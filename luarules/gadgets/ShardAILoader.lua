local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Shard AI Loader",
		desc = "Shard by AF for Spring Lua",
		author = "eronoobos, based on gadget by raaar, and original AI by AF, maintained by Pandaro(bio)",
		date = "November 2026",
		license = "GPL",
		layer = 999999,
		enabled = true,
	}
end

-- Loader of the Lua AIs written for the Shard runtime (luarules/gadgets/ai/<AI name>/boot.lua).
-- The AIs run only on the client that hosts their ally team; the synced side registers that host in the
-- public team rules param "aiHostPlayer" and relays the binary order messages of shard_runtime/ordercodec.lua,
-- only from the host of a team and only for units of that team.

local spEcho = Spring.Echo
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamLuaAI = Spring.GetTeamLuaAI
local spGetGameFrame = Spring.GetGameFrame
local teamList = Spring.GetTeamList()

local AI_PATH = "luarules/gadgets/ai/"
local RUNTIME_PATH = "luarules/gadgets/ai/shard_runtime"

-- teams whose Lua AI has a Shard boot.lua
local aiTeams = {}
local shardEnabled = false

for i = 1, #teamList do
	local luaAI = spGetTeamLuaAI(teamList[i])
	if type(luaAI) == "string" and luaAI ~= "" and VFS.FileExists(AI_PATH .. luaAI .. "/boot.lua") then
		aiTeams[teamList[i]] = luaAI
		shardEnabled = true
	end
end

if not shardEnabled then
	spEcho("[AI Loader] ShardLua bot Deactivated!")
	return false
end

-- unit IDs travel as U16 in the order messages
---@diagnostic disable-next-line: unnecessary-if
if Game.maxUnits > 65536 then
	spEcho("[AI Loader] Game.maxUnits does not fit the order format: ShardLua bot Deactivated!")
	return false
end

spEcho("[AI Loader] ShardLua bot Activated!")

