-- EnemySeaSerpent.lua
-- A long, zig-zagging Enemy variant. Unlike the base Enemy's continuous
-- homing turn, it alternates two states (see EnemySeaSerpent:update) --
--   "straight": heading locked, swims LEG_DISTANCE px dead ahead
--   "turning":  pivots by ZIGZAG_ANGLE degrees off the direct line to its
--     target, alternating left/right every leg, for up to TURN_TIME seconds
-- tracing a long zig-zag path toward the player rather than a smooth curve.
--
-- Its body is a trailing chain of black ellipses (count/size/separation all
-- configurable, see Config.ENEMY_SEA_SERPENT_SEGMENT_*) that follow the
-- head's actual travelled path -- each segment's position is independent
-- history, not a rigid shape rotated with the head, so this class tracks its
-- own self.trail and overrides :draw() entirely rather than going through
-- Ship's cached-body-image + drawRotated path (see EnemySeaSerpent:updateTrail
-- / :draw). A black triangle head leads the way, drawn frontmost. All tuning
-- lives in Config.ENEMY_SEA_SERPENT_* (see ConfigEnemy.lua).

import "scripts/utilities/Config"
import "scripts/enemies/ConfigEnemy"
import "scripts/utilities/Utils"
import "scripts/enemies/Enemy"

local gfx <const> = playdate.graphics

---@class EnemySeaSerpent : Enemy
---@field segmentCount integer number of trailing body ellipses
---@field segmentRadius number px radius of each body ellipse
---@field segmentSeparation number px between consecutive segment centers along the path
---@field headLength number px from the head position to the triangle's tip
---@field headWidth number px half-width of the triangle's base
---@field trail {x: number, y: number}[] head-to-tail history of past head positions, one per body segment
---@field trailDist number px accumulated since the last trail sample, see updateTrail
---@field prevX number head x last frame, see updateTrail
---@field prevY number head y last frame, see updateTrail
---@field legState string "straight" | "turning" -- see EnemySeaSerpent:update
---@field legDistance number px travelled during the current "straight" leg
---@field turnTarget number heading (degrees) the current "turning" pivot is steering toward
---@field turnTimer number seconds elapsed in the current "turning" pivot
---@field zigSign integer 1 | -1, alternated each pivot to zig-zag left/right of the direct line to the target
EnemySeaSerpent = class("EnemySeaSerpent").extends(Enemy) or EnemySeaSerpent

-- Unlocked starting this level (see Config.ENEMY_SEA_SERPENT_MIN_LEVEL /
-- Enemy.minLevel / GameScene:spawnEnemy).
EnemySeaSerpent.minLevel = Config.ENEMY_SEA_SERPENT_MIN_LEVEL

-- See Enemy.displayName.
EnemySeaSerpent.displayName = "Sea Serpent"

---@param x number
---@param y number
---@param heading? number
function EnemySeaSerpent:init(x, y, heading)
	EnemySeaSerpent.super.init(self, x, y, heading)

	self.radius = Config.ENEMY_SEA_SERPENT_RADIUS
	self.healthBarOffset = Config.ENEMY_SEA_SERPENT_HEALTH_BAR_OFFSET
	self.length = Config.ENEMY_SEA_SERPENT_HEAD_LENGTH
	self.color = Config.ENEMY_SEA_SERPENT_COLOR
	self.health = Config.ENEMY_SEA_SERPENT_HEALTH
	self.maxHealth = self.health
	self.speed = 0

	self.moveSpeed = Config.ENEMY_SEA_SERPENT_SPEED
	self.accel = Config.ENEMY_SEA_SERPENT_ACCEL
	self.windMultiplier = Config.ENEMY_SEA_SERPENT_WIND_MULTIPLIER
	self.damage = Config.ENEMY_SEA_SERPENT_DAMAGE

	self.segmentCount = Config.ENEMY_SEA_SERPENT_SEGMENT_COUNT
	self.segmentRadius = Config.ENEMY_SEA_SERPENT_SEGMENT_RADIUS
	self.segmentSeparation = Config.ENEMY_SEA_SERPENT_SEGMENT_SEPARATION
	self.headLength = Config.ENEMY_SEA_SERPENT_HEAD_LENGTH
	self.headWidth = Config.ENEMY_SEA_SERPENT_HEAD_WIDTH

	-- Pre-fill the trail behind the spawn point so the body reads as a full
	-- length immediately instead of growing in from nothing as it swims --
	-- see updateTrail, which extends this same list going forward.
	local hx, hy = Utils.heading(self.heading)
	self.trail = {}
	for i = 1, self.segmentCount do
		local d = self.segmentSeparation * i
		self.trail[i] = { x = x - hx * d, y = y - hy * d }
	end
	self.trailDist = 0
	self.prevX, self.prevY = x, y

	self.legState = "straight"
	self.legDistance = 0
	self.turnTarget = self.heading
	self.turnTimer = 0
	self.zigSign = 1
