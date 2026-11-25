LosHST = class(Module) ---track the enemy units in los and radar and insert them in the right cell of ENEMY

function LosHST:Name()
	return "LosHST"
end

function LosHST:internalName()
	return "loshst"
end

function LosHST:Scope()
	return "team"
end

function LosHST:Init()
	self.DebugEnabled = false
	self.losEnemy = {}
	self.radarEnemy = {}
	self.ghostEnemy = {} --mobile units seen in los and still on radar since: their type is known
	self.ENEMY = self.ai.gridhst:NewLayer(self.resetCell) --the cells with enemies in this round
	self.ai.friendlyTeamID = {}
end

function LosHST:Update()
	self.ENEMY:Clear()

	for id, def in pairs(self.losEnemy) do
		local unit = game:GetUnitByID(id)
		local x, y, z = unit:GetRawPos()
		if self:countSets(id) > 1 then
			self:Warn("unit in more than one of los, radar and ghost, with losStatus:", game:GetUnitLos(id))
		elseif not x or not unit:IsAlive() then
			self:cleanEnemy(id)
		else
			local X, Z = self.ai.gridhst:RawPosToGrid(x, y, z)
			self:setCellLos(unit, X, Z)
		end
	end
	for id, def in pairs(self.radarEnemy) do
		local unit = game:GetUnitByID(id)
		local x, y, z = unit:GetRawPos()
		--self:EchoDebug('enemyunitx',x,unit.x,unit.y,unit.z)

		if self:countSets(id) > 1 then
			self:Warn("unit in more than one of los, radar and ghost, with losStatus:", game:GetUnitLos(id))
		elseif not x or not unit:IsAlive() then
			self:cleanEnemy(id)
		else
			local X, Z = self.ai.gridhst:RawPosToGrid(x, y, z)
			self:setCellRadar(unit, X, Z)
		end
	end
	for id, def in pairs(self.ghostEnemy) do
		local unit = game:GetUnitByID(id)
		local x, y, z = unit:GetRawPos() --the radar position, as for radarEnemy
		if self:countSets(id) > 1 then
			self:Warn("unit in more than one of los, radar and ghost, with losStatus:", game:GetUnitLos(id))
		elseif not x or not unit:IsAlive() then
			self:cleanEnemy(id)
		else
			local X, Z = self.ai.gridhst:RawPosToGrid(x, y, z)
			self:setCellLos(unit, X, Z) --the type is known, so it counts as a unit in los
		end
	end
end

function LosHST:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
	if allyTeam ~= self.ai.allyId then
		return
	end
	self:EchoDebug("ENTER LOS", unitID, unitTeam, allyTeam, unitDefID, UnitDefs[unitDefID].name)
	self.losEnemy[unitID] = unitDefID
	self.radarEnemy[unitID] = nil
	self.ghostEnemy[unitID] = nil
end

function LosHST:UnitLeftLos(unitID, unitTeam, allyTeam, unitDefID)
	if allyTeam ~= self.ai.allyId then
		return
	end
	local speed = UnitDefs[unitDefID].speed
	if speed == 0 then
		self.losEnemy[unitID] = unitDefID
		self.radarEnemy[unitID] = nil
	elseif self.ai.perceptionhandler:OnRadar(unitID) then --the radar never stopped: the player still sees its type
		self.losEnemy[unitID] = nil
		self.ghostEnemy[unitID] = unitDefID
	else
		self.losEnemy[unitID] = nil
	end
	self:EchoDebug("LEFT LOS", unitID, unitTeam, allyTeam, unitDefID)
end

function LosHST:UnitEnteredRadar(unitID, unitTeam, allyTeam, unitDefID)
	if allyTeam ~= self.ai.allyId then
		return
	end
	if not self.losEnemy[unitID] then
		self.radarEnemy[unitID] = unitDefID
	end
	self:EchoDebug("ENTER RADAR", unitID, unitTeam, allyTeam, unitDefID)
end

