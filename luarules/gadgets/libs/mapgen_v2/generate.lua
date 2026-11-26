-- Seed -> transform descriptor list. Pure: same seed, map size and options give the same list everywhere.
--
-- A "descriptor" is a table describing one transform step (reflect, rotate, nfold, tile, wallpaper, warp, zoom or
-- select). The list is evaluated first-to-last on each output position; Transform.new turns it into a sampler.
-- Coordinates are in elmos, with (0, 0) at the map's top-left corner.

local Prng = VFS.Include("luarules/gadgets/libs/mapgen_v2/prng.lua")
local Transform = VFS.Include("luarules/gadgets/libs/mapgen_v2/transform.lua")

local pi = math.pi
local min = math.min
local abs = math.abs

local Generate = {}

-- ===========================================================================================================
-- Quality gate
-- ===========================================================================================================

-- Quality gate for a candidate chain, on geometry alone (so synced and unsynced agree and it needs no map data):
--   coverage   share of the base map that the result actually shows; a chain that shows only a sliver of it (a small
--              wallpaper triangle, a narrow wedge) repeats that sliver and often contains no metal at all
--   border     how much more often the outer 7% strip of the base map (water, cliffs) is used than its area warrants
local MIN_COVERAGE, MAX_BORDER = 0.08, 1.7

-- Tests a candidate chain by sampling the output map on a regular grid and looking at where each sample comes from.
-- Params: descriptors (list of step descriptors), mapWidth / mapHeight (elmos).
-- Returns: ok (true if coverage and border usage are acceptable; false if the chain cannot even be built),
--          coverage (share of source-map cells shown, 0 when the chain cannot be built).
local function usable(descriptors, mapWidth, mapHeight)
	local built, transform = pcall(Transform.new, descriptors, mapWidth, mapHeight)
	if not built then
		return false, 0
	end

	local COVERAGE_GRID = 24 -- the source map is divided into 24 x 24 cells; coverage = share of cells shown
	local SAMPLES_PER_SIDE = 40 -- output positions probed: 40 x 40
	local BORDER_FRACTION = 0.07 -- width of the outer strip of the source map, as a share of its size
	local seenCells, cellCount, borderWeight = {}, 0, 0
	for j = 0, SAMPLES_PER_SIDE - 1 do
		for i = 0, SAMPLES_PER_SIDE - 1 do
			-- one output position (cell centre) maps back to tapCount source positions ("taps"), each with a weight
			-- (several taps appear where the chain cross-fades between alternatives)
			local tapCount, srcXs, srcZs, tapWeights =
				transform:taps((i + 0.5) / SAMPLES_PER_SIDE * mapWidth, (j + 0.5) / SAMPLES_PER_SIDE * mapHeight)
			for t = 1, tapCount do
				-- source position as a fraction of the map size, in [0, 1]
				local srcU, srcV = srcXs[t] / mapWidth, srcZs[t] / mapHeight
				-- taps below 0.3 weight are faint blend tails and do not count as "showing" the cell
				if tapWeights[t] > 0.3 then
					local cellKey = math.floor(srcU * COVERAGE_GRID) * COVERAGE_GRID
						+ math.floor(srcV * COVERAGE_GRID)
					if not seenCells[cellKey] then
						seenCells[cellKey] = true
						cellCount = cellCount + 1
					end
				end
				if
					srcU < BORDER_FRACTION
					or srcU > 1 - BORDER_FRACTION
					or srcV < BORDER_FRACTION
					or srcV > 1 - BORDER_FRACTION
				then
					borderWeight = borderWeight + tapWeights[t]
				end
			end
		end
	end

	local coverage = cellCount / (COVERAGE_GRID * COVERAGE_GRID)
	-- average border weight per sample, divided by the strip's share of the area (1 - inner square area):
	-- 1.0 means the border is used exactly as often as its size warrants
	local borderRatio = borderWeight / (SAMPLES_PER_SIDE * SAMPLES_PER_SIDE)
		/ (1 - (1 - 2 * BORDER_FRACTION) ^ 2)
	return coverage >= MIN_COVERAGE and borderRatio <= MAX_BORDER, coverage
