-- ConfigEnemy.lua
-- Enemy tuning, split out of Config.lua since it's the part that grows as
-- new enemy types are added. Still just adds fields onto the shared global
-- Config table -- import "scripts/utilities/Config" first (this file assumes
-- Config.SHIP_MAX_SPEED already exists).
local gfx <const> = playdate.graphics

-------------
-- Enemies --
-------------
Config.ENEMY_SPEED      = math.floor(Config.SHIP_MAX_SPEED * 0.75 )    -- pixels / second (should be slower than you at full sail)
-- Turn rate falls off linearly from TURN_RATE_MAX (at rest) to TURN_RATE_MIN
-- (at or above the "max speed" used for the falloff) as an enemy's current
-- speed rises -- see Enemy:update. That reference "max speed" is
-- ENEMY_SPEED * ENEMY_TURN_RATE_SPEED_MULTIPLIER, not ENEMY_SPEED directly,
-- so the falloff curve can be tuned independent of ENEMY_SPEED itself (e.g.
-- < 1 makes them lose turn rate well before reaching their target speed,
-- > 1 delays the falloff past it -- speed can exceed ENEMY_SPEED thanks to
-- wind push, up to SHIP_MAX_SPEED before overspeed friction bites).
Config.ENEMY_TURN_RATE_MAX  = 80   -- degrees / second they can rotate toward you at low speed
Config.ENEMY_TURN_RATE_MIN  = 20   -- degrees / second they can rotate toward you at/above max speed
Config.ENEMY_TURN_RATE_SPEED_MULTIPLIER = 1.0   -- multiplier on ENEMY_SPEED giving the speed at which turn rate bottoms out
Config.ENEMY_SPAWN_DIST = 300   -- how far off-screen they appear, from ship
Config.ENEMY_DAMAGE     = 1
Config.ENEMY_LENGTH    = 20      -- half-length of hull when drawn, default 22
Config.ENEMY_BEAM      = 8       -- half-width of hull when drawn
Config.ENEMY_RADIUS     = Config.ENEMY_LENGTH
Config.ENEMY_WIND_MULTIPLIER = 0.1 -- enemies have no sails: wind just adds a straight push of windSpeed * this, in the wind's direction, on top of their steering speed
Config.ENEMY_ACCEL      = 60    -- pixels/second, added per second while easing toward ENEMY_SPEED (see Ship:updateSpeed)
-- Lowest self.level an enemy type is allowed to spawn at (see Enemy.minLevel
-- and GameScene:spawnEnemy, which filters GameScene.enemyTypes by this each
-- time it picks a type to spawn). 1 means "eligible from the very first
-- level", i.e. always appears.
Config.ENEMY_MIN_LEVEL = 1

-- With an infinite world an enemy that loses the player would otherwise
-- chase forever; past ENEMY_MAX_DISTANCE it's flagged for relocation, warned
-- for ENEMY_TELEPORT_WARN_TIME seconds (see the off-screen indicator), then
-- teleported to the opposite side of the player at the same distance so it
-- stays an active threat instead of trailing off into the distance.
Config.ENEMY_MAX_DISTANCE      = 900
Config.ENEMY_TELEPORT_WARN_TIME = 3     -- seconds of countdown warning before relocation

