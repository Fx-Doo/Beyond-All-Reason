local DoomHandler = {}

local DoomStack = VFS.Include("luarules/gadgets/doomstack/stack.lua")

function DoomHandler:Init()
    self.DOOM_IGNORE_THRESHOLD = 0 -- if totalDoomValue * 2 * DOOM_IGNORE_THRESHOLD > health, then ignore target
    self.DOOM_IGNORE_ENTERING_MULT = 3
    -- higher value = more stack candidates, then select lower values first to avoid overkill, but more processing time
    -- lower value can result in picking a single high value stack that would overkill by a large margin, but means smaller stackLists
    self.stacksByAttacker = {} -- [attackerID][weaponNum] = stack
    self.stacksByTarget = {} -- [targetID] = {stack1, stack2, ...}
    self.stackCounts = {} -- [targetID] = number of stacks targeting that unit
    self.targetStackedDoom = {} -- [targetID] = totalDoomValue  
    self.activeProjectiles = {} -- [proID] = {targetID, value}
    self.anticipatedDamages = {} -- [targetID] = totalDoomValue of active projectiles
    self.ignoredTargets = {} -- [targetID] = true if target is already marked as ignored/overkill
    self.representativeTeamID = nil -- teamID from allyTeam for CallAsTeam LOS-gated health queries
end

function DoomHandler:Kill()
    self.stacksByAttacker = nil
    self.stacksByTarget = nil
    self.stackCounts = nil
    self.targetStackedDoom = nil
    self.activeProjectiles = nil
    self.anticipatedDamages = nil
    self.ignoredTargets = nil
    DoomHandler = nil
end

function DoomHandler:OwnerCreated(unitID)
    -- Capture a representative teamID for LOS-gated health queries via CallAsTeam
    if not self.representativeTeamID then
        self.representativeTeamID = Spring.GetUnitTeam(unitID)
    end
    
    local unitDefID = Spring.GetUnitDefID(unitID)
    local weapons = UnitDefs[unitDefID].weapons
    self.stacksByAttacker[unitID] = self.stacksByAttacker[unitID] or {}
    for weaponNum, weapon in ipairs(weapons) do
        local weaponDefID = weapon.weaponDef
        local weaponDef = WeaponDefs[weaponDefID]
        if weaponDef and weaponDef.damages then
            local stack = DoomStack:New(unitID, weaponNum, weaponDefID)
            stack.handler = self
            self.stacksByAttacker[unitID][weaponNum] = stack
        end
    end
end

function DoomHandler:TargetCreated(unitID)
    self.targetStackedDoom[unitID] = 0
    self:UpdateTargetMult(unitID)
end

function DoomHandler:OwnerDestroyed(unitID)
    local attackerStacks = self.stacksByAttacker[unitID]
    if attackerStacks then
        for weaponNum, stack in pairs(attackerStacks) do
            stack:SetData(-1, nil, nil, 1)
            self:UpdateStack(stack) -- removes stack from stacksByTarget of its old target
        end
        self.stacksByAttacker[unitID] = nil
    end
end

function DoomHandler:TargetDestroyed(unitID)
    -- WeaponChangedTarget cleans up individual stacks; clear residual tracking tables
    self.stacksByTarget[unitID] = nil
    self.stackCounts[unitID] = nil
    self.targetStackedDoom[unitID] = nil
    self.ignoredTargets[unitID] = nil
    Spring.SetAllyTeamToUnitPriorityMult(self.allyTeam, unitID, nil)
end

function DoomHandler:UpdateStack(stack)
    local oldTargetID = stack.lastData.targetID
    local newTargetID = stack.targetID
    local oldActiveState = stack.lastData.reloadState*stack.lastData.rangeState*stack.lastData.pauseState
    local newActiveState = stack.rangeState*stack.reloadState*stack.pauseState

    if oldTargetID ~= newTargetID then
        self:OnTargetChanged(stack)
    elseif oldActiveState ~= newActiveState then
        self:OnActiveStateChanged(stack)
    end
    stack:StackUpdated() -- dump current into lastData
end

