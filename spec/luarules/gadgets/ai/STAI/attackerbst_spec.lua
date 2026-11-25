---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase, Behaviour and Module, then STAI/attackhst.lua and STAI/attackerbst.lua, in an
-- environment of their own; the behaviour talks to a real AttackHST.
local function newAttackerBST()
	local env = setmetatable({}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/behaviour.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/attackhst.lua",
		"luarules/gadgets/ai/STAI/attackerbst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local attack = env.AttackHST()
	attack.ai = {}
	attack:Init()
	local attacker = env.AttackerBST()
	attacker.ai = { attackhst = attack }
	attacker.Warn = function() end
	return attacker
end

describe("STAI AttackerBST", function()
	it("counts an idle member on its squad", function()
		local attacker = newAttackerBST()
		attacker.squad = { idleCount = 2 }
		attacker:OwnerIdle()
		assert.are.equal(3, attacker.squad.idleCount)
		assert.is_true(attacker.idle)
	end)

	it("starts the idle count of a squad that has none", function()
		local attacker = newAttackerBST()
		attacker.squad = {}
		attacker:OwnerIdle()
		assert.are.equal(1, attacker.squad.idleCount)
	end)

	it("counts a failed move as idle", function()
		local attacker = newAttackerBST()
		attacker.squad = { idleCount = 0 }
		attacker:OwnerMoveFailed()
		assert.are.equal(1, attacker.squad.idleCount)
	end)

	it("counts the idle members of a squad and not a recruit without one", function()
		local member = newAttackerBST()
		local recruit = newAttackerBST()
		member.squad = { idleCount = 0 }
		recruit:OwnerIdle()
		member:OwnerIdle()
		assert.are.equal(1, member.squad.idleCount)
		assert.is_true(recruit.idle)
		assert.is_nil(recruit.squad)
	end)

	it("never asks for control of the unit", function()
		local attacker = newAttackerBST()
		attacker.squad = { idleCount = 0 }
		attacker.target = { X = 1, Z = 1 }
		attacker.attacking = true
		assert.are.equal(0, attacker:Priority())
	end)
end)
