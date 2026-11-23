Module = class(AIBase)

--- What is the human readable name off this object?
--
-- @return string the human friendly name
function Module:Name()
	return "error no name module name defined"
end

--- What is the internal name of this object?
--
-- Shard will not add this module if this is set to error
-- overriding this is *mandatory*
--
-- This gets used to define variable names in places
--
-- @return string the internal name
function Module:internalName()
	return "error"
end

--- Which scope holds this module?
--
-- Shard will not add this module if this is not one of the three scopes
-- overriding this is *mandatory*
--
-- "team": one instance for every AI
-- "ally": one instance shared by the AIs of the same type in an ally team
-- "global": one instance shared by every AI of the same type that this client hosts
--
-- A module reaches the modules of its own and wider scopes as self.ai.<internalName>, never narrower ones
--
-- @return string the scope
function Module:Scope()
	return "error"
end

function Module:Warn(...)
	self.game:SendToConsole(self:ConsoleOwner(), self.ai:Name(), self:Name(), "Warning:", ...)
end

function Module:EchoDebug(...)
	if self.DebugEnabled then
		self.game:SendToConsole(self:ConsoleOwner(), self.ai:Name(), self:Name(), ...)
	end
end
