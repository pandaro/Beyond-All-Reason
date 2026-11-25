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
	self.SCOUTED = self.ai.gridhst:NewLayer() --the cells a scout went through in the last 3600 frames
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
	if self.ai.gridhst:GetCell(X, Z, self.SCOUTED) then
		self:EchoDebug("networkSpots", X, Z, "is in a SCOUTED cell")
	elseif self.ai.gridhst:GetCell(X, Z, self.ai.loshst.ENEMY) then
		self:EchoDebug("networkSpots", X, Z, "is in a ENEMY cell")
	elseif self.ai.gridhst:GetCell(X, Z, self.ai.damagehst.DAMAGED) then
		self:EchoDebug("networkSpots", X, Z, "is in a DAMAGE cell")
	elseif self:ScoutTargetAlreadyHandled(X, Z, scoutID) then
		self:EchoDebug("target already in use by scout", X, Z, "by scout", scoutID)
	else
		self:EchoDebug("target scout ", X, Z, "Available", scoutID)
		return true
	end
end

function ScoutHST:Scouted(X, Z) --a scout is in the cell X, Z now
	if not self.ai.gridhst:IsCellInGrid(X, Z) then
		return
	end
	local i = self.ai.gridhst:GridToIndex(X, Z)
	self.SCOUTED:Get(i).frame = game:Frame()
	self.SCOUTED:Mark(i)
end

function ScoutHST:Update()
	local frame = game:Frame()
	local LIST = self.SCOUTED.LIST
	for n = #LIST, 1, -1 do --backward: Unmark takes the cell out of LIST
		local i = LIST[n]
		if frame > self.SCOUTED.CELLS[i].frame + 3600 then
			self.SCOUTED:Unmark(i)
		end
	end
end
