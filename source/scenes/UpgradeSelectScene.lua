-- UpgradeSelectScene.lua
-- Reached from LevelCompleteScene after clearing a level. Offers 3 randomly
-- drawn entries from Config.UPGRADES (see ConfigUpgrades.lua) rendered with
-- the playout UI library (see libraries/playout.lua) -- the same
-- rebuild-on-change list pattern as EnemySelectScene/SettingsScene, plus a
-- description of the highlighted upgrade. Up/Down move the highlight, Ⓐ
-- applies the highlighted upgrade (via Config.applyUpgrade) and swaps to a
-- before/after summary; a second Ⓐ continues on to WindShiftScene or
-- straight back to self.gameScene (see GameSceneMain.gameSceneClass),
-- mirroring LevelCompleteScene's own transition logic.

import "scripts/Config"
import "scripts/ConfigUpgrades"

local gfx <const> = playdate.graphics

-- Text styling for this scene's menu -- change this to switch fonts (size
-- and style come bundled together, since a font file is both). Any of
-- Noble.Text.FONT_SYSTEM/FONT_SMALL/FONT_MEDIUM/FONT_LARGE work, or load a
-- custom one via gfx.font.new(path). nil falls back to whatever font is
-- currently set globally (the Playdate system font, unless another scene
-- changed it).
local MENU_FONT = nil

---@class UpgradeSelectScene : NobleScene
---@field level integer
---@field completedLevel integer
---@field totalDefeated integer
---@field gameScene table class table (GameSceneMain or a subclass, e.g. GameSceneDemo) to eventually return to -- see GameSceneMain.gameSceneClass
---@field upgrades Config.Upgrade[] this round's 3 random picks
---@field selected integer index into self.upgrades
---@field phase string "select" | "result"
---@field tree table playout tree, see rebuild()
---@field img _Image drawn image of the playout tree, see rebuild()
---@field upgrade Config.Upgrade set once phase == "result"
---@field oldValue number set once phase == "result"
---@field newValue number set once phase == "result"
UpgradeSelectScene = class("UpgradeSelectScene").extends(NobleScene) or UpgradeSelectScene

local scene = nil

-- Draws `count` distinct entries from Config.UPGRADES without replacement
-- (falls back to fewer if the pool is smaller than `count`). Entries with an
-- `available` predicate (e.g. "Rapid Autocannon" requiring the Autofire
-- Cannon already be installed) are skipped unless it currently returns true.
---@param count integer
---@return Config.Upgrade[]
local function pickUpgrades(count)
	local pool = {}
	for _, upgrade in ipairs(Config.UPGRADES) do
		if upgrade.available == nil or upgrade.available() then
			pool[#pool + 1] = upgrade
		end
	end
	local picks = {}
	for i = 1, math.min(count, #pool) do
		local idx = math.random(#pool)
		picks[#picks + 1] = table.remove(pool, idx)
	end
	return picks
end

-- Selection screen: list of upgrade titles (highlighted row = black
-- background/white text, same as EnemySelectScene/SettingsScene) plus the
-- description of whichever one is currently highlighted.
---@param selectedIndex integer
---@param upgrades Config.Upgrade[]
---@return table playout tree
local function buildSelectTree(selectedIndex, upgrades)
	local children = {
		playout.text.new("Choose an Upgrade"),
	}
	for i, upgrade in ipairs(upgrades) do
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
	children[#children + 1] = playout.text.new(upgrades[selectedIndex].description, {
		alignment = kTextAlignment.center,
	})
	children[#children + 1] = playout.text.new("Ⓐ select")

	local root = playout.box.new({
		direction = playout.kDirectionVertical,
		spacing = 8,
		padding = 10,
		hAlign = playout.kAlignCenter,
		maxWidth = 340,
		backgroundColor = gfx.kColorWhite,
		font = MENU_FONT,
	}, children)

	return playout.tree.new(root)
end

-- Result screen: the chosen upgrade's title plus a before/after readout of
-- the stat it touched.
---@param upgrade Config.Upgrade
---@param oldValue number
---@param newValue number
---@return table playout tree
local function buildResultTree(upgrade, oldValue, newValue)
	local children = {
		playout.text.new(upgrade.title .. "!"),
		playout.text.new("Was: " .. upgrade.format(oldValue)),
		playout.text.new("Now: " .. upgrade.format(newValue)),
		playout.text.new("Ⓐ continue"),
	}

	local root = playout.box.new({
		direction = playout.kDirectionVertical,
		spacing = 8,
		padding = 10,
		hAlign = playout.kAlignCenter,
		maxWidth = 340,
		backgroundColor = gfx.kColorWhite,
		font = MENU_FONT,
	}, children)

	return playout.tree.new(root)
end

---@param sceneProperties? table
function UpgradeSelectScene:init(sceneProperties)
	UpgradeSelectScene.super.init(self, sceneProperties)
	self.backgroundColor = gfx.kColorWhite
	sceneProperties = sceneProperties or {}
	self.level = sceneProperties.level or 1
	self.completedLevel = sceneProperties.completedLevel or (self.level - 1)
	self.totalDefeated = sceneProperties.totalDefeated or 0
	self.gameScene = sceneProperties.gameScene or GameSceneMain

	self.upgrades = pickUpgrades(3)
	self.selected = 1
	self.phase = "select" -- "select" -> "result"

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.img must already exist by then.
	self:rebuild()
end

function UpgradeSelectScene:start()
	UpgradeSelectScene.super.start(self)
	scene = self
end

function UpgradeSelectScene:finish()
	UpgradeSelectScene.super.finish(self)
	if scene == self then scene = nil end
end

function UpgradeSelectScene:rebuild()
	if self.phase == "select" then
		self.tree = buildSelectTree(self.selected, self.upgrades)
	else
		self.tree = buildResultTree(self.upgrade, self.oldValue, self.newValue)
	end
	self.img = self.tree:draw()
end

---@param delta integer
local function moveSelection(delta)
	if not scene or scene.phase ~= "select" then return end
	local count = #scene.upgrades
	scene.selected = ((scene.selected - 1 + delta) % count) + 1
	scene:rebuild()
end

UpgradeSelectScene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	AButtonDown = function()
		if not scene then return end
		if scene.phase == "select" then
			local upgrade = scene.upgrades[scene.selected]
			local oldValue, newValue = Config.applyUpgrade(upgrade)
			scene.upgrade = upgrade
			scene.oldValue = oldValue
			scene.newValue = newValue
			scene.phase = "result"
			scene:rebuild()
		else
			local windStepped = GameSceneMain.windStepForLevel(scene.level)
				> GameSceneMain.windStepForLevel(scene.completedLevel)
			local nextScene = windStepped and WindShiftScene or scene.gameScene
			Noble.transition(nextScene, nil, nil, nil, {
				level = scene.level,
				totalDefeated = scene.totalDefeated,
				gameScene = scene.gameScene,
			})
		end
	end,
}

function UpgradeSelectScene:update()
	UpgradeSelectScene.super.update(self)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	local x = (Config.SCREEN_W - self.img.width) / 2
	local y = (Config.SCREEN_H - self.img.height) / 2
	self.img:draw(x, y)
end
