#!/usr/bin/env bash
# Generates source/assets/images/blue-whale.png, the sprite
# EnemyBlueWhale.lua's drawBodyLocal draws instead of its old procedural
# ellipse+tail-fluke shape.
#
# The source art (art-src/blue_whale.png) is a top-down whale, nose at the
# top of the frame, on what looks like a transparency checkerboard -- but
# `identify -verbose` shows the whole 2048x2048 canvas is fully opaque
# (alpha=1 everywhere): the checker pattern is baked into the RGB pixels
# themselves, not real alpha. Its cells aren't a clean two-color checker
# either (sampled corner pixels ranged ~180-255), so plain chroma-keying by
# color would also wrongly key out the whale's own white belly. Instead this
# floods in from all four corners (`-fuzz 30%` so the whole 180-255 range
# counts as "background", `-alpha on -fill none -draw "color X,Y floodfill"`)
# -- a connected-region fill, not a global color swap, so it can't leak past
# the whale's solid black outline into the interior even though the
# interior shares literal color values (e.g. white) with the background.
#
# After that: trim to content, rotate 90 (clockwise, ImageMagick's default
# direction for a positive -rotate) so the nose points along +x -- this
# game's local body-space convention for heading 0, see Ship:drawBodyLocal
# and Utils.heading -- then force-resize to OUTPUT_WIDTHxOUTPUT_HEIGHT
# (default 80x36, i.e. 2x Config.ENEMY_BLUE_WHALE_LENGTH x 2x
# Config.ENEMY_BLUE_WHALE_BEAM's current defaults) so EnemyBlueWhale.lua's
# runtime drawScaled call is an identity scale in the common case, same
# reasoning as source/assets/images/storm-cloud.png sitting at exactly
# Config.STORM_CLOUD_WIDTH x HEIGHT (see StormCloud:draw) -- avoids scaling
# an already-pdc-dithered image at runtime except when Config's
# LENGTH/BEAM are actually customized away from that default.
#
# Usage: tools/render-blue-whale.sh [input.png] [output.png]
#   e.g. tools/render-blue-whale.sh
#        -> art-src/blue_whale.png -> source/assets/images/blue-whale.png (80x36)
#
# Requires ImageMagick (`convert`) on PATH.
set -euo pipefail

if [ $# -gt 2 ]; then
	echo "Usage: $0 [input.png] [output.png]" >&2
	exit 1
fi

if ! command -v convert >/dev/null 2>&1; then
	echo "Error: ImageMagick's convert not found on PATH -- install it first (e.g. apt install imagemagick)" >&2
	exit 1
fi

INPUT="${1:-art-src/blue_whale.png}"
OUTPUT="${2:-source/assets/images/blue-whale.png}"
if [ ! -f "$INPUT" ]; then
	echo "Error: $INPUT not found" >&2
	exit 1
fi

# 2x Config.ENEMY_BLUE_WHALE_LENGTH / BEAM's current defaults -- see header.
OUTPUT_WIDTH=80
OUTPUT_HEIGHT=36

# Background flood-fill tolerance -- wide enough to span the ~180-255
# checker-cell range sampled from the source art (see header).
BACKGROUND_FUZZ=30%

mkdir -p "$(dirname "$OUTPUT")"

TMP="$(mktemp --suffix=.png)"
trap 'rm -f "$TMP"' EXIT

read -r IN_W IN_H <<<"$(identify -format "%w %h" "$INPUT")"

convert "$INPUT" -alpha on -fuzz "$BACKGROUND_FUZZ" -fill none \
	-draw "color 0,0 floodfill" \
	-draw "color $((IN_W - 1)),0 floodfill" \
	-draw "color 0,$((IN_H - 1)) floodfill" \
	-draw "color $((IN_W - 1)),$((IN_H - 1)) floodfill" \
	-trim +repage \
	-rotate 90 +repage \
	-filter Lanczos -resize "${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}!" \
	"$TMP"
mv "$TMP" "$OUTPUT"
trap - EXIT

echo "==> $INPUT -> $OUTPUT (${OUTPUT_WIDTH}x${OUTPUT_HEIGHT})"
