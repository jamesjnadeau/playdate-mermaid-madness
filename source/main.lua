-- main.lua
-- Mermaid Madness — a top-down pirate sailing game for Playdate.
-- Built on Noble Engine (scenes/input/transitions) + pdParticles (wake/explosions).

import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/sprites"

-- Engine + libraries.
-- Noble expects to live at libraries/noble relative to this file.
import "libraries/noble/Noble"
-- pdParticles is a single file dropped in libraries/.
import "libraries/pdParticles"
-- playout is a single file dropped in libraries/, used for menu/list UI.
import "libraries/playout"

-- Game code.
import "scripts/Config"
import "scripts/ConfigEnemy"
import "scripts/ConfigUpgrades"
import "scripts/Utils"
import "scripts/Ship"
import "scripts/Enemy"
import "scripts/EnemySwordfish"
import "scripts/EnemyKraken"
import "scripts/EnemyDummy"
import "scripts/Tridentball"
import "scenes/TitleScene"
import "scenes/InstructionsScene"
import "scenes/SettingsScene"
import "scenes/GameScene"
import "scenes/GameSceneMain"
import "scenes/GameSceneTraining"
import "scenes/EnemySelectScene"
import "scenes/LevelCompleteScene"
import "scenes/UpgradeSelectScene"
import "scenes/WindShiftScene"

-- Lock to a fixed 30fps so our fixed-timestep (Config.DT) matches wall-clock.
playdate.display.setRefreshRate(Config.REFRESH)

-- Which scene to boot into: Config.START_SCENE, unless overridden via the
-- MERMAID_START_SCENE environment variable (see tools/simulate.sh, which
-- forwards it as a Simulator launch argument since the Lua sandbox has no
-- os.getenv -- playdate.argv[1] is where that argument lands).
local sceneByName = {
	Title = TitleScene,
	Instructions = InstructionsScene,
	Settings = SettingsScene,
	GameMain = GameSceneMain,
	GameTraining = GameSceneTraining,
	EnemySelect = EnemySelectScene,
	LevelComplete = LevelCompleteScene,
	UpgradeSelect = UpgradeSelectScene,
	WindShift = WindShiftScene,
}

local startSceneName = playdate.argv[1] or Config.START_SCENE
local StartScene = sceneByName[startSceneName]
if not StartScene then
	print("Config.START_SCENE/MERMAID_START_SCENE: unknown scene '" .. tostring(startSceneName) .. "', falling back to Title")
	StartScene = TitleScene
end

-- Boot the engine.
Noble.new(StartScene)