function LosHST:UnitLeftRadar(unitID, unitTeam, allyTeam, unitDefID)
	if allyTeam ~= self.ai.allyId then
		return
	end
	self.radarEnemy[unitID] = nil
	self.ghostEnemy[unitID] = nil
	self:EchoDebug("LEFT RADAR", unitID, unitTeam, allyTeam, unitDefID)
end

function LosHST:UnitDead(unit) --this is a bit cheat, we always know if a unit died but is not computability to track allways all dead unit and try it everytime
	self:cleanEnemy(unit:ID())
end

function LosHST:cleanEnemy(id)
	self:EchoDebug("unit dead removed from los and radar", id)
	self.losEnemy[id] = nil
	self.radarEnemy[id] = nil
	self.ghostEnemy[id] = nil
end

function LosHST:countSets(id) --in how many of losEnemy, radarEnemy, ghostEnemy is the unit: one at a time
	local count = 0
	if self.losEnemy[id] then
		count = count + 1
	end
	if self.radarEnemy[id] then
		count = count + 1
	end
	if self.ghostEnemy[id] then
		count = count + 1
	end
	return count
end

function LosHST:setPosLayer2(unitName, x, y, z)
	local ut = self.ai.armyhst.unitTable[unitName]
	local floating = false
	if ut.mtype == "air" then
		self.ai.needAntiAir = true --TODO need to move from here
		return 1
	end
	if (ut.mtype == "sub" or ut.mtype == "amp") and y < -5 then
		return -1
	end
	if Spring.GetGroundHeight(x, z) < 0 then --TEST  WARNING
		floating = true
	end
	return 0, floating
end

function LosHST:getEnemyCell(X, Z) --the cell X, Z of ENEMY, marked as true for this round
	local i = self.ai.gridhst:GridToIndex(X, Z)
	local CELL = self.ENEMY:Get(i)
	if not CELL.POS then --a new cell: its place on the grid, written once
		CELL.X = X
		CELL.Z = Z
		CELL.POS = self.ai.gridhst.CELLS[i].POS
	end
	self.ENEMY:Mark(i)
	return CELL
end

function LosHST.resetCell(CELL) --clear an ENEMY cell, its tables are kept. GAS are 3 layer. Unit of measure is usually metal cost!
	--I = immoble
	-- M = mobile
	--G = ground
	--A = air
	--S = submerged
	CELL.metal = 0
	if CELL.units then
		local units = CELL.units
		for k, v in pairs(units) do
			units[k] = nil
		end
	else
		CELL.units = {} --hold all the units
	end
	if CELL.buildings then
		local buildings = CELL.buildings
		for k, v in pairs(buildings) do
			buildings[k] = nil
		end
	else
		CELL.buildings = {} --hold all the buildings
	end
	CELL.metalMedia = 0
	CELL.unitsCount = 0
	CELL.base = nil --the name of the last factory seen in this round

	--unarm GAS immobiles
	CELL.unarmGI = 0
	CELL.unarmAI = 0
	CELL.unarmSI = 0
	CELL.unarmI = 0
	--unarm GAS mobile
	CELL.unarmGM = 0
	CELL.unarmAM = 0
	CELL.unarmSM = 0
	CELL.unarmM = 0
	--armed GAS mobile
	CELL.armedGM = 0
	CELL.armedAM = 0
	CELL.armedSM = 0
	CELL.armedM = 0
	--armed GAS immobile
	CELL.armedGI = 0
	CELL.armedAI = 0
	CELL.armedSI = 0
	CELL.armedI = 0
	--  unarm GAS sum
	CELL.unarmG = 0
	CELL.unarmA = 0
	CELL.unarmS = 0
	--armed GAS sum
	CELL.armedG = 0
	CELL.armedA = 0
	CELL.armedS = 0
	--GAS SUM
	CELL.G = 0
	CELL.A = 0
	CELL.S = 0
	-- GAS balanced unarm - armed
	CELL.G_balance = 0
	CELL.S_balance = 0
	CELL.A_balance = 0
	--totals unarmed armed
	CELL.UNARM = 0 -- total amount of armed units in metal
	CELL.ARMED = 0 -- total amount of unarmed int in metal
	CELL.SOLDIERS = 0 --armed mobile units in Metal
	CELL.TURRETS = 0 --armed immobile units in Metal
	CELL.BUILDINGS = 0 --immobile unarmed units in metal value
	CELL.WORKERS = 0 -- mobile unarmed value in metal
	CELL.MOBILE = 0 -- total amount of mobile units in metal
	CELL.IMMOBILE = 0 --total amount of immobile units in metal
	CELL.IM_balance = 0 -- mobile - immobile in metal
	CELL.ENEMY = 0 --total amount of metal in cell
	CELL.ENEMY_BALANCE = 0 -- this is balanced SOLDIERS - TURRETS
	CELL.SPEED = 0
