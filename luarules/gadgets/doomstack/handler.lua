local DoomHandler = {}

local DoomStack = VFS.Include("luarules/gadgets/doomstack/stack.lua")

function DoomHandler:Init()
    self.DOOM_IGNORE_THRESHOLD = 1 -- if totalDoomValue * 2 * DOOM_IGNORE_THRESHOLD > health, then ignore target
    self.DOOM_IGNORE_ENTERING_MULT = 4
    -- higher value = more stack candidates, then select lower values first to avoid overkill, but more processing time
    -- lower value can result in picking a single high value stack that would overkill by a large margin, but means smaller stackLists
    self.stacksByAttacker = {} -- [attackerID][weaponNum] = stack
    self.stacksByTarget = {} -- [targetID] = {stack1, stack2, ...}
    self.stackCounts = {} -- [targetID] = number of stacks targeting that unit
    self.targetStackedDoom = {} -- [targetID] = totalDoomValue  
    self.activeProjectiles = {} -- [proID] = {targetID, value}
    self.anticipatedDamages = {} -- [targetID] = totalDoomValue of active projectiles
end

function DoomHandler:Kill()
    self.stacksByAttacker = nil
    self.stacksByTarget = nil
    self.stackCounts = nil
    self.targetStackedDoom = nil
    self.activeProjectiles = nil
    self.anticipatedDamages = nil
    DoomHandler = nil
end

function DoomHandler:RegisterUnit(unitID)
    Spring.Echo("DoomHandler:RegisterUnit() - unitID: " .. unitID)
    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]
    local weapons = unitDef.weapons
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
    self.targetStackedDoom[unitID] = self.targetStackedDoom[unitID] or 0
    self:UpdateTargetMult(unitID)
end

function DoomHandler:UnregisterUnit(unitID)
    Spring.Echo("DoomHandler:UnregisterUnit() - unitID: " .. unitID)
    local attackerStacks = self.stacksByAttacker[unitID]
    if attackerStacks then
        for weaponNum, stack in pairs(attackerStacks) do
            self:CancelTarget(unitID, weaponNum, true)
            self.stacksByAttacker[unitID][weaponNum] = nil
        end
        self.stacksByAttacker[unitID] = nil
    end
    self.stacksByTarget[unitID] = nil
    self.stackCounts[unitID] = nil
    self.targetStackedDoom[unitID] = nil
end

function DoomHandler:UpdateStack(stack)
    --Spring.Echo("DoomHandler:UpdateStack() - attackerID: " .. stack.attackerID .. ", weaponNum: " .. stack.weaponNum)
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
    Spring.Echo("DoomHandler:OnTargetChanged() - attackerID: " .. stack.attackerID .. ", weaponNum: " .. stack.weaponNum)
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
    Spring.Echo("DoomHandler:OnActiveStateChanged() - attackerID: " .. stack.attackerID .. ", weaponNum: " .. stack.weaponNum)
    local targetID = stack.targetID
    if targetID and Spring.ValidUnitID(targetID) then
        self.targetStackedDoom[targetID] = math.max(0, self.targetStackedDoom[targetID] - stack.lastData.value) + stack.value
        self:UpdateTargetMult(targetID)
    end
end

function DoomHandler:UpdateTargetMult(targetID)
    Spring.Echo("DoomHandler:UpdateTargetMult() - targetID: " .. targetID)
    if not targetID or not Spring.ValidUnitID(targetID) then return end
    local mult = 1
    local health = self:GetAnticipatedHealth(targetID)
    local value = self.targetStackedDoom[targetID] or 0
    if value > health * self.DOOM_IGNORE_ENTERING_MULT * self.DOOM_IGNORE_THRESHOLD then
        mult = 0
    else
        mult = 1 + math.max(0,(value - health) / health) -- no malus until value exceeds health
    end
    Spring.SetSelfPriorityMult(targetID, mult)
end

function DoomHandler:TestWeaponTarget(targetID)
    Spring.Echo("DoomHandler:TestWeaponTarget() - targetID: " .. targetID)
    if not targetID or not Spring.ValidUnitID(targetID) then return false end
    local health = self:GetAnticipatedHealth(targetID)
    local value = self.targetStackedDoom[targetID] or 0
    if value > health * self.DOOM_IGNORE_THRESHOLD then
        return false
    end
    return true
end

function DoomHandler:WeaponFired(attackerID, weaponNum, proID)
    Spring.Echo("DoomHandler:WeaponFired() - attackerID: " .. attackerID .. ", weaponNum: " .. weaponNum .. ", proID: " .. proID)
    local stack = self.stacksByAttacker[attackerID][weaponNum]
    if stack then
        stack:SetData(nil, 0, nil, nil) --> same target, reloading, same range
        if stack.targetID then
            self.activeProjectiles[proID] = {targetID = stack.targetID, value = stack.expectedDamage}
            self.anticipatedDamages[stack.targetID] = (self.anticipatedDamages[stack.targetID] or 0) + self.activeProjectiles[proID].value
        end
        self:UpdateStack(stack) --> update doom total
    end
end

function DoomHandler:WeaponReached(proID)
    Spring.Echo("DoomHandler:WeaponReached() - proID: " .. proID)
    if proID and self.activeProjectiles[proID] then
        local targetID = self.activeProjectiles[proID].targetID
        self.anticipatedDamages[targetID] = math.max(0,(self.anticipatedDamages[targetID] or 0) - self.activeProjectiles[proID].value)
        self.activeProjectiles[proID] = nil
        self:UpdateTargetMult(targetID)
    end
end

function DoomHandler:UnitDamaged(targetID)
    self:UpdateTargetMult(targetID)
end

