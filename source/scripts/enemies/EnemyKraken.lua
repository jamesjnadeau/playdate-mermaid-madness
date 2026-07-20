-- EnemyKraken.lua
-- A slow, tougher Enemy variant with a round body instead of a ship hull.
-- Draws its own body + a chevron of 3 small circles ahead of it, doubling
-- as a direction indicator in place of the base Enemy's bow eye-dot
-- (see EnemyKraken:drawBodyLocal/bodyRadius, which override Ship's hull-based
-- versions instead of filling a self.hull polygon). All tuning lives in
-- Config.ENEMY_KRAKEN_* (see ConfigEnemy.lua).

import "scripts/utilities/Config"
import "scripts/enemies/ConfigEnemy"
import "scripts/enemies/Enemy"

local gfx <const> = playdate.graphics

---@class EnemyKraken : Enemy
EnemyKraken = class("EnemyKraken").extends(Enemy) or EnemyKraken

-- Unlocked starting this level (see Config.ENEMY_KRAKEN_MIN_LEVEL /
-- Enemy.minLevel / GameScene:spawnEnemy).
EnemyKraken.minLevel = Config.ENEMY_KRAKEN_MIN_LEVEL

-- See Enemy.displayName.
EnemyKraken.displayName = "Kraken"

---@param x number
---@param y number
---@param heading? number
function EnemyKraken:init(x, y, heading)
	EnemyKraken.super.init(self, x, y, heading)

	self.radius = Config.ENEMY_KRAKEN_RADIUS
	self.healthBarOffset = Config.ENEMY_KRAKEN_HEALTH_BAR_OFFSET
	self.length = Config.ENEMY_KRAKEN_BODY_RADIUS -- no hull polygon to size off of; only Ship:sternPosition/beamPosition read this, and neither is called on enemies
	self.color = Config.ENEMY_KRAKEN_COLOR
	self.outlineColor = Config.ENEMY_KRAKEN_OUTLINE_COLOR
	self.health = Config.ENEMY_KRAKEN_HEALTH
	self.maxHealth = self.health -- see Enemy:drawHealthBar, shown once health < maxHealth
	self.speed = 0

	self.moveSpeed = Config.ENEMY_KRAKEN_SPEED
	self.accel = Config.ENEMY_KRAKEN_ACCEL
	self.turnRateMax = Config.ENEMY_KRAKEN_TURN_RATE_MAX
	self.turnRateMin = Config.ENEMY_KRAKEN_TURN_RATE_MIN
	self.turnRateSpeedMultiplier = Config.ENEMY_KRAKEN_TURN_RATE_SPEED_MULTIPLIER
	self.windMultiplier = Config.ENEMY_KRAKEN_WIND_MULTIPLIER
	self.damage = Config.ENEMY_KRAKEN_DAMAGE
end

-- Bounding radius of the body circle + the furthest chevron dot -- see
-- Ship:bodyRadius/buildBodyImage.
---@return number
function EnemyKraken:bodyRadius()
	local dotReach = Config.ENEMY_KRAKEN_DOT_OFFSET + Config.ENEMY_KRAKEN_DOT_SPACING + Config.ENEMY_KRAKEN_DOT_RADIUS
	return math.max(Config.ENEMY_KRAKEN_BODY_RADIUS, dotReach)
end

-- Same body-circle + chevron-of-dots shape as before, just drawn in local
-- space (heading 0 = pointing along +x) so it can be baked into the cached,
-- per-frame-rotated body image -- see Ship:drawBodyLocal/buildBodyImage.
-- 5 small circles: a chevron of 3 ahead of the body -- one at the tip and
-- two swept back to either side -- reading as an arrow pointing along the
-- heading, plus 2 more flanking the body itself on its left/right sides.
---@param cx number
---@param cy number
function EnemyKraken:drawBodyLocal(cx, cy)
	gfx.setColor(self.color)
	gfx.fillCircleAtPoint(cx, cy, Config.ENEMY_KRAKEN_BODY_RADIUS)
	if self.outlineColor then
		gfx.setColor(self.outlineColor)
		gfx.setLineWidth(2)
		gfx.drawCircleAtPoint(cx, cy, Config.ENEMY_KRAKEN_BODY_RADIUS)
	end

	gfx.setColor(self.color)
	local tipDist = Config.ENEMY_KRAKEN_DOT_OFFSET + Config.ENEMY_KRAKEN_DOT_SPACING
	gfx.fillCircleAtPoint(cx + tipDist, cy, Config.ENEMY_KRAKEN_DOT_RADIUS)
	for _, side in ipairs({ -1, 1 }) do
		gfx.fillCircleAtPoint(cx + Config.ENEMY_KRAKEN_DOT_OFFSET, cy + side * Config.ENEMY_KRAKEN_DOT_SPACING,
			Config.ENEMY_KRAKEN_DOT_RADIUS)
		gfx.fillCircleAtPoint(cx, cy + side * Config.ENEMY_KRAKEN_DOT_OFFSET, Config.ENEMY_KRAKEN_DOT_RADIUS)
	end
end

function EnemyKraken:draw()
	Ship.draw(self)

	if self.health < self.maxHealth then
		self:drawHealthBar()
	end
end
