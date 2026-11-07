-- Run from the repository root: lua common/testing/transport_handlers_test.lua
local definitions = {
	[1] = {
		canFly = true, isTransport = true, customParams = {},
		transportCapacity = 4, transportMass = 1000, transportSize = 4,
		minTransportSize = 0, minTransportMass = 0, loadingRadius = 128,
	},
	[2] = { customParams = {}, modCategories = {}, xsize = 2, mass = 200, speed = 1 },
	[3] = { customParams = { cantbeautoloaded = "1" }, modCategories = { hover = true }, xsize = 4, mass = 500 },
}
UnitDefs = definitions
local teams, defIDs = { [10] = 1, [11] = 1, [20] = 1, [21] = 2 }, {
	[10] = 1, [11] = 1, [20] = 2, [21] = 3,
}
local positions = { [10] = { 0, 100, 0 }, [11] = { 0, 100, 0 },
	[20] = { 0, 0, 0 }, [21] = { 40, 0, 0 } }
local attached, rules, commands, moves, effects = {}, {}, {}, {}, {}
local frame, speed, stunned, built = 0, 0, false, false
local function rule(id, key)
	return rules[id] and rules[id][key]
end
local function setRule(id, key, value)
	rules[id] = rules[id] or {}
	rules[id][key] = value
