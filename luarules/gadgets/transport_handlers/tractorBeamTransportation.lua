local BaseHandler = VFS.Include("luarules/gadgets/transport_handlers/baseHandler.lua")
local TractorBeam = setmetatable({}, { __index = BaseHandler })

function TractorBeam.New(context)
	return BaseHandler.New(TractorBeam, context)
end

function TractorBeam:Initialize()
	self.enemyProgress = {}
	local settings = self.context.settings
	self.loadRadius = settings.LOAD_RADIUS or 128
	self.unloadRadius = settings.UNLOAD_RADIUS or 32
	self.enemyMode = settings.ALLOW_ENEMY_LOAD_MODE or 2
	self.enemyRadius = self.loadRadius * (settings.ENEMY_LOAD_RADIUS_MULTIPLIER or 0.5)
	self.enemyIntervals = settings.MIN_CONSECUTIVE_FRAMES_TO_LOAD_ENEMY or 60
end

function TractorBeam:InLoadRange(tx, ty, tz, px, py, pz, reduced)
	return self.context.distance(tx, tz, px, pz) <= (reduced and self.enemyRadius or self.loadRadius)
		and ty >= py
end

function TractorBeam:InUnloadRange(tx, ty, tz, x, y, z)
	return self.context.distance(tx, tz, x, z) <= self.unloadRadius and ty >= y
end

function TractorBeam:CanBeTransportedStatic(passengerID, passengerDefID)
	return not UnitDefs[passengerDefID].cantBeTransported
end

function TractorBeam:CanBeTransportedDynamic(passengerID, passengerDefID, passengerY, passengerTeam)
	if Spring.GetUnitIsBeingBuilt(passengerID) or self.context.isUnderwater(passengerID, passengerY) then
		return false
	end
	local transporterID = self.context.transporterID
	if Spring.AreTeamsAllied(passengerTeam, Spring.GetUnitTeam(transporterID)) then
		return true
	end
	if self.enemyMode == 1 then
		return false
	end
	local definition = UnitDefs[passengerDefID]
	if definition.customParams.isCommander or definition.transportByEnemy == false then
		return false
	end
	local los = Spring.GetUnitLosState(passengerID, Spring.GetUnitAllyTeam(transporterID), false)
	return los ~= nil and (los.los or los.radar) or false
end

function TractorBeam:CanBeAutoClaimed(passengerID)
	local defID = Spring.GetUnitDefID(passengerID)
	return UnitDefs[defID].customParams.cantbeautoloaded ~= "1"
end

function TractorBeam:CanFit(passengerID, passengerDefID, claims)
	local queued = 0
	for _, id in ipairs(claims or {}) do
		if id ~= passengerID then
			queued = queued + self.context.api.GetPassengerSize(id)
		end

		function TractorBeam:IsFull(claims)
			local queued = 0
			for _, id in ipairs(claims or {}) do
				queued = queued + self.context.api.GetPassengerSize(id)
			end
			return self.context.api.IsTransportFull(self.context.transporterID, queued)
		end

		function TractorBeam:GetQueueScanLimit()
			return Spring.GetUnitRulesParam(self.context.transporterID, "transporterSeats")
		end
	end
	return self.context.api.CanPassengerFitInTransporter(
		self.context.transporterID, passengerID, self.context.transporterDefID,
		self.context.api.GetPassengerSize(passengerID), queued)
end

function TractorBeam:SpawnWeakBeam(passengerID, size)
	local x, y, z = Spring.GetUnitPosition(passengerID)
	y = y + Spring.GetUnitHeight(passengerID)
	local tx, ty, tz = Spring.GetUnitPosition(self.context.transporterID)
	Spring.SpawnCEG("tractorbeam_weak", x, y, z, (tx - x) * size, (ty - y) * size, (tz - z) * size, 1, 0)
end

