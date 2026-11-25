---@diagnostic disable: undefined-field, call-non-callable, inject-field

local ALLY = 0
local OTHER_ALLY = 1
local BUILDING = 1
local MOBILE = 2

-- Loads the runtime's class, AIBase and Module, then STAI/loshst.lua, in an environment of their own. The
-- perception handler is a fake whose radar holds the unitIDs of onRadar; the game knows the units of units.
local function newLosHST(onRadar, units)
	local env = setmetatable({
		UnitDefs = {
			[BUILDING] = { name = "building", speed = 0 },
			[MOBILE] = { name = "mobile", speed = 60 },
		},
		game = {
			GetUnitByID = function(_, unitID)
				return units[unitID]
			end,
			Frame = function()
				return 0
			end,
		},
		Spring = {
			GetUnitVelocity = function(unitID)
				return 0, 0, 0, units[unitID] and units[unitID].SPEED or 0
			end,
		},
	}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/loshst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local losHST = env.LosHST()
	losHST.ai = {
		allyId = ALLY,
		armyhst = {
			unitTable = {
				building = { name = "building", metalCost = 100, speed = 0 },
				mobile = { name = "mobile", metalCost = 50, speed = 60 },
				factory = { name = "factory", metalCost = 500, speed = 0, isFactory = true },
			},
		},
		gridhst = {
			IsCellInGrid = function()
				return true
			end,
			NewLayer = function()
				return { Clear = function() end }
			end,
			RawPosToGrid = function(_, x, _, z)
				return math.floor(x / 256) + 1, math.floor(z / 256) + 1
			end,
		},
		perceptionhandler = {
			OnRadar = function(_, unitID)
				return onRadar[unitID] == true
			end,
		},
	}
	losHST:Init()
	return losHST
end

-- An enemy unit at x, z that is alive
local function newUnit(unitID, x, z)
	return {
		ID = function()
			return unitID
		end,
		GetRawPos = function()
			return x, 0, z
		end,
		IsAlive = function()
			return true
		end,
	}
end

-- An unarmed enemy unit of the type name, moving at SPEED
local function newTypedUnit(unitID, name, SPEED)
	return {
		id = unitID,
		name = name,
		SPEED = SPEED,
		ID = function()
			return unitID
		end,
		Name = function()
			return name
		end,
		GetRawPos = function()
			return 0, 0, 0
		end,
	}
end

-- Every unit of units goes in one ENEMY cell, on the move layer layer, through setCell (setCellLos or setCellRadar)
local function fillCell(units, layer, setCell)
	local losHST = newLosHST({}, units)
	local CELL = {}
	losHST.resetCell(CELL)
	losHST.getEnemyCell = function()
		return CELL
	end
	losHST.setPosLayer2 = function()
		return layer
	end
	for unitID = 1, #units do
		losHST[setCell](losHST, units[unitID], 1, 1)
	end
	return CELL
end

local function where(losHST, unitID)
	return {
		los = losHST.losEnemy[unitID],
		radar = losHST.radarEnemy[unitID],
		ghost = losHST.ghostEnemy[unitID],
	}
end

describe("STAI LosHST", function()
	it("keeps a mobile unit that leaves the los while on radar as a ghost of its type", function()
		local losHST = newLosHST({ [10] = true }, {})
		losHST:UnitEnteredLos(10, 5, ALLY, MOBILE)

		losHST:UnitLeftLos(10, 5, ALLY, MOBILE)

		assert.same({ ghost = MOBILE }, where(losHST, 10))
	end)

	it("forgets a mobile unit that leaves the los off radar", function()
		local losHST = newLosHST({}, {})
		losHST:UnitEnteredLos(10, 5, ALLY, MOBILE)

		losHST:UnitLeftLos(10, 5, ALLY, MOBILE)

		assert.same({}, where(losHST, 10))
	end)

	it("moves a ghost back to the los when it enters the los again", function()
		local losHST = newLosHST({ [10] = true }, {})
		losHST:UnitEnteredLos(10, 5, ALLY, MOBILE)
		losHST:UnitLeftLos(10, 5, ALLY, MOBILE)

		losHST:UnitEnteredLos(10, 5, ALLY, MOBILE)

		assert.same({ los = MOBILE }, where(losHST, 10))
	end)

	it("forgets a ghost when it leaves the radar, or dies", function()
		local onRadar = { [10] = true, [11] = true }
		local losHST = newLosHST(onRadar, {})
		for unitID = 10, 11 do
			losHST:UnitEnteredLos(unitID, 5, ALLY, MOBILE)
			losHST:UnitLeftLos(unitID, 5, ALLY, MOBILE)
		end

		onRadar[10] = nil
		losHST:UnitLeftRadar(10, 5, ALLY, MOBILE)
		losHST:cleanEnemy(11)

		assert.same({}, where(losHST, 10))
		assert.same({}, where(losHST, 11))
	end)

	it("keeps a building that leaves the los in the los, on radar or not", function()
		local losHST = newLosHST({ [20] = true }, {})
		for unitID = 20, 21 do
			losHST:UnitEnteredLos(unitID, 5, ALLY, BUILDING)
			losHST:UnitLeftLos(unitID, 5, ALLY, BUILDING)
		end

		assert.same({ los = BUILDING }, where(losHST, 20))
		assert.same({ los = BUILDING }, where(losHST, 21))
	end)

	it("marks a ghost in the cell of its radar position as a unit of known type", function()
		local units = { [10] = newUnit(10, 600, 300), [30] = newUnit(30, 100, 100) }
		local losHST = newLosHST({ [10] = true }, units)
		local marked = {}
		losHST.setCellLos = function(_, unit, X, Z)
			marked[#marked + 1] = { "los", unit:ID(), X, Z }
		end
		losHST.setCellRadar = function(_, unit, X, Z)
			marked[#marked + 1] = { "radar", unit:ID(), X, Z }
		end
		losHST:UnitEnteredLos(10, 5, ALLY, MOBILE)
		losHST:UnitLeftLos(10, 5, ALLY, MOBILE)
		losHST:UnitEnteredLos(30, 5, OTHER_ALLY, MOBILE)

		losHST:Update()

		assert.same({ { "los", 10, 3, 2 } }, marked)
	end)

	for layer, letter in pairs({ [0] = "G", [1] = "A", [-1] = "S" }) do
		it("adds up the unarmed buildings of a cell in los, layer " .. letter, function()
			local buildings = { newTypedUnit(1, "building", 0), newTypedUnit(2, "building", 0) }
			local CELL = fillCell(buildings, layer, "setCellLos")
			assert.equal(200, CELL["unarm" .. letter .. "I"])
			assert.equal(0, CELL["unarm" .. letter .. "M"])

			local mobileFirst = { newTypedUnit(3, "mobile", 1), buildings[1], buildings[2] }
			CELL = fillCell(mobileFirst, layer, "setCellLos")
			assert.equal(200, CELL["unarm" .. letter .. "I"])
			assert.equal(50, CELL["unarm" .. letter .. "M"])
		end)
	end

	it("adds up the immobile units of a cell on radar, on every layer", function()
		local immobile = { newTypedUnit(1, "building", 0), newTypedUnit(2, "building", 0) }
		local CELL = fillCell(immobile, 0, "setCellRadar")
		for _, letter in ipairs({ "G", "A", "S" }) do
			assert.equal(60, CELL["unarm" .. letter .. "I"]) --30 metal each, the guess for a unit on radar at frame 0
			assert.equal(0, CELL["unarm" .. letter .. "M"])
		end

		local mobileFirst = { newTypedUnit(3, "mobile", 1), immobile[1], immobile[2] }
		CELL = fillCell(mobileFirst, 0, "setCellRadar")
		for _, letter in ipairs({ "G", "A", "S" }) do
			assert.equal(60, CELL["unarm" .. letter .. "I"])
			assert.equal(30, CELL["unarm" .. letter .. "M"])
		end
	end)

	it("forgets the factory of a cell when the cell is cleared and used again", function()
		local CELL = fillCell({ newTypedUnit(1, "factory", 0) }, 0, "setCellLos")
		assert.equal("factory", CELL.base)

		local losHST = newLosHST({}, {})
		losHST.getEnemyCell = function()
			return CELL
		end
		losHST.setPosLayer2 = function()
			return 0
		end
		losHST.resetCell(CELL) --what ENEMY:Clear does to every cell of its list
		losHST:setCellLos(newTypedUnit(2, "building", 0), 1, 1)

		assert.equal(100, CELL.BUILDINGS)
		assert.is_nil(CELL.base)
	end)

	it("keeps the center where it is without own buildings, and puts it in their mean position with them", function()
		local units = { [40] = newUnit(40, 100, 300), [41] = newUnit(41, 300, 500) }
		local losHST = newLosHST({}, units)
		local commanderPosition = { x = 1000, y = 20, z = 2000 }
		losHST.CENTER = commanderPosition

		losHST:getCenter()

		assert.equal(commanderPosition, losHST.CENTER)
		assert.same({ x = 1000, y = 20, z = 2000 }, losHST.CENTER)

		losHST.ownImmobile[40] = BUILDING
		losHST.ownImmobile[41] = BUILDING
		losHST:getCenter()

		assert.same({ x = 200, y = 0, z = 400 }, losHST.CENTER)
	end)
end)
