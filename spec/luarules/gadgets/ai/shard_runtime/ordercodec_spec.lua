---@diagnostic disable: undefined-field, need-check-nil, inject-field, call-non-callable, param-type-mismatch
---@diagnostic disable: assign-type-mismatch, unnecessary-if

local RUNTIME_PATH = "luarules/gadgets/ai/shard_runtime/"
local CODEC_PATH = RUNTIME_PATH .. "ordercodec.lua"

-- VFS.Pack* and VFS.Unpack* as Recoil implements them: little-endian, F32 as IEEE 754 single precision rounded to
-- nearest even, packing stops at the first value that is not a number and returns nothing when none is, and
-- unpacking returns nothing for a position below 1 or not below the string length.
local function toBytes(value, size)
	value = math.floor(value) % 2 ^ (8 * size)
	local bytes = {}
	for i = 1, size do
		local byte = value % 256
		bytes[i] = string.char(byte)
		value = (value - byte) / 256
	end
	return table.concat(bytes)
end

local function fromBytes(text, position, size)
	local value = 0
	for i = size, 1, -1 do
		value = value * 256 + string.byte(text, position + i - 1)
	end
	return value
end

local function roundEven(value)
	local floor = math.floor(value)
	local fraction = value - floor
	if fraction > 0.5 or (fraction == 0.5 and floor % 2 == 1) then
		return floor + 1
	end
	return floor
end

local function encodeF32(value)
	local sign = 0
	if value < 0 or (value == 0 and 1 / value < 0) then
		sign = 1
		value = -value
	end
	local exponent, mantissa
	if value ~= value then
		exponent, mantissa = 255, 2 ^ 22
	elseif value == math.huge then
		exponent, mantissa = 255, 0
	elseif value == 0 then
		exponent, mantissa = 0, 0
	else
		local fraction, power = math.frexp(value)
		exponent = power + 126
		if exponent <= 0 then
			exponent = 0
			mantissa = roundEven(value * 2 ^ 149)
			if mantissa >= 2 ^ 23 then
				exponent, mantissa = 1, mantissa - 2 ^ 23
			end
		else
			mantissa = roundEven((fraction * 2 - 1) * 2 ^ 23)
			if mantissa == 2 ^ 23 then
				exponent, mantissa = exponent + 1, 0
			end
			if exponent >= 255 then
				exponent, mantissa = 255, 0
			end
		end
	end
	return toBytes(sign * 2 ^ 31 + exponent * 2 ^ 23 + mantissa, 4)
end

local function decodeF32(text, position)
	local bits = fromBytes(text, position, 4)
	local sign = bits >= 2 ^ 31 and -1 or 1
	bits = bits % 2 ^ 31
	local exponent = math.floor(bits / 2 ^ 23)
	local mantissa = bits % 2 ^ 23
	if exponent == 255 then
		return mantissa == 0 and sign * math.huge or 0 / 0
	elseif exponent == 0 then
		return sign * mantissa * 2 ^ -149
	end
	return sign * (1 + mantissa / 2 ^ 23) * 2 ^ (exponent - 127)
end

local function packer(encode)
	return function(first, ...)
		local values = type(first) == "table" and first or { first, ... }
		local pieces = {}
		local i = 1
		while type(values[i]) == "number" do
			pieces[i] = encode(values[i])
			i = i + 1
		end
		if i == 1 then
			return nil
		end
		return table.concat(pieces)
	end
end

local function unpacker(size, decode)
	return function(text, position, count)
		local length = #text
		local offset = 0
		if position ~= nil then
			if position < 1 or position >= length then
				return
			end
			offset = position - 1
		end
		local available = length - offset
		if available < size then
			return
		end
		if count == nil then
			return decode(text, offset + 1)
		end
		local maxCount = math.floor(available / size)
		if count < 0 or count > maxCount then
			count = maxCount
		end
		local values = { n = count }
		for i = 1, count do
			values[i] = decode(text, offset + 1 + (i - 1) * size)
		end
		return values
	end
end

local function unsigned(size)
	return function(text, position)
		return fromBytes(text, position, size)
	end
end

local function decodeS32(text, position)
	local value = fromBytes(text, position, 4)
	if value >= 2 ^ 31 then
		return value - 2 ^ 32
	end
	return value
end

