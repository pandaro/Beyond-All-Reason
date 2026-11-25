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
		gridhst = {
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
end)
