---@diagnostic disable: undefined-field, need-check-nil, inject-field

local MAP_PATH = "luarules/gadgets/ai/shard_runtime/spring_lua/map.lua"

-- Loads map.lua with the game rules params given, as api_resource_spot_finder sets them.
local function loadMap(rulesParams)
	local env = setmetatable({
		shard_include = function()
			return {}
		end,
		Spring = {
			GetGameRulesParam = function(name)
				return rulesParams[name]
			end,
			GetGroundHeight = function()
				return 7
			end,
		},
	}, { __index = _G })
	local chunk = assert(loadfile(MAP_PATH))
	setfenv(chunk, env)
	return chunk()
end

describe("map metal spots", function()
	it("come from the game rules params of api_resource_spot_finder", function()
		local params = { mex_count = 2, mex_x1 = 100, mex_y1 = 5, mex_z1 = 200, mex_x2 = 300, mex_y2 = 6, mex_z2 = 400 }
		local map = loadMap(params)

		assert.same({ { x = 100, y = 5, z = 200 }, { x = 300, y = 6, z = 400 } }, map:GetMetalSpots())
		assert.equal(2, map:SpotCount())
		assert.same({ x = 300, y = 6, z = 400 }, map:GetSpot(2))
	end)

	it("are read when first asked for, after the spot finder set them", function()
		local params = {}
		local map = loadMap(params)

		assert.same({}, map:GetMetalSpots())
		params.mex_count = 1
		params.mex_x1, params.mex_z1 = 10, 20

		assert.same({ { x = 10, y = 7, z = 20 } }, map:GetMetalSpots())
	end)

	it("are none on a metal map, where the spot finder sets mex_count to -1", function()
		local map = loadMap({ mex_count = -1 })

		assert.same({}, map:GetMetalSpots())
		assert.equal(0, map:SpotCount())
	end)
end)
