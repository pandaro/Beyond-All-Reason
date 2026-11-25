shard_include("astarclass")
shard_include("toolbox")

Tool = class(Module)

function Tool:Name()
	return "Tool"
end

function Tool:internalName()
	return "tool"
end

function Tool:Scope()
	return "team"
end

for name, func in pairs(Toolbox) do --the Toolbox helpers answer as self.ai.tool:<name> too, with Toolbox as self
	if type(func) == "function" then
		Tool[name] = function(_, ...)
			return func(Toolbox, ...)
		end
	end
end

sqrt = math.sqrt
random = math.random
pi = math.pi
halfPi = pi / 2
twicePi = pi * 2
cos = math.cos
sin = math.sin
atan2 = math.atan2
floor = math.floor
ceil = math.ceil
abs = math.abs
min = math.min
max = math.max

Tool.COLOURS = Toolbox.COLOURS --the same table
Tool._TABLES = {}
Tool.tablerez = 0
Tool.tablenew = 0
function Tool:RezTable()
	if self.DebugEnabled then
		self:EchoDebug("#RezTable", #self._TABLES, self.tablerez, self.tablenew)
	end
	if self._TABLES[1] then
		self.tablerez = self.tablerez + 1
		return table.remove(self._TABLES)
	end
	self.tablenew = self.tablenew + 1
	return {}
end

-- Function to recursively process a table and discard everything that is not a table
function Tool:KillTable(t)

	if not t or type(t) ~= "table" then
		if self.DebugEnabled then
			self:EchoDebug("incorrect type in KillTable", t, type(t))
		end
		return
	end
	--self:EchoDebug("SIT_TABLE: Before clearing", t)
	--if type(t) == 'table' then

	for key, value in pairs(t) do

		if type(value) == "table" then
			self:KillTable(value)
		end
		t[key] = nil
		if next(t) == nil then
			table.insert(self._TABLES, t)
			--t = nil
		end
	end
	if self.DebugEnabled then
		self:EchoDebug("#KillTable", #self._TABLES)
	end
	return nil
end

function Tool:ResetTable(t)
	self:KillTable(t)
	return self:RezTable()
end

function Tool:GiveOrder(id, cmd, parameters, options, method)
	if not id or not cmd or not parameters or not options or not method then
		self:EchoDebug("Serialize Order missing parameters", id, cmd, parameters, options, method)
		return
	end
	--if type(id) ~= ('number' or 'table') or type(cmd) ~= ('number' or 'table') or type(parameters) ~= ('number' or 'table') or type(options) ~= ('number' or 'table') or type(method) ~= 'string' then
	--	self:EchoDebug('Serialize Order wrong arg types',type(id),type(cmd),type(parameters),type(options),type(method))
	--	return
	--end
	return game:GiveOrder(id, cmd, parameters, options, method)

end

function Tool:RandomAway(pos, dist, opposite, angle)
	if angle == nil then
		angle = random() * twicePi
	end
	local mapSize = self.ai.map:MapDimensions()
	local maxElmosX = mapSize.x * 8
	local maxElmosZ = mapSize.z * 8
	local away = api.Position()
	away.x = pos.x + dist * cos(angle)
	away.z = pos.z - dist * sin(angle)
	away.y = pos.y + 0
	if away.x < 1 then
		away.x = 1
	elseif away.x > maxElmosX - 1 then
		away.x = maxElmosX - 1
	end
	if away.z < 1 then
		away.z = 1
	elseif away.z > maxElmosZ - 1 then
		away.z = maxElmosZ - 1
	end
	if opposite then
		angle = twicePi - angle
		return away, Tool:RandomAway(pos, dist, false, angle)
	else
		return away
	end
end

function Tool:RandomAway2(pos, dist, opposite, angle, away)
	if angle == nil then
		angle = random() * twicePi
	end
	away = away or {}
	-- 	local mapSize = self.ai.map:MapDimensions()
	-- 	local maxElmosX = mapSize.x * 8
	-- 	local maxElmosZ = mapSize.z * 8
	away.x, away.y, away.z = 0, 0, 0
	away.x = pos.x + dist * cos(angle)
	away.z = pos.z - dist * sin(angle)
	away.y = pos.y + 0
	if away.x < 1 then
		away.x = 1
	elseif away.x > self.ai.maphst.elmoMapSizeX - 1 then
		away.x = self.ai.maphst.elmoMapSizeX - 1
	end
	if away.z < 1 then
		away.z = 1
	elseif away.z > self.ai.maphst.elmoMapSizeZ - 1 then
		away.z = self.ai.maphst.elmoMapSizeZ - 1
	end
	if opposite then
		angle = twicePi - angle
		return away, Tool:RandomAway2(pos, dist, false, angle, away)
	else
		return away
	end
end

function Tool:getTeamUnitsByClass(classes)
	local list = {}
	for i, class in pairs(classes) do

		if not self.ai.armyhst[class] then
			self:EchoDebug(class, "is not a valid class to searching for a unit")
		else
			for name, data in pairs(self.ai.armyhst[class]) do
				local current = game:GetTeamUnitsByDefs(self.ai.id, self.ai.armyhst.unitTable[name].defId)
				for index, unit in pairs(current) do
					table.insert(list, current)
				end
			end
		end
	end
	return list
end

function Tool:countFinished(targets, team) --accept units names, units def number or classes
	local team = team or self.game:GetTeamID()
	local defs = {}
	local counter = 0
	for i, target in pairs(targets) do
		if self.ai.armyhst[target] then
			for name, data in pairs(self.ai.armyhst[target]) do
				local def = self.ai.armyhst.unitTable[name].defId
				table.insert(defs, def)
			end
		elseif self.ai.armyhst.unitTable[target] then
			table.insert(defs, self.ai.armyhst.unitTable[target].defId)

		elseif UnitDefs[target] then
			table.insert(defs, target)
		end
	end
	defs = game:GetTeamUnitsByDefs(team, defs)

	for index, id in pairs(defs) do
		if not game:GetUnitByID(id):IsBeingBuilt() then
			counter = counter + 1
		end
	end
	return counter, defs
end

function Tool:countMyUnit(targets)
	local team = self.game:GetTeamID()
	local counter = 0
	for i, target in pairs(targets) do
		self:EchoDebug("target", target)
		if type(target) == "number" then
			counter = counter + game:GetTeamUnitDefCount(team, target)
		elseif self.ai.armyhst[target] then
			for name, t in pairs(self.ai.armyhst[target]) do
				local id = self.ai.armyhst.unitTable[name].defId
				counter = counter + game:GetTeamUnitDefCount(team, id)
			end

		else
			self:EchoDebug("search for spec")
			for name, spec in pairs(self.ai.armyhst.unitTable) do
				self:EchoDebug(name, spec)
				if spec[target] or name == target then
					local id = spec.defId
					counter = counter + self.game:GetTeamUnitDefCount(team, id)
				end
			end
		end
	end
	self:EchoDebug("counter", counter)
	return counter
end

function Tool:mtypedLvCount(tpLv)
	local team = self.game:GetTeamID()
	local counter = 0
	for name, spec in pairs(self.ai.armyhst.unitTable) do
		if spec.mtypedLv and spec.mtypedLv == tpLv then
			local id = spec.defId
			counter = counter + self.game:GetTeamUnitDefCount(team, id)
		end
	end
	return counter
end

function Tool:UnitPos(UNIT)
	if not UNIT then
		return
	end
	if not UNIT.unit then
		return
	end
	if not UNIT.unit:Internal() then
		return
	end
	return UNIT.unit:Internal():GetPosition()
end
