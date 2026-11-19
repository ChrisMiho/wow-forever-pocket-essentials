-- Rules for the setup guide (Setup.lua).
-- Source: docs/superpowers/specs/2026-11-17-0.4.0-handheld-batch.md, section
-- "5. Setup guide" ("What the player sees", "Rules", "Debug-log lines") as
-- amended on 2026-11-18 (options in the guide, rules 13 to 18) and its
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
-- Since 0.5.0 (the spec's amendment of 2026-11-18): one screen per feature that has options.
local ALL_SCREENS = { "Welcome to Pocket Essentials", "Quest icons", "Quest arrow", "Menu background", "Bags", "Vendors",
    "Chat", "The round button and moving things", "All set" }
local N = #ALL_SCREENS
local AT = { welcome = 1, questIcons = 2, questArrow = 3, menuBg = 4, bags = 5, vendors = 6, chat = 7, layout = 8, finish = 9 }
-- The screen each feature's switch is on.
local SCREEN_OF = { questIcons = 2, questArrow = 3, menuBg = 4, bags = 5, sellJunk = 6, repair = 6, chat = 7 }

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
    eq(title(c), TITLE .. " (1 of " .. N .. ")")
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
    eq(title(c), TITLE .. " (1 of " .. N .. ")")
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
    goTo(c, AT.vendors)
    check(hasText(c, "Vendors"), "screen " .. AT.vendors .. " is not Vendors")
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

test("setup: the screens are welcome, quest icons, quest arrow, menu background, bags, vendors, chat, layout, finish", function()
    local c, PE = T.new({})
    open(c, PE)
    local headings = {}
    for i = 1, N do
        eq(title(c), TITLE .. " (" .. i .. " of " .. N .. ")")
        for _, name in ipairs(ALL_SCREENS) do
            if hasText(c, name) then headings[#headings + 1] = name end
        end
        eq(has(c, "Back"), i > 1, "Back on screen " .. i)
        eq(has(c, "Skip"), i < N, "Skip on screen " .. i)
        eq(T.labelOf(nextButton(c)), i == 1 and "Start" or i == N and "Finish" or "Next")
        if i < N then goTo(c, 2) end
    end
    eq(headings, ALL_SCREENS)
    eq(nextButton(c).peStyle, "on", "Finish is not green")
    c:click(button(c, "Back"))
    c:advance(0.1)
    eq(title(c), TITLE .. " (" .. (N - 1) .. " of " .. N .. ")")
    c:assertClean("screens")
end)

test("setup: every feature of this build has a switch on some screen, and the new choices are explained", function()
    local c, PE = T.new({})
    open(c, PE)
    local seen = {}
    local all = {}
    for i = 1, N do
        for _, b in ipairs(shownButtons(c, guide(c))) do
            if b.peKey then seen[b.peKey] = (seen[b.peKey] or 0) + 1 end
        end
        for _, t in ipairs(texts(c)) do all[#all + 1] = t end
        for key, at in pairs(SCREEN_OF) do
            if at == i then switch(c, key) end
        end
        -- The stepper is a real control now, shown with Big chat buttons off (it is marked always).
        if i == AT.chat then button(c, "-"); button(c, "+") end
        if i < N then goTo(c, 2) end
    end
    for _, mod in ipairs(PE.moduleList) do
        eq(seen[mod.key], 1, "switches for " .. mod.key)
    end
    local joined = table.concat(all, "\n")
    for _, part in ipairs({ "D-pad to Sort", "Bag icons", "One row at the top", "Chat text size" }) do
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
    goTo(c, AT.vendors)
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
    goTo(c, AT.vendors)
    eq(T.labelOf(switch(c, "repair")), "OFF")
    PE:SetModuleEnabled("repair", true)
    c:advance(0.1)
    eq(T.labelOf(switch(c, "repair")), "ON")
    c:assertClean("redraw hook")
end)

test("setup: quest switches are dimmed with the reason when QuestieDB is missing", function()
    local c, PE = T.new({})
    open(c, PE)
    local state, reason = PE:GetModuleState("questIcons")
    eq(state, "blocked")
    check(type(reason) == "string" and reason:find("QuestieDB", 1, true), "no reason for the blocked quest features")
    for _, key in ipairs({ "questIcons", "questArrow" }) do
        goTo(c, 2)
        eq(title(c), TITLE .. " (" .. SCREEN_OF[key] .. " of " .. N .. ")")
        eq(T.labelOf(switch(c, key)), "OFF")
        eq(switch(c, key).peStyle, "disabled")
        c:click(switch(c, key))
        c:advance(0.1)
        check(not PE:IsModuleSavedOn(key), "a tap on a dimmed switch saved " .. key .. " as on")
        local count = 0
        for _, t in ipairs(texts(c)) do
            if t == reason then count = count + 1 end
        end
        eq(count, 1, "the amber reason under the " .. key .. " switch")
        -- as in the settings: a feature that cannot be switched on shows none of its options
        for _, opt in ipairs(PE:GetModule(key).options) do
            if opt.label then check(not hasText(c, opt.label), key .. " shows \"" .. opt.label .. "\" although it cannot be on") end
        end
    end
    -- Menu background does not need QuestieDB
    goTo(c, 2)
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
        for i = 1, N - 1 do
            eq(title(c), TITLE .. " (" .. i .. " of " .. (N - 1) .. ")")
            for _, name in ipairs(ALL_SCREENS) do
                if hasText(c, name) then headings[#headings + 1] = name end
            end
            if i < N - 1 then goTo(c, 2) end
        end
        eq(headings, { "Welcome to Pocket Essentials", "Quest icons", "Quest arrow", "Menu background", "Bags", "Chat",
            "The round button and moving things", "All set" })
        eq(T.labelOf(nextButton(c)), "Finish")
        c:assertClean("a build without the vendor features")
    end)
    if dir:find("pe-setup-test-", 1, true) then sh("rm -rf '" .. dir .. "'") end
    if not ok then error(err, 0) end
end)

test("setup: the finish screen lists what is on and what is off", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, N)
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
    goTo(c, N)
    check(textWith(c, "Switched on: Quest icons, Quest arrow, Bag sorter"), "no Switched on line")
    check(not textWith(c, "Still off:"), "a Still off line with everything on")
end)

test("setup: the finish screen offers a reload when a feature asked for one", function()
    local c, PE = T.new({ gamepadUI = false, setup = function(c) c.world.cvars.combinedBags = "0" end })
    open(c, PE)
    goTo(c, AT.bags)
    c:click(switch(c, "bags"))
    c:advance(0.2)
    check(#PE.reloadReasons > 0, "Bag sorter asked for no reload (the test's premise)")
    goTo(c, N - AT.bags + 1)
    eq(title(c), TITLE .. " (" .. N .. " of " .. N .. ")")
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
    goTo(c, AT.bags)
    c:click(switch(c, "bags"))
    c:advance(0.2)
    goTo(c, N - AT.bags + 1)
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
    goTo(c, N)
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
    eq(title(c), TITLE .. " (1 of " .. N .. ")")
    -- reopened from the middle: back at the first screen
    goTo(c, 3)
    PE:OpenSettings()
    c:advance(0.2)
    c:click(shownButtons(c, settings, "Setup guide")[1])
    c:advance(0.2)
    eq(title(c), TITLE .. " (1 of " .. N .. ")")
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
    eq(title(c), TITLE .. " (3 of " .. N .. ")")
    c:enterCombat()
    check(not isOpen(c), "the guide stayed on screen in a fight")
    eq(bindings(c), nil, "the controller keys were kept in a fight")
    eq(PE.db.setup, nil, "a fight counted as an answer")
    eq(linesWith(c, "Setup guide closed"), 0, "a fight printed the closed line")
    c:advance(2)
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    eq(title(c), TITLE .. " (3 of " .. N .. ")")
    check(hasText(c, "Quest arrow"), "it came back at another screen")
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
    eq(title(c), TITLE .. " (3 of " .. N .. ")")
    eq(bindings(c), ALL_KEYS)
    c:enterCombat()
    check(not isOpen(c), "the guide stayed on screen in a fight after the interface came back")
    eq(linesWith(c, "Setup guide closed"), 0, "a fight printed the closed line")
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    eq(title(c), TITLE .. " (3 of " .. N .. ")")
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
    eq(title(c), TITLE .. " (2 of " .. N .. ")")
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
    eq(title(c), TITLE .. " (2 of " .. N .. ")")
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
    goTo(c, AT.vendors) -- Vendors: two switches
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
        local paging = T.labelOf(b) == "^" or T.labelOf(b) == "v"
        check(reached[b] or paging, "the d-pad never reached " .. T.labelOf(b))
    end
    eq(count, 6, "buttons in the d-pad's round: two switches, Back, Skip, Next, Close")
    -- A on Next moves a screen
    while panel.peNavFocus ~= nextButton(c) do press(c, "RIGHT") end
    press(c, "A")
    c:advance(0.1)
    eq(title(c), TITLE .. " (" .. AT.chat .. " of " .. N .. ")")
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
    for i = 2, N do
        press(c, "A")
        c:advance(0.1)
        eq(title(c), TITLE .. " (" .. i .. " of " .. N .. ")")
        check(panel.peNavFocus == nextBtn and nextBtn.peNavFocused ~= false, "the highlight left Next on screen " .. i)
    end
    -- Back to the first screen with the highlight on Back: Back goes away, the highlight goes to Next
    press(c, "LEFT")
    check(panel.peNavFocus == button(c, "Back"), "LEFT from Finish is not Back")
    for _ = 1, N - 1 do
        press(c, "A")
        c:advance(0.1)
    end
    eq(title(c), TITLE .. " (1 of " .. N .. ")")
    check(panel.peNavFocus == nextBtn, "the highlight did not go to Start when Back went away")
    -- a switch keeps the highlight after it is pressed
    goTo(c, AT.vendors)
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
        for i = 1, N do
            eq(title(c), TITLE .. " (" .. i .. " of " .. N .. ")")
            c:assertClean(size .. ", screen " .. i)
            if i < N then goTo(c, 2) end
        end
        PE:SetUISetting("size", size == "small" and "large" or "small")
        c:advance(0.2)
        check(isOpen(c), "a size change closed the guide")
        eq(title(c), TITLE .. " (" .. N .. " of " .. N .. ")")
        c:click(button(c, "Close"))
    end
    c:assertClean("sizes")
end)

test("setup: Up and Down show only on a screen too long to fit, and a screen that fits has the whole width", function()
    local c, PE = T.new({})
    local withPaging, without = 0, 0
    for _, size in ipairs({ "small", "medium", "large" }) do
        PE:SetUISetting("size", size)
        c:advance(0.2)
        open(c, PE)
        for i = 1, N do
            local up, down = shownButtons(c, guide(c), "^"), shownButtons(c, guide(c), "v")
            eq(#up, #down, size .. ", screen " .. i .. ": Up and Down go together")
            if #up > 0 then
                withPaging = withPaging + 1
                local area = up[1]:GetParent()
                check(area:GetRange() > 0, size .. ", screen " .. i .. ": paging buttons on a screen that fits")
                check(area.viewWidth < guide(c).contentWidth, size .. ", screen " .. i .. ": no room kept for the paging buttons")
            else
                without = without + 1
            end
            if i < N then goTo(c, 2) end
        end
        c:click(button(c, "Close"))
    end
    check(without > 0, "no screen was drawn without paging buttons")
    if os.getenv("SETUP_VERBOSE") then print("screens with paging: " .. withPaging .. ", without: " .. without) end
    -- The welcome screen is short at every size.
    PE:SetUISetting("size", "medium")
    c:advance(0.2)
    open(c, PE)
    check(not has(c, "^") and not has(c, "v"), "the welcome screen shows paging buttons")
    c:assertClean("paging")
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
    goTo(c, 3)
    c:click(switch(c, "questArrow"))
    goTo(c, 2)
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
    goTo(c, N)
    c:click(button(c, "Finish"))
    local all = "screens: welcome, questIcons, questArrow, menuBg, bags, vendors, chat, layout, finish"
    eq(debugLines(c, "setup"), {
        "first login check: not needed (finished)",
        "opened (settings)", all, "screen 1 of 9: welcome",
        "screen 2 of 9: questIcons", "screen 3 of 9: questArrow",
        "switch tapped: questArrow cannot be switched on",
        "screen 4 of 9: menuBg",
        "switch tapped: menuBg -> on",
        "switch tapped: menuBg -> off",
        "closed: fight started, will come back",
        "not opened: in a fight",
        "opened (after the fight)", all, "screen 4 of 9: menuBg",
        "closed: not remembered (Close)",
        "opened (slash)", all, "screen 1 of 9: welcome",
        "closed: not remembered (B, Escape or another window)",
        "opened (settings)", all, "screen 1 of 9: welcome",
        "closed: skipped",
        "opened (settings)", all, "screen 1 of 9: welcome",
        "screen 2 of 9: questIcons", "screen 3 of 9: questArrow", "screen 4 of 9: menuBg", "screen 5 of 9: bags",
        "screen 6 of 9: vendors", "screen 7 of 9: chat", "screen 8 of 9: layout", "screen 9 of 9: finish",
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

---------------------------------------------------------------------------
-- Options in the guide (amendment of 2026-11-18, rules 13 to 18)
--
-- What a feature's options should look like is worked out here from the
-- feature's own `options` list, not from the drawing code: a choices row is
-- its label and one button per choice, the saved one marked; an action row is
-- one button; a buttons row is its label and its buttons.
---------------------------------------------------------------------------

local SIZES = { "small", "medium", "large" }

-- Features that cannot be switched on in this run (the quest ones without QuestieDB).
local function canBeOn(PE, key)
    return not PE:GetModule(key).requiresQuestieDB or T.questieDB ~= nil
end

local function newClient(opts)
    opts = opts or {}
    opts.quest = T.questieDB ~= nil
    if opts.gamepadUI == nil then opts.gamepadUI = true end
    return T.new(opts)
end

local function modsWithOptions(PE)
    local out = {}
    for _, mod in ipairs(PE.moduleList) do
        if type(mod.options) == "table" and #mod.options > 0 then out[#out + 1] = mod end
    end
    return out
end

local function goToFeature(c, PE, key)
    open(c, PE)
    goTo(c, SCREEN_OF[key])
    return switch(c, key)
end

-- The visible text of `top` that is exactly `text`, or starts with `text .. ":"`.
local function textRegion(c, top, text)
    local found
    walk(c, top, function(w)
        if c._state(w).type ~= "Button" then
            for _, r in ipairs(c._state(w).regions) do
                local st = c._state(r)
                if st.type == "FontString" and st.text and r:IsVisible()
                    and (st.text == text or st.text:sub(1, #text + 1) == text .. ":") then
                    found = found or { region = r, parent = w, text = st.text }
                end
            end
        end
    end)
    return found
end

-- The buttons drawn after a label, in reading order: same list, below the label.
local function buttonsAfter(c, top, label)
    local at = textRegion(c, top, label)
    if not at then return nil end
    -- Since 0.6.0 the heading may sit on its buttons' line (left of them), so
    -- "after" is every button whose middle is not above the heading's top.
    local _, _, labelTop = c._rect(at.region)
    local out = {}
    for _, b in ipairs(shownButtons(c, top)) do
        local l, _, t, bottom = c._rect(b)
        if b:GetParent() == at.parent and (t + bottom) / 2 <= labelTop + 0.01 then out[#out + 1] = { b = b, l = l, t = t } end
    end
    table.sort(out, function(x, y)
        if math.abs(x.t - y.t) > 0.01 then return x.t > y.t end
        return x.l < y.l
    end)
    for i = 1, #out do out[i] = out[i].b end
    return out
end

-- The value a choices row shows: its get, or the saved value of its key.
local function currentOf(mod, opt)
    if type(opt.get) == "function" then return opt.get(mod) end
    return mod.opts[opt.key]
end

-- The one button of a toggle row (0.6.0): it reads "label: choice"; nil when not drawn.
local function toggleButton(c, top, opt)
    for _, b in ipairs(shownButtons(c, top)) do
        local text = T.labelOf(b)
        if text and text:sub(1, #opt.label + 2) == opt.label .. ": " then return b end
    end
    return nil
end

-- The buttons of one choices row, in the order of its choices; nil when the row is not drawn.
-- A toggle row has one button, so this is a list of that one.
local function choiceButtons(c, top, opt)
    if opt.toggle then
        local b = toggleButton(c, top, opt)
        return b and { b } or nil
    end
    local after = buttonsAfter(c, top, opt.label)
    if not after then return nil end
    local out = {}
    for i, choice in ipairs(opt.choices) do
        local b = after[i]
        check(b and T.labelOf(b) == tostring(choice.label), "under \"" .. opt.label .. "\" button " .. i .. " reads "
            .. tostring(b and T.labelOf(b)) .. ", expected " .. tostring(choice.label), 2)
        out[i] = b
    end
    return out
end

-- Checks that `top` draws (shown = true) or does not draw one option row of a feature.
local function checkOption(c, top, mod, opt, shown, where)
    if opt.toggle then
        local b = toggleButton(c, top, opt)
        eq(b ~= nil, shown, where .. ": toggle \"" .. opt.label .. "\" drawn")
        if shown then
            local current = currentOf(mod, opt)
            local choice = current == opt.choices[2].value and opt.choices[2] or opt.choices[1]
            eq(T.labelOf(b), opt.label .. ": " .. tostring(choice.label), where .. ": toggle label")
            eq(b.peStyle, current == true and "on" or "off", where .. ": toggle style")
        end
    elseif type(opt.choices) == "table" then
        local buttons = choiceButtons(c, top, opt)
        eq(buttons ~= nil, shown, where .. ": \"" .. opt.label .. "\" drawn")
        if shown then
            for i, choice in ipairs(opt.choices) do
                eq(buttons[i].peSelected == true, currentOf(mod, opt) == choice.value,
                    where .. ": \"" .. opt.label .. "\" / " .. tostring(choice.label) .. " marked")
            end
        end
    elseif type(opt.number) == "table" or type(opt.stepper) == "function" then
        -- A number control (0.7.0): the heading, then "-" and "+".
        local region = textRegion(c, top, opt.label)
        eq(region ~= nil, shown, where .. ": \"" .. opt.label .. "\" drawn")
        if shown then
            local after = buttonsAfter(c, top, opt.label)
            eq({ T.labelOf(after[1]), T.labelOf(after[2]) }, { "-", "+" }, where .. ": the ends of \"" .. opt.label .. "\"")
        end
    elseif type(opt.action) == "function" then
        eq(#shownButtons(c, top, opt.label), shown and 1 or 0, where .. ": button \"" .. opt.label .. "\"")
    else
        eq(textRegion(c, top, opt.label) ~= nil, shown, where .. ": \"" .. opt.label .. "\" drawn")
        if shown then
            local list = type(opt.buttons) == "function" and opt.buttons(mod) or opt.buttons
            local after = buttonsAfter(c, top, opt.label)
            local n = 0
            for _, entry in ipairs(list) do
                if entry.action then
                    n = n + 1
                    eq(T.labelOf(after[n]), entry.label, where .. ": button " .. n .. " of \"" .. opt.label .. "\"")
                    eq(after[n].peStyle, entry.style == "disabled" and "disabled" or "normal", where .. ": style of " .. entry.label)
                end
            end
            check(n > 0, where .. ": \"" .. opt.label .. "\" has no buttons in this stand-in (the test's premise)")
        end
    end
end

-- The scrolling list a button of the guide sits in.
local function areaOf(btn) return btn:GetParent():GetParent():GetParent() end

local function pagingShown(c)
    local up, down = shownButtons(c, guide(c), "^"), shownButtons(c, guide(c), "v")
    eq(#up, #down, "Up and Down go together")
    return #up > 0
end

test("options: the test's own reading of the screen list matches the features that have options", function()
    local c, PE = newClient()
    -- every feature with options has a screen to itself; the others may share one
    local perScreen = {}
    for _, mod in ipairs(PE.moduleList) do
        check(SCREEN_OF[mod.key], "no screen known for " .. mod.key)
        perScreen[SCREEN_OF[mod.key]] = (perScreen[SCREEN_OF[mod.key]] or 0) + 1
    end
    local with = modsWithOptions(PE)
    check(#with >= 4, "fewer than four features have options (the test's premise)")
    for _, mod in ipairs(with) do
        eq(perScreen[SCREEN_OF[mod.key]], 1, "features on the screen of " .. mod.key .. ", which has options")
    end
    open(c, PE)
    for i = 1, N do
        for key, at in pairs(SCREEN_OF) do
            if at == i then switch(c, key) end
        end
        if i < N then goTo(c, 2) end
    end
end)

test("options: off, a feature shows only its rows marked always; switched on, all of them at once under its switch", function()
    local c, PE = newClient()
    local sawAlways = false
    for _, mod in ipairs(modsWithOptions(PE)) do
        if canBeOn(PE, mod.key) then
            local key = mod.key
            local sw = goToFeature(c, PE, key)
            eq(T.labelOf(sw), "OFF")
            for _, opt in ipairs(mod.options) do
                if opt.always then sawAlways = true end
                checkOption(c, guide(c), mod, opt, opt.always == true, key .. " off")
            end
            c:click(sw)
            c:advance(0.1)
            check(PE:IsModuleEnabled(key), key .. " did not switch on")
            check(switch(c, key) == sw, key .. ": the switch is another button after the press")
            local _, _, _, switchBottom = c._rect(sw)
            for _, opt in ipairs(mod.options) do
                checkOption(c, guide(c), mod, opt, true, key .. " on")
                local first = type(opt.action) == "function" and shownButtons(c, guide(c), opt.label)[1]
                    or opt.toggle and toggleButton(c, guide(c), opt)
                    or textRegion(c, guide(c), opt.label).region
                local _, _, top = c._rect(first)
                check(top < switchBottom, key .. ": \"" .. opt.label .. "\" is not under the switch")
            end
            check(not has(c, "Hide options") and not has(c, "Show options"), key .. ": the guide has a fold button")
            c:click(switch(c, key))
            c:advance(0.1)
            for _, opt in ipairs(mod.options) do
                checkOption(c, guide(c), mod, opt, opt.always == true, key .. " off again")
            end
            c:assertClean(key)
            c:click(button(c, "Close"))
        end
    end
    check(sawAlways, "no option row is marked always (the test's premise: Chat text size)")
end)

test("options: a feature with both kinds of row shows only the always rows while it is off, in both windows", function()
    local c, PE = newClient()
    local mod = PE:GetModule("chat")
    local extra = { key = "testChoice", label = "Only while on", choices = { { value = 1, label = "First" }, { value = 2, label = "Second" } } }
    mod.options[#mod.options + 1] = extra
    goToFeature(c, PE, "chat")
    checkOption(c, guide(c), mod, mod.options[1], true, "guide, chat off")
    checkOption(c, guide(c), mod, extra, false, "guide, chat off")
    PE:OpenSettings()
    c:advance(0.2)
    checkOption(c, settingsPanel(c), mod, mod.options[1], true, "settings, chat off")
    checkOption(c, settingsPanel(c), mod, extra, false, "settings, chat off")
    c:click(goToFeature(c, PE, "chat"))
    c:advance(0.1)
    checkOption(c, guide(c), mod, mod.options[1], true, "guide, chat on")
    checkOption(c, guide(c), mod, extra, true, "guide, chat on")
    PE:OpenSettings()
    c:advance(0.2)
    checkOption(c, settingsPanel(c), mod, extra, true, "settings, chat on")
    c:assertClean("always rows")
end)

test("options: a fold saved in the settings hides nothing in the guide", function()
    local c, PE = newClient({ on = { "bags" } })
    PE.db.ui.folded.bags = true
    PE:OpenSettings()
    c:advance(0.2)
    local mod = PE:GetModule("bags")
    checkOption(c, settingsPanel(c), mod, mod.options[1], false, "settings, folded")
    goToFeature(c, PE, "bags")
    for _, opt in ipairs(mod.options) do checkOption(c, guide(c), mod, opt, true, "guide, folded in the settings") end
    eq(PE.db.ui.folded.bags, true, "the guide changed the saved fold")
end)

test("options: the guide draws what the settings window draws for the same feature", function()
    local c, PE = newClient()
    for _, mod in ipairs(modsWithOptions(PE)) do
        if canBeOn(PE, mod.key) then PE:SetModuleEnabled(mod.key, true) end
    end
    c:advance(0.5)
    for _, mod in ipairs(modsWithOptions(PE)) do
        if canBeOn(PE, mod.key) then
            goToFeature(c, PE, mod.key)
            for _, opt in ipairs(mod.options) do checkOption(c, guide(c), mod, opt, true, mod.key .. " in the guide") end
        end
    end
    -- the settings, one feature at a time (the others folded away), by the same reading
    for _, mod in ipairs(modsWithOptions(PE)) do
        if canBeOn(PE, mod.key) then
            for _, other in ipairs(modsWithOptions(PE)) do PE.db.ui.folded[other.key] = other ~= mod and true or nil end
            PE:OpenSettings()
            c:advance(0.2)
            for _, opt in ipairs(mod.options) do checkOption(c, settingsPanel(c), mod, opt, true, mod.key .. " in the settings") end
        end
    end
    c:assertClean("same drawing")
end)

test("options: a choice pressed in the guide is saved, runs the same OnChange and shows in the settings, and the other way round", function()
    local c, PE = newClient()
    local pressed = 0
    for _, mod in ipairs(modsWithOptions(PE)) do
        if canBeOn(PE, mod.key) then
            PE:SetModuleEnabled(mod.key, true)
            c:advance(0.3)
            for _, other in ipairs(modsWithOptions(PE)) do PE.db.ui.folded[other.key] = other ~= mod and true or nil end
            for _, opt in ipairs(mod.options) do
                if type(opt.choices) == "table" then
                    local calls = {}
                    local original = opt.OnChange
                    opt.OnChange = function(...)
                        calls[#calls + 1] = { ... }
                        if original then return original(...) end
                    end
                    local where = mod.key .. " / " .. opt.label
                    -- The value a press on this row should save, and the button to press.
                    -- A toggle has one button that flips; otherwise a choice that is
                    -- not the saved one (or the only other one, twice over).
                    local function pick(top, nth)
                        local current = currentOf(mod, opt)
                        if opt.toggle then
                            local value = opt.choices[1].value -- not "and ... or": the other value may be false
                            if current == opt.choices[1].value then value = opt.choices[2].value end
                            return toggleButton(c, top, opt), value
                        end
                        local others = {}
                        for i, choice in ipairs(opt.choices) do
                            if choice.value ~= current then others[#others + 1] = i end
                        end
                        local i = others[nth] or others[1]
                        return choiceButtons(c, top, opt)[i], opt.choices[i].value, i
                    end
                    local function marked(top, i)
                        if opt.toggle then return true end -- checkOption reads the toggle's label
                        return choiceButtons(c, top, opt)[i].peSelected == true
                    end

                    -- in the guide
                    goToFeature(c, PE, mod.key)
                    local btn, value, index = pick(guide(c), 1)
                    c:click(btn)
                    c:advance(0.1)
                    eq(currentOf(mod, opt), value, where .. ": saved after the press in the guide")
                    if opt.key ~= nil then
                        eq(PE.db.options[mod.key][opt.key], value, where .. ": in the saved table")
                    end
                    eq(#calls, 1, where .. ": OnChange calls after the press in the guide")
                    check(calls[1][1] == mod and calls[1][2] == value, where .. ": OnChange got other arguments")
                    check(marked(guide(c), index), where .. ": not marked in the guide")
                    checkOption(c, guide(c), mod, opt, true, where .. ", guide after the press")
                    PE:OpenSettings()
                    c:advance(0.2)
                    checkOption(c, settingsPanel(c), mod, opt, true, where .. ", settings after the guide")

                    -- in the settings
                    btn, value, index = pick(settingsPanel(c), 2)
                    c:click(btn)
                    c:advance(0.2)
                    eq(currentOf(mod, opt), value, where .. ": saved after the press in the settings")
                    eq(#calls, 2, where .. ": OnChange calls after the press in the settings")
                    check(calls[2][1] == mod and calls[2][2] == value, where .. ": OnChange got other arguments")
                    goToFeature(c, PE, mod.key)
                    check(not settingsPanel(c):IsShown(), "the settings stayed open under the guide")
                    checkOption(c, guide(c), mod, opt, true, where .. ", guide after the settings")
                    check(marked(guide(c), index), where .. ": not marked in the guide")
                    opt.OnChange = original
                    pressed = pressed + 1
                end
            end
            c:assertClean(mod.key)
        end
    end
    check(pressed >= 5, "only " .. pressed .. " choices were tried")
end)

-- The number in the chat text size box (between - and +) in a window.
local function stepperNumber(c, top)
    local smaller, bigger = shownButtons(c, top, "-")[1], shownButtons(c, top, "+")[1]
    check(smaller and bigger, "no Smaller / Bigger pair", 2)
    local _, sr, st, sb = c._rect(smaller)
    local bl = c._rect(bigger)
    local found
    walk(c, top, function(w)
        for _, r in ipairs(c._state(w).regions) do
            local rs = c._state(r)
            if rs.type == "FontString" and tonumber(rs.text) and r:IsVisible() then
                local l, rr, t = c._rect(r)
                if l >= sr - 0.01 and rr <= bl + 0.01 and t <= st + 0.01 and t >= sb - 0.01 then found = rs.text end
            end
        end
    end)
    return tonumber(found)
end

test("options: the chat text size stepper works in the guide with Big chat buttons off, and both windows show the same number", function()
    local c, PE = newClient()
    check(not PE:IsModuleEnabled("chat"), "chat is on (the test's premise)")
    goToFeature(c, PE, "chat")
    local start = stepperNumber(c, guide(c))
    check(start, "no number between Smaller and Bigger in the guide")
    c:click(button(c, "+"))
    c:advance(0.1)
    local bigger = stepperNumber(c, guide(c))
    check(bigger > start, "Bigger in the guide did not raise the number: " .. tostring(bigger))
    eq(c.chatSizes[1], bigger, "the chat window's size")
    PE:OpenSettings()
    c:advance(0.2)
    eq(stepperNumber(c, settingsPanel(c)), bigger, "the settings show another size")
    c:click(shownButtons(c, settingsPanel(c), "-")[1])
    c:advance(0.2)
    c:click(shownButtons(c, settingsPanel(c), "-")[1])
    c:advance(0.2)
    local smaller = stepperNumber(c, settingsPanel(c))
    check(smaller < start, "Smaller twice in the settings did not lower the number")
    goToFeature(c, PE, "chat")
    eq(stepperNumber(c, guide(c)), smaller, "the guide shows another size")
    eq(c.chatSizes[1], smaller)
    check(not PE:IsModuleSavedOn("chat"), "the stepper switched Big chat buttons on")
    -- the highlight stays on the button after a press with A
    local panel = guide(c)
    press(c, "DOWN")
    while panel.peNavFocus ~= button(c, "+") do press(c, "RIGHT") end
    press(c, "A")
    c:advance(0.1)
    check(panel.peNavFocus == button(c, "+"), "the highlight left Bigger")
    check(stepperNumber(c, guide(c)) > smaller, "A on Bigger did nothing")
    c:assertClean("stepper")
end)

-- The spec's risk 12: the two choices that belong to no feature are not in the guide
-- (proposed, not asked for). The layout screen says where they are.
test("options: the layout screen has no controls of its own; it says where Button size is", function()
    local c, PE = newClient()
    open(c, PE)
    goTo(c, AT.layout)
    check(not textRegion(c, guide(c), "Button size") and not textRegion(c, guide(c), "Round button position"),
        "the settings' own two choices are drawn in the guide")
    check(textWith(c, "In the settings you can choose where the round button sits"), "the screen does not say where they are")
    local panel = guide(c)
    press(c, "DOWN")
    eq(T.labelOf(panel.peNavFocus), "Back", "the first button the d-pad reaches on a screen without controls")
end)

test("options: Icon key in the guide opens the settings' Icon key page, as it does in the settings", function()
    if not T.questieDB then return end
    local c, PE = newClient({ on = { "questIcons" } })
    goToFeature(c, PE, "questIcons")
    c:click(button(c, "Icon key"))
    c:advance(0.2)
    check(not isOpen(c), "the guide stayed open under the Icon key page")
    check(settingsPanel(c):IsShown(), "the settings did not open")
    eq(settingsPanel(c).peTitle:GetText(), "Pocket Essentials - Icon key")
    c:assertClean("icon key from the guide")
end)

test("options: a reload asked for by an option is offered on the finish screen", function()
    local c, PE = newClient({ on = { "bags" } })
    local mod = PE:GetModule("bags")
    eq(#PE.reloadReasons, 0, "a reload is already wanted (the test's premise)")
    mod.options[#mod.options + 1] = { key = "testReload", label = "Needs a reload",
        choices = { { value = 1, label = "One" }, { value = 2, label = "Two" } },
        OnChange = function(self) self:RequestReload("Test reason.") end }
    goToFeature(c, PE, "bags")
    c:click(button(c, "Two"))
    c:advance(0.1)
    eq(#PE.reloadReasons, 1)
    check(not has(c, "Reload now"), "Reload now is on a feature screen")
    goTo(c, N - AT.bags + 1)
    check(hasText(c, "Bag sorter: Test reason."), "the reason is not on the finish screen")
    button(c, "Reload now")
    -- and the settings offer it too
    PE:OpenSettings()
    c:advance(0.2)
    eq(#shownButtons(c, settingsPanel(c), "Reload now"), 1, "Reload now in the settings")
end)

test("options: an option row that breaks is recorded and does not take the guide down", function()
    local c, PE = newClient({ on = { "bags" } })
    local mod = PE:GetModule("bags")
    mod.options[#mod.options + 1] = { label = "Broken", value = function() error("value broke") end,
        buttons = function() error("buttons broke") end }
    mod.options[#mod.options + 1] = { key = "x", label = "Bad change", choices = { { value = 1, label = "Go" } },
        OnChange = function() error("change broke") end }
    goToFeature(c, PE, "bags")
    check(hasText(c, "Broken"), "the row's label is not drawn")
    local before = #PE.errors
    c:click(button(c, "Go"))
    c:advance(0.1)
    eq(c.errors, {}, "the error reached the game")
    eq(#PE.errors - before, 1, "the error is not on the Errors page")
    eq(PE.errors[#PE.errors].module, "bags")
    check(isOpen(c), "the guide closed")
    button(c, "Next")
end)

test("options: the d-pad reaches every control of every screen and scrolls it into view", function()
    local c, PE = newClient()
    for _, mod in ipairs(PE.moduleList) do
        if canBeOn(PE, mod.key) then PE:SetModuleEnabled(mod.key, true) end
    end
    c:advance(0.5)
    for _, size in ipairs(SIZES) do
        PE:SetUISetting("size", size)
        c:advance(0.2)
        open(c, PE)
        local panel = guide(c)
        for i = 1, N do
            local where = size .. ", screen " .. i
            local reached, first = {}, nil
            for _ = 1, 80 do
                press(c, "RIGHT")
                local b = panel.peNavFocus
                check(b and b:IsVisible(), where .. ": the highlight is on nothing, or on a hidden button")
                if reached[b] then break end
                reached[b] = true
                if b.peScrollTop then
                    local area = areaOf(b)
                    local height = b.peScrollBottom - b.peScrollTop
                    check(b.peScrollTop >= area.offset - 0.5, where .. ": " .. T.labelOf(b) .. " is above the view")
                    check(math.min(b.peScrollBottom, b.peScrollTop + area.viewHeight) <= area.offset + area.viewHeight + 0.5,
                        where .. ": " .. T.labelOf(b) .. " is below the view (" .. height .. " high)")
                end
            end
            for _, b in ipairs(shownButtons(c, panel)) do
                check(reached[b], where .. ": the d-pad never reached " .. T.labelOf(b))
            end
            c:assertClean(where)
            if i < N then
                c:click(nextButton(c))
                c:advance(0.1)
            end
        end
        c:click(button(c, "Close"))
    end
end)

test("options: switching a feature on with A keeps the highlight on the switch, and the d-pad then walks its options", function()
    local c, PE = newClient()
    local sw = goToFeature(c, PE, "bags")
    local panel = guide(c)
    press(c, "DOWN")
    check(panel.peNavFocus == sw, "DOWN from nothing did not land on the switch")
    press(c, "A")
    c:advance(0.1)
    check(PE:IsModuleEnabled("bags"), "A did not switch Bag sorter on")
    check(panel.peNavFocus == sw and T.labelOf(sw) == "ON", "the highlight left the switch")
    local mod = PE:GetModule("bags")
    local want = {}
    for _, opt in ipairs(mod.options) do
        for _, b in ipairs(choiceButtons(c, panel, opt)) do want[#want + 1] = b end
    end
    for i, b in ipairs(want) do
        press(c, "RIGHT")
        check(panel.peNavFocus == b, "step " .. i .. " from the switch is " .. T.labelOf(panel.peNavFocus) .. ", expected " .. T.labelOf(b))
    end
    -- A on the last control (a toggle since 0.6.0): it flips, and the highlight stays on it
    local last = want[#want]
    local before = T.labelOf(last)
    press(c, "A")
    c:advance(0.1)
    check(panel.peNavFocus == last, "the highlight left the control")
    check(T.labelOf(last) ~= before or last.peSelected == true, "A did not change the control")
    -- DOWN moves a line at a time, so a few presses cross the whole list
    press(c, "UP")
    check(panel.peNavFocus ~= last, "UP did not leave the line")
    c:assertClean("d-pad in options")
end)

test("options: paging is decided again after every switch and option press, at each button size", function()
    local c, PE = newClient()
    local flips = 0
    local function invariant(where)
        local area
        walk(c, guide(c), function(w) if w.upButton and w.downButton then area = w end end)
        check(area, where .. ": no scrolling list")
        local paging = pagingShown(c)
        eq(paging, area:GetRange() > 0, where .. ": paging buttons shown")
        if paging then
            check(area.viewWidth < guide(c).contentWidth, where .. ": no room kept for the paging buttons")
        else
            eq(area.viewWidth, guide(c).contentWidth, where .. ": the list does not take the whole width")
        end
        return paging
    end
    for _, size in ipairs(SIZES) do
        PE:SetUISetting("size", size)
        c:advance(0.2)
        for _, mod in ipairs(PE.moduleList) do
            if canBeOn(PE, mod.key) then
                local key = mod.key
                goToFeature(c, PE, key)
                local off = invariant(size .. ", " .. key .. " off")
                c:click(switch(c, key))
                c:advance(0.1)
                local on = invariant(size .. ", " .. key .. " on")
                if on ~= off then flips = flips + 1 end
                for _, opt in ipairs(mod.options or {}) do
                    if type(opt.choices) == "table" then
                        c:click(choiceButtons(c, guide(c), opt)[1])
                        c:advance(0.1)
                        invariant(size .. ", " .. key .. " after \"" .. opt.label .. "\"")
                    end
                end
                c:click(switch(c, key))
                c:advance(0.1)
                eq(invariant(size .. ", " .. key .. " off again"), off, size .. ", " .. key .. ": paging after switching off again")
                c:assertClean(size .. ", " .. key)
                c:click(button(c, "Close"))
            end
        end
    end
    check(flips > 0, "no switch ever changed whether a screen needs paging (the test's premise)")
end)

test("options: every screen draws without error at every size, with every feature on and with every feature off", function()
    for _, allOn in ipairs({ false, true }) do
        local c, PE = newClient()
        if allOn then
            for _, mod in ipairs(PE.moduleList) do
                if canBeOn(PE, mod.key) then PE:SetModuleEnabled(mod.key, true) end
            end
            c:advance(0.5)
        end
        local report = {}
        for _, size in ipairs(SIZES) do
            PE:SetUISetting("size", size)
            c:advance(0.2)
            open(c, PE)
            local line = {}
            for i = 1, N do
                eq(title(c), TITLE .. " (" .. i .. " of " .. N .. ")")
                line[i] = pagingShown(c) and "page" or "fits"
                check(#texts(c) >= 2, size .. ", screen " .. i .. ": almost no text")
                c:assertClean((allOn and "all on, " or "all off, ") .. size .. ", screen " .. i)
                if i < N then goTo(c, 2) end
            end
            report[#report + 1] = "  " .. (allOn and "all on,  " or "all off, ") .. size .. ": " .. table.concat(line, " ")
            c:click(button(c, "Close"))
        end
        eq(#PE.errors, 0, "errors recorded while walking the guide")
        if os.getenv("SETUP_VERBOSE") then print(table.concat(report, "\n")) end
    end
end)

test("options: with options on screen the guide still has no per-frame code and listens for nothing once closed", function()
    -- Bag sorter and Big chat buttons: features with options that start no timers of their own.
    local c, PE = newClient({ on = { "bags", "chat" } })
    c:advance(0.5)
    c.stats.addonOnUpdate = 0
    open(c, PE)
    for i = 2, N do
        goTo(c, 2)
        if i == AT.bags then button(c, "Extra large") end
        if i == AT.chat then button(c, "+") end
    end
    c:advance(2)
    eq(c.stats.addonOnUpdate, 0, "something ticked while the guide was open")
    c:click(button(c, "Close"))
    c:advance(0.2)
    local made = 0
    walk(c, guide(c), function(w)
        local st = c._state(w)
        made = made + 1
        check(st.scripts.OnUpdate == nil, "a frame of the guide has an OnUpdate")
        check(next(st.events) == nil, "a frame of the guide listens for events")
    end)
    check(made > 20, "the walk over the guide's frames saw almost nothing: " .. made)
    local timers = c.stats.addonTimers
    c:advance(5)
    eq(c.stats.addonTimers, timers, "timers of ours while the guide is closed")
    c:assertClean("closed after options")
end)

return { known = KNOWN_FAILURES }
