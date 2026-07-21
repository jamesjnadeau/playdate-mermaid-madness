-- ConfigUpgrades.lua
-- Upgrade pool offered by UpgradeSelectScene after each level clear, split
-- out of Config.lua like ConfigEnemy.lua -- still just adds fields onto the
-- shared global Config table -- import "scripts/utilities/Config" first (this file
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
---@field descriptionFor? fun(current: number): string if present, used instead of the static `description` to render text specific to the current Config[configKey] value (e.g. "Autofire Cannon" reads differently once a cannon is already mounted) -- see Config.upgradeDescription.

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
		descriptionFor = function(current)
			if current <= 0 then
				return "Mounts a cannon that fires on its own at the nearest enemy in range."
			end
			return "Adds another autofire cannon -- fires an extra shot at the nearest enemy every volley."
		end,
		configKey = "AUTOFIRE_CANNON_UNLOCKED",
		delta = 1,
		maxValue = 5,
		format = function(v)
			local count = math.floor(v)
			return count > 0 and (count .. (count == 1 and " cannon" or " cannons")) or "Not installed"
		end,
	},
	{
		id = "autofire_cannon_delay",
		title = "Rapid Autocannon",
		description = "Shortens the delay between autofire cannon shots. Requires the Autofire Cannon.",
		configKey = "AUTOFIRE_CANNON_DELAY",
		delta = -Config.AUTOFIRE_CANNON_DELAY_STEP,
		minValue = 0.5,
		available = function() return Config.AUTOFIRE_CANNON_UNLOCKED > 0 end,
		format = function(v) return string.format("%.2f", v) .. " s" end,
	},
	{
		id = "trident_count",
		title = "Twin Tridents",
		description = "Fires an additional trident, fanned out from the aimed shot. Stacks up to a limit.",
		configKey = "TRIDENT_COUNT",
		delta = 1,
		maxValue = Config.TRIDENT_COUNT_MAX,
		format = function(v) return math.floor(v) .. (math.floor(v) == 1 and " trident" or " tridents") end,
	},
	{
		id = "storm_cloud",
		title = "Storm Cloud",
		description = "Summons a storm cloud that drifts toward enemies, damaging any it passes over. Stacks -- each pick adds another cloud.",
		configKey = "STORM_CLOUD_COUNT",
		delta = 1,
		format = function(v) return math.floor(v) .. (math.floor(v) == 1 and " cloud" or " clouds") end,
	},
	{
		id = "storm_cloud_damage",
		title = "Charged Storm",
		description = "Storm clouds deal more damage per tick. Requires a Storm Cloud.",
		configKey = "STORM_CLOUD_DAMAGE",
		delta = 1,
		available = function() return Config.STORM_CLOUD_COUNT > 0 end,
		format = function(v) return math.floor(v) .. " dmg" end,
	},
	{
		id = "storm_cloud_speed",
		title = "Squalling Winds",
		description = "Storm clouds drift faster toward enemies. Requires a Storm Cloud.",
		configKey = "STORM_CLOUD_SPEED",
		multiplier = 1.25,
		available = function() return Config.STORM_CLOUD_COUNT > 0 end,
		format = function(v) return math.floor(v) .. " px/s" end,
	},
	{
		id = "ammo_max",
		title = "Bigger Quiver",
		description = "Carry more tridents before running dry.",
		configKey = "AMMO_MAX",
		delta = 4,
		maxValue = Config.AMMO_MAX_CAP,
		format = function(v) return math.floor(v) .. " ammo" end,
	},
	{
		id = "ammo_regen",
		title = "Quick Reload",
		description = "Ammo replenishes faster.",
		configKey = "AMMO_REGEN_INTERVAL",
		delta = -Config.AMMO_REGEN_INTERVAL_STEP,
		minValue = 0.5,
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

-- Resolves the description to show for `upgrade` given the current value at
-- Config[upgrade.configKey] -- most upgrades have a fixed description, but
-- ones with a `descriptionFor` (e.g. "Autofire Cannon", which reads
-- differently once a cannon is already mounted) render text specific to
-- that value instead.
---@param upgrade Config.Upgrade
---@return string
function Config.upgradeDescription(upgrade)
	if upgrade.descriptionFor then
		return upgrade.descriptionFor(Config[upgrade.configKey])
	end
	return upgrade.description
end

-- Maps a list of Config.Upgrade entries to the { title, description } shape
-- MenuCard.build expects, resolving each entry's description via
-- Config.upgradeDescription. UpgradeSelectScene and UpgradeTestScene call
-- this instead of passing Config.Upgrade entries to MenuCard directly, so a
-- dynamic descriptionFor is reflected on screen.
---@param upgrades Config.Upgrade[]
---@return { title: string, description: string }[]
function Config.upgradeMenuItems(upgrades)
	local items = {}
	for i, upgrade in ipairs(upgrades) do
		items[i] = { title = upgrade.title, description = Config.upgradeDescription(upgrade) }
	end
	return items
end

return Config
