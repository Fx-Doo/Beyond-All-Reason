local gadget = gadget ---@type Gadget
local sharing_tax = Spring.GetModOptions().sharing_tax / 100
local disable_manual_resource_sharing = Spring.GetModOptions().disable_manual_resource_sharing
local disable_overflow = Spring.GetModOptions().disable_overflow
local engineOverflowBlock = Game.nativeExcessSharing ~= nil
local teamExcessCallin = Script.GetCallInList().TeamResourceExcess ~= nil

local debugMode = false

function Echo(a)
	if debugMode then
		Spring.Echo(a)
	end
end

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

if sharing_tax == 0 and disable_manual_resource_sharing == false and disable_overflow == false then
	return false
elseif sharing_tax == 0 and disable_manual_resource_sharing == false and engineOverflowBlock == true and disable_overflow == true then
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

addresraw = true
useresraw = true
adjustteamresstats = true

if addresraw then
	AddResourceRaw = Spring.AddResourceRaw
else
	AddResourceRaw = function (teamID, resType, amount)
		local current = Spring.GetTeamResources(teamID, resType)
		Spring.SetTeamResource(teamID, resType, current + amount)
	end
end

if useresraw then
	UseResourceRaw = Spring.UseResourceRaw
else
	UseResourceRaw = function (teamID, resType, amount)
		local current = Spring.GetTeamResources(teamID, resType)
		Spring.SetTeamResource(teamID, resType, current - amount)
	end
end

if adjustteamresstats then
	AdjustTeamResourceStats = Spring.AdjustTeamResourceStats
else
	AdjustTeamResourceStats = function (teamID, resType, statType, amount)
		--Echo("Could not log ".. amount.." "..resType.." "..statType.." for team "..teamID.." as game statistics as AdjustTeamResourceStats function is not available on this engine version.")
	end
end

function GG.TaxedResourceSharing(senderTeamId, receiverTeamId, resourceType, sendAmount)
	--Echo("Received request to send "..sendAmount.. " "..resourceType.. " from team "..senderTeamId.." to team "..receiverTeamId..".")
	local senderCurrent = Spring.GetTeamResources(senderTeamId, resourceType)
	local receiverCurrent, receiverStorage = Spring.GetTeamResources(receiverTeamId, resourceType)
	local availableStorage = math.max(0, receiverStorage - receiverCurrent)
	-- cap receive amount to available storage
	local receiveAmount = (1-sharing_tax) * sendAmount
	--Echo("Received amount should be "..receiveAmount.." "..resourceType..".")
	local receiveAmount = math.min(receiveAmount, availableStorage)
	--Echo("Received amount has been clamped to "..receiveAmount.." "..resourceType..".")
	sendAmount = receiveAmount*(1/(1-sharing_tax))
	--Echo("Sent amount is therefor "..sendAmount.. " "..resourceType..".")
	if sendAmount > senderCurrent then -- in the unlikely case sender can't pay the preTaxAmount (full value), we run back the function with senderCurrent-1 as new sendAmount
		--Echo("Sent amount could not be paid, requesting share with lower value.")
		GG.TaxedResourceSharing(senderTeamId, receiverTeamId, resourceType, senderCurrent-1)
		return
	end
	--Echo("Applying the request")
	Spring.UseResourceRaw(senderTeamId, resourceType, sendAmount)
	--Echo("Removed "..sendAmount.." "..resourceType.." from team "..senderTeamId..".")
	AdjustTeamResourceStats(senderTeamId, resourceType, "s", sendAmount)
	--Echo("Logged "..sendAmount.." "..resourceType.." sent from team "..senderTeamId..".")
	AddResourceRaw(receiverTeamId, resourceType, receiveAmount)
	--Echo("Added "..receiveAmount.." "..resourceType.." to team "..receiverTeamId..".")
	AdjustTeamResourceStats(receiverTeamId, resourceType, "r", receiveAmount)
	--Echo("Logged "..receiveAmount.." "..resourceType.." received by team "..receiverTeamId..".")
end

function gadget:AllowResourceTransfer(senderTeamId, receiverTeamId, resourceType, amount)
	--Echo("Team ".. senderTeamId.." wants to share "..amount.. " "..resourceType.. " to team "..receiverTeamId..".")
	if disable_manual_resource_sharing then
		--Echo("Sharing resource is not allowed, cancelling request.")
		return false
	end
	--Echo("Requesting tax of "..(sharing_tax*100).. "% to be applied.")
	GG.TaxedResourceSharing(senderTeamId, receiverTeamId, resourceType, amount)
	return false
