-- Which AI teams of the game may run: for each AI type, the MAX_INSTANCES_PER_AI_TYPE teams with the lowest
-- teamIDs. Every client computes it from the same team list, so all agree without exchanging anything, and a new
-- host does not change it. Included by the synced relay and by the unsynced loader. Pure: synced code may include it.

local MAX_INSTANCES_PER_AI_TYPE = 2

local Admission = { MAX_INSTANCES_PER_AI_TYPE = MAX_INSTANCES_PER_AI_TYPE }

--- aiTeams: teamID -> AI name. Returns teamID -> true for the teams that may run their AI
---@param aiTeams table<integer, string>
---@param maxInstances integer? replaces MAX_INSTANCES_PER_AI_TYPE, for the specs
---@return table<integer, true>
function Admission.Admitted(aiTeams, maxInstances)
	maxInstances = maxInstances or MAX_INSTANCES_PER_AI_TYPE
	local teamIDs = {} ---@type integer[]
	for teamID in pairs(aiTeams) do
		teamIDs[#teamIDs + 1] = teamID
	end
	table.sort(teamIDs)
	local admitted = {}
	local countByType = {}
	for i = 1, #teamIDs do
		local teamID = teamIDs[i]
		local aiName = aiTeams[teamID]
		local count = countByType[aiName] or 0
		if count < maxInstances then
			admitted[teamID] = true
			countByType[aiName] = count + 1
		end
	end
	return admitted
end

return Admission