end

-- ===========================================================================================================
-- Kinds and shared helpers
-- ===========================================================================================================

-- { kind, relative weight } pairs; the weight is how likely the kind is to be drawn for a chain step.
-- Every kind has a matching entry in the `makers` table below.
local kindWeights = {
	{ "reflect", 5 },
	{ "rotate", 3 },
	{ "nfold", 2 },
	{ "tile", 1.5 },
	{ "wallpaper", 1.2 },
	{ "warp", 2 },
	{ "zoom", 1 },
	{ "select", 1.5 },
}

-- Draws a random infinite line near the map centre, used as the axis of reflections, rotations and select masks.
-- Params: rng, mapWidth, mapHeight, bandWidth (blend width across the line, elmos).
-- Returns: table { px, pz (point on the line), source (+1 / -1: which side is the source), band, angle (radians) }.
local function randomLine(rng, mapWidth, mapHeight, bandWidth)
	local line = {
		-- anchor point: up to 12% of the map size away from the centre
		px = mapWidth * 0.5 + rng:range(-0.12, 0.12) * mapWidth,
		pz = mapHeight * 0.5 + rng:range(-0.12, 0.12) * mapHeight,
		source = rng:chance(0.5) and 1 or -1,
		band = bandWidth,
	}
	if rng:chance(0.6) then
		-- mostly axis-aligned or diagonal lines: 0, 90, 45 and 135 degrees
		line.angle = rng:pick({ 0, pi / 2, pi / 4, 3 * pi / 4 })
	else
		line.angle = rng:range(0, pi)
	end
	return line
end

-- Descriptor builders, keyed by kind. Each is called as maker(rng, mapWidth, mapHeight, bandWidth, allowed)
-- (extra arguments are ignored by the makers that do not need them) and returns one descriptor.
local makers = {}

-- Params: angle (radians).
-- Returns: unit vector (cos, sin) pointing in that direction.
local function unitVec(angle)
	return math.cos(angle), math.sin(angle)
end

-- Params: kind (string), line (table, e.g. from randomLine).
-- Returns: a new descriptor { kind = kind } with every field of `line` copied into it.
local function copyLine(kind, line)
	local desc = { kind = kind }
	for key, value in pairs(line) do
		desc[key] = value
	end
	return desc
end

-- ===========================================================================================================
-- Descriptor makers (one per kind)
-- ===========================================================================================================

-- Mirror across a line, sometimes with a wavy (sinusoidal) axis.
makers.reflect = function(rng, mapWidth, mapHeight, bandWidth)
	local desc = copyLine("reflect", randomLine(rng, mapWidth, mapHeight, bandWidth))
	if rng:chance(0.25) then
		-- long wavelength; amplitude capped so the line's slope (about 2.5 * amp * freq) stays under ~15%
		local wavelength = rng:range(0.3, 0.7) * min(mapWidth, mapHeight)
		local freq = 2 * pi / wavelength
		desc.wave = {
			amp = rng:range(0.3, 1) * min(0.01 * min(mapWidth, mapHeight), 0.15 / (2.5 * freq)),
			freq = freq,
			phase = rng:range(0, 100),
		}
	end
	return desc
end

-- 180 degree rotation about a point on (or near) a random line.
makers.rotate = function(rng, mapWidth, mapHeight, bandWidth)
	local desc = copyLine("rotate", randomLine(rng, mapWidth, mapHeight, bandWidth))
	-- slide the rotation centre along the line, up to 20% of the map width either way
	local slide = rng:range(-0.2, 0.2) * mapWidth
	desc.cx = desc.px + slide * math.cos(desc.angle)
	desc.cz = desc.pz + slide * math.sin(desc.angle)
	desc.rot = pi
	return desc
end

