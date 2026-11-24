---@diagnostic disable: undefined-global, undefined-field, global-in-non-module

-- Shard, the example AI, outside the engine with shard_null: require finds the AI and the runtime through
-- package.path, as a test or a tool outside the engine would run it.
describe("Shard under shard_null", function()
	local savedPath = package.path
	local savedLoaded = {}

	before_each(function()
		for name, value in pairs(package.loaded) do
			savedLoaded[name] = value
		end
		package.path = "luarules/gadgets/ai/?.lua;" .. savedPath
	end)

	after_each(function()
		package.path = savedPath
		for name in pairs(package.loaded) do
			if savedLoaded[name] == nil then
				package.loaded[name] = nil
			end
		end
		ai, game, map = nil, nil, nil
	end)

	it("loads, runs Init and a few Update without errors", function()
		require("Shard/boot")

		assert.equal("Shard", ai:Name())
		assert.is_true(ai.loaded)
		assert.equal(5, #ai.modules)
		assert.is_table(ai.placementhandler)
		for _ = 1, 5 do
			ai:Update()
		end
	end)

	it("runs AttackHandler and PlacementHandler in turns and the other modules every frame", function()
		require("Shard/boot")

		local everyFrame = {}
		for i, m in ipairs(ai.handlers.Update) do
			everyFrame[i] = m:Name()
		end
		assert.same({ "UnitHandler", "Sleep" }, everyFrame)
		assert.equal(ai.attackhandler, ai.scheduledModules[1])
		assert.equal(ai.placementhandler, ai.scheduledModules[2])
	end)
end)
