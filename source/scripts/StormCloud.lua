-- StormCloud.lua
-- A slow-moving hazard summoned by the "Storm Cloud" upgrade
-- (source/scripts/ConfigUpgrades.lua): drifts toward whichever enemy is
-- currently nearest and, on a fixed interval, damages every enemy within
-- Config.STORM_CLOUD_RADIUS -- not just the one it's drifting toward, so a
-- second enemy that wanders into range still takes damage. With no enemy
-- around, it follows the player instead, until close enough to wander
-- randomly (see the "Idle behavior" comment in Config.lua and
-- StormCloud:update) -- an enemy appearing always takes priority over both.
-- Unlike Tridentball it never expires and isn't fired -- GameScene creates
-- and keeps one per stack of the upgrade (Config.STORM_CLOUD_COUNT) and owns
-- the actual damage application (see GameScene:updateStormClouds), the same
-- split as Tridentball/the trident collision loop.

import "scripts/Config"
import "scripts/Utils"

local gfx <const> = playdate.graphics

-- Cloud artwork, drawn at Config.STORM_CLOUD_WIDTH x STORM_CLOUD_HEIGHT (see
-- StormCloud:draw) rather than at this file's native size -- see
-- art-src/cloud.png for the hi-res original. That original's fill is a
-- near-white gray (242/255) that pdc's 1-bit dither would render as almost
-- solid white; storm-cloud.png recolors the fill to 50% gray first so it
-- dithers to a visibly gray checkerboard instead.
local cloudImage = gfx.image.new("assets/images/storm-cloud")
local cloudImageWidth, cloudImageHeight = cloudImage:getSize()

-- Random gap before the next lightning strike, see the "Lightning flash"
-- comment in Config.lua and StormCloud:update.
---@return number
local function nextFlashInterval()
	return Config.STORM_CLOUD_FLASH_MIN_INTERVAL
		+ math.random() * (Config.STORM_CLOUD_FLASH_MAX_INTERVAL - Config.STORM_CLOUD_FLASH_MIN_INTERVAL)
end

-- Random gap before an idle, in-range cloud picks a new wander heading, see
-- the "Idle behavior" comment in Config.lua and StormCloud:update.
---@return number
local function nextWanderInterval()
	return Config.STORM_CLOUD_WANDER_MIN_INTERVAL
		+ math.random() * (Config.STORM_CLOUD_WANDER_MAX_INTERVAL - Config.STORM_CLOUD_WANDER_MIN_INTERVAL)
end

-- Random point between minDist and maxDist from (cx, cy), used to land a
-- teleporting cloud just offscreen -- see the "Idle-only failsafe" comment
-- in Config.lua and StormCloud:update.
---@param cx number
---@param cy number
---@param minDist number
---@param maxDist number
---@return number x
---@return number y
local function randomPointNear(cx, cy, minDist, maxDist)
	local hx, hy = Utils.heading(math.random() * 360)
	local dist = minDist + math.random() * (maxDist - minDist)
	return cx + hx * dist, cy + hy * dist
end

---@class StormCloud : _Object
---@field x number
---@field y number
---@field damageTimer number seconds until this cloud's next damage tick, see GameScene:updateStormClouds
---@field flashPhase "white" | "black" | nil current step of a lightning strike; nil when showing the default image
---@field phaseTimer number seconds remaining in flashPhase, or seconds until the next strike when flashPhase is nil
---@field wanderAngle number heading (degrees) used while idling within STORM_CLOUD_FOLLOW_DISTANCE of the player
---@field wanderTimer number seconds until wanderAngle is re-rolled
StormCloud = class("StormCloud").extends() or StormCloud

---@param x number
---@param y number
function StormCloud:init(x, y)
	StormCloud.super.init(self)
	self.x = x
	self.y = y
	self.damageTimer = Config.STORM_CLOUD_DAMAGE_INTERVAL
	self.flashPhase = nil
	self.phaseTimer = nextFlashInterval()
	self.wanderAngle = math.random() * 360
	self.wanderTimer = nextWanderInterval()
end

