local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Map Alterations",
		version = "v1",
		desc = "Terrain/map edits via GG: CreateRamp, CreateSquarePlateau, CreateRoundPlateau, CreateMetalSpot, AddFeature. Cheats: /luarules ramp <startX> <startZ> <endX> <endZ> <width> [smoothWidth]",
		author = "",
		date = "Oct 2026",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

local PACKET_HEADER = "$ramp$"
local PACKET_HEADER_LENGTH = string.len(PACKET_HEADER)
local PH_B1 = string.byte(PACKET_HEADER, 1)

local DEFAULT_SMOOTH_WIDTH = 64
local MAX_CELLS = 250000 -- sanity limit on the affected heightmap points

if gadgetHandler:IsSyncedCode() then
	local unpack = unpack or table.unpack
	local spGetGroundHeight = Spring.GetGroundHeight
	local spGetGroundOrigHeight = Spring.GetGroundOrigHeight
	local spSetHeightMap = Spring.SetHeightMap
	local spSetOriginalHeightMap = Spring.SetOriginalHeightMap

	local mathMax, mathMin, mathAbs, mathSqrt, mathFloor, mathCeil =
		math.max, math.min, math.abs, math.sqrt, math.floor, math.ceil

	local function clamp(v, a, b)
		return mathMax(a, mathMin(b, v))
	end

	local function smoothstep(e0, e1, x)
		local t = clamp((x - e0) / (e1 - e0), 0, 1)
		return t * t * (3 - 2 * t)
	end

	-- Oriented rectangle along the segment start->end. Returns dist(x, z) -> distance to the
	-- rectangle (0 inside, euclidean outside so corners are rounded) and the position along it.
	local function makeRectDistance(startX, startZ, endX, endZ, width)
		local dx, dz = endX - startX, endZ - startZ
		local len = mathSqrt(dx * dx + dz * dz)
		local nx, nz = dx / len, dz / len -- along
		local px, pz = -nz, nx -- across
		local hw = width / 2

		return function(x, z)
			local rx, rz = x - startX, z - startZ
			local t = rx * nx + rz * nz
			local s = rx * px + rz * pz
			local ox = mathMax(0, -t, t - len)
			local oz = mathMax(0, mathAbs(s) - hw)
			return mathSqrt(ox * ox + oz * oz), t / len
		end, px, pz
	end

	-- Each make* returns f(x, z, baseHeight) -> new height, or nil when outside the blend area.
	local function makeRamp(startX, startZ, endX, endZ, width, smoothWidth)
		local rectDistance, px, pz = makeRectDistance(startX, startZ, endX, endZ, width)

		local function edgeHeight(cx, cz)
			local sum, n = 0, 5
			for i = 0, n - 1 do
				local s = (i / (n - 1) - 0.5) * width
				sum = sum + spGetGroundHeight(cx + px * s, cz + pz * s)
			end
			return sum / n
		end
		local hStart = edgeHeight(startX, startZ)
		local hEnd = edgeHeight(endX, endZ)

		return function(x, z, baseHeight)
			local dist, u = rectDistance(x, z)
			if dist >= smoothWidth then
				return nil
			end

			local w = 1 - smoothstep(0, smoothWidth, dist)
			local hRamp = hStart + (hEnd - hStart) * clamp(u, 0, 1)
			return baseHeight * (1 - w) + hRamp * w
		end
	end

	local function makeSquarePlateau(startX, startZ, endX, endZ, width, height, smoothWidth)
		local rectDistance = makeRectDistance(startX, startZ, endX, endZ, width)
		return function(x, z, baseHeight)
			local dist = rectDistance(x, z)
			if dist >= smoothWidth then
				return nil
			end
			local w = 1 - smoothstep(0, smoothWidth, dist)
			return baseHeight * (1 - w) + height * w
		end
	end

	local function makeRoundPlateau(cx, cz, radius, height, smoothWidth)
		return function(x, z, baseHeight)
			local dx, dz = x - cx, z - cz
			local dist = mathMax(0, mathSqrt(dx * dx + dz * dz) - radius)
			if dist >= smoothWidth then
				return nil
			end
			local w = 1 - smoothstep(0, smoothWidth, dist)
			return baseHeight * (1 - w) + height * w
		end
	end

	local function adjustFeaturesInRect(x1, z1, x2, z2)
		local features = Spring.GetFeaturesInRectangle(x1, z1, x2, z2)
		for i = 1, #features do
			local x, y, z = Spring.GetFeaturePosition(features[i])
			Spring.SetFeaturePosition(features[i], x, y, z, true) -- snaptoground
		end
	end

	-- Applies f over the bounding box [x1,x2]x[z1,z2] (elmos) to both the live and original heightmaps.
	local function applyShape(x1, z1, x2, z2, f)
		local sq = Game.squareSize
		local minX = clamp(mathFloor(x1 / sq) * sq, 0, Game.mapSizeX)
		local maxX = clamp(mathCeil(x2 / sq) * sq, 0, Game.mapSizeX)
		local minZ = clamp(mathFloor(z1 / sq) * sq, 0, Game.mapSizeZ)
		local maxZ = clamp(mathCeil(z2 / sq) * sq, 0, Game.mapSizeZ)

		local cells = ((maxX - minX) / sq + 1) * ((maxZ - minZ) / sq + 1)
		if cells > MAX_CELLS then
			return false, "area too large (" .. cells .. " points)"
		end

		-- Sample everything first so no read sees partially written terrain.
		local curX, curZ, curH = {}, {}, {}
		local origH = {}
		local n = 0
		for x = minX, maxX, sq do
			for z = minZ, maxZ, sq do
				local h = f(x, z, spGetGroundHeight(x, z))
				if h then
					n = n + 1
					curX[n], curZ[n], curH[n] = x, z, h
					origH[n] = f(x, z, spGetGroundOrigHeight(x, z))
				end
			end
		end
		if n == 0 then
			return false, "no heightmap points affected"
		end

		Spring.SetHeightMapFunc(function()
			for i = 1, n do
				spSetHeightMap(curX[i], curZ[i], curH[i])
			end
		end)
		-- keep the ramp when terrain is restored/deformed back towards the original map
		Spring.SetOriginalHeightMapFunc(function()
			for i = 1, n do
				spSetOriginalHeightMap(curX[i], curZ[i], origH[i])
			end
		end)

		Spring.RebuildSmoothMesh(minX, minZ, maxX, maxZ)
		adjustFeaturesInRect(minX, minZ, maxX, maxZ)
		return true, n
	end

	local function isNum(...)
		for i = 1, select("#", ...) do
			if type(select(i, ...)) ~= "number" then
				return false
			end
		end
		return true
	end

	local function createRamp(startX, startZ, endX, endZ, width, smoothWidth)
		smoothWidth = smoothWidth or DEFAULT_SMOOTH_WIDTH
		if not isNum(startX, startZ, endX, endZ, width) then
			return false, "missing parameters"
		end
		if width <= 0 or smoothWidth <= 0 then
			return false, "width and smoothWidth must be > 0"
		end
		if startX == endX and startZ == endZ then
			return false, "start and end must differ"
		end
		local r = width / 2 + smoothWidth
		return applyShape(
			mathMin(startX, endX) - r,
			mathMin(startZ, endZ) - r,
			mathMax(startX, endX) + r,
			mathMax(startZ, endZ) + r,
			makeRamp(startX, startZ, endX, endZ, width, smoothWidth)
		)
	end

	-- Flat plateau at an absolute `height`, blended into the terrain over smoothWidth.
	local function createSquarePlateau(startX, startZ, endX, endZ, width, height, smoothWidth)
		smoothWidth = smoothWidth or DEFAULT_SMOOTH_WIDTH
		if not isNum(startX, startZ, endX, endZ, width, height) then
			return false, "missing parameters"
		end
		if width <= 0 or smoothWidth <= 0 then
			return false, "width and smoothWidth must be > 0"
		end
		if startX == endX and startZ == endZ then
			return false, "start and end must differ"
		end
		local r = width / 2 + smoothWidth
		return applyShape(
			mathMin(startX, endX) - r,
			mathMin(startZ, endZ) - r,
			mathMax(startX, endX) + r,
			mathMax(startZ, endZ) + r,
			makeSquarePlateau(startX, startZ, endX, endZ, width, height, smoothWidth)
		)
	end

	local function createRoundPlateau(cx, cz, radius, height, smoothWidth)
		smoothWidth = smoothWidth or DEFAULT_SMOOTH_WIDTH
		if not isNum(cx, cz, radius, height) then
			return false, "missing parameters"
		end
		if radius <= 0 or smoothWidth <= 0 then
			return false, "radius and smoothWidth must be > 0"
		end
		local r = radius + smoothWidth
		return applyShape(cx - r, cz - r, cx + r, cz + r, makeRoundPlateau(cx, cz, radius, height, smoothWidth))
	end

	-- Same footprint and scaling as map_metal_spot_placer.lua, so `value` matches the `metal`
	-- field of a map_metal_layout.lua spot (e.g. 2.0).
	local METAL_SQUARE_SIZE = 16
	local METAL_FACTOR = 0.43 * 9 / 21

	local function createMetalSpot(x, z, value)
		if not isNum(x, z, value) then
			return false, "missing parameters"
		end
		if value < 0 then
			return false, "value must be >= 0"
		end
		local xIndex = mathFloor(x / METAL_SQUARE_SIZE)
		local zIndex = mathFloor(z / METAL_SQUARE_SIZE)
		local maxXI = Game.mapSizeX / METAL_SQUARE_SIZE - 1
		local maxZI = Game.mapSizeZ / METAL_SQUARE_SIZE - 1
		if xIndex < 0 or zIndex < 0 or xIndex > maxXI or zIndex > maxZI then
			return false, "position outside the map"
		end

		local amount = mathMin(255, value * METAL_FACTOR * 255)
		local n = 0
		for dxi = -2, 2 do
			for dzi = -2, 2 do
				if not (mathAbs(dxi) == 2 and mathAbs(dzi) == 2) then -- skip corners
					local xi, zi = xIndex + dxi, zIndex + dzi
					if xi >= 0 and xi <= maxXI and zi >= 0 and zi <= maxZI then
						Spring.SetMetalAmount(xi, zi, amount)
						n = n + 1
					end
				end
			end
		end
		return true, n
	end

	-- rx, ry, rz are rotations in radians. Returns true, featureID or false, reason.
	local function addFeature(x, z, rx, ry, rz, featureDefName)
		if not isNum(x, z) or type(featureDefName) ~= "string" then
			return false, "missing parameters"
		end
		local featureDef = FeatureDefNames[featureDefName]
		if not featureDef then
			return false, "unknown feature def '" .. featureDefName .. "'"
		end
		if x < 0 or z < 0 or x > Game.mapSizeX or z > Game.mapSizeZ then
			return false, "position outside the map"
		end

		local featureID = Spring.CreateFeature(featureDef.id, x, spGetGroundHeight(x, z), z)
		if not featureID then
			return false, "engine refused to create the feature"
		end
		Spring.SetFeatureRotation(featureID, rx or 0, ry or 0, rz or 0)
		return true, featureID
	end

	-- type (case-insensitive) -> { function, number of positional args }
	local tweakActions = {
		ramp = { createRamp, 6 },
		squareplateau = { createSquarePlateau, 7 },
		roundplateau = { createRoundPlateau, 5 },
		metalspot = { createMetalSpot, 3 },
		feature = { addFeature, 6 },
		addfeature = { addFeature, 6 },
	}

	-- tweakmap, tweakmap1 .. tweakmap29: each is base64 of a lua table
	-- { {type = "ramp", args = {...}}, ... } and is applied in listed order, slots by index.
	local function applyTweakMap()
		-- GetModOptions() is a read-only __index proxy in BAR, so pairs() sees nothing; iterate a copy.
		local modOptions = BAR.GetModOptionsCopy and BAR.GetModOptionsCopy() or Spring.GetModOptions()
		Spring.Echo("[Map Tweak] applyTweakMap called, game frame " .. tostring(Spring.GetGameFrame()))
		local slots = {}
		local seen = {}
		for key, value in pairs(modOptions) do
			if type(key) == "string" and key:lower():find("^tweak") then
				seen[#seen + 1] = key .. "(" .. type(value) .. ", len " .. #tostring(value) .. ")"
			end
			local index = type(key) == "string" and key:match("^tweakmap(%d*)$")
			if index and type(value) == "string" and value ~= "" then
				slots[#slots + 1] = { key = key, index = tonumber(index) or 0, value = value }
			end
		end
		table.sort(seen)
		Spring.Echo("[Map Tweak] tweak* modoptions seen: " .. (#seen > 0 and table.concat(seen, ", ") or "none"))
		Spring.Echo("[Map Tweak] tweakmap slots to apply: " .. #slots)
		table.sort(slots, function(a, b)
			return a.index < b.index
		end)

		for _, slot in ipairs(slots) do
			-- '=' padding is sent as '_' because modoption values can't carry it
			local okDecode, decoded = pcall(string.base64Decode, (slot.value:gsub("_", "=")))
			if not okDecode or type(decoded) ~= "string" then
				Spring.Echo("[Map Tweak] " .. slot.key .. ": base64 decode failed: " .. tostring(decoded))
			else
				Spring.Echo("[Map Tweak] " .. slot.key .. " decoded (" .. #decoded .. " bytes): " .. decoded:sub(1, 200))
				local actions, err = BAR.Utilities.SafeLuaTableParser(decoded)
				if err or type(actions) ~= "table" then
					Spring.Echo("[Map Tweak] " .. slot.key .. ": parse failed: " .. tostring(err))
				else
					Spring.Echo("[Map Tweak] Loading " .. slot.key .. " (" .. #actions .. " actions)")
					for i, action in ipairs(actions) do
						local def = type(action) == "table"
							and type(action.type) == "string"
							and tweakActions[action.type:lower()]
						if not def or type(action.args) ~= "table" then
							Spring.Echo("[Map Tweak] " .. slot.key .. " #" .. i .. ": invalid action (type=" .. tostring(type(action) == "table" and action.type or action) .. ")")
						else
							local label = "[Map Tweak] " .. slot.key .. " #" .. i .. " " .. action.type
							Spring.Echo(label .. ": args " .. table.concat(action.args, ", "))
							local ok, success, info = pcall(def[1], unpack(action.args, 1, def[2]))
							if not ok then
								Spring.Echo(label .. ": error: " .. tostring(success))
							elseif success then
								Spring.Echo(label .. ": ok (" .. tostring(info) .. ")")
							else
								Spring.Echo(label .. ": failed: " .. tostring(info))
							end
						end
					end
				end
			end
		end
		Spring.Echo("[Map Tweak] done")
	end

	function gadget:Initialize()
		Spring.Echo("[Map Tweak] gadget loaded (synced)")
		GG.CreateRamp = createRamp
		GG.CreateSquarePlateau = createSquarePlateau
		GG.CreateRoundPlateau = createRoundPlateau
		GG.CreateMetalSpot = createMetalSpot
		GG.AddFeature = addFeature

		applyTweakMap()
	end

	function gadget:Shutdown()
		GG.CreateRamp = nil
		GG.CreateSquarePlateau = nil
		GG.CreateRoundPlateau = nil
		GG.CreateMetalSpot = nil
		GG.AddFeature = nil
	end

	function gadget:RecvLuaMsg(msg, playerID)
		if
			#msg < PACKET_HEADER_LENGTH
			or string.byte(msg, 1) ~= PH_B1
			or string.sub(msg, 1, PACKET_HEADER_LENGTH) ~= PACKET_HEADER
		then
			return
		end
		if not Spring.IsCheatingEnabled() then
			return
		end

		local params = string.split(msg, ":")
		local startX, startZ = tonumber(params[2]), tonumber(params[3])
		local endX, endZ = tonumber(params[4]), tonumber(params[5])
		local width, smoothWidth = tonumber(params[6]), tonumber(params[7])

		local ok, info = createRamp(startX, startZ, endX, endZ, width, smoothWidth)
		if ok then
			Spring.Echo("[Map Ramp] Created ramp (" .. info .. " heightmap points)")
		else
			Spring.Echo("[Map Ramp] Failed: " .. tostring(info))
		end
	end

else -- UNSYNCED
	local myPlayerID = Spring.GetLocalPlayerID()

	local function ramp(cmd, line, words, playerID)
		if playerID ~= myPlayerID or not Spring.IsCheatingEnabled() then
			return
		end
		if #words < 5 then
			Spring.Echo("[Map Ramp] Usage: /luarules ramp <startX> <startZ> <endX> <endZ> <width> [smoothWidth]")
			return
		end
		for i = 1, 5 do
			if not tonumber(words[i]) then
				Spring.Echo("[Map Ramp] Non-numeric argument: " .. tostring(words[i]))
				return
			end
		end
		local msg = PACKET_HEADER
			.. ":"
			.. table.concat({ words[1], words[2], words[3], words[4], words[5], words[6] or DEFAULT_SMOOTH_WIDTH }, ":")
		Spring.SendLuaRulesMsg(msg)
	end

	function gadget:Initialize()
		gadgetHandler:AddChatAction("ramp", ramp)
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveChatAction("ramp")
	end
end
