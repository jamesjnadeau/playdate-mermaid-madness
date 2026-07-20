-- GameSceneMain.lua
-- The real game: enemies spawn automatically on a shrinking timer, capped
-- per level, and clearing a level's kill target hands off to
-- LevelCompleteScene for the next one -- see onLevelComplete, which
-- GameSceneDemo (a level-capped build variant, see Config.DEMO_MODE)
-- overrides to end the run instead once its cap is reached.

import "scripts/Config"
import "scripts/ConfigEnemy"
import "scripts/Utils"
import "scenes/GameScene"

local gfx <const> = playdate.graphics

---@class GameSceneMain : GameScene
---@field gameSceneClass table class-level: which class to restart/continue into -- see the comment on the assignment below
---@field level number set in resetGame; overrides GameScene's optional field
---@field spawnTimer number seconds until the next automatic spawn
---@field levelKills number kills toward clearing the current level
---@field levelSpawned number enemies spawned so far this level
---@field levelTarget number levelKills needed to clear the level
---@field levelComplete boolean
---@field levelCompleteTimer number|nil seconds left to hold on the cleared level before onLevelComplete fires; nil once it has fired, see tickGame
GameSceneMain = class("GameSceneMain").extends(GameScene) or GameSceneMain

-- Class-level self-reference read by the shared AButtonDown restart handler
-- below and by onLevelComplete/the LevelCompleteScene -> UpgradeSelectScene
-- -> WindShiftScene interstitial chain, so a restart or "continue" always
-- lands back on the right game scene class. GameSceneDemo overrides this to
-- its own class so death/continue never accidentally drops the player out of
-- demo mode into the uncapped GameSceneMain.
GameSceneMain.gameSceneClass = GameSceneMain

---@param a number
---@param b number
---@param t number
---@return number
local function lerp(a, b, t) return a + (b - a) * t end

GameSceneMain.inputHandler = GameScene.buildSharedInputHandler(GameScene.current)
GameSceneMain.inputHandler.AButtonDown = function()
	local s = GameScene.current()
	if s and s.gameOver then Noble.transition(s.gameSceneClass) end
end

---@param sceneProperties? table
function GameSceneMain:resetGame(sceneProperties)
	sceneProperties = sceneProperties or {}
	-- Set before calling super: GameScene.resetGame calls self:windTuning(),
	-- which (below) reads self.level to scale wind speed/timing per level.
	self.level = sceneProperties.level or 1
	GameSceneMain.super.resetGame(self, sceneProperties)
	self.spawnTimer = Config.SPAWN_INTERVAL_START
	self.score = sceneProperties.totalDefeated or 0 -- cumulative across all levels this run
	self.levelKills = 0                             -- kills toward clearing the current level
	self.levelSpawned = 0                           -- enemies spawned so far this level
	self.levelTarget = self.level * Config.LEVEL_ENEMY_STEP
	self.levelComplete = false
	self.levelCompleteTimer = 0
end

-- How many wind-escalation steps have landed by the given level, per
-- Config.LEVEL_WIND_STEP_INTERVAL (e.g. 2 -> levels 1-2 are step 0, 3-4 are
-- step 1, 5-6 are step 2, ...). A class-level (not instance) function so
-- LevelCompleteScene can call it
-- directly to decide whether a level transition needs to route through
-- WindShiftScene.
---@param level number
---@return integer
function GameSceneMain.windStepForLevel(level)
	return math.floor((level - 1) / Config.LEVEL_WIND_STEP_INTERVAL)
end

-- Wind gets twitchier (faster easing rate) and more frequent (shorter time
-- between changes) as levels climb, same idea as levelTarget above: scaled
-- linearly off the wind step (see windStepForLevel above), tunable via
-- Config.LEVEL_WIND_SPEED_CHANGE_RATE_STEP and Config.LEVEL_WIND_CHANGE_INTERVAL_STEP.
---@return { speedChangeRateMin: number, speedChangeRateMax: number, changeIntervalMin: number, changeIntervalMax: number }
function GameSceneMain:windTuning()
	local step = GameSceneMain.windStepForLevel(self.level)
	local intervalMin = math.max(Config.WIND_CHANGE_INTERVAL_FLOOR,
		Config.WIND_CHANGE_INTERVAL_MIN - step * Config.LEVEL_WIND_CHANGE_INTERVAL_STEP)
	local intervalMax = math.max(Config.WIND_CHANGE_INTERVAL_FLOOR,
		Config.WIND_CHANGE_INTERVAL_MAX - step * Config.LEVEL_WIND_CHANGE_INTERVAL_STEP)
	return {
		speedChangeRateMin = Config.WIND_SPEED_CHANGE_RATE_MIN + step * Config.LEVEL_WIND_SPEED_CHANGE_RATE_STEP,
		speedChangeRateMax = Config.WIND_SPEED_CHANGE_RATE_MAX + step * Config.LEVEL_WIND_SPEED_CHANGE_RATE_STEP,
		changeIntervalMin = intervalMin,
		changeIntervalMax = intervalMax,
	}
