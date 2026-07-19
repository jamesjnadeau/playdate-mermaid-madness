-- Player.lua
-- The player-controlled pirate ship.

import "scripts/Config"
import "scripts/Utils"
import "scripts/Ship"

local gfx <const> = playdate.graphics

---@class Player : Ship
---@field invuln number seconds of remaining hit-invulnerability, see Player:hit
---@field sailTrim number 0 (trimmed in) - 1 (fully out), see Player:adjustSailTrim
---@field windDirection number last wind direction passed to Player:update
---@field sailAngle number animated world-space boom angle, see Player:updateSailAngle
---@field sailAngularVelocity number deg/s, see Player:updateSailAngle
---@field wakePort table ParticleCircle
---@field wakeStarboard table ParticleCircle
Player = class("Player").extends(Ship) or Player

---@param x number
---@param y number
function Player:init(x, y)
	Player.super.init(self, x, y, -90) -- start pointing "north"
	self.speed = 0
	self.health = Config.SHIP_MAX_HEALTH
	self.invuln = 0
	self.length = Config.SHIP_LENGTH
	self.color = gfx.kColorWhite
	self.outlineColor = gfx.kColorBlack
	self.sailTrim = Config.SAIL_TRIM_START
	self.windDirection = 0
	self.sailAngle = self:sailTargetAngle()
	self.sailAngularVelocity = 0

	-- Hull Setup
	local L, B = Config.SHIP_LENGTH, Config.SHIP_BEAM
	self.hull = { L, 0,  -L * 0.7, B,  -L, B * 0.55,  -L, -B * 0.55,  -L * 0.7, -B }

	-- Wake Setup: one stream off each side of the hull's widest point.
	self.wakePort = ParticleCircle(x, y)
	self.wakeStarboard = ParticleCircle(x, y)
	for _, wake in ipairs({ self.wakePort, self.wakeStarboard }) do
		wake:setMode(Particles.modes.DECAY)
		wake:setSize(2, 4)
		wake:setDecay(0.35)
		wake:setSpeed(1, 3)
		wake:setColor(gfx.kColorBlack)
	end
end

-- takes player input and steers the boat
---@param crankChange number
function Player:steer(crankChange)
	self.heading = Utils.wrapDeg(self.heading + crankChange * Config.SHIP_TURN_SCALE)
end

-- Lets out or hauls in the main line; delta is trim units (see
-- Config.SAIL_TRIM_RATE), positive = let out (more slack), negative = haul
-- in. This only ever changes how far the boom is ALLOWED to swing -- see
-- sailTargetAngle() for where it ends up settling.
---@param delta number
function Player:adjustSailTrim(delta)
	self.sailTrim = Utils.clamp(self.sailTrim + delta, 0, 1)
end

-- The boom's resting world-space angle, i.e. where it's headed -- not where
-- it actually is right now (see self.sailAngle / updateSailAngle for the
-- animated position the physics and drawing code actually use). The main
-- line doesn't aim the sail at the wind -- it only limits how far the boom
-- can swing out from the centerline. Wherever the wind would push a totally
-- free boom (capped at the rigging limit, since it can't swing forward past
-- abeam) is where the boom sits, right up until the main line is hauled in
-- far enough to start holding it in tighter than that -- only then does
-- trimming in actually move the sail. With enough slack (trim let most of
-- the way out) that resting angle lands on the wind direction itself, i.e.
-- the sail flops to lie parallel with the wind.
---@return number
function Player:sailTargetAngle()
	local aft = Utils.wrapDeg(self.heading + 180)
	local freeOffset = Utils.clamp(Utils.angleDiff(aft, self.windDirection),
		-Config.SAIL_MAX_ANGLE, Config.SAIL_MAX_ANGLE)
	local sheetLimit = Config.SAIL_MAX_ANGLE * self.sailTrim
	local sign = freeOffset >= 0 and 1 or -1
	local offset = sign * math.min(math.abs(freeOffset), sheetLimit)
	return Utils.wrapDeg(aft + offset)
end

