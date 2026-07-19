#!/usr/bin/env bash
# Runs the Lua unit tests in tests/ under a plain lua5.4 interpreter -- no
# Playdate SDK/Simulator involved, so this only covers pure-logic files that
# don't touch class()/CoreLibs (see tests/support/mock_playdate.lua for the
# scope/rationale). Exits non-zero on any test failure, so it's safe to use
# as a CI gate. Used both locally and by .github/workflows/build.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f "tests/vendor/luaunit.lua" ]; then
	bash tools/fetch-test-deps.sh
fi

LUA_BIN="${LUA_BIN:-lua5.4}"
"$LUA_BIN" tests/run_all.lua
