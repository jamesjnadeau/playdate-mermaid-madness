-- TitleScene.lua
-- Start screen: Up/Down pick a scene, A confirms. Rendered with the playout
-- UI library, see libraries/playout.lua.

import "scripts/utilities/Config"

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

-- Ease-out-back: eases toward 1 but overshoots past it first before settling
-- back -- used for the menu's rise-in below so it crests up past its resting
-- position and settles down, like a wave washing up the shore rather than a
-- mechanical slide. Standard cubic-with-overshoot coefficients (c1 = 1.70158).
---@param t number 0-1
---@return number eased, >1 during the overshoot, exactly 1 at t=1
local function easeOutBack(t)
	local c1 = 1.70158
	local c3 = c1 + 1
	local inv = t - 1
	return 1 + c3 * inv * inv * inv + c1 * inv * inv
end

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
		-- playout.text.new("Zeus and Posiden use you to dual.", { alignment = kTextAlignment.center }),
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
		-- Config.DEMO_MODE (off by default) swaps in the level-capped
		-- GameSceneDemo for a trade-show/kiosk build -- see Config.lua.
		Noble.transition(Config.DEMO_MODE and GameSceneDemo or GameSceneMain)
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
	local restY = (Config.SCREEN_H - img.height) / 2

	-- Hidden below the screen until TITLE_MENU_DELAY elapses, then rises to
	-- restY over TITLE_MENU_RISE_DURATION seconds. progress <= 0 (still
	-- waiting out the delay) clamps to y = SCREEN_H, i.e. fully offscreen.
	local progress = Utils.clamp((self.t - Config.TITLE_MENU_DELAY) / Config.TITLE_MENU_RISE_DURATION, 0, 1)
	local y = Config.SCREEN_H - (Config.SCREEN_H - restY) * easeOutBack(progress)
	img:draw(x, y)
end
