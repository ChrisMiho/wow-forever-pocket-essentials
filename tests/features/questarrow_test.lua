-- Rules for the "Quest arrow" (QuestArrow.lua), with real quests from QuestieDB.
-- Sources: QuestArrow.lua's header and comments; docs/DECISIONS.md, part "Quest arrow" of
-- "Decisions made without the maintainer"; docs/superpowers/specs/2026-11-15-fewer-spots-icon-key-reload.md
-- section 2 (the arrow's target). Each test names its source in a comment.
-- Fresh client and addon per test (QuestieDB itself is loaded once per run and only read).
--
-- Skipped, with a notice, when the QuestieDB release is not available (offline).
local T = ...
if not T.questieDB then return { skip = "QuestieDB is not available" } end
local test, eq, check = T.test, T.eq, T.check
local QW = dofile(T.root .. "/tests/lib/questworld.lua")

local KNOWN_FAILURES = {
}

local rad = math.rad

-- One quest log, the player in Elwynn Forest, a given quest focused.
local function newArrow(spec, on)
    spec = spec or {}
    spec.quests = spec.quests or { { id = QW.MANY }, { id = QW.ONE }, { id = QW.ELSEWHERE } }
    if spec.focus == nil and not spec.nofocus then spec.focus = QW.MANY end
    local c, PE = T.new({ quest = true, on = on or { "questArrow" }, setup = function(c) QW.setup(c, spec) end })
    c:advance(1.2)
    return c, PE
end

-- The arrow's frames: the text block, the arrow box, the driver (the frame with the OnUpdate).
local function parts(c)
    local found = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == "QuestArrow.lua" and rec.type == "Frame" then found[#found + 1] = rec end
    end
    eq(#found, 3, "frames made by QuestArrow.lua")
    local display, box, driver = found[1], found[2], found[3]
    local function region(rec, i) return c._state(rec.regions[i]) end
    return {
        display = display, box = box, driver = driver,
        distText = function() return region(display, 1).text end,
        titleText = function() return region(display, 2).text end,
        arrow = function() return region(box, 1) end,
        turn = function() return region(box, 2) end,
    }
end

-- The pin the arrow publishes to the quest data.
local function published(PE) return PE.QuestData:GetArrowPin() end

-- The nearest pin by distance on the map, worked out here from the quest's pins and the map's size
-- in yards (x grows east, y south), not by the arrow's own helper.
local function nearest(c, PE, questID, px, py)
    local map = c.world.player.map
    local m = c.world.maps[map]
    local best, bestD
    for _, p in ipairs(PE.QuestData:GetPinsForQuest(questID)[map]) do
        local dx, dy = (p.x - px) * m.width, (p.y - py) * m.height
        local d = dx * dx + dy * dy
        if not bestD or d < bestD then best, bestD = p, d end
    end
    return best
end

local function placeAt(c, x, y, facing, seconds)
    local p = c.world.player
    p.x, p.y = x, y
    if facing then p.facing = facing end
    c:advance(seconds or 0.3)
end

-- The single spot of quest 6, and a position 0.03 of the map (69 yards) south of it.
local function onePin(c, PE) return PE.QuestData:GetPinsForQuest(QW.ONE)[QW.HOME][1] end
local function focusOne() return { focus = QW.ONE } end

---------------------------------------------------------------------------
-- Which spot
---------------------------------------------------------------------------

-- Header: "A quest is focused and has known places on this map: its nearest pin." Spec section 2:
-- "unchanged choice (nearest of all pins, extra or not)".
test("quest arrow: points at the spot nearest the player (the published pin)", function()
    local c, PE = newArrow(nil, { "questIcons", "questArrow" })   -- icons on: most spots are marked surplus
    QW.check(c, PE)
    local p = c.world.player
    local expected = nearest(c, PE, QW.MANY, p.x, p.y)
    check(published(PE), "no pin published")
    check(rawequal(published(PE), expected), "published pin is at " .. published(PE).x .. "," .. published(PE).y
        .. ", the nearest is at " .. expected.x .. "," .. expected.y)
    eq(parts(c).titleText(), "Wolves Across the Border")
    c:assertClean("nearest")
end)

-- Spec section 2: "Spots are hidden from the icons only (marked, not deleted), so the arrow ... still
-- points at the truly nearest one"; "The arrow's target ... is nearest ... extra or not".
test("quest arrow: after the player moves next to a different spot and a second passes, it points at that one", function()
    local c, PE = newArrow(nil, { "questIcons", "questArrow" })   -- icons on: most spots are marked surplus
    local before = published(PE)
    local pins = PE.QuestData:GetPinsForQuest(QW.MANY)[QW.HOME]
    local target                              -- a surplus spot far from the first choice
    for _, pin in ipairs(pins) do
        local dx, dy = (pin.x - before.x) * QW.WIDTH, (pin.y - before.y) * QW.HEIGHT
        if pin.extra and dx * dx + dy * dy > 400 * 400 then target = pin break end
    end
    check(target, "no surplus spot 400 yards from the first one in this data")
    placeAt(c, target.x + 0.002, target.y + 0.002, nil, 1.5)
    local expected = nearest(c, PE, QW.MANY, target.x + 0.002, target.y + 0.002)
    check(rawequal(expected, target), "test setup: the spot is not the nearest one")
    check(rawequal(published(PE), target), "the arrow still points at the old spot")
    check(not rawequal(published(PE), before))
    c:assertClean("moved")
end)

-- Spec section 2: "It clears it (nil) whenever it stops pointing (... feature off)".
test("quest arrow: the published pin is nil after the arrow is switched off, while icons still hold the data", function()
    local c, PE = newArrow(nil, { "questIcons", "questArrow" })
    check(published(PE), "no pin published while on")
    PE:SetModuleEnabled("questArrow", false)
    c:advance(0.5)
    eq(published(PE), nil)
    eq(PE:GetModuleState("questIcons"), "on")
end)

-- Spec section 2: "... clears it (nil) whenever it stops pointing (no pin ...)". Header: "No quest focused".
test("quest arrow: the published pin is nil after the focus is cleared", function()
    local c, PE = newArrow()
    check(published(PE), "no pin published while focused")
    c.world.questLog.focus = nil
    c:fire("SUPER_TRACKING_CHANGED")
    c:advance(1.2)
    eq(published(PE), nil)
end)

-- Spec section 2 / QuestArrow.lua Idle: "not pointing while the position is unknown".
test("quest arrow: the published pin is nil while the position is unknown, and comes back with it", function()
    local c, PE = newArrow()
    check(published(PE))
    c.world.player.map = nil                  -- a loading screen
    c:advance(1.5)
    eq(published(PE), nil)
    c.world.player.map = QW.HOME
    c:advance(1.5)
    check(published(PE), "no pin after the position came back")
end)

---------------------------------------------------------------------------
-- What the arrow says
---------------------------------------------------------------------------

-- QuestArrow.lua header (distance and the quest name under the arrow); ShowDistance: nearest 5 yards
-- below 300.
test("quest arrow: shows the distance in yards and the quest name", function()
    local c, PE = newArrow(focusOne())
    local pin = onePin(c, PE)
    placeAt(c, pin.x, pin.y + 0.03, 0)         -- 0.03 * 2314 = 69.4 yards south
    eq(parts(c).distText(), "70 yd")
    eq(parts(c).titleText(), "Bounty on Garrick Padfoot")
    check(parts(c).display.frame:IsVisible(), "the arrow block is not on screen")
    c:assertClean("distance")
end)

-- QuestArrow.lua HERE_ENTER = 10 yards: "Here".
test("quest arrow: within 10 yards it says Here", function()
    local c, PE = newArrow(focusOne())
    local pin = onePin(c, PE)
    placeAt(c, pin.x, pin.y + 0.002, 0)        -- 4.6 yards
    eq(parts(c).distText(), "Here")
end)

-- DECISIONS "Quest arrow": 'With none focused it says "No quest focused / Focus one in your quest log"'.
test("quest arrow: with no quest focused it says so", function()
    local c, PE = newArrow({ nofocus = true })
    local a = parts(c)
    eq(a.distText(), "No quest focused")
    eq(a.titleText(), "Focus one in your quest log")
    check(a.display.frame:IsVisible(), "the message is not on screen")
    check(not a.box.frame:IsShown(), "the arrow itself is shown with nothing to point at")
    eq(published(PE), nil)
end)

-- DECISIONS "Quest arrow": 'for a focused quest elsewhere it says "Outside this zone / Head to <zone>"'.
test("quest arrow: a focused quest in another zone says Outside this zone and names the zone", function()
    local c, PE = newArrow({ focus = QW.ELSEWHERE })
    local a = parts(c)
    eq(a.distText(), "Outside this zone")
    eq(a.titleText(), "Head to Duskwood")
    check(not a.box.frame:IsShown(), "an arrow is shown for another zone")
    eq(published(PE), nil)
end)

---------------------------------------------------------------------------
-- Turn around, direction
---------------------------------------------------------------------------

local function turnShown(c) return parts(c).turn().shown and true or false end

-- DECISIONS "Quest arrow": '"Turn around" instead of an arrow pointing down (back below 135 degrees)';
-- QuestArrow.lua TURN_ENTER = 150 degrees, TURN_LEAVE = 135. The spot is straight north (bearing 0),
-- so the angle off straight ahead is the facing.
test("quest arrow: Turn around appears above 150 degrees off, stays down to 135, then goes", function()
    local c, PE = newArrow(focusOne())
    local pin = onePin(c, PE)
    local x, y = pin.x, pin.y + 0.03
    placeAt(c, x, y, rad(140))
    check(not turnShown(c), "Turn around at 140 degrees off")
    check(parts(c).arrow().shown, "arrow hidden at 140 degrees off")
    placeAt(c, x, y, rad(160))
    check(turnShown(c), "no Turn around at 160 degrees off")
    check(not parts(c).arrow().shown, "arrow still shown with Turn around")
    placeAt(c, x, y, rad(140))
    check(turnShown(c), "Turn around went away at 140 degrees, above the 135 it should wait for")
    placeAt(c, x, y, rad(130))
    check(not turnShown(c), "Turn around still shown at 130 degrees off")
    check(parts(c).arrow().shown, "arrow not back at 130 degrees off")
    c:assertClean("turn around")
end)

-- QuestArrow.lua header: "facing north, pin north: rel = 0 -> up; facing east, pin north: rel = +pi/2
-- (left); facing north, pin east: rel = -pi/2 (right)". The picture turns counter-clockwise by rel.
test("quest arrow: the arrow turns the way the header says (north, east and left of the player)", function()
    local c, PE = newArrow(focusOne())
    local pin = onePin(c, PE)
    local function rotation() return parts(c).arrow().rotation or 0 end
    local function near(a, b) return math.abs(((a - b + math.pi) % (2 * math.pi)) - math.pi) < 0.05 end
    placeAt(c, pin.x, pin.y + 0.03, 0)                          -- spot straight north, facing north
    check(near(rotation(), 0), "straight ahead: rotation " .. rotation())
    placeAt(c, pin.x, pin.y + 0.03, 3 * math.pi / 2)            -- facing east: the spot is on the left
    check(near(rotation(), math.pi / 2), "spot on the left: rotation " .. rotation())
    placeAt(c, pin.x - 0.02, pin.y, 0)                          -- the spot is east, facing north: right
    check(near(rotation(), -math.pi / 2), "spot on the right: rotation " .. rotation())
end)

---------------------------------------------------------------------------
-- Instances, and nothing ticking
---------------------------------------------------------------------------

-- DECISIONS-adjacent: QuestArrow.lua header "The driver is stopped completely inside instances";
-- STATUS.instance "Hidden while you are inside a dungeon."; the brief: "hidden inside an instance".
test("quest arrow: hidden inside an instance, and nothing of ours ticks there", function()
    local c, PE = newArrow()
    check(parts(c).display.frame:IsVisible(), "the arrow is not on screen before the instance")
    c.world.instance = true
    c:fire("PLAYER_ENTERING_WORLD", false, false)
    c:advance(0.5)
    local a = parts(c)
    check(not a.display.frame:IsVisible(), "the arrow is on screen inside an instance")
    check(not a.driver.frame:IsVisible(), "the driver is still running inside an instance")
    eq(published(PE), nil)
    eq(PE:GetModule("questArrow").status(PE:GetModule("questArrow")), "Hidden while you are inside a dungeon.")
    local ticks = c.stats.addonOnUpdate
    c:advance(3)
    eq(c.stats.addonOnUpdate, ticks, "an OnUpdate of ours ran inside the instance")
    c.world.instance = false
    c:fire("PLAYER_ENTERING_WORLD", false, false)
    c:advance(1.5)
    check(a.display.frame:IsVisible(), "the arrow did not come back after leaving the instance")
    check(published(PE), "no pin after leaving the instance")
end)

-- QuestArrow.lua header: "The driver is stopped completely ... while there is nothing to point at".
test("quest arrow: nothing ticks while there is nothing to point at (no quest focused)", function()
    local c, PE = newArrow({ nofocus = true })
    check(not parts(c).driver.frame:IsVisible(), "the driver is still running")
    local ticks = c.stats.addonOnUpdate
    c:advance(3)
    eq(c.stats.addonOnUpdate, ticks, "an OnUpdate of ours ran")
end)

test("quest arrow: nothing ticks while the focused quest is in another zone", function()
    local c, PE = newArrow({ focus = QW.ELSEWHERE })
    check(not parts(c).driver.frame:IsVisible(), "the driver is still running")
    local ticks = c.stats.addonOnUpdate
    c:advance(3)
    eq(c.stats.addonOnUpdate, ticks)
end)

-- Focusing a quest again starts it (QuestData's "tracked" callback), so a stopped driver is not stuck.
test("quest arrow: focusing a quest after nothing was focused starts the arrow again", function()
    local c, PE = newArrow({ nofocus = true })
    c.world.questLog.focus = QW.MANY
    c:fire("SUPER_TRACKING_CHANGED")
    c:advance(1.5)
    check(parts(c).driver.frame:IsVisible(), "the driver did not start")
    check(published(PE), "no pin after focusing")
end)

-- CLAUDE.md "Nothing ticks while its feature is off".
test("quest arrow: nothing ticks and nothing shows after the feature is switched off", function()
    local c, PE = newArrow()
    PE:SetModuleEnabled("questArrow", false)
    c:advance(0.5)
    local a = parts(c)
    check(not a.driver.frame:IsVisible(), "the driver is visible")
    check(not a.display.frame:IsVisible(), "the arrow is on screen")
    local ticks = c.stats.addonOnUpdate
    c:advance(3)
    eq(c.stats.addonOnUpdate, ticks)
    eq(published(PE), nil)
    c:assertClean("off")
end)

return { known = KNOWN_FAILURES }
