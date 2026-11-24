---@diagnostic disable: undefined-field, need-check-nil, inject-field

local RUNTIME_PATH = "luarules/gadgets/ai/shard_runtime/"
local RUNTIME_FILES = { "class", "aibase", "behaviour", "unit" }

-- The runtime's Unit and Behaviour in an environment of their own, as spring_lua/boot.lua loads them.
local function loadRuntime()
	local env = setmetatable({ Spring = { Echo = function() end } }, { __index = _G })
	for _, name in ipairs(RUNTIME_FILES) do
		local chunk = assert(loadfile(RUNTIME_PATH .. name .. ".lua"))
		setfenv(chunk, env)
		chunk()
	end
	return env
end

-- A unit with one behaviour per entry of priorities (a number, or false for a nil priority), named b1, b2...
-- Every call a behaviour gets that matters to the election goes to log as "<name>:<call>".
local function newUnit(env, priorities, ai)
	local log = {}
	local unit = env.Unit()
	unit.ai = ai or {}
	unit:SetEngineRepresentation({
		ID = function()
			return 1
		end,
	})
	unit:Init()
	local behaviours = {}
	for i, priority in ipairs(priorities) do
		local name = "b" .. i
		local class = env.class(env.Behaviour)
		function class:Name()
			return name
		end
		function class:Priority()
			return self.score
		end
		for _, call in ipairs({ "PreActivate", "Activate", "PreDeactivate", "Deactivate" }) do
			class[call] = function()
				log[#log + 1] = name .. ":" .. call
			end
		end
		local behaviour = class()
		behaviour.score = priority or nil
		unit:AddBehaviour(behaviour)
		behaviours[i] = behaviour
	end
	return unit, behaviours, log
end

-- Elects, then runs one update, as the unit gets it on the next frame.
local function electAndUpdate(unit)
	unit:ElectBehaviour()
	unit:Update()
end

describe("Shard runtime Unit", function()
	local env ---@type table

	before_each(function()
		env = loadRuntime()
	end)

	describe("electing a behaviour", function()
		it("gives the unit to the highest priority above zero", function()
			local unit, b = newUnit(env, { 10, 300, 50 })

			electAndUpdate(unit)

			assert.equal(b[2], unit:ActiveBehaviour())
		end)

		it("counts a nil priority as zero", function()
			local unit, b = newUnit(env, { false, 5 })

			electAndUpdate(unit)
			assert.equal(b[2], unit:ActiveBehaviour())

			b[2].score = nil
			electAndUpdate(unit)
			assert.is_nil(unit:ActiveBehaviour())
		end)

		it("activates no behaviour when no priority is above zero", function()
			local unit = newUnit(env, { 0, -5, false })

			electAndUpdate(unit)

			assert.is_nil(unit:ActiveBehaviour())
		end)

		it("deactivates the active behaviour at once when no priority is left above zero", function()
			local unit, b, log = newUnit(env, { 20, 10 })
			electAndUpdate(unit)
			b[1].score = 0
			b[2].score = -1

			unit:ElectBehaviour()

			assert.same({ "b1:PreActivate", "b1:Activate", "b1:PreDeactivate", "b1:Deactivate" }, log)
			assert.is_nil(unit:ActiveBehaviour())
			unit:Update()
			assert.equal(4, #log)
			assert.is_nil(unit:ActiveBehaviour())
		end)

		it("gives a tie to the first in the list", function()
			local unit, b = newUnit(env, { 7, 40, 40 })

			electAndUpdate(unit)

			assert.equal(b[2], unit:ActiveBehaviour())
		end)

		it("changes nothing when the active behaviour wins again", function()
			local unit, b, log = newUnit(env, { 30, 10 })
			electAndUpdate(unit)
			b[1].score = 25

			electAndUpdate(unit)

			assert.same({ "b1:PreActivate", "b1:Activate" }, log)
			assert.equal(b[1], unit:ActiveBehaviour())
		end)

		it("deactivates the loser at once and activates the winner on the next update", function()
			local unit, b, log = newUnit(env, { 30, 10 })
			electAndUpdate(unit)
			b[2].score = 60

			unit:ElectBehaviour()

			assert.same({ "b1:PreActivate", "b1:Activate", "b1:PreDeactivate", "b1:Deactivate" }, log)
			assert.is_nil(unit:ActiveBehaviour())
			unit:Update()
			assert.same({ "b2:PreActivate", "b2:Activate" }, { log[5], log[6] })
			assert.equal(b[2], unit:ActiveBehaviour())
		end)

		it("drops a waiting behaviour that loses before its update", function()
			local unit, b, log = newUnit(env, { 30, 10, 5 })
			unit:ElectBehaviour()
			b[1].score = 0

			unit:ElectBehaviour()
			unit:Update()
			assert.equal(b[2], unit:ActiveBehaviour())

			b[2].score = 0
			b[3].score = 0
			electAndUpdate(unit)
			b[3].score = 9
			unit:ElectBehaviour()
			b[3].score = 0
			electAndUpdate(unit)

			assert.same({
				"b2:PreActivate",
				"b2:Activate",
				"b2:PreDeactivate",
				"b2:Deactivate",
			}, log)
			assert.is_nil(unit:ActiveBehaviour())
		end)

		it("does not deactivate a behaviour twice when two elections come before an update", function()
			local unit, b, log = newUnit(env, { 30, 10, 5 })
			electAndUpdate(unit)
			b[1].score = 0

			unit:ElectBehaviour()
			b[2].score = 0
			unit:ElectBehaviour()
			unit:Update()

			assert.same({
				"b1:PreActivate",
				"b1:Activate",
				"b1:PreDeactivate",
				"b1:Deactivate",
				"b3:PreActivate",
				"b3:Activate",
			}, log)
			assert.equal(b[3], unit:ActiveBehaviour())
		end)
	end)

	describe("electing a behaviour with legacyElection", function()
		local legacy = { legacyElection = true }

		it("gives the unit to the highest priority above zero", function()
			local unit, b = newUnit(env, { 10, 300, 50 }, legacy)

			electAndUpdate(unit)

			assert.equal(b[2], unit:ActiveBehaviour())
		end)

		it("gives the unit to the first in the list when no priority is above zero", function()
			local unit, b = newUnit(env, { 0, -5, -1 }, legacy)

			electAndUpdate(unit)

			assert.equal(b[1], unit:ActiveBehaviour())
		end)

		it("keeps the active behaviour when no priority is left above zero", function()
			local unit, b, log = newUnit(env, { 20, 10 }, legacy)
			electAndUpdate(unit)
			b[1].score = 0
			b[2].score = -1

			electAndUpdate(unit)

			assert.same({ "b1:PreActivate", "b1:Activate" }, log)
			assert.equal(b[1], unit:ActiveBehaviour())
		end)

		it("gives a tie to the first in the list", function()
			local unit, b = newUnit(env, { 7, 40, 40 }, legacy)

			electAndUpdate(unit)

			assert.equal(b[2], unit:ActiveBehaviour())
		end)

		it("lets the first behaviour win with a nil priority, and fails on a nil priority after it", function()
			local unit, b = newUnit(env, { false, 0 }, legacy)
			electAndUpdate(unit)
			assert.equal(b[1], unit:ActiveBehaviour())

			local other = newUnit(env, { 5, false }, legacy)
			assert.has_error(function()
				other:ElectBehaviour()
			end)
		end)

		it("deactivates the loser at once and activates the winner on the next update", function()
			local unit, b, log = newUnit(env, { 30, 10 }, legacy)
			electAndUpdate(unit)
			b[2].score = 60

			unit:ElectBehaviour()

			assert.same({ "b1:PreActivate", "b1:Activate", "b1:PreDeactivate", "b1:Deactivate" }, log)
			unit:Update()
			assert.same({ "b2:PreActivate", "b2:Activate" }, { log[5], log[6] })
			assert.equal(b[2], unit:ActiveBehaviour())
		end)

		it("keeps the deactivated behaviour as the active one until the update, and lets the waiting one in", function()
			local unit, b, log = newUnit(env, { 30, 10 }, legacy)
			electAndUpdate(unit)
			b[1].score = 0

			unit:ElectBehaviour()
			assert.equal(b[1], unit:ActiveBehaviour())
			b[1].score = 50
			unit:ElectBehaviour()
			unit:Update()

			assert.same({
				"b1:PreActivate",
				"b1:Activate",
				"b1:PreDeactivate",
				"b1:Deactivate",
				"b2:PreActivate",
				"b2:Activate",
			}, log)
			assert.equal(b[2], unit:ActiveBehaviour())
		end)
	end)

	describe("updating the behaviours", function()
		-- A unit of the AI of team 4 with the behaviours of the given names; updates counts the Update of each.
		local function scheduledUnit(names, ai)
			local updates = {}
			local unit = env.Unit()
			unit.ai = ai
			unit:SetEngineRepresentation({
				ID = function()
					return 1
				end,
			})
			unit:Init()
			for _, name in ipairs(names) do
				local class = env.class(env.Behaviour)
				function class:Name()
					return name
				end
				function class:Update()
					updates[name] = updates[name] + 1
				end
				updates[name] = 0
				unit:AddBehaviour(class())
			end
			return unit, updates
		end

		local function scheduledAI(scheduler)
			return { id = 4, scheduledBehaviours = { Listed = true, Other = true }, scheduler = scheduler }
		end

		it("gives a listed behaviour Update only in the turn of its name for its AI, the others every time", function()
			local scheduler = {}
			local unit, updates = scheduledUnit({ "Listed", "Other", "Free" }, scheduledAI(scheduler))
			local turns = {
				{ 4, "Listed" },
				{ 5, "Listed" },
				{ 4, "Other" },
				{ 4, "Nobody" },
				{ nil, nil },
			}

			for _, turn in ipairs(turns) do
				scheduler.behaviourTeam = turn[1]
				scheduler.behaviourUpdate = turn[2]
				unit:Update()
			end

			assert.same({ Listed = 1, Other = 1, Free = 5 }, updates)
		end)

		it("gives every behaviour Update every time when the AI lists no behaviours or has no scheduler", function()
			local plain, plainUpdates = scheduledUnit({ "Listed", "Free" }, { id = 4 })
			local ai = scheduledAI(nil)
			local unscheduled, unscheduledUpdates = scheduledUnit({ "Listed", "Free" }, ai)

			for _ = 1, 3 do
				plain:Update()
				unscheduled:Update()
			end

			assert.same({ Listed = 3, Free = 3 }, plainUpdates)
			assert.same({ Listed = 3, Free = 3 }, unscheduledUpdates)
		end)

		it("activates a waiting behaviour at every update, in its turn or not", function()
			local scheduler = { behaviourTeam = 5, behaviourUpdate = "Listed" }
			local unit = scheduledUnit({ "Listed" }, scheduledAI(scheduler))
			local behaviour = unit.behaviours[1]
			behaviour.score = 10
			function behaviour:Priority()
				return self.score
			end

			unit:ElectBehaviour()
			unit:Update()

			assert.equal(behaviour, unit:ActiveBehaviour())
		end)

		it("allocates nothing to update the behaviours", function()
			local scheduler = { behaviourTeam = 4, behaviourUpdate = "Listed" }
			local unit = scheduledUnit({ "Listed", "Other", "Free" }, scheduledAI(scheduler))
			unit:Update()

			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for n = 1, 1000 do
				scheduler.behaviourTeam = 3 + n % 3
				scheduler.behaviourUpdate = n % 2 == 0 and "Listed" or "Other"
				unit:Update()
			end
			local after = collectgarbage("count")
			collectgarbage("restart")

			assert.equal(before, after)
		end)
	end)
end)
