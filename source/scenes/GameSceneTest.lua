-- GameSceneTest.lua
-- A sandbox for testing ship/wind/combat feel: no automatic spawning or
-- level progression. Press A to spawn one enemy, B to return to the title
-- screen.

import "scripts/Config"
import "scenes/GameScene"

local gfx <const> = playdate.graphics

---@class GameSceneTest : GameScene
---@field selectedEnemyType? table class-level: one of GameScene.enemyTypes, see below
GameSceneTest = class("GameSceneTest").extends(GameScene) or GameSceneTest

-- Which enemy type Ⓐ spawns; nil means "pick randomly", matching the
-- original behavior. Set by EnemySelectScene, reached via the "Select Enemy"
-- system-menu item added below. A class field (not per-instance) so it
-- survives the scene being torn down and recreated on transition.
GameSceneTest.selectedEnemyType = nil

GameSceneTest.inputHandler = GameScene.buildSharedInputHandler(GameScene.current)
GameSceneTest.inputHandler.AButtonDown = function()
	local s = GameScene.current()
	if s then s:spawnEnemy(GameSceneTest.selectedEnemyType) end
end
GameSceneTest.inputHandler.BButtonDown = function()
	if GameScene.current() then Noble.transition(TitleScene) end
end

function GameSceneTest:start()
	GameSceneTest.super.start(self)
	playdate.getSystemMenu():addMenuItem("Select Enemy", function()
		Noble.transition(EnemySelectScene)
	end)
end

function GameSceneTest:finish()
	GameSceneTest.super.finish(self)
	playdate.getSystemMenu():removeAllMenuItems()
end

function GameSceneTest:drawModeStatus()
	local enemyLabel = (GameSceneTest.selectedEnemyType and GameSceneTest.selectedEnemyType.displayName) or "Random"
	gfx.drawTextAligned("TEST  " .. enemyLabel .. "  " .. #self.enemies .. " up", Config.SCREEN_W - 4, 6, kTextAlignment.right)
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

function GameSceneTest:drawHUD()
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
function GameSceneTest:gameOverPrompt()
	return "Ⓑ to return to menu"
end
