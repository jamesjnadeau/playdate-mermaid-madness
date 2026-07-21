-- UpgradeSelectScene.lua
-- Reached from LevelCompleteScene after clearing a level. Offers 3 randomly
-- drawn entries from Config.UPGRADES (see ConfigUpgrades.lua). The "select"
-- phase (list of titles + description of whichever is highlighted) is
-- rendered via MenuCard (source/scripts/utilities/MenuCard.lua), the same
-- list+description card layout UpgradeTestScene uses; the "confirm" phase
-- (before/after preview once Ⓐ is pressed) is its own simple centered
-- playout tree, since it has no list to lay out. Up/Down (or the crank,
-- while in the "select" phase) move the highlight, Ⓐ previews the
-- highlighted upgrade (via Config.previewUpgrade, which doesn't touch
-- Config) and swaps to the before/after screen; from there Ⓐ commits it
-- (via Config.applyUpgrade) and continues on to WindShiftScene or straight
-- back to self.gameScene (see GameSceneMain.gameSceneClass), mirroring
-- LevelCompleteScene's own transition logic, while Ⓑ backs out to the
-- select list without applying anything.

import "scripts/utilities/Config"
import "scripts/player/ConfigUpgrades"
import "scripts/utilities/MenuCard"

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
---@field phase string "select" | "confirm"
---@field layout MenuCard.Layout set once phase == "select", see rebuild()
---@field resultTree table playout tree, set once phase == "confirm", see rebuild()
---@field resultImg _Image drawn image of resultTree, set once phase == "confirm", see rebuild()
---@field upgrade Config.Upgrade set once phase == "confirm"
---@field oldValue number set once phase == "confirm"
---@field newValue number set once phase == "confirm"
---@field crankAccum number leftover crank degrees not yet converted into a selection move, see the cranked handler
UpgradeSelectScene = class("UpgradeSelectScene").extends(NobleScene) or UpgradeSelectScene

local scene = nil

-- Draws `count` distinct entries from Config.UPGRADES without replacement
-- (falls back to fewer if the pool is smaller than `count`). Entries with an
-- `available` predicate (e.g. "Rapid Autolightning" requiring Autolightning
-- already be installed) are skipped unless it currently returns true.
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

-- Confirm screen: the chosen upgrade's title plus a before/after preview of
-- the stat it would touch, and a Ⓐ confirm / Ⓑ back prompt.
---@param upgrade Config.Upgrade
---@param oldValue number
---@param newValue number
---@return table playout tree
local function buildResultTree(upgrade, oldValue, newValue)
	local children = {
		playout.text.new(upgrade.title .. "!"),
		playout.text.new("Was: " .. upgrade.format(oldValue)),
		playout.text.new("Now: " .. upgrade.format(newValue)),
		playout.text.new("Ⓐ confirm   Ⓑ back"),
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
	self.phase = "select" -- "select" <-> "confirm"
	self.crankAccum = 0

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.layout must already exist by then.
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
		self.layout = MenuCard.build("Choose an Upgrade", "Ⓐ select", Config.upgradeMenuItems(self.upgrades), self.selected, MENU_FONT)
	else
		self.resultTree = buildResultTree(self.upgrade, self.oldValue, self.newValue)
		self.resultImg = self.resultTree:draw()
	end
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
			local oldValue, newValue = Config.previewUpgrade(upgrade)
			scene.upgrade = upgrade
			scene.oldValue = oldValue
			scene.newValue = newValue
			scene.phase = "confirm"
			scene:rebuild()
		else
			Config.applyUpgrade(scene.upgrade)
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
	BButtonDown = function()
		if not scene or scene.phase ~= "confirm" then return end
		scene.phase = "select"
		scene:rebuild()
	end,
	-- Same fast-scroll idea as TuningScene.lua: the crank moves the
	-- highlight one item per Config.MENU_CRANK_DEGREES_PER_ITEM degrees
	-- turned, in either direction (a no-op once phase == "confirm", same as
	-- moveSelection). crankAccum carries leftover sub-threshold rotation
	-- between calls.
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

function UpgradeSelectScene:update()
	UpgradeSelectScene.super.update(self)
	if self.phase == "select" then
		MenuCard.draw(self.layout)
	else
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
		local x = (Config.SCREEN_W - self.resultImg.width) / 2
		local y = (Config.SCREEN_H - self.resultImg.height) / 2
		self.resultImg:draw(x, y)
	end
end
