-- SailingInstructions.lua
-- Remedial "how does sailing even work" lesson, reached from
-- InstructionsScene's "do you know how to sail?" gate when the player says
-- no (see InstructionsScene:onBButtonDown). Extends InstructionsScene (so
-- it inherits GameScene's real ship-on-real-water plumbing the same way
-- InstructionsScene does) but doesn't use any of InstructionsScene's own
-- STEP_*/prompts machinery -- instead it's a content-driven dialogue
-- interpreter narrated as a sarcastic, put-upon Zeus, driven entirely by
-- the SailingInstructions.DIALOGUE array below (a "beat" per line/lesson
-- step), plus the OFF_COURSE_PHRASES/UPWIND_MOCK_LINES arrays. Edit the
-- wording there, not the code below, to change what Zeus says.
--
-- Wind is pinned constant (blowing screen left -> right, see
-- fixedWindDirection) rather than wandering, and starts at
-- Config.SHIP_MAX_SPEED - Config.SAILING_INSTRUCTIONS_WIND_SPEED_OFFSET,
-- live-adjustable +/- Config.SAILING_INSTRUCTIONS_WIND_SPEED_MENU_STEP via
-- two system-menu items (added in :start(), removed in :finish(), the same
-- pattern as TuningScene.lua/GameSceneTraining.lua -- see the 3-item cap
-- note in CLAUDE.md). The ship starts dead downwind with the sail let all
-- the way out (see resetGame).
--
-- Beat types (the "type" field of each SailingInstructions.DIALOGUE entry):
--   "line"           - plain dialogue; Ⓐ advances it once
--                       Config.SAILING_INSTRUCTIONS_DIALOGUE_MIN_SECONDS has
--                       elapsed. An optional "sound" field plays a cue (see
--                       SOUND_CUES) the moment the beat begins.
--   "heading"        - the "enforcement policy": clears once the ship's
--                       heading has stayed within
--                       Config.SAILING_INSTRUCTIONS_HEADING_TOLERANCE_DEG of
--                       the beat's "target" degrees for
--                       Config.SAILING_INSTRUCTIONS_HEADING_HOLD_SECONDS.
--                       Going off course swaps the displayed text to the
--                       next OFF_COURSE_PHRASES entry (edge-triggered, not
--                       spammed every frame), and every
--                       Config.SAILING_INSTRUCTIONS_LIGHTNING_INTERVAL_SECONDS
--                       of continuous off-course time plays a random
--                       lightning-crack sound -- see tickHeadingGate.
--   "trim"           - clears after Config.SAILING_INSTRUCTIONS_TRIM_PRESSES
--                       presses of Down.
--   "upwindChallenge" - clears once the ship has made
--                       Config.SAILING_INSTRUCTIONS_UPWIND_DISTANCE_PX of
--                       "distance made good" upwind (displacement since the
--                       beat began, projected onto the upwind axis, floored
--                       at 0) since the beat began; mocks the player with
--                       UPWIND_MOCK_LINES if it's taking a while -- see
--                       tickUpwindChallenge.
--   "freeSail"        - terminal: no more gating, Ⓑ hands off to
--                       InstructionsScene's normal walkthrough (skipping its
--                       own ask/confirm gate, since the player just proved
--                       they can sail).

import "scripts/utilities/Config"
import "scripts/utilities/Utils"
import "scripts/utilities/Sound"
import "scenes/InstructionsScene"

local gfx <const> = playdate.graphics

---@class SailingInstructions : InstructionsScene
---@field beatIndex integer index into SailingInstructions.DIALOGUE
---@field beatElapsed number seconds since the current beat began
---@field windSpeedOverride number current fixed wind speed; adjustable via the "Increase/Decrease Wind Speed" system-menu items, see fixedWindSpeed
---@field offCourseSeconds number seconds continuously off the current "heading" beat's target (0 while on course)
---@field offCourseMessage? string currently displayed annoyed phrase; nil while on course
---@field offCourseHitCount integer times gone off-course during the current "heading" beat, drives OFF_COURSE_PHRASES rotation
---@field wasOnCourse boolean heading on-course state as of last tick, for edge-triggering offCourseMessage
---@field headingHoldSeconds number seconds continuously on-course; a "heading" beat clears once this reaches Config.SAILING_INSTRUCTIONS_HEADING_HOLD_SECONDS
---@field trimPresses integer Down presses counted toward the current "trim" beat
---@field upwindStartX? number ship x when the current "upwindChallenge" beat began
---@field upwindStartY? number ship y when the current "upwindChallenge" beat began
---@field upwindProgressPx number "distance made good" upwind so far this beat
---@field upwindTauntTimer number seconds since the current "upwindChallenge" beat began (or since the last taunt)
---@field upwindTauntCount integer how many UPWIND_MOCK_LINES have been shown this beat
---@field upwindMockText? string currently displayed mock line; nil until the first taunt fires
SailingInstructions = class("SailingInstructions").extends(InstructionsScene) or SailingInstructions