end

function LosHST:setCellRadar(unit, X, Z)
	if not self.ai.gridhst:IsCellInGrid(X, Z) then
		return
	end
	local CELL = self:getEnemyCell(X, Z)

	if CELL.metalMedia == 0 then
		CELL.metalMedia = 30 + game:Frame() / 90
	end
	CELL.metal = CELL.metal + CELL.metalMedia
	local M = CELL.metalMedia
	local speedX, speedY, speedZ, SPEED = Spring.GetUnitVelocity(unit:ID())
	CELL.SPEED = CELL.SPEED + SPEED
	CELL.units[unit:ID()] = unit:Name()
	CELL.unitsCount = CELL.unitsCount + 1
	CELL.ARMED = CELL.ARMED + M
	if SPEED > 0 then
		CELL.SOLDIERS = CELL.SOLDIERS + M
		CELL.MOBILE = CELL.MOBILE + M
		CELL.armedGM = CELL.armedGM + M
		CELL.armedAM = CELL.armedAM + M
		CELL.armedSM = CELL.armedSM + M
	else
		CELL.TURRETS = CELL.TURRETS + M
		CELL.IMMOBILE = CELL.IMMOBILE + M
		CELL.armedGI = CELL.armedGI + M
		CELL.armedAI = CELL.armedAI + M
		CELL.armedSI = CELL.armedSI + M
	end
	CELL.UNARM = CELL.UNARM + M
	if SPEED > 0 then
		CELL.WORKERS = CELL.WORKERS + M
		CELL.MOBILE = CELL.MOBILE + M
		CELL.unarmAM = CELL.unarmAM + M
		CELL.unarmSM = CELL.unarmSM + M
		CELL.unarmGM = CELL.unarmGM + M
	else
		CELL.BUILDINGS = CELL.BUILDINGS + M
		CELL.IMMOBILE = CELL.IMMOBILE + M
		CELL.unarmAI = CELL.unarmAI + M
		CELL.unarmSI = CELL.unarmSI + M
		CELL.unarmGI = CELL.unarmGI + M
	end
	CELL.unarmG = CELL.unarmGM + CELL.unarmGI
	CELL.unarmA = CELL.unarmAM + CELL.unarmAI
	CELL.unarmS = CELL.unarmSM + CELL.unarmSI
	CELL.armedG = CELL.armedGI + CELL.armedGM
	CELL.armedA = CELL.armedAI + CELL.armedAM
	CELL.armedS = CELL.armedSI + CELL.armedSM
	CELL.G = CELL.armedG + CELL.unarmG
	CELL.A = CELL.armedA + CELL.unarmA
	CELL.S = CELL.armedS + CELL.unarmS
	CELL.G_balance = CELL.armedG - CELL.unarmG
	CELL.A_balance = CELL.armedA - CELL.unarmA
	CELL.S_balance = CELL.armedS - CELL.unarmS
	CELL.ENEMY = CELL.ARMED + CELL.UNARM --TOTAL VALUE
	CELL.ENEMY_BALANCE = CELL.ARMED - CELL.UNARM
	CELL.IM_balance = CELL.MOBILE - CELL.IMMOBILE

