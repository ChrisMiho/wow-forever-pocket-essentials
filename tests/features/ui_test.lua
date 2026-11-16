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

return { known = KNOWN_FAILURES }
