#!/usr/bin/env bash
# Converts a directory tree of source sound effects (any format ffmpeg
# reads, e.g. art-src/sounds/**/*.mp3) into ADPCM .wav files under
# source/assets/sounds/, one output file per input file, preserving the
# input's subdirectory structure -- offline preprocessing for
# source/scripts/SoundBank.lua, which plays back a folder's compiled sounds
# at random (see that file's header). Mirrors render-song.sh's ADPCM encode
# step but skips the MIDI-synthesis and piece-splitting stages: each sound
# effect here is already a short, standalone clip, so it stays in one piece.
#
# Downmixes to mono -- the Playdate's built-in speaker is mono anyway, and
# it keeps these short one-shots small.
#
# Usage: tools/render-sfx.sh <input-dir> [output-dir]
#   e.g. tools/render-sfx.sh art-src/sounds/enemy/hit
#        -> source/assets/sounds/enemy/hit/hit.wav, .../crush.wav, ...
#   e.g. tools/render-sfx.sh art-src/sounds
#        -> converts the whole tree, e.g.
#           source/assets/sounds/player/hurt/owe.wav
#
# Requires ffmpeg on PATH. pdc auto-compiles any .wav dropped under
# source/assets into .pda at build time.
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
	echo "Usage: $0 <input-dir> [output-dir]" >&2
	echo "  e.g. $0 art-src/sounds/enemy/hit" >&2
	exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "Error: ffmpeg not found on PATH -- install it first (e.g. apt install ffmpeg)" >&2
	exit 1
fi

INPUT_DIR="$1"
if [ ! -d "$INPUT_DIR" ]; then
	echo "Error: $INPUT_DIR not found or not a directory" >&2
	exit 1
fi

# Default output mirrors the input's own path under source/assets/sounds,
# e.g. art-src/sounds/enemy/hit -> source/assets/sounds/enemy/hit, so the
# common "convert one bank" invocation needs no second argument.
case "$INPUT_DIR" in
	art-src/sounds) DEFAULT_OUTPUT="source/assets/sounds" ;;
	art-src/sounds/*) DEFAULT_OUTPUT="source/assets/sounds/${INPUT_DIR#art-src/sounds/}" ;;
	*) DEFAULT_OUTPUT="source/assets/sounds/$(basename "$INPUT_DIR")" ;;
esac
OUTPUT_DIR="${2:-$DEFAULT_OUTPUT}"

count=0
while IFS= read -r -d '' src; do
	rel="${src#"$INPUT_DIR"/}"
	out="$OUTPUT_DIR/${rel%.*}.wav"
	mkdir -p "$(dirname "$out")"
	echo "==> $src -> $out"
	ffmpeg -y -loglevel error -i "$src" -ar 44100 -ac 1 -acodec adpcm_ima_wav "$out"
	count=$((count + 1))
done < <(find "$INPUT_DIR" -type f \( -iname '*.mp3' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.aiff' \) -print0)

echo "==> Wrote $count file(s) to $OUTPUT_DIR"