function DoomHandler:OnTargetChanged(stack)
    local oldTargetID = stack.lastData.targetID
    if oldTargetID and Spring.ValidUnitID(oldTargetID) then
        local oldIndex = stack.index
        local targetStacks = self.stacksByTarget[oldTargetID]
        if targetStacks then
            local count = self.stackCounts[oldTargetID]
            for i = oldIndex, count - 1 do
                targetStacks[i] = targetStacks[i+1]
                targetStacks[i].index = i
            end
            targetStacks[count] = nil
            count = count - 1
            self.stackCounts[oldTargetID] = count
            if count == 0 then
                self.stacksByTarget[oldTargetID] = nil
            end
        end
        stack.index = nil
        self.targetStackedDoom[oldTargetID] = math.max(0, self.targetStackedDoom[oldTargetID] - stack.lastData.value)
        self:UpdateTargetMult(oldTargetID)
    end
    local newTargetID = stack.targetID
    if newTargetID and Spring.ValidUnitID(newTargetID) then
        self.stacksByTarget[newTargetID] = self.stacksByTarget[newTargetID] or {}
        local targetStacks = self.stacksByTarget[newTargetID]
        local count = (self.stackCounts[newTargetID] or 0) + 1
        self.stackCounts[newTargetID] = count
        stack.index = count
        targetStacks[count] = stack
        self.targetStackedDoom[newTargetID] = self.targetStackedDoom[newTargetID] + stack.value
        self:UpdateTargetMult(newTargetID)
    end
end

function DoomHandler:OnActiveStateChanged(stack)
    local targetID = stack.targetID
    if targetID and Spring.ValidUnitID(targetID) then
        self.targetStackedDoom[targetID] = math.max(0, self.targetStackedDoom[targetID] - stack.lastData.value) + stack.value
        self:UpdateTargetMult(targetID)
    end
end

function DoomHandler:UpdateTargetMult(targetID)
    if not targetID or not Spring.ValidUnitID(targetID) then return end
    local mult = 1
    local health = self:GetAnticipatedHealth(targetID)
    local value = self.targetStackedDoom[targetID] or 0
    local threshold = self.ignoredTargets[targetID] and self:GetTargetDoomThreshold(targetID) or self:GetTargetEnterThreshold(targetID)
    if value >= health + threshold then
        mult = 0
    else
        mult = 1 + math.max(0,(value - health) / health) -- no malus until value exceeds health
    end
    Spring.SetAllyTeamToUnitPriorityMult(self.allyTeam, targetID, mult)
end

function DoomHandler:TestWeaponTarget(targetID)
    if not targetID or not Spring.ValidUnitID(targetID) then return false end
    local health = self:GetAnticipatedHealth(targetID)
    local value = self.targetStackedDoom[targetID] or 0
    local threshold = self.ignoredTargets[targetID] and self:GetTargetDoomThreshold(targetID) or self:GetTargetEnterThreshold(targetID)
    if value > health + threshold then
        return false
    end
    return true
end

function DoomHandler:WeaponFired(attackerID, weaponNum, proID)
    local stack = self.stacksByAttacker[attackerID][weaponNum]
    if stack then
        local salvoLeft = Spring.GetUnitWeaponState(attackerID, weaponNum, "salvoLeft") or 0
        local salvoSize = math.max(1, WeaponDefs[stack.weaponDefID].salvoSize or 1)
        local reloadState = salvoLeft > 0 and salvoLeft / salvoSize or 0
        stack:SetData(nil, reloadState, nil, nil)
        if stack.targetID then
            self.activeProjectiles[proID] = {targetID = stack.targetID, value = stack.expectedDamage}
            self.anticipatedDamages[stack.targetID] = (self.anticipatedDamages[stack.targetID] or 0) + self.activeProjectiles[proID].value
        end
        self:UpdateStack(stack) --> update doom total
    end
end

function DoomHandler:WeaponReached(proID)
    if proID and self.activeProjectiles[proID] then
        local targetID = self.activeProjectiles[proID].targetID
        self.anticipatedDamages[targetID] = math.max(0,(self.anticipatedDamages[targetID] or 0) - self.activeProjectiles[proID].value)
        self.activeProjectiles[proID] = nil
        self:UpdateTargetMult(targetID)
    end
end

function DoomHandler:TargetDamaged(targetID)
    self:UpdateTargetMult(targetID)
