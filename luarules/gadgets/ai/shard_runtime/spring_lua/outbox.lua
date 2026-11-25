--- ShardOutbox(teamID): the order queue of one AI
--
-- Orders wait here until Flush turns the oldest ones into one binary message (see ordercodec.lua). A queue entry is
-- an order or a group record (one command for several units). Every entry belongs to a group, the entries of one
-- call: a group never spans two messages.
--
-- Fields: teamID, the team the orders are for; the queue arrays below are reused, never rebuilt.

local OrderCodec = VFS.Include("luarules/gadgets/ai/shard_runtime/ordercodec.lua")

local MAX_ORDERS_PER_MESSAGE = OrderCodec.MAX_ORDERS_PER_MESSAGE

local MAX_PARAMS = OrderCodec.MAX_PARAMS
local GROUP_UNIT = OrderCodec.GROUP_UNIT
local MAX_UNITS_PER_GROUP = OrderCodec.MAX_UNITS_PER_GROUP
-- Bounds as powers of two, exact also where Lua numbers are single precision floats; the upper ones are excluded.
local U8_END = 2 ^ 8
local S32_START = -2 ^ 31
local S32_END = 2 ^ 31
local packHeader = OrderCodec.PackHeader
local packOrder = OrderCodec.PackOrder
local packGroup = OrderCodec.PackGroup
local tableConcat = table.concat
local spEcho = Spring.Echo

local OPTION_BITS = {
	shift = CMD.OPT_SHIFT,
	alt = CMD.OPT_ALT,
	ctrl = CMD.OPT_CTRL,
	meta = CMD.OPT_META,
	right = CMD.OPT_RIGHT,
}

local function isInteger(value, min, maxExcluded)
	return type(value) == "number" and value % 1 == 0 and value >= min and value < maxExcluded
end

-- Bitwise or of two masks within a byte, without a bit library.
local function addBits(mask, bits)
	local value = 1
	for _ = 1, 8 do
		if bits % (2 * value) >= value and mask % (2 * value) < value then
			mask = mask + value
		end
		value = value * 2
	end
	return mask
end

-- The options as a U8 mask of CMD.OPT_* bits: a number, or an array of names and masks; nil and why otherwise.
local function optionsMask(options)
	if options == nil then
		return 0
	end
	if type(options) == "number" then
		if isInteger(options, 0, U8_END) then
			return options
		end
		return nil, "options " .. tostring(options) .. " do not fit in a byte"
	end
	if type(options) ~= "table" then
		return nil, "options of type " .. type(options)
	end
	local mask = 0
	for i = 1, #options do
		local option = options[i]
		local bits = OPTION_BITS[option]
		if bits == nil and isInteger(option, 0, U8_END) then
			bits = option
		end
		if bits == nil then
			return nil, "unknown option " .. tostring(option)
		end
		mask = addBits(mask, bits)
	end
	return mask
end

-- Writes the params into the reused array `slot` and returns how many; nil and why when they cannot be sent.
-- A position table becomes x, y, z, followed by its [1] when it has one.
local function writeParams(slot, params)
	local count
	if params == nil then
		count = 0
	elseif type(params) == "number" then
		slot[1] = params
		count = 1
	elseif type(params) ~= "table" then
		return nil, "params of type " .. type(params)
	elseif params.x ~= nil or params.z ~= nil then
		if type(params.x) ~= "number" or type(params.y) ~= "number" or type(params.z) ~= "number" then
			return nil, "incomplete position"
		end
		slot[1] = params.x
		slot[2] = params.y
		slot[3] = params.z
		count = 3
		if params[1] ~= nil then
			slot[4] = params[1]
			count = 4
		end
	else
		count = #params
		if count > MAX_PARAMS then
			return nil, count .. " params, at most " .. MAX_PARAMS
		end
		for i = 1, count do
			slot[i] = params[i]
		end
	end
	for i = 1, count do
		if type(slot[i]) ~= "number" then
			return nil, "param " .. i .. " is a " .. type(slot[i])
		end
	end
	local tail = count + 1
	while slot[tail] ~= nil do
		slot[tail] = nil
		tail = tail + 1
	end
	return count
end

-- Checks the command of the record at `index` and writes its params there; the mask, the param count, or nil and why.
local function writeCommand(outbox, index, cmdID, params, options)
	if not isInteger(cmdID, S32_START, S32_END) then
		return nil, nil, "command ID is not an S32"
	end
	local mask, reason = optionsMask(options)
	if reason ~= nil then
		return nil, nil, reason
	end
	local slot = outbox.params[index]
	if slot == nil then
		slot = {}
		outbox.params[index] = slot
	end
	local paramCount
	paramCount, reason = writeParams(slot, params)
	return mask, paramCount, reason
