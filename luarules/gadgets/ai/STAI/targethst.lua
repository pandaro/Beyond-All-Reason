TargetHST = class(Module)

function TargetHST:Name()
	return "TargetHST"
end

function TargetHST:internalName()
	return "targethst"
end

function TargetHST:Scope()
	return "team"
end

function TargetHST:Init()
	self.DebugEnabled = false
	self.enemyCenter = self.elmoMapCenter
	self.IMMOBILE_BLOBS = {}
	self.MOBILE_BLOBS = {}
	self.enemyFrontList = {}
	self.blobchecked = {}
	self.enemyCenter = { x = 0, y = 0, z = 0 }
	self.enemyBasePosition = { x = 0, y = 0, z = 0 }
	self.enemybasecount = 0
	self.cellCount = 0
end

function TargetHST:Update()
	self:EnemiesCellsAnalisy()
	self:GetBlobs("MOBILE_BLOBS", "SPEED")
	self:GetBlobs("IMMOBILE_BLOBS", "IMMOBILE")
	self:drawDBG()
end

function TargetHST:GetBlobs(_blobs_, param) --reset all the old blobs
	--for ref,blob in pairs(self[_blobs_]) do --reset all the old blobs
	self.ai.tool:ResetTable(self[_blobs_])
	--end
	local blobref
	local ENEMY = self.ai.loshst.ENEMY
	for n = 1, #ENEMY.LIST do --find all the bew blobs, numeric loop keeps the order of the cells
		local CELL = ENEMY.CELLS[ENEMY.LIST[n]]
		blobref = CELL.X .. ":" .. CELL.Z
		if not self.blobchecked[blobref] then
			self:Blobbing(ENEMY, param, CELL.X, CELL.Z, _blobs_, blobref)
		end
	end
	for i, v in pairs(self.blobchecked) do --clean all the cell/blobs checked
		self.blobchecked[i] = nil
	end
	for ref, blob in pairs(self[_blobs_]) do -- fill the blobs with data
		for i, v in pairs(blob.cells) do
			local CELL = self.ai.gridhst:GetCell(v.X, v.Z, ENEMY)
			for id, name in pairs(CELL.units) do
				blob.units[id] = name
			end
			blob.position.x = blob.position.x + CELL.POS.x
			blob.position.z = blob.position.z + CELL.POS.z
			blob.metal = blob.metal + CELL.metal
		end
		blob.position.x = blob.position.x / #blob.cells
		blob.position.z = blob.position.z / #blob.cells
		blob.position.y = map:GetGroundHeight(blob.position.x, blob.position.z)
		blob.targetCell.X, blob.targetCell.Z = self.ai.gridhst:PosToGrid(blob.position)
	end
	self:EchoDebug("selfblob", _blobs_, self[_blobs_])
end

function TargetHST:Blobbing(layer, param, x, z, _blobs_, blobref) --rolling on the cell to extrapolate blob of param
	self.blobchecked[x .. ":" .. z] = true
	local CELL = self.ai.gridhst:GetCell(x, z, layer) --nil out of the edges, the recursion goes beyond them
	if CELL and CELL[param] and CELL[param] > 0 then
		if not self[_blobs_][blobref] then
			self[_blobs_][blobref] = self.ai.tool:RezTable()
			self[_blobs_][blobref].position = self.ai.tool:RezTable()
			self[_blobs_][blobref].position.x = 0
			self[_blobs_][blobref].position.y = 0
			self[_blobs_][blobref].position.z = 0
			self[_blobs_][blobref].cells = self.ai.tool:RezTable()
			self[_blobs_][blobref].units = self.ai.tool:RezTable()
			self[_blobs_][blobref].metal = 0
			self[_blobs_][blobref].targetCell = self.ai.tool:RezTable()
		end
		local cellCoord = self.ai.tool:RezTable()
		cellCoord.X = x
		cellCoord.Z = z
		table.insert(self[_blobs_][blobref].cells, cellCoord)
		for X = -1, 1, 1 do
			for Z = -1, 1, 1 do
				if not self.blobchecked[x + X .. ":" .. z + Z] then
					self:Blobbing(layer, param, x + X, z + Z, _blobs_, blobref)
				end
			end
		end
	end
end

