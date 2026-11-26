-- Resampling of regular grids through a Transform. Pure Lua, no engine calls.
--
-- Grids are flat arrays, index = cellZ * cellsX + cellX + 1.
--   centered = false: sample (cellX, cellZ) sits at (cellX * cellSize, cellZ * cellSize)    (heightmap corners)
--   centered = true : sample (cellX, cellZ) sits at ((cellX + 0.5) * cellSize, ...)         (metal map cells)
--
-- Naming used throughout: "out" = a position / grid of the transformed (output) map, "src" = a position / grid of
-- the untransformed source map. `offset` is the 0 / 0.5 cell shift that goes with `centered`.

local floor = math.floor
local abs = math.abs

local Field = {}


--------------------------------------------------------------------------------------------------------------------
-- Sampling
--------------------------------------------------------------------------------------------------------------------

-- Clamps a 0-based grid index into the valid range [0, count - 1].
local function clampIndex(index, count)
	if index < 0 then
		return 0
	elseif index > count - 1 then
		return count - 1
	end
	return index
end


-- Bilinear interpolation of a grid at a world position (continuous data); positions outside are clamped to the edge.
--   data: flat grid; cellsX, cellsZ: grid size; cellSize: world size of a cell; offset: 0 (corners) or 0.5 (centres)
--   sampleX, sampleZ: world position to sample at
-- Returns the interpolated value.
local function bilinear(data, cellsX, cellsZ, cellSize, offset, sampleX, sampleZ)
	local gridX = sampleX / cellSize - offset
	local gridZ = sampleZ / cellSize - offset
	local cellX = floor(gridX)
	local cellZ = floor(gridZ)
	local fracX = gridX - cellX
	local fracZ = gridZ - cellZ
	local leftX = clampIndex(cellX, cellsX)
	local rightX = clampIndex(cellX + 1, cellsX)
	local upperZ = clampIndex(cellZ, cellsZ)
	local lowerZ = clampIndex(cellZ + 1, cellsZ)
	local upperRow = upperZ * cellsX
	local lowerRow = lowerZ * cellsX
	local top = data[upperRow + leftX + 1] * (1 - fracX) + data[upperRow + rightX + 1] * fracX
	local bottom = data[lowerRow + leftX + 1] * (1 - fracX) + data[lowerRow + rightX + 1] * fracX
	return top * (1 - fracZ) + bottom * fracZ
end


-- Nearest-neighbour lookup of a grid at a world position (never mixes values: peaks and ids stay intact).
-- Same parameters as bilinear. Returns the value of the closest cell.
local function nearest(data, cellsX, cellsZ, cellSize, offset, sampleX, sampleZ)
	local cellX = clampIndex(floor(sampleX / cellSize - offset + 0.5), cellsX)
	local cellZ = clampIndex(floor(sampleZ / cellSize - offset + 0.5), cellsZ)
	return data[cellZ * cellsX + cellX + 1]
end

Field.bilinear = bilinear
Field.nearest = nearest


--------------------------------------------------------------------------------------------------------------------
-- Mirror cells of the closing symmetry
--------------------------------------------------------------------------------------------------------------------

-- The chain always starts with an exact symmetry S (descs[1].closing), so out(p) == out(S(p)): only half of the
-- cells need the transform, the rest are copied from their mirror cell.
--   transform: the Transform; cellsX, cellsZ, cellSize, centered: the grid layout
-- Returns a function (cellX, cellZ) -> index of the mirror cell (0-based linear), or nil when the grid does not map
-- onto itself exactly (then everything is computed).
local function mirrorOf(transform, cellsX, cellsZ, cellSize, centered)
	local firstDesc = transform.descs and transform.descs[1]
	local closingKind = firstDesc and firstDesc.closing
	if not closingKind then
		return nil
	end
	local mapWidth, mapHeight = transform.W, transform.H
	local gridWidth = (centered and cellsX or cellsX - 1) * cellSize
	local gridHeight = (centered and cellsZ or cellsZ - 1) * cellSize
	if gridWidth ~= mapWidth or gridHeight ~= mapHeight then
		return nil
	end
	if closingKind == "vertical" then
		return function(cellX, cellZ)
			return cellZ * cellsX + (cellsX - 1 - cellX)
		end
	elseif closingKind == "horizontal" then
		return function(cellX, cellZ)
			return (cellsZ - 1 - cellZ) * cellsX + cellX
		end
	elseif closingKind == "central" then
		return function(cellX, cellZ)
			return (cellsZ - 1 - cellZ) * cellsX + (cellsX - 1 - cellX)
		end
	elseif closingKind == "diagonal" and cellsX == cellsZ then
		if firstDesc.angle == math.pi / 4 then
			return function(cellX, cellZ)
				return cellX * cellsX + cellZ
			end
		end
		return function(cellX, cellZ)
			return (cellsX - 1 - cellX) * cellsX + (cellsZ - 1 - cellZ)
		end
	end
	return nil