end

---@class ShardOutbox
---@field teamID integer
---@field seq integer
---@field last integer
---@field units integer[]
---@field unitCounts integer[]
---@field unitLists integer[][]
---@field commands integer[]
---@field options integer[]
---@field paramCounts integer[]
---@field params number[][]
---@field groups integer[]
---@field groupCounter integer
---@field grouping boolean
---@field groupFailed boolean
---@field groupStart integer
---@field parts string[]
ShardOutbox = class(function(outbox, teamID)
	outbox.teamID = teamID
	outbox.seq = 0
	outbox.last = 0 -- orders in the queue, at indices 1 to last
	outbox.units = {} -- the unit of an order, GROUP_UNIT for a group
	outbox.unitCounts = {} -- 0 for an order, the number of units for a group
	outbox.unitLists = {} -- one reused array per queue index, the units of a group
	outbox.commands = {}
	outbox.options = {}
	outbox.paramCounts = {}
	outbox.params = {} -- one reused array per queue index
	outbox.groups = {}
	outbox.groupCounter = 0
	outbox.grouping = false
	outbox.groupFailed = false
	outbox.groupStart = 1
	outbox.parts = {} -- reused buffer of the message pieces
end)

function ShardOutbox:Warn(text)
	spEcho("Shard outbox team " .. tostring(self.teamID) .. " Warning: " .. text)
end

--- Queues one order
--
-- Outside BeginGroup and EndGroup the order is a group of its own
--
-- @param unitID integer
-- @param cmdID integer
-- @param params nil, a number, an array of at most 255 numbers or a position table {x, y, z}
-- @param options nil, a CMD.OPT_* mask or an array of names: "shift", "alt", "ctrl", "meta", "right"
-- @return boolean whether the order was queued; when not, a warning says why
function ShardOutbox:Queue(unitID, cmdID, params, options)
	if self.groupFailed then
		return false
	end
	local reason, mask, paramCount
	local index = self.last + 1
	if not isInteger(unitID, 0, GROUP_UNIT) then
		reason = "unit ID is not a U16 below " .. GROUP_UNIT
	else
		mask, paramCount, reason = writeCommand(self, index, cmdID, params, options)
	end
	if reason ~= nil then
		self:Warn("order " .. tostring(cmdID) .. " for unit " .. tostring(unitID) .. " dropped: " .. reason)
		if self.grouping then
			self.groupFailed = true
		end
		return false
	end
	if not self.grouping then
		self.groupCounter = self.groupCounter + 1
	end
	self.units[index] = unitID
	self.unitCounts[index] = 0
	self.commands[index] = cmdID
	self.options[index] = mask
	self.paramCounts[index] = paramCount
	self.groups[index] = self.groupCounter
	self.last = index
	return true
end

-- Queues the record at `index`: an order for one unit, a group for more; `list` holds `count` units.
local function commitGroup(outbox, index, cmdID, mask, paramCount, list, count)
	local tail = count + 1
	while list[tail] ~= nil do
		list[tail] = nil
		tail = tail + 1
	end
	if count == 1 then
		outbox.units[index] = list[1]
		outbox.unitCounts[index] = 0
	else
		outbox.units[index] = GROUP_UNIT
		outbox.unitCounts[index] = count
	end
	outbox.commands[index] = cmdID
	outbox.options[index] = mask
	outbox.paramCounts[index] = paramCount
	outbox.groups[index] = outbox.groupCounter
	outbox.last = index
end

