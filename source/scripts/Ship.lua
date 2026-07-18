-- Ship.lua
-- Base class for all ships (player and enemy).

import "scripts/Config"
import "scripts/Utils"

local gfx <const> = playdate.graphics

class("Ship").extends()

-- Default explosion look for every ship; subclasses can overwrite the whole
-- table (Enemy.explosionConfig = {...}) or set self.explosionConfig in init()
-- to override just this instance.
Ship.explosionConfig = Config.EXPLOSION

local function rotatePts(pts, deg, ox, oy)
	local r = deg * math.pi / 180
	local c, s = math.cos(r), math.sin(r)
	local out = {}
	for i = 1, #pts, 2 do
		local lx, ly = pts[i], pts[i + 1]
		out[#out + 1] = ox + (lx * c - ly * s)
		out[#out + 1] = oy + (lx * s + ly * c)
	end
	return out
end

local function fillFan(p)
	local n = #p // 2
	for i = 2, n - 1 do
		gfx.fillTriangle(p[1], p[2], p[i * 2 - 1], p[i * 2], p[i * 2 + 1], p[i * 2 + 2])
	end
end

local function strokeLoop(p)
	local n = #p // 2
	for i = 1, n do
		local j = (i % n) + 1
		gfx.drawLine(p[i * 2 - 1], p[i * 2], p[j * 2 - 1], p[j * 2])
	end
end

function Ship:init(x, y, heading)
	self.x = x
	self.y = y 
	self.heading = heading or 0
	self.alive = true
end

function Ship:sternPosition()
	local hx, hy = Utils.heading(self.heading)
	return self.x - hx * self.length, self.y - hy * self.length
end

function Ship:update()
	-- Subclasses should override this method.
end

function Ship:hit(damage)
	self.health = self.health - damage
	if self.health <= 0 then
		self.alive = false
	end
end

function Ship:explosionOrigin()
	return self.x, self.y
end

-- Spawns this ship's explosion particle system and returns the record the
-- scene tracks to update/prune it: { sys, age, maxAge }.
function Ship:explode()
	local cfg = self.explosionConfig
	local x, y = self:explosionOrigin()
	local sys = ParticleCircle(x, y)
	sys:setMode(cfg.mode)
	sys:setSize(cfg.size[1], cfg.size[2])
	sys:setSpeed(cfg.speed[1], cfg.speed[2])
	sys:setSpread(cfg.spread[1], cfg.spread[2])
	sys:setLifespan(cfg.lifespan[1], cfg.lifespan[2])
	sys:setColor(cfg.color)
	sys:add(cfg.count)
	return { sys = sys, age = 0, maxAge = cfg.maxAge }
end

function Ship:draw()
	if not self.alive then return end
	local p = rotatePts(self.hull, self.heading, self.x, self.y)
	gfx.setColor(self.color)
	fillFan(p)
	if self.outlineColor then
		gfx.setColor(self.outlineColor)
		gfx.setLineWidth(2)
		strokeLoop(p) 
	end
end