--INCREMENT THIS COUNTER FOR EVERY HOUR OF YOUR LIFE WASTED HERE: 38



--Skeleton pieces
--local head, torso, luparm, biggun, ruparm, rloarm, lflare, nano, laserflare, pelvis, rthigh, lthigh, lleg, rleg, rfoot, rfootstep, lfoot, lfootstep, dish, barrel, aimy1, bigguncyl,hatpoint, crown, medalsilver, medalbronze, medalgold, cagelight, cagelight_emit = piece("head", "torso", "luparm", "biggun", "ruparm","rloarm","lflare", "nano", "laserflare", "pelvis", "rthigh", "lthigh" ,"lleg", "rleg", "rfoot", "rfootstep", "lfoot", "lfootstep", "dish", "barrel", "aimy1","bigguncyl","hatpoint", "crown", "medalsilver", "medalbronze", "medalgold", "cagelight", "cagelight_emit")
local base, flare, turret, sensor, sleeve = piece("base", "flare", "turret", "sensor", "sleeve")
local unitDefID = Spring.GetUnitDefID(unitID)
local SIG_AIM = 2
local SIG_MOVE = 1
local SIG_DONTMOVE = 4

stHeading = nil
awHeading = nil
mHeading = nil
curHeading = nil


function GetTargetPos()
	local tx, ty, tz
	local targetID = Spring.GetUnitRulesParam(unitID, "targetID")
	targetID = tonumber(targetID) and targetID >= 0 and targetID or nil
	if not targetID then
		targetID = {
			Spring.GetUnitRulesParam(unitID, "targetCoordX"),
			Spring.GetUnitRulesParam(unitID, "targetCoordY"),
			Spring.GetUnitRulesParam(unitID, "targetCoordZ"),
		}
		targetID = targetID[1] ~= -1 and targetID[3] ~= -1 and targetID or nil
		if targetID then
			tx, ty, tz = targetID[1],targetID[2],targetID[3]
		end
	else
		tx,ty,tz = Spring.GetUnitPosition(targetID)
	end
	if not tx then
		local targetList = GG.getUnitTargetList(unitID)
		if not targetList then return end
		local maybeID = GG.getUnitTargetList(unitID)[1].target
		if type(maybeID) == "table" then
			tx, ty, tz = maybeID[1], maybeID[2], maybeID[3]
		else
			tx, ty, tz = Spring.GetUnitPosition(maybeID)
		end
	end
	if tx then
		local ux,uy,uz = Spring.GetUnitPosition(unitID)
		local dist = math.sqrt((tx-ux)^2 + (tz-uz)^2)
		local range = Spring.GetUnitMaxRange(unitID)
		-- Spring.Echo(dist, range)
		if dist > 2*range then
			tx = nil
		end
	end
	return tx and {tx,ty,tz} or nil
end

local rad = math.rad
function UpdateTargetHeading()
	while(true)do
	local pos = GetTargetPos()
	-- Spring.Echo(pos)
	if pos then
		local ux, uy, uz = Spring.GetUnitPosition(unitID)
		local dirx, diry, dirz =  pos[1] - ux, pos[2] - uy, pos[3] - uz
		curHeading = 2*math.pi*((Spring.GetUnitHeading(unitID) + 32768) / 65536)
		local wtdHeading = 2*math.pi*((Spring.GetHeadingFromVector(dirx, dirz) + 32768) / 65536)
		-- Spring.Echo(curHeading)
		-- Spring.Echo(wtdHeading)
		stHeading = wtdHeading
		-- Spring.Echo(stHeading)
	else
		-- Spring.Echo("setting stHeading = nil")
		stHeading = nil
		-- StopReversing()
	end
	Sleep(100)
	end
end

function Moving()
	SetSignalMask(SIG_MOVE)
	while true do
		local data = Spring.GetUnitMoveTypeData(unitID)
		local mgoal = {data.goalx, data.goaly, data.goalz}
		local ux, uy, uz = Spring.GetUnitPosition(unitID)
		local dirx, diry, dirz = mgoal[1] - ux, mgoal[2] - uy, mgoal[3] - uz
		curHeading = 2*math.pi*((Spring.GetUnitHeading(unitID) + 32768) / 65536)
		local wtdHeading = 2*math.pi*((Spring.GetHeadingFromVector(dirx, dirz) + 32768) / 65536)
		-- Spring.Echo(wtdHeading)
		-- Spring.Echo(curHeading)
		mHeading = wtdHeading
		-- Spring.Echo("mHeading = "..(mHeading or "nil"))
		-- Spring.Echo("stHeading = "..(stHeading or "nil"))
		-- Spring.Echo("awHeading = "..(awHeading or "nil"))
		Decide()
		Sleep(100)
	end
end

