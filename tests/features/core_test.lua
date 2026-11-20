-- Rules for the core (Core.lua): saved settings, the feature registry, the
-- error log, the combat queue and /pe reset.
-- Sources: Core.lua's comments; docs/DECISIONS.md "General" ("Errors are logged
-- quietly ...", "/pe reset ..."); CLAUDE.md "Conventions" (features default off,
-- handlers go through PE:Safe or PE:Wrap); PRD.md goals 3 and 4.
-- The debug log: docs/superpowers/specs/2026-11-17-debug-log.md and Core.lua "Debug log".
-- Each test names its source in a comment. Fresh client and addon per test.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local FEATURES = { "questIcons", "questArrow", "bags", "bagWindow", "sellJunk", "repair", "chat", "menuBg" }

local function saved(enabled, options)
    return { version = 1, enabled = enabled or {}, options = options or {}, ui = { size = "medium", hubPos = "LEFT" }, errors = {} }
end

local function errorsOf(PE, key)
    local out = {}
    for _, e in ipairs(PE.errors) do
        if e.module == key then out[#out + 1] = e end
    end
    return out
end

-- How many chat lines the addon printed that contain `text`.
local function linesWith(c, text)
    local n = 0
    for _, line in ipairs(T.chatLines(c)) do
        if line:find(text, 1, true) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------

-- CLAUDE.md "Features default off until device-tested"; Core.lua Login: only `== true` enables.
test("core: every feature is off on first install", function()
    local c, PE = T.new({})
    eq(PE.db.enabled, {})
    for _, key in ipairs(FEATURES) do
        check(PE:GetModule(key) ~= nil, "feature " .. key .. " did not register")
        check(not PE:IsModuleEnabled(key), key .. " is on at first install")
        check(not PE:IsModuleSavedOn(key), key .. " is saved on at first install")
    end
    eq(#T.gameCalls(c), 0, "the addon called game functions that change something at first install")
end)

-- Core.lua Login line 714: `PE.db.enabled[mod.key] == true`.
test("core: only a saved true switches a feature on", function()
    local c, PE = T.new({ saved = saved({ sellJunk = true, repair = "true", chat = 1, bags = false, questArrow = {} }) })
    check(PE:IsModuleEnabled("sellJunk"), "sellJunk saved as true is not on")
    check(not PE:IsModuleEnabled("repair"), "repair saved as the text \"true\" is on")
    check(not PE:IsModuleEnabled("chat"), "chat saved as 1 is on")
    check(not PE:IsModuleEnabled("bags"), "bags saved as false is on")
    check(not PE:IsModuleEnabled("questArrow"), "questArrow saved as a table is on")
    c:assertClean("login")
end)

-- 0.3.0 removed the Layout helper; a 0.2.1 save that still has "layout" on must not break anything.
test("core: a saved Layout helper from 0.2.1 is ignored: no module, no row, no error", function()
    local c, PE = T.new({ saved = saved({ layout = true, sellJunk = true }) })
    eq(PE:GetModule("layout"), nil)
    check(PE:IsModuleEnabled("sellJunk"), "sell junk did not come back on")
    PE:OpenSettings()
    c:advance(0.2)
    c:assertClean("0.2.1 saved layout")
end)

-- Core.lua AttachOptions lines 314-328: a default is added only where the key is nil.
test("core: new default options are added to old saved options without overwriting chosen values", function()
    local old = saved({}, {
        questIcons = { show = "all", size = "large", map = false },           -- an older version: no spots, cluster, mini ...
        chat = { whispers = { { name = "Ann", target = "Ann", unanswered = true, time = 5 } } },
    })
    local c, PE = T.new({ saved = old })
    local opts = PE:GetModule("questIcons").opts
    check(opts == rawget(c.env, "PocketEssentialsDB").options.questIcons, "the saved table was not the one used")
    eq(opts.show, "all"); eq(opts.size, "large"); eq(opts.map, false)    -- chosen values kept (false is a choice too)
    eq(opts.spots, 5); eq(opts.cluster, 2); eq(opts.mini, true); eq(opts.hideHaze, true)  -- defaults added
    eq(PE:GetModule("chat").opts.whispers[1].name, "Ann")
    eq(PE:GetModule("bagWindow").opts.size, "normal", "a feature with no saved options gets its defaults")
    eq(PE.db.ui, { size = "medium", hubPos = "LEFT", folded = {}, moved = {} })
end)

---------------------------------------------------------------------------
-- A feature that fails
---------------------------------------------------------------------------

-- Core.lua EnableModule lines 419-442: a failed OnEnable marks the feature failed, calls its
-- OnDisable, keeps the error; other features still enable (Login loop).
test("core: an error in one feature's OnEnable marks it failed, calls OnDisable, logs one error; others still enable", function()
    local disabled = 0
    local c, PE = T.new({ saved = saved({ probe = true, sellJunk = true, repair = true }) })
    check(not PE:GetModule("probe"), "probe should not exist yet")
    PE:RegisterModule({
        key = "probe", label = "Probe feature", order = 5,
        OnEnable = function(self)
            self:RegisterEvent("ZONE_CHANGED", function() end)
            error("probe broke", 0)
        end,
        OnDisable = function() disabled = disabled + 1 end,
    })
    eq(disabled, 1, "OnDisable calls")
    eq((PE:GetModuleState("probe")), "failed")
    check(not PE:IsModuleEnabled("probe"), "a failed feature reports itself as on")
    local errs = errorsOf(PE, "probe")
    eq(#errs, 1)
    eq(errs[1].msg, "probe broke")
    eq(errs[1].count, 1)
    eq(#PE.errors, 1, "no other error was recorded")
    eq(linesWith(c, "Probe feature hit a problem"), 1)
    -- its event registration was dropped, and the others work
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile then check(not rec.events.ZONE_CHANGED, "ZONE_CHANGED is still registered after the failed enable") end
    end
    check(PE:IsModuleEnabled("sellJunk") and PE:IsModuleEnabled("repair"), "the other features did not enable")
end)

-- The same through a real feature at login: sell junk cannot enable without UseContainerItem
-- (Vendor.lua OnEnable raises); repair and chat saved on still come up.
test("core: at login a feature that cannot enable does not stop the features after it", function()
    local c, PE = T.new({
        saved = saved({ sellJunk = true, repair = true, chat = true }),
        setup = function(c)
            local orig, partial = c.env.C_Container, {}
            for _, k in ipairs({ "GetContainerNumSlots", "GetContainerItemInfo", "SortBags", "GetBackpackSellJunkDisabled", "GetBagSlotFlag" }) do
                partial[k] = orig[k]
            end
            rawset(c.env, "C_Container", partial)   -- no UseContainerItem
        end,
    })
    eq((PE:GetModuleState("sellJunk")), "failed")
    eq((PE:GetModuleState("repair")), "on")
    eq((PE:GetModuleState("chat")), "on")
    local errs = errorsOf(PE, "sellJunk")
    eq(#errs, 1)
    eq(errs[1].msg, "This game version does not have the functions needed to sell items.")
    eq(#PE.errors, 1)
end)

---------------------------------------------------------------------------
-- Errors inside handlers
---------------------------------------------------------------------------

-- A feature made in the test: ZONE_CHANGED handlers that raise `msg`, plus a second feature
-- that counts its calls (it must still run after the first one failed).
local function twoProbes(PE)
    local state = { msg = "boom", second = 0 }
    PE:RegisterModule({
        key = "probe", label = "Probe feature", order = 1,
        OnEnable = function(self)
            self:RegisterEvent("ZONE_CHANGED", function() error(state.msg, 0) end)
        end,
    })
    PE:RegisterModule({
        key = "probe2", label = "Probe two", order = 2,
        OnEnable = function(self)
            self:RegisterEvent("ZONE_CHANGED", function() state.second = state.second + 1 end)
        end,
    })
    PE:SetModuleEnabled("probe", true)
    PE:SetModuleEnabled("probe2", true)
    return state
end

-- Core.lua LogErrorBody lines 79-92: the same message from the same feature counts up.
-- DECISIONS "General": "Errors are logged quietly with one chat line per feature per session".
test("core: an error in an event handler is recorded once per message with a count, and does not propagate", function()
    local c, PE = T.new({})
    local state = twoProbes(PE)
    for _ = 1, 3 do c:fire("ZONE_CHANGED") end
    eq(c.errors, {}, "the error reached the game's error list")
    local errs = errorsOf(PE, "probe")
    eq(#errs, 1)
    eq(errs[1].msg, "boom")
    eq(errs[1].count, 3)
    eq(state.second, 3, "the next feature's handler did not run after the first failed")
    state.msg = "a different message"
    c:fire("ZONE_CHANGED")
    eq(#errorsOf(PE, "probe"), 2)
    eq(PE.errors[1].msg, "a different message", "newest first")
    eq(PE.errors[2].count, 3)
    eq(linesWith(c, "Probe feature hit a problem"), 1, "one chat line per feature per session")
end)

-- Core.lua ERROR_CAP = 30 (line 21), LogErrorBody line 95.
test("core: at most 30 errors are kept, the newest", function()
    local c, PE = T.new({})
    local state = twoProbes(PE)
    for i = 1, 35 do
        state.msg = "problem " .. i
        c:fire("ZONE_CHANGED")
    end
    eq(#PE.errors, 30)
    eq(PE.errors[1].msg, "problem 35")
    eq(PE.errors[30].msg, "problem 6")
    eq(rawget(c.env, "PocketEssentialsDB").errors, PE.errors, "the kept list is the saved one")
end)

---------------------------------------------------------------------------
-- /pe reset
---------------------------------------------------------------------------

-- DECISIONS "General": "/pe reset puts the round button and button size back to default."
-- Core.lua SlashCommand lines 816-819.
test("core: /pe reset restores the round button position and the button size", function()
    local c, PE = T.new({})
    local hub = PE.Hub.button
    local widthMedium = hub:GetWidth()
    local pointMedium = hub:GetPoint(1)
    PE:SetUISetting("size", "large")
    PE:SetUISetting("hubPos", "RIGHT")
    check(hub:GetWidth() ~= widthMedium, "the large size did not change the round button")
    check(hub:GetPoint(1) ~= pointMedium, "the round button did not move")
    eq(PE.db.ui, { size = "large", hubPos = "RIGHT", folded = {}, moved = {} })
    c.env.SlashCmdList.POCKETESSENTIALS("reset")
    eq(PE.db.ui, { size = "medium", hubPos = "LEFT", folded = {}, moved = {} })
    eq(hub:GetWidth(), widthMedium)
    eq(hub:GetPoint(1), pointMedium)
    eq(T.chatLines(c), { "Button size and round button position were reset." })
    c:assertClean("/pe reset")
end)

---------------------------------------------------------------------------
-- The combat queue
---------------------------------------------------------------------------

-- Core.lua RunOutOfCombat lines 200-211 and FlushCombatQueue lines 213-227.
test("core: PE:RunOutOfCombat runs at once out of combat", function()
    local c, PE = T.new({})
    local ran = 0
    PE:RunOutOfCombat("probe:once", function() ran = ran + 1 end)
    eq(ran, 1)
end)

test("core: PE:RunOutOfCombat defers while in combat and runs once after PLAYER_REGEN_ENABLED", function()
    local c, PE = T.new({})
    local ran = {}
    c:enterCombat()
    PE:RunOutOfCombat("probe:job", function() ran[#ran + 1] = "first" end)
    PE:RunOutOfCombat("probe:job", function() ran[#ran + 1] = "second" end)  -- same key: the latest one is kept
    c:advance(5)
    eq(ran, {}, "ran during combat")
    c:leaveCombat()
    eq(ran, { "second" })
    c:fire("PLAYER_REGEN_ENABLED")
    c:advance(2)
    eq(ran, { "second" }, "ran a second time")
    c:assertClean("combat queue")
end)


---------------------------------------------------------------------------
-- /pe, saved errors, one line per feature
---------------------------------------------------------------------------

local function settingsShown(c)
    local p = rawget(c.env, "PocketEssentialsSettingsPanel")
    return p ~= nil and p:IsShown()
end

-- Core.lua SlashCommand lines 812-823.
test("core: /pe errors opens the settings on the errors page", function()
    local c, PE = T.new({})
    local asked = {}
    local open = PE.OpenSettings
    PE.OpenSettings = function(self, which) asked[#asked + 1] = which or "main" return open(self, which) end
    c.env.SlashCmdList.POCKETESSENTIALS("errors")
    eq(asked, { "errors" })
    check(settingsShown(c), "the settings window did not open")
    c.env.SlashCmdList.POCKETESSENTIALS("  ERRORS ")   -- spaces and capitals are ignored
    eq(asked, { "errors", "errors" })
end)

test("core: bare /pe, and /pe with an unknown word, toggle the settings window", function()
    local c, PE = T.new({})
    local slash = c.env.SlashCmdList.POCKETESSENTIALS
    slash("")
    check(settingsShown(c), "/pe did not open the settings")
    slash("")
    check(not settingsShown(c), "a second /pe did not close the settings")
    slash("bogus")
    check(settingsShown(c), "/pe bogus did not open the settings")
    c:assertClean("/pe")
end)

-- Core.lua MergeErrors lines 330-357 and ERROR_CAP.
test("core: saved errors are merged at load: same message counts add up, damaged ones drop, 30 kept", function()
    local list = {
        { module = "chat", msg = "old trouble", count = 2, last = 5, stack = "" },
        { module = "chat", msg = "old trouble", count = 3, last = 6, stack = "" },
        { module = "bags", msg = "other", count = 1, last = 7, stack = "" },
        { module = "bags", count = 9 },       -- no message: dropped
        "junk",
    }
    for i = 1, 40 do list[#list + 1] = { module = "core", msg = "saved " .. i, count = 1, last = i, stack = "" } end
    local c, PE = T.new({ saved = { version = 1, enabled = {}, options = {}, ui = {}, errors = list } })
    eq(#PE.errors, 30)
    eq(PE.errors[1].msg, "old trouble"); eq(PE.errors[1].count, 5)
    eq(PE.errors[2].msg, "other")
    eq(PE.errors[30].msg, "saved 28")
    -- new errors go on top and the cap still holds across the reload
    for i = 1, 4 do PE:LogError("core", "new " .. i) end
    eq(#PE.errors, 30)
    eq(PE.errors[1].msg, "new 4")
    eq(PE.errors[30].msg, "saved 24")
    eq(rawget(c.env, "PocketEssentialsDB").errors, PE.errors)
end)

-- Core.lua LogErrorBody lines 98-101: announced per module key.
test("core: each failing feature gets its own chat line, once", function()
    local c, PE = T.new({})
    local state = { a = "first", b = "second" }
    PE:RegisterModule({ key = "pa", label = "Probe A", order = 1, OnEnable = function(self)
        self:RegisterEvent("ZONE_CHANGED", function() error(state.a, 0) end) end })
    PE:RegisterModule({ key = "pb", label = "Probe B", order = 2, OnEnable = function(self)
        self:RegisterEvent("ZONE_CHANGED", function() error(state.b, 0) end) end })
    PE:SetModuleEnabled("pa", true)
    PE:SetModuleEnabled("pb", true)
    c:fire("ZONE_CHANGED")
    state.a, state.b = "third", "fourth"
    c:fire("ZONE_CHANGED")
    eq(linesWith(c, "Probe A hit a problem"), 1)
    eq(linesWith(c, "Probe B hit a problem"), 1)
    eq(#PE.errors, 4)
end)

---------------------------------------------------------------------------
-- The on/off switch is saved; a switched-off feature's timers
---------------------------------------------------------------------------

-- Core.lua SetModuleEnabled (line 640: db.enabled[key] = on); Settings.lua calls it from the switch;
-- Login enables on a saved true. A copy of the saved table is loaded into a fresh client.
test("core: switching a feature on is saved, and a fresh client with that saved table has it on; off is saved too", function()
    local c, PE = T.new({})
    PE:SetModuleEnabled("sellJunk", true)
    local db = rawget(c.env, "PocketEssentialsDB")
    eq(db.enabled.sellJunk, true)
    local c2, PE2 = T.new({ saved = { version = 1, enabled = { sellJunk = db.enabled.sellJunk }, options = {}, ui = db.ui, errors = {} } })
    check(PE2:IsModuleEnabled("sellJunk"), "the feature is off after a restart")
    PE2:SetModuleEnabled("sellJunk", false)
    local db2 = rawget(c2.env, "PocketEssentialsDB")
    eq(db2.enabled.sellJunk, false)
    local _, PE3 = T.new({ saved = { version = 1, enabled = { sellJunk = db2.enabled.sellJunk }, options = {}, ui = db2.ui, errors = {} } })
    check(not PE3:IsModuleEnabled("sellJunk"), "the feature came back on after being switched off")
end)

-- Core.lua Methods:After (line 506): "Skipped if the module was switched off ... meanwhile."
test("core: a feature's pending timer does not fire after the feature is switched off", function()
    local c, PE = T.new({})
    local fired = {}
    local mod = PE:RegisterModule({ key = "probe", label = "Probe", order = 99 })
    PE:SetModuleEnabled("probe", true)
    mod:After(5, function() fired[#fired + 1] = "before" end)
    PE:SetModuleEnabled("probe", false)
    c:advance(6)
    eq(fired, {}, "a timer fired after its feature was switched off")
    PE:SetModuleEnabled("probe", true)
    mod:After(1, function() fired[#fired + 1] = "after" end)
    c:advance(2)
    eq(fired, { "after" }, "a timer set after switching on did not fire")
    c:assertClean("timer")
end)

-- Spec 2026-11-16-blocked-action-report: a block of ours goes on the Errors page with the function's
-- name and the features that were on; one chat line per function per session.
test("core: a block of ours is logged with its function, and announced once per function", function()
    local c, PE = T.new({ on = { "chat" } })
    c:fire("ADDON_ACTION_FORBIDDEN", "PocketEssentials", "UseContainerItem")
    c:fire("ADDON_ACTION_FORBIDDEN", "PocketEssentials", "UseContainerItem")
    c:fire("ADDON_ACTION_BLOCKED", "PocketEssentials", "SetAttribute")
    local errs = errorsOf(PE, "blocked")
    eq(#errs, 2, "one entry per function")
    local forbade
    for _, e in ipairs(errs) do if e.msg:find("UseContainerItem", 1, true) then forbade = e end end
    check(forbade, "no entry names UseContainerItem")
    eq(forbade.count, 2, "the repeat was counted")
    check(forbade.msg:find("forbade", 1, true), "entry does not say forbade: " .. forbade.msg)
    check(forbade.msg:find("Chat picker", 1, true), "entry does not list the features on: " .. forbade.msg)
    eq(linesWith(c, "The game blocked Pocket Essentials from using UseContainerItem"), 1)
    eq(linesWith(c, "The game blocked Pocket Essentials from using SetAttribute"), 1)
    eq(linesWith(c, "hit a problem"), 0, "the generic problem line is not added for blocks")
    eq(PE.blockedSerial, 3)
end)

-- Spec 2026-11-16-blocked-action-report: another addon's block is none of ours.
test("core: another addon's block is ignored", function()
    local c, PE = T.new({ on = { "chat" } })
    c:fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "CastSpellByName")
    c:fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "CastSpellByName")
    eq(#errorsOf(PE, "blocked"), 0)
    eq(PE.blockedSerial, 0)
    c:assertClean("other addon")
end)

-- Spec 2026-11-16-blocked-action-report: Blizzard's own "Interface action failed" message is
-- recorded only when our code is on the stack.
test("core: Blizzard's blocked message with none of our code on the stack is not ours", function()
    local c, PE = T.new({ on = { "chat" } })
    c.env.DisplayInterfaceActionBlockedMessage()
    eq(#errorsOf(PE, "blocked"), 0)
    c:assertClean("blizzard message")
end)

---------------------------------------------------------------------------
-- The debug log
---------------------------------------------------------------------------

local LINE = "^%d%d:%d%d:%d%d%.%d%d%d "   -- HH:MM:SS.mmm and a space

local function debugOf(c) return rawget(c.env, "PocketEssentialsDB").debug end

-- The stored lines containing `text` (plain match), in slot order.
local function debugLines(c, text)
    local out = {}
    for _, line in ipairs(debugOf(c).lines) do
        if line:find(text, 1, true) then out[#out + 1] = line end
    end
    return out
end

-- Addon frames that listen for `event`.
local function listeners(c, event)
    local n = 0
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile and rec.events[event] then n = n + 1 end
    end
    return n
end

-- Spec "Cost while off": "No text is built, nothing is stored"; "off by default".
test("debug: off on first install, and nothing is stored while off", function()
    local c, PE = T.new({})
    eq(PE.debugOn, false)
    eq(debugOf(c), { on = false, lines = {}, next = 1 })
    PE:Debug("probe", "a line while off")
    PE:SetModuleEnabled("sellJunk", true)
    PE:SetModuleEnabled("sellJunk", false)
    PE:LogError("core", "an error while off")
    c:enterCombat()
    c:leaveCombat()
    eq(debugOf(c), { on = false, lines = {}, next = 1 })
    eq(PE:DebugCount(), 0)
end)

-- Spec "What it does": "a timestamped line for each thing"; Core.lua PE:Debug builds
-- "HH:MM:SS.mmm key: text"; SetDebug writes the "switched on" header first.
test("debug: while on, lines are stored in order as HH:MM:SS.mmm key: text", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    eq(PE.debugOn, true)
    eq(debugOf(c).on, true)
    PE:Debug("probe", "first")
    PE:Debug("probe", "second")
    local lines = debugOf(c).lines
    eq(#lines, 3)
    eq(PE:DebugCount(), 3)
    eq(debugOf(c).next, 4)
    check(lines[1]:find(LINE .. "core: %-%-%-%- debug log switched on %-%-%-%- "), "no header line: " .. lines[1])
    check(lines[1]:find("addon=0.0.0-test", 1, true), "the header does not give the addon version: " .. lines[1])
    check(lines[1]:find("features=none", 1, true), "the header does not list the features on: " .. lines[1])
    check(lines[2]:find(LINE .. "probe: first$"), "unexpected line: " .. lines[2])
    check(lines[3]:find(LINE .. "probe: second$"), "unexpected line: " .. lines[3])
end)

-- Spec "Size": "each cut at 200 characters" (Core.lua DEBUG_LINE_MAX).
test("debug: a line is cut at 200 characters", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    PE:Debug("probe", string.rep("x", 500))
    PE:Debug("probe", "short")
    local lines = debugOf(c).lines
    eq(#lines[2], 200)
    check(lines[2]:find(LINE .. "probe: x+$"), "the cut line lost its start: " .. lines[2]:sub(1, 40))
    check(#lines[3] < 200, "a short line was padded")
end)

-- Spec "Size": "10,000 lines ... When full, the oldest lines are replaced (a ring ...)".
-- Core.lua: "Once full, the oldest line is at `next`". The saved table is filled to two
-- short of the cap before load so the test makes only a few real calls across the wrap.
test("debug: the ring keeps at most DEBUG_CAP lines, and after wrapping the oldest is at next", function()
    local cap = 10000
    local lines = {}
    for i = 1, cap - 2 do lines[i] = "old " .. i end
    local db = saved()
    db.debug = { on = false, lines = lines, next = cap - 1 }
    local c, PE = T.new({ saved = db })
    eq(PE.DEBUG_CAP, cap)
    eq(PE:DebugCount(), cap - 2)
    PE:SetDebug(true)                      -- the header takes slot cap - 1
    PE:Debug("probe", "fills the last slot")
    local store = debugOf(c)
    check(store.lines == lines, "the saved list was not the one used")
    eq(#store.lines, cap)
    eq(store.next, 1, "next did not wrap to the first slot")
    check(store.lines[cap]:find("probe: fills the last slot", 1, true), "the last slot holds: " .. store.lines[cap])
    PE:Debug("probe", "replaces the oldest")
    PE:Debug("probe", "and the one after")
    eq(#store.lines, cap, "the list grew past the cap")
    eq(PE:DebugCount(), cap)
    eq(store.next, 3)
    check(store.lines[1]:find("probe: replaces the oldest", 1, true), "slot 1 holds: " .. store.lines[1])
    check(store.lines[2]:find("probe: and the one after", 1, true), "slot 2 holds: " .. store.lines[2])
    eq(store.lines[store.next], "old 3", "the oldest line is not at next")
    eq(store.lines[cap - 2], "old " .. (cap - 2))
end)

-- Core.lua InitDB: a damaged saved log is put right instead of being trusted.
test("debug: a damaged saved log is repaired at load", function()
    local db = saved()
    db.debug = { on = "yes", lines = { "a", "b", "c" }, next = 9 }   -- next points past the lines; on is not true
    local c, PE = T.new({ saved = db })
    eq(PE.debugOn, false)
    eq(debugOf(c), { on = false, lines = { "a", "b", "c" }, next = 4 })
    local db2 = saved()
    db2.debug = "junk"
    local c2 = T.new({ saved = db2 })
    eq(debugOf(c2), { on = false, lines = {}, next = 1 })
end)

-- Spec "Size": "Switching the log off keeps the lines; only Clear log removes them."
test("debug: switching off keeps the lines, ClearDebug empties the log", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    PE:Debug("probe", "kept")
    PE:SetDebug(false)
    eq(PE.debugOn, false)
    eq(#debugLines(c, "probe: kept"), 1)
    eq(#debugLines(c, "core: debug log switched off"), 1)
    local held = PE:DebugCount()
    PE:Debug("probe", "not stored")
    eq(PE:DebugCount(), held)
    PE:ClearDebug()
    eq(PE:DebugCount(), 0)
    eq(debugOf(c), { on = false, lines = {}, next = 1 })
    -- clearing while on keeps the switch on and starts again at slot 1
    PE:SetDebug(true)
    PE:ClearDebug()
    eq(debugOf(c), { on = true, lines = {}, next = 1 })
    PE:Debug("probe", "after the clear")
    eq(#debugOf(c).lines, 1)
end)

-- Spec "What it does": "/pe debug on and /pe debug off do the same from chat".
test("debug: /pe debug on and /pe debug off switch the log and say so", function()
    local c, PE = T.new({})
    local slash = c.env.SlashCmdList.POCKETESSENTIALS
    slash("debug on")
    eq(PE.debugOn, true)
    eq(debugOf(c).on, true)
    eq(#debugLines(c, "---- debug log switched on ----"), 1)
    eq(linesWith(c, "Debug log on."), 1)
    slash("  DEBUG ON ")                                  -- already on: no second header
    eq(#debugLines(c, "---- debug log switched on ----"), 1)
    slash("debug off")
    eq(PE.debugOn, false)
    eq(debugOf(c).on, false)
    eq(linesWith(c, "Debug log off."), 1)
    check(not settingsShown(c), "/pe debug opened the settings window")
    c:assertClean("/pe debug")
end)

-- Spec "What it does": "It stays as it was left across logins"; "Each session starts with a
-- header: addon version, game build, which features are on, Gamepad UI on or off, screen size".
test("debug: a saved on survives a reload, and the new session starts with a header line", function()
    local db = saved({ sellJunk = true })
    db.debug = { on = true, lines = { "12:00:00.000 probe: from the last session" }, next = 2 }
    local c, PE = T.new({ saved = db })
    eq(PE.debugOn, true)
    local store = debugOf(c)
    eq(store.lines[1], "12:00:00.000 probe: from the last session", "the earlier line was lost")
    local headers = debugLines(c, "---- session ----")
    eq(#headers, 1)
    local header = headers[1]
    check(header:find(LINE .. "core: "), "the header has no time and key: " .. header)
    for _, part in ipairs({ "addon=0.0.0-test", "game=1.16.0 (60000)", "gamepadUI=", "screen=", "features=sellJunk" }) do
        check(header:find(part, 1, true), "the header has no " .. part .. ": " .. header)
    end
    eq(#debugLines(c, "sellJunk: feature on"), 1)
    eq(listeners(c, "PLAYER_REGEN_DISABLED"), 1, "the start of a fight is not listened for")
    -- and a saved off stays off
    local db2 = saved()
    db2.debug = { on = false, lines = { "12:00:00.000 probe: old" }, next = 2 }
    local c2, PE2 = T.new({ saved = db2 })
    eq(PE2.debugOn, false)
    eq(debugOf(c2).lines, { "12:00:00.000 probe: old" })
end)

-- Spec table, Core: "every error and every blocked action (the same text as the Errors page)".
test("debug: a caught error and a blocked action each produce a line", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    twoProbes(PE)
    c:fire("ZONE_CHANGED")
    local errs = debugLines(c, "probe: ERROR boom")
    eq(#errs, 1)
    check(errs[1]:find(LINE .. "probe: ERROR boom$"), "unexpected line: " .. errs[1])
    c:fire("ADDON_ACTION_FORBIDDEN", "PocketEssentials", "UseContainerItem")
    local entry = errorsOf(PE, "blocked")[1]
    check(entry, "the block was not recorded")
    local blocks = debugLines(c, "UseContainerItem")
    eq(#blocks, 1)
    check(blocks[1]:find(("blocked: ERROR " .. entry.msg):sub(1, 60), 1, true),
        "the line does not carry the Errors page text: " .. blocks[1])
    c:fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "CastSpellByName")
    eq(#debugLines(c, "CastSpellByName"), 0, "another addon's block was written")
end)

-- Spec rules: "A value the game hides is written as <secret>; it is never read."
-- The stand-in's issecretvalue is true for values listed in c.world.secrets.
test("debug: PE.Plain writes a hidden value as <secret>, and a hidden line text is not stored", function()
    local c, PE = T.new({})
    local hidden = "a hidden value"
    c.world.secrets[hidden] = true
    eq(PE.Plain(hidden), "<secret>")
    eq(PE.Plain("plain"), "plain")
    eq(PE.Plain(42), "42")
    eq(PE.Plain(nil), "nil")
    eq(PE.Plain(false), "false")
    PE:SetDebug(true)
    PE:Debug("probe", "cost " .. PE.Plain(hidden))
    PE:Debug("probe", hidden)
    eq(#debugLines(c, "probe: cost <secret>"), 1)
    eq(#debugLines(c, "probe: <secret>"), 1)
    eq(#debugLines(c, hidden), 0, "the hidden value was stored")
end)

-- Spec table, Core: "feature switched on / off / failed to start".
test("debug: switching a feature on or off, and a failed start, each write a line", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    PE:SetModuleEnabled("sellJunk", true)
    PE:SetModuleEnabled("sellJunk", false)
    PE:RegisterModule({ key = "probe", label = "Probe feature", order = 5, OnEnable = function() error("probe broke", 0) end })
    PE:SetModuleEnabled("probe", true)
    local got = {}
    for _, line in ipairs(debugOf(c).lines) do
        local text = line:match(LINE .. "(.+)$")
        if text and (text:find("^sellJunk: feature") or text:find("^probe: ")) then got[#got + 1] = text end
    end
    eq(got, { "sellJunk: feature on", "sellJunk: feature off", "probe: ERROR probe broke", "probe: feature failed to start" })
end)

-- Spec table, Core: "fight started / ended; work held back for after a fight and when it ran".
-- Spec 7: seconds and milliseconds come from one clock, so stamps never go backwards even
-- when the wall clock and the game timer have unaligned fractions (a real log read
-- 16:02:45.760 then 16:02:45.686).
local function stampMs(line)
    local h, m, s, ms = line:match("^(%d%d):(%d%d):(%d%d)%.(%d%d%d) ")
    return ((tonumber(h) * 60 + tonumber(m)) * 60 + tonumber(s)) * 1000 + tonumber(ms)
end

test("debug: stamps do not go backwards across second boundaries when the clocks are offset", function()
    local c, PE = T.new({})
    c.wallOffset = -0.3
    c.now = 1000.55
    PE:SetDebug(true)
    for _ = 1, 40 do
        PE:Debug("probe", "tick")
        c:advance(0.1)
    end
    local lines = debugOf(c).lines
    check(#lines >= 41, "lines missing: " .. #lines)
    for i = 2, #lines do
        check(stampMs(lines[i]) >= stampMs(lines[i - 1]),
            "stamp went back: " .. lines[i - 1] .. " then " .. lines[i])
    end
    check(stampMs(lines[#lines]) - stampMs(lines[1]) > 3500, "the stamps did not move with the timer")
end)

test("debug: a time() that returns nothing does not stop the log or raise errors", function()
    local c, PE = T.new({})
    rawset(c.env, "time", function() return nil end)
    PE:SetDebug(true)
    PE:Debug("probe", "one")
    PE:Debug("probe", "two")
    local lines = debugLines(c, "probe: ")
    eq(#lines, 2)
    for _, l in ipairs(lines) do check(l:find(LINE), "bad line format: " .. l) end
    eq(c:problems(), {})
end)

test("debug: a date() that raises when given a time does not stop the log or raise errors", function()
    local c, PE = T.new({})
    local realDate = c.env.date
    rawset(c.env, "date", function(fmt, t)
        if t ~= nil then error("date: no second argument here") end
        return realDate(fmt)
    end)
    PE:SetDebug(true)
    PE:Debug("probe", "one")
    PE:Debug("probe", "two")
    local lines = debugLines(c, "probe: ")
    eq(#lines, 2)
    for _, l in ipairs(lines) do check(l:find(LINE), "bad line format: " .. l) end
    eq(c:problems(), {})
end)

test("debug: the fight legend is written with the first restriction line of a session only", function()
    local db = saved()
    db.debug = { on = true, lines = {}, next = 1 }
    local c, PE = T.new({ saved = db })
    c:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
    c:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 2)
    local got = debugLines(c, "addon restriction")
    eq(#got, 2)
    check(got[1]:find("(kinds: 0 combat", 1, true), "first line has no legend: " .. got[1])
    check(not got[2]:find("kinds", 1, true), "second line repeats the legend: " .. got[2])
    check(got[2]:find("addon restriction 0 is now 2", 1, true), "second line text: " .. got[2])
    -- switching the log off and on starts a new session
    PE:SetDebug(false)
    PE:SetDebug(true)
    c:fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
    got = debugLines(c, "addon restriction")
    check(got[3]:find("(kinds: 0 combat", 1, true), "no legend after switching on again: " .. got[3])
    -- a reload is a new session
    local db2 = rawget(c.env, "PocketEssentialsDB")
    local c2 = T.new({ saved = db2 })
    c2:fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
    got = debugLines(c2, "addon restriction 1 is now 1")
    check(got[1]:find("(kinds: 0 combat", 1, true), "no legend in a new session: " .. tostring(got[1]))
end)

-- CLAUDE.md "Nothing ticks while its feature is off": the start of a fight is only listened
-- for while the log is on (Core.lua DebugWatchFights).
test("debug: fights are written only while on, and PLAYER_REGEN_DISABLED is not listened for while off", function()
    local c, PE = T.new({})
    eq(listeners(c, "PLAYER_REGEN_DISABLED"), 0, "listening for the start of a fight with the log off")
    c:enterCombat()
    c:leaveCombat()
    eq(PE:DebugCount(), 0)
    PE:SetDebug(true)
    eq(listeners(c, "PLAYER_REGEN_DISABLED"), 1, "not listening for the start of a fight with the log on")
    c:enterCombat()
    PE:RunOutOfCombat("probe:job", function() end)
    c:leaveCombat()
    local got = {}
    for _, line in ipairs(debugOf(c).lines) do
        local text = line:match(LINE .. "core: (.+)$")
        if text and not text:find("^%-%-%-%-") then got[#got + 1] = text end
    end
    eq(got, { "fight started", "held for after the fight: probe:job", "fight ended", "fight over, running: probe:job" })
    PE:SetDebug(false)
    eq(listeners(c, "PLAYER_REGEN_DISABLED"), 0, "still listening for the start of a fight after switching off")
    local held = PE:DebugCount()
    c:enterCombat()
    c:leaveCombat()
    eq(PE:DebugCount(), held, "a fight was written with the log off")
    c:assertClean("fights")
end)

---------------------------------------------------------------------------
-- The debug log on Settings > Errors
---------------------------------------------------------------------------

local function errorsPage(c, PE)
    PE:OpenSettings("errors")
    c:advance(0.1)
    return rawget(c.env, "PocketEssentialsSettingsPanel")
end

-- The visible buttons under `top`, by label, and every visible text.
local function pageOf(c, top)
    local buttons, texts = {}, {}
    local function walk(w)
        local st = c._state(w)
        if st.type == "Button" and w:IsVisible() then buttons[T.labelOf(w)] = w end
        for _, r in ipairs(st.regions) do
            local rs = c._state(r)
            if rs.type == "FontString" and rs.text and rs.text ~= "" and r:IsVisible() then texts[#texts + 1] = rs.text end
        end
        for _, child in ipairs(st.children) do walk(child) end
        if st.scrollChild then walk(st.scrollChild) end
    end
    walk(top)
    return buttons, texts
end

local function hasText(texts, text)
    for _, t in ipairs(texts) do
        if t:find(text, 1, true) then return true end
    end
    return false
end

-- Spec "What it does": "A Debug log switch on Settings > Errors, off by default"; "Next to the
-- switch: how many lines are held, a Save log now button ... and a Clear log button".
test("debug: the Errors tab has the switch (off), the line count, Save and Empty", function()
    local c, PE = T.new({})
    local panel = errorsPage(c, PE)
    local buttons, texts = pageOf(c, panel)
    check(buttons["Off"], "no Off switch on the Errors page")
    check(buttons["Save"], "no Save button")
    check(buttons["Empty"], "no Empty button")
    check(hasText(texts, "Debug log"), "no Debug log title")
    check(hasText(texts, "0 of 10,000 lines"), "no line count")
    check(hasText(texts, "SavedVariables/PocketEssentials.lua"), "the page does not name the file to send")
    check(hasText(texts, "No errors recorded."), "the error list is gone")
    check(hasText(texts, "Save the log (reloads)") and hasText(texts, "Empty the log"), "the debug rows are missing")
    c:click(buttons["Off"])
    c:advance(0.1)
    eq(PE.debugOn, true)
    eq(debugOf(c).on, true)
    buttons, texts = pageOf(c, panel)
    check(buttons["On"] and not buttons["Off"], "the switch does not read On after the tap")
    check(hasText(texts, "1 of 10,000 lines"), "the count was not redrawn after the switch")
    c:click(buttons["On"])
    c:advance(0.1)
    eq(PE.debugOn, false)
    check(pageOf(c, panel)["Off"], "the switch does not read Off after the second tap")
    c:assertClean("debug switch")
end)

-- Spec: "a Save log now button (a reload, straight from the tap ...)" and "only Clear log removes them".
test("debug: Save reloads once; Empty empties the log and the count, and leaves the errors", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    PE:Debug("probe", "one")
    PE:LogError("bags", "a recorded problem")
    local panel = errorsPage(c, PE)
    local buttons, texts = pageOf(c, panel)
    check(hasText(texts, "3 of 10,000 lines"), "the count is not the number of lines held")
    local before = #c:callsTo("C_UI.Reload")
    c:click(buttons["Save"])
    eq(#c:callsTo("C_UI.Reload") - before, 1, "reloads from one tap")
    c:click(buttons["Empty"])
    c:advance(0.1)
    eq(PE:DebugCount(), 0)
    eq(PE.debugOn, true, "Clear log switched the log off")
    eq(#PE.errors, 1, "Clear log removed the errors")
    buttons, texts = pageOf(c, panel)
    check(hasText(texts, "0 of 10,000 lines"), "the count was not redrawn after Clear log")
    check(hasText(texts, "a recorded problem"), "the error is no longer shown")
end)

-- Settings.lua DebugCard: the count is read when the page is drawn, never per logged line.
test("debug: a logged line does not redraw the settings window; the count is fresh when the page is opened again", function()
    local c, PE = T.new({})
    PE:SetDebug(true)
    local panel = errorsPage(c, PE)
    check(hasText(select(2, pageOf(c, panel)), "1 of 10,000 lines"), "unexpected count at first")
    local asked = 0
    local refresh = PE.RefreshSettings
    PE.RefreshSettings = function(...) asked = asked + 1 return refresh(...) end
    for i = 1, 20 do PE:Debug("probe", "line " .. i) end
    c:advance(1)
    eq(asked, 0, "PE:Debug asked for a redraw")
    check(hasText(select(2, pageOf(c, panel)), "1 of 10,000 lines"), "the page was redrawn for a logged line")
    PE:CloseSettings()
    panel = errorsPage(c, PE)
    check(hasText(select(2, pageOf(c, panel)), "21 of 10,000 lines"), "the count is stale after reopening the page")
end)

return { known = KNOWN_FAILURES }
