-- GameSceneDemo.lua
-- Identical to GameSceneMain (same shared input handler, spawning, level
-- progression, wind tuning, upgrade-select flow -- everything is inherited
-- unchanged) except the run ends after Config.DEMO_MAX_LEVEL levels instead
-- of continuing indefinitely: see onLevelComplete below. TitleScene's "Play"
-- item launches this instead of GameSceneMain when Config.DEMO_MODE is on
-- (see main.lua's sceneByName and TitleScene's confirmSelection).

import "scripts/Config"
import "scenes/GameSceneMain"
import "scenes/DemoOverScene"

---@class GameSceneDemo : GameSceneMain
GameSceneDemo = class("GameSceneDemo").extends(GameSceneMain) or GameSceneDemo

-- See GameSceneMain.gameSceneClass -- this is the only thing that needs
-- overriding for GameSceneMain's shared AButtonDown restart handler and the
-- LevelCompleteScene/UpgradeSelectScene/WindShiftScene interstitial chain to
-- both correctly stay within GameSceneDemo instead of dropping back to the
-- uncapped GameSceneMain. GameSceneDemo doesn't need its own inputHandler --
-- it inherits GameSceneMain.inputHandler as-is (class-level fields fall
-- through the extends() chain like methods do), and that handler's
-- AButtonDown reads gameSceneClass off the live instance rather than
-- hardcoding a class.
GameSceneDemo.gameSceneClass = GameSceneDemo

-- Ends the run once the level cap is reached, instead of GameSceneMain's
-- default hand-off to LevelCompleteScene for the next level.
function GameSceneDemo:onLevelComplete()
	if self.level >= Config.DEMO_MAX_LEVEL then
		Noble.transition(DemoOverScene, nil, nil, nil, {
			completedLevel = self.level,
			totalDefeated = self.score,
		})
		return
	end
	GameSceneDemo.super.onLevelComplete(self)
end
