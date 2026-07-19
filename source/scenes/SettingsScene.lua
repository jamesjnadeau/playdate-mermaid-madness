-- SettingsScene.lua
-- Reached from the title screen's "Settings" item. Lets you toggle the HUD
-- visibility flags (Config.HUD_SHOW_*) that used to live as checkmark items
-- in the system menu -- moved here so the system menu is free for
-- scene-specific items like GameSceneTest's "Select Enemy" (it caps out at
-- 3 custom items total). Built with the playout UI library, see
-- libraries/playout.lua. Up/Down move the highlight, Ⓐ toggles the
-- highlighted setting, Ⓑ returns to the title screen.

import "scripts/Config"

local gfx <const> = playdate.graphics

---@class SettingsScene : NobleScene
---@field selected integer index into SETTINGS
---@field tree table playout tree, see rebuild()
---@field img _Image drawn image of the playout tree, see rebuild()
SettingsScene = class("SettingsScene").extends(NobleScene) or SettingsScene

local scene = nil

-- label + Config field toggled by each row. Add an entry here to expose a
-- new HUD_SHOW_* (or other boolean Config) flag in this menu.
local SETTINGS = {
	{ label = "Wind Speed", key = "HUD_SHOW_WIND_SPEED" },
	{ label = "Wind Direction", key = "HUD_SHOW_WIND_DIRECTION" },
	{ label = "Player Speed", key = "HUD_SHOW_PLAYER_SPEED" },
}

-- Builds a fresh playout tree highlighting `selectedIndex`. Rebuilt (rather
-- than mutated in place) whenever the selection or a setting changes -- the
-- list is tiny so this stays cheap and keeps the highlight/checkbox logic in
-- one place.
---@param selectedIndex integer
---@return table playout tree
local function buildTree(selectedIndex)
	local children = {
		playout.text.new("Settings"),
	}
	for i, setting in ipairs(SETTINGS) do
		local isSelected = i == selectedIndex
		local checkbox = Config[setting.key] and "[x]" or "[ ]"
		children[#children + 1] = playout.box.new({
			padding = 4,
			spacing = 8,
			direction = playout.kDirectionHorizontal,
			hAlign = playout.kAlignStart,
			backgroundColor = isSelected and gfx.kColorBlack or nil,
		}, {
			playout.text.new(checkbox, {
				color = isSelected and gfx.kColorWhite or gfx.kColorBlack,
			}),
			playout.text.new(setting.label, {
				color = isSelected and gfx.kColorWhite or gfx.kColorBlack,
			}),
		})
	end
	children[#children + 1] = playout.text.new("Ⓐ toggle   Ⓑ back")

	local root = playout.box.new({
		direction = playout.kDirectionVertical,
		spacing = 8,
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
	local count = #SETTINGS
	scene.selected = ((scene.selected - 1 + delta) % count) + 1
	scene:rebuild()
end

SettingsScene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	AButtonDown = function()
		if not scene then return end
		local setting = SETTINGS[scene.selected]
		Config[setting.key] = not Config[setting.key]
		scene:rebuild()
	end,
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
