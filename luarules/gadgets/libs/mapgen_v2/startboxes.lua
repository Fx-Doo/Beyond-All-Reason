-- Start boxes / start positions under a Transform. Pure Lua (no engine calls) so it is testable and can be
-- shared by the synced gadget (computes) and the LuaUI widget (applies the published result).
--
-- Balance rule. The transform always ends in a closing symmetry S (see generate.lua), and the final map is
-- exactly symmetric under S. A start region must therefore come in mirror pairs, otherwise one team could get
-- terrain the other does not. The map is split in two halves by S: D (S is the identity there) and M (the
-- mirrored half). For every point p the original region it falls in is found with the transform (T(p)):
--   * on D, p belongs to that region's team a;
--   * on M, p belongs to the *partner* of that team, partner(a), where partner is an involution pairing teams.
-- So team a owns B_a (its content on D) plus S(B_partner(a)), and its partner owns the exact mirror image:
-- the two regions are mirror images of each other with equal area.
--
-- Contents (in order):
--   * original regions      rect / polygon-set / disc regions as { id, cx, cz, contains(x, z) } records
--   * closing symmetry      the closing descriptor as a plain involution function
--   * outlines              marching a cell mask into polygon rings, simplifying them
--   * main computation      Startboxes.compute: label cells, pair teams, fallback seeds, outlines, mirroring
--   * publishing / applying serialize / deserialize / applyToConfig (synced gadget -> LuaUI widget)
--
-- Conventions: a "ring" is a closed polygon outline, a list of vertices { x, z } (the closing edge back to the
-- first vertex is implicit); a "region" owns a list of rings. The grid has cellsX x cellsZ square cells of
-- cellSize elmos; (cellX, cellZ) are 0-based cell indices and the flat cell index is
-- cellZ * cellsX + cellX + 1.

local floor = math.floor
local ceil = math.ceil
local min = math.min
local max = math.max
local abs = math.abs
local sqrt = math.sqrt
local cos = math.cos
local sin = math.sin
local pi = math.pi

local Startboxes = {}

--------------------------------------------------------------------------------
-- original regions
--------------------------------------------------------------------------------

-- Even-odd (ray casting) point-in-polygon test.
-- ring: list of { x, z } vertices; pointX, pointZ: the point. Returns true when the point is inside.
local function insideRing(ring, pointX, pointZ)
	local inside = false
	local vertexCount = #ring
	local j = vertexCount
	for i = 1, vertexCount do
		local curX = ring[i][1]
		local curZ = ring[i][2]
		local prevX = ring[j][1]
		local prevZ = ring[j][2]
		if (curZ > pointZ) ~= (prevZ > pointZ)
			and pointX < (prevX - curX) * (pointZ - curZ) / (prevZ - curZ) + curX then
			inside = not inside
		end
		j = i
	end
	return inside
end

-- True when the point lies inside at least one of the rings (a region is the union of its rings).
-- rings: list of rings; pointX, pointZ: the point.
function Startboxes.insideRings(rings, pointX, pointZ)
	for i = 1, #rings do
		if insideRing(rings[i], pointX, pointZ) then
			return true
		end
	end
	return false
end

-- Axis-aligned rectangle region (map-defined start box).
-- id: team id; minX, minZ, maxX, maxZ: the rectangle. Returns { id, cx, cz, contains(x, z) } (cx, cz: centre).
function Startboxes.rectRegion(id, minX, minZ, maxX, maxZ)
	return {
		id = id,
		cx = (minX + maxX) * 0.5,
		cz = (minZ + maxZ) * 0.5,
		contains = function(pointX, pointZ)
			return pointX >= minX and pointX <= maxX and pointZ >= minZ and pointZ <= maxZ
		end,
	}
end

-- Polygon region (BAR startbox config polygons).
-- id: team id; rings: list of rings. Returns { id, cx, cz, contains(x, z) }; (cx, cz) is the mean of all vertices.
function Startboxes.ringsRegion(id, rings)
	local sumX = 0
	local sumZ = 0
	local vertexCount = 0
	for i = 1, #rings do
		for j = 1, #rings[i] do
			sumX = sumX + rings[i][j][1]
			sumZ = sumZ + rings[i][j][2]
			vertexCount = vertexCount + 1
		end
	end
	return {
		id = id,
		cx = vertexCount > 0 and sumX / vertexCount or 0,
		cz = vertexCount > 0 and sumZ / vertexCount or 0,
		contains = function(pointX, pointZ)
			return Startboxes.insideRings(rings, pointX, pointZ)
		end,
	}
