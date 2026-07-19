-- Ship.lua
-- Base class for all ships (player and enemy).

import "scripts/Config"
import "scripts/Utils"

local gfx <const> = playdate.graphics

-- Base class for Player/Enemy; never instantiated directly, so fields below
-- that aren't set in Ship:init() (length, speed, health, hull, color,
-- outlineColor, bodyImage) are the contract subclasses' own init()s fill in.
---@class Ship : _Object
---@field x number
---@field y number
---@field heading number world-space degrees, 0 = +x (east)
---@field alive boolean
---@field length number half-length of the hull, used by sternPosition/beamPosition
---@field speed number px/s, see Ship:updateSpeed
---@field health number
---@field hull? number[] flat {x1,y1,x2,y2,...} polygon in local space, nil for hull-less ships like EnemyKraken
---@field color integer a playdate.graphics kColor*
---@field outlineColor? integer a playdate.graphics kColor*
---@field bodyImage? _Image lazily baked by Ship:buildBodyImage
---@field explosionConfig table see Config.EXPLOSION
Ship = class("Ship").extends() or Ship

-- Default explosion look for every ship; subclasses can overwrite the whole
-- table (Enemy.explosionConfig = {...}) or set self.explosionConfig in init()
-- to override just this instance.
Ship.explosionConfig = Config.EXPLOSION

---@param pts number[]
---@param deg number
---@param ox number
---@param oy number
---@return number[]
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

---@param p number[]
local function fillFan(p)
	local n = #p // 2
	for i = 2, n - 1 do
		gfx.fillTriangle(p[1], p[2], p[i * 2 - 1], p[i * 2], p[i * 2 + 1], p[i * 2 + 2])
	end
end

---@param p number[]
local function strokeLoop(p)
	local n = #p // 2
	for i = 1, n do
		local j = (i % n) + 1
		gfx.drawLine(p[i * 2 - 1], p[i * 2], p[j * 2 - 1], p[j * 2])
	end
end

---@param x number
---@param y number
---@param heading? number
function Ship:init(x, y, heading)
	self.x = x
	self.y = y
	self.heading = heading or 0
	self.alive = true
end

---@return number x
---@return number y
function Ship:sternPosition()
	local hx, hy = Utils.heading(self.heading)
	return self.x - hx * self.length, self.y - hy * self.length
end

-- The widest point of the hull (where the beam points sit in self.hull),
-- 0.7 * length back from the bow -- see the hull point tables in
-- Player:init/Enemy:init. An optional sideOffset shifts the point
-- perpendicular to the heading (positive = to port), landing it on the
-- port/starboard edge of the hull instead of the centerline.
---@param sideOffset? number
---@return number x
---@return number y
function Ship:beamPosition(sideOffset)
	sideOffset = sideOffset or 0
	local hx, hy = Utils.heading(self.heading)
	local bx = self.x - hx * self.length * 0.7
	local by = self.y - hy * self.length * 0.7
	return bx - hy * sideOffset, by + hx * sideOffset
end

function Ship:update()
	-- Subclasses should override this method.
end

-- Eases self.speed toward targetSpeed at accel px/s^2, then applies water
-- friction: a continuous drag that bleeds off Config.SHIP_WATER_FRICTION of
-- the current speed every second, shared by every ship (see Player:update,
-- Enemy:update). Any speed above Config.SHIP_MAX_SPEED (e.g. from a wind
-- boost) also bleeds off extra drag at Config.SHIP_OVERSPEED_FRICTION per
-- pixel/second over the max.
---@param targetSpeed number
---@param accel number
---@param dt number
function Ship:updateSpeed(targetSpeed, accel, dt)
	if self.speed < targetSpeed then
		self.speed = math.min(targetSpeed, self.speed + accel * dt)
	else
		self.speed = math.max(targetSpeed, self.speed - accel * dt)
	end
	self.speed = math.max(0, self.speed - self.speed * Config.SHIP_WATER_FRICTION * dt)
	local overspeed = self.speed - Config.SHIP_MAX_SPEED
	if overspeed > 0 then
		self.speed = self.speed - overspeed * Config.SHIP_OVERSPEED_FRICTION * dt
	end
