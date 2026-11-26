-- Composable gather transform T(outX, outZ) -> srcX, srcZ over map coordinates (elmos).
--
-- A transform is built from a list of plain-data descriptors (see generate.lua), so the exact same
-- transform can be rebuilt in synced and unsynced Lua (and later handed to a shader as uniforms).
--
-- Semantics are "gather": the value shown at an output position is the original value found at T(position).
-- Naming used throughout this file:
--   srcX, srcZ  a position in the ORIGINAL map that an output position reads from
--   outX, outZ  a position in the transformed (output) map
--   x, z        a position with no particular source/output meaning (e.g. between two chain steps)
-- Steps run in order; each step maps the position produced by the previous one.
--
-- Each step function returns (tapAX, tapAZ, weightA, tapBX, tapBZ): weight weightA on position A and
-- weight (1 - weightA) on position B, where B defaults to the unchanged input. That is how seams get
-- cross-faded: close to a seam a step returns two taps instead of one, and the layer blends the values
-- fetched at both.
--
-- Primitive kinds:
--   reflect  fold across a line (optionally wavy)
--   rotate   fold with a rotation about a point instead of a mirror
--   nfold    n-sector kaleidoscope around a centre (optionally mirrored; twist, radial rings, narrow wedge)
--   tile     grid of cells (repeat / mirror / brick offset / shuffled / flipped cells, optional seam blend)
--   wallpaper  reflection into the fundamental triangle of a p4m / p3m1 / p6m mirror lattice
--   warp     smooth sine domain warp
--   zoom     similarity: scale + rotate + translate
--   select   masked choice between two sub-chains (halfplane or disc mask); folds inside the branches always apply

local floor, ceil, sin, cos, sqrt, abs, pi = math.floor, math.ceil, math.sin, math.cos, math.sqrt, math.abs, math.pi
local atan2 = math.atan2 or math.atan
local min, max = math.min, math.max
local TWO_PI = 2 * pi

-- upper bound on the number of candidate pre-images collected while inverting a chain
local MAX_CANDIDATES = 4096

--------------------------------------------------------------------------------
-- small helpers
--------------------------------------------------------------------------------

-- Smoothstep: 0 for t <= 0, 1 for t >= 1, an S-shaped curve in between.
local function smooth(t)
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end

-- signedDist is a signed distance to the seam, negative on the side that gets remapped.
-- Returns the weight of the remapped branch: 1 beyond -bandWidth, 0 beyond +bandWidth, 0.5 on the seam.
local function seamWeight(signedDist, bandWidth)
	if bandWidth <= 0 then
		return signedDist < 0 and 1 or 0
	end
	return smooth((bandWidth - signedDist) / (2 * bandWidth))
end

-- Wavy offset along a line: a sum of three sine/cosine harmonics of the position t along the line.
-- waveParams = { amp, freq, phase }. Returns the offset perpendicular to the line.
local function wave(t, waveParams)
	local freq = waveParams.freq
	local phase = waveParams.phase
	return waveParams.amp
		* (
			0.5 * sin(t * freq + phase)
			+ 0.25 * sin(t * freq * 3 + phase * 0.5)
			+ 0.25 * cos(t * freq * 5 + phase * 1.5)
		)
end

