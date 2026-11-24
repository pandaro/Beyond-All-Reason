ShardAI = class(AIBase)

local lastGCinfo = 0
local logRAM = false
local function tracyZoneBeginMem()
	return
end
local function tracyZoneEndMem()
	return
end

if tracy then
	Spring.Echo("Enabled Tracy support for STAI")
	tracyZoneBeginMem = function(fname)
		if logRAM then
			lastGCinfo = gcinfo()
		end
		tracy.ZoneBeginN(fname)
	end

	tracyZoneEndMem = function(fname)
		fname = fname or "STAI"
		if logRAM then
			local nowGCinfo = gcinfo()
			local delta = nowGCinfo - lastGCinfo
			if delta > 0 then
				tracy.Message(tostring(fname .. nowGCinfo - lastGCinfo))
			end
			lastGCinfo = nowGCinfo
		end
		tracy.ZoneEnd()
	end
end

function ShardAI:Name()
	return "Shard"
end

function ShardAI:internalName()
	return "shard"
end

function ShardAI:Scope()
	return "team"
end

-- The events a module can hear, and the events of AIBase that call others: a module that redefines one of those
-- wants the event too (AIBase:UnitBuilt sorts a unit into MyUnitBuilt and the like, AIBase:UnitGiven calls
-- UnitCreated and UnitBuilt).
local EVENTS = {
	"Update",
	"GameMessage",
	"UnitCreated",
	"UnitBuilt",
	"UnitGiven",
	"UnitDead",
	"UnitIdle",
	"UnitDamaged",
	"UnitEnteredLos",
	"UnitLeftLos",
	"UnitEnteredRadar",
	"UnitLeftRadar",
	"UnitMoveFailed",
	"GameEnd",
}
local EVENTS_CALLED = {
	UnitBuilt = { "MyUnitBuilt", "FriendlyUnitBuilt", "EnemyUnitBuilt", "NeutralUnitBuilt" },
	UnitGiven = { "UnitCreated", "UnitBuilt" },
}

-- whether the module redefines the event, or one the event calls; read on the instance, so that a method set in
-- Init counts too
local function WantsEvent(module, event)
	if module[event] ~= AIBase[event] then
		return true
	end
	local called = EVENTS_CALLED[event]
	if called ~= nil then
		for i = 1, #called do
			if WantsEvent(module, called[i]) then
				return true
			end
		end
	end
	return false
end

---@type table<string, integer>
local SCOPE_RANKS = { team = 1, ally = 2, global = 3 }

-- Module classes already warned about for their Scope(), so that every AI of a type warns once.
local warnedScopes = setmetatable({}, { __mode = "k" })

local function holdsModule(container, module)
	for _, held in ipairs(container.modules or {}) do
		if held == module then
			return true
		end
	end
	return false
end

--- Loads one module class of modules.lua according to its Scope()
--
-- A module of this object's scope gets an instance of its own, a module of a wider scope is the instance the
-- ally or global object holds, a module of a narrower scope is skipped
--
-- @param moduleClass a module class, not yet instantiated
function ShardAI:LoadModule(moduleClass)
	local name = moduleClass:Name()
	local scope = type(moduleClass.Scope) == "function" and moduleClass:Scope() or nil
	local rank = scope and SCOPE_RANKS[scope] or nil
	if rank == nil then
		if not warnedScopes[moduleClass] then
			warnedScopes[moduleClass] = true
			self:Warn(
				"Skipping the loading of "
					.. name
					.. ": its Scope() returns "
					.. tostring(scope)
					.. ', declare a Scope() function returning "team", "ally" or "global" on that module.'
			)
		end
		return
	end
	local ownRank = SCOPE_RANKS[self:Scope()]
	if rank < ownRank then
		return
	end
	local internalname = moduleClass:internalName()
	if internalname == "error" then
		self:Warn(
			"CRITICAL ERROR: The module with the name "
				.. name
				.. " has no internal name! Tis is necesssary and not optional, declare an internalName() function on that module immediatley."
		)
		self:Warn("Skipping the loading of " .. name)
		return
	end
	if self[internalname] ~= nil then
		self:Warn(
			"CRITICAL ERROR: Shard tried to add a module with the internal name "
				.. internalname
				.. " but one already exists!! There cannot be duplicates! Shard will skip this module to avoid overwriting an existing module"
		)
		return
	end
	if rank > ownRank then
		local container = scope == "global" and self.global or self.ally
		local shared = container and container[internalname]
		if shared == nil or not holdsModule(container, shared) then
			self:Warn("Skipping the loading of " .. name .. ": no " .. scope .. " object holds it")
			return
		end
		self[internalname] = shared
		return
	end
	local newmodule = moduleClass()
	self:Info("adding " .. name .. " module")
	self[internalname] = newmodule
	table.insert(self.modules, newmodule)
	newmodule:SetAI(self)
