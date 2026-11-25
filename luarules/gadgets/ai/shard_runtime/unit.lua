--- This is the definition of a unit AI!
--
-- it isn't the unit itself, but rather the mini-AI
-- that controls it
Unit = class(AIBase)

local function tracyZoneBeginMem()
	return
end
local function tracyZoneEndMem()
	return
end

if tracy and not tracy then
	Spring.Echo("Enabled Tracy support for UNIT STAI")
	tracyZoneBeginMem = function(fname)
		if logRAM then
			lastGCinfo = gcinfo()
		end
		tracy.ZoneBeginN(fname)
	end

	tracyZoneEndMem = function(fname)
		fname = fname or "STAI"
		if logRAM then
			local nowGCinfo = gcinfo()
			local delta = nowGCinfo - lastGCinfo
			if delta > 0 then
				tracy.Message(tostring(fname .. nowGCinfo - lastGCinfo))
			end
			lastGCinfo = nowGCinfo
		end
		tracy.ZoneEnd()
	end
end

-- the loader's timers (loader/timers.lua); without the loader, as in the specs, nothing is timed
local Timers = ShardTimers
local function NoTimer() end
local BeginBehaviour = Timers and Timers.BeginBehaviour or NoTimer
local EndBehaviour = Timers and Timers.EndBehaviour or NoTimer

-- The election rule STAI was written for: the first behaviour of the list wins unless a later one has a
-- priority above zero and above the best so far, so a unit always has a behaviour, even when all of them
-- return zero or less. A nil priority after the first one is an error.
local function LegacyElection(self)
	local bestBehaviour = nil
	local bestScore = -1

	for k, behaviour in pairs(self.behaviours) do
		local score = behaviour:Priority()
		if bestBehaviour == nil or (score > 0 and score > bestScore) then
			bestScore = score
			bestBehaviour = behaviour
		end
	end

	if bestBehaviour ~= nil then
		if (self.activeBehaviour ~= bestBehaviour) and (self.nextBehaviour ~= bestBehaviour) then
			if self.activeBehaviour ~= nil then
				self.activeBehaviour:PreDeactivate()
				self.activeBehaviour:Deactivate()
			end
			self.nextBehaviour = bestBehaviour
		end
	end
end

function Unit:Init()
	-- check if we were set up correctly
	if self.engineUnit == nil then
		-- oh noes, someone was meant to call SetEngineRepresentation
		-- on this before calling Init
		--
		-- @see Unit:SetEngineRepresentation
		self:Warn("Shard Unit:Init revieved a nil engineUnit :(")
	end
	self.behaviours = {}
	self.nextBehaviour = nil
	self.activeBehaviour = nil
end

--- Tell the unit AI which unit it's coontrolling
--
-- This is how it knows which unit it is
--
-- @param engineUnit the unit object ( Shard unit )
function Unit:SetEngineRepresentation(engineUnit)
	self.engineUnit = engineUnit
	self.engineID = engineUnit:ID()
end

--- Which unit is this controlling?
--
-- This object is great at being a mini-AI
-- for controlling a unit, but which unit?!
--
-- @return a shard unit object
function Unit:Internal()
	return self.engineUnit
end

