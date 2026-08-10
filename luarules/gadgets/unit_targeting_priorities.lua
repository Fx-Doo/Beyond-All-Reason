local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = 'Targeting Priorities',
		desc = '',
		author = 'Doo', --additions wilkubyk
		version = 'v1.0',
		date = 'May 2018',
		license = 'GNU GPL, v2 or later',
		layer = -1, --must run before game_initial_spawn, because game_initial_spawn must control the return of GameSteup
		enabled = true
	}
end

if gadgetHandler:IsSyncedCode() then
	local UPDATE_RATE = 1
	local DoomHandlerClass = VFS.Include("luarules/gadgets/doomstack/handler.lua")
	local DoomHandlers = {}        -- [allyTeam] = handler instance
	local projectileAllyTeam = {} -- [proID] = allyTeam, for routing ProjectileDestroyed
	local unitAllyTeam = {}       -- [unitID] = allyTeam cache (needed for UnitDestroyed)
	local OVERKILL_MODE = 2 -- 0: none, 1: hp%damagePerShot ~= 0 (further = bad), 2: hp - damagePerShot < 0 (further = bad)
	local PRIORITIES_UNDO_POWER = 1 -- 0: no undo, ]0;1]: undo partial or complete undo
	for wDefID, wDef in pairs(WeaponDefs) do
		local dumbness = tonumber(wDef.customParams.dumbness or 0.5) -- [0,1] 0: full penalty, 1: no penalty
		local damagesTable = wDef.damages
		local damagesPerShotTable = {}
		local damageMultTable = {}
		-- beam weapons (non-burst) override salvoSize at runtime: salvoSize = beamtime * GAME_SPEED
		-- salvoDamageMult = 1/salvoSize is also applied, so effective damage per shot = damage/salvoSize
			local salvoSize = 1
			if wDef.type == "BeamLaser" then
				salvoSize = (not wDef.beamburst and wDef.beamtime and wDef.beamtime > 0)
				and math.max(1, math.floor(wDef.beamtime * 30))
				or (wDef.salvoSize or 1)
			else
				salvoSize = wDef.salvoSize or 1
			end
		local salvoDamageMult = (not wDef.beamburst and wDef.beamtime and wDef.beamtime > 0) and (1 / salvoSize) or 1

		for armorType, damage in pairs(damagesTable) do
			damagesPerShotTable[armorType] = math.max(1, damage * salvoDamageMult * salvoSize) -- = damage for beams, damage*salvoSize for normal
			damageMultTable[armorType] = damagesPerShotTable[armorType] / damagesPerShotTable[1]
		end
		local reloadFrames = math.max(1, math.floor(wDef.reload * 30 + 0.5))
		local secDamage = (damagesTable[0] or 0) * salvoSize * 30 / reloadFrames  -- matches engine: weaponDmg->GetDefault() * salvoSize / reloadTime * GAME_SPEED
		local overKillMults = {}
		for unitDefID, unitDef in pairs(UnitDefs) do
			local maxHealth = unitDef.health
			local armorType = unitDef.armorType
			local shotsToKill = maxHealth / damagesPerShotTable[armorType] 
			overKillMults[1] = math.ceil(shotsToKill) / shotsToKill -- = 1 for shotsToKill == ceil(shotsToKill), else rises with hp%damagePerShot ~= 0
			overKillMults[2] = 1 + (2*(1 - dumbness)/(1+dumbness)) * (1 - (shotsToKill < 1 and shotsToKill or 1)) -- dumbness=1: no overkill penalty; dumbness=0: full penalty [1,2]; at dumbness=0 switchRange=range/3 for shotsToKill=0.5
			local invPowerMult = math.max(0.0001,damagesTable[armorType]) * unitDef.power -- cancels engine's /= (damageMul * power); curArmorMultiple ignored (runtime)
			local invHealthMult = 1/(secDamage + maxHealth)
			local hitChance = 1
			
			-- Determine if weapon is ballistic (cannon, laser, non-tracking missile)
			-- and should apply hitChance penalty based on target mobility vs projectile flight time
			local isBallistic = wDef.type ~= "BeamLaser" and not wDef.tracks
			
			if isBallistic then
				-- Use weapon range as separation and target max speed for static defense-time calculation
				local sep = wDef.range
				local targetSpeed = unitDef.speed / 30  -- max speed in elmos/frame
				local projectileSpeed = wDef.projectilespeed or 0
				local eta = projectileSpeed > 0 and sep / projectileSpeed or 0
				local predictBoost = wDef.customParams.predictBoost or 0
				local currentBoost = math.max(1, (1 - predictBoost) * targetSpeed)
				
				-- High-trajectory weapons take significantly longer to reach target
				if wDef.highTrajectory then
					eta = eta * 2
				end
				
				-- Starburst launchers have extreme eta penalty (massive arc)
				if wDef.type == "StarburstLauncher" then
					eta = eta * 5000
				end
				
				local accuracy = wDef.accuracy or 1.0
				local aoe = wDef.damageAreaOfEffect or 0
				
				-- Hit chance: inversely proportional to how far target can move during projectile flight
				hitChance = targetSpeed > 0 and aoe / (targetSpeed * eta) or 1
				hitChance = math.min(1.0, hitChance / (currentBoost * accuracy))
			end
			
			local range = wDef.range
			local invRangeMult = 1/(range * 0.4 + 100)
			local undoStuff = invPowerMult * invHealthMult * invRangeMult / hitChance
			Spring.SetWeaponDefToUnitDefPriorityMult(wDefID, unitDefID, undoStuff * (overKillMults[OVERKILL_MODE] or undoStuff)) 
		end
	end


	local currentTargets = {} -- {[attackerID] = {targetID=, weaponNum=}} -- only the lowest-weaponNum target is tracked

	local function GetHandler(unitID)
		local at = unitAllyTeam[unitID] or Spring.GetUnitAllyTeam(unitID)
		return at and DoomHandlers[at]
	end

	function gadget:Initialize()
		for _, allyTeam in ipairs(Spring.GetAllyTeamList()) do
			DoomHandlers[allyTeam] = DoomHandlerClass:New(allyTeam)
		end
		for _, unitID in ipairs(Spring.GetAllUnits()) do
			local unitAT = Spring.GetUnitAllyTeam(unitID)
			unitAllyTeam[unitID] = unitAT
			for allyTeam, handler in pairs(DoomHandlers) do
				if allyTeam == unitAT then handler:OwnerCreated(unitID)
				else                       handler:TargetCreated(unitID) end
			end
		end
		for wDefID in pairs(WeaponDefs) do
			Script.SetWatchWeapon(wDefID, true)
		end
	end

	function gadget:UnitCreated(unitID, unitDefID)
		local unitAT = Spring.GetUnitAllyTeam(unitID)
		unitAllyTeam[unitID] = unitAT
		for allyTeam, handler in pairs(DoomHandlers) do
			if allyTeam == unitAT then handler:OwnerCreated(unitID)
			else                       handler:TargetCreated(unitID) end
		end
	end

	function gadget:UnitDestroyed(unitID, unitDefID)
		local unitAT = unitAllyTeam[unitID]
		for allyTeam, handler in pairs(DoomHandlers) do
			if allyTeam == unitAT then handler:OwnerDestroyed(unitID)
			else                       handler:TargetDestroyed(unitID) end
		end
		currentTargets[unitID] = nil
		unitAllyTeam[unitID] = nil
	end

	function gadget:AllowWeaponTargetCheck(attackerID, attackerWeaponNum, attackerWeaponDefID)
		if whileupdate then return false end
		local states = Spring.GetUnitStates(attackerID)
		if states and states["firestate"] <= 1 then return false end
		RemoveCurrentTarget(attackerID, attackerWeaponNum)
		local handler = GetHandler(attackerID)
		if handler then handler:WeaponRequestsTarget(attackerID, attackerWeaponNum, attackerWeaponDefID) end
		return true, false, true  -- keepWatching=true: AllowWeaponTarget fires per-target so TestWeaponTarget can veto already-committed targets
	end

	function gadget:UnitAutoTargetRange(attackerID, range)
		local states = Spring.GetUnitStates(attackerID)
		if states and states["movestate"] == 0 then return 0 end
		local unitDefID = Spring.GetUnitDefID(attackerID)
		local weapons = UnitDefs[unitDefID].weapons
		local handler = GetHandler(attackerID)
		for k,v in pairs(weapons) do
			RemoveCurrentTarget(attackerID, k)
			if handler then handler:WeaponRequestsTarget(attackerID, k, v.weaponDef) end
		end
		return 0
	end

	function gadget:AllowWeaponTarget(attackerID, targetID, attackerWeaponNum, attackerWeaponDefID, defPriority)
		if defPriority then
			return true, defPriority
		end
		local handler = GetHandler(attackerID)
		local allowed = not handler or handler:TestWeaponTarget(targetID)
		if allowed then
			if handler then handler:WeaponTarget(attackerID, attackerWeaponNum, attackerWeaponDefID, targetID) end
			RegisterCurrentTarget(attackerID, attackerWeaponNum, targetID)
		end
		return allowed
	end

	function RemoveCurrentTarget(attackerID, attackerWeaponNum)
		local cur = currentTargets[attackerID]
		if cur and cur.weaponNum < attackerWeaponNum then
			Spring.SetUnitToTargetUnitPriorityMult(attackerID, cur.targetID, 1)
			currentTargets[attackerID] = nil
		end
	end

	function RegisterCurrentTarget(attackerID, attackerWeaponNum, targetID)
		if not targetID then return end
		-- Guard: Don't modify multiplier if this unit has priority targets set by user
		-- (indicated by has_priority_targets rules param)
		local hasPriorityTargets = Spring.GetUnitRulesParam(attackerID, "has_priority_targets")
		if hasPriorityTargets and hasPriorityTargets > 0 then
			return  -- Skip modifying multiplier for priority-target units
		end
		
		local cur = currentTargets[attackerID]
		if cur and attackerWeaponNum > cur.weaponNum then return end -- higher weaponNum can't override a lower one
		if cur then
			Spring.SetUnitToTargetUnitPriorityMult(attackerID, cur.targetID, 1)
		end
		currentTargets[attackerID] = {targetID = targetID, weaponNum = attackerWeaponNum}
		Spring.SetUnitToTargetUnitPriorityMult(attackerID, targetID, 1)
	end

	function gadget:WeaponChangedTarget(attackerID, attackerDefID, attackerTeam, weaponNum, weaponDefID, oldTargetData, newTargetData)
		local targetID = newTargetData and newTargetData[2] == string.byte('u') and newTargetData[1]
		RegisterCurrentTarget(attackerID, weaponNum, targetID)
		local handler = GetHandler(attackerID)
		if handler then handler:WeaponTarget(attackerID, weaponNum, weaponDefID, targetID) end
	end

	function gadget:GameFramePost(f)
		if f%UPDATE_RATE == 0 then
			for _, handler in pairs(DoomHandlers) do
				handler:Update(UPDATE_RATE)
			end
		end
	end

	function gadget:ProjectileCreated(projID, projOwnerID, weaponDefID)
		if not projOwnerID or projOwnerID < 0 then return end
		local allyTeam = Spring.GetUnitAllyTeam(projOwnerID)
		local handler = allyTeam and DoomHandlers[allyTeam]
		if handler then
			projectileAllyTeam[projID] = allyTeam
			handler:ProjectileCreated(projID, projOwnerID, weaponDefID)
		end
	end

	function gadget:ProjectileDestroyed(projID)
		local allyTeam = projectileAllyTeam[projID]
		if allyTeam then
			DoomHandlers[allyTeam]:WeaponReached(projID)
			projectileAllyTeam[projID] = nil
		end
	end

	function gadget:UnitDamaged(unitID)
		local unitAT = unitAllyTeam[unitID]
		for allyTeam, handler in pairs(DoomHandlers) do
			if allyTeam ~= unitAT then handler:TargetDamaged(unitID) end
		end
	end
else
	return
end