end

function LosHST:setCellLos(unit, X, Z)
	if not self.ai.gridhst:IsCellInGrid(X, Z) then
		return
	end
	local CELL = self:getEnemyCell(X, Z)
	CELL.unitsCount = CELL.unitsCount + 1
	CELL.units[unit:ID()] = unit:Name()
	local name = unit:Name()
	local x, y, z = unit:GetRawPos()
	local ut = self.ai.armyhst.unitTable[name]
	local M = ut.metalCost
	local mobile = ut.speed > 0
	local layer = self:setPosLayer2(ut.name, x, y, z)
	local speedX, speedY, speedZ, SPEED = Spring.GetUnitVelocity(unit:ID())
	CELL.SPEED = CELL.SPEED + SPEED
	CELL.metal = CELL.metal + M
	if CELL.unitsCount > 0 then
		CELL.metalMedia = CELL.metal / CELL.unitsCount
	end
	if not mobile then
		CELL.buildings[unit.id] = unit.name

	end
	if ut.isFactory then
		CELL.base = unit.name
	end
	if ut.isWeapon then
		CELL.ARMED = CELL.ARMED + M
		if mobile then
			CELL.SOLDIERS = CELL.SOLDIERS + M
			CELL.MOBILE = CELL.MOBILE + M
			if layer == 0 then
				CELL.armedGM = CELL.armedGM + M
			elseif layer == 1 then
				CELL.armedAM = CELL.armedAM + M
			elseif layer == -1 then
				CELL.armedSM = CELL.armedSM + M
			end
		else
			CELL.TURRETS = CELL.TURRETS + M
			CELL.IMMOBILE = CELL.IMMOBILE + M
			if layer == 0 then
				CELL.armedGI = CELL.armedGI + M
			elseif layer == 1 then
				CELL.armedAI = CELL.armedAI + M
			elseif layer == -1 then
				CELL.armedSI = CELL.armedSI + M
			end
		end

	else
		CELL.UNARM = CELL.UNARM + M
		if mobile then
			CELL.WORKERS = CELL.WORKERS + M
			CELL.MOBILE = CELL.MOBILE + M
			if layer > 0 then
				CELL.unarmAM = CELL.unarmAM + M
			elseif layer < 0 then
				CELL.unarmSM = CELL.unarmSM + M
			elseif layer == 0 then
				CELL.unarmGM = CELL.unarmGM + M
			end
		else
			CELL.BUILDINGS = CELL.BUILDINGS + M
			CELL.IMMOBILE = CELL.IMMOBILE + M
			if layer > 0 then
				CELL.unarmAI = CELL.unarmAI + M
			elseif layer < 0 then
				CELL.unarmSI = CELL.unarmSI + M
			elseif layer == 0 then
				CELL.unarmGI = CELL.unarmGI + M
			end
		end
	end

	CELL.unarmG = CELL.unarmGM + CELL.unarmGI
	CELL.unarmA = CELL.unarmAM + CELL.unarmAI
	CELL.unarmS = CELL.unarmSM + CELL.unarmSI
	CELL.armedG = CELL.armedGI + CELL.armedGM
	CELL.armedA = CELL.armedAI + CELL.armedAM
	CELL.armedS = CELL.armedSI + CELL.armedSM
	CELL.G = CELL.armedG + CELL.unarmG
	CELL.A = CELL.armedA + CELL.unarmA
	CELL.S = CELL.armedS + CELL.unarmS
	CELL.G_balance = CELL.armedG - CELL.unarmG
	CELL.A_balance = CELL.armedA - CELL.unarmA
	CELL.S_balance = CELL.armedS - CELL.unarmS
	CELL.ENEMY = CELL.ARMED + CELL.UNARM --TOTAL VALUE
	CELL.ENEMY_BALANCE = CELL.ARMED - CELL.UNARM
	CELL.IM_balance = CELL.MOBILE - CELL.IMMOBILE
end

