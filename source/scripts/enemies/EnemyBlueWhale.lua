-- EnemyBlueWhale.lua
-- An ambush Enemy variant that never chases: instead of Enemy:update's
-- continuous homing turn, it cycles through four states (see
-- EnemyBlueWhale:update) --
--   "submerged": invisible and harmless (self.radius pinned to 0, so neither
--     ramming nor tridents/Storm Cloud/lightning can touch it), for
--     Config.ENEMY_BLUE_WHALE_SUBMERGE_TIME seconds
--   "warning":   still invisible, but draws a dithered circle at the spot
--     it's about to surface that darkens over Config.ENEMY_BLUE_WHALE_WARN_TIME
--     seconds as the surfacing gets closer -- see EnemyBlueWhale:drawWarningCircle
--   "breaching": still invisible and harmless, for a brief
--     Config.ENEMY_BLUE_WHALE_BREACH_TIME beat -- separates the telegraph
--     circle vanishing from the whale actually appearing/hitting, so a
--     player watching never sees the hit land while the circle's still up
--   "surfaced":  teleports to that spot, throws anything within
--     Config.ENEMY_BLUE_WHALE_ATTACK_RADIUS outward (see EnemyBlueWhale:onRamHit),
--     then sits there visible and vulnerable (like any other enemy) for
--     Config.ENEMY_BLUE_WHALE_SURFACE_TIME seconds before submerging again --
-- at which point it retargets wherever the player is at that moment and
-- repeats. All tuning lives in Config.ENEMY_BLUE_WHALE_* (see ConfigEnemy.lua).
--
-- Drawn as a body ellipse with a tail fluke and a blowhole (see
-- EnemyBlueWhale:drawBodyLocal) rather than a hull polygon, only while
-- "surfaced" -- see EnemyBlueWhale:draw.

import "scripts/config/Config"
import "scripts/config/ConfigEnemy"
import "scripts/utilities/Utils"
import "scripts/enemies/Enemy"

local gfx <const> = playdate.graphics

---@class EnemyBlueWhale : Enemy
---@field state string "submerged" | "warning" | "breaching" | "surfaced" -- see EnemyBlueWhale:update
---@field stateTimer number seconds remaining in the current state
---@field targetX number world-space x it will next surface at (or last surfaced at)
---@field targetY number world-space y it will next surface at (or last surfaced at)
---@field justSurfaced boolean true for the single tick it transitions into "surfaced", see EnemyBlueWhale:collidesWithShip
EnemyBlueWhale = class("EnemyBlueWhale").extends(Enemy) or EnemyBlueWhale

-- Unlocked starting this level (see Config.ENEMY_BLUE_WHALE_MIN_LEVEL /
-- Enemy.minLevel / GameScene:spawnEnemy).
EnemyBlueWhale.minLevel = Config.ENEMY_BLUE_WHALE_MIN_LEVEL

-- See Enemy.displayName.
EnemyBlueWhale.displayName = "Blue Whale"

---@param x number
---@param y number
---@param heading? number
function EnemyBlueWhale:init(x, y, heading)
	EnemyBlueWhale.super.init(self, x, y, heading)

	self.length = Config.ENEMY_BLUE_WHALE_LENGTH
	self.healthBarOffset = Config.ENEMY_BLUE_WHALE_HEALTH_BAR_OFFSET
	self.color = Config.ENEMY_BLUE_WHALE_COLOR
	self.outlineColor = Config.ENEMY_BLUE_WHALE_OUTLINE_COLOR
	self.health = Config.ENEMY_BLUE_WHALE_HEALTH
	self.maxHealth = self.health
	self.damage = Config.ENEMY_BLUE_WHALE_DAMAGE
	self.speed = 0

	-- Starts submerged (invisible, uncollidable) rather than mid-attack, same
	-- as it'll be after every future breathing spell -- see :update.
	self.radius = 0
	self.state = "submerged"
	self.stateTimer = Config.ENEMY_BLUE_WHALE_SUBMERGE_TIME
	self.targetX, self.targetY = x, y
	self.justSurfaced = false
end

