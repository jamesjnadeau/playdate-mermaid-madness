-- SettingsScene.lua
-- Reached from the title screen's "Settings" item. A flat list of settings
-- (HUD toggles -- Config.HUD_SHOW_*, moved here from the system menu so it
-- stays free for scene-specific items, see EnemySelectScene/
-- GameSceneTraining's "Select Enemy"; Sound -- pick a background song out of
-- source/assets/songs and set Config.MUSIC_VOLUME, via MusicPlayer.selectSong
-- -- the same function main.lua's boot default and the system menu's
-- "Music" checkmark use, so all three stay in sync; and Tuning -- a single
-- row that hands off to TuningScene's full debug/tweak menu -- Tuning is no
-- longer reachable directly from the title screen, only through here).
-- Rendered via MenuCard (source/scripts/utilities/MenuCard.lua), the same
-- list+description card layout UpgradeTestScene/UpgradeSelectScene use --
-- the description pane shows what the highlighted row does. Up/Down (or
-- the crank) move the highlight (wraps); Left/Right cycle the song or adjust
-- the volume; Ⓐ toggles a HUD setting or opens Tuning; Ⓑ returns to the
-- title screen.

import "scripts/utilities/Config"
import "scripts/utilities/Utils"
import "scripts/utilities/MusicPlayer"
import "scripts/utilities/MenuCard"

local gfx <const> = playdate.graphics

---@class SettingsScene.Item
---@field type "boolean"|"number"|"song"|"action"
---@field label string
---@field description string shown in MenuCard's description pane when this row is highlighted
---@field key? string Config field this row edits (boolean/number types)
---@field step? number Left/Right increment, for number rows
---@field min? number
---@field max? number
---@field percent? boolean display a number row as a rounded percentage (0-1 -> "NN%") instead of a raw decimal
---@field action? fun() Ⓐ handler, for action rows

---@class SettingsScene : NobleScene
---@field selected integer index into ITEMS
---@field layout MenuCard.Layout see rebuild()
---@field crankAccum number leftover crank degrees not yet converted into a row move, see the cranked handler
SettingsScene = class("SettingsScene").extends(NobleScene) or SettingsScene

local scene = nil

-- The song row cycles a virtual list: index 1 is always "no song", indices
-- 2.. map to MusicPlayer.listSongs()[index - 1]. Config.MUSIC_SONG (nil or a
-- song name) is the source of truth so the choice reads back correctly if
-- this scene is re-entered -- MusicPlayer.selectSong keeps it and actual
-- playback in sync (also used by main.lua's boot default and the
-- system-menu "Music" checkmark, so all three stay consistent).
---@return integer
local function currentSongIndex()
	if not Config.MUSIC_SONG then return 1 end
	for i, name in ipairs(MusicPlayer.listSongs()) do
		if name == Config.MUSIC_SONG then return i + 1 end
	end
	return 1
end

-- Applies the song at virtual index `index` via MusicPlayer.selectSong (nil
-- for "no song", index 1). Playback isn't tied to this scene -- it keeps
-- looping as background music after you leave Settings.
---@param index integer
local function selectSong(index)
	local songs = MusicPlayer.listSongs()
	MusicPlayer.selectSong(index > 1 and songs[index - 1] or nil)
end

---@param v number
---@param decimals integer
---@return number
local function roundTo(v, decimals)
	local mult = 10 ^ decimals
	return math.floor(v * mult + 0.5) / mult
end

-- label + Config field toggled/adjusted by each row, in on-screen order
-- (HUD rows, then Sound rows, then the Tuning row).
local ITEMS = {
	{ type = "boolean", key = "HUD_SHOW_WIND_SPEED", label = "Wind Speed", description = "Show the current wind speed in the HUD." },
	{ type = "boolean", key = "HUD_SHOW_WIND_DIRECTION", label = "Wind Direction", description = "Show the current wind direction in the HUD." },
	{ type = "boolean", key = "HUD_SHOW_PLAYER_SPEED", label = "Player Speed", description = "Show the ship's current speed in the HUD." },
	{ type = "boolean", key = "HUD_SHOW_FPS", label = "FPS Counter", description = "Show a frames-per-second counter in the HUD." },
	{ type = "song", label = "Song", description = "Choose the background music track (or none)." },
	{ type = "number", key = "MUSIC_VOLUME", label = "Volume", step = 0.05, min = 0, max = 1, percent = true, description = "Adjust the background music volume." },
	{ type = "action", label = "Open Tuning Menu", action = function() Noble.transition(TuningScene) end, description = "Open the full debug tuning menu." },
}