end

function ShardAI:Init()
	if self.loaded == true then
		self:Warn(self:Name() .. " Init called multiple times")
		return
	end
	--tracyZoneBeginMem("ShardAI:Init")

	self.loaded = true
	self.game = self.api.game
	self.map = self.api.map
	self.game.ai = self
	self.map.ai = self
	self.data = {}
	self.game:DrawDisplay(false)
	self:Info(self.fullname .. " - playing: " .. self.game:GameName() .. " on: " .. self.map:MapName())

	if self:Scope() == "team" then
		self.api.shard_include("behaviourfactory")
		self.api.shard_include("unit")
	end
	local modules = self.api.shard_include("modules")
	self.modules = {}

	if next(modules) ~= nil then
		for i, m in ipairs(modules) do
			self:LoadModule(m)
		end
		for i, m in ipairs(self.modules) do
			if m == nil then
				self:Warn("Error! Shard tried to init a nil module!")
			else
				tracyZoneBeginMem(m:Name())
				m:Init()
				tracyZoneEndMem()
			end
		end

	else
		self:Warn("Shard found no modules :( Who will control the units now?")
	end
	self:BuildHandlers()
	--tracyZoneEndMem()
end

--- For every event, the modules that want it, in the order of modules.lua; built after Init and AddModule
--
-- When the AI class declares MScheduler, a list of module names, the modules of this object named there go to
-- scheduledModules (position in the list -> module): the loader's scheduler runs their Update in turns, and they
-- leave the Update of every frame. When it declares BScheduler, a list of behaviour names, the AI gets them as
-- the set scheduledBehaviours, which Unit:Update reads; ally and global objects never get BScheduler.
function ShardAI:BuildHandlers()
	local scheduled = {} ---@type table<integer, table>
	local inTurns = {}
	local names = self.MScheduler
	if names ~= nil then
		for _, m in ipairs(self.modules) do
			local name = m:Name()
			for position = 1, #names do
				if names[position] == name then
					scheduled[position] = m
					inTurns[m] = true
				end
			end
		end
	end
	local handlers = {}
	for _, event in ipairs(EVENTS) do
		local list = {}
		for _, m in ipairs(self.modules) do
			if WantsEvent(m, event) and not (event == "Update" and inTurns[m]) then
				list[#list + 1] = m
			end
		end
		handlers[event] = list
	end
	self.handlers = handlers
	self.scheduledModules = scheduled
	local behaviourNames = self.BScheduler ---@type string[]?
	if behaviourNames ~= nil then
		local set = {}
		for i = 1, #behaviourNames do
			set[behaviourNames[i]] = true
		end
		self.scheduledBehaviours = set
	end
end

--- Whether a module of this object wants the event: the loader calls the object only then
function ShardAI:WantsEvent(event)
	local handlers = self.handlers
	return handlers == nil or handlers[event][1] ~= nil
end

function ShardAI:Prepare()
	--tracyZoneBeginMem("ShardAI:Prepare")
	ai = self
	game = self.api.game
	map = self.api.map
	shard_include = self.api.shard_include
	if self.loaded ~= true then
		self:Init()
	end
	--tracyZoneEndMem()
end

function ShardAI:Update()
	if self.gameend == true then
		return
	end

	----tracyZoneBeginMem("ShardAI:Update")
	--self.game:StartTimer('UPDATE')
	for i, m in ipairs(self.handlers.Update) do
		if m == nil then
			self:Warn("nil module!")
		else
			--self.game:StartTimer(m:Name() .. ' hst')
			--tracyZoneBeginMem('STAI'..m:Name())
			--local RAM = gcinfo()
			m:Update()
			--RAM =  gcinfo() -RAM
			--if RAM > 0 then
			--	print (RAM,m:Name())
			--end
			--tracyZoneEndMem('STAI'..m:Name())
			--self.game:StopTimer(m:Name() .. ' hst')
		end
	end
	----tracyZoneEndMem()
	--self.game:StopTimer('UPDATE')
end

--- The turn of one module of MScheduler: position is its place in the list
function ShardAI:ScheduledUpdate(position)
	if self.gameend == true then
		return
	end
	local m = self.scheduledModules[position]
	if m ~= nil then
		m:Update()
	end
end

function ShardAI:GameMessage(text)
	if self.gameend == true then
		return
	end
	for i, m in ipairs(self.handlers.GameMessage) do
		if m == nil then
			self:Warn("nil module!")
		else
			--self.game:StartTimer(m:Name() .. ' M')
			m:GameMessage(text)
			--self.game:StopTimer(m:Name() .. ' M')
		end
	end
end

function ShardAI:UnitCreated(unit, unitDefId, teamId, builderId)
	if self.gameend == true then
		return
	end
	if unit == nil then
		self:Warn("shard found nil engineunit")
		return
	end
	if (self.modules == nil) or (#self.modules == 0) then
		self:Warn("No modules found in AI")
		return
	end

	--tracyZoneBeginMem("ShardAI:UnitCreated")
	for i, m in ipairs(self.handlers.UnitCreated) do
		--self.game:StartTimer(m:Name() .. ' C')

		--tracyZoneBeginMem(m:Name())
		m:UnitCreated(unit, unitDefId, teamId, builderId)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' C')
	end
	--tracyZoneEndMem()
end

function ShardAI:UnitBuilt(engineunit, unitDefId, teamId)
	if self.gameend == true then
		return
	end
	if engineunit == nil then
		self:Warn("shard-warning: unitbuilt engineunit nil ")
		return
	end

	--tracyZoneBeginMem("ShardAI:UnitBuilt")
	for i, m in ipairs(self.handlers.UnitBuilt) do
		--self.game:StartTimer(m:Name() .. ' B')
		--tracyZoneBeginMem(m:Name())
		m:UnitBuilt(engineunit, unitDefId, teamId)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' B')
	end
	--tracyZoneEndMem()
