
function gadget:GetInfo()
	return {
		name    = "Undo Self Destructions",
		desc	= 'Restore selfdestructed units (only availible to a select few playernames)',
		author	= 'Floris',
		date	= 'June 2017',
		license	= 'GNU GPL, v2 or later',
		layer	= 1,
		enabled	= true
	}
end

-- usage: /luarules undo #teamid #maxSecondsAgo

local cmdname = 'undo'

local rememberGameframes = 9000 -- 9000 -> 5 minutes
local PACKET_HEADER = "$u$"
local PACKET_HEADER_LENGTH = string.len(PACKET_HEADER)

if gadgetHandler:IsSyncedCode() then

	local authorizedPlayers  = {'[teh]Flow', 'FlowerPower'}

	local teamSelfdUnits = {}
	local selfdCmdUnits = {}

	local startPlayers = {}
	function checkStartPlayers()
		for _,playerID in ipairs(Spring.GetPlayerList()) do -- update player infos
			local playername,_,spec,teamID = Spring.GetPlayerInfo(playerID)
			if not spec then
				startPlayers[playername] = true
			end
		end
	end
	function gadget:Initialize()
		checkStartPlayers()
	end
	function gadget:GameStart()
		checkStartPlayers()
	end
	function gadget:PlayerChanged(playerID)
		checkStartPlayers()
	end

	function gadget:GameFrame(gameFrame)
		-- cleanup periodically
		if gameFrame % 901 == 1 then
			local oldestGameFrame = gameFrame - rememberGameframes
			for teamID, units in pairs(teamSelfdUnits) do
				local cleanedUnits = {}
				for oldUnitID, params in pairs(units) do
					if params[1] > oldestGameFrame then
						cleanedUnits[oldUnitID] = params
					end
				end
				teamSelfdUnits[teamID] = cleanedUnits
			end

		end
	end

	function explode(div,str) -- credit: http://richard.warburton.it
		if (div=='') then return false end
		local pos,arr = 0,{}
		-- for each divider found
		for st,sp in function() return string.find(str,div,pos,true) end do
			table.insert(arr,string.sub(str,pos,st-1)) -- Attach chars left of current divider
			pos = sp + 1 -- Jump past current divider
		end
		table.insert(arr,string.sub(str,pos)) -- Attach chars right of last divider
		return arr
	end

	function restoreUnits(teamID, seconds, playerID)
		if teamSelfdUnits[teamID] == nil then
			Spring.SendMessageToPlayer(playerID, 'There is no self destruct unit history for team '..teamID)
			return
		end
		local oldestGameFrame = Spring.GetGameFrame() - (seconds * 30)
		local numRestoredUnits = 0
		local leftovers = {}
		for oldUnitID, params in pairs(teamSelfdUnits[teamID]) do
			if params[1] > oldestGameFrame then
				local unitID = Spring.CreateUnit(params[2], params[4], Spring.GetGroundHeight(params[4], params[6]), params[6], params[7], teamID)
				if unitID ~= nil then
					Spring.SetUnitHealth(unitID, params[3])
					Spring.SetUnitDirection(unitID, params[8], params[9], params[10])
					numRestoredUnits = numRestoredUnits + 1
				end
			else
				leftovers[oldUnitID] = params
			end
		end
		teamSelfdUnits[teamID] = leftovers
		Spring.SendMessageToPlayer(playerID, 'Restored: '..numRestoredUnits..' units')
	end

	function gadget:RecvLuaMsg(msg, playerID)
		if string.sub(msg, 1, PACKET_HEADER_LENGTH) ~= PACKET_HEADER then
			return
		end

		local playername, _, spec = Spring.GetPlayerInfo(playerID)
		local authorized = false
		for _,name in ipairs(authorizedPlayers) do
			if playername == name then
				authorized = true
				break
			end
		end
		if playername ~= "UnnamedPlayer" then
			if authorized == nil then
				Spring.SendMessageToPlayer(playerID, "You are not authorized to restore units")
				return
			end
			if not spec then
				Spring.SendMessageToPlayer(playerID, "You arent allowed to restore units when playing")
				return
			end
			if startPlayers[playername] ~= nil then
				Spring.SendMessageToPlayer(playerID, "You arent allowed to restore units when you have been a player")
				return
			end
		end
		local params = explode(':', msg)
		restoreUnits(tonumber(params[2]), tonumber(params[3]), playerID)
		return true
	end


	-- log selfd's
	local armcomDefID = UnitDefNames.armcom.id
	local corcomDefID = UnitDefNames.corcom.id
	function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID, attackerDefID, attackerTeamID)

		if attackerID == nil and selfdCmdUnits[unitID] then -- attackerID == nil -> selfd/reclaim
			if teamSelfdUnits[teamID] == nil then
				teamSelfdUnits[teamID] = {}
			end
			local ux,uy,uz = Spring.GetUnitPosition(unitID)
			local health = Spring.GetUnitHealth(unitID)
			local buildFacing =  Spring.GetUnitBuildFacing(unitID)
			local dx, dy, dz =  Spring.GetUnitDirection(unitID)
			teamSelfdUnits[teamID][unitID] = {Spring.GetGameFrame(), unitDefID, health, ux, uy, uz, buildFacing, dx, dy, dz }

			-- armcom and corcom leave wreckage behind
			if unitDefID == armcomDefID or unitDefID == corcomDefID then

			end
		end
	end

	-- log selfd commands
	function gadget:UnitCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)

		-- check for queued selfd (to check if queue gets cancelled)
		if selfdCmdUnits[unitID] then
			local foundSelfdCmd = false
			local unitQueue = Spring.GetUnitCommands(unitID,20) or {}
			if (#unitQueue > 0) then
				for _,cmd in ipairs(unitQueue) do
					if cmd.id == CMD.SELFD then
						foundSelfdCmd = true
						break
					end
				end
			end
			if foundSelfdCmd then
				selfdCmdUnits[unitID] = nil
			end
		end

		if cmdID == CMD.SELFD then
			if Spring.GetUnitSelfDTime(unitID) > 0 then  	-- since cmd hasnt been cancelled yet
				selfdCmdUnits[unitID] = nil
			else
				selfdCmdUnits[unitID] = Spring.GetGameFrame()
			end
		end
	end

else	-- UNSYNCED


	function gadget:Initialize()
		gadgetHandler:AddChatAction(cmdname, Undo)
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveChatAction(cmdname)
	end

	function Undo(cmd, line, words, playerID)

		if words[1] ~= nil and words[2] ~= nil then
			Spring.SendLuaRulesMsg(PACKET_HEADER..':'..words[1]..':'..words[2])

			--Spring.SendMessageToPlayer(playerID, "Invalid team")
		end
	end
end
