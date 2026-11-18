-- Rules for the setup guide (Setup.lua).
-- Source: docs/superpowers/specs/2026-11-17-0.4.0-handheld-batch.md, section
-- "5. Setup guide" ("What the player sees", "Rules", "Debug-log lines") and its
-- "Rulings"; the plan's test list in
-- docs/superpowers/plans/2026-11-17-0.4.0-handheld-batch.md (Task 5, 2.9).
-- Fresh client and addon per test. Tests that need the guide to open by itself
-- pass firstRun = true to T.new (without it T.new marks setup as skipped).
--
-- The stand-in cannot make the game fail to load the saved settings, so that
-- rule is tested by swapping PE.db for another table, which is what Core.lua's
-- EnsureDB leaves behind in that case.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local NAV_NAME = "PocketEssentialsNavButton"
local ALL_KEYS = { PADDUP = NAV_NAME, PADDDOWN = NAV_NAME, PADDLEFT = NAV_NAME, PADDRIGHT = NAV_NAME, PAD1 = NAV_NAME, PAD2 = NAV_NAME }
local TITLE = "Pocket Essentials - Setup guide"
local ALL_SCREENS = { "Welcome to Pocket Essentials", "Quests", "Bags", "Vendors", "Chat",
    "The round button and moving things", "All set" }

local function guide(c) return rawget(c.env, "PocketEssentialsSetupPanel") end
local function settingsPanel(c) return rawget(c.env, "PocketEssentialsSettingsPanel") end
local function chatPanel(c) return rawget(c.env, "PocketEssentialsChatPanel") end
local function nav(c) return rawget(c.env, NAV_NAME) end
local function isOpen(c) return guide(c) ~= nil and guide(c):IsShown() end
local function bindings(c) return c._state(guide(c)).bindings end
local function title(c) return guide(c).peTitle:GetText() end

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

local function has(c, label) return #shownButtons(c, guide(c), label) > 0 end

