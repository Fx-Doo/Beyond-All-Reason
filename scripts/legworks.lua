local stepStartHeading -- current's step starting heading
local currentStepHeadingDelta = 0 -- accumulated heading change since last step
local decayingStepHeadingDelta = 0 -- when the delta is dumped into the this list, it starts decaying at unitDef.turnRate
local maxStepDeg = UnitDefs[Spring.GetUnitDefID(unitID)].turnRate/30
local maxStepHead = degToHead(maxStepDeg)
local lastGroundedFoot
local FULL = 65536
local HALF = FULL/2

local function shortDelta(a, b)
  local d = a - b
  if d >  HALF then d = d - FULL end
  if d < -HALF then d = d + FULL end
  return d
end

function ChangeHeading(currentHeading, lastHeading)
  local thisDelta = shortDelta(currentHeading, lastHeading)
  currentStepHeadingDelta = currentStepHeadingDelta + thisDelta
  Signal(SIG_LEGWORKS)
  StartThread(LegWorks)
end

function decayDelta(decayHeading) -- we move towards 0, at turnRate speed
  if decayHeading < 0 then
    decayHeading = decayHeading + math.min(maxStepHead, -decayHeading)
  elseif decayHeading > 0 then
    decayHeading = decayHeading - math.min(maxStepHead, decayHeading)
  end
  return decayHeading
end

function LegWorks()
  SetSignalMask(SIG_LEGWORKS)
  if lastGroundedFoot ~= groundedFoot then
    lastGroundedFoot = groundedFoot
    decayingStepHeadingDelta = decayingStepHeadingDelta + currentStepHeadingDelta -- decaying should be zeroed at this time, unless some weirdness in the walk() function
    -- we stack "just in case"
    currentStepHeadingDelta = 0
  end
  if (abs(currentStepHeadingDelta) > 0 or abs(decayingStepHeadingDelta) > 0) then
    decayingStepHeadingDelta = decayDelta(decayingStepHeadingDelta)
    local thisDelta = (currentStepHeadingDelta + decayingStepHeadingDelta) -- our reference is the pelvis, it's currently located at -thisDelta
    Turn(lowerbody, 2, -thisDelta / 2, maxStepHead / 2)
    Turn(groundedThigh, 2, -thisDelta / 4, maxStepHead / 4)
    Turn(groundedFoot, 2, -thisDelta / 4, maxStepHead / 4)
    Turn(swingingThigh, 2, thisDelta / 4, maxStepHead / 4)
    Turn(swingingFoot, 2, thisDelta / 4, maxStepHead / 4)
  end
  while (abs(currentStepHeadingDelta) > 0 or abs(decayingStepHeadingDelta) > 0) do
    Sleep(33)
    decayingStepHeadingDelta = decayDelta(decayingStepHeadingDelta)
    local thisDelta = (currentStepHeadingDelta + decayingStepHeadingDelta) -- our reference is the pelvis, it's currently located at -thisDelta
    Turn(lowerbody, 2, -thisDelta / 2, maxStepHead / 2)
    Turn(groundedThigh, 2, -thisDelta / 4, maxStepHead / 4)
    Turn(groundedFoot, 2, -thisDelta / 4, maxStepHead / 4)
    Turn(swingingThigh, 2, thisDelta / 4, maxStepHead / 4)
    Turn(swingingFoot, 2, thisDelta / 4, maxStepHead / 4)
  end
end
  
  
  