--- Queues one command for several units: a group of at most 255 units is one record, more units make more records
--
-- A unit ID that is not valid is dropped alone, with one warning for the call; a command that is not valid drops
-- the call. A single valid unit is queued as an order. Outside BeginGroup and EndGroup the records are a group of
-- their own.
--
-- @param unitIDs integer[] array of unit IDs
-- @param cmdID integer
-- @param params nil, a number, an array of at most 255 numbers or a position table {x, y, z}
-- @param options nil, a CMD.OPT_* mask or an array of names: "shift", "alt", "ctrl", "meta", "right"
-- @return boolean whether every unit was queued
function ShardOutbox:QueueGroup(unitIDs, cmdID, params, options)
	if self.groupFailed then
		return false
	end
	local index = self.last + 1
	local mask, paramCount, reason = writeCommand(self, index, cmdID, params, options)
	if reason ~= nil then
		self:Warn("order " .. tostring(cmdID) .. " for " .. #unitIDs .. " units dropped: " .. reason)
		if self.grouping then
			self.groupFailed = true
		end
		return false
	end
	if not self.grouping then
		self.groupCounter = self.groupCounter + 1
	end
	local list = self.unitLists[index]
	if list == nil then
		list = {}
		self.unitLists[index] = list
	end
	local count = 0
	local dropped = 0
	for i = 1, #unitIDs do
		local unitID = unitIDs[i]
		if not isInteger(unitID, 0, GROUP_UNIT) then
			dropped = dropped + 1
		else
			if count == MAX_UNITS_PER_GROUP then
				commitGroup(self, index, cmdID, mask, paramCount, list, count)
				index = index + 1
				mask, paramCount = writeCommand(self, index, cmdID, params, options)
				list = self.unitLists[index]
				if list == nil then
					list = {}
					self.unitLists[index] = list
				end
				count = 0
			end
			count = count + 1
			list[count] = unitID
		end
	end
	if count > 0 then
		commitGroup(self, index, cmdID, mask, paramCount, list, count)
	end
	if dropped > 0 then
		self:Warn(
			"order " .. tostring(cmdID) .. ": " .. dropped .. " of " .. #unitIDs .. " units dropped: not a unit ID"
		)
		return false
	end
	return true
end

--- Starts a group: the orders queued until EndGroup travel in the same message
function ShardOutbox:BeginGroup()
	self.groupCounter = self.groupCounter + 1
	self.groupStart = self.last + 1
	self.grouping = true
	self.groupFailed = false
end

--- Ends a group; if one of its orders was dropped, the whole group is
--
-- @return boolean whether the group stays queued
function ShardOutbox:EndGroup()
	local kept = not self.groupFailed
	if not kept then
		self.last = self.groupStart - 1
	end
	self.grouping = false
	self.groupFailed = false
	return kept
end

-- Moves the orders after the first `count` to the front of the queue, swapping the params arrays to keep them all.
local function dropFirst(outbox, count)
	local remaining = outbox.last - count
	local units, commands, options = outbox.units, outbox.commands, outbox.options
	local paramCounts, params, groups = outbox.paramCounts, outbox.params, outbox.groups
	local unitCounts, unitLists = outbox.unitCounts, outbox.unitLists
	for i = 1, remaining do
		local from = count + i
		units[i] = units[from]
		unitCounts[i] = unitCounts[from]
		unitLists[i], unitLists[from] = unitLists[from], unitLists[i]
		commands[i] = commands[from]
		options[i] = options[from]
		paramCounts[i] = paramCounts[from]
		groups[i] = groups[from]
		params[i], params[from] = params[from], params[i]
	end
	outbox.last = remaining
end

--- Sends the oldest records as one message, at most MAX_ORDERS_PER_MESSAGE of them unless a single group is larger
--
-- A larger group goes alone in one message, which the relay rejects whole.
--
-- @param frame integer the current game frame, written as the emission frame
-- @param send function called with the message
-- @return boolean whether a message was sent; nothing is sent for an empty queue
function ShardOutbox:Flush(frame, send)
	local last = self.last
	if last == 0 then
		return false
	end
	local groups = self.groups
	local count = 0
	while count < last do
		local group = groups[count + 1]
		local groupEnd = count + 1
		while groupEnd < last and groups[groupEnd + 1] == group do
			groupEnd = groupEnd + 1
		end
		if count > 0 and groupEnd > MAX_ORDERS_PER_MESSAGE then
			break
		end
		count = groupEnd
		if count >= MAX_ORDERS_PER_MESSAGE then
			break
		end
	end

	local seq = self.seq + 1
	self.seq = seq
	local parts = self.parts
	parts[1] = packHeader(self.teamID, seq, frame, count)
	local units, commands, options, paramCounts, params =
		self.units, self.commands, self.options, self.paramCounts, self.params
	local unitCounts, unitLists = self.unitCounts, self.unitLists
	for i = 1, count do
		if unitCounts[i] == 0 then
			parts[i + 1] = packOrder(units[i], commands[i], options[i], params[i], paramCounts[i])
		else
			parts[i + 1] = packGroup(commands[i], options[i], params[i], paramCounts[i], unitLists[i], unitCounts[i])
		end
	end
	local message = tableConcat(parts, "", 1, count + 1)
	for i = 1, count + 1 do
		parts[i] = nil
	end
	dropFirst(self, count)
	send(message)
	return true
end

--- Empties the queue and starts again from seq 1, as a new host must
function ShardOutbox:Reset()
	self.last = 0
	self.seq = 0
	self.grouping = false
	self.groupFailed = false
end
