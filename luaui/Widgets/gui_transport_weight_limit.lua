local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Transport Load Indicators",
		desc = "When pressing Load command, it highlights units the transports can lift",
		author = "nixtux ( + made fancy by Floris), SuperKitowiec",
		date = "Apr 24, 2015",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

if not WG.TransportAPI then return false end

local TransportAPI = WG.TransportAPI

-- Localized functions for performance
local mathSin = math.sin
local mathCos = math.cos

-- Localized Spring API for performance
local spGetUnitDefID = Spring.GetUnitDefID
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetSelectedUnitsCount = Spring.GetSelectedUnitsCount

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Changelog
-- Sep 2025 SuperKitowiec - Show indicators when one or more transports are selected

local circlePieces = 3
local circlePieceDetail = 14
local circleSpaceUsage = 0.8
local circleInnerOffset = 0
local rotationSpeed = 8

-- outerSize - innerSize = circle width
local innerSize = 1.85
local outerSize = 2.02

local alphaFalloffDistance = 750
local maxAlpha = 0.55
local indicatorSizeMultiplier = 6

-- Multiplier to convert footprints sizes
-- see SPRING_FOOTPRINT_SCALE in GlobalConstants.h in recoil engine repo for details
-- https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts%2FSim%2FMisc%2FGlobalConstants.h
local springFootprintScale = 2

local CMD_LOAD_UNITS = CMD.LOAD_UNITS
local unitsToDraw = {}
local activeTransportDefs = {}

local validTrans = {}
local math_sqrt = math.sqrt

local transDefs = {}
local cantBeTransported = {}
local unitMass = {}
local unitXSize = {}

local circleList = {}
local chobbyInterface

for defID, def in pairs(UnitDefs) do
	if def.transportSize and def.transportSize > 0 then
		validTrans[defID] = true
		transDefs[defID] = { def.transportMass, def.transportCapacity, def.transportSize }
	end
	unitMass[defID] = def.mass
	unitXSize[defID] = def.xsize
	cantBeTransported[defID] = def.cantBeTransported
end

local function DrawCircleLine(nPieces)
	gl.BeginEnd(GL.QUADS, function()
		local detailPartWidth, a1, a2, a3, a4
		local width = circleSpaceUsage
		local detail = circlePieceDetail

		local radStep = (2.0 * math.pi) / nPieces
		for i = 1, nPieces do
			for d = 1, detail do
				detailPartWidth = ((width / detail) * d)
				a1 = ((i + detailPartWidth - (width / detail)) * radStep)
				a2 = ((i + detailPartWidth) * radStep)
				a3 = ((i + circleInnerOffset + detailPartWidth - (width / detail)) * radStep)
				a4 = ((i + circleInnerOffset + detailPartWidth) * radStep)

				--outer (fadein)
				gl.Vertex(mathSin(a4) * innerSize, 0, mathCos(a4) * innerSize)
				gl.Vertex(mathSin(a3) * innerSize, 0, mathCos(a3) * innerSize)
				--outer (fadeout)
				gl.Vertex(mathSin(a1) * outerSize, 0, mathCos(a1) * outerSize)
				gl.Vertex(mathSin(a2) * outerSize, 0, mathCos(a2) * outerSize)
			end
		end
	end)
end

local selectedUnits = {}
local selectedUnitsCount = 0

function widget:Initialize()
	selectedUnits = spGetSelectedUnits()
	selectedUnitsCount = spGetSelectedUnitsCount()
	circleList = {}
end

function widget:Shutdown()
	for k,v in pairs(circleList) do
		gl.DeleteList(v)
	end
end

function widget:SelectionChanged(sel)
	selectedUnits = sel
	selectedUnitsCount = spGetSelectedUnitsCount()
	unitsToDraw = {}
end

