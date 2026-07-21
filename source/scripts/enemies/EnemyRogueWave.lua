-- EnemyRogueWave.lua
-- A bull-charge Enemy variant: unlike the base Enemy's continuous homing
-- turn, it only ever turns while fully stopped, cycling through three
-- states (see EnemyRogueWave:update) --
--   "charging": heading locked, speed eased up to CHARGE_SPEED and held for
--     CHARGE_LENGTH seconds
--   "stopping": heading still locked, speed eased back down to 0
--   "turning":  speed pinned at 0, heading rotated toward the target for up
--     to TURN_TIME seconds before charging again
-- Config.ENEMY_ROGUEWAVE_CHARGE_SPEED/_CHARGE_LENGTH/_TURN_TIME are the three
-- tunable knobs (speed, charge length, and turn timing) called out above.
--
-- Drawn as an elongated crescent (see EnemyRogueWave:drawBodyLocal) rather
-- than a hull polygon: a filled outer ellipse with a second, rear-shifted
-- ellipse cut out of it (gfx.kColorClear) to open its "mouth" toward the
-- stern -- the rear end of the direction it moves, matching a real wave's
-- curl. All tuning lives in Config.ENEMY_ROGUEWAVE_* (see ConfigEnemy.lua).

import "scripts/utilities/Config"
import "scripts/enemies/ConfigEnemy"
import "scripts/utilities/Utils"
import "scripts/enemies/Enemy"

local gfx <const> = playdate.graphics

---@class EnemyRogueWave : Enemy
---@field state string "charging" | "stopping" | "turning" -- see EnemyRogueWave:update
---@field stateTimer number seconds elapsed in the current state
EnemyRogueWave = class("EnemyRogueWave").extends(Enemy) or EnemyRogueWave

-- Unlocked starting this level (see Config.ENEMY_ROGUEWAVE_MIN_LEVEL /
-- Enemy.minLevel / GameScene:spawnEnemy).
EnemyRogueWave.minLevel = Config.ENEMY_ROGUEWAVE_MIN_LEVEL

-- See Enemy.displayName.
EnemyRogueWave.displayName = "Rogue Wave"

---@param x number
---@param y number
---@param heading? number
function EnemyRogueWave:init(x, y, heading)
	EnemyRogueWave.super.init(self, x, y, heading)

	self.radius = Config.ENEMY_ROGUEWAVE_RADIUS
	self.healthBarOffset = Config.ENEMY_ROGUEWAVE_HEALTH_BAR_OFFSET
	self.length = Config.ENEMY_ROGUEWAVE_LENGTH
	self.color = Config.ENEMY_ROGUEWAVE_COLOR
	self.outlineColor = Config.ENEMY_ROGUEWAVE_OUTLINE_COLOR
	self.health = Config.ENEMY_ROGUEWAVE_HEALTH
	self.maxHealth = self.health
	self.speed = 0

	-- accel is shared by both the charge-up and the braking-to-a-stop leg
	-- (see :update) -- ENEMY_ROGUEWAVE_STOP_ACCEL is deliberately its own
	-- knob so stopping can feel snappier (or slower) than winding up.
	self.accel = Config.ENEMY_ROGUEWAVE_ACCEL
	self.windMultiplier = Config.ENEMY_ROGUEWAVE_WIND_MULTIPLIER
	self.damage = Config.ENEMY_ROGUEWAVE_DAMAGE

	self.state = "charging"
	self.stateTimer = 0
end

-- See Enemy:previewStats -- self.moveSpeed/turnRateMax are inherited from
-- Enemy:init but never actually used by :update below, which charges at
-- Config.ENEMY_ROGUEWAVE_CHARGE_SPEED and only turns (at
-- ENEMY_ROGUEWAVE_TURN_RATE) while fully stopped, so report those instead.
---@return number moveSpeed
---@return number accel
---@return number turnRate
function EnemyRogueWave:previewStats()
	return Config.ENEMY_ROGUEWAVE_CHARGE_SPEED, self.accel, Config.ENEMY_ROGUEWAVE_TURN_RATE
end

