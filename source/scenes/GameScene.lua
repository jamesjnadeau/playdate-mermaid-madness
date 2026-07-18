-- GameScene.lua
-- The sailing/combat scene. All rendering happens here in immediate mode
-- inside update(), which Noble runs after its sprite+background pass.

import "scripts/Config"
import "scripts/Utils"
import "scripts/Player"
import "scripts/Enemy"
import "scripts/Cannonball"

local gfx <const> = playdate.graphics

GameScene = {}
class("GameScene").extends(NobleScene)

-- File-local handle to the live scene so the (class-level) inputHandler
-- callbacks can talk to the current instance.
local scene = nil

local function lerp(a, b, t) return a + (b - a) * t end

-- Remove every particle system the library is tracking. Guarded so a version
-- mismatch in the library's global API can't hard-crash the scene (worst case:
-- a small leak of spent systems across restarts).
local function clearAllParticles()
	if Particles then
		if Particles.removeAll then
			Particles:removeAll()
		elseif Particles.clearAll then
			Particles:clearAll()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- Build all game state in init() (runs before the scene's first update()).
-- Noble may call update() during the tail of a scene transition, before
-- start() fires, so nothing here may be left until start().
function GameScene:init(sceneProperties)
	GameScene.super.init(self, sceneProperties)
	self.backgroundColor = gfx.kColorWhite
	scene = self
	self:resetGame(sceneProperties)
end

function GameScene:start()
	GameScene.super.start(self)
	scene = self
	Noble.Input.setCrankIndicatorStatus(true) -- prompt the player to use the crank
end

function GameScene:finish()
	GameScene.super.finish(self)
	clearAllParticles() -- drop every particle system this scene created
	if scene == self then scene = nil end
end

function GameScene:resetGame(sceneProperties)
	sceneProperties = sceneProperties or {}
	clearAllParticles()
	self.ship = Player(Config.WORLD_W / 2, Config.WORLD_H / 2)
	self.enemies = {}
	self.cannonballs = {}
	self.explosions = {}
	self.elapsed = 0
	self.spawnTimer = Config.SPAWN_INTERVAL_START
	self.level = sceneProperties.level or 1
	self.score = sceneProperties.totalDefeated or 0 -- cumulative across all levels this run
	self.levelKills = 0                             -- kills toward clearing the current level
	self.levelSpawned = 0                           -- enemies spawned so far this level
	self.levelTarget = self.level * Config.LEVEL_ENEMY_STEP
	self.gameOver = false
	self.levelComplete = false

	-- Input state
	self.speedInput = 0        -- -1 / 0 / +1 throttle from Up/Down
	self.chargingSide = nil
	self.charge = 0
	self.target = nil
end

-- ---------------------------------------------------------------------------
-- Input (class-level handler; callbacks defer to `scene`)
-- ---------------------------------------------------------------------------

GameScene.inputHandler = {
	-- Crank steers the helm.
	cranked = function(change, _)
		if scene and not scene.gameOver then scene.ship:steer(change) end
	end,
	-- Up/Down set a persistent throttle flag; the tick applies it each frame.
	upButtonDown = function()
		if scene then scene.speedInput = 1 end
	end,
	upButtonUp = function()
		if scene and scene.speedInput == 1 then scene.speedInput = 0 end
	end,
	downButtonDown = function()
		if scene then scene.speedInput = -1 end
	end,
	downButtonUp = function()
		if scene and scene.speedInput == -1 then scene.speedInput = 0 end
	end,
	-- Left/Right begin charging a broadside; release fires.
	leftButtonDown = function()
		if scene and not scene.gameOver then scene:beginCharge("port") end
	end,
	leftButtonUp = function()
		if scene then scene:releaseCharge("port") end
	end,
	rightButtonDown = function()
		if scene and not scene.gameOver then scene:beginCharge("starboard") end
	end,
	rightButtonUp = function()
		if scene then scene:releaseCharge("starboard") end
	end,
	AButtonDown = function()
		if scene and scene.gameOver then Noble.transition(GameScene) end
	end,
}

-- ---------------------------------------------------------------------------
-- Cannon: charging + auto-target
-- ---------------------------------------------------------------------------

function GameScene:beginCharge(side)
	self.chargingSide = side
	self.charge = 0
	self.target = self:pickTarget(side)
end

-- Choose the nearest enemy on the given side, within targeting range.
function GameScene:pickTarget(side)
	local ship = self.ship
	local fx, fy = Utils.heading(ship.heading)
	local best, bestD2 = nil, Config.TARGET_RANGE * Config.TARGET_RANGE
	for _, e in ipairs(self.enemies) do
		local dx, dy = e.x - ship.x, e.y - ship.y
		local cross = fx * dy - fy * dx      -- >0 starboard, <0 port
		local onSide = (side == "starboard" and cross > 0) or (side == "port" and cross < 0)
		if onSide then
			local d2 = dx * dx + dy * dy
			if d2 < bestD2 then
				bestD2 = d2
				best = e
			end
		end
	end
	return best
end

function GameScene:releaseCharge(side)
	if self.chargingSide ~= side then return end
	if not self.gameOver then
		local ship = self.ship
		local dir
		local target = self.target or self:pickTarget(side)
		if target then
			dir = Utils.angleTo(ship.x, ship.y, target.x, target.y)
		else
			-- Nothing to lock onto: fire a broadside straight out that side.
			dir = Utils.wrapDeg(ship.heading + (side == "starboard" and 90 or -90))
		end
		-- Charging steadies the aim: accuracy ramps up to 99% at full charge,
		-- so an undercharged shot can still stray wide of the target.
		dir = Utils.wrapDeg(dir + (math.random() * 2 - 1) * self:currentAimSpread())
		local speed = Config.CANNON_SPEED
		local hx, hy = Utils.heading(dir)
		local bx = ship.x + hx * (Config.SHIP_LENGTH + 4)
		local by = ship.y + hy * (Config.SHIP_LENGTH + 4)
		self.cannonballs[#self.cannonballs + 1] = Cannonball(bx, by, dir, speed)
	end

	self.chargingSide = nil
	self.charge = 0
	self.target = nil
end

-- Degrees of random aim error at the current charge: full spread at 0 charge,
-- narrowing to (1 - CANNON_MAX_ACCURACY) worth of spread once fully charged.
function GameScene:currentAimSpread()
	local accuracy = Config.CANNON_MAX_ACCURACY * self.charge
	return Config.CANNON_MAX_SPREAD * (1 - accuracy)
end

-- ---------------------------------------------------------------------------
-- Enemies / difficulty
-- ---------------------------------------------------------------------------

function GameScene:currentSpawnInterval()
	local t = Utils.clamp(self.elapsed / Config.SPAWN_RAMP_SECONDS, 0, 1)
	return lerp(Config.SPAWN_INTERVAL_START, Config.SPAWN_INTERVAL_FLOOR, t)
end

function GameScene:spawnEnemy()
	if #self.enemies >= Config.MAX_ENEMIES then return end
	if self.levelSpawned >= self.levelTarget then return end
	local ship = self.ship
	local ang = math.random() * 360
	local ax, ay = Utils.heading(ang)
	local dist = 250 + math.random() * 120 -- just beyond the screen's corner
	local ex = Utils.clamp(ship.x + ax * dist, 0, Config.WORLD_W)
	local ey = Utils.clamp(ship.y + ay * dist, 0, Config.WORLD_H)
	local facing = Utils.angleTo(ex, ey, ship.x, ship.y)
	self.enemies[#self.enemies + 1] = Enemy(ex, ey, facing)
	self.levelSpawned = self.levelSpawned + 1
end

function GameScene:addExplosion(ship)
	self.explosions[#self.explosions + 1] = ship:explode()
end

-- Call whenever an enemy is destroyed, however it died (rammed or cannoned),
-- so both the running total and the current level's progress stay in sync.
function GameScene:enemyDefeated()
	self.score = self.score + 1
	self.levelKills = self.levelKills + 1
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------

function GameScene:update()
	GameScene.super.update(self)

	if not self.gameOver and not self.levelComplete then
		self:tickGame()
	end

	self:render()
end

function GameScene:tickGame()
	local dt = Config.DT
	self.elapsed = self.elapsed + dt

	-- Apply throttle (held Up/Down) and cannon charge (held Left/Right).
	if self.speedInput ~= 0 then
		self.ship:changeSpeed(self.speedInput)
	end
	if self.chargingSide then
		self.target = self:pickTarget(self.chargingSide)
		if self.target then
			self.charge = math.min(1, self.charge + Config.CHARGE_RATE * dt)
		else
			-- Nothing in range on this side: charge can't steady an aim that
			-- has nothing to lock onto.
			self.charge = 0
		end
	end

	self.ship:update()

	-- Spawn on a shrinking interval.
	self.spawnTimer = self.spawnTimer - dt
	if self.spawnTimer <= 0 then
		self:spawnEnemy()
		self.spawnTimer = self:currentSpawnInterval()
	end

	-- Enemies chase; check ramming.
	local ship = self.ship
	for i = #self.enemies, 1, -1 do
		local e = self.enemies[i]
		e:update(ship.x, ship.y)
		if Utils.dist(e.x, e.y, ship.x, ship.y) < (Config.SHIP_COLLIDE_RADIUS + e.radius) then
			self:addExplosion(e)
			table.remove(self.enemies, i)
			self:enemyDefeated()
			if ship:hit(Config.ENEMY_DAMAGE) and ship.health <= 0 then
				self.gameOver = true
			end
		end
	end

	-- Cannonballs move and hit.
	for i = #self.cannonballs, 1, -1 do
		local b = self.cannonballs[i]
		b:update()
		local hit = false
		for j = #self.enemies, 1, -1 do
			local e = self.enemies[j]
			if Utils.dist(b.x, b.y, e.x, e.y) < (b.radius + e.radius) then
				self:addExplosion(e)
				table.remove(self.enemies, j)
				self:enemyDefeated()
				hit = true
				break
			end
		end
		if hit or b.dead then
			table.remove(self.cannonballs, i)
		end
	end

	-- Level clears once enough enemies have been defeated; hand off to the
	-- interstitial scene, which restarts GameScene at the next level with
	-- health reset (Player:init always sets full health).
	if self.levelKills >= self.levelTarget then
		self.levelComplete = true
		Noble.transition(LevelCompleteScene, nil, nil, nil, {
			completedLevel = self.level,
			totalDefeated = self.score,
		})
	end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

function GameScene:cameraOrigin()
	local camX = Utils.clamp(self.ship.x - Config.SCREEN_W / 2, 0, Config.WORLD_W - Config.SCREEN_W)
	local camY = Utils.clamp(self.ship.y - Config.SCREEN_H / 2, 0, Config.WORLD_H - Config.SCREEN_H)
	return math.floor(camX), math.floor(camY)
end

function GameScene:render()
	local camX, camY = self:cameraOrigin()

	-- ---- World space (camera offset applied) ----
	gfx.setDrawOffset(-camX, -camY)

	self:drawWater(camX, camY)

	-- Wake sits under the hulls.
	self.ship.wake:update()

	for _, e in ipairs(self.enemies) do e:draw() end
	for _, b in ipairs(self.cannonballs) do b:draw() end
	self.ship:draw()

	-- Explosions on top, then prune spent systems (age cap as a safety net).
	for i = #self.explosions, 1, -1 do
		local ex = self.explosions[i]
		ex.sys:update()
		ex.age = ex.age + 1
		if #ex.sys:getParticles() == 0 or ex.age > ex.maxAge then
			ex.sys:remove()
			table.remove(self.explosions, i)
		end
	end

	-- ---- Screen space (HUD) ----
	gfx.setDrawOffset(0, 0)
	self:drawTargetingLine(camX, camY)
	self:drawOffscreenArrows(camX, camY)
	self:drawHUD()
	if self.gameOver then self:drawGameOver() end
end

function GameScene:drawWater(camX, camY)
	local g = Config.WATER_GRID
	local startX = math.floor(camX / g) * g
	local startY = math.floor(camY / g) * g
	gfx.setColor(gfx.kColorBlack)
	for gx = startX, camX + Config.SCREEN_W + g, g do
		for gy = startY, camY + Config.SCREEN_H + g, g do
			-- Little staggered wavelets for a sea texture.
			gfx.fillRect(gx, gy, 2, 1)
			gfx.fillRect(gx + g / 2, gy + g / 2, 2, 1)
		end
	end

	-- Map boundary so the edge of the world is legible.
	gfx.setLineWidth(4)
	gfx.drawRect(0, 0, Config.WORLD_W, Config.WORLD_H)
end

function GameScene:drawTargetingLine(camX, camY)
	if not self.chargingSide then return end
	if not self.target then
		self:drawNoTargetMark(camX, camY, self.chargingSide)
		return
	end
	local sx = self.ship.x - camX
	local sy = self.ship.y - camY
	local tx = self.target.x - camX
	local ty = self.target.y - camY
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	Utils.drawDottedLine(sx, sy, tx, ty, 4, 4)
	-- Reticle around the locked target.
	gfx.drawCircleAtPoint(tx, ty, self.target.radius + 6)
	gfx.drawCircleAtPoint(tx, ty, self.target.radius + 2)

	self:drawAimLines(sx, sy, tx, ty)
end

-- Lazily-built image for the "nothing in range" indicator; text images are
-- cheap to cache since the string never changes.
local noTargetMarkImage = nil
local function getNoTargetMarkImage()
	if not noTargetMarkImage then
		noTargetMarkImage = gfx.imageWithText("?", 40, 40)
	end
	return noTargetMarkImage
end

-- Shown on whichever side the player is charging when no enemy is in range
-- on that side, at Config.NO_TARGET_MARK_OFFSET from the ship and scaled to
-- Config.NO_TARGET_MARK_SIZE.
function GameScene:drawNoTargetMark(camX, camY, side)
	local ship = self.ship
	local perp = Utils.wrapDeg(ship.heading + (side == "starboard" and 90 or -90))
	local hx, hy = Utils.heading(perp)
	local wx = ship.x + hx * Config.NO_TARGET_MARK_OFFSET
	local wy = ship.y + hy * Config.NO_TARGET_MARK_OFFSET
	local sx = wx - camX
	local sy = wy - camY

	local img = getNoTargetMarkImage()
	local iw, ih = img:getSize()
	local scale = Config.NO_TARGET_MARK_SIZE / ih
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	img:drawScaled(sx - (iw * scale) / 2, sy - (ih * scale) / 2, scale)
end

-- Two short lines near the ship show live aim spread: wide apart while
-- undercharged, converging onto the dotted target line as charge (and thus
-- accuracy) builds toward CANNON_MAX_ACCURACY.
function GameScene:drawAimLines(sx, sy, tx, ty)
	local dir = Utils.angleTo(sx, sy, tx, ty)
	local spread = self:currentAimSpread()
	gfx.setLineWidth(Config.AIM_LINE_WIDTH)
	for _, sign in ipairs({ -1, 1 }) do
		local hx, hy = Utils.heading(dir + sign * spread)
		gfx.drawLine(sx, sy, sx + hx * Config.AIM_LINE_LENGTH, sy + hy * Config.AIM_LINE_LENGTH)
	end
	gfx.setLineWidth(1)
end

function GameScene:drawOffscreenArrows(camX, camY)
	local margin = 14
	local cx, cy = Config.SCREEN_W / 2, Config.SCREEN_H / 2
	gfx.setColor(gfx.kColorBlack)
	for _, e in ipairs(self.enemies) do
		local sx = e.x - camX
		local sy = e.y - camY
		if sx < 0 or sx > Config.SCREEN_W or sy < 0 or sy > Config.SCREEN_H then
			local ang = Utils.angleTo(cx, cy, sx, sy)
			local px = Utils.clamp(sx, margin, Config.SCREEN_W - margin)
			local py = Utils.clamp(sy, margin, Config.SCREEN_H - margin)
			self:drawArrow(px, py, ang, 9)
		end
	end
end

function GameScene:drawArrow(px, py, angleDeg, size)
	local hx, hy = Utils.heading(angleDeg)
	-- perpendicular
	local rx, ry = -hy, hx
	local tipx, tipy = px + hx * size, py + hy * size
	local b1x, b1y = px - hx * size * 0.4 + rx * size * 0.6, py - hy * size * 0.4 + ry * size * 0.6
	local b2x, b2y = px - hx * size * 0.4 - rx * size * 0.6, py - hy * size * 0.4 - ry * size * 0.6
	gfx.fillTriangle(tipx, tipy, b1x, b1y, b2x, b2y)
end

function GameScene:drawHUD()
	gfx.setImageDrawMode(gfx.kDrawModeCopy)

	-- Health pips (top-left)
	for i = 1, Config.SHIP_MAX_HEALTH do
		local x = 6 + (i - 1) * 12
		gfx.setColor(gfx.kColorBlack)
		if i <= self.ship.health then
			gfx.fillRect(x, 6, 9, 9)
		else
			gfx.drawRect(x, 6, 9, 9)
		end
	end

	-- Score (top-right)
	-- gfx.drawText("* " .. self.score, Config.SCREEN_W - 60, 6)
	gfx.drawText("LV " .. self.level .. "  " .. self.levelKills .. "/" .. self.levelTarget, Config.SCREEN_W - 90, 6) -- 20

	-- Speed gauge (bottom-left)
	local gw, gh = 90, 8
	local gx, gy = 6, Config.SCREEN_H - 16
	gfx.drawText("SPEED", gx, gy - 16)
	gfx.drawRect(gx, gy, gw, gh)
	local fill = (self.ship.speed / Config.SHIP_MAX_SPEED) * (gw - 2)
	gfx.fillRect(gx + 1, gy + 1, fill, gh - 2)
end

function GameScene:drawGameOver()
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(60, 80, Config.SCREEN_W - 120, 80)
	gfx.setColor(gfx.kColorWhite)
	gfx.drawRect(62, 82, Config.SCREEN_W - 124, 76)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	gfx.drawTextAligned("SUNK!", Config.SCREEN_W / 2, 96, kTextAlignment.center)
	gfx.drawTextAligned("Plunder: " .. self.score, Config.SCREEN_W / 2, 116, kTextAlignment.center)
	gfx.drawTextAligned("Ⓐ to set sail again", Config.SCREEN_W / 2, 134, kTextAlignment.center)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
end