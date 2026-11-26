-- Widget description read by the widget handler (the layer makes this widget update after map_grass_gl4 has
-- built its grass).
function widget:GetInfo()
	return {
		name = "MapGen v2 grass",
		desc = "Applies the MapGen v2 transform to the grass of maps that define it with a grass image "
			.. "(BAR's Map Grass GL4)",
		author = "Doo",
		date = "2026",
		layer = 1000000, -- after map_grass_gl4 has built its grass
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- MapGen v2 grass widget
--
-- BAR's grass widget takes its grass from the map's own grass image (mapinfo grassconfig.grassDistTGA) when there
-- is one, and only otherwise from the engine's grass map. The synced gadget transforms the engine grass map; this
-- widget covers the image case: it reads the densities through WG.grassgl4, maps them through the same transform
-- and writes them back. The transform is rebuilt from the published config exactly like the unsynced gadget does.
--
-- The grass is handled as a grid of "patches" (cells): cellsX x cellsZ patches of cellSize elmos each.
-- State machine: "wait" (grass widget not ready) -> "writing" (a few cells per frame) -> "done".
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- constants
--------------------------------------------------------------------------------

-- names of the game rules params published by the gadget
local PARAM_CFG = "mapgen_cfg"
local PARAM_SIG = "mapgen_sig"
local PARAM_GRASS = "mapgen_grass_engine"

-- how many grass patches are written back per frame
local CELLS_PER_FRAME = 6000

--------------------------------------------------------------------------------
-- libraries
--------------------------------------------------------------------------------

-- Loads transform.lua, generate.lua and field.lua from the first library folder that has all three
-- (the MapGen v2 folder first, then the older mapgen folder). Leaves them nil when none is usable.
local Transform, Generate, Field
for _, libDir in ipairs({ "luarules/gadgets/libs/mapgen_v2/", "luarules/gadgets/libs/mapgen/" }) do
	local okTransform, transformLib = pcall(VFS.Include, libDir .. "transform.lua")
	if okTransform and type(transformLib) == "table" then
		local okGenerate, generateLib = pcall(VFS.Include, libDir .. "generate.lua")
		local okField, fieldLib = pcall(VFS.Include, libDir .. "field.lua")
		if okGenerate and okField and type(generateLib) == "table" and type(fieldLib) == "table" then
			Transform, Generate, Field = transformLib, generateLib, fieldLib
			break
		end
	end
end

local floor = math.floor

--------------------------------------------------------------------------------
-- widget state
--------------------------------------------------------------------------------

local state = "wait" -- wait -> writing -> done

-- srcDensity: grass density per patch as read from the grass widget (row-major, index = cellZ * cellsX + cellX + 1)
-- outDensity: the same grid after the transform
-- cursor:     number of patches already written back
local srcDensity, outDensity
local cellsX, cellsZ, cellSize
local cursor
local changedCount = 0

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

-- Ends the widget's work (it removes itself on the next Update) and optionally logs a message.
-- message: text appended to the log prefix, or nil to stay silent
-- Returns nothing.
local function finish(message)
	state = "done"
	if message then
		Spring.Echo("[MapGen v2] grass widget: " .. message)
	end
end

-- Waits until the grass widget is ready, then reads its densities, applies the transform to them and
-- switches to the "writing" state.
-- Returns false when it is not ready yet (try again next frame), true when the transformed grid is ready,
-- and nothing when the widget is finished instead (nothing to do or something is inconsistent).
local function build()
	local grassApi = WG.grassgl4
	if not (
		grassApi
		and grassApi.hasGrass
		and grassApi.getConfig
		and grassApi.getDensityAt
		and grassApi.setDensityAt
	) then
		return false
	end
	if not grassApi.hasGrass() then
		return false
	end

	local configString = Spring.GetGameRulesParam(PARAM_CFG)
	if not configString then
		return false
	end
	if Spring.GetGameRulesParam(PARAM_GRASS) == 1 then
		return finish("grass came from the engine grass map, already transformed by the gadget")
	end

	-- config format: "seed;layers;band;mapWidth;mapHeight[;attempt]"
	local seed, layers, band, mapWidth, mapHeight, attempt =
		configString:match("^(%-?%d+);(%-?%d+);([^;]+);(%d+);(%d+);?(%d*)$")
	if not seed then
		return finish("unreadable config, grass left as it is")
	end
	local descriptors = Generate.descriptors(tonumber(seed), tonumber(mapWidth), tonumber(mapHeight), {
		layers = tonumber(layers), band = tonumber(band), attempt = tonumber(attempt) or 0,
	})
	if Transform.signature(descriptors) ~= Spring.GetGameRulesParam(PARAM_SIG) then
		return finish("transform differs from the synced one, grass left as it is")
	end
	local mapTransform = Transform.new(descriptors, tonumber(mapWidth), tonumber(mapHeight))

	-- read the density of every patch (sampled at the patch centre)
	local grassConfig = grassApi.getConfig()
	cellSize = grassConfig.patchResolution
	cellsX, cellsZ = floor(grassConfig.mapSizeX / cellSize), floor(grassConfig.mapSizeZ / cellSize)
	srcDensity = {}
	local anyGrass = false
	for cellZ = 0, cellsZ - 1 do
		for cellX = 0, cellsX - 1 do
			local density = grassApi.getDensityAt((cellX + 0.5) * cellSize, (cellZ + 0.5) * cellSize)
			srcDensity[cellZ * cellsX + cellX + 1] = density
			if density > 0 then
				anyGrass = true
			end
		end
	end
	if not anyGrass then
		return finish("no grass on this map")
	end

	outDensity = Field.remapHard(mapTransform, srcDensity, cellsX, cellsZ, cellSize, true)
	cursor = 0
	state = "writing"
	Spring.Echo(string.format(
		"[MapGen v2] grass widget: transforming %d x %d grass patches (%.0f elmos each)",
		cellsX, cellsZ, cellSize
	))
	return true
end

--------------------------------------------------------------------------------
-- widget callins
--------------------------------------------------------------------------------

-- Called every frame by the widget handler: builds the transformed grid once the grass widget is ready,
-- then writes up to CELLS_PER_FRAME changed patches back per frame, and removes itself when done.
function widget:Update()
	if state == "done" then
		widgetHandler:RemoveWidget()
		return
	end
	if state == "wait" then
		if build() == false then
			return
		end
	end
	if state ~= "writing" then
		return
	end
	local grassApi = WG.grassgl4
	if not grassApi then
		return finish("grass widget went away")
	end

	-- write this frame's slice of patches (only those whose density changed)
	local lastCell = math.min(cellsX * cellsZ, cursor + CELLS_PER_FRAME)
	for cellIndex = cursor + 1, lastCell do
		if outDensity[cellIndex] ~= srcDensity[cellIndex] then
			local cellX, cellZ = (cellIndex - 1) % cellsX, floor((cellIndex - 1) / cellsX)
			grassApi.setDensityAt((cellX + 0.5) * cellSize, (cellZ + 0.5) * cellSize, outDensity[cellIndex], true)
			changedCount = changedCount + 1
		end
	end
	cursor = lastCell
	if cursor >= cellsX * cellsZ then
		finish(string.format("%d of %d grass patches changed", changedCount, cellsX * cellsZ))
	end
end
