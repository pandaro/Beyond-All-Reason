--- Table pools: tables given back are emptied and handed out again instead of new ones.
--
-- Worth it for code that makes hundreds of short-lived tables a frame; not for a few tables, nor for tables kept
-- for long, where a pool only adds the cost of emptying them. A table given back must not be used again.
--
-- local TablePool = shard_include("tablepool")
-- local pool = TablePool.New()
-- local list = pool:Get()
-- pool:Release(list)

local pairs = pairs

---@class TablePool
---@field free table[] the released tables, ready for Get
---@field freeCount integer
local TablePool = {}
TablePool.__index = TablePool

--- A new, empty pool
function TablePool.New()
	return setmetatable({ free = {}, freeCount = 0 }, TablePool)
end

--- An empty table: a released one when there is one, a new one otherwise
function TablePool:Get()
	local freeCount = self.freeCount
	if freeCount == 0 then
		return {}
	end
	local free = self.free
	local result = free[freeCount]
	free[freeCount] = nil
	self.freeCount = freeCount - 1
	return result
end

--- Empties a table and keeps it for the next Get
function TablePool:Release(used)
	for key in pairs(used) do
		used[key] = nil
	end
	local freeCount = self.freeCount + 1
	self.free[freeCount] = used
	self.freeCount = freeCount
end

return TablePool
