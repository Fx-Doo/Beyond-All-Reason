DoomStack = {}

function DoomStack:New()
    local newStack = {}
    setmetatable(newStack, self)
    self.__index = self
    return newStack
end

function DoomStack:Remove()
    self = nil
end

function DoomStack:SetData(targetID, reloadState, rangeState, pauseState)
    if targetID == -1 then -- remove target
        self.targetID = nil
    elseif targetID == nil then -- keep target
        self.targetID = self.targetID
    elseif Spring.ValidUnitID(targetID) then -- set new target
        self.targetID = targetID
        self.expectedDamage = self.handler:GetExpectedDamage(self.attackerID, self.targetID)
    else
        Spring.Echo("DoomStack:SetState() - Invalid targetID: " .. targetID)
    end
    self.rangeState = rangeState and rangeState or self.rangeState -- nil => keep current state, else => set new state
    self.reloadState = reloadState and reloadState or self.reloadState -- nil => keep current state, else => set new state
    self.pauseState = pauseState and pauseState or self.pauseState -- nil => keep current state, else => set new state
    self.value = pauseState * reloadState * rangeState * self.expectedDamage
end

function DoomStack:StackUpdated() -- dumps current into lastData
    self.lastData.value = self.value    
    self.lastData.rangeState = self.rangeState
    self.lastData.reloadState = self.reloadState
    self.lastData.expectedDamage = self.expectedDamage
    self.lastData.targetID = self.targetID
    self.lastData.pauseState = self.pauseState
end