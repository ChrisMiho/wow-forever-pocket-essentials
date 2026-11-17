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
    local c, PE = T.new({ on = { "bags" } })
    openSettings(c, PE)
    eq(#shownButtons(c, "Hide options"), 1)
    check(shownButtons(c, "Normal")[1], "the options are not drawn at first")
    c:click(shownButtons(c, "Hide options")[1])
    c:advance(0.5)
    eq(#shownButtons(c, "Show options"), 1)
    eq(#shownButtons(c, "Hide options"), 0)
    eq(#shownButtons(c, "Normal"), 0, "the options are still drawn")
    check(not shownText(c, "Bag size"), "the option label is still drawn")
    check(PE:IsModuleEnabled("bags"), "folding switched the feature off")
    eq(#shownButtons(c, "ON"), 1, "the switch no longer shows ON")
    eq(PE.db.ui.folded.bags, true)
    c:assertClean("fold")
end)

test("fold: the description line is hidden when folded and comes back when unfolded", function()
    local c, PE = T.new({ on = { "bags" } })
    local desc = PE:GetModule("bags").desc
    check(type(desc) == "string" and desc ~= "", "bags has no description")
    openSettings(c, PE)
    check(shownText(c, desc), "no description at first")
    c:click(shownButtons(c, "Hide options")[1])
    c:advance(0.5)
    check(not shownText(c, desc), "the description is still drawn when folded")
    c:click(shownButtons(c, "Show options")[1])
    c:advance(0.5)
    check(shownText(c, desc), "the description did not come back")
    check(shownButtons(c, "Normal")[1], "the options did not come back")
    eq(PE.db.ui.folded.bags, nil, "unfold left the entry in the saved table")
end)

test("fold: a status line stays while folded", function()
    local c, PE = T.new({ on = { "bags" } })
    PE:GetModule("bags").status = function() return "Status stays" end
    openSettings(c, PE)
    c:click(shownButtons(c, "Hide options")[1])
    c:advance(0.5)
    check(shownText(c, "Status stays"), "the status line vanished")
end)

test("fold: the folded state is saved and still there after a reload", function()
    local c, PE = T.new({ on = { "bags" } })
    openSettings(c, PE)
    c:click(shownButtons(c, "Hide options")[1])
    c:advance(0.5)
    local db = rawget(c.env, "PocketEssentialsDB")
    local c2, PE2 = T.new({ saved = db })
    openSettings(c2, PE2)
    eq(#shownButtons(c2, "Show options"), 1)
    eq(#shownButtons(c2, "Normal"), 0)
end)

test("fold: a feature that is off, or has no options, has no fold button", function()
    local c, PE = T.new({})
    openSettings(c, PE)
    eq(#shownButtons(c, "Hide options"), 0)
    eq(#shownButtons(c, "Show options"), 0)
    local c2, PE2 = T.new({ on = { "sellJunk" } })
    PE2:GetModule("sellJunk").options = nil
    openSettings(c2, PE2)
    eq(#shownButtons(c2, "Hide options"), 0)
    local c3, PE3 = T.new({ on = { "sellJunk" } })
    PE3:GetModule("sellJunk").options = {}
    openSettings(c3, PE3)
    eq(#shownButtons(c3, "Hide options"), 0)
end)

test("fold: a folded feature that is switched off shows no fold button and no options", function()
    local c, PE = T.new({ on = { "bags" } })
    openSettings(c, PE)
    c:click(shownButtons(c, "Hide options")[1])
    c:advance(0.5)
    PE:SetModuleEnabled("bags", false)
    c:advance(0.5)
    eq(#shownButtons(c, "Show options"), 0)
    eq(#shownButtons(c, "Normal"), 0)
end)

test("fold: a damaged saved folded value does no harm and is replaced by an empty table", function()
    for _, bad in ipairs({ "yes", 5, true }) do
        local c, PE = T.new({ on = { "bags" }, saved = { version = 1, enabled = { bags = true }, options = {}, ui = { size = "medium", hubPos = "LEFT", folded = bad }, errors = {} } })
        eq(type(PE.db.ui.folded), "table")
        openSettings(c, PE)
        eq(#shownButtons(c, "Hide options"), 1)
        c:click(shownButtons(c, "Hide options")[1])
        c:advance(0.5)
        eq(PE.db.ui.folded.bags, true)
    end
    -- A non-true entry inside the table does not fold anything.
    local c, PE = T.new({ on = { "bags" }, saved = { version = 1, enabled = { bags = true }, options = {}, ui = { size = "medium", hubPos = "LEFT", folded = { bags = "yes" } }, errors = {} } })
    openSettings(c, PE)
    eq(#shownButtons(c, "Hide options"), 1)
end)

test("fold: the controller's d-pad reaches the fold button, A presses it, and the highlight stays on it", function()
    local c, PE = T.new({ on = { "bags", "sellJunk" } })
    openSettings(c, PE)
    local panel = settingsPanel(c)
    local nav = rawget(c.env, NAV_NAME)
    local fold = shownButtons(c, "Hide options")[1]
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
    local after = shownButtons(c, "Show options")[1]
    check(after, "no Show options button after folding")
    check(panel.peNavFocus == after, "the highlight left the fold button")
    -- and again the other way
    c:script(nav, "OnClick", "A", true)
    c:script(nav, "OnClick", "A", false)
    c:advance(0.5)
    eq(PE.db.ui.folded.bags, nil)
    check(panel.peNavFocus == shownButtons(c, "Hide options")[1], "the highlight left the fold button after unfolding")
    c:assertClean("fold nav")
end)

test("fold: the highlight stays on the fold button of the same feature when two features have one", function()
    local c, PE = T.new({ on = { "bags", "sellJunk" } })
    PE:GetModule("sellJunk").options = { { label = "Extra", action = function() end } }
    openSettings(c, PE)
    local panel = settingsPanel(c)
    local nav = rawget(c.env, NAV_NAME)
    local folds = shownButtons(c, "Hide options")
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
    c:click(shownButtons(c, "Hide options")[1])
    c:advance(0.5)
    c:click(shownButtons(c, "Show options")[1])
    c:advance(0.5)
    eq(debugLinesOf(c, "settings"), { "bags folded", "bags unfolded" })
end)

return { known = KNOWN_FAILURES }
