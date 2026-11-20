-- Rules for "Move on screen" (Move.lua) and the round button as its first piece.
-- Source: docs/superpowers/specs/2026-11-17-move-things.md ("What the player
-- sees", "Rules" and "Tests"). Fresh client and addon per test.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local NAV_NAME = "PocketEssentialsNavButton"
local EPS = 1e-6

local function near(a, b, msg)
    if type(a) ~= "number" or type(b) ~= "number" or math.abs(a - b) > 1e-4 then
        error((msg and (msg .. ": ") or "") .. "expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

local function movePanel(c) return rawget(c.env, "PocketEssentialsMovePanel") end
local function settingsPanel(c) return rawget(c.env, "PocketEssentialsSettingsPanel") end
local function nav(c) return rawget(c.env, NAV_NAME) end

local function walk(c, w, fn, seen)
    seen = seen or {}
    if seen[w] then return end
    seen[w] = true
    fn(w)
    local st = c._state(w)
    for _, ch in ipairs(st.children) do walk(c, ch, fn, seen) end
    if st.scrollChild then walk(c, st.scrollChild, fn, seen) end
end

local function shownButtons(c, top, label)
    local out = {}
    walk(c, top, function(w)
        if c._state(w).type == "Button" and w:IsVisible() and (label == nil or T.labelOf(w) == label) then
            out[#out + 1] = w
        end
    end)
    return out
end

local function button(c, label)
    local list = shownButtons(c, movePanel(c), label)
    check(#list == 1, "expected one shown button '" .. label .. "' in the Move on screen panel, found " .. #list)
    return list[1]
end

local function debugLines(c, key)
    local out = {}
    local prefix = " " .. key .. ": "
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        local at = line:find(prefix, 1, true)
        if at and at <= 14 then out[#out + 1] = line:sub(at + #prefix) end
    end
    return out
end

-- The round button's anchor: point, x, y (UI units).
local function hubPoint(PE)
    local point, rel, relPoint, x, y = PE.Hub.button:GetPoint(1)
    return point, x, y, rel, relPoint
end

-- Where the hub sits with no offset at the LEFT preset (Hub.lua: margin 10 pixels).
local function baseLeft(PE) return PE.UI:Px(10), 0 end

local function savedHub(PE)
    local moved = PE.db.ui.moved
    return moved and moved.hub
end

local function openMove(c, PE)
    PE.Move:Open()
    c:advance(0.1)
    check(movePanel(c) and movePanel(c):IsShown(), "the Move on screen panel did not open")
end

-- A press of one of the panel's buttons by touch, held for `seconds` (0: a tap).
local function touchHold(c, btn, seconds)
    c:script(btn, "OnMouseDown", "LeftButton")
    if seconds and seconds > 0 then c:advance(seconds) end
    c:script(btn, "OnMouseUp", "LeftButton")
    c:script(btn, "OnClick", "LeftButton", false)
end

local function dpadTo(c, panel, target)
    local n = 0
    while panel.peNavFocus ~= target and n < 40 do
        c:script(nav(c), "OnClick", "RIGHT", true)
        c:script(nav(c), "OnClick", "RIGHT", false)
        n = n + 1
    end
    check(panel.peNavFocus == target, "the d-pad never reached " .. T.labelOf(target))
end

local function rectOf(c, w)
    local l, r, t, b = c._rect(w)
    return { l = l, r = r, t = t, b = b }
end

local function overlaps(a, b)
    return a.l < b.r - EPS and b.l < a.r - EPS and a.b < b.t - EPS and b.b < a.t - EPS
end

local function outlineBox(c)
    local found
    for _, rec in ipairs(c:frames()) do
        if rec.name == "PocketEssentialsMoveOutline" then found = rec.frame end
    end
    return found
end

---------------------------------------------------------------------------
-- Saved offsets
---------------------------------------------------------------------------

test("move: with no saved offset the round button sits exactly where 0.1.0 put it", function()
    local c, PE = T.new({})
    local point, x, y = hubPoint(PE)
    local bx, by = baseLeft(PE)
    eq(point, "LEFT")
    near(x, bx); near(y, by)
    eq(type(PE.db.ui.moved), "table", "db.ui.moved is not a table")
    eq({ PE.Move:GetOffset("hub") }, { 0, 0 })
    c:assertClean("no offset")
end)

test("move: saved settings from 0.1.0 (no moved table) load unchanged", function()
    local c, PE = T.new({ saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "RIGHT", folded = {} }, errors = {} } })
    eq(PE.db.ui.hubPos, "RIGHT")
    eq(PE.db.ui.moved, {})
    local point, x = hubPoint(PE)
    eq(point, "RIGHT"); near(x, -PE.UI:Px(10))
end)

test("move: a saved offset moves the round button by that many pixels from its preset", function()
    local c, PE = T.new({ saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "LEFT", moved = { hub = { x = 30, y = -20 } } }, errors = {} } })
    local point, x, y = hubPoint(PE)
    local bx, by = baseLeft(PE)
    eq(point, "LEFT")
    near(x, bx + PE.UI:Px(30)); near(y, by + PE.UI:Px(-20))
    local dx, dy = PE.Move:GetOffset("hub")
    near(dx, PE.UI:Px(30)); near(dy, PE.UI:Px(-20))
    c:assertClean("saved offset")
end)

test("move: a bad saved value reads as 0, 0; the range is limited to -2000..2000", function()
    for _, bad in ipairs({ "yes", 5, true, { x = "a", y = 1 }, { x = 1 }, { x = 0 / 0, y = 0 }, { x = math.huge, y = 0 } }) do
        local c, PE = T.new({ saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "LEFT", moved = { hub = bad } }, errors = {} } })
        eq({ PE.Move:GetOffset("hub") }, { 0, 0 }, "bad value " .. T.show(bad))
        local _, x, y = hubPoint(PE)
        near(x, PE.UI:Px(10)); near(y, 0)
        c:assertClean("bad value")
    end
    for _, bad in ipairs({ "yes", 7 }) do
        local c, PE = T.new({ saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "LEFT", moved = bad }, errors = {} } })
        eq(PE.db.ui.moved, {}, "a damaged moved table was not replaced")
        eq({ PE.Move:GetOffset("hub") }, { 0, 0 })
    end
    local c, PE = T.new({ saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "LEFT", moved = { hub = { x = 5000, y = -9000 } } }, errors = {} } })
    local dx, dy = PE.Move:GetOffset("hub")
    near(dx, PE.UI:Px(2000)); near(dy, PE.UI:Px(-2000))
    eq({ PE.Move:GetOffset("nothing") }, { 0, 0 })