-- N-fold kaleidoscope around a point near the map centre, optionally mirrored, swirled, wedged or ringed.
makers.nfold = function(rng, mapWidth, mapHeight, bandWidth)
	local foldCount = rng:pick({ 3, 4, 5, 6, 8 })
	local desc = {
		kind = "nfold",
		n = foldCount,
		-- mirrored (dihedral) folds only make sense for an even count
		mirror = (foldCount % 2 == 0) and rng:chance(0.5),
		cx = mapWidth * 0.5 + rng:range(-0.1, 0.1) * mapWidth,
		cz = mapHeight * 0.5 + rng:range(-0.1, 0.1) * mapHeight,
		phase = rng:range(0, 2 * pi),
		band = bandWidth,
	}
	-- extras: swirl (angle per elmo of radius), narrow source wedge, concentric echoes of the centre disc.
	-- Twist is limited so the swirl turns by at most ~0.5 rad out to half the map, the wedge to a mild squeeze.
	if rng:chance(0.35) then
		desc.twist = (rng:chance(0.5) and 1 or -1) * rng:range(0.15, 0.5) / (0.5 * min(mapWidth, mapHeight))
	end
	if rng:chance(0.3) then
		desc.wedge = rng:range(0.7, 0.95)
	end
	if rng:chance(0.2) then
		desc.ring = rng:range(0.2, 0.4) * min(mapWidth, mapHeight)
		desc.ringMirror = rng:chance(0.5)
	end
	return desc
end

-- Tiling of the map with (mirrored or repeated) rectangular cells, possibly rotated and cross-faded.
makers.tile = function(rng, mapWidth, mapHeight)
	local tileWidth = rng:range(0.25, 0.6) * mapWidth
	local desc = {
		kind = "tile",
		mode = rng:pick({ "mirror", "repeat" }),
		w = tileWidth,
		h = tileWidth * rng:range(0.7, 1.3), -- height: 70% to 130% of the width
		angle = rng:chance(0.7) and 0 or rng:range(0, pi),
		ox = rng:range(-0.2, 0.2) * mapWidth,
		oz = rng:range(-0.2, 0.2) * mapHeight,
	}
	if rng:chance(0.5) then
		desc.band = rng:range(150, 400) -- cross-fade across cell borders
	end
	return desc
end

-- Mirror-line kaleidoscope lattices: the fundamental triangle is the only part of the map that is shown (repeated), so
-- it is made large and kept completely inside the map, away from the border strip.
-- Vertices are in unit size: p4m is a 45-45-90 triangle, p3m1 an equilateral one (0.866... = sqrt(3) / 2), p6m a
-- 30-60-90 one (0.433... = sqrt(3) / 4).
local WALL_VERTS = {
	p4m = { { 0, 0 }, { 1, 0 }, { 1, 1 } },
	p3m1 = { { 0, 0 }, { 1, 0 }, { 0.5, 0.8660254037844386 } },
	p6m = { { 0, 0 }, { 1, 0 }, { 0.75, 0.4330127018922193 } },
}

makers.wallpaper = function(rng, mapWidth, mapHeight)
	local group = rng:pick({ "p4m", "p3m1", "p6m" })
	local angle = rng:range(0, 2 * pi)
	local size = rng:range(0.35, 0.6) * min(mapWidth, mapHeight)
	local cosAngle, sinAngle = math.cos(angle), math.sin(angle)
	local margin = 0.05 -- the triangle must stay at least 5% of the map size away from every edge

	-- Shrink the triangle (by 10% per round, at most 12 times) until some offset places it fully inside the margin.
	-- The offset range for each axis is [offsetMin, offsetMax]; the triangle fits when both ranges are non-empty.
	local offsetMin, offsetMax
	for _ = 1, 12 do
		-- bounding box of the rotated, scaled triangle
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, vertex in ipairs(WALL_VERTS[group]) do
			local vertX = (vertex[1] * cosAngle - vertex[2] * sinAngle) * size
			local vertZ = (vertex[1] * sinAngle + vertex[2] * cosAngle) * size
			minX = min(minX, vertX)
			maxX = math.max(maxX, vertX)
			minZ = min(minZ, vertZ)
			maxZ = math.max(maxZ, vertZ)
		end
		offsetMin = { margin * mapWidth - minX, margin * mapHeight - minZ }
		offsetMax = { (1 - margin) * mapWidth - maxX, (1 - margin) * mapHeight - maxZ }
		if offsetMin[1] <= offsetMax[1] and offsetMin[2] <= offsetMax[2] then
			break
		end
		size = size * 0.9
	end

	-- pick a random offset in the valid range (or the middle of the inverted range if it never fitted)
	local offsetX = offsetMin[1] <= offsetMax[1] and rng:range(offsetMin[1], offsetMax[1])
		or (offsetMin[1] + offsetMax[1]) / 2
	local offsetZ = offsetMin[2] <= offsetMax[2] and rng:range(offsetMin[2], offsetMax[2])
		or (offsetMin[2] + offsetMax[2]) / 2
	return { kind = "wallpaper", group = group, size = size, ox = offsetX, oz = offsetZ, angle = angle }
