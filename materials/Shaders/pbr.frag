%%FRAGMENT_GLOBAL_NAMESPACE%%
#line 20002

/***********************************************************************/
// Definitions

#ifdef DEFERRED_MODE
	#define GBUFFER_NORMTEX_IDX 0
	#define GBUFFER_DIFFTEX_IDX 1
	#define GBUFFER_SPECTEX_IDX 2
	#define GBUFFER_EMITTEX_IDX 3
	#define GBUFFER_MISCTEX_IDX 4
#endif

#define NORM2SNORM(value) (value * 2.0 - 1.0)
#define SNORM2NORM(value) (value * 0.5 + 0.5)

/***********************************************************************/
// Struct definitions

struct MaterialInfo {
	vec4 baseColor;

	float emission;
	float occlusion;
	float specularF0;
	float roughness;
	float roughness4;
	float metalness;
};


//TODO review if all vectors here are in use
struct VectorDotsInfo {
	float NdotLu;			// cos angle between normal and light direction. Unclamped.
	float NdotL;			// cos angle between normal and light direction. Clamped.
	float NdotV;			// cos angle between normal and view direction
	float NdotH;			// cos angle between normal and half vector
	float LdotV;			// cos angle between light direction and view direction
	float LdotH;			// cos angle between light direction and half vector
	float VdotH;			// cos angle between view direction and half vector
};

/***********************************************************************/
// Consts

#if 1
	const float PI = acos(0.0) * 2.0;
#else
	const float PI = 3.14159265359;
#endif
const float PI2 = PI * 2.0;

const float MIN_ROUGHNESS = 0.04;
const float DEFAULT_SPECULAR_FO = 0.04;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

/***********************************************************************/
// Samplers

uniform sampler2D tex0;
uniform sampler2D tex1;
uniform sampler2D tex2;
uniform sampler2D tex3;

uniform sampler2D normalTex;

uniform sampler2D brdfLutTex;

#ifdef use_shadows
	uniform sampler2DShadow shadowTex;
	uniform float shadowDensity;
#endif

uniform samplerCube reflectionTex;


/***********************************************************************/
// Uniforms

//The api_custom_unit_shaders supplies these definitions:
uniform vec3 sunPos; //sent by engine or api_cus with worst possible name
#define lightDir sunPos // rename to not get confused

uniform int simFrame; //set by api_cus
uniform vec4 teamColor; //set by engine

uniform vec3 lightColor; //sent by shader material file (pbr.lua)


/***********************************************************************/
// Varyings

in Data {
	vec3 worldPos;
	vec3 cameraDir;
	vec2 texCoord;
	#ifdef use_shadows
		vec4 shadowTexCoord;
	#endif

	#ifdef DO_FLASHLIGHTS
		float flashLightIntensity;
	#endif

	#ifdef DO_NORMALMAPPING
		#ifdef HAS_TANGENTS
			mat3 worldTBN;
		#else
			vec3 worldNormal;
		#endif
	#else
		vec3 worldNormal;
	#endif
};

/***********************************************************************/
// Global variables

#ifdef HAS_TANGENTS
	#define worldNormal worldTBN[2]
#else
	mat3 worldTBN;
#endif

MaterialInfo matInfo;
VectorDotsInfo vdi;

vec3 baseDiffuseColor;
vec3 specularEnvironmentR0; // specularEnvironmentR0 = baseSpecularColor
#define baseSpecularColor specularEnvironmentR0;
vec3 specularEnvironmentR90;


/***********************************************************************/
// Hash functions


/***********************************************************************/
// Gamma forward and inverse correction procedures

//inspired by https://github.com/tobspr/GLSL-Color-Spaces/blob/master/ColorSpaces.inc.glsl
const vec3 SRGB_INVERSE_GAMMA = vec3(2.2);
const vec3 SRGB_GAMMA = vec3(1.0 / 2.2);
const vec3 SRGB_ALPHA = vec3(0.055);
const vec3 SRGB_MAGIC_NUMBER = vec3(12.92);
const vec3 SRGB_MAGIC_NUMBER_INV = vec3(1.0) / SRGB_MAGIC_NUMBER;

float FromSRGB(float srgbIn) {
	#ifdef DO_FASTGAMMACORRECTION
		float rgbOut = pow(srgbIn, SRGB_INVERSE_GAMMA.x);
	#else
		float bLess = step(0.04045, srgbIn);
		float rgbOut1 = srgbIn * SRGB_MAGIC_NUMBER_INV.x;
		float rgbOut2 = pow((srgbIn + SRGB_ALPHA.x) / (1.0 + SRGB_ALPHA.x), 2.4);
		float rgbOut = mix( rgbOut1, rgbOut2, bLess );
	#endif
	return rgbOut;
}

