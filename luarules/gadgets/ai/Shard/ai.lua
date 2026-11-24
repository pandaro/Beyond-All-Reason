-- The class of the Shard example AI: a plain ShardAI with its own name. Not called Shard, which is the
-- runtime's global object and would be hidden in the AI type's environment.
ShardBasic = class(ShardAI)

function ShardBasic:Name()
	return "Shard"
end

function ShardBasic:internalName()
	return "shard"
end

-- The modules named here run in turns, one module of one AI a frame, as the loader's scheduler hands them out;
-- the others (UnitHandler, which runs the behaviours, and Sleep, which counts frames) get Update every frame.
ShardBasic.MScheduler = { "AttackHandler", "PlacementHandler" }

-- The behaviours named here get Update only in their turn, one behaviour name of one AI a frame: the task queue
-- of the builders. BootBehaviour counts frames to release a new unit and stays out; AttackerBehaviour has no Update.
ShardBasic.BScheduler = { "TaskQueueBehaviour" }
