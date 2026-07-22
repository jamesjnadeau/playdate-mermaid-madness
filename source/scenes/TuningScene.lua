-- TuningScene.lua
-- Reached from SettingsScene's "Open Tuning Menu" row. Lets you live-adjust
-- nearly every Config.lua tuning value from a single scrollable, categorized
-- menu -- unlike SettingsScene's curated rows, this is meant as a broad
-- debug/tweak surface, not a player-facing settings screen; that's also why
-- it's not reachable directly from the title screen. Changes are
-- runtime-only by default -- they mutate the global Config table exactly
-- like SettingsScene's HUD_SHOW_* toggles already do -- but this scene's
-- system-menu items (see below) can persist/restore a whole snapshot of
-- them via playdate.datastore, through ConfigTuning
-- (source/scripts/utilities/ConfigTuning.lua), which owns the actual
-- ITEMS/CATEGORIES table, the fresh-load default snapshot, and the
-- save/load/diff logic.
--
-- While this scene is active it adds three items to the system menu (see
-- the 3-item cap note in CLAUDE.md -- these three are added in :start() and
-- removed in :finish(), so they only ever compete for the cap with whatever
-- else is active at the same time, never with GameSceneTraining's own two):
--  - "Load Defaults" resets every field below back to its fresh-load value
--    (ConfigTuning.loadDefaults), then shows TuningDiffScene.
--  - "Load Custom" restores the single saved custom slot, if any
--    (ConfigTuning.loadCustom), then shows TuningDiffScene either way.
--  - "Save Custom" writes the current values of every field below to that
--    slot (ConfigTuning.saveCustom), overwriting whatever was saved before.
-- The custom slot persists in playdate.datastore across app relaunches (not
-- just scene transitions), so a player can dial in values, Save Custom, quit
-- to Title (or exit the game entirely), and Load Custom to get them back.
--
-- Rendered via MenuCard (source/scripts/utilities/MenuCard.lua), the same
-- list+description card layout UpgradeTestScene/UpgradeSelectScene/
-- SettingsScene use, with two features MenuCard supports only for this
-- scene's benefit (see MenuCard.lua's header comment): `headerBefore` on the
-- first item of each category inserts that category's name as a
-- non-selectable header line, and `opts.maxVisible` windows the on-screen
-- rows to VISIBLE_ROWS at a time (recentered on the selection every
-- rebuild) so a rebuild never has to lay out all ~90 rows at once. Up/Down
-- move the highlight (wraps); the crank fast-scrolls through the list;
-- Left/Right adjust the highlighted numeric setting; Ⓐ toggles the
-- highlighted boolean setting; Ⓑ returns to SettingsScene.
--
-- See ConfigTuning.lua for what's deliberately left out of ITEMS/CATEGORIES
-- (every Config.ENEMY_*/ConfigEnemy.lua field, Config.EXPLOSION, the display
-- fundamentals, Config.START_SCENE/DEMO_MODE/DEMO_MAX_LEVEL,
-- Config.MUSIC_VOLUME/MUSIC_SONG/MUSIC_ENABLED, and Config.HUD_SHOW_FPS --
-- all covered by SettingsScene instead).

import "scripts/utilities/Config"
import "scripts/utilities/ConfigTuning"
import "scripts/utilities/Utils"
import "scripts/utilities/MenuCard"

local gfx <const> = playdate.graphics

---@class TuningScene : NobleScene
---@field selected integer index into ConfigTuning.ITEMS
---@field crankAccum number leftover crank degrees not yet converted into a row move, see the cranked handler
---@field layout MenuCard.Layout see rebuild()
TuningScene = class("TuningScene").extends(NobleScene) or TuningScene

local scene = nil

-- System-menu items added in :start(), removed in :finish() -- see the file
-- header comment above.
local loadDefaultsMenuItem = nil
local loadCustomMenuItem = nil
local saveCustomMenuItem = nil

-- How many display rows (headers + items) MenuCard lays out at once -- see
-- opts.maxVisible in MenuCard.build.
local VISIBLE_ROWS = 9

-- Local alias -- every reference below used to mean "the CATEGORIES/ITEMS
-- declared in this file"; they now live in ConfigTuning.lua instead (see the
-- file header above), but keeping the short name avoids touching every call
-- site's punctuation.
local ITEMS = ConfigTuning.ITEMS

---@param v number
---@param decimals integer
---@return number
local function roundTo(v, decimals)
	local mult = 10 ^ decimals
	return math.floor(v * mult + 0.5) / mult
