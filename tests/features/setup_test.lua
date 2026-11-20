-- Rules for the setup guide (Setup.lua).
-- Source: docs/superpowers/specs/2026-11-20-0.9.0-ui-redesign.md, section
-- "Setup guide" (nine screens, the Quest icon details screen only while Quest
-- icons is on, step dots, feature cards, "Move things now"), and the first-run
-- rules it keeps from docs/superpowers/specs/2026-11-17-0.4.0-handheld-batch.md,
-- section "5. Setup guide" (opening once, Skip and Finish saving, fights).
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
local TITLE = "Setup"
-- The screens while Quest icons is off: "Quest icon details" is skipped.
local ALL_SCREENS = { "Welcome", "Quest icons", "Quest arrow", "Bags", "Vendors and menus", "Round button and chat",
    "Your screen", "All set" }
local IDS = { "welcome", "questIcons", "questArrow", "bags", "vendors", "chat", "layout", "finish" }
local N = #ALL_SCREENS
local AT = { welcome = 1, questIcons = 2, questArrow = 3, bags = 4, vendors = 5, chat = 6, layout = 7, finish = 8 }
-- The screen each feature's switch is on (Quest icons off).
local SCREEN_OF = { questIcons = 2, questArrow = 3, bagWindow = 4, bags = 4, sellJunk = 5, repair = 5, menuBg = 5, chat = 6 }
-- The settings tab of each feature.
local TAB_OF = { questIcons = "questIcons", questArrow = "questArrow", bagWindow = "bags", bags = "bags",
    sellJunk = "vendors", repair = "vendors", chat = "chat", menuBg = "menuBg" }
-- Quest icons' rows in the guide: three on its own screen, three on the details screen.
local QUEST_SCREEN_ROWS = { ["Show icons for"] = true, ["Icons on"] = true, ["Icon size"] = true }
local QUEST_DETAIL_ROWS = { ["Merge icons closer than"] = true, ["Spots per objective"] = true, ["Blizzard blue quest haze"] = true }

local function guide(c) return rawget(c.env, "PocketEssentialsSetupPanel") end
local function settingsPanel(c) return rawget(c.env, "PocketEssentialsSettingsPanel") end
local function movePanel(c) return rawget(c.env, "PocketEssentialsMovePanel") end
local function chatPanel(c) return rawget(c.env, "PocketEssentialsChatPanel") end
local function nav(c) return rawget(c.env, NAV_NAME) end
local function isOpen(c) return guide(c) ~= nil and guide(c):IsShown() end
local function moveOpen(c) return movePanel(c) ~= nil and movePanel(c):IsShown() end
local function bindings(c) return c._state(guide(c)).bindings end
local function title(c) return guide(c).peTitle:GetText() end

-- "pos of count" for the screen showing.
local function at(PE)
    local _, pos, count = PE.Setup:Screen()
    return pos .. " of " .. count
end

local function screenId(PE)
    return (PE.Setup:Screen())
end

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

