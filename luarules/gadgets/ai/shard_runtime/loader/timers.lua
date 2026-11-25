-- How long the calls into modules and behaviours take, on the hosting client. Unsynced.
--
-- shardai.lua and unit.lua call BeginModule/EndModule around every call into a module, Begin/EndBehaviour around
-- every call into a behaviour. A call longer than SPIKE_MS writes one line:
-- "[Shard timer] frame=<n> ai=<AI> team=<id|-> ally=<id|-> scope=<scope> module=<name|-> behaviour=<name|->
-- call=<method> ms=<ms>"
-- A behaviour's module is the module whose call is running when the behaviour is called. A module's time
-- includes the behaviours it calls. GameOver and Shutdown write one summary line per name, the first time only.
--
-- Times come from Spring.GetTimerMicros read here, in the loader: in the environment of the modules it is an
-- opaque value. Its step grows with the uptime of the process (2 us at the start, 256 us after 45 minutes).

local TIMERS_ON = true -- off: no time is read and nothing is written
local SPIKE_MS = 10

local spEcho = Spring.Echo
local spGetTimerMicros = Spring.GetTimerMicros
local spDiffTimers = Spring.DiffTimers
local spGetGameFrame = Spring.GetGameFrame
local stringFormat = string.format

local enabled = TIMERS_ON
local currentModule = nil ---@type string? the module whose call is running
---@class ShardTimerStat
---@field kind string "module" or "behaviour"
---@field calls integer
---@field min number
---@field max number
---@field sum number
---@field spikes integer the calls above SPIKE_MS

local stats = {} ---@type table<string, ShardTimerStat>
local summaryWritten = false

local function Record(name, kind, ms, object, moduleName, behaviourName, call)
	local entry = stats[name] ---@type ShardTimerStat?
	if entry == nil then
		entry = { kind = kind, calls = 0, min = ms, max = ms, sum = 0, spikes = 0 }
		stats[name] = entry
	end
	entry.calls = entry.calls + 1
	entry.sum = entry.sum + ms
	if ms < entry.min then
		entry.min = ms
	end
	if ms > entry.max then
		entry.max = ms
	end
	if ms <= SPIKE_MS then
		return
	end
	entry.spikes = entry.spikes + 1
	local scope = object and object:Scope() or "-"
	local team = scope == "team" and object.id or "-"
	local ally = object and object.allyId or "-"
	spEcho(
		stringFormat(
			"[Shard timer] frame=%d ai=%s team=%s ally=%s scope=%s module=%s behaviour=%s call=%s ms=%.1f",
			spGetGameFrame(),
			tostring(object and object.fullname or "-"),
			tostring(team),
			tostring(ally),
			scope,
			moduleName or "-",
			behaviourName or "-",
			call,
			ms
		)
	)
end

--- Before a call into a module: the start time, and the module whose call was running, for EndModule
---@return any? startTimer nil when the timers are off
---@return string? outerModule
local function BeginModule(module)
	if not enabled then
		return nil, nil
	end
	local outer = currentModule
	currentModule = module:Name()
	return spGetTimerMicros(), outer
end

--- After a call into a module of `object` (the team, ally or global object that called it)
local function EndModule(startTimer, outerModule, object, module, call)
	if startTimer == nil then
		return
	end
	local ms = spDiffTimers(spGetTimerMicros(), startTimer, true, true)
	currentModule = outerModule
	local name = module:Name()
	Record(name, "module", ms, object, name, nil, call)
end

--- Before a call into a behaviour
---@return any? startTimer nil when the timers are off
local function BeginBehaviour()
	if not enabled then
		return nil
	end
	return spGetTimerMicros()
end

--- After a call into a behaviour of a unit of `ai`
local function EndBehaviour(startTimer, ai, behaviour, call)
	if startTimer == nil then
		return
	end
	local ms = spDiffTimers(spGetTimerMicros(), startTimer, true, true)
	local name = behaviour:Name()
	Record(name, "behaviour", ms, ai, currentModule, name, call)
end

--- One line per name, the largest sum first; only the first call writes
local function WriteSummary()
	if summaryWritten or next(stats) == nil then
		return
	end
	summaryWritten = true
	local names = {} ---@type string[]
	for name in pairs(stats) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b)
		return (stats[a] --[[@as ShardTimerStat]]).sum > (stats[b] --[[@as ShardTimerStat]]).sum
	end)
	spEcho(stringFormat("[Shard timer summary] names=%d spike_ms=%s", #names, tostring(SPIKE_MS)))
	for i = 1, #names do
		local name = names[i]
		local entry = stats[name] --[[@as ShardTimerStat]]
		spEcho(
			stringFormat(
				"[Shard timer summary] name=%s kind=%s calls=%d min=%.3f max=%.1f avg=%.3f sum=%.1f spikes=%d",
				name,
				entry.kind,
				entry.calls,
				entry.min,
				entry.max,
				entry.sum / entry.calls,
				entry.sum,
				entry.spikes
			)
		)
	end
end

--- For the specs: TIMERS_ON stays the switch of the game
local function SetEnabled(on)
	enabled = on
end

return {
	SPIKE_MS = SPIKE_MS,
	BeginModule = BeginModule,
	EndModule = EndModule,
	BeginBehaviour = BeginBehaviour,
	EndBehaviour = EndBehaviour,
	WriteSummary = WriteSummary,
	SetEnabled = SetEnabled,
}
