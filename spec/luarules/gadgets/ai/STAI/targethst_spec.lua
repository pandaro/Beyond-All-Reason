---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase and Module, then STAI/targethst.lua, in an environment of their own. ENEMY holds
-- the cells of cells, keyed by "X:Z", in the order of the list.
local function newTargetHST(cells)
	local env = setmetatable({
		shard_include = function(name)
			return assert(loadfile("luarules/gadgets/ai/shard_runtime/" .. name .. ".lua"))()
		end,
		map = {
			GetGroundHeight = function()
				return 0
			end,
		},
	}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/targethst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local ENEMY = { LIST = {}, CELLS = {} }
	local targetHST = env.TargetHST()
	targetHST.ai = {
		loshst = { ENEMY = ENEMY },
		gridhst = {
			GetCell = function(_, X, Z)
				return cells[X .. ":" .. Z]
			end,
			PosToGrid = function(_, position)
				return math.floor(position.x / 256) + 1, math.floor(position.z / 256) + 1
			end,
		},
	}
	targetHST:Init()
	return targetHST, ENEMY
end

-- A cell of ENEMY at X, Z with one moving unit
local function newCell(X, Z, unitID)
	return {
		X = X,
		Z = Z,
		POS = { x = X * 256 - 128, y = 0, z = Z * 256 - 128 },
		SPEED = 1,
		metal = 50,
		units = { [unitID] = "mobile" },
	}
end

describe("STAI TargetHST", function()
	it("gives back to the pool the old blobs with the tables in them", function()
		local cells = { ["1:1"] = newCell(1, 1, 10), ["2:1"] = newCell(2, 1, 11) }
		local targetHST, ENEMY = newTargetHST(cells)
		ENEMY.CELLS[1] = cells["1:1"]
		ENEMY.CELLS[2] = cells["2:1"]
		ENEMY.LIST[1] = 1
		ENEMY.LIST[2] = 2

		targetHST:GetBlobs("MOBILE_BLOBS", "SPEED")

		local blob = targetHST.MOBILE_BLOBS["1:1"]
		assert.equal(2, #blob.cells)
		assert.equal(100, blob.metal)
		assert.same({ [10] = "mobile", [11] = "mobile" }, blob.units)
		local used = { blob, blob.position, blob.cells, blob.cells[1], blob.cells[2], blob.units, blob.targetCell }

		ENEMY.LIST[1] = nil
		ENEMY.LIST[2] = nil
		targetHST:GetBlobs("MOBILE_BLOBS", "SPEED")

		assert.is_nil(next(targetHST.MOBILE_BLOBS))
		local pool = targetHST.blobPool
		assert.equal(#used, pool.freeCount)
		for _, usedTable in ipairs(used) do
			local found = false
			for n = 1, pool.freeCount do
				found = found or pool.free[n] == usedTable
			end
			assert.is_true(found)
			assert.is_nil(next(usedTable))
		end
	end)
end)
