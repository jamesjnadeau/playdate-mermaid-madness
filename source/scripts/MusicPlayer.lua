-- MusicPlayer.lua
-- Plays a song's pre-rendered ADPCM .wav pieces via playdate.sound.fileplayer.
-- Songs are rendered offline (tools/render-song.sh, fluidsynth + ffmpeg)
-- into a directory of ~1-minute pieces rather than one big file, so booting
-- the game only has to open the first piece before starting playback --
-- fileplayer streams from flash, so even a single big file wouldn't block
-- long, but splitting keeps any one load small and lets later pieces be
-- rendered/added independently. play() advances piece-to-piece via
-- setFinishCallback, looping back to the first piece after the last.
--
-- Replaces the earlier MidiPlayer.lua, which synthesized playback live from
-- a .mid file note-by-note (see git history) -- pre-rendering trades that
-- approach's synthesized-instrument flexibility for real sampled audio and
-- a much cheaper runtime.

import "scripts/Config"

local snd <const> = playdate.sound

---@class MusicPlayer
---@field player _FilePlayer
---@field song string|nil currently loaded song (a subdirectory name under MusicPlayer.SONGS_DIR)
---@field pieces string[] sorted piece paths for the loaded song
---@field pieceIndex integer index into pieces of the piece currently loaded in `player`; 0 if none
---@field playing boolean
MusicPlayer = {
	player = snd.fileplayer.new(),
	song = nil,
	pieces = {},
	pieceIndex = 0,
	playing = false,
}

-- Loads piece `index` of the current song into `player` and starts it.
-- Doesn't touch MusicPlayer.playing -- callers (play(), the finish
-- callback) are responsible for that.
---@param index integer
local function playPiece(index)
	MusicPlayer.pieceIndex = index
	MusicPlayer.player:load(MusicPlayer.pieces[index])
	MusicPlayer.applyVolume()
	MusicPlayer.player:play()
end

-- Fires when a piece finishes playing on its own (not from an explicit
-- stop() -- guarded by MusicPlayer.playing, same pattern as MidiPlayer's
-- onFinish had). Advances to the next piece, wrapping back to the first
-- after the last so the song loops.
local function onFinish()
	if MusicPlayer.playing and #MusicPlayer.pieces > 0 then
		playPiece((MusicPlayer.pieceIndex % #MusicPlayer.pieces) + 1)
	end
end
MusicPlayer.player:setFinishCallback(onFinish)

-- Stops playback. Safe to call with nothing loaded or already stopped.
function MusicPlayer.stop()
	if MusicPlayer.playing then
		MusicPlayer.playing = false -- clear first so onFinish doesn't advance
		MusicPlayer.player:stop()
	end
end

-- Loads `songName` (a subdirectory of MusicPlayer.SONGS_DIR, or nil for "no
-- song"), stopping whatever's currently loaded. Does not start playback;
-- call play() once loaded.
---@param songName string|nil
function MusicPlayer.load(songName)
	MusicPlayer.stop()
	MusicPlayer.song = songName
	MusicPlayer.pieces = {}
	MusicPlayer.pieceIndex = 0
	if songName then
		local dir = MusicPlayer.SONGS_DIR .. "/" .. songName
		for _, name in ipairs(playdate.file.listFiles(dir) or {}) do
			if name:match("%.wav$") then
				MusicPlayer.pieces[#MusicPlayer.pieces + 1] = dir .. "/" .. name
			end
		end
		table.sort(MusicPlayer.pieces)
	end
end

-- Starts (or restarts, if stopped) the currently loaded song at its first
-- piece, looping indefinitely. No-op if nothing is loaded or it's already
-- playing.
function MusicPlayer.play()
	if not MusicPlayer.playing and #MusicPlayer.pieces > 0 then
		MusicPlayer.playing = true
		playPiece(1)
	end
end

-- Pushes Config.MUSIC_VOLUME to the currently-loaded piece. Called
-- automatically by playPiece() (so a volume change while stopped still
-- takes effect on the next play()); call again any time Config.MUSIC_VOLUME
-- changes at runtime (e.g. from SettingsScene) to make the change audible
-- immediately. Safe to call with nothing loaded.
function MusicPlayer.applyVolume()
	MusicPlayer.player:setVolume(Config.MUSIC_VOLUME)
end

-- Background-music selection, keyed off Config.MUSIC_ENABLED/MUSIC_SONG so
-- every caller (main.lua's boot logic and system-menu "Music" checkmark,
-- SettingsScene's Song row) shares one source of truth instead of each
-- reimplementing "how to start/stop a song".

-- Where bundled songs live -- each a subdirectory of .wav pieces, compiled
-- into the .pdx from source/assets/songs (see tools/render-song.sh).
MusicPlayer.SONGS_DIR = "assets/songs"

-- Bundled resources are read-only and can't change mid-session, so this
-- scans MusicPlayer.SONGS_DIR once and caches the result.
local songNames = nil

-- Sorted list of song subdirectory names under MusicPlayer.SONGS_DIR
-- (suitable for Config.MUSIC_SONG / selectSong below).
---@return string[]
function MusicPlayer.listSongs()
	if songNames then return songNames end
	songNames = {}
	local files = playdate.file.listFiles(MusicPlayer.SONGS_DIR) or {}
	for _, name in ipairs(files) do
		if name:sub(-1) == "/" then
			songNames[#songNames + 1] = name:sub(1, -2)
		end
	end
	table.sort(songNames)
	return songNames
end

-- Selects `name` (a song from listSongs(), or nil for "no song") as
-- Config.MUSIC_SONG. If music is enabled (Config.MUSIC_ENABLED), also loads
-- and plays it immediately (or just stops, for nil) so picking a song
-- previews it; if disabled, only records the choice -- setEnabled(true)
-- picks it up later.
---@param name string|nil
function MusicPlayer.selectSong(name)
	Config.MUSIC_SONG = name
	if not Config.MUSIC_ENABLED then return end
	MusicPlayer.load(name)
	if name then
		MusicPlayer.play()
	end
end

-- Turns background music on/off, syncing Config.MUSIC_ENABLED -- shared by
-- the system-menu "Music" checkmark (main.lua) and anything else that wants
-- to mute/unmute. Off stops playback without forgetting Config.MUSIC_SONG;
-- on (re)loads and plays it, if one is selected.
---@param enabled boolean
function MusicPlayer.setEnabled(enabled)
	Config.MUSIC_ENABLED = enabled
	if enabled then
		MusicPlayer.selectSong(Config.MUSIC_SONG)
	else
		MusicPlayer.stop()
	end
end

-- Called once at boot (main.lua): picks the first bundled song
-- (alphabetically) as the default if none is already selected, then plays
-- it if Config.MUSIC_ENABLED. A no-op if no songs are bundled.
function MusicPlayer.playDefault()
	if not Config.MUSIC_SONG then
		Config.MUSIC_SONG = MusicPlayer.listSongs()[1]
	end
	if Config.MUSIC_ENABLED then
		MusicPlayer.selectSong(Config.MUSIC_SONG)
	end
end
