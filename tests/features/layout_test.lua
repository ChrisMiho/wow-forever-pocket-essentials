-- Rules for "Controller layout" (ControllerLayout.lua), the pure half.
-- Source: docs/superpowers/specs/2026-11-21-controller-layout.md ("The template",
-- "Frames", "Swing timers", "Bars") and 2026-11-22-controller-layout-measured-sizes.md
-- (the map's size). Fresh client and addon per test.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local function near(a, b, msg)
    check(type(a) == "number" and math.abs(a - b) < 1e-9, (msg or "number") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

local function plan()
    local c, PE = T.new({})
    local Plan = PE.LayoutPlan
    check(Plan ~= nil, "PE.LayoutPlan is missing")
    return Plan, c, PE
end

local function with(o)
    local out = {}
    for k, v in pairs(o or {}) do out[k] = v end
    return out
end

-- The piece of the list for a system (and index name).
local function piece(list, system, index)
    for _, p in ipairs(list) do
        if p.system == system and p.index == index then return p end
    end
    return nil
end

-- A small stand-in for the enums the shell reads from the game.
local function fakeEnums()
    local e = { system = {}, setting = {}, index = {}, layoutType = { Account = 1, Character = 2 }, style = { Gamepad = 7 } }
    local n = 100
    local function num() n = n + 1 return n end
    for _, s in ipairs({ "Minimap", "ChatFrame", "AuraFrame", "ObjectiveTracker", "StatusTrackingBar", "GamepadMainActionBar",
        "UnitFrame", "SwingTimer" }) do
        e.system[s] = num()
        e.setting[s] = {}
        e.index[s] = {}
    end
    e.setting.Minimap.Size = num()
    for _, k in ipairs({ "WidthHundreds", "WidthTensAndOnes", "HeightHundreds", "HeightTensAndOnes" }) do e.setting.ChatFrame[k] = num() end
    e.setting.ObjectiveTracker.Height = num()
    e.setting.StatusTrackingBar.Size = num()
    for _, k in ipairs({ "Compact", "ShowEmptyBars", "ShouldExpand" }) do e.setting.GamepadMainActionBar[k] = num() end
    for _, k in ipairs({ "Scale", "Width", "Height", "Visibility" }) do e.setting.SwingTimer[k] = num() end
    e.index.AuraFrame.BuffFrame, e.index.AuraFrame.DebuffFrame = 1, 2
    e.index.UnitFrame.Player, e.index.UnitFrame.Target, e.index.UnitFrame.Pet = 1, 2, 8
    e.index.SwingTimer.MainHand, e.index.SwingTimer.OffHand, e.index.SwingTimer.Ranged = 1, 2, 3
    e.index.StatusTrackingBar.StatusTrackingBar1, e.index.StatusTrackingBar.StatusTrackingBar2 = 1, 2
    e.setting.Minimap.HeaderUnderneath = num()
    return e
end

local function settingValue(entry, settingNumber)
    for _, s in ipairs(entry.settings) do
        if s.setting == settingNumber then return s.value end
    end
    return nil
end

---------------------------------------------------------------------------
-- Sizes
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

test("layout: Pieces for the defaults carry the template's anchors and settings", function()
    local Plan = plan()
    local list = Plan.Pieces(with(Plan.DEFAULTS))
    local map = piece(list, "Minimap")
    check(map, "no Minimap piece")
    eq(map.anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -10, y = 38 })
    eq(map.settings, { Size = 2, HeaderUnderneath = 1 })
    eq(map.moved, true)
    local chat = piece(list, "ChatFrame")
    eq(chat.anchor, { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -30, y = -40 })
    eq(chat.settings, { WidthHundreds = 4, WidthTensAndOnes = 30, HeightHundreds = 2, HeightTensAndOnes = 10 })
    eq(piece(list, "AuraFrame", "BuffFrame").anchor.y, -292)
    eq(piece(list, "AuraFrame", "DebuffFrame").anchor.y, -330)
    local quest = piece(list, "ObjectiveTracker")
    eq(quest.anchor, { point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "TOPLEFT", x = 92, y = -5 })
    eq(quest.settings, { Height = 0 })
    for _, name in ipairs({ "MainHand", "OffHand", "Ranged" }) do
        local t = piece(list, "SwingTimer", name)
        eq({ t.settings.Scale, t.settings.Width, t.settings.Height }, { 3, 0, 0 }, name)
    end
    eq(piece(list, "SwingTimer", "Ranged").settings.Visibility, 1)
    eq(piece(list, "SwingTimer", "MainHand").settings.Visibility, 1)
    eq(piece(list, "SwingTimer", "OffHand").settings.Visibility, 2)
    for _, name in ipairs({ "StatusTrackingBar1", "StatusTrackingBar2" }) do
        local p = piece(list, "StatusTrackingBar", name)
        check(p, "no " .. name)
        eq(p.settings, { Size = 10 })
        eq(p.moved, true)
    end
    local bar = piece(list, "GamepadMainActionBar")
    eq(bar.settings, { Compact = 0, ShowEmptyBars = 0, ShouldExpand = 0 })
    eq(bar.anchor, nil)
    eq(bar.moved, nil)
end)

test("plan: map bottom middle at 70% with its title under it", function()
    local Plan = plan()
    local map = piece(Plan.Pieces(), "Minimap")
    eq(map.anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -10, y = 38 })
    eq(map.settings, { Size = 2, HeaderUnderneath = 1 })
    -- The round map: 30 up and 10 right of the map's bottom, its 253 frame at 70%.
    local r = Plan.Rects()
    near((r.map[1] + r.map[3]) / 2, 0, "round map centred")
    near((r.map[2] + r.map[4]) / 2, 38 + 30 + 253 * 0.7 / 2, "round map centre up")
    near(r.map[3] - r.map[1], 198 * 0.7, "round map width")
    -- The title strip right under it.
    eq(r["title strip"], { -10 - 1 - 76, 46, -10 - 1 + 76, 69 })
    check(r["title strip"][4] < r.map[2], "the strip reaches the round map")
end)

test("plan: swing timers stacked under the title strip", function()
    local Plan = plan()
    local list = Plan.Pieces()
    eq(piece(list, "SwingTimer", "MainHand").anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 0, y = 31 })
    eq(piece(list, "SwingTimer", "OffHand").anchor.y, 17)
    eq(piece(list, "SwingTimer", "Ranged").anchor.y, 3)
    local r = Plan.Rects()
    near(r["MainHand timer"][3] - r["MainHand timer"][1], 170.4, "timer width")
    near(r["MainHand timer"][4] - r["MainHand timer"][2], 12, "timer height")
    check(r["MainHand timer"][4] < r["title strip"][2], "the top timer reaches the strip")
    check(r["Ranged timer"][2] >= 0, "the bottom timer is off screen")
    -- Order from the top: Main Hand, Off Hand, Ranged, whatever is shown.
    for _, o in ipairs({ { offHand = 0 }, { ranged = 2, mainHand = 2 } }) do
        local l = Plan.Pieces(o)
        eq({ piece(l, "SwingTimer", "MainHand").anchor.y, piece(l, "SwingTimer", "OffHand").anchor.y, piece(l, "SwingTimer", "Ranged").anchor.y }, { 31, 17, 3 })
    end
end)

