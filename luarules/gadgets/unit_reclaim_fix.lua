function gadget:GetInfo()
    return {
        name      = "Reclaim Fix",
        desc      = "Implements Old Style Reclaim. Included various anticommie reclaim/repair limitations toggled via custom mos",
        author    = "TheFatController, DoodVanDaag", -- lots of help from Lurker
        date      = "May 24th, 2009",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true
    }
end

local mo_reclaimwreckrefundsowner = true
local mo_reclaimunitrefundsowner = true
local mo_repairwreckcapped = true -- Set to default false once MOs are set up

local MOsThatShouldEnableRefundsOwner= { -- list your modoption name here if you want to enable functionality
--Mo_name = true,
}

local MOsThatShouldEnableReclaimUnitRefundsOwner = { -- list your modoption name here if you want to enable functionality
--Mo_name = true,
}

local MOsThatShouldEnableRepairCap = { -- list your modoption name here if you want to enable functionality
--Mo_name = true,
}

for k,v in pairs (Spring.GetModOptions()) do
	if MOsThatShouldEnableRefundsOwner[k] == v then
		mo_reclaimwreckrefundsowner = true
	end
	if MOsThatShouldEnableRepairCap[k] == v then
		mo_repairwreckcapped = true
	end
end

if not gadgetHandler:IsSyncedCode() then
    return
end

local SetFeatureReclaim = Spring.SetFeatureReclaim
local GetFeaturePosition = Spring.GetFeaturePosition
local GetUnitDefID = Spring.GetUnitDefID
local GetFeatureResources = Spring.GetFeatureResources

local featureListMaxResource = {}
local featureListReclaimTime = {}
local unitListReclaimSpeed = {}

for unitDefID, defs in pairs(UnitDefs) do
    if defs.reclaimSpeed > 0 then
        unitListReclaimSpeed[unitDefID] = defs.reclaimSpeed / 30
    end
end

for featureDefID, fdefs in pairs(FeatureDefs) do
    local maxResource = math.max(fdefs.metal, fdefs.energy)
	
    if maxResource > 0 then
		featureListMaxResource[featureDefID] = maxResource
		featureListReclaimTime[featureDefID] = fdefs.reclaimTime
    end
end

local function getStep(featureDefID, unitDefID)
	local maxResource = featureListMaxResource[featureDefID]
	local reclaimTime = featureListReclaimTime[featureDefID]
	local reclaimSpeed = unitListReclaimSpeed[unitDefID]
	if maxResource == nil or reclaimTime == nil or reclaimSpeed == nil then return nil end
	local oldformula = (reclaimSpeed*0.70 + 10*0.30) * 1.5  / reclaimTime
	local newformula = reclaimSpeed / reclaimTime
	return (((maxResource * oldformula) * 1) - (maxResource * newformula)) / maxResource
end

local function ProcessReclaimRefundsOwner(builderID, builderTeam, featureID, featureDefID, step)
	local unitDefID = GetUnitDefID(builderID)
	local newstep = getStep(featureDefID, unitDefID)
	if newstep == nil then return true end
	newstep = math.min(select(5, GetFeatureResources(featureID)), newstep)
	local newpercent = select(5, GetFeatureResources(featureID)) - newstep
	local reclaimTeam = Spring.GetFeatureTeam(featureID)
	local isAllied = reclaimTeam and Spring.AreTeamsAllied(reclaimTeam, builderTeam)
	if not isAllied then
		reclaimTeam = builderTeam
	end
	local metal = FeatureDefs[featureDefID].metal * newstep
	local energy = FeatureDefs[featureDefID].energy * newstep
	local curmetal,_,curenergy = GetFeatureResources(featureID)
	local metal = math.min(metal, curmetal)
	local energy = math.min(energy, curenergy)
	local newmetal = curmetal - metal
	local newenergy = curenergy - energy
	if reclaimTeam == builderTeam then
		Spring.AddUnitResource(builderID,"metal", metal)
		Spring.AddUnitResource(builderID,"energy", energy)
	else
		Spring.AddTeamResource(reclaimTeam,"metal", metal)
		Spring.AddTeamResource(reclaimTeam,"energy", energy)	
	end
	if newpercent <= 0 then
		Spring.DestroyFeature(featureID)
	else
		SetFeatureReclaim(featureID, newpercent)
		Spring.SetFeatureResources(featureID, newmetal, newenergy)
	end
	return false
end

local function ProcessReclaimNoRefunds(builderID, builderTeam, featureID, featureDefID, step)
	local unitDefID = GetUnitDefID(builderID)
	local newstep = getStep(featureDefID, unitDefID)
	if newstep == nil then return true end
	newstep = math.min(select(5, GetFeatureResources(featureID)), newstep)
	local newpercent = select(5, GetFeatureResources(featureID)) - newstep
	SetFeatureReclaim(featureID, newpercent)
	return true
end
local AddedStep = {}
local function ProcessRepairNoCap(builderID, builderTeam, featureID, featureDefID, step)

	return true
end

