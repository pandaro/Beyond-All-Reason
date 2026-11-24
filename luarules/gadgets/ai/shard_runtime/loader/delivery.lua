-- Calls from the loader into the AI objects (global, ally team and team), on the hosting client. Unsynced.
--
-- Every call goes through Call: Prepare() and then the method, in xpcall, so that an error stops only that
-- call. Errors are told apart by object, call-in and message (the first line, with file and line): the first
-- time with its traceback, then only counted; WriteErrorSummary lists them all once at the end.
--
-- An event reaches an object only when one of its modules wants it (ShardAI:WantsEvent), global -> ally team ->
-- team. Provisional, as the old loader did: every object whose modules want Update() runs it every frame, and a
-- unit event reaches every object, whether or not its ally team can see the unit; only the sight events (LOS and
-- radar) go to the ally objects of the ally team concerned, and to every AI.

local spEcho = Spring.Echo
local spGetGameFrame = Spring.GetGameFrame
local traceback = debug and debug.traceback

local errorsByKey = {} -- "<object>|<call-in>|<message>" -> error record
local errorList = {} ---@type table[] error records, in the order they first happened
local errorSummaryWritten = false
local catchUpTargets = nil -- while catching up, only these objects hear the events

-- the call being made, in upvalues rather than a closure so that a call allocates nothing
local callTarget ---@type any
local callName ---@type any
local callA, callB, callC, callD

-- errors ------------------------------------------------------------------------------------------------

local function ObjectLabel(target)
	local scope = target:Scope()
	if scope == "ally" then
		return tostring(target.fullname) .. " ally team " .. tostring(target.allyId)
	elseif scope == "global" then
		return tostring(target.fullname) .. " global"
	end
	return tostring(target.fullname) .. " team " .. tostring(target.id)
end

