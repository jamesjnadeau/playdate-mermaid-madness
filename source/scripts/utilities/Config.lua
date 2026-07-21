-- Config.lua
-- Central place for all tuning values so the game is easy to tweak.
-- Everything lives in a global table so any file can read it after import.
local gfx <const> = playdate.graphics

Config = {}

-------------
-- Display --
-------------
Config.SCREEN_W   = 400
Config.SCREEN_H   = 240
Config.REFRESH    = 30          -- we lock to 30fps and use a fixed timestep
Config.DT         = 1 / 30

-----------
-- World --
-----------
-- The sea is infinite and all coordinates are player-centered: the camera
-- always centers on the ship and nothing clamps its position.
Config.WATER_GRID = 80             -- spacing of the drawn water speckle grid
Config.WATER_WAVELET_LENGTH_MIN = 15 -- shortest span (px) of each wavelet, perpendicular to the wind
Config.WATER_WAVELET_LENGTH_MAX = 55 -- longest span (px) of each wavelet, perpendicular to the wind
Config.WATER_WAVELET_WIDTH = 1     -- line width (px) of each wavelet segment
Config.WATER_WAVELET_SEGMENTS_PER_ZIGZAG_MIN = 6 -- fewest line segments per up/down cycle (higher = smoother curves)
Config.WATER_WAVELET_SEGMENTS_PER_ZIGZAG_MAX = 8 -- most line segments per up/down cycle
Config.WATER_WAVELET_AMPLITUDE = 6 -- how far the wave bulges along the wind direction (px)
Config.WATER_WAVELET_ZIGZAGS_MIN = 1 -- fewest up/down cycles along each wavelet
Config.WATER_WAVELET_ZIGZAGS_MAX = 3 -- most up/down cycles along each wavelet
Config.WATER_WAVELET_SPAWN_CHANCE = 0.35 -- chance (0-1) any given wavelet slot draws one at all

----------
-- Wind --
----------
-- Direction is the angle the wind blows TOWARD (same convention as heading).
-- Every WIND_CHANGE_INTERVAL_MIN..MAX seconds a new random change fires: it
-- picks a new target speed in WIND_SPEED_MIN..MAX, eases toward it at a rate
-- in WIND_SPEED_CHANGE_RATE_MIN..MAX (px/s per second), and picks a new
-- target direction by a random +/- magnitude in WIND_DIRECTION_CHANGE_MIN..MAX
-- degrees, easing toward it at a rate in WIND_DIRECTION_CHANGE_RATE_MIN..MAX
-- (degrees per second).
Config.WIND_SPEED_MIN             = 20  -- px/s a fully-out sail catches running dead downwind
Config.WIND_SPEED_MAX             = 80
Config.WIND_SPEED_CHANGE_RATE_MIN = 1   -- px/s per second the wind eases toward its new target speed
Config.WIND_SPEED_CHANGE_RATE_MAX = 3
Config.WIND_CHANGE_INTERVAL_MIN   = 10   -- seconds between random wind changes
Config.WIND_CHANGE_INTERVAL_MAX   = 15
Config.WIND_DIRECTION_CHANGE_MIN  = 5   -- degrees the wind direction target shifts by on each change
Config.WIND_DIRECTION_CHANGE_MAX  = 45
Config.WIND_DIRECTION_CHANGE_RATE_MIN = 2  -- degrees/second the wind eases toward its new target direction
Config.WIND_DIRECTION_CHANGE_RATE_MAX = 4
Config.WIND_INDICATOR_CIRCLE_SIZE = 20
Config.WIND_INDICATOR_SIZE = 20
-- How much wind bends the player's wake spray away from directly astern,
-- toward the direction the wind is blowing (0 = wake trails straight behind
-- the ship, 1 = wake is fully re-centered on the wind direction). See
-- Player:update.
Config.WAKE_WIND_INFLUENCE = 0.2

