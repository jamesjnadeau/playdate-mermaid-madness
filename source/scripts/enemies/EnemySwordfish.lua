-- EnemySwordfish.lua
-- A smaller, faster Enemy variant with a swordfish-shaped hull: a slim body
-- tipped with a long spiked bill. All tuning lives in Config.ENEMY_SWORDFISH_*
-- (see Config.lua) -- Enemy:update/draw already read from instance fields, so
-- this subclass just points those fields at its own config values.

import "scripts/utilities/Config"
import "scripts/enemies/ConfigEnemy"
import "scripts/utilities/Utils"
import "scripts/enemies/Enemy"

---@class EnemySwordfish : Enemy
EnemySwordfish = class("EnemySwordfish").extends(Enemy) or EnemySwordfish

-- Unlocked starting this level (see Config.ENEMY_SWORDFISH_MIN_LEVEL /
-- Enemy.minLevel / GameScene:spawnEnemy).
EnemySwordfish.minLevel = Config.ENEMY_SWORDFISH_MIN_LEVEL

-- See Enemy.displayName.
EnemySwordfish.displayName = "Swordfish"

---@param x number
---@param y number
---@param heading? number
function EnemySwordfish:init(x, y, heading)
	EnemySwordfish.super.init(self, x, y, heading)

	self.radius = Config.ENEMY_SWORDFISH_RADIUS
	self.healthBarOffset = Config.ENEMY_SWORDFISH_HEALTH_BAR_OFFSET
	self.length = Config.ENEMY_SWORDFISH_LENGTH
	self.color = Config.ENEMY_SWORDFISH_COLOR
	self.outlineColor = Config.ENEMY_SWORDFISH_OUTLINE_COLOR
	self.health = Config.ENEMY_SWORDFISH_HEALTH
	self.maxHealth = self.health
	self.speed = 0

	self.moveSpeed = Config.ENEMY_SWORDFISH_SPEED
	self.accel = Config.ENEMY_SWORDFISH_ACCEL
	self.turnRateMax = Config.ENEMY_SWORDFISH_TURN_RATE_MAX
	self.turnRateMin = Config.ENEMY_SWORDFISH_TURN_RATE_MIN
	self.turnRateSpeedMultiplier = Config.ENEMY_SWORDFISH_TURN_RATE_SPEED_MULTIPLIER
	self.windMultiplier = Config.ENEMY_SWORDFISH_WIND_MULTIPLIER
	self.eyeOffset = Config.ENEMY_SWORDFISH_EYE_OFFSET
	self.damage = Config.ENEMY_SWORDFISH_DAMAGE

	-- Same fan-shaped hull as the base Enemy, but slimmer (smaller beam
	-- fractions) and stretched forward by BILL_LENGTH past the bow to read
	-- as a swordfish's spike rather than a ship's prow.
	local L, B, BILL = Config.ENEMY_SWORDFISH_LENGTH, Config.ENEMY_SWORDFISH_BEAM, Config.ENEMY_SWORDFISH_BILL_LENGTH
	self.hull = { L + BILL, 0,  -L * 0.7, B * 0.5,  -L, B * 0.3,  -L, -B * 0.3,  -L * 0.7, -B * 0.5 }
end
