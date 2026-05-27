--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "ff",
		desc = "ff",
		author = "ff",
		date = "ff",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local passengerArmorType = 0
for k,v in pairs (Game.armorTypes) do
	if v == "passengers" then
		passengerArmorType = k
		break
	end
end

local transporters = {}
local passengers = {}

local function RemoveDamages(unitID)
	Spring.SetUnitBlocking(unitID, _, _,false, false)
end

local function RestoreDamages(unitID)
	Spring.SetUnitBlocking(unitID, _, _,true, true)
end

function gadget:UnitLoaded(passengerID, passengerDefID, passengerTeam, transporterID, transportTeam)
	transporters[passengerID] = transporterID
	passengers[transporterID] = passengers[transporterID] or {}
	table.insert(passengers[transporterID], passengerID)
	RemoveDamages(passengerID)
end

function gadget:UnitUnloaded(passengerID, passengerDefID, passengerTeam, transporterID, transportTeam)
	transporters[passengerID] = nil
	if passengers[transporterID] then
		for i, id in ipairs(passengers[transporterID]) do
			if id == passengerID then
				table.remove(passengers[transporterID], i)
				break
			end
		end
	end
	RestoreDamages(passengerID)
end

function gadget:UnitPreDamaged(unitID, unitDefID, teamID, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeamID)
	if transporters[unitID] then
		return 0
	end
	if passengers[unitID] and #passengers[unitID] > 0 then
		local transporterID = unitID
		if paralyzer then
			return damage, paralyzer
		end
		for i = 1, #passengers[transporterID] do
			local passengerID = passengers[transporterID][i]
			if weaponDefID and WeaponDefs[weaponDefID] then
				local damagesArray = WeaponDefs[weaponDefID].damages
				if damagesArray then
					local transporterArmorType = UnitDefs[Spring.GetUnitDefID(transporterID)].armorType
					local transporterToPassengerMult = damagesArray[passengerArmorType] / damagesArray[transporterArmorType]
					local passengerDamage = damage * transporterToPassengerMult
					local newHealth = Spring.GetUnitHealth(passengerID) - passengerDamage
					if newHealth > 0 then
						Spring.SetUnitHealth(passengerID, newHealth)
					else
						Spring.DestroyUnit(passengerID, true, false, attackerID)
					end
				end
			end
		end
		return damage		
	end
	return damage, paralyzer
end
