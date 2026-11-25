DamageHST = class(Module) -- keeps track of hits to our units

function DamageHST:Name()
	return "DamageHST"
end

function DamageHST:internalName()
	return "damagehst"
end

function DamageHST:Scope()
	return "team"
end

function DamageHST:Init()
	self.DebugEnabled = false
	self.DAMAGED = self.ai.gridhst:NewLayer(self.resetCell) --the cells where our units were hit, they last until the threat fades
end

function DamageHST:UnitDamaged(defender, attacker, damage)
	local teamID = defender:Team()
	if teamID ~= self.ai.id then
		return
	end
	local defenderName = defender:Name()
	-- even if the attacker can't be seen, human players know what weapons look like
	-- in non-lua shard, the attacker is nil if it's an enemy defender, so this becomes useless
	if attacker ~= nil and attacker:AllyTeam() ~= self.ai.allyId then --   we know what is it and self.ai.loshst:IsKnownEnemy(attacker) ~= 2 then
		local mtype
		local defenderUt = self.ai.armyhst.unitTable[defenderName]
		if defenderUt then
			local attackerut = self.ai.armyhst.unitTable[attacker:Name()]
			local attackerThreat = attackerut and attackerut.metalCost or damage or 100 --an attacker out of unitTable counts as its damage
			local defenderThreat = defenderUt.metalCost or damage or 100

			if attackerut then
				if attackerut.isBuilding then
					self.ai.loshst.losEnemy[attacker:ID()] = attackerut.defId
					self.ai.loshst.radarEnemy[attacker:ID()] = nil
					--  					self.ai.loshst:scanEnemy(attacker,isShoting)---isshoting maybe need to be true?
					--  					return
				end

			end
			self:AddBadPosition(defender:GetPosition(), defenderUt.mtype, attackerThreat, defenderThreat, 900)
		end
	end
end

function DamageHST:AddBadPosition(position, mtype, attackerThreat, defenderThreat, duration)
	duration = duration or 1800
	local X, Z = self.ai.gridhst:PosToGrid(position)
	if not self.ai.gridhst:IsCellInGrid(X, Z) then
		self:Warn(X, Z, "damage out of the grid")
		return
	end
	local f = self.game:Frame()
	local i = self.ai.gridhst:GridToIndex(X, Z)
	local CELL = self.DAMAGED:Get(i)
	if not self.DAMAGED:GetMarked(i) then
		CELL.X = X
		CELL.Z = Z
		CELL.POS = self.ai.gridhst:GridToPos(X, Z) --not the POS of the GridHST cell: the ground can change after Init
		CELL.nodeCostIndex = i
		CELL.frame = f
		CELL.attackerThreat = attackerThreat
		CELL.defenderThreat = defenderThreat
		CELL.duration = duration
	else
		CELL.frame = f
		CELL.attackerThreat = CELL.attackerThreat + attackerThreat
		CELL.defenderThreat = CELL.defenderThreat + defenderThreat
	end
	self.DAMAGED:Mark(i)
end

function DamageHST.resetCell(CELL) --clear a DAMAGED cell
	CELL.frame = 0
	CELL.attackerThreat = 0
	CELL.defenderThreat = 0
	CELL.duration = 0
end

function DamageHST:UpdateBadPositions()
	local f = self.game:Frame()
	local LIST = self.DAMAGED.LIST
	for n = #LIST, 1, -1 do --backward: Unmark takes the cell out of LIST
		local i = LIST[n]
		local cell = self.DAMAGED.CELLS[i]
		if f - cell.frame > 300 then -- reduce  bad position every 10 seconds
			cell.frame = f
			cell.attackerThreat = math.floor(cell.attackerThreat * 0.9)
			cell.defenderThreat = math.floor(cell.defenderThreat * 0.9)
			self:EchoDebug(cell.defenderThreat)

			if cell.defenderThreat < 1 then
				self.DAMAGED:Unmark(i)
			end

		end
	end
end

function DamageHST:Update()
	self:UpdateBadPositions()
	self:VisualDBG()
end

function DamageHST:VisualDBG()

	if not self.ai.drawDebug then
		return
	end
	local ch = 1
	self.map:EraseAll(ch)
	local colours = Toolbox.COLOURS
	local cellElmosHalf = self.ai.gridhst.gridSizeHalf ---@type number
	local LIST = self.DAMAGED.LIST
	for n = 1, #LIST do
		local cell = self.DAMAGED.CELLS[LIST[n]]
		local p = cell.POS
		if not p then
			self:EchoDebug("no p in draw debug")

			return
		end
		local pos1, pos2 = api.Position(), api.Position() --z,api.Position(),api.Position(),api.Position()
		pos1.x, pos1.z = p.x - cellElmosHalf, p.z - cellElmosHalf
		pos2.x, pos2.z = p.x + cellElmosHalf, p.z + cellElmosHalf
		pos1.y = Spring.GetGroundHeight(pos1.x, pos1.z)
		pos2.y = Spring.GetGroundHeight(pos2.x, pos2.z)
		map:DrawRectangle(p, pos2, colours.blue, cell.defenderThreat, false, ch)
		map:DrawRectangle(pos1, p, colours.red, cell.attackerThreat, false, ch)
		map:DrawPoint(p, colours.black, cell.X .. ":" .. cell.Z .. "=" .. cell.nodeCostIndex, ch)
	end
end
