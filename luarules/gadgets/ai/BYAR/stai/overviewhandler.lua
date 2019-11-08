OverviewHandler = class(Module)

function OverviewHandler:Name()
	return "OverviewHandler"
end

function OverviewHandler:internalName()
	return "overviewhandler"
end

function OverviewHandler:Init()
	self.DebugEnabled = false

	self.heavyPlasmaLimit = 3
	self.AAUnitPerTypeLimit = 3
	self.nukeLimit = 1
	self.tacticalNukeLimit = 1

	self.lastCheckFrame = 0
	self.lastEconCheckFrame = 0

	self:StaticEvaluate()
	self:Evaluate()
end

function OverviewHandler:Update()
	self:Evaluate()
end

function OverviewHandler:Evaluate()
	local f = self.game:Frame()
	if f > self.lastCheckFrame + 240 then
		self:EvaluateSituation()
		self.lastCheckFrame = f
	end
	if f > self.lastEconCheckFrame + 22 then
		self:SetEconomyAliases()
		self.lastEconCheckFrame = f
	end
end

function OverviewHandler:EvaluateSituation()
	self.haveAdvFactory = self.factoriesAtLevel[3] and #self.factoriesAtLevel[3] ~= 0
	self.haveExpFactory = self.factoriesAtLevel[5] and #self.factoriesAtLevel[5] ~= 0
	
	self.needToReclaim = self.Metal.full < 0.5 and self.wreckCount > 0
	self.AAUnitPerTypeLimit = math.ceil(self.turtlehandler:GetTotalPriority() / 4)
	self.heavyPlasmaLimit = math.ceil(self.combatCount / 10)
	self.nukeLimit = math.ceil(self.combatCount / 50)
	self.tacticalNukeLimit = math.ceil(self.combatCount / 40)

	local attackCounter = self.attackhandler:GetCounter()
	local couldAttack = self.couldAttack >= 1 or self.couldBomb >= 1
	local bombingTooExpensive = self.bomberhandler:GetCounter() == maxBomberCounter
	local attackTooExpensive = attackCounter == maxAttackCounter
	local controlMetalSpots = self.mexCount > #self.mobNetworkMetals["air"][1] * 0.4
	local needUpgrade = couldAttack or bombingTooExpensive or attackTooExpensive

	self.keepCommanderSafe = self.totalEnemyThreat > 3000 -- turn commander into assistant, for now above paranoidCommander because the assistant behaviour isn't helpful or safe
	self.paranoidCommander = self.totalEnemyThreat > 2500 -- move commander to safest place assisting a factory

	self:EchoDebug(self.totalEnemyThreat .. " " .. self.totalEnemyImmobileThreat .. " " .. self.totalEnemyMobileThreat)
	-- build siege units if the enemy is turtling, if a lot of our attackers are getting destroyed, or if we control over 40% of the metal spots
	self.plasmaRocketBotRatio = 1
	if self.totalEnemyMobileThreat and self.totalEnemyMobileThreat > 0 and self.totalEnemyImmobileThreat and self.totalEnemyImmobileThreat > 0 then
		self.plasmaRocketBotRatio = 1 - ((self.totalEnemyImmobileThreat / self.totalEnemyThreat) / 2.5)
		self:EchoDebug("plasma/rocket bot ratio: " .. self.plasmaRocketBotRatio)
	end
	self.needSiege = (self.totalEnemyImmobileThreat > self.totalEnemyMobileThreat * 3.5 and self.totalEnemyImmobileThreat > 50000) or attackCounter >= siegeAttackCounter or controlMetalSpots
	local needAdvanced = (self.Metal.income > 18 or controlMetalSpots) and self.factories > 0 and (needUpgrade or self.lotsOfMetal)
	if needAdvanced ~= self.needAdvanced then
		self.needAdvanced = needAdvanced
		self.factorybuildershandler:UpdateFactories()
	end
	self.needAdvanced = needAdvanced
	local needExperimental
	self.needNukes = false
	if self.Metal.income > 50 and self.haveAdvFactory and (needUpgrade or self.BigEco) and self.enemyBasePosition then
		if not self.haveExpFactory then
			for i, factory in pairs(self.factoriesAtLevel[self.maxFactoryLevel]) do
				for expFactName, _ in pairs(expFactories) do
					for _, mtype in pairs(factoryMobilities[expFactName]) do
						local myNet = self.maphandler:MobilityNetworkHere(mtype, factory.position)
						local enemyNet = self.maphandler:MobilityNetworkHere(mtype, self.enemyBasePosition)
						if myNet and enemyNet and myNet == enemyNet then
							needExperimental = true
							break
						end
					end
				end
			end
		end
		self.needNukes = true
	end
	if needExperimental ~= self.needExperimental then
		self.factorybuildershandler:UpdateFactories()
	end
	self.needExperimental = needExperimental
	self:EchoDebug("need experimental? " .. tostring(self.needExperimental) .. ", need nukes? " .. tostring(self.needNukes) .. ", have advanced? " .. tostring(self.haveAdvFactory) .. ", need upgrade? " .. tostring(needUpgrade) .. ", have enemy base position? " .. tostring(self.enemyBasePosition))
	self:EchoDebug("metal income: " .. self.Metal.income .. "  combat units: " .. self.combatCount)
	self:EchoDebug("have advanced? " .. tostring(self.haveAdvFactory) .. " have experimental? " .. tostring(self.haveExpFactory))
	self:EchoDebug("need advanced? " .. tostring(self.needAdvanced) .. "  need experimental? " .. tostring(self.needExperimental))
	self:EchoDebug("need advanced? " .. tostring(self.needAdvanced) .. ", need upgrade? " .. tostring(needUpgrade) .. ", have attacked enough? " .. tostring(couldAttack) .. " (" .. self.couldAttack .. "), have " .. self.factories .. " factories, " .. math.floor(self.Metal.income) .. " metal income")
