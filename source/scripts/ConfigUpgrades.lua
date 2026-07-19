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
