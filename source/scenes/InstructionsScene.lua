-- InstructionsScene.lua
-- How-to-play walkthrough reached from the Title screen. Extends GameScene
-- so the player's own ship is sailing on real water while they practice --
-- each step asks them to actually perform that input before the next one is
-- shown, rather than just reading static text. Every control has two
-- directions (crank one way / the other, Up / Down, Left / Right), and each
-- gets its own step, so the player exercises both instead of whichever's
-- more convenient. Ⓑ exits back to Title at any point, regardless of step.

import "scripts/Config"
import "scripts/Utils"
import "scripts/EnemyDummy"
import "scenes/GameScene"

local gfx <const> = playdate.graphics

---@class InstructionsScene : GameScene
---@field step number index into InstructionsScene.prompts; STEP_DONE once finished
---@field stepProgress number generic counter for the current step -- seconds for the crank steps, a press count for the rest; reset to 0 by advanceStep
InstructionsScene = class("InstructionsScene").extends(GameScene) or InstructionsScene

-- "Forward"/"backward" just label the two signs of crank delta (positive vs
-- negative) -- not a claim about which is physically clockwise.
InstructionsScene.STEP_CRANK_FORWARD  = 1
InstructionsScene.STEP_CRANK_BACKWARD = 2
InstructionsScene.STEP_TRIM_UP        = 3
InstructionsScene.STEP_TRIM_DOWN      = 4
InstructionsScene.STEP_BROADSIDE_LEFT  = 5
InstructionsScene.STEP_BROADSIDE_RIGHT = 6
InstructionsScene.STEP_DONE            = 7

InstructionsScene.prompts = {
	[InstructionsScene.STEP_CRANK_FORWARD]  = "Crank one way to steer the helm",
	[InstructionsScene.STEP_CRANK_BACKWARD] = "Now crank the other way",
	[InstructionsScene.STEP_TRIM_UP]        = "Press Up to let out the sail",
	[InstructionsScene.STEP_TRIM_DOWN]      = "Now press Down to trim it in",
	[InstructionsScene.STEP_BROADSIDE_LEFT]  = "Press Left to charge a broadside",
	[InstructionsScene.STEP_BROADSIDE_RIGHT] = "Now press Right to charge a broadside",
}

---@param sceneProperties? table
function InstructionsScene:resetGame(sceneProperties)
	InstructionsScene.super.resetGame(self, sceneProperties)
	self.step = InstructionsScene.STEP_CRANK_FORWARD
	self.stepProgress = 0
end

function InstructionsScene:advanceStep()
	self.step = self.step + 1
	self.stepProgress = 0
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

shared.BButtonDown = function()
	if GameScene.current() then Noble.transition(TitleScene) end
end

InstructionsScene.inputHandler = shared

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

---@param side string "port" | "starboard"
function InstructionsScene:onBroadsideButtonDown(side)
	local wantStep = side == "port" and InstructionsScene.STEP_BROADSIDE_LEFT or InstructionsScene.STEP_BROADSIDE_RIGHT
	if self.step ~= wantStep then return end
	self.stepProgress = self.stepProgress + 1
	if self.stepProgress >= Config.INSTRUCTIONS_BROADSIDE_PRESSES then self:advanceStep() end
end

-- ---------------------------------------------------------------------------
-- Broadside practice: a stationary EnemyDummy that can't chase or ram back,
-- spawned on whichever side the current step is teaching (so it's always in
-- range of the button being taught) and kept respawning if destroyed, so the
-- player always has something to lock onto while pressing that button.
-- ---------------------------------------------------------------------------

-- Footprint the instruction card could occupy at its largest -- used as a
-- fixed exclusion zone for dummy placement below rather than matching
-- drawInstructionText's live box exactly, since spawn logic shouldn't need
-- to reach into rendering to size text.
---@return number width
---@return number height
function InstructionsScene:instructionBoxFootprint()
	local maxW, lineH = 0, 0
	for _, prompt in pairs(InstructionsScene.prompts) do
		local w, h = gfx.getTextSize(prompt)
		if w > maxW then maxW = w end
		lineH = h
	end
	for _, sample in ipairs({ "9.9s / 9.9s", "9 / 9" }) do
		local w = gfx.getTextSize(sample)
		if w > maxW then maxW = w end
	end
	local boxW = maxW + Config.INSTRUCTIONS_TEXT_BOX_PADDING_X * 2
	local boxH = lineH * 2 + Config.INSTRUCTIONS_TEXT_LINE_GAP + Config.INSTRUCTIONS_TEXT_BOX_PADDING_Y * 2
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