end
Spring = {
	GetUnitDefID = function(id) return defIDs[id] end,
	GetUnitTeam = function(id) return teams[id] end,
	GetUnitAllyTeam = function(id) return teams[id] end,
	AreTeamsAllied = function(a, b) return a == b end,
	GetUnitIsBeingBuilt = function() return built end,
	GetUnitIsDead = function() return false end,
	ValidUnitID = function(id) return defIDs[id] ~= nil end,
	GetUnitIsStunned = function() return stunned end,
	GetUnitVelocity = function() return 0, 0, 0, speed end,
	GetUnitHeight = function(id) return defIDs[id] and 10 end,
	GetUnitLosState = function() return { los = true } end,
	GetUnitPosition = function(id) return unpack(positions[id]) end,
	GetUnitTransporter = function(id) return attached[id] end,
	GetUnitIsTransporting = function(id)
		local passengers = {}
		for passenger, transporter in pairs(attached) do
			if transporter == id then passengers[#passengers + 1] = passenger end
		end
		table.sort(passengers)
		return passengers
	end,
	GetUnitRulesParam = rule,
	SetUnitRulesParam = setRule,
	GetGameFrame = function() return frame end,
	GetGroundHeight = function() return 0 end,
	GetUnitsInCylinder = function() return { 20 } end,
	SetUnitMoveGoal = function(...) moves[#moves + 1] = { ... } end,
	SpawnCEG = function(...) effects[#effects + 1] = { ... } end,
	UnitAttach = function(transporter, passenger, piece, forced)
		assert(forced == true)
		attached[passenger] = transporter
	end,
	UnitDetach = function(passenger) attached[passenger] = nil end,
	SetUnitPosition = function(id, x, y, z) positions[id] = { x, y, z } end,
	GetCOBScriptID = function() return nil end,
	GetModOptions = function() return { beta_tractorbeam = "spiced" } end,
	GetAllUnits = function() return { 10, 11, 20, 21 } end,
	GetAllyTeamList = function() return { 1, 2 } end,
	GetUnitCommands = function(id, count)
		if count == 0 then return 0 end
		return commands[id] or {}
	end,
	SetCustomCommandDrawData = function() end,
	MoveCtrl = { Disable = function() end },
	Echo = function(message) error(message) end,
	UnitScript = {},
}
local settings = { ALLOW_ENEMY_LOAD_MODE = 4, MIN_CONSECUTIVE_FRAMES_TO_LOAD_ENEMY = 2 }
VFS = {
	Include = function(path)
		if path == "tractor_beams_temp_defs/transporter_defs_spiced.lua" then return settings end
		return dofile(path)
	end,
}
local Helpers = dofile("common/upgets/transport_helpers.lua")
local api = {
	Helpers = Helpers,
	GetPassengerSize = function(id) return defIDs[id] == 3 and 2 or 1 end,
	CanPassengerFitInTransporter = function(id, passenger, definition, size, queued)
		return size + (queued or 0) + (rule(id, "transporterUsedSeats") or 0) <= 4
	end,
	IsTransportFull = function(id, queued)
		return (rule(id, "transporterUsedSeats") or 0) + (queued or 0) >= 4
	end,
	EnablePassenger = function() end,
}
local loads = {}
local function load(id, name, passenger)
	loads[#loads + 1] = { id, passenger }
	setRule(passenger, "inLoadAnim", id)
	setRule(id, "canUnload", 0)
end
Spring.UnitScript.GetScriptEnv = function(id)
	return {
		PerformLoad = function(passenger) load(id, "PerformLoad", passenger) end,
		PerformUnload = function() end,
	}
end
Spring.UnitScript.CallAsUnit = function(id, fn, ...) return fn(...) end

assert(Helpers.Distance2D(0, 0, 3, 4) == 5)
assert(Helpers.IsUnderwater(20, -11))
assert(not Helpers.IsUnderwater(20, -10))
local cached = Helpers.GetCachedUnitsInCylinder(0, 0, 32, 1)
assert(cached == Helpers.GetCachedUnitsInCylinder(1, 1, 32, 1))
frame = 1
assert(cached ~= Helpers.GetCachedUnitsInCylinder(0, 0, 32, 1))

local Tractor = dofile("luarules/gadgets/transport_handlers/tractorBeamTransportation.lua")
local function newTractor(id, mode)
	return Tractor.New({
		transporterID = id, transporterDefID = 1, api = api,
		settings = { ALLOW_ENEMY_LOAD_MODE = mode, MIN_CONSECUTIVE_FRAMES_TO_LOAD_ENEMY = 2 },
		distance = Helpers.Distance2D, isUnderwater = Helpers.IsUnderwater,
		load = load, unload = function() end,
	})
end
local handler, other = newTractor(10, 4), newTractor(11, 4)
assert(handler:GetUpdateInterval() == 1)
assert(not handler:CanBeAutoClaimed(21))
assert(handler:CanMoveToTransporter(21, -1))
assert(not handler:CanMoveToTransporter(20, -1))
assert(not handler:InLoadRange(0, -1, 0, 0, 0, 0))
assert(handler:InUnloadRange(0, 100, 0, 32, 0, 0))
assert(not handler:InUnloadRange(0, 100, 0, 33, 0, 0))
assert(handler:CanFit(20, 2, { 21 }))
setRule(10, "transporterUsedSeats", 2)
assert(not handler:CanFit(20, 2, { 21 }))
setRule(10, "transporterUsedSeats", 0)
assert(handler:CanBeTransportedDynamic(20, 2, 0, 1))
built = true
assert(not handler:CanBeTransportedDynamic(20, 2, 0, 1))
built = false
assert(not handler:CanBeTransportedNow(21, 2, 0, 0, 0, 0, 100, 0))
assert(not handler:CanBeTransportedNow(21, 2, 0, 0, 0, 0, 100, 0))
assert(handler:CanBeTransportedNow(21, 2, 0, 0, 0, 0, 100, 0))
assert(other.enemyProgress[21] == nil)
handler:CanBeTransportedNow(21, 2, 0, 0, 0, 0, 100, 0)
handler:ClaimRemoved(21)
assert(handler.enemyProgress[21] == nil)
handler:CanBeTransportedNow(21, 2, 0, 0, 0, 0, 100, 0)
speed = 1
handler:CanBeTransportedNow(21, 2, 0, 0, 0, 0, 100, 0)
assert(handler.enemyProgress[21] == nil)
speed = 0
stunned = true
assert(handler:CanBeTransportedNow(21, 2, 100, 0, 0, 0, 100, 0))
stunned = false
handler = newTractor(10, 5)
local moveCount = #moves
handler:ApproachPassenger(21)
assert(#moves == moveCount)
handler:ApproachPassenger(20)
assert(#moves == moveCount + 1)

local Basic = dofile("luarules/gadgets/transport_handlers/basicTransportation.lua")
local basic = Basic.New({ transporterID = 10, transporterDefID = 1, api = api })
assert(basic:CanFit(20, 2, { 21 }))
definitions[1].transportCapacity = 2
assert(not basic:CanFit(20, 2, { 21 }))
definitions[1].transportCapacity = 4
basic:ExecuteLoad(20)
assert(attached[20] == 10)
assert(basic:CanFit(21, 3, { 20 })) -- attached claims must not count twice
basic:ExecuteUnloadAll(10, 0, 20)
assert(attached[20] == nil and positions[20][1] == 10)

GG = { TransportAPI = api }
Game = { mapSizeX = 1024, mapSizeZ = 1024, Commands = { ReissueOrder = function() end } }
CMD = { LOAD_UNITS = 75, LOAD_ONTO = 76, UNLOAD_UNIT = 81, UNLOAD_UNITS = 80 }
gadget = {}
gadgetHandler = {
	IsSyncedCode = function() return true end,
	RegisterAllowCommand = function() end,
}
dofile(arg[1] or "luarules/gadgets/game_transportation_coordinator.lua")
gadget:Initialize()
setRule(10, "canUnload", 1)
setRule(10, "transporterSeats", 4)
positions[20] = { 0, 0, 0 }
commands[10] = { { id = 39751, params = { 0, 0, 0, 128 } } }
local before = #loads
gadget:CommandFallback(10, 1, 1, 39751, { 0, 0, 0, 128 }, {}, 1)
assert(#loads == before + 1 and loads[#loads][2] == 20)
gadget:UnitGiven(10, 1, 1, 1)
gadget:UnitDestroyed(10, 1, 1)
print("transport handler tests passed")
