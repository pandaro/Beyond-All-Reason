---@diagnostic disable: undefined-field, need-check-nil, inject-field, param-type-mismatch, redundant-parameter
---@diagnostic disable: missing-return, missing-return-value, missing-fields, call-non-callable, undefined-global

local newVFS = require("spec/support/fake_vfs")

local LOADER_PATH = "luarules/gadgets/ShardAILoader.lua"
local CODEC_PATH = "luarules/gadgets/ai/shard_runtime/ordercodec.lua"
local FIXTURE_PATHS = {
	["luarules/gadgets/ai/SpecAI/"] = "spec/fixtures/shard_ai/",
	["luarules/gadgets/ai/BrokenAI/"] = "spec/fixtures/shard_ai_broken/",
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

-- the spec AI types live under spec/fixtures, the rest of the runtime where the engine finds it
local function realPath(path)
	for aiPath, fixturePath in pairs(FIXTURE_PATHS) do
		if string.sub(path, 1, #aiPath) == aiPath then
			return fixturePath .. string.sub(path, #aiPath + 1)
		end
	end
	return path
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
		return include(realPath(path), includeEnv)
	end
	vfs.FileExists = function(path)
		return fileExists(realPath(path))
	end
	env.VFS = vfs
	env.Game = { maxUnits = 32000, gameShortName = "BAR", mapName = "Spec Map" }
	env.UnitDefs = { [1] = { name = "specunit" } }
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
		GetUnitDefID = function()
			return 1
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
		GetUnitLosState = function()
			return 0
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
		assert.is_nil(loader.env.Shard.unitsByID[200])
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
		assert.equal(2, echoesWith(loader, "[AI Loader] error in SpecAI team 1, Update"))
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

		local reference = 0
		for i = 1, #gameID do
			local step = reference * 31 + string.byte(gameID, i)
			assert.is_true(step < 2 ^ 24)
			reference = step % 65521
		end

		assert.equal(reference, loader.gadget:HashGameID(gameID))
		assert.equal(reference, loader.gadget:HashGameID(gameID))
		loader.gadget:GameID(gameID)
		local o = objects(loader)
		assert.equal(reference, loader.env.Shard.randomseed)
		assert.equal((reference * 31 + 1) % 65521, o.team0.randomseed)
		assert.are_not.equal(o.team0.randomseed, o.team1.randomseed)
		assert.is_true(reference * 31 + 255 < 2 ^ 24)
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
end)
