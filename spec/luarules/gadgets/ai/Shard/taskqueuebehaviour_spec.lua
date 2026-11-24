---@diagnostic disable: undefined-field, call-non-callable

-- Loads the runtime's class and AIBase, Shard/behaviour.lua and Shard/taskqueuebehaviour.lua, in unsynced code as
-- the AIs run: no SendToUnsynced; LuaUI without the debug widget.
local function loadTaskQueueBehaviour()
	local env = setmetatable({
		Script = { LuaUI = setmetatable({}, {
			__call = function()
				return false
			end,
		}) },
	}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/Shard/behaviour.lua",
		"luarules/gadgets/ai/Shard/taskqueuebehaviour.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	return env
end

describe("Shard TaskQueueBehaviour", function()
	it("marks a debug point in unsynced code, where SendToUnsynced does not exist", function()
		local behaviour = loadTaskQueueBehaviour().TaskQueueBehaviour()
		behaviour.unit = {
			Internal = function()
				return {
					GetPosition = function()
						return { x = 1, y = 2, z = 3 }
					end,
				}
			end,
		}

		assert.has_no.errors(function()
			behaviour:DebugPoint("success")
		end)
	end)
end)
