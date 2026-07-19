-- UpgradeTestScene.lua
-- Reached from GameSceneTraining's "Test Upgrade" system-menu item. Lists
-- every entry in Config.UPGRADES (source/scripts/ConfigUpgrades.lua) --
-- unlike UpgradeSelectScene's random draw of 3, the whole pool, and unlike
-- UpgradeSelectScene's pickUpgrades, ignoring each entry's `available`
-- predicate (e.g. "Rapid Autocannon" normally requires the Autofire Cannon
-- already installed) -- this is a dev/test tool, so every upgrade is always
-- reachable here regardless of prerequisites. Up/Down move the highlight, Ⓐ
-- applies the highlighted upgrade (via Config.applyUpgrade, same as
-- UpgradeSelectScene) and returns to GameSceneTraining, Ⓑ cancels back
-- without applying anything. No before/after result screen -- unlike
-- UpgradeSelectScene, this is meant to be reopened repeatedly to stack
-- several picks in a row, so it goes straight back to the sandbox instead of
-- pausing on a summary each time.

import "scripts/Config"
import "scripts/ConfigUpgrades"

local gfx <const> = playdate.graphics

---@class UpgradeTestScene : NobleScene
---@field selected integer index into Config.UPGRADES
---@field tree table playout tree, see rebuild()
---@field img _Image drawn image of the playout tree, see rebuild()
UpgradeTestScene = class("UpgradeTestScene").extends(NobleScene) or UpgradeTestScene

local scene = nil

-- Builds a fresh playout tree highlighting `selectedIndex`. Rebuilt (rather
-- than mutated in place) whenever the selection changes -- the list is tiny
-- so this stays cheap and keeps the highlight logic in one place.
---@param selectedIndex integer
---@return table playout tree
local function buildTree(selectedIndex)
	local children = {
		playout.text.new("Test Upgrade"),
	}
	for i, upgrade in ipairs(Config.UPGRADES) do
		local isSelected = i == selectedIndex
		children[#children + 1] = playout.box.new({
			padding = 4,
			hAlign = playout.kAlignStart,
			backgroundColor = isSelected and gfx.kColorBlack or nil,
		}, {
			playout.text.new(upgrade.title, {
				color = isSelected and gfx.kColorWhite or gfx.kColorBlack,
			}),
		})
	end
	children[#children + 1] = playout.text.new(Config.UPGRADES[selectedIndex].description, {
		alignment = kTextAlignment.center,
	})
	children[#children + 1] = playout.text.new("Ⓐ apply   Ⓑ cancel")

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
function UpgradeTestScene:init(...)
	UpgradeTestScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
	self.selected = 1

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.img must already exist by then.
	self:rebuild()
end

function UpgradeTestScene:start()
	UpgradeTestScene.super.start(self)
	scene = self
end

function UpgradeTestScene:finish()
	UpgradeTestScene.super.finish(self)
	if scene == self then scene = nil end
end

function UpgradeTestScene:rebuild()
	self.tree = buildTree(self.selected)
	self.img = self.tree:draw()
end

---@param delta integer
local function moveSelection(delta)
	if not scene then return end
	local count = #Config.UPGRADES
	scene.selected = ((scene.selected - 1 + delta) % count) + 1
	scene:rebuild()
end

UpgradeTestScene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	AButtonDown = function()
		if not scene then return end
		Config.applyUpgrade(Config.UPGRADES[scene.selected])
		Noble.transition(GameSceneTraining)
	end,
	BButtonDown = function()
		if scene then Noble.transition(GameSceneTraining) end
	end,
}

function UpgradeTestScene:update()
	UpgradeTestScene.super.update(self)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	local x = (Config.SCREEN_W - self.img.width) / 2
	local y = (Config.SCREEN_H - self.img.height) / 2
	self.img:draw(x, y)
end
