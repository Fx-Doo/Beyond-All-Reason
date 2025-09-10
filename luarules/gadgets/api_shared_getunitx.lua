
function gadget:GetInfo()
  return {
    name      = "Shared GG.GetUnitX functions",
    desc      = "Attempt to optimize recurrent GetUnitX calls by caching and pooling",
    author    = "DoodVanDaag",
    date      = "",
    license   = "GNU GPL, v2 or later",
    layer     = -math.huge, -- needs to be the very first gadget that loads.
    enabled   = true,
  }
end

if gadgetHandler:IsSyncedCode() then
local floor = math.floor
local cachedUnitData = {}
local unitInstantPos = {[-1] = {}}
local unitSlowPos = {[-1] = {}}
local curUpdate = -1
local curSlowUpdate = -1
	
	function gadget:Initialize()
		for index, unitID in pairs(Spring.GetAllUnits()) do
			gadget:UnitCreated(unitID, Spring.GetUnitDefID(unitID), Spring.GetUnitTeam(unitID))
		end
	end
	
	function gadget:GameFrame(f)
		curUpdate = f
		curSlowUpdate = floor(f/15)
		unitInstantPos[curUpdate] = {}
		unitSlowPos[curSlowUpdate] = {}
		unitInstantPos[curUpdate-1] = nil
		unitSlowPos[curSlowUpdate-1] = nil
	end
	
	function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
		cachedUnitData[unitID] = {
			unitDefID = unitDefID,
			unitTeam = unitTeam,
			defs = UnitDefs[unitDefID],
			}
		local x,y,z = Spring.GetUnitPosition(unitID)
		unitInstantPos[curUpdate][unitID] = {x,y,z}
		unitSlowPos[curSlowUpdate][unitID] = {x,y,z}
		SendToUnsynced("unitPosUpdate", unitID, curUpdate, curSlowUpdate, x,y,z)
	end
	
	function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
		cachedUnitData[unitID].unitTeam = newTeam
	end
	
	function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
		cachedUnitData[unitID] = nil
		unitInstantPos[curUpdate][unitID] = nil
		unitSlowPos[curSlowUpdate][unitID] = nil
	end
	
	GG.GetUnitTeam = function (unitID)
		-- Spring.Echo(unitID.." Using synced cached GetUnitTeam() at gameFrame "..Spring.GetGameFrame())
		return cachedUnitData[unitID].unitTeam or Spring.GetUnitTeam(unitID)
	end
	GG.GetUnitDefID = function (unitID)
		-- Spring.Echo(unitID.." Using synced cached GetUnitDefID() at gameFrame "..Spring.GetGameFrame())
		return cachedUnitData[unitID].unitDefID or Spring.GetUnitDefID(unitID)
	end
	
	GG.GetDefs = function (unitID)
		return cachedUnitData[unitID].defs or unitDefs[Spring.GetUnitDefID(unitID)]
	end
	
	GG.GetUnitPosition = function (unitID)
		local cachedData = unitInstantPos[curUpdate][unitID]
		if not cachedData then
			local x,y,z = Spring.GetUnitPosition(unitID)
			cachedData = {x,y,z}
			unitInstantPos[curUpdate][unitID] = cachedData
			unitSlowPos[curSlowUpdate][unitID] = cachedData
			SendToUnsynced("unitPosUpdate", unitID, x,y,z)
		end
		return cachedData[1], cachedData[2], cachedData[3]
	end
	GG.GetUnitPosition = function (unitID)
		local cachedData = unitSlowPos[curSlowUpdate][unitID]
		if not cachedData then
			local x,y,z = Spring.GetUnitPosition(unitID)
			-- Spring.Echo("Caching synced position data for unit "..unitID)
			cachedData = {x,y,z}
			unitInstantPos[curUpdate][unitID] = cachedData
			unitSlowPos[curSlowUpdate][unitID] = cachedData
			SendToUnsynced("unitPosUpdate", unitID, x,y,z)
		end
		return cachedData[1], cachedData[2], cachedData[3]
	end
	
else
local cachedUnitData = {}
local unitInstantPos = {[-1] = {}}
local unitSlowPos = {[-1] = {}}
local floor = math.floor
local curUpdate = -1
local curSlowUpdate = -1
	-------------------
	-- UNIT LIFECYCLE--
	-------------------

	function gadget:Initialize()
		for index, unitID in pairs(Spring.GetAllUnits()) do
			gadget:UnitCreated(unitID, Spring.GetUnitDefID(unitID), Spring.GetUnitTeam(unitID))
		end
		gadgetHandler:AddSyncAction("unitPosUpdate", unitPosUpdate)
	end
	
	function gadget:GameFrame(f)
		curUpdate = f
		curSlowUpdate = floor(f/15)
		unitInstantPos[curUpdate] = {}
		unitSlowPos[curSlowUpdate] = {}
		unitInstantPos[curUpdate-1] = nil
		unitSlowPos[curSlowUpdate-1] = nil
	end

	function unitPosUpdate(_, unitID, x,y,z)
		-- Spring.Echo("Received synced pos data for unit "..unitID.." at currentFrame = "..curUpdate.." and currentSlowFrame = "..curSlowUpdate)
		unitInstantPos[curUpdate][unitID] = {x,y,z}
		unitSlowPos[curSlowUpdate][unitID] = {x,y,z}
	end

	function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
		cachedUnitData[unitID] = {
			unitDefID = unitDefID,
			unitTeam = unitTeam,
			defs = UnitDefs[unitDefID],
			}
		local x,y,z = Spring.GetUnitPosition(unitID)
		unitInstantPos[curUpdate][unitID] = {x,y,z}
		unitSlowPos[curSlowUpdate][unitID] = {x,y,z}
	end
	
	function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
		cachedUnitData[unitID].unitTeam = newTeam
	end
	
	function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
		cachedUnitData[unitID] = nil
	end
	
	GG.GetUnitTeam = function (unitID)
		return cachedUnitData[unitID].unitTeam or Spring.GetUnitTeam(unitID)
	end
	GG.GetUnitDefID = function (unitID)
		return cachedUnitData[unitID].unitDefID or Spring.GetUnitDefID(unitID)
	end
	
	GG.GetDefs = function (unitID)
		return cachedUnitData[unitID].defs or unitDefs[Spring.GetUnitDefID(unitID)]
	end
	
	GG.GetUnitPosition = function (unitID)
		local cachedData = unitSlowPos[curSlowUpdate][unitID]
		if not cachedData then
			-- Spring.Echo("Caching unsynced position data for unit "..unitID)
			local x,y,z = Spring.GetUnitPosition(unitID)
			cachedData = {x,y,z}
			unitInstantPos[curUpdate][unitID] = cachedData
			unitSlowPos[curSlowUpdate][unitID] = cachedData
		end
		return cachedData[1], cachedData[2], cachedData[3]
	end
end