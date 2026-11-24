---@diagnostic disable: undefined-field, need-check-nil, inject-field

local RUNTIME_PATH = "luarules/gadgets/ai/shard_runtime/"
local RUNTIME_FILES = { "class", "aibase", "module", "shardai", "shardally", "shardglobal" }

-- Loads the runtime classes into an environment of their own, as spring_lua/boot.lua does, then the extra runtime
-- files, with a console that keeps every line it is sent.
local function loadRuntime(extraFiles)
	local runtime = { console = {} }
	local env = setmetatable({ Spring = { Echo = function() end } }, { __index = _G })
	local files = { unpack(RUNTIME_FILES) }
	for _, name in ipairs(extraFiles or {}) do
		files[#files + 1] = name
	end
	for _, name in ipairs(files) do
		local chunk = assert(loadfile(RUNTIME_PATH .. name .. ".lua"))
		setfenv(chunk, env)
		chunk()
	end
	runtime.env = env
	return runtime
end

-- A new api for every object, as the AI loader builds one: shard_include hands out the given module list and
-- records every other file asked for.
local function newApi(runtime, modules, includes)
	local game = {}
	function game:SendToConsole(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		runtime.console[#runtime.console + 1] = table.concat(parts, " ")
	end
	function game:GetTeamID()
		return self.ai.id
	end
	function game:DrawDisplay() end
	function game:GameName()
		return "test game"
	end
	local map = {}
	function map:MapName()
		return "test map"
	end
	return {
		game = game,
		map = map,
		shard_include = function(file)
			if file == "modules" then
				return modules
			end
			includes[#includes + 1] = file
		end,
	}
end

local function newObject(runtime, class, modules, fields)
	local object = class()
	object.fullname = "Test"
	object.includes = {}
	object.api = newApi(runtime, modules, object.includes)
	for key, value in pairs(fields) do
		object[key] = value
	end
	return object
end

-- A module class of the given scope that counts the Init and Update calls of all its instances and of each one.
local function moduleClass(runtime, internalName, scope)
	local class = runtime.env.class(runtime.env.Module)
	class.inits = 0
	function class:Name()
		return internalName .. " module"
	end
	function class:internalName()
		return internalName
	end
	if scope ~= nil then
		function class:Scope()
			return scope
		end
	end
	function class:Init()
		class.inits = class.inits + 1
		self.updates = 0
	end
	function class:Update()
		self.updates = self.updates + 1
	end
	return class
end

local function linesWith(runtime, text)
	local count = 0
	for _, line in ipairs(runtime.console) do
		if string.find(line, text, 1, true) then
			count = count + 1
		end
	end
	return count
end

-- One global, the ally teams 0 and 1, teams 1 and 2 in ally team 0 and team 3 in ally team 1, initialised
-- global -> ally team -> team as the AI loader does.
---@return { global: table, allies: table<integer, table>, teams: table[] }
local function buildWorld(runtime, modules)
	local env = runtime.env
	local global = newObject(runtime, env.ShardGlobal, modules, { AIs = {} })
	local allies = {}
	for allyId = 0, 1 do
		allies[allyId] = newObject(runtime, env.ShardAlly, modules, { allyId = allyId, AIs = {}, global = global })
	end
	local teams = {}
	for id, allyId in ipairs({ 0, 0, 1 }) do
		local ally = allies[allyId]
		teams[id] = newObject(runtime, env.ShardAI, modules, { id = id, allyId = allyId, ally = ally, global = global })
		ally.AIs[#ally.AIs + 1] = teams[id]
		global.AIs[#global.AIs + 1] = teams[id]
	end
	global:Init()
	allies[0]:Init()
	allies[1]:Init()
	for _, team in ipairs(teams) do
		team:Init()
	end
	return { global = global, allies = allies, teams = teams }
end

describe("ShardAI module scopes", function()
	local runtime ---@type table
	local teamModule ---@type table
	local allyModule ---@type table
	local globalModule ---@type table
	local modules ---@type table[]

	before_each(function()
		runtime = loadRuntime()
		teamModule = moduleClass(runtime, "teammodule", "team")
		allyModule = moduleClass(runtime, "allymodule", "ally")
		globalModule = moduleClass(runtime, "globalmodule", "global")
		modules = { globalModule, allyModule, teamModule }
	end)

	it("skips a module without Scope() or with an unknown one, warning once for each class", function()
		local noScope = moduleClass(runtime, "noscope", nil)
		local unknownScope = moduleClass(runtime, "unknownscope", "teams")
		local world = buildWorld(runtime, { noScope, unknownScope, teamModule })

		local teams = world.teams
		for _, object in ipairs({ world.global, world.allies[0], world.allies[1], teams[1], teams[2], teams[3] }) do
			assert.is_nil(object.noscope)
			assert.is_nil(object.unknownscope)
		end
		assert.equal(0, noScope.inits + unknownScope.inits)
		assert.equal(3, teamModule.inits)
		assert.equal(1, linesWith(runtime, "Skipping the loading of noscope module"))
		assert.equal(1, linesWith(runtime, "Skipping the loading of unknownscope module"))
	end)

	it("gives every team its own team module and shares the ally and global ones", function()
		local world = buildWorld(runtime, modules)
		local team1, team2, team3 = world.teams[1], world.teams[2], world.teams[3]

		assert.equal(team1.allymodule, team2.allymodule)
		assert.are_not.equal(team1.allymodule, team3.allymodule)
		assert.equal(world.allies[0].allymodule, team1.allymodule)
		assert.equal(world.allies[1].allymodule, team3.allymodule)
		for _, object in ipairs({ world.allies[0], world.allies[1], team1, team2, team3 }) do
			assert.equal(world.global.globalmodule, object.globalmodule)
		end
		assert.are_not.equal(team1.teammodule, team2.teammodule)
		assert.are_not.equal(team1.teammodule, team3.teammodule)
	end)

	it("reaches the modules of its own and wider scopes only", function()
		local world = buildWorld(runtime, modules)
		local team1 = world.teams[1]

		assert.is_not_nil(team1.teammodule)
		assert.is_not_nil(team1.allymodule)
		assert.is_not_nil(team1.globalmodule)
		assert.equal(world.allies[0], team1.allymodule.ai)
		assert.is_nil(team1.allymodule.ai.teammodule)
		assert.is_not_nil(team1.allymodule.ai.globalmodule)
		assert.equal(world.global, team1.globalmodule.ai)
		assert.is_nil(team1.globalmodule.ai.allymodule)
		assert.is_nil(team1.globalmodule.ai.teammodule)
	end)

	it("initialises a shared module once and hands every module an event once", function()
		local world = buildWorld(runtime, modules)

		assert.equal(1, globalModule.inits)
		assert.equal(2, allyModule.inits)
		assert.equal(3, teamModule.inits)

		world.global:Update()
		world.allies[0]:Update()
		world.allies[1]:Update()
		for _, team in ipairs(world.teams) do
			team:Update()
		end

		assert.equal(1, world.global.globalmodule.updates)
		assert.equal(1, world.allies[0].allymodule.updates)
		assert.equal(1, world.allies[1].allymodule.updates)
		for _, team in ipairs(world.teams) do
			assert.equal(1, team.teammodule.updates)
		end
	end)

	it("loads behaviours for team AIs only", function()
		local world = buildWorld(runtime, modules)

		assert.same({}, world.global.includes)
		assert.same({}, world.allies[0].includes)
		assert.same({ "behaviourfactory", "unit" }, world.teams[1].includes)
	end)

	it("adds a module after Init only to an object of its scope", function()
		local world = buildWorld(runtime, { teamModule })
		local team1 = world.teams[1]
		local late = moduleClass(runtime, "latemodule", "ally")

		team1:AddModule(late())

		assert.is_nil(team1.latemodule)
		assert.equal(1, linesWith(runtime, "Skipping latemodule module"))
	end)

	describe("without ally and global objects", function()
		it("loads and runs team modules as before", function()
			local team = newObject(runtime, runtime.env.ShardAI, { teamModule }, { id = 1, allyId = 0 })
			team:Init()
			team:Update()

			assert.equal(1, team.teammodule.updates)
			assert.equal(0, linesWith(runtime, "Warning"))
		end)

		it("skips an ally module with a warning", function()
			local team = newObject(runtime, runtime.env.ShardAI, { allyModule, teamModule }, { id = 1, allyId = 0 })
			team:Init()

			assert.is_nil(team.allymodule)
			assert.is_not_nil(team.teammodule)
			assert.equal(1, linesWith(runtime, "Skipping the loading of allymodule module"))
		end)
	end)

	it("names the scope instead of a team on the console lines of shared modules", function()
		local world = buildWorld(runtime, modules)

		world.allies[1].allymodule:Warn("ally line")
		world.global.globalmodule:Warn("global line")
		world.teams[2].teammodule:Warn("team line")

		assert.equal(1, linesWith(runtime, "ally 1 ShardAlly allymodule module Warning: ally line"))
		assert.equal(1, linesWith(runtime, "global ShardGlobal globalmodule module Warning: global line"))
		assert.equal(1, linesWith(runtime, "2 Shard teammodule module Warning: team line"))
	end)
end)

describe("behaviour.lua", function()
	it("leaves the default internal name of modules alone", function()
		local runtime = loadRuntime({ "behaviour" })

		assert.equal("error", runtime.env.Module:internalName())
	end)

	it("lets a module without internalName() be skipped once it is loaded", function()
		local runtime = loadRuntime({ "behaviour" })
		local noName = runtime.env.class(runtime.env.Module)
		function noName:Name()
			return "noname module"
		end
		function noName:Scope()
			return "team"
		end
		local team = newObject(runtime, runtime.env.ShardAI, { noName }, { id = 1, allyId = 0 })
		team:Init()

		assert.same({}, team.modules)
		assert.equal(1, linesWith(runtime, "The module with the name noname module has no internal name!"))
	end)
end)

describe("ShardAI targeted events", function()
	local runtime ---@type table

	before_each(function()
		runtime = loadRuntime()
	end)

	-- a team module class whose methods `events` record their calls in `calls`
	local function listening(internalName, events, calls, base)
		local class = runtime.env.class(base or runtime.env.Module)
		function class:Name()
			return internalName
		end
		function class:internalName()
			return internalName
		end
		function class:Scope()
			return "team"
		end
		for _, event in ipairs(events) do
			class[event] = function()
				calls[#calls + 1] = internalName .. " " .. event
			end
		end
		return class
	end

	local function team(modules)
		local ai = newObject(runtime, runtime.env.ShardAI, modules, { id = 1, allyId = 0 })
		ai:Init()
		return ai
	end

	local function names(list)
		local result = {}
		for i, m in ipairs(list) do
			result[i] = m:internalName()
		end
		return result
	end

	-- a unit that is ours, as AIBase:UnitBuilt asks
	local function ownUnit()
		return {
			IsMine = function()
				return true
			end,
		}
	end

	it("hands an event only to the modules that redefine it, in the order of modules.lua", function()
		local calls = {}
		local ai = team({
			listening("dead1", { "UnitDead" }, calls),
			listening("idle", { "UnitIdle" }, calls),
			listening("dead2", { "UnitDead" }, calls),
		})

		ai:UnitDead({})

		assert.same({ "dead1 UnitDead", "dead2 UnitDead" }, calls)
		assert.same({ "dead1", "dead2" }, names(ai.handlers.UnitDead))
		assert.same({}, ai.handlers.UnitMoveFailed)
		assert.is_false(ai:WantsEvent("UnitMoveFailed"))
		assert.is_true(ai:WantsEvent("UnitIdle"))
	end)

	it("hands UnitBuilt to a module that redefines only MyUnitBuilt", function()
		local calls = {}
		local ai = team({ listening("mine", { "MyUnitBuilt" }, calls), listening("other", { "UnitIdle" }, calls) })

		ai:UnitBuilt(ownUnit())

		assert.same({ "mine MyUnitBuilt" }, calls)
		assert.same({ "mine" }, names(ai.handlers.UnitBuilt))
	end)

	it("hands UnitGiven to the modules that want UnitCreated or UnitBuilt, and to no other", function()
		local calls = {}
		local ai = team({
			listening("created", { "UnitCreated" }, calls),
			listening("built", { "UnitBuilt" }, calls),
			listening("enemy", { "EnemyUnitBuilt" }, calls),
			listening("idle", { "UnitIdle" }, calls),
		})

		ai:UnitGiven(ownUnit())

		assert.same({ "created", "built", "enemy" }, names(ai.handlers.UnitGiven))
		assert.same({ "created UnitCreated", "built UnitBuilt" }, calls)
	end)

	it("counts a method inherited from an intermediate class and one set in Init", function()
		local calls = {}
		local ModA = listening("moda", { "UnitDead" }, calls)
		local ModB = runtime.env.class(ModA)
		function ModB:internalName()
			return "modb"
		end
		local ModC = listening("modc", {}, calls)
		function ModC:Init()
			self.UnitDead = function()
				calls[#calls + 1] = "modc UnitDead"
			end
		end
		local ai = team({ ModB, ModC })

		ai:UnitDead({})

		assert.same({ "moda UnitDead", "modc UnitDead" }, calls)
	end)

	it("updates the lists when a module is added after Init", function()
		local calls = {}
		local ai = team({ listening("first", { "UnitIdle" }, calls) })
		local Late = listening("late", { "UnitDead" }, calls)

		assert.is_false(ai:WantsEvent("UnitDead"))
		ai:AddModule(Late())
		ai:UnitDead({})

		assert.same({ "late UnitDead" }, calls)
	end)

	it("allocates nothing to hand an event", function()
		local count = 0
		local Counter = listening("counter", {}, {})
		function Counter:UnitDead()
			count = count + 1
		end
		local ai = team({ Counter, listening("idle", { "UnitIdle" }, {}) })
		local unit = {}
		ai:UnitDead(unit)

		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, 1000 do
			ai:UnitDead(unit)
		end
		local after = collectgarbage("count")
		collectgarbage("restart")

		assert.equal(before, after)
		assert.equal(1001, count)
	end)
end)
