local BaseHandler = {}
BaseHandler.__index = BaseHandler

-- Instances own only backend data. Claims, commands and scheduling belong to
-- the coordinator; the script backend still owns its cargo and animations.
-- Static/Dynamic rejection invalidates a candidate/claim. Now rejection only
-- delays execution. Concrete handlers supply CanFit, readiness and execution.
-- Required RulesParam publication and LUS callbacks are a subsequent boundary;
-- backends must not introduce their own copies of that common state contract.
function BaseHandler.New(handler, context)
	assert(context.transporterID, "Transport handler requires a transporter ID")
	assert(context.api, "Transport handler requires the transport API")
	local instance = setmetatable({ context = context }, { __index = handler })
	instance:Initialize()
	return instance
end

function BaseHandler:Initialize()
end

function BaseHandler:GetUpdateInterval()
	return 1
end

function BaseHandler:CanBeTransportedStatic(passengerID, passengerDefID)
	return true
end

function BaseHandler:CanBeTransportedDynamic(passengerID, passengerDefID)
	return true
end

function BaseHandler:CanBeAutoClaimed(passengerID)
	return true
end

function BaseHandler:CanMoveToTransporter(passengerID, destinationY)
	return true
end

function BaseHandler:IsFull(claims)
	return false
end

function BaseHandler:ClaimAdded(passengerID)
end

function BaseHandler:ClaimRemoved(passengerID)
end

function BaseHandler:ClaimsRemoved()
end

function BaseHandler:Destroyed()
	self:ClaimsRemoved()
end

function BaseHandler:ResolveUnloadPosition(passengerID, x, y, z)
	return x, y, z
end

return BaseHandler
