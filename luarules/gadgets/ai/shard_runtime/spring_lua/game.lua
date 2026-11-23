---@class ShardGame
---@field ai table the object whose game this is, set by its Init
---@field warnedNoOutbox boolean?
local game = {}
--game_engine

-- prints 'message' to ingame chat console
function game:SendToConsole(...)
	Spring.Echo(...)
	return true
end

function game:Frame() -- returns int/game frame number
	return Spring.GetGameFrame() -- Spring Gadget API
end

function game:Test() -- debug
	Spring.Echo("Testing API")
	return true
end

function game:IsPaused() -- if the game is paused, returns true
	local _, _, paused = Spring.GetGameSpeed()
	return paused
end

function game:GetTypeByName(typename) -- returns unittype
	if not UnitDefNames[typename] then
		Spring.Echo('shard: debug: could not find "' .. typename .. '" in UnitDefNames')
		return nil
	end
	local def = UnitDefNames[typename]
	return Shard:shardify_unittype(def.id)
end

function game:GetUnitLos(id, bitmask)
	bitmask = bitmask or true
	return Spring.GetUnitLosState(id, self.ai.allyId, bitmask)

end

function game:ConfigFolderPath() -- returns string with path to the folder
	return "luarules/gadgets/ai/" .. self:GameName() .. "/"
	-- return game_engine:ConfigFolderPath()
end

function game:ReadFile(filename) -- returns string with file contents
	return VFS.LoadFile(filename)
end

function game:FileExists(filename) -- returns boolean
	return VFS.FileExists(filename)
end

function game:GetTeamID()
	return self.ai.id
	-- return Spring.GetMyTeamID()
end

function game:GetAllyTeamID()
	return self.ai.allyId
end

function game:getUnitsInCylinder(pos, range)
	return Spring.GetUnitsInCylinder(pos.x, pos.z, range, team)
end

function game:GetTeamUnitDefCount(team, unitDef)
	return Spring.GetTeamUnitDefCount(team, unitDef)
end

function game:GetTeamUnitsByDefs(team, unitDef)
	return Spring.GetTeamUnitsByDefs(team, unitDef)
end

function game:GetUnitSeparation(Id1, Id2, d2d, surface)
	return Spring.GetUnitSeparation(Id1, Id2, d2d, surface)
end

function game:GetEnemies()
	local ev = self.ai.enemyUnitIds
	if not ev then
		return {}
	end
	local e = {}
	local n = 0
	for uID, _ in pairs(ev) do
		n = n + 1
		e[n] = Shard:shardify_unit(uID)
	end
	return e
end

function game:GetUnits()
	local uv = self.ai.ownUnitIds
	if not uv then
		return {}
	end
	local u = {}
	local n = 0
	for uID, _ in pairs(uv) do
		n = n + 1
		u[n] = Shard:shardify_unit(uID)
	end
	return u
end

function game:GetFriendlies()
	local fv = self.ai.friendlyUnitIds
	if not fv then
		return {}
	end
	local f = {}
	local n = 0
	for uID, _ in pairs(fv) do
		n = n + 1
		f[n] = Shard:shardify_unit(uID)
	end
	return f
end

function game:GameName() -- returns the shortname of this game
	return Game.gameShortName
end

function game:AddMarker(position, label) -- adds a marker
	Spring.MarkerAddPoint(position.x, position.y, position.z, label)
	return true
end
-- 		gadgetHandler:AddSyncAction('ShardDrawDisplay', sdDisplay)
-- 		gadgetHandler:AddSyncAction('ShardStartTimer', sStartTimer)
-- 		gadgetHandler:AddSyncAction('ShardStopTimer', sStopTimer)
function game:StartTimer(name)
	--return SendToUnsynced('ShardStartTimer',name)
	if Script.LuaUI("ShardStartTimer") then
		Script.LuaUI.ShardStartTimer(name)
	end
end

function game:StopTimer(name)
	--return SendToUnsynced('ShardStopTimer',name)
	if Script.LuaUI("ShardStopTimer") then
		Script.LuaUI.ShardStopTimer(name)
	end
end
function game:DrawDisplay(onOff)
	self.ai.drawDebug = onOff
	--return SendToUnsynced('ShardDrawDisplay',onOff)
	if Script.LuaUI("ShardDrawDisplay") then
		Script.LuaUI.ShardDrawDisplay(onOff)
	end
end

function game:SendToContent(stringvar) -- returns a string passed from any lua gadgets
	-- doesn't make a lot of sense if we're already in the lua environment, needs discussin
	return false --game_engine:SendToContent(stringvar)
