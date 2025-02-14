
function gadget:GetInfo()
	return {
		name    = "Loads fixes",
		desc	= 'Changes the load cmds',
		author	= 'Doo',
		date	= '2025',
		license	= 'GNU GPL, v2 or later',
		layer	= 1,
		enabled	= true
	}
end

if gadgetHandler:IsSyncedCode() then

function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, synced)
	if cmdID == 76 then
		Spring.GiveOrderToUnit(cmdParams[1], CMD.LOAD_UNITS, {unitID}, cmdOptions) -- change LOAD_ONTO cmds into LOAD_UNITS from transporter
		return false
	end
	if cmdID == 75 then -- Change LOAD_UNITS area commands into LOAD_UNITS individual commands
		if #cmdParams > 1 then
			local toQ = Spring.GetUnitsInCylinder(cmdParams[1],cmdParams[3],cmdParams[4],unitTeam)
			for i = 1, #toQ do
				if toQ[i] ~= unitID then
					Spring.GiveOrderToUnit( unitID, CMD.LOAD_UNITS, {toQ[i]}, cmdOptions)
					if not cmdOptions.shift == true then -- Use shift on first command only if the area cmd was shifted, else use non shift on first so i cancel previous queue, then shift for the next individual commands
						 cmdOptions.shift = true
					end
				end
			end
		return false
	end


end
		return true -- don't forget to return true for all the other cmds to get through...
end

end