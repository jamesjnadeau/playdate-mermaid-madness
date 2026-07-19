-- MidiPlayer.lua
-- Loads a .mid into a playdate.sound.sequence and starts/stops it. The
-- Playdate SDK parses standard MIDI files but has no General MIDI sound
-- set, so it leaves instrumentation up to the game -- this assigns a
-- Patches.lua instrument to every track, guessing from note statistics
-- when a song doesn't pin one explicitly. Adapted from
-- https://github.com/plaidate/midiplayer's midiplayer.lua (MIT license):
-- trimmed to the load/play/stop/volume surface this game needs -- that
-- project's own UI, per-track mute, live patch cycling, and crank-driven
-- tempo scaling aren't ported.
--
-- Known upstream limitations (not fixable here, see that repo's
-- DEVGUIDE.md): program-change events in the file are ignored (hence the
-- mapping/guessing layer below); Format-0 MIDI files collapse to a single
-- track, so source files should be exported as Format 1; mid-song tempo
-- maps are unreliable, so source files should bake a fixed tempo.

import "scripts/Config"
import "scripts/Patches"
import "scripts/Utils"

local snd <const> = playdate.sound

---@class MidiPlayer.Track
---@field index integer sequence track index (1-based; low indices are often a tempo/meta track with no notes and are skipped)
---@field track _Track sequence track object, kept so applyDynamics can re-clamp and rewrite its notes without re-fetching from the sequence
---@field patch string Patches name assigned to this track
---@field inst _Instrument
---@field relVolume number this track's volume (0-1) relative to the rest of the song, from song.volume; multiplied with Config.MUSIC_VOLUME by applyVolume
---@field notes _SoundTrackNote[] this track's original note events (with unclamped velocity), captured at load() -- applyDynamics reads from this rather than the track's live notes so repeated calls with different Config.MUSIC_VOLUME_MIN/MAX bounds don't compound clamps on top of clamps

---@class MidiPlayer.Song
---@field path string path to a .mid file (e.g. "assets/songs/theme.mid"), passed straight to playdate.sound.sequence.new
---@field map? table<integer, string> explicit sequence track index -> Patches name; unmapped tracks are guessed from their own note statistics
---@field volume? table<integer, number> optional per-track relative volume (0-1); tracks not listed default to 1

---@class MidiPlayer
---@field seq _Sequence|nil
---@field tracks MidiPlayer.Track[]
---@field playing boolean
MidiPlayer = {
	seq = nil,
	tracks = {},
	playing = false,
}

-- Guesses a patch for a track with no explicit song.map entry, from its
-- note events: sequence track 10 is the GM drum-channel convention;
-- otherwise a track hitting few distinct pitches over and over reads as
-- percussion, a low mean pitch reads as bass, three-plus-note polyphony
-- reads as a pad, and anything else falls back to a lead.
---@param trackIndex integer
---@param notes table
---@param poly integer
---@return string
local function guessPatch(trackIndex, notes, poly)
	if trackIndex == 10 then return "drums" end
	local sum, count = 0, #notes
	local distinct = {}
	for i = 1, count do
		sum = sum + notes[i].note
		distinct[notes[i].note] = true
	end
	local mean = sum / count
	local nDistinct = 0
	for _ in pairs(distinct) do nDistinct = nDistinct + 1 end
	if nDistinct <= 6 and count / nDistinct >= 12 then return "drums" end
	if mean < 48 then return "bass" end
	if poly >= 3 then return "pad" end
	return "lead"
end

