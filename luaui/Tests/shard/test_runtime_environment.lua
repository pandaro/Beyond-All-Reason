local RUNTIME_PATH = "luarules/gadgets/ai/shard_runtime/"

local function assertEqual(expected, actual, what)
	assert(expected == actual, ("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)))
end

-- The runtime files run in the environment boot.lua runs in, never in the global one: the loader and the AI types
-- read the runtime classes from there.
local function test_runtime_files_run_in_the_boot_environment()
	local env = setmetatable({}, { __index = getfenv(1) })
	VFS.Include(RUNTIME_PATH .. "spring_lua/boot.lua", env)

	assertEqual("function", type(env.class), "class")
	assertEqual("table", type(env.ShardAI), "ShardAI")
	assertEqual("table", type(env.ShardOutbox), "ShardOutbox")
	assertEqual("table", type(env.ShardUnit), "ShardUnit")

	env.ShardSpringLua = true
	local api = VFS.Include(RUNTIME_PATH .. "api.lua", env)
	assertEqual(env, getfenv(api.game.GiveOrder), "environment of game.lua")
	assertEqual(env, getfenv(api.map.MapName), "environment of map.lua")
end

local function test()
	test_runtime_files_run_in_the_boot_environment()
end

return { test = test }