end

-- Sinusoidal distortion of the terrain.
makers.warp = function(rng, mapWidth, mapHeight)
	-- Distortion budget: a warp stretches / squeezes the terrain by up to 2.5 * amp * freq (its slope) and shifts it by
	-- up to amp. Both stay small so no detail is lost: at most about 12% stretch and 48 elmos of shift.
	local freq = 2 * pi / (rng:range(0.3, 0.8) * min(mapWidth, mapHeight))
	local maxAmp = min(0.12 / (2.5 * freq), 48)
	return {
		kind = "warp",
		amp = rng:range(0.3, 1) * maxAmp,
		freq = freq,
		p1 = rng:range(0, 100), -- random phases of the two axes' waves
		p2 = rng:range(0, 100),
	}
end

-- Enlarges the map around the centre and looks at a random part of it, optionally rotated.
makers.zoom = function(rng, mapWidth, mapHeight)
	local scale = rng:range(1.1, 1.3) -- stronger zooms blur the terrain: it is being enlarged
	return {
		kind = "zoom",
		scale = scale,
		angle = rng:chance(0.7) and 0 or rng:range(-pi / 8, pi / 8),
		cx = mapWidth * 0.5,
		cz = mapHeight * 0.5,
		-- target point: the source position shown at the centre; the visible window of size map / scale stays inside
		tx = rng:range(mapWidth / (2 * scale), mapWidth - mapWidth / (2 * scale)),
		tz = rng:range(mapHeight / (2 * scale), mapHeight - mapHeight / (2 * scale)),
	}
end

