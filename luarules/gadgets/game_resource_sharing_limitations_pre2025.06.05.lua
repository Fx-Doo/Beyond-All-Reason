local gadget = gadget ---@type Gadget
local sharing_tax = Spring.GetModOptions().sharing_tax/100
local disable_manual_resource_sharing = Spring.GetModOptions().disable_manual_resource_sharing
local disable_overflow = Spring.GetModOptions().disable_overflow

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

if sharing_tax == 0 and disable_manual_resource_sharing == false and disable_overflow == false then -- remove ourselves
	return false
end

local ForcedRequests = {}
local lastRecv = {}

for _, teamID in pairs(Spring.GetTeamList()) do
	lastRecv[teamID] = {metal = 0, energy = 0}
	if disable_overflow then
		Spring.SetTeamShareLevel(teamID, "metal", 1.0)
		Spring.SetTeamShareLevel(teamID, "energy", 1.0)
	end
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

if (sharing_tax > 0 or disable_overflow) then

	local function KillOverflow(teamID, resType, amount)
		if amount > 0 then
			local taxedAmount = (disable_overflow and amount) or (amount * sharing_tax)
			local curr = Spring.GetTeamResources(teamID, resType)
			Spring.SetTeamResource(teamID, string.sub(resType,1,1), curr-taxedAmount) -- silently remove
		end
	end

	function gadget:GameFramePost(f)
		if f%30 == 0 then
			for _, teamID in pairs(Spring.GetTeamList()) do
				local _,_,_,curRecvM = Spring.GetTeamResourceStats(teamID, "m")
				local _,_,_,curRecvE = Spring.GetTeamResourceStats(teamID, "e")
				local diffRecvM = curRecvM - lastRecv[teamID].metal
				local diffRecvE = curRecvE - lastRecv[teamID].energy
				KillOverflow(teamID, "metal", diffRecvM)
				KillOverflow(teamID, "energy", diffRecvE)
				lastRecv[teamID].metal = curRecvM
				lastRecv[teamID].energy = curRecvE
			end
		end
	end
	
	if disable_overflow then	
		function gadget:AllowResourceLevel()
			return false
		end
	end
end
