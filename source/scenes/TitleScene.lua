-- TitleScene.lua
-- Start screen: Up/Down pick a scene, A confirms. Rendered with the playout
-- UI library, see libraries/playout.lua.

import "scripts/Config"

local gfx <const> = playdate.graphics

---@class TitleScene : NobleScene
---@field t number seconds elapsed, drives the blinking "Ⓐ to select" prompt
---@field selected integer index into MENU_ITEMS
TitleScene = class("TitleScene").extends(NobleScene) or TitleScene

local scene = nil

-- Splash art, full-screen background behind the menu. Pre-dithered at
-- 400x240 (see art-src/title-hero.png for the hi-res original) so pdc's
-- 1-bit conversion happens at the resolution it's actually shown at.
local heroImage = gfx.image.new("assets/images/title-hero")

-- Menu labels, in order. Kept as plain display strings -- the scene classes
-- themselves are only referenced inside confirmSelection() below, which runs
-- long after every scene file has finished loading, so load order here
-- doesn't matter.
local MENU_ITEMS = { "Play", "Training", "Instructions", "Settings" }

-- Rebuilt every frame from :update() -- the blinking prompt needs to redraw
-- regardless of whether the selection changed, and the tree is tiny enough
-- that rebuilding it outright is simpler than diffing what changed.
---@param selected integer
---@param showPrompt boolean
---@return table playout tree
local function buildTree(selected, showPrompt)
	local menuChildren = {}
	for i, label in ipairs(MENU_ITEMS) do
		local text = (i == selected) and ("> " .. label .. " <") or label
		menuChildren[i] = playout.text.new(text, { alignment = kTextAlignment.center })
	end

	local root = playout.box.new({
		direction = playout.kDirectionVertical,
		spacing = 14,
		padding = 20,
		hAlign = playout.kAlignCenter,
		-- Opaque card (rather than drawing straight over the art) so the menu
		-- text stays legible regardless of what's dithered underneath it.
		backgroundColor = gfx.kColorWhite,
		border = 2,
		borderRadius = 6,
	}, {
		playout.text.new("* Mermaid Madness *", { alignment = kTextAlignment.center }),
		playout.text.new("a Playdate pirate voyage", { alignment = kTextAlignment.center }),
		playout.box.new({ direction = playout.kDirectionVertical, spacing = 4 }, menuChildren),
		-- Toggling color (rather than adding/removing this node) keeps the
		-- blink from shifting the rest of the layout.
		playout.text.new("Ⓐ to select", {
			alignment = kTextAlignment.center,
			color = showPrompt and gfx.kColorBlack or gfx.kColorWhite,
		}),
	})

	return playout.tree.new(root)
end

---@param ... any
function TitleScene:init(...)
	TitleScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
	self.t = 0
	self.selected = 2
end

function TitleScene:start()
	TitleScene.super.start(self)
	scene = self
end

function TitleScene:finish()
	TitleScene.super.finish(self)
	scene = nil
end

local function confirmSelection()
	if not scene then return end
	if scene.selected == 1 then
		Noble.transition(GameSceneMain)
	elseif scene.selected == 2 then
		Noble.transition(GameSceneTraining)
	elseif scene.selected == 3 then
		Noble.transition(InstructionsScene)
	else
		Noble.transition(SettingsScene)
	end
end

TitleScene.inputHandler = {
	upButtonDown = function()
		if not scene then return end
		scene.selected = scene.selected - 1
		if scene.selected < 1 then scene.selected = #MENU_ITEMS end
	end,
	downButtonDown = function()
		if not scene then return end
		scene.selected = scene.selected + 1
		if scene.selected > #MENU_ITEMS then scene.selected = 1 end
	end,
	AButtonDown = function() confirmSelection() end,
}

function TitleScene:update()
	TitleScene.super.update(self)
	self.t = self.t + Config.DT

	local showPrompt = math.floor(self.t * 2) % 2 == 0
	local img = buildTree(self.selected, showPrompt):draw()

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	heroImage:draw(0, 0)
	local x = (Config.SCREEN_W - img.width) / 2
	local y = (Config.SCREEN_H - img.height) / 2
	img:draw(x, y)
end
