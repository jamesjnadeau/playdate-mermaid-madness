-- GameScene.lua
-- Base class for the sailing/combat scenes (GameSceneMain, GameSceneTraining).
-- Holds everything they share: ship/wind/trident physics, enemy and
-- tridentball collision handling, and all rendering. Subclasses hook in
-- their own enemy-spawning policy and extra HUD text; see updateSpawning()
-- and drawModeStatus() below. This class is never instantiated directly.

import "scripts/utilities/Config"
import "scripts/enemies/ConfigEnemy"
import "scripts/utilities/Utils"
import "scripts/player/Player"
import "scripts/enemies/Enemy"
import "scripts/enemies/EnemySwordfish"
import "scripts/enemies/EnemyKraken"
import "scripts/enemies/EnemyRogueWave"
import "scripts/player/Tridentball"
import "scripts/player/StormCloud"
import "scripts/utilities/Sound"

local gfx <const> = playdate.graphics

-- Never instantiated directly (see header); self.level below is only ever
-- set by the GameSceneMain subclass, hence optional here.
---@class GameScene : NobleScene
---@field ship Player
---@field enemies Enemy[]
---@field tridentballs Tridentball[]
---@field stormClouds StormCloud[]
---@field stormBolts table[] active damage-bolt effects, each { points: number[], timer: number, frame: integer }, see updateStormClouds/updateStormBolts/drawStormBolts
---@field autoLightningBolts table[] active auto-lightning strike-bolt effects, each { points: number[], timer: number, frame: integer }, see fireLightning/updateAutoLightningBolts/drawAutoLightningBolts
---@field explosions table[] each { sys: table, age: number, maxAge: number }, see Ship:explode
---@field elapsed number
---@field score number
---@field gameOver boolean
---@field confirmingQuit? boolean set by GameSceneTraining while its B-button quit-confirmation dialog is up; nil/false elsewhere
---@field level? number set by GameSceneMain; nil elsewhere, treated as 1
---@field windSpeedChangeRateMin number
---@field windSpeedChangeRateMax number
---@field windChangeIntervalMin number
---@field windChangeIntervalMax number
---@field windDirection number
---@field windDirectionTarget number
---@field windDirectionChangeRate number
---@field windSpeed number
---@field windSpeedTarget number
---@field windSpeedChangeRate number
---@field windChangeIntervalDuration number
---@field windChangeTimer number
---@field windEaseTimer number
---@field windEaseDuration number
---@field windSettled boolean
---@field trimInput number -1 / 0 / 1
---@field chargingSide? string "port" | "starboard"
---@field charge number 0-1
---@field target? Enemy
---@field lightningTimer number seconds until auto-lightning can strike again, see updateAutoLightning
---@field enemyTypes table[] class-level: Enemy/EnemySwordfish/EnemyKraken/EnemyRogueWave class tables eligible for random spawning
GameScene = class("GameScene").extends(NobleScene) or GameScene

-- File-local handle to the live scene so the (class-level) inputHandler
-- callbacks -- in this class and in subclasses -- can talk to the current
-- instance. GameScene.current() is the accessor subclasses should use.
local scene = nil

---@return GameScene?
function GameScene.current()
	return scene
end

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
---@param sceneProperties? table
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

-- Generic state every variant needs. Subclasses that track anything extra
-- (level progress, spawn timers, ...) should override this, call
-- GameScene.super.resetGame(self, sceneProperties) first, then add their own.
---@param sceneProperties? table
function GameScene:resetGame(sceneProperties)
	sceneProperties = sceneProperties or {}
	clearAllParticles()
	self.ship = Player(0, 0)
	self.enemies = {}
	self.tridentballs = {}
	self.stormClouds = {} -- lazily backfilled up to Config.STORM_CLOUD_COUNT, see updateStormClouds
	self.stormBolts = {} -- active damage-bolt effects, see updateStormClouds/updateStormBolts/drawStormBolts
	self.autoLightningBolts = {} -- active auto-lightning strike-bolt effects, see fireLightning/updateAutoLightningBolts/drawAutoLightningBolts
	self.explosions = {}
	self.elapsed = 0
	self.score = 0
	self.gameOver = false

	local wind = self:windTuning()
	self.windSpeedChangeRateMin = wind.speedChangeRateMin
	self.windSpeedChangeRateMax = wind.speedChangeRateMax
	self.windChangeIntervalMin = wind.changeIntervalMin
	self.windChangeIntervalMax = wind.changeIntervalMax

	self.windDirection = math.random() * 360
	self.windDirectionTarget = self.windDirection
	self.windDirectionChangeRate = Config.WIND_DIRECTION_CHANGE_RATE_MIN
	self.windSpeed = self:fixedWindSpeed()
		or (Config.WIND_SPEED_MIN + math.random() * (Config.WIND_SPEED_MAX - Config.WIND_SPEED_MIN))
	self.windSpeedTarget = self.windSpeed
	self.windSpeedChangeRate = self.windSpeedChangeRateMin
	self.windChangeIntervalDuration = self.windChangeIntervalMin
		+ math.random() * (self.windChangeIntervalMax - self.windChangeIntervalMin)
	self.windChangeTimer = self.windChangeIntervalDuration

	-- Counts up (0 -> windEaseDuration) while the wind is easing toward its
	-- current targets, i.e. exactly while windChangeTimer is paused. Lets the
	-- HUD show progress toward the countdown resuming. Both start at 0 since
	-- the wind begins already settled.
	self.windEaseTimer = 0
	self.windEaseDuration = 0
	self.windSettled = true

	-- Input state
	self.trimInput = 0         -- -1 / 0 / +1 sail trim adjustment from Up/Down
	self.chargingSide = nil
	self.charge = 0
	self.target = nil
	self.lightningTimer = 0 -- auto-lightning; see updateAutoLightning -- 0 lets it strike as soon as a level starts, if unlocked and something's in range
end

