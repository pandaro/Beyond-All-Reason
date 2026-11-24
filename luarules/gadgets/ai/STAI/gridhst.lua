GridHST = class(Module)

function GridHST:Name()
	return "GridHST"
end

function GridHST:internalName()
	return "gridhst"
end

function GridHST:Scope()
	return "team"
end

function GridHST:Init()
	self.DebugEnabled = false
	self:EchoDebug("GridHST START")
	self:basicGridInfo()
	self:createCells()
	self:EchoDebug("GridHST STOP")
end

function GridHST:basicGridInfo() --capture the map size and set the grid geometry
	local mapSize = map:MapDimensions()
	self.elmoMapSizeX = mapSize.x * 8
	self.elmoMapSizeZ = mapSize.z * 8
	self.gridSize = 256 --the only place in STAI that holds the cell size
	self.gridSizeHalf = self.gridSize / 2
	self.gridSizeDouble = self.gridSize * 2
	self.gridSideX = self.elmoMapSizeX / self.gridSize
	self.gridSideZ = self.elmoMapSizeZ / self.gridSize
	self.gridArea = self.gridSideX * self.gridSideZ
	self:EchoDebug("grid size: " .. self.gridSize .. "grid area", self.gridArea, self.gridSideX, self.gridSideZ)
end

function GridHST:createCells() --the cells of the grid, one for every index
	self.CELLS = {}
	for X = 1, self.gridSideX do
		for Z = 1, self.gridSideZ do
			local i = self:GridToIndex(X, Z)
			local x = (X * self.gridSize) - self.gridSizeHalf
			local z = (Z * self.gridSize) - self.gridSizeHalf
			local POS = {}
			POS.x, POS.z = x, z
			POS.y = map:GetGroundHeight(x, z)
			self:isInMap(POS) --move here ,is in map!!
			local CELL = {}
			CELL.INDEX = i --the cell index in CELLS
			CELL.X = X --the cell coordinate X on the grid
			CELL.Z = Z --the cell coordinate Z on the grid
			CELL.POS = POS --the cell position
			self.CELLS[i] = CELL
		end
	end
end

function GridHST:GridToIndex(X, Z) --the index of the cell X, Z in CELLS
	return (X - 1) * self.gridSideZ + Z
end

function GridHST:PosToIndex(pos) --the index of the cell holding pos, nil out of the grid
	local X, Z = self:PosToGrid(pos)
	if not self:IsCellInGrid(X, Z) then
		return
	end
	return self:GridToIndex(X, Z)
end

function GridHST:RawPosToIndex(x, z) --the index of the cell holding x, z, nil out of the grid
	local X, Z = self:RawPosToGrid(x, nil, z)
	if not self:IsCellInGrid(X, Z) then
		return
	end
	return self:GridToIndex(X, Z)
end

function GridHST:RawPosIsInMap(x, y, z)
	if (x <= 0) or (x > self.elmoMapSizeX) or (z <= 0) or (z > self.elmoMapSizeZ) then
		self:EchoDebug("bad position: " .. pos.x .. ", " .. pos.z)
		return nil
	else
		return x, y, z
	end
end

function GridHST:isInMap(pos)
	if (pos.x <= 0) or (pos.x > self.elmoMapSizeX) or (pos.z <= 0) or (pos.z > self.elmoMapSizeZ) then
		self:EchoDebug("bad position: " .. pos.x .. ", " .. pos.z)
		return nil
	else
		return pos
	end
end

function GridHST:PosToGrid(pos)
	local X = math.ceil(pos.x / self.gridSize)
	local Z = math.ceil(pos.z / self.gridSize)
	if not self:IsCellInGrid(X, Z) then
		self:EchoDebug(X, Z, "is out of GRID", pos.x, pos.z)
	end
	return X, Z
end

function GridHST:RawPosToGrid(x, y, z)
	local X = math.ceil(x / self.gridSize)
	local Z = math.ceil(z / self.gridSize)
	if not self:IsCellInGrid(X, Z) then
		self:EchoDebug(X, Z, "is out of GRID", x, z)
	end
	return X, Z
end

function GridHST:IsCellInGrid(X, Z)
	if X < 1 or Z < 1 or X > self.gridSideX or Z > self.gridSideZ then
		return nil
	end
	return true
end

function GridHST:GridToPos(X, Z)
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

function GridHST:GridToRawPos(X, Z)
	local x = X * self.gridSize - self.gridSizeHalf
	local z = Z * self.gridSize - self.gridSizeHalf
	local y = map:GetGroundHeight(x, z)
	if not self:RawPosIsInMap(x, y, z) then
		self:Warn(x, z, "is not in map")
		return
	end
	return x, y, z
end

function GridHST:areaCells(X, Z, R, grid) -- return alist of cells in range R from a cell
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

function GridHST:GetCell(X, Z, grid) --accept 1one position({t.x,t.y,t.z}) OR 2two XZ grid coordinate; return a CEll if exist
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

function GridHST:getCellsFields(p, fields, range, grid) --return the required list of values of a cell/cells
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
