-- DemoOverScene.lua
-- Shown when GameSceneDemo's run reaches Config.DEMO_MAX_LEVEL: reports the
-- run's defeated total, then returns to the Title screen. Only reachable via
-- GameSceneDemo:onLevelComplete, so only ever seen in a Config.DEMO_MODE
-- build (see Config.lua/TitleScene's confirmSelection).

import "scripts/Config"

local gfx <const> = playdate.graphics

---@class DemoOverScene : NobleScene
---@field completedLevel integer
---@field totalDefeated integer
DemoOverScene = class("DemoOverScene").extends(NobleScene) or DemoOverScene

local scene = nil

---@param sceneProperties? table
function DemoOverScene:init(sceneProperties)
	DemoOverScene.super.init(self, sceneProperties)
	self.backgroundColor = gfx.kColorWhite
	sceneProperties = sceneProperties or {}
	self.completedLevel = sceneProperties.completedLevel or 1
	self.totalDefeated = sceneProperties.totalDefeated or 0
end

function DemoOverScene:start()
	DemoOverScene.super.start(self)
	scene = self
end

function DemoOverScene:finish()
	DemoOverScene.super.finish(self)
	if scene == self then scene = nil end
end

DemoOverScene.inputHandler = {
	AButtonDown = function()
		if scene then Noble.transition(TitleScene) end
	end,
}

function DemoOverScene:update()
	DemoOverScene.super.update(self)
	local cx = Config.SCREEN_W / 2

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	gfx.drawTextAligned("THANKS FOR PLAYING!", cx, 80, kTextAlignment.center)
	gfx.drawTextAligned("You cleared " .. self.completedLevel .. " levels", cx, 105, kTextAlignment.center)
	gfx.drawTextAligned("Enemies defeated: " .. self.totalDefeated, cx, 125, kTextAlignment.center)
	gfx.drawTextAligned("Ⓐ to return to the title screen", cx, 160, kTextAlignment.center)
end
