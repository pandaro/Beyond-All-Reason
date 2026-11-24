-- Loading and life of the AIs on the hosting client. Unsynced.
--
-- Loads the runtime and each AI type once, builds the objects of an AI (its team object, and the ShardAlly
-- and ShardGlobal objects it shares), gives each AI its random seed, and leaves unloaded an AI whose loading
-- or Init() fails. Starts the objects global -> ally team -> team, stops an AI, catches up with the units that
-- already exist after a reload, and follows the changes of host the synced side reports.

local spEcho = Spring.Echo
local spGetTeamInfo = Spring.GetTeamInfo
local spGetGameFrame = Spring.GetGameFrame
local spGetMyPlayerID = Spring.GetMyPlayerID
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spGetTeamStartPosition = Spring.GetTeamStartPosition
local spAreTeamsAllied = Spring.AreTeamsAllied
local spSendLuaRulesMsg = Spring.SendLuaRulesMsg
local spGetAllUnits = Spring.GetAllUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitLosState = Spring.GetUnitLosState

-- Lua numbers are single precision floats in the engine: seeds stay below 2^24 at every step,
-- as 65520 * 31 + 255 does
local SEED_MODULUS = 65521 -- the largest prime below 2^16

local myPlayerID = spGetMyPlayerID()
local hosting = false -- this client runs at least one AI
local started = false -- the AIs have been initialised
local runtimeInclude = nil -- boot.lua's shard_include: runtime files only
local gameHash = nil
local failedTypes = {} -- AI name -> the error that stopped the type from loading
local runtimeFailure = nil -- the error that stopped the runtime from loading
local newAllies = nil ---@type table[]? while an AI loads, the ShardAlly objects created for it

-- given by Setup
local gadget ---@type table the gadget, whose environment the AI types fall back on and whose call-ins CatchUp calls
local aiTeams ---@type table<integer, string> teamID -> AI name, for the teams with a Shard AI
local teamList ---@type integer[]
local AI_PATH ---@type string
local RUNTIME_PATH ---@type string
local Call ---@type fun(target: table, name: string, ...): boolean
local WithTraceback ---@type fun(err: any): string
local SetCatchUpTargets ---@type fun(targets: table?)
local NewUnitTables ---@type fun(thisAI: table)

--- The loader's parts: context = { gadget, aiTeams, teamList, aiPath, runtimePath, Delivery, UnitRegistry }
local function Setup(context)
	gadget = context.gadget
	aiTeams = context.aiTeams
	teamList = context.teamList
	AI_PATH = context.aiPath
	RUNTIME_PATH = context.runtimePath
	Call = context.Delivery.Call
	WithTraceback = context.Delivery.WithTraceback
	SetCatchUpTargets = context.Delivery.SetCatchUpTargets
	NewUnitTables = context.UnitRegistry.NewUnitTables
end

-- the runtime is loaded only by a client that hosts an AI
local function LoadRuntime()
	if Shard ~= nil then
		return
	end

	-- globals of the gadget environment, read by the runtime and by the AI types
	---@diagnostic disable-next-line: global-in-non-module
	ShardSpringLua = true

	VFS.Include(RUNTIME_PATH .. "/spring_lua/boot.lua")
	runtimeInclude = shard_include

	---@diagnostic disable-next-line: global-in-non-module
	Shard = VFS.Include(RUNTIME_PATH .. "/spring_lua/shard.lua")
	Shard.AIs = {}
	Shard.AIsByTeamID = {}
	Shard.alliesByAllyID = {} -- allyTeamID -> ShardAlly objects, one per AI type
	Shard.globals = {} -- ShardGlobal objects, one per AI type
	Shard.types = {} -- AI name -> AI type read by LoadAIType
end

--- The seed of a game, the same on every client: a hash of the GameID bytes below SEED_MODULUS
---@param gameID string
---@return integer
local function HashGameID(gameID)
	local hash = 0
	for i = 1, #gameID do
		hash = (hash * 31 + string.byte(gameID, i)) % SEED_MODULUS
	end
	return hash
end

local function TeamSeed(teamID)
	local hash = gameHash --[[@as integer]]
	local seed = (hash * 31 + teamID + 1) % SEED_MODULUS
	spEcho("[AI Loader] AI team " .. teamID .. " random seed " .. seed)
	return seed
end

-- AI setup -------------------------------------------------------------------------------------

