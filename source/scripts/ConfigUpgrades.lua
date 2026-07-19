-- ConfigUpgrades.lua
-- Upgrade pool offered by UpgradeSelectScene after each level clear, split
-- out of Config.lua like ConfigEnemy.lua -- still just adds fields onto the
-- shared global Config table -- import "scripts/Config" first (this file
-- assumes Config.SHIP_ACCEL etc. already exist).

---------------
-- Upgrades --
---------------
-- Each entry names the Config field it modifies (configKey) and how: either
-- a `multiplier` (new = old * multiplier) or a `delta` (new = old + delta),
-- never both. `minValue`/`maxValue` optionally clamp the result so picking
-- the same upgrade repeatedly across a run can't push a stat past a sane
-- bound. `format` renders a value for the before/after display shown by
-- UpgradeSelectScene once an upgrade is chosen.
---@class Config.Upgrade
---@field id string
---@field title string
---@field description string
---@field configKey string name of the Config field this upgrade modifies
---@field multiplier? number new = old * multiplier (mutually exclusive with delta)
---@field delta? number new = old + delta (mutually exclusive with multiplier)
---@field minValue? number clamps the result
---@field maxValue? number clamps the result
---@field format fun(v: number): string
---@field available? fun(): boolean if present, only offered by UpgradeSelectScene's pickUpgrades when this returns true (e.g. a prerequisite upgrade already installed); omitted means always offered. UpgradeTestScene deliberately ignores this -- see its header comment.

---@type Config.Upgrade[]
Config.UPGRADES = {
	{
		id = "ship_accel",
		title = "Swift Rigging",
		description = "Ship accelerates faster, reaching top speed sooner.",
		configKey = "SHIP_ACCEL",
		multiplier = 1.25,
		format = function(v) return math.floor(v) .. " px/s" end,
	},
	{
		id = "shot_damage",
		title = "Sharpened Prongs",
		description = "Trident hits deal more damage, downing tougher enemies faster.",
		configKey = "TRIDENT_DAMAGE",
		delta = 1,
		format = function(v) return math.floor(v) .. " dmg" end,
	},
	{
		id = "max_health",
		title = "Extra Heart",
		description = "Adds an additional heart of max health, shown in the HUD.",
		configKey = "SHIP_MAX_HEALTH",
		delta = 1,
		format = function(v) return math.floor(v) .. " hearts" end,
	},
	{
		id = "collision_radius",
		title = "Slim Hull",
		description = "Smaller collision radius makes the ship easier to dodge with.",
		configKey = "SHIP_COLLIDE_RADIUS",
		multiplier = 0.85,
		minValue = 8,
		format = function(v) return math.floor(v) .. " px" end,
	},
	{
		id = "charge_rate",
		title = "Quick Draw",
		description = "Trident charges to full accuracy faster.",
		configKey = "TRIDENT_CHARGE_RATE",
		multiplier = 1.25,
		format = function(v) return string.format("%.2f", v) .. " chg/s" end,
	},
	{
		id = "autofire_cannon",
		title = "Autofire Cannon",
		description = "Mounts a cannon that fires on its own at the nearest enemy in range.",
		configKey = "AUTOFIRE_CANNON_UNLOCKED",
		delta = 1,
		maxValue = 5,
		format = function(v) return v > 0 and "Installed" or "Not installed" end,
	},
	{
		id = "autofire_cannon_delay",
		title = "Rapid Autocannon",
		description = "Shortens the delay between autofire cannon shots. Requires the Autofire Cannon.",
		configKey = "AUTOFIRE_CANNON_DELAY",
		delta = -Config.AUTOFIRE_CANNON_DELAY_STEP,
		minValue = 0.1,
		available = function() return Config.AUTOFIRE_CANNON_UNLOCKED > 0 end,
		format = function(v) return string.format("%.2f", v) .. " s" end,
	},
}

-- Applies `upgrade` to the live Config table and returns the before/after
-- values so the caller (UpgradeSelectScene) can render a "was -> now"
-- summary. Config fields touched here (SHIP_ACCEL, SHIP_COLLIDE_RADIUS,
-- TRIDENT_CHARGE_RATE, TRIDENT_DAMAGE) are all read fresh from Config every
-- frame/use elsewhere in the game, so mutating them here takes effect
-- immediately -- no Ship/Player instance state needs to be touched.
---@param upgrade Config.Upgrade
---@return number old
---@return number new
function Config.applyUpgrade(upgrade)
	local old = Config[upgrade.configKey]
	local new = old
	if upgrade.multiplier then
		new = old * upgrade.multiplier
	elseif upgrade.delta then
		new = old + upgrade.delta
	end
	if upgrade.minValue and new < upgrade.minValue then new = upgrade.minValue end
	if upgrade.maxValue and new > upgrade.maxValue then new = upgrade.maxValue end
	Config[upgrade.configKey] = new
	return old, new
end

return Config
