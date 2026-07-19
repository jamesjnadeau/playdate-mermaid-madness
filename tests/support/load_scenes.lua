-- load_scenes.lua
-- Loads the mock Noble Engine (mock_noble.lua), the real Config/Utils
-- scripts every scene imports, the GameScene test double (mock_game_scene.lua,
-- see its header for why GameSceneMain/GameSceneTraining -- and now
-- InstructionsScene, which extends GameScene too, see its header -- don't use
-- the real source/scenes/GameScene.lua), and finally the *real* scene files
-- under test -- in the same order source/main.lua imports them, since a few
-- top-level scene statements (e.g. GameSceneMain.inputHandler =
-- GameScene.buildSharedInputHandler(...), or InstructionsScene's own
-- `.extends(GameScene)`) run at load time and need GameScene to already
-- exist.
--
-- dofile'd once from tests/test_scene_flow.lua.

dofile("tests/support/mock_noble.lua")

dofile("source/scripts/Config.lua")
dofile("source/scripts/ConfigEnemy.lua")
dofile("source/scripts/ConfigUpgrades.lua")
dofile("source/scripts/Utils.lua")

dofile("tests/support/mock_game_scene.lua") -- stands in for source/scenes/GameScene.lua

dofile("source/scenes/TitleScene.lua")
dofile("source/scenes/InstructionsScene.lua")
dofile("source/scenes/SettingsScene.lua")

dofile("source/scenes/GameSceneMain.lua")
dofile("source/scenes/GameSceneTraining.lua")
dofile("source/scenes/EnemySelectScene.lua")
dofile("source/scenes/LevelCompleteScene.lua")
dofile("source/scenes/UpgradeSelectScene.lua")
dofile("source/scenes/WindShiftScene.lua")
