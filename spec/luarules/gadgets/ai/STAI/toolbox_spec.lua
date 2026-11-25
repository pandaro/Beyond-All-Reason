---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads files in an environment of their own; shard_include runs STAI's toolbox.lua and ignores the other files.
local function newEnvironment()
	local env = setmetatable({}, { __index = _G })
	local function run(path)
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	env.shard_include = function(name)
		if name == "toolbox" then
			run("luarules/gadgets/ai/STAI/toolbox.lua")
		end
	end
	return env, run
end

local function newToolbox()
	local env, run = newEnvironment()
	run("luarules/gadgets/ai/STAI/toolbox.lua")
	return env.Toolbox
end

local function newTool()
	local env, run = newEnvironment()
	run("luarules/gadgets/ai/shard_runtime/class.lua")
	run("luarules/gadgets/ai/shard_runtime/aibase.lua")
	run("luarules/gadgets/ai/shard_runtime/module.lua")
	run("luarules/gadgets/ai/STAI/tool.lua")
	return env.Tool(), env.Toolbox
end

describe("STAI Toolbox", function()
	local Toolbox = newToolbox()

	it("measures distance on the ground, and DISTANCE and RawDistance in three dimensions", function()
		local a = { x = 1, y = 100, z = 2 }
		local b = { x = 4, y = 112, z = 6 }
		assert.equal(5, Toolbox:distance(a, b))
		assert.equal(13, Toolbox:DISTANCE(a, b))
		assert.equal(13, Toolbox:RawDistance(1, 100, 2, 4, 112, 6))
		assert.equal(13, Toolbox:RawDistance(4, 112, 6, 1, 100, 2))
	end)

	it("finds the greatest common divisor", function()
		assert.equal(6, Toolbox:gcd(12, 18))
		assert.equal(6, Toolbox:gcd(18, 12))
		assert.equal(7, Toolbox:gcd(7, 0))
		assert.equal(1, Toolbox:gcd(9, 4))
		assert.equal(2048, Toolbox:gcd(10240, 6144))
	end)

	it("sorts positions from the nearest on the ground", function()
		local near = { x = 10, y = 900, z = 0 }
		local middle = { x = 0, y = 0, z = 20 }
		local far = { x = 30, y = 0, z = 0 }
		local sorted = Toolbox:sortByDistance({ x = 0, y = 0, z = 0 }, { far, near, middle })
		assert.equal(3, #sorted)
		assert.is_true(rawequal(near, sorted[1]))
		assert.is_true(rawequal(middle, sorted[2]))
		assert.is_true(rawequal(far, sorted[3]))
	end)

	it("keeps both positions at the same distance", function()
		local Toolbox = newToolbox()
		local east = { x = 10, y = 0, z = 0 }
		local north = { x = 0, y = 0, z = 10 }
		local near = { x = 5, y = 0, z = 0 }
		local sorted = Toolbox:sortByDistance({ x = 0, y = 0, z = 0 }, { east, north, near })
		assert.equal(3, #sorted)
		assert.is_true(rawequal(near, sorted[1]))
		local second, third = sorted[2], sorted[3]
		assert.is_true(
			rawequal(east, second) and rawequal(north, third) or rawequal(north, second) and rawequal(east, third)
		)
	end)

	it("concatenates every value in the array part, in the order of the given tables", function()
		local T = assert(Toolbox:tableConcat({ { "a", "b" }, {}, { "c", "d", "e" } }))
		assert.equal(5, #T)
		assert.same({ "a", "b", "c", "d", "e" }, T)
		assert.same({ "x" }, Toolbox:tableConcat({ { "x" } }))
		assert.is_nil(Toolbox:tableConcat("not a table"))
	end)
end)

describe("STAI Tool", function()
	it("answers the Toolbox helpers with Toolbox as self", function()
		local tool, Toolbox = newTool()
		tool.distance = function()
			error("the Toolbox helper called the Tool instance")
		end
		local origin = { x = 0, y = 0, z = 0 }
		local near = { x = 1, y = 0, z = 0 }
		local far = { x = 2, y = 0, z = 0 }
		local sorted = tool:sortByDistance(origin, { far, near })
		assert.is_true(rawequal(near, sorted[1]))
		assert.equal(Toolbox:gcd(12, 18), tool:gcd(12, 18))
	end)
end)
