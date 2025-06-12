NullModule2 = class(Module)

function NullModule2:Name()
	return "NullModule2" -- a nice developer friendly response
end

function NullModule2:internalName()
	return "nullmodule2"
end

function NullModule2:Init()
	self.space = {}
	print('NullModule2 Init',self.space)
	Spring.Echo(self.api.game)
	
	-- we should setup some variables here
end

function NullModule2:Update()
	--print('NullModule2 update')
	-- nothing much to do is there
end

function NullModule2:UnitCreated(unit, unitDefID, teamId)
	Spring.Echo('unitcreated',unit)
end

return NullModule2