local CMD_TURN_TOWARDS = 30103
local UNIT_ID = 7
local PARAMS = { 100, 0, 200 }

local function loadGadget(mode)
	local state = { count = 1, id = CMD_TURN_TOWARDS, tag = 10, created = 0, resumed = 0, logs = {} }
	local env = {
		gadget = {},
		gadgetHandler = {
			IsSyncedCode = function()
				return true
			end,
			RegisterCMDID = function(_, id)
				state.registered = id
			end,
			RegisterAllowCommand = function(_, id)
				state.allowed = id
			end,
		},
		GameCMD = { TURN_TOWARDS = CMD_TURN_TOWARDS },
		CMDTYPE = { ICON_MAP = 5 },
		UnitDefs = { [1] = { speed = 60 }, [2] = { speed = 0 } },
		Spring = {
			GetUnitCurrentCommand = function()
				return state.id, 0, state.tag
			end,
			GetUnitCommandCount = function()
				return state.count
			end,
			GetAllUnits = function()
				return { UNIT_ID }
			end,
			GetUnitDefID = function()
				return 1
			end,
			InsertUnitCmdDesc = function(unitID, desc)
				state.descriptor = { unitID, desc.id }
			end,
			Log = function(...)
				state.logs[#state.logs + 1] = { ... }
			end,
		},
		coroutine = {
			create = function(body)
				state.created = state.created + 1
				if mode == "complete" then
					body = function() end
				elseif mode == "error" then
					body = function()
						error("turn failed")
					end
				end
				return coroutine.create(body)
			end,
			resume = function(co)
				state.resumed = state.resumed + 1
				return coroutine.resume(co)
			end,
			status = coroutine.status,
			yield = coroutine.yield,
		},
	}
	setmetatable(env, { __index = _G })
	local chunk = assert(loadfile("luarules/gadgets/unit_turn_towards.lua"))
	setfenv(chunk, env)
	chunk()

	local function fallback(cmdID)
		return { env.gadget:CommandFallback(UNIT_ID, 1, 0, cmdID or CMD_TURN_TOWARDS, PARAMS, {}, state.tag) }
	end
	return env.gadget, state, fallback
end

describe("turn towards command", function()
	it("registers the command for existing and newly created mobile units", function()
		local gadget, state = loadGadget()
		gadget:Initialize()
		assert.equals(CMD_TURN_TOWARDS, state.registered)
		assert.equals(CMD_TURN_TOWARDS, state.allowed)
		assert.same({ UNIT_ID, CMD_TURN_TOWARDS }, state.descriptor)
		state.descriptor = nil
		gadget:UnitCreated(8, 2)
		assert.is_nil(state.descriptor)
		gadget:UnitCreated(9, 1)
		assert.same({ 9, CMD_TURN_TOWARDS }, state.descriptor)
	end)

	it("starts only on fallback and resumes once per frame without restarting", function()
		local gadget, state, fallback = loadGadget()
		gadget:GameFrame()
		assert.equals(0, state.created)
		assert.same({ false }, fallback(20))
		assert.same({ true, false }, fallback())
		assert.same({ true, false }, fallback())
		gadget:GameFrame()
		gadget:GameFrame()
		assert.equals(1, state.created)
		assert.equals(2, state.resumed)
	end)

	it("does not start when another command is already queued behind it", function()
		local _, state, fallback = loadGadget()
		state.count = 2
		assert.same({ true, true }, fallback())
		assert.equals(0, state.created)
	end)

	it("stops on an appended command and stays stopped until fallback finishes it", function()
		local gadget, state, fallback = loadGadget()
		fallback()
		gadget:GameFrame()
		state.count = 2
		gadget:GameFrame()
		state.count = 1
		gadget:GameFrame()
		assert.equals(1, state.resumed)
		assert.same({ true, true }, fallback())
	end)

	it("also stops if fallback observes the appended command before the next frame", function()
		local gadget, state, fallback = loadGadget()
		fallback()
		gadget:GameFrame()
		state.count = 2
		assert.same({ true, true }, fallback())
		gadget:GameFrame()
		assert.equals(1, state.resumed)
	end)

	it("stops when the command is removed or replaced, even with the same command ID", function()
		for _, replacement in ipairs({ 20, CMD_TURN_TOWARDS }) do
			local gadget, state, fallback = loadGadget()
			fallback()
			gadget:GameFrame()
			state.id = replacement
			state.tag = 11
			gadget:GameFrame()
			assert.equals(1, state.resumed)
			if replacement == CMD_TURN_TOWARDS then
				fallback()
				assert.equals(2, state.created)
			end
		end
		local gadget, state, fallback = loadGadget()
		fallback()
		state.id = nil
		state.count = 0
		gadget:GameFrame()
		assert.equals(0, state.resumed)
	end)

	it("finishes a returned coroutine without resuming or starting it again", function()
		local gadget, state, fallback = loadGadget("complete")
		fallback()
		gadget:GameFrame()
		gadget:GameFrame()
		assert.equals(1, state.resumed)
		assert.same({ true, true }, fallback())
		assert.equals(1, state.created)
	end)

	it("logs coroutine errors and finishes the failed command", function()
		local gadget, state, fallback = loadGadget("error")
		fallback()
		gadget:GameFrame()
		gadget:GameFrame()
		assert.equals(1, #state.logs)
		assert.matches("turn failed", state.logs[1][3])
		assert.same({ true, true }, fallback())
	end)

	it("drops coroutine state for destroyed units", function()
		local gadget, state, fallback = loadGadget()
		fallback()
		gadget:UnitDestroyed(UNIT_ID)
		gadget:GameFrame()
		assert.equals(0, state.resumed)
	end)

	it("tracks each unit independently", function()
		local gadget, state, fallback = loadGadget()
		fallback()
		gadget:CommandFallback(8, 1, 0, CMD_TURN_TOWARDS, PARAMS, {}, state.tag)
		gadget:GameFrame()
		assert.equals(2, state.resumed)
		gadget:UnitDestroyed(UNIT_ID)
		gadget:GameFrame()
		assert.equals(3, state.resumed)
	end)

	it("accepts only map positions for mobile units", function()
		local gadget = loadGadget()
		assert.is_true(gadget:AllowCommand(UNIT_ID, 1, 0, CMD_TURN_TOWARDS, PARAMS))
		assert.is_false(gadget:AllowCommand(UNIT_ID, 2, 0, CMD_TURN_TOWARDS, PARAMS))
		assert.is_false(gadget:AllowCommand(UNIT_ID, 1, 0, CMD_TURN_TOWARDS, { 100 }))
		assert.is_false(gadget:AllowCommand(UNIT_ID, 1, 0, CMD_TURN_TOWARDS, { "100", 0, 200 }))
	end)
end)
