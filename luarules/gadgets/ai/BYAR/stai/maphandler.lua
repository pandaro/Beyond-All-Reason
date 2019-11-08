MapHandler = class(Module)

function MapHandler:Name()
	return "MapHandler"
end

function MapHandler:internalName()
	return "maphandler"
end

MapHandler.DebugEnabled = false


function MapHandler:basicMapInfo()
--[[    for i,v in pairs(self) do
        print(i.. ' ' ..tostring(v))
    end
    for i,v in pairs(MapHandler) do
        print(i.. ' ' ..tostring(v))
    end]]   
    MapHandler.mapSize = self.map:MapDimensions()
    MapHandler.elmoMapSizeX = MapHandler.mapSize.x * 8
	MapHandler.elmoMapSizeZ = MapHandler.mapSize.z * 8    
    MapHandler.mobilityGridSize = math.max( math.floor(math.max(MapHandler.mapSize.x * 8, MapHandler.mapSize.z * 8) / 128),32)-- don't make grids smaller than 32
    MapHandler.mobilityGridSizeHalf = MapHandler.mobilityGridSize/ 2
	MapHandler.maxX = math.ceil((MapHandler.mapSize.x * 8) / MapHandler.mobilityGridSize)
	MapHandler.maxZ = math.ceil((MapHandler.mapSize.z * 8) / MapHandler.mobilityGridSize)
    self:EchoDebug("grid size: " .. MapHandler.mobilityGridSize)
--     self:EchoDebug("Map size in grids: x "..MapHandler.maxX.." z "..MapHandler.maxZ)
end



local mapColors = {
	veh = { 1, 0, 0 },
	bot = { 0, 1, 0 },
	hov = { 0, 0, 1 },
	shp = { 1, 0, 0 },
	amp = { 0, 1, 0 },
	sub = { 0, 0, 1 },
	start = { 1, 1, 1, 1 },
}

local mapChannels = {
	veh = { 4 },
	bot = { 4 },
	hov = { 4 },
	sub = { 5 },
	amp = { 5 },
	shp = { 5 },
	start = { 4, 5 },
}

-- mobTypes = {}
local mobUnitTypes = {}
local UWMetalSpotCheckUnitType

local topology
local mobMap
local mobilityGridMaxX, mobilityGridMaxZ
local mobCount
local totalCount
local geoSpots
local didMapSpotMobility
local mobSpots, mobNetworks, mobNetworkCount
local mobNetworkMetals
local networkSize
local mobNetworkGeos
local scoutSpots
local UWMetalSpots, landMetalSpots
local mobilityGridSize, mobilityGridSizeHalf
local mobilityGridArea
local hotSpot
local spotPathMobRank
local spotPathMobRankSuccessOnly
local mobilityRatingFloor

local pathGraphs = {}

local savepositions = {}

local mSqrt = math.sqrt
local mCeil = math.ceil

local function Distance3d(pos1, pos2)
	local dx = pos2.x - pos1.x
	local dy = pos2.y - pos1.y
	local dz = pos2.z - pos1.z
	return mSqrt( dx*dx + dy*dy + dz*dz )
end

local function MapDataFilename()
	local mapName = string.gsub(map:MapName(), "%W", "_")
	return "cache/Shard-" .. game:GameName() .. "-" .. mapName .. ".lua"
end

local function serialize (o, keylist)
  if keylist == nil then keylist = "" end
  if type(o) == "number" then
    mapdatafile:write(o)
  elseif type(o) == "boolean" then
  	mapdatafile:write(tostring(o))
  elseif type(o) == "string" then
    mapdatafile:write(string.format("%q", o))
  elseif type(o) == "userdata" then
  	-- assume it's a position
  	mapdatafile:write("api.Position()")
  	table.insert(savepositions, {keylist = keylist, position = o})
  	--mapdatafile:write("{ x = " .. math.ceil(o.x) .. ", y = " .. math.ceil(o.y) .. ", z = " .. math.ceil(o.z) .. " }")
  elseif type(o) == "table" then
    mapdatafile:write("{\n")
    for k,v in pairs(o) do
      mapdatafile:write("  [")
      serialize(k)
      mapdatafile:write("] = ")
      local newkeylist
      if type(v) == "table" or type(v) == "userdata" then
      	if type(k) == "string" then
        	newkeylist = keylist .. "[\""  .. k .. "\"]"
        elseif type(k) == "number" then
        	newkeylist = keylist .. "["  .. k .. "]"
        end
      end
      serialize(v, newkeylist)
      mapdatafile:write(",\n")
    end
    mapdatafile:write("}\n")
  else
    error("cannot serialize a " .. type(o))
  end
end

local function EchoData(name, o)
	savepositions = {}
	mapdatafile:write(name)
	mapdatafile:write(" = ")
	serialize(o)
	mapdatafile:write("\n\n")
	if #savepositions > 0 then
		for i, sp in pairs (savepositions) do
			mapdatafile:write(name .. sp.keylist .. ".x = " .. sp.position.x .. "\n")
			mapdatafile:write(name .. sp.keylist .. ".y = " .. sp.position.y .. "\n")
			mapdatafile:write(name .. sp.keylist .. ".z = " .. sp.position.z .. "\n")
		end
		mapdatafile:write("\n\n")
	end
	self:EchoDebug("wrote " .. name)
end

local function AddColors(colorA, colorB)
	local color = {}
	for i = 1, 4 do
		if colorA[i] or colorB[i] then
			color[i] = (colorA[i] or 0) + (colorB[i] or 0)
			color[i] = math.min(color[i], 1)
		end
	end
	return color
end

local function GetColorFromLabel(label)
	local color = mapColors[label] or { 1, 1, 1 }
	color[4] = color[4] or 0.33
	return color
end

local function GetChannelsFromLabel(label)
	local channels = mapChannels[label] or {4}
	return channels
end

local function PlotDebug(x, z, label, labelAdd)
	if DebugDrawEnabled then
		x = math.ceil(x)
		z = math.ceil(z)
		local pointString = x .. "  " .. z
		if label == nil then label= "nil" end
		local pos = api.Position()
		pos.x, pos.z = x, z
		local color = GetColorFromLabel(label)
		local channels = GetChannelsFromLabel(label)
		if labelAdd then label = label .. ' ' .. labelAdd end
		for i = 1, #channels do
			local channel = channels[i]
			self.map:DrawPoint(pos, color, label, channel)
		end
	end
end

local function MiddleOfTwo(pos1, pos2)
	local middle = api.Position()
	middle.x, middle.y, middle.z = (pos1.x+pos2.x)/2, (pos1.y+pos2.y)/2,(pos1.z+pos2.z)/2
	return middle
end

local function Check1Topology(x, z, mtype, network)
	if mobMap[mtype][x] == nil then
		return 1
	elseif mobMap[mtype][x][z] == nil then
		return 1
	else
		return mobMap[mtype][x][z]
	end
end

function distance(pos1,pos2)
	local xd = pos1.x-pos2.x
	local zd = pos1.z-pos2.z
	local yd = pos1.y-pos2.y
	if yd < 0 then
		yd = -yd
	end
	dist = math.sqrt(xd*xd + zd*zd + yd*yd*yd)
	return dist
end

