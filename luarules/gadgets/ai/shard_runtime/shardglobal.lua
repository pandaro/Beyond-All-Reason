--- The global scope: one object per AI type on the hosting client, holding the modules whose Scope() is "global"
--
-- Fields set by the AI loader before Init:
-- AIs: every team AI of this type the client hosts
-- fullname, api: as on a team AI
--
-- Init fills game, map and modules as ShardAI:Init does; no behaviours, they belong to teams
ShardGlobal = class(ShardAI)

function ShardGlobal:Name()
	return "ShardGlobal"
end

function ShardGlobal:internalName()
	return "shardglobal"
end

function ShardGlobal:Scope()
	return "global"
end
