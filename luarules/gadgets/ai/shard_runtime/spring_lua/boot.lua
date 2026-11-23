-- initial setup of things

-- Stands in an include cache for a file that returned nil, which a plain lookup cannot tell from a file never run.
local CACHED_NIL = {}

-- Runs `file` in `env` the first time and keeps what it returned under its lowercased path: VFS paths ignore case.
local function cachedInclude(cache, file, env)
	local key = string.lower(file)
	local cached = cache[key]
	if cached == nil then
		cached = VFS.Include(file, env)
		if cached == nil then
			cached = CACHED_NIL
		end
		cache[key] = cached
	end
	if cached == CACHED_NIL then
		return nil
	end
	return cached
end

--- Generates a per AI shard_include function
--
-- Returns a function that can be used for shard_include
-- that is specific for a particular AI
-- e.g.
--
-- ```
-- local load = shard_generate_include_func( 'luarules/gadgets/shard_runtime', 'luarules/gadgets/myai' )
-- local config = load( "config" )
-- ```
--
-- The returned function will also check for a folder with that file name
--
-- With an environment, the AI type's files run in it and each runs once: later includes of the same file get
-- the value its first run returned, so the classes it defines are defined once for every AI of the type
--
-- @param runtime_path the location of the Shard runtime
-- @param ai_path the location of the AI itself
-- @param env optional environment of the AI type; without it the files run in the caller's, every time
--
-- @return function a shard_include function
function shard_generate_include_func(runtime_path, ai_path, env)
	local cache = env and {}
	return function(file)
		if type(file) ~= "string" then
			return nil
		end
		local candidates = {
			ai_path .. "/" .. file .. ".lua",
			ai_path .. "/" .. file .. "/main.lua",
			runtime_path .. "/" .. file .. ".lua",
			runtime_path .. "/" .. file .. "/main.lua",
		}
		for index, file in ipairs(candidates) do
			if VFS.FileExists(file) then
				if not cache then
					-- not a tail call: VFS.Include runs the file in its caller's environment, and in the global one
					-- when the caller is gone after a tail call
					local result = VFS.Include(file)
					return result
				end
				return cachedInclude(cache, file, env)
			end
		end
		Spring.Echo("Failed to load " .. file .. " we attempted to load the first of the following:")
		for index, file in ipairs(candidates) do
			Spring.Echo(index .. ": " .. file)
		end
		return nil
	end
end

--- the default shard include function, only deals with the runtime files for boot up
function shard_include(file)
	if type(file) ~= "string" then
		return nil
	end
	local runtime_file = "luarules/gadgets/ai/shard_runtime/" .. file .. ".lua"
	if VFS.FileExists(runtime_file) then
		-- not a tail call, as above: the runtime files must run in this file's environment
		local result = VFS.Include(runtime_file)
		return result
	end
	Spring.Echo("Failed to load " .. runtime_file)
	return
end

os = shard_include("spring_lua/fakeos")
api = shard_include("spring_lua/fakeapi")

local runtime_includes = {
	"spring_lua/shard",
	"class",
	"aibase",
	"module",
	"shardai",
	"shardally",
	"shardglobal",
	"spring_lua/unit",
	"spring_lua/unittype",
	"spring_lua/damage",
	"spring_lua/feature",
	"spring_lua/outbox",
}

for key, include in ipairs(runtime_includes) do
	local result = shard_include(include)
end
