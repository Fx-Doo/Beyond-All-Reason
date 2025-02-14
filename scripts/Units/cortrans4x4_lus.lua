base, link, link11, link12, link21, link22, thrust1, thrust2, thrust3, thrust4, thrust5, thrust6 = piece('base', 'link', 'link11', 'link12', 'link21', 'link22', 'thrust1', 'thrust2', 'thrust3', 'thrust4', 'thrust5', 'thrust6')
local SIG_AIM = {}

-- state variables
isMoving = "isMoving"
terrainType = "terrainType"

dontmove = {  -- movectrl params table (don't move params)
maxSpeed = 0,
turnRate = 0,
accRate = 0,
altitudeRate = 0,
currentPitch = 0,
currentBank = 0,
}

move = Spring.GetUnitMoveTypeData (unitID ) -- movectrl params table (default params)

-- table to keep track of transport spots
usedSpots = {
	[link] = false,
	[link11] = false,
	[link12] = false,
	[link21] = false,
	[link22] = false,
	}
	
function script.Create()
	Spring.SetUnitRadiusAndHeight(unitID, 1,1) -- because model's radius is too big so it cannot descend low enough to load small units, will have to be fixed in model but I have no model editor
end


function SetData(val)
	Spring.MoveCtrl.SetGunshipMoveTypeData( unitID, "maxSpeed", val.maxSpeed )
	Spring.MoveCtrl.SetGunshipMoveTypeData( unitID, "turnRate", val.turnRate )
	Spring.MoveCtrl.SetGunshipMoveTypeData( unitID, "accelRate", val.accRate )
	Spring.MoveCtrl.SetGunshipMoveTypeData( unitID, "altitudeRate", val.altitudeRate )
	Spring.MoveCtrl.SetGunshipMoveTypeData( unitID, "currentPitch", val.currentPitch )
	Spring.MoveCtrl.SetGunshipMoveTypeData( unitID, "currentBank", val.currentBank )
end

function script.StartMoving() -- unused here, i copied this from older armdfly script...
   isMoving = true
end

function script.StopMoving() -- unused here, i copied this from older armdfly script...
   isMoving = false
end   

function GetNextSpot(passengerID)
	for k,v in pairs(usedSpots) do
		if v == false then
			usedSpots[k] = true
			return k 
		end
	end
	return false
end

function script.QueryTransport ( passengerID ) -- called after AllowUnitTransportLoad returned true; in current engine that only happens once the unit is aliogned etc..
local curQ = Spring.GetUnitCommands(unitID, 10) -- since it's only called for the first unit in and it wont attempt to load others nearby, i had to find a way to get the next load cmds in queue...
	local spot
	
	for k,v in pairs (curQ) do
		if k > 1 and v.id == CMD.LOAD_UNITS the -- laod cmds in Q
			local dist = Spring.GetUnitSeparation(unitID, v.params[1])
			if dist < 200 then -- Within load radius (tested 200 elmos value but this can be anything)
				spot = GetNextSpot() -- an incomplete function to place unit within transport. This obviously needs more
				if spot then
					StartThread(StartTransport, v.params[1],spot) -- a small animation follows unitAttach (cf infra)
				end
			end
		end
	end
					spot = GetNextSpot() -- because the querytransport still hasn't been processed and placed we have to do it too
				if spot then -- no animation if there is no spot left, obviously this is just so that it doesnt crash right now, but a complete script would have to handle transport capacity beforehand so that it isn't needed
					StartThread(StartTransport, passengerID,spot)
				end
	return spot -- querytransport gets done, and an animation gets done here aswell
end


-- next are functions to turn transport piece -> passenger vector in world space to transport piece -> passenger vector in transporter's unit space
local function rotationMatrixX(rx)
    local cosx = math.cos(rx)
    local sinx = math.sin(rx)
    return {
        {1, 0, 0},
        {0, cosx, -sinx},
        {0, sinx, cosx}
    }
end


local function rotationMatrixY(ry)
    local cosy = math.cos(ry)
    local siny = math.sin(ry)
    return {
        {cosy, 0, siny},
        {0, 1, 0},
        {-siny, 0, cosy}
    }
end

local function rotationMatrixZ(rz)
    local cosz = math.cos(rz)
    local sinz = math.sin(rz)
    return {
        {cosz, -sinz, 0},
        {sinz, cosz, 0},
        {0, 0, 1}
    }
end

local function multiplyMatrices(a, b)
    local result = {}
    for i = 1, 3 do
        result[i] = {}
        for j = 1, 3 do
            result[i][j] = 0
            for k = 1, 3 do
                result[i][j] = result[i][j] + a[i][k] * b[k][j]
            end
        end
    end
    return result
end

local function applyRotation(matrix, vx, vy, vz)
    local x = matrix[1][1] * vx + matrix[1][2] * vy + matrix[1][3] * vz
    local y = matrix[2][1] * vx + matrix[2][2] * vy + matrix[2][3] * vz
    local z = matrix[3][1] * vx + matrix[3][2] * vy + matrix[3][3] * vz
    return x, y, z
end

function StartTransport(passengerID,spot)
	SetData(dontmove) -- first prevent the transport from trying to move, otherwise it will give very weird effects
	local x,y,z = Spring.GetUnitPiecePosDir(unitID, spot) -- transport piece position in world space
	local rx,ry,rz = Spring.GetUnitRotation(unitID) -- transporter rotation in worldspace
	local px,py,pz = Spring.GetUnitPosition(passengerID) -- passenger position in world space
	local rux,ruy,ruz = Spring.GetUnitRotation(passengerID) -- passenger rotation in world space
	local h = Spring.GetUnitHeight(passengerID) -- passenger height
	local dx,dy,dz = px-x, py-y, pz-z -- transport piece -> passenger vector in world space
	local rotX = rotationMatrixX(rx)
	local rotY = rotationMatrixY(ry)
	local rotZ = rotationMatrixZ(rz)
	local combinedRotation = multiplyMatrices(rotZ, multiplyMatrices(rotY, rotX))
	local dx, dy, dz = applyRotation(combinedRotation, dx, dy, dz) -- transport piece -> passenger vector in transporter's unit space
	local drx,dry,drz = rx - rux, ry-ruy, rz-ruz -- transport piece -> passenger rotation in unit space
	
	-- instantaneous move and turn to fit passenger position
	Move(spot, 1, dx)
	Move(spot, 2, dy)
	Move(spot, 3, dz)
	Turn(spot, 1, drx)
	Turn(spot, 2, dry)
	Turn(spot, 3, drz)
	
	Spring.UnitAttach(unitID, passengerID, spot) -- attach piece
	
	-- 3s load animation => go back to spot's position, and make sure height fits
	Move(spot, 1, 0, dx / 3)
	Move(spot, 2, -h, (dy+h) / 3)
	Move(spot, 3, 0, dz / 3)
	Turn(spot, 1, 0, drx/3)
	Turn(spot, 2, 0, dry/3)
	Turn(spot, 3, 0, drz/3)
	
	-- wait for the defined time (3 seconds since the animation takes 3 seconds)
	Sleep(3000)
	
	SetData(move) -- revert mvctrl params so the unit can move again
end

local function RestoreAfterDelay() -- unused
end		


function script.Killed() -- unused
		return 1
end