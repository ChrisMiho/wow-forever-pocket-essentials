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
-- Spec 2026-11-20-0.9.0-ui-redesign, "Settings window": tabs on the left,
-- cards on the right (Settings.lua), and the widgets (UI.lua).
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

-- tab: a tab id (PE.SETTINGS_TABS); nil keeps the tab shown last.
local function openSettings(c, PE, tab)
    PE:OpenSettings(tab)
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

-- The visible switch of a feature's card.
local function switchOf(c, key)
    local found
    walkAll(c, settingsPanel(c), function(w)
        if w.peSwitchState and w.peKey == key and w:IsVisible() then found = w end
    end)
    return found
end

local function tabButton(c, id)
    local found
    walkAll(c, settingsPanel(c), function(w) if w.peTabId == id then found = w end end)
    return found
end

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

local function dpadKey(c, key)
    local nav = rawget(c.env, NAV_NAME)
    c:script(nav, "OnClick", key, true)
    c:script(nav, "OnClick", key, false)
end

local function near(a, b, eps) return math.abs(a - b) < (eps or 0.01) end

test("tabs: eight tabs in the spec's order, each holding the spec's helpers", function()
    local c, PE = T.new({})
    local got = {}
    for _, t in ipairs(PE.SETTINGS_TABS) do
        got[#got + 1] = t.id .. "=" .. t.label .. "=" .. table.concat(t.features or {}, ",")
    end
    eq(got, { "questIcons=Quest icons=questIcons", "questArrow=Quest arrow=questArrow", "bags=Bags=bagWindow,bags",
        "vendors=Vendors=sellJunk,repair", "chat=Chat=chat", "menuBg=Menu background=menuBg", "general=General=",
        "errors=Errors=" })
    openSettings(c, PE)
    for _, t in ipairs(PE.SETTINGS_TABS) do
        local b = tabButton(c, t.id)
        check(b and b:IsVisible(), "no tab " .. t.id)
        eq(T.labelOf(b), t.label)
    end
    eq(settingsPanel(c).peTitle:GetText(), "Pocket Essentials")
    c:assertClean("tabs")
end)

test("tabs: all eight fit the window at every button size, stacked one border apart, never taller than a button", function()
    for _, size in ipairs({ "small", "medium", "large" }) do
        local c, PE = T.new({})
        PE:SetUISetting("size", size)
        openSettings(c, PE)
        local M = PE.UI:Metrics()
        local panel = settingsPanel(c)
        local _, _, contentTop, contentBottom = c._rect(panel.content)
        local prevBottom
        for _, t in ipairs(PE.SETTINGS_TABS) do
            local b = tabButton(c, t.id)
            local _, _, top, bottom = c._rect(b)
            check(top - bottom <= M.button + 0.01, size .. ": a tab is taller than a button")
            check(bottom >= contentBottom - 0.01, size .. ": tab " .. t.id .. " is below the window")
            check(near(b:GetWidth(), M.button * 5), size .. ": tabs are not five buttons wide")
            if prevBottom then check(near(prevBottom - top, M.border), size .. ": tabs are not one border apart") end
            prevBottom = bottom
        end
        local _, _, firstTop = c._rect(tabButton(c, "questIcons"))
        check(near(firstTop, contentTop), size .. ": the tabs do not start at the top of the content")
        c:assertClean("tabs at " .. size)
    end
end)

test("tabs: the chosen tab is gold with its bar, a tap shows only that tab's cards, and it is remembered", function()
    local c, PE = T.new({})
    openSettings(c, PE)
    eq(PE:SettingsPage(), "questIcons")
    eq(tabButton(c, "questIcons").peStyle, "tabOn")
    eq(tabButton(c, "bags").peStyle, "tabItem")
    check(tabButton(c, "questIcons").peBar:IsShown() and not tabButton(c, "bags").peBar:IsShown(), "the gold bar is wrong")
    check(shownText(c, "Quest icons"), "the Quest icons card is not on the first tab")
    c:click(tabButton(c, "bags"))
    c:advance(0.2)
    check(shownText(c, PE:GetModule("bagWindow").label) and shownText(c, PE:GetModule("bags").label),
        "the Bags tab does not hold both bag cards")
    check(not switchOf(c, "questIcons"), "another tab's card is still drawn")
    eq(tabButton(c, "bags").peStyle, "tabOn")
    PE:CloseSettings()
    openSettings(c, PE)
    eq(PE:SettingsPage(), "bags", "the tab was not remembered")
    openSettings(c, PE, "vendors")
    check(switchOf(c, "sellJunk") and switchOf(c, "repair"), "the Vendors tab does not hold both vendor cards")
    c:assertClean("tab choice")
end)

test("tabs: a feature tab's dot is green while any of its helpers is on, grey otherwise", function()
    local c, PE = T.new({ on = { "repair" } })
    openSettings(c, PE)
    eq(tabButton(c, "vendors").peDotOn, true)
    eq(tabButton(c, "bags").peDotOn, false)
    local green = c._state(tabButton(c, "vendors").peDot.texture).vertexColor
    check(near(green[1], 0.35) and near(green[2], 0.92), "the on dot is not green")
    local grey = c._state(tabButton(c, "bags").peDot.texture).vertexColor
    check(near(grey[1], 0.40) and near(grey[3], 0.43), "the off dot is not grey")
    check(not tabButton(c, "general").peDot.texture:IsShown(), "General has a dot")
    PE:SetModuleEnabled("bags", true)
    c:advance(0.2)
    eq(tabButton(c, "bags").peDotOn, true)
end)

test("tabs: the Errors tab has a red badge with the count only while there are errors", function()
    local c, PE = T.new({})
    openSettings(c, PE)
    check(not tabButton(c, "errors").peCount:IsShown(), "a badge with no errors")
    PE:LogError("probe", "one")
    PE:LogError("probe", "two")
    c:advance(0.2)
    local b = tabButton(c, "errors")
    check(b.peCount:IsShown() and b.peCount:GetText() == tostring(#PE.errors), "no badge with the count")
    check(b.peBadgeDisc.texture:IsShown(), "no red disc")
    PE:ClearErrors()
    c:advance(0.2)
    check(not b.peCount:IsShown(), "the badge stays after Clear errors")
end)

test("settings: no fold buttons, no tip line, no bottom row, no Move the round button", function()
    local c, PE = T.new({ on = { "bags", "bagWindow", "chat" } })
    for _, t in ipairs(PE.SETTINGS_TABS) do
        openSettings(c, PE, t.id)
        for _, label in ipairs({ "Hide options", "Show options", "Move the round button", "Reload UI", "Errors (0)",
            "Move on screen", "Touch screen: Yes" }) do
            eq(#shownButtons(c, label), 0, t.id .. ": " .. label)
        end
        check(not shownText(c, "Tip: press and hold the round button to open this window."), t.id .. ": the tip line")
    end
end)

test("row: the control is min(58% of the row, 9 buttons) wide on the right, the name column fills the rest", function()
    for _, size in ipairs({ "small", "medium", "large" }) do
        local c, PE = T.new({})
        PE:SetUISetting("size", size)
        local UI, M = PE.UI, PE.UI:Metrics()
        for _, inner in ipairs({ 300, 700, 2000 }) do
            check(near(UI:ControlWidth(inner), math.min(inner * 0.58, M.button * 9)), size .. " " .. inner)
        end
        PE:SetModuleEnabled("sellJunk", true)
        PE:GetModule("sellJunk").options = { { label = "Do the thing", button = "Go", action = function() end } }
        openSettings(c, PE, "vendors")
        local go = shownButtons(c, "Go")[1]
        local card = switchOf(c, "sellJunk")
        local _, cardRight = c._rect(card)  -- the switch sits at the card's inner right edge
        local gl, gr = c._rect(go)
        check(near(gr, cardRight), size .. ": the control does not end at the card's inner edge")
        local inner = go:GetWidth() -- the control width
        local area = settingsPanel(c).peNavArea
        local innerWidth = area.viewWidth - 2 * M.pad
        check(near(inner, UI:ControlWidth(innerWidth)), size .. ": the control is " .. inner .. " wide")
        c:assertClean("row at " .. size)
    end
end)

test("row: at Large a long name wraps in its column and never reaches the control", function()
    local c, PE = T.new({ on = { "sellJunk" } })
    PE:SetUISetting("size", "large")
    local long = "A very long row name that cannot possibly fit on one line beside its control at this size"
    PE:GetModule("sellJunk").options = { { label = long, help = "And a help line under it, which is long as well.", action = function() end } }
    openSettings(c, PE, "vendors")
    local M = PE.UI:Metrics()
    local open = shownButtons(c, "Open")[1]
    check(open, "the action row has no Open button")
    local ol, _, ot, ob = c._rect(open)
    local name, help
    walkAll(c, settingsPanel(c), function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.text == long and r:IsVisible() then name = r end
            if st.text == "And a help line under it, which is long as well." and r:IsVisible() then help = r end
        end
    end)
    check(name and help, "the name or the help line is missing")
    local nl, nr, nt, nb = c._rect(name)
    check(nr <= ol - M.gap + 0.01, "the name reaches the control")
    check(name:GetStringHeight() > M.fontSize * 1.5, "the long name did not wrap")
    local _, _, ht = c._rect(help)
    check(ht <= nb + 0.01, "the help line is not under the name")
    -- The control is centred on the row.
    -- (a text's rectangle has no height here: its bottom is its top less its string height)
    local hb = ht - help:GetStringHeight()
    check(near((ot + ob) / 2, (nt + hb) / 2, 1), "the control is not centred on the row")
    c:assertClean("long name")
end)

test("switch: On is green with the knob on the right, Off grey with it on the left, blocked does nothing", function()
    local c, PE = T.new({ on = { "repair" } })
    openSettings(c, PE, "vendors")
    local M = PE.UI:Metrics()
    local on, off = switchOf(c, "repair"), switchOf(c, "sellJunk")
    eq({ T.labelOf(on), on.peStyle, T.labelOf(off), off.peStyle }, { "On", "on", "Off", "off" })
    check(near(on:GetWidth(), M.button * 2) and near(on:GetHeight(), M.button), "the switch is not 2 x 1 buttons")
    local knob = M.button - 4 * M.border - M.gap * 0.4
    check(near(on.peKnob:GetWidth(), knob) and near(on.peKnob:GetHeight(), knob), "the knob is not square at the spec's size")
    local sl, sr = c._rect(on)
    local kl, kr = c._rect(on.peKnob)
    check(near(sr - kr, 2 * M.border + M.gap * 0.2), "the On knob is not at the right")
    local fl = c._rect(off)
    local ol = c._rect(off.peKnob)
    check(near(ol - fl, 2 * M.border + M.gap * 0.2), "the Off knob is not at the left")
    c:click(off)
    c:advance(0.2)
    check(PE:IsModuleEnabled("sellJunk"), "a tap did not switch it on")
    eq(T.labelOf(switchOf(c, "sellJunk")), "On")
    -- Blocked: the disabled look, and a tap changes nothing.
    local sw = PE.UI:CreateSwitch(rawget(c.env, "UIParent"))
    sw:SetSwitch("blocked")
    eq({ sw.peStyle, T.labelOf(sw) }, { "disabled", "Off" })
    sw:SetSwitch("failed")
    eq({ sw.peStyle, T.labelOf(sw) }, { "warn", "Problem" })
    c:assertClean("switch")
end)

test("switch: a blocked feature's switch is disabled and a tap leaves it off", function()
    local c, PE = T.new({})
    openSettings(c, PE, "questIcons")
    local sw = switchOf(c, "questIcons")
    check(sw, "no Quest icons switch")
    if PE:GetModuleState("questIcons") == "blocked" then
        eq(sw.peStyle, "disabled")
        c:click(sw)
        c:advance(0.2)
        check(not PE:IsModuleSavedOn("questIcons"), "a tap on a blocked switch saved it on")
    end
end)

test("feature card: name, line, switch; off with options says to switch it on; on shows a divider and the rows", function()
    local c, PE = T.new({})
    openSettings(c, PE, "bags")
    check(shownText(c, "Switch it on to choose how it works."), "no hint on an off feature with options")
    eq(#shownButtons(c, "Normal"), 0, "options drawn while off")
    PE:SetModuleEnabled("bagWindow", true)
    c:advance(0.2)
    check(shownButtons(c, "Normal")[1], "no options once on")
    openSettings(c, PE, "vendors")
    check(not shownText(c, "Switch it on to choose how it works."), "the hint on a feature with no options")
end)

test("menu background: the tab starts with the heading card", function()
    local c, PE = T.new({})
    openSettings(c, PE, "menuBg")
    check(shownText(c, "Fixes for the game's own interface"), "no heading")
    check(shownText(c, "Parts of the default Blizzard UI that are hard to use on a handheld. Each fix only changes the game's window it names."),
        "no heading line")
    check(switchOf(c, "menuBg"), "no Menu background card")
end)

test("general: two cards with the core rows, I play with saves touch and moves the Sort button", function()
    local c, PE = T.new({})
    openSettings(c, PE, "general")
    for _, name in ipairs({ "Button size", "Round button colour", "I play with", "Move things on screen", "Setup guide",
        "Reload the interface" }) do
        check(shownText(c, name), "no row " .. name)
    end
    check(shownButtons(c, "Reload")[1] and #shownButtons(c, "Open") == 2, "the action buttons are wrong")
    local bags = PE:GetModule("bags")
    local changes = {}
    for _, opt in ipairs(bags.options) do
        if opt.key == "showTab" then
            local real = opt.OnChange
            opt.OnChange = function(m, v) changes[#changes + 1] = v; if real then return real(m, v) end end
        end
    end
    c:click(shownButtons(c, "Controller")[1])
    c:advance(0.2)
    eq(PE.db.ui.touch, false)
    eq(bags.opts.showTab, false)
    eq(shownButtons(c, "Controller")[1].peStyle, "segmentOn")
    c:click(shownButtons(c, "Touch controls")[1])
    c:advance(0.2)
    eq(PE.db.ui.touch, true)
    eq(bags.opts.showTab, true)
    eq(changes, { false, true })
    c:assertClean("general")
end)

test("general: Button size and Round button colour are segmented choices that save at once", function()
    local c, PE = T.new({})
    openSettings(c, PE, "general")
    c:click(shownButtons(c, "Large")[1])
    c:advance(0.2)
    eq(PE.db.ui.size, "large")
    eq(shownButtons(c, "Large")[1].peStyle, "segmentOn")
    c:click(shownButtons(c, "Horde")[1])
    c:advance(0.2)
    eq(PE.db.ui.hubColor, "horde")
end)

test("errors: the debug card and the errors card; Clear errors is dim with no errors", function()
    local c, PE = T.new({})
    openSettings(c, PE, "errors")
    check(shownText(c, "Debug log") and shownText(c, "Errors"), "a card heading is missing")
    check(shownText(c, "Save the log (reloads)") and shownText(c, "Empty the log"), "a debug row is missing")
    check(shownButtons(c, "Save")[1] and shownButtons(c, "Empty")[1], "a debug button is missing")
    check(shownText(c, "No errors recorded."), "no empty line")
    eq(shownButtons(c, "Clear errors")[1].peStyle, "disabled")
    PE:LogError("probe", "boom")
    c:advance(0.2)
    eq(shownButtons(c, "Clear errors")[1].peStyle, "normal")
    check(shownText(c, "boom"), "the error is not listed")
end)

test("icon key: an Icon key row opens the key page; Back returns to the Quest icons tab", function()
    local c, PE = T.new({ quest = true, on = { "questIcons" } })
    openSettings(c, PE, "questIcons")
    check(shownText(c, "Icon key"), "no Icon key row")
    c:click(shownButtons(c, "Open")[1])
    c:advance(0.5)
    eq({ PE:SettingsPage() }, { "questIcons", "key" })
    eq(settingsPanel(c).peTitle:GetText(), "Pocket Essentials")
    local back = shownButtons(c, "Back")[1]
    check(back and near(back:GetWidth(), PE.UI:Metrics().button * 3), "no Back button three buttons wide")
    for _, d in ipairs({ "A creature to kill.", "A creature that drops a quest item.", "An object to click, use or open.",
        "A place to go to, or someone to talk to.", "Where to hand the quest in.", "Tap an icon on the map to see what it is for." }) do
        check(shownText(c, d), "missing: " .. d)
    end
    c:click(back)
    c:advance(0.5)
    eq({ PE:SettingsPage() }, { "questIcons", "main" })
    check(shownText(c, "Icon key"), "Back did not return to the tab")
    c:assertClean("icon key")
end)

test("icon key: no row while Quest icons is off", function()
    local c, PE = T.new({ quest = true })
    openSettings(c, PE, "questIcons")
    check(not shownText(c, "Icon key"), "an Icon key row with the feature off")
end)

test("nav: Right from a tab goes to the page, Left from the first stop of a row goes back to the chosen tab", function()
    local c, PE = T.new({ on = { "bagWindow" } })
    openSettings(c, PE, "bags")
    local panel = settingsPanel(c)
    dpadKey(c, "DOWN")
    eq(panel.peNavFocus, tabButton(c, "bags"), "the first press does not land on the chosen tab")
    dpadKey(c, "DOWN")
    eq(panel.peNavFocus, tabButton(c, "vendors"), "Down does not stay in the tab column")
    dpadKey(c, "UP")
    dpadKey(c, "RIGHT")
    eq(panel.peNavFocus, switchOf(c, "bagWindow"), "Right from a tab does not go to the page's first stop")
    dpadKey(c, "DOWN")
    eq(T.labelOf(panel.peNavFocus), "Normal", "Down from the switch does not reach the first segment")
    dpadKey(c, "RIGHT")
    eq(T.labelOf(panel.peNavFocus), "Large", "Right does not move between segments")
    dpadKey(c, "LEFT")
    eq(T.labelOf(panel.peNavFocus), "Normal")
    dpadKey(c, "LEFT")
    eq(panel.peNavFocus, tabButton(c, "bags"), "Left from the first stop of a row does not go to the tab")
    -- A on a tab chooses it.
    dpadKey(c, "DOWN")
    pressA(c)
    eq(PE:SettingsPage(), "vendors")
    eq(panel.peNavFocus, tabButton(c, "vendors"), "the highlight left the tab")
    c:assertClean("nav columns")
end)

test("nav: Up and Down in the page never land on a tab", function()
    local c, PE = T.new({ on = { "bagWindow", "bags" } })
    openSettings(c, PE, "bags")
    local panel = settingsPanel(c)
    dpadKey(c, "DOWN")
    dpadKey(c, "RIGHT")
    for _ = 1, 20 do
        dpadKey(c, "DOWN")
        check(not panel.peNavFocus.peTabId, "Down went into the tabs")
    end
    for _ = 1, 20 do
        dpadKey(c, "UP")
        check(not panel.peNavFocus.peTabId, "Up went into the tabs")
    end
end)

test("nav: A on a switch keeps the highlight on that feature's switch, off to on and on to off", function()
    local c, PE = T.new({})
    openSettings(c, PE, "bags")
    local panel = settingsPanel(c)
    dpadTo(c, switchOf(c, "bags"))
    pressA(c)
    check(PE:IsModuleEnabled("bags"), "A did not switch bags on")
    check(panel.peNavFocus == switchOf(c, "bags"), "off to on: the highlight left the switch")
    eq(T.labelOf(panel.peNavFocus), "On")
    pressA(c)
    check(not PE:IsModuleEnabled("bags"), "the second A did not switch bags off again")
    check(panel.peNavFocus == switchOf(c, "bags"), "on to off: the highlight left the switch")
    eq(T.labelOf(panel.peNavFocus), "Off")
end)

test("scroll bar: a page that fits has no bar, a page that does not fit has one (touch on)", function()
    local c, PE = T.new({})
    PE:SetUISetting("touch", true)
    openSettings(c, PE, "vendors")
    local panel = settingsPanel(c)
    local area = panel.peNavArea
    check(not area.upButton:IsShown(), "a bar on a page that fits")
    for i = 1, 40 do PE:LogError("probe", "problem number " .. i .. " with a fairly long message to fill the line", "stack " .. i) end
    openSettings(c, PE, "errors")
    check(area.upButton:IsShown() and area:GetRange() > 0, "no bar on a long page")
end)

-- Spec 2026-11-17-move-things, "Hold with the controller": only a button with a peHold table
-- acts on A going down; every other button still clicks once, on A's release.
test("nav: an ordinary settings button does nothing on A down and clicks once on A up", function()
    local c, PE = T.new({})
    openSettings(c, PE, "bags")
    local panel, nav = settingsPanel(c), rawget(c.env, NAV_NAME)
    local sw = switchOf(c, "bags")
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
    openSettings(c, PE, "bags")
    local panel, nav = settingsPanel(c), rawget(c.env, NAV_NAME)
    local sw = switchOf(c, "bags")
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
-- Option rows (spec 2026-11-20-0.9.0-ui-redesign, "The option-row
-- interface"): choices (toggle or not) as segmented controls, rows with get /
-- set, help lines. Drawn on "Auto sell junk", which has no options of its own.
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

local YES_NO = { { value = true, label = "Yes" }, { value = false, label = "No" } }

local function withOptions(options, opts)
    local c, PE = T.new({ on = { "sellJunk" } })
    local mod = PE:GetModule("sellJunk")
    mod.options = options
    mod.opts = mod.opts or {}
    for k, v in pairs(opts or {}) do mod.opts[k] = v end
    openSettings(c, PE, "vendors")
    return c, PE, mod
end

test("options: a toggle row is drawn as a segmented choice, the saved part chosen, and a tap saves and runs OnChange", function()
    local calls = {}
    local c, PE, mod = withOptions({
        { key = "first", label = "First", toggle = true, choices = YES_NO,
          OnChange = function(m, v) calls[#calls + 1] = v end },
    }, { first = true })
    local M = PE.UI:Metrics()
    local yes, no = shownButtons(c, "Yes")[1], shownButtons(c, "No")[1]
    check(yes and no, "the choices are not drawn as parts")
    eq({ yes.peStyle, no.peStyle }, { "segmentOn", "segment" })
    check(yes.peBar:IsShown() and not no.peBar:IsShown(), "the gold bar is not under the chosen part")
    check(near(yes:GetWidth(), no:GetWidth()), "the parts are not equal")
    check(textRegionOf(c, "First"), "no row name")
    local _, yr, yt = c._rect(yes)
    local nl, _, nt = c._rect(no)
    check(near(yt, nt) and near(nl - yr, M.border), "the parts are not one border apart on one line")
    eq(#shownButtons(c, "First: Yes"), 0, "still drawn as the old one-button toggle")
    c:click(no)
    c:advance(0.2)
    eq(mod.opts.first, false)
    eq(calls, { false })
    eq(shownButtons(c, "No")[1].peStyle, "segmentOn")
    c:assertClean("toggle as segmented")
end)

test("options: a toggle with a damaged saved value marks no part, and a tap saves", function()
    local c, PE, mod = withOptions({
        { key = "first", label = "First", toggle = true, choices = YES_NO },
    }, { first = "yes" })
    eq({ shownButtons(c, "Yes")[1].peStyle, shownButtons(c, "No")[1].peStyle }, { "segment", "segment" })
    c:click(shownButtons(c, "No")[1])
    c:advance(0.2)
    eq(mod.opts.first, false)
    c:assertClean("damaged toggle")
end)

test("options: a row with get and set marks what get returns, and a tap goes through set", function()
    local c, PE, mod = withOptions({
        { label = "Pair", choices = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
          get = function(m) return m.opts.x end,
          set = function(m, v) m.opts.x = v; m.opts.y = v .. "!" end },
    }, { x = "a" })
    eq(shownButtons(c, "Alpha")[1].peChosen, true)
    eq(shownButtons(c, "Beta")[1].peChosen, false)
    c:click(shownButtons(c, "Beta")[1])
    c:advance(0.2)
    eq({ mod.opts.x, mod.opts.y }, { "b", "b!" })
    eq(shownButtons(c, "Beta")[1].peChosen, true)
    c:assertClean("get and set")
end)

test("options: get returning nothing marks no part, and a set that fails is recorded and saves nothing", function()
    local c, PE, mod = withOptions({
        { label = "Pair", choices = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
          get = function() return nil end,
          set = function() error("broken set") end,
          OnChange = function() error("OnChange ran after a failed set") end },
    })
    eq(shownButtons(c, "Alpha")[1].peChosen, false)
    eq(shownButtons(c, "Beta")[1].peChosen, false)
    c:click(shownButtons(c, "Alpha")[1])
    c:advance(0.2)
    local msgs = {}
    for _, e in ipairs(PE.errors) do msgs[#msgs + 1] = tostring(e.msg) end
    local joined = table.concat(msgs, "\n")
    check(joined:find("broken set", 1, true), "the failed set is not recorded")
    check(not joined:find("OnChange ran", 1, true), "OnChange ran after a failed set")
end)

test("options: the name sits left of its control on the row, a help line under the name, at every size", function()
    for _, size in ipairs({ "small", "medium", "large" }) do
        local c, PE = T.new({ on = { "sellJunk" } })
        PE:SetUISetting("size", size)
        local mod = PE:GetModule("sellJunk")
        mod.options = {
            { key = "few", label = "Few", help = "Helps.", choices = { { value = 1, label = "One" }, { value = 2, label = "Two" } } },
        }
        openSettings(c, PE, "vendors")
        local few, helpLine, one = textRegionOf(c, "Few"), textRegionOf(c, "Helps."), shownButtons(c, "One")[1]
        check(few and helpLine and one, size .. ": a piece is missing")
        local fl, fr, ft, fb = c._rect(few)
        local bl = c._rect(one)
        local _, _, ht = c._rect(helpLine)
        check(fr < bl, size .. ": the name is not left of its control")
        check(ht <= fb + 0.01, size .. ": the help line is not under the name")
        c:assertClean("row at " .. size)
    end
end)

test("options: an action row's button reads its `button` text, or Open without one, and runs the action", function()
    local ran = 0
    local c = withOptions({
        { label = "Move the arrow row", button = "Move the arrow", action = function() ran = ran + 1 end },
        { label = "Plain", action = function() ran = ran + 10 end },
    })
    check(textRegionOf(c, "Move the arrow row") and textRegionOf(c, "Plain"), "the row names are missing")
    c:click(shownButtons(c, "Move the arrow")[1])
    c:click(shownButtons(c, "Open")[1])
    eq(ran, 11)
end)

test("number: step moves by its size and stops at the ends", function()
    local c, PE = T.new({ on = { "sellJunk" } })
    local mod = PE:GetModule("sellJunk")
    mod.opts = mod.opts or {}
    mod.opts.n = 140
    mod.options = { { key = "n", label = "Scale", number = { min = 50, max = 150, step = 10, default = 100, suffix = "%", unit = "of normal" } } }
    openSettings(c, PE, "vendors")
    check(textRegionOf(c, "140%") and textRegionOf(c, "of normal"), "the value or unit is missing")
    c:click(shownButtons(c, "+")[1])
    c:advance(0.2)
    eq(mod.opts.n, 150)
    eq(shownButtons(c, "+")[1].peStyle, "stepDim")
    c:click(shownButtons(c, "-")[1])
    c:advance(0.2)
    eq(mod.opts.n, 140)
end)

test("number: the control is as wide as the row's control, the ends one button square", function()
    local c, PE = T.new({ on = { "sellJunk" } })
    local mod = PE:GetModule("sellJunk")
    mod.opts = mod.opts or {}
    mod.opts.n = 3
    mod.options = { { key = "n", label = "Count", number = { min = 1, max = 20, default = 5 } } }
    openSettings(c, PE, "vendors")
    local M = PE.UI:Metrics()
    local minus, plus = shownButtons(c, "-")[1], shownButtons(c, "+")[1]
    local ml = c._rect(minus)
    local _, pr = c._rect(plus)
    local inner = settingsPanel(c).peNavArea.viewWidth - 2 * M.pad
    check(near(pr - ml, PE.UI:ControlWidth(inner)), "the control is " .. (pr - ml) .. " wide")
    check(near(minus:GetWidth(), M.button) and near(plus:GetHeight(), M.button), "the ends are not square")
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
        openSettings(c, PE, "vendors")
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

test("touch off: the settings list is full width and the d-pad reaches the last settings button", function()
    local c, PE = T.new({})
    PE:SetUISetting("touch", false)
    openSettings(c, PE)
    local panel = settingsPanel(c)
    local area
    walkAll(c, panel, function(w) if w.upButton and w.downButton then area = w end end)
    check(area, "no scroll area")
    check(not area.upButton:IsShown(), "the bar is shown with touch off")
    local M = PE.UI:Metrics()
    eq(area.viewWidth, panel.contentWidth - M.button * 5 - M.gap, "the page is not full width")
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

local function nearColor(a, b)
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
        check(nearColor(got.ring, case[2]), case[1] .. " ring")
        check(nearColor(got.label, case[2]), case[1] .. " label")
        check(nearColor(got.fill, case[3]), case[1] .. " fill")
    end
    c:assertClean("hub themes")
end)

test("hub: the pressed colour follows the theme", function()
    local c, PE = T.new({})
    PE:SetUISetting("hubColor", "alliance")
    c:script(PE.Hub.button, "OnMouseDown", "LeftButton")
    check(nearColor(hubColors(c, PE).fill, { 0.10, 0.25, 0.55 }), "alliance pressed")
    PE:SetUISetting("hubColor", "horde")
    check(nearColor(hubColors(c, PE).fill, { 0.18, 0.03, 0.03 }) or nearColor(hubColors(c, PE).fill, { 0.45, 0.07, 0.05 }), "horde fill")
    c:assertClean("hub pressed theme")
end)

test("settings: the Button colour row has Gold, Horde and Alliance, and a tap repaints the round button", function()
    local c, PE = T.new({})
    openSettings(c, PE, "general")
    check(textRegionOf(c, "Round button colour"), "no Round button colour row")
    check(shownButtons(c, "Gold")[1] and shownButtons(c, "Alliance")[1], "buttons missing")
    press(c, "Horde")
    eq(PE.db.ui.hubColor, "horde")
    check(nearColor(hubColors(c, PE).ring, { 0.85, 0.15, 0.10 }), "ring not red")
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

-- Spec 2026-11-20-0.9.0-ui-redesign, "Option rows per feature": Quest icons.
test("quest icons: the rows in the spec's order with its labels, the haze as Hide / Show, Icon key with Open", function()
    local c, PE = T.new({ quest = true, on = { "questIcons" } })
    openSettings(c, PE, "questIcons")
    for _, name in ipairs({ "Show icons for", "Icons on", "Icon size", "Merge icons closer than", "Spots per objective",
        "Blizzard blue quest haze", "Icon key" }) do
        check(shownText(c, name), "no row " .. name)
    end
    for _, label in ipairs({ "Tracked", "Focused", "All", "Both", "Map", "Minimap", "Tiny", "Small", "Medium", "Large",
        "Hide", "Show", "Open" }) do
        check(shownButtons(c, label)[1], "no button " .. label)
    end
    local hide = shownButtons(c, "Hide")[1]
    eq(hide.peStyle, PE:GetModule("questIcons").opts.hideHaze == false and "segment" or "segmentOn")
    c:click(shownButtons(c, "Show")[1])
    c:advance(0.2)
    eq(PE:GetModule("questIcons").opts.hideHaze, false)
    c:assertClean("quest icons rows")
end)


return { known = KNOWN_FAILURES }
