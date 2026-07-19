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
import "scripts/StormCloud"
import "scripts/Sound"
import "scripts/MusicPlayer"
import "scenes/TitleScene"
import "scenes/InstructionsScene"
import "scenes/SettingsScene"
import "scenes/TuningScene"
import "scenes/GameScene"
import "scenes/GameSceneMain"
import "scenes/GameSceneDemo"
import "scenes/GameSceneTraining"
import "scenes/EnemySelectScene"
import "scenes/UpgradeTestScene"
import "scenes/LevelCompleteScene"
import "scenes/UpgradeSelectScene"
import "scenes/WindShiftScene"
import "scenes/DemoOverScene"

-- Lock to a fixed 30fps so our fixed-timestep (Config.DT) matches wall-clock.
playdate.display.setRefreshRate(Config.REFRESH)

-- Noble's built-in FPS counter -- player-facing on/off switch lives in
-- SettingsScene's HUD section (Config.HUD_SHOW_FPS), which also mirrors onto
-- Noble.showFPS whenever it's toggled. This just applies the boot default.
Noble.showFPS = Config.HUD_SHOW_FPS

-- Which scene to boot into: Config.START_SCENE, unless overridden via the
-- MERMAID_START_SCENE environment variable (see tools/simulate.sh, which
-- forwards it as a Simulator launch argument since the Lua sandbox has no
-- os.getenv -- playdate.argv[1] is where that argument lands).
local sceneByName = {
	Title = TitleScene,
	Instructions = InstructionsScene,
	Settings = SettingsScene,
	Tuning = TuningScene,
	GameMain = GameSceneMain,
	GameDemo = GameSceneDemo,
	GameTraining = GameSceneTraining,
	EnemySelect = EnemySelectScene,
	UpgradeTest = UpgradeTestScene,
	LevelComplete = LevelCompleteScene,
	UpgradeSelect = UpgradeSelectScene,
	WindShift = WindShiftScene,
	DemoOver = DemoOverScene,
}

local startSceneName = playdate.argv[1] or Config.START_SCENE
local StartScene = sceneByName[startSceneName]
if not StartScene then
	print("Config.START_SCENE/MERMAID_START_SCENE: unknown scene '" .. tostring(startSceneName) .. "', falling back to Title")
	StartScene = TitleScene
end

-- Background music: plays the first bundled song (source/assets/songs,
-- alphabetically) by default -- a no-op if none are bundled. The system
-- menu's "Music" checkmark is the player-facing on/off switch; it and
-- SettingsScene's Sound section both go through MusicPlayer.setEnabled/
-- selectSong, so all three stay in sync (see Config.MUSIC_ENABLED/MUSIC_SONG).
MusicPlayer.playDefault()
playdate.getSystemMenu():addCheckmarkMenuItem("Music", Config.MUSIC_ENABLED, function(value)
	MusicPlayer.setEnabled(value)
end)

-- Boot the engine.
Noble.new(StartScene)
