---@diagnostic disable: undefined-field, need-check-nil, inject-field, param-type-mismatch, redundant-parameter
---@diagnostic disable: missing-return, missing-return-value, missing-fields, call-non-callable, undefined-global

local newVFS = require("spec/support/fake_vfs")

local LOADER_PATH = "luarules/gadgets/ShardAILoader.lua"
local CODEC_PATH = "luarules/gadgets/ai/shard_runtime/ordercodec.lua"
local FIXTURE_PATHS = {
	["luarules/gadgets/ai/SpecAI/"] = "spec/fixtures/shard_ai/",
	["luarules/gadgets/ai/BrokenAI/"] = "spec/fixtures/shard_ai_broken/",
	["luarules/gadgets/ai/SchedAI/"] = "spec/fixtures/shard_ai_scheduled/",
	["luarules/gadgets/ai/SchedAI/specmodules.lua"] = "spec/fixtures/shard_ai/specmodules.lua",
	["luarules/gadgets/ai/SchedAI/behaviourfactory.lua"] = "spec/fixtures/shard_ai/behaviourfactory.lua",
	["luarules/gadgets/ai/BehavAI/"] = "spec/fixtures/shard_ai_behaviours/",
	["luarules/gadgets/ai/BehavAI/modules.lua"] = "spec/fixtures/shard_ai_scheduled/modules.lua",
	["luarules/gadgets/ai/BehavAI/specmodules.lua"] = "spec/fixtures/shard_ai/specmodules.lua",
	["luarules/gadgets/ai/BehavAI/behaviourfactory.lua"] = "spec/fixtures/shard_ai/behaviourfactory.lua",
	["luarules/gadgets/ai/PercAI/"] = "spec/fixtures/shard_ai/",
	["luarules/gadgets/ai/PercAI/modules.lua"] = "spec/fixtures/shard_ai_perception/modules.lua",
}

local CMD = { STOP = 0, MOVE = 10, OPT_META = 4, OPT_RIGHT = 16, OPT_SHIFT = 32, OPT_CTRL = 64, OPT_ALT = 128 }
local GAIA_TEAM = 4

-- Teams 0 and 1 are SpecAI in ally team 0, team 2 is SpecAI in ally team 1, team 3 is a human in ally
-- team 1, team 4 is Gaia. `hosts` is the aiHostPlayer team rules param; this client is player `me`.
local function defaultWorld()
	return {
		me = 0,
		frame = 0,
		hosts = { [0] = 0, [1] = 0, [2] = 0 },
		teams = {
			[0] = { allyId = 0, luaAI = "SpecAI" },
			[1] = { allyId = 0, luaAI = "SpecAI" },
			[2] = { allyId = 1, luaAI = "SpecAI" },
			[3] = { allyId = 1 },
			[GAIA_TEAM] = { allyId = 2 },
		},
		units = {},
		-- three SpecAI teams: above the loader's limit per AI type, which the specs of the limit restore with nil
		maxInstancesPerAIType = 3,
		-- the switch of timers.lua: true or false replace it, "code" keeps the file's value
		timers = false,
	}
end

local function fileExists(path)
	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	end
	return false
end