local function Flood4Topology(x, z, mtype, network)
	if x > mobilityGridMaxX or x < 1 or z > mobilityGridMaxZ or z < 1 then return end
	--precheck throws out 1-wide bottlenecks
	local blocked = 0
	blocked = blocked + Check1Topology(x+1, z, mtype, network)
	blocked = blocked + Check1Topology(x-1, z, mtype, network)
	if blocked == 2 then return end
	blocked = blocked + Check1Topology(x, z+1, mtype, network)
	if blocked == 2 then return end
	blocked = blocked + Check1Topology(x, z-1, mtype, network)
	if blocked == 2 then return end
	-- now actually flood fill
	local actualValue = mobMap[mtype][x][z]
	if actualValue and (actualValue == 0) and topology[mtype][x][z] == nil then
		topology[mtype][x][z] = network
		networkSize[mtype][network] = networkSize[mtype][network] + 1
		Flood4Topology(x+1,z,mtype,network)
		Flood4Topology(x-1,z,mtype,network)
		Flood4Topology(x,z+1,mtype,network)
		Flood4Topology(x,z-1,mtype,network)
	end
end

local function Flood8Topology(x, z, mtype, network)
	if x > mobilityGridMaxX or x < 1 or z > mobilityGridMaxZ or z < 1 then return end
	local actualValue = mobMap[mtype][x][z]
	if actualValue and (actualValue == 0) and topology[mtype][x][z] == nil then
		topology[mtype][x][z] = network
		networkSize[mtype][network] = networkSize[mtype][network] + 1
		Flood8Topology(x+1,z,mtype,network)
		Flood8Topology(x-1,z,mtype,network)
		Flood8Topology(x,z+1,mtype,network)
		Flood8Topology(x,z-1,mtype,network)
		Flood8Topology(x+1,z+1,mtype,network)
		Flood8Topology(x-1,z+1,mtype,network)
		Flood8Topology(x+1,z-1,mtype,network)
		Flood8Topology(x-1,z-1,mtype,network)
	end
end

function MapHandler:MapMobility()
	-- check for water map works like this:
	-- the map is divided into sectors, then center of each sector is tested if specific unit can be built there (water, kbot, vehicle)
	local mapSize = self.map:MapDimensions()
	mobilityGridSize = math.floor(math.max(mapSize.x * 8, mapSize.z * 8) / 128)
	mobilityGridSize = math.max(mobilityGridSize, 32) -- don't make grids smaller than 32
	mobilityGridSizeHalf = mobilityGridSize/ 2
	self:EchoDebug("grid size: " .. mobilityGridSize)
	local maxX = math.ceil((mapSize.x * 8) / mobilityGridSize)
	local maxZ = math.ceil((mapSize.z * 8) / mobilityGridSize)
	self:EchoDebug("Map size in grids: x "..maxX.." z "..maxZ)
	mobilityGridMaxX = maxX
	mobilityGridMaxZ = maxZ
	local mobCount = {}
	local totalCount = maxX * maxZ
	local half = mobilityGridSizeHalf
	local pos = api.Position()
	pos.y = 0
	mobMap = {}
	for mtype, utypes in pairs(mobUnitTypes) do
		mobMap[mtype] = {}
		mobCount[mtype] = 0
	end
	for x = 1, maxX do
		for mtype, utypes in pairs(mobUnitTypes) do
			mobMap[mtype][x] = {}
		end
		for z = 1, maxZ do
			-- all blocked unless unblocked below
			for mtype, utypes in pairs(mobUnitTypes) do
				mobMap[mtype][x][z] = 1
			end
			pos.x = (x * mobilityGridSize) - half
			pos.z = (z * mobilityGridSize) - half
			-- find out if each mobility type can exist there
			for mtype, utypes in pairs(mobUnitTypes) do
				local canbuild = false
                local uname = mobUnitExampleName[mtype]
                local uDef = UnitDefNames[uname]
                canbuild = Spring.TestMoveOrder(uDef.id, pos.x, Spring.GetGroundHeight(pos.x,pos.z), pos.z)
				if canbuild then
					-- self:EchoDebug(mtype .. " at " .. x .. "," .. z .. " count " .. mobCount[mtype])
					mobCount[mtype] = mobCount[mtype] + 1
					mobMap[mtype][x][z] = 0
				end
			end
			-- self:EchoDebug(x .. "," .. z .. " sub " .. subMap[x][z] .. " bot " .. botMap[x][z] .. " veh " .. vehMap[x][z])
		end
	end
	return totalCount, maxX, maxZ, mobCount
end

local function InitializeTopology()
	topology = {}
	for mtype, utypes in pairs(mobUnitTypes) do
		topology[mtype] = {}
	end
	topology["air"] = {}
	for x = 1, mobilityGridMaxX do
		for mtype, utypes in pairs(mobUnitTypes) do
			topology[mtype][x] = {}
		end
		topology["air"][x] = {}
		for z = 1, mobilityGridMaxZ do
			-- fill air topology with single network
			topology["air"][x][z] = 1
		end
	end
end

function MapHandler:MapSpotMobility(metals, geos)
	local half = mobilityGridSizeHalf
	networkSize = {}
	mobNetworkGeos = {}
	mobNetworkGeos['air'] = {}
	mobNetworkGeos['air'][1] = geos
	scoutSpots = {}
	scoutSpots["air"] = {}
	scoutSpots["air"][1] = {}
	local mobNetworkMetals = {}
	mobNetworkMetals["air"] = {}
	mobNetworkMetals["air"][1] = {}
	local mobSpots = {}
	local mobNetworks = {}
	local mobNetworkCount = {}
	for mtype, utypes in pairs(mobUnitTypes) do
		mobSpots[mtype] = {}
		mobNetworkMetals[mtype] = {}
		mobNetworkCount[mtype] = {}
		mobNetworks[mtype] = 0
		networkSize[mtype] = {}
		scoutSpots[mtype] = {}
		mobNetworkGeos[mtype] = {}
	end
	for metalOrGeo = 1, 2 do
		local spots
		if metalOrGeo == 1 then
			spots = metals
		else
			spots = geos
		end
		for i, spot in pairs(spots) do
			local landOrWater
			if metalOrGeo == 1 then
				if self.map:CanBuildHere(UWMetalSpotCheckUnitType, spot) then
					table.insert(UWMetalSpots, spot)
					landOrWater = 2
				else
					table.insert(landMetalSpots, spot)
					landOrWater = 1
				end
			end
			local x = math.ceil(spot.x / mobilityGridSize)
			local z = math.ceil(spot.z / mobilityGridSize)
			for mtype, utypes in pairs(mobUnitTypes) do
				if mobMap and mobMap[mtype] and mobMap[mtype][x] and mobMap[mtype][x][z] == 0 then
					local thisNetwork
					if topology[mtype][x][z] == nil then
						-- if topology is empty here, initiate a new network, and flood fill it
						mobNetworks[mtype] = mobNetworks[mtype] + 1
						thisNetwork = mobNetworks[mtype]
						mobNetworkCount[mtype][thisNetwork] = 1
						networkSize[mtype][thisNetwork] = 0
						mobNetworkMetals[mtype][thisNetwork] = {}
						PlotDebug(x * mobilityGridSize - mobilityGridSizeHalf, z * mobilityGridSize - mobilityGridSizeHalf, mtype, thisNetwork)
						Flood4Topology(x, z, mtype, mobNetworks[mtype])
					else
						-- if topology isn't empty here, add this spot to its count
						thisNetwork = topology[mtype][x][z]
						mobNetworkCount[mtype][thisNetwork] = mobNetworkCount[mtype][thisNetwork] + 1
					end
					table.insert(mobSpots[mtype], {x = x, z = z})
					if metalOrGeo == 1 then
						if landOrWater == 1 and mtype ~= "sub" and mtype ~= "shp" then
							table.insert(mobNetworkMetals[mtype][thisNetwork], spot)
						elseif landOrWater == 2 and mtype ~= "veh" and mtype ~= "bot" then
							table.insert(mobNetworkMetals[mtype][thisNetwork], spot)
						end
					else
						mobNetworkGeos[mtype][thisNetwork] = mobNetworkGeos[mtype][thisNetwork] or {}
						table.insert(mobNetworkGeos[mtype][thisNetwork], spot)
					end
					scoutSpots[mtype][thisNetwork] = scoutSpots[mtype][thisNetwork] or {}
					table.insert(scoutSpots[mtype][thisNetwork], spot)
				end
			end
			if metalOrGeo == 1 then table.insert(mobNetworkMetals["air"][1], spot) end
			table.insert(scoutSpots["air"][1], spot)
		end
	end
	didMapSpotMobility = true
	return mobSpots, mobNetworkMetals, mobNetworks, mobNetworkCount