-- See Enemy:previewStats -- it doesn't chase, so moveSpeed/accel/turnRate
-- (inherited but unused by :update below) would be misleading; report 0s
-- instead of whatever Enemy:init happened to default them to.
---@return number moveSpeed
---@return number accel
---@return number turnRate
function EnemyBlueWhale:previewStats()
	return 0, 0, 0
end

-- Ambush state machine -- replaces Enemy:update's continuous homing turn
-- entirely, since a blue whale never steers toward the player, only ever
-- appears where it last decided to. self.radius (the shared collision field
-- that Enemy:collidesWithShip, the tridentball loop, Storm Cloud's damage
-- loop, and auto-lightning targeting all read) doubles as the
-- submerged/surfaced visibility switch: 0 while hidden, the real collision
-- radius only while "surfaced".
---@param targetX number
---@param targetY number
---@param windDirection? number
---@param windSpeed? number
function EnemyBlueWhale:update(targetX, targetY, windDirection, windSpeed)
	local dt = Config.DT
	self.justSurfaced = false
	self.stateTimer = self.stateTimer - dt

	if self.state == "submerged" then
		self.radius = 0
		if self.stateTimer <= 0 then
			-- Retarget wherever the player actually is right now, and face
			-- that way so the surfaced body reads as having swum toward it.
			self.heading = Utils.angleTo(self.x, self.y, targetX, targetY)
			self.targetX, self.targetY = targetX, targetY
			self.state = "warning"
			self.stateTimer = Config.ENEMY_BLUE_WHALE_WARN_TIME
		end
	elseif self.state == "warning" then
		self.radius = 0
		if self.stateTimer <= 0 then
			self.state = "breaching"
			self.stateTimer = Config.ENEMY_BLUE_WHALE_BREACH_TIME
		end
	elseif self.state == "breaching" then
		self.radius = 0
		if self.stateTimer <= 0 then
			self.x, self.y = self.targetX, self.targetY
			self.state = "surfaced"
			self.stateTimer = Config.ENEMY_BLUE_WHALE_SURFACE_TIME
			self.radius = Config.ENEMY_BLUE_WHALE_RADIUS
			self.justSurfaced = true
		end
	elseif self.state == "surfaced" then
		self.radius = Config.ENEMY_BLUE_WHALE_RADIUS
		if self.stateTimer <= 0 then
			self.state = "submerged"
			self.stateTimer = Config.ENEMY_BLUE_WHALE_SUBMERGE_TIME
			self.radius = 0
		end
	end

	self:updateLeash(targetX, targetY, dt)
end

-- Ramming hit test -- see Enemy:collidesWithShip. On the single tick it just
-- surfaced (self.justSurfaced), the whole Config.ENEMY_BLUE_WHALE_ATTACK_RADIUS
-- burst counts as a hit regardless of self.radius, so anything caught in the
-- telegraphed zone gets thrown even if it isn't touching the (smaller) body
-- collision circle; every other tick this just falls back to the normal
-- circle-circle check against self.radius (0 while hidden, so always false).
---@param shipX number
---@param shipY number
---@param shipRadius number
---@return boolean
function EnemyBlueWhale:collidesWithShip(shipX, shipY, shipRadius)
	if self.justSurfaced then
		return Utils.dist(self.x, self.y, shipX, shipY) < (shipRadius + Config.ENEMY_BLUE_WHALE_ATTACK_RADIUS)
	end
	return EnemyBlueWhale.super.collidesWithShip(self, shipX, shipY, shipRadius)
end

-- Throws the player outward from wherever the whale is (its surfacing point,
-- on the burst tick; its resting position for an ordinary touch while
-- breathing) -- see Enemy:onRamHit and Player:applyKnockback, which turns
-- Config.ENEMY_BLUE_WHALE_KNOCKBACK_DISTANCE into the actual push.
---@param ship Player
function EnemyBlueWhale:onRamHit(ship)
	local outward = Utils.angleTo(self.x, self.y, ship.x, ship.y)
	ship:applyKnockback(outward, Config.ENEMY_BLUE_WHALE_KNOCKBACK_DISTANCE)
end