end

-- See Enemy:previewStats -- self.turnRateMax/Min are inherited from
-- Enemy:init but never read by :update below, which only ever turns (at
-- Config.ENEMY_SEA_SERPENT_TURN_RATE) during the "turning" leg, so report
-- that instead.
---@return number moveSpeed
---@return number accel
---@return number turnRate
function EnemySeaSerpent:previewStats()
	return self.moveSpeed, self.accel, Config.ENEMY_SEA_SERPENT_TURN_RATE
end

-- Zig-zag state machine -- replaces Enemy:update's continuous homing turn.
-- Swims dead ahead for LEG_DISTANCE px ("straight"), then pivots for up to
-- TURN_TIME seconds toward a heading offset ZIGZAG_ANGLE degrees from the
-- direct line to the target ("turning"), alternating which side of that line
-- each pivot aims for so the path zig-zags along it. Speed never eases to 0
-- for the turn -- see the module comment -- it keeps swimming through the
-- pivot, unlike EnemyRogueWave's stop-to-turn.
---@param targetX number
---@param targetY number
---@param windDirection? number
---@param windSpeed? number
function EnemySeaSerpent:update(targetX, targetY, windDirection, windSpeed)
	local dt = Config.DT

	if self.legState == "straight" then
		self.legDistance = self.legDistance + self.speed * dt
		if self.legDistance >= Config.ENEMY_SEA_SERPENT_LEG_DISTANCE then
			self.legDistance = 0
			self.zigSign = -self.zigSign
			local direct = Utils.angleTo(self.x, self.y, targetX, targetY)
			self.turnTarget = Utils.wrapDeg(direct + self.zigSign * Config.ENEMY_SEA_SERPENT_ZIGZAG_ANGLE)
			self.turnTimer = 0
			self.legState = "turning"
		end
	elseif self.legState == "turning" then
		self.turnTimer = self.turnTimer + dt
		local diff = Utils.angleDiff(self.heading, self.turnTarget)
		local maxTurn = Config.ENEMY_SEA_SERPENT_TURN_RATE * dt
		if diff > maxTurn then diff = maxTurn elseif diff < -maxTurn then diff = -maxTurn end
		self.heading = Utils.wrapDeg(self.heading + diff)

		if self.turnTimer >= Config.ENEMY_SEA_SERPENT_TURN_TIME then
			self.legState = "straight"
		end
	end

	self:updateSpeed(self.moveSpeed, self.accel, dt)
	local hx, hy = Utils.heading(self.heading)
	self.x = self.x + hx * self.speed * dt
	self.y = self.y + hy * self.speed * dt

	-- No sails to trim, so wind just shoves it along at a straight,
	-- configurable fraction of its speed on top of the zig-zag above -- same
	-- treatment as the base Enemy.
	if windDirection and windSpeed then
		local wx, wy = Utils.heading(windDirection)
		local push = windSpeed * self.windMultiplier
		self.x = self.x + wx * push * dt
		self.y = self.y + wy * push * dt
	end

	self:updateTrail()
	self:updateLeash(targetX, targetY, dt)
end

-- Records a new trail sample -- the head's own position -- each time it has
-- travelled segmentSeparation px since the last one, and drops the oldest
-- sample past segmentCount so the trail always has exactly one entry per body
-- segment.
function EnemySeaSerpent:updateTrail()
	self.trailDist = self.trailDist + Utils.dist(self.prevX, self.prevY, self.x, self.y)
	self.prevX, self.prevY = self.x, self.y

	while self.trailDist >= self.segmentSeparation do
		self.trailDist = self.trailDist - self.segmentSeparation
		table.insert(self.trail, 1, { x = self.x, y = self.y })
	end
	while #self.trail > self.segmentCount do
		table.remove(self.trail)
	end
end

