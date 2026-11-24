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

	-- the lines the AI objects print while Shard boots: { owner, text } for each print
	local function bootPrinting()
		local lines = {}
		local savedPrint = _G.print
		_G.print = function(owner, ...)
			lines[#lines + 1] = { owner = owner, text = table.concat({ tostring(owner), ... }, " ") }
		end
		local ok, err = pcall(function()
			require("Shard/boot")
		end)
		_G.print = savedPrint
		assert(ok, err)
		return lines
	end

	it("builds the ally and global objects and shares the ally's PerceptionHandler with the team", function()
		local lines = bootPrinting()

		for _, line in ipairs(lines) do
			assert.is_nil(string.find(line.text, "Skipping the loading", 1, true), line.text)
		end
		assert.equal("ally", ai.ally:Scope())
		assert.equal("global", ai.global:Scope())
		assert.equal(ai.global, ai.ally.global)
		assert.equal(0, ai.ally.allyId)
		assert.same({ ai }, ai.ally.AIs)
		assert.same({ ai }, ai.global.AIs)
		assert.is_true(ai.ally.loaded)
		assert.is_true(ai.global.loaded)
		assert.is_table(ai.perceptionhandler)
		assert.equal(ai.ally.perceptionhandler, ai.perceptionhandler)
		assert.same({ ai.perceptionhandler }, ai.ally.modules)
		assert.same({}, ai.global.modules)
		assert.equal(5, #ai.modules)
		for _, m in ipairs(ai.modules) do
			assert.equal("team", m:Scope())
		end
		assert.are_not.equal(ai.api.game, ai.ally.api.game)
		assert.equal(ai.ally, ai.ally.game.ai)
	end)

	it("runs Init on the global object, then the ally, then the team", function()
		local owners = {}
		for _, line in ipairs(bootPrinting()) do
			if string.find(line.text, " - playing: ", 1, true) then
				owners[#owners + 1] = line.owner
			end
		end

		assert.same({ "global", "ally 0", 0 }, owners)
	end)

	it("tells the ally object's PerceptionHandler what the ally team sees", function()
		require("Shard/boot")

		ai.ally:UnitEnteredLos(42, 1, 1, 7)
		assert.is_true(ai.perceptionhandler:Sees(42))
		ai.ally:UnitLeftLos(42, 1, 1, 7)
		assert.is_false(ai.perceptionhandler:Sees(42))
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