-- Loads `song`, stopping and replacing whatever's currently loaded. Every
-- track with at least one note gets an instrument (song.map[i] if given,
-- else guessPatch's heuristic), and Config.MUSIC_VOLUME /
-- Config.MUSIC_VOLUME_MIN/MAX are applied immediately -- see applyVolume
-- and applyDynamics. Does not start playback; call play() once loaded.
---@param song MidiPlayer.Song
function MidiPlayer.load(song)
	MidiPlayer.stop()
	local seq = snd.sequence.new(song.path)
	assert(seq, "MidiPlayer: failed to load " .. song.path)

	MidiPlayer.seq = seq
	MidiPlayer.tracks = {}

	local map = song.map or {}
	local relVolume = song.volume or {}
	for i = 1, seq:getTrackCount() do
		local track = seq:getTrackAtIndex(i)
		if track ~= nil then
			local notes = track:getNotes() or {}
			if #notes > 0 then
				local poly = track:getPolyphony()
				local patch = map[i] or guessPatch(i, notes, poly)
				local inst = Patches.instrument(patch, poly)
				track:setInstrument(inst)
				MidiPlayer.tracks[#MidiPlayer.tracks + 1] = {
					index = i,
					track = track,
					patch = patch,
					inst = inst,
					relVolume = relVolume[i] or 1,
					notes = notes,
				}
			end
		end
	end
	MidiPlayer.applyVolume()
	MidiPlayer.applyDynamics()
end

local function onFinish()
	if MidiPlayer.playing then
		MidiPlayer.seq:goToStep(1)
		MidiPlayer.seq:play(onFinish)
	end
end

-- Starts (or restarts, if stopped) the currently loaded song, looping
-- indefinitely. No-op if nothing is loaded or it's already playing.
function MidiPlayer.play()
	if MidiPlayer.seq and not MidiPlayer.playing then
		MidiPlayer.playing = true
		MidiPlayer.seq:play(onFinish)
	end
end

-- Stops playback and silences every voice. Safe to call with nothing
-- loaded or already stopped.
function MidiPlayer.stop()
	if MidiPlayer.seq and MidiPlayer.playing then
		MidiPlayer.playing = false -- clear first so onFinish doesn't restart it
		MidiPlayer.seq:stop()
		MidiPlayer.seq:allNotesOff()
	end
end

-- Pushes Config.MUSIC_VOLUME (times each track's relative volume from
-- song.volume) to every loaded track's instrument. Called automatically at
-- the end of load(); call it again any time Config.MUSIC_VOLUME changes at
-- runtime (e.g. from a settings screen) to make the change audible
-- immediately. Safe to call with nothing loaded.
function MidiPlayer.applyVolume()
	for _, t in ipairs(MidiPlayer.tracks) do
		t.inst:setVolume(Config.MUSIC_VOLUME * t.relVolume)
	end
end

-- Clamps every track's original note velocities (t.notes, captured at
-- load()) into [Config.MUSIC_VOLUME_MIN, Config.MUSIC_VOLUME_MAX] and
-- rewrites the track's notes to match -- compressing a song's per-note
-- dynamic range instead of scaling it uniformly like applyVolume does.
-- Clamping from the cached original notes (rather than track:getNotes(),
-- which would already reflect a previous clamp) means calling this
-- repeatedly with different bounds doesn't compound. track:setNotes() is
-- Lua-side sugar that *adds* notes rather than replacing them -- the
-- underlying C API has no bulk "replace" -- hence the clearNotes() first.
-- Called automatically at the end of load(); call again any time
-- Config.MUSIC_VOLUME_MIN/MAX changes at runtime. Safe to call with nothing
-- loaded.
function MidiPlayer.applyDynamics()
	local lo, hi = Config.MUSIC_VOLUME_MIN, Config.MUSIC_VOLUME_MAX
	for _, t in ipairs(MidiPlayer.tracks) do
		local clamped = {}
		for i, note in ipairs(t.notes) do
			clamped[i] = {
				step = note.step,
				note = note.note,
				length = note.length,
				velocity = Utils.clamp(note.velocity or 1, lo, hi),
			}
		end
		t.track:clearNotes()
		t.track:setNotes(clamped)
	end
end

-- Background-music selection, keyed off Config.MUSIC_ENABLED/MUSIC_SONG so
-- every caller (main.lua's boot logic and system-menu "Music" checkmark,
-- SettingsScene's Song row) shares one source of truth instead of each
-- reimplementing "how to start/stop a song".

-- Where bundled .mid files live -- compiled into the .pdx from
-- source/assets/songs.
MidiPlayer.SONGS_DIR = "assets/songs"

-- Bundled resources are read-only and can't change mid-session, so this
-- scans MidiPlayer.SONGS_DIR once and caches the result.
local songFiles = nil

-- Sorted list of .mid filenames under MidiPlayer.SONGS_DIR (bare filenames,
-- suitable for Config.MUSIC_SONG / selectSong below).
---@return string[]
function MidiPlayer.listSongs()
	if songFiles then return songFiles end
	songFiles = {}
	local files = playdate.file.listFiles(MidiPlayer.SONGS_DIR) or {}
	for _, name in ipairs(files) do
		if name:match("%.mid$") then
			songFiles[#songFiles + 1] = name
		end
	end
	table.sort(songFiles)
	return songFiles
end

-- Selects `name` (a filename from listSongs(), or nil for "no song") as
-- Config.MUSIC_SONG. If music is enabled (Config.MUSIC_ENABLED), also loads
-- and plays it immediately (or just stops, for nil) so picking a song
-- previews it; if disabled, only records the choice -- setEnabled(true)
-- picks it up later.
---@param name string|nil
function MidiPlayer.selectSong(name)
	Config.MUSIC_SONG = name
	if not Config.MUSIC_ENABLED then return end
	if name then
		MidiPlayer.load({ path = MidiPlayer.SONGS_DIR .. "/" .. name })
		MidiPlayer.play()
	else
		MidiPlayer.stop()
	end
end

-- Turns background music on/off, syncing Config.MUSIC_ENABLED -- shared by
-- the system-menu "Music" checkmark (main.lua) and anything else that wants
-- to mute/unmute. Off stops playback without forgetting Config.MUSIC_SONG;
-- on (re)loads and plays it, if one is selected.
---@param enabled boolean
function MidiPlayer.setEnabled(enabled)
	Config.MUSIC_ENABLED = enabled
	if enabled then
		MidiPlayer.selectSong(Config.MUSIC_SONG)
	else
		MidiPlayer.stop()
	end
end

-- Called once at boot (main.lua): picks the first bundled song
-- (alphabetically) as the default if none is already selected, then plays
-- it if Config.MUSIC_ENABLED. A no-op if no songs are bundled.
function MidiPlayer.playDefault()
	if not Config.MUSIC_SONG then
		Config.MUSIC_SONG = MidiPlayer.listSongs()[1]
	end
	if Config.MUSIC_ENABLED then
		MidiPlayer.selectSong(Config.MUSIC_SONG)
	end
end
