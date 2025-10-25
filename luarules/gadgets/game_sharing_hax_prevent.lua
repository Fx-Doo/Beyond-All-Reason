--[[
Let's consider it that way:

Say we are playing a fun game among friends, we all love each other, so we cooperate alot, that's what we currently have

Sometimes, we lose units, that's supposed to happen in an RTS.
Maybe we can't get access to the wreck ourselves, but our ally can, so he does it.

In our settings, the BP can be "lended"
That means that, despite a worker being owned by A; we are allowed to consider that its bp is working for B without any recquirement to share the worker

We could picture this as:
> Our ally provides BP
> Reclaims our wreck which gives us metal
> But we instantly share that metal to him to thank him for it.
> He gets the full amount of metal funded to him
OR 
> We share our wreck to our ally
> He reclaims with his own BP
> he gets his own metal because we shared the wreck
== self-d commander to boost

From this scenario we can compute what would happen in the different tax/share disabilities that coexist

1/ sharing tax only
> We share our wreck to our ally
> He reclaims with his own BP
> he gets his own metal because we shared the wreck

2/ sharing tax + disable_unit_sharing only
> Our ally provides BP
> Reclaims our wreck which gives us metal
> But we instantly share that metal to him to thank him for it. --> TAX IS APPLIED
> He gets the aft tax amount of metal funded to him

3/ sharing_tax + disable_resource_sharing only
> We share our wreck to our ally
> He reclaims with his own BP
> he gets his own metal because we shared the wreck

4/ disable_resource_sharing + disable_unit_sharing
> Our ally provides BP
> Reclaims our wreck which gives us metal
> We want to share him but we can't, hence we get the income ourselves
> IF we overflow, the whole team might benefit from the shared amount

5/ sharing_tax + disable_resource_sharing + disable_unit_sharing
> Our ally provides BP
> Reclaims our wreck which gives us metal
> We want to share him but we can't, hence we get the income ourselves
> IF we overflow, the whole team might benefit from the aft_tax shared amount

6/ disable_overflow + disable_resource_sharing + disable_unit_sharing
> Our ally provides BP
> Reclaims our wreck which gives us metal
> We want to share him but we can't, and we can't overflow either
> the reclaim is halted(delayed) for as long as we can't store, because our ally has no real control on our storage nor is asked to "know" how full we are


Second scenario;
we lost a unit, and our ally wants to resurrect it
> our ally provides the BP
> Shares us the cost to resurrect our wreck
> We instantly share our unit to him once it's resurrected to thank that nice person
> He gets to use it
OR
> We share the wreck to our ally
> he provides the bp and cost for his own benefit
> he gets HIS unit
== self-kill a unit to share it via resurrection

1/ disabled unit sharing
> our ally provides the BP
> Shares the cost to resurrect our wreck
> We can't share him to thank him
> The unit stays ours

2/ sharing_tax
> We share the wreck to our ally
> he provides the bp and cost taxless for his own benefit
> he gets HIS unit

3/ sharing_tax + disabled_unit_sharing
> our ally provides the BP
> Shares the cost to resurrect our wreck but pays tax
> We can't share him to thank him
> The unit stays ours

4/ disabled resource sharing
> We share the wreck to our ally
> he provides the bp and cost for his own benefit
> he gets HIS unit

5/ disabled resource_sharing and disabled_unit_sharing
> we can't share him the wreck
> he can't share us the cost
> WERE STUCKED

3rd scenario;
We are building something useful for the team, our ally is good, he wants to assist
> our ally provides the BP
> He "shares" us the cost to maintain that BP
> the unit gets finished
> we got our building
OR
> we share the blueprint to our ally
> He provides BP and cost
> the unit gets finished and he shares it back to us
> he gets back his, and we get back our building
== boosting by assisting labs/cons

1/ disabled unit_sharing
> our ally provides the BP
> He "shares" us the cost to maintain that BP
> the unit gets finished
> we got our building

2/ sharing_tax
> we share the blueprint to our ally
> He provides BP and cost
> the unit gets finished and he shares it back to us
> he gets back his, and we get back our building

3/ disabled_resource_sharing
> we share the blueprint to our ally
> He provides BP and cost
> the unit gets finished and he shares it back to us
> he gets back his, and we get back our building

4/ disabled unit_sharing + sharing_tax
> our ally provides the BP
> He "shares" us the cost to maintain that BP but pays the tax
> the unit gets finished
> we got our building

5/ disabled unit_sharing + disabled_resource_sharing
> We just can't

4th scenario
We want something of ours deleted for all eternity, our ally is nice and has available bp so he will, again, help us.
> our ally provides the BP
> He reclaims the unit
> We are refunded the metal cost, and instantly share it to him
> he is thanked for his service
OR 
> We share our unit to our ally
> He reclaims with his own BP
> he gets his own metal because we shared the wreck
== boosting by allowing mate to reclaim our units

1/ sharing tax only
> We share our unit to our ally
> He reclaims with his own BP
> he gets his own metal because we shared the unit

2/ sharing tax + disable_unit_sharing only
> Our ally provides BP
> Reclaims our unit which gives us metal
> But we instantly share that metal to him to thank him for it. --> TAX IS APPLIED
> He gets the aft tax amount of metal funded to him

3/ sharing_tax + disable_resource_sharing only
> We share our unit to our ally
> He reclaims with his own BP
> he gets his own metal because we shared the unit

4/ disable_resource_sharing + disable_unit_sharing
> Our ally provides BP
> Reclaims our unit which gives us metal
> We want to share him but we can't, hence we get the income ourselves
> IF we overflow, the whole team might benefit from the shared amount

5/ sharing_tax + disable_resource_sharing + disable_unit_sharing
> Our ally provides BP
> Reclaims our unit which gives us metal
> We want to share him but we can't, hence we get the income ourselves
> IF we overflow, the whole team might benefit from the aft_tax shared amount

6/ disable_overflow + disable_resource_sharing + disable_unit_sharing
> Our ally provides BP
> Reclaims our unit which gives us metal
> We want to share him but we can't, and we can't overflow either
> the reclaim is halted(delayed) for as long as we can't store, because our ally has no real control on our storage nor is asked to "know" how full we are

5th scenario
We want to resurrect a wreck that has been partially reclaimed
our ally is again trying to help us
3rd scenario;
> our ally provides the BP
> He "shares" us the cost to maintain that BP
> the repair can happen
OR
> we share the wreck to our ally
> He provides BP and cost
> the wreck gets repaired
== boosting by feeding metal into a wreck while ally reclaims it

1/ disabled unit_sharing
> our ally provides the BP
> He "shares" us the cost to maintain that BP
> the wreck gets repaired


2/ sharing_tax
> we share the wreck to our ally
> He provides BP and cost
> the wreck gets repaired

3/ disabled_resource_sharing
> we share the wreck to our ally
> He provides BP and cost
> the wreck gets repaired

4/ disabled unit_sharing + sharing_tax
> our ally provides the BP
> He "shares" us the cost to maintain that BP but pays a tax
> the wreck gets repaired

5/ disabled unit_sharing + disabled_resource_sharing
> We just can't

This gives us a rough idea of how to handle things depending on the enabled modoptions; things that would make sense altogether.


to sum this up, in every situation we actually have
A "wreckOwner" or "unitOwner"
And a "bpOwner"

whenever possible, we will want bpOwner == wreckOwner, because that is what will avoid sharing_tax being applied

That translates into this logic when this is about an "income":

	if sameAlly and not samePerson then
		if not disable_unit_sharing then -- we share the wreck (or unit) to bpOwner for the duration of the interaction
			wreckOwner = bpOwner
		end
		if disable_manual_resource_sharing and (bpOwner ~= wreckOwner) then -- we could not share the wreck or unit, and sharing resources is not possible, we "lend" the bp to the wreckOwner
			bpOwner = wreckOwner
		end
		if sharing_tax > 0 then -- we apply a tax whenever bpOwner ~= wreckOwner
			taxCostEnergy = (bpOwner ~= wreckOwner and sharing_tax * stepCostEnergy) or 0
			taxCostMetal = (bpOwner ~= wreckOwner and sharing_tax * stepCostMetal) or 0
		end
	else -- if gaia, enemy or own, we ignore all this
		wreckOwner = bpOwner
	end
	
And into this logic, when this is about a cost:

	if sameAlly and not samePerson then
		if not disable_unit_sharing then -- we share the wreck (or unit) to bpOwner for the duration of the interaction
			wreckOwner = bpOwner
		end
		if disable_manual_resource_sharing and (bpOwner ~= wreckOwner) then -- we could not share the wreck or unit, and sharing resources is not possible, we're not putting the cost on our ally so we stop here
			return false
		end
		if sharing_tax > 0 then -- we apply a tax whenever bpOwner ~= wreckOwner
			taxCostEnergy = (bpOwner ~= wreckOwner and sharing_tax * stepCostEnergy) or 0
			taxCostMetal = (bpOwner ~= wreckOwner and sharing_tax * stepCostMetal) or 0
		end
	else -- if gaia, enemy or own, we ignore all this
		wreckOwner = bpOwner
	end

]]

