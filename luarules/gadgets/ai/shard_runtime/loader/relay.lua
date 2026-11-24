-- The order relay: the binary messages of shard_runtime/ordercodec.lua become engine orders, only when they
-- come from the host of their team and only for units of that team. Every check runs on every client.
-- Synced: no unsynced data, no timers.

local OrderCodec = VFS.Include("luarules/gadgets/ai/shard_runtime/ordercodec.lua")

local spEcho = Spring.Echo
local spGetGameFrame = Spring.GetGameFrame
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

local lastSeq = {} ---@type table<integer, number?> teamID -> last accepted seq
local lastFrame = {} ---@type table<integer, number?> teamID -> emission frame of the last accepted message
local messagesInFrame = {} -- teamID -> accepted messages with that emission frame
local relayCounter = { messages = 0, orders = 0, rejectedOrders = 0, rejected = {} }

-- orders of the unit being decoded; these tables are reused, only the params tables are new
local cmdArray = {} ---@type table[]
local cmdCount = 0
local cmdPool = {} ---@type table[]

-- given by Setup
local hostOf ---@type fun(teamID: integer): integer?

--- hostOf(teamID): the only playerID whose messages give orders to that team
local function Setup(hostOfTeam)
	hostOf = hostOfTeam
end

--- A new host counts its messages from 1
local function ForgetTeam(teamID)
	lastSeq[teamID] = nil
	lastFrame[teamID] = nil
end

local function Reject(reason)
	relayCounter.rejected[reason] = (relayCounter.rejected[reason] or 0) + 1
end

-- orders ----------------------------------------------------------------------------------------------------

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

local function ReadParams(msg, paramCount, paramsPosition)
	if paramCount == 1 then
		return spUnpackF32(msg, paramsPosition)
	elseif paramCount > 1 then
		---@diagnostic disable-next-line: redundant-parameter
		local values = spUnpackF32(msg, paramsPosition, paramCount) --[[@as table]]
		values.n = nil -- the engine reads params with next() too: keep only the values
		return values
	end
	return nil
end

-- message -----------------------------------------------------------------------------------------------------

-- every check of the header, in order; the team, its orders and where they start, or nil when rejected
local function CheckHeader(msg, playerID)
	local version, teamID, seq, frame, count, position = unpackHeader(msg)
	if version == nil then
		return Reject("size")
	end
	if version ~= OrderCodec.VERSION then
		return Reject("version")
	end
	-- playerID comes from the server: a client cannot fake it
	if hostOf(teamID) ~= playerID then
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
	return teamID, count, position
end

-- the orders of a message, each unit checked once; an order cut short and the ones after it are rejected
local function GiveMessageOrders(msg, teamID, count, position)
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
			AddOrder(cmdID, ReadParams(msg, paramCount, paramsPosition), options)
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
end

--- A message with the order magic is always ours, accepted or rejected: no other gadget parses it
---@return boolean ours
local function Receive(msg, playerID)
	if not isOrderMessage(msg) then
		return false
	end
	relayCounter.messages = relayCounter.messages + 1
	local teamID, count, position = CheckHeader(msg, playerID)
	if teamID ~= nil then
		GiveMessageOrders(msg, teamID, count, position)
	end
	return true
end

local function WriteCounters()
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

return {
	Setup = Setup,
	ForgetTeam = ForgetTeam,
	Receive = Receive,
	WriteCounters = WriteCounters,
}