function TractorBeam:CanBeTransportedNow(passengerID, passengerTeam, px, py, pz, tx, ty, tz)
	if Spring.AreTeamsAllied(passengerTeam, Spring.GetUnitTeam(self.context.transporterID))
		or Spring.GetUnitIsStunned(passengerID) then
		return self:InLoadRange(tx, ty, tz, px, py, pz)
	end
	if not self:InLoadRange(tx, ty, tz, px, py, pz, self.enemyMode >= 4) then
		self.enemyProgress[passengerID] = nil
		return false
	end
	if self.enemyMode >= 3 then
		local _, _, _, speed = Spring.GetUnitVelocity(passengerID)
		if speed < 0.5 then
			local progress = (self.enemyProgress[passengerID] or 0) + 1
			self.enemyProgress[passengerID] = progress
			self:SpawnWeakBeam(passengerID, progress / self.enemyIntervals)
			if progress > self.enemyIntervals then
				self.enemyProgress[passengerID] = nil
				return true
			end
		else
			self.enemyProgress[passengerID] = nil
		end
	end
	return false
end

function TractorBeam:CanMoveToTransporter(passengerID, destinationY)
	return destinationY >= 0
		or UnitDefs[Spring.GetUnitDefID(passengerID)].modCategories.hover == true
end

function TractorBeam:ExecuteApproach(x, y, z, passengerID, radius)
	if passengerID then
		Spring.SetUnitMoveGoal(passengerID, x, y, z, 64, nil, true)
	else
		Spring.SetUnitMoveGoal(self.context.transporterID, x, y, z, radius)
	end
end

function TractorBeam:ApproachPassenger(passengerID)
	if self.enemyMode >= 5
		and not Spring.AreTeamsAllied(Spring.GetUnitTeam(passengerID), Spring.GetUnitTeam(self.context.transporterID))
		and not Spring.GetUnitIsStunned(passengerID) then
		return
	end
	self:ExecuteApproach(Spring.GetUnitPosition(passengerID))
end

function TractorBeam:ExecuteLoad(passengerID)
	self.context.load(self.context.transporterID, "PerformLoad", passengerID)
end

function TractorBeam:ExecuteUnload(passengerID, x, y, z)
	self.context.unload(self.context.transporterID, "PerformUnload", passengerID, x, y, z)
end

function TractorBeam:ExecuteUnloadAll(x, y, z)
	local targets = self.context.api.GetUnloadTargets(self.context.transporterID, nil, x, y, z)
	for _, passengerID in ipairs(targets) do
		self:ExecuteUnload(passengerID, x, y, z)
	end

	function TractorBeam:ResolveUnloadPosition(passengerID, x, y, z)
		local transporterID = self.context.transporterID
		local pad = self.context.api.GetUnloadPadType(transporterID, passengerID)
		return Spring.ClosestBuildPos(Spring.GetUnitTeam(transporterID), pad, x, y, z, 512, 0, 0)
	end

	function TractorBeam:ClearUnloadArea(x, y, z, padDefID)
		local transporterID = self.context.transporterID
		local padSize = UnitDefs[padDefID].xsize * 8
		local allyTeam = Spring.GetUnitAllyTeam(transporterID)
		local units = Spring.GetUnitsInBox(x - padSize / 2, y - 50, z - padSize / 2,
			x + padSize / 2, y + 5, z + padSize / 2)
		for _, unitID in ipairs(units) do
			if unitID ~= transporterID and Spring.GetUnitAllyTeam(unitID) == allyTeam then
				local ux, uy, uz = Spring.GetUnitPosition(unitID)
				local dx, dy, dz = x - ux, y - uy, z - uz
				local length = math.sqrt(dx * dx + dy * dy + dz * dz)
				if length > 0 then
					dx, dy, dz = dx / length, dy / length, dz / length
				end
				Spring.SetUnitMoveGoal(unitID, x - dx * padSize, y, z - dz * padSize, 8)
			end
		end
	end
end

function TractorBeam:ClaimRemoved(passengerID)
	self.enemyProgress[passengerID] = nil
end

function TractorBeam:ClaimsRemoved()
	self.enemyProgress = {}
end

return TractorBeam