-- The exact bottom-right corner direction from the ship (always screen
-- center, see GameScene:cameraOrigin), so "turn slightly upwind toward the
-- bottom-right corner" points at a real landmark rather than a guessed
-- angle. Straight down is just 90 degrees (Utils.heading: 0 = +x, 90 = +y).
SailingInstructions.HEADING_BOTTOM_RIGHT = Utils.angleTo(0, 0, Config.SCREEN_W / 2, Config.SCREEN_H / 2)
SailingInstructions.HEADING_DOWN = 90

---@type table[]
SailingInstructions.DIALOGUE = {
	{ type = "line", text = "Ugh. Fine. It's me. Zeus." },
	{ type = "line", text = "Poseidon's busy. So you get me." },
	{ type = "line", text = "Lesson one: wind." },
	{ type = "line", text = "See it blow? Left to right. That's the wind." },
	{ type = "line", text = "Your sail catches that wind. That's what pushes your boat." },
	{ type = "line", text = "Right now you're running with the wind at your back, sail all the way out." },
	{
		type = "heading",
		target = SailingInstructions.HEADING_BOTTOM_RIGHT,
		text = "Turn a little upwind. Aim for the bottom-right corner.",
	},
	{ type = "line", text = "Feel that? You're slower now. That's the price of pointing up." },
	{ type = "trim", text = "Press Down to trim your sail in. Match the new wind angle." },
	{ type = "line", text = "There we go. Speed's back. Was that so hard?" },
	{
		type = "heading",
		target = SailingInstructions.HEADING_DOWN,
		text = "Now aim for the bottom of the screen.",
	},
	{ type = "trim", text = "Trim in again. Watch your speed." },
	{ type = "line", text = "Huh. Even faster. Good job, mortal. Don't let it go to your head." },
	{ type = "line", text = "Here's a secret: boats can even sail upwind." },
	{ type = "line", text = "Bet you can't.", sound = "evilLaugh" },
	{ type = "upwindChallenge", text = "Sail upwind. Go on. I'll wait." },
	{ type = "line", text = "Wow, look at you. You can actually sail now." },
	{ type = "freeSail", text = "Press \u{24B7} when you are ready." },
}

-- Shown while off-course on a "heading" beat (see tickHeadingGate): index 1
-- always fires first, then the rest rotate 2..N so repeat offenses don't
-- just loop the same line -- edit freely, order doesn't matter past index 1.
SailingInstructions.OFF_COURSE_PHRASES = {
	"That is not what I asked.",
	"Wrong way. I'm a god, not a GPS.",
	"That corner. That one. Not that one.",
	"Are you steering with your eyes shut?",
	"Even a barnacle turns better than that.",
	"Try aiming where I said. Wild idea, I know.",
}

-- Shown in order during the "upwindChallenge" beat once the player's taking
-- a while -- see tickUpwindChallenge. Stays on the last one once exhausted.
SailingInstructions.UPWIND_MOCK_LINES = {
	"Any day now. I have forever. You don't.",
	"Struggling? Sails don't push themselves.",
	"Even Poseidon's fish sail better than this.",
}