-- Moves at Config.STORM_CLOUD_SPEED, picking a direction by priority: the
-- nearest enemy always wins if one exists; otherwise the player, until
-- within Config.STORM_CLOUD_FOLLOW_DISTANCE, at which point the cloud
-- wanders in a random heading (re-rolled every STORM_CLOUD_WANDER_MIN/MAX_INTERVAL
-- seconds) instead of just sitting still -- drifting back out past
-- FOLLOW_DISTANCE while wandering resumes following. If it's fallen even
-- further behind -- past STORM_CLOUD_TELEPORT_DISTANCE -- it teleports to a
-- random point just offscreen of the player instead of trudging the whole
-- way back (see the "Idle-only failsafe" comment in Config.lua). Also
-- counts down damageTimer -- GameScene checks/resets it and applies the
-- actual damage once it elapses (see updateStormClouds), the same split of
-- duties as Tridentball's self.life/self.dead and GameScene's tridentball
-- collision loop.
---@param enemies Enemy[]
---@param playerX number
---@param playerY number
---@param dt number
function StormCloud:update(enemies, playerX, playerY, dt)
	local best, bestD2 = nil, math.huge
	for _, e in ipairs(enemies) do
		local dx, dy = e.x - self.x, e.y - self.y
		local d2 = dx * dx + dy * dy
		if d2 < bestD2 then
			bestD2 = d2
			best = e
		end
	end

	local dir
	if best then
		dir = Utils.angleTo(self.x, self.y, best.x, best.y)
	else
		local distToPlayer = Utils.dist(self.x, self.y, playerX, playerY)
		if distToPlayer > Config.STORM_CLOUD_TELEPORT_DISTANCE then
			self.x, self.y = randomPointNear(playerX, playerY,
				Config.STORM_CLOUD_TELEPORT_LAND_MIN, Config.STORM_CLOUD_TELEPORT_LAND_MAX)
		elseif distToPlayer > Config.STORM_CLOUD_FOLLOW_DISTANCE then
			dir = Utils.angleTo(self.x, self.y, playerX, playerY)
		else
			self.wanderTimer = self.wanderTimer - dt
			if self.wanderTimer <= 0 then
				self.wanderAngle = math.random() * 360
				self.wanderTimer = nextWanderInterval()
			end
			dir = self.wanderAngle
		end
	end
	if dir then
		local hx, hy = Utils.heading(dir)
		self.x = self.x + hx * Config.STORM_CLOUD_SPEED * dt
		self.y = self.y + hy * Config.STORM_CLOUD_SPEED * dt
	end

	self.damageTimer = self.damageTimer - dt

	self.phaseTimer = self.phaseTimer - dt
	if self.phaseTimer <= 0 then
		if self.flashPhase == nil then
			self.flashPhase = "white"
			self.phaseTimer = Config.STORM_CLOUD_FLASH_STEP_DURATION
		elseif self.flashPhase == "white" then
			self.flashPhase = "black"
			self.phaseTimer = Config.STORM_CLOUD_FLASH_STEP_DURATION
		else
			self.flashPhase = nil
			self.phaseTimer = nextFlashInterval()
		end
	end
end

-- Drawn from cloudImage, scaled to Config.STORM_CLOUD_WIDTH x
-- STORM_CLOUD_HEIGHT and centered on (self.x, self.y). Width/height scale
-- independently (drawScaled's separate x/y scale factors), so the two config
-- values don't need to share the source art's aspect ratio. Between
-- lightning strikes (flashPhase == nil) this is the only thing drawn; during
-- a strike, kDrawModeFillWhite/FillBlack override every non-transparent
-- pixel of cloudImage to solid white or black instead, to mimic a flash --
-- see the "Lightning flash" comment in Config.lua.
function StormCloud:draw()
	local w, h = Config.STORM_CLOUD_WIDTH, Config.STORM_CLOUD_HEIGHT
	if self.flashPhase == "white" then
		gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	elseif self.flashPhase == "black" then
		gfx.setImageDrawMode(gfx.kDrawModeFillBlack)
	else
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
	end
	cloudImage:drawScaled(self.x - w * 0.5, self.y - h * 0.5, w / cloudImageWidth, h / cloudImageHeight)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
end
