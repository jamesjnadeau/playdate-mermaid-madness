-- InstructionsScene.lua
-- How-to-play walkthrough reached from the Title screen. Extends GameScene
-- so the player's own ship is sailing on real water while they practice --
-- each step asks them to actually perform that input before the next one is
-- shown, rather than just reading static text. Every control has two
-- directions (crank one way / the other, Up / Down, Left / Right), and each
-- gets its own step, so the player exercises both instead of whichever's
-- more convenient.
--
-- Opens with a "do you know how to sail?" gate (STEP_ASK_KNOW_SAILING /
-- STEP_CONFIRM_KNOW_SAILING): Ⓐ ("yes") advances ask -> confirm -> this
-- walkthrough; Ⓑ ("no") on either sends the player to the remedial
-- SailingInstructions lesson instead -- see onAButtonDown/onBButtonDown.
-- Once past the gate, Ⓑ exits back to Title at any point, regardless of step.

import "scripts/utilities/Config"
import "scripts/utilities/Utils"
import "scripts/enemies/EnemyDummy"
import "scenes/GameScene"

local gfx <const> = playdate.graphics

---@class InstructionsScene : GameScene
---@field step number index into InstructionsScene.prompts; STEP_DONE once finished
---@field stepProgress number generic counter for the current step -- seconds for the crank steps, a scored-hit count for the broadside steps, a press count for the rest; reset to 0 by advanceStep
---@field outOfRangeSeconds number seconds the broadside steps' target has been continuously out of range, see tickGame/onBroadsideButtonDown; reset to 0 by advanceStep
InstructionsScene = class("InstructionsScene").extends(GameScene) or InstructionsScene

-- The walkthrough opens with a "do you know how to sail?" gate (see
-- onAButtonDown/onBButtonDown below): Ⓐ ("yes") advances ask -> confirm ->
-- the normal walkthrough; Ⓑ ("no") on either sends the player to
-- SailingInstructions instead. Everything from STEP_CRANK_FORWARD down is
-- the pre-existing walkthrough, just renumbered to make room.
InstructionsScene.STEP_ASK_KNOW_SAILING     = 1
InstructionsScene.STEP_CONFIRM_KNOW_SAILING = 2

-- "Forward"/"backward" just label the two signs of crank delta (positive vs
-- negative) -- not a claim about which is physically clockwise.
InstructionsScene.STEP_CRANK_FORWARD  = 3
InstructionsScene.STEP_CRANK_BACKWARD = 4
InstructionsScene.STEP_TRIM_UP        = 5
InstructionsScene.STEP_TRIM_DOWN      = 6
InstructionsScene.STEP_BROADSIDE_LEFT  = 7
InstructionsScene.STEP_BROADSIDE_RIGHT = 8
InstructionsScene.STEP_DONE            = 9

InstructionsScene.prompts = {
	[InstructionsScene.STEP_ASK_KNOW_SAILING]     = "Do you know how to sail?",
	[InstructionsScene.STEP_CONFIRM_KNOW_SAILING] = "Are you sure?\nYou'll be lost to the sea if you don't know how to sail.",
	[InstructionsScene.STEP_CRANK_FORWARD]  = "Crank one way to steer the helm",
	[InstructionsScene.STEP_CRANK_BACKWARD] = "Now crank the other way",
	[InstructionsScene.STEP_TRIM_UP]        = "Press Up to let out the sail",
	[InstructionsScene.STEP_TRIM_DOWN]      = "Now press Down to trim it in",
	[InstructionsScene.STEP_BROADSIDE_LEFT]  = "Press Left to charge a broadside",
	[InstructionsScene.STEP_BROADSIDE_RIGHT] = "Now press Right to charge a broadside",
}

-- Shown in place of the progress count once the broadside steps' target has
-- been out of range for a while -- see stepSubline/Config.INSTRUCTIONS_OUT_OF_RANGE_HINT_SECONDS.
InstructionsScene.OUT_OF_RANGE_MESSAGE = "Out of range -- close the distance!"
InstructionsScene.OUT_OF_RANGE_HINT_MESSAGE = "Look for a triangle marker on your screen showing where the enemy is"

---@param sceneProperties? table skipKnowSailingPrompt (default false) skips straight to STEP_CRANK_FORWARD, bypassing the ask/confirm gate -- set by SailingInstructions once the player's proven they can sail
function InstructionsScene:resetGame(sceneProperties)
	InstructionsScene.super.resetGame(self, sceneProperties)
	sceneProperties = sceneProperties or {}
	self.step = sceneProperties.skipKnowSailingPrompt
		and InstructionsScene.STEP_CRANK_FORWARD
		or InstructionsScene.STEP_ASK_KNOW_SAILING
	self.stepProgress = 0
	self.outOfRangeSeconds = 0