function Decide()
	if stHeading then  -- Prioritize stHeading over awHeading
		if mHeading then
			local delta = (mHeading - stHeading)% (2*math.pi)
			-- delta = delta > 0 and delta or (delta + 2*math.pi)
			-- Spring.Echo(delta)
			if delta > (math.pi/2) and  delta < (3/2 * math.pi) then
				-- Spring.Echo("reverse")
				StartReversing()
			else
				-- Spring.Echo("dontreverse")

				StopReversing()
			end
		else
				-- Spring.Echo("dontreverse")

			StopReversing()
		end
	elseif awHeading then
		if mHeading then
			local delta = (mHeading + awHeading)% (2*math.pi)
			-- delta = delta > 0 and delta or (delta + 2*math.pi)
			-- Spring.Echo(delta)
			if delta > math.pi/2 and delta < 3/2 * math.pi then
				-- Spring.Echo("reverse")
				StartReversing()
			else
				-- Spring.Echo("dontreverse")

				StopReversing()
			end
		else
				-- Spring.Echo("dontreverse")

			StopReversing()
		end
	else
				-- Spring.Echo("dontreverse")

		StopReversing()
	end
end

function NotMoving()
	SetSignalMask(SIG_DONTMOVE)
	while true do
		if Spring.GetUnitMoveTypeData(unitID).goalx then
			-- Signal(SIG_DONTMOVE)
		else
			Decide()
		end
		Sleep(100)
	end
end

function script.StartMoving()
	-- Spring.Echo("StartedMoving")
	StartThread(Moving)
	Signal(SIG_DONTMOVE)
end

function script.StopMoving()
	-- mHeading = nil
	-- Spring.Echo("StoppedMoving")
	-- StartThread(NotMoving)
	-- Signal(SIG_MOVE)
end

function script.Create()
	StopReversing()
	StartThread(UpdateTargetHeading)
end


function script.AimFromWeapon(weapon)
	return turret
end

function StopReversing()
	if reversing then
		-- Spring.Echo("Stopreverse")
		Spring.MoveCtrl.SetGroundMoveTypeData(unitID, "maxSpeed", UnitDefs[unitDefID].speed)
		Spring.MoveCtrl.SetGroundMoveTypeData(unitID, "maxReverseSpeed", 0)
		-- Spring.MoveCtrl.SetGroundMoveTypeData(unitID, "maxReverseDist", 0)
		reversing = false
	end
end

local function Normalize(dtx, dty, dtz)
    local len = math.sqrt(dtx*dtx + dty*dty + dtz*dtz)
    if len == 0 then
        return 0, 0, 0
    end
    return dtx / len, dty / len, dtz / len
end

function CheckIfINeedToTurnAroundManually()
	while (reversing) do
		local delta  = (curHeading-mHeading)%(2*math.pi)
		if delta <= math.pi/2 or delta >= 3*math.pi/2 then
			Spring.Echo(delta)
			local dx,dy,dz = Spring.GetUnitDirection(unitID)
			local ux,uy,uz = Spring.GetUnitPosition(unitID)
			local pos = GetTargetPos()
			if pos then
				tx = pos[1] or ux
				ty = pos[2] or uy
				tz = pos[3] or uz
				dtx, dty, dtz = tx - ux, ty - uy, tz - uz
				dtx,dty,dtz = Normalize(dtx, dty, dtz)
				local v = Spring.GetUnitVelocity(unitID)
				local movegoal = {}
				if v > 0.1 then
					movegoal = {x=ux+dx*32 + dtx*32,y=uy+dy*32-dty*32 ,z=uz+dz*32+dtz*32}
				else
					movegoal = {x=ux-dx*128 - dtx*128,y=uy-dy*128-dty*128 ,z=uz-dz*128-dtz*128}
				end
				Spring.SpawnCEG("fire-flames", movegoal.x, movegoal.y, movegoal.z, 0,1,0, 32)
				Spring.SetUnitMoveGoal(unitID, movegoal.x, movegoal.y, movegoal.z, 32, UnitDefs[unitDefID].speed, true)
			end
		end
		Sleep(1)
	end
end

function StartReversing()
	if not reversing then
	-- Spring.Echo("Startreverse"..Spring.GetGameFrame())
		-- Spring.MoveCtrl.SetGroundMoveTypeData(unitID, "maxSpeed", -UnitDefs[unitDefID].speed)
		Spring.MoveCtrl.SetGroundMoveTypeData(unitID, "maxReverseSpeed", UnitDefs[unitDefID].speed)
		-- Spring.MoveCtrl.SetGroundMoveTypeData(unitID, "maxReverseDist", 500000)
		reversing = true
		StartThread(CheckIfINeedToTurnAroundManually)
	end
end

function script.AimWeapon(weapon, heading, pitch)
	Signal(SIG_AIM)
	StartThread(Restore)
	awHeading = heading
	Turn(turret, 2, heading, math.rad(50))
	WaitForTurn(turret, 2)
	return true
end

function script.FireWeapon(weapon)
	return true
end

function script.QueryWeapon(weapon)
	return flare
end

function Restore()
	SetSignalMask(SIG_AIM)
	Sleep(3000)
	awHeading = nil
	Turn(turret, 2, 0, math.rad(50))
	return
end



function script.Killed()
	return 1
end
