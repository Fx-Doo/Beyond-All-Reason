local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Target on the move",
		desc = "Adds a command to set a priority attack target",
		author = "Google Frog, adapted by BrainDamage, added priority to Dgun by doo",
		date = "06/05/2013",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

local CMD_UNIT_SET_TARGET_NO_GROUND = GameCMD.UNIT_SET_TARGET_NO_GROUND
local CMD_UNIT_SET_TARGET = GameCMD.UNIT_SET_TARGET
local CMD_UNIT_CANCEL_TARGET = GameCMD.UNIT_CANCEL_TARGET
local CMD_UNIT_SET_TARGET_RECTANGLE = GameCMD.UNIT_SET_TARGET_RECTANGLE

-- Custom command IDs for visual differentiation
local CMD_CURRENT_TARGET = -79701  -- Weapon target crosshair
local CMD_PRIORITY_TARGETS = -79702  -- Priority list target crosshair
local CMD_PRIORITY_DEF_TARGETS = -79703  -- Priority-def target crosshair

if gadgetHandler:IsSyncedCode() then

	local deleteMaxDistance = 30

	local spInsertUnitCmdDesc = Spring.InsertUnitCmdDesc
	local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
	local spSetUnitTarget = Spring.SetUnitTarget
	local spValidUnitID = Spring.ValidUnitID
	local spGetUnitDefID = Spring.GetUnitDefID
	local spGetUnitLosState = Spring.GetUnitLosState
	local spGetUnitTeam = Spring.GetUnitTeam
	local spAreTeamsAllied = Spring.AreTeamsAllied
	local spGetUnitsInRectangle = Spring.GetUnitsInRectangle
	local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
	local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
	local spGetUnitWeaponTarget = Spring.GetUnitWeaponTarget
	local spGetUnitWeaponTryTarget = Spring.GetUnitWeaponTryTarget
	local spGetUnitWeaponTestTarget = Spring.GetUnitWeaponTestTarget
	local spGetUnitWeaponTestRange = Spring.GetUnitWeaponTestRange
	local spGetUnitWeaponHaveFreeLineOfFire = Spring.GetUnitWeaponHaveFreeLineOfFire
	local spGetGroundHeight = Spring.GetGroundHeight
	local spGetAllUnits = Spring.GetAllUnits
	local spGetPlayerInfo = Spring.GetPlayerInfo
	local spGetUnitStates = Spring.GetUnitStates
	local spSetUnitRulesParam = Spring.SetUnitRulesParam

	local tremove = table.remove
	local ensureTable = table.ensureTable
	local max = math.max
	local min = math.min
	local clamp = math.clamp
	local pairsNext = next
	local type = type

	local CMD_STOP = CMD.STOP

	local validUnits = {}
	local unitWeapons = {}
	local unitAlwaysSeen = {}

	local WATERWEAPON = 0
	do
		local allowNonAttackerUnit = { legpede = true } -- Fastpass for units that don't have an attack command for other reasons.

		local function hasTargeting(weapon, canManualFire)
			local weaponDef = WeaponDefs[weapon.weaponDef]
			return weapon.slavedTo == 0
				and weaponDef.type ~= "Shield"
				and not (canManualFire and weaponDef.manualFire)
				and weaponDef.range > 10
		end

		local function canSetTarget(unitDef)
			if (unitDef.canAttack or allowNonAttackerUnit[unitDef.name]) and unitDef.maxWeaponRange > 0 then
				local canManualFire = unitDef.canManualFire
				for _, weapon in pairs(unitDef.weapons) do
					if hasTargeting(weapon, canManualFire) then
						return true
					end
				end
			end
			return false
		end

		-- FIXME: We don't know which weaponDefs have submissile. We can check `nuclear`, for now.
		local function getWeaponType(weapon, canManualFire)
			if hasTargeting(weapon, canManualFire) then
				local weaponDef = WeaponDefs[weapon.weaponDef]
				return weaponDef.waterWeapon and not weaponDef.customParams.nuclear and WATERWEAPON or 1
			else
				return false
			end
		end

		for unitDefID = 1, #UnitDefs do
			local unitDef = UnitDefs[unitDefID]
			if canSetTarget(unitDef) then
				validUnits[unitDefID] = true
				unitWeapons[unitDefID] = table.map(unitDef.weapons, function(weapon, index)
					return getWeaponType(weapon, unitDef.canManualFire), index
				end)
			end
			unitAlwaysSeen[unitDefID] = unitDef.isBuilding or unitDef.speed == 0
		end
	end

	-- Gadget-side tracking for drawing and ignoreStop filtering
	local unitPriorityTargets = {} -- unitID => {target=<unitID or {x,y,z}>, ignoreStop=<bool>}[]
	local priorityDefs = {}         -- unitID => targetDefID (priority targeting by unit type) [DEPRECATED]
	local currentPrioDef = {}       -- unitID => targetDefID (current priority def, replaces priorityDefs)
	local watchedDefs = {}          -- targetDefID => {attackerID1, attackerID2, ...} (track which units watch each def)
	
	local spAddUnitPriorityTarget = Spring.AddUnitPriorityTarget
	local spRemoveUnitPriorityTarget = Spring.RemoveUnitPriorityTarget
	local spClearUnitPriorityTargets = Spring.ClearUnitPriorityTargets
	local spSetUnitToTargetUnitPriorityMult = Spring.SetUnitToTargetUnitPriorityMult

	--------------------------------------------------------------------------------
	-- Commands

	local tooltipText = 'Set a priority attack target,\nto be used when within range\n(not removed by move commands)'

	local unitSetTargetNoGroundCmdDesc = {
		id = CMD_UNIT_SET_TARGET_NO_GROUND,
		type = CMDTYPE.ICON_UNIT_OR_AREA,
		name = 'Set Unit Target',
		action = 'settargetnoground',
		cursor = 'settarget',
		tooltip = tooltipText,
		hidden = true,
		queueing = false,
	}

	local unitSetTargetCircleCmdDesc = {
		id = CMD_UNIT_SET_TARGET,
		type = CMDTYPE.ICON_UNIT_OR_AREA,
		name = 'Set Target', --extra spaces center the 'Set' text
		action = 'settarget',
		cursor = 'settarget',
		tooltip = tooltipText,
		hidden = false,
		queueing = false,
	}

	local unitCancelTargetCmdDesc = {
		id = CMD_UNIT_CANCEL_TARGET,
		type = CMDTYPE.ICON,
		name = 'Cancel Target',
		action = 'canceltarget',
		tooltip = 'Removes top priority target, if set',
		hidden = false,
		queueing = false,
	}



	--------------------------------------------------------------------------------
	-- Target Handling

	local function isAlliedUnit(teamID, unitID)
		local unitTeam = spGetUnitTeam(unitID)
		return unitTeam and spAreTeamsAllied(teamID, unitTeam)
	end

	local function testTargetUnit(unitID, weaponList, target)
		for weaponNum = 1, #weaponList do
			if weaponList[weaponNum] and spGetUnitWeaponTryTarget(unitID, weaponNum, target) then
				return weaponNum
			end
		end
	end

	local function testTargetPos(unitID, weaponList, x, y, z)
		for weaponNum = 1, #weaponList do
			if
				weaponList[weaponNum]
				and spGetUnitWeaponTestTarget(unitID, weaponNum, x, y, z)
				and spGetUnitWeaponTestRange(unitID, weaponNum, x, y, z)
				and spGetUnitWeaponHaveFreeLineOfFire(unitID, weaponNum, nil, nil, nil, x, y, z)
			then
				return weaponNum
			end
		end
	end

	function gadget:Initialize()
		gadgetHandler:RegisterCMDID(CMD_UNIT_SET_TARGET)
		gadgetHandler:RegisterCMDID(CMD_UNIT_CANCEL_TARGET)
		gadgetHandler:RegisterCMDID(CMD_UNIT_SET_TARGET_RECTANGLE)
		gadgetHandler:RegisterCMDID(CMD_UNIT_SET_TARGET_NO_GROUND)
		gadgetHandler:RegisterAllowCommand(CMD_UNIT_SET_TARGET_NO_GROUND)
		gadgetHandler:RegisterAllowCommand(CMD_UNIT_SET_TARGET)
		gadgetHandler:RegisterAllowCommand(CMD_UNIT_SET_TARGET_RECTANGLE)
		gadgetHandler:RegisterAllowCommand(CMD_UNIT_CANCEL_TARGET)

		local allUnits = spGetAllUnits()
		for i = 1, #allUnits do
			local unitID = allUnits[i]
			gadget:UnitCreated(unitID, spGetUnitDefID(unitID), spGetUnitTeam(unitID))
		end
	end

	function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
		if validUnits[unitDefID] then
			spInsertUnitCmdDesc(unitID, unitSetTargetNoGroundCmdDesc)
			spInsertUnitCmdDesc(unitID, unitSetTargetCircleCmdDesc)
			spInsertUnitCmdDesc(unitID, unitCancelTargetCmdDesc)
		end
	end

	function gadget:UnitGiven(unitID, unitDefID, unitTeam)
		-- Clear priority targets when unit changes teams
		unitPriorityTargets[unitID] = nil
		spClearUnitPriorityTargets(unitID)
		spSetUnitRulesParam(unitID, "has_priority_targets", 0)
		SendToUnsynced("targetList", unitID, 0)
		
		-- Clear priority def from watched list
		local oldDefID = currentPrioDef[unitID]
		if oldDefID then
			currentPrioDef[unitID] = nil
			if watchedDefs[oldDefID] then
				for i = #watchedDefs[oldDefID], 1, -1 do
					if watchedDefs[oldDefID][i] == unitID then
						table.remove(watchedDefs[oldDefID], i)
						break
					end
				end
				if #watchedDefs[oldDefID] == 0 then
					watchedDefs[oldDefID] = nil
				end
			end
		end
		SendToUnsynced("targetDef", unitID, nil)
	end

	function gadget:UnitTaken(unitID, unitDefID, unitTeam)
		-- Clear priority targets when unit changes teams
		unitPriorityTargets[unitID] = nil
		spClearUnitPriorityTargets(unitID)
		spSetUnitRulesParam(unitID, "has_priority_targets", 0)
		SendToUnsynced("targetList", unitID, 0)
		
		-- Clear priority def from watched list
		local oldDefID = currentPrioDef[unitID]
		if oldDefID then
			currentPrioDef[unitID] = nil
			if watchedDefs[oldDefID] then
				for i = #watchedDefs[oldDefID], 1, -1 do
					if watchedDefs[oldDefID][i] == unitID then
						table.remove(watchedDefs[oldDefID], i)
						break
					end
				end
				if #watchedDefs[oldDefID] == 0 then
					watchedDefs[oldDefID] = nil
				end
			end
		end
		SendToUnsynced("targetDef", unitID, nil)
	end

	function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam, weaponDefID)
		-- Engine handles cleanup of priority targets on death
		-- Just clear gadget-side tracking
		unitPriorityTargets[unitID] = nil
		SendToUnsynced("targetList", unitID, 0)
		
		-- Clear priority def from watched list
		local oldDefID = currentPrioDef[unitID]
		if oldDefID then
			currentPrioDef[unitID] = nil
			if watchedDefs[oldDefID] then
				for i = #watchedDefs[oldDefID], 1, -1 do
					if watchedDefs[oldDefID][i] == unitID then
						table.remove(watchedDefs[oldDefID], i)
						break
					end
				end
				if #watchedDefs[oldDefID] == 0 then
					watchedDefs[oldDefID] = nil
				end
			end
		end
		SendToUnsynced("targetDef", unitID, nil)
	end


	--------------------------------------------------------------------------------
	-- Command Tracking

	local teamQueryCaches = {}
	local ENEMY_UNITS = -4 -- From UnitAllegiance enum. Includes Gaia and ceasefired targets.

	local function allowTargetUnit(unitID, weaponList, targetID)
		for weaponNum = 1, #weaponList do
			-- This only tests the validity of the target type, not range or other variable things.
			if weaponList[weaponNum] and spGetUnitWeaponTestTarget(unitID, weaponNum, targetID) then
				return true
			end
		end
		return false
	end

	local function allowTargetPos(unitID, weaponList, xyz)
		local x, y, z = xyz[1], xyz[2], xyz[3]
		for weaponNum = 1, #weaponList do
			local weaponType = weaponList[weaponNum]
			-- Quirk: Targets are not adjusted engine-side for water level, unlike Attack commands and weapon aiming.
			if weaponType and spGetUnitWeaponTestTarget(unitID, weaponNum, x, weaponType == WATERWEAPON and y or max(y, 1), z) then
				-- We may or may not adjust this targetY depending on weapon order, which can tend to seem arbitrary.
				if weaponType ~= WATERWEAPON then
					xyz[2] = max(y, 1)
				end
				return true
			end
		end
		return false
	end

	-- Helper: Handle Alt+Click on single unit to set priority by unit type (def)
	local function handleAltSingleUnitDef(unitID, unitTeam, targetID, weaponList)
		if not (spValidUnitID(targetID) and not spAreTeamsAllied(unitTeam, spGetUnitTeam(targetID))) then
			return nil, false  -- Invalid target
		end
		if not allowTargetUnit(unitID, weaponList, targetID) then
			return nil, false  -- Weapon can't target this
		end

		local targetDefID = spGetUnitDefID(targetID)
		local oldDefID = currentPrioDef[unitID]
		
		if oldDefID == targetDefID then
			-- Cancel: same type already prioritized, toggle off
			currentPrioDef[unitID] = nil
			-- Remove this attacker from watched list
			if watchedDefs[oldDefID] then
				for i = #watchedDefs[oldDefID], 1, -1 do
					if watchedDefs[oldDefID][i] == unitID then
						table.remove(watchedDefs[oldDefID], i)
						break
					end
				end
				-- Clean up empty watched def
				if #watchedDefs[oldDefID] == 0 then
					watchedDefs[oldDefID] = nil
				else
					-- Reset mults for remaining watchers
					for _, attackerID in ipairs(watchedDefs[oldDefID]) do
						local enemies = CallAsTeam(unitTeam, spGetAllUnits)
						for i = 1, #enemies do
							local enemyID = enemies[i]
							if spGetUnitDefID(enemyID) == oldDefID and not spAreTeamsAllied(unitTeam, spGetUnitTeam(enemyID)) then
								spSetUnitToTargetUnitPriorityMult(attackerID, enemyID, 1.0)
							end
						end
					end
				end
			end
			SendToUnsynced("targetDef", unitID, nil)
		else
			-- Set: switch to new priority def
			currentPrioDef[unitID] = targetDefID
			
			-- Remove from old def's watched list if switching
			if oldDefID and oldDefID ~= targetDefID then
				if watchedDefs[oldDefID] then
					for i = #watchedDefs[oldDefID], 1, -1 do
						if watchedDefs[oldDefID][i] == unitID then
							table.remove(watchedDefs[oldDefID], i)
							break
						end
					end
					-- Clean up empty watched def
					if #watchedDefs[oldDefID] == 0 then
						watchedDefs[oldDefID] = nil
					else
						-- Reset mults for this def on remaining watchers
						for _, attackerID in ipairs(watchedDefs[oldDefID]) do
							local enemies = CallAsTeam(unitTeam, spGetAllUnits)
							for i = 1, #enemies do
								local enemyID = enemies[i]
								if spGetUnitDefID(enemyID) == oldDefID and not spAreTeamsAllied(unitTeam, spGetUnitTeam(enemyID)) then
									spSetUnitToTargetUnitPriorityMult(attackerID, enemyID, 1.0)
								end
							end
						end
					end
				end
			end
			
			-- Add to new def's watched list
			if not watchedDefs[targetDefID] then
				watchedDefs[targetDefID] = {}
			end
			table.insert(watchedDefs[targetDefID], unitID)
			
			-- Apply priority mult to new unit type
			local enemies = CallAsTeam(unitTeam, spGetAllUnits)
			for i = 1, #enemies do
				local enemyID = enemies[i]
				if spGetUnitDefID(enemyID) == targetDefID and not spAreTeamsAllied(unitTeam, spGetUnitTeam(enemyID)) then
					spSetUnitToTargetUnitPriorityMult(unitID, enemyID, 0.00001)
				end
			end
			
			SendToUnsynced("targetDef", unitID, targetDefID)
		end
		return true, true
	end

	-- Helper: Handle Alt+Click on ground to cancel priority def
	local function handleAltCancelDef(unitID, unitTeam)
		local oldDefID = currentPrioDef[unitID]
		if oldDefID then
			currentPrioDef[unitID] = nil
			-- Remove this attacker from watched list
			if watchedDefs[oldDefID] then
				for i = #watchedDefs[oldDefID], 1, -1 do
					if watchedDefs[oldDefID][i] == unitID then
						table.remove(watchedDefs[oldDefID], i)
						break
					end
				end
				-- Clean up empty watched def and reset mults for remaining watchers
				if #watchedDefs[oldDefID] == 0 then
					watchedDefs[oldDefID] = nil
				else
					for _, attackerID in ipairs(watchedDefs[oldDefID]) do
						local enemies = CallAsTeam(unitTeam, spGetAllUnits)
						for i = 1, #enemies do
							local enemyID = enemies[i]
							if spGetUnitDefID(enemyID) == oldDefID and not spAreTeamsAllied(unitTeam, spGetUnitTeam(enemyID)) then
								spSetUnitToTargetUnitPriorityMult(attackerID, enemyID, 1.0)
							end
						end
					end
				end
			end
			SendToUnsynced("targetDef", unitID, nil)
		end
		return true
	end

	-- Helper: Collect targets from rectangle or circle area
	local function collectAreaTargets(unitID, unitTeam, cmdParams, nParams, weaponList, ignoreStop, cmdOptions)
		if not cmdOptions.internal then
			SendToUnsynced("settarget_line_sound", unitTeam, -1, unitID, CMD_UNIT_SET_TARGET)
		end

		local targets = nil
		if nParams == 6 then
			-- Rectangle
			local top, bot, left, right
			if cmdParams[1] < cmdParams[4] then
				left = cmdParams[1]
				right = cmdParams[4]
			else
				left = cmdParams[4]
				right = cmdParams[1]
			end
			if cmdParams[3] < cmdParams[6] then
				top = cmdParams[3]
				bot = cmdParams[6]
			else
				bot = cmdParams[6]
				top = cmdParams[3]
			end
			local teamCache = ensureTable(teamQueryCaches, spGetUnitAllyTeam(unitID))
			local hash = left + top + right + bot
			targets = teamCache[hash]
			if not targets then
				targets = CallAsTeam(unitTeam, spGetUnitsInRectangle, left, top, right, bot, ENEMY_UNITS)
				teamCache[hash] = targets
			end
		elseif nParams == 4 then
			-- Circle
			local teamCache = ensureTable(teamQueryCaches, spGetUnitAllyTeam(unitID))
			local hash = -(cmdParams[1] + cmdParams[2] + cmdParams[3] + cmdParams[4])
			targets = teamCache[hash]
			if not targets then
				targets = CallAsTeam(unitTeam, spGetUnitsInCylinder, cmdParams[1], cmdParams[3], cmdParams[4], ENEMY_UNITS)
				teamCache[hash] = targets
			end
		end

		local targetList = {}
		local targetCount = 0
		if targets and targets[1] then
			for i = 1, #targets do
				local target = targets[i]
				if allowTargetUnit(unitID, weaponList, target) then
					targetCount = targetCount + 1
					targetList[targetCount] = {target = target, ignoreStop = ignoreStop}
				end
			end
		end
		return targetList, targetCount
	end

	-- Helper: Collect ground position target
	local function collectGroundPosTarget(unitID, cmdID, cmdParams, weaponList, ignoreStop)
		if cmdID == CMD_UNIT_SET_TARGET_NO_GROUND then
			return nil, 0  -- Not allowed for this command
		end

		local target = cmdParams
		if target[2] > spGetGroundHeight(target[1], target[3]) then
			target[2] = spGetGroundHeight(target[1], target[3])
		end
		if allowTargetPos(unitID, weaponList, target) then
			return {{target = target, ignoreStop = ignoreStop}}, 1
		end
		return nil, 0
	end

	-- Helper: Collect single unit target
	local function collectSingleUnitTarget(unitID, unitTeam, cmdParams, weaponList, ignoreStop)
		local target = cmdParams[1]
		if spValidUnitID(target) and not spAreTeamsAllied(unitTeam, spGetUnitTeam(target)) then
			if allowTargetUnit(unitID, weaponList, target) then
				return {{target = target, ignoreStop = ignoreStop}}, 1
			end
		end
		return nil, 0
	end

	-- Helper: Add collected targets to engine priority list
	local function addTargetsToEngine(unitID, unitTeam, targetList, append)
		if not targetList or #targetList == 0 then
			return false
		end

		-- Clear previous targets if not appending
		if not append then
			spClearUnitPriorityTargets(unitID)
			unitPriorityTargets[unitID] = {}
		end

		for i = 1, #targetList do
			local targetData = targetList[i]
			local target = targetData.target
			
			-- Call Spring API
			if type(target) == "number" then
				spAddUnitPriorityTarget(unitID, target)
			else
				spAddUnitPriorityTarget(unitID, nil, target[1], target[2], target[3])
			end
			
			-- Store in tracking table for all target types
			table.insert(unitPriorityTargets[unitID], targetData)
		end

		-- Send updated list to unsynced for drawing
		SendToUnsynced("targetList", unitID, 1, unitPriorityTargets[unitID])
		return true
	end

	-- Helper: Clear all priority targets
	local function clearPriorityTargets(unitID)
		spClearUnitPriorityTargets(unitID)
		unitPriorityTargets[unitID] = nil
		spSetUnitRulesParam(unitID, "has_priority_targets", 0)
		SendToUnsynced("targetList", unitID, 0)
	end

	-- Helper: Cancel all targets and priority def
	local function handleCancelAllTargets(unitID, unitTeam)
		-- Clear priority targets
		spClearUnitPriorityTargets(unitID)
		unitPriorityTargets[unitID] = nil
		spSetUnitRulesParam(unitID, "has_priority_targets", 0)
		SendToUnsynced("targetList", unitID, 0)
		
		-- Clear priority def
		local oldDefID = currentPrioDef[unitID]
		if oldDefID then
			currentPrioDef[unitID] = nil
			if watchedDefs[oldDefID] then
				for i = #watchedDefs[oldDefID], 1, -1 do
					if watchedDefs[oldDefID][i] == unitID then
						table.remove(watchedDefs[oldDefID], i)
						break
					end
				end
				if #watchedDefs[oldDefID] == 0 then
					watchedDefs[oldDefID] = nil
				end
			end
		end
		SendToUnsynced("targetDef", unitID, nil)
	end

	-- Helper: Cancel single unit target by ID
	local function handleCancelTargetUnit(unitID, unitTeam, targetID)
		if unitPriorityTargets[unitID] then
			for index = #unitPriorityTargets[unitID], 1, -1 do
				if unitPriorityTargets[unitID][index].target == targetID then
					table.remove(unitPriorityTargets[unitID], index)
					spRemoveUnitPriorityTarget(unitID, index - 1)  -- 0-based index
					break
				end
			end
			if #unitPriorityTargets[unitID] == 0 then
				clearPriorityTargets(unitID)
			else
				SendToUnsynced("targetList", unitID, 1, unitPriorityTargets[unitID])
			end
		end
	end

	-- Helper: Cancel priority def via alt-click
	local function handleCancelTargetDef(unitID, unitTeam)
		local targetDefID = currentPrioDef[unitID]
		if targetDefID then
			currentPrioDef[unitID] = nil
			-- Remove from watched list
			if watchedDefs[targetDefID] then
				for i = #watchedDefs[targetDefID], 1, -1 do
					if watchedDefs[targetDefID][i] == unitID then
						table.remove(watchedDefs[targetDefID], i)
						break
					end
				end
				-- Clean up empty watched def and reset mults for remaining watchers
				if #watchedDefs[targetDefID] == 0 then
					watchedDefs[targetDefID] = nil
				else
					for _, attackerID in ipairs(watchedDefs[targetDefID]) do
						local enemies = CallAsTeam(unitTeam, spGetAllUnits)
						for i = 1, #enemies do
							local enemyID = enemies[i]
							if spGetUnitDefID(enemyID) == targetDefID and not spAreTeamsAllied(unitTeam, spGetUnitTeam(enemyID)) then
								spSetUnitToTargetUnitPriorityMult(attackerID, enemyID, 1.0)
							end
						end
					end
				end
			end
			SendToUnsynced("targetDef", unitID, nil)
		end
	end

	-- Helper: Cancel ground position target by proximity
	local function handleCancelTargetPos(unitID, unitTeam, cancelPos)
		if unitPriorityTargets[unitID] then
			local deleteMaxDistance = 30
			for index = #unitPriorityTargets[unitID], 1, -1 do
				local targetData = unitPriorityTargets[unitID][index]
				if type(targetData.target) == "table" then
					local dx = targetData.target[1] - cancelPos[1]
					local dy = targetData.target[2] - cancelPos[2]
					local dz = targetData.target[3] - cancelPos[3]
					if math.sqrt(dx*dx + dy*dy + dz*dz) < deleteMaxDistance then
						table.remove(unitPriorityTargets[unitID], index)
						spRemoveUnitPriorityTarget(unitID, index - 1)  -- 0-based index
					end
				end
			end
			if #unitPriorityTargets[unitID] == 0 then
				clearPriorityTargets(unitID)
			else
				SendToUnsynced("targetList", unitID, 1, unitPriorityTargets[unitID])
			end
		end
	end

	local function processCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions)
		local nParams = #cmdParams

		if nParams == 4 and cmdParams[4] < 1 then
			cmdParams[4] = nil
			nParams = 3
		end

		if cmdID == CMD_UNIT_SET_TARGET_NO_GROUND or cmdID == CMD_UNIT_SET_TARGET or cmdID == CMD_UNIT_SET_TARGET_RECTANGLE then
			local weaponList = unitWeapons[unitDefID]
			local append = cmdOptions.shift or false
			local ignoreStop = cmdOptions.ctrl
			local isAltTarget = cmdOptions.alt

			-- Handle Alt+Single Unit: Set/Cancel priority def by unit type
			if isAltTarget and nParams == 1 then
				local success, isValid = handleAltSingleUnitDef(unitID, unitTeam, cmdParams[1], weaponList)
				if isValid then
					return true
				else
					SendToUnsynced("failCommand", unitTeam)
					return false
				end
			end

			-- Handle Alt+Ground: Cancel priority def
			if isAltTarget and nParams == 3 then
				handleAltCancelDef(unitID, unitTeam)
				return true  -- Consume command
			end

			-- Normal priority targets: collect based on parameter count
			local targetList, targetCount = nil, 0

			if nParams > 3 then
				-- Area target (rectangle or circle)
				targetList, targetCount = collectAreaTargets(unitID, unitTeam, cmdParams, nParams, weaponList, ignoreStop, cmdOptions)
			elseif nParams == 3 then
				-- Ground position target
				targetList, targetCount = collectGroundPosTarget(unitID, cmdID, cmdParams, weaponList, ignoreStop)
				if targetCount == 0 then
					SendToUnsynced("failCommand", unitTeam)
					return false
				end
			elseif nParams == 1 then
				-- Single unit target
				targetList, targetCount = collectSingleUnitTarget(unitID, unitTeam, cmdParams, weaponList, ignoreStop)
			end

			-- Add targets or clear if no valid targets
			if addTargetsToEngine(unitID, unitTeam, targetList, append) then
				-- Targets added successfully
			elseif not append then
				-- Invalid target and not appending: clear all
				clearPriorityTargets(unitID)
			end

			return true
		elseif cmdID == CMD_UNIT_CANCEL_TARGET then
			if nParams == 0 then
				-- Cancel all targets and def
				handleCancelAllTargets(unitID, unitTeam)
			elseif nParams == 1 then
				if cmdOptions.alt then
					-- Alt-click: remove priority def
					handleCancelTargetDef(unitID, unitTeam)
				else
					-- Remove specific unit target by ID
					handleCancelTargetUnit(unitID, unitTeam, cmdParams[1])
				end
			elseif nParams == 3 then
				-- Remove ground position target by proximity
				handleCancelTargetPos(unitID, unitTeam, cmdParams)
			end
			return true
		end
	end

	function gadget:UnitCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions, cmdTag)
		if cmdID == CMD_STOP and unitPriorityTargets[unitID] then
			-- Handle CMD_STOP: remove non-ignoreStop targets
			local nonIgnoreCount = 0
			for i = #unitPriorityTargets[unitID], 1, -1 do
				if not unitPriorityTargets[unitID][i].ignoreStop then
					table.remove(unitPriorityTargets[unitID], i)
					spRemoveUnitPriorityTarget(unitID, i - 1)  -- 0-based index
				else
					nonIgnoreCount = nonIgnoreCount + 1
				end
			end
			if nonIgnoreCount == 0 then
				spClearUnitPriorityTargets(unitID)
				unitPriorityTargets[unitID] = nil
				spSetUnitRulesParam(unitID, "has_priority_targets", 0)
				SendToUnsynced("targetList", unitID, 0)
			else
				SendToUnsynced("targetList", unitID, 1, unitPriorityTargets[unitID])
			end
		end
	end

	function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions, cmdTag, playerID, fromSynced, fromLua, fromInsert)
		-- Accepts: CMD_UNIT_SET_TARGET_NO_GROUND, CMD_UNIT_SET_TARGET, CMD_UNIT_SET_TARGET_RECTANGLE, CMD_UNIT_CANCEL_TARGET.
		if validUnits[unitDefID] then
			processCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
		end
		return false -- consume command
	end

	function gadget:RecvLuaMsg(msg, playerID)
		if msg == "settarget_line" then
			local _, _, _, teamID = spGetPlayerInfo(playerID)
			if teamID then
				SendToUnsynced("settarget_line_sound", teamID, playerID, nil, CMD_UNIT_SET_TARGET)
			end
		end
	end

	function gadget:GameFrame(frame)
		teamQueryCaches = {}
	end