end

function InstructionsScene:advanceStep()
	self.step = self.step + 1
	self.stepProgress = 0
	self.outOfRangeSeconds = 0
end

-- Pins wind speed to Config.SHIP_MAX_SPEED for the whole walkthrough (see
-- GameScene:fixedWindSpeed) so every step plays out at a predictable, known
-- speed instead of whatever the normal wander-over-time wind happened to
-- roll -- wind direction still wanders normally, this only pins speed.
---@return number
function InstructionsScene:fixedWindSpeed()
	return Config.SHIP_MAX_SPEED
end

-- Which side the current step is teaching, or nil if it's not a broadside
-- step at all -- shared by input handling, the dummy spawner, and rendering.
---@return string? "port" | "starboard"
function InstructionsScene:currentBroadsideSide()
	if self.step == InstructionsScene.STEP_BROADSIDE_LEFT then return "port" end
	if self.step == InstructionsScene.STEP_BROADSIDE_RIGHT then return "starboard" end
	return nil
end

-- ---------------------------------------------------------------------------
-- Input (wraps GameScene.buildSharedInputHandler so the ship really steers/
-- trims/fires -- see each handler for the extra step-progress bookkeeping
-- layered on top).
-- ---------------------------------------------------------------------------

local shared = GameScene.buildSharedInputHandler(GameScene.current)
local sharedCranked = shared.cranked
local sharedUpButtonDown = shared.upButtonDown
local sharedDownButtonDown = shared.downButtonDown
local sharedLeftButtonDown = shared.leftButtonDown
local sharedRightButtonDown = shared.rightButtonDown

shared.cranked = function(change, acceleratedChange)
	sharedCranked(change, acceleratedChange)
	local s = GameScene.current()
	if s then
		---@cast s InstructionsScene
		s:onCranked(change)
	end
end

shared.upButtonDown = function()
	sharedUpButtonDown()
	local s = GameScene.current()
	if s then
		---@cast s InstructionsScene
		s:onTrimButtonDown("up")
	end
end

shared.downButtonDown = function()
	sharedDownButtonDown()
	local s = GameScene.current()
	if s then
		---@cast s InstructionsScene
		s:onTrimButtonDown("down")
	end
end

shared.leftButtonDown = function()
	sharedLeftButtonDown()
	local s = GameScene.current()
	if s then
		---@cast s InstructionsScene
		s:onBroadsideButtonDown("port")
	end
end

shared.rightButtonDown = function()
	sharedRightButtonDown()
	local s = GameScene.current()
	if s then
		---@cast s InstructionsScene
		s:onBroadsideButtonDown("starboard")
	end
end

shared.AButtonDown = function()
	local s = GameScene.current()
	if s then
		---@cast s InstructionsScene
		s:onAButtonDown()
	end
end

shared.BButtonDown = function()
	local s = GameScene.current()
	if s then
		---@cast s InstructionsScene
		s:onBButtonDown()
	end
end

InstructionsScene.inputHandler = shared

-- Ⓐ ("yes") on the ask/confirm gate steps advances ask -> confirm -> the
-- normal walkthrough (STEP_CONFIRM_KNOW_SAILING + 1 == STEP_CRANK_FORWARD by
-- construction, so a plain advanceStep works for both). No-op on every other
-- step -- there's nothing else for Ⓐ to do during the walkthrough itself.
function InstructionsScene:onAButtonDown()
	if self.step == InstructionsScene.STEP_ASK_KNOW_SAILING
		or self.step == InstructionsScene.STEP_CONFIRM_KNOW_SAILING then
		self:advanceStep()
	end
end

-- Ⓑ ("no") on the ask/confirm gate steps sends the player to the remedial
-- SailingInstructions lesson instead of the normal walkthrough; everywhere
-- else Ⓑ keeps its original meaning of exiting to Title at any point.
function InstructionsScene:onBButtonDown()
	if self.step == InstructionsScene.STEP_ASK_KNOW_SAILING
		or self.step == InstructionsScene.STEP_CONFIRM_KNOW_SAILING then
		Noble.transition(SailingInstructions)
		return
	end
	Noble.transition(TitleScene)
end