end

-- Disc region (map-defined start position).
-- id: team id; centerX, centerZ: disc centre; radius: disc radius. Returns { id, cx, cz, contains(x, z) }.
function Startboxes.discRegion(id, centerX, centerZ, radius)
	local radiusSquared = radius * radius
	return {
		id = id,
		cx = centerX,
		cz = centerZ,
		contains = function(pointX, pointZ)
			local deltaX = pointX - centerX
			local deltaZ = pointZ - centerZ
			return deltaX * deltaX + deltaZ * deltaZ <= radiusSquared
		end,
	}
end

--------------------------------------------------------------------------------
-- the closing symmetry as a plain involution
--------------------------------------------------------------------------------

-- Unit vector of a direction angle; the axis-aligned angles are exact (no cos/sin rounding noise).
-- angle: radians. Returns dirX, dirZ.
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

-- The closing symmetry S as a plain function.
-- desc: the closing descriptor (descriptors[1]): a "rotate" (about desc.cx/cz or desc.px/pz by desc.rot, default
-- half a turn) or a reflection about the line through (desc.px, desc.pz) with direction desc.angle.
-- Returns f(x, z) -> x', z' with f(f(p)) == p.
function Startboxes.involution(desc)
	if desc.kind == "rotate" then
		local centerX = desc.cx or desc.px
		local centerZ = desc.cz or desc.pz
		local cosRot = cos(desc.rot or pi)
		local sinRot = sin(desc.rot or pi)
		return function(pointX, pointZ)
			local deltaX = pointX - centerX
			local deltaZ = pointZ - centerZ
			return centerX + deltaX * cosRot - deltaZ * sinRot, centerZ + deltaX * sinRot + deltaZ * cosRot
		end
	end
	local axisX, axisZ = unitVector(desc.angle)
	local normalX = -axisZ
	local normalZ = axisX
	return function(pointX, pointZ)
		-- signed distance from the mirror line, then step twice that distance along the normal
		local distance = (pointX - desc.px) * normalX + (pointZ - desc.pz) * normalZ
		return pointX - 2 * distance * normalX, pointZ - 2 * distance * normalZ
	end
end

--------------------------------------------------------------------------------
-- outlines of a cell mask
--------------------------------------------------------------------------------

