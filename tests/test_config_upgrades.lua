-- test_config_upgrades.lua
-- Covers Config.applyUpgrade (source/scripts/ConfigUpgrades.lua) -- the
-- multiplier/delta/clamp math UpgradeSelectScene relies on to mutate Config
-- and compute the before/after stat values it displays -- plus a sanity
-- check that every entry in Config.UPGRADES is well-formed (catches typo'd
-- configKeys or a bad format() before they'd surface as a blank/garbled
-- stat in-game).

TestConfigUpgrades = {}

-- SHIP_ACCEL/TRIDENT_DAMAGE are real Config fields; snapshot and restore
-- them so mutating tests don't leak state into each other or into
-- testUpgradePoolEntriesAreWellFormed.
function TestConfigUpgrades:setUp()
	self.savedShipAccel = Config.SHIP_ACCEL
	self.savedTridentDamage = Config.TRIDENT_DAMAGE
end

function TestConfigUpgrades:tearDown()
	Config.SHIP_ACCEL = self.savedShipAccel
	Config.TRIDENT_DAMAGE = self.savedTridentDamage
	Config.TEST_STAT = nil
end

function TestConfigUpgrades:testMultiplierIncreasesValue()
	local old, new = Config.applyUpgrade({ configKey = "SHIP_ACCEL", multiplier = 1.25 })
	lu.assertEquals(old, self.savedShipAccel)
	lu.assertEquals(new, old * 1.25)
	lu.assertEquals(Config.SHIP_ACCEL, new)
end

function TestConfigUpgrades:testDeltaAddsValue()
	local old, new = Config.applyUpgrade({ configKey = "TRIDENT_DAMAGE", delta = 1 })
	lu.assertEquals(old, self.savedTridentDamage)
	lu.assertEquals(new, old + 1)
	lu.assertEquals(Config.TRIDENT_DAMAGE, new)
end

function TestConfigUpgrades:testMinValueClamp()
	Config.TEST_STAT = 10
	local old, new = Config.applyUpgrade({ configKey = "TEST_STAT", multiplier = 0.1, minValue = 5 })
	lu.assertEquals(old, 10)
	lu.assertEquals(new, 5) -- 10 * 0.1 = 1, clamped up to minValue
end

function TestConfigUpgrades:testMaxValueClamp()
	Config.TEST_STAT = 10
	local old, new = Config.applyUpgrade({ configKey = "TEST_STAT", delta = 100, maxValue = 20 })
	lu.assertEquals(old, 10)
	lu.assertEquals(new, 20)
end

function TestConfigUpgrades:testUpgradePoolEntriesAreWellFormed()
	lu.assertTrue(#Config.UPGRADES > 0)
	for _, upgrade in ipairs(Config.UPGRADES) do
		lu.assertNotNil(upgrade.id)
		lu.assertNotNil(upgrade.title)
		lu.assertNotNil(upgrade.description)
		lu.assertNotNil(Config[upgrade.configKey],
			"Config." .. tostring(upgrade.configKey) .. " must exist for upgrade " .. tostring(upgrade.id))
		lu.assertTrue((upgrade.multiplier ~= nil) ~= (upgrade.delta ~= nil),
			"upgrade " .. tostring(upgrade.id) .. " must set exactly one of multiplier/delta")
		lu.assertNotNil(upgrade.format)
		local ok = pcall(upgrade.format, Config[upgrade.configKey])
		lu.assertTrue(ok, "format() errored for upgrade " .. tostring(upgrade.id))
	end
end
