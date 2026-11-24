-- Rules for Catch all errors (ErrorCatcher.lua), the Errors tab's viewer and
-- the shared "choices grow to fit" row rule (Settings.lua, UI.lua).
-- Source: docs/superpowers/specs/2026-11-20-error-catcher-and-probe-panel.md,
-- "Shared rule (all settings rows)" and "Part 2". The game's error path is the
-- stand-in's (tests/lib/fakeclient.lua: ScriptErrorsFrame, geterrorhandler,
-- seterrorhandler, c:luaError, c:otherError, c:luaWarning).
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local NAV_NAME = "PocketEssentialsNavButton"
local HIDDEN = "(the game hides this message from addons)"
local ONLY_OURS = "Only Pocket Essentials' own errors are listed while this is off."

local function settingsPanel(c) return rawget(c.env, "PocketEssentialsSettingsPanel") end

local function walkAll(c, w, fn, seen)
    seen = seen or {}
    if seen[w] then return end
    seen[w] = true
    fn(w)
    local st = c._state(w)
    for _, ch in ipairs(st.children) do walkAll(c, ch, fn, seen) end
    if st.scrollChild then walkAll(c, st.scrollChild, fn, seen) end
end

local function shownButtons(c, label)
    local out = {}
    walkAll(c, settingsPanel(c), function(w)
        if c._state(w).type == "Button" and w:IsVisible() and T.labelOf(w) == label then out[#out + 1] = w end
    end)
    return out
end

-- The visible text regions whose text is `text` (plain) or contains it (find = true).
local function shownTexts(c, text, find)
    local out = {}
    walkAll(c, settingsPanel(c), function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and st.text and r:IsVisible()
                and (st.text == text or (find and st.text:find(text, 1, true))) then
                out[#out + 1] = r
            end
        end
    end)
    return out
end

local function shownText(c, text, find) return shownTexts(c, text, find)[1] ~= nil end

local function switchOf(c, key)
    local found
    walkAll(c, settingsPanel(c), function(w)
        if w.peSwitchState and w.peKey == key and w:IsVisible() then found = w end
    end)
    return found
end

local function openErrors(c, PE)
    PE:OpenSettings("errors")
    c:advance(0.2)
end

local function others(PE) return PE.db.otherErrors end

local function near(a, b, eps) return math.abs(a - b) < (eps or 0.01) end

-- A client with the feature switched on.
local function on(opts)
    opts = opts or {}
    opts.on = opts.on or { "errors" }
    return T.new(opts)
end

---------------------------------------------------------------------------
-- Off by default, and nothing while off
---------------------------------------------------------------------------

test("catcher: off by default, with no listener, no warning event and the popup setting untouched", function()
    local c, PE = T.new({})
    local original = c.errorBox.DisplayMessageInternal
    eq(PE:IsModuleEnabled("errors"), false)
    eq(PE:GetModule("errors").label, "Catch all errors")
    eq(PE:GetModule("errors").desc, "Keeps every Lua error, from the game and other addons, in one list.")
    check(c.errorBox.DisplayMessageInternal == original, "the error box was hooked while off")
    eq(#c:callsTo("seterrorhandler"), 0, "the error handler was replaced while off")
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: boom")
    eq(#others(PE), 0, "an error was caught while off")
    eq(c.world.cvars.scriptErrors, "1")
    for _, rec in ipairs(c:frames()) do check(not rec.events.LUA_WARNING, "LUA_WARNING registered while off") end
    c:assertClean("off")
end)

---------------------------------------------------------------------------
-- Standing aside
---------------------------------------------------------------------------

local function standAsideCase(setup, name, amber, dim)
    local c, PE = T.new({ setup = setup, saved = { enabled = { errors = true } } })
    local setBefore = #c:callsTo("seterrorhandler")
    eq(PE:IsModuleEnabled("errors"), false, name .. ": switched on beside another error addon")
    eq(PE:GetModuleState("errors"), "blocked", name)
    eq(PE:SetModuleEnabled("errors", true), false, name .. ": could be switched on")
    openErrors(c, PE)
    local sw = switchOf(c, "errors")
    check(sw, name .. ": no switch")
    eq({ T.labelOf(sw), sw.peStyle }, { "Off", "disabled" }, name .. ": the switch")
    c:click(sw)
    c:advance(0.2)
    eq(PE:IsModuleEnabled("errors"), false, name .. ": a tap switched it on")
    amber = amber or ("Off while " .. name .. " is loaded: " .. name .. " takes the errors before they reach this list.")
    dim = dim or ("To use this instead, turn " .. name .. " off in the AddOns list and restart.")
    local why = shownTexts(c, amber, true)[1]
    check(why, name .. ": no amber line")
    check(c._state(why).text:find(dim, 1, true), name .. ": no dim line under it")
    local color = c._state(why).textColor
    check(near(color[1], 1) and near(color[2], 0.60), name .. ": the line is not amber")
    check(not shownText(c, "Switch it on to choose how it works."), name .. ": the switch-on line beside a blocked switch")
    check(not shownButtons(c, "Hide")[1], name .. ": the popup row is shown")
    check(shownText(c, ONLY_OURS), name .. ": no dim line instead of the filter row")
    check(not shownButtons(c, "Blizzard")[1], name .. ": the filter row is shown")
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: boom")
    eq(#others(PE), 0, name .. ": an error was caught while standing aside")
    eq(#c:callsTo("seterrorhandler"), setBefore, name .. ": the handler was replaced")
    c:assertClean(name)
end

test("stand aside: BugSack, BugGrabber (folder or global) and Swatter each turn the feature off, with the name", function()
    standAsideCase(function(c) c.world.addons.BugSack = true end, "BugSack")
    standAsideCase(function(c) c.world.addons["!BugGrabber"] = true end, "BugGrabber")
    standAsideCase(function(c) rawset(c.env, "BugGrabber", {}) end, "BugGrabber")
    standAsideCase(function(c) c.world.addons["!Swatter"] = true end, "Swatter")
end)

local function replaceHandlerAfterUs(c)
    local f = c.env.CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function()
        local old = c.env.geterrorhandler()
        c.env.seterrorhandler(function(...) return old(...) end)
    end)
end

-- Review fix 2: a replaced handler blocks only when the fallback would be needed.
test("stand aside: a handler replaced after this addon loaded counts as another error addon only without the error box", function()
    standAsideCase(function(c)
        rawset(c.env, "ScriptErrorsFrame", nil)
        replaceHandlerAfterUs(c)
    end, "another error addon",
    -- Spec 0.15.0 A6: no name to give, so the line does not repeat one.
    "Off while another addon handles errors first.",
    "Turn that addon off in the AddOns list to use this.")
end)

test("stand aside: with the error box there, a handler chained in by another addon does not block", function()
    local c, PE = T.new({ setup = replaceHandlerAfterUs, saved = { enabled = { errors = true } } })
    eq(PE:GetModuleState("errors"), "on")
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: through the chain")
    eq(others(PE)[1].source, "ExampleAddon")
end)

-- Review fix 1: OnEnable / OnDisable never run when the feature is blocked or saved off at login.
test("popup: a Hide left in effect is put back at login when another error addon appeared or the feature is saved off", function()
    for _, case in ipairs({ "aside", "saved off" }) do
        local c, PE = T.new({
            saved = { enabled = { errors = case == "aside" }, options = { errors = { popup = "hide", oldScriptErrors = "1" } } },
            setup = function(cl)
                cl.world.cvars.scriptErrors = "0"
                if case == "aside" then cl.world.addons.BugSack = true end
            end,
        })
        eq(c.world.cvars.scriptErrors, "1", case .. ": the popup setting was not put back")
        eq(PE:GetModule("errors").opts.oldScriptErrors, nil, case .. ": the old value is still kept")
        eq(PE:GetModule("errors").opts.popup, "hide", case .. ": the choice itself was changed")
    end
    -- Saved on and free to start: OnEnable keeps it hidden.
    local c = T.new({
        saved = { enabled = { errors = true }, options = { errors = { popup = "hide", oldScriptErrors = "1" } } },
        setup = function(cl) cl.world.cvars.scriptErrors = "0" end,
    })
    eq(c.world.cvars.scriptErrors, "0")
end)

---------------------------------------------------------------------------
-- Catching and sources
---------------------------------------------------------------------------

test("sources: another addon, Blizzard, a macro and our own; locals are never kept", function()
    local c, PE = on()
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: bad argument #1 to 'pairs'")
    c:luaError("Interface/AddOns/Blizzard_GamepadSoftCursor/SoftCursor.lua:174: attempt to perform arithmetic",
        "[string \"@Interface/AddOns/Blizzard_GamepadSoftCursor/SoftCursor.lua\"]:174: in function 'Init'\n")
    c:luaError("[string \"/run x()\"]:1: attempt to call a nil value")
    local list = others(PE)
    eq(#list, 3)
    eq({ list[1].source, list[2].source, list[3].source }, { "Macro or script", "Blizzard", "ExampleAddon" })
    eq(list[3].msg, "ExampleAddon/Main.lua:40: bad argument #1 to 'pairs'", "the path is shortened")
    for _, e in ipairs(list) do
        for k, v in pairs(e) do
            check(not tostring(v):find("locals of", 1, true), "locals stored in " .. k)
        end
        eq(e.count, 1)
    end
    -- Ours goes into our own list, not the others'.
    c:luaError("Interface/AddOns/PocketEssentials/Bags.lua:10: attempt to index a nil value",
        "Interface/AddOns/PocketEssentials/Bags.lua:10: in function <...>\n")
    eq(#others(PE), 3, "our own error went into the others' list")
    eq(#PE.errors, 1, "our own error is not in our list")
    check(PE.errors[1].msg:find("PocketEssentials/Bags.lua:10", 1, true), "our own entry: " .. PE.errors[1].msg)
end)

test("sources: the source is read from the stack when the message names no file", function()
    local c, PE = on()
    c:otherError("ExampleAddon", "attempt to call a nil value")
    eq(others(PE)[1].source, "ExampleAddon")
    eq(PE.ErrorCatcher._SourceOf(nil, nil), "Unknown")
end)

test("dedupe: the same source, message and first stack line count up and move to the top", function()
    local c, PE = on()
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: boom")
    c:otherError("OtherAddon", "Interface/AddOns/OtherAddon/Main.lua:1: other")
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: boom")
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: boom")
    local list = others(PE)
    eq(#list, 2)
    eq({ list[1].source, list[1].count, list[2].source, list[2].count }, { "ExampleAddon", 3, "OtherAddon", 1 })
    -- The same message from another line is another entry.
    c:luaError("Interface/AddOns/ExampleAddon/Main.lua:40: boom", "Interface/AddOns/ExampleAddon/Other.lua:7: in function\n")
    eq(#others(PE), 3)
end)

test("cap: at most 50 others' errors, newest first; a stack keeps at most 8 lines", function()
    local c, PE = on()
    for i = 1, 60 do c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:" .. i .. ": problem " .. i) end
    local list = others(PE)
    eq(#list, 50)
    check(list[1].msg:find("problem 60", 1, true) and list[50].msg:find("problem 11", 1, true), "not the newest 50")
    local long = {}
    for i = 1, 14 do long[i] = "Interface/AddOns/Deep/File.lua:" .. i .. ": in function 'f" .. i .. "'" end
    c:luaError("Interface/AddOns/Deep/File.lua:1: deep", table.concat(long, "\n"))
    local _, lines = others(PE)[1].stack:gsub("\n", "")
    eq(lines + 1, 8, "the stack is not 8 lines")
    check(not others(PE)[1].stack:find("Interface/AddOns", 1, true), "the stack's paths are not shortened")
end)

test("cap: a saved list longer than 50, or with broken entries, is cut back at load", function()
    local saved = { otherErrors = {} }
    for i = 1, 70 do saved.otherErrors[i] = { source = "A", msg = "m" .. i, stack = "", count = 1, last = i } end
    saved.otherErrors[3] = "broken"
    local c, PE = T.new({ saved = saved })
    eq(#others(PE), 50)
    eq(others(PE)[3].msg, "m4")
end)

test("secret: a message the game hides is stored as a fixed sentence, the source read from the stack", function()
    local c, PE = on()
    local secret = "Interface/AddOns/Sneaky/Main.lua:3: a secret message"
    c.world.secrets[secret] = true
    c:otherError("Sneaky", secret)
    local e = others(PE)[1]
    eq(e.msg, HIDDEN)
    eq(e.source, "Sneaky")
    c:assertClean("secret")
end)

test("back-fill: errors from before login are listed once, and switching off and on does not count them again", function()
    local c, PE = T.new({
        saved = { enabled = { errors = true } },
        setup = function(cl) cl:otherError("EarlyAddon", "Interface/AddOns/EarlyAddon/Main.lua:1: early") end,
    })
    eq(#others(PE), 1)
    eq(others(PE)[1].source, "EarlyAddon")
    PE:SetModuleEnabled("errors", false)
    PE:SetModuleEnabled("errors", true)
    eq(others(PE)[1].count, 1, "counted again")
    -- One raised while it was off is picked up when it is switched on again.
    PE:SetModuleEnabled("errors", false)
    c:otherError("WhileOff", "Interface/AddOns/WhileOff/Main.lua:1: while off")
    PE:SetModuleEnabled("errors", true)
    eq(others(PE)[1].source, "WhileOff")
    eq(#others(PE), 2)
end)

test("warnings: LUA_WARNING is counted while on and never listed", function()
    local c, PE = on()
    c:luaWarning("Couldn't open a texture")
    c:luaWarning("Couldn't open a texture")
    eq(PE.db.luaWarnings, 2)
    eq(#others(PE), 0, "a warning was listed")
    PE:SetModuleEnabled("errors", false)
    c:luaWarning("another")
    eq(PE.db.luaWarnings, 2, "counted while off")
end)

test("fallback: without the error box a handler is chained in front, passes errors on, and is put back when off", function()
    local original
    local c, PE = T.new({ setup = function(cl)
        rawset(cl.env, "ScriptErrorsFrame", nil)
        original = cl.env.geterrorhandler()
    end })
    PE:SetModuleEnabled("errors", true)
    check(c.env.geterrorhandler() ~= original, "no handler chained in front")
    local before = #c.errorBox.errorData
    c:luaError("Interface/AddOns/ExampleAddon/Main.lua:40: chained")
    eq(others(PE)[1].source, "ExampleAddon")
    eq(#c.errorBox.errorData, before + 1, "the error was not passed on to the game's handler")
    PE:SetModuleEnabled("errors", false)
    check(c.env.geterrorhandler() == original, "the old handler was not put back")
end)

---------------------------------------------------------------------------
-- The popup and the chat line
---------------------------------------------------------------------------

test("popup: Hide sets scriptErrors to 0 and keeps the old value; Show and switching off put it back", function()
    local c, PE = on()
    openErrors(c, PE)
    check(shownText(c, "Error popup") and shownText(c, "Hidden errors still show in this list."), "no popup row")
    c:click(shownButtons(c, "Hide")[1])
    c:advance(0.2)
    eq(c.world.cvars.scriptErrors, "0")
    eq(PE:GetModule("errors").opts.oldScriptErrors, "1")
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: hidden one")
    eq(c.errorBox.shown, false, "the popup showed while hidden")
    eq(#others(PE), 1, "a hidden error is not listed")
    eq(#T.chatLines(c), 0, "a chat line while the popup is hidden")
    c:click(shownButtons(c, "Show")[1])
    c:advance(0.2)
    eq(c.world.cvars.scriptErrors, "1")
    eq(PE:GetModule("errors").opts.oldScriptErrors, nil)
    c:click(shownButtons(c, "Hide")[1])
    c:advance(0.2)
    eq(c.world.cvars.scriptErrors, "0")
    PE:SetModuleEnabled("errors", false)
    c:advance(0.2)
    eq(c.world.cvars.scriptErrors, "1", "switching off did not put it back")
    PE:SetModuleEnabled("errors", true)
    c:advance(0.2)
    eq(c.world.cvars.scriptErrors, "0", "switching on again with Hide chosen did not hide it")
    c:assertClean("popup")
end)

test("popup: a scriptErrors of 0 set by the player is put back as 0", function()
    local c, PE = T.new({ setup = function(cl) cl.world.cvars.scriptErrors = "0" end })
    PE:SetModuleEnabled("errors", true)
    PE:GetModule("errors").opts.popup = "hide"
    PE:SetModuleEnabled("errors", false)
    PE:SetModuleEnabled("errors", true)
    PE:SetModuleEnabled("errors", false)
    eq(c.world.cvars.scriptErrors, "0")
end)

test("chat: others' errors give one chat line per session", function()
    local c, PE = on()
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: one")
    c:otherError("OtherAddon", "Interface/AddOns/OtherAddon/Main.lua:2: two")
    local lines = T.chatLines(c)
    eq(#lines, 1)
    check(lines[1]:find("ExampleAddon", 1, true) and lines[1]:find("Settings > Errors", 1, true), lines[1])
end)

-- Spec 0.15.0 A6: the line reads as a sentence for a macro and for an unknown source.
test("chat: a macro's error and one from nowhere readable each give a plain sentence", function()
    local c = on()
    c:luaError("[string \"/run x()\"]:1: attempt to call a nil value")
    local lines = T.chatLines(c)
    eq(#lines, 1)
    check(lines[1]:find("An error from a macro or script was caught. See Settings > Errors.", 1, true), lines[1])
    local c2 = on()
    local msg, stack = "a hidden message", "a hidden stack"
    c2.world.secrets[msg], c2.world.secrets[stack] = true, true
    c2:luaError(msg, stack)
    lines = T.chatLines(c2)
    eq(#lines, 1)
    check(lines[1]:find("An error was caught. See Settings > Errors.", 1, true), lines[1])
    check(not lines[1]:find("Unknown", 1, true), lines[1])
end)

---------------------------------------------------------------------------
-- The viewer
---------------------------------------------------------------------------

local function threeErrors(c, PE)
    PE:LogError("bags", "our own problem", "Bags.lua:10: in function 'Sort'")
    c.now = c.now + 60
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: theirs")
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: theirs")
    c.now = c.now + 60
    c:luaError("Interface/AddOns/Blizzard_WorldMap/Map.lua:9: the game's own",
        "[string \"@Interface/AddOns/Blizzard_WorldMap/Map.lua\"]:9: in function 'A'\n")
end

local function countText(c)
    local found
    walkAll(c, settingsPanel(c), function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and st.text and st.text:match("^%d+ of %d+$") and r:IsVisible() then found = st.text end
        end
    end)
    return found
end

test("viewer: the filter row, one error per page newest first, Previous, Next, the count and Clear all", function()
    local c, PE = on()
    threeErrors(c, PE)
    openErrors(c, PE)
    for _, label in ipairs({ "All", "Pocket Essentials", "Blizzard", "Other addons", "< Previous", "Next >", "Clear all" }) do
        check(shownButtons(c, label)[1], "no button " .. label)
    end
    check(not shownText(c, ONLY_OURS), "the off line while on")
    eq(countText(c), "1 of 3")
    local source = shownTexts(c, "Blizzard")
    local gold
    for _, r in ipairs(source) do
        local col = c._state(r).textColor
        if col and near(col[1], 1) and near(col[2], 0.82) then gold = r end
    end
    check(gold, "the newest error's source is not in gold")
    check(shownText(c, "Blizzard_WorldMap/Map.lua:9: the game's own"), "the message is not shown")
    eq(shownButtons(c, "< Previous")[1].peStyle, "disabled")
    c:click(shownButtons(c, "Next >")[1])
    c:advance(0.2)
    eq(countText(c), "2 of 3")
    check(shownText(c, "ExampleAddon/Main.lua:40: theirs"), "the second error is not shown")
    check(shownText(c, "x2 · ", true), "no \"x2 · HH:MM\"")
    c:click(shownButtons(c, "Next >")[1])
    c:advance(0.2)
    eq(countText(c), "3 of 3")
    check(shownText(c, "Pocket Essentials: Bag sorting"), "our own error's source")
    eq(shownButtons(c, "Next >")[1].peStyle, "disabled")
    c:click(shownButtons(c, "Next >")[1])
    c:advance(0.2)
    eq(countText(c), "3 of 3", "Next went past the end")
    c:click(shownButtons(c, "< Previous")[1])
    c:advance(0.2)
    eq(countText(c), "2 of 3")
    -- Filters
    c:click(shownButtons(c, "Blizzard")[1])
    c:advance(0.2)
    eq(countText(c), "1 of 1")
    c:click(shownButtons(c, "Pocket Essentials")[1])
    c:advance(0.2)
    eq(countText(c), "1 of 1")
    check(shownText(c, "our own problem"), "the filter for ours")
    c:click(shownButtons(c, "Other addons")[1])
    c:advance(0.2)
    eq(countText(c), "1 of 1")
    check(shownText(c, "ExampleAddon"), "the filter for other addons")
    c:click(shownButtons(c, "All")[1])
    c:advance(0.2)
    eq(countText(c), "1 of 3")
    -- The badge counts everything listed.
    local badge
    walkAll(c, settingsPanel(c), function(w) if w.peTabId == "errors" then badge = w.peCount end end)
    eq(badge:GetText(), "3")
    c:click(shownButtons(c, "Clear all")[1])
    c:advance(0.2)
    check(shownText(c, "No errors recorded."), "Clear all did not empty the list")
    eq({ #PE.errors, #others(PE) }, { 0, 0 })
    c:assertClean("viewer")
end)

test("viewer: while off only our own errors are listed, with the dim line and no filter row", function()
    local c, PE = on()
    threeErrors(c, PE)
    PE:SetModuleEnabled("errors", false)
    openErrors(c, PE)
    check(shownText(c, ONLY_OURS), "no dim line")
    for _, label in ipairs({ "All", "Blizzard", "Other addons" }) do
        check(not shownButtons(c, label)[1], "the filter row while off: " .. label)
    end
    eq(countText(c), "1 of 1")
    check(shownText(c, "our own problem"), "our own error is not listed")
    c:click(shownButtons(c, "Clear all")[1])
    c:advance(0.2)
    eq(#PE.errors, 0)
    eq(#others(PE), 2, "Clear all while off emptied the list it does not show")
end)

test("viewer: empty shows No errors recorded.", function()
    local c, PE = on()
    openErrors(c, PE)
    check(shownText(c, "No errors recorded."), "no empty line")
    check(not shownButtons(c, "Next >")[1], "page buttons with nothing to page")
    c:assertClean("empty")
end)

test("viewer: the message shows at most 3 lines and the stack at most 6", function()
    local c, PE = on()
    local stack = {}
    for i = 1, 8 do stack[i] = "Interface/AddOns/Long/File.lua:" .. i .. ": in function 'f" .. i .. "'" end
    c:luaError("Interface/AddOns/Long/File.lua:1: " .. string.rep("a very long message ", 40), table.concat(stack, "\n"))
    openErrors(c, PE)
    local msg = shownTexts(c, "a very long message", true)[1]
    check(msg, "no message")
    eq(c._state(msg).maxLines, 3)
    local st = shownTexts(c, "Long/File.lua:1: in function", true)[1]
    check(st, "no stack")
    check(c._state(st).maxLines <= 6, "the stack may show more than 6 lines")
    check(not c._state(st).text:find("f7", 1, true), "more than 6 stack lines")
end)

test("viewer: d-pad Left and Right on Previous and Next move between errors", function()
    local c, PE = on()
    threeErrors(c, PE)
    openErrors(c, PE)
    local panel, nav = settingsPanel(c), rawget(c.env, NAV_NAME)
    local function key(k)
        c:script(nav, "OnClick", k, true)
        c:script(nav, "OnClick", k, false)
    end
    local nextButton = shownButtons(c, "Next >")[1]
    local n = 0
    repeat key("RIGHT"); n = n + 1 until panel.peNavFocus == nextButton or n > 80
    -- Getting there with Right moved the viewer on from Previous; start over from the first error.
    key("LEFT")
    key("LEFT")
    eq(countText(c), "1 of 3")
    check(T.labelOf(panel.peNavFocus) == "Next >", "the highlight left Next")
    key("RIGHT")
    eq(countText(c), "2 of 3")
    check(T.labelOf(panel.peNavFocus) == "Next >", "the highlight left Next after Right")
    key("RIGHT")
    eq(countText(c), "3 of 3")
    key("RIGHT") -- no more errors that way: the usual move
    eq(countText(c), "3 of 3")
    eq(T.labelOf(panel.peNavFocus), "Clear all")
    key("LEFT")
    eq(T.labelOf(panel.peNavFocus), "Next >")
    key("LEFT")
    eq(countText(c), "2 of 3")
    PE:ClearErrors()
    c:assertClean("d-pad")
end)

-- Spec "No scroll bar": the Errors page fits at every button size.
test("viewer: the Errors page fits with no scroll bar at Small, Medium and Large", function()
    for _, size in ipairs({ "small", "medium", "large" }) do
        for _, case in ipairs({ "on", "off", "aside" }) do
            local c, PE = T.new({
                saved = { enabled = { errors = case ~= "off" } },
                setup = function(cl) if case == "aside" then cl.world.addons.BugSack = true end end,
            })
            PE:SetUISetting("size", size)
            PE:SetUISetting("touch", true)
            local stack = {}
            for i = 1, 8 do stack[i] = "Interface/AddOns/Long/File.lua:" .. i .. ": in function 'a_rather_long_function_name_" .. i .. "'" end
            PE:LogError("bags", string.rep("our long message ", 30), table.concat(stack, "\n"))
            c:luaError("Interface/AddOns/Long/File.lua:1: " .. string.rep("a very long message ", 40), table.concat(stack, "\n"))
            openErrors(c, PE)
            local area = settingsPanel(c).peNavArea
            local where = size .. ", " .. case
            check(not area.upButton:IsShown(), where .. ": a scroll bar")
            eq(area:GetRange(), 0, where .. ": the page is longer than the window")
            check(shownButtons(c, "Clear all")[1], where .. ": no Clear all")
            -- Nothing on the page reaches below the window.
            local _, _, _, areaBottom = c._rect(area)
            for _, label in ipairs({ "< Previous", "Next >", "Clear all" }) do
                local _, _, _, b = c._rect(shownButtons(c, label)[1])
                check(b >= areaBottom - 0.5, where .. ": " .. label .. " is below the window")
            end
            -- Every page button's label fits its button.
            for _, label in ipairs({ "< Previous", "Next >", "Clear all" }) do
                local btn = shownButtons(c, label)[1]
                check(btn.peText:GetUnboundedStringWidth() <= btn:GetWidth() - PE.UI:Metrics().gap * 0.99,
                    where .. ": " .. label .. " is cut")
            end
            if case == "on" then
                for _, label in ipairs({ "All", "Pocket Essentials", "Blizzard", "Other addons" }) do
                    local part = shownButtons(c, label)[1]
                    check(part.peText:GetUnboundedStringWidth() <= part:GetWidth() - PE.UI:Metrics().gap * 0.79,
                        where .. ": the filter " .. label .. " is cut")
                end
            end
            PE:ClearErrors()
            c:assertClean(where)
        end
    end
end)

---------------------------------------------------------------------------
-- Shared rule: choices that do not fit grow wider
---------------------------------------------------------------------------

test("row rule: a choice control grows to fit its labels, up to the row less the name (at most 30%) and a gap", function()
    for _, size in ipairs({ "small", "medium", "large" }) do
        local c, PE = T.new({})
        PE:SetUISetting("size", size)
        local UI, M = PE.UI, PE.UI:Metrics()
        local inner = 600
        local usual = math.min(inner * 0.58, M.button * 9)
        eq(UI:ControlWidth(inner), usual, size .. ": no need")
        eq(UI:ControlWidth(inner, usual - 1, "Name"), usual, size .. ": a need below the usual width")
        local name = UI:TextWidth("Name", "font") + UI:Px(2)
        check(near(UI:ControlWidth(inner, inner, "Name"), inner - name - M.gap), size .. ": a short name keeps its width and a little slack")
        local long = "A very long row name that would take most of the row"
        check(near(UI:ControlWidth(inner, inner, long), inner - inner * 0.3 - M.gap), size .. ": a long name keeps at most 30%")
        check(near(UI:ControlWidth(inner, usual + 20, long), usual + 20), size .. ": grows only as far as needed")
        c:assertClean("row rule at " .. size)
    end
end)

test("row rule: no choice label is cut on the General tab and in a feature's row, at every size", function()
    for _, size in ipairs({ "small", "medium", "large" }) do
        local c, PE = T.new({ on = { "sellJunk" } })
        PE:SetUISetting("size", size)
        local M = PE.UI:Metrics()
        PE:GetModule("sellJunk").options = { { key = "probeChoice", label = "Choose one of these",
            choices = { { value = 1, label = "Touch controls" }, { value = 2, label = "Controller only" } } } }
        for _, page in ipairs({ { "general", { "Touch controls", "Controller", "Alliance", "Medium" } },
            { "vendors", { "Touch controls", "Controller only" } } }) do
            PE:OpenSettings(page[1])
            c:advance(0.2)
            for _, label in ipairs(page[2]) do
                local part = shownButtons(c, label)[1]
                check(part, size .. ": no " .. label)
                eq(part.peSmallLabel, false, size .. ": " .. label .. " needed the small font")
                check(part.peText:GetUnboundedStringWidth() <= part:GetWidth() - M.gap * 0.79, size .. ": " .. label .. " is cut")
            end
        end
        c:assertClean("row rule labels at " .. size)
    end
end)

---------------------------------------------------------------------------
-- Review fixes
---------------------------------------------------------------------------

-- Review fix 3: one press pages and leaves the highlight where it was, on either button.
test("viewer: d-pad paging keeps the highlight on the same button, Previous or Next", function()
    local c, PE = on()
    threeErrors(c, PE)
    openErrors(c, PE)
    local panel, nav = settingsPanel(c), rawget(c.env, NAV_NAME)
    local function key(k)
        c:script(nav, "OnClick", k, true)
        c:script(nav, "OnClick", k, false)
    end
    local prev = shownButtons(c, "< Previous")[1]
    local n = 0
    repeat key("RIGHT"); n = n + 1 until panel.peNavFocus == prev or n > 40
    eq(countText(c), "1 of 3")
    key("RIGHT")
    eq(countText(c), "2 of 3")
    eq(T.labelOf(panel.peNavFocus), "< Previous", "Right on Previous moved the highlight")
    check(panel.peNavFocus:IsVisible() and panel.peNavFocus.peErrorStep == -1, "the highlight is not on the shown Previous")
    key("LEFT")
    eq(countText(c), "1 of 3")
    eq(T.labelOf(panel.peNavFocus), "< Previous", "Left on Previous moved the highlight")
    PE:ClearErrors()
    c:assertClean("paging focus")
end)

-- Review fix 4: a repeat of an error already listed redraws the open viewer.
test("viewer: a repeat of a listed error shows its new count in the open viewer", function()
    local c, PE = on()
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: again")
    c:otherError("OtherAddon", "Interface/AddOns/OtherAddon/Main.lua:1: other")
    openErrors(c, PE)
    check(shownText(c, "x1 · ", true) and not shownText(c, "x2 · ", true), "x1 at first")
    -- Not the last error raised, so this goes through the merge (not the storm path)
    -- and comes to the top of the list, on the page shown.
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: again")
    c:advance(0.2)
    check(shownText(c, "ExampleAddon/Main.lua:40: again"), "the merged error is not on the first page")
    check(shownText(c, "x2 · ", true), "the viewer did not show the new count")
end)

-- Review fix 5: a storm costs one comparison per repeat; a back-filled error of ours is logged once.
test("storm: an identical repeat only counts up, with no parsing", function()
    local c, PE = on()
    local catcher = PE.ErrorCatcher
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: storm")
    local parsed = catcher._Parsed()
    for _ = 1, 50 do c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: storm") end
    eq(catcher._Parsed(), parsed, "a repeat was parsed")
    eq(others(PE)[1].count, 51)
    eq(#others(PE), 1)
    -- After Clear all the next one is a new entry.
    catcher:ClearAll()
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: storm")
    eq({ #others(PE), others(PE)[1].count }, { 1, 1 })
end)

test("back-fill: an error of ours seen 3 times before login is logged once with a count of 3", function()
    local c, PE = T.new({
        saved = { enabled = { errors = true }, debug = { on = true, lines = {}, next = 1 } },
        setup = function(cl)
            for _ = 1, 3 do
                cl:luaError("Interface/AddOns/PocketEssentials/Bags.lua:10: early of ours",
                    "Interface/AddOns/PocketEssentials/Bags.lua:10: in function <...>\n")
            end
        end,
    })
    eq(c.errorBox.errorData[1].count, 3, "the stand-in's box did not merge them (the test's premise)")
    eq(#PE.errors, 1)
    eq(PE.errors[1].count, 3)
    local logged = 0
    for _, line in ipairs(PE.db.debug.lines) do
        if line:find("core: ERROR", 1, true) then logged = logged + 1 end
    end
    eq(logged, 1, "logged more than once")
end)

-- Review fix 6: the unequal parts are only for the filter row.
test("row rule: the Button size row at Large keeps equal parts", function()
    local c, PE = T.new({})
    PE:SetUISetting("size", "large")
    PE:OpenSettings("general")
    c:advance(0.2)
    local w = {}
    for _, label in ipairs({ "Small", "Medium", "Large" }) do w[#w + 1] = shownButtons(c, label)[1]:GetWidth() end
    check(near(w[1], w[2]) and near(w[2], w[3]), "the parts are not equal: " .. table.concat(w, ", "))
    c:assertClean("equal parts")
end)

-- Review fix 7: on a narrow window Clear all never overlaps Next; the count goes first.
test("viewer: on a narrow window the bottom row never overlaps, at every size", function()
    for _, size in ipairs({ "small", "medium", "large" }) do
        for _, screen in ipairs({ { 1280, 720 }, { 900, 720 }, { 640, 720 } }) do
            local c, PE = on({ screen = screen })
            PE:SetUISetting("size", size)
            for i = 1, 12 do c:otherError("A" .. i, "Interface/AddOns/A" .. i .. "/Main.lua:1: x") end
            openErrors(c, PE)
            local where = size .. " " .. screen[1]
            local prev, nxt, clear = shownButtons(c, "< Previous")[1], shownButtons(c, "Next >")[1], shownButtons(c, "Clear all")[1]
            local pl, pr = c._rect(prev)
            local nl, nr = c._rect(nxt)
            local cl, cr = c._rect(clear)
            check(pr <= nl + 0.01, where .. ": Previous overlaps Next")
            check(nr <= cl + 0.01, where .. ": Next overlaps Clear all")
            local count = shownTexts(c, "1 of 12")[1]
            if count then
                local tl, tr = c._rect(count)
                check(tl >= pr - 0.01 and tr <= nl + 0.01, where .. ": the count overlaps a button")
            end
            local _, areaRight = c._rect(settingsPanel(c).peNavArea)
            check(cr <= areaRight + 0.01, where .. ": Clear all runs past the page")
        end
    end
end)

test("viewer: the message's height is the height of the lines that show", function()
    local c, PE = on()
    c:luaError("Interface/AddOns/Long/File.lua:1: " .. string.rep("a very long message ", 40))
    openErrors(c, PE)
    local msg = shownTexts(c, "a very long message", true)[1]
    local M = PE.UI:Metrics()
    check(msg:GetStringHeight() <= 3 * PE.UI:LineHeight("small") + 0.01, "more than three lines tall")
    eq(c._state(msg).maxLines, 3)
    check(M.smallFontSize > 0, "metrics")
end)

-- Review fix 8: no chat line while the game's popup setting is off, whoever turned it off.
test("chat: no chat line while scriptErrors is 0, even with Show chosen", function()
    local c, PE = on({ setup = function(cl) cl.world.cvars.scriptErrors = "0" end })
    eq(PE:GetModule("errors").opts.popup, "show")
    c:otherError("ExampleAddon", "Interface/AddOns/ExampleAddon/Main.lua:40: quiet")
    eq(#others(PE), 1)
    eq(#T.chatLines(c), 0)
end)

-- Review fix 9: an error that is not text (an error object) is listed through tostring.
test("sources: an error value that is not text is listed through tostring; only a secret one is hidden", function()
    local c, PE = on()
    local object = setmetatable({}, { __tostring = function() return "an error object" end })
    c:luaError(object)
    eq(others(PE)[1].msg, "an error object")
    c:luaError(42)
    eq(others(PE)[1].msg, "42")
    c:assertClean("non-string errors")
end)

return { known = KNOWN_FAILURES }