end


--------------------------------------------------------------------------------------------------------------------
-- Remapping a whole grid
--------------------------------------------------------------------------------------------------------------------

-- Builds the transformed grid: every output cell is a weighted sum of source samples at the positions the transform
-- ("taps") says it shows.
--   transform: the Transform; base: source grid (cellsX x cellsZ, cellSize, centered as described in the header)
--   interp: "bilinear" (continuous data) or "nearest" (keeps peaks sharp)
-- Returns the new grid.
function Field.remap(transform, base, cellsX, cellsZ, cellSize, centered, interp)
	local offset = centered and 0.5 or 0
	local sample = (interp == "nearest") and nearest or bilinear
	local mirror = mirrorOf(transform, cellsX, cellsZ, cellSize, centered)
	local outGrid = {}
	for cellZ = 0, cellsZ - 1 do
		local outZ = (cellZ + offset) * cellSize
		local rowStart = cellZ * cellsX
		for cellX = 0, cellsX - 1 do
			local mirrorIndex = mirror and mirror(cellX, cellZ)
			if mirrorIndex and mirrorIndex < rowStart + cellX then
				-- the mirror cell comes earlier in iteration order, so it is already computed
				outGrid[rowStart + cellX + 1] = outGrid[mirrorIndex + 1]
			else
				local tapCount, tapsX, tapsZ, tapWeights = transform:taps((cellX + offset) * cellSize, outZ)
				local value
				if tapCount == 1 then
					value = sample(base, cellsX, cellsZ, cellSize, offset, tapsX[1], tapsZ[1])
				else
					value = 0
					for tap = 1, tapCount do
						value = value
							+ tapWeights[tap] * sample(base, cellsX, cellsZ, cellSize, offset, tapsX[tap], tapsZ[tap])
					end
				end
				outGrid[rowStart + cellX + 1] = value
			end
		end
	end
	return outGrid
end


-- Discrete data (type maps, ids): follows the dominant branch only, never mixes values.
-- Same parameters as Field.remap without `interp`. Returns the new grid.
function Field.remapHard(transform, base, cellsX, cellsZ, cellSize, centered)
	local offset = centered and 0.5 or 0
	local mirror = mirrorOf(transform, cellsX, cellsZ, cellSize, centered)
	local outGrid = {}
	for cellZ = 0, cellsZ - 1 do
		local outZ = (cellZ + offset) * cellSize
		local rowStart = cellZ * cellsX
		for cellX = 0, cellsX - 1 do
			local mirrorIndex = mirror and mirror(cellX, cellZ)
			if mirrorIndex and mirrorIndex < rowStart + cellX then
				outGrid[rowStart + cellX + 1] = outGrid[mirrorIndex + 1]
			else
				local srcX, srcZ = transform:map((cellX + offset) * cellSize, outZ)
				outGrid[rowStart + cellX + 1] = nearest(base, cellsX, cellsZ, cellSize, offset, srcX, srcZ)
			end
		end
	end
	return outGrid
end


-- Copies one half of a grid onto the other along the chain's closing symmetry (exact symmetry after local edits).
-- Edits `grid` in place; does nothing when the grid has no exact mirror.
function Field.symmetrize(transform, grid, cellsX, cellsZ, cellSize, centered)
	local mirror = mirrorOf(transform, cellsX, cellsZ, cellSize, centered)
	if not mirror then
		return
	end
	for cellZ = 0, cellsZ - 1 do
		for cellX = 0, cellsX - 1 do
			local cellIndex = cellZ * cellsX + cellX
			local mirrorIndex = mirror(cellX, cellZ)
			if mirrorIndex < cellIndex then
				grid[cellIndex + 1] = grid[mirrorIndex + 1]
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Metal total
--------------------------------------------------------------------------------------------------------------------

