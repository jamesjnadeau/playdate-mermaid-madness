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
-- / :draw). A black triangle head leads the way, drawn frontmost.
--
-- On top of that, it cycles between surfaced and submerged (see
-- EnemySeaSerpent:updateSurfaceCycle/visiblePartCount): fully visible for
-- SURFACE_TIME seconds, fully hidden for DIVE_TIME, with a REVEAL_TIME
-- transition on each side where the head appears/leads first and the body
-- ellipses reveal in behind it one at a time (or, diving, disappear tail
-- first) -- like a sea serpent breaching and submerging. Movement and
-- collision keep running the whole time; only the drawing is gated, so it
-- can still ram the player while submerged. All tuning lives in
-- Config.ENEMY_SEA_SERPENT_* (see ConfigEnemy.lua).

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
---@field cycleState string "surfaced" | "hiding" | "submerged" | "revealing" -- see EnemySeaSerpent:updateSurfaceCycle
---@field cycleTimer number seconds elapsed in the current cycleState
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

	-- Starts surfaced (fully visible) so a freshly spawned serpent is an
	-- immediately visible threat rather than appearing to do nothing for up
	-- to DIVE_TIME seconds -- see updateSurfaceCycle.
	self.cycleState = "surfaced"
	self.cycleTimer = 0
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
	self:updateSurfaceCycle(dt)
	self:updateLeash(targetX, targetY, dt)
end

-- Records a new trail sample -- the head's own position -- each time it has
-- travelled segmentSeparation px since the last one, and drops the oldest
-- sample past segmentCount so the trail always has exactly one entry per body
-- segment. Runs every frame regardless of the surface/dive cycle so the body
-- keeps a coherent shape underneath the visibility gating in :draw -- see
-- updateSurfaceCycle.
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

-- Surfaced/submerged cycle: alternates SURFACE_TIME (fully visible) and
-- DIVE_TIME (fully hidden), with a REVEAL_TIME transition on each side --
-- "revealing" on the way up, "hiding" on the way down. See visiblePartCount
-- for how this state is turned into an actual part count to draw.
---@param dt number
function EnemySeaSerpent:updateSurfaceCycle(dt)
	self.cycleTimer = self.cycleTimer + dt

	if self.cycleState == "surfaced" then
		if self.cycleTimer >= Config.ENEMY_SEA_SERPENT_SURFACE_TIME then
			self.cycleState, self.cycleTimer = "hiding", 0
		end
	elseif self.cycleState == "hiding" then
		if self.cycleTimer >= Config.ENEMY_SEA_SERPENT_REVEAL_TIME then
			self.cycleState, self.cycleTimer = "submerged", 0
		end
	elseif self.cycleState == "submerged" then
		if self.cycleTimer >= Config.ENEMY_SEA_SERPENT_DIVE_TIME then
			self.cycleState, self.cycleTimer = "revealing", 0
		end
	elseif self.cycleState == "revealing" then
		if self.cycleTimer >= Config.ENEMY_SEA_SERPENT_REVEAL_TIME then
			self.cycleState, self.cycleTimer = "surfaced", 0
		end
	end
end

-- How many of the (head + segmentCount) parts are currently visible, head
-- first: 0 is fully submerged, 1 is head-only, segmentCount + 1 is fully
-- surfaced. "revealing" counts up from 0 (head appears, then leads the body
-- ellipses into view one at a time behind it); "hiding" counts back down the
-- same way, so the tail-most segment disappears first and the head goes
-- under last -- see :draw, which reads this to decide what to blit.
---@return integer
function EnemySeaSerpent:visiblePartCount()
	local total = self.segmentCount + 1
	if self.cycleState == "surfaced" then
		return total
	elseif self.cycleState == "submerged" then
		return 0
	end

	local frac = self.cycleTimer / Config.ENEMY_SEA_SERPENT_REVEAL_TIME
	if self.cycleState == "revealing" then
		return math.floor(frac * total)
	else -- "hiding"
		return math.floor((1 - frac) * total)
	end
end

-- EnemySelectScene's preview pane (see the module comment above and
-- EnemySelectScene.lua:54) is a small fixed-size box, not the full game
-- screen -- so the static reference pose below only draws the head plus this
-- many trailing segments, not the full self.segmentCount. With a long body
-- (large SEGMENT_COUNT/SEPARATION), Ship:bodyRadius/buildBodyImage would
-- otherwise bake a huge, mostly-empty square image sized off the full tail
-- length, leaving the head off in a corner of it instead of centered in the
-- preview -- capping the pose keeps the baked image small and the head
-- visibly in frame. Only affects this static preview: the live, moving
-- :draw() below reads self.trail directly (all segmentCount of it) and never
-- calls buildBodyImage.
local PREVIEW_SEGMENT_COUNT = 1

-- Static reference pose for EnemySelectScene's preview pane (Ship:buildBodyImage
-- bakes this once via Ship:drawBodyLocal) -- the body ellipses laid out in a
-- straight line astern since there's no real travelled path to draw from for
-- a preview icon. Capped to PREVIEW_SEGMENT_COUNT segments -- see above.
---@param cx number
---@param cy number
function EnemySeaSerpent:drawBodyLocal(cx, cy)
	gfx.setColor(self.color)
	for i = math.min(PREVIEW_SEGMENT_COUNT, self.segmentCount), 1, -1 do
		local sx = cx - self.segmentSeparation * i
		gfx.fillEllipseInRect(sx - self.segmentRadius, cy - self.segmentRadius,
			self.segmentRadius * 2, self.segmentRadius * 2)
	end

	local tipX, tipY = cx + self.headLength, cy
	gfx.fillTriangle(tipX, tipY, cx, cy - self.headWidth, cx, cy + self.headWidth)
end

-- Bounding radius of the capped reference pose above -- see
-- Ship:bodyRadius/buildBodyImage.
---@return number
function EnemySeaSerpent:bodyRadius()
	local n = math.min(PREVIEW_SEGMENT_COUNT, self.segmentCount)
	local tailReach = n * self.segmentSeparation + self.segmentRadius
	return math.max(self.headLength, tailReach)
end

-- Live per-frame draw. Unlike other Enemy subclasses this never goes through
-- Ship:draw/buildBodyImage: the body isn't a rigid shape that rotates with
-- the head, it's a chain of independently-positioned trail samples (see
-- updateTrail), so each part is drawn straight in world space instead of
-- baked into one rotated image. visiblePartCount gates how many parts (head
-- first) actually get drawn this frame -- see updateSurfaceCycle.
function EnemySeaSerpent:draw()
	if not self.alive then return end

	local visible = self:visiblePartCount()
	if visible <= 0 then return end

	gfx.setColor(self.color)

	-- Body first (tail to head) so the head triangle ends up drawn on top of
	-- the foremost body segment, reading as the segments trailing behind it
	-- rather than the head poking out from underneath.
	local segmentsVisible = visible - 1
	for i = segmentsVisible, 1, -1 do
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
