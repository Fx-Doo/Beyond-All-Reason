local gadget = gadget ---@type Gadget
local sharing_tax = Spring.GetModOptions().sharing_tax/100
local disable_manual_resource_sharing = Spring.GetModOptions().disable_manual_resource_sharing
local disable_overflow = Spring.GetModOptions().disable_overflow
-- Needs nativeExcessSharing = false whenever a tax or overflow ban is enabled because we now entirely handle overflow from up here

function gadget:GetInfo()
	return {
		name    = 'Resource sharing limitations',
		desc    = 'Handles tax and related limitations',
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

if sharing_tax == 0 and disable_manual_resource_sharing == false then -- we don't need any of the following if we're just disabling overflow post 2025.06.05 (except if we want to lock share cursor)
	return false
end

local ForcedRequests = {}
local lastRecv = {}

for _, teamID in pairs(Spring.GetTeamList()) do
	lastRecv[teamID] = {metal = 0, energy = 0}
	--share cursor is meaningless now, force it to 1.0
	Spring.SetTeamShareLevel(teamID, "metal", 1.0)
	Spring.SetTeamShareLevel(teamID, "energy", 1.0)
end

function GG.ForcedResourceSharing(senderTeamId, receiverTeamId, resourceType, amount)
	local hash = Hash(senderTeamId, receiverTeamId, resourceType, amount)
	ForcedRequests[hash] = true
	Spring.ShareTeamResource(senderTeamId, receiverTeamId, resourceType, amount)
	lastRecv[receiverTeamId][resourceType] = lastRecv[receiverTeamId][resourceType] + amount
end

function Hash(senderTeamId, receiverTeamId, resourceType, amount)
	local frame = Spring.GetGameFrame()
	local str = frame..senderTeamId..receiverTeamId..resourceType..amount
	return str
end

function gadget:AllowResourceTransfer(senderTeamId, receiverTeamId, resourceType, amount)
	local hash = Hash(senderTeamId, receiverTeamId, resourceType, amount)
	
	if ForcedRequests[hash] == true then
		ForcedRequests[hash] = nil
		return true
	end
	
	if disable_manual_resource_sharing then
		return false
	end

	Spring.UseTeamResource(senderTeamId, resourceType, sharing_tax * amount) 
	GG.ForcedResourceSharing(senderTeamId, receiverTeamId, resourceType, (1-sharing_tax)*amount)
	return false
end

	function gadget:TeamResourceExcess(teamID, metal, energy)
		if disable_overflow == true then
			-- Do NOTHING
			return true
		else
			Leak(teamID, "energy", energy)
			Leak(teamID, "metal", metal)
			return true
		end
	end
	
	function Leak(teamID, resType, excess)
		local _,_,_,_,_,curAlly = Spring.GetTeamInfo(teamID)
		local totAvailableStor = 0
		local perTeamAvStor = {}
		local preTaxExcess = excess
		excess = excess * (1-sharing_tax)
		local teamAllyList = Spring.GetTeamList(curAlly)
		for i, toTeamID in pairs (teamAllyList) do
			if teamID ~= toTeamID then
				local curr,stor,_,_,_,share = Spring.GetTeamResources(toTeamID, resType)
				local avStor = stor - curr
				perTeamAvStor[toTeamID] = avStor
				totAvailableStor = totAvailableStor + avStor
			end
		end
		if totAvailableStor <= 0 then
			return
		end
		local percent = math.min(1,excess / totAvailableStor)
		for i, toTeamID in pairs (teamAllyList) do
			if teamID ~= toTeamID then
				local amnt = percent * perTeamAvStor[toTeamID]
				if amnt > 0 then
					Spring.AddTeamResource(toTeamID, resType, amnt)
					totAvailableStor = totAvailableStor - amnt
					perTeamAvStor[toTeamID] = perTeamAvStor[toTeamID] - amnt
				end
			end
		end	
	end
	
	function gadget:AllowResourceLevel()
		return false
	end