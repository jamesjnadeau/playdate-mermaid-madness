-- Enemy.lua
-- A hostile ship that steers toward the player and rams them.

import "scripts/utilities/Config"
import "scripts/enemies/ConfigEnemy"
import "scripts/utilities/Utils"
import "scripts/utilities/Ship"

local gfx <const> = playdate.graphics

---@class Enemy : Ship
---@field radius number collision radius
---@field maxHealth number see Enemy:draw's health bar, shown once health < maxHealth
---@field healthBarOffset number extra px past the collision radius before the health bar, see Enemy:drawHealthBar
---@field teleportWarning? number seconds left before relocation, nil when not pending -- see Enemy:updateLeash
---@field moveSpeed number
---@field accel number
---@field turnRateMax number
---@field turnRateMin number
---@field turnRateSpeedMultiplier number
---@field windMultiplier number
---@field eyeOffset number px the bow eye-dot sits ahead of center
---@field damage number damage dealt to the player ship on ramming
---@field minLevel number class-level: lowest self.level this enemy type may spawn at
---@field displayName string class-level: human-readable label, e.g. EnemySelectScene's picker
Enemy = class("Enemy").extends(Ship) or Enemy

-- Lowest self.level this enemy type is allowed to spawn at -- see
-- Config.ENEMY_MIN_LEVEL and GameScene:spawnEnemy, which filters
-- GameScene.enemyTypes by this. The base Enemy is unlocked from level 1, i.e.
-- it always appears; subclasses (e.g. EnemySwordfish) can raise this to gate
-- themselves to later levels.
Enemy.minLevel = Config.ENEMY_MIN_LEVEL

-- Human-readable label, e.g. for EnemySelectScene's enemy picker. Subclasses
-- should set their own.
Enemy.displayName = "Enemy"

