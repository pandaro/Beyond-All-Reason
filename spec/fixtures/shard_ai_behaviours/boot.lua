-- A Shard AI type for the loader specs whose class declares the turns of its behaviours only; the modules are
-- SpecAI's.
---@diagnostic disable: call-non-callable
BehavAI = class(ShardAI)

function BehavAI:Name()
	return "BehavAI"
end

function BehavAI:internalName()
	return "behavai"
end

BehavAI.BScheduler = { "SpecBehaviour", "SpecBehaviourFree", "SpecBehaviourB" }

return BehavAI()
