




local CMD_GUARD = 25
local CMD_PATROL = 15

AssistBehaviour = class(Behaviour)

function AssistBehaviour:Name()
	return "AssistBehaviour"
end

AssistBehaviour.DebugEnabled = false

function AssistBehaviour:DoIAssist()
	if self.nonAssistant[self.id] ~= true or self.isNanoTurret then
		return true
	else
		return false
	end
end

function AssistBehaviour:Init()
	self.active = false
	self.target = nil
	-- keeping track of how many of each type of unit
	local uname = self.unit:Internal():Name()
	self.name = uname
	if nanoTurretList[uname] then self.isNanoTurret = true end
	if commanderList[uname] then self.isCommander = true end
	self.id = self.unit:Internal():ID()
	ai.assisthandler:AssignIDByName(self)
	-- game:SendToConsole("assistbehaviour:init", ai, ai.id, self.ai, self.id)
	self:EchoDebug(uname .. " " .. self.IDByName[self.id])
	self:EchoDebug("added to unit "..uname)
end

function AssistBehaviour:OwnerIdle()
	self.patroling = false
	self.assisting = nil
end

function AssistBehaviour:Update()
	-- nano turrets don't need updating, they already have a patrol order
	if self.isNanoTurret then return end

	local f = game:Frame()

	if f % 180 == 0 then
		local unit = self.unit:Internal()
		local uname = self.name
		if self.isCommander then
			-- turn commander into build assister if you control more than half the mexes or if it's damaged
			if self.nonAssistant[self.id] then
				if ( self.overviewhandler.keepCommanderSafe or self.overviewhandler.needSiege or unit:GetHealth() < unit:GetMaxHealth() * 0.9) and self.factories ~= 0 and self.conCount > 2 then
					self:EchoDebug("turn commander into assistant")
					self.nonAssistant[self.id] = nil
					self.unit:ElectBehaviour()
				end
			else
				-- switch commander back to building
				if (not self.overviewhandler.keepCommanderSafe and not self.overviewhandler.needSiege and unit:GetHealth() >= unit:GetMaxHealth() * 0.9) or self.factories == 0 or self.conCount <= 2 then
					self:EchoDebug("turn commander into builder")
					self.nonAssistant[self.id] = true
					self.unit:ElectBehaviour()
				end
			end
		else
			-- fill empty spots after con units die
			-- if not self.IDByName[self.id] or not self.nameCount[uname] then game:SendToConsole(self.id, uname, self.IDByName[self.id], self.nameCount[uname]) end
			if self.IDByName[self.id] > self.nameCount[uname] then
				self:EchoDebug("filling empty spots with " .. uname .. " " .. self.IDByName[self.id])
				self.assisthandler:AssignIDByName(self)
				self:EchoDebug("ID now: " .. self.IDByName[self.id])
				self.unit:ElectBehaviour()
			end
		end
	end

	if f % 60 == 0 then
		if self.active then
			if self.target ~= nil then
				if self.assisting ~= self.target then
					local floats = api.vectorFloat()
					floats:push_back(self.target)
					self.unit:Internal():ExecuteCustomCommand(CMD_GUARD, floats)
					self.assisting = self.target
					self.patroling = false
				end
			elseif not self.patroling then
				local patrolPos = self.fallbackPos or self.unit:Internal():GetPosition()
				local pos = RandomAway(patrolPos, 200)
				local floats = api.vectorFloat()
				-- populate with x, y, z of the position
				floats:push_back(pos.x)
				floats:push_back(pos.y)
				floats:push_back(pos.z)
				self.unit:Internal():ExecuteCustomCommand(CMD_PATROL, floats)
				ai.assisthandler:AddFree(self)
				self.patroling = true
			end
		end
	end
end

function AssistBehaviour:Activate()
	self:EchoDebug("activated on unit "..self.name)
	if self:DoIAssist() then
		ai.assisthandler:Release(self.unit:Internal())
		ai.assisthandler:AddFree(self)
	end
	if self.isNanoTurret then
		-- set nano turrets to patrol
		local upos = RandomAway(self.unit:Internal():GetPosition(), 50)
		local floats = api.vectorFloat()
		-- populate with x, y, z of the position
		floats:push_back(upos.x)
		floats:push_back(upos.y)
		floats:push_back(upos.z)
		self.unit:Internal():ExecuteCustomCommand(CMD_PATROL, floats)
	end
	self.active = true
	self.target = nil
end

function AssistBehaviour:Deactivate()
	self:EchoDebug("deactivated on unit "..self.name)
	ai.assisthandler:RemoveWorking(self)
	ai.assisthandler:RemoveFree(self)
	self.active = false
	self.target = nil
	self.assisting = nil
end

function AssistBehaviour:Priority()
	if self:DoIAssist() then
		return 100
	else
		return 0
	end
end

function AssistBehaviour:OwnerDead()
	ai.assisthandler:RemoveAssistant(self)
end

function AssistBehaviour:Assign(builderID)
	self.target = builderID
	self.lastAssignFrame = game:Frame()
end

function AssistBehaviour:SetFallback(position)
	self.fallbackPos = position
end

-- assign if not busy (used by factories to occupy idle assistants)
function AssistBehaviour:SoftAssign(builderID)
	if self.target == nil then
		self.target = builderID
	else
		if self.lastAssignFrame == nil then
			self.target = builderID
		else
			local f = game:Frame()
			if f > self.lastAssignFrame + 900 then
				self.target = builderID
			end
		end
	end
end
