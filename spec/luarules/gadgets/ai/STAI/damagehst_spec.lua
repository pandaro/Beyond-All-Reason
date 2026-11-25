---@diagnostic disable: undefined-field, call-non-callable, inject-field

local TEAM = 0
local ALLY = 0
local ENEMY_ALLY = 1

-- Loads the runtime's class, AIBase and Module, then STAI/damagehst.lua, in an environment of their own.
-- AddBadPosition is replaced by a fake that keeps its arguments.
local function newDamageHST()
	local env = setmetatable({
		game = {
			GetTeamID = function()
				return TEAM
			end,
		},
	}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/damagehst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local damageHST = env.DamageHST()
	damageHST.ai = {
		allyId = ALLY,
		friendlyTeamID = {},
		armyhst = {
			unitTable = {
				defender = { name = "defender", defId = 11, metalCost = 50, mtype = "veh" },
				turret = { name = "turret", defId = 22, metalCost = 300, isBuilding = true },
			},
		},
		gridhst = {
			NewLayer = function()
				return {}
			end,
		},
		loshst = { losEnemy = {}, radarEnemy = {} },
	}
	damageHST:Init()
	damageHST.badPositions = {}
	damageHST.AddBadPosition = function(self, position, mtype, attackerThreat, defenderThreat, duration)
		self.badPositions[#self.badPositions + 1] = { position, mtype, attackerThreat, defenderThreat, duration }
	end
	return damageHST
end

local function newUnit(unitID, name, teamID, allyTeamID)
	return {
		ID = function()
			return unitID
		end,
		Name = function()
			return name
		end,
		Team = function()
			return teamID
		end,
		AllyTeam = function()
			return allyTeamID
		end,
		GetPosition = function()
			return { x = 100, y = 0, z = 200 }
		end,
	}
end

describe("STAI DamageHST", function()
	it("puts a building that hits our unit in the los with the type of the building", function()
		local damageHST = newDamageHST()
		damageHST.ai.loshst.radarEnemy[30] = 22

		damageHST:UnitDamaged(newUnit(10, "defender", TEAM, ALLY), newUnit(30, "turret", 5, ENEMY_ALLY), 40)

		assert.equal(22, damageHST.ai.loshst.losEnemy[30])
		assert.is_nil(damageHST.ai.loshst.radarEnemy[30])
		assert.same({ { { x = 100, y = 0, z = 200 }, "veh", 300, 50, 900 } }, damageHST.badPositions)
	end)

	it("counts an attacker out of unitTable as its damage", function()
		local damageHST = newDamageHST()

		damageHST:UnitDamaged(newUnit(10, "defender", TEAM, ALLY), newUnit(31, "unknown", 5, ENEMY_ALLY), 40)

		assert.same({}, damageHST.ai.loshst.losEnemy)
		assert.same({ { { x = 100, y = 0, z = 200 }, "veh", 40, 50, 900 } }, damageHST.badPositions)
	end)
end)