-- Iterative Ramer-Douglas-Peucker on points[first..last]: marks the vertices to keep.
-- points: list of { x, z }; first, last: index range (both endpoints are always kept); tolerance: maximum
-- distance a dropped vertex may be from the simplified line; keep: output set, keep[index] = true.
local function simplifyOpen(points, first, last, tolerance, keep)
	local stack = { { first, last } }
	keep[first] = true
	keep[last] = true
	while #stack > 0 do
		local segment = table.remove(stack)
		local startIndex = segment[1]
		local endIndex = segment[2]
		local startX = points[startIndex][1]
		local startZ = points[startIndex][2]
		local endX = points[endIndex][1]
		local endZ = points[endIndex][2]
		local deltaX = endX - startX
		local deltaZ = endZ - startZ
		local length = sqrt(deltaX * deltaX + deltaZ * deltaZ)
		local farthest = nil
		local worstDistance = tolerance
		for i = startIndex + 1, endIndex - 1 do
			local distance
			if length < 1e-9 then
				-- degenerate segment (closed loop): plain distance to its start point
				distance = sqrt((points[i][1] - startX) ^ 2 + (points[i][2] - startZ) ^ 2)
			else
				distance = abs((points[i][1] - startX) * deltaZ - (points[i][2] - startZ) * deltaX) / length
			end
			if distance > worstDistance then
				farthest = i
				worstDistance = distance
			end
		end
		if farthest then
			keep[farthest] = true
			stack[#stack + 1] = { startIndex, farthest }
			stack[#stack + 1] = { farthest, endIndex }
		end
	end
end

-- Simplifies a closed ring with Ramer-Douglas-Peucker.
-- ring: list of { x, z }; tolerance: see simplifyOpen. Returns a new ring (or the input when it has <= 4 vertices).
local function simplifyRing(ring, tolerance)
	local vertexCount = #ring
	if vertexCount <= 4 then
		return ring
	end
	-- anchor on point 1 and the point farthest from it
	local farthest = 2
	local bestDistance = -1
	for i = 2, vertexCount do
		local distance = (ring[i][1] - ring[1][1]) ^ 2 + (ring[i][2] - ring[1][2]) ^ 2
		if distance > bestDistance then
			farthest = i
			bestDistance = distance
		end
	end
	-- the ring as an open polyline that returns to its first vertex
	local points = {}
	for i = 1, vertexCount do
		points[i] = ring[i]
	end
	points[vertexCount + 1] = ring[1]
	local keepFirstHalf = {}
	local keepSecondHalf = {}
	simplifyOpen(points, 1, farthest, tolerance, keepFirstHalf)
	simplifyOpen(points, farthest, vertexCount + 1, tolerance, keepSecondHalf)
	local simplified = {}
	for i = 1, vertexCount do
		if keepFirstHalf[i] or keepSecondHalf[i] then
			simplified[#simplified + 1] = ring[i]
		end
	end
	return simplified
end

-- Removes vertices that lie on a straight line between their neighbours (exactly collinear, cross product 0).
-- ring: list of { x, z }. Returns a new ring.
local function dropCollinear(ring)
	local result = {}
	local vertexCount = #ring
	for i = 1, vertexCount do
		local prevVertex = ring[(i - 2) % vertexCount + 1]
		local vertex = ring[i]
		local nextVertex = ring[i % vertexCount + 1]
		local cross = (vertex[1] - prevVertex[1]) * (nextVertex[2] - vertex[2])
			- (vertex[2] - prevVertex[2]) * (nextVertex[1] - vertex[1])
		if cross ~= 0 then
			result[#result + 1] = vertex
		end
	end
	return result
end

-- Signed polygon area (shoelace formula); the sign tells the winding direction.
-- ring: list of { x, z }. Returns the area.
local function ringArea(ring)
	local area = 0
	local vertexCount = #ring
	for i = 1, vertexCount do
		local vertexP = ring[i]
		local vertexQ = ring[i % vertexCount + 1]
		area = area + (vertexP[1] * vertexQ[2] - vertexQ[1] * vertexP[2])
	end
	return area * 0.5
end

-- edge direction codes: 1 = +x, 2 = +z, 3 = -x, 4 = -z (the next code is a left turn)
local DIR = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }

-- Traces the outline of a cell mask: collects the boundary edges of all inside cells, chains them into loops,
-- and cleans the loops up (collinear vertices dropped, small ones discarded, optional simplification).
-- inside(cellX, cellZ) -> bool over a cellsX x cellsZ grid of cellSize sized cells; mapWidth, mapHeight clamp the
-- result; tolerance (optional): simplification tolerance; minArea (optional, default 0): loops of at most this
-- area are dropped.
-- Returns rings of world coordinates (outer boundaries only; interior holes are dropped, so a region reads as a
-- union of polygons).
function Startboxes.trace(inside, cellsX, cellsZ, cellSize, mapWidth, mapHeight, tolerance, minArea)
	-- boundary edges, bucketed by the grid corner they start from: corner key -> list of edges leaving it
	local edges = {}
	local cornerStride = cellsX + 1

	-- Registers a boundary edge leaving grid corner (cornerX, cornerZ) in direction dir (see DIR).
	local function addEdge(cornerX, cornerZ, dir)
		local key = cornerZ * cornerStride + cornerX + 1
		local list = edges[key]
		if not list then
			list = {}
			edges[key] = list
		end
		list[#list + 1] = { dir = dir, used = false, cornerX = cornerX, cornerZ = cornerZ }
	end

	-- every inside cell contributes the sides that touch a non-inside neighbour (or the grid border),
	-- oriented so that the inside is on the left
	for cellZ = 0, cellsZ - 1 do
		for cellX = 0, cellsX - 1 do
			if inside(cellX, cellZ) then
				if not (cellZ > 0 and inside(cellX, cellZ - 1)) then
					addEdge(cellX, cellZ, 1)
				end
				if not (cellX < cellsX - 1 and inside(cellX + 1, cellZ)) then
					addEdge(cellX + 1, cellZ, 2)
				end
				if not (cellZ < cellsZ - 1 and inside(cellX, cellZ + 1)) then
					addEdge(cellX + 1, cellZ + 1, 3)
				end
				if not (cellX > 0 and inside(cellX - 1, cellZ)) then
					addEdge(cellX, cellZ + 1, 4)
				end
			end
		end
	end

	-- chain the edges head to tail into closed loops
	local rings = {}
	for _, list in pairs(edges) do
		for _, startEdge in ipairs(list) do
			if not startEdge.used then
				local outline = {}
				local edge = startEdge
				while edge and not edge.used do
					edge.used = true
					outline[#outline + 1] = {
						min(edge.cornerX * cellSize, mapWidth),
						min(edge.cornerZ * cellSize, mapHeight),
					}
					local step = DIR[edge.dir]
					local candidates = edges[(edge.cornerZ + step[2]) * cornerStride + (edge.cornerX + step[1]) + 1]
					local nextEdge = nil
					if candidates then
						-- prefer a left turn, then straight, then a right turn: diagonal contacts stay separate
						local preferredDirs = { (edge.dir % 4) + 1, edge.dir, ((edge.dir + 2) % 4) + 1 }
						for k = 1, 3 do
							for _, candidate in ipairs(candidates) do
								if not candidate.used and candidate.dir == preferredDirs[k] then
									nextEdge = candidate
									break
								end
							end
							if nextEdge then
								break
							end
						end
					end
					edge = nextEdge
				end
				if #outline >= 4 then
					local ring = dropCollinear(outline)
					if #ring >= 3 and ringArea(ring) > (minArea or 0) then
						rings[#rings + 1] = ring
					end
				end
			end
		end
	end

	if tolerance and tolerance > 0 then
		for i = 1, #rings do
			rings[i] = simplifyRing(rings[i], tolerance)
		end
	end
	return rings
end

-- Bounding box of a set of rings.
-- rings: list of rings. Returns minX, minZ, maxX, maxZ (inf, inf, -inf, -inf when there are no vertices).
function Startboxes.bounds(rings)
	local minX = math.huge
	local minZ = math.huge
	local maxX = -math.huge
	local maxZ = -math.huge
	for i = 1, #rings do
		for j = 1, #rings[i] do
			local vertex = rings[i][j]
			minX = min(minX, vertex[1])
			minZ = min(minZ, vertex[2])
			maxX = max(maxX, vertex[1])
			maxZ = max(maxZ, vertex[2])
		end
	end
	return minX, minZ, maxX, maxZ
end

--------------------------------------------------------------------------------
-- main computation
--------------------------------------------------------------------------------

-- Pairs the teams into mirror pairs (an involution: partner[partner[a]] == a).
-- regionIds: list of team ids; areaOnD: id -> number of cells the team owns on the home half D;
-- centers: id -> { cx, cz } of the original region; mirror: the closing symmetry function, or nil when the map has
-- none (every team is then its own partner).
-- Teams are visited from the largest D content down; each takes the free team whose centre is nearest to its own
-- mirrored centre. Returns partner: id -> id.
local function pairTeams(regionIds, areaOnD, centers, mirror)
	local partner = {}
	if not mirror then
		for _, id in ipairs(regionIds) do
			partner[id] = id
		end
		return partner
	end
	local order = {}
	for i, id in ipairs(regionIds) do
		order[i] = { id = id, index = i }
	end
	-- largest D area first; ties keep the input order (table.sort is not stable)
	table.sort(order, function(a, b)
		if areaOnD[a.id] ~= areaOnD[b.id] then
			return areaOnD[a.id] > areaOnD[b.id]
		end
		return a.index < b.index
	end)
	for _, entry in ipairs(order) do
		local idA = entry.id
		if not partner[idA] then
			local mirroredX, mirroredZ = mirror(centers[idA][1], centers[idA][2])
			local bestId
			local bestScore
			-- a team with content on D prefers a partner without any (that partner receives the mirror image)
			for pass = 1, 2 do
				for _, idB in ipairs(regionIds) do
					if idB ~= idA and not partner[idB] and (pass == 2 or areaOnD[idA] == 0 or areaOnD[idB] == 0) then
						local score = (centers[idB][1] - mirroredX) ^ 2 + (centers[idB][2] - mirroredZ) ^ 2
						if not bestScore or score < bestScore then
							bestId = idB
							bestScore = score
						end
					end
				end
				if bestId then
					break
				end
			end
			if bestId then
				partner[idA] = bestId
				partner[bestId] = idA
			else
				partner[idA] = idA
			end
		end
	end
	return partner
end

-- Computes the mirror-paired start regions of a transform.
-- transform: the Transform; descriptors: its descriptors (descriptors[1] may be the closing symmetry);
-- mapWidth, mapHeight: map size in elmos; regions: list of { id, cx, cz, contains(x, z) } (original regions, see
-- rectRegion / ringsRegion / discRegion);
-- opts.cell (default 32), opts.tolerance (outline simplification, default 0.8 cell), opts.minCells (default 4),
-- opts.fallbackRadius (radius of the seed discs for pairs without content, fraction of the smaller map side,
-- default 0.07).
-- Returns { regions = { [id] = { rings, bounds, cx, cz, cells, dCells } }, partner, cell, nx, nz, labels, side,
-- areaD }; labels[cellIndex] is the owning team id (or false), side[cellIndex] is true on the mirrored half.
function Startboxes.compute(transform, descriptors, mapWidth, mapHeight, regions, opts)
	opts = opts or {}
	local cellSize = opts.cell or 32
	local cellsX = ceil(mapWidth / cellSize)
	local cellsZ = ceil(mapHeight / cellSize)
	local closing = descriptors and descriptors[1] and descriptors[1].closing and descriptors[1] or nil
	local mirror = closing and Startboxes.involution(closing) or nil
	local firstItem = transform.items[1]

	local regionIds = {}
	local centers = {}
	for i, region in ipairs(regions) do
		regionIds[i] = region.id
		centers[region.id] = { region.cx, region.cz }
	end

	-- 1. label every cell with the team of the original region its transformed centre falls in, and note which
	--    half (D or M) it is on
	local rawLabels = {}
	local side = {}
	local areaOnD = {}
	for _, id in ipairs(regionIds) do
		areaOnD[id] = 0
	end
	for cellZ = 0, cellsZ - 1 do
		local centerZ = (cellZ + 0.5) * cellSize
		for cellX = 0, cellsX - 1 do
			local centerX = (cellX + 0.5) * cellSize
			local cellIndex = cellZ * cellsX + cellX + 1
			local mirrored = false
			if closing then
				-- third result of the closing item: 0 on D, 1 on the mirrored half, 0.5 on the seam
				local _, _, mirrorSelect = firstItem.f(centerX, centerZ)
				if mirrorSelect > 0.5 + 1e-9 then
					mirrored = true
				elseif mirrorSelect >= 0.5 - 1e-9 then
					-- exactly on the seam: p and S(p) both land here, exactly one of them must count as mirrored
					local mirrorX, mirrorZ = mirror(centerX, centerZ)
					mirrored = centerX > mirrorX + 1e-6 or (abs(centerX - mirrorX) <= 1e-6 and centerZ > mirrorZ)
				end
			end
			side[cellIndex] = mirrored
			-- where this cell's centre came from in the source map
			local srcX, srcZ = transform:map(centerX, centerZ)
			local label = false
			-- cells on the symmetry axis are their own mirror image and cannot belong to one team of a pair
			local onAxis = false
			if mirror then
				local mirrorX, mirrorZ = mirror(centerX, centerZ)
				onAxis = abs(mirrorX - centerX) < cellSize * 0.5 and abs(mirrorZ - centerZ) < cellSize * 0.5
			end
			for k = 1, #regions do
				if not onAxis and regions[k].contains(srcX, srcZ) then
					label = regions[k].id
					break
				end
			end
			rawLabels[cellIndex] = label
			if label and not mirrored then
				areaOnD[label] = areaOnD[label] + 1
			end
		end
	end

	-- 2. pair the teams; on the mirrored half a cell belongs to the partner of the team it was labelled with
	local partner = pairTeams(regionIds, areaOnD, centers, mirror)
	local labels = {}
	for cellIndex = 1, cellsX * cellsZ do
		local label = rawLabels[cellIndex]
		if label and side[cellIndex] then
			label = partner[label]
		end
		labels[cellIndex] = label
	end

	-- 3. A pair whose box content appears nowhere (e.g. cropped away by a zoom) still needs a place to start:
	--    give it a disc on D plus its mirror image, away from everything already assigned.
	if mirror then
		local counts = {}
		for cellIndex = 1, cellsX * cellsZ do
			if labels[cellIndex] then
				counts[labels[cellIndex]] = (counts[labels[cellIndex]] or 0) + 1
			end
		end
		local radius = (opts.fallbackRadius or 0.07) * min(mapWidth, mapHeight)
		local seeds = {}
		local done = {}
		for _, id in ipairs(regionIds) do
			if not counts[id] and not done[id] then
				local partnerId = partner[id]
				done[id] = true
				done[partnerId] = true
				-- seed: the free D cell farthest from earlier seeds (the first one: the free D cell closest to the D
				-- centroid)
				local sumX = 0
				local sumZ = 0
				local freeCount = 0
				for cellZ = 0, cellsZ - 1 do
					for cellX = 0, cellsX - 1 do
						local cellIndex = cellZ * cellsX + cellX + 1
						if not labels[cellIndex] and not side[cellIndex] then
							sumX = sumX + (cellX + 0.5) * cellSize
							sumZ = sumZ + (cellZ + 0.5) * cellSize
							freeCount = freeCount + 1
						end
					end
				end
				if freeCount > 0 then
					local bestSeed
					local bestScore
					for cellZ = 0, cellsZ - 1 do
						for cellX = 0, cellsX - 1 do
							local cellIndex = cellZ * cellsX + cellX + 1
							if not labels[cellIndex] and not side[cellIndex] then
								local centerX = (cellX + 0.5) * cellSize
								local centerZ = (cellZ + 0.5) * cellSize
								local score
								if #seeds == 0 then
									score = -((centerX - sumX / freeCount) ^ 2 + (centerZ - sumZ / freeCount) ^ 2)
								else
									score = math.huge
									for _, seed in ipairs(seeds) do
										score = min(score, (centerX - seed[1]) ^ 2 + (centerZ - seed[2]) ^ 2)
									end
								end
								if not bestScore or score > bestScore then
									bestSeed = { centerX, centerZ }
									bestScore = score
								end
							end
						end
					end
					seeds[#seeds + 1] = bestSeed
					-- claim the free D cells within the radius, and their mirror cells for the partner
					for cellZ = 0, cellsZ - 1 do
						for cellX = 0, cellsX - 1 do
							local cellIndex = cellZ * cellsX + cellX + 1
							local centerX = (cellX + 0.5) * cellSize
							local centerZ = (cellZ + 0.5) * cellSize
							if not labels[cellIndex] and not side[cellIndex]
								and (centerX - bestSeed[1]) ^ 2 + (centerZ - bestSeed[2]) ^ 2 <= radius * radius then
								local mirrorX, mirrorZ = mirror(centerX, centerZ)
								local mirrorCellX = floor(mirrorX / cellSize)
								local mirrorCellZ = floor(mirrorZ / cellSize)
								if mirrorCellX >= 0 and mirrorCellX < cellsX
									and mirrorCellZ >= 0 and mirrorCellZ < cellsZ
									and not labels[mirrorCellZ * cellsX + mirrorCellX + 1] then
									labels[cellIndex] = id
									labels[mirrorCellZ * cellsX + mirrorCellX + 1] = partnerId
								end
							end
						end
					end
				end
			end
		end
	end

	-- 4. outline every team's cells, and pick a representative start point inside
	local outRegions = {}
	local tolerance = opts.tolerance or cellSize * 0.8
	for _, id in ipairs(regionIds) do
		local cellCount = 0
		local dCellCount = 0
		local sumX = 0
		local sumZ = 0
		local dSumX = 0
		local dSumZ = 0
		for cellZ = 0, cellsZ - 1 do
			for cellX = 0, cellsX - 1 do
				local cellIndex = cellZ * cellsX + cellX + 1
				if labels[cellIndex] == id then
					cellCount = cellCount + 1
					sumX = sumX + (cellX + 0.5) * cellSize
					sumZ = sumZ + (cellZ + 0.5) * cellSize
					if not side[cellIndex] then
						dCellCount = dCellCount + 1
						dSumX = dSumX + (cellX + 0.5) * cellSize
						dSumZ = dSumZ + (cellZ + 0.5) * cellSize
					end
				end
			end
		end
		if cellCount >= (opts.minCells or 4) then
			local rings = Startboxes.trace(function(cellX, cellZ)
				return labels[cellZ * cellsX + cellX + 1] == id
			end, cellsX, cellsZ, cellSize, mapWidth, mapHeight, tolerance, cellSize * cellSize * 2)
			-- a representative point inside the region: the cell nearest to the centroid of its home half (D)
			local targetX = sumX / cellCount
			local targetZ = sumZ / cellCount
			if dCellCount > 0 then
				targetX = dSumX / dCellCount
				targetZ = dSumZ / dCellCount
			end
			local bestX
			local bestZ
			local bestDistance
			-- true when the four direct neighbours of the cell belong to the region too
			local function interior(cellX, cellZ)
				return cellX > 0 and cellZ > 0 and cellX < cellsX - 1 and cellZ < cellsZ - 1
					and labels[cellZ * cellsX + cellX] == id
					and labels[cellZ * cellsX + cellX + 2] == id
					and labels[(cellZ - 1) * cellsX + cellX + 1] == id
					and labels[(cellZ + 1) * cellsX + cellX + 1] == id
			end
			-- pass 1: well inside the outline (also keeps the point off edges, which the mirrored copy shares);
			-- pass 2: anywhere inside the outline; pass 3: any cell of the region
			for pass = 1, 3 do
				for cellZ = 0, cellsZ - 1 do
					for cellX = 0, cellsX - 1 do
						local cellIndex = cellZ * cellsX + cellX + 1
						if labels[cellIndex] == id and (pass == 3 or dCellCount == 0 or not side[cellIndex])
							and (pass ~= 1 or interior(cellX, cellZ)) then
							local centerX = (cellX + 0.5) * cellSize
							local centerZ = (cellZ + 0.5) * cellSize
							local distance = (centerX - targetX) ^ 2 + (centerZ - targetZ) ^ 2
							if (not bestDistance or distance < bestDistance)
								and (pass == 3 or Startboxes.insideRings(rings, centerX, centerZ)) then
								bestX = centerX
								bestZ = centerZ
								bestDistance = distance
							end
						end
					end
				end
				if bestDistance then
					break
				end
			end
			if #rings > 0 then
				local minX, minZ, maxX, maxZ = Startboxes.bounds(rings)
				outRegions[id] = {
					rings = rings,
					bounds = { minX, minZ, maxX, maxZ },
					cx = bestX,
					cz = bestZ,
					cells = cellCount,
					dCells = dCellCount,
				}
			end
		end
	end

	-- 5. the partner's outline is the exact mirror image of its pair's (simplifying both independently would leave
	--    tiny differences at their edges)
	if mirror then
		local seen = {}
		for _, idA in ipairs(regionIds) do
			local idB = partner[idA]
			if idB ~= idA and not seen[idA] and outRegions[idA] and outRegions[idB] then
				seen[idA] = true
				seen[idB] = true
				local mirroredRings = {}
				for i, ring in ipairs(outRegions[idA].rings) do
					local mirroredRing = {}
					for j, vertex in ipairs(ring) do
						local mirrorX, mirrorZ = mirror(vertex[1], vertex[2])
						mirroredRing[j] = { max(0, min(mapWidth, mirrorX)), max(0, min(mapHeight, mirrorZ)) }
					end
					if ringArea(mirroredRing) < 0 then -- a reflection flips the winding
						for j = 1, floor(#mirroredRing / 2) do
							mirroredRing[j], mirroredRing[#mirroredRing + 1 - j] =
								mirroredRing[#mirroredRing + 1 - j], mirroredRing[j]
						end
					end
					mirroredRings[i] = mirroredRing
				end
				local minX, minZ, maxX, maxZ = Startboxes.bounds(mirroredRings)
				local mirroredCx, mirroredCz = mirror(outRegions[idA].cx, outRegions[idA].cz)
				outRegions[idB].rings = mirroredRings
				outRegions[idB].bounds = { minX, minZ, maxX, maxZ }
				outRegions[idB].cx = mirroredCx
				outRegions[idB].cz = mirroredCz
			end
		end
	end

	return {
		regions = outRegions,
		partner = partner,
		cell = cellSize,
		nx = cellsX,
		nz = cellsZ,
		labels = labels,
		side = side,
		areaD = areaOnD,
	}
end

--------------------------------------------------------------------------------
-- publishing / applying
--------------------------------------------------------------------------------

-- Compact text form of the computed regions, published by the synced gadget as a game rules parameter.
-- Format: id@cx,cz:x,z x,z;x,z x,z|id@...   (rings separated by ";", vertices by " ", teams by "|";
-- all numbers rounded to whole elmos, teams in ascending id order).
-- entries: { [id] = { rings, cx, cz } }. Returns the string.
function Startboxes.serialize(entries)
	local ids = {}
	for id in pairs(entries) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local parts = {}
	for _, id in ipairs(ids) do
		local entry = entries[id]
		local ringStrings = {}
		for i = 1, #entry.rings do
			local vertexStrings = {}
			for j = 1, #entry.rings[i] do
				vertexStrings[j] = string.format(
					"%d,%d",
					floor(entry.rings[i][j][1] + 0.5),
					floor(entry.rings[i][j][2] + 0.5)
				)
			end
			ringStrings[i] = table.concat(vertexStrings, " ")
		end
		parts[#parts + 1] = string.format(
			"%d@%d,%d:%s",
			id,
			floor(entry.cx + 0.5),
			floor(entry.cz + 0.5),
			table.concat(ringStrings, ";")
		)
	end
	return table.concat(parts, "|")
end

-- Inverse of serialize.
-- str: the published string (nil / "" gives an empty table). Rings with fewer than 3 vertices are dropped.
-- Returns entries: { [id] = { rings, cx, cz } } with numeric ids and coordinates.
function Startboxes.deserialize(str)
	local entries = {}
	if not str or str == "" then
		return entries
	end
	for part in str:gmatch("[^|]+") do
		local id, cx, cz, body = part:match("^(%-?%d+)@(%-?%d+),(%-?%d+):(.*)$")
		if id then
			local rings = {}
			for ringText in body:gmatch("[^;]+") do
				local ring = {}
				for x, z in ringText:gmatch("(%-?%d+),(%-?%d+)") do
					ring[#ring + 1] = { tonumber(x), tonumber(z) }
				end
				if #ring >= 3 then
					rings[#rings + 1] = ring
				end
			end
			entries[tonumber(id)] = { rings = rings, cx = tonumber(cx), cz = tonumber(cz) }
		end
	end
	return entries
end

-- Overwrites the polygons of a BAR startbox config (startbox_utilities' table) in place.
-- config: the config table, config[id] = startbox entry; entries: see deserialize; maxZ (optional): vertices are
-- clamped to this z (the last map row). Returns the number of config entries that were updated.
function Startboxes.applyToConfig(config, entries, maxZ)
	local updated = 0
	for id, entry in pairs(entries) do
		local configEntry = config[id]
		if configEntry then
			local boxes = {}
			for i = 1, #entry.rings do
				local ring = {}
				for j = 1, #entry.rings[i] do
					local z = entry.rings[i][j][2]
					ring[j] = { entry.rings[i][j][1], maxZ and min(z, maxZ) or z }
				end
				ring.anchors = ring
				boxes[i] = ring
			end
			configEntry.boxes = boxes
			configEntry.startpoints = { { entry.cx, entry.cz } }
			configEntry.wholeMap = nil
			updated = updated + 1
		end
	end
	return updated
end

return Startboxes
