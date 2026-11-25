AttackerBST = class(Behaviour)

function AttackerBST:Name()
	return "AttackerBST"
end

function AttackerBST:Init()
	self.DebugEnabled = false
	local mtype, network = self.ai.maphst:MobilityOfUnit(self.unit:Internal())
	self.mtype = mtype
	self.network = network
	self.name = self.unit:Internal():Name()
	self.id = self.unit:Internal():ID()
	self.x = self.unit:Internal().x
	self.y = self.unit:Internal().y
	self.z = self.unit:Internal().z
	self.defID = self.ai.armyhst.unitTable[self.name].defId
	local ut = self.ai.armyhst.unitTable[self.name]
	self.level = ut.techLevel - 1
	if self.level == 0 then
		self.level = 0.5
	elseif self.level < 0 then
		self.level = 0.25
	end
	self.size = math.max(ut.xsize, ut.zsize) * 8
	self.congSize = self.size * 1.5 -- how much self.ai.tool:distance between it and other attackers when congregating
	self.range = math.max(ut.groundRange, ut.airRange, ut.submergedRange)
	self.weaponDistance = self.range * 0.9
	self.sightDistance = ut.sightDistance --* 0.9
	self.sturdy = self.ai.armyhst.battles[self.name] or self.ai.armyhst.breaks[self.name]
	if ut.groundRange > 0 then
		self.hits = "ground"
	elseif ut.submergedRange > 0 then
		self.hits = "submerged"
	elseif ut.airRange > 0 then
		self.hits = "air"
	end
	self.speed = ut.speed
	self.threat = ut.metalCost
	self.mass = ut.metalCost
end

function AttackerBST:OwnerBuilt()
	self.ai.attackhst:AddRecruit(self)
end

function AttackerBST:OwnerDamaged(attacker, damage)
	self.damaged = self.game:Frame() --frame of the last hit
end

function AttackerBST:OwnerDead()
	self.unit = nil
	self.ai.attackhst:RemoveRecruit(self)
	self.ai.attackhst:RemoveMember(self)
end

function AttackerBST:OwnerIdle()
	self.idle = true
	self.ai.attackhst:MemberIdle(self)
end

function AttackerBST:OwnerMoveFailed(unit)
	self:Warn("OWNER MOVE FAILED")
	self:OwnerIdle()
end

function AttackerBST:Priority()
	return 0 --the squad gives the orders
end

function AttackerBST:Update()
	local f = self.game:Frame()
	if not self.mtype then
		self:Warn("no mtype and network")
	end
	if self.damaged then
		if f > self.damaged + 450 then
			self.damaged = nil
		end
	end
end

function AttackerBST:Free()
	self.idle = nil
	if self.squad and self.squad.disbanding then
		self.squad = nil
	else
		self.ai.attackhst:RemoveMember(self)
	end
end