local function button(c, label)
    local list = shownButtons(c, guide(c), label)
    check(#list == 1, "expected one shown button '" .. label .. "' in the setup guide, found " .. #list, 2)
    return list[1]
end

-- Next under whichever name it has on this screen.
local function nextButton(c)
    for _, label in ipairs({ "Start", "Next", "Finish" }) do
        local list = shownButtons(c, guide(c), label)
        if #list == 1 then return list[1] end
    end
    error("no Start / Next / Finish button in the setup guide", 2)
end

-- The visible texts of the guide that are not button labels.
local function texts(c)
    local out = {}
    walk(c, guide(c), function(w)
        if c._state(w).type ~= "Button" then
            for _, r in ipairs(c._state(w).regions) do
                local st = c._state(r)
                if st.type == "FontString" and st.text and st.text ~= "" and r:IsVisible() then out[#out + 1] = st.text end
            end
        end
    end)
    return out
end

local function hasText(c, text)
    for _, t in ipairs(texts(c)) do
        if t == text then return true end
    end
    return false
end

local function textWith(c, part)
    for _, t in ipairs(texts(c)) do
        if t:find(part, 1, true) then return t end
    end
    return nil
end

-- The switch of one feature on the screen that is showing.
local function switch(c, key)
    local found
    for _, b in ipairs(shownButtons(c, guide(c))) do
        if b.peKey == key then
            check(found == nil, "two switches for " .. key, 2)
            found = b
        end
    end
    check(found, "no switch for " .. key .. " on this screen", 2)
    return found
end

local function open(c, PE, how)
    check(PE.Setup:Open(how or "settings") == true, "the setup guide did not open", 2)
    c:advance(0.1)
    check(isOpen(c), "the setup guide is not shown", 2)
end

-- From the first screen to screen n.
local function goTo(c, n)
    for _ = 2, n do
        c:click(nextButton(c))
        c:advance(0.1)
    end
end

local function press(c, key)
    c:script(nav(c), "OnClick", key, true)
    c:script(nav(c), "OnClick", key, false)
end

local function linesWith(c, text)
    local n = 0
    for _, line in ipairs(T.chatLines(c)) do
        if line:find(text, 1, true) then n = n + 1 end
    end
    return n
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

local function saved(enabled, setup)
    return { version = 1, enabled = enabled or {}, options = {}, ui = { size = "medium", hubPos = "LEFT" }, errors = {}, setup = setup }
end

---------------------------------------------------------------------------
-- Opening by itself (rule 1, rule 6)
---------------------------------------------------------------------------

test("setup: opens by itself after the first loading screen on a fresh install", function()
    local c, PE = T.new({ firstRun = true })
    check(guide(c) == nil, "the guide was built at load")
    c:advance(1)
    check(guide(c) == nil, "the guide opened before the loading screen had settled")
    c:advance(1)
    check(isOpen(c), "the guide did not open by itself")
    eq(title(c), TITLE .. " (1 of 7)")
    check(hasText(c, "Welcome to Pocket Essentials"), "the first screen is not Welcome")
    button(c, "Skip"); button(c, "Start")
    check(not has(c, "Back"), "Back is on the first screen")
    eq(PE.db.setup, nil)
    eq(PE.db.enabled, {})
    c:assertClean("first run")
end)

test("setup: does not open when setup was finished or skipped before", function()
    for _, value in ipairs({ "finished", "skipped" }) do
        local c, PE = T.new({ firstRun = true, saved = saved({}, value) })
        c:advance(3)
        check(guide(c) == nil, "the guide opened although setup was " .. value)
        eq(PE.db.setup, value)
        c:assertClean(value)
    end
end)

test("setup: a damaged saved value counts as never seen", function()
    for _, bad in ipairs({ 7, {}, "yes", true }) do
        local c, PE = T.new({ firstRun = true, saved = saved({}, bad) })
        c:advance(2)
        check(isOpen(c), "the guide did not open with setup saved as " .. T.show(bad))
        eq(PE.Setup:Seen(), nil)
        c:assertClean("damaged value")
    end
end)

test("setup: waits for the end of a fight at login", function()
    local c, PE = T.new({ firstRun = true, setup = function(c) c.world.inCombat = true end })
    c:advance(3)
    check(not isOpen(c), "the guide opened during a fight")
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not open when the fight ended")
    eq(title(c), TITLE .. " (1 of 7)")
    eq(bindings(c), ALL_KEYS, "the controller keys were not taken")
    c:assertClean("fight at login") -- a binding call in a fight would be recorded as blocked
end)

test("setup: opens once per login, not again after it was closed", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    check(isOpen(c), "the guide did not open by itself")
    press(c, "B")
    check(not isOpen(c), "B did not close the guide")
    c:advance(5)
    c:fire("PLAYER_ENTERING_WORLD", false, false)
    c:advance(3)
    check(not isOpen(c), "the guide opened a second time in one login")
    eq(PE.db.setup, nil)
    c:assertClean("once per login")
end)

test("setup: existing settings are kept and shown", function()
    local c, PE = T.new({ firstRun = true, saved = saved({ sellJunk = true, chat = true }) })
    c:advance(2)
    check(isOpen(c), "an existing player did not get the guide once")
    goTo(c, 4)
    check(hasText(c, "Vendors"), "screen 4 is not Vendors")
    eq(T.labelOf(switch(c, "sellJunk")), "ON")
    eq(T.labelOf(switch(c, "repair")), "OFF")
    goTo(c, 2)
    eq(T.labelOf(switch(c, "chat")), "ON")
    c:click(button(c, "Skip"))
    eq(PE.db.enabled, { sellJunk = true, chat = true })
    eq(PE.db.setup, "skipped")
    c:assertClean("existing player")
end)

---------------------------------------------------------------------------
-- Screens and switches (rules 5 and 7)
---------------------------------------------------------------------------

test("setup: the screens are welcome, quests, bags, vendors, chat, layout, finish", function()
    local c, PE = T.new({})
    open(c, PE)
    local headings = {}
    for i = 1, 7 do
        eq(title(c), TITLE .. " (" .. i .. " of 7)")
        for _, name in ipairs(ALL_SCREENS) do
            if hasText(c, name) then headings[#headings + 1] = name end
        end
        eq(has(c, "Back"), i > 1, "Back on screen " .. i)
        eq(has(c, "Skip"), i < 7, "Skip on screen " .. i)
        eq(T.labelOf(nextButton(c)), i == 1 and "Start" or i == 7 and "Finish" or "Next")
        if i < 7 then goTo(c, 2) end
    end
    eq(headings, ALL_SCREENS)
    eq(nextButton(c).peStyle, "on", "Finish is not green")
    c:click(button(c, "Back"))
    c:advance(0.1)
    eq(title(c), TITLE .. " (6 of 7)")
    c:assertClean("screens")
end)

test("setup: every feature of this build has a switch on some screen, and the new choices are explained", function()
    local c, PE = T.new({})
    open(c, PE)
    local seen = {}
    local all = {}
    for i = 1, 7 do
        for _, b in ipairs(shownButtons(c, guide(c))) do
            if b.peKey then seen[b.peKey] = (seen[b.peKey] or 0) + 1 end
        end
        for _, t in ipairs(texts(c)) do all[#all + 1] = t end
        if i == 2 then switch(c, "menuBg") end -- the ruling: Menu background sits on the Quests screen
        if i < 7 then goTo(c, 2) end
    end
    for _, mod in ipairs(PE.moduleList) do
        eq(seen[mod.key], 1, "switches for " .. mod.key)
    end
    local joined = table.concat(all, "\n")
    for _, part in ipairs({ "D-pad to Sort", "Bag icons", "One row at the top", "Chat text size", "Smaller and Bigger" }) do
        check(joined:find(part, 1, true), "no screen mentions \"" .. part .. "\"")
    end
    -- Review of 0.4.0, point 7: A on the Sort tab is not device-tested, so it is not stated as fact.
    check(not joined:find("then A to sort", 1, true), "the Bags screen promises that A sorts")
    check(joined:find("then A should press it (this is new and untested; if A does nothing, tap it)", 1, true),
        "the Bags screen does not say that A on the Sort button is untested")
end)

test("setup: a switch calls the same path as the settings switch", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, 4)
    c:click(switch(c, "sellJunk"))
    c:advance(0.1)
    check(PE:IsModuleEnabled("sellJunk"), "the switch did not turn Sell junk on")
    eq(PE.db.enabled.sellJunk, true)
    eq(T.labelOf(switch(c, "sellJunk")), "ON")
    eq(switch(c, "sellJunk").peStyle, "on")
    eq(T.labelOf(switch(c, "repair")), "OFF")
    c:click(switch(c, "sellJunk"))
    c:advance(0.1)
    check(not PE:IsModuleEnabled("sellJunk"), "the switch did not turn Sell junk off")
    eq(PE.db.enabled.sellJunk, false)
    eq(T.labelOf(switch(c, "sellJunk")), "OFF")
    c:click(switch(c, "repair"))
    c:advance(0.1)
    -- the settings window shows the same
    PE:OpenSettings()
    c:advance(0.2)
    check(not isOpen(c), "the guide stayed open under the settings")
    local on, off = 0, 0
    for _, b in ipairs(shownButtons(c, settingsPanel(c))) do
        if T.labelOf(b) == "ON" then on = on + 1 elseif T.labelOf(b) == "OFF" then off = off + 1 end
    end
    eq(on, 1, "switches reading ON in the settings")
    check(PE:IsModuleEnabled("repair") and not PE:IsModuleEnabled("sellJunk"), "the wrong feature is on")
    c:assertClean("switch")
end)

test("setup: a feature switched on in the settings shows ON in the guide", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, 4)
    eq(T.labelOf(switch(c, "repair")), "OFF")
    PE:SetModuleEnabled("repair", true)
    c:advance(0.1)
    eq(T.labelOf(switch(c, "repair")), "ON")
    c:assertClean("redraw hook")
end)

test("setup: quest switches are dimmed with the reason when QuestieDB is missing", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, 2)
    local state, reason = PE:GetModuleState("questIcons")
    eq(state, "blocked")
    check(type(reason) == "string" and reason:find("QuestieDB", 1, true), "no reason for the blocked quest features")
    for _, key in ipairs({ "questIcons", "questArrow" }) do
        eq(T.labelOf(switch(c, key)), "OFF")
        eq(switch(c, key).peStyle, "disabled")
        c:click(switch(c, key))
        c:advance(0.1)
        check(not PE:IsModuleSavedOn(key), "a tap on a dimmed switch saved " .. key .. " as on")
    end
    local count = 0
    for _, t in ipairs(texts(c)) do
        if t == reason then count = count + 1 end
    end
    eq(count, 2, "the amber reason under each quest switch")
    -- Menu background does not need QuestieDB
    eq(switch(c, "menuBg").peStyle, "off")
    c:click(switch(c, "menuBg"))
    c:advance(0.1)
    check(PE:IsModuleEnabled("menuBg"), "Menu background did not switch on")
    eq(T.labelOf(switch(c, "menuBg")), "ON")
    c:assertClean("blocked switches")
end)

test("setup: a row whose feature is not registered is left out, and an empty screen is skipped", function()
    -- a copy of the addon whose TOC leaves Vendor.lua out
    local dir = (os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "") .. "/pe-setup-test-" .. tostring(os.time()) .. "-" .. tostring(math.random(1e6))
    local function sh(cmd) return os.execute(cmd) end
    sh("mkdir -p '" .. dir .. "' && cp -R '" .. T.addonDir .. "/.' '" .. dir .. "/'")
    local ok, err = pcall(function()
        local path = dir .. "/PocketEssentials.toc"
        local f = assert(io.open(path, "rb"))
        local toc = f:read("*a")
        f:close()
        local changed, n = toc:gsub("Vendor%.lua\r?\n", "")
        eq(n, 1, "Vendor.lua lines in the TOC")
        f = assert(io.open(path, "wb"))
        f:write(changed)
        f:close()
        local c, PE = T.new({ addonDir = dir })
        check(PE:GetModule("sellJunk") == nil and PE:GetModule("repair") == nil, "the vendor features still registered")
        open(c, PE)
        local headings = {}
        for i = 1, 6 do
            eq(title(c), TITLE .. " (" .. i .. " of 6)")
            for _, name in ipairs(ALL_SCREENS) do
                if hasText(c, name) then headings[#headings + 1] = name end
            end
            if i < 6 then goTo(c, 2) end
        end
        eq(headings, { "Welcome to Pocket Essentials", "Quests", "Bags", "Chat", "The round button and moving things", "All set" })
        eq(T.labelOf(nextButton(c)), "Finish")
        c:assertClean("a build without the vendor features")
    end)
    if dir:find("pe-setup-test-", 1, true) then sh("rm -rf '" .. dir .. "'") end
    if not ok then error(err, 0) end
end)

test("setup: the finish screen lists what is on and what is off", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, 7)
    check(hasText(c, "Nothing is switched on yet. That is fine: you can do it later in the settings."),
        "no \"nothing is on\" sentence")
    local off = textWith(c, "Still off:")
    check(off, "no Still off line with everything off")
    for _, mod in ipairs(PE.moduleList) do
        check(off:find(mod.label, 1, true), "Still off does not name " .. mod.label)
    end
    check(not textWith(c, "Switched on:"), "a Switched on line with nothing on")

    PE:SetModuleEnabled("sellJunk", true)
    PE:SetModuleEnabled("chat", true)
    c:advance(0.1)
    check(hasText(c, "Switched on: Sell junk automatically, Big chat buttons."), "the Switched on line is wrong: "
        .. tostring(textWith(c, "Switched on:")))
    eq(textWith(c, "Still off:"), "Still off: Quest icons, Quest arrow, Bag sorter, Repair automatically, Menu background.")
    check(textWith(c, "\"Setup guide\" button at the bottom of the settings"), "no closing paragraph")
    check(not has(c, "Reload now"), "a reload is offered although nothing asked for one")
    c:assertClean("finish screen")
end)

test("setup: with every feature on the finish screen has no Still off line", function()
    if not T.questieDB then return end -- the quest features cannot be on without QuestieDB
    local c, PE = T.new({ quest = true, gamepadUI = true })
    for _, mod in ipairs(PE.moduleList) do PE:SetModuleEnabled(mod.key, true) end
    c:advance(0.5)
    open(c, PE)
    goTo(c, 7)
    check(textWith(c, "Switched on: Quest icons, Quest arrow, Bag sorter"), "no Switched on line")
    check(not textWith(c, "Still off:"), "a Still off line with everything on")
end)

test("setup: the finish screen offers a reload when a feature asked for one", function()
    local c, PE = T.new({ gamepadUI = false, setup = function(c) c.world.cvars.combinedBags = "0" end })
    open(c, PE)
    goTo(c, 3)
    c:click(switch(c, "bags"))
    c:advance(0.2)
    check(#PE.reloadReasons > 0, "Bag sorter asked for no reload (the test's premise)")
    goTo(c, 5)
    eq(title(c), TITLE .. " (7 of 7)")
    check(textWith(c, "Bag sorter: "), "the reason for the reload is not shown")
    local before = #c:callsTo("C_UI.Reload")
    eq(PE.db.setup, "skipped") -- what T.new stored
    PE.db.setup = nil
    c:click(button(c, "Reload now"))
    eq(#c:callsTo("C_UI.Reload") - before, 1, "Reload now called C_UI.Reload")
    eq(PE.db.setup, "finished", "the reload did not store Finish first")
    c:assertClean("reload offer")
end)

-- Review of 0.4.0, point 3: the click runs inside PE:Safe, so an error in it lands on our
-- Errors page and never reaches the game; Finish is still stored first (rule 11).
test("setup: an error under Reload now does not escape the click, and Finish is already stored", function()
    local c, PE = T.new({ gamepadUI = false, setup = function(c) c.world.cvars.combinedBags = "0" end })
    open(c, PE)
    goTo(c, 3)
    c:click(switch(c, "bags"))
    c:advance(0.2)
    goTo(c, 5)
    PE.db.setup = nil
    local reload = PE.ReloadNow
    local called = 0
    PE.ReloadNow = function()
        called = called + 1
        error("reload broke")
    end
    local before = #PE.errors
    c:click(button(c, "Reload now"))
    PE.ReloadNow = reload
    eq(called, 1, "the reload was not asked for straight from the click")
    eq(c.errors, {}, "the error reached the game's error list")
    eq(#PE.errors - before, 1, "the error was not recorded on the Errors page")
    eq(PE.db.setup, "finished", "Finish was not stored before the reload")
end)

---------------------------------------------------------------------------
-- Closing and remembering (rule 2)
---------------------------------------------------------------------------

test("setup: Finish remembers \"finished\" and closes", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    goTo(c, 7)
    c:click(button(c, "Finish"))
    check(not isOpen(c), "Finish did not close the guide")
    eq(PE.db.setup, "finished")
    eq(rawget(c.env, "PocketEssentialsDB").setup, "finished", "not in the saved table")
    eq(linesWith(c, "Setup guide closed"), 0)
    eq(bindings(c), nil)
    c:assertClean("finish")
end)

test("setup: Skip remembers \"skipped\" and closes", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    c:click(button(c, "Skip"))
    check(not isOpen(c), "Skip did not close the guide")
    eq(PE.db.setup, "skipped")
    eq(PE.db.enabled, {})
    eq(linesWith(c, "Setup guide closed"), 0)
    c:assertClean("skip")
end)

test("setup: Close, B and another window hide it without remembering, with one chat line", function()
    local closers = {
        Close = function(c, PE) c:click(button(c, "Close")) end,
        B = function(c, PE) press(c, "B") end,
        ["another window"] = function(c, PE) PE:OpenSettings() end,
    }
    for name, close in pairs(closers) do
        local c, PE = T.new({ firstRun = true })
        c:advance(2)
        check(isOpen(c), "the guide did not open by itself")
        close(c, PE)
        c:advance(0.1)
        check(not isOpen(c), name .. " did not hide the guide")
        eq(PE.db.setup, nil, name .. " was remembered")
        eq(linesWith(c, "Setup guide closed. It will show again next time you log in. Press Skip in it to stop that. "
            .. "You can open it any time from the settings."), 1, "chat lines after " .. name)
        PE:CloseSettings()
        open(c, PE)
        c:click(button(c, "Close"))
        eq(linesWith(c, "Setup guide closed"), 1, "the chat line came twice in one session")
        eq(PE.db.setup, nil)
        c:assertClean(name)
    end
end)

test("setup: once finished, a later Skip does not change it to skipped", function()
    local c, PE = T.new({ saved = saved({}, "finished") })
    open(c, PE)
    c:click(button(c, "Skip"))
    check(not isOpen(c), "Skip did not close the guide")
    eq(PE.db.setup, "finished")
    -- and Close after Finish says nothing in chat
    open(c, PE)
    c:click(button(c, "Close"))
    eq(linesWith(c, "Setup guide closed"), 0)
end)

test("setup: the game closing its windows does not count as a skip", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    guide(c):Hide() -- what the game's CloseAllWindows does to every window in UISpecialFrames
    c:advance(0.1)
    eq(PE.db.setup, nil)
    eq(bindings(c), nil, "the controller keys were kept")
    local listed = false
    for _, name in ipairs(rawget(c.env, "UISpecialFrames")) do
        if name == "PocketEssentialsSetupPanel" then listed = true end
    end
    check(listed, "the guide is not in UISpecialFrames (Escape would not close it)")
    c:assertClean("closed by the game")
end)

test("setup: the answer is not saved when the saved settings did not load", function()
    local c, PE = T.new({ firstRun = true })
    -- what Core.lua's EnsureDB leaves when the saved table could not be used
    local real = PE.db
    PE.db = { version = 1, enabled = {}, options = {}, ui = real.ui, errors = PE.errors }
    c:advance(3)
    check(not isOpen(c), "the guide opened by itself although the answer could not be kept")
    open(c, PE)
    c:click(button(c, "Skip"))
    eq(PE.db.setup, nil, "an answer was written to the stand-in table")
    eq(real.setup, nil)
    c:assertClean("stand-in settings")
end)

---------------------------------------------------------------------------
-- Reopening (rule 3)
---------------------------------------------------------------------------

test("setup: the settings' bottom row has Setup guide after Move things; it closes the settings and opens the guide at screen 1", function()
    local c, PE = T.new({})
    PE:OpenSettings()
    c:advance(0.2)
    local settings = settingsPanel(c)
    local setupBtn = shownButtons(c, settings, "Setup guide")
    local moveBtn = shownButtons(c, settings, "Move things")
    eq(#setupBtn, 1, "Setup guide buttons in the settings")
    eq(#moveBtn, 1)
    local mx, my = moveBtn[1]:GetCenter()
    local sx, sy = setupBtn[1]:GetCenter()
    check(sx > mx or sy < my, "Setup guide is not after Move things")
    c:click(setupBtn[1])
    c:advance(0.2)
    check(not settings:IsShown(), "the settings stayed open")
    check(isOpen(c), "the guide did not open")
    eq(title(c), TITLE .. " (1 of 7)")
    -- reopened from the middle: back at the first screen
    goTo(c, 3)
    PE:OpenSettings()
    c:advance(0.2)
    c:click(shownButtons(c, settings, "Setup guide")[1])
    c:advance(0.2)
    eq(title(c), TITLE .. " (1 of 7)")
    c:assertClean("open from settings")
end)

test("setup: /pe setup opens it", function()
    local c, PE = T.new({})
    local slash = rawget(c.env, "SlashCmdList").POCKETESSENTIALS
    c._protect("/pe setup", slash, "setup")
    c:advance(0.1)
    check(isOpen(c), "/pe setup did not open the guide")
    check(not (settingsPanel(c) and settingsPanel(c):IsShown()), "/pe setup opened the settings")
    c._protect("/pe SETUP", slash, "  SETUP ")
    c:advance(0.1)
    check(isOpen(c), "/pe SETUP closed the guide")
    c:assertClean("/pe setup")
end)

test("setup: cannot be opened by hand in a fight; it says so in chat", function()
    local c, PE = T.new({})
    c:enterCombat()
    eq(PE.Setup:Open("settings"), false)
    eq(PE.Setup:Open("slash"), false)
    check(not isOpen(c), "the guide opened in a fight")
    eq(linesWith(c, "The setup guide cannot be opened during a fight. Try again afterwards."), 2)
    c:leaveCombat()
    c:advance(0.5)
    check(not isOpen(c), "a refused opening came back after the fight")
    c:assertClean("refused in a fight")
end)

test("setup: opening the settings closes the guide", function()
    local c, PE = T.new({})
    open(c, PE)
    PE:OpenSettings()
    c:advance(0.1)
    check(not isOpen(c), "the guide stayed open")
    check(settingsPanel(c):IsShown(), "the settings did not open")
    open(c, PE)
    check(not settingsPanel(c):IsShown(), "the settings stayed open under the guide")
    c:assertClean("settings and guide")
end)

test("setup: opening the chat picker closes the guide", function()
    local c, PE = T.new({ on = { "chat" } })
    open(c, PE)
    c:click(PE.Hub.button)
    c:advance(0.2)
    check(chatPanel(c) and chatPanel(c):IsShown(), "the chat picker did not open")
    check(not isOpen(c), "the guide stayed open under the chat picker")
    open(c, PE)
    check(not chatPanel(c):IsShown(), "the chat picker stayed open under the guide")
    c:assertClean("chat picker and guide")
end)

---------------------------------------------------------------------------
-- Fights (rule 4)
---------------------------------------------------------------------------

test("setup: a fight starting hides it; it comes back at the same screen afterwards", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    goTo(c, 3)
    eq(title(c), TITLE .. " (3 of 7)")
    c:enterCombat()
    check(not isOpen(c), "the guide stayed on screen in a fight")
    eq(bindings(c), nil, "the controller keys were kept in a fight")
    eq(PE.db.setup, nil, "a fight counted as an answer")
    eq(linesWith(c, "Setup guide closed"), 0, "a fight printed the closed line")
    c:advance(2)
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    eq(title(c), TITLE .. " (3 of 7)")
    check(hasText(c, "Bags"), "it came back at another screen")
    eq(bindings(c), ALL_KEYS)
    -- only once: a second fight end does nothing more
    c:click(button(c, "Skip"))
    c:enterCombat(); c:leaveCombat()
    c:advance(0.2)
    check(not isOpen(c), "the guide came back after Skip")
    c:assertClean("fight")
end)

test("setup: it does not come back after a fight if another window was opened meanwhile", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, 2)
    c:enterCombat()
    check(not isOpen(c), "the guide stayed on screen in a fight")
    PE:OpenSettings()
    c:leaveCombat()
    c:advance(0.2)
    check(not isOpen(c), "the guide came back over the settings")
    check(settingsPanel(c):IsShown(), "the settings were closed")
    PE:CloseSettings()
    c:enterCombat(); c:leaveCombat()
    c:advance(0.2)
    check(not isOpen(c), "the guide came back after a later fight")
    c:assertClean("fight with another window")
end)

-- Review of 0.4.0, point 2 (rule 12): the game hides its whole interface for a cinematic or a
-- full-screen view. The guide's OnHide runs although the guide itself is still "shown"; that is
-- not a closing. When the interface comes back the guide is on the screen again and must hide
-- for a fight as before.
test("setup: the game hiding its whole interface is not a closing; back on screen, a fight still hides the guide", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    goTo(c, 3)
    c.UIParent:Hide()
    c:advance(0.1)
    check(guide(c):IsShown() and not guide(c):IsVisible(), "the test's premise: shown, but not on the screen")
    eq(linesWith(c, "Setup guide closed"), 0, "the closed line was printed")
    eq(PE.db.setup, nil)
    c.UIParent:Show()
    c:advance(0.1)
    check(guide(c):IsVisible(), "the guide did not come back with the interface")
    eq(title(c), TITLE .. " (3 of 7)")
    eq(bindings(c), ALL_KEYS)
    c:enterCombat()
    check(not isOpen(c), "the guide stayed on screen in a fight after the interface came back")
    eq(linesWith(c, "Setup guide closed"), 0, "a fight printed the closed line")
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    eq(title(c), TITLE .. " (3 of 7)")
    -- a real closing still says its line, once
    c:click(button(c, "Close"))
    eq(linesWith(c, "Setup guide closed"), 1)
    eq(PE.db.setup, nil)
    eq(c.blocked, {})
    c:assertClean("interface hidden")
end)

test("setup: a fight that starts while the interface is hidden hides the guide when it comes back, until the fight ends", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    goTo(c, 2)
    c.UIParent:Hide()
    c:enterCombat()
    check(guide(c):IsShown(), "a fight closed a guide that was not on the screen")
    c.UIParent:Show()
    c:advance(0.1)
    check(not isOpen(c), "the guide is on the screen in a fight")
    eq(bindings(c), nil, "the controller keys were kept in a fight")
    eq(PE.db.setup, nil)
    eq(linesWith(c, "Setup guide closed"), 0)
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    eq(title(c), TITLE .. " (2 of 7)")
    eq(c.blocked, {})
    c:assertClean("interface back in a fight")
end)

test("setup: a fight that starts and ends while the interface is hidden changes nothing", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    goTo(c, 2)
    c.UIParent:Hide()
    c:enterCombat(); c:leaveCombat()
    c:advance(0.1)
    c.UIParent:Show()
    c:advance(0.1)
    check(isOpen(c) and guide(c):IsVisible(), "the guide is gone")
    eq(title(c), TITLE .. " (2 of 7)")
    eq(linesWith(c, "Setup guide closed"), 0)
    c:enterCombat()
    check(not isOpen(c), "the guide stayed on screen in a fight")
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    c:assertClean("fight while hidden")
end)

---------------------------------------------------------------------------
-- Controller (rule 8)
---------------------------------------------------------------------------

test("setup: the d-pad reaches every button; A presses; B closes", function()
    local c, PE = T.new({})
    open(c, PE)
    local panel = guide(c)
    eq(bindings(c), ALL_KEYS)
    check(panel.peNavFocus == nil, "something is highlighted before the d-pad is used")
    goTo(c, 4) -- Vendors: two switches
    press(c, "DOWN")
    check(panel.peNavFocus == switch(c, "sellJunk"), "DOWN from nothing did not land on the first button")
    local reached = { [panel.peNavFocus] = 1 }
    local count = 1
    for _ = 1, 30 do
        press(c, "RIGHT")
        local b = panel.peNavFocus
        if reached[b] then break end
        reached[b] = 1
        count = count + 1
    end
    for _, b in ipairs(shownButtons(c, panel)) do
        local paging = T.labelOf(b) == "Up" or T.labelOf(b) == "Down"
        check(reached[b] or paging, "the d-pad never reached " .. T.labelOf(b))
    end
    eq(count, 6, "buttons in the d-pad's round: two switches, Back, Skip, Next, Close")
    -- A on Next moves a screen
    while panel.peNavFocus ~= nextButton(c) do press(c, "RIGHT") end
    press(c, "A")
    c:advance(0.1)
    eq(title(c), TITLE .. " (5 of 7)")
    press(c, "B")
    check(not isOpen(c), "B did not close the guide")
    c:assertClean("d-pad")
end)

test("setup: the highlight stays on Next from screen to screen, and on a switch after pressing it", function()
    local c, PE = T.new({})
    open(c, PE)
    local panel = guide(c)
    press(c, "UP") -- from nothing: the last button, Close
    press(c, "LEFT")
    local nextBtn = nextButton(c)
    check(panel.peNavFocus == nextBtn, "LEFT from Close is not Next")
    for i = 2, 7 do
        press(c, "A")
        c:advance(0.1)
        eq(title(c), TITLE .. " (" .. i .. " of 7)")
        check(panel.peNavFocus == nextBtn and nextBtn.peNavFocused ~= false, "the highlight left Next on screen " .. i)
    end
    -- Back to the first screen with the highlight on Back: Back goes away, the highlight goes to Next
    press(c, "LEFT")
    check(panel.peNavFocus == button(c, "Back"), "LEFT from Finish is not Back")
    for _ = 1, 6 do
        press(c, "A")
        c:advance(0.1)
    end
    eq(title(c), TITLE .. " (1 of 7)")
    check(panel.peNavFocus == nextBtn, "the highlight did not go to Start when Back went away")
    -- a switch keeps the highlight after it is pressed
    goTo(c, 4)
    local sw = switch(c, "repair")
    while panel.peNavFocus ~= sw do press(c, "RIGHT") end
    press(c, "A")
    c:advance(0.1)
    check(PE:IsModuleEnabled("repair"), "A on the switch did not turn Repair on")
    check(panel.peNavFocus == switch(c, "repair"), "the highlight left the switch")
    eq(T.labelOf(panel.peNavFocus), "ON")
    c:assertClean("highlight")
end)

test("setup: closing gives the d-pad back", function()
    local c, PE = T.new({})
    open(c, PE)
    eq(bindings(c), ALL_KEYS)
    c:click(button(c, "Close"))
    eq(bindings(c), nil, "the d-pad stays captured after the guide closed")
    open(c, PE)
    eq(bindings(c), ALL_KEYS, "reopening did not bind again")
    c:click(button(c, "Skip"))
    eq(bindings(c), nil)
    c:assertClean("keys")
end)

---------------------------------------------------------------------------
-- Nothing runs while closed (rule 9), sizes, debug log
---------------------------------------------------------------------------

local function setupListens(c, PE)
    local out = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == "Core.lua" or rec.addonFile == "Setup.lua" then
            for e in pairs(rec.events) do out[e] = true end
        end
    end
    return out
end

test("setup: nothing is built before the first opening, and nothing ticks or listens while it is closed", function()
    local c, PE = T.new({})
    check(guide(c) == nil, "the guide was built at load")
    for _, rec in ipairs(c:frames()) do
        check(rec.addonFile ~= "Setup.lua", "Setup.lua made a frame at load")
    end
    check(not setupListens(c, PE).PLAYER_ENTERING_WORLD, "still listening for the loading screen after login")
    check(not setupListens(c, PE).PLAYER_REGEN_DISABLED, "listening for fights while closed")
    c.stats.addonOnUpdate = 0
    c:advance(5)
    eq(c.stats.addonOnUpdate, 0)
    check(guide(c) == nil, "the guide opened although setup was skipped")

    open(c, PE)
    check(setupListens(c, PE).PLAYER_REGEN_DISABLED, "not listening for a fight while open")
    goTo(c, 3)
    c:advance(2)
    eq(c.stats.addonOnUpdate, 0, "something ticked while the guide was open")
    c:click(button(c, "Close"))
    c:advance(0.2)
    -- Every frame of the guide is made through UI.lua's kit; none may tick or listen.
    local made = 0
    walk(c, guide(c), function(w)
        local st = c._state(w)
        made = made + 1
        check(st.scripts.OnUpdate == nil, "a frame of the guide has an OnUpdate")
        check(next(st.events) == nil, "a frame of the guide listens for events")
    end)
    check(made > 10, "the walk over the guide's frames saw almost nothing")
    -- UI.lua's controller code keeps PLAYER_REGEN_DISABLED from the first window on; ours is gone
    local timers = c.stats.addonTimers
    c:advance(5)
    eq(c.stats.addonTimers, timers, "timers of ours while the guide is closed")
    eq(c.stats.addonOnUpdate, 0)
    c:assertClean("closed")
end)

test("setup: it draws at every button size, and a size change while open keeps it open", function()
    local c, PE = T.new({})
    for _, size in ipairs({ "small", "large", "medium" }) do
        PE:SetUISetting("size", size)
        c:advance(0.2)
        open(c, PE)
        for i = 1, 7 do
            eq(title(c), TITLE .. " (" .. i .. " of 7)")
            c:assertClean(size .. ", screen " .. i)
            if i < 7 then goTo(c, 2) end
        end
        PE:SetUISetting("size", size == "small" and "large" or "small")
        c:advance(0.2)
        check(isOpen(c), "a size change closed the guide")
        eq(title(c), TITLE .. " (7 of 7)")
        c:click(button(c, "Close"))
    end
    c:assertClean("sizes")
end)

test("setup: the debug log has the lines of the spec", function()
    local start = saved({}, "finished")
    start.debug = { on = true }
    local c, PE = T.new({ firstRun = true, saved = start })
    c:advance(2)
    eq(debugLines(c, "setup"), { "first login check: not needed (finished)" })
    PE.db.setup = nil
    PE.Setup:Open("settings")
    c:advance(0.1)
    goTo(c, 2)
    c:click(switch(c, "questArrow"))
    c:click(switch(c, "menuBg"))
    c:advance(0.1)
    c:click(switch(c, "menuBg"))
    c:advance(0.1)
    c:enterCombat()
    PE.Setup:Open("slash")
    c:leaveCombat()
    c:advance(0.1)
    c:click(button(c, "Close"))
    PE.Setup:Open("slash")
    press(c, "B")
    PE.Setup:Open("settings")
    c:click(button(c, "Skip"))
    PE.Setup:Open("settings")
    goTo(c, 7)
    c:click(button(c, "Finish"))
    local all = "screens: welcome, quests, bags, vendors, chat, layout, finish"
    eq(debugLines(c, "setup"), {
        "first login check: not needed (finished)",
        "opened (settings)", all, "screen 1 of 7: welcome",
        "screen 2 of 7: quests",
        "switch tapped: questArrow cannot be switched on",
        "switch tapped: menuBg -> on",
        "switch tapped: menuBg -> off",
        "closed: fight started, will come back",
        "not opened: in a fight",
        "opened (after the fight)", all, "screen 2 of 7: quests",
        "closed: not remembered (Close)",
        "opened (slash)", all, "screen 1 of 7: welcome",
        "closed: not remembered (B, Escape or another window)",
        "opened (settings)", all, "screen 1 of 7: welcome",
        "closed: skipped",
        "opened (settings)", all, "screen 1 of 7: welcome",
        "screen 2 of 7: quests", "screen 3 of 7: bags", "screen 4 of 7: vendors", "screen 5 of 7: chat",
        "screen 6 of 7: layout", "screen 7 of 7: finish",
        "closed: finished",
    })
    eq(PE.db.setup, "finished")
    c:assertClean("debug lines")
end)

test("setup: the debug log says when it waits for a fight at login and when the answer cannot be kept", function()
    local c, PE = T.new({ firstRun = true, saved = { debug = { on = true } }, setup = function(c) c.world.inCombat = true end })
    c:advance(2)
    eq(debugLines(c, "setup"), { "waiting for the fight to end" })
    PE:OpenSettings()
    c:leaveCombat()
    c:advance(0.1)
    eq(debugLines(c, "setup"), { "waiting for the fight to end", "not reopened: another window is open" })
    check(not isOpen(c), "the guide opened over the settings")

    local c2, PE2 = T.new({ firstRun = true, saved = { debug = { on = true } } })
    local real = PE2.db
    PE2.db = { version = 1, enabled = {}, options = {}, ui = real.ui, errors = PE2.errors }
    c2:advance(2)
    eq(debugLines(c2, "setup"), { "first login check: saved settings not loaded, guide not shown" })
end)

return { known = KNOWN_FAILURES }
