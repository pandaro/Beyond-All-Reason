---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase and Behaviour, then STAI/bootbst.lua, in an environment of their own.
local function newBootBST(name, unitTable, labs, position)
	local env = setmetatable({}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/behaviour.lua",
		"luarules/gadgets/ai/STAI/bootbst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local boot = env.BootBST()
	local internal = {
		ID = function()
			return 7
		end,
		Name = function()
			return name
		end,
	}
	boot.unit = {
		Internal = function()
			return internal
		end,
		ElectBehaviour = function() end,
	}
	boot.game = {
		Frame = function()
			return 0
		end,
	}
	boot.ai = {
		armyhst = { unitTable = unitTable },
		labshst = { labs = labs },
		tool = {
			UnitPos = function()
				return position
			end,
			PositionWithinRect = function(_, pos, rect)
				return pos.x > rect.x1 and pos.x < rect.x2 and pos.z > rect.z1 and pos.z < rect.z2
			end,
		},
	}
	return boot
end

describe("STAI BootBST", function()
	local unitTable = {
		armham = { speed = 50, mtype = "veh" },
		armmex = { speed = 0, mtype = "bldg" },
	}
	local lab = { x1 = 0, z1 = 0, x2 = 80, z2 = 80 }

	it("is mobile for a unit that moves and not for a building", function()
		local unit = newBootBST("armham", unitTable, {}, { x = 0, z = 0 })
		local building = newBootBST("armmex", unitTable, {}, { x = 0, z = 0 })
		unit:Init()
		building:Init()
		assert.is_true(unit.mobile)
		assert.is_false(building.mobile)
	end)

	it("finds the factory when the unit is inside its exit rect", function()
		local behaviour = {}
		local boot = newBootBST(
			"armham",
			unitTable,
			{ [1] = { behaviour = behaviour, exitRect = lab } },
			{ x = 40, z = 40 }
		)
		boot:Init()
		assert.equal(behaviour, boot.factory)
		assert.equal(120, boot:Priority())
	end)

	it("has no factory when the unit is outside the exit rect, even after being inside", function()
		local labs = { [1] = { behaviour = {}, exitRect = lab } }
		local position = { x = 40, z = 40 }
		local boot = newBootBST("armham", unitTable, labs, position)
		boot:Init()
		position.x = 500
		boot:FindMyFactory()
		assert.is_nil(boot.factory)
		assert.equal(0, boot:Priority())
	end)

	it("skips a lab without behaviour or exit rect", function()
		local boot = newBootBST(
			"armham",
			unitTable,
			{ [1] = { exitRect = lab }, [2] = { behaviour = {} } },
			{ x = 40, z = 40 }
		)
		boot:Init()
		assert.is_nil(boot.factory)
	end)
end)
