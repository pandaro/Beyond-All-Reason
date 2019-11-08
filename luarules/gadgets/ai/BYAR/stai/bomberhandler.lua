




BomberHandler = class(Module)

function BomberHandler:Name()
	return "BomberHandler"
end

function BomberHandler:internalName()
	return "bomberhandler"
end

BomberHandler.DebugEnabled = false

function BomberHandler:Init()
    BomberHandler.plans = {} --TODO why here and why called with bomberhandler instead of self
	self.recruits = {}
	self.needsTargetting = {}
	self.counter = baseBomberCounter
	self.hasBombed = 0
	self.couldBomb = 0
	self.pathValidFuncs = {}
	
end

function BomberHandler:Update()
	local f = Spring.GetGameFrame()
    self:EchoDebug(f, f % 30)
	if f % 30 == 0 then self:DoTargetting() end
    
	for i = #self.plans, 1, -1 do
		local plan = self.plans[i]
		local pathfinder = plan.pathfinder
		local path, remaining, maxInvalid = pathfinder:Find(1)
		if path then
			-- path = SimplifyPath(path)
			if self.DebugEnabled then
				self.map:EraseLine(nil, nil, {1,1,1}, nil, nil, 8)
				for i = 2, #path do
					local pos1 = path[i-1].position
					local pos2 = path[i].position
					local arrow = i == #path
					self.map:DrawLine(pos1, pos2, {1,1,1}, nil, arrow, 8)
				end
			end
			if maxInvalid == 0 or #path < 3 then
				self:Bomb(plan)
			else
				self:Bomb(plan, path)
			end
			table.remove(self.plans, i)
		elseif remaining == 0 then
			for _, bomber in pairs(plan.bombers) do
				self:AddRecruit(bomber)
			end
			table.remove(self.plans, i)
		end
	end
end

function BomberHandler:Bomb(plan, path)
	local bombers = plan.bombers
	local target = plan.target
	for i = 1, #bombers do
		local bomber = bombers[i]
		bomber:BombTarget(target, path)
	end
	self.hasBombed = self.hasBombed + 1
end

function BomberHandler:DoTargetting()
	for weapon, _ in pairs(self.needsTargetting) do
		local recruits = self.recruits[weapon]
		self.couldBomb = self.couldBomb + 1
		-- find somewhere to attack
		self:EchoDebug("getting target for " .. weapon)
		local torpedo = weapon == 'torpedo'
		local targetUnit = self.targethandler:GetBestBomberTarget(torpedo)
		if targetUnit ~= nil then
			local tupos = targetUnit:GetPosition()
			if tupos and tupos.x then
				self:EchoDebug("got target for " .. weapon)
				local sumX = 0
				local sumZ = 0
				local validFunc
				for i = 1, #recruits do
					local recruit = recruits[i]
					local pos = recruit.unit:Internal():GetPosition()
					sumX = sumX + pos.x
					sumZ = sumZ + pos.z
					validFunc = validFunc or self:GetPathValidFunc(recruit.unit:Internal():Name())
				end
				local midPos = api.Position()
				midPos.x = sumX / #recruits
				midPos.z = sumZ / #recruits
				midPos.y = 0
				self.graph = self.graph or self.maphandler:GetPathGraph('air', 512)
				local pathfinder = self.graph:PathfinderPosPos(midPos, targetUnit:GetPosition(), nil, validFunc)
				local bombers = {}
				for i = 1, #recruits do
					local recruit = recruits[i]
					bombers[#bombers+1] = recruit
				end
				local plan = { target = targetUnit, start = midPos, bombers = bombers, pathfinder = pathfinder }
				self.plans[#self.plans+1] = plan
				self.recruits[weapon] = {}
				self.needsTargetting[weapon] = nil
			end
		end
	end
end

function BomberHandler:IsRecruit(bmbrbehaviour)
	if self.recruits[bmbrbehaviour.weapon] == nil then self.recruits[bmbrbehaviour.weapon] = {} end
	for i,v in ipairs(self.recruits[bmbrbehaviour.weapon]) do
		if v == bmbrbehaviour then
			return true
		end
	end
	return false
end

function BomberHandler:AddRecruit(bmbrbehaviour)
	if self.recruits[bmbrbehaviour.weapon] == nil then self.recruits[bmbrbehaviour.weapon] = {} end
	if not self:IsRecruit(bmbrbehaviour) then
		table.insert(self.recruits[bmbrbehaviour.weapon],bmbrbehaviour)
		if #self.recruits[bmbrbehaviour.weapon] >= self.counter then
			self.needsTargetting[bmbrbehaviour.weapon] = true
		end
	end
end

function BomberHandler:RemoveRecruit(bmbrbehaviour)
	if self.recruits[bmbrbehaviour.weapon] == nil then self.recruits[bmbrbehaviour.weapon] = {} end
	for i,v in ipairs(self.recruits[bmbrbehaviour.weapon]) do
		if v == bmbrbehaviour then
			table.remove(self.recruits[bmbrbehaviour.weapon], i)
			if #self.recruits[bmbrbehaviour.weapon] < self.counter then
				self.needsTargetting[bmbrbehaviour.weapon] = nil
			end
			return true
		end
	end
	return false
end

function BomberHandler:NeedMore()
	self.counter = self.counter + 1
	self.counter = math.min(self.counter, maxBomberCounter)
	-- self:EchoDebug("bomber counter: " .. self.counter .. " (bomber died)")
end

function BomberHandler:NeedLess()
	self.counter = self.counter - 1
	self.counter = math.max(self.counter, minBomberCounter)
	self:EchoDebug("bomber counter: " .. self.counter .. " (AA died)")
end

function BomberHandler:GetCounter()
	return self.counter
end

function BomberHandler:GetPathValidFunc(unitName)
	if self.pathValidFuncs[unitName] then
		return self.pathValidFuncs[unitName]
	end
	local valid_node_func = function ( node )
		return self.targethandler:IsSafePosition(node.position, unitName, nil, true)
	end
	self.pathValidFuncs[unitName] = valid_node_func
	return valid_node_func
end
