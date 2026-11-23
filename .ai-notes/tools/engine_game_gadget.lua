-- Writes, every minute of game, one line per team: units, factories, metal extractors, metal, energy and, for a Shard
-- team, aiHostPlayer; "SUMMARY" lines at the end frame. Copied to luarules/gadgets/ by run_engine_game.sh, never
-- committed there.

local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Shard engine game",
		desc = "Reports every team once a minute in a test game",
		author = "Shard",
		date = "November 2026",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	-- nobody presses "ready" in a headless game: ask the test environment helper, as the test runner does,
	-- every two seconds until the game starts
	local lastAsked = nil
	function gadget:Update()
		if Spring.GetGameFrame() > 0 then
			gadgetHandler:RemoveCallIn("Update")
			return
		end
		local now = os.clock()
		if lastAsked == nil or now - lastAsked > 2 then
			lastAsked = now
			Spring.SendCommands("luarules setTestReadyPlayers")
		end
	end
	return
end

local TAG = "[SHARD-GAME]"
local FRAMES_PER_MINUTE = 1800
-- run_engine_game.sh replaces the next line with the last frame of the game
local END_FRAME = 27000

local factoryDefs = {}
local extractorDefs = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.isFactory then
		factoryDefs[unitDefID] = true
	end
	if (unitDef.extractsMetal or 0) > 0 then
		extractorDefs[unitDefID] = true
	end
end

local function report(label)
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local units = Spring.GetTeamUnits(teamID) or {}
		local factories, extractors = 0, 0
		for i = 1, #units do
			local unitDefID = Spring.GetUnitDefID(units[i])
			if factoryDefs[unitDefID] then
				factories = factories + 1
			end
			if extractorDefs[unitDefID] then
				extractors = extractors + 1
			end
		end
		local metal = Spring.GetTeamResources(teamID, "metal") or 0
		local energy = Spring.GetTeamResources(teamID, "energy") or 0
		local luaAI = Spring.GetTeamLuaAI(teamID) or ""
		local host = Spring.GetTeamRulesParam(teamID, "aiHostPlayer")
		Spring.Echo(
			string.format(
				"%s %s team %d %s: units %d, factories %d, mexes %d, metal %.0f, energy %.0f, aiHostPlayer %s",
				TAG,
				label,
				teamID,
				luaAI ~= "" and luaAI or "-",
				#units,
				factories,
				extractors,
				metal,
				energy,
				tostring(host)
			)
		)
	end
end

function gadget:GameFrame(n)
	if n == END_FRAME then
		report("SUMMARY")
	elseif n > 0 and n % FRAMES_PER_MINUTE == 0 and n < END_FRAME then
		report(string.format("minute %2d", n / FRAMES_PER_MINUTE))
	end
end