function LosHST:Draw()
	if not self.ai.drawDebug then
		return
	end
	local ch = 5
	self.map:EraseAll(ch)
	for id, def in pairs(self.losEnemy) do
		local u = self.game:GetUnitByID(id)
		u:DrawHighlight({ 1, 0, 0, 1 }, nil, ch)
	end
	for id, def in pairs(self.radarEnemy) do
		local u = self.game:GetUnitByID(id)
		u:DrawHighlight({ 0, 1, 0, 1 }, nil, ch)
	end
	for id, def in pairs(self.ghostEnemy) do
		local u = self.game:GetUnitByID(id)
		u:DrawHighlight({ 1, 1, 0, 1 }, nil, ch)
	end

	local colours = {
		g = { 1, 0, 0, 1 }, --'red'
		a = { 0, 1, 0, 1 }, --'green'
		s = { 0, 0, 1, 1 }, --'blue'
		p = { 0, 1, 1, 1 },
		f = { 1, 1, 0, 1 },
		unbalance = { 1, 1, 1, 1 },
		balance = { 0, 0, 0, 1 },

	}
	if self.enemyBasePosition then
		map:DrawPoint(self.enemyBasePosition, { 1, 1, 1, 1 }, "BASE", ch)
	end
	local cellElmosHalf = self.ai.gridhst.gridSizeHalf ---@type number
	for n = 1, #self.ENEMY.LIST do --numeric loop keeps the order of the cells
		local cell = self.ENEMY.CELLS[self.ENEMY.LIST[n]]
		local p = cell.POS
		--map:DrawCircle(p,cellElmosHalf, colours.balance, cell.ENEMY,false,  4)
		local pos1, pos2 = api.Position(), api.Position() --z,api.Position(),api.Position(),api.Position()
		pos1.x, pos1.z = p.x - cellElmosHalf, p.z - cellElmosHalf
		pos2.x, pos2.z = p.x + cellElmosHalf, p.z + cellElmosHalf
		pos1.y = Spring.GetGroundHeight(pos1.x, pos1.z)
		pos2.y = Spring.GetGroundHeight(pos2.x, pos2.z)
		self:EchoDebug("drawing", pos1.x, pos1.z, pos2.x, pos2.z)
		if cell.ENEMY_BALANCE > 0 then
			map:DrawRectangle(pos1, pos2, colours.balance, cell.ENEMY_BALANCE, false, ch)
		else
			map:DrawRectangle(pos1, pos2, colours.unbalance, cell.ENEMY_BALANCE, false, ch)
		end
		local posG = { x = p.x - cellElmosHalf / 2, y = p.y, z = p.z - cellElmosHalf / 2 }
		local posS = { x = p.x + cellElmosHalf / 2, y = p.y, z = p.z - cellElmosHalf / 2 }
		local posB = { x = p.x - cellElmosHalf / 2, y = p.y, z = p.z + cellElmosHalf / 2 }
		local posA = { x = p.x + cellElmosHalf / 2, y = p.y, z = p.z + cellElmosHalf / 2 }

		if cell.G > 0 then
			map:DrawCircle(posG, cellElmosHalf / 2, colours.g, cell.G, true, ch)
		end
		if cell.A > 0 then
			map:DrawCircle(posA, cellElmosHalf / 2, colours.a, cell.A, true, ch)
		end
		if cell.S > 0 then
			map:DrawCircle(posS, cellElmosHalf / 2, colours.s, cell.S, true, ch)
		end
	end
end

--[[ suggested of beherith
LOS
15 1111 have the los so other info are useless LOS
14 1110
13 1101
12 1100
11 1011
10 1010
9  1001
8  1000 last of LOS
RADAR
7 0111 in radar, already seen and have continous coverage so keep the ID last IDDD
6 0110 in R already in L but intermittent so pure RADAR
5 0101 in radar, and in continous coverage after los, but never in los so IMPOSSIBLE
4 0100 in PURE radar, never in los

3 0011 just already seen but not in R or L tecnically IMPOSSIBLE
2 0010  just already seen but not in R or L usable for a building that we know its already there and mobile that is there but where?

1 0001 not in radar not in los but continous.... IMPOSSIBLE
]]
--

