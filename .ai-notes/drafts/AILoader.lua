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

-- DRAFT. Same entry point and structure as the loader removed in 3ad8f3fb, with these changes:
-- * the AIs run only on the client that hosts them: one host per ally team, registered by the
--   synced side in the team rules param "aiHostPlayer";
-- * the synced side only relays orders: a binary message from the host of a team, for units of
--   that team, and nothing else;
-- * each AI type is read once, into its own environment; modules can be shared per ally team or per
--   client (Module:Scope()), so there is a ShardGlobal per AI type and a ShardAlly per ally team and
--   AI type;
-- * a call-in reaches only the objects whose modules override the callback, and only the ally
--   teams that can see the unit;
-- * no forced garbage collection.
--
-- Runtime pieces this loader expects (shard_runtime/, to be written or changed):
--   boot.lua                   shard_generate_include_func(runtimePath, aiPath, env): loads into env,
--                              each file once per AI type
--   shardai.lua                Prepare() returns at once when the object is already the current one;
--                              Init() binds the shared modules as self[internalName]
--   shardally.lua              ShardAlly, ShardAI subclass for the modules with Scope() "ally"
--   shardglobal.lua            ShardGlobal, ShardAI subclass for the modules with Scope() "global"
--   scheduler.lua              ShardScheduler: AddAI(object), Update(frame)
--   spring_lua/outbox.lua      ShardOutbox(teamID): Flush(frame, send); writes the message decoded below
--   spring_lua/perception.lua  ShardPerception(allyTeamID): EnteredLos, LeftLos, EnteredRadar, LeftRadar
--   spring_lua/shard.lua       Shard:RegisterUnit(unitID, unitDefID, teamID), Shard:UnregisterUnit(unitID)

-- localization
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
if Game.maxUnits > 65536 then
	spEcho("[AI Loader] Game.maxUnits does not fit the order format: ShardLua bot Deactivated!")
	return false
end

spEcho("[AI Loader] ShardLua bot Activated!")

