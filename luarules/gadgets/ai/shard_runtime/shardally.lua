--- The ally team scope: one object per ally team and AI type, holding the modules whose Scope() is "ally"
--
-- Fields set by the AI loader before Init:
-- allyId: the ally team
-- AIs: the team AIs of this type in the ally team
-- global: the ShardGlobal of this AI type, whose modules this object reaches
-- fullname, api: as on a team AI
--
-- Init fills game, map and modules as ShardAI:Init does; no behaviours, they belong to teams
ShardAlly = class(ShardAI)

function ShardAlly:Name()
	return "ShardAlly"
end

function ShardAlly:internalName()
	return "shardally"
end

function ShardAlly:Scope()
	return "ally"
end
