-- InstructionsScene.lua
-- How-to-play screen reached from the Title screen. B returns to Title.

import "scripts/Config"

local gfx <const> = playdate.graphics

---@class InstructionsScene : NobleScene
InstructionsScene = class("InstructionsScene").extends(NobleScene) or InstructionsScene

---@param ... any
function InstructionsScene:init(...)
	InstructionsScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
end

InstructionsScene.inputHandler = {
	BButtonDown = function() Noble.transition(TitleScene) end,
}

function InstructionsScene:update()
	InstructionsScene.super.update(self)
	local cx = Config.SCREEN_W / 2

	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	gfx.drawTextAligned("Crank to steer the helm", cx, 96, kTextAlignment.center)
	gfx.drawTextAligned("Up/Down to trim the sails", cx, 112, kTextAlignment.center)
	gfx.drawTextAligned("Left/Right to charge a broadside", cx, 128, kTextAlignment.center)

	gfx.drawTextAligned("Ⓑ to return to menu", cx, 160, kTextAlignment.center)
end
