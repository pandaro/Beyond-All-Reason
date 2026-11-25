---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase and Module, then STAI/maphst.lua, in an environment of their own; the map
-- records the channels EraseAll gets. Returns the environment too.
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
	return mapHST, erased, env
end

-- Two cells, index 1 and 2, the index of a spot is its x; a spot with x below 1 is out of the map. Both cells are
-- in the ground network 1, only the first in the air network 1.
local function setTwoCells(mapHST)
	mapHST.ai.gridhst = {
		PosToIndex = function(_, spot)
			if spot.x >= 1 then
				return spot.x
			end
		end,
	}
	mapHST.GRID = { CELLS = {} }
	for i = 1, 2 do
		mapHST.GRID.CELLS[i] = { metalSpots = {}, geoSpots = {}, moveLayers = { ground = 1, air = i == 1 and 1 } }
	end
	mapHST.networks = {
		ground = { { metals = {}, geos = {} } },
		air = { { metals = {}, geos = {} } },
	}
end

describe("STAI MapHST", function()
	it("erases no debug channel when the debug drawing is off", function()
		local mapHST, erased = newMapHST(false)

		mapHST:DrawDebug()

		assert.same({}, erased)
	end)

	it("skips only the metal spot out of the map, and puts the ones after it in their cells and networks", function()
		local mapHST = newMapHST(false)
		setTwoCells(mapHST)
		local first, out, last = { x = 1 }, { x = -5 }, { x = 2 }
		mapHST.METALS = { first, out, last }

		mapHST:metalScan()

		assert.same({ first }, mapHST.GRID.CELLS[1].metalSpots)
		assert.same({ last }, mapHST.GRID.CELLS[2].metalSpots)
		assert.same({ first, last }, mapHST.networks.ground[1].metals)
		assert.same({ first }, mapHST.networks.air[1].metals)
	end)

	it("skips only the geo spot out of the map, and puts the ones after it in their cells and networks", function()
		local mapHST = newMapHST(false)
		setTwoCells(mapHST)
		local first, out, last = { x = 1 }, { x = -5 }, { x = 2 }
		mapHST.GEOS = { first, out, last }

		mapHST:geoScan()

		assert.same({ first }, mapHST.GRID.CELLS[1].geoSpots)
		assert.same({ last }, mapHST.GRID.CELLS[2].geoSpots)
		assert.same({ first, last }, mapHST.networks.ground[1].geos)
		assert.same({ first }, mapHST.networks.air[1].geos)
	end)

	it("simplifies the metal spots over the whole of a map that is not square", function()
		local mapHST = newMapHST(false)
		mapHST.elmoMapSizeX = 1024
		mapHST.elmoMapSizeZ = 2048
		mapHST.METALS = {}
		for n = 1, 1000 do
			mapHST.METALS[n] = { x = 0, z = 0 } --on the edge of a square: never taken
		end
		local inSquares = 0
		for x = 0, 1024 - 256, 256 do
			for z = 0, 2048 - 256, 256 do
				mapHST.METALS[#mapHST.METALS + 1] = { x = x + 128, z = z + 128 }
				inSquares = inSquares + 1
			end
		end

		local spots = mapHST:SimplifyMetalSpots(256)

		assert.equal(32, inSquares)
		assert.equal(inSquares, #spots)
		local beyondX = 0
		for _, spot in ipairs(spots) do
			if spot.z > 1024 then
				beyondX = beyondX + 1
			end
		end
		assert.equal(16, beyondX)
	end)

	it("gives the lowest and the highest ground height of the cells near a point", function()
		local mapHST, _, env = newMapHST(false)
		env.map = {
			GetGroundHeight = function(_, x, z)
				if x > 512 then
					return -100
				elseif x > 256 then
					return -40
				elseif x == 112 and z == 176 then
					return 90 --a hill under one sample of the first cell
				end
				return 10
			end,
		}
		mapHST.ai.gridhst = {
			gridSize = 256,
			gridSideX = 3,
			gridSideZ = 1,
			GridToIndex = function(_, X, Z)
				return (X - 1) * 1 + Z
			end,
		}
		mapHST.GRID = { CELLS = {} }
		for X = 1, 3 do
			local CELL = {}
			CELL.lowestHeight, CELL.highestHeight = mapHST:cellHeights({ X = X, Z = 1 })
			mapHST.GRID.CELLS[X] = CELL
		end

		assert.same({ 10, 90 }, { mapHST.GRID.CELLS[1].lowestHeight, mapHST.GRID.CELLS[1].highestHeight })
		assert.same({ 10, 90 }, { mapHST:HeightsNear(100, 128, 50) })
		assert.same({ -40, 90 }, { mapHST:HeightsNear(200, 128, 100) })
		assert.same({ -100, -40 }, { mapHST:HeightsNear(600, 128, 100) })
		assert.same({ -100, 90 }, { mapHST:HeightsNear(700, 128, 5000) })
		assert.same({}, { mapHST:HeightsNear(-5000, 128, 10) })
	end)
end)