---@param item SettingsScene.Item
---@return string
local function formatValue(item)
	if item.type == "number" then
		if item.percent then
			return math.floor(Config[item.key] * 100 + 0.5) .. "%"
		end
		return tostring(Config[item.key])
	elseif item.type == "song" then
		local songs = MusicPlayer.listSongs()
		if #songs == 0 then return "(no songs found)" end
		local idx = currentSongIndex()
		if idx == 1 then return "(none)" end
		return songs[idx - 1]
	end
	return ""
end

---@param item SettingsScene.Item
---@return string
local function formatTitle(item)
	if item.type == "boolean" then
		return (Config[item.key] and "[x] " or "[ ] ") .. item.label
	elseif item.type == "action" then
		return item.label .. " >"
	end
	return item.label .. ": " .. formatValue(item)
end

---@return { title: string, description: string }[]
local function buildMenuItems()
	local items = {}
	for i, item in ipairs(ITEMS) do
		items[i] = { title = formatTitle(item), description = item.description }
	end
	return items
end

---@param ... any
function SettingsScene:init(...)
	SettingsScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
	self.selected = 1
	self.crankAccum = 0

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.layout must already exist by then.
	self:rebuild()
end

function SettingsScene:start()
	SettingsScene.super.start(self)
	scene = self
end

function SettingsScene:finish()
	SettingsScene.super.finish(self)
	if scene == self then scene = nil end
end

function SettingsScene:rebuild()
	self.layout = MenuCard.build("Settings", "Left/Right adjust   Ⓐ toggle/open   Ⓑ back", buildMenuItems(), self.selected)
end

---@param delta integer
local function moveSelection(delta)
	if not scene then return end
	local count = #ITEMS
	scene.selected = ((scene.selected - 1 + delta) % count) + 1
	scene:rebuild()
end

---@param delta integer -1 or 1
local function adjustValue(delta)
	if not scene then return end
	local item = ITEMS[scene.selected]
	if item.type == "number" then
		Config[item.key] = Utils.clamp(roundTo(Config[item.key] + delta * item.step, 2), item.min, item.max)
		if item.key == "MUSIC_VOLUME" then
			MusicPlayer.applyVolume()
		end
		scene:rebuild()
	elseif item.type == "song" then
		local songCount = #MusicPlayer.listSongs()
		if songCount == 0 then return end
		selectSong(((currentSongIndex() - 1 + delta) % (songCount + 1)) + 1)
		scene:rebuild()
	end
end

local function activate()
	if not scene then return end
	local item = ITEMS[scene.selected]
	if item.type == "boolean" then
		Config[item.key] = not Config[item.key]
		if item.key == "HUD_SHOW_FPS" then
			-- Noble's own update loop checks Noble.showFPS, not Config directly
			-- (unlike the other HUD_SHOW_* fields) -- see Noble.lua's showFPS field.
			Noble.showFPS = Config.HUD_SHOW_FPS
		end
		scene:rebuild()
	elseif item.type == "action" then
		item.action()
	end
end

SettingsScene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	leftButtonDown = function() adjustValue(-1) end,
	rightButtonDown = function() adjustValue(1) end,
	AButtonDown = function() activate() end,
	BButtonDown = function()
		if scene then Noble.transition(TitleScene) end
	end,
	-- Same fast-scroll idea as TuningScene.lua: the crank moves the
	-- highlight one item per Config.MENU_CRANK_DEGREES_PER_ITEM degrees
	-- turned, in either direction. crankAccum carries leftover sub-threshold
	-- rotation between calls.
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

function SettingsScene:update()
	SettingsScene.super.update(self)
	MenuCard.draw(self.layout)
end