-- The visible texts of a window that are not button labels.
local function textsOf(c, top)
    local out = {}
    walk(c, top, function(w)
        if c._state(w).type ~= "Button" then
            for _, r in ipairs(c._state(w).regions) do
                local st = c._state(r)
                if st.type == "FontString" and st.text and st.text ~= "" and r:IsVisible() then out[#out + 1] = st.text end
            end
        end
    end)
    return out
end

local function texts(c) return textsOf(c, guide(c)) end

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

-- n - 1 presses of Next / Start (from the first screen: to screen n).
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

-- The two Open buttons of the settings' General tab, top to bottom: Move things on screen, Setup guide.
local function generalOpenButtons(c, PE)
    PE:OpenSettings("general")
    c:advance(0.2)
    local open = shownButtons(c, settingsPanel(c), "Open")
    table.sort(open, function(a, b) return select(2, a:GetCenter()) > select(2, b:GetCenter()) end)
    return open
end

---------------------------------------------------------------------------
-- Opening by itself (first-run rules)
---------------------------------------------------------------------------

test("setup: opens by itself after the first loading screen on a fresh install", function()
    local c, PE = T.new({ firstRun = true })
    check(guide(c) == nil, "the guide was built at load")
    c:advance(1)
    check(guide(c) == nil, "the guide opened before the loading screen had settled")
    c:advance(1)
    check(isOpen(c), "the guide did not open by itself")
    eq(title(c), TITLE)
    eq(at(PE), "1 of " .. N)
    check(hasText(c, "Welcome"), "the first screen is not Welcome")
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
    eq(at(PE), "1 of " .. N)
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
    check(hasText(c, "Vendors and menus"), "screen " .. AT.vendors .. " is not Vendors and menus")
    eq(T.labelOf(switch(c, "sellJunk")), "On")
    eq(T.labelOf(switch(c, "repair")), "Off")
    goTo(c, 2)
    eq(T.labelOf(switch(c, "chat")), "On")
    c:click(button(c, "Skip"))
    eq(PE.db.enabled, { sellJunk = true, chat = true })
    eq(PE.db.setup, "skipped")
    c:assertClean("existing player")
end)

---------------------------------------------------------------------------
-- Screens, dots and switches
---------------------------------------------------------------------------

test("setup: the window is titled Setup; the screens are welcome, quest icons, quest arrow, bags, vendors and menus, round button and chat, your screen, all set", function()
    local c, PE = T.new({})
    open(c, PE)
    for i = 1, N do
        eq(title(c), TITLE)
        eq(at(PE), i .. " of " .. N)
        eq(screenId(PE), IDS[i])
        check(hasText(c, ALL_SCREENS[i]), "screen " .. i .. " has no title " .. ALL_SCREENS[i])
        eq(has(c, "Back"), i > 1, "Back on screen " .. i)
        eq(has(c, "Skip"), i < N, "Skip on screen " .. i)
        eq(T.labelOf(nextButton(c)), i == 1 and "Start" or i == N and "Finish" or "Next")
        if i < N then goTo(c, 2) end
    end
    check(not hasText(c, "Quest icon details"), "the details screen was shown with Quest icons off")
    eq(nextButton(c).peStyle, "on", "Finish is not green")
    c:click(button(c, "Back"))
    c:advance(0.1)
    eq(at(PE), (N - 1) .. " of " .. N)
    c:assertClean("screens")
end)

-- One dot per screen between Skip and Next, the current one gold.
local function dots(c)
    local out = {}
    for _, ch in ipairs(c._state(guide(c).content).children) do
        if ch.disc and ch:IsShown() then out[#out + 1] = ch end
    end
    return out
end

test("setup: one dot per screen between Skip and Next, the current one gold", function()
    local c, PE = T.new({})
    open(c, PE)
    for i = 1, N do
        local list = dots(c)
        eq(#list, N, "dots on screen " .. i)
        for k, dot in ipairs(list) do eq(dot.peCurrent == true, k == i, "dot " .. k .. " on screen " .. i) end
        local _, _, dotTop = c._rect(list[1])
        local _, _, _, nextBottom = c._rect(nextButton(c))
        check(dotTop > nextBottom, "the dots are not on the bottom row")
        if i < N then goTo(c, 2) end
    end
    c:assertClean("dots")
end)

-- The spec's skip: "Quest icon details" only while Quest icons is on.
test("setup: the Quest icon details screen shows only while Quest icons is on, as screen 3 of 9", function()
    if not T.questieDB then return end
    local c, PE = T.new({ quest = true })
    open(c, PE)
    eq(at(PE), "1 of 8")
    goTo(c, 2)
    eq(screenId(PE), "questIcons")
    c:click(switch(c, "questIcons"))
    c:advance(0.1)
    eq(at(PE), "2 of 9", "switching Quest icons on did not add the details screen")
    eq(#dots(c), 9)
    goTo(c, 2)
    eq(screenId(PE), "questDetails")
    check(hasText(c, "Quest icon details"), "no details title")
    for _, name in ipairs({ "Merge icons closer than", "Spots per objective", "Blizzard blue quest haze", "What the icons mean",
        "Kill", "Loot", "Use", "Explore", "Turn in" }) do
        check(textWith(c, name), "the details screen has no " .. name)
    end
    check(not textWith(c, "Show icons for"), "a first-screen row is on the details screen")
    check(not has(c, "Open"), "the Icon key row is in the guide")
    goTo(c, 2)
    eq(screenId(PE), "questArrow")
    eq(at(PE), "4 of 9")
    -- off again: skipped
    PE:SetModuleEnabled("questIcons", false)
    c:advance(0.1)
    eq(at(PE), "3 of 8")
    c:click(button(c, "Back"))
    c:advance(0.1)
    eq(screenId(PE), "questIcons")
    c:assertClean("details screen")
end)

test("setup: every feature of this build has a switch on some screen, and the old long texts are gone", function()
    local c, PE = T.new({})
    open(c, PE)
    local seen = {}
    local all = {}
    for i = 1, N do
        for _, b in ipairs(shownButtons(c, guide(c))) do
            if b.peKey then seen[b.peKey] = (seen[b.peKey] or 0) + 1 end
        end
        for _, t in ipairs(texts(c)) do all[#all + 1] = t end
        for key, screen in pairs(SCREEN_OF) do
            if screen == i then switch(c, key) end
        end
        if i < N then goTo(c, 2) end
    end
    for _, mod in ipairs(PE.moduleList) do
        eq(seen[mod.key], 1, "switches for " .. mod.key)
    end
    local joined = table.concat(all, "\n")
    for _, part in ipairs({ "Bag icons", "Sort stick", "Bag sorter", "Chat from round button", "Move the round button",
        "bottom row", "Pocket Essentials - Setup guide" }) do
        check(not joined:find(part, 1, true), "a screen still says \"" .. part .. "\"")
    end
end)

test("setup: the cards carry the spec's How: lines for quest icons, quest arrow, chat picker and menu background", function()
    local c, PE = T.new({})
    open(c, PE)
    local all = {}
    for i = 1, N do
        for _, t in ipairs(texts(c)) do all[#all + 1] = t end
        if i < N then goTo(c, 2) end
    end
    local joined = table.concat(all, "\n")
    for _, line in ipairs({ "Tap an icon on the map to see what it is for.",
        "Focus a quest in your quest log, and the arrow points to it.",
        "Tap PE, pick who to talk to, then press A to type.",
        "For menus like Track, Focus and Share on a quest." }) do
        check(joined:find("How: |r" .. line, 1, true), "no How: line \"" .. line .. "\"")
    end
end)

test("setup: a switch calls the same path as the settings switch", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, AT.vendors)
    c:click(switch(c, "sellJunk"))
    c:advance(0.1)
    check(PE:IsModuleEnabled("sellJunk"), "the switch did not turn Sell junk on")
    eq(PE.db.enabled.sellJunk, true)
    eq(T.labelOf(switch(c, "sellJunk")), "On")
    eq(switch(c, "sellJunk").peStyle, "on")
    eq(T.labelOf(switch(c, "repair")), "Off")
    c:click(switch(c, "sellJunk"))
    c:advance(0.1)
    check(not PE:IsModuleEnabled("sellJunk"), "the switch did not turn Sell junk off")
    eq(PE.db.enabled.sellJunk, false)
    eq(T.labelOf(switch(c, "sellJunk")), "Off")
    c:click(switch(c, "repair"))
    c:advance(0.1)
    -- the settings window shows the same
    PE:OpenSettings("vendors")
    c:advance(0.2)
    check(not isOpen(c), "the guide stayed open under the settings")
    local on = 0
    for _, b in ipairs(shownButtons(c, settingsPanel(c))) do
        if b.peKey and T.labelOf(b) == "On" then on = on + 1 end
    end
    eq(on, 1, "switches reading On in the settings")
    check(PE:IsModuleEnabled("repair") and not PE:IsModuleEnabled("sellJunk"), "the wrong feature is on")
    c:assertClean("switch")
end)

test("setup: a feature switched on in the settings shows On in the guide", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, AT.vendors)
    eq(T.labelOf(switch(c, "repair")), "Off")
    PE:SetModuleEnabled("repair", true)
    c:advance(0.1)
    eq(T.labelOf(switch(c, "repair")), "On")
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
        eq(at(PE), SCREEN_OF[key] .. " of " .. N)
        eq(T.labelOf(switch(c, key)), "Off")
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
    goTo(c, AT.vendors - AT.questArrow + 1)
    eq(switch(c, "menuBg").peStyle, "off")
    c:click(switch(c, "menuBg"))
    c:advance(0.1)
    check(PE:IsModuleEnabled("menuBg"), "Menu background did not switch on")
    eq(T.labelOf(switch(c, "menuBg")), "On")
    c:assertClean("blocked switches")
end)

test("setup: a card whose feature is not registered is left out, and a screen with no card left is skipped", function()
    -- a copy of the addon whose TOC leaves Vendor.lua and MenuBackground.lua out
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
        changed, n = changed:gsub("MenuBackground%.lua\r?\n", "")
        eq(n, 1, "MenuBackground.lua lines in the TOC")
        f = assert(io.open(path, "wb"))
        f:write(changed)
        f:close()
        local c, PE = T.new({ addonDir = dir })
        check(PE:GetModule("sellJunk") == nil and PE:GetModule("repair") == nil and PE:GetModule("menuBg") == nil,
            "the vendor and menu features still registered")
        open(c, PE)
        local seenTitles = {}
        for i = 1, N - 1 do
            eq(at(PE), i .. " of " .. (N - 1))
            for _, name in ipairs(ALL_SCREENS) do
                if hasText(c, name) then seenTitles[#seenTitles + 1] = name end
            end
            if i < N - 1 then goTo(c, 2) end
        end
        check(not table.concat(seenTitles, "|"):find("Vendors and menus", 1, true), "the empty screen was shown")
        eq(T.labelOf(nextButton(c)), "Finish")
        c:assertClean("a build without the vendor and menu features")
    end)
    if dir:find("pe-setup-test-", 1, true) then sh("rm -rf '" .. dir .. "'") end
    if not ok then error(err, 0) end
end)

test("setup: the finish screen lists what is on and what is off, then the Tap, Hold and Move things tiles", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, N)
    check(hasText(c, "|cff59eb73On: |rnothing yet"), "no \"On: nothing yet\" line")
    local off = textWith(c, "Off: |r")
    check(off, "no Off line with everything off")
    for _, mod in ipairs(PE.moduleList) do
        check(off:find(mod.label, 1, true), "Off does not name " .. mod.label)
    end

    PE:SetModuleEnabled("sellJunk", true)
    PE:SetModuleEnabled("chat", true)
    c:advance(0.1)
    check(hasText(c, "|cff59eb73On: |rAuto sell junk, Chat picker"), "the On line is wrong: " .. tostring(textWith(c, "On: |r")))
    eq(textWith(c, "Off: |r"), "|cff9e9ea3Off: |rQuest icons, Quest arrow, Bag sorting, Bigger bag, Auto repair, Menu background")
    for _, t in ipairs({ "Tap", "Hold", "Move things", "Opens the settings, or Chat picker when it is on.",
        "Always opens the settings.", "Settings, General tab." }) do
        check(hasText(c, t), "the tiles have no \"" .. t .. "\"")
    end
    check(not has(c, "Reload now"), "a reload is offered although nothing asked for one")
    c:assertClean("finish screen")
end)

test("setup: the three tiles have the same width and height and sit side by side", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, N)
    local tops, lefts = {}, {}
    for _, name in ipairs({ "Tap", "Hold", "Move things" }) do
        local found
        walk(c, guide(c), function(w)
            for _, r in ipairs(c._state(w).regions) do
                if c._state(r).text == name and r:IsVisible() then found = r end
            end
        end)
        check(found, "no tile title " .. name)
        local l, r, t = c._rect(found)
        tops[#tops + 1], lefts[#lefts + 1] = t, l
        eq(r - l > 0, true)
    end
    check(math.abs(tops[1] - tops[2]) < 0.01 and math.abs(tops[2] - tops[3]) < 0.01, "the titles are not on one line")
    check(lefts[1] < lefts[2] and lefts[2] < lefts[3], "the tiles are not side by side")
    check(math.abs((lefts[2] - lefts[1]) - (lefts[3] - lefts[2])) < 0.01, "the tiles are not the same width")
    c:assertClean("tiles")
end)

test("setup: with every feature on the finish screen has no Off line", function()
    if not T.questieDB then return end -- the quest features cannot be on without QuestieDB
    local c, PE = T.new({ quest = true, gamepadUI = true })
    for _, mod in ipairs(PE.moduleList) do PE:SetModuleEnabled(mod.key, true) end
    c:advance(0.5)
    open(c, PE)
    goTo(c, N + 1) -- nine screens with Quest icons on
    check(textWith(c, "On: |rQuest icons, Quest arrow, Bag sorting"), "no On line")
    check(not textWith(c, "Off: |r"), "an Off line with everything on")
end)

test("setup: the finish screen offers a reload when a feature asked for one", function()
    local c, PE = T.new({ gamepadUI = false, setup = function(c) c.world.cvars.combinedBags = "0" end })
    open(c, PE)
    goTo(c, AT.bags)
    c:click(switch(c, "bags"))
    c:advance(0.2)
    check(#PE.reloadReasons > 0, "Bag sorting asked for no reload (the test's premise)")
    goTo(c, N - AT.bags + 1)
    eq(at(PE), N .. " of " .. N)
    check(textWith(c, "Bag sorting: "), "the reason for the reload is not shown")
    local before = #c:callsTo("C_UI.Reload")
    eq(PE.db.setup, "skipped") -- what T.new stored
    PE.db.setup = nil
    c:click(button(c, "Reload now"))
    eq(#c:callsTo("C_UI.Reload") - before, 1, "Reload now called C_UI.Reload")
    eq(PE.db.setup, "finished", "the reload did not store Finish first")
    c:assertClean("reload offer")
end)

-- Review of 0.4.0, point 3: the click runs inside PE:Safe, so an error in it lands on our
-- Errors page and never reaches the game; Finish is still stored first.
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
-- The screens' own cards
---------------------------------------------------------------------------

test("setup: Welcome has the play-style row and the controls card with its three glyphs", function()
    local c, PE = T.new({ on = { "bags" } })
    open(c, PE)
    for _, t in ipairs({ "A few helpers for playing on a handheld. They all start off: switch on the ones you want.",
        "You can change everything later in the settings.", "How do you play?", "Getting around these windows",
        "Move the blue highlight", "Press the highlighted button", "Close the window",
        "Or just tap any button on the screen." }) do
        check(hasText(c, t), "Welcome has no \"" .. t .. "\"")
    end
    check(hasText(c, "A") and hasText(c, "B"), "no round A and B glyphs")
    c:click(button(c, "Controller"))
    c:advance(0.1)
    check(hasText(c, "Touch works too, any time."), "the controller line did not replace the touch line")
    check(not hasText(c, "Or just tap any button on the screen."), "the touch line stayed")
    c:assertClean("welcome cards")
end)

-- The live round button beside its two choices.
local function hubPreview(c)
    local found
    walk(c, guide(c), function(w)
        if w.outer and w.word and w:IsVisible() and c._state(w.word).text == "PE" then
            local l, r = c._rect(w)
            if not found or (r - l) > found.width then found = { frame = w, width = r - l } end
        end
    end)
    return found and found.frame
end

test("setup: Round button and chat shows a live round button that follows the colour and the button size", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, AT.chat)
    check(hasText(c, "The PE button is always on screen. With Chat picker on, a tap opens the chat window."), "no lead line")
    check(textWith(c, "Colour") and textWith(c, "Size of all Pocket Essentials buttons"), "no Colour or size rows")
    switch(c, "chat")
    local preview = hubPreview(c)
    check(preview, "no round button picture")
    local function width() local l, r = c._rect(hubPreview(c)); return r - l end
    eq(math.abs(width() - PE.UI:Metrics().hub * 1.6) < 0.01, true, "the picture is not 1.6 times the round button")
    local function ringColor() return { c._state(hubPreview(c).outer.texture).vertexColor } end
    local gold = ringColor()
    c:click(button(c, "Horde"))
    c:advance(0.1)
    eq(PE.db.ui.hubColor, "horde")
    check(T.show(ringColor()) ~= T.show(gold), "the picture did not change colour")
    eq(button(c, "Horde").peStyle, "segmentOn")
    c:click(button(c, "Large"))
    c:advance(0.2)
    eq(PE.db.ui.size, "large")
    eq(math.abs(width() - PE.UI:Metrics().hub * 1.6) < 0.01, true, "the picture did not follow the button size")
    c:assertClean("round button card")
end)

-- The labels of the gold boxes in the screen picture.
test("setup: Your screen shows a gold box for each of the three pieces, with Move things now beside it", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, AT.layout)
    check(hasText(c, "This is where each piece sits to start with. Move any of them to suit your screen."), "no lead line")
    for _, t in ipairs({ "Quest arrow", "Press A to type", "Round button", "Gold boxes show where each piece starts.",
        "You can do this later too: Settings, General tab." }) do
        check(hasText(c, t), "Your screen has no \"" .. t .. "\"")
    end
    button(c, "Move things now")
    c:assertClean("your screen")
end)

test("setup: a moved round button moves its box in the screen picture", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, AT.layout)
    local function labelTop(name)
        local found
        walk(c, guide(c), function(w)
            for _, r in ipairs(c._state(w).regions) do
                if c._state(r).text == name and r:IsVisible() then found = r end
            end
        end)
        local _, _, t = c._rect(found)
        return t
    end
    local before = labelTop("Round button")
    PE.db.ui.moved.hub = { x = 0, y = 200 }
    PE:RefreshSettings()
    c:advance(0.1)
    check(labelTop("Round button") > before + 1, "the box did not follow the round button up")
end)

test("setup: Move things now hides the guide and opens Move on screen; closing it brings the guide back on the same screen", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    goTo(c, AT.layout)
    c:click(button(c, "Move things now"))
    c:advance(0.1)
    check(not isOpen(c), "the guide stayed open")
    check(moveOpen(c), "Move on screen did not open")
    eq(linesWith(c, "Setup guide closed"), 0, "opening Move printed the closed line")
    eq(PE.db.setup, nil, "opening Move counted as an answer")
    c:click(shownButtons(c, movePanel(c), "Close")[1])
    c:advance(0.1)
    check(not moveOpen(c), "Move on screen did not close")
    check(isOpen(c), "the guide did not come back")
    eq(at(PE), AT.layout .. " of " .. N)
    eq(bindings(c), ALL_KEYS)
    -- B closes Move the same way
    c:click(button(c, "Move things now"))
    c:advance(0.1)
    press(c, "B")
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after B")
    eq(at(PE), AT.layout .. " of " .. N)
    c:assertClean("move things now")
end)

test("setup: Move the arrow in the guide behaves like Move things now, with the arrow picked", function()
    if not T.questieDB then return end
    local c, PE = T.new({ quest = true, on = { "questArrow" } })
    open(c, PE)
    goTo(c, AT.questArrow)
    eq(screenId(PE), "questArrow")
    c:click(button(c, "Move the arrow"))
    c:advance(0.1)
    check(not isOpen(c), "the guide stayed open")
    check(moveOpen(c), "Move on screen did not open")
    check(shownButtons(c, movePanel(c), "Quest arrow")[1].peSelected, "the arrow is not picked")
    c:click(shownButtons(c, movePanel(c), "Close")[1])
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back")
    eq(screenId(PE), "questArrow")
    c:assertClean("move the arrow")
end)

test("setup: the guide does not come back over another window that closed Move on screen", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, AT.layout)
    c:click(button(c, "Move things now"))
    c:advance(0.1)
    PE:OpenSettings()
    c:advance(0.2)
    check(not moveOpen(c), "Move on screen stayed open")
    check(settingsPanel(c):IsShown(), "the settings did not open")
    check(not isOpen(c), "the guide came back over the settings")
    PE:CloseSettings()
    c:advance(0.2)
    check(not isOpen(c), "the guide came back later")
    c:assertClean("move then settings")
end)

test("setup: a fight while Move on screen is open brings the guide back on the same screen after the fight", function()
    local c, PE = T.new({})
    open(c, PE)
    goTo(c, AT.layout)
    c:click(button(c, "Move things now"))
    c:advance(0.1)
    c:enterCombat()
    c:advance(0.1)
    check(not moveOpen(c), "Move on screen stayed open in a fight")
    check(not isOpen(c), "the guide came back in a fight")
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    eq(at(PE), AT.layout .. " of " .. N)
    c:assertClean("move and fight")
end)

---------------------------------------------------------------------------
-- Closing and remembering
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
-- Reopening
---------------------------------------------------------------------------

test("setup: the General tab's Setup guide row closes the settings and opens the guide at screen 1", function()
    local c, PE = T.new({})
    local open2 = generalOpenButtons(c, PE)
    local settings = settingsPanel(c)
    eq(#open2, 2, "the General tab does not have its two Open buttons")
    check(textsOf(c, settings)[1] ~= nil, "no texts in the settings")
    c:click(open2[2])
    c:advance(0.2)
    check(not settings:IsShown(), "the settings stayed open")
    check(isOpen(c), "the guide did not open")
    eq(at(PE), "1 of " .. N)
    -- reopened from the middle: back at the first screen
    goTo(c, 3)
    c:click(generalOpenButtons(c, PE)[2])
    c:advance(0.2)
    eq(at(PE), "1 of " .. N)
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
-- Fights
---------------------------------------------------------------------------

test("setup: a fight starting hides it; it comes back at the same screen afterwards", function()
    local c, PE = T.new({ firstRun = true })
    c:advance(2)
    goTo(c, 3)
    eq(at(PE), "3 of " .. N)
    c:enterCombat()
    check(not isOpen(c), "the guide stayed on screen in a fight")
    eq(bindings(c), nil, "the controller keys were kept in a fight")
    eq(PE.db.setup, nil, "a fight counted as an answer")
    eq(linesWith(c, "Setup guide closed"), 0, "a fight printed the closed line")
    c:advance(2)
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    eq(at(PE), "3 of " .. N)
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

-- Review of 0.4.0, point 2: the game hides its whole interface for a cinematic or a
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
    eq(at(PE), "3 of " .. N)
    eq(bindings(c), ALL_KEYS)
    c:enterCombat()
    check(not isOpen(c), "the guide stayed on screen in a fight after the interface came back")
    eq(linesWith(c, "Setup guide closed"), 0, "a fight printed the closed line")
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    eq(at(PE), "3 of " .. N)
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
    eq(at(PE), "2 of " .. N)
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
    eq(at(PE), "2 of " .. N)
    eq(linesWith(c, "Setup guide closed"), 0)
    c:enterCombat()
    check(not isOpen(c), "the guide stayed on screen in a fight")
    c:leaveCombat()
    c:advance(0.1)
    check(isOpen(c), "the guide did not come back after the fight")
    c:assertClean("fight while hidden")
end)

---------------------------------------------------------------------------
-- Controller
---------------------------------------------------------------------------

test("setup: the d-pad reaches every button; A presses; B closes", function()
    local c, PE = T.new({})
    open(c, PE)
    local panel = guide(c)
    eq(bindings(c), ALL_KEYS)
    check(panel.peNavFocus == button(c, "Start"), "the highlight does not start on Start (0.8.0)")
    panel:NavSetFocus(nil) -- the rest of this test presses the d-pad from nothing
    goTo(c, AT.vendors) -- Vendors and menus: three switches
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
    local paging = 0
    for _, b in ipairs(shownButtons(c, panel)) do
        check(reached[b], "the d-pad never reached " .. T.labelOf(b))
        if T.labelOf(b) == "^" or T.labelOf(b) == "v" then paging = paging + 1 end
    end
    eq(count - paging, 7, "buttons in the d-pad's round: three switches, Back, Skip, Next, Close")
    -- A on Next moves a screen
    while panel.peNavFocus ~= nextButton(c) do press(c, "RIGHT") end
    press(c, "A")
    c:advance(0.1)
    eq(at(PE), AT.chat .. " of " .. N)
    press(c, "B")
    check(not isOpen(c), "B did not close the guide")
    c:assertClean("d-pad")
end)

test("setup: the highlight stays on Next from screen to screen, and on a switch after pressing it", function()
    local c, PE = T.new({})
    open(c, PE)
    local panel = guide(c)
    panel:NavSetFocus(nil)
    press(c, "UP") -- from nothing: the last button, Close
    press(c, "LEFT")
    local nextBtn = nextButton(c)
    check(panel.peNavFocus == nextBtn, "LEFT from Close is not Next")
    for i = 2, N do
        press(c, "A")
        c:advance(0.1)
        eq(at(PE), i .. " of " .. N)
        check(panel.peNavFocus == nextBtn and nextBtn.peNavFocused ~= false, "the highlight left Next on screen " .. i)
    end
    -- Back to the first screen with the highlight on Back: Back goes away, the highlight goes to Next
    press(c, "LEFT")
    check(panel.peNavFocus == button(c, "Back"), "LEFT from Finish is not Back")
    for _ = 1, N - 1 do
        press(c, "A")
        c:advance(0.1)
    end
    eq(at(PE), "1 of " .. N)
    check(panel.peNavFocus == nextBtn, "the highlight did not go to Start when Back went away")
    -- a switch keeps the highlight after it is pressed
    goTo(c, AT.vendors)
    local sw = switch(c, "repair")
    while panel.peNavFocus ~= sw do press(c, "RIGHT") end
    press(c, "A")
    c:advance(0.1)
    check(PE:IsModuleEnabled("repair"), "A on the switch did not turn Repair on")
    check(panel.peNavFocus == switch(c, "repair"), "the highlight left the switch")
    eq(T.labelOf(panel.peNavFocus), "On")
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
-- Nothing runs while closed, sizes, debug log
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
    for _ = 2, N do goTo(c, 2) end -- every screen, the screen picture and the tiles too
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
            eq(at(PE), i .. " of " .. N)
            c:assertClean(size .. ", screen " .. i)
            if i < N then goTo(c, 2) end
        end
        PE:SetUISetting("size", size == "small" and "large" or "small")
        c:advance(0.2)
        check(isOpen(c), "a size change closed the guide")
        eq(at(PE), N .. " of " .. N)
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
                local area = guide(c).peNavArea
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
    -- The welcome screen is short at Medium.
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
    goTo(c, 3)
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
    local all = "screens: welcome, questIcons, questArrow, bags, vendors, chat, layout, finish"
    eq(debugLines(c, "setup"), {
        "first login check: not needed (finished)",
        "opened (settings)", all, "screen 1 of 8: welcome",
        "screen 2 of 8: questIcons", "screen 3 of 8: questArrow",
        "switch tapped: questArrow cannot be switched on",
        "screen 4 of 8: bags", "screen 5 of 8: vendors",
        "switch tapped: menuBg -> on",
        "switch tapped: menuBg -> off",
        "closed: fight started, will come back",
        "not opened: in a fight",
        "opened (after the fight)", all, "screen 5 of 8: vendors",
        "closed: not remembered (Close)",
        "opened (slash)", all, "screen 1 of 8: welcome",
        "closed: not remembered (B, Escape or another window)",
        "opened (settings)", all, "screen 1 of 8: welcome",
        "closed: skipped",
        "opened (settings)", all, "screen 1 of 8: welcome",
        "screen 2 of 8: questIcons", "screen 3 of 8: questArrow", "screen 4 of 8: bags", "screen 5 of 8: vendors",
        "screen 6 of 8: chat", "screen 7 of 8: layout", "screen 8 of 8: finish",
        "closed: finished",
    })
    eq(PE.db.setup, "finished")
    c:assertClean("debug lines")
end)

test("setup: the debug log says when Move on screen takes the guide's place and when it comes back", function()
    local c, PE = T.new({ saved = { debug = { on = true } } })
    open(c, PE)
    goTo(c, AT.layout)
    c:click(button(c, "Move things now"))
    c:advance(0.1)
    c:click(shownButtons(c, movePanel(c), "Close")[1])
    c:advance(0.1)
    local lines = debugLines(c, "setup")
    eq({ lines[#lines - 3], lines[#lines - 2], lines[#lines - 1], lines[#lines] }, {
        "closed: Move on screen opened, will come back", "opened (after move)",
        "screens: welcome, questIcons, questArrow, bags, vendors, chat, layout, finish", "screen 7 of 8: layout" })
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
-- Options in the guide's cards
--
-- What a feature's rows should look like is worked out here from the
-- feature's own `options` list, not from the drawing code: a row is its name
-- on the left and its control on the right; a choices row is one segment per
-- choice, the saved one in the selected style; a number row is "-" and "+";
-- an action row is one button reading its `button` text ("Open" when
-- missing); a buttons row is its name and its buttons.
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

-- The screen of the guide that holds this row of a feature: "card" (the
-- feature's own screen), "details" (Quest icon details) or nil (not in the
-- guide: rows that open another settings page).
local function guideScreenOf(mod, opt)
    if opt.page ~= nil then return nil end
    if mod.key == "questIcons" then
        if QUEST_SCREEN_ROWS[opt.label] then return "card" end
        if QUEST_DETAIL_ROWS[opt.label] then return "details" end
        return nil
    end
    return "card"
end

local function goToFeature(c, PE, key)
    open(c, PE)
    for _ = 1, 12 do
        if screenId(PE) == (key == "bagWindow" and "bags" or (key == "sellJunk" or key == "repair" or key == "menuBg") and "vendors"
            or key) then break end
        c:click(nextButton(c))
        c:advance(0.1)
    end
    return switch(c, key)
end

-- To the screen that holds a row (the details screen for Quest icons' last rows).
local function goToRow(c, PE, mod, opt)
    goToFeature(c, PE, mod.key)
    if guideScreenOf(mod, opt) == "details" then
        c:click(nextButton(c))
        c:advance(0.1)
        eq(screenId(PE), "questDetails")
    end
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

-- The buttons of a row: right of its name, left to right. The row's control
-- is the one whose middle is nearest the name's; its parts share that middle.
local function rowButtons(c, top, label, PE)
    local at = textRegion(c, top, label)
    if not at then return nil end
    local nl, _, nt, nb = c._rect(at.region)
    local mid = (nt + nb) / 2
    local reach = PE.UI:Metrics().button
    local best
    for _, b in ipairs(shownButtons(c, top)) do
        local l, _, t, bottom = c._rect(b)
        local d = math.abs((t + bottom) / 2 - mid)
        if l > nl and d <= reach and (not best or d < best.d) then best = { d = d, y = (t + bottom) / 2 } end
    end
    local out = {}
    for _, b in ipairs(shownButtons(c, top)) do
        local l, _, t, bottom = c._rect(b)
        if best and l > nl and math.abs((t + bottom) / 2 - best.y) < 1 then out[#out + 1] = { b = b, l = l } end
    end
    table.sort(out, function(x, y) return x.l < y.l end)
    for i = 1, #out do out[i] = out[i].b end
    return out
end

-- The value a choices row shows: its get, or the saved value of its key.
local function currentOf(mod, opt)
    if type(opt.get) == "function" then return opt.get(mod) end
    return mod.opts[opt.key]
end

-- The segments of one choices row, in the order of its choices; nil when the row is not drawn.
local function choiceButtons(c, top, mod, opt, PE)
    local after = rowButtons(c, top, opt.label, PE)
    if not after then return nil end
    local out = {}
    for i, choice in ipairs(opt.choices) do
        local b = after[i]
        check(b and T.labelOf(b) == tostring(choice.label), "under \"" .. opt.label .. "\" segment " .. i .. " reads "
            .. tostring(b and T.labelOf(b)) .. ", expected " .. tostring(choice.label), 2)
        out[i] = b
    end
    return out
end

local function chosen(b) return b.peStyle == "segmentOn" end

-- Checks that `top` draws (shown = true) or does not draw one option row of a feature.
local function checkOption(c, top, mod, opt, shown, where, PE)
    if type(opt.choices) == "table" then
        local buttons = choiceButtons(c, top, mod, opt, PE)
        eq(buttons ~= nil, shown, where .. ": \"" .. opt.label .. "\" drawn")
        if shown then
            for i, choice in ipairs(opt.choices) do
                eq(chosen(buttons[i]), currentOf(mod, opt) == choice.value,
                    where .. ": \"" .. opt.label .. "\" / " .. tostring(choice.label) .. " marked")
            end
        end
    elseif type(opt.number) == "table" or type(opt.stepper) == "function" then
        local region = textRegion(c, top, opt.label)
        eq(region ~= nil, shown, where .. ": \"" .. opt.label .. "\" drawn")
        if shown then
            local after = rowButtons(c, top, opt.label, PE)
            eq({ T.labelOf(after[1]), T.labelOf(after[2]) }, { "-", "+" }, where .. ": the ends of \"" .. opt.label .. "\"")
        end
    elseif type(opt.action) == "function" then
        local region = textRegion(c, top, opt.label)
        eq(region ~= nil, shown, where .. ": \"" .. opt.label .. "\" drawn")
        if shown then
            local after = rowButtons(c, top, opt.label, PE)
            eq(T.labelOf(after[1]), opt.button or "Open", where .. ": the button of \"" .. opt.label .. "\"")
        end
    else
        eq(textRegion(c, top, opt.label) ~= nil, shown, where .. ": \"" .. opt.label .. "\" drawn")
        if shown then
            local list = type(opt.buttons) == "function" and opt.buttons(mod) or opt.buttons
            local after = rowButtons(c, top, opt.label, PE)
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

local function pagingShown(c)
    local up, down = shownButtons(c, guide(c), "^"), shownButtons(c, guide(c), "v")
    eq(#up, #down, "Up and Down go together")
    return #up > 0
end

test("options: the test's own reading of the screen list matches the features", function()
    local c, PE = newClient()
    for _, mod in ipairs(PE.moduleList) do
        check(SCREEN_OF[mod.key], "no screen known for " .. mod.key)
        check(TAB_OF[mod.key], "no settings tab known for " .. mod.key)
    end
    check(#modsWithOptions(PE) >= 4, "fewer than four features have options (the test's premise)")
    open(c, PE)
    for i = 1, N do
        for key, screen in pairs(SCREEN_OF) do
            if screen == i then switch(c, key) end
        end
        if i < N then goTo(c, 2) end
    end
end)

test("options: off, a card shows only its rows marked always; switched on, its rows under its switch", function()
    local c, PE = newClient()
    local sawAlways = false
    for _, mod in ipairs(modsWithOptions(PE)) do
        if canBeOn(PE, mod.key) then
            local key = mod.key
            local sw = goToFeature(c, PE, key)
            eq(T.labelOf(sw), "Off")
            for _, opt in ipairs(mod.options) do
                if opt.always then sawAlways = true end
                checkOption(c, guide(c), mod, opt, opt.always == true and guideScreenOf(mod, opt) == "card", key .. " off", PE)
            end
            c:click(sw)
            c:advance(0.1)
            check(PE:IsModuleEnabled(key), key .. " did not switch on")
            check(switch(c, key) == sw, key .. ": the switch is another button after the press")
            local _, _, _, switchBottom = c._rect(sw)
            for _, opt in ipairs(mod.options) do
                local here = guideScreenOf(mod, opt) == "card"
                checkOption(c, guide(c), mod, opt, here, key .. " on", PE)
                if here then
                    local _, _, top = c._rect(textRegion(c, guide(c), opt.label).region)
                    check(top < switchBottom, key .. ": \"" .. opt.label .. "\" is not under the switch")
                end
            end
            check(not has(c, "Hide options") and not has(c, "Show options"), key .. ": the guide has a fold button")
            c:click(switch(c, key))
            c:advance(0.1)
            for _, opt in ipairs(mod.options) do
                checkOption(c, guide(c), mod, opt, opt.always == true and guideScreenOf(mod, opt) == "card", key .. " off again", PE)
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
    checkOption(c, guide(c), mod, mod.options[1], true, "guide, chat off", PE)
    checkOption(c, guide(c), mod, extra, false, "guide, chat off", PE)
    PE:OpenSettings("chat")
    c:advance(0.2)
    checkOption(c, settingsPanel(c), mod, mod.options[1], true, "settings, chat off", PE)
    checkOption(c, settingsPanel(c), mod, extra, false, "settings, chat off", PE)
    c:click(goToFeature(c, PE, "chat"))
    c:advance(0.1)
    checkOption(c, guide(c), mod, mod.options[1], true, "guide, chat on", PE)
    checkOption(c, guide(c), mod, extra, true, "guide, chat on", PE)
    PE:OpenSettings("chat")
    c:advance(0.2)
    checkOption(c, settingsPanel(c), mod, extra, true, "settings, chat on", PE)
    c:assertClean("always rows")
end)

test("options: the guide draws what the settings window draws for the same feature", function()
    local c, PE = newClient()
    for _, mod in ipairs(modsWithOptions(PE)) do
        if canBeOn(PE, mod.key) then PE:SetModuleEnabled(mod.key, true) end
    end
    c:advance(0.5)
    local compared = 0
    for _, mod in ipairs(modsWithOptions(PE)) do
        if canBeOn(PE, mod.key) then
            for _, opt in ipairs(mod.options) do
                if guideScreenOf(mod, opt) then
                    goToRow(c, PE, mod, opt)
                    checkOption(c, guide(c), mod, opt, true, mod.key .. " in the guide", PE)
                    PE:OpenSettings(TAB_OF[mod.key])
                    c:advance(0.2)
                    checkOption(c, settingsPanel(c), mod, opt, true, mod.key .. " in the settings", PE)
                    compared = compared + 1
                end
            end
        end
    end
    check(compared >= 5, "only " .. compared .. " rows were compared")
    c:assertClean("same drawing")
end)

test("options: a choice pressed in the guide is saved, runs the same OnChange and shows in the settings, and the other way round", function()
    local c, PE = newClient()
    local pressed = 0
    for _, mod in ipairs(modsWithOptions(PE)) do
        if canBeOn(PE, mod.key) then
            PE:SetModuleEnabled(mod.key, true)
            c:advance(0.3)
            for _, opt in ipairs(mod.options) do
                if type(opt.choices) == "table" and guideScreenOf(mod, opt) then
                    local calls = {}
                    local original = opt.OnChange
                    opt.OnChange = function(...)
                        calls[#calls + 1] = { ... }
                        if original then return original(...) end
                    end
                    local where = mod.key .. " / " .. opt.label
                    -- A choice that is not the saved one (the nth such), and its segment.
                    local function pick(top, nth)
                        local current = currentOf(mod, opt)
                        local others = {}
                        for i, choice in ipairs(opt.choices) do
                            if choice.value ~= current then others[#others + 1] = i end
                        end
                        local i = others[nth] or others[1]
                        return choiceButtons(c, top, mod, opt, PE)[i], opt.choices[i].value, i
                    end

                    -- in the guide
                    goToRow(c, PE, mod, opt)
                    local btn, value, index = pick(guide(c), 1)
                    c:click(btn)
                    c:advance(0.1)
                    eq(currentOf(mod, opt), value, where .. ": saved after the press in the guide")
                    if opt.key ~= nil then
                        eq(PE.db.options[mod.key][opt.key], value, where .. ": in the saved table")
                    end
                    eq(#calls, 1, where .. ": OnChange calls after the press in the guide")
                    check(calls[1][1] == mod and calls[1][2] == value, where .. ": OnChange got other arguments")
                    check(chosen(choiceButtons(c, guide(c), mod, opt, PE)[index]), where .. ": not marked in the guide")
                    PE:OpenSettings(TAB_OF[mod.key])
                    c:advance(0.2)
                    checkOption(c, settingsPanel(c), mod, opt, true, where .. ", settings after the guide", PE)

                    -- in the settings
                    btn, value, index = pick(settingsPanel(c), 2)
                    c:click(btn)
                    c:advance(0.2)
                    eq(currentOf(mod, opt), value, where .. ": saved after the press in the settings")
                    eq(#calls, 2, where .. ": OnChange calls after the press in the settings")
                    check(calls[2][1] == mod and calls[2][2] == value, where .. ": OnChange got other arguments")
                    goToRow(c, PE, mod, opt)
                    check(not settingsPanel(c):IsShown(), "the settings stayed open under the guide")
                    checkOption(c, guide(c), mod, opt, true, where .. ", guide after the settings", PE)
                    check(chosen(choiceButtons(c, guide(c), mod, opt, PE)[index]), where .. ": not marked in the guide")
                    opt.OnChange = original
                    pressed = pressed + 1
                end
            end
            c:assertClean(mod.key)
        end
    end
    check(pressed >= 3, "only " .. pressed .. " choices were tried")
end)

-- The number in the chat text size box (between - and +) in a window.
local function stepperNumber(c, top)
    local smaller, bigger = shownButtons(c, top, "-")[1], shownButtons(c, top, "+")[1]
    check(smaller and bigger, "no - / + pair", 2)
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

test("options: the chat text size control works in the guide with Chat picker off, and both windows show the same number", function()
    local c, PE = newClient()
    check(not PE:IsModuleEnabled("chat"), "chat is on (the test's premise)")
    goToFeature(c, PE, "chat")
    local start = stepperNumber(c, guide(c))
    check(start, "no number between - and + in the guide")
    c:click(button(c, "+"))
    c:advance(0.1)
    local bigger = stepperNumber(c, guide(c))
    check(bigger > start, "+ in the guide did not raise the number: " .. tostring(bigger))
    eq(c.chatSizes[1], bigger, "the chat window's size")
    PE:OpenSettings("chat")
    c:advance(0.2)
    eq(stepperNumber(c, settingsPanel(c)), bigger, "the settings show another size")
    c:click(shownButtons(c, settingsPanel(c), "-")[1])
    c:advance(0.2)
    c:click(shownButtons(c, settingsPanel(c), "-")[1])
    c:advance(0.2)
    local smaller = stepperNumber(c, settingsPanel(c))
    check(smaller < start, "- twice in the settings did not lower the number")
    goToFeature(c, PE, "chat")
    eq(stepperNumber(c, guide(c)), smaller, "the guide shows another size")
    eq(c.chatSizes[1], smaller)
    check(not PE:IsModuleSavedOn("chat"), "the control switched Chat picker on")
    -- the highlight stays on the button after a press with A
    local panel = guide(c)
    press(c, "DOWN")
    while panel.peNavFocus ~= button(c, "+") do press(c, "RIGHT") end
    press(c, "A")
    c:advance(0.1)
    check(panel.peNavFocus == button(c, "+"), "the highlight left +")
    check(stepperNumber(c, guide(c)) > smaller, "A on + did nothing")
    c:assertClean("stepper")
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
    check(hasText(c, "Bag sorting: Test reason."), "the reason is not on the finish screen")
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
        local area = panel.peNavArea
        local _, _, count = PE.Setup:Screen()
        for i = 1, count do
            local where = size .. ", screen " .. i
            local reached = {}
            for _ = 1, 80 do
                press(c, "RIGHT")
                local b = panel.peNavFocus
                check(b and b:IsVisible(), where .. ": the highlight is on nothing, or on a hidden button")
                if reached[b] then break end
                reached[b] = true
                if b.peScrollTop then
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
            if i < count then
                c:click(nextButton(c))
                c:advance(0.1)
            end
        end
        c:click(button(c, "Close"))
    end
end)

test("options: switching a feature on with A keeps the highlight on the switch, and the d-pad then walks its options", function()
    local c, PE = newClient()
    -- Bigger bag: the first switch on the Bags screen.
    local sw = goToFeature(c, PE, "bagWindow")
    local panel = guide(c)
    panel:NavSetFocus(nil)
    press(c, "DOWN")
    check(panel.peNavFocus == sw, "DOWN from nothing did not land on the switch")
    press(c, "A")
    c:advance(0.1)
    check(PE:IsModuleEnabled("bagWindow"), "A did not switch Bigger bag on")
    check(panel.peNavFocus == sw and T.labelOf(sw) == "On", "the highlight left the switch")
    local mod = PE:GetModule("bagWindow")
    local want = {}
    for _, opt in ipairs(mod.options) do
        for _, b in ipairs(choiceButtons(c, panel, mod, opt, PE)) do want[#want + 1] = b end
    end
    for i, b in ipairs(want) do
        press(c, "RIGHT")
        check(panel.peNavFocus == b, "step " .. i .. " from the switch is " .. T.labelOf(panel.peNavFocus) .. ", expected " .. T.labelOf(b))
    end
    -- A on the last segment: it is chosen, and the highlight stays on it
    local last = want[#want]
    press(c, "A")
    c:advance(0.1)
    check(panel.peNavFocus == last, "the highlight left the control")
    check(chosen(last), "A did not choose the segment")
    press(c, "UP")
    check(panel.peNavFocus ~= last, "UP did not leave the line")
    c:assertClean("d-pad in options")
end)

test("options: paging is decided again after every switch and option press, at each button size", function()
    local c, PE = newClient()
    local flips = 0
    local function invariant(where)
        local area = guide(c).peNavArea
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
                    if type(opt.choices) == "table" and guideScreenOf(mod, opt) == "card" then
                        c:click(choiceButtons(c, guide(c), mod, opt, PE)[1])
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
            local _, _, count = PE.Setup:Screen()
            local line = {}
            for i = 1, count do
                eq(at(PE), i .. " of " .. count)
                line[i] = pagingShown(c) and "page" or "fits"
                check(#texts(c) >= 2, size .. ", screen " .. i .. ": almost no text")
                c:assertClean((allOn and "all on, " or "all off, ") .. size .. ", screen " .. i)
                if i < count then goTo(c, 2) end
            end
            report[#report + 1] = "  " .. (allOn and "all on,  " or "all off, ") .. size .. ": " .. table.concat(line, " ")
            c:click(button(c, "Close"))
        end
        eq(#PE.errors, 0, "errors recorded while walking the guide")
        if os.getenv("SETUP_VERBOSE") then print(table.concat(report, "\n")) end
    end
end)

test("options: with options on screen the guide still has no per-frame code and listens for nothing once closed", function()
    -- Bag sorting, Bigger bag and Chat picker: features with options that start no timers of their own.
    local c, PE = newClient({ on = { "bags", "bagWindow", "chat" } })
    c:advance(0.5)
    c.stats.addonOnUpdate = 0
    open(c, PE)
    for i = 2, N do
        goTo(c, 2)
        if i == AT.bags then button(c, "Extra large") end
        if i == AT.chat then c:click(shownButtons(c, guide(c), "+")[1]) end
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

---------------------------------------------------------------------------
-- How do you play? (the same save and Sort button rule as General's "I play with")
---------------------------------------------------------------------------

test("touch: opening the guide puts the controller highlight on Start", function()
    local c, PE = newClient({ on = { "bags" } })
    open(c, PE)
    check(guide(c).peNavFocus == button(c, "Start"), "the highlight is not on Start")
    c:assertClean("focus on start")
end)

test("touch: Controller saves ui.touch false, hides the Sort button and redraws with no scroll bar", function()
    local c, PE = newClient({ on = { "bags" } })
    open(c, PE)
    c:click(button(c, "Controller"))
    c:advance(0.1)
    eq(PE.db.ui.touch, false)
    eq(PE.db.options.bags.showTab, false)
    check(not has(c, "^") and not has(c, "v"), "a scroll bar is showing with touch off")
    c:assertClean("controller")
end)

test("touch: Touch controls after Controller brings the Sort button back", function()
    local c, PE = newClient({ on = { "bags" } })
    open(c, PE)
    c:click(button(c, "Controller"))
    c:advance(0.1)
    c:click(button(c, "Touch controls"))
    c:advance(0.1)
    eq(PE.db.ui.touch, true)
    eq(PE.db.options.bags.showTab, true)
    c:assertClean("touch after controller")
end)

test("touch: Touch controls shows the Sort button, as the General tab's I play with does", function()
    local c, PE = newClient({ on = { "bags" } })
    open(c, PE)
    PE.db.options.bags.showTab = false
    c:click(button(c, "Touch controls"))
    c:advance(0.1)
    eq(PE.db.ui.touch, true)
    eq(PE.db.options.bags.showTab, true)
    c:assertClean("touch controls")
end)

test("touch: the guide marks the current answer", function()
    local c, PE = newClient({ on = { "bags" } })
    open(c, PE)
    check(chosen(button(c, "Touch controls")) and not chosen(button(c, "Controller")), "Touch controls is not marked at the start")
    c:click(button(c, "Controller"))
    c:advance(0.1)
    check(chosen(button(c, "Controller")) and not chosen(button(c, "Touch controls")), "Controller is not marked after Controller")
    c:assertClean("touch marked")
end)

-- 0.8.0, spec section 2: the Bags screen holds both bag features.
test("bags split: the Bags screen has a switch for Bigger bag and one for Bag sorting", function()
    local c, PE = newClient()
    open(c, PE)
    goTo(c, AT.bags)
    switch(c, "bagWindow")
    switch(c, "bags")
    c:click(switch(c, "bagWindow"))
    c:advance(0.1)
    check(PE:IsModuleEnabled("bagWindow"), "the guide's switch did not switch Bigger bag on")
    check(has(c, "Extra large") and hasText(c, "Bag size"), "Bigger bag's options are not under its switch")
    c:assertClean("bags screen")
end)

-- Controller hides the Sort button through Bag sorting's own row, so an open
-- bag loses its tab at once, whichever stick is chosen.
test("touch: Controller hides the Sort tab of an open bag at once, with either stick chosen", function()
    local c, PE = newClient({ on = { "bags" } })
    PE.db.options.bags.sortKey = "r3"
    c:openBag()
    c:advance(0.1)
    local rec = c:find(function(r) return r.addonFile ~= nil and r.type == "Button" and T.labelOf(r.frame) == "Sort"
        and r.frame:GetParent() == c.UIParent end)
    check(rec and rec.frame:IsVisible(), "no Sort tab with the bag open (the test's premise)")
    open(c, PE)
    c:click(button(c, "Controller"))
    c:advance(0.1)
    eq(PE.db.options.bags.showTab, false)
    check(not rec.frame:IsVisible(), "the Sort tab still shows after Controller")
    c:assertClean("controller hides tab")
end)

-- 0.8.0 fix: touch off, a tall screen with no list buttons is paged by the d-pad.
test("touch: with touch off the d-pad Down pages a tall finish screen to its bottom", function()
    local c, PE = newClient({ on = { "bags" } })
    PE:SetUISetting("touch", false)
    open(c, PE)
    for _ = 1, 40 do
        if has(c, "Finish") then break end
        c:click(nextButton(c))
        c:advance(0.1)
    end
    check(has(c, "Finish"), "never reached the last screen")
    local area = guide(c).peNavArea
    area:SetContentHeight(area.viewHeight * 3)   -- a screen taller than the view
    check(area:GetRange() > 20, "the finish screen does not scroll")
    local key = rawget(c.env, NAV_NAME)
    for _ = 1, 40 do
        c:script(key, "OnClick", "DOWN", true)
        c:script(key, "OnClick", "DOWN", false)
        if area.offset >= area:GetRange() - 0.5 then break end
    end
    check(area.offset >= area:GetRange() - 0.5, "the d-pad never reached the bottom: " .. area.offset .. " of " .. area:GetRange())
    c:assertClean("finish d-pad")
end)

-- Spec 2026-11-19-0.8.1-clearer-labels, and 0.9.0: rows that open another settings page stay out of the guide.
test("setup: no guide screen says Big chat buttons or has the Icon key row", function()
    local c, PE = T.new({ quest = true, on = { "questIcons", "chat" } })
    open(c, PE)
    local _, _, count = PE.Setup:Screen()
    for i = 1, count do
        for _, t in ipairs(texts(c)) do
            check(not t:find("Big chat buttons", 1, true) and not t:find("Icon key", 1, true), "screen " .. i .. ": " .. t)
        end
        for _, b in ipairs(shownButtons(c, guide(c))) do
            local l = tostring(T.labelOf(b))
            check(not l:find("Big chat", 1, true) and l ~= "Icon key", "screen " .. i .. " button: " .. l)
        end
        if i < count then goTo(c, 2) end
    end
end)

return { known = KNOWN_FAILURES }