-- Health bar shown under an enemy once it's taken damage (see Enemy:draw /
-- Enemy:drawHealthBar) -- hidden entirely at full health.
Config.ENEMY_HEALTH_BAR_WIDTH  = 20  -- px wide
Config.ENEMY_HEALTH_BAR_HEIGHT = 3   -- px tall
Config.ENEMY_HEALTH_BAR_MARGIN = 4   -- px gap between the hull's collision radius and the bar's top edge
-- Extra px added past self.radius (the collision radius) before the margin,
-- for enemies whose drawn shape reaches farther than their collision radius
-- (e.g. a bill or direction dots that don't count toward collision) -- see
-- Enemy.healthBarOffset / Enemy:drawHealthBar. 0 for the base enemy, whose
-- hull barely exceeds its collision radius.
Config.ENEMY_HEALTH_BAR_OFFSET = 0

-- Difficulty ramp: spawn interval shrinks from START to FLOOR over RAMP seconds
Config.SPAWN_INTERVAL_START = 2.6
Config.SPAWN_INTERVAL_FLOOR = 0.55
Config.SPAWN_RAMP_SECONDS   = 90
Config.MAX_ENEMIES          = 40

------------------------
-- Enemy: Swordfish --
------------------------
-- A smaller, faster Enemy variant (see EnemySwordfish.lua) with a long spiked
-- bill instead of a hull bow. Mirrors the base ENEMY_* tuning knobs above so
-- it can be tuned independently.
Config.ENEMY_SWORDFISH_SPEED      = math.floor(Config.ENEMY_SPEED * 1.2)   -- pixels / second, faster than the base enemy
Config.ENEMY_SWORDFISH_ACCEL      = math.floor(Config.ENEMY_ACCEL * 1.2)   -- pixels / second^2
Config.ENEMY_SWORDFISH_TURN_RATE_MAX = 110  -- degrees / second at low speed
Config.ENEMY_SWORDFISH_TURN_RATE_MIN = 30   -- degrees / second at/above max speed
Config.ENEMY_SWORDFISH_TURN_RATE_SPEED_MULTIPLIER = 1.0
Config.ENEMY_SWORDFISH_LENGTH     = math.floor(Config.ENEMY_LENGTH * 0.85) -- half-length of hull body (excludes bill), smaller than the base enemy
Config.ENEMY_SWORDFISH_BEAM       = math.floor(Config.ENEMY_BEAM * 0.85)   -- half-width of hull when drawn, slimmer than the base enemy
Config.ENEMY_SWORDFISH_BILL_LENGTH = math.floor(Config.ENEMY_SWORDFISH_LENGTH * 0.9) -- extra spike length added ahead of the body, giving the swordfish look
Config.ENEMY_SWORDFISH_RADIUS     = Config.ENEMY_SWORDFISH_LENGTH +  (Config.ENEMY_SWORDFISH_BILL_LENGTH/2)       -- collision radius 
Config.ENEMY_SWORDFISH_HEALTH     = 1
Config.ENEMY_SWORDFISH_DAMAGE     = Config.ENEMY_DAMAGE / 2
Config.ENEMY_SWORDFISH_WIND_MULTIPLIER = Config.ENEMY_WIND_MULTIPLIER
Config.ENEMY_SWORDFISH_COLOR      = gfx.kColorBlack
Config.ENEMY_SWORDFISH_OUTLINE_COLOR = gfx.kColorWhite -- distinguishes it from the base enemy's silhouette at a glance
Config.ENEMY_SWORDFISH_EYE_OFFSET = 4   -- px the eye dot sits ahead of center, scaled down to match its smaller hull
Config.ENEMY_SWORDFISH_MIN_LEVEL  = 5   -- unlocked starting this level (appears after level 2) -- see Config.ENEMY_MIN_LEVEL
-- The bill tip (bow point of the hull) sits BILL_LENGTH past the body, but
-- ENEMY_SWORDFISH_RADIUS (the collision radius) only counts half of that --
-- see Enemy.healthBarOffset -- so nudge the health bar out by the other half
-- to clear the bill tip when it's pointed toward the bar.
Config.ENEMY_SWORDFISH_HEALTH_BAR_OFFSET = Config.ENEMY_SWORDFISH_BILL_LENGTH / 2

------------------------
-- Enemy: Kraken --
------------------------
-- A slow, tougher Enemy variant (see EnemyKraken.lua) drawn as a round body
-- with 3 small circles trailing off ahead of it in a row, doubling as a
-- direction indicator in place of the base Enemy's hull + eye dot.
Config.ENEMY_KRAKEN_SPEED      = math.floor(Config.ENEMY_SPEED * 0.5)   -- pixels / second, much slower than the base enemy
Config.ENEMY_KRAKEN_ACCEL      = math.floor(Config.ENEMY_ACCEL * 0.5)   -- pixels / second^2
Config.ENEMY_KRAKEN_TURN_RATE_MAX = Config.ENEMY_TURN_RATE_MAX
Config.ENEMY_KRAKEN_TURN_RATE_MIN = Config.ENEMY_TURN_RATE_MIN
Config.ENEMY_KRAKEN_TURN_RATE_SPEED_MULTIPLIER = Config.ENEMY_TURN_RATE_SPEED_MULTIPLIER
Config.ENEMY_KRAKEN_BODY_RADIUS = 14  -- px radius of the main body circle
Config.ENEMY_KRAKEN_RADIUS     = Config.ENEMY_KRAKEN_BODY_RADIUS  -- collision radius; the direction dots are purely visual
Config.ENEMY_KRAKEN_DOT_RADIUS  = 4  -- px radius of each of the 3 direction-indicator circles
Config.ENEMY_KRAKEN_DOT_SPACING = 9  -- px between consecutive dot centers
Config.ENEMY_KRAKEN_DOT_OFFSET  = Config.ENEMY_KRAKEN_BODY_RADIUS + 6  -- px from body center to the nearest dot's center, along heading
Config.ENEMY_KRAKEN_HEALTH     = 3
Config.ENEMY_KRAKEN_DAMAGE     = Config.ENEMY_DAMAGE
Config.ENEMY_KRAKEN_WIND_MULTIPLIER = Config.ENEMY_WIND_MULTIPLIER
Config.ENEMY_KRAKEN_COLOR      = gfx.kColorBlack
Config.ENEMY_KRAKEN_OUTLINE_COLOR = gfx.kColorWhite
Config.ENEMY_KRAKEN_MIN_LEVEL  = 3   -- unlocked starting this level, tougher than the swordfish -- see Config.ENEMY_MIN_LEVEL
-- The direction-indicator dots are purely visual (ENEMY_KRAKEN_RADIUS, the
-- collision radius, ignores them) but reach farther from center than the
-- body itself -- see Enemy.healthBarOffset -- so nudge the health bar out by
-- the difference to clear them regardless of which way the chevron is facing.
Config.ENEMY_KRAKEN_HEALTH_BAR_OFFSET = (Config.ENEMY_KRAKEN_DOT_OFFSET + Config.ENEMY_KRAKEN_DOT_SPACING
	+ Config.ENEMY_KRAKEN_DOT_RADIUS) - Config.ENEMY_KRAKEN_BODY_RADIUS

---------------------------
-- Enemy: Rogue Wave --
---------------------------
-- A bull-charge Enemy variant (see EnemyRogueWave.lua): charges in a
-- straight line at CHARGE_SPEED for CHARGE_LENGTH seconds, brakes to a full
-- stop, turns in place to face the target for up to TURN_TIME seconds, then
-- charges again -- it never turns while moving. CHARGE_SPEED/CHARGE_LENGTH/
-- TURN_TIME are the three tunable knobs (speed, charge length, timing).
Config.ENEMY_ROGUEWAVE_CHARGE_SPEED = math.floor(Config.ENEMY_SPEED * 2.0)  -- pixels / second while charging, much faster than a steady-homing enemy
Config.ENEMY_ROGUEWAVE_ACCEL       = math.floor(Config.ENEMY_ACCEL * 2.5)  -- pixels / second^2 easing up to CHARGE_SPEED
Config.ENEMY_ROGUEWAVE_STOP_ACCEL  = Config.ENEMY_ROGUEWAVE_ACCEL * 2      -- brakes harder than it winds up, so the stop reads as a deliberate dig-in
Config.ENEMY_ROGUEWAVE_STOP_SPEED_THRESHOLD = 5  -- px/second below which "stopping" counts as fully stopped and turning can begin
Config.ENEMY_ROGUEWAVE_CHARGE_LENGTH = 1.0  -- seconds spent charging before braking to a stop
Config.ENEMY_ROGUEWAVE_TURN_TIME    = 0.6   -- seconds spent stopped-and-turning before charging again
Config.ENEMY_ROGUEWAVE_TURN_RATE    = 220   -- degrees / second while stopped -- fast, since this is the only time it can turn at all
Config.ENEMY_ROGUEWAVE_LENGTH = 34  -- half-length of the outer ellipse, elongated compared to the base enemy's hull
Config.ENEMY_ROGUEWAVE_BEAM   = 10  -- half-width of the outer ellipse
-- The crescent look (see EnemyRogueWave:drawBodyLocal) comes from cutting a
-- second, smaller ellipse out of the outer one, shifted toward the stern by
-- HOLLOW_OFFSET. HOLLOW_SCALE and HOLLOW_OFFSET are chosen so the cut
-- ellipse stays fully inside the outer one (HOLLOW_OFFSET + LENGTH *
-- HOLLOW_SCALE <= LENGTH) -- otherwise its stroked outline would poke out
-- past the filled body as a disconnected arc.
Config.ENEMY_ROGUEWAVE_HOLLOW_SCALE  = 0.75
Config.ENEMY_ROGUEWAVE_HOLLOW_OFFSET = 6
Config.ENEMY_ROGUEWAVE_RADIUS = 22  -- collision radius -- smaller than LENGTH since the crescent's horns taper to almost nothing
Config.ENEMY_ROGUEWAVE_HEALTH = 2
Config.ENEMY_ROGUEWAVE_DAMAGE = Config.ENEMY_DAMAGE * 1.5  -- a charging wave hits harder than a steady-homing enemy
Config.ENEMY_ROGUEWAVE_WIND_MULTIPLIER = Config.ENEMY_WIND_MULTIPLIER
Config.ENEMY_ROGUEWAVE_COLOR         = gfx.kColorBlack
Config.ENEMY_ROGUEWAVE_OUTLINE_COLOR = gfx.kColorWhite
Config.ENEMY_ROGUEWAVE_MIN_LEVEL = 4  -- unlocked starting this level -- see Config.ENEMY_MIN_LEVEL
-- The crescent's bow-side tip reaches all the way to LENGTH, well past the
-- RADIUS collision circle -- see Enemy.healthBarOffset -- so nudge the
-- health bar out by the difference to clear it regardless of heading.
Config.ENEMY_ROGUEWAVE_HEALTH_BAR_OFFSET = Config.ENEMY_ROGUEWAVE_LENGTH - Config.ENEMY_ROGUEWAVE_RADIUS

return Config