--[[ 1los 2 prev los 3 in rad 4 continous rad maybe this is correct
LOS
15 1111 have the los so other info are useless LOS
14 1110
13 1101
12 1100
11 1011
10 1010
9  1001
8  1000 last of LOS first time i see it

7 0111 see one time, in radar with continous radar coverage LOS

RADAR
6 0110 see one time, in radar but intermittent so if mobile then RADAR, if building then LOS
5 0101 see one time, no in radar but have continous radar?? IMPOSSIBLE
4 0100 see on time, now HIDDEN but if is a building then LOS

3 0011 never seen ,in radar, with continous coverage ?? IMPOSSIBLE
2 0010 just in radar, never seen in los RADAR PURE

1 0001 not in radar not in los but continous.... IMPOSSIBLE
]]
--

--[[int LuaSyncedRead::GetUnitLosState(lua_State* L)
{
    const CUnit* unit = ParseUnit(L, __func__, 1);
    if (unit == nullptr)
        return 0;

    const int allyTeamID = GetEffectiveLosAllyTeam(L, 2);
    unsigned short losStatus;
    if (allyTeamID < 0) {
        losStatus = (allyTeamID == CEventClient::AllAccessTeam) ? (LOS_ALL_MASK_BITS | LOS_ALL_BITS) : 0;
    } else {
        losStatus = unit->losStatus[allyTeamID];
    }

    constexpr int currMask = LOS_INLOS   | LOS_INRADAR;
    constexpr int prevMask = LOS_PREVLOS | LOS_CONTRADAR;

    const bool isTyped = ((losStatus & prevMask) == prevMask);

    if (luaL_optboolean(L, 3, false)) {
        // return a numeric value
        if (!CLuaHandle::GetHandleFullRead(L))
            losStatus &= ((prevMask * isTyped) | currMask);

        lua_pushnumber(L, losStatus);
        return 1;
    }

    lua_createtable(L, 0, 3);
    if (losStatus & LOS_INLOS) {
        HSTR_PUSH_BOOL(L, "los", true);
    }
    if (losStatus & LOS_INRADAR) {
        HSTR_PUSH_BOOL(L, "radar", true);
    }
    if ((losStatus & LOS_INLOS) || isTyped) {
        HSTR_PUSH_BOOL(L, "typed", true);
    }
    return 1;
}
ugh this is nasty
ok raw means it returns number instead of table
so the numeric integer of the mask bits
and I dont think you can get wether a unit is seen in airlos or regular los
its either seen or not
raw is generally preferred, as is much faster in than creating a table
isnt 'typed' meaning that its a radar dot that has been revealed or not?
I definately think so
so if you use raw = true
then result = 15 ( 1 1 1 1 ) means in radar, in los, known unittype
also, if result is > 2, that means that the unitDefID is known
cause the unitDefID of a unit is 'forgotten' if the unit leaves radar
so the key info here is these 4 bits:
I think the bits might be:
bit 0 : LOS_INLOS, unit is in LOS right now,
bit 1 : LOS_INRADAR unit is in radar right now,
bit 2: LOS_PREVLOS unit was in los at least once already, so the unitDefID can be queried
bit 3: LOS_CONTRADAR: unit has had continous radar coverage since it was spotted in LOS]]
--

--[[
contr,prevlos, rad,los
0 	0000	NIL
1 	0001	L
2 	0010	R
3 	0011	L
4 	0100	HIDDEN
5 	0101	L
6 	0110	R
7 	0111	L
8 	1000	IMPOSSIBLE
9 	1001	L
10 	1010	IMPOSSIBLE
11	1011	L
12	1100	was in los and not in radar but have contradar ??? strange
13	1101	L
14	1110	L in radar, already seen and have continous coverage so keep the ID last IDDD IN LOS
15	1111	L
]]