end

function DoomHandler:ProjectileHit(projectileID, targetID, actualDamage, expectedDamage)
    -- Projectile hit expected target with actualDamage
    -- Use actual damage instead of anticipated (removes from anticipatedDamages, adds real damage received)
    if self.activeProjectiles[projectileID] then
        local oldExpected = self.activeProjectiles[projectileID].value
        self.anticipatedDamages[targetID] = math.max(0, (self.anticipatedDamages[targetID] or 0) - oldExpected + actualDamage)
        self.activeProjectiles[projectileID] = nil
        self:UpdateTargetMult(targetID)
    end
end

function DoomHandler:ProjectileMissed(projectileID, intendedTargetID, actualTargetID, actualDamage)
    -- Projectile missed intended target, hit different unit (or splashed)
    -- Remove from intended target's anticipated damages
    if self.activeProjectiles[projectileID] then
        local oldExpected = self.activeProjectiles[projectileID].value
        self.anticipatedDamages[intendedTargetID] = math.max(0, (self.anticipatedDamages[intendedTargetID] or 0) - oldExpected)
        self.activeProjectiles[projectileID] = nil
        self:UpdateTargetMult(intendedTargetID)
    end
    -- If actual target is in our tracking and valid, update its anticipated damages too
    if actualTargetID and Spring.ValidUnitID(actualTargetID) then
        self.anticipatedDamages[actualTargetID] = (self.anticipatedDamages[actualTargetID] or 0) + actualDamage
        self:UpdateTargetMult(actualTargetID)
    end
end

function DoomHandler:WeaponRequestsTarget(attackerID, weaponNum, weaponDefID) -- pauses current stack without removing values
    local stack = self.stacksByAttacker[attackerID] and self.stacksByAttacker[attackerID][weaponNum]
    if stack then
        stack:SetData(nil, nil, nil, 0) --> keep current target (avoid useless table re-indexing), set paused
        self:UpdateStack(stack)
        if stack.targetID then
        end
    end
end

function DoomHandler:WeaponTarget(attackerID, weaponNum, weaponDefID, targetID) -- we always check for next frame, because the weapon will not fire this frame anyway
    -- and because we won't be blocking on GameFrame, but GameFramePost, if needed.
    local stack = self.stacksByAttacker[attackerID][weaponNum]
    if stack then
        local reloadReady = Spring.GetGameFrame() >= (Spring.GetUnitWeaponState(attackerID, weaponNum, "reloadFrame") or 0) - 1
        local salvoLeft = Spring.GetUnitWeaponState(attackerID, weaponNum, "salvoLeft") or 0
        local salvoSize = math.max(1, WeaponDefs[weaponDefID].salvoSize or 1)
        local reloadState = reloadReady and 1 or (salvoLeft > 0 and salvoLeft / salvoSize or 0)
        local rangeState = targetID and Spring.GetUnitWeaponTestRange(attackerID, weaponNum, targetID) and 1 or 0
        stack:SetData(targetID or -1, reloadState, rangeState, 1)
        self:UpdateStack(stack)
    end
end

function DoomHandler:GetAnticipatedHealth(targetID)
    -- Gate health query by LOS: only return actual health if we have vision
    -- Fallback to 100k if health unknown (no LOS or invalid unit)
    local health = 100000
    if self.representativeTeamID then
        local actualHealth = CallAsTeam(self.representativeTeamID, Spring.GetUnitHealth, targetID)
        if actualHealth then
            health = actualHealth
        end
    end
    return health - (self.anticipatedDamages[targetID] or 0)
end

function DoomHandler:GetTargetDoomThreshold(targetID)
    if not targetID or not Spring.ValidUnitID(targetID) then return 0 end
    local targetDefID = Spring.GetUnitDefID(targetID)
    local maxHealth = UnitDefs[targetDefID].health
    return maxHealth * self.DOOM_IGNORE_THRESHOLD
end

function DoomHandler:GetTargetEnterThreshold(targetID)
    if not targetID or not Spring.ValidUnitID(targetID) then return 0 end
    local targetDefID = Spring.GetUnitDefID(targetID)
    local maxHealth = UnitDefs[targetDefID].health
    return maxHealth * (self.DOOM_IGNORE_ENTERING_MULT + self.DOOM_IGNORE_THRESHOLD)
