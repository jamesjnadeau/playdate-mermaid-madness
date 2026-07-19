-- StormCloud.lua
-- A slow-moving hazard summoned by the "Storm Cloud" upgrade
-- (source/scripts/ConfigUpgrades.lua): drifts toward whichever enemy is
-- currently nearest and, on a fixed interval, damages every enemy within
-- Config.STORM_CLOUD_RADIUS -- not just the one it's drifting toward, so a
-- second enemy that wanders into range still takes damage. Unlike
-- Tridentball it never expires and isn't fired -- GameScene creates and
-- keeps one per stack of the upgrade (Config.STORM_CLOUD_COUNT) and owns the
-- actual damage application (see GameScene:updateStormClouds), the same
-- split as Tridentball/the trident collision loop.

import "scripts/Config"
import "scripts/Utils"

local gfx <const> = playdate.graphics

---@class StormCloud : _Object
---@field x number
---@field y number
---@field damageTimer number seconds until this cloud's next damage tick, see GameScene:updateStormClouds
StormCloud = class("StormCloud").extends() or StormCloud

---@param x number
---@param y number
function StormCloud:init(x, y)
	StormCloud.super.init(self)
	self.x = x
	self.y = y
	self.damageTimer = Config.STORM_CLOUD_DAMAGE_INTERVAL
end

-- Drifts toward the nearest entry in `enemies` at Config.STORM_CLOUD_SPEED;
-- idles in place if `enemies` is empty. Also counts down damageTimer --
-- GameScene checks/resets it and applies the actual damage once it elapses
-- (see updateStormClouds), the same split of duties as Tridentball's
-- self.life/self.dead and GameScene's tridentball collision loop.
---@param enemies Enemy[]
---@param dt number
function StormCloud:update(enemies, dt)
	local best, bestD2 = nil, math.huge
	for _, e in ipairs(enemies) do
		local dx, dy = e.x - self.x, e.y - self.y
		local d2 = dx * dx + dy * dy
		if d2 < bestD2 then
			bestD2 = d2
			best = e
		end
	end
	if best then
		local dir = Utils.angleTo(self.x, self.y, best.x, best.y)
		local hx, hy = Utils.heading(dir)
		self.x = self.x + hx * Config.STORM_CLOUD_SPEED * dt
		self.y = self.y + hy * Config.STORM_CLOUD_SPEED * dt
	end
	self.damageTimer = self.damageTimer - dt
end

-- Drawn as three overlapping circle outlines (a wide flat-bottomed puff)
-- plus a small zigzag bolt underneath, so it reads as a storm cloud rather
-- than a plain circle on the 1-bit display.
function StormCloud:draw()
	local r = Config.STORM_CLOUD_RADIUS
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(Config.STORM_CLOUD_LINE_WIDTH)
	gfx.drawCircleAtPoint(self.x - r * 0.5, self.y, r * 0.55)
	gfx.drawCircleAtPoint(self.x + r * 0.5, self.y, r * 0.55)
	gfx.drawCircleAtPoint(self.x, self.y - r * 0.15, r * 0.7)

	local bx, by = self.x, self.y + r * 0.35
	gfx.drawLine(bx - 3, by, bx + 3, by + r * 0.25)
	gfx.drawLine(bx + 3, by + r * 0.25, bx - 2, by + r * 0.25)
	gfx.drawLine(bx - 2, by + r * 0.25, bx + 4, by + r * 0.55)
	gfx.setLineWidth(1)
end
