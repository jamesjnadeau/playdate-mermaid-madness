#!/usr/bin/env bash
# Scaffolds a new Enemy subclass: source/scripts/Enemy<Name>.lua plus a
# matching Config.ENEMY_<NAME>_* tuning block appended to ConfigEnemy.lua.
# Mirrors EnemySwordfish.lua / its ConfigEnemy.lua section.
#
# Usage: tools/new-enemy.sh <Name>
#   e.g. tools/new-enemy.sh Piranha       -> EnemyPiranha.lua, Config.ENEMY_PIRANHA_*
#   e.g. tools/new-enemy.sh SeaSerpent    -> EnemySeaSerpent.lua, Config.ENEMY_SEA_SERPENT_*
set -euo pipefail

if [ $# -ne 1 ]; then
	echo "Usage: $0 <Name>" >&2
	echo "  e.g. $0 Piranha" >&2
	exit 1
fi

RAW="$1"
if ! [[ "$RAW" =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
	echo "Error: name must be alphanumeric, starting with a letter (got '$RAW')" >&2
	exit 1
fi

NAME="$(tr '[:lower:]' '[:upper:]' <<< "${RAW:0:1}")${RAW:1}"           # PascalCase (forces first letter upper)
SNAKE="$(sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' <<< "$NAME" | tr '[:lower:]' '[:upper:]')"  # SCREAMING_SNAKE_CASE
PREFIX="ENEMY_${SNAKE}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/source/scripts"
ENEMY_FILE="$SCRIPTS/Enemy${NAME}.lua"
CONFIG_FILE="$SCRIPTS/ConfigEnemy.lua"

if [ -f "$ENEMY_FILE" ]; then
	echo "Error: $ENEMY_FILE already exists" >&2
	exit 1
fi

if grep -q "Config\.${PREFIX}_" "$CONFIG_FILE"; then
	echo "Error: $CONFIG_FILE already has a ${PREFIX}_ section" >&2
	exit 1
fi

cat > "$ENEMY_FILE" <<LUA
-- Enemy${NAME}.lua
-- TODO: describe what makes this Enemy variant distinct.
-- All tuning lives in Config.${PREFIX}_* (see ConfigEnemy.lua) -- Enemy:update/draw
-- already read from instance fields, so this subclass just points those
-- fields at its own config values.

import "scripts/Config"
import "scripts/ConfigEnemy"
import "scripts/Utils"
import "scripts/Enemy"

class("Enemy${NAME}").extends(Enemy)

-- Unlocked starting this level (see Config.${PREFIX}_MIN_LEVEL /
-- Enemy.minLevel / GameScene:spawnEnemy).
Enemy${NAME}.minLevel = Config.${PREFIX}_MIN_LEVEL

function Enemy${NAME}:init(x, y, heading)
	Enemy${NAME}.super.init(self, x, y, heading)

	self.radius = Config.${PREFIX}_RADIUS
	self.length = Config.${PREFIX}_LENGTH
	self.color = Config.${PREFIX}_COLOR
	self.outlineColor = Config.${PREFIX}_OUTLINE_COLOR
	self.health = Config.${PREFIX}_HEALTH
	self.speed = 0

	self.moveSpeed = Config.${PREFIX}_SPEED
	self.accel = Config.${PREFIX}_ACCEL
	self.turnRateMax = Config.${PREFIX}_TURN_RATE_MAX
	self.turnRateMin = Config.${PREFIX}_TURN_RATE_MIN
	self.turnRateSpeedMultiplier = Config.${PREFIX}_TURN_RATE_SPEED_MULTIPLIER
	self.windMultiplier = Config.${PREFIX}_WIND_MULTIPLIER
	self.eyeOffset = Config.${PREFIX}_EYE_OFFSET
	self.damage = Config.${PREFIX}_DAMAGE

	-- TODO: give it its own hull shape if it should look different from the
	-- base Enemy fan-shaped hull (see EnemySwordfish.lua for an example that
	-- adds a spiked bill).
	local L, B = Config.${PREFIX}_LENGTH, Config.${PREFIX}_BEAM
	self.hull = { L, 0,  -L * 0.7, B,  -L, B * 0.55,  -L, -B * 0.55,  -L * 0.7, -B }
end
LUA

echo "Created $ENEMY_FILE"

CONFIG_BLOCK=$(cat <<LUA
------------------------
-- Enemy: ${NAME} --
------------------------
-- TODO: tune these -- mirrors the base ENEMY_* knobs above so this variant
-- can be adjusted independently (see EnemySwordfish's section for reference).
Config.${PREFIX}_SPEED      = Config.ENEMY_SPEED
Config.${PREFIX}_ACCEL      = Config.ENEMY_ACCEL
Config.${PREFIX}_TURN_RATE_MAX = Config.ENEMY_TURN_RATE_MAX
Config.${PREFIX}_TURN_RATE_MIN = Config.ENEMY_TURN_RATE_MIN
Config.${PREFIX}_TURN_RATE_SPEED_MULTIPLIER = Config.ENEMY_TURN_RATE_SPEED_MULTIPLIER
Config.${PREFIX}_LENGTH     = Config.ENEMY_LENGTH
Config.${PREFIX}_BEAM       = Config.ENEMY_BEAM
Config.${PREFIX}_RADIUS     = Config.${PREFIX}_LENGTH
Config.${PREFIX}_HEALTH     = 1
Config.${PREFIX}_DAMAGE     = Config.ENEMY_DAMAGE
Config.${PREFIX}_WIND_MULTIPLIER = Config.ENEMY_WIND_MULTIPLIER
Config.${PREFIX}_COLOR      = gfx.kColorBlack
Config.${PREFIX}_OUTLINE_COLOR = gfx.kColorWhite
Config.${PREFIX}_EYE_OFFSET = 6
Config.${PREFIX}_MIN_LEVEL  = Config.ENEMY_MIN_LEVEL
LUA
)

awk -v block="$CONFIG_BLOCK" '
	!done && /^return Config/ { print block; print ""; done=1 }
	{ print }
' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo "Appended Config.${PREFIX}_* section to $CONFIG_FILE"

echo
echo "Next steps to wire it in:"
echo "  1. Add 'import \"scripts/Enemy${NAME}\"' to source/main.lua (next to the other Enemy imports)"
echo "  2. Add 'import \"scripts/Enemy${NAME}\"' and Enemy${NAME} to GameScene.enemyTypes in source/scenes/GameScene.lua"
echo "  3. Tune the Config.${PREFIX}_* values in $CONFIG_FILE and give it a distinct hull/look in $ENEMY_FILE"
