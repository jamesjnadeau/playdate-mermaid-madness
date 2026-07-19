# Working in this repo

## Response Notes

Before you respond, think if you should make any updates to this document that would help you be faster to respond in the future. Ask before making these updates to this document each time.

Please end your summaries with a suggested commit message for git.

If your change touches which scene the game boots into (`Config.START_SCENE`,
`main.lua`'s `sceneByName`, or `tools/simulate.sh`), ask whether the user
wants to run the Simulator with `MERMAID_START_SCENE` set to a scene that
makes testing the change easy, e.g. `MERMAID_START_SCENE=GameMain bash
tools/simulate.sh`.

## Build/run verification

Don't try to locate or run the Playdate SDK compiler (`pdc`) or launch the
Simulator to verify changes — the user builds and runs this project
themselves. Static review (reading the diff, checking Lua syntax/logic by
eye) is still expected; just don't invoke the toolchain. If asked to
specifically run something, that's a direct request and fine to do.

This does *not* apply to `tests/run.sh` (see the `tests/` section below) —
it's a plain `lua5.4` script with no SDK/Simulator involved, so running it to
check pure-logic changes is expected, not just a direct-request exception.

## Type annotations (LuaCATS)

`source/scripts/*.lua` and `source/scenes/*.lua` (not `source/libraries/` —
that's vendored third-party code) carry
[LuaCATS](https://luals.github.io/wiki/annotations/) doc comments so
lua-language-server can type-check and autocomplete against the Playdate SDK.
This is editor-only tooling — plain comments, no effect on `pdc`/the compiled
`.pdx` — so it needs no build/CI wiring, unlike `tests/`.

- **Setup**: run `tools/fetch-luacats.sh` to vendor
  [notpeter/playdate-luacats](https://github.com/notpeter/playdate-luacats)
  (SDK type stubs) into `vendor/playdate-luacats/` (gitignored — editor
  tooling only, not a build/test dependency). `.luarc.json` at the repo root
  already points `workspace.library` at it; point your editor's Lua
  extension (e.g. the "Lua" extension by sumneko/LLS-Addons on VSCode) at
  this project and it picks the config up automatically.
- **Class pattern**: the Playdate SDK's `class("X").extends(Parent)` creates
  the global `X` as a side effect but returns `nil`, which LuaCATS can't see
  through. Every class in this repo follows the workaround from
  [Franchovy/Playdate-Guides](https://github.com/Franchovy/Playdate-Guides)'s
  `Type-checking-basics` guide:
  ```lua
  ---@class Enemy : Ship
  ---@field moveSpeed number
  Enemy = class("Enemy").extends(Ship) or Enemy
  ```
  The `or Enemy` is a no-op at runtime (`class()` already assigned the
  global; `extends()` returns `nil`, so the `or` falls through to the
  existing value) but gives LuaCATS the direct assignment it needs to attach
  the `---@class` type. Follow this pattern for any new class, including
  ones scaffolded by `tools/new-enemy.sh` (see below) — it doesn't add
  annotations for you.
- Fields assigned in `:init()` (or a table constructor) are inferred
  automatically from that assignment — don't re-declare them with `---@field`.
  Reserve `---@field` for fields a subclass is expected to set (e.g. `Ship`'s
  `length`/`hull`/`color`, filled in by `Player`/`Enemy`, not `Ship:init`
  itself) or fields set outside `:init()` (lazily-built caches like
  `Ship.bodyImage`, class-level statics like `Enemy.minLevel`).
- `Config.lua`/`ConfigEnemy.lua` are almost entirely flat `Config.FOO = value`
  assignments, which LuaCATS already infers without help — no `---@field`
  needed there. `ConfigUpgrades.lua` is the exception: its `Config.UPGRADES`
  entries have a real shape, so it defines `---@class Config.Upgrade` and
  types `Config.applyUpgrade` against it.

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
item to `GameSceneTraining.lua` alongside 3 always-on HUD-toggle checkmark items
from `main.lua` — the 4th item never appeared. It was fixed by moving the HUD
toggles (Wind Speed/Direction/Player Speed) out of the system menu entirely
into `SettingsScene.lua` (reached from `TitleScene`'s "Settings" item). As of
now two items are live: `main.lua`'s "Music" checkmark (always on, added once
at boot, synced with `Config.MUSIC_ENABLED` via `MidiPlayer.setEnabled` —
see `SettingsScene.lua`'s Sound section for the player-facing equivalent) and
`GameSceneTraining`'s scene-scoped "Select Enemy" (added in `:start()`,
removed via `removeMenuItem` — not `removeAllMenuItems`, which would also
wipe out "Music" — in `:finish()`). That's 2 of the 3-item cap; there's
headroom for exactly one more, but check both of these are still accounted
for before adding it.

## `tests/`

Plain-`lua5.4` unit tests — no Playdate SDK or Simulator involved. Two tiers:

- Pure-logic files that don't use `class("X").extends(...)` at all
  (`source/scripts/Utils.lua`, `Config.applyUpgrade` in
  `source/scripts/ConfigUpgrades.lua`) — loaded under `support/mock_playdate.lua`,
  a minimal `playdate`/`Particles` global stand-in.
- The scene system (`source/scenes/*.lua`, real files, not copies) — loaded
  under `support/mock_noble.lua`, a from-scratch stand-in for the Playdate
  SDK's `class()`/CoreLibs and for Noble Engine's `NobleScene`/`Noble.transition`/
  `Noble.Input`, plus `support/mock_game_scene.lua`, a lightweight test double
  for `source/scenes/GameScene.lua` (real `Ship`/`Enemy`/sprite/particle
  gameplay is still real-Simulator territory — the double keeps
  `GameSceneMain`/`GameSceneTraining`'s *own* logic real while swapping out
  everything they build on top of). See `tests/test_scene_flow.lua`'s header
  for the full rationale.

Both tiers are a floor, not a substitute for manual verification in the
Simulator — gameplay feel, rendering, and anything that isn't scene
transitions or pure logic still needs a human in the Simulator.

- **`run.sh`** — runs the suite (`lua5.4 tests/run_all.lua`), fetching
  `luaunit` first via `fetch-test-deps.sh` if `tests/vendor/luaunit.lua` isn't
  already present. Exits non-zero on any failure. Used both locally and by
  `.github/workflows/build.yml`'s `test` job, which the `build` job now
  depends on (`needs: test`) — a broken test blocks the compile/release
  steps.
- **`run_all.lua`** — loads `tests/support/mock_playdate.lua`, then every
  `tests/test_*.lua` file, then hands off to `luaunit.LuaUnit.run()`. Add new
  test files to the list here.
- **`support/mock_playdate.lua`** — the minimal `playdate`/`Particles` global
  stand-ins needed to `dofile` `Config.lua`/`ConfigUpgrades.lua`/`Utils.lua`
  outside the Simulator. Extend this if a future pure-logic script needs
  something it doesn't already stub.
- **`support/mock_noble.lua`** — stand-in for `class()`/`Object`/`NobleScene`/
  `Noble.transition`/`Noble.Input`/`playdate.graphics`/`kTextAlignment`/
  `playout`/`playdate.getSystemMenu()`, narrow like `mock_playdate.lua`:
  only what `source/scenes/*.lua` actually touches. `Noble.transition`
  collapses the real engine's animated multi-frame swap into one synchronous
  call (same exit/finish/enter/start order); `Noble.Input.fire(eventName, ...)`
  is a test-only helper that simulates a button press by invoking that event
  on whichever inputHandler is currently active.
- **`support/mock_game_scene.lua`** — test double for `source/scenes/GameScene.lua`
  (see above). Extend this, not the real `GameScene.lua`, if a scene test
  needs another bit of the shared base scene's surface.
- **`support/load_scenes.lua`** — loads `mock_noble.lua`, the real
  `Config`/`ConfigEnemy`/`ConfigUpgrades`/`Utils` scripts, `mock_game_scene.lua`,
  then every real `source/scenes/*.lua` file, in `main.lua`'s import order
  (some scene files run code at load time that expects `GameScene` to
  already exist). `dofile`'d once from `test_scene_flow.lua`.
- **`test_scene_flow.lua`** — functional test of every transition in
  `source/scenes/Scenes.md`'s flow diagram, driven by `Noble.Input.fire`.
  Update this alongside `Scenes.md` when scene wiring changes.
- **`vendor/luaunit.lua`** — checked into git (like `pdParticles.lua`/
  `playout.lua` under `source/libraries/`), not gitignored; `fetch-test-deps.sh`
  is the bootstrap/fallback for a fresh clone missing it, mirroring
  `fetch-deps.sh`'s pattern. Honors `LUAUNIT_REF` to pin a branch/tag/commit
  instead of `master`.

## `source/scenes/Scenes.md`

One page per scene (purpose, entry points, controls, transitions out) plus a
mermaid diagram of the whole title-to-gameplay flow. **Keep it updated** —
whenever you add, remove, or rewire a scene (a new `Noble.transition` call, a
new scene file, a changed input binding that changes where a button leads),
update the matching section and diagram edge in `Scenes.md` in the same
change. `tests/test_scene_flow.lua` exercises the diagram's edges directly,
so a stale diagram and a stale test tend to go stale together — update both.

## `tools/`

- **`build.sh`** — `$PLAYDATE_SDK_PATH/bin/pdc source MermaidMadness.pdx`.
  Compiles `source/` into the `.pdx` bundle. Requires `PLAYDATE_SDK_PATH` to
  be set and `fetch-deps.sh` to have been run first (`pdc` will fail on
  missing `import`s otherwise). Per the build/run-verification note above,
  this is for the user to run, not something to invoke to check your own work.
- **`simulate.sh`** — `$PLAYDATE_SDK_PATH/bin/PlaydateSimulator MermaidMadness.pdx`.
  Launches the compiled bundle in the Playdate Simulator. Same caveat as
  `build.sh`: the user runs this themselves. If `MERMAID_START_SCENE` is set
  in the environment, forwards it as a launch argument so `main.lua` can pick
  a non-default boot scene — see `Config.START_SCENE` in
  `source/scripts/Config.lua` and the "Response Notes" section above.
- **`fetch-deps.sh`** — pulls the two vendored dependencies into
  `source/libraries/` if they aren't already present: Noble Engine (git clone)
  and pdParticles + playout (curl'd single files). Idempotent — safe to
  re-run, skips anything already fetched. Used both locally and by
  `.github/workflows/build.yml` in CI. Honors `NOBLE_REF` / `PARTICLES_REF` /
  `PLAYOUT_REF` env vars to pin a branch/tag/commit instead of `main`.
- **`fetch-test-deps.sh`** — same idea as `fetch-deps.sh` but for `tests/`:
  pulls `luaunit` into `tests/vendor/` if it isn't already present. Kept
  separate so a test-only dependency never ends up under `source/` (`pdc`
  would compile it into the `.pdx`). See the `tests/` section above.
- **`fetch-luacats.sh`** — same idea again, but for editor type checking:
  pulls `playdate-luacats` into `vendor/playdate-luacats/` (gitignored) if
  it isn't already present. Not wired into CI or `build.sh`/`tests/run.sh` —
  it's pure editor tooling, see the "Type annotations (LuaCATS)" section
  above. Honors `LUACATS_REF` to pin a branch/tag/commit instead of `main`.
- **`parse-check.sh`** — syntax-checks `source/scripts/`, `source/scenes/`,
  and `main.lua` with `luac5.4 -p` (compile-and-discard, no execution). Warns
  and exits 0 if `luac5.4` isn't on `PATH` rather than failing. Deliberately
  skips `source/libraries/`: those vendored files use `pdc`-only syntax (the
  `+=` family) plain `luac5.4` can't parse — see the "Type annotations
  (LuaCATS)" section above for the same distinction. Used both locally and by
  `.github/workflows/build.yml`'s `build` job (after `fetch-deps.sh`, its own
  "Install Lua" step providing `luac5.4` since the `build` job doesn't
  otherwise need lua5.4) as a fast fail-before-the-SDK-install gate.
  `tests/run.sh` already exercises `source/scenes/*.lua` for real (under the
  `mock_noble.lua` stand-in) as a stronger check than a bare parse, so this
  isn't a substitute for that, just a cheaper first check.
- **`new-enemy.sh <Name>`** — scaffolds a new `Enemy` subclass. Given a
  PascalCase or camelCase name (e.g. `Piranha`, `SeaSerpent`), it generates
  `source/scripts/Enemy<Name>.lua` (modeled on `EnemySwordfish.lua`, with
  TODOs for a distinct hull/look) and appends a matching
  `Config.ENEMY_<SNAKE_CASE_NAME>_*` tuning block to `ConfigEnemy.lua`
  (defaults mirror the base `ENEMY_*` values). Refuses to run if the target
  file or config section already exists. Prints the remaining manual wiring
  steps afterward (import in `main.lua`, add to `GameScene.enemyTypes`, tune
  the generated config block).
