---@diagnostic disable: undefined-field, call-non-callable

-- Loads the runtime's class, AIBase and Module, then Shard/placementhandler.lua, in an environment of their own.
local function loadPlacementHandler()
	local env = setmetatable({}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/Shard/placementhandler.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	return env
end

describe("Shard PlacementHandler", function()
	it("starts a job at the given position, snapped to a 16 elmo grid", function()
		local handler = loadPlacementHandler().PlacementHandler()
		handler:Init()

		local accepted = handler:NewJob({ start_position = { x = 33, y = 5, z = 50 }, unittype = {} })

		assert.is_true(accepted)
		assert.equal(1, #handler.jobs)
		assert.same({ x = 32, y = 5, z = 48 }, handler.jobs[1].start_position)
	end)
end)
