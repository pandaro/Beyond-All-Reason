-- The units the ally team sees: los and radar, [unitID] = true, from the engine's sight events.
--
-- A starting point, shared by the AIs of an ally team: the framework filters nothing, so an AI that wants
-- something else puts its own perceptionhandler.lua in its folder, and one that uses none reads every unit.
PerceptionHandler = class(Module)

function PerceptionHandler:Name()
	return "PerceptionHandler"
end

function PerceptionHandler:internalName()
	return "perceptionhandler"
end

function PerceptionHandler:Scope()
	return "ally"
end

function PerceptionHandler:Init()
	self.los = {}
	self.radar = {}
end

function PerceptionHandler:UnitEnteredLos(unitID)
	self.los[unitID] = true
end

function PerceptionHandler:UnitLeftLos(unitID)
	self.los[unitID] = nil
end

function PerceptionHandler:UnitEnteredRadar(unitID)
	self.radar[unitID] = true
end

function PerceptionHandler:UnitLeftRadar(unitID)
	self.radar[unitID] = nil
end

function PerceptionHandler:UnitDead(engineunit)
	local unitID = engineunit:ID()
	self.los[unitID] = nil
	self.radar[unitID] = nil
end

function PerceptionHandler:Sees(unitID)
	return self.los[unitID] == true
end

function PerceptionHandler:OnRadar(unitID)
	return self.radar[unitID] == true
end