-- api.lua builds a new game and map for every object, as before: it must not go through the AI
-- type's include, which runs each file once
local function NewAPI(aiType)
	shard_include = runtimeInclude
	local api = VFS.Include(RUNTIME_PATH .. "/api.lua")
	api.shard_include = aiType.env.shard_include
	return api
end

-- each AI type is read once, into its own environment: its classes do not overwrite those of
-- another AI, and every AI of the type shares the same classes
local function LoadAIType(aiName)
	local aiType = Shard.types[aiName]
	if aiType ~= nil then
		return aiType
	end
	local env = setmetatable({}, { __index = gadget })
	env.shard_include = shard_generate_include_func(RUNTIME_PATH, AI_PATH .. aiName, env)
	local first = VFS.Include(AI_PATH .. aiName .. "/boot.lua", env)
	if type(first) ~= "table" then
		spEcho("AI type " .. aiName .. ": boot.lua did not return an AI")
		return nil
	end
	aiType = {
		name = aiName,
		env = env,
		first = first, -- the instance boot.lua returned goes to the first team
		class = getmetatable(first), -- the other teams get new instances of the same class
		omniscient = first.Perception ~= nil and first:Perception() == "omniscient",
	}
	---@diagnostic disable-next-line: call-non-callable
	local global = ShardGlobal()
	global.loaded = false
	global.fullname = aiName
	global.omniscient = aiType.omniscient
	global.api = NewAPI(aiType)
	global.AIs = {}
	aiType.global = global
	Shard.globals[#Shard.globals + 1] = global
	Shard.types[aiName] = aiType
	return aiType
end

local function GetAlly(aiType, allyId)
	local allies = Shard.alliesByAllyID[allyId]
	if allies == nil then
		allies = {}
		Shard.alliesByAllyID[allyId] = allies
	end
	for i = 1, #allies do
		if allies[i].fullname == aiType.name then
			return allies[i]
		end
	end
	---@diagnostic disable-next-line: call-non-callable
	local ally = ShardAlly()
	ally.loaded = false
	ally.allyId = allyId
	ally.fullname = aiType.name
	ally.omniscient = aiType.omniscient
	ally.api = NewAPI(aiType)
	ally.global = aiType.global
	ally.AIs = {}
	allies[#allies + 1] = ally
	if newAllies ~= nil then
		newAllies[#newAllies + 1] = ally
	end
	return ally
end

local function SetupAI(id)
	local aiInfo = aiTeams[id]
	spEcho("AI Player " .. id .. " is a " .. aiInfo)
	local aiType = LoadAIType(aiInfo)
	if aiType == nil then
		return nil
	end

	local thisAI = aiType.first or aiType.class()
	aiType.first = nil
	thisAI.loaded = false
	thisAI.id = id
	local _, _, _, _, side, allyId = spGetTeamInfo(id, false)
	thisAI.allyId = allyId
	thisAI.side = side
	thisAI.fullname = aiInfo
	thisAI.omniscient = aiType.omniscient
	thisAI.api = NewAPI(aiType)
	thisAI.global = aiType.global
	thisAI.ally = GetAlly(aiType, allyId)
	---@diagnostic disable-next-line: call-non-callable
	thisAI.outbox = ShardOutbox(id)
	if gameHash ~= nil then
		thisAI.randomseed = TeamSeed(id)
	end

	local alliedTeamIds = {}
	local enemyTeamIds = {}
	for i = 1, #teamList do
		if spAreTeamsAllied(thisAI.id, teamList[i]) then
			alliedTeamIds[teamList[i]] = true
		else
			enemyTeamIds[teamList[i]] = true
		end
	end
	thisAI.alliedTeamIds = alliedTeamIds
	thisAI.enemyTeamIds = enemyTeamIds
	NewUnitTables(thisAI)

	local allyAIs = thisAI.ally.AIs
	allyAIs[#allyAIs + 1] = thisAI
	local globalAIs = thisAI.global.AIs
	globalAIs[#globalAIs + 1] = thisAI
	return thisAI
end

local function RemoveValue(list, value)
	for i = #list, 1, -1 do
		if list[i] == value then
			table.remove(list, i)
		end
	end
end

local function RemoveAlly(ally)
	local allies = Shard.alliesByAllyID[ally.allyId]
	if allies == nil then
		return
	end
	RemoveValue(allies, ally)
	if allies[1] == nil then
		Shard.alliesByAllyID[ally.allyId] = nil
	end
end

-- the ShardAlly objects a failed load created and left without AIs
local function RemoveNewAllies(allies)
	for i = 1, #allies do
		if allies[i].AIs[1] == nil then
			RemoveAlly(allies[i])
		end
	end
end

local function LoadingFailed(id, err)
	spEcho("[AI Loader] error loading " .. tostring(aiTeams[id]) .. " for team " .. id .. ": " .. tostring(err))
end

-- loads the AI of team id; an error leaves it unloaded, and the other AIs and LuaRules go on
local function AddAI(id)
	local aiName = aiTeams[id]
	local known = runtimeFailure or failedTypes[aiName]
	if known ~= nil then
		LoadingFailed(id, known)
		return nil
	end
	newAllies = {}
	local ok, result = xpcall(function()
		LoadRuntime()
		return SetupAI(id)
	end, WithTraceback)
	local allies = newAllies
	newAllies = nil
	if not ok then
		if Shard == nil or Shard.AIs == nil then
			runtimeFailure = result
		elseif Shard.types[aiName] == nil then
			failedTypes[aiName] = result
		end
		if Shard ~= nil and Shard.alliesByAllyID ~= nil then
			RemoveNewAllies(allies)
		end
		LoadingFailed(id, result)
		return nil
	end
	local thisAI = result
	if thisAI ~= nil then
		Shard.AIsByTeamID[id] = thisAI
		Shard.AIs[#Shard.AIs + 1] = thisAI
		thisAI.index = #Shard.AIs
		hosting = true
	end
	return thisAI
end

-- the AI of teamID stops here: no more events nor updates, and its queued orders are dropped
local function StopAI(teamID, reason)
	local thisAI = Shard.AIsByTeamID[teamID]
	if thisAI == nil then
		return
	end
	spEcho("[AI Loader] AI team " .. teamID .. " " .. reason .. ": stopped on this client")
	thisAI.outbox:Reset()
	Shard.AIsByTeamID[teamID] = nil
	RemoveValue(Shard.AIs, thisAI)
	RemoveValue(thisAI.ally.AIs, thisAI)
	RemoveValue(thisAI.global.AIs, thisAI)
	for i = 1, #Shard.AIs do
		Shard.AIs[i].index = i
	end
	hosting = Shard.AIs[1] ~= nil
end

-- Init() runs on the first Prepare(), as in Shard; an object whose Init() failed goes to `failed`
local function StartObject(target, fresh, failed)
	if target.loaded == true then
		return
	end
	fresh[target] = true
	if not Call(target, "Prepare") then
		failed[#failed + 1] = target
	end
end

-- an object whose Init() failed leaves the lists, and so do the AIs that rely on it: a shared
-- object half initialised would fail its AIs in every call
local function DropFailed(failed)
	for i = 1, #failed do
		local target = failed[i]
		local scope = target:Scope()
		if scope == "team" then
			StopAI(target.id, "failed to initialise")
		else
			local AIs = target.AIs
			for j = #AIs, 1, -1 do
				StopAI(AIs[j].id, "lost its " .. scope .. " object, which failed to initialise")
			end
			if scope == "ally" then
				RemoveAlly(target)
			else
				RemoveValue(Shard.globals, target)
				failedTypes[target.fullname] = "its global object failed to initialise"
				Shard.types[target.fullname] = nil
			end
		end
	end
end

-- initialise every object not loaded yet, global -> ally team -> team, so that a module finds the
-- shared modules already initialised; returns the objects it started
local function StartAIs()
	started = true
	local fresh = {}
	local failed = {}
	for _, global in ipairs(Shard.globals) do
		StartObject(global, fresh, failed)
	end
	DropFailed(failed)
	failed = {}
	for _, allies in pairs(Shard.alliesByAllyID) do
		for _, ally in ipairs(allies) do
			StartObject(ally, fresh, failed)
		end
	end
	DropFailed(failed)
	failed = {}
	for _, thisAI in ipairs(Shard.AIs) do
		if thisAI.loaded ~= true then
			local x, y, z = spGetTeamStartPosition(thisAI.id)
			thisAI.startPos = { x, y, z }
		end
		StartObject(thisAI, fresh, failed)
	end
	DropFailed(failed)
	return fresh
end

--- Whether this client runs at least one AI
local function IsHosting()
	return hosting
end

--- The first event or the first frame starts the AIs, as the lazy Init() of Prepare() did
local function StartAIsOnce()
	if not started then
		StartAIs()
	end
end

-- regenerate the events of the units that already exist, as the old loader did after a reload;
-- only the objects in targets hear them
local function CatchUp(targets)
	SetCatchUpTargets(targets)
	local units = spGetAllUnits()
	for i = 1, #units do
		local unitID = units[i]
		local unitDefID = spGetUnitDefID(unitID) --[[@as integer]]
		local teamID = spGetUnitTeam(unitID) --[[@as integer]]
		---@diagnostic disable-next-line: need-check-nil
		gadget:UnitCreated(unitID, unitDefID, teamID)
		-- the old loader reported nanoframes as finished too
		local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
		if buildProgress == nil or buildProgress >= 1 then
			---@diagnostic disable-next-line: need-check-nil
			gadget:UnitFinished(unitID, unitDefID, teamID)
		end
		local unitAllyId = spGetUnitAllyTeam(unitID)
		for allyId, _ in pairs(Shard.alliesByAllyID) do
			if allyId ~= unitAllyId then
				local state = spGetUnitLosState(unitID, allyId, true)
				if state ~= nil and state % 4 >= 2 then
					gadget:UnitEnteredRadar(unitID, teamID, allyId, unitDefID)
				end
				if state ~= nil and state % 2 == 1 then
					gadget:UnitEnteredLos(unitID, teamID, allyId, unitDefID)
				end
			end
		end
	end
	SetCatchUpTargets(nil)
end

-- the synced side moved an AI team to another host, because its host left the game
local function HostChanged(_, teamID, hostPlayerID)
	if aiTeams[teamID] == nil then
		return
	end
	local hostedHere = Shard ~= nil and Shard.AIsByTeamID[teamID] ~= nil
	if hostPlayerID ~= myPlayerID then
		if hostedHere then
			StopAI(teamID, "moved to another host")
		end
		return
	end
	if hostedHere then
		return
	end
	spEcho("[AI Loader] taking over AI team " .. teamID .. ": its memory is lost, the world is rebuilt from the units")
	if AddAI(teamID) == nil then
		return
	end
	-- only the objects created now hear the catch-up; a ShardGlobal that already existed does not
	-- get the units of the new ally team again
	if started or spGetGameFrame() > 0 then
		CatchUp(StartAIs())
	end
end

local function RelayRejected(_, teamID, count)
	local thisAI = hosting and Shard.AIsByTeamID[teamID]
	if thisAI then
		thisAI.outbox.rejected = (thisAI.outbox.rejected or 0) + count
	end
end

-- the teams this client hosts, by the aiHostPlayer team rules param of the synced side
local function AddHostedAIs()
	for i = 1, #teamList do
		local id = teamList[i]
		if aiTeams[id] ~= nil and spGetTeamRulesParam(id, "aiHostPlayer") == myPlayerID then
			AddAI(id)
		end
	end
end

-- after LuaRules is reloaded in a running game, the AIs start at once and hear the units that exist
local function CatchUpAfterReload()
	if spGetGameFrame() > 0 then
		CatchUp(StartAIs())
	end
end

--- Each AI's queue of orders becomes at most one message
local function FlushOrders(n)
	local AIs = Shard.AIs
	for i = 1, #AIs do
		AIs[i].outbox:Flush(n, spSendLuaRulesMsg)
	end
end

--- The seeds of the game and of each AI, from the GameID: the old Shard.randomseed was the sum of the bytes,
--- the same for every AI
local function SetGameID(gameID)
	gameHash = HashGameID(gameID)
	if not hosting then
		return
	end
	Shard.gameID = gameID
	Shard.randomseed = gameHash
	for _, thisAI in ipairs(Shard.AIs) do
		thisAI.randomseed = TeamSeed(thisAI.id)
	end
end

return {
	Setup = Setup,
	HashGameID = HashGameID,
	IsHosting = IsHosting,
	AddHostedAIs = AddHostedAIs,
	StartAIs = StartAIs,
	StartAIsOnce = StartAIsOnce,
	CatchUpAfterReload = CatchUpAfterReload,
	HostChanged = HostChanged,
	RelayRejected = RelayRejected,
	FlushOrders = FlushOrders,
	SetGameID = SetGameID,
}
