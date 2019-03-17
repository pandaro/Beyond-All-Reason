local commonDefinitions = {
	"#version 150 compatibility",

	"#define DO_FLASHLIGHTS",
	"#define DO_NORMALMAPPING", --disable TBN normal mapping from normal texture
	"#define HAS_TANGENTS", -- undefine to visually verify TBN correctness, but don't use in production

	"#define NORMAL_OPENGL", -- https://polycount.com/discussion/147156/is-it-y-or-y-for-normal-maps
	--"define NORMAL_RG",
	--"define NORMAL_VFLIP",
	
	"#define SHADOW_SAMPLES 6",

	"#define DO_GAMMACORRECTION",
	--"#define DO_FASTGAMMACORRECTION",
	"#define DO_TONEMAPPING(val) FilmicTM(val)",

	"#define IBL_DIFFUSECOLOR_STATIC", -- take IBL diffuse color from sun light color
	--"#define IBL_SPECULARCOLOR_STATIC", -- take IBL specular color from sun light color

	"#define PBR_SCHLICK_SMITH_GGX PBR_SCHLICK_SMITH_GGX_THICK",
	"#define PBR_F_SCHLICK PBR_F_SCHLICK_KHRONOS",
	"#define PBR_R90_METHOD PBR_R90_METHOD_GOOGLE",
	"#define PBR_BRDF_DIFFUSE PBR_BRDF_DIFFUSE_LAMBERT",
}

local function SunChanged(curShader)
	gl.Uniform(gl.GetUniformLocation(curShader, "shadowDensity"), gl.GetSun("shadowDensity" ,"unit"))

	gl.Uniform(gl.GetUniformLocation(curShader, "sunDiffuse"), gl.GetSun("diffuse" ,"unit"))
end

local forwardShaderDefs = Spring.Utilities.MergeTable(commonDefinitions, {}, true)
local deferredShaderDefs = Spring.Utilities.MergeTable(commonDefinitions, {"#define DEFERRED_MODE"}, true)

local materials = {
	pbrS3O = {
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
		SunChanged = SunChanged,
	},
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local brdfLutTex = GG.GetBrdfTexture()
local unitMaterials = {}

for i=1,#UnitDefs do
	local udef = UnitDefs[i]

	if udef.customParams.normaltex
		and udef.customParams.pbr
		and VFS.FileExists(udef.customParams.normaltex) then

		unitMaterials[udef.name] = {
			"pbrS3O",
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