-- Bounding radius of the body ellipse + the tail fluke poking out past its
-- stern -- see Ship:bodyRadius/buildBodyImage. Fixed regardless of state
-- (self.radius toggles for collision, but the baked body image itself is
-- built once from this and only ever drawn while "surfaced" -- see :draw).
---@return number
function EnemyBlueWhale:bodyRadius()
	return Config.ENEMY_BLUE_WHALE_LENGTH * 1.3
end

-- Body ellipse (LENGTH along the bow-stern axis, BEAM across) with a
-- triangular tail fluke fanning out past the stern and a small blowhole dot
-- near the bow, drawn in local space (heading 0 = pointing along +x) for
-- Ship:buildBodyImage to bake and rotate per frame. No hull polygon and no
-- bow eye dot (see Enemy:drawBodyLocal) -- a whale doesn't have either.
---@param cx number
---@param cy number
function EnemyBlueWhale:drawBodyLocal(cx, cy)
	local L, B = Config.ENEMY_BLUE_WHALE_LENGTH, Config.ENEMY_BLUE_WHALE_BEAM

	gfx.setColor(self.color)
	gfx.fillEllipseInRect(cx - L, cy - B, L * 2, B * 2)
	if self.outlineColor then
		gfx.setColor(self.outlineColor)
		gfx.setLineWidth(2)
		gfx.drawEllipseInRect(cx - L, cy - B, L * 2, B * 2)
	end

	gfx.setColor(self.color)
	local tailTipX = cx - L * 1.3
	gfx.fillTriangle(cx - L, cy, tailTipX, cy - B * 0.6, tailTipX, cy + B * 0.6)
	if self.outlineColor then
		gfx.setColor(self.outlineColor)
		gfx.setLineWidth(2)
		gfx.drawTriangle(cx - L, cy, tailTipX, cy - B * 0.6, tailTipX, cy + B * 0.6)
	end

	gfx.setColor(self.outlineColor or gfx.kColorWhite)
	gfx.fillCircleAtPoint(cx + L * 0.4, cy - B * 0.5, 2)
end

-- Grey dithered circle at (targetX, targetY), the spot this whale is about
-- to surface -- radius Config.ENEMY_BLUE_WHALE_ATTACK_RADIUS, the same value
-- the surfacing burst actually checks against (see :collidesWithShip), so
-- the telegraph honestly previews the danger zone rather than approximating
-- it. Starts barely-visible grey and darkens toward solid black as stateTimer
-- counts down to 0 -- same dithered-fill idiom as StormCloud's resting-gray
-- look (gfx.kDitherTypeBayer4x4), just animated frame to frame instead of
-- baked once, since the coverage itself changes every tick here. Passed
-- straight to setDitherPattern as alpha -- empirically (on this SDK, with a
-- black draw color) alpha near 1 reads as the lighter end and alpha near 0 as
-- the darker/more-opaque end, the opposite of the alpha=0-transparent/
-- alpha=1-opaque description in the SDK docs, so this counts DOWN from ~1 to
-- 0 rather than up, to get lighter-at-first/darker-as-it-approaches-surfacing.
function EnemyBlueWhale:drawWarningCircle()
	local coverage = Utils.clamp(self.stateTimer / Config.ENEMY_BLUE_WHALE_WARN_TIME, 0, 1)
	if coverage <= 0 then return end

	gfx.setColor(gfx.kColorBlack)
	gfx.setDitherPattern(coverage, gfx.image.kDitherTypeBayer4x4)
	gfx.fillCircleAtPoint(self.targetX, self.targetY, Config.ENEMY_BLUE_WHALE_ATTACK_RADIUS)
	gfx.setColor(gfx.kColorBlack) -- clear the dither pattern so it doesn't leak into later world-space draws
end

-- Nothing drawn while "submerged" or "breaching" (fully hidden); the
-- darkening telegraph circle while "warning" (see drawWarningCircle); the
-- normal cached-image hull + health bar while "surfaced" (see
-- Ship:draw/Enemy:drawHealthBar).
function EnemyBlueWhale:draw()
	if self.state == "warning" then
		self:drawWarningCircle()
		return
	end
	if self.state ~= "surfaced" then
		return
	end

	Ship.draw(self)
	if self.health < self.maxHealth then
		self:drawHealthBar()
	end
end
