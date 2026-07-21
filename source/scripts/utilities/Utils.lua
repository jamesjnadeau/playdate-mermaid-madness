-- Utils.lua
-- Small math / drawing helpers shared across the game.

---@class Utils
Utils = {}

local gfx <const> = playdate.graphics
local sqrt <const> = math.sqrt
local sin <const> = math.sin
local cos <const> = math.cos
local atan2 <const> = math.atan  -- Lua 5.4: math.atan(y, x) works like atan2
local pi <const> = math.pi

---@param v number
---@param lo number
---@param hi number
---@return number
function Utils.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- Wrap an angle (degrees) into [0, 360)
---@param a number
---@return number
function Utils.wrapDeg(a)
	a = a % 360
	if a < 0 then a = a + 360 end
	return a
end

-- Shortest signed difference from a to b, in degrees, range (-180, 180].
---@param a number
---@param b number
---@return number
function Utils.angleDiff(a, b)
	local d = (b - a) % 360
	if d > 180 then d = d - 360 end
	return d
end

---@param d number
---@return number
function Utils.deg2rad(d) return d * pi / 180 end
---@param r number
---@return number
function Utils.rad2deg(r) return r * 180 / pi end

---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return number
function Utils.dist(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	return sqrt(dx * dx + dy * dy)
end

---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return number
function Utils.dist2(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	return dx * dx + dy * dy
end

-- Angle (degrees) pointing from (x1,y1) toward (x2,y2). 0 = +x (east).
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return number
function Utils.angleTo(x1, y1, x2, y2)
	return Utils.rad2deg(atan2(y2 - y1, x2 - x1))
end

-- Unit vector for a heading in degrees.
---@param deg number
---@return number ux
---@return number uy
function Utils.heading(deg)
	local r = Utils.deg2rad(deg)
	return cos(r), sin(r)
end

-- Draw a dashed/dotted line between two points (screen space).
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param dash? number
---@param gap? number
function Utils.drawDottedLine(x1, y1, x2, y2, dash, gap)
	dash = dash or 4
	gap = gap or 4
	local dx, dy = x2 - x1, y2 - y1
	local len = sqrt(dx * dx + dy * dy)
	if len < 1 then return end
	local ux, uy = dx / len, dy / len
	local step = dash + gap
	local d = 0
	while d < len do
		local sx = x1 + ux * d
		local sy = y1 + uy * d
		local e = d + dash
		if e > len then e = len end
		local ex = x1 + ux * e
		local ey = y1 + uy * e
		gfx.drawLine(sx, sy, ex, ey)
		d = d + step
	end
end

-- Jagged lightning-bolt path from (x1,y1) to (x2,y2): interpolates
-- `segments` points evenly along the straight line and offsets each interior
-- one (not the two endpoints, which stay exact) perpendicular to the line by
-- a random amount up to +/-`jitter` px, giving the zigzag "electric" look
-- instead of a straight stroke. Returned flat (x,y pairs in one array) so
-- it's easy to store on a bolt effect and hand straight to Utils.drawPolyline
-- every frame without recomputing the shape -- see
-- GameScene:updateStormClouds/drawStormBolts.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param segments integer
---@param jitter number
---@return number[] points flat x,y pairs from (x1,y1) to (x2,y2)
function Utils.lightningBoltPoints(x1, y1, x2, y2, segments, jitter)
	local dx, dy = x2 - x1, y2 - y1
	local len = sqrt(dx * dx + dy * dy)
	local nx, ny = 0, 0
	if len > 0 then nx, ny = -dy / len, dx / len end

	local points = { x1, y1 }
	for i = 1, segments - 1 do
		local t = i / segments
		local offset = (math.random() * 2 - 1) * jitter
		points[#points + 1] = x1 + dx * t + nx * offset
		points[#points + 1] = y1 + dy * t + ny * offset
	end
	points[#points + 1] = x2
	points[#points + 1] = y2
	return points
end

-- Draws straight segments through flat x,y pairs (see
-- Utils.lightningBoltPoints), connecting each consecutive point with
-- gfx.drawLine.
---@param points number[]
function Utils.drawPolyline(points)
	for i = 1, #points - 2, 2 do
		gfx.drawLine(points[i], points[i + 1], points[i + 2], points[i + 3])
	end
end

-- Draws a trident glyph: a shaft trailing behind a crossbar, with three
-- prongs (center + two spread outward) sticking forward from the crossbar
-- toward dirDeg. (tipX, tipY) is the leading point (the center prong's tip);
-- everything else is laid out behind it along dirDeg. Shared by
-- Tridentball.lua (the fired projectile, sized off Config.TRIDENT_*) and
-- Player:drawAmmoIcons (the HUD ammo icons, sized off Config.AMMO_ICON_*).
---@param tipX number
---@param tipY number
---@param dirDeg number
---@param shaftLength number
---@param prongLength number
---@param prongSpread number
function Utils.drawTridentGlyph(tipX, tipY, dirDeg, shaftLength, prongLength, prongSpread)
	local hx, hy = Utils.heading(dirDeg)
	local px, py = -hy, hx

	local crossX = tipX - hx * prongLength
	local crossY = tipY - hy * prongLength
	local tailX = crossX - hx * shaftLength
	local tailY = crossY - hy * shaftLength
	local leftX = crossX + px * prongSpread
	local leftY = crossY + py * prongSpread
	local rightX = crossX - px * prongSpread
	local rightY = crossY - py * prongSpread

	gfx.drawLine(tailX, tailY, crossX, crossY) -- shaft
	gfx.drawLine(leftX, leftY, rightX, rightY) -- crossbar
	gfx.drawLine(crossX, crossY, tipX, tipY) -- center prong
	gfx.drawLine(leftX, leftY, leftX + hx * prongLength, leftY + hy * prongLength) -- left prong
	gfx.drawLine(rightX, rightY, rightX + hx * prongLength, rightY + hy * prongLength) -- right prong
end

return Utils
