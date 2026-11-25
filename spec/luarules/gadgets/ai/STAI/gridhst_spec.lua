---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase and Module, then STAI/gridhst.lua, in an environment of their own whose map is
-- elmoX by elmoZ elmos; ground height is x + z / 1000 so a cell position shows which point it was read at.
local function newGridHST(elmoX, elmoZ)
	local env = setmetatable({
		map = {
			MapDimensions = function()
				return { x = elmoX / 8, y = 0, z = elmoZ / 8 }
			end,
			GetGroundHeight = function(_, x, z)
				return x + z / 1000
			end,
		},
	}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/gridhst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local grid = env.GridHST()
	grid.ai = {
		Name = function()
			return "STAI"
		end,
	}
	grid.game = { SendToConsole = function() end }
	grid:Init()
	return grid
end

describe("STAI GridHST", function()
	-- 6 cells along X, 4 along Z
	local grid = newGridHST(1536, 1024)

	it("measures a grid that is not square", function()
		assert.equal(256, grid.gridSize)
		assert.equal(6, grid.gridSideX)
		assert.equal(4, grid.gridSideZ)
		assert.equal(24, grid.gridArea)
		assert.equal(24, #grid.CELLS)
	end)

	it("gives every cell one index, and the index gives back its X and Z", function()
		local seen = {}
		for X = 1, grid.gridSideX do
			for Z = 1, grid.gridSideZ do
				local i = grid:GridToIndex(X, Z)
				assert.is_nil(seen[i])
				seen[i] = true
				assert.equal(i, grid.CELLS[i].INDEX)
				assert.equal(X, grid.CELLS[i].X)
				assert.equal(Z, grid.CELLS[i].Z)
			end
		end
		for i = 1, #grid.CELLS do
			assert.is_true(seen[i])
		end
	end)

	it("puts the next Z at i + 1 and the next X at i + gridSideZ", function()
		local i = grid:GridToIndex(2, 3)
		assert.equal(2, grid.CELLS[i + 1].X)
		assert.equal(4, grid.CELLS[i + 1].Z)
		assert.equal(3, grid.CELLS[i + grid.gridSideZ].X)
		assert.equal(3, grid.CELLS[i + grid.gridSideZ].Z)
	end)

	it("starts at the cell 1, 1 and ends at the last cell, with the ground under their centres", function()
		local first, last = grid.CELLS[1], grid.CELLS[24]
		assert.same({ 1, 1, 1 }, { first.INDEX, first.X, first.Z })
		assert.same({ x = 128, y = 128 + 128 / 1000, z = 128 }, first.POS)
		assert.same({ 24, 6, 4 }, { last.INDEX, last.X, last.Z })
		assert.same({ x = 1408, y = 1408 + 896 / 1000, z = 896 }, last.POS)
	end)

	it("keeps a position on the edge of a cell in that cell, and the next elmo in the next one", function()
		assert.equal(1, grid:PosToIndex({ x = 256, y = 0, z = 256 }))
		assert.equal(grid:GridToIndex(2, 1), grid:PosToIndex({ x = 257, y = 0, z = 256 }))
		assert.equal(grid:GridToIndex(1, 2), grid:RawPosToIndex(256, 257))
		assert.equal(24, grid:RawPosToIndex(1536, 1024))
	end)

	it("finds no cell out of the edges", function()
		assert.is_true(grid:IsCellInGrid(1, 1))
		assert.is_true(grid:IsCellInGrid(6, 4))
		assert.is_nil(grid:IsCellInGrid(0, 1))
		assert.is_nil(grid:IsCellInGrid(1, 0))
		assert.is_nil(grid:IsCellInGrid(7, 1))
		assert.is_nil(grid:IsCellInGrid(6, 5))
		assert.is_nil(grid:PosToIndex({ x = 0, y = 0, z = 100 }))
		assert.is_nil(grid:PosToIndex({ x = 100, y = 0, z = 1025 }))
		assert.is_nil(grid:RawPosToIndex(1537, 100))
	end)

	it("gives the cell of CELLS holding a position, and no cell out of the edges", function()
		assert.equal(grid.CELLS[grid:GridToIndex(2, 1)], grid:PosToCell({ x = 257, y = 0, z = 256 }))
		assert.equal(grid.CELLS[grid:GridToIndex(1, 2)], grid:RawPosToCell(256, 257))
		assert.is_nil(grid:PosToCell({ x = 0, y = 0, z = 100 }))
		assert.is_nil(grid:PosToCell({ x = 100, y = 0, z = 1025 }))
		assert.is_nil(grid:RawPosToCell(1537, 100))
		assert.is_nil(grid:RawPosToCell(100, 0))
		assert.is_nil(grid:RawPosToCell(100, 1025))
	end)

	describe("layer", function()
		local resets = {}
		local function resetCell(CELL)
			resets[#resets + 1] = CELL
			CELL.metal = 0
		end

		before_each(function()
			resets = {}
		end)

		it("makes the data of a cell once, resets it when made, and does not mark it", function()
			local layer = grid:NewLayer(resetCell)
			assert.is_nil(layer.CELLS[5])
			local CELL = layer:Get(5)
			assert.equal(0, CELL.metal)
			assert.equal(1, #resets)
			assert.equal(CELL, resets[1])
			CELL.metal = 7
			assert.equal(CELL, layer:Get(5))
			assert.equal(7, CELL.metal)
			assert.equal(1, #resets)
			assert.equal(CELL, layer.CELLS[5])
			assert.equal(0, #layer.LIST)
		end)

		it("makes empty cells without a reset function", function()
			local layer = grid:NewLayer()
			assert.same({}, layer:Get(3))
			layer:Mark(3)
			layer:Clear()
			assert.same({}, layer.CELLS[3])
		end)

		it("puts a cell marked twice in the list once, in order of arrival", function()
			local layer = grid:NewLayer(resetCell)
			layer:Mark(9)
			layer:Mark(2)
			layer:Mark(9)
			assert.same({ 9, 2 }, layer.LIST)
		end)

		it("resets only the cells in the list and keeps the same tables", function()
			local layer = grid:NewLayer(resetCell)
			local LIST = layer.LIST
			local marked, unmarked = layer:Get(4), layer:Get(6)
			marked.metal, unmarked.metal = 3, 5
			layer:Mark(4)
			resets = {}
			layer:Clear()
			assert.equal(1, #resets)
			assert.is_true(rawequal(marked, resets[1]))
			assert.equal(0, marked.metal)
			assert.equal(5, unmarked.metal)
			assert.is_true(rawequal(LIST, layer.LIST))
			assert.equal(0, #layer.LIST)
			assert.is_nil(layer.LIST[1])
			resets = {}
			assert.is_true(rawequal(marked, layer:Get(4)))
			assert.is_true(rawequal(unmarked, layer.CELLS[6]))
			assert.equal(0, #resets)
		end)

		it("marks a cell again after the clear", function()
			local layer = grid:NewLayer(resetCell)
			layer:Get(4)
			layer:Mark(4)
			layer:Clear()
			layer:Mark(4)
			assert.same({ 4 }, layer.LIST)
			layer:Clear()
			assert.equal(0, #layer.LIST)
		end)

		it("keeps the layers apart", function()
			local first, second = grid:NewLayer(), grid:NewLayer()
			first:Get(1)
			first:Mark(1)
			assert.is_nil(second.CELLS[1])
			assert.equal(0, #second.LIST)
		end)
	end)
end)
