return {
	corcomlvl4 = {
		maxacc = 0.18,
		activatewhenbuilt = true,
		autoheal = 5,
		maxdec = 1.125,
		energycost = 50000,
		metalcost = 5000,
		builddistance = 169,
		builder = true,
		buildpic = "CORCOM.DDS",
		buildtime = 140000,
		cancapture = true,
		cancloak = true,
		canmanualfire = true,
		canmove = true,
		capturable = false,
		capturespeed = 1800,
		cloakcost = 100,
		cloakcostmoving = 1000,
		collisionvolumeoffsets = "0 3 0",
		collisionvolumescales = "28 52 28",
		collisionvolumetype = "CylY",
		corpse = "DEAD",
		damagemodifier = 0.1,
		energymake = 125,
		energystorage = 2000,
		explodeas = "commanderexplosion",
		footprintx = 2,
		footprintz = 2,
		hidedamage = true,
    	holdsteady = true,
		icontype = "corcom",
		idleautoheal = 68,
		idletime = 1800,
		sightemitheight = 40,
		mass = 4900,
		health = 8000,
		maxslope = 20,
		speed = 37.5,
		maxwaterdepth = 35,
		metalmake = 9,
		metalstorage = 500,
		mincloakdistance = 50,
		movementclass = "COMMANDERBOT",
		nochasecategory = "ALL",
		objectname = "Units/CORCOMHILVL.s3o",
		radardistance = 700,
		radaremitheight = 40,
		reclaimable = false,
		script = "Units/CORCOMHILVL.cob",
		seismicsignature = 0,
		selfdestructas = "commanderExplosion",
		selfdestructcountdown = 5,
		showplayername = true,
		sightdistance = 550,
		sonardistance = 550,
		terraformspeed = 1500,
		turninplaceanglelimit = 140,
		turninplacespeedlimit = 0.825,
		turnrate = 1133,
		upright = true,
		workertime = 545,
		buildoptions = {
			[1] = "cormex",
			[2] = "corsolar",
			[3] = "corwin",
			[4] = "coradvsol",
			[5] = "corgeo",
			[6] = "cormakr",
			[7] = "corestor",
			[8] = "coruwms",
			[9] = "cortide",
			[10] = "corexp",
			[11] = "cormstor",
			[12] = "coruwes", 
			[13] = "corfmkr", 
			[14] = "coreyes", 
			[15] = "corrad", 
			[16] = "cordrag", 
			[17] = "cormaw", 
			[18] = "corllt", 
			[19] = "corhllt", 
			[20] = "corhlt", 
			[21] = "corpun", 
			[22] = "corfrock", 
			[23] = "cormadsam", 
			[24] = "corerad", 
			[25] = "cordl", 
			[26] = "corjamt", 
			[27] = "corjuno",
			[28] = "corlab",
			[29] = "corvp",
			[30] = "corap",
			[31] = "cortl", 
			[32] = "corfrt", 
			[33] = "corfrad",
			[34] = "corsy",
			[35] = "cornanotc",
			[36] = "corhp",
			[37] = "corfdrag",
			[38] = "cornanotcplat",
			[39] = "corfhp",
		},
		customparams = {
			unitgroup = 'builder',
			area_mex_def = "cormex",
			iscommander = true,
			effigy_offset = 1,
			evocomlvl = 4,
			--energyconv_capacity = 70,
			--energyconv_efficiency = 1/70,
			model_author = "Mr Bob",
			normaltex = "unittextures/cor_normal.dds",
			paralyzemultiplier = 0.025,
			subfolder = "",
			shield_color_mult = 0.8,
			shield_power = 5500,
			shield_radius = 100,
			evolution_health_transfer = "percentage",
			evolution_target = "corcomlvl5",
			evolution_condition = "timer",
			evolution_timer = 99999,
			evolution_power_threshold = 105000,
			evolution_power_multiplier = 1,
			combatradius = 0,
			effigy = "comeffigylvl2",
			minimum_respawn_stun = 5,
			distance_stun_multiplier = 1,
			fall_damage_multiplier = 5,--this ensures commander dies when it hits the ground so effigies can trigger respawn.
		},
		featuredefs = {
			dead = {
				blocking = true,
				category = "corpses",
				collisionvolumeoffsets = "0 0 0",
				collisionvolumescales = "35 12 54",
				collisionvolumetype = "cylY",
				damage = 20000,
				energy = 0,
				featuredead = "HEAP",
				featurereclamate = "SMUDGE01",
				footprintx = 2,
				footprintz = 2,
				height = 20,
				hitdensity = 100,
				metal = 1250,
				object = "Units/corcom_dead.s3o",
				reclaimable = true,
				seqnamereclamate = "TREE1RECLAMATE",
				world = "All Worlds",
			},
			heap = {
				blocking = false,
				category = "heaps",
				collisionvolumescales = "35 12 54",
				collisionvolumetype = "cylY",
				damage = 5000,
				energy = 0,
				featurereclamate = "SMUDGE01",
				footprintx = 2,
				footprintz = 2,
				height = 4,
				hitdensity = 100,
				metal = 500,
				object = "Units/cor2X2C.s3o",
				reclaimable = true,
				resurrectable = 0,
				seqnamereclamate = "TREE1RECLAMATE",
				world = "All Worlds",
			},
		},
		sfxtypes = {
			explosiongenerators = {
				[1] = "custom:com_sea_laser_bubbles",
				[2] = "custom:barrelshot-medium",
				[3] = "custom:footstep-medium",
			},
			pieceexplosiongenerators = {
				[1] = "deathceg3",
				[2] = "deathceg4",
			},
		},
		sounds = {
			build = "nanlath2",
			canceldestruct = "cancel2",
			capture = "capture2",
			cloak = "kloak2",
			repair = "repair2",
			uncloak = "kloak2un",
			underattack = "warning2",
			unitcomplete = "corcomsel",
			working = "reclaim1",
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
				[1] = "corcom1",
				[2] = "corcom2",
				[3] = "corcom3",
				[4] = "corcom4",
				[5] = "corcom5",
			},
			select = {
				[1] = "corcomsel",
			},
		},
		weapondefs = {
			corcomlaser = {
				allowNonBlockingAim = true,
				areaofeffect = 16,
				avoidfeature = false,
				beamtime = 0.16,
				collidefeature = false,
				collidefriendly = false,
				corethickness = 0.21,
				craterareaofeffect = 0,
				craterboost = 0,
				cratermult = 0,
				edgeeffectiveness = 0.15,
				explosiongenerator = "custom:laserhit-medium-green",
				firestarter = 90,
				impactonly = 1,
				impulsefactor = 0,
				laserflaresize = 5.5,
				name = "HighEnergyLaser",
				noselfdamage = true,
				range = 350,
				reloadtime = 0.33,
				rgbcolor = "0.027 0.40 0.027",
				rgbcolor2 = "0.9 1 0.9",
				soundhitdry = "",
				soundhitwet = "sizzle",
				soundstart = "Lasrmas2",
				soundtrigger = 1,
				thickness = 4.0,
				tolerance = 10000,
				turret = true,
				weapontype = "BeamLaser",
				weaponvelocity = 700,
				damage = {
					default = 550,
					subs = 275,
				},
			},
			corcomsealaser = {
				areaofeffect = 16,
				avoidfeature = false,
				beamtime = 0.16,
				beamttl = 2.4,
				camerashake = 0,
				corethickness = 0.1,
				craterareaofeffect = 0,
				craterboost = 0,
				cratermult = 0,
				cylindertargeting = 1,
				edgeeffectiveness = 1,
				explosiongenerator = "custom:laserhit-small-blue",
				firestarter = 35,
				firesubmersed = true,
				impactonly = 1,
				impulsefactor = 0,
				intensity = 0.3,
				laserflaresize = 5.5,
				name = "J7NSLaser",
				noselfdamage = true,
				range = 450,
				reloadtime = 0.42,
				rgbcolor = "0.2 0.8 0.3",
				rgbcolor2 = "0.2 0.2 0.2",
				soundhitdry = "",
				soundhitwet = "sizzle",
				soundstart = "uwlasrfir1",
				soundtrigger = 1,
				thickness = 5,
				tolerance = 10000,
				turret = true,
				waterweapon = true,
				weapontype = "BeamLaser",
				weaponvelocity = 900,
				damage = {
					default = 400,
					subs = 200,
				},
			},
			disintegrator = {
				areaofeffect = 36,
				avoidfeature = false,
				avoidfriendly = false,
				avoidground = false,
				bouncerebound = 0,
				cegtag = "dgunprojectile",
				commandfire = true,
				craterboost = 0,
				cratermult = 0.15,
				edgeeffectiveness = 0.15,
				energypershot = 500,
				explosiongenerator = "custom:expldgun",
				firestarter = 100,
				firesubmersed = false,
				impulsefactor = 0,
				name = "Disintegrator",
				noexplode = true,
				noselfdamage = true,
				range = 250,
				reloadtime = 0.9,
				soundhit = "xplomas2s",
				soundhitwet = "sizzlexs",
				soundstart = "disigun1",
				soundhitvolume = 36,
				soundstartvolume = 96,
				soundtrigger = true,
				tolerance = 10000,
				turret = true,
				waterweapon = true,
				weapontimer = 4.2,
				weapontype = "DGun",
				weaponvelocity = 300,
				damage = {
					commanders = 0,
					default = 99999,
					scavboss = 1000,
					raptorqueen = 1000,
				},
			},
			corcomeyelaser = {
				areaofeffect = 12,
				avoidfeature = false,
				beamtime = 0.12,
				corethickness = 0.175,
				craterareaofeffect = 0,
				craterboost = 0,
				cratermult = 0,
				edgeeffectiveness = 0.15,
				energypershot = 0,
				explosiongenerator = "custom:laserhit-small-red",
				firestarter = 100,
				impactonly = 1,
				impulsefactor = 0,
				laserflaresize = 20,
				name = "Eye laser",
				noselfdamage = true,
				proximitypriority = 1,
				range = 550,
				reloadtime = 0.306,
				rgbcolor = "1 0 0",
				soundhitdry = "",
				soundhitwet = "sizzle",
				soundstart = "lasrfir3",
				soundtrigger = 1,
				thickness = 2,
				tolerance = 10000,
				turret = true,
				weapontype = "BeamLaser",
				weaponvelocity = 2250,
				damage = {
					default = 85,
					subs = 22,
				},
			},
			repulsor = {
				avoidfeature = false,
				craterareaofeffect = 0,
				craterboost = 0,
				cratermult = 0,
				edgeeffectiveness = 0.15,
				name = "PlasmaRepulsor",
				range = 100,
				soundhitwet = "sizzle",
				weapontype = "Shield",
				damage = {
					default = 100,
				},
				shield = {
					alpha = 0.17,
					armortype = "shields",
					force = 2.5,
					intercepttype = 8191,
					power = 5500,
					powerregen = 125,
					powerregenenergy = 25,
					radius = 100,
					repulser = false,
					smart = true,
					startingpower = 5500,
					visiblerepulse = false,
					badcolor = {
						[1] = 1,
						[2] = 0.2,
						[3] = 0.2,
						[4] = 0.2,
					},
					goodcolor = {
						[1] = 0.2,
						[2] = 1,
						[3] = 0.2,
						[4] = 0.17,
					},
				},
			},
			armcannon = {
				areaofeffect = 144,
				avoidfeature = false,
				craterareaofeffect = 292,
				craterboost = 0,
				cratermult = 0,
				edgeeffectiveness = 0.15,
				explosiongenerator = "custom:genericshellexplosion-medium",
				gravityaffected = "true",
				impulsefactor = 0.123,
				name = "HeavyCannon",
				noselfdamage = true,
				range = 500,
				reloadtime = 3,
				soundhit = "corlevlrhit",
				soundhitwet = "splslrg",
				soundstart = "corlevlr",
				turret = true,
				weapontype = "Cannon",
				weaponvelocity = 310,
				damage = {
					default = 450,
					subs = 225,
					vtol = 45,
				},
			},
		},
		weapons = {
			[1] = {
				def = "CORCOMLASER",
				onlytargetcategory = "SURFACE",
				fastautoretargeting = true,
			},
			[2] = {
				badtargetcategory = "VTOL",
				def = "CORCOMSEALASER",
				onlytargetcategory = "NOTAIR"
			},
			[3] = {
				def = "DISINTEGRATOR",
				onlytargetcategory = "NOTSUB",
			},
            [4] = {
				def = "REPULSOR",
				onlytargetcategory = "NOTSUB",
			},
            [5] = {
				def = "CORCOMEYELASER",
				onlytargetcategory = "NOTSUB",
				fastautoretargeting = true,
			},
			[6] = {
				def = "ARMCANNON",
				onlytargetcategory = "SURFACE",
				fastautoretargeting = true,
			},
		},
	},
}
