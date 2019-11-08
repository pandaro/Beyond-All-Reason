CountHandler = class(Module)

function CountHandler:Name()
	return "CountHandler"
end

function CountHandler:internalName()
	return "counthandler"
end

function CountHandler:Init()
	self.DebugEnabled = false

	self.factories = 0
	self.maxFactoryLevel = 0
	self.factoriesAtLevel = {}
	self.outmodedFactoryID = {}

	self.nameCount = {}
	self.nameCountFinished = {}
	self.lastNameCreated = {}
	self.lastNameFinished = {}
	self.lastNameDead = {}
	self.mexCount = 0
	self.conCount = 0
	self.conList = {}
	self.combatCount = 0
	self.battleCount = 0
	self.breakthroughCount = 0
	self.siegeCount = 0
	self.reclaimerCount = 0
	self.bigEnergyCount = 0
	self.cleanable = {}
	self.assistCount = 0
	self.nanoList = {}
	
	self.mtypeLvCount = {}
	self.mtypeCount = {veh = 0, bot = 0, air = 0, shp = 0, sub = 0, amp = 0, hov = 0 }
	
	self:InitializeNameCounts()
end

function CountHandler:InitializeNameCounts()
	for name, t in pairs(unitTable) do
		self.nameCount[name] = 0
	end
end

function CountHandler:UnitDamaged(unit, attacker,damage)
	if unit:Team() ~= self.game:GetTeamID() then
		self:EchoDebug("unit damaged", unit:Team(), unit:Name(), unit:ID())
	end
	local aname = "nil"
	if attacker then 
		if attacker:Team() ~= game:GetTeamID() then
			self:EchoDebug(unit:Name() .. " on team " .. unit:Team() .. " damaged by " .. attacker:Name() .. " on team " .. attacker:Team())
		end
	end
end