-- One-shot sound cues a "line" beat can request via its "sound" field.
local SOUND_CUES = {
	-- The exact "evil laugh" clip (source/assets/sounds/player/loose/evil-laugh.wav),
	-- already wired up as Sound.playPlayerDeath.
	evilLaugh = function() Sound.playPlayerDeath() end,
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

---@param sceneProperties? table
function SailingInstructions:resetGame(sceneProperties)
	-- Set before calling super: GameScene:resetGame (further up the chain)
	-- calls self:fixedWindSpeed() while setting up wind state, so
	-- windSpeedOverride must already hold the right value by then.
	self.windSpeedOverride = Config.SHIP_MAX_SPEED - Config.SAILING_INSTRUCTIONS_WIND_SPEED_OFFSET
	-- InstructionsScene:resetGame (further up the chain) sets self.step to
	-- its own ask-gate value -- harmless, just unused: SailingInstructions
	-- drives everything off self.beatIndex instead.
	SailingInstructions.super.resetGame(self, sceneProperties)

	-- Downwind start, full sail -- see file header.
	self.ship.heading = self:fixedWindDirection()
	self.ship.sailTrim = 1

	self.beatIndex = 1
	self:resetBeatState()
	self:enterBeat()
end

-- Wind direction is pinned (see GameScene:fixedWindDirection) rather than
-- wandering: blows toward +x, i.e. screen left -> right.
---@return number
function SailingInstructions:fixedWindDirection()
	return 0
end

-- Wind speed is pinned (see GameScene:fixedWindSpeed) to windSpeedOverride,
-- live-adjustable via the system-menu items in :start().
---@return number
function SailingInstructions:fixedWindSpeed()
	return self.windSpeedOverride
end

-- Per-beat tracking fields, reset both at scene start and on every
-- advanceBeat -- see the field doc comments on the class annotation above
-- for what each one means.
function SailingInstructions:resetBeatState()
	self.beatElapsed = 0
	self.offCourseSeconds = 0
	self.offCourseMessage = nil
	self.offCourseHitCount = 0
	self.wasOnCourse = true
	self.headingHoldSeconds = 0
	self.trimPresses = 0
	self.upwindProgressPx = 0
	self.upwindTauntTimer = 0
	self.upwindTauntCount = 0
	self.upwindMockText = nil
end

-- Setup that only runs once, when a beat first becomes current (not on every
-- tick): plays the beat's sound cue, if any, and snapshots the ship's
-- position for the upwind challenge's distance-made-good tracking.
function SailingInstructions:enterBeat()
	local beat = SailingInstructions.DIALOGUE[self.beatIndex]
	if not beat then return end
	if beat.sound and SOUND_CUES[beat.sound] then SOUND_CUES[beat.sound]() end
	if beat.type == "upwindChallenge" then
		self.upwindStartX, self.upwindStartY = self.ship.x, self.ship.y
	end
end

function SailingInstructions:advanceBeat()
	self.beatIndex = self.beatIndex + 1
	self:resetBeatState()
	self:enterBeat()
end

-- ---------------------------------------------------------------------------
-- Input (fresh off GameScene.buildSharedInputHandler -- none of
-- InstructionsScene's own step-progress hooks apply here, see file header)
-- ---------------------------------------------------------------------------

local shared = GameScene.buildSharedInputHandler(GameScene.current)
local sharedDownButtonDown = shared.downButtonDown

shared.downButtonDown = function()
	sharedDownButtonDown()
	local s = GameScene.current()
	if s then
		---@cast s SailingInstructions
		local beat = SailingInstructions.DIALOGUE[s.beatIndex]
		if beat and beat.type == "trim" then
			s.trimPresses = s.trimPresses + 1
		end
	end
end

shared.AButtonDown = function()
	local s = GameScene.current()
	if s then
		---@cast s SailingInstructions
		s:onAButtonDown()
	end
end

shared.BButtonDown = function()
	local s = GameScene.current()
	if s then
		---@cast s SailingInstructions
		s:onBButtonDown()
	end
end

SailingInstructions.inputHandler = shared

-- Ⓐ only ever advances a plain "line" beat (and only once it's been up long
-- enough to read) -- every other beat type clears itself once its gate is
-- satisfied, see tickGame/tickHeadingGate/tickUpwindChallenge.
function SailingInstructions:onAButtonDown()
	local beat = SailingInstructions.DIALOGUE[self.beatIndex]
	if beat and beat.type == "line" and self.beatElapsed >= Config.SAILING_INSTRUCTIONS_DIALOGUE_MIN_SECONDS then
		self:advanceBeat()
	end
end

-- Ⓑ only does something on the terminal "freeSail" beat: hands off to the
-- normal InstructionsScene walkthrough, skipping its ask/confirm gate since
-- the player just proved they can sail.
function SailingInstructions:onBButtonDown()
	local beat = SailingInstructions.DIALOGUE[self.beatIndex]
	if beat and beat.type == "freeSail" then
		Noble.transition(InstructionsScene, nil, nil, nil, { skipKnowSailingPrompt = true })
	end
end

-- ---------------------------------------------------------------------------
-- System menu: live wind-speed adjustment (2 of the 3-item cap -- see
-- CLAUDE.md -- added in :start(), removed in :finish(), same pattern as
-- TuningScene.lua/GameSceneTraining.lua)
-- ---------------------------------------------------------------------------

local windSpeedUpMenuItem = nil
local windSpeedDownMenuItem = nil

function SailingInstructions:start()
	SailingInstructions.super.start(self)

	windSpeedUpMenuItem = playdate.getSystemMenu():addMenuItem("Increase Wind Speed", function()
		local s = GameScene.current()
		if s then
			---@cast s SailingInstructions
			s.windSpeedOverride = math.max(0, s.windSpeedOverride + Config.SAILING_INSTRUCTIONS_WIND_SPEED_MENU_STEP)
			s.windSpeedTarget = s.windSpeedOverride
		end
	end)
	windSpeedDownMenuItem = playdate.getSystemMenu():addMenuItem("Decrease Wind Speed", function()
		local s = GameScene.current()
		if s then
			---@cast s SailingInstructions
			s.windSpeedOverride = math.max(0, s.windSpeedOverride - Config.SAILING_INSTRUCTIONS_WIND_SPEED_MENU_STEP)
			s.windSpeedTarget = s.windSpeedOverride
		end
	end)
end

function SailingInstructions:finish()
	SailingInstructions.super.finish(self)

	if windSpeedUpMenuItem then
		playdate.getSystemMenu():removeMenuItem(windSpeedUpMenuItem)
		windSpeedUpMenuItem = nil
	end
	if windSpeedDownMenuItem then
		playdate.getSystemMenu():removeMenuItem(windSpeedDownMenuItem)
		windSpeedDownMenuItem = nil
	end
end

-- ---------------------------------------------------------------------------
-- Per-beat gating ("enforcement policy" lives here -- tickHeadingGate)
-- ---------------------------------------------------------------------------

function SailingInstructions:tickGame()
	-- InstructionsScene.tickGame -> GameScene.tickGame: real ship/wind
	-- physics. InstructionsScene.tickGame's own broadside-dummy spawn branch
	-- no-ops here (currentBroadsideSide checks self.step against its own
	-- broadside constants, which this scene never sets).
	SailingInstructions.super.tickGame(self)
	self.beatElapsed = self.beatElapsed + Config.DT

	local beat = SailingInstructions.DIALOGUE[self.beatIndex]
	if not beat then return end

	if beat.type == "heading" then
		self:tickHeadingGate(beat)
	elseif beat.type == "trim" then
		if self.trimPresses >= Config.SAILING_INSTRUCTIONS_TRIM_PRESSES then
			self:advanceBeat()
		end
	elseif beat.type == "upwindChallenge" then
		self:tickUpwindChallenge(beat)
	end
end

-- The "enforcement policy": clears the beat once the ship's heading has
-- stayed within Config.SAILING_INSTRUCTIONS_HEADING_TOLERANCE_DEG of
-- beat.target for Config.SAILING_INSTRUCTIONS_HEADING_HOLD_SECONDS. While
-- off course, offCourseMessage is set once on the on-course -> off-course
-- transition (not spammed every frame) and cleared the moment the player
-- corrects; a random lightning-crack sound plays every
-- Config.SAILING_INSTRUCTIONS_LIGHTNING_INTERVAL_SECONDS of continuous
-- off-course time on top of that.
---@param beat table
function SailingInstructions:tickHeadingGate(beat)
	local diff = Utils.angleDiff(beat.target, self.ship.heading)
	local onCourse = math.abs(diff) <= Config.SAILING_INSTRUCTIONS_HEADING_TOLERANCE_DEG

	if onCourse then
		self.offCourseSeconds = 0
		self.offCourseMessage = nil
		self.headingHoldSeconds = self.headingHoldSeconds + Config.DT
		if self.headingHoldSeconds >= Config.SAILING_INSTRUCTIONS_HEADING_HOLD_SECONDS then
			self:advanceBeat()
			return
		end
	else
		self.headingHoldSeconds = 0
		if self.wasOnCourse then
			self.offCourseMessage = self:nextOffCourseMessage()
		end
		self.offCourseSeconds = self.offCourseSeconds + Config.DT
		if self.offCourseSeconds >= Config.SAILING_INSTRUCTIONS_LIGHTNING_INTERVAL_SECONDS then
			Sound.playLightning()
			self.offCourseSeconds = self.offCourseSeconds - Config.SAILING_INSTRUCTIONS_LIGHTNING_INTERVAL_SECONDS
		end
	end
	self.wasOnCourse = onCourse
end

-- Index 1 (the fixed "That is not what I asked" opener) always fires first;
-- every subsequent off-course transition this beat cycles through the rest.
---@return string
function SailingInstructions:nextOffCourseMessage()
	self.offCourseHitCount = self.offCourseHitCount + 1
	local phrases = SailingInstructions.OFF_COURSE_PHRASES
	if self.offCourseHitCount <= 1 then return phrases[1] end
	local alternates = #phrases - 1
	local index = 2 + ((self.offCourseHitCount - 2) % alternates)
	return phrases[index]
end

-- "Distance made good" upwind: the ship's displacement since the beat
-- began, projected onto the upwind axis (opposite fixedWindDirection),
-- floored at 0 so drifting back downwind doesn't count as negative
-- progress. Mocks the player with UPWIND_MOCK_LINES if it's taking a while.
---@param __beat table unused -- the challenge has no per-instance data beyond what's already tracked on self
function SailingInstructions:tickUpwindChallenge(__beat)
	local upwindDir = Utils.wrapDeg(self:fixedWindDirection() + 180)
	local ux, uy = Utils.heading(upwindDir)
	local dx, dy = self.ship.x - self.upwindStartX, self.ship.y - self.upwindStartY
	self.upwindProgressPx = math.max(0, dx * ux + dy * uy)

	if self.upwindProgressPx >= Config.SAILING_INSTRUCTIONS_UPWIND_DISTANCE_PX then
		self:advanceBeat()
		return
	end

	self.upwindTauntTimer = self.upwindTauntTimer + Config.DT
	local delay = self.upwindTauntCount == 0
		and Config.SAILING_INSTRUCTIONS_UPWIND_TAUNT_DELAY_SECONDS
		or Config.SAILING_INSTRUCTIONS_UPWIND_TAUNT_INTERVAL_SECONDS
	if self.upwindTauntTimer >= delay and self.upwindTauntCount < #SailingInstructions.UPWIND_MOCK_LINES then
		self.upwindTauntCount = self.upwindTauntCount + 1
		self.upwindMockText = SailingInstructions.UPWIND_MOCK_LINES[self.upwindTauntCount]
		self.upwindTauntTimer = 0
	end
end

-- ---------------------------------------------------------------------------
-- Rendering (drawInstructionText overrides InstructionsScene's -- called
-- polymorphically from InstructionsScene:render, so no render() override
-- needed here)
-- ---------------------------------------------------------------------------

-- Whichever line is "live" right now: an off-course scolding takes priority,
-- then an upwind-challenge mock line (once one's fired), otherwise the
-- current beat's own text.
---@return string
function SailingInstructions:currentText()
	local beat = SailingInstructions.DIALOGUE[self.beatIndex]
	if not beat then return "" end
	if self.offCourseMessage then return self.offCourseMessage end
	if beat.type == "upwindChallenge" and self.upwindMockText then return self.upwindMockText end
	return beat.text
end

-- Same white rounded-rect card InstructionsScene:drawInstructionText draws
-- (top-right, Config.INSTRUCTIONS_TEXT_BOX_* sizing/wrapping), just showing
-- one line (currentText()) instead of a prompt+subline pair -- there's no
-- step-progress counter here, and no "Ⓑ to exit" hint (Ⓑ only ever does
-- something on the terminal "freeSail" beat, whose own text already says
-- "Press Ⓑ").
function SailingInstructions:drawInstructionText()
	local text = self:currentText()
	local maxWidth = Config.INSTRUCTIONS_TEXT_BOX_MAX_WIDTH
	local padX = Config.INSTRUCTIONS_TEXT_BOX_PADDING_X
	local padY = Config.INSTRUCTIONS_TEXT_BOX_PADDING_Y
	local radius = Config.INSTRUCTIONS_TEXT_BOX_RADIUS

	local textW, textH = gfx.getTextSizeForMaxWidth(text, maxWidth)
	local boxW = textW + padX * 2
	local boxH = textH + padY * 2

	local boxX = Config.SCREEN_W - Config.INSTRUCTIONS_TEXT_BOX_MARGIN_RIGHT - boxW
	local boxY = Config.INSTRUCTIONS_TEXT_BOX_TOP

	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(boxX, boxY, boxW, boxH, radius)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRoundRect(boxX, boxY, boxW, boxH, radius)

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	gfx.drawTextInRect(text, boxX + padX, boxY + padY, textW, textH, nil, nil, kTextAlignment.center)
end
