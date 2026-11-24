---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase, Module and perceptionhandler.lua, then Shard/attackhandler.lua, in an
-- environment of their own.
local function loadAttackHandler()
	local env = setmetatable({}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/shard_runtime/perceptionhandler.lua",
		"luarules/gadgets/ai/Shard/attackhandler.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	return env
end

local function enemy(unitID, x, z)
	return {
		ID = function()
			return unitID
		end,
		GetPosition = function()
			return { x = x, y = 0, z = z }
		end,
		CanMove = function()
			return true
		end,
		CanBuild = function()
			return false
		end,
	}
end

-- An AttackHandler with enough recruits to attack, the given enemies, and the ally team's PerceptionHandler;
-- the cells the recruits are sent to go to `attacked`.
local function newAttackHandler(enemies)
	local env = loadAttackHandler()
	local perception = env.PerceptionHandler()
	perception:Init()
	local handler = env.AttackHandler()
	handler:Init()
	handler.ai = { perceptionhandler = perception }
	handler.game = {
		map = {
			MapDimensions = function()
				return { x = 64, z = 64 }
			end,
		},
		GetEnemies = function()
			return enemies
		end,
	}
	local attacked = {}
	for i = 1, 10 do
		handler.recruits[i] = {
			engineID = i,
			AttackCell = function(_, cell)
				attacked[#attacked + 1] = cell
			end,
		}
	end
	return handler, perception, attacked
end

describe("Shard AttackHandler", function()
	it("attacks no enemy the ally team does not see in LOS", function()
		local handler, perception, attacked = newAttackHandler({ enemy(300, 1000, 1000) })
		perception:UnitEnteredRadar(300, 3, 0, 1)

		handler:DoTargetting()

		assert.same({}, attacked)
		assert.equal(10, #handler.recruits)
	end)

	it("attacks the enemies the ally team sees, and leaves out the one it does not", function()
		-- alone in its cell, the unseen enemy would be the weakest target
		local handler, perception, attacked =
			newAttackHandler({ enemy(300, 1000, 1000), enemy(301, 3000, 3000), enemy(302, 1010, 1010) })
		perception:UnitEnteredLos(300, 3, 0, 1)
		perception:UnitEnteredLos(302, 3, 0, 1)

		handler:DoTargetting()

		assert.equal(10, #attacked)
		assert.equal(1010, attacked[1].posx)
		assert.equal(1010, attacked[1].posz)
		assert.same({}, handler.recruits)
	end)
end)
