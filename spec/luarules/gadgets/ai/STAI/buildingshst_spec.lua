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

local LAND = 10 --ground height of the dry ground
local WATER = -40 --ground height under the water
local DEEP_WATER_DEPTH = 20 --the least water depth of the tidal generator

-- BuildingsHST on a 4096 x 4096 map whose ground height is world.height(x, z). The engine records the points whose
-- height is asked (the points tried), the build orders tested, the cylinders and the paths asked; MapHST answers
-- world.lowest and world.highest as the heights near any point.
local function newPlacingWorld()
	local world = { points = {}, tests = 0, cylinders = 0, paths = 0, units = {}, teamUnits = {}, separations = {} }
	world.height = function()
		return LAND
	end
	world.buildable = function()
		return false
	end
	world.lowest, world.highest = WATER, LAND
	local env = setmetatable({
		Game = { mapSizeX = 4096, mapSizeZ = 4096 },
		map = {
			GetGroundHeight = function(_, x, z)
				world.points[#world.points + 1] = { x = x, z = z }
				return world.height(x, z)
			end,
		},
		Spring = {
			Pos2BuildPos = function(_, x, y, z)
				return x, y, z
			end,
			TestBuildOrder = function(_, x, y, z)
				world.tests = world.tests + 1
				return world.buildable(x, z) and 1 or 0
			end,
		},
		game = {
			getUnitsInCylinder = function()
				world.cylinders = world.cylinders + 1
				return {}
			end,
			GetUnitByID = function(_, unitID)
				return world.units[unitID]
			end,
			GetTeamUnitsByDefs = function(_, _, defId)
				return world.teamUnits[defId] or {}
			end,
			GetUnitSeparation = function(_, unitID)
				return world.separations[unitID]
			end,
		},
		VFS = {
			Include = function(path)
				return dofile(path)
			end,
		},
	}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/toolbox.lua",
		"luarules/gadgets/ai/STAI/buildingshst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local unitTable = {
		armwin = { defId = 1, xsize = 6, zsize = 6, minWaterDepth = -10e6, maxWaterDepth = 0, speed = 0 },
		armtide = { defId = 2, xsize = 6, zsize = 6, minWaterDepth = DEEP_WATER_DEPTH, maxWaterDepth = 10e6, speed = 0 },
		armck = { defId = 3, speed = 50, mtype = "bot" },
		armsolar = { defId = 11, xsize = 10, zsize = 10, minWaterDepth = -10e6, maxWaterDepth = 0, speed = 0 },
		armmakr = { defId = 12, xsize = 6, zsize = 6, minWaterDepth = -10e6, maxWaterDepth = 0, speed = 0 },
	}
	unitTable.armwin.needsWater = false
	unitTable.armtide.needsWater = true
	local ai = {
		id = TEAM,
		tool = env.Toolbox,
		armyhst = {
			unitTable = unitTable,
			commanderList = {},
			factoryMobilities = {},
			factoryExitSides = {},
			_mex_ = {},
			_eco_ = { armsolar = true, armmakr = true },
		},
		gridhst = {
			isInMap = function(_, pos)
				if pos.x > 0 and pos.x <= 4096 and pos.z > 0 and pos.z <= 4096 then
					return pos
				end
			end,
		},
		maphst = {
			allSpots = {},
			HeightsNear = function()
				return world.lowest, world.highest
			end,
			UnitCanGoHere = function()
				world.paths = world.paths + 1
				return 32
			end,
		},
	}
	local buildingsHST = env.BuildingsHST()
	buildingsHST.ai = ai
	buildingsHST.game = env.game
	buildingsHST:Init()
	world.builder = {
		Name = function()
			return "armck"
		end,
		ID = function()
			return 3000
		end,
	}
	return buildingsHST, world
end

local function newUnitType(name, defId)
	return {
		Name = function()
			return name
		end,
		ID = function()
			return defId
		end,
	}
end

-- A unit of the team named name at x, 0, z
local function newSupportUnit(name, x, z)
	return {
		Name = function()
			return name
		end,
		GetRawPos = function()
			return x, 0, z
		end,
	}
end

describe("STAI BuildingsHST placement", function()
	before_each(function()
		math.randomseed(1)
	end)

	it("rejects a water building on land, and a land building in water, before asking the engine", function()
		local buildingsHST, world = newPlacingWorld()

		local onLand =
			buildingsHST:CheckBuildPos({ x = 1000, y = LAND, z = 1000 }, newUnitType("armtide", 2), world.builder)
		local inWater =
			buildingsHST:CheckBuildPos({ x = 1000, y = WATER, z = 1000 }, newUnitType("armwin", 1), world.builder)

		assert.is_nil(onLand)
		assert.is_nil(inWater)
		assert.equal(0, world.cylinders)
		assert.equal(0, world.tests)
		assert.equal(0, world.paths)
	end)

	it("tests the build order only on the points in water, for a water building near the shore", function()
		local buildingsHST, world = newPlacingWorld()
		world.height = function(x)
			return x > 1150 and WATER or LAND
		end
		world.buildable = function(x, z)
			return world.height(x, z) <= -DEEP_WATER_DEPTH
		end

		local position =
			buildingsHST:FindClosestBuildSite(newUnitType("armtide", 2), 1000, LAND, 1000, 50, 390, world.builder)

		assert.is_not_nil(position)
		assert.is_true(position.x > 1150)
		assert.equal(1, world.tests)
	end)

	it("tries no point for a water building with no water near", function()
		local buildingsHST, world = newPlacingWorld()
		world.lowest, world.highest = 5, 80

		local position =
			buildingsHST:FindClosestBuildSite(newUnitType("armtide", 2), 1000, LAND, 1000, 50, 390, world.builder)

		assert.is_nil(position)
		assert.equal(0, #world.points)
	end)

end)
