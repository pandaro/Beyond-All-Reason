return {
	cormex = {
		acceleration = 0,
		activatewhenbuilt = true,
		brakerate = 0,
		buildangle = 2048,
		buildcostenergy = 500,
		buildcostmetal = 55,
		buildinggrounddecaldecayspeed = 30,
		buildinggrounddecalsizex = 5,
		buildinggrounddecalsizey = 5,
		buildinggrounddecaltype = "cormex_aoplane.dds",
		buildpic = "CORMEX.DDS",
		buildtime = 1874,
		category = "ALL NOTLAND NOTSUB NOWEAPON NOTSHIP NOTAIR NOTHOVER SURFACE",
		collisionvolumeoffsets = "0 3 0",
		collisionvolumescales = "48 33 48",
		collisionvolumetype = "CylY",
		corpse = "DEAD",
		description = "Extracts Metal",
		explodeas = "smallBuildingexplosiongeneric",
		extractsmetal = 0.001,
		footprintx = 3,
		footprintz = 3,
		icontype = "building",
		idleautoheal = 5,
		idletime = 1800,
		maxdamage = 175,
		maxslope = 20,
		maxwaterdepth = 20,
		metalstorage = 50,
		name = "Metal Extractor",
		objectname = "CORMEX",
		onoffable = true,
		seismicsignature = 0,
		selfdestructas = "smallBuildingexplosiongeneric",
		selfdestructcountdown = 1,
		sightdistance = 273,
		usebuildinggrounddecal = true,
		yardmap = "ooooooooo",
		customparams = {
			death_sounds = "generic",
		},
		featuredefs = {
			dead = {
				blocking = true,
				category = "corpses",
				collisionvolumeoffsets = "-3.07257080078 -0.112374182129 0.00819396972656",
				collisionvolumescales = "61.0307312012 23.0310516357 47.5323181152",
				collisionvolumetype = "Box",
				damage = 105,
				description = "Metal Extractor Wreckage",
				energy = 0,
				featuredead = "HEAP",
				featurereclamate = "SMUDGE01",
				footprintx = 3,
				footprintz = 3,
				height = 20,
				hitdensity = 100,
				metal = 33,
				object = "CORMEX_DEAD",
				reclaimable = true,
				seqnamereclamate = "TREE1RECLAMATE",
				world = "All Worlds",
			},
			heap = {
				blocking = false,
				category = "heaps",
				damage = 53,
				description = "Metal Extractor Heap",
				energy = 0,
				featurereclamate = "SMUDGE01",
				footprintx = 3,
				footprintz = 3,
				height = 4,
				hitdensity = 100,
				metal = 13,
				object = "3X3E",
                collisionvolumescales = "55.0 4.0 6.0",
                collisionvolumetype = "cylY",
				reclaimable = true,
				resurrectable = 0,
				seqnamereclamate = "TREE1RECLAMATE",
				world = "All Worlds",
			},
		},
		sfxtypes = { 
 			pieceExplosionGenerators = { 
				"deathceg3",
				"deathceg4",
			},
		},
		sounds = {
			activate = "mexrun2",
			canceldestruct = "cancel2",
			deactivate = "mexoff2",
			underattack = "warning1",
			working = "mexrun2",
			cant = {
				[1] = "cantdo4",
			},
			count = {
				[1] = "count6",
				[2] = "count5",
				[3] = "count4",
				[4] = "count3",
				[5] = "count2",
				[6] = "count1",
			},
			ok = {
				[1] = "servmed2",
			},
			select = {
				[1] = "mexon2",
			},
		},
	},
}