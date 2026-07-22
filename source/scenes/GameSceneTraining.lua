-- GameSceneTraining.lua
-- A sandbox for testing ship/wind/combat feel: no automatic spawning or
-- level progression. Press A to spawn one enemy, B to bring up a "return to
-- title?" confirmation (A confirms, B cancels back into training).

import "scripts/config/Config"
import "scenes/GameScene"

local gfx <const> = playdate.graphics

---@class GameSceneTraining : GameScene
---@field selectedEnemyType? table class-level: one of GameScene.enemyTypes, see below
GameSceneTraining = class("GameSceneTraining").extends(GameScene) or GameSceneTraining

-- Which enemy type Ⓐ spawns; nil means "pick randomly", matching the
-- original behavior. Set by EnemySelectScene, reached via the "Select Enemy"
-- system-menu item added below. A class field (not per-instance) so it
-- survives the scene being torn down and recreated on transition.
GameSceneTraining.selectedEnemyType = nil

-- The "Select Enemy"/"Test Upgrade" items this scene itself owns, so
-- :finish() can remove just those two instead of every system-menu item --
-- main.lua's "Music" checkmark is also live at the same time and must
-- survive leaving this scene (see the 3-item cap note in CLAUDE.md -- these
-- two plus "Music" is the full 3, no headroom left for a fourth).
local selectEnemyMenuItem = nil
local testUpgradeMenuItem = nil

GameSceneTraining.inputHandler = GameScene.buildSharedInputHandler(GameScene.current)
GameSceneTraining.inputHandler.AButtonDown = function()
	local s = GameScene.current()
	if not s then return end
	if s.confirmingQuit then
		Noble.transition(TitleScene)
		return
	end
	s:spawnEnemy(GameSceneTraining.selectedEnemyType)
end
-- First press brings up the "return to title?" dialog (drawn by
-- drawConfirmQuit below); a second B cancels it and returns to the sandbox
-- without spawning an enemy -- see AButtonDown above for the confirm side.
GameSceneTraining.inputHandler.BButtonDown = function()
	local s = GameScene.current()
	if not s then return end
	s.confirmingQuit = not s.confirmingQuit
end

function GameSceneTraining:start()
	GameSceneTraining.super.start(self)
	selectEnemyMenuItem = playdate.getSystemMenu():addMenuItem("Enemy ⊙", function()
		Noble.transition(EnemySelectScene)
	end)
	testUpgradeMenuItem = playdate.getSystemMenu():addMenuItem("Upgrade 🎣", function()
		Noble.transition(UpgradeTestScene)
	end)
end

function GameSceneTraining:finish()
	GameSceneTraining.super.finish(self)
	if selectEnemyMenuItem then
		playdate.getSystemMenu():removeMenuItem(selectEnemyMenuItem)
		selectEnemyMenuItem = nil
	end
	if testUpgradeMenuItem then
		playdate.getSystemMenu():removeMenuItem(testUpgradeMenuItem)
		testUpgradeMenuItem = nil
	end
end

function GameSceneTraining:drawModeStatus()
	local enemyLabel = (GameSceneTraining.selectedEnemyType and GameSceneTraining.selectedEnemyType.displayName) or "Random"
	gfx.drawTextAligned("TRAINING  " .. enemyLabel .. "  " .. #self.enemies .. " up", Config.SCREEN_W - 4, 6, kTextAlignment.right)
end

-- Draws a sine-wave polyline from x=0 to x=width along baseline y, so the
-- wind bars read as little waves rather than flat progress bars (matching
-- the water's look -- see GameScene:drawWavelet). `dir` is +1/-1 and picks
-- which way the crest crawls, so the two bars visibly move opposite ways.
---@param width number
---@param y number
---@param phase number
---@param dir number +1 | -1
local function drawWaveBar(width, y, phase, dir)
	if width <= 0 then return end
	local amplitude = Config.WIND_BAR_WAVE_AMPLITUDE
	local k = 2 * math.pi / Config.WIND_BAR_WAVE_WAVELENGTH
	local segLen = 3
	local prevX, prevY = 0, y + amplitude * math.sin(-dir * phase)
	local x = 0
	while x < width - 0.001 do
		local nx = math.min(x + segLen, width)
		local ny = y + amplitude * math.sin(nx * k - dir * phase)
		gfx.drawLine(prevX, prevY, nx, ny)
		prevX, prevY = nx, ny
		x = nx
	end
end

function GameSceneTraining:drawHUD()
	GameScene.drawHUD(self)

	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	local phase = self.elapsed * Config.WIND_BAR_WAVE_SPEED * (2 * math.pi / Config.WIND_BAR_WAVE_WAVELENGTH)

	-- Wind-change bar: counts down (draining to nothing) toward the next wind
	-- change while the wind is settled, then -- while it eases toward its
	-- latest targets and the countdown is paused -- swaps to counting up
	-- (filling from nothing) toward the countdown resuming. Only one of the
	-- two is ever drawn, so it always reads as a single bar.
	if self.windSettled then
		local countdownFrac = Utils.clamp(self.windChangeTimer / self.windChangeIntervalDuration, 0, 1)
		drawWaveBar(Config.SCREEN_W * countdownFrac, Config.SCREEN_H - 3, phase, 1)
	elseif self.windEaseDuration > 0 then
		local easeFrac = Utils.clamp(self.windEaseTimer / self.windEaseDuration, 0, 1)
		drawWaveBar(Config.SCREEN_W * easeFrac, Config.SCREEN_H - 3, phase, -1)
	end
end

---@return string
function GameSceneTraining:gameOverPrompt()
	return "Ⓑ to return to menu"
end

-- Training is a sandbox for testing combat feel, not a scored run -- losing
-- all health resets the player's health instead of ending the game, so
-- testing isn't interrupted by having to back out to the title screen.
function GameSceneTraining:onPlayerHealthDepleted()
	self.ship.health = Config.SHIP_MAX_HEALTH
	self.ship.alive = true
end

-- Drawn (in place of the frozen gameplay) while self.confirmingQuit is true,
-- see BButtonDown above and GameScene's confirmingQuit field/drawConfirmQuit
-- hook. Same boxed-text look as GameScene:drawGameOver, just shorter.
function GameSceneTraining:drawConfirmQuit()
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(60, 90, Config.SCREEN_W - 120, 60)
	gfx.setColor(gfx.kColorWhite)
	gfx.drawRect(62, 92, Config.SCREEN_W - 124, 56)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	gfx.drawTextAligned("Return to title?", Config.SCREEN_W / 2, 104, kTextAlignment.center)
	gfx.drawTextAligned("Ⓐ yes   Ⓑ no", Config.SCREEN_W / 2, 124, kTextAlignment.center)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
end