if gadgetHandler:IsSyncedCode() then
	-- SYNCED CODE: host registry and order relay. No AI code runs here.

	local spGetAIInfo = Spring.GetAIInfo
	local spGetPlayerInfo = Spring.GetPlayerInfo
	local spGetPlayerList = Spring.GetPlayerList
	local spSetTeamRulesParam = Spring.SetTeamRulesParam
	local spValidUnitID = Spring.ValidUnitID
	local spGetUnitTeam = Spring.GetUnitTeam
	local spGiveOrderToUnit = Spring.GiveOrderToUnit
	local spGiveOrderArrayToUnit = Spring.GiveOrderArrayToUnit
	local spUnpackU16 = VFS.UnpackU16
	local spUnpackU32 = VFS.UnpackU32
	local spUnpackS32 = VFS.UnpackS32
	local spUnpackF32 = VFS.UnpackF32
	local stringSub = string.sub

	-- order message, version 1 (written by shard_runtime/spring_lua/outbox.lua)
	--   header, 16 bytes:   magic "AIFw", version U8, teamID U8, seq U32, emission frame U32, count U16
	--   order, 8 + 4n bytes: unitID U16, cmdID S32, options U8, n U8, params F32 x n
	local ORDER_MAGIC = "AIFw"
	local ORDER_VERSION = 1
	local HEADER_SIZE = 16
	local MAX_ORDERS_PER_MESSAGE = 4000
	local MAX_MESSAGES_PER_FRAME = 2 -- per team and emission frame, never per arrival frame
	local MAX_FRAME_AGE = 900 -- oldest accepted emission frame, in frames
	local PUBLIC = { public = true }

	local aiHostPlayer = {} -- teamID -> the only playerID whose messages give orders to that team
	local lastSeq = {} -- teamID -> last accepted seq
	local lastFrame = {} -- teamID -> emission frame of the last accepted message
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
		local players = spGetPlayerList(true)
		for i = 1, #players do
			local playerID = players[i]
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
					local host = aiHostPlayer[teamID] or hostingPlayerID
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
	local cmdArray = {}
	local cmdCount = 0
	local cmdPool = {}

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
			local cmd = cmdArray[1]
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
		if stringSub(msg, 1, 4) ~= ORDER_MAGIC then
			return false
		end
		relayCounter.messages = relayCounter.messages + 1
		local size = #msg
		if size < HEADER_SIZE then
			return Reject("size")
		end
		-- VFS.Unpack* returns nothing for a position equal to #msg, and the last order may end with its
		-- options and n bytes: every U8 pair is read as one U16
		local versionAndTeam = spUnpackU16(msg, 5)
		local version = versionAndTeam % 256
		local teamID = (versionAndTeam - version) / 256
		if version ~= ORDER_VERSION then
			return Reject("version")
		end
		-- playerID comes from the server: a client cannot fake it
		if aiHostPlayer[teamID] ~= playerID then
			return Reject("sender")
		end
		local seq = spUnpackU32(msg, 7)
		if seq <= (lastSeq[teamID] or 0) then
			return Reject("seq")
		end
		local frame = spUnpackU32(msg, 11)
		local now = spGetGameFrame()
		if frame > now or frame < now - MAX_FRAME_AGE then
			return Reject("frame")
		end
		if frame == lastFrame[teamID] then
			if messagesInFrame[teamID] >= MAX_MESSAGES_PER_FRAME then
				return Reject("rate")
			end
			messagesInFrame[teamID] = messagesInFrame[teamID] + 1
		else
			lastFrame[teamID] = frame
			messagesInFrame[teamID] = 1
		end
		local count = spUnpackU16(msg, 15)
		if count > MAX_ORDERS_PER_MESSAGE then
			return Reject("count")
		end
		lastSeq[teamID] = seq

		local pos = HEADER_SIZE + 1
		local currentUnit = nil
		local unitAllowed = false
		local rejectedOrders = 0
		for i = 1, count do
			if pos + 7 > size then
				rejectedOrders = rejectedOrders + count - i + 1
				break
			end
			local unitID = spUnpackU16(msg, pos)
			local cmdID = spUnpackS32(msg, pos + 2)
			local optionsAndCount = spUnpackU16(msg, pos + 6)
			local options = optionsAndCount % 256
			local paramCount = (optionsAndCount - options) / 256
			pos = pos + 8
			if pos + 4 * paramCount - 1 > size then
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
					params = spUnpackF32(msg, pos)
				elseif paramCount > 1 then
					params = spUnpackF32(msg, pos, paramCount)
				end
				AddOrder(cmdID, params, options)
			else
				rejectedOrders = rejectedOrders + 1
			end
			pos = pos + 4 * paramCount
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
		spEcho("Shard relay:", relayCounter.messages, "messages,", relayCounter.orders, "orders given,", relayCounter.rejectedOrders, "orders rejected")
		for reason, count in pairs(relayCounter.rejected) do
			spEcho("Shard relay: " .. count .. " messages rejected (" .. reason .. ")")
		end
	end

