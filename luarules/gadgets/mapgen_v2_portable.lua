--------------------------------------------------------------------------------
-- MapGen v2 Portable
--
-- Applies one seeded composite transform (symmetry, kaleidoscope, tiling, warp...) to every layer of a map:
-- heightmap, metal, type map, grass, features, start boxes and (unsynced) textures.
-- The synced and unsynced halves each rebuild the same transform and cross-check it (see the two section overviews
-- below). The geometry lives in the libraries under luarules/gadgets/libs/mapgen_v2/; this file only drives them.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Gadget layer
--------------------------------------------------------------------------------

-- Gadgets a map ships to write its metal at load (e.g. Rosetta's map_lua_resource_spots.lua stamps the spots of
-- mapconfig/map_resource_spot_layout.lua with SetMetalAmount, a random map generator...) must run before the transform.
-- Otherwise they stamp the ORIGINAL positions on top of the transformed metal: mexes where the terrain no longer fits.
--
-- Scans the map's gadgets that mention SetMetalAmount and takes the highest "layer = N" they declare.
-- Returns: the gadget layer for this gadget (one above the highest such layer, or -100 if there is none).
local function layerAfterMapMetalGadgets()
	local layer = -100
	for _, path in ipairs(VFS.DirList("luarules/gadgets", "*.lua", VFS.MAP) or {}) do
		if not path:find("mapgen_v2", 1, true) then
			local text = VFS.LoadFile(path, VFS.MAP)
			if text and text:find("SetMetalAmount", 1, true) then
				layer = math.max(layer, (tonumber(text:match("layer%s*=%s*(%-?%d+)")) or 0) + 1)
			end
		end
	end
	return layer
end

