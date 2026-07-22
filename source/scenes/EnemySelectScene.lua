-- EnemySelectScene.lua
-- Reached from GameSceneTraining's "Select Enemy" system-menu item. Lists every
-- type in GameScene.enemyTypes so you can force GameSceneTraining to spawn a
-- specific type on Ⓐ instead of a random one. Styled like UpgradeSelectScene's
-- "select" phase -- rendered via MenuCard (source/scripts/utilities/MenuCard.lua)
-- with the same list-on-the-left/pane-on-the-right card layout, except the
-- right pane is a custom preview (MenuCard's buildDesc hook) showing the
-- highlighted enemy's sprite, health, and movement stats instead of plain
-- text. Up/Down (or the crank) move the highlight, Ⓐ confirms and returns
-- to GameSceneTraining, Ⓑ cancels back without changing the current
-- selection.

import "scripts/config/Config"
import "scripts/utilities/MenuCard"

local gfx <const> = playdate.graphics

---@class EnemySelectScene : NobleScene
---@field selected integer index into GameScene.enemyTypes
---@field layout MenuCard.Layout see rebuild()
---@field crankAccum number leftover crank degrees not yet converted into a selection move, see the cranked handler
EnemySelectScene = class("EnemySelectScene").extends(NobleScene) or EnemySelectScene

local scene = nil

-- One inert instance per GameScene.enemyTypes entry, positioned off at the
-- origin and never updated -- exists purely so the preview pane can read its
-- real stats (Enemy:previewStats) and bake its real body image
-- (Ship:buildBodyImage) instead of duplicating either from Config by hand.
-- Module-level and built lazily (not per-scene-instance) since GameScene.enemyTypes
-- is class-level and unchanging -- every EnemySelectScene visit can share it.
local previews = nil

---@return table[]
local function getPreviews()
	if not previews then
		previews = {}
		for i, EnemyType in ipairs(GameScene.enemyTypes) do
			previews[i] = EnemyType(0, 0, 0)
		end
	end
	return previews
end

-- MenuCard opts.buildDesc callback: draws the selected enemy's body image
-- above its health/speed/accel/turn stats, centered in the description pane.
---@param item MenuCard.Item
---@param index integer
---@param descWidth number
---@param font _Font?
---@return _Image
local function buildEnemyDesc(item, index, descWidth, font)
	local enemy = getPreviews()[index]
	if not enemy.bodyImage then enemy:buildBodyImage() end
	local moveSpeed, accel, turnRate = enemy:previewStats()

	local children = {
		playout.image.new(enemy.bodyImage),
		playout.text.new(string.format("HP: %d", enemy.maxHealth), { font = font }),
		playout.text.new(string.format("Speed: %d", moveSpeed), { font = font }),
		playout.text.new(string.format("Accel: %d", accel), { font = font }),
		playout.text.new(string.format("Turn: %d", turnRate), { font = font }),
	}

	local root = playout.box.new({
		direction = playout.kDirectionVertical,
		spacing = 4,
		padding = 4,
		width = descWidth,
		hAlign = playout.kAlignCenter,
		vAlign = playout.kAlignCenter,
		font = font,
	}, children)

	return playout.tree.new(root):draw()
end

---@return MenuCard.Item[]
local function buildItems()
	local items = {}
	for i, EnemyType in ipairs(GameScene.enemyTypes) do
		items[i] = { title = EnemyType.displayName }
	end
	return items
end

---@param ... any
function EnemySelectScene:init(...)
	EnemySelectScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite

	-- Default to whatever GameSceneTraining currently has selected (nil / random
	-- falls back to the first entry) so reopening the menu shows your last pick.
	self.selected = 1
	for i, EnemyType in ipairs(GameScene.enemyTypes) do
		if EnemyType == GameSceneTraining.selectedEnemyType then
			self.selected = i
			break
		end
	end
	self.crankAccum = 0

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.layout must already exist by then.
	self:rebuild()
end

function EnemySelectScene:start()
	EnemySelectScene.super.start(self)
	scene = self
end

function EnemySelectScene:finish()
	EnemySelectScene.super.finish(self)
	if scene == self then scene = nil end
end

function EnemySelectScene:rebuild()
	self.layout = MenuCard.build("Select Enemy", "Ⓐ select   Ⓑ cancel", buildItems(), self.selected, nil, { buildDesc = buildEnemyDesc })
end

---@param delta integer
local function moveSelection(delta)
	if not scene then return end
	local count = #GameScene.enemyTypes
	scene.selected = ((scene.selected - 1 + delta) % count) + 1
	scene:rebuild()
end

EnemySelectScene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	AButtonDown = function()
		if not scene then return end
		GameSceneTraining.selectedEnemyType = GameScene.enemyTypes[scene.selected]
		Noble.transition(GameSceneTraining)
	end,
	BButtonDown = function()
		if scene then Noble.transition(GameSceneTraining) end
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

function EnemySelectScene:update()
	EnemySelectScene.super.update(self)
	MenuCard.draw(self.layout)
end
