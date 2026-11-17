-- Rules for QuestData's conversion of a spot from one map to another (QD:MapToMap in QuestData.lua),
-- against the stand-in maps of tests/lib/questworld.lua (each with its continent and north-west corner).
-- Source: docs/superpowers/specs/2026-11-17-arrow-other-zones-and-layout-removal.md section 2,
-- "How the direction is worked out", "When it does not point" and "Cost".
-- Fresh client and addon per test (QuestieDB itself is loaded once per run and only read).
--
-- Skipped, with a notice, when the QuestieDB release is not available (offline).
local T = ...
if not T.questieDB then return { skip = "QuestieDB is not available" } end
local test, eq, check = T.test, T.eq, T.check
local QW = dofile(T.root .. "/tests/lib/questworld.lua")

local KNOWN_FAILURES = {
}

-- The quest arrow on (so the quest data is acquired), the player in Elwynn Forest.
-- change(c) runs after the maps are set up and before the addon loads.
local function newClient(change)
    local c, PE = T.new({ quest = true, on = { "questArrow" }, setup = function(c)
        QW.setup(c, { quests = { { id = QW.MANY } }, focus = QW.MANY })
        if change then change(c) end
    end })
    c:advance(1.2)
    return c, PE
end

-- Expected values worked out here from the maps' corners, not by the addon.
local function expected(c, from, x, y, to)
    local a, b = c.world.maps[from], c.world.maps[to]
    local north, west = a.top - y * a.height, a.left - x * a.width
    return (b.left - west) / b.width, (b.top - north) / b.height
end

local function close(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local function calls(c) return #c:callsTo("C_Map.GetWorldPosFromMapPos") end

-- Spec: "Same map in and out returns x, y without any game call" (the plan's interface for QD:MapToMap).
test("map convert: the same map returns the position unchanged", function()
    local c, PE = newClient()
    local before = calls(c)
    eq({ PE.QuestData:MapToMap(QW.HOME, 0.3, 0.7, QW.HOME) }, { 0.3, 0.7 })
    eq(calls(c), before, "calls to C_Map.GetWorldPosFromMapPos")
end)

-- Spec: "With the conversion of the player's map and of the spot's map, the spot gets a position on the
-- player's map (it may lie outside the map's edges)".
test("map convert: Duskwood to Elwynn matches the corners' arithmetic", function()
    local c, PE = newClient()
    local ex, ey = expected(c, QW.AWAY, 0.5, 0.5, QW.HOME)
    local x, y = PE.QuestData:MapToMap(QW.AWAY, 0.5, 0.5, QW.HOME)
    check(close(x, ex) and close(y, ey), "got " .. tostring(x) .. "," .. tostring(y) .. ", expected " .. ex .. "," .. ey)
    check(y > 1, "Duskwood lies south of Elwynn Forest, so y should be above 1: " .. y)
    c:assertClean("convert")
end)

-- Spec: "No assumption is made about which way the continent's axes run."
test("map convert: world components the other way round still convert", function()
    local c, PE = newClient(function(c) c.world.mapWorldSwap = true end)
    local ex, ey = expected(c, QW.AWAY, 0.5, 0.5, QW.HOME)
    local x, y = PE.QuestData:MapToMap(QW.AWAY, 0.5, 0.5, QW.HOME)
    check(close(x, ex) and close(y, ey), "got " .. tostring(x) .. "," .. tostring(y) .. ", expected " .. ex .. "," .. ey)
end)

-- Spec "When it does not point": "the spot's zone is on another continent".
test("map convert: another continent gives nil", function()
    local c, PE = newClient()
    eq(PE.QuestData:MapToMap(QW.MULGORE, 0.5, 0.5, QW.HOME), nil)
    c:assertClean("continent")
end)

-- Spec: "the game gives no conversion for either map"; "A failed conversion is tried again after the next
-- zone change."
test("map convert: a map the game cannot convert gives nil, and is tried again after a zone change", function()
    local c, PE = newClient()
    local QD = PE.QuestData
    local dusk = c.world.maps[QW.AWAY]
    dusk.continent = nil
    eq(QD:MapToMap(QW.AWAY, 0.5, 0.5, QW.HOME), nil)
    dusk.continent = 0
    eq(QD:MapToMap(QW.AWAY, 0.5, 0.5, QW.HOME), nil, "the failure was not kept until a zone change")
    c:fire("ZONE_CHANGED_NEW_AREA")
    c:advance(1.5)
    local x, y = QD:MapToMap(QW.AWAY, 0.5, 0.5, QW.HOME)
    check(type(x) == "number" and type(y) == "number", "not tried again after the zone change")
    c:assertClean("retry")
end)

-- Spec: "a map's conversion does not fit its known size (north-south span against the map's height,
-- east-west against its width, within 5 %)".
test("map convert: a conversion that does not fit the map's size gives nil", function()
    local c, PE = newClient()
    -- Duskwood's size reads 5000 yards wide while the game's conversion still spans 2700 (the stand-in
    -- works out both from one width, so the size alone is changed here).
    local Map = c.env.C_Map
    local realSize = Map.GetMapWorldSize
    Map.GetMapWorldSize = function(mapID)
        if mapID == QW.AWAY then return 5000, c.world.maps[QW.AWAY].height end
        return realSize(mapID)
    end
    eq(PE.QuestData:MapToMap(QW.AWAY, 0.5, 0.5, QW.HOME), nil)
end)

-- Spec: "a map whose size cannot be read does not fit".
test("map convert: a map whose size cannot be read gives nil", function()
    local c, PE = newClient()
    c.world.maps[QW.AWAY].width, c.world.maps[QW.AWAY].height = 0, 0
    eq(PE.QuestData:MapToMap(QW.AWAY, 0.5, 0.5, QW.HOME), nil)
    c:assertClean("no size")
end)

-- Spec: "the game gives no conversion for either map, or the call fails" (CLAUDE.md: every value read is
-- checked for secrets; every new game call is guarded).
test("map convert: a secret value or an error from the game gives nil and logs no error", function()
    local c, PE = newClient()
    local QD = PE.QuestData
    c.world.mapWorldSecret = true
    eq(QD:MapToMap(QW.AWAY, 0.5, 0.5, QW.HOME), nil, "secret")
    c.world.mapWorldSecret = false
    c.env.C_Map.GetWorldPosFromMapPos = function() error("the game failed") end
    c:fire("ZONE_CHANGED_NEW_AREA")             -- the failures above are tried again
    c:advance(1.5)
    eq(QD:MapToMap(QW.AWAY, 0.5, 0.5, QW.HOME), nil, "error")
    c:assertClean("secret and error")
end)

-- Spec "Cost": "The conversion is two game calls per map, once."
test("map convert: each map is asked twice, once", function()
    local c, PE = newClient()
    local QD = PE.QuestData
    local before = calls(c)
    for i = 1, 3 do
        check(QD:MapToMap(QW.AWAY, 0.1 * i, 0.2 * i, QW.HOME), "conversion " .. i .. " failed")
    end
    eq(calls(c) - before, 4, "calls to C_Map.GetWorldPosFromMapPos")
end)

return { known = KNOWN_FAILURES }
