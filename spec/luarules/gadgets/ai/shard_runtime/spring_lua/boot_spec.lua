---@diagnostic disable: undefined-field

local BOOT_PATH = "luarules/gadgets/ai/shard_runtime/spring_lua/boot.lua"
local RUNTIME_PATH = "luarules/gadgets/ai/shard_runtime"
local ALPHA_PATH = "luarules/gadgets/ai/Alpha"
local BETA_PATH = "luarules/gadgets/ai/Beta"

-- Loads boot.lua over a VFS of fake files. A fake file is a function run with the environment it is included into,
-- as VFS.Include(path, env) runs a real one, or with boot.lua's own environment when none is given. Every run is
-- counted, and lookups ignore case like the engine's VFS. boot.lua's own start-up includes find no file and only echo.
local function loadBoot(files)
	local world = { runs = {}, echoes = {} }
	local byPath = {}
	for path, body in pairs(files) do
		byPath[string.lower(path)] = body
	end

	local env
	env = setmetatable({
		VFS = {
			FileExists = function(path)
				return byPath[string.lower(path)] ~= nil
			end,
			Include = function(path, includeEnv)
				local key = string.lower(path)
				world.runs[key] = (world.runs[key] or 0) + 1
				return byPath[key](includeEnv or env)
			end,
		},
		Spring = {
			Echo = function(text)
				world.echoes[#world.echoes + 1] = text
			end,
		},
	}, { __index = _G })

	local chunk = assert(loadfile(BOOT_PATH))
	setfenv(chunk, env)
	chunk()

	world.env = env
	return world
end

local function runs(world, path)
	return world.runs[string.lower(path)] or 0
end

-- A file that defines the global class Foo in whatever environment it runs in, as `Foo = class(...)` would.
local function definesFoo(label)
	return function(env)
		env.Foo = { label = label }
		return env.Foo
	end
end

local function returns(value)
	return function()
		return value
	end
end

describe("shard_generate_include_func", function()
	describe("with an AI type environment", function()
		it("keeps a class defined by two AI types apart, and out of the global environment", function()
			local world = loadBoot({
				[ALPHA_PATH .. "/foo.lua"] = definesFoo("alpha"),
				[BETA_PATH .. "/foo.lua"] = definesFoo("beta"),
			})
			local alphaEnv, betaEnv = {}, {}
			local alphaInclude = world.env.shard_generate_include_func(RUNTIME_PATH, ALPHA_PATH, alphaEnv)
			local betaInclude = world.env.shard_generate_include_func(RUNTIME_PATH, BETA_PATH, betaEnv)

			alphaInclude("foo")
			betaInclude("foo")

			assert.equal("alpha", alphaEnv.Foo.label)
			assert.equal("beta", betaEnv.Foo.label)
			assert.is_nil(rawget(world.env, "Foo"))
			assert.is_nil(rawget(_G, "Foo"))
		end)

		it("runs a file included twice once, and returns its value both times", function()
			local world = loadBoot({ [ALPHA_PATH .. "/foo.lua"] = definesFoo("alpha") })
			local shardInclude = world.env.shard_generate_include_func(RUNTIME_PATH, ALPHA_PATH, {})

			local first = shardInclude("foo")
			local second = shardInclude("foo")

			assert.equal(1, runs(world, ALPHA_PATH .. "/foo.lua"))
			assert.equal("alpha", first.label)
			assert.equal(first, second)
		end)

		it("does not run a file again when it is asked for with different case", function()
			local world = loadBoot({ [ALPHA_PATH .. "/foo.lua"] = definesFoo("alpha") })
			local shardInclude = world.env.shard_generate_include_func(RUNTIME_PATH, ALPHA_PATH, {})

			local first = shardInclude("foo")
			local second = shardInclude("Foo")

			assert.equal(1, runs(world, ALPHA_PATH .. "/foo.lua"))
			assert.equal(first, second)
		end)

		it("does not run a file again when it returned nil or false", function()
			local world = loadBoot({
				[ALPHA_PATH .. "/nothing.lua"] = returns(nil),
				[ALPHA_PATH .. "/no.lua"] = returns(false),
			})
			local shardInclude = world.env.shard_generate_include_func(RUNTIME_PATH, ALPHA_PATH, {})

			shardInclude("nothing")
			shardInclude("no")

			assert.is_nil(shardInclude("nothing"))
			assert.equal(false, shardInclude("no"))
			assert.equal(1, runs(world, ALPHA_PATH .. "/nothing.lua"))
			assert.equal(1, runs(world, ALPHA_PATH .. "/no.lua"))
		end)

		it("runs a runtime file once for each AI type that includes it", function()
			local world = loadBoot({ [RUNTIME_PATH .. "/foo.lua"] = definesFoo("runtime") })
			local alphaEnv, betaEnv = {}, {}
			local alphaInclude = world.env.shard_generate_include_func(RUNTIME_PATH, ALPHA_PATH, alphaEnv)
			local betaInclude = world.env.shard_generate_include_func(RUNTIME_PATH, BETA_PATH, betaEnv)

			alphaInclude("foo")
			alphaInclude("foo")
			betaInclude("foo")
			betaInclude("foo")

			assert.equal(2, runs(world, RUNTIME_PATH .. "/foo.lua"))
			assert.is_not_nil(alphaEnv.Foo)
			assert.is_not_nil(betaEnv.Foo)
			assert.are_not.equal(alphaEnv.Foo, betaEnv.Foo)
		end)
	end)

	describe("without an environment", function()
		it("runs the file in the caller's environment on every include", function()
			local world = loadBoot({ [ALPHA_PATH .. "/foo.lua"] = definesFoo("alpha") })
			local shardInclude = world.env.shard_generate_include_func(RUNTIME_PATH, ALPHA_PATH)

			shardInclude("foo")
			shardInclude("foo")

			assert.equal(2, runs(world, ALPHA_PATH .. "/foo.lua"))
			assert.equal("alpha", rawget(world.env, "Foo").label)
		end)
	end)
end)
