-- run_all.lua
-- Entry point for tests/run.sh. Loads the playdate/Config/Utils mocks, then
-- every test_*.lua file below, then hands off to luaunit's runner. Expects
-- to be run from the repo root (tests/run.sh cd's there first) so these
-- relative paths resolve.

dofile("tests/support/mock_playdate.lua")
lu = dofile("tests/vendor/luaunit.lua")

local testFiles = {
	"tests/test_utils.lua",
	"tests/test_config_upgrades.lua",
}
for _, path in ipairs(testFiles) do
	dofile(path)
end

os.exit(lu.LuaUnit.run())
