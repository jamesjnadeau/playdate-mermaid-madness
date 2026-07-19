-- test_scene_flow.lua
-- Functional test of the scene system: dofiles the *real*
-- source/scenes/*.lua files (not copies) under the class()/NobleScene/Noble
-- stand-ins in tests/support/mock_noble.lua, then drives them exactly like a
-- player would -- by firing simulated button-down events at whichever
-- inputHandler is currently active (Noble.Input.fire, see mock_noble.lua) --
-- and asserts each screen lands on the scene the flow diagram in
-- source/scenes/Scenes.md says it should.
--
-- GameSceneMain/GameSceneTraining/InstructionsScene extend a lightweight test
-- double (tests/support/mock_game_scene.lua) instead of the real
-- source/scenes/GameScene.lua: the real class builds a Player/Ship, sprites,
-- and particle systems, which is real-Simulator territory per CLAUDE.md, not
-- "does this button transition to the right scene." The double keeps
-- GameSceneMain/GameSceneTraining/InstructionsScene's *own* code (level-clear
-- detection, spawn caps, the enemy-select handoff, tutorial step progress)
-- real and under test.

dofile("tests/support/load_scenes.lua")

TestSceneFlow = {}

-- Config is a shared global mutated by SettingsScene (HUD_SHOW_* toggles)
-- and UpgradeSelectScene (Config.applyUpgrade rewrites whichever stat the
-- randomly-picked upgrade targets) -- snapshot/restore every scalar field so
-- one test's button presses can't leak into the next, same pattern as
-- test_config_upgrades.lua.
function TestSceneFlow:setUp()
	self.configSnapshot = {}
	for k, v in pairs(Config) do
		self.configSnapshot[k] = v
	end
	GameSceneTraining.selectedEnemyType = nil -- class-level field; survives scene transitions by design
	Noble.transition(TitleScene)
end

function TestSceneFlow:tearDown()
	for k, v in pairs(self.configSnapshot) do
		Config[k] = v
	end
end

local function currentClassName()
	local scene = Noble.currentScene()
	return scene and scene.className
end

-- --- TitleScene ---------------------------------------------------------

function TestSceneFlow:testTitleMenuNavigationWraps()
	lu.assertEquals(Noble.currentScene().selected, 2) -- default: "Training"

	Noble.Input.fire("upButtonDown")
	lu.assertEquals(Noble.currentScene().selected, 1) -- "Play"

	Noble.Input.fire("upButtonDown")
	lu.assertEquals(Noble.currentScene().selected, 4) -- wraps to "Settings"

	Noble.Input.fire("downButtonDown")
	Noble.Input.fire("downButtonDown")
	lu.assertEquals(Noble.currentScene().selected, 2) -- back to "Training"
end

function TestSceneFlow:testTitlePlaySelectionTransitionsToGameSceneMain()
	Noble.Input.fire("upButtonDown") -- 2 -> 1 ("Play")
	Noble.Input.fire("AButtonDown")

	lu.assertEquals(currentClassName(), "GameSceneMain")
	local scene = Noble.currentScene()
	lu.assertEquals(scene.level, 1)
	lu.assertEquals(scene.score, 0)
	lu.assertFalse(scene.gameOver)
end

function TestSceneFlow:testTitleTrainingSelectionTransitionsToGameSceneTraining()
	Noble.Input.fire("AButtonDown") -- default selected == 2, "Training"
	lu.assertEquals(currentClassName(), "GameSceneTraining")
end

function TestSceneFlow:testTitleInstructionsAndBack()
	Noble.Input.fire("downButtonDown") -- 2 -> 3, "Instructions"
	Noble.Input.fire("AButtonDown")
	lu.assertEquals(currentClassName(), "InstructionsScene")

	Noble.Input.fire("BButtonDown")
	lu.assertEquals(currentClassName(), "TitleScene")
end

-- Every control gets one step per direction, and each only clears once the
-- player actually performs *that* direction enough (see InstructionsScene.lua):
-- the crank steps by cumulative time spent cranking that sign, the trim/
-- broadside steps by a press count of that specific button. A same-step
-- wrong-direction press is asserted not to count, to lock in the "both
-- directions required" behavior this test exists to cover.
function TestSceneFlow:testInstructionsStepsRequireBothDirectionsThenBackAtAnyPoint()
	Noble.Input.fire("downButtonDown")
	Noble.Input.fire("AButtonDown")
	local scene = Noble.currentScene()
	lu.assertEquals(scene.step, InstructionsScene.STEP_CRANK_FORWARD)

	Noble.Input.fire("cranked", -5) -- wrong direction: doesn't count
	lu.assertEquals(scene.step, InstructionsScene.STEP_CRANK_FORWARD)

	-- A couple of extra ticks past the exact threshold as a margin against
	-- float accumulation error in the repeated Config.DT additions.
	local crankTicks = math.ceil(Config.INSTRUCTIONS_CRANK_SECONDS / Config.DT) + 2
	for _ = 1, crankTicks do
		Noble.Input.fire("cranked", 5)
	end
	lu.assertEquals(scene.step, InstructionsScene.STEP_CRANK_BACKWARD)

	for _ = 1, crankTicks do
		Noble.Input.fire("cranked", -5)
	end
	lu.assertEquals(scene.step, InstructionsScene.STEP_TRIM_UP)

	Noble.Input.fire("downButtonDown") -- wrong direction: doesn't count
	Noble.Input.fire("downButtonUp")
	lu.assertEquals(scene.step, InstructionsScene.STEP_TRIM_UP)

	for _ = 1, Config.INSTRUCTIONS_TRIM_PRESSES do
		Noble.Input.fire("upButtonDown")
		Noble.Input.fire("upButtonUp")
	end
	lu.assertEquals(scene.step, InstructionsScene.STEP_TRIM_DOWN)

	for _ = 1, Config.INSTRUCTIONS_TRIM_PRESSES do
		Noble.Input.fire("downButtonDown")
		Noble.Input.fire("downButtonUp")
	end
	lu.assertEquals(scene.step, InstructionsScene.STEP_BROADSIDE_LEFT)

	Noble.Input.fire("rightButtonDown") -- wrong direction: doesn't count
	Noble.Input.fire("rightButtonUp")
	lu.assertEquals(scene.step, InstructionsScene.STEP_BROADSIDE_LEFT)

	for _ = 1, Config.INSTRUCTIONS_BROADSIDE_PRESSES do
		Noble.Input.fire("leftButtonDown")
		Noble.Input.fire("leftButtonUp")
	end
	lu.assertEquals(scene.step, InstructionsScene.STEP_BROADSIDE_RIGHT)

	for _ = 1, Config.INSTRUCTIONS_BROADSIDE_PRESSES do
		Noble.Input.fire("rightButtonDown")
		Noble.Input.fire("rightButtonUp")
	end
	lu.assertEquals(scene.step, InstructionsScene.STEP_DONE)

	Noble.Input.fire("BButtonDown") -- B still exits once every step is done
	lu.assertEquals(currentClassName(), "TitleScene")
end

function TestSceneFlow:testTitleSettingsToggleAndBack()
	Noble.Input.fire("downButtonDown")
	Noble.Input.fire("downButtonDown") -- 2 -> 4, "Settings"
	Noble.Input.fire("AButtonDown")
	lu.assertEquals(currentClassName(), "SettingsScene")

	lu.assertEquals(Noble.currentScene().selected, 1)
	Noble.Input.fire("downButtonDown")
	lu.assertEquals(Noble.currentScene().selected, 2) -- "Wind Direction"

	local before = Config.HUD_SHOW_WIND_DIRECTION
	Noble.Input.fire("AButtonDown")
	lu.assertEquals(Config.HUD_SHOW_WIND_DIRECTION, not before)

	Noble.Input.fire("BButtonDown")
	lu.assertEquals(currentClassName(), "TitleScene")
end

-- --- GameSceneTraining / EnemySelectScene ------------------------------------

function TestSceneFlow:testGameSceneTrainingSpawnAndReturnToTitle()
	Noble.Input.fire("AButtonDown") -- Title -> GameSceneTraining
	lu.assertEquals(currentClassName(), "GameSceneTraining")

	local scene = Noble.currentScene()
	lu.assertEquals(#scene.enemies, 0)
	Noble.Input.fire("AButtonDown") -- spawn
	lu.assertEquals(#scene.enemies, 1)

	Noble.Input.fire("BButtonDown")
	lu.assertEquals(currentClassName(), "TitleScene")
	lu.assertEquals(#playdate.getSystemMenu():getMenuItems(), 0) -- GameSceneTraining:finish() cleared it
end

function TestSceneFlow:testGameSceneTrainingEnemySelectConfirmSetsForcedType()
	Noble.Input.fire("AButtonDown") -- Title -> GameSceneTraining
	local menuItems = playdate.getSystemMenu():getMenuItems()
	lu.assertEquals(#menuItems, 1)
	lu.assertEquals(menuItems[1].name, "Select Enemy")

	menuItems[1].callback() -- same as choosing it from the system menu
	lu.assertEquals(currentClassName(), "EnemySelectScene")
	lu.assertEquals(Noble.currentScene().selected, 1) -- selectedEnemyType was nil

	Noble.Input.fire("downButtonDown")
	lu.assertEquals(Noble.currentScene().selected, 2)
	Noble.Input.fire("AButtonDown")

	lu.assertEquals(currentClassName(), "GameSceneTraining")
	lu.assertEquals(GameSceneTraining.selectedEnemyType, StubEnemyB)

	-- Spawning now forces the selected type instead of a random pick.
	local scene = Noble.currentScene()
	Noble.Input.fire("AButtonDown")
	lu.assertEquals(getmetatable(scene.enemies[1]), StubEnemyB)
end

function TestSceneFlow:testGameSceneTrainingEnemySelectCancelLeavesSelectionUnchanged()
	Noble.Input.fire("AButtonDown") -- Title -> GameSceneTraining
	playdate.getSystemMenu():getMenuItems()[1].callback() -- -> EnemySelectScene

	Noble.Input.fire("downButtonDown")
	Noble.Input.fire("BButtonDown") -- cancel

	lu.assertEquals(currentClassName(), "GameSceneTraining")
	lu.assertNil(GameSceneTraining.selectedEnemyType)
end

-- --- GameSceneMain / LevelCompleteScene -----------------------------------

function TestSceneFlow:testGameSceneMainLevelClearTransitionsToLevelComplete()
	Noble.transition(GameSceneMain)
	local scene = Noble.currentScene()

	for _ = 1, Config.LEVEL_ENEMY_STEP do
		scene:enemyDefeated()
	end
	scene:tickGame()

	lu.assertEquals(currentClassName(), "LevelCompleteScene")
	local nextScene = Noble.currentScene()
	lu.assertEquals(nextScene.completedLevel, 1)
	lu.assertEquals(nextScene.totalDefeated, Config.LEVEL_ENEMY_STEP)
end

function TestSceneFlow:testGameSceneMainGameOverRestartsOnlyWhenOver()
	Noble.transition(GameSceneMain)
	local scene = Noble.currentScene()

	Noble.Input.fire("AButtonDown") -- gameOver == false: no-op
	lu.assertEquals(Noble.currentScene(), scene)

	scene.gameOver = true
	Noble.Input.fire("AButtonDown") -- gameOver == true: restart
	lu.assertNotEquals(Noble.currentScene(), scene)
	lu.assertEquals(currentClassName(), "GameSceneMain")
	lu.assertFalse(Noble.currentScene().gameOver)
end

function TestSceneFlow:testLevelCompleteConfirmTransitionsToUpgradeSelect()
	Noble.transition(LevelCompleteScene, nil, nil, nil, { completedLevel = 2, totalDefeated = 9 })
	Noble.Input.fire("AButtonDown")

	lu.assertEquals(currentClassName(), "UpgradeSelectScene")
	local scene = Noble.currentScene()
	lu.assertEquals(scene.level, 3)
	lu.assertEquals(scene.totalDefeated, 9)
end

-- --- UpgradeSelectScene / WindShiftScene ----------------------------------

function TestSceneFlow:testUpgradeSelectWithoutWindStepGoesStraightToGameSceneMain()
	-- windStepForLevel(2) == windStepForLevel(1) == 0: no escalation this level.
	Noble.transition(UpgradeSelectScene, nil, nil, nil, { level = 2, completedLevel = 1, totalDefeated = 5 })
	local scene = Noble.currentScene()
	lu.assertEquals(scene.phase, "select")
	lu.assertEquals(#scene.upgrades, 3)

	Noble.Input.fire("downButtonDown")
	lu.assertEquals(scene.selected, 2)

	Noble.Input.fire("AButtonDown") -- pick highlighted upgrade -> "result" phase
	lu.assertEquals(scene.phase, "result")
	lu.assertNotEquals(scene.oldValue, scene.newValue)

	Noble.Input.fire("AButtonDown") -- continue
	lu.assertEquals(currentClassName(), "GameSceneMain")
	lu.assertEquals(Noble.currentScene().level, 2)
	lu.assertEquals(Noble.currentScene().score, 5)
end

function TestSceneFlow:testUpgradeSelectWithWindStepGoesToWindShiftScene()
	-- windStepForLevel(4) == 1 > windStepForLevel(3) == 0: level 4 escalates.
	Noble.transition(UpgradeSelectScene, nil, nil, nil, { level = 4, completedLevel = 3, totalDefeated = 12 })
	Noble.Input.fire("AButtonDown") -- select -> result
	Noble.Input.fire("AButtonDown") -- continue

	lu.assertEquals(currentClassName(), "WindShiftScene")
	local scene = Noble.currentScene()
	lu.assertEquals(scene.level, 4)
	lu.assertEquals(scene.totalDefeated, 12)
end

function TestSceneFlow:testWindShiftConfirmTransitionsToGameSceneMain()
	Noble.transition(WindShiftScene, nil, nil, nil, { level = 4, totalDefeated = 12 })
	Noble.Input.fire("AButtonDown")

	lu.assertEquals(currentClassName(), "GameSceneMain")
	local scene = Noble.currentScene()
	lu.assertEquals(scene.level, 4)
	lu.assertEquals(scene.score, 12)
end
