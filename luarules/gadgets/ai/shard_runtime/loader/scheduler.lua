-- The turns of the modules and of the behaviours, one scheduler for every AI hosted on this client. Unsynced.
--
-- Only for the AI types whose class declares MScheduler, a list of module names: the modules listed there run
-- in turns, one module of one object a frame, and no longer in the Update of every frame (ShardAI:BuildHandlers).
-- A type without MScheduler is not touched: its modules get Update every frame, as before.
--
-- The turns go as in STAI's SchedulerHST: for each position of the list, every hosted AI that declares it, then
-- the next position; after the last one the list starts again. A module of the ally or global scope gets one
-- turn a round for the object that holds it, not one for each of its AIs. The rotation is rebuilt only when the
-- hosted AIs change (Changed), and goes on from the turn it was about to run, or the next one still in it.
--
-- BScheduler, a list of behaviour names (their Name()), has a rotation of its own built the same way, one turn
-- of one AI a frame, and no module call: NextBehaviourTurn only says whose turn it is, before the Update of
-- every frame, and Unit:Update gives Update to a listed behaviour only in the turn of its name for its AI. A turn
-- is not skipped when the AI has no unit with that behaviour.
--
-- During a turn, the table that every object of such a type holds as `scheduler` says whose turn it is, as the
-- fields of the same name in SchedulerHST: moduleTeam (the AI's team; nil for an ally or global module) and
-- moduleUpdate (the module's Name()), behaviourTeam and behaviourUpdate (the behaviour's Name()).

---@class ShardSchedulerTurn
---@field target table the AI, ally or global object that holds the module; the AI for a behaviour
---@field position integer
---@field team integer?
---@field name string

local state = { moduleTeam = nil, moduleUpdate = nil, behaviourTeam = nil, behaviourUpdate = nil }
local turns = {} ---@type ShardSchedulerTurn[] the rotation of the modules
local cursor = 1 -- the turn to run next
local behaviourTurns = {} ---@type ShardSchedulerTurn[] the rotation of the behaviours
local behaviourCursor = 1
local changed = true
-- object -> position -> record, so that a record outlives a rebuild
local recordsByTarget = {}
local behaviourRecordsByTarget = {}

-- given by Setup
local Call ---@type fun(target: table, name: string, ...): boolean

--- context = { Delivery }
local function Setup(context)
	Call = context.Delivery.Call
end

--- The hosted AIs, or their objects, changed: the rotation is rebuilt before the next turn
local function Changed()
	changed = true
end

local function Record(records, previous, target, position, name)
	local byPosition = records[target]
	if byPosition == nil then
		byPosition = previous[target] or {}
		records[target] = byPosition
	end
	local record = byPosition[position]
	if record == nil then
		record = { target = target, position = position, name = name }
		if target:Scope() == "team" then
			record.team = target.id
		end
		byPosition[position] = record
	end
	return record
end

-- the object that runs position for thisAI: the AI, or its ally or global object when that holds the module
local function Holder(thisAI, position)
	local held = thisAI.scheduledModules
	if held ~= nil and held[position] ~= nil then
		return thisAI
	end
	local shared = thisAI.ally
	for _ = 1, 2 do
		held = shared and shared.scheduledModules
		if held ~= nil and held[position] ~= nil then
			return shared
		end
		shared = thisAI.global
	end
	-- held by nobody yet: the AI's turn, skipped while it has no such module
	return thisAI
end

-- the place in newTurns to go on from: the first record of the old rotation, from its cursor on, still in it
local function ResumeAt(oldTurns, oldCursor, newTurns)
	local placeOf = {}
	for i = 1, #newTurns do
		placeOf[newTurns[i]] = i
	end
	local count = #oldTurns
	for k = 0, count - 1 do
		local place = placeOf[oldTurns[(oldCursor - 1 + k) % count + 1]] ---@type integer?
		if place ~= nil then
			return place
		end
	end
	return 1
end

local function Longest(AIs, field)
	local longest = 0
	for i = 1, #AIs do
		local names = AIs[i][field]
		if names ~= nil and #names > longest then
			longest = #names
		end
	end
	return longest
end

local function RebuildModules(AIs)
	local newTurns = {}
	local records = {}
	local givenAt = {} -- shared object -> the last position it got a turn at
	for position = 1, Longest(AIs, "MScheduler") do
		for i = 1, #AIs do
			local thisAI = AIs[i]
			local names = thisAI.MScheduler
			local name = names and names[position]
			if name ~= nil then
				local target = Holder(thisAI, position)
				if target == thisAI or givenAt[target] ~= position then
					givenAt[target] = position
					newTurns[#newTurns + 1] = Record(records, recordsByTarget, target, position, name)
				end
			end
		end
	end
	cursor = ResumeAt(turns, cursor, newTurns)
	turns = newTurns
	recordsByTarget = records
end

local function RebuildBehaviours(AIs)
	local newTurns = {}
	local records = {}
	for position = 1, Longest(AIs, "BScheduler") do
		for i = 1, #AIs do
			local thisAI = AIs[i]
			local names = thisAI.BScheduler
			local name = names and names[position]
			if name ~= nil then
				newTurns[#newTurns + 1] = Record(records, behaviourRecordsByTarget, thisAI, position, name)
			end
		end
	end
	behaviourCursor = ResumeAt(behaviourTurns, behaviourCursor, newTurns)
	behaviourTurns = newTurns
	behaviourRecordsByTarget = records
end

local function Rebuild()
	changed = false
	local AIs = Shard.AIs
	RebuildModules(AIs)
	RebuildBehaviours(AIs)
end

--- The turn of the behaviours for this frame, before the Update of every frame: the next AI and behaviour name
local function NextBehaviourTurn()
	if changed then
		Rebuild()
	end
	local count = #behaviourTurns
	if count == 0 then
		state.behaviourTeam = nil
		state.behaviourUpdate = nil
		return
	end
	local record = behaviourTurns[behaviourCursor] --[[@as ShardSchedulerTurn]]
	behaviourCursor = behaviourCursor % count + 1
	state.behaviourTeam = record.team
	state.behaviourUpdate = record.name
end

--- One turn: the next module in the rotation whose object holds it now
local function RunScheduledTurn()
	if changed then
		Rebuild()
	end
	local count = #turns
	for _ = 1, count do
		local record = turns[cursor] --[[@as ShardSchedulerTurn]]
		cursor = cursor % count + 1
		local target = record.target
		local held = target.scheduledModules
		if held ~= nil and held[record.position] ~= nil then
			state.moduleTeam = record.team
			state.moduleUpdate = record.name
			Call(target, "ScheduledUpdate", record.position)
			return
		end
	end
end

return {
	state = state,
	Setup = Setup,
	Changed = Changed,
	RunScheduledTurn = RunScheduledTurn,
	NextBehaviourTurn = NextBehaviourTurn,
}