----------------
-- Explosions --
----------------
-- Each field maps to one pdParticles ParticleCircle setter (see Ship:explode).
-- Ship.explosionConfig is the default every ship inherits; a subclass can
-- overwrite the whole table or just a field to get its own look.
Config.EXPLOSION = {
	mode     = Particles.modes.DECAY,
	decay    = 0.5,
	size     = { 2, 5 },
	speed    = { 2, 9 },      -- pdParticles speed is per-frame
	spread   = { 0, 100 },
	lifespan = { 2, 3 },
	color    = gfx.kColorBlack,
	count    = 10,
	maxAge   = 120,           -- frames; safety net if particles never fully decay
}
-- How much wind bends the explosion's spread arc toward the direction the
-- wind is blowing (0 = ignore wind and use spread as authored above, 1 =
-- spread arc is fully re-centered on the wind direction). See Ship:explode.
Config.EXPLOSION_WIND_INFLUENCE = 0.4

----------
-- Ship --
----------
-- set max ship speed to half way between min/max wind speed
Config.SHIP_MAX_SPEED = math.floor((Config.WIND_SPEED_MAX - Config.WIND_SPEED_MIN)/2) + Config.WIND_SPEED_MIN     -- pixels / second
Config.SHIP_DEFAULT_SPEED = math.floor(Config.SHIP_MAX_SPEED * 0.1 )    -- guaranteed baseline forward speed regardless of sail/wind
Config.SHIP_ACCEL        = math.floor(Config.SHIP_MAX_SPEED * 0.3 )       -- pixels / second, added per second while easing toward target speed
Config.SHIP_TURN_SCALE = 1   -- crank-degrees -> heading-degrees multiplier
Config.SHIP_MAX_HEALTH = 3
Config.SHIP_LENGTH    = 20      -- half-length of hull when drawn, default 22
Config.SHIP_COLLIDE_RADIUS = Config.SHIP_LENGTH      -- collision radius
Config.SHIP_BEAM      = math.floor(Config.SHIP_LENGTH * 0.4)       -- half-width of hull when drawn
Config.SHIP_WIND_POWER_MULTIPLIER = 1.2
-- Continuous drag opposing every ship's speed: each second a ship loses this
-- fraction of its current speed to water resistance, on top of easing toward
-- its target speed. Kept small relative to SHIP_ACCEL/ENEMY_ACCEL so it
-- doesn't choke off top speed -- see Ship:updateSpeed.
Config.SHIP_WATER_FRICTION = 0.05
-- Extra drag applied only to the portion of speed above SHIP_MAX_SPEED (e.g.
-- from a wind boost pushing a ship past its cap): each second a ship loses
-- this fraction of every pixel/second it's over the max, on top of the
-- regular water friction above -- see Ship:updateSpeed.
Config.SHIP_OVERSPEED_FRICTION = 0.025
-- wake
Config.SHIP_WAKE_SIZE_MIN = 1
Config.SHIP_WAKE_SIZE_MAX = 2
Config.SHIP_WAKE_DECAY = 0.15
Config.SHIP_WAKE_SPEED_MIN = 2
Config.SHIP_WAKE_SPEED_MAX = 4

----------
-- Sail --
----------
-- Up/Down let the sail out / trim it in (0 = trimmed in, 1 = fully out).
Config.SAIL_TRIM_START = 0.5  -- trim the player starts each run with
Config.SAIL_TRIM_RATE  = 1.2  -- trim units / second while Up/Down is held
Config.SAIL_MAX_ANGLE  = 90   -- max degrees the boom can swing from the centerline (rigging limit)
Config.SAIL_LENGTH     = Config.SHIP_LENGTH + (.25 * Config.SHIP_LENGTH)   -- px length of the drawn sail
-- The boom doesn't snap straight to its resting angle (see Player:sailTargetAngle)
-- -- it's animated like a lightly damped spring, so a slack sail visibly flops
-- over to lie parallel with the wind. SWING_SPEED is the spring's stiffness
-- (how hard the boom accelerates to close the gap to its target angle, in
-- deg/s^2 per degree of error); higher = snappier flop. SWING_FRICTION is the
-- fraction of angular velocity shed per second (damping); higher settles
-- faster with less overshoot, lower wobbles/oscillates longer. See
-- Player:updateSailAngle.
Config.SAIL_SWING_SPEED    = 110
Config.SAIL_SWING_FRICTION = 5


