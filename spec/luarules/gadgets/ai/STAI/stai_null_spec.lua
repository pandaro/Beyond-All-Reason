---@diagnostic disable: undefined-global, undefined-field, inject-field

-- STAI outside the engine with shard_null: the global, ally and team objects boot, run a few frames and meet a
-- commander. STAI reads the engine directly (Spring, UnitDefs), so the spec builds a small engine of its own;
-- everything runs in an environment of its own, so no global of the suite changes.
local SpecEnv = VFS.Include("spec/support/spec_env.lua")

-- a map of 128 by 128 squares, flat, with three metal spots
local MAP_EXTRAS = {
	CanBuildHere = function()
		return true
	end,
	GetGroundHeight = function()
		return 10
	end,
	-- the length of the path: always short
	TestPath = function()
		return 50
	end,
	-- a path with no waypoints: the commander's walk to the metal spots tramples no cell
	GetPathObject = function()
		return {}
	end,
	GetPathWaypoints = function()
		return {}
	end,
	-- without a metal spot LabsHST divides by zero when it rates the factories
	GetMetalSpots = function()
		return { { x = 200, y = 10, z = 200 }, { x = 800, y = 10, z = 200 }, { x = 200, y = 10, z = 800 } }
	end,
}

-- a game with the units of the test, by ID; the orders it is given go to orders
local function newGameExtras(units, UnitDefNames, orders)
	return {
		GiveOrder = function(_, id, cmd, params, options, method)
			orders[#orders + 1] = { id = id, cmd = cmd, params = params, options = options, method = method }
			return true
		end,
		GetTypeByName = function(_, name)
			local def = UnitDefNames[name]
			if def == nil then
				return nil
			end
			return {
				ID = function()
					return def.id
				end,
				Name = function()
					return name
				end,
				CanBuild = function(_, other)
					for _, id in ipairs(def.buildOptions) do
						if id == other:ID() then
							return true
						end
					end
					return false
				end,
			}
		end,
		GetUnitByID = function(_, id)
			return units[id]
		end,
		GetTeamUnitDefCount = function()
			return 0
		end,
		GetTeamUnitsByDefs = function()
			return {}
		end,
		getUnitsInCylinder = function()
			return {}
		end,
	}
end

-- The environment STAI runs in: its own require, which finds the AIs under luarules/gadgets/ai and runs every file
-- in the environment; the null map and game of shard_null get what STAI calls on them.
local function newEnv(overrides, units, orders)
	local env = SpecEnv.new(overrides)
	env.game_engine = {
		Map = function()
			return {
				MapDimensions = function()
					return { x = 128, z = 128, y = 0 }
				end,
			}
		end,
	}
	local extras = {
		["shard_runtime/shard_null/map"] = MAP_EXTRAS,
		["shard_runtime/shard_null/game"] = newGameExtras(units, overrides.UnitDefNames, orders),
	}
	local loaded = {}
	env.package = { path = "luarules/gadgets/ai/?.lua", loaded = loaded }
	env.require = function(name)
		if loaded[name] ~= nil then
			return loaded[name]
		end
		local file = string.gsub(env.package.path, "%?", name)
		local chunk = assert(loadfile(file))
		setfenv(chunk, env)
		local result = chunk(name)
		if result == nil then
			result = true
		end
		loaded[name] = result
		for key, value in pairs(extras[name] or {}) do
			result[key] = value
		end
		return result
	end
	return env
end

-- A unit def as the engine gives it, every field ArmyHST reads set to a plain value; the fields the test hands in
-- make it a builder, a building and the like.
local function newDef(id, name, fields)
	local def = {
		id = id,
		name = name,
		humanName = name,
		corpse = name .. "_dead",
		speed = 0,
		maxAcc = 0,
		turnRate = 0,
		maxDec = 0,
		health = 100,
		metalCost = 50,
		energyCost = 500,
		buildTime = 500,
		minWaterDepth = 0,
		xsize = 2,
		zsize = 2,
		moveDef = {},
		customParams = {},
		modCategories = {},
		weapons = {},
		buildOptions = {},
	}
	for key, value in pairs(fields or {}) do
		def[key] = value
	end
	return def
end

-- the factories ArmyHST knows by name: LabsHST rates every one of them at Init
local FACTORIES = [[
	corap armap corlab armlab corvp armvp coralab coravp corhp armhp corfhp armfhp armalab armavp coraap armaap
	corplat armplat corsy armsy corasy armasy coramsub armamsub corgant armshltx corgantuw armshltxuw
]]

-- The unit types of the test, as the engine's UnitDefs and UnitDefNames hold them. For each side: a commander, a
-- mex, a fighter, the nano turrets and the factories, which build the fighter. Besides: the five constructors
-- ArmyHST names as the example of each way to move, which it asks the engine where they can go.
local function newUnitDefs()
	local UnitDefs, UnitDefNames = {}, {}
	local nextID = 0
	local function add(name, fields)
		nextID = nextID + 1
		local def = newDef(nextID, name, fields)
		UnitDefs[nextID] = def
		UnitDefNames[name] = def
		return nextID
	end
	for _, side in ipairs({ "arm", "cor" }) do
		local mex = add(side .. "mex", { isBuilding = true, extractsMetal = 0.001 })
		local fighter =
			add(side .. "pw", { speed = 90, moveDef = { name = "bot1" }, modCategories = { weapon = true } })
		local factories = {}
		for factory in string.gmatch(FACTORIES, "%f[%w]" .. side .. "%w*") do
			factories[#factories + 1] = add(
				factory,
				{ isBuilding = true, isBuilder = true, isStaticBuilder = true, buildOptions = { fighter } }
			)
		end
		for _, nano in ipairs({ "nanotc", "nanotcplat" }) do
			add(side .. nano, { isBuilding = true, isBuilder = true, isStaticBuilder = true })
		end
		add(side .. "com", {
			isBuilder = true,
			isMobileBuilder = true,
			speed = 40,
			moveDef = { name = "commanderbot" },
			buildOptions = { mex, factories[1] },
		})
	end
	local moves = { armcv = "tank2", armck = "bot2", armbeaver = "abot1", armch = "hover2", armcs = "boat2" }
	moves.armacsub = "uboat2"
	for name, moveName in pairs(moves) do
		add(name, { isBuilder = true, isMobileBuilder = true, speed = 50, moveDef = { name = moveName } })
	end
	return UnitDefs, UnitDefNames
end

local function newSpring()
	return {
		GetGameRulesParam = function() end,
		-- currentLevel, storage, pull, income, expense, share, sent, received
		GetTeamResources = function()
			return 500, 1000, 0, 10, 0, 0.5, 0, 0
		end,
		TestMoveOrder = function()
			return true
		end,
		GetGroundHeight = function()
			return 10
		end,
	}
end

-- The engine's unit object for a unit of the team, as far as the commander's behaviours read it
local function newEngineUnit(id, name)
	return {
		ID = function()
			return id
		end,
		Team = function()
			return 0
		end,
		IsMine = function()
			return true
		end,
		Name = function()
			return name
		end,
		GetRawPos = function()
			return 100, 10, 100
		end,
		GetPosition = function()
			return { x = 100, y = 10, z = 100 }
		end,
		GetHealth = function()
			return 3000
		end,
		GetMaxHealth = function()
			return 3000
		end,
		-- health, maxHealth, paralyzeDamage, captureProgress, buildProgress, relativeHealth
		GetHealtsParams = function()
			return 3000, 3000, 0, 0, 1, 1
		end,
		CanBuild = function()
			return true
		end,
		Move = function()
			return true
		end,
		Patrol = function()
			return true
		end,
		Guard = function()
			return true
		end,
	}
end

-- Runs STAI/boot.lua: Init of the global, ally and team objects. The lines the AI prints are in lines, the orders
-- it gives in orders, the engine units of the test in units.
local function boot()
	local units, orders, lines = {}, {}, {}
	local UnitDefs, UnitDefNames = newUnitDefs()
	local env = newEnv({
		UnitDefs = UnitDefs,
		UnitDefNames = UnitDefNames,
		FeatureDefs = {},
		WeaponDefs = {},
		Spring = newSpring(),
	}, units, orders)
	env.print = function(...)
		lines[#lines + 1] = table.concat({ tostring((...)), select(2, ...) }, " ")
	end
	env.require("STAI/boot")
	return env, lines, units, orders
end

local function assertNoWarning(lines)
	for _, line in ipairs(lines) do
		assert.is_nil(string.find(line, "Warning", 1, true), line)
	end
end

describe("STAI under shard_null", function()
	it("boots the global, ally and team objects with the modules of their scopes, without a warning", function()
		local env, lines = boot()
		local ai = env.ai

		assert.equal("STAI", ai:Name())
		assert.is_true(ai.loaded)
		assert.is_true(ai.ally.loaded)
		assert.is_true(ai.global.loaded)
		assert.is_table(ai.global.maphst)
		assert.is_table(ai.global.armyhst)
		assert.is_table(ai.ally.loshst)
		assert.is_table(ai.unithst)
		assert.equal(ai.global.maphst, ai.maphst)
		assert.equal(ai.ally.loshst, ai.loshst)
		assertNoWarning(lines)
	end)

	it("runs Update on the three objects and every turn of the scheduler without an error", function()
		local env, lines = boot()
		local ai = env.ai

		for _ = 1, 3 do
			ai.global:Update()
			ai.ally:Update()
			ai:Update()
			for position = 1, #env.STAI.MScheduler do
				ai:ScheduledUpdate(position)
			end
		end

		assertNoWarning(lines)
	end)

	it("gives the commander its behaviours, and the commander orders the first mex", function()
		local env, lines, units, orders = boot()
		local ai = env.ai
		local commander = newEngineUnit(1, "armcom")
		units[1] = commander
		local commanderDef = env.UnitDefNames.armcom.id

		ai:UnitCreated(commander, commanderDef, 0)
		ai:UnitBuilt(commander, commanderDef, 0)
		ai:Update()

		local behaviours = ai.unithst.units[1].behaviours
		local names = {}
		for _, behaviour in pairs(behaviours) do
			names[behaviour:Name()] = true
		end
		assert.same({ BootBST = true, BuildersBST = true, CommanderBST = true }, names)
		assert.equal(1, #orders)
		assert.equal(1, orders[1].id)
		assert.equal(-env.UnitDefNames.armmex.id, orders[1].cmd)
		assertNoWarning(lines)
	end)
end)
