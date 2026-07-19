-- WindShiftScene.lua
-- Interstitial shown when clearing a level also lands a wind escalation step
-- (see Config.LEVEL_WIND_STEP_INTERVAL / GameSceneMain.windStepForLevel).
-- Warns the player before dropping them into self.gameScene with tougher
-- wind. UpgradeSelectScene routes here only on levels where the step
-- actually changes; other levels go straight back to gameScene.

import "scripts/Config"

local gfx <const> = playdate.graphics

---@class WindShiftScene : NobleScene
---@field level integer
---@field totalDefeated integer
---@field gameScene table class table (GameSceneMain or a subclass, e.g. GameSceneDemo) to return to -- see GameSceneMain.gameSceneClass
WindShiftScene = class("WindShiftScene").extends(NobleScene) or WindShiftScene

local scene = nil

---@param sceneProperties? table
function WindShiftScene:init(sceneProperties)
	WindShiftScene.super.init(self, sceneProperties)
	self.backgroundColor = gfx.kColorWhite
	sceneProperties = sceneProperties or {}
	self.level = sceneProperties.level or 1
	self.totalDefeated = sceneProperties.totalDefeated or 0
	self.gameScene = sceneProperties.gameScene or GameSceneMain
end

function WindShiftScene:start()
	WindShiftScene.super.start(self)
	scene = self
end

function WindShiftScene:finish()
	WindShiftScene.super.finish(self)
	if scene == self then scene = nil end
end

WindShiftScene.inputHandler = {
	AButtonDown = function()
		if scene then
			Noble.transition(scene.gameScene, nil, nil, nil, {
				level = scene.level,
				totalDefeated = scene.totalDefeated,
			})
		end
	end,
}

function WindShiftScene:update()
	WindShiftScene.super.update(self)
	local cx = Config.SCREEN_W / 2

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	gfx.drawTextAligned("THE WINDS ARE SHIFTING!", cx, 80, kTextAlignment.center)
	gfx.drawTextAligned("Stronger gusts ahead", cx, 110, kTextAlignment.center)
	gfx.drawTextAligned("Level " .. self.level, cx, 130, kTextAlignment.center)
	gfx.drawTextAligned("Ⓐ to set sail", cx, 160, kTextAlignment.center)
end