function Unit:Update()
	-- Handle activating a new behaviour if we switched
	if self.nextBehaviour ~= nil then
		self.activeBehaviour = self.nextBehaviour
		self.nextBehaviour = nil
		local active = self.activeBehaviour
		local startTimer = BeginBehaviour()
		active:PreActivate()
		active:Activate()
		EndBehaviour(startTimer, self.ai, active, "Activate")
	end

	-- Pass the update event to the behaviours: those whose Name() the AI class lists in BScheduler only in the
	-- turn of that name for this AI, the others every time
	local ai = self.ai ---@type table?
	local inTurns = ai and ai.scheduledBehaviours
	local scheduler = ai and ai.scheduler
	if inTurns == nil or scheduler == nil then
		for k, behaviour in pairs(self.behaviours) do
			--self.game:StartTimer(behaviour:Name() .. ' Unit')
			--tracyZoneBeginMem('STAI:'..behaviour:Name())
			local startTimer = BeginBehaviour()
			behaviour:Update()
			EndBehaviour(startTimer, self.ai, behaviour, "Update")
			--tracyZoneEndMem('STAI:'..behaviour:Name())
			--self.game:StopTimer(behaviour:Name() .. ' Unit')
		end
		return
	end
	local turn = nil
	if scheduler.behaviourTeam == ai.id then
		turn = scheduler.behaviourUpdate
	end
	for _, behaviour in pairs(self.behaviours) do
		local name = behaviour:Name()
		if name == turn or inTurns[name] == nil then
			local startTimer = BeginBehaviour()
			behaviour:Update()
			EndBehaviour(startTimer, self.ai, behaviour, "Update")
		end
	end
	--  		RAM = gcinfo() - RAM
	--  		if RAM > 0 then
	--  			Spring.Echo(--[[behaviour:Name(),]]self:Internal():Name(), RAM , 'RAM')
	-- 		end
end

function Unit:GameEnd()
	for k, v in pairs(self.behaviours) do
		local startTimer = BeginBehaviour()
		v:GameEnd()
		EndBehaviour(startTimer, self.ai, v, "GameEnd")
	end
end

function Unit:UnitCreated(unit, unitDefId, teamId, builderId)
	if unit then -- TEMPORARY FIX
		if unit.engineID == self.engineID then
			for k, v in pairs(self.behaviours) do
				--self.game:StartTimer(v:Name() .. 'OCreated')
				local startTimer = BeginBehaviour()
				v:OwnerCreated(unit, unitDefId, teamId, builderId)
				EndBehaviour(startTimer, self.ai, v, "OwnerCreated")
				-- 				self.game:StopTimer(v:Name() .. 'OCreated')
			end
		end
		for k, v in pairs(self.behaviours) do
			--self.game:StartTimer(v:Name() .. 'Created')
			local startTimer = BeginBehaviour()
			v:UnitCreated(unit, unitDefId, teamId, builderId)
			EndBehaviour(startTimer, self.ai, v, "UnitCreated")
			--self.game:StopTimer(v:Name() .. 'Created')

		end
	end
end

function Unit:UnitBuilt(unit)
	if unit.engineID == self.engineID then
		self:ElectBehaviour()
		for k, v in pairs(self.behaviours) do
			--self.game:StartTimer(v:Name() .. 'Ubuilt')
			local startTimer = BeginBehaviour()
			v:OwnerBuilt()
			EndBehaviour(startTimer, self.ai, v, "OwnerBuilt")
			-- 			self.game:StopTimer(v:Name() .. 'Ubuilt')
		end
	else
		for k, v in pairs(self.behaviours) do
			--self.game:StartTimer(v:Name() .. 'Obuilt')
			local startTimer = BeginBehaviour()
			v:UnitBuilt(unit)
			EndBehaviour(startTimer, self.ai, v, "UnitBuilt")
			-- 			self.game:StopTimer(v:Name() .. 'Obuilt')
		end
	end
end

function Unit:UnitDead(unit)

	if unit.engineID == self.engineID then
		if self.behaviours then
			-- game:SendToConsole("unit died, removing behaviours", self.engineID, self:Internal():Name())
			for k, v in pairs(self.behaviours) do
				local startTimer = BeginBehaviour()
				v:OwnerDead()
				EndBehaviour(startTimer, self.ai, v, "OwnerDead")
				self.behaviours[k] = nil
			end
			self.behaviours = nil
		end
		self.engineUnit = nil
	else
		for k, v in pairs(self.behaviours) do
			local startTimer = BeginBehaviour()
			v:UnitDead(unit)
			EndBehaviour(startTimer, self.ai, v, "UnitDead")
		end
	end
end

