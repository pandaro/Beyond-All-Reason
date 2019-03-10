return {
	-- Rework based on:
	--    https://github.com/lhog/spring-map-pbr
	--    https://github.com/lhog/spring-models-pbr
	vertex = VFS.LoadFile("Materials/Shaders/pbr.vert"),
	fragment = VFS.LoadFile("Materials/Shaders/pbr.frag"),

	uniformInt = {
		tex0 = 0,
		tex1 = 1,
		tex2 = 2,
		tex3 = 3,

		normalTex = 4,

		brdfLutTex = 5,

		shadowTex = 6,
		reflectionTex = 7,
	},
	uniformFloat = {
		--lightColor = {1.0, 1.0, 1.0},
		lightColor = {gl.GetSun("diffuse" ,"unit")},
		shadowDensity = {gl.GetSun("shadowDensity" ,"unit")},
	},
	uniformMatrix = {
	},
}