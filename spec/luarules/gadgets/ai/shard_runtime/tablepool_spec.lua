local TablePool = assert(loadfile("luarules/gadgets/ai/shard_runtime/tablepool.lua"))()

describe("TablePool", function()
	it("hands out an empty table from a new pool", function()
		local pool = TablePool.New()

		assert.same({}, pool:Get())
	end)

	it("hands a released table out again, emptied of its array and hash entries", function()
		local pool = TablePool.New()
		local used = pool:Get()
		used[1], used[2], used.name, used[used] = 1, 2, "x", true

		pool:Release(used)
		local again = pool:Get()

		assert.equal(used, again)
		assert.is_nil(next(again))
	end)

	it("hands out each released table once, and a new one when none is left", function()
		local pool = TablePool.New()
		local first, second = pool:Get(), pool:Get()
		pool:Release(first)
		pool:Release(second)

		local a, b, c = pool:Get(), pool:Get(), pool:Get()

		assert.are_not.equal(a, b)
		assert.is_true((a == first or a == second) and (b == first or b == second))
		assert.is_true(c ~= first and c ~= second)
	end)

	it("allocates nothing once warmed up", function()
		local pool = TablePool.New()
		local held = {}
		for round = 1, 2 do
			for i = 1, 100 do
				local list = pool:Get()
				list[1], list.round = i, round
				held[i] = list
			end
			for i = 1, 100 do
				pool:Release(held[i])
			end
		end

		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, 50 do
			for i = 1, 100 do
				local list = pool:Get()
				list[1], list.round = i, 0
				held[i] = list
			end
			for i = 1, 100 do
				pool:Release(held[i])
			end
		end
		local after = collectgarbage("count")
		collectgarbage("restart")

		assert.equal(before, after)
	end)
end)