local sharing_tax = Spring.GetModOptions().sharing_tax/100
local disable_manual_resource_sharing = Spring.GetModOptions().disable_manual_resource_sharing
local disable_overflow = Spring.GetModOptions().disable_overflow
local disable_unit_sharing = Spring.GetModOptions().disable_unit_sharing

function gadget:GetInfo()
	return {
		name    = 'Sharing Hax prevent',
		desc    = 'Handles sharing related hacks',
		author  = 'DoodVanDaag',
		date    = 'Oct 2025',
		license = 'GNU GPL, v2 or later',
		layer   = 1,
		enabled = true
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local udefcost = {}
local fdefcost = {}

-- some localized functions and helpers
AddTeamResource = Spring.AddTeamResource
AddUnitResource = Spring.AddUnitResource
UseUnitResource = Spring.UseUnitResource
UseTeamResource = Spring.UseTeamResource

local function AddResources(unitID, unitTeam, fundTeam, metal, energy)
	local canReceive, canReceiveE, canReceiveM = true, true, true
	local currentEnergy, maxEnergy
	local currentMetal, maxMetal
	if  unitTeam ~= fundTeam and disable_overflow == true then
		currentEnergy,maxEnergy = Spring.GetTeamResources(fundTeam, "energy")
		currentMetal, maxMetal = Spring.GetTeamResources(fundTeam, "metal")
		canReceiveE = (maxEnergy - currentEnergy) >= (energy)
		canReceiveM = (maxMetal - currentMetal) >= (metal)
		canReceive = canReceiveE and canReceiveM
	end
	if canReceive then
		AddTeamResource(fundTeam, "metal", metal)
		AddTeamResource(fundTeam, "energy", energy)
	end
	return canReceive
end

local function UseResources(unitID, unitTeam, fundTeam, metal, energy)
	if unitTeam == fundTeam then
		local hadEnoughM = UseUnitResource(unitID, "metal", metal)
		local hadEnoughE = UseUnitResource(unitID, "energy", energy)
		return hadEnoughM and hadEnoughE, hadEnoughM, hadEnoughE
	end
	local hadEnoughM = UseTeamResource(fundTeam, "metal", metal)
	local hadEnoughE = UseTeamResource(fundTeam, "energy", energy)
	return hadEnoughM and hadEnoughE, hadEnoughM, hadEnoughE
end


for defID, defs in pairs (UnitDefs) do
	local data = {
		metal = defs.metalCost,
		energy = defs.energyCost,
	}
	udefcost[defID] = data
end

for defID, defs in pairs (FeatureDefs) do
	local data = {
		metal = defs.metal,
		energy = defs.energy,
	}
	fdefcost[defID] = data
end

-------------------------- Repair Wreck Behaviour code
function AddRepairStepToFeature(featureID, stepCostMetal, stepCostEnergy,step)
	local metal,maxMetal,energy,maxEnergy,reclaimLeft = Spring.GetFeatureResources(featureID)
	local newMetal = math.min(maxMetal, metal + stepCostMetal)
	local newEnergy = math.min(maxEnergy, energy + stepCostEnergy)
	local newReclaimLeft = math.min(1, reclaimLeft + step)
	Spring.SetFeatureResources(featureID, newMetal, newEnergy)
	Spring.SetFeatureReclaim(featureID, newReclaimLeft)
end

function ProcessRepairWreck(builderID, builderTeam, featureID, featureDefID, step)
	local metal,maxMetal,energy,maxEnergy,reclaimLeft = Spring.GetFeatureResources(featureID)
	step = math.min(1-reclaimLeft, step)
	local costMetal = fdefcost[featureDefID].metal
	local costEnergy = fdefcost[featureDefID].energy
	local stepCostMetal = costMetal*step
	local stepCostEnergy = costEnergy*step
	
	local bpOwner = builderTeam
	local wreckOwner = Spring.GetFeatureTeam(featureID)

	local samePerson = wreckOwner == bpOwner
	local sameAlly = (wreckOwner ~= bpOwner) and Spring.AreTeamsAllied(wreckOwner, bpOwner)
	local taxCostMetal, taxCostEnergy = 0,0
	if sameAlly and not samePerson then
		if not disable_unit_sharing then
			wreckOwner = bpOwner
		end
		if disable_manual_resource_sharing and (bpOwner ~= wreckOwner) then
			return false
		end
		if sharing_tax > 0 then
			taxCostMetal = (bpOwner ~= wreckOwner and sharing_tax * stepCostMetal) or 0
			taxCostEnergy = (bpOwner ~= wreckOwner and sharing_tax * stepCostEnergy) or 0
		end
	else
		wreckOwner = bpOwner
	end
	
	local hadEnough, hadEnoughM, hadEnoughE = UseResources(builderID, builderTeam, bpOwner, taxCostMetal +stepCostMetal, taxCostEnergy + stepCostEnergy)
	
	if hadEnough then
		-- we refund just the stepCost part, engine will use it again, this allows us to actually return true
		AddResources(builderID, builderTeam, bpOwner, stepCostMetal, stepCostEnergy)
		return true
	end
	-- refund if didnt get through
	if hadEnoughM then
		AddResources(builderID, builderTeam, bpOwner, taxCostMetal +stepCostMetal, 0)
	end
	if hadEnoughE then
		AddResources(builderID, builderTeam, bpOwner, 0, taxCostEnergy +stepCostEnergy)
	end
	return false
end
-------------------------------
------------ Resurrect Wreck Behaviour Code

function AddResurrectStepToFeature(featureID, stepCostEnergy, step, wreckOwner, wreckDefID, facing)
	local health, maxHealth, resurrectProgress = Spring.GetFeatureHealth(featureID)
	local newResurrectProgress = math.min(1, resurrectProgress + step)
	if newResurrectProgress >= 1 then
		Spring.TransferFeature(featureID, wreckOwner)
	end
	Spring.SetFeatureResurrect(featureID, wreckDefID, facing, newResurrectProgress)
end

function ProcessResurrectWreck(builderID, builderTeam, featureID, featureDefID, step)
	local health, maxHealth, resurrectProgress = Spring.GetFeatureHealth(featureID)
	step = math.min ( 1 - resurrectProgres, step)
	local wreckDefName, facing = Spring.GetFeatureResurrect (featureID)
	local wreckDefID = UnitDefNames[wreckDefName].id
	local costEnergy = udefcost[wreckDefID].energy
	local stepCostEnergy = costEnergy * step
	
	local bpOwner = builderTeam
	local wreckOwner = Spring.GetFeatureTeam(featureID)
	
	local samePerson = wreckOwner == bpOwner
	local sameAlly = (wreckOwner ~= bpOwner) and Spring.AreTeamsAllied(wreckOwner, bpOwner)
	
	local taxCostEnergy = 0
	
	if sameAlly and not samePerson then
		if not disable_unit_sharing then
			wreckOwner = bpOwner
		end
		if disable_manual_resource_sharing and (bpOwner ~= wreckOwner) then
			return false
		end
		if sharing_tax > 0 then
			taxCostEnergy = (bpOwner ~= wreckOwner and sharing_tax * stepCostEnergy) or 0
		end
	else
		wreckOwner = bpOwner
	end
	local hadEnough = UseResources(builderID, builderTeam, bpOwner, 0, taxCostEnergy + stepCostEnergy)
	if hadEnough then
		-- we refund just the stepCost part, engine will use it again, this allows us to actually return true
		AddResources(builderID, builderTeam, bpOwner, 0,  stepCostEnergy)
		-- the issue here is that once we hit resurrectProgress >= 1, engine will spawn the unit as builderTeam's rather than wreckOwner's (which can be a different team in case of disable_unit_sharing = true but disable_manual_resource_sharing = false
		-- transfering ownership of the wreck (as seen previously) is meaningless
		-- what we need is to remove the final buildstep after processing its cost, and Spring.CreateUnit(wreckDefID) + Spring.DestroyFeature(featureID);
		-- But because DestroyFeature will only take action at the end of the simFrame, we will still have other rezzers managing to "spawn" new units.
		-- Causing 1 wreck + 15 rezzers => 15 live units + 15 rezzers; that's really an issue
		-- I have to figure out a better way to do it; in the meantime i'll just leave it at that.
		-- maybe with a clamped step and a step > 0 check i can avoid multiple create + destroy calls
		return true
	end
	return false
end
----------------------------
------------------ Reclaim Wreck Behaviour Code
-- this is logical and all but missing the engineformula to barformula correction (semi constant reclaim rate)
local amountMetalClaimedOnFeature = {}
function AddReclaimStepToFeature(featureID, stepCostEnergy, stepCostMetal,step)
	local metal,maxMetal,energy,maxEnergy,reclaimLeft = Spring.GetFeatureResources(featureID)
	local newMetal = math.max(0, metal - stepCostMetal)
	local newEnergy = math.max(0, energy - stepCostEnergy)
	local newReclaimLeft = math.max(0, reclaimLeft - step)
	if newReclaimLeft == 0 then
		Spring.Echo("ended: "..(amountMetalClaimedOnFeature[featureID] - maxMetal))
		Spring.DestroyFeature(featureID)
		return
	end
	Spring.SetFeatureResources(featureID, newMetal, newEnergy)
	Spring.SetFeatureReclaim(featureID, newReclaimLeft)
end



function ProcessReclaimWreck(builderID, builderTeam, featureID, featureDefID, step)
	local metal,maxMetal,energy,maxEnergy,reclaimLeft = Spring.GetFeatureResources(featureID)
	step = math.abs(step)
	step = math.min( reclaimLeft, step)
	local costMetal = fdefcost[featureDefID].metal
	local costEnergy = fdefcost[featureDefID].energy
	local stepCostMetal = costMetal*step
	local stepCostEnergy = costEnergy*step
	
	local bpOwner = builderTeam
	local wreckOwner = Spring.GetFeatureTeam(featureID)
	
	local samePerson = wreckOwner == bpOwner
	local sameAlly = (wreckOwner ~= bpOwner) and Spring.AreTeamsAllied(wreckOwner, bpOwner)
	
	local taxCostEnergy = 0
	local taxCostMetal = 0
	
	if sameAlly and not samePerson then
		if not disable_unit_sharing then
			wreckOwner = bpOwner
		end
		if disable_manual_resource_sharing and (bpOwner ~= wreckOwner) then
			bpOwner = wreckOwner
		end
		if sharing_tax > 0 then
			taxCostEnergy = (bpOwner ~= wreckOwner and sharing_tax * stepCostEnergy) or 0
			taxCostMetal = (bpOwner ~= wreckOwner and sharing_tax * stepCostMetal) or 0
		end
	else
		wreckOwner = bpOwner
	end
		
	local canReceive = AddResources(builderID, builderTeam, bpOwner, stepCostMetal - taxCostMetal, stepCostEnergy - taxCostEnergy)
		Spring.Echo(amountMetalClaimedOnFeature[featureID])
		if canReceive then 
			amountMetalClaimedOnFeature[featureID] = (amountMetalClaimedOnFeature[featureID] or 0) + stepCostMetal - taxCostMetal
			AddReclaimStepToFeature(featureID, stepCostEnergy, stepCostMetal, step)
		end
	return false
end
----------------------------
-------------Build Unit Behaviour code
function AddBuildStepToUnit(unitID, step)
	local health, maxHealth, capture, paralyze, buildProgress = Spring.GetUnitHealth(unitID)
	local newHealth = math.min(maxHealth, health + step*maxHealth)
	local newBuildProgress = math.min(1, buildProgress + step)
	local data = {
	health = newHealth,
	capture = capture,
	paralyze = paralyze,
	build = newBuildProgress,
	}
	Spring.SetUnitHealth(unitID, data)
end

function ProcessBuildUnit(builderID, builderTeam, unitID, unitDefID, step)
	local health, maxHealth, capture, paralyze, buildProgress = Spring.GetUnitHealth(unitID)
	step = math.min(1-buildProgress, step)
	local costMetal = udefcost[unitDefID].metal
	local costEnergy = udefcost[unitDefID].energy
	local stepCostMetal = costMetal*step
	local stepCostEnergy = costEnergy*step
	
	local bpOwner = builderTeam
	local unitOwner = Spring.GetUnitTeam(unitID)

	local samePerson = unitOwner == bpOwner
	local sameAlly = (unitOwner ~= bpOwner) and Spring.AreTeamsAllied(unitOwner, bpOwner)
	local taxCostMetal, taxCostEnergy = 0,0
	if sameAlly and not samePerson then
		if not disable_unit_sharing then
			unitOwner = bpOwner
		end
		if disable_manual_resource_sharing and (bpOwner ~= unitOwner) then
			return false
		end
		if sharing_tax > 0 then
			taxCostMetal = (bpOwner ~= unitOwner and sharing_tax * stepCostMetal) or 0
			taxCostEnergy = (bpOwner ~= unitOwner and sharing_tax * stepCostEnergy) or 0
		end
	else
		unitOwner = bpOwner
	end
	
	local hadEnough, hadEnoughM, hadEnoughE = UseResources(builderID, builderTeam, bpOwner, taxCostMetal +stepCostMetal, taxCostEnergy + stepCostEnergy)
	
	if hadEnough then
		AddResources(builderID, builderTeam, bpOwner, stepCostMetal, stepCostEnergy) -- refund the step cost that will be picked again by engine
		return true
	end
	-- refund if didnt get through
	if hadEnoughM then
		AddResources(builderID, builderTeam, bpOwner, taxCostMetal +stepCostMetal, 0)
	end
	if hadEnoughE then
		AddResources(builderID, builderTeam, bpOwner, 0, taxCostEnergy +stepCostEnergy)
	end
	return false
end

--------------------------
--------------- Repair Unit Behaviour Code
function ProcessRepairUnit(builderID, builderTeam, unitID, unitDefID, step)
	-- placeHolder, but i can't foresee anything happening here since "lending" BP is fine, there is no cost nor benefit involved
	return true
end

--------------------------
-------------- Reclaim Unit Behaviour Code
function DeleteReclaimedUnit(unitID, builderID)
	Spring.DestroyUnit(unitID, false, true, builderID)
end

function ProcessReclaimUnit(builderID, builderTeam, unitID, unitDefID, step)
	step = math.abs(step)
	local costMetal = udefcost[unitDefID].metal
	
	local bpOwner = builderTeam
	local unitOwner = Spring.GetUnitTeam(unitID)
	
	local samePerson = unitOwner == bpOwner
	local sameAlly = (unitOwner ~= bpOwner) and Spring.AreTeamsAllied(unitOwner, bpOwner)
	
	local taxCostMetal = 0
	
	if sameAlly and not samePerson then
		if not disable_unit_sharing then
			unitOwner = bpOwner
		end
		if disable_manual_resource_sharing and (bpOwner ~= unitOwner) then
			bpOwner = unitOwner
		end
		if sharing_tax > 0 then
			taxCostMetal = (bpOwner ~= unitOwner and sharing_tax * costMetal) or 0
		end
	else
		unitOwner = bpOwner
	end 
	--wanted to try returning true and managine resources, but could not, reason being paying a tax upfront (before getting the resources form engine) might be blocked due to not enough current resource
	canReceive = AddResources(builderID, builderTeam, bpOwner, costMetal - taxCostMetal, 0)

	if canReceive then
		DeleteReclaimedUnit(unitID, builderID)
	end
	return false
end

----------------------

function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, step)
	if step > 0 then -- repair or rez step
		local _,_,_,_, reclaimLeft = Spring.GetFeatureResources(featureID)
		if reclaimLeft < 1 then -- repair step
			return ProcessRepairWreck(builderID, builderTeam, featureID, featureDefID, step)
		else -- rez step
			return ProcessResurrectWreck(builderID, builderTeam, featureID, featureDefID, step)
		end
    else -- reclaim step
		return ProcessReclaimWreck(builderID, builderTeam, featureID, featureDefID, step)
	end
end

function gadget:AllowUnitBuildStep(builderID, builderTeam, unitID, unitDefID, step)
	local hp,maxhp,_,_,currentBuild = Spring.GetUnitHealth(unitID)
	if step > 0 then -- repair or rez step
		if currentBuild < 1 then -- build step
			return ProcessBuildUnit(builderID, builderTeam, unitID, unitDefID, step)
		else -- repair step
			return ProcessRepairUnit(builderID, builderTeam, unitID, unitDefID, step)
		end
    else -- reclaim step
		if (hp + step * maxhp) <= 0 then -- we only care about the last bit
			if hp > 0 then
				return ProcessReclaimUnit(builderID, builderTeam, unitID, unitDefID, step)
			else
				return false
			end
		else
			return true
		end
	end
end