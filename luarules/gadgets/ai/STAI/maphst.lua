MapHST = class(Module)

function MapHST:Name()
	return "MapHST"
end

function MapHST:internalName()
	return "maphst"
end

function MapHST:Scope()
	return "team"
end

function MapHST:Init()
	local rules_param_mex_count = Spring.GetGameRulesParam("mex_count")
	self:EchoDebug("games rules param mex_count:", rules_param_mex_count)

	self.DebugEnabled = false
	self:EchoDebug("MapHST START")
	self:basicMapInfo()
	self.topology = { air = {} }
	self:createGrid()
	self.METALS = map:GetMetalSpots()
	self.GEOS = map:GetGeoSpots()
	self.METALS = self:SimplifyMetalSpots(self.gridSize * 2) -- is a random choice, can be 1 or 9999999999
	self.allSpots = self.ai.tool:tableConcat({ self.METALS, self.GEOS })
	self.hotSpots = {}
	self:hotSpotter()
	self.networks = {} --hold data in a "specific network" area(about GAS (area,mex,geos,trampling)
	self.layers = {} --hold the "global layer" data about a GAS (area,mex,geos,trampling)
	self:gridAnalisy()
	self:metalScan()
	self:geoScan()
	self:LayerScan()
	self:DrawDebug()
	collectgarbage("collect")
	self:EchoDebug("MapHST STOP")
end

function MapHST:GridToNodeIndex(X, Z)
	return (((X - 1) * self.ai.maphst.gridSideX) + Z) - 1
end

function MapHST:basicMapInfo() --capture and set foundamental map info
	self.mapSize = map:MapDimensions()
	self.elmoMapSizeX = self.mapSize.x * 8
	self.elmoMapSizeZ = self.mapSize.z * 8
	self.elmoMapCenter = {
		x = self.elmoMapSizeX / 2,
		y = map:GetGroundHeight(self.elmoMapSizeX / 2, self.elmoMapSizeZ / 2),
		z = self.elmoMapSizeZ / 2,
	}
	self.elmoMapMaxCenterDistance = self.ai.tool:distance({ x = 0, y = 0, z = 0 }, self.elmoMapCenter)
	self.elmoMapMaxDistance = self.ai.tool:distance(
		{ x = 0, y = 0, z = 0 },
		{ x = self.elmoMapSizeX, y = 0, z = self.elmoMapSizeZ }
	)
	self:EchoDebug(
		"self.elmoMapMaxDistance",
		self.elmoMapMaxDistance,
		"self.elmoMapMaxCenterDistance",
		self.elmoMapMaxCenterDistance
	)
	self:EchoDebug(self.ai.tool:gcd(self.elmoMapSizeX, self.elmoMapSizeZ))
	self.elmoArea = self.elmoMapSizeX * self.elmoMapSizeZ
	self.gridSize = 256 --math.max( math.floor(math.max(MapHST.mapSize.x * 8, MapHST.mapSize.z * 8) / 128),32)-- don't make grids smaller than 32
	self.gridSizeHalf = self.gridSize / 2
	self.gridSizeDouble = self.gridSize * 2
	self.gridSideX = self.elmoMapSizeX / self.gridSize
	self.gridSideZ = self.elmoMapSizeZ / self.gridSize
	self.gridArea = self.gridSideX * self.gridSideZ
	self:EchoDebug("ElmoX", self.elmoMapSizeX, "ElmoZ", self.elmoMapSizeZ, "ElmoArea", self.elmoArea)
	self:EchoDebug("grid size: " .. self.gridSize .. "grid area", self.gridArea, self.gridSideX, self.gridSideZ)
end

function MapHST:createGrid()
	self.GRID = {}
	for X = 1, self.gridSideX do
		if not self.GRID[X] then
			self.GRID[X] = {}
		end
		for Z = 1, self.gridSideZ do
			self.GRID[X][Z] = self:NewCell(X, Z)
		end
	end
end

function MapHST:RawPosIsInMap(x, y, z)
	if (x <= 0) or (x > self.elmoMapSizeX) or (z <= 0) or (z > self.elmoMapSizeZ) then
		self:EchoDebug("bad position: " .. pos.x .. ", " .. pos.z)
		return nil
	else
		return x, y, z
	end
end

function MapHST:isInMap(pos)
	if (pos.x <= 0) or (pos.x > self.elmoMapSizeX) or (pos.z <= 0) or (pos.z > self.elmoMapSizeZ) then
		self:EchoDebug("bad position: " .. pos.x .. ", " .. pos.z)
		return nil
	else
		return pos
	end
end

function MapHST:PosToGrid(pos)
	local X = math.ceil(pos.x / self.gridSize)
	local Z = math.ceil(pos.z / self.gridSize)
	if not self.GRID[X] or not self.GRID[X][Z] then
		self:EchoDebug(X, Z, "is out of GRID", pos.x, pos.z)
	end
	return X, Z
end

function MapHST:RawPosToGrid(x, y, z)
	local X = math.ceil(x / self.gridSize)
	local Z = math.ceil(z / self.gridSize)
	if not self.GRID[X] or not self.GRID[X][Z] then
		self:EchoDebug(X, Z, "is out of GRID", x, z)
	end
	return X, Z
end

function MapHST:IsCellInGrid(X, Z)
	if X < 1 or Z < 1 or X > self.gridSideX or Z > self.gridSideZ then
		return nil
	end
	return true
end

function MapHST:GridToPos(X, Z)
	local pos = {}
	pos.x = X * self.gridSize - self.gridSizeHalf
	pos.z = Z * self.gridSize - self.gridSizeHalf
	pos.y = map:GetGroundHeight(pos.x, pos.z)
	if not self:isInMap(pos) then
		self:Warn(pos.x, pos.z, "is not in map")
		return
	end
	return pos
end

function MapHST:GridToRawPos(X, Z)
	local x = X * self.gridSize - self.gridSizeHalf
	local z = Z * self.gridSize - self.gridSizeHalf
	local y = map:GetGroundHeight(x, z)
	if not self:RawPosIsInMap(x, y, z) then
		self:Warn(x, z, "is not in map")
		return
	end
	return x, y, z
end

function MapHST:NewCell(gx, gz)
	local x = (gx * self.gridSize) - self.gridSizeHalf
	local z = (gz * self.gridSize) - self.gridSizeHalf
	local cellPos = {}
	cellPos.x, cellPos.z = x, z
	cellPos.y = Spring.GetGroundHeight(x, z)
	self:isInMap(cellPos) --move here ,is in map!!
	local cell = {}
	cell.POS = cellPos --the cell position
	cell.X = gx --the cell coordinate X on the grid
	cell.Z = gz --the cell coordinate Z on the grid
	cell.moveLayers = self:moveLayerTest(cellPos) --hold the  layers and networks in this cell
	cell.metalSpots = {} --hold the metalSpots of this cell
	cell.geoSpots = {} --hold the geoSpots of this cell
	cell.allSpots = {} --hold all the interesting spots
	return cell
end

function MapHST:areaCells(X, Z, R, grid) -- return alist of cells in range R from a cell
	if not X or not Z then
		self:Warn("no grid XZ for areacells")
	end
	local AC = {}
	R = R or 0
	for x = X - R, X + R, 1 do
		for z = Z - R, Z + R, 1 do
			if grid[x] and grid[x][z] then
				table.insert(AC, grid[x][z])
			end
		end
	end
	return AC
end

function MapHST:GetCell(X, Z, grid) --accept 1one position({t.x,t.y,t.z}) OR 2two XZ grid coordinate; return a CEll if exist
	local grid = grid
	if type(X) == "table" and X.x and X.z then
		grid = Z
		X, Z = self:PosToGrid(X)
	end
	if not grid[X] then
		return
	end
	if not grid[X][Z] then
		return
	end
	return grid[X][Z]
end

function MapHST:getCellsFields(p, fields, range, grid) --return the required list of values of a cell/cells
	if not fields or not p or type(fields) ~= "table" then
		self:Warn("incomplete or incorrect params for get cells params", p, fields, range, grid)
		return
	end
	range = range or 0
	local X, Z = self:PosToGrid(p)
	local cells = self:areaCells(X, Z, range, grid)
	local value = 0 --VALUE is a total count of all request fields
	local subValues = {} --subValues is the sum of this fields of each asked cell
	for i, f in pairs(fields) do
		subValues[f] = 0
	end
	for index, cell in pairs(cells) do
		for i, field in pairs(fields) do
			value = value + cell[field]
			subValues[field] = subValues[field] + cell[field]
		end
	end
	return value, subValues, cells
end

function MapHST:moveLayerTest(pos) --check where units can stay or not
	local layers = {}
	layers.air = 1
	for layer, unitName in pairs(self.ai.armyhst.mobUnitExampleName) do
		if not self.topology[layer] then
			self.topology[layer] = {}
		end
		if
			Spring.TestMoveOrder(
				self.ai.armyhst.unitTable[unitName].defId,
				pos.x,
				pos.y,
				pos.z,
				nil,
				nil,
				nil,
				true,
				false,
				true
			)
		then
			layers[layer] = 0
		else
			layers[layer] = false
		end
	end
	return layers
end

function MapHST:gridAnalisy() --do the first analisy of the grid
	local net = {}
	for X, Zetas in pairs(self.GRID) do
		for Z, CELL in pairs(Zetas) do
			for layer, anteNetwork in pairs(CELL.moveLayers) do
				if anteNetwork == 0 then
					if not net[layer] then
						net[layer] = 0
						self.networks[layer] = {}
					end
					net[layer] = net[layer] + 1
					self.networks[layer][net[layer]] = {}
					self.networks[layer][net[layer]].area = 0
					self.networks[layer][net[layer]].metals = {}
					self.networks[layer][net[layer]].geos = {}
					self.networks[layer][net[layer]].allSpots = {}
					self:TopologyFooded(X, Z, layer, net)
				end
			end
		end
	end
	self.networks.air = {}
	self.networks.air[1] = {
		area = self.gridArea,
		metals = {},
		geos = {},
		allSpots = {},
	}
end

function MapHST:LayerScan() --a most approfondite analisy of the layers
	for layer, net in pairs(self.networks) do
		local main = {}
		main[layer] = {}
		main[layer].area = 0
		main[layer].metals = 0
		main[layer].geos = 0
		main[layer].allSpots = 0
		main[layer].ratioArea = 0
		main[layer].ratioMetals = 0
		main[layer].ratioGeos = 0
		for index, network in pairs(net) do
			network.allSpots = self.ai.tool:tableConcat({ network.metals, network.geos })
			network.ratioArea = network.area / self.gridArea
			if #network.allSpots == 0 or #self.allSpots == 0 then
				network.ratioSpots = 0
			else
				network.ratioSpots = #network.allSpots / #self.allSpots
			end

			if #network.metals == 0 or #self.METALS == 0 then
				network.ratioMetals = 0
			else
				network.ratioMetals = #network.metals / #self.METALS
			end

			if #network.geos == 0 or #self.GEOS == 0 then
				network.ratioGeos = 0
			else
				network.ratioGeos = #network.geos / #self.GEOS
			end
			self:EchoDebug(
				layer,
				"Network :",
				index,
				network.area,
				#network.metals,
				#network.geos,
				network.ratioArea,
				network.ratioMetals,
				network.ratioGeos
			)
			main[layer].area = main[layer].area + network.area
			main[layer].metals = main[layer].metals + #network.metals
			main[layer].geos = main[layer].geos + #network.geos
			main[layer].allSpots = main[layer].allSpots + #network.metals + #network.geos
		end
		main[layer].ratioArea = main[layer].area / self.gridArea
		if main[layer].metals == 0 or #self.METALS == 0 then
			main[layer].ratioMetals = 0
		else
			main[layer].ratioMetals = main[layer].metals / #self.METALS
		end
		if main[layer].geos == 0 or #self.GEOS == 0 then
			main[layer].ratioGeos = 0
		else
			main[layer].ratioGeos = main[layer].geos / #self.GEOS
		end
		self.layers[layer] = main[layer]

		self:EchoDebug(
			"layers",
			layer,
			main[layer].area,
			main[layer].metals,
			main[layer].geos,
			main[layer].ratioArea,
			main[layer].ratioMetals,
			main[layer].ratioGeos
		)
	end
end

function MapHST:TopologyFooded(x, z, layer, net) --rolling on the cell to extrapolate where unit can go
	if x > self.gridSideX or x < 1 or z > self.gridSideZ or z < 1 then
		return
	end
	if self.GRID[x][z].moveLayers[layer] == 0 then
		self.GRID[x][z].moveLayers[layer] = net[layer]
		self.topology[layer][x] = self.topology[layer][x] or {}
		self.topology[layer][x][z] = true
		self.networks[layer][net[layer]].area = self.networks[layer][net[layer]].area + 1
		for X = -1, 1, 1 do
			for Z = -1, 1, 1 do
				if x ~= x + X or z ~= z + Z then
					self:TopologyFooded(x + X, z + Z, layer, net)
				end
			end
		end
	end
end

function MapHST:hotSpotter()
	local spots = {}
	local mirrorspots = {}
	local limit = (self.map:MapDimensions())
	local limit = limit.x / 2 + limit.z / 2
	for i, v in pairs(self.METALS) do
		table.insert(spots, v)
	end
	for i, v in pairs(self.GEOS) do
		table.insert(spots, v)
	end
	self:EchoDebug("limit", tostring(limit))
	for index1, pos1 in pairs(spots) do
		if spots[index1] then
			mirrorspots[index1] = {}
			table.insert(mirrorspots[index1], pos1)
			spots[index1] = false
			for index2, pos2 in pairs(spots) do
				if spots[index2] and pos1 ~= pos2 then
					local dist = self.ai.tool:distance(pos1, pos2)
					if dist < limit and ((pos1.y > 0 and pos2.y > 0) or (pos1.y < 0 and pos2.y < 0)) then
						table.insert(mirrorspots[index1], pos2)
						spots[index2] = false
					end
				end
			end
		end
	end
	for i, v in pairs(mirrorspots) do
		local items = 0
		local x = 0
		local z = 0
		local y = 0
		for ii, vv in pairs(v) do
			items = items + 1
			x = x + vv.x
			z = z + vv.z
		end
		x = x / items
		z = z / items
		y = Spring.GetGroundHeight(x, z)
		table.insert(self.hotSpots, { x = x, y = y, z = z, weight = items })
		--Spring.MarkerAddPoint(x,y,z,'hot ' ..items	)
	end
end

function MapHST:SimplifyMetalSpots(number) --reduce the number of metal spots for speed metal maps
	if #self.METALS <= 1024 then -- metal map is too complex, simplify it
		return self.METALS
	end
	local spots = {}
	local spotsCount = 0
	for x = 0, self.elmoMapSizeX - number, number do
		for z = 0, self.elmoMapSizeX - number, number do
			for i, spot in pairs(self.METALS) do
				if spot.x > x and spot.x < x + number and spot.z > z and spot.z < z + number then
					spotsCount = spotsCount + 1
					spots[spotsCount] = spot
					table.remove(self.METALS, i)
					break
				end
			end
		end
	end
	return spots
end

function MapHST:metalScan() --insert MEX in to the correct CELL and layer's network
	for i, spot in pairs(self.METALS) do
		local CELL = self:GetCell(spot, self.GRID)
		if not CELL then
			self:EchoDebug("no cell for this metal spot", spot)
			return
		end
		table.insert(CELL.metalSpots, spot)
		for layer, nets in pairs(self.networks) do
			if CELL.moveLayers[layer] then
				table.insert(self.networks[layer][CELL.moveLayers[layer]].metals, spot)
			end
		end
	end
end

function MapHST:geoScan() --insert GEOS in to the correct CELL and layer's network
	for i, spot in pairs(self.GEOS) do
		local CELL = self:GetCell(spot, self.GRID)
		if not CELL then
			self:EchoDebug("no cell for this geo spot", spot)
			return
		end
		table.insert(CELL.geoSpots, spot)
		for layer, nets in pairs(self.networks) do
			if CELL.moveLayers[layer] then
				table.insert(self.networks[layer][CELL.moveLayers[layer]].geos, spot)
			end
		end
	end
end

function MapHST:getPath(unitName, POS1, POS2, toGrid)
	local mclass = self.ai.armyhst.unitTable[unitName].mclass
	local pathObject = map:GetPathObject(mclass, POS1.x, POS1.y, POS1.z, POS2.x, POS2.y, POS2.z)
	if not pathObject then
		self:Warn("no path found", POS1, POS2)
		return
	end
	local waypoints = map:GetPathWaypoints(pathObject)
	if not waypoints then
		self:Warn("no waypoints for the object found", POS1, POS2)
		return
	end
	if toGrid then
		waypoints = self:gridThePath(waypoints)
	end
	return waypoints

end
function MapHST:gridThePath(wp, factor)
	factor = factor or self.gridSize
	local prev = #wp
	for i = #wp, 1, -1 do
		if i and i ~= prev then
			if
				self.ai.tool:RawDistance(wp[prev][1], wp[prev][2], wp[prev][3], wp[i][1], wp[i][2], wp[i][3]) < factor
			then
				table.remove(wp, i)
				prev = prev - 1
			else
				prev = i
			end
		end
	end
	for index, pos in pairs(wp) do
		pos.x = table.remove(pos, 1)
		pos.y = table.remove(pos, 1)
		pos.z = table.remove(pos, 1)
	end
	return wp
end

function MapHST:MobilityNetworkHere(mtype, position)
	if not mtype or not position then
		return nil
	end
	local cell = self:GetCell(position, self.GRID)
	if cell then
		return cell.moveLayers[mtype]
	end
end

function MapHST:MobilityOfUnit(unit)
	local position = unit:GetPosition()
	local name = unit:Name()
	local mtype = self.ai.armyhst.unitTable[name].mtype
	return mtype, self:MobilityNetworkHere(mtype, position)
end

function MapHST:UnitCanGoHere(unit, position, maxDistance)
	if not unit or not position then
		return false
	end
	local mtype, unet = self:MobilityOfUnit(unit)
	if mtype == "air" then
		return true
	end

	maxDistance = maxDistance or 128
	local ux, uy, uz = unit:GetRawPos()
	if self.ai.tool:RawDistance(ux, uy, uz, position.x, position.y, position.z) < 32 then
		self:EchoDebug(unit:Name(), "ask for a short pathtest: pass")
		return 32
	end
	local pathtest = map:TestPath(
		self.ai.armyhst.unitTable[unit:Name()].mclass,
		ux,
		uy,
		uz,
		position.x,
		position.y,
		position.z,
		nil,
		unit:Name()
	)
	if pathtest and pathtest < maxDistance then
		self:EchoDebug(unit:Name(), "ask for a pathtest: pass")
		return pathtest
	end
end

function MapHST:UnitCanGetToUnit(unit1, unit2)
	local position = unit2:GetPosition()
	return self:UnitCanGoHere(unit1, position)
end

function MapHST:AccessibleSpotsHere(mtype, position)
	local network = self:MobilityNetworkHere(mtype, position)
	if network then
		return self.networks[mtype][network].allSpots or {}
	end
	return {}
end

function MapHST:DrawDebug()
	for i = 0, 9 do
		self.map:EraseAll(i)
	end
	if not self.ai.drawDebug then
		return
	end
	local ch = 1
	local colours = {
		{ 1, 0, 0, 1 }, --'red'
		{ 0, 1, 0, 1 }, --'green'
		{ 0, 0, 1, 1 }, --'blue'
		{ 0, 1, 1, 1 },
		{ 1, 1, 0, 1 },
		{ 1, 1, 1, 1 },
		{ 0, 0, 0, 1 },
	}
	for i, p in pairs(self.hotSpots) do
		map:DrawPoint(p, colours[2], i, ch)
	end
	for i, p in pairs(self.METALS) do
		map:DrawPoint(p, colours[6], i, ch)
	end
	for i, p in pairs(self.GEOS) do
		map:DrawPoint(p, colours[6], i, ch)
	end
	for X, Zetas in pairs(self.GRID) do
		for Z, CELL in pairs(Zetas) do
			map:DrawPoint(CELL.POS, nil, X .. ":" .. Z .. " = " .. ((X - 1) * self.ai.maphst.gridSideX) + Z, 9)
			local pos1, pos2 = {}, {}
			pos1.x, pos1.z = CELL.POS.x - self.gridSizeHalf, CELL.POS.z - self.gridSizeHalf
			pos2.x, pos2.z = CELL.POS.x + self.gridSizeHalf, CELL.POS.z + self.gridSizeHalf
			pos1.y = 0
			pos2.y = 0
			map:DrawRectangle(pos1, pos2, colours[6], nil, false, ch)
			ch = 0
			for layer, unitName in pairs(CELL.moveLayers) do
				ch = ch + 1
				if CELL.moveLayers[layer] then
					map:DrawRectangle(pos1, pos2, colours[ch], CELL.moveLayers[layer], true, ch)
				end
			end
		end
	end
end
