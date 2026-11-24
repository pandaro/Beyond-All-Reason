-- @TODO: Move top level logic out of ai.lua into here, and then make it load environment specific boot.lua files

-- outside the engine, shard_null gives the runtime, a null game and map, and the AI's shard_include
local ShardNull = nil
if ShardSpringLua then
	-- VFS.Include( "luarules/gadgets/ai/shard_runtime/spring_lua/boot.lua" )
else
	ShardNull = require("shard_runtime/shard_null/boot")
	ShardNull.SetAIFolder("Shard")
end

shard_include("ai")

-- create and use an AI
if ShardSpringLua then
	return ShardBasic()
else
	ai = ShardBasic()
	---@diagnostic disable-next-line: need-check-nil
	ShardNull.Start(ai, "Shard")
end
