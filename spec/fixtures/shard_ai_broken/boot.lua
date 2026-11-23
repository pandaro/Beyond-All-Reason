---@diagnostic disable: undefined-global
-- An AI type that fails to load, for the loader specs and the engine tests.
if SpecLog then
	SpecLog[#SpecLog + 1] = { "BrokenBoot" }
end
error("broken boot")
