-- mock_game_scene.lua
-- A lightweight test double for source/scenes/GameScene.lua, the base class
-- GameSceneMain, GameSceneTraining, and InstructionsScene all extend.
--
-- The real GameScene builds a Player/Ship, sprites, particles, wind physics,
-- and drawing for every frame -- fine for the Simulator, but way past what a
-- "does pressing this button transition to the right scene" test needs, and
-- per CLAUDE.md's tests/ note, gameplay built on Noble Engine's class system
-- still needs the real Simulator to verify. This stand-in keeps just the
-- surface GameSceneMain.lua/GameSceneTraining.lua/EnemySelectScene.lua/
-- InstructionsScene.lua actually call: lifecycle (init/start/finish),
-- GameScene.current(), the shared D-pad input handler (copied verbatim from
-- the real class -- it only touches
-- self.ship/self.trimInput/self:beginCharge/self:releaseCharge, all stubbed
-- below), pickTarget (a simplified stand-in, see below), enemyTypes,
-- spawnEnemy's cap/forced-type logic, and the tickGame hook GameSceneMain/
-- InstructionsScene layer their own level-clear/step-spawn logic onto.
-- Rendering (:render/:drawHUD/:drawModeStatus/:drawGameOver) is a no-op --
-- this suite checks scene transitions and state, not pixels. self.ship here
-- carries just enough (x/y/heading/speed, all zeroed, plus a no-op steer) to
-- satisfy GameSceneMain:coastShip during the level-complete hold -- no test
-- calls the real Ship:update() (which nothing currently does), since that's
-- the only path that reaches InstructionsScene:spawnDummyTarget, the one
-- place that'd need real ship coordinates.

GameScene = {}
class("GameScene").extends(NobleScene)

local scene = nil

function GameScene.current()
	return scene
end

function GameScene:init(sceneProperties)
	GameScene.super.init(self, sceneProperties)
	self.backgroundColor = playdate.graphics.kColorWhite
	scene = self
	self:resetGame(sceneProperties)
end

function GameScene:start()
	GameScene.super.start(self)
	scene = self
	Noble.Input.setCrankIndicatorStatus(true)
end

function GameScene:finish()
	GameScene.super.finish(self)
	if scene == self then scene = nil end
end

function GameScene:resetGame(sceneProperties)
	sceneProperties = sceneProperties or {}
	self.ship = { x = 0, y = 0, heading = 0, speed = 0, steer = function() end }
	self.enemies = {}
	self.elapsed = 0
	self.score = sceneProperties.totalDefeated or 0
	self.gameOver = false

	local wind = self:windTuning()
	self.windSpeedChangeRateMin = wind.speedChangeRateMin
	self.windSpeedChangeRateMax = wind.speedChangeRateMax
	self.windChangeIntervalMin = wind.changeIntervalMin
	self.windChangeIntervalMax = wind.changeIntervalMax

	self.trimInput = 0
	self.chargingSide = nil
	self.charge = 0
	self.target = nil
end

function GameScene:windTuning()
	return {
		speedChangeRateMin = Config.WIND_SPEED_CHANGE_RATE_MIN,
		speedChangeRateMax = Config.WIND_SPEED_CHANGE_RATE_MAX,
		changeIntervalMin = Config.WIND_CHANGE_INTERVAL_MIN,
		changeIntervalMax = Config.WIND_CHANGE_INTERVAL_MAX,
	}
end

-- Copied from the real GameScene.buildSharedInputHandler (source/scenes/GameScene.lua)
-- so the D-pad/crank/broadside bindings GameSceneMain and GameSceneTraining both
-- build on top of get exercised for real, against the stubbed self.ship/
-- self:beginCharge/self:releaseCharge below.
function GameScene.buildSharedInputHandler(getScene)
	return {
		cranked = function(change, _)
			local s = getScene()
			if s and not s.gameOver then s.ship:steer(change) end
		end,
		upButtonDown = function()
			local s = getScene()
			if s then s.trimInput = 1 end
		end,
		upButtonUp = function()
			local s = getScene()
			if s and s.trimInput == 1 then s.trimInput = 0 end
		end,
		downButtonDown = function()
			local s = getScene()
			if s then s.trimInput = -1 end
		end,
		downButtonUp = function()
			local s = getScene()
			if s and s.trimInput == -1 then s.trimInput = 0 end
		end,
		leftButtonDown = function()
			local s = getScene()
			if s and not s.gameOver then s:beginCharge("port") end
		end,
		leftButtonUp = function()
			local s = getScene()
			if s then s:releaseCharge("port") end
		end,
		rightButtonDown = function()
			local s = getScene()
			if s and not s.gameOver then s:beginCharge("starboard") end
		end,
		rightButtonUp = function()
			local s = getScene()
			if s then s:releaseCharge("starboard") end
		end,
	}
