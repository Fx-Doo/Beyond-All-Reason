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

-- this is logical and all but missing the engineformula to barformula correction
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
	
	local hadEnoughM = Spring.UseTeamResource(bpOwner, "metal", taxCostMetal +stepCostMetal) -- paying
	local hadEnoughE = Spring.UseTeamResource(bpOwner, "energy", taxCostEnergy + stepCostEnergy) -- paying
	
	if hadEnoughM and hadEnoughE then
		AddRepairStepToFeature(featureID, stepCostMetal, stepCostEnergy,step)
		return false
	end
	if hadEnoughM then
		Spring.AddTeamResource(bpOwner, "metal", taxCostMetal + stepCostMetal)
	end
	if hadEnoughE then
		Spring.AddTeamResource(bpOwner, "energy", taxCostEnergy + stepCostEnergy)
	end
	return false
end
-------------------------------
------------ Resurrect Wreck Behaviour Code

function RegenerateUnit(featureID, unitTeam, unitDefID, facing)
	local x,y,z = Spring.GetFeaturePosition(featureID)
	local unitID = Spring.CreateUnit(unitDefID, x, y, z, facing, unitTeam)
	local maxHealth = UnitDefs[unitDefID].health
	Spring.SetUnitHealth(unitID, maxHealth * 0.05)
	Spring.DestroyFeature(featureID)
end

function AddResurrectStepToFeature(featureID, stepCostEnergy, step, wreckOwner, wreckDefID, facing)
	local health, maxHealth, resurrectProgress = Spring.GetFeatureHealth(featureID)
	local newResurrectProgress = math.min(1, resurrectProgress + step)
	if newResurrectProgress == 1 then
		RegenerateUnit(featureID, wreckOwner, wreckDefID, facing)
	else
		Spring.SetFeatureResurrect(featureID, wreckDefID, facing, newResurrectProgress)
	end
end

function ProcessResurrectWreck(builderID, builderTeam, featureID, featureDefID, step)
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
	local hadEnoughE = Spring.UseTeamResource(bpOwner, "energy", taxCostEnergy + stepCostEnergy) -- paying
	if hadEnoughE then
		AddResurrectStepToFeature(featureID, stepCostEnergy, step, wreckOwner, wreckDefID, facing)
		return false
	end
	return false
end
----------------------------
------------------ Reclaim Wreck Behaviour Code

function AddReclaimStepToFeature(featureID, stepCostEnergy, stepCostMetal,step)
	local metal,maxMetal,energy,maxEnergy,reclaimLeft = Spring.GetFeatureResources(featureID)
	local newMetal = math.max(0, metal - stepCostMetal)
	local newEnergy = math.max(0, energy - stepCostEnergy)
	local newReclaimLeft = math.max(0, reclaimLeft - step)
	if newReclaimLeft == 0 then
		Spring.DestroyFeature(featureID)
		return
	end
	Spring.SetFeatureResources(featureID, newMetal, newEnergy)
	Spring.SetFeatureReclaim(featureID, newReclaimLeft)
end

function ProcessReclaimWreck(builderID, builderTeam, featureID, featureDefID, step)
	step = math.abs(step)
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
	local hadEnough = true
	if bpOwner ~= builderTeam then
		local currentEnergy,maxEnergy = Spring.GetTeamResources(bpOwner, "energy")
		local currentMetal, maxMetal = Spring.GetTeamResources(bpOwner, "metal")
		local hadEnoughE = (maxEnergy - currentEnergy) >= (stepCostEnergy - taxCostEnergy)
		local hadEnoughM = (maxMetal - currentMetal) >= (stepCostMetal - taxCostMetal)
		hadEnough = hadEnoughE and hadEnoughM
	end
	if hadEnough then
		Spring.AddTeamResource(bpOwner, "energy", stepCostEnergy - taxCostEnergy)
		Spring.AddTeamResource(bpOwner, "metal", stepCostMetal - taxCostMetal)
		AddReclaimStepToFeature(featureID, stepCostEnergy, stepCostMetal, step)
	end
	return false
end


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
	if step > 0 then -- repair or rez step
		local _,_,_,_,currentBuild = Spring.GetUnitHealth(unitID)
		if currentBuild < 1 then -- build step
			return ProcessBuildUnit(builderID, builderTeam, unitID, unitDefID, step)
		else -- repair step
			return ProcessRepairUnit(builderID, builderTeam, unitID, unitDefID, step)
		end
    else -- reclaim step
		return ProcessReclaimUnit(builderID, builderTeam, unitID, unitDefID, step)
	end
end