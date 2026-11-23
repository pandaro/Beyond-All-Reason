local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "AI Framework Bench",
		desc = "Cost of engine reads, the order relay and reference AIs for the Lua AI framework: /luarules aibench [relay|direct <teamID> [label] | ref [minutes]]",
		author = "pandaro",
		date = "November 2026",
		license = "GNU GPL, v2 or later",
		layer = 0,
		handler = true,
		enabled = true,
	}
end

-- handler = true hands this gadget the real gadget handler, which timing another gadget's callins needs. The
-- handler swaps it in only after this file has run, so it is looked up on each call; this table offers the
-- rest of the file the calls of the usual per-gadget proxy.
---@return table
local function realHandler()
	return gadget.gadgetHandler
end
local gadgetHandler = {
	IsSyncedCode = function(_)
		return realHandler():IsSyncedCode()
	end,
	UpdateCallIn = function(_, name)
		realHandler():UpdateGadgetCallIn(name, gadget)
	end,
	RemoveCallIn = function(_, name)
		realHandler():RemoveGadgetCallIn(name, gadget)
	end,
	AddChatAction = function(_, cmd, func, help)
		return realHandler().actionHandler.AddChatAction(gadget, cmd, func, help)
	end,
	RemoveChatAction = function(_, cmd)
		return realHandler().actionHandler.RemoveChatAction(gadget, cmd)
	end,
	AddSyncAction = function(_, cmd, func, help)
		return realHandler().actionHandler.AddSyncAction(gadget, cmd, func, help)
	end,
	RemoveSyncAction = function(_, cmd)
		return realHandler().actionHandler.RemoveSyncAction(gadget, cmd)
	end,
}

-- Order message, version 1 of the proposal: 16-byte header (4-byte magic, U8 version, U8 teamID, U32 sequence,
-- U32 emission frame, U16 count), then per order U16 unitID, S32 cmdID, U8 options, U8 n, F32 x n.
local MESSAGE_VERSION = 1
local HEADER_BYTES = 16
local ORDER_FIXED_BYTES = 8
local CMD_MOVE = CMD.MOVE
local CMD_STOP = CMD.STOP
-- Relay test messages share the magic; version 0 is control: U8 teamID, U8 mode, U16 expected messages
-- (0 disarms). VFS.UnpackU8 returns nil for the last byte of a string, so the control message ends with a U16
-- and the relay reads an order's options and n as one U16.
local RELAY_MAGIC = "AIFb"
local RELAY_CONTROL_VERSION = 0
local RELAY_CONTROL_BYTES = 9
-- apply: decode, check and apply move orders; decode: the same without GiveOrderArrayToUnit;
-- stop: decode, check and apply stop orders; direct and direct stop: the synced half gives prebuilt move or
-- stop orders, no message
local RELAY_MODE_APPLY = 1
local RELAY_MODE_DECODE = 2
local RELAY_MODE_STOP = 3
local RELAY_MODE_DIRECT = 4
local RELAY_MODE_DIRECT_STOP = 5
-- ref: expected 1 hooks SimpleAI's callins for timing, 0 unhooks them; teamID is unused
local RELAY_MODE_REF = 6
local RELAY_SIZES = { 1, 100, 1000 }
-- move targets alternate between +/- this many elmos from where each unit stood at the start
local RELAY_MOVE_OFFSET = 64
local RELAY_ACTION_MARK = "aibench_relay_mark"
local RELAY_ACTION_RESULT = "aibench_relay_result"
local RELAY_ACTION_STATE = "aibench_relay_state"
local REF_ACTION_START = "aibench_ref_start"
local REF_ACTION_END = "aibench_ref_end"
local REF_ACTION_STATE = "aibench_ref_state"
local REF_GADGET_NAME = "SimpleAI"

