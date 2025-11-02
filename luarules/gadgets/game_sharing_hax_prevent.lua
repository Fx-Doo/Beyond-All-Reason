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

-- params:
-- builderTeam = owner of the build power that we're using
-- objectTeam = owner of the object that we are interacting with
-- step = % of progress that is expected, < 0 for a reclaim step, > 0 for a build, repair, resurrect, repair wreck step
-- currentProgress = % of progress that was already made, ranges from 0 to 1, used to clamp step value
-- totalECost = absolute Ecost of the full (step = 1) interaction ( = 1* featureenergy for reclaimwreck, 0* unit energy for reclaimunit, 0* unitmetal for repair, 1* unit energy for building, 0.5*wreckDef unit energy for resurrecting, 1* featuremetal for repair wreck)
-- totalECost = absolute Mcost of the full (step = 1) interaction ( = 1* featuremetal for reclaimwreck, 1* unit metal for reclaimunit, 0* unitmetal for repair, 1* unit metal for building, 0*wreckDef unit metal for resurrecting, 1* featuremetal for repair wreck)
-- justBool = used to produce only a bool answer (allowed, not allowed) without any resourcing data (anticipated stop within function)
-- returns:
-- bool allowed
-- table result == table of the resourcing deltas between engine and wanted behaviour, used in the resolve function to add/remove resources
-- table stats == table of the stats deltas between engine and wanted behaviour, used in the resolve function to add/remove stats (but could be moved to a GameFramePost() thread instead
local hasDebt = {}

function gadget:AllowStockpileBuildStep(unitID, unitTeam, weaponDefID, energyCost, metalCost, step)
	local paidDebt = true
	if hasDebt[teamID] then
		paidDebt = TryToPayDebts(teamID)
	end
	return paidDebt
end

local function UseTeamResource(teamID, resType, amount)
	local hadEnough = true
	local curr = Spring.GetTeamResources(teamID, resType)
	if curr >= amount then
		Spring.UseTeamResource(teamID, resType, amount)
		return true
	else
		return false
	end
end

local function UseResource(teamID, resType, amount)
	local hadEnough = UseTeamResource(teamID, resType, amount) -- Debts happen when we ie reclaiming an allied wreck or unit and both manual sharing and unit sharing are disabled or when unit sharing is disabled and res sharing is taxed
	-- We have to remove what the engine produces from builderID => We use Spring.UseTeamResource
	-- But at this point, the income haven't yet arrived
	-- Because we can't hook at the right time with either gameFrame() or gameFramePost() and process that debt before anything else could use the received amount
	-- we set up a lock on any resource consumption that would happen until the debt is paid
	-- this includes positive buildsteps for features, units, weapon stockpiling
	-- this should also include weapons firing with a cost but we have no hook there.
	-- generally, since the resources are credited right after the reclaim step, and those resources are supposedly sufficient to paid the debt, we shouldn't hit a case where anything would actually be delayed (false return on paidDebt = false)
	-- because of the debt itself, but rather because of insuffiscient resources after the debt was paid
	if hadEnough then
		return
	end
	local debt = hasDebt[teamID] or {}
	debt[resType] = (debt[resType] or 0) + amount
	hasDebt[teamID] = debt
end
	
local function TryToPayDebts(teamID)
	if hasDebt[teamID] then
		for _,resType in pairs ({"energy", "metal"}) do
			local debtValue = hasDebt[teamID][resType] or 0
			Spring.Echo(teamID, debtValue)
			local hadEnough = UseTeamResource(teamID, resType, debtValue)
			if hadEnough then
				hasDebt[teamID][resType] = nil
			end
		end
		if hasDebt[teamID].metal == nil and hasDebt[teamID].energy == nil then
			hasDebt[teamID] = nil
			return true
		end
	end
	return false
end
		

function NewDecideOutcome(builderTeam, objectTeam, step, currentProgress, totalECost, totalMCost, justBool)

	-- step 1: clamp step to valid range
	local clampedStep = 0
	if step > 0 then
		clampedStep = math.min(1 - currentProgress, step)
	elseif step < 0 then
		clampedStep = math.max(-currentProgress, step)
	end
	totalECost = - totalECost
	totalMCost = - totalMCost
	-- compute engine resourcing outcome: builder pays or gets the stepcost, objectteam gets/pays nothin
	
	
	local builderResourcing = {metal = clampedStep * totalMCost, energy = clampedStep * totalECost}
	local objectResourcing  = {metal = 0, energy = 0}

	-- step 2: decide ownership & tax logic
	
	local samePerson = (builderTeam == objectTeam)
	local sameAlly = (objectTeam ~= builderTeam) and Spring.AreTeamsAllied(objectTeam, builderTeam)
	local applyTax = false
	local objectOwner = objectTeam
	local bpOwner = builderTeam
	
	if sameAlly and not samePerson then
		if not disable_unit_sharing then 
			objectOwner = bpOwner
			return true, {[builderTeam] = nil, [objectTeam] = nil}, {} -- We consider owning the object, no tax nor limitation can be applied, resourcing stays ==
		end
		if disable_manual_resource_sharing and (bpOwner ~= objectOwner) then
			bpOwner = objectOwner
			if justBool and step > 0 then
				return false
			end
		end
		if (bpOwner ~= objectOwner) and (sharing_tax > 0) then
			applyTax = true
		end
	else -- gaia, enemy or myself case
		objectOwner = bpOwner
		return true, {[builderTeam] = nil, [objectTeam] = nil}, {} -- Similar to owning the object, no tax nor limitation can be applied, resourcing stays ==
	end
	if justBool then
		return true 
	end

	-- step 3: compute wanted outcome
	local wtdBuilderResourcing = {metal = 0, energy = 0}
	local wtdObjectOwnerResourcing = {metal = 0, energy = 0}

	if step > 0 then
		if bpOwner ~= builderTeam then
			return false, nil
		end
		if applyTax then
			totalMCost = totalMCost * (1/(1 - sharing_tax))
			totalECost = totalECost * (1/(1 - sharing_tax))
		end
	elseif step < 0 then
		if applyTax then
			totalMCost = totalMCost * (1 - sharing_tax)
			totalECost = totalECost * (1 - sharing_tax)
		end
	end

	if bpOwner == builderTeam then
		wtdBuilderResourcing = {metal = clampedStep * totalMCost, energy = clampedStep * totalECost}
		wtdObjectOwnerResourcing = {metal = 0, energy = 0}
	elseif bpOwner == objectTeam then
		wtdObjectOwnerResourcing = {metal = clampedStep * totalMCost, energy = clampedStep * totalECost}
		wtdBuilderResourcing = {metal = 0, energy = 0}
	end
	

	local deltaBuilder = {
		metal  = ((wtdBuilderResourcing.metal  - builderResourcing.metal) ~= 0) and (wtdBuilderResourcing.metal  - builderResourcing.metal) or nil,
		energy = ((wtdBuilderResourcing.energy  - builderResourcing.energy) ~= 0) and (wtdBuilderResourcing.energy  - builderResourcing.energy) or nil,
		netPositive = step < 0,
	}
	local deltaObject = {
		metal  = ((wtdObjectOwnerResourcing.metal  - objectResourcing.metal) ~= 0) and (wtdObjectOwnerResourcing.metal  - objectResourcing.metal) or nil,
		energy = ((wtdObjectOwnerResourcing.energy  - objectResourcing.energy) ~= 0) and (wtdObjectOwnerResourcing.energy  - objectResourcing.energy) or nil
	}

	local result = {
		[builderTeam] = deltaBuilder,
		[objectTeam]  = deltaObject,
	}
	
	local statsToManage = {metal = {}, energy = {}}
	local absUntaxed = {metal = math.abs(builderResourcing.metal), energy = math.abs(builderResourcing.energy)}
	local absTaxed = {metal = math.abs(clampedStep * totalMCost), energy = math.abs(clampedStep * totalECost)}
	for resType, tab in pairs (statsToManage) do
		statsToManage[resType] = {
			income = step < 0 and { -- reclaim situation
				[objectTeam] = absUntaxed[resType], -- reclaim step object team produces untaxed value
				[builderTeam] = -absUntaxed[resType], -- reclaim step, builder didn't produce untaxed value
				} or nil,
			expense = step > 0 and { -- build situation
				[objectTeam] = absUntaxed[resType], -- build step, object team uses untaxed value
				[builderTeam] = -absUntaxed[resType], -- buildstep, builderteam didn't use untaxed value
				} or nil,
			pull = step > 0 and { -- build situation
				[objectTeam] = absUntaxed[resType], -- build step, object team uses untaxed value
				[builderTeam] = -absUntaxed[resType], -- buildstep, builderteam didn't use untaxed value
				} or nil,
			sent = bpOwner == builderTeam and {
				[objectTeam] = (step < 0 and absUntaxed[resType]) or nil, -- reclaim step, objectTeam sends untaxed (produced) value
				[builderTeam] = (step > 0 and absTaxed[resType]) or nil, -- build step, builderTeam sends Taxed (increased) value
				} or nil,
			received = bpOwner == builderTeam and {
				[objectTeam] =  (step > 0 and absUntaxed[resType]) or nil, -- buildstep, object team receives untaxed (used) value
				[builderTeam] = (step < 0 and absTaxed[resType]) or nil, -- reclaimstep, builderteam receives taxed (decreased) value
				} or nil,
			}
	end

	return true, result, statsToManage
end

function gadget:AllowCommandAutoTargetUnit(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, targetID, targetDefID, targetTeam, wtdcmdID)
	if wtdcmdID == CMD.RECLAIM then
		return NewDecideOutcome(unitTeam, targetTeam,-1, 0.5,0,0,true )
	elseif wtdcmdID == CMD.REPAIR then
		local hp, maxHP,_,_ buildProgress = Spring.GetUnitHealth(unitID)
		if buildProgress < 1 then
			return NewDecideOutcome(unitTeam, targetTeam,1, 0.5,0,0,true )
		else
			return true
		end
	end
	return true
end

function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag)
	if cmdID == CMD.RESURRECT then
		if #cmdParams == 1 then
			local featureID = cmdParams[1] - Game.maxUnits
			return NewDecideOutcome(unitTeam, Spring.GetFeatureTeam(featureID),1, 0.5,0,0,true )
		end
	elseif cmdID == CMD.RECLAIM then
		if #cmdParams == 1 then
			if cmdParams[1] > Game.maxUnits then
				local featureID = cmdParams[1] - Game.maxUnits
				return NewDecideOutcome(unitTeam, Spring.GetFeatureTeam(featureID),-1, 0.5,0,0,true )
			else
				local targetID = cmdParams[1]
				return NewDecideOutcome(unitTeam, Spring.GetUnitTeam(targetID),-1, 0.5,0,0,true )
			end
		end
	elseif cmdID == CMD.REPAIR then
		if #cmdParams == 1 then
			local targetID = cmdParams[1]
			local hp, maxHP,_,_, buildProgress = Spring.GetUnitHealth(targetID)
			if buildProgress < 1 then
				return NewDecideOutcome(unitTeam, Spring.GetUnitTeam(targetID),1, 0.5,0,0,true )
			else
				return true
			end
		end
	end
	return true