end

function MapHandler:MergePositions(posTable, cutoff, includeNonMerged)
	local list = {} -- make copy to prevent clearing table
	for k, v in pairs(posTable) do table.insert(list, v) end
	self:EchoDebug('#list&cutof',#list .. " " .. cutoff)
	local merged = {}
	while #list > 0 do
		local lp = table.remove(list)
		local pos1 = api.Position()
		pos1.x, pos1.y, pos1.z = lp.x, lp.y, lp.z
		local merge = nil
		for i = #list, 1, -1 do
			local pos2 = list[i]
			local dist = Distance(pos1, pos2)
			if dist < cutoff then
				self:EchoDebug("merging " .. pos1.x .. "," .. pos1.z .. " with " .. pos2.x .. "," .. pos2.z .. " -- " .. dist .. " away")
				merge = MiddleOfTwo(pos1, pos2)
				pos1 = merge
				table.remove(list, i)
			end
		end
		if merge ~= nil then
			table.insert(merged, merge)
		elseif includeNonMerged then
			table.insert(merged, pos1)
		end
	end
	self:EchoDebug('#merged',#merged)
	return merged
end

function MapHandler:Update()
-- 	-- workaround for shifting metal spots: map data is reloaded every two minutess
-- 	local f = Spring.GetGameFrame()
--     self:EchoDebug('frame',f)
-- 	if f > self.lastDataResetFrame + 3600 then
-- 		-- self:LoadMapData()
-- 		self.lastDataResetFrame = f
-- 	end
end

function MapHandler:Init()
        self:EchoDebug('MapHandler START')
    self:EchoDebug('self',self)
--     MapHandler.map = self.map
    self:basicMapInfo()
    for i,v in pairs(self.ai) do
        self:EchoDebug('self.ai',i,v)
    end
--     self:EchoDebug('-------------------------------ai------------------------------------',ai)
--     
--     self:EchoDebug('MapHandler',MapHandler)
--     for i,v in pairs(MapHandler) do
--         self:EchoDebug(i,v)
--     end    
    

    
	if DebugDrawEnabled then
		self.map:EraseAll(4, 5)
	end
   
	local mapSize = self.map:MapDimensions()
	self.elmoMapSizeX = mapSize.x * 8
	self.elmoMapSizeZ = mapSize.z * 8

	-- factoryMobilities = self:GetFactoryMobilities()

	self.conUnitPerTypeLimit = math.max(self.map:SpotCount() / 6, 4)--add here cause map:spotcount not correctly load or so
	self.conUnitAdvPerTypeLimit = math.max(self.map:SpotCount() / 8, 2)
	self.activeMobTypes = {}
	self.factoryListMap = {}

	-- local dataloaded = self:LoadMapData()

	self.lastDataResetFrame = Spring.GetGameFrame()
    
	if dataloaded then
		return
	end

	mobilityGridSize = 256 -- will be recalculated by MapMobility()
    
	for mtype, unames in pairs(mobUnitNames) do
		mobUnitTypes[mtype] = {}
		for i, uname in pairs(unames) do
			mobUnitTypes[mtype][i] = self.game:GetTypeByName(uname)
		end
	end
	UWMetalSpotCheckUnitType = self.game:GetTypeByName(UWMetalSpotCheckUnit)

	if not mobMap then
		totalCount, mobilityGridMaxX, mobilityGridMaxZ, mobCount = self:MapMobility()
	end
	mobilityGridArea = totalCount
	self.mobilityGridArea = totalCount
	self.mobCount = mobCount
	if not topology then
		InitializeTopology()
	end
    
	-- now let's see how much water we found
	self:EchoDebug("total sectors "..totalCount)
	local wetness = mobCount["sub"] * 100 / totalCount
	self:EchoDebug("map wetness is "..wetness)
	self.waterMap = wetness >= 10
	self:EchoDebug("there is water on the map")

	for mtype, count in pairs(mobCount) do
		local ness = count * 100 / totalCount
		self:EchoDebug("map " .. mtype .. "-ness is " .. ness .. " and total grids: " .. count)
	end

	self.spots = self.map:GetMetalSpots()
	-- copy metal spots
	local metalSpots = {}
	for k, v in pairs(self.spots) do table.insert(metalSpots, v) end
	if #metalSpots > 1600 then
		-- metal map is too complex, simplify it
		metalSpots = self:SimplifyMetalSpots(metalSpots, 1600)
		self.spots = metalSpots
	end

	-- now let's find out are there any geo spots on the map
	-- and add them to allSpots
	-- supposedly they have "geo" in names (don't know of a better way)
	if not geoSpots then
		local tmpFeatures = self.map:GetMapFeatures()
		self.mapHasGeothermal = false
		geoSpots = {}
		if tmpFeatures then
			for _, feature in pairs(tmpFeatures) do
				if feature then
					tmpName = feature:Name()
					if tmpName == "geovent" then
						self.mapHasGeothermal = true
						table.insert(geoSpots, feature:GetPosition())
					end
				end
			end
		end
		self:EchoDebug(#geoSpots, "geovents")
	end
    
	if not didMapSpotMobility then
		UWMetalSpots = {}
		landMetalSpots = {}
		mobSpots, mobNetworkMetals, mobNetworks, mobNetworkCount = self:MapSpotMobility(metalSpots, geoSpots)
	end
   
	self.landMetalSpots = landMetalSpots
	self.UWMetalSpots = UWMetalSpots
	self.scoutSpots = scoutSpots
	self.mobNetworkMetals = mobNetworkMetals
	self.mobNetworks = mobNetworks
	if not hotSpot then
		hotSpot = self:SpotSimplyfier(metalSpots,geoSpots)
	end
    
	self.hotSpot = hotSpot
	if not spotPathMobRank then
		spotPathMobRank, spotPathMobRankSuccessOnly = self:SpotPathMobRank(scoutSpots.air[1])
    else
        
        self:EchoDebug('spotPathMobRank',spotPathMobRank)
	end
    
	for mtype, mspots in pairs(mobSpots) do
		self:EchoDebug('mtype-spots-#spots',mtype .. " spots: " .. #mspots)
	end
	-- self:EchoDebug(" spots sub:" .. #mobSpots["sub"] .. " bot:" .. #mobSpots["bot"] .. " veh:" .. #mobSpots["veh"])
	for mtype, utypes in pairs(mobUnitTypes) do
		self:EchoDebug(mtype .. "  networks: " .. mobNetworks[mtype])
		for n, count in pairs(mobNetworkCount[mtype]) do
			self:EchoDebug("network #" .. n .. " has " .. count .. " spots and " .. networkSize[mtype][n] .. " grids")
		end
	end


	-- deciding what kind of map it is
	local maxSpots = 0
	local minNetworks = 5
	local best = nil
	local mobRating = {}
	local totalRating = 0
	local numberOfRatings = 0
	for mtype, spots in pairs(mobSpots) do
		if #spots > maxSpots then
			if mobNetworks[mtype] < minNetworks then
				maxSpots = #spots
				minNetworks = mobNetworks[mtype]
				best = mtype
			end
		end
		local mostGrids = 0
		local mostSpots = 0
		if networkSize[mtype] ~= nil then
			for n, size in pairs(networkSize[mtype]) do
				if size > mostGrids and #scoutSpots[mtype][n] > mostSpots then
					mostGrids = size
					mostSpots = #scoutSpots[mtype][n]
				end
			end
		end
		if mobNetworks[mtype] == 0 then
			mobRating[mtype] = 0
		else
			mobRating[mtype] = ((mostSpots - mobNetworks[mtype]) + ((mostGrids / mobilityGridArea) * mostSpots * 0.25))
		end
		totalRating = totalRating + mobRating[mtype]
		numberOfRatings = numberOfRatings + 1
		self:EchoDebug(mtype .. " rating: " .. mobRating[mtype])
	end
    
	-- add in bechmark air rating
	-- local airRating = (#scoutSpots["air"][1] + (#scoutSpots["air"][1] * 0.25)) * 0.5
	local airRating = #scoutSpots["air"][1] + (#scoutSpots["air"][1] * 0.25)
	mobRating['air'] = airRating
	totalRating = totalRating + airRating
	numberOfRatings = numberOfRatings + 1
	self:EchoDebug('air rating: ' .. airRating)
	local avgRating = totalRating / numberOfRatings
	local ratingFloor = avgRating * 0.65
	self:EchoDebug('average rating: ' .. avgRating)
	self:EchoDebug('rating floor: ' .. ratingFloor)
	mobilityRatingFloor = ratingFloor

	self.mobRating = mobRating

	self.hasUWSpots = #mobSpots["sub"] > 0

	if self.hasUWSpots then
		self:EchoDebug("MapHandler: Submerged metal spots detected")
	end

	-- find start locations (loading them into air's list for later localization)
	self.startLocations = {}
	if self.startLocations["air"] == nil then self.startLocations["air"] = {} end
	self.startLocations["air"][1] = self:GuessStartLocations(metalSpots)
	if self.startLocations["air"][1] ~= nil then
		-- localize start locations into mobility networks
		for i, start in pairs(self.startLocations["air"][1]) do
			self:EchoDebug("start location guessed at: " .. start.x .. ", " .. start.z)
			PlotDebug(start.x, start.z, "start")
			for mtype, networkList in pairs(scoutSpots) do
				if mtype ~= "air" then -- air list is already filled
					for n, spots in pairs(networkList) do
						if self.startLocations[mtype] == nil then self.startLocations[mtype] = {} end
						if self.startLocations[mtype][n] == nil then self.startLocations[mtype][n] = {} end
						table.insert(self.startLocations[mtype][n], start)
					end
				end
			end
		end
	end
    
	-- self:SaveMapData()

	-- cleanup
	mobMap = nil
	self.factoriesRanking, self.ranksByFactories = self:factoriesRating()

	self:DebugDrawMobilities()

    self:EchoDebug('MapHandler STOP')
    
end

-- gives all kinds of unexpected results
-- function MapHandler:GetFactoryMobilities()
-- 	local factMobs = {}
-- 	for uname, utable in pairs(unitTable) do
-- 		if utable.unitsCanBuild and #utable.unitsCanBuild > 0 then
-- 			factMobs[uname] = {}
-- 			local haveMtype = {}
-- 			for i = 1, #utable.unitsCanBuild do
-- 				local canBuildName = utable.unitsCanBuild[i]
-- 				local mtype = unitTable[canBuildName].mtype
-- 				if not haveMtype[mtype] then
-- 					factMobs[uname][#factMobs[uname]+1] = mtype
-- 					haveMtype[mtype] = true
-- 					self:EchoDebug(uname .. " " .. mtype)
-- 				end
-- 			end
-- 		end
-- 	end
-- 	return factMobs
-- end

function MapHandler:SpotSimplyfier(metalSpots,geoSpots)
	local spots = {}
	local mirrorspots = {}
	local limit = (self.map:MapDimensions())
	local limit = limit.x/2  + limit.z/2
	for i,v in pairs(metalSpots) do 
		table.insert(spots,v)
	end
	for i,v in pairs(geoSpots) do 
		table.insert(spots,v)
	end
	local spotscleaned={ }
	self:EchoDebug('limit',tostring(limit))
	for index1,pos1 in pairs(spots) do 
		if spots[index1] ~= false then
			mirrorspots[index1] = {}
			mirrorspots[index1][index1] = pos1
			spots[index1] = false
			--Spring.MarkerAddPoint(pos1.x,pos1.y,pos1.z, tostring(i))--uncomment this to draw the hotspot reducing system
			for index2,pos2 in pairs(spots) do 
				if spots[index2] ~= false then
					local dist = Distance(pos1,pos2)
					if dist < limit and dist > 0 and ((pos1.y > 0 and pos2.y > 0) or (pos1.y < 0 and pos2.y < 0)) then
						mirrorspots[index1][index2] = pos2
						--Spring.MarkerAddLine(pos1.x, pos1.y, pos1.z, pos2.x, pos2.y, pos2.z)--uncomment this to draw all the hotspot on map
						spots[index2] = false
					end
				end
			end
		end
	end
	for i,v in pairs(mirrorspots) do
		local items = 0
		mirrorspots[i] = api.Position()
		for ii,vv in pairs(v) do
			items = items+1
			mirrorspots[i].x = mirrorspots[i].x+vv.x
			mirrorspots[i].y = mirrorspots[i].y+vv.y
			mirrorspots[i].z = mirrorspots[i].z+vv.z
		end
		local x =mirrorspots[i].x/items
		local z = mirrorspots[i].z/items
		local y = 0
		y = Spring.GetGroundHeight(x,z)
		mirrorspots[i].x = x
		mirrorspots[i].y = y
		mirrorspots[i].z = z
		if DebugDrawEnabled then self.map:DrawPoint(mirrorspots[i], {1,0,1}, 'hotspot', 6) end
	end
	return mirrorspots
end

function MapHandler:SpotPathMobRank(spotscleaned)
    self:EchoDebug('spotPathMobRank START')
	local moveclass = {}
	local pathDistRatios = {}
	local pathDistRatiosSuccessOnly = {}

    for id,unitDef in pairs(UnitDefs) do
		if unitDef.moveDef.name  then--maybe because we have already chickens
			if moveclass[unitDef.moveDef.name] ==   nil then
				moveclass[unitDef.moveDef.name] = id
                self:EchoDebug('name&id',unitDef.moveDef.name,id)
			end
		end
	end
                                                                                                                    
	for mclass, number in pairs(moveclass) do
		pathDistRatios[mclass] = 0
		pathDistRatiosSuccessOnly[mclass] = 0
		local mySpots = {}
		for i = 1, #spotscleaned do
			mySpots[i] = spotscleaned[i]
		end
		local pathCount = 0
		local pathSuccessCount = 0
		local pos1 = table.remove(mySpots)
		while #mySpots > 0 do
			local pos2 = table.remove(mySpots)
			if Spring.TestMoveOrder(number,pos1.x,pos1.y,pos1.z) == true and Spring.TestMoveOrder(number,pos2.x,pos2.y,pos2.z) == true then
				local metapath = Spring.RequestPath(mclass, pos1.x,pos1.y,pos1.z,pos2.x,pos2.y,pos2.z) 
				if metapath then 
					local waypoints, pathStartIdx = metapath:GetPathWayPoints()
					local dist  = Distance3d(pos1,pos2)
					if waypoints and #waypoints > 0 and dist > 0 then
                        --self:EchoDebug(mclass,'has a path')
-- 						if mclass == 'tank2' then
-- 							self.map:DrawLine(pos1, pos2, {0,0,0,1}, nil, true, 1)
-- 						end
						local waypointsNumber = #waypoints
						local last = waypoints[#waypoints]
						if pos2.x == last[1] and pos2.z == last[3] then
							local totalPathDist = 0
							for i = 2, waypointsNumber do
								local wp1 = waypoints[i-1]
								local wp2 = waypoints[i]
								local dx = wp2[1] - wp1[1]
								local dy = wp2[2] - wp1[2]
								local dz = wp2[3] - wp1[3]
								local segDist = math.sqrt(dx*dx + dy*dy + dz*dz) + 1
								totalPathDist = totalPathDist + segDist 
                                
--                                 self:EchoDebug(segDist)
-- 								if mclass == 'tank2' then
-- 									self.map:DrawLine({x=wp1[1], y=wp1[2], z=wp1[3]}, {x=wp2[1], y=wp2[2], z=wp2[3]}, {1,1,1,1}, nil, true, 1)
-- 								end
							end
                            if totalPathDist == 0 then totalPathDist = 1 end --TODO understand why totalpathdist somtime is 0
							pathDistRatios[mclass] = pathDistRatios[mclass] + (dist / totalPathDist)
							pathCount = pathCount + 1
							pathSuccessCount = pathSuccessCount + 1
							self:EchoDebug('mclasstotpathdistdist',mclass,UnitDefs[number].name,dist, totalPathDist, dist / totalPathDist,pathDistRatios[mclass])
						else
							--self:EchoDebug('path does not get to destination')
							pathCount = pathCount + 1
						end
                        
                        
                    else
					end
				end
			end
			pos1 = pos2
		end
		if pathDistRatios[mclass] > 0 then
			if pathSuccessCount > 0 then
				-- dist ratio of only paths that get to their destinations
				pathDistRatiosSuccessOnly[mclass] = pathDistRatios[mclass] / pathSuccessCount
			end
			if pathCount > 0 then
				pathDistRatios[mclass] = pathDistRatios[mclass] / pathCount
			end
		end
		self:EchoDebug('spmr',mclass, pathDistRatios[mclass], pathDistRatiosSuccessOnly[mclass])
	end
    for pathType, rank in pairs(pathDistRatios) do
        self:EchoDebug('pathdistRatios',pathType .. ' = ' ..rank)
    end
    self:EchoDebug('spotPathMobRank STOP')
	return pathDistRatios, pathDistRatiosSuccessOnly
end

function MapHandler:GuessStartLocations(spots)
	if spots == nil then return end
	if #spots == 0 then
		self:EchoDebug("spot table for start location guessing is empty")
		return
	end

	-- find links
	local spotsCopy = {}
	for i, v in pairs(spots) do table.insert(spotsCopy, v) end
	local minDist = 1000
	local links = {}
	local from = table.remove(spotsCopy)
	while #spotsCopy > 0 do
		local closest = nil
		for i, to in pairs(spotsCopy) do
			local dist = Distance(from, to)
			if dist < minDist then
				minDist = dist
				closest = i
			end
			local middle = MiddleOfTwo(from, to)
			table.insert(links, {dist = dist, middle = middle})
		end
		if closest ~= nil then
			from = table.remove(spotsCopy, closest)
		else
			from = table.remove(spotsCopy)
		end
	end

	-- look for matches
	local matches = {}
	local tolerance = minDist * 0.5
	local cutoff = minDist + tolerance
	self:EchoDebug("tolerance: " .. tolerance .. "  cutoff: " .. cutoff)
	for i, l in pairs(links) do
		if l.dist < cutoff then
			self:EchoDebug("metal spot link at " .. math.ceil(l.middle.x) .. "," .. math.ceil(l.middle.z) .. " within cutoff with distance of " .. math.ceil(l.dist))
			table.insert(matches, l.middle)
		end
	end
	if #matches == 0 then return end

	-- merge matches close to each other
	local merged = self:MergePositions(matches, cutoff, false)
	if #merged < 2 then
		self:EchoDebug("not enough merged, using all matches")
		return matches
	else
		self:EchoDebug("using merged links")
		return merged
	end
end

function MapHandler:factoriesRating()
	local mtypesMapRatings = {}
	local factoryRating = {}
	self.factoryBuilded = {}
	self.factoryBuilded['air'] = {}
	for mtype, networks in pairs(networkSize) do
		self.factoryBuilded[mtype] = {}
		for network, size in pairs(networks) do
			local spots = self.mobNetworkMetals[mtype][network] or {}
			spots = #spots
			if size > mobilityGridArea * 0.20 and spots > (#landMetalSpots + #UWMetalSpots) * 0.4 then
				-- area large enough and enough metal spots
				self.factoryBuilded[mtype][network] = 0 
			end
		end
	end
	self.factoryBuilded['air'][1] = 0
	for mtype, unames in pairs(mobUnitNames) do
		local realMetals = 0
		local realSize = 0
		local realGeos = 0
		local spots = 0
		local geos= 0
		local realRating = self.mobRating[mtype] / 100
        
		if self.mobCount[mtype] ~= 0 then
			realSize = self.mobCount[mtype] / mobilityGridArea --relative area occupable
		end
		
		if #landMetalSpots + #UWMetalSpots ~= 0 then
			for network, index in pairs(self.mobNetworkMetals[mtype]) do
				spots=spots + #index
			end
			realMetals = spots / (#landMetalSpots + #UWMetalSpots)--relative metals occupable
		end
		
		if #geoSpots ~= 0 and mtype ~= ('shp' or 'sub') then 
			realGeos = math.min(0.1 * #geoSpots,1) --if there are more then 10 geos is useless give it more weight on bestfactory type calculations
		end 
		
		mtypesMapRatings[mtype] = (( realMetals + realSize + realGeos) / 3) * realRating
		mtypesMapRatings[mtype] = (self.mobRating[mtype] / self.mobRating['air']) * mobilityEffeciencyMultiplier[mtype]
		-- area is not as important as number of metal and geo
		-- mtypesMapRatings[mtype] = (( realMetals + (realSize*0.5) + realGeos) / 2.5) * mobilityEffeciencyMultiplier[mtype]
		self:EchoDebug('mtypes map rating ' ..mtype .. ' = ' .. mtypesMapRatings[mtype])
	end
	mtypesMapRatings['air'] = mobilityEffeciencyMultiplier['air']


	local bestPath = 0
	for factory,mtypes in pairs(factoryMobilities)do
		local factoryPathRating = 0
		local factoryMtypeRating = 0
		if mtypes[1] ~='air' then
			local factoryBuildsCons = false
			for index, unit in pairs(unitTable[factory].unitsCanBuild) do
				local mtype = unitTable[unit].mtype
				if unitTable[unit].buildOptions then
					if (self.hasUWSpots and mtype ~= 'veh') or (not self.hasUWSpots and mtype ~= 'amp') then
					-- if self.hasUWSpots or not (mtype == 'amp' and mtypes[1] == 'veh') then
						factoryBuildsCons = true
						break
					end
				end
			end
			self:EchoDebug(factory .. " builds cons: " .. tostring(factoryBuildsCons))
			local count = 0
			local maxPath = 0
			local mediaPath = 0
			for index, unit in pairs(unitTable[factory].unitsCanBuild) do
				local mtype = unitTable[unit].mtype
				local mclass = unitTable[unit].mclass
				if unitTable[unit].buildOptions or not factoryBuildsCons then
					local ok = true
					-- if self.hasUWSpots or not (mtype == 'amp' and mtypes[1] == 'veh') then
					if (self.hasUWSpots and mtype ~= 'veh') or (not self.hasUWSpots and mtype ~= 'amp') then
						count = count + 1
						factoryMtypeRating = factoryMtypeRating + mtypesMapRatings[mtype]
						self:EchoDebug(factory .. ' ' .. unit .. ' ' .. unitTable[unit].mtype .. ' ' .. mtypesMapRatings[unitTable[unit].mtype])
                        bestPath = math.max(bestPath,spotPathMobRank[mclass])
                        maxPath = math.max(maxPath,spotPathMobRank[mclass])
                        mediaPath = mediaPath + spotPathMobRank[mclass]
                        self:EchoDebug('bigdbg',factory .. ' ' .. unit .. ' ' .. unitTable[unit].mtype .. ' ' .. mtypesMapRatings[unitTable[unit].mtype],bestPath,maxPath,mediaPath,spotPathMobRank[mclass])
					end
				end
			end
			if count == 0 then 
				factoryMtypeRating = 0
			else
				factoryMtypeRating = factoryMtypeRating / count
			end
            if maxPath == 0 then
                mediaPath = 0
            else
                mediaPath = (mediaPath / count)
                factoryPathRating = (maxPath + mediaPath) / 2
            end
		else
            self:EchoDebug('airfactory',factory)
			factoryPathRating = 1
			if #landMetalSpots + #UWMetalSpots == 0 then
				factoryMtypeRating = mtypesMapRatings['air']
			elseif unitTable[factory].needsWater then
				factoryMtypeRating = mtypesMapRatings['air'] * (#UWMetalSpots / (#landMetalSpots + #UWMetalSpots))
			else
				factoryMtypeRating = mtypesMapRatings['air'] * (#landMetalSpots / (#landMetalSpots + #UWMetalSpots))
			end
		end
		self:EchoDebug(factory .. ' mtype rating: ' .. factoryMtypeRating)

		local Rating
        self:EchoDebug(factory .. ' path rating: ' .. factoryPathRating)
        Rating = factoryPathRating * factoryMtypeRating * unitTable[factory].techLevel
        self:EchoDebug('Rating',factoryPathRating, factoryMtypeRating , unitTable[factory].techLevel)
		if factoryMobilities[factory][1] == ('hov') then
			Rating = Rating * (self.mobCount['shp'] /mobilityGridArea)
		end
		if factory == 'armfhp' or factory == 'corfhp' then 
			Rating = Rating * 0.999 -- better a ground one, nanos around
		end 
		Rating = Rating * -1--reverse the value to get the right order
		
		if Rating ~= 0 then --useless add factory totally out of mode
			factoryRating[factory] = Rating
			self:EchoDebug('factory rating ' .. factory ..' = ' .. factoryRating[factory])
		end
		
		
	end
	
	local sorting = {}
	local rank = {}
	
	for name, rating in pairs(factoryRating) do

        self:EchoDebug('name,rating,rank[rating]',name,rating,rank[rating])
		if not rank[rating] then
			rank[rating] = {}
			table.insert(rank[rating],name)
		else
			table.insert(rank[rating],name)
		end
		table.insert(sorting, rating)
	end 
	table.sort(sorting)
	
	local factoriesRanking = {}
	local ranksByFactories = {}
	for i,v in pairs(sorting) do
		for ii = #rank[v], 1, -1 do
			local factoryName = table.remove(rank[v],ii)
			table.insert(factoriesRanking, factoryName)
			ranksByFactories[factoryName] = #factoriesRanking
			self:EchoDebug('i-factoryname',(i .. ' ' .. factoryName))
		end
	end
	return factoriesRanking, ranksByFactories
end

function MapHandler:SaveMapData()
	local mdfilename = MapDataFilename()
	self:EchoDebug("saving map data to " .. mdfilename)
	mapdatafile = io.open(mdfilename,'w')
	if mapdatafile ~= nil then
		EchoData("mobilityGridSize", mobilityGridSize)
		EchoData("mobilityGridMaxX", mobilityGridMaxX)
		EchoData("mobilityGridMaxZ", mobilityGridMaxZ)
		EchoData("self.waterMap", self.waterMap)
		EchoData("self.mapHasGeothermal", self.mapHasGeothermal)
		EchoData("mobilityRatingFloor", mobilityRatingFloor)
		EchoData("self.hasUWSpots", self.hasUWSpots)
		EchoData("mobilityGridSizeHalf", mobilityGridSizeHalf)
		EchoData("self.mobilityGridArea", self.mobilityGridArea)
		EchoData("self.mobRating", self.mobRating)
		EchoData("self.mobCount", self.mobCount)
		EchoData("self.mobNetworks", self.mobNetworks)
		EchoData("networkSize", networkSize)
		EchoData("landMetalSpots", landMetalSpots)
		EchoData("UWMetalSpots", UWMetalSpots)
		EchoData("geoSpots", geoSpots)
		EchoData("self.startLocations", self.startLocations)
		EchoData("self.mobNetworkMetals", self.mobNetworkMetals)
		EchoData("scoutSpots", scoutSpots)
		EchoData("topology", topology)
		mapdatafile:close()
	else
		self:EchoDebug("unable to write map data file " .. mdfilename)
	end
end

function MapHandler:LoadMapData()
	-- check for existing map data and load it
	local dataloaded = false
	local mdfilename = MapDataFilename()
	local mapdatafile = io.open(mdfilename ,"r")
	if mapdatafile ~= nil then
		mapdatafile:close()
		dofile(mdfilename)
		dataloaded = true
		self:EchoDebug("map data loaded from " .. mdfilename)
	end
	return dataloaded
end

function MapHandler:DebugDrawMobilities()
	if not DebugDrawEnabled then
		return
	end
	local size = mobilityGridSize
	local halfSize = mobilityGridSize / 2
	local squares = {}
	for mtype, xx in pairs(topology) do
		if mtype ~= 'air' then
			for x, zz in pairs(xx) do
				squares[x] = squares[x] or {}
				for z, network in pairs(zz) do
					squares[x][z] = squares[x][z] or {}
					squares[x][z][#squares[x][z]+1] = {network=network, mtype=mtype}
				end
			end
		end
	end
	for x, zz in pairs(squares) do
		x = x * size
		for z, square in pairs(zz) do
			z = z * size
			local colorA = {0, 0, 0}
			local colorB = {0, 0, 0}
			local channels = {}
			for i = 1, #square do
				local layer = square[i]
				-- Spring.Echo(layer.mtype)
				local channel = mapChannels[layer.mtype][1]
				channels[channel] = true
				if channel == 4 then
					colorA = AddColors(colorA, mapColors[layer.mtype])
				elseif channel == 5 then
					colorB = AddColors(colorB, mapColors[layer.mtype])
				end
			end
			local pos1 = api.Position()
			local pos2 = api.Position()
			pos1.x = x - size
			pos1.z = z - size
			pos2.x = x
			pos2.z = z
			-- Spring.Echo(x, z, colorA[1], colorA[2], colorA[3], colorA[4], channels[4])
			colorA[4], colorB[4] = 0.33, 0.33
			if channels[4] then
				self.map:DrawRectangle(pos1, pos2, colorA, nil, true, 4)
			end
			if channels[5] then
				self.map:DrawRectangle(pos1, pos2, colorB, nil, true, 5)
			end
		end
	end
end

function MapHandler:SimplifyMetalSpots(metalSpots, number)
	-- for maps that are all metal for example
	-- pretend for the sake of calculations that there are only 100 metal spots
	local mapSize = self.map:MapDimensions()
	local maxX = mapSize.x * 8
	local maxZ = mapSize.z * 8
	local divisor = math.ceil(math.sqrt(number))
	local gridSize = math.ceil( math.max(maxX, maxZ) / divisor )
	local halfGrid = math.ceil( gridSize / 2 )
	local spots = {}
	for x = 0, maxX-gridSize, gridSize do
		for z = 0, maxZ-gridSize, gridSize do
			for i = 1, #metalSpots do
				local spot = metalSpots[i]
				if spot.x > x and spot.x < x + gridSize and spot.z > z and spot.z < z + gridSize then
					spots[#spots+1] = spot
					table.remove(metalSpots, i)
					break
				end
			end
		end
	end
	return spots
end
 
function MapHandler:ClosestFreeSpot(unittype, builder, position)

	-- local kbytes, threshold = gcinfo()
	-- game:SendToConsole("maphandler gcinfo: " .. kbytes .. " (before ClosestFreeSpot)")

	if position == nil then position = builder:GetPosition() end
	local spots = {}
	local bname = builder:Name()
	if commanderList[bname] then
		-- give the commander both hov and bot spots
		local pos = builder:GetPosition()
		local network = self:MobilityNetworkHere("bot", pos)
		if network ~= nil then
			-- self:EchoDebug("found bot metal spot network for commander")
			spots = self.mobNetworkMetals["bot"][network]
		end
		network = self:MobilityNetworkHere("hov", pos)
		if network ~= nil then
			-- self:EchoDebug("found hover metal spot network for commander")
			if #spots == 0 then
				spots = self.mobNetworkMetals["hov"][network]
			else
				for i, p in pairs(self.mobNetworkMetals["hov"][network]) do
					table.insert(spots, p)
				end
			end
		end
		-- give the commander all metal spots if shp or bot doesn't work out
		if #spots == 0 then spots = self.mobNetworkMetals["air"][1] end
	else
		local mtype, network = self:MobilityOfUnit(builder)
		if self.mobNetworkMetals[mtype][network] ~= nil then
			spots = self.mobNetworkMetals[mtype][network]
		end
	end
	if spots == nil then 
		self:EchoDebug(builder:Name() .. " has nil spots")
		return end
	if #spots == 0 then
		self:EchoDebug(builder:Name() .. " has zero spots")
		return
	end
	local uname = unittype:Name()
	local pos = nil
	local reclaimEnemyMex = false
	local bestDistance = 10000
 	-- check for armed enemy units nearby
	local uw = nil
	local uwutype = nil
	if self.hasUWSpots then
		-- underwater mex check
		-- self:EchoDebug("map has uw spots")
		local coruwtype
		local armuwtype
		if uname == "cormex" or uname == "armmex" then
			coruwtype = self.game:GetTypeByName("coruwmex")
			armuwtype = self.game:GetTypeByName("armuwmex")
		elseif uname == "cormoho" or uname == "armoho" then
			coruwtype = self.game:GetTypeByName("coruwmme")
			armuwtype = self.game:GetTypeByName("armuwmme")
		end
		if coruwtype ~= nil then
			if builder:CanBuild(coruwtype) then
				uwutype = coruwtype
			elseif builder:CanBuild(armuwtype) then
				uwutype = armuwtype
			end
		end
		-- if uwutype ~= nil then self:EchoDebug("builder can build uw mexes") end
	end
	local f = game:Frame()
	for i,p in pairs(spots) do
		-- dont use this spot if we're already building there
		local alreadyPlanned = self.buildsitehandler:PlansOverlap(p, uname)
		if not alreadyPlanned then
			local dist = Distance(position, p)
			-- don't add if it's already too high
			if dist < bestDistance then
				-- now check if we can build there
				local uwcheck
				if uwutype ~= nil then
					 uwcheck = self.map:CanBuildHere(uwutype, p)
					 -- self:EchoDebug("builder can build uw mex here? " .. tostring(uwcheck))
				end
				if self.map:CanBuildHere(unittype, p) or uwcheck then
					-- self:EchoDebug("can build mex at" .. p.x .. " " .. p.z)
					-- game:SendToConsole("before builder gets safe position", self.self.id, self.id, builder:Team())
					if self.targethandler:IsSafePosition(p, builder) then
						bestDistance = dist
						pos = p
						reclaimEnemyMex = false
						if uwcheck then
							-- self:EchoDebug("uw mex is best distance")
							uw = uwutype
						else
							uw = nil
						end
					end
				elseif self.targethandler:IsSafePosition(p, builder, 200) then
					-- is it an enemy mex that's blocking a safe position (or an unknown radar blip)?
					for i, enemySpot in pairs(self.enemyMexSpots) do
						local epos = enemySpot.position
						if p.x > epos.x - 100 and p.x < epos.x + 100 and p.z > epos.z - 100 and p.z < epos.z + 100 then
							bestDistance = dist
							pos = epos
							reclaimEnemyMex = enemySpot.unit
							if uwcheck then
								-- self:EchoDebug("uw mex is best distance")
								uw = uwutype
							else
								uw = nil
							end
							break
						end
					end
				end
			end
		end
	end
	
	-- local kbytes, threshold = gcinfo()
	-- game:SendToConsole("maphandler gcinfo: " .. kbytes .. " (after ClosestFreeSpot)")

	-- if uw then self:EchoDebug("uw mex is final best distance") end
	return pos, uw, reclaimEnemyMex
end

function MapHandler:ClosestFreeGeo(unittype, builder, position)
	self:EchoDebug("closestfreegeo for " .. unittype:Name() .. " by " .. builder:Name())
	if not position then position = builder:GetPosition() end
	local bname = builder:Name()
	local uname = unittype:Name()
	local bestDistance, bestPos
	for i,p in pairs(geoSpots) do
		-- dont use this spot if we're already building there
		if not self.buildsitehandler:PlansOverlap(p, uname) and self:UnitCanGoHere(builder, p) and self.map:CanBuildHere(unittype, p) and self.targethandler:IsSafePosition(p, builder) then
			local dist = Distance(position, p)
			if not bestDistance or dist < bestDistance then
				bestDistance = dist
				bestPos = p
			end
		end
	end
	return bestPos
end

function MapHandler:MobilityNetworkHere(mtype, position)
	if mtype == "air" then return 1 end
	local x = math.ceil(position.x / mobilityGridSize)
	local z = math.ceil(position.z / mobilityGridSize)
	local network
	if topology[mtype][x] ~= nil then
		network = topology[mtype][x][z]
	end
	return network
end

function MapHandler:MobilityOfUnit(unit)
	local position = unit:GetPosition()
	local name = unit:Name()
	local mtype = unitTable[name].mtype
	if self.activeMobTypes[mtype] == nil then self.activeMobTypes[mtype] = true end
	return mtype, self:MobilityNetworkHere(mtype, position)
end

function MapHandler:UnitCanGoHere(unit, position)
	if unit == nil then return false end
	if position == nil then return false end
	local mtype, unet = self:MobilityOfUnit(unit)
	if mtype == 'air' then return true end
    -- check if it's even a valid move order
    local moveOrderTest = Spring.TestMoveOrder(unit:Type():ID(), position.x, position.y, position.z, nil, nil, nil, true, false)
    if not moveOrderTest then
        return false
    end
	local pnet = self:MobilityNetworkHere(mtype, position)
	if unet == pnet then
		return true
	else
		-- self:EchoDebug(mtype .. " " .. tostring(unet) .. " " .. tostring(pnet))
		return false
	end
end

function MapHandler:UnitCanGetToUnit(unit1, unit2)
	local position = unit2:GetPosition()
	return self:UnitCanGoHere(unit1, position)
end

function MapHandler:UnitCanHurtVictim(unit, victim)
	if unit:WeaponCount() == 0 then return false end
	local vname = victim:Name()
	local mtype = unitTable[vname].mtype
	local name = unit:Name()
	local canhurt = false
	if unitTable[name].groundRange > 0 and mtype == "veh" or mtype == "bot" or mtype == "amp" or mtype == "hov" then
		canhurt = "ground"
	elseif unitTable[name].airRange > 0 and mtype == "air" then
		canhurt = "air"
	elseif unitTable[name].submergedRange > 0 and mtype == "shp" or mtype == "sub" or mtype == "amp" then
		canhurt = "submerged"
	end
	return canhurt
end

function MapHandler:MobilityNetworkSizeHere(mtype, position)
	if mtype == "air" then return mobilityGridArea end
	local x = math.ceil(position.x / mobilityGridSize)
	local z = math.ceil(position.z / mobilityGridSize)
	if topology[mtype][x] == nil then
		return 0
	elseif topology[mtype][x][z] == nil then
		return 0
	else
		local network = topology[mtype][x][z]
		return networkSize[mtype][network]
	end
end

function MapHandler:AccessibleMetalSpotsHere(mtype, position)
	local network = self:MobilityNetworkHere(mtype, position)
	return mobNetworkMetals[mtype][network] or {}
end

function MapHandler:AccessibleGeoSpotsHere(mtype, position)
	local network = self:MobilityNetworkHere(mtype, position)
	return mobNetworkGeos[mtype][network] or {}
end

function MapHandler:AccessibleMetalGeoSpotsHere(mtype, position)
	local network = self:MobilityNetworkHere(mtype, position)
	return scoutSpots[mtype][network] or {}
end

function MapHandler:IsUnderWater(position)
	return Spring.GetGroundHeight(position.x, position.z) < 0
end

function MapHandler:OutmodedFactoryHere(mtype, position, network)
	if mtype == "air" then return false end
	if position and network == nil then
		network = self:MobilityNetworkHere(mtype, position)
	end
	if network == nil then
		return false
	else
		if networkSize[mtype][network] < self.mobCount[mtype] * 0.67 and self.mobNetworks[mtype] > 1 then
	 		return true
		else
			return false
		end
	end
end

function MapHandler:CheckDefenseLocalization(unitName, position)
	local size = 0
	if unitTable[unitName].groundRange > 0 then
		local vehsize = self:MobilityNetworkSizeHere("veh", position)
		local botsize = self:MobilityNetworkSizeHere("bot", position)
		size = math.max(vehsize, botsize)
	elseif unitTable[unitName].airRange > 0 then
		return true
	elseif  unitTable[unitName].submergedRange > 0 then
		size = self:MobilityNetworkSizeHere("sub", position)
	else
		return true
	end
	local minimumSize = mobilityGridArea / 4
	self:EchoDebug("network size here: " .. size .. ", minimum: " .. minimumSize)
	if size < minimumSize then
		return false
	else
		return true
	end
end

function MapHandler:GetPathGraph(mtype, targetNodeSize)
	targetNodeSize = targetNodeSize or 256
	local cellsPerNodeSide = mCeil(targetNodeSize / mobilityGridSize)
	if pathGraphs[mtype] then
		if pathGraphs[mtype][cellsPerNodeSide] then
			return pathGraphs[mtype][cellsPerNodeSide]
		end
	end
	local nodeSize = cellsPerNodeSide * mobilityGridSize
	local nodeSizeHalf = nodeSize / 2
	local graph = {}
	local id = 1
	local myTopology = topology[mtype]
	for cx = 1, mobilityGridMaxX, cellsPerNodeSide do
		local x = ((cx * mobilityGridSize) - mobilityGridSizeHalf) + nodeSizeHalf
		for cz = 1, mobilityGridMaxZ, cellsPerNodeSide do
			local cellsComplete = true
			local goodCells = {}
			for ccx = cx, cx+cellsPerNodeSide-1 do
				for ccz = cz, cz+cellsPerNodeSide-1 do
					if myTopology[ccx] and myTopology[ccx][ccz] then
						goodCells[#goodCells+1] = {ccx, ccz}
					else
						cellsComplete = false
					end
				end
			end
			if #goodCells > 0 then
				local z = ((cz * mobilityGridSize) - mobilityGridSizeHalf) + nodeSizeHalf
				local position = api.Position()
				position.x = x
				position.z = z
				position.y = 0
				if not cellsComplete then
					local bestDist, bestX, bestZ
					for i = 1, #goodCells do
						local good = goodCells[i]
						local gx = (good[1] * mobilityGridSize) - mobilityGridSizeHalf
						local gz = (good[2] * mobilityGridSize) - mobilityGridSizeHalf
						local dx = x - gx
						local dz = z - gz
						local dist = dx*dx + dz*dz
						if not bestDist or dist < bestDist then
							bestDist = dist
							bestX = gx
							bestZ = gz
						end
					end
					position.x = bestX
					position.z = bestZ
				end
				
				position.y = Spring.GetGroundHeight(x, z)
				local nodeX = mCeil(cx / cellsPerNodeSide)
				local nodeY = mCeil(cz / cellsPerNodeSide)
				local node = { x = nodeX, y = nodeY, id = id, position = position }
				-- self.map:DrawPoint(position, {1,1,1,1}, mtype .. " " .. nodeX .. ", " .. nodeY, 8)
				graph[id] = node
				id = id + 1
			end
		end
	end
	local aGraph = GraphAStar()
	aGraph:Init(graph)
	aGraph:SetOctoGridSize(1)
	aGraph:SetPositionUnitsPerNodeUnits(nodeSize)
	pathGraphs[mtype] = pathGraphs[mtype] or {}
	pathGraphs[mtype][cellsPerNodeSide] = aGraph
	return aGraph
end
