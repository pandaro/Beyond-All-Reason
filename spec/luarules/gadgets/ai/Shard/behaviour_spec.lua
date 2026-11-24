---@diagnostic disable: undefined-field

-- Loads the runtime's class and AIBase, then Shard/behaviour.lua, in an environment of their own.
local function loadBehaviour()
	local env = setmetatable({}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/Shard/behaviour.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	return env
end

describe("Shard Behaviour", function()
	it("has every Owner callback the runtime's Unit calls", function()
		local Behaviour = loadBehaviour().Behaviour

		for _, name in ipairs({
			"OwnerCreated",
			"OwnerBuilt",
			"OwnerDead",
			"OwnerDamaged",
			"OwnerIdle",
			"OwnerMoveFailed",
		}) do
			assert.is_function(Behaviour[name], name)
		end
	end)
end)