-- Standard gadget metadata; only the layer is computed (see layerAfterMapMetalGadgets).
function gadget:GetInfo()
	return {
		name = "MapGen v2 Portable",
		desc = "Seeded composite transform (symmetry, kaleidoscope, tiling, warp...) applied to every layer of any map",
		author = "Doo",
		date = "2026",
		layer = layerAfterMapMetalGadgets(),
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- Guard, libraries and shared constants
--------------------------------------------------------------------------------

-- A map that ships its own copy of this gadget (mapgen_v2.lua) keeps priority; the two must not both run.
if VFS.FileExists("luarules/gadgets/mapgen_v2.lua", VFS.MAP) then
	Spring.Echo("[MapGen v2 Portable] map ships its own MapGen v2, portable copy stays off")
	return false
end

local LIB = "luarules/gadgets/libs/mapgen_v2/"
local Transform = VFS.Include(LIB .. "transform.lua")
local Generate = VFS.Include(LIB .. "generate.lua")
local Field = VFS.Include(LIB .. "field.lua")
local Startboxes = VFS.Include(LIB .. "startboxes.lua")
local Patches = VFS.Include(LIB .. "patches.lua")
local Relax = VFS.Include(LIB .. "relax.lua")
-- the texture shader only exists on the unsynced side
local Textures = (not gadgetHandler:IsSyncedCode()) and VFS.Include(LIB .. "textures.lua") or nil

local floor, sin, cos, sqrt, abs, pi = math.floor, math.sin, math.cos, math.sqrt, math.abs, math.pi
local atan2 = math.atan2 or math.atan

-- Game rules params: how the synced side publishes what it used, so the unsynced side and the widgets can follow
local PARAM_CFG = "mapgen_cfg" -- everything the unsynced side needs, as one string: seed;layers;band;W;H;attempt
local PARAM_SIG = "mapgen_sig"
local PARAM_PROBE = "mapgen_probe"
local PARAM_DESC = "mapgen_desc"
local PARAM_BOXES = "mapgen_startboxes" -- new start box polygons, applied by the LuaUI widget
local PARAM_PROTECT = "mapgen_protect" -- protected points (metal spots, geo vents) as "x,z,r,blend;..."
local PARAM_PATCHES = "mapgen_patches" -- number of patches synced derived from them, checked by unsynced
local PARAM_GRASS = "mapgen_grass_engine" -- 1 when the engine's own grass map was transformed (the widget then skips)
local PARAM_ROCK = "mapgen_rock" -- coarse nodes the terrain pass reshaped and left steep: drawn as rock (see relax.lua)

-- Chain selection (see the loop in gadget:Initialize)
local MAX_ATTEMPTS = 12 -- chain re-rolls when copies of protected points would overlap or a seam is too steep

-- Protected points must stay whole in every copy (see patches.lua): solid radius and blended rim, in elmos.
-- A mex takes the metal within Game.extractorRadius of its position; one extra metal cell covers the grid rounding
-- (the resource spot finder pads it the same way). Read at load, not hard-coded, so a game that changes it is followed.
-- The rim is wide so that the terrain around a redrawn copy can climb to its surroundings on a gentle slope.
local SPOT_BLEND = 96
local GEO_RADIUS, GEO_BLEND = 96, 64
-- A chain whose seams would force more than this many percent of the map to be reshaped (see relax.lua) is re-rolled
local SEAM_OK = 1.0

--------------------------------------------------------------------------------
-- Shared helpers (used by both the synced and the unsynced side)
--------------------------------------------------------------------------------

-- Options come from the game's modoptions (mg_*), falling back to the map's own options, then defaults.
-- Without any option set the transform is ON with a random seed.
-- Returns: { enabled, seed, layers, band, metalMode, textures }
local function readOptions()
	local modOptions = (Spring.GetModOptions and Spring.GetModOptions()) or {}
	local mapOptions = (Spring.GetMapOptions and Spring.GetMapOptions()) or {}

	-- the mod option wins; an unset or empty one falls back to the map option (named like the mod key unless given)
	local function get(modKey, mapKey)
		local value = modOptions[modKey]
		if value == nil or value == "" then
			value = mapOptions[mapKey or modKey]
		end
		return value
	end

	-- numeric option, or defaultValue when it is missing or not a number
	local function num(modKey, mapKey, defaultValue)
		local value = tonumber(get(modKey, mapKey))
		if value == nil then
			return defaultValue
		end
		return value
	end

	return {
		enabled = (get("mg_mode", "mapgen_mode") or "on") ~= "off",
		seed = floor(num("mg_seed", "seed", 0)),
		layers = floor(num("mg_layers", "mg_layers", 0)),
		band = num("mg_band", "mg_band", 192),
		metalMode = get("mg_metal") or "spots_normalize",
		textures = (get("mg_textures") or "on") ~= "off",
	}
end

-- A few fixed points whose hard mapping is compared between synced and unsynced to catch divergence.
-- Params: transform = the Transform to test.
-- Returns: the mapped source points, rounded to 4-elmo steps, as one "x,z;x,z;..." string.
local function probe(transform)
	local mapWidth, mapHeight = Game.mapSizeX, Game.mapSizeZ
	local pointStrings = {}
	for i, fraction in ipairs({
		{ 0.13, 0.29 },
		{ 0.41, 0.77 },
		{ 0.62, 0.18 },
		{ 0.87, 0.55 },
		{ 0.5, 0.5 },
		{ 0.23, 0.91 },
	}) do
		local srcX, srcZ = transform:map(fraction[1] * mapWidth, fraction[2] * mapHeight)
		pointStrings[i] = floor(srcX / 4 + 0.5) .. "," .. floor(srcZ / 4 + 0.5)
	end
	return table.concat(pointStrings, ";")
end

--------------------------------------------------------------------------------
-- SYNCED
--
-- Load sequence (everything happens once, in gadget:Initialize, before the first game frame):
--   1. seed           from the mg_seed option, or random when it is 0
--   2. chain          Generate.descriptors() is re-rolled (attempt 0..MAX_ATTEMPTS) until the resulting Transform keeps
--                     protected points (metal spots, geo vents) whole, shows every spot and its metal and has gentle
--                     seams; the best-scoring attempt is kept. The result is published as game rules params so the
--                     unsynced side rebuilds the very same transform.
--   3. layers         heightmap, metal, type map and grass are remapped through the transform
--   4. features       existing features are moved/copied/removed; features created later by other gadgets are caught
--                     in FeatureCreated, and anything that slipped through is swept up at game start / first frame
--   5. start boxes    start boxes and start positions follow the transform in mirror pairs
--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
	local GetGroundHeight = Spring.GetGroundHeight
	local SetHeightMap = Spring.SetHeightMap
	local GetMetalAmount = Spring.GetMetalAmount
	local SetMetalAmount = Spring.SetMetalAmount

	local mapWidth, mapHeight = Game.mapSizeX, Game.mapSizeZ
	local transform -- the accepted Transform; nil until Initialize has built it

	local setupPhase = true -- features created by other gadgets before the game starts are transformed too
	local isPlacingFeature = false -- true while we create a feature ourselves, so FeatureCreated ignores it
	local handledFeatureIds = {} -- feature ids already transformed (or created by us)
	local stats = { hook = 0, existing = 0, late = 0, kept = 0, retired = 0, created = 0 }
	local sweepDone = false

	----------------------------------------------------------------------------
	-- Layers: heightmap, metal, type map, grass
	----------------------------------------------------------------------------

	-- Remaps the heightmap through the transform, redraws cut copies of protected points whole, relaxes the slopes the
	-- seams created, writes the result into the engine and logs how much of it was really applied.
	-- Params: patches = protected-point copies a seam would cut (from Patches.build),
	--         protectedPoints = the protected points (metal spots, geo vents).
	local function transformHeightmap(patches, protectedPoints)
		local squareSize = Game.squareSize
		local cellsX, cellsZ = floor(mapWidth / squareSize) + 1, floor(mapHeight / squareSize) + 1
		local baseHeights = {}
		for cellZ = 0, cellsZ - 1 do
			local rowStart = cellZ * cellsX
			for cellX = 0, cellsX - 1 do
				baseHeights[rowStart + cellX + 1] = GetGroundHeight(cellX * squareSize, cellZ * squareSize)
			end
		end
		local outHeights = Field.remap(transform, baseHeights, cellsX, cellsZ, squareSize, false, "bilinear")
		-- copies of protected points that a seam would cut are redrawn whole, lifted to meet their surroundings
		if #patches > 0 then
			Patches.applyToGrid(
				patches, outHeights, baseHeights, cellsX, cellsZ, squareSize, false, Field.bilinear, true
			)
		end
		-- slopes the transform made (a cross-fade between two unrelated heights) are spread over a ramp
		local relaxResult = Relax.run(
			transform, baseHeights, outHeights, cellsX, cellsZ, squareSize, Relax.discs(transform, protectedPoints)
		)
		if #patches > 0 or (relaxResult.flagged or 0) > 0 then
			Field.symmetrize(transform, outHeights, cellsX, cellsZ, squareSize, false)
		end
		if relaxResult.skipped then
			Spring.Echo("[MapGen v2] seams: grid not suitable for slope relaxation, skipped")
		else
			Spring.Echo(string.format("[MapGen v2] seams: %d coarse nodes steeper than the source allows (cap %.2f), %.2f%% of the map reshaped (max %.0f elmos), %d edges still too steep",
				relaxResult.flagged, relaxResult.cap, relaxResult.rewritten * 100, relaxResult.maxShift,
				relaxResult.residual))
		end
		Spring.SetGameRulesParam(PARAM_ROCK, Relax.serializeRock(relaxResult.rock), { public = true })
		Spring.SetHeightMapFunc(function()
			for cellZ = 0, cellsZ - 1 do
				local rowStart = cellZ * cellsX
				for cellX = 0, cellsX - 1 do
					SetHeightMap(cellX * squareSize, cellZ * squareSize, outHeights[rowStart + cellX + 1])
				end
			end
		end)

		-- read back what the engine now holds, so the log says whether the terrain really changed
		local changed, applied, samples = 0, 0, 0
		for cellZ = 0, cellsZ - 1, 7 do
			for cellX = 0, cellsX - 1, 7 do
				local index = cellZ * cellsX + cellX + 1
				samples = samples + 1
				if abs(outHeights[index] - baseHeights[index]) > 0.5 then
					changed = changed + 1
				end
				if abs(GetGroundHeight(cellX * squareSize, cellZ * squareSize) - outHeights[index]) < 0.5 then
					applied = applied + 1
				end
			end
		end
		Spring.Echo(string.format("[MapGen v2] heightmap: %d of %d samples differ from the original, engine holds the new value at %d of %d", changed, samples, applied, samples))
	end

	-- The metal map as the game would start with it. Maps that list their spots in mapconfig/map_metal_layout.lua get
	-- them from a gadget that runs after this one; they are laid out here the same way so they are transformed too
	-- (and the other gadget then finds a metal map and leaves it alone).
	-- Returns: { cellsX, cellsZ, cellSize, amounts (flat row-major array, 1-based), total }
	local function readMetalGrid()
		local cellsX, cellsZ = Spring.GetMetalMapSize()
		local cellSize = Game.metalMapSquareSize or 16
		local amounts, total = {}, 0
		for cellZ = 0, cellsZ - 1 do
			local rowStart = cellZ * cellsX
			for cellX = 0, cellsX - 1 do
				local amount = GetMetalAmount(cellX, cellZ)
				amounts[rowStart + cellX + 1] = amount
				total = total + amount
			end
		end
		local layoutFile = "mapconfig/map_metal_layout.lua"
		if total == 0 and Spring.GetGameFrame() == 0 and VFS.FileExists(layoutFile) then
			local ok, layout = pcall(VFS.Include, layoutFile)
			if ok and type(layout) == "table" and layout.spots then
				local factor = 0.43 * 9 / 21
				for _, spot in ipairs(layout.spots) do
					if spot.x and spot.z and spot.metal then
						local spotCellX, spotCellZ = floor(spot.x / cellSize), floor(spot.z / cellSize)
						if spotCellX >= 0 and spotCellZ >= 0 then
							-- a 5x5 block of cells without its four corners
							for offsetX = -2, 2 do
								for offsetZ = -2, 2 do
									local neighborX, neighborZ = spotCellX + offsetX, spotCellZ + offsetZ
									if not (abs(offsetX) == 2 and abs(offsetZ) == 2)
										and neighborX > 0 and neighborX < cellsX
										and neighborZ > 0 and neighborZ < cellsZ then
										amounts[neighborZ * cellsX + neighborX + 1] =
											math.min(255, spot.metal * factor * 255)
									end
								end
							end
						end
					end
				end
				total = 0
				for i = 1, cellsX * cellsZ do
					total = total + amounts[i]
				end
			end
		end
		return { cellsX = cellsX, cellsZ = cellsZ, cellSize = cellSize, amounts = amounts, total = total }
	end

	-- Points whose copies must stay whole: metal spots (spots mode) and geo vents. Rounded the way they are published,
	-- so synced and unsynced compute patches from identical numbers.
	-- Params: mode = metal mode (unused), spots = spots found in the metal grid (cell coordinates mx, mz),
	--         cellSize = metal cell size in elmos.
	-- Returns: the parsed list of { x, z, radius, blend } (spots first), its serialized text and the spot count.
	local function collectProtected(mode, spots, cellSize)
		local points = {}
		for i, spot in ipairs(spots) do
			points[i] = {
				(spot.mx + 0.5) * cellSize,
				(spot.mz + 0.5) * cellSize,
				(Game.extractorRadius or 90) + cellSize,
				SPOT_BLEND,
			}
		end
		local featureIds = Spring.GetAllFeatures()
		for i = 1, #featureIds do
			local featureDefId = Spring.GetFeatureDefID(featureIds[i])
			local featureDef = featureDefId and FeatureDefs[featureDefId]
			if featureDef and featureDef.geoThermal then
				local x, _, z = Spring.GetFeaturePosition(featureIds[i])
				if x then
					points[#points + 1] = { x, z, GEO_RADIUS, GEO_BLEND }
				end
			end
		end
		-- geo vents listed in the map's feature set are created by a feature placer after this runs
		local setPath = "mapconfig/featureplacer/set.lua"
		if VFS.FileExists(setPath) then
			local ok, featureSet = pcall(VFS.Include, setPath)
			if ok and type(featureSet) == "table" then
				for _, placement in pairs(featureSet.objectlist or {}) do
					local featureDef = placement.name and FeatureDefNames and FeatureDefNames[placement.name]
					local x, z = tonumber(placement.x), tonumber(placement.z)
					if featureDef and featureDef.geoThermal and x and z then
						points[#points + 1] = { x, z, GEO_RADIUS, GEO_BLEND }
					end
				end
			end
		end
		-- the same vent can come from a live feature and from the feature set (spots are never merged)
		local uniquePoints, seenKeys = {}, {}
		for i, point in ipairs(points) do
			local key = i <= #spots and i or (floor(point[1] / 2) .. ":" .. floor(point[2] / 2))
			if not seenKeys[key] then
				seenKeys[key] = true
				uniquePoints[#uniquePoints + 1] = point
			end
		end
		points = uniquePoints
		local text = Patches.serialize(points)
		return Patches.parse(text), text, #spots
	end

	-- Writes the transformed metal map. Modes:
	-- "spots": spot-sized clusters are stamped unchanged wherever the transform shows them;
	-- "spots_normalize" (default): the same, then every cell is scaled by one factor so the map keeps its original
	-- total;
	-- "normalize": resampled grid scaled back to the original total; "raw": resampled grid as is
	-- Params: mode, metalGrid = result of readMetalGrid (+ spots, field), protectedPoints = collectProtected's list,
	--         spotCount = how many of the first protectedPoints are metal spots, patches = cut copies (for the log).
	local function transformMetal(mode, metalGrid, protectedPoints, spotCount, patches)
		local cellsX, cellsZ = metalGrid.cellsX, metalGrid.cellsZ
		local cellSize, baseAmounts = metalGrid.cellSize, metalGrid.amounts
		local outAmounts, scale = nil, 1
		if mode == "spots" or mode == "spots_normalize" then
			local spotPoints = {}
			for i = 1, spotCount do
				spotPoints[i] = protectedPoints[i]
			end
			local found, placed
			outAmounts, found, placed = Field.remapSpots(transform, baseAmounts, cellsX, cellsZ, cellSize, {
				spots = metalGrid.spots, field = metalGrid.field, images = Field.imagesOf(transform, spotPoints),
			})
			Spring.Echo(string.format("[MapGen v2] metal: %d spots in the map, %d shown after the transform (%d redrawn whole where a seam crosses them)", found, placed, #patches))
			if mode == "spots_normalize" then
				local before = 0
				for i = 1, cellsX * cellsZ do
					before = before + outAmounts[i]
				end
				local sum, capped
				outAmounts, scale, sum, capped = Field.scaleToTotal(outAmounts, metalGrid.total, 255)
				Spring.Echo(string.format("[MapGen v2] metal normalized: total %d -> %d (original %d), factor %.3f, %d cells at the cap%s",
					before, sum, metalGrid.total, scale, capped, sum < metalGrid.total * 0.995 and " | WARNING: target not reachable without flattening the spots" or ""))
				-- already applied by scaleToTotal
				scale = 1
			end
		else
			outAmounts = Field.remap(transform, baseAmounts, cellsX, cellsZ, cellSize, true, "nearest")
			if mode == "normalize" then
				local newTotal = 0
				for i = 1, cellsX * cellsZ do
					newTotal = newTotal + outAmounts[i]
				end
				scale = newTotal > 0 and (metalGrid.total / newTotal) or 1
			end
		end
		for cellZ = 0, cellsZ - 1 do
			local rowStart = cellZ * cellsX
			for cellX = 0, cellsX - 1 do
				SetMetalAmount(cellX, cellZ, outAmounts[rowStart + cellX + 1] * scale)
			end
		end
	end

	-- Type map: one byte per 16x16 elmo cell, discrete, so it follows the dominant branch of the transform.
	-- Returns: number of cells changed, number of cells.
	local function transformTypemap()
		local cellSize = 2 * Game.squareSize
		local cellsX, cellsZ = floor(mapWidth / cellSize), floor(mapHeight / cellSize)
		local baseTypes = {}
		for cellZ = 0, cellsZ - 1 do
			local rowStart = cellZ * cellsX
			for cellX = 0, cellsX - 1 do
				local _, _, typeIndex = Spring.GetGroundInfo((cellX + 0.5) * cellSize, (cellZ + 0.5) * cellSize)
				baseTypes[rowStart + cellX + 1] = typeIndex
			end
		end
		local outTypes = Field.remapHard(transform, baseTypes, cellsX, cellsZ, cellSize, true)
		local changed = 0
		for cellZ = 0, cellsZ - 1 do
			local rowStart = cellZ * cellsX
			for cellX = 0, cellsX - 1 do
				local index = rowStart + cellX + 1
				if outTypes[index] ~= baseTypes[index] then
					Spring.SetMapSquareTerrainType((cellX + 0.5) * cellSize, (cellZ + 0.5) * cellSize, outTypes[index])
					changed = changed + 1
				end
			end
		end
		return changed, cellsX * cellsZ
	end

	-- Grass: one value per 32x32 elmo cell (4x4 height squares), purely visual but filled by the map's grass bitmap.
	-- GetGrass reports 255 everywhere when the map has no grass map, in which case there is nothing to move.
	-- Returns: number of cells changed, number of cells.
	local function transformGrass()
		if not (Spring.GetGrass and Spring.AddGrass and Spring.RemoveGrass) then
			return 0, 0
		end
		local cellSize = 4 * Game.squareSize
		local cellsX, cellsZ = floor(mapWidth / cellSize), floor(mapHeight / cellSize)
		local baseGrass, first, uniform = {}, nil, true
		for cellZ = 0, cellsZ - 1 do
			local rowStart = cellZ * cellsX
			for cellX = 0, cellsX - 1 do
				local grass = Spring.GetGrass((cellX + 0.5) * cellSize, (cellZ + 0.5) * cellSize)
				baseGrass[rowStart + cellX + 1] = grass
				first = first or grass
				uniform = uniform and grass == first
			end
		end
		if uniform then
			return 0, cellsX * cellsZ
		end
		local outGrass = Field.remapHard(transform, baseGrass, cellsX, cellsZ, cellSize, true)
		local changed = 0
		for cellZ = 0, cellsZ - 1 do
			local rowStart = cellZ * cellsX
			for cellX = 0, cellsX - 1 do
				local index = rowStart + cellX + 1
				if outGrass[index] ~= baseGrass[index] then
					local centerX, centerZ = (cellX + 0.5) * cellSize, (cellZ + 0.5) * cellSize
					if outGrass[index] > 0 then
						Spring.AddGrass(centerX, centerZ, outGrass[index])
					else
						Spring.RemoveGrass(centerX, centerZ)
					end
					changed = changed + 1
				end
			end
		end
		return changed, cellsX * cellsZ
	end

	----------------------------------------------------------------------------
	-- Features
	----------------------------------------------------------------------------

	-- Converts a direction vector on the map plane into an engine heading (-32768..32767 covers a full turn).
	-- Params: dirX, dirZ = direction. Returns: the integer heading.
	local function headingFromVector(dirX, dirZ)
		local heading = atan2(dirX, dirZ) * (32768 / pi)
		if heading >= 32768 then
			heading = heading - 65536
		elseif heading < -32768 then
			heading = heading + 65536
		end
		return floor(heading + 0.5)
	end

	-- Creates one feature on the (new) ground and tilts it to the terrain normal.
	-- Params: featureDefName, outX/outZ = output position, heading, teamId.
	local function placeFeature(featureDefName, outX, outZ, heading, teamId)
		local outY = GetGroundHeight(outX, outZ)
		isPlacingFeature = true
		local featureId = Spring.CreateFeature(featureDefName, outX, outY, outZ, heading, teamId)
		isPlacingFeature = false
		if not featureId then
			return
		end
		handledFeatureIds[featureId] = true
		stats.created = stats.created + 1
		local normalX, normalY, normalZ = Spring.GetGroundNormal(outX, outZ)
		if Spring.SetFeatureHeadingAndUpDir then
			Spring.SetFeatureHeadingAndUpDir(featureId, heading, normalX or 0, normalY or 1, normalZ or 0)
		end
	end

	-- Before the first simulation frame the renderer ignores moves and deletions, so an original that has
	-- to change is hidden and replaced by freshly created features (those are drawn where they are created).
	-- Params: featureId = the original feature to remove.
	local function retireFeature(featureId)
		-- drawing is controlled from unsynced code only
		Spring.SetFeatureRulesParam(featureId, "mapgen_retired", 1, { public = true })
		SendToUnsynced("mapgen_retire", featureId)
		Spring.SetFeatureNoSelect(featureId, true)
		if Spring.SetFeatureBlocking then
			Spring.SetFeatureBlocking(featureId, false, false, false, false, false)
		end
		Spring.DestroyFeature(featureId)
		stats.retired = stats.retired + 1
	end

	-- Creates the feature at each target; its heading is the source heading pulled back through the
	-- local Jacobian of the transform (so mirrored/rotated copies face the right way).
	-- Params: defName = feature def name, targets = list of { outX, outZ }, heading = source heading, teamId.
	local function placeAtTargets(defName, targets, heading, teamId)
		local sourceRadians = heading * (pi / 32768)
		local dirX, dirZ = sin(sourceRadians), cos(sourceRadians)
		for i = 1, #targets do
			local outX, outZ = targets[i][1], targets[i][2]
			-- Jacobian [jacXX jacXZ; jacZX jacZZ] of out -> source at this target
			local jacXX, jacXZ, jacZX, jacZZ = transform:jacobian(outX, outZ)
			local det = jacXX * jacZZ - jacXZ * jacZX
			local pulledDirX, pulledDirZ = dirX, dirZ
			if abs(det) > 1e-6 then
				pulledDirX = (jacZZ * dirX - jacXZ * dirZ) / det
				pulledDirZ = (-jacZX * dirX + jacXX * dirZ) / det
			end
			placeFeature(defName, outX, outZ, headingFromVector(pulledDirX, pulledDirZ), teamId)
		end
	end

	-- Every feature is replaced by one feature at each position that maps onto it (none = it disappears).
	-- Params: featureId = a feature at its original (source) position.
	local function transformFeature(featureId)
		handledFeatureIds[featureId] = true
		local featureDefId = Spring.GetFeatureDefID(featureId)
		local featureDef = featureDefId and FeatureDefs[featureDefId]
		local srcX, _, srcZ = Spring.GetFeaturePosition(featureId)
		if not featureDef or not srcX then
			return
		end
		local teamId = Spring.GetFeatureTeam(featureId)
		local heading = Spring.GetFeatureHeading(featureId) or 0

		local targets = transform:preimages(srcX, srcZ)

		-- an original that already sits where the transform wants it (same orientation) is left alone
		local keep = false
		for i = 1, #targets do
			if abs(targets[i][1] - srcX) < 1 and abs(targets[i][2] - srcZ) < 1 then
				local jacXX, jacXZ, jacZX, jacZZ = transform:jacobian(srcX, srcZ)
				if abs(jacXX - 1) < 0.01 and abs(jacZZ - 1) < 0.01 and abs(jacXZ) < 0.01 and abs(jacZX) < 0.01 then
					keep = true
					table.remove(targets, i)
					stats.kept = stats.kept + 1
					break
				end
			end
		end

		if not keep then
			retireFeature(featureId)
		end
		placeAtTargets(featureDef.name, targets, heading, teamId)
	end

	-- Transforms every feature that exists now and was not handled yet. Returns how many features existed.
	local function transformExistingFeatures()
		local featureIds = Spring.GetAllFeatures()
		for i = 1, #featureIds do
			if not handledFeatureIds[featureIds[i]] then
				transformFeature(featureIds[i])
			end
		end
		return #featureIds
	end

	-- Logs how features were caught and handled so far. Params: label = when this report is made.
	local function reportFeatures(label)
		Spring.Echo(string.format(
			"[MapGen v2] features (%s): %d at load, %d caught on creation, %d caught late | %d kept, %d replaced by %d new",
			label, stats.existing, stats.hook, stats.late, stats.kept, stats.retired, stats.created
		))
	end

	-- Safety net: anything that slipped past FeatureCreated (or appeared before the first frame) is handled here.
	-- Runs once; ends the setup phase. Params: label = what triggered it (for the log).
	local function endSetup(label)
		if sweepDone then
			return
		end
		sweepDone = true
		setupPhase = false
		local before = stats.kept + stats.retired
		transformExistingFeatures()
		stats.late = stats.kept + stats.retired - before
		reportFeatures(label)
	end

	----------------------------------------------------------------------------
	-- Start boxes and start positions
	----------------------------------------------------------------------------

	-- Start boxes and map-defined start positions follow the transform in mirror pairs (see startboxes.lua),
	-- so neither team gets terrain the other does not.
	-- Params: descriptors = the accepted chain descriptors (Generate.descriptors result).
	-- Returns: a one-line summary for the log.
	local function transformStartBoxes(descriptors)
		local gaiaTeamId = Spring.GetGaiaTeamID()
		local gaiaAllyTeamId = gaiaTeamId and select(6, Spring.GetTeamInfo(gaiaTeamId, false))
		local allyTeamIds = {}
		for _, allyTeamId in ipairs(Spring.GetAllyTeamList()) do
			if allyTeamId ~= gaiaAllyTeamId then
				allyTeamIds[#allyTeamIds + 1] = allyTeamId
			end
		end

		-- the game's own start box config (BAR); absent on other games, then only the engine rectangles count
		local okLib, StartboxLib = pcall(require, "luarules/gadgets/include/startbox_utilities")
		local startboxConfig, hasExplicitBoxes
		if okLib and type(StartboxLib) == "table" and StartboxLib.GetConfig then
			local _
			startboxConfig, _, hasExplicitBoxes = StartboxLib.GetConfig()
		end

		-- one region per ally team: its polygon boxes from the config, else the engine's start rectangle
		local regions = {}
		for _, allyTeamId in ipairs(allyTeamIds) do
			local entry = hasExplicitBoxes and startboxConfig and startboxConfig[allyTeamId]
			if entry and entry.boxes and #entry.boxes > 0 and not entry.wholeMap then
				regions[#regions + 1] = Startboxes.ringsRegion(allyTeamId, entry.boxes)
			else
				local boxX1, boxZ1, boxX2, boxZ2 = Spring.GetAllyTeamStartBox(allyTeamId)
				if boxX1 and boxX2 > boxX1 and boxZ2 > boxZ1
					and not (boxX1 <= 0 and boxZ1 <= 0 and boxX2 >= mapWidth and boxZ2 >= mapHeight) then
					regions[#regions + 1] = Startboxes.rectRegion(allyTeamId, boxX1, boxZ1, boxX2, boxZ2)
				end
			end
		end

		local summaryParts = {}
		if #regions > 0 then
			local result = Startboxes.compute(transform, descriptors, mapWidth, mapHeight, regions, { cell = 32 })
			local entries = result.regions
			if hasExplicitBoxes and startboxConfig then
				Startboxes.applyToConfig(startboxConfig, entries, mapHeight - 1)
			end

			-- the game's containment helpers read these on every placement; answer from the new shapes
			if GG then
				local originalIsInside = GG.IsInsideStartbox
				local originalBounds = GG.GetStartboxBounds
				local originalPolygons = GG.GetStartboxPolygons
				GG.IsInsideStartbox = function(x, z, allyTeamId)
					local entry = entries[allyTeamId]
					if entry then
						return Startboxes.insideRings(entry.rings, x, z)
					end
					if originalIsInside then
						return originalIsInside(x, z, allyTeamId)
					end
				end
				GG.GetStartboxBounds = function(allyTeamId)
					local entry = entries[allyTeamId]
					if entry then
						return entry.bounds[1], entry.bounds[2], entry.bounds[3], entry.bounds[4]
					end
					if originalBounds then
						return originalBounds(allyTeamId)
					end
				end
				GG.GetStartboxPolygons = function(allyTeamId)
					local entry = entries[allyTeamId]
					if entry then
						return entry.rings
					end
					if originalPolygons then
						return originalPolygons(allyTeamId)
					end
				end
			end

			-- the engine clamps/drops placements outside the ally team rectangle, but only choose-in-game uses it
			if Game.startPosType == 2 then
				for allyTeamId, entry in pairs(entries) do
					Spring.SetAllyTeamStartBox(
						allyTeamId, entry.bounds[1], entry.bounds[2], entry.bounds[3], entry.bounds[4]
					)
				end
			end
			Spring.SetGameRulesParam(PARAM_BOXES, Startboxes.serialize(entries), { public = true })

			local missingCount, infoParts = 0, {}
			for _, region in ipairs(regions) do
				local entry = entries[region.id]
				if entry then
					infoParts[#infoParts + 1] =
						string.format("%d<->%d %d cells", region.id, result.partner[region.id], entry.cells)
				else
					missingCount = missingCount + 1
				end
			end
			summaryParts[#summaryParts + 1] = string.format(
				"boxes (%s): %s%s",
				hasExplicitBoxes and "polygons" or "engine rects",
				table.concat(infoParts, ", "),
				missingCount > 0 and (", " .. missingCount .. " unchanged") or ""
			)
		end

		-- map-defined start positions (fixed / random modes); in choose-in-game the player picks inside the box
		if Game.startPosType ~= 2 then
			local posRegions, hasStartPos = {}, {}
			for _, teamId in ipairs(Spring.GetTeamList()) do
				if teamId ~= gaiaTeamId then
					local startX, _, startZ = Spring.GetTeamStartPosition(teamId)
					if startX and startZ and startX > 0 and startZ > 0 then
						posRegions[#posRegions + 1] = Startboxes.discRegion(teamId, startX, startZ, 64)
						hasStartPos[teamId] = true
					end
				end
			end
			if #posRegions > 0 then
				local result = Startboxes.compute(
					transform, descriptors, mapWidth, mapHeight, posRegions,
					{ cell = 32, minCells = 1, fallbackRadius = 0.03 }
				)
				local movedCount = 0
				for teamId, entry in pairs(result.regions) do
					Spring.SetTeamStartPosition(teamId, entry.cx, GetGroundHeight(entry.cx, entry.cz), entry.cz)
					movedCount = movedCount + 1
				end
				summaryParts[#summaryParts + 1] =
					string.format("%d of %d team start positions moved", movedCount, #posRegions)
			end
		end
		return #summaryParts > 0 and table.concat(summaryParts, "; ") or "nothing to transform"
	end

	----------------------------------------------------------------------------
	-- Gadget callins
	----------------------------------------------------------------------------

	-- Runs the whole load sequence described at the top of the synced section.
	-- Removes the gadget (leaving the map untouched) when disabled, when the game already started or when the
	-- terrain cannot be deformed.
	function gadget:Initialize()
		local options = readOptions()
		if Spring.GetGameFrame() > 0 or not options.enabled then
			gadgetHandler:RemoveGadget(self)
			return
		end

		-- On a map with terrain deformation disabled (mapinfo notDeformable, or the map-damage lobby option) the engine
		-- silently ignores every heightmap write. Transforming everything else would then leave the terrain and the
		-- textures / metal / features out of step, so the map is left completely untouched.
		if Spring.SetHeightMapFunc(function() end) == nil then
			Spring.Echo("[MapGen v2] this map's terrain cannot be modified (notDeformable / map damage disabled): map left untouched")
			gadgetHandler:RemoveGadget(self)
			return
		end

		-- A: seed
		local seed = options.seed
		if seed == 0 then
			-- the engine's Lua numbers are float32: seeds above 2^24 would be rounded, so stay below
			seed = math.random(1, 16000000)
		end

		-- protected points (metal spots, geo vents): they decide which chain is accepted, and the unsynced side
		-- derives its texture patches from them
		local metalGrid = readMetalGrid()
		local spotsMode = options.metalMode == "spots" or options.metalMode == "spots_normalize"
		if spotsMode then
			metalGrid.spots, metalGrid.field = Field.findSpots(metalGrid.amounts, metalGrid.cellsX, metalGrid.cellsZ)
		else
			metalGrid.spots = {}
		end
		local protectedPoints, protectText, spotCount =
			collectProtected(options.metalMode, metalGrid.spots, metalGrid.cellSize)

		-- B: composite transform. A chain that would put two copies of protected points on top of each other (a spot
		-- close to a fold line next to its own mirror image...) is re-rolled; the accepted attempt number is published.
		-- With normalized metal a chain must also keep the metal from falling short: scaling can only turn it down
		-- (spots peak at the engine's cell cap), never up. Copies cut by the map edge or a seam lose some, so the
		-- stamped total itself is checked.
		local needSpots = options.metalMode == "spots_normalize" and spotCount > 0

		-- Fraction (0..1) of the original metal total that a trial chain's stamped spots fall short of.
		local function metalShortfall(trial)
			local spotPoints = {}
			for i = 1, spotCount do
				spotPoints[i] = protectedPoints[i]
			end
			local outAmounts = Field.remapSpots(
				trial, metalGrid.amounts, metalGrid.cellsX, metalGrid.cellsZ, metalGrid.cellSize, {
					spots = metalGrid.spots, field = metalGrid.field, images = Field.imagesOf(trial, spotPoints),
				}
			)
			local sum = 0
			for i = 1, metalGrid.cellsX * metalGrid.cellsZ do
				sum = sum + outAmounts[i]
			end
			return metalGrid.total > 0 and math.max(0, 1 - sum / metalGrid.total) or 0
		end

		-- The terrain must also survive the chain: a cross-fade between two unrelated parts of the map (a select
		-- seam, a tile border...) turns their height difference into a cliff. relax.lua can spread moderate steps
		-- over a ramp; a chain that would need to reshape more than SEAM_OK percent of the map is re-rolled.
		-- The check runs on a coarse copy of the heightmap, a fraction of a second per attempt.
		local seamBase, seamCellsX, seamCellsZ
		do
			local seamCellSize = Relax.TARGET_STEP
			if mapWidth % seamCellSize == 0 and mapHeight % seamCellSize == 0 then
				seamCellsX, seamCellsZ = mapWidth / seamCellSize + 1, mapHeight / seamCellSize + 1
				seamBase = {}
				for cellZ = 0, seamCellsZ - 1 do
					for cellX = 0, seamCellsX - 1 do
						seamBase[cellZ * seamCellsX + cellX + 1] =
							GetGroundHeight(cellX * seamCellSize, cellZ * seamCellSize)
					end
				end
			end
		end

		-- Seam penalty of a trial chain: residual steep edges and the share of the map that would be reshaped.
		-- Returns 0 when the map size does not fit the coarse grid (no seam check possible).
		local function seamCost(trial)
			if not seamBase then
				return 0
			end
			local seamCellSize = Relax.TARGET_STEP
			local seamOut = Field.remap(trial, seamBase, seamCellsX, seamCellsZ, seamCellSize, false, "bilinear")
			local _, seamStats = Relax.plan(
				trial, seamBase, seamOut, seamCellsX, seamCellsZ, seamCellSize, Relax.discs(trial, protectedPoints)
			)
			return math.min(900, seamStats.residual / 10 + seamStats.rewritten * 100)
		end

		-- Lower score = better chain. Overlapping copies of protected points weigh most, then missing spots, then the
		-- metal shortfall, then steep seams; a score of SEAM_OK or less is accepted at once.
		local descriptors, attempt, overlapCount
		local bestScore, bestSeamCost
		do
			for attemptIndex = 0, MAX_ATTEMPTS do
				local candidate = Generate.descriptors(
					seed, mapWidth, mapHeight, { layers = options.layers, band = options.band, attempt = attemptIndex }
				)
				local trial = Transform.new(candidate, mapWidth, mapHeight)
				local conflictCount = #protectedPoints > 0 and Patches.conflicts(trial, protectedPoints) or 0
				local deficit = needSpots
					and math.max(0, spotCount - Patches.copies(trial, protectedPoints, spotCount)) or 0
				local chainScore, seamPenalty = conflictCount * 1e6 + deficit * 1e4, 0
				if conflictCount == 0 and deficit == 0 then
					local shortfallFraction = needSpots and metalShortfall(trial) or 0
					seamPenalty = seamCost(trial)
					chainScore = chainScore
						+ (shortfallFraction > 0.005 and 1000 + shortfallFraction * 100 or 0) + seamPenalty
				else
					chainScore = chainScore + 5000
				end
				if not bestScore or chainScore < bestScore then
					descriptors, attempt, overlapCount, bestScore, bestSeamCost =
						candidate, attemptIndex, conflictCount, chainScore, seamPenalty
				end
				if chainScore <= SEAM_OK then
					break
				end
			end
		end
		transform = Transform.new(descriptors, mapWidth, mapHeight)
		local patches = Patches.build(transform, protectedPoints)
		Spring.SetGameRulesParam(PARAM_PROTECT, protectText, { public = true })
		Spring.SetGameRulesParam(PARAM_PATCHES, tostring(#patches), { public = true })

		-- C: publish exactly what was used, so unsynced never re-derives anything from options.
		-- Strings, not numbers: numeric rules params are 32-bit floats and would round large seeds.
		local description = Transform.describe(descriptors)
		Spring.SetGameRulesParam(
			PARAM_CFG,
			string.format("%d;%d;%.9g;%d;%d;%d", seed, options.layers, options.band, mapWidth, mapHeight, attempt),
			{ public = true }
		)
		Spring.SetGameRulesParam(PARAM_SIG, Transform.signature(descriptors), { public = true })
		Spring.SetGameRulesParam(PARAM_PROBE, probe(transform), { public = true })
		Spring.SetGameRulesParam(PARAM_DESC, description, { public = true })
		Spring.Echo(
			"[MapGen v2] seed " .. seed .. ": " .. description .. " [" .. Transform.signature(descriptors) .. "]"
		)
		Spring.Echo(string.format("[MapGen v2] protected spots / vents: %d, chain attempt %d, overlapping copies left: %d, seam cost %.2f", #protectedPoints, attempt, overlapCount, bestSeamCost))

		-- D: layers
		transformHeightmap(patches, protectedPoints)
		transformMetal(options.metalMode, metalGrid, protectedPoints, spotCount, patches)
		local typemapChanged, typemapTotal = transformTypemap()
		Spring.Echo(string.format("[MapGen v2] typemap: %d of %d cells changed", typemapChanged, typemapTotal))
		local grassChanged, grassTotal = transformGrass()
		-- the grass widget reads grass either from this engine grass map or from the map's own grass image; the
		-- widget in luaui/Widgets/mapgen_v2_grass.lua transforms the image case, so it must know this one was done
		Spring.SetGameRulesParam(PARAM_GRASS, grassChanged > 0 and 1 or 0, { public = true })
		Spring.Echo(string.format("[MapGen v2] grass: %d of %d engine grass cells changed (a grass image, if the map has one, is handled by the widget)", grassChanged, grassTotal))
		-- the smooth mesh is derived from the heightmap but normally lags by ~25 s; rebuild it now
		if Spring.RebuildSmoothMesh then
			Spring.RebuildSmoothMesh()
		end

		-- E: features, then start boxes
		stats.existing = transformExistingFeatures()
		Spring.Echo("[MapGen v2] heightmap and metal transformed")
		Spring.Echo("[MapGen v2] start boxes: " .. transformStartBoxes(descriptors))
		reportFeatures("after load")
	end

	-- Features made by other gadgets after this one loaded (e.g. the map's LuaGaia feature placer).
	function gadget:FeatureCreated(featureId)
		if transform and setupPhase and not isPlacingFeature and not handledFeatureIds[featureId] then
			stats.hook = stats.hook + 1
			transformFeature(featureId)
		end
	end

	function gadget:GamePreload()
		if transform then
			reportFeatures("before game start")
		end
	end

	function gadget:GameStart()
		if transform then
			endSetup("game start")
		end
	end

	function gadget:GameFrame()
		if transform then
			endSetup("first frame")
		end
	end

--------------------------------------------------------------------------------
-- UNSYNCED
--
-- Load sequence (the unsynced side never rolls anything itself, it only follows what synced published):
--   1. seed + chain   synced publishes "seed;layers;band;W;H;attempt" (PARAM_CFG) once its chain is accepted; tryBuild
--                     polls for it, then rebuilds the very same descriptors and Transform from those numbers
--   2. cross-check    the transform signature and the probe points must match synced's; otherwise textures are left
--                     untouched and the difference is logged
--   3. layers         only the textures are unsynced: the protected-point patches are re-derived from the published
--                     points, and a shader remaps the ground textures a few squares per frame (DrawGenesis)
--   4. features       originals that synced retired are hidden from drawing until the first simulation frame
--   5. start boxes    applied by the LuaUI widget from PARAM_BOXES, not here
--------------------------------------------------------------------------------
else
	local transform
	local lastConfigText -- the config string tryBuild last acted on, so it only rebuilds when it changes
	local textureRemap -- the texture shader driver (Textures.new); nil while textures are not remapped

	-- Synced may not have published yet when this Initialize runs, so poll until the config shows up.
	-- Rebuilds the transform from the published config, verifies it against synced and starts the texture remap.
	local function tryBuild()
		local configText = Spring.GetGameRulesParam(PARAM_CFG)
		if not configText or configText == lastConfigText then
			return
		end
		lastConfigText = configText
		local seed, layers, band, mapWidth, mapHeight, attempt =
			configText:match("^(%-?%d+);(%-?%d+);([^;]+);(%d+);(%d+);?(%d*)$")
		if not seed then
			Spring.Echo("[MapGen v2] unsynced: unreadable config '" .. tostring(configText) .. "', textures untouched")
			return
		end
		seed, layers, band, mapWidth, mapHeight =
			tonumber(seed), tonumber(layers), tonumber(band), tonumber(mapWidth), tonumber(mapHeight)
		attempt = tonumber(attempt) or 0
		local options = readOptions()
		local descriptors = Generate.descriptors(
			seed, mapWidth, mapHeight, { layers = layers, band = band, attempt = attempt }
		)
		transform = Transform.new(descriptors, mapWidth, mapHeight)

		local mySignature, syncedSignature = Transform.signature(descriptors), Spring.GetGameRulesParam(PARAM_SIG)
		local myProbe, syncedProbe = probe(transform), Spring.GetGameRulesParam(PARAM_PROBE)
		local sameSize = (mapWidth == Game.mapSizeX and mapHeight == Game.mapSizeZ)
		if mySignature == syncedSignature and myProbe == syncedProbe and sameSize then
			Spring.Echo(
				"[MapGen v2] unsynced transform rebuilt, matches synced (seed " .. seed .. ", " .. mySignature .. ")"
			)
		else
			Spring.Echo("[MapGen v2] WARNING unsynced transform differs from synced, textures left untouched!")
			Spring.Echo(
				"  synced  : " .. tostring(Spring.GetGameRulesParam(PARAM_DESC)) .. " [" .. tostring(syncedSignature)
					.. "] probe " .. tostring(syncedProbe)
			)
			Spring.Echo(
				"  unsynced: " .. Transform.describe(descriptors) .. " [" .. mySignature .. "] probe " .. myProbe
			)
			Spring.Echo("  cfg " .. configText .. ", game map size " .. Game.mapSizeX .. "x" .. Game.mapSizeZ)
			return
		end
		-- textures are rebuilt by a shader, a few squares per frame (see DrawGenesis)
		if options.textures then
			-- the same protected-point patches synced used for the terrain: copies cut by a seam are redrawn whole
			local patches = Patches.build(transform, Patches.parse(Spring.GetGameRulesParam(PARAM_PROTECT)))
			local syncedPatchCount = tostring(Spring.GetGameRulesParam(PARAM_PATCHES))
			if tostring(#patches) ~= syncedPatchCount then
				Spring.Echo(
					"[MapGen v2] WARNING unsynced derived " .. #patches .. " patches, synced " .. syncedPatchCount
				)
			else
				Spring.Echo("[MapGen v2] textures: " .. #patches .. " spot / geo copies redrawn whole")
			end
			textureRemap = Textures.new(transform, mapWidth, mapHeight, patches)
			-- slopes the terrain pass made (published by synced, which knows the source heights) are drawn as rock
			local rock = Relax.parseRock(Spring.GetGameRulesParam(PARAM_ROCK))
			if rock then
				textureRemap:setRockMask(rock.ncx, rock.ncz, rock.cs, rock.weights)
			end
		end
	end

	----------------------------------------------------------------------------
	-- Retired features
	----------------------------------------------------------------------------

	-- Retired originals stay in the world until the first simulation frame, so hide them from drawing.
	local hiddenFeatureIds = {}

	-- Stops drawing a feature (once). Params: featureId.
	local function hide(featureId)
		if not hiddenFeatureIds[featureId] then
			hiddenFeatureIds[featureId] = true
			Spring.SetFeatureNoDraw(featureId, true)
		end
	end

	-- Synced announces each retired feature through SendToUnsynced("mapgen_retire", featureId).
	function gadget:RecvFromSynced(message, featureId)
		if message == "mapgen_retire" and featureId then
			hide(featureId)
		end
	end

	-- Fallback in case a message arrived before this gadget could act on it: rules params are persistent.
	local function sweepRetired()
		local featureIds = Spring.GetAllFeatures()
		for i = 1, #featureIds do
			if not hiddenFeatureIds[featureIds[i]] and Spring.GetFeatureRulesParam(featureIds[i], "mapgen_retired") then
				hide(featureIds[i])
			end
		end
	end

	----------------------------------------------------------------------------
	-- Gadget callins
	----------------------------------------------------------------------------

	function gadget:Initialize()
		tryBuild()
	end

	-- Draw callins are the only place GL render-to-texture is allowed.
	function gadget:DrawGenesis()
		if textureRemap then
			textureRemap:step()
		end
	end

	function gadget:Shutdown()
		if textureRemap then
			textureRemap:restore()
		end
	end

	-- Retries tryBuild until synced has published, and keeps hiding retired features during the first frames.
	function gadget:Update()
		if not transform then
			tryBuild()
		end
		if Spring.GetGameFrame() <= 1 then
			sweepRetired()
		end
	end
end
