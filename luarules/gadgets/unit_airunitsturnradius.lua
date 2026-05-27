local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name      = "Aircrafts land at exact position",
		desc      = "Moves the aircraft at the intended position when landing.",
		author    = "Doo",
		date      = "May 2026",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local attackTurnRadius = 64

local CMD_ATTACK = CMD.ATTACK
local CMD_LAND_AT_GOAL = 99999
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local spGetUnitMoveTypeData = Spring.GetUnitMoveTypeData
local spMoveCtrlEnable = Spring.MoveCtrl.Enable
local spMoveCtrlIsEnabled = Spring.MoveCtrl.IsEnabled
local spMoveCtrlDisable = Spring.MoveCtrl.Disable
local spMoveCtrlSetAirMoveTypeData = Spring.MoveCtrl.SetAirMoveTypeData

local handledUnits = {}
local handledUnitTypes = {}

local landAtGoalAfterThisCommand = {
	[CMD.FIGHT] = true,
	[CMD.MOVE] = true,
}
local keepFlyingStraightAfterThisCommand = {
	[CMD.ATTACK] = true,
}

Spring.SetCustomCommandDrawData(CMD_LAND_AT_GOAL, CMD.MOVE , {0.1, 1.0, 0.1, 0.8}) -- custom command to show the landing zone; will be used in the future when we have a better way to show it without using a command
for udid, ud in pairs(UnitDefs) do
	if ud.canFly then
		handledUnitTypes[udid] = math.max(UnitDefs[udid].turnRadius or 128, 128)
	end
end

local function hasTarget(unitID) -- this doesn't check for "attack-able" units. Maybe we can actualy accurately check if unitID has a "weaponTarget" instead?
	local canAttack = UnitDefs[handledUnits[unitID]].canAttack
	if not canAttack then
		return false
	end
	for ct, weapon in pairs (UnitDefs[handledUnits[unitID]].weapons) do
		local unitTarget = Spring.GetUnitWeaponTarget(unitID, ct)
		if unitTarget > 0 then
			return true
		end
	end
	return false
end

function gadget:Initialize()
	for ct, unitID in pairs(Spring.GetAllUnits()) do
		gadget:UnitCreated(unitID, Spring.GetUnitDefID(unitID))
	end
end

function gadget:UnitCreated(unitID, unitDefID)
	if handledUnitTypes[unitDefID] then
		handledUnits[unitID] = unitDefID
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam, weaponDefID)
	handledUnits[unitID] = nil -- no-op if wasn't registered in the first place
	Spring.MoveCtrl.SetAirMoveTypeData(unitID, "myGravity", 1)
	-- will probs be called twice for crashing bombers, but who cares
end
function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer)
	if handledUnits[unitID] and spGetUnitMoveTypeData(unitID).aircraftState == "crashing" then
		gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam, weaponDefID)
	end
end

function gadget:UnitCmdDone(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions, cmdTag)

	if not handledUnits[unitID] then
		return
	end
	local Q = Spring.GetUnitCommands(unitID, 1)
	local curCMD = Q and Q[1] or nil
	if curCMD then
		return -- we're still busy, don't land 
	end
	if landAtGoalAfterThisCommand[cmdID] then
		local flyMode = Spring.GetUnitStates(unitID).autoland == false
		if flyMode then
			return
		end
		local enemyInRange = hasTarget(unitID)
		if enemyInRange then
			return -- enemy in range, don't land, if the enemy can be hit, engine will autotarget it; else it will land at a closeby free pos
		end
		Spring.GiveOrderToUnit(unitID, CMD_LAND_AT_GOAL, {cmdParams[1], cmdParams[2], cmdParams[3]}, 0)
		-- we force a first update here, to avoid delays that could make the unit overshoot
		-- overshooting still happens though
		local handled, finished = gadget:CommandFallback(unitID, unitDefID, teamID, CMD_LAND_AT_GOAL, {cmdParams[1], cmdParams[2], cmdParams[3]}, {}, 0)
		if (not handled) or finished then
			Spring.UnitFinishCommand(unitID)
		end
	end
end

function gadget:CommandFallback(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions, cmdTag)
	if cmdID ~= CMD_LAND_AT_GOAL then
		return false
	end
	if not handledUnits[unitID] then
		return false
	end
	local Q = Spring.GetUnitCommands(unitID, 2)
	local curCMD = Q and Q[1] or nil
	local nextCMD = Q and Q[2] or nil
	if nextCMD then
		return true,true -- we're back to being busy, don't land and finish current cmd
	end
	local enemyInRange = hasTarget(unitID)
	if enemyInRange then
		return true, true -- enemy in range, don't force land, if the enemy can be hit, engine will autotarget it; else it will land at a closeby free pos
	end
	local landedState = spGetUnitMoveTypeData(unitID).aircraftState == "landed"
	if landedState then
		return true, true -- already landed, just finish the cmd
	end
	local goalPosX, goalPosY, goalPosZ = cmdParams[1], cmdParams[2], cmdParams[3]
	goalPosX, goalPosY, goalPosZ = Spring.ClosestBuildPos(teamID, unitDefID, goalPosX, goalPosY, goalPosZ, 128, 0, 0) -- snap the goal position to the closest valid position to prevent weird landing behavior
	if goalPosX < 0 then
		return true, true -- no valid position found, just finish the cmd and let the engine handle it
	end
	Spring.SetUnitLandGoal(unitID, goalPosX, goalPosY, goalPosZ,16)
	return true, false
end