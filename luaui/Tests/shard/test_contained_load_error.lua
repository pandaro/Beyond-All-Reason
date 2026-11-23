-- An AI type whose boot.lua fails is contained by xpcall, as the loader's AddAI loads it: the error comes back
-- with its traceback, and LuaRules goes on including files.
local function test_broken_ai_type_is_contained()
	local env = setmetatable({}, { __index = getfenv(1) })
	local traceback = debug and debug.traceback or tostring
	local ok, err = xpcall(function()
		return VFS.Include("spec/fixtures/shard_ai_broken/boot.lua", env)
	end, traceback)

	assert(not ok, "the broken boot.lua loaded")
	assert(string.find(tostring(err), "broken boot", 1, true), "unexpected error: " .. tostring(err))
	local codec = VFS.Include("luarules/gadgets/ai/shard_runtime/ordercodec.lua")
	assert(codec.MAGIC == "AIFw", "LuaRules could not include a file after the error")
end

local function test()
	test_broken_ai_type_is_contained()
end

return { test = test }
