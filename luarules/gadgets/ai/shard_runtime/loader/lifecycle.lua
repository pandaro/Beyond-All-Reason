-- The life of the AIs on the hosting client: start, stop, catch-up and change of host. Unsynced.
--
-- Starts the objects global -> ally team -> team and drops an object whose Init() fails with the AIs that rely
-- on it, stops an AI, catches up with the units that already exist after a reload or a change of host, follows
-- the changes of host the synced side reports, and sends each AI's orders.

local spEcho = Spring.Echo
local spGetGameFrame = Spring.GetGameFrame
local spGetMyPlayerID = Spring.GetMyPlayerID
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spGetTeamStartPosition = Spring.GetTeamStartPosition
local spSendLuaRulesMsg = Spring.SendLuaRulesMsg
local spGetAllUnits = Spring.GetAllUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitLosState = Spring.GetUnitLosState

local myPlayerID = spGetMyPlayerID()
local hosting = false -- this client runs at least one AI
local started = false -- the AIs have been initialised

-- given by Setup
local gadget ---@type table the gadget, whose call-ins CatchUp calls
local aiTeams ---@type table<integer, string> teamID -> AI name, for the teams with a Shard AI
local teamList ---@type integer[]
local Call ---@type fun(target: table, name: string, ...): boolean
local SetCatchUpTargets ---@type fun(targets: table?)
local SetUnitTableTargets ---@type fun(targets: table?)
local LoadAI ---@type fun(id: integer): table?
local MarkTypeFailed ---@type fun(aiName: string, reason: string)
local RemoveValue ---@type fun(list: table, value: any)
local RemoveAlly ---@type fun(ally: table)
local Types ---@type table
local Changed ---@type fun()
local AIAdded ---@type fun(thisAI: table)

--- context = { gadget, aiTeams, teamList, Types, Delivery, UnitRegistry, Scheduler, MemStats }
local function Setup(context)
	gadget = context.gadget
	aiTeams = context.aiTeams
	teamList = context.teamList
	Types = context.Types
	LoadAI = Types.LoadAI
	MarkTypeFailed = Types.MarkTypeFailed
	RemoveValue = Types.RemoveValue
	RemoveAlly = Types.RemoveAlly
	Call = context.Delivery.Call
	SetCatchUpTargets = context.Delivery.SetCatchUpTargets
	SetUnitTableTargets = context.UnitRegistry.SetUnitTableTargets
	Changed = context.Scheduler.Changed
	AIAdded = context.MemStats.AIAdded
end

--- Loads the AI of team id and hosts it here; nil when it failed to load
local function AddAI(id)
	local thisAI = LoadAI(id)
	if thisAI ~= nil then
		Shard.AIsByTeamID[id] = thisAI
		Shard.AIs[#Shard.AIs + 1] = thisAI
		thisAI.index = #Shard.AIs
		hosting = true
		Changed()
		AIAdded(thisAI)
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
	Changed()
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
				MarkTypeFailed(target.fullname, "its global object failed to initialise")
			end
		end
	end
end

-- initialise every object not loaded yet, global -> ally team -> team, so that a module finds the
-- shared modules already initialised; returns the objects it started. GameStart calls it again after
-- the start units have started the AIs, so it collects only when it started something
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
	if next(fresh) ~= nil then
		collectgarbage("collect") -- clean up after the start-up analyses of the AIs
	end
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
	SetUnitTableTargets(targets)
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
	SetUnitTableTargets(nil)
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
		return
	end
	-- clean start, as in the old loader
	collectgarbage("collect")
end

--- Each AI's queue of orders becomes at most one message
local function FlushOrders(n)
	local AIs = Shard.AIs
	for i = 1, #AIs do
		AIs[i].outbox:Flush(n, spSendLuaRulesMsg)
	end
end

--- The seeds of the game, and of each AI when this client hosts some
local function SetGameID(gameID)
	Types.SetGameHash(gameID)
	if not hosting then
		return
	end
	Types.SeedAIs(gameID)
end

return {
	Setup = Setup,
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
