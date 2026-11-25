---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase and Module, then STAI/maphst.lua, in an environment of their own; the map
-- records the channels EraseAll gets.
local function newMapHST(drawDebug)
	local env = setmetatable({
		shard_include = function() end,
	}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/maphst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local mapHST = env.MapHST()
	local erased = {}
	mapHST.ai = { drawDebug = drawDebug }
	mapHST.map = {
		EraseAll = function(_, channel)
			erased[#erased + 1] = channel
		end,
	}
	return mapHST, erased
end

describe("STAI MapHST", function()
	it("erases no debug channel when the debug drawing is off", function()
		local mapHST, erased = newMapHST(false)

		mapHST:DrawDebug()

		assert.same({}, erased)
	end)
end)
