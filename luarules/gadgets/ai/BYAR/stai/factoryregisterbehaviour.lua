FactoryRegisterBehaviour = class(Behaviour)

function FactoryRegisterBehaviour:Name()
	return "FactoryRegisterBehaviour"
end

FactoryRegisterBehaviour.DebugEnabled = false


function FactoryRegisterBehaviour:Init()
    self.name = self.unit:Internal():Name()
    self.id = self.unit:Internal():ID()
    self.position = self.unit:Internal():GetPosition() -- factories don't move
    self.exitRect = {
    	x1 = self.position.x - 40,
    	z1 = self.position.z - 40,
    	x2 = self.position.x + 40,
    	z2 = self.position.z + 40,
	}
	self.sides = factoryExitSides[self.name]
    self.level = unitTable[self.name].techLevel

    self.factoryUnderConstruction = self.id
	self:EchoDebug('starting building of ' ..self.name)
end

function FactoryRegisterBehaviour:OwnerBuilt()
	-- don't add factories to factory location table until they're done
	self.finished = true
	self:Register()
	self.overviewhandler:EvaluateSituation()
	self.factorybuildershandler:UpdateFactories()
end

function FactoryRegisterBehaviour:Priority()
	return 0
end

function FactoryRegisterBehaviour:OwnerDead()
	if self.factoryUnderConstruction == self.id then self.factoryUnderConstruction = false end
	-- game:SendToConsole("factory " .. self.name .. " died")
	if self.finished then
		self:Unregister()
		self.overviewhandler:EvaluateSituation()
		ai.factorybuildershandler:UpdateFactories()
	end
end

function FactoryRegisterBehaviour:Unregister()
	self.factories = self.factories - 1
	local un = self.name
    local level = self.level
   	self:EchoDebug("factory " .. un .. " level " .. level .. " unregistering")
   	for i, factory in pairs(self.factoriesAtLevel[level]) do
   		if factory == self then
   			table.remove(self.factoriesAtLevel[level], i)
   			break
   		end
   	end
    local maxLevel = 0
    -- reassess maxFactoryLevel
    for level, factories in pairs(self.factoriesAtLevel) do
    	if #factories > 0 and level > maxLevel then
    		maxLevel = level
    	end
    end
    self.maxFactoryLevel = maxLevel
	-- game:SendToConsole(self.factories .. " factories")
	
	if self.factoryUnderConstruction == self.id then self.factoryUnderConstruction = false end
	local mtype = factoryMobilities[self.name][1]
	local network = self.maphandler:MobilityNetworkHere(mtype,self.position)
	-- self:EchoDebug(mtype, network, self.factoryBuilded[mtype], self.factoryBuilded[mtype][network], self.name, unitTable[self.name], unitTable[self.name].techLevel)
	if self.factoryBuilded[mtype] and self.factoryBuilded[mtype][network] then
		self.factoryBuilded[mtype][network] = self.factoryBuilded[mtype][network] - self.level
	end
	self:EchoDebug('factory '  ..self.name.. ' network '  .. mtype .. '-' .. network .. ' level ' .. self.factoryBuilded[mtype][network] .. ' subtract tech '.. self.level)
end

function FactoryRegisterBehaviour:Register()
	if self.factories ~= nil then
		self.factories = self.factories + 1
	else
		self.factories = 1
	end
	-- register maximum factory level
    local un = self.name
    local level = self.level
    self:EchoDebug("factory " .. un .. " level " .. level .. " registering")
	if self.factoriesAtLevel[level] == nil then
		self.factoriesAtLevel[level] = {}
	end
	table.insert(self.factoriesAtLevel[level], self)
	if level > self.maxFactoryLevel then
		-- so that it will start producing combat units
		self.attackhandler:NeedLess(nil, 2)
		self.bomberhandler:NeedLess()
		self.bomberhandler:NeedLess()
		self.raidhandler:NeedMore(nil, 2)
		-- set the current maximum factory level
		self.maxFactoryLevel = level
	end
	-- game:SendToConsole(self.factories .. " factories")
	
	if self.factoryUnderConstruction == self.id then self.factoryUnderConstruction = false end
	local mtype = factoryMobilities[self.name][1]
	local network = self.maphandler:MobilityNetworkHere(mtype,self.position) or 0
	self.factoryBuilded[mtype][network] = (self.factoryBuilded[mtype][network] or 0) + self.level
	self:EchoDebug('factory '  ..self.name.. ' network '  .. mtype .. '-' .. network .. ' level ' .. self.factoryBuilded[mtype][network] .. ' adding tech '.. self.level)
end
