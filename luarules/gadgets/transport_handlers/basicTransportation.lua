local BaseHandler = VFS.Include("luarules/gadgets/transport_handlers/baseHandler.lua")
local BasicTransportation = setmetatable({}, { __index = BaseHandler })

function BasicTransportation.New(context)
	return BaseHandler.New(BasicTransportation, context)
end

function BasicTransportation:CanBeTransportedStatic(passengerID, passengerDefID)
	return not UnitDefs[passengerDefID].cantBeTransported
end

function BasicTransportation:CanBeTransportedDynamic(passengerID, passengerDefID, passengerY, passengerTeam)
	local context = self.context
	return not Spring.GetUnitIsBeingBuilt(passengerID)
		and (Spring.AreTeamsAllied(passengerTeam, Spring.GetUnitTeam(context.transporterID))
			or UnitDefs[passengerDefID].transportByEnemy ~= false)
end

function BasicTransportation:CanFit(passengerID, passengerDefID, claims)
	local context = self.context
	local definition = UnitDefs[context.transporterDefID]
	local passenger = UnitDefs[passengerDefID]
	if passenger.xsize / 2 > definition.transportSize
		or passenger.xsize / 2 < definition.minTransportSize
		or passenger.mass < definition.minTransportMass then
		return false
	end
	local capacity, mass = 0, 0
	local included = {}
	local function account(id)
		if id ~= passengerID and not included[id] then
			local defID = Spring.GetUnitDefID(id)
			if defID then
				included[id] = true
				capacity = capacity + UnitDefs[defID].xsize / 2
				mass = mass + UnitDefs[defID].mass
			end
		end
	end
	for _, id in ipairs(Spring.GetUnitIsTransporting(context.transporterID)) do
		account(id)
	end
	for _, id in ipairs(claims or {}) do
		account(id)
	end
	return capacity + passenger.xsize / 2 <= definition.transportCapacity
		and mass + passenger.mass <= definition.transportMass
end

function BasicTransportation:CanBeTransportedNow(passengerID, passengerTeam, px, py, pz, tx, ty, tz)
	local radius = UnitDefs[self.context.transporterDefID].loadingRadius
	return (px - tx)^2 + (py - ty)^2 + (pz - tz)^2 <= radius^2
end

function BasicTransportation:ExecuteApproach(x, y, z, passengerID)
	Spring.SetUnitMoveGoal(passengerID or self.context.transporterID, x, y, z)
end

-- This backend is not activated by the legacy coordinator yet. Its cargo
-- bookkeeping/reload contract will be supplied when the LUS boundary is defined.
function BasicTransportation:ExecuteLoad(passengerID)
	Spring.UnitAttach(self.context.transporterID, passengerID, 0, true)
	if Spring.GetUnitTransporter(passengerID) ~= self.context.transporterID then
		error("basicTransportation: authorized attachment failed for passenger " .. passengerID)
	end
end

function BasicTransportation:ExecuteUnload(passengerID, x, y, z)
	Spring.UnitDetach(passengerID)
	Spring.SetUnitPosition(passengerID, x, y, z)
end

function BasicTransportation:ExecuteUnloadAll(x, y, z)
	local passengers = Spring.GetUnitIsTransporting(self.context.transporterID)
	for _, passengerID in ipairs(passengers) do
		self:ExecuteUnload(passengerID, x, y, z)
	end
end

return BasicTransportation