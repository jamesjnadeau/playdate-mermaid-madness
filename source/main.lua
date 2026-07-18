-- main.lua
-- Cannonade — a top-down pirate sailing game for Playdate.
-- Built on Noble Engine (scenes/input/transitions) + pdParticles (wake/explosions).

import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/sprites"

-- Engine + libraries.
-- Noble expects to live at libraries/noble relative to this file.
import "libraries/noble/Noble"
-- pdParticles is a single file dropped in libraries/.
import "libraries/pdParticles"

-- Game code.
import "scripts/Config"
import "scripts/Utils"
import "scripts/Ship"
import "scripts/Enemy"
import "scripts/Cannonball"
import "scenes/TitleScene"
import "scenes/GameScene"
import "scenes/LevelCompleteScene"

-- Lock to a fixed 30fps so our fixed-timestep (Config.DT) matches wall-clock.
playdate.display.setRefreshRate(Config.REFRESH)

-- Boot the engine, starting on the title screen.
Noble.new(TitleScene)
