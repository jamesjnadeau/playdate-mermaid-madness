-- mock_noble.lua
-- A narrow stand-in for the pieces of the Playdate SDK's CoreLibs/object.lua
-- (the class() system) and Noble Engine (source/libraries/noble/) that
-- actual scene files touch at load time and during normal operation:
-- class()/Object/NobleScene, Noble.transition/currentScene, Noble.Input, the
-- playdate.graphics calls scenes make, kTextAlignment, playout, and
-- playdate.getSystemMenu(). This lets tests/test_scene_flow.lua dofile the
-- *real* source/scenes/*.lua files under plain lua5.4 and drive them by
-- calling into Noble.Input the same way a button press would.
--
-- Deliberately narrow, like tests/support/mock_playdate.lua: only what the
-- scene files under test actually call. Extend as needed if a future scene
-- touches something new -- see CLAUDE.md's tests/ section.
--
-- One real simplification worth calling out: Noble.transition() in the real
-- engine (source/libraries/noble/Noble.lua) animates the swap across several
-- frames (exit -> transition draws -> finish/enter -> start, on the *next*
-- frame boundary). Tests don't care about the animation, only the resulting
-- scene/inputHandler, so this mock collapses it into one synchronous call in
-- the same lifecycle order (exit, finish, then create/enter/start the new
-- scene).

-- CoreLibs/object.lua stand-in ------------------------------------------------

Object = {}
Object.__index = Object
Object.className = "Object"

-- Supports exactly what this repo's scenes use: class("Name").extends(Parent),
-- Name.super.method(self, ...) calls, and NewClass(sceneProperties) construction
-- that runs :init(sceneProperties) automatically (mirrors Noble.transition's
-- `queuedScene = NewScene(sceneProperties)`).
function class(name, properties, namespace)
	local target = namespace or _G
	local cls = target[name]
	if type(cls) ~= "table" then
		cls = {}
	end
	cls.className = name
	cls.__index = cls
	if type(properties) == "table" then
		for k, v in pairs(properties) do
			cls[k] = v
		end
	end
	target[name] = cls

	local builder = {}
	function builder.extends(parent)
		cls.super = parent
		setmetatable(cls, {
			__index = parent,
			__call = function(_, ...)
				local instance = setmetatable({}, cls)
				if instance.init then instance:init(...) end
				return instance
			end,
		})
		return cls
	end
	return builder
end

-- pdc's preprocessor directive; a no-op here since tests dofile files
-- directly in the order they need each other.
function import(...) end

-- playdate.graphics / kTextAlignment ------------------------------------------

playdate = playdate or {}
playdate.graphics = playdate.graphics or {}
local gfx = playdate.graphics
gfx.kColorBlack = gfx.kColorBlack or 0
gfx.kColorWhite = gfx.kColorWhite or 1
gfx.kColorClear = gfx.kColorClear or 2
gfx.kDrawModeCopy = gfx.kDrawModeCopy or "copy"
gfx.kDrawModeFillWhite = gfx.kDrawModeFillWhite or "fillWhite"
function gfx.drawText() end
function gfx.drawTextAligned() end
function gfx.setColor() end
function gfx.setLineWidth() end
function gfx.drawLine() end
function gfx.setImageDrawMode() end

kTextAlignment = { left = 0, center = 1, right = 2 }

-- playdate.getSystemMenu() ----------------------------------------------------

local systemMenuItems = {}
local systemMenu = {}
function systemMenu:addMenuItem(name, callback)
	systemMenuItems[#systemMenuItems + 1] = { name = name, callback = callback }
end
function systemMenu:addCheckmarkMenuItem(name, checked, callback)
	systemMenuItems[#systemMenuItems + 1] = { name = name, callback = callback }
end
function systemMenu:removeAllMenuItems()
	systemMenuItems = {}
end
-- Test helper, not part of the real playdate API: inspect what scenes have
-- added, e.g. to invoke GameSceneTest's "Select Enemy" callback directly.
function systemMenu:getMenuItems()
	return systemMenuItems
end
function playdate.getSystemMenu()
	return systemMenu
end

-- playout (source/libraries/playout.lua) stand-in -----------------------------
-- Scenes only ever build a tree and call tree:draw() to get an image-like
-- table with width/height and a :draw(x, y) method -- the actual layout math
-- isn't something the scene system's tests care about.

playout = {}
playout.kDirectionVertical = 1
playout.kDirectionHorizontal = 2
playout.kAlignStart = 1
playout.kAlignCenter = 2
playout.kAlignEnd = 3
playout.kAlignStretch = 4

playout.text = {}
function playout.text.new(content, properties)
	return { kind = "text", content = content, properties = properties or {} }
end

playout.box = {}
function playout.box.new(properties, children)
	return { kind = "box", properties = properties or {}, children = children or {} }
end

local fakeTreeImage = { width = 0, height = 0 }
function fakeTreeImage:draw(x, y) end

playout.tree = {}
function playout.tree.new(root, options)
	local self = { root = root, options = options or {} }
	function self:draw()
		return fakeTreeImage
	end
	return self
end

-- NobleScene (source/libraries/noble/modules/NobleScene.lua) stand-in --------

NobleScene = {}
class("NobleScene").extends(Object)
NobleScene.name = ""
NobleScene.backgroundColor = gfx.kColorWhite
NobleScene.inputHandler = {}

function NobleScene:init(__sceneProperties)
	self.name = self.className
end

function NobleScene:enter() end

function NobleScene:start()
	Noble.Input.setHandler(self.inputHandler)
end

function NobleScene:update() end
function NobleScene:drawBackground(__x, __y, __width, __height) end
function NobleScene:exit() end
function NobleScene:finish() end
function NobleScene:pause() end
function NobleScene:resume() end

-- Noble (source/libraries/noble/Noble.lua) stand-in --------------------------

Noble = {}

local currentScene = nil

function Noble.currentScene()
	return currentScene
end

function Noble.currentSceneName()
	return currentScene and currentScene.name
end

function Noble.isTransitioning()
	return false
end

-- See file header note: this runs synchronously instead of over several
-- animated frames, but in the same lifecycle order the real engine uses --
-- see Noble.transitionStartHandler/MidpointHandler/CompleteHandler in
-- source/libraries/noble/Noble.lua.
function Noble.transition(NewScene, __duration, __transition, __transitionProperties, __sceneProperties)
	local sceneProperties = __sceneProperties or {}
	local queuedScene = NewScene(sceneProperties) -- runs :init() now, like the real engine.

	if currentScene ~= nil then
		currentScene:exit()
		currentScene:finish()
	end
	currentScene = queuedScene
	currentScene:enter()
	currentScene:start() -- activates currentScene.inputHandler via NobleScene:start().
end

Noble.Input = {}
local currentHandler = nil

function Noble.Input.getHandler()
	return currentHandler
end

function Noble.Input.setHandler(__inputHandler)
	currentHandler = __inputHandler
end

function Noble.Input.clearHandler()
	currentHandler = nil
end

function Noble.Input.setEnabled(__value) end
function Noble.Input.setCrankIndicatorStatus(__active, __evenWhenUndocked) end

-- Test helper, not part of the real Noble.Input API: simulate a button press
-- by firing a named event (e.g. "AButtonDown", "upButtonDown", "cranked")
-- against whichever inputHandler is currently active -- exactly what the
-- Simulator does on a real button press, minus the SDK's own dispatch code.
function Noble.Input.fire(eventName, ...)
	if currentHandler and currentHandler[eventName] then
		currentHandler[eventName](...)
	end
end