test("plan: player, pet and target frames", function()
    local Plan = plan()
    local list = Plan.Pieces()
    eq(piece(list, "UnitFrame", "Player").anchor, { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -395, y = 56 })
    eq(piece(list, "UnitFrame", "Pet").anchor, { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -395, y = 181 })
    eq(piece(list, "UnitFrame", "Target").anchor, { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 395, y = 56 })
    for _, i in ipairs({ "Player", "Pet", "Target" }) do eq(piece(list, "UnitFrame", i).moved, true, i) end
    -- The target of target, placed by the module: above the two aura rows, left edges lined up.
    eq(Plan.TOT_SPOT, { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", x = 0, y = 25 })
    eq(Plan.SHOULDERS, { left = { "BOTTOMRIGHT", -76, 128 }, right = { "BOTTOMLEFT", 76, 128 } })
end)

test("plan: the target gets its auras on top", function()
    local Plan = plan()
    eq(piece(Plan.Pieces(), "UnitFrame", "Target").settings, { BuffsOnTop = 1 })
    eq(piece(Plan.Pieces(), "UnitFrame", "Player").settings, nil)
    local e = fakeEnums()
    e.setting.UnitFrame.BuffsOnTop = 501
    local layout = { systems = { { system = e.system.UnitFrame, systemIndex = e.index.UnitFrame.Target, settings = {}, isInDefaultPosition = true,
        anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 } } } }
    Plan.Apply(layout, Plan.Pieces(), e)
    eq(settingValue(layout.systems[1], 501), 1)
    -- A game without the setting: the spot is written, the setting left out.
    e.setting.UnitFrame.BuffsOnTop = nil
    local layout2 = { systems = { { system = e.system.UnitFrame, systemIndex = e.index.UnitFrame.Target, settings = {}, isInDefaultPosition = true,
        anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 } } } }
    Plan.Apply(layout2, Plan.Pieces(), e)
    eq(#layout2.systems[1].settings, 0)
    eq(layout2.systems[1].anchorInfo.offsetY, 56)
end)

test("plan: the target's cast bar lands on screen in the free corner, the aura rows under the target of target", function()
    local Plan = plan()
    local r = Plan.Rects()
    -- Cast bar with the target of target shown (Gamepad UI): 123 right, 46 under the frame's bottom left.
    eq(r["target cast bar"], { 395 + 123, 56 - 46 - 10, 395 + 123 + 150, 56 - 46 })
    local cast = r["target cast bar"]
    check(cast[1] >= -682.6 and cast[3] <= 682.6 and cast[2] >= 0 and cast[4] <= 768, "the cast bar is off screen")
    for _, spot in ipairs({ "inner right diamond", "outer right diamond" }) do
        check(cast[1] > r[spot][3], "the cast bar reaches the " .. spot)
    end
    -- Two rows of 21 with 3 between, up from 6 inside the frame picture's top (192 by 67, centred).
    local pictureTop = 56 + 50 + 33.5
    eq(r["target auras"], { 395 + 20 + 5, 156, 395 + 20 + 5 + 122, pictureTop - 6 + 45 })
    check(r["target auras"][4] < r["target of target"][2], "the aura rows reach the target of target")
    check(r["target auras"][3] <= 682.6, "the aura rows are off screen")
    check(r["target auras"][1] > r["outer right diamond"][3], "the aura rows reach the outer diamond")
end)

test("plan: the face, four diamond spots beside the map, picture 42", function()
    local Plan = plan()
    eq(Plan.FACE, { button = 42, dx = 46, dy = 28 })
    local s = Plan.FaceSpots()
    eq(s, {
        inner = { left = { x = -170, y = 66 }, right = { x = 170, y = 66 } },
        outer = { left = { x = -316, y = 66 }, right = { x = 316, y = 66 } },
    })
    -- A fresh copy each time.
    s.inner.left.x = 0
    eq(Plan.FaceSpots().inner.left.x, -170)
    -- A diamond is 134 by 98; the inner ones span 103 to 237 from the centre, the outer 249 to 383, 17 to 115 up.
    local r = Plan.Rects()
    for _, name in ipairs({ "inner left diamond", "outer left diamond", "inner right diamond", "outer right diamond" }) do
        check(r[name], "no rectangle for " .. name)
        near(r[name][3] - r[name][1], 134, name .. " width")
        near(r[name][4] - r[name][2], 98, name .. " height")
    end
    eq(r["inner left diamond"], { -237, 17, -103, 115 })
    eq(r["inner right diamond"], { 103, 17, 237, 115 })
    eq(r["outer left diamond"], { -383, 17, -249, 115 })
    eq(r["outer right diamond"], { 249, 17, 383, 115 })
    -- Only the four spots are listed, once each (no per-bar halves).
    for name in pairs(r) do
        check(not name:find(" dpad$") and not name:find(" face$"), "a bar half is listed: " .. name)
    end
end)

test("plan: the states, one panel a side, the triggers swap it", function()
    local Plan = plan()
    local st = Plan.FaceStates()
    eq(st, {
        rest = {
            { group = "main", half = "dpad", spot = "innerLeft" },
            { group = "main", half = "face", spot = "innerRight" },
        },
        lt = {
            { group = "lt", half = "dpad", spot = "outerLeft" },
            { group = "lt", half = "face", spot = "innerLeft" },
            { group = "main", half = "face", spot = "innerRight", quiet = true },
        },
        rt = {
            { group = "main", half = "dpad", spot = "innerLeft", quiet = true },
            { group = "rt", half = "dpad", spot = "innerRight" },
            { group = "rt", half = "face", spot = "outerRight" },
        },
        both = {
            { group = "both", half = "dpad", spot = "innerLeft" },
            { group = "both", half = "face", spot = "innerRight" },
        },
    })
    -- A fresh copy each time.
    st.rest[1].spot = "outerLeft"
    eq(Plan.FaceStates().rest[1].spot, "innerLeft")
    -- In every state: each spot used at most once, each half at most once, and a bar's d-pad left of its own face.
    local spots = Plan.FaceSpots()
    local function x(spot) local ring, side = spot:match("^(%l+)(%u%l+)$") return spots[ring][side:lower()].x end
    for key, list in pairs(Plan.FaceStates()) do
        local usedSpot, usedHalf, at = {}, {}, {}
        for _, e in ipairs(list) do
            check(not usedSpot[e.spot], key .. ": " .. e.spot .. " used twice")
            check(not usedHalf[e.group .. e.half], key .. ": " .. e.group .. " " .. e.half .. " drawn twice")
            usedSpot[e.spot], usedHalf[e.group .. e.half] = true, true
            at[e.group] = at[e.group] or {}
            at[e.group][e.half] = x(e.spot)
        end
        for group, halves in pairs(at) do
            if halves.dpad and halves.face then check(halves.dpad < halves.face, key .. ": " .. group .. " d-pad not left of its face") end
        end
    end
end)

test("plan: the rectangles follow the frames' spots", function()
    local Plan = plan()
    local r = Plan.Rects()
    local list = Plan.Pieces()
    local p = piece(list, "UnitFrame", "Player").anchor
    eq(r.player, { p.x - 232, p.y, p.x, p.y + 100 })
    local pet = piece(list, "UnitFrame", "Pet").anchor
    eq(r.pet, { pet.x - 120, pet.y, pet.x, pet.y + 49 })
    local t = piece(list, "UnitFrame", "Target").anchor
    eq(r.target, { t.x, t.y, t.x + 232, t.y + 100 })
    eq(r["target of target"], { t.x + Plan.TOT_SPOT.x, t.y + 100 + Plan.TOT_SPOT.y, t.x + Plan.TOT_SPOT.x + 120, t.y + 100 + Plan.TOT_SPOT.y + 49 })
    -- The pet and the target of target mirror each other.
    eq({ -r.pet[3], r.pet[2], -r.pet[1], r.pet[4] }, r["target of target"])
end)

test("plan: the four real bars at 60%, two under each inner diamond", function()
    local Plan = plan()
    local s = Plan.BarSpots()
    eq(s.top, { x = -170, y = 87, s = 0.6 })
    eq(s.left, { x = -170, y = 45, s = 0.6 })
    eq(s.right, { x = 170, y = 87, s = 0.6 })
    eq(s.both, { x = 170, y = 45, s = 0.6 })
    -- Old saved values change nothing.
    eq(Plan.BarSpots({ size = 70, fineBoth = 0.85, main = "under", map = 60 }), s)
    -- 124.8 by 40.8 each.
    local real = Plan.RealBarRects()
    for _, bar in ipairs({ "main", "lt", "rt", "both" }) do
        near(real[bar][3] - real[bar][1], 124.8, bar .. " width")
        near(real[bar][4] - real[bar][2], 40.8, bar .. " height")
    end
end)

test("plan: each real bar lies under its own side's inner diamond, clear of everything else", function()
    local Plan = plan()
    local r, real = Plan.Rects(), Plan.RealBarRects()
    local side = { main = "inner left diamond", lt = "inner left diamond", rt = "inner right diamond", both = "inner right diamond" }
    for bar, b in pairs(real) do
        local d = r[side[bar]]
        check(b[1] >= d[1] and b[3] <= d[3] and b[2] >= d[2] and b[4] <= d[4], bar .. " real bar is not under its diamond")
        near((b[1] + b[3]) / 2, (d[1] + d[3]) / 2, bar .. " real bar centred on its diamond")
    end
    -- The two a side do not overlap each other.
    for _, pair in ipairs({ { "main", "lt" }, { "rt", "both" } }) do
        local a, b = real[pair[1]], real[pair[2]]
        check(math.min(a[4], b[4]) - math.max(a[2], b[2]) <= 0, pair[1] .. " and " .. pair[2] .. " real bars overlap")
    end
    -- Clear of the frames, the map, the targeting pictures and every other piece but the inner diamonds.
    for bar, b in pairs(real) do
        for name, a in pairs(r) do
            if name ~= "inner left diamond" and name ~= "inner right diamond" then
                local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
                local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
                check(not (w > 0 and h > 0), bar .. " real bar overlaps " .. name)
            end
        end
    end
end)

test("plan: sub-menu buttons 138 either side at 188 up", function()
    local Plan = plan()
    eq(Plan.BarSpots().bottom, { x = 0, y = 238, s = 1 })
    local w = Plan.Wheels()
    eq({ w[1].x, w[1].y, w[2].x, w[2].y }, { -138, 188, 138, 188 })
end)

test("plan: no piece overlaps another", function()
    local Plan = plan()
    local r = Plan.Rects()
    local names = {}
    for name in pairs(r) do names[#names + 1] = name end
    table.sort(names)
    local W, H = 1365.33, 768
    -- Every piece the spec names is in the check.
    for _, name in ipairs({ "inner left diamond", "outer left diamond", "inner right diamond", "outer right diamond",
        "player", "pet", "target", "target of target", "target auras", "target cast bar", "map", "title strip",
        "MainHand timer", "OffHand timer", "Ranged timer", "LB+LT button", "RB+RT button", "LB targeting picture",
        "RB targeting picture", "quest tracker", "chat", "buffs and debuffs", "XP bars", "round button" }) do
        check(r[name], "no rectangle for " .. name)
    end
    -- 0.14.0: nothing overlaps (the quest tracker left the right side in 0.13.0).
    for i = 1, #names do
        local a = r[names[i]]
        check(a[1] >= -W / 2 and a[3] <= W / 2 and a[2] >= 0 and a[4] <= H, names[i] .. " is off screen")
        for j = i + 1, #names do
            local b = r[names[j]]
            local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
            local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
            check(not (w > 0 and h > 0), names[i] .. " overlaps " .. names[j] .. " (" .. w .. " by " .. h .. ")")
        end
    end
end)

test("plan: the quest tracker top left, clear of the round button at every size and of the quest arrow", function()
    local Plan = plan()
    local t = Plan.Rects()["quest tracker"]
    local W, H = 1365.33, 768
    eq({ t[1], t[2], t[3], t[4] }, { -W / 2 + 92, H - 5 - 400, -W / 2 + 92 + 260, H - 5 })
    -- The round button (Hub.lua): LEFT of the screen, 10 px in, 56 / 60 / 72 px (UI.lua), 768 / 720 units a pixel,
    -- at the left middle or the upper left (0.24 of the screen's height above the middle).
    local px = 768 / 720
    for _, size in ipairs({ 56, 60, 72 }) do
        for _, up in ipairs({ 0, 0.24 * H }) do
            local s = size * px
            local hub = { -W / 2 + 10 * px, H / 2 + up - s / 2, -W / 2 + 10 * px + s, H / 2 + up + s / 2 }
            local w = math.min(hub[3], t[3]) - math.max(hub[1], t[1])
            local h = math.min(hub[4], t[4]) - math.max(hub[2], t[2])
            check(not (w > 0 and h > 0), "the tracker overlaps the round button (" .. size .. " px, " .. up .. " up)")
        end
    end
    -- The quest arrow at its "top" spot: TOP 0, -40 px, 400 px wide (QuestArrow.lua:103, 110), up to 150%.
    local arrowHalf = 400 * px * 1.5 / 2
    check(t[3] < -arrowHalf, "the tracker reaches the quest arrow")
end)

test("plan: the frames clear the two wheel circles; the wheels may cover the face", function()
    local Plan = plan()
    local r = Plan.Rects()
    for _, wheel in ipairs(Plan.Wheels()) do
        for _, name in ipairs({ "player", "pet", "target", "target of target", "target auras" }) do
            local b = r[name]
            local nx = math.max(b[1], math.min(wheel.x, b[3]))
            local ny = math.max(b[2], math.min(wheel.y, b[4]))
            local d = math.sqrt((nx - wheel.x) ^ 2 + (ny - wheel.y) ^ 2)
            check(d > wheel.r, name .. " reaches the wheel at " .. wheel.x .. " (" .. d .. ")")
        end
    end
end)

test("plan: old saved option values do not change the plan", function()
    local Plan = plan()
    local old = { main = "under", map = 60, frames = "flat", size = 70, fineMain = 1.15, fineSide = 0.85, fineBoth = 0.85, timers = "bars" }
    eq(Plan.Pieces(old), Plan.Pieces())
    -- Only the three timer visibilities count; a value that is not 0, 1 or 2 is its default.
    eq(piece(Plan.Pieces({ ranged = 0, offHand = 1 }), "SwingTimer", "Ranged").settings.Visibility, 0)
    eq(piece(Plan.Pieces({ ranged = "x", offHand = 7 }), "SwingTimer", "OffHand").settings.Visibility, 2)
end)

---------------------------------------------------------------------------
-- Build and Apply
---------------------------------------------------------------------------

local function baseLayout(e)
    return {
        layoutName = "Gamepad",
        layoutType = 0,
        interfaceStyle = 7,
        systems = {
            { system = e.system.Minimap, anchorInfo = { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", offsetX = -5, offsetY = -5 },
              settings = { { setting = e.setting.Minimap.Size, value = 5 } }, isInDefaultPosition = true },
            { system = e.system.ChatFrame, anchorInfo = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", offsetX = 1, offsetY = 2 },
              settings = {}, isInDefaultPosition = true },
            { system = 999, settings = { { setting = 1, value = 2 } }, anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
              isInDefaultPosition = true },
        },
    }
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

test("layout: Build changes the template's pieces, leaves the rest and the base alone", function()
    local Plan = plan()
    local e = fakeEnums()
    local base = baseLayout(e)
    local before = deepCopy(base)
    local layout = Plan.Build(base, with(Plan.DEFAULTS), e)
    eq(base, before, "the base table changed")
    check(layout ~= base, "the base itself was returned")
    eq(layout.layoutName, "Pocket Essentials")
    eq(layout.layoutName, Plan.NAME)
    eq(layout.layoutType, e.layoutType.Account)
    eq(layout.interfaceStyle, e.style.Gamepad)
    eq(layout.systems[3], base.systems[3], "an unrelated system changed")
    local map = layout.systems[1]
    eq(map.isInDefaultPosition, false)
    eq(map.anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = -10, offsetY = 38 })
    eq(settingValue(map, e.setting.Minimap.Size), 2)
    -- A setting missing from the entry is appended.
    local chat = layout.systems[2]
    eq(settingValue(chat, e.setting.ChatFrame.WidthHundreds), 4)
    eq(settingValue(chat, e.setting.ChatFrame.HeightTensAndOnes), 10)
    eq(#chat.settings, 4)
    -- A piece whose system is absent adds nothing.
    eq(#layout.systems, 3)
end)

test("layout: Apply changes only the pieces given and reports how many it changed", function()
    local Plan = plan()
    local e = fakeEnums()
    local layout = baseLayout(e)
    local list = Plan.Pieces(with(Plan.DEFAULTS))
    local only = { piece(list, "Minimap"), piece(list, "UnitFrame", "Pet") }
    eq(Plan.Apply(layout, only, e), 1, "only the Minimap is in this layout")
    eq(layout.systems[1].anchorInfo.offsetY, 38)
    eq(layout.systems[2].isInDefaultPosition, true)
    eq(Plan.Apply(layout, {}, e), 0)
end)

test("layout: a piece with an index only changes the entry with that index", function()
    local Plan = plan()
    local e = fakeEnums()
    local layout = { systems = {
        { system = e.system.UnitFrame, systemIndex = 1, settings = {}, isInDefaultPosition = true,
          anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 } },
        { system = e.system.UnitFrame, systemIndex = 8, settings = {}, isInDefaultPosition = true,
          anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 } },
    } }
    eq(Plan.Apply(layout, Plan.Pieces(with(Plan.DEFAULTS)), e), 2)
    eq(layout.systems[1].anchorInfo.offsetY, 56)
    eq(layout.systems[2].anchorInfo.offsetY, 181)
    eq(layout.systems[2].isInDefaultPosition, false)
end)

test("layout: Apply drops a second anchor when it sets an anchor, and keeps it for settings only", function()
    local Plan = plan()
    local e = fakeEnums()
    local layout = baseLayout(e)
    local second = { point = "TOP", relativeTo = "UIParent", relativePoint = "TOP", offsetX = 1, offsetY = 1 }
    layout.systems[1].anchorInfo2 = deepCopy(second)
    layout.systems[2].anchorInfo2 = deepCopy(second)
    local list = Plan.Pieces(with({}))
    Plan.Apply(layout, { piece(list, "Minimap") }, e)
    eq(layout.systems[1].anchorInfo2, nil)
    eq(layout.systems[2].anchorInfo2, second, "an untouched entry lost its second anchor")
    local settingsOnly = { system = "ChatFrame", settings = { WidthHundreds = 4 } }
    Plan.Apply(layout, { settingsOnly }, e)
    eq(layout.systems[2].anchorInfo2, second, "a settings-only piece dropped the second anchor")
end)

---------------------------------------------------------------------------
-- 0.11.1 template changes (spec 2026-11-23-controller-layout-0.11.1.md, 1, 3 and 4)
---------------------------------------------------------------------------

test("plan: XP bars top middle at 100%", function()
    local Plan = plan()
    for _, o in ipairs({ with(Plan.DEFAULTS), with({ offHand = 0 }) }) do
        local list = Plan.Pieces(o)
        local one = piece(list, "StatusTrackingBar", "StatusTrackingBar1")
        eq(one.anchor, { point = "TOP", relativeTo = "UIParent", relativePoint = "TOP", x = 0, y = -2 })
        eq(one.settings, { Size = 10 })
        eq(one.moved, true)
        -- The second bar right under the first: a bar is 17 high (STATUS_BAR_CONTAINER_HEIGHT,
        -- Blizzard_StatusTrackingBar/Camelot/StatusTrackingBarConstants.lua:2).
        local two = piece(list, "StatusTrackingBar", "StatusTrackingBar2")
        eq(two.anchor, { point = "TOP", relativeTo = "UIParent", relativePoint = "TOP", x = 0, y = -19 })
        eq(two.settings, { Size = 10 })
        eq(two.moved, true)
    end
    -- Written into a layout: both entries get the spot, the size, and leave their default position.
    local e = fakeEnums()
    local base = { systems = {
        { system = e.system.StatusTrackingBar, systemIndex = 1, isInDefaultPosition = true,
          settings = { { setting = e.setting.StatusTrackingBar.Size, value = 16 } },
          anchorInfo = { point = "BOTTOM", relativeTo = "StatusTrackingBarManager", relativePoint = "BOTTOM", offsetX = 0, offsetY = 0 } },
        { system = e.system.StatusTrackingBar, systemIndex = 2, isInDefaultPosition = true,
          settings = { { setting = e.setting.StatusTrackingBar.Size, value = 16 } },
          anchorInfo = { point = "BOTTOM", relativeTo = "StatusTrackingBarManager", relativePoint = "BOTTOM", offsetX = 0, offsetY = 17 } },
    } }
    local layout = Plan.Build(base, with(Plan.DEFAULTS), e)
    eq(layout.systems[1].anchorInfo, { point = "TOP", relativeTo = "UIParent", relativePoint = "TOP", offsetX = 0, offsetY = -2 })
    eq(layout.systems[2].anchorInfo, { point = "TOP", relativeTo = "UIParent", relativePoint = "TOP", offsetX = 0, offsetY = -19 })
    for i = 1, 2 do
        eq(settingValue(layout.systems[i], e.setting.StatusTrackingBar.Size), 10, "bar " .. i .. " size")
        eq(layout.systems[i].isInDefaultPosition, false, "bar " .. i .. " moved")
    end
end)

test("plan: minimap header underneath", function()
    local Plan = plan()
    local e = fakeEnums()
    eq(piece(Plan.Pieces(), "Minimap").settings.HeaderUnderneath, 1)
    local layout = Plan.Build(baseLayout(e), with(Plan.DEFAULTS), e)
    eq(settingValue(layout.systems[1], e.setting.Minimap.HeaderUnderneath), 1)
    eq(settingValue(layout.systems[1], e.setting.Minimap.Size), 2)
    eq(#layout.systems[1].settings, 2, "Size and HeaderUnderneath")
end)

test("plan: no HeaderUnderneath enum leaves it out", function()
    local Plan = plan()
    local e = fakeEnums()
    e.setting.Minimap.HeaderUnderneath = nil
    local layout = Plan.Build(baseLayout(e), with(Plan.DEFAULTS), e)
    local map = layout.systems[1]
    eq(#map.settings, 1, "only Size")
    eq(settingValue(map, e.setting.Minimap.Size), 2)
    eq(map.anchorInfo.offsetY, 38)
end)

test("plan: buffs, debuffs, tracker spots", function()
    local Plan = plan()
    local list = Plan.Pieces(with(Plan.DEFAULTS))
    eq(piece(list, "AuraFrame", "BuffFrame").anchor,
        { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -30, y = -292 })
    eq(piece(list, "AuraFrame", "DebuffFrame").anchor,
        { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -30, y = -330 })
    local quest = piece(list, "ObjectiveTracker")
    eq(quest.anchor, { point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "TOPLEFT", x = 92, y = -5 })
    eq(quest.settings, { Height = 0 })
    -- The chat box keeps its spot and size.
    local chat = piece(list, "ChatFrame")
    eq(chat.anchor, { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -30, y = -40 })
    eq(chat.settings, { WidthHundreds = 4, WidthTensAndOnes = 30, HeightHundreds = 2, HeightTensAndOnes = 10 })
end)

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

test("layout: registered, off, with its defaults, a Controller tab and no work while off", function()
    local c, PE = T.new({})
    local mod = PE:GetModule("ctrlLayout")
    check(mod ~= nil, "the feature did not register")
    eq(mod.label, "Controller layout")
    eq(mod.desc, "Map bottom middle, a spell panel each side (hold LT or RT to swap), chat top right.")
    eq(mod.order, 60)
    eq(mod.experimental, true)
    eq(mod.statusWhenOff, true)
    check(not PE:IsModuleEnabled("ctrlLayout"), "the feature is on at first install")
    for k, v in pairs(PE.LayoutPlan.DEFAULTS) do eq(mod.defaults[k], v, "default " .. k) end
    eq(mod.defaults.prev, false)
    eq(mod.defaults.prevs, nil, "0.11.1's entries by name are only read")
    eq(mod:status(), "Needs a reload to switch on or off. Off brings back your own layout.")
    eq(PE.SETTINGS_TABS[6].id, "controller")
    eq(PE.SETTINGS_TABS[6].label, "Controller")
    eq(PE.SETTINGS_TABS[6].features, { "ctrlLayout" })
    eq(PE.SETTINGS_TABS[7].id, "gameFixes")
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Switching on and off (spec "Switching on", "Switching off")
---------------------------------------------------------------------------

local NAME = "Pocket Essentials"
local RELOAD = "Reload to finish the layout change."
local USING = "Using the Pocket Essentials layout. Move the map, chat or frames in Edit Mode if you like."
local ANOTHER = "Another Edit Mode layout is active. Pick Pocket Essentials in Edit Mode, or switch this off and on."
local OFF_TEXT = "Needs a reload to switch on or off. Off brings back your own layout."

-- Saved layouts as the game stores them (fake client: Account 1, Character 2, Gamepad style 1).
local function saved(name, layoutType, style)
    return { layoutName = name, layoutType = layoutType or 1, interfaceStyle = style or 1, systems = {
        { system = 2, isInDefaultPosition = true, settings = {},
          anchorInfo = { point = "TOP", relativeTo = "UIParent", relativePoint = "TOP", offsetX = 1, offsetY = 2 } },
    } }
end

-- A client with the Gamepad UI on and this list of saved layouts, `active` counting the three presets.
local function layoutClient(list, active, extra)
    extra = extra or {}
    return T.new({ gamepadUI = extra.gamepadUI ~= false, saved = extra.saved, setup = function(c)
        c.world.layouts = { layouts = list or {}, activeLayout = active or 3 }
        if extra.setup then extra.setup(c) end
    end })
end

local function switchOn(c, PE)
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
end

local function switchOff(c, PE)
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
end

local function statusText(PE)
    local s = PE:GetModule("ctrlLayout"):status()
    if type(s) == "table" then return table.concat(s, "\n") end
    return s
end

local function reloadReason(PE)
    for _, r in ipairs(PE.reloadReasons) do
        if r.key == "ctrlLayout" then return r.reason end
    end
    return nil
end

local function layoutCalls(c)
    return #c:callsTo("C_EditMode.SaveLayouts") + #c:callsTo("C_EditMode.SetActiveLayout") + #c:callsTo("C_EditMode.OnLayoutAdded")
end

local function opts(PE) return PE:GetModule("ctrlLayout").opts end

-- The stand-in's character name and realm (UnitName("player"), GetRealmName()): 0.11.1's key.
local KEY = "Tester-Camelot"

-- This character's own saved table (PocketEssentialsCharDB) in a client.
local function charDB(c) return rawget(c.env, "PocketEssentialsCharDB") end

-- This character's remembered layout (PE.charDB.ctrlLayoutPrev), or nil.
local function prev(PE)
    local t = PE.charDB
    local entry = type(t) == "table" and t.ctrlLayoutPrev or nil
    return type(entry) == "table" and entry or nil
end

-- Every SaveLayouts call sent the whole list the way Blizzard does: the three presets first
-- (Modern, Classic, Gamepad), then the saved layouts. Returns how many calls there were.
local function checkSaves(c)
    local saves = c:callsTo("C_EditMode.SaveLayouts")
    for n, call in ipairs(saves) do
        local list = call.args[1] and call.args[1].layouts
        check(type(list) == "table", "SaveLayouts call " .. n .. " has no list")
        for i = 1, 3 do
            local l = list[i]
            check(type(l) == "table" and l.layoutType == 0 and l.layoutIndex == i - 1,
                "SaveLayouts call " .. n .. ": entry " .. i .. " is not preset " .. (i - 1))
        end
        for i = 4, #list do
            check(list[i].layoutType ~= 0, "SaveLayouts call " .. n .. ": a preset after the presets at " .. i)
        end
    end
    return #saves
end

test("layout: on from the Gamepad preset saves a new account-wide Gamepad layout after the presets and makes it active", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    check(PE:IsModuleEnabled("ctrlLayout"), "the feature did not stay on")
    local saves = c:callsTo("C_EditMode.SaveLayouts")
    eq(#saves, 1, "SaveLayouts calls")
    local list = saves[1].args[1].layouts
    eq(#list, 4, "presets plus the new layout")
    for i = 1, 3 do eq(list[i].layoutType, 0, "preset " .. i .. " first") end
    local ours = list[4]
    eq(ours.layoutName, NAME)
    eq(ours.layoutType, 1, "Account")
    eq(ours.interfaceStyle, 1, "Gamepad")
    eq(ours.layoutIndex, nil, "the preset-only field was kept")
    -- Built from the Gamepad preset: its map moved, its action bar entry untouched.
    eq(ours.systems[1].anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = -10, offsetY = 38 })
    eq(ours.systems[1].isInDefaultPosition, false)
    eq(ours.systems[2].isInDefaultPosition, true)
    local added = c:callsTo("C_EditMode.OnLayoutAdded")
    eq(#added, 1, "OnLayoutAdded calls")
    eq({ added[1].args[1], added[1].args[2], added[1].args[3] }, { 4, true, false })
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 0)
    eq(c.world.layouts.activeLayout, 4)
    eq(c.world.layouts.layouts[1].layoutName, NAME)
    eq(type(prev(PE)), "table")
    eq(prev(PE).preset, 2, "the Gamepad preset's id")
    eq(reloadReason(PE), RELOAD)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("layout: on with two account and one character layout inserts the new one after the account ones", function()
    local c, PE = layoutClient({ saved("A1"), saved("A2"), saved("C1", 2) }, 1)
    switchOn(c, PE)
    local saves = c:callsTo("C_EditMode.SaveLayouts")
    eq(#saves, 1)
    local list = saves[1].args[1].layouts
    eq(#list, 7)
    eq(list[6].layoutName, NAME)
    eq(list[7].layoutName, "C1")
    local added = c:callsTo("C_EditMode.OnLayoutAdded")
    eq(added[1].args[1], 6)
    eq(c.world.layouts.layouts[3].layoutName, NAME)
    eq(c.world.layouts.activeLayout, 6)
    -- Modern was active: remembered by its preset id.
    eq(prev(PE).preset, 0)
    eq(prev(PE).name, "Modern")
    c:assertClean()
end)

test("layout: the template starts from the active layout when that one is a Gamepad layout", function()
    local mine = saved("Mine")
    local c, PE = layoutClient({ mine }, 4)
    switchOn(c, PE)
    local list = c:callsTo("C_EditMode.SaveLayouts")[1].args[1].layouts
    local ours = list[5]
    eq(ours.layoutName, NAME)
    eq(#ours.systems, 1, "not built from the Gamepad preset")
    eq(ours.systems[1].anchorInfo.offsetY, 38)
    eq(list[4].layoutName, "Mine")
    eq(list[4].systems[1].anchorInfo.offsetY, 2, "the player's own layout changed")
    eq(prev(PE), { name = "Mine", layoutType = 1 })
    c:assertClean()
end)

test("layout: on writes the map's title under the map; a game without that setting leaves it out", function()
    -- The stand-in's Gamepad preset has the map as system 2 with Size (setting 2) = 5;
    -- HeaderUnderneath is setting 0 (EditModeManagerConstantsDocumentation.lua:580).
    local function mapEntry(c)
        for _, l in ipairs(c.world.layouts.layouts) do
            if l.layoutName == NAME then
                for _, entry in ipairs(l.systems) do if entry.system == 2 then return entry end end
            end
        end
    end
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    local map = mapEntry(c)
    check(map, "no map entry in our layout")
    local values = {}
    for _, st in ipairs(map.settings) do values[st.setting] = st.value end
    eq(values, { [0] = 1, [2] = 2 })
    c:assertClean()
    local c2, PE2 = layoutClient({}, 3, { setup = function(c2) rawset(c2.env.Enum.EditModeMinimapSetting, "HeaderUnderneath", nil) end })
    switchOn(c2, PE2)
    check(PE2:IsModuleEnabled("ctrlLayout"), "the feature did not stay on")
    local map2 = mapEntry(c2)
    eq(#map2.settings, 1, "only Size")
    eq(map2.settings[1].value, 2)
end)

test("layout: on with five account layouts refuses, says why, and switches back off", function()
    local c, PE = layoutClient({ saved("A1"), saved("A2"), saved("A3"), saved("A4"), saved("A5") }, 3)
    switchOn(c, PE)
    eq(layoutCalls(c), 0, "a layout call was made")
    check(not PE:IsModuleEnabled("ctrlLayout"), "the feature stayed on")
    eq(PE:IsModuleSavedOn("ctrlLayout"), false)
    local text = statusText(PE)
    check(text:find("You already have 5 account-wide layouts. Delete one in Edit Mode, then switch this on again.", 1, true),
        "status: " .. tostring(text))
    eq(prev(PE), nil)
    eq(reloadReason(PE), nil)
    c:assertClean()
    -- The refusal goes away when the player tries again.
    c.world.layouts.layouts[5] = nil
    switchOn(c, PE)
    eq(statusText(PE), USING)
end)

test("layout: on when Pocket Essentials already exists activates it and leaves it as it is", function()
    local ours = saved(NAME)
    ours.systems[1].anchorInfo.offsetX = 123 -- the player's own change
    local c, PE = layoutClient({ saved("A1"), ours }, 4)
    opts(PE).template = PE.LayoutPlan.TEMPLATE -- built from this template (an older one is rebuilt first)
    switchOn(c, PE)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 0)
    eq(#c:callsTo("C_EditMode.OnLayoutAdded"), 0)
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(#set, 1)
    eq(set[1].args[1], 5)
    eq(c.world.layouts.activeLayout, 5)
    eq(c.world.layouts.layouts[2].systems[1].anchorInfo.offsetX, 123)
    eq(prev(PE), { name = "A1", layoutType = 1 })
    eq(reloadReason(PE), RELOAD)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("layout: on when Pocket Essentials is already the active layout changes nothing", function()
    local c, PE = layoutClient({ saved(NAME) }, 4)
    switchOn(c, PE)
    eq(layoutCalls(c), 0)
    check(PE:IsModuleEnabled("ctrlLayout"), "the feature did not stay on")
    eq(type(prev(PE)), "table")
    eq(reloadReason(PE), nil)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("layout: on while Edit Mode is open refuses and switches back off", function()
    local c, PE = layoutClient({}, 3, { setup = function(c) c.world.editMode = true end })
    switchOn(c, PE)
    eq(layoutCalls(c), 0)
    check(not PE:IsModuleEnabled("ctrlLayout"), "the feature stayed on")
    check(statusText(PE):find("Close Edit Mode first.", 1, true), "status: " .. tostring(statusText(PE)))
    check(statusText(PE):find(OFF_TEXT, 1, true), "the reload note went away")
    c:assertClean()
end)

test("layout: on when the game refuses the name refuses and switches back off", function()
    local c, PE = layoutClient({}, 3, { setup = function(c) c.world.layoutNameRefused = true end })
    switchOn(c, PE)
    eq(layoutCalls(c), 0)
    check(not PE:IsModuleEnabled("ctrlLayout"), "the feature stayed on")
    check(statusText(PE):find("The game refused the layout name.", 1, true), "status: " .. tostring(statusText(PE)))
    c:assertClean()
end)

test("layout: on in combat waits for the fight to end", function()
    local c, PE = layoutClient({}, 3)
    c:enterCombat()
    switchOn(c, PE)
    eq(layoutCalls(c), 0, "a layout call in combat")
    c:leaveCombat()
    c:advance(0.1)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(c.world.layouts.activeLayout, 4)
    c:assertClean()
end)

test("layout: on and off again in one fight changes nothing", function()
    local c, PE = layoutClient({}, 3)
    c:enterCombat()
    switchOn(c, PE)
    switchOff(c, PE)
    c:leaveCombat()
    c:advance(0.1)
    eq(layoutCalls(c), 0)
    eq(reloadReason(PE), nil)
    c:assertClean()
end)

test("layout: blocked without the game's Gamepad UI", function()
    local c, PE = layoutClient({}, 3, { gamepadUI = false })
    local state, detail = PE:GetModuleState("ctrlLayout")
    eq(state, "blocked")
    eq(detail, "Needs the game's Gamepad UI (Options, Controller, Enable Gamepad UI).")
    switchOn(c, PE)
    check(not PE:IsModuleEnabled("ctrlLayout"), "switched on while blocked")
    eq(layoutCalls(c), 0)
    c:assertClean()
end)

test("layout: not blocked with the Gamepad UI on", function()
    local _, PE = layoutClient({}, 3)
    eq(PE:GetModuleState("ctrlLayout"), "off")
end)

test("layout: a layout list that raises or is empty logs an error and switches back off", function()
    for _, how in ipairs({ "raises", "empty" }) do
        local c, PE = layoutClient({}, 3, { setup = function(c)
            if how == "raises" then c.world.layoutsBroken = true else c.world.layouts = {} end
        end })
        switchOn(c, PE)
        check(#PE.errors >= 1, how .. ": no error logged")
        check(not PE:IsModuleEnabled("ctrlLayout"), how .. ": the feature stayed on")
        eq(#c:callsTo("C_EditMode.SaveLayouts"), 0, how)
        eq(prev(PE), nil, how)
    end
end)

test("layout: off brings back the remembered preset, keeps our layout saved, and asks for a reload", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    PE.reloadReasons[1] = nil
    switchOff(c, PE)
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(#set, 1)
    eq(set[1].args[1], 3)
    eq(c.world.layouts.activeLayout, 3)
    eq(prev(PE), nil)
    eq(reloadReason(PE), RELOAD)
    eq(c.world.layouts.layouts[1].layoutName, NAME, "our layout was deleted")
    eq(statusText(PE), OFF_TEXT)
    c:assertClean()
end)

test("layout: off brings back a remembered saved layout by name and type", function()
    local c, PE = layoutClient({ saved("Mine", 2), saved(NAME) }, 4)
    switchOn(c, PE)
    eq(c.world.layouts.activeLayout, 5)
    -- The player renames nothing, but the list order changes: found by name, not index.
    local list = c.world.layouts.layouts
    list[1], list[2] = list[2], list[1]
    c.world.layouts.activeLayout = 4
    switchOff(c, PE)
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(set[#set].args[1], 5)
    eq(c.world.layouts.activeLayout, 5)
    eq(c.world.layouts.layouts[2].layoutName, "Mine")
    c:assertClean()
end)

test("layout: off with the remembered layout deleted falls back to the Gamepad preset", function()
    local c, PE = layoutClient({ saved("Mine") }, 4)
    switchOn(c, PE)
    eq(c.world.layouts.activeLayout, 5)
    -- The player deletes "Mine" in Edit Mode.
    c.world.layouts = { layouts = { c.world.layouts.layouts[2] }, activeLayout = 4 }
    eq(c.world.layouts.layouts[1].layoutName, NAME)
    switchOff(c, PE)
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(set[#set].args[1], 3)
    eq(c.world.layouts.activeLayout, 3)
    c:assertClean()
end)

test("layout: off when another layout is active leaves the layouts alone", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    c.world.layouts.activeLayout = 1 -- the player picked Modern in Edit Mode
    eq(statusText(PE), ANOTHER)
    switchOff(c, PE)
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 0)
    eq(c.world.layouts.activeLayout, 1)
    eq(prev(PE), nil)
    c:assertClean()
end)

test("layout: a later login with the feature on changes no layout", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    local db = rawget(c.env, "PocketEssentialsDB")
    local c2, PE2 = T.new({ gamepadUI = true, saved = db, savedChar = charDB(c), setup = function(c2) c2.world.layouts = c.world.layouts end })
    check(PE2:IsModuleEnabled("ctrlLayout"), "not on after the login")
    eq(layoutCalls(c2), 0, "a layout call at login")
    eq(reloadReason(PE2), nil)
    eq(statusText(PE2), USING)
    c2:assertClean()
    -- Another layout picked meanwhile: still nothing changed, and the status says so.
    local c3, PE3 = T.new({ gamepadUI = true, saved = db, savedChar = charDB(c), setup = function(c3)
        c3.world.layouts = { layouts = c.world.layouts.layouts, activeLayout = 2 }
    end })
    eq(layoutCalls(c3), 0)
    eq(statusText(PE3), ANOTHER)
    c3:assertClean()
end)

---------------------------------------------------------------------------
-- Switching on: game calls that fail or answer late (review of task 2)
---------------------------------------------------------------------------

test("layout: every SaveLayouts call starts with the three presets", function()
    local c, PE = layoutClient({ saved("A1"), saved("C1", 2) }, 1)
    switchOn(c, PE)
    eq(checkSaves(c), 1)
    c:assertClean()
end)

test("layout: the stand-in records a SaveLayouts call whose list does not start with the presets", function()
    local c = layoutClient({}, 3)
    local ok = pcall(c.env.C_EditMode.SaveLayouts, { layouts = { saved("A1") }, activeLayout = 3 })
    eq(ok, false)
    eq(#c.errors, 1)
    eq(#c.world.layouts.layouts, 0, "the list was saved anyway")
end)

test("layout: on when the re-read does not show ours active yet stays on and asks for the reload", function()
    local c, PE = layoutClient({}, 3, { setup = function(c) c.world.layoutsLag = true end })
    switchOn(c, PE)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    check(PE:IsModuleEnabled("ctrlLayout"), "the feature switched itself off")
    eq(PE:IsModuleSavedOn("ctrlLayout"), true)
    eq(type(prev(PE)), "table")
    eq(reloadReason(PE), RELOAD)
    eq(statusText(PE), ANOTHER)
    c:assertClean()
end)

test("layout: on when SaveLayouts raises logs it, switches back off and remembers nothing", function()
    local c, PE = layoutClient({}, 3, { setup = function(c) c.world.layoutCallFails.SaveLayouts = true end })
    switchOn(c, PE)
    check(#PE.errors >= 1, "no error logged")
    check(not PE:IsModuleEnabled("ctrlLayout"), "the feature stayed on")
    eq(prev(PE), nil)
    eq(#c:callsTo("C_EditMode.OnLayoutAdded"), 0)
    eq(reloadReason(PE), nil)
end)

test("layout: on when OnLayoutAdded raises logs it and switches back off; our saved layout stays", function()
    local c, PE = layoutClient({}, 3, { setup = function(c) c.world.layoutCallFails.OnLayoutAdded = true end })
    switchOn(c, PE)
    check(#PE.errors >= 1, "no error logged")
    check(not PE:IsModuleEnabled("ctrlLayout"), "the feature stayed on")
    eq(c.world.layouts.layouts[1].layoutName, NAME)
    eq(c.world.layouts.activeLayout, 3, "the previous layout is still the active one")
    eq(prev(PE), nil, "the switch-off ran and found nothing to undo")
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 0)
end)

test("layout: on with a character layout first and an account layout after inserts after the account one", function()
    local c, PE = layoutClient({ saved("C1", 2), saved("A1") }, 3)
    switchOn(c, PE)
    eq(c:callsTo("C_EditMode.OnLayoutAdded")[1].args[1], 6)
    local list = c.world.layouts.layouts
    eq({ list[1].layoutName, list[2].layoutName, list[3].layoutName }, { "C1", "A1", NAME })
    eq(checkSaves(c), 1)
    c:assertClean()
end)

test("layout: off brings back a remembered character layout by name and type", function()
    local c, PE = layoutClient({ saved("Mine", 2) }, 4)
    switchOn(c, PE)
    eq(prev(PE), { name = "Mine", layoutType = 2 })
    eq(c.world.layouts.activeLayout, 4, "ours goes before the character layout")
    switchOff(c, PE)
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(set[#set].args[1], 5, "Mine moved to index 5")
    eq(c.world.layouts.layouts[2].layoutName, "Mine")
    c:assertClean()
end)

test("layout: off when SetActiveLayout raises keeps the remembered layout for the next try", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    c.world.layoutCallFails.SetActiveLayout = true
    switchOff(c, PE)
    check(#PE.errors >= 1, "no error logged")
    eq(type(prev(PE)), "table", "the remembered layout was forgotten")
    -- On and off again once the game takes the call: back to the Gamepad preset.
    PE:ClearErrors()
    c.world.layoutCallFails.SetActiveLayout = nil
    switchOn(c, PE)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1, "on again wrote another layout")
    switchOff(c, PE)
    eq(c.world.layouts.activeLayout, 3)
    eq(prev(PE), nil)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Bars (spec "Bars (placed by the addon)", "While on", "Switching off" step 1)
---------------------------------------------------------------------------

-- The five frames the addon moves, from the stand-in's GamepadMainActionBarFrame.
local function barFrames(c)
    local pu = c.env.GamepadMainActionBarFrame.PageUnit
    return {
        top = pu.TopCenteredAnchor, left = pu.LeftCenteredAnchor, right = pu.RightCenteredAnchor,
        bottom = pu.BottomCenteredAnchor, both = pu.BottomCenteredAnchor.Bar,
    }, pu
end

-- Points and scale of a frame, read from the stand-in's own record (no method call).
local function frameState(c, f)
    local st = c._state(f)
    local points = {}
    for i, p in ipairs(st.points) do points[i] = { p.point, p.rel, p.relPoint, p.x, p.y } end
    return { points = points, scale = st.scale }
end

local function allStates(c)
    local out = {}
    for k, f in pairs((barFrames(c))) do out[k] = frameState(c, f) end
    return out
end

-- Calls the addon (or anyone) made on the bar frames, from c.calls.
local function barCalls(c, method)
    local n = 0
    for _, call in ipairs(c.calls) do
        if call.name:match("^GamepadBar%.") and (method == nil or call.name:match(":" .. method .. "$")) then n = n + 1 end
    end
    return n
end

-- The frame sits where Plan.BarSpots puts that group: CENTER on UIParent's BOTTOM at (x / s, y / s), scale s.
local function placedAt(c, f, spot, what)
    local st = frameState(c, f)
    eq(#st.points, 1, what .. ": number of points")
    local p = st.points[1]
    eq({ p[1], p[2], p[3] }, { "CENTER", c.env.UIParent, "BOTTOM" }, what .. ": anchor")
    near(p[4], spot.x / spot.s, what .. ": x")
    near(p[5], spot.y / spot.s, what .. ": y")
    near(st.scale, spot.s, what .. ": scale")
end

test("layout: on with ours active places the bar anchors and the both-triggers bar", function()
    local c, PE = layoutClient({}, 3)
    local spots = PE.LayoutPlan.BarSpots(PE.LayoutPlan.DEFAULTS)
    switchOn(c, PE)
    local f = barFrames(c)
    placedAt(c, f.left, spots.left, "left")
    near(frameState(c, f.left).scale, 0.6, "left scale")
    placedAt(c, f.right, spots.right, "right")
    placedAt(c, f.top, spots.top, "top")
    placedAt(c, f.bottom, spots.bottom, "bottom")
    eq(frameState(c, f.bottom).scale, 1)
    placedAt(c, f.both, spots.both, "both-triggers bar")
    near(frameState(c, f.both).scale, 0.6, "both-triggers scale")
    c:assertClean()
end)

test("layout: the bars are never touched in combat, and placed once the fight ends", function()
    local c, PE = layoutClient({}, 3)
    local before = allStates(c)
    c:enterCombat()
    switchOn(c, PE)
    eq(barCalls(c, "SetPoint") + barCalls(c, "SetScale") + barCalls(c, "ClearAllPoints"), 0)
    eq(allStates(c), before)
    c:leaveCombat()
    c:advance(0.1)
    check(barCalls(c, "SetPoint") >= 5, "the bars were not placed after the fight")
    -- An Edit Mode change during a fight waits too.
    local calls = barCalls(c)
    c:enterCombat()
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    local _, pu = barFrames(c)
    pu:RefreshCompactLayout()
    eq(barCalls(c) - calls, 0, "a bar frame was touched in combat")
    c:leaveCombat()
    c:advance(0.1)
    placedAt(c, barFrames(c).left, PE.LayoutPlan.BarSpots(PE.LayoutPlan.DEFAULTS).left, "left after the fight")
    c:assertClean()
end)

test("layout: another layout picked puts the bars back as the game had them", function()
    local c, PE = layoutClient({}, 3)
    local before = allStates(c)
    switchOn(c, PE)
    c.world.layouts.activeLayout = 1
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(allStates(c), before)
    check(statusText(PE):find("Another Edit Mode layout is active", 1, true), "status: " .. tostring(statusText(PE)))
    -- Picked again: placed again.
    c.world.layouts.activeLayout = 4
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    placedAt(c, barFrames(c).left, PE.LayoutPlan.BarSpots().left, "placed again")
    c:assertClean()
end)

test("layout: our layout deleted puts the bars back, with no error", function()
    local c, PE = layoutClient({}, 3)
    local before = allStates(c)
    switchOn(c, PE)
    c.world.layouts = { layouts = {}, activeLayout = 3 }
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(allStates(c), before)
    check(statusText(PE):find("Another Edit Mode layout is active", 1, true), "status: " .. tostring(statusText(PE)))
    c:assertClean()
end)

test("layout: the game's RefreshCompactLayout re-anchors the bars; while on they are placed again, while off left alone", function()
    local c, PE = layoutClient({}, 3)
    local spots = PE.LayoutPlan.BarSpots(PE.LayoutPlan.DEFAULTS)
    switchOn(c, PE)
    local f, pu = barFrames(c)
    pu:RefreshCompactLayout()
    placedAt(c, f.left, spots.left, "left")
    placedAt(c, f.top, spots.top, "top")
    switchOff(c, PE)
    local calls = barCalls(c)
    pu:RefreshCompactLayout()
    c:advance(0.1)
    eq(barCalls(c) - calls, 0, "a bar frame was touched while off")
    c:assertClean()
end)

test("layout: off puts every bar frame back exactly as it was, and is clean", function()
    local c, PE = layoutClient({}, 3)
    local before = allStates(c)
    switchOn(c, PE)
    check(barCalls(c, "SetPoint") >= 5, "the bars were not placed")
    switchOff(c, PE)
    eq(allStates(c), before)
    c:assertClean()
end)

test("layout: off restores the bars even when no layout was changed (ours was already active)", function()
    local c, PE = layoutClient({ saved(NAME) }, 4)
    local before = allStates(c)
    switchOn(c, PE)
    placedAt(c, barFrames(c).left, PE.LayoutPlan.BarSpots().left, "placed")
    switchOff(c, PE)
    eq(allStates(c), before)
    c:assertClean()
end)

test("layout: a later login with the feature on places the bars", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    local db = rawget(c.env, "PocketEssentialsDB")
    local c2, PE2 = T.new({ gamepadUI = true, saved = db, savedChar = charDB(c), setup = function(c2) c2.world.layouts = c.world.layouts end })
    placedAt(c2, barFrames(c2).left, PE2.LayoutPlan.BarSpots(PE2.LayoutPlan.DEFAULTS).left, "left at login")
    c2:assertClean()
end)

test("layout: without the bar anchors nothing is placed and nothing fails", function()
    local c, PE = layoutClient({}, 3, { setup = function(c)
        c.barParts[c.env.GamepadMainActionBarFrame].PageUnit = nil
    end })
    switchOn(c, PE)
    check(PE:IsModuleEnabled("ctrlLayout"), "the feature switched off")
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    switchOff(c, PE)
    c:assertClean()
end)

test("layout: the stand-in's bar frames refuse a field written on them", function()
    local c = layoutClient({}, 3)
    local ok = pcall(function() barFrames(c).left.peSaved = 1 end)
    eq(ok, false)
    eq(#c.errors, 1)
end)

test("layout: the stand-in's bar frames refuse moves in combat", function()
    local c = layoutClient({}, 3)
    c:enterCombat()
    local ok = pcall(function() barFrames(c).left:SetScale(1) end)
    eq(ok, false)
    c:leaveCombat()
end)

---------------------------------------------------------------------------
-- Option rows (spec "Options on the card")
---------------------------------------------------------------------------

local START_OVER_ASK = "Tap Start over again to put every piece back. Changes you made in Edit Mode are lost."

local function optRow(PE, keyOrLabel)
    for _, o in ipairs(PE:GetModule("ctrlLayout").options or {}) do
        if o.key == keyOrLabel or o.label == keyOrLabel then return o end
    end
    return nil
end

-- A tap on a choice or number row, the way the settings window does it (Settings.lua ChooseHandler).
local function choose(c, PE, key, value)
    local m = PE:GetModule("ctrlLayout")
    local o = optRow(PE, key)
    check(o ~= nil, "no option row " .. key)
    m.opts[key] = value
    if o.OnChange then PE:Safe("ctrlLayout", o.OnChange, m, value) end
    c:advance(0.1)
end

local function tapStartOver(c, PE)
    local o = optRow(PE, "Rebuild the layout")
    check(o ~= nil and type(o.action) == "function", "no Start over row")
    PE:Safe("ctrlLayout", o.action, PE:GetModule("ctrlLayout"))
    c:advance(0.1)
end

-- An entry of a saved layout by system number and index (stand-in Enum values).
local function entryOf(layout, system, index)
    for _, e in ipairs(layout.systems) do
        if e.system == system and (index == nil or e.systemIndex == index) then return e end
    end
    return nil
end

local SYS = { Minimap = 2, UnitFrame = 3, ChatFrame = 8, SwingTimer = 29 }
local SWING = { MainHand = 1, OffHand = 2, Ranged = 3 }
local VISIBILITY = 2 -- Enum.EditModeSwingTimerSetting.Visibility in the stand-in

-- Switched on from the Gamepad preset (ours built and active), the reload request cleared.
local function onClient(extra)
    local c, PE = layoutClient({}, 3, extra)
    switchOn(c, PE)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    PE:GetModule("ctrlLayout"):CancelReload()
    return c, PE
end

local function ours(c)
    for _, l in ipairs(c.world.layouts.layouts) do if l.layoutName == NAME then return l end end
    return nil
end

test("rows: Spell panel size, the three timer rows and Start over", function()
    local _, PE = layoutClient({}, 3)
    local list = PE:GetModule("ctrlLayout").options
    local labels = {}
    for i, o in ipairs(list) do labels[i] = o.label end
    eq(labels, { "Spell panel size", "Ranged timer", "Main hand timer", "Off hand timer", "Rebuild the layout" })
    eq(list[1].key, "panelSize")
    local n = list[1].number
    eq({ n.min, n.max, n.step, n.default, n.suffix }, { 80, 120, 10, 100, "%" })
    eq(PE:GetModule("ctrlLayout").opts.panelSize, 100, "the default")
    for i, key in ipairs({ "ranged", "mainHand", "offHand" }) do
        eq(list[i + 1].key, key)
        local out = {}
        for j, ch in ipairs(list[i + 1].choices) do out[j] = { ch.value, ch.label } end
        eq(out, { { 0, "Always" }, { 1, "In combat" }, { 2, "Hidden" } })
    end
    eq(list[5].button, "Start over")
    eq(type(list[5].action), "function")
end)

test("rows: old saved values for the removed rows change nothing", function()
    local file = { enabled = { ctrlLayout = false }, options = { ctrlLayout = {
        main = "under", map = 60, frames = "flat", size = 70, fineMain = 1.15, fineSide = 0.85, fineBoth = 0.85, timers = "bars" } } }
    local c, PE = T.new({ gamepadUI = true, saved = file, setup = function(c) c.world.layouts = { layouts = {}, activeLayout = 3 } end })
    switchOn(c, PE)
    local spots = PE.LayoutPlan.BarSpots()
    local f = barFrames(c)
    placedAt(c, f.left, spots.left, "left")
    placedAt(c, f.both, spots.both, "both")
    local map = entryOf(ours(c), SYS.Minimap)
    eq(map.anchorInfo.offsetY, 38)
    eq(opts(PE).map, 60, "the old value no longer stays in the file")
    c:assertClean()
end)

test("layout: Ranged timer changes only that timer's Visibility", function()
    local c, PE = onClient()
    local expected = deepCopy(ours(c))
    for _, s in ipairs(entryOf(expected, SYS.SwingTimer, SWING.Ranged).settings) do
        if s.setting == VISIBILITY then s.value = 2 end
    end
    choose(c, PE, "ranged", 2)
    eq(checkSaves(c), 2)
    eq(ours(c), expected)
    c:assertClean()
end)

test("layout: Off Hand timer changes only that timer's Visibility", function()
    local c, PE = onClient()
    local expected = deepCopy(ours(c))
    for _, s in ipairs(entryOf(expected, SYS.SwingTimer, SWING.OffHand).settings) do
        if s.setting == VISIBILITY then s.value = 0 end
    end
    choose(c, PE, "offHand", 0)
    eq(checkSaves(c), 2)
    eq(ours(c), expected)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
end)

test("layout: an option that changes the layout is refused while Edit Mode is open and put back", function()
    local c, PE = onClient()
    c.world.editMode = true
    choose(c, PE, "ranged", 2)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(statusText(PE), "Close Edit Mode first.")
    eq(opts(PE).ranged, 1)
    -- Edit Mode closed: the next change goes through and the refusal goes away.
    c.world.editMode = false
    choose(c, PE, "ranged", 2)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 2)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("layout: option changes in a fight are written together once it ends", function()
    local c, PE = onClient()
    c:enterCombat()
    choose(c, PE, "ranged", 2)
    choose(c, PE, "offHand", 0)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1, "a save in combat")
    c:leaveCombat()
    c:advance(0.1)
    eq(checkSaves(c), 2, "one save for both changes")
    local function vis(index)
        for _, s in ipairs(entryOf(ours(c), SYS.SwingTimer, index).settings) do
            if s.setting == VISIBILITY then return s.value end
        end
    end
    eq(vis(SWING.Ranged), 2)
    eq(vis(SWING.OffHand), 0)
    c:assertClean()
end)

test("layout: an option change with our layout deleted writes nothing and keeps the choice", function()
    local c, PE = onClient()
    c.world.layouts = { layouts = {}, activeLayout = 3 }
    choose(c, PE, "ranged", 0)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(opts(PE).ranged, 0)
    eq(statusText(PE), ANOTHER)
    c:assertClean()
end)

test("layout: Start over asks for a second tap within 20 seconds, then rebuilds our layout from the template", function()
    local c, PE = onClient()
    -- The player's own changes in Edit Mode.
    local mine = ours(c)
    entryOf(mine, SYS.Minimap).anchorInfo.offsetX = 123
    mine.systems[#mine.systems + 1] = { system = 99, settings = {}, isInDefaultPosition = false,
        anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 } }
    tapStartOver(c, PE)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1, "the first tap wrote")
    eq(statusText(PE), START_OVER_ASK)
    eq(reloadReason(PE), nil)
    c:advance(5)
    tapStartOver(c, PE)
    eq(checkSaves(c), 2)
    local after = ours(c)
    eq(after.layoutName, NAME)
    eq(after.layoutType, 1)
    eq(after.interfaceStyle, 1)
    eq(after.layoutIndex, nil)
    eq(entryOf(after, SYS.Minimap).anchorInfo.offsetX, -10)
    eq(entryOf(after, 99), nil, "a system not in the template stayed")
    eq(#after.systems, #c.env.EditModePresetLayoutManager:GetCopyOfPresetLayouts()[3].systems)
    eq(c.world.layouts.activeLayout, 4, "ours is still the active one")
    eq(reloadReason(PE), RELOAD)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("layout: a Start over tap after 20 seconds counts as a first tap", function()
    local c, PE = onClient()
    tapStartOver(c, PE)
    c:advance(21)
    tapStartOver(c, PE)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(statusText(PE), START_OVER_ASK)
    c:advance(3)
    tapStartOver(c, PE)
    eq(checkSaves(c), 2)
    c:assertClean()
end)

test("layout: Start over is refused while Edit Mode is open", function()
    local c, PE = onClient()
    tapStartOver(c, PE)
    c.world.editMode = true
    tapStartOver(c, PE)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(statusText(PE), "Close Edit Mode first.")
    c:assertClean()
end)

test("layout: the settings window's Controller tab draws the rows while on, and a tap there rewrites the layout", function()
    local c, PE = onClient()
    PE:OpenSettings("controller")
    c:advance(0.2)
    local panel = rawget(c.env, "PocketEssentialsSettingsPanel")
    local function walk(w, fn, seen)
        seen = seen or {}
        if seen[w] then return end
        seen[w] = true
        fn(w)
        local st = c._state(w)
        for _, ch in ipairs(st.children) do walk(ch, fn, seen) end
        if st.scrollChild then walk(st.scrollChild, fn, seen) end
    end
    local texts, buttons = {}, {}
    walk(panel, function(w)
        local st = c._state(w)
        if st.type == "Button" and w:IsVisible() then buttons[T.labelOf(w)] = buttons[T.labelOf(w)] or w end
        for _, r in ipairs(st.regions) do
            local rs = c._state(r)
            if rs.type == "FontString" and rs.text and r:IsVisible() then texts[rs.text] = true end
        end
    end)
    for _, label in ipairs({ "Spell panel size", "Ranged timer", "Main hand timer", "Off hand timer", "Rebuild the layout" }) do
        check(texts[label], "no row " .. label)
    end
    for _, gone in ipairs({ "Main bar", "Map size", "Player and target frames", "Spell button size", "Swing timers" }) do
        check(not texts[gone], "a removed row is drawn: " .. gone)
    end
    check(buttons["Start over"], "no Start over button")
    check(buttons["Always"], "no Always button")
    c:click(buttons["Always"])
    c:advance(0.2)
    eq(checkSaves(c), 2)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Bars put back after the game's Compact setting changed (review of tasks 3 and 4, I1)
---------------------------------------------------------------------------

local function setCompact(c, on) c.barParts[c.env.GamepadMainActionBarFrame].useCompactLayout = on end

test("layout: a Compact layout picked while on gets the bars stacked on the bottom anchor, as the game has them", function()
    local c, PE = layoutClient({}, 3)
    local before = allStates(c)
    switchOn(c, PE)
    -- The player picks a layout with Compact on: the game stacks the three anchors, then the event.
    c.world.layouts.activeLayout = 1
    setCompact(c, true)
    local f, pu = barFrames(c)
    pu:RefreshCompactLayout()
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    for _, key in ipairs({ "top", "left", "right" }) do
        local st = frameState(c, f[key])
        eq(st.points, {
            { "TOPLEFT", f.bottom, "TOPLEFT", 0, 0 },
            { "BOTTOMRIGHT", f.bottom, "BOTTOMRIGHT", 0, 0 },
        }, key .. " points")
        eq(st.scale, 1, key .. " scale")
    end
    eq(frameState(c, f.bottom), before.bottom)
    eq(frameState(c, f.both), before.both)
    c:assertClean()
end)

test("layout: with Compact off the bars go back to the game's own points even if they were stacked when first read", function()
    local c, PE = layoutClient({}, 3)
    local before = allStates(c)
    local f, pu = barFrames(c)
    -- The session starts on a Compact layout: the anchors are stacked when the addon first reads them.
    setCompact(c, true)
    pu:RefreshCompactLayout()
    switchOn(c, PE)
    check(barCalls(c, "SetPoint") >= 5, "the bars were not placed")
    -- Later the Gamepad preset (Compact off) is picked.
    setCompact(c, false)
    c.world.layouts.activeLayout = 3
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(allStates(c), before)
    c:assertClean()
end)

test("layout: without the game's points for an anchor its first-read points are put back", function()
    local c, PE = layoutClient({}, 3)
    local before = allStates(c)
    local f, pu = barFrames(c)
    c.barParts[pu].anchorPoints[f.left] = {}
    c.barParts[pu].anchorPoints[f.top] = nil
    switchOn(c, PE)
    switchOff(c, PE)
    eq(allStates(c), before)
    -- And with the whole table missing.
    c.barParts[pu].anchorPoints = nil
    switchOn(c, PE)
    switchOff(c, PE)
    eq(allStates(c), before)
    c:assertClean()
end)

test("layout: an option changed in a fight and then switched off is written at the next switch-on", function()
    local c, PE = onClient()
    local function vis()
        for _, s in ipairs(entryOf(ours(c), SYS.SwingTimer, SWING.Ranged).settings) do
            if s.setting == VISIBILITY then return s.value end
        end
    end
    c:enterCombat()
    choose(c, PE, "ranged", 0)
    switchOff(c, PE)
    c:leaveCombat()
    c:advance(0.1)
    eq(vis(), 1, "written while off")
    switchOn(c, PE)
    eq(vis(), 0)
    checkSaves(c)
    c:assertClean()
end)

test("layout: when the rewrite cannot be saved the option goes back", function()
    local c, PE = onClient()
    c.world.layoutCallFails.SaveLayouts = true
    choose(c, PE, "ranged", 2)
    check(#PE.errors >= 1, "no error logged")
    eq(opts(PE).ranged, 1)
    placedAt(c, barFrames(c).left, PE.LayoutPlan.BarSpots().left, "left")
    eq(reloadReason(PE), nil)
end)

test("layout: an option refused in Edit Mode says so in the status line only, and not once switched off", function()
    local c, PE = onClient()
    local lines = #c.chat
    c.world.editMode = true
    choose(c, PE, "ranged", 2)
    eq(statusText(PE), "Close Edit Mode first.")
    eq(#c.chat, lines, "a chat line for a refused tap")
    c.world.editMode = false
    switchOff(c, PE)
    eq(statusText(PE), OFF_TEXT)
    c:assertClean()
end)

test("layout: switched on, then a login where the Gamepad UI reads off: still on, and off brings back the remembered layout", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    local db = rawget(c.env, "PocketEssentialsDB")
    local db3, layouts3, char3 = deepCopy(db), deepCopy(c.world.layouts), deepCopy(charDB(c)) -- the third login starts from the same state
    local c2, PE2 = T.new({ gamepadUI = false, saved = db, savedChar = charDB(c), setup = function(c2) c2.world.layouts = c.world.layouts end })
    eq(PE2:GetModuleState("ctrlLayout"), "on")
    check(PE2:IsModuleEnabled("ctrlLayout"), "not running after the login")
    eq(layoutCalls(c2), 0)
    switchOff(c2, PE2)
    eq(c2.world.layouts.activeLayout, 3)
    eq(prev(PE2), nil)
    c2:assertClean()
    -- The same login without the gamepad bar's anchors: nothing placed, nothing fails.
    local c3, PE3 = T.new({ gamepadUI = false, saved = db3, savedChar = char3, setup = function(c3)
        c3.world.layouts = layouts3
        c3.barParts[c3.env.GamepadMainActionBarFrame].PageUnit = nil
    end })
    eq(PE3:GetModuleState("ctrlLayout"), "on")
    switchOff(c3, PE3)
    eq(c3.world.layouts.activeLayout, 3)
    c3:assertClean()
end)

test("layout: Gamepad UI off and no switch-on done yet: blocked with the spec's reason", function()
    local c, PE = layoutClient({}, 3, { gamepadUI = false })
    eq(prev(PE), nil)
    local state, detail = PE:GetModuleState("ctrlLayout")
    eq(state, "blocked")
    eq(detail, "Needs the game's Gamepad UI (Options, Controller, Enable Gamepad UI).")
    c:assertClean()
end)


---------------------------------------------------------------------------
-- Each character's own layout to go back to (spec 2026-11-23-controller-layout-0.11.1.md, 2;
-- 0.11.2: kept in the game's per-character saved file, PocketEssentialsCharDB.ctrlLayoutPrev)
---------------------------------------------------------------------------

-- A login of one character: the saved file `file` (shared by every character of the
-- account), the account's saved layouts `list` and this character's active layout.
-- extra.char: this character's own saved table (nil: its first login); extra.name: the
-- name UnitName("player") gives (false: nil); extra.setup as T.new.
local function login(file, list, active, extra)
    extra = extra or {}
    return T.new({ gamepadUI = extra.gamepadUI ~= false, saved = file, savedChar = extra.char, setup = function(c)
        if extra.name == false then c.world.playerName = nil elseif extra.name then c.world.playerName = extra.name end
        c.world.layouts = { layouts = deepCopy(list), activeLayout = active }
        if extra.setup then extra.setup(c) end
    end })
end

local function db(c) return rawget(c.env, "PocketEssentialsDB") end

-- A client's character entry, read from that character's own saved table.
local function entryOf(c)
    local t = charDB(c)
    return type(t) == "table" and t.ctrlLayoutPrev or nil
end

-- The index of a saved layout by name in a client's list, counting the three presets.
local function indexOf(c, name)
    for i, l in ipairs(c.world.layouts.layouts) do
        if l.layoutName == name then return 3 + i end
    end
    return nil
end

-- The events the addon's frames listen to, as a set.
local function addonEvents(c)
    local set = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile then for e in pairs(rec.events) do set[e] = true end end
    end
    return set
end

local GAMEPAD_ENTRY = { name = "Gamepad", preset = 2 }
local MINE = { name = "Mine", layoutType = 2 }

-- Character "Tester" switched on from the Gamepad preset: our layout saved at index 4.
local function testerOn()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    eq(prev(PE), GAMEPAD_ENTRY)
    return c, PE
end

-- Tester switched on, then "Bee" logs in for the first time on its own character layout
-- "Mine" (index 5) and is switched over to ours by the login check.
local function testerAndBee()
    local a, PEa = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local b, PEb = login(db(a), list, 5, { name = "Bee" })
    eq(b.world.layouts.activeLayout, 4)
    eq(prev(PEb), MINE)
    return a, PEa, b, PEb
end

test("switch: On, no entry, own layout active: remembers it, makes ours active, asks reload", function()
    local a = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local c, PE = login(db(a), list, 5, { name = "Bee" })
    check(PE:IsModuleEnabled("ctrlLayout"), "not on after the login")
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 0, "our layout exists: nothing saved")
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(#set, 1)
    eq(set[1].args[1], 4)
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE), MINE)
    eq(entryOf(a), GAMEPAD_ENTRY, "Tester's own entry changed")
    eq(rawget(c.env, "PocketEssentialsCharDB").ctrlLayoutPrev, MINE, "not in the per-character saved table")
    eq(reloadReason(PE), RELOAD)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("switch: On, no entry, no layout of ours yet: saves it and makes it active", function()
    local file = { enabled = { ctrlLayout = true } }
    local c, PE = login(file, { saved("Mine", 2) }, 4, { char = {} })
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(indexOf(c, NAME), 4)
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE), MINE)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
end)

test("switch: On, ours active: nothing changes", function()
    local a = testerOn()
    local c, PE = login(db(a), a.world.layouts.layouts, 4, { name = "Bee" })
    eq(layoutCalls(c), 0, "a layout call at login")
    eq(reloadReason(PE), nil)
    eq(statusText(PE), USING)
    placedAt(c, barFrames(c).left, PE.LayoutPlan.BarSpots(PE.LayoutPlan.DEFAULTS).left, "left at login")
    -- Off on Bee goes back to the Gamepad preset (nothing else was known for Bee).
    switchOff(c, PE)
    eq(c.world.layouts.activeLayout, 3)
    eq(prev(PE), nil)
    eq(entryOf(a), GAMEPAD_ENTRY, "Tester's own entry changed")
    c:assertClean()
end)

test("switch: On, entry present, another layout active: left alone, status says another", function()
    local a = testerOn()
    local c, PE = login(db(a), a.world.layouts.layouts, 1, { char = charDB(a) })
    eq(layoutCalls(c), 0)
    eq(reloadReason(PE), nil)
    eq(statusText(PE), ANOTHER)
    eq(prev(PE), GAMEPAD_ENTRY)
    c:assertClean()
end)

test("switch: Off puts back this character's own and removes its entry", function()
    local a, _, b = testerAndBee()
    local c, PE = login(db(b), b.world.layouts.layouts, 4, { char = charDB(b) })
    eq(layoutCalls(c), 0, "a layout call at login")
    switchOff(c, PE)
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(#set, 1)
    eq(set[1].args[1], 5)
    eq(prev(PE), nil)
    eq(entryOf(a), GAMEPAD_ENTRY, "Tester's entry changed")
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
end)

test("switch: off on A, B puts back once", function()
    local a, PEa, b = testerAndBee()
    switchOff(a, PEa)
    eq(a.world.layouts.activeLayout, 3)
    eq(prev(PEa), nil)
    -- Bee logs in with the switch off and ours still active on Bee: Bee's own comes back.
    local c, PE = login(db(a), b.world.layouts.layouts, 4, { char = charDB(b) })
    check(not PE:IsModuleEnabled("ctrlLayout"), "on after the login")
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(#set, 1)
    eq(set[1].args[1], 5)
    eq(c.world.layouts.activeLayout, 5)
    eq(prev(PE), nil)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
    -- The next login on Bee: nothing more.
    local c2, PE2 = login(db(c), c.world.layouts.layouts, 5, { char = charDB(c) })
    eq(layoutCalls(c2), 0)
    eq(reloadReason(PE2), nil)
    c2:assertClean()
end)

test("switch: login off with an entry but another layout active only forgets the entry", function()
    local a, PEa, b = testerAndBee()
    switchOff(a, PEa)
    -- Bee picked its own layout in Edit Mode meanwhile.
    local c, PE = login(db(a), b.world.layouts.layouts, 5, { char = charDB(b) })
    eq(layoutCalls(c), 0)
    eq(prev(PE), nil)
    eq(reloadReason(PE), nil)
    c:assertClean()
end)

test("switch: missing saved layout falls back to Gamepad", function()
    -- Bee deletes "Mine" in Edit Mode, then switches off.
    local _, _, b = testerAndBee()
    local c, PE = login(db(b), { b.world.layouts.layouts[1] }, 4, { char = charDB(b) })
    eq(indexOf(c, NAME), 4)
    switchOff(c, PE)
    eq(c.world.layouts.activeLayout, 3)
    eq(prev(PE), nil)
    c:assertClean()
    -- The same with the switch turned off on Tester: Bee's login puts back the Gamepad preset.
    local a2, PEa2, b2 = testerAndBee()
    switchOff(a2, PEa2)
    local c2, PE2 = login(db(a2), { b2.world.layouts.layouts[1] }, 4, { char = charDB(b2) })
    eq(c2.world.layouts.activeLayout, 3)
    eq(prev(PE2), nil)
    c2:assertClean()
end)

test("switch: works when the character's name cannot be read, and the debug log says why", function()
    local cases = {
        { why = "name secret", setup = function(c) c.world.playerName = "Bee"; c.world.secrets.Bee = true end },
        { why = "name empty", setup = function(c) c.world.playerName = nil end },
        { why = "unknown name", setup = function(c) c.world.playerName = "Unknown" end },
        { why = "realm empty", setup = function(c) c.world.realm = "" end },
    }
    for _, case in ipairs(cases) do
        local a = testerOn()
        local list = a.world.layouts.layouts
        list[#list + 1] = saved("Mine", 2)
        local file = db(a)
        file.debug = { on = true }
        local c, PE = login(file, list, 5, { setup = case.setup })
        eq(c.world.layouts.activeLayout, 4, case.why .. ": not switched")
        eq(prev(PE), MINE, case.why)
        local found = 0
        for _, line in ipairs(db(c).debug.lines) do
            if tostring(line):find("the character's name does not read: " .. case.why, 1, true) then found = found + 1 end
        end
        eq(found, 1, case.why .. ": debug lines")
        -- Switched off on this character later, still without the name: its own comes back.
        local c2, PE2 = login(db(c), c.world.layouts.layouts, 4, { char = charDB(c), setup = case.setup })
        switchOff(c2, PE2)
        eq(c2.world.layouts.activeLayout, 5, case.why .. ": not put back")
        eq(prev(PE2), nil)
        eq(reloadReason(PE2), RELOAD)
        c2:assertClean()
    end
end)

test("switch: waits until the game has given Edit Mode its layouts", function()
    local a = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local c, PE = login(db(a), list, 5, { setup = function(c) c.world.editModeReady = false end })
    eq(layoutCalls(c), 0, "a layout call before Edit Mode had its layouts")
    c.world.editModeReady = true
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE), MINE)
    c:assertClean()
end)

test("switch: login in a fight waits", function()
    local a = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local c, PE = login(db(a), list, 5, { setup = function(c) c.world.inCombat = true end })
    eq(layoutCalls(c), 0, "a layout call in a fight")
    c:fire("PLAYER_ENTERING_WORLD", false, false)
    eq(layoutCalls(c), 0, "a layout call in a fight")
    c:leaveCombat()
    c:advance(0.1)
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 1)
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE), MINE)
    c:assertClean()
    -- Off in a fight the same way.
    local file = db(c)
    file.enabled.ctrlLayout = false
    local c2, PE2 = login(file, c.world.layouts.layouts, 4, { char = charDB(c), setup = function(c2) c2.world.inCombat = true end })
    eq(layoutCalls(c2), 0, "a layout call in a fight")
    c2:leaveCombat()
    eq(c2.world.layouts.activeLayout, 5)
    eq(prev(PE2), nil)
    c2:assertClean()
end)

test("migrate: old prev moved or dropped once", function()
    -- A 0.11.0 saved file: one layout to go back to for the whole account.
    local function oldFile(on)
        -- (template 4: only the migration is tested here; the rebuild of an older layout has its own tests)
        return { enabled = { ctrlLayout = on }, options = { ctrlLayout = { template = 4, prev = { name = "Mine", layoutType = 2 } } } }
    end
    local ours = saved(NAME)
    -- Ours active on the character logging in: it becomes this character's entry.
    local c, PE = login(oldFile(true), { ours, saved("Mine", 2) }, 4)
    eq(layoutCalls(c), 0)
    eq(prev(PE), MINE)
    eq(opts(PE).prev, false)
    c:assertClean()
    -- Read once: a second character with ours not active gets its own layout remembered, not the old one.
    local c2, PE2 = login(db(c), { ours, saved("Mine", 2), saved("Bees", 2) }, 6)
    eq(c2.world.layouts.activeLayout, 4)
    eq(prev(PE2), { name = "Bees", layoutType = 2 })
    eq(entryOf(c), MINE)
    c2:assertClean()
    -- Ours not active: dropped; this character then switches as one with nothing remembered.
    local c3, PE3 = login(oldFile(true), { ours, saved("Mine", 2) }, 1)
    eq(opts(PE3).prev, false)
    eq(c3.world.layouts.activeLayout, 4)
    eq(prev(PE3), { name = "Modern", preset = 0 })
    c3:assertClean()
    -- Off (a switch-off that had not finished): moved over, then put back.
    local c4, PE4 = login(oldFile(false), { ours, saved("Mine", 2) }, 4)
    eq(opts(PE4).prev, false)
    eq(c4.world.layouts.activeLayout, 5)
    eq(prev(PE4), nil)
    eq(reloadReason(PE4), RELOAD)
    c4:assertClean()
end)

test("migrate: a 0.11.1 entry by name moves into this character's own file once", function()
    local function namedFile(on)
        return { enabled = { ctrlLayout = on }, options = { ctrlLayout = { template = 4, prevs = {
            [KEY] = { name = "Mine", layoutType = 2 }, ["Bee-Camelot"] = { preset = 0 } } } } }
    end
    local ours = saved(NAME)
    -- On, ours active: moved over, nothing changes in the game.
    local c, PE = login(namedFile(true), { ours, saved("Mine", 2) }, 4)
    eq(layoutCalls(c), 0)
    eq(prev(PE), MINE)
    eq(opts(PE).prevs[KEY], nil, "left in the account-wide file")
    eq(opts(PE).prevs["Bee-Camelot"], { preset = 0 }, "another character's entry changed")
    eq(statusText(PE), USING)
    c:assertClean()
    -- Off, ours active: moved over and put back.
    local c2, PE2 = login(namedFile(false), { ours, saved("Mine", 2) }, 4)
    eq(c2.world.layouts.activeLayout, 5)
    eq(prev(PE2), nil)
    eq(opts(PE2).prevs[KEY], nil)
    c2:assertClean()
    -- The name unreadable: not found, and the switch-on works without it.
    local c3, PE3 = login(namedFile(true), { ours, saved("Mine", 2) }, 5, { name = false })
    eq(c3.world.layouts.activeLayout, 4)
    eq(prev(PE3), MINE)
    eq(opts(PE3).prevs[KEY], MINE, "read without the name")
    c3:assertClean()
end)

test("switch: off state registers no events after the login check", function()
    local base = addonEvents((layoutClient({}, 3)))
    check(not base.PLAYER_ENTERING_WORLD and not base.EDIT_MODE_LAYOUTS_UPDATED, "a fresh install listens for layout events")
    -- Nothing remembered for this character: nothing to check at all.
    local c0 = login({ enabled = { ctrlLayout = false } }, {}, 3)
    eq(addonEvents(c0), base)
    -- An entry for this character, checked at login, then nothing more.
    local a, PEa, b = testerAndBee()
    switchOff(a, PEa)
    local c = login(db(a), b.world.layouts.layouts, 4, { char = charDB(b) })
    eq(c.world.layouts.activeLayout, 5, "the login check did not run")
    eq(addonEvents(c), base)
    c:assertClean()
    -- Waiting for Edit Mode's layouts: listening until they come, then not.
    local a2, PEa2, b2 = testerAndBee()
    switchOff(a2, PEa2)
    local c2 = login(db(a2), b2.world.layouts.layouts, 4, { char = charDB(b2), setup = function(c2) c2.world.editModeReady = false end })
    check(addonEvents(c2).EDIT_MODE_LAYOUTS_UPDATED, "not waiting for Edit Mode's layouts")
    c2.world.editModeReady = true
    c2:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(c2.world.layouts.activeLayout, 5)
    eq(addonEvents(c2), base)
    c2:assertClean()
end)

---------------------------------------------------------------------------
-- Review of 0.11.1: automatic switch-on failures, a Gamepad UI reported late
---------------------------------------------------------------------------

test("switch: failed automatic switch-on keeps the switch on and other characters untouched", function()
    local a = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    -- Bee's login: the game refuses to activate our layout.
    local c, PE = login(db(a), list, 5, { setup = function(c) c.world.layoutCallFails.SetActiveLayout = true end })
    c:advance(0.1)
    check(PE:IsModuleEnabled("ctrlLayout"), "the feature switched itself off")
    eq(PE:IsModuleSavedOn("ctrlLayout"), true)
    eq(prev(PE), nil, "an entry was written for a switch that did not happen")
    eq(entryOf(a), GAMEPAD_ENTRY, "Tester's entry changed")
    check(#PE.errors >= 1, "no error logged")
    check(statusText(PE):find("It tries again at the next login.", 1, true), "status: " .. tostring(statusText(PE)))
    eq(reloadReason(PE), nil)
    PE:ClearErrors() -- the saved error log would follow into the next logins
    -- Tester's next login: still on, ours still active there, nothing put back.
    local c2, PE2 = login(db(c), c.world.layouts.layouts, 4, { char = charDB(a) })
    check(PE2:IsModuleEnabled("ctrlLayout"), "off on Tester")
    eq(layoutCalls(c2), 0)
    eq(c2.world.layouts.activeLayout, 4)
    c2:assertClean()
    -- Bee's next login, with the game taking the call: switched.
    local c3, PE3 = login(db(c), c.world.layouts.layouts, 5, { char = charDB(c) })
    eq(c3.world.layouts.activeLayout, 4)
    eq(prev(PE3), MINE)
    c3:assertClean()
    -- A refusal (five account-wide layouts, ours not saved yet) keeps the switch on too.
    local file = { enabled = { ctrlLayout = true } }
    local c4, PE4 = login(file, { saved("A1"), saved("A2"), saved("A3"), saved("A4"), saved("A5"), saved("Mine", 2) }, 9)
    c4:advance(0.1)
    check(PE4:IsModuleEnabled("ctrlLayout"), "the feature switched itself off after the refusal")
    eq(layoutCalls(c4), 0)
    eq(prev(PE4), nil)
    check(statusText(PE4):find("You already have 5 account-wide layouts.", 1, true), "status: " .. tostring(statusText(PE4)))
    c4:assertClean()
    -- A tap that fails still switches back off, as before.
    local c5, PE5 = layoutClient({}, 3, { setup = function(c5) c5.world.layoutCallFails.SaveLayouts = true end })
    switchOn(c5, PE5)
    check(not PE5:IsModuleEnabled("ctrlLayout"), "a failed tap stayed on")
end)

test("switch: Gamepad UI reported late at login still switches on", function()
    local a = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local file = deepCopy(db(a))
    local c, PE = login(db(a), list, 5, { gamepadUI = false, setup = function(c)
        -- The game reports its Gamepad UI once the character enters the world: just before the
        -- addon hears that PLAYER_ENTERING_WORLD (this frame registered for it first).
        local f = c.env.CreateFrame("Frame")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function() c.world.gamepadUI = true end)
    end })
    check(PE:IsModuleEnabled("ctrlLayout"), "not started once the Gamepad UI read on")
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE), MINE)
    eq(reloadReason(PE), RELOAD)
    eq(addonEvents(c).EDIT_MODE_LAYOUTS_UPDATED, true, "the feature's own events")
    c:assertClean()
    -- Still off at that PLAYER_ENTERING_WORLD: not started, and only that one look.
    local c2, PE2 = login(file, list, 5, { gamepadUI = false })
    check(not PE2:IsModuleEnabled("ctrlLayout"), "started without the Gamepad UI")
    eq(layoutCalls(c2), 0)
    check(not addonEvents(c2).PLAYER_ENTERING_WORLD, "still listening after the one look")
    c2.world.gamepadUI = true
    c2:fire("PLAYER_ENTERING_WORLD", false, false)
    check(not PE2:IsModuleEnabled("ctrlLayout"), "a second look")
    c2:assertClean()
end)

test("switch: a tap off always asks for the reload, a login off only when it changed the layout", function()
    -- Another layout active: nothing to put back, but a tap still asks.
    local c, PE = testerOn()
    c.world.layouts.activeLayout = 1
    PE:GetModule("ctrlLayout"):CancelReload()
    switchOff(c, PE)
    eq(prev(PE), nil)
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 0)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
end)

test("switch: a login that changes the layout says so in chat, a tap does not", function()
    local function said(c, text)
        for _, line in ipairs(c.chat) do if line:find(text, 1, true) then return true end end
        return false
    end
    local a = testerOn()
    check(not said(a, "now uses the controller layout"), "a tap said it in chat")
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local c = login(db(a), list, 5)
    check(said(c, "now uses the controller layout"), "no chat line after the login switch-on")
    local a2, PEa2, b2 = testerAndBee()
    switchOff(a2, PEa2)
    local c2 = login(db(a2), b2.world.layouts.layouts, 4, { char = charDB(b2) })
    check(said(c2, "own screen layout is back"), "no chat line after the login switch-off")
    local c3 = login(db(c2), c2.world.layouts.layouts, 5, { char = charDB(c2) })
    check(not said(c3, "Reload now"), "a login that changed nothing said it")
end)


---------------------------------------------------------------------------
-- Pieces placed with the bars (0.12.0): the LB / RB targeting pictures and the target of target
---------------------------------------------------------------------------

-- The two pictures (PageUnit.LeftShoulderBackground / RightShoulderBackground) and the target of
-- target (TargetFrame.totFrame) in the stand-in.
local function extras(c)
    local pu = c.barParts[c.env.GamepadMainActionBarFrame].PageUnit
    local parts = c.barParts[pu]
    local target = rawget(c.env, "TargetFrame")
    return parts.LeftShoulderBackground, parts.RightShoulderBackground, target and rawget(target, "totFrame")
end

local function pointsOf(c, region)
    local out = {}
    for i, p in ipairs(c._state(region).points) do out[i] = { p.point, p.rel, p.relPoint, p.x, p.y } end
    return out
end

local function extraStates(c)
    local l, r, t = extras(c)
    return { pointsOf(c, l), pointsOf(c, r), pointsOf(c, t) }
end

local function totCalls(c)
    local n = 0
    for _, call in ipairs(c.calls) do if call.name:match("^TargetFrame%.totFrame:") then n = n + 1 end end
    return n
end

test("bars: the targeting pictures go beside the map", function()
    local c = onClient()
    local l, r = extras(c)
    eq(pointsOf(c, l), { { "BOTTOMRIGHT", c.env.UIParent, "BOTTOM", -76, 128 } })
    eq(pointsOf(c, r), { { "BOTTOMLEFT", c.env.UIParent, "BOTTOM", 76, 128 } })
    c:assertClean()
end)

test("bars: the target of target sits above the target frame", function()
    local c = onClient()
    local _, _, tot = extras(c)
    eq(pointsOf(c, tot), { { "BOTTOMLEFT", c.env.TargetFrame, "TOPLEFT", 0, 25 } })
    c:assertClean()
end)

test("bars: off puts the targeting pictures and the target of target back", function()
    local c, PE = layoutClient({}, 3)
    local before = extraStates(c)
    switchOn(c, PE)
    switchOff(c, PE)
    eq(extraStates(c), before)
    -- Another layout picked while on: put back the same way.
    local c2, PE2 = layoutClient({}, 3)
    local before2 = extraStates(c2)
    switchOn(c2, PE2)
    c2.world.layouts.activeLayout = 1
    c2:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(extraStates(c2), before2)
    c:assertClean()
    c2:assertClean()
end)

test("bars: a missing, nil or failing targeting picture or target of target places the rest", function()
    local cases = {
        { what = "no LB picture", setup = function(c)
            c.barParts[c.barParts[c.env.GamepadMainActionBarFrame].PageUnit].LeftShoulderBackground = nil end,
          placed = { false, true, true } },
        { what = "an LB picture that is not a frame", setup = function(c)
            c.barParts[c.barParts[c.env.GamepadMainActionBarFrame].PageUnit].LeftShoulderBackground = 7 end,
          placed = { false, true, true } },
        { what = "no target of target", setup = function(c) rawset(c.env.TargetFrame, "totFrame", nil) end,
          placed = { true, true, false } },
        { what = "no target frame", setup = function(c) rawset(c.env, "TargetFrame", nil) end,
          placed = { true, true, false } },
        { what = "an RB picture whose SetPoint raises", setup = function(c)
            local _, r = extras(c)
            rawset(r, "SetPoint", function() error("refused") end) end,
          placed = { true, false, true }, logged = true },
        { what = "a target of target whose points cannot be read", setup = function(c)
            local _, _, t = extras(c)
            rawset(t, "GetNumPoints", function() error("refused") end) end,
          placed = { true, true, false } },
    }
    for _, case in ipairs(cases) do
        local c, PE = layoutClient({}, 3, { setup = case.setup })
        local l, r, t = extras(c)
        local want = {
            { "BOTTOMRIGHT", c.env.UIParent, "BOTTOM", -76, 128 },
            { "BOTTOMLEFT", c.env.UIParent, "BOTTOM", 76, 128 },
            { "BOTTOMLEFT", rawget(c.env, "TargetFrame"), "TOPLEFT", 0, 25 },
        }
        switchOn(c, PE)
        check(PE:IsModuleEnabled("ctrlLayout"), case.what .. ": switched off")
        placedAt(c, barFrames(c).left, PE.LayoutPlan.BarSpots().left, case.what .. ": left bar")
        for i, region in ipairs({ l, r, t }) do
            if case.placed[i] then
                eq(pointsOf(c, region), { want[i] }, case.what .. ": piece " .. i)
            end
        end
        if case.logged then
            check(#PE.errors == 1, case.what .. ": " .. #PE.errors .. " errors logged")
        else
            eq(#PE.errors, 0, case.what .. ": errors logged")
            eq(#c.errors, 0, case.what .. ": Lua errors")
        end
        switchOff(c, PE)
    end
end)

test("bars: the targeting pictures and the target of target are never moved in a fight", function()
    local c, PE = layoutClient({}, 3)
    local before = extraStates(c)
    c:enterCombat()
    switchOn(c, PE)
    eq(extraStates(c), before)
    eq(totCalls(c), 0, "the target of target touched in a fight")
    c:leaveCombat()
    c:advance(0.1)
    local _, _, tot = extras(c)
    eq(pointsOf(c, tot), { { "BOTTOMLEFT", c.env.TargetFrame, "TOPLEFT", 0, 25 } })
    -- The game re-anchors the bars in a fight: nothing moves until it ends.
    local calls = totCalls(c)
    c:enterCombat()
    local _, pu = barFrames(c)
    pu:RefreshCompactLayout()
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(totCalls(c) - calls, 0, "the target of target touched in a fight")
    c:leaveCombat()
    c:assertClean()
end)


---------------------------------------------------------------------------
-- Getting the new arrangement without taps (0.12.0 spec): the template version
---------------------------------------------------------------------------

-- An entry of a saved layout by system number and index (the per-character block above
-- names another helper entryOf).
local function systemEntry(layout, system, index)
    for _, e in ipairs(layout.systems) do
        if e.system == system and (index == nil or e.systemIndex == index) then return e end
    end
    return nil
end

local UPDATED = "The controller layout was updated to the new arrangement (changes you made to it in Edit Mode are replaced). Open the settings and tap Reload now to finish."

local function saidIn(c, text)
    local n = 0
    for _, line in ipairs(c.chat) do if line:find(text, 1, true) then n = n + 1 end end
    return n
end

-- Tester on our layout as 0.11.x left it: no template number saved, our layout's map where
-- 0.11.x put it, the player's own character layout "Mine" saved beside it.
local function oldTester()
    local a = testerOn()
    local file = db(a)
    file.options.ctrlLayout.template = nil
    local list = deepCopy(a.world.layouts.layouts)
    systemEntry(list[1], SYS.Minimap).anchorInfo.offsetY = 44
    list[#list + 1] = saved("Mine", 2)
    return file, list, charDB(a)
end

test("template: an older layout is rebuilt once at login, asks the reload and says so", function()
    local file, list, char = oldTester()
    local mine = deepCopy(list[2])
    local c, PE = login(file, list, 4, { char = char })
    eq(checkSaves(c), 1)
    eq(c.world.layouts.activeLayout, 4, "ours is not the active one any more")
    local map = systemEntry(ours(c), SYS.Minimap)
    eq(map.anchorInfo.offsetY, 38, "not rebuilt from the template")
    eq(c.world.layouts.layouts[2], mine, "the player's own layout changed")
    eq(opts(PE).template, PE.LayoutPlan.TEMPLATE)
    eq(reloadReason(PE), RELOAD)
    eq(saidIn(c, UPDATED), 1)
    c:assertClean()
end)

test("template: the next login does nothing", function()
    local file, list, char = oldTester()
    local c = login(file, list, 4, { char = char })
    local c2, PE2 = login(db(c), c.world.layouts.layouts, 4, { char = charDB(c) })
    eq(layoutCalls(c2), 0)
    eq(reloadReason(PE2), nil)
    eq(saidIn(c2, UPDATED), 0)
    eq(statusText(PE2), USING)
    c2:assertClean()
end)

test("template: in a fight it waits and the status line says so", function()
    local file, list, char = oldTester()
    local c, PE = login(file, list, 4, { char = char, setup = function(c) c.world.inCombat = true end })
    eq(layoutCalls(c), 0, "a layout call in a fight")
    eq(statusText(PE), "Updating the layout after this fight.")
    c:leaveCombat()
    c:advance(0.1)
    eq(checkSaves(c), 1)
    eq(systemEntry(ours(c), SYS.Minimap).anchorInfo.offsetY, 38)
    eq(saidIn(c, UPDATED), 1)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("template: waiting for the game's layouts says so", function()
    local file, list, char = oldTester()
    local c, PE = login(file, list, 4, { char = char, setup = function(c) c.world.editModeReady = false end })
    eq(layoutCalls(c), 0)
    eq(statusText(PE), "Waiting for the game's layouts.")
    c.world.editModeReady = true
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(checkSaves(c), 1)
    eq(statusText(PE), USING)
    c:assertClean()
    -- With the switch off the wait shows too, under the usual line.
    local a, PEa, b = testerAndBee()
    switchOff(a, PEa)
    local c2, PE2 = login(db(a), b.world.layouts.layouts, 4, { char = charDB(b), setup = function(c2) c2.world.editModeReady = false end })
    eq(PE2:GetModule("ctrlLayout"):status(), { "Waiting for the game's layouts.", OFF_TEXT })
    c2:assertClean()
end)

test("template: a layout of the player's own is never touched", function()
    -- Another layout picked in Edit Mode: our older layout waits, nothing is saved.
    local file, list, char = oldTester()
    local c, PE = login(file, list, 5, { char = char })
    eq(layoutCalls(c), 0)
    eq(opts(PE).template, nil)
    eq(saidIn(c, UPDATED), 0)
    eq(statusText(PE), ANOTHER)
    c:assertClean()
    -- A tap that finds our older layout active already keeps it as it is (the next login
    -- brings the new one).
    local c2, PE2 = layoutClient({ saved(NAME) }, 4)
    switchOn(c2, PE2)
    eq(#c2:callsTo("C_EditMode.SaveLayouts"), 0)
    eq(saidIn(c2, UPDATED), 0)
    c2:assertClean()
end)

test("template: a tap that makes an older layout of ours active rebuilds it first; one reload is enough", function()
    -- Switched on and off again on 0.11.x: our layout is saved, with no version, and the
    -- player is back on the Modern preset.
    local file, list, char = oldTester()
    char.ctrlLayoutPrev = nil
    file.enabled.ctrlLayout = false
    local c, PE = login(file, list, 1, { char = char })
    eq(layoutCalls(c), 0, "a layout call while off")
    switchOn(c, PE)
    eq(checkSaves(c), 1, "rebuilt before it was made active")
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 1)
    eq(c.world.layouts.activeLayout, 4)
    eq(systemEntry(ours(c), SYS.Minimap).anchorInfo.offsetY, 38, "not rebuilt from the template")
    eq(opts(PE).template, PE.LayoutPlan.TEMPLATE)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
    -- The reload: nothing more to do, no second reload asked for.
    local c2, PE2 = login(db(c), c.world.layouts.layouts, 4, { char = charDB(c) })
    eq(layoutCalls(c2), 0)
    eq(reloadReason(PE2), nil)
    eq(saidIn(c2, UPDATED), 0)
    eq(statusText(PE2), USING)
    c2:assertClean()
end)

test("template: a new layout saves the version", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    eq(opts(PE).template, PE.LayoutPlan.TEMPLATE)
    eq(PE.LayoutPlan.TEMPLATE, 4)
    -- Start over saves it too.
    opts(PE).template = nil
    PE:GetModule("ctrlLayout"):CancelReload()
    tapStartOver(c, PE)
    c:advance(1)
    tapStartOver(c, PE)
    eq(opts(PE).template, 4)
    c:assertClean()
end)

test("template: the rebuild failing logs it and tries again next login", function()
    local file, list, char = oldTester()
    local c, PE = login(file, list, 4, { char = char, setup = function(c) c.world.layoutCallFails.SaveLayouts = true end })
    check(#PE.errors >= 1, "no error logged")
    eq(opts(PE).template, nil)
    eq(reloadReason(PE), nil)
    eq(saidIn(c, UPDATED), 0)
    check(PE:IsModuleEnabled("ctrlLayout"), "the feature switched itself off")
    PE:ClearErrors()
    -- The Gamepad preset missing (a difficult game): logged, nothing saved.
    local file2, list2, char2 = oldTester()
    local c2, PE2 = login(file2, list2, 4, { char = char2, setup = function(c2)
        rawset(c2.env, "EditModePresetLayoutManager", { GetCopyOfPresetLayouts = function() error("no presets") end })
    end })
    eq(#c2:callsTo("C_EditMode.SaveLayouts"), 0)
    eq(opts(PE2).template, nil)
    PE2:ClearErrors()
    -- The next login, the game taking it: rebuilt.
    local c3, PE3 = login(db(c), c.world.layouts.layouts, 4, { char = charDB(c) })
    eq(checkSaves(c3), 1)
    eq(opts(PE3).template, 4)
    eq(saidIn(c3, UPDATED), 1)
    c3:assertClean()
end)


test("layout: on writes the target's auras on top; a game without that setting still switches on", function()
    -- The stand-in's Gamepad preset has the target as system 3, index 2; BuffsOnTop is setting 2
    -- (EditModeManagerConstantsDocumentation.lua:792).
    local function targetEntry(c)
        for _, l in ipairs(c.world.layouts.layouts) do
            if l.layoutName == NAME then
                for _, entry in ipairs(l.systems) do
                    if entry.system == 3 and entry.systemIndex == 2 then return entry end
                end
            end
        end
    end
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    local entry = targetEntry(c)
    eq(entry.settings, { { setting = 2, value = 1 } })
    eq(entry.anchorInfo.offsetY, 56)
    c:assertClean()
    local cases = {
        { what = "no BuffsOnTop", setup = function(c2) rawset(c2.env.Enum.EditModeUnitFrameSetting, "BuffsOnTop", nil) end },
        { what = "no setting group", setup = function(c2) rawset(c2.env.Enum, "EditModeUnitFrameSetting", nil) end },
        { what = "a group that raises", setup = function(c2)
            rawset(c2.env.Enum, "EditModeUnitFrameSetting", setmetatable({}, { __index = function() error("no such value") end })) end },
    }
    for _, case in ipairs(cases) do
        local c2, PE2 = layoutClient({}, 3, { setup = case.setup })
        switchOn(c2, PE2)
        check(PE2:IsModuleEnabled("ctrlLayout"), case.what .. ": not on")
        local e2 = targetEntry(c2)
        eq(#e2.settings, 0, case.what .. ": a setting was written")
        eq(e2.anchorInfo.offsetY, 56, case.what)
        eq(#PE2.errors, 0, case.what .. ": errors logged")
    end
end)

---------------------------------------------------------------------------
-- 0.13.0: the game's controller hint box (spec "Where everything goes", "Game's hint box")
---------------------------------------------------------------------------

local HINTS = "GamepadShowPersistentInputLegend"

-- A layout client whose game has the hint box setting at `value` ("1" unless given).
local function hintsClient(value, list, active, setup)
    return layoutClient(list or {}, active or 3, { setup = function(c)
        c.world.cvars[HINTS] = value or "1"
        if setup then setup(c) end
    end })
end

local function hintWrites(c) return #c:callsTo("C_CVar.SetCVar") end

test("hints: on hides the game's hint box and keeps the player's value; off puts it back", function()
    local c, PE = hintsClient("1")
    switchOn(c, PE)
    eq(c.world.cvars[HINTS], "0")
    eq(opts(PE).hintsWas, "1")
    switchOff(c, PE)
    eq(c.world.cvars[HINTS], "1")
    eq(opts(PE).hintsWas, nil)
    c:assertClean()
    -- A player who had it off gets it off again.
    local c2, PE2 = hintsClient("0")
    switchOn(c2, PE2)
    eq(opts(PE2).hintsWas, "0")
    switchOff(c2, PE2)
    eq(c2.world.cvars[HINTS], "0")
    c2:assertClean()
end)

test("hints: turned back on by the player while on, it is left alone, also at the next login", function()
    local c, PE = hintsClient("1")
    switchOn(c, PE)
    c.world.cvars[HINTS] = "1" -- the player ticks the game's own option again
    local writes = hintWrites(c)
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    c:fire("PLAYER_ENTERING_WORLD")
    eq(c.world.cvars[HINTS], "1")
    eq(hintWrites(c), writes)
    local c2, PE2 = login(db(c), c.world.layouts.layouts, 4, { char = charDB(c), setup = function(c2) c2.world.cvars[HINTS] = "1" end })
    eq(c2.world.cvars[HINTS], "1")
    eq(hintWrites(c2), 0)
    eq(opts(PE2).hintsWas, "1")
    -- Off puts back the value from before the layout.
    switchOff(c2, PE2)
    eq(c2.world.cvars[HINTS], "1")
    eq(opts(PE2).hintsWas, nil)
    c2:assertClean()
end)

test("hints: another layout picked brings the box back; ours picked again hides it", function()
    local c, PE = hintsClient("1")
    switchOn(c, PE)
    c.world.layouts.activeLayout = 1
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(c.world.cvars[HINTS], "1")
    eq(opts(PE).hintsWas, nil)
    c.world.layouts.activeLayout = 4
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(c.world.cvars[HINTS], "0")
    c:assertClean()
end)

test("hints: nothing is written in a fight; it waits for the fight to end", function()
    local c, PE = hintsClient("1")
    c:enterCombat()
    switchOn(c, PE)
    eq(hintWrites(c), 0)
    c:leaveCombat()
    c:advance(0.1)
    eq(c.world.cvars[HINTS], "0")
    c:enterCombat()
    switchOff(c, PE)
    eq(c.world.cvars[HINTS], "0", "written in a fight")
    c:leaveCombat()
    c:advance(0.1)
    eq(c.world.cvars[HINTS], "1")
    c:assertClean()
end)

test("hints: a game whose setting is missing, cannot be read or refuses the change: nothing changes, nothing fails", function()
    -- Missing: no write at all.
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    eq(hintWrites(c), 0)
    eq(opts(PE).hintsWas, nil)
    switchOff(c, PE)
    eq(hintWrites(c), 0)
    c:assertClean()
    local cases = {
        { what = "reading raises", api = { GetCVar = function() error("no") end, SetCVar = function() return true end } },
        { what = "writing raises", api = { GetCVar = function() return "1" end, SetCVar = function() error("no") end } },
        { what = "writing refused", api = { GetCVar = function() return "1" end, SetCVar = function() return false end } },
        { what = "no functions", api = {} },
    }
    for _, case in ipairs(cases) do
        local c2, PE2 = layoutClient({}, 3, { setup = function(c2) rawset(c2.env, "C_CVar", case.api) end })
        switchOn(c2, PE2)
        check(PE2:IsModuleEnabled("ctrlLayout"), case.what .. ": not on")
        eq(opts(PE2).hintsWas, nil, case.what)
        switchOff(c2, PE2)
        eq(#PE2.errors, 0, case.what .. ": errors logged")
        eq(#c2.errors, 0, case.what .. ": Lua errors")
    end
    -- A value saved that cannot be written back is kept for the next try.
    local c3, PE3 = hintsClient("1")
    switchOn(c3, PE3)
    rawset(c3.env, "C_CVar", { GetCVar = function() return "0" end, SetCVar = function() return false end })
    switchOff(c3, PE3)
    eq(opts(PE3).hintsWas, "1")
    c3:assertClean()
end)

---------------------------------------------------------------------------
-- 0.13.0: our spell pictures (PE.FaceBars, FaceBars.lua) started and stopped here
-- (plan "The contract between the two halves"). A stand-in records each call and
-- whether the real bars were placed at that moment.
---------------------------------------------------------------------------

local USING_LINE = "Using the Pocket Essentials layout. Move the map, chat or frames in Edit Mode if you like."

local function faceStub(c, PE)
    local s = { calls = {}, reason = nil }
    local function placedNow() return frameState(c, barFrames(c).left).scale == 0.6 end
    function s:Start()
        s.calls[#s.calls + 1] = { "Start", placed = placedNow(), combat = c.world.inCombat }
        if s.startFails then error("face start failed") end
        if s.refuse then return false, s.refuse end
        return true
    end
    function s:Stop()
        s.calls[#s.calls + 1] = { "Stop", placed = placedNow(), combat = c.world.inCombat }
        if s.stopFails then error("face stop failed") end
    end
    function s:Status()
        if s.statusFails then error("face status failed") end
        return s.reason
    end
    PE.FaceBars = s
    return s
end

local function count(stub, name)
    local n = 0
    for _, call in ipairs(stub.calls) do if call[1] == name then n = n + 1 end end
    return n
end

test("face: started after the bars are placed, out of a fight only", function()
    local c, PE = layoutClient({}, 3)
    local face = faceStub(c, PE)
    switchOn(c, PE)
    check(count(face, "Start") >= 1, "not started")
    for _, call in ipairs(face.calls) do
        if call[1] == "Start" then
            check(call.placed, "started before the bars were placed")
            check(not call.combat, "started in a fight")
        end
    end
    eq(face.calls[#face.calls][1], "Start")
    c:assertClean()
    -- Switched on in a fight: nothing until it ends.
    local c2, PE2 = layoutClient({}, 3)
    local face2 = faceStub(c2, PE2)
    c2:enterCombat()
    switchOn(c2, PE2)
    eq(count(face2, "Start"), 0)
    c2:leaveCombat()
    c2:advance(0.1)
    check(count(face2, "Start") >= 1, "not started after the fight")
    check(face2.calls[#face2.calls].placed, "started before the bars were placed")
    c2:assertClean()
end)

test("face: stopped at once when switched off, also in a fight, and before the bars go back", function()
    local c, PE = layoutClient({}, 3)
    local face = faceStub(c, PE)
    switchOn(c, PE)
    face.calls = {}
    switchOff(c, PE)
    check(count(face, "Stop") >= 1, "not stopped")
    eq(face.calls[1][1], "Stop")
    check(face.calls[1].placed, "stopped only after the bars went back")
    eq(count(face, "Start"), 0)
    eq(frameState(c, barFrames(c).left).scale, 1, "bars not put back")
    c:assertClean()
    -- In a fight: stopped at once; the bars go back once it ends.
    local c2, PE2 = layoutClient({}, 3)
    local face2 = faceStub(c2, PE2)
    switchOn(c2, PE2)
    face2.calls = {}
    c2:enterCombat()
    PE2:SetModuleEnabled("ctrlLayout", false)
    eq(count(face2, "Stop"), 1)
    check(face2.calls[1].combat and face2.calls[1].placed, "not stopped in the fight")
    c2:leaveCombat()
    c2:advance(0.1)
    eq(frameState(c2, barFrames(c2).left).scale, 1, "bars not put back after the fight")
    c2:assertClean()
end)

test("face: another layout picked stops it before the bars go back; ours again starts it", function()
    local c, PE = layoutClient({}, 3)
    local face = faceStub(c, PE)
    switchOn(c, PE)
    face.calls = {}
    c.world.layouts.activeLayout = 1
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(face.calls[1][1], "Stop")
    check(face.calls[1].placed, "stopped after the bars went back")
    eq(count(face, "Start"), 0)
    face.calls = {}
    c.world.layouts.activeLayout = 4
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(count(face, "Start"), 1)
    check(face.calls[#face.calls].placed, "started before the bars were placed")
    c:assertClean()
end)

test("face: not started when the bars cannot be placed", function()
    local c, PE = layoutClient({}, 3, { setup = function(c)
        c.barParts[c.env.GamepadMainActionBarFrame].PageUnit = nil
    end })
    local face = faceStub(c, PE)
    switchOn(c, PE)
    eq(count(face, "Start"), 0)
    c:assertClean()
end)

test("face: the status line says when and why the game's own spell bars are showing", function()
    local c, PE = layoutClient({}, 3)
    local face = faceStub(c, PE)
    switchOn(c, PE)
    PE:GetModule("ctrlLayout"):CancelReload()
    eq(statusText(PE), USING_LINE)
    face.reason = "the game's bars were not found"
    eq(PE:GetModule("ctrlLayout"):status(), { USING_LINE, "Pocket Essentials' spell pictures are off: the game's bars were not found." })
    face.reason = "they hit an error"
    eq(PE:GetModule("ctrlLayout"):status(), { USING_LINE, "Pocket Essentials' spell pictures are off: they hit an error." })
    -- A status that raises or is not text: the usual line only.
    face.statusFails = true
    eq(statusText(PE), USING_LINE)
    face.statusFails, face.reason = false, 7
    eq(statusText(PE), USING_LINE)
    -- Another layout active: only that line.
    face.reason = "the game's bars were not found"
    c.world.layouts.activeLayout = 1
    eq(statusText(PE), ANOTHER)
    c:assertClean()
end)

test("face: a start or stop that fails or refuses is logged, and the layout carries on", function()
    local c, PE = layoutClient({}, 3)
    local face = faceStub(c, PE)
    face.refuse = "the game's bars were not found"
    switchOn(c, PE)
    check(count(face, "Start") >= 1, "not started")
    eq(frameState(c, barFrames(c).left).scale, 0.6, "bars not placed")
    c:assertClean()
    local c2, PE2 = layoutClient({}, 3)
    local face2 = faceStub(c2, PE2)
    face2.startFails, face2.stopFails = true, true
    switchOn(c2, PE2)
    check(#PE2.errors >= 1, "the failed start was not logged")
    check(PE2:IsModuleEnabled("ctrlLayout"), "the feature switched off")
    eq(frameState(c2, barFrames(c2).left).scale, 0.6, "bars not placed")
    switchOff(c2, PE2)
    eq(frameState(c2, barFrames(c2).left).scale, 1, "bars not put back after a failed stop")
    eq(#c2.errors, 0)
    -- A FaceBars without the functions (an older one): nothing happens, nothing fails.
    local c3, PE3 = layoutClient({}, 3)
    PE3.FaceBars = { Start = true, Stop = "no", Status = 1 }
    switchOn(c3, PE3)
    eq(statusText(PE3), USING_LINE)
    switchOff(c3, PE3)
    c3:assertClean()
end)

-- 0.15.0 (polish spec E4): with our pictures off, the game's four bars show at full size.
local function checkFull(c, PE, what)
    local full, f = PE.LayoutPlan.FullBarSpots(), barFrames(c)
    for _, spot in ipairs({ "top", "left", "right", "both", "bottom" }) do
        placedAt(c, f[spot], full[spot], what .. ": " .. spot)
        eq(frameState(c, f[spot]).scale, 1, what .. ": " .. spot .. " scale")
    end
end

test("face: the real bars at full size, two a side, clear of everything but the hidden diamonds", function()
    local Plan = plan()
    local full = Plan.FullBarSpots()
    eq(full.top, { x = -220, y = 121, s = 1 })
    eq(full.left, { x = -220, y = 45, s = 1 })
    eq(full.right, { x = 220, y = 121, s = 1 })
    eq(full.both, { x = 220, y = 45, s = 1 })
    eq(full.bottom, Plan.BarSpots().bottom)
    local rects = Plan.Rects()
    for spot, b in pairs(full) do
        if spot ~= "bottom" then
            local r = { b.x - 104, b.y - 34, b.x + 104, b.y + 34 }
            check(r[2] >= 0, spot .. " below the screen")
            for name, o in pairs(rects) do
                if not name:find("diamond") then
                    check(r[3] <= o[1] or o[3] <= r[1] or r[4] <= o[2] or o[4] <= r[2], spot .. " bar overlaps " .. name)
                end
            end
            for other, o in pairs(full) do
                if other ~= spot and other ~= "bottom" then
                    check(math.abs(o.x - b.x) >= 208 or math.abs(o.y - b.y) >= 68, spot .. " overlaps " .. other)
                end
            end
        end
    end
end)

test("face: pictures that cannot be made leave the game's bars at full size", function()
    local c, PE = layoutClient({}, 3, { setup = function(c) c.world.noCooldownFrames = true end })
    switchOn(c, PE)
    check(PE.FaceBars:Status() ~= nil, "the pictures were made")
    checkFull(c, PE, "not made")
    c:assertClean()
end)

test("face: the safety net turning the pictures off in a fight puts the bars at full size once it ends", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    PE:GetModule("ctrlLayout"):CancelReload()
    near(frameState(c, barFrames(c).left).scale, 0.6, "placed under the pictures")
    c:enterCombat()
    rawset(PE.FaceBars.view[1].pics[1].icon, "SetVertexColor", function() error("broken picture") end)
    local real = c.barButtons.TopCenteredAnchor[1]
    for _ = 1, 3 do
        real.icon:SetVertexColor(0.5, 0.5, 0.5)
        c:advance(0.1)
    end
    eq(PE.FaceBars:Status(), "they hit an error")
    near(frameState(c, barFrames(c).left).scale, 0.6, "a bar moved in the fight")
    c:leaveCombat()
    c:advance(0.1)
    checkFull(c, PE, "after the fight")
    -- Later syncs keep them at full size; off puts them back as the game had them.
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    checkFull(c, PE, "after a sync")
    PE:ClearErrors()
    switchOff(c, PE)
    eq(frameState(c, barFrames(c).left).scale, 1)
    eq(#c.errors, 0)
end)

---------------------------------------------------------------------------
-- 0.15.0: Spell panel size (spec 2026-11-24-controller-layout-0.15.0-panel-size.md, with
-- the corrections in 2026-11-24-0.15.0-polish.md E6)
---------------------------------------------------------------------------

local SIZES = { 80, 90, 100, 110, 120 }
-- size: inner centre, outer centre, outer edge, frames' bottom
local SIZE_NUMBERS = {
    [80] = { 156.6, 275.8, 329.4, 56 },
    [90] = { 163.3, 295.9, 356.2, 56 },
    [100] = { 170, 316, 383, 56 },
    [110] = { 176.7, 336.1, 409.8, 128 },
    [120] = { 183.4, 356.2, 436.6, 133 },
}

local function overlapArea(a, b)
    local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
    local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
    return w > 1e-9 and h > 1e-9, w, h
end

test("size: the plan's numbers at every Spell panel size", function()
    local Plan = plan()
    for _, size in ipairs(SIZES) do
        local s, n, what = size / 100, SIZE_NUMBERS[size], size .. "%"
        local face = Plan.Face(size)
        near(face.button, 42 * s, what .. " picture")
        near(face.dx, 46 * s, what .. " dx")
        near(face.dy, 28 * s, what .. " dy")
        local spots = Plan.FaceSpots(size)
        for _, side in ipairs({ { "left", -1 }, { "right", 1 } }) do
            near(spots.inner[side[1]].x, side[2] * n[1], what .. " inner " .. side[1])
            near(spots.outer[side[1]].x, side[2] * n[2], what .. " outer " .. side[1])
            eq(spots.inner[side[1]].y, 66)
            eq(spots.outer[side[1]].y, 66)
        end
        local r = Plan.Rects(size)
        near(r["outer right diamond"][3], n[3], what .. " outer edge")
        near(r["outer left diamond"][1], -n[3], what .. " outer edge, left")
        near(r["inner right diamond"][1], 103, what .. " inner edge")
        near(r["inner right diamond"][4] - r["inner right diamond"][2], 98 * s, what .. " diamond height")
        local bars = Plan.BarSpots(size)
        for _, b in ipairs({ { "top", -1, 1 }, { "left", -1, -1 }, { "right", 1, 1 }, { "both", 1, -1 } }) do
            near(bars[b[1]].x, b[2] * n[1], what .. " " .. b[1] .. " x")
            near(bars[b[1]].y, 66 + b[3] * 21 * s, what .. " " .. b[1] .. " y")
            near(bars[b[1]].s, 0.6 * s, what .. " " .. b[1] .. " scale")
        end
        eq(bars.bottom, { x = 0, y = 238, s = 1 }, what .. " sub-menu buttons")
        local list = Plan.Pieces({ panelSize = size })
        local p, pet, t = piece(list, "UnitFrame", "Player").anchor, piece(list, "UnitFrame", "Pet").anchor, piece(list, "UnitFrame", "Target").anchor
        eq({ p.point, p.x, p.y }, { "BOTTOMRIGHT", -395, n[4] }, what .. " player")
        eq({ t.point, t.x, t.y }, { "BOTTOMLEFT", 395, n[4] }, what .. " target")
        eq({ pet.x, pet.y }, { -395, n[4] + 125 }, what .. " pet")
        eq(Plan.TOT_SPOT, { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", x = 0, y = 25 })
        -- The rest of the template does not depend on the size.
        local other, base = Plan.Pieces({ panelSize = size }), Plan.Pieces()
        for i, x in ipairs(other) do
            if x.system ~= "UnitFrame" then eq(x, base[i], what .. " " .. x.system) end
        end
    end
    -- 100% is exactly 0.14.0's numbers: the template version stays 4.
    eq(Plan.Pieces({ panelSize = 100 }), Plan.Pieces())
    eq(Plan.Rects(100), Plan.Rects())
    eq(Plan.TEMPLATE, 4)
end)

test("size: no piece overlaps another at every Spell panel size, and all stay on screen", function()
    local Plan = plan()
    local W, H = 1365.33, 768
    for _, size in ipairs(SIZES) do
        local r = Plan.Rects(size)
        local names = {}
        for name in pairs(r) do names[#names + 1] = name end
        table.sort(names)
        for i = 1, #names do
            local a = r[names[i]]
            check(a[1] >= -W / 2 and a[3] <= W / 2 and a[2] >= 0 and a[4] <= H, size .. "%: " .. names[i] .. " is off screen")
            for j = i + 1, #names do
                local hit, w, h = overlapArea(a, r[names[j]])
                check(not hit, size .. "%: " .. names[i] .. " overlaps " .. names[j] .. " (" .. w .. " by " .. h .. ")")
            end
        end
    end
    -- The tightest spot: at 120% the inner diamonds reach 124.8, the LB / RB pictures start at 128.
    local r = Plan.Rects(120)
    near(r["inner left diamond"][4], 124.8, "inner diamond top at 120%")
    eq(r["LB targeting picture"][2], 128)
    check(r["inner right diamond"][4] < r["RB targeting picture"][2], "the inner diamond reaches the RB picture")
    -- And the frames clear the wheels at every size.
    for _, size in ipairs(SIZES) do
        local rs = Plan.Rects(size)
        for _, wheel in ipairs(Plan.Wheels()) do
            for _, name in ipairs({ "player", "pet", "target", "target of target", "target auras" }) do
                local b = rs[name]
                local nx = math.max(b[1], math.min(wheel.x, b[3]))
                local ny = math.max(b[2], math.min(wheel.y, b[4]))
                check(math.sqrt((nx - wheel.x) ^ 2 + (ny - wheel.y) ^ 2) > wheel.r, size .. "%: " .. name .. " reaches a wheel")
            end
        end
    end
end)

test("size: the real bars stay under the inner diamonds at every Spell panel size", function()
    local Plan = plan()
    local side = { main = "inner left diamond", lt = "inner left diamond", rt = "inner right diamond", both = "inner right diamond" }
    for _, size in ipairs(SIZES) do
        local r, real = Plan.Rects(size), Plan.RealBarRects(size)
        for bar, b in pairs(real) do
            local d = r[side[bar]]
            check(b[1] >= d[1] and b[3] <= d[3] and b[2] >= d[2] and b[4] <= d[4], size .. "%: " .. bar .. " real bar is not under its diamond")
            near(b[3] - b[1], 124.8 * size / 100, size .. "%: " .. bar .. " width")
            near(b[4] - b[2], 40.8 * size / 100, size .. "%: " .. bar .. " height")
            for name, a in pairs(r) do
                if name ~= "inner left diamond" and name ~= "inner right diamond" then
                    check(not overlapArea(a, b), size .. "%: " .. bar .. " real bar overlaps " .. name)
                end
            end
        end
        for _, pair in ipairs({ { "main", "lt" }, { "rt", "both" } }) do
            check(not overlapArea(real[pair[1]], real[pair[2]]), size .. "%: " .. pair[1] .. " and " .. pair[2] .. " overlap")
        end
    end
end)

test("size: a saved size that is not one of the five reads as 100%; an old saved size is ignored", function()
    local Plan = plan()
    for _, v in ipairs({ 85, 130, 70, 0, "120", true }) do eq(Plan.PanelSize(v), 100, tostring(v)) end
    eq(Plan.PanelSize(nil), 100)
    eq(Plan.PanelSize({}), 100)
    eq(Plan.PanelSize({ panelSize = 110 }), 110)
    eq(Plan.PanelSize({ size = 80 }), 100, "0.11.x's size counts")
    eq(Plan.BarSpots({ size = 80 }), Plan.BarSpots())
    eq(Plan.Pieces({ panelSize = 85 }), Plan.Pieces())
    -- In the saved file: an unknown value becomes 100 at login, the old `size` stays unused.
    local file = { enabled = { ctrlLayout = false }, options = { ctrlLayout = { panelSize = 85, size = 70 } } }
    local c, PE = T.new({ gamepadUI = true, saved = file, setup = function(c) c.world.layouts = { layouts = {}, activeLayout = 3 } end })
    eq(opts(PE).panelSize, 100)
    eq(opts(PE).size, 70, "the old value was changed")
    switchOn(c, PE)
    placedAt(c, barFrames(c).left, Plan.BarSpots(100).left, "left")
    c:assertClean()
end)

test("size: a change rewrites the frames and asks for a reload; after it the bars and the pictures are at the new size", function()
    local c, PE = onClient()
    local f = barFrames(c)
    choose(c, PE, "panelSize", 120)
    eq(checkSaves(c), 2, "the layout was not rewritten")
    eq(systemEntry(ours(c), SYS.UnitFrame, 1).anchorInfo.offsetY, 133, "the player frame did not rise")
    eq(systemEntry(ours(c), SYS.UnitFrame, 2).anchorInfo.offsetY, 133, "the target frame did not rise")
    eq(systemEntry(ours(c), SYS.UnitFrame, 8).anchorInfo.offsetY, 258, "the pet did not rise")
    eq(systemEntry(ours(c), SYS.SwingTimer, SWING.Ranged).anchorInfo.offsetY, 3, "a timer moved")
    eq(reloadReason(PE), RELOAD)
    -- Until the reload the bars stay with the pictures, at the size they were built at.
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    placedAt(c, f.left, PE.LayoutPlan.BarSpots(100).left, "before the reload")
    c:assertClean()
    -- The reload: bars, pictures and the frames under them at 120%.
    local c2, PE2 = login(db(c), c.world.layouts.layouts, 4, { char = charDB(c) })
    eq(layoutCalls(c2), 0)
    eq(reloadReason(PE2), nil)
    local spots = PE2.LayoutPlan.BarSpots(120)
    local f2 = barFrames(c2)
    for _, spot in ipairs({ "top", "left", "right", "both", "bottom" }) do placedAt(c2, f2[spot], spots[spot], "after the reload: " .. spot) end
    local Face = PE2.FaceBars
    eq(Face:Status(), nil)
    local h = Face.view[1].halves[1]
    near(h:GetScale(), 1.2, "the pictures' scale")
    local _, _, _, x, y = h:GetPoint(1)
    near(x * 1.2, -183.4, "inner left diamond x")
    near(y * 1.2, 66, "inner left diamond y")
    near(Face.view[1].pics[1].frame:GetWidth() * h:GetScale(), 50.4, "a picture on screen")
    eq(statusText(PE2), USING)
    c2:assertClean()
end)

test("size: a change in a fight waits for it to end, and the card says so", function()
    local c, PE = onClient()
    c:enterCombat()
    choose(c, PE, "panelSize", 80)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1, "a save in combat")
    eq(statusText(PE), "Updating the layout after this fight.")
    c:leaveCombat()
    c:advance(0.1)
    eq(checkSaves(c), 2)
    eq(reloadReason(PE), RELOAD)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("size: refused while Edit Mode is open, and put back", function()
    local c, PE = onClient()
    c.world.editMode = true
    choose(c, PE, "panelSize", 110)
    eq(opts(PE).panelSize, 100)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    c.world.editMode = false
    c:assertClean()
end)

return { known = KNOWN_FAILURES }
