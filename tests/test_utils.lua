-- test_utils.lua
-- Covers the pure math helpers in source/scripts/Utils.lua. Loaded by
-- tests/run_all.lua, which dofiles tests/support/mock_playdate.lua first so
-- the global `Utils` and luaunit's `lu` are already in place.

TestUtils = {}

function TestUtils:testClamp()
	lu.assertEquals(Utils.clamp(5, 0, 10), 5)
	lu.assertEquals(Utils.clamp(-5, 0, 10), 0)
	lu.assertEquals(Utils.clamp(15, 0, 10), 10)
end

function TestUtils:testWrapDeg()
	lu.assertEquals(Utils.wrapDeg(0), 0)
	lu.assertEquals(Utils.wrapDeg(360), 0)
	lu.assertEquals(Utils.wrapDeg(370), 10)
	lu.assertEquals(Utils.wrapDeg(-10), 350)
	lu.assertEquals(Utils.wrapDeg(-370), 350)
end

function TestUtils:testAngleDiff()
	lu.assertEquals(Utils.angleDiff(0, 90), 90)
	lu.assertEquals(Utils.angleDiff(90, 0), -90)
	lu.assertEquals(Utils.angleDiff(350, 10), 20)
	lu.assertEquals(Utils.angleDiff(10, 350), -20)
	lu.assertEquals(Utils.angleDiff(0, 180), 180)
end

function TestUtils:testDist()
	lu.assertEquals(Utils.dist(0, 0, 3, 4), 5)
	lu.assertEquals(Utils.dist(1, 1, 1, 1), 0)
end

function TestUtils:testDist2()
	lu.assertEquals(Utils.dist2(0, 0, 3, 4), 25)
end

function TestUtils:testAngleTo()
	lu.assertAlmostEquals(Utils.angleTo(0, 0, 1, 0), 0, 1e-9)
	lu.assertAlmostEquals(Utils.angleTo(0, 0, 0, 1), 90, 1e-9)
	lu.assertAlmostEquals(Utils.angleTo(0, 0, -1, 0), 180, 1e-9)
end

function TestUtils:testHeadingUnitVector()
	local hx, hy = Utils.heading(0)
	lu.assertAlmostEquals(hx, 1, 1e-9)
	lu.assertAlmostEquals(hy, 0, 1e-9)

	local hx2, hy2 = Utils.heading(90)
	lu.assertAlmostEquals(hx2, 0, 1e-9)
	lu.assertAlmostEquals(hy2, 1, 1e-9)
end

function TestUtils:testDeg2radRad2degRoundTrip()
	lu.assertAlmostEquals(Utils.rad2deg(Utils.deg2rad(123)), 123, 1e-9)
end