vec3 FromSRGB(vec3 srgbIn) {
	#ifdef DO_FASTGAMMACORRECTION
		vec3 rgbOut = pow(srgbIn.rgb, SRGB_INVERSE_GAMMA);
	#else
		vec3 bLess = step(vec3(0.04045), srgbIn.rgb);
		vec3 rgbOut1 = srgbIn.rgb * SRGB_MAGIC_NUMBER_INV;
		vec3 rgbOut2 = pow((srgbIn.rgb + SRGB_ALPHA) / (vec3(1.0) + SRGB_ALPHA), vec3(2.4));
		vec3 rgbOut = mix( rgbOut1, rgbOut2, bLess );
	#endif
	return rgbOut;
}

vec4 FromSRGB(vec4 srgbIn) {
	#ifdef DO_FASTGAMMACORRECTION
		vec3 rgbOut = pow(srgbIn.rgb, SRGB_INVERSE_GAMMA);
	#else
		vec3 bLess = step(vec3(0.04045), srgbIn.rgb);
		vec3 rgbOut1 = srgbIn.rgb * SRGB_MAGIC_NUMBER_INV;
		vec3 rgbOut2 = pow((srgbIn.rgb + SRGB_ALPHA) / (vec3(1.0) + SRGB_ALPHA), vec3(2.4));
		vec3 rgbOut = mix( rgbOut1, rgbOut2, bLess );
	#endif
	return vec4(rgbOut, srgbIn.a);
}

float ToSRGB(float rgbIn) {
	#ifdef DO_FASTGAMMACORRECTION
		float srgbOut = pow(rgbIn, SRGB_GAMMA.x);
	#else
		float bLess = step(0.0031308, rgbIn);
		float srgbOut1 = rgbIn * SRGB_MAGIC_NUMBER.x;
		float srgbOut2 = (1.0 + SRGB_ALPHA.x) * pow(rgbIn, 1.0/2.4) - SRGB_ALPHA.x;
		float srgbOut = mix( srgbOut1, srgbOut2, bLess );
	#endif
	return srgbOut;
}

vec3 ToSRGB(vec3 rgbIn) {
	#ifdef DO_FASTGAMMACORRECTION
		vec3 srgbOut = pow(rgbIn.rgb, SRGB_GAMMA);
	#else
		vec3 bLess = step(vec3(0.0031308), rgbIn.rgb);
		vec3 srgbOut1 = rgbIn.rgb * SRGB_MAGIC_NUMBER;
		vec3 srgbOut2 = (vec3(1.0) + SRGB_ALPHA) * pow(rgbIn.rgb, vec3(1.0/2.4)) - SRGB_ALPHA;
		vec3 srgbOut = mix( srgbOut1, srgbOut2, bLess );
	#endif
	return srgbOut;
}

vec4 ToSRGB(vec4 rgbIn) {
	#ifdef DO_FASTGAMMACORRECTION
		vec3 srgbOut = pow(rgbIn.rgb, SRGB_GAMMA);
	#else
		vec3 bLess = step(vec3(0.0031308), rgbIn.rgb);
		vec3 srgbOut1 = rgbIn.rgb * SRGB_MAGIC_NUMBER;
		vec3 srgbOut2 = (vec3(1.0) + SRGB_ALPHA) * pow(rgbIn.rgb, vec3(1.0/2.4)) - SRGB_ALPHA;
		vec3 srgbOut = mix( srgbOut1, srgbOut2, bLess );
	#endif
	return vec4(srgbOut, rgbIn.a);
}

/***********************************************************************/
// Forward and inverse tone mapping operators

vec3 ACESFilmicTM(in vec3 x) {
	float a = 2.51;
	float b = 0.03;
	float c = 2.43;
	float d = 0.59;
	float e = 0.14;
	return (x * (a * x + b)) / (x * (c * x + d) + e);
}

// https://twitter.com/jimhejl/status/633777619998130176
vec3 FilmicHejl2015(in vec3 x) {
    vec4 vh = vec4(x, 1.0); //1.0 is hardcoded whitepoint!
    vec4 va = 1.425 * vh + 0.05;
    vec4 vf = (vh * va + 0.004) / (vh * (va + 0.55) + 0.0491) - 0.0821;
    return vf.rgb / vf.www;
}

