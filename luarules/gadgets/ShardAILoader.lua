local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Shard AI Loader",
		desc = "Shard by AF for Spring Lua",
		author = "eronoobos, based on gadget by raaar, and original AI by AF, maintained by Pandaro(bio)",
		date = "November 2026",
		license = "GPL",
		layer = 999999,
		enabled = true,
	}
end

-- Loader of the Lua AIs written for the Shard runtime (luarules/gadgets/ai/<AI name>/boot.lua).
-- The AIs run only on the client that hosts their ally team; the synced side registers that host in the
-- public team rules param "aiHostPlayer" and relays the binary order messages of shard_runtime/ordercodec.lua,
-- only from the host of a team and only for units of that team.

local spEcho = Spring.Echo
local spGetTeamLuaAI = Spring.GetTeamLuaAI
local spGetGameFrame = Spring.GetGameFrame
local teamList = Spring.GetTeamList()

local AI_PATH = "luarules/gadgets/ai/"
local RUNTIME_PATH = "luarules/gadgets/ai/shard_runtime"
local LOADER_PATH = RUNTIME_PATH .. "/loader/"

-- teams whose Lua AI has a Shard boot.lua
local aiTeams = {}
local shardEnabled = false

for i = 1, #teamList do
	local luaAI = spGetTeamLuaAI(teamList[i])
	if type(luaAI) == "string" and luaAI ~= "" and VFS.FileExists(AI_PATH .. luaAI .. "/boot.lua") then
		aiTeams[teamList[i]] = luaAI
		shardEnabled = true
	end
end

if not shardEnabled then
	spEcho("[AI Loader] ShardLua bot Deactivated!")
	return false
end

-- unit IDs travel as U16 in the order messages
---@diagnostic disable-next-line: unnecessary-if
if Game.maxUnits > 65536 then
	spEcho("[AI Loader] Game.maxUnits does not fit the order format: ShardLua bot Deactivated!")
	return false
end

spEcho("[AI Loader] ShardLua bot Activated!")

if gadgetHandler:IsSyncedCode() then
	-- SYNCED CODE: host registry and order relay. No AI code runs here.

	local Relay = VFS.Include(LOADER_PATH .. "relay.lua")
	local Hosts = VFS.Include(LOADER_PATH .. "hosts.lua")
	Hosts.Setup(aiTeams, teamList, Relay.ForgetTeam)
	Relay.Setup(Hosts.HostOf)

	function gadget:Initialize()
		-- before the game starts players may still be connecting: keep the hosts chosen in the lobby
		Hosts.Register(nil, spGetGameFrame() > 0)
		-- UnitMoveFailed: the engine sends it only to synced code, only for unit defs watched with
		-- Script.SetWatchUnit, and luarules/gadgets.lua keeps it among the commented optional call-ins.
		-- Until both change the AIs do not receive it (the old loader did not forward it either).
	end

	function gadget:GameStart()
		Hosts.Register(nil, true)
	end

	function gadget:PlayerRemoved(playerID, reason)
		Hosts.Register(playerID, true)
	end

	function gadget:RecvLuaMsg(msg, playerID)
		return Relay.Receive(msg, playerID)
	end

	function gadget:Shutdown()
		spEcho("Shard AI sync gadget shutdown")
		Relay.WriteCounters()
	end
