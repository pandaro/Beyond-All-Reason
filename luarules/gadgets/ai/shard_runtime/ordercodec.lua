--- Order message format, version 2: the only definition of it, for the outbox that writes it and the relay that
-- reads it. Pure byte packing, no unsynced call: synced code may include this file.
--
-- header, 16 bytes:    magic "AIFw", version U8, teamID U8, seq U32, emission frame U32, record count U16
-- order, 8 + 4n bytes: unitID U16, cmdID S32, options U8, n U8, then n params F32
-- group, 10 + 4n + 2k bytes: an order whose unitID is GROUP_UNIT (65535, never a unit), then k U16, then k unitID U16;
--                      one command for k units, at most MAX_UNITS_PER_GROUP
--
-- A record is an order or a group; the header counts records. Version 1 had orders only.
--
-- Positions are 1-based byte offsets, as VFS.Unpack* takes them. VFS.Unpack* returns nothing for a position equal to
-- the message length, so every pair of U8 is read as one U16: an order without params ends with options and n.

local packU8 = VFS.PackU8
local packU16 = VFS.PackU16
local packU32 = VFS.PackU32
local packS32 = VFS.PackS32
local packF32 = VFS.PackF32
local unpackU16 = VFS.UnpackU16
local unpackU32 = VFS.UnpackU32
local unpackS32 = VFS.UnpackS32
local stringSub = string.sub

local OrderCodec = {
	MAGIC = "AIFw",
	VERSION = 2,
	HEADER_SIZE = 16,
	ORDER_FIXED_SIZE = 8,
	PARAM_SIZE = 4,
	MAX_PARAMS = 255,
	MAX_ORDERS = 65535,
	-- the outbox writes at most this many records a message and the relay rejects a message with more; each order
	-- costs the engine about 4.2 us on every client (phase 0), a group counts as one record
	MAX_ORDERS_PER_MESSAGE = 20,
	-- the unitID that marks a group record
	GROUP_UNIT = 65535,
	MAX_UNITS_PER_GROUP = 255,
}

local MAGIC = OrderCodec.MAGIC
local VERSION = OrderCodec.VERSION
local HEADER_SIZE = OrderCodec.HEADER_SIZE
local ORDER_FIXED_SIZE = OrderCodec.ORDER_FIXED_SIZE
local PARAM_SIZE = OrderCodec.PARAM_SIZE
local GROUP_UNIT = OrderCodec.GROUP_UNIT
local UNIT_SIZE = 2

--- Whether a message starts with the order magic, whatever else it holds
function OrderCodec.IsOrderMessage(message)
	return stringSub(message, 1, 4) == MAGIC
end

--- Packs a header
--
-- @param teamID integer 0-255
-- @param seq integer U32, growing for every message of the team
-- @param frame integer U32 game frame the message was sent in
-- @param count integer U16 orders that follow
-- @return string the 16 header bytes
function OrderCodec.PackHeader(teamID, seq, frame, count)
	return MAGIC .. packU8(VERSION, teamID) .. packU32(seq, frame) .. packU16(count)
end

--- Packs one order
--
-- @param unitID integer U16
-- @param cmdID integer S32, negative for build commands
-- @param options integer U8 CMD.OPT_* bit mask
-- @param params table array of exactly paramCount numbers, read only when paramCount > 0
-- @param paramCount integer 0-255
-- @return string the 8 + 4 * paramCount order bytes
function OrderCodec.PackOrder(unitID, cmdID, options, params, paramCount)
	local fixed = packU16(unitID) .. packS32(cmdID) .. packU8(options, paramCount)
	if paramCount == 0 then
		return fixed
	end
	return fixed .. packF32(params)
end

--- Packs one group: one command for several units
--
-- @param cmdID integer S32
-- @param options integer U8
-- @param params table array of exactly paramCount numbers, read only when paramCount > 0
-- @param paramCount integer 0-255
-- @param unitIDs table array of exactly unitCount unit IDs, read only when unitCount > 0
-- @param unitCount integer 0 to MAX_UNITS_PER_GROUP
-- @return string the 10 + 4 * paramCount + 2 * unitCount group bytes
function OrderCodec.PackGroup(cmdID, options, params, paramCount, unitIDs, unitCount)
	local head = OrderCodec.PackOrder(GROUP_UNIT, cmdID, options, params, paramCount) .. packU16(unitCount)
	if unitCount == 0 then
		return head
	end
	return head .. packU16(unitIDs)
end

--- Reads a header
--
-- @param message string a message IsOrderMessage accepted
-- @return integer? version, nil when the message is shorter than a header
-- @return integer teamID
-- @return integer seq
-- @return integer frame
-- @return integer count
-- @return integer position of the first order
function OrderCodec.UnpackHeader(message)
	if #message < HEADER_SIZE then
		return nil
	end
	local versionAndTeam = unpackU16(message, 5)
	local version = versionAndTeam % 256
	local teamID = (versionAndTeam - version) / 256
	return version, teamID, unpackU32(message, 7), unpackU32(message, 11), unpackU16(message, 15), HEADER_SIZE + 1
end

--- Reads the fixed part of the order at `position`; its params, F32 each, are left to the caller
--
-- @param message string
-- @param position integer where the order starts
-- @return integer? unitID, GROUP_UNIT for a group (then see UnpackGroupUnits), nil when the order or its params run
--         past the end of the message
-- @return integer cmdID
-- @return integer options
-- @return integer paramCount
-- @return integer position of the first param
-- @return integer position of the next order
function OrderCodec.UnpackOrder(message, position)
	local size = #message
	if position + ORDER_FIXED_SIZE - 1 > size then
		return nil
	end
	local optionsAndCount = unpackU16(message, position + 6)
	local options = optionsAndCount % 256
	local paramCount = (optionsAndCount - options) / 256
	local paramsPosition = position + ORDER_FIXED_SIZE
	local nextPosition = paramsPosition + PARAM_SIZE * paramCount
	if nextPosition - 1 > size then
		return nil
	end
	return unpackU16(message, position),
		unpackS32(message, position + 2),
		options,
		paramCount,
		paramsPosition,
		nextPosition
end

--- Reads the units of the group whose fixed part and params UnpackOrder has read
--
-- @param message string
-- @param position integer the position of the next order that UnpackOrder returned for the group
-- @return integer? unitCount, nil when the count or the units run past the end of the message
-- @return integer position of the first unitID, read as U16 each
-- @return integer position of the next record
function OrderCodec.UnpackGroupUnits(message, position)
	if position + UNIT_SIZE - 1 > #message then
		return nil
	end
	local unitCount = unpackU16(message, position)
	local unitsPosition = position + UNIT_SIZE
	local nextPosition = unitsPosition + UNIT_SIZE * unitCount
	if nextPosition - 1 > #message then
		return nil
	end
	return unitCount, unitsPosition, nextPosition
end

return OrderCodec
