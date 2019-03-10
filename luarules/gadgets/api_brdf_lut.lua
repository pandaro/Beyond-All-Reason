function gadget:GetInfo()
	return {
		name      = "BRDF LUT Generator",
		desc      = "Generates BRDF Lookup table for PBR shaders",
		author    = "ivand",
		date      = "2019",
		license   = "PD",
		layer     = -1,
		enabled   = true,
	}
end

if (not gadgetHandler:IsSyncedCode()) then --unsynced gadget
	local genLut

	local BRDFLUT_TEXDIM = 512 --512 is BRDF LUT texture resolution

	local function GetBrdfTexture()
		return genLut:GetTexture()
	end

	function gadget:DrawGenesis()
		if genLut then
			genLut:Execute(false)
			GG.GetBrdfTexture = GetBrdfTexture
		end
		gadgetHandler:RemoveCallIn("DrawGenesis")
	end

	function gadget:Initialize()
		local genLutClass = VFS.Include("Luarules/Gadgets/Include/GenBrdfLut.lua")
		if genLutClass then
			genLut = genLutClass(BRDFLUT_TEXDIM)
			if genLut then
				genLut:Initialize()
			end
		end
	end

	function gadget:Shutdown()
		if genLut then
			genLut:Finalize()
		end
	end
end

