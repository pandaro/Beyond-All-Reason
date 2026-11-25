---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase, Behaviour and Module, then STAI/attackhst.lua, in an environment of their own
-- with the engine globals SquadAdvance reads: game, CMD.
local CMD = { FIGHT = 16, MOVE = 10 }

local function newAttackHST(frame)
	local env = setmetatable({ game = { Frame = frame }, CMD = CMD }, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/behaviour.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/attackhst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local attack = env.AttackHST()
	attack.ai = {
		tool = {
			ResetTable = function()
				return {}
			end,
			distance = function()
				return 1000
			end,
			GiveOrder = function() end,
		},
		gridhst = {
			GridToPos = function(_, x, z)
				return { x = x, z = z }
			end,
		},
	}
	attack:Init()
	return attack
end

local function newSquad(memberCount)
	local members = {}
	for i = 1, memberCount do
		members[i] = {
			unit = {
				Internal = function()
					return {
						ID = function()
							return i
						end,
					}
				end,
			},
		}
	end
	return {
		squadID = 1,
		role = "offense",
		target = { X = 1, Z = 1 },
		path = { { x = 100, z = 100 }, { x = 200, z = 200 }, { x = 300, z = 300 } },
		step = 1,
		position = { x = 0, z = 0 },
		lastAdvance = 0,
		idleCount = 0,
		cmdUnitId = {},
		members = members,
	}
end

describe("STAI AttackHST", function()
	it("advances a squad whose members went idle since the last advance", function()
		local attack = newAttackHST(function()
			return 1000
		end)
		local squad = newSquad(4)
		for _ = 1, 4 do
			attack:MemberIdle({ squad = squad })
		end
		assert.equal(4, squad.idleCount)

		attack:SquadAdvance(squad)

		assert.equal(2, squad.step)
		assert.equal(0, squad.idleCount)
	end)

	it("keeps the squad on its step when too few members went idle", function()
		local attack = newAttackHST(function()
			return 1000
		end)
		local squad = newSquad(4)
		attack:MemberIdle({ squad = squad })
		attack:MemberIdle({ squad = squad })

		attack:SquadAdvance(squad)

		assert.equal(1, squad.step)
	end)
end)
