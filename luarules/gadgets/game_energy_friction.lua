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
local sqr = 8

local nCol = sizeX / sqr
local nRows = sizeZ / sqr

local nCells = nCol * nRows -- use finer grain if the map is small, lower res if the map is big, so that we're never over 128*128 cells total
while nCells > 128*128 do
	sqr = sqr * 2
	nCol = sizeX / sqr
	nRows = sizeZ / sqr
	nCells = nCol * nRows
end

local BLKSIZEX = sqr/sizeX
local BLKSIZEZ = sqr/sizeZ

function gadget:Initialize()
	Spring.Echo(sqr, nCells)
end

	
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

local distTable = {}
for dx = 0,nCol do
	distTable[dx] = {}
	for dz = 0, nRows do
		distTable[dx][dz] = math.sqrt((dx*sqr)^2 + (dz*sqr)^2)
	end
end


local function GetTaxValue(dist)
	local taxValue = math.min(0.5, math.max(0,(dist - taxStartDist) * taxPerDistConst)) -- clamped 0 - 0.5; value 0 at dist 256 and under, value 0.5 at dist 4096 and over, linear in between
	return taxValue
end

local function CellsDist(col1, row1, col2, row2)
	local dx, dz = math.abs(col2-col1), math.abs(row2-row1)
	local dist = distTable[dx][dz]
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

function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	if energyBuilding[unitDefID] then
		local amount = energyBuilding[unitDefID]
		local x,_,z = Spring.GetUnitPosition(unitID)
		AddCellValue(x,z,newTeam, amount)
		AddCellValue(x,z,oldTeam, -amount)
		FlushCellTaxValues(oldTeam)
		FlushCellTaxValues(newTeam)
	end
end

function gadget:AllowUnitBuildStep(builderID, builderTeam, unitID, unitDefID, part)
	local _,_,_,_,bProgress = Spring.GetUnitHealth (unitID)
	if part > 0 and bProgress < 1 then -- positive progress on unfinished building = build
		local x,_,z = Spring.GetUnitPosition(unitID)
		local uCol, uRow = math.floor(x/sqr), math.floor(z/sqr)
		local taxValue = cellTaxValue[builderTeam] and cellTaxValue[builderTeam][uCol] and cellTaxValue[builderTeam][uCol][uRow]
		if not taxValue then
			local meanDist = GetMeanDist(uCol, uRow, builderTeam)
			taxValue = GetTaxValue(meanDist)
			RegisterCellTaxValue(uCol, uRow, builderTeam, taxValue)
		end
		return ProcessBuildStep(builderID, builderTeam, unitID, unitDefID, part, taxValue)
	else
		return true
	end
end

-- Some unsynced stuff for perf tests (== full map map iterations)
-- local PendingChanges = {}

-- function gadget:Update()
	-- local MyTeam = Spring.GetMyTeamID()
	-- startCell = lastCell and (lastCell + 1) or 1
	-- for n = startCell, (startCell + 64) do
		-- lastCell = n
		-- local currentCellx, currentCellz = n%nCol, math.floor(n/nRows)
		-- local meanDist = GetMeanDist(currentCellx, currentCellz, MyTeam)
		-- local taxValue = GetTaxValue(meanDist)
		-- table.insert(PendingChanges, {x = currentCellx, z = currentCellz, tax = taxValue})
		-- if lastCell == nCells then
			-- break
		-- end
	-- end
	-- if lastCell == nCells then
		-- lastCell = 0
	-- end
-- end

-- function gadget:DrawGenesis()
	-- if #PendingChanges > 0 then
		-- for i = 1, #PendingChanges do
			-- Spring.Echo(PendingChanges[i].x,PendingChanges[i].z,PendingChanges[i].tax)
		-- end
		-- PendingChanges = {}
	-- end
-- end