-- Crank input has no discrete "press", so each crank step clears once the
-- player has spent Config.INSTRUCTIONS_CRANK_SECONDS actively turning it the
-- required direction (sign of `change`) rather than after a fixed count.
-- `cranked` fires roughly once per update frame while the crank is moving,
-- so counting calls * Config.DT approximates seconds spent cranking.
---@param change number
function InstructionsScene:onCranked(change)
	if change == 0 then return end
	local matches
	if self.step == InstructionsScene.STEP_CRANK_FORWARD then
		matches = change > 0
	elseif self.step == InstructionsScene.STEP_CRANK_BACKWARD then
		matches = change < 0
	else
		return
	end
	if not matches then return end
	self.stepProgress = self.stepProgress + Config.DT
	if self.stepProgress >= Config.INSTRUCTIONS_CRANK_SECONDS then self:advanceStep() end
end

---@param direction string "up" | "down"
function InstructionsScene:onTrimButtonDown(direction)
	local wantStep = direction == "up" and InstructionsScene.STEP_TRIM_UP or InstructionsScene.STEP_TRIM_DOWN
	if self.step ~= wantStep then return end
	self.stepProgress = self.stepProgress + 1
	if self.stepProgress >= Config.INSTRUCTIONS_TRIM_PRESSES then self:advanceStep() end
end

-- Only credits progress once a hit is actually scored -- a bare press no
-- longer counts. "Scored" here means the press finds a locked-on, in-range
-- target (self:pickTarget, inherited from GameScene): charge/aim spread
-- could still make the real shot miss, and this is a tutorial, not a
-- marksmanship test, so being properly lined up is treated as good enough.
-- Out of range presses earn nothing; tickGame's continuous range tracking
-- below is what drives the "get closer" / "look for the triangle" hints so
-- the player isn't left pressing into silence.
---@param side string "port" | "starboard"
function InstructionsScene:onBroadsideButtonDown(side)
	if self:currentBroadsideSide() ~= side then return end
	if not self:pickTarget(side) then return end

	self.outOfRangeSeconds = 0
	self.stepProgress = self.stepProgress + 1
	if self.stepProgress >= Config.INSTRUCTIONS_BROADSIDE_PRESSES then self:advanceStep() end
end

-- ---------------------------------------------------------------------------
-- Broadside practice: a stationary EnemyDummy that can't chase or ram back,
-- spawned on whichever side the current step is teaching (so it's always in
-- range of the button being taught) and kept respawning if destroyed, so the
-- player always has something to lock onto while pressing that button.
-- ---------------------------------------------------------------------------

-- Footprint the instruction card could occupy at its largest (any prompt, or
-- the out-of-range hint message, each wrapped to Config.INSTRUCTIONS_TEXT_BOX_MAX_WIDTH)
-- -- used as a fixed exclusion zone for dummy placement below rather than
-- matching drawInstructionText's live box exactly, since spawn logic
-- shouldn't need to reach into rendering to size text.
---@return number width
---@return number height
function InstructionsScene:instructionBoxFootprint()
	local maxWidth = Config.INSTRUCTIONS_TEXT_BOX_MAX_WIDTH
	local promptW, promptH = 0, 0
	for _, prompt in pairs(InstructionsScene.prompts) do
		local w, h = gfx.getTextSizeForMaxWidth(prompt, maxWidth)
		if w > promptW then promptW = w end
		if h > promptH then promptH = h end
	end
	local hintW, hintH = gfx.getTextSizeForMaxWidth(InstructionsScene.OUT_OF_RANGE_HINT_MESSAGE, maxWidth)

	local boxW = math.max(promptW, hintW) + Config.INSTRUCTIONS_TEXT_BOX_PADDING_X * 2
	local boxH = promptH + Config.INSTRUCTIONS_TEXT_LINE_GAP + hintH + Config.INSTRUCTIONS_TEXT_BOX_PADDING_Y * 2
	return boxW, boxH
end

-- Whether a dummy spawned at this angle/distance from the ship (which is
-- always screen-center, see GameScene:cameraOrigin -- world and screen
-- offsets from the ship are identical) would land under or too close to the
-- instruction card in the top-right corner.
---@param ang number degrees
---@param dist number
---@return boolean
function InstructionsScene:screenOffsetHitsInstructionBox(ang, dist)
	local hx, hy = Utils.heading(ang)
	local sx = Config.SCREEN_W / 2 + hx * dist
	local sy = Config.SCREEN_H / 2 + hy * dist
	local boxW, boxH = self:instructionBoxFootprint()
	local margin = Config.ENEMY_RADIUS -- keep the dummy's own hull clear of the card too, not just its center point
	local left = Config.SCREEN_W - Config.INSTRUCTIONS_TEXT_BOX_MARGIN_RIGHT - boxW - margin
	local bottom = Config.INSTRUCTIONS_TEXT_BOX_TOP + boxH + margin
	return sx >= left and sy <= bottom