end

function ShardAI:UnitGiven(engineunit, unitDefId, teamId)
	if self.gameend == true then
		return
	end
	if engineunit == nil then
		return
	end
	for i, m in ipairs(self.handlers.UnitGiven) do
		m:UnitGiven(engineunit, unitDefId, teamId)
	end
end

function ShardAI:UnitDead(engineunit)
	if self.gameend == true then
		return
	end
	if engineunit == nil then
		return
	end
	--tracyZoneBeginMem("ShardAI:UnitDead")
	for i, m in ipairs(self.handlers.UnitDead) do
		--self.game:StartTimer(m:Name() .. ' D')
		--tracyZoneBeginMem(m:Name())
		m:UnitDead(engineunit)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' D')
	end
	--tracyZoneEndMem()
end

function ShardAI:UnitIdle(engineunit)
	if self.gameend == true then
		return
	end
	if engineunit == nil then
		self:Warn("shard-warning: idle engineunit nil")
		return
	end
	--tracyZoneBeginMem("ShardAI:UnitIdle")

	for i, m in ipairs(self.handlers.UnitIdle) do
		--self.game:StartTimer(m:Name() .. ' I')
		--tracyZoneBeginMem(m:Name())
		m:UnitIdle(engineunit)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' I')
	end
	--tracyZoneEndMem()
end

function ShardAI:UnitDamaged(engineunit, engineattacker, enginedamage)
	if self.gameend == true then
		return
	end
	if engineunit == nil then
		return
	end
	--tracyZoneBeginMem("ShardAI:UnitDamaged")
	-- self.game:SendToConsole("UnitDamage for " .. enginedamage:Damage())
	for i, m in ipairs(self.handlers.UnitDamaged) do
		--self.game:StartTimer(m:Name() .. ' G')
		--tracyZoneBeginMem(m:Name())
		m:UnitDamaged(engineunit, engineattacker, enginedamage)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' G')
	end
	--tracyZoneEndMem()
end

