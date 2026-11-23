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
		if frame == lastFrame[teamID] then
			if messagesInFrame[teamID] >= MAX_MESSAGES_PER_FRAME then
				return Reject("rate")
			end
			messagesInFrame[teamID] = messagesInFrame[teamID] + 1
		else
			lastFrame[teamID] = frame
			messagesInFrame[teamID] = 1
		end
		if count > MAX_ORDERS_PER_MESSAGE then
			return Reject("count")
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
	-- UNSYNCED CODE: loading and running the AIs on the hosting client comes with T5b.
end