end

-- Real GameScene:pickTarget picks the nearest enemy on the given side by
-- cross product against ship heading -- more geometry than these tests need.
-- This just hands back the first enemy regardless of side/range, which is
-- enough for InstructionsScene:onBroadsideButtonDown's tests: they simulate
-- "in range" by seeding self.enemies with a stub table and "out of range" by
-- leaving it empty.
---@param __side string unused, see above
function GameScene:pickTarget(__side)
	return self.enemies[1]
end

function GameScene:beginCharge(side)
	self.chargingSide = side
	self.charge = 0
end

function GameScene:releaseCharge(side)
	if self.chargingSide ~= side then return end
	self.chargingSide = nil
	self.charge = 0
	self.target = nil
end

-- Two minimal stub "enemy" classes standing in for Enemy/EnemySwordfish/
-- EnemyKraken -- enough to be constructed (EnemyType(x, y, facing)) and to
-- carry the displayName/minLevel fields spawnEnemy's level-gating reads,
-- plus the maxHealth/previewStats/buildBodyImage surface EnemySelectScene's
-- preview pane reads/calls on whatever it picks from GameScene.enemyTypes --
-- bodyImage is a fake image table (numeric width/height + a no-op :draw)
-- rather than a real gfx.image, since these stubs never go through
-- Ship:buildBodyImage.
StubEnemyA = {}
class("StubEnemyA").extends(Object)
StubEnemyA.displayName = "Stub Enemy A"
StubEnemyA.minLevel = 1
function StubEnemyA:init(x, y, facing)
	self.x, self.y, self.facing = x, y, facing
	self.maxHealth = 1
	self.moveSpeed, self.accel, self.turnRateMax = 10, 20, 30
end
function StubEnemyA:buildBodyImage()
	self.bodyImage = { width = 10, height = 10, draw = function() end }
end
function StubEnemyA:previewStats()
	return self.moveSpeed, self.accel, self.turnRateMax
end

StubEnemyB = {}
class("StubEnemyB").extends(Object)
StubEnemyB.displayName = "Stub Enemy B"
StubEnemyB.minLevel = 1
function StubEnemyB:init(x, y, facing)
	self.x, self.y, self.facing = x, y, facing
	self.maxHealth = 2
	self.moveSpeed, self.accel, self.turnRateMax = 15, 25, 35
end
function StubEnemyB:buildBodyImage()
	self.bodyImage = { width = 10, height = 10, draw = function() end }
end
function StubEnemyB:previewStats()
	return self.moveSpeed, self.accel, self.turnRateMax
end

GameScene.enemyTypes = { StubEnemyA, StubEnemyB }

-- Mirrors the real GameScene:spawnEnemy's cap/forced-type/level-gating logic
-- (source/scenes/GameScene.lua) without the position math or real Enemy
-- classes -- that's what GameSceneMain's per-level cap and GameSceneTraining's
-- forced-type picker actually build on top of.
function GameScene:spawnEnemy(forcedType)
	if #self.enemies >= Config.MAX_ENEMIES then return false end

	local EnemyType = forcedType
	if not EnemyType then
		local level = self.level or 1
		local eligible = {}
		for _, t in ipairs(GameScene.enemyTypes) do
			if level >= t.minLevel then
				eligible[#eligible + 1] = t
			end
		end
		EnemyType = eligible[math.random(#eligible)]
	end
	self.enemies[#self.enemies + 1] = EnemyType(0, 0, 0)
	return true
end

function GameScene:updateSpawning(dt) end

function GameScene:enemyDefeated()
	self.score = self.score + 1
end

function GameScene:tickGame() end

function GameScene:update()
	GameScene.super.update(self)
	if not self.gameOver then
		self:tickGame()
	end
	self:render()
end

function GameScene:render() end
function GameScene:drawHUD() end
function GameScene:drawModeStatus() end
function GameScene:drawGameOver() end
function GameScene:gameOverPrompt()
	return "A to set sail again"
end
