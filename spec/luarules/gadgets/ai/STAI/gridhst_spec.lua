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
	local grid = newGridHST(768, 512)

	it("measures a grid that is not square", function()
		assert.equal(128, grid.gridSize)
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
		assert.same({ x = 64, y = 64 + 64 / 1000, z = 64 }, first.POS)
		assert.same({ 24, 6, 4 }, { last.INDEX, last.X, last.Z })
		assert.same({ x = 704, y = 704 + 448 / 1000, z = 448 }, last.POS)
	end)

	it("keeps a position on the edge of a cell in that cell, and the next elmo in the next one", function()
		assert.equal(1, grid:PosToIndex({ x = 128, y = 0, z = 128 }))
		assert.equal(grid:GridToIndex(2, 1), grid:PosToIndex({ x = 129, y = 0, z = 128 }))
		assert.equal(grid:GridToIndex(1, 2), grid:RawPosToIndex(128, 129))
		assert.equal(24, grid:RawPosToIndex(768, 512))
	end)

	it("finds no cell out of the edges", function()
		assert.is_true(grid:IsCellInGrid(1, 1))
		assert.is_true(grid:IsCellInGrid(6, 4))
		assert.is_nil(grid:IsCellInGrid(0, 1))
		assert.is_nil(grid:IsCellInGrid(1, 0))
		assert.is_nil(grid:IsCellInGrid(7, 1))
		assert.is_nil(grid:IsCellInGrid(6, 5))
		assert.is_nil(grid:PosToIndex({ x = 0, y = 0, z = 100 }))
		assert.is_nil(grid:PosToIndex({ x = 100, y = 0, z = 513 }))
		assert.is_nil(grid:RawPosToIndex(769, 100))
	end)

	it("gives the cell of CELLS holding a position, and no cell out of the edges", function()
		assert.equal(grid.CELLS[grid:GridToIndex(2, 1)], grid:PosToCell({ x = 129, y = 0, z = 128 }))
		assert.equal(grid.CELLS[grid:GridToIndex(1, 2)], grid:RawPosToCell(128, 129))
		assert.is_nil(grid:PosToCell({ x = 0, y = 0, z = 100 }))
		assert.is_nil(grid:PosToCell({ x = 100, y = 0, z = 513 }))
		assert.is_nil(grid:RawPosToCell(769, 100))
		assert.is_nil(grid:RawPosToCell(100, 0))
		assert.is_nil(grid:RawPosToCell(100, 513))
	end)

	it("tells a raw position out of the map in the debug, and gives it back when in the map", function()
		local debugGrid = newGridHST(1536, 1024)
		local lines = {}
		debugGrid.game.GetTeamID = function()
			return 0
		end
		debugGrid.game.SendToConsole = function(_, ...)
			lines[#lines + 1] = table.concat({ ... }, " ", 4) --after the team, AI and module names
		end
		debugGrid.DebugEnabled = true

		assert.is_nil(debugGrid:RawPosIsInMap(1537, 7, 100))
		assert.same({ "bad position: 1537, 100" }, lines)
		assert.same({ 100, 7, 200 }, { debugGrid:RawPosIsInMap(100, 7, 200) })
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

		it("gives the data of a cell only while the cell is in the list", function()
			local layer = grid:NewLayer(resetCell)
			local CELL = layer:Get(7)
			assert.is_nil(layer:GetMarked(7))
			layer:Mark(7)
			assert.is_true(rawequal(CELL, layer:GetMarked(7)))
			assert.is_nil(layer:GetMarked(8))
			layer:Clear()
			assert.is_nil(layer:GetMarked(7))
			assert.is_true(rawequal(CELL, layer.CELLS[7]))
		end)

		it("reads only the true cells of a layer, and nothing past the edges", function()
			local layer = grid:NewLayer(resetCell)
			local function markCell(X, Z, metal)
				local i = grid:GridToIndex(X, Z)
				layer:Get(i).metal = metal
				layer:Mark(i)
				return layer.CELLS[i]
			end
			-- past the edge Z = 4, the index of 1, 5 is the one of 2, 1 and the index of 2, 5 the one of 3, 1
			local wrapped, wrappedNext = markCell(2, 1, 100), markCell(3, 1, 200)
			local corner, inside = markCell(1, 4, 1), markCell(2, 3, 2)
			layer:Get(grid:GridToIndex(2, 4)).metal = 50
			assert.same({ corner, inside }, grid:areaCells(1, 4, 1, layer))
			assert.is_true(rawequal(corner, grid:GetCell(1, 4, layer)))
			assert.is_true(rawequal(wrapped, grid:GetCell({ x = 150, y = 0, z = 50 }, layer)))
			assert.is_true(rawequal(wrappedNext, grid:GetCell(3, 1, layer)))
			assert.is_nil(grid:GetCell(1, 5, layer))
			assert.is_nil(grid:GetCell(2, 4, layer))
			assert.is_nil(grid:GetCell(0, 2, layer))
			local value, subValues, cells = grid:getCellsFields({ x = 50, y = 0, z = 500 }, { "metal" }, 1, layer)
			assert.equal(3, value)
			assert.same({ metal = 3 }, subValues)
			assert.same({ corner, inside }, cells)
		end)

		it("takes one cell out of the list keeping the order of the others, and resets it", function()
			local layer = grid:NewLayer(resetCell)
			local LIST = layer.LIST
			for _, i in ipairs({ 5, 9, 2, 7 }) do
				layer:Get(i).metal = i
				layer:Mark(i)
			end
			resets = {}
			layer:Unmark(9)
			assert.same({ 5, 2, 7 }, layer.LIST)
			assert.is_true(rawequal(LIST, layer.LIST))
			assert.is_nil(layer:GetMarked(9))
			assert.equal(1, #resets)
			assert.is_true(rawequal(layer.CELLS[9], resets[1]))
			assert.equal(0, layer.CELLS[9].metal)
			assert.equal(2, layer:GetMarked(2).metal)
		end)

		it("does nothing on a cell that is not in the list", function()
			local layer = grid:NewLayer(resetCell)
			layer:Get(3).metal = 4
			layer:Mark(6)
			resets = {}
			layer:Unmark(3)
			layer:Unmark(8)
			assert.same({ 6 }, layer.LIST)
			assert.equal(0, #resets)
			assert.equal(4, layer.CELLS[3].metal)
		end)

		it("marks a cell again after it was taken out, at the end of the list", function()
			local layer = grid:NewLayer(resetCell)
			local CELL = layer:Get(4)
			layer:Mark(4)
			layer:Mark(1)
			layer:Unmark(4)
			layer:Mark(4)
			assert.same({ 1, 4 }, layer.LIST)
			assert.is_true(rawequal(CELL, layer:GetMarked(4)))
		end)

		it("takes cells out while a backward loop runs over the list", function()
			local layer = grid:NewLayer(resetCell)
			for i = 1, 6 do
				layer:Get(i).metal = i
				layer:Mark(i)
			end
			local LIST, seen = layer.LIST, {}
			for n = #LIST, 1, -1 do
				local i = LIST[n]
				seen[#seen + 1] = i
				if i % 2 == 0 then
					layer:Unmark(i)
				end
			end
			assert.same({ 6, 5, 4, 3, 2, 1 }, seen)
			assert.same({ 1, 3, 5 }, layer.LIST)
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
