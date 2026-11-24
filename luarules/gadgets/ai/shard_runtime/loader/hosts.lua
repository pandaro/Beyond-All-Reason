-- The host of each AI team: one client per ally team runs all its AIs, so that the ally scope exists once.
-- The host is published in the public team rules param "aiHostPlayer", which the relay and the unsynced side
-- read; when a host leaves, a deterministic successor takes over. Synced: no unsynced data, no timers.

local spEcho = Spring.Echo
local spGetTeamInfo = Spring.GetTeamInfo
local spGetAIInfo = Spring.GetAIInfo
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetPlayerList = Spring.GetPlayerList
local spSetTeamRulesParam = Spring.SetTeamRulesParam

local PUBLIC = { public = true }

local aiHostPlayer = {} -- teamID -> the only playerID whose messages give orders to that team

-- given by Setup
local aiTeams ---@type table<integer, string>
local teamList ---@type integer[]
local onHostChanged ---@type fun(teamID: integer)

--- aiTeams: teamID -> AI name; onHostChanged(teamID) runs when a team gets a new host
local function Setup(teams, list, hostChanged)
	aiTeams = teams
	teamList = list
	onHostChanged = hostChanged
end

local function HostOf(teamID)
	return aiHostPlayer[teamID]
end

local function IsActive(playerID)
	local _, active = spGetPlayerInfo(playerID, false)
	return active == true
end

-- deterministic successor: an active player of the same ally team, then any active player,
-- then an active spectator; the lowest playerID wins
local function ChooseSuccessor(allyId, removedPlayerID)
	local best, bestRank = nil, nil
	local players = spGetPlayerList(-1, true) or {}
	for i = 1, #players do
		local playerID = players[i] --[[@as integer]]
		if playerID ~= removedPlayerID then
			local _, active, spectator, _, playerAllyId = spGetPlayerInfo(playerID, false)
			if active then
				local rank = 3
				if not spectator then
					rank = (playerAllyId == allyId) and 1 or 2
				end
				if bestRank == nil or rank < bestRank or (rank == bestRank and playerID < best) then
					best = playerID
					bestRank = rank
				end
			end
		end
	end
	return best
end

-- the current host of the ally team's first AI team, or the player that added it in the lobby, while active
local function ChooseHost(teamID, allyId, removedPlayerID, checkActive)
	local _, _, hostingPlayerID = spGetAIInfo(teamID)
	local host = aiHostPlayer[teamID] or hostingPlayerID ---@type integer?
	if host == nil or host == removedPlayerID or (checkActive and not IsActive(host)) then
		host = ChooseSuccessor(allyId, removedPlayerID)
	end
	return host or -1 -- -1: nobody can host it
end

local function SetHost(teamID, host)
	local previous = aiHostPlayer[teamID]
	if previous == host then
		return
	end
	aiHostPlayer[teamID] = host
	onHostChanged(teamID)
	spSetTeamRulesParam(teamID, "aiHostPlayer", host, PUBLIC)
	if previous ~= nil then
		SendToUnsynced("shard_host", teamID, host)
	end
	spEcho("[AI Loader] AI team " .. teamID .. " hosted by player " .. host)
end

--- One host per ally team: the AI team with the lowest teamID decides for its ally team, and teamList keeps the
--- order deterministic. removedPlayerID: a player who left; checkActive: replace hosts that are not active
local function Register(removedPlayerID, checkActive)
	local hostByAlly = {}
	for i = 1, #teamList do
		local teamID = teamList[i]
		if aiTeams[teamID] ~= nil then
			local _, _, _, _, _, allyId = spGetTeamInfo(teamID, false)
			if hostByAlly[allyId] == nil then
				hostByAlly[allyId] = ChooseHost(teamID, allyId, removedPlayerID, checkActive)
			end
			SetHost(teamID, hostByAlly[allyId])
		end
	end
end

return {
	Setup = Setup,
	HostOf = HostOf,
	Register = Register,
}