local function newVFS(env)
	return {
		PackU8 = packer(function(value)
			return toBytes(value, 1)
		end),
		PackU16 = packer(function(value)
			return toBytes(value, 2)
		end),
		PackU32 = packer(function(value)
			return toBytes(value, 4)
		end),
		PackS32 = packer(function(value)
			return toBytes(value, 4)
		end),
		PackF32 = packer(encodeF32),
		UnpackU8 = unpacker(1, unsigned(1)),
		UnpackU16 = unpacker(2, unsigned(2)),
		UnpackU32 = unpacker(4, unsigned(4)),
		UnpackS32 = unpacker(4, decodeS32),
		UnpackF32 = unpacker(4, decodeF32),
		Include = function(path, includeEnv)
			local chunk = assert(loadfile(path))
			setfenv(chunk, includeEnv or env)
			return chunk()
		end,
	}
end

local CMD = {
	STOP = 0,
	WAIT = 5,
	MOVE = 10,
	FIGHT = 16,
	ATTACK = 20,
	GUARD = 25,
	OPT_META = 4,
	OPT_RIGHT = 16,
	OPT_SHIFT = 32,
	OPT_CTRL = 64,
	OPT_ALT = 128,
}

-- The runtime's class, outbox and codec, and game.lua, over the fake VFS, with Spring.Echo kept in `echoes`.
local function loadOrders()
	local world = { echoes = {} }
	local env = setmetatable({ CMD = CMD }, { __index = _G })
	env.VFS = newVFS(env)
	env.Spring = {
		Echo = function(text)
			world.echoes[#world.echoes + 1] = text
		end,
	}
	env.VFS.Include(RUNTIME_PATH .. "class.lua")
	env.VFS.Include(RUNTIME_PATH .. "spring_lua/outbox.lua")
	world.codec = env.VFS.Include(CODEC_PATH)
	world.game = env.VFS.Include(RUNTIME_PATH .. "spring_lua/game.lua")
	world.env = env
	world.VFS = env.VFS
	return world
end

-- Reads a whole message back into tables, with the codec and the fake VFS.
local function decode(world, message)
	local codec = world.codec
	assert.is_true(codec.IsOrderMessage(message))
	local version, teamID, seq, frame, count, position = codec.UnpackHeader(message)
	local decoded = { version = version, teamID = teamID, seq = seq, frame = frame, orders = {} }
	for i = 1, count do
		local unitID, cmdID, options, paramCount, paramsPosition, nextPosition = codec.UnpackOrder(message, position)
		assert.is_not_nil(unitID, "order " .. i .. " runs past the message")
		local params = {}
		if paramCount > 0 then
			params = world.VFS.UnpackF32(message, paramsPosition, paramCount)
			params.n = nil
		end
		decoded.orders[i] = { unit = unitID, cmd = cmdID, options = options, params = params }
		position = nextPosition
	end
	assert.equal(#message + 1, position)
	return decoded
end

-- Flushes once and returns the decoded message, or nil when nothing was sent.
local function flush(world, outbox, frame)
	local sent
	local result = outbox:Flush(frame or 300, function(message)
		sent = message
	end)
	assert.equal(sent ~= nil, result)
	return sent and decode(world, sent)
end

local function units(decoded)
	local list = {}
	for i, order in ipairs(decoded.orders) do
		list[i] = order.unit
	end
	return list
end

local function echoesWith(world, text)
	local count = 0
	for _, line in ipairs(world.echoes) do
		if string.find(line, text, 1, true) then
			count = count + 1
		end
	end
	return count
end

-- Within half a unit in the last place of F32: 24 significant bits.
local function assertF32(expected, actual)
	assert.is_true(math.abs(actual - expected) <= math.abs(expected) * 2 ^ -24, expected .. " read as " .. actual)
end

describe("the fake VFS", function()
	it("writes the bytes Recoil writes", function()
		local VFS = loadOrders().VFS

		assert.equal("\0\0\128\63", VFS.PackF32(1))
		assert.equal("\0\0\0\192", VFS.PackF32(-2))
		assert.equal("\255\255\255\255", VFS.PackS32(-1))
		assert.equal("\2\1", VFS.PackU16(258))
		assert.equal("\1\2", VFS.PackU8({ 1, 2 }))
		assert.is_nil(VFS.PackF32({}))
	end)

	it("reads nothing at a position equal to the length", function()
		local VFS = loadOrders().VFS

		assert.is_nil(VFS.UnpackU8("\1\2", 2))
		assert.equal(2 * 256 + 1, VFS.UnpackU16("\1\2", 1))
	end)
end)

describe("OrderCodec", function()
	it("reads back every field of the orders it wrote", function()
		local world = loadOrders()
		local codec = world.codec
		local message = codec.PackHeader(7, 123456, 9000, 3)
			.. codec.PackOrder(65535, -2147483648, 255, { -1234.5678, 0.1, 40960 }, 3)
			.. codec.PackOrder(42, 2147483647, 0, { 3.25 }, 1)
			.. codec.PackOrder(0, -250, 96, { 1e-3, -7.75 }, 2)

		local decoded = decode(world, message)

		assert.equal(1, decoded.version)
		assert.equal(7, decoded.teamID)
		assert.equal(123456, decoded.seq)
		assert.equal(9000, decoded.frame)
		local expected = {
			{ unit = 65535, cmd = -2147483648, options = 255, params = { -1234.5678, 0.1, 40960 } },
			{ unit = 42, cmd = 2147483647, options = 0, params = { 3.25 } },
			{ unit = 0, cmd = -250, options = 96, params = { 1e-3, -7.75 } },
		}
		for i, order in ipairs(expected) do
			local got = decoded.orders[i]
			assert.equal(order.unit, got.unit)
			assert.equal(order.cmd, got.cmd)
			assert.equal(order.options, got.options)
			assert.equal(#order.params, #got.params)
			for k, value in ipairs(order.params) do
				assertF32(value, got.params[k])
			end
		end
	end)

	it("reads an order without params at the end of the message", function()
		local world = loadOrders()
		local codec = world.codec
		local message = codec.PackHeader(1, 1, 1, 2)
			.. codec.PackOrder(5, CMD.MOVE, 0, { 1, 2, 3 }, 3)
			.. codec.PackOrder(5, CMD.STOP, CMD.OPT_SHIFT, nil, 0)

		local decoded = decode(world, message)

		assert.is_nil(world.VFS.UnpackU8(message, #message))
		assert.same({ unit = 5, cmd = CMD.STOP, options = CMD.OPT_SHIFT, params = {} }, decoded.orders[2])
	end)

	it("reads nothing from a short header or an order cut short", function()
		local world = loadOrders()
		local codec = world.codec
		local header = codec.PackHeader(1, 1, 1, 1)
		local order = codec.PackOrder(5, CMD.MOVE, 0, { 1, 2, 3 }, 3)

		assert.is_nil(codec.UnpackHeader(string.sub(header, 1, 15)))
		assert.is_nil(codec.UnpackOrder(header .. string.sub(order, 1, 7), 17))
		assert.is_nil(codec.UnpackOrder(header .. string.sub(order, 1, #order - 1), 17))
		assert.is_false(codec.IsOrderMessage("@Shard[STGO]"))
	end)
end)

describe("ShardOutbox", function()
	it("turns options given as names, masks or arrays of masks into one byte", function()
		local world = loadOrders()
		local outbox = world.env.ShardOutbox(3)

		outbox:Queue(1, CMD.MOVE, nil, { "shift", "ctrl" })
		outbox:Queue(2, CMD.MOVE, nil, { "shift", "shift", "alt", "meta", "right" })
		outbox:Queue(3, CMD.MOVE, nil, { 0 })
		outbox:Queue(4, CMD.MOVE, nil, 64)
		outbox:Queue(5, CMD.MOVE, nil, nil)
		assert.is_false(outbox:Queue(6, CMD.MOVE, nil, { "bogus" }))
		assert.is_false(outbox:Queue(7, CMD.MOVE, nil, 256))
		local decoded = flush(world, outbox)

		local options = {}
		for i, order in ipairs(decoded.orders) do
			options[i] = order.options
		end
		assert.same({ 96, 180, 0, 64, 0 }, options)
		assert.equal(2, echoesWith(world, "dropped"))
	end)

	it("takes params as nothing, a number, an array or a position, up to 255 of them", function()
		local world = loadOrders()
		local outbox = world.env.ShardOutbox(3)
		local tooMany = {}
		for i = 1, 256 do
			tooMany[i] = i
		end

		outbox:Queue(1, CMD.STOP, nil, 0)
		outbox:Queue(2, CMD.GUARD, 77, 0)
		outbox:Queue(3, CMD.MOVE, { 1, 2, 3 }, 0)
		outbox:Queue(4, CMD.MOVE, { x = 10, y = 20, z = 30 }, 0)
		outbox:Queue(5, -300, { x = 10, y = 20, z = 30, 2 }, 0)
		assert.is_false(outbox:Queue(6, CMD.MOVE, { x = 10, z = 30 }, 0))
		assert.is_false(outbox:Queue(7, CMD.MOVE, tooMany, 0))
		assert.is_false(outbox:Queue(9, 2 ^ 31, nil, 0))
		assert.is_false(outbox:Queue(2 ^ 16, CMD.STOP, nil, 0))
		tooMany[256] = nil
		outbox:Queue(8, CMD.MOVE, tooMany, 0)
		local decoded = flush(world, outbox)

		assert.same({ 1, 2, 3, 4, 5, 8 }, units(decoded))
		assert.same({}, decoded.orders[1].params)
		assert.same({ 77 }, decoded.orders[2].params)
		assert.same({ 1, 2, 3 }, decoded.orders[3].params)
		assert.same({ 10, 20, 30 }, decoded.orders[4].params)
		assert.same({ 10, 20, 30, 2 }, decoded.orders[5].params)
		assert.equal(255, #decoded.orders[6].params)
		assert.equal(4, echoesWith(world, "dropped"))
	end)

	it("sends at most 25 orders a message, in order, without losing or repeating any", function()
		local world = loadOrders()
		local outbox = world.env.ShardOutbox(4)
		for unitID = 1, 60 do
			outbox:Queue(unitID, CMD.MOVE, { unitID, 0, -unitID }, 0)
		end

		local messages = { flush(world, outbox, 30), flush(world, outbox, 31), flush(world, outbox, 32) }

		assert.is_nil(flush(world, outbox, 33))
		local all = {}
		for i, decoded in ipairs(messages) do
			assert.equal(i, decoded.seq)
			assert.equal(29 + i, decoded.frame)
			assert.equal(4, decoded.teamID)
			for _, order in ipairs(decoded.orders) do
				all[#all + 1] = order.unit
				assert.same({ order.unit, 0, -order.unit }, order.params)
			end
		end
		assert.equal(25, #messages[1].orders)
		assert.equal(25, #messages[2].orders)
		assert.equal(10, #messages[3].orders)
		for unitID = 1, 60 do
			assert.equal(unitID, all[unitID])
		end
	end)

	it("keeps the orders of a group in one message", function()
		local world = loadOrders()
		local outbox = world.env.ShardOutbox(4)
		for unitID = 1, 20 do
			outbox:Queue(unitID, CMD.MOVE, nil, 0)
		end
		outbox:BeginGroup()
		for _ = 1, 10 do
			outbox:Queue(99, -300, 0, 0)
		end
		assert.is_true(outbox:EndGroup())
		outbox:Queue(100, CMD.STOP, nil, 0)

		local first = flush(world, outbox)
		local second = flush(world, outbox)

		assert.equal(20, #first.orders)
		assert.equal(11, #second.orders)
		assert.equal(99, second.orders[10].unit)
		assert.equal(100, second.orders[11].unit)
	end)

	it("sends a group larger than 25 orders alone", function()
		local world = loadOrders()
		local outbox = world.env.ShardOutbox(4)
		outbox:BeginGroup()
		for _ = 1, 30 do
			outbox:Queue(99, -300, 0, 0)
		end
		outbox:EndGroup()
		outbox:Queue(100, CMD.STOP, nil, 0)

		assert.equal(30, #flush(world, outbox).orders)
		assert.same({ 100 }, units(flush(world, outbox)))
	end)

	it("drops a whole group when one of its orders is dropped", function()
		local world = loadOrders()
		local outbox = world.env.ShardOutbox(4)
		outbox:Queue(1, CMD.STOP, nil, 0)
		outbox:BeginGroup()
		outbox:Queue(2, CMD.MOVE, { 1, 2, 3 }, 0)
		outbox:Queue(2, CMD.MOVE, { x = 1 }, 0)
		outbox:Queue(2, CMD.MOVE, { 4, 5, 6 }, 0)
		assert.is_false(outbox:EndGroup())
		outbox:Queue(3, CMD.STOP, nil, 0)

		assert.same({ 1, 3 }, units(flush(world, outbox)))
		assert.equal(1, echoesWith(world, "dropped"))
	end)

	it("starts again from seq 1 with an empty queue after Reset", function()
		local world = loadOrders()
		local outbox = world.env.ShardOutbox(4)
		for unitID = 1, 30 do
			outbox:Queue(unitID, CMD.STOP, nil, 0)
		end
		flush(world, outbox)

		outbox:Reset()

		assert.is_nil(flush(world, outbox))
		outbox:Queue(5, CMD.STOP, nil, 0)
		local decoded = flush(world, outbox)
		assert.equal(1, decoded.seq)
		assert.same({ 5 }, units(decoded))
	end)

	it("sends nothing while the queue is empty", function()
		local world = loadOrders()
		local outbox = world.env.ShardOutbox(4)
		local sends = 0

		local result = outbox:Flush(1, function()
			sends = sends + 1
		end)

		assert.is_false(result)
		assert.equal(0, sends)
	end)
end)

describe("game:GiveOrder", function()
	local world, game, outbox, warnings

	before_each(function()
		world = loadOrders()
		game = world.game
		outbox = world.env.ShardOutbox(2)
		warnings = {}
		game.ai = {
			outbox = outbox,
			Warn = function(_, text)
				warnings[#warnings + 1] = text
			end,
		}
	end)

	it("'1-1' queues one command for one unit", function()
		assert.is_true(game:GiveOrder(11, CMD.GUARD, 12, 0, "1-1"))

		assert.same({ { unit = 11, cmd = CMD.GUARD, options = 0, params = { 12 } } }, flush(world, outbox).orders)
	end)

	it("'2-1' queues the commands of one unit together", function()
		for unitID = 1, 24 do
			outbox:Queue(unitID, CMD.STOP, nil, 0)
		end

		assert.is_true(game:GiveOrder(7, { -101, -101, -102 }, { 0, 0, 0 }, { 0, 0, { "shift" } }, "2-1"))

		assert.equal(24, #flush(world, outbox).orders)
		assert.same({
			{ unit = 7, cmd = -101, options = 0, params = { 0 } },
			{ unit = 7, cmd = -101, options = 0, params = { 0 } },
			{ unit = 7, cmd = -102, options = CMD.OPT_SHIFT, params = { 0 } },
		}, flush(world, outbox).orders)
	end)

	it("'1-2' queues one command for every unit", function()
		assert.is_true(game:GiveOrder({ 3, 1, 2 }, CMD.MOVE, { x = 5, y = 6, z = 7 }, 0, "1-2"))

		local orders = flush(world, outbox).orders
		assert.same({ 3, 1, 2 }, { orders[1].unit, orders[2].unit, orders[3].unit })
		for _, order in ipairs(orders) do
			assert.equal(CMD.MOVE, order.cmd)
			assert.same({ 5, 6, 7 }, order.params)
		end
	end)

	it("'2-2' gives the i-th command to the i-th unit, up to the shorter array", function()
		local commands = { CMD.FIGHT, CMD.ATTACK, CMD.MOVE }

		assert.is_true(game:GiveOrder({ 1, 2 }, commands, { { 1, 2, 3 }, 9 }, { 0, { "shift" } }, "2-2"))

		assert.same({
			{ unit = 1, cmd = CMD.FIGHT, options = 0, params = { 1, 2, 3 } },
			{ unit = 2, cmd = CMD.ATTACK, options = CMD.OPT_SHIFT, params = { 9 } },
		}, flush(world, outbox).orders)
	end)

	it("drops a '1-2' call with an array of commands, with a warning", function()
		assert.is_false(game:GiveOrder({ 1, 2 }, { CMD.FIGHT, CMD.FIGHT }, { 1, 2 }, { 0, 0 }, "1-2"))

		assert.is_nil(flush(world, outbox))
		assert.equal(1, #warnings)
	end)

	it("warns about an unknown method", function()
		assert.is_false(game:GiveOrder(1, CMD.STOP, nil, 0, "3-1"))

		assert.is_nil(flush(world, outbox))
		assert.equal(1, #warnings)
	end)

	it("warns once and queues nothing without an outbox", function()
		game.ai.outbox = nil

		assert.is_false(game:GiveOrder(1, CMD.STOP, nil, 0, "1-1"))
		assert.is_false(game:GiveOrder(2, CMD.STOP, nil, 0, "1-1"))

		assert.equal(1, #warnings)
	end)
end)
