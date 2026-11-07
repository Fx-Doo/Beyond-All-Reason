local Helpers = {}
local cylinderCache = {}

function Helpers.GetScriptFunc(unitID, functionName)
	if Spring.GetCOBScriptID(unitID, functionName) then
		return Spring.CallCOBScript
	end
	local env = Spring.UnitScript.GetScriptEnv(unitID)
	if env and env[functionName] then
		return function(uid, fname, ...)
			local scriptEnv = Spring.UnitScript.GetScriptEnv(uid)
			Spring.UnitScript.CallAsUnit(uid, scriptEnv[fname], ...)
		end
	end
	return false
end

function Helpers.IsUnderwater(passengerID, y)
	local height = Spring.GetUnitHeight(passengerID)
	return not height or y + height < 0
end

function Helpers.Distance2D(x1, z1, x2, z2)
	local dx, dz = x1 - x2, z1 - z2
	return math.sqrt(dx * dx + dz * dz)
end

-- Callers currently compact the returned array in place. Preserve this shared
-- per-frame cache behavior during extraction.
function Helpers.GetCachedUnitsInCylinder(cx, cz, radius, allyTeam)
	cz, cx, radius = math.floor(cz / 16) * 16, math.floor(cx / 16) * 16, math.ceil(radius / 16) * 16
	local key = allyTeam .. "," .. cx .. "," .. cz .. "," .. radius
	local cached = cylinderCache[key]
	local frame = Spring.GetGameFrame()
	if cached and cached.frame == frame then
		return cached.units
	end
	local units = Spring.GetUnitsInCylinder(cx, cz, radius, allyTeam)
	cylinderCache[key] = { frame = frame, units = units }
	return units
end

return Helpers
