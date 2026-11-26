-- Protected points (metal spots, geo vents): every copy of one must show the WHOLE original neighbourhood, never a
-- half cut by a seam, a fold line or a cross-fade band.
--
-- For each place the transform shows a protected point (its "images") the neighbourhood is tested with
-- Transform:isClean. Copies that are not clean get a patch: a disc around the copy that is redrawn as an exact affine
-- copy of the disc around the original point, blended into its surroundings. The patch list is a pure function of the
-- transform and the protected points, so the synced side (terrain) and the unsynced side (textures) compute the same.
--
-- patch = { qx, qz = centre of the copy, mx, mz = original point it shows, a, b, c, d = local linear map (copy offset
--           -> original offset), r = solid radius, blend = width of the blended rim }
--
-- In the code, positions of the transformed (output) map are outX / outZ (patch.qx / qz) and positions of the source
-- map are srcX / srcZ (patch.mx / mz). The linear map { a, b, c, d } is the 2x2 matrix [ m11 m12 ; m21 m22 ]:
--   srcOffset = ( a * outOffsetX + b * outOffsetZ,  c * outOffsetX + d * outOffsetZ )

local floor, abs, sqrt, pi = math.floor, math.abs, math.sqrt, math.pi

local Patches = {}

Patches.MAX_PATCHES = 900


--------------------------------------------------------------------------------------------------------------------
-- Closing symmetry
--------------------------------------------------------------------------------------------------------------------

-- The closing symmetry S of a chain.
--   descs: the chain's descriptors (descs[1].closing names the symmetry); mapWidth, mapHeight: map size in elmos
-- Returns the point map (x, z) -> (x', z') and its linear part { m11, m12, m21, m22 }, or nothing when the chain has
-- no closing symmetry.
local function closingOf(descs, mapWidth, mapHeight)
	local firstDesc = descs and descs[1]
	local closingKind = firstDesc and firstDesc.closing
	if closingKind == "vertical" then
		return function(x, z)
			return mapWidth - x, z
		end, { -1, 0, 0, 1 }
	elseif closingKind == "horizontal" then
		return function(x, z)
			return x, mapHeight - z
		end, { 1, 0, 0, -1 }
	elseif closingKind == "central" then
		return function(x, z)
			return mapWidth - x, mapHeight - z
		end, { -1, 0, 0, -1 }
	elseif closingKind == "diagonal" then
		if firstDesc.angle == pi / 4 then
			return function(x, z)
				return z, x
			end, { 0, 1, 1, 0 }
		end
		return function(x, z)
			return mapWidth - z, mapHeight - x
		end, { 0, -1, -1, 0 }
	end
end


--------------------------------------------------------------------------------------------------------------------
-- Building the patch list
--------------------------------------------------------------------------------------------------------------------

-- Builds the patches for every unclean image of every protected point.
--   transform: the Transform; points: { { x, z, radius, blend }, ... } in base (source) map coordinates
-- Returns the patch list (at most Patches.MAX_PATCHES entries).
function Patches.build(transform, points)
	local patches = {}
	local closingMap, closingLinear = closingOf(transform.descs, transform.W, transform.H)
	for _, point in ipairs(points) do
		local images = transform:preimages(point[1], point[2])
		for _, image in ipairs(images) do
			local outX, outZ = image[1], image[2]

			-- one canonical image per mirror pair; its twin is generated from it so the result is exactly symmetric
			local canonical, mirrorX, mirrorZ = true, nil, nil
			if closingMap then
				mirrorX, mirrorZ = closingMap(outX, outZ)
				if mirrorX < outX - 1e-6 or (abs(mirrorX - outX) <= 1e-6 and mirrorZ < outZ - 1e-6) then
					canonical = false
				end
			end

			if canonical and not transform:isClean(outX, outZ, point[3]) then
				local srcX, srcZ = transform:map(outX, outZ)

				-- the local linear map; if a seam passes within a fraction of an elmo of the exact centre its finite
				-- difference is useless, so step a little to the side and take the one that still lands on the point
				local m11, m12, m21, m22
				local fallback -- first sound linear map even if it does not continue through the exact centre
				local shifts = { { 0, 0 }, { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 }, { 6, 6 }, { -6, -6 } }
				for _, shift in ipairs(shifts) do
					local j11, j12, j21, j22 = transform:jacobian(outX + shift[1], outZ + shift[2], 0.75)
					local det = j11 * j22 - j12 * j21
					if abs(det) > 0.25 and abs(det) < 4 then
						local shiftedSrcX, shiftedSrcZ = transform:map(outX + shift[1], outZ + shift[2])
						-- does the linear map, started from the original point, land on the mapped shifted point?
						if abs(shiftedSrcX - (srcX + j11 * shift[1] + j12 * shift[2])) < 4
							and abs(shiftedSrcZ - (srcZ + j21 * shift[1] + j22 * shift[2])) < 4 then
							m11, m12, m21, m22 = j11, j12, j21, j22
							break
						end
						fallback = fallback
							or { j11, j12, j21, j22, outX + shift[1], outZ + shift[2], shiftedSrcX, shiftedSrcZ }
					end
				end
				if not m11 and fallback then
					-- re-pivot on the shifted point: the copy is off by a few elmos at most, but whole
					m11, m12, m21, m22 = fallback[1], fallback[2], fallback[3], fallback[4]
					outX = fallback[5]
					outZ = fallback[6]
					srcX = fallback[7]
					srcZ = fallback[8]
					if closingMap then
						mirrorX, mirrorZ = closingMap(outX, outZ)
					end
				end

				if m11 then
					patches[#patches + 1] = {
						qx = outX, qz = outZ, mx = srcX, mz = srcZ,
						a = m11, b = m12, c = m21, d = m22,
						r = point[3], blend = point[4],
					}
					if closingMap and (abs(mirrorX - outX) > 1e-6 or abs(mirrorZ - outZ) > 1e-6) then
						-- out(S q + e) = out(q + Ls^-1 e); Ls is an involution so Ls^-1 = Ls
						local s11, s12 = closingLinear[1], closingLinear[2]
						local s21, s22 = closingLinear[3], closingLinear[4]
						patches[#patches + 1] = {
							qx = mirrorX, qz = mirrorZ, mx = srcX, mz = srcZ,
							a = m11 * s11 + m12 * s21, b = m11 * s12 + m12 * s22,
							c = m21 * s11 + m22 * s21, d = m21 * s12 + m22 * s22,
							r = point[3], blend = point[4],
						}
					end
					if #patches >= Patches.MAX_PATCHES then
						return patches
					end
				end
			end
		end
	end
	return patches
