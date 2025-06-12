SuperModule = class(AIBase)

function SuperModule:Name()
	return 'SuperModule'
end

function SuperModule:internalName()
	return "supermodule"
end

function SuperModule:Init()
	Spring.Echo('ksjhdcbksdcjh')
end

function SuperModule:Update()
	if self.gameend == true then
		return
	end
	--print('update')
end