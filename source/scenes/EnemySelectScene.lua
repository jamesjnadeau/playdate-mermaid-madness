-- EnemySelectScene.lua
-- Reached from GameSceneTraining's "Select Enemy" system-menu item. Lists every
-- type in GameScene.enemyTypes (rendered with the playout UI library, see
-- libraries/playout.lua) so you can force GameSceneTraining to spawn a specific
-- type on Ⓐ instead of a random one. Up/Down (or the crank) move the
-- highlight, Ⓐ confirms and returns to GameSceneTraining, Ⓑ cancels back
-- without changing the current selection.

import "scripts/utilities/Config"

local gfx <const> = playdate.graphics

---@class EnemySelectScene : NobleScene
---@field selected integer index into GameScene.enemyTypes
---@field tree table playout tree, see rebuild()
---@field img _Image drawn image of the playout tree, see rebuild()
---@field crankAccum number leftover crank degrees not yet converted into a selection move, see the cranked handler
EnemySelectScene = class("EnemySelectScene").extends(NobleScene) or EnemySelectScene

local scene = nil

-- Degrees of crank rotation that moves the highlight by one item, same idea
-- (and same threshold) as TuningScene.lua's CRANK_DEGREES_PER_ROW.
local CRANK_DEGREES_PER_ITEM = 20

-- Builds a fresh playout tree highlighting `selectedIndex`. Rebuilt (rather
-- than mutated in place) whenever the selection changes -- the list is tiny
-- so this stays cheap and keeps the highlight logic in one place.
---@param selectedIndex integer
---@return table playout tree
local function buildTree(selectedIndex)
	local children = {
		playout.text.new("Select Enemy"),
	}
	for i, EnemyType in ipairs(GameScene.enemyTypes) do
		local isSelected = i == selectedIndex
		children[#children + 1] = playout.box.new({
			padding = 4,
			hAlign = playout.kAlignStart,
			backgroundColor = isSelected and gfx.kColorBlack or nil,
		}, {
			playout.text.new(EnemyType.displayName, {
				color = isSelected and gfx.kColorWhite or gfx.kColorBlack,
			}),
		})
	end
	children[#children + 1] = playout.text.new("Ⓐ select   Ⓑ cancel")

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
	-- init/start comments), so self.img must already exist by then.
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
	self.tree = buildTree(self.selected)
	self.img = self.tree:draw()
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
	-- highlight one item per CRANK_DEGREES_PER_ITEM degrees turned, in
	-- either direction. crankAccum carries leftover sub-threshold rotation
	-- between calls.
	cranked = function(change)
		if not scene then return end
		scene.crankAccum = scene.crankAccum + change
		while scene.crankAccum >= CRANK_DEGREES_PER_ITEM do
			moveSelection(1)
			scene.crankAccum = scene.crankAccum - CRANK_DEGREES_PER_ITEM
		end
		while scene.crankAccum <= -CRANK_DEGREES_PER_ITEM do
			moveSelection(-1)
			scene.crankAccum = scene.crankAccum + CRANK_DEGREES_PER_ITEM
		end
	end,
}

function EnemySelectScene:update()
	EnemySelectScene.super.update(self)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	local x = (Config.SCREEN_W - self.img.width) / 2
	local y = (Config.SCREEN_H - self.img.height) / 2
	self.img:draw(x, y)
end
