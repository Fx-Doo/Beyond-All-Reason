-- Widget description read by the widget handler (the layer makes this widget load before map_startbox, which has
-- layer 1000000, reads the config).
function widget:GetInfo()
	return {
		name = "MapGen v2 start boxes",
		desc = "Makes the game's start box widgets show the start boxes produced by MapGen v2",
		author = "Doo",
		date = "2026",
		layer = -1000000, -- before map_startbox (layer 1000000) reads the config
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- MapGen v2 start boxes widget
--
-- The synced MapGen gadget publishes the new start box polygons as a rules param. BAR's start box widgets read
-- polygons through startbox_utilities, which re-derives them from the lobby's modoptions inside this Lua state,
-- so the result has to be patched in here as well.
--------------------------------------------------------------------------------

-- Loads the start box library from the first folder that has it (the MapGen v2 folder first, then the older
-- mapgen folder). Stays nil when none is usable.
local Startboxes
for _, libPath in ipairs({
	"luarules/gadgets/libs/mapgen_v2/startboxes.lua",
	"luarules/gadgets/libs/mapgen/startboxes.lua",
}) do
	local ok, library = pcall(VFS.Include, libPath)
	if ok and type(library) == "table" then
		Startboxes = library
		break
	end
end

-- Reads the start boxes published by the gadget and patches them into BAR's startbox_utilities, both into its
-- cached config and into every config built by its ParseBoxes function from now on.
-- Does nothing when nothing was published or startbox_utilities is not available.
function widget:Initialize()
	local serialized = Spring.GetGameRulesParam("mapgen_startboxes")
	if not (Startboxes and serialized and serialized ~= "") then
		return
	end
	local okUtilities, utilities = pcall(require, "luarules/gadgets/include/startbox_utilities")
	if not (okUtilities and type(utilities) == "table") then
		return
	end

	local entries = Startboxes.deserialize(serialized)
	local maxZ = Game.mapSizeZ - 1

	-- the cached config (GetBounds / IsInside / GetCenter ...) is patched in place
	local cachedConfig = utilities.GetConfig and utilities.GetConfig()
	if cachedConfig then
		Startboxes.applyToConfig(cachedConfig, entries, maxZ)
	end

	-- ParseBoxes builds a fresh config each call (the overlay widget uses it), so wrap it
	local originalParseBoxes = utilities.ParseBoxes
	local loggedCount = 0

	-- Describes a config for the log: per team id, the polygon count and the first vertex of the first polygon.
	-- config: start box config table { [teamId] = { boxes = { polygon, ... } } }
	-- Returns one string, teams sorted and separated by " | ".
	local function describeFirstVertices(config)
		local lines = {}
		for teamId, entry in pairs(config) do
			local firstPolygon = entry.boxes and entry.boxes[1]
			local vertex = firstPolygon and firstPolygon[1]
			lines[#lines + 1] = string.format(
				"team %s: %s polygons, first vertex %s",
				tostring(teamId),
				entry.boxes and #entry.boxes or 0,
				vertex and (math.floor(vertex[1]) .. "," .. math.floor(vertex[2])) or "-"
			)
		end
		table.sort(lines)
		return table.concat(lines, " | ")
	end

	if originalParseBoxes then
		utilities.ParseBoxes = function(...)
			local config, source, explicit = originalParseBoxes(...)
			if config then
				-- the first few calls are logged with the config before and after patching
				local beforeText = loggedCount < 4 and describeFirstVertices(config) or nil
				Startboxes.applyToConfig(config, entries, maxZ)
				if beforeText then
					loggedCount = loggedCount + 1
					local callerInfo = debug and debug.getinfo and debug.getinfo(2, "S")
					Spring.Echo(string.format(
						"[MapGen v2] start boxes read by %s (source %s, explicit %s)\n  before: %s\n  after : %s",
						callerInfo and callerInfo.short_src or "?",
						tostring(source),
						tostring(explicit),
						beforeText,
						describeFirstVertices(config)
					))
				end
			end
			return config, source, explicit
		end
	end

	local boxCount = 0
	for _ in pairs(entries) do
		boxCount = boxCount + 1
	end
	Spring.Echo("[MapGen v2] start box widget: patched " .. boxCount .. " start boxes")
end
