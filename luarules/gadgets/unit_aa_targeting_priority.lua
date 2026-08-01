local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = 'Targeting Priority',
		desc = '',
		author = 'Doo', --additions wilkubyk
		version = 'v1.0',
		date = 'May 2018',
		license = 'GNU GPL, v2 or later',
		layer = -1, --must run before game_initial_spawn, because game_initial_spawn must control the return of GameSteup
		enabled = false
	}
end
if true then
	return false
end
if gadgetHandler:IsSyncedCode() then

	-- Collect weaponDef names used as unit death/self-destruct explosions — skip these.
	local explosionWeaponNames = {}
	for _, ud in pairs(UnitDefs) do
		if ud.deathExplosion        then explosionWeaponNames[ud.deathExplosion]        = true end
		if ud.selfDestructExplosion then explosionWeaponNames[ud.selfDestructExplosion] = true end
	end

	local function IsAutoTargetWeapon(wDef)
		if explosionWeaponNames[wDef.name] then return false end
		if wDef.isShield   then return false end
		if wDef.manualfire then return false end
		if wDef.range < 64 then return false end
		return true
	end

	-- ──────────────────────────────────────────────────────────────────────────
	-- Tuning parameters
	--
	-- Two per-weapon malus values plus a physics-based hit-chance score:
	--
	--   highHPMalus  – aversion to overshooting: dmg >> hp (overkill / splash waste).
	--                  exp(-max(0, log(dmg/hp)) * highHPMalus) per unit.
	--   lowHPMalus   – aversion to undershooting: hp >> dmg (too tanky to kill).
	--                  exp(-max(0, log(hp/dmg)) * lowHPMalus) per unit.
	--   hitChanceMult – proportional hit quality Q ∈ (0,1] per (weapon × unit).
	--                   Derived from weapon category, error terms, AoE, and target radius.
	-- ──────────────────────────────────────────────────────────────────────────
	local cfg = {
		-- highHPMalus: how strongly a weapon avoids overkilling weak targets (dmg >> hp).
		-- A high commit window means wasted reload on a target that needed only a
		-- fraction of the damage. Beam hold-time and burst lock raise the window;
		-- sweepFire partially mitigates because the area is covered regardless.
		highHP = {
			malusPerSecond = 0.1,  -- commitTime (s) × this = malus exponent rate
			beamWeight     = 1,  -- beam hold-time (s) contribution to commit window
			beamSweepScale = 0.1,  -- sweepFire halves the beam commitment
			burstWeight    = 0.1,  -- (burst-1)*burstRate (s) contribution to commit window
		},
		-- lowHPMalus: how strongly a weapon avoids undershooting tanky targets (hp >> dmg).
		-- AOE weapons with high edgeEffectiveness waste the most splash on over-HP targets.
		-- Non-AOE or zero-edge weapons get 0 automatically; fast reload reduces the cost.
		lowHP = {
			weight    = 0.04,  -- log(1 + aoeRadius × edgeEffectiveness) × reloadTime × this
			minRadius = 32,    -- AOE below this is treated as zero (collision geometry noise)
		},
		-- Range-threat bonus: applied when a target unit's best weapon range exceeds our range.
		-- Scales with the unit's DPS so long-range scouts matter less than long-range snipers.
		threat = {
			rangeWeight = 0.001,  -- (unitRange/weaponRange - 1) * unitBestDPS * this → additive bonus
		},
		-- selfPower: drives SetUnitDefSelfPriorityMult — a global "how impactful is this unit" score.
		-- combat = bestDPS × log(1+maxRange); build and intel are scaled against it.
		selfPower = {
			buildWeight = 0.5,   -- build contribution (buildSpeed × log(1+buildRange)) relative to combat
			radarWeight = 0.5,   -- per-elmo radar radius contribution
			losWeight   = 0.1,   -- per-elmo LOS radius contribution
		},
	}
	local TAANG2RAD = 2 * math.pi / 65536   -- COB angle units → radians

	-- Precompute per-unit combat capability (best DPS + max weapon range).
	-- Used for the range-threat bonus in per-weapon scoring and for SetUnitDefSelfPriorityMult.
	local unitCombatData = {}
	for uID, uDef in pairs(UnitDefs) do
		local bestDPS  = 0
		local maxRange = 0
		for _, wSlot in ipairs(uDef.weapons or {}) do
			local wd = WeaponDefs[wSlot.weaponDef]
			if wd then
				local dps   = math.max(wd.damages[0] or 1, 1) * math.max(wd.burst or 1, 1)
				            / math.max(wd.reload, 0.033)
				local range = wd.range or 0
				if dps   > bestDPS  then bestDPS  = dps   end
				if range > maxRange then maxRange = range  end
			end
		end
		unitCombatData[uID] = { bestDPS = bestDPS, maxRange = maxRange }
	end

	for wID, wDef in pairs(WeaponDefs) do
		if IsAutoTargetWeapon(wDef) then
		
		local projectileSpeed = wDef.projectilespeed
		local reloadTime      = math.max(wDef.reload, 0.033)
		local damage          = math.max(wDef.damages[0] or 1, 1)
		local burst           = math.max(wDef.burst    or 1, 1)
		local burstRate       = wDef.burstRate or 0   -- seconds between shots in burst
		local beamTime        = wDef.beamTime  or 0   -- seconds
		local sweepFire       = wDef.sweepFire or false

		-- Total damage committed per firing cycle (all burst shots).
		local dmgPerBurst = damage * burst

		-- ── highHPMalus ───────────────────────────────────────────────────────
		-- Commit window: time the weapon is locked to a target per cycle.
		-- Beam: holds lock for beamTime (sweepFire covers area → reduced commitment).
		-- Burst: fires all shots before it can retarget.
		local beamCommit  = beamTime * (sweepFire and cfg.highHP.beamSweepScale or 1.0)
		                             * cfg.highHP.beamWeight
		local burstCommit = (burst - 1) * burstRate * cfg.highHP.burstWeight
		local commitTime  = reloadTime + beamCommit + burstCommit
		local highHPMalus = commitTime * cfg.highHP.malusPerSecond

		-- ── lowHPMalus ────────────────────────────────────────────────────────
		-- AOE weapons waste splash on targets that die to a fraction of their damage.
		-- edgeEffectiveness controls how much the outer ring contributes to waste.
		-- Fast-reloading weapons care less (can fire again quickly).
		local aoeRadius         = wDef.damageAreaOfEffect or 0
		local edgeEffectiveness = wDef.edgeEffectiveness  or 0
		local effectiveAOE      = aoeRadius >= cfg.lowHP.minRadius and aoeRadius or 0
		local lowHPMalus        = math.log(1 + effectiveAOE * edgeEffectiveness)
		                        * reloadTime * cfg.lowHP.weight

		-- ── hit-chance error precomputation ──────────────────────────────────
		-- Three weapon categories drive different E_total formulas:
		--   HITSCAN  (BeamLaser / LightningCannon): t_flight ≈ 0, no lead error.
		--   HOMING   (tracks=true, projectileSpeed>0): binary on turnRate sufficiency.
		--   DUMB     (everything else): lead error = full v*t_flight (direction changes).
		-- E_total = 1-sigma miss radius in elmos; Q = weighted hit quality ∈ (0,1].
		local wType     = wDef.type or ""
		local isHitscan = wType == "BeamLaser" or wType == "LightningCannon"
		local isHoming  = (not isHitscan) and (wDef.tracks or false) and (projectileSpeed > 0)
		local wRange    = math.max(wDef.range or 0, 1)
		-- Q is evaluated at half max-range so the hit-quality score spans the same
		-- proportional gradient as rangeMul(d). proximityPriority is clamped to
		-- [-1, +10] by alldefs_post.lua (no C++ clamp); the full range is now used.
		local wRangeQ   = wRange * 0.5
		-- Angular spread projected to typical engagement distance
		local E_angular = ((wDef.accuracy or 0) + (wDef.sprayAngle or 0)) * wRangeQ
		-- Movement tracking error rate: multiply by unitSpeed later
		local tme       = wDef.targetMoveError or 0
		-- Homing-specific precomputes
		local omega     = (wDef.turnRate or 0) * TAANG2RAD / 30      -- rad/frame
		local E_wobble  = (wDef.wobble   or 0) * TAANG2RAD / 30 * wRangeQ  -- elmos
		local E_dance   = (wDef.dance    or 0) / 30                  -- elmos
		local wUptime   = (wDef.uptime   or 0)                       -- seconds

		-- ── Per-unit scoring ──────────────────────────────────────────────────
		local raw = {}
		for uID, uDef in pairs(UnitDefs) do
			local hp        = math.max(uDef.health, 1)
			local unitSpeed = uDef.speed or 0

			-- Asymmetric log-space tent centred on dmgPerBurst:
			--   logRatio < 0  → dmg > hp (overshoot / overkill) → highHPMalus decays score
			--   logRatio > 0  → hp > dmg (undershoot / too tanky) → lowHPMalus decays score
			local logRatio   = math.log(hp) - math.log(dmgPerBurst)

			-- ── hitChanceScore (Q) ─────────────────────────────────────────────
			-- E_total: combined 1-sigma miss radius given target speed and weapon type.
			-- unitSpeed (uDef.speed) is in elmos/sec; projectileSpeed in elmos/frame.
			local r_unit = math.max(uDef.radius or 1, 1)
			local v      = unitSpeed   -- elmos/sec

			local E_total
			if isHitscan then
				-- No flight time: angular spread + movement tracking error only.
				E_total = math.sqrt(E_angular^2 + (tme * v)^2)
			elseif isHoming then
				-- Binary: can missile recover from 90° direction change within r_unit+aoeRadius?
				local r_eff = math.max(r_unit + aoeRadius, 1)
				local tracking_ok = omega * r_eff > (v / 30) * (math.pi / 2)
				if tracking_ok then
					local E_startup = 0
					if wUptime > 0 and projectileSpeed > 0 then
						-- During ascent missile doesn't home; homing phase corrects drift.
						local t_homing  = math.max(wRangeQ / projectileSpeed - wUptime * 30, 0)
						local corrected = math.min(omega * t_homing / (math.pi / 2), 1)
						E_startup = v * wUptime * (1 - corrected)
					end
					E_total = math.sqrt(E_wobble^2 + E_dance^2 + E_startup^2)
				else
					-- Insufficient tracking: fall back to dumb-fire.
					local E_lead = v / 30 * (wRangeQ / math.max(projectileSpeed, 0.01))
					E_total = math.sqrt(E_angular^2 + (tme * v)^2 + E_lead^2)
				end
			else
				-- Dumb-fire: direction changes make entire lead useless.
				local E_lead = v / 30 * (wRangeQ / math.max(projectileSpeed, 0.01))
				E_total = math.sqrt(E_angular^2 + (tme * v)^2 + E_lead^2)
			end
			E_total = math.max(E_total, 0.1)

			-- Weighted hit quality Q: Gaussian 2-D probability with AoE ring.
			-- aoeRadius used directly (consistent with lowHPMalus above).
			local hitChanceScore
			if aoeRadius > r_unit then
				local a  = math.exp(-(r_unit    / E_total)^2)
				local b  = math.exp(-(aoeRadius / E_total)^2)
				hitChanceScore = 1 - a * (1 - edgeEffectiveness) / 2
				               -     b * (1 + edgeEffectiveness) / 2
			else
				hitChanceScore = 1 - math.exp(-(r_unit / E_total)^2)
			end
			hitChanceScore = math.max(hitChanceScore, 1e-4)

			-- Discrete overkill efficiency: how much of the last salvo's damage is used.
			-- = 1.0 when hp is an exact multiple of dmgPerBurst (no waste),
			-- approaches 1/ceil(hp/dmg) → 0 when dmgPerBurst >> hp.
			local shotsToKill   = hp / dmgPerBurst
			local overkillScore = shotsToKill / math.ceil(shotsToKill)

			raw[uID] = hitChanceScore * overkillScore
		end
		for uID, v in pairs(raw) do
			-- The engine divides targetPriority by (damageMul × unit.power).
			-- Multiplying our mult by unit.power here causes the power terms to cancel,
			-- so the final priority is independent of unit.power (damageMul still applies).
			local power = math.max((UnitDefs[uID].power or 1), 1e-4)
			--Spring.Echo(WeaponDefs[wID].name, UnitDefs[uID].name, 0.999*power / math.max(v, 1e-4))
			Spring.SetWeaponDefToUnitDefPriorityMult(wID, uID, 0.999*power / math.max(v, 1e-4)) -- cancel most of the power's mult
		end

		end -- IsAutoTargetWeapon
	end

	-- ── Empirical proximityPriority calibration ─────────────────────────────
	-- For each weapon, find the proximityPriority that makes rangeMul(d) × Q(d)
	-- as flat as possible over 10 distance samples (0.1R … 1.0R), averaged over
	-- all mobile UnitDefs. rangeMul(d) = d*PP + R*0.4+100 (from GenerateWeaponTargets).
	-- Minimize: CV = std(rangeMul*Q) / mean(rangeMul*Q)  over PP in [0, 4].
	do
		local function computeQ_at_dist(wDef, uDef, d)
			local ps      = math.max(wDef.projectilespeed or 0, 0.01)
			local wt      = wDef.type or ""
			local hitscan = wt == "BeamLaser" or wt == "LightningCannon"
			local homing  = (not hitscan) and (wDef.tracks or false)
			              and (wDef.projectilespeed or 0) > 0

			local acc   = wDef.accuracy        or 0
			local spray = wDef.sprayAngle      or 0
			local tme_  = wDef.targetMoveError or 0
			local om    = (wDef.turnRate or 0) * TAANG2RAD / 30
			local Ew    = (wDef.wobble   or 0) * TAANG2RAD / 30 * d
			local Ed    = (wDef.dance    or 0) / 30
			local upt   = (wDef.uptime   or 0)
			local aoe_  = (wDef.damageAreaOfEffect or 0)
			local ee_   = wDef.edgeEffectiveness   or 0

			local r_u   = math.max(uDef.radius or 1, 1)
			local v_    = uDef.speed or 0
			local Ea    = (acc + spray) * d
			local Et

			if hitscan then
				Et = math.sqrt(Ea^2 + (tme_ * v_)^2)
			elseif homing then
				local r_eff = math.max(r_u + aoe_, 1)
				if om * r_eff > (v_ / 30) * (math.pi / 2) then
					local E_start = 0
					if upt > 0 then
						local t_h  = math.max(d / ps - upt * 30, 0)
						local corr = math.min(om * t_h / (math.pi / 2), 1)
						E_start = v_ * upt * (1 - corr)
					end
					Et = math.sqrt(Ew^2 + Ed^2 + E_start^2)
				else
					local El = v_ / 30 * (d / ps)
					Et = math.sqrt(Ea^2 + (tme_ * v_)^2 + El^2)
				end
			else
				local El = v_ / 30 * (d / ps)
				Et = math.sqrt(Ea^2 + (tme_ * v_)^2 + El^2)
			end
			Et = math.max(Et, 0.1)

			local Q
			if aoe_ > r_u then
				local a = math.exp(-(r_u  / Et)^2)
				local b = math.exp(-(aoe_ / Et)^2)
				Q = 1 - a * (1 - ee_) / 2 - b * (1 + ee_) / 2
			else
				Q = 1 - math.exp(-(r_u / Et)^2)
			end

			-- Damage falloff with distance: BeamLaser intensity drops linearly from
			-- 1.0 at point-blank to minIntensity at max range.
			-- dmgRatio(d) = max(minIntensity, 1 - d / range)
			local dmgRatio = 1.0
			if wt == "BeamLaser" then
				local R_ = math.max(wDef.range or 1, 1)
				dmgRatio = math.max(wDef.minIntensity or 0, 1.0 - d / R_)
			end

			return math.max(Q * dmgRatio, 1e-6)
		end

		-- Collect mobile UnitDefs
		local mobileUDefs = {}
		for _, uDef in pairs(UnitDefs) do
			if (uDef.speed or 0) > 0 then
				mobileUDefs[#mobileUDefs + 1] = uDef
			end
		end
		local nMobile = math.max(#mobileUDefs, 1)

		local proximityPriorities = {}
		local N_DIST = 10
		-- alldefs_post.lua clamps proximitypriority to [-1, 10]; no further C++ clamp exists.
		-- Search the full usable range with enough resolution.
		local PP_STEP, PP_MAX = 0.1, 10.0

		for wID, wDef in pairs(WeaponDefs) do
			if IsAutoTargetWeapon(wDef) then
				local R = math.max(wDef.range or 1, 1)
				local C = R * 0.4 + 100  -- constant part of rangeMul

				-- Average Q(d_i) across mobile units at each sample
				local avgQ = {}
				for i = 1, N_DIST do avgQ[i] = 0 end
				for _, uDef in ipairs(mobileUDefs) do
					for i = 1, N_DIST do
						avgQ[i] = avgQ[i] + computeQ_at_dist(wDef, uDef, i / N_DIST * R)
					end
				end
				for i = 1, N_DIST do avgQ[i] = avgQ[i] / nMobile end

				-- Grid-search PP minimising CV of rangeMul(d)*Q(d)
				local bestPP, bestCV = 0.0, math.huge
				local pp = 0.0
				while pp <= PP_MAX + 1e-9 do
					local sum, sumSq = 0, 0
					for i = 1, N_DIST do
						local p = (i / N_DIST * R * pp + C) * avgQ[i]
						sum   = sum   + p
						sumSq = sumSq + p * p
					end
					local mean = sum / N_DIST
					local cv   = math.sqrt(math.max(sumSq / N_DIST - mean * mean, 0))
					           / math.max(mean, 1e-9)
					if cv < bestCV then bestCV = cv ; bestPP = pp end
					pp = pp + PP_STEP
				end

				proximityPriorities[wDef.name] = bestPP
			end
		end

	end

	-- ── AimAdjustPriority calibration ───────────────────────────────────────────
	do
		local PI = math.pi
		local function fitAimAdjust(R)
			if R <= 0 then return 0 end
			local N, phi = 36, (math.sqrt(5) + 1) / 2
			local function sse(p)
				local err = 0
				for i = 0, N do
					local T = math.max(1, 180 * i / (N * R))
					local E = (1 + p * (1 - math.cos(PI * i / N)))^2
					local d = E - T; err = err + d * d
				end
				return err
			end
			local lo, hi = 0, 20
			for _ = 1, 60 do
				local c = hi-(hi-lo)/phi; local d = lo+(hi-lo)/phi
				if sse(c) < sse(d) then hi = d else lo = c end
			end
			return math.max(0, (lo + hi) / 2)
		end

		local aimAdjust = {}   -- aimAdjust[unitDefName][wNum] = p
		for _, uDef in pairs(UnitDefs) do
			local cp = uDef.customParams or {}
			for wNum, wSlot in ipairs(uDef.weapons or {}) do
				local turretY = tonumber(cp["wpn" .. wNum .. "turrety"])
				if turretY and turretY > 0 then
					local wDef = WeaponDefs[wSlot.weaponDef]
					if wDef then
						local reload = math.max(wDef.reloadtime or 0.033, 0.033) * 30
						Spring.Echo("reloadtime raw", uDef.name, wNum, wDef.reloadtime, "reload=", reload)
						local name = uDef.name
						if not aimAdjust[name] then aimAdjust[name] = {} end
						aimAdjust[name][wNum] = fitAimAdjust(turretY * reload)
					end
				end
			end
		end

		Spring.Echo(aimAdjust)
	end
	-- ─────────────────────────────────────────────────────────────────────────

	-- Free working data
	cfg                  = nil
	explosionWeaponNames = nil
	unitCombatData       = nil

	local doomStack = {} -- { [attackerID] = { [weaponNum] = {["targetID"] = targetID, ["value"] = value}} }
	local stackedDoom = {} -- {[targetID] = value}
	local function ClearDoomStack(attackerID, attackerWeaponNum)
		if doomStack[attackerID] and doomStack[attackerID][attackerWeaponNum] then
			local targetID = doomStack[attackerID][attackerWeaponNum]["targetID"]
			local value = doomStack[attackerID][attackerWeaponNum]["value"]
			if not targetID or not value then return end
			if value ~= 0 then
				stackedDoom[targetID] = stackedDoom[targetID] / value
			else
				stackedDoom[targetID] = 1
			end
			--Spring.Echo(stackedDoom[targetID])
			doomStack[attackerID][attackerWeaponNum]["targetID"] = nil
			doomStack[attackerID][attackerWeaponNum]["value"] = 1
			Spring.SetSelfPriorityMult(targetID, stackedDoom[targetID] < 100 and stackedDoom[targetID] or 0)
		end
	end

<<<<<<< Updated upstream
	-- AllowWeaponTarget is only called for weapons with SetWatchAllowTarget (vtol-targeting),
	-- so the attacker always has AA priority — no need to check hasPriorityAir or call
	-- spGetUnitDefID on the attacker.
	function gadget:AllowWeaponTarget(unitID, targetID, attackerWeaponNum, attackerWeaponDefID, defPriority)
		local mult = airPriorityMultiplier[spGetUnitDefID(targetID)]
		if mult then
			return true, (defPriority or 1.0) * mult
=======
	local function RegisterDoomStack(attackerID, attackerWeaponNum, targetID, value)
		if doomStack[attackerID] and doomStack[attackerID][attackerWeaponNum] then
			doomStack[attackerID][attackerWeaponNum]["targetID"] = targetID
			doomStack[attackerID][attackerWeaponNum]["value"] = value
			stackedDoom[targetID] = (stackedDoom[targetID] or 1) * value
			Spring.SetSelfPriorityMult(targetID, stackedDoom[targetID] < 100 and stackedDoom[targetID] or 0)
>>>>>>> Stashed changes
		end
		return true
	end

	local currentTargets = {} -- {[attackerID] = {[attackerWeaponNum] = targetID}}

	function gadget:Initialize()
		for _, unitID in ipairs(Spring.GetAllUnits()) do
			stackedDoom[unitID] = 1
			doomStack[unitID] = {}
			local unitDefID = Spring.GetUnitDefID(unitID)
			for k,v in pairs(UnitDefs[unitDefID].weapons) do
				currentTargets[unitID] = currentTargets[unitID] or {}
				currentTargets[unitID][k] = nil 
				doomStack[unitID][k] = {["targetID"] = nil, ["value"] = 0}
			end
			Script.SetWatchAllowTargetUnit(unitID, true)
		end
	end

	function gadget:UnitCreated(unitID, unitDefID)
		Spring.Echo(unitDefID)
		stackedDoom[unitID] = 1
		doomStack[unitID] = {}
		for k,v in pairs(UnitDefs[unitDefID].weapons) do
			currentTargets[unitID] = currentTargets[unitID] or {}
			currentTargets[unitID][k] = nil
			doomStack[unitID][k] = {["targetID"] = nil, ["value"] = 1}
		end
		Script.SetWatchAllowTargetUnit(unitID, true)
	end

	function gadget:AllowWeaponTargetCheck(attackerID, attackerWeaponNum, attackerWeaponDefID)
		ClearDoomStack(attackerID, attackerWeaponNum)
		Script.SetWatchAllowTargetUnit(attackerID, false)
		return true
	end

	function gadget:UnitAutoTargetRange(attackerID, range)
		local unitDefID = Spring.GetUnitDefID(attackerID)
		local weapons = UnitDefs[unitDefID].weapons
		for k,v in pairs(weapons) do
			ClearDoomStack(attackerID, k)
		end
		return range
	end

	function gadget:AllowWeaponTarget(attackerID, targetID, attackerWeaponNum, attackerWeaponDefID)
		local allowed = (stackedDoom[targetID] or 1) < 100
		if allowed then
			RemoveCurrentTarget(attackerID, attackerWeaponNum)
			if targetID and targetID > 0 then
				local targetHealth = Spring.GetUnitHealth(targetID)
				local targetArmorDef = UnitDefs[Spring.GetUnitDefID(targetID)].armorType
				local salvoSize = WeaponDefs[attackerWeaponDefID].salvoSize or 1
				local burstSize = WeaponDefs[attackerWeaponDefID].burst or 1
				local weaponDamages = (WeaponDefs[attackerWeaponDefID].damages[targetArmorDef] or 1) * salvoSize * burstSize
				if targetHealth and weaponDamages then
					local sep = Spring.GetUnitSeparation(attackerID, targetID)
					local weaponRange = WeaponDefs[attackerWeaponDefID].range
					local sureKill = false
					local reloadDone = Spring.GetGameFrame() > Spring.GetUnitWeaponState(attackerID, attackerWeaponNum, "reloadFrame") - 15 -- last slow update before firing
					local value = 1
					if reloadDone and sep > weaponRange*0.3 and sep < weaponRange then
						local BeamWeapon = WeaponDefs[attackerWeaponDefID].type == "BeamLaser" or WeaponDefs[attackerWeaponDefID].type == "LightningCannon"
						local hitScanWeapon = BeamWeapon or WeaponDefs[attackerWeaponDefID].type == "Rifle"
						local hardHomeWeapon = WeaponDefs[attackerWeaponDefID].tracks
						local sureHitWeapon = hitScanWeapon or hardHomeWeapon
						sureKill = (weaponDamages >= targetHealth * 3) and sureHitWeapon
					end
					value = 1 + weaponDamages / targetHealth
					if sureKill then value = 100000 end
					RegisterDoomStack(attackerID, attackerWeaponNum, targetID, value)
				end
				RegisterCurrentTarget(attackerID, attackerWeaponNum, targetID)
			end
		end
		return allowed
	end

	function RemoveCurrentTarget(attackerID, attackerWeaponNum) 
		local curTargID = currentTargets[attackerID][attackerWeaponNum]
		if curTargID and curTargID > 0 then
			Spring.SetUnitToTargetUnitPriorityMult(attackerID, curTargID, 1)
		end
		currentTargets[attackerID][attackerWeaponNum] = nil
	end

	function RegisterCurrentTarget(attackerID, attackerWeaponNum, targetID)
		if not currentTargets[attackerID] then currentTargets[attackerID] = {} end
		currentTargets[attackerID][attackerWeaponNum] = targetID
		Spring.SetUnitToTargetUnitPriorityMult(attackerID, targetID, 0.6) -- bias towards currentTarget to avoid switching targets too often
	end

	function gadget:WeaponAutoTarget(attackerID, attackerWeaponNum, attackerWeaponDefID, targetID)
		RemoveCurrentTarget(attackerID, attackerWeaponNum)
		if targetID and targetID > 0 then
			local targetHealth = Spring.GetUnitHealth(targetID)
			local targetArmorDef = UnitDefs[Spring.GetUnitDefID(targetID)].armorType
			local salvoSize = WeaponDefs[attackerWeaponDefID].salvoSize or 1
			local burstSize = WeaponDefs[attackerWeaponDefID].burst or 1
			local weaponDamages = (WeaponDefs[attackerWeaponDefID].damages[targetArmorDef] or 1) * salvoSize * burstSize
			if targetHealth and weaponDamages then
				local sep = Spring.GetUnitSeparation(attackerID, targetID)
				local weaponRange = WeaponDefs[attackerWeaponDefID].range
				local sureKill = false
				local reloadDone = Spring.GetGameFrame() > Spring.GetUnitWeaponState(attackerID, attackerWeaponNum, "reloadFrame") - 15 -- last slow update before firing
				Spring.Echo("reloadTime", reloadDone)
				local value = 1
				if reloadDone and sep > weaponRange*0.3 then
					local BeamWeapon = WeaponDefs[attackerWeaponDefID].type == "BeamLaser" or WeaponDefs[attackerWeaponDefID].type == "LightningCannon"
					local hitScanWeapon = BeamWeapon or WeaponDefs[attackerWeaponDefID].type == "Rifle"
					local hardHomeWeapon = WeaponDefs[attackerWeaponDefID].tracks
					local sureHitWeapon = hitScanWeapon or hardHomeWeapon
					sureKill = (weaponDamages >= targetHealth * 3) and sureHitWeapon
				end
				value = 1 + weaponDamages / targetHealth
				if sureKill then value = 100000 end
				RegisterDoomStack(attackerID, attackerWeaponNum, targetID, value)
			end
			RegisterCurrentTarget(attackerID, attackerWeaponNum, targetID)
		end
		Script.SetWatchAllowTargetUnit(attackerID, true)
	end
else
	return
end
