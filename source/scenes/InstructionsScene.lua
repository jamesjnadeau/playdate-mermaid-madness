-- InstructionsScene.lua
-- How-to-play walkthrough reached from the Title screen. Each step asks the
-- player to actually perform that input before the next one is shown.
-- Ⓑ exits back to Title at any point, regardless of step.

import "scripts/Config"

local gfx <const> = playdate.graphics

-- Crank steering is analog rather than a single button press, so its step
-- clears once the player has cumulatively turned it this many degrees
-- (direction doesn't matter) instead of on a single discrete event.
local CRANK_STEP_DEGREES = 30

---@class InstructionsScene : NobleScene
---@field step number index into InstructionsScene.steps; > #steps once done
---@field crankAccum number cumulative |crank change| (degrees) during the crank step
InstructionsScene = class("InstructionsScene").extends(NobleScene) or InstructionsScene

InstructionsScene.steps = {
	"Crank to steer the helm",
	"Up/Down to trim the sails",
	"Left/Right to charge a broadside",
}

-- File-local handle to the live instance, mirroring GameScene's `scene`
-- pattern (see GameScene.lua), so the class-level inputHandler below can
-- reach whichever instance is current.
local scene = nil

---@param ... any
function InstructionsScene:init(...)
	InstructionsScene.super.init(self, ...)
	self.backgroundColor = gfx.kColorWhite
	self.step = 1
	self.crankAccum = 0
end

function InstructionsScene:start()
	InstructionsScene.super.start(self)
	scene = self
end

function InstructionsScene:finish()
	InstructionsScene.super.finish(self)
	if scene == self then scene = nil end
end

---@param s InstructionsScene
local function advance(s)
	s.step = s.step + 1
	s.crankAccum = 0
end

InstructionsScene.inputHandler = {
	BButtonDown = function() Noble.transition(TitleScene) end,
	cranked = function(change, _)
		local s = scene
		if not s or s.step ~= 1 then return end
		s.crankAccum = s.crankAccum + math.abs(change)
		if s.crankAccum >= CRANK_STEP_DEGREES then advance(s) end
	end,
	upButtonDown = function()
		local s = scene
		if s and s.step == 2 then advance(s) end
	end,
	downButtonDown = function()
		local s = scene
		if s and s.step == 2 then advance(s) end
	end,
	leftButtonDown = function()
		local s = scene
		if s and s.step == 3 then advance(s) end
	end,
	rightButtonDown = function()
		local s = scene
		if s and s.step == 3 then advance(s) end
	end,
}

function InstructionsScene:update()
	InstructionsScene.super.update(self)
	local cx = Config.SCREEN_W / 2

	gfx.setImageDrawMode(gfx.kDrawModeCopy)

	local prompt = InstructionsScene.steps[self.step]
	if prompt then
		gfx.drawTextAligned(prompt, cx, 112, kTextAlignment.center)
	else
		gfx.drawTextAligned("You're ready to sail!", cx, 112, kTextAlignment.center)
	end

	gfx.drawTextAligned("Ⓑ to exit", cx, 160, kTextAlignment.center)
end
