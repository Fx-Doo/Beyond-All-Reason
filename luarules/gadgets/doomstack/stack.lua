local DoomStack = {}

function DoomStack:New(unitID, weaponNum, weaponDefID)
    local newStack = {
        attackerID = unitID,
        targetID = nil,
        weaponNum = weaponNum,
        weaponDefID = weaponDefID,
        rangeState = 0,
        reloadState = 0,
        pauseState = 0,
        value = 0,
        index = nil,
        lastData = {
            targetID = nil,
            rangeState = 0,
            reloadState = 0,
            pauseState = 0,
            expectedDamage = 0,
            value = 0
        }
    }
    setmetatable(newStack, self)
    self.__index = self
    return newStack
end

function DoomStack:Remove()
    self = nil
end

function DoomStack:expectedDamage()
    local targetID = self.targetID
    local weaponDefID = self.weaponDefID
    if not targetID or not weaponDefID then
        return 0
    end
    local weaponDef = WeaponDefs[weaponDefID]
    local targetArmorType = UnitDefs[Spring.GetUnitDefID(targetID)].armorType
    if weaponDef then
        local baseDamage = (weaponDef.damages[targetArmorType] or weaponDef.damages[0]) * weaponDef.salvoSize
        
        -- Determine if weapon is ballistic (cannon, laser, non-tracking missile)
        -- and should apply hitChance penalty
        local isBallistic = weaponDef.type ~= "BeamLaser" and not weaponDef.tracks
        
        if isBallistic then
            -- Calculate hit chance based on target mobility vs projectile flight time
            local sep = Spring.GetUnitSeparation(self.attackerID, targetID)
            local _,_,_,targetSpeed = Spring.GetUnitVelocity(targetID)
            local targetSpeed = targetSpeed * 0.7 + UnitDefs[Spring.GetUnitDefID(targetID)].speed/30 * 0.3 -- weighted average of current speed and max speed
            local projectileSpeed = weaponDef.projectilespeed
            local eta = projectileSpeed and projectileSpeed > 0 and sep / projectileSpeed or 0
            local predictBoost = weaponDef.predictBoost
            local currentBoost = math.max(1,(1-predictBoost) * targetSpeed)
            -- High-trajectory weapons take significantly longer to reach target
            if weaponDef.highTrajectory then
                eta = eta * 2
            end
            
            -- Starburst launchers have extreme eta penalty (massive arc)
            if weaponDef.type == "StarburstLauncher" then
                eta = 50000
            end

            local accuracy = math.max(1, weaponDef.accuracy)
            local aoe = weaponDef.damageAreaOfEffect
            local hitChance =  targetSpeed > 0 and aoe / (targetSpeed * eta) or 1 -- should probably be something like ^0.2 or w/e because it should heavily decrease if aoe < targetSpeed * eta, but not be linear. This is a placeholder for now.
            local hitChance = math.min(1.0, hitChance / (currentBoost * accuracy))
            return baseDamage * hitChance
        else
            -- Instant-hit (lasers) or tracking (missiles) get full damage
            return baseDamage
        end
    end
    return 0
end

function DoomStack:SetData(targetID, reloadState, rangeState, pauseState)
    if targetID == -1 then -- remove target
        self.targetID = nil
    elseif targetID == nil then -- keep target
        self.targetID = self.targetID
    elseif Spring.ValidUnitID(targetID) then -- set new target
        self.targetID = targetID
    else
    end
    self.rangeState = rangeState and rangeState or self.rangeState -- nil => keep current state, else => set new state
    self.reloadState = reloadState and reloadState or self.reloadState -- nil => keep current state, else => set new state
    self.pauseState = pauseState and pauseState or self.pauseState -- nil => keep current state, else => set new state
    self.value = self.pauseState == 1 and self.rangeState * self.reloadState * self:expectedDamage() or 0
end

function DoomStack:StackUpdated() -- dumps current into lastData
    self.lastData.value = self.value    
    self.lastData.rangeState = self.rangeState
    self.lastData.reloadState = self.reloadState
    self.lastData.expectedDamage = self:expectedDamage()
    self.lastData.targetID = self.targetID
    self.lastData.pauseState = self.pauseState
end

return DoomStack