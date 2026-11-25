---@diagnostic disable: undefined-field, call-non-callable, inject-field

local TEAM = 0
local BUILDING = 1

-- Loads the runtime's class, AIBase, Module and Behaviour, then STAI/buildingshst.lua and STAI/commanderbst.lua, in an
-- environment of their own; the game knows the units of units.
local function loadEnv(units)
	local env = setmetatable({
		game = {
			GetUnitByID = function(_, unitID)
				return units[unitID]
			end,
		},
		VFS = {
			Include = function()
				return {}
			end,
		},
	}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/shard_runtime/behaviour.lua",
		"luarules/gadgets/ai/STAI/buildingshst.lua",
		"luarules/gadgets/ai/STAI/commanderbst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	return env
end

-- A unit at x, y, z
local function newUnit(unitID, x, y, z)
	return {
		ID = function()
			return unitID
		end,
		GetRawPos = function()
			return x, y, z
		end,
		GetPosition = function()
			return { x = x, y = y, z = z }
		end,
	}
end

describe("STAI BuildingsHST", function()
	it("keeps the center on a copy of the commander position without buildings, on their mean with them", function()
		local units = { [40] = newUnit(40, 100, 0, 300), [41] = newUnit(41, 300, 0, 500) }
		local env = loadEnv(units)
		local ai = { id = TEAM, maphst = { allSpots = {} } }
		local buildingsHST = env.BuildingsHST()
		buildingsHST.ai = ai
		buildingsHST:Init()
		buildingsHST.UnitMexMoveTest = function() end
		ai.buildingshst = buildingsHST
		local commanderUnit = newUnit(30, 1000, 20, 2000)
		local commander = env.CommanderBST()
		commander.ai = ai
		commander.unit = {
			Internal = function()
				return commanderUnit
			end,
		}
		commander:Init()

		assert.are_not.equal(commander.position, buildingsHST.CENTER)
		assert.same({ x = 1000, y = 20, z = 2000 }, buildingsHST.CENTER)

		local center = buildingsHST.CENTER
		buildingsHST:getCenter()

		assert.equal(center, buildingsHST.CENTER)
		assert.same({ x = 1000, y = 20, z = 2000 }, buildingsHST.CENTER)

		buildingsHST.ownImmobile[40] = BUILDING
		buildingsHST.ownImmobile[41] = BUILDING
		buildingsHST:getCenter()

		assert.same({ x = 200, y = 0, z = 400 }, buildingsHST.CENTER)
		assert.same({ x = 1000, y = 20, z = 2000 }, commander.position)
	end)
end)