-------------
-- Trident --
-------------
Config.TRIDENT_CHARGE_RATE      = 0.5   -- charge units / second (held), clamps at 1.0
Config.TRIDENT_DAMAGE    = 1     -- health removed from an enemy per trident hit, see GameScene's tridentball collision loop
Config.TRIDENT_SPEED     = 420   -- projectile speed, fixed regardless of charge
Config.TRIDENT_MAX_SPREAD = 40   -- degrees of random aim error at 0 charge
Config.TRIDENT_MAX_ACCURACY = 0.99 -- accuracy (0-1) reached once fully charged
Config.TRIDENT_LIFETIME  = 1.6   -- seconds before a trident falls in the sea
Config.TRIDENT_RADIUS    = 2
Config.TRIDENT_SHAFT_LENGTH  = 8  -- length (px) of the trailing shaft line
Config.TRIDENT_PRONG_LENGTH  = 4  -- length (px) of each forward prong, from the crossbar
Config.TRIDENT_PRONG_SPREAD  = 3  -- half-width (px) of the crossbar / outer prong offset
Config.TRIDENT_LINE_WIDTH    = 2  -- stroke thickness (px) of the trident glyph
Config.TRIDENT_COUNT     = 1     -- tridents fired per manual release; set by the "Twin Tridents" upgrade
Config.TRIDENT_COUNT_MAX = 3     -- cap on TRIDENT_COUNT, used as the upgrade's maxValue
Config.TRIDENT_COUNT_SPREAD = 10 -- degrees between adjacent tridents when TRIDENT_COUNT > 1, fanned symmetrically around the aim direction
Config.TARGET_RANGE     = 160   -- max auto-target acquisition distance, default: 320
Config.AIM_LINE_LENGTH  = 32    -- length (px) of the converging aim-indicator lines
Config.AIM_LINE_WIDTH   = 2     -- stroke thickness (px) of the aim-indicator lines
Config.NO_TARGET_MARK_SIZE   = 22 -- pixel height of the "?" shown when charging with nothing in range
Config.NO_TARGET_MARK_OFFSET = 30 -- distance (px) from the ship's center to that mark

---------------------
-- Autofire Cannon --
---------------------
-- A single cannon, unlocked via the "Autofire Cannon" upgrade (see
-- ConfigUpgrades.lua), that fires on its own at the nearest enemy in range --
-- no player input, unlike the manual port/starboard trident. See GameScene's
-- cannonTimer tick and fireCannon.
Config.AUTOFIRE_CANNON_UNLOCKED = 0     -- 0 = not installed, >0 = installed; set by the upgrade
Config.AUTOFIRE_CANNON_DAMAGE   = 0.5     -- health removed from an enemy per cannon hit
Config.AUTOFIRE_CANNON_DELAY    = 2   -- seconds between shots
Config.AUTOFIRE_CANNON_RANGE    = Config.TARGET_RANGE / 2.5 -- max auto-target acquisition distance
-- Seconds AUTOFIRE_CANNON_DELAY drops by per pick of the "Rapid Autocannon"
-- upgrade (only offered once AUTOFIRE_CANNON_UNLOCKED -- see ConfigUpgrades.lua).
Config.AUTOFIRE_CANNON_DELAY_STEP = 0.25