end

function DoomHandler:CancelTarget(attackerID, weaponNum, updateNow)
    local stack = self.stacksByAttacker[attackerID][weaponNum]
    if stack then
        Spring.UnitWeaponHoldFire(attackerID, weaponNum, true)
        stack:SetData(-1, nil, nil, 1) --> no target, not paused
        if updateNow then
            self:UpdateStack(stack)
        end
    end
end

function DoomHandler:UpdateStackList(stackList, count)
    for i = count, 1, -1 do
        self:UpdateStack(stackList[i])
    end
end

function DoomHandler:GetExpectedDamage(weaponDefID, targetID)
    local weaponDef = WeaponDefs[weaponDefID]
    local targetArmorType = UnitDefs[Spring.GetUnitDefID(targetID)].armorType
    if weaponDef then
        local baseDamage = (weaponDef.damages[targetArmorType] or weaponDef.damages[0]) * weaponDef.salvoSize
        
        -- Determine if weapon is ballistic (cannon, laser, non-tracking missile)
        -- and should apply hitChance penalty
        local isBallistic = weaponDef.type ~= "BeamLaser" and not weaponDef.tracks
        
        if isBallistic then
            -- Calculate hit chance based on target mobility vs projectile flight time
            local range = weaponDef.range
            local projectileSpeed = weaponDef.projectilespeed * 30
            local eta = projectileSpeed and projectileSpeed > 0 and range / projectileSpeed or 0
            
            -- High-trajectory weapons take significantly longer to reach target
            if weaponDef.highTrajectory then
                eta = eta * 2
            end
            
            -- Starburst launchers have extreme eta penalty (massive arc)
            if weaponDef.starburst then
                eta = eta * 5
            end
            
            local targetSpeed = Spring.GetUnitDefID(targetID) and UnitDefs[Spring.GetUnitDefID(targetID)].speed or 0
            local aoe = weaponDef.damageAreaOfEffect
            local hitChance =  aoe / (targetSpeed * eta) -- should probably be something like ^0.2 or w/e because it should heavily decrease if aoe < targetSpeed * eta, but not be linear. This is a placeholder for now.
            local hitChance = math.min(1.0,hitChance * hitChance * hitChance / weaponDef.accuracy)
            Spring.Echo(weaponDef.name .. " expected damage vs " .. UnitDefs[Spring.GetUnitDefID(targetID)].name .. ": baseDamage=" .. baseDamage .. ", hitChance=" .. hitChance)
            return baseDamage * hitChance
        else
            -- Instant-hit (lasers) or tracking (missiles) get full damage
            return baseDamage
        end
    end
    return 0
end

-- Entry point from gadget:ProjectileCreated — disambiguates weapon by highest reloadFrame
function DoomHandler:ProjectileCreated(proID)
    local ownerID = Spring.GetProjectileOwnerID(proID)
    local weaponDefID = Spring.GetProjectileDefID(proID)
    if WeaponDefs[weaponDefID].type == "BeamLaser" then -- instant hit weapons can probably be ignored
        return
    end

    if not ownerID or not weaponDefID or weaponDefID < 0 then return end
    local attackerStacks = self.stacksByAttacker[ownerID]
    if not attackerStacks then return end
    local bestWeaponNum  = nil
    local bestReloadFrame = -1
    for weaponNum, stack in pairs(attackerStacks) do
        if stack.weaponDefID == weaponDefID and stack.targetID then
            local rf = Spring.GetUnitWeaponState(ownerID, weaponNum, "reloadFrame") or -1
            if rf > bestReloadFrame then
                bestReloadFrame = rf
                bestWeaponNum   = weaponNum
            end
        end
    end
    if bestWeaponNum then
        self:WeaponFired(ownerID, bestWeaponNum, proID)
    end
