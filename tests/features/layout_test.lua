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

local HINTS_CVAR_162 = "GamepadShowPersistentInputLegend"

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

local function overlapArea(a, b)
    local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
    local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
    return w > 1e-9 and h > 1e-9, w, h
end

-- Blizzard draws each sub-menu button with its "LB + LT" / "RB + RT" prompt under it, the
-- prompt 1 unit into the button (MainActionBarFrame.xml:94-135: the button 38 across at 188
-- up, ActionBarStyles.lua:20; the prompt 72 by 24 at 158 up). The two are one piece of the
-- game's, so that one pair is not checked against each other.
local ONE_PIECE = { ["LB+LT button|LB+LT prompt"] = true, ["RB+RT button|RB+RT prompt"] = true }

-- Every rectangle of r is on screen and no two overlap.
local function checkClear(r, what)
    local W, H = 1365.33, 768
    local names = {}
    for name in pairs(r) do names[#names + 1] = name end
    table.sort(names)
    for i = 1, #names do
        local a = r[names[i]]
        check(a[1] >= -W / 2 and a[3] <= W / 2 and a[2] >= 0 and a[4] <= H, what .. ": " .. names[i] .. " is off screen")
        for j = i + 1, #names do
            if not ONE_PIECE[names[i] .. "|" .. names[j]] then
                local hit, w, h = overlapArea(a, r[names[j]])
                check(not hit, what .. ": " .. names[i] .. " overlaps " .. names[j] .. " (" .. w .. " by " .. h .. ")")
            end
        end
    end
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
    eq(map.anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -6, y = 0 })
    eq(map.settings, { Size = 2, HeaderUnderneath = 1 })
    eq(map.moved, true)
    local chat = piece(list, "ChatFrame")
    eq(chat.anchor, { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", x = 17, y = 245 })
    eq(chat.settings, { WidthHundreds = 4, WidthTensAndOnes = 50, HeightHundreds = 1, HeightTensAndOnes = 70 })
    eq(piece(list, "AuraFrame", "BuffFrame").anchor.y, -40)
    eq(piece(list, "AuraFrame", "DebuffFrame").anchor.y, -78)
    local quest = piece(list, "ObjectiveTracker")
    eq(quest.anchor, { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -5, y = -5 })
    eq(quest.settings, { Height = 0 })
    local tip = piece(list, "HudTooltip")
    eq(tip.anchor, { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", x = -10, y = 236 })
    eq(tip.settings, nil)
    eq(tip.moved, true)
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
    eq(map.anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -6, y = 0 })
    eq(map.settings, { Size = 2, HeaderUnderneath = 1 })
    -- The round map: 30 up and 10 right of the map's bottom, its 253 frame at 70%. 0.16.0: 4 right
    -- of the centre, so the magnifier left of the strip stays clear of the inner left diamond.
    local r = Plan.Rects()
    near((r.map[1] + r.map[3]) / 2, 4, "round map 4 right of the centre")
    near((r.map[2] + r.map[4]) / 2, 0 + 30 + 253 * 0.7 / 2, "round map centre up")
    near(r.map[3] - r.map[1], 198 * 0.7, "round map width")
    -- The title strip right under it, where the swing timers were.
    eq(r["title strip"], { -6 - 1 - 76, 8, -6 - 1 + 76, 31 })
    check(r["title strip"][4] < r.map[2], "the strip reaches the round map")
end)

test("plan: swing timers stacked above the round map, Main Hand lowest", function()
    local Plan = plan()
    local list = Plan.Pieces()
    -- The round map's top is 187.85 up: Main Hand 6 over it (rounded up), 2 between the timers.
    eq(piece(list, "SwingTimer", "MainHand").anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 4, y = 194 })
    eq(piece(list, "SwingTimer", "OffHand").anchor.y, 208)
    eq(piece(list, "SwingTimer", "Ranged").anchor.y, 222)
    local r = Plan.Rects()
    near(r["MainHand timer"][3] - r["MainHand timer"][1], 170.4, "timer width")
    near(r["MainHand timer"][4] - r["MainHand timer"][2], 12, "timer height")
    near((r["MainHand timer"][1] + r["MainHand timer"][3]) / 2, (r.map[1] + r.map[3]) / 2, "centred on the round map")
    near(r["MainHand timer"][2] - r.map[4], 194 - 187.85, "6 over the round map")
    near(r["OffHand timer"][2] - r["MainHand timer"][4], 2, "2 between")
    near(r["Ranged timer"][2] - r["OffHand timer"][4], 2, "2 between")
    -- Order from the bottom: Main Hand, Off Hand, Ranged, whatever is shown.
    for _, o in ipairs({ { offHand = 0 }, { ranged = 2, mainHand = 2 } }) do
        local l = Plan.Pieces(o)
        eq({ piece(l, "SwingTimer", "MainHand").anchor.y, piece(l, "SwingTimer", "OffHand").anchor.y, piece(l, "SwingTimer", "Ranged").anchor.y }, { 194, 208, 222 })
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
    eq(Plan.SHOULDERS, { left = { "BOTTOMRIGHT", -178, 155 }, right = { "BOTTOMLEFT", 178, 155 } })
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
    -- Every piece the spec names is in the check.
    for _, name in ipairs({ "inner left diamond", "outer left diamond", "inner right diamond", "outer right diamond",
        "player", "pet", "target", "target of target", "target auras", "target cast bar", "map", "title strip",
        "MainHand timer", "OffHand timer", "Ranged timer", "LB+LT button", "RB+RT button", "LB targeting picture",
        "RB targeting picture", "quest tracker", "chat", "buffs and debuffs", "XP bars", "round button",
        "LB+LT prompt", "RB+RT prompt", "tooltip" }) do
        check(r[name], "no rectangle for " .. name)
    end
    check(r["hint box"] == nil, "the hint box is listed while it is off")
    checkClear(r, "defaults")
end)

test("plan: the quest tracker top right, the round button bottom left at every size, the tracker clear of the quest arrow", function()
    local Plan = plan()
    local r = Plan.Rects()
    local t = r["quest tracker"]
    local W, H = 1365.33, 768
    eq({ t[1], t[2], t[3], t[4] }, { W / 2 - 5 - 260, H - 5 - 400, W / 2 - 5, H - 5 })
    -- The round button (Hub.lua) at the layout's spot, 10 in, 6 over the player frame's top, at its
    -- three sizes (56 / 60 / 72 px, UI.lua; 768 / 720 units a pixel): clear of the frames and the chat.
    local px = 768 / 720
    for _, size in ipairs(Plan.PANEL_SIZES) do
        local rs = Plan.Rects(size)
        local point, x, y = Plan.HubSpot({ panelSize = size })
        eq({ point, x, y }, { "BOTTOMLEFT", 10, rs.player[4] + 6 }, size .. "%: the round button's spot")
        for _, hub in ipairs({ 56, 60, 72 }) do
            local s = hub * px
            local b = { -W / 2 + x, y, -W / 2 + x + s, y + s }
            for _, name in ipairs({ "player", "pet", "chat", "quest tracker", "LB targeting picture" }) do
                check(not overlapArea(b, rs[name]), size .. "%: the " .. hub .. " px round button overlaps the " .. name)
            end
        end
    end
    -- The quest arrow at its "top" spot: TOP 0, -40 px, 400 px wide (QuestArrow.lua:103, 110), up to 150%.
    local arrowHalf = 400 * px * 1.5 / 2
    check(t[1] > arrowHalf, "the tracker reaches the quest arrow")
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
    eq(map.anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = -6, offsetY = 0 })
    eq(settingValue(map, e.setting.Minimap.Size), 2)
    -- A setting missing from the entry is appended.
    local chat = layout.systems[2]
    eq(settingValue(chat, e.setting.ChatFrame.WidthHundreds), 4)
    eq(settingValue(chat, e.setting.ChatFrame.HeightTensAndOnes), 70)
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
    eq(layout.systems[1].anchorInfo.offsetY, 0)
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
    eq(map.anchorInfo.offsetY, 0)
end)

