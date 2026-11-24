SchedAI = class(ShardAI)

function SchedAI:Name()
	return "SchedAI"
end

function SchedAI:internalName()
	return "schedai"
end

-- SpecTeamModuleC is not listed: it gets Update every frame
SchedAI.MScheduler = { "SpecTeamModule", "SpecAllyModule", "SpecGlobalModule", "SpecTeamModuleB" }
SchedAI.BScheduler = { "SpecBehaviour" }
