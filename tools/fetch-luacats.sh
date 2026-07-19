#!/usr/bin/env bash
# Fetches playdate-luacats (LuaCATS type stubs for the Playdate SDK, used by
# lua-language-server for editor autocomplete/type checking) into
# vendor/playdate-luacats/ if it isn't already present. Mirrors fetch-deps.sh's
# pattern but kept separate since this is editor tooling only -- not needed
# by pdc or tests/run.sh, so it isn't wired into CI. Safe to run repeatedly.
# Honors LUACATS_REF to pin a branch/tag/commit instead of main.
set -euo pipefail

LUACATS_REF="${LUACATS_REF:-main}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
mkdir -p "$VENDOR"

if [ ! -d "$VENDOR/playdate-luacats" ]; then
	echo "==> Fetching playdate-luacats ($LUACATS_REF)"
	git clone --depth 1 --branch "$LUACATS_REF" \
		https://github.com/notpeter/playdate-luacats.git "$VENDOR/playdate-luacats"
else
	echo "==> playdate-luacats already present"
fi

echo "==> LuaCATS stubs ready. Point your editor's lua-language-server at"
echo "    this project (.luarc.json already references ./vendor/playdate-luacats)."
