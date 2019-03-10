local commonDefinitions = {
	"#version 150 compatibility",

	"#define GET_NORMALMAP",
	"#define GET_FLASHLIGHTS",
	"#define HAS_TANGENTS", -- undefine to visually verify TBN correctness, but don't use in production

	"#define NORMAL_OPENGL", -- https://polycount.com/discussion/147156/is-it-y-or-y-for-normal-maps
	--"define NORMAL_RG",
	--"define NORMAL_VFLIP",

	--"#define FAST_GAMMA",

	"#define PBR_SCHLICK_SMITH_GGX PBR_SCHLICK_SMITH_GGX_THIN",
	"#define PBR_F_SCHLICK PBR_F_SCHLICK_KHRONOS",
	"#define PBR_R90_METHOD PBR_R90_METHOD_GOOGLE",
	"#define PBR_BRDF_DIFFUSE PBR_BRDF_DIFFUSE_LAMBERT",
}

local forwardShaderDefs = Spring.Utilities.MergeTable(commonDefinitions, {}, true)
local deferredShaderDefs = Spring.Utilities.MergeTable(commonDefinitions, {"#define DEFERRED_MODE"}, true)

local materials = {
	s3oPBR = {
		shaderDefinitions = forwardShaderDefs,
		deferredDefinitions = deferredShaderDefs,

		shader    = VFS.Include("materials/Shaders/pbr.lua"),
		deferred  = VFS.Include("materials/Shaders/pbr.lua"),
		usecamera = false,
		culling   = GL.BACK,
		predl  = nil,
		postdl = nil,
		texunits  = {
			[0] = '%%UNITDEFID:0',
			[1] = '%%UNITDEFID:1',
			--[2] = '%TEX2',
			--[3] = '%TEX3',

			[4] = '%NORMALTEX',

			[5] = '%BRDFLUT',

			[6] = '$shadow',
			[7] = '$reflection',
		},
		-- uniforms = {
		-- }
		--DrawUnit = DrawUnit,
	},
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local brdfLutTex = GG.GetBrdfTexture()
local unitMaterials = {}

for i=1,#UnitDefs do
	local udef = UnitDefs[i]

	if udef.customParams.normaltex and VFS.FileExists(udef.customParams.normaltex) then
		unitMaterials[udef.name] = {
			"s3oPBR",
			NORMALTEX = udef.customParams.normaltex,
			BRDFLUT = brdfLutTex,
		}
		--Spring.Echo('normalmapped',udef.name)
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--return {}, {}
return materials, unitMaterials

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
