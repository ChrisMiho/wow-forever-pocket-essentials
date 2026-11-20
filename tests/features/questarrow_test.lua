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
    local c, PE = T.new({ quest = true, on = on or { "questArrow" }, saved = spec.saved, setup = function(c)
        QW.setup(c, spec)
        c.world.resting = spec.resting == true
        -- The fake client has no IsResting; the test world says whether the player rests.
        rawset(c.env, "IsResting", function() return c.world.resting == true end)
    end })
    c:advance(1.2)
    QW.check(c, PE)
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
        -- The quest line without its colour codes (|cffRRGGBB ... |r).
        titleText = function() return ((region(display, 2).text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end,
        rawTitle = function() return region(display, 2).text end,
        distWidget = display.regions[1], titleWidget = display.regions[2],
        distColor = function() return region(display, 1).textColor end,
        arrow = function() return region(box, 1) end,
    }
end

-- Spec 2026-11-20-0.9.0-ui-redesign, "Quest arrow on screen": the quest line is
-- "Quest: " in dim gold (.85, .72, .35), then the name in white.
local DIM_GOLD, WHITE, GREY = "|cffd9b859", "|cffffffff", "|cffd6d6d6"
local function questLine(prefix, name) return DIM_GOLD .. prefix .. "|r" .. WHITE .. name .. "|r" end
local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.01 end
local function sameColor(got, r, g, b)
    return got ~= nil and math.abs(got[1] - r) < 0.005 and math.abs(got[2] - g) < 0.005 and math.abs(got[3] - b) < 0.005
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
    eq(parts(c).rawTitle(), questLine("Quest: ", "Wolves Across the Border"))
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
    eq(parts(c).rawTitle(), questLine("Quest: ", "Bounty on Garrick Padfoot"))
    check(sameColor(parts(c).distColor(), 1, 0.82, 0), "the distance is not gold")
    check(parts(c).box.frame:IsShown(), "no arrow with a distance")
    check(parts(c).display.frame:IsVisible(), "the arrow block is not on screen")
    c:assertClean("distance")
end)

-- QuestArrow.lua HERE_ENTER = 10 yards: "Here".
test("quest arrow: within 10 yards it says Here", function()
    local c, PE = newArrow(focusOne())
    local pin = onePin(c, PE)
    placeAt(c, pin.x, pin.y + 0.002, 0)        -- 4.6 yards
    eq(parts(c).distText(), "Here")
    -- Spec 0.9.0: Here is green (.35, 1, .45) in the arrow and the text.
    check(sameColor(parts(c).distColor(), 0.35, 1, 0.45), "Here is not green")
    check(sameColor(parts(c).arrow().vertexColor, 0.35, 1, 0.45), "the arrow is not green at Here")
    eq(parts(c).rawTitle(), questLine("Quest: ", "Bounty on Garrick Padfoot"))
end)

-- QuestArrow.lua HERE_ENTER = 10, HERE_LEAVE = 14: "Here" switches on below 10 yards and off only above 14.
test("quest arrow: Here switches on below 10 yards and stays on until 14", function()
    local c, PE = newArrow(focusOne())
    local pin = onePin(c, PE)
    local function at(yards) placeAt(c, pin.x, pin.y + yards / QW.HEIGHT, 0) return parts(c).distText() end
    eq(at(30), "30 yd")
    eq(at(12), "10 yd", "between 10 and 14 yards coming in: not Here yet")
    eq(at(5), "Here")
    eq(at(12), "Here", "12 yards going out: still Here")
    eq(at(13.5), "Here", "13.5 yards going out: still Here")
    eq(at(16), "15 yd", "above 14 yards: Here is off")
    eq(at(12), "10 yd", "12 yards coming in again: not Here")
end)

-- DECISIONS "Quest arrow": "Five preset positions (Top, Upper middle, Lower middle, Left, Right)";
-- QuestArrow.lua POSITIONS (pixels on a 720p screen; PE.UI:Px converts). Spec 0.9.0: "Today's position
-- and Move offsets stay."
test("quest arrow: the five positions put the block where QuestArrow.lua says", function()
    local c, PE = newArrow(focusOne())
    local mod = PE:GetModule("questArrow")
    local function choose(name)
        mod.opts.position = name
        -- The position has no option row; a saved one is still drawn, so it redraws through the size row.
        for _, opt in ipairs(mod.options) do
            if opt.key == "scale" then PE:Safe(mod.key, opt.OnChange, mod, mod.opts.scale) end
        end
    end
    local Px = function(n) return PE.UI:Px(n) end
    local expected = {
        top = { "TOP", 0, -40 }, upper = { "CENTER", 0, 150 }, lower = { "CENTER", 0, -140 },
        left = { "CENTER", -230, 60 }, right = { "CENTER", 230, 60 },
    }
    for name, e in pairs(expected) do
        choose(name)
        local point, rel, relPoint, x, y = parts(c).display.frame:GetPoint(1)
        eq({ point, rel, relPoint }, { e[1], c.UIParent, e[1] }, name)
        check(near(x, Px(e[2])) and near(y, Px(e[3])), name .. ": offset " .. x .. "," .. y)
    end
end)

---------------------------------------------------------------------------
-- Size from scale (spec 0.9.0, "Quest arrow on screen" and "Option rows per feature")
---------------------------------------------------------------------------