-----------------
-- Storm Cloud --
-----------------
-- Summoned by the "Storm Cloud" upgrade (see ConfigUpgrades.lua): a slow
-- hazard that drifts toward whichever enemy is nearest and damages every
-- enemy within STORM_CLOUD_RADIUS on a fixed interval. Stacks -- each pick
-- of the upgrade adds one more independent cloud (see
-- GameScene:updateStormClouds and source/scripts/player/StormCloud.lua). The drawn
-- size (STORM_CLOUD_WIDTH/HEIGHT) is independent of STORM_CLOUD_RADIUS,
-- which only ever drives the damage check. With no enemy around, a cloud
-- instead follows the player until within STORM_CLOUD_FOLLOW_DISTANCE, then
-- wanders randomly (see the "Idle behavior" comment below) -- an enemy
-- appearing always preempts both.
Config.STORM_CLOUD_COUNT    = 0    -- number of clouds currently owned; set by the upgrade
Config.STORM_CLOUD_SPEED    = 20   -- px/s drift speed, whether tracking an enemy/player or wandering
Config.STORM_CLOUD_DAMAGE   = .8    -- health removed from every enemy in range, per damage tick
Config.STORM_CLOUD_DAMAGE_INTERVAL = 2 -- seconds between damage ticks
Config.STORM_CLOUD_RADIUS   = 50   -- px; damage-application radius, independent of the drawn image size below
Config.STORM_CLOUD_WIDTH    = 80   -- px; drawn width of the cloud image (source/assets/images/storm-cloud.png)
Config.STORM_CLOUD_HEIGHT   = 44   -- px; drawn height of the cloud image
-- Coverage (0-1) of the runtime-dithered checkerboard StormCloud.lua bakes
-- for the cloud's resting (non-flashing) look -- 0.5 is an even black/white
-- checker reading as mid-gray; higher = darker, lower = lighter. See the
-- "Resting-state gray" comment in StormCloud.lua.
Config.STORM_CLOUD_GREY_ALPHA = 0.5

-- Initial spawn (a fresh cloud backfilled by GameScene:updateStormClouds, not
-- the teleport-back-into-range case below): lands at a random point
-- somewhere on screen, at least this far from the player, so it never
-- appears directly on top of the ship. See StormCloud.randomSpawnPoint.
Config.STORM_CLOUD_SPAWN_MIN_DISTANCE = 80 -- px; minimum distance from the player for a freshly spawned cloud

-- Idle behavior (no enemy in play): follow the player until within
-- FOLLOW_DISTANCE, then wander in a random heading, picking a new one every
-- WANDER_MIN/MAX_INTERVAL seconds; drifting back out past FOLLOW_DISTANCE
-- while wandering resumes following. An enemy appearing always overrides
-- this, see StormCloud:update.
Config.STORM_CLOUD_FOLLOW_DISTANCE = 100 -- px; leash radius around the player for the follow/wander switch
Config.STORM_CLOUD_WANDER_MIN_INTERVAL = 1 -- seconds; shortest time before picking a new wander heading
Config.STORM_CLOUD_WANDER_MAX_INTERVAL = 3 -- seconds; longest time before picking a new wander heading

-- Idle-only failsafe: a cloud that's been trudging back toward the player
-- (the FOLLOW_DISTANCE case above) instead teleports once it's this far
-- away -- e.g. it wandered off while the player sailed away in the
-- meantime -- rather than spending ages walking the whole distance back at
-- STORM_CLOUD_SPEED. Lands at a random point LAND_MIN..LAND_MAX from the
-- player, the same "just beyond the screen's corner" idea as
-- GameScene:spawnEnemy's enemy spawn point, so it reappears out of sight
-- instead of popping in on screen.
Config.STORM_CLOUD_TELEPORT_DISTANCE = 500 -- px; no-enemy distance from the player that triggers a teleport
Config.STORM_CLOUD_TELEPORT_LAND_MIN = 250 -- px; nearest the teleport can land from the player
Config.STORM_CLOUD_TELEPORT_LAND_MAX = 300 -- px; farthest the teleport can land from the player

-- Lightning flash: between strikes the cloud draws as its normal image; a
-- strike briefly flashes it to solid white, then solid black, then back to
-- normal (see StormCloud:draw). STEP_DURATION is how long each of those two
-- flash steps lasts; MIN/MAX_INTERVAL bound the random wait between strikes.
Config.STORM_CLOUD_FLASH_MIN_INTERVAL = 0.2    -- seconds; shortest gap between flashes
Config.STORM_CLOUD_FLASH_MAX_INTERVAL = 0.8    -- seconds; longest gap between flashes
Config.STORM_CLOUD_FLASH_STEP_DURATION = 0.25 -- seconds each flash step (white, then black) lasts

