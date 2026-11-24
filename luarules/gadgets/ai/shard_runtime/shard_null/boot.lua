-- Shard outside the engine: the runtime classes, the null game and map of shard_null, and a shard_include that looks
-- in the AI's folder first and then in the runtime, as shard_generate_include_func does in the engine.
-- Run with package.path pointing at luarules/gadgets/ai/, for example "luarules/gadgets/ai/?.lua".

local aiFolder = nil -- the AI type's folder under package.path, set by SetAIFolder

-- whether require finds a module, without running it: package.path read as Lua 5.1 reads it
local function Findable(name)
	for pattern in string.gmatch(package.path, "[^;]+") do
		local file = io.open((string.gsub(pattern, "%?", name)), "r")
		if file then
			file:close()
			return true
		end
	end
	return false
end

function shard_include(file)
	if type(file) ~= "string" then
		return nil
	end
	local name = file
	if aiFolder ~= nil and Findable(aiFolder .. "/" .. file) then
		name = aiFolder .. "/" .. file
	elseif Findable("shard_runtime/" .. file) then
		name = "shard_runtime/" .. file
	end
	-- not a tail call: BAR's require goes through VFS.Include, which runs a file in its caller's environment
	local result = require(name)
	return result
end

-- load null objects
require("shard_runtime/class")
require("shard_runtime/aibase")
require("shard_runtime/module")
require("shard_runtime/shardai")
require("shard_runtime/shardally")
require("shard_runtime/shardglobal")
shard_include("shard_runtime/shard_null/unit")
shard_include("shard_runtime/shard_null/unittype")

local ShardNull = {}

--- The folder of the AI type, under package.path: shard_include looks there first
function ShardNull.SetAIFolder(name)
	aiFolder = name
end

--- Sets on the AI what the engine's loader sets (its api, name and team), then Prepare(), which runs Init()
function ShardNull.Start(ai, name)
	local api = require("shard_runtime/api")
	---@diagnostic disable-next-line: inject-field
	api.shard_include = shard_include
	ai.api = api
	ai.fullname = name
	ai.id = 0
	ai.allyId = 0
	ai:Prepare()
end

return ShardNull