if gadgetHandler:IsSyncedCode() then
	-- Test relay: applies orders only while armed by one player, with cheats on, for one AI team,
	-- and disarms after the expected messages or a timeout. It has no timer: the unsynced half of the
	-- sending client times it through SendToUnsynced marks, which run their handler immediately.
	local spGetGameFrame = Spring.GetGameFrame
	local spGetUnitPosition = Spring.GetUnitPosition
	local spValidUnitID = Spring.ValidUnitID
	local spGetUnitTeam = Spring.GetUnitTeam
	local spGiveOrderArrayToUnit = Spring.GiveOrderArrayToUnit
	local vfsUnpackU8 = VFS.UnpackU8
	local vfsUnpackU16 = VFS.UnpackU16
	local vfsUnpackU32 = VFS.UnpackU32
	local vfsUnpackS32 = VFS.UnpackS32
	local vfsUnpackF32 = VFS.UnpackF32
	local stringSub = string.sub

	-- limits the proposal gives the real relay
	local MAX_ORDERS_PER_MESSAGE = 4000
	local MAX_MESSAGES_PER_FRAME = 2
	local MAX_EXPECTED_MESSAGES = 1000
	local ARM_TIMEOUT_FRAMES = 30 * 60

	---@class AIBenchRelayArm
	---@field playerID integer
	---@field teamID integer
	---@field remaining integer
	---@field expiryFrame integer
	---@field lastSequence integer
	---@field frame integer
	---@field messagesThisFrame integer
	---@field cmdID integer
	---@field apply boolean
	---@field direct AIBenchDirectOrders?

	---@class AIBenchDirectOrders
	---@field unitIDs integer[]
	---@field out table[]
	---@field back table[]
	---@field sample integer

	local armed = nil ---@type AIBenchRelayArm?

	local function disarm(reason)
		local playerID = armed and armed.playerID or -1
		armed = nil
		gadgetHandler:RemoveCallIn("GameFrame")
		SendToUnsynced(RELAY_ACTION_STATE, "disarmed", reason, playerID)
	end

	-- Command tables for the direct modes, built before any timing: per order one unit and one command.
	---@return AIBenchDirectOrders?
	local function buildDirectOrders(teamID, cmdID)
		local teamUnitIDs = Spring.GetTeamUnits(teamID) or {}
		local unitCount = #teamUnitIDs
		if unitCount == 0 then
			return nil
		end
		local direct = { unitIDs = {}, out = {}, back = {}, sample = 0 }
		for k = 1, RELAY_SIZES[#RELAY_SIZES] do
			local unitID = teamUnitIDs[(k - 1) % unitCount + 1] --[[@as integer]]
			local x, y, z = spGetUnitPosition(unitID)
			if not x then
				return nil
			end
			direct.unitIDs[k] = unitID
			if cmdID == CMD_STOP then
				direct.out[k] = { { CMD_STOP, {}, 0 } }
				direct.back[k] = direct.out[k]
			else
				direct.out[k] = { { CMD_MOVE, { x + RELAY_MOVE_OFFSET, y, z }, 0 } }
				direct.back[k] = { { CMD_MOVE, { x - RELAY_MOVE_OFFSET, y, z }, 0 } }
			end
		end
		return direct
	end

	local function armRefusal(playerID, teamID, expected, mode)
		if mode < RELAY_MODE_APPLY or mode > RELAY_MODE_DIRECT_STOP then
			return "unknown mode " .. mode
		end
		if not Spring.IsCheatingEnabled() then
			return "cheats are off (/cheat)"
		end
		local _, _, spectator = Spring.GetPlayerInfo(playerID, false)
		if spectator ~= false then
			return "the sender is a spectator"
		end
		local validTeam, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if not validTeam or not isAI then
			return "team " .. teamID .. " is not an AI team"
		end
		local maxUnits = Game.maxUnits ---@type integer the stub assigns nil
		if maxUnits > 65536 then
			return "unit IDs do not fit in U16"
		end
		if expected > MAX_EXPECTED_MESSAGES then
			return "too many messages requested"
		end
		return nil
	end

	-- SimpleAI timing: its callins are wrapped between two marks for the unsynced half of the requesting
	-- client, like the relay. Marks change no game state, so every client wrapping them stays in sync.
	local REF_HOOKED_CALLINS = { "GameFrame", "UnitCreated", "UnitDestroyed", "UnitFinished" }
	local REF_CALIBRATION_PAIRS = 500

	---@class AIBenchRefHook
	---@field playerID integer
	---@field target table
	---@field originals table<string, function>

	local refHook = nil ---@type AIBenchRefHook?

	local function unhookReference()
		local hook = refHook
		if not hook then
			return
		end
		for _, callin in ipairs(REF_HOOKED_CALLINS) do
			local original = hook.originals[callin] ---@type function?
			if original then
				hook.target[callin] = original
			end
		end
		refHook = nil
		SendToUnsynced(REF_ACTION_STATE, "unhooked", hook.playerID)
	end

	local function hookReference(playerID)
		if refHook then
			return "another player's measure is running"
		end
		if not Spring.IsCheatingEnabled() then
			return "cheats are off (/cheat)"
		end
		local target = nil
		for _, g in ipairs(realHandler().gadgets) do
			if g.ghInfo and g.ghInfo.name == REF_GADGET_NAME then
				target = g
				break
			end
		end
		if not target then
			return REF_GADGET_NAME .. " is not running"
		end
		local originals = {}
		for _, callin in ipairs(REF_HOOKED_CALLINS) do
			local original = target[callin]
			if type(original) == "function" then
				originals[callin] = original
				target[callin] = function(...)
					SendToUnsynced(REF_ACTION_START)
					local r1, r2, r3, r4 = original(...)
					SendToUnsynced(REF_ACTION_END)
					return r1, r2, r3, r4
				end
			end
		end
		refHook = { playerID = playerID, target = target, originals = originals }
		-- empty pairs: their mean is what one timed callin's marks add, which the unsynced half subtracts
		SendToUnsynced(REF_ACTION_STATE, "calibrating", playerID)
		for _ = 1, REF_CALIBRATION_PAIRS do
			SendToUnsynced(REF_ACTION_START)
			SendToUnsynced(REF_ACTION_END)
		end
		SendToUnsynced(REF_ACTION_STATE, "hooked", playerID)
		return nil
	end

	local function handleControl(message, playerID)
		if #message < RELAY_CONTROL_BYTES then
			return
		end
		local teamID = vfsUnpackU8(message, 6)
		local mode = vfsUnpackU8(message, 7)
		local expected = vfsUnpackU16(message, 8)
		if mode == RELAY_MODE_REF then
			if expected == 0 then
				if refHook and refHook.playerID == playerID then
					unhookReference()
				end
				return
			end
			local refusal = hookReference(playerID)
			if refusal then
				SendToUnsynced(REF_ACTION_STATE, "refused", playerID, refusal)
			end
			return
		end
		if expected == 0 then
			if armed and armed.playerID == playerID then
				disarm("cancelled")
			end
			return
		end
		local refusal = armed and "another run is armed" or armRefusal(playerID, teamID, expected, mode)
		local direct = nil
		local cmdID = (mode == RELAY_MODE_STOP or mode == RELAY_MODE_DIRECT_STOP) and CMD_STOP or CMD_MOVE
		if not refusal and mode >= RELAY_MODE_DIRECT then
			direct = buildDirectOrders(teamID, cmdID)
			refusal = not direct and "the team has no units" or nil
		end
		if refusal then
			SendToUnsynced(RELAY_ACTION_STATE, "refused", refusal, playerID)
			return
		end
		armed = {
			playerID = playerID,
			teamID = teamID,
			remaining = expected,
			expiryFrame = spGetGameFrame() + ARM_TIMEOUT_FRAMES,
			lastSequence = 0,
			frame = -1,
			messagesThisFrame = 0,
			cmdID = cmdID,
			apply = mode ~= RELAY_MODE_DECODE,
			direct = direct,
		}
		gadgetHandler:UpdateCallIn("GameFrame")
		SendToUnsynced(RELAY_ACTION_STATE, "armed", teamID, playerID)
	end

	-- Checks the header as the proposal's relay does, then applies each valid order of the armed command;
	-- consecutive orders of one unit become one GiveOrderArrayToUnit, skipped in decode mode.
	-- A truncated message keeps what was applied before it.
	---@param message string
	---@param arm AIBenchRelayArm
	---@return string status
	---@return integer count
	---@return integer accepted
	---@return integer emissionFrame
	local function relayOrders(message, arm)
		local teamID = vfsUnpackU8(message, 6)
		local sequence = vfsUnpackU32(message, 7)
		local emissionFrame = vfsUnpackU32(message, 11)
		local count = vfsUnpackU16(message, 15)
		if teamID ~= arm.teamID then
			return "wrong team", count, 0, emissionFrame
		end
		if sequence <= arm.lastSequence then
			return "old sequence", count, 0, emissionFrame
		end
		local frame = spGetGameFrame()
		if frame ~= arm.frame then
			arm.frame = frame
			arm.messagesThisFrame = 0
		end
		arm.messagesThisFrame = arm.messagesThisFrame + 1
		if arm.messagesThisFrame > MAX_MESSAGES_PER_FRAME then
			return "frame limit", count, 0, emissionFrame
		end
		if count > MAX_ORDERS_PER_MESSAGE then
			return "too many orders", count, 0, emissionFrame
		end
		arm.lastSequence = sequence

		local length = #message
		local armedCmdID = arm.cmdID
		local apply = arm.apply
		local offset = HEADER_BYTES + 1
		local accepted = 0
		local currentUnitID = -1
		local commands = {} ---@type CreateCommand[]
		for _ = 1, count do
			if offset + ORDER_FIXED_BYTES - 1 > length then
				return "truncated", count, accepted, emissionFrame
			end
			local unitID = vfsUnpackU16(message, offset)
			local cmdID = vfsUnpackS32(message, offset + 2)
			-- one little-endian U16: options in the low byte, n in the high one, which can be the message's last
			local optionsAndCount = vfsUnpackU16(message, offset + 6)
			local options = optionsAndCount % 256
			local paramCount = math.floor(optionsAndCount / 256)
			local paramOffset = offset + ORDER_FIXED_BYTES
			offset = paramOffset + 4 * paramCount
			if offset - 1 > length then
				return "truncated", count, accepted, emissionFrame
			end
			if cmdID == armedCmdID and spValidUnitID(unitID) and spGetUnitTeam(unitID) == teamID then
				local params = {}
				for p = 1, paramCount do
					params[p] = vfsUnpackF32(message, paramOffset)
					paramOffset = paramOffset + 4
				end
				if unitID ~= currentUnitID then
					if currentUnitID >= 0 then
						if apply then
							spGiveOrderArrayToUnit(currentUnitID, commands)
						end
						commands = {}
					end
					currentUnitID = unitID
				end
				commands[#commands + 1] = { cmdID, params, options }
				accepted = accepted + 1
			end
		end
		if currentUnitID >= 0 and apply then
			spGiveOrderArrayToUnit(currentUnitID, commands)
		end
		return "ok", count, accepted, emissionFrame
	end

	-- Direct mode: one sample per frame, sizes interleaved, prebuilt orders given between the marks.
	---@param arm AIBenchRelayArm
	---@param direct AIBenchDirectOrders
	local function giveDirectOrders(arm, direct, frame)
		local sample = direct.sample + 1
		direct.sample = sample
		local size = RELAY_SIZES[(sample - 1) % #RELAY_SIZES + 1]
		local commands = sample % 2 == 0 and direct.back or direct.out
		local unitIDs = direct.unitIDs
		for k = 1, size do
			local unitID = unitIDs[k] --[[@as integer]]
			if not spValidUnitID(unitID) then
				SendToUnsynced(RELAY_ACTION_RESULT, "unit lost", size, 0, frame, frame, arm.playerID)
				return
			end
		end
		SendToUnsynced(RELAY_ACTION_MARK)
		SendToUnsynced(RELAY_ACTION_MARK)
		for k = 1, size do
			local unitID = unitIDs[k] --[[@as integer]]
			spGiveOrderArrayToUnit(unitID, commands[k] --[[@as CreateCommand[] ]])
		end
		SendToUnsynced(RELAY_ACTION_RESULT, "ok", size, size, frame, frame, arm.playerID)
	end

	function gadget:RecvLuaMsg(message, playerID)
		if stringSub(message, 1, 4) ~= RELAY_MAGIC then
			return false
		end
		local version = #message >= RELAY_CONTROL_BYTES and vfsUnpackU8(message, 5)
		if version == RELAY_CONTROL_VERSION then
			handleControl(message, playerID)
			return true
		end
		local arm = armed
		if version ~= MESSAGE_VERSION or #message < HEADER_BYTES or not arm or playerID ~= arm.playerID then
			return true
		end
		if arm.direct then
			return true
		end
		-- two marks: their gap is the cost of one mark, which the result subtracts
		SendToUnsynced(RELAY_ACTION_MARK)
		SendToUnsynced(RELAY_ACTION_MARK)
		local status, count, accepted, emissionFrame = relayOrders(message, arm)
		SendToUnsynced(RELAY_ACTION_RESULT, status, count, accepted, emissionFrame, spGetGameFrame(), playerID)
		arm.remaining = arm.remaining - 1
		if arm.remaining <= 0 then
			disarm("done")
		end
		return true
	end

	function gadget:GameFrame(frame)
		local arm = armed
		if not arm then
			return
		end
		if frame > arm.expiryFrame then
			disarm("timeout")
			return
		end
		local direct = arm.direct
		if direct then
			giveDirectOrders(arm, direct, frame)
			arm.remaining = arm.remaining - 1
			if arm.remaining <= 0 then
				disarm("done")
			end
		end
	end

	function gadget:Initialize()
		gadgetHandler:RemoveCallIn("GameFrame")
	end

	function gadget:Shutdown()
		unhookReference()
	end

	return
end

-- Dormant until "/luarules aibench" from the local player: no per-frame callin is registered while idle.
-- One sample runs per Update, round-robin over the measures, so a run takes about 75 Updates and the
-- repetitions of a measure are spread over time instead of back to back. A sample repeats the
-- 10000-call block until it lasts MIN_TIMER_STEPS timer steps; the first sample calibrates the count.

local spGetTimerMicros = Spring.GetTimerMicros
local spDiffTimers = Spring.DiffTimers
local spEcho = Spring.Echo
local spGetAllUnits = Spring.GetAllUnits
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitVelocity = Spring.GetUnitVelocity
local spGetUnitLosState = Spring.GetUnitLosState
local spGetGroundHeight = Spring.GetGroundHeight
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spPos2BuildPos = Spring.Pos2BuildPos
local spTestBuildOrder = Spring.TestBuildOrder
local spValidUnitID = Spring.ValidUnitID
local vfsPackU8 = VFS.PackU8
local vfsPackU16 = VFS.PackU16
local vfsPackU32 = VFS.PackU32
local vfsPackS32 = VFS.PackS32
local vfsPackF32 = VFS.PackF32
local vfsUnpackU8 = VFS.UnpackU8
local vfsUnpackU16 = VFS.UnpackU16
local vfsUnpackS32 = VFS.UnpackS32
local vfsUnpackF32 = VFS.UnpackF32
local stringSub = string.sub
local tableConcat = table.concat
local mathFloor = math.floor

local CALLS = 10000
local REPETITIONS = 5
local MIN_UNITS = 20
local ORDERS_PER_MESSAGE = 100
local MESSAGES_PER_MEASURE = CALLS / ORDERS_PER_MESSAGE
local MOVE_PARAM_COUNT = 3
-- the codec measure never sends its messages; its magic differs from the relay's
local CODEC_MAGIC = "AIFw"
local LOG_PREFIX = "[AIBENCH] "
local JSON_PREFIX = "[AIBENCH-JSON] "
-- longer JSON is split into "[AIBENCH-JSON i/n]" lines; the infolog showed one line cut at 1425 bytes
local JSON_CHUNK_BYTES = 1000
-- a sample must last this many timer steps, so quantization stays under 1%
local MIN_TIMER_STEPS = 100
-- cap on 10000-call blocks per sample: the empty loop reaches it at a 256 us step (44 min of uptime)
local MAX_PASSES = 2048

---@class AIBenchMeasure
---@field name string
---@field measure fun(input: table, passes: integer): number milliseconds for one sample
---@field subtractLoop boolean the empty-loop cost is removed from the result
---@field perMessage boolean also reported per 100-order message
---@field averageResult number?
---@field passes integer 10000-call blocks per sample, 0 until calibrated
---@field samples number[] ns per operation

---@class AIBenchRun
---@field input table
---@field unitIDs integer[]
---@field unitCount integer
---@field measures AIBenchMeasure[]
---@field emptyLoop AIBenchMeasure
---@field timerType string
---@field timerResolutionUs number
---@field step integer

local run = nil ---@type AIBenchRun?

-- Halton points spread evenly over the map and are the same on every run. Recoil builds Lua with
-- LUA_NUMBER = float, where a 32-bit LCG collapses to a handful of values.
---@param index number
---@param base number
---@return number
local function halton(index, base)
	local result, fraction = 0.0, 1.0
	while index > 0 do
		fraction = fraction / base
		result = result + fraction * (index % base)
		index = mathFloor(index / base)
	end
	return result
end

-- Timers are userdata, yet the step DiffTimers can show doubles with process uptime like a float32 of
-- absolute microseconds: 4 us at 40 s, 256 us at 44 min (engine 2025.06.18).
local function timerResolutionUs()
	local startTimer = spGetTimerMicros()
	local now = startTimer
	while now == startTimer do
		now = spGetTimerMicros()
	end
	return spDiffTimers(now, startTimer, true, true) * 1000
end

local function elapsedMs(startTimer)
	return spDiffTimers(spGetTimerMicros(), startTimer, true, true)
end

-- Each measure runs its 10000-call block `passes` times in one timed sample.
local function measureEmptyLoop(_, passes)
	local startTimer = spGetTimerMicros()
	for _ = 1, passes do
		for _ = 1, CALLS do
		end
	end
	return elapsedMs(startTimer)
end

local function measureTableRead(input, passes)
	local units = input.units
	local value
	local startTimer = spGetTimerMicros()
	for _ = 1, passes do
		for i = 1, CALLS do
			value = units[i]
		end
	end
	local ms = elapsedMs(startTimer)
	input.sink = value
	return ms
end

local function measureUnitCall(input, passes, unitFunction)
	local units = input.units
	local startTimer = spGetTimerMicros()
	for _ = 1, passes do
		for i = 1, CALLS do
			unitFunction(units[i])
		end
	end
	return elapsedMs(startTimer)
end

local function measureUnitLosState(input, passes)
	local units = input.units
	local allyTeamID = input.allyTeamID
	local startTimer = spGetTimerMicros()
	for _ = 1, passes do
		for i = 1, CALLS do
			spGetUnitLosState(units[i], allyTeamID, true)
		end
	end
	return elapsedMs(startTimer)
end

local function measureGroundHeight(input, passes)
	local pointX, pointZ = input.pointX, input.pointZ
	local startTimer = spGetTimerMicros()
	for _ = 1, passes do
		for i = 1, CALLS do
			spGetGroundHeight(pointX[i], pointZ[i])
		end
	end
	return elapsedMs(startTimer)
end

local function measureUnitsInCylinder(input, passes, radius)
	local unitX, unitZ = input.unitX, input.unitZ
	local startTimer = spGetTimerMicros()
	for _ = 1, passes do
		for i = 1, CALLS do
			spGetUnitsInCylinder(unitX[i], unitZ[i], radius)
		end
	end
	return elapsedMs(startTimer)
end

local function measurePos2BuildPos(input, passes)
	local buildDefID = input.buildDefID
	local pointX, pointY, pointZ = input.pointX, input.pointY, input.pointZ
	local startTimer = spGetTimerMicros()
	for _ = 1, passes do
		for i = 1, CALLS do
			spPos2BuildPos(buildDefID, pointX[i], pointY[i], pointZ[i], 0)
		end
	end
	return elapsedMs(startTimer)
end

local function measureBuildTest(input, passes)
	local buildDefID = input.buildDefID
	local pointX, pointY, pointZ = input.pointX, input.pointY, input.pointZ
	local startTimer = spGetTimerMicros()
	for _ = 1, passes do
		for i = 1, CALLS do
			local buildX, buildY, buildZ = spPos2BuildPos(buildDefID, pointX[i], pointY[i], pointZ[i], 0)
			spTestBuildOrder(buildDefID, buildX, buildY, buildZ, 0)
		end
	end
	return elapsedMs(startTimer)
end

-- Move orders 1..count of `orders` as one message; `parts` is reused between calls.
local function encodeMessage(parts, magic, teamID, sequence, frame, orders, count)
	parts[1] = magic
	-- the engine's annotations only know the table form of the multi-value packers
	---@diagnostic disable-next-line: redundant-parameter
	parts[2] = vfsPackU8(MESSAGE_VERSION, teamID)
	---@diagnostic disable-next-line: redundant-parameter
	parts[3] = vfsPackU32(sequence, frame)
	parts[4] = vfsPackU16(count)
	local partCount = 4
	for k = 1, count do
		parts[partCount + 1] = vfsPackU16(orders.unitID[k])
		parts[partCount + 2] = vfsPackS32(CMD_MOVE)
		---@diagnostic disable-next-line: redundant-parameter
		parts[partCount + 3] = vfsPackU8(0, MOVE_PARAM_COUNT)
		---@diagnostic disable-next-line: redundant-parameter
		parts[partCount + 4] = vfsPackF32(orders.x[k], orders.y[k], orders.z[k])
		partCount = partCount + 4
	end
	return tableConcat(parts, "", 1, partCount)
end

-- Reads every order field into locals; returns what the round-trip check needs.
local function decodeMessage(message)
	if stringSub(message, 1, 4) ~= CODEC_MAGIC or vfsUnpackU8(message, 5) ~= MESSAGE_VERSION then
		return 0, 0, 0, 0
	end
	local count = vfsUnpackU16(message, 15)
	local offset = HEADER_BYTES + 1
	local unitSum, paramSum = 0, 0
	for _ = 1, count do
		local unitID = vfsUnpackU16(message, offset)
		local cmdID = vfsUnpackS32(message, offset + 2)
		local options = vfsUnpackU8(message, offset + 6)
		local paramCount = vfsUnpackU8(message, offset + 7)
		local paramOffset = offset + ORDER_FIXED_BYTES
		for _ = 1, paramCount do
			paramSum = paramSum + vfsUnpackF32(message, paramOffset)
			paramOffset = paramOffset + 4
		end
		unitSum = unitSum + unitID + cmdID - CMD_MOVE + options
		offset = paramOffset
	end
	return count, offset - 1, unitSum, paramSum
end

local function measureEncode(input, passes)
	local message
	local parts, teamID, frame, orders = input.parts, input.teamID, input.frame, input.orders
	local startTimer = spGetTimerMicros()
	for m = 1, MESSAGES_PER_MEASURE * passes do
		message = encodeMessage(parts, CODEC_MAGIC, teamID, m, frame, orders, ORDERS_PER_MESSAGE)
	end
	local ms = elapsedMs(startTimer)
	input.sink = message
	return ms
end

local function measureDecode(input, passes)
	local message = input.message
	local startTimer = spGetTimerMicros()
	for _ = 1, MESSAGES_PER_MEASURE * passes do
		decodeMessage(message)
	end
	return elapsedMs(startTimer)
end

local function checkRoundTrip(input)
	local message =
		encodeMessage(input.parts, CODEC_MAGIC, input.teamID, 1, input.frame, input.orders, ORDERS_PER_MESSAGE)
	local expectedBytes = HEADER_BYTES + ORDERS_PER_MESSAGE * (ORDER_FIXED_BYTES + 4 * MOVE_PARAM_COUNT)
	if #message ~= expectedBytes then
		return nil, string.format("message is %d bytes, expected %d", #message, expectedBytes)
	end
	local orders = input.orders
	local unitSum, paramSum = 0, 0
	for k = 1, ORDERS_PER_MESSAGE do
		unitSum = unitSum + orders.unitID[k]
		paramSum = paramSum + orders.x[k] + orders.y[k] + orders.z[k]
	end
	local count, endByte, decodedUnitSum, decodedParamSum = decodeMessage(message)
	-- F32 keeps about 7 significant digits; the coordinate sum gets a matching tolerance
	if
		count ~= ORDERS_PER_MESSAGE
		or endByte ~= expectedBytes
		or decodedUnitSum ~= unitSum
		or math.abs(decodedParamSum - paramSum) > 1e-3 * math.max(1, math.abs(paramSum))
	then
		return nil, "decoded message does not match the encoded orders"
	end
	return message
end

local function findBuildingDefID(unitIDs)
	for _, unitID in ipairs(unitIDs) do
		local unitDefID = spGetUnitDefID(unitID)
		local unitDef = unitDefID and UnitDefs[unitDefID] ---@type table?
		if unitDef and unitDef.customParams.iscommander then
			for _, buildDefID in ipairs(unitDef.buildOptions) do
				local buildDef = UnitDefs[buildDefID] ---@type table?
				if buildDef and buildDef.isBuilding and not (buildDef.extractsMetal > 0) then
					return buildDefID
				end
			end
		end
	end
	return nil
end

local function prepareInput(unitIDs)
	local unitCount = #unitIDs
	local mapCenterX, mapCenterZ = Game.mapSizeX / 2, Game.mapSizeZ / 2
	local input = {
		units = {},
		unitX = {},
		unitZ = {},
		pointX = {},
		pointY = {},
		pointZ = {},
		orders = { unitID = {}, x = {}, y = {}, z = {} },
		parts = {},
		allyTeamID = Spring.GetMyAllyTeamID(),
		teamID = Spring.GetMyTeamID(),
		frame = Spring.GetGameFrame(),
		buildDefID = findBuildingDefID(unitIDs),
	}
	for i = 1, CALLS do
		local unitID = unitIDs[(i - 1) % unitCount + 1]
		local x, _, z = spGetUnitPosition(unitID)
		input.units[i] = unitID
		input.unitX[i] = x or mapCenterX
		input.unitZ[i] = z or mapCenterZ
		local pointX = halton(i, 2) * Game.mapSizeX
		local pointZ = halton(i, 3) * Game.mapSizeZ
		input.pointX[i] = pointX
		input.pointY[i] = spGetGroundHeight(pointX, pointZ)
		input.pointZ[i] = pointZ
	end
	local orders = input.orders
	for k = 1, ORDERS_PER_MESSAGE do
		orders.unitID[k] = input.units[k]
		orders.x[k] = input.pointX[k]
		orders.y[k] = input.pointY[k]
		orders.z[k] = input.pointZ[k]
	end
	return input
end

local function averageCylinderCount(input, unitCount, radius)
	local centers = math.min(unitCount, CALLS)
	local total = 0
	for i = 1, centers do
		total = total + #spGetUnitsInCylinder(input.unitX[i], input.unitZ[i], radius)
	end
	return total / centers
end

-- kind "call": blocks of 10000 calls, empty-loop cost removed; "codec": blocks of 10000 orders in 100-order messages
---@param name string
---@param measure fun(input: table, passes: integer): number
---@param kind "baseline"|"call"|"codec"
---@param averageResult number?
---@return AIBenchMeasure
local function newMeasure(name, measure, kind, averageResult)
	return {
		name = name,
		measure = measure,
		subtractLoop = kind == "call",
		perMessage = kind == "codec",
		averageResult = averageResult,
		passes = 0,
		samples = {},
	}
end

-- Doubles the block count until one sample lasts 2 * MIN_TIMER_STEPS timer steps, then takes the sample.
---@param entry AIBenchMeasure
---@param input table
---@param resolutionUs number
---@return number ms
local function takeSample(entry, input, resolutionUs)
	if entry.passes == 0 then
		local passes = 1
		-- aim at twice the minimum: later samples can run faster than the calibrating one
		while passes < MAX_PASSES and entry.measure(input, passes) * 1000 < 2 * MIN_TIMER_STEPS * resolutionUs do
			passes = passes * 2
		end
		entry.passes = passes
	end
	return entry.measure(input, entry.passes)
end

---@return AIBenchMeasure[] measures
---@return AIBenchMeasure emptyLoop
local function buildMeasures(input, unitCount)
	local function unitCall(unitFunction)
		return function(_, passes)
			return measureUnitCall(input, passes, unitFunction)
		end
	end
	local function cylinder(radius)
		return function(_, passes)
			return measureUnitsInCylinder(input, passes, radius)
		end
	end
	local emptyLoop = newMeasure("EmptyLoop", measureEmptyLoop, "baseline")
	local measures = {
		emptyLoop,
		newMeasure("TableRead", measureTableRead, "call"),
		newMeasure("GetUnitPosition", unitCall(spGetUnitPosition), "call"),
		newMeasure("GetUnitHealth", unitCall(spGetUnitHealth), "call"),
		newMeasure("GetUnitDefID", unitCall(spGetUnitDefID), "call"),
		newMeasure("GetUnitTeam", unitCall(spGetUnitTeam), "call"),
		newMeasure("GetUnitVelocity", unitCall(spGetUnitVelocity), "call"),
		newMeasure("GetUnitLosState", measureUnitLosState, "call"),
		newMeasure("GetGroundHeight", measureGroundHeight, "call"),
		newMeasure("GetUnitsInCylinder500", cylinder(500), "call", averageCylinderCount(input, unitCount, 500)),
		newMeasure("GetUnitsInCylinder1500", cylinder(1500), "call", averageCylinderCount(input, unitCount, 1500)),
	}
	if input.buildDefID then
		measures[#measures + 1] = newMeasure("Pos2BuildPos", measurePos2BuildPos, "call")
		measures[#measures + 1] = newMeasure("Pos2BuildPos+TestBuildOrder", measureBuildTest, "call")
	end
	measures[#measures + 1] = newMeasure("EncodeMoveOrder", measureEncode, "codec")
	measures[#measures + 1] = newMeasure("DecodeMoveOrder", measureDecode, "codec")
	return measures, emptyLoop
end

---@param samples number[]
---@return number median
---@return number minimum
---@return number maximum
local function summarize(samples)
	local sorted = {}
	local minimum, maximum = math.huge, -math.huge
	for i, value in ipairs(samples) do
		sorted[i] = value
		minimum = math.min(minimum, value)
		maximum = math.max(maximum, value)
	end
	table.sort(sorted)
	local count = #sorted
	local middle = (count % 2 == 1) and sorted[(count + 1) / 2] or (sorted[count / 2] + sorted[count / 2 + 1]) / 2
	return middle, minimum, maximum
end

local function jsonText(text)
	return (string.gsub(tostring(text), '[%c"\\]', ""))
end

-- One line when short enough; otherwise "[AIBENCH-JSON i/n] " lines whose payloads concatenate to the JSON.
local function emitJson(json)
	local chunkCount = math.ceil(#json / JSON_CHUNK_BYTES)
	if chunkCount <= 1 then
		spEcho(JSON_PREFIX .. json)
		return
	end
	for i = 1, chunkCount do
		local first = (i - 1) * JSON_CHUNK_BYTES + 1
		spEcho(
			string.format(
				"[AIBENCH-JSON %d/%d] %s",
				i,
				chunkCount,
				stringSub(json, first, first + JSON_CHUNK_BYTES - 1)
			)
		)
	end
end

local function commonJsonFields()
	return string.format(
		'"engine":"%s","game":"%s","map":"%s"',
		jsonText(Engine.versionFull),
		jsonText(Game.gameName .. " " .. Game.gameVersion),
		jsonText(Game.mapName)
	)
end

---@param benchRun AIBenchRun
local function report(benchRun)
	local measures = benchRun.measures
	-- one baseline for median and min: subtracting min from min lets a noisy loop push the min above the median
	local emptyMedian = summarize(benchRun.emptyLoop.samples)
	local validAtEnd = 0
	for _, unitID in ipairs(benchRun.unitIDs) do
		if spValidUnitID(unitID) then
			validAtEnd = validAtEnd + 1
		end
	end

	local resolutionUs = benchRun.timerResolutionUs
	local coarse = {}
	local measureJson = {}
	local averageJson = {}
	for index, entry in ipairs(measures) do
		local rawMedian, rawMin, rawMax = summarize(entry.samples)
		local medianNs, minNs = rawMedian, rawMin
		if entry.subtractLoop then
			medianNs, minNs = rawMedian - emptyMedian, rawMin - emptyMedian
		end
		local line = string.format(
			"%s%-28s median %9.1f ns  min %9.1f ns  (raw median %9.1f, raw max %9.1f, %d x %d calls)",
			LOG_PREFIX,
			entry.name,
			medianNs,
			minNs,
			rawMedian,
			rawMax,
			entry.passes,
			CALLS
		)
		if entry.averageResult then
			averageJson[#averageJson + 1] = string.format('"%s":%.1f', entry.name, entry.averageResult)
			line = line .. string.format(", %.1f units returned on average", entry.averageResult)
		end
		if entry.perMessage then
			local usPerMessage = medianNs * ORDERS_PER_MESSAGE / 1000
			line = line .. string.format(", %.1f us per %d-order message", usPerMessage, ORDERS_PER_MESSAGE)
		end
		-- sample length in us = ns per call * calls per sample / 1000; MAX_PASSES can stop short of the target
		if rawMin * CALLS * entry.passes / 1000 < MIN_TIMER_STEPS * resolutionUs then
			coarse[#coarse + 1] = entry.name
		end
		measureJson[index] =
			string.format('"%s":[%.1f,%.1f,%.1f,%.1f,%d]', entry.name, medianNs, minNs, rawMedian, rawMax, entry.passes)
		spEcho(line)
	end
	if #coarse > 0 then
		spEcho(
			string.format(
				"%stimer step is %.0f us; samples under %d steps are imprecise: %s",
				LOG_PREFIX,
				resolutionUs,
				MIN_TIMER_STEPS,
				tableConcat(coarse, ", ")
			)
		)
	end

	if validAtEnd < benchRun.unitCount then
		spEcho(
			string.format(
				"%s%d of %d units died during the run; pause the game (/pause) for stable numbers",
				LOG_PREFIX,
				benchRun.unitCount - validAtEnd,
				benchRun.unitCount
			)
		)
	end

	local buildDef = UnitDefs[benchRun.input.buildDefID or -1]
	local _, _, paused = Spring.GetGameSpeed()
	-- Written by hand: Json.encode prints float noise (5.5999999).
	local json = string.format(
		'{"format":4,"mode":"calls",%s,"gameFrame":%d,"paused":%s,"units":%d,'
			.. '"unitsValidAtEnd":%d,"calls":%d,"repetitions":%d,"ordersPerMessage":%d,"messageBytes":%d,'
			.. '"buildingDef":%s,"timerType":"%s","timerResolutionUs":%.1f,'
			.. '"columns":["medianNs","minNs","rawMedianNs","rawMaxNs","passes"],"measures":{%s},'
			.. '"averageUnitsReturned":{%s}}',
		commonJsonFields(),
		benchRun.input.frame,
		tostring(paused == true),
		benchRun.unitCount,
		validAtEnd,
		CALLS,
		REPETITIONS,
		ORDERS_PER_MESSAGE,
		#benchRun.input.message,
		buildDef and ('"' .. jsonText(buildDef.name) .. '"') or "null",
		benchRun.timerType,
		resolutionUs,
		tableConcat(measureJson, ","),
		tableConcat(averageJson, ",")
	)
	emitJson(json)
end

--------------------------------------------------------------------------------
-- Relay test: four phases in a row, each one message (or one direct sample) per sim frame with the sizes
-- interleaved, timed between the synced half's marks.
--------------------------------------------------------------------------------

local RELAY_MESSAGES_PER_SIZE = 60
-- frames to wait for the arm reply, and past the last message for the last result
local RELAY_WAIT_FRAMES = 30 * 30
local RELAY_PHASES = {
	{ mode = RELAY_MODE_APPLY, key = "relayMove", label = "relay move" },
	{ mode = RELAY_MODE_DECODE, key = "decodeOnly", label = "decode only" },
	{ mode = RELAY_MODE_STOP, key = "relayStop", label = "relay stop" },
	{ mode = RELAY_MODE_DIRECT, key = "directMove", label = "direct move" },
}
-- engine cost of GiveOrderArrayToUnit alone, for A/B runs with LuaUI or gadgets switched off in between
local DIRECT_PHASES = {
	{ mode = RELAY_MODE_DIRECT, key = "directMove", label = "direct move" },
	{ mode = RELAY_MODE_DIRECT_STOP, key = "directStop", label = "direct stop" },
}

---@class AIBenchRelaySize
---@field workUs number[]
---@field markUs number[]
---@field latencyFrames number[]
---@field rejectedOrders integer
---@field rejectedMessages integer

---@class AIBenchRelayPhaseRun
---@field mode integer
---@field key string
---@field label string
---@field sizes table<integer, AIBenchRelaySize>

---@class AIBenchRelayRun
---@field label string
---@field pending boolean
---@field teamID integer
---@field teamUnits integer
---@field ordersOut table
---@field ordersBack table
---@field parts string[]
---@field total integer
---@field phases AIBenchRelayPhaseRun[]
---@field phase integer
---@field active AIBenchRelayPhaseRun
---@field sent integer
---@field received integer
---@field armed boolean
---@field deadlineFrame integer
---@field markCount integer
---@field firstMark any
---@field secondMark any
---@field lastRejection string?
---@field timerResolutionUs number

local relayRun = nil ---@type AIBenchRelayRun?
local refRun = nil ---@type AIBenchRefRun?
local gcRun = nil ---@type AIBenchGcRun?

-- GameFrame stays registered while any per-frame measure runs.
local function releaseGameFrame()
	if not (relayRun or refRun or gcRun) then
		gadgetHandler:RemoveCallIn("GameFrame")
	end
end

local function sendRelayControl(teamID, expected, mode)
	---@diagnostic disable-next-line: redundant-parameter
	local versionTeamAndMode = vfsPackU8(RELAY_CONTROL_VERSION, teamID, mode)
	Spring.SendLuaRulesMsg(RELAY_MAGIC .. versionTeamAndMode .. vfsPackU16(expected))
end

local function finishRelay(disarmSynced)
	local current = relayRun
	if disarmSynced and current and not current.pending then
		sendRelayControl(current.teamID, 0, current.active.mode)
	end
	relayRun = nil
	releaseGameFrame()
end

local function mean(values)
	local total = 0
	for _, value in ipairs(values) do
		total = total + value
	end
	return total / #values
end

---@param current AIBenchRelayRun
local function reportRelay(current)
	local markAll = {}
	local phaseJson = {}
	spEcho(
		string.format(
			"%srelay results [%s], team %d (%d units); us = microseconds per message, latency in frames",
			LOG_PREFIX,
			current.label,
			current.teamID,
			current.teamUnits
		)
	)
	for _, phase in ipairs(current.phases) do
		local sizes = phase.sizes
		local sizeJson = {}
		for _, size in ipairs(RELAY_SIZES) do
			local bucket = sizes[size]
			for _, value in ipairs(bucket.markUs) do
				markAll[#markAll + 1] = value
			end
			local samples = #bucket.workUs
			if samples == 0 then
				spEcho(string.format("%s%-11s %4d orders: no samples", LOG_PREFIX, phase.label, size))
				sizeJson[#sizeJson + 1] = string.format('"%d":[0]', size)
			else
				local meanUs = mean(bucket.workUs)
				local medianUs, minUs, maxUs = summarize(bucket.workUs)
				local latencyMedian, latencyMin, latencyMax = summarize(bucket.latencyFrames)
				local usPerOrder = meanUs / size
				spEcho(
					string.format(
						"%s%-11s %4d orders: mean %7.1f us, median %7.1f us, %.2f us per order "
							.. "(min %.1f, max %.1f, latency %d, %d samples, %d orders rejected)",
						LOG_PREFIX,
						phase.label,
						size,
						meanUs,
						medianUs,
						usPerOrder,
						minUs,
						maxUs,
						latencyMedian,
						samples,
						bucket.rejectedOrders
					)
				)
				sizeJson[#sizeJson + 1] = string.format(
					'"%d":[%d,%.1f,%.1f,%.1f,%.1f,%.3f,%d,%d,%d,%d,%d]',
					size,
					samples,
					meanUs,
					medianUs,
					minUs,
					maxUs,
					usPerOrder,
					latencyMedian,
					latencyMin,
					latencyMax,
					bucket.rejectedOrders,
					bucket.rejectedMessages
				)
			end
		end
		phaseJson[#phaseJson + 1] = string.format('"%s":{%s}', phase.key, tableConcat(sizeJson, ","))
	end
	local markUs = #markAll > 0 and mean(markAll) or 0
	spEcho(
		string.format(
			"%stimer step %.0f us: single samples are quantized, means are not biased; one mark costs %.1f us",
			LOG_PREFIX,
			current.timerResolutionUs,
			markUs
		)
	)
	if current.lastRejection then
		spEcho(LOG_PREFIX .. "last rejected message: " .. current.lastRejection)
	end
	emitJson(
		string.format(
			'{"format":3,"mode":"relay","label":"%s",%s,"gameFrame":%d,"teamID":%d,"teamUnits":%d,"messagesPerSize":%d,'
				.. '"timerResolutionUs":%.1f,"markUs":%.1f,"columns":["samples","meanUs","medianUs","minUs","maxUs",'
				.. '"usPerOrder","latencyMedian","latencyMin","latencyMax","rejectedOrders","rejectedMessages"],'
				.. '"phases":{%s}}',
			jsonText(current.label),
			commonJsonFields(),
			Spring.GetGameFrame(),
			current.teamID,
			current.teamUnits,
			RELAY_MESSAGES_PER_SIZE,
			current.timerResolutionUs,
			markUs,
			tableConcat(phaseJson, ",")
		)
	)
end

local function buildRelayOrders(teamUnitIDs, offset)
	local orders = { unitID = {}, x = {}, y = {}, z = {} }
	local unitCount = #teamUnitIDs
	for k = 1, RELAY_SIZES[#RELAY_SIZES] do
		local unitID = teamUnitIDs[(k - 1) % unitCount + 1]
		local x, y, z = spGetUnitPosition(unitID)
		orders.unitID[k] = unitID
		orders.x[k] = (x or Game.mapSizeX / 2) + offset
		orders.y[k] = y or 0
		orders.z[k] = z or Game.mapSizeZ / 2
	end
	return orders
end

-- Stop orders 1..count of `orders` as one message, with no parameters.
local function encodeStopMessage(parts, teamID, sequence, frame, orders, count)
	parts[1] = RELAY_MAGIC
	---@diagnostic disable-next-line: redundant-parameter
	parts[2] = vfsPackU8(MESSAGE_VERSION, teamID)
	---@diagnostic disable-next-line: redundant-parameter
	parts[3] = vfsPackU32(sequence, frame)
	parts[4] = vfsPackU16(count)
	local partCount = 4
	for k = 1, count do
		parts[partCount + 1] = vfsPackU16(orders.unitID[k])
		parts[partCount + 2] = vfsPackS32(CMD_STOP)
		---@diagnostic disable-next-line: redundant-parameter
		parts[partCount + 3] = vfsPackU8(0, 0)
		partCount = partCount + 3
	end
	return tableConcat(parts, "", 1, partCount)
end

-- Asks the synced half to arm the given phase; false when there is no such phase.
---@param current AIBenchRelayRun
---@return boolean
local function startRelayPhase(current, phaseIndex)
	local active = current.phases[phaseIndex]
	if not active then
		return false
	end
	current.phase = phaseIndex
	current.active = active
	current.sent = 0
	current.received = 0
	current.armed = false
	current.markCount = 0
	current.deadlineFrame = Spring.GetGameFrame() + RELAY_WAIT_FRAMES
	sendRelayControl(current.teamID, current.total, active.mode)
	return true
end

---@param phaseList table[] RELAY_PHASES or DIRECT_PHASES
---@param label string? tag for the results, such as the A/B case being run
local function startRelay(teamIDText, phaseList, label)
	local teamID = tonumber(teamIDText)
	if not teamID then
		spEcho(LOG_PREFIX .. "usage: /luarules aibench relay <teamID> [label] | direct <teamID> [label]")
		return
	end
	---@cast teamID integer
	if not Spring.IsCheatingEnabled() then
		spEcho(LOG_PREFIX .. "the relay test orders another team's units: turn on cheats (/cheat) first")
		return
	end
	local validTeam, _, _, isAI = Spring.GetTeamInfo(teamID, false)
	local teamUnitIDs = validTeam and isAI and Spring.GetTeamUnits(teamID)
	if not teamUnitIDs or #teamUnitIDs == 0 then
		spEcho(string.format("%steam %d is not an AI team with units", LOG_PREFIX, teamID))
		return
	end
	local largest = RELAY_SIZES[#RELAY_SIZES]
	if #teamUnitIDs < largest then
		spEcho(
			string.format(
				"%steam %d has %d units, so %d-order messages give several orders to a unit; "
					.. "/luarules give %d armpw %d adds more",
				LOG_PREFIX,
				teamID,
				#teamUnitIDs,
				largest,
				largest,
				teamID
			)
		)
	end
	local phases = {}
	local phaseLabels = {}
	for phaseIndex, phase in ipairs(phaseList) do
		phaseLabels[phaseIndex] = phase.label
		local sizes = {}
		for _, size in ipairs(RELAY_SIZES) do
			sizes[size] = { workUs = {}, markUs = {}, latencyFrames = {}, rejectedOrders = 0, rejectedMessages = 0 }
		end
		phases[phaseIndex] = { mode = phase.mode, key = phase.key, label = phase.label, sizes = sizes }
	end
	local _, _, paused = Spring.GetGameSpeed()
	local current = {
		label = label or "",
		pending = paused == true,
		teamID = teamID,
		teamUnits = #teamUnitIDs,
		ordersOut = buildRelayOrders(teamUnitIDs, RELAY_MOVE_OFFSET),
		ordersBack = buildRelayOrders(teamUnitIDs, -RELAY_MOVE_OFFSET),
		parts = {},
		total = RELAY_MESSAGES_PER_SIZE * #RELAY_SIZES,
		phases = phases,
		phase = 1,
		active = phases[1] --[[@as AIBenchRelayPhaseRun]],
		sent = 0,
		received = 0,
		armed = false,
		deadlineFrame = 0,
		markCount = 0,
		timerResolutionUs = timerResolutionUs(),
	}
	relayRun = current
	-- GameFrame does not run while paused, so a pending run starts on the first frame after unpausing
	if not current.pending then
		startRelayPhase(current, 1)
	end
	gadgetHandler:UpdateCallIn("GameFrame")
	spEcho(
		string.format(
			"%srelay [%s]: %d phases (%s) of %d samples of 1, 100 and 1000 orders to team %d (%d units), "
				.. "one per frame%s",
			LOG_PREFIX,
			current.label,
			#phaseList,
			tableConcat(phaseLabels, ", "),
			current.total,
			teamID,
			#teamUnitIDs,
			current.pending and "; starts when the game is unpaused" or ""
		)
	)
end

local function relayGameFrame(frame)
	local current = relayRun
	if not current then
		return
	end
	if current.pending then
		current.pending = false
		startRelayPhase(current, 1)
		return
	end
	if frame > current.deadlineFrame then
		spEcho(
			string.format(
				"%srelay: %s timed out with %d of %d results",
				LOG_PREFIX,
				current.active.label,
				current.received,
				current.total
			)
		)
		reportRelay(current)
		finishRelay(true)
		return
	end
	local mode = current.active.mode
	if not current.armed or current.sent >= current.total or mode >= RELAY_MODE_DIRECT then
		return
	end
	local sequence = current.sent + 1
	local size = RELAY_SIZES[(sequence - 1) % #RELAY_SIZES + 1]
	local orders = sequence % 2 == 0 and current.ordersBack or current.ordersOut
	local message ---@type string
	if mode == RELAY_MODE_STOP then
		message = encodeStopMessage(current.parts, current.teamID, sequence, frame, orders, size)
	else
		message = encodeMessage(current.parts, RELAY_MAGIC, current.teamID, sequence, frame, orders, size)
	end
	Spring.SendLuaRulesMsg(message)
	current.sent = sequence
end

local function onRelayMark()
	local now = spGetTimerMicros()
	local current = relayRun
	if not current or not current.armed then
		return
	end
	if current.markCount == 0 then
		current.firstMark = now
		current.markCount = 1
	else
		current.secondMark = now
		current.markCount = 2
	end
end

local function onRelayResult(_, status, count, accepted, emissionFrame, appliedFrame, playerID)
	local now = spGetTimerMicros()
	local current = relayRun
	if not current or playerID ~= Spring.GetLocalPlayerID() then
		return
	end
	local markCount = current.markCount
	current.markCount = 0
	current.received = current.received + 1
	local bucket = current.active.sizes[count]
	if bucket and status ~= "ok" then
		bucket.rejectedMessages = bucket.rejectedMessages + 1
		bucket.rejectedOrders = bucket.rejectedOrders + count
		current.lastRejection = status
	elseif bucket and markCount == 2 then
		local markUs = spDiffTimers(current.secondMark, current.firstMark, true, true) * 1000
		bucket.markUs[#bucket.markUs + 1] = markUs
		bucket.workUs[#bucket.workUs + 1] = spDiffTimers(now, current.secondMark, true, true) * 1000 - markUs
		bucket.latencyFrames[#bucket.latencyFrames + 1] = appliedFrame - emissionFrame
		bucket.rejectedOrders = bucket.rejectedOrders + count - accepted
	end
	if current.received < current.total then
		return
	end
	-- the synced half disarms itself after its last result, before the next arm request reaches it
	if not startRelayPhase(current, current.phase + 1) then
		reportRelay(current)
		finishRelay(false)
	end
end

local function onRelayState(_, state, detail, playerID)
	local current = relayRun
	if not current or playerID ~= Spring.GetLocalPlayerID() then
		return
	end
	if state == "armed" then
		current.armed = true
		current.deadlineFrame = Spring.GetGameFrame() + current.total + RELAY_WAIT_FRAMES
	elseif state == "refused" then
		spEcho(LOG_PREFIX .. "relay refused by the synced half: " .. tostring(detail))
		finishRelay(false)
	elseif state == "disarmed" and detail ~= "done" then
		spEcho(
			string.format(
				"%srelay disarmed (%s) during %s after %d results",
				LOG_PREFIX,
				tostring(detail),
				current.active.label,
				current.received
			)
		)
		reportRelay(current)
		finishRelay(false)
	end
end

--------------------------------------------------------------------------------
-- Reference AIs: per sim frame cost of each AI in the game, reported per 30 s window. Native AIs come
-- from the engine's per-AI profiler timer, SimpleAI from its own callins timed between synced marks.
--------------------------------------------------------------------------------

local REF_WINDOW_FRAMES = 30 * 30
local REF_DEFAULT_MINUTES = 15
local REF_TIMER_PREFIX = "AI::"
local REF_LUA_PREFIX = "Simple"

---@class AIBenchRefTrack
---@field name string
---@field kind string
---@field teamIDs integer[]
---@field timerName string?
---@field lastTotal number?
---@field samples number[] ms per frame in the current window; reused, only 1..count is live
---@field count integer
---@field rows string[]

---@class AIBenchRefRun
---@field endFrame integer
---@field tracks AIBenchRefTrack[]
---@field simple AIBenchRefTrack?
---@field hooked boolean
---@field calibrating boolean
---@field calibrationUs number
---@field calibrationPairs integer
---@field markUs number
---@field depth integer
---@field startTimer any
---@field frameUs number
---@field framePairs integer
---@field sorted number[]

local spGetProfilerTimeRecord = Spring.GetProfilerTimeRecord
local spGetTeamUnitCount = Spring.GetTeamUnitCount
local tableSort = table.sort

local function sendRefControl(expected)
	sendRelayControl(0, expected, RELAY_MODE_REF)
end

local function teamUnits(teamIDs)
	local total = 0
	for _, teamID in ipairs(teamIDs) do
		total = total + (spGetTeamUnitCount(teamID) or 0)
	end
	return total
end

local function allUnits()
	return teamUnits(Spring.GetTeamList() or {})
end

local function clockText(frame)
	local seconds = mathFloor(frame / Game.gameSpeed + 0.5)
	return string.format("%02d:%02d", mathFloor(seconds / 60), seconds % 60)
end

---@param track AIBenchRefTrack
local function pushRefSample(track, ms)
	local count = track.count + 1
	track.count = count
	track.samples[count] = ms
end

-- Mean, 99th percentile and maximum of samples[1..count]; `sorted` is scratch space reused between calls.
---@param samples number[]
---@param sorted number[]
---@return number mean
---@return number p99
---@return number maximum
local function frameStats(samples, count, sorted)
	if count == 0 then
		return 0, 0, 0
	end
	local total, maximum = 0.0, 0.0
	for i = 1, count do
		local value = samples[i] --[[@as number]]
		sorted[i] = value
		total = total + value
		if value > maximum then
			maximum = value
		end
	end
	for i = #sorted, count + 1, -1 do
		sorted[i] = nil
	end
	tableSort(sorted)
	return total / count, sorted[math.ceil(count * 0.99)] or maximum, maximum
end

---@param current AIBenchRefRun
---@param track AIBenchRefTrack
local function closeRefWindow(current, track, frame)
	local count = track.count
	if count == 0 then
		return
	end
	local meanMs, p99, maximum = frameStats(track.samples, count, current.sorted)
	local own = teamUnits(track.teamIDs)
	local everyone = allUnits()
	local usPerUnit = own > 0 and meanMs * 1000 / own or 0
	spEcho(
		string.format(
			"[AIBENCH-REF] %s %-22s mean %.3f ms, p99 %.3f, max %.3f over %d frames; own %d units, total %d; "
				.. "%.2f us per own unit",
			clockText(frame),
			track.name,
			meanMs,
			p99,
			maximum,
			count,
			own,
			everyone,
			usPerUnit
		)
	)
	track.rows[#track.rows + 1] = string.format(
		"[%.2f,%d,%d,%d,%.4f,%.4f,%.4f]",
		frame / (Game.gameSpeed * 60),
		count,
		own,
		everyone,
		meanMs,
		p99,
		maximum
	)
	track.count = 0
end

---@param current AIBenchRefRun
local function reportRef(current)
	local trackJson = {}
	for _, track in ipairs(current.tracks) do
		trackJson[#trackJson + 1] = string.format(
			'"%s":{"kind":"%s","timer":"%s","rows":[%s]}',
			jsonText(track.name),
			track.kind,
			jsonText(track.timerName or ""),
			tableConcat(track.rows, ",")
		)
	end
	emitJson(
		string.format(
			'{"format":1,"mode":"ref",%s,"gameFrame":%d,"windowFrames":%d,"markUs":%.2f,'
				.. '"columns":["minute","frames","ownUnits","totalUnits","meanMs","p99Ms","maxMs"],"tracks":{%s}}',
			commonJsonFields(),
			Spring.GetGameFrame(),
			REF_WINDOW_FRAMES,
			current.markUs,
			tableConcat(trackJson, ",")
		)
	)
end

local function finishRef(reason)
	local current = refRun
	if not current then
		return
	end
	local frame = Spring.GetGameFrame()
	for _, track in ipairs(current.tracks) do
		closeRefWindow(current, track, frame)
	end
	spEcho(string.format("[AIBENCH-REF] %s measure ended: %s", clockText(frame), reason))
	reportRef(current)
	if current.simple then
		sendRefControl(0)
	end
	refRun = nil
	releaseGameFrame()
end

local function newRefTrack(name, kind, teamIDs, timerName)
	return { name = name, kind = kind, teamIDs = teamIDs, timerName = timerName, samples = {}, count = 0, rows = {} }
end

-- Prints the profiler records once. GetProfilerTimeRecord(name, true) is not called: asking for frameData
-- crashed engine 2026.07.04 (SIGSEGV).
local function describeTimers(timerNames)
	spEcho(string.format("[AIBENCH-REF] %d profiler records: %s", #timerNames, tableConcat(timerNames, " | ")))
	local total, current, maxDt, timePct, peakPct = spGetProfilerTimeRecord("Sim", false)
	spEcho(
		string.format(
			'[AIBENCH-REF] GetProfilerTimeRecord("Sim", false): total %s, current %s, max_dt %s, time_pct %s, peak_pct %s',
			tostring(total),
			tostring(current),
			tostring(maxDt),
			tostring(timePct),
			tostring(peakPct)
		)
	)
end

-- The engine's per-AI timer of a team, "AI::{id=.. team=.. name=.. version=..}", when the profiler has one.
---@return string?
local function findAITimer(teamID)
	local wanted = "team=" .. teamID .. " "
	for _, name in ipairs(Spring.GetProfilerRecordNames() or {}) do
		if stringSub(name, 1, #REF_TIMER_PREFIX) == REF_TIMER_PREFIX and name:find(wanted, 1, true) then
			return name
		end
	end
	return nil
end

local function startRef(minutesText)
	local minutes = tonumber(minutesText) or REF_DEFAULT_MINUTES
	local endFrame = mathFloor(minutes * 60 * Game.gameSpeed)
	if endFrame <= Spring.GetGameFrame() then
		spEcho(string.format("[AIBENCH-REF] the game is already past minute %s", tostring(minutes)))
		return
	end
	describeTimers(Spring.GetProfilerRecordNames() or {})
	local tracks, simpleTeams = {}, {}
	for _, teamID in ipairs(Spring.GetTeamList() or {}) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		-- the stub types hasAI as a number; the engine returns a boolean
		---@diagnostic disable-next-line: unnecessary-if
		if isAI then
			local luaAI = Spring.GetTeamLuaAI(teamID) or ""
			if luaAI ~= "" then
				if stringSub(luaAI, 1, #REF_LUA_PREFIX) == REF_LUA_PREFIX then
					simpleTeams[#simpleTeams + 1] = teamID
				else
					spEcho(string.format("[AIBENCH-REF] team %d runs Lua AI %s, not measured", teamID, luaAI))
				end
			else
				local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
				local trackName = string.format("%s team %d", tostring(shortName or aiName or "AI"), teamID)
				local timerName = findAITimer(teamID)
				if not timerName then
					spEcho("[AIBENCH-REF] no profiler timer yet for " .. trackName .. "; looking again every window")
				end
				tracks[#tracks + 1] = newRefTrack(trackName, "native", { teamID }, timerName)
			end
		end
	end
	local simple = nil
	if #simpleTeams > 0 then
		simple = newRefTrack(REF_GADGET_NAME .. " teams " .. tableConcat(simpleTeams, ","), "gadget", simpleTeams)
		tracks[#tracks + 1] = simple
	end
	if #tracks == 0 then
		spEcho("[AIBENCH-REF] no AI to measure")
		return
	end
	refRun = {
		endFrame = endFrame,
		tracks = tracks,
		simple = simple,
		hooked = false,
		calibrating = false,
		calibrationUs = 0,
		calibrationPairs = 0,
		markUs = 0,
		depth = 0,
		frameUs = 0,
		framePairs = 0,
		sorted = {},
	}
	if simple then
		sendRefControl(1)
	end
	gadgetHandler:UpdateCallIn("GameFrame")
	spEcho(
		string.format(
			"[AIBENCH-REF] measuring %d AIs until %s, a line per AI every %d s of game time",
			#tracks,
			clockText(endFrame),
			REF_WINDOW_FRAMES / Game.gameSpeed
		)
	)
end

---@param current AIBenchRefRun
local function refGameFrame(current, frame)
	for _, track in ipairs(current.tracks) do
		if track.timerName then
			local total = spGetProfilerTimeRecord(track.timerName, false)
			if track.lastTotal and total then
				pushRefSample(track, total - track.lastTotal)
			end
			track.lastTotal = total
		end
	end
	local simple = current.simple
	if simple and current.hooked then
		pushRefSample(simple, (current.frameUs - current.framePairs * current.markUs) / 1000)
	end
	current.frameUs = 0
	current.framePairs = 0
	if frame % REF_WINDOW_FRAMES == 0 then
		for _, track in ipairs(current.tracks) do
			closeRefWindow(current, track, frame)
			if track.kind == "native" and not track.timerName then
				track.timerName = findAITimer(track.teamIDs[1])
				spEcho(
					string.format(
						"[AIBENCH-REF] %s %-22s %s",
						clockText(frame),
						track.name,
						track.timerName and ("timer found: " .. track.timerName) or "no profiler timer"
					)
				)
			end
		end
	end
	if frame >= current.endFrame then
		finishRef("reached " .. clockText(current.endFrame))
	end
end

local function onRefStart()
	local now = spGetTimerMicros()
	local current = refRun
	if not current then
		return
	end
	local depth = current.depth + 1
	current.depth = depth
	if depth == 1 then
		current.startTimer = now
	end
end

local function onRefEnd()
	local now = spGetTimerMicros()
	local current = refRun
	if not current or current.depth == 0 then
		return
	end
	local depth = current.depth - 1
	current.depth = depth
	if current.calibrating then
		current.calibrationUs = current.calibrationUs + spDiffTimers(now, current.startTimer, true, true) * 1000
		current.calibrationPairs = current.calibrationPairs + 1
		return
	end
	-- nested callins are inside the outer one's time; every pair's marks are taken off at frame end
	current.framePairs = current.framePairs + 1
	if depth == 0 then
		current.frameUs = current.frameUs + spDiffTimers(now, current.startTimer, true, true) * 1000
	end
end

local function onRefState(_, state, playerID, detail)
	local current = refRun
	if not current or playerID ~= Spring.GetLocalPlayerID() then
		return
	end
	if state == "calibrating" then
		current.calibrating = true
	elseif state == "hooked" then
		current.calibrating = false
		current.hooked = true
		current.depth = 0
		current.frameUs = 0
		current.framePairs = 0
		current.markUs = current.calibrationPairs > 0 and current.calibrationUs / current.calibrationPairs or 0
		spEcho(
			string.format(
				"[AIBENCH-REF] %s callins hooked; one timed call's marks cost %.2f us (%d calibration pairs, timer step %.0f us)",
				REF_GADGET_NAME,
				current.markUs,
				current.calibrationPairs,
				timerResolutionUs()
			)
		)
	elseif state == "refused" then
		spEcho("[AIBENCH-REF] " .. REF_GADGET_NAME .. " not measured: " .. tostring(detail))
		current.simple = nil
		for i = #current.tracks, 1, -1 do
			if current.tracks[i].kind == "gadget" then
				table.remove(current.tracks, i)
			end
		end
		if #current.tracks == 0 then
			finishRef("nothing left to measure")
		end
	end
end

--------------------------------------------------------------------------------
-- Garbage collection: the cost of this gadget's own GameFrame while it allocates like an AI, with and without
-- explicit collection, then single full collections over a heap filled on purpose. The engine's own GC steps
-- on unsynced Lua run outside that timer, so its profiler record is read alongside.
--------------------------------------------------------------------------------

local GC_FRAMES = 900
local GC_LIFETIME_FRAMES = 300
-- STAI called collectgarbage("collect") every 121 frames
local GC_COLLECT_INTERVAL = 121
local GC_HEAP_TARGETS_MB = { 50, 200, 500 }
local GC_FILL_KB_PER_FRAME = 25 * 1024
local GC_FILL_CHUNK = 10000
local GC_COLLECT_REPEATS = 5
local GC_ENGINE_TIMER = "Lua::CollectGarbage::Unsynced"
local GC_SCENARIOS = {
	{ key = "alloc0", tables = 0, collect = "none" },
	{ key = "alloc100", tables = 100, collect = "none" },
	{ key = "alloc1000", tables = 1000, collect = "none" },
	{ key = "alloc10000", tables = 10000, collect = "none" },
	{ key = "alloc1000-step0", tables = 1000, collect = "step" },
	{ key = "alloc1000-collect121", tables = 1000, collect = "collect121" },
}

---@class AIBenchGcRun
---@field scenario integer index in GC_SCENARIOS, then past it for the heap targets
---@field frame integer frames run in the current scenario
---@field buffers table[][] GC_LIFETIME_FRAMES batches of live tables
---@field samples number[]
---@field engineSamples number[]
---@field count integer
---@field sorted number[]
---@field engineTimer string?
---@field lastEngineTotal number?
---@field heapKB number[] gcinfo() at start, middle and end
---@field heap table[]?
---@field filling boolean
---@field note string?

local collectGarbage = collectgarbage
local gcInfo = gcinfo

local function newGcBuffers()
	local buffers = {}
	for slot = 1, GC_LIFETIME_FRAMES do
		buffers[slot] = {}
	end
	return buffers
end

---@param current AIBenchGcRun
local function resetGcSamples(current)
	current.frame = 0
	current.count = 0
	current.lastEngineTotal = nil
	current.heapKB = { gcInfo() }
	current.note = nil
end

---@param current AIBenchGcRun
---@return number? engineMs
local function readEngineGc(current)
	local name = current.engineTimer
	if not name then
		return nil
	end
	local total = spGetProfilerTimeRecord(name, false)
	local last = current.lastEngineTotal
	current.lastEngineTotal = total
	return last and total and total - last or nil
end

---@param current AIBenchGcRun
local function reportGcScenario(current, key, unit)
	local count = current.count
	local meanMs, p99Ms, maxMs = frameStats(current.samples, count, current.sorted)
	local engineCount = #current.engineSamples
	local engineMean, engineP99, engineMax = frameStats(current.engineSamples, engineCount, current.sorted)
	local heapKB = current.heapKB
	local stepUs = timerResolutionUs()
	spEcho(
		string.format(
			"[AIBENCH-GC] %-22s mean %.3f ms, p99 %.3f, max %.3f over %d %s; heap %d / %d / %d KB; "
				.. "engine GC %s; timer step %.0f us%s",
			key,
			meanMs,
			p99Ms,
			maxMs,
			count,
			unit,
			heapKB[1] or 0,
			heapKB[2] or 0,
			heapKB[3] or 0,
			engineCount > 0
					and string.format("mean %.3f ms, p99 %.3f, max %.3f per frame", engineMean, engineP99, engineMax)
				or "not read (" .. GC_ENGINE_TIMER .. " missing)",
			stepUs,
			current.note and ("; " .. current.note) or ""
		)
	)
	local engineJson = engineCount > 0
			and string.format('{"meanMs":%.4f,"p99Ms":%.4f,"maxMs":%.4f}', engineMean, engineP99, engineMax)
		or "null"
	emitJson(
		string.format(
			'{"format":1,"mode":"gc","scenario":"%s",%s,"gameFrame":%d,"samples":%d,"unit":"%s","meanMs":%.4f,'
				.. '"p99Ms":%.4f,"maxMs":%.4f,"heapKB":[%d,%d,%d],"engineGc":%s,"engineTimer":"%s",'
				.. '"timerStepUs":%.1f,"note":"%s"}',
			key,
			commonJsonFields(),
			Spring.GetGameFrame(),
			count,
			unit,
			meanMs,
			p99Ms,
			maxMs,
			heapKB[1] or 0,
			heapKB[2] or 0,
			heapKB[3] or 0,
			engineJson,
			jsonText(current.engineTimer or ""),
			stepUs,
			jsonText(current.note or "")
		)
	)
	for i = #current.engineSamples, 1, -1 do
		current.engineSamples[i] = nil
	end
end

local function finishGc(reason)
	if not gcRun then
		return
	end
	gcRun = nil
	collectGarbage("collect")
	spEcho("[AIBENCH-GC] measure ended: " .. reason)
	releaseGameFrame()
end

---@param current AIBenchGcRun
local function nextGcScenario(current)
	current.buffers = newGcBuffers()
	current.heap = nil
	collectGarbage("collect")
	current.scenario = current.scenario + 1
	current.filling = current.scenario > #GC_SCENARIOS
	resetGcSamples(current)
	if current.scenario > #GC_SCENARIOS + #GC_HEAP_TARGETS_MB then
		finishGc("all scenarios done")
	end
end

---@param current AIBenchGcRun
local function gcAllocFrame(current, scenario)
	local startTimer = spGetTimerMicros()
	local tables = scenario.tables
	local frame = current.frame
	if tables > 0 then
		local batch = current.buffers[frame % GC_LIFETIME_FRAMES + 1] --[[@as table]]
		for i = 1, tables do
			batch[i] = { x = i, y = i, z = i }
		end
	end
	local collect = scenario.collect
	if collect == "step" then
		collectGarbage("step", 0)
	elseif collect == "collect121" and frame % GC_COLLECT_INTERVAL == 0 then
		collectGarbage("collect")
	end
	local ms = spDiffTimers(spGetTimerMicros(), startTimer, true, true)
	local count = current.count + 1
	current.count = count
	current.samples[count] = ms
	frame = frame + 1
	current.frame = frame
	if frame == GC_FRAMES / 2 then
		current.heapKB[2] = gcInfo()
	elseif frame >= GC_FRAMES then
		current.heapKB[3] = gcInfo()
		reportGcScenario(current, scenario.key, "frames")
		nextGcScenario(current)
	end
end

-- Adds live tables until the heap grows by about kb, in chunks of GC_FILL_CHUNK.
local function fillHeap(heap, kb)
	local target = gcInfo() + kb
	while gcInfo() < target do
		local chunk = {}
		for i = 1, GC_FILL_CHUNK do
			chunk[i] = { x = i, y = i, z = i }
		end
		heap[#heap + 1] = chunk
	end
end

---@param current AIBenchGcRun
local function gcHeapFrame(current)
	local targetMB = GC_HEAP_TARGETS_MB[current.scenario - #GC_SCENARIOS]
	if not targetMB then
		return
	end
	local key = "collect" .. targetMB .. "MB"
	if current.filling then
		local heap = current.heap or {}
		current.heap = heap
		if gcInfo() >= targetMB * 1024 then
			current.filling = false
			current.heapKB[1] = gcInfo()
			return
		end
		local filled, err = pcall(fillHeap, heap, GC_FILL_KB_PER_FRAME)
		if not filled then
			current.filling = false
			current.heapKB[1] = gcInfo()
			current.note = string.format("filling stopped at %d KB: %s", gcInfo(), tostring(err))
		end
		return
	end
	local startTimer = spGetTimerMicros()
	collectGarbage("collect")
	local ms = spDiffTimers(spGetTimerMicros(), startTimer, true, true)
	local count = current.count + 1
	current.count = count
	current.samples[count] = ms
	if count == 1 then
		current.heapKB[2] = gcInfo()
	end
	if count >= GC_COLLECT_REPEATS then
		current.heapKB[3] = gcInfo()
		reportGcScenario(current, key, "collections")
		nextGcScenario(current)
	end
end

---@param current AIBenchGcRun
local function gcGameFrame(current)
	local engineMs = readEngineGc(current)
	if engineMs then
		current.engineSamples[#current.engineSamples + 1] = engineMs
	end
	local scenario = GC_SCENARIOS[current.scenario]
	local ok, err
	if scenario then
		ok, err = pcall(gcAllocFrame, current, scenario)
	else
		ok, err = pcall(gcHeapFrame, current)
	end
	if not ok and gcRun == current then
		current.note = "error: " .. tostring(err)
		current.heapKB[3] = gcInfo()
		local key = scenario and scenario.key
			or ("collect" .. tostring(GC_HEAP_TARGETS_MB[current.scenario - #GC_SCENARIOS]) .. "MB")
		reportGcScenario(current, key, scenario and "frames" or "collections")
		nextGcScenario(current)
	end
end

local function startGc()
	if not collectGarbage or not gcInfo then
		spEcho("[AIBENCH-GC] collectgarbage or gcinfo is missing in this Lua state")
		return
	end
	local engineTimer = nil
	for _, name in ipairs(Spring.GetProfilerRecordNames() or {}) do
		if name == GC_ENGINE_TIMER then
			engineTimer = name
		end
	end
	collectGarbage("collect")
	local current = {
		scenario = 1,
		frame = 0,
		buffers = newGcBuffers(),
		samples = {},
		engineSamples = {},
		count = 0,
		sorted = {},
		engineTimer = engineTimer,
		heapKB = {},
		filling = false,
	}
	resetGcSamples(current)
	gcRun = current
	gadgetHandler:UpdateCallIn("GameFrame")
	spEcho(
		string.format(
			"[AIBENCH-GC] %d allocation scenarios of %d frames, then collect over %s MB heaps; engine GC timer %s; "
				.. "timer step %.0f us; starts when the game runs",
			#GC_SCENARIOS,
			GC_FRAMES,
			tableConcat(GC_HEAP_TARGETS_MB, "/"),
			engineTimer or "missing",
			timerResolutionUs()
		)
	)
end

function gadget:GameFrame(frame)
	if relayRun then
		relayGameFrame(frame)
	end
	local current = refRun
	if current then
		refGameFrame(current, frame)
	end
	local gcCurrent = gcRun
	if gcCurrent then
		gcGameFrame(gcCurrent)
	end
end

local function finish()
	gadgetHandler:RemoveCallIn("Update")
	run = nil
end

function gadget:Update()
	local current = run
	if not current then
		return
	end
	local step = current.step
	local measureCount = #current.measures
	local entry = current.measures[(step - 1) % measureCount + 1]
	if not entry then
		finish()
		return
	end
	local measured, ms = pcall(takeSample, entry, current.input, current.timerResolutionUs)
	if not measured then
		Spring.Log(gadget:GetInfo().name, LOG.ERROR, entry.name .. ": " .. tostring(ms))
		finish()
		return
	end
	-- ms over passes * CALLS operations -> ns per operation
	entry.samples[#entry.samples + 1] = ms * 1000000 / (CALLS * entry.passes)
	current.step = step + 1
	if step >= measureCount * REPETITIONS then
		local ok, err = pcall(report, current)
		if not ok then
			Spring.Log(gadget:GetInfo().name, LOG.ERROR, err)
		end
		finish()
	end
end

local function aibench(_, _, words, playerID)
	if playerID ~= Spring.GetLocalPlayerID() then
		return
	end
	local busy = run or relayRun or refRun or gcRun
	if words[1] == "stop" then
		if run then
			finish()
		end
		if relayRun then
			finishRelay(true)
		end
		if refRun then
			finishRef("stopped")
		end
		if gcRun then
			finishGc("stopped")
		end
		spEcho(LOG_PREFIX .. (busy and "stopped" or "nothing to stop"))
		return true
	end
	if busy then
		spEcho(LOG_PREFIX .. "a measure is already running; /luarules aibench stop ends it")
		return true
	end
	if words[1] == "ref" then
		startRef(words[2])
		return true
	end
	if words[1] == "gc" then
		startGc()
		return true
	end
	if words[1] == "relay" then
		startRelay(words[2], RELAY_PHASES, words[3])
		return true
	end
	if words[1] == "direct" then
		startRelay(words[2], DIRECT_PHASES, words[3])
		return true
	end
	if words[1] then
		spEcho(
			LOG_PREFIX
				.. "unknown '"
				.. tostring(words[1])
				.. "'; usage: /luarules aibench [relay|direct <teamID> [label] | ref [minutes] | gc | stop]"
		)
		return true
	end
	local unitIDs = spGetAllUnits()
	if #unitIDs < MIN_UNITS then
		spEcho(
			string.format(
				"%sonly %d units on the map, at least %d are needed; wait a few minutes and retry",
				LOG_PREFIX,
				#unitIDs,
				MIN_UNITS
			)
		)
		return true
	end
	local input = prepareInput(unitIDs)
	local message, err = checkRoundTrip(input)
	if not message then
		Spring.Log(gadget:GetInfo().name, LOG.ERROR, "order codec check failed: " .. err)
		return true
	end
	input.message = message
	if not input.buildDefID then
		spEcho(LOG_PREFIX .. "no commander found, skipping Pos2BuildPos and TestBuildOrder")
	end
	local measures, emptyLoop = buildMeasures(input, #unitIDs)
	run = {
		input = input,
		unitIDs = unitIDs,
		unitCount = #unitIDs,
		measures = measures,
		emptyLoop = emptyLoop,
		timerType = type(spGetTimerMicros()),
		timerResolutionUs = timerResolutionUs(),
		step = 1,
	}
	spEcho(
		string.format(
			"%sstarting: %d units, %d measures x %d repetitions of at least %d calls, timer step %.0f us",
			LOG_PREFIX,
			#unitIDs,
			#measures,
			REPETITIONS,
			CALLS,
			run.timerResolutionUs
		)
	)
	gadgetHandler:UpdateCallIn("Update")
	return true
end

function gadget:Initialize()
	gadgetHandler:AddChatAction(
		"aibench",
		aibench,
		" [relay|direct <teamID> [label] | ref [minutes] | gc | stop] : engine reads, order relay, reference AIs"
	)
	gadgetHandler:AddSyncAction(RELAY_ACTION_MARK, onRelayMark)
	gadgetHandler:AddSyncAction(RELAY_ACTION_RESULT, onRelayResult)
	gadgetHandler:AddSyncAction(RELAY_ACTION_STATE, onRelayState)
	gadgetHandler:AddSyncAction(REF_ACTION_START, onRefStart)
	gadgetHandler:AddSyncAction(REF_ACTION_END, onRefEnd)
	gadgetHandler:AddSyncAction(REF_ACTION_STATE, onRefState)
	gadgetHandler:RemoveCallIn("Update")
	gadgetHandler:RemoveCallIn("GameFrame")
end

function gadget:Shutdown()
	if relayRun then
		finishRelay(true)
	end
	if refRun then
		finishRef("gadget shut down")
	end
	if gcRun then
		finishGc("gadget shut down")
	end
	gadgetHandler:RemoveChatAction("aibench")
	gadgetHandler:RemoveSyncAction(RELAY_ACTION_MARK)
	gadgetHandler:RemoveSyncAction(RELAY_ACTION_RESULT)
	gadgetHandler:RemoveSyncAction(RELAY_ACTION_STATE)
	gadgetHandler:RemoveSyncAction(REF_ACTION_START)
	gadgetHandler:RemoveSyncAction(REF_ACTION_END)
	gadgetHandler:RemoveSyncAction(REF_ACTION_STATE)
end
