#!/usr/bin/env bash
# Parse-checks this repo's own Lua code (source/scripts, source/scenes,
# source/main.lua) with `luac5.4 -p` (compiles each file and discards the
# output -- syntax-checking without executing anything), so a broken file is
# caught without needing the Playdate SDK or Simulator. Per CLAUDE.md's
# build/run-verification note, this -- like tests/run.sh -- is plain
# lua5.4/luac5.4 with no SDK/Simulator involved, so it's safe to run directly
# to check changes, not just on direct request.
#
# Deliberately points at scripts/scenes/main.lua rather than all of source/:
# source/libraries/ is vendored third-party code that `pdc`'s preprocessor
# compiles (it understands non-standard syntax like the `+=` family -- see
# .luarc.json's runtime.nonstandardSymbol -- that plain luac5.4 doesn't), so
# it isn't something this repo's own code ever relies on or can parse-check
# this way.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/source"

if ! command -v luac5.4 >/dev/null 2>&1; then
	echo "WARNING: luac5.4 not found on PATH -- skipping parse check." >&2
	exit 0
fi

fail=0
count=0
while IFS= read -r -d '' file; do
	count=$((count + 1))
	if ! err=$(luac5.4 -p "$file" 2>&1 >/dev/null); then
		fail=$((fail + 1))
		echo "==> FAILED: ${file#"$ROOT"/}"
		echo "$err" | sed 's/^/    /'
	fi
done < <(find "$SOURCE/scripts" "$SOURCE/scenes" "$SOURCE/main.lua" -name "*.lua" -print0)

if [ "$fail" -gt 0 ]; then
	echo "==> $fail/$count file(s) failed to parse." >&2
	exit 1
fi

echo "==> $count file(s) parsed OK."