end

--------------------------------------------------------------------------------------------------------------------
-- Statistics
--------------------------------------------------------------------------------------------------------------------

-- Number of pairs of copies (of any protected points) that sit closer than the sum of their radii: such two copies
-- cannot both be shown whole, so a chain with conflicts is re-rolled by the caller.
--   transform: the Transform; points: { { x, z, radius, ... }, ... } in base (source) map coordinates
function Patches.conflicts(transform, points)
	local images = {}
	for _, point in ipairs(points) do
		for _, image in ipairs(transform:preimages(point[1], point[2])) do
			images[#images + 1] = { image[1], image[2], point[3] }
		end
	end

	-- spatial hash: buckets of bucketSize elmos, so each copy is only compared with copies in the 3 x 3 buckets
	-- around it
	local bucketSize, buckets, count = 200, {}, 0
	for imageIndex, image in ipairs(images) do
		local bucketX = floor(image[1] / bucketSize)
		local bucketZ = floor(image[2] / bucketSize)
		for deltaX = -1, 1 do
			for deltaZ = -1, 1 do
				local neighbors = buckets[(bucketX + deltaX) * 100000 + bucketZ + deltaZ]
				if neighbors then
					for _, otherIndex in ipairs(neighbors) do
						local other = images[otherIndex]
						if sqrt((other[1] - image[1]) ^ 2 + (other[2] - image[2]) ^ 2) < other[3] + image[3] then
							count = count + 1
						end
					end
				end
			end
		end
		local key = bucketX * 100000 + bucketZ
		local bucket = buckets[key]
		if not bucket then
			bucket = {}
			buckets[key] = bucket
		end
		bucket[#bucket + 1] = imageIndex
	end
	return count
end


-- Total number of places the transform shows the first pointCount of `points` (a spot that is shown twice counts
-- twice).
function Patches.copies(transform, points, pointCount)
	local count = 0
	for i = 1, pointCount do
		count = count + #transform:preimages(points[i][1], points[i][2])
	end
	return count
end


--------------------------------------------------------------------------------------------------------------------
-- Applying patches to a grid
--------------------------------------------------------------------------------------------------------------------

-- Blend weight of a patch at an output position: 1 inside the solid disc, 0 outside the rim (smooth in between).
function Patches.weight(patch, outX, outZ)
	local distance = sqrt((outX - patch.qx) ^ 2 + (outZ - patch.qz) ^ 2)
	local t = (distance - patch.r) / patch.blend
	if t <= 0 then
		return 1
	elseif t >= 1 then
		return 0
	end
	return 1 - t * t * (3 - 2 * t)
end


-- Redraws the discs of a regular grid (same layout as field.lua: flat, index = cellZ * cellsX + cellX + 1) from the
-- original grid `base`, using `sample(base, cellsX, cellsZ, cellSize, offset, x, z)` (Field.bilinear / Field.nearest).
-- match = true: the copy keeps its exact shape but is lifted by one constant so that its rim meets the surrounding
-- grid (average difference on the circle where the blend ends). Without it a copy that comes from higher or lower
-- ground puts the whole height difference into the rim, a cliff right beside a mex.
--   patches: from Patches.build; outGrid: the transformed grid, edited in place; base: the untouched source grid
function Patches.applyToGrid(patches, outGrid, base, cellsX, cellsZ, cellSize, centered, sample, match)
	local offset = centered and 0.5 or 0
	for _, patch in ipairs(patches) do
		local reach = patch.r + patch.blend

		-- constant height lift: mean (current output - patch copy) over 24 points on the outer rim circle
		local lift = 0
		if match then
			local sum, count = 0, 0
			for step = 0, 23 do
				local angle = step * pi / 12
				local rimDeltaX = reach * math.cos(angle)
				local rimDeltaZ = reach * math.sin(angle)
				local outX = patch.qx + rimDeltaX
				local outZ = patch.qz + rimDeltaZ
				if outX >= 0 and outZ >= 0
					and outX <= (cellsX - 1 + 2 * offset) * cellSize
					and outZ <= (cellsZ - 1 + 2 * offset) * cellSize then
					local copyValue = sample(
						base, cellsX, cellsZ, cellSize, offset,
						patch.mx + patch.a * rimDeltaX + patch.b * rimDeltaZ,
						patch.mz + patch.c * rimDeltaX + patch.d * rimDeltaZ
					)
					sum = sum + sample(outGrid, cellsX, cellsZ, cellSize, offset, outX, outZ) - copyValue
					count = count + 1
				end
			end
			if count > 0 then
				lift = sum / count
			end
		end

		-- grid cells that can be touched by the disc (bounding box, clamped to the grid)
		local firstCellX = math.max(0, floor((patch.qx - reach) / cellSize - offset))
		local lastCellX = math.min(cellsX - 1, math.ceil((patch.qx + reach) / cellSize - offset))
		local firstCellZ = math.max(0, floor((patch.qz - reach) / cellSize - offset))
		local lastCellZ = math.min(cellsZ - 1, math.ceil((patch.qz + reach) / cellSize - offset))
		for cellZ = firstCellZ, lastCellZ do
			for cellX = firstCellX, lastCellX do
				local outX = (cellX + offset) * cellSize
				local outZ = (cellZ + offset) * cellSize
				local weight = Patches.weight(patch, outX, outZ)
				if weight > 0 then
					local deltaX = outX - patch.qx
					local deltaZ = outZ - patch.qz
					local value = sample(
						base, cellsX, cellsZ, cellSize, offset,
						patch.mx + patch.a * deltaX + patch.b * deltaZ,
						patch.mz + patch.c * deltaX + patch.d * deltaZ
					) + lift
					local gridIndex = cellZ * cellsX + cellX + 1
					outGrid[gridIndex] = outGrid[gridIndex] * (1 - weight) + value * weight
				end
			end
		end
	end
end


--------------------------------------------------------------------------------------------------------------------
-- Serialization
--------------------------------------------------------------------------------------------------------------------

-- Text form of protected points for a rules param: "x,z,r,blend;..." with fixed precision so both sides read
-- identical numbers.
--   points: { { x, z, radius, blend }, ... }
function Patches.serialize(points)
	local parts = {}
	for i, point in ipairs(points) do
		parts[i] = string.format("%.2f,%.2f,%.1f,%.1f", point[1], point[2], point[3], point[4])
	end
	return table.concat(parts, ";")
end


-- Inverse of Patches.serialize. text may be nil. Returns { { x, z, radius, blend }, ... } (empty when nothing parses).
function Patches.parse(text)
	local points = {}
	if text then
		for x, z, radius, blend in text:gmatch("(%-?[%d%.]+),(%-?[%d%.]+),([%d%.]+),([%d%.]+)") do
			points[#points + 1] = { tonumber(x), tonumber(z), tonumber(radius), tonumber(blend) }
		end
	end
	return points
end


-- A patch is a single affine node for the shader's walker (kind 8, see shader.lua). Returns the 400-entry program
-- array: [1] = kind, [5..8] = qx, qz, mx, mz, [9..12] = a, b, c, d.
function Patches.program(patch)
	local program = {}
	for i = 1, 400 do
		program[i] = 0
	end
	program[1] = 8
	program[5] = patch.qx
	program[6] = patch.qz
	program[7] = patch.mx
	program[8] = patch.mz
	program[9] = patch.a
	program[10] = patch.b
	program[11] = patch.c
	program[12] = patch.d
	return program
end

return Patches
