#!/usr/bin/env bash
# Renders art-src/title-hero.mp4 into the looping background imagetable
# TitleScene.lua draws behind the title menu -- a thin wrapper around
# tools/render-video-loop.sh with the params pinned to what TitleScene.lua
# actually expects, instead of having to remember them at the call site.
#
# The two params that matter most are FPS and NAME: TitleScene.lua's
# HERO_FPS local must equal the --fps this was rendered at (it's passed
# straight into gfx.animation.loop.new(1000 / HERO_FPS, ...)), and NAME must
# stay "title-hero" since that's the literal string TitleScene.lua passes to
# gfx.imagetable.new. WIDTH/HEIGHT are pinned to Config.SCREEN_W/H (400x240)
# since this is a full-screen background, same as the old static
# title-hero.png. If you change any of these, update TitleScene.lua (and its
# HERO_FPS) to match.
#
# Usage: tools/render-title-hero-loop.sh [input.mp4]
#   e.g. tools/render-title-hero-loop.sh
#        -> art-src/title-hero.mp4 -> source/assets/images/title-hero-table-400-240.png
#
# Requires ffmpeg and ffprobe on PATH (see tools/render-video-loop.sh).
set -euo pipefail

if [ $# -gt 1 ]; then
	echo "Usage: $0 [input.mp4]" >&2
	exit 1
fi

INPUT="${1:-art-src/title-hero.mp4}"
if [ ! -f "$INPUT" ]; then
	echo "Error: $INPUT not found" >&2
	exit 1
fi

NAME="title-hero"
FPS=10
WIDTH=400
HEIGHT=240
MAX_FRAMES=40
COLUMNS=8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/render-video-loop.sh" "$INPUT" "$NAME" \
	--fps "$FPS" --width "$WIDTH" --height "$HEIGHT" \
	--max-frames "$MAX_FRAMES" --columns "$COLUMNS"