else
	-- UNSYNCED CODE: the AIs, only on the client that hosts them

	local MemStats = VFS.Include(LOADER_PATH .. "memstats.lua")
	local UnitRegistry = VFS.Include(LOADER_PATH .. "unitregistry.lua")
	local Delivery = VFS.Include(LOADER_PATH .. "delivery.lua")
	local Loader = VFS.Include(LOADER_PATH .. "loader.lua")
	Loader.Setup({
		gadget = gadget,
		aiTeams = aiTeams,
		teamList = teamList,
		aiPath = AI_PATH,
		runtimePath = RUNTIME_PATH,
		Delivery = Delivery,
		UnitRegistry = UnitRegistry,
	})

	-- the functions of every frame and every unit event
	local IsHosting = Loader.IsHosting
	local StartAIsOnce = Loader.StartAIsOnce
	local FlushOrders = Loader.FlushOrders
	local UpdateAll = Delivery.UpdateAll
	local DeliverToShared = Delivery.DeliverToShared
	local DeliverToOwner = Delivery.DeliverToOwner
	local DeliverToAll = Delivery.DeliverToAll
	local DeliverSight = Delivery.DeliverSight
	local AddToUnitTables = UnitRegistry.AddToUnitTables
	local RemoveFromUnitTables = UnitRegistry.RemoveFromUnitTables
	local KeepDeadUnit = UnitRegistry.KeepDeadUnit
	local ExpireDeadUnits = UnitRegistry.ExpireDeadUnits
	local BeginMemoryFrame = MemStats.BeginFrame
	local EndMemoryFrame = MemStats.EndFrame

	function gadget:Initialize()
		spEcho("Looking for AIs")
		gadgetHandler:AddSyncAction("shard_host", Loader.HostChanged)
		gadgetHandler:AddSyncAction("shard_relay_rejected", Loader.RelayRejected)
		Loader.AddHostedAIs()
		if not IsHosting() then
			spEcho("[AI Loader] no AI hosted on this client")
			return
		end
		Loader.CatchUpAfterReload()
	end

	function gadget:GameStart()
		if IsHosting() then
			Loader.StartAIs()
		end
	end

	function gadget:GameFrame(n)
		if not IsHosting() then
			return
		end
		StartAIsOnce()
		BeginMemoryFrame()
		UpdateAll()
		FlushOrders(n)
		ExpireDeadUnits(n)
		EndMemoryFrame(n)
	end

	function gadget:UnitCreated(unitId, unitDefId, teamId, builderId)
		if not IsHosting() then
			return
		end
		StartAIsOnce()
		AddToUnitTables(unitId, teamId)
		local unit = Shard:shardify_unit(unitId)
		DeliverToShared("UnitCreated", unit, unitDefId, teamId, builderId)
		DeliverToOwner(teamId, "UnitCreated", unit, unitDefId, teamId, builderId)
	end

	function gadget:UnitFinished(unitId, unitDefId, teamId)
		if not IsHosting() then
			return
		end
		StartAIsOnce()
		-- AIBase:UnitBuilt turns it into MyUnitBuilt, FriendlyUnitBuilt, EnemyUnitBuilt or NeutralUnitBuilt
		DeliverToAll("UnitBuilt", Shard:shardify_unit(unitId), unitDefId, teamId)
	end

	function gadget:UnitDestroyed(unitId, unitDefId, teamId, attackerId, attackerDefId, attackerTeamId)
		if not IsHosting() then
			return
		end
		StartAIsOnce()
		local unit = Shard:shardify_unit(unitId)
		DeliverToAll("UnitDead", unit)
		RemoveFromUnitTables(unitId)
		-- kept a while, with its type and name, then dropped: the old loader kept every dead unit forever
		KeepDeadUnit(unitId, unit, spGetGameFrame())
	end

	function gadget:UnitDamaged(
		unitId,
		unitDefId,
		unitTeamId,
		damage,
		paralyzer,
		weaponDefId,
		projectileId,
		attackerId,
		attackerDefId,
		attackerTeamId
	)
		if not IsHosting() then
			return
		end
		StartAIsOnce()
		local unit = Shard:shardify_unit(unitId)
		local attacker = Shard:shardify_unit(attackerId)
		local damageObj = Shard:shardify_damage(damage, weaponDefId, paralyzer)
		DeliverToAll("UnitDamaged", unit, attacker, damageObj)
	end

	function gadget:UnitIdle(unitId, unitDefId, teamId)
		if not IsHosting() then
			return
		end
		StartAIsOnce()
		DeliverToAll("UnitIdle", Shard:shardify_unit(unitId))
	end

	function gadget:UnitTaken(unitId, unitDefId, teamId, newTeamId)
		if not IsHosting() then
			return
		end
		StartAIsOnce()
		DeliverToAll("UnitDead", Shard:shardify_unit(unitId))
		RemoveFromUnitTables(unitId)
	end

	-- as the old loader did: every object hears UnitCreated for a unit that changed team
	function gadget:UnitGiven(unitId, unitDefId, teamId, oldTeamId)
		if not IsHosting() then
			return
		end
		StartAIsOnce()
		AddToUnitTables(unitId, teamId)
		DeliverToAll("UnitCreated", Shard:shardify_unit(unitId), unitDefId, teamId, oldTeamId)
	end

	function gadget:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
		if IsHosting() then
			StartAIsOnce()
			DeliverSight("UnitEnteredLos", unitID, unitTeam, allyTeam, unitDefID)
		end
	end

	function gadget:UnitLeftLos(unitID, unitTeam, allyTeam, unitDefID)
		if IsHosting() then
			StartAIsOnce()
			DeliverSight("UnitLeftLos", unitID, unitTeam, allyTeam, unitDefID)
		end
	end

	function gadget:UnitEnteredRadar(unitID, unitTeam, allyTeam, unitDefID)
		if IsHosting() then
			StartAIsOnce()
			DeliverSight("UnitEnteredRadar", unitID, unitTeam, allyTeam, unitDefID)
		end
	end

	function gadget:UnitLeftRadar(unitID, unitTeam, allyTeam, unitDefID)
		if IsHosting() then
			StartAIsOnce()
			DeliverSight("UnitLeftRadar", unitID, unitTeam, allyTeam, unitDefID)
		end
	end

	function gadget:FeatureDestroyed(featureID)
		if IsHosting() then
			Shard:unshardify_feature(featureID)
		end
	end

	-- the old loader never forwarded the end of the game: GameEnd() did not reach the modules
	function gadget:GameOver(winningAllyTeams)
		if not IsHosting() then
			return
		end
		Delivery.EndGameAll()
		Delivery.WriteErrorSummary()
	end

	function gadget:GameID(gameID)
		Loader.SetGameID(gameID)
	end

	function gadget:Shutdown()
		spEcho("Shard AI unsync gadget shutdown")
		MemStats.WritePeak()
		Delivery.WriteErrorSummary()
		gadgetHandler:RemoveSyncAction("shard_host")
		gadgetHandler:RemoveSyncAction("shard_relay_rejected")
	end
end
