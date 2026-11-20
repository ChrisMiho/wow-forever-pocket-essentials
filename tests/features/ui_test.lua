-- Rules for the shared window code and the round button: controller navigation
-- (UI.lua "Controller navigation"), and the round button's tap and hold (Hub.lua).
-- Sources: the comments in UI.lua lines 628-634 and at NavArm / NavOnHide /
-- NavCombatEvent; Hub.lua OnClick; docs/DECISIONS.md "General" (holding the round
-- button always opens settings). Fresh client and addon per test.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local NAV_NAME = "PocketEssentialsNavButton"
local ALL_KEYS = { PADDUP = NAV_NAME, PADDDOWN = NAV_NAME, PADDLEFT = NAV_NAME, PADDRIGHT = NAV_NAME, PAD1 = NAV_NAME, PAD2 = NAV_NAME }

local function settingsPanel(c) return rawget(c.env, "PocketEssentialsSettingsPanel") end
local function bindings(c) return c._state(settingsPanel(c)).bindings end

-- Controller keys are only captured while one of our windows is open out of
-- combat (UI.lua header, NavArm line 752).
test("nav: the d-pad and A / B are bound when our window opens out of combat", function()
    local c, PE = T.new({})
    PE:OpenSettings()
    eq(bindings(c), ALL_KEYS)
    c:assertClean("nav open")
end)

-- UI.lua NavArm: "if PE:InCombat() ... return false"; NavCombatEvent re-arms after combat.
test("nav: a window opened in combat gets no keys, and gets them when the fight ends", function()
    local c, PE = T.new({})
    c:enterCombat()
    PE:OpenSettings()
    check(settingsPanel(c):IsShown(), "the window did not open in combat")
    eq(bindings(c), nil, "keys bound in combat")
    c:advance(1)
    c:leaveCombat()
    eq(bindings(c), ALL_KEYS, "keys not bound after the fight")
    c:assertClean("nav open in combat")   -- a binding call during lockdown would be recorded as blocked
end)

-- UI.lua NavOnHide: "Release the keys first".
test("nav: closing the window gives the d-pad back", function()
    local c, PE = T.new({})
    PE:OpenSettings()
    eq(bindings(c), ALL_KEYS)
    PE:CloseSettings()
    eq(bindings(c), nil, "the d-pad stays captured after the window closed")
    PE:OpenSettings()
    eq(bindings(c), ALL_KEYS, "reopening did not bind again")
    c:assertClean("nav close")
end)

-- UI.lua NavCombatEvent / header: cleared when combat starts; no highlight while the controller cannot drive it;
-- re-armed after combat if the window is still open.
test("nav: combat starting releases the keys and the highlight; the keys return after the fight if the window is open", function()
    local c, PE = T.new({})
    PE:OpenSettings()
    local panel = settingsPanel(c)
    c:script(rawget(c.env, NAV_NAME), "OnClick", "DOWN", true)   -- the d-pad moves the highlight
    check(panel.peNavFocus ~= nil, "the d-pad did not highlight anything")
    c:enterCombat()
    check(panel:IsShown(), "the window closed when combat started")
    eq(bindings(c), nil, "keys kept in combat")
    check(panel.peNavFocus == nil, "the highlight stays in combat")
    c:advance(1)
    c:leaveCombat()
    eq(bindings(c), ALL_KEYS, "keys not back after the fight")
    c:assertClean("nav combat")
end)

-- UI.lua NavCombatEvent: re-arm only "if top and top:IsShown()".
test("nav: a window closed during combat does not get the keys back when the fight ends", function()
    local c, PE = T.new({})
    PE:OpenSettings()
    c:enterCombat()
    PE:CloseSettings()
    c:leaveCombat()
    eq(bindings(c), nil, "the d-pad was captured for a closed window")
    c:assertClean("nav closed in combat")
end)

---------------------------------------------------------------------------
-- The round button
---------------------------------------------------------------------------

local function chatPanel(c) return rawget(c.env, "PocketEssentialsChatPanel") end

-- Hub.lua OnClick: held >= HOLD_SECONDS opens the settings even when a click handler
-- (the chat feature) is set; DECISIONS "General": "Holding the round button ... always opens settings".
test("hub: holding the round button opens settings even with the chat feature on", function()
    local c, PE = T.new({ on = { "chat" } })
    local btn = PE.Hub.button
    c:script(btn, "OnMouseDown", "LeftButton")
    c:advance(0.8)
    c:script(btn, "OnMouseUp", "LeftButton")
    c:script(btn, "OnClick", "LeftButton", false)
    c:advance(0.2)
    local settings = settingsPanel(c)
    check(settings and settings:IsShown(), "holding did not open the settings")
    check(not (chatPanel(c) and chatPanel(c):IsShown()), "holding opened the chat picker")
    c:assertClean("hub hold")
end)

test("hub: a short tap opens the chat picker, not the settings, when the chat feature is on", function()
    local c, PE = T.new({ on = { "chat" } })
    c:click(PE.Hub.button)
    c:advance(0.2)
    check(chatPanel(c) and chatPanel(c):IsShown(), "a tap did not open the chat picker")
    check(not (settingsPanel(c) and settingsPanel(c):IsShown()), "a tap opened the settings")
    c:assertClean("hub tap")
end)

---------------------------------------------------------------------------
-- Spec 2026-11-17-post-0.0.9-batch, section 5: feature blocks fold away (Settings.lua BuildModuleRow).
---------------------------------------------------------------------------

local function walkAll(c, w, fn, seen)
    seen = seen or {}
    if seen[w] then return end
    seen[w] = true
    fn(w)
    local st = c._state(w)
    for _, ch in ipairs(st.children) do walkAll(c, ch, fn, seen) end
    if st.scrollChild then walkAll(c, st.scrollChild, fn, seen) end
end

