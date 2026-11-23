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

test("layout: Scales give size times the fine-tune, capped at 100%, the both-triggers bar 0.7 of that", function()
    local Plan = plan()
    local dM, dS, dB = Plan.Scales(with(Plan.DEFAULTS))
    near(dM, 1, "default kM")
    near(dS, 1, "default kS")
    near(dB, 0.7, "default kB")
    local kM, kS, kB = Plan.Scales(with({ size = 85 }))
    near(kM, 0.85, "kM")
    near(kS, 0.85, "kS")
    near(kB, 0.595, "kB")
    local _, kS2 = Plan.Scales(with({ size = 100, fineSide = 1.15 }))
    near(kS2, 1, "kS capped")
    local kM3 = Plan.Scales(with({ size = 70, fineMain = 0.85 }))
    near(kM3, 0.595, "kM small")
end)

test("layout: MapY is 44 with the timers under, 6 otherwise, and 90 or more with the main bar under", function()
    local Plan = plan()
    eq(Plan.MapY(with(Plan.DEFAULTS)), 44)
    eq(Plan.MapY(with({ timers = "bars" })), 6)
    eq(Plan.MapY(with({ timers = "above" })), 6)
    eq(Plan.MapY(with({ main = "under", timers = "under" })), 126)
    eq(Plan.MapY(with({ main = "under", timers = "above" })), 90)
    eq(Plan.MapY(with({ main = "under", timers = "bars", size = 70 })), 90, "the template is written for 100%")
    -- A shown Off Hand timer adds 16 under the map.
    eq(Plan.MapY(with({ offHand = 0 })), 60)
    eq(Plan.MapY(with({ main = "under", offHand = 1 })), 142)
    eq(Plan.MapY(with({ timers = "above", offHand = 0 })), 6)
end)

test("layout: BarSpots for the defaults follow the spec's Bars table", function()
    local Plan = plan()
    local o = with(Plan.DEFAULTS)
    o.size = 85 -- the scaled arithmetic (the default is 100)
    local s = Plan.BarSpots(o)
    near(s.left.x, -(218.4 / 2 + 14 + 208 * 0.85 / 2), "left.x")
    near(s.left.y, 8 + 68 * 0.85 / 2, "left.y")
    near(s.left.s, 0.85, "left.s")
    near(s.right.x, -s.left.x, "right.x")
    near(s.right.y, s.left.y, "right.y")
    near(s.top.x, 0, "top.x")
    near(s.top.y, 44 + 226.4 + 12 + 68 * 0.85 / 2, "top.y")
    near(s.top.s, 0.85, "top.s")
    eq(s.bottom.s, 1)
    near(s.bottom.x, 0, "bottom.x")
    near(s.bottom.y, 44 + 226.4 * 0.62 + 50, "bottom.y")
    near(s.both.x, 0, "both.x")
    near(s.both.y, s.top.y + 68 * 0.85 / 2 + 22 + 68 * 0.595 / 2, "both.y")
    near(s.both.s, 0.595, "both.s")
    -- Timers under the LT and RT bars: both side bars sit 22 higher.
    local b = Plan.BarSpots(with({ timers = "bars", size = 85 }))
    near(b.left.y, s.left.y + 22, "lifted left")
    near(b.right.y, s.right.y + 22, "lifted right")
end)

test("layout: BarSpots with the main bar under the map", function()
    local Plan = plan()
    local o = with({ main = "under", timers = "above", size = 85 })
    local s = Plan.BarSpots(o)
    near(s.left.x, -(208 * 0.85 / 2 + 12 + 208 * 0.85 / 2), "left.x")
    near(s.left.y, 8 + 68 * 0.85 / 2, "left.y")
    near(s.top.y, 8 + 68 * 0.85 / 2, "top.y")
    near(s.both.y, 90 + 226.4 + 14 + 68 * 0.595 / 2, "both.y")
    near(s.bottom.y, 90 + 226.4 * 0.5 + 50, "bottom.y")
    eq(s.bottom.s, 1)
end)

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