end

function game:GetResource(idx) --  returns a Resource object
	local currentLevel, storage, pull, income, expense, share, sent, received =
		Spring.GetTeamResources(self.ai.id, Shard.resourceIds[idx])
	return Shard:shardify_resource({
		currentLevel = currentLevel,
		storage = storage,
		pull = pull,
		income = income,
		expense = expense,
		share = share,
		sent = sent,
		received = received,
	})
end

function game:GetResourceCount() -- return the number of resources
	return 2 --game_engine:GetResourceCount()
end

function game:GetResourceByName(name) -- returns a Resource object, takes the name of the resource
	name = string.lower(name)
	local currentLevel, storage, pull, income, expense, share, sent, received =
		Spring.GetTeamResources(self.ai.id, name)
	return Shard:shardify_resource({
		currentLevel = currentLevel,
		storage = storage,
		pull = pull,
		income = income,
		expense = expense,
		share = share,
		sent = sent,
		received = received,
	})
end

function game:GetUnitByID(unit_id) -- returns a Shard unit when given an engine unit ID number
	return Shard:shardify_unit(unit_id)
end

local function warnOrders(game, text)
	if game.ai ~= nil then
		game.ai:Warn(text)
	else
		Spring.Echo("Shard Warning: " .. text)
	end
end

-- The i-th entry of an optional array argument.
local function arrayEntry(array, i)
	if type(array) == "table" then
		return array[i]
	end
	return nil
end

--- Queues orders in the outbox of this AI, with the methods of STAI's Tool:GiveOrder
--
-- '1-1': one command to one unit: id, cmd, params and options of the command
-- '2-1': commands to one unit: id, then arrays cmd, params and options with an entry per command; they stay together
-- '1-2': one command to units: an array of ids, then cmd, params and options as in '1-1'
-- '2-2': a command each to units: arrays id, cmd, params and options; id[i] gets cmd[i], params[i] and options[i]
--        as Spring.GiveOrderArrayToUnitArray(units, commands, true) did, up to the shorter of id and cmd
--
-- params: nil, a number, an array of numbers or a position table; options: a CMD.OPT_* mask or an array of names
--
-- @return boolean whether every order was queued
function game:GiveOrder(id, cmd, params, options, method)
	local outbox = self.ai and self.ai.outbox ---@type ShardOutbox?
	if outbox == nil then
		if not self.warnedNoOutbox then
			self.warnedNoOutbox = true
			warnOrders(self, "no outbox for this AI: its orders are dropped")
		end
		return false
	end
	if method == "1-1" then
		return outbox:Queue(id, cmd, params, options)
	elseif method == "2-1" then
		if type(cmd) ~= "table" or (params ~= nil and type(params) ~= "table") or type(options) == "number" then
			warnOrders(self, "GiveOrder '2-1' takes arrays of commands, params and options; orders dropped")
			return false
		end
		outbox:BeginGroup()
		for i = 1, #cmd do
			outbox:Queue(id, cmd[i], arrayEntry(params, i), arrayEntry(options, i))
		end
		return outbox:EndGroup()
	elseif method == "1-2" then
		if type(id) ~= "table" or type(cmd) ~= "number" then
			warnOrders(self, "GiveOrder '1-2' takes an array of units and one command; orders dropped")
			return false
		end
		local queued = true
		for i = 1, #id do
			queued = outbox:Queue(id[i], cmd, params, options) and queued
		end
		return queued
	elseif method == "2-2" then
		if
			type(id) ~= "table"
			or type(cmd) ~= "table"
			or (params ~= nil and type(params) ~= "table")
			or type(options) == "number"
		then
			warnOrders(self, "GiveOrder '2-2' takes arrays of units, commands, params and options; orders dropped")
			return false
		end
		local queued = true
		for i = 1, math.min(#id, #cmd) do
			queued = outbox:Queue(id[i], cmd[i], arrayEntry(params, i), arrayEntry(options, i)) and queued
		end
		return queued
	end
	warnOrders(self, "GiveOrder: unknown method " .. tostring(method))
	return false
end

function game:Pause() -- pauses the game
	Spring.SendCommands("pause")
end

function game:GetResources() -- returns a table of Resource objects, takes the name of the resource
	return { self:GetResource(1), self:GetResource(2) }

	--[[local rcount = game_engine:GetResourceCount()
		if(rcount > 0) then

			local resources = {}

			for i = 0,rcount do
				local res = game:GetResource(i)
				if res.name ~= "" then
					resources[res.name] = res
				end
			end
			return resources
		else
			return nil
		end]]
	--
end

return game