end

function OverviewHandler:SetEconomyAliases()
	self.realMetal = self.Metal.income / self.Metal.usage
	self.realEnergy = self.Energy.income / self.Energy.usage
	self.scaledMetal = self.Metal.reserves * self.realMetal
	self.scaledEnergy = self.Energy.reserves * self.realEnergy
	self.extraEnergy = self.Energy.income - self.Energy.usage
	self.extraMetal = self.Metal.income - self.Metal.usage
	local enoughMetalReserves = math.min(self.Metal.income, self.Metal.capacity * 0.1)
	local lotsMetalReserves = math.min(self.Metal.income * 10, self.Metal.capacity * 0.5)
	local enoughEnergyReserves = math.min(self.Energy.income * 2, self.Energy.capacity * 0.25)
	-- local lotsEnergyReserves = math.min(self.Energy.income * 3, self.Energy.capacity * 0.5)
	self.energyTooLow = self.Energy.reserves < enoughEnergyReserves or self.Energy.income < 40
	self.energyOkay = self.Energy.reserves >= enoughEnergyReserves and self.Energy.income >= 40
	self.metalTooLow = self.Metal.reserves < enoughMetalReserves
	self.metalOkay = self.Metal.reserves >= enoughMetalReserves
	self.metalBelowHalf = self.Metal.reserves < lotsMetalReserves
	self.metalAboveHalf = self.Metal.reserves >= lotsMetalReserves
	local attackCounter = self.attackhandler:GetCounter()
	self.notEnoughCombats = self.combatCount < attackCounter * 0.6
	self.farTooFewCombats = self.combatCount < attackCounter * 0.2
	
	self.underReserves = self.Metal.full < 0.3 or self.Energy.full < 0.3
	self.aboveReserves = self.Metal.full > 0.7 and self.Energy.full > 0.7
	self.normalReserves = self.Metal.full > 0.5 and self.Energy.full > 0.5
	
	self.LittleEco = self.Energy.income < 1000 and self.Metal.income < 30
	self.BigEco = self.Energy.income > 5000 and self.Metal.income > 100 and self.Metal.reserves > 4000 and self.factoryBuilded['air'][1] > 2 and self.combatCount > 40
	self.lotsOfMetal = self.Metal.income > 30 and self.Metal.full > 0.75 and self.mexCount > #self.mobNetworkMetals["air"][1] * 0.5
end

function OverviewHandler:StaticEvaluate()
	self.needAmphibiousCons = self.hasUWSpots and self.mobRating["sub"] > self.mobRating["bot"] * 0.75
end
