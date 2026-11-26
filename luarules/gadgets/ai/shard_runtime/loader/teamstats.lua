-- How every team of the game is doing, whoever plays it, on the hosting client. Unsynced.
--
-- SHARD_TEAM_STATS, the switch: once a minute of game, one line per team of the game but Gaia, from the last
-- sample of the engine's statistics history:
-- "[Shard stats] f=<frame> team=<id> ally=<allyId> ai=<type> metal=+<produced>/-<used> energy=+<produced>/-<used>
-- dmg=<dealt>/<received> units=<produced>/<died>/<killed>"
-- The values are totals since the start of the game, rounded; f is the frame of the line, not of the sample.
-- type is the name of the Lua AI, the short name of a native AI, or "human".
-- GameOver, or Shutdown if the game is not over, writes "[Shard stats] summary" and the same lines, once.
-- Off, it costs one check per frame.

local SHARD_TEAM_STATS = false ---@type boolean

local spEcho = Spring.Echo
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamStatsHistory = Spring.GetTeamStatsHistory
local stringFormat = string.format
local mathFloor = math.floor

local REPORT_FRAMES = 1800 -- one report a minute

---@class ShardStatsTeam
---@field id integer
---@field allyId integer
---@field ai string

local enabled = SHARD_TEAM_STATS
local teams = {} ---@type ShardStatsTeam[]
local summaryWritten = false

local function TypeOfTeam(teamID)
	local luaAI = Spring.GetTeamLuaAI(teamID)
	if luaAI ~= nil and luaAI ~= "" then
		return luaAI
	end
	local _, _, _, shortName = Spring.GetAIInfo(teamID)
	return shortName or "human"
end

--- The teams of the report and their types, which do not change during the game
---@param teamList integer[]
local function Setup(teamList)
	if not enabled then
		return
	end
	local gaiaTeamID = Spring.GetGaiaTeamID()
	for i = 1, #teamList do
		local teamID = teamList[i] --[[@as integer]]
		if teamID ~= gaiaTeamID then
			local _, _, _, _, _, allyId = Spring.GetTeamInfo(teamID, false)
			teams[#teams + 1] = {
				id = teamID,
				allyId = allyId --[[@as integer]],
				ai = TypeOfTeam(teamID),
			}
		end
	end
end

local function Round(value)
	return mathFloor(value + 0.5)
end

local function WriteTeams(frame)
	for i = 1, #teams do
		local team = teams[i] --[[@as ShardStatsTeam]]
		local count = spGetTeamStatsHistory(team.id) --[[@as integer?]]
		local history = count ~= nil and count > 0 and spGetTeamStatsHistory(team.id, count)
		local sample = history and history[1]
		if sample then
			-- the engine's stubs do not list unitsKilled
			---@diagnostic disable-next-line: undefined-field
			local killed = sample.unitsKilled ---@type integer
			spEcho(
				stringFormat(
					"[Shard stats] f=%d team=%d ally=%d ai=%s metal=+%d/-%d energy=+%d/-%d dmg=%d/%d units=%d/%d/%d",
					frame,
					team.id,
					team.allyId,
					team.ai,
					Round(sample.metalProduced),
					Round(sample.metalUsed),
					Round(sample.energyProduced),
					Round(sample.energyUsed),
					Round(sample.damageDealt),
					Round(sample.damageReceived),
					sample.unitsProduced,
					sample.unitsDied,
					killed
				)
			)
		end
	end
end

--- Called at the end of the gadget's GameFrame
local function GameFrame(n)
	if enabled and n > 0 and n % REPORT_FRAMES == 0 then
		WriteTeams(n)
	end
end

--- The last report of the game; only the first call writes
local function WriteSummary()
	if not enabled or summaryWritten then
		return
	end
	summaryWritten = true
	spEcho("[Shard stats] summary")
	WriteTeams(spGetGameFrame())
end

return {
	Setup = Setup,
	GameFrame = GameFrame,
	WriteSummary = WriteSummary,
}