-- Eases self.sailAngle toward sailTargetAngle() like a lightly damped
-- spring instead of snapping straight there: SAIL_SWING_SPEED is the
-- stiffness (how hard the boom accelerates to close the gap), SAIL_SWING_FRICTION
-- bleeds off angular velocity each second so the swing settles instead of
-- oscillating forever. This is what makes a slack sail visibly flop over to
-- the wind rather than teleporting there.
---@param dt number
function Player:updateSailAngle(dt)
	local target = self:sailTargetAngle()
	local diff = Utils.angleDiff(self.sailAngle, target)
	self.sailAngularVelocity = self.sailAngularVelocity + diff * Config.SAIL_SWING_SPEED * dt
	self.sailAngularVelocity = self.sailAngularVelocity - self.sailAngularVelocity * Config.SAIL_SWING_FRICTION * dt
	self.sailAngle = Utils.wrapDeg(self.sailAngle + self.sailAngularVelocity * dt)
end

-- How much of the wind's push the sail catches: zero when the sail lies
-- parallel to the wind (luffing, no surface presented to catch it), peaking
-- as it swings broadside (perpendicular) to the wind.
---@param sailAngle number
---@param windDirection number
---@return number
local function sailPower(sailAngle, windDirection)
	local angleToWind = Utils.angleDiff(sailAngle, windDirection)
	return math.abs(math.sin(Utils.deg2rad(angleToWind))) * Config.SHIP_WIND_POWER_MULTIPLIER
end

---@param windDirection number
---@param windSpeed number
function Player:update(windDirection, windSpeed)
	local dt = Config.DT
	if self.invuln > 0 then self.invuln = self.invuln - dt end
	self.windDirection = windDirection
	self:updateSailAngle(dt)

	-- Wind only ever adds on top of the guaranteed baseline speed, so a bad
	-- point of sail (or a slack, luffing sail) never stalls the ship or
	-- pushes it backwards -- it just forgoes the bonus. Trim's whole effect
	-- runs through sailTargetAngle() (the main line limits the boom's angle);
	-- it's not double-counted as a separate multiplier here. Power is driven
	-- off the animated self.sailAngle, not the target, so the ship doesn't
	-- catch wind until the boom actually swings into it.
	local windBoost = math.max(0, sailPower(self.sailAngle, windDirection) * windSpeed)
	local targetSpeed = Config.SHIP_DEFAULT_SPEED + windBoost
	self:updateSpeed(targetSpeed, Config.SHIP_ACCEL, dt)

	local hx, hy = Utils.heading(self.heading)
	self.x = self.x + hx * self.speed * dt
	self.y = self.y + hy * self.speed * dt

	if self.speed > 8 then
		local back = Utils.wrapDeg(self.heading + 180)
		local center = math.floor(Utils.wrapDeg(back
			+ Utils.angleDiff(back, windDirection) * Config.WAKE_WIND_INFLUENCE))
		local count = self.speed > 70 and 2 or 1

		local px, py = self:beamPosition(Config.SHIP_BEAM)
		self.wakePort:moveTo(px, py)
		self.wakePort:setSpread(center - 22, center + 22)
		self.wakePort:add(count)

		local sx, sy = self:beamPosition(-Config.SHIP_BEAM)
		self.wakeStarboard:moveTo(sx, sy)
		self.wakeStarboard:setSpread(center - 22, center + 22)
		self.wakeStarboard:add(count)
	end
end

function Player:drawWake()
	self.wakePort:update()
	self.wakeStarboard:update()
end

---@param damage number
---@return boolean applied false if already invulnerable
function Player:hit(damage)
	if self.invuln > 0 then return false end
	Player.super.hit(self, damage)
	self.invuln = 1.0
	return true
end

-- Bakes the small bow dot into the cached body image alongside the hull --
-- see Ship:drawBodyLocal/buildBodyImage.
---@param cx number
---@param cy number
function Player:drawBodyLocal(cx, cy)
	Player.super.drawBodyLocal(self, cx, cy)
	gfx.setColor(self.outlineColor)
	gfx.fillCircleAtPoint(cx + 3, cy, 3)
end

function Player:drawSail()
	local hx, hy = Utils.heading(self.sailAngle)
	local tipX, tipY = self.x + hx * Config.SAIL_LENGTH, self.y + hy * Config.SAIL_LENGTH

	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(2)
	gfx.drawLine(self.x, self.y, tipX, tipY)

	-- Main line (mainsheet): runs from the stern to the end of the boom.
	local sx, sy = self:sternPosition()
	gfx.setLineWidth(1)
	gfx.drawLine(sx, sy, tipX, tipY)
end

function Player:draw()
	if self.invuln > 0 and (math.floor(self.invuln * 12) % 2 == 0) then
		return
	end
	Player.super.draw(self)
	self:drawSail()
end