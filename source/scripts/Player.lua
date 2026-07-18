-- Player.lua
-- The player-controlled pirate ship.

import "scripts/Config"
import "scripts/Utils"
import "scripts/Ship"

local gfx <const> = playdate.graphics

class("Player").extends(Ship)

function Player:init(x, y)
	Player.super.init(self, x, y, -90) -- start pointing "north"
	self.speed = 0
	self.health = Config.SHIP_MAX_HEALTH
	self.invuln = 0
	self.length = Config.SHIP_LENGTH
	self.color = gfx.kColorWhite
	self.outlineColor = gfx.kColorBlack

	local L, B = Config.SHIP_LENGTH, Config.SHIP_BEAM
	self.hull = { L, 0,  -L * 0.7, B,  -L, B * 0.55,  -L, -B * 0.55,  -L * 0.7, -B }

	self.wake = ParticleCircle(x, y)
	self.wake:setMode(Particles.modes.DECAY)
	self.wake:setSize(2, 4)
	self.wake:setDecay(0.35)
	self.wake:setSpeed(1, 3)
	self.wake:setColor(gfx.kColorBlack)
end

function Player:steer(crankChange)
	self.heading = Utils.wrapDeg(self.heading + crankChange * Config.SHIP_TURN_SCALE)
end

function Player:changeSpeed(dir)
	self.speed = Utils.clamp(self.speed + dir * Config.SHIP_ACCEL * Config.DT, 0, Config.SHIP_MAX_SPEED)
end

function Player:update()
	local dt = Config.DT
	if self.invuln > 0 then self.invuln = self.invuln - dt end

	local hx, hy = Utils.heading(self.heading)
	self.x = Utils.clamp(self.x + hx * self.speed * dt, 0, Config.WORLD_W)
	self.y = Utils.clamp(self.y + hy * self.speed * dt, 0, Config.WORLD_H)

	if self.speed > 8 then
		local sx, sy = self:sternPosition()
		self.wake:moveTo(sx, sy)
		local back = math.floor(Utils.wrapDeg(self.heading + 180))
		self.wake:setSpread(back - 22, back + 22)
		self.wake:add(self.speed > 70 and 2 or 1)
	end
end

function Player:hit(damage)
	if self.invuln > 0 then return false end
	Player.super.hit(self, damage)
	self.invuln = 1.0
	return true
end

function Player:draw()
	if self.invuln > 0 and (math.floor(self.invuln * 12) % 2 == 0) then
		return
	end
	Player.super.draw(self)

	local hx, hy = Utils.heading(self.heading)
	gfx.fillCircleAtPoint(self.x + hx * 3, self.y + hy * 3, 3)
end