end
function DoomHandler:Update(UPDATE_RATE) -- called from GameFramePost; frame+1 is the relevant frame for weapon readiness
    local frame = Spring.GetGameFrame()
    for targetID, stackList in pairs(self.stacksByTarget) do
        local count = self.stackCounts[targetID]

        -- refresh values and rebuild doom total inline; no target changes so UpdateStack is bypassed
        local totalDoom = 0
        for i = 1, count do
            local stack = stackList[i]
            local reloadReady = frame >= ((Spring.GetUnitWeaponState(stack.attackerID, stack.weaponNum, "reloadFrame") or 0) - UPDATE_RATE)
            local salvoLeft = Spring.GetUnitWeaponState(stack.attackerID, stack.weaponNum, "salvoLeft") or 0
            local salvoSize = math.max(1, WeaponDefs[stack.weaponDefID].salvoSize or 1)
            local reloadState = reloadReady and 1 or (salvoLeft > 0 and salvoLeft / salvoSize or 0)
            local rangeState = stack.targetID and Spring.GetUnitWeaponTestRange(stack.attackerID, stack.weaponNum, stack.targetID) and 1 or 0
            stack:SetData(nil, reloadState, rangeState, nil) -- nil preserves pauseState set by WeaponRequestsTarget
            stack:StackUpdated()
            totalDoom = totalDoom + stack.value
        end
        self.targetStackedDoom[targetID] = totalDoom
        self:UpdateTargetMult(targetID)

        table.sort(stackList, function(a, b) return a.value > b.value end)

        local health = self:GetAnticipatedHealth(targetID)
        local threshold = self:GetTargetDoomThreshold(targetID) -- always the minimal threshold for ignoring stacks, even if the target is not marked as ignored
        Spring.Echo("DoomHandler:Update() - targetID: " .. targetID .. ", health: " .. health .. ", totalDoom: " .. totalDoom .. ", threshold: " .. threshold)
        if totalDoom > health + threshold then -- we need to validate when anticipated health == 0 too
            local targetPosX, targetPosY, targetPosZ = Spring.GetUnitPosition(targetID)
            Spring.SpawnCEG("doomeffect", targetPosX, targetPosY+20, targetPosZ,0,1,0,0,20,0)
            local newStackList = {}
            local writeIndex = 1
            local runningDoom = totalDoom
            local pendingHoldFires = {} -- deferred to prevent UnitWeaponHoldFire re-entrancy mid-loop
            for i = 1, count do
                local stack = stackList[i]
                local value = stack.value
                -- Guard: Don't remove stacks if the weapon's current target is a user target
                local targetType, isUserTarget = Spring.GetUnitWeaponTarget(stack.attackerID, stack.weaponNum)
                if (runningDoom - value) > health + threshold and not isUserTarget then
                    pendingHoldFires[#pendingHoldFires + 1] = {stack.attackerID, stack.weaponNum}
                    stack:SetData(-1, nil, nil, 1)
                    stack:StackUpdated()
                    runningDoom = runningDoom - value
                else
                    stack.index = writeIndex
                    newStackList[writeIndex] = stack
                    writeIndex = writeIndex + 1
                end
            end
            local newCount = writeIndex - 1
            self.targetStackedDoom[targetID] = runningDoom
            self:UpdateTargetMult(targetID)
            -- Mark as ignored once stacks are being removed
            self.ignoredTargets[targetID] = true
            if newCount > 0 then
                self.stacksByTarget[targetID] = newStackList
                self.stackCounts[targetID] = newCount
            else
                self.stacksByTarget[targetID] = nil
                self.stackCounts[targetID] = nil
            end
            for j = 1, #pendingHoldFires do
                Spring.UnitWeaponHoldFire(pendingHoldFires[j][1], pendingHoldFires[j][2], true)
            end
        else
            local targetPosX, targetPosY, targetPosZ = Spring.GetUnitPosition(targetID)
            if not targetPosX or not targetPosY or not targetPosZ then
                Spring.Echo("DoomHandler:Update() - Invalid target position for targetID: " .. targetID)
                return
            end
            Spring.SpawnCEG("targeteffect", targetPosX, targetPosY+20, targetPosZ,0,1,0,0,20,0)
            for i = 1, count do stackList[i].index = i end -- resync after sort
            -- Clear ignored status if doom dropped back below threshold
            self.ignoredTargets[targetID] = nil
        end
    end
end

function DoomHandler:New(allyTeam)
    local instance = setmetatable({}, {__index = self})
    instance:Init()
    instance.allyTeam = allyTeam
    return instance
end

return DoomHandler