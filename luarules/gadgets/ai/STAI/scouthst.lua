ScoutHST = class(Module)

function ScoutHST:Name()
	return "ScoutHST"
end

function ScoutHST:internalName()
	return "scouthst"
end

function ScoutHST:Scope()
	return "team"
end

function ScoutHST:Init()
	self.DebugEnabled = false
	self.scouts = {}
	self.spotsToScout = {}
	self.lastCount = {}
	self.sameCount = {}
	self.usingStarts = {}
	self.SCOUTED = {}
	self.perimetralCells = {}
	self.lastSpotCheck = {}
	self:PerimetralCells()
end

function ScoutHST:ScoutTargetAlreadyHandled(X, Z, refScout)
	for id, scout in pairs(self.scouts) do
		if scout.target then
			local scoutX, scoutZ = self.ai.gridhst:PosToGrid(scout.target)
			if scoutX == X and scoutZ == Z and refScout ~= id then
				return id
			end
		end
	end
end

function ScoutHST:PerimetralCells()
	local gridhst = self.ai.gridhst
	for i = 1, gridhst.gridArea do --numeric loop keeps the cell order
		local CELL = gridhst.CELLS[i]
		if CELL.X == 1 or CELL.Z == 1 or CELL.X == gridhst.gridSideX or CELL.Z == gridhst.gridSideZ then
			table.insert(self.perimetralCells, CELL.POS)
		end
	end
end

function ScoutHST:ClosestSpot2(scoutbst)
	self:EchoDebug("closestSpot2")
	for i, v in pairs(self.lastSpotCheck) do
		self.lastSpotCheck[i] = nil
	end
	local scout = scoutbst.unit:Internal()
	local scoutPos = scout:GetPosition()
	local mtype = scoutbst.mtype
	local network = scoutbst.network
	mtype = mtype or "air" --CAUTION
	network = network or 1 --CAUTION
	local networkSpots = self.ai.maphst.networks[mtype][network].allSpots
	for index, spot in pairs(networkSpots) do
		self.lastSpotCheck[self.ai.tool:distance(scoutPos, spot)] = index
	end
	for distance, index in pairs(self.lastSpotCheck) do
		local X, Z = self.ai.gridhst:PosToGrid(networkSpots[index])
		if self:TargetAvailable(X, Z, scoutbst.id) then
			if self.ai.maphst:UnitCanGoHere(scout, networkSpots[index]) then
				return networkSpots[index]
			end
		end
	end
end

function ScoutHST:TargetAvailable(X, Z, scoutID)
	if self.SCOUTED[X] and self.SCOUTED[X][Z] then
		self:EchoDebug("networkSpots", X, Z, "is in a SCOUTED cell")
	elseif self.ai.gridhst:GetCell(X, Z, self.ai.loshst.ENEMY) then
		self:EchoDebug("networkSpots", X, Z, "is in a ENEMY cell")
	elseif self.ai.damagehst.DAMAGED[X] and self.ai.damagehst.DAMAGED[X][Z] then
		self:EchoDebug("networkSpots", X, Z, "is in a DAMAGE cell")
	elseif self.ai.loshst.OWN[X] and self.ai.loshst.OWN[X][Z] then
		self:EchoDebug("networkSpots", X, Z, "is in a OWN cell")
	elseif self.ai.loshst.ALLY[X] and self.ai.loshst.ALLY[X][Z] then
		self:EchoDebug("networkSpots", X, Z, "is in a ALLY cell")
	elseif self:ScoutTargetAlreadyHandled(X, Z, scoutID) then
		self:EchoDebug("target already in use by scout", X, Z, "by scout", scoutID)
	else
		self:EchoDebug("target scout ", X, Z, "Available", scoutID)
		return true
	end
end

function ScoutHST:Update()
	local frame = game:Frame()
	for X, cells in pairs(self.SCOUTED) do
		for Z, cellFrame in pairs(cells) do
			if frame > cellFrame + 3600 then
				self.SCOUTED[X][Z] = nil
				-- 				cell = nil
			end
		end
	end
end