-- Draws a non-select step (a "simple" one) among the allowed kinds.
-- Params: rng, mapWidth, mapHeight, bandWidth, allowed (set kind -> true).
-- Returns: a descriptor, or nil when no simple kind is allowed.
local function randomSimple(rng, mapWidth, mapHeight, bandWidth, allowed)
	local kinds = {}
	for _, entry in ipairs(kindWeights) do
		if entry[1] ~= "select" and allowed[entry[1]] then
			kinds[#kinds + 1] = entry
		end
	end
	if #kinds == 0 then
		return nil
	end
	local kind = rng:weighted(kinds)
	return makers[kind](rng, mapWidth, mapHeight, bandWidth)
end

-- A step that applies one chain on one side of a mask and another chain on the other side (cross-faded over the mask's
-- band). The mask is a half-plane bounded by a random line, or a disc.
-- Params: rng, mapWidth, mapHeight, bandWidth, allowed (set kind -> true).
-- Returns: descriptor { kind = "select", mask, a = {steps...}, b = {steps...} }; a or b may be empty (identity).
makers.select = function(rng, mapWidth, mapHeight, bandWidth, allowed)
	local mask
	local isLine = rng:chance(0.6)
	local line
	if isLine then
		line = randomLine(rng, mapWidth, mapHeight, bandWidth * 2)
		mask = copyLine("halfplane", line)
		mask.sign = mask.source
	else
		mask = {
			kind = "disc",
			cx = mapWidth * 0.5 + rng:range(-0.15, 0.15) * mapWidth,
			cz = mapHeight * 0.5 + rng:range(-0.15, 0.15) * mapHeight,
			r = rng:range(0.2, 0.45) * min(mapWidth, mapHeight), -- disc radius
			band = bandWidth * 2,
		}
	end

	-- twin: a different kaleidoscope on each side of the mask
	if allowed.nfold and rng:chance(0.3) then
		-- the two folds are drawn in this order (a, then b): the rng sequence depends on it
		local stepA = makers.nfold(rng, mapWidth, mapHeight, bandWidth)
		local stepB = makers.nfold(rng, mapWidth, mapHeight, bandWidth)
		if isLine then
			-- tangent and normal of the mask line
			local tangentX, tangentZ = unitVec(line.angle)
			local normalX, normalZ = -tangentZ, tangentX
			local offset = 0.2 * min(mapWidth, mapHeight) -- how far from the line each centre sits
			-- Puts the fold centre of `desc` at `side` * offset from the line (side is +1 or -1), kept inside the map
			-- (within 10% of the edges).
			local function place(desc, side)
				desc.cx = math.max(0.1 * mapWidth, math.min(0.9 * mapWidth, line.px + side * offset * normalX))
				desc.cz = math.max(0.1 * mapHeight, math.min(0.9 * mapHeight, line.pz + side * offset * normalZ))
			end
			-- b is used where sign * distance < 0
			place(stepA, mask.sign)
			place(stepB, -mask.sign)
		else
			-- both folds share the disc's centre
			stepB.cx = mask.cx
			stepB.cz = mask.cz
		end
		return { kind = "select", mask = mask, a = { stepA }, b = { stepB } }
	end

	local listA, listB = {}, {}
	if rng:chance(0.75) then
		listA[1] = randomSimple(rng, mapWidth, mapHeight, bandWidth, allowed)
	end
	-- the second side is always tried when the first is empty, so a select never has two empty sides
	-- (unless no simple kind is allowed at all)
	if #listA == 0 or rng:chance(0.75) then
		listB[1] = randomSimple(rng, mapWidth, mapHeight, bandWidth, allowed)
	end
	return { kind = "select", mask = mask, a = listA, b = listB }
end

-- ===========================================================================================================
-- Closing symmetry
-- ===========================================================================================================

-- The chain is evaluated first-to-last on each output position (gather), so the step at index 1 is the
-- one that shapes the final terrain: making it an exact involution of the whole map guarantees
-- out(p) == out(S(p)) no matter what the remaining steps do. S is always centred on the map centre:
--   central   180 degree rotation about the centre, split by any line through it
--   vertical / horizontal   mirror across x = mapWidth/2 or z = mapHeight/2 (valid on any rectangle)
--   diagonal  mirror across a diagonal (square maps only: on a rectangle it does not map the map onto itself)
-- Params: rng, mapWidth, mapHeight, bandWidth (blend width across the seam, elmos).
-- Returns: the closing descriptor (tagged with d.closing = "central" / "vertical" / "horizontal" / "diagonal").
local function makeClosing(rng, mapWidth, mapHeight, bandWidth)
	-- { kind, weight }; the diagonal is only offered on (nearly) square maps
	local options = { { "central", 4 }, { "vertical", 3 }, { "horizontal", 3 } }
	if abs(mapWidth - mapHeight) < 1 then
		options[#options + 1] = { "diagonal", 2 }
	end
	local closingKind = rng:weighted(options)
	local desc = {
		px = mapWidth * 0.5,
		pz = mapHeight * 0.5,
		source = rng:chance(0.5) and 1 or -1,
		closing = closingKind,
	}
	if closingKind == "central" then
		desc.kind = "rotate"
		desc.rot = pi
		desc.cx = desc.px
		desc.cz = desc.pz
		desc.band = bandWidth
		desc.angle = rng:chance(0.6) and rng:pick({ 0, pi / 2 }) or rng:range(0, pi)
	else
		desc.kind = "reflect"
		-- A symmetric blend keeps the symmetry exact: out(p) = s * f(S p) + (1 - s) * f(p) with s(-d) = 1 - s(d),
		-- so out(S p) equals out(p). It rounds off the crease where the mirrored halves meet.
		desc.band = bandWidth
		if closingKind == "vertical" then
			desc.angle = pi / 2
		elseif closingKind == "horizontal" then
			desc.angle = 0
		else
			-- the two diagonals: 45 or 135 degrees
			desc.angle = rng:pick({ pi / 4, 3 * pi / 4 })
		end
	end
	return desc
end

-- ===========================================================================================================
-- Public entry point
-- ===========================================================================================================

-- Builds the descriptor list (the transform chain) for a seed.
-- Params: seed (integer), mapWidth / mapHeight (elmos),
--   opts (optional): layers (0 or nil = random 1..4 total steps, closing symmetry included),
--                    band (elmos), allowed (set of kinds for the non-closing steps; nil = all),
--                    attempt (re-roll counter, see below).
-- Returns: list of step descriptors; index 1 is always the closing symmetry.
function Generate.descriptors(seed, mapWidth, mapHeight, opts)
	opts = opts or {}
	-- attempt > 0 re-rolls the chain deterministically (the caller published the attempt that was accepted)
	local rng = Prng.new(seed, opts.attempt)
	-- seam blends scale with the map: a fixed 192 elmos is a hairline on a 12288 map
	local bandWidth = math.max(opts.band or 192, 0.03 * min(mapWidth, mapHeight))
	local allowed = opts.allowed
	if not allowed then
		allowed = {}
		for _, entry in ipairs(kindWeights) do
			allowed[entry[1]] = true
		end
	end

	-- weighted entries of the allowed kinds, in kindWeights order
	local pool = {}
	for _, entry in ipairs(kindWeights) do
		if allowed[entry[1]] then
			pool[#pool + 1] = entry
		end
	end

	local layerCount = (opts.layers and opts.layers > 0) and opts.layers or rng:int(1, 4)
	local descriptors = { makeClosing(rng, mapWidth, mapHeight, bandWidth) }

	-- a second wallpaper (or one after a blended tile) makes the pre-image search explode, so allow only one
	local function hasWallpaper(desc)
		if desc.kind == "wallpaper" then
			return true
		elseif desc.kind == "select" then
			return (desc.a and desc.a[1] and hasWallpaper(desc.a[1]))
				or (desc.b and desc.b[1] and hasWallpaper(desc.b[1]))
				or false
		end
		return false
	end
	-- the same allowed set / pool without wallpaper, used once a wallpaper is already in the chain
	local allowedNoWallpaper = {}
	for kind, isAllowed in pairs(allowed) do
		allowedNoWallpaper[kind] = isAllowed
	end
	allowedNoWallpaper.wallpaper = nil
	local poolNoWallpaper = {}
	for _, entry in ipairs(pool) do
		if entry[1] ~= "wallpaper" then
			poolNoWallpaper[#poolNoWallpaper + 1] = entry
		end
	end

	-- Append steps 2..layerCount. Each step is tried up to 8 times; the first candidate whose chain passes the quality
	-- gate wins, otherwise the candidate with the best coverage does.
	local seenWallpaper = false
	if #pool > 0 then
		for stepIndex = 2, layerCount do
			local bestDesc, bestCoverage
			for _ = 1, 8 do
				local desc
				if seenWallpaper and #poolNoWallpaper > 0 then
					desc = makers[rng:weighted(poolNoWallpaper)](
						rng, mapWidth, mapHeight, bandWidth, allowedNoWallpaper
					)
				else
					desc = makers[rng:weighted(pool)](rng, mapWidth, mapHeight, bandWidth, allowed)
				end

				-- the chain as it would be with this candidate as its last step
				local trialChain = {}
				for k = 1, stepIndex - 1 do
					trialChain[k] = descriptors[k]
				end
				trialChain[stepIndex] = desc

				local ok, coverage = usable(trialChain, mapWidth, mapHeight)
				if not bestDesc or coverage > bestCoverage then
					bestDesc, bestCoverage = desc, coverage
				end
				if ok then
					bestDesc = desc
					break
				end
			end
			if hasWallpaper(bestDesc) then
				seenWallpaper = true
			end
			descriptors[stepIndex] = bestDesc
		end
	end

	return descriptors
end

return Generate