function widget:GameFrame(n)
	if n % 4 ~= 1 then
		return
	end

	if selectedUnitsCount < 1  or selectedUnitsCount > 20 then
		return
	end
	local activeCommand, activeCmdDescID = Spring.GetActiveCommand()
	if (activeCmdDescID ~= CMD_LOAD_UNITS) and (select(2,Spring.GetDefaultCommand()) ~= CMD_LOAD_UNITS) then
		if next(unitsToDraw) then
			unitsToDraw = {}
		end
		return
	end

	activeTransportDefs = {}
	local selectedTransports = {}
	for i = 1, #selectedUnits do
		local transID = selectedUnits[i]
		local transDefID = spGetUnitDefID(transID)
		if validTrans[transDefID] then
			selectedTransports[#selectedTransports + 1] = transID
		end
	end

	if not next(selectedTransports) then
		if next(unitsToDraw) then
			unitsToDraw = {}
		end
		return
	end

	unitsToDraw = {}

	local visibleUnits = {}
	if activeCmdDescID == CMD_LOAD_UNITS then
		visibleUnits = Spring.GetVisibleUnits()
	else
		local mx, my = Spring.GetMouseState()
		local type, data = Spring.TraceScreenRay(mx, my)
		if type == "unit" then
			visibleUnits = {data}
		end
	end

	if not visibleUnits or not next(visibleUnits) then
		return
	end

	for _, unitID in ipairs(visibleUnits) do
		local passengerDefID = spGetUnitDefID(unitID)
		if not cantBeTransported[passengerDefID] and not Spring.IsUnitIcon(unitID) then
			local passengerSize = TransportAPI.GetPassengerSize(unitID)
			local bestState = 0 -- 0 no slot for unit, 1 - slot but cant fit, 2 - can fit
			for idx, transportID in pairs(selectedTransports) do
				local transporterDefID = spGetUnitDefID(transportID)
				if bestState < 1 then
					local slotString = "transporterHasSlotOfSize" .. passengerSize
					if Spring.GetUnitRulesParam(transportID, slotString) == true then
						bestState = 1	
					end
				end
				if bestState < 2 then
					local canFit = TransportAPI.CanPassengerFitInTransporter(transportID, unitID, transporterDefID, passengerSize, 0)
					if canFit then
						bestState = 2
						break
					end
				end
			end
			local isOverSized = UnitDefs[passengerDefID].customParams.oversized == "1"
			local color = {0,0,0,0}
			if bestState == 0 then
				canBePickedUp = false
			elseif bestState == 1 then
				canBePickedUp = true
				color = { 1, 0.5, 0, 0.8} -- orange
			elseif bestState == 2 and isOverSized then
				canBePickedUp = true
				color = { 1, 1, 0, 0.8} -- yellow
			else
				canBePickedUp = true
				color = { 0, 1, 0, 0.8} -- green
			end

			if canBePickedUp then
				local x, y, z = Spring.GetUnitBasePosition(unitID)
				if x then
					-- we have to scale up passengerFootprintX otherwise indicator would be under the unit instead of around it
					unitsToDraw[unitID] = { pos = { x, y, z }, size = passengerSize, color = color}
				end
			end
		end
	end
end

local cursorGround = { 0, 0, 0 }

function widget:Update()
	if not next(unitsToDraw) then
		return
	end

	local mx, my = Spring.GetMouseState()
	local _, coords = Spring.TraceScreenRay(mx, my, true)

	if type(coords) == "table" then
		cursorGround = coords
	end
end

local previousOsClock = os.clock()
local currentRotationAngle = 0
local currentRotationAngleOpposite = 0
function widget:RecvLuaMsg(msg)
	if msg:sub(1, 18) == "LobbyOverlayActive" then
		chobbyInterface = (msg:sub(1, 19) == "LobbyOverlayActive1")
	end
end

function widget:DrawWorldPreUnit()
	if chobbyInterface then
		return
	end

	if not next(unitsToDraw) then
		return
	end

	if rotationSpeed > 0 then
		local clockDifference = (os.clock() - previousOsClock)
		previousOsClock = os.clock()

		local angleDifference = rotationSpeed * (clockDifference * 5)
		currentRotationAngle = currentRotationAngle + (angleDifference * 0.66)
		if currentRotationAngle > 360 then
			currentRotationAngle = currentRotationAngle - 360
		end

		currentRotationAngleOpposite = currentRotationAngleOpposite - angleDifference
		if currentRotationAngleOpposite < -360 then
			currentRotationAngleOpposite = currentRotationAngleOpposite + 360
		end
	end

	local alpha = 1
	for unitID, opts in pairs(unitsToDraw) do
		local pos = opts.pos
		local xDiff = cursorGround[1] - pos[1]
		local zDiff = cursorGround[3] - pos[3]
		alpha = 1 - math_sqrt(xDiff * xDiff + zDiff * zDiff) / alphaFalloffDistance
		if alpha > maxAlpha then
			alpha = maxAlpha
		end
		if alpha > 0.04 then
			local size = opts.size
			if not circleList[size] then
				circleList[size] = gl.CreateList(function() DrawCircleLine(size) end)
			end
			local color = opts.color
			local thisSize = math.sqrt(2*size)/2 * springFootprintScale * indicatorSizeMultiplier
			gl.Color(color[1], color[2], color[3], alpha * color[4])
			gl.DrawListAtUnit(unitID, circleList[size], false, thisSize, 1.0, thisSize, currentRotationAngle, 0, 1, 0)
			--gl.DrawListAtUnit(unitID, circleList[size], false, thisSize * 1.18, 1.0, thisSize * 1.18, -currentRotationAngle * 8/size, 0, 1, 0)
		end
	end

	gl.Color(1, 1, 1, 1)
	gl.LineWidth(1)
end