end

function gadget:AllowCommandAutoTargetFeature(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, targetID, targetDefID, targetTeam, wtdcmdID)
	if wtdcmdID == CMD.RECLAIM then
		return NewDecideOutcome(unitTeam, targetTeam,-1, 0.5,0,0,true )
	elseif wtdcmdID == CMD.RESURRECT then
		return NewDecideOutcome(unitTeam, targetTeam,1, 0.5,0,0,true )
	end	
	return true
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

function gadget:UnitCreated(unitID, unitDefID, teamID, builderID)
  if not disable_unit_sharing then
	return
  end
  if not builderID then -- definitely not rezzed
    return
  end
  local cmdID, wreckID = Spring.GetUnitWorkerTask(builderID)
  if cmdID ~= CMD.RESURRECT then -- also not rezzed
    return
  end
  wreckID = wreckID - Game.maxUnits
  local wreckTeamID = Spring.GetFeatureTeam(wreckID)
  if Spring.AreTeamsAllied(wreckTeamID, teamID) then
    Spring.TransferUnit(unitID, wreckTeamID, false)
  end
end


-- params = 
-- builderteam
-- objectteam
-- result from DecideOutcome function (= deltas that will have to be resolved)
-- stats from decide outcome (= deltas that will have to be resolved
-- return:
-- bool resolved: returns true if the delta has been managed, it could fail because of insuffiscient resourcing or storage

local function ResolveDelta(builderID, builderTeam, objectTeam, result, stats)
	-- preliminaryCheck, can we actually credit objectTeam?
	if result[objectTeam] then
		if disable_overflow == true then
			if (result[builderTeam].metal and result[objectTeam].metal > 0) or (result[builderTeam].energy and result[objectTeam].energy > 0) then
				local ecurr, estor = Spring.GetTeamResources(objectTeam, "energy")
				local mcurr, mstor = Spring.GetTeamResources(objectTeam, "metal")
				local avE, avM = estor - ecurr, mstor - mcurr
				if result[objectTeam].metal > avM or result[objectTeam].energy > avE then
					return false
				end
			end
		end
	end

	-- second check, can builderTeam sustain the taxed cost ?
	local ecurr = Spring.GetTeamResources(builderTeam, "energy")
	local mcurr = Spring.GetTeamResources(builderTeam, "metal")
	if result[builderTeam] then
		if not result[builderTeam].netPositive then --netPositive is used to define a step that despite causing a temporary loss, will grant resources to overcome that loss (generally all step < 0 cases)
		-- This is to allow cases of temporary < 0 res pool, if we know for sure the end of gameframepost will be positive
			if result[builderTeam].metal and mcurr < math.abs(result[builderTeam].metal) then
				return false
			end
			if result[builderTeam].energy and ecurr < math.abs(result[builderTeam].energy) then
				return false
			end
		end
		result[builderTeam].netPositive = nil --remove entry as we processed it
	end
	-- We've checked out cases of not being able to perform the resource removals/adds
	-- we can now proceed without any further caution
	-- add or use resourceRaw
	for teamID, subTable in pairs (result) do
		for resType, value in pairs(subTable) do
			if value > 0 then
				Spring.AddTeamResource(teamID, resType, value)
			else
				UseResource(teamID, resType, math.abs(value))
			end
		end
	end
	
	-- optional: add to stats (maybe we can accumulate stats changes and apply once per second instead of doing this)
	for resType, subTable in pairs(stats) do
		for statType, subsubtable in pairs(subTable) do
			for teamID, value in pairs (subsubtable) do	
				Spring.Echo("Adjusted ".. teamID, resType, statType, value)
				Spring.AdjustTeamResourceStats(teamID, resType, statType, value)
				if teamID == builderTeam then
					if statType == "income" then
						Spring.AdjustUnitResourceStats(builderID, resType, "m", value)
					elseif statType == "expense" then
						Spring.AdjustUnitResourceStats(builderID, resType, "u", value)
					end
				end
			end
		end
	end
	
	return true
end
----------------------

function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, step)
		local objectTeam = Spring.GetFeatureTeam(featureID)
		local _,_,_,_, reclaimLeft = Spring.GetFeatureResources(featureID)
		local _, _, resurrectProgress = Spring.GetFeatureHealth(featureID)
		local paidDebt = true
		if hasDebt[builderTeam] then
			paidDebt = TryToPayDebts(builderTeam)
		end
	if step > 0 then -- repair or rez step
		if reclaimLeft < 1 then -- repairing a feature
			local totalECost = FeatureDefs[featureDefID].energy
			local totalMCost = FeatureDefs[featureDefID].metal
			local allowed, result, stats = NewDecideOutcome(builderTeam, objectTeam, step, reclaimLeft, totalECost, totalMCost)
			if not allowed then -- anticipated resturn (no need to try and resolve anything)
				return false
			end
			local resolved = ResolveDelta(builderID, builderTeam, objectTeam, result, stats)
			return allowed and resolved and paidDebt -- return true only once resolved
		else -- rez step
			local wreckDefName, facing = Spring.GetFeatureResurrect (featureID)
			local wreckDefID = UnitDefNames[wreckDefName].id
			local totalECost = 0.5 * UnitDefs[wreckDefID].energyCost
			local totalMCost = 0
			local allowed, result, stats = NewDecideOutcome(builderTeam, objectTeam, step, resurrectProgress, totalECost, totalMCost)
			if not allowed then
				return false
			end
			local resolved = ResolveDelta(builderID, builderTeam, objectTeam, result, stats)
			return allowed and resolved and paidDebt
		end
    else -- reclaim step
		local totalECost = FeatureDefs[featureDefID].energy
		local totalMCost = FeatureDefs[featureDefID].metal
		local allowed, result, stats = NewDecideOutcome(builderTeam, objectTeam, step, reclaimLeft, totalECost, totalMCost)
		if not allowed then
			return false
		end
		local resolved = ResolveDelta(builderID, builderTeam, objectTeam, result, stats)
		return allowed and resolved
	end
