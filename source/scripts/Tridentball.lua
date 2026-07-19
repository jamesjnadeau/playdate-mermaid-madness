-- Tridentball.lua
-- A projectile fired from the ship toward an auto-targeted enemy.

import "scripts/Config"
import "scripts/Utils"

local gfx <const> = playdate.graphics

---@class Tridentball : _Object
---@field x number tip position -- also the leading point used for collision
---@field y number
---@field dir number heading in degrees
---@field vx number px/s
---@field vy number px/s
---@field life number seconds remaining before it falls in the sea
---@field radius number collision radius
---@field dead boolean
Tridentball = class("Tridentball").extends() or Tridentball

---@param x number
---@param y number
---@param dirDeg number
---@param speed number
function Tridentball:init(x, y, dirDeg, speed)
	Tridentball.super.init(self)
	self.x = x
	self.y = y
	self.dir = dirDeg
	local hx, hy = Utils.heading(dirDeg)
	self.vx = hx * speed
	self.vy = hy * speed
	self.life = Config.TRIDENT_LIFETIME
	self.radius = Config.TRIDENT_RADIUS
	self.dead = false
end

function Tridentball:update()
	local dt = Config.DT
	self.x = self.x + self.vx * dt
	self.y = self.y + self.vy * dt
	self.life = self.life - dt
	if self.life <= 0 then self.dead = true end
end

-- Drawn as a trident glyph rather than a ball: a shaft trailing behind a
-- crossbar, with three prongs (center + two spread outward) sticking forward
-- from the crossbar toward the direction of travel. (self.x, self.y) is the
-- tip -- the leading point used for collision -- everything else is laid out
-- behind it along self.dir.
function Tridentball:draw()
	local hx, hy = Utils.heading(self.dir)
	local px, py = -hy, hx

	local tipX, tipY = self.x, self.y
	local crossX = tipX - hx * Config.TRIDENT_PRONG_LENGTH
	local crossY = tipY - hy * Config.TRIDENT_PRONG_LENGTH
	local tailX = crossX - hx * Config.TRIDENT_SHAFT_LENGTH
	local tailY = crossY - hy * Config.TRIDENT_SHAFT_LENGTH
	local leftX = crossX + px * Config.TRIDENT_PRONG_SPREAD
	local leftY = crossY + py * Config.TRIDENT_PRONG_SPREAD
	local rightX = crossX - px * Config.TRIDENT_PRONG_SPREAD
	local rightY = crossY - py * Config.TRIDENT_PRONG_SPREAD

	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(Config.TRIDENT_LINE_WIDTH)
	gfx.drawLine(tailX, tailY, crossX, crossY) -- shaft
	gfx.drawLine(leftX, leftY, rightX, rightY) -- crossbar
	gfx.drawLine(crossX, crossY, tipX, tipY) -- center prong
	gfx.drawLine(leftX, leftY, leftX + hx * Config.TRIDENT_PRONG_LENGTH, leftY + hy * Config.TRIDENT_PRONG_LENGTH) -- left prong
	gfx.drawLine(rightX, rightY, rightX + hx * Config.TRIDENT_PRONG_LENGTH, rightY + hy * Config.TRIDENT_PRONG_LENGTH) -- right prong
	gfx.setLineWidth(1)
end