if gadgetHandler:IsSyncedCode() then
	-- SYNCED CODE: host registry and order relay. No AI code runs here.

	local OrderCodec = VFS.Include(RUNTIME_PATH .. "/ordercodec.lua")

	local spGetAIInfo = Spring.GetAIInfo
	local spGetPlayerInfo = Spring.GetPlayerInfo
	local spGetPlayerList = Spring.GetPlayerList
	local spSetTeamRulesParam = Spring.SetTeamRulesParam
	local spValidUnitID = Spring.ValidUnitID
	local spGetUnitTeam = Spring.GetUnitTeam
	local spGiveOrderToUnit = Spring.GiveOrderToUnit
	local spGiveOrderArrayToUnit = Spring.GiveOrderArrayToUnit
	local spUnpackF32 = VFS.UnpackF32
	local isOrderMessage = OrderCodec.IsOrderMessage
	local unpackHeader = OrderCodec.UnpackHeader
	local unpackOrder = OrderCodec.UnpackOrder

	local MAX_ORDERS_PER_MESSAGE = 4000
	local MAX_MESSAGES_PER_FRAME = 2 -- per team and emission frame, never per arrival frame
	local MAX_FRAME_AGE = 900 -- oldest accepted emission frame, in frames
	local PUBLIC = { public = true }

	local aiHostPlayer = {} -- teamID -> the only playerID whose messages give orders to that team
	local lastSeq = {} ---@type table<integer, number?> teamID -> last accepted seq
	local lastFrame = {} ---@type table<integer, number?> teamID -> emission frame of the last accepted message
	local messagesInFrame = {} -- teamID -> accepted messages with that emission frame
	local relayCounter = { messages = 0, orders = 0, rejectedOrders = 0, rejected = {} }

	local function IsActive(playerID)
		local _, active = spGetPlayerInfo(playerID, false)
		return active == true
	end

	-- deterministic successor: an active player of the same ally team, then any active player,
	-- then an active spectator; the lowest playerID wins
	local function ChooseSuccessor(allyId, removedPlayerID)
		local best, bestRank = nil, nil
		local players = spGetPlayerList(-1, true) or {}
		for i = 1, #players do
			local playerID = players[i] --[[@as integer]]
			if playerID ~= removedPlayerID then
				local _, active, spectator, _, playerAllyId = spGetPlayerInfo(playerID, false)
				if active then
					local rank = 3
					if not spectator then
						rank = (playerAllyId == allyId) and 1 or 2
					end
					if bestRank == nil or rank < bestRank or (rank == bestRank and playerID < best) then
						best = playerID
						bestRank = rank
					end
				end
			end
		end
		return best
	end

	-- One host per ally team: all its AI teams run on one client, so the ally scope exists once.
	-- The AI team with the lowest teamID decides: its current host, or the player that added it in
	-- the lobby, stays while active. teamList keeps the order deterministic.
	local function RegisterHosts(removedPlayerID, checkActive)
		local hostByAlly = {}
		for i = 1, #teamList do
			local teamID = teamList[i]
			if aiTeams[teamID] ~= nil then
				local _, _, _, _, _, allyId = spGetTeamInfo(teamID, false)
				if hostByAlly[allyId] == nil then
					local _, _, hostingPlayerID = spGetAIInfo(teamID)
					local host = aiHostPlayer[teamID] or hostingPlayerID ---@type integer?
					if host == nil or host == removedPlayerID or (checkActive and not IsActive(host)) then
						host = ChooseSuccessor(allyId, removedPlayerID)
					end
					hostByAlly[allyId] = host or -1 -- -1: nobody can host it
				end
				local host = hostByAlly[allyId]
				local previous = aiHostPlayer[teamID]
				if previous ~= host then
					aiHostPlayer[teamID] = host
					lastSeq[teamID] = nil -- the new host counts from 1
					lastFrame[teamID] = nil
					spSetTeamRulesParam(teamID, "aiHostPlayer", host, PUBLIC)
					if previous ~= nil then
						SendToUnsynced("shard_host", teamID, host)
					end
					spEcho("[AI Loader] AI team " .. teamID .. " hosted by player " .. host)
				end
			end
		end
	end

	-- orders of the unit being decoded; these tables are reused, only the params tables are new
	local cmdArray = {} ---@type table[]
	local cmdCount = 0
	local cmdPool = {} ---@type table[]

	local function AddOrder(cmdID, params, options)
		cmdCount = cmdCount + 1
		local cmd = cmdPool[cmdCount]
		if cmd == nil then
			cmd = {}
			cmdPool[cmdCount] = cmd
		end
		cmd[1] = cmdID
		cmd[2] = params
		cmd[3] = options
		cmdArray[cmdCount] = cmd
	end

	-- consecutive orders of one unit become one engine call
	local function GiveOrders(unitID)
		if cmdCount == 1 then
			local cmd = cmdArray[1] --[[@as table]]
			spGiveOrderToUnit(unitID, cmd[1], cmd[2], cmd[3])
		elseif cmdCount > 1 then
			spGiveOrderArrayToUnit(unitID, cmdArray)
		end
		-- the engine reads the whole table with next(): empty it, shortening is not enough
		for i = 1, cmdCount do
			cmdArray[i] = nil
		end
		relayCounter.orders = relayCounter.orders + cmdCount
		cmdCount = 0
	end

	local function Reject(reason)
		relayCounter.rejected[reason] = (relayCounter.rejected[reason] or 0) + 1
		return true -- the message is ours all the same: no other gadget parses it
	end

	function gadget:Initialize()
		-- before the game starts players may still be connecting: keep the hosts chosen in the lobby
		RegisterHosts(nil, spGetGameFrame() > 0)
		-- UnitMoveFailed: the engine sends it only to synced code, only for unit defs watched with
		-- Script.SetWatchUnit, and luarules/gadgets.lua keeps it among the commented optional call-ins.
		-- Until both change the AIs do not receive it (the old loader did not forward it either).
	end

	function gadget:GameStart()
		RegisterHosts(nil, true)
	end

	function gadget:PlayerRemoved(playerID, reason)
		RegisterHosts(playerID, true)
	end

	function gadget:RecvLuaMsg(msg, playerID)
		if not isOrderMessage(msg) then
			return false
		end
		relayCounter.messages = relayCounter.messages + 1
		local version, teamID, seq, frame, count, position = unpackHeader(msg)
		if version == nil then
			return Reject("size")
		end
		if version ~= OrderCodec.VERSION then
			return Reject("version")
		end
		-- playerID comes from the server: a client cannot fake it
		if aiHostPlayer[teamID] ~= playerID then
			return Reject("sender")
		end
		if seq <= (lastSeq[teamID] or 0) then
			return Reject("seq")
		end
		local now = spGetGameFrame()
		if frame > now or frame < now - MAX_FRAME_AGE then
			return Reject("frame")
		end
		-- emission frames never go back, so alternating frames cannot dodge the limit per frame
		local previousFrame = lastFrame[teamID]
		if previousFrame ~= nil and frame < previousFrame then
			return Reject("frame")
		end
		-- before the limit per frame, so that a rejected message does not use up a place
		if count > MAX_ORDERS_PER_MESSAGE then
			return Reject("count")
		end
		if frame == previousFrame then
			if messagesInFrame[teamID] >= MAX_MESSAGES_PER_FRAME then
				return Reject("rate")
			end
			messagesInFrame[teamID] = messagesInFrame[teamID] + 1
		else
			lastFrame[teamID] = frame
			messagesInFrame[teamID] = 1
		end
		lastSeq[teamID] = seq

		local currentUnit = nil
		local unitAllowed = false
		local rejectedOrders = 0
		for i = 1, count do
			local unitID, cmdID, options, paramCount, paramsPosition, nextPosition = unpackOrder(msg, position)
			if unitID == nil then
				rejectedOrders = rejectedOrders + count - i + 1
				break
			end
			if unitID ~= currentUnit then
				GiveOrders(currentUnit)
				currentUnit = unitID
				unitAllowed = spValidUnitID(unitID) and spGetUnitTeam(unitID) == teamID
			end
			if unitAllowed then
				local params = nil
				if paramCount == 1 then
					params = spUnpackF32(msg, paramsPosition)
				elseif paramCount > 1 then
					---@diagnostic disable-next-line: redundant-parameter
					local values = spUnpackF32(msg, paramsPosition, paramCount) --[[@as table]]
					values.n = nil -- the engine reads params with next() too: keep only the values
					params = values
				end
				AddOrder(cmdID, params, options)
			else
				rejectedOrders = rejectedOrders + 1
			end
			position = nextPosition
		end
		GiveOrders(currentUnit)

		if rejectedOrders > 0 then
			relayCounter.rejectedOrders = relayCounter.rejectedOrders + rejectedOrders
			SendToUnsynced("shard_relay_rejected", teamID, rejectedOrders)
		end
		return true
	end

	function gadget:Shutdown()
		spEcho("Shard AI sync gadget shutdown")
		spEcho(
			"Shard relay:",
			relayCounter.messages,
			"messages,",
			relayCounter.orders,
			"orders given,",
			relayCounter.rejectedOrders,
			"orders rejected"
		)
		for reason, count in pairs(relayCounter.rejected) do
			spEcho("Shard relay: " .. count .. " messages rejected (" .. reason .. ")")
		end
	end
