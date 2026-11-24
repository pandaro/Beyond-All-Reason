---@diagnostic disable: undefined-global

-- Every call a module gets goes to SpecLog as { name, internalName, owner object, arguments... };
-- SpecHooks[name], when set by the spec, runs with the module and the arguments; SpecQuiet turns both off.
local EVENTS = {
	"Init",
	"Update",
	"GameEnd",
	"UnitCreated",
	"UnitBuilt",
	"UnitDead",
	"UnitIdle",
	"UnitDamaged",
	"UnitEnteredLos",
	"UnitLeftLos",
	"UnitEnteredRadar",
	"UnitLeftRadar",
}

local function recordingModule(className, internalName, scope)
	local moduleClass = class(Module)
	function moduleClass:Name()
		return className
	end
	function moduleClass:internalName()
		return internalName
	end
	function moduleClass:Scope()
		return scope
	end
	for _, event in ipairs(EVENTS) do
		moduleClass[event] = function(self, ...)
			if SpecQuiet then
				return
			end
			SpecLog[#SpecLog + 1] = { event, internalName, self.ai, ... }
			local hook = SpecHooks[event]
			if hook then
				hook(self, ...)
			end
		end
	end
	return moduleClass
end

SpecGlobalModule = recordingModule("SpecGlobalModule", "specglobal", "global")
SpecAllyModule = recordingModule("SpecAllyModule", "specally", "ally")
SpecTeamModule = recordingModule("SpecTeamModule", "specteam", "team")
SpecTeamModuleB = recordingModule("SpecTeamModuleB", "specteamb", "team")
SpecTeamModuleC = recordingModule("SpecTeamModuleC", "specteamc", "team")