-- Wind speed's easing rate and how often it changes, in {speedChangeRateMin,
-- speedChangeRateMax, changeIntervalMin, changeIntervalMax}. Plain Config
-- defaults here; GameSceneMain overrides this to scale both with level, the
-- same way it scales levelTarget off Config.LEVEL_ENEMY_STEP.
---@return { speedChangeRateMin: number, speedChangeRateMax: number, changeIntervalMin: number, changeIntervalMax: number }
function GameScene:windTuning()
	return {
		speedChangeRateMin = Config.WIND_SPEED_CHANGE_RATE_MIN,
		speedChangeRateMax = Config.WIND_SPEED_CHANGE_RATE_MAX,
		changeIntervalMin = Config.WIND_CHANGE_INTERVAL_MIN,
		changeIntervalMax = Config.WIND_CHANGE_INTERVAL_MAX,
	}
end

-- Hook for a scene that wants wind speed pinned to one fixed value instead
-- of the normal wander-over-time system (see resetGame above and the speed
-- half of tickGame's wind-change block below): nil (the default) means "use
-- the normal random wind speed"; a number locks windSpeed/windSpeedTarget to
-- exactly that value forever (wind direction still wanders normally either
-- way -- this only pins speed). InstructionsScene overrides this to
-- Config.SHIP_MAX_SPEED so its tutorial steps play out at a predictable,
-- ship-matching wind. Kept as a scene-level hook (not hardcoded to
-- InstructionsScene) since GameSceneTraining is expected to eventually
-- expose this as a player-adjustable setting.
---@return number?
function GameScene:fixedWindSpeed()
	return nil
end

-- ---------------------------------------------------------------------------
-- Input (class-level handlers; callbacks defer to the current instance)
-- ---------------------------------------------------------------------------

-- The steering/trim/trident bindings every variant shares. Each subclass
-- builds its own inputHandler from this (input tables don't merge through
-- inheritance the way methods do) and adds its own A/B bindings on top.
-- `getScene` should return the currently-active instance -- pass
-- GameScene.current.
---@param getScene fun(): GameScene?
---@return table inputHandler
function GameScene.buildSharedInputHandler(getScene)
	return {
		-- Crank steers the helm.
		cranked = function(change, _)
			local s = getScene()
			if s and not s.gameOver and not s.confirmingQuit then s.ship:steer(change) end
		end,
		-- Up/Down set a persistent sail-trim flag; the tick applies it each
		-- frame. Up lets the sail out, Down trims it in.
		upButtonDown = function()
			local s = getScene()
			if s then s.trimInput = 1 end
		end,
		upButtonUp = function()
			local s = getScene()
			if s and s.trimInput == 1 then s.trimInput = 0 end
		end,
		downButtonDown = function()
			local s = getScene()
			if s then s.trimInput = -1 end
		end,
		downButtonUp = function()
			local s = getScene()
			if s and s.trimInput == -1 then s.trimInput = 0 end
		end,
		-- Left/Right begin charging a broadside; release fires.
		leftButtonDown = function()
			local s = getScene()
			if s and not s.gameOver and not s.confirmingQuit then s:beginCharge("port") end
		end,
		leftButtonUp = function()
			local s = getScene()
			if s then s:releaseCharge("port") end
		end,
		rightButtonDown = function()
			local s = getScene()
			if s and not s.gameOver and not s.confirmingQuit then s:beginCharge("starboard") end
		end,
		rightButtonUp = function()
			local s = getScene()
			if s then s:releaseCharge("starboard") end
		end,
	}
end

-- ---------------------------------------------------------------------------
-- Trident: charging + auto-target
-- ---------------------------------------------------------------------------

---@param side string "port" | "starboard"
function GameScene:beginCharge(side)
	-- Out of ammo: don't even start a charge that couldn't fire anyway (see
	-- releaseCharge's Player:consumeAmmo call, the actual enforcement point).
	if self.ship.ammo < Config.TRIDENT_COUNT * Config.AMMO_COST_PER_SHOT then return end
	self.chargingSide = side
	self.charge = 0
	self.target = self:pickTarget(side)
end

-- Choose the nearest enemy on the given side, within `range` (defaults to
-- Config.TARGET_RANGE). side = nil skips the side check entirely -- used by
-- auto-lightning, which (unlike the manual port/starboard trident) targets
-- the nearest enemy anywhere around the ship.
---@param side? string "port" | "starboard" | nil for "either side"
---@param range? number defaults to Config.TARGET_RANGE
---@return Enemy?
function GameScene:pickTarget(side, range)
	local ship = self.ship
	local fx, fy = Utils.heading(ship.heading)
	range = range or Config.TARGET_RANGE
	local best, bestD2 = nil, range * range
	for _, e in ipairs(self.enemies) do
		local dx, dy = e.x - ship.x, e.y - ship.y
		local cross = fx * dy - fy * dx      -- >0 starboard, <0 port
		local onSide = side == nil
			or (side == "starboard" and cross > 0) or (side == "port" and cross < 0)
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

---@param side string "port" | "starboard"
function GameScene:releaseCharge(side)
	if self.chargingSide ~= side then return end
	if not self.gameOver then
		local ship = self.ship
		local count = Config.TRIDENT_COUNT
		if ship:consumeAmmo(count * Config.AMMO_COST_PER_SHOT) then
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
			local speed = Config.TRIDENT_SPEED
			for i = 1, count do
				-- Fan extra tridents symmetrically around `dir` (e.g. count=2 fires
				-- at -0.5*spread/+0.5*spread, count=3 at -spread/0/+spread).
				local shotDir = Utils.wrapDeg(dir + (i - (count + 1) / 2) * Config.TRIDENT_COUNT_SPREAD)
				local hx, hy = Utils.heading(shotDir)
				local bx = ship.x + hx * (Config.SHIP_LENGTH + 4)
				local by = ship.y + hy * (Config.SHIP_LENGTH + 4)
				self.tridentballs[#self.tridentballs + 1] = Tridentball(bx, by, shotDir, speed)
			end
			Sound.playTridentWhoosh()
		end
	end

	self.chargingSide = nil
	self.charge = 0
	self.target = nil
end

-- Degrees of random aim error at the current charge: full spread at 0 charge,
-- narrowing to (1 - TRIDENT_MAX_ACCURACY) worth of spread once fully charged.
---@return number
function GameScene:currentAimSpread()
	local accuracy = Config.TRIDENT_MAX_ACCURACY * self.charge
	return Config.TRIDENT_MAX_SPREAD * (1 - accuracy)
end

-- ---------------------------------------------------------------------------
-- Auto-lightning (see Config.AUTO_LIGHTNING_* and the "Autolightning"
-- upgrade in ConfigUpgrades.lua)
-- ---------------------------------------------------------------------------

-- Called once per tick from tickGame. No-ops until the upgrade is picked
-- (Config.AUTO_LIGHTNING_UNLOCKED); once unlocked, strikes unassisted at the
-- nearest enemy within Config.AUTO_LIGHTNING_RANGE every
-- Config.AUTO_LIGHTNING_DELAY seconds -- no charge, no player input, no
-- side restriction (unlike the manual port/starboard trident). Each pick of
-- the "Autolightning" upgrade beyond the first adds another strike
-- (Config.AUTO_LIGHTNING_UNLOCKED counts them), so a volley strikes that many
-- times at once, all at the same target. Bolt effects age/flash regardless
-- of whether the upgrade is currently unlocked (there's nothing to age once
-- it isn't -- fireLightning is the only thing that ever adds one).
---@param dt number
function GameScene:updateAutoLightning(dt)
	if Config.AUTO_LIGHTNING_UNLOCKED > 0 then
		if self.lightningTimer > 0 then
			self.lightningTimer = self.lightningTimer - dt
		else
			local target = self:pickTarget(nil, Config.AUTO_LIGHTNING_RANGE)
			if target then
				for _ = 1, Config.AUTO_LIGHTNING_UNLOCKED do
					self:fireLightning(target)
				end
				self.lightningTimer = Config.AUTO_LIGHTNING_DELAY
			end
		end
	end
	self:updateAutoLightningBolts(dt)
end

-- Strikes `target` for Config.AUTO_LIGHTNING_DAMAGE immediately -- unlike
-- Tridentball/fireCannon (its predecessor), there's no travelling projectile
-- and thus no later collision pass to land the hit or clean up a defeated
-- enemy, so this does that bookkeeping itself, the same as
-- GameScene:updateStormClouds does for a Storm Cloud's damage tick. The bolt
-- is drawn from a point just ahead of the ship's bow toward the target (the
-- same muzzle point fireCannon used) to the target itself.
---@param target Enemy
function GameScene:fireLightning(target)
	local ship = self.ship
	local dir = Utils.angleTo(ship.x, ship.y, target.x, target.y)
	local hx, hy = Utils.heading(dir)
	local bx = ship.x + hx * (Config.SHIP_LENGTH + 4)
	local by = ship.y + hy * (Config.SHIP_LENGTH + 4)
	self:addAutoLightningBolt(bx, by, target.x, target.y)

	target:hit(Config.AUTO_LIGHTNING_DAMAGE)
	Sound.playEnemyHit()
	if not target.alive then
		for i = #self.enemies, 1, -1 do
			if self.enemies[i] == target then
				self:addExplosion(target)
				table.remove(self.enemies, i)
				self:enemyDefeated()
				break
			end
		end
	end
end

-- Spawns one auto-lightning strike-bolt visual effect from (x1, y1) (the
-- ship's muzzle point) to (x2, y2) (the struck enemy) -- called once per
-- strike from fireLightning. Mirrors addStormBolt, just drawing its shape
-- from the AUTO_LIGHTNING_BOLT_* config block instead of STORM_CLOUD_BOLT_*
-- so the two effects can be tuned independently.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
function GameScene:addAutoLightningBolt(x1, y1, x2, y2)
	self.autoLightningBolts[#self.autoLightningBolts + 1] = {
		points = Utils.lightningBoltPoints(x1, y1, x2, y2, Config.AUTO_LIGHTNING_BOLT_SEGMENTS, Config.AUTO_LIGHTNING_BOLT_JITTER),
		timer = Config.AUTO_LIGHTNING_BOLT_DURATION,
		frame = 0,
	}
end

-- Ages every active strike bolt by dt, dropping ones whose
-- Config.AUTO_LIGHTNING_BOLT_DURATION has elapsed, and advances the frame
-- counter drawAutoLightningBolts uses to flash the still-active ones.
-- Mirrors updateStormBolts.
---@param dt number
function GameScene:updateAutoLightningBolts(dt)
	for i = #self.autoLightningBolts, 1, -1 do
		local bolt = self.autoLightningBolts[i]
		bolt.timer = bolt.timer - dt
		if bolt.timer <= 0 then
			table.remove(self.autoLightningBolts, i)
		else
			bolt.frame = bolt.frame + 1
		end
	end
end

-- Draws every active strike bolt, flashing on/off every
-- Config.AUTO_LIGHTNING_BOLT_FLASH_FRAMES frames rather than staying solid
-- for its whole duration -- called from render() alongside the storm bolts.
-- Mirrors drawStormBolts.
function GameScene:drawAutoLightningBolts()
	if #self.autoLightningBolts == 0 then return end
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(Config.AUTO_LIGHTNING_BOLT_WIDTH)
	for _, bolt in ipairs(self.autoLightningBolts) do
		local flashStep = math.floor(bolt.frame / Config.AUTO_LIGHTNING_BOLT_FLASH_FRAMES)
		if flashStep % 2 == 0 then
			Utils.drawPolyline(bolt.points)
		end
	end
	gfx.setLineWidth(1)
end

-- ---------------------------------------------------------------------------
-- Storm clouds (see Config.STORM_CLOUD_* and the "Storm Cloud" upgrade in
-- ConfigUpgrades.lua)
-- ---------------------------------------------------------------------------

-- Called once per tick from tickGame, after enemies have moved and the
-- tridentball collision pass has run. Lazily backfills self.stormClouds up
-- to Config.STORM_CLOUD_COUNT (which only ever grows, via the upgrade, and
-- only between levels) so a fresh level starts with every previously-picked
-- cloud already summoned. Each cloud drifts on its own (StormCloud:update);
-- damage application stays here, the same split as the tridentball collision
-- loop above, since only GameScene can defeat an enemy (addExplosion/
-- enemyDefeated/table.remove).
---@param dt number
function GameScene:updateStormClouds(dt)
	while #self.stormClouds < Config.STORM_CLOUD_COUNT do
		local sx, sy = StormCloud.randomSpawnPoint(self.ship.x, self.ship.y)
		self.stormClouds[#self.stormClouds + 1] = StormCloud(sx, sy)
	end

	for _, cloud in ipairs(self.stormClouds) do
		cloud:update(self.enemies, self.ship.x, self.ship.y, dt)
		if cloud.damageTimer <= 0 then
			cloud.damageTimer = Config.STORM_CLOUD_DAMAGE_INTERVAL
			for i = #self.enemies, 1, -1 do
				local e = self.enemies[i]
				if Utils.dist(cloud.x, cloud.y, e.x, e.y) < (Config.STORM_CLOUD_RADIUS + e.radius) then
					self:addStormBolt(cloud.x, cloud.y, e.x, e.y)
					e:hit(Config.STORM_CLOUD_DAMAGE)
					Sound.playEnemyHit()
					if not e.alive then
						self:addExplosion(e)
						table.remove(self.enemies, i)
						self:enemyDefeated()
					end
				end
			end
		end
	end

	self:updateStormBolts(dt)
end

-- Spawns one damage-bolt visual effect from (x1, y1) (a cloud's center) to
-- (x2, y2) (the enemy it just damaged) -- called once per enemy hit from the
-- loop above, so a cloud that damages several enemies on the same tick draws
-- one bolt to each. The zigzag shape is rolled once here and stored rather
-- than recomputed every draw, so the bolt doesn't visibly writhe while it's
-- shown -- only its on/off flash (see drawStormBolts) changes frame to frame.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
function GameScene:addStormBolt(x1, y1, x2, y2)
	self.stormBolts[#self.stormBolts + 1] = {
		points = Utils.lightningBoltPoints(x1, y1, x2, y2, Config.STORM_CLOUD_BOLT_SEGMENTS, Config.STORM_CLOUD_BOLT_JITTER),
		timer = Config.STORM_CLOUD_BOLT_DURATION,
		frame = 0,
	}
end

-- Ages every active damage bolt by dt, dropping ones whose
-- Config.STORM_CLOUD_BOLT_DURATION has elapsed, and advances the frame
-- counter drawStormBolts uses to flash the still-active ones.
---@param dt number
function GameScene:updateStormBolts(dt)
	for i = #self.stormBolts, 1, -1 do
		local bolt = self.stormBolts[i]
		bolt.timer = bolt.timer - dt
		if bolt.timer <= 0 then
			table.remove(self.stormBolts, i)
		else
			bolt.frame = bolt.frame + 1
		end
	end
end

-- Draws every active damage bolt, flashing on/off every
-- Config.STORM_CLOUD_BOLT_FLASH_FRAMES frames rather than staying solid for
-- its whole duration -- called from render() alongside the storm clouds
-- themselves, so bolts share their top-of-everything z-order.
function GameScene:drawStormBolts()
	if #self.stormBolts == 0 then return end
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(Config.STORM_CLOUD_BOLT_WIDTH)
	for _, bolt in ipairs(self.stormBolts) do
		local flashStep = math.floor(bolt.frame / Config.STORM_CLOUD_BOLT_FLASH_FRAMES)
		if flashStep % 2 == 0 then
			Utils.drawPolyline(bolt.points)
		end
	end
	gfx.setLineWidth(1)
end

-- ---------------------------------------------------------------------------
-- Enemies
-- ---------------------------------------------------------------------------

-- Enemy classes eligible for random spawning, gated by level via each
-- class's minLevel (Enemy.minLevel / EnemySwordfish.minLevel / EnemyKraken.minLevel /
-- EnemyRogueWave.minLevel, driven by Config.ENEMY_MIN_LEVEL /
-- Config.ENEMY_SWORDFISH_MIN_LEVEL / Config.ENEMY_KRAKEN_MIN_LEVEL /
-- Config.ENEMY_ROGUEWAVE_MIN_LEVEL). Add new enemy types here to fold them
-- into spawnEnemy's random pick below.
GameScene.enemyTypes = { Enemy, EnemySwordfish, EnemyKraken, EnemyRogueWave }

-- Spawns one enemy at a random position around the ship. With no argument,
-- picks uniformly among GameScene.enemyTypes entries unlocked at self.level
-- (self.level is nil for scenes without level progression, e.g.
-- GameSceneTraining -- treated as level 1). Pass forcedType (one of
-- GameScene.enemyTypes) to spawn that type regardless of level gating --
-- see GameSceneTraining, which uses this for its enemy picker. Returns whether
-- it actually spawned one (false if already at MAX_ENEMIES). Subclasses that
-- gate spawning further (e.g. a per-level cap) should override this, check
-- their own condition, then delegate to GameScene.super.spawnEnemy(self).
---@param forcedType? table one of GameScene.enemyTypes
---@return boolean spawned
function GameScene:spawnEnemy(forcedType)
	if #self.enemies >= Config.MAX_ENEMIES then return false end
	local ship = self.ship
	local ang = math.random() * 360
	local ax, ay = Utils.heading(ang)
	local dist = 250 + math.random() * 120 -- just beyond the screen's corner
	local ex = ship.x + ax * dist
	local ey = ship.y + ay * dist
	local facing = Utils.angleTo(ex, ey, ship.x, ship.y)

	local EnemyType = forcedType
	if not EnemyType then
		local level = self.level or 1
		local eligible = {}
		for _, t in ipairs(GameScene.enemyTypes) do
			if level >= t.minLevel then
				eligible[#eligible + 1] = t
			end
		end
		EnemyType = eligible[math.random(#eligible)]
	end
	self.enemies[#self.enemies + 1] = EnemyType(ex, ey, facing)
	return true
end

-- Hook for automatic spawning; called once per tick. The base scene never
-- spawns on its own (GameSceneTraining relies on this); GameSceneMain overrides
-- it to spawn on a timer.
---@param dt number
function GameScene:updateSpawning(dt) end

---@param ship Ship
function GameScene:addExplosion(ship)
	self.explosions[#self.explosions + 1] = ship:explode(self.windDirection)
end

-- Call whenever an enemy is destroyed, however it died (rammed or tridented).
-- Subclasses that track further progress (level kills, ...) should override
-- this and call GameScene.super.enemyDefeated(self) first.
function GameScene:enemyDefeated()
	self.score = self.score + 1
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------

function GameScene:update()
	GameScene.super.update(self)

	if not self.gameOver and not self.confirmingQuit then
		self:tickGame()
	end

	self:render()
end

function GameScene:tickGame()
	local dt = Config.DT
	self.elapsed = self.elapsed + dt

	-- Wind wanders rather than sitting still all run: every so often it picks
	-- a new target speed and direction, then eases both toward those targets
	-- at a random rate until the next change. The countdown to the next
	-- change is paused while the current one is still easing in, so changes
	-- can't stack up faster than the ship can visibly react to them.
	local windSettled = self.windSpeed == self.windSpeedTarget
		and self.windDirection == self.windDirectionTarget
	self.windSettled = windSettled
	if windSettled then
		self.windChangeTimer = self.windChangeTimer - dt
	else
		self.windEaseTimer = math.min(self.windEaseDuration, self.windEaseTimer + dt)
	end
	if windSettled and self.windChangeTimer <= 0 then
		local fixedSpeed = self:fixedWindSpeed()
		self.windSpeedTarget = fixedSpeed
			or (Config.WIND_SPEED_MIN + math.random() * (Config.WIND_SPEED_MAX - Config.WIND_SPEED_MIN))
		self.windSpeedChangeRate = self.windSpeedChangeRateMin
			+ math.random() * (self.windSpeedChangeRateMax - self.windSpeedChangeRateMin)

		local shift = Config.WIND_DIRECTION_CHANGE_MIN
			+ math.random() * (Config.WIND_DIRECTION_CHANGE_MAX - Config.WIND_DIRECTION_CHANGE_MIN)
		if math.random() < 0.5 then shift = -shift end
		self.windDirectionTarget = Utils.wrapDeg(self.windDirection + shift)
		self.windDirectionChangeRate = Config.WIND_DIRECTION_CHANGE_RATE_MIN
			+ math.random() * (Config.WIND_DIRECTION_CHANGE_RATE_MAX - Config.WIND_DIRECTION_CHANGE_RATE_MIN)

		self.windChangeIntervalDuration = self.windChangeIntervalMin
			+ math.random() * (self.windChangeIntervalMax - self.windChangeIntervalMin)
		self.windChangeTimer = self.windChangeIntervalDuration

		-- The countdown (windChangeTimer) freezes until speed and direction
		-- both catch up to their new targets; estimate how long that'll take
		-- from each one's distance-to-target and easing rate so the HUD can
		-- show that wait filling up (see windEaseTimer above).
		local speedEaseTime = math.abs(self.windSpeedTarget - self.windSpeed) / self.windSpeedChangeRate
		local dirEaseTime = math.abs(Utils.angleDiff(self.windDirection, self.windDirectionTarget)) / self.windDirectionChangeRate
		self.windEaseDuration = math.max(speedEaseTime, dirEaseTime)
		self.windEaseTimer = 0
	end

	if self.windSpeed < self.windSpeedTarget then
		self.windSpeed = math.min(self.windSpeedTarget, self.windSpeed + self.windSpeedChangeRate * dt)
	elseif self.windSpeed > self.windSpeedTarget then
		self.windSpeed = math.max(self.windSpeedTarget, self.windSpeed - self.windSpeedChangeRate * dt)
	end

	local dirDiff = Utils.angleDiff(self.windDirection, self.windDirectionTarget)
	local maxDirStep = self.windDirectionChangeRate * dt
	if dirDiff >= -maxDirStep and dirDiff <= maxDirStep then
		-- Snap to the exact target (like the speed clamp above) so windSettled's
		-- == check can actually become true instead of chasing float rounding forever.
		self.windDirection = self.windDirectionTarget
	else
		local dirStep = Utils.clamp(dirDiff, -maxDirStep, maxDirStep)
		self.windDirection = Utils.wrapDeg(self.windDirection + dirStep)
	end

	-- Apply sail trim (held Up/Down) and trident charge (held Left/Right).
	if self.trimInput ~= 0 then
		self.ship:adjustSailTrim(self.trimInput * Config.SAIL_TRIM_RATE * dt)
	end
	if self.chargingSide then
		self.target = self:pickTarget(self.chargingSide)
		if self.target then
			self.charge = math.min(1, self.charge + Config.TRIDENT_CHARGE_RATE * dt)
		else
			-- Nothing in range on this side: charge can't steady an aim that
			-- has nothing to lock onto.
			self.charge = 0
		end
	end

	self.ship:update(self.windDirection, self.windSpeed)
	self:updateAutoLightning(dt)

	self:updateSpawning(dt)

	-- Enemies chase; check ramming. Ramming only damages the player -- an
	-- enemy is never defeated by hull contact, only by a tridentball/Storm
	-- Cloud hit (see the tridentball loop below and updateStormClouds above).
	local ship = self.ship
	for _, e in ipairs(self.enemies) do
		e:update(ship.x, ship.y, self.windDirection, self.windSpeed)
		if Utils.dist(e.x, e.y, ship.x, ship.y) < (Config.SHIP_COLLIDE_RADIUS + e.radius) then
			if ship:hit(e.damage) then
				Sound.playPlayerHurt()
				if ship.health <= 0 then
					self:onPlayerHealthDepleted()
				end
			end
		end
	end

	-- Tridentballs move and hit.
	for i = #self.tridentballs, 1, -1 do
		local b = self.tridentballs[i]
		b:update()
		local hit = false
		for j = #self.enemies, 1, -1 do
			local e = self.enemies[j]
			if Utils.dist(b.x, b.y, e.x, e.y) < (b.radius + e.radius) then
				e:hit(b.damage)
				Sound.playEnemyHit()
				hit = true
				if not e.alive then
					self:addExplosion(e)
					table.remove(self.enemies, j)
					self:enemyDefeated()
				end
				break
			end
		end
		if hit or b.dead then
			table.remove(self.tridentballs, i)
		end
	end

	self:updateStormClouds(dt)
end

-- Called when the player's health drops to 0 or below. Default behavior ends
-- the run; GameSceneTraining overrides this to reset health and keep the
-- sandbox running instead of kicking the tester back to the title screen.
function GameScene:onPlayerHealthDepleted()
	self.gameOver = true
	Sound.playPlayerDeath()
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- The world is infinite and player-centered: the camera always keeps the
-- ship dead-center on screen rather than clamping to any world bound.
---@return integer camX
---@return integer camY
function GameScene:cameraOrigin()
	local camX = self.ship.x - Config.SCREEN_W / 2
	local camY = self.ship.y - Config.SCREEN_H / 2
	return math.floor(camX), math.floor(camY)
end

function GameScene:render()
	local camX, camY = self:cameraOrigin()

	-- ---- World space (camera offset applied) ----
	gfx.setDrawOffset(-camX, -camY)

	self:drawWater(camX, camY)

	-- Wake sits under the hulls.
	self.ship:drawWake()

	for _, e in ipairs(self.enemies) do e:draw() end
	for _, b in ipairs(self.tridentballs) do b:draw() end
	self.ship:draw()

	-- Explosions above the hulls, then prune spent systems (age cap as a
	-- safety net).
	for i = #self.explosions, 1, -1 do
		local ex = self.explosions[i]
		ex.sys:update()
		ex.age = ex.age + 1
		if #ex.sys:getParticles() == 0 or ex.age > ex.maxAge then
			ex.sys:remove()
			table.remove(self.explosions, i)
		end
	end

	-- Storm clouds (and their damage bolts) drawn last of the world-space
	-- layer, on top of every other sprite/effect above -- see StormCloud.lua's
	-- header. Auto-lightning bolts join them here for the same reason: always
	-- visible over whatever they're striking.
	for _, cloud in ipairs(self.stormClouds) do cloud:draw() end
	self:drawStormBolts()
	self:drawAutoLightningBolts()

	-- ---- Screen space (HUD) ----
	gfx.setDrawOffset(0, 0)
	self:drawTargetingLine(camX, camY)
	self:drawOffscreenArrows(camX, camY)
	self:drawHUD()
	self:drawModeStatus()
	self:drawWindIndicator()
	if self.gameOver then self:drawGameOver() end
	if self.confirmingQuit then self:drawConfirmQuit() end
end

-- Integer hash (mix-then-fold) used to pick each wavelet's segment count.
-- Grid indices (not raw world coordinates) go in: world coordinates are
-- multiples of WATER_GRID / WATER_GRID/2, and a plain weighted sum of those
-- collapses to the same residue for every wavelet once the range divides
-- the grid spacing -- this scrambles the bits first so it doesn't.
---@param a integer
---@param b integer
---@param c integer
---@return integer
local function waterHash(a, b, c)
	local h = a * 374761393 + b * 668265263 + c * 1136930381
	h = (h ~ (h >> 13)) * 1274126177
	h = h ~ (h >> 16)
	return h
end

---@param camX integer
---@param camY integer
function GameScene:drawWater(camX, camY)
	local g = Config.WATER_GRID
	local startX = math.floor(camX / g) * g
	local startY = math.floor(camY / g) * g
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(Config.WATER_WAVELET_WIDTH)

	-- Wavelets are short wave-shaped lines spanning perpendicular to the wind
	-- (real sea waves crest across the wind, not along it), with their
	-- undulation bulging along the wind axis.
	local hx, hy = Utils.heading(self.windDirection)
	local px, py = -hy, hx
	for gx = startX, camX + Config.SCREEN_W + g, g do
		local ix = math.floor(gx / g)
		for gy = startY, camY + Config.SCREEN_H + g, g do
			local iy = math.floor(gy / g)
			self:drawWavelet(gx, gy, px, py, hx, hy, ix, iy, 0)
			self:drawWavelet(gx + g / 2, gy + g / 2, px, py, hx, hy, ix, iy, 1)
		end
	end
end

-- Draws one wave-shaped wavelet centered at (cx, cy): a polyline spanning a
-- length (px) along the (px, py) axis, undulating by
-- Config.WATER_WAVELET_AMPLITUDE along the (wx, wy) axis. Length and zigzag
-- count are picked from their own [MIN, MAX] range via waterHash(ix, iy,
-- variant), so they vary per wavelet but stay stable frame to frame instead
-- of flickering. Segment count is derived from zigzags (segments-per-zigzag,
-- also hashed) rather than picked independently, so every up/down cycle
-- always gets enough points to read as a curve instead of a jagged zigzag.
-- Config.WATER_WAVELET_SPAWN_CHANCE rolls (with the same stable hash)
-- whether this slot draws anything at all.
---@param cx number
---@param cy number
---@param px number perpendicular-to-wind axis unit vector, x
---@param py number perpendicular-to-wind axis unit vector, y
---@param wx number wind-heading unit vector, x
---@param wy number wind-heading unit vector, y
---@param ix integer
---@param iy integer
---@param variant integer
function GameScene:drawWavelet(cx, cy, px, py, wx, wy, ix, iy, variant)
	local spawnRoll = (waterHash(ix, iy, variant + 3000) % 10000) / 10000
	if spawnRoll >= Config.WATER_WAVELET_SPAWN_CHANCE then return end

	local lenMin, lenMax = Config.WATER_WAVELET_LENGTH_MIN, Config.WATER_WAVELET_LENGTH_MAX
	local lenT = (waterHash(ix, iy, variant + 1000) % 1009) / 1009
	local length = lenMin + lenT * (lenMax - lenMin)

	local zigMin, zigMax = Config.WATER_WAVELET_ZIGZAGS_MIN, Config.WATER_WAVELET_ZIGZAGS_MAX
	local zigzags = zigMin + (waterHash(ix, iy, variant + 2000) % (zigMax - zigMin + 1))

	local spzMin, spzMax = Config.WATER_WAVELET_SEGMENTS_PER_ZIGZAG_MIN, Config.WATER_WAVELET_SEGMENTS_PER_ZIGZAG_MAX
	local segmentsPerZigzag = spzMin + (waterHash(ix, iy, variant + 4000) % (spzMax - spzMin + 1))
	local segments = zigzags * segmentsPerZigzag

	local halfLen = length / 2
	local amplitude = Config.WATER_WAVELET_AMPLITUDE
	local prevX, prevY = cx - px * halfLen, cy - py * halfLen
	for i = 1, segments do
		local t = -halfLen + length * i / segments
		local wave = amplitude * math.sin(2 * math.pi * zigzags * i / segments)
		local x = cx + px * t + wx * wave
		local y = cy + py * t + wy * wave
		gfx.drawLine(prevX, prevY, x, y)
		prevX, prevY = x, y
	end
end

---@param camX integer
---@param camY integer
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
---@type _Image?
local noTargetMarkImage = nil
---@return _Image
local function getNoTargetMarkImage()
	if not noTargetMarkImage then
		noTargetMarkImage = gfx.imageWithText("?", 40, 40)
	end
	return noTargetMarkImage
end

-- Lazily-built heart glyph images, cached for the same reason as above and
-- so drawHUD can scale them (drawText can't be scaled, images can).
---@type _Image?
local fullHeartImage = nil
---@type _Image?
local emptyHeartImage = nil
---@return _Image
local function getFullHeartImage()
	if not fullHeartImage then
		fullHeartImage = gfx.imageWithText("❤️", 20, 20)
	end
	return fullHeartImage
end
---@return _Image
local function getEmptyHeartImage()
	if not emptyHeartImage then
		emptyHeartImage = gfx.imageWithText("🤍", 20, 20)
	end
	return emptyHeartImage
end

-- Shown on whichever side the player is charging when no enemy is in range
-- on that side, at Config.NO_TARGET_MARK_OFFSET from the ship and scaled to
-- Config.NO_TARGET_MARK_SIZE.
---@param camX integer
---@param camY integer
---@param side string "port" | "starboard"
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
-- accuracy) builds toward TRIDENT_MAX_ACCURACY.
---@param sx number
---@param sy number
---@param tx number
---@param ty number
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

-- Off-screen enemies are bucketed by on-screen direction so a cluster of
-- enemies coming from the same side draws as one (larger) arrow with a count
-- badge instead of a stack of overlapping ones. Each group also surfaces the
-- most urgent teleport countdown among its members (see Enemy:updateLeash),
-- so the player gets advance warning before an enemy relocates.
---@param camX integer
---@param camY integer
function GameScene:drawOffscreenArrows(camX, camY)
	local margin = Config.OFFSCREEN_INDICATOR_MARGIN
	local groupWindow = Config.OFFSCREEN_INDICATOR_GROUP_ANGLE
	local size = Config.OFFSCREEN_INDICATOR_SIZE
	local cx, cy = Config.SCREEN_W / 2, Config.SCREEN_H / 2
	local reach = Config.SCREEN_W + Config.SCREEN_H -- far enough to always clamp onto an edge

	local groups = {}
	for _, e in ipairs(self.enemies) do
		local sx = e.x - camX
		local sy = e.y - camY
		if sx < 0 or sx > Config.SCREEN_W or sy < 0 or sy > Config.SCREEN_H then
			local ang = Utils.angleTo(cx, cy, sx, sy)
			local hx, hy = Utils.heading(ang)

			local group = nil
			for _, g in ipairs(groups) do
				if math.abs(Utils.angleDiff(g.angle, ang)) <= groupWindow / 2 then
					group = g
					break
				end
			end
			if not group then
				group = { sumX = 0, sumY = 0, count = 0, angle = ang, warning = nil, minDist = nil }
				groups[#groups + 1] = group
			end

			group.sumX = group.sumX + hx
			group.sumY = group.sumY + hy
			group.count = group.count + 1
			group.angle = Utils.angleTo(0, 0, group.sumX, group.sumY)
			if e.teleportWarning and (not group.warning or e.teleportWarning < group.warning) then
				group.warning = e.teleportWarning
			end
			local dist = Utils.dist(self.ship.x, self.ship.y, e.x, e.y)
			if not group.minDist or dist < group.minDist then
				group.minDist = dist
			end
		end
	end

	-- A flashing group blinks fully on/off at Config.OFFSCREEN_INDICATOR_FLASH_PERIOD
	-- (see shouldFlashOffscreenIndicator) rather than drawing dimmer -- there's
	-- no dimming on Playdate's 1-bit display, so on/off is the whole toolbox.
	local flashVisible = math.floor(self.elapsed / (Config.OFFSCREEN_INDICATOR_FLASH_PERIOD / 2)) % 2 == 0

	gfx.setColor(gfx.kColorBlack)
	for _, g in ipairs(groups) do
		if flashVisible or not self:shouldFlashOffscreenIndicator(g) then
			local hx, hy = Utils.heading(g.angle)

			local px = Utils.clamp(cx + hx * reach, margin, Config.SCREEN_W - margin)
			local py = Utils.clamp(cy + hy * reach, margin, Config.SCREEN_H - margin)
			local ex = Utils.clamp(cx + hx * reach, 0, Config.SCREEN_W)
			local ey = Utils.clamp(cy + hy * reach, 0, Config.SCREEN_H)

			-- A group's count replaces the arrow outright (the number alone is
			-- clearer than trying to cram it inside a tiny triangle).
			local labelHeight = size
			local radius = size -- how far the indicator extends from px,py toward the edge
			local countImg, countW, countH, countScale
			if g.count > 1 then
				countImg = gfx.imageWithText(tostring(g.count), 100, 100)
				local iw, ih = countImg:getSize()
				countScale = Config.OFFSCREEN_INDICATOR_COUNT_SIZE / ih
				countW, countH = iw * countScale, ih * countScale
				labelHeight = countH
				radius = math.max(countW, countH) / 2
			end

			-- Line starts at the indicator's outer edge (not its center) and
			-- reaches the true screen edge when the nearest enemy in the group
			-- is at Config.ENEMY_MAX_DISTANCE.
			local fraction = Utils.clamp(g.minDist / Config.ENEMY_MAX_DISTANCE, 0, 1)
			local startX, startY = px + hx * radius, py + hy * radius
			local endX, endY = px + (ex - px) * fraction, py + (ey - py) * fraction
			gfx.drawLine(startX, startY, endX, endY)

			if countImg then
				gfx.setImageDrawMode(gfx.kDrawModeCopy)
				countImg:drawScaled(px - countW / 2, py - countH / 2, countScale)
			else
				self:drawArrow(px, py, g.angle, size)
			end
			if g.warning then
				gfx.drawTextAligned(tostring(math.ceil(g.warning)), px, py + labelHeight / 2 + 2, kTextAlignment.center)
			end
		end
	end
end

-- Whether this off-screen indicator group should blink to draw the player's
-- attention -- default: it's the last enemy left (nothing else to distract
-- from, and worth making easy to find so a mop-up doesn't turn into a long
-- search). Subclasses can override for their own attention-getting
-- conditions -- see InstructionsScene, which replaces this with its own
-- "target's been out of range too long" hint instead.
---@param __group table unused in the base implementation; a group entry from drawOffscreenArrows
---@return boolean
function GameScene:shouldFlashOffscreenIndicator(__group)
	return #self.enemies == 1
end

---@param px number
---@param py number
---@param angleDeg number
---@param size number
function GameScene:drawArrow(px, py, angleDeg, size)
	local hx, hy = Utils.heading(angleDeg)
	-- perpendicular
	local rx, ry = -hy, hx
	local tipx, tipy = px + hx * size, py + hy * size
	local b1x, b1y = px - hx * size * 0.4 + rx * size * 0.6, py - hy * size * 0.4 + ry * size * 0.6
	local b2x, b2y = px - hx * size * 0.4 - rx * size * 0.6, py - hy * size * 0.4 - ry * size * 0.6
	gfx.drawLine(tipx, tipy, b1x, b1y)
	gfx.drawLine(b1x, b1y, b2x, b2y)
	gfx.drawLine(b2x, b2y, tipx, tipy)
end

function GameScene:drawHUD()
	gfx.setImageDrawMode(gfx.kDrawModeCopy)

	-- Health pips (top-left): whole hearts drawn full-size, the next
	-- (partially-lost) heart scaled down to how much of it remains, and
	-- the rest drawn as small empty hearts.
	local fullHeart = getFullHeartImage()
	local emptyHeart = getEmptyHeartImage()
	local fw, fh = fullHeart:getSize()
	local wholeHearts = math.floor(math.max(0, self.ship.health))
	local remainder = self.ship.health - wholeHearts
	for i = 1, Config.SHIP_MAX_HEALTH do
		local x = Config.HUD_HEART_MARGIN_X + (i - 1) * Config.HUD_HEART_SPACING
		if i <= wholeHearts then
			fullHeart:draw(x, Config.HUD_HEART_MARGIN_Y)
		elseif i == wholeHearts + 1 and remainder > 0 then
			local scale = remainder
			fullHeart:drawScaled(x + fw * (1 - scale) / 2, Config.HUD_HEART_MARGIN_Y + fh * (1 - scale) / 2, scale)
		else
			local scale = Config.HUD_EMPTY_HEART_SCALE
			emptyHeart:drawScaled(x + fw * (1 - scale) / 2, Config.HUD_HEART_MARGIN_Y + fh * (1 - scale) / 2, scale)
		end
	end

	-- Speed gauge (bottom-left)
	if Config.HUD_SHOW_PLAYER_SPEED then
		local gw, gh = 90, 8
		local gx, gy = 6, Config.SCREEN_H - 16
		gfx.drawText(string.format("%d px/s", math.floor(self.ship.speed + 0.5)), gx + 10, gy - 16)
	end
end

-- Hook for whatever status text belongs in the top-right (level progress,
-- test-mode hints, ...). The base scene shows nothing.
function GameScene:drawModeStatus() end

-- Bottom-right compass showing which way the wind currently blows.
function GameScene:drawWindIndicator()
	local cx, cy = Config.SCREEN_W - 26, Config.SCREEN_H - 30
	gfx.setColor(gfx.kColorBlack)
	if Config.HUD_SHOW_WIND_SPEED then
		gfx.drawTextAligned(string.format("%d px/s", math.floor(self.windSpeed + 0.5)),
			cx - Config.WIND_INDICATOR_CIRCLE_SIZE - 4, cy - 8, kTextAlignment.right)
	end
	if Config.HUD_SHOW_WIND_DIRECTION then
		gfx.drawCircleAtPoint(cx, cy, Config.WIND_INDICATOR_CIRCLE_SIZE)
		self:drawSolidArrow(cx, cy, self.windDirection, Config.WIND_INDICATOR_SIZE)
	end
end

-- Solid (filled) version of drawArrow, used for the wind indicator so it
-- reads as a pointer rather than a wireframe triangle.
---@param px number
---@param py number
---@param angleDeg number
---@param size number
function GameScene:drawSolidArrow(px, py, angleDeg, size)
	local hx, hy = Utils.heading(angleDeg)
	-- perpendicular
	local rx, ry = -hy, hx
	local tipx, tipy = px + hx * size, py + hy * size
	local b1x, b1y = px - hx * size * 0.4 + rx * size * 0.6, py - hy * size * 0.4 + ry * size * 0.6
	local b2x, b2y = px - hx * size * 0.4 - rx * size * 0.6, py - hy * size * 0.4 - ry * size * 0.6
	gfx.fillPolygon(tipx, tipy, b1x, b1y, b2x, b2y)
end

function GameScene:drawGameOver()
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(60, 80, Config.SCREEN_W - 120, 80)
	gfx.setColor(gfx.kColorWhite)
	gfx.drawRect(62, 82, Config.SCREEN_W - 124, 76)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	gfx.drawTextAligned("SUNK!", Config.SCREEN_W / 2, 96, kTextAlignment.center)
	gfx.drawTextAligned("Plunder: " .. self.score, Config.SCREEN_W / 2, 116, kTextAlignment.center)
	gfx.drawTextAligned(self:gameOverPrompt(), Config.SCREEN_W / 2, 134, kTextAlignment.center)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- What to tell the player to do once sunk; each mode's A/B bindings mean
-- something different, so this can't be one fixed string.
---@return string
function GameScene:gameOverPrompt()
	return "Ⓐ to set sail again"
end

-- Hook for a scene that wants a confirmation dialog drawn while
-- self.confirmingQuit is true (see the field's doc comment above and
-- buildSharedInputHandler's gating on it); the base scene never sets that
-- field, so this never fires here. GameSceneTraining overrides it to draw
-- its "return to title?" prompt.
function GameScene:drawConfirmQuit() end
