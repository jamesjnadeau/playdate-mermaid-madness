-- Tridentball.lua
-- A projectile fired from the ship toward an auto-targeted enemy.

import "scripts/utilities/Config"
import "scripts/utilities/Utils"

local gfx <const> = playdate.graphics

---@class Tridentball : _Object
---@field x number tip position -- also the leading point used for collision
---@field y number
---@field dir number heading in degrees
---@field vx number px/s
---@field vy number px/s
---@field life number seconds remaining before it falls in the sea
---@field radius number collision radius
---@field damage number health removed from an enemy on hit
---@field dead boolean
Tridentball = class("Tridentball").extends() or Tridentball

---@param x number
---@param y number
---@param dirDeg number
---@param speed number
---@param damage? number defaults to Config.TRIDENT_DAMAGE -- the autofire cannon passes its own value here
function Tridentball:init(x, y, dirDeg, speed, damage)
	Tridentball.super.init(self)
	self.x = x
	self.y = y
	self.dir = dirDeg
	local hx, hy = Utils.heading(dirDeg)
	self.vx = hx * speed
	self.vy = hy * speed
	self.life = Config.TRIDENT_LIFETIME
	self.radius = Config.TRIDENT_RADIUS
	self.damage = damage or Config.TRIDENT_DAMAGE
	self.dead = false
end

function Tridentball:update()
	local dt = Config.DT
	self.x = self.x + self.vx * dt
	self.y = self.y + self.vy * dt
	self.life = self.life - dt
	if self.life <= 0 then self.dead = true end
end

-- Drawn as a trident glyph rather than a ball -- see Utils.drawTridentGlyph.
-- (self.x, self.y) is the tip -- the leading point used for collision.
function Tridentball:draw()
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(Config.TRIDENT_LINE_WIDTH)
	Utils.drawTridentGlyph(self.x, self.y, self.dir,
		Config.TRIDENT_SHAFT_LENGTH, Config.TRIDENT_PRONG_LENGTH, Config.TRIDENT_PRONG_SPREAD)
	gfx.setLineWidth(1)
end