end

-- Degree offsets from the ship's forward heading to try the dummy at, in
-- order -- all strictly between 0 and 180 so every candidate stays on the
-- same side of the ship (GameScene:pickTarget's cross-product side test),
-- just as the ship's heading was at spawn time. 90 (dead broadside, the
-- natural "beam" position) is tried first; the rest are fallbacks for
-- dodging the instruction card (see screenOffsetHitsInstructionBox below) --
-- spread across the valid half-circle rather than a single fixed fallback,
-- since the card's screen position is fixed but which offset lands clear of
-- it depends on the ship's current heading. A class field (not a local) so
-- tests can verify the side-preserving property directly.
InstructionsScene.BROADSIDE_ANGLE_OFFSETS = { 90, 45, 135, 20, 160 }

function InstructionsScene:spawnDummyTarget()
	local ship = self.ship
	local side = self:currentBroadsideSide()
	local sign = side == "starboard" and 1 or -1
	local dist = Config.INSTRUCTIONS_DUMMY_DISTANCE

	-- Falls back to the first (default, dead-broadside) candidate if every
	-- offset hits the card -- a visual overlap is a far smaller problem than
	-- spawning the target on the wrong side, which the old "reflect through
	-- screen-center" fallback did (a 180 degree rotation flips the
	-- cross-product sign, silently moving the dummy to the *other* side --
	-- see GameScene:pickTarget -- so it could never be locked onto with the
	-- very button this step was teaching).
	local offsets = InstructionsScene.BROADSIDE_ANGLE_OFFSETS
	local ang = Utils.wrapDeg(ship.heading + sign * offsets[1])
	for _, offset in ipairs(offsets) do
		local candidate = Utils.wrapDeg(ship.heading + sign * offset)
		if not self:screenOffsetHitsInstructionBox(candidate, dist) then
			ang = candidate
			break
		end
	end

	local hx, hy = Utils.heading(ang)
	local ex, ey = ship.x + hx * dist, ship.y + hy * dist
	local facing = Utils.angleTo(ex, ey, ship.x, ship.y)
	self.enemies[#self.enemies + 1] = EnemyDummy(ex, ey, facing)
end

-- Plain distance to the current broadside step's dummy, ignoring
-- GameScene:pickTarget's cross-product side test -- that test is sensitive
-- to the ship's *current* heading, which can drift after the dummy spawns
-- (nothing stops the player from still cranking during a broadside step),
-- so using it here could flag a target that's sitting right next to the
-- ship as "out of range" just because the ship turned. The literal "out of
-- range" hint text should mean literal range, not side.
---@return boolean
function InstructionsScene:currentDummyInRange()
	local dummy = self.enemies[1]
	if not dummy then return false end
	return Utils.dist(self.ship.x, self.ship.y, dummy.x, dummy.y) <= Config.TARGET_RANGE
end

function InstructionsScene:tickGame()
	InstructionsScene.super.tickGame(self)

	local side = self:currentBroadsideSide()
	if not side then return end

	if #self.enemies == 0 then self:spawnDummyTarget() end

	-- Tracked every tick (not just on button press) so "continues to not be
	-- in range" reflects actual elapsed time, even if the player pauses
	-- between attempts -- see onBroadsideButtonDown/stepSubline/
	-- shouldFlashOffscreenIndicator.
	if self:currentDummyInRange() then
		self.outOfRangeSeconds = 0
	else
		self.outOfRangeSeconds = self.outOfRangeSeconds + Config.DT
	end
end

-- Once the broadside target's been out of range long enough, blink its
-- off-screen indicator (see GameScene:drawOffscreenArrows) instead of the
-- base "last enemy left" rule -- with only ever one dummy alive, that base
-- rule would be true (and so flashing) the instant it goes off-screen at
-- all, well before the hint is meant to kick in.
---@param __group table unused -- the hint isn't tied to which group, just whether the current step's target has been out of range long enough
---@return boolean
function InstructionsScene:shouldFlashOffscreenIndicator(__group)
	return self.outOfRangeSeconds >= Config.INSTRUCTIONS_OUT_OF_RANGE_HINT_SECONDS
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- The second line under the current step's prompt: normally a progress
-- count, but on a broadside step with the target out of range, this swaps to
-- a "get closer" nudge and then (past Config.INSTRUCTIONS_OUT_OF_RANGE_HINT_SECONDS)
-- a pointer at the flashing off-screen indicator -- see tickGame/
-- shouldFlashOffscreenIndicator.
---@return string
function InstructionsScene:stepSubline()
	if self.step == InstructionsScene.STEP_ASK_KNOW_SAILING
		or self.step == InstructionsScene.STEP_CONFIRM_KNOW_SAILING then
		return "Ⓐ Yes    Ⓑ No"
	end
	local side = self:currentBroadsideSide()
	if side then
		if self.outOfRangeSeconds >= Config.INSTRUCTIONS_OUT_OF_RANGE_HINT_SECONDS then
			return InstructionsScene.OUT_OF_RANGE_HINT_MESSAGE
		elseif self.outOfRangeSeconds > 0 then
			return InstructionsScene.OUT_OF_RANGE_MESSAGE
		end
		return string.format("%d / %d", self.stepProgress, Config.INSTRUCTIONS_BROADSIDE_PRESSES)
	elseif self.step == InstructionsScene.STEP_CRANK_FORWARD or self.step == InstructionsScene.STEP_CRANK_BACKWARD then
		return string.format("%.1fs / %.1fs", self.stepProgress, Config.INSTRUCTIONS_CRANK_SECONDS)
	elseif self.step == InstructionsScene.STEP_TRIM_UP or self.step == InstructionsScene.STEP_TRIM_DOWN then
		return string.format("%d / %d", self.stepProgress, Config.INSTRUCTIONS_TRIM_PRESSES)
	end
	return ""
end

-- Drawn top-right, above the ship (which -- like every GameScene -- sits
-- camera-locked at screen center), so the water, wake, and practice dummy
-- stay visible underneath while the player works through each step. The
-- prompt/subline pair sits on a white rounded-rect card (sized to fit
-- whichever text is currently longest, each line wrapped to
-- Config.INSTRUCTIONS_TEXT_BOX_MAX_WIDTH since the out-of-range hint is long)
-- so it stays legible over the water instead of floating bare -- see
-- Config.INSTRUCTIONS_TEXT_BOX_*.
function InstructionsScene:drawInstructionText()
	local prompt = InstructionsScene.prompts[self.step] or "You're ready to sail!"
	local subline = InstructionsScene.prompts[self.step] and self:stepSubline() or nil

	local maxWidth = Config.INSTRUCTIONS_TEXT_BOX_MAX_WIDTH
	local padX = Config.INSTRUCTIONS_TEXT_BOX_PADDING_X
	local padY = Config.INSTRUCTIONS_TEXT_BOX_PADDING_Y
	local lineGap = Config.INSTRUCTIONS_TEXT_LINE_GAP

	local promptW, promptH = gfx.getTextSizeForMaxWidth(prompt, maxWidth)
	local boxW, boxH = promptW, promptH
	local sublineW, sublineH = 0, 0
	if subline then
		sublineW, sublineH = gfx.getTextSizeForMaxWidth(subline, maxWidth)
		boxW = math.max(boxW, sublineW)
		boxH = boxH + lineGap + sublineH
	end
	boxW = boxW + padX * 2
	boxH = boxH + padY * 2

	local boxX = Config.SCREEN_W - Config.INSTRUCTIONS_TEXT_BOX_MARGIN_RIGHT - boxW
	local boxY = Config.INSTRUCTIONS_TEXT_BOX_TOP
	local radius = Config.INSTRUCTIONS_TEXT_BOX_RADIUS

	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(boxX, boxY, boxW, boxH, radius)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRoundRect(boxX, boxY, boxW, boxH, radius)

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	local textX = boxX + padX
	local textY = boxY + padY
	gfx.drawTextInRect(prompt, textX, textY, promptW, promptH, nil, nil, kTextAlignment.center)
	if subline then
		gfx.drawTextInRect(subline, textX, textY + promptH + lineGap, sublineW, sublineH, nil, nil, kTextAlignment.center)
	end

	-- Misleading during the ask/confirm gate steps, where Ⓑ means "no", not
	-- "exit" -- see onBButtonDown.
	if self.step > InstructionsScene.STEP_CONFIRM_KNOW_SAILING then
		gfx.drawTextAligned("Ⓑ to exit", Config.SCREEN_W / 2, Config.SCREEN_H - 16, kTextAlignment.center)
	end
end

function InstructionsScene:render()
	InstructionsScene.super.render(self)
	self:drawInstructionText()
end
