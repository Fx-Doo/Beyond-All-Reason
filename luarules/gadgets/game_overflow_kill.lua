function gadget:GetInfo()
	return {
		name    = "Overflow Killer",
		desc    = "Removes overflow incomes",
		author  = "DoodVanDaag",
		date    = "Oct 2025",
		license = "GNU GPL, v2 or later",
		layer   = -math.huge, -- before anything else can mess with resources (ie metal makers gadget)
		enabled = Spring.GetModOptions().tax_resource_sharing_amount and Spring.GetModOptions().tax_resource_sharing_amount > 0,
	}
end


if gadgetHandler:IsSyncedCode() then

	local lastSent = {}
	local lastRecv = {}
	local overFlowTax = Spring.GetModOptions().tax_resource_sharing_amount
	local taxFreeAmount = {}

	for _, teamID in pairs(Spring.GetTeamList()) do
	if Spring.GetModOptions().tax_resource_sharing_amount and Spring.GetModOptions().tax_resource_sharing_amount == 1 then
		Spring.SetTeamShareLevel(teamID, "metal", 1.0)
		Spring.SetTeamShareLevel(teamID, "energy", 1.0)
	end
		lastSent[teamID] = {m = 0, e = 0}
		lastRecv[teamID] = {m = 0, e = 0}
		taxFreeAmount[teamID] = {metal = 0, energy = 0}
	end


	local function KillOverflow(teamID, resType, amount)
		if amount > 0 then
			if overFlowTax < 1 or taxFreeAmount[teamID][resType] ~= 0 then
				local maxFree = taxFreeAmount[teamID][resType]
				local FreeAmount = math.min(maxFree, amount)
				taxFreeAmount[teamID][resType] = maxFree - FreeAmount -- we used FreeAmount of available share)
				local untaxedAmount = amount - FreeAmount
				local taxedAmount = untaxedAmount * overFlowTax
				Spring.UseTeamResource(teamID, resType, taxedAmount)
				return
			else
				Spring.UseTeamResource(teamID, resType, amount)
			-- Spring.Echo(string.format(
				-- "Team %d overflowed %d %s (removed by Overflow Killer)",
				-- teamID, amount, resType
			-- ))
			end
		end
	end

if Spring.GetModOptions().tax_resource_sharing_amount and Spring.GetModOptions().tax_resource_sharing_amount == 1 then
	function gadget:AllowResourceLevel(teamID, _, level)
		if level ~= 1 then
			return false
		end
		return true
	end
end

	function gadget:GameFrame(f)
		if f%30 == 1 then -- exactly one frame after teamhandler calls team->SlowUpdate() where overflow happens (and teamres stats get updated); so this won't cancel received sharing properly =  needs manual sharing to not go through engine pipeline.
			for _, teamID in pairs(Spring.GetTeamList()) do
				local _,_,_,curRecvM = Spring.GetTeamResourceStats(teamID, "m")
				local _,_,_,curRecvE = Spring.GetTeamResourceStats(teamID, "e")

				local diffRecvM = curRecvM - lastRecv[teamID].m
				local diffRecvE = curRecvE - lastRecv[teamID].e

				KillOverflow(teamID, "metal", diffRecvM)
				KillOverflow(teamID, "energy", diffRecvE)

				lastRecv[teamID].m = curRecvM
				lastRecv[teamID].e = curRecvE
				
				-- taxFreeAmount[teamID].energy = math.min(taxFreeAmount[teamID].energy + 0)--10*30, 600) -- +10 per frame (max 300 per second and not over 600 stack)
				-- taxFreeAmount[teamID].metal= math.min(taxFreeAmount[teamID].metal + 0)--0.5*30, 30) -- +0.5 per frame (max 15 per second and not over 30 stack)
				
			end
		end
	end
end
