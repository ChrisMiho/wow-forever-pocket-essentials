-- Rules for "Menu background" (MenuBackground.lua).
-- Sources: docs/superpowers/specs/2026-11-17-0.4.0-handheld-batch.md, section
-- "2. Menu background" (rules 1-10 and the debug-log lines); MenuBackground.lua's
-- header. Each test names its source in a comment. Fresh client and addon per test.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local FILE = "MenuBackground.lua"
local FILL = { 0.05, 0.05, 0.05, 0.95 }
local EDGE = { 0.52, 0.52, 0.57, 1 }

-- A client with the debug log on before the feature is switched on, so the
-- switch-on lines are kept. opts.off leaves the feature off.
local function start(opts)
    opts = opts or {}
    local c, PE = T.new({ setup = opts.setup })
    PE:SetDebug(true)
    if not opts.off then PE:SetModuleEnabled("menuBg", true) end
    c:advance(0.1)
    return c, PE
end

-- The stored debug lines for this feature that contain `text` (plain match).
local function debugLines(c, text)
    local out = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        if line:find(" menuBg: ", 1, true) and line:find(text, 1, true) then out[#out + 1] = line end
    end
    return out
end

local function sameColour(a, b)
    if type(a) ~= "table" then return false end
    for i = 1, 4 do
        if math.abs((a[i] or -1) - b[i]) > 1e-9 then return false end
    end
    return true
end

local function textureWith(c, rec, colour)
    for _, r in ipairs(rec.regions) do
        local st = c._state(r)
        if st.type == "Texture" and sameColour(st.color, colour) then return st end
    end
    return nil
end

-- Every frame the feature's file ever made.
local function made(c)
    local out = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == FILE then out[#out + 1] = rec end
    end
    return out
end

-- The feature's frames that are on screen and carry the dark fill.
local function panels(c)
    local out = {}
    for _, rec in ipairs(made(c)) do
        if rec.frame:IsVisible() and textureWith(c, rec, FILL) then out[#out + 1] = rec end
    end
    return out
end

-- The panel pinned to `menu`, or nil.
local function panelOn(c, menu)
    for _, rec in ipairs(panels(c)) do
        if select(2, rec.frame:GetPoint(1)) == menu then return rec end
    end
    return nil
end

local function errorsOf(PE, key)
    local out = {}
    for _, e in ipairs(PE.errors) do
        if e.module == key then out[#out + 1] = e end
    end
    return out
end

-- Calls the addon made on the game's menu frame (the stand-in logs every
-- Set*, Clear*, Hook*, Show and Hide on it under "Menu:").
local function menuWrites(c)
    local out = {}
    for _, call in ipairs(c.calls) do
        if call.name:sub(1, 5) == "Menu:" then out[#out + 1] = call.name end
    end
    return out
end

---------------------------------------------------------------------------
-- Off
---------------------------------------------------------------------------

-- Spec "With the switch off: nothing is added and nothing runs"; CLAUDE.md "Features default off".
test("menu background: off by default, a menu gets no panel and nothing is registered", function()
    local c, PE = start({ off = true })
    check(PE:GetModule("menuBg") ~= nil, "the feature did not register")
    check(not PE:IsModuleEnabled("menuBg"), "the feature is on at first install")
    local menu = c:openMenu()
    c:advance(1)
    eq(#c:callsTo("EventRegistry.RegisterCallback"), 0)
    eq(#panels(c), 0)
    eq(#made(c), 0, "a frame was made with the feature off")
    c:closeMenu(menu)
    c:openQuestMenu()
    c:advance(1)
    eq(#panels(c), 0)
    eq(#debugLines(c, ""), 0)
    c:assertClean()
end)

-- Spec "What the player sees": name and text under it (the shorter line from spec 2026-11-20-0.9.0-ui-redesign).
test("menu background: the switch has the spec's name and text", function()
    local _, PE = start({ off = true })
    local mod = PE:GetModule("menuBg")
    eq(mod.label, "Menu background")
    eq(mod.desc, "A dark panel behind pop-up menus, so they are easy to read.")
end)

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

-- Spec rules 1, 2 and 4.
test("menu background: an opened menu gets one dark panel pinned to it", function()
    local c = start()
    eq(#c:callsTo("EventRegistry.RegisterCallback"), 3)
    local menu = c:openMenu({ w = 200, h = 120, x = 300, y = -200 })
    local list = panels(c)
    eq(#list, 1)
    local p = list[1]
    eq(p.frame:GetLeft(), menu:GetLeft() - 6)
    eq(p.frame:GetRight(), menu:GetRight() + 6)
    eq(p.frame:GetTop(), menu:GetTop() + 3)
    eq(p.frame:GetBottom(), menu:GetBottom() - 3)
    check(textureWith(c, p, FILL), "no fill texture of 0.05, 0.05, 0.05, 0.95")
    check(textureWith(c, p, EDGE), "no edge texture of 0.52, 0.52, 0.57")
    eq(p.mouse, false, "the panel takes taps")
    eq(p.parent, nil, "the panel has a parent")
    eq(p.name, nil, "the panel has a global name")
    eq(#debugLines(c, "panel shown (announcement), menu 200 x 120, layer FULLSCREEN_DIALOG level 503, panels in use 1"), 1)
    c:assertClean()
end)

-- Spec rule 3.
test("menu background: the panel sits one level under the menu in the menu's layer", function()
    local c = start()
    local menu = c:openMenu({ strata = "FULLSCREEN_DIALOG", level = 503 })
    local p = panelOn(c, menu)
    check(p, "no panel on the menu")
    eq(p.strata, "FULLSCREEN_DIALOG")
    eq(p.level, 502)
    c:closeMenu(menu)

    local low = c:openMenu({ strata = "TOOLTIP", level = 0 })
    local p2 = panelOn(c, low)
    check(p2, "no panel on the second menu")
    eq(p2.strata, "TOOLTIP")
    eq(p2.level, 0)
    c:assertClean()
end)

-- Spec rule 2: "always the menu's size even if the menu changes size while open".
test("menu background: the panel follows the menu when it changes size", function()
    local c = start()
    local menu = c:openMenu({ w = 200, h = 120 })
    local p = panelOn(c, menu)
    eq(p.frame:GetWidth(), 212)
    eq(p.frame:GetHeight(), 126)
    menu:SetSize(300, 200)
    eq(p.frame:GetWidth(), 312)
    eq(p.frame:GetHeight(), 206)
    c:assertClean()
end)

-- Spec "When the menu closes, the panel goes away with it"; debug lines (hidden) / (closed).
test("menu background: closing the menu hides the panel", function()
    local c = start()
    local menu = c:openMenu()
    eq(#panels(c), 1)
    c:closeMenu(menu)
    eq(#panels(c), 0)
    eq(#debugLines(c, "panel hidden (closed)"), 1)

    local m2 = c:openMenu()
    eq(#panels(c), 1)
    c:closeMenu(m2, { noClose = true })       -- only the hide announcement
    eq(#panels(c), 0)
    eq(#debugLines(c, "panel hidden (hidden)"), 1)

    local m3 = c:openMenu()
    eq(#panels(c), 1)
    c:closeMenu(m3, { noHide = true })        -- only the close announcement
    eq(#panels(c), 0)
    eq(#debugLines(c, "panel hidden (closed)"), 2)
    c:assertClean()
end)

-- Spec "A side menu that opens from a menu entry gets its own panel".
test("menu background: a side menu gets its own panel, and closing it leaves the first", function()
    local c = start()
    local root = c:openMenu({ x = 100, y = -100 })
    local side = c:openMenu({ x = 320, y = -120, level = 504, root = false })
    eq(#panels(c), 2)
    check(panelOn(c, root), "no panel on the first menu")
    check(panelOn(c, side), "no panel on the side menu")
    eq(panelOn(c, side).level, 503)
    c:closeMenu(side)
    eq(#panels(c), 1)
    check(panelOn(c, root), "the first menu lost its panel")
    c:assertClean()
end)

-- Spec rule 10.
test("menu background: panels are reused, never more than six", function()
    local c = start()
    for _ = 1, 10 do
        local menu = c:openMenu()
        eq(#panels(c), 1)
        c:closeMenu(menu)
        eq(#panels(c), 0)
    end
    eq(#made(c), 1, "a closed menu's panel was not reused")

    for i = 1, 7 do c:openMenu({ x = 20 * i, y = -20 * i, root = (i == 1) }) end
    eq(#panels(c), 6)
    eq(#made(c), 6)
    eq(#debugLines(c, "no room (6 panels in use)"), 1)
    c:assertClean()
end)

-- Plan 3.3 item 7 (Sweep); spec debug line "(menu gone)".
test("menu background: a menu that closed without telling is tidied at the next menu", function()
    local c = start()
    local m1 = c:openMenu({ x = 100, y = -100 })
    c:closeMenu(m1, { noClose = true, noHide = true })
    eq(#panels(c), 1, "nothing told the addon, so the panel is still there")
    local m2 = c:openMenu({ x = 400, y = -100 })
    eq(#panels(c), 1)
    check(panelOn(c, m2), "the panel is not on the new menu")
    eq(#debugLines(c, "panel hidden (menu gone)"), 1)
    c:assertClean()
end)

-- The menu frames are pooled: the same frame comes back at another level.
test("menu background: a menu frame shown again while it has a panel keeps one panel at the new level", function()
    local c = start()
    local menu = c:openMenu({ level = 503 })
    c._state(menu).level = 510
    c:triggerRegistry("MenuProxy.OnShow", menu)
    eq(#panels(c), 1)
    eq(panelOn(c, menu).level, 509)
    eq(#debugLines(c, "panel shown"), 1)
    c:assertClean()
end)

-- Spec rule 9.
test("menu background: switching off hides every panel and stops listening", function()
    local c, PE = start()
    c:openMenu({ x = 100, y = -100 })
    c:openMenu({ x = 320, y = -100, root = false })
    eq(#panels(c), 2)
    PE:SetModuleEnabled("menuBg", false)
    eq(#panels(c), 0)
    eq(#c:callsTo("EventRegistry.UnregisterCallback"), 3)
    eq(c:registryCount("MenuProxy.OnShow"), 0)
    eq(c:registryCount("MenuProxy.OnHide"), 0)
    eq(c:registryCount("MenuProxy.OnClose"), 0)
    eq(#debugLines(c, "panel hidden (switched off)"), 2)
    c:openMenu({ x = 500, y = -100 })
    c:openQuestMenu()
    c:advance(1)
    eq(#panels(c), 0)

    PE:SetModuleEnabled("menuBg", true)
    eq(c:registryCount("MenuProxy.OnShow"), 1)
    eq(c:registryCount("MenuProxy.OnHide"), 1)
    eq(c:registryCount("MenuProxy.OnClose"), 1)
    local menu = c:openMenu({ x = 100, y = -300 })
    eq(#panels(c), 1)
    check(panelOn(c, menu), "no panel after switching on again")
    c:assertClean()
end)

-- Spec rule 5 and "Things that must be avoided".
test("menu background: nothing is written to or hooked on the game's menu frame", function()
    local c = start()
    local menu = c:openMenu()
    local side = c:openMenu({ x = 400, y = -100, root = false })
    c:closeMenu(side)
    c:closeMenu(menu)
    c:openQuestMenu()
    c:advance(1)
    eq(menuWrites(c), {})
    for _, m in ipairs({ menu, side }) do
        local st = c._state(m)
        eq(st.parent, nil)
        eq(#st.children, 0)
        eq(#st.regions, 0)
        eq(next(st.scripts), nil)
        eq(next(st.hooks), nil)
        for k in pairs(m) do error("the addon wrote the field " .. tostring(k) .. " on the menu frame") end
    end
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The fallback (the quest menu)
---------------------------------------------------------------------------

-- Spec debug line "panel shown (quest hook)"; plan 3.3 items 9 and 10.
test("menu background: without the game's announcement the quest menu still gets a panel", function()
    local c = start({ setup = function(c) c.world.questMenu = { silent = true } end })
    local menu = c:openQuestMenu()
    eq(#panels(c), 1)
    check(panelOn(c, menu), "the panel is not on the quest menu")
    eq(#debugLines(c, "panel shown (quest hook)"), 1)
    eq(#debugLines(c, "panel shown (announcement)"), 0)

    c:closeMenu(menu, { noClose = true, noHide = true })
    c:advance(1)
    eq(#panels(c), 0)
    eq(#debugLines(c, "panel hidden (menu gone)"), 1)
    local before = c.stats.addonTimers
    c:advance(5)
    eq(c.stats.addonTimers, before, "a timer of ours still runs with no panel on screen")
    c:assertClean()
end)

-- "Nothing ticks while its feature is off": the watch stops with the switch.
test("menu background: the fallback's watch stops when the feature is switched off", function()
    local c, PE = start({ setup = function(c) c.world.questMenu = { silent = true } end })
    c:openQuestMenu()
    c:advance(1)
    eq(#panels(c), 1)
    PE:SetModuleEnabled("menuBg", false)
    eq(#panels(c), 0)
    c:advance(1)                       -- the one timer already queued is let go
    local before = c.stats.addonTimers
    c:advance(5)
    eq(c.stats.addonTimers, before)
    c:openQuestMenu()
    c:advance(1)
    eq(#panels(c), 0, "the hook did something with the feature off")
    eq(#debugLines(c, "(quest hook)"), 1)
    c:assertClean()
end)

-- Spec debug line "quest menu opened, panel already there": first time only per switch-on.
test("menu background: with both ways working the quest menu gets exactly one panel", function()
    local c = start()
    for _ = 1, 3 do
        local menu = c:openQuestMenu()
        eq(#panels(c), 1)
        check(panelOn(c, menu), "the panel is not on the quest menu")
        c:closeMenu(menu)
        eq(#panels(c), 0)
    end
    eq(#debugLines(c, "panel shown (announcement)"), 3)
    eq(#debugLines(c, "panel shown (quest hook)"), 0)
    eq(#debugLines(c, "quest menu opened, panel already there"), 1)
    local before = c.stats.addonTimers
    c:advance(5)
    eq(c.stats.addonTimers, before, "the main path started a timer")
    c:assertClean()
end)

-- Spec debug line "quest hook ran but no open menu was found".
test("menu background: the quest hook says so when it finds no open menu", function()
    local c = start({ setup = function(c) c.world.questMenu = { silent = true, root = false } end })
    c:openQuestMenu()
    eq(#panels(c), 0)
    eq(#debugLines(c, "quest hook ran but no open menu was found"), 1)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Missing pieces
---------------------------------------------------------------------------

-- Spec debug line "listening: ...".
test("menu background: the log lists which pieces the client has", function()
    local c = start()
    eq(#debugLines(c, "listening: shown yes, hidden yes, closed yes, quest hook yes, manager yes"), 1)
    eq(#debugLines(c, "cannot listen"), 0)

    local c2 = start({ setup = function(c) rawset(c.env, "EventRegistry", nil) end })
    eq(#debugLines(c2, "listening: shown no, hidden no, closed no, quest hook yes, manager yes"), 1)
    eq(#debugLines(c2, "cannot listen"), 0)
    local menu = c2:openQuestMenu()
    check(panelOn(c2, menu), "the quest menu got no panel through the hook")
    c2:assertClean()
end)

-- Spec rule 7.
test("menu background: a client without the menu announcements does nothing and says so once", function()
    local c, PE = start({ setup = function(c)
        rawset(c.env, "EventRegistry", nil)
        rawset(c.env, "QuestMapLogTitleButton_CreateContextMenu", nil)
    end })
    check(PE:IsModuleEnabled("menuBg"), "the feature did not switch on")
    eq(PE:GetModuleState("menuBg"), "on")
    eq(#PE.errors, 0)
    eq(#debugLines(c, "cannot listen for menus on this client; doing nothing"), 1)
    c:openMenu()
    c:advance(1)
    eq(#panels(c), 0)
    PE:SetModuleEnabled("menuBg", false)
    eq(#c:callsTo("EventRegistry.UnregisterCallback"), 0)
    c:assertClean()
end)

-- Spec debug line 'game background art "common-dropdown-bg": ...'.
test("menu background: the log says whether the game's own background art exists", function()
    local c = start()
    eq(#debugLines(c, 'game background art "common-dropdown-bg": missing'), 1)

    local c2 = start({ setup = function(c) c.world.menuArt = true end })
    eq(#debugLines(c2, 'game background art "common-dropdown-bg": present'), 1)

    local c3 = start({ setup = function(c) rawset(c.env, "C_Texture", nil) end })
    eq(#debugLines(c3, 'game background art "common-dropdown-bg": cannot tell'), 1)
    check(panelOn(c3, c3:openMenu()), "no panel without C_Texture")
    c3:assertClean()
end)

-- Spec debug line "menu skipped: forbidden".
test("menu background: a forbidden menu frame is left alone", function()
    local c = start()
    c:openMenu({ forbidden = true })
    eq(#panels(c), 0)
    eq(#made(c), 0)
    eq(#debugLines(c, "menu skipped: forbidden"), 1)
    eq(menuWrites(c), {})
    c:assertClean()
end)

-- Something that is not a frame at all (a later patch could change what the announcement carries).
test("menu background: an announcement that carries no frame is ignored", function()
    local c = start()
    c:triggerRegistry("MenuProxy.OnShow", nil)
    c:triggerRegistry("MenuProxy.OnShow", "text")
    c:triggerRegistry("MenuProxy.OnShow", {})
    c:triggerRegistry("MenuProxy.OnHide", nil)
    c:triggerRegistry("MenuProxy.OnClose", {}, 1)
    eq(#panels(c), 0)
    c:assertClean()
end)

-- CLAUDE.md "Event handlers and callbacks go through PE:Safe or PE:Wrap".
test("menu background: an error in our code never reaches the game", function()
    local c, PE = start()
    local bad = c:openMenu({ breakStrata = true })
    eq(#panels(c), 0)
    eq(#errorsOf(PE, "menuBg"), 1)
    eq(#c.errors, 0, "the error reached the game")
    c:closeMenu(bad)
    local menu = c:openMenu({ x = 400, y = -100 })
    eq(#panels(c), 1)
    check(panelOn(c, menu), "the next menu got no panel")
    eq(#errorsOf(PE, "menuBg"), 1)
    eq(#c.errors, 0)
end)

-- Spec rule 8.
test("menu background: works the same during a fight", function()
    local c, PE = start()
    c:enterCombat()
    local menu = c:openMenu()
    eq(#panels(c), 1)
    check(panelOn(c, menu), "no panel in a fight")
    eq(#c.blocked, 0)
    c:closeMenu(menu)
    eq(#panels(c), 0)
    local quest = c:openQuestMenu()
    check(panelOn(c, quest), "no panel on the quest menu in a fight")
    c:leaveCombat()
    c:advance(1)
    eq(#panels(c), 1, "something waited for the end of the fight")
    eq(#c.blocked, 0)
    c:assertClean()
end)

-- Spec "To keep the log short": 20 lines, then a count at switch-off.
test("menu background: after twenty panel lines only a count is kept", function()
    local c, PE = start()
    for _ = 1, 25 do c:closeMenu(c:openMenu()) end
    eq(#debugLines(c, "panel shown"), 20)
    PE:SetModuleEnabled("menuBg", false)
    eq(#debugLines(c, "25 menus got a panel since switch-on"), 1)

    PE:SetModuleEnabled("menuBg", true)
    c:closeMenu(c:openMenu())
    eq(#debugLines(c, "panel shown"), 21)
    PE:SetModuleEnabled("menuBg", false)
    eq(#debugLines(c, "menus got a panel since switch-on"), 1)
    c:assertClean()
end)

return { known = KNOWN_FAILURES }
