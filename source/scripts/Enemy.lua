-- Enemy.lua
-- A hostile ship that steers toward the player and rams them.

import "scripts/Config"
import "scripts/Utils"
import "scripts/Ship"

local gfx <const> = playdate.graphics

class("Enemy").extends(Ship)

function Enemy:init(x, y, heading)
	Enemy.super.init(self, x, y, heading)
	self.radius = Config.ENEMY_RADIUS
	self.length = 16
	self.color = gfx.kColorBlack
	self.health = 1

	local L, B = 16, 8
	self.hull = { L, 0,  -L * 0.7, B,  -L, B * 0.55,  -L, -B * 0.55,  -L * 0.7, -B }
end

function Enemy:update(targetX, targetY)
	local dt = Config.DT
	local want = Utils.angleTo(self.x, self.y, targetX, targetY)
	local diff = Utils.angleDiff(self.heading, want)
	local maxTurn = Config.ENEMY_TURN_RATE * dt
	if diff > maxTurn then diff = maxTurn elseif diff < -maxTurn then diff = -maxTurn end
	self.heading = Utils.wrapDeg(self.heading + diff)

	local hx, hy = Utils.heading(self.heading)
	self.x = self.x + hx * Config.ENEMY_SPEED * dt
	self.y = self.y + hy * Config.ENEMY_SPEED * dt
end

function Enemy:draw()
	Enemy.super.draw(self)
	
	local hx, hy = Utils.heading(self.heading)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillCircleAtPoint(self.x + hx * 6, self.y + hy * 6, 2)
end