-- Bull-charge state machine -- replaces Enemy:update's continuous homing
-- turn entirely, since a rogue wave only ever turns while stopped. Heading
-- is left untouched during "charging"/"stopping" (it was locked in at the
-- end of the previous "turning" state) and only rotated during "turning",
-- with speed pinned at 0 the whole time so it can't drift while it aims.
---@param targetX number
---@param targetY number
---@param windDirection? number
---@param windSpeed? number
function EnemyRogueWave:update(targetX, targetY, windDirection, windSpeed)
	local dt = Config.DT
	self.stateTimer = self.stateTimer + dt

	if self.state == "charging" then
		self:updateSpeed(Config.ENEMY_ROGUEWAVE_CHARGE_SPEED, self.accel, dt)
		if self.stateTimer >= Config.ENEMY_ROGUEWAVE_CHARGE_LENGTH then
			self.state = "stopping"
			self.stateTimer = 0
		end
	elseif self.state == "stopping" then
		self:updateSpeed(0, Config.ENEMY_ROGUEWAVE_STOP_ACCEL, dt)
		if self.speed <= Config.ENEMY_ROGUEWAVE_STOP_SPEED_THRESHOLD then
			self.speed = 0
			self.state = "turning"
			self.stateTimer = 0
		end
	elseif self.state == "turning" then
		self.speed = 0
		local want = Utils.angleTo(self.x, self.y, targetX, targetY)
		local diff = Utils.angleDiff(self.heading, want)
		local maxTurn = Config.ENEMY_ROGUEWAVE_TURN_RATE * dt
		if diff > maxTurn then diff = maxTurn elseif diff < -maxTurn then diff = -maxTurn end
		self.heading = Utils.wrapDeg(self.heading + diff)

		if self.stateTimer >= Config.ENEMY_ROGUEWAVE_TURN_TIME then
			self.state = "charging"
			self.stateTimer = 0
		end
	end

	local hx, hy = Utils.heading(self.heading)
	self.x = self.x + hx * self.speed * dt
	self.y = self.y + hy * self.speed * dt

	-- No sails to trim, so wind just shoves it along at a straight,
	-- configurable fraction of its speed on top of the charge/turn above --
	-- same treatment as the base Enemy.
	if windDirection and windSpeed then
		local wx, wy = Utils.heading(windDirection)
		local push = windSpeed * self.windMultiplier
		self.x = self.x + wx * push * dt
		self.y = self.y + wy * push * dt
	end

	self:updateLeash(targetX, targetY, dt)
end

-- Bounding radius of the outer ellipse, or the rear-shifted cut ellipse if
-- it pokes out past the outer ellipse's own stern tip -- see
-- Ship:bodyRadius/buildBodyImage.
---@return number
function EnemyRogueWave:bodyRadius()
	local outer = math.max(Config.ENEMY_ROGUEWAVE_LENGTH, Config.ENEMY_ROGUEWAVE_BEAM)
	local hollowReach = Config.ENEMY_ROGUEWAVE_HOLLOW_OFFSET
		+ Config.ENEMY_ROGUEWAVE_LENGTH * Config.ENEMY_ROGUEWAVE_HOLLOW_SCALE
	return math.max(outer, hollowReach)
end

-- Elongated crescent, drawn in local space (heading 0 = pointing along +x,
-- the direction of travel) for Ship:buildBodyImage to bake and rotate per
-- frame: a filled outer ellipse (the wave's outer curl) with a second,
-- smaller ellipse cleared out of it (gfx.kColorClear -- see the Playdate SDK
-- note that drawing with kColorClear erases pixels back to transparent
-- rather than painting them) and shifted toward -x (the stern). That leaves
-- a solid crescent whose thick "belly" faces the bow and whose open mouth
-- faces the stern, i.e. the rear end of the direction it's moving, as
-- requested. No hull polygon and no bow eye dot (see Enemy:drawBodyLocal) --
-- a wave doesn't have a face.
---@param cx number
---@param cy number
function EnemyRogueWave:drawBodyLocal(cx, cy)
	local a, b = Config.ENEMY_ROGUEWAVE_LENGTH, Config.ENEMY_ROGUEWAVE_BEAM

	gfx.setColor(self.color)
	gfx.fillEllipseInRect(cx - a, cy - b, a * 2, b * 2)
	if self.outlineColor then
		gfx.setColor(self.outlineColor)
		gfx.setLineWidth(2)
		gfx.drawEllipseInRect(cx - a, cy - b, a * 2, b * 2)
	end

	local ia, ib = a * Config.ENEMY_ROGUEWAVE_HOLLOW_SCALE, b * Config.ENEMY_ROGUEWAVE_HOLLOW_SCALE
	local hx = cx - Config.ENEMY_ROGUEWAVE_HOLLOW_OFFSET
	gfx.setColor(gfx.kColorClear)
	gfx.fillEllipseInRect(hx - ia, cy - ib, ia * 2, ib * 2)
	if self.outlineColor then
		gfx.setColor(self.outlineColor)
		gfx.setLineWidth(2)
		gfx.drawEllipseInRect(hx - ia, cy - ib, ia * 2, ib * 2)
	end
end

function EnemyRogueWave:draw()
	Ship.draw(self)

	if self.health < self.maxHealth then
		self:drawHealthBar()
	end
end
