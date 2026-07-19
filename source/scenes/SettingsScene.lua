-- SettingsScene.lua
-- Reached from the title screen's "Settings" item. Three sections in one
-- scrollless list (it's short enough not to need TuningScene's scroll
-- window): HUD toggles (Config.HUD_SHOW_*, moved here from the system menu
-- so it stays free for scene-specific items -- see EnemySelectScene/
-- GameSceneTraining's "Select Enemy"), Sound (pick a background song out of
-- source/assets/songs and set Config.MUSIC_VOLUME, via MusicPlayer.selectSong
-- -- the same function main.lua's boot default and the system menu's
-- "Music" checkmark use, so all three stay in sync), and Tuning (a single
-- row that hands off to TuningScene's full debug/tweak menu -- Tuning is no
-- longer reachable directly from the title screen, only through here).
-- Built with the playout UI library, see libraries/playout.lua. Up/Down
-- move the highlight (wraps); Left/Right cycle the song or adjust the
-- volume; Ⓐ toggles a HUD setting or opens Tuning; Ⓑ returns to the title
-- screen.

import "scripts/Config"
import "scripts/Utils"
import "scripts/MusicPlayer"

local gfx <const> = playdate.graphics

---@class SettingsScene.Item
---@field type "boolean"|"number"|"song"|"action"
---@field label string
---@field key? string Config field this row edits (boolean/number types)
---@field step? number Left/Right increment, for number rows
---@field min? number
---@field max? number
---@field percent? boolean display a number row as a rounded percentage (0-1 -> "NN%") instead of a raw decimal
---@field action? fun() Ⓐ handler, for action rows

---@class SettingsScene : NobleScene
---@field selected integer index into SETTING_ROWS
---@field tree table playout tree, see rebuild()
---@field img _Image drawn image of the playout tree, see rebuild()
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

-- label + Config field toggled/adjusted by each row, grouped into the three
-- sections described in the file header above.
local CATEGORIES = {
	{ name = "HUD", items = {
		{ type = "boolean", key = "HUD_SHOW_WIND_SPEED", label = "Wind Speed" },
		{ type = "boolean", key = "HUD_SHOW_WIND_DIRECTION", label = "Wind Direction" },
		{ type = "boolean", key = "HUD_SHOW_PLAYER_SPEED", label = "Player Speed" },
		{ type = "boolean", key = "HUD_SHOW_FPS", label = "FPS Counter" },
	} },
	{ name = "Sound", items = {
		{ type = "song", label = "Song" },
		{ type = "number", key = "MUSIC_VOLUME", label = "Volume", step = 0.05, min = 0, max = 1, percent = true },
	} },
	{ name = "Tuning", items = {
		{ type = "action", label = "Open Tuning Menu", action = function() Noble.transition(TuningScene) end },
	} },
}

-- Flattened once at load time, same split as TuningScene: ROWS is every row
-- in on-screen order (category headers + settings), SETTING_ROWS is just
-- the selectable subset that moveSelection/adjustValue/activate index into.
local ROWS = {}
local SETTING_ROWS = {}
for _, category in ipairs(CATEGORIES) do
	ROWS[#ROWS + 1] = { kind = "header", label = category.name }
	for _, item in ipairs(category.items) do
		ROWS[#ROWS + 1] = { kind = "setting", item = item }
		SETTING_ROWS[#SETTING_ROWS + 1] = item
	end
end

---@param item SettingsScene.Item
---@return string
local function formatValue(item)
	if item.type == "boolean" then
		return Config[item.key] and "[x] " or "[ ] "
	elseif item.type == "number" then
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

-- Builds a fresh playout tree highlighting `selectedIndex` (into
-- SETTING_ROWS). Rebuilt (rather than mutated in place) whenever the
-- selection or a setting changes, same as TuningScene/EnemySelectScene.
---@param selectedIndex integer
---@return table playout tree
local function buildTree(selectedIndex)
	local currentItem = SETTING_ROWS[selectedIndex]
	local children = {
		playout.text.new("Settings"),
	}
	for _, row in ipairs(ROWS) do
		if row.kind == "header" then
			children[#children + 1] = playout.text.new(row.label)
		else
			local item = row.item
			local isSelected = item == currentItem
			local text
			if item.type == "boolean" then
				text = formatValue(item) .. item.label
			elseif item.type == "action" then
				text = item.label .. " >"
			else
				text = item.label .. ": " .. formatValue(item)
			end
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
	children[#children + 1] = playout.text.new("Left/Right adjust  Ⓐ toggle/open  Ⓑ back")

	local root = playout.box.new({
		direction = playout.kDirectionVertical,
		spacing = 6,
		padding = 10,
		hAlign = playout.kAlignCenter,
		backgroundColor = gfx.kColorWhite,
		border = 2,
		borderRadius = 6,
	}, children)

	return playout.tree.new(root)
end

---@param ... any
function SettingsScene:init(...)
	SettingsScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
	self.selected = 1

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.img must already exist by then.
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

---@param delta integer -1 or 1
local function adjustValue(delta)
	if not scene then return end
	local item = SETTING_ROWS[scene.selected]
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
	local item = SETTING_ROWS[scene.selected]
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
}

function SettingsScene:update()
	SettingsScene.super.update(self)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	local x = (Config.SCREEN_W - self.img.width) / 2
	local y = (Config.SCREEN_H - self.img.height) / 2
	self.img:draw(x, y)
end
