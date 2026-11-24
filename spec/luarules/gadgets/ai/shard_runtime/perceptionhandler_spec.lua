---@diagnostic disable: undefined-field, call-non-callable

-- Loads the runtime's class, AIBase, Module and perceptionhandler.lua in an environment of their own.
local function newPerceptionHandler()
	local env = setmetatable({}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/shard_runtime/perceptionhandler.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local handler = env.PerceptionHandler()
	handler:Init()
	return handler
end

local function deadUnit(unitID)
	return {
		ID = function()
			return unitID
		end,
	}
end

describe("PerceptionHandler", function()
	it("is an ally team module", function()
		local handler = newPerceptionHandler()

		assert.equal("ally", handler:Scope())
		assert.equal("perceptionhandler", handler:internalName())
	end)

	it("follows a unit into and out of LOS", function()
		local handler = newPerceptionHandler()

		handler:UnitEnteredLos(10, 1, 0, 1)
		assert.is_true(handler:Sees(10))
		assert.is_false(handler:OnRadar(10))

		handler:UnitLeftLos(10, 1, 0, 1)
		assert.is_false(handler:Sees(10))
		assert.same({}, handler.los)
	end)

	it("follows a unit into and out of radar", function()
		local handler = newPerceptionHandler()

		handler:UnitEnteredRadar(10, 1, 0, 1)
		assert.is_true(handler:OnRadar(10))
		assert.is_false(handler:Sees(10))

		handler:UnitLeftRadar(10, 1, 0, 1)
		assert.is_false(handler:OnRadar(10))
		assert.same({}, handler.radar)
	end)

	it("keeps on radar a unit in LOS and radar that leaves LOS", function()
		local handler = newPerceptionHandler()
		handler:UnitEnteredRadar(10, 1, 0, 1)
		handler:UnitEnteredLos(10, 1, 0, 1)

		handler:UnitLeftLos(10, 1, 0, 1)

		assert.is_false(handler:Sees(10))
		assert.is_true(handler:OnRadar(10))
	end)

	it("forgets a dead unit in LOS and radar, and only that unit", function()
		local handler = newPerceptionHandler()
		handler:UnitEnteredRadar(10, 1, 0, 1)
		handler:UnitEnteredLos(10, 1, 0, 1)
		handler:UnitEnteredRadar(11, 1, 0, 1)
		handler:UnitEnteredLos(11, 1, 0, 1)

		handler:UnitDead(deadUnit(10))

		assert.same({ [11] = true }, handler.los)
		assert.same({ [11] = true }, handler.radar)
	end)

	it("neither sees nor has on radar a unit it never heard of", function()
		local handler = newPerceptionHandler()

		assert.is_false(handler:Sees(99))
		assert.is_false(handler:OnRadar(99))
	end)
end)