end

-- Modern overflow handling (TeamResourceExcess present)
local allyTeamOverflowedLastFrame = {}
local teamOverflowedLastFrame = {}
local teamReceivedLastFrame = {}
for i, allyTeam in pairs(Spring.GetAllyTeamList()) do
	allyTeamOverflowedLastFrame[allyTeam] = {metal = 0, energy = 0}
end
for i, teamID in pairs(Spring.GetTeamList()) do
	teamOverflowedLastFrame[teamID] = {metal = 0, energy = 0}
	teamReceivedLastFrame[teamID] = {metal = 0, energy = 0}
end

function gadget:TeamResourceExcess(teamID, metal, energy)
	if disable_overflow == true then
		--Echo("Overflow is disabled, logging ".. metal.. " metal and ".. energy.. " energy as team "..teamID.. " metal and energy excess.")
		AdjustTeamResourceStats(teamID, "m", "e", metal)
		AdjustTeamResourceStats(teamID, "e", "e", energy)
		-- log the excess
		return true -- Do nothing
	else
		local _, _, _, _, _, curAlly = Spring.GetTeamInfo(teamID)
		--Echo("Overflow is enabled, logging ".. metal.. " metal and ".. energy.. " energy as allyTeam "..curAlly.. " metal and energy future overflow.")
		allyTeamOverflowedLastFrame[curAlly].metal = allyTeamOverflowedLastFrame[curAlly].metal + metal
		allyTeamOverflowedLastFrame[curAlly].energy = allyTeamOverflowedLastFrame[curAlly].energy + energy
		teamOverflowedLastFrame[teamID].metal = teamOverflowedLastFrame[teamID].metal + metal
		teamOverflowedLastFrame[teamID].energy = teamOverflowedLastFrame[teamID].energy + energy
		--Echo("AllyTeam "..curAlly.. " now has ".. allyTeamOverflowedLastFrame[curAlly].metal.. " metal and "..allyTeamOverflowedLastFrame[curAlly].energy.." energy pending leak.")
		return true
	end
end
	
function gadget:GameFramePost(f)
	if f%30 == 0 then
		for _, allyTeam in pairs(Spring.GetAllyTeamList()) do
			Leak(allyTeam, allyTeamOverflowedLastFrame[allyTeam].metal, allyTeamOverflowedLastFrame[allyTeam].energy)
		end
	end
end

function GetAvailableStorage(teamID, resType)
	local current, storage = Spring.GetTeamResources(teamID, resType)
	return math.max(0, storage - current)
end

