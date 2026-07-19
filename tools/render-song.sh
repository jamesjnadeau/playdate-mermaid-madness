#!/usr/bin/env bash
# Renders a MIDI file to a directory of ADPCM-encoded .wav pieces via
# fluidsynth + ffmpeg -- offline preprocessing for
# source/scripts/MusicPlayer.lua, which streams pre-rendered audio far more
# cheaply than a live playdate.sound.synth-per-note approach (see Inside
# Playdate section 7.28: "ADPCM is the ideal audio format to use for
# Playdate games"). Splitting into pieces (rather than one big .wav) means
# MusicPlayer only has to load the first piece before starting playback --
# see its header comment -- and each further piece loads in the background
# while the previous one plays. pdc auto-compiles any .wav dropped under
# source/assets into .pda at build time.
#
# Usage: tools/render-song.sh [--piano | --program N] [--seconds N] <input.mid> [output-dir]
#   e.g. tools/render-song.sh "source/assets/songs/Mozart.mid"
#        -> source/assets/songs/Mozart/000.wav, 001.wav, ..., using each
#           track's own instrument, split into 60s pieces
#   e.g. tools/render-song.sh --piano --seconds 30 "source/assets/songs/Mozart.mid"
#        -> same, but every track (except the GM percussion channel) is
#           forced to program 0 (Acoustic Grand Piano) via
#           midi_force_program.py before rendering, split into 30s pieces
#
# Requires fluidsynth and ffmpeg on PATH, and a General MIDI soundfont --
# defaults to /usr/share/sounds/sf2/default-GM.sf2 (Debian/Ubuntu's
# fluid-soundfont-gm package), override with the SOUNDFONT env var. The GM
# soundfont's instruments won't match the in-game sound of any other
# procedurally synthesized parts of the game -- this is meant as a starting
# point / proof of concept, not a drop-in tonal match. --piano/--program
# also need python3 on PATH.
set -euo pipefail

PROGRAM=""
SECONDS_PER_PIECE=60
ARGS=()
while [ $# -gt 0 ]; do
	case "$1" in
		--piano) PROGRAM=0; shift ;;
		--program) PROGRAM="$2"; shift 2 ;;
		--seconds) SECONDS_PER_PIECE="$2"; shift 2 ;;
		*) ARGS+=("$1"); shift ;;
	esac
done
set -- "${ARGS[@]}"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
	echo "Usage: $0 [--piano | --program N] [--seconds N] <input.mid> [output-dir]" >&2
	echo "  e.g. $0 \"source/assets/songs/Mozart.mid\"" >&2
	echo "  e.g. $0 --piano \"source/assets/songs/Mozart.mid\"" >&2
	exit 1
fi

for cmd in fluidsynth ffmpeg; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Error: $cmd not found on PATH -- install it first (e.g. apt install fluidsynth ffmpeg)" >&2
		exit 1
	fi
done

if [ -n "$PROGRAM" ] && ! command -v python3 >/dev/null 2>&1; then
	echo "Error: --piano/--program needs python3 on PATH" >&2
	exit 1
fi

SOUNDFONT="${SOUNDFONT:-/usr/share/sounds/sf2/default-GM.sf2}"
if [ ! -f "$SOUNDFONT" ]; then
	echo "Error: soundfont not found at $SOUNDFONT -- install one (e.g. apt install fluid-soundfont-gm) or set SOUNDFONT=/path/to/font.sf2" >&2
	exit 1
fi

INPUT="$1"
if [ ! -f "$INPUT" ]; then
	echo "Error: $INPUT not found" >&2
	exit 1
fi

OUTPUT_DIR="${2:-${INPUT%.*}}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TMP_RAW="$(mktemp --suffix=.wav)"
TMP_MID=""
TMP_SEGDIR="$(mktemp -d)"
trap 'rm -f "$TMP_RAW" "$TMP_MID"; rm -rf "$TMP_SEGDIR"' EXIT

SYNTH_INPUT="$INPUT"
if [ -n "$PROGRAM" ]; then
	TMP_MID="$(mktemp --suffix=.mid)"
	echo "==> Forcing every track to GM program $PROGRAM"
	python3 "$ROOT/tools/midi_force_program.py" "$INPUT" "$TMP_MID" "$PROGRAM"
	SYNTH_INPUT="$TMP_MID"
fi

echo "==> Synthesizing $INPUT with $SOUNDFONT"
fluidsynth -ni "$SOUNDFONT" "$SYNTH_INPUT" -F "$TMP_RAW" -r 44100

echo "==> Splitting into ${SECONDS_PER_PIECE}s pieces"
# -c copy: exact PCM split, no re-encode -- avoids stacking lossy passes
# before the per-piece ADPCM encode below.
ffmpeg -y -loglevel error -i "$TMP_RAW" -f segment -segment_time "$SECONDS_PER_PIECE" -c copy "$TMP_SEGDIR/%03d.wav"

echo "==> Encoding pieces to ADPCM (44100Hz) -> $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.wav
count=0
for seg in "$TMP_SEGDIR"/*.wav; do
	# Each piece is encoded from raw PCM independently, so its ADPCM
	# predictor state starts fresh -- splitting an already-encoded ADPCM
	# stream instead would carry decoder state across the cut and click.
	ffmpeg -y -loglevel error -i "$seg" -ar 44100 -acodec adpcm_ima_wav "$OUTPUT_DIR/$(basename "$seg")"
	count=$((count + 1))
done

echo "==> Wrote $count piece(s) to $OUTPUT_DIR"