end)

test("move: positions survive a reload (the saved table)", function()
    local c, PE = T.new({})
    openMove(c, PE)
    c:click(button(c, "Right"))
    c:click(button(c, "Up"))
    eq(savedHub(PE), { x = 2, y = 2 })
    local db = rawget(c.env, "PocketEssentialsDB")
    local c2, PE2 = T.new({ saved = db })
    local _, x, y = hubPoint(PE2)
    near(x, PE2.UI:Px(10) + PE2.UI:Px(2)); near(y, PE2.UI:Px(2))
end)

---------------------------------------------------------------------------
-- Opening and the list of pieces
---------------------------------------------------------------------------

-- The two Open buttons of the General tab, top to bottom: Move things on screen, then Setup guide.
local function generalOpenButtons(c, PE)
    PE:OpenSettings("general")
    c:advance(0.2)
    local open = shownButtons(c, settingsPanel(c), "Open")
    table.sort(open, function(a, b) return select(2, a:GetCenter()) > select(2, b:GetCenter()) end)
    return open
end

test("move: the General tab's Move things on screen row opens the panel and closes the settings", function()
    local c, PE = T.new({})
    local settings = settingsPanel(c)
    local moveBtn = generalOpenButtons(c, PE)
    settings = settingsPanel(c)
    eq(#moveBtn, 2, "the General tab does not have its two Open buttons")
    c:click(moveBtn[1])
    c:advance(0.2)
    check(not settings:IsShown(), "the settings stayed open")
    check(movePanel(c) and movePanel(c):IsShown(), "the Move on screen panel did not open")
    for _, label in ipairs({ "Up", "Down", "Left", "Right", "Reset", "Close", "Round button" }) do
        button(c, label)
    end
    eq(movePanel(c).peTitle:GetText(), "Move on screen")
    check(button(c, "Round button").peSelected, "the round button is not selected")
    c:assertClean("open from settings")
end)

test("move: nothing is built and nothing listens before the panel is first opened", function()
    local c, PE = T.new({})
    check(movePanel(c) == nil, "the panel was built at load")
    check(outlineBox(c) == nil, "the outline box was built at load")
    c.stats.addonOnUpdate = 0
    c:advance(2)
    eq(c.stats.addonOnUpdate, 0)
end)

test("move: the panel lists only the pieces that are available, in order, and selects the first", function()
    local c, PE = T.new({})
    local applied = 0
    PE.Move:Register({ key = "testOff", label = "Hidden piece", order = 1, available = function() return false end,
        apply = function() end, outline = function(box) box:ClearAllPoints(); box:SetPoint("CENTER", c.env.UIParent, "CENTER", 0, 0); box:SetSize(20, 20) end })
    PE.Move:Register({ key = "testOn", label = "Test piece", order = 2, available = function() return true end,
        apply = function() applied = applied + 1 end,
        outline = function(box) box:ClearAllPoints(); box:SetPoint("CENTER", c.env.UIParent, "CENTER", 0, 0); box:SetSize(20, 20) end })
    openMove(c, PE)
    eq(#shownButtons(c, movePanel(c), "Hidden piece"), 0, "an unavailable piece is listed")
    local first, hub = button(c, "Test piece"), button(c, "Round button")
    check(first.peSelected and not hub.peSelected, "the first piece is not the one selected")
    local _, fy = first:GetCenter()
    local _, hy = hub:GetCenter()
    check(fy > hy, "the pieces are not in order")
    c:click(button(c, "Right"))
    eq(applied, 1, "apply() was not called after a move")
    eq(PE.db.ui.moved.testOn, { x = 2, y = 0 })
    eq(PE.db.ui.moved.hub, nil, "the round button moved too")
    c:click(hub)
    check(hub.peSelected and not first.peSelected, "tapping a piece did not select it")
    c:assertClean("list")
end)

test("move: cannot be opened in a fight; it says so in chat", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    c:enterCombat()
    PE.Move:Open()
    c:advance(0.1)
    check(not (movePanel(c) and movePanel(c):IsShown()), "the panel opened in a fight")
    eq(#T.chatLines(c), 1, "no chat line")
    eq(debugLines(c, "move"), { "not opened: in a fight" })
    c:assertClean("fight open")
end)

---------------------------------------------------------------------------
-- Pressing and holding
---------------------------------------------------------------------------

test("move: one press on each arrow moves the selected piece 2 pixels and saves it", function()
    local c, PE = T.new({})
    openMove(c, PE)
    local bx, by = baseLeft(PE)
    c:click(button(c, "Right"))
    eq(savedHub(PE), { x = 2, y = 0 })
    local _, x, y = hubPoint(PE)
    near(x, bx + PE.UI:Px(2)); near(y, by)
    c:click(button(c, "Up"))
    eq(savedHub(PE), { x = 2, y = 2 })
    c:click(button(c, "Down")); c:click(button(c, "Down"))
    eq(savedHub(PE), { x = 2, y = -2 })
    c:click(button(c, "Left"))
    eq(savedHub(PE), { x = 0, y = -2 })
    _, x, y = hubPoint(PE)
    near(x, bx); near(y, by - PE.UI:Px(2))
    c:assertClean("press")
end)

test("move: holding repeats after 0.4 s at 10 a second, grows to 6 pixels after 1.5 s, and release stops it", function()
    local c, PE = T.new({})
    openMove(c, PE)
    local right = button(c, "Right")
    c:script(right, "OnMouseDown", "LeftButton")
    eq(savedHub(PE).x, 2, "the press itself did not nudge")
    c:advance(0.3)
    eq(savedHub(PE).x, 2, "it repeated before 0.4 s")
    c:advance(0.1) -- 0.4 s
    eq(savedHub(PE).x, 4)
    c:advance(1.0) -- 1.4 s: ten more steps of 2 since 0.4 s
    eq(savedHub(PE).x, 4 + 9 * 2 + 2)
    c:advance(0.1) -- 1.5 s: 6 pixels a step from here
    eq(savedHub(PE).x, 24 + 6)
    c:advance(0.5)
    eq(savedHub(PE).x, 30 + 5 * 6)
    c:script(right, "OnMouseUp", "LeftButton")
    c:script(right, "OnClick", "LeftButton", false)
    local stopped = savedHub(PE).x
    c:advance(1)
    eq(savedHub(PE).x, stopped, "it kept moving after release")
    local _, x = hubPoint(PE)
    near(x, PE.UI:Px(10) + PE.UI:Px(stopped), "the piece did not move live")
    c:assertClean("hold")
end)

test("move: a tap nudges once, not twice (mouse down plus the click)", function()
    local c, PE = T.new({})
    openMove(c, PE)
    touchHold(c, button(c, "Up"), 0)
    eq(savedHub(PE), { x = 0, y = 2 })
    c:advance(1)
    eq(savedHub(PE), { x = 0, y = 2 })
end)

test("move: a click with no mouse down before it still nudges once", function()
    local c, PE = T.new({})
    openMove(c, PE)
    c:script(button(c, "Up"), "OnClick", "LeftButton", false)
    eq(savedHub(PE), { x = 0, y = 2 })
end)

test("move: hiding the panel stops a hold, and nothing ticks afterwards", function()
    local c, PE = T.new({})
    openMove(c, PE)
    c:script(button(c, "Right"), "OnMouseDown", "LeftButton")
    c:advance(0.6)
    PE.Move:Close("test")
    local stopped = savedHub(PE).x
    c.stats.addonOnUpdate = 0
    c:advance(2)
    eq(savedHub(PE).x, stopped, "it kept moving after the panel closed")
    eq(c.stats.addonOnUpdate, 0, "something ticks with the panel closed")
    c:assertClean("hide stops")
end)

test("move: the driver has no OnUpdate running while nothing is held", function()
    local c, PE = T.new({})
    openMove(c, PE)
    c.stats.addonOnUpdate = 0
    c:advance(2)
    eq(c.stats.addonOnUpdate, 0, "something ticks with the panel open and nothing held")
    c:script(button(c, "Right"), "OnMouseDown", "LeftButton")
    c:advance(0.5)
    check(c.stats.addonOnUpdate > 0, "the hold has no driver")
    c:script(button(c, "Right"), "OnMouseUp", "LeftButton")
    c.stats.addonOnUpdate = 0
    c:advance(1)
    eq(c.stats.addonOnUpdate, 0, "the driver still ticks after release")
end)

test("move: a fight starting stops the hold and closes the panel; positions are kept", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    openMove(c, PE)
    c:script(button(c, "Right"), "OnMouseDown", "LeftButton")
    c:advance(0.5)
    c:enterCombat()
    check(not movePanel(c):IsShown(), "the panel stayed open in a fight")
    local stopped = savedHub(PE).x
    check(stopped > 2, "the hold did not move before the fight")
    c:advance(1)
    eq(savedHub(PE).x, stopped, "it kept moving in the fight")
    local lines = debugLines(c, "move")
    eq(lines[#lines], "panel closed (fight started)")
    c:advance(1)
    c:leaveCombat()
    check(not movePanel(c):IsShown(), "the panel came back after the fight")
    c:assertClean("fight")
end)

test("move: a hold stops by itself after 8 seconds", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    PE:SetUISetting("hubPos", "TOP")
    openMove(c, PE)
    -- Down from the top: plenty of room for 8 seconds.
    c:script(button(c, "Down"), "OnMouseDown", "LeftButton")
    c:advance(7.9)
    local before = savedHub(PE).y
    c:advance(0.2)
    local at = savedHub(PE).y
    c:advance(2)
    eq(savedHub(PE).y, at, "it kept moving after 8 seconds")
    check(at <= before, "sanity")
    local found = false
    for _, l in ipairs(debugLines(c, "move")) do if l == "hold stopped after 8 s" then found = true end end
    check(found, "no debug line for the 8-second stop")
    c.stats.addonOnUpdate = 0
    c:advance(1)
    eq(c.stats.addonOnUpdate, 0, "the driver still ticks after the 8-second stop")
    c:script(button(c, "Down"), "OnMouseUp", "LeftButton")
    c:assertClean("8 s")
end)

test("move: a step that would leave the screen is not taken", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    openMove(c, PE)
    -- The LEFT preset is 10 pixels from the left edge: five steps of 2 reach it.
    for _ = 1, 8 do c:click(button(c, "Left")) end
    eq(savedHub(PE), { x = -10, y = 0 })
    local l = rectOf(c, PE.Hub.button).l
    check(l >= -EPS, "the round button is off the screen")
    local found = false
    for _, line in ipairs(debugLines(c, "move")) do if line == "stopped at the screen edge" then found = true end end
    check(found, "no debug line at the screen edge")
    -- A hold against the edge stops too.
    c:script(button(c, "Left"), "OnMouseDown", "LeftButton")
    c:advance(1)
    c:script(button(c, "Left"), "OnMouseUp", "LeftButton")
    eq(savedHub(PE), { x = -10, y = 0 })
    c:assertClean("edge")
end)

test("move: Reset puts the piece back on its preset", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    openMove(c, PE)
    c:click(button(c, "Right")); c:click(button(c, "Up"))
    c:click(button(c, "Reset"))
    eq(savedHub(PE), nil)
    local _, x, y = hubPoint(PE)
    near(x, PE.UI:Px(10)); near(y, 0)
    local lines = debugLines(c, "move")
    eq(lines[#lines], "hub reset")
    c:assertClean("reset")
end)

test("move: settings has no Move the round button and no Round button position row", function()
    local c, PE = T.new({ saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "LEFT", moved = { hub = { x = 40, y = 40 } } }, errors = {} } })
    local b = generalOpenButtons(c, PE)
    eq(#shownButtons(c, settingsPanel(c), "Right"), 0, "a position button is still drawn")
    eq(#shownButtons(c, settingsPanel(c), "Move the round button"), 0, "Move the round button is still drawn")
    c:click(b[1])
    c:advance(0.2)
    check(movePanel(c) and movePanel(c):IsShown(), "the Move on screen panel did not open")
    c:assertClean("move the round button")
end)

test("move: Move:Open(key) selects that piece; an unknown key falls back to the first", function()
    local c, PE = T.new({})
    PE.Move:Register({ key = "zzfirst", label = "Aaa piece", order = 1, outline = function(box) box:ClearAllPoints(); box:SetPoint("CENTER", UIParent, "CENTER", 0, 0); box:SetSize(20, 20) end })
    PE.Move:Open("hub")
    c:advance(0.1)
    local outline = rawget(c.env, "PocketEssentialsMoveOutline")
    check(outline and outline:IsShown(), "no outline")
    local l, r = c._rect(outline)
    check(r - l > 30, "the first piece was selected, not the round button")
    PE.Move:Close("test")
    PE.Move:Open("nope")
    c:advance(0.1)
    l, r = c._rect(outline)
    check(r - l <= 30, "an unknown key did not fall back to the first piece")
end)

test("move: Reset also sets the round button back to its left preset", function()
    local c, PE = T.new({ saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "RIGHT", moved = { hub = { x = 4, y = 4 } } }, errors = {} } })
    openMove(c, PE)
    c:click(button(c, "Reset"))
    eq(PE.db.ui.hubPos, "LEFT")
    eq(savedHub(PE), nil)
end)

---------------------------------------------------------------------------
-- The outline box and the panel's corner
---------------------------------------------------------------------------

test("move: the outline box sits over the selected piece and follows it, even while the piece is hidden", function()
    local c, PE = T.new({})
    openMove(c, PE)
    local box = outlineBox(c)
    check(box and box:IsVisible(), "no outline box")
    local function same()
        local a, b = rectOf(c, box), rectOf(c, PE.Hub.button)
        near(a.l, b.l, "left"); near(a.r, b.r, "right"); near(a.t, b.t, "top"); near(a.b, b.b, "bottom")
    end
    same()
    c:click(button(c, "Right")); c:click(button(c, "Down"))
    same()
    PE.Hub.button:Hide()
    c:click(button(c, "Right"))
    same()
    check(box:IsVisible(), "the box went away with the piece hidden")
    check(not c._state(box).mouse, "the outline box takes taps")
    PE.Move:Close("test")
    check(not box:IsVisible(), "the box stays after the panel closed")
    c:assertClean("outline")
end)

test("move: the panel sits bottom right and hops to the bottom left when the box overlaps it", function()
    local c, PE = T.new({})
    local UIParent = c.env.UIParent
    local where = "TOPLEFT"
    PE.Move:Register({ key = "corner", label = "Corner piece", order = 1, available = function() return true end,
        apply = function() end,
        outline = function(box)
            box:ClearAllPoints()
            box:SetPoint(where, UIParent, where, 0, 0)
            box:SetSize(40, 40)
        end })
    openMove(c, PE)
    local panel = movePanel(c)
    local screen = rectOf(c, UIParent)
    local p = rectOf(c, panel)
    check(screen.r - p.r < 40 and p.b - screen.b < 40, "the panel is not in the bottom right corner")
    where = "BOTTOMRIGHT"
    c:click(button(c, "Round button"))
    c:click(button(c, "Corner piece")) -- selecting re-checks the corner
    p = rectOf(c, panel)
    check(p.l - screen.l < 40 and p.b - screen.b < 40, "the panel did not hop to the bottom left")
    check(not overlaps(p, rectOf(c, outlineBox(c))), "the panel still overlaps the box")
    -- Back when the box no longer overlaps the bottom right.
    c:click(button(c, "Round button"))
    p = rectOf(c, panel)
    check(screen.r - p.r < 40, "the panel did not come back to the bottom right")
    c:assertClean("hop")
end)

---------------------------------------------------------------------------
-- Controller
---------------------------------------------------------------------------

test("move: the d-pad reaches every button; A down then up on an arrow nudges once; B closes", function()
    local c, PE = T.new({})
    openMove(c, PE)
    local panel = movePanel(c)
    local seen = {}
    for _ = 1, 12 do
        c:script(nav(c), "OnClick", "RIGHT", true)
        c:script(nav(c), "OnClick", "RIGHT", false)
        if panel.peNavFocus then seen[T.labelOf(panel.peNavFocus)] = true end
    end
    for _, label in ipairs({ "Round button", "Up", "Down", "Left", "Right", "Reset", "Close" }) do
        check(seen[label], "the d-pad never reached " .. label)
    end
    dpadTo(c, panel, button(c, "Right"))
    c:script(nav(c), "OnClick", "A", true)
    eq(savedHub(PE), { x = 2, y = 0 }, "A down did not nudge")
    c:script(nav(c), "OnClick", "A", false)
    eq(savedHub(PE), { x = 2, y = 0 }, "A up nudged again")
    c:advance(1)
    eq(savedHub(PE), { x = 2, y = 0 })
    c:script(nav(c), "OnClick", "B", true)
    c:script(nav(c), "OnClick", "B", false)
    check(not panel:IsShown(), "B did not close the panel")
    c:assertClean("nav")
end)

test("move: holding A on an arrow repeats exactly like a held finger", function()
    local c, PE = T.new({})
    openMove(c, PE)
    local panel = movePanel(c)
    dpadTo(c, panel, button(c, "Up"))
    c:script(nav(c), "OnClick", "A", true)
    c:advance(0.3)
    eq(savedHub(PE).y, 2)
    c:advance(1.2) -- 1.5 s
    eq(savedHub(PE).y, 2 + 11 * 2 + 6) -- steps at 0.4 .. 1.4 s, then one of 6
    -- A repeated "down" while held does not restart or nudge.
    c:script(nav(c), "OnClick", "A", true)
    eq(savedHub(PE).y, 30)
    c:script(nav(c), "OnClick", "A", false)
    local stopped = savedHub(PE).y
    c:advance(1)
    eq(savedHub(PE).y, stopped, "A up did not stop the hold")
    c:assertClean("nav hold")
end)

test("move: moving the highlight away while A is held stops the hold, and the release presses nothing", function()
    local c, PE = T.new({})
    openMove(c, PE)
    local panel = movePanel(c)
    dpadTo(c, panel, button(c, "Right"))
    c:script(nav(c), "OnClick", "A", true)
    c:advance(0.5)
    c:script(nav(c), "OnClick", "RIGHT", true) -- onto Down or Reset
    c:script(nav(c), "OnClick", "RIGHT", false)
    local stopped = savedHub(PE)
    stopped = { x = stopped.x, y = stopped.y }
    c:advance(1)
    eq(savedHub(PE), stopped, "the hold kept going after the highlight moved")
    c:script(nav(c), "OnClick", "A", false)
    eq(savedHub(PE), stopped, "the release pressed the newly highlighted button")
    check(panel:IsShown(), "the release closed the panel")
    c:assertClean("nav lost")
end)

test("move: the debug log has the lines of the spec, one per press, never per repeat", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    openMove(c, PE)
    c:click(button(c, "Right"))
    c:script(button(c, "Up"), "OnMouseDown", "LeftButton")
    c:advance(1)
    c:script(button(c, "Up"), "OnMouseUp", "LeftButton")
    c:click(button(c, "Round button"))
    PE.Move:Close("Close")
    eq(debugLines(c, "move"), {
        "panel opened",
        "hub selected",
        "hub now at 2,0",
        "hub now at 2," .. tostring(2 + 7 * 2),
        "hub selected",
        "panel closed (Close)",
    })
end)

-- Fix round 1: a hold that Move.lua stops on its own must not leave the
-- navigation waiting for a release that never comes.
test("move: after the 8-second stop with no A release, a fresh A press nudges once", function()
    local c, PE = T.new({})
    PE:SetUISetting("hubPos", "TOP")
    openMove(c, PE)
    local panel = movePanel(c)
    dpadTo(c, panel, button(c, "Down"))
    c:script(nav(c), "OnClick", "A", true)
    c:advance(9) -- the release never arrives
    local at = savedHub(PE).y
    c:script(nav(c), "OnClick", "A", true)
    eq(savedHub(PE).y, at - 2, "the next A down was swallowed")
    c:script(nav(c), "OnClick", "A", false)
    eq(savedHub(PE).y, at - 2, "the next A up nudged again")
    c:advance(1)
    eq(savedHub(PE).y, at - 2, "the fresh press kept moving after release")
    check(panel:IsShown(), "the panel closed")
    c:assertClean("after safety stop")
end)

test("move: after a controller hold stops at the screen edge, a fresh A press works", function()
    local c, PE = T.new({})
    openMove(c, PE)
    local panel = movePanel(c)
    dpadTo(c, panel, button(c, "Left"))
    c:script(nav(c), "OnClick", "A", true)
    c:advance(2) -- reaches the edge and stops, A still down
    eq(savedHub(PE), { x = -10, y = 0 })
    -- A late release of that press clicks nothing.
    c:script(nav(c), "OnClick", "A", false)
    eq(savedHub(PE), { x = -10, y = 0 })
    check(panel:IsShown(), "the late release closed the panel")
    dpadTo(c, panel, button(c, "Right"))
    c:script(nav(c), "OnClick", "A", true)
    c:script(nav(c), "OnClick", "A", false)
    eq(savedHub(PE), { x = -8, y = 0 }, "the fresh press did not nudge once")
    c:assertClean("after edge stop")
end)

test("move: a first step refused at the edge leaves no hold behind", function()
    local c, PE = T.new({ saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "LEFT", moved = { hub = { x = -10, y = 0 } } }, errors = {} } })
    openMove(c, PE)
    local left = button(c, "Left")
    c:script(left, "OnMouseDown", "LeftButton")
    c.stats.addonOnUpdate = 0
    c:advance(1)
    eq(c.stats.addonOnUpdate, 0, "the driver runs for a refused press")
    c:script(left, "OnMouseUp", "LeftButton")
    c:script(left, "OnClick", "LeftButton", false)
    eq(savedHub(PE), { x = -10, y = 0 })
    -- The controller: A down on Left is refused; the release and a fresh press behave.
    local panel = movePanel(c)
    dpadTo(c, panel, left)
    c:script(nav(c), "OnClick", "A", true)
    c:script(nav(c), "OnClick", "A", false)
    dpadTo(c, panel, button(c, "Right"))
    c:script(nav(c), "OnClick", "A", true)
    c:script(nav(c), "OnClick", "A", false)
    eq(savedHub(PE), { x = -8, y = 0 })
    c:assertClean("refused first step")
end)

test("move: a piece whose outline fails cannot be moved, with one debug line", function()
    for _, kind in ipairs({ "error", "no position" }) do
        local c, PE = T.new({})
        PE:SetDebug(true)
        local applied = 0
        PE.Move:Register({ key = "broken", label = "Broken piece", order = 1,
            apply = function() applied = applied + 1 end,
            outline = function(box)
                if kind == "error" then error("outline broke") end
                box:ClearAllPoints()
                box:SetSize(20, 20)
            end })
        openMove(c, PE)
        check(button(c, "Broken piece").peSelected, "the broken piece is not selected")
        c:click(button(c, "Right"))
        c:script(button(c, "Up"), "OnMouseDown", "LeftButton")
        c:advance(1)
        c:script(button(c, "Up"), "OnMouseUp", "LeftButton")
        eq(PE.db.ui.moved.broken, nil, kind .. ": a step was taken")
        eq(applied, 0, kind .. ": apply() was called")
        local n = 0
        for _, line in ipairs(debugLines(c, "move")) do
            if line == "broken could not be checked against the screen edge" then n = n + 1 end
        end
        eq(n, 2, kind .. ": not one debug line per press")
    end
end)

test("move: a fight starting during a controller hold stops it and closes the panel", function()
    local c, PE = T.new({})
    openMove(c, PE)
    local panel = movePanel(c)
    dpadTo(c, panel, button(c, "Right"))
    c:script(nav(c), "OnClick", "A", true)
    c:advance(0.6)
    c:enterCombat()
    check(not panel:IsShown(), "the panel stayed open in the fight")
    local stopped = savedHub(PE).x
    check(stopped > 2, "the hold did not move before the fight")
    c:advance(2)
    eq(savedHub(PE).x, stopped, "it kept moving in the fight")
    c:script(nav(c), "OnClick", "A", false)
    eq(savedHub(PE).x, stopped)
    c.stats.addonOnUpdate = 0
    c:advance(1)
    eq(c.stats.addonOnUpdate, 0, "the driver ticks in the fight")
    c:assertClean("fight during A hold")
end)

test("move: the Close button closes the panel", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    openMove(c, PE)
    c:click(button(c, "Close"))
    check(not movePanel(c):IsShown())
    local lines = debugLines(c, "move")
    eq(lines[#lines], "panel closed (Close)")
end)

return { known = KNOWN_FAILURES }
