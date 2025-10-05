function gadget:GetInfo()
	return {
		name	= "Energy Friction",
		desc	= "Adds friction to energy transfers",
		author	= "Doo",
		date	= "September 2025 (wip)",
		layer	= -100,
        enabled = true,--(select(1, Spring.GetGameFrame()) <= 0),
	}
end

local sizeX = Game.mapSizeX
local sizeZ = Game.mapSizeZ
local sqr = 64

local nCol = sizeX / sqr
local nRows = sizeZ / sqr

local nCells = nCol * nRows
local energyProdPerCell = {}
local cellTaxValue = {}

local taxStartDist = 256 -- start at 256 elmos
local taxEndDist = 4096 -- max tax at 4096 elmos
local maxTax = 0.5 -- 50%

local taxPerDistConst = maxTax/(taxEndDist - taxStartDist)
local avgWind = math.sqrt(((Game.windMin + Game.windMax)/2)^2)

local energyBuilding = {}

for defID, defs in pairs (UnitDefs) do
	if defs.isBuilding == true then
		if (defs.energyMake > 0 ) then
			energyBuilding[defID] = defs.energyMake
		elseif defs.energyUpkeep < 0 then
			energyBuilding[defID] = -defs.energyUpkeep
		elseif defs.windGenerator > 0 then
			energyBuilding[defID] = avgWind
		end
	end
end


local function GetTaxValue(dist)
	local taxValue = math.min(0.5, math.max(0,(dist - taxStartDist) * taxPerDistConst)) -- clamped 0 - 0.5; value 0 at dist 256 and under, value 0.5 at dist 4096 and over, linear in between
	return taxValue
end

local function CellsDist(col1, row1, col2, row2)
	local dist = math.sqrt((sqr*(col2-col1))^2 + (sqr*(row2-row1))^2)
	return dist
end

local function AddCellValue(x, z, team, amount)
	local col, row = math.floor(x/sqr), math.floor(z/sqr)
	energyProdPerCell[team] = energyProdPerCell[team] or {}
	energyProdPerCell[team][col] = energyProdPerCell[team][col] or {}
	energyProdPerCell[team][col][row] = math.max((energyProdPerCell[team][col][row] and (energyProdPerCell[team][col][row] + amount) or amount ), 0)
	if energyProdPerCell[team][col][row] == 0 then
		energyProdPerCell[team][col][row] = nil
	end
end

local function RegisterCellTaxValue(col, row, team, taxValue)
	cellTaxValue[team] = cellTaxValue[team] or {}
	cellTaxValue[team][col] = cellTaxValue[team][col] or {}
	cellTaxValue[team][col][row] = taxValue
end

local function FlushCellTaxValues(team)
	cellTaxValue[team] = {}
end

local function GetMeanDist(uCol, uRow, team)
	if not energyProdPerCell[team] then
		return 0
	end
	local totProd = 0
	local dist = 0
	for pCol, colTab in pairs (energyProdPerCell[team]) do
		for pRow, eProd in pairs (colTab) do
			dist = dist + eProd * CellsDist(uCol, uRow, pCol, pRow)
			totProd = totProd + eProd
		end
	end
	if totProd == 0 then
		return 0
	end
	local meanDist = dist / totProd
	return meanDist
end
			
local function ProcessBuildStep(builderID, builderTeam, unitID, unitDefID, part, taxValue)
	local partEValue = UnitDefs[unitDefID].energyCost * part
	local taxEValue = taxValue * partEValue
	local partEValue = taxEValue + partEValue
	local currentE = Spring.GetTeamResources ( builderTeam, "energy" )
	if currentE >= partEValue then
		Spring.UseUnitResource(builderID,"e", taxEValue)
		return true
	else
		return false
	end
end

function gadget:UnitFinished(unitID, unitDefID, team)
	if energyBuilding[unitDefID] then
		local amount = energyBuilding[unitDefID]
		local x,_,z = Spring.GetUnitPosition(unitID)
		AddCellValue(x,z,team, amount)
		FlushCellTaxValues(team)
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, team)
	if energyBuilding[unitDefID] then
		local amount = energyBuilding[unitDefID]
		local x,_,z = Spring.GetUnitPosition(unitID)
		AddCellValue(x,z,team,-amount)
		FlushCellTaxValues(team)
	end
end

function gadget:AllowUnitBuildStep(builderID, builderTeam, unitID, unitDefID, part)
	local _,_,_,_,bProgress = Spring.GetUnitHealth (unitID)
	if part > 0 and bProgress < 1 then -- positive progress on unfinished building = build
		local x,_,z = Spring.GetUnitPosition(unitID)
		local uCol, uRow = math.floor(x/sqr), math.floor(z/sqr)
		local meanDist = GetMeanDist(uCol, uRow, builderTeam)
		local taxValue = cellTaxValue[builderTeam] and cellTaxValue[builderTeam][uCol] and cellTaxValue[builderTeam][uCol][uRow] or GetTaxValue(meanDist)
		RegisterCellTaxValue(uCol, uRow, builderTeam, taxValue)
		return ProcessBuildStep(builderID, builderTeam, unitID, unitDefID, part, taxValue)
	else
		return true
	end
end
	