-- Scales every cell by one common factor so that the grid sums to `target`, rounding each cell to an integer and
-- capping it at maxValue (the engine's metal cell limit, 255). The cap makes the total a non-linear function of the
-- factor, so the factor is searched (bisection on the sparse list of non-zero cells) instead of computed.
--   grid: flat metal grid; target: wanted sum; maxValue: per-cell cap (default 255)
-- Returns the new grid, the factor, the achieved total and how many cells sit at the cap; the target is missed only
-- when too many cells saturate.
function Field.scaleToTotal(grid, target, maxValue)
	maxValue = maxValue or 255
	local nonZero = {}
	for i = 1, #grid do
		if grid[i] > 0 then
			nonZero[#nonZero + 1] = grid[i]
		end
	end

	-- total of the rounded, capped cells for a given scale factor
	local function totalFor(factor)
		local total = 0
		for i = 1, #nonZero do
			local value = floor(nonZero[i] * factor + 0.5)
			total = total + (value > maxValue and maxValue or value)
		end
		return total
	end

	local scale = 1
	if #nonZero > 0 and target > 0 then
		-- never boost beyond the point where the strongest cell reaches the cap: more would flatten every spot to 255
		local peak = 0
		for i = 1, #nonZero do
			if nonZero[i] > peak then
				peak = nonZero[i]
			end
		end
		local maxScale = maxValue / peak
		if maxScale < 1 then
			maxScale = 1
		end
		if totalFor(maxScale) < target then
			scale = maxScale -- cannot reach the target without distorting the spots; the shortfall is reported
		else
			local lo, hi = 0, maxScale
			for _ = 1, 50 do
				local mid = (lo + hi) / 2
				if totalFor(mid) < target then
					lo = mid
				else
					hi = mid
				end
			end
			-- hi is the smallest factor reaching the target; lo may be closer when rounding overshoots
			scale = (abs(totalFor(lo) - target) < abs(totalFor(hi) - target)) and lo or hi
		end
	end

	local scaled, saturated, sum = {}, 0, 0
	for i = 1, #grid do
		local value = grid[i] > 0 and floor(grid[i] * scale + 0.5) or 0
		if value >= maxValue then
			value = maxValue
			saturated = saturated + 1
		end
		scaled[i] = value
		sum = sum + value
	end
	return scaled, scale, sum, saturated
end


--------------------------------------------------------------------------------------------------------------------
-- Metal spots
--------------------------------------------------------------------------------------------------------------------

-- Metal spots are small clusters of metal cells. Resampling them through a warp smears or drops cells, so each
-- cluster is lifted out of the grid and stamped, unchanged (same cells, same values), at every place the transform
-- shows it. Anything bigger than a spot (metal fields, gradients) stays in the grid and goes through the normal remap.

-- Finds the spot-sized clusters of a metal grid (8-connected cells > 0).
--   base: flat metal grid (cellsX x cellsZ)
--   opts.maxCells / opts.maxSpan: largest cluster (in cells / per side) still treated as a spot
-- Returns the spots ({ cells = { {cellX, cellZ, value}, ... }, mx, mz = value-weighted centre in cell units }) and a
-- copy of the grid with the spots cleared.
function Field.findSpots(base, cellsX, cellsZ, opts)
	opts = opts or {}
	local maxCells = opts.maxCells or 80
	local maxSpan = opts.maxSpan or 12
	local visited, spots = {}, {}
	local clearedGrid = {}
	for i = 1, cellsX * cellsZ do
		clearedGrid[i] = base[i]
	end

	for startIndex = 1, cellsX * cellsZ do
		if base[startIndex] > 0 and not visited[startIndex] then
			-- flood fill (depth first, explicit stack) over the 8-neighbourhood
			local stack, cells = { startIndex }, {}
			visited[startIndex] = true
			local minX, maxX = cellsX, -1
			local minZ, maxZ = cellsZ, -1
			while #stack > 0 do
				local index = stack[#stack]
				stack[#stack] = nil
				local cellX = (index - 1) % cellsX
				local cellZ = floor((index - 1) / cellsX)
				cells[#cells + 1] = { cellX, cellZ, base[index] }
				minX = math.min(minX, cellX)
				maxX = math.max(maxX, cellX)
				minZ = math.min(minZ, cellZ)
				maxZ = math.max(maxZ, cellZ)
				for deltaZ = -1, 1 do
					for deltaX = -1, 1 do
						local neighborX = cellX + deltaX
						local neighborZ = cellZ + deltaZ
						if neighborX >= 0 and neighborX < cellsX and neighborZ >= 0 and neighborZ < cellsZ then
							local neighborIndex = neighborZ * cellsX + neighborX + 1
							if base[neighborIndex] > 0 and not visited[neighborIndex] then
								visited[neighborIndex] = true
								stack[#stack + 1] = neighborIndex
							end
						end
					end
				end
			end

			if #cells <= maxCells and maxX - minX < maxSpan and maxZ - minZ < maxSpan then
				-- value-weighted centre of the cluster
				local sumX, sumZ, sumWeight = 0, 0, 0
				for _, cell in ipairs(cells) do
					sumX = sumX + cell[1] * cell[3]
					sumZ = sumZ + cell[2] * cell[3]
					sumWeight = sumWeight + cell[3]
				end
				spots[#spots + 1] = { cells = cells, mx = sumX / sumWeight, mz = sumZ / sumWeight }
				for _, cell in ipairs(cells) do
					clearedGrid[cell[2] * cellsX + cell[1] + 1] = 0
				end
			end
		end
	end
	return spots, clearedGrid
end


-- Every place (world position) where the transform shows each point of `points` ({ x, z, ... } list).
-- Returns a list parallel to `points`; entry i is the list of positions { x, z } of point i.
function Field.imagesOf(transform, points)
	local images = {}
	for i, point in ipairs(points) do
		images[i] = transform:preimages(point[1], point[2])
	end
	return images
end


-- How faithfully the transform copies a set of protected points (metal spots, geo vents): every copy must sit in a
-- clean neighbourhood (see Transform:isClean), otherwise a seam / blend band would cut it in half.
--   points[i] = { x, z, radius }; images: from Field.imagesOf
-- Returns total copies, dirty copies, points without any copy.
function Field.cleanliness(transform, points, images)
	local total, dirty, lost = 0, 0, 0
	for i, point in ipairs(points) do
		local copies = images[i]
		if #copies == 0 then
			lost = lost + 1
		end
		for _, copy in ipairs(copies) do
			total = total + 1
			if not transform:isClean(copy[1], copy[2], point[3]) then
				dirty = dirty + 1
			end
		end
	end
	return total, dirty, lost
end


-- Remaps a metal grid spot by spot: the spots are stamped unchanged at every image, the rest follows remapHard.
--   base: flat metal grid (centered cells, cellsX x cellsZ, cellSize)
--   opts.spots / opts.field / opts.images: results of findSpots / imagesOf when the caller already has them
--   (opts.field is the grid with the spots cleared); opts.maxCells / opts.maxSpan are passed on to findSpots
-- Returns the new grid, the number of spots found and the number of copies placed.
function Field.remapSpots(transform, base, cellsX, cellsZ, cellSize, opts)
	opts = opts or {}
	local spots, field = opts.spots, opts.field
	if not spots then
		spots, field = Field.findSpots(base, cellsX, cellsZ, opts)
	end
	local images = opts.images
	if not images then
		local points = {}
		for i, spot in ipairs(spots) do
			points[i] = { (spot.mx + 0.5) * cellSize, (spot.mz + 0.5) * cellSize }
		end
		images = Field.imagesOf(transform, points)
	end

	-- the remaining metal follows the dominant branch only: metal is never cross-faded, a cell is always a source value
	local outGrid = Field.remapHard(transform, field, cellsX, cellsZ, cellSize, true)
	local mirror = mirrorOf(transform, cellsX, cellsZ, cellSize, true)
	local placed = 0
	for i, spot in ipairs(spots) do
		-- anchor cell of the cluster: the cell the images are positioned by
		local anchorX = floor(spot.mx + 0.5)
		local anchorZ = floor(spot.mz + 0.5)
		for _, image in ipairs(images[i]) do
			local targetX = floor(image[1] / cellSize)
			local targetZ = floor(image[2] / cellSize)
			placed = placed + 1
			for _, cell in ipairs(spot.cells) do
				local stampX = cell[1] - anchorX + targetX
				local stampZ = cell[2] - anchorZ + targetZ
				if stampX >= 0 and stampX < cellsX and stampZ >= 0 and stampZ < cellsZ then
					outGrid[stampZ * cellsX + stampX + 1] = cell[3]
				end
			end
		end
	end

	-- the closing symmetry is exact on the grid: copy one half onto the other
	if mirror then
		for cellZ = 0, cellsZ - 1 do
			for cellX = 0, cellsX - 1 do
				local cellIndex = cellZ * cellsX + cellX
				local mirrorIndex = mirror(cellX, cellZ)
				if mirrorIndex < cellIndex then
					outGrid[cellIndex + 1] = outGrid[mirrorIndex + 1]
				end
			end
		end
	end
	return outGrid, #spots, placed
end

return Field