local function setScale(PE, value)
    local mod = PE:GetModule("questArrow")
    mod.opts.scale = value
    for _, opt in ipairs(mod.options) do
        if opt.key == "scale" then PE:Safe(mod.key, opt.OnChange, mod, value) end
    end
end

-- Spec: arrow box 76*s, text width 400*s, top line 28*s (title face), quest line 20*s (font face).
test("quest arrow: the block's sizes follow scale", function()
    local c, PE = newArrow(focusOne())
    local Px = function(n) return PE.UI:Px(n) end
    for _, scale in ipairs({ 100, 50, 150, 70 }) do
        setScale(PE, scale)
        local s = scale / 100
        local a = parts(c)
        check(near(a.box.frame:GetWidth(), Px(76 * s)) and near(a.box.frame:GetHeight(), Px(76 * s)),
            scale .. "%: box " .. a.box.frame:GetWidth())
        check(near(a.display.frame:GetWidth(), Px(400 * s)), scale .. "%: width " .. a.display.frame:GetWidth())
        local _, big = a.distWidget:GetFont()
        local _, small = a.titleWidget:GetFont()
        check(near(big, Px(28 * s)), scale .. "%: top line size " .. tostring(big))
        check(near(small, Px(20 * s)), scale .. "%: quest line size " .. tostring(small))
    end
    c:assertClean("scale")
end)

-- Spec: "It no longer follows Button size."
test("quest arrow: the sizes do not follow Button size", function()
    local c, PE = newArrow(focusOne())
    local Px = function(n) return PE.UI:Px(n) end
    for _, size in ipairs({ "large", "small", "medium" }) do
        PE.db.ui.size = size
        PE.UI:Refresh(true)
        local a = parts(c)
        check(near(a.box.frame:GetWidth(), Px(76)), size .. ": box " .. a.box.frame:GetWidth())
        check(near(a.display.frame:GetWidth(), Px(400)), size .. ": width " .. a.display.frame:GetWidth())
        local _, big = a.distWidget:GetFont()
        local _, small = a.titleWidget:GetFont()
        check(near(big, Px(28)) and near(small, Px(20)), size .. ": fonts " .. tostring(big) .. ", " .. tostring(small))
    end
end)

-- Spec: "Saved size values move to scale once: small -> 70, normal -> 100, large -> 150. After that size
-- is ignored."
test("quest arrow: a saved size moves to scale once", function()
    for size, scale in pairs({ small = 70, normal = 100, large = 150 }) do
        local c, PE = newArrow({ focus = QW.ONE, saved = { options = { questArrow = { size = size } } } })
        local opts = PE:GetModule("questArrow").opts
        eq(opts.scale, scale, size)
        eq(opts.size, nil, size .. ": size still saved")
        check(near(parts(c).box.frame:GetWidth(), PE.UI:Px(76 * scale / 100)), size .. ": box not drawn at the new scale")
    end
    -- A scale already saved (with no size) is kept, and a later size is not read again.
    local c, PE = newArrow({ focus = QW.ONE, saved = { options = { questArrow = { scale = 120 } } } })
    eq(PE:GetModule("questArrow").opts.scale, 120)
    PE:GetModule("questArrow").opts.size = "small"
    setScale(PE, 120)
    check(near(parts(c).box.frame:GetWidth(), PE.UI:Px(76 * 1.2)), "a size saved after the move was read")
    -- First install: 100, and Hide in cities and inns.
    local _, PE2 = newArrow(focusOne())
    eq(PE2:GetModule("questArrow").opts.scale, 100)
    eq(PE2:GetModule("questArrow").opts.restHide, true)
end)

