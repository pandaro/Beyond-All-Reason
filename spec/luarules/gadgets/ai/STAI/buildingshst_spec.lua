---@diagnostic disable: undefined-field, call-non-callable, inject-field

local TEAM = 0
local BUILDING = 1

-- Loads the runtime's class, AIBase, Module and Behaviour, then STAI/buildingshst.lua and STAI/commanderbst.lua, in an
-- environment of their own; the game knows the units of units.
local function loadEnv(units)
	local env = setmetatable({
		game = {
			GetUnitByID = function(_, unitID)
				return units[unitID]
			end,
		},
		VFS = {
			Include = function()
				return {}
			end,
		},
	}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/shard_runtime/behaviour.lua",
		"luarules/gadgets/ai/STAI/buildingshst.lua",
		"luarules/gadgets/ai/STAI/commanderbst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	return env
end

-- A unit at unit.x, unit.y, unit.z; without x it is dead
local function newUnit(unitID, x, y, z)
	local unit = { x = x, y = y, z = z }
	unit.ID = function()
		return unitID
	end
	unit.GetRawPos = function()
		return unit.x, unit.y, unit.z
	end
	unit.GetPosition = function()
		if not unit.x then
			return
		end
		unit.position = unit.position or {}
		unit.position.x, unit.position.y, unit.position.z = unit.x, unit.y, unit.z
		return unit.position
	end
	return unit
end

-- BuildingsHST and an initialized CommanderBST of commanderUnit
local function newBuildingsHST(units, commanderUnit)
	local env = loadEnv(units)
	local ai = { id = TEAM, maphst = { allSpots = {} } }
	local buildingsHST = env.BuildingsHST()
	buildingsHST.ai = ai
	buildingsHST:Init()
	buildingsHST.UnitMexMoveTest = function() end
	ai.buildingshst = buildingsHST
	local commander = env.CommanderBST()
	commander.ai = ai
	commander.unit = {
		Internal = function()
			return commanderUnit
		end,
	}
	commander:Init()
	return buildingsHST
end

describe("STAI BuildingsHST", function()
	it("gives as center the current commander position without buildings, in a table of its own", function()
		local commanderUnit = newUnit(30, 1000, 20, 2000)
		local buildingsHST = newBuildingsHST({ [30] = commanderUnit }, commanderUnit)

		local center = buildingsHST:GetCenter()

		assert.same({ x = 1000, y = 20, z = 2000 }, center)
		assert.are_not.equal(commanderUnit:GetPosition(), center)

		commanderUnit.x, commanderUnit.z = 1500, 2500

		assert.same({ x = 1500, y = 20, z = 2500 }, buildingsHST:GetCenter())
		assert.same({ x = 1500, y = 20, z = 2500 }, buildingsHST.CENTER)
		assert.are_not.equal(commanderUnit:GetPosition(), buildingsHST:GetCenter())
	end)

	it("gives as center the mean of the buildings, even when the commander moves", function()
		local commanderUnit = newUnit(30, 1000, 20, 2000)
		local units = { [30] = commanderUnit, [40] = newUnit(40, 100, 0, 300), [41] = newUnit(41, 300, 0, 500) }
		local buildingsHST = newBuildingsHST(units, commanderUnit)
		buildingsHST:GetCenter()
		buildingsHST.ownImmobile[40] = BUILDING
		buildingsHST.ownImmobile[41] = BUILDING
		buildingsHST:getCenter()

		assert.same({ x = 200, y = 0, z = 400 }, buildingsHST:GetCenter())

		commanderUnit.x, commanderUnit.z = 1500, 2500

		assert.same({ x = 200, y = 0, z = 400 }, buildingsHST:GetCenter())
	end)

	it("goes back to the commander when all the buildings are lost", function()
		local commanderUnit = newUnit(30, 1000, 20, 2000)
		local units = { [30] = commanderUnit, [40] = newUnit(40, 100, 0, 300) }
		local buildingsHST = newBuildingsHST(units, commanderUnit)
		buildingsHST.ownImmobile[40] = BUILDING
		buildingsHST:getCenter()

		assert.same({ x = 100, y = 0, z = 300 }, buildingsHST:GetCenter())

		buildingsHST.ownImmobile[40] = nil
		buildingsHST:getCenter()

		assert.same({ x = 1000, y = 20, z = 2000 }, buildingsHST:GetCenter())
	end)

	it("keeps the last center with no buildings and the commander dead", function()
		local commanderUnit = newUnit(30, 1000, 20, 2000)
		local buildingsHST = newBuildingsHST({ [30] = commanderUnit }, commanderUnit)
		buildingsHST:GetCenter()
		commanderUnit.x, commanderUnit.y, commanderUnit.z = nil, nil, nil

		assert.same({ x = 1000, y = 20, z = 2000 }, buildingsHST:GetCenter())
	end)
end)