local function ProcessRepairCap(builderID, builderTeam, featureID, featureDefID, step)
	-- Figure out if it's a rezz step or a repair wreck step
	local _,_,_,_, reclaimLeft = GetFeatureResources(featureID)
	if reclaimLeft < 1 then -- it's a repair step
		AddedStep[featureID] = (AddedStep[featureID] or 0 ) + step
		if AddedStep[featureID] > 0.5 then
			Spring.SetFeatureResurrect(featureID, -1)
			return false
		end
		if reclaimLeft < (1-(0.5 - (AddedStep[featureID] - step ))) then -- if we can anticipate that rezz can't be done anymore, make in non rezzable
			Spring.SetFeatureResurrect(featureID, -1)
			return false
		end
		return true
	end
	return true
end

local function ProcessReclaimUnitRefunds(builderID, builderTeam, unitID, unitDefID, part)
	local unitTeam = Spring.GetUnitTeam(unitID)
	if unitTeam ~= builderTeam and Spring.AreTeamsAllied(builderTeam, unitTeam) then
		local hp,maxHp,_,_,currentBuild = Spring.GetUnitHealth(unitID)
		if hp + part*maxHp <= 0 then
			Spring.AddTeamResource(unitTeam, "metal", UnitDefs[unitDefID].metalCost*currentBuild) -- this needs to be set to refund the unit's current value, not the full cost
			Spring.DestroyUnit(unitID, false, true, builderID)
			return false
		end
	return true
	end
	return true
end


if mo_reclaimwreckrefundsowner then
	if not mo_repairwreckcapped then
		function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, step)
			if step > 0 or featureListMaxResource[featureDefID] == nil then
				return ProcessRepairNoCap(builderID, builderTeam, featureID, featureDefID, step)
			end
			return ProcessReclaimRefundsOwner(builderID, builderTeam, featureID, featureDefID, step)
		end
	else
		function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, step)
			if step > 0 or featureListMaxResource[featureDefID] == nil then
				return ProcessRepairCap(builderID, builderTeam, featureID, featureDefID, step)
			end
			return ProcessReclaimRefundsOwner(builderID, builderTeam, featureID, featureDefID, step)
		end
	end
else
	if not mo_repairwreckcapped then
		function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, step)
			if step > 0 or featureListMaxResource[featureDefID] == nil then
				return ProcessRepairNoCap(builderID, builderTeam, featureID, featureDefID, step)
			end
			return ProcessReclaimNoRefunds(builderID, builderTeam, featureID, featureDefID, step)
		end
	else
		function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, step)
			if step > 0 or featureListMaxResource[featureDefID] == nil then
				return ProcessRepairCap(builderID, builderTeam, featureID, featureDefID, step)
			end
			return ProcessReclaimNoRefunds(builderID, builderTeam, featureID, featureDefID, step)
		end
	end
end

if mo_reclaimunitrefundsowner then
	function gadget:AllowUnitBuildStep(builderID, builderTeam, unitID, unitDefID, part)
		if part < 0 then
			return ProcessReclaimUnitRefunds(builderID, builderTeam, unitID, unitDefID, part)
		end
		return true
	end
end

-- when a wreck dies and becomes a heap, we need to set the reclaim % of the heap to be equal to its 'parent' wreck
-- order of callins below: featurecreated (for heap), feature destroyed (for wreck), gameframe
-- two features should not be able to occupy the same pos on the same frame 
-- so; keep track of features created on that frame, then when a feature dies in coord matching the feature created, transfer reclaim % onto it
-- no need to transfer rez % since heaps are not rezzable
local featuresCreatedThisFrame = {}

function gadget:FeatureCreated(featureID, allyTeamID)
	--record feature creation
	--Spring.Echo("created:",featureID)
	featuresCreatedThisFrame[#featuresCreatedThisFrame+1] = featureID
end

function gadget:FeatureDestroyed(featureID, allyTeamID)
	local bpx,bpy,bpz = GetFeaturePosition(featureID)
	local _,_,_,_, reclaimLeft = GetFeatureResources(featureID)
	--Spring.Echo("died:", featureID, bpx,bpy,bpz,reclaimLeft, heap)

	--seek out heap, if one exists
	local replaceFID
	for i=1,#featuresCreatedThisFrame do 
		local nbpx, nbpy, nbpz = GetFeaturePosition(featuresCreatedThisFrame[i])
		--Spring.Echo("possible", featuresCreatedThisFrame[i], bpx,bpy,bpz,nbpx,nbpy,nbpz)
		if bpx==nbpx and bpy==nbpy and bpz==nbpz then --floating point errors
			replaceFID = featuresCreatedThisFrame[i]
		end
	end
	
	--set heap reclaim %
	if replaceFID and reclaimLeft then
		--Spring.Echo("set:", replaceFID, reclaimLeft)
		SetFeatureReclaim(replaceFID, reclaimLeft)
	end
	
end

function gadget:GameFrame()
	--flush featuresCreatedThisFrame
	if featuresCreatedThisFrame then
		for i=1,#featuresCreatedThisFrame do
			featuresCreatedThisFrame[i] = nil
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------