-- Spec "Option rows per feature", Quest arrow (labels exactly); plan "Option-row interface".
test("quest arrow: the option rows, in order, with the size choice gone", function()
    local _, PE = newArrow(focusOne())
    local mod = PE:GetModule("questArrow")
    eq(mod.desc, "Points to the nearest objective of your focused quest.")
    local o = mod.options
    eq(#o, 3, "rows")
    eq(o[1].key, "scale")
    eq(o[1].label, "Size of the arrow and its text")
    eq(o[1].number, { min = 50, max = 150, step = 10, default = 100, suffix = "%", unit = "of normal" })
    eq(o[2].key, "restHide")
    eq(o[2].label, "\"No quest focused\" in cities and inns")
    eq(o[2].choices, { { value = true, label = "Hide" }, { value = false, label = "Show" } })
    eq(o[3].label, "Position on screen")
    eq(o[3].button, "Move the arrow")
    check(type(o[3].action) == "function", "no action")
    for _, opt in ipairs(o) do check(opt.key ~= "size", "the size choice is still there") end
end)

-- DECISIONS "Quest arrow": 'With none focused it says "No quest focused / Focus one in your quest log"'.
test("quest arrow: with no quest focused it says so", function()
    local c, PE = newArrow({ nofocus = true })
    local a = parts(c)
    eq(a.distText(), "No quest focused")
    eq(a.rawTitle(), GREY .. "Focus one in your quest log|r")
    local point, _, relPoint = a.distWidget:GetPoint(1)
    eq({ point, relPoint }, { "TOP", "TOP" }, "with no arrow the top line is not at the block's top")
    check(a.display.frame:IsVisible(), "the message is not on screen")
    check(not a.box.frame:IsShown(), "the arrow itself is shown with nothing to point at")
    eq(published(PE), nil)
end)

-- DECISIONS "Quest arrow": 'for a focused quest elsewhere it says "Outside this zone / Head to <zone>"'.
test("quest arrow: a focused quest in another zone says Outside this zone and names the zone", function()
    local c, PE = newArrow({ focus = QW.ELSEWHERE })
    local a = parts(c)
    eq(a.distText(), "Outside this zone")
    eq(a.rawTitle(), questLine("Head to ", "Duskwood"))
    check(not a.box.frame:IsShown(), "an arrow is shown for another zone")
    eq(published(PE), nil)
end)

-- Spec 0.9.0 message table, "No location": "No map data for this quest" over the quest line. Here the
-- quest has places but none are known to the data: its pins are removed before the arrow looks.
test("quest arrow: a quest with no known place says No map data for this quest", function()
    local c, PE = newArrow(focusOne())
    local QD = PE.QuestData
    local real = QD.GetPinsForQuest
    QD.GetPinsForQuest = function(self, id) if id == QW.ONE then return {} end return real(self, id) end
    c.world.player.x = c.world.player.x + 0.001
    c:fire("SUPER_TRACKING_CHANGED")
    c:advance(1.5)
    local a = parts(c)
    eq(a.distText(), "No map data for this quest")
    eq(a.rawTitle(), questLine("Quest: ", "Bounty on Garrick Padfoot"))
    check(not a.box.frame:IsShown(), "an arrow is shown with no map data")
end)

-- Spec 0.9.0 message table, "Turn-in target": the distance, then "Turn in: " in dim gold and the name.
test("quest arrow: a turn-in spot reads Turn in: before the quest name", function()
    local c, PE = newArrow(focusOne())
    local QD = PE.QuestData
    local real = QD.GetPinsForQuest
    QD.GetPinsForQuest = function(self, id)
        local byMap = real(self, id)
        if id ~= QW.ONE then return byMap end
        local out = {}
        for map, pins in pairs(byMap) do
            out[map] = {}
            for i, p in ipairs(pins) do
                local copy = {}
                for k, v in pairs(p) do copy[k] = v end
                copy.kind, copy.obj = "turnin", nil
                out[map][i] = copy
            end
        end
        return out
    end
    PE:SetModuleEnabled("questArrow", false)       -- start again, so the first pick is the turn-in spot
    c:advance(0.2)
    PE:SetModuleEnabled("questArrow", true)
    c:advance(1.5)
    eq(parts(c).rawTitle(), questLine("Turn in: ", "Bounty on Garrick Padfoot"))
    check(parts(c).distText():find(" yd$"), "no distance: " .. tostring(parts(c).distText()))
end)

---------------------------------------------------------------------------
-- Resting (spec 0.9.0 "Quest arrow on screen", Resting)
---------------------------------------------------------------------------

local function listening(c, event) return #c:_eventOrder(event) > 0 end

test("quest arrow: no quest focused while resting hides the block when restHide is on", function()
    local c, PE = newArrow({ nofocus = true })
    local a = parts(c)
    check(a.display.frame:IsVisible(), "test setup: the message is not on screen")
    c.world.resting = true
    c:fire("PLAYER_UPDATE_RESTING")
    c:advance(0.3)
    check(not a.display.frame:IsVisible(), "the message is on screen while resting")
    c.world.resting = false
    c:fire("PLAYER_UPDATE_RESTING")
    c:advance(0.3)
    check(a.display.frame:IsVisible(), "the message did not come back after leaving the inn")
    -- Show: the message stays while resting.
    PE:GetModule("questArrow").opts.restHide = false
    c.world.resting = true
    c:fire("PLAYER_UPDATE_RESTING")
    c:advance(0.3)
    check(a.display.frame:IsVisible(), "hidden while resting with Show chosen")
    c:assertClean("resting")
end)

test("quest arrow: choosing Hide while resting hides the message at once", function()
    local c, PE = newArrow({ nofocus = true })
    local mod = PE:GetModule("questArrow")
    mod.opts.restHide = false
    c.world.resting = true
    c:fire("PLAYER_UPDATE_RESTING")
    c:advance(0.3)
    check(parts(c).display.frame:IsVisible(), "test setup: hidden with Show")
    for _, opt in ipairs(mod.options) do
        if opt.key == "restHide" then
            mod.opts.restHide = true
            PE:Safe(mod.key, opt.OnChange, mod, true)
        end
    end
    c:advance(0.3)
    check(not parts(c).display.frame:IsVisible(), "still shown after choosing Hide")
end)

test("quest arrow: resting never hides an arrow pointing at a focused quest", function()
    local c, PE = newArrow(focusOne())
    c.world.resting = true
    c:fire("PLAYER_UPDATE_RESTING")
    c:advance(0.5)
    local a = parts(c)
    check(a.display.frame:IsVisible(), "the arrow is hidden while resting")
    check(a.box.frame:IsShown(), "no arrow while resting")
    -- And in another zone the text stays too.
    local c2 = newArrow({ focus = QW.ELSEWHERE })
    c2.world.resting = true
    c2:fire("PLAYER_UPDATE_RESTING")
    c2:advance(0.5)
    check(parts(c2).display.frame:IsVisible(), "Outside this zone is hidden while resting")
end)

test("quest arrow: resting at login with no quest focused starts hidden", function()
    local c = newArrow({ nofocus = true, resting = true })
    check(not parts(c).display.frame:IsVisible(), "the message is on screen while resting")
    check(not parts(c).driver.frame:IsVisible(), "the driver is still running")
end)

-- Spec: "PLAYER_UPDATE_RESTING, which is registered only while the feature is on."
test("quest arrow: PLAYER_UPDATE_RESTING is listened for only while the arrow is on", function()
    local c, PE = newArrow({ nofocus = true }, { "questIcons" })   -- icons hold the quest data
    check(not listening(c, "PLAYER_UPDATE_RESTING"), "listened for with the arrow off")
    PE:SetModuleEnabled("questArrow", true)
    c:advance(0.2)
    check(listening(c, "PLAYER_UPDATE_RESTING"), "not listened for with the arrow on")
    PE:SetModuleEnabled("questArrow", false)
    c:advance(0.2)
    check(not listening(c, "PLAYER_UPDATE_RESTING"), "still listened for after the arrow went off")
    c:assertClean("resting event")
end)

---------------------------------------------------------------------------
-- Turn around, direction
---------------------------------------------------------------------------

-- Spec 0.9.0: Turn around draws no arrow; the top line reads "Turn around" in gold, at the block's top,
-- with the quest line under it.
local function turnShown(c)
    local a = parts(c)
    local shown = a.distText() == "Turn around"
    if shown then
        check(not a.box.frame:IsShown(), "an arrow is drawn with Turn around")
        check(sameColor(a.distColor(), 1, 0.82, 0), "Turn around is not gold")
        eq(a.rawTitle(), questLine("Quest: ", "Bounty on Garrick Padfoot"))
        local point, _, relPoint = a.distWidget:GetPoint(1)
        eq({ point, relPoint }, { "TOP", "TOP" }, "Turn around is not at the top of the block")
    end
    return shown
end

-- DECISIONS "Quest arrow": '"Turn around" instead of an arrow pointing down (back below 135 degrees)';
-- QuestArrow.lua TURN_ENTER = 150 degrees, TURN_LEAVE = 135. The spot is straight north (bearing 0),
-- so the angle off straight ahead is the facing.
test("quest arrow: Turn around appears above 150 degrees off, stays down to 135, then goes", function()
    local c, PE = newArrow(focusOne())
    local pin = onePin(c, PE)
    local x, y = pin.x, pin.y + 0.03
    placeAt(c, x, y, rad(140))
    check(not turnShown(c), "Turn around at 140 degrees off")
    check(parts(c).box.frame:IsShown(), "arrow hidden at 140 degrees off")
    eq(parts(c).distText(), "70 yd")
    placeAt(c, x, y, rad(160))
    check(turnShown(c), "no Turn around at 160 degrees off")
    check(not parts(c).box.frame:IsShown(), "arrow still shown with Turn around")
    placeAt(c, x, y, rad(140))
    check(turnShown(c), "Turn around went away at 140 degrees, above the 135 it should wait for")
    placeAt(c, x, y, rad(130))
    check(not turnShown(c), "Turn around still shown at 130 degrees off")
    check(parts(c).box.frame:IsShown(), "arrow not back at 130 degrees off")
    eq(parts(c).distText(), "70 yd", "the distance did not come back")
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

---------------------------------------------------------------------------
-- Debug log (docs/superpowers/specs/2026-11-17-debug-log.md)
---------------------------------------------------------------------------

-- The debug log's lines that contain `text` (plain match).
local function logLines(c, text)
    local out = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        if line:find(text, 1, true) then out[#out + 1] = line end
    end
    return out
end

-- Spec "What is written", Quest arrow: "each change of state (pointing at a quest, text only, hidden) and
-- why; not the distance or the turning". "Not doing: No log of every frame or every update of the arrow".
test("debug log: the arrow's ticks write nothing; a change of state writes one line", function()
    local c, PE = newArrow()
    PE:SetDebug(true)
    placeAt(c, 0.4505, 0.6205, nil, 1.5)                   -- the next choice of spot writes the state once
    local pointing = logLines(c, "questArrow: pointing at quest " .. QW.MANY .. " ")
    eq(#pointing, 1)
    check(pointing[1]:find(" on map " .. QW.HOME .. " (nearest of ", 1, true), "pointing line: " .. pointing[1])
    local count, ticks = #logLines(c, ""), c.stats.addonOnUpdate
    c:advance(10)
    check(c.stats.addonOnUpdate >= ticks + 90, "test setup: the arrow's driver did not tick")
    eq(#logLines(c, ""), count, "lines written by ticks with nothing changing")
    placeAt(c, 0.451, 0.621, 0.5, 3)                       -- walking and turning: still the same state
    eq(#logLines(c, ""), count, "lines written while walking towards the same quest")

    c.world.questLog.focus = QW.ONE                        -- another quest focused: one new state
    c:fire("SUPER_TRACKING_CHANGED")
    c:advance(1.2)
    eq(#logLines(c, "questArrow: pointing at quest " .. QW.ONE .. " "), 1)
    c.world.questLog.focus = nil
    c:fire("SUPER_TRACKING_CHANGED")
    c:advance(1.2)
    eq(#logLines(c, "questArrow: text only: no quest focused"), 1)
    eq(#logLines(c, "questArrow: driver stopped"), 1)
    count = #logLines(c, "")
    c:advance(5)
    eq(#logLines(c, ""), count, "lines written while stopped")
    c:assertClean("arrow lines")
end)

-- Spec "Cost while off": "No text is built, nothing is stored."
test("debug log: with the log off the arrow writes nothing", function()
    local c, PE = newArrow()
    c.world.questLog.focus = nil
    c:fire("SUPER_TRACKING_CHANGED")
    c:advance(1.2)
    eq(#rawget(c.env, "PocketEssentialsDB").debug.lines, 0)
end)

---------------------------------------------------------------------------
-- Following the player (docs/superpowers/specs/2026-11-17-post-0.0.9-batch.md, section 4)
-- Quest 745 on Mulgore: three kill objectives (1 Tanner, 2 Skinner, 3 Poacher), spots in three camps.
---------------------------------------------------------------------------

local A = { x = 0.4654, y = 0.7277 }     -- a Tanner spot (objective 1)
local B = { x = 0.4810, y = 0.7276 }     -- a Tanner spot 80 yards east of A
local S2 = { x = 0.4652, y = 0.7354 }    -- a Skinner spot (objective 2) 26 yards south of A
local MW, MH = QW.MULGORE_WIDTH, QW.MULGORE_HEIGHT

local function newCamps(x, y)
    local c, PE = T.new({ quest = true, on = { "questArrow" }, setup = function(c)
        QW.setup(c, { quests = { { id = QW.CAMPS } }, focus = QW.CAMPS, pos = { map = QW.MULGORE, x = x, y = y } })
    end })
    c:advance(1.2)
    QW.check(c, PE)
    return c, PE
end

local function campPins(PE) return PE.QuestData:GetPinsForQuest(QW.CAMPS)[QW.MULGORE] end

-- The spot at a position (to 4 decimals), or nil.
local function pinAt(PE, at)
    for _, p in ipairs(campPins(PE) or {}) do
        if math.abs(p.x - at.x) < 0.00005 and math.abs(p.y - at.y) < 0.00005 then return p end
    end
end

local function isAt(pin, at)
    return pin ~= nil and math.abs(pin.x - at.x) < 0.00005 and math.abs(pin.y - at.y) < 0.00005
end

local function where(pin) return pin and (pin.x .. "," .. pin.y .. " objective " .. tostring(pin.obj)) or "nothing" end

-- Marks a log objective of quest 745 finished, as the game does after the last kill.
local function finish(c, j)
    local o = c.world.questLog.quests[1].objectives[j]
    o.finished = true
    o.text = o.text:gsub("0/1", "1/1")
    c:fire("QUEST_LOG_UPDATE")
end

-- Spec 4, "Objective number": each spot carries the number of its objective in the quest log.
test("quest data: every spot carries its quest-log objective number", function()
    local c, PE = newCamps(0.40, 0.70)
    local names = { "Palemane Tanner", "Palemane Skinner", "Palemane Poacher" }
    for _, p in ipairs(campPins(PE)) do
        eq(names[p.obj], p.target, "spot " .. p.x .. "," .. p.y)
    end
end)

-- Spec 4 Tests: "Finished objective: its spots are gone and the arrow is on a remaining objective's spot
-- after the next update, no extra second." Here at a Tanner spot (Here never blocks a finished objective).
test("quest arrow: a finished objective's spot is left at once for a remaining objective's spot", function()
    local c, PE = newCamps(A.x, A.y)
    PE:SetDebug(true)
    check(isAt(published(PE), A), "test setup: not pointing at the Tanner spot: " .. where(published(PE)))
    eq(parts(c).distText(), "Here")
    finish(c, 1)
    c:advance(0.5)                                  -- the rebuild lands after 0.3 s, then one update
    for _, p in ipairs(campPins(PE)) do check(p.obj ~= 1, "a Tanner spot is still there") end
    check(isAt(published(PE), S2), "expected the Skinner spot 26 yards away, got " .. where(published(PE)))
    eq(#logLines(c, "questArrow: spot changed: objective finished or spot gone"), 1)
end)

-- Spec 4 Tests: "Same target kept across a rebuild that keeps the spot." Spec Design: '"Here" is not reset'.
test("quest arrow: a rebuild that keeps the spot keeps the target and Here", function()
    local c, PE = newCamps(A.x, A.y)
    PE:SetDebug(true)
    local before = published(PE)
    check(isAt(before, A), "test setup: not pointing at the Tanner spot")
    eq(parts(c).distText(), "Here")
    finish(c, 3)                                    -- the Poachers: every spot table is made again
    c:advance(1.5)
    check(not rawequal(pinAt(PE, A), before), "test setup: the rebuild did not make new spot tables")
    check(isAt(published(PE), A), "the target moved to " .. where(published(PE)))
    check(rawequal(published(PE), pinAt(PE, A)), "the published pin is not the rebuilt spot")
    eq(parts(c).distText(), "Here")
    eq(#logLines(c, "questArrow: arrived at the spot"), 0, "Here was reset and entered again")
    eq(#logLines(c, "questArrow: spot changed"), 0)
end)

-- Spec 4 Tests: "two spots at a similar distance do not swap as the player steps back and forth across
-- the midpoint; a clearly nearer spot does take over after a second" (20 % and 15 yards nearer).
test("quest arrow: two spots at a similar distance do not swap; a clearly nearer one takes over", function()
    local y = 0.7276
    local c, PE = newCamps(0.4722, y)               -- 35 yards from A, 45 from B
    check(isAt(published(PE), A), "test setup: expected A first, got " .. where(published(PE)))
    for _ = 1, 4 do
        placeAt(c, 0.4742, y, nil, 1.5)             -- now B is 10 yards nearer (not 15)
        check(isAt(published(PE), A), "swapped to " .. where(published(PE)))
        placeAt(c, 0.4722, y, nil, 1.5)
        check(isAt(published(PE), A), "swapped to " .. where(published(PE)))
    end
    PE:SetDebug(true)
    placeAt(c, 0.4790, y, nil, 0.5)                 -- B 10 yards away, A 70: clearly nearer
    check(isAt(published(PE), A) or isAt(published(PE), B), "pointing at neither")
    placeAt(c, 0.4790, y + 0.0001, nil, 1.1)
    check(isAt(published(PE), B), "the clearly nearer spot did not take over: " .. where(published(PE)))
    eq(#logLines(c, "questArrow: spot changed: another is nearer ("), 1)
end)

-- Spec 4 Tests: "after 'Here' then leaving, the arrow goes to another spot, not back; after 180 seconds
-- the spot is eligible again".
test("quest arrow: a reached spot is set aside after leaving it, and comes back after 180 seconds", function()
    local c, PE = newCamps(A.x, A.y)
    PE:SetDebug(true)
    eq(parts(c).distText(), "Here")
    local north = A.y - 20 / MH                     -- 20 yards north: A is still the nearest spot
    placeAt(c, A.x, north, nil, 2.5)
    check(isAt(published(PE), S2), "expected the next spot (26 yards south of A), got " .. where(published(PE)))
    eq(#logLines(c, "questArrow: spot set aside for 180 s after being reached"), 1)
    for i = 1, 5 do                                 -- walking about near A: never back to it
        placeAt(c, A.x + i * 0.0002, north, nil, 1.2)
        check(not isAt(published(PE), A), "went back to the reached spot")
    end
    c:advance(180)
    placeAt(c, A.x, north, nil, 1.5)
    check(isAt(published(PE), A), "the spot did not come back after 180 seconds: " .. where(published(PE)))
end)

-- Spec 4 Tests: "all set aside clears the list; a one-spot quest keeps pointing at its spot".
test("quest arrow: a one-spot quest keeps pointing at its spot after it was reached", function()
    local c, PE = newArrow(focusOne())
    PE:SetDebug(true)
    local pin = onePin(c, PE)
    placeAt(c, pin.x, pin.y + 0.002, 0, 1.5)       -- 4.6 yards: Here
    eq(parts(c).distText(), "Here")
    placeAt(c, pin.x, pin.y + 0.01, 0, 2.5)        -- 23 yards: left
    check(rawequal(published(PE), pin), "the only spot is no longer pointed at")
    eq(parts(c).distText(), "25 yd")
    eq(#logLines(c, "questArrow: all spots reached: starting again"), 1)
end)

-- Spec 4 Design: "The list is cleared when the focused quest changes".
test("quest arrow: changing the focused quest clears the set-aside spots", function()
    local c, PE = newCamps(A.x, A.y)
    local north = A.y - 20 / MH
    placeAt(c, A.x, north, nil, 2.5)
    check(isAt(published(PE), S2), "test setup: A was not set aside")
    PE:SetDebug(true)
    c.world.questLog.focus = nil
    c:fire("SUPER_TRACKING_CHANGED")
    c:advance(1.2)
    c.world.questLog.focus = QW.CAMPS
    c:fire("SUPER_TRACKING_CHANGED")
    c:advance(1.2)
    check(isAt(published(PE), A), "the set-aside spot was not forgotten: " .. where(published(PE)))
    eq(#logLines(c, "questArrow: set-aside spots forgotten: quest changed"), 1)
end)

-- Spec 4 Design: "The list is cleared when ... the map changes".
test("quest arrow: changing the map clears the set-aside spots", function()
    local c, PE = newCamps(A.x, A.y)
    PE:SetDebug(true)
    local north = A.y - 20 / MH
    placeAt(c, A.x, north, nil, 2.5)
    check(isAt(published(PE), S2), "test setup: A was not set aside")
    c.world.player.map = QW.HOME                     -- into Elwynn Forest (no spot of quest 745 there)
    c:fire("ZONE_CHANGED_NEW_AREA")
    c:advance(1.2)
    eq(published(PE), nil, "test setup: still pointing on another map")
    c.world.player.map = QW.MULGORE
    c:fire("ZONE_CHANGED_NEW_AREA")
    c:advance(1.2)
    check(isAt(published(PE), A), "the set-aside spot was not forgotten: " .. where(published(PE)))
    eq(#logLines(c, "questArrow: set-aside spots forgotten: map changed"), 1)
end)

-- Spec 4 Design: "The list is cleared when ... the feature goes off".
test("quest arrow: switching the arrow off and on clears the set-aside spots", function()
    local c, PE = newCamps(A.x, A.y)
    local north = A.y - 20 / MH
    placeAt(c, A.x, north, nil, 2.5)
    check(isAt(published(PE), S2), "test setup: A was not set aside")
    PE:SetModuleEnabled("questArrow", false)
    c:advance(0.5)
    PE:SetModuleEnabled("questArrow", true)
    c:advance(1.2)
    check(isAt(published(PE), A), "the set-aside spot was not forgotten: " .. where(published(PE)))
end)

-- Spec 4 "Arrow debug log": "driver stopped: feature off" only pairs with a "driver started" line.
test("debug log: switching the arrow off writes driver stopped only after a driver started line", function()
    local c, PE = newArrow({ nofocus = true })
    PE:SetDebug(true)
    PE:SetModuleEnabled("questArrow", false)
    c:advance(0.5)
    eq(logLines(c, "questArrow: driver"), {}, "text only, then off")
    local c2, PE2 = newArrow()
    PE2:SetDebug(true)
    c2:advance(0.5)
    PE2:SetModuleEnabled("questArrow", false)
    c2:advance(0.5)
    eq(#logLines(c2, "questArrow: driver started"), 1)
    eq(#logLines(c2, "questArrow: driver stopped: feature off"), 1)
end)

-- Spec 4 "Arrow debug log": the pointing line names objective and spot, and is written on each change.
test("debug log: the pointing line names the objective and the spot, once per change", function()
    local c, PE = newCamps(0.4722, 0.7276)
    PE:SetDebug(true)
    placeAt(c, 0.4723, 0.7276, nil, 1.5)            -- the log was switched on after the first pick; the next one writes it
    local lines = logLines(c, "questArrow: pointing at quest 745 objective 1 spot 46.5,72.8 on map 1412 (nearest of 26, 0 set aside)")
    eq(#lines, 1, "pointing lines")
    placeAt(c, 0.4800, 0.7276, nil, 1.5)
    eq(#logLines(c, "questArrow: pointing at quest 745 objective 1 spot 48.1,72.8 on map 1412 (nearest of 26, 0 set aside)"), 1)
    eq(#logLines(c, "questArrow: pointing at"), 2)
end)

-- Spec 4 "Arrow debug log": no started/stopped pair for a quest-log event with no quest focused.
test("debug log: a quest-log change with no quest focused writes no driver started / stopped pair", function()
    local c, PE = newArrow({ nofocus = true })
    PE:SetDebug(true)
    local o = c.world.questLog.quests[1].objectives[1]
    o.finished, o.text = true, o.text:gsub("0/", "8/")
    c:fire("QUEST_LOG_UPDATE")
    c:advance(1.2)
    check(#logLines(c, "questData: rebuild:") >= 1, "test setup: no rebuild")
    eq(logLines(c, "questArrow: driver"), {})
end)

---------------------------------------------------------------------------
-- Move on screen: the quest arrow as a movable piece (docs/superpowers/specs/2026-11-17-move-things.md)
---------------------------------------------------------------------------

local function movePanel(c) return rawget(c.env, "PocketEssentialsMovePanel") end
local function moveButton(c, label)
    local found
    local function walk(w, seen)
        if seen[w] then return end
        seen[w] = true
        local st = c._state(w)
        if st.type == "Button" and w:IsVisible() and T.labelOf(w) == label then found = w end
        for _, ch in ipairs(st.children) do walk(ch, seen) end
    end
    walk(movePanel(c), {})
    return found
end
local function moveOutline(c)
    for _, rec in ipairs(c:frames()) do
        if rec.name == "PocketEssentialsMoveOutline" then return rec.frame end
    end
end
local function openMove(c, PE)
    PE.Move:Open()
    c:advance(0.1)
    check(movePanel(c) and movePanel(c):IsShown(), "the Move on screen panel did not open")
end
local function nudge(c, label)
    local b = moveButton(c, label)
    check(b, "no '" .. label .. "' button")
    c:script(b, "OnMouseDown", "LeftButton")
    c:script(b, "OnMouseUp", "LeftButton")
    c:script(b, "OnClick", "LeftButton", false)
end
local function rect(c, w)
    local l, r, t, b = c._rect(w)
    return { l = l, r = r, t = t, b = b }
end
local function sameRect(a, b)
    return math.abs(a.l - b.l) < 1e-3 and math.abs(a.r - b.r) < 1e-3
        and math.abs(a.t - b.t) < 1e-3 and math.abs(a.b - b.b) < 1e-3
end

local function arrowSelected(c, PE)
    openMove(c, PE)
    c:click(moveButton(c, "Quest arrow"))
end

test("quest arrow: move: no saved offset leaves the block where it was", function()
    local c, PE = newArrow(focusOne())
    local point, _, _, x, y = parts(c).display.frame:GetPoint(1)
    eq(point, "TOP")
    check(math.abs(x) < 0.01 and math.abs(y + PE.UI:Px(40)) < 0.01, "moved: " .. x .. "," .. y)
    eq({ PE.Move:GetOffset("questArrow") }, { 0, 0 })
end)

test("quest arrow: move: a saved offset is added to the preset when the block is laid out", function()
    local c, PE = newArrow(focusOne())
    PE.db.ui.moved.questArrow = { x = 14, y = -6 }
    local mod = PE:GetModule("questArrow")
    for _, opt in ipairs(mod.options) do
        if opt.key == "scale" then PE:Safe(mod.key, opt.OnChange, mod, mod.opts.scale) end
    end
    local _, _, _, x, y = parts(c).display.frame:GetPoint(1)
    local dx, dy = PE.Move:GetOffset("questArrow")
    check(math.abs(x - dx) < 0.01 and math.abs(y - (PE.UI:Px(-40) + dy)) < 0.01, "at " .. x .. "," .. y)
    check(dx ~= 0 and dy ~= 0, "no offset read")
end)

test("quest arrow: move: listed while the feature is on, not when it is off", function()
    local c, PE = newArrow(focusOne())
    openMove(c, PE)
    check(moveButton(c, "Quest arrow"), "not listed while on")
    PE.Move:Close("test")
    PE:SetModuleEnabled("questArrow", false)
    c:advance(0.2)
    openMove(c, PE)
    check(moveButton(c, "Quest arrow") == nil, "listed while off")
end)

test("quest arrow: move: a press moves the real block 2 pixels and the outline covers the whole block", function()
    local c, PE = newArrow(focusOne())
    local display = parts(c).display.frame
    local _, _, _, x0, y0 = display:GetPoint(1)
    arrowSelected(c, PE)
    nudge(c, "Right")
    nudge(c, "Up")
    local _, _, _, x1, y1 = display:GetPoint(1)
    check(math.abs(x1 - x0 - PE.UI:Px(2)) < 0.01 and math.abs(y1 - y0 - PE.UI:Px(2)) < 0.01, "moved " .. (x1 - x0) .. "," .. (y1 - y0))
    eq(PE.db.ui.moved.questArrow, { x = 2, y = 2 })
    check(sameRect(rect(c, moveOutline(c)), rect(c, display)), "the outline is not over the block")
end)

test("quest arrow: move: the outline works while the arrow is hidden (no quest focused, feature just on)", function()
    local c, PE = newArrow({ nofocus = true })
    arrowSelected(c, PE)
    local outline = moveOutline(c)
    check(outline and outline:IsVisible(), "no outline")
    local r = rect(c, outline)
    check(r.r - r.l > 10 and r.t - r.b > 10, "empty outline")
    nudge(c, "Left")
    check(sameRect(rect(c, outline), rect(c, parts(c).display.frame)), "outline and block differ after a move")
end)

test("quest arrow: no Arrow position row; a Position on screen row with Move the arrow instead", function()
    local c, PE = newArrow(focusOne())
    local mod = PE:GetModule("questArrow")
    local action
    for _, opt in ipairs(mod.options) do
        check(opt.label ~= "Arrow position", "the Arrow position row is still there")
        if opt.button == "Move the arrow" then action = opt end
    end
    check(action and type(action.action) == "function", "no Move the arrow action row")
end)

test("quest arrow: Move the arrow opens Move on screen with the arrow selected", function()
    local c, PE = newArrow(focusOne())
    local mod = PE:GetModule("questArrow")
    for _, opt in ipairs(mod.options) do
        if opt.button == "Move the arrow" then PE:Safe(mod.key, opt.action, mod) end
    end
    c:advance(0.1)
    check(movePanel(c) and movePanel(c):IsShown(), "the Move on screen panel did not open")
    local outline = moveOutline(c)
    check(outline and outline:IsShown(), "no outline")
    check(sameRect(rect(c, outline), rect(c, parts(c).display.frame)), "the outline is not over the arrow")
end)

test("quest arrow: move: Reset clears the offset and sets the position back to top", function()
    local c, PE = newArrow(focusOne())
    local mod = PE:GetModule("questArrow")
    mod.opts.position = "left"
    arrowSelected(c, PE)
    nudge(c, "Right")
    check(PE.db.ui.moved.questArrow, "no offset saved")
    c:click(moveButton(c, "Reset"))
    eq(PE.db.ui.moved.questArrow, nil)
    eq(mod.opts.position, "top")
    c:assertClean("reset")
end)

test("quest arrow: an old saved position = left with an offset is still drawn at left plus the offset", function()
    local c, PE = newArrow(focusOne())
    local mod = PE:GetModule("questArrow")
    mod.opts.position = "left"
    PE.db.ui.moved.questArrow = { x = 10, y = 4 }
    for _, opt in ipairs(mod.options) do
        if opt.key == "scale" then PE:Safe(mod.key, opt.OnChange, mod, mod.opts.scale) end
    end
    local _, _, _, x, y = parts(c).display.frame:GetPoint(1)
    check(math.abs(x - PE.UI:Px(-230 + 10)) < 0.01 and math.abs(y - PE.UI:Px(60 + 4)) < 0.01, "drawn at " .. x .. "," .. y)
end)

test("quest arrow: move: a hold-free update tick does nothing new (same driver, no extra OnUpdate)", function()
    local c, PE = newArrow(focusOne())
    arrowSelected(c, PE)
    PE.Move:Close("test")
    local n = 0
    for _, rec in ipairs(c:frames()) do
        if rec.frame:GetScript("OnUpdate") and rec.addonFile == "QuestArrow.lua" then n = n + 1 end
    end
    eq(n, 1, "frames with an OnUpdate from QuestArrow.lua")
end)

test("quest arrow: move: stays clean", function()
    local c, PE = newArrow(focusOne())
    arrowSelected(c, PE)
    nudge(c, "Down")
    c:advance(1.2)
    eq(#c:problems(), 0, table.concat(c:problems(), " / "))
end)

return { known = KNOWN_FAILURES }