-- Damage bolt: a jagged lightning line drawn from a cloud's center to each
-- enemy it damages on a given tick (see GameScene:updateStormClouds/
-- updateStormBolts/drawStormBolts). DURATION is how long the bolt stays on
-- screen after the hit; while shown, it flashes on/off every FLASH_FRAMES
-- frames rather than drawing solid. SEGMENTS/JITTER control the zigzag
-- shape (see Utils.lightningBoltPoints) and WIDTH is the stroke thickness.
Config.STORM_CLOUD_BOLT_DURATION     = 0.25 -- seconds a damage bolt stays on screen
Config.STORM_CLOUD_BOLT_FLASH_FRAMES = 2    -- frames each on/off flash step lasts while a bolt is shown
Config.STORM_CLOUD_BOLT_SEGMENTS     = 6    -- jagged line segments making up a bolt
Config.STORM_CLOUD_BOLT_JITTER       = 10   -- px; max perpendicular offset of each interior segment joint
Config.STORM_CLOUD_BOLT_WIDTH        = 2    -- stroke width (px) of the bolt line

-----------
-- Sound --
-----------
-- Trident-launch whoosh: synthesized (no audio assets), see Sound.lua. A
-- noise burst run through a bandpass filter whose center frequency sweeps
-- up then back down, giving a "rushing past" pitch shape.
Config.SOUND_WHOOSH_VOLUME    = 0.7  -- 0-1
Config.SOUND_WHOOSH_LENGTH    = 0.3  -- seconds, passed to synth:playNote
Config.SOUND_WHOOSH_ATTACK    = 0.01 -- seconds, noise burst fade-in
Config.SOUND_WHOOSH_DECAY     = 0.12 -- seconds, noise burst fade-out (sustain is 0, so decay is effectively the whole tail)
Config.SOUND_WHOOSH_RELEASE   = 0.08 -- seconds
Config.SOUND_WHOOSH_FILTER_RESONANCE = 0.45 -- 0-1, higher = more "whistle", risks self-oscillation near 1
Config.SOUND_WHOOSH_SWEEP_ATTACK  = 0.015 -- seconds for the filter sweep to reach its peak frequency
Config.SOUND_WHOOSH_SWEEP_DECAY   = 0.22  -- seconds for the filter sweep to fall back off
Config.SOUND_WHOOSH_SWEEP_MIN_HZ  = 300   -- filter center frequency at the start/end of the sweep
Config.SOUND_WHOOSH_SWEEP_RANGE_HZ = 2200 -- how far above SWEEP_MIN_HZ the sweep peaks

-- Sampled one-shot SFX played via SoundBank (source/assets/sounds, rendered
-- from art-src/sounds by tools/render-sfx.sh) -- distinct from the
-- synthesized whoosh above.
Config.SOUND_SFX_VOLUME = 0.7 -- 0-1, applied to every SoundBank on load

-----------
-- Music --
-----------
-- MusicPlayer.lua: plays a song's pre-rendered ADPCM .wav pieces (see
-- tools/render-song.sh) via playdate.sound.fileplayer -- see
-- MusicPlayer.selectSong/setEnabled/playDefault for how the fields below
-- get kept in sync between main.lua's boot logic, the system-menu "Music"
-- checkmark, and SettingsScene's Sound section.
Config.MUSIC_ENABLED = true   -- master on/off for background music playback
Config.MUSIC_SONG = nil       -- song name (a file under MusicPlayer.SONGS_DIR), or nil for no song selected
Config.MUSIC_VOLUME = 0.6     -- 0-1, master volume. Changing this at runtime needs a MusicPlayer.applyVolume() call to take effect immediately.

