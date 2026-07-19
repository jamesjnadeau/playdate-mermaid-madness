-- EnemyDummy.lua
-- A stationary target: InstructionsScene spawns these so the player can
-- practice locking on and firing a broadside without a real enemy chasing
-- or ramming them. Not one of GameScene.enemyTypes -- never eligible for
-- random spawning in real gameplay.

import "scripts/Config"
import "scripts/Enemy"

---@class EnemyDummy : Enemy
EnemyDummy = class("EnemyDummy").extends(Enemy) or EnemyDummy

-- See Enemy.displayName.
EnemyDummy.displayName = "Training Dummy"

---@param x number
---@param y number
---@param heading? number
function EnemyDummy:init(x, y, heading)
	EnemyDummy.super.init(self, x, y, heading)
	self.moveSpeed = 0
	self.accel = 0
	self.turnRateMax = 0
	self.turnRateMin = 0
	self.windMultiplier = 0
	self.damage = 0 -- harmless to ram: practicing shouldn't cost the player any health
end

-- Stationary: skip Enemy:update's steering/movement/wind-push/leash entirely
-- so it just sits where InstructionsScene spawned it.
---@param targetX number
---@param targetY number
---@param windDirection? number
---@param windSpeed? number
function EnemyDummy:update(targetX, targetY, windDirection, windSpeed) end
