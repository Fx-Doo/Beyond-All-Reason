-- Seam relaxation for the heightmap. Pure Lua, no engine calls.
--
-- A cross-fade between two unrelated parts of the map (a select / twin seam, a tile or wedge border...) turns the
-- height difference between them into a slope: 400 elmos over a 384 elmo band is a cliff that the diffuse texture does
-- not show and that units cannot cross. This module finds the edges of a coarse copy of the transformed heightmap that
-- are steeper than anything the source map has there and spreads the step over a wide ramp:
--
--   * an edge between two coarse nodes may not be steeper than max(cap, 1.5 x the source steepness at the place the
--     node shows). Source cliffs therefore stay, only slopes the transform made are touched;
--   * nodes that violate it, plus a margin (`reach`), are free to move; everything else is fixed;
--   * free nodes are relaxed pairwise (the two ends of a steep edge move towards each other by the same amount, so
--     the average height is kept) until every edge is within its limit or the margin is used up;
--   * the resulting difference is added to the full resolution grid (bilinear), so the fine detail stays;
--   * discs around protected points (metal spots, geo vents) are fixed, their exact shape is not touched.
--
-- Every step is symmetric, so a symmetric grid stays symmetric (the caller symmetrizes again to remove rounding noise).

-- Naming used throughout: the fine grid is the heightmap (cellsX x cellsZ corner-aligned nodes, cellSize elmos apart),
-- the coarse grid is every coarseStride-th node of it (coarseNodesX x coarseNodesZ nodes, coarseStep elmos apart, so
-- coarseStep = coarseStride * cellSize). Grids are flat arrays, index = nodeZ * coarseNodesX + nodeX + 1.

local floor, ceil, abs, max, min = math.floor, math.ceil, math.abs, math.max, math.min

local Relax = {}

Relax.CAP_MIN = 0.5 -- slope (rise / run) that is always allowed, 0.5 = 27 degrees
Relax.CAP_MAX = 1.0
Relax.REACH = 960 -- elmos a ramp may spread away from a violating edge
Relax.TARGET_STEP = 64 -- elmos between coarse nodes
Relax.FIXED_MARGIN = 1.5 -- fixed discs are r + this many coarse cells wide: a fine point inside r sees only fixed nodes
Relax.ITERATIONS = 400
Relax.ROCK_MIN = 0.4 -- slope from which a made-up slope is drawn as rock
Relax.MAX_ROCK = 2500 -- most rock nodes that are serialized into the rules param


--------------------------------------------------------------------------------------------------------------------
-- Coarse grid
--------------------------------------------------------------------------------------------------------------------

-- Coarse node spacing, in fine cells: the largest k <= TARGET_STEP / cellSize that divides the grid exactly.
-- Returns k, or nil when there is no usable k (k >= 2 is required).
function Relax.step(cellsX, cellsZ, cellSize)
	local coarseStride = max(1, floor(Relax.TARGET_STEP / cellSize + 0.5))
	while coarseStride > 1 and ((cellsX - 1) % coarseStride ~= 0 or (cellsZ - 1) % coarseStride ~= 0) do
		coarseStride = coarseStride - 1
	end
	if coarseStride < 2 then
		return nil
	end
	return coarseStride
end


-- Every coarseStride-th node of a fine grid (corner-aligned heightmap grid).
-- Returns the coarse grid and its size in nodes (coarseNodesX, coarseNodesZ).
function Relax.subsample(grid, cellsX, cellsZ, coarseStride)
	local coarseNodesX = (cellsX - 1) / coarseStride + 1
	local coarseNodesZ = (cellsZ - 1) / coarseStride + 1
	local coarse = {}
	for coarseZ = 0, coarseNodesZ - 1 do
		local fineRow = coarseZ * coarseStride * cellsX
		local coarseRow = coarseZ * coarseNodesX
		for coarseX = 0, coarseNodesX - 1 do
			coarse[coarseRow + coarseX + 1] = grid[fineRow + coarseX * coarseStride + 1]
		end
	end
	return coarse, coarseNodesX, coarseNodesZ
end


