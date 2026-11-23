---@diagnostic disable: undefined-field, need-check-nil, inject-field, param-type-mismatch, redundant-parameter
---@diagnostic disable: missing-return, missing-return-value, missing-fields, call-non-callable

local newVFS = require("spec/support/fake_vfs")

local LOADER_PATH = "luarules/gadgets/ShardAILoader.lua"
local CODEC_PATH = "luarules/gadgets/ai/shard_runtime/ordercodec.lua"

local CMD_STOP = 0
local CMD_MOVE = 10
local CMD_GUARD = 25
local OPT_SHIFT = 32

-- Teams 0 and 1 are STAI in ally team 0, team 2 is STAI in ally team 1, team 3 is a human in ally team 0.
-- Lobby hosts: player 0 added teams 0 and 1, player 1 added team 2.
local function defaultWorld()
	return {
		frame = 1000,
		teams = {
			[0] = { allyId = 0, luaAI = "STAI", host = 0 },
			[1] = { allyId = 0, luaAI = "STAI", host = 0 },
			[2] = { allyId = 1, luaAI = "STAI", host = 1 },
			[3] = { allyId = 0 },
		},
		players = {
			[0] = { active = true, spectator = false, allyId = 0 },
			[1] = { active = true, spectator = false, allyId = 1 },
			[2] = { active = true, spectator = false, allyId = 0 },
			[5] = { active = true, spectator = true, allyId = 0 },
		},
		units = { [100] = 0, [101] = 0, [200] = 1, [300] = 2 },
	}
end

