-- TuningDiffScene.lua
-- Reached only from TuningScene's system menu, after "Load Defaults" or
-- "Load Custom" -- lists every ConfigTuning.ITEMS field whose value no
-- longer matches its fresh-load default (ConfigTuning.diffFromDefaults),
-- showing both the default and the now-current value, so a player can see
-- exactly what a load changed. Read-only: no editing happens here, only
-- scrolling and going back.
--
-- Rendered via MenuCard (source/scripts/utilities/MenuCard.lua), the same
-- list+description card layout TuningScene/SettingsScene/UpgradeTestScene/
-- UpgradeSelectScene use, with `opts.maxVisible` windowing like TuningScene
-- (a "Load Defaults" after a big custom load, or vice versa, could still
-- list most of ConfigTuning.ITEMS). Up/Down move the highlight (wraps); the
-- crank fast-scrolls; Ⓑ returns to TuningScene.

import "scripts/utilities/Config"
import "scripts/utilities/ConfigTuning"
import "scripts/utilities/MenuCard"

local gfx <const> = playdate.graphics

---@class TuningDiffScene : NobleScene
---@field selected integer index into self.diffs
---@field diffs { item: ConfigTuning.Item, default: number|boolean, current: number|boolean }[] snapshotted once in :init(), see the header comment above
---@field message? string optional note shown as the sole row when there's nothing to diff and no other content (e.g. "Load Custom" with no saved slot) -- see sceneProperties below
---@field crankAccum number leftover crank degrees not yet converted into a row move, see the cranked handler
---@field layout MenuCard.Layout see rebuild()
TuningDiffScene = class("TuningDiffScene").extends(NobleScene) or TuningDiffScene

local scene = nil

-- Same windowing constant as TuningScene.lua -- see MenuCard.build's
-- opts.maxVisible.
local VISIBLE_ROWS = 9

---@param sceneProperties? { message?: string }
function TuningDiffScene:init(sceneProperties)
	TuningDiffScene.super.init(self, sceneProperties)
	sceneProperties = sceneProperties or {}
	self.backgroundColor = gfx.kColorWhite
	self.selected = 1
	self.crankAccum = 0
	self.message = sceneProperties.message
	-- Snapshotted once here rather than recomputed every rebuild -- nothing
	-- on this read-only screen changes Config, so the diff can't change
	-- while it's open.
	self.diffs = ConfigTuning.diffFromDefaults()

	-- Built here rather than in :start() -- Noble may call :update() during
	-- the tail of the transition in, before :start() fires (see GameScene's
	-- init/start comments), so self.layout must already exist by then.
	self:rebuild()
end

function TuningDiffScene:start()
	TuningDiffScene.super.start(self)
	scene = self
end

function TuningDiffScene:finish()
	TuningDiffScene.super.finish(self)
	if scene == self then scene = nil end
end

---@return MenuCard.Item[]
local function buildMenuItems(self)
	if #self.diffs == 0 then
		return { {
			title = "No Differences",
			description = self.message or "Current settings match the defaults.",
		} }
	end
	local items = {}
	for i, diff in ipairs(self.diffs) do
		items[i] = {
			title = diff.item.label .. ": " .. ConfigTuning.formatValue(diff.item, diff.current),
			description = "Default: " .. ConfigTuning.formatValue(diff.item, diff.default),
		}
	end
	return items
end

function TuningDiffScene:rebuild()
	self.layout = MenuCard.build("What Changed", "Ⓑ back", buildMenuItems(self), self.selected, nil, { maxVisible = VISIBLE_ROWS })
end

---@param delta integer
local function moveSelection(delta)
	if not scene then return end
	local count = math.max(#scene.diffs, 1)
	scene.selected = ((scene.selected - 1 + delta) % count) + 1
	scene:rebuild()
end

TuningDiffScene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	BButtonDown = function()
		if scene then Noble.transition(TuningScene) end
	end,
	-- Same fast-scroll idea as TuningScene.lua: the crank moves the
	-- highlight one row per Config.MENU_CRANK_DEGREES_PER_ITEM degrees
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

function TuningDiffScene:update()
	TuningDiffScene.super.update(self)
	MenuCard.draw(self.layout)
end