function InstructionsScene:spawnDummyTarget()
	local ship = self.ship
	local side = self.step == InstructionsScene.STEP_BROADSIDE_LEFT and "port" or "starboard"
	local ang = Utils.wrapDeg(ship.heading + (side == "starboard" and 90 or -90))
	local dist = Config.INSTRUCTIONS_DUMMY_DISTANCE

	if self:screenOffsetHitsInstructionBox(ang, dist) then
		-- Spawn on the opposite side of the ship instead: it's a point
		-- reflection through screen-center, which the instruction card (only
		-- ever near the top edge, well above center) can never also cover.
		-- The target stays reachable either way -- pickTarget re-checks side
		-- against the ship's *current* heading each time a charge begins, not
		-- the heading at spawn time.
		ang = Utils.wrapDeg(ang + 180)
	end

	local hx, hy = Utils.heading(ang)
	local ex, ey = ship.x + hx * dist, ship.y + hy * dist
	local facing = Utils.angleTo(ex, ey, ship.x, ship.y)
	self.enemies[#self.enemies + 1] = EnemyDummy(ex, ey, facing)
end

function InstructionsScene:tickGame()
	InstructionsScene.super.tickGame(self)
	local onBroadsideStep = self.step == InstructionsScene.STEP_BROADSIDE_LEFT
		or self.step == InstructionsScene.STEP_BROADSIDE_RIGHT
	if onBroadsideStep and #self.enemies == 0 then
		self:spawnDummyTarget()
	end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

---@return string
function InstructionsScene:stepProgressText()
	if self.step == InstructionsScene.STEP_CRANK_FORWARD or self.step == InstructionsScene.STEP_CRANK_BACKWARD then
		return string.format("%.1fs / %.1fs", self.stepProgress, Config.INSTRUCTIONS_CRANK_SECONDS)
	elseif self.step == InstructionsScene.STEP_TRIM_UP or self.step == InstructionsScene.STEP_TRIM_DOWN then
		return string.format("%d / %d", self.stepProgress, Config.INSTRUCTIONS_TRIM_PRESSES)
	elseif self.step == InstructionsScene.STEP_BROADSIDE_LEFT or self.step == InstructionsScene.STEP_BROADSIDE_RIGHT then
		return string.format("%d / %d", self.stepProgress, Config.INSTRUCTIONS_BROADSIDE_PRESSES)
	end
	return ""
end

-- Drawn top-right, above the ship (which -- like every GameScene -- sits
-- camera-locked at screen center), so the water, wake, and practice dummy
-- stay visible underneath while the player works through each step. The
-- prompt/progress pair sits on a white rounded-rect card (sized to fit
-- whichever text is currently longest) so it stays legible over the water
-- instead of floating bare -- see Config.INSTRUCTIONS_TEXT_BOX_*.
function InstructionsScene:drawInstructionText()
	local prompt = InstructionsScene.prompts[self.step] or "You're ready to sail!"
	local progress = InstructionsScene.prompts[self.step] and self:stepProgressText() or nil

	local padX = Config.INSTRUCTIONS_TEXT_BOX_PADDING_X
	local padY = Config.INSTRUCTIONS_TEXT_BOX_PADDING_Y
	local lineGap = Config.INSTRUCTIONS_TEXT_LINE_GAP

	local promptW, promptH = gfx.getTextSize(prompt)
	local boxW, boxH = promptW, promptH
	if progress then
		local progressW, progressH = gfx.getTextSize(progress)
		boxW = math.max(boxW, progressW)
		boxH = boxH + lineGap + progressH
	end
	boxW = boxW + padX * 2
	boxH = boxH + padY * 2

	local boxX = Config.SCREEN_W - Config.INSTRUCTIONS_TEXT_BOX_MARGIN_RIGHT - boxW
	local boxY = Config.INSTRUCTIONS_TEXT_BOX_TOP
	local radius = Config.INSTRUCTIONS_TEXT_BOX_RADIUS
	local textCx = boxX + boxW / 2

	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(boxX, boxY, boxW, boxH, radius)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRoundRect(boxX, boxY, boxW, boxH, radius)

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	local textY = boxY + padY
	gfx.drawTextAligned(prompt, textCx, textY, kTextAlignment.center)
	if progress then
		gfx.drawTextAligned(progress, textCx, textY + promptH + lineGap, kTextAlignment.center)
	end

	gfx.drawTextAligned("Ⓑ to exit", Config.SCREEN_W / 2, Config.SCREEN_H - 16, kTextAlignment.center)
end

function InstructionsScene:render()
	InstructionsScene.super.render(self)
	self:drawInstructionText()
end