-- Visible buttons of the settings window with this label (the pool keeps hidden ones around).
local function shownButtons(c, label)
    local out = {}
    walkAll(c, settingsPanel(c), function(w)
        if c._state(w).type == "Button" and w:IsVisible() and T.labelOf(w) == label then out[#out + 1] = w end
    end)
    return out
end

-- The visible fold buttons with this label, without the one of "Chat from
-- round button": since 0.4.0 that block has a row drawn with the feature off
-- ("Chat text size", marked always), so it has a fold button in every one of
-- these tests. Its own fold button is tested in chat_test.lua.
local function foldButtons(c, label)
    local out = {}
    for _, b in ipairs(shownButtons(c, label)) do
        if b.peFoldKey ~= "chat" then out[#out + 1] = b end
    end
    return out
end

local function shownText(c, text)
    local found = false
    walkAll(c, settingsPanel(c), function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and st.text == text and r:IsVisible() then found = true end
        end
    end)
    return found
end

local function openSettings(c, PE)
    PE:OpenSettings()
    c:advance(0.2)
end

local function debugLinesOf(c, key)
    local out = {}
    local prefix = " " .. key .. ": "
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        local at = line:find(prefix, 1, true)
        if at and at <= 14 then out[#out + 1] = line:sub(at + #prefix) end
    end
    return out
end

test("fold: a feature that is on with options shows Hide options; tapping folds it and keeps the switch ON", function()
    local c, PE = T.new({ on = { "bagWindow" } })
    openSettings(c, PE)
    eq(#foldButtons(c, "Hide options"), 1)
    check(shownButtons(c, "Normal")[1], "the options are not drawn at first")
    c:click(foldButtons(c, "Hide options")[1])
    c:advance(0.5)
    eq(#foldButtons(c, "Show options"), 1)
    eq(#foldButtons(c, "Hide options"), 0)
    eq(#shownButtons(c, "Normal"), 0, "the options are still drawn")
    check(not shownText(c, "Bag size"), "the option label is still drawn")
    check(PE:IsModuleEnabled("bagWindow"), "folding switched the feature off")
    eq(#shownButtons(c, "ON"), 1, "the switch no longer shows ON")
    eq(PE.db.ui.folded.bagWindow, true)
    c:assertClean("fold")
end)

test("fold: the description line is hidden when folded and comes back when unfolded", function()
    local c, PE = T.new({ on = { "bagWindow" } })
    local desc = PE:GetModule("bagWindow").desc
    check(type(desc) == "string" and desc ~= "", "bagWindow has no description")
    openSettings(c, PE)
    check(shownText(c, desc), "no description at first")
    c:click(foldButtons(c, "Hide options")[1])
    c:advance(0.5)
    check(not shownText(c, desc), "the description is still drawn when folded")
    c:click(foldButtons(c, "Show options")[1])
    c:advance(0.5)
    check(shownText(c, desc), "the description did not come back")
    check(shownButtons(c, "Normal")[1], "the options did not come back")
    eq(PE.db.ui.folded.bagWindow, nil, "unfold left the entry in the saved table")
end)

test("fold: a status line stays while folded", function()
    local c, PE = T.new({ on = { "bags" } })
    PE:GetModule("bags").status = function() return "Status stays" end
    openSettings(c, PE)
    c:click(foldButtons(c, "Hide options")[1])
    c:advance(0.5)
    check(shownText(c, "Status stays"), "the status line vanished")
end)

test("fold: the folded state is saved and still there after a reload", function()
    local c, PE = T.new({ on = { "bags" } })
    openSettings(c, PE)
    c:click(foldButtons(c, "Hide options")[1])
    c:advance(0.5)
    local db = rawget(c.env, "PocketEssentialsDB")
    local c2, PE2 = T.new({ saved = db })
    openSettings(c2, PE2)
    eq(#foldButtons(c2, "Show options"), 1)
    eq(#shownButtons(c2, "Normal"), 0)
end)

test("fold: a feature that is off, or has no options, has no fold button", function()
    local c, PE = T.new({})
    openSettings(c, PE)
    eq(#foldButtons(c, "Hide options"), 0)
    eq(#foldButtons(c, "Show options"), 0)
    local c2, PE2 = T.new({ on = { "sellJunk" } })
    PE2:GetModule("sellJunk").options = nil
    openSettings(c2, PE2)
    eq(#foldButtons(c2, "Hide options"), 0)
    local c3, PE3 = T.new({ on = { "sellJunk" } })
    PE3:GetModule("sellJunk").options = {}
    openSettings(c3, PE3)
    eq(#foldButtons(c3, "Hide options"), 0)
end)

test("fold: a folded feature that is switched off shows no fold button and no options", function()
    local c, PE = T.new({ on = { "bagWindow" } })
    openSettings(c, PE)
    c:click(foldButtons(c, "Hide options")[1])
    c:advance(0.5)
    PE:SetModuleEnabled("bagWindow", false)
    c:advance(0.5)
    eq(#foldButtons(c, "Show options"), 0)
    eq(#shownButtons(c, "Normal"), 0)
end)

test("fold: a damaged saved folded value does no harm and is replaced by an empty table", function()
    for _, bad in ipairs({ "yes", 5, true }) do
        local c, PE = T.new({ on = { "bags" }, saved = { version = 1, enabled = { bags = true }, options = {}, ui = { size = "medium", hubPos = "LEFT", folded = bad }, errors = {} } })
        eq(type(PE.db.ui.folded), "table")
        openSettings(c, PE)
        eq(#foldButtons(c, "Hide options"), 1)
        c:click(foldButtons(c, "Hide options")[1])
        c:advance(0.5)
        eq(PE.db.ui.folded.bags, true)
    end
    -- A non-true entry inside the table does not fold anything.
    local c, PE = T.new({ on = { "bags" }, saved = { version = 1, enabled = { bags = true }, options = {}, ui = { size = "medium", hubPos = "LEFT", folded = { bags = "yes" } }, errors = {} } })
    openSettings(c, PE)
    eq(#foldButtons(c, "Hide options"), 1)
end)

test("fold: the controller's d-pad reaches the fold button, A presses it, and the highlight stays on it", function()
    local c, PE = T.new({ on = { "bags", "sellJunk" } })
    openSettings(c, PE)
    local panel = settingsPanel(c)
    local nav = rawget(c.env, NAV_NAME)
    local fold = foldButtons(c, "Hide options")[1]
    local n = 0
    repeat
        c:script(nav, "OnClick", "RIGHT", true)
        c:script(nav, "OnClick", "RIGHT", false)
        n = n + 1
    until panel.peNavFocus == fold or n > 60
    check(panel.peNavFocus == fold, "the d-pad never reached the fold button")
    c:script(nav, "OnClick", "A", true)
    c:script(nav, "OnClick", "A", false)
    c:advance(0.5)
    eq(PE.db.ui.folded.bags, true)
    local after = foldButtons(c, "Show options")[1]
    check(after, "no Show options button after folding")
    check(panel.peNavFocus == after, "the highlight left the fold button")
    -- and again the other way
    c:script(nav, "OnClick", "A", true)
    c:script(nav, "OnClick", "A", false)
    c:advance(0.5)
    eq(PE.db.ui.folded.bags, nil)
    check(panel.peNavFocus == foldButtons(c, "Hide options")[1], "the highlight left the fold button after unfolding")
    c:assertClean("fold nav")
end)

test("fold: the highlight stays on the fold button of the same feature when two features have one", function()
    local c, PE = T.new({ on = { "bags", "sellJunk" } })
    PE:GetModule("sellJunk").options = { { label = "Extra", action = function() end } }
    openSettings(c, PE)
    local panel = settingsPanel(c)
    local nav = rawget(c.env, NAV_NAME)
    local folds = foldButtons(c, "Hide options")
    eq(#folds, 2)
    local target = folds[2]
    local n = 0
    repeat
        c:script(nav, "OnClick", "RIGHT", true)
        c:script(nav, "OnClick", "RIGHT", false)
        n = n + 1
    until panel.peNavFocus == target or n > 80
    check(panel.peNavFocus == target, "could not reach the second fold button")
    local key = target.peFoldKey
    c:script(nav, "OnClick", "A", true)
    c:script(nav, "OnClick", "A", false)
    c:advance(0.5)
    eq(panel.peNavFocus.peFoldKey, key, "the highlight moved to another feature's button")
    eq(T.labelOf(panel.peNavFocus), "Show options")
end)

test("fold: a tap writes a debug line and does not redraw twice for a fold", function()
    local c, PE = T.new({ on = { "bags" } })
    PE:SetDebug(true)
    openSettings(c, PE)
    c:click(foldButtons(c, "Hide options")[1])
    c:advance(0.5)
    c:click(foldButtons(c, "Show options")[1])
    c:advance(0.5)
    eq(debugLinesOf(c, "settings"), { "bags folded", "bags unfolded" })
end)

-- Spec 2026-11-17 section 6: the Icon key button lives with the Quest icons options.
test("icon key: not in the bottom row; one in the Quest icons block when it is on; it opens the key page and Back returns", function()
    local c, PE = T.new({ quest = true, on = { "questIcons" } })
    openSettings(c, PE)
    eq(#shownButtons(c, "Quest Icon Key"), 1)
    eq(#shownButtons(c, "Reload UI"), 1)
    c:click(shownButtons(c, "Quest Icon Key")[1])
    c:advance(0.5)
    check(shownText(c, "Pocket Essentials - Quest Icon Key") or #shownButtons(c, "Back") == 1, "the key page did not open")
    eq(#shownButtons(c, "Back"), 1)
    c:click(shownButtons(c, "Back")[1])
    c:advance(0.5)
    eq(#shownButtons(c, "Quest Icon Key"), 1, "Back did not return to the main list")
    c:assertClean("icon key")
end)

test("icon key: no button when Quest icons is off, and none in the bottom row", function()
    local c, PE = T.new({ quest = true })
    openSettings(c, PE)
    eq(#shownButtons(c, "Quest Icon Key"), 0)
    eq(#shownButtons(c, "Reload UI"), 1)
end)

test("icon key: folding Quest icons hides the Icon key button", function()
    local c, PE = T.new({ quest = true, on = { "questIcons" } })
    openSettings(c, PE)
    eq(#shownButtons(c, "Quest Icon Key"), 1)
    c:click(foldButtons(c, "Hide options")[1])
    c:advance(0.5)
    eq(#shownButtons(c, "Quest Icon Key"), 0, "the Icon key button is drawn while folded")
    c:click(foldButtons(c, "Show options")[1])
    c:advance(0.5)
    eq(#shownButtons(c, "Quest Icon Key"), 1)
end)

-- The controller highlight stays on a feature's own ON / OFF switch after A switches it
-- (the buttons after it come and go, so the highlight must not drift to another button).
local function dpadTo(c, target)
    local panel, nav = settingsPanel(c), rawget(c.env, NAV_NAME)
    local n = 0
    repeat
        c:script(nav, "OnClick", "RIGHT", true)
        c:script(nav, "OnClick", "RIGHT", false)
        n = n + 1
    until panel.peNavFocus == target or n > 80
    check(panel.peNavFocus == target, "the d-pad never reached the button")
end

local function pressA(c)
    local nav = rawget(c.env, NAV_NAME)
    c:script(nav, "OnClick", "A", true)
    c:script(nav, "OnClick", "A", false)
    c:advance(0.5)
end

-- The switch of the n-th feature row: the 'n'-th button labelled ON or OFF (the debug switch is not on this page).
local function switchOfRow(c, n)
    local found = {}
    walkAll(c, settingsPanel(c), function(w)
        local l = c._state(w).type == "Button" and w:IsVisible() and T.labelOf(w)
        if l == "ON" or l == "OFF" then found[#found + 1] = w end
    end)
    table.sort(found, function(a, b)
        local _, ya = a:GetCenter()
        local _, yb = b:GetCenter()
        return ya > yb
    end)
    return found[n]
end

local function rowIndexOf(c, PE, key)
    for i, m in ipairs(PE.moduleList) do if m.key == key then return i end end
end

test("fold: A on a switch keeps the highlight on that feature's switch, off to on and on to off", function()
    local c, PE = T.new({ on = { "sellJunk" } })
    PE:GetModule("sellJunk").options = { { label = "Extra", action = function() end } }
    openSettings(c, PE)
    local panel = settingsPanel(c)
    local i = rowIndexOf(c, PE, "bags")
    local sw = switchOfRow(c, i)
    dpadTo(c, sw)
    pressA(c)
    check(PE:IsModuleEnabled("bags"), "A did not switch bags on")
    check(panel.peNavFocus == switchOfRow(c, i), "off to on: the highlight left the switch")
    eq(T.labelOf(panel.peNavFocus), "ON")
    pressA(c)
    check(not PE:IsModuleEnabled("bags"), "the second A did not switch bags off again")
    check(PE:IsModuleEnabled("sellJunk"), "the second A switched another feature")
    check(panel.peNavFocus == switchOfRow(c, i), "on to off: the highlight left the switch")
    eq(T.labelOf(panel.peNavFocus), "OFF")
end)

test("fold: in a row with a fold button the d-pad goes to the fold button first, then the switch", function()
    local c, PE = T.new({ on = { "bags" } })
    openSettings(c, PE)
    local panel, nav = settingsPanel(c), rawget(c.env, NAV_NAME)
    local fold = foldButtons(c, "Hide options")[1]
    local order = {}
    for _ = 1, 40 do
        c:script(nav, "OnClick", "RIGHT", true)
        c:script(nav, "OnClick", "RIGHT", false)
        local f = panel.peNavFocus
        order[#order + 1] = f
        if f == fold then break end
    end
    c:script(nav, "OnClick", "RIGHT", true)
    c:script(nav, "OnClick", "RIGHT", false)
    eq(T.labelOf(panel.peNavFocus), "ON", "the switch does not follow the fold button")
end)

-- Spec 2026-11-17-move-things, "Hold with the controller": only a button with a peHold table
-- acts on A going down; every other button still clicks once, on A's release.
test("nav: an ordinary settings button does nothing on A down and clicks once on A up", function()
    local c, PE = T.new({})
    openSettings(c, PE)
    local panel, nav = settingsPanel(c), rawget(c.env, NAV_NAME)
    local sw = switchOfRow(c, rowIndexOf(c, PE, "bags"))
    check(sw.peHold == nil, "a settings button has a hold hook")
    local clicks = 0
    local original = sw:GetScript("OnClick")
    sw:SetScript("OnClick", function(...) clicks = clicks + 1; return original(...) end)
    dpadTo(c, sw)
    c:script(nav, "OnClick", "A", true)
    c:advance(1)
    eq(clicks, 0, "A down clicked")
    check(not PE:IsModuleEnabled("bags"), "A down switched the feature")
    c:script(nav, "OnClick", "A", false)
    eq(clicks, 1, "A up did not click exactly once")
    check(PE:IsModuleEnabled("bags"), "A up did not switch the feature")
    c:advance(0.5)
    c:assertClean("nav ordinary")
end)

-- The same hook in UI.lua on any panel: start on A down, stop on A up, no click on release.
test("nav: a button with peHold gets start on A down and stop on A up, and no click", function()
    local c, PE = T.new({})
    openSettings(c, PE)
    local panel, nav = settingsPanel(c), rawget(c.env, NAV_NAME)
    local sw = switchOfRow(c, rowIndexOf(c, PE, "bags"))
    local log = {}
    sw.peHold = { start = function() log[#log + 1] = "start" end, stop = function() log[#log + 1] = "stop" end }
    dpadTo(c, sw)
    c:script(nav, "OnClick", "A", true)
    eq(log, { "start" })
    c:script(nav, "OnClick", "A", false)
    eq(log, { "start", "stop" })
    check(not PE:IsModuleEnabled("bags"), "the release clicked a hold button")
    -- The press is lost when the window hides.
    c:script(nav, "OnClick", "A", true)
    PE:CloseSettings()
    eq(log, { "start", "stop", "start", "stop" })
    sw.peHold = nil
    c:assertClean("nav hold hook")
end)

---------------------------------------------------------------------------
-- Tidier option rows (spec 2026-11-18-tidier-settings): toggles, rows with
-- get / set, and the heading beside its buttons. Drawn on "Sell junk", which
-- has no options of its own.
---------------------------------------------------------------------------

-- The visible text region of the settings window that reads exactly `text`.
local function textRegionOf(c, text)
    local found
    walkAll(c, settingsPanel(c), function(w)
        if c._state(w).type ~= "Button" then
            for _, r in ipairs(c._state(w).regions) do
                local st = c._state(r)
                if st.type == "FontString" and st.text == text and r:IsVisible() then found = found or r end
            end
        end
    end)
    return found
end

local ON_OFF_TEST = { { value = true, label = "On" }, { value = false, label = "Off" } }

local function withOptions(options, opts)
    local c, PE = T.new({ on = { "sellJunk" } })
    local mod = PE:GetModule("sellJunk")
    mod.options = options
    mod.opts = mod.opts or {}
    for k, v in pairs(opts or {}) do mod.opts[k] = v end
    openSettings(c, PE)
    return c, PE, mod
end

test("options: a toggle is one button reading label: choice, green for true, and a tap flips it and runs OnChange", function()
    local calls = {}
    local c, PE, mod = withOptions({
        { key = "first", label = "First", toggle = true, choices = ON_OFF_TEST,
          OnChange = function(m, v) calls[#calls + 1] = v end },
        { key = "second", label = "Second", toggle = true,
          choices = { { value = false, label = "In" }, { value = true, label = "Out" } } },
    }, { first = true, second = false })
    local first, second = shownButtons(c, "First: On")[1], shownButtons(c, "Second: In")[1]
    check(first and second, "the toggles are not drawn as one button each")
    eq(first.peStyle, "on")
    eq(second.peStyle, "off")
    eq(#shownButtons(c, "On") + #shownButtons(c, "Off") + #shownButtons(c, "In") + #shownButtons(c, "Out"), 0,
        "a choice is still drawn as a button of its own")
    check(not textRegionOf(c, "First") and not textRegionOf(c, "Second"), "a toggle has a heading line")
    local _, _, top1 = c._rect(first)
    local _, _, top2 = c._rect(second)
    check(math.abs(top1 - top2) < 0.01, "two toggles in a row are not on one line")
    c:click(first)
    c:advance(0.2)
    eq(mod.opts.first, false)
    eq(calls, { false })
    check(shownButtons(c, "First: Off")[1], "the toggle does not read the new choice")
    eq(shownButtons(c, "First: Off")[1].peStyle, "off")
    c:assertClean("toggle")
end)

test("options: a toggle with a damaged saved value reads as its first choice and a tap saves the second", function()
    local c, PE, mod = withOptions({
        { key = "first", label = "First", toggle = true, choices = ON_OFF_TEST },
    }, { first = "yes" })
    local b = shownButtons(c, "First: On")[1]
    check(b, "not drawn as the first choice")
    c:click(b)
    c:advance(0.2)
    eq(mod.opts.first, false)
    check(shownButtons(c, "First: Off")[1], "the tap did not change what the toggle says")
    c:assertClean("damaged toggle")
end)

test("options: a row with get and set marks what get returns, and a tap goes through set", function()
    local c, PE, mod = withOptions({
        { label = "Pair", choices = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
          get = function(m) return m.opts.x end,
          set = function(m, v) m.opts.x = v; m.opts.y = v .. "!" end },
    }, { x = "a" })
    eq(shownButtons(c, "Alpha")[1].peSelected, true)
    eq(shownButtons(c, "Beta")[1].peSelected, false)
    c:click(shownButtons(c, "Beta")[1])
    c:advance(0.2)
    eq({ mod.opts.x, mod.opts.y }, { "b", "b!" })
    eq(shownButtons(c, "Beta")[1].peSelected, true)
    c:assertClean("get and set")
end)

test("options: get returning nothing marks no button, and a set that fails is recorded and saves nothing", function()
    local c, PE, mod = withOptions({
        { label = "Pair", choices = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
          get = function() return nil end,
          set = function() error("broken set") end,
          OnChange = function() error("OnChange ran after a failed set") end },
    })
    eq(shownButtons(c, "Alpha")[1].peSelected, false)
    eq(shownButtons(c, "Beta")[1].peSelected, false)
    c:click(shownButtons(c, "Alpha")[1])
    c:advance(0.2)
    local msgs = {}
    for _, e in ipairs(PE.errors) do msgs[#msgs + 1] = tostring(e.msg) end
    local joined = table.concat(msgs, "\n")
    check(joined:find("broken set", 1, true), "the failed set is not recorded")
    check(not joined:find("OnChange ran", 1, true), "OnChange ran after a failed set")
end)

test("options: a heading sits on its buttons' line when they fit, and above them when they do not", function()
    local many = {}
    for i = 1, 14 do many[i] = { value = i, label = "Choice number " .. i } end
    for _, size in ipairs({ "small", "medium", "large" }) do
        local c, PE = T.new({ on = { "sellJunk" } })
        PE:SetUISetting("size", size)
        local mod = PE:GetModule("sellJunk")
        mod.options = {
            { key = "few", label = "Few", choices = { { value = 1, label = "One" }, { value = 2, label = "Two" } } },
            { key = "many", label = "Many", choices = many },
        }
        openSettings(c, PE)
        local few, one = textRegionOf(c, "Few"), shownButtons(c, "One")[1]
        local fl, _, ft, fb = c._rect(few)
        local bl, _, bt, bb = c._rect(one)
        check(ft <= bt + 0.01 and fb >= bb - 0.01, size .. ": \"Few\" is not on its buttons' line")
        check(fl < bl, size .. ": \"Few\" is not left of its buttons")
        local manyText, first = textRegionOf(c, "Many"), shownButtons(c, "Choice number 1")[1]
        local _, _, _, mb = c._rect(manyText)
        local _, _, ct = c._rect(first)
        check(mb >= ct - 0.01, size .. ": \"Many\" is not above its buttons, which wrap")
        c:assertClean("headings at " .. size)
    end
end)

---------------------------------------------------------------------------
-- The number control (spec 2026-11-18-number-control-design, section 1):
-- one joined box, "-" | value | "+", drawn by the shared list drawer.
---------------------------------------------------------------------------

local function numberRow(opts, extra)
    local calls = {}
    local row = { key = "n", label = "Count",
        number = { min = 1, max = 20, default = 5, unit = "spots", all = 0, allLabel = "All" },
        OnChange = function(m, v) calls[#calls + 1] = v end }
    for k, v in pairs(extra or {}) do row.number[k] = v end
    local c, PE, mod = withOptions({ row }, opts)
    return c, PE, mod, calls
end

local function press(c, label)
    c:click(shownButtons(c, label)[1])
    c:advance(0.2)
end

test("number: one joined box, - value +, on the heading's line, - then + in the d-pad order", function()
    local c, PE = numberRow({ n = 5 })
    local minus, plus, value = shownButtons(c, "-")[1], shownButtons(c, "+")[1], textRegionOf(c, "5")
    check(minus and plus and value, "the box is not drawn as -, 5, +")
    check(textRegionOf(c, "spots"), "no unit word under the value")
    local ml, mr, mt = c._rect(minus)
    local vl, vr = c._rect(value)
    local pl, _, pt = c._rect(plus)
    check(mr <= vl + 0.01 and vr <= pl + 0.01, "the pieces are not in the order - value +")
    check(math.abs(mt - pt) < 0.01, "- and + are not on one line")
    check(math.abs(pl - mr) > 0, "the ends touch with nothing between them")
    local heading = textRegionOf(c, "Count")
    local hl = c._rect(heading)
    check(hl < ml, "the heading is not left of the box")
    dpadTo(c, minus)
    local nav = rawget(c.env, NAV_NAME)
    c:script(nav, "OnClick", "RIGHT", true)
    c:script(nav, "OnClick", "RIGHT", false)
    check(settingsPanel(c).peNavFocus == plus, "after - the d-pad does not go to +")
    eq(minus.peStyle, "step")
    c:assertClean("number box")
end)

test("number: + and - step by one and run OnChange with the new value", function()
    local c, PE, mod, calls = numberRow({ n = 5 })
    press(c, "+")
    eq(mod.opts.n, 6)
    check(textRegionOf(c, "6"), "the box does not show the new value")
    press(c, "-")
    press(c, "-")
    eq(mod.opts.n, 4)
    eq(calls, { 6, 5, 4 })
    c:assertClean("number step")
end)

test("number: + at the top goes to All, - from All goes back to the top, and + is dim at All", function()
    local c, PE, mod = numberRow({ n = 20 })
    press(c, "+")
    eq(mod.opts.n, 0)
    check(textRegionOf(c, "All"), "the box does not read All")
    eq(shownButtons(c, "+")[1].peStyle, "stepDim")
    press(c, "+")
    eq(mod.opts.n, 0, "a dim + changed the value")
    press(c, "-")
    eq(mod.opts.n, 20)
    c:assertClean("number all")
end)

test("number: - is dim at the bottom, and pressing it saves nothing and runs no OnChange", function()
    local c, PE, mod, calls = numberRow({ n = 1 })
    eq(shownButtons(c, "-")[1].peStyle, "stepDim")
    press(c, "-")
    eq(mod.opts.n, 1)
    eq(calls, {})
    c:assertClean("number bottom")
end)

test("number: 0 with an Off label reads Off", function()
    local c = numberRow({ n = 0 }, { min = 0, max = 10, default = 2, all = false, offLabel = "Off", unit = "merge" })
    check(textRegionOf(c, "Off"), "0 does not read Off")
    eq(shownButtons(c, "-")[1].peStyle, "stepDim")
    c:assertClean("number off")
end)

test("number: a saved value out of range or not a number reads the default, and + steps from it", function()
    for _, bad in ipairs({ 15.5, 25, "x", -3 }) do
        local c, PE, mod = numberRow({ n = bad }, { all = false })
        check(textRegionOf(c, "5"), tostring(bad) .. " does not read as the default")
        press(c, "+")
        eq(mod.opts.n, 6, tostring(bad))
        c:assertClean("number bad " .. tostring(bad))
    end
end)

test("number: a stepper row draws the same box from the feature's own value, and a missing step is dim", function()
    local ups = 0
    local c = withOptions({
        { label = "Size", stepper = function() return { text = "14", unit = "text size", up = function() ups = ups + 1 end } end },
    })
    check(textRegionOf(c, "14") and textRegionOf(c, "text size"), "the stepper's value is not in the box")
    eq(shownButtons(c, "-")[1].peStyle, "stepDim")
    eq(shownButtons(c, "+")[1].peStyle, "step")
    press(c, "+")
    press(c, "-")
    eq(ups, 1)
    c:assertClean("stepper")
end)

test("number: at every size in a narrow window the three pieces stay on one line", function()
    for _, size in ipairs({ "small", "medium", "large" }) do
        local c, PE = T.new({ on = { "sellJunk" } })
        PE:SetUISetting("size", size)
        local mod = PE:GetModule("sellJunk")
        mod.opts = mod.opts or {}
        mod.opts.n = 3
        mod.options = { { key = "n", label = "A rather long heading for a number row",
            number = { min = 1, max = 20, default = 5, unit = "spots" } } }
        openSettings(c, PE)
        local _, _, mt = c._rect(shownButtons(c, "-")[1])
        local _, _, pt = c._rect(shownButtons(c, "+")[1])
        check(math.abs(mt - pt) < 0.01, size .. ": the box split across lines")
        c:assertClean("number at " .. size)
    end
end)

---------------------------------------------------------------------------
-- 0.8.0: the slim scroll bar (spec section 6) and the touch setting (section 5)
---------------------------------------------------------------------------

-- A scroll area of our own in the settings window, sized by hand.
local function bareArea(c, PE, touch, contentHeight, noPaging)
    PE:SetUISetting("touch", touch)
    local UI = PE.UI
    local m = UI:Metrics()
    local area = UI:CreateScrollArea(rawget(c.env, "UIParent"))
    area:SetPoint("CENTER", rawget(c.env, "UIParent"), "CENTER", 0, 0)
    area:Layout(400, m.button * 8, noPaging)
    area:SetContentHeight(contentHeight)
    return area, m
end

test("scroll bar: shows for a list that does not fit with touch on, and not for a list that fits", function()
    local c, PE = T.new({})
    local area = bareArea(c, PE, true, 4000)
    check(area.upButton:IsShown() and area.downButton:IsShown() and area.track:IsShown(), "no bar on a long list")
    check(area.viewWidth < 400, "no room kept for the bar")
    local fits = bareArea(c, PE, true, 100, true)
    check(not fits.upButton:IsShown() and not fits.downButton:IsShown() and not fits.track:IsShown(), "a bar on a list that fits")
    eq(fits.viewWidth, 400)
    c:assertClean("scroll bar shown")
end)

test("scroll bar: the marker is the share of the list in view, and at least half a button", function()
    local c, PE = T.new({})
    local area, m = bareArea(c, PE, true, 4000)
    local want = area.trackHeight * (area.viewHeight / 4000)
    eq(math.abs(area.thumb:GetHeight() - math.max(want, m.button * 0.5)) < 0.01, true, "thumb height " .. area.thumb:GetHeight())
    area:SetContentHeight(area.viewHeight * 400)
    eq(math.abs(area.thumb:GetHeight() - m.button * 0.5) < 0.01, true, "a very long list: the marker is thinner than half a button")
    area:SetContentHeight(area.viewHeight * 2)
    eq(math.abs(area.thumb:GetHeight() - area.trackHeight * 0.5) < 0.01, true, "half in view: the marker is half the track")
    c:assertClean("scroll bar marker")
end)

test("scroll bar: the marker is at the track top at offset 0 and at its bottom at the full range", function()
    local c, PE = T.new({})
    local area = bareArea(c, PE, true, 4000)
    local _, _, trackTop, trackBottom = c._rect(area.track)
    local _, _, top = c._rect(area.thumb)
    eq(math.abs(top - trackTop) < 0.01, true, "not at the top")
    area:ScrollTo(area:GetRange())
    local _, _, _, bottom = c._rect(area.thumb)
    eq(math.abs(bottom - trackBottom) < 0.01, true, "not at the bottom")
    area:ScrollTo(area:GetRange() / 2)
    local _, _, midTop, midBottom = c._rect(area.thumb)
    eq(math.abs((midTop + midBottom) / 2 - (trackTop + trackBottom) / 2) < 0.01, true, "not in the middle")
end)

test("scroll bar: a tap on the track above the marker pages up, below it pages down", function()
    local c, PE = T.new({})
    local area = bareArea(c, PE, true, 4000)
    area:ScrollTo(1000)
    local scale = area.track:GetEffectiveScale()
    local _, _, top, bottom = c._rect(area.thumb)
    c.world.cursor = { 10, (bottom - 5) * scale }
    local before = area.offset
    c:script(area.track, "OnMouseDown", "LeftButton")
    check(area.offset > before, "a tap below the marker did not page down")
    _, _, top, bottom = c._rect(area.thumb)
    c.world.cursor = { 10, (top + 5) * scale }
    before = area.offset
    c:script(area.track, "OnMouseDown", "LeftButton")
    check(area.offset < before, "a tap above the marker did not page up")
    c:assertClean("scroll bar taps")
end)

test("scroll bar: the arrow tabs dim at the ends and page like Up and Down did", function()
    local c, PE = T.new({})
    local area = bareArea(c, PE, true, 4000)
    eq(area.upButton.peStyle, "stepDim")
    eq(area.downButton.peStyle, "step")
    c:click(area.downButton)
    check(area.offset > 0, "the down tab did not page")
    eq(area.upButton.peStyle, "step")
    area:ScrollTo(area:GetRange())
    eq(area.downButton.peStyle, "stepDim")
    c:click(area.upButton)
    check(area.offset < area:GetRange(), "the up tab did not page")
    c:assertClean("scroll bar tabs")
end)

test("touch: not asked yet reads as yes; only an explicit no hides the bar", function()
    local c, PE = T.new({})
    eq(PE.db.ui.touch, nil)
    eq(PE:UsesTouch(), true)
    PE:SetUISetting("touch", false)
    eq(PE:UsesTouch(), false)
    local area = bareArea(c, PE, false, 4000)
    check(not area.upButton:IsShown() and not area.track:IsShown(), "the bar shows with touch off")
    eq(area.viewWidth, 400, "the list is not full width")
end)

test("touch: the toggle in the settings flips ui.touch and the window redraws at once", function()
    local c, PE = T.new({})
    openSettings(c, PE)
    check(#shownButtons(c, "Touch screen: Yes") == 1, "no 'Touch screen: Yes' button")
    local btn = shownButtons(c, "Touch screen: Yes")[1]
    eq(btn.peStyle, "on")
    c:click(btn)
    c:advance(0.2)
    eq(PE.db.ui.touch, false)
    check(#shownButtons(c, "Touch screen: No") == 1, "the toggle did not change its label")
    eq(shownButtons(c, "Touch screen: No")[1].peStyle, "off")
    c:click(shownButtons(c, "Touch screen: No")[1])
    c:advance(0.2)
    eq(PE.db.ui.touch, true)
    check(#shownButtons(c, "Touch screen: Yes") == 1, "the toggle did not come back")
    c:assertClean("touch toggle")
end)

test("touch off: the settings list is full width and the d-pad reaches the last settings button", function()
    local c, PE = T.new({})
    PE:SetUISetting("touch", false)
    openSettings(c, PE)
    local panel = settingsPanel(c)
    local area
    walkAll(c, panel, function(w) if w.upButton and w.downButton then area = w end end)
    check(area, "no scroll area")
    check(not area.upButton:IsShown(), "the bar is shown with touch off")
    eq(area.viewWidth, panel.contentWidth, "the list is not full width")
    -- Every button of the list, in reading order; the last one must be reachable.
    local last
    walkAll(c, area.child, function(w)
        if c._state(w).type == "Button" and w:IsVisible() then
            local _, _, top = c._rect(w)
            if not last or top < select(3, c._rect(last)) then last = w end
        end
    end)
    check(last, "no button in the list")
    dpadTo(c, last)
    eq(panel.peNavFocus, last)
    c:assertClean("touch off d-pad")
end)


---------------------------------------------------------------------------
-- 0.8.0 spec section 3: round button colour themes; section 4: number suffix.
---------------------------------------------------------------------------

local function hubColors(c, PE)
    local H = PE.Hub
    return { ring = c._state(H.ring.texture).vertexColor, fill = c._state(H.fill.texture).vertexColor,
             label = c._state(H.label).textColor }
end

local function near(a, b)
    for i = 1, 3 do if math.abs(a[i] - b[i]) > 1e-6 then return false end end
    return true
end

local THEME_CASES = {
    { "gold", { 1, 0.82, 0 }, { 0.07, 0.07, 0.10 } },
    { "horde", { 0.85, 0.15, 0.10 }, { 0.18, 0.03, 0.03 } },
    { "alliance", { 0.35, 0.62, 1.00 }, { 0.03, 0.08, 0.24 } },
    { "nonsense", { 1, 0.82, 0 }, { 0.07, 0.07, 0.10 } },   -- unknown draws gold
}

test("hub: each colour theme sets the ring, fill and label at once, an unknown one draws gold", function()
    local c, PE = T.new({})
    for _, case in ipairs(THEME_CASES) do
        PE:SetUISetting("hubColor", case[1])
        local got = hubColors(c, PE)
        check(near(got.ring, case[2]), case[1] .. " ring")
        check(near(got.label, case[2]), case[1] .. " label")
        check(near(got.fill, case[3]), case[1] .. " fill")
    end
    c:assertClean("hub themes")
end)

test("hub: the pressed colour follows the theme", function()
    local c, PE = T.new({})
    PE:SetUISetting("hubColor", "alliance")
    c:script(PE.Hub.button, "OnMouseDown", "LeftButton")
    check(near(hubColors(c, PE).fill, { 0.10, 0.25, 0.55 }), "alliance pressed")
    PE:SetUISetting("hubColor", "horde")
    check(near(hubColors(c, PE).fill, { 0.18, 0.03, 0.03 }) or near(hubColors(c, PE).fill, { 0.45, 0.07, 0.05 }), "horde fill")
    c:assertClean("hub pressed theme")
end)

test("settings: the Button colour row has Gold, Horde and Alliance, and a tap repaints the round button", function()
    local c, PE = T.new({})
    openSettings(c, PE)
    check(textRegionOf(c, "Button colour"), "no Button colour heading")
    check(shownButtons(c, "Gold")[1] and shownButtons(c, "Alliance")[1], "buttons missing")
    press(c, "Horde")
    eq(PE.db.ui.hubColor, "horde")
    check(near(hubColors(c, PE).ring, { 0.85, 0.15, 0.10 }), "ring not red")
    c:assertClean("button colour row")
end)

test("number: a suffix follows a number but never Off or All", function()
    local c, PE = numberRow({ n = 3 }, { min = 0, suffix = "%", offLabel = "Off", all = false })
    check(textRegionOf(c, "3%"), "no 3%")
    local c2 = numberRow({ n = 0 }, { min = 0, suffix = "%", offLabel = "Off", all = false })
    check(textRegionOf(c2, "Off") and not textRegionOf(c2, "Off%") and not textRegionOf(c2, "0%"), "Off wrong")
    local c3 = numberRow({ n = 0 }, { suffix = "%" })
    check(textRegionOf(c3, "All") and not textRegionOf(c3, "All%"), "All wrong")
end)

-- 0.8.0 fix: with touch off there are no scroll tabs, so the d-pad itself pages a list
-- that has no stops below the top (UI.lua NavMove).
local function dpadKey(c, key)
    local nav = rawget(c.env, NAV_NAME)
    c:script(nav, "OnClick", key, true)
    c:script(nav, "OnClick", key, false)
end

test("nav: touch off, the Errors page can be read to the bottom with the d-pad Down", function()
    local c, PE = T.new({})
    PE:SetUISetting("touch", false)
    for i = 1, 40 do PE:LogError("probe", "problem number " .. i .. " with a fairly long message to fill the line", "stack " .. i) end
    openSettings(c, PE)
    PE:OpenSettings("errors")
    c:advance(0.2)
    local panel = settingsPanel(c)
    local area = panel.peNavArea
    check(area and area:GetRange() > 100, "the Errors page does not scroll")
    for _ = 1, 80 do
        dpadKey(c, "DOWN")
        if area.offset >= area:GetRange() - 0.5 then break end
    end
    check(area.offset >= area:GetRange() - 0.5, "the d-pad never reached the bottom: " .. area.offset .. " of " .. area:GetRange())
    for _ = 1, 80 do
        dpadKey(c, "UP")
        if area.offset <= 0.5 then break end
    end
    check(area.offset <= 0.5, "the d-pad Up never got back to the top")
end)

test("nav: touch on, the d-pad Down does not page the Errors page", function()
    local c, PE = T.new({})
    PE:SetUISetting("touch", true)
    for i = 1, 40 do PE:LogError("probe", "problem number " .. i .. " with a fairly long message to fill the line", "stack " .. i) end
    openSettings(c, PE)
    PE:OpenSettings("errors")
    c:advance(0.2)
    local area = settingsPanel(c).peNavArea
    check(area and area:GetRange() > 100, "the Errors page does not scroll")
    for _ = 1, 6 do dpadKey(c, "DOWN") end
    eq(area.offset, 0, "the d-pad paged with touch on")
end)

-- Spec 2026-11-19-0.8.1-clearer-labels, section 1: toggles and action buttons
-- that follow each other share a line; one action alone stays one wide button.
test("quest icons: Hide Blue Quest Haze and Quest Icon Key sit on one line, the key to the right", function()
    local c, PE = T.new({ quest = true, on = { "questIcons" } })
    openSettings(c, PE)
    local haze, key = shownButtons(c, "Hide Blue Quest Haze: On")[1], shownButtons(c, "Quest Icon Key")[1]
    check(haze, "no Hide Blue Quest Haze: On button")
    check(key, "no Quest Icon Key button")
    eq(key:GetTop(), haze:GetTop(), "not on one line")
    check(key:GetLeft() > haze:GetLeft(), "the key is not to the right of the toggle")
    c:assertClean("haze and key")
end)

test("quest arrow: Move the arrow is still one wide button on its own line", function()
    local c, PE = T.new({ quest = true, on = { "questArrow" } })
    openSettings(c, PE)
    local move, small = shownButtons(c, "Move the arrow")[1], shownButtons(c, "Small")[1]
    check(move and small, "Move the arrow or the Arrow size buttons are missing")
    check(move:GetWidth() >= move:GetHeight() * 4 - 0.01, "Move the arrow is narrower than 4 button heights")
    check(move:GetTop() ~= small:GetTop(), "Move the arrow shares a line with Arrow size")
    c:assertClean("move the arrow")
end)


return { known = KNOWN_FAILURES }
