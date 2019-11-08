CountBehaviour = class(Behaviour)

function CountBehaviour:Name()
	return "CountBehaviour"
end

CountBehaviour.DebugEnabled = false


function CountBehaviour:Init()
	self.finished = false
	self.name = self.unit:Internal():Name()
	self.id = self.unit:Internal():ID()
	local uTn = unitTable[self.name]
	-- game:SendToConsole(self.name .. " " .. self.id .. " init")
	if uTn.isBuilding then
		self.position = self.unit:Internal():GetPosition() -- buildings don't move
		self.isBuilding = true
	else
		if uTn.buildOptions then
			self.isCon = true
		elseif uTn.isWeapon then
			self.isCombat = true
			self.mtypedLv = tostring(uTn.mtype)..uTn.techLevel
			self.mobileMtyped = uTn.mtype
		end
	end
	if uTn.totalEnergyOut > 750 then self.isBigEnergy = true end
	if uTn.extractsMetal > 0 then self.isMex = true end
	if battleList[self.name] then self.isBattle = true end
	if breakthroughList[self.name] then self.isBreakthrough = true end
	if self.isCombat and not battleList[self.name] and not breakthroughList[self.name] then
		self.isSiege = true
	end
	if reclaimerList[self.name] then self.isReclaimer = true end
	if cleanable[self.name] then self.isCleanable = true end
	if assistList[self.name] then self.isAssist = true end
	if nanoTurretList[self.name] then self.isNano = true end
	if self.nameCount[self.name] == nil then
		self.nameCount[self.name] = 1
	else
		self.nameCount[self.name] = self.nameCount[self.name] + 1
	end
	self:EchoDebug(self.nameCount[self.name] .. " " .. self.name .. " created")
	self.lastNameCreated[self.name] = game:Frame()
	self.unit:ElectBehaviour()
end

function CountBehaviour:OwnerBuilt()
	-- game:SendToConsole(self.name .. " " .. self.id .. " built")
	if self.nameCountFinished[self.name] == nil then
		self.nameCountFinished[self.name] = 1
	else
		self.nameCountFinished[self.name] = self.nameCountFinished[self.name] + 1
	end
	if self.isMex then self.mexCount = self.mexCount + 1 end
	if self.isCon then 
		self.conCount = self.conCount + 1 
		self.conList[self.id] = self
	end
	if self.isCombat then self.combatCount = self.combatCount + 1 end
	if self.isBattle then self.battleCount = self.battleCount + 1 end
	if self.isBreakthrough then self.breakthroughCount = self.breakthroughCount + 1 end
	if self.isSiege then self.siegeCount = self.siegeCount + 1 end
	if self.isReclaimer then self.reclaimerCount = self.reclaimerCount + 1 end
	if self.isAssist then self.assistCount = self.assistCount + 1 end
	if self.isBigEnergy then self.bigEnergyCount = self.bigEnergyCount + 1 end
	if self.isCleanable then self.cleanable[self.unit.engineID] = self.position end
	if self.isNano then 
		self.nanoList[self.id] = self.unit:Internal():GetPosition() 
		self.lastNanoBuild = self.unit:Internal():GetPosition()
	end
	self.lastNameFinished[self.name] = game:Frame()
	self:EchoDebug(self.nameCountFinished[self.name] .. " " .. self.name .. " finished")
	self.finished = true
	--mtyped leveled counters
	if self.mobileMtyped then ai.mtypeCount[self.mobileMtyped] = ai.mtypeCount[self.mobileMtyped] + 1 end
	if self.mtypedLv then
		if self.mtypeLvCount[self.mtypedLv] == nil then 
			self.mtypeLvCount[self.mtypedLv] = 1 
		else
			self.mtypeLvCount[self.mtypedLv] = self.mtypeLvCount[self.mtypedLv] + 1
		end
	end
end

function CountBehaviour:Priority()
	return 0
end

function CountBehaviour:OwnerDead()
	self.nameCount[self.name] = self.nameCount[self.name] - 1
	if self.finished then
		self.nameCountFinished[self.name] = self.nameCountFinished[self.name] - 1
		if self.isMex then self.mexCount = self.mexCount - 1 end
		if self.isCon then
			self.conCount = self.conCount - 1
			self.conList[self.id] = nil
		end
		if self.isCombat then self.combatCount = self.combatCount - 1 end
		if self.isBattle then self.battleCount = self.battleCount - 1 end
		if self.isBreakthrough then self.breakthroughCount = self.breakthroughCount - 1 end
		if self.isSiege then self.siegeCount = self.siegeCount - 1 end
		if self.isReclaimer then self.reclaimerCount = self.reclaimerCount - 1 end
		if self.isAssist then self.assistCount = self.assistCount - 1 end
		if self.isBigEnergy then self.bigEnergyCount = self.bigEnergyCount - 1 end
		if self.isCleanable then self.cleanable[self.unit.engineID] = nil end
		if self.isNano then 
			self.nanoList[self.id] = nil 
			if self.lastNanoBuild == self.unit:Internal():GetPosition() then self.lastNanoBuild = nil end
		end
		if self.mobileMtyped then ai.mtypeCount[self.mobileMtyped] = ai.mtypeCount[self.mobileMtyped] - 1 end
		if self.mtypedLv then
			self.mtypeLvCount[self.mtypedLv] = self.mtypeLvCount[self.mtypedLv] - 1
		end
	end
end