test("layout: Pieces for the defaults carry the template's anchors and settings", function()
    local Plan = plan()
    local list = Plan.Pieces(with(Plan.DEFAULTS))
    local map = piece(list, "Minimap")
    check(map, "no Minimap piece")
    eq(map.anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 0, y = 44 })
    eq(map.settings, { Size = 3, HeaderUnderneath = 1 })
    eq(map.moved, true)
    local chat = piece(list, "ChatFrame")
    eq(chat.anchor, { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -30, y = -40 })
    eq(chat.settings, { WidthHundreds = 4, WidthTensAndOnes = 30, HeightHundreds = 2, HeightTensAndOnes = 10 })
    eq(piece(list, "AuraFrame", "BuffFrame").anchor.y, -292)
    eq(piece(list, "AuraFrame", "DebuffFrame").anchor.y, -330)
    local quest = piece(list, "ObjectiveTracker")
    eq(quest.anchor.y, -375)
    eq(quest.settings, { Height = 0 })
    local ranged = piece(list, "SwingTimer", "Ranged")
    eq(ranged.settings.Visibility, 1)
    eq(ranged.settings.Scale, 3)
    eq(ranged.settings.Width, 0)
    eq(ranged.settings.Height, 0)
    eq(ranged.anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 0, y = 24 })
    eq(piece(list, "SwingTimer", "MainHand").anchor.y, 8)
    eq(piece(list, "SwingTimer", "MainHand").settings.Visibility, 1)
    eq(piece(list, "SwingTimer", "OffHand").settings.Visibility, 2)
    eq(piece(list, "SwingTimer", "OffHand").anchor.y, -8)
    eq(piece(list, "UnitFrame", "Player").anchor,
        { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", x = 20, y = 20 })
    eq(piece(list, "UnitFrame", "Pet").anchor,
        { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", x = 40, y = 124 })
    eq(piece(list, "UnitFrame", "Target").anchor,
        { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", x = -20, y = 20 })
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

test("layout: Pieces follow the frames option", function()
    local Plan = plan()
    local flat = Plan.Pieces(with({ frames = "flat" }))
    eq(piece(flat, "UnitFrame", "Pet").anchor,
        { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -401, y = 130 })
    eq(piece(flat, "UnitFrame", "Player").anchor.x, -165)
    eq(piece(flat, "UnitFrame", "Target").anchor,
        { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 165, y = 112 })
    local stacked = Plan.Pieces(with({ frames = "stacked" }))
    eq(piece(stacked, "UnitFrame", "Pet").anchor,
        { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -185, y = 216 })
end)

test("layout: Pieces follow the timers option", function()
    local Plan = plan()
    -- Off Hand shown with the timers under: the stack keeps Ranged on top.
    local shown = Plan.Pieces(with({ offHand = 0 }))
    eq(piece(shown, "SwingTimer", "OffHand").anchor.y, 8)
    eq(piece(shown, "SwingTimer", "MainHand").anchor.y, 24)
    eq(piece(shown, "SwingTimer", "Ranged").anchor.y, 40)
    eq(piece(shown, "Minimap").anchor.y, 60)
    -- Above the bars.
    local o = with({ timers = "above" })
    local spots = Plan.BarSpots(with({ timers = "above", size = 100, fineMain = 1, fineSide = 1, fineBoth = 1 }))
    local topY = spots.both.y + 68 * 0.7 / 2
    local above = Plan.Pieces(o)
    near(piece(above, "SwingTimer", "Ranged").anchor.y, topY + 40, "above ranged")
    near(piece(above, "SwingTimer", "MainHand").anchor.y, topY + 24, "above main hand")
    near(piece(above, "SwingTimer", "OffHand").anchor.y, topY + 8, "above off hand")
    eq(piece(above, "Minimap").anchor.y, 6)
    -- Under the LT and RT bars.
    local sideX = -Plan.BarSpots(with({ timers = "bars", size = 100 })).left.x
    local bars = Plan.Pieces(with({ timers = "bars" }))
    near(piece(bars, "SwingTimer", "Ranged").anchor.x, -sideX, "bars ranged x")
    near(piece(bars, "SwingTimer", "MainHand").anchor.x, sideX, "bars main hand x")
    near(piece(bars, "SwingTimer", "OffHand").anchor.x, sideX, "bars off hand x")
    eq(piece(bars, "SwingTimer", "Ranged").anchor.y, 6)
    eq(piece(bars, "SwingTimer", "OffHand").anchor.y, 22)
    -- Visibility is the option's value.
    local vis = Plan.Pieces(with({ ranged = 2, mainHand = 0, offHand = 1 }))
    eq(piece(vis, "SwingTimer", "Ranged").settings.Visibility, 2)
    eq(piece(vis, "SwingTimer", "MainHand").settings.Visibility, 0)
    eq(piece(vis, "SwingTimer", "OffHand").settings.Visibility, 1)
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
    eq(map.anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 44 })
    eq(settingValue(map, e.setting.Minimap.Size), 3)
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
    eq(layout.systems[1].anchorInfo.offsetY, 44)
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
    eq(layout.systems[1].anchorInfo.offsetX, 20)
    eq(layout.systems[2].anchorInfo.offsetX, 40)
    eq(layout.systems[2].isInDefaultPosition, false)
end)

test("layout: with the main bar under the map the timer stack sits between that bar and the map", function()
    local Plan = plan()
    local hidden = Plan.Pieces(with({ main = "under" }))
    eq(piece(hidden, "SwingTimer", "Ranged").anchor.y, 102)
    eq(piece(hidden, "SwingTimer", "MainHand").anchor.y, 86)
    eq(piece(hidden, "SwingTimer", "OffHand").anchor.y, 70)
    eq(piece(hidden, "Minimap").anchor.y, 126)
    local shown = Plan.Pieces(with({ main = "under", offHand = 0 }))
    eq(piece(shown, "SwingTimer", "Ranged").anchor.y, 118)
    eq(piece(shown, "SwingTimer", "MainHand").anchor.y, 102)
    eq(piece(shown, "SwingTimer", "OffHand").anchor.y, 86)
    eq(piece(shown, "Minimap").anchor.y, 142)
    -- Main bar above: unchanged.
    eq(piece(Plan.Pieces(with({})), "SwingTimer", "Ranged").anchor.y, 24)
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
    for _, o in ipairs({ with(Plan.DEFAULTS), with({ main = "under", map = 60, timers = "bars" }) }) do
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
    for _, m in ipairs({ 60, 70, 80 }) do
        eq(piece(Plan.Pieces(with({ map = m })), "Minimap").settings.HeaderUnderneath, 1, "map " .. m)
    end
    local layout = Plan.Build(baseLayout(e), with(Plan.DEFAULTS), e)
    eq(settingValue(layout.systems[1], e.setting.Minimap.HeaderUnderneath), 1)
    eq(settingValue(layout.systems[1], e.setting.Minimap.Size), 3)
    eq(#layout.systems[1].settings, 2, "Size and HeaderUnderneath")
    -- The header sits inside the map's own frame (Blizzard_Minimap/Camelot/Minimap.lua:68-84),
    -- so the map's spot is not lifted for it.
    eq(Plan.MapY(with(Plan.DEFAULTS)), 44)
end)

test("plan: no HeaderUnderneath enum leaves it out", function()
    local Plan = plan()
    local e = fakeEnums()
    e.setting.Minimap.HeaderUnderneath = nil
    local layout = Plan.Build(baseLayout(e), with(Plan.DEFAULTS), e)
    local map = layout.systems[1]
    eq(#map.settings, 1, "only Size")
    eq(settingValue(map, e.setting.Minimap.Size), 3)
    eq(map.anchorInfo.offsetY, 44)
end)

test("plan: buffs, debuffs, tracker spots", function()
    local Plan = plan()
    local list = Plan.Pieces(with(Plan.DEFAULTS))
    eq(piece(list, "AuraFrame", "BuffFrame").anchor,
        { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -30, y = -292 })
    eq(piece(list, "AuraFrame", "DebuffFrame").anchor,
        { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -30, y = -330 })
    local quest = piece(list, "ObjectiveTracker")
    eq(quest.anchor, { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -30, y = -375 })
    eq(quest.settings, { Height = 0 })
    -- The chat box keeps its spot and size.
    local chat = piece(list, "ChatFrame")
    eq(chat.anchor, { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", x = -30, y = -40 })
    eq(chat.settings, { WidthHundreds = 4, WidthTensAndOnes = 30, HeightHundreds = 2, HeightTensAndOnes = 10 })
end)

---------------------------------------------------------------------------
-- Map size (spec 2026-11-22-controller-layout-measured-sizes.md). The map is
-- 273 by 283 at 100%: 163.8 by 169.8 at 60%, 191.1 by 198.1 at 70%, 218.4 by
-- 226.4 at 80%. Every number below is worked out by hand from those.
---------------------------------------------------------------------------

local MAP_CASES = {
    -- leftX: mapW/2 + 14 + 104. topY: 44 + mapH + 12 + 34. bothY: topY + 34 + 22 + 23.8.
    -- bottomY: 44 + mapH * 0.62 + 50. aboveTop: the both-triggers bar's top with the map at 6.
    { map = 60, stored = 1, leftX = 199.9, topY = 259.8, bothY = 339.6, bottomY = 199.276, aboveTop = 325.4,
      underBothY = 297.6, underBottomY = 224.9 },
    { map = 70, stored = 2, leftX = 213.55, topY = 288.1, bothY = 367.9, bottomY = 216.822, aboveTop = 353.7,
      underBothY = 325.9, underBottomY = 239.05 },
    { map = 80, stored = 3, leftX = 227.2, topY = 316.4, bothY = 396.2, bottomY = 234.368, aboveTop = 382,
      underBothY = 354.2, underBottomY = 253.2 },
}

test("layout: the map option defaults to 80", function()
    local Plan = plan()
    eq(Plan.DEFAULTS.map, 80)
end)

test("layout: BarSpots follow the map's size at 60, 70 and 80 percent", function()
    local Plan = plan()
    for _, m in ipairs(MAP_CASES) do
        local what = "map " .. m.map .. " "
        local s = Plan.BarSpots(with({ map = m.map }))
        near(s.left.x, -m.leftX, what .. "left.x")
        near(s.right.x, m.leftX, what .. "right.x")
        near(s.left.y, 42, what .. "left.y")
        near(s.right.y, 42, what .. "right.y")
        near(s.left.s, 1, what .. "left.s")
        near(s.top.x, 0, what .. "top.x")
        near(s.top.y, m.topY, what .. "top.y")
        near(s.top.s, 1, what .. "top.s")
        near(s.both.x, 0, what .. "both.x")
        near(s.both.y, m.bothY, what .. "both.y")
        near(s.both.s, 0.7, what .. "both.s")
        near(s.bottom.y, m.bottomY, what .. "bottom.y")
        eq(s.bottom.s, 1)
        -- Main bar under the map: the side bars hug the main bar, so the map's width does not move them.
        local u = Plan.BarSpots(with({ map = m.map, main = "under", timers = "above" }))
        near(u.left.x, -220, what .. "under left.x")
        near(u.top.y, 42, what .. "under top.y")
        near(u.both.y, m.underBothY, what .. "under both.y")
        near(u.bottom.y, m.underBottomY, what .. "under bottom.y")
    end
end)

test("layout: the map's y does not depend on the map's size", function()
    local Plan = plan()
    for _, m in ipairs(MAP_CASES) do
        eq(Plan.MapY(with({ map = m.map })), 44)
        eq(Plan.MapY(with({ map = m.map, offHand = 0 })), 60)
        eq(Plan.MapY(with({ map = m.map, timers = "above" })), 6)
        eq(Plan.MapY(with({ map = m.map, timers = "bars" })), 6)
        eq(Plan.MapY(with({ map = m.map, main = "under" })), 126)
        eq(Plan.MapY(with({ map = m.map, main = "under", timers = "bars" })), 90)
    end
end)

test("layout: the timer spots follow the map's size at 60, 70 and 80 percent", function()
    local Plan = plan()
    for _, m in ipairs(MAP_CASES) do
        local what = "map " .. m.map .. " "
        -- Under the map: the same spots at every size.
        local under = Plan.Pieces(with({ map = m.map }))
        eq(piece(under, "SwingTimer", "Ranged").anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 0, y = 24 })
        eq(piece(under, "SwingTimer", "MainHand").anchor.y, 8)
        eq(piece(under, "SwingTimer", "OffHand").anchor.y, -8)
        -- Above the bars: over the both-triggers bar's top, at any spell button size.
        local above = Plan.Pieces(with({ map = m.map, timers = "above", size = 70, fineBoth = 0.85 }))
        near(piece(above, "SwingTimer", "Ranged").anchor.y, m.aboveTop + 40, what .. "above ranged")
        near(piece(above, "SwingTimer", "MainHand").anchor.y, m.aboveTop + 24, what .. "above main hand")
        near(piece(above, "SwingTimer", "OffHand").anchor.y, m.aboveTop + 8, what .. "above off hand")
        eq(piece(above, "SwingTimer", "Ranged").anchor.x, 0)
        -- Under the LT and RT bars: on the side bars' centres.
        local bars = Plan.Pieces(with({ map = m.map, timers = "bars" }))
        near(piece(bars, "SwingTimer", "Ranged").anchor.x, -m.leftX, what .. "bars ranged x")
        near(piece(bars, "SwingTimer", "MainHand").anchor.x, m.leftX, what .. "bars main hand x")
        near(piece(bars, "SwingTimer", "OffHand").anchor.x, m.leftX, what .. "bars off hand x")
        eq(piece(bars, "SwingTimer", "Ranged").anchor.y, 6)
        eq(piece(bars, "SwingTimer", "MainHand").anchor.y, 6)
        eq(piece(bars, "SwingTimer", "OffHand").anchor.y, 22)
    end
end)

test("layout: the template's Minimap entry stores the map's size as (map - 50) / 10", function()
    local Plan = plan()
    local e = fakeEnums()
    for _, m in ipairs(MAP_CASES) do
        local map = piece(Plan.Pieces(with({ map = m.map })), "Minimap")
        eq(map.settings, { Size = m.stored, HeaderUnderneath = 1 })
        eq(map.anchor, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 0, y = 44 })
        local layout = Plan.Build(baseLayout(e), with({ map = m.map }), e)
        eq(settingValue(layout.systems[1], e.setting.Minimap.Size), m.stored)
        eq(layout.systems[1].anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 44 })
    end
end)

test("layout: an unusable map value falls back to 80", function()
    local Plan = plan()
    local at80 = Plan.BarSpots(with({ map = 80 }))
    for _, bad in ipairs({ 100, 50, 65, 0, -80, 60.5, "60", true }) do
        local what = "map " .. tostring(bad)
        local s = Plan.BarSpots(with({ map = bad }))
        near(s.left.x, -227.2, what .. " left.x")
        near(s.top.y, 316.4, what .. " top.y")
        eq(s, at80, what)
        eq(piece(Plan.Pieces(with({ map = bad })), "Minimap").settings.Size, 3, what .. " stored size")
    end
    eq(piece(Plan.Pieces(with({})), "Minimap").settings.Size, 3, "no map value")
    near(Plan.BarSpots(nil).left.x, -227.2, "no options")
end)

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

test("layout: registered, off, with its defaults, a Controller tab and no work while off", function()
    local c, PE = T.new({})
    local mod = PE:GetModule("ctrlLayout")
    check(mod ~= nil, "the feature did not register")
    eq(mod.label, "Controller layout")
    eq(mod.desc, "Map bottom middle, spell bars around it, chat top right.")
    eq(mod.order, 60)
    eq(mod.experimental, true)
    eq(mod.statusWhenOff, true)
    check(not PE:IsModuleEnabled("ctrlLayout"), "the feature is on at first install")
    for k, v in pairs(PE.LayoutPlan.DEFAULTS) do eq(mod.defaults[k], v, "default " .. k) end
    eq(mod.defaults.prev, false)
    eq(mod.defaults.prevs, {})
    eq(mod:status(), "Switching on or off reloads. Your old layout comes back when off.")
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
local RELOAD = "Reload to finish changing the screen layout."
local USING = "Using the Pocket Essentials layout. Move the map, chat or frames in Edit Mode; it is kept."
local ANOTHER = "Another Edit Mode layout is active. Pick Pocket Essentials in Edit Mode, or switch this off and on."
local OFF_TEXT = "Switching on or off reloads. Your old layout comes back when off."

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

-- The stand-in's character (UnitName("player"), GetRealmName()) and its remembered layout.
local KEY = "Tester-Camelot"
local function prev(PE, key)
    local p = opts(PE).prevs
    return type(p) == "table" and p[key or KEY] or nil
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
    eq(ours.systems[1].anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 44 })
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
    eq(ours.systems[1].anchorInfo.offsetY, 44)
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
    eq(values, { [0] = 1, [2] = 3 })
    c:assertClean()
    local c2, PE2 = layoutClient({}, 3, { setup = function(c2) rawset(c2.env.Enum.EditModeMinimapSetting, "HeaderUnderneath", nil) end })
    switchOn(c2, PE2)
    check(PE2:IsModuleEnabled("ctrlLayout"), "the feature did not stay on")
    local map2 = mapEntry(c2)
    eq(#map2.settings, 1, "only Size")
    eq(map2.settings[1].value, 3)
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
    local c2, PE2 = T.new({ gamepadUI = true, saved = db, setup = function(c2) c2.world.layouts = c.world.layouts end })
    check(PE2:IsModuleEnabled("ctrlLayout"), "not on after the login")
    eq(layoutCalls(c2), 0, "a layout call at login")
    eq(reloadReason(PE2), nil)
    eq(statusText(PE2), USING)
    c2:assertClean()
    -- Another layout picked meanwhile: still nothing changed, and the status says so.
    local c3, PE3 = T.new({ gamepadUI = true, saved = db, setup = function(c3)
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
    near(frameState(c, f.left).scale, 1, "left scale (default size 100)")
    placedAt(c, f.right, spots.right, "right")
    placedAt(c, f.top, spots.top, "top")
    placedAt(c, f.bottom, spots.bottom, "bottom")
    eq(frameState(c, f.bottom).scale, 1)
    placedAt(c, f.both, spots.both, "both-triggers bar")
    near(frameState(c, f.both).scale, 0.7, "both-triggers scale")
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
    opts(PE).size = 85 -- scaled, so a scale left behind would show
    switchOn(c, PE)
    c.world.layouts.activeLayout = 1
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(allStates(c), before)
    eq(frameState(c, barFrames(c).left).scale, 1)
    check(statusText(PE):find("Another Edit Mode layout is active", 1, true), "status: " .. tostring(statusText(PE)))
    -- Picked again: placed again.
    c.world.layouts.activeLayout = 4
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    near(frameState(c, barFrames(c).left).scale, 0.85, "placed again")
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
    opts(PE).size = 85
    switchOn(c, PE)
    check(barCalls(c, "SetPoint") >= 5, "the bars were not placed")
    switchOff(c, PE)
    eq(allStates(c), before)
    c:assertClean()
end)

test("layout: off restores the bars even when no layout was changed (ours was already active)", function()
    local c, PE = layoutClient({ saved(NAME) }, 4)
    local before = allStates(c)
    opts(PE).size = 85
    switchOn(c, PE)
    near(frameState(c, barFrames(c).left).scale, 0.85, "placed")
    switchOff(c, PE)
    eq(allStates(c), before)
    c:assertClean()
end)

test("layout: a later login with the feature on places the bars", function()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    local db = rawget(c.env, "PocketEssentialsDB")
    local c2, PE2 = T.new({ gamepadUI = true, saved = db, setup = function(c2) c2.world.layouts = c.world.layouts end })
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

local START_OVER_ASK = "Tap Start over again to replace the Pocket Essentials layout with the template."

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
    local o = optRow(PE, "Template")
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

test("layout: the card has twelve option rows with the spec's labels and choices", function()
    local _, PE = layoutClient({}, 3)
    local list = PE:GetModule("ctrlLayout").options
    eq(#list, 12)
    local labels = {}
    for i, o in ipairs(list) do labels[i] = o.label end
    eq(labels, { "Main bar", "Map size", "Player and target frames", "Spell button size", "Main bar size", "LT and RT bar size",
        "Both-triggers bar size", "Swing timers", "Ranged timer", "Main Hand timer", "Off Hand timer", "Template" })
    local function choiceList(o)
        local out = {}
        for i, ch in ipairs(o.choices) do out[i] = { ch.value, ch.label } end
        return out
    end
    eq(list[1].key, "main")
    eq(choiceList(list[1]), { { "above", "Above the map" }, { "under", "Under the map" } })
    eq(list[2].key, "map")
    eq(choiceList(list[2]), { { 60, "60%" }, { 70, "70%" }, { 80, "80%" } })
    eq(list[3].key, "frames")
    eq(choiceList(list[3]), { { "corner", "Corners" }, { "stacked", "Stacked" }, { "flat", "Side by side" } })
    eq(list[4].key, "size")
    eq({ list[4].number.min, list[4].number.max, list[4].number.step, list[4].number.default, list[4].number.suffix },
        { 70, 100, 5, 100, "%" })
    eq(list[4].help, "Below 100%, a spell that opens its own wheel may open beside its button.")
    for i, key in ipairs({ "fineMain", "fineSide", "fineBoth" }) do
        eq(list[4 + i].key, key)
        eq(choiceList(list[4 + i]), { { 0.85, "Smaller" }, { 1, "Same" }, { 1.15, "Bigger" } })
    end
    eq(list[8].key, "timers")
    eq(choiceList(list[8]), { { "under", "Under the map" }, { "above", "Above the bars" }, { "bars", "Under the LT and RT bars" } })
    for i, key in ipairs({ "ranged", "mainHand", "offHand" }) do
        eq(list[8 + i].key, key)
        eq(choiceList(list[8 + i]), { { 0, "Always" }, { 1, "In combat" }, { 2, "Hidden" } })
    end
    eq(list[12].button, "Start over")
    eq(type(list[12].action), "function")
end)

local MAP_SIZE = 2 -- Enum.EditModeMinimapSetting.Size in the stand-in

test("layout: Map size rewrites the map and the timers in our layout, re-places the bars and asks for a reload", function()
    local c, PE = onClient()
    local before = deepCopy(ours(c))
    eq(settingValue(entryOf(before, SYS.Minimap), MAP_SIZE), 3, "the template's map size")
    choose(c, PE, "map", 60)
    eq(checkSaves(c), 2)
    local after = ours(c)
    local map = entryOf(after, SYS.Minimap)
    eq(settingValue(map, MAP_SIZE), 1)
    eq(map.anchorInfo, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 44 })
    eq(map.isInDefaultPosition, false)
    eq(entryOf(after, SYS.UnitFrame, 8), entryOf(before, SYS.UnitFrame, 8), "the pet frame changed")
    eq(entryOf(after, SYS.ChatFrame), entryOf(before, SYS.ChatFrame), "the chat entry changed")
    local f = barFrames(c)
    placedAt(c, f.left, { x = -199.9, y = 42, s = 1 }, "left")
    placedAt(c, f.right, { x = 199.9, y = 42, s = 1 }, "right")
    placedAt(c, f.top, { x = 0, y = 259.8, s = 1 }, "top")
    placedAt(c, f.both, { x = 0, y = 339.6, s = 0.7 }, "both")
    placedAt(c, f.bottom, { x = 0, y = 199.276, s = 1 }, "bottom")
    eq(reloadReason(PE), RELOAD)
    eq(statusText(PE), USING)
    -- 70%, then back to 80%.
    choose(c, PE, "map", 70)
    eq(checkSaves(c), 3)
    eq(settingValue(entryOf(ours(c), SYS.Minimap), MAP_SIZE), 2)
    placedAt(c, f.left, { x = -213.55, y = 42, s = 1 }, "left at 70")
    choose(c, PE, "map", 80)
    eq(checkSaves(c), 4)
    eq(settingValue(entryOf(ours(c), SYS.Minimap), MAP_SIZE), 3)
    placedAt(c, f.left, { x = -227.2, y = 42, s = 1 }, "left at 80")
    placedAt(c, f.top, { x = 0, y = 316.4, s = 1 }, "top at 80")
    c:assertClean()
end)

test("layout: Map size moves the timers that hang on the bars", function()
    local c, PE = onClient()
    choose(c, PE, "timers", "bars")
    near(entryOf(ours(c), SYS.SwingTimer, SWING.Ranged).anchorInfo.offsetX, -227.2, "ranged x at 80")
    choose(c, PE, "map", 60)
    eq(checkSaves(c), 3)
    local after = ours(c)
    near(entryOf(after, SYS.SwingTimer, SWING.Ranged).anchorInfo.offsetX, -199.9, "ranged x")
    near(entryOf(after, SYS.SwingTimer, SWING.MainHand).anchorInfo.offsetX, 199.9, "main hand x")
    eq(entryOf(after, SYS.Minimap).anchorInfo.offsetY, 6)
    placedAt(c, barFrames(c).left, { x = -199.9, y = 42 + 22, s = 1 }, "left")
    c:assertClean()
end)

test("layout: Map size is refused while Edit Mode is open and put back", function()
    local c, PE = onClient()
    c.world.editMode = true
    choose(c, PE, "map", 60)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(statusText(PE), "Close Edit Mode first.")
    eq(opts(PE).map, 80)
    placedAt(c, barFrames(c).left, { x = -227.2, y = 42, s = 1 }, "left")
    eq(reloadReason(PE), nil)
    c:assertClean()
end)

test("layout: when the Map size rewrite cannot be saved the option and the bars go back", function()
    local c, PE = onClient()
    c.world.layoutCallFails.SaveLayouts = true
    choose(c, PE, "map", 60)
    check(#PE.errors >= 1, "no error logged")
    eq(opts(PE).map, 80)
    placedAt(c, barFrames(c).left, { x = -227.2, y = 42, s = 1 }, "left")
    eq(reloadReason(PE), nil)
end)

test("layout: a saved map value that is not 60, 70 or 80 places the bars as 80", function()
    local c, PE = layoutClient({}, 3)
    opts(PE).map = 100
    switchOn(c, PE)
    eq(settingValue(entryOf(ours(c), SYS.Minimap), MAP_SIZE), 3)
    placedAt(c, barFrames(c).left, { x = -227.2, y = 42, s = 1 }, "left")
    placedAt(c, barFrames(c).top, { x = 0, y = 316.4, s = 1 }, "top")
    c:assertClean()
end)

test("layout: Player and target frames rewrites only the frames in our layout and asks for a reload", function()
    local c, PE = onClient()
    local before = deepCopy(ours(c))
    choose(c, PE, "frames", "flat")
    eq(checkSaves(c), 2)
    local after = ours(c)
    eq(entryOf(after, SYS.UnitFrame, 8).anchorInfo,
        { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = -401, offsetY = 130 })
    eq(entryOf(after, SYS.UnitFrame, 1).anchorInfo.offsetX, -165)
    eq(entryOf(after, SYS.Minimap), entryOf(before, SYS.Minimap), "the map entry changed")
    eq(entryOf(after, SYS.ChatFrame), entryOf(before, SYS.ChatFrame), "the chat entry changed")
    eq(entryOf(after, SYS.SwingTimer, SWING.Ranged), entryOf(before, SYS.SwingTimer, SWING.Ranged))
    eq(reloadReason(PE), RELOAD)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("layout: Spell button size re-places the bars only", function()
    local c, PE = onClient()
    choose(c, PE, "size", 70)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    near(frameState(c, barFrames(c).left).scale, 0.7, "left scale")
    placedAt(c, barFrames(c).left, PE.LayoutPlan.BarSpots({ size = 70 }).left, "left")
    eq(reloadReason(PE), nil)
    c:assertClean()
end)

test("layout: the three bar size rows re-place their bars only", function()
    local c, PE = onClient()
    choose(c, PE, "fineMain", 1.15)
    choose(c, PE, "fineSide", 0.85)
    choose(c, PE, "fineBoth", 0.85)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    local spots = PE.LayoutPlan.BarSpots({ fineMain = 1.15, fineSide = 0.85, fineBoth = 0.85 })
    local f = barFrames(c)
    placedAt(c, f.top, spots.top, "top")
    placedAt(c, f.left, spots.left, "left")
    placedAt(c, f.both, spots.both, "both")
    c:assertClean()
end)

test("layout: Swing timers rewrites the timers and the map and lifts the side bars", function()
    local c, PE = onClient()
    local before = deepCopy(ours(c))
    local spotsBefore = PE.LayoutPlan.BarSpots(PE.LayoutPlan.DEFAULTS)
    choose(c, PE, "timers", "bars")
    eq(checkSaves(c), 2)
    local after = ours(c)
    local sideX = -PE.LayoutPlan.BarSpots({ timers = "bars", size = 100 }).left.x
    near(entryOf(after, SYS.SwingTimer, SWING.Ranged).anchorInfo.offsetX, -sideX, "ranged x")
    eq(entryOf(after, SYS.SwingTimer, SWING.OffHand).anchorInfo.offsetY, 22)
    eq(entryOf(after, SYS.Minimap).anchorInfo.offsetY, 6)
    eq(entryOf(after, SYS.UnitFrame, 8), entryOf(before, SYS.UnitFrame, 8), "the pet frame changed")
    local left = frameState(c, barFrames(c).left)
    near(left.points[1][5] * left.scale, spotsBefore.left.y + 22, "left bar lifted")
    eq(reloadReason(PE), RELOAD)
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

test("layout: Off Hand timer rewrites all three timers and the map (the stack depends on it)", function()
    local c, PE = onClient()
    choose(c, PE, "offHand", 0)
    eq(checkSaves(c), 2)
    local after = ours(c)
    eq(entryOf(after, SYS.Minimap).anchorInfo.offsetY, 60)
    eq(entryOf(after, SYS.SwingTimer, SWING.Ranged).anchorInfo.offsetY, 40)
    eq(entryOf(after, SYS.SwingTimer, SWING.OffHand).anchorInfo.offsetY, 8)
    c:assertClean()
end)

test("layout: Main bar under the map moves the map up and the main bar down", function()
    local c, PE = onClient()
    choose(c, PE, "main", "under")
    eq(checkSaves(c), 2)
    eq(entryOf(ours(c), SYS.Minimap).anchorInfo.offsetY, 126)
    placedAt(c, barFrames(c).top, { x = 0, y = 8 + 68 / 2, s = 1 }, "top")
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
end)

test("layout: an option that changes the layout is refused while Edit Mode is open and put back", function()
    local c, PE = onClient()
    c.world.editMode = true
    choose(c, PE, "frames", "flat")
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(statusText(PE), "Close Edit Mode first.")
    eq(opts(PE).frames, "corner")
    choose(c, PE, "timers", "bars")
    eq(opts(PE).timers, "under")
    local left = frameState(c, barFrames(c).left)
    near(left.points[1][5] * left.scale, PE.LayoutPlan.BarSpots({}).left.y, "the bars moved anyway")
    -- Edit Mode closed: the next change goes through and the refusal goes away.
    c.world.editMode = false
    choose(c, PE, "frames", "flat")
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 2)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("layout: option changes in a fight are written together once it ends", function()
    local c, PE = onClient()
    c:enterCombat()
    choose(c, PE, "frames", "flat")
    choose(c, PE, "ranged", 2)
    choose(c, PE, "size", 70)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1, "a save in combat")
    c:leaveCombat()
    c:advance(0.1)
    eq(checkSaves(c), 2, "one save for both changes")
    local after = ours(c)
    eq(entryOf(after, SYS.UnitFrame, 8).anchorInfo.offsetX, -401)
    local vis
    for _, s in ipairs(entryOf(after, SYS.SwingTimer, SWING.Ranged).settings) do
        if s.setting == VISIBILITY then vis = s.value end
    end
    eq(vis, 2)
    near(frameState(c, barFrames(c).left).scale, 0.7, "left scale")
    c:assertClean()
end)

test("layout: an option change with our layout deleted writes nothing and keeps the choice", function()
    local c, PE = onClient()
    c.world.layouts = { layouts = {}, activeLayout = 3 }
    choose(c, PE, "frames", "flat")
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(opts(PE).frames, "flat")
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
    eq(entryOf(after, SYS.Minimap).anchorInfo.offsetX, 0)
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
    for _, label in ipairs({ "Main bar", "Map size", "Player and target frames", "Spell button size", "Swing timers", "Off Hand timer", "Template" }) do
        check(texts[label], "no row " .. label)
    end
    check(buttons["Start over"], "no Start over button")
    check(buttons["Side by side"], "no Side by side button")
    c:click(buttons["Side by side"])
    c:advance(0.2)
    eq(opts(PE).frames, "flat")
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
    opts(PE).size = 85
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
    opts(PE).size = 85
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
    c:enterCombat()
    choose(c, PE, "frames", "flat")
    switchOff(c, PE)
    c:leaveCombat()
    c:advance(0.1)
    eq(entryOf(ours(c), SYS.UnitFrame, 8).anchorInfo.offsetX, 40, "written while off")
    switchOn(c, PE)
    eq(entryOf(ours(c), SYS.UnitFrame, 8).anchorInfo.offsetX, -401)
    checkSaves(c)
    c:assertClean()
end)

test("layout: when the rewrite cannot be saved the option and the bars go back", function()
    local c, PE = onClient()
    c.world.layoutCallFails.SaveLayouts = true
    choose(c, PE, "timers", "bars")
    check(#PE.errors >= 1, "no error logged")
    eq(opts(PE).timers, "under")
    local left = frameState(c, barFrames(c).left)
    near(left.points[1][5] * left.scale, PE.LayoutPlan.BarSpots({}).left.y, "the bars stayed lifted")
    eq(reloadReason(PE), nil)
end)

test("layout: an option refused in Edit Mode says so in the status line only, and not once switched off", function()
    local c, PE = onClient()
    local lines = #c.chat
    c.world.editMode = true
    choose(c, PE, "frames", "flat")
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
    local db3, layouts3 = deepCopy(db), deepCopy(c.world.layouts) -- the third login starts from the same state
    local c2, PE2 = T.new({ gamepadUI = false, saved = db, setup = function(c2) c2.world.layouts = c.world.layouts end })
    eq(PE2:GetModuleState("ctrlLayout"), "on")
    check(PE2:IsModuleEnabled("ctrlLayout"), "not running after the login")
    eq(layoutCalls(c2), 0)
    switchOff(c2, PE2)
    eq(c2.world.layouts.activeLayout, 3)
    eq(prev(PE2), nil)
    c2:assertClean()
    -- The same login without the gamepad bar's anchors: nothing placed, nothing fails.
    local c3, PE3 = T.new({ gamepadUI = false, saved = db3, setup = function(c3)
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
-- Each character's own layout to go back to (spec 2026-11-23-controller-layout-0.11.1.md, 2)
---------------------------------------------------------------------------

-- A login of one character: the saved file `file` (shared by every character of the
-- account), the account's saved layouts `list` and this character's active layout.
-- extra.name: the character's name (false: not readable yet); extra.setup as T.new.
local function login(file, list, active, extra)
    extra = extra or {}
    return T.new({ gamepadUI = extra.gamepadUI ~= false, saved = file, setup = function(c)
        if extra.name == false then c.world.playerName = nil elseif extra.name then c.world.playerName = extra.name end
        c.world.layouts = { layouts = deepCopy(list), activeLayout = active }
        if extra.setup then extra.setup(c) end
    end })
end

local function db(c) return rawget(c.env, "PocketEssentialsDB") end

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

-- Character "Tester" switched on from the Gamepad preset: our layout saved at index 4.
local function testerOn()
    local c, PE = layoutClient({}, 3)
    switchOn(c, PE)
    eq(prev(PE), { name = "Gamepad", preset = 2 })
    return c, PE
end

-- Tester switched on, then "Bee" logs in on its own character layout "Mine" (index 5) and
-- is switched over to ours by the login check. Returns Tester's and Bee's clients.
local function testerAndBee()
    local a, PEa = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local b, PEb = login(db(a), list, 5, { name = "Bee" })
    eq(b.world.layouts.activeLayout, 4)
    eq(prev(PEb, "Bee-Camelot"), { name = "Mine", layoutType = 2 })
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
    eq(prev(PE, "Bee-Camelot"), { name = "Mine", layoutType = 2 })
    eq(prev(PE), { name = "Gamepad", preset = 2 }, "Tester's own entry changed")
    eq(reloadReason(PE), RELOAD)
    eq(statusText(PE), USING)
    c:assertClean()
end)

test("switch: On, no entry, no layout of ours yet: saves it and makes it active", function()
    local file = { enabled = { ctrlLayout = true }, options = { ctrlLayout = { prevs = { ["Other-Camelot"] = { preset = 0 } } } } }
    local c, PE = login(file, { saved("Mine", 2) }, 4)
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 1)
    eq(indexOf(c, NAME), 4)
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE), { name = "Mine", layoutType = 2 })
    eq(prev(PE, "Other-Camelot"), { preset = 0 })
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
    eq(prev(PE, "Bee-Camelot"), nil)
    eq(prev(PE), { name = "Gamepad", preset = 2 }, "Tester's own entry changed")
    c:assertClean()
end)

test("switch: On, entry present, another layout active: left alone, status says another", function()
    local a = testerOn()
    local c, PE = login(db(a), a.world.layouts.layouts, 1)
    eq(layoutCalls(c), 0)
    eq(reloadReason(PE), nil)
    eq(statusText(PE), ANOTHER)
    eq(prev(PE), { name = "Gamepad", preset = 2 })
    c:assertClean()
end)

test("switch: Off puts back this character's own and removes its entry", function()
    local _, _, b = testerAndBee()
    local c, PE = login(db(b), b.world.layouts.layouts, 4, { name = "Bee" })
    eq(layoutCalls(c), 0, "a layout call at login")
    switchOff(c, PE)
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(#set, 1)
    eq(set[1].args[1], 5)
    eq(prev(PE, "Bee-Camelot"), nil)
    eq(prev(PE), { name = "Gamepad", preset = 2 }, "Tester's entry changed")
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
end)

test("switch: off on A, B puts back once", function()
    local a, PEa, b = testerAndBee()
    switchOff(a, PEa)
    eq(a.world.layouts.activeLayout, 3)
    eq(prev(PEa), nil)
    -- Bee logs in with the switch off and ours still active on Bee: Bee's own comes back.
    local c, PE = login(db(a), b.world.layouts.layouts, 4, { name = "Bee" })
    check(not PE:IsModuleEnabled("ctrlLayout"), "on after the login")
    local set = c:callsTo("C_EditMode.SetActiveLayout")
    eq(#set, 1)
    eq(set[1].args[1], 5)
    eq(c.world.layouts.activeLayout, 5)
    eq(prev(PE, "Bee-Camelot"), nil)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
    -- The next login on Bee: nothing more.
    local c2, PE2 = login(db(c), c.world.layouts.layouts, 5, { name = "Bee" })
    eq(layoutCalls(c2), 0)
    eq(reloadReason(PE2), nil)
    c2:assertClean()
end)

test("switch: login off with an entry but another layout active only forgets the entry", function()
    local a, PEa, b = testerAndBee()
    switchOff(a, PEa)
    -- Bee picked its own layout in Edit Mode meanwhile.
    local c, PE = login(db(a), b.world.layouts.layouts, 5, { name = "Bee" })
    eq(layoutCalls(c), 0)
    eq(prev(PE, "Bee-Camelot"), nil)
    eq(reloadReason(PE), nil)
    c:assertClean()
end)

test("switch: missing saved layout falls back to Gamepad", function()
    -- Bee deletes "Mine" in Edit Mode, then switches off.
    local _, _, b = testerAndBee()
    local c, PE = login(db(b), { b.world.layouts.layouts[1] }, 4, { name = "Bee" })
    eq(indexOf(c, NAME), 4)
    switchOff(c, PE)
    eq(c.world.layouts.activeLayout, 3)
    eq(prev(PE, "Bee-Camelot"), nil)
    c:assertClean()
    -- The same with the switch turned off on Tester: Bee's login puts back the Gamepad preset.
    local a2, PEa2, b2 = testerAndBee()
    switchOff(a2, PEa2)
    local c2, PE2 = login(db(a2), { b2.world.layouts.layouts[1] }, 4, { name = "Bee" })
    eq(c2.world.layouts.activeLayout, 3)
    eq(prev(PE2, "Bee-Camelot"), nil)
    c2:assertClean()
end)

test("switch: no character key yet does nothing", function()
    local a = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local c, PE = login(db(a), list, 5, { name = false })
    eq(layoutCalls(c), 0, "a layout call without the character's name")
    eq(prev(PE, "Bee-Camelot"), nil)
    eq(prev(PE), { name = "Gamepad", preset = 2 }, "Tester's entry changed")
    -- The game's "Unknown" is not a name either.
    c.world.playerName = "Unknown"
    c:fire("PLAYER_ENTERING_WORLD", false, false)
    eq(layoutCalls(c), 0, "a layout call for the character \"Unknown\"")
    eq(prev(PE, "Unknown-Camelot"), nil)
    -- The name is known at the next PLAYER_ENTERING_WORLD.
    c.world.playerName = "Bee"
    c:fire("PLAYER_ENTERING_WORLD", false, false)
    c:advance(0.1)
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE, "Bee-Camelot"), { name = "Mine", layoutType = 2 })
    c:assertClean()
    -- Off: the same wait, then Bee's own back.
    local file = db(c)
    file.enabled.ctrlLayout = false
    local c2, PE2 = login(file, c.world.layouts.layouts, 4, { name = false })
    eq(layoutCalls(c2), 0)
    c2.world.playerName = "Bee"
    c2:fire("PLAYER_ENTERING_WORLD", false, false)
    eq(c2.world.layouts.activeLayout, 5)
    eq(prev(PE2, "Bee-Camelot"), nil)
    c2:assertClean()
end)

test("switch: waits until the game has given Edit Mode its layouts", function()
    local a = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local c, PE = login(db(a), list, 5, { name = "Bee", setup = function(c) c.world.editModeReady = false end })
    eq(layoutCalls(c), 0, "a layout call before Edit Mode had its layouts")
    c.world.editModeReady = true
    c:fire("EDIT_MODE_LAYOUTS_UPDATED")
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE, "Bee-Camelot"), { name = "Mine", layoutType = 2 })
    c:assertClean()
end)

test("switch: login in a fight waits", function()
    local a = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    local c, PE = login(db(a), list, 5, { name = "Bee", setup = function(c) c.world.inCombat = true end })
    eq(layoutCalls(c), 0, "a layout call in a fight")
    c:fire("PLAYER_ENTERING_WORLD", false, false)
    eq(layoutCalls(c), 0, "a layout call in a fight")
    c:leaveCombat()
    c:advance(0.1)
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 1)
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE, "Bee-Camelot"), { name = "Mine", layoutType = 2 })
    c:assertClean()
    -- Off in a fight the same way.
    local file = db(c)
    file.enabled.ctrlLayout = false
    local c2, PE2 = login(file, c.world.layouts.layouts, 4, { name = "Bee", setup = function(c2) c2.world.inCombat = true end })
    eq(layoutCalls(c2), 0, "a layout call in a fight")
    c2:leaveCombat()
    eq(c2.world.layouts.activeLayout, 5)
    eq(prev(PE2, "Bee-Camelot"), nil)
    c2:assertClean()
end)

test("migrate: old prev moved or dropped once", function()
    -- A 0.11.0 saved file: one layout to go back to for the whole account.
    local function oldFile(on)
        return { enabled = { ctrlLayout = on }, options = { ctrlLayout = { prev = { name = "Mine", layoutType = 2 } } } }
    end
    local ours = saved(NAME)
    -- Ours active on the character logging in: it becomes this character's entry.
    local c, PE = login(oldFile(true), { ours, saved("Mine", 2) }, 4)
    eq(layoutCalls(c), 0)
    eq(prev(PE), { name = "Mine", layoutType = 2 })
    eq(opts(PE).prev, false)
    c:assertClean()
    -- Read once: a second character with ours not active gets its own layout remembered, not the old one.
    local c2, PE2 = login(db(c), { ours, saved("Mine", 2), saved("Bees", 2) }, 6, { name = "Bee" })
    eq(c2.world.layouts.activeLayout, 4)
    eq(prev(PE2, "Bee-Camelot"), { name = "Bees", layoutType = 2 })
    eq(prev(PE2), { name = "Mine", layoutType = 2 })
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

test("switch: off state registers no events after the login check", function()
    local base = addonEvents((layoutClient({}, 3)))
    check(not base.PLAYER_ENTERING_WORLD and not base.EDIT_MODE_LAYOUTS_UPDATED, "a fresh install listens for layout events")
    -- Nothing remembered for anyone: nothing to check at all.
    local c0 = login({ enabled = { ctrlLayout = false } }, {}, 3)
    eq(addonEvents(c0), base)
    -- An entry for this character, checked at login, then nothing more.
    local a, PEa, b = testerAndBee()
    local file = deepCopy(db(a))
    switchOff(a, PEa)
    local c = login(db(a), b.world.layouts.layouts, 4, { name = "Bee" })
    eq(c.world.layouts.activeLayout, 5, "the login check did not run")
    eq(addonEvents(c), base)
    c:assertClean()
    -- Waiting for the character's name: listening until it is known, then not.
    file.enabled.ctrlLayout = false
    local c2 = login(file, b.world.layouts.layouts, 4, { name = false })
    check(addonEvents(c2).PLAYER_ENTERING_WORLD, "not waiting for the next PLAYER_ENTERING_WORLD")
    c2.world.playerName = "Bee"
    c2:fire("PLAYER_ENTERING_WORLD", false, false)
    eq(c2.world.layouts.activeLayout, 5)
    eq(addonEvents(c2), base)
    c2:assertClean()
end)


---------------------------------------------------------------------------
-- Review of 0.11.1: automatic switch-on failures, a Gamepad UI reported late, a tap off
-- before the character's name is known
---------------------------------------------------------------------------

test("switch: failed automatic switch-on keeps the switch on and other characters untouched", function()
    local a = testerOn()
    local list = a.world.layouts.layouts
    list[#list + 1] = saved("Mine", 2)
    -- Bee's login: the game refuses to activate our layout.
    local c, PE = login(db(a), list, 5, { name = "Bee", setup = function(c) c.world.layoutCallFails.SetActiveLayout = true end })
    c:advance(0.1)
    check(PE:IsModuleEnabled("ctrlLayout"), "the feature switched itself off")
    eq(PE:IsModuleSavedOn("ctrlLayout"), true)
    eq(prev(PE, "Bee-Camelot"), nil, "an entry was written for a switch that did not happen")
    eq(prev(PE), { name = "Gamepad", preset = 2 }, "Tester's entry changed")
    check(#PE.errors >= 1, "no error logged")
    check(statusText(PE):find("It tries again at the next login.", 1, true), "status: " .. tostring(statusText(PE)))
    eq(reloadReason(PE), nil)
    PE:ClearErrors() -- the saved error log would follow into the next logins
    -- Tester's next login: still on, ours still active there, nothing put back.
    local c2, PE2 = login(db(c), c.world.layouts.layouts, 4)
    check(PE2:IsModuleEnabled("ctrlLayout"), "off on Tester")
    eq(layoutCalls(c2), 0)
    eq(c2.world.layouts.activeLayout, 4)
    c2:assertClean()
    -- Bee's next login, with the game taking the call: switched.
    local c3, PE3 = login(db(c), c.world.layouts.layouts, 5, { name = "Bee" })
    eq(c3.world.layouts.activeLayout, 4)
    eq(prev(PE3, "Bee-Camelot"), { name = "Mine", layoutType = 2 })
    c3:assertClean()
    -- A refusal (five account-wide layouts, ours not saved yet) keeps the switch on too.
    local file = { enabled = { ctrlLayout = true }, options = { ctrlLayout = { prevs = { ["Other-Camelot"] = { preset = 0 } } } } }
    local c4, PE4 = login(file, { saved("A1"), saved("A2"), saved("A3"), saved("A4"), saved("A5"), saved("Mine", 2) }, 9)
    c4:advance(0.1)
    check(PE4:IsModuleEnabled("ctrlLayout"), "the feature switched itself off after the refusal")
    eq(layoutCalls(c4), 0)
    eq(prev(PE4), nil)
    eq(prev(PE4, "Other-Camelot"), { preset = 0 })
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
    local c, PE = login(db(a), list, 5, { name = "Bee", gamepadUI = false, setup = function(c)
        -- The game reports its Gamepad UI once the character enters the world: just before the
        -- addon hears that PLAYER_ENTERING_WORLD (this frame registered for it first).
        local f = c.env.CreateFrame("Frame")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function() c.world.gamepadUI = true end)
    end })
    check(PE:IsModuleEnabled("ctrlLayout"), "not started once the Gamepad UI read on")
    eq(c.world.layouts.activeLayout, 4)
    eq(prev(PE, "Bee-Camelot"), { name = "Mine", layoutType = 2 })
    eq(reloadReason(PE), RELOAD)
    eq(addonEvents(c).EDIT_MODE_LAYOUTS_UPDATED, true, "the feature's own events")
    c:assertClean()
    -- Still off at that PLAYER_ENTERING_WORLD: not started, and only that one look.
    local c2, PE2 = login(file, list, 5, { name = "Bee", gamepadUI = false })
    check(not PE2:IsModuleEnabled("ctrlLayout"), "started without the Gamepad UI")
    eq(layoutCalls(c2), 0)
    check(not addonEvents(c2).PLAYER_ENTERING_WORLD, "still listening after the one look")
    c2.world.gamepadUI = true
    c2:fire("PLAYER_ENTERING_WORLD", false, false)
    check(not PE2:IsModuleEnabled("ctrlLayout"), "a second look")
    c2:assertClean()
end)

test("switch: a tap off before the character's name is known keeps its reload request", function()
    -- Another layout active: nothing to put back, but a tap always asks for the reload.
    local c, PE = testerOn()
    c.world.layouts.activeLayout = 1
    PE:GetModule("ctrlLayout"):CancelReload()
    c.world.playerName = nil
    switchOff(c, PE)
    eq(prev(PE), { name = "Gamepad", preset = 2 }, "forgotten before the name was known")
    eq(reloadReason(PE), nil)
    c.world.playerName = "Tester"
    c:fire("PLAYER_ENTERING_WORLD", false, false)
    eq(prev(PE), nil)
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 0)
    eq(reloadReason(PE), RELOAD)
    c:assertClean()
    -- Ours active: put back, with the reload request.
    local c2, PE2 = testerOn()
    PE2:GetModule("ctrlLayout"):CancelReload()
    c2.world.playerName = nil
    switchOff(c2, PE2)
    eq(c2.world.layouts.activeLayout, 4)
    c2.world.playerName = "Tester"
    c2:fire("PLAYER_ENTERING_WORLD", false, false)
    eq(c2.world.layouts.activeLayout, 3)
    eq(prev(PE2), nil)
    eq(reloadReason(PE2), RELOAD)
    c2:assertClean()
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
    local c = login(db(a), list, 5, { name = "Bee" })
    check(said(c, "now uses the controller layout"), "no chat line after the login switch-on")
    local a2, PEa2, b2 = testerAndBee()
    switchOff(a2, PEa2)
    local c2 = login(db(a2), b2.world.layouts.layouts, 4, { name = "Bee" })
    check(said(c2, "own screen layout is back"), "no chat line after the login switch-off")
    local c3 = login(db(c2), c2.world.layouts.layouts, 5, { name = "Bee" })
    check(not said(c3, "Reload now"), "a login that changed nothing said it")
end)

return { known = KNOWN_FAILURES }
