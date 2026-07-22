-- ConfigTuning.lua
-- The tunable-field table backing TuningScene (source/scenes/TuningScene.lua)
-- and TuningDiffScene (source/scenes/TuningDiffScene.lua), split out of
-- TuningScene.lua like ConfigEnemy.lua/ConfigUpgrades.lua were split out of
-- Config.lua -- still just describes/reads/writes the shared global Config
-- table, not a separate state store. Import "scripts/utilities/Config"
-- first (this file assumes Config.WATER_GRID etc. already exist).
--
-- Also owns the three system-menu actions TuningScene wires up ("Load
-- Defaults", "Load Custom", "Save Custom"):
--  - Config.resetUpgrades (ConfigUpgrades.lua) restores upgrade-touched
--    fields to their fresh-game baseline; ConfigTuning.loadDefaults does the
--    same thing for every field listed in ConfigTuning.ITEMS below.
--  - ConfigTuning.saveCustom/loadCustom persist/restore a single named slot
--    via playdate.datastore.write/read (Data/<bundleid>/CUSTOM_SLOT.json on
--    device) -- the first thing in this codebase to touch
--    playdate.datastore. This is deliberately a separate mechanism from
--    Config.resetUpgrades: upgrades are per-run state reset on death, while
--    a tuning custom slot is a player-authored preset meant to survive
--    across app relaunches, saved/loaded only when explicitly asked via the
--    system menu.
--  - ConfigTuning.diffFromDefaults compares the live Config values against
--    the fresh-load baseline so TuningDiffScene can show what a Load
--    actually changed.

import "scripts/utilities/Config"

---@class ConfigTuning.Item
---@field key string Config field this row edits
---@field label string display label, auto-derived from key unless overridden
---@field type "number"|"boolean"
---@field step? number amount Left/Right adjusts a number row by
---@field min? number
---@field max? number
---@field decimals? integer digits shown/rounded to for a number row
---@field headerBefore? string category name, set on the first item of each CATEGORIES entry -- see the flatten loop below

---@class ConfigTuning
ConfigTuning = {}

-- Datastore filename (extension-less, per playdate.datastore convention) for
-- the single custom-tuning save slot "Save Custom"/"Load Custom" read and
-- write. Just one slot -- saving again overwrites whatever was there before.
ConfigTuning.CUSTOM_SLOT = "tuning_custom"

-- Every adjustable Config.lua field, grouped to mirror Config.lua's own
-- section comments -- see TuningScene.lua's header for what's deliberately
-- left out and why. `label` is auto-derived from `key` (see titleCase
-- below) unless given explicitly, which HUD_SHOW_* uses since "Hud Show
-- Wind Speed" reads worse than a hand-picked label.
ConfigTuning.CATEGORIES = {
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

-- Flattened once at load time, in on-screen order. TuningScene's
-- selected/moveSelection/adjustValue/toggleBoolean index directly into
-- this -- MenuCard takes headerBefore on the item itself and inserts the
-- header display-side, so ITEMS' numbering never has to account for them.
---@type ConfigTuning.Item[]
ConfigTuning.ITEMS = {}
for _, category in ipairs(ConfigTuning.CATEGORIES) do
	for j, item in ipairs(category.items) do
		item.type = item.type or "number"
		item.decimals = item.decimals or 0
		item.label = item.label or titleCase(item.key)
		if j == 1 then item.headerBefore = category.name end
		ConfigTuning.ITEMS[#ConfigTuning.ITEMS + 1] = item
	end
end

-- Snapshot of every ConfigTuning.ITEMS field's value as of this file's first
-- load (before any runtime tuning has ever happened), so loadDefaults/
-- diffFromDefaults have a fresh-game baseline to compare against -- same
-- idea as ConfigUpgrades.lua's upgradeBaselines.
local defaults = {}
for _, item in ipairs(ConfigTuning.ITEMS) do
	defaults[item.key] = Config[item.key]
end

-- Renders `value` (not necessarily the live Config value -- TuningDiffScene
-- passes the default baseline too) the way `item`'s type/decimals say to.
---@param item ConfigTuning.Item
---@param value number|boolean
---@return string
function ConfigTuning.formatValue(item, value)
	if item.type == "boolean" then
		return value and "On" or "Off"
	end
	return string.format("%." .. item.decimals .. "f", value)
end

-- Restores every ConfigTuning.ITEMS field back to its fresh-load baseline --
-- "Load Defaults" in TuningScene's system menu.
function ConfigTuning.loadDefaults()
	for _, item in ipairs(ConfigTuning.ITEMS) do
		Config[item.key] = defaults[item.key]
	end
end

-- Writes every ConfigTuning.ITEMS field's current Config value to the custom
-- datastore slot, overwriting whatever was saved there before -- "Save
-- Custom" in TuningScene's system menu.
function ConfigTuning.saveCustom()
	local data = {}
	for _, item in ipairs(ConfigTuning.ITEMS) do
		data[item.key] = Config[item.key]
	end
	playdate.datastore.write(data, ConfigTuning.CUSTOM_SLOT)
end

-- Reads the custom datastore slot and applies whichever recognized fields it
-- contains onto Config -- "Load Custom" in TuningScene's system menu. A slot
-- saved by an older build might be missing fields this build added (or carry
-- ones it removed); only keys ConfigTuning.ITEMS still recognizes are
-- applied, so a stale or partial save can't leave unrelated Config fields
-- untouched or crash on an unknown one.
---@return boolean loaded true if a saved custom slot existed to load
function ConfigTuning.loadCustom()
	local data = playdate.datastore.read(ConfigTuning.CUSTOM_SLOT)
	if not data then return false end
	for _, item in ipairs(ConfigTuning.ITEMS) do
		if data[item.key] ~= nil then
			Config[item.key] = data[item.key]
		end
	end
	return true
end

-- Every ConfigTuning.ITEMS field whose live Config value no longer matches
-- its fresh-load baseline, in on-screen order -- what TuningDiffScene lists
-- after a Load Defaults/Load Custom.
---@return { item: ConfigTuning.Item, default: number|boolean, current: number|boolean }[]
function ConfigTuning.diffFromDefaults()
	local diffs = {}
	for _, item in ipairs(ConfigTuning.ITEMS) do
		local current = Config[item.key]
		local default = defaults[item.key]
		if current ~= default then
			diffs[#diffs + 1] = { item = item, default = default, current = current }
		end
	end
	return diffs
end

return ConfigTuning