function DoomHandler:WeaponRequestsTarget(attackerID, weaponNum, weaponDefID) -- pauses current stack without removing values
    Spring.Echo("DoomHandler:WeaponRequestsTarget() - attackerID: " .. attackerID .. ", weaponNum: " .. weaponNum .. ", weaponDefID: " .. weaponDefID)
    local stack = self.stacksByAttacker[attackerID][weaponNum]
    if stack then
        stack:SetData(nil, nil, nil, 0) --> keep current target (avoid useless table re-indexing), set paused
        self:UpdateStack(stack)
        if stack.targetID then
            Spring.Echo(stack.targetID .. " is paused, doom value: " .. stack.value, "total doom on target: " .. (self.targetStackedDoom[stack.targetID] or 0))
        end
    end
end

function DoomHandler:WeaponTarget(attackerID, weaponNum, weaponDefID, targetID) -- we always check for next frame, because the weapon will not fire this frame anyway
    Spring.Echo("DoomHandler:WeaponTarget() - attackerID: " .. attackerID .. ", weaponNum: " .. weaponNum .. ", weaponDefID: " .. weaponDefID .. ", targetID: " .. (targetID or "nil"))
    -- and because we won't be blocking on GameFrame, but GameFramePost, if needed.
    local stack = self.stacksByAttacker[attackerID][weaponNum]
    if stack then
        local reloadState = (Spring.GetGameFrame() >= Spring.GetUnitWeaponState(attackerID, weaponNum, "reloadFrame") - 1) and 1 or 0
        local rangeState = targetID and Spring.GetUnitWeaponTestRange(attackerID, weaponNum, targetID) and 1 or 0
        stack:SetData(targetID or -1, reloadState, rangeState, 1)
        self:UpdateStack(stack)
    end
end

function DoomHandler:GetAnticipatedHealth(targetID)
    Spring.Echo("DoomHandler:GetAnticipatedHealth() - targetID: " .. targetID)
    local health = Spring.GetUnitHealth(targetID)
    Spring.Echo("DoomHandler:GetAnticipatedHealth() - current health: " .. health .. ", anticipated damage: " .. (self.anticipatedDamages[targetID] or 0))
    return math.max(0, health - (self.anticipatedDamages[targetID] or 0))
    -- we multiply by DOOM_IGNORE_THRESHOLD to maintain the ratio when stack value is transfered as inc damages
end

function DoomHandler:CancelTarget(attackerID, weaponNum, updateNow)
    Spring.Echo("DoomHandler:CancelTarget() - attackerID: " .. attackerID .. ", weaponNum: " .. weaponNum)
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
    Spring.Echo("DoomHandler:GetExpectedDamage() - weaponDefID: " .. weaponDefID .. ", targetID: " .. targetID)
    local weaponDef = WeaponDefs[weaponDefID]
    local targetArmorType = UnitDefs[Spring.GetUnitDefID(targetID)].armorType
    if weaponDef then
        local damage = (weaponDef.damages[targetArmorType] or weaponDef.damages[0]) * weaponDef.salvoSize
        return damage
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

    Spring.Echo("DoomHandler:ProjectileCreated() - proID: " .. proID .. ", ownerID: " .. ownerID .. ", weaponDefID: " .. weaponDefID)
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
    Spring.Echo("DoomHandler:Update() - GameFrame: " .. Spring.GetGameFrame())
    local frame = Spring.GetGameFrame()
    for targetID, stackList in pairs(self.stacksByTarget) do
        local count = self.stackCounts[targetID]
        Spring.Echo("DoomHandler:Update() - targetID: " .. targetID .. ", count: " .. count)

        -- refresh values and rebuild doom total inline; no target changes so UpdateStack is bypassed
        local totalDoom = 0
        for i = 1, count do
            local stack = stackList[i]
            local reloadState = (frame >= (Spring.GetUnitWeaponState(stack.attackerID, stack.weaponNum, "reloadFrame") or 0) - UPDATE_RATE) and 1 or 0
            local rangeState = stack.targetID and Spring.GetUnitWeaponTestRange(stack.attackerID, stack.weaponNum, stack.targetID) and 1 or 0
            stack:SetData(nil, reloadState, rangeState, nil) -- nil preserves pauseState set by WeaponRequestsTarget
            stack:StackUpdated()
            totalDoom = totalDoom + stack.value
        end
        self.targetStackedDoom[targetID] = totalDoom
        self:UpdateTargetMult(targetID)

        table.sort(stackList, function(a, b) return a.value > b.value end)

        local health = self:GetAnticipatedHealth(targetID)
        if totalDoom > health * self.DOOM_IGNORE_THRESHOLD then
            local targetPosX, targetPosY, targetPosZ = Spring.GetUnitPosition(targetID)
            Spring.SpawnCEG("doomeffect", targetPosX, targetPosY+20, targetPosZ,0,1,0,0,20,0)
            local newStackList = {}
            local writeIndex = 1
            local runningDoom = totalDoom
            local pendingHoldFires = {} -- deferred to prevent UnitWeaponHoldFire re-entrancy mid-loop
            for i = 1, count do
                local stack = stackList[i]
                local value = stack.value
                Spring.Echo(runningDoom .. " > " .. health * self.DOOM_IGNORE_THRESHOLD .. " ?")
                if (runningDoom - value) > health * self.DOOM_IGNORE_THRESHOLD then
                    Spring.Echo("DoomHandler:Update() - removing stack: " .. stack.attackerID .. "/" .. stack.weaponNum)
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
            Spring.SpawnCEG("targeteffect", targetPosX, targetPosY+20, targetPosZ,0,1,0,0,20,0)
            for i = 1, count do stackList[i].index = i end -- resync after sort
        end
    end
end

return DoomHandler