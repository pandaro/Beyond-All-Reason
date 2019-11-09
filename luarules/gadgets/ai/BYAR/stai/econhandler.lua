




EconHandler = class(Module)

function EconHandler:Name()
	return "EconHandler"
end

function EconHandler:internalName()
	return "econhandler"
end

EconHandler.DebugEnabled = false
local framesPerAvg = 20
local resourceNames = { "Energy", "Metal" }
local resourceCount = #resourceNames

function EconHandler:Init()
	self.hasData = false -- so that it gets data immediately
	self.samples = {}
	self.Energy = {}
	self.Metal = {}
	self:Update()
end

function EconHandler:Update()
	local sample = {}
	-- because resource data is stored as userdata
	for i = 1, resourceCount do
		local name = resourceNames[i]
		local udata = self.game:GetResourceByName(name)
		sample[name] = { income = udata.income, usage = udata.usage, reserves = udata.reserves }
		self[name].capacity = udata.capacity -- capacity is not something that fluctuates wildly
	end
	self.samples[#self.samples+1] = sample
	if not self.hasData or #self.samples == framesPerAvg then self:Average() end
end

function EconHandler:Average()
	local resources = {}
	-- get sum of samples
	local samples = self.samples
	for i = 1, #samples do
		local sample = samples[i]
		for name, resource in pairs(sample) do
			for property, value in pairs(resource) do
				resources[name] = resources[name] or {}
				resources[name][property] = (resources[name][property] or 0) + value
			end
		end
	end
	-- get averages
	local totalSamples = #self.samples
	for name, resource in pairs(self.samples[1]) do
		for property, value in pairs(resource) do
			self[name][property] = resources[name][property] / totalSamples
		end
		self[name].extra = self[name].income - self[name].usage
		if self[name].capacity == 0 then
			self[name].full = math.inf
		else
			self[name].full = self[name].reserves / self[name].capacity
		end
		if self[name].income == 0 then
			self[name].tics = math.inf
		else
			self[name].tics = self[name].reserves / self[name].income
		end
	end
	self.hasData = true
	self.samples = {}
	self:DebugAll()
end

function EconHandler:DebugAll()
	if DebugEnabled then
		for i, name in pairs(resourceNames) do
			local resource = self[name]
			for property, value in pairs(resource) do
				self:EchoDebug(name .. "." .. property .. ": " .. value)
			end
		end
	end
end

