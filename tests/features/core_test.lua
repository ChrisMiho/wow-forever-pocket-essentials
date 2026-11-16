-- Rules for the core (Core.lua): saved settings, the feature registry, the
-- error log, the combat queue and /pe reset.
-- Sources: Core.lua's comments; docs/DECISIONS.md "General" ("Errors are logged
-- quietly ...", "/pe reset ..."); CLAUDE.md "Conventions" (features default off,
-- handlers go through PE:Safe or PE:Wrap); PRD.md goals 3 and 4.
-- Each test names its source in a comment. Fresh client and addon per test.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local FEATURES = { "questIcons", "questArrow", "bags", "sellJunk", "repair", "chat", "layout" }

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
    eq(#c.calls, 0, "the addon called game functions that change something at first install")
end)

-- Core.lua Login line 714: `PE.db.enabled[mod.key] == true`.
test("core: only a saved true switches a feature on", function()
    local c, PE = T.new({ saved = saved({ sellJunk = true, repair = "true", chat = 1, bags = false, layout = {} }) })
    check(PE:IsModuleEnabled("sellJunk"), "sellJunk saved as true is not on")
    check(not PE:IsModuleEnabled("repair"), "repair saved as the text \"true\" is on")
    check(not PE:IsModuleEnabled("chat"), "chat saved as 1 is on")
    check(not PE:IsModuleEnabled("bags"), "bags saved as false is on")
    check(not PE:IsModuleEnabled("layout"), "layout saved as a table is on")
    c:assertClean("login")
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
    eq(PE:GetModule("bags").opts.size, "normal", "a feature with no saved options gets its defaults")
    eq(PE.db.ui, { size = "medium", hubPos = "LEFT" })
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
    eq(PE.db.ui, { size = "large", hubPos = "RIGHT" })
    c.env.SlashCmdList.POCKETESSENTIALS("reset")
    eq(PE.db.ui, { size = "medium", hubPos = "LEFT" })
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

return { known = KNOWN_FAILURES }