-- EnemySelectScene's preview pane (see the module comment above and
-- EnemySelectScene.lua:54) is a small fixed-width box (MenuCard's descWidth,
-- ~180px, shared with 4 lines of stat text stacked below the image -- see
-- MenuCard.build/buildEnemyDesc), not the full game screen -- so the static
-- reference pose below only draws the head plus PREVIEW_SEGMENT_COUNT
-- trailing segments, AND clamps its overall size to PREVIEW_MAX_RADIUS
-- (comparable to the other enemies' own natural preview sizes, e.g.
-- EnemyRogueWave's LENGTH=34). Capping segment count alone isn't enough --
-- Config.ENEMY_SEA_SERPENT_SEGMENT_RADIUS/SEPARATION/HEAD_LENGTH can each be
-- tuned arbitrarily large on their own, and playout's box lays the image out
-- at a fixed `width` (see buildEnemyDesc), so an oversized image gets cropped
-- to that column instead of shrinking to fit -- reading as the preview
-- "vanishing" when only a sliver of the head or body happens to land inside
-- the visible column. Scaling every preview dimension down together (see
-- previewDimensions below) keeps the whole pose comfortably inside frame
-- instead of just moving where the cropping happens. Only affects this
-- static preview: the live, moving :draw() below reads self.trail directly
-- (all segmentCount of it, at the real configured size) and never calls
-- buildBodyImage.
local PREVIEW_SEGMENT_COUNT = 1
local PREVIEW_MAX_RADIUS = 32

-- Head/segment dimensions to use for the static preview pose -- the real
-- self.headLength/headWidth/segmentRadius/segmentSeparation, uniformly scaled
-- down (never up) so the pose's own bounding radius never exceeds
-- PREVIEW_MAX_RADIUS -- see the comment above.
---@return integer segmentCount capped to PREVIEW_SEGMENT_COUNT
---@return number headLength
---@return number headWidth
---@return number segmentRadius
---@return number segmentSeparation
function EnemySeaSerpent:previewDimensions()
	local n = math.min(PREVIEW_SEGMENT_COUNT, self.segmentCount)
	local natural = math.max(self.headLength, n * self.segmentSeparation + self.segmentRadius)
	local scale = natural > PREVIEW_MAX_RADIUS and (PREVIEW_MAX_RADIUS / natural) or 1
	return n, self.headLength * scale, self.headWidth * scale, self.segmentRadius * scale, self.segmentSeparation * scale
end

-- Static reference pose for EnemySelectScene's preview pane (Ship:buildBodyImage
-- bakes this once via Ship:drawBodyLocal) -- the body ellipses laid out in a
-- straight line astern since there's no real travelled path to draw from for
-- a preview icon. Sized via previewDimensions -- see above.
---@param cx number
---@param cy number
function EnemySeaSerpent:drawBodyLocal(cx, cy)
	local n, headLength, headWidth, segmentRadius, segmentSeparation = self:previewDimensions()

	gfx.setColor(self.color)
	for i = n, 1, -1 do
		local sx = cx - segmentSeparation * i
		gfx.fillEllipseInRect(sx - segmentRadius, cy - segmentRadius, segmentRadius * 2, segmentRadius * 2)
	end

	local tipX, tipY = cx + headLength, cy
	gfx.fillTriangle(tipX, tipY, cx, cy - headWidth, cx, cy + headWidth)
end

-- Bounding radius of the scaled reference pose above -- see
-- Ship:bodyRadius/buildBodyImage. Always <= PREVIEW_MAX_RADIUS by
-- construction (see previewDimensions).
---@return number
function EnemySeaSerpent:bodyRadius()
	local n, headLength, _, segmentRadius, segmentSeparation = self:previewDimensions()
	local tailReach = n * segmentSeparation + segmentRadius
	return math.max(headLength, tailReach)
end

-- Live per-frame draw. Unlike other Enemy subclasses this never goes through
-- Ship:draw/buildBodyImage: the body isn't a rigid shape that rotates with
-- the head, it's a chain of independently-positioned trail samples (see
-- updateTrail), so each part is drawn straight in world space instead of
-- baked into one rotated image.
function EnemySeaSerpent:draw()
	if not self.alive then return end

	gfx.setColor(self.color)

	-- Body first (tail to head) so the head triangle ends up drawn on top of
	-- the foremost body segment, reading as the segments trailing behind it
	-- rather than the head poking out from underneath.
	for i = self.segmentCount, 1, -1 do
		local p = self.trail[i]
		gfx.fillEllipseInRect(p.x - self.segmentRadius, p.y - self.segmentRadius,
			self.segmentRadius * 2, self.segmentRadius * 2)
	end

	local hx, hy = Utils.heading(self.heading)
	local px, py = -hy, hx
	local tipX, tipY = self.x + hx * self.headLength, self.y + hy * self.headLength
	local leftX, leftY = self.x + px * self.headWidth, self.y + py * self.headWidth
	local rightX, rightY = self.x - px * self.headWidth, self.y - py * self.headWidth
	gfx.fillTriangle(tipX, tipY, leftX, leftY, rightX, rightY)

	if self.health < self.maxHealth then
		self:drawHealthBar()
	end
end
