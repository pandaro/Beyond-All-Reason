NullModule3 = class(Module)

function NullModule3:Name()
	return "NullModule2" -- a nice developer friendly response
end

function NullModule3:internalName()
	return "nullmodule2"
end

function NullModule3:Init()
	self.space = {}
	print('NullModule3 Init',self.game,self.space)

	-- we should setup some variables here
end

function NullModule3:Update()
	--print('NullModule2 update')
	-- nothing much to do is there
end

function NullModule3:UnitCreated(unit, unitDefID, teamId)
	Spring.Echo('nullmodule3 unitcreated',unit)
end