function Leak(allyTeam, metal, energy)
	--Echo("Processing AllyTeam "..allyTeam.." leak.")
	if metal == 0 then 
		metal = nil 
		--Echo("No metal to process")
	end
		if energy == 0 then 
		energy = nil 
		--Echo("No energy to process")
	end

	local preTaxValue = {metal = metal, energy = energy}
	--Echo("Processing "..(metal and metal or 0).." metal and "..(energy and energy or 0).. " energy.")
	local totalAvailableAllyTeamStorages = {metal = 0, energy = 0}
	local availableTeamStorage = {}
	--Echo("Figuring out the allyTeam's storage capabilities")
	for _, teamID in pairs(Spring.GetTeamList(allyTeam)) do
		--Echo("Processing team ".. teamID..".")
		availableTeamStorage[teamID] = {}
		for resType, excess in pairs(preTaxValue) do
			--Echo("Processing "..resType..".")
			local availableStorage = GetAvailableStorage(teamID, resType)
			if teamOverflowedLastFrame[teamID][resType] > 0 and availableStorage > 0 then	--refund excess to current team with top priority and no tax
				--Echo("Team "..teamID.." had pending excess of ".. teamOverflowedLastFrame[teamID][resType] .. " "..resType.." while its available storage is non 0 ("..availableStorage..").")
				local shareBack = math.min(teamOverflowedLastFrame[teamID][resType], availableStorage)
				AddResourceRaw(teamID, resType, shareBack)
				--Echo("Refunding it with "..shareBack.." "..resType.. " out of its own "..teamOverflowedLastFrame[teamID][resType].." " .. resType..".")
				availableStorage = availableStorage - shareBack -- remove from available storage
				teamOverflowedLastFrame[teamID][resType] = teamOverflowedLastFrame[teamID][resType] - shareBack --remove from available teamID excess
				--Echo("Team "..teamID.." overflow for "..resType.." is now "..teamOverflowedLastFrame[teamID][resType]..".")
				allyTeamOverflowedLastFrame[allyTeam][resType] = allyTeamOverflowedLastFrame[allyTeam][resType] - shareBack -- remove from available allyTeam excess
				--Echo("Ally Team "..allyTeam.." overflow for "..resType.." is now "..allyTeamOverflowedLastFrame[allyTeam][resType]..".")
				preTaxValue[resType] = preTaxValue[resType] - shareBack -- remove from currently processed excess
				--Echo("Currently processed excess for "..resType.." is now "..preTaxValue[resType]..".")
			end					
			availableTeamStorage[teamID][resType] = availableStorage
			--Echo("Team "..teamID.." can store up to "..availableStorage.." "..resType..".")
			totalAvailableAllyTeamStorages[resType] = totalAvailableAllyTeamStorages[resType] + availableStorage
		end
		--Echo("AllyTeam "..allyTeam.." can store up to "..totalAvailableAllyTeamStorages.metal.." metal and "..totalAvailableAllyTeamStorages.energy.." energy.")
	end

	if preTaxValue.metal == 0 then
		--Echo("No more metal to process")
		preTaxValue.metal = nil
	end
	if preTaxValue.energy == 0 then
		--Echo("No more energy to process")
		preTaxValue.energy = nil
	end

	for resType, excess in pairs(preTaxValue) do
		if totalAvailableAllyTeamStorages[resType] <= 0 then
			--Echo("Available storage for ally team "..allyTeam.." was null.")
			for _, teamID in pairs(Spring.GetTeamList(allyTeam)) do
				local resExcessed = teamOverflowedLastFrame[teamID][resType]
				--Echo("Logging "..resExcessed.." "..resType.." as team "..teamID.." excessed resources.")
				AdjustTeamResourceStats(teamID, resType, "e", resExcessed)
				preTaxValue[resType] = nil
				teamOverflowedLastFrame[teamID][resType] = 0
			end
		end
		allyTeamOverflowedLastFrame[allyTeam][resType] = 0
	end

	--Echo("Attempting to apply leak if non zero.")
	
	for resType, excess in pairs(preTaxValue) do
		--Echo("Processing "..excess.." "..resType..".")
		local postTaxValue = excess * (1 - sharing_tax)
		--Echo("Post tax value is ".. postTaxValue.." "..resType..".")
		local percent = math.min(1, postTaxValue / totalAvailableAllyTeamStorages[resType])
		--Echo("The share percent is "..(percent*100).."%.")
		local SharedAmount = 0
		
		for _, teamID in pairs(Spring.GetTeamList(allyTeam)) do
			local aftTaxAmount = percent * availableTeamStorage[teamID][resType]
			local preTaxAmount = aftTaxAmount / (1 - sharing_tax)
			--Echo("Team "..teamID.." receives "..aftTaxAmount.." "..resType..".")
			AddResourceRaw(teamID, resType, aftTaxAmount)
			AdjustTeamResourceStats(teamID, resType, "r", aftTaxAmount)
			SharedAmount = SharedAmount + preTaxAmount
			--Echo(preTaxAmount.." "..resType.." was just sent, a total of "..SharedAmount..".")
		end
		
		local percentShared = SharedAmount / excess
		--Echo("The percent of shared resources / excess was "..(percentShared*100).."%.")
		for _, teamID in pairs(Spring.GetTeamList(allyTeam)) do
			local resSent = percentShared * teamOverflowedLastFrame[teamID][resType]
			local resExcessed = (1 - percentShared) * teamOverflowedLastFrame[teamID][resType]
			--Echo("Logging ".. resSent.." "..resType.." as sent from team ".."teamID.")
			--Echo("Logging ".. resExcessed.." "..resType.." as excessed from team ".."teamID.")
			AdjustTeamResourceStats(teamID, resType, "e", resExcessed)
			AdjustTeamResourceStats(teamID, resType, "s", resSent)
			teamOverflowedLastFrame[teamID][resType] = 0
		end
		allyTeamOverflowedLastFrame[allyTeam][resType] = 0
	end
	--Echo("Processed the leak for allyTeam "..allyTeam.."." )
end
	
function gadget:AllowResourceLevel(teamID)
	Spring.SetTeamShareLevel(teamID, "metal", 1.0)
	Spring.SetTeamShareLevel(teamID, "energy", 1.0)
	return false
end
