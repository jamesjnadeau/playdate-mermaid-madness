#!/usr/bin/env bash
# Fetches luaunit (the Lua test framework used by tests/, see tests/run.sh)
# into tests/vendor/ if it isn't already present. Mirrors fetch-deps.sh's
# pattern but is kept separate since this is a test-only dependency that
# must never end up under source/ (pdc would compile it into the .pdx).
# Safe to run repeatedly. Used both locally and by .github/workflows/build.yml
# in CI. Honors LUAUNIT_REF to pin a branch/tag/commit instead of master.
set -euo pipefail

LUAUNIT_REF="${LUAUNIT_REF:-master}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/tests/vendor"
mkdir -p "$VENDOR"

if [ ! -f "$VENDOR/luaunit.lua" ]; then
	echo "==> Fetching luaunit ($LUAUNIT_REF)"
	curl -fsSL -o "$VENDOR/luaunit.lua" \
		"https://raw.githubusercontent.com/bluebird75/luaunit/${LUAUNIT_REF}/luaunit.lua"
else
	echo "==> luaunit already present"
fi

echo "==> Test dependencies ready."
