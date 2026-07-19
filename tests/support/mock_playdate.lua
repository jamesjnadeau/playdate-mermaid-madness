-- mock_playdate.lua
-- Minimal stand-ins for the Playdate/pdParticles globals that
-- source/scripts/Config.lua, ConfigUpgrades.lua and Utils.lua touch at load
-- time, so those pure-logic files can be dofile'd under a plain lua5.4
-- interpreter instead of the Simulator.
--
-- Deliberately narrow: this does NOT provide class()/CoreLibs, so anything
-- that does `class("X").extends(...)` (every scene, Ship, Enemy, ...) is out
-- of scope for tests/ -- those still need the real Simulator, per
-- CLAUDE.md's build/run-verification note. Extend this file's globals if a
-- future pure-logic script needs something it doesn't already provide.

playdate = {
	graphics = {
		kColorBlack = 0,
		kColorWhite = 1,
		kColorClear = 2,
	},
}

-- Config.lua's EXPLOSION table stores Particles.modes.DECAY (pdParticles) --
-- the value is never evaluated by the logic under test, just carried along.
Particles = {
	modes = { DECAY = "decay" },
}

dofile("source/scripts/Config.lua")
dofile("source/scripts/ConfigUpgrades.lua")
dofile("source/scripts/Utils.lua")
