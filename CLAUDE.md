# Working in this repo

## Build/run verification

Don't try to locate or run the Playdate SDK compiler (`pdc`) or launch the
Simulator to verify changes — the user builds and runs this project
themselves. Static review (reading the diff, checking Lua syntax/logic by
eye) is still expected; just don't invoke the toolchain. If asked to
specifically run something, that's a direct request and fine to do.

## Playdate system menu: 3-item cap

`playdate.getSystemMenu()` accepts at most **3 custom items total**, across
the whole game — this is a hardware/SDK constraint, not per-scene.
`addMenuItem`/`addCheckmarkMenuItem` don't error or warn when over the
limit; they silently no-op, so the only symptom is "the item isn't there."

Before adding any `playdate.getSystemMenu():addMenuItem`/
`addCheckmarkMenuItem` call, check how many other system-menu items could be
live at the same time. Prefer an in-scene [playout](source/libraries/playout.lua)-based
menu (see `source/scenes/EnemySelectScene.lua` / `source/scenes/SettingsScene.lua`
for the pattern) over the system menu when the setting doesn't need to be
reachable from the pause menu specifically.

History: this was first hit 2026-07-18 adding a "Select Enemy" system-menu
item to `GameSceneTest.lua` alongside 3 always-on HUD-toggle checkmark items
from `main.lua` — the 4th item never appeared. It was fixed by moving the HUD
toggles (Wind Speed/Direction/Player Speed) out of the system menu entirely
into `SettingsScene.lua` (reached from `TitleScene`'s "Settings" item). As of
now `GameSceneTest`'s "Select Enemy" is the only system-menu item in the
game, so there's no live conflict — but the cap still applies if a future
scene wants its own system-menu item alongside it.

## `tools/`

- **`build.sh`** — `$PLAYDATE_SDK_PATH/bin/pdc source MermaindMadness.pdx`.
  Compiles `source/` into the `.pdx` bundle. Requires `PLAYDATE_SDK_PATH` to
  be set and `fetch-deps.sh` to have been run first (`pdc` will fail on
  missing `import`s otherwise). Per the build/run-verification note above,
  this is for the user to run, not something to invoke to check your own work.
- **`simulate.sh`** — `$PLAYDATE_SDK_PATH/bin/PlaydateSimulator MermaindMadness.pdx`.
  Launches the compiled bundle in the Playdate Simulator. Same caveat as
  `build.sh`: the user runs this themselves.
- **`fetch-deps.sh`** — pulls the two vendored dependencies into
  `source/libraries/` if they aren't already present: Noble Engine (git clone)
  and pdParticles + playout (curl'd single files). Idempotent — safe to
  re-run, skips anything already fetched. Used both locally and by
  `.github/workflows/build.yml` in CI. Honors `NOBLE_REF` / `PARTICLES_REF` /
  `PLAYOUT_REF` env vars to pin a branch/tag/commit instead of `main`.
- **`new-enemy.sh <Name>`** — scaffolds a new `Enemy` subclass. Given a
  PascalCase or camelCase name (e.g. `Piranha`, `SeaSerpent`), it generates
  `source/scripts/Enemy<Name>.lua` (modeled on `EnemySwordfish.lua`, with
  TODOs for a distinct hull/look) and appends a matching
  `Config.ENEMY_<SNAKE_CASE_NAME>_*` tuning block to `ConfigEnemy.lua`
  (defaults mirror the base `ENEMY_*` values). Refuses to run if the target
  file or config section already exists. Prints the remaining manual wiring
  steps afterward (import in `main.lua`, add to `GameScene.enemyTypes`, tune
  the generated config block).
