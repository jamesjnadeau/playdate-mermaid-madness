-- TitleScene.lua
-- Start screen: Up/Down (or the crank) pick a scene, A or B confirms.
-- Rendered with the playout UI library, see libraries/playout.lua.

import "scripts/utilities/Config"
import "scripts/utilities/Sound"

local gfx <const> = playdate.graphics

---@class TitleScene : NobleScene
---@field t number seconds elapsed, drives the TITLE_MENU_DELAY/lightning timing
---@field selected integer index into MENU_ITEMS
---@field menuImg _Image drawn image of the menu card for the current selection, see rebuildMenu()
---@field crankAccum number leftover crank degrees not yet converted into a menu move, see the cranked handler
TitleScene = class("TitleScene").extends(NobleScene) or TitleScene

local scene = nil

-- Module-scope (not a self.* field): Noble.transition(TitleScene) builds a
-- brand-new TitleScene instance -- and so re-runs :init() -- every time the
-- title screen is revisited, but this file is only ever loaded once per game
-- session. Tracking the "has the crack played yet" flag here instead of on
-- self means it stays true for the rest of the session once set, so the
-- lightning only plays the first time the title screen appears, not every
-- time the player backs out to it.
local lightningPlayedThisSession = false

-- Gap between the menu card and the bottom/left screen edges.
local TITLE_MENU_MARGIN = 12

-- Splash art, full-screen background behind the menu. Pre-dithered at
-- 400x240 (see art-src/title-hero.png for the hi-res original) so pdc's
-- 1-bit conversion happens at the resolution it's actually shown at.
local heroImage = gfx.image.new("assets/images/title-hero")

-- Menu labels, in order. Kept as plain display strings -- the scene classes
-- themselves are only referenced inside confirmSelection() below, which runs
-- long after every scene file has finished loading, so load order here
-- doesn't matter.
local MENU_ITEMS = { "Play", "Training", "Instructions", "Settings" }

-- Bolt flanking the selected item. Playdate's built-in system font has no
-- glyph for "⚡" itself -- a plain text decoration silently drops the
-- character -- so this is a pre-rendered image instead; see
-- tools/render-lightning-icon.sh for how it's generated.
local lightningIcon = gfx.image.new("assets/images/lightning-icon")
assert(lightningIcon, "missing assets/images/lightning-icon")
local ICON_W, ICON_H = lightningIcon.width, lightningIcon.height

-- Every row gets an icon-sized slot on each side of its label, whether or
-- not that row is selected (a same-size empty box standing in for the icon
-- when it's not) -- see buildRow() below. That keeps each row's width/height
-- contribution from the flanks constant across selection changes, so the
-- card never resizes as the highlight moves, even onto/off of the widest
-- item.
---@return table playout node
local function iconSlot()
	return playout.box.new({ width = ICON_W, height = ICON_H })
end

---@param label string
---@param isSelected boolean
---@return table playout node
local function buildRow(label, isSelected)
	local leftIcon = isSelected and playout.image.new(lightningIcon) or iconSlot()
	local rightIcon = isSelected and playout.image.new(lightningIcon) or iconSlot()
	return playout.box.new({ direction = playout.kDirectionHorizontal, spacing = 4 }, {
		leftIcon,
		playout.text.new(label, { alignment = kTextAlignment.center }),
		rightIcon,
	})
end

-- Only depends on `selected`, so it's rebuilt on demand (see rebuildMenu())
-- rather than every :update() frame -- nothing about the card changes
-- frame-to-frame.
---@param selected integer
---@return table playout tree
local function buildTree(selected)
	local menuChildren = {}
	for i, label in ipairs(MENU_ITEMS) do
		menuChildren[i] = buildRow(label, i == selected)
	end

	local root = playout.box.new({
		direction = playout.kDirectionVertical,
		spacing = 20,
		padding = 20,
		hAlign = playout.kAlignCenter,
		-- Opaque card (rather than drawing straight over the art) so the menu
		-- text stays legible regardless of what's dithered underneath it.
		backgroundColor = gfx.kColorWhite,
		border = 2,
		borderRadius = 6,
	}, {
		--output menu
		playout.box.new({ direction = playout.kDirectionVertical, spacing = 4 }, menuChildren),
	})

	return playout.tree.new(root)
end

---@param ... any
function TitleScene:init(...)
	TitleScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
	self.t = 0
	self.selected = 2
	self.crankAccum = 0
	self:rebuildMenu()
end

-- Redraws the menu card image for the current selection. Only needs calling
-- when self.selected changes (see the input handlers below) -- :update()
-- just draws the cached self.menuImg every frame.
function TitleScene:rebuildMenu()
	self.menuImg = buildTree(self.selected):draw()
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

---@param delta integer
local function moveSelection(delta)
	if not scene then return end
	scene.selected = ((scene.selected - 1 + delta) % #MENU_ITEMS) + 1
	scene:rebuildMenu()
end

TitleScene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	AButtonDown = function() confirmSelection() end,
	BButtonDown = function() confirmSelection() end,
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

function TitleScene:update()
	TitleScene.super.update(self)
	self.t = self.t + Config.DT

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	heroImage:draw(0, 0)

	-- Hidden entirely until TITLE_MENU_DELAY elapses (letting the splash art
	-- sit alone for a beat), then just appears in place -- no rise/slide. A
	-- lightning crack plays the instant it first appears -- but only the
	-- first time this game session, see lightningPlayedThisSession above.
	if self.t < Config.TITLE_MENU_DELAY then return end
	if not lightningPlayedThisSession then
		Sound.playLightning()
		lightningPlayedThisSession = true
	end

	local img = self.menuImg
	local x = TITLE_MENU_MARGIN
	local y = Config.SCREEN_H - img.height - TITLE_MENU_MARGIN
	img:draw(x, y)
end