-- the spec AI types live under spec/fixtures, the rest of the runtime where the engine finds it; the longest
-- prefix wins
local function realPath(path)
	local found, foundPath = nil, nil
	for aiPath, fixturePath in pairs(FIXTURE_PATHS) do
		if string.sub(path, 1, #aiPath) == aiPath and (found == nil or #aiPath > #found) then
			found = aiPath
			foundPath = fixturePath .. string.sub(path, #aiPath + 1)
		end
	end
	return foundPath or path
end

-- Loads ShardAILoader.lua as unsynced code over a fake engine; the gadget table is its environment.
local function loadLoader(world)
	world = world or defaultWorld()
	local loader = { world = world, echoes = {}, sent = {}, syncActions = {} }
	local env = setmetatable({ CMD = CMD, SpecLog = {}, SpecHooks = {} }, { __index = _G })
	env.gadget = env
	local teamIDs = {}
	for teamID in pairs(world.teams) do
		teamIDs[#teamIDs + 1] = teamID
	end
	table.sort(teamIDs)

	local vfs = newVFS(env)
	local include = vfs.Include
	vfs.Include = function(path, includeEnv)
		local result = include(realPath(path), includeEnv)
		if path == "luarules/gadgets/ai/shard_runtime/loader/types.lua" then
			local setup = result.Setup
			result.Setup = function(context)
				context.maxInstancesPerAIType = world.maxInstancesPerAIType
				return setup(context)
			end
		end
		if path == "luarules/gadgets/ai/shard_runtime/loader/timers.lua" and world.timers ~= "code" then
			result.SetEnabled(world.timers == true)
		end
		return result
	end
	vfs.FileExists = function(path)
		return fileExists(realPath(path))
	end
	env.VFS = vfs
	world.config = world.config or {}
	world.countCalls = 0
	-- the clock of Spring.GetTimerMicros, in microseconds; the specs move it
	world.micros = 0
	world.timerReads = 0
	-- collectgarbage("count") and gcinfo() read world.heap when the spec sets it, in KB; then a full collection
	-- only goes to SpecLog and leaves world.heapAfterCollect
	env.collectgarbage = function(option, ...)
		if option == "count" and world.heap ~= nil then
			world.countCalls = world.countCalls + 1
			return world.heap
		end
		if option == "collect" and world.heap ~= nil then
			env.SpecLog[#env.SpecLog + 1] = { "collectgarbage", world.heap }
			world.heap = world.heapAfterCollect or world.heap
			return 0
		end
		return collectgarbage(option, ...)
	end
	env.gcinfo = function()
		if world.heap ~= nil then
			return world.heap
		end
		return gcinfo()
	end
	env.Game = { maxUnits = 32000, gameShortName = "BAR", mapName = "Spec Map" }
	env.WeaponDefs = { [1] = { name = "specweapon" } }
	env.UnitDefs = { [1] = { name = "specunit" }, [2] = { name = "otherunit" } }
	env.Script = { LuaUI = setmetatable({}, {
		__call = function()
			return false
		end,
	}) }
	env.gadgetHandler = {
		IsSyncedCode = function()
			return false
		end,
		AddSyncAction = function(_, name, action)
			loader.syncActions[name] = action
		end,
		RemoveSyncAction = function(_, name)
			loader.syncActions[name] = nil
		end,
	}
	env.Spring = {
		Echo = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			loader.echoes[#loader.echoes + 1] = table.concat(parts, " ")
		end,
		GetMyPlayerID = function()
			return world.me
		end,
		GetTimerMicros = function()
			world.timerReads = world.timerReads + 1
			return world.micros
		end,
		DiffTimers = function(endTimer, startTimer, returnMs, fromMicroSecs)
			assert(returnMs == true and fromMicroSecs == true)
			return (endTimer - startTimer) / 1000
		end,
		GetConfigInt = function(name, default)
			return world.config[name] or default
		end,
		GetTeamRulesParam = function(teamID, name)
			assert(name == "aiHostPlayer")
			return world.hosts[teamID]
		end,
		GetTeamList = function()
			return teamIDs
		end,
		GetTeamLuaAI = function(teamID)
			return world.teams[teamID].luaAI or ""
		end,
		GetTeamInfo = function(teamID)
			return teamID, 0, false, world.teams[teamID].luaAI ~= nil, "arm", world.teams[teamID].allyId
		end,
		AreTeamsAllied = function(a, b)
			if a == world.failAllied then
				error("allied failure")
			end
			return world.teams[a].allyId == world.teams[b].allyId
		end,
		GetTeamStartPosition = function()
			return 100, 0, 200
		end,
		GetGaiaTeamID = function()
			return GAIA_TEAM
		end,
		GetGameFrame = function()
			return world.frame
		end,
		SendLuaRulesMsg = function(message)
			loader.sent[#loader.sent + 1] = message
		end,
		GetAllUnits = function()
			local list = {}
			for unitID in pairs(world.units) do
				list[#list + 1] = unitID
			end
			table.sort(list)
			return list
		end,
		GetUnitDefID = function(unitID)
			local unit = world.units[unitID]
			return unit and (unit.defID or 1)
		end,
		ValidUnitID = function(unitID)
			return world.units[unitID] ~= nil
		end,
		GetUnitTeam = function(unitID)
			return world.units[unitID] and world.units[unitID].team
		end,
		GetUnitAllyTeam = function(unitID)
			return world.teams[world.units[unitID].team].allyId
		end,
		GetUnitHealth = function()
			return 100, 100, 0, 0, 1
		end,
		-- world.losStates[unitID][allyTeamID], the raw bits: 1 in LOS, 2 on radar
		GetUnitLosState = function(unitID, allyTeamID)
			local states = world.losStates and world.losStates[unitID]
			return states and states[allyTeamID] or 0
		end,
		GetAllFeatures = function()
			return {}
		end,
	}

	local chunk = assert(loadfile(LOADER_PATH))
	setfenv(chunk, env)
	chunk()
	loader.env = env
	loader.gadget = env
	loader.log = env.SpecLog
	loader.hooks = env.SpecHooks
	loader.codec = vfs.Include(CODEC_PATH)
	return loader
end

-- Initialize and GameStart, as the engine calls them, with the units already in the world; `hooks`
-- go to SpecHooks before anything loads.
local function started(world, hooks)
	local loader = loadLoader(world)
	for name, hook in pairs(hooks or {}) do
		loader.hooks[name] = hook
	end
	loader.gadget:Initialize()
	loader.gadget:GameStart()
	return loader
end

local function addUnit(loader, unitID, teamID)
	loader.world.units[unitID] = { team = teamID }
	loader.gadget:UnitCreated(unitID, 1, teamID)
end

-- the log entries of an event, as { internalName, owner object } pairs
local function heard(loader, event)
	local list = {}
	for _, entry in ipairs(loader.log) do
		if entry[1] == event then
			list[#list + 1] = { module = entry[2], owner = entry[3], args = { select(4, unpack(entry)) } }
		end
	end
	return list
end

local function countBy(list, key)
	local counts = {}
	for _, entry in ipairs(list) do
		counts[entry[key]] = (counts[entry[key]] or 0) + 1
	end
	return counts
end

local function echoesWith(loader, text)
	local count = 0
	for _, line in ipairs(loader.echoes) do
		if string.find(line, text, 1, true) then
			count = count + 1
		end
	end
	return count
end

-- the team and orders of a sent message, as { unitID, cmdID } pairs
local function decode(loader, message)
	local codec = loader.codec
	local _, teamID, _, frame, count, position = codec.UnpackHeader(message)
	local orders = {}
	for i = 1, count do
		local unitID, cmdID, _, _, _, nextPosition = codec.UnpackOrder(message, position)
		orders[i] = { unitID, cmdID }
		position = nextPosition
	end
	return teamID, frame, orders
end

local function objects(loader)
	local Shard = loader.env.Shard
	return {
		global = Shard.globals[1],
		ally0 = Shard.alliesByAllyID[0][1],
		ally1 = Shard.alliesByAllyID[1][1],
		team0 = Shard.AIsByTeamID[0],
		team1 = Shard.AIsByTeamID[1],
		team2 = Shard.AIsByTeamID[2],
	}
end

describe("ShardAILoader unsynced side", function()
	it("leaves no function of the loader in the environment of an AI type, nor in _G", function()
		local loader = started()
		local env = loader.env
		local aiEnv = env.Shard.types.SpecAI.env
		local names = {
			-- the gadget methods of before, now functions of loader/types.lua and loader/lifecycle.lua
			"NewAPI",
			"LoadAIType",
			"GetAlly",
			"SetupAI",
			"AddAI",
			"StartAIs",
			"CatchUp",
			"HashGameID",
			"LoadRuntime",
			"StopAI",
			"ReportError",
			"MemStats",
			"UnitRegistry",
			"Delivery",
			"Types",
			"Lifecycle",
			"LoadAI",
			"Scheduler",
			"Rebuild",
		}
		for _, file in ipairs({ "memstats", "timers", "unitregistry", "delivery", "types", "lifecycle", "scheduler" }) do
			local exported = env.VFS.Include("luarules/gadgets/ai/shard_runtime/loader/" .. file .. ".lua")
			for name in pairs(exported) do
				names[#names + 1] = name
			end
		end

		for _, name in ipairs(names) do
			assert.is_nil(rawget(env, name), name .. " in the gadget environment")
			assert.is_nil(aiEnv[name], name .. " in the environment of SpecAI")
			assert.is_nil(rawget(_G, name), name .. " in _G")
		end
	end)

	it("loads nothing on a client that hosts no AI", function()
		local world = defaultWorld()
		world.me = 5
		local loader = started(world)
		loader.gadget:GameFrame(1)

		assert.is_nil(loader.env.Shard)
		assert.equal(0, #loader.log)
		assert.equal(0, #loader.sent)
		assert.equal(1, echoesWith(loader, "no AI hosted on this client"))
	end)

	it("hosts only the teams whose aiHostPlayer is this client", function()
		local world = defaultWorld()
		world.hosts[2] = 1
		local loader = started(world)

		local Shard = loader.env.Shard
		assert.equal(2, #Shard.AIs)
		assert.is_nil(Shard.AIsByTeamID[2])
		assert.is_nil(Shard.alliesByAllyID[1])
	end)

	it(
		"creates one global per AI type, one ally per ally team and type, one object per team, initialised in that order",
		function()
			local loader = started()
			local Shard = loader.env.Shard
			local o = objects(loader)

			assert.equal(1, #Shard.globals)
			assert.equal(1, #Shard.alliesByAllyID[0])
			assert.equal(1, #Shard.alliesByAllyID[1])
			assert.equal(3, #Shard.AIs)
			local order = {}
			for i, entry in ipairs(heard(loader, "Init")) do
				order[i] = entry.module
			end
			assert.same({ "specglobal", "specally", "specally", "specteam", "specteam", "specteam" }, order)
			assert.equal(o.global.specglobal, o.team0.specglobal)
			assert.equal(o.global.specglobal, o.team2.specglobal)
			assert.equal(o.ally0.specally, o.team0.specally)
			assert.equal(o.ally0.specally, o.team1.specally)
			assert.equal(o.ally1.specally, o.team2.specally)
			assert.are_not.equal(o.team0.specteam, o.team1.specteam)
			assert.same({ 100, 0, 200 }, o.team0.startPos)
		end
	)

	it("hands a unit event once to every module", function()
		local loader = started()
		loader.world.units[100] = { team = 0 }

		loader.gadget:UnitFinished(100, 1, 0)

		local events = heard(loader, "UnitBuilt")
		assert.equal(6, #events)
		local o = objects(loader)
		local counts = countBy(events, "owner")
		for _, object in pairs(o) do
			assert.equal(1, counts[object])
		end
		assert.equal(100, events[1].args[1]:ID())
	end)

	it("hands UnitCreated to the shared objects and, among the AIs, only to the owner", function()
		local loader = started()

		addUnit(loader, 100, 0)

		local o = objects(loader)
		local counts = countBy(heard(loader, "UnitCreated"), "owner")
		assert.same({ [o.global] = 1, [o.ally0] = 1, [o.ally1] = 1, [o.team0] = 1 }, counts)
	end)

	it("hands a sight event to the ally that sees the unit, not to the other, and to every AI", function()
		local loader = started()
		loader.world.units[300] = { team = 3 }

		loader.gadget:UnitEnteredLos(300, 3, 0, 1)

		local o = objects(loader)
		local counts = countBy(heard(loader, "UnitEnteredLos"), "owner")
		assert.same({ [o.ally0] = 1, [o.team0] = 1, [o.team1] = 1, [o.team2] = 1 }, counts)
	end)

	it("keeps the unit tables of each AI through creation, transfer and death", function()
		local loader = started()
		local o = objects(loader)
		addUnit(loader, 100, 0)
		addUnit(loader, 101, 1)
		addUnit(loader, 200, 2)
		addUnit(loader, 400, GAIA_TEAM)

		assert.same({ [100] = true }, o.team0.ownUnitIds)
		assert.same({ [101] = true }, o.team0.alliedUnitIds)
		assert.same({ [100] = true, [101] = true }, o.team0.friendlyUnitIds)
		assert.same({ [200] = true }, o.team0.enemyUnitIds)
		assert.same({ [400] = true }, o.team0.neutralUnitIds)
		assert.same({ [100] = true, [101] = true }, o.team2.enemyUnitIds)

		loader.world.units[100].team = 2
		loader.gadget:UnitTaken(100, 1, 0, 2)
		loader.gadget:UnitGiven(100, 1, 2, 0)
		loader.world.units[200] = nil
		loader.gadget:UnitDestroyed(200, 1, 2)

		assert.same({}, o.team0.ownUnitIds)
		assert.same({ [100] = true }, o.team0.enemyUnitIds)
		assert.same({ [100] = true }, o.team2.ownUnitIds)
		assert.same({ [101] = true }, o.team2.enemyUnitIds)
		assert.is_not_nil(loader.env.Shard.unitsByID[200])
		assert.equal(12, #heard(loader, "UnitDead")) -- UnitTaken and UnitDestroyed, to all six objects
	end)

	it("sends an order given in Update as a message in the same GameFrame", function()
		local loader = started()
		loader.world.units[100] = { team = 0 }
		loader.hooks.Update = function(module)
			if module.ai.id == 0 then
				module.game:GiveOrder(100, CMD.MOVE, { 1, 2, 3 }, 0, "1-1")
			end
		end

		loader.world.frame = 30
		loader.gadget:GameFrame(30)

		assert.equal(1, #loader.sent)
		local teamID, frame, orders = decode(loader, loader.sent[1])
		assert.equal(0, teamID)
		assert.equal(30, frame)
		assert.same({ { 100, CMD.MOVE } }, orders)
	end)

	it("queues a ShardUnit order in the outbox of the AI that owns the unit", function()
		local loader = started()
		local Shard = loader.env.Shard
		addUnit(loader, 200, 2)
		addUnit(loader, 300, 3)
		Shard.AIsByTeamID[0]:Prepare() -- the global game is team 0's

		Shard:shardify_unit(200):Move({ x = 1, y = 2, z = 3 })
		assert.is_false(Shard:shardify_unit(300):SyncOrder(300, CMD.STOP, nil, 0))
		loader.gadget:GameFrame(1)

		assert.equal(1, #loader.sent)
		local teamID, _, orders = decode(loader, loader.sent[1])
		assert.equal(2, teamID)
		assert.same({ { 200, CMD.MOVE } }, orders)
		assert.equal(1, echoesWith(loader, "unit 300 is not of an AI hosted here"))
	end)

	it("writes an error in Update once, runs the other objects, and calls the object again", function()
		local loader = started()
		local o = objects(loader)
		local calls = 0
		loader.hooks.Update = function(module)
			if module.ai == o.team1 then
				calls = calls + 1
				error("spec failure")
			end
		end

		loader.world.frame = 10
		loader.gadget:GameFrame(10)
		loader.world.frame = 11
		loader.gadget:GameFrame(11)

		assert.equal(2, calls)
		assert.equal(1, echoesWith(loader, "[AI Loader] error in SpecAI team 1, Update"))
		assert.equal(1, echoesWith(loader, "spec failure"))
		local counts = countBy(heard(loader, "Update"), "owner")
		assert.equal(2, counts[o.team0])
		assert.equal(2, counts[o.team2])
		assert.equal(2, counts[o.global])

		loader.world.frame = 910
		loader.gadget:GameFrame(910)
		assert.equal(1, echoesWith(loader, "[AI Loader] error in SpecAI team 1, Update"))
	end)

	describe("error list", function()
		local function failing(messages)
			return {
				Update = function(module)
					local message = module.ai.id ~= nil and messages[module.ai.id]
					local text = message and message(module.ai.specFrame())
					if text then
						error(text)
					end
				end,
			}
		end

		local function run(loader, from, to)
			for n = from, to do
				loader.world.frame = n
				loader.gadget:GameFrame(n)
			end
		end

		local function erroring(messages)
			local loader = started(nil, failing(messages))
			for _, thisAI in ipairs(loader.env.Shard.AIs) do
				thisAI.specFrame = function()
					return loader.world.frame
				end
			end
			return loader
		end

		it("writes two different errors of one call-in a few frames apart, each with its traceback", function()
			local loader = erroring({
				[1] = function(frame)
					return frame < 12 and "first failure" or "second failure"
				end,
			})

			run(loader, 10, 14)

			assert.equal(1, echoesWith(loader, "first failure\nstack traceback"))
			assert.equal(1, echoesWith(loader, "second failure\nstack traceback"))
		end)

		it("writes an error that comes back 50 times once and lists it with its count once", function()
			local loader = erroring({
				[1] = function()
					return "same failure"
				end,
			})

			run(loader, 1, 50)
			loader.gadget:GameOver({ 0 })
			loader.gadget:Shutdown()

			assert.equal(1, echoesWith(loader, "same failure\nstack traceback"))
			assert.equal(1, echoesWith(loader, "[AI Loader] errors in this game, 1 different:"))
			assert.equal(1, echoesWith(loader, "[AI Loader] SpecAI team 1, Update: 50 times, frames 1 to 50: "))
		end)

		it("lists the errors in the order they first happened", function()
			local loader = erroring({
				[2] = function(frame)
					return frame >= 5 and "late failure" or nil
				end,
				[0] = function()
					return "early failure"
				end,
			})

			run(loader, 1, 6)
			loader.gadget:Shutdown()

			local listed = {}
			for _, line in ipairs(loader.echoes) do
				local label = string.match(line, "^%[AI Loader%] (SpecAI team %d), Update: %d+ times")
				if label then
					listed[#listed + 1] = label
				end
			end
			assert.same({ "SpecAI team 0", "SpecAI team 2" }, listed)
			assert.equal(1, echoesWith(loader, "SpecAI team 2, Update: 2 times, frames 5 to 6"))
		end)

		it("lists the errors at GameOver, before Shutdown", function()
			local loader = erroring({
				[1] = function()
					return "over failure"
				end,
			})

			run(loader, 1, 2)
			loader.gadget:GameOver({ 0 })

			assert.equal(1, echoesWith(loader, "[AI Loader] SpecAI team 1, Update: 2 times, frames 1 to 2: "))
		end)

		it("lists nothing when there was no error", function()
			local loader = started()

			run(loader, 1, 3)
			loader.gadget:GameOver({ 0 })
			loader.gadget:Shutdown()

			assert.equal(0, echoesWith(loader, "errors in this game"))
		end)
	end)

	it("takes over a team whose host moved here, with only the new objects hearing the existing units", function()
		local world = defaultWorld()
		world.hosts[2] = 1
		local loader = started(world)
		loader.world.frame = 100
		loader.gadget:GameFrame(100)
		loader.world.units[300] = { team = 3 }
		loader.log[#loader.log + 1] = { "mark" }
		local mark = #loader.log

		loader.syncActions.shard_host("shard_host", 2, 0)

		local o = objects(loader)
		assert.is_not_nil(o.team2)
		local created = {}
		for i = mark + 1, #loader.log do
			local entry = loader.log[i]
			if entry[1] == "UnitBuilt" then
				created[#created + 1] = entry[3]
			end
		end
		assert.same({ o.ally1, o.team2 }, created)
		assert.equal(o.global.specglobal, o.team2.specglobal)
	end)

	it(
		"writes the unit tables of the AI taken over during the catch-up, not those of the AIs already running",
		function()
			local world = defaultWorld()
			world.hosts[2] = 1
			local loader = started(world)
			addUnit(loader, 100, 0)
			addUnit(loader, 300, 3)
			local team0 = loader.env.Shard.AIsByTeamID[0]
			local writes = 0
			local function counting()
				return setmetatable({}, {
					__newindex = function(t, key, value)
						writes = writes + 1
						rawset(t, key, value)
					end,
				})
			end
			for _, name in ipairs({ "ownUnitIds", "friendlyUnitIds", "alliedUnitIds", "enemyUnitIds", "neutralUnitIds" }) do
				team0[name] = counting()
			end
			loader.world.frame = 100

			loader.syncActions.shard_host("shard_host", 2, 0)

			local team2 = loader.env.Shard.AIsByTeamID[2]
			assert.equal(0, writes)
			assert.same({ [100] = true }, team2.enemyUnitIds)
			assert.same({ [300] = true }, team2.alliedUnitIds)
		end
	)

	it("stops a team whose host moved away and drops its queued orders", function()
		local loader = started()
		local o = objects(loader)
		loader.world.units[100] = { team = 0 }
		o.team0.outbox:Queue(100, CMD.STOP, nil, 0)

		loader.syncActions.shard_host("shard_host", 0, 1)
		loader.gadget:GameFrame(1)
		loader.gadget:UnitFinished(100, 1, 0)

		local Shard = loader.env.Shard
		assert.is_nil(Shard.AIsByTeamID[0])
		assert.equal(2, #Shard.AIs)
		assert.equal(1, #o.ally0.AIs)
		assert.equal(0, o.team0.outbox.last)
		assert.equal(0, #loader.sent)
		assert.is_nil(countBy(heard(loader, "Update"), "owner")[o.team0])
		assert.is_nil(countBy(heard(loader, "UnitBuilt"), "owner")[o.team0])
	end)

	it("does not call an object none of whose modules wants the event, not even Prepare", function()
		local loader = started()
		local o = objects(loader)
		o.ally0.specally.UnitIdle = loader.env.AIBase.UnitIdle
		o.ally0:BuildHandlers()
		local prepared = 0
		local prepare = o.ally0.Prepare
		o.ally0.Prepare = function(self)
			prepared = prepared + 1
			return prepare(self)
		end
		loader.world.units[100] = { team = 0 }

		loader.gadget:UnitIdle(100, 1, 0)

		assert.equal(0, prepared)
		local counts = countBy(heard(loader, "UnitIdle"), "owner")
		assert.is_nil(counts[o.ally0])
		assert.equal(1, counts[o.ally1])
		assert.equal(1, counts[o.team0])
	end)

	it("hands a unit event to the global object, then the ally objects, then the AIs", function()
		local loader = started()
		local o = objects(loader)
		loader.world.units[100] = { team = 0 }

		loader.gadget:UnitFinished(100, 1, 0)

		local scopes = {}
		for _, entry in ipairs(heard(loader, "UnitBuilt")) do
			scopes[#scopes + 1] = entry.owner:Scope()
		end
		assert.same({ "global", "ally", "ally", "team", "team", "team" }, scopes)
		assert.equal(o.team0, heard(loader, "UnitBuilt")[4].owner)
	end)

	it("allocates nothing to hand a unit event to every object", function()
		local loader = started()
		loader.world.units[100] = { team = 0 }
		loader.env.SpecQuiet = true
		loader.gadget:UnitIdle(100, 1, 0)

		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, 500 do
			loader.gadget:UnitIdle(100, 1, 0)
		end
		local after = collectgarbage("count")
		collectgarbage("restart")

		assert.equal(before, after)
	end)

	it("hands no event for a unit ID that is neither valid nor cached, but an attacker may be missing", function()
		local loader = started()
		loader.world.units[100] = { team = 0 }

		loader.gadget:UnitDamaged(4242, 1, 0, 10, 0, 1, 1, 100, 1, 0)
		loader.gadget:UnitIdle(4242, 1, 0)
		loader.gadget:UnitFinished(4242, 1, 0)
		loader.gadget:UnitDestroyed(4242, 1, 0)
		loader.gadget:UnitDamaged(100, 1, 0, 10, 0, 1, 1, 4242, 1, 0)

		assert.equal(0, #heard(loader, "UnitIdle"))
		assert.equal(0, #heard(loader, "UnitBuilt"))
		assert.equal(0, #heard(loader, "UnitDead"))
		local damaged = heard(loader, "UnitDamaged")
		assert.equal(6, #damaged)
		assert.equal(100, damaged[1].args[1]:ID())
		assert.is_nil(damaged[1].args[2])
		assert.is_nil(loader.env.Shard.unitsByID[4242])
	end)

	it("ends the game only for the objects that have modules", function()
		local loader = started()
		local o = objects(loader)
		o.ally1.modules = {}
		o.ally1:BuildHandlers() -- the event lists, as Init and AddModule build them
		local ended = false
		o.ally1.GameEnd = function()
			ended = true
		end

		loader.gadget:GameOver({ 0 })

		assert.is_false(ended)
		assert.equal(1, countBy(heard(loader, "GameEnd"), "owner")[o.ally0])
	end)

	it("ends the game for every module at GameOver", function()
		local loader = started()

		loader.gadget:GameOver({ 0 })

		local o = objects(loader)
		local counts = countBy(heard(loader, "GameEnd"), "owner")
		for _, object in pairs(o) do
			assert.equal(1, counts[object])
		end
	end)

	it("hashes the GameID into the same seed every time, below 2^24 at every step", function()
		local loader = started()
		local gameID = string.rep("\255", 16) .. "\0\127\200abc"
		-- HashGameID is a function of loader/types.lua, not of the gadget
		local HashGameID = loader.env.VFS.Include("luarules/gadgets/ai/shard_runtime/loader/types.lua").HashGameID

		local reference = 0
		for i = 1, #gameID do
			local step = reference * 31 + string.byte(gameID, i)
			assert.is_true(step < 2 ^ 24)
			reference = step % 65521
		end

		assert.equal(reference, HashGameID(gameID))
		assert.equal(reference, HashGameID(gameID))
		loader.gadget:GameID(gameID)
		local o = objects(loader)
		assert.equal(reference, loader.env.Shard.randomseed)
		assert.equal((reference * 31 + 1) % 65521, o.team0.randomseed)
		assert.are_not.equal(o.team0.randomseed, o.team1.randomseed)
		assert.is_true(reference * 31 + 255 < 2 ^ 24)
	end)

	describe("with the turns of the modules", function()
		-- teams 0, 1 and 2 are SchedAI, whose class lists the turns: specteam, specally, specglobal, specteamb
		local function scheduledWorld()
			local world = defaultWorld()
			for teamID = 0, 2 do
				world.teams[teamID].luaAI = "SchedAI"
			end
			return world
		end

		local function label(entry)
			local owner = entry.owner
			local scope = owner:Scope()
			if scope == "team" then
				return entry.module .. "@t" .. owner.id
			elseif scope == "ally" then
				return entry.module .. "@a" .. owner.allyId
			end
			return entry.module .. "@" .. owner.fullname
		end

		-- runs the frames; the Updates of each frame as labels, in the order they came
		local function updatesByFrame(loader, from, to)
			local byFrame = {}
			for n = from, to do
				local mark = #loader.log
				loader.world.frame = n
				loader.gadget:GameFrame(n)
				local labels = {}
				for i = mark + 1, #loader.log do
					local entry = loader.log[i]
					if entry[1] == "Update" then
						labels[#labels + 1] = label({ module = entry[2], owner = entry[3] })
					end
				end
				byFrame[#byFrame + 1] = labels
			end
			return byFrame
		end

		-- the Updates of the listed modules, frame after frame
		local function turnsOf(byFrame)
			local turns = {}
			for _, labels in ipairs(byFrame) do
				for _, text in ipairs(labels) do
					if not string.find(text, "specteamc", 1, true) then
						turns[#turns + 1] = text
					end
				end
			end
			return turns
		end

		local ROUND = {
			"specteam@t0",
			"specteam@t1",
			"specteam@t2",
			"specally@a0",
			"specally@a1",
			"specglobal@SchedAI",
			"specteamb@t0",
			"specteamb@t1",
			"specteamb@t2",
		}

		it("gives Update to every module every frame when the class lists no turns", function()
			local loader = started()

			local byFrame = updatesByFrame(loader, 1, 3)

			for _, labels in ipairs(byFrame) do
				table.sort(labels)
				assert.same({
					"specally@a0",
					"specally@a1",
					"specglobal@SpecAI",
					"specteam@t0",
					"specteam@t1",
					"specteam@t2",
				}, labels)
			end
			assert.is_nil(loader.env.Shard.AIsByTeamID[0].scheduler)
		end)

		it("runs one listed module a frame, in the order of the list and round after round", function()
			local loader = started(scheduledWorld())

			local byFrame = updatesByFrame(loader, 1, 18)

			for _, labels in ipairs(byFrame) do
				local unlisted = 0
				for _, text in ipairs(labels) do
					if string.find(text, "specteamc", 1, true) then
						unlisted = unlisted + 1
					end
				end
				assert.equal(3, unlisted)
				assert.equal(4, #labels)
			end
			local expected = {}
			for i = 1, 18 do
				expected[i] = ROUND[(i - 1) % #ROUND + 1]
			end
			assert.same(expected, turnsOf(byFrame))
		end)

		it("does not call every frame an object whose modules all run in turns, not even Prepare", function()
			local loader = started(scheduledWorld())
			local o = objects(loader)
			local prepared = 0
			local prepare = o.ally0.Prepare
			o.ally0.Prepare = function(self)
				prepared = prepared + 1
				return prepare(self)
			end

			updatesByFrame(loader, 1, 3)

			assert.equal(0, prepared)
			assert.same({}, o.ally0.handlers.Update)
			assert.equal(1, #o.team0.handlers.Update)
			assert.equal(o.team0.specteamc, o.team0.handlers.Update[1])
		end)

		it("gives a shared module one turn a round for the object that holds it", function()
			local loader = started(scheduledWorld())

			local counts = {}
			for _, text in ipairs(turnsOf(updatesByFrame(loader, 1, 3 * #ROUND))) do
				counts[text] = (counts[text] or 0) + 1
			end

			assert.equal(3, counts["specally@a0"])
			assert.equal(3, counts["specally@a1"])
			assert.equal(3, counts["specglobal@SchedAI"])
			assert.equal(3, counts["specteam@t1"])
		end)

		it("takes a stopped AI out of the rotation without skipping or repeating the turns of the others", function()
			local loader = started(scheduledWorld())
			local before = turnsOf(updatesByFrame(loader, 1, 1))

			-- team 1 was the next turn
			loader.syncActions.shard_host("shard_host", 1, 1)
			local after = turnsOf(updatesByFrame(loader, 2, 15))

			assert.same({ "specteam@t0" }, before)
			assert.same({
				"specteam@t2",
				"specally@a0",
				"specally@a1",
				"specglobal@SchedAI",
				"specteamb@t0",
				"specteamb@t2",
				"specteam@t0",
				"specteam@t2",
				"specally@a0",
				"specally@a1",
				"specglobal@SchedAI",
				"specteamb@t0",
				"specteamb@t2",
				"specteam@t0",
			}, after)
		end)

		it("goes on from the same turn when an AI whose turn is not next stops", function()
			local loader = started(scheduledWorld())
			updatesByFrame(loader, 1, 4)

			loader.syncActions.shard_host("shard_host", 0, 1)
			local after = turnsOf(updatesByFrame(loader, 5, 10))

			assert.same({
				"specally@a1",
				"specglobal@SchedAI",
				"specteamb@t1",
				"specteamb@t2",
				"specteam@t1",
				"specteam@t2",
			}, after)
		end)

		it("skips a listed module no object holds, and gives it turns once AddModule adds it", function()
			local loader = loadLoader(scheduledWorld())
			loader.gadget:Initialize()
			local names = loader.env.Shard.types.SchedAI.class.MScheduler
			names[#names + 1] = "SpecLate"
			loader.gadget:GameStart()
			local env = loader.env
			local Late = env.class(env.Module)
			function Late:Name()
				return "SpecLate"
			end
			function Late:internalName()
				return "speclate"
			end
			function Late:Scope()
				return "team"
			end
			local lateFrames = {}
			function Late:Update()
				lateFrames[#lateFrames + 1] = loader.world.frame
			end

			local before = turnsOf(updatesByFrame(loader, 1, 9))
			objects(loader).team0:AddModule(Late())
			updatesByFrame(loader, 10, 28)

			assert.same(ROUND, before)
			assert.same({ 10, 20 }, lateFrames)
		end)

		it("puts an AI taken over from another host in the rotation", function()
			local world = scheduledWorld()
			world.hosts[2] = 1
			local loader = started(world)
			local before = turnsOf(updatesByFrame(loader, 1, 7))

			loader.syncActions.shard_host("shard_host", 2, 0)
			local after = turnsOf(updatesByFrame(loader, 8, 16))

			assert.same({
				"specteam@t0",
				"specteam@t1",
				"specally@a0",
				"specglobal@SchedAI",
				"specteamb@t0",
				"specteamb@t1",
				"specteam@t0",
			}, before)
			assert.same({
				"specteam@t1",
				"specteam@t2",
				"specally@a0",
				"specally@a1",
				"specglobal@SchedAI",
				"specteamb@t0",
				"specteamb@t1",
				"specteamb@t2",
				"specteam@t0",
			}, after)
		end)

		it("leaves an AI type that lists no turns as it was, next to one that lists them", function()
			local world = defaultWorld()
			world.teams[0].luaAI = "SchedAI"
			world.teams[1].luaAI = "SchedAI"
			local loader = started(world)

			local byFrame = updatesByFrame(loader, 1, 12)

			local turns = {}
			for _, labels in ipairs(byFrame) do
				local plain = {}
				for _, text in ipairs(labels) do
					if string.find(text, "SpecAI", 1, true) or string.find(text, "@a1", 1, true) then
						plain[#plain + 1] = text
					elseif string.find(text, "@t2", 1, true) then
						plain[#plain + 1] = text
					elseif not string.find(text, "specteamc", 1, true) then
						turns[#turns + 1] = text
					end
				end
				table.sort(plain)
				assert.same({ "specally@a1", "specglobal@SpecAI", "specteam@t2" }, plain)
			end
			local round = {
				"specteam@t0",
				"specteam@t1",
				"specally@a0",
				"specglobal@SchedAI",
				"specteamb@t0",
				"specteamb@t1",
			}
			assert.same(round, { unpack(turns, 1, 6) })
			assert.same(round, { unpack(turns, 7, 12) })
			assert.is_nil(loader.env.Shard.AIsByTeamID[2].scheduler)
		end)

		it("tells the module whose turn it is through the scheduler table of its object", function()
			local loader = started(scheduledWorld())
			local o = objects(loader)
			local seen = {}
			loader.hooks.Update = function(module)
				local scheduler = module.ai.scheduler
				seen[#seen + 1] = { module:Name(), scheduler.moduleUpdate, scheduler.moduleTeam }
			end

			updatesByFrame(loader, 1, 4)

			assert.equal(o.team0.scheduler, o.ally0.scheduler)
			assert.equal(o.team0.scheduler, o.global.scheduler)
			local listed = {}
			for _, entry in ipairs(seen) do
				if entry[1] ~= "SpecTeamModuleC" then
					listed[#listed + 1] = entry
				end
			end
			assert.same({
				{ "SpecTeamModule", "SpecTeamModule", 0 },
				{ "SpecTeamModule", "SpecTeamModule", 1 },
				{ "SpecTeamModule", "SpecTeamModule", 2 },
				{ "SpecAllyModule", "SpecAllyModule", nil },
			}, listed)
		end)

		it("allocates nothing to run the turns", function()
			local loader = started(scheduledWorld())
			loader.env.SpecQuiet = true
			for n = 1, 20 do
				loader.world.frame = n
				loader.gadget:GameFrame(n)
			end

			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for n = 21, 520 do
				loader.world.frame = n
				loader.gadget:GameFrame(n)
			end
			local after = collectgarbage("count")
			collectgarbage("restart")

			assert.equal(before, after)
		end)
	end)

	describe("with the turns of the behaviours", function()
		-- teams 0, 1 and 2 are SchedAI, whose class lists the behaviours SpecBehaviour and SpecBehaviourB
		local function scheduledWorld()
			local world = defaultWorld()
			for teamID = 0, 2 do
				world.teams[teamID].luaAI = "SchedAI"
			end
			return world
		end

		-- Every AI of the list gets a unit with SpecBehaviour, SpecBehaviourB and SpecBehaviourFree, and a team
		-- module, not in turns, that gives the unit Update every frame, as UnitHandler does. A behaviour's Update
		-- goes to updates as "<name>@t<team>", unless quiet.
		local function addUnits(loader, AIs)
			local env = loader.env
			local run = { updates = {}, quiet = false } ---@type { updates: string[], quiet: boolean }
			for _, thisAI in ipairs(AIs) do
				local unit = env.Shard.types[loader.world.teams[thisAI.id].luaAI].env.Unit()
				unit:SetAI(thisAI)
				unit:SetEngineRepresentation({
					ID = function()
						return 100 + thisAI.id
					end,
				})
				unit:Init()
				for _, name in ipairs({ "SpecBehaviour", "SpecBehaviourB", "SpecBehaviourFree" }) do
					local label = name .. "@t" .. thisAI.id
					local class = env.class(env.Behaviour)
					function class:Name()
						return name
					end
					function class:Update()
						if not run.quiet then
							run.updates[#run.updates + 1] = label
						end
					end
					unit:AddBehaviour(class())
				end
				local Runner = env.class(env.Module)
				function Runner:Name()
					return "SpecUnitRunner"
				end
				function Runner:internalName()
					return "specunitrunner"
				end
				function Runner:Scope()
					return "team"
				end
				function Runner:Update()
					unit:Update()
				end
				thisAI:AddModule(Runner())
			end
			return run
		end

		-- runs the frames; the behaviour Updates of each frame, those of SpecBehaviourFree apart
		local function behaviourFrames(loader, run, from, to)
			local listed, free = {}, {}
			for n = from, to do
				run.updates = {}
				loader.world.frame = n
				loader.gadget:GameFrame(n)
				local frameFree = {}
				for _, label in ipairs(run.updates) do
					if string.find(label, "Free", 1, true) then
						frameFree[#frameFree + 1] = label
					else
						listed[#listed + 1] = label
					end
				end
				table.sort(frameFree)
				free[#free + 1] = frameFree
			end
			return listed, free
		end

		local ROUND = {
			"SpecBehaviour@t0",
			"SpecBehaviour@t1",
			"SpecBehaviour@t2",
			"SpecBehaviourB@t0",
			"SpecBehaviourB@t1",
			"SpecBehaviourB@t2",
		}

		it(
			"gives a listed behaviour Update only in its turn, one turn a frame, and an unlisted one every frame",
			function()
				local loader = started(scheduledWorld())
				local o = objects(loader)
				local run = addUnits(loader, { o.team0, o.team1, o.team2 })

				local listed, free = behaviourFrames(loader, run, 1, 12)

				local expected = {}
				for i = 1, 12 do
					expected[i] = ROUND[(i - 1) % #ROUND + 1]
				end
				assert.same(expected, listed)
				for _, frameFree in ipairs(free) do
					assert.same({ "SpecBehaviourFree@t0", "SpecBehaviourFree@t1", "SpecBehaviourFree@t2" }, frameFree)
				end
			end
		)

		it("alternates two AIs, and leaves the behaviours of a type that lists none as they were", function()
			local world = defaultWorld()
			world.teams[0].luaAI = "SchedAI"
			world.teams[1].luaAI = "SchedAI"
			local loader = started(world)
			local o = objects(loader)
			local run = addUnits(loader, { o.team0, o.team1, o.team2 })

			local listed, free = behaviourFrames(loader, run, 1, 8)

			local scheduled, plain = {}, {}
			for _, label in ipairs(listed) do
				if string.find(label, "@t2", 1, true) then
					plain[#plain + 1] = label
				else
					scheduled[#scheduled + 1] = label
				end
			end
			assert.same({
				"SpecBehaviour@t0",
				"SpecBehaviour@t1",
				"SpecBehaviourB@t0",
				"SpecBehaviourB@t1",
				"SpecBehaviour@t0",
				"SpecBehaviour@t1",
				"SpecBehaviourB@t0",
				"SpecBehaviourB@t1",
			}, scheduled)
			assert.equal(16, #plain)
			assert.is_nil(o.team2.scheduler)
			assert.is_nil(o.team2.scheduledBehaviours)
			for _, frameFree in ipairs(free) do
				assert.same({ "SpecBehaviourFree@t0", "SpecBehaviourFree@t1", "SpecBehaviourFree@t2" }, frameFree)
			end
		end)

		it("says whose turn it is in behaviourTeam and behaviourUpdate, before the Update of the frame", function()
			local loader = started(scheduledWorld())
			local o = objects(loader)
			local seen = {}
			loader.hooks.Update = function(module)
				if module:Name() == "SpecTeamModuleC" and module.ai == o.team0 then
					local scheduler = module.ai.scheduler
					seen[#seen + 1] = { scheduler.behaviourUpdate, scheduler.behaviourTeam }
				end
			end

			for n = 1, 7 do
				loader.world.frame = n
				loader.gadget:GameFrame(n)
			end

			assert.same({
				{ "SpecBehaviour", 0 },
				{ "SpecBehaviour", 1 },
				{ "SpecBehaviour", 2 },
				{ "SpecBehaviourB", 0 },
				{ "SpecBehaviourB", 1 },
				{ "SpecBehaviourB", 2 },
				{ "SpecBehaviour", 0 },
			}, seen)
			assert.same({ SpecBehaviour = true, SpecBehaviourB = true }, o.team0.scheduledBehaviours)
			assert.is_nil(o.ally0.scheduledBehaviours)
		end)

		it(
			"takes a stopped AI out of the rotation of the behaviours without skipping the turns of the others",
			function()
				local loader = started(scheduledWorld())
				local o = objects(loader)
				local run = addUnits(loader, { o.team0, o.team1, o.team2 })
				local before = behaviourFrames(loader, run, 1, 1)

				loader.syncActions.shard_host("shard_host", 1, 1)
				local after = behaviourFrames(loader, run, 2, 6)

				assert.same({ "SpecBehaviour@t0" }, before)
				assert.same({
					"SpecBehaviour@t2",
					"SpecBehaviourB@t0",
					"SpecBehaviourB@t2",
					"SpecBehaviour@t0",
					"SpecBehaviour@t2",
				}, after)
			end
		)

		it(
			"runs the behaviours in turns for a class that lists only behaviours, longer than the list of modules",
			function()
				local world = defaultWorld()
				for teamID = 0, 2 do
					world.teams[teamID].luaAI = "BehavAI"
				end
				local loader = started(world)
				local o = objects(loader)
				local run = addUnits(loader, { o.team0, o.team1 })

				for n = 1, 2 do
					local mark = #loader.log
					loader.world.frame = n
					loader.gadget:GameFrame(n)
					local updates = 0
					for i = mark + 1, #loader.log do
						if loader.log[i][1] == "Update" then
							updates = updates + 1
						end
					end
					-- the global, two allies, three modules for each of three teams
					assert.equal(12, updates)
				end
				local turns = {}
				run.updates = {}
				for n = 3, 10 do
					loader.world.frame = n
					loader.gadget:GameFrame(n)
				end
				for _, label in ipairs(run.updates) do
					turns[#turns + 1] = label
				end

				-- frames 3 to 10 are the turns 3 to 10 of nine; those of team 2, which has no unit, update nothing
				assert.same({
					"SpecBehaviourFree@t0",
					"SpecBehaviourFree@t1",
					"SpecBehaviourB@t0",
					"SpecBehaviourB@t1",
					"SpecBehaviour@t0",
				}, turns)
				assert.equal(o.team0.scheduler, o.team1.scheduler)
				assert.equal(o.team0.scheduler, o.ally0.scheduler)
			end
		)

		it("allocates nothing to run the turns of the behaviours", function()
			local loader = started(scheduledWorld())
			local o = objects(loader)
			local run = addUnits(loader, { o.team0, o.team1, o.team2 })
			run.quiet = true
			loader.env.SpecQuiet = true
			for n = 1, 20 do
				loader.world.frame = n
				loader.gadget:GameFrame(n)
			end

			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for n = 21, 520 do
				loader.world.frame = n
				loader.gadget:GameFrame(n)
			end
			local after = collectgarbage("count")
			collectgarbage("restart")

			assert.equal(before, after)
		end)
	end)

	describe("with the PerceptionHandler of the runtime", function()
		local function perceptionWorld()
			local world = defaultWorld()
			for teamID = 0, 2 do
				world.teams[teamID].luaAI = "PercAI"
			end
			return world
		end

		local function perceptions(loader)
			local Shard = loader.env.Shard
			return Shard.alliesByAllyID[0][1].perceptionhandler, Shard.alliesByAllyID[1][1].perceptionhandler
		end

		-- the calls of an event to a module instance, counted
		local function counting(module, event)
			local calls = { count = 0 }
			local method = module[event]
			module[event] = function(self, ...)
				calls.count = calls.count + 1
				return method(self, ...)
			end
			return calls
		end

		it("loads one PerceptionHandler per ally team, shared by its AIs", function()
			local loader = started(perceptionWorld())
			local Shard = loader.env.Shard
			local perception0, perception1 = perceptions(loader)

			assert.is_not_nil(perception0)
			assert.is_not_nil(perception1)
			assert.are_not.equal(perception0, perception1)
			assert.equal(perception0, Shard.AIsByTeamID[0].perceptionhandler)
			assert.equal(perception0, Shard.AIsByTeamID[1].perceptionhandler)
			assert.equal(perception1, Shard.AIsByTeamID[2].perceptionhandler)
		end)

		it("hands each sight event once to the PerceptionHandler of the ally team that sees the unit", function()
			local loader = started(perceptionWorld())
			local perception0, perception1 = perceptions(loader)
			local entered = counting(perception0, "UnitEnteredLos")
			local left = counting(perception0, "UnitLeftLos")
			local radar = counting(perception0, "UnitEnteredRadar")
			local otherEntered = counting(perception1, "UnitEnteredLos")
			loader.world.units[300] = { team = 3 }

			loader.gadget:UnitEnteredRadar(300, 3, 0, 1)
			loader.gadget:UnitEnteredLos(300, 3, 0, 1)

			assert.equal(1, entered.count)
			assert.equal(1, radar.count)
			assert.equal(0, otherEntered.count)
			assert.is_true(perception0:Sees(300))
			assert.is_true(perception0:OnRadar(300))
			assert.is_false(perception1:Sees(300))

			loader.gadget:UnitLeftLos(300, 3, 0, 1)

			assert.equal(1, left.count)
			assert.is_false(perception0:Sees(300))
			assert.is_true(perception0:OnRadar(300))
		end)

		it("forgets a unit that dies in sight", function()
			local loader = started(perceptionWorld())
			local perception0 = perceptions(loader)
			addUnit(loader, 300, 3)
			loader.gadget:UnitEnteredRadar(300, 3, 0, 1)
			loader.gadget:UnitEnteredLos(300, 3, 0, 1)

			loader.gadget:UnitDestroyed(300, 1, 3)

			assert.is_false(perception0:Sees(300))
			assert.is_false(perception0:OnRadar(300))
		end)

		it("fills the tables with the units already in sight after a reload", function()
			local world = perceptionWorld()
			world.frame = 100
			world.units[200] = { team = 2 }
			world.units[300] = { team = 3 }
			world.units[100] = { team = 0 }
			world.losStates = { [200] = { [0] = 3 }, [300] = { [0] = 2 }, [100] = { [1] = 1 } }
			local loader = loadLoader(world)

			loader.gadget:Initialize()

			local perception0, perception1 = perceptions(loader)
			assert.same({ [200] = true }, perception0.los)
			assert.same({ [200] = true, [300] = true }, perception0.radar)
			assert.same({ [100] = true }, perception1.los)
			assert.same({}, perception1.radar)
		end)

		it("collects the garbage once, after the catch-up of a reload", function()
			local world = perceptionWorld()
			world.frame = 100
			world.units[200] = { team = 2 }
			world.heap = 1000
			local loader = loadLoader(world)
			local env = loader.env
			local AIsAtCollect
			local collect = env.collectgarbage
			env.collectgarbage = function(option, ...)
				if option == "collect" then
					AIsAtCollect = #env.Shard.AIs
				end
				return collect(option, ...)
			end

			loader.gadget:Initialize()

			local collects = 0
			for _, entry in ipairs(env.SpecLog) do
				if entry[1] == "collectgarbage" then
					collects = collects + 1
				end
			end
			assert.equal(1, collects)
			assert.equal(#env.Shard.AIs, AIsAtCollect)
			assert.is_true(AIsAtCollect > 0)
		end)

		it("fills the tables of an ally team taken over from another host with the units it sees", function()
			local world = perceptionWorld()
			world.hosts[2] = 1
			local loader = started(world)
			loader.world.frame = 100
			loader.world.units[100] = { team = 0 }
			loader.world.losStates = { [100] = { [1] = 3 } }

			loader.syncActions.shard_host("shard_host", 2, 0)

			local perception0, perception1 = perceptions(loader)
			assert.same({ [100] = true }, perception1.los)
			assert.same({ [100] = true }, perception1.radar)
			assert.same({}, perception0.los)
		end)
	end)

	describe("with errors while loading", function()
		it("leaves an AI type that fails to load unloaded, with a line per team, and runs the others", function()
			local world = defaultWorld()
			world.teams[1].luaAI = "BrokenAI"
			world.teams[2].luaAI = "BrokenAI"
			local loader = started(world)
			loader.gadget:GameFrame(1)

			local Shard = loader.env.Shard
			assert.equal(1, #Shard.AIs)
			assert.is_not_nil(Shard.AIsByTeamID[0])
			assert.is_nil(Shard.alliesByAllyID[1])
			assert.equal(1, #Shard.globals)
			assert.equal(1, echoesWith(loader, "[AI Loader] error loading BrokenAI for team 1: "))
			assert.equal(1, echoesWith(loader, "[AI Loader] error loading BrokenAI for team 2: "))
			assert.equal(2, echoesWith(loader, "broken boot"))
			assert.equal(1, #heard(loader, "BrokenBoot"))
			assert.equal(1, countBy(heard(loader, "Update"), "owner")[Shard.AIsByTeamID[0]])
		end)

		it("drops an AI whose module fails in Init and runs the others", function()
			local loader = started(nil, {
				Init = function(module)
					if module.ai.id == 1 then
						error("broken init")
					end
				end,
			})
			loader.gadget:GameFrame(1)

			local Shard = loader.env.Shard
			assert.is_nil(Shard.AIsByTeamID[1])
			assert.equal(2, #Shard.AIs)
			assert.equal(1, echoesWith(loader, "AI team 1 failed to initialise: stopped on this client"))
			assert.equal(1, echoesWith(loader, "broken init"))
			local counts = countBy(heard(loader, "Update"), "owner")
			assert.equal(1, counts[Shard.AIsByTeamID[0]])
			assert.equal(1, counts[Shard.AIsByTeamID[2]])
		end)

		it("drops a shared object that fails in Init together with the AIs that rely on it", function()
			local loader = started(nil, {
				Init = function(module)
					if module.ai.allyId == 1 and module:Scope() == "ally" then
						error("broken ally init")
					end
				end,
			})

			local Shard = loader.env.Shard
			assert.is_nil(Shard.alliesByAllyID[1])
			assert.is_nil(Shard.AIsByTeamID[2])
			assert.equal(2, #Shard.AIs)
			assert.equal(1, echoesWith(loader, "AI team 2 lost its ally object, which failed to initialise"))
		end)

		it("takes back the ShardAlly that an AI failing after it was created left without AIs", function()
			local world = defaultWorld()
			world.failAllied = 2
			local loader = started(world)

			local Shard = loader.env.Shard
			assert.is_nil(Shard.AIsByTeamID[2])
			assert.is_nil(Shard.alliesByAllyID[1])
			assert.equal(1, #Shard.alliesByAllyID[0])
			assert.equal(1, echoesWith(loader, "allied failure"))
		end)

		it("does not take over a team of an AI type that failed to load", function()
			local world = defaultWorld()
			world.hosts[2] = 1
			world.teams[2].luaAI = "BrokenAI"
			local loader = started(world)

			loader.syncActions.shard_host("shard_host", 2, 0)

			assert.is_nil(loader.env.Shard.AIsByTeamID[2])
			assert.equal(1, echoesWith(loader, "[AI Loader] error loading BrokenAI for team 2: "))
		end)
	end)

	describe("with dead units", function()
		local function destroy(loader, unitID, frame)
			loader.world.frame = frame
			local teamID = loader.world.units[unitID].team
			loader.world.units[unitID] = nil
			loader.gadget:UnitDestroyed(unitID, 1, teamID)
		end

		local function frames(loader, from, to)
			for n = from, to do
				loader.world.frame = n
				loader.gadget:GameFrame(n)
			end
		end

		it("keeps the ShardUnit of a dead unit, with its name, for 900 frames", function()
			local loader = started()
			local Shard = loader.env.Shard
			local game = Shard.AIsByTeamID[0].game
			addUnit(loader, 100, 0)

			destroy(loader, 100, 10)
			assert.equal("specunit", game:GetUnitByID(100):Name())
			frames(loader, 10, 909)
			assert.equal("specunit", game:GetUnitByID(100):Name())
			frames(loader, 910, 911)

			assert.is_nil(Shard.unitsByID[100])
		end)

		it("hands a reused unit ID to the new unit, and the old expiry leaves it alone", function()
			local loader = started()
			local Shard = loader.env.Shard
			addUnit(loader, 100, 0)
			destroy(loader, 100, 10)

			loader.world.frame = 20
			loader.world.units[100] = { team = 2, defID = 2 }
			loader.gadget:UnitCreated(100, 2, 2)
			local reused = Shard.unitsByID[100]
			frames(loader, 20, 1000)

			assert.equal("otherunit", reused:Name())
			assert.equal(reused, Shard.unitsByID[100])
			assert.is_nil(reused.destroyed)
		end)

		it("hands a recycled ID to the new unit before its UnitCreated, and UnitCreated keeps it", function()
			local loader = started()
			local Shard = loader.env.Shard
			local game = Shard.AIsByTeamID[0].game
			addUnit(loader, 100, 0)
			destroy(loader, 100, 10)

			loader.world.units[100] = { team = 2, defID = 2 }
			local recycled = game:GetUnitByID(100)
			assert.equal("otherunit", recycled:Name())
			loader.world.frame = 12
			loader.gadget:UnitCreated(100, 2, 2)
			frames(loader, 12, 1000)

			assert.equal(recycled, Shard.unitsByID[100])
			assert.equal(recycled, game:GetUnitByID(100))
		end)

		it("has no unit for an ID that never existed, and caches nothing", function()
			local loader = started()
			local Shard = loader.env.Shard

			assert.is_nil(Shard.AIsByTeamID[0].game:GetUnitByID(4242))
			assert.is_nil(Shard.unitsByID[4242])
		end)

		it("allocates nothing in GameFrame with many dead units waiting", function()
			local loader = started()
			for unitID = 1000, 1299 do
				addUnit(loader, unitID, 0)
				destroy(loader, unitID, 5)
			end
			loader.env.SpecQuiet = true
			frames(loader, 6, 50)

			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			frames(loader, 51, 1500)
			local after = collectgarbage("count")
			collectgarbage("restart")

			assert.equal(before, after)
			assert.is_nil(loader.env.Shard.unitsByID[1000])
		end)
	end)

	describe("with ShardMemStats", function()
		local function frames(loader, from, to)
			for n = from, to do
				loader.world.frame = n
				loader.gadget:GameFrame(n)
			end
		end

		-- team 0's module allocates `kb(frame)` KB in its Update
		local function allocating(kb)
			return {
				Update = function(module)
					local world = module.ai.specWorld
					if module.ai.id == 0 and module:Scope() == "team" and world then
						world.heap = world.heap + kb(world.frame)
					end
				end,
			}
		end

		local function startedWith(config, kb)
			local world = defaultWorld()
			world.config = config
			world.heap = 1000
			local loader = started(world, allocating(kb))
			loader.env.Shard.AIsByTeamID[0].specWorld = world
			return loader, world
		end

		it("writes the average and the largest allocation of the frames of each minute", function()
			local loader = startedWith({ ShardMemStats = 1 }, function(frame)
				if frame > 1800 then
					return 10
				end
				return frame % 2 == 1 and 6 or 2
			end)

			frames(loader, 0, 3600)

			assert.equal(2, echoesWith(loader, "memory per frame"))
			assert.equal(
				1,
				echoesWith(
					loader,
					"[AI Loader] memory per frame: avg 4.00 KB max 6.00 KB over 1801 frames, heap 8.0 MB"
				)
			)
			assert.equal(
				1,
				echoesWith(
					loader,
					"[AI Loader] memory per frame: avg 10.00 KB max 10.00 KB over 1800 frames, heap 25.6 MB"
				)
			)
		end)

		it("measures nothing and writes nothing when it is off", function()
			local loader, world = startedWith({}, function()
				return 4
			end)

			frames(loader, 1, 3600)

			assert.equal(0, echoesWith(loader, "memory per frame"))
			assert.equal(0, world.countCalls)
		end)

		it("starts measuring in the minute after it is turned on", function()
			local loader, world = startedWith({}, function()
				return 3
			end)

			frames(loader, 1, 1000)
			world.config.ShardMemStats = 1
			frames(loader, 1001, 3600)

			assert.equal(1, echoesWith(loader, "memory per frame"))
			assert.equal(1, echoesWith(loader, "avg 3.00 KB max 3.00 KB over 1800 frames"))
		end)
	end)
	describe("with the timers", function()
		-- Team 0 gets a unit with SpecTimedBehaviour and a team module SpecTimedRunner that updates it, as
		-- UnitHandler does. world.costs.runner and world.costs.behaviour are the milliseconds their Update takes;
		-- SpecHooks.Update, with world.costs.ally and world.costs.global, those of the ally and global modules.
		local function timedWorld(timers)
			local world = defaultWorld()
			world.timers = timers
			world.costs = { runner = 0, behaviour = 0, ally = 0, global = 0 } ---@type table<string, number>
			return world
		end

		local function spend(world, ms)
			world.micros = world.micros + ms * 1000
		end

		local function startedTimed(world)
			local loader = started(world, {
				Update = function(module)
					local scope = module:Scope()
					if scope == "ally" and module.ai.allyId == 0 then
						spend(world, world.costs.ally)
					elseif scope == "global" then
						spend(world, world.costs.global)
					end
				end,
			})
			local env = loader.env
			local thisAI = env.Shard.AIsByTeamID[0]
			local unit = env.Shard.types.SpecAI.env.Unit()
			unit:SetAI(thisAI)
			unit:SetEngineRepresentation({
				ID = function()
					return 100
				end,
			})
			unit:Init()
			local Timed = env.class(env.Behaviour)
			function Timed:Name()
				return "SpecTimedBehaviour"
			end
			function Timed:Update()
				spend(world, world.costs.behaviour)
			end
			unit:AddBehaviour(Timed())
			local Runner = env.class(env.Module)
			function Runner:Name()
				return "SpecTimedRunner"
			end
			function Runner:internalName()
				return "spectimedrunner"
			end
			function Runner:Scope()
				return "team"
			end
			function Runner:Update()
				spend(world, world.costs.runner)
				unit:Update()
			end
			thisAI:AddModule(Runner())
			return loader
		end

		local function frame(loader, n)
			loader.world.frame = n
			loader.gadget:GameFrame(n)
		end

		local function timerLines(loader)
			local lines = {}
			for _, line in ipairs(loader.echoes) do
				if string.find(line, "[Shard timer] ", 1, true) == 1 then
					lines[#lines + 1] = line
				end
			end
			return lines
		end

		it("writes one line for a behaviour and its module above the threshold, with every field", function()
			local world = timedWorld(true)
			local loader = startedTimed(world)
			world.costs.runner = 2
			world.costs.behaviour = 12.34

			frame(loader, 5)

			assert.same({
				"[Shard timer] frame=5 ai=SpecAI team=0 ally=0 scope=team module=SpecTimedRunner"
					.. " behaviour=SpecTimedBehaviour call=Update ms=12.3",
				"[Shard timer] frame=5 ai=SpecAI team=0 ally=0 scope=team module=SpecTimedRunner"
					.. " behaviour=- call=Update ms=14.3",
			}, timerLines(loader))
		end)

		it("writes no line at the threshold or below", function()
			local world = timedWorld(true)
			local loader = startedTimed(world)
			world.costs.behaviour = 10

			frame(loader, 1)
			world.costs.behaviour = 9.9
			frame(loader, 2)

			assert.same({}, timerLines(loader))
		end)

		it("writes the ally and the global modules with their scope", function()
			local world = timedWorld(true)
			local loader = startedTimed(world)
			world.costs.ally = 11
			world.costs.global = 20

			frame(loader, 3)

			assert.same({
				"[Shard timer] frame=3 ai=SpecAI team=- ally=- scope=global module=SpecGlobalModule"
					.. " behaviour=- call=Update ms=20.0",
				"[Shard timer] frame=3 ai=SpecAI team=- ally=0 scope=ally module=SpecAllyModule"
					.. " behaviour=- call=Update ms=11.0",
			}, timerLines(loader))
		end)

		it("names the event a module was called for", function()
			local world = timedWorld(true)
			local loader = startedTimed(world)
			loader.hooks.UnitCreated = function(module)
				if module.ai.id == 1 and module:Name() == "SpecTeamModule" then
					spend(world, 15)
				end
			end

			world.frame = 7
			addUnit(loader, 500, 1)

			assert.same({
				"[Shard timer] frame=7 ai=SpecAI team=1 ally=0 scope=team module=SpecTeamModule"
					.. " behaviour=- call=UnitCreated ms=15.0",
			}, timerLines(loader))
		end)

		it("sums up each name once, at GameOver", function()
			local world = timedWorld(true)
			local loader = startedTimed(world)
			for n, ms in ipairs({ 2, 12, 4 }) do
				world.costs.behaviour = ms
				frame(loader, n)
			end

			loader.gadget:GameOver({ 0 })
			local atGameOver = echoesWith(loader, "[Shard timer summary] names=")
			loader.gadget:Shutdown()

			assert.equal(1, atGameOver)
			assert.equal(
				1,
				echoesWith(
					loader,
					"[Shard timer summary] name=SpecTimedBehaviour kind=behaviour calls=3 min=2.000 max=12.0"
						.. " avg=6.000 sum=18.0 spikes=1"
				)
			)
			assert.equal(
				1,
				echoesWith(
					loader,
					"[Shard timer summary] name=SpecTimedRunner kind=module calls=3 min=2.000 max=12.0"
						.. " avg=6.000 sum=18.0 spikes=1"
				)
			)
			-- three teams: Init, three Updates and GameEnd each
			assert.equal(1, echoesWith(loader, "name=SpecTeamModule kind=module calls=15 min=0.000"))
			assert.equal(1, echoesWith(loader, "[Shard timer summary] names="))
		end)

		it("reads no time and writes nothing when they are off", function()
			local world = timedWorld(false)
			local loader = startedTimed(world)
			world.costs.behaviour = 50

			frame(loader, 1)
			loader.gadget:GameOver({ 0 })

			assert.equal(0, world.timerReads)
			assert.equal(0, echoesWith(loader, "[Shard timer"))
		end)

		it("are on by the switch in the code", function()
			local world = timedWorld("code")
			local loader = startedTimed(world)
			world.costs.behaviour = 30

			frame(loader, 1)

			assert.equal(2, #timerLines(loader))
		end)
	end)

	describe("with the limit of AIs per type", function()
		it("leaves the third team of a type without AI and writes why", function()
			local world = defaultWorld()
			world.maxInstancesPerAIType = nil
			local loader = started(world)
			loader.gadget:GameFrame(1)

			local Shard = loader.env.Shard
			assert.equal(2, #Shard.AIs)
			assert.is_table(Shard.AIsByTeamID[0])
			assert.is_table(Shard.AIsByTeamID[1])
			assert.is_nil(Shard.AIsByTeamID[2])
			assert.is_nil(Shard.alliesByAllyID[1])
			assert.equal(
				1,
				echoesWith(
					loader,
					"[AI Loader] AI team 2 not started: 2 SpecAI AIs already in this game, the most one AI type may have"
				)
			)
			assert.equal(0, echoesWith(loader, "AI team 0 not started"))
			assert.equal(0, echoesWith(loader, "AI team 1 not started"))
		end)

		it("counts the AIs of the whole game, not of this client", function()
			local world = defaultWorld()
			world.maxInstancesPerAIType = nil
			world.hosts = { [0] = 1, [1] = 1, [2] = 0 }
			local loader = started(world)

			assert.equal(0, #loader.env.Shard.AIs)
			assert.equal(1, echoesWith(loader, "AI team 2 not started: 2 SpecAI AIs already in this game"))
		end)

		it("admits the teams with the lowest IDs, whatever their order on this client", function()
			local world = defaultWorld()
			world.maxInstancesPerAIType = nil
			world.teams[0].luaAI = "PercAI"
			world.teams[3].luaAI = "SpecAI"
			world.hosts[3] = 0
			local loader = started(world)

			local Shard = loader.env.Shard
			assert.same({ 0, 1, 2 }, { Shard.AIs[1].id, Shard.AIs[2].id, Shard.AIs[3].id })
			assert.is_nil(Shard.AIsByTeamID[3])
			assert.equal(1, echoesWith(loader, "AI team 3 not started"))
		end)

		it("keeps an excluded team excluded when its host moves here", function()
			local world = defaultWorld()
			world.maxInstancesPerAIType = nil
			world.hosts[2] = 1
			local loader = started(world)
			loader.gadget:GameFrame(1)

			loader.syncActions.shard_host("shard_host", 2, 0)
			loader.gadget:GameFrame(2)

			local Shard = loader.env.Shard
			assert.equal(2, #Shard.AIs)
			assert.is_nil(Shard.AIsByTeamID[2])
			assert.equal(1, echoesWith(loader, "AI team 2 not started"))
		end)

		it("keeps an admitted team admitted when its host moves here", function()
			local world = defaultWorld()
			world.maxInstancesPerAIType = nil
			world.hosts = { [0] = 1, [1] = 0, [2] = 0 }
			local loader = started(world)

			loader.syncActions.shard_host("shard_host", 0, 0)

			local Shard = loader.env.Shard
			assert.is_table(Shard.AIsByTeamID[0])
			assert.is_table(Shard.AIsByTeamID[1])
			assert.is_nil(Shard.AIsByTeamID[2])
			assert.equal(0, echoesWith(loader, "AI team 0 not started"))
		end)

		it("counts each AI type on its own", function()
			local world = defaultWorld()
			world.maxInstancesPerAIType = nil
			world.teams[2].luaAI = "PercAI"
			local loader = started(world)

			assert.equal(3, #loader.env.Shard.AIs)
			assert.equal(0, echoesWith(loader, "not started"))
		end)
	end)

	describe("with the garbage collection safety net", function()
		local function collections(loader)
			return #heard(loader, "collectgarbage")
		end

		it("raises the limit by 50 MB from 200 MB for every AI, as the old loader did", function()
			local loader = started()

			assert.equal(1, echoesWith(loader, "AI 0 (SpecAI) using 200 MB RAM, adjusting limit to 250 MB"))
			assert.equal(1, echoesWith(loader, "AI 1 (SpecAI) using 200 MB RAM, adjusting limit to 300 MB"))
			assert.equal(1, echoesWith(loader, "AI 2 (SpecAI) using 200 MB RAM, adjusting limit to 350 MB"))
		end)

		it("collects only on frames divisible by 121 with the memory above the limit", function()
			local world = defaultWorld()
			world.heap = 350000
			local loader = started(world)
			-- without the clean start of Initialize
			for i = #loader.log, 1, -1 do
				loader.log[i] = nil
			end
			loader.gadget:GameFrame(121)
			assert.equal(0, collections(loader))

			world.heap = 350001
			loader.gadget:GameFrame(120)
			loader.gadget:GameFrame(122)
			assert.equal(0, collections(loader))
			loader.gadget:GameFrame(242)
			assert.equal(1, collections(loader))
		end)

		it("collects after the AIs' Update of the frame and sets the limit from what is left", function()
			local world = defaultWorld()
			local loader = started(world)
			world.heap = 350001
			world.heapAfterCollect = 100000
			for i = #loader.log, 1, -1 do
				loader.log[i] = nil
			end
			loader.gadget:GameFrame(121)

			local lastUpdate, collect = 0, nil
			for i, entry in ipairs(loader.log) do
				if entry[1] == "Update" then
					lastUpdate = i
				elseif entry[1] == "collectgarbage" then
					collect = i
				end
			end
			assert.is_true(lastUpdate > 0)
			assert.is_true(collect > lastUpdate)
			assert.equal(
				1,
				echoesWith(
					loader,
					"3 STAIs using 350 MB RAM > 350 MB limit, performing garbage collection and adjusting limit to 450 MB"
				)
			)

			world.heap = 450000
			loader.gadget:GameFrame(242)
			assert.equal(1, collections(loader))
			world.heap = 450001
			loader.gadget:GameFrame(363)
			assert.equal(2, collections(loader))
		end)

		it("keeps the limit at 1 GB at most", function()
			local world = defaultWorld()
			local loader = started(world)
			world.heap = 2000000
			world.heapAfterCollect = 900000
			loader.gadget:GameFrame(121)

			assert.equal(1, echoesWith(loader, "adjusting limit to 1000 MB"))
		end)
	end)
end)