end

---@param item ConfigTuning.Item
---@return string
local function formatValue(item)
	if item.type == "boolean" then
		return Config[item.key] and "[x] " or "[ ] "
	end
	return string.format("%." .. item.decimals .. "f", Config[item.key])
end

---@param item ConfigTuning.Item
---@return string
local function formatTitle(item)
	if item.type == "boolean" then
		return formatValue(item) .. item.label
	end
	return item.label .. ": " .. formatValue(item)
end

---@param item ConfigTuning.Item
---@return string
local function formatDescription(item)
	if item.type == "boolean" then
		return "Toggle on or off."
	end
	return "Range: " .. tostring(item.min) .. " to " .. tostring(item.max) .. " (step " .. tostring(item.step) .. ")"
end

---@return MenuCard.Item[]
local function buildMenuItems()
	local items = {}
	for i, item in ipairs(ITEMS) do
		items[i] = {
			title = formatTitle(item),
			description = formatDescription(item),
			headerBefore = item.headerBefore,
		}
	end
	return items
end

---@param ... any
function TuningScene:init(...)
	TuningScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
	self.selected = 1
	self.crankAccum = 0

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.layout must already exist by then.
	self:rebuild()
end

function TuningScene:start()
	TuningScene.super.start(self)
	scene = self

	loadDefaultsMenuItem = playdate.getSystemMenu():addMenuItem("Load Defaults", function()
		ConfigTuning.loadDefaults()
		Noble.transition(TuningDiffScene)
	end)
	loadCustomMenuItem = playdate.getSystemMenu():addMenuItem("Load Custom", function()
		local loaded = ConfigTuning.loadCustom()
		Noble.transition(TuningDiffScene, nil, nil, nil, {
			message = loaded and nil or "No custom save found -- nothing changed.",
		})
	end)
	saveCustomMenuItem = playdate.getSystemMenu():addMenuItem("Save Custom", function()
		ConfigTuning.saveCustom()
	end)
end

function TuningScene:finish()
	TuningScene.super.finish(self)
	if scene == self then scene = nil end

	if loadDefaultsMenuItem then
		playdate.getSystemMenu():removeMenuItem(loadDefaultsMenuItem)
		loadDefaultsMenuItem = nil
	end
	if loadCustomMenuItem then
		playdate.getSystemMenu():removeMenuItem(loadCustomMenuItem)
		loadCustomMenuItem = nil
	end
	if saveCustomMenuItem then
		playdate.getSystemMenu():removeMenuItem(saveCustomMenuItem)
		saveCustomMenuItem = nil
	end
end

function TuningScene:rebuild()
	self.layout = MenuCard.build("Tuning", "Left/Right adjust   Ⓐ toggle   Ⓑ back", buildMenuItems(), self.selected, nil, { maxVisible = VISIBLE_ROWS })
end

---@param delta integer
local function moveSelection(delta)
	if not scene then return end
	local count = #ITEMS
	scene.selected = ((scene.selected - 1 + delta) % count) + 1
	scene:rebuild()
end

---@param delta integer -1 or 1, in units of the row's step
local function adjustValue(delta)
	if not scene then return end
	local item = ITEMS[scene.selected]
	if item.type ~= "number" then return end
	local newValue = roundTo(Config[item.key] + delta * item.step, item.decimals)
	Config[item.key] = Utils.clamp(newValue, item.min, item.max)
	scene:rebuild()
end

local function toggleBoolean()
	if not scene then return end
	local item = ITEMS[scene.selected]
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
	-- Config.MENU_CRANK_DEGREES_PER_ITEM degrees turned, in either direction.
	-- crankAccum carries leftover sub-threshold rotation between calls.
	cranked = function(change)
		if not scene then return end
		scene.crankAccum = scene.crankAccum + change
		while scene.crankAccum >= Config.MENU_CRANK_DEGREES_PER_ITEM do
			moveSelection(1)
			scene.crankAccum = scene.crankAccum - Config.MENU_CRANK_DEGREES_PER_ITEM
		end
		while scene.crankAccum <= -Config.MENU_CRANK_DEGREES_PER_ITEM do
			moveSelection(-1)
			scene.crankAccum = scene.crankAccum + Config.MENU_CRANK_DEGREES_PER_ITEM
		end
	end,
}

function TuningScene:update()
	TuningScene.super.update(self)
	MenuCard.draw(self.layout)
end
