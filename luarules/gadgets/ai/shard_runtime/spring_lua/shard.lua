local Shard = {}

Shard.resourceIds = { "metal", "energy" }
Shard.resourceKeyAliases = {
	currentLevel = "reserves",
	storage = "capacity",
	expense = "usage",
}
Shard.unitsByID = {}
Shard.unittypesByID = {}
Shard.featuresByID = {}
Shard.shardResource = {}

function Shard:shardify_resource(luaResource)
	for key, value in pairs(luaResource) do
		local newKey = self.resourceKeyAliases[key] or key
		Shard.shardResource[newKey] = value
	end
	return Shard.shardResource
end

-- A unit that died stays a while, marked destroyed, as the loader keeps it; once the engine gives its ID to a new
-- unit, the new one takes its place. An ID that is neither cached nor valid has no unit.
function Shard:shardify_unit(unitID)
	if not unitID then
		return
	end
	local unit = self.unitsByID[unitID]
	if unit ~= nil and not unit.destroyed then
		return unit
	end
	if not Spring.ValidUnitID(unitID) then
		return unit
	end
	unit = ShardUnit(unitID)
	self.unitsByID[unitID] = unit
	return unit
end

function Shard:unshardify_unit(unitID)
	if not unitID then
		return
	end
	self.unitsByID[unitID] = nil
end

function Shard:shardify_unittype(unitDefID)
	if not unitDefID then
		Spring.Echo(
			'shard: error: shardify_unittype recieved "' .. unitDefID .. '" of type "' .. type(unitDefID) .. '" '
		)
		return nil
	end
	if not self.unittypesByID[unitDefID] then
		local unittype = ShardUnitType(unitDefID)
		self.unittypesByID[unitDefID] = unittype
	end
	return self.unittypesByID[unitDefID]
end

function Shard:shardify_damage(damage, weaponDefID, paralyzer, projectileID, engineAttacker)
	local sharddamage = ShardSpringDamage()
	sharddamage:Init(damage, weaponDefID, paralyzer, projectileID, engineAttacker)
	return sharddamage
end

function Shard:shardify_feature(featureID)
	if not featureID then
		return
	end
	if not self.featuresByID[featureID] then
		local shardfeature = ShardSpringFeature()
		shardfeature:Init(featureID)
		self.featuresByID[featureID] = shardfeature
	end
	return self.featuresByID[featureID]
end

function Shard:unshardify_feature(featureID)
	if not featureID then
		return
	end
	self.featuresByID[featureID] = nil
end

return Shard