-- Steepest edge touching each node (rise / run), for a coarse height grid with node spacing coarseStep.
-- Returns a flat array of slopes.
local function nodeSlope(heights, coarseNodesX, coarseNodesZ, coarseStep)
	local slopes = {}
	for i = 1, coarseNodesX * coarseNodesZ do
		slopes[i] = 0
	end
	for nodeZ = 0, coarseNodesZ - 1 do
		for nodeX = 0, coarseNodesX - 1 do
			local node = nodeZ * coarseNodesX + nodeX + 1
			if nodeX < coarseNodesX - 1 then
				-- edge to the right neighbour
				local slope = abs(heights[node + 1] - heights[node]) / coarseStep
				if slope > slopes[node] then
					slopes[node] = slope
				end
				if slope > slopes[node + 1] then
					slopes[node + 1] = slope
				end
			end
			if nodeZ < coarseNodesZ - 1 then
				-- edge to the neighbour below
				local slope = abs(heights[node + coarseNodesX] - heights[node]) / coarseStep
				if slope > slopes[node] then
					slopes[node] = slope
				end
				if slope > slopes[node + coarseNodesX] then
					slopes[node + coarseNodesX] = slope
				end
			end
		end
	end
	return slopes
end


-- 1D box dilation of a boolean grid along x (vertical = false) or z (vertical = true): every node within `reach`
-- nodes of a flagged node (on the same row / column) becomes flagged. Done as a forward and a backward sweep that
-- remember the last flagged position. Returns the dilated boolean grid.
local function dilate(flagged, coarseNodesX, coarseNodesZ, reach, vertical)
	local dilated = {}
	-- lines run along the dilation direction: lineCount of them, lineLength nodes each
	local lineCount, lineLength = coarseNodesZ, coarseNodesX
	local alongStep, lineStep = 1, coarseNodesX -- index distance between neighbours along / across lines
	if vertical then
		lineCount, lineLength = coarseNodesX, coarseNodesZ
		alongStep, lineStep = coarseNodesX, 1
	end
	for line = 0, lineCount - 1 do
		local lineStart = line * lineStep + 1
		local lastFlagged = -1e9
		for position = 0, lineLength - 1 do
			local node = lineStart + position * alongStep
			if flagged[node] then
				lastFlagged = position
			end
			if position - lastFlagged <= reach then
				dilated[node] = true
			end
		end
		lastFlagged = 1e9
		for position = lineLength - 1, 0, -1 do
			local node = lineStart + position * alongStep
			if flagged[node] then
				lastFlagged = position
			end
			if lastFlagged - position <= reach then
				dilated[node] = true
			end
		end
	end
	return dilated
end

--------------------------------------------------------------------------------------------------------------------
-- Planning the corrections
--------------------------------------------------------------------------------------------------------------------

-- Coarse nodes that lie inside a protected disc (plus FIXED_MARGIN coarse cells).
--   discs: { { x, z, radius }, ... } in world elmos
-- Returns a boolean array (sparse) of coarse nodes that must not move.
local function fixedNodes(discs, coarseNodesX, coarseNodesZ, coarseStep)
	local fixed = {}
	for _, disc in ipairs(discs) do
		local reach = disc[3] + Relax.FIXED_MARGIN * coarseStep
		local reachSquared = reach * reach
		-- bounding box of the disc in node indices
		local firstX = max(0, floor((disc[1] - reach) / coarseStep))
		local lastX = min(coarseNodesX - 1, ceil((disc[1] + reach) / coarseStep))
		local firstZ = max(0, floor((disc[2] - reach) / coarseStep))
		local lastZ = min(coarseNodesZ - 1, ceil((disc[2] + reach) / coarseStep))
		for nodeZ = firstZ, lastZ do
			local deltaZ = nodeZ * coarseStep - disc[2]
			for nodeX = firstX, lastX do
				local deltaX = nodeX * coarseStep - disc[1]
				if deltaX * deltaX + deltaZ * deltaZ <= reachSquared then
					fixed[nodeZ * coarseNodesX + nodeX + 1] = true
				end
			end
		end
	end
	return fixed
end


