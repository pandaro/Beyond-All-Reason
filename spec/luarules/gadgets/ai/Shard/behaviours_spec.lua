---@diagnostic disable: undefined-field

-- Loads Shard/behaviours.lua with a shard_include that runs nothing, as the AI type's environment would hold it.
local function loadBehaviours()
	local env = setmetatable({
		shard_include = function() end,
	}, { __index = _G })
	local chunk = assert(loadfile("luarules/gadgets/ai/Shard/behaviours.lua"))
	setfenv(chunk, env)
	chunk()
	return env
end

describe("Shard behaviours", function()
	it("defines the table of behaviours by unit name that BehaviourFactory reads, empty", function()
		local env = loadBehaviours()

		assert.same({}, env.behaviours)
		assert.is_function(env.defaultBehaviours)
	end)
end)
