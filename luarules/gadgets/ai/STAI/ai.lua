STAI = class(ShardAI)

STAI.legacyElection = false --only a priority above zero wins: a unit whose behaviours are all at zero has none active

-- the modules and the behaviours that run in turns, one a frame (shard_runtime/loader/scheduler.lua)
STAI.MScheduler = {
	"EcoHST",
	-- 	'OverviewHST',
	"LosHST",
	"TargetHST",
	"DamageHST",
	"ScoutHST",
	"AttackHST",
	"RaidHST",
	"BomberHST",
	"LabsHST",
}

STAI.BScheduler = {
	"BootBST",
	"CommanderBST",
	"BuildersBST",
	"EngineerBST",
	"LabsBST",
	"ScoutBST",
	"RaidBST",
	"AttackerBST",
	--'BomberBST',
	"ReclaimBST",
	"CleanerBST",
	"AntinukeBST",
	"NukeBST",
}

function STAI:Name()
	return "STAI"
end

function STAI:internalName()
	return "stai"
end

function STAI:test()
	for i, v in pairs(STAI) do
		Spring.Echo("H.I.V.E. ST AI module:", i, v)
	end
end