function TargetHST:EnemiesCellsAnalisy() --TODO:--MOVE TO TACTICALHST!!!
	self.enemybasecount = 0
	self.cellCount = 0

	self.enemyBasePosition.x = 0
	self.enemyBasePosition.y = 0
	self.enemyBasePosition.z = 0

	self.enemyCenter.x = 0
	self.enemyCenter.y = 0
	self.enemyCenter.z = 0

	local ENEMY = self.ai.loshst.ENEMY
	for n = 1, #ENEMY.LIST do --numeric loop keeps the order of the cells
		local cell = ENEMY.CELLS[ENEMY.LIST[n]]
		self.enemyCenter.x = self.enemyCenter.x + cell.POS.x
		self.enemyCenter.y = self.enemyCenter.y + cell.POS.y
		self.enemyCenter.z = self.enemyCenter.z + cell.POS.z
		self.cellCount = self.cellCount + 1
		if cell.base then
			self.enemyBasePosition.x = self.enemyBasePosition.x + cell.POS.x
			self.enemyBasePosition.z = self.enemyBasePosition.z + cell.POS.z
			self.enemybasecount = self.enemybasecount + 1
		end
	end
	if self.cellCount > 0 then

		self.enemyCenter.x = self.enemyCenter.x / self.cellCount
		self.enemyCenter.z = self.enemyCenter.z / self.cellCount
		self.enemyCenter.y = map:GetGroundHeight(self.enemyCenter.x, self.enemyCenter.z)
	end
	if self.enemybasecount > 0 then
		self.enemyBasePosition.x = self.enemyBasePosition.x / self.enemybasecount
		self.enemyBasePosition.z = self.enemyBasePosition.z / self.enemybasecount
		self.enemyBasePosition.y = map:GetGroundHeight(self.enemyBasePosition.x, self.enemyBasePosition.z)
	end
end

function TargetHST:IsSafeCell(position, unitName, threshold, adjacent) --TODO move and improve in damagehst
	if not position then
		self:Warn("nil position in safe position check")
		return
	end
	threshold = threshold or 0
	adjacent = adjacent or 0
	-- 	local layer = --here implement a count of danger per layer, but now we count all danger layer as dangerous
	-- 	if unit then
	-- 		layer = self.ai.armyhst.unitTable[unitName].LAYER
	-- 	end
	--WARNING here implement a count of danger per layer, but now we count all danger layer as dangerous
	local danger = self.ai.gridhst:getCellsFields(position, { "ARMED" }, adjacent, self.ai.loshst.ENEMY)
	return danger <= threshold
end

function TargetHST:drawDBG()

	if not self.ai.drawDebug then
		return
	end
	local ch = 4
	self.map:EraseAll(ch)
	local colours = self.ai.tool.COLOURS
	if self.enemyBasePosition then
		map:DrawPoint(self.enemyBasePosition, colours.black, "BASE", ch)
	end
	map:DrawPoint(self.enemyCenter, colours.black, "CENTER", ch)
	--[[
	for i,cell in pairs(self.enemyFrontList) do
		map:DrawCircle(cell.POS, cellElmosHalf/2, colours.f, 'front', true, ch)
	end]]
	local cellElmosHalf = self.ai.gridhst.gridSizeHalf
	for i, blob in pairs(self.MOBILE_BLOBS) do

		for ref, cell in pairs(blob.cells) do
			local pos1 = {}
			local pos2 = {}
			pos1.x, pos1.z = cell.POS.x - cellElmosHalf, cell.POS.z - cellElmosHalf
			pos2.x, pos2.z = cell.POS.x + cellElmosHalf, cell.POS.z + cellElmosHalf
			map:DrawRectangle(pos1, pos2, colours.yellow, i, false, ch)

		end
		map:DrawCircle(blob.position, 128, colours.red, nil, true, ch)
	end
	for i, blob in pairs(self.IMMOBILE_BLOBS) do

		for ref, cell in pairs(blob.cells) do
			local pos1 = {}
			local pos2 = {}
			pos1.x, pos1.z = cell.POS.x - cellElmosHalf, cell.POS.z - cellElmosHalf
			pos2.x, pos2.z = cell.POS.x + cellElmosHalf, cell.POS.z + cellElmosHalf
			map:DrawRectangle(pos1, pos2, colours.aqua, i, false, ch)

		end
		map:DrawCircle(blob.position, 128, colours.blue, nil, true, ch)
	end
end
