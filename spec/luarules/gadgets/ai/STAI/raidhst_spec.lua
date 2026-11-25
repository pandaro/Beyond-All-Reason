---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase and Module, then STAI/raidhst.lua, in an environment of their own with the
-- engine globals the guard branch of SquadAdvance reads: game, CMD.
local CMD = { FIGHT = 16, GUARD = 25, MOVE = 10 }

local function newRaidHST(game)
	local env = setmetatable({ game = game, CMD = CMD }, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/raidhst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local raid = env.RaidHST()
	raid.game = game
	raid.ai = {
		Name = function()
			return "STAI"
		end,
		targethst = { MOBILE_BLOBS = {} },
		tool = {
			ResetTable = function()
				return {}
			end,
			GiveOrder = function(_, ids, cmd)
				raid.orders[#raid.orders + 1] = { ids = ids, cmd = cmd }
			end,
		},
	}
	raid.orders = {}
	raid:Init()
	return raid
end

local function newMember(id, lastCommand, lastTarget)
	local member = {
		unit = {
			Internal = function()
				return {
					ID = function()
						return id
					end,
				}
			end,
		},
		lastCommand = lastCommand,
		lastTarget = lastTarget,
	}
	function member:GetLastCommandReceived()
		return self.lastCommand, self.lastTarget
	end
	function member:SetLastCommandReceived(command, target)
		self.lastCommand = command
		self.lastTarget = target
	end
	return member
end

describe("STAI RaidHST", function()
	it("guards with the members that are not yet guarding the target, from index 1", function()
		local game = {
			Frame = function()
				return 1000
			end,
			GetUnitByID = function()
				return {
					GetPosition = function()
						return { x = 0, y = 0, z = 0 }
					end,
				}
			end,
		}
		local raid = newRaidHST(game)
		local target = { X = 1, Z = 1 }
		local squad = {
			squadID = 1,
			role = 77,
			target = target,
			path = {},
			step = 1,
			lastAdvance = 0,
			idleCount = 0,
			members = {
				newMember(101, CMD.GUARD, target),
				newMember(102, CMD.MOVE, nil),
				newMember(103, CMD.MOVE, nil),
			},
		}

		raid:SquadAdvance(squad)

		assert.equal(1, #raid.orders)
		assert.equal(CMD.GUARD, raid.orders[1].cmd)
		assert.same({ 102, 103 }, raid.orders[1].ids)
		assert.equal(2, #raid.orders[1].ids)
	end)

	it("advances a squad whose members went idle since the last advance", function()
		local game = {
			Frame = function()
				return 1000
			end,
		}
		local raid = newRaidHST(game)
		raid.ai.tool.RawDistance = function()
			return 1000
		end
		local squad = {
			squadID = 1,
			role = "offense",
			target = { X = 1, Z = 1 },
			path = { { x = 100, z = 100 }, { x = 200, z = 200 }, { x = 300, z = 300 } },
			step = 1,
			position = { x = 0, z = 0 },
			lastAdvance = 0,
			idleCount = 0,
			cmdUnitId = {},
			members = {
				newMember(101),
				newMember(102),
				newMember(103),
				newMember(104),
			},
		}
		for _ = 1, 4 do
			raid:MemberIdle({ squad = squad }, squad)
		end
		assert.equal(4, squad.idleCount)

		raid:SquadAdvance(squad)

		assert.equal(2, squad.step)
		assert.equal(0, squad.idleCount)
	end)
end)