function ShardAI:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
	if self.gameend == true then
		return
	end
	if unitID == nil then
		return
	end
	--tracyZoneBeginMem("ShardAI:UnitEnteredLos")
	-- self.game:SendToConsole("UnitDamage for " .. enginedamage:Damage())
	for i, m in ipairs(self.handlers.UnitEnteredLos) do
		--self.game:StartTimer(m:Name() .. ' G')
		--tracyZoneBeginMem(m:Name())
		m:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' G')
	end
	--tracyZoneEndMem()
end

function ShardAI:UnitLeftLos(unitID, unitTeam, allyTeam, unitDefID)
	if self.gameend == true then
		return
	end
	if unitID == nil then
		return
	end
	-- self.game:SendToConsole("UnitDamage for " .. enginedamage:Damage())
	--tracyZoneBeginMem("ShardAI:UnitLeftLos")
	for i, m in ipairs(self.handlers.UnitLeftLos) do
		--self.game:StartTimer(m:Name() .. ' G')
		--tracyZoneBeginMem(m:Name())
		m:UnitLeftLos(unitID, unitTeam, allyTeam, unitDefID)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' G')
	end
	--tracyZoneEndMem()
end

function ShardAI:UnitEnteredRadar(unitID, unitTeam, allyTeam, unitDefID)
	if self.gameend == true then
		return
	end
	if unitID == nil then
		return
	end
	-- self.game:SendToConsole("UnitDamage for " .. enginedamage:Damage())
	--tracyZoneBeginMem("ShardAI:UnitEnteredRadar")
	for i, m in ipairs(self.handlers.UnitEnteredRadar) do
		--self.game:StartTimer(m:Name() .. ' G')
		--tracyZoneBeginMem(m:Name())
		m:UnitEnteredRadar(unitID, unitTeam, allyTeam, unitDefID)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' G')
	end
	--tracyZoneEndMem()
end

function ShardAI:UnitLeftRadar(unitID, unitTeam, allyTeam, unitDefID)
	if self.gameend == true then
		return
	end
	if unitID == nil then
		return
	end
	--tracyZoneBeginMem("ShardAI:UnitLeftRadar")
	-- self.game:SendToConsole("UnitDamage for " .. enginedamage:Damage())
	for i, m in ipairs(self.handlers.UnitLeftRadar) do
		--self.game:StartTimer(m:Name() .. ' G')
		--tracyZoneBeginMem(m:Name())
		m:UnitLeftRadar(unitID, unitTeam, allyTeam, unitDefID)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' G')
	end
	--tracyZoneEndMem()
end

function ShardAI:UnitMoveFailed(engineunit)
	if self.gameend == true then
		return
	end
	if engineunit == nil then
		return
	end
	--tracyZoneBeginMem("ShardAI:UnitMoveFailed")
	for i, m in ipairs(self.handlers.UnitMoveFailed) do
		--self.game:StartTimer(m:Name() .. ' F')
		--tracyZoneBeginMem(m:Name())
		m:UnitMoveFailed(engineunit)
		--tracyZoneEndMem()
		--self.game:StopTimer(m:Name() .. ' F')
	end
	--tracyZoneEndMem()
end

function ShardAI:GameEnd()
	self.gameend = true
	for i, m in ipairs(self.handlers.GameEnd) do
		m:GameEnd()
	end
end

--- Adds a module after Init
--
-- Adds and initializes a module instance to
-- this instance of the AI.
--
-- Note that this function does not get called
-- by the AIs main Init, so changing this will
-- not change how the modules are loaded at startup
--
-- Only modules of this object's scope are added
--
-- @param newmodule a module object to initialize and add
function ShardAI:AddModule(newmodule)
	if newmodule:Scope() ~= self:Scope() then
		self:Warn("Skipping " .. newmodule:Name() .. ": only " .. self:Scope() .. " modules can be added here")
		return
	end
	local internalname = newmodule:internalName()
	if self[internalname] ~= nil then
		self:Warn(
			"CRITICAL ERROR: Shard tried to add a module with the internal name "
				.. internalname
				.. " but one already exists!! There cannot be duplicates! Shard will skip this module to avoid overwriting an existing module"
		)
		return
	end
	self[internalname] = newmodule
	table.insert(self.modules, newmodule)
	newmodule:SetAI(self)
	newmodule:Init()
	self:BuildHandlers()
end
