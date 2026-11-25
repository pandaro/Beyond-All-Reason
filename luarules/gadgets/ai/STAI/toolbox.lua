Toolbox = {} --math and table helpers for every scope: no state, no ai, no game

local sqrt = math.sqrt
local twicePi = math.pi * 2

function Toolbox:RawDistance(x1, y1, z1, x2, y2, z2)
	local x = x1 - x2
	local y = y1 - y2
	local z = z1 - z2
	return sqrt((x * x) + (y * y) + (z * z))
end

function Toolbox:DISTANCE(POS1, POS2)
	local x = POS2.x - POS1.x
	local y = POS2.y - POS1.y
	local z = POS2.z - POS1.z
	return sqrt((x * x) + (y * y) + (z * z))
end

function Toolbox:distance(POS1, POS2)
	local x = POS2.x - POS1.x
	local z = POS2.z - POS1.z
	return sqrt((x * x) + (z * z))
end

function Toolbox:AngleAdd(angle1, angle2)
	return (angle1 + angle2) % twicePi
end

function Toolbox:PositionWithinRect(position, rect)
	return position.x > rect.x1 and position.x < rect.x2 and position.z > rect.z1 and position.z < rect.z2
end

function Toolbox:RectsOverlap(rectA, rectB)
	return rectA.x1 < rectB.x2 and rectB.x1 < rectA.x2 and rectA.z1 < rectB.z2 and rectB.z1 < rectA.z2
end

function Toolbox:pairsByKeys(t, f)
	local a = {}
	for n in pairs(t) do
		table.insert(a, n)
	end
	table.sort(a, f)
	local i = 0 -- iterator variable
	local iter = function() -- iterator function
		i = i + 1
		if a[i] == nil then
			return nil
		else
			return a[i], t[a[i]]
		end
	end
	return iter
end

function Toolbox:tableSorting(t)
	local Tkey = {}
	local Tvalue = {}
	for key, value in self:pairsByKeys(t) do
		table.insert(Tkey, key)
		table.insert(Tvalue, value)
	end
	return Tkey, Tvalue
end

function Toolbox:sortByDistance(POS, list)
	local distanceIndex = {}
	local dix = {}
	for index, pos in pairs(list) do
		distanceIndex[(self:distance(pos, POS))] = index
		dix[index] = (self:distance(pos, POS))
	end
	table.sort(dix)
	for i, v in pairs(dix) do
		dix[i] = list[distanceIndex[v]]
	end
	return dix
end

function Toolbox:listHasValue(list, value)
	for k, v in pairs(list) do
		if v == value then
			return k
		end
	end
	return false
end

function Toolbox:gcd(a, b)
	return b == 0 and a or self:gcd(b, a % b)
end

function Toolbox:tableConcat(tables)
	if type(tables) ~= "table" then
		return --concatenation require a table of tables
	end
	local T = {}
	for index, t in pairs(tables) do
		for k, value in pairs(t) do
			table.insert(T, value)
		end
	end
	return T
end