---------
-- HUD --
---------
-- Off-screen enemy indicators: enemies whose on-screen directions fall
-- within OFFSCREEN_INDICATOR_GROUP_ANGLE of each other share a single arrow
-- (with a count badge) instead of stacking separate ones.
Config.OFFSCREEN_INDICATOR_MARGIN      = 75  -- px inset from the screen edge
Config.OFFSCREEN_INDICATOR_SIZE        = 14  -- pixel size of the arrow glyph
Config.OFFSCREEN_INDICATOR_GROUP_ANGLE = 18  -- degrees; enemies this close together share one indicator
Config.OFFSCREEN_INDICATOR_COUNT_SIZE  = 24  -- pixel height of the group count text
-- Full on/off blink cycle (seconds) for an indicator flagged by
-- GameScene:shouldFlashOffscreenIndicator -- see drawOffscreenArrows.
Config.OFFSCREEN_INDICATOR_FLASH_PERIOD = 0.4

-- Toggled from SettingsScene (reached from the title screen); all default to visible.
Config.HUD_SHOW_WIND_SPEED     = true
Config.HUD_SHOW_WIND_DIRECTION = true
Config.HUD_SHOW_PLAYER_SPEED   = true
-- Noble Engine's built-in FPS counter (playdate.drawFPS, top-left). Unlike
-- the HUD_SHOW_* fields above, this doesn't get read directly at draw time --
-- it's mirrored onto Noble.showFPS at boot (main.lua) and whenever
-- SettingsScene's "FPS Counter" row is toggled, since that's the flag Noble's
-- own update loop actually checks. See Noble.lua's showFPS field.
Config.HUD_SHOW_FPS = true

-- Health hearts (top-left): drawn one glyph at a time so spacing is exact
-- regardless of what the font reports for a run of hearts + spaces.
Config.HUD_HEART_MARGIN_X = 6   -- px inset from the left screen edge to the first heart
Config.HUD_HEART_MARGIN_Y = 4   -- px inset from the top screen edge
Config.HUD_HEART_SPACING  = 20  -- px from one heart's left edge to the next's
Config.HUD_EMPTY_HEART_SCALE = 0.75  -- size of a missing heart, relative to a full one

-- Wind-change bar (test scene only, see GameSceneTraining:drawHUD): drawn as a
-- crawling sine wave instead of a flat bar to match the water's look.
Config.WIND_BAR_WAVE_AMPLITUDE  = 3   -- px the wave bulges above/below its baseline
Config.WIND_BAR_WAVE_WAVELENGTH = 20  -- px length of one full wave cycle
Config.WIND_BAR_WAVE_SPEED      = 40  -- px/s the wave crawls sideways

------------
-- Levels --
------------
-- Level N clears once the player has defeated N * LEVEL_ENEMY_STEP enemies
-- since that level began (level 1 -> 5, level 2 -> 10, ...).
Config.LEVEL_ENEMY_STEP = 3

-- Seconds GameSceneMain:tickGame holds on the just-cleared level (gameplay
-- frozen, see the levelComplete guard) before handing off to
-- onLevelComplete/LevelCompleteScene.
Config.LEVEL_COMPLETE_DELAY = 3

