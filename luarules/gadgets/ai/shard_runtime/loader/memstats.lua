-- Memory of the Lua state the AIs run in, on the hosting client: the memory allocated in each GameFrame,
-- written once a minute while the option ShardMemStats is on, and the peak heap written at the end. Unsynced.
--
-- Option ShardMemStats (springsettings.cfg, or /set ShardMemStats 1 in game, read again every minute):
-- once a minute of game "[AI Loader] memory per frame: avg <KB> max <KB> over <N> frames, heap <MB>", the
-- Lua memory the loader and the AIs allocate in GameFrame. A step of the incremental garbage collector in
-- the middle of a frame lowers that frame's figure, even below zero. Off, it costs one check per frame.

local spEcho = Spring.Echo
local spGetConfigInt = Spring.GetConfigInt
local collectGarbage = collectgarbage
local gcInfo = gcinfo

local REPORT_FRAMES = 1800 -- one line a minute
local PEAK_FRAMES = 300 -- how often the peak heap is read

local measuring = spGetConfigInt("ShardMemStats", 0) == 1
local frameStart = false ---@type number|false memory at the start of the frame being measured
local sum = 0 ---@type number
local largest = 0 ---@type number
local frames = 0
local peak = 0 -- the peak heap at the end of the game, also when ShardMemStats is off

local function AddFrame(allocated)
	sum = sum + allocated
	frames = frames + 1
	if frames == 1 or allocated > largest then
		largest = allocated
	end
end

local function WriteMinute()
	if frames > 0 then
		spEcho(
			string.format(
				"[AI Loader] memory per frame: avg %.2f KB max %.2f KB over %d frames, heap %.1f MB",
				sum / frames,
				largest,
				frames,
				collectGarbage("count") / 1024
			)
		)
	end
	sum, largest, frames = 0, 0, 0
	measuring = spGetConfigInt("ShardMemStats", 0) == 1
end

--- Called at the start of GameFrame, after the AIs started
local function BeginFrame()
	frameStart = measuring and collectGarbage("count")
end

--- Called at the end of GameFrame
local function EndFrame(n)
	if frameStart then
		AddFrame(collectGarbage("count") - frameStart)
	end
	if n > 0 and n % REPORT_FRAMES == 0 then
		WriteMinute()
	end
	if n % PEAK_FRAMES == 0 then
		peak = math.max(peak, gcInfo()) -- measured, never forced
	end
end

local function WritePeak()
	spEcho("Shard memory record:", peak)
end

return {
	BeginFrame = BeginFrame,
	EndFrame = EndFrame,
	WritePeak = WritePeak,
}
