---@diagnostic disable: undefined-global, undefined-field, global-in-non-module, call-non-callable

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

	it("runs TaskQueueBehaviour in turns", function()
		require("Shard/boot")

		assert.same({ TaskQueueBehaviour = true }, ai.scheduledBehaviours)
		assert.equal("TaskQueueBehaviour", TaskQueueBehaviour():Name())
	end)

	it(
		"moves a task queue on at the first Update after 15 frames, whether it comes every frame or every third",
		function()
			require("Shard/boot")

			local function framesToProgress(step)
				local frame = 0
				local behaviour = TaskQueueBehaviour()
				behaviour.game = {
					Frame = function()
						return frame
					end,
				}
				behaviour.active = true
				behaviour.progress = true
				behaviour.countdown = 0
				local progressedAt = nil
				function behaviour:ProgressQueue()
					progressedAt = progressedAt or frame
				end
				while progressedAt == nil and frame < 100 do
					frame = frame + step
					behaviour:Update()
				end
				return progressedAt
			end

			assert.equal(16, framesToProgress(1))
			-- frames 1, 3, 3, 3, 3, 3 counted by frame 18: the next Update, at frame 21, moves on
			assert.equal(21, framesToProgress(3))
		end
	)
end)