-- Wind gets both twitchier and more frequent as levels climb (see
-- GameSceneMain:windTuning), but not on every level -- it steps up once every
-- LEVEL_WIND_STEP_INTERVAL levels (2 = every other level: 1, 3, 5, ... step
-- up; 2, 4, 6, ... hold the previous step's wind). Each step adds
-- LEVEL_WIND_SPEED_CHANGE_RATE_STEP to WIND_SPEED_CHANGE_RATE_MIN/MAX and
-- subtracts LEVEL_WIND_CHANGE_INTERVAL_STEP from WIND_CHANGE_INTERVAL_MIN/MAX,
-- floored at WIND_CHANGE_INTERVAL_FLOOR so changes can't stack up faster than
-- the ease from the previous one. WindShiftScene (see GameSceneMain.windStepForLevel)
-- announces the level transitions where a step actually lands.
Config.LEVEL_WIND_STEP_INTERVAL          = 3   -- levels per wind escalation step
Config.LEVEL_WIND_SPEED_CHANGE_RATE_STEP = 0.3 -- px/s per second added to the wind's easing rate, per step
Config.LEVEL_WIND_CHANGE_INTERVAL_STEP   = 0.75 -- seconds shaved off the time between wind changes, per step
Config.WIND_CHANGE_INTERVAL_FLOOR        = 4   -- seconds; LEVEL_WIND_CHANGE_INTERVAL_STEP won't shrink the interval past this

---------------
-- Demo mode --
---------------
-- Set true to make TitleScene's "Play" item launch GameSceneDemo instead of
-- GameSceneMain -- see TitleScene's confirmSelection. This is a build-time
-- switch (baked into the compiled .pdx via this default, not a runtime
-- Settings toggle), meant for shipping a capped trade-show/kiosk build.
-- Off by default -- flip to true and rebuild to produce a demo .pdx.
Config.DEMO_MODE = false
Config.DEMO_MAX_LEVEL = 5 -- levels GameSceneDemo plays through before DemoOverScene ends the run

------------------
-- Title screen --
------------------
-- The menu card stays hidden for TITLE_MENU_DELAY seconds (letting the
-- splash art sit alone for a beat), then appears in place -- see
-- TitleScene:update.
Config.TITLE_MENU_DELAY = 3          -- seconds before the menu appears

------------------------
-- Instructions screen --
------------------------
-- Every direction of every control gets its own step (crank one way, then
-- the other; Up, then Down; Left broadside, then Right), so the player
-- actually exercises both instead of just whichever's more convenient. Each
-- step's prompt clears once the player has performed it enough -- a
-- held/analog input for long enough (crank) or a discrete action repeated
-- enough times (button presses) -- see InstructionsScene.
Config.INSTRUCTIONS_CRANK_SECONDS = 2       -- seconds spent actively cranking one direction to clear that crank step
Config.INSTRUCTIONS_TRIM_PRESSES = 3        -- presses of Up (or Down) to clear that trim step
Config.INSTRUCTIONS_BROADSIDE_PRESSES = 3   -- in-range presses of Left (or Right) to clear that broadside step -- see InstructionsScene:onBroadsideButtonDown
Config.INSTRUCTIONS_DUMMY_DISTANCE = 120    -- px from the ship the practice dummy spawns at during the broadside steps
-- How long the broadside steps' target can sit continuously out of range
-- before the hint escalates from "get closer" to pointing at the flashing
-- off-screen indicator -- see InstructionsScene:tickGame/stepSubline.
Config.INSTRUCTIONS_OUT_OF_RANGE_HINT_SECONDS = 5

-- White rounded-rect card the current step's prompt/progress text is drawn
-- on, so it stays readable over the water/ship instead of floating bare --
-- see InstructionsScene:drawInstructionText.
Config.INSTRUCTIONS_TEXT_BOX_TOP          = 8   -- px from the top of the screen to the box
Config.INSTRUCTIONS_TEXT_BOX_MARGIN_RIGHT = 8   -- px from the right of the screen to the box
Config.INSTRUCTIONS_TEXT_BOX_PADDING_X    = 10  -- px horizontal padding inside the box
Config.INSTRUCTIONS_TEXT_BOX_PADDING_Y    = 6   -- px vertical padding inside the box
Config.INSTRUCTIONS_TEXT_BOX_RADIUS       = 8   -- corner radius (px)
Config.INSTRUCTIONS_TEXT_LINE_GAP         = 2   -- px gap between the prompt and progress/hint lines
Config.INSTRUCTIONS_TEXT_BOX_MAX_WIDTH    = 220 -- px each line wraps at -- the out-of-range hint is long enough to need it

----------
-- Boot --
----------
-- Which scene the game boots into (see main.lua's sceneByName table for the
-- full list of valid names). Defaults to the title screen.
--
-- Playdate's Lua sandbox has no os.getenv, so this can't be read from an
-- environment variable directly: override it for local testing via the
-- MERMAID_START_SCENE environment variable when running tools/simulate.sh,
-- which forwards it to the Simulator as a launch argument; main.lua reads it
-- back out of playdate.argv[1] and falls back to this default if unset.
Config.START_SCENE = "Title"

return Config
