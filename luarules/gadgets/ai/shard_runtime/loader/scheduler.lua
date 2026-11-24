-- The turns of the modules, one scheduler for every AI hosted on this client. Unsynced.
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
-- During a turn, the table that every object of such a type holds as `scheduler` says whose turn it is, as the
-- fields of the same name in SchedulerHST: moduleTeam (the AI's team; nil for an ally or global module) and
-- moduleUpdate (the module's Name()).
--
-- BScheduler, the list of behaviours, is not read: behaviours run in UnitHandler's Update, a module of the AI.

---@class ShardSchedulerTurn
---@field target table the AI, ally or global object that holds the module
---@field position integer
---@field team integer?
---@field name string

local state = { moduleTeam = nil, moduleUpdate = nil }
local turns = {} ---@type ShardSchedulerTurn[] the rotation
local cursor = 1 -- the turn to run next
local changed = true
local recordsByTarget = {} -- object -> position -> record, so that a record outlives a rebuild

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

local function Record(records, target, position, name)
	local byPosition = records[target]
	if byPosition == nil then
		byPosition = recordsByTarget[target] or {}
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

local function Rebuild()
	changed = false
	local AIs = Shard.AIs
	local longest = 0
	for i = 1, #AIs do
		local names = AIs[i].MScheduler
		if names ~= nil and #names > longest then
			longest = #names
		end
	end
	local newTurns = {}
	local records = {}
	local givenAt = {} -- shared object -> the last position it got a turn at
	for position = 1, longest do
		for i = 1, #AIs do
			local thisAI = AIs[i]
			local names = thisAI.MScheduler
			local name = names and names[position]
			if name ~= nil then
				local target = Holder(thisAI, position)
				if target == thisAI or givenAt[target] ~= position then
					givenAt[target] = position
					newTurns[#newTurns + 1] = Record(records, target, position, name)
				end
			end
		end
	end

	local placeOf = {}
	for i = 1, #newTurns do
		placeOf[newTurns[i]] = i
	end
	local nextPlace = 1
	local count = #turns
	for k = 0, count - 1 do
		local place = placeOf[turns[(cursor - 1 + k) % count + 1]] ---@type integer?
		if place ~= nil then
			nextPlace = place
			break
		end
	end
	turns = newTurns
	cursor = nextPlace
	recordsByTarget = records
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
}
