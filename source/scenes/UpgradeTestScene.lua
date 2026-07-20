-- UpgradeTestScene.lua
-- Reached from GameSceneTraining's "Test Upgrade" system-menu item. Lists
-- every entry in Config.UPGRADES (source/scripts/player/ConfigUpgrades.lua) --
-- unlike UpgradeSelectScene's random draw of 3, the whole pool, and unlike
-- UpgradeSelectScene's pickUpgrades, ignoring each entry's `available`
-- predicate (e.g. "Rapid Autocannon" normally requires the Autofire Cannon
-- already installed) -- this is a dev/test tool, so every upgrade is always
-- reachable here regardless of prerequisites. Up/Down (or the crank) move
-- the highlight, Ⓐ applies the highlighted upgrade (via Config.applyUpgrade,
-- same as UpgradeSelectScene) and returns to GameSceneTraining, Ⓑ cancels back
-- without applying anything. No before/after result screen -- unlike
-- UpgradeSelectScene, this is meant to be reopened repeatedly to stack
-- several picks in a row, so it goes straight back to the sandbox instead of
-- pausing on a summary each time.
--
-- Rendered via MenuCard (source/scripts/utilities/MenuCard.lua), the same
-- list+description card layout UpgradeSelectScene's "select" phase uses.

import "scripts/utilities/Config"
import "scripts/player/ConfigUpgrades"
import "scripts/utilities/MenuCard"

local gfx <const> = playdate.graphics

---@class UpgradeTestScene : NobleScene
---@field selected integer index into Config.UPGRADES
---@field layout MenuCard.Layout see rebuild()
---@field crankAccum number leftover crank degrees not yet converted into a selection move, see the cranked handler
UpgradeTestScene = class("UpgradeTestScene").extends(NobleScene) or UpgradeTestScene

local scene = nil

-- Degrees of crank rotation that moves the highlight by one item, same idea
-- (and same threshold) as TuningScene.lua's CRANK_DEGREES_PER_ROW.
local CRANK_DEGREES_PER_ITEM = 20

---@param ... any
function UpgradeTestScene:init(...)
	UpgradeTestScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
	self.selected = 1
	self.crankAccum = 0

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.layout must already exist by then.
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
	self.layout = MenuCard.build("Test Upgrade", "Ⓐ apply   Ⓑ cancel", Config.upgradeMenuItems(Config.UPGRADES), self.selected)
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

function UpgradeTestScene:update()
	UpgradeTestScene.super.update(self)
	MenuCard.draw(self.layout)
end
