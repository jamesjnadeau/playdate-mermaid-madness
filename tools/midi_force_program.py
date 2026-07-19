#!/usr/bin/env python3
"""Rewrites every Program Change event in a Standard MIDI File to a fixed GM
program number, in place -- byte-for-byte, no re-encoding -- so fluidsynth
renders the whole file with a single instrument (e.g. program 0 = Acoustic
Grand Piano) instead of whatever each track originally specified. Channel 10
(the GM percussion channel) is left untouched, since remapping "instrument"
there doesn't apply -- it's always the drum kit.

Used by render-song.sh's --piano flag; not meant to be run standalone, but
takes plain positional args if you want to:

    midi_force_program.py <input.mid> <output.mid> [program]

`program` defaults to 0 (Acoustic Grand Piano) and must be 0-127.
"""
import sys


def force_program(data: bytearray, program: int) -> None:
	if not data.startswith(b"MThd"):
		raise ValueError("not a Standard MIDI File (missing MThd header)")

	pos = 14  # MThd chunk: 4-byte id + 4-byte length(=6) + 6 bytes of header data
	while pos < len(data):
		chunk_id = bytes(data[pos:pos + 4])
		chunk_len = int.from_bytes(data[pos + 4:pos + 8], "big")
		chunk_start = pos + 8
		chunk_end = chunk_start + chunk_len
		if chunk_id == b"MTrk":
			_rewrite_track(data, chunk_start, chunk_end, program)
		pos = chunk_end


def _read_vlq(data: bytearray, pos: int) -> tuple[int, int]:
	"""Returns (value, position just past the variable-length quantity at pos)."""
	value = 0
	while True:
		b = data[pos]
		value = (value << 7) | (b & 0x7F)
		pos += 1
		if not (b & 0x80):
			return value, pos


def _rewrite_track(data: bytearray, start: int, end: int, program: int) -> None:
	pos = start
	running_status = None
	while pos < end:
		_, pos = _read_vlq(data, pos)  # delta-time
		status = data[pos]
		if status & 0x80:
			pos += 1
			running_status = status if status < 0xF0 else None
		else:
			status = running_status

		if status == 0xFF:  # meta event: FF <type> <VLQ length> <data>
			pos += 1  # type byte
			length, pos = _read_vlq(data, pos)
			pos += length
		elif status in (0xF0, 0xF7):  # sysex: F0/F7 <VLQ length> <data>
			length, pos = _read_vlq(data, pos)
			pos += length
		elif status is None:
			raise ValueError(f"malformed MIDI: no running status at byte {pos}")
		else:
			high, channel = status & 0xF0, status & 0x0F
			if high == 0xC0:  # Program Change: <status> <program>
				if channel != 9:  # leave the percussion channel alone
					data[pos] = program
				pos += 1
			elif high == 0xD0:  # Channel Pressure: <status> <value>
				pos += 1
			else:  # Note On/Off, Poly Pressure, Control Change, Pitch Bend: 2 data bytes
				pos += 2


def main() -> None:
	if len(sys.argv) not in (3, 4):
		print(f"Usage: {sys.argv[0]} <input.mid> <output.mid> [program=0]", file=sys.stderr)
		sys.exit(1)
	input_path, output_path = sys.argv[1], sys.argv[2]
	program = int(sys.argv[3]) if len(sys.argv) == 4 else 0
	if not 0 <= program <= 127:
		print("program must be 0-127", file=sys.stderr)
		sys.exit(1)

	with open(input_path, "rb") as f:
		data = bytearray(f.read())
	force_program(data, program)
	with open(output_path, "wb") as f:
		f.write(data)


if __name__ == "__main__":
	main()
