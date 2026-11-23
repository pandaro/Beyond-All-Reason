local OrderCodec = VFS.Include("luarules/gadgets/ai/shard_runtime/ordercodec.lua")

-- Within half a unit in the last place of F32: 24 significant bits.
local function assertF32(expected, actual)
	assert(math.abs(actual - expected) <= math.abs(expected) * 2 ^ -24, ("%s read as %s"):format(expected, actual))
end

local function assertEqual(expected, actual, what)
	assert(expected == actual, ("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)))
end

local function test_byte_order()
	assertEqual("\0\0\128\63", VFS.PackF32(1), "F32 1")
	assertEqual("\0\0\0\192", VFS.PackF32(-2), "F32 -2")
	assertEqual("\255\255\255\255", VFS.PackS32(-1), "S32 -1")
	assertEqual("\2\1", VFS.PackU16(258), "U16 258")
	assertEqual(nil, VFS.UnpackU8("\1\2", 2), "U8 at the last byte")
end

local function test_round_trip()
	-- Integers exact as single precision floats too, as Lua numbers are in the engine.
	local orders = {
		{ unit = 65535, cmd = -2147483648, options = 255, params = { -1234.5678, 0.1, 40960 } },
		{ unit = 1, cmd = 2147483520, options = 0, params = { 16777216 } },
		{ unit = 42, cmd = CMD.GUARD, options = CMD.OPT_SHIFT, params = { 3.25 } },
		{ unit = 0, cmd = -250, options = 0, params = { 1e-3, -7.75, 0, 2 } },
		{ unit = 42, cmd = CMD.STOP, options = CMD.OPT_SHIFT + CMD.OPT_CTRL, params = {} },
	}
	local pieces = { OrderCodec.PackHeader(255, 4294967040, 16777216, #orders) }
	for i, order in ipairs(orders) do
		pieces[i + 1] = OrderCodec.PackOrder(order.unit, order.cmd, order.options, order.params, #order.params)
	end
	local message = table.concat(pieces)

	assert(OrderCodec.IsOrderMessage(message), "magic")
	local version, teamID, seq, frame, count, position = OrderCodec.UnpackHeader(message)
	assertEqual(OrderCodec.VERSION, version, "version")
	assertEqual(255, teamID, "teamID")
	assertEqual(4294967040, seq, "seq")
	assertEqual(16777216, frame, "frame")
	assertEqual(#orders, count, "count")
	for i, order in ipairs(orders) do
		local unitID, cmdID, options, paramCount, paramsPosition, nextPosition =
			OrderCodec.UnpackOrder(message, position)
		assertEqual(order.unit, unitID, "unitID of order " .. i)
		assertEqual(order.cmd, cmdID, "cmdID of order " .. i)
		assertEqual(order.options, options, "options of order " .. i)
		assertEqual(#order.params, paramCount, "params of order " .. i)
		if paramCount > 0 then
			---@diagnostic disable-next-line: redundant-parameter
			local params = VFS.UnpackF32(message, paramsPosition, paramCount) --[[@as number[] ]]
			for k, value in ipairs(order.params) do
				assertF32(value, params[k])
			end
		end
		position = nextPosition
	end
	assertEqual(#message + 1, position, "end of the message")
	assertEqual(nil, OrderCodec.UnpackOrder(string.sub(message, 1, #message - 1), position - 8), "cut order")
end

function test()
	test_byte_order()
	test_round_trip()
end

return { test = test }