-- The slope cap of a source map: a little above how steep it is almost everywhere (99th percentile of its coarse
-- nodes), clamped to [CAP_MIN, CAP_MAX]. baseSlopes: result of nodeSlope for the source map.
local function capOf(baseSlopes)
	local sorted = {}
	for i = 1, #baseSlopes do
		sorted[i] = baseSlopes[i]
	end
	table.sort(sorted)
	local p99 = sorted[max(1, floor(#sorted * 0.99))] or 0
	return min(Relax.CAP_MAX, max(Relax.CAP_MIN, 1.3 * p99))
end


-- Finds the coarse edges that are steeper than allowed and relaxes them (see the file header for the idea).
--   transform: the Transform; baseCoarse / outCoarse: coarse source and transformed heights
--   (coarseNodesX x coarseNodesZ nodes, spacing coarseStep, corner aligned)
--   discs: protected discs ({ x, z, radius }) at the places they are shown
-- Returns
--   heightCorrections: coarse height corrections per node (nil when nothing is steeper than allowed),
--   stats: { cap, nodes, flagged, residual, rewritten, maxShift, iterations },
--   dropDetail: nodes (value 1) around sheer edges where the fine detail must be dropped (only with corrections).
function Relax.plan(transform, baseCoarse, outCoarse, coarseNodesX, coarseNodesZ, coarseStep, discs)
	local nodeCount = coarseNodesX * coarseNodesZ
	local baseSlopes = nodeSlope(baseCoarse, coarseNodesX, coarseNodesZ, coarseStep)
	local cap = capOf(baseSlopes)

	-- steepness the source has around the place each node shows (3 x 3 nodes)
	local allowedSlope = {}
	for nodeZ = 0, coarseNodesZ - 1 do
		for nodeX = 0, coarseNodesX - 1 do
			local srcX, srcZ = transform:map(nodeX * coarseStep, nodeZ * coarseStep)
			local srcNodeX = min(coarseNodesX - 1, max(0, floor(srcX / coarseStep + 0.5)))
			local srcNodeZ = min(coarseNodesZ - 1, max(0, floor(srcZ / coarseStep + 0.5)))
			local steepest = 0
			for deltaZ = -1, 1 do
				local neighborZ = srcNodeZ + deltaZ
				if neighborZ >= 0 and neighborZ < coarseNodesZ then
					for deltaX = -1, 1 do
						local neighborX = srcNodeX + deltaX
						if neighborX >= 0 and neighborX < coarseNodesX then
							local neighborSlope = baseSlopes[neighborZ * coarseNodesX + neighborX + 1]
							if neighborSlope > steepest then
								steepest = neighborSlope
							end
						end
					end
				end
			end
			allowedSlope[nodeZ * coarseNodesX + nodeX + 1] = max(cap, 1.5 * steepest)
		end
	end

	local stats = {
		cap = cap, nodes = nodeCount, flagged = 0, residual = 0, rewritten = 0, maxShift = 0, iterations = 0,
	}

	-- violating edges: flag both end nodes
	local flaggedNodes = {}
	local flaggedCount = 0
	for nodeZ = 0, coarseNodesZ - 1 do
		for nodeX = 0, coarseNodesX - 1 do
			local node = nodeZ * coarseNodesX + nodeX + 1
			if nodeX < coarseNodesX - 1 then
				local limit = min(allowedSlope[node], allowedSlope[node + 1]) * coarseStep
				if abs(outCoarse[node + 1] - outCoarse[node]) > limit then
					flaggedNodes[node + 1] = true
					flaggedNodes[node] = true
				end
			end
			if nodeZ < coarseNodesZ - 1 then
				local limit = min(allowedSlope[node], allowedSlope[node + coarseNodesX]) * coarseStep
				if abs(outCoarse[node + coarseNodesX] - outCoarse[node]) > limit then
					flaggedNodes[node + coarseNodesX] = true
					flaggedNodes[node] = true
				end
			end
		end
	end
	for _ in pairs(flaggedNodes) do
		flaggedCount = flaggedCount + 1
	end
	stats.flagged = flaggedCount
	if flaggedCount == 0 then
		return nil, stats
	end

	-- free nodes: within REACH of a violating edge (dilated in x, then in z) and not inside a protected disc
	local reachNodes = ceil(Relax.REACH / coarseStep)
	local freeMask = dilate(dilate(flaggedNodes, coarseNodesX, coarseNodesZ, reachNodes, false),
		coarseNodesX, coarseNodesZ, reachNodes, true)
	local fixedDisc = fixedNodes(discs or {}, coarseNodesX, coarseNodesZ, coarseStep)
	local fixed = {}
	for node = 1, nodeCount do
		fixed[node] = fixedDisc[node] or not freeMask[node]
	end

	-- edges with at least one free end: edgeFrom[e] -- edgeTo[e], height difference limit edgeLimit[e]
	local edgeFrom, edgeTo, edgeLimit = {}, {}, {}
	local edgeCount = 0
	for nodeZ = 0, coarseNodesZ - 1 do
		for nodeX = 0, coarseNodesX - 1 do
			local node = nodeZ * coarseNodesX + nodeX + 1
			if nodeX < coarseNodesX - 1 and not (fixed[node] and fixed[node + 1]) then
				edgeCount = edgeCount + 1
				edgeFrom[edgeCount] = node
				edgeTo[edgeCount] = node + 1
				edgeLimit[edgeCount] = min(allowedSlope[node], allowedSlope[node + 1]) * coarseStep
			end
			if nodeZ < coarseNodesZ - 1 and not (fixed[node] and fixed[node + coarseNodesX]) then
				edgeCount = edgeCount + 1
				edgeFrom[edgeCount] = node
				edgeTo[edgeCount] = node + coarseNodesX
				edgeLimit[edgeCount] = min(allowedSlope[node], allowedSlope[node + coarseNodesX]) * coarseStep
			end
		end
	end

	local heights = {} -- working copy of the heights that gets relaxed
	local pending = {} -- height change collected for each node during one Jacobi sweep
	local freeNodes = {}
	for node = 1, nodeCount do
		heights[node] = outCoarse[node]
		pending[node] = 0
		if not fixed[node] then
			freeNodes[#freeNodes + 1] = node
		end
	end

	-- Jacobi relaxation: every sweep first collects the corrections of all edges, then applies them (damped by omega)
	local omega = 0.6
	local tolerance = 0.25
	local iterations = 0
	for iteration = 1, Relax.ITERATIONS do
		local worst = 0
		for edge = 1, edgeCount do
			local nodeA, nodeB = edgeFrom[edge], edgeTo[edge]
			local difference = heights[nodeB] - heights[nodeA]
			local excess = abs(difference) - edgeLimit[edge]
			if excess > 0 then
				if excess > worst then
					worst = excess
				end
				local signedExcess = difference > 0 and excess or -excess
				if fixed[nodeA] then
					pending[nodeB] = pending[nodeB] - signedExcess
				elseif fixed[nodeB] then
					pending[nodeA] = pending[nodeA] + signedExcess
				else
					pending[nodeA] = pending[nodeA] + 0.5 * signedExcess
					pending[nodeB] = pending[nodeB] - 0.5 * signedExcess
				end
			end
		end
		iterations = iteration
		if worst < tolerance then
			break
		end
		for f = 1, #freeNodes do
			local node = freeNodes[f]
			local change = pending[node]
			if change ~= 0 then
				heights[node] = heights[node] + omega * change
				pending[node] = 0
			end
		end
	end
	stats.iterations = iterations

	-- what is still too steep (a 10 % margin ignores the last bit of convergence)
	local residual = 0
	for edge = 1, edgeCount do
		if abs(heights[edgeTo[edge]] - heights[edgeFrom[edge]]) > edgeLimit[edge] * 1.1 then
			residual = residual + 1
		end
	end
	stats.residual = residual

	local heightCorrections = {}
	local rewritten, maxShift = 0, 0
	for node = 1, nodeCount do
		local change = heights[node] - outCoarse[node]
		heightCorrections[node] = change
		if abs(change) > 15 then
			rewritten = rewritten + 1
		end
		if abs(change) > maxShift then
			maxShift = abs(change)
		end
	end
	stats.rewritten = rewritten / nodeCount
	stats.maxShift = maxShift

	-- Where the cross-fade has no band at all the two heights sit one cell apart: a sheer step that no coarse
	-- correction can reach. In the cells that hold such an edge the fine detail is dropped, so the ramp is all
	-- there is.
	local dropDetail = {}
	for node in pairs(flaggedNodes) do
		if not fixedDisc[node] then
			dropDetail[node] = 1
		end
	end
	return heightCorrections, stats, dropDetail
end

--------------------------------------------------------------------------------------------------------------------
-- Applying the corrections
--------------------------------------------------------------------------------------------------------------------

-- Adds the coarse corrections (bilinear) to the fine grid `outGrid` (cellsX x cellsZ nodes, coarseStride fine cells
-- per coarse cell). Edits outGrid in place.
--   heightCorrections: from Relax.plan; coarseNodesX / coarseNodesZ: coarse grid size
--   outCoarse: the coarse heights heightCorrections was computed from
--   dropWeights[node] (0..1, nil = 0): removes that share of the fine detail (outGrid minus the bilinear coarse
--   heights) around coarse node `node`
-- In the variable names the digits are the (x, z) corner of the coarse cell: 00 = left/top, 10 = right/top, ...
function Relax.apply(outGrid, cellsX, cellsZ, coarseStride, heightCorrections, coarseNodesX, coarseNodesZ,
		outCoarse, dropWeights)
	local inverseStride = 1 / coarseStride
	for coarseZ = 0, coarseNodesZ - 2 do
		for coarseX = 0, coarseNodesX - 2 do
			local node = coarseZ * coarseNodesX + coarseX + 1
			local corr00 = heightCorrections[node]
			local corr10 = heightCorrections[node + 1]
			local corr01 = heightCorrections[node + coarseNodesX]
			local corr11 = heightCorrections[node + coarseNodesX + 1]
			local drop00 = dropWeights[node] or 0
			local drop10 = dropWeights[node + 1] or 0
			local drop01 = dropWeights[node + coarseNodesX] or 0
			local drop11 = dropWeights[node + coarseNodesX + 1] or 0
			-- cells without any correction or detail drop stay untouched
			if corr00 ~= 0 or corr10 ~= 0 or corr01 ~= 0 or corr11 ~= 0
				or drop00 > 0 or drop10 > 0 or drop01 > 0 or drop11 > 0 then
				local height00 = outCoarse[node]
				local height10 = outCoarse[node + 1]
				local height01 = outCoarse[node + coarseNodesX]
				local height11 = outCoarse[node + coarseNodesX + 1]
				-- the last coarse cell of a row / column also owns the fine nodes on the far grid border
				local lastFineX = (coarseX == coarseNodesX - 2) and coarseStride or coarseStride - 1
				local lastFineZ = (coarseZ == coarseNodesZ - 2) and coarseStride or coarseStride - 1
				for fineZ = 0, lastFineZ do
					local fracZ = fineZ * inverseStride
					-- left / right edge of the coarse cell, interpolated to this fine row
					local corrLeft = corr00 * (1 - fracZ) + corr01 * fracZ
					local corrRight = corr10 * (1 - fracZ) + corr11 * fracZ
					local dropLeft = drop00 * (1 - fracZ) + drop01 * fracZ
					local dropRight = drop10 * (1 - fracZ) + drop11 * fracZ
					local heightLeft = height00 * (1 - fracZ) + height01 * fracZ
					local heightRight = height10 * (1 - fracZ) + height11 * fracZ
					local rowStart = (coarseZ * coarseStride + fineZ) * cellsX + coarseX * coarseStride + 1
					for fineX = 0, lastFineX do
						local fracX = fineX * inverseStride
						local drop = dropLeft * (1 - fracX) + dropRight * fracX
						local value = outGrid[rowStart + fineX]
						local coarseValue = heightLeft * (1 - fracX) + heightRight * fracX
						outGrid[rowStart + fineX] = value - drop * (value - coarseValue)
							+ corrLeft * (1 - fracX) + corrRight * fracX
					end
				end
			end
		end
	end
end


-- Whole pass on a fine grid: returns the stats (and edits `outGrid` in place). `base` is the untouched source grid.
--   transform: the Transform; base / outGrid: fine source / transformed heights (cellsX x cellsZ, cellSize)
--   discs: protected discs, see Relax.plan
-- Returns { skipped = true } when the grid has no usable coarse step, otherwise the stats of Relax.plan plus
-- stats.rock: { ncx, ncz, cs, weights } (weights sparse, 0..1) for the nodes this pass reshaped that are still steep:
-- the diffuse texture draws them as rock, so a ramp that is too steep to hide looks like a cliff.
function Relax.run(transform, base, outGrid, cellsX, cellsZ, cellSize, discs)
	local coarseStride = Relax.step(cellsX, cellsZ, cellSize)
	if not coarseStride then
		return { skipped = true }
	end
	local baseCoarse, coarseNodesX, coarseNodesZ = Relax.subsample(base, cellsX, cellsZ, coarseStride)
	local outCoarse = Relax.subsample(outGrid, cellsX, cellsZ, coarseStride)
	local heightCorrections, stats, dropDetail = Relax.plan(
		transform, baseCoarse, outCoarse, coarseNodesX, coarseNodesZ, coarseStride * cellSize, discs
	)
	if heightCorrections then
		Relax.apply(
			outGrid, cellsX, cellsZ, coarseStride, heightCorrections, coarseNodesX, coarseNodesZ, outCoarse, dropDetail
		)
		local coarseStep = coarseStride * cellSize
		-- slopes after the correction: the ones that are still steep are drawn as rock
		local slopes = nodeSlope((Relax.subsample(outGrid, cellsX, cellsZ, coarseStride)), coarseNodesX, coarseNodesZ,
			coarseStep)
		local weights = {}
		for node = 1, coarseNodesX * coarseNodesZ do
			if slopes[node] > Relax.ROCK_MIN and (dropDetail[node] or abs(heightCorrections[node]) > 5) then
				weights[node] = min(1, (slopes[node] - Relax.ROCK_MIN) / 0.4)
			end
		end
		stats.rock = { ncx = coarseNodesX, ncz = coarseNodesZ, cs = coarseStep, weights = weights }
	end
	return stats
end


--------------------------------------------------------------------------------------------------------------------
-- Rock weights: serialization
--------------------------------------------------------------------------------------------------------------------

-- Rock weights as a rules param string: "ncx;ncz;cs;index:digit,..." (digit 1..9 = weight, at most MAX_ROCK nodes,
-- strongest first). rock: stats.rock of Relax.run (may be nil). Returns "" when there is nothing to draw.
function Relax.serializeRock(rock)
	if not rock then
		return ""
	end
	local entries = {}
	for node, weight in pairs(rock.weights) do
		local digit = floor(weight * 9 + 0.5)
		if digit >= 1 then
			entries[#entries + 1] = { node, digit }
		end
	end
	if #entries == 0 then
		return ""
	end
	-- strongest weight first, ties by node index, so the output is deterministic
	table.sort(entries, function(left, right)
		if left[2] ~= right[2] then
			return left[2] > right[2]
		end
		return left[1] < right[1]
	end)
	local parts = {}
	for n = 1, min(#entries, Relax.MAX_ROCK) do
		parts[n] = entries[n][1] .. ":" .. entries[n][2]
	end
	return string.format("%d;%d;%d;", rock.ncx, rock.ncz, rock.cs) .. table.concat(parts, ",")
end


-- Inverse of Relax.serializeRock. Returns { ncx, ncz, cs, weights } (weights = digit / 9), or nil for an empty or
-- malformed string.
function Relax.parseRock(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local coarseNodesX, coarseNodesZ, coarseStep, body = text:match("^(%d+);(%d+);(%d+);(.*)$")
	if not coarseNodesX then
		return nil
	end
	local weights = {}
	for node, digit in body:gmatch("(%d+):(%d)") do
		weights[tonumber(node)] = tonumber(digit) / 9
	end
	return {
		ncx = tonumber(coarseNodesX), ncz = tonumber(coarseNodesZ), cs = tonumber(coarseStep), weights = weights,
	}
end


--------------------------------------------------------------------------------------------------------------------
-- Protected discs
--------------------------------------------------------------------------------------------------------------------

-- Protected discs at every place the transform shows a protected point.
--   points: { { x, z, radius, ... }, ... } in base (source) map coordinates
-- Returns { { x, z, radius }, ... } in output world elmos.
function Relax.discs(transform, points)
	local discs = {}
	for _, point in ipairs(points) do
		for _, image in ipairs(transform:preimages(point[1], point[2])) do
			discs[#discs + 1] = { image[1], image[2], point[3] }
		end
	end
	return discs
end

return Relax
