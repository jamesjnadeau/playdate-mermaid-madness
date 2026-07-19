-- TuningScene.lua
-- Reached from SettingsScene's "Tuning" section (its "Open Tuning Menu" row
-- -- see SettingsScene.lua). Lets you live-adjust nearly every Config.lua
-- tuning value from a single scrollable, categorized menu -- unlike
-- SettingsScene's HUD/Sound rows, this is meant as a broad debug/tweak
-- surface, not a curated player-facing settings screen; that's also why it's
-- not reachable directly from the title screen. Changes are runtime-only:
-- they mutate the global Config table exactly like SettingsScene's
-- HUD_SHOW_* toggles already do, and nothing here ever touches
-- playdate.datastore, so nothing persists past this play session. Built
-- with the playout UI library, see libraries/playout.lua. Up/Down move the
-- highlight (wraps); the crank fast-scrolls through the list; Left/Right
-- adjust the highlighted numeric setting; Ⓐ toggles the highlighted boolean
-- setting; Ⓑ returns to SettingsScene.
--
-- Deliberately leaves out:
--  - every Config.ENEMY_*/ConfigEnemy.lua field.
--  - Config.EXPLOSION (a structured table of pdParticles setters, not a
--    single scalar value -- EXPLOSION_WIND_INFLUENCE, the one plain-number
--    knob next to it, is still exposed below).
--  - Config.SCREEN_W/SCREEN_H/REFRESH/DT (display fundamentals baked in via
--    playdate.display.setRefreshRate at boot in main.lua; changing them here
--    wouldn't reconfigure the display or fixed timestep mid-run).
--  - Config.START_SCENE (a string naming a scene class, and boot-time only).
--  - Config.DEMO_MODE/DEMO_MAX_LEVEL (explicitly documented in Config.lua as
--    a build-time switch for a kiosk .pdx, not a runtime setting).
--  - Config.MUSIC_VOLUME/MUSIC_SONG (covered by SettingsScene's own Sound
--    section instead; MUSIC_SONG is a filename string besides, which this
--    scene's number/boolean row types don't support).
--  - Config.HUD_SHOW_FPS (covered by SettingsScene's HUD section instead --
--    toggling it needs a side effect, syncing Noble.showFPS, that this
--    scene's generic toggleBoolean doesn't perform).

import "scripts/Config"
import "scripts/Utils"

local gfx <const> = playdate.graphics

---@class TuningScene.Item
---@field key string Config field this row edits
---@field label string display label, auto-derived from key unless overridden
---@field type "number"|"boolean"
---@field step? number amount Left/Right adjusts a number row by
---@field min? number
---@field max? number
---@field decimals? integer digits shown/rounded to for a number row
---@field row integer index into ROWS, filled in when the category table is flattened below

---@class TuningScene : NobleScene
---@field selected integer index into SETTING_ROWS
---@field crankAccum number leftover crank degrees not yet converted into a row move, see the cranked handler
---@field tree table playout tree, see rebuild()
---@field img _Image drawn image of the playout tree, see rebuild()
TuningScene = class("TuningScene").extends(NobleScene) or TuningScene

local scene = nil

-- How many rows (category headers + settings) fit in the scroll window at
-- once -- see computeScrollStart/buildTree.
local VISIBLE_ROWS = 9

-- Degrees of crank rotation that scrolls the list by one row.
local CRANK_DEGREES_PER_ROW = 20

-- Every adjustable Config.lua field, grouped to mirror Config.lua's own
-- section comments -- see the file header above for what's deliberately
-- left out and why. `label` is auto-derived from `key` (see titleCase
-- below) unless given explicitly, which HUD_SHOW_* uses since "Hud Show
-- Wind Speed" reads worse than a hand-picked label.
local CATEGORIES = {
	{ name = "Water", items = {
		{ key = "WATER_GRID", step = 5, min = 10, max = 300 },
		{ key = "WATER_WAVELET_LENGTH_MIN", step = 1, min = 1, max = 200 },
		{ key = "WATER_WAVELET_LENGTH_MAX", step = 1, min = 1, max = 300 },
		{ key = "WATER_WAVELET_WIDTH", step = 1, min = 1, max = 10 },
		{ key = "WATER_WAVELET_SEGMENTS_PER_ZIGZAG_MIN", step = 1, min = 1, max = 20 },
		{ key = "WATER_WAVELET_SEGMENTS_PER_ZIGZAG_MAX", step = 1, min = 1, max = 30 },
		{ key = "WATER_WAVELET_AMPLITUDE", step = 1, min = 0, max = 50 },
		{ key = "WATER_WAVELET_ZIGZAGS_MIN", step = 1, min = 1, max = 10 },
		{ key = "WATER_WAVELET_ZIGZAGS_MAX", step = 1, min = 1, max = 15 },
		{ key = "WATER_WAVELET_SPAWN_CHANCE", step = 0.05, min = 0, max = 1, decimals = 2 },
	} },
	{ name = "Wind", items = {
		{ key = "WIND_SPEED_MIN", step = 5, min = 0, max = 300 },
		{ key = "WIND_SPEED_MAX", step = 5, min = 0, max = 400 },
		{ key = "WIND_SPEED_CHANGE_RATE_MIN", step = 0.5, min = 0, max = 20, decimals = 1 },
		{ key = "WIND_SPEED_CHANGE_RATE_MAX", step = 0.5, min = 0, max = 20, decimals = 1 },
		{ key = "WIND_CHANGE_INTERVAL_MIN", step = 1, min = 1, max = 60 },
		{ key = "WIND_CHANGE_INTERVAL_MAX", step = 1, min = 1, max = 60 },
		{ key = "WIND_DIRECTION_CHANGE_MIN", step = 5, min = 0, max = 180 },
		{ key = "WIND_DIRECTION_CHANGE_MAX", step = 5, min = 0, max = 180 },
		{ key = "WIND_DIRECTION_CHANGE_RATE_MIN", step = 0.5, min = 0, max = 30, decimals = 1 },
		{ key = "WIND_DIRECTION_CHANGE_RATE_MAX", step = 0.5, min = 0, max = 30, decimals = 1 },
		{ key = "WIND_INDICATOR_CIRCLE_SIZE", step = 1, min = 1, max = 80 },
		{ key = "WIND_INDICATOR_SIZE", step = 1, min = 1, max = 80 },
		{ key = "WAKE_WIND_INFLUENCE", step = 0.05, min = 0, max = 1, decimals = 2 },
	} },
	{ name = "Explosions", items = {
		{ key = "EXPLOSION_WIND_INFLUENCE", step = 0.05, min = 0, max = 1, decimals = 2 },
	} },
	{ name = "Ship", items = {
		{ key = "SHIP_MAX_SPEED", step = 5, min = 10, max = 400 },
		{ key = "SHIP_DEFAULT_SPEED", step = 1, min = 0, max = 200 },
		{ key = "SHIP_ACCEL", step = 5, min = 0, max = 400 },
		{ key = "SHIP_TURN_SCALE", step = 0.05, min = 0.05, max = 3, decimals = 2 },
		{ key = "SHIP_MAX_HEALTH", step = 1, min = 1, max = 20 },
		{ key = "SHIP_LENGTH", step = 1, min = 5, max = 60 },
		{ key = "SHIP_COLLIDE_RADIUS", step = 1, min = 4, max = 80 },
		{ key = "SHIP_BEAM", step = 1, min = 2, max = 40 },
		{ key = "SHIP_WIND_POWER_MULTIPLIER", step = 0.1, min = 0, max = 5, decimals = 2 },
		{ key = "SHIP_WATER_FRICTION", step = 0.01, min = 0, max = 1, decimals = 3 },
		{ key = "SHIP_OVERSPEED_FRICTION", step = 0.01, min = 0, max = 1, decimals = 3 },
	} },
	{ name = "Sail", items = {
		{ key = "SAIL_TRIM_START", step = 0.05, min = 0, max = 1, decimals = 2 },
		{ key = "SAIL_TRIM_RATE", step = 0.1, min = 0.1, max = 10, decimals = 2 },
		{ key = "SAIL_MAX_ANGLE", step = 5, min = 10, max = 180 },
		{ key = "SAIL_LENGTH", step = 1, min = 5, max = 80 },
		{ key = "SAIL_SWING_SPEED", step = 5, min = 1, max = 500 },
		{ key = "SAIL_SWING_FRICTION", step = 0.5, min = 0, max = 50, decimals = 1 },
	} },
	{ name = "Trident", items = {
		{ key = "TRIDENT_CHARGE_RATE", step = 0.05, min = 0.05, max = 5, decimals = 2 },
		{ key = "TRIDENT_DAMAGE", step = 1, min = 1, max = 20 },
		{ key = "TRIDENT_SPEED", step = 10, min = 50, max = 1000 },
		{ key = "TRIDENT_MAX_SPREAD", step = 1, min = 0, max = 90 },
		{ key = "TRIDENT_MAX_ACCURACY", step = 0.01, min = 0, max = 1, decimals = 2 },
		{ key = "TRIDENT_LIFETIME", step = 0.1, min = 0.1, max = 10, decimals = 2 },
		{ key = "TRIDENT_RADIUS", step = 1, min = 1, max = 20 },
		{ key = "TRIDENT_SHAFT_LENGTH", step = 1, min = 1, max = 40 },
		{ key = "TRIDENT_PRONG_LENGTH", step = 1, min = 1, max = 40 },
		{ key = "TRIDENT_PRONG_SPREAD", step = 1, min = 1, max = 40 },
		{ key = "TRIDENT_LINE_WIDTH", step = 1, min = 1, max = 10 },
		{ key = "TARGET_RANGE", step = 10, min = 20, max = 800 },
		{ key = "AIM_LINE_LENGTH", step = 1, min = 1, max = 60 },
		{ key = "AIM_LINE_WIDTH", step = 1, min = 1, max = 10 },
		{ key = "NO_TARGET_MARK_SIZE", step = 1, min = 1, max = 60 },
		{ key = "NO_TARGET_MARK_OFFSET", step = 1, min = 1, max = 100 },
	} },
	{ name = "HUD", items = {
		{ key = "OFFSCREEN_INDICATOR_MARGIN", step = 5, min = 0, max = 200 },
		{ key = "OFFSCREEN_INDICATOR_SIZE", step = 1, min = 4, max = 60 },
		{ key = "OFFSCREEN_INDICATOR_GROUP_ANGLE", step = 1, min = 1, max = 90 },
		{ key = "OFFSCREEN_INDICATOR_COUNT_SIZE", step = 1, min = 4, max = 60 },
		{ key = "OFFSCREEN_INDICATOR_FLASH_PERIOD", step = 0.05, min = 0.05, max = 5, decimals = 2 },
		{ key = "HUD_SHOW_WIND_SPEED", type = "boolean", label = "HUD Wind Speed" },
		{ key = "HUD_SHOW_WIND_DIRECTION", type = "boolean", label = "HUD Wind Direction" },
		{ key = "HUD_SHOW_PLAYER_SPEED", type = "boolean", label = "HUD Player Speed" },
		{ key = "HUD_HEART_MARGIN_X", step = 1, min = 0, max = 100 },
		{ key = "HUD_HEART_MARGIN_Y", step = 1, min = 0, max = 100 },
		{ key = "HUD_HEART_SPACING", step = 1, min = 5, max = 60 },
		{ key = "HUD_EMPTY_HEART_SCALE", step = 0.05, min = 0.1, max = 2, decimals = 2 },
		{ key = "WIND_BAR_WAVE_AMPLITUDE", step = 1, min = 0, max = 40 },
		{ key = "WIND_BAR_WAVE_WAVELENGTH", step = 1, min = 2, max = 100 },
		{ key = "WIND_BAR_WAVE_SPEED", step = 5, min = 0, max = 200 },
	} },
	{ name = "Levels", items = {
		{ key = "LEVEL_ENEMY_STEP", step = 1, min = 1, max = 50 },
		{ key = "LEVEL_WIND_STEP_INTERVAL", step = 1, min = 1, max = 20 },
		{ key = "LEVEL_WIND_SPEED_CHANGE_RATE_STEP", step = 0.1, min = 0, max = 5, decimals = 2 },
		{ key = "LEVEL_WIND_CHANGE_INTERVAL_STEP", step = 0.25, min = 0, max = 10, decimals = 2 },
		{ key = "WIND_CHANGE_INTERVAL_FLOOR", step = 1, min = 1, max = 30 },
	} },
	{ name = "Title Screen", items = {
		{ key = "TITLE_MENU_DELAY", step = 0.5, min = 0, max = 20, decimals = 1 },
		{ key = "TITLE_MENU_RISE_DURATION", step = 0.1, min = 0.1, max = 10, decimals = 2 },
	} },
	{ name = "Instructions", items = {
		{ key = "INSTRUCTIONS_CRANK_SECONDS", step = 0.5, min = 0.5, max = 20, decimals = 1 },
		{ key = "INSTRUCTIONS_TRIM_PRESSES", step = 1, min = 1, max = 20 },
		{ key = "INSTRUCTIONS_BROADSIDE_PRESSES", step = 1, min = 1, max = 20 },
		{ key = "INSTRUCTIONS_DUMMY_DISTANCE", step = 10, min = 20, max = 600 },
		{ key = "INSTRUCTIONS_OUT_OF_RANGE_HINT_SECONDS", step = 1, min = 1, max = 60 },
		{ key = "INSTRUCTIONS_TEXT_BOX_TOP", step = 1, min = 0, max = 100 },
		{ key = "INSTRUCTIONS_TEXT_BOX_MARGIN_RIGHT", step = 1, min = 0, max = 100 },
		{ key = "INSTRUCTIONS_TEXT_BOX_PADDING_X", step = 1, min = 0, max = 40 },
		{ key = "INSTRUCTIONS_TEXT_BOX_PADDING_Y", step = 1, min = 0, max = 40 },
		{ key = "INSTRUCTIONS_TEXT_BOX_RADIUS", step = 1, min = 0, max = 30 },
		{ key = "INSTRUCTIONS_TEXT_LINE_GAP", step = 1, min = 0, max = 20 },
		{ key = "INSTRUCTIONS_TEXT_BOX_MAX_WIDTH", step = 10, min = 50, max = 400 },
	} },
}

-- "WATER_WAVELET_LENGTH_MIN" -> "Water Wavelet Length Min".
---@param key string
---@return string
local function titleCase(key)
	return (key:gsub("_", " "):gsub("%a[%w']*", function(word)
		return word:sub(1, 1):upper() .. word:sub(2):lower()
	end))
end

---@param v number
---@param decimals integer
---@return number
local function roundTo(v, decimals)
	local mult = 10 ^ decimals
	return math.floor(v * mult + 0.5) / mult
end

-- Flattened once at load time: ROWS is every row in on-screen order
-- (category headers + settings), SETTING_ROWS is just the selectable
-- subset -- moveSelection/adjustValue/toggleBoolean index into SETTING_ROWS,
-- each entry's `row` field points back into ROWS so buildTree knows where
-- the current selection sits for scrolling.
local ROWS = {}
local SETTING_ROWS = {}
for _, category in ipairs(CATEGORIES) do
	ROWS[#ROWS + 1] = { kind = "header", label = category.name }
	for _, item in ipairs(category.items) do
		item.type = item.type or "number"
		item.decimals = item.decimals or 0
		item.label = item.label or titleCase(item.key)
		ROWS[#ROWS + 1] = { kind = "setting", item = item }
		item.row = #ROWS
		SETTING_ROWS[#SETTING_ROWS + 1] = item
	end
end

---@param item TuningScene.Item
---@return string
local function formatValue(item)
	if item.type == "boolean" then
		return Config[item.key] and "[x] " or "[ ] "
	end
	return string.format("%." .. item.decimals .. "f", Config[item.key])
end

-- Keeps the selected row inside a VISIBLE_ROWS-tall window, recentering
-- rather than nudging by one -- simple and correct regardless of how far a
-- single crank tick or selection wrap moves the target row.
---@param rowIndex integer
---@return integer
local function computeScrollStart(rowIndex)
	local start = rowIndex - math.floor(VISIBLE_ROWS / 2)
	local maxStart = math.max(1, #ROWS - VISIBLE_ROWS + 1)
	return Utils.clamp(start, 1, maxStart)
end

-- Builds a fresh playout tree around `selectedIndex` (into SETTING_ROWS),
-- windowed to VISIBLE_ROWS around the current selection. Rebuilt (rather
-- than mutated in place) on every change, same as SettingsScene/
-- EnemySelectScene.
---@param selectedIndex integer
---@return table playout tree
local function buildTree(selectedIndex)
	local currentItem = SETTING_ROWS[selectedIndex]
	local start = computeScrollStart(currentItem.row)
	local lastVisible = math.min(#ROWS, start + VISIBLE_ROWS - 1)

	local children = {
		playout.text.new("Tuning"),
	}
	if start > 1 then
		children[#children + 1] = playout.text.new("^ more above")
	end
	for i = start, lastVisible do
		local row = ROWS[i]
		if row.kind == "header" then
			children[#children + 1] = playout.text.new(row.label)
		else
			local item = row.item
			local isSelected = item == currentItem
			local text = item.type == "boolean" and (formatValue(item) .. item.label)
				or (item.label .. ": " .. formatValue(item))
			children[#children + 1] = playout.box.new({
				padding = 2,
				hAlign = playout.kAlignStart,
				backgroundColor = isSelected and gfx.kColorBlack or nil,
			}, {
				playout.text.new(text, {
					color = isSelected and gfx.kColorWhite or gfx.kColorBlack,
				}),
			})
		end
	end
	if lastVisible < #ROWS then
		children[#children + 1] = playout.text.new("v more below")
	end
	children[#children + 1] = playout.text.new("Left/Right adjust  Ⓐ toggle  Ⓑ back")

	local root = playout.box.new({
		direction = playout.kDirectionVertical,
		spacing = 4,
		padding = 10,
		hAlign = playout.kAlignCenter,
		backgroundColor = gfx.kColorWhite,
		border = 2,
		borderRadius = 6,
	}, children)

	return playout.tree.new(root)
end

---@param ... any
function TuningScene:init(...)
	TuningScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
	self.selected = 1
	self.crankAccum = 0

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.img must already exist by then.
	self:rebuild()
end

function TuningScene:start()
	TuningScene.super.start(self)
	scene = self
end

function TuningScene:finish()
	TuningScene.super.finish(self)
	if scene == self then scene = nil end
end

function TuningScene:rebuild()
	self.tree = buildTree(self.selected)
	self.img = self.tree:draw()
end

---@param delta integer
local function moveSelection(delta)
	if not scene then return end
	local count = #SETTING_ROWS
	scene.selected = ((scene.selected - 1 + delta) % count) + 1
	scene:rebuild()
end

---@param delta integer -1 or 1, in units of the row's step
local function adjustValue(delta)
	if not scene then return end
	local item = SETTING_ROWS[scene.selected]
	if item.type ~= "number" then return end
	local newValue = roundTo(Config[item.key] + delta * item.step, item.decimals)
	Config[item.key] = Utils.clamp(newValue, item.min, item.max)
	scene:rebuild()
end

local function toggleBoolean()
	if not scene then return end
	local item = SETTING_ROWS[scene.selected]
	if item.type ~= "boolean" then return end
	Config[item.key] = not Config[item.key]
	scene:rebuild()
end

TuningScene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	leftButtonDown = function() adjustValue(-1) end,
	rightButtonDown = function() adjustValue(1) end,
	AButtonDown = function() toggleBoolean() end,
	BButtonDown = function()
		if scene then Noble.transition(SettingsScene) end
	end,
	-- Fast-scroll: the list is long enough (~90 rows) that Up/Down alone is
	-- tedious, so the crank moves the selection one row per
	-- CRANK_DEGREES_PER_ROW degrees turned, in either direction. crankAccum
	-- carries leftover sub-threshold rotation between calls.
	cranked = function(change)
		if not scene then return end
		scene.crankAccum = scene.crankAccum + change
		while scene.crankAccum >= CRANK_DEGREES_PER_ROW do
			moveSelection(1)
			scene.crankAccum = scene.crankAccum - CRANK_DEGREES_PER_ROW
		end
		while scene.crankAccum <= -CRANK_DEGREES_PER_ROW do
			moveSelection(-1)
			scene.crankAccum = scene.crankAccum + CRANK_DEGREES_PER_ROW
		end
	end,
}

function TuningScene:update()
	TuningScene.super.update(self)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	local x = (Config.SCREEN_W - self.img.width) / 2
	local y = (Config.SCREEN_H - self.img.height) / 2
	self.img:draw(x, y)
end