-- Loads ShardAILoader.lua as synced code over a fake engine and returns what it did.
local function loadLoader(world)
	world = world or defaultWorld()
	local recorded = { orders = {}, arrays = {}, toUnsynced = {}, rulesParams = {}, echoes = {} }
	local env = setmetatable({}, { __index = _G })
	local teamIDs = {}
	for teamID in pairs(world.teams) do
		teamIDs[#teamIDs + 1] = teamID
	end
	table.sort(teamIDs)

	env.VFS = newVFS(env)
	env.VFS.FileExists = function(path)
		for _, team in pairs(world.teams) do
			if team.luaAI and path == "luarules/gadgets/ai/" .. team.luaAI .. "/boot.lua" then
				return true
			end
		end
		return false
	end
	env.Game = { maxUnits = 32000 }
	env.gadget = {}
	env.gadgetHandler = {
		IsSyncedCode = function()
			return true
		end,
	}
	env.SendToUnsynced = function(...)
		recorded.toUnsynced[#recorded.toUnsynced + 1] = { ... }
	end
	env.Spring = {
		Echo = function(...)
			recorded.echoes[#recorded.echoes + 1] = table.concat({ ... }, " ")
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
		GetAIInfo = function(teamID)
			return 0, "STAI", world.teams[teamID].host
		end,
		GetPlayerList = function()
			local list = {}
			for playerID in pairs(world.players) do
				list[#list + 1] = playerID
			end
			table.sort(list)
			return list
		end,
		GetPlayerInfo = function(playerID)
			local player = world.players[playerID]
			if player == nil then
				return nil
			end
			return "player" .. playerID, player.active, player.spectator, 0, player.allyId
		end,
		GetGameFrame = function()
			return world.frame
		end,
		SetTeamRulesParam = function(teamID, name, value, access)
			recorded.rulesParams[#recorded.rulesParams + 1] = { teamID, name, value, access.public }
		end,
		ValidUnitID = function(unitID)
			return world.units[unitID] ~= nil
		end,
		GetUnitTeam = function(unitID)
			return world.units[unitID]
		end,
		GiveOrderToUnit = function(unitID, cmdID, params, options)
			recorded.orders[#recorded.orders + 1] = { unit = unitID, cmds = { { cmdID, params, options } } }
		end,
		GiveOrderArrayToUnit = function(unitID, array)
			local cmds = {}
			for i, cmd in ipairs(array) do
				cmds[i] = { cmd[1], cmd[2], cmd[3] }
			end
			recorded.orders[#recorded.orders + 1] = { unit = unitID, cmds = cmds, array = array }
		end,
	}

	local chunk = assert(loadfile(LOADER_PATH))
	setfenv(chunk, env)
	recorded.loaded = chunk()
	recorded.gadget = env.gadget
	recorded.codec = env.VFS.Include(CODEC_PATH)
	recorded.VFS = env.VFS
	recorded.world = world
	return recorded
end

-- A message from the orders { unitID, cmdID, params, options }.
local function message(loader, teamID, seq, frame, orders)
	local codec = loader.codec
	local pieces = { codec.PackHeader(teamID, seq, frame, #orders) }
	for i, order in ipairs(orders) do
		local params = order[3] or {}
		pieces[i + 1] = codec.PackOrder(order[1], order[2], order[4] or 0, params, #params)
	end
	return table.concat(pieces)
end

local function receive(loader, playerID, text)
	return loader.gadget:RecvLuaMsg(text, playerID)
end

-- The reasons the relay rejected messages for, as Shutdown reports them.
local function rejections(loader)
	loader.gadget:Shutdown()
	local reasons = {}
	for _, line in ipairs(loader.echoes) do
		local count, reason = string.match(line, "^Shard relay: (%d+) messages rejected %((%w+)%)$")
		if reason then
			reasons[reason] = tonumber(count)
		end
	end
	return reasons
end

local function started(world)
	local loader = loadLoader(world)
	loader.gadget:Initialize()
	return loader
end

describe("ShardAILoader synced relay", function()
	it("gives the host's orders, consecutive orders of a unit in one array call that is emptied after", function()
		local loader = started()

		local accepted = receive(
			loader,
			0,
			message(loader, 0, 1, 1000, {
				{ 100, CMD_MOVE, { 10.5, -20, 30 }, OPT_SHIFT },
				{ 100, CMD_GUARD, { 101 } },
				{ 101, CMD_MOVE, { 1, 2, 3 } },
				{ 100, CMD_STOP },
			})
		)

		assert.is_true(accepted)
		local orders = loader.orders
		assert.equal(3, #orders)
		assert.equal(100, orders[1].unit)
		assert.same({ { CMD_MOVE, { 10.5, -20, 30 }, OPT_SHIFT }, { CMD_GUARD, 101, 0 } }, orders[1].cmds)
		assert.is_nil(next(orders[1].array))
		assert.same({ unit = 101, cmds = { { CMD_MOVE, { 1, 2, 3 }, 0 } } }, orders[2])
		assert.same({ unit = 100, cmds = { { CMD_STOP, nil, 0 } } }, orders[3])
		assert.equal(0, #loader.toUnsynced)
	end)

	it("reads an order without params at the end of the message", function()
		local loader = started()

		receive(
			loader,
			0,
			message(loader, 0, 1, 1000, { { 100, CMD_MOVE, { 1, 2, 3 } }, { 100, CMD_STOP, nil, OPT_SHIFT } })
		)

		assert.same({ { CMD_MOVE, { 1, 2, 3 }, 0 }, { CMD_STOP, nil, OPT_SHIFT } }, loader.orders[1].cmds)
	end)

	it("rejects a message from a player who does not host the team", function()
		local loader = started()

		assert.is_true(receive(loader, 1, message(loader, 0, 1, 1000, { { 100, CMD_STOP } })))
		assert.is_true(receive(loader, 0, message(loader, 2, 1, 1000, { { 300, CMD_STOP } })))
		assert.is_true(receive(loader, 0, message(loader, 3, 1, 1000, { { 100, CMD_STOP } })))

		assert.equal(0, #loader.orders)
		assert.same({ sender = 3 }, rejections(loader))
	end)

	it("drops only the orders for units of another team or not valid, and reports how many", function()
		local loader = started()

		receive(
			loader,
			0,
			message(loader, 0, 1, 1000, {
				{ 100, CMD_STOP },
				{ 200, CMD_STOP },
				{ 200, CMD_MOVE, { 1, 2, 3 } },
				{ 999, CMD_STOP },
				{ 101, CMD_STOP },
			})
		)

		assert.same({ 100, 101 }, { loader.orders[1].unit, loader.orders[2].unit })
		assert.equal(2, #loader.orders)
		assert.same({ { "shard_relay_rejected", 0, 3 } }, loader.toUnsynced)
	end)

	it("rejects a seq that is not above the last accepted one", function()
		local loader = started()

		receive(loader, 0, message(loader, 0, 5, 1000, { { 100, CMD_STOP } }))
		receive(loader, 0, message(loader, 0, 5, 1000, { { 100, CMD_STOP } }))
		receive(loader, 0, message(loader, 0, 4, 999, { { 100, CMD_STOP } }))

		assert.equal(1, #loader.orders)
		assert.same({ seq = 2 }, rejections(loader))
	end)

	it("rejects an emission frame in the future or older than 900 frames", function()
		local loader = started()

		receive(loader, 0, message(loader, 0, 1, 1001, { { 100, CMD_STOP } }))
		receive(loader, 0, message(loader, 0, 2, 99, { { 100, CMD_STOP } }))
		receive(loader, 0, message(loader, 0, 3, 100, { { 100, CMD_STOP } }))

		assert.equal(1, #loader.orders)
		assert.same({ frame = 2 }, rejections(loader))
	end)

	it("accepts two messages per emission frame, and a new emission frame in the same game frame", function()
		local loader = started()

		for seq = 1, 3 do
			receive(loader, 0, message(loader, 0, seq, 999, { { 100, CMD_STOP } }))
		end
		receive(loader, 0, message(loader, 0, 4, 1000, { { 100, CMD_STOP } }))

		assert.equal(3, #loader.orders)
		assert.same({ rate = 1 }, rejections(loader))
	end)

	it("rejects a wrong version, a short header and more than 4000 orders, and keeps all three", function()
		local loader = started()
		local VFS = loader.VFS
		local valid = message(loader, 0, 1, 1000, { { 100, CMD_STOP } })
		local wrongVersion = "AIFw" .. VFS.PackU8(2, 0) .. string.sub(valid, 7)

		assert.is_true(receive(loader, 0, wrongVersion))
		assert.is_true(receive(loader, 0, string.sub(valid, 1, 15)))
		assert.is_true(receive(loader, 0, loader.codec.PackHeader(0, 2, 1000, 4001)))

		assert.equal(0, #loader.orders)
		assert.same({ version = 1, size = 1, count = 1 }, rejections(loader))
	end)

	it("gives the orders before a cut one and reports the rest as rejected", function()
		local loader = started()
		local text =
			message(loader, 0, 1, 1000, { { 100, CMD_STOP }, { 101, CMD_MOVE, { 1, 2, 3 } }, { 101, CMD_STOP } })

		receive(loader, 0, string.sub(text, 1, #text - 9))

		assert.same({ unit = 100, cmds = { { CMD_STOP, nil, 0 } } }, loader.orders[1])
		assert.equal(1, #loader.orders)
		assert.same({ { "shard_relay_rejected", 0, 2 } }, loader.toUnsynced)
	end)

	it("leaves a message without the magic to other gadgets", function()
		local loader = started()

		assert.is_false(receive(loader, 0, "@Shard[STGO]&id:100[STGO]Shard@"))
		assert.is_false(receive(loader, 0, ""))
	end)
end)

describe("ShardAILoader host registry", function()
	local function hostParams(loader)
		local hosts = {}
		for _, param in ipairs(loader.rulesParams) do
			assert.equal("aiHostPlayer", param[2])
			assert.is_true(param[4])
			hosts[param[1]] = param[3]
		end
		return hosts
	end

	it("registers the lobby host of each ally team as a public team rules param", function()
		local loader = started()

		assert.same({ [0] = 0, [1] = 0, [2] = 1 }, hostParams(loader))
		assert.equal(0, #loader.toUnsynced)
	end)

	it("hands an ally team to its lowest active player when the host leaves, and the seq starts again", function()
		local world = defaultWorld()
		world.players[4] = { active = true, spectator = false, allyId = 0 }
		local loader = started(world)
		receive(loader, 0, message(loader, 0, 7, 1000, { { 100, CMD_STOP } }))

		world.players[0].active = false
		loader.gadget:PlayerRemoved(0, 1)

		assert.same({ [0] = 2, [1] = 2, [2] = 1 }, hostParams(loader))
		assert.same({ { "shard_host", 0, 2 }, { "shard_host", 1, 2 } }, loader.toUnsynced)
		receive(loader, 0, message(loader, 0, 8, 1000, { { 100, CMD_STOP } }))
		receive(loader, 2, message(loader, 0, 1, 1000, { { 101, CMD_STOP } }))
		assert.same({ 100, 101 }, { loader.orders[1].unit, loader.orders[2].unit })
		assert.equal(2, #loader.orders)
	end)

	it("falls back to any active player, then to a spectator, the lowest ID first", function()
		local world = defaultWorld()
		world.players = {
			[0] = { active = true, spectator = false, allyId = 0 },
			[1] = { active = true, spectator = false, allyId = 1 },
			[3] = { active = true, spectator = false, allyId = 1 },
			[7] = { active = true, spectator = true, allyId = 0 },
			[6] = { active = true, spectator = true, allyId = 1 },
		}
		local loader = started(world)

		world.players[0].active = false
		loader.gadget:PlayerRemoved(0, 1)
		assert.same({ [0] = 1, [1] = 1, [2] = 1 }, hostParams(loader))

		world.players[1].active = false
		world.players[3].active = false
		loader.gadget:PlayerRemoved(1, 1)
		assert.same({ [0] = 6, [1] = 6, [2] = 6 }, hostParams(loader))
	end)
end)

describe("ShardAILoader start", function()
	it("deactivates itself without Shard AIs", function()
		local world = defaultWorld()
		for _, team in pairs(world.teams) do
			team.luaAI = nil
		end

		assert.is_false(loadLoader(world).loaded)
	end)
end)
