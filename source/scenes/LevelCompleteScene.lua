-- LevelCompleteScene.lua
-- Interstitial shown after clearing a level: reports the running defeated
-- total, then hands off to UpgradeSelectScene to pick a run upgrade before
-- continuing. UpgradeSelectScene carries the level/wind-step handoff the
-- rest of the way (to WindShiftScene or GameSceneMain, see
-- GameSceneMain.windStepForLevel).

import "scripts/Config"

local gfx <const> = playdate.graphics

---@class LevelCompleteScene : NobleScene
---@field completedLevel integer
---@field totalDefeated integer
LevelCompleteScene = class("LevelCompleteScene").extends(NobleScene) or LevelCompleteScene

local scene = nil

---@param sceneProperties? table
function LevelCompleteScene:init(sceneProperties)
	LevelCompleteScene.super.init(self, sceneProperties)
	self.backgroundColor = gfx.kColorWhite
	sceneProperties = sceneProperties or {}
	self.completedLevel = sceneProperties.completedLevel or 1
	self.totalDefeated = sceneProperties.totalDefeated or 0
end

function LevelCompleteScene:start()
	LevelCompleteScene.super.start(self)
	scene = self
end

function LevelCompleteScene:finish()
	LevelCompleteScene.super.finish(self)
	if scene == self then scene = nil end
end

LevelCompleteScene.inputHandler = {
	AButtonDown = function()
		if scene then
			local nextLevel = scene.completedLevel + 1
			Noble.transition(UpgradeSelectScene, nil, nil, nil, {
				level = nextLevel,
				completedLevel = scene.completedLevel,
				totalDefeated = scene.totalDefeated,
			})
		end
	end,
}

function LevelCompleteScene:update()
	LevelCompleteScene.super.update(self)
	local cx = Config.SCREEN_W / 2

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	gfx.drawTextAligned("LEVEL " .. self.completedLevel .. " CLEARED!", cx, 80, kTextAlignment.center)
	gfx.drawTextAligned("Enemies defeated: " .. self.totalDefeated, cx, 110, kTextAlignment.center)
	gfx.drawTextAligned("Next: Level " .. (self.completedLevel + 1), cx, 130, kTextAlignment.center)
	gfx.drawTextAligned("Ⓐ to continue", cx, 160, kTextAlignment.center)
end
