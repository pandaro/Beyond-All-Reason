-- Runs test files inside the engine, synced and unsynced, while the test runner of BAR cannot run them
-- (see T4 in .ai-notes/handoff.md). Copied to luarules/gadgets/ by run_engine_tests.sh, never committed there.
--
-- A test file returns { test = function, setup = function?, cleanup = function?, skip = function? }, as for the
-- test runner. Every line starts with TAG; the last one of each side is "TAG SUMMARY <side>: ...".

local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Shard engine tests",
		desc = "Runs luaui/Tests/shard/ in synced and unsynced code",
		author = "Shard",
		date = "November 2026",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

local TAG = "[SHARD-ENGINE-TESTS]"
local TEST_DIR = "luaui/Tests/shard/"
-- run_engine_tests.sh replaces the next line with the requested files, or leaves it to run the whole folder
local REQUESTED_FILES = nil -- @REQUESTED_FILES@

local side = gadgetHandler:IsSyncedCode() and "synced" or "unsynced"

local function echo(text)
	Spring.Echo(TAG .. " " .. side .. " " .. text)
end

local function oneLine(value)
	return (string.gsub(tostring(value), "[\r\n]+", " | "))
end

-- Runs one test table; returns true, or false and the error.
local function runTest(testTable)
	if type(testTable) ~= "table" or type(testTable.test) ~= "function" then
		return false, "the file did not return a table with a test function"
	end
	if testTable.skip then
		local ok, skip = pcall(testTable.skip)
		if not ok then
			return false, "skip: " .. tostring(skip)
		end
		if skip then
			return "skipped"
		end
	end
	if testTable.setup then
		local ok, err = pcall(testTable.setup)
		if not ok then
			return false, "setup: " .. tostring(err)
		end
	end
	local ok, err = pcall(testTable.test)
	if testTable.cleanup then
		local cleanupOk, cleanupErr = pcall(testTable.cleanup)
		if ok and not cleanupOk then
			ok, err = false, "cleanup: " .. tostring(cleanupErr)
		end
	end
	return ok, err
end

local function runFile(path)
	local text = VFS.LoadFile(path)
	if text == nil then
		return false, "file not found"
	end
	local chunk, err = loadstring(text, path)
	if chunk == nil then
		return false, err
	end
	setfenv(chunk, setmetatable({}, { __index = getfenv(1) }))
	local loaded, testTable = pcall(chunk)
	if not loaded then
		return false, testTable
	end
	return runTest(testTable)
end

local files = REQUESTED_FILES
if files == nil then
	files = VFS.DirList(TEST_DIR, "*.lua")
	table.sort(files)
end

local passed, failed, skipped = 0, 0, 0
for _, path in ipairs(files) do
	local ok, err = runFile(path)
	if ok == "skipped" then
		skipped = skipped + 1
		echo("skipped " .. path)
	elseif ok then
		passed = passed + 1
		echo("ok " .. path)
	else
		failed = failed + 1
		echo("FAILED " .. path .. ": " .. oneLine(err))
	end
end

-- negative control: a failing test must be reported as failing
local controlOk = runTest({
	test = function()
		error("negative control")
	end,
})
local control = controlOk and "NOT DETECTED, the results above are not reliable" or "detected"

echo(string.format("SUMMARY %s: %d ok, %d failed, %d skipped; negative control %s", side, passed, failed, skipped, control))

return false
