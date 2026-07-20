#!/usr/bin/env bash
# Generates source/assets/images/lightning-icon.png, the bolt glyph
# TitleScene.lua flanks the selected menu item with (see that file's
# ICON_W/ICON_H and buildTree()). Playdate's built-in system font has no
# glyph for the actual "⚡" character -- text containing it silently drops
# the character -- so the bolt is drawn here as a small pre-rendered image
# instead, the same approach as source/assets/images/storm-cloud.png.
#
# The shape is a plain vector polygon (no external source art), traced from
# Google's Material Design "flash_on" icon path (24x24 viewBox:
# M7,2V13H10L8,22L18,10H12L14,2H7) and rendered at 8x supersampling before
# downscaling, so the edges anti-alias cleanly. Left in 8-bit grayscale+alpha
# (not pre-dithered to 1-bit) so pdc dithers it at compile time, same as
# storm-cloud.png -- see render-title-hero.sh's header for when
# pre-dithering is needed instead (full-bleed art sized down from a much
# larger source, which isn't the case here).
#
# Usage: tools/render-lightning-icon.sh [output.png]
#   e.g. tools/render-lightning-icon.sh
#        -> source/assets/images/lightning-icon.png (9x16)
#
# Requires ImageMagick (`convert`) on PATH.
set -euo pipefail

if [ $# -gt 1 ]; then
	echo "Usage: $0 [output.png]" >&2
	exit 1
fi

if ! command -v convert >/dev/null 2>&1; then
	echo "Error: ImageMagick's convert not found on PATH -- install it first (e.g. apt install imagemagick)" >&2
	exit 1
fi

OUTPUT="${1:-source/assets/images/lightning-icon.png}"
mkdir -p "$(dirname "$OUTPUT")"

# Material "flash_on" path, shifted so its bbox (x:[7,18] y:[2,22] in the
# original 24x24 viewBox) starts at the origin, then scaled 8x for
# supersampling: canvas is 11x20 * 8 = 88x160.
TMP="$(mktemp --suffix=.png)"
trap 'rm -f "$TMP"' EXIT

convert -size 88x160 xc:none -fill black \
	-draw "polygon 0,0 0,88 24,88 8,160 88,64 40,64 56,0" "$TMP"
convert "$TMP" -resize 9x16 "$OUTPUT"

echo "==> $OUTPUT (9x16)"
