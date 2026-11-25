---@diagnostic disable: undefined-field, call-non-callable, inject-field

-- Loads the runtime's class, AIBase and Module, then STAI/labshst.lua, in an environment of their own.
local function newLabsHST(ai)
	local env = setmetatable({}, { __index = _G })
	for _, path in ipairs({
		"luarules/gadgets/ai/shard_runtime/class.lua",
		"luarules/gadgets/ai/shard_runtime/aibase.lua",
		"luarules/gadgets/ai/shard_runtime/module.lua",
		"luarules/gadgets/ai/STAI/labshst.lua",
	}) do
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		chunk()
	end
	local labs = env.LabsHST()
	labs.ai = ai
	return labs
end

describe("STAI LabsHST PostPositionalFilter", function()
	local function newAI(layerNetworks)
		return {
			armyhst = { factoryMobilities = { armlab = { "veh" } } },
			gridhst = { gridArea = 100 },
			maphst = {
				METALS = { 1, 2 },
				networks = { veh = layerNetworks },
				MobilityNetworkHere = function()
					return 1
				end,
			},
		}
	end

	it("keeps a position whose network is large enough", function()
		local ai = newAI({ [1] = { area = 50, metals = { 1, 2 } } })
		local labs = newLabsHST(ai)
		local p, name = labs:PostPositionalFilter({ x = 0, y = 0, z = 0 }, "armlab")
		assert.truthy(p)
		assert.equal("armlab", name)
	end)

	it("drops a position with no network of its layer instead of erroring", function()
		local ai = newAI({})
		local labs = newLabsHST(ai)
		local p = labs:PostPositionalFilter({ x = 0, y = 0, z = 0 }, "armlab")
		assert.is_nil(p)
	end)

	it("drops a position whose network is too small", function()
		local ai = newAI({ [1] = { area = 1, metals = { 1, 2 } } })
		local labs = newLabsHST(ai)
		local p = labs:PostPositionalFilter({ x = 0, y = 0, z = 0 }, "armlab")
		assert.is_nil(p)
	end)
end)