test("plan: buffs, debuffs, tracker spots", function()
    local Plan = plan()
    local list = Plan.Pieces(with(Plan.DEFAULTS))
    -- 0.16.0: the buffs 10 left of the tracker, their top 4 under the XP bars' bottom (36 down),
    -- the debuff row 38 under them.
    eq(piece(list, "AuraFrame", "BuffFrame").anchor,
        { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -275, y = -40 })
    eq(piece(list, "AuraFrame", "DebuffFrame").anchor,
        { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -275, y = -78 })
    local quest = piece(list, "ObjectiveTracker")
    eq(quest.anchor, { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -5, y = -5 })
    eq(quest.settings, { Height = 0 })
    local r = Plan.Rects()
    near(r["buffs and debuffs"][3], r["quest tracker"][1] - 10, "10 left of the tracker")
    near(r["XP bars"][2] - r["buffs and debuffs"][4], 4, "4 under the XP bars")
    -- The chat bottom left, 450 by 170, 6 over the round button (higher than the pet frame).
    local chat = piece(list, "ChatFrame")
    eq(chat.anchor, { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", x = 17, y = 245 })
    eq(chat.settings, { WidthHundreds = 4, WidthTensAndOnes = 50, HeightHundreds = 1, HeightTensAndOnes = 70 })
end)

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

test("layout: registered, off, with its defaults, a Controller tab and no work while off", function()
    local c, PE = T.new({})
    local mod = PE:GetModule("ctrlLayout")
    check(mod ~= nil, "the feature did not register")
    eq(mod.label, "Controller layout")
    eq(mod.desc, "Map bottom middle, a spell panel each side (hold LT or RT to swap), chat on the left above the PE button.")
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
    eq(ours.systems[1].anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = -6, offsetY = 0 })
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
    eq(ours.systems[1].anchorInfo.offsetY, 0)
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

test("layout: the PE button takes the layout's spot when the bars are placed and leaves it when they are put back", function()
    local c, PE = layoutClient({}, 3)
    local button = PE.Hub.button
    local before = { button:GetPoint(1) }
    switchOn(c, PE)
    local _, x, y = PE.LayoutPlan.HubSpot(PE.LayoutPlan.PanelSize(PE.LayoutPlan.DEFAULTS))
    local p, _, _, px, py = button:GetPoint(1)
    eq({ p, px, py }, { "BOTTOMLEFT", x, y }, "the button is not at the layout's spot")
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    local q, _, _, qx, qy = button:GetPoint(1)
    eq({ q, qx, qy }, { before[1], before[4], before[5] }, "the button did not go back")
    c:assertClean("hub spot")
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

local SYS = { Minimap = 2, UnitFrame = 3, ChatFrame = 8, HudTooltip = 11, SwingTimer = 29 }
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
    eq(labels, { "Spell panel size", "Ranged timer", "Main hand timer", "Off hand timer", "Controls reminder", "Map buttons",
        "Rebuild the layout",
        -- (0.20.0: the seven "Part: ..." rows of 0.16.2 and 0.16.4 are gone)
        -- 0.17.0: the slim bars, Off until tried on the device
        "Slim bars",
        -- 0.20.0: whole names or first names on the slim bars
        "Names on the bars",
        -- 0.19.0: the map's look, Round until the square map is tried on the device
        "Map look",
        -- 0.18.0: arrange it yourself, both Off until tried on the device, and the way in
        "Arrange it yourself", "Arrange: spell wheels", "Arrange the screen",
        -- 0.16.4: for the device test
        "Mark a test section", "Save a snapshot" })
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
    eq(list[7].button, "Start over")
    eq(type(list[7].action), "function")
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
    eq(map.anchorInfo.offsetY, 0)
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
    eq(entryOf(after, SYS.Minimap).anchorInfo.offsetX, -6)
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
        return { enabled = { ctrlLayout = on }, options = { ctrlLayout = { template = 5, prev = { name = "Mine", layoutType = 2 } } } }
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
        return { enabled = { ctrlLayout = on }, options = { ctrlLayout = { template = 5, prevs = {
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

test("bars: the targeting pictures go beside the LB + LT / RB + RT prompts", function()
    local c = onClient()
    local l, r = extras(c)
    eq(pointsOf(c, l), { { "BOTTOMRIGHT", c.env.UIParent, "BOTTOM", -178, 155 } })
    eq(pointsOf(c, r), { { "BOTTOMLEFT", c.env.UIParent, "BOTTOM", 178, 155 } })
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
            { "BOTTOMRIGHT", c.env.UIParent, "BOTTOM", -178, 155 },
            { "BOTTOMLEFT", c.env.UIParent, "BOTTOM", 178, 155 },
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
    eq(map.anchorInfo.offsetY, 0, "not rebuilt from the template")
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
    eq(systemEntry(ours(c), SYS.Minimap).anchorInfo.offsetY, 0)
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
    eq(systemEntry(ours(c), SYS.Minimap).anchorInfo.offsetY, 0, "not rebuilt from the template")
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
    eq(PE.LayoutPlan.TEMPLATE, 5)
    -- Start over saves it too.
    opts(PE).template = nil
    PE:GetModule("ctrlLayout"):CancelReload()
    tapStartOver(c, PE)
    c:advance(1)
    tapStartOver(c, PE)
    eq(opts(PE).template, 5)
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
    eq(opts(PE3).template, 5)
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
                -- The game's own LB + LT / RB + RT prompts (158 up, 24 high) reach 9 into the top
                -- full bars (87 to 155): where the game puts them, as in 0.15.0, and only while our
                -- pictures are off.
                if not name:find("diamond") and not name:find(" prompt$") then
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
        -- The rest of the template does not depend on the size (0.16.0: the chat and the
        -- tooltip rise with the frames).
        local other, base = Plan.Pieces({ panelSize = size }), Plan.Pieces()
        local follows = { UnitFrame = true, ChatFrame = true, HudTooltip = true }
        for i, x in ipairs(other) do
            if not follows[x.system] then eq(x, base[i], what .. " " .. x.system) end
        end
    end
    -- 100% is the default; a number is still taken as the size.
    eq(Plan.Pieces({ panelSize = 100 }), Plan.Pieces())
    eq(Plan.Rects(100), Plan.Rects())
    eq(Plan.Rects(120), Plan.Rects({ panelSize = 120 }))
    eq(Plan.TEMPLATE, 5)
end)

test("size: no piece overlaps another at every Spell panel size, and all stay on screen", function()
    local Plan = plan()
    for _, size in ipairs(SIZES) do checkClear(Plan.Rects(size), size .. "%") end
    -- The tightest spots: at 120% the inner diamonds reach 124.8 and 7.2, the LB / RB pictures start
    -- at 155; the magnifier left of the place name ends at the inner left diamond's edge (103).
    local r = Plan.Rects({ panelSize = 120, mapButtons = 1 })
    near(r["inner left diamond"][4], 124.8, "inner diamond top at 120%")
    eq(r["LB targeting picture"][2], 155)
    check(r["inner right diamond"][4] < r["RB targeting picture"][2], "the inner diamond reaches the RB picture")
    near(r["title strip"][1], -103, "the strip's left edge with the map buttons")
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
    eq(systemEntry(ours(c), SYS.SwingTimer, SWING.Ranged).anchorInfo.offsetY, 222, "a timer moved")
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

-- 0.15.0 review: a size that leaves the frames at the same height (80% to 100%) must not throw away
-- where the player put them in Edit Mode; only 110% and 120% move them.
test("size: a change that leaves the frames' height alone keeps the frames where the player put them", function()
    local c, PE = onClient()
    systemEntry(ours(c), SYS.UnitFrame, 2).anchorInfo.offsetX = 222   -- moved in Edit Mode
    choose(c, PE, "panelSize", 90)
    eq(systemEntry(ours(c), SYS.UnitFrame, 2).anchorInfo.offsetX, 222, "the target frame was put back")
    eq(systemEntry(ours(c), SYS.UnitFrame, 1).anchorInfo.offsetY, 56, "the player frame moved")
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
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

---------------------------------------------------------------------------
-- 0.16.0: the playing screen (spec 2026-11-24-playing-screen-layout-design.md, "0.16.0: the
-- arrangement" and "Known pinches")
---------------------------------------------------------------------------

test("0.16.0: the template is 5 and the two new options default to 0", function()
    local Plan = plan()
    eq(Plan.TEMPLATE, 5)
    eq(Plan.DEFAULTS.hints, 0)
    eq(Plan.DEFAULTS.mapButtons, 0)
end)

-- 0.20.0 (spec 2026-11-25-0.20.0-after-first-sitting.md, 3): the seven "Part: ..." rows are
-- gone (0.16.2's testing rows for the refused controller actions, and 0.16.4's untried hook
-- on the triggers). Every part is always placed; values an older version saved are ignored
-- and cleared at load.
local PART_KEYS = { "tHints", "tChat", "tMap", "tBars", "tExtras", "tFace", "tHook" }

test("0.20.0 parts: no option row is a Part row, and the plan has no part switches", function()
    local Plan = plan()
    local c, PE = layoutClient({}, 3)
    for _, o in ipairs(PE:GetModule("ctrlLayout").options) do
        check(not tostring(o.label):find("^Part:"), "a Part row is still there: " .. tostring(o.label))
    end
    eq(Plan.TEST_PARTS, nil)
    for _, key in ipairs(PART_KEYS) do
        eq(Plan.DEFAULTS[key], nil, key .. " default")
        eq(optRow(PE, key), nil, key .. " row")
        eq(opts(PE)[key], nil, key .. " at first install")
    end
    -- A value passed to the plan changes nothing.
    eq(Plan.Pieces({ tHook = 1, tBars = 0, tFace = 0 }), Plan.Pieces({}))
end)

-- A login with a file 0.16.2 to 0.19.0 saved: every part Off and the hook On.
local function partsOffClient(more)
    local registered = { n = 0 }
    local file = { options = { ctrlLayout = { tHints = 0, tChat = 0, tMap = 0, tBars = 0, tExtras = 0, tFace = 0, tHook = 1 } } }
    for k, v in pairs(more or {}) do file.options.ctrlLayout[k] = v end
    local c, PE = layoutClient({}, 3, { saved = file, setup = function(cl)
        cl.world.cvars[HINTS_CVAR_162] = "1"
        local pageUnit = cl.env.GamepadMainActionBarFrame.PageUnit
        local real = rawget(pageUnit, "RegisterActiveActionBarUpdatedCallback")
        rawset(pageUnit, "RegisterActiveActionBarUpdatedCallback", function(...)
            registered.n = registered.n + 1
            return real(...)
        end)
    end })
    return c, PE, registered
end

test("0.20.0 parts: saved Off values and a saved hook are cleared at load, also while the layout is off", function()
    local c, PE = partsOffClient()
    for _, key in ipairs(PART_KEYS) do eq(opts(PE)[key], nil, key) end
    eq(PE:IsModuleSavedOn("ctrlLayout"), false)
    c:assertClean()
end)

test("0.20.0 parts: with saved Off values every part is placed, and the triggers are followed with the game's callback, never the hook", function()
    local c, PE, registered = partsOffClient()
    PE:SetDebug(true)
    switchOn(c, PE)
    -- The chat's box, the map's ring, the hint box, the bars, the targeting pictures, the spell pictures.
    eq(c.env.ChatFrame1Background:IsShown(), false, "the chat's box was not hidden")
    eq(c.env.MinimapCompassTexture:IsShown(), false, "the map's ring was not hidden")
    local hintWritten = false
    for _, call in ipairs(c:callsTo("C_CVar.SetCVar")) do
        if call.args[1] == HINTS_CVAR_162 then hintWritten = true end
    end
    check(hintWritten, "the hint box setting was not written")
    check(barCalls(c, "SetScale") > 0, "the bars were not placed")
    local f = barFrames(c)
    eq(c._state(f.top).scale, 0.6, "the bars are not under the spell panels")
    local left = c.env.GamepadMainActionBarFrame.PageUnit.LeftShoulderBackground
    eq({ select(4, left:GetPoint(1)) }, { -178, 155 }, "the LB targeting picture was not placed")
    eq(PE.FaceBars:Status(), nil)
    check(type(PE.FaceBars.view) == "table" and PE.FaceBars.view[1] ~= nil, "the spell pictures were not made")
    -- The triggers: the device-proven callback, once; no hook on SetActiveActionBar.
    eq(registered.n, 1)
    for _, call in ipairs(c:callsTo("hooksecurefunc")) do
        check(not (call.args[1] == c.env.GamepadMainActionBarFrame.PageUnit and call.args[2] == "SetActiveActionBar"),
            "SetActiveActionBar was hooked")
    end
    local lines = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        lines[#lines + 1] = line:match("^%S+ ctrlLayout: (.*)$")
    end
    local placedLines = 0
    for _, l in ipairs(lines) do
        if l:find("^bars placed") then
            placedLines = placedLines + 1
            eq(l, "bars placed")
        end
        check(not l:find("parts left out", 1, true), "a part is logged as left out: " .. l)
    end
    check(placedLines > 0, "no 'bars placed' line")
    check(table.concat(lines, "\n"):find("spell pictures: on (triggers followed with the game's callback)", 1, true),
        "the start line does not name the callback")
    for _, key in ipairs(PART_KEYS) do eq(opts(PE)[key], nil, key) end
    eq(#PE.errors, 0)
    c:assertClean()
end)

test("0.16.0: the chat is bottom left, the tracker top right, the tooltip is a piece", function()
    local Plan = plan()
    local list = Plan.Pieces({})
    eq(piece(list, "ChatFrame").anchor.point, "BOTTOMLEFT")
    eq(piece(list, "ObjectiveTracker").anchor.point, "TOPRIGHT")
    local tip = piece(list, "HudTooltip")
    check(tip, "no HudTooltip piece")
    eq(tip.anchor.point, "BOTTOMRIGHT")
    -- At every size: the chat's bottom 6 over the higher of the pet frame and the round button
    -- (rounded up); the tooltip's bottom 6 over the target of target, 10 in from the right edge
    -- while the tracker is not in the way (up to 100%), else lined up with the buffs' right edge.
    for _, size in ipairs(Plan.PANEL_SIZES) do
        local o = { panelSize = size }
        local l, r = Plan.Pieces(o), Plan.Rects(o)
        local chat, t = piece(l, "ChatFrame").anchor, piece(l, "HudTooltip").anchor
        eq({ chat.x, chat.y }, { 17, math.ceil(math.max(r.pet[4], r["round button"][4]) + 6) }, size .. "%: chat")
        eq(t.y, r["target of target"][4] + 6, size .. "%: tooltip up")
        eq(t.x, size <= 100 and -10 or -275, size .. "%: tooltip across")
        eq(r.chat[2], chat.y, size .. "%: the chat's rectangle")
        eq(r.tooltip[2], t.y, size .. "%: the tooltip's rectangle")
    end
    -- Nothing else in the list depends on the two new options.
    eq(Plan.Pieces({ hints = 1, mapButtons = 1 }), Plan.Pieces({}))
end)

test("0.16.0: the timers are above the round map", function()
    local Plan = plan()
    local r = Plan.Rects({})
    for _, name in ipairs({ "MainHand", "OffHand", "Ranged" }) do
        check(r[name .. " timer"][2] >= r.map[4], name .. " timer is not above the round map")
    end
end)

test("0.16.0: no piece overlaps another in any state", function()
    local Plan = plan()
    local W, H = 1365.33, 768
    local px = 768 / 720
    for _, size in ipairs(Plan.PANEL_SIZES) do
        for _, hints in ipairs({ 0, 1 }) do
            for _, mapButtons in ipairs({ 0, 1 }) do
                local o = { panelSize = size, hints = hints, mapButtons = mapButtons }
                local what = size .. "%, hints " .. hints .. ", map buttons " .. mapButtons
                local r = Plan.Rects(o)
                for _, name in ipairs({ "LB+LT prompt", "RB+RT prompt", "tooltip", "round button", "chat", "title strip" }) do
                    check(r[name], what .. ": no rectangle for " .. name)
                end
                -- The prompts: 72 by 24, 138 either side, 158 up (MainActionBarFrame.xml:119-135).
                eq(r["LB+LT prompt"], { -174, 146, -102, 170 }, what .. ": LB+LT prompt")
                eq(r["RB+RT prompt"], { 102, 146, 174, 170 }, what .. ": RB+RT prompt")
                -- The targeting pictures on the prompts' outer sides, clear of them.
                check(r["LB targeting picture"][3] < r["LB+LT prompt"][1], what .. ": the LB picture is not left of its prompt")
                check(r["RB targeting picture"][1] > r["RB+RT prompt"][3], what .. ": the RB picture is not right of its prompt")
                -- The tooltip taken 200 by 100.
                near(r.tooltip[3] - r.tooltip[1], 200, what .. ": tooltip width")
                near(r.tooltip[4] - r.tooltip[2], 100, what .. ": tooltip height")
                -- The round button at the layout's spot, at its largest size (72 px).
                local point, x, y = Plan.HubSpot(o)
                eq(point, "BOTTOMLEFT")
                local s = 72 * px
                for i, want in ipairs({ -W / 2 + x, y, -W / 2 + x + s, y + s }) do near(r["round button"][i], want, what .. ": round button " .. i) end
                -- The hint box only while it is on: TOPLEFT 5, -5, 200 by 100.
                if hints == 1 then
                    eq(r["hint box"], { -W / 2 + 5, H - 5 - 100, -W / 2 + 5 + 200, H - 5 }, what .. ": hint box")
                else
                    eq(r["hint box"], nil, what .. ": hint box while off")
                end
                checkClear(r, what)
            end
        end
    end
end)

test("0.16.0: the strip is wider with the map buttons shown", function()
    local Plan = plan()
    eq(Plan.STRIP_W[0], 152)
    eq(Plan.STRIP_W[1], 191)
    for _, mapButtons in ipairs({ 0, 1 }) do
        local strip = Plan.Rects({ mapButtons = mapButtons })["title strip"]
        near(strip[3] - strip[1], Plan.STRIP_W[mapButtons], "map buttons " .. mapButtons)
        eq({ strip[2], strip[4] }, { 8, 31 })
    end
    -- An unknown value reads as hidden.
    eq(Plan.Rects({ mapButtons = "yes" })["title strip"], Plan.Rects({ mapButtons = 0 })["title strip"])
end)

test("0.16.0: a size change that raises the frames rewrites the chat and the tooltip", function()
    -- Every entry of ours moved by hand in Edit Mode (offsetX 222); a rewritten one loses that.
    local function moveAll(c)
        for _, e in ipairs(ours(c).systems) do if e.anchorInfo then e.anchorInfo.offsetX = 222 end end
    end
    local function rewritten(c)
        local out = {}
        for _, e in ipairs(ours(c).systems) do
            if e.anchorInfo and e.anchorInfo.offsetX ~= 222 then out[e.system] = true end
        end
        return out
    end
    local c, PE = onClient()
    check(systemEntry(ours(c), SYS.HudTooltip), "our layout has no tooltip entry")
    eq(systemEntry(ours(c), SYS.HudTooltip).anchorInfo,
        { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = -10, offsetY = 236 })
    moveAll(c)
    choose(c, PE, "panelSize", 110)
    eq(rewritten(c), { [SYS.UnitFrame] = true, [SYS.ChatFrame] = true, [SYS.HudTooltip] = true })
    eq(systemEntry(ours(c), SYS.ChatFrame).anchorInfo.offsetY, 317)
    eq(systemEntry(ours(c), SYS.HudTooltip).anchorInfo.offsetY, 308)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
    -- 80% to 100%: the frames stay at the same height, so nothing is rewritten.
    local c2, PE2 = onClient()
    choose(c2, PE2, "panelSize", 80)
    moveAll(c2)
    choose(c2, PE2, "panelSize", 100)
    eq(rewritten(c2), {})
    c2:assertClean()
end)

test("0.16.0: a layout without the tooltip system is still built", function()
    local Plan = plan()
    local e = fakeEnums()
    check(e.system.HudTooltip == nil, "the stand-in enums have the tooltip")
    local base = baseLayout(e)
    base.systems[#base.systems + 1] = { system = 11, settings = {}, isInDefaultPosition = true,
        anchorInfo = { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = -9, offsetY = 85 } }
    local ok, layout = pcall(Plan.Build, base, {}, e)
    check(ok, "Build raised: " .. tostring(layout))
    check(type(layout) == "table", "no layout")
    eq(layout.systems[1].anchorInfo.offsetY, 0, "the map was not placed")
    eq(layout.systems[4].anchorInfo.offsetY, 85, "an entry of an unknown system was changed")
end)

---------------------------------------------------------------------------
-- 0.16.0: the pieces Edit Mode does not own (spec "0.16.0: the arrangement", the two rows,
-- "Left to the builder"): the hint box row, the chat without its dark box, the map's black
-- border, the two map buttons.
---------------------------------------------------------------------------

local function choicesOf(row)
    local out = {}
    for i, ch in ipairs(row.choices or {}) do out[i] = { ch.value, ch.label } end
    return out
end

-- Our black disc behind the round map: a frame of ControllerLayout.lua's with the circle picture.
local function mapDisc(c)
    for _, f in ipairs(c._allFrames()) do
        local st = c._state(f)
        if st.addonFile == "ControllerLayout.lua" then
            for _, r in ipairs(st.regions) do
                local tex = c._state(r).texture
                if type(tex) == "string" and tex:find("Icons\\circle", 1, true) then return f, r end
            end
        end
    end
    return nil
end

local function mapButtons(c)
    return { c.env.MinimapCluster.Tracking, c.env.GameTimeFrame, c.env.AddonCompartmentFrame }
end

local function allShown(list, want, what)
    for i, f in ipairs(list) do eq(f:IsShown(), want, what .. ": button " .. i) end
end

test("0.16.0: the two rows exist, Off and Hidden by default", function()
    local _, PE = layoutClient({}, 3)
    local h, m = optRow(PE, "hints"), optRow(PE, "mapButtons")
    check(h ~= nil and m ~= nil, "a row is missing")
    eq(h.label, "Controls reminder")
    eq(choicesOf(h), { { 0, "Off" }, { 1, "On" } })
    eq(m.label, "Map buttons")
    eq(choicesOf(m), { { 0, "Hidden" }, { 1, "Shown" } })
    eq(opts(PE).hints, 0)
    eq(opts(PE).mapButtons, 0)
end)

test("0.16.0: Controls reminder On writes the game setting once and Off hides it", function()
    -- On from the start: the player's "0" is kept, the box is shown, once.
    local c, PE = hintsClient("0")
    opts(PE).hints = 1
    switchOn(c, PE)
    eq(c.world.cvars[HINTS], "1")
    eq(opts(PE).hintsWas, "0")
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    c:fire("PLAYER_ENTERING_WORLD")
    eq(hintWrites(c), 1, "written more than once")
    switchOff(c, PE)
    eq(c.world.cvars[HINTS], "0")
    eq(opts(PE).hintsWas, nil)
    c:assertClean()
    -- Off (the default): hidden, the player's "1" kept; the row turns it on and off while placed.
    local c2, PE2 = hintsClient("1")
    switchOn(c2, PE2)
    eq(c2.world.cvars[HINTS], "0")
    eq(opts(PE2).hintsWas, "1")
    PE2:GetModule("ctrlLayout"):CancelReload() -- the switch-on's own reload
    choose(c2, PE2, "hints", 1)
    eq(c2.world.cvars[HINTS], "1")
    eq(opts(PE2).hintsWas, "1", "the value from before the layout")
    choose(c2, PE2, "hints", 0)
    eq(c2.world.cvars[HINTS], "0")
    eq(reloadReason(PE2), nil, "a reload was asked for")
    switchOff(c2, PE2)
    eq(c2.world.cvars[HINTS], "1")
    c2:assertClean()
end)

-- 0.16.3: the chat's box is hidden by hiding its textures, and nothing else. Until 0.16.2 the
-- addon called FCF_SetWindowAlpha, which writes frame.oldAlpha on the chat window
-- (FloatingChatFrame.lua:1062); with that call the game refused its own controller actions in
-- the addon's name from login on (device, 2026-11-24, the testing rows of 0.16.2).
test("0.16.3: the chat's box is hidden without FCF_SetWindowAlpha and no field is written on a chat window", function()
    local c, PE = layoutClient({}, 3, { setup = function(c0)
        c0.env.FCF_SetWindowAlpha(c0.chatWindows[2], 0.6, true) -- the player's own see-through on window 2
        c0.chatAlphas[2] = 0.6                                    -- as the game saved it
    end })
    local w1, w2 = c.chatWindows[1], c.chatWindows[2]
    local bg1, bg2 = c.env.ChatFrame1Background, c.env.ChatFrame2Background
    local before1, before2 = rawget(w1, "oldAlpha"), rawget(w2, "oldAlpha")
    local callsBefore = #c:callsTo("FCF_SetWindowAlpha")
    switchOn(c, PE)
    eq(bg1:IsShown(), false, "window 1's box shows")
    eq(bg2:IsShown(), false, "window 2's box shows")
    eq(c.env.ChatFrame1TopLeftTexture:IsShown(), false, "the border shows")
    -- Opening or pointing at the chat fades the box in (FloatingChatFrame.lua:1237-1246): a hidden texture is skipped.
    c.env.FCF_FadeInChatFrame(w1)
    eq(bg1:IsShown(), false, "the box shows when the chat fades in")
    eq(rawget(w1, "oldAlpha"), before1, "a field was written on window 1")
    eq(rawget(w2, "oldAlpha"), before2, "a field was written on window 2")
    switchOff(c, PE)
    eq(bg1:IsShown(), true)
    eq(bg2:IsShown(), true)
    eq(bg2:GetAlpha(), 0.6, "the player's see-through on window 2 was changed")
    eq(rawget(w1, "oldAlpha"), before1)
    eq(rawget(w2, "oldAlpha"), before2)
    eq(#c:callsTo("FCF_SetWindowAlpha"), callsBefore, "FCF_SetWindowAlpha was called by the addon")
    eq(#c:callsTo("SetChatWindowAlpha"), 0, "the player's saved value was changed")
    c:assertClean()
end)

test("0.16.3: a box texture the game had hidden stays hidden at put-back; on and off twice ends as found", function()
    local c, PE = layoutClient({}, 3)
    local bg, top = c.env.ChatFrame1Background, c.env.ChatFrame1TopLeftTexture
    top:Hide() -- hidden by the game beforehand
    local alpha = bg:GetAlpha()
    switchOn(c, PE)
    switchOff(c, PE)
    switchOn(c, PE)
    eq(bg:IsShown(), false)
    switchOff(c, PE)
    eq(bg:IsShown(), true)
    eq(bg:GetAlpha(), alpha)
    eq(top:IsShown(), false, "a texture the game had hidden was shown")
    eq(#c:callsTo("FCF_SetWindowAlpha"), 0)
    c:assertClean()
end)

test("0.16.3: a client without the chat's texture list changes nothing and raises nothing", function()
    local c, PE = layoutClient({}, 3, { setup = function(c0) rawset(c0.env, "CHAT_FRAME_TEXTURES", nil) end })
    switchOn(c, PE)
    eq(c.env.ChatFrame1Background:IsShown(), true)
    switchOff(c, PE)
    c:assertClean()
end)

test("0.16.0: the map's ring is hidden, the black border shown, and both survive the game redrawing the ring", function()
    local c, PE = layoutClient({}, 3)
    local ring = c.env.MinimapCompassTexture
    switchOn(c, PE)
    eq(ring:IsShown(), false)
    eq(c.env.MinimapCompassTextureUnderlay:IsShown(), false)
    local disc, tex = mapDisc(c)
    check(disc ~= nil, "no black disc")
    eq(disc:IsShown(), true)
    eq({ tex:GetVertexColor() }, { 0, 0, 0, 1 })
    eq(disc:GetFrameLevel(), c.minimap:GetFrameLevel() - 1)
    near(disc:GetWidth(), c.minimap:GetWidth() + 4, "disc width")
    near(disc:GetHeight(), c.minimap:GetHeight() + 4, "disc height")
    c.env.MinimapCluster:UpdateMinimapConfig()
    eq(ring:IsShown(), false, "the ring came back after the game redrew it")
    eq(disc:IsShown(), true)
    -- The map turned to rotating: the game shows its underlay; hidden too, and it comes back at the end.
    c.world.rotateMinimap = true
    c.env.MinimapCluster:UpdateMinimapConfig()
    eq(c.env.MinimapCompassTextureUnderlay:IsShown(), false)
    switchOff(c, PE)
    eq(ring:IsShown(), true)
    eq(c.env.MinimapCompassTextureUnderlay:IsShown(), true)
    eq(disc:IsShown(), false)
    -- While off the hook does nothing.
    c.world.rotateMinimap = false
    c.env.MinimapCluster:UpdateMinimapConfig()
    eq(ring:IsShown(), true)
    eq(disc:IsShown(), false)
    c:assertClean()
end)

test("0.16.0: Map buttons Hidden hides both buttons, Shown leaves them, off puts them back", function()
    local c, PE = layoutClient({}, 3)
    local list = mapButtons(c)
    switchOn(c, PE)
    allShown(list, false, "Hidden")
    PE:GetModule("ctrlLayout"):CancelReload() -- the switch-on's own reload
    -- The game shows one again (an addon registers, the tracking list changes): hidden once more.
    c.env.GameTimeFrame:Show()
    eq(c.env.GameTimeFrame:IsShown(), false, "the calendar button stayed after the game showed it")
    choose(c, PE, "mapButtons", 1)
    allShown(list, true, "Shown")
    eq(reloadReason(PE), nil, "a reload was asked for")
    choose(c, PE, "mapButtons", 0)
    allShown(list, false, "Hidden again")
    switchOff(c, PE)
    allShown(list, true, "off")
    c:assertClean()
    -- Shown from the start: none of the three is touched.
    local c2, PE2 = layoutClient({}, 3)
    opts(PE2).mapButtons = 1
    switchOn(c2, PE2)
    allShown(mapButtons(c2), true, "Shown from the start")
    for _, name in ipairs({ "MinimapCluster.Tracking:Hide", "GameTimeFrame:Hide", "AddonCompartmentFrame:Hide" }) do
        eq(#c2:callsTo(name), 0, name)
    end
    -- A button the game itself had hidden stays hidden at the end.
    local c3, PE3 = layoutClient({}, 3, { setup = function(c0) c0.env.AddonCompartmentFrame:Hide() end })
    switchOn(c3, PE3)
    switchOff(c3, PE3)
    eq(c3.env.AddonCompartmentFrame:IsShown(), false)
    eq(c3.env.GameTimeFrame:IsShown(), true)
    c3:assertClean()
end)

test("0.16.0: a client without the calendar button or the ring still places the rest", function()
    local c, PE = hintsClient("1", nil, nil, function(c0)
        rawset(c0.env, "GameTimeFrame", nil)
        rawset(c0.env, "MinimapCompassTexture", nil)
    end)
    switchOn(c, PE)
    eq(c.world.cvars[HINTS], "0", "the hint step did not run")
    eq(c.env.ChatFrame1Background:IsShown(), false, "the chat step did not run")
    eq(c.env.MinimapCluster.Tracking:IsShown(), false, "the tracking button step did not run")
    switchOff(c, PE)
    eq(c.env.ChatFrame1Background:IsShown(), true)
    eq(c.env.MinimapCluster.Tracking:IsShown(), true)
    c:assertClean()
end)

test("0.16.0: none of it runs in a fight", function()
    local c, PE = hintsClient("1")
    switchOn(c, PE)
    c:enterCombat()
    local n = #c.calls
    choose(c, PE, "hints", 1)
    choose(c, PE, "mapButtons", 1)
    local game = { ["FCF_SetWindowAlpha"] = true, ["C_CVar.SetCVar"] = true, ["MinimapCluster.Tracking:Show"] = true,
        ["GameTimeFrame:Show"] = true, ["AddonCompartmentFrame:Show"] = true, ["MinimapCompassTexture:Hide"] = true,
        ["MinimapCompassTexture:Show"] = true }
    for i = n + 1, #c.calls do check(not game[c.calls[i].name], "called in a fight: " .. c.calls[i].name) end
    eq(c.world.cvars[HINTS], "0")
    eq(c.env.GameTimeFrame:IsShown(), false)
    c:leaveCombat()
    c:advance(0.1)
    eq(c.world.cvars[HINTS], "1")
    allShown(mapButtons(c), true, "after the fight")
    -- Switched off in a fight: the box, the ring and the buttons wait for its end too.
    c:enterCombat()
    n = #c.calls
    switchOff(c, PE)
    for i = n + 1, #c.calls do check(not game[c.calls[i].name], "called in a fight: " .. c.calls[i].name) end
    eq(c.env.ChatFrame1Background:IsShown(), false, "the chat's box came back in the fight")
    c:leaveCombat()
    c:advance(0.1)
    eq(c.env.ChatFrame1Background:IsShown(), true)
    eq(c.env.MinimapCompassTexture:IsShown(), true)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- 0.16.4 (spec 2026-11-24-0.16.4-cleanup.md, 6 and 7): the section mark and the snapshot
---------------------------------------------------------------------------

local function logOf(c) return rawget(c.env, "PocketEssentialsDB").debug end

-- The text of every debug line of `key` (after "HH:MM:SS.mmm key: "), in order.
local function logTexts(c, key)
    local out = {}
    for _, line in ipairs(logOf(c).lines) do
        local text = line:match("^%S+ " .. key .. ": (.*)$")
        if text then out[#out + 1] = text end
    end
    return out
end

local function lastChat(c)
    local lines = T.chatLines(c)
    return lines[#lines]
end

-- The snapshot's line for a piece, or nil.
local function pieceLine(lines, name)
    for _, l in ipairs(lines) do
        if l:sub(1, #name + 9) == "piece: " .. name .. " |" then return l end
    end
    return nil
end

-- A number read back from a snapshot line, which carries one decimal.
local function about(a, b, msg)
    check(type(a) == "number" and math.abs(a - b) <= 0.051, (msg or "number") .. ": expected about " .. tostring(b) .. ", got " .. tostring(a))
end

-- left, bottom, width, height, scale from a piece line.
local function numbers(line)
    local l, b, w, h, sc = line:match("l=(%-?[%d%.]+) b=(%-?[%d%.]+) w=([%d%.]+) h=([%d%.]+) s=([%d%.]+)")
    return tonumber(l), tonumber(b), tonumber(w), tonumber(h), tonumber(sc)
end

test("0.16.4 mark: with the Debug log off nothing is counted and chat says to switch it on", function()
    local c, PE = T.new({})
    eq(PE:MarkSection(), nil)
    eq(lastChat(c), "Switch the Debug log on first (Settings, Debug log).")
    eq(#logOf(c).lines, 0)
    PE:SetDebug(true)
    eq(PE:MarkSection(), 1, "the tap with the log off was counted")
end)

test("0.16.4 mark: writes ==== section N ==== and says Section N marked, N counting up", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    eq(PE:MarkSection(), 1)
    eq(lastChat(c), "Section 1 marked")
    eq(PE:MarkSection(), 2)
    eq(lastChat(c), "Section 2 marked")
    eq(logTexts(c, "mark"), { "==== section 1 ====", "==== section 2 ====" })
    -- The count goes on after a reload (one sitting has many), and starts again with an empty log.
    local db = rawget(c.env, "PocketEssentialsDB")
    local c2, PE2 = T.new({ saved = db })
    eq(PE2:MarkSection(), 3, "the count did not go on after a reload")
    PE2:ClearDebug()
    eq(PE2:MarkSection(), 1, "an emptied log did not start the count again")
end)

test("0.16.4 rows: Mark and Snapshot are on the Controller tab, also while the layout is off, and on the Debug log tab", function()
    local c, PE = layoutClient({}, 3)
    for _, label in ipairs({ "Mark a test section", "Save a snapshot" }) do
        local row = optRow(PE, label)
        check(row, "no row " .. label)
        eq(row.always, true, label .. " shows only while the layout is on")
        eq(type(row.action), "function")
    end
    eq(optRow(PE, "Mark a test section").button, "Mark")
    eq(optRow(PE, "Save a snapshot").button, "Snapshot")
    PE:SetDebug(true)
    optRow(PE, "Mark a test section").action()
    eq(lastChat(c), "Section 1 marked")
    optRow(PE, "Save a snapshot").action()
    eq(lastChat(c), "Snapshot 1 saved to the debug log.")
    -- The Debug log tab's two buttons do the same.
    PE:OpenSettings("debug")
    c:advance(0.1)
    local buttons = {}
    local function walk(w)
        local st = c._state(w)
        if st.type == "Button" and w:IsVisible() then buttons[T.labelOf(w)] = w end
        for _, child in ipairs(st.children) do walk(child) end
        if st.scrollChild then walk(st.scrollChild) end
    end
    walk(rawget(c.env, "PocketEssentialsSettingsPanel"))
    check(buttons["Mark"], "no Mark button on the Debug log tab")
    check(buttons["Snapshot"], "no Snapshot button on the Debug log tab")
    c:click(buttons["Mark"])
    eq(lastChat(c), "Section 2 marked")
    c:click(buttons["Snapshot"])
    eq(lastChat(c), "Snapshot 2 saved to the debug log.")
    c:assertClean()
end)

test("0.16.4 snapshot: with the Debug log off nothing is written and chat says to switch it on", function()
    local c, PE = onClient()
    eq(PE.ControllerLayout:Snapshot(), false)
    eq(lastChat(c), "Switch the Debug log on first (Settings, Debug log).")
    eq(#logOf(c).lines, 0)
end)

test("0.16.4 snapshot: one block with the screen, the layout, every switch and every piece", function()
    local c, PE = onClient()
    PE:SetDebug(true)
    PE:MarkSection()
    eq(PE.ControllerLayout:Snapshot(), true)
    local lines = logTexts(c, "snapshot")
    eq(lines[1], "==== snapshot 1 ==== section 1")
    check(lines[#lines]:find("^==== snapshot 1 end ==== %d+ pieces, %d+ not found, %d+ overlaps?$"), "the end line: " .. lines[#lines])
    local W, H = c.UIParent:GetWidth(), c.UIParent:GetHeight()
    eq(lines[2], string.format("screen %dx%d, UI scale %.2f", math.floor(W + 0.5), math.floor(H + 0.5), c.UIParent:GetEffectiveScale()))
    eq(lines[3], 'Edit Mode layout "Pocket Essentials" (ours: yes)')
    local all = table.concat(lines, "\n")
    check(all:find("\nfeatures: [^\n]*ctrlLayout=on"), "the features line does not give the layout's switch")
    check(all:find("sellJunk=off", 1, true), "a feature that is off is not listed")
    for _, want in ipairs({ "panelSize=100", "ranged=1", "mainHand=1", "offHand=2", "hints=0", "mapButtons=0", "slim=0", "arrange=0" }) do
        check(all:find("\noptions: [^\n]*" .. want) or all:find("\noptions %(more%): [^\n]*" .. want), "no option " .. want)
    end
    -- Every line fits the log's 200 characters with its stamp and key.
    for _, l in ipairs(lines) do check(#l <= 170, "a snapshot line is too long: " .. l) end
    -- Our own panels: the main bar's two halves show at the inner spots, 134 by 98; the others are hidden.
    local dpad = pieceLine(lines, "main d-pad panel")
    check(dpad and dpad:find("| shown |", 1, true), "main d-pad panel: " .. tostring(dpad))
    local l, b, w, h, sc = numbers(dpad)
    about(l, W / 2 - 170 - 67, "main d-pad panel left")
    about(b, 66 - 49, "main d-pad panel bottom")
    eq({ w, h, sc }, { 134, 98, 1 })
    check(pieceLine(lines, "main face panel"):find("| shown |", 1, true), "main face panel is not shown")
    check(pieceLine(lines, "lt face panel"):find("| hidden |", 1, true), "lt face panel is not hidden")
    -- The game's frames: the map, the chat, a bar made see-through, a targeting picture, the PE button.
    for _, name in ipairs({ "map", "round map", "chat", "buffs", "debuffs", "quest tracker", "target", "target of target",
        "game bar main", "game bar LT", "game bar RT", "game bar LT+RT", "bar anchor bottom", "LB targeting picture",
        "RB targeting picture", "LB+LT button", "tap guard left", "tap guard right", "map's black disc", "PE button" }) do
        check(pieceLine(lines, name), "no line for " .. name)
    end
    check(pieceLine(lines, "game bar main"):find(" a=0.00", 1, true), "the faded bar's see-through is not given: " .. pieceLine(lines, "game bar main"))
    local lb = pieceLine(lines, "LB targeting picture")
    local ll, lbot = numbers(lb)
    about(ll, W / 2 - 178 - 60, "LB targeting picture left") -- the stand-in's picture is 60 wide, BOTTOMRIGHT at -178, 155
    about(lbot, 155, "LB targeting picture bottom")
    -- A frame this client does not have is said, not skipped.
    eq(pieceLine(lines, "hint box"), "piece: hint box | not found")
    -- A second one counts up.
    PE.ControllerLayout:Snapshot()
    check(logTexts(c, "snapshot")[#lines + 1] == "==== snapshot 2 ==== section 1", "the second snapshot's first line")
    c:assertClean()
end)

test("0.16.4 snapshot: overlapping visible pieces are named with the overlap in units and pixels; hidden and by-design ones are not", function()
    local c, PE = onClient()
    PE:SetDebug(true)
    -- The game's buffs put onto the chat: 100 by 40 units of the buffs' box inside the chat's.
    local chat, buffs = c.env.ChatFrame1, c.env.BuffFrame
    chat:ClearAllPoints()
    chat:SetSize(450, 170)
    chat:SetPoint("BOTTOMLEFT", c.UIParent, "BOTTOMLEFT", 17, 400)
    buffs:ClearAllPoints()
    buffs:SetSize(260, 80)
    buffs:SetPoint("BOTTOMLEFT", c.UIParent, "BOTTOMLEFT", 17 + 450 - 100, 400 + 170 - 40)
    -- The debuffs on the chat too, but hidden: listed, not an overlap.
    local debuffs = c.env.DebuffFrame
    debuffs:ClearAllPoints()
    debuffs:SetPoint("BOTTOMLEFT", c.UIParent, "BOTTOMLEFT", 20, 410)
    debuffs:Hide()
    PE.ControllerLayout:Snapshot()
    local lines = logTexts(c, "snapshot")
    local px = c.UIParent:GetEffectiveScale()
    local want = string.format("overlap: buffs + chat | 100.0 x 40.0 units (%d x %d px)", math.floor(100 * px + 0.5), math.floor(40 * px + 0.5))
    local found = false
    for _, l in ipairs(lines) do
        if l == want then found = true end
        if l:sub(1, 9) == "overlap: " then
            check(not l:find("debuffs", 1, true), "a hidden piece is in an overlap: " .. l)
            check(not l:find("tap guard", 1, true), "a tap guard is in an overlap: " .. l)
            check(not l:find("bar anchor", 1, true), "a bar anchor is in an overlap: " .. l)
            check(not l:find("game bar", 1, true), "a see-through bar is in an overlap: " .. l)
            check(not (l:find("round map", 1, true) and l:find("map's black disc", 1, true)), "the map and its own disc: " .. l)
        end
    end
    check(found, "no line " .. want .. " in:\n" .. table.concat(lines, "\n"))
    check(pieceLine(lines, "debuffs"):find("| hidden |", 1, true), "the hidden piece is not listed as hidden")
end)

test("0.16.4 snapshot: in a fight it waits for the end, and says so", function()
    local c, PE = onClient()
    PE:SetDebug(true)
    c:enterCombat()
    eq(PE.ControllerLayout:Snapshot(), false)
    eq(lastChat(c), "In a fight: the snapshot is saved when the fight is over.")
    eq(#logTexts(c, "snapshot"), 0)
    PE.ControllerLayout:Snapshot() -- a second tap in the same fight still makes one
    c:leaveCombat()
    c:advance(0.1)
    local lines = logTexts(c, "snapshot")
    eq(lines[1], "==== snapshot 1 ==== section 0")
    local starts = 0
    for _, l in ipairs(lines) do if l:find("^==== snapshot %d+ ==== section") then starts = starts + 1 end end
    eq(starts, 1)
    eq(lastChat(c), "Snapshot 1 saved to the debug log.")
    c:assertClean()
end)

test("0.16.4 snapshot: another part adds its pieces; a value the game hides is written <secret> and left out of the overlaps", function()
    local c, PE = onClient()
    PE:SetDebug(true)
    local hidden = 4321.5
    c.world.secrets[hidden] = true
    local function region(left)
        return { IsShown = function() return true end, IsVisible = function() return true end,
            GetLeft = function() return left end, GetBottom = function() return 10 end,
            GetWidth = function() return 2000 end, GetHeight = function() return 2000 end,
            GetEffectiveScale = function() return c.UIParent:GetEffectiveScale() end, GetAlpha = function() return 1 end }
    end
    PE.ControllerLayout:AddSnapshotSource(function(add)
        add("trial secret", region(hidden))
        add("trial big", region(0))
        add("trial missing", nil)
    end)
    -- A source that raises does not stop the snapshot.
    PE.ControllerLayout:AddSnapshotSource(function() error("a broken source") end)
    PE.ControllerLayout:Snapshot()
    local lines = logTexts(c, "snapshot")
    local secret = pieceLine(lines, "trial secret")
    check(secret and secret:find("l=<secret>", 1, true), "the hidden value is not written <secret>: " .. tostring(secret))
    eq(pieceLine(lines, "trial missing"), "piece: trial missing | not found")
    local big = 0
    for _, l in ipairs(lines) do
        if l:sub(1, 9) == "overlap: " then
            check(not l:find("trial secret", 1, true), "a piece with a hidden value is in an overlap: " .. l)
            if l:find("trial big", 1, true) then big = big + 1 end
        end
    end
    check(big > 0, "the added piece is not checked against the others")
    check(lines[#lines]:find("^==== snapshot 1 end ===="), "the snapshot did not finish: " .. lines[#lines])
end)

test("0.16.4 snapshot: with the layout off it still lists every piece, and makes no frame and no hook", function()
    local c, PE = layoutClient({}, 3)
    PE:SetDebug(true)
    local frames, hooks = #c:frames(), #c:callsTo("hooksecurefunc")
    eq(PE.ControllerLayout:Snapshot(), true)
    local lines = logTexts(c, "snapshot")
    eq(lines[3], 'Edit Mode layout "Gamepad" (ours: no)')
    check(pieceLine(lines, "chat"), "no line for the chat")
    eq(pieceLine(lines, "main d-pad panel"), "piece: main d-pad panel | not found")
    eq(#c:frames(), frames, "a frame was made")
    eq(#c:callsTo("hooksecurefunc"), hooks, "a hook was made")
    c:assertClean()
end)

---------------------------------------------------------------------------
-- 0.17.0: the slim bars' place in the plan, their switch, and how the layout starts and
-- stops them (spec 2026-11-24-0.17.0-slim-bars.md; the bars themselves: slimbars_test.lua)
---------------------------------------------------------------------------

local SLIM_RECTS = {
    ["player bar"] = { -498, 141, -218, 169 },
    ["target bar"] = { 218, 141, 498, 169 },
    ["cast bar"] = { 218, 127, 498, 139 },
    ["pet bar"] = { -498, 172, -362, 189 },
    ["target of target bar"] = { 362, 172, 498, 189 },
    ["pet boxes room"] = { -498, 192, -218, 213 },
    ["target boxes room"] = { 218, 172, 358, 193 },
}
-- The game's own pieces that are invisible while the slim bars show.
local GAME_FRAME_RECTS = { "player", "pet", "target", "target of target", "target auras", "target cast bar" }

test("0.17.0 plan: the seven slim rectangles, the same at every size, the two sides mirrored", function()
    local Plan = plan()
    eq(Plan.SlimRects(), SLIM_RECTS)
    local r = Plan.SlimRects()
    for _, pair in ipairs({ { "player bar", "target bar" }, { "pet bar", "target of target bar" } }) do
        local a, b = r[pair[1]], r[pair[2]]
        eq({ a[1], a[2], a[3], a[4] }, { -b[3], b[2], -b[1], b[4] }, pair[1] .. " mirrors " .. pair[2])
    end
    -- A fresh table each time.
    r["player bar"][1] = 0
    eq(Plan.SlimRects(), SLIM_RECTS)
    -- The design's sizes, in units: 264 by 26 px and 128 by 16 px on a 720 px screen.
    local px = 768 / 720
    check(math.abs(280 - 264 * px) < 2 and math.abs(28 - 26 * px) < 1, "the main bar is not the design's size")
    check(math.abs(136 - 128 * px) < 1 and math.abs(17 - 16 * px) < 1, "the small bar is not the design's size")
end)

test("0.17.0 plan: Slim bars is Off by default, and Off leaves the plan exactly as it was", function()
    local Plan = plan()
    eq(Plan.DEFAULTS.slim, 0)
    for _, size in ipairs(Plan.PANEL_SIZES) do
        local base = Plan.Rects({ panelSize = size })
        eq(Plan.Rects({ panelSize = size, slim = 0 }), base, size .. "%")
        eq(Plan.Rects({ panelSize = size, slim = 2 }), base, size .. "%: a value that is not 0 or 1")
        eq(Plan.Rects({ panelSize = size, slim = "yes" }), base, size .. "%: a value that is not a number")
        for name in pairs(SLIM_RECTS) do eq(base[name], nil, size .. "%: " .. name .. " while off") end
        for _, name in ipairs(GAME_FRAME_RECTS) do check(base[name], size .. "%: no " .. name .. " while off") end
        eq(Plan.Pieces({ panelSize = size, slim = 0 }), Plan.Pieces({ panelSize = size }), size .. "% pieces")
    end
    eq(Plan.TEMPLATE, 5, "the template number must not change: nobody's layout is rebuilt for this")
end)

test("0.17.0 plan: with Slim bars on no piece overlaps another, at every size and in every state", function()
    local Plan = plan()
    local W = 1365.33
    local SPOT_RECT = { innerLeft = "inner left diamond", outerLeft = "outer left diamond",
        innerRight = "inner right diamond", outerRight = "outer right diamond" }
    for _, size in ipairs(Plan.PANEL_SIZES) do
        for _, hints in ipairs({ 0, 1 }) do
            for _, mapButtons in ipairs({ 0, 1 }) do
                local what = "slim, " .. size .. "%, hints " .. hints .. ", map buttons " .. mapButtons
                local r = Plan.Rects({ panelSize = size, hints = hints, mapButtons = mapButtons, slim = 1 })
                for name, want in pairs(SLIM_RECTS) do eq(r[name], want, what .. ": " .. name) end
                -- The game's frames are invisible then: not pieces of the screen.
                for _, name in ipairs(GAME_FRAME_RECTS) do eq(r[name], nil, what .. ": " .. name) end
                -- The tooltip in the bottom right corner, taken 200 by 100.
                for i, want in ipairs({ W / 2 - 10 - 200, 10, W / 2 - 10, 110 }) do near(r.tooltip[i], want, what .. ": tooltip " .. i) end
                checkClear(r, what)
                -- Each trigger state by name: what is drawn then is clear of every slim piece.
                for state, halves in pairs(Plan.FaceStates()) do
                    for _, h in ipairs(halves) do
                        local diamond = r[SPOT_RECT[h.spot]]
                        check(diamond, what .. ": no rectangle for " .. h.spot)
                        for name in pairs(SLIM_RECTS) do
                            check(not overlapArea(diamond, r[name]), what .. ", " .. state .. ": " .. h.spot .. " overlaps the " .. name)
                        end
                    end
                end
            end
        end
    end
    -- The tightest spots: the largest diamonds end 2.2 under the cast bar, the LB / RB
    -- pictures 4 inside the bars, the room for the pet's boxes under the chat.
    local r = Plan.Rects({ panelSize = 120, slim = 1 })
    near(r["cast bar"][2] - r["outer right diamond"][4], 2.2, "cast bar over the diamonds at 120%")
    eq(r["target bar"][1] - r["RB targeting picture"][3], 4)
    eq(r["LB targeting picture"][1] - r["player bar"][3], 4)
    check(Plan.Rects({ slim = 1 })["pet boxes room"][4] < Plan.Rects({ slim = 1 }).chat[2], "the pet's boxes would reach the chat")
end)

test("0.17.0 plan: the tooltip's piece is in the corner with Slim bars on; no other piece changes", function()
    local Plan = plan()
    for _, size in ipairs(Plan.PANEL_SIZES) do
        local on, off = Plan.Pieces({ panelSize = size, slim = 1 }), Plan.Pieces({ panelSize = size })
        eq(#on, #off)
        for i, p in ipairs(on) do
            if p.system == "HudTooltip" then
                eq(p.anchor, { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", x = -10, y = 10 }, size .. "%")
            else
                eq(p, off[i], size .. "% " .. p.system)
            end
        end
    end
end)

test("0.17.0 switch: the row is Off by default; a change rewrites only the tooltip, asks for the reload and says once that it counts from then", function()
    local c, PE = onClient()
    local row = optRow(PE, "slim")
    check(row ~= nil, "no Slim bars row")
    eq(row.label, "Slim bars")
    eq(choicesOf(row), { { 0, "Off" }, { 1, "On" } })
    eq(opts(PE).slim, 0)
    for _, e in ipairs(ours(c).systems) do if e.anchorInfo then e.anchorInfo.offsetX = 222 end end
    choose(c, PE, "slim", 1)
    local rewritten = {}
    for _, e in ipairs(ours(c).systems) do
        if e.anchorInfo and e.anchorInfo.offsetX ~= 222 then rewritten[e.system] = true end
    end
    eq(rewritten, { [SYS.HudTooltip] = true })
    eq(systemEntry(ours(c), SYS.HudTooltip).anchorInfo,
        { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = -10, offsetY = 10 })
    eq(reloadReason(PE), RELOAD)
    -- Off again: the tooltip goes back over the target of target.
    choose(c, PE, "slim", 0)
    eq(systemEntry(ours(c), SYS.HudTooltip).anchorInfo.offsetY, 236)
    local said = 0
    for _, line in ipairs(T.chatLines(c)) do
        if line == "Slim bars count from the next reload." then said = said + 1 end
    end
    eq(said, 1)
    c:assertClean()
end)

test("0.17.0 switch: a change in a fight waits for the fight to end", function()
    local c, PE = onClient()
    c:enterCombat()
    choose(c, PE, "slim", 1)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1, "the layout was written in a fight")
    eq(systemEntry(ours(c), SYS.HudTooltip).anchorInfo.offsetY, 236)
    eq(statusText(PE), "Updating the layout after this fight.")
    c:leaveCombat()
    c:advance(0.1)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 2)
    eq(systemEntry(ours(c), SYS.HudTooltip).anchorInfo.offsetY, 10)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
end)

test("0.17.0 switch: refused while Edit Mode is open, and put back", function()
    local c, PE = onClient()
    c.world.editMode = true
    choose(c, PE, "slim", 1)
    eq(opts(PE).slim, 0)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(reloadReason(PE), nil)
    c:assertClean()
end)

-- A stand-in for PE.SlimBars that records each call (as faceStub does for the spell pictures).
local function slimStub(c, PE)
    local s = { calls = {}, reason = nil }
    function s:Start()
        s.calls[#s.calls + 1] = { "Start", combat = c.world.inCombat }
        if s.startFails then error("slim start failed") end
        if s.refuse then return false, s.refuse end
        return true
    end
    function s:Stop()
        s.calls[#s.calls + 1] = { "Stop", combat = c.world.inCombat }
        if s.stopFails then error("slim stop failed") end
    end
    function s:Status() return s.reason end
    PE.SlimBars = s
    return s
end

test("0.17.0 layout: with the switch Off the slim bars' file is never called", function()
    local c, PE = layoutClient({}, 3)
    local slim = slimStub(c, PE)
    switchOn(c, PE)
    c:fire("PLAYER_ENTERING_WORLD")
    c:advance(0.1)
    switchOff(c, PE)
    eq(#slim.calls, 0)
    -- Switching the row On counts from the next reload: still nothing this session.
    local c2, PE2 = layoutClient({}, 3)
    local slim2 = slimStub(c2, PE2)
    switchOn(c2, PE2)
    choose(c2, PE2, "slim", 1)
    c2:fire("PLAYER_ENTERING_WORLD")
    c2:advance(0.1)
    eq(#slim2.calls, 0, "started without a reload")
end)

test("0.17.0 layout: with the switch On the bars start when the layout is placed, out of a fight, and stop when it goes", function()
    local c, PE = layoutClient({}, 3)
    local slim = slimStub(c, PE)
    opts(PE).slim = 1
    switchOn(c, PE)
    check(count(slim, "Start") >= 1, "not started")
    eq(count(slim, "Stop"), 0)
    for _, call in ipairs(slim.calls) do check(not call.combat, "called in a fight") end
    -- Switching the row Off counts from the next reload: the bars stay this session.
    choose(c, PE, "slim", 0)
    eq(count(slim, "Stop"), 0, "stopped without a reload")
    opts(PE).slim = 1
    -- Another layout picked: stopped. Ours again: started.
    local starts = count(slim, "Start")
    c.world.layouts.activeLayout = 3
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    c:advance(0.1)
    eq(slim.calls[#slim.calls][1], "Stop")
    c.world.layouts.activeLayout = 4
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    c:advance(0.1)
    eq(slim.calls[#slim.calls][1], "Start")
    check(count(slim, "Start") > starts, "not started again")
    -- The layout switched off: stopped.
    switchOff(c, PE)
    eq(slim.calls[#slim.calls][1], "Stop")
    c:assertClean()
end)

test("0.17.0 layout: the layout going off in a fight stops the slim bars only when the fight is over", function()
    local c, PE = layoutClient({}, 3)
    local slim = slimStub(c, PE)
    opts(PE).slim = 1
    switchOn(c, PE)
    c:enterCombat()
    switchOff(c, PE)
    eq(count(slim, "Stop"), 0, "stopped in a fight")
    c:leaveCombat()
    c:advance(0.1)
    check(count(slim, "Stop") >= 1, "not stopped after the fight")
    for _, call in ipairs(slim.calls) do check(not call.combat, "called in a fight") end
    -- Switched on in a fight: nothing until it ends.
    local c2, PE2 = layoutClient({}, 3)
    local slim2 = slimStub(c2, PE2)
    opts(PE2).slim = 1
    c2:enterCombat()
    switchOn(c2, PE2)
    eq(#slim2.calls, 0)
    c2:leaveCombat()
    c2:advance(0.1)
    check(count(slim2, "Start") >= 1, "not started after the fight")
end)

test("0.17.0 layout: a start that refuses or fails is logged and the layout carries on; the card says why the bars are off", function()
    local c, PE = layoutClient({}, 3)
    PE:SetDebug(true)
    local slim = slimStub(c, PE)
    slim.refuse = "the game's player frame was not found"
    opts(PE).slim = 1
    switchOn(c, PE)
    local found = false
    for _, l in ipairs(logTexts(c, "ctrlLayout")) do
        if l == "slim bars not shown: the game's player frame was not found" then found = true end
    end
    check(found, "the refusal is not in the debug log")
    check(barCalls(c, "SetScale") > 0, "the bars were not placed")
    slim.reason = "they hit an error"
    check(statusText(PE):find("Pocket Essentials' slim bars are off: they hit an error.", 1, true), "the card: " .. tostring(statusText(PE)))
    slim.reason = nil
    eq(statusText(PE), USING)
    -- A start that raises: one error for the feature, the layout still placed.
    local c2, PE2 = layoutClient({}, 3)
    local slim2 = slimStub(c2, PE2)
    slim2.startFails = true
    opts(PE2).slim = 1
    switchOn(c2, PE2)
    check(barCalls(c2, "SetScale") > 0, "the bars were not placed")
    check(#PE2.errors >= 1, "the failure was not logged")
end)

test("0.17.0 layout: a missing slim bars file changes nothing", function()
    local c, PE = layoutClient({}, 3)
    PE.SlimBars = nil
    opts(PE).slim = 1
    switchOn(c, PE)
    switchOff(c, PE)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- 0.19.0: the square map (spec 2026-11-25-0.19.0-square-map.md, "The switch", "Size and
-- spot", "Tests"): the plan's numbers and the "Map look" row. What is drawn on the map is in
-- maplook_test.lua.
---------------------------------------------------------------------------

-- Plan.Rects() as 0.18.0 gives it (printed from that code with %.17g), for the rule that
-- Round changes nothing.
local RECTS_0_18 = {
    ["LB targeting picture"] = { -214, 155, -178, 187 },
    ["LB+LT button"] = { -157, 169, -119, 207 },
    ["LB+LT prompt"] = { -174, 146, -102, 170 },
    ["MainHand timer"] = { -81.200000000000003, 194, 89.200000000000003, 206 },
    ["OffHand timer"] = { -81.200000000000003, 208, 89.200000000000003, 220 },
    ["RB targeting picture"] = { 178, 155, 214, 187 },
    ["RB+RT button"] = { 119, 169, 157, 207 },
    ["RB+RT prompt"] = { 102, 146, 174, 170 },
    ["Ranged timer"] = { -81.200000000000003, 222, 89.200000000000003, 234 },
    ["XP bars"] = { -298, 732, 298, 766 },
    ["buffs and debuffs"] = { -47.335000000000036, 640, 407.66499999999996, 728 },
    ["chat"] = { -665.66499999999996, 245, -215.66499999999996, 415 },
    ["inner left diamond"] = { -237, 17, -103, 115 },
    ["inner right diamond"] = { 103, 17, 237, 115 },
    ["map"] = { -65.299999999999997, 49.25, 73.299999999999997, 187.84999999999999 },
    ["outer left diamond"] = { -383, 17, -249, 115 },
    ["outer right diamond"] = { 249, 17, 383, 115 },
    ["pet"] = { -515, 181, -395, 230 },
    ["player"] = { -627, 56, -395, 156 },
    ["quest tracker"] = { 417.66499999999996, 363, 677.66499999999996, 763 },
    ["round button"] = { -672.66499999999996, 162, -595.86500000000001, 238.80000000000001 },
    ["target"] = { 395, 56, 627, 156 },
    ["target auras"] = { 420, 156, 542, 178.5 },
    ["target cast bar"] = { 518, 0, 668, 10 },
    ["target of target"] = { 395, 181, 515, 230 },
    ["title strip"] = { -83, 8, 69, 31 },
    ["tooltip"] = { 472.66499999999996, 236, 672.66499999999996, 336 },
}

-- The arrangement saved on the device on 2026-11-25 (its debug log's "arrange: offset:" lines),
-- as the plan takes a session's offsets.
local function arranged(extra)
    local v = { arrange = 1, arrangeWheel = 0,
        offsets = { map = { x = 0, y = -2 }, ["buffs and debuffs"] = { x = 0, y = 4 } },
        charOffsets = {
            ["inner left diamond"] = { x = 0, y = -16 }, ["inner right diamond"] = { x = 0, y = -16 },
            ["outer left diamond"] = { x = 0, y = -16 }, ["outer right diamond"] = { x = 0, y = -16 },
            ["LB targeting picture"] = { x = 94, y = -56 }, ["RB targeting picture"] = { x = -94, y = -56 },
            ["player bar"] = { x = -18, y = -16 }, ["target bar"] = { x = 18, y = -16 },
        } }
    for k, x in pairs(extra or {}) do v[k] = x end
    return v
end

-- The overlapping pairs of a plan, as "a|b" strings in order.
local function pairsOf(Plan, v)
    local out = {}
    for _, o in ipairs(Plan.Overlaps(Plan.Rects(v))) do out[#out + 1] = o.a .. "|" .. o.b end
    return out
end

test("0.19.0: the option is Round by default and reads only 0 and 1", function()
    local Plan = plan()
    eq(Plan.DEFAULTS.mapLook, 0)
    eq(Plan.MapLook(nil), 0)
    eq(Plan.MapLook({}), 0)
    eq(Plan.MapLook({ mapLook = 0 }), 0)
    eq(Plan.MapLook({ mapLook = 1 }), 1)
    for _, bad in ipairs({ 2, -1, "1", true, 0.5 }) do eq(Plan.MapLook({ mapLook = bad }), 0, "mapLook " .. tostring(bad)) end
    eq(Plan.MapLook(100), 0, "a Spell panel size")
    -- A saved 2 is not kept as a third look.
    eq(Plan.Pieces({ mapLook = 2 }), Plan.Pieces({}))
    eq(Plan.MAP_SQUARE.size, 100)
    eq(Plan.MAP_SQUARE.edge, 1)
    eq(Plan.MAP_SQUARE.bottom, 4)
end)

test("0.19.0: Round gives 0.18.0's rectangles and pieces, with the key 0 or absent", function()
    local Plan = plan()
    for what, r in pairs({ ["no options"] = Plan.Rects(), ["mapLook 0"] = Plan.Rects({ mapLook = 0 }), ["a size"] = Plan.Rects(100) }) do
        local n = 0
        for name, want in pairs(RECTS_0_18) do
            n = n + 1
            check(r[name], what .. ": no rectangle " .. name)
            for i = 1, 4 do near(r[name][i], want[i], what .. ": " .. name .. " " .. i) end
        end
        for name in pairs(r) do check(RECTS_0_18[name], what .. ": a rectangle 0.18.0 did not have: " .. name) end
        eq(n, 27)
    end
    eq(Plan.Rects({ mapLook = 0 }), Plan.Rects())
    eq(Plan.Rects({ mapLook = 0, slim = 1, panelSize = 120, hints = 1, mapButtons = 1 }),
        Plan.Rects({ slim = 1, panelSize = 120, hints = 1, mapButtons = 1 }))
    eq(Plan.Pieces({ mapLook = 0 }), Plan.Pieces({}))
    eq(Plan.Shoulders({ mapLook = 0 }), { left = { "BOTTOMRIGHT", -178, 155 }, right = { "BOTTOMLEFT", 178, 155 } })
    eq(Plan.MapBox({ mapLook = 0 }), Plan.Rects().map)
    eq(Plan.MapBox(), Plan.Rects().map)
end)

test("0.19.0: Square gives the edge box -100..100 by 4..204 and no title strip", function()
    local Plan = plan()
    local r = Plan.Rects({ mapLook = 1 })
    for i, want in ipairs({ -100, 4, 100, 204 }) do
        check(math.abs(r.map[i] - want) < 0.01, "map " .. i .. ": expected " .. want .. ", got " .. tostring(r.map[i]))
        check(math.abs(Plan.MapBox({ mapLook = 1 })[i] - want) < 0.01, "MapBox " .. i)
    end
    eq(r["title strip"], nil)
    eq(Plan.Rects({ mapLook = 1, mapButtons = 1 })["title strip"], nil, "with the map buttons asked for")
    -- The Arrange piece "map" is then the map alone.
    local listed = {}
    for _, name in ipairs(Plan.ARRANGE_BY.map.rects) do if r[name] then listed[#listed + 1] = name end end
    eq(listed, { "map" })
    -- A saved offset moves the edge box like any Edit Mode piece.
    local moved = Plan.Rects({ mapLook = 1, arrange = 1, offsets = { map = { x = 6, y = 10 } } }).map
    for i, want in ipairs({ -94, 14, 106, 214 }) do check(math.abs(moved[i] - want) < 0.01, "moved map " .. i) end
end)

test("0.19.0: Square lifts the timers 14 and moves the targeting pictures 20 out; nothing else moves", function()
    local Plan = plan()
    for _, base in ipairs({ {}, { slim = 1 }, { panelSize = 120, hints = 1 }, arranged({ slim = 1 }) }) do
        local round = Plan.Rects(with(base))
        local sq = with(base)
        sq.mapLook = 1
        local square = Plan.Rects(sq)
        local MOVED = { map = true, ["title strip"] = true }
        for _, name in ipairs({ "MainHand timer", "OffHand timer", "Ranged timer" }) do
            MOVED[name] = true
            eq(square[name], { round[name][1], round[name][2] + 14, round[name][3], round[name][4] + 14 }, name)
        end
        local l, r = "LB targeting picture", "RB targeting picture"
        MOVED[l], MOVED[r] = true, true
        eq(square[l], { round[l][1] - 20, round[l][2], round[l][3] - 20, round[l][4] }, l)
        eq(square[r], { round[r][1] + 20, round[r][2], round[r][3] + 20, round[r][4] }, r)
        for name, q in pairs(round) do
            if not MOVED[name] then eq(square[name], q, name .. " moved with the square map") end
        end
        for name in pairs(square) do check(round[name], "a new rectangle with the square map: " .. name) end
    end
    -- The lowest timer sits 4 over the edge box.
    local r = Plan.Rects({ mapLook = 1 })
    eq(r["MainHand timer"][2] - r.map[4], 4)
    eq(Plan.Shoulders({ mapLook = 1 }), { left = { "BOTTOMRIGHT", -198, 155 }, right = { "BOTTOMLEFT", 198, 155 } })
end)

test("0.19.0: Square has no overlap with nothing moved, at every Spell panel size", function()
    local Plan = plan()
    eq(Plan.SQUARE_TIGHT_SIZES, {}, "no size brings a spell panel to the square map")
    for _, size in ipairs(Plan.PANEL_SIZES) do
        for _, hints in ipairs({ 0, 1 }) do
            local o = { mapLook = 1, panelSize = size, hints = hints }
            eq(pairsOf(Plan, o), {}, size .. "%, hints " .. hints)
            -- The inner panels stay 3 clear of the edge box.
            local r = Plan.Rects(o)
            near(r.map[1] - r["inner left diamond"][3], 3, size .. "%: left panel to the map")
            near(r["inner right diamond"][1] - r.map[3], 3, size .. "%: right panel to the map")
        end
    end
end)

-- The named exception (the spec's "As built"): the pictures' 20 outwards is made for a
-- picture that was moved in beside the map. Left at their built-in spot with the slim bars on,
-- they reach 16 into the bars' inner ends (218 from the centre). Arrange it yourself moves them.
test("0.19.0: Square with Slim bars and nothing moved overlaps only at the targeting pictures", function()
    local Plan = plan()
    for _, size in ipairs(Plan.PANEL_SIZES) do
        eq(pairsOf(Plan, { mapLook = 1, slim = 1, panelSize = size }),
            { "LB targeting picture|player bar", "RB targeting picture|target bar", "RB targeting picture|target boxes room" }, size .. "%")
        eq(pairsOf(Plan, { mapLook = 0, slim = 1, panelSize = size }), {}, size .. "% round")
    end
    local hit = Plan.Overlaps(Plan.Rects({ mapLook = 1, slim = 1 }))[1]
    eq({ hit.w, hit.h }, { 16, 14 })
end)

test("0.19.0: Square has no overlap with the arrangement of 2026-11-25", function()
    local Plan = plan()
    for _, size in ipairs({ 80, 90, 100 }) do
        eq(pairsOf(Plan, arranged({ mapLook = 1, slim = 1, panelSize = size })), {}, size .. "%")
    end
    -- The nearest points at 100%, as the spec lists them.
    local r = Plan.Rects(arranged({ mapLook = 1, slim = 1 }))
    for i, want in ipairs({ -100, 2, 100, 202 }) do check(math.abs(r.map[i] - want) < 0.01, "map " .. i) end
    near(r.map[1] - r["LB targeting picture"][3], 4, "LB picture to the map")
    near(r["RB targeting picture"][1] - r.map[3], 4, "RB picture to the map")
    near(r["RB+RT prompt"][1] - r.map[3], 2, "prompt to the map")
    near(r["inner right diamond"][1] - r.map[3], 3, "inner panel to the map")
    -- That arrangement was made at 100%. At 110% and 120% its targeting pictures meet the
    -- larger inner panels, with the round map as with the square one: not the square's doing.
    local WANT = { "LB targeting picture|inner left diamond", "RB targeting picture|inner right diamond" }
    for _, size in ipairs({ 110, 120 }) do
        eq(pairsOf(Plan, arranged({ mapLook = 1, slim = 1, panelSize = size })), WANT, size .. "% square")
        eq(pairsOf(Plan, arranged({ mapLook = 0, slim = 1, panelSize = size })), WANT, size .. "% round")
    end
end)

test("0.19.0: the layout written for Square holds Size 5; for Round or no key, Size 2", function()
    local Plan = plan()
    local e = fakeEnums()
    local function mapOf(o)
        local layout = Plan.Build(baseLayout(e), o, e)
        local entry = systemEntry(layout, e.system.Minimap)
        return entry, settingValue(entry, e.setting.Minimap.Size), settingValue(entry, e.setting.Minimap.HeaderUnderneath)
    end
    local entry, size, under = mapOf({ mapLook = 1 })
    eq({ size, under }, { 5, 1 })
    eq(entry.anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = -10, offsetY = 0 })
    for what, o in pairs({ round = { mapLook = 0 }, ["no key"] = {}, ["a bad value"] = { mapLook = "square" } }) do
        local entry2, size2, under2 = mapOf(o)
        eq({ size2, under2 }, { 2, 1 }, what)
        eq(entry2.anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = -6, offsetY = 0 }, what)
    end
    -- The pieces: the map at -10, 0 (the edge box's middle on the screen's) and the timers 14 up.
    local list = Plan.Pieces({ mapLook = 1 })
    eq(piece(list, "Minimap").settings, { Size = 5, HeaderUnderneath = 1 })
    eq({ piece(list, "SwingTimer", "MainHand").anchor.y, piece(list, "SwingTimer", "OffHand").anchor.y,
        piece(list, "SwingTimer", "Ranged").anchor.y }, { 208, 222, 236 })
    eq(piece(list, "SwingTimer", "MainHand").anchor.x, piece(Plan.Pieces({}), "SwingTimer", "MainHand").anchor.x)
    -- Every other piece is the round plan's.
    local round = Plan.Pieces({})
    for i, p in ipairs(list) do
        if p.system ~= "Minimap" and p.system ~= "SwingTimer" then eq(p, round[i], "piece " .. i .. " (" .. p.system .. ")") end
    end
end)

test("0.19.0: the Map look row, Round and Square, bigger", function()
    local _, PE = layoutClient({}, 3)
    local row = optRow(PE, "mapLook")
    check(row ~= nil, "no Map look row")
    eq(row.label, "Map look")
    eq(choicesOf(row), { { 0, "Round" }, { 1, "Square, bigger" } })
    eq(opts(PE).mapLook, 0)
end)

test("0.19.0: Square rewrites the map and the timers and asks for the reload; Round puts them back", function()
    local c, PE = onClient()
    local function mapEntry() return systemEntry(ours(c), SYS.Minimap) end
    local function timerY(index) return systemEntry(ours(c), SYS.SwingTimer, SWING[index]).anchorInfo.offsetY end
    local SIZE = c.env.Enum.EditModeMinimapSetting.Size
    eq(settingValue(mapEntry(), SIZE), 2)
    -- Every entry moved by hand in Edit Mode; only the map and the timers lose that.
    for _, e in ipairs(ours(c).systems) do if e.anchorInfo then e.anchorInfo.offsetX = 222 end end
    choose(c, PE, "mapLook", 1)
    local rewritten = {}
    for _, e in ipairs(ours(c).systems) do
        if e.anchorInfo and e.anchorInfo.offsetX ~= 222 then rewritten[e.system] = true end
    end
    eq(rewritten, { [SYS.Minimap] = true, [SYS.SwingTimer] = true })
    eq(settingValue(mapEntry(), SIZE), 5)
    eq({ mapEntry().anchorInfo.offsetX, mapEntry().anchorInfo.offsetY }, { -10, 0 })
    eq({ timerY("MainHand"), timerY("OffHand"), timerY("Ranged") }, { 208, 222, 236 })
    eq(reloadReason(PE), RELOAD)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 2)
    PE:GetModule("ctrlLayout"):CancelReload()
    choose(c, PE, "mapLook", 0)
    eq(settingValue(mapEntry(), SIZE), 2)
    eq({ mapEntry().anchorInfo.offsetX, mapEntry().anchorInfo.offsetY }, { -6, 0 })
    eq({ timerY("MainHand"), timerY("OffHand"), timerY("Ranged") }, { 194, 208, 222 })
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
end)

test("0.19.0: a Map look change in a fight is written when the fight ends; with Edit Mode open it is refused", function()
    local c, PE = onClient()
    c:enterCombat()
    choose(c, PE, "mapLook", 1)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1, "written in a fight")
    eq(reloadReason(PE), nil)
    c:leaveCombat()
    c:advance(0.1)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 2)
    eq(settingValue(systemEntry(ours(c), SYS.Minimap), c.env.Enum.EditModeMinimapSetting.Size), 5)
    eq(reloadReason(PE), RELOAD)
    -- Edit Mode open: the row goes back and nothing is written.
    local c2, PE2 = onClient()
    c2.world.editMode = true
    choose(c2, PE2, "mapLook", 1)
    eq(opts(PE2).mapLook, 0)
    eq(#c2:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(statusText(PE2), "Close Edit Mode first.")
end)

-- Review focus: a saved file from 0.18.0 has no mapLook key.
test("0.19.0: a saved layout from 0.18.0 without the key is Round: nothing rewritten, no reload asked for", function()
    local c, PE = onClient()
    local file = deepCopy(db(c))
    local char = deepCopy(charDB(c))
    local list, active = deepCopy(c.world.layouts.layouts), c.world.layouts.activeLayout
    file.options.ctrlLayout.mapLook = nil -- as 0.18.0 saved it
    local c2, PE2 = T.new({ gamepadUI = true, saved = file, savedChar = char, setup = function(c)
        c.world.layouts = { layouts = list, activeLayout = active }
    end })
    local Plan = PE2.LayoutPlan
    eq(Plan.MapLook(opts(PE2)), 0)
    eq(layoutCalls(c2), 0, "the layout was written at login")
    eq(reloadReason(PE2), nil)
    eq(statusText(PE2), USING)
    eq(settingValue(systemEntry(ours(c2), SYS.Minimap), c2.env.Enum.EditModeMinimapSetting.Size), 2)
    eq(Plan.Rects(PE2:GetModule("ctrlLayout"):View()).map, Plan.Rects().map)
    c2:assertClean()
end)

test("0.19.0: with Square the Map buttons row reads Round map only and the buttons stay hidden", function()
    local c, PE = onClient()
    local row = optRow(PE, "mapButtons")
    local m = PE:GetModule("ctrlLayout")
    eq(row.value(m), nil, "the note with the round map")
    choose(c, PE, "mapLook", 1)
    eq(row.value(m), "Round map only")
    allShown(mapButtons(c), false, "Square")
    choose(c, PE, "mapButtons", 1)
    allShown(mapButtons(c), false, "Square, Map buttons tapped to Shown")
    -- Back to Round: the remembered choice counts again.
    choose(c, PE, "mapLook", 0)
    eq(row.value(m), nil)
    allShown(mapButtons(c), true, "Round again, Shown")
    c:assertClean()
end)

test("0.19.0: the targeting pictures follow the Map look at once, and the session's view carries it", function()
    local c, PE = onClient()
    local Plan = PE.LayoutPlan
    local m = PE:GetModule("ctrlLayout")
    local function leftX() return (select(4, (extras(c)):GetPoint(1))) end
    eq(leftX(), -178)
    eq(m:View().mapLook, 0)
    choose(c, PE, "mapLook", 1)
    eq(m:View().mapLook, 1)
    eq(leftX(), -198)
    eq(Plan.Shoulders().left[2], -198, "the session's look for a caller with no options")
    choose(c, PE, "mapLook", 0)
    eq(leftX(), -178)
    eq(Plan.Shoulders().left[2], -178)
end)

test("0.19.0: the status line says when pieces overlap with the square map", function()
    local c, PE = onClient()
    eq(statusText(PE), USING)
    choose(c, PE, "mapLook", 1)
    PE:GetModule("ctrlLayout"):CancelReload()
    eq(statusText(PE), USING, "Square with the game's frames: nothing overlaps")
    -- With the slim bars on at login and nothing moved, the three pairs are said.
    local file, char = deepCopy(db(c)), deepCopy(charDB(c))
    local list, active = deepCopy(c.world.layouts.layouts), c.world.layouts.activeLayout
    file.options.ctrlLayout.slim = 1
    local c2, PE2 = T.new({ gamepadUI = true, saved = file, savedChar = char, setup = function(c)
        c:addUnitFrames()
        c.world.layouts = { layouts = list, activeLayout = active }
    end })
    check(statusText(PE2):find("With the square map 3 pairs of pieces overlap. Arrange the screen shows which, and moves them.", 1, true),
        "the card: " .. tostring(statusText(PE2)))
end)

return { known = KNOWN_FAILURES }