end

function gadget:AllowUnitBuildStep(builderID, builderTeam, unitID, unitDefID, step)
	local hp,maxhp,_,_,currentBuild = Spring.GetUnitHealth(unitID)
	local objectTeam = Spring.GetUnitTeam(unitID)
	local paidDebt = true
	if hasDebt[builderTeam] then
		paidDebt = TryToPayDebts(builderTeam)
	end
	if step > 0 then
		if currentBuild < 1 then -- build step
			local totalECost = UnitDefs[unitDefID].energyCost
			local totalMCost = UnitDefs[unitDefID].metalCost
			local allowed, result, stats = NewDecideOutcome(builderTeam, objectTeam, step, currentBuild, totalECost, totalMCost)
			if not allowed then
				return false
			end
			local resolved = ResolveDelta(builderID, builderTeam, objectTeam, result, stats)
			return allowed and resolved and paidDebt
		else -- repair step
			return true
		end
    else -- reclaim step
		if (hp + step * maxhp) <= 0 then -- we only care about the last bit
			local totalECost = 0
			local totalMCost = UnitDefs[unitDefID].metalCost * currentBuild
			local allowed, result , stats= NewDecideOutcome(builderTeam, objectTeam, -1, currentBuild, totalECost, totalMCost)
			if not allowed then
				return false
			end
			local resolved = ResolveDelta(builderID, builderTeam, objectTeam, result, stats)
			return allowed and resolved
		else
			return true
		end
	end
end