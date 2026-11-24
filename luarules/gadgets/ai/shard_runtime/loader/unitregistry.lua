-- The units the loader keeps track of, on the hosting client. Unsynced.
--
-- Provisional: the unit tables of every AI (own, allied, enemy and neutral units) are omniscient, whatever the
-- AI can see; game:GetUnits(), GetFriendlies() and GetEnemies() read them, as with the old loader.
--
-- A dead unit's ShardUnit stays in Shard.unitsByID for 30 s of game, with its type and name, because the AIs
-- still ask the game for units they saw die; a ring of three parallel arrays (unit ID, ShardUnit, frame it
-- leaves the cache) keeps them in the order they died, and grows by doubling when full.

local gaiaTeamID = Spring.GetGaiaTeamID()

local DEAD_UNIT_FRAMES = 900

local deadIDs, deadUnits, deadExpiry = {}, {}, {}
local deadCapacity, deadHead, deadCount = 0, 1, 0

-- unit tables (provisional) -------------------------------------------------------------------------

local function NewUnitTables(thisAI)
	thisAI.ownUnitIds = {}
	thisAI.friendlyUnitIds = {}
	thisAI.alliedUnitIds = {}
	thisAI.enemyUnitIds = {}
	thisAI.neutralUnitIds = {}
end

local function AddToUnitTables(unitID, teamID)
	local AIs = Shard.AIs
	for i = 1, #AIs do
		local thisAI = AIs[i]
		if teamID == thisAI.id then
			thisAI.ownUnitIds[unitID] = true
			thisAI.friendlyUnitIds[unitID] = true
		elseif thisAI.alliedTeamIds[teamID] then
			thisAI.alliedUnitIds[unitID] = true
			thisAI.friendlyUnitIds[unitID] = true
		elseif teamID == gaiaTeamID then
			thisAI.neutralUnitIds[unitID] = true
		else
			thisAI.enemyUnitIds[unitID] = true
		end
	end
end

local function RemoveFromUnitTables(unitID)
	local AIs = Shard.AIs
	for i = 1, #AIs do
		local thisAI = AIs[i]
		thisAI.ownUnitIds[unitID] = nil
		thisAI.friendlyUnitIds[unitID] = nil
		thisAI.alliedUnitIds[unitID] = nil
		thisAI.enemyUnitIds[unitID] = nil
		thisAI.neutralUnitIds[unitID] = nil
	end
end

-- dead units ------------------------------------------------------------------------------------------

local function GrowDeadRing()
	local capacity = math.max(64, deadCapacity * 2)
	local ids, units, expiry = {}, {}, {}
	for k = 1, deadCount do
		local i = (deadHead + k - 2) % deadCapacity + 1
		ids[k], units[k], expiry[k] = deadIDs[i], deadUnits[i], deadExpiry[i]
	end
	deadIDs, deadUnits, deadExpiry = ids, units, expiry
	deadCapacity, deadHead = capacity, 1
end

--- Marks the ShardUnit of a dead unit destroyed and keeps it in the cache for DEAD_UNIT_FRAMES
local function UnitDied(unitID, unit, frame)
	unit.destroyed = true
	if deadCount == deadCapacity then
		GrowDeadRing()
	end
	local i = (deadHead + deadCount - 1) % deadCapacity + 1
	deadIDs[i], deadUnits[i], deadExpiry[i] = unitID, unit, frame + DEAD_UNIT_FRAMES
	deadCount = deadCount + 1
end

--- Drops from the cache the dead units whose time is over, unless their ID already belongs to a new unit
local function ExpireDeadUnits(frame)
	while deadCount > 0 and deadExpiry[deadHead] <= frame do
		local unitID = deadIDs[deadHead]
		if Shard.unitsByID[unitID] == deadUnits[deadHead] then
			Shard:unshardify_unit(unitID)
		end
		deadUnits[deadHead] = nil
		deadHead = deadHead % deadCapacity + 1
		deadCount = deadCount - 1
	end
end

return {
	NewUnitTables = NewUnitTables,
	AddToUnitTables = AddToUnitTables,
	RemoveFromUnitTables = RemoveFromUnitTables,
	UnitDied = UnitDied,
	ExpireDeadUnits = ExpireDeadUnits,
}
