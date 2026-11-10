local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Turn towards command",
		desc = "Coroutine lifecycle for turning towards a position",
		author = "Fx-Doo",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CMD_TURN_TOWARDS = GameCMD.TURN_TOWARDS
local activeTurns = {}
local mobileUnits = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.speed > 0 then
		mobileUnits[unitDefID] = true
	end
end

local commandDesc = {
	id = CMD_TURN_TOWARDS,
	type = CMDTYPE.ICON_MAP,
	name = "Turn towards",
	action = "turntowards",
	cursor = "cursormove",
	tooltip = "Turn towards a position",
}

local function TurnTowards(unitID, cmdParams)
	-- TODO: Implement turning here. Yield to wait for the next frame; return to finish the command.
	while true do
		local unitPosX, unitPosY, unitPosZ = Spring.GetUnitPosition(unitID)
		local targetPosX, targetPosY, targetPosZ = cmdParams[1], cmdParams[2], cmdParams[3]
		local currentDirX, currentDirY, currentDirZ = Spring.GetUnitDirection(unitID)
		local wantedDirX, wantedDirY, wantedDirZ = targetPosX - unitPosX, targetPosY - unitPosY, targetPosZ - unitPosZ
		local wantedHeading = Spring.GetHeadingFromVector(wantedDirX, wantedDirZ)
		local currentHeading = Spring.GetHeadingFromVector(currentDirX, currentDirZ)
		local turnRate = UnitDefs[Spring.GetUnitDefID(unitID)].turnRate
		local headDelta = shortDelta(wantedHeading, currentHeading)	
		if headDelta == 0 then
			return
		end
		local absHeadDelta = math.abs(headDelta)
		local sign = absHeadDelta / headDelta
		local maxTurnThisFrame = math.min(turnRate, absHeadDelta)
		local newHeading = currentHeading + (sign * maxTurnThisFrame)
		local newDirX, newDirZ = Spring.GetVectorFromHeading(newHeading)
		Spring.SetUnitDirection(newDirX, currentDirY, newDirZ)
		if newHeading == wantedHeading then
			return
		end
		coroutine.yield()
	end
end

function gadget:CommandFallback(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag)
	if cmdID ~= CMD_TURN_TOWARDS then
		return false
	end

	local turn = activeTurns[unitID]
	if Spring.GetUnitCommandCount(unitID) > 1 or (turn and turn.tag == cmdTag and turn.finished) then
		activeTurns[unitID] = nil
		return true, true
	end

	if not turn or turn.tag ~= cmdTag then
		activeTurns[unitID] = {
			tag = cmdTag,
			co = coroutine.create(function()
				TurnTowards(unitID, cmdParams)
			end),
		}
	end
	return true, false
end

function gadget:GameFrame()
	for unitID, turn in pairs(activeTurns) do
		local cmdID, _, cmdTag = Spring.GetUnitCurrentCommand(unitID)
		if cmdID ~= CMD_TURN_TOWARDS or cmdTag ~= turn.tag then
			activeTurns[unitID] = nil
		elseif Spring.GetUnitCommandCount(unitID) > 1 then
			turn.co = nil
			turn.finished = true
		elseif not turn.finished then
			local ok, err = coroutine.resume(turn.co)
			if not ok then
				Spring.Log("Turn towards command", LOG.ERROR, "Unit " .. unitID .. ": " .. tostring(err))
			end
			if not ok or coroutine.status(turn.co) == "dead" then
				-- Keep the tag until fallback removes the command, so it cannot start again.
				turn.co = nil
				turn.finished = true
			end
		end
	end
end

function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams)
	return mobileUnits[unitDefID] == true
		and #cmdParams == 3
		and type(cmdParams[1]) == "number"
		and type(cmdParams[2]) == "number"
		and type(cmdParams[3]) == "number"
end

function gadget:UnitCreated(unitID, unitDefID)
	if mobileUnits[unitDefID] then
		Spring.InsertUnitCmdDesc(unitID, commandDesc)
	end
end

function gadget:UnitDestroyed(unitID)
	activeTurns[unitID] = nil
end

function gadget:Initialize()
	gadgetHandler:RegisterCMDID(CMD_TURN_TOWARDS)
	gadgetHandler:RegisterAllowCommand(CMD_TURN_TOWARDS)
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		self:UnitCreated(unitID, Spring.GetUnitDefID(unitID))
	end
end

function gadget:Shutdown()
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local cmdDescID = Spring.FindUnitCmdDesc(unitID, CMD_TURN_TOWARDS)
		if cmdDescID then
			Spring.RemoveUnitCmdDesc(unitID, cmdDescID)
		end
	end
end