vec3 Uncharted2TM(in vec3 x) {
	const float A = 0.15;
	const float B = 0.50;
	const float C = 0.10;
	const float D = 0.20;
	const float E = 0.02;
	const float F = 0.30;
	const float W = 11.2;
	const float white = ((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F;

	x *= vec3(2.0); //exposure bias

	vec3 outColor = ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
	outColor /= white;

	return outColor;
}

vec3 FilmicTM(in vec3 x) {
	vec3 outColor = max(vec3(0.0), x - vec3(0.004));
	outColor = (outColor * (6.2 * outColor + 0.5)) / (outColor * (6.2 * outColor + 1.7) + 0.06);
	return FromSRGB(outColor); //sadly FilmicTM outputs gamma corrected colors, so need to reverse that effect
}

//https://mynameismjp.wordpress.com/2010/04/30/a-closer-look-at-tone-mapping/ (comments by STEVEM)
vec3 SteveMTM1(in vec3 x) {
	const float a = 10.0; /// Mid
	const float b = 0.3; /// Toe
	const float c = 0.5; /// Shoulder
	const float d = 1.5; /// Mid

	return (x * (a * x + b)) / (x * (a * x + c) + d);
}

vec3 SteveMTM2(in vec3 x) {
	const float a = 1.8; /// Mid
	const float b = 1.4; /// Toe
	const float c = 0.5; /// Shoulder
	const float d = 1.5; /// Mid

	return (x * (a * x + b)) / (x * (a * x + c) + d);
}

vec3 LumaReinhardTM(in vec3 x) {
	float luma = dot(x, LUMA);
	float toneMappedLuma = luma / (1.0 + luma);
	return x * vec3(toneMappedLuma / luma);
}

vec3 ReinhardTM(in vec3 x) {
	return x / (vec3(1.0) + x);
}

vec3 LogTM(vec3 c) {
	const float limit = 2.2;
	const float contrast = 0.35;

	c = log(c + 1.0) / log(limit + 1.0);
	c = clamp(c, 0.0, 1.0);

	c = mix(c, c * c * (3.0 - 2.0 * c), contrast);
	c = pow(c, vec3(1.05,0.9,1));

	return c;
}

vec3 RomBinDaHouseTM(vec3 c) {
	c = exp( -1.0 / ( 2.72 * c + 0.15 ) );
	return c;
}

vec3 ExpExpand(in vec3 x, in float cutoff, in float mul) {
	float xL = dot(x, LUMA);

	float cutEval = step(cutoff, xL);

	//float yL = (1.0 - cutEval) * xL + cutEval * (exp(mul * xL) - exp(mul * cutoff) + cutoff);
	float yL = mix(xL, exp(mul * xL) - exp(mul * cutoff) + cutoff, cutEval);
	return x * yL / xL;
}

/***********************************************************************/
// TBN calculation in fragment shader

#ifndef HAS_TANGENTS
	#if 1
	void CalcTBN() {
		vec3 posDx = dFdx(worldPos);
		vec3 posDy = dFdy(worldPos);

		vec2 texDx = dFdx(texCoord);
		vec2 texDy = dFdy(texCoord);

		vec3 worldTangent = (texDy.t * posDx - texDx.t * posDy) / (texDx.s * texDy.t - texDy.s * texDx.t);

		// TODO: figure out which one is right/better
		#if 1
			vec3 worldNormalN = normalize(worldNormal);
		#else
			vec3 worldNormalN = normalize(cross(posDx, posDy));
		#endif

		// Do Gramm-Schmidt re-ortogonalization
		#if 1
			worldTangent = normalize(worldTangent - worldNormalN * dot(worldNormalN, worldTangent));
		#else
			worldTangent = normalize(worldTangent);
		#endif

		//vec3 worldBitangent = normalize( cross(worldTangent, worldNormalN) );
		vec3 worldBitangent = normalize( cross(worldNormalN, worldTangent) );

		#if 0
			float handednessSign = sign(dot(cross(worldNormalN, worldTangent), worldBitangent));
			worldBitangent = worldBitangent * handednessSign;
		#endif

		worldTBN = mat3(worldTangent, worldBitangent, worldNormalN);
	}
	#else
	void CalcTBN() {
		vec3 N = normalize(worldNormal);
		// get edge vectors of the pixel triangle
		vec3 dp1 = dFdx( worldPos );
		vec3 dp2 = dFdy( worldPos );
		vec2 duv1 = dFdx( texCoord );
		vec2 duv2 = dFdy( texCoord );

		// solve the linear system
		vec3 dp2perp = cross( dp2, N );
		vec3 dp1perp = cross( N, dp1 );
		vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
		vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

		// construct a scale-invariant frame
		float invmax = inversesqrt( max( dot(T,T), dot(B,B) ) );
		worldTBN = mat3( T * invmax, B * invmax, N );
	}
	#endif
#endif

/***********************************************************************/
// Normal mapping function

vec3 GetWorldFragNormal() {
	#ifdef DO_NORMALMAPPING
		vec2 nTexCoord = texCoord;

		#ifdef NORMAL_VFLIP
			nTexCoord.y = 1.0 - nTexCoord.y;
		#endif

		vec3 normalMapVal = texture(normalTex, nTexCoord).xyz;
		normalMapVal = NORM2SNORM(normalMapVal);

		#ifdef NORMAL_RG
			normalMapVal.z = sqrt( clamp(1.0f - dot(normalMapVal.xy, normalMapVal.xy), 0.0, 1.0) );
		#endif

		#ifndef NORMAL_OPENGL
			normalMapVal.y *= -1.0;
		#endif

		vec3 worldFragNormal = worldTBN * normalMapVal;
	#else // undefined DO_NORMALMAPPING
		// don't do normal mapping, just pass worldNormal
		vec3 worldFragNormal = worldNormal;
	#endif

	return normalize(worldFragNormal);
}


/***********************************************************************/
// Scary PBR supplemental stuff, I collected from dozens of places


// Normal (Microfacet) Distribution function --------------------------------------
// Standard across every implementation so far
float D_GGX(float NdotH, float roughness4) {
	float denom = NdotH * NdotH * (roughness4 - 1.0) + 1.0;
	return roughness4/(PI * denom*denom);
}



// Geometric Shadowing (Occlusion) function --------------------------------------
#define PBR_SCHLICK_SMITH_GGX_THIN 1
#define PBR_SCHLICK_SMITH_GGX_THICK 2

#if (PBR_SCHLICK_SMITH_GGX == PBR_SCHLICK_SMITH_GGX_THIN)
	// Thinner, more concentrated lobe. Equation 4 of https://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_notes_v2.pdf
	// Same is used to generate BRDF LUT
	float G_SchlickSmithGGX(float NdotL, float NdotV, float roughness, float roughness4) {
		float k = roughness + 1.0;
		k = k * k / 8.0;
		float GL = NdotL / (NdotL * (1.0 - k) + k);
		float GV = NdotV / (NdotV * (1.0 - k) + k);
		return GL * GV;
	}
#elif (PBR_SCHLICK_SMITH_GGX == PBR_SCHLICK_SMITH_GGX_THICK)
	// Wider, more spread lobe. Used in Khronos reference PBR implementation
	float G_SchlickSmithGGX(float NdotL, float NdotV, float roughness, float roughness4) {
		float GL = 2.0 * NdotL / (NdotL + sqrt(roughness4 + (1.0 - roughness4) * (NdotL * NdotL)));
		float GV = 2.0 * NdotV / (NdotV + sqrt(roughness4 + (1.0 - roughness4) * (NdotV * NdotV)));
		return GL * GV;
	}
#endif

// Fresnel function ----------------------------------------------------
// Represent specular reflectivity
#define PBR_F_SCHLICK_KHRONOS 1
#define PBR_F_SCHLICK_SASCHA 2
#define PBR_F_SCHLICK_GOOGLE 3
#define PBR_F_SCHLICK_GAUSSIAN 4
#define PBR_F_COOK_TORRANCE 5

#if (PBR_F_SCHLICK == PBR_F_SCHLICK_GAUSSIAN)
	vec3 F_Schlick_Gaussian(float VdotX, vec3 R0, vec3 R90) {
		//Spherical Gaussian Approximation, Used in UE4(?)
		//Reference: Seb. Lagarde's Blog (seblagarde.wordpress.com)
		vec3 k = vec3(exp2((-5.55473 * VdotX - 6.98316) * VdotX));
		return R0 + (R90 - R0) * k;
	}
#elif (PBR_F_SCHLICK == PBR_F_COOK_TORRANCE)
	// https://github.com/AndreaMelle/unitypbr/blob/master/Assets/pbr.cginc
	vec3 F_CookTorrance(float VdotX, vec3 R0) {
		vec3 sqrtR0 = sqrt(R0);
		vec3 n = (1.0 + sqrtR0) / (1.0 - sqrtR0);
		vec3 g = sqrt(n * n + VdotX * VdotX - 1.0);

		vec3 part1 = (g - VdotX)/(g + VdotX);
		vec3 part2 = ((g + VdotX) * VdotX - 1.0f)/((g - VdotX) * VdotX + 1.0f);

		return max( vec3(0.0), 0.5 * part1 * part1 * (1.0 + part2 * part2) );
	}
#else
	vec3 F_Schlick(float VdotX, vec3 R0, vec3 R90) {
		return R0 + (R90 - R0) * pow( clamp(1.0 - VdotX, 0.0, 1.0), 5.0 );
	}

	vec3 F_Schlick(float VdotX, float R0, vec3 R90) {
		return R0 + (R90 - R0) * pow( clamp(1.0 - VdotX, 0.0, 1.0), 5.0 );
	}

	float F_Schlick(float VdotX, float R0, float R90) {
		return R0 + (R90 - R0) * pow( clamp(1.0 - VdotX, 0.0, 1.0), 5.0 );
	}

	vec3 F_Schlick(float VdotX, vec3 R0) {
		return R0 + (vec3(1.0) - R0) * pow( clamp(1.0 - VdotX, 0.0, 1.0), 5.0 );
	}

	vec3 F_Schlick(float VdotX, float R0) {
		return R0 + (vec3(1.0) - R0) * pow( clamp(1.0 - VdotX, 0.0, 1.0), 5.0 );
	}
	/*
	vec3 F_SchlickR(float cosTheta, vec3 F0, float roughness)
	{
		return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
	}
	*/
#endif



// Directional light Diffuse terms
#define PBR_BRDF_DIFFUSE_LAMBERT 1
#define PBR_BRDF_DIFFUSE_BURLEY_GOOGLE 2
#define PBR_BRDF_DIFFUSE_BURLEY_GODOT 3
#define PBR_BRDF_DIFFUSE_OREN_NAYAR_GODOT 4

#if (PBR_BRDF_DIFFUSE == PBR_BRDF_DIFFUSE_LAMBERT)
	vec3 Diffuse(vec3 diffColor, float roughness) {
		return diffColor / PI;
	}
#elif (PBR_BRDF_DIFFUSE == PBR_BRDF_DIFFUSE_BURLEY_GOOGLE)
	vec3 Diffuse(vec3 diffColor, float roughness) {
		float f90 = 0.5 + 2.0 * roughness * vdi.LdotH * vdi.LdotH;
		float lightScatter = F_Schlick(vdi.NdotL, 1.0, f90);
		float viewScatter  = F_Schlick(vdi.NdotV, 1.0, f90);
		return diffColor * lightScatter * viewScatter / PI;
	}
#elif (PBR_BRDF_DIFFUSE == PBR_BRDF_DIFFUSE_BURLEY_GODOT)
	vec3 Diffuse(vec3 diffColor, float roughness) {
			float FD90_minus_1 = 2.0 * vdi.LdotH * vdi.LdotH * roughness - 0.5;
			float FdV = 1.0 + FD90_minus_1 * pow(vdi.NdotV, 5.0);
			float FdL = 1.0 + FD90_minus_1 * pow(vdi.NdotL, 5.0);
			return (diffColor / PI) * FdV * FdL;
	}
#elif (PBR_BRDF_DIFFUSE == PBR_BRDF_DIFFUSE_OREN_NAYAR_GODOT)
	vec3 Diffuse(vec3 diffColor, float roughness) {
			float s = vdi.LdotV - vdi.NdotL * vdi.NdotV;
			float t = mix(1.0, max(vdi.NdotL, vdi.NdotV), step(0.0, s));

			float sigma2 = roughness * roughness; // TODO: this needs checking
			vec3 A = 1.0 + sigma2 * (-0.5 / (sigma2 + 0.33) + 0.17 * diffColor / (sigma2 + 0.13));
			float B = 0.45 * sigma2 / (sigma2 + 0.09);

			return diffColor * (A + vec3(B) * s / t) / PI;
	}
#endif


/***********************************************************************/
// Main PBR Methods

// Sets baseDiffuseColor, specularEnvironmentR0 = baseSpecularColor, specularEnvironmentR90
#define PBR_R90_METHOD_STD 1
#define PBR_R90_METHOD_GOOGLE 2

void FillInMaterialInfo() {
	vec4 tex0Texel = texture(tex0, texCoord); //RGB - base color, A - teamColor mix for now
	vec4 tex1Texel = texture(tex1, texCoord); //R - emission ,incl. flashlights, G - specular exp mult
	//vec4 tex2Texel = texture(tex2, texCoord);
	//vec4 tex3Texel = texture(tex3, texCoord);

	const float occlusion = 1.0;
	const float specularF0 = DEFAULT_SPECULAR_FO;

	#ifdef DO_GAMMACORRECTION
		vec4 baseColor = FromSRGB( tex0Texel );
	#else
		vec4 baseColor = tex0Texel;
	#endif

	float emission = tex1Texel.r;
	float roughness = tex1Texel.b;
	roughness = 0.0;
	roughness = fract(simFrame * 0.0125);
	float metalness = tex1Texel.g * 1.0;
	//metalness = 0.5;
	//metalness = fract(simFrame * 0.025);


	roughness = clamp(roughness, MIN_ROUGHNESS, 1.0);
	metalness = clamp(metalness, 0.0, 1.0);

	// additional vars
	float roughness2 = roughness * roughness;
	float roughness4 = roughness2 * roughness2; // roughness^4

	matInfo = MaterialInfo(
		baseColor, 			//matInfo.baseColor

		emission, 			//matInfo.emission
		occlusion, 			//matInfo.occlusion
		specularF0, 		//matInfo.occlusion
		roughness, 			//matInfo.roughness
		roughness4, 		//matInfo.roughness4
		metalness 			//matInfo.metalness
	);
}

void FillInVectorsInfo(vec3 thisLightDir, out vec3 N, out vec3 R) {
	//all vectors are defined in world space
	N = GetWorldFragNormal(); 	// Get world-space geometry or normal-mapped fragment normal

	vec3 V = normalize(cameraDir); 			// Vector from surface point to camera
	vec3 L = normalize(thisLightDir); 		// Vector from surface point to light
	vec3 H = normalize(L + V); 				// Half vector between both L and V

	R = -normalize(reflect(V, N));

	float NdotLu = dot(N, L);

	vdi = VectorDotsInfo(
		NdotLu, 							//vdi.NdotL
		clamp(NdotLu, 0.001, 1.0), 			//vdi.NdotL
		clamp(abs(dot(N, V)), 1e-3, 1.0), 	//vdi.NdotV
		clamp(dot(N, H), 0.0, 1.0), 		//vdi.NdotH
		clamp(dot(L, V), 0.0, 1.0), 		//vdi.LdotV
		clamp(dot(L, H), 0.0, 1.0),			//vdi.LdotH
		clamp(dot(V, H), 0.0, 1.0) 			//vdi.VdotH
	);
}

void GetBaseColors() {
	vec3 F0 = vec3(matInfo.specularF0);

	// break down the base color
	baseDiffuseColor = matInfo.baseColor.rgb * (vec3(1.0) - F0) * (1.0 - matInfo.metalness);
	specularEnvironmentR0 = mix(F0, matInfo.baseColor.rgb, vec3(matInfo.metalness)); // specularEnvironmentR0 = baseSpecularColor

	#if (PBR_R90_METHOD == PBR_R90_METHOD_STD)
		float maxReflectance = max(max(specularEnvironmentR0.r, specularEnvironmentR0.g), specularEnvironmentR0.b);
		float reflectance90 = clamp(maxReflectance / matInfo.specularF0, 0.0, 1.0); // bugged for low F0 values
		//float reflectance90 = clamp(maxReflectance * 25.0, 0.0, 1.0);
	#elif (PBR_R90_METHOD == PBR_R90_METHOD_GOOGLE)
		float reflectance90 = clamp(dot(F0, vec3(50.0 * 0.33)), 0.0, 1.0);
	#endif

	specularEnvironmentR90 = vec3(reflectance90);
}


// Calculates diffuse and specular contributions for a particular light
void GetDirectLightContribution(vec3 thisLightColor,
								out vec3 litDiffColor, out vec3 litSpecColor) {

	// D = Normal distribution (Distribution of the microfacets)
	float D = D_GGX(vdi.NdotH, matInfo.roughness4);

	// F = Fresnel factor (Reflectance depending on angle of incidence)
	#if (PBR_F_SCHLICK == PBR_F_SCHLICK_KHRONOS) // Khronos & learnopengl
		vec3 F = F_Schlick(vdi.VdotH, specularEnvironmentR0, specularEnvironmentR90);
	#elif (PBR_F_SCHLICK == PBR_F_SCHLICK_SASCHA) // SaschaWillems. Likely mistake
		vec3 F = F_Schlick(vdi.NdotV, specularEnvironmentR0, specularEnvironmentR90);
	#elif (PBR_F_SCHLICK == PBR_F_SCHLICK_GOOGLE) // Google, same as Khronos?
		vec3 F = F_Schlick(vdi.LdotH, specularEnvironmentR0, specularEnvironmentR90);
	#elif (PBR_F_SCHLICK == PBR_F_SCHLICK_GAUSSIAN)
		vec3 F = F_Schlick_Gaussian(vdi.LdotH, specularEnvironmentR0, specularEnvironmentR90);
	#elif (PBR_F_SCHLICK == PBR_F_COOK_TORRANCE)
		vec3 F = F_CookTorrance(vdi.LdotH, specularEnvironmentR0);
	#endif

	// G = Geometric shadowing term (Microfacets shadowing)
	float G = G_SchlickSmithGGX(vdi.NdotL, vdi.NdotV, matInfo.roughness, matInfo.roughness4);

	// Calculation of analytical lighting contribution
	vec3 lightDiffuseContrib = (1.0 - F) * Diffuse(baseDiffuseColor, matInfo.roughness);
	vec3 lightSpecContrib = F * G * D / (4.0 * vdi.NdotL * vdi.NdotV);

	// Obtain final intensity as reflectance (BRDF) scaled by the energy of the light (cosine law)
	litDiffColor = vdi.NdotL * thisLightColor * lightDiffuseContrib;
	litSpecColor = vdi.NdotL * thisLightColor * lightSpecContrib;
}

// Alternative calculation of LOD from Urho3D
//https://github.com/urho3d/Urho3D/blob/master/bin/CoreData/Shaders/GLSL/IBL.glsl

float GetMipFromRoughness(float roughness, float lodMax) {
	return (roughness * (lodMax + 1.0) - pow(roughness, 6.0) * 1.5);
}


// Image based Lighting Color Contribution
void GetIndirectLightContribution(vec3 N, vec3 R,
								out vec3 iblLitDiffColor, out vec3 iblLitSpecColor) {

	// Image Based Lighting
	ivec2 reflectionTexSize = textureSize(reflectionTex, 0);
	float reflectionTexMaxLOD = log2(float(max(reflectionTexSize.x, reflectionTexSize.y)));
	#if 0
		float specularLOD = reflectionTexMaxLOD * roughness;
	#else
		float specularLOD = GetMipFromRoughness(matInfo.roughness, reflectionTexMaxLOD);
	#endif

	#ifdef IBL_DIFFUSECOLOR_STATIC
		vec3 iblDiffuseLight = 0.2 * lightColor;
	#else
		// It's wrong to sample diffuse irradiance from reflection texture.
		// But alternative (convolution to irradiance) is too performance hungry (???)
		// Sample from "blurry" 16x16 texels mip level, so it looks more or less like irradiance
		vec3 iblDiffuseLight = texture(reflectionTex, N, reflectionTexMaxLOD - 4.0).rgb;
		/*
		iblDiffuseLight = IBL_GAMMACORRECTION(iblDiffuseLight);
		#if (IBL_INVERSE_TONEMAP == 1)
			float avgDLum = dot(LUMA, textureLod(reflectionTex, N, reflectionTexMaxLOD).rgb);
			iblDiffuseLight = ExpExpand(iblDiffuseLight, avgDLum, IBL_INVERSE_TONEMAP_MUL);
		#endif
		*/
	#endif

	#ifdef IBL_SPECULARCOLOR_STATIC
		vec3 iblSpecularLight = 0.5 * lightColor;
	#else
		// Get reflection with respect to surface roughness
		vec3 iblSpecularLight = texture(reflectionTex, R, specularLOD).rgb;
		/*
		iblSpecularLight = IBL_GAMMACORRECTION(iblSpecularLight);
		#if (IBL_INVERSE_TONEMAP == 1)
			float avgSLum = dot(LUMA, textureLod(reflectionTex, R, reflectionTexMaxLOD).rgb);
			iblSpecularLight = ExpExpand(iblSpecularLight, avgSLum, IBL_INVERSE_TONEMAP_MUL);
		#endif
		*/
	#endif

/*
	iblDiffuseLight = IBL_SCALE_DIFFUSE(iblDiffuseLight);
	iblSpecularLight = IBL_SCALE_SPECULAR(iblSpecularLight);
*/
	//sanitize Lights
	iblDiffuseLight = max(vec3(0.0), iblDiffuseLight);
	iblSpecularLight = max(vec3(0.0), iblSpecularLight);

	vec2 brdfLUT = textureLod(brdfLutTex, vec2(vdi.NdotV, 1.0 - matInfo.roughness), 0.0).xy;

	iblLitDiffColor = iblDiffuseLight * baseDiffuseColor;
	iblLitSpecColor = iblSpecularLight * (specularEnvironmentR0 * brdfLUT.x + brdfLUT.y);
}

#ifdef use_shadows
float GetShadowPCFGrid() {
	float shadow = 0.0;

	#if (SHADOW_SAMPLES == 1)
		shadow = textureProj( shadowTex, shadowTexCoord );
	#else
		const int ssHalf = int(floor(float(SHADOW_SAMPLES)/2.0));
		const float ssSum = float((ssHalf + 1) * (ssHalf + 1));

		for( int x = -ssHalf; x <= ssHalf; x++ ) {
			float wx = float(ssHalf - abs(x) + 1) / ssSum;
			for( int y = -ssHalf; y <= ssHalf; y++ ) {
				float wy = float(ssHalf - abs(y) + 1) / ssSum;
				shadow += wx * wy * textureProjOffset ( shadowTex, shadowTexCoord, ivec2(x, y) );
			}
		}
	#endif

	return mix(1.0, shadow, shadowDensity);
}
#endif


void main(void) {
	%%FRAGMENT_PRE_SHADING%%

	#ifndef HAS_TANGENTS
		CalcTBN();
	#endif

	FillInMaterialInfo();
	GetBaseColors();

	vec3 N;
	vec3 R;
	FillInVectorsInfo(lightDir, N, R);

	vec3 directLitDiffColor;
	vec3 directLitSpecColor;
	GetDirectLightContribution(lightColor, directLitDiffColor, directLitSpecColor);

	vec3 iblLitDiffColor;
	vec3 iblLitSpecColor;
	GetIndirectLightContribution(N, R, iblLitDiffColor, iblLitSpecColor);

	float nShadowMix = smoothstep(0.0, 0.5, vdi.NdotLu);
	float nShadow = mix(1.0, nShadowMix, shadowDensity);

	#ifdef use_shadows
		float gShadow = GetShadowPCFGrid();
	#else
		float gShadow = 1.0;
	#endif

	float oShadow = mix(1.0, matInfo.occlusion, shadowDensity);

	float shadow = min(min(nShadow, gShadow), oShadow);

	//TODO: figure out which one looks better
	#if 0
		gl_FragColor.rgb = (directLitDiffColor + iblLitDiffColor) * shadow + (directLitSpecColor + iblLitSpecColor);
	#else
		gl_FragColor.rgb = (directLitDiffColor + directLitSpecColor) + (iblLitDiffColor + iblLitSpecColor) * shadow;
	#endif

	#ifdef DO_FLASHLIGHTS
		gl_FragColor.rgb += matInfo.baseColor.rgb * matInfo.emission * flashLightIntensity;
	#else
		gl_FragColor.rgb += matInfo.baseColor.rgb * matInfo.emission;
	#endif

	//gl_FragColor.rgb = vec3(vdi.NdotL);
	//gl_FragColor.rgb = vec3(vdi.NdotV);
	//gl_FragColor.rgb = vec3(vdi.NdotH);
	//gl_FragColor.rgb = vec3(vdi.LdotV);
	//gl_FragColor.rgb = vec3(vdi.LdotH);
	//gl_FragColor.rgb = vec3(vdi.VdotH);
	//gl_FragColor.rgb = normalize(cameraDir);
	//gl_FragColor.rgb = normalize(lightDir);
	//gl_FragColor.rgb = lightColor;
	//gl_FragColor.rgb = baseDiffuseColor;
	//gl_FragColor.rgb = (directLitDiffColor + directLitSpecColor);
	//gl_FragColor.rgb = (iblLitDiffColor + iblLitSpecColor);
	//gl_FragColor.rgb = directLitSpecColor;
	//gl_FragColor.rgb = vec3(matInfo.roughness);
	//gl_FragColor.rgb = baseDiffuseColor;
	//gl_FragColor.rgb = baseSpecularColor;
	//gl_FragColor.rgb = worldTBN[0];
	//gl_FragColor.rgb = normalize(worldNormal);
	//gl_FragColor.rgb = GetWorldFragNormal();
	//gl_FragColor.rgb = texture(normalTex, texCoord).rgb;
	//gl_FragColor.rgb = vec3(matInfo.metalness);
	//gl_FragColor.rgb = texture(tex0, texCoord).rgb;
	//gl_FragColor.rg = texCoord;

	#ifdef DO_TONEMAPPING
		gl_FragColor.rgb = DO_TONEMAPPING(gl_FragColor.rgb);
	#endif

	#ifdef DO_GAMMACORRECTION
		gl_FragColor.rgb = ToSRGB(gl_FragColor.rgb);
	#endif

	gl_FragColor.rgb = mix(gl_FragColor.rgb, teamColor.rgb, matInfo.baseColor.a); //hack
	gl_FragColor.a = 1.0;

	//gl_FragColor.rgb = GetWorldFragNormal();

	%%FRAGMENT_POST_SHADING%%
}