---@param x number
---@param y number
---@param heading? number
function Enemy:init(x, y, heading)
	Enemy.super.init(self, x, y, heading)
	self.radius = Config.ENEMY_RADIUS
	self.length = Config.ENEMY_LENGTH
	self.color = gfx.kColorBlack
	self.health = 1
	self.maxHealth = self.health -- see Enemy:draw's health bar, shown once health < maxHealth
	self.healthBarOffset = Config.ENEMY_HEALTH_BAR_OFFSET -- see Enemy:drawHealthBar; subclasses whose drawn shape reaches past self.radius (e.g. EnemyKraken's dots) override this
	self.speed = 0
	self.teleportWarning = nil -- seconds left before relocation; nil when not pending

	-- Movement tuning, broken out into instance fields (rather than read
	-- straight from Config.ENEMY_*) so a subclass can override just these in
	-- its own init and reuse the update/draw logic below -- see
	-- EnemySwordfish.
	self.moveSpeed = Config.ENEMY_SPEED
	self.accel = Config.ENEMY_ACCEL
	self.turnRateMax = Config.ENEMY_TURN_RATE_MAX
	self.turnRateMin = Config.ENEMY_TURN_RATE_MIN
	self.turnRateSpeedMultiplier = Config.ENEMY_TURN_RATE_SPEED_MULTIPLIER
	self.windMultiplier = Config.ENEMY_WIND_MULTIPLIER
	self.eyeOffset = 6 -- px the bow eye-dot sits ahead of center, see Enemy:draw
	self.damage = Config.ENEMY_DAMAGE -- damage dealt to the player ship on ramming, see GameScene:tickGame

	local L, B = Config.ENEMY_LENGTH, Config.ENEMY_BEAM
	self.hull = { L, 0,  -L * 0.7, B,  -L, B * 0.55,  -L, -B * 0.55,  -L * 0.7, -B }
end

-- Turn rate falls off linearly from self.turnRateMax toward self.turnRateMin
-- as self.speed rises toward self.moveSpeed * self.turnRateSpeedMultiplier
-- (see the Config comment on ENEMY_TURN_RATE_SPEED_MULTIPLIER for why that
-- reference speed isn't just moveSpeed directly).
-- Movement stats shown by EnemySelectScene's preview pane. Default just
-- reads the instance fields Enemy:update actually steers by; a subclass
-- whose update loop moves by different numbers (e.g. EnemyRogueWave, which
-- charges at a fixed speed unrelated to self.moveSpeed) should override this
-- to report what it actually does instead of the unused inherited fields.
---@return number moveSpeed
---@return number accel
---@return number turnRate
function Enemy:previewStats()
	return self.moveSpeed, self.accel, self.turnRateMax
end

---@return number
function Enemy:currentTurnRate()
	local maxSpeed = self.moveSpeed * self.turnRateSpeedMultiplier
	local speedRatio = maxSpeed > 0 and (self.speed / maxSpeed) or 0
	if speedRatio < 0 then speedRatio = 0 elseif speedRatio > 1 then speedRatio = 1 end
	return self.turnRateMax - (self.turnRateMax - self.turnRateMin) * speedRatio
end

---@param targetX number
---@param targetY number
---@param windDirection? number
---@param windSpeed? number
function Enemy:update(targetX, targetY, windDirection, windSpeed)
	local dt = Config.DT
	local want = Utils.angleTo(self.x, self.y, targetX, targetY)
	local diff = Utils.angleDiff(self.heading, want)
	local turnRate = self:currentTurnRate()
	local maxTurn = turnRate * dt
	if diff > maxTurn then diff = maxTurn elseif diff < -maxTurn then diff = -maxTurn end
	self.heading = Utils.wrapDeg(self.heading + diff)

	self:updateSpeed(self.moveSpeed, self.accel, dt)
	local hx, hy = Utils.heading(self.heading)
	self.x = self.x + hx * self.speed * dt
	self.y = self.y + hy * self.speed * dt

	-- No sails to trim, so wind just shoves them along at a straight,
	-- configurable fraction of its speed on top of their steering.
	if windDirection and windSpeed then
		local wx, wy = Utils.heading(windDirection)
		local push = windSpeed * self.windMultiplier
		self.x = self.x + wx * push * dt
		self.y = self.y + wy * push * dt
	end

	self:updateLeash(targetX, targetY, dt)
end

-- In an infinite world an enemy that falls behind would otherwise chase the
-- player forever. Past Config.ENEMY_MAX_DISTANCE it starts a countdown
-- (surfaced on its off-screen indicator); if it's still that far away when
-- the countdown runs out, it's relocated to the opposite side of the player
-- at the same distance (a point reflection through the player), landing it
-- back in play instead of trailing off into the distance.
---@param shipX number
---@param shipY number
---@param dt number
function Enemy:updateLeash(shipX, shipY, dt)
	if Utils.dist(self.x, self.y, shipX, shipY) <= Config.ENEMY_MAX_DISTANCE then
		self.teleportWarning = nil
		return
	end

	if not self.teleportWarning then
		self.teleportWarning = Config.ENEMY_TELEPORT_WARN_TIME
		return
	end

	self.teleportWarning = self.teleportWarning - dt
	if self.teleportWarning <= 0 then
		self.x = 2 * shipX - self.x
		self.y = 2 * shipY - self.y
		self.teleportWarning = nil
	end
end

-- Bakes the white bow "eye" dot into the cached body image alongside the
-- hull -- see Ship:drawBodyLocal/buildBodyImage.
---@param cx number
---@param cy number
function Enemy:drawBodyLocal(cx, cy)
	Enemy.super.drawBodyLocal(self, cx, cy)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillCircleAtPoint(cx + self.eyeOffset, cy, 2)
end

function Enemy:draw()
	Enemy.super.draw(self)

	if self.health < self.maxHealth then
		self:drawHealthBar()
	end
end

-- Small bar centered under the hull, only shown once damaged (see draw()
-- above) -- white background with a black outline and a black fill
-- proportional to health remaining, so it reads at a glance regardless of
-- what's behind the enemy. Positioned self.radius (the collision radius)
-- plus self.healthBarOffset below center, so it clears both the collision
-- circle and any purely-visual parts (bill, direction dots) that reach
-- farther -- see Enemy.healthBarOffset.
function Enemy:drawHealthBar()
	local w, h = Config.ENEMY_HEALTH_BAR_WIDTH, Config.ENEMY_HEALTH_BAR_HEIGHT
	local x = self.x - w / 2
	local y = self.y + self.radius + self.healthBarOffset + Config.ENEMY_HEALTH_BAR_MARGIN

	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(x, y, w, h)

	local frac = math.max(0, self.health / self.maxHealth)
	gfx.setColor(gfx.kColorBlack)
	if frac > 0 then
		gfx.fillRect(x, y, w * frac, h)
	end
	gfx.drawRect(x, y, w, h)
end