function Unit:UnitDamaged(unit, attacker, damage)
	if unit.engineID == self.engineID then
		-- 		--self.game:StartTimer(v:Name() .. 'G')
		for k, v in pairs(self.behaviours) do

			local startTimer = BeginBehaviour()
			v:OwnerDamaged(attacker, damage)
			EndBehaviour(startTimer, self.ai, v, "OwnerDamaged")

		end
	else
		for k, v in pairs(self.behaviours) do

			local startTimer = BeginBehaviour()
			v:UnitDamaged(unit, attacker, damage)
			EndBehaviour(startTimer, self.ai, v, "UnitDamaged")

		end
		-- 		--self.game:StopTimer(v:Name() .. 'G')
	end
end

function Unit:UnitIdle(unit)
	if unit.engineID == self.engineID then
		for k, v in pairs(self.behaviours) do
			--self.game:StartTimer(v:Name() .. 'I')
			local startTimer = BeginBehaviour()
			v:OwnerIdle()
			EndBehaviour(startTimer, self.ai, v, "OwnerIdle")
			--self.game:StopTimer(v:Name() .. 'I')
		end
	else
		for k, v in pairs(self.behaviours) do
			--self.game:StartTimer(v:Name() .. 'I')
			local startTimer = BeginBehaviour()
			v:UnitIdle(unit)
			EndBehaviour(startTimer, self.ai, v, "UnitIdle")
			--self.game:StopTimer(v:Name() .. 'I')
		end
	end
end

function Unit:UnitMoveFailed(unit)
	if unit.engineID == self.engineID then
		for k, v in pairs(self.behaviours) do
			local startTimer = BeginBehaviour()
			v:OwnerMoveFailed()
			EndBehaviour(startTimer, self.ai, v, "OwnerMoveFailed")
		end
	else
		for k, v in pairs(self.behaviours) do
			local startTimer = BeginBehaviour()
			v:UnitMoveFailed(unit)
			EndBehaviour(startTimer, self.ai, v, "UnitMoveFailed")
		end
	end
end

-- Adds a new behaviour to this unit.
--
-- It does not activate that behaviour though
--
-- @param behaviour The behaviour to add
function Unit:AddBehaviour(behaviour)
	table.insert(self.behaviours, behaviour)
end

--- Which behaviour has control of this unit?
--
-- @return the behaviour or nil
function Unit:ActiveBehaviour()
	return self.activeBehaviour
end

--- Does this unit have behaviours?
--
-- Units with no behaviours do not get events
--
-- @return true or false
function Unit:HasBehaviours()
	if self.behaviours ~= nil then
		if #self.behaviours > 0 then
			return true
		end
	end
	return false
end

--- Picks and activates the best behaviour to control this unit!
--
-- Only a priority above zero wins; a nil priority counts as zero, and on a tie the first in the list wins.
-- If no behaviour has a priority above zero, no behaviour is active: the active one is deactivated and a
-- behaviour waiting to be activated is dropped.
--
-- The elected behaviour will be activated on the next update,
-- the currently activated behaviour is deactivated immediately.
--
-- If the current behaviour is elected, there is no change
-- The active behaviour has full control of the unit
--
-- An AI class with legacyElection = true elects with LegacyElection instead.
function Unit:ElectBehaviour()
	-- Check if we have any behaviours to elect
	if self:HasBehaviours() == false then
		return -- exit early
	end
	local ai = self.ai ---@type table?
	if ai ~= nil and ai.legacyElection == true then
		LegacyElection(self)
		return
	end

	local bestBehaviour = nil
	local bestScore = 0
	for _, behaviour in ipairs(self.behaviours) do
		local score = behaviour:Priority() or 0
		if score > bestScore then
			bestScore = score
			bestBehaviour = behaviour
		end
	end

	-- the active behaviour and the one waiting for the next update are never both set
	self.nextBehaviour = nil
	local active = self.activeBehaviour ---@type table?
	if bestBehaviour == active then
		return
	end
	self.nextBehaviour = bestBehaviour
	if active ~= nil then
		self.activeBehaviour = nil
		active:PreDeactivate()
		active:Deactivate()
	end
end
