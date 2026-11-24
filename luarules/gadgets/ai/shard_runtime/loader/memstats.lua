-- Memory of the Lua state the AIs run in, on the hosting client: the memory allocated in each GameFrame,
-- written once a minute while the option ShardMemStats is on, and the peak heap written at the end. Unsynced.
--
-- Option ShardMemStats (springsettings.cfg, or /set ShardMemStats 1 in game, read again every minute):
-- once a minute of game "[AI Loader] memory per frame: avg <KB> max <KB> over <N> frames, heap <MB>", the
-- Lua memory the loader and the AIs allocate in GameFrame. A step of the incremental garbage collector in
-- the middle of a frame lowers that frame's figure, even below zero. Off, it costs one check per frame.
--
-- The safety net of the old loader, always on: every 121 frames, a full collection when the Lua memory is above
-- a limit that starts at 200 MB and grows by 50 MB for every AI.

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

-- in KB, as in the old loader
local basememlimit = 200000
local pershardmemlimit = 50000
local garbagelimit = basememlimit -- in kilobytes, will adjust upwards as needed
local numShards = 0

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

--- The limit grows for every AI this client runs, as when the old loader set up an AI
local function AIAdded(thisAI)
	garbagelimit = math.min(1000000, garbagelimit + pershardmemlimit)
	spEcho(
		string.format(
			"AI %d (%s) using %d MB RAM, adjusting limit to %d MB",
			thisAI.id,
			thisAI.fullname,
			basememlimit / 1000,
			garbagelimit / 1000
		)
	)
	numShards = numShards + 1
end

--- Called in GameFrame after the AIs' Update
local function SafetyNet(n)
	if n % 121 == 0 then
		local ramuse = gcInfo()
		if ramuse > garbagelimit then
			-- safety net against out-of-memory crashes, as in the old loader
			collectGarbage("collect")
			local notgarbagemem = gcInfo()
			local newgarbagelimit = math.min(1000000, notgarbagemem + basememlimit + pershardmemlimit * numShards) -- peak 1 GB
			spEcho(
				string.format(
					"%d STAIs using %d MB RAM > %d MB limit, performing garbage collection and adjusting limit to %d MB",
					numShards,
					math.floor(ramuse / 1000),
					math.floor(garbagelimit / 1000),
					math.floor(newgarbagelimit / 1000)
				)
			)
			garbagelimit = newgarbagelimit
		end
	end
end

local function WritePeak()
	spEcho("Shard memory record:", peak)
end

return {
	BeginFrame = BeginFrame,
	EndFrame = EndFrame,
	AIAdded = AIAdded,
	SafetyNet = SafetyNet,
	WritePeak = WritePeak,
}
