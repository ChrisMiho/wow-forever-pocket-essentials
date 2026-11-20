-- Rules for "Loot sparkles" (LootSparkles.lua).
-- Source: docs/superpowers/specs/2026-11-20-loot-sparkles.md ("What it does",
-- "Where it shows" and "Tests"). Fresh client and addon per test.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local CVAR = "outlineModeShowLootEffectWhenDisabled"
local ON_LINE = "Quest items show the sparkle instead of the outline."
local RESTART_LINE = "Fully restart the game to remove the sparkles."

-- A client whose sparkle setting starts at `value` ("0" unless given).
local function start(opts)
    opts = opts or {}
    return T.new({
        saved = opts.saved,
        setup = function(c)
            c.world.cvars[CVAR] = opts.value or "0"
            c.world.cvars.graphicsQuality = "1"
            c.world.cvars.raidGraphicsQuality = "1"
        end,
        on = opts.on,
    })
end

-- A graphics preset change as the game does it: the preset writes its own
-- settings (which turns the sparkle off) and announces each change.
local function lowerGraphics(c)
    c.world.cvars.graphicsQuality = "0"
    c:fire("CVAR_UPDATE", "graphicsQuality", "0")
    c.world.cvars[CVAR] = "0"
    c:fire("CVAR_UPDATE", CVAR, "0")
end

-- Every frame of the client that has this event registered.
local function listeners(c, event)
    local n = 0
    for _, rec in ipairs(c:frames()) do
        if rec.events and rec.events[event] then n = n + 1 end
    end
    return n
end

