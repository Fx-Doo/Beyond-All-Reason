local gadget = gadget ---@type Gadget
local sharing_tax = Spring.GetModOptions().sharing_tax/100
local disable_manual_resource_sharing = Spring.GetModOptions().disable_manual_resource_sharing
local disable_overflow = Spring.GetModOptions().disable_overflow
local engineOverflowBlock = Game.nativeExcessSharing ~= nil
local teamExcessCallin = Script.GetCallInList().TeamResourceExcess ~= nil

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
elseif sharing_tax == 0 and disable_manual_resource_sharing == false and engineOverflowBlock == true and disable_overflow == true then -- we don't need any of the following if we're just disabling overflow post 2025.06.05
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

function GG.ForcedResourceSharing(senderTeamId, receiverTeamId, resourceType, amount) -- Register a global function that would allow us to override the no sharing limitation (= forced sharing) it is probably useless for now, but will be recquired for taxed share to still show as received/sent resources
	local hash = Hash(senderTeamId, receiverTeamId, resourceType, amount)
	ForcedRequests[hash] = true
	Spring.ShareTeamResource(senderTeamId, receiverTeamId, resourceType, amount)
	lastRecv[receiverTeamId][resourceType] = lastRecv[receiverTeamId][resourceType] + amount -- register the received metal so overflow kill doesnt remove it
end

function Hash(senderTeamId, receiverTeamId, resourceType, amount)  -- Id those sharing requests
	local frame = Spring.GetGameFrame()
	local str = frame..senderTeamId..receiverTeamId..resourceType..amount
	return str
end

function gadget:AllowResourceTransfer(senderTeamId, receiverTeamId, resourceType, amount)
	local hash = Hash(senderTeamId, receiverTeamId, resourceType, amount)
	
	if ForcedRequests[hash] == true then -- if this is a requested share, allow it + remove from requests table
		ForcedRequests[hash] = nil
		return true
	end
	
	if disable_manual_resource_sharing then
		return false
	end

	Spring.UseTeamResource(senderTeamId, resourceType, sharing_tax * amount) 
	GG.ForcedResourceSharing(senderTeamId, receiverTeamId, resourceType, (1-sharing_tax)*amount)
	return false -- we processed the share
end

if teamExcessCallin then

	function gadget:TeamResourceExcess(teamID, metal, energy) -- no need to handle the disable_overflow case here; we only need to dispatch among allyteam with a tax
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
					-- Spring.Echo(teamID.."leaked "..(amnt).." "..resType.." to "..toTeamID..".")
					totAvailableStor = totAvailableStor - amnt
					perTeamAvStor[toTeamID] = perTeamAvStor[toTeamID] - amnt
				end
			end
		end	
		-- Spring.Echo("Team "..teamID.." leaked a total of "..(percent* totAvailableStor).." ".. resType.. "to its team.")
	end
	
	function gadget:AllowResourceLevel()
		return false
	end

	
elseif (engineOverflowBlock == false and (sharing_tax > 0 or disable_overflow)) or (engineOverflowBlock == true and sharing_tax > 0 and (not disable_overflow)) then -- we only need this to A) kill overflow pre 2025.06.05 and tax overflow pre 2025.06.05 or B) tax overflow post 2025.06.05

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