else	-- UNSYNCED

	local math_min = math.min
	local pairsNext = next

	local glVertex = gl.Vertex
	local glPushAttrib = gl.PushAttrib
	local glLineStipple = gl.LineStipple
	local glDepthTest = gl.DepthTest
	local glLineWidth = gl.LineWidth
	local glColor = gl.Color
	local glBeginEnd = gl.BeginEnd
	local glPopAttrib = gl.PopAttrib
	local glTranslate = gl.Translate
	local glRotate = gl.Rotate
	local GL_LINE_STRIP = GL.LINE_STRIP
	local GL_LINES = GL.LINES

	local spGetUnitPosition = Spring.GetUnitPosition
	local spValidUnitID = Spring.ValidUnitID
	local spGetMyAllyTeamID = Spring.GetMyAllyTeamID
	local spGetMyTeamID = Spring.GetMyTeamID
	local spIsUnitSelected = Spring.IsUnitSelected
	local spGetSpectatingState = Spring.GetSpectatingState
	local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
	local spGetUnitTeam = Spring.GetUnitTeam
	local spPlaySoundFile = Spring.PlaySoundFile
	local spSetActiveCommand = Spring.SetActiveCommand
	local spAssignMouseCursor = Spring.AssignMouseCursor
	local spGetUnitWeaponTarget = Spring.GetUnitWeaponTarget
	local spSetCustomCommandDrawData = Spring.SetCustomCommandDrawData
	local spAddWorldIcon = Spring.AddWorldIcon
	local spGetSelectedUnits = Spring.GetSelectedUnits
	local spGetUnitDefID = Spring.GetUnitDefID
	local spGetAllUnits = Spring.GetAllUnits
	local spIsUnitInView = Spring.IsUnitInView

	local myAllyTeam = spGetMyAllyTeamID()
	local myTeam = spGetMyTeamID()
	local mySpec, fullview = spGetSpectatingState()

	-- Colors for different target types
	local colorPriorityTarget = {1, 1, 0, 0.8}   -- Yellow for priority list targets
	local colorPriorityDef = {1, 0.35, 0, 0.8}  -- Bright orange for priority-def type units
	local colorNonPriority = {1, 0, 0, 0.8}      -- Red for non-priority weapon targets
	local lineWidth = 1.4
	local crosshairSize = 40

	local unitsFullDrawCount = 100

	-- Gadget-side tracking of priority targets and priority-defs
	local unitPriorityTargets = {} -- unitID => {target=<unitID or {x,y,z}>, ignoreStop=<bool>}[]
	local currentPrioDef = {}       -- unitID => targetDefID (current priority def)
	local targetDefUnits = {}       -- targetDefID => {unitID, unitID, ...} (enemy units matching watched def types)

	local drawTarget = {}
	local drawAllTargets = {}

	function gadget:Initialize()
		gadgetHandler:AddChatAction("targetdrawteam", handleTargetDrawEvent, "toggles drawing targets for units, params: teamID doDraw")
		gadgetHandler:AddChatAction("targetdrawunit", handleUnitTargetDrawEvent, "toggles drawing targets for units, params: unitID")
		gadgetHandler:AddSyncAction("targetList", handleTargetListEvent)
		gadgetHandler:AddSyncAction("targetDef", handleTargetDefEvent)
		gadgetHandler:AddSyncAction("failCommand", handleFailCommand)

		-- Register custom cursors for each target type
		spAssignMouseCursor("attack", "cursorattack", false)                  -- Regular attack cursor
		spAssignMouseCursor("settarget", "cursorsettarget", false)            -- Priority list cursor
		spAssignMouseCursor("prioritydef", "cursorprioritydef", false)        -- Priority-def cursor (ORANGE)
		
		--show the command in the queue
		local queueColour = { 1, 0.75, 0, 0.3 }
		spSetCustomCommandDrawData(CMD_UNIT_SET_TARGET, "settarget", queueColour, true)
		spSetCustomCommandDrawData(CMD_UNIT_SET_TARGET_NO_GROUND, "attack", queueColour, true)
		spSetCustomCommandDrawData(CMD_UNIT_SET_TARGET_RECTANGLE, "settarget", queueColour, true)
		
		-- Set custom command draw data for our new commands (using cursor names)
		spSetCustomCommandDrawData(CMD_CURRENT_TARGET, "attack", queueColour, true)
		spSetCustomCommandDrawData(CMD_PRIORITY_TARGETS, "settarget", queueColour, true)
		spSetCustomCommandDrawData(CMD_PRIORITY_DEF_TARGETS, "prioritydef", queueColour, true)
	end

	function gadget:PlayerChanged(playerID)
		myAllyTeam = spGetMyAllyTeamID()
		myTeam = spGetMyTeamID()
		mySpec, fullview = spGetSpectatingState()
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveChatAction("targetdrawteam")
		gadgetHandler:RemoveChatAction("targetdrawunit")
		gadgetHandler:RemoveSyncAction("targetList")
		gadgetHandler:RemoveSyncAction("targetDef")
		gadgetHandler:RemoveSyncAction("failCommand")
	end

	function handleFailCommand(_, teamID)
		if teamID == myTeam and not mySpec then
			spPlaySoundFile("FailedCommand", 0.75, "ui")
			spSetActiveCommand('settargetnoground')
		end
	end

	function handleTargetListEvent(_, unitID, hasTargets, targetListData)
		if hasTargets == 0 then
			unitPriorityTargets[unitID] = nil
		else
			-- targetListData is the full priority target list from gadget
			unitPriorityTargets[unitID] = targetListData
		end
	end

	function handleTargetDefEvent(_, unitID, targetDefID)
		if targetDefID then
			currentPrioDef[unitID] = targetDefID
			-- Scan enemies of this defID once and cache them
			if not targetDefUnits[targetDefID] then
				local allUnits = spGetAllUnits()
				local matches = {}
				for _, enemyID in ipairs(allUnits) do
					if CallAsTeam(myTeam, spValidUnitID, enemyID) and CallAsTeam(myTeam, spGetUnitDefID, enemyID) == targetDefID then
						table.insert(matches, enemyID)
					end
				end
				targetDefUnits[targetDefID] = matches
			end
		else
			currentPrioDef[unitID] = nil
		end
	end

	function handleUnitTargetDrawEvent(_, _, params)
		drawTarget[tonumber(params[1])] = true
		return true
	end

	function handleTargetDrawEvent(_, _, params)
		local teamID = tonumber(params[1])
		local doDraw = tonumber(params[2]) ~= 0
		drawAllTargets[teamID] = doDraw
		return true
	end

	-- Cached draw data (built in GameFrame, rendered in DrawWorld)
	local cachedWeaponLines = {}    -- {startPos={x,y,z}, endPos={x,y,z}, color={r,g,b,a}}[]
	local cachedCrosshairs = {}     -- {pos={x,y,z}, type="weapon"|"priority"|"def"}[]

	local function isTargetInPriorityList(unitID, target)
		local priorityList = unitPriorityTargets[unitID]
		if not priorityList then return false end
		
		for _, targetData in ipairs(priorityList) do
			local listTarget = targetData.target
			if type(target) == "number" and type(listTarget) == "number" then
				if target == listTarget then return true end
			elseif type(target) == "table" and type(listTarget) == "table" then
				if target[1] == listTarget[1] and target[2] == listTarget[2] and target[3] == listTarget[3] then
					return true
				end
			end
		end
		return false
	end

	local function isTargetMatchesPriorityDef(target, priorityDefID)
		if type(target) ~= "number" then return false end
		if not spValidUnitID(target) then return false end
		local targetDefID = spGetUnitDefID(target)
		return targetDefID == priorityDefID
	end

	local function getTargetColor(ownerUnitID, target)
		-- Check priority list first (yellow)
		if isTargetInPriorityList(ownerUnitID, target) then
			return colorPriorityTarget
		end
		
		-- Check priority def (orange)
		local priorityDefID = currentPrioDef[ownerUnitID]
		if priorityDefID and isTargetMatchesPriorityDef(target, priorityDefID) then
			return colorPriorityDef
		end
		
		-- Default red for other targets
		return colorNonPriority
	end

	local function drawCrosshair(x, y, z, color, size)
		glColor(color)
		-- Vertical line
		glVertex(x, y + size, z)
		glVertex(x, y - size, z)
		-- Horizontal line (X axis)
		glVertex(x + size, y, z)
		glVertex(x - size, y, z)
		-- Horizontal line (Z axis)
		glVertex(x, y, z + size)
		glVertex(x, y, z - size)
	end

	local function getWeaponTargetInfo(unitID, weaponNum)
		local targetType, isUserTarget, value1, value2, value3 = spGetUnitWeaponTarget(unitID, weaponNum)
		
		if not targetType or targetType == 0 then
			return nil -- No target
		elseif targetType == 1 then
			-- Unit target: returns unitID
			return { type = "unit", unitID = value1, isUserTarget = isUserTarget }
		elseif targetType == 2 then
			-- Position target: returns {x, y, z} as a table
			return { type = "pos", pos = value1, isUserTarget = isUserTarget }
		elseif targetType == 3 then
			-- Projectile target: returns projectileID
			return { type = "projectile", projectileID = value1, isUserTarget = isUserTarget }
		end
		return nil
	end

	local function buildDrawCache()
		cachedWeaponLines = {}
		cachedCrosshairs = {}
		local drawnCrosshairs = {}
		
		local selectedUnits = spGetSelectedUnits()
		if not selectedUnits or #selectedUnits == 0 then return end
		
		-- Phase 1: Build weapon target lines
		for _, unitID in ipairs(selectedUnits) do
			if (fullview or spGetUnitAllyTeam(unitID) == myAllyTeam) then
				local x1, y1, z1 = CallAsTeam(myTeam, spGetUnitPosition, unitID, false, true)
				if x1 then
					local unitDefID = spGetUnitDefID(unitID)
					local unitDef = UnitDefs[unitDefID]
					if unitDef and unitDef.weapons then
						for weaponNum = 1, #unitDef.weapons do
							local targetInfo = getWeaponTargetInfo(unitID, weaponNum)
							if targetInfo then
								local targetX, targetY, targetZ, target, isValid
								
								if targetInfo.type == "unit" then
									if CallAsTeam(myTeam, spValidUnitID, targetInfo.unitID) then
										targetX, targetY, targetZ = CallAsTeam(myTeam, spGetUnitPosition, targetInfo.unitID, false, true)
										target = targetInfo.unitID
										isValid = true
									end
								elseif targetInfo.type == "pos" then
									targetX = targetInfo.pos[1]
									targetY = targetInfo.pos[2]
									targetZ = targetInfo.pos[3] or 0
									target = targetInfo.pos
									isValid = true
								end
								
								if isValid and targetX then
									local color = getTargetColor(unitID, target)
									table.insert(cachedWeaponLines, {
										startPos = {x1, y1, z1},
										endPos = {targetX, targetY, targetZ},
										color = color
									})
									
									-- Only add weapon target crosshair if it's not already covered by priority or priority def
									local isInPriorityList = isTargetInPriorityList(unitID, target)
									local priorityDefID = currentPrioDef[unitID]
									local isInPriorityDef = priorityDefID and isTargetMatchesPriorityDef(target, priorityDefID)
									
									if not isInPriorityList and not isInPriorityDef then
										local key = targetX .. "," .. targetY .. "," .. targetZ
										if not drawnCrosshairs[key] then
											drawnCrosshairs[key] = true
											table.insert(cachedCrosshairs, {pos = {targetX, targetY, targetZ}, type = "weapon"})
										end
									end
								end
							end
						end
					end
				end
			end
		end
		
		-- Phase 2: Add crosshairs for priority targets (only for selected/draw-enabled units)
		for unitID, targets in pairsNext, unitPriorityTargets do
			if (fullview or spGetUnitAllyTeam(unitID) == myAllyTeam) then
				local shouldDraw = spIsUnitSelected(unitID) or drawTarget[unitID] or drawAllTargets[spGetUnitTeam(unitID)]
				if shouldDraw then
					for i, targetData in ipairs(targets) do
						local target = targetData.target
						local targetX, targetY, targetZ, isValid
						
						if type(target) == "number" then
							if CallAsTeam(myTeam, spValidUnitID, target) then
								targetX, targetY, targetZ = CallAsTeam(myTeam, spGetUnitPosition, target, false, true)
								isValid = true
							end
						else
							targetX = target[1]
							targetY = target[2]
							targetZ = target[3]
							isValid = true
						end
						
						if isValid and targetX then
							local key = targetX .. "," .. targetY .. "," .. targetZ
							if not drawnCrosshairs[key] then
								drawnCrosshairs[key] = true
								table.insert(cachedCrosshairs, {pos = {targetX, targetY, targetZ}, type = "priority"})
							end
						end
					end
				end
			end
		end
		
		-- Phase 3: Add crosshairs for priority-def targets (only for selected units' priority defs)
		for _, unitID in ipairs(selectedUnits) do
			if (fullview or spGetUnitAllyTeam(unitID) == myAllyTeam) then
				local priorityDefID = currentPrioDef[unitID]
				if priorityDefID and targetDefUnits[priorityDefID] then
					local unitList = targetDefUnits[priorityDefID]
					for _, targetID in ipairs(unitList) do
						-- Validate unit still exists, is in view, and has correct defID
						if CallAsTeam(myTeam, spValidUnitID, targetID) and spIsUnitInView(targetID) then
							local currentDefID = CallAsTeam(myTeam, spGetUnitDefID, targetID)
							if currentDefID == priorityDefID then
								local targetX, targetY, targetZ = CallAsTeam(myTeam, spGetUnitPosition, targetID, false, true)
								if targetX then
									local key = targetX .. "," .. targetY .. "," .. targetZ
									if not drawnCrosshairs[key] then
										drawnCrosshairs[key] = true
										table.insert(cachedCrosshairs, {pos = {targetX, targetY, targetZ}, type = "def"})
									end
								end
							end
						end
					end
				end
			end
		end
	end

	local function drawSelectedUnitWeaponTargetLines()
		-- Draw cached weapon target lines
		for _, line in ipairs(cachedWeaponLines) do
			glColor(line.color)
			glVertex(line.startPos[1], line.startPos[2], line.startPos[3])
			glVertex(line.endPos[1], line.endPos[2], line.endPos[3])
		end
	end

	local function drawTargetCrosshairs()
		-- Debug: log cache size
		if #cachedCrosshairs > 0 then
		end
		
		-- Draw cached crosshairs with different command IDs based on type
		for _, crosshair in ipairs(cachedCrosshairs) do
			if crosshair and crosshair.pos then
				local cmdID = CMD_CURRENT_TARGET  -- Default
				
				if crosshair.type == "weapon" then
					-- Regular weapon target
					cmdID = CMD_CURRENT_TARGET
				elseif crosshair.type == "priority" then
					-- Priority list target
					cmdID = CMD_PRIORITY_TARGETS
				elseif crosshair.type == "def" then
					-- Priority-def target
					cmdID = CMD_PRIORITY_DEF_TARGETS
				end
				
				spAddWorldIcon(cmdID, crosshair.pos[1], crosshair.pos[2], crosshair.pos[3])
			end
		end
	end

	local function drawSelectedUnitWeaponTargets()
		-- This is now called inside glBeginEnd - only draws lines from cache
		drawSelectedUnitWeaponTargetLines()
	end

	local function drawDecorations()
		-- Line drawing is now handled by drawWeaponTargets() for weapon targets
		-- This function is kept for future priority target visualization if needed
	end

	local function drawWeaponTargets()
		if Spring.IsGUIHidden() then
			return
		end
		
		-- Rebuild draw cache based on current selections
		buildDrawCache()
		
		-- Draw lines to weapon targets
		glPushAttrib(GL.LINE_BITS)
		glLineStipple("any")
		glDepthTest(false)
		glLineWidth(lineWidth)
		
		glBeginEnd(GL_LINES, function()
			drawSelectedUnitWeaponTargets()
		end)
		
		glColor(1, 1, 1, 1)
		glLineStipple(false)
		glPopAttrib()
		
		-- Draw crosshair icons for all targets (with type-based coloring)
		drawTargetCrosshairs()
	end

	function gadget:DrawWorld()
		if Spring.IsGUIHidden() then
			return
		end

		-- Draw weapon targets with lines and crosshairs
		drawWeaponTargets()

		-- Draw priority target lists
		if fullview then
			drawDecorations()
		else
			CallAsTeam(myTeam, drawDecorations)
		end
	end

	function gadget:Update()
		-- Continuously update active command to display correct cursor
		-- Default to settarget command which shows settarget cursor
		spSetActiveCommand(CMD_UNIT_SET_TARGET)
	end

	function gadget:UnitCreated(unitID, unitDefID, unitTeam)
		-- Add to any targetDefUnits cache that matches this defID
		if targetDefUnits[unitDefID] then
			table.insert(targetDefUnits[unitDefID], unitID)
		end
	end

	function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
		-- Remove from any targetDefUnits cache that matches this defID
		if targetDefUnits[unitDefID] then
			for i = #targetDefUnits[unitDefID], 1, -1 do
				if targetDefUnits[unitDefID][i] == unitID then
					table.remove(targetDefUnits[unitDefID], i)
					break
				end
			end
			-- Clean up empty cache entry
			if #targetDefUnits[unitDefID] == 0 then
				targetDefUnits[unitDefID] = nil
			end
		end
	end

	function gadget:UnitTaken(unitID, unitDefID, unitTeam)
		-- Same as destroyed—unit changes teams, remove from cache
		if targetDefUnits[unitDefID] then
			for i = #targetDefUnits[unitDefID], 1, -1 do
				if targetDefUnits[unitDefID][i] == unitID then
					table.remove(targetDefUnits[unitDefID], i)
					break
				end
			end
			-- Clean up empty cache entry
			if #targetDefUnits[unitDefID] == 0 then
				targetDefUnits[unitDefID] = nil
			end
		end
	end

	function gadget:DrawScreen()
		-- Cursors are now managed by the active command system
		-- No need for manual cursor switching
	end

end