local function writes(c)
    local out = {}
    for _, call in ipairs(c:callsTo("C_CVar.SetCVar")) do
        if call.args[1] == CVAR then out[#out + 1] = call.args[2] end
    end
    return out
end

local function reasonOf(PE)
    for _, r in ipairs(PE.reloadReasons) do
        if r.key == "sparkles" then return r.reason end
    end
    return nil
end

---------------------------------------------------------------------------
-- The switch
---------------------------------------------------------------------------

-- Spec "New feature": key, name, line, off by default.
test("loot sparkles: registered with the spec's name and line, off by default", function()
    local c, PE = start()
    local mod = PE:GetModule("sparkles")
    check(mod ~= nil, "the feature did not register")
    eq(mod.label, "Loot sparkles")
    eq(mod.desc, "Brings back the sparkle on things you can loot or use, even on the lowest graphics.")
    check(not PE:IsModuleEnabled("sparkles"), "the feature is on at first install")
    eq(c.world.cvars[CVAR], "0", "the setting changed with the feature off")
    eq(#writes(c), 0)
    c:assertClean()
end)

-- Spec Tests: "No events are registered while off."
test("loot sparkles: no events are registered while off, before or after being on", function()
    local c, PE = start()
    eq(listeners(c, "CVAR_UPDATE"), 0, "CVAR_UPDATE listened to while off")
    lowerGraphics(c)
    eq(#writes(c), 0, "a write with the feature off")
    PE:SetModuleEnabled("sparkles", true)
    c:advance(0.1)
    eq(listeners(c, "CVAR_UPDATE"), 1, "CVAR_UPDATE not listened to while on")
    PE:SetModuleEnabled("sparkles", false)
    c:advance(0.1)
    eq(listeners(c, "CVAR_UPDATE"), 0, "CVAR_UPDATE still listened to after switching off")
    local before = #writes(c)
    lowerGraphics(c)
    c:enterCombat()
    c:leaveCombat()
    eq(#writes(c), before, "a write after switching off")
    c:assertClean()
end)

---------------------------------------------------------------------------
-- On
---------------------------------------------------------------------------

-- Spec Tests: "Turning it on saves previous and sets the CVar to 1."
test("loot sparkles: turning it on saves previous and sets the setting to 1", function()
    local c, PE = start()
    PE:SetModuleEnabled("sparkles", true)
    c:advance(0.1)
    check(PE:IsModuleEnabled("sparkles"), "the feature did not switch on")
    eq(c.world.cvars[CVAR], "1")
    eq(PE.db.options.sparkles.previous, "0")
    eq(PE.db.enabled.sparkles, true)
    c:assertClean()
end)

-- Spec "Save the CVar's current value once ... if not already saved".
test("loot sparkles: previous is saved once and kept at the next login", function()
    local c, PE = start({ value = "1", saved = { enabled = { sparkles = true }, options = { sparkles = { previous = "0" } } } })
    check(PE:IsModuleEnabled("sparkles"), "the saved switch did not turn it on at login")
    eq(PE.db.options.sparkles.previous, "0", "previous was overwritten at login")
    eq(c.world.cvars[CVAR], "1")
    c:assertClean()
end)

-- Spec "Set it again at login".
test("loot sparkles: at login with the switch saved on, the setting is put back to 1", function()
    local c, PE = start({ value = "0", saved = { enabled = { sparkles = true }, options = { sparkles = { previous = "0" } } } })
    check(PE:IsModuleEnabled("sparkles"), "not on at login")
    eq(c.world.cvars[CVAR], "1")
    c:assertClean()
end)

-- Spec Tests: "A graphics change that resets it is undone, outside combat at once".
test("loot sparkles: a graphics change that resets it is undone at once outside a fight", function()
    local c, PE = start({ on = { "sparkles" } })
    eq(c.world.cvars[CVAR], "1")
    lowerGraphics(c)
    eq(c.world.cvars[CVAR], "1", "not set again after the graphics change")
    -- A graphics change alone (the preset announced first) is also enough.
    c.world.cvars[CVAR] = "0"
    c:fire("CVAR_UPDATE", "raidGraphicsQuality", "0")
    eq(c.world.cvars[CVAR], "1", "not set again after the raid graphics change")
    c:assertClean()
end)

-- Spec "on CVAR_UPDATE for graphicsQuality, raidGraphicsQuality or this CVar itself".
test("loot sparkles: other settings changing do not cause a write", function()
    local c, PE = start({ on = { "sparkles" } })
    local before = #writes(c)
    c.world.cvars[CVAR] = "0" -- changed behind our back, not announced
    c:fire("CVAR_UPDATE", "combinedBags", "1")
    eq(#writes(c), before, "written for another setting")
    eq(c.world.cvars[CVAR], "0")
    c:assertClean()
end)

-- Spec "when it is not 1": no write when it already is.
test("loot sparkles: no write when the setting is already 1", function()
    local c, PE = start({ value = "1" })
    PE:SetModuleEnabled("sparkles", true)
    c:fire("CVAR_UPDATE", "graphicsQuality", "3")
    eq(#writes(c), 0)
    eq(PE.db.options.sparkles.previous, "1")
    c:assertClean()
end)

-- Spec Tests: "... and in combat after combat ends."
test("loot sparkles: in a fight the write waits for the fight to end", function()
    local c, PE = start({ on = { "sparkles" } })
    c:enterCombat()
    local before = #writes(c)
    lowerGraphics(c)
    eq(c.world.cvars[CVAR], "0", "written during the fight")
    eq(#writes(c), before, "written during the fight")
    c:leaveCombat()
    eq(c.world.cvars[CVAR], "1", "not set again after the fight")
    eq(listeners(c, "CVAR_UPDATE"), 1)
    c:assertClean()
end)

-- Spec "Writes are put off while in combat": switching on during a fight.
test("loot sparkles: switched on in a fight, the setting is written after it", function()
    local c, PE = start()
    c:enterCombat()
    PE:SetModuleEnabled("sparkles", true)
    eq(c.world.cvars[CVAR], "0", "written during the fight")
    eq(PE.db.options.sparkles.previous, "0")
    c:leaveCombat()
    eq(c.world.cvars[CVAR], "1")
    c:assertClean()
end)

-- Spec "No timers and no OnUpdate".
test("loot sparkles: no timers and no OnUpdate", function()
    local c, PE = start({ on = { "sparkles" } })
    lowerGraphics(c)
    c:enterCombat()
    lowerGraphics(c)
    c:leaveCombat()
    PE:SetModuleEnabled("sparkles", false)
    local f = assert(io.open(T.addonDir .. "/LootSparkles.lua", "rb"))
    local source = f:read("*a")
    f:close()
    -- Code only: comments may name what the file does not do.
    local code = source:gsub("%-%-[^\n]*", "")
    for _, word in ipairs({ "C_Timer", ":After(", "OnUpdate", "CreateFrame" }) do
        check(not code:find(word, 1, true), "LootSparkles.lua uses " .. word)
    end
    for _, rec in ipairs(c:frames()) do
        check(not (rec.addonFile == "LootSparkles.lua"), "LootSparkles.lua made a frame")
    end
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Off
---------------------------------------------------------------------------

-- Spec Tests: "Turning it off puts previous back and shows the restart line." No reload
-- reason: "Reload now" would not remove the sparkles (owner review, 0.9.1).
test("loot sparkles: turning it off puts previous back and shows the restart line, with no reload reason", function()
    local c, PE = start({ on = { "sparkles" } })
    eq(c.world.cvars[CVAR], "1")
    PE:SetModuleEnabled("sparkles", false)
    eq(c.world.cvars[CVAR], "0")
    eq(PE.db.options.sparkles.previous, nil, "previous not cleared")
    eq(reasonOf(PE), nil, "a reload reason was asked for; a reload does not remove the sparkles")
    local mod = PE:GetModule("sparkles")
    eq(mod:status(), RESTART_LINE)
    -- On again: the blue line comes back.
    PE:SetModuleEnabled("sparkles", true)
    eq(mod:status(), ON_LINE)
    c:assertClean()
end)

-- Spec "Put the saved previous value back (or "0")".
test("loot sparkles: with nothing saved, off writes 0", function()
    local c, PE = start({ value = "1", saved = { enabled = { sparkles = true }, options = { sparkles = {} } } })
    -- previous was taken at login, so drop it to stand for an old saved file.
    PE.db.options.sparkles.previous = nil
    PE:SetModuleEnabled("sparkles", false)
    eq(c.world.cvars[CVAR], "0")
    c:assertClean()
end)

-- Spec "A blue status line while it is on"; none while off and never on.
test("loot sparkles: the status line says what is happening", function()
    local c, PE = start()
    local mod = PE:GetModule("sparkles")
    local line = mod:status()
    check(line == nil or line == "", "a status line while off and never on: " .. tostring(line))
    PE:SetModuleEnabled("sparkles", true)
    eq(mod:status(), ON_LINE)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Where it shows
---------------------------------------------------------------------------

local function walk(c, w, fn, seen)
    seen = seen or {}
    if not w or seen[w] then return end
    seen[w] = true
    fn(w)
    local st = c._state(w)
    for _, ch in ipairs(st.children) do walk(c, ch, fn, seen) end
    if st.scrollChild then walk(c, st.scrollChild, fn, seen) end
end

local function shownSwitches(c, top)
    local out = {}
    walk(c, top, function(w)
        if w.peKey and w:IsVisible() and c._state(w).type == "Button" then out[#out + 1] = w.peKey end
    end)
    return out
end

local function shownText(c, top, text)
    local found = false
    walk(c, top, function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and st.text == text and r:IsVisible() then found = true end
        end
    end)
    return found
end

-- Spec "Where it shows", Settings.
test("loot sparkles: the Game fixes tab holds the heading, Menu background, then Loot sparkles", function()
    local c, PE = start()
    local tab
    for _, t in ipairs(PE.SETTINGS_TABS) do
        if t.label == "Game fixes" then tab = t end
        check(t.label ~= "Menu background", "a tab is still called Menu background")
    end
    check(tab, "no Game fixes tab")
    eq(tab.features, { "menuBg", "sparkles" })
    check(tab.heading, "the tab lost its heading card")
    PE:OpenSettings(tab.id)
    c:advance(0.2)
    local panel = rawget(c.env, "PocketEssentialsSettingsPanel")
    check(shownText(c, panel, "Fixes for the game's own interface"), "no heading card")
    check(shownText(c, panel, "Loot sparkles"), "no Loot sparkles card")
    local keys = shownSwitches(c, panel)
    local seen = table.concat(keys, ",")
    check(seen:find("menuBg,sparkles", 1, true), "the cards are not Menu background then Loot sparkles: " .. seen)
    -- The blue line shows on the card while on, the restart line after switching off.
    PE:SetModuleEnabled("sparkles", true)
    c:advance(0.2)
    check(shownText(c, panel, ON_LINE), "no blue line on the card while on")
    PE:SetModuleEnabled("sparkles", false)
    c:advance(0.2)
    check(shownText(c, panel, RESTART_LINE), "no restart line on the card after switching off")
    c:assertClean()
end)

-- Spec "Its dot is green when either is on": the tab's features decide its dot.
test("loot sparkles: the Game fixes tab counts as on when only Loot sparkles is on", function()
    local c, PE = start({ on = { "sparkles" } })
    local tab
    for _, t in ipairs(PE.SETTINGS_TABS) do if t.label == "Game fixes" then tab = t end end
    local anyOn = false
    for _, key in ipairs(tab.features) do anyOn = anyOn or PE:IsModuleEnabled(key) end
    check(anyOn, "the tab's features do not include the one that is on")
    c:assertClean()
end)

-- Spec "Where it shows", Setup guide.
test("loot sparkles: the Vendors and game fixes screen holds four cards and no How: line", function()
    local c, PE = start()
    check(PE.Setup:Open("settings") == true, "the setup guide did not open")
    c:advance(0.1)
    local guide = rawget(c.env, "PocketEssentialsSetupPanel")
    for _ = 1, 10 do
        if shownText(c, guide, "Vendors and game fixes") then break end
        local nextBtn
        walk(c, guide, function(w)
            if c._state(w).type == "Button" and w:IsVisible() and w.GetLabel
                    and (w:GetLabel() == "Start" or w:GetLabel() == "Next") then nextBtn = w end
        end)
        c:click(nextBtn)
        c:advance(0.1)
    end
    check(shownText(c, guide, "Vendors and game fixes"), "no Vendors and game fixes screen")
    eq(shownSwitches(c, guide), { "sellJunk", "repair", "menuBg", "sparkles" })
    walk(c, guide, function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and r:IsVisible() and type(st.text) == "string" then
                check(not st.text:find("How: ", 1, true), "a How: line on the screen: " .. st.text)
            end
        end
    end)
    check(shownText(c, guide, "Brings back the sparkle on things you can loot or use, even on the lowest graphics."),
        "no one-line description on the Loot sparkles card")
    c:assertClean()
end)

return { known = KNOWN_FAILURES }
