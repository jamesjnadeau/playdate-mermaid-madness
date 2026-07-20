-- SoundBank.lua
-- Loads every compiled sound file directly under a folder and plays a random
-- one on demand -- e.g. a handful of enemy-hit variations (see
-- tools/render-sfx.sh for how raw audio in art-src/sounds gets into
-- source/assets/sounds in the first place) so repeated hits don't all sound
-- identical. Uses playdate.sound.sampleplayer, which decompresses the whole
-- clip into memory up front -- appropriate for short one-shot SFX, unlike
-- MusicPlayer.lua's streamed fileplayer used for full songs.

import "scripts/Config"

local snd <const> = playdate.sound

---@class SoundBank : _Object
---@field dir string folder (under assets/) this bank was loaded from
---@field players _SamplePlayer[] one sampleplayer per sound file found in `dir`
---@field lastIndex integer|nil index played last time playRandom() was called
SoundBank = class("SoundBank").extends() or SoundBank

-- Loads every compiled sample file directly under `dir` (e.g.
-- "assets/sounds/enemy/hit") into its own sampleplayer. Does not recurse
-- into subdirectories -- `dir` should hold nothing but sound files.
---@param dir string
function SoundBank:init(dir)
	SoundBank.super.init(self)
	self.dir = dir
	self.players = {}
	self.lastIndex = nil
	for _, name in ipairs(playdate.file.listFiles(dir) or {}) do
		-- pdc compiles each .wav into a .pda (see tools/render-song.sh's
		-- header for the same convention); sampleplayer.new(), like
		-- fileplayer:load() and gfx.image.new(), wants the path with no
		-- extension.
		local base = name:match("^(.*)%.pda$")
		if base then
			local player = snd.sampleplayer.new(dir .. "/" .. base)
			if player then
				player:setVolume(Config.SOUND_SFX_VOLUME)
				self.players[#self.players + 1] = player
			end
		end
	end
end

-- Plays one of this bank's sounds at random. If the bank has more than one
-- sound, avoids repeating whichever one played last time so the same clip
-- doesn't fire twice in a row. No-op if the bank is empty (e.g. an
-- unpopulated or not-yet-converted folder).
function SoundBank:playRandom()
	local count = #self.players
	if count == 0 then return end
	local index = math.random(count)
	if count > 1 and index == self.lastIndex then
		index = (index % count) + 1
	end
	self.lastIndex = index
	self.players[index]:play()
end

-- Sets playback volume (0-1) for every sound in the bank -- call after
-- Config.SOUND_SFX_VOLUME changes at runtime, mirroring
-- MusicPlayer.applyVolume.
---@param volume number
function SoundBank:setVolume(volume)
	for _, player in ipairs(self.players) do
		player:setVolume(volume)
	end
end