end

---@return number
function GameSceneMain:currentSpawnInterval()
	local t = Utils.clamp(self.elapsed / Config.SPAWN_RAMP_SECONDS, 0, 1)
	return lerp(Config.SPAWN_INTERVAL_START, Config.SPAWN_INTERVAL_FLOOR, t)
end

-- Spawn on a shrinking interval, same as the base scene's manual spawnEnemy
-- but capped so at most levelTarget enemies ever spawn this level.
---@param dt number
function GameSceneMain:updateSpawning(dt)
	self.spawnTimer = self.spawnTimer - dt
	if self.spawnTimer <= 0 then
		self:spawnEnemy()
		self.spawnTimer = self:currentSpawnInterval()
	end
end

---@return boolean spawned
function GameSceneMain:spawnEnemy()
	if self.levelSpawned >= self.levelTarget then return false end
	if GameSceneMain.super.spawnEnemy(self) then
		self.levelSpawned = self.levelSpawned + 1
		return true
	end
	return false
end

function GameSceneMain:enemyDefeated()
	GameSceneMain.super.enemyDefeated(self)
	self.levelKills = self.levelKills + 1
end

-- Drifts the ship onward at its last heading, easing speed down with the
-- same water friction as normal play (see Ship:updateSpeed), instead of
-- snapping motionless the instant levelComplete skips the rest of tickGame
-- below -- called each tick during the level-complete hold so the ship
-- visibly coasts to a stop rather than freezing mid-glide.
---@param dt number
function GameSceneMain:coastShip(dt)
	local ship = self.ship
	ship.speed = math.max(0, ship.speed - ship.speed * Config.SHIP_WATER_FRICTION * dt)
	local hx, hy = Utils.heading(ship.heading)
	ship.x = ship.x + hx * ship.speed * dt
	ship.y = ship.y + hy * ship.speed * dt
end

-- Level clears once enough enemies have been defeated. Gameplay freezes
-- immediately (the levelComplete guard below skips the super call), but
-- onLevelComplete doesn't fire until levelCompleteTimer counts down from
-- Config.LEVEL_COMPLETE_DELAY. levelCompleteTimer is set to nil the moment
-- it fires so this only ever happens once per level, even with a delay of 0.
function GameSceneMain:tickGame()
	if self.levelComplete then
		self:coastShip(Config.DT)
		if self.levelCompleteTimer ~= nil then
			self.levelCompleteTimer = self.levelCompleteTimer - Config.DT
			if self.levelCompleteTimer <= 0 then
				self.levelCompleteTimer = nil
				self:onLevelComplete()
			end
		end
		return
	end
	GameSceneMain.super.tickGame(self)
	if self.levelKills >= self.levelTarget then
		self.levelComplete = true
		self.levelCompleteTimer = Config.LEVEL_COMPLETE_DELAY
	end
end

-- Hook for what happens once a level's kill target is reached -- default:
-- hand off to LevelCompleteScene, which carries self.gameSceneClass the rest
-- of the way through UpgradeSelectScene (and WindShiftScene, on levels that
-- land a wind-escalation step) back to a fresh level, restarting whichever
-- game scene class actually completed this one, with health reset
-- (Player:init always sets full health). GameSceneDemo overrides this to end
-- the run instead, once its own level cap is reached.
function GameSceneMain:onLevelComplete()
	Noble.transition(LevelCompleteScene, nil, nil, nil, {
		completedLevel = self.level,
		totalDefeated = self.score,
		gameScene = self.gameSceneClass,
	})
end

function GameSceneMain:drawModeStatus()
	gfx.drawText("LV " .. self.level .. "  " .. self.levelKills .. "/" .. self.levelTarget, Config.SCREEN_W - 90, 6)
end