-- Appends the point (x, z) to the candidate list.
local function push(candidates, x, z)
	candidates[#candidates + 1] = { x, z }
end

-- Ping-pong reflection of u into [0, size]: used for tile cells, radial rings and for positions outside the map.
local function mirrorAxis(u, size)
	local folded = u % (2 * size)
	if folded > size then
		return 2 * size - folded
	end
	return folded
end

-- Step builders by descriptor kind. Each builder takes (desc, ctx) and returns an "item" with:
--   item.f(x, z)               -> tapAX, tapAZ, weightA, tapBX, tapBZ  (gather step, see header)
--   item.cand(x, z, candidates) appends positions that this step maps onto (x, z) (used by Transform:preimages)
--   item.multi(x, z)           optional: list of { x, z, weight } taps for steps with more than two taps
local prims = {}

--------------------------------------------------------------------------------
-- reflect / rotate (fold along a line)
--------------------------------------------------------------------------------

-- Exact unit vector (cos, sin) for the axis-aligned angles so axial symmetry has no rounding error.
local function unitVector(angle)
	if angle == 0 then
		return 1, 0
	elseif angle == pi / 2 then
		return 0, 1
	elseif angle == pi then
		return -1, 0
	end
	return cos(angle), sin(angle)
end

-- Builds a "reflect" or "rotate" step: everything on the remapped side of a line is mirrored across it
-- (or rotated about a centre), optionally cross-faded over a band and with a wavy line.
-- d: descriptor (px, pz point on the line; angle of the line; source side; band; wave; rot, cx, cz for rotate)
-- ctx: build context; ctx.always makes the fold apply everywhere (inside select branches)
local function buildFold(d, ctx)
	local lineX = d.px
	local lineZ = d.pz
	local tangentX, tangentZ = unitVector(d.angle)
	local normalX = -tangentZ
	local normalZ = tangentX
	local sign = d.source or 1
	local bandWidth = d.band or 0
	local waveParams = d.wave
	local isRotate = d.kind == "rotate"
	-- inside a select branch the fold applies everywhere: the mask already decided where the branch is used,
	-- and a second side test would make a fold on the "wrong" side do nothing at all
	local always = ctx and ctx.always
	local centerX, centerZ, cosRot, sinRot
	if isRotate then
		centerX = d.cx or lineX
		centerZ = d.cz or lineZ
		local rotAngle = d.rot or pi
		cosRot = cos(rotAngle)
		sinRot = sin(rotAngle)
	end

	local item = {}

	-- Gather step: returns the folded position and its weight (0 = untouched, 1 = fully folded).
	item.f = function(x, z)
		local relX = x - lineX
		local relZ = z - lineZ
		local signedDist = relX * normalX + relZ * normalZ
		if waveParams then
			signedDist = signedDist - wave(relX * tangentX + relZ * tangentZ, waveParams)
		end
		local weight = always and 1 or seamWeight(signedDist * sign, bandWidth)
		if weight <= 0 then
			return x, z, 0
		end
		if isRotate then
			local offX = x - centerX
			local offZ = z - centerZ
			return centerX + offX * cosRot - offZ * sinRot, centerZ + offX * sinRot + offZ * cosRot, weight
		end
		return x - 2 * signedDist * normalX, z - 2 * signedDist * normalZ, weight
	end

	-- Candidate pre-image of (x, z): the reflection (or inverse rotation) of the point.
	item.cand = function(x, z, candidates)
		if isRotate then
			local offX = x - centerX
			local offZ = z - centerZ
			push(candidates, centerX + offX * cosRot + offZ * sinRot, centerZ - offX * sinRot + offZ * cosRot)
		else
			local relX = x - lineX
			local relZ = z - lineZ
			local signedDist = relX * normalX + relZ * normalZ
			if waveParams then
				signedDist = signedDist - wave(relX * tangentX + relZ * tangentZ, waveParams)
			end
			push(candidates, x - 2 * signedDist * normalX, z - 2 * signedDist * normalZ)
		end
	end

	return item
end

prims.reflect = buildFold
prims.rotate = buildFold

--------------------------------------------------------------------------------
-- nfold (kaleidoscope)
--------------------------------------------------------------------------------

-- Extra parameters (all optional, defaults give the plain kaleidoscope):
--   twist       radians of extra rotation per elmo of radius, applied before folding (swirl)
--   ring        radial period in elmos: the radius is folded too (concentric echoes); ringMirror = ping-pong
--   wedge       0..1: the source wedge is `wedge` times the sector width, stretched to fill the sector
-- d: descriptor (cx, cz centre; n sectors; phase; mirror; band; twist; ring; ringMirror; wedge)
prims.nfold = function(d, ctx)
	local centerX = d.cx
	local centerZ = d.cz
	local sectorCount = d.n
	local sectorAngle = TWO_PI / sectorCount
	local phase = d.phase or 0
	local mirror = d.mirror and true or false
	local bandWidth = d.band or 0
	local twist = d.twist or 0
	local ring = d.ring or 0
	local ringMirror = d.ringMirror and true or false
	local wedge = d.wedge or 1
	local far = 3 * max(ctx.W, ctx.H)

	-- Folds the radius into one ring period (identity when rings are off).
	local function ringFold(radius)
		if ring <= 0 then
			return radius
		elseif ringMirror then
			return mirrorAxis(radius, ring)
		end
		return radius % ring
	end

	-- Position inside sector `sectorIndex` that corresponds to angle `theta` (measured from phase) and radius.
	local function mapSector(sectorIndex, theta, radius)
		local angleInSector = theta - sectorIndex * sectorAngle
		if mirror and (sectorIndex % sectorCount) % 2 == 1 then
			angleInSector = sectorAngle - angleInSector
		end
		local srcAngle = phase + wedge * angleInSector
		local srcRadius = ringFold(radius)
		return centerX + srcRadius * cos(srcAngle), centerZ + srcRadius * sin(srcAngle)
	end

	local item = {}

	-- Gather step: finds the sector of (x, z) and maps into it; near a sector border also taps the neighbour sector.
	item.f = function(x, z)
		local deltaX = x - centerX
		local deltaZ = z - centerZ
		local radius = sqrt(deltaX * deltaX + deltaZ * deltaZ)
		if radius < 1e-6 then
			return x, z, 0
		end
		local theta = (atan2(deltaZ, deltaX) - phase + twist * radius) % TWO_PI
		local sectorIndex = floor(theta / sectorAngle)
		local sectorFraction = theta / sectorAngle - sectorIndex
		local tapAX, tapAZ = mapSector(sectorIndex, theta, radius)
		if bandWidth <= 0 then
			return tapAX, tapAZ, 1
		end
		-- arc length to the lower and upper sector borders
		local distToLower = sectorFraction * sectorAngle * radius
		local distToUpper = (1 - sectorFraction) * sectorAngle * radius
		local otherIndex
		local borderDist
		if distToLower < bandWidth then
			otherIndex = sectorIndex - 1
			borderDist = distToLower
		elseif distToUpper < bandWidth then
			otherIndex = sectorIndex + 1
			borderDist = distToUpper
		else
			return tapAX, tapAZ, 1
		end
		local otherWeight = smooth((bandWidth - borderDist) / (2 * bandWidth))
		local tapBX, tapBZ = mapSector(otherIndex, theta, radius)
		return tapAX, tapAZ, 1 - otherWeight, tapBX, tapBZ
	end

	-- Candidate pre-images of (x, z): one per sector (and per ring repeat when rings are on).
	item.cand = function(x, z, candidates)
		local deltaX = x - centerX
		local deltaZ = z - centerZ
		local queryRadius = sqrt(deltaX * deltaX + deltaZ * deltaZ)
		-- output angle inside the sector: phase + wedge * angleInSector
		local angleFromPhase = (atan2(deltaZ, deltaX) - phase) % TWO_PI
		local queryAngleInSector = angleFromPhase / wedge
		if queryAngleInSector > sectorAngle + 1e-9 then
			return -- the narrow wedge never produces this angle
		end
		local radii = { queryRadius }
		if ring > 0 then
			radii = {}
			if queryRadius <= ring + 1e-9 then
				for i = 0, min(200, floor(far / ring)) do
					if ringMirror and i % 2 == 1 then
						radii[#radii + 1] = i * ring + (ring - queryRadius)
					else
						radii[#radii + 1] = i * ring + queryRadius
					end
				end
			end
		end
		for _, radius in ipairs(radii) do
			for sectorIndex = 0, sectorCount - 1 do
				local angleInSector = queryAngleInSector
				if mirror and sectorIndex % 2 == 1 then
					angleInSector = sectorAngle - queryAngleInSector
				end
				-- angle in twisted space, then undo the twist (it depends on the pre-image radius)
				local angle = phase + sectorIndex * sectorAngle + angleInSector - twist * radius
				push(candidates, centerX + radius * cos(angle), centerZ + radius * sin(angle))
			end
		end
	end

	return item
end

--------------------------------------------------------------------------------
-- tile
--------------------------------------------------------------------------------

-- Cells of cellWidth x cellHeight in a frame rotated by `angle` with origin (originX, originZ).
-- Frame coordinates are called (u, v). Cell (i, j) shows source cell (srcCellI, srcCellJ) of the same grid,
-- optionally flipped / turned, so a plain tile is "every cell shows cell (0, 0)".
--   mode      "repeat" (copies) or "mirror" (alternating flips: continuous seams)
--   brick     0..0.5: every second row is shifted by brick * w
--   shuffle   each cell shows a hash-picked cell of the map-sized grid instead of cell (0, 0)
--   flip      each cell is randomly flipped in u and v, and (square cells) turned by 90 degrees
--   seed      0..1020, varies the hash
--   band      cross-fade width at cell borders (neighbouring cells are sampled with the same position)
-- The cell hash only uses exact small-integer arithmetic so the GLSL port gives the same answers.
-- d: descriptor (ox, oz, angle, w, h, mode, brick, shuffle, flip, seed, band)
prims.tile = function(d, ctx)
	local originX = d.ox
	local originZ = d.oz
	local cosAngle = cos(d.angle or 0)
	local sinAngle = sin(d.angle or 0)
	local cellWidth = d.w
	local cellHeight = d.h or d.w
	local mirror = d.mode == "mirror"
	local brick = d.brick or 0
	local shuffle = d.shuffle and true or false
	local flip = d.flip and true or false
	local seed = d.seed or 0
	local bandWidth = d.band or 0
	local square = abs(cellWidth - cellHeight) < 1e-6
	-- number of cells needed to cover the map (at least 2 so shuffling has something to choose from)
	local cellsX = max(2, ceil(ctx.W / cellWidth))
	local cellsZ = max(2, ceil(ctx.H / cellHeight))

	-- World position -> frame coordinates (u, v).
	local function toLocal(x, z)
		local relX = x - originX
		local relZ = z - originZ
		return relX * cosAngle + relZ * sinAngle, -relX * sinAngle + relZ * cosAngle
	end

	-- Frame coordinates (u, v) -> world position.
	local function toWorld(u, v)
		return originX + u * cosAngle - v * sinAngle, originZ + u * sinAngle + v * cosAngle
	end

	-- Pseudo-random value in [0, 1) for cell (i, j); `salt` gives independent values per purpose.
	local function cellHash(i, j, salt)
		local hash = (i * 37 + j * 101 + salt * 211 + seed * 53 + 17) % 1021
		hash = (hash * hash + 3 * hash + 5) % 1021
		hash = (hash * hash + 7 * hash + 13 + i * 3) % 1021
		hash = (hash * hash + 11 * hash + 29 + j * 5) % 1021
		return hash / 1021
	end

	-- Horizontal offset of row j (brick pattern).
	local function shift(j)
		return brick * cellWidth * (j % 2)
	end

	-- Flips, turn and source cell of cell (i, j).
	local function cellInfo(i, j)
		local flipU = (mirror and i % 2 == 1) and -1 or 1
		local flipV = (mirror and j % 2 == 1) and -1 or 1
		local swap = false
		if flip then
			if cellHash(i, j, 1) < 0.5 then
				flipU = -flipU
			end
			if cellHash(i, j, 2) < 0.5 then
				flipV = -flipV
			end
			swap = square and cellHash(i, j, 3) < 0.5
		end
		local srcCellI = 0
		local srcCellJ = 0
		if shuffle then
			srcCellI = floor(cellHash(i, j, 4) * cellsX)
			srcCellJ = floor(cellHash(i, j, 5) * cellsZ)
		end
		return flipU, flipV, swap, srcCellI, srcCellJ
	end

	-- Position (frame coordinates) that cell (i, j) shows at frame position (u, v).
	local function sourceFrame(u, v, i, j)
		local flipU, flipV, swap, srcCellI, srcCellJ = cellInfo(i, j)
		-- position inside the cell, then flipped / turned
		local cellU = u - shift(j) - i * cellWidth
		local cellV = v - j * cellHeight
		if swap then
			cellU, cellV = cellV, cellU
		end
		if flipU < 0 then
			cellU = cellWidth - cellU
		end
		if flipV < 0 then
			cellV = cellHeight - cellV
		end
		return srcCellI * cellWidth + cellU, srcCellJ * cellHeight + cellV
	end

	-- Intermediate positions of a chain can lie well outside the map (rotations, zooms, other tiles):
	-- bound the frame region that has to be searched for candidate cells.
	local pad = max(ctx.W, ctx.H)
	local minU = math.huge
	local maxU = -math.huge
	local minV = math.huge
	local maxV = -math.huge
	local paddedCorners = {
		{ -pad, -pad },
		{ ctx.W + pad, -pad },
		{ -pad, ctx.H + pad },
		{ ctx.W + pad, ctx.H + pad },
	}
	for _, corner in ipairs(paddedCorners) do
		local u, v = toLocal(corner[1], corner[2])
		minU = min(minU, u)
		maxU = max(maxU, u)
		minV = min(minV, v)
		maxV = max(maxV, v)
	end

	local item = {}

	-- Gather step: find the cell containing (x, z) and return the position that cell shows there.
	item.f = function(x, z)
		local u, v = toLocal(x, z)
		local j = floor(v / cellHeight)
		local i = floor((u - shift(j)) / cellWidth)
		local srcU, srcV = sourceFrame(u, v, i, j)
		local srcX, srcZ = toWorld(srcU, srcV)
		return srcX, srcZ, 1
	end

	if bandWidth > 0 then
		-- Distance from `coord` (position inside a cell of length `size`) to the nearest border,
		-- and the direction (-1 / +1) of the neighbour cell across that border.
		local function nearest(coord, size)
			if coord < size - coord then
				return coord, -1
			end
			return size - coord, 1
		end

		-- Blend weight of the neighbour cell at the given distance from the border (0 outside the band).
		local function neighbourWeight(borderDist)
			if borderDist >= bandWidth then
				return 0
			end
			return smooth((bandWidth - borderDist) / (2 * bandWidth))
		end

		-- Up to four taps: own cell and the nearest neighbours across the u and v borders.
		-- Returns a list of { x, z, weight }.
		item.multi = function(x, z)
			local u, v = toLocal(x, z)
			local j = floor(v / cellHeight)
			local i = floor((u - shift(j)) / cellWidth)
			local distU, dirU = nearest(u - shift(j) - i * cellWidth, cellWidth)
			local distV, dirV = nearest(v - j * cellHeight, cellHeight)
			local weightU = neighbourWeight(distU)
			local weightV = neighbourWeight(distV)
			local tapList = {}
			local function addTap(cellI, cellJ, tapWeight)
				if tapWeight > 1e-9 then
					local srcU, srcV = sourceFrame(u, v, cellI, cellJ)
					local tapX, tapZ = toWorld(srcU, srcV)
					tapList[#tapList + 1] = { tapX, tapZ, tapWeight }
				end
			end
			addTap(i, j, (1 - weightU) * (1 - weightV))
			addTap(i + dirU, j, weightU * (1 - weightV))
			if weightV > 0 then
				-- the neighbouring row may be brick-shifted, so its column is recomputed
				local neighbourJ = j + dirV
				local neighbourI = floor((u - shift(neighbourJ)) / cellWidth)
				local distU2, dirU2 = nearest(u - shift(neighbourJ) - neighbourI * cellWidth, cellWidth)
				local weightU2 = neighbourWeight(distU2)
				addTap(neighbourI, neighbourJ, weightV * (1 - weightU2))
				addTap(neighbourI + dirU2, neighbourJ, weightV * weightU2)
			end
			return tapList
		end
	end

	-- Every cell whose source cell contains the query point shows it somewhere: invert that cell's flips and turn.
	item.cand = function(x, z, candidates)
		local queryU, queryV = toLocal(x, z)
		for j = floor(minV / cellHeight) - 1, ceil(maxV / cellHeight) + 1 do
			local rowShift = shift(j)
			for i = floor((minU - rowShift) / cellWidth) - 1, ceil((maxU - rowShift) / cellWidth) + 1 do
				local flipU, flipV, swap, srcCellI, srcCellJ = cellInfo(i, j)
				local cellU = queryU - srcCellI * cellWidth
				local cellV = queryV - srcCellJ * cellHeight
				if cellU >= -1e-6 and cellU <= cellWidth + 1e-6 and cellV >= -1e-6 and cellV <= cellHeight + 1e-6 then
					if flipU < 0 then
						cellU = cellWidth - cellU
					end
					if flipV < 0 then
						cellV = cellHeight - cellV
					end
					if swap then
						cellU, cellV = cellV, cellU
					end
					local candX, candZ = toWorld(i * cellWidth + rowShift + cellU, j * cellHeight + cellV)
					push(candidates, candX, candZ)
					if #candidates >= MAX_CANDIDATES then
						return
					end
				end
			end
		end
	end

	return item
end

--------------------------------------------------------------------------------
-- wallpaper: reflect the plane into the fundamental triangle of a mirror-line wallpaper group
--------------------------------------------------------------------------------

local SQ3 = sqrt(3)
-- Mirror lines of the fundamental triangle in units of `size`: { point u, point v, inward normal u, inward normal v }
local WALL_LINES = {
	p4m = { { 0, 0, 0, 1 }, { 1, 0, -1, 0 }, { 0, 0, 0.7071067811865476, -0.7071067811865476 } }, -- (0,0) (1,0) (1,1)
	p3m1 = { { 0, 0, 0, 1 }, { 0, 0, SQ3 / 2, -0.5 }, { 1, 0, -SQ3 / 2, -0.5 } }, -- equilateral (0,0) (1,0) (1/2,s3/2)
	p6m = { { 0, 0, 0, 1 }, { 0, 0, 0.5, -SQ3 / 2 }, { 1, 0, -SQ3 / 2, -0.5 } }, -- 30-60-90 (0,0) (1,0) (3/4,sqrt3/4)
}
-- Centroid of each fundamental triangle in units of `size` (used to identify triangles while enumerating images)
local WALL_CENTROID = { p4m = { 2 / 3, 1 / 3 }, p3m1 = { 0.5, SQ3 / 6 }, p6m = { 1.75 / 3, SQ3 / 12 } }

-- group: "p4m" (square lattice, 45-45-90 triangle), "p3m1" (equilateral triangles), "p6m" (hexagonal, 30-60-90)
-- size: triangle scale in elmos, (ox, oz) its corner, angle its rotation
-- A point is reflected across any triangle edge it lies behind until it sits inside the triangle at (ox, oz):
-- the result is continuous across every seam and the whole map becomes copies of that one triangle of the map.
-- Triangle coordinates are called (u, v): world coordinates relative to the corner, rotated by `angle`,
-- divided by size.
prims.wallpaper = function(d, ctx)
	local lines = WALL_LINES[d.group]
	if not lines then
		error("mapgen transform: unknown wallpaper group '" .. tostring(d.group) .. "'")
	end
	local size = d.size
	local originX = d.ox
	local originZ = d.oz
	local cosAngle = cos(d.angle or 0)
	local sinAngle = sin(d.angle or 0)
	local centroid = WALL_CENTROID[d.group]
	local mapWidth = ctx.W
	local mapHeight = ctx.H
	local pad = max(mapWidth, mapHeight)

	-- World position -> triangle coordinates (u, v).
	local function toLocal(x, z)
		local relX = x - originX
		local relZ = z - originZ
		return (relX * cosAngle + relZ * sinAngle) / size, (-relX * sinAngle + relZ * cosAngle) / size
	end

	-- Triangle coordinates (u, v) -> world position.
	local function toWorld(u, v)
		u = u * size
		v = v * size
		return originX + u * cosAngle - v * sinAngle, originZ + u * sinAngle + v * cosAngle
	end

	-- Reflects (u, v) across every mirror line it lies behind, repeatedly, until it is inside the triangle.
	-- Same pass limit and tolerance as the shader, so both sides fold identically.
	local function fold(u, v)
		for _ = 1, 128 do
			local moved = false
			for k = 1, 3 do
				local line = lines[k]
				local signedDist = (u - line[1]) * line[3] + (v - line[2]) * line[4]
				if signedDist < -1e-6 then
					u = u - 2 * signedDist * line[3]
					v = v - 2 * signedDist * line[4]
					moved = true
				end
			end
			if not moved then
				break
			end
		end
		return u, v
	end

	local item = {}

	-- Gather step: fold the position into the fundamental triangle.
	item.f = function(x, z)
		local u, v = toLocal(x, z)
		u, v = fold(u, v)
		local srcX, srcZ = toWorld(u, v)
		return srcX, srcZ, 1
	end

	-- Every image of the query point under the group, found by walking from triangle to triangle through the
	-- mirrors. Each triangle is described by the affine map { m11, m12, m21, m22, tx, tz } taking the fundamental
	-- triangle to it: (u, v) -> (m11 * u + m12 * v + tx, m21 * u + m22 * v + tz).
	item.cand = function(x, z, candidates)
		local queryU, queryV = toLocal(x, z)
		for k = 1, 3 do
			local line = lines[k]
			if (queryU - line[1]) * line[3] + (queryV - line[2]) * line[4] < -1e-6 then
				return -- the fold never produces points outside the fundamental triangle
			end
		end

		-- Returns a string key for the triangle (its rounded centroid), and the centroid itself.
		local function triangleKey(affine)
			local centroidX = affine.m11 * centroid[1] + affine.m12 * centroid[2] + affine.tx
			local centroidZ = affine.m21 * centroid[1] + affine.m22 * centroid[2] + affine.tz
			return floor(centroidX * 1000 + 0.5) .. "," .. floor(centroidZ * 1000 + 0.5), centroidX, centroidZ
		end

		local queue = { { m11 = 1, m12 = 0, m21 = 0, m22 = 1, tx = 0, tz = 0 } }
		local seen = {}
		seen[(triangleKey(queue[1]))] = true
		local head = 1
		-- triangles whose centroid is far outside the (padded) map cannot hold candidates and are not expanded
		local minX = -pad - size
		local maxX = mapWidth + pad + size
		local minZ = -pad - size
		local maxZ = mapHeight + pad + size
		while head <= #queue and #candidates < MAX_CANDIDATES do
			local affine = queue[head]
			head = head + 1
			local imageU = affine.m11 * queryU + affine.m12 * queryV + affine.tx
			local imageV = affine.m21 * queryU + affine.m22 * queryV + affine.tz
			local candX, candZ = toWorld(imageU, imageV)
			push(candidates, candX, candZ)
			for k = 1, 3 do
				local line = lines[k]
				local normalU = line[3]
				local normalV = line[4]
				-- neighbour = affine o reflect(line k): linear part R = I - 2 n n^T, translation 2 (n.P) n
				local refl11 = 1 - 2 * normalU * normalU
				local refl12 = -2 * normalU * normalV
				local refl22 = 1 - 2 * normalV * normalV
				local lineOffset = 2 * (normalU * line[1] + normalV * line[2])
				local neighbour = {
					m11 = affine.m11 * refl11 + affine.m12 * refl12,
					m12 = affine.m11 * refl12 + affine.m12 * refl22,
					m21 = affine.m21 * refl11 + affine.m22 * refl12,
					m22 = affine.m21 * refl12 + affine.m22 * refl22,
					tx = affine.m11 * lineOffset * normalU + affine.m12 * lineOffset * normalV + affine.tx,
					tz = affine.m21 * lineOffset * normalU + affine.m22 * lineOffset * normalV + affine.tz,
				}
				local neighbourKey, centroidX, centroidZ = triangleKey(neighbour)
				if not seen[neighbourKey] then
					seen[neighbourKey] = true
					local worldX, worldZ = toWorld(centroidX, centroidZ)
					if worldX >= minX and worldX <= maxX and worldZ >= minZ and worldZ <= maxZ then
						queue[#queue + 1] = neighbour
					end
				end
			end
		end
	end

	return item
end

--------------------------------------------------------------------------------
-- warp
--------------------------------------------------------------------------------

-- Smooth sine domain warp: x is displaced by a wave of z and z by a wave of x.
-- d: descriptor (amp, freq, p1 and p2 = phases of the x and z displacement)
prims.warp = function(d)
	local waveX = { amp = d.amp, freq = d.freq, phase = d.p1 }
	local waveZ = { amp = d.amp, freq = d.freq, phase = d.p2 }

	local item = {}

	item.f = function(x, z)
		return x + wave(z, waveX), z + wave(x, waveZ), 1
	end

	-- the generator keeps amp * freq small enough for this to be a contraction
	-- (fixed-point iteration solving x' + wave(z') = x, z' + wave(x') = z)
	item.cand = function(x, z, candidates)
		local candX = x
		local candZ = z
		for _ = 1, 8 do
			candX, candZ = x - wave(candZ, waveX), z - wave(candX, waveZ)
		end
		push(candidates, candX, candZ)
	end

	return item
end

--------------------------------------------------------------------------------
-- zoom
--------------------------------------------------------------------------------

-- Similarity transform: the neighbourhood of (cx, cz) is shown scaled by `scale`, rotated by `angle`,
-- and moved to (tx, tz).
-- d: descriptor (cx, cz, tx, tz, scale, angle)
prims.zoom = function(d)
	local centerX = d.cx
	local centerZ = d.cz
	local targetX = d.tx
	local targetZ = d.tz
	local scale = d.scale
	local cosAngle = cos(d.angle or 0)
	local sinAngle = sin(d.angle or 0)

	local item = {}

	item.f = function(x, z)
		local offX = (x - centerX) / scale
		local offZ = (z - centerZ) / scale
		return targetX + offX * cosAngle - offZ * sinAngle, targetZ + offX * sinAngle + offZ * cosAngle, 1
	end

	item.cand = function(x, z, candidates)
		local offX = x - targetX
		local offZ = z - targetZ
		push(
			candidates,
			centerX + scale * (offX * cosAngle + offZ * sinAngle),
			centerZ + scale * (-offX * sinAngle + offZ * cosAngle)
		)
	end

	return item
end

--------------------------------------------------------------------------------
-- select masks: return weight of the "b" branch
--------------------------------------------------------------------------------

-- Builds a mask function (x, z) -> weight of branch b (0 = branch a only, 1 = branch b only).
-- mask: descriptor { kind = "disc", cx, cz, r, band } or halfplane { angle, px, pz, sign, band }
local function buildMask(mask)
	local bandWidth = mask.band or 0
	if mask.kind == "disc" then
		local centerX = mask.cx
		local centerZ = mask.cz
		local radius = mask.r
		return function(x, z)
			local deltaX = x - centerX
			local deltaZ = z - centerZ
			return seamWeight(sqrt(deltaX * deltaX + deltaZ * deltaZ) - radius, bandWidth)
		end
	end
	-- halfplane
	local tangentX = cos(mask.angle)
	local tangentZ = sin(mask.angle)
	local normalX = -tangentZ
	local normalZ = tangentX
	local lineX = mask.px
	local lineZ = mask.pz
	local sign = mask.sign or 1
	return function(x, z)
		return seamWeight(((x - lineX) * normalX + (z - lineZ) * normalZ) * sign, bandWidth)
	end
end

--------------------------------------------------------------------------------
-- chain building
--------------------------------------------------------------------------------

local buildItems

-- Builds one chain item from a descriptor. A "select" item holds a mask and two sub-chains (a and b);
-- every other kind is built by its entry in `prims`.
local function buildItem(desc, ctx)
	local item
	if desc.kind == "select" then
		-- folds inside the branches apply everywhere (see buildFold); the mask alone decides where a branch is used
		local inner = { W = ctx.W, H = ctx.H, always = true }
		item = {
			select = true,
			mask = buildMask(desc.mask),
			a = buildItems(desc.a or {}, inner),
			b = buildItems(desc.b or {}, inner),
		}
	else
		local builder = prims[desc.kind]
		if not builder then
			error("mapgen transform: unknown kind '" .. tostring(desc.kind) .. "'")
		end
		item = builder(desc, ctx)
		item.always = ctx.always
	end
	item.desc = desc
	return item
end

-- Builds the list of items for a list of descriptors (same order).
buildItems = function(descriptors, ctx)
	local items = {}
	for i = 1, #descriptors do
		items[i] = buildItem(descriptors[i], ctx)
	end
	return items
end

-- Wires `next` pointers so evaluation is a loop; a select's branches continue into the select's own `next`.
-- Returns the first item of the list (or `tail` when the list is empty).
local function link(items, tail)
	local head = tail
	for i = #items, 1, -1 do
		local item = items[i]
		item.next = head
		if item.select then
			item.ahead = link(item.a, head)
			item.bhead = link(item.b, head)
		end
		head = item
	end
	return head
end

-- Blended mapping from `node` to the end of the chain. Walks the chain from the position (x, z) carrying a
-- weight; wherever a step offers two taps, the second one is followed recursively with its share of the weight.
-- Every finished path appends one tap (srcX, srcZ, weight) to `taps` (scratch buffer with n, x, z, w, W, H).
-- Positions outside the map are reflected back inside (mirror repeat, see mirrorAxis) instead of clamped:
-- clamping smears the border row across the whole overshoot, which shows up as stretched streaks.
local function walk(node, x, z, weight, taps)
	while node do
		if node.select then
			local maskWeight = node.mask(x, z)
			if maskWeight <= 0 then
				node = node.ahead
			elseif maskWeight >= 1 then
				node = node.bhead
			else
				walk(node.bhead, x, z, weight * maskWeight, taps)
				weight = weight * (1 - maskWeight)
				node = node.ahead
			end
		elseif node.multi then
			-- a step with several weighted taps (tile seam blending)
			local tapList = node.multi(x, z)
			for k = 2, #tapList do
				walk(node.next, tapList[k][1], tapList[k][2], weight * tapList[k][3], taps)
			end
			weight = weight * tapList[1][3]
			x = tapList[1][1]
			z = tapList[1][2]
			node = node.next
		else
			local tapAX, tapAZ, weightA, tapBX, tapBZ = node.f(x, z)
			if tapBX == nil then
				tapBX = x
				tapBZ = z
			end
			if weightA >= 1 then
				x = tapAX
				z = tapAZ
			elseif weightA <= 0 then
				x = tapBX
				z = tapBZ
			else
				walk(node.next, tapAX, tapAZ, weight * weightA, taps)
				weight = weight * (1 - weightA)
				x = tapBX
				z = tapBZ
			end
			node = node.next
		end
	end
	local tapCount = taps.n + 1
	taps.n = tapCount
	taps.x[tapCount] = mirrorAxis(x, taps.W)
	taps.z[tapCount] = mirrorAxis(z, taps.H)
	taps.w[tapCount] = weight
end

-- Inverts one chain item: given a list of points, returns those points plus every candidate position that the
-- item could map onto them (a select item recurses into both branches, last step first).
local function preStep(item, points)
	local results = {}
	for i = 1, #points do
		local point = points[i]
		if item.select then
			local pointsA = { point }
			local pointsB = { point }
			for j = #item.a, 1, -1 do
				pointsA = preStep(item.a[j], pointsA)
			end
			for j = #item.b, 1, -1 do
				pointsB = preStep(item.b[j], pointsB)
			end
			for j = 1, #pointsA do
				results[#results + 1] = pointsA[j]
			end
			for j = 1, #pointsB do
				results[#results + 1] = pointsB[j]
			end
		else
			results[#results + 1] = point
			if item.cand then
				item.cand(point[1], point[2], results)
			end
		end
		if #results >= MAX_CANDIDATES then
			break
		end
	end
	return results
end

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

local Transform = {}
Transform.__index = Transform

-- Creates a transform from a list of step descriptors for a map of mapWidth x mapHeight elmos.
function Transform.new(descriptors, mapWidth, mapHeight)
	local ctx = { W = mapWidth, H = mapHeight }
	local items = buildItems(descriptors, ctx)
	local self = setmetatable({
		descs = descriptors,
		W = mapWidth,
		H = mapHeight,
		items = items,
		head = link(items, nil),
		scratch = { n = 0, x = {}, z = {}, w = {}, W = mapWidth, H = mapHeight },
	}, Transform)
	return self
end

-- Hard (dominant branch) mapping from `node` to the end of the chain, reflected into the map.
-- Returns srcX, srcZ for the output position (x, z).
local function mapNode(node, x, z, mapWidth, mapHeight)
	while node do
		if node.select then
			if node.mask(x, z) >= 0.5 then
				node = node.bhead
			else
				node = node.ahead
			end
		else
			local tapAX, tapAZ, weightA, tapBX, tapBZ = node.f(x, z)
			if tapBX == nil then
				tapBX = x
				tapBZ = z
			end
			if weightA >= 0.5 then
				x = tapAX
				z = tapAZ
			else
				x = tapBX
				z = tapBZ
			end
			node = node.next
		end
	end
	return mirrorAxis(x, mapWidth), mirrorAxis(z, mapHeight)
end

-- Hard (dominant branch) mapping: use for discrete data such as features, type maps, start boxes.
-- Takes an output position, returns the source position (srcX, srcZ) it reads from.
function Transform:map(outX, outZ)
	return mapNode(self.head, outX, outZ, self.W, self.H)
end

-- Blended mapping of an output position: returns count, xs, zs, ws. xs[i], zs[i] are source positions and ws[i]
-- their weights. Arrays are reused between calls; weights sum to 1.
function Transform:taps(outX, outZ)
	local taps = self.scratch
	taps.n = 0
	walk(self.head, outX, outZ, 1, taps)
	return taps.n, taps.x, taps.z, taps.w
end

-- All positions p inside the map with map(p) ~= (srcX, srcZ): where something at (srcX, srcZ) must be copied to.
-- tolerance (elmos, default 2) is how close map(p) has to land to the source position.
-- Returns a list of { outX, outZ } points.
function Transform:preimages(srcX, srcZ, tolerance)
	tolerance = tolerance or 2
	-- the final reflection into the map has up to 9 candidate pre-images of (srcX, srcZ) just outside it
	local mapWidth = self.W
	local mapHeight = self.H
	local points = {}
	for _, candX in ipairs({ srcX, -srcX, 2 * mapWidth - srcX }) do
		for _, candZ in ipairs({ srcZ, -srcZ, 2 * mapHeight - srcZ }) do
			points[#points + 1] = { candX, candZ }
		end
	end
	for i = #self.items, 1, -1 do
		local item = self.items[i]
		points = preStep(item, points)
		-- keep only candidates that really land on (srcX, srcZ) through steps i..n, so the set never blows up
		local kept = {}
		local seen = {}
		for j = 1, #points do
			local candX = points[j][1]
			local candZ = points[j][2]
			local mappedX, mappedZ = mapNode(item, candX, candZ, mapWidth, mapHeight)
			if abs(mappedX - srcX) <= tolerance and abs(mappedZ - srcZ) <= tolerance then
				local key = floor(candX / 2) .. ":" .. floor(candZ / 2)
				if not seen[key] then
					seen[key] = true
					kept[#kept + 1] = points[j]
				end
			end
		end
		points = kept
	end
	local result = {}
	for i = 1, #points do
		local outX = points[i][1]
		local outZ = points[i][2]
		if outX >= 0 and outX <= self.W and outZ >= 0 and outZ <= self.H then
			result[#result + 1] = points[i]
		end
	end
	return result
end

-- Is the neighbourhood of the output position (outX, outZ) shown as a faithful copy of one place of the source map?
-- Samples a disc of the given radius: every sample must be a single hard tap (no cross-fade band), and the mapping
-- must be one affine map over the whole disc (so no seam, fold line, tile edge or map-edge fold cuts through it).
-- Used to keep metal spots / geo vents whole.
-- tolerance (elmos, default 3) is the allowed deviation of a sample from the affine fit.
function Transform:isClean(outX, outZ, radius, tolerance)
	tolerance = tolerance or 3
	-- sample offsets are cached per radius
	local patterns = self.cleanPatterns
	if not patterns then
		patterns = {}
		self.cleanPatterns = patterns
	end
	local offsets = patterns[radius]
	if not offsets then
		-- the first three samples span the affine map: centre, +x direction, +z direction
		offsets = { { 0, 0 }, { radius, 0 }, { 0, radius } }
		for k = 0, 7 do
			local angle = k * pi / 4 + 0.2
			offsets[#offsets + 1] = { radius * cos(angle), radius * sin(angle) }
		end
		for k = 0, 5 do
			local angle = k * pi / 3 + 0.6
			offsets[#offsets + 1] = { 0.5 * radius * cos(angle), 0.5 * radius * sin(angle) }
		end
		patterns[radius] = offsets
	end
	local srcXs = {}
	local srcZs = {}
	for i = 1, #offsets do
		local tapCount, tapXs, tapZs = self:taps(outX + offsets[i][1], outZ + offsets[i][2])
		if tapCount ~= 1 then
			return false
		end
		srcXs[i] = tapXs[1]
		srcZs[i] = tapZs[1]
	end
	-- linear part of the map fitted through the first three samples: (outX, outZ) offset -> (srcX, srcZ) offset
	local m11 = (srcXs[2] - srcXs[1]) / radius
	local m21 = (srcZs[2] - srcZs[1]) / radius
	local m12 = (srcXs[3] - srcXs[1]) / radius
	local m22 = (srcZs[3] - srcZs[1]) / radius
	for i = 4, #offsets do
		local offsetX = offsets[i][1]
		local offsetZ = offsets[i][2]
		if
			abs(srcXs[i] - (srcXs[1] + m11 * offsetX + m12 * offsetZ)) > tolerance
			or abs(srcZs[i] - (srcZs[1] + m21 * offsetX + m22 * offsetZ)) > tolerance
		then
			return false
		end
	end
	return true
end

-- Local linearisation of map() around the output position (outX, outZ) using central differences with step epsilon
-- (default 4 elmos). Returns the Jacobian entries dsrcX/doutX, dsrcX/doutZ, dsrcZ/doutX, dsrcZ/doutZ.
function Transform:jacobian(outX, outZ, epsilon)
	epsilon = epsilon or 4
	local plusXSrcX, plusXSrcZ = self:map(outX + epsilon, outZ)
	local minusXSrcX, minusXSrcZ = self:map(outX - epsilon, outZ)
	local plusZSrcX, plusZSrcZ = self:map(outX, outZ + epsilon)
	local minusZSrcX, minusZSrcZ = self:map(outX, outZ - epsilon)
	local invStep = 1 / (2 * epsilon)
	return (plusXSrcX - minusXSrcX) * invStep,
		(plusZSrcX - minusZSrcX) * invStep,
		(plusXSrcZ - minusXSrcZ) * invStep,
		(plusZSrcZ - minusZSrcZ) * invStep
end

-- Flat float program for a shader interpreter (see shader.lua). 20 floats per node, 5 slots of 4:
--   slot 0: kind, next, ahead, bhead   (node references are 1-based, 0 = end of chain)
--   slots 1-4: kind specific parameters
Transform.NODE_STRIDE = 20
Transform.MAX_NODES = 20

local KIND_CODE = { reflect = 1, rotate = 1, nfold = 2, tile = 3, warp = 4, zoom = 5, select = 6, wallpaper = 7 }
local WALL_CODE = { p4m = 1, p3m1 = 2, p6m = 3 }

-- Flattens the node graph into the shader program. Returns the float array (1-based, MAX_NODES * NODE_STRIDE
-- entries) and the number of nodes used. Raises an error for kinds / options the shader cannot run.
function Transform:program()
	-- number the nodes (list order = node reference, 1-based)
	local list = {}
	local index = {}
	local function assign(node)
		if node == nil or index[node] then
			return
		end
		list[#list + 1] = node
		index[node] = #list
		assign(node.next)
		if node.select then
			assign(node.ahead)
			assign(node.bhead)
		end
	end
	assign(self.head)
	if #list > Transform.MAX_NODES then
		error("mapgen transform: too many nodes for the shader program (" .. #list .. ")")
	end

	-- node reference for the program (0 = end of chain)
	local function ref(node)
		return node and index[node] or 0
	end

	local prog = {}
	for i = 1, Transform.MAX_NODES * Transform.NODE_STRIDE do
		prog[i] = 0
	end

	for nodeIndex, node in ipairs(list) do
		local desc = node.desc
		local base = (nodeIndex - 1) * Transform.NODE_STRIDE
		local slot = {}
		for slotIndex = 1, 5 do
			slot[slotIndex] = { 0, 0, 0, 0 }
		end
		if not KIND_CODE[desc.kind] then
			error("mapgen transform: '" .. tostring(desc.kind) .. "' has no shader port yet")
		end
		slot[1] = { KIND_CODE[desc.kind], ref(node.next), ref(node.ahead), ref(node.bhead) }

		if desc.kind == "reflect" or desc.kind == "rotate" then
			local tangentX, tangentZ = unitVector(desc.angle)
			local isRotate = desc.kind == "rotate"
			local rotAngle = desc.rot or pi
			slot[2] = { desc.px, desc.pz, tangentX, tangentZ }
			slot[3] = { desc.source or 1, desc.band or 0, isRotate and 1 or 0, node.always and 1 or 0 }
			if isRotate then
				slot[4] = { desc.cx or desc.px, desc.cz or desc.pz, cos(rotAngle), sin(rotAngle) }
			end
			if desc.wave then
				slot[5] = { desc.wave.amp, desc.wave.freq, desc.wave.phase, 1 }
			end
		elseif desc.kind == "nfold" then
			slot[2] = { desc.cx, desc.cz, desc.n, desc.phase or 0 }
			slot[3] = { desc.mirror and 1 or 0, desc.band or 0, desc.twist or 0, desc.wedge or 1 }
			slot[4] = { desc.ring or 0, desc.ringMirror and 1 or 0, 0, 0 }
		elseif desc.kind == "tile" then
			if desc.brick or desc.shuffle or desc.flip then
				error("mapgen transform: tile brick/shuffle/flip have no shader port")
			end
			local angle = desc.angle or 0
			slot[2] = { desc.ox, desc.oz, cos(angle), sin(angle) }
			slot[3] = { desc.w, desc.h or desc.w, desc.mode == "mirror" and 1 or 0, desc.band or 0 }
		elseif desc.kind == "wallpaper" then
			local angle = desc.angle or 0
			slot[2] = { desc.ox, desc.oz, cos(angle), sin(angle) }
			slot[3] = { desc.size, WALL_CODE[desc.group], 0, 0 }
		elseif desc.kind == "warp" then
			slot[2] = { desc.amp, desc.freq, desc.p1, desc.p2 }
		elseif desc.kind == "zoom" then
			local angle = desc.angle or 0
			slot[2] = { desc.cx, desc.cz, desc.tx, desc.tz }
			slot[3] = { desc.scale, cos(angle), sin(angle), 0 }
		elseif desc.kind == "select" then
			local mask = desc.mask
			if mask.kind == "disc" then
				slot[2] = { 2, mask.band or 0, 0, 0 }
				slot[3] = { mask.cx, mask.cz, mask.r, 0 }
			else
				slot[2] = { 1, mask.band or 0, mask.sign or 1, 0 }
				slot[3] = { mask.px, mask.pz, cos(mask.angle), sin(mask.angle) }
			end
		end

		for slotIndex = 1, 5 do
			for component = 1, 4 do
				prog[base + (slotIndex - 1) * 4 + component] = slot[slotIndex][component]
			end
		end
	end

	return prog, #list
end

-- Short exact fingerprint of a descriptor list; two sides that print the same value built the same transform.
-- Two small rolling hashes (every product stays below 2^24, so float32 Lua numbers compute them exactly).
function Transform.signature(descriptors)
	-- deterministic serialisation: numbers with 9 significant digits, table keys in sorted order
	local function serialize(value)
		local valueType = type(value)
		if valueType == "number" then
			return string.format("%.9g", value)
		elseif valueType == "table" then
			local keys = {}
			for key in pairs(value) do
				keys[#keys + 1] = key
			end
			table.sort(keys, function(keyA, keyB)
				return tostring(keyA) < tostring(keyB)
			end)
			local fields = {}
			for i = 1, #keys do
				fields[i] = tostring(keys[i]) .. "=" .. serialize(value[keys[i]])
			end
			return "{" .. table.concat(fields, ",") .. "}"
		end
		return tostring(value)
	end
	local text = serialize(descriptors)
	local hash1 = 7
	local hash2 = 11
	for i = 1, #text do
		local byte = text:byte(i)
		hash1 = (hash1 * 31 + byte) % 65521
		hash2 = (hash2 * 37 + byte) % 65519
	end
	return string.format("%05d%05d/%d", hash1, hash2, #text)
end

-- Human-readable one-line summary of a descriptor list, e.g. for logs: steps joined by " > ".
function Transform.describe(descriptors)
	local parts = {}
	for i = 1, #descriptors do
		local desc = descriptors[i]
		if desc.kind == "select" then
			parts[i] = "select("
				.. desc.mask.kind
				.. ": ["
				.. Transform.describe(desc.a or {})
				.. "] | ["
				.. Transform.describe(desc.b or {})
				.. "])"
		elseif desc.kind == "nfold" then
			parts[i] = string.format(
				"nfold(n=%d%s%s%s%s)",
				desc.n,
				desc.mirror and ",mirror" or "",
				desc.twist and string.format(",twist=%.2f", desc.twist * 1000) or "",
				desc.ring and string.format(",ring=%.0f%s", desc.ring, desc.ringMirror and "m" or "") or "",
				desc.wedge and string.format(",wedge=%.2f", desc.wedge) or ""
			)
		elseif desc.kind == "tile" then
			parts[i] = string.format(
				"tile(%s %.0fx%.0f%s%s%s%s)",
				desc.mode,
				desc.w,
				desc.h or desc.w,
				desc.brick and string.format(",brick=%.2f", desc.brick) or "",
				desc.shuffle and ",shuffle" or "",
				desc.flip and ",flip" or "",
				desc.band and string.format(",band=%.0f", desc.band) or ""
			)
		elseif desc.kind == "wallpaper" then
			parts[i] = string.format("wallpaper(%s s=%.0f)", desc.group, desc.size)
		elseif desc.kind == "zoom" then
			parts[i] = string.format("zoom(x%.2f)", desc.scale)
		elseif desc.kind == "warp" then
			parts[i] = string.format("warp(amp=%.0f)", desc.amp)
		else
			parts[i] = desc.kind
				.. string.format("(%.0f deg)", (desc.angle or 0) * 180 / pi)
				.. (desc.closing and ("[closing " .. desc.closing .. "]") or "")
		end
	end
	return table.concat(parts, " > ")
end

return Transform