local function ReportError(target, name, err)
	local text = tostring(err)
	local label = ObjectLabel(target)
	local message = string.match(text, "^[^\n]*")
	local key = label .. "|" .. name .. "|" .. message
	local frame = spGetGameFrame()
	local record = errorsByKey[key]
	if record ~= nil then
		record.count = record.count + 1
		record.last = frame
		return
	end
	record = { label = label, callIn = name, message = message, count = 1, first = frame, last = frame }
	errorsByKey[key] = record
	errorList[#errorList + 1] = record
	spEcho("[AI Loader] error in " .. label .. ", " .. name .. ": " .. text)
end

--- Lists every error of the game once; later calls write nothing
local function WriteErrorSummary()
	if errorSummaryWritten then
		return
	end
	errorSummaryWritten = true
	if errorList[1] == nil then
		return
	end
	spEcho("[AI Loader] errors in this game, " .. #errorList .. " different:")
	for i = 1, #errorList do
		local record = errorList[i] --[[@as table]]
		spEcho(
			string.format(
				"[AI Loader] %s, %s: %d times, frames %d to %d: %s",
				record.label,
				record.callIn,
				record.count,
				record.first,
				record.last,
				record.message
			)
		)
	end
end

local function WithTraceback(err)
	---@diagnostic disable-next-line: unnecessary-if
	if traceback then
		return traceback(tostring(err), 2)
	end
	return tostring(err)
end

-- calls -------------------------------------------------------------------------------------------------

local function ProtectedCall()
	callTarget:Prepare()
	if callName ~= "Prepare" then
		callTarget[callName](callTarget, callA, callB, callC, callD)
	end
end

--- Prepare() and then target[name](...): an error is written and stops only this call
---@return boolean ok
local function Call(target, name, a, b, c, d)
	local savedTarget, savedName, savedA, savedB, savedC, savedD = callTarget, callName, callA, callB, callC, callD
	callTarget, callName, callA, callB, callC, callD = target, name, a, b, c, d
	local ok, err = xpcall(ProtectedCall, WithTraceback)
	callTarget, callName, callA, callB, callC, callD = savedTarget, savedName, savedA, savedB, savedC, savedD
	if not ok then
		ReportError(target, name, err)
	end
	return ok
end

-- whether a module of the object wants the event; an object not initialised yet is called, and Prepare() runs Init()
local function Wants(target, name)
	return target:WantsEvent(name)
end

local function UpdateObject(target)
	if Wants(target, "Update") then
		Call(target, "Update")
	end
end

-- event delivery ------------------------------------------------------------------------------------------

local function SetCatchUpTargets(targets)
	catchUpTargets = targets
end

local function Deliver(target, name, a, b, c, d)
	if catchUpTargets ~= nil and catchUpTargets[target] == nil then
		return
	end
	if Wants(target, name) then
		Call(target, name, a, b, c, d)
	end
end

local function DeliverToShared(name, a, b, c, d)
	local globals = Shard.globals
	for i = 1, #globals do
		Deliver(globals[i], name, a, b, c, d)
	end
	for _, allies in pairs(Shard.alliesByAllyID) do
		for i = 1, #allies do
			Deliver(allies[i], name, a, b, c, d)
		end
	end
end

local function DeliverToAIs(name, a, b, c, d)
	local AIs = Shard.AIs
	for i = 1, #AIs do
		Deliver(AIs[i], name, a, b, c, d)
	end
end

--- Among the AIs only the owner of the unit, as the old loader did for UnitCreated: STAI's modules take
--- UnitCreated for a unit of their own team (BuildingsHST blocks the ground of any structure it hears of)
local function DeliverToOwner(teamID, name, a, b, c, d)
	local thisAI = Shard.AIsByTeamID[teamID]
	if thisAI ~= nil then
		Deliver(thisAI, name, a, b, c, d)
	end
end

local function DeliverToAll(name, a, b, c, d)
	DeliverToShared(name, a, b, c, d)
	DeliverToAIs(name, a, b, c, d)
end

--- The ShardAlly objects of the ally team that sees or loses the unit, and every AI
local function DeliverSight(name, unitID, unitTeam, allyTeam, unitDefID)
	local allies = Shard.alliesByAllyID[allyTeam]
	if allies ~= nil then
		for i = 1, #allies do
			Deliver(allies[i], name, unitID, unitTeam, allyTeam, unitDefID)
		end
	end
	DeliverToAIs(name, unitID, unitTeam, allyTeam, unitDefID)
end

-- every object ----------------------------------------------------------------------------------------------

--- Update() of every object, global -> ally team -> team
local function UpdateAll()
	local globals = Shard.globals
	for i = 1, #globals do
		UpdateObject(globals[i])
	end
	for _, allies in pairs(Shard.alliesByAllyID) do
		for i = 1, #allies do
			UpdateObject(allies[i])
		end
	end
	local AIs = Shard.AIs
	for i = 1, #AIs do
		UpdateObject(AIs[i])
	end
end

local function EndGameObject(target)
	if Wants(target, "GameEnd") then
		Call(target, "GameEnd")
	end
end

--- GameEnd() of every object, team -> ally team -> global
local function EndGameAll()
	for _, thisAI in ipairs(Shard.AIs) do
		EndGameObject(thisAI)
	end
	for _, allies in pairs(Shard.alliesByAllyID) do
		for _, ally in ipairs(allies) do
			EndGameObject(ally)
		end
	end
	for _, global in ipairs(Shard.globals) do
		EndGameObject(global)
	end
end

return {
	Call = Call,
	WithTraceback = WithTraceback,
	WriteErrorSummary = WriteErrorSummary,
	SetCatchUpTargets = SetCatchUpTargets,
	Deliver = Deliver,
	DeliverToShared = DeliverToShared,
	DeliverToAIs = DeliverToAIs,
	DeliverToOwner = DeliverToOwner,
	DeliverToAll = DeliverToAll,
	DeliverSight = DeliverSight,
	UpdateAll = UpdateAll,
	EndGameAll = EndGameAll,
}
