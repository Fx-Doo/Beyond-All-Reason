function gadget:GetInfo()
  return {
    name      = "Shared GG.GetUnitX functions",
    desc      = "Caches GetUnitX calls with per-frame delay support",
    author    = "DoodVanDaag (refactored)",
    license   = "GNU GPL, v2 or later",
    layer     = -math.huge, -- must load first
    enabled   = true,
  }
end

------------------------------------------------------------
-- SYNCED
------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
  local cachedUnitData = {}
  local unitPos = {}       -- unified table: unitPos[unitID] = {frame, pos={x,y,z,...}}
  local currentFrame = -1

  function gadget:Initialize()
    for _, unitID in pairs(Spring.GetAllUnits()) do
      gadget:UnitCreated(unitID, Spring.GetUnitDefID(unitID), Spring.GetUnitTeam(unitID))
    end
  end

  function gadget:GameFrame(f)
    currentFrame = f
  end

  function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    cachedUnitData[unitID] = {
      unitDefID = unitDefID,
      unitTeam  = unitTeam,
      defs      = UnitDefs[unitDefID],
    }
    local x,y,z,mx,my,mz,ax,ay,az = Spring.GetUnitPosition(unitID,true)
    unitPos[unitID] = {frame = currentFrame, pos = {x,y,z,mx,my,mz,ax,ay,az}}
  end

  function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    local dat = cachedUnitData[unitID]
    if dat then dat.unitTeam = newTeam end
  end

  function gadget:UnitDestroyed(unitID)
    cachedUnitData[unitID] = nil
    unitPos[unitID] = nil
  end

  ----------------------------------------------------------------
  -- GG functions
  ----------------------------------------------------------------
  GG.GetUnitTeam = function (unitID)
    local dat = cachedUnitData[unitID]
    return dat and dat.unitTeam or Spring.GetUnitTeam(unitID)
  end

  GG.GetUnitDefID = function (unitID)
    local dat = cachedUnitData[unitID]
    return dat and dat.unitDefID or Spring.GetUnitDefID(unitID)
  end

  GG.GetDefs = function (unitID)
    local dat = cachedUnitData[unitID]
    return (dat and dat.defs) or UnitDefs[Spring.GetUnitDefID(unitID)]
  end

  -- Unified position getter with maxDelay
  GG.GetUnitPosition = function (unitID, _, maxDelay)
    maxDelay = maxDelay or 0
    local cached = unitPos[unitID]
    if cached and (currentFrame - cached.frame) <= maxDelay then
      return unpack(cached.pos)
    end
    local x,y,z,mx,my,mz,ax,ay,az = Spring.GetUnitPosition(unitID,true)
    if not x then return end
    local pos = {x,y,z,mx,my,mz,ax,ay,az}
    unitPos[unitID] = {frame = currentFrame, pos = pos}
    SendToUnsynced("unitPosUpdate", unitID, x,y,z,mx,my,mz,ax,ay,az, currentFrame)
    return unpack(pos)
  end

------------------------------------------------------------
-- UNSYNCED
------------------------------------------------------------
else
  local cachedUnitData = {}
  local unitPos = {}
  local currentFrame = -1

  local function unitPosUpdate(_, unitID, x,y,z,mx,my,mz,ax,ay,az, frame)
    unitPos[unitID] = {frame = frame, pos = {x,y,z,mx,my,mz,ax,ay,az}}
  end

  function gadget:Initialize()
    currentFrame = Spring.GetGameFrame()
    for _, unitID in pairs(Spring.GetAllUnits()) do
      gadget:UnitCreated(unitID, Spring.GetUnitDefID(unitID), Spring.GetUnitTeam(unitID))
    end
    gadgetHandler:AddSyncAction("unitPosUpdate", unitPosUpdate)
  end

  function gadget:GameFrame(f)
    currentFrame = f
  end

  function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    cachedUnitData[unitID] = {
      unitDefID = unitDefID,
      unitTeam  = unitTeam,
      defs      = UnitDefs[unitDefID],
    }
    local x,y,z,mx,my,mz,ax,ay,az = Spring.GetUnitPosition(unitID,true)
    unitPos[unitID] = {frame = currentFrame, pos = {x,y,z,mx,my,mz,ax,ay,az}}
  end

  function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    local dat = cachedUnitData[unitID]
    if dat then dat.unitTeam = newTeam end
  end

  function gadget:UnitDestroyed(unitID)
    cachedUnitData[unitID] = nil
    unitPos[unitID] = nil
  end

  ----------------------------------------------------------------
  -- GG functions
  ----------------------------------------------------------------
  GG.GetUnitTeam = function (unitID)
    local dat = cachedUnitData[unitID]
    return dat and dat.unitTeam or Spring.GetUnitTeam(unitID)
  end

  GG.GetUnitDefID = function (unitID)
    local dat = cachedUnitData[unitID]
    return dat and dat.unitDefID or Spring.GetUnitDefID(unitID)
  end

  GG.GetDefs = function (unitID)
    local dat = cachedUnitData[unitID]
    return (dat and dat.defs) or UnitDefs[Spring.GetUnitDefID(unitID)]
  end

  -- Same unified getter
  GG.GetUnitPosition = function (unitID, _, maxDelay)
    maxDelay = maxDelay or 0
    local cached = unitPos[unitID]
    if cached and (currentFrame - cached.frame) <= maxDelay then
      return unpack(cached.pos)
    end
    local x,y,z,mx,my,mz,ax,ay,az = Spring.GetUnitPosition(unitID,true)
    if not x then return end
    local pos = {x,y,z,mx,my,mz,ax,ay,az}
    unitPos[unitID] = {frame = currentFrame, pos = pos}
    return unpack(pos)
  end
end