else
	-- UNSYNCED CODE: the AIs, only on the client that hosts them

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
	local gaiaTeamID = Spring.GetGaiaTeamID()
	local traceback = debug and debug.traceback

	-- Lua numbers are single precision floats in the engine: seeds stay below 2^24 at every step,
	-- as 65520 * 31 + 255 does
	local SEED_MODULUS = 65521 -- the largest prime below 2^16
	local ERROR_REPORT_FRAMES = 900 -- the same error of an object in a call-in is written once per 30 s of game

	local myPlayerID = spGetMyPlayerID()
	local hosting = false -- this client runs at least one AI
	local started = false -- the AIs have been initialised
	local catchUpTargets = nil -- while catching up, only these objects hear the events
	local runtimeInclude = nil -- boot.lua's shard_include: runtime files only
	local gameHash = nil
	local memoryRecord = 0

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
	function gadget:HashGameID(gameID)
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

	-- calls into the objects ---------------------------------------------------------------------------

	local reportedErrors = setmetatable({}, { __mode = "k" }) -- object -> call-in -> game frame of the last report

	local function ObjectLabel(target)
		local scope = target:Scope()
		if scope == "ally" then
			return tostring(target.fullname) .. " ally team " .. tostring(target.allyId)
		elseif scope == "global" then
			return tostring(target.fullname) .. " global"
		end
		return tostring(target.fullname) .. " team " .. tostring(target.id)
	end

	local function ReportError(target, name, err)
		local byName = reportedErrors[target]
		if byName == nil then
			byName = {}
			reportedErrors[target] = byName
		end
		local frame = spGetGameFrame()
		local last = byName[name]
		if last ~= nil and frame - last < ERROR_REPORT_FRAMES then
			return
		end
		byName[name] = frame
		spEcho("[AI Loader] error in " .. ObjectLabel(target) .. ", " .. name .. ": " .. tostring(err))
	end

	local function WithTraceback(err)
		---@diagnostic disable-next-line: unnecessary-if
		if traceback then
			return traceback(tostring(err), 2)
		end
		return tostring(err)
	end

	-- the call being made, in upvalues rather than a closure so that a call allocates nothing
	local callTarget ---@type any
	local callName ---@type any
	local callA, callB, callC, callD

	local function ProtectedCall()
		callTarget:Prepare()
		if callName ~= "Prepare" then
			callTarget[callName](callTarget, callA, callB, callC, callD)
		end
	end

	-- Prepare() and then target[name](...): an error is written and stops only this call
	local function Call(target, name, a, b, c, d)
		local savedTarget, savedName, savedA, savedB, savedC, savedD = callTarget, callName, callA, callB, callC, callD
		callTarget, callName, callA, callB, callC, callD = target, name, a, b, c, d
		local ok, err = xpcall(ProtectedCall, WithTraceback)
		callTarget, callName, callA, callB, callC, callD = savedTarget, savedName, savedA, savedB, savedC, savedD
		if not ok then
			ReportError(target, name, err)
		end
	end

	-- A ShardAlly or ShardGlobal whose AI type has no module of its scope has nothing to run, and
	-- ShardAI would warn at every unit that it has no modules.
	local function HasModules(target)
		local modules = target.modules
		return modules == nil or modules[1] ~= nil
	end

	-- event delivery ---------------------------------------------------------------------------------
	-- Provisional, as the old loader did: every object hears every unit event, whether or not one of its
	-- modules wants it or its ally team can see the unit.

	local function Deliver(target, name, a, b, c, d)
		if catchUpTargets ~= nil and catchUpTargets[target] == nil then
			return
		end
		if HasModules(target) then
			Call(target, name, a, b, c, d)
		end
	end

	local function DeliverToShared(name, a, b, c, d)
		local globals = Shard.globals
		for i = 1, #globals do
			Deliver(globals[i], name, a, b, c, d)
		end
		for _, allies in pairs(Shard.alliesByAllyID) do
			for i = 1, #allies do
				Deliver(allies[i], name, a, b, c, d)
			end
		end
	end

	local function DeliverToAIs(name, a, b, c, d)
		local AIs = Shard.AIs
		for i = 1, #AIs do
			Deliver(AIs[i], name, a, b, c, d)
		end
	end

	local function DeliverToAll(name, a, b, c, d)
		DeliverToShared(name, a, b, c, d)
		DeliverToAIs(name, a, b, c, d)
	end

	-- the ShardAlly objects of the ally team that sees or loses the unit, and every AI
	local function DeliverSight(name, unitID, unitTeam, allyTeam, unitDefID)
		local allies = Shard.alliesByAllyID[allyTeam]
		if allies ~= nil then
			for i = 1, #allies do
				Deliver(allies[i], name, unitID, unitTeam, allyTeam, unitDefID)
			end
		end
		DeliverToAIs(name, unitID, unitTeam, allyTeam, unitDefID)
	end

	-- Provisional, as the old loader kept them: the units of every AI split into own, allied, enemy and
	-- neutral, for game:GetUnits(), GetFriendlies() and GetEnemies(); omniscient, whatever the AI sees.
	local function AddToUnitTables(unitID, teamID)
		local AIs = Shard.AIs
		for i = 1, #AIs do
			local thisAI = AIs[i]
			if teamID == thisAI.id then
				thisAI.ownUnitIds[unitID] = true
				thisAI.friendlyUnitIds[unitID] = true
			elseif thisAI.alliedTeamIds[teamID] then
				thisAI.alliedUnitIds[unitID] = true
				thisAI.friendlyUnitIds[unitID] = true
			elseif teamID == gaiaTeamID then
				thisAI.neutralUnitIds[unitID] = true
			else
				thisAI.enemyUnitIds[unitID] = true
			end
		end
	end

	local function RemoveFromUnitTables(unitID)
		local AIs = Shard.AIs
		for i = 1, #AIs do
			local thisAI = AIs[i]
			thisAI.ownUnitIds[unitID] = nil
			thisAI.friendlyUnitIds[unitID] = nil
			thisAI.alliedUnitIds[unitID] = nil
			thisAI.enemyUnitIds[unitID] = nil
			thisAI.neutralUnitIds[unitID] = nil
		end
	end

	-- AI setup -------------------------------------------------------------------------------------

	-- api.lua builds a new game and map for every object, as before: it must not go through the AI
	-- type's include, which runs each file once
	function gadget:NewAPI(aiType)
		shard_include = runtimeInclude
		local api = VFS.Include(RUNTIME_PATH .. "/api.lua")
		api.shard_include = aiType.env.shard_include
		return api
	end

	-- each AI type is read once, into its own environment: its classes do not overwrite those of
	-- another AI, and every AI of the type shares the same classes
	function gadget:LoadAIType(aiName)
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
		global.api = self:NewAPI(aiType)
		global.AIs = {}
		aiType.global = global
		Shard.globals[#Shard.globals + 1] = global
		Shard.types[aiName] = aiType
		return aiType
	end

	function gadget:GetAlly(aiType, allyId)
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
		ally.api = self:NewAPI(aiType)
		ally.global = aiType.global
		ally.AIs = {}
		allies[#allies + 1] = ally
		return ally
	end

	function gadget:SetupAI(id)
		local aiInfo = aiTeams[id]
		spEcho("AI Player " .. id .. " is a " .. aiInfo)
		local aiType = self:LoadAIType(aiInfo)
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
		thisAI.api = self:NewAPI(aiType)
		thisAI.global = aiType.global
		thisAI.ally = self:GetAlly(aiType, allyId)
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
		thisAI.ownUnitIds = {}
		thisAI.friendlyUnitIds = {}
		thisAI.alliedUnitIds = {}
		thisAI.enemyUnitIds = {}
		thisAI.neutralUnitIds = {}

		local allyAIs = thisAI.ally.AIs
		allyAIs[#allyAIs + 1] = thisAI
		local globalAIs = thisAI.global.AIs
		globalAIs[#globalAIs + 1] = thisAI
		return thisAI
	end

	function gadget:AddAI(id)
		LoadRuntime()
		local thisAI = self:SetupAI(id)
		if thisAI ~= nil then
			Shard.AIsByTeamID[id] = thisAI
			Shard.AIs[#Shard.AIs + 1] = thisAI
			thisAI.index = #Shard.AIs
			hosting = true
		end
		return thisAI
	end

	local function RemoveValue(list, value)
		for i = #list, 1, -1 do
			if list[i] == value then
				table.remove(list, i)
			end
		end
	end

	-- the AI of teamID stops here: no more events nor updates, and its queued orders are dropped
	local function StopAI(teamID)
		local thisAI = Shard.AIsByTeamID[teamID]
		if thisAI == nil then
			return
		end
		spEcho("[AI Loader] AI team " .. teamID .. " moved to another host: stopped on this client")
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

	local function StartObject(target, fresh)
		if target.loaded == true then
			return
		end
		Call(target, "Prepare") -- Init() runs on the first Prepare(), as in Shard
		fresh[target] = true
	end

	-- initialise every object not loaded yet, global -> ally team -> team, so that a module finds the
	-- shared modules already initialised; returns the objects it started
	function gadget:StartAIs()
		started = true
		local fresh = {}
		for _, global in ipairs(Shard.globals) do
			StartObject(global, fresh)
		end
		for _, allies in pairs(Shard.alliesByAllyID) do
			for _, ally in ipairs(allies) do
				StartObject(ally, fresh)
			end
		end
		for _, thisAI in ipairs(Shard.AIs) do
			if thisAI.loaded ~= true then
				local x, y, z = spGetTeamStartPosition(thisAI.id)
				thisAI.startPos = { x, y, z }
			end
			StartObject(thisAI, fresh)
		end
		return fresh
	end

	-- the first event or the first frame starts the AIs, as the lazy Init() of Prepare() did
	local function Ready()
		if not hosting then
			return false
		end
		if not started then
			gadget:StartAIs()
		end
		return true
	end

	-- regenerate the events of the units that already exist, as the old loader did after a reload;
	-- only the objects in targets hear them
	function gadget:CatchUp(targets)
		catchUpTargets = targets
		local units = spGetAllUnits()
		for i = 1, #units do
			local unitID = units[i]
			local unitDefID = spGetUnitDefID(unitID) --[[@as integer]]
			local teamID = spGetUnitTeam(unitID) --[[@as integer]]
			---@diagnostic disable-next-line: need-check-nil
			self:UnitCreated(unitID, unitDefID, teamID)
			-- the old loader reported nanoframes as finished too
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			if buildProgress == nil or buildProgress >= 1 then
				---@diagnostic disable-next-line: need-check-nil
				self:UnitFinished(unitID, unitDefID, teamID)
			end
			local unitAllyId = spGetUnitAllyTeam(unitID)
			for allyId, _ in pairs(Shard.alliesByAllyID) do
				if allyId ~= unitAllyId then
					local state = spGetUnitLosState(unitID, allyId, true)
					if state ~= nil and state % 4 >= 2 then
						self:UnitEnteredRadar(unitID, teamID, allyId, unitDefID)
					end
					if state ~= nil and state % 2 == 1 then
						self:UnitEnteredLos(unitID, teamID, allyId, unitDefID)
					end
				end
			end
		end
		catchUpTargets = nil
	end

	-- the synced side moved an AI team to another host, because its host left the game
	local function HostChanged(_, teamID, hostPlayerID)
		if aiTeams[teamID] == nil then
			return
		end
		local hostedHere = Shard ~= nil and Shard.AIsByTeamID[teamID] ~= nil
		if hostPlayerID ~= myPlayerID then
			if hostedHere then
				StopAI(teamID)
			end
			return
		end
		if hostedHere then
			return
		end
		spEcho(
			"[AI Loader] taking over AI team " .. teamID .. ": its memory is lost, the world is rebuilt from the units"
		)
		if gadget:AddAI(teamID) == nil then
			return
		end
		-- only the objects created now hear the catch-up; a ShardGlobal that already existed does not
		-- get the units of the new ally team again
		if started or spGetGameFrame() > 0 then
			gadget:CatchUp(gadget:StartAIs())
		end
	end

	local function RelayRejected(_, teamID, count)
		local thisAI = hosting and Shard.AIsByTeamID[teamID]
		if thisAI then
			thisAI.outbox.rejected = (thisAI.outbox.rejected or 0) + count
		end
	end

	-- call-ins ---------------------------------------------------------------------------------------

	function gadget:Initialize()
		spEcho("Looking for AIs")
		gadgetHandler:AddSyncAction("shard_host", HostChanged)
		gadgetHandler:AddSyncAction("shard_relay_rejected", RelayRejected)

		for i = 1, #teamList do
			local id = teamList[i]
			if aiTeams[id] ~= nil and spGetTeamRulesParam(id, "aiHostPlayer") == myPlayerID then
				self:AddAI(id)
			end
		end
		if not hosting then
			spEcho("[AI Loader] no AI hosted on this client")
			return
		end
		-- catch up to started game (LuaRules reloaded)
		if spGetGameFrame() > 0 then
			self:CatchUp(self:StartAIs())
		end
	end

	function gadget:GameStart()
		if hosting then
			self:StartAIs()
		end
	end

	local function UpdateObject(target)
		if HasModules(target) then
			Call(target, "Update")
		end
	end

	function gadget:GameFrame(n)
		if not Ready() then
			return
		end
		-- Provisional, as the old loader did: every object runs Update() every frame, global -> ally
		-- team -> team; STAI's own SchedulerHST picks the module that works in each frame.
		local globals = Shard.globals
		for i = 1, #globals do
			UpdateObject(globals[i])
		end
		for _, allies in pairs(Shard.alliesByAllyID) do
			for i = 1, #allies do
				UpdateObject(allies[i])
			end
		end
		local AIs = Shard.AIs
		for i = 1, #AIs do
			UpdateObject(AIs[i])
		end
		-- each AI's queue becomes at most one message
		for i = 1, #AIs do
			AIs[i].outbox:Flush(n, spSendLuaRulesMsg)
		end
		if n % 300 == 0 then
			memoryRecord = math.max(memoryRecord, gcinfo()) -- measured, never forced
		end
	end

	function gadget:UnitCreated(unitId, unitDefId, teamId, builderId)
		if not Ready() then
			return
		end
		AddToUnitTables(unitId, teamId)
		local unit = Shard:shardify_unit(unitId)
		DeliverToShared("UnitCreated", unit, unitDefId, teamId, builderId)
		-- among the AIs only the owner, as the old loader did: STAI's modules take UnitCreated for a unit
		-- of their own team (BuildingsHST blocks the ground of any structure it hears of)
		local thisAI = Shard.AIsByTeamID[teamId]
		if thisAI ~= nil then
			Deliver(thisAI, "UnitCreated", unit, unitDefId, teamId, builderId)
		end
	end

	function gadget:UnitFinished(unitId, unitDefId, teamId)
		if not Ready() then
			return
		end
		-- AIBase:UnitBuilt turns it into MyUnitBuilt, FriendlyUnitBuilt, EnemyUnitBuilt or NeutralUnitBuilt
		DeliverToAll("UnitBuilt", Shard:shardify_unit(unitId), unitDefId, teamId)
	end

	function gadget:UnitDestroyed(unitId, unitDefId, teamId, attackerId, attackerDefId, attackerTeamId)
		if not Ready() then
			return
		end
		DeliverToAll("UnitDead", Shard:shardify_unit(unitId))
		RemoveFromUnitTables(unitId)
		-- the engine reuses unit IDs, and the old loader kept every dead unit in Shard.unitsByID
		Shard:unshardify_unit(unitId)
	end

	function gadget:UnitDamaged(
		unitId,
		unitDefId,
		unitTeamId,
		damage,
		paralyzer,
		weaponDefId,
		projectileId,
		attackerId,
		attackerDefId,
		attackerTeamId
	)
		if not Ready() then
			return
		end
		local unit = Shard:shardify_unit(unitId)
		local attacker = Shard:shardify_unit(attackerId)
		local damageObj = Shard:shardify_damage(damage, weaponDefId, paralyzer)
		DeliverToAll("UnitDamaged", unit, attacker, damageObj)
	end

	function gadget:UnitIdle(unitId, unitDefId, teamId)
		if not Ready() then
			return
		end
		DeliverToAll("UnitIdle", Shard:shardify_unit(unitId))
	end

	function gadget:UnitTaken(unitId, unitDefId, teamId, newTeamId)
		if not Ready() then
			return
		end
		DeliverToAll("UnitDead", Shard:shardify_unit(unitId))
		RemoveFromUnitTables(unitId)
	end

	-- as the old loader did: every object hears UnitCreated for a unit that changed team
	function gadget:UnitGiven(unitId, unitDefId, teamId, oldTeamId)
		if not Ready() then
			return
		end
		AddToUnitTables(unitId, teamId)
		DeliverToAll("UnitCreated", Shard:shardify_unit(unitId), unitDefId, teamId, oldTeamId)
	end

	function gadget:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
		if Ready() then
			DeliverSight("UnitEnteredLos", unitID, unitTeam, allyTeam, unitDefID)
		end
	end

	function gadget:UnitLeftLos(unitID, unitTeam, allyTeam, unitDefID)
		if Ready() then
			DeliverSight("UnitLeftLos", unitID, unitTeam, allyTeam, unitDefID)
		end
	end

	function gadget:UnitEnteredRadar(unitID, unitTeam, allyTeam, unitDefID)
		if Ready() then
			DeliverSight("UnitEnteredRadar", unitID, unitTeam, allyTeam, unitDefID)
		end
	end

	function gadget:UnitLeftRadar(unitID, unitTeam, allyTeam, unitDefID)
		if Ready() then
			DeliverSight("UnitLeftRadar", unitID, unitTeam, allyTeam, unitDefID)
		end
	end

	function gadget:FeatureDestroyed(featureID)
		if hosting then
			Shard:unshardify_feature(featureID)
		end
	end

	-- the old loader never forwarded the end of the game: GameEnd() did not reach the modules
	function gadget:GameOver(winningAllyTeams)
		if not hosting then
			return
		end
		for _, thisAI in ipairs(Shard.AIs) do
			Call(thisAI, "GameEnd")
		end
		for _, allies in pairs(Shard.alliesByAllyID) do
			for _, ally in ipairs(allies) do
				Call(ally, "GameEnd")
			end
		end
		for _, global in ipairs(Shard.globals) do
			Call(global, "GameEnd")
		end
	end

	function gadget:GameID(gameID)
		-- a hash per team: the old Shard.randomseed was the sum of the bytes, the same for every AI
		gameHash = self:HashGameID(gameID)
		if not hosting then
			return
		end
		Shard.gameID = gameID
		Shard.randomseed = gameHash
		for _, thisAI in ipairs(Shard.AIs) do
			thisAI.randomseed = TeamSeed(thisAI.id)
		end
	end

	function gadget:Shutdown()
		spEcho("Shard AI unsync gadget shutdown")
		spEcho("Shard memory record:", memoryRecord)
		gadgetHandler:RemoveSyncAction("shard_host")
		gadgetHandler:RemoveSyncAction("shard_relay_rejected")
	end
end