end

---@param damage number
function Ship:hit(damage)
	self.health = self.health - damage
	if self.health <= 0 then
		self.alive = false
	end
end

---@return number x
---@return number y
function Ship:explosionOrigin()
	return self.x, self.y
end

-- Spawns this ship's explosion particle system and returns the record the
-- scene tracks to update/prune it: { sys, age, maxAge }. windDirection, if
-- given, bends the spread arc toward the way the wind is blowing (debris and
-- smoke drift downwind) -- see Config.EXPLOSION_WIND_INFLUENCE.
---@param windDirection? number
---@return table explosion { sys: table, age: number, maxAge: number }
function Ship:explode(windDirection)
	local cfg = self.explosionConfig
	local x, y = self:explosionOrigin()
	local sys = ParticleCircle(x, y)
	sys:setMode(cfg.mode)
	if cfg.mode == Particles.modes.DECAY then
		sys:setDecay(cfg.decay)
	end
	sys:setSize(cfg.size[1], cfg.size[2])
	sys:setSpeed(cfg.speed[1], cfg.speed[2])

	local spreadMin, spreadMax = cfg.spread[1], cfg.spread[2]
	if windDirection then
		local width = spreadMax - spreadMin
		local center = math.floor(Utils.wrapDeg((spreadMin + spreadMax) / 2
			+ Utils.angleDiff((spreadMin + spreadMax) / 2, windDirection) * Config.EXPLOSION_WIND_INFLUENCE))
		spreadMin, spreadMax = center - width / 2, center + width / 2
	end
	sys:setSpread(spreadMin, spreadMax)

	sys:setLifespan(cfg.lifespan[1], cfg.lifespan[2])
	sys:setColor(cfg.color)
	sys:add(cfg.count)
	return { sys = sys, age = 0, maxAge = cfg.maxAge }
end

-- Bounding radius (in local, unrotated space) of everything this ship draws
-- into its cached body image -- see Ship:buildBodyImage. Subclasses that draw
-- shapes further out than the hull (EnemyKraken's dots) should override this.
---@return number
function Ship:bodyRadius()
	local r = 0
	if self.hull then
		for i = 1, #self.hull, 2 do
			local d = math.sqrt(self.hull[i] * self.hull[i] + self.hull[i + 1] * self.hull[i + 1])
			if d > r then r = d end
		end
	end
	return r
end

-- Draws this ship's shape in local space (heading 0, i.e. pointing along +x)
-- centered at (cx, cy). Called once by Ship:buildBodyImage rather than every
-- frame. Subclasses that add extra fixed parts (Enemy's eye dot, Player's bow
-- dot) should call the super implementation first, then draw their own piece
-- at the same local offsets used in their live-space draw code.
---@param cx number
---@param cy number
function Ship:drawBodyLocal(cx, cy)
	local p = rotatePts(self.hull, 0, cx, cy)
	gfx.setColor(self.color)
	fillFan(p)
	if self.outlineColor then
		gfx.setColor(self.outlineColor)
		gfx.setLineWidth(2)
		strokeLoop(p)
	end
end

-- Bakes drawBodyLocal into an image once, so per-frame drawing (Ship:draw)
-- is a single rotated image blit instead of re-rotating every hull point and
-- re-filling the polygon from scratch each frame. Built lazily on first draw
-- and cached on the instance.
function Ship:buildBodyImage()
	local pad = 3 -- headroom for the 2px outline stroke
	local r = math.ceil(self:bodyRadius()) + pad
	local size = r * 2
	local img = gfx.image.new(size, size)

	gfx.pushContext(img)
	self:drawBodyLocal(r, r)
	gfx.popContext()

	self.bodyImage = img
end

function Ship:draw()
	if not self.alive then return end
	if not self.bodyImage then self:buildBodyImage() end
	self.bodyImage:drawRotated(self.x, self.y, self.heading)
end