else -- UNSYNCED CODE: the AIs, only on the client that hosts them

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

		-- globals
		ShardSpringLua = true

		-- this is the AI Boot gadget, so we're in Spring Lua
		VFS.Include(RUNTIME_PATH .. "/spring_lua/boot.lua")
		runtimeInclude = shard_include

		-- Shard object
		Shard = VFS.Include(RUNTIME_PATH .. "/spring_lua/shard.lua")
		Shard.AIs = {}
		Shard.AIsByTeamID = {}
		Shard.alliesByAllyID = {} -- allyTeamID -> ShardAlly objects, one per AI type
		Shard.globals = {} -- ShardGlobal objects, one per AI type
		Shard.types = {} -- AI name -> AI type read by LoadAIType
		Shard.perceptions = {} -- allyTeamID -> what that ally team sees, shared by every AI type
		Shard.scheduler = ShardScheduler()
	end

	local function TeamSeed(teamID)
		return (gameHash * 31 + teamID + 1) % 2147483647
	end

	-- event delivery --------------------------------------------------------------------------------

	-- false when no module of target overrides name; composite callbacks such as UnitGiven have no
	-- list of their own and always pass
	local function Wants(target, name)
		local handlers = target.handlers
		if handlers == nil then
			return false
		end
		local list = handlers[name]
		return list == nil or list[1] ~= nil
	end

	local function Deliver(target, name, a, b, c, d)
		if catchUpTargets ~= nil and catchUpTargets[target] == nil then
			return
		end
		if not Wants(target, name) then
			return
		end
		target:Prepare()
		target[name](target, a, b, c, d)
	end

	local function DeliverToGlobals(name, a, b, c, d)
		local globals = Shard.globals
		for i = 1, #globals do
			Deliver(globals[i], name, a, b, c, d)
		end
	end

	-- the ally team's shared objects first, then its AIs
	local function DeliverToAllyTeam(allies, name, a, b, c, d)
		for i = 1, #allies do
			Deliver(allies[i], name, a, b, c, d)
		end
		for i = 1, #allies do
			local AIs = allies[i].AIs
			for j = 1, #AIs do
				Deliver(AIs[j], name, a, b, c, d)
			end
		end
	end

	local function AllyTeamWants(allies, name)
		for i = 1, #allies do
			if Wants(allies[i], name) then
				return true
			end
			local AIs = allies[i].AIs
			for j = 1, #AIs do
				if Wants(AIs[j], name) then
					return true
				end
			end
		end
		return false
	end

	-- in LOS, or also in radar when radarToo; an omniscient AI type sees everything
	-- (an ally team with two AI types follows the first one)
	local function Sees(ally, unitID, radarToo)
		if ally.omniscient then
			return true
		end
		local state = spGetUnitLosState(unitID, ally.allyId, true)
		if state == nil then
			return false
		end
		return state % 2 == 1 or (radarToo and state % 4 >= 2)
	end

	-- the owner's ally team always, the other hosted ally teams only if they see the unit
	local function DeliverToObservers(name, unitID, unitAllyId, radarToo, a, b, c, d)
		for allyId, allies in pairs(Shard.alliesByAllyID) do
			if allyId == unitAllyId or Sees(allies[1], unitID, radarToo) then
				DeliverToAllyTeam(allies, name, a, b, c, d)
			end
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
			Shard.perceptions[allyId] = ShardPerception(allyId)
		end
		for i = 1, #allies do
			if allies[i].fullname == aiType.name then
				return allies[i]
			end
		end
		local ally = ShardAlly()
		ally.loaded = false
		ally.allyId = allyId
		ally.fullname = aiType.name
		ally.omniscient = aiType.omniscient
		ally.api = self:NewAPI(aiType)
		ally.global = aiType.global
		ally.perception = Shard.perceptions[allyId]
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
		local _, _, _, isAI, side, allyId = spGetTeamInfo(id, false)
		thisAI.allyId = allyId
		thisAI.side = side
		thisAI.fullname = aiInfo
		thisAI.omniscient = aiType.omniscient
		thisAI.api = self:NewAPI(aiType)
		thisAI.global = aiType.global
		thisAI.ally = self:GetAlly(aiType, allyId)
		thisAI.perception = thisAI.ally.perception
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
		-- ownUnitIds, friendlyUnitIds, alliedUnitIds, enemyUnitIds and neutralUnitIds are gone:
		-- game:GetUnits(), GetFriendlies() and GetEnemies() read the registry and the ally team's perception

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

	local function StartObject(target, fresh)
		if target.loaded == true then
			return
		end
		target:Prepare() -- Init() runs on the first Prepare(), as in Shard
		Shard.scheduler:AddAI(target)
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
			local unitDefID = spGetUnitDefID(unitID)
			local teamID = spGetUnitTeam(unitID)
			self:UnitCreated(unitID, unitDefID, teamID)
			-- the old loader reported nanoframes as finished too
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			if buildProgress == nil or buildProgress >= 1 then
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
		if hostPlayerID ~= myPlayerID or (hosting and Shard.AIsByTeamID[teamID] ~= nil) then
			return
		end
		spEcho("[AI Loader] taking over AI team " .. teamID .. ": its memory is lost, the world is rebuilt from the units")
		if gadget:AddAI(teamID) == nil then
			return
		end
		-- only the objects created now hear the catch-up; a ShardGlobal that already existed does not
		-- get the units of the new ally team again (to be decided)
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

	function gadget:GameFrame(n)
		if not Ready() then
			return
		end
		-- elected behaviours activated, expired waits, every-frame updates, MScheduler and BScheduler
		-- turns within the budget, long jobs
		Shard.scheduler:Update(n)
		-- each AI's queue becomes at most one message (two above 60,000 bytes)
		local AIs = Shard.AIs
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
		Shard:RegisterUnit(unitId, unitDefId, teamId)
		local allies = Shard.alliesByAllyID[spGetUnitAllyTeam(unitId)]
		if allies == nil then
			return -- not a unit of an ally team hosted here: perception reports it if it is seen
		end
		local unit = Shard:shardify_unit(unitId)
		DeliverToGlobals("UnitCreated", unit, unitDefId, teamId, builderId)
		for i = 1, #allies do
			Deliver(allies[i], "UnitCreated", unit, unitDefId, teamId, builderId)
		end
		local thisAI = Shard.AIsByTeamID[teamId]
		if thisAI ~= nil then
			Deliver(thisAI, "UnitCreated", unit, unitDefId, teamId, builderId)
		end
	end

	function gadget:UnitFinished(unitId, unitDefId, teamId)
		if not Ready() then
			return
		end
		local unit = Shard:shardify_unit(unitId)
		local unitAllyId = spGetUnitAllyTeam(unitId)
		if Shard.alliesByAllyID[unitAllyId] ~= nil then
			DeliverToGlobals("UnitBuilt", unit, unitDefId, teamId)
		end
		-- AIBase:UnitBuilt turns it into MyUnitBuilt, FriendlyUnitBuilt, EnemyUnitBuilt or NeutralUnitBuilt
		DeliverToObservers("UnitBuilt", unitId, unitAllyId, false, unit, unitDefId, teamId)
	end

	function gadget:UnitDestroyed(unitId, unitDefId, teamId, attackerId, attackerDefId, attackerTeamId)
		if not Ready() then
			return
		end
		local unit = Shard:shardify_unit(unitId)
		local unitAllyId = spGetUnitAllyTeam(unitId)
		if Shard.alliesByAllyID[unitAllyId] ~= nil then
			DeliverToGlobals("UnitDead", unit)
		end
		-- the other ally teams hear it only if they see the unit die, in LOS or in radar
		DeliverToObservers("UnitDead", unitId, unitAllyId, true, unit)
		-- the engine reuses unit IDs: the registry drops the unit from every perception too
		Shard:UnregisterUnit(unitId)
		Shard:unshardify_unit(unitId) -- the old loader kept every dead unit in Shard.unitsByID
	end

	function gadget:UnitDamaged(unitId, unitDefId, unitTeamId, damage, paralyzer, weaponDefId, projectileId, attackerId, attackerDefId, attackerTeamId)
		if not Ready() then
			return
		end
		local unitAllyId = spGetUnitAllyTeam(unitId)
		local unit = nil
		local damageObj = nil -- created only if somebody receives it
		for allyId, allies in pairs(Shard.alliesByAllyID) do
			if (allyId == unitAllyId or Sees(allies[1], unitId, false)) and AllyTeamWants(allies, "UnitDamaged") then
				unit = unit or Shard:shardify_unit(unitId)
				damageObj = damageObj or Shard:shardify_damage(damage, weaponDefId, paralyzer)
				local attacker = nil
				if attackerId ~= nil and Sees(allies[1], attackerId, true) then
					attacker = Shard:shardify_unit(attackerId)
				end
				DeliverToAllyTeam(allies, "UnitDamaged", unit, attacker, damageObj)
			end
		end
	end

	function gadget:UnitIdle(unitId, unitDefId, teamId)
		local thisAI = hosting and Shard.AIsByTeamID[teamId]
		if not thisAI or not Ready() then
			return
		end
		Deliver(thisAI, "UnitIdle", Shard:shardify_unit(unitId))
	end

	function gadget:UnitTaken(unitId, unitDefId, teamId, newTeamId)
		local thisAI = hosting and Shard.AIsByTeamID[teamId]
		if not thisAI or not Ready() then
			return
		end
		Deliver(thisAI, "UnitDead", Shard:shardify_unit(unitId))
	end

	function gadget:UnitGiven(unitId, unitDefId, teamId, oldTeamId)
		if not Ready() then
			return
		end
		Shard:RegisterUnit(unitId, unitDefId, teamId)
		local thisAI = Shard.AIsByTeamID[teamId]
		if thisAI ~= nil then
			-- AIBase:UnitGiven calls UnitCreated and UnitBuilt, as aibase.lua intends; the old loader
			-- called only UnitCreated, so a received unit never had its end-of-build election
			Deliver(thisAI, "UnitGiven", Shard:shardify_unit(unitId))
		end
	end

	function gadget:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
		local allies = hosting and Shard.alliesByAllyID[allyTeam]
		if not allies or not Ready() then
			return
		end
		Shard.perceptions[allyTeam]:EnteredLos(unitID, unitTeam, unitDefID)
		DeliverToAllyTeam(allies, "UnitEnteredLos", unitID, unitTeam, allyTeam, unitDefID)
	end

	function gadget:UnitLeftLos(unitID, unitTeam, allyTeam, unitDefID)
		local allies = hosting and Shard.alliesByAllyID[allyTeam]
		if not allies or not Ready() then
			return
		end
		Shard.perceptions[allyTeam]:LeftLos(unitID)
		DeliverToAllyTeam(allies, "UnitLeftLos", unitID, unitTeam, allyTeam, unitDefID)
	end

	function gadget:UnitEnteredRadar(unitID, unitTeam, allyTeam, unitDefID)
		local allies = hosting and Shard.alliesByAllyID[allyTeam]
		if not allies or not Ready() then
			return
		end
		Shard.perceptions[allyTeam]:EnteredRadar(unitID, unitTeam)
		DeliverToAllyTeam(allies, "UnitEnteredRadar", unitID, unitTeam, allyTeam, unitDefID)
	end

	function gadget:UnitLeftRadar(unitID, unitTeam, allyTeam, unitDefID)
		local allies = hosting and Shard.alliesByAllyID[allyTeam]
		if not allies or not Ready() then
			return
		end
		Shard.perceptions[allyTeam]:LeftRadar(unitID)
		DeliverToAllyTeam(allies, "UnitLeftRadar", unitID, unitTeam, allyTeam, unitDefID)
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
			thisAI:Prepare()
			thisAI:GameEnd()
		end
		for _, allies in pairs(Shard.alliesByAllyID) do
			for _, ally in ipairs(allies) do
				ally:Prepare()
				ally:GameEnd()
			end
		end
		for _, global in ipairs(Shard.globals) do
			global:Prepare()
			global:GameEnd()
		end
	end

	function gadget:GameID(gameID)
		-- a real hash, per team: the old Shard.randomseed was the sum of the bytes, the same for every AI
		local hash = 0
		for i = 1, #gameID do
			hash = (hash * 31 + string.byte(gameID, i)) % 2147483647
		end
		gameHash = hash
		if not hosting then
			return
		end
		Shard.gameID = gameID
		Shard.randomseed = hash
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
