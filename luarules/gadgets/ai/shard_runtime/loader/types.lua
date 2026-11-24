-- The AI types and their objects, on the hosting client. Unsynced.
--
-- Loads the runtime and each AI type once, into its own environment, builds the objects of an AI (its team
-- object, and the ShardAlly and ShardGlobal objects it shares), gives each AI its random seed, and leaves
-- unloaded an AI whose loading fails: the type or the runtime that failed is remembered, and the ShardAlly
-- objects the failed load created are taken back.

local spEcho = Spring.Echo
local spGetTeamInfo = Spring.GetTeamInfo
local spAreTeamsAllied = Spring.AreTeamsAllied

-- Lua numbers are single precision floats in the engine: seeds stay below 2^24 at every step,
-- as 65520 * 31 + 255 does
local SEED_MODULUS = 65521 -- the largest prime below 2^16

local runtimeInclude = nil -- boot.lua's shard_include: runtime files only
local gameHash = nil
local failedTypes = {} -- AI name -> the error that stopped the type from loading
local runtimeFailure = nil -- the error that stopped the runtime from loading
local newAllies = nil ---@type table[]? while an AI loads, the ShardAlly objects created for it

-- given by Setup
local gadget ---@type table the gadget, whose environment the AI types fall back on
local aiTeams ---@type table<integer, string> teamID -> AI name, for the teams with a Shard AI
local teamList ---@type integer[]
local AI_PATH ---@type string
local RUNTIME_PATH ---@type string
local WithTraceback ---@type fun(err: any): string
local NewUnitTables ---@type fun(thisAI: table)
local schedulerState ---@type table

--- context = { gadget, aiTeams, teamList, aiPath, runtimePath, Delivery, UnitRegistry, Scheduler }
local function Setup(context)
	gadget = context.gadget
	aiTeams = context.aiTeams
	teamList = context.teamList
	AI_PATH = context.aiPath
	RUNTIME_PATH = context.runtimePath
	WithTraceback = context.Delivery.WithTraceback
	NewUnitTables = context.UnitRegistry.NewUnitTables
	schedulerState = context.Scheduler.state
end

-- runtime and seeds ---------------------------------------------------------------------------------

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

--- The seed of an AI team, written to the log
local function TeamSeed(teamID)
	local hash = gameHash --[[@as integer]]
	local seed = (hash * 31 + teamID + 1) % SEED_MODULUS
	spEcho("[AI Loader] AI team " .. teamID .. " random seed " .. seed)
	return seed
end

local function SetGameHash(gameID)
	gameHash = HashGameID(gameID)
end

--- The seeds of the game and of each AI, from the GameID: the old Shard.randomseed was the sum of the bytes,
--- the same for every AI
local function SeedAIs(gameID)
	Shard.gameID = gameID
	Shard.randomseed = gameHash
	for _, thisAI in ipairs(Shard.AIs) do
		thisAI.randomseed = TeamSeed(thisAI.id)
	end
end

-- AI objects ---------------------------------------------------------------------------------------

-- an object of a type whose class declares MScheduler gets the list; with MScheduler or BScheduler, the
-- scheduler's state of the turn
local function SetSchedule(target, aiType)
	local class = aiType.class
	local names = class.MScheduler
	if names ~= nil then
		target.MScheduler = names
	end
	if names ~= nil or class.BScheduler ~= nil then
		target.scheduler = schedulerState
	end
end

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
	}
	---@diagnostic disable-next-line: call-non-callable
	local global = ShardGlobal()
	global.loaded = false
	global.fullname = aiName
	global.api = NewAPI(aiType)
	global.AIs = {}
	SetSchedule(global, aiType)
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
	ally.api = NewAPI(aiType)
	ally.global = aiType.global
	ally.AIs = {}
	SetSchedule(ally, aiType)
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
	thisAI.api = NewAPI(aiType)
	thisAI.global = aiType.global
	thisAI.ally = GetAlly(aiType, allyId)
	---@diagnostic disable-next-line: call-non-callable
	thisAI.outbox = ShardOutbox(id)
	SetSchedule(thisAI, aiType)
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

--- A type whose global object failed to initialise: its other teams do not load
local function MarkTypeFailed(aiName, reason)
	failedTypes[aiName] = reason
	Shard.types[aiName] = nil
end

--- Loads the AI of team id; an error leaves it unloaded, and the other AIs and LuaRules go on
local function LoadAI(id)
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
	return result
end

return {
	Setup = Setup,
	HashGameID = HashGameID,
	SetGameHash = SetGameHash,
	SeedAIs = SeedAIs,
	LoadAI = LoadAI,
	MarkTypeFailed = MarkTypeFailed,
	RemoveValue = RemoveValue,
	RemoveAlly = RemoveAlly,
}
