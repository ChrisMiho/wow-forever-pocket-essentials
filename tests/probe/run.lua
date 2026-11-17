-- Tests for the restriction probe (probe/PocketProbe), a separate test addon.
--
--   luajit tests/probe/run.lua <repo root>
--
-- Loads the probe from its TOC into the stand-in client (tests/lib/fakeclient.lua)
-- and checks its rules: when passes run, what gets recorded and under which
-- situation key, how blocks are noticed, the clean series across reloads, the
-- vendor trials, and that nothing read from the game ends up in the saved table.
--
-- The stand-in only knows the game names Pocket Essentials uses, so the names
-- only the probe uses are added here (install, below), each as the source
-- describes it. Passing here means "passes offline": the probe's own logic
-- holds, not that the game answers the same way.
--
-- Prints "Probe: N tests" on pass; exit 1 and FAIL: lines otherwise.

local root = arg[1]
if not root then
    io.stderr:write("usage: luajit tests/probe/run.lua <repo root>\n")
    os.exit(2)
end

local Client = dofile(root .. "/tests/lib/fakeclient.lua")
local ADDON_DIR = root .. "/probe/PocketProbe"

local PLAYER = "Zugzug"
local WHISPERER = "Whisperer"
-- Text that exists only in the stand-in's world: none of it may be saved.
local WORLD_TEXT = { PLAYER, WHISPERER, "Broken Fang", "Wolf Pelt", "Good Sword", "Kill Ten Rats", "Rats slain",
    "Elwynn", "psst hello" }

local KEY_AUTO = "gp=on fight=no rest=------ where=world trig=auto"
local KEY_FIGHT = "gp=on fight=yes rest=c----- where=world trig=auto"
local KEY_PRESS = "gp=on fight=no rest=------ where=world trig=press"
local KEY_CLEAN = "gp=on fight=no rest=------ where=world trig=clean"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local clients = {}

local function check(cond, msg)
    if not cond then error(msg or "check failed", 2) end
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- The game names only the probe uses, added to one stand-in client.
local function install(c)
    local env, world = c.env, c.world

    -- Enum.AddOnRestrictionType: RestrictedActionsConstantsDocumentation.lua
    local kinds = env.Enum.AddOnRestrictionType
    rawset(kinds, "Encounter", 1); rawset(kinds, "ChallengeMode", 2); rawset(kinds, "PvPMatch", 3)
    rawset(kinds, "Map", 4); rawset(kinds, "Chat", 5)
    world.restrictions = {}
    rawset(env.C_RestrictedActions, "IsAddOnRestrictionActive", function(kind)
        if kind == 0 then return (world.combatRestricted or world.inCombat) and true or false end
        return world.restrictions[kind] and true or false
    end)

    rawset(env, "UnitName", function(unit)                      -- UnitDocumentation.lua:2489
        if unit == "player" then return PLAYER, nil end
        return nil
    end)
    rawset(env, "canaccessvalue", function(v) return not (v ~= nil and world.secrets[v] == true) end)

    -- Bags: Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:2153, 2235, 2282
    rawset(env, "IsAnyBagOpen", function() return c.bagFrame:IsShown() end)
    rawset(env, "OpenAllBags", function() c:openBag() end)
    rawset(env, "CloseAllBags", function() c:closeBag() end)

    -- Bindings: in a fight the game refuses and says so with the event.
    local bind = env.SetOverrideBindingClick
    rawset(env, "SetOverrideBindingClick", function(...)
        if world.inCombat then
            c:fire("ADDON_ACTION_BLOCKED", "PocketProbe", "SetOverrideBindingClick()")
            return
        end
        return bind(...)
    end)
    local clear = env.ClearOverrideBindings
    rawset(env, "ClearOverrideBindings", function(...)
        if world.inCombat then return end
        return clear(...)
    end)
    rawset(env, "GetBindingAction", function(key)
        for _, rec in ipairs(c:frames()) do
            local b = rawget(rec, "bindings")
            if b and b[key] then return "CLICK " .. b[key] .. ":LeftButton" end
        end
        return ""
    end)

    -- Controller: FrameControlsManager.lua:834, 1012; Blizzard_GamepadSmartNavigation/Utility.lua:46, 54
    rawset(env, "GamepadMode", { FrameControlsManager = { GetActiveFrame = function() return world.focusFrame end } })
    rawset(env, "SmartNavigation_MarkFrameIgnored", function(frame) rawset(frame, "smartNavigationIgnored", true) end)
    rawset(env, "SmartNavigation_ClearIgnoreStatus", function(frame) rawset(frame, "smartNavigationIgnored", nil) end)

    -- Vendor: MerchantFrameDocumentation.lua:53, 77, 86
    local function junk()
        local n = 0
        for _, bag in pairs(world.bags) do
            for _, it in pairs(bag) do
                if type(it) == "table" and it.quality == 0 and (it.price or 0) > 0 then n = n + 1 end
            end
        end
        return n
    end
    rawset(env, "C_MerchantFrame", {
        GetNumJunkItems = function() return junk() end,
        IsSellAllJunkEnabled = function() return world.sellAllJunk ~= false end,
        SellAllJunkItems = function()
            c.sellAllCalls = (c.sellAllCalls or 0) + 1
            if not world.merchant.open then return end
            for _, bag in pairs(world.bags) do
                for slot, it in pairs(bag) do
                    if type(it) == "table" and it.quality == 0 and (it.price or 0) > 0 then bag[slot] = nil end
                end
            end
        end,
    })

    -- Widget methods: SetParent (SimpleScriptRegionAPIDocumentation.lua:653), GetName, edit box focus.
    local function SetParent(self, parent)
        local st = c._state(self)
        if st.parent then
            local list = c._state(st.parent).children
            for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
        end
        st.parent = parent
        if parent then
            local list = c._state(parent).children
            list[#list + 1] = self
        end
    end
    local function GetName(self) return c._state(self).name end
    for _, kind in ipairs({ "Frame", "Button", "EditBox", "ScrollingMessageFrame" }) do
        c.typeMethods[kind].SetParent = SetParent
        c.typeMethods[kind].GetName = GetName
    end
    local focused
    c.typeMethods.EditBox.SetFocus = function(self) focused = self end
    c.typeMethods.EditBox.ClearFocus = function(self) if focused == self then focused = nil end end
    c.typeMethods.EditBox.HasFocus = function(self) return focused == self end

    -- Chat: ChatFrameEditBox.lua:14, ChatFrameUtil.lua:564
    rawset(c.editBox, "GetChatType", function() return c.chatBox.chatType end)
    env.ChatFrameUtil.DeactivateChat = function() c.closeChat() end

    -- A small world with names in it.
    world.bags[0][1] = { itemID = 101, quality = 0, price = 50, count = 1, name = "Broken Fang" }
    world.bags[0][2] = { itemID = 102, quality = 0, price = 5, count = 1, name = "Wolf Pelt" }
    world.bags[0][3] = { itemID = 103, quality = 1, price = 500, count = 1, name = "Good Sword" }
    world.money = 10000
    world.player = { map = 1429, x = 0.4, y = 0.6, facing = 1.5 }
    world.maps[1429] = { name = "Elwynn Forest", width = 3000, height = 2000 }
    world.questLog.quests = {
        { header = true, title = "Elwynn Forest" },
        { id = 7, title = "Kill Ten Rats", objectives = { { text = "Rats slain: 3/10", numFulfilled = 3, numRequired = 10 } } },
    }
end

-- A fresh client with the probe loaded. opts.saved: the saved table (a
-- reload is a new client with the same table). opts.setup(c) runs after the
-- names above are installed and before the probe loads.
local function new(opts)
    opts = opts or {}
    local gamepad = opts.gamepadUI
    if gamepad == nil then gamepad = true end
    local c = Client.new({ root = root, addonDir = ADDON_DIR, addonName = "PocketProbe", saved = opts.saved, gamepadUI = gamepad })
    clients[#clients + 1] = c
    install(c)
    if opts.setup then opts.setup(c) end
    local P = c:loadAddon()
    return c, P, c.env.PocketProbeDB
end

local function noErrors(c, where)
    if #c.errors > 0 then
        local e = c.errors[1]
        error((where or "client") .. ": Lua error in " .. e.where .. ": " .. e.msg, 2)
    end
    for _, line in ipairs(c.env.PocketProbeDB.log) do
        if line:find("error in the probe", 1, true) then error((where or "client") .. ": " .. line, 2) end
    end
end

local function button(c, name)
    local b = rawget(c.env, name)
    check(b, "no button named " .. name)
    return b
end

local function cell(db, id, key)
    local r = db.results[id]
    return r and r[key]
end

-- The newest detail entry of a trial (optionally in one situation).
local function detail(db, id, key)
    for i = #db.details, 1, -1 do
        local d = db.details[i]
        if d.trial == id and (not key or d.situation == key) then return d end
    end
end

local function countLog(db, text)
    local n = 0
    for _, line in ipairs(db.log) do if line:find(text, 1, true) then n = n + 1 end end
    return n
end

-- Everything in a table as one text (keys and values).
local function dump(v, out, seen)
    out, seen = out or {}, seen or {}
    if type(v) == "table" then
        if seen[v] then return out end
        seen[v] = true
        for k, x in pairs(v) do
            dump(k, out, seen)
            dump(x, out, seen)
        end
    else
        out[#out + 1] = tostring(v)
    end
    return out
end

-- Trials an ordinary pass must give a result for.
local function passTrials(db)
    local out = {}
    for _, t in ipairs(db.trials) do
        if t.area ~= "Vendor" and t.id ~= "val.whisper" then out[#out + 1] = t end
    end
    return out
end

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------

test("saved table has the fixed shape", function()
    local c, P, db = new()
    eq(db.version, 1)
    eq(db.game, "1.16.0 (60000)")
    eq(db.probe, "0.1.0")
    eq(db.options.vendor, true)
    eq(db.clean.index, 0); eq(db.clean.running, false)
    check(#db.trials >= 30, "trial list too short")
    local seen = {}
    for _, t in ipairs(db.trials) do
        check(type(t.id) == "string" and type(t.area) == "string" and type(t.label) == "string", "trial entry fields")
        check(t.kind == "action" or t.kind == "value", "trial kind " .. tostring(t.kind))
        check(not seen[t.id], "trial id twice: " .. t.id)
        seen[t.id] = true
    end
    for _, key in ipairs({ "situations", "results", "details", "log" }) do eq(type(db[key]), "table", key) end
    noErrors(c)
end)

test("an automatic pass after login records every trial under trig=auto", function()
    local c, P, db = new()
    c:advance(2.5)
    eq(next(db.results), nil, "nothing runs in the first seconds")
    c:advance(25)
    noErrors(c)
    for _, t in ipairs(passTrials(db)) do
        check(cell(db, t.id, KEY_AUTO), "no result for " .. t.id)
    end
    local s = db.situations[KEY_AUTO]
    check(s, "situation missing")
    eq(s.gamepad, true); eq(s.lockdown, false); eq(s.where, "world"); eq(s.trigger, "auto"); eq(s.passes, 1)
    for _, r in ipairs({ "combat", "encounter", "challenge", "pvp", "map", "chat" }) do eq(s.restrictions[r], false, r) end
    check(s.first:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"), "first is a date and time")
    for _, id in ipairs({ "chat.open", "chat.openframe", "chat.focus", "chat.type", "chat.close", "own.show", "own.escape",
        "own.create", "win.map.create", "win.map.attach", "win.bag.create", "win.chat.create", "bag.toggle", "bag.move",
        "bag.scale", "pad.bind", "pad.mark", "bags.sort", "cvar.write", "layout.set" }) do
        eq(cell(db, id, KEY_AUTO), "allowed", id)
    end
    for _, id in ipairs({ "layout.read", "val.position", "val.facing", "val.map", "val.questlog", "val.objectives",
        "val.bagitem", "val.money", "val.repaircost", "val.name.player" }) do
        eq(cell(db, id, KEY_AUTO), "readable", id)
    end
    eq(cell(db, "val.name.target", KEY_AUTO), "nil")
    check(P.status:find("pass done", 1, true), "status: " .. tostring(P.status))
    check(db.log[1]:match("^%d%d:%d%d:%d%d "), "log lines start with the time")
    -- Everything is put back.
    check(not c.editBox:IsShown(), "chat box left open")
    check(not c.bagFrame:IsShown(), "bag left open")
    eq(c.chatBox.chatType, "SAY")
    eq(c.world.cvars.combinedBags, "0")
    for _, rec in ipairs(c:frames()) do check(not rawget(rec, "bindings"), "a key is still taken") end
    -- No vendor trial without a vendor.
    eq(#c:callsTo("C_Container.UseContainerItem"), 0)
    check(not db.results["vendor.sell1"], "vendor trial ran without a vendor")
end)

test("Gamepad UI off and a dungeon give their own keys", function()
    local c, P, db = new({ gamepadUI = false, setup = function(cl) cl.world.instance = true end })
    c:advance(25)
    noErrors(c)
    local key = "gp=off fight=no rest=------ where=party trig=auto"
    check(db.situations[key], "situation key")
    eq(db.situations[key].where, "party")
    eq(db.situations[key].gamepad, false)
end)

test("a fight gets its own situation, one second after it starts", function()
    local c, P, db = new()
    c:advance(25)
    c:enterCombat()
    c:advance(0.8)
    check(not db.situations[KEY_FIGHT], "the fight pass started too early")
    c:advance(25)
    noErrors(c)
    local s = db.situations[KEY_FIGHT]
    check(s, "no fight situation")
    eq(s.lockdown, true); eq(s.restrictions.combat, true); eq(s.passes, 1)
    eq(cell(db, "chat.open", KEY_FIGHT), "allowed")
    -- The game refuses the key in a fight and names the function.
    eq(cell(db, "pad.bind", KEY_FIGHT), "blocked")
    local d = detail(db, "pad.bind", KEY_FIGHT)
    eq(d.func, "SetOverrideBindingClick()")
    check(d.stack and d.stack:find("Trials.lua", 1, true), "stack names our trial line")
    -- One button per Blizzard window per session: made in the first pass, reused here.
    check(not cell(db, "win.map.create", KEY_FIGHT), "a second button was made under the world map")
    eq(cell(db, "win.map.attach", KEY_FIGHT), "allowed")
end)

test("a pass in a situation already covered this session is skipped", function()
    local c, P, db = new()
    c:advance(25)
    c:enterCombat(); c:advance(25)
    c:leaveCombat(); c:advance(25)
    c:enterCombat(); c:advance(25)
    c:fire("PLAYER_ENTERING_WORLD", false, false); c:advance(25)
    noErrors(c)
    eq(db.situations[KEY_AUTO].passes, 1)
    eq(db.situations[KEY_FIGHT].passes, 1)
    eq(countLog(db, "pass started"), 2)
end)

test("a fight starting mid-pass stops it; the pass runs again afterwards", function()
    local c, P, db = new()
    c:advance(4.5)
    check(cell(db, "chat.open", KEY_AUTO), "the pass had begun")
    c:enterCombat()
    c:advance(30)
    noErrors(c)
    eq(db.situations[KEY_AUTO].passes, 0, "the stopped pass does not count")
    check(not cell(db, "val.money", KEY_AUTO), "the stopped pass went on")
    eq(db.situations[KEY_FIGHT].passes, 1)
    check(countLog(db, "the situation changed") >= 1, "log says why")
    c:leaveCombat()
    c:advance(30)
    eq(db.situations[KEY_AUTO].passes, 1)
    check(cell(db, "val.money", KEY_AUTO), "the pass was run again")
end)

test("a press pass starts inside the tap and each tap starts with the next trial", function()
    local c, P, db = new({ setup = function(cl)
        -- The chat box refuses to open and the game prints its line (no event).
        cl.env.ChatFrameUtil.OpenChat = function() cl.env.DisplayInterfaceActionBlockedMessage() end
    end })
    c:advance(25)
    eq(cell(db, "chat.open", KEY_AUTO), "blocked")
    c:click(button(c, "PocketProbeButton"))
    -- Before any timer: the first trial already has its result.
    eq(cell(db, "chat.open", KEY_PRESS), "blocked")
    eq(db.pressIndex, 1)
    local d = detail(db, "chat.open", KEY_PRESS)
    eq(d.inPress, true)
    eq(d.result, "blocked"); eq(d.func, nil)
    check(d.stack and d.stack:find("Trials.lua", 1, true), "stack")
    check(d.at:match("^%d%d%d%d%-"), "at")
    check(not cell(db, "own.show", KEY_PRESS), "the rest waits for the timers")
    c:advance(25)
    noErrors(c)
    for _, t in ipairs(passTrials(db)) do
        if not t.id:find("%.create$") or t.id == "own.create" then
            check(cell(db, t.id, KEY_PRESS), "no press result for " .. t.id)
        end
    end
    eq(db.situations[KEY_PRESS].trigger, "press")
    eq(detail(db, "chat.close", KEY_PRESS).inPress, false)
    eq(detail(db, "val.name.target", KEY_AUTO).inPress, nil)
    -- Press passes always run, and the next one starts with the next action trial.
    c:click(button(c, "PocketProbeButton"))
    eq(db.pressIndex, 2)
    eq(detail(db, "chat.openframe", KEY_PRESS).inPress, true)
    c:advance(25)
    eq(db.situations[KEY_PRESS].passes, 2)
    -- /probe is the same thing.
    c.env.SlashCmdList.POCKETPROBE("")
    eq(db.pressIndex, 3)
    check(countLog(db, "chat.focus: allowed (straight from the press)") == 1, "third press ran chat.focus directly")
    c.env.SlashCmdList.POCKETPROBE("stop")
    check(P.status:find("stopped", 1, true), "status after /probe stop")
    local before = countLog(db, ": ")
    c:advance(25)
    eq(countLog(db, ": "), before, "nothing runs after Stop")
    noErrors(c)
end)

test("a forbidden call and a blocked message are recorded with function and stack", function()
    local c, P, db = new({ setup = function(cl)
        rawset(cl.env.C_Container, "SortBags", function()
            cl:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "C_Container.SortBags()")
        end)
        -- Another addon's block during one of our trials is not ours.
        local set = cl.env.C_CVar.SetCVar
        rawset(cl.env.C_CVar, "SetCVar", function(...)
            cl:fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "SetCVar()")
            return set(...)
        end)
        cl.env.ChatFrameUtil.OpenChat = function() cl.env.DisplayInterfaceActionBlockedMessage() end
        -- A trial that raises.
        rawset(cl.env.C_EditMode, "SetActiveLayout", function() error("layout exploded") end)
        cl.world.focusFrame = cl.env.WorldMapFrame
    end })
    c:advance(25)
    noErrors(c)
    eq(cell(db, "bags.sort", KEY_AUTO), "forbidden")
    local d = detail(db, "bags.sort")
    eq(d.result, "forbidden"); eq(d.func, "C_Container.SortBags()"); eq(d.situation, KEY_AUTO)
    check(type(d.stack) == "string" and d.stack:find("Trials.lua", 1, true), "forbidden: stack")
    local lines = 0
    for _ in d.stack:gmatch("[^\n]+") do lines = lines + 1 end
    check(lines >= 1 and lines <= 14, "stack has " .. lines .. " lines")
    eq(d.focus, "WorldMapFrame")
    eq(cell(db, "cvar.write", KEY_AUTO), "allowed")
    -- The message hook: both chat trials that open the box, though the game's
    -- function swapped itself out after the first call.
    eq(cell(db, "chat.open", KEY_AUTO), "blocked")
    eq(cell(db, "chat.openframe", KEY_AUTO), "blocked")
    local b = detail(db, "chat.openframe")
    eq(b.func, nil)
    check(b.message:find("interface action failed", 1, true), "blocked: message")
    check(b.stack:find("Trials.lua", 1, true), "blocked: stack")
    eq(cell(db, "layout.set", KEY_AUTO), "error")
    check(detail(db, "layout.set").message:find("layout exploded", 1, true), "error message kept")
    -- One failing trial never stops the pass.
    eq(db.situations[KEY_AUTO].passes, 1)
    eq(cell(db, "val.money", KEY_AUTO), "readable")
end)

test("an action that does nothing is 'no effect'; Edit Mode open is left alone", function()
    local c, P, db = new({ setup = function(cl)
        cl.env.ChatFrameUtil.OpenChat = function() end
        cl.world.editMode = true
    end })
    c:advance(25)
    noErrors(c)
    eq(cell(db, "chat.open", KEY_AUTO), "no effect")
    eq(cell(db, "layout.set", KEY_AUTO), "no effect")
    eq(detail(db, "layout.set").message, "Edit Mode open")
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 0)
end)

test("a missing function is 'missing'", function()
    local c, P, db = new({ setup = function(cl)
        rawset(cl.env.C_Container, "SortBags", nil)
        rawset(cl.env, "SmartNavigation_MarkFrameIgnored", nil)
        rawset(cl.env, "UnitName", nil)
        cl.typeMethods.EditBox.SetFocus = nil
        rawset(cl.env, "WorldMapFrame", nil)
    end })
    c:advance(25)
    noErrors(c)
    eq(cell(db, "bags.sort", KEY_AUTO), "missing")
    check(detail(db, "bags.sort").message:find("C_Container.SortBags", 1, true), "message names it")
    eq(cell(db, "pad.mark", KEY_AUTO), "missing")
    eq(cell(db, "val.name.player", KEY_AUTO), "missing")
    eq(cell(db, "chat.focus", KEY_AUTO), "missing")
    eq(cell(db, "win.map.create", KEY_AUTO), "missing")
    eq(db.situations[KEY_AUTO].passes, 1)
end)

test("two different answers for one cell are both kept, across sessions", function()
    local saved = {}
    local c1, _, db = new({ saved = saved })
    c1:advance(25)
    eq(cell(db, "bags.sort", KEY_AUTO), "allowed")
    local forbid = function(cl)
        rawset(cl.env.C_Container, "SortBags", function()
            cl:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "C_Container.SortBags()")
        end)
    end
    local c2 = new({ saved = saved, setup = forbid })
    c2:advance(25)
    eq(cell(saved, "bags.sort", KEY_AUTO), "allowed / forbidden")
    eq(cell(saved, "own.show", KEY_AUTO), "allowed", "the same answer is not repeated")
    eq(saved.situations[KEY_AUTO].passes, 2)
    local c3 = new({ saved = saved, setup = forbid })
    c3:advance(25)
    eq(cell(saved, "bags.sort", KEY_AUTO), "allowed / forbidden")
    noErrors(c3)
end)

test("the clean series runs one trial per reload and ends", function()
    local saved = {}
    local c, P, db = new({ saved = saved })
    c:advance(25)
    local n = #P.cleanList
    check(n >= 10, "clean list")
    eq(P.cleanList[n].id, "vendor.sell1", "the vendor trial is last")
    c:click(button(c, "PocketProbeCleanButton"))
    eq(c.reloads, 1, "Clean trials reloads from the tap")
    eq(saved.clean.running, true); eq(saved.clean.index, 0)
    local started = countLog(saved, "pass started")

    for i = 1, n do
        c, P = new({ saved = saved })
        local trial = P.cleanList[i]
        local detailsBefore, resultsBefore = #saved.details, #dump(saved.results)
        c:advance(2.5)
        eq(#dump(saved.results), resultsBefore, "nothing before the clean trial")
        if trial.vendor then
            c:advance(2)
            check(P.status:find("open a vendor", 1, true), "status asks for a vendor: " .. tostring(P.status))
            eq(saved.clean.index, i - 1)
            c:openMerchant()
        end
        c:advance(3)
        noErrors(c, "clean trial " .. i)
        eq(saved.clean.index, i, "index after trial " .. i)
        check(cell(saved, trial.id, KEY_CLEAN), "no clean result for " .. trial.id)
        eq(countLog(saved, "pass started"), started, "no pass in a clean session")
        -- Only that one trial ran.
        local ran = 0
        for _, cells in pairs(saved.results) do
            if cells[KEY_CLEAN] then ran = ran + 1 end
        end
        eq(ran, i, "clean results so far")
        local nextButton = button(c, "PocketProbeNextButton")
        if i < n then
            -- A fight in a clean session starts no pass either.
            c:enterCombat(); c:advance(5); c:leaveCombat(); c:advance(5)
            eq(countLog(saved, "pass started"), started, "no pass while the series runs")
            eq(saved.clean.running, true)
            eq(P.status, "clean trial " .. i .. " of " .. n .. ": tap Next")
            check(nextButton:IsShown(), "Next is showing")
            c:click(nextButton)
            eq(c.reloads, 1, "Next reloads from the tap")
        else
            eq(saved.clean.running, false)
            eq(P.status, "clean trials done")
            check(not nextButton:IsShown(), "Next is hidden at the end")
        end
    end
    eq(saved.situations[KEY_CLEAN].trigger, "clean")
    eq(#c:callsTo("C_Container.UseContainerItem"), 1)
    -- The next login is an ordinary one again.
    c = new({ saved = saved })
    c:advance(25)
    eq(countLog(saved, "pass started"), started + 1)
end)

test("Stop ends the clean series; Next skips a trial waiting for a vendor", function()
    local saved = {}
    local c, P = new({ saved = saved })
    local n = #P.cleanList
    saved.clean.running, saved.clean.index = true, n - 1
    c, P = new({ saved = saved })
    c:advance(5)
    check(P.status:find("open a vendor", 1, true), "waiting for a vendor")
    c:click(button(c, "PocketProbeNextButton"))
    eq(saved.clean.index, n)
    eq(c.reloads, 1)
    c, P = new({ saved = saved })
    c:advance(5)
    eq(saved.clean.running, false)
    eq(P.status, "clean trials done")

    saved.clean.running, saved.clean.index = true, 2
    c, P = new({ saved = saved })
    c:click(button(c, "PocketProbeStopButton"))
    eq(saved.clean.running, false)
    c:advance(10)
    eq(saved.clean.index, 2, "no clean trial after Stop")
    noErrors(c)
end)

test("vendor trials run only with a vendor open and the switch on", function()
    local c, P, db = new({ setup = function(cl)
        cl.world.merchant.canRepair, cl.world.merchant.repairCost = true, 300
    end })
    c:advance(25)
    eq(#c:callsTo("C_Container.UseContainerItem"), 0)
    -- Switch off: a vendor changes nothing.
    local switch = button(c, "PocketProbeVendorButton")
    c:click(switch)
    eq(db.options.vendor, false)
    eq(switch.label:GetText(), "Vendor trials: off")
    c:openMerchant(); c:advance(10); c:closeMerchant()
    eq(#c:callsTo("C_Container.UseContainerItem"), 0)
    eq(c.sellAllCalls, nil)
    eq(#c:callsTo("RepairAllItems"), 0)
    check(not db.results["vendor.sell1"], "vendor trial ran with the switch off")
    -- Switch on.
    c:click(switch)
    eq(switch.label:GetText(), "Vendor trials: on")
    c:openMerchant()
    c:advance(0.5)
    local sold = c:callsTo("C_Container.UseContainerItem")
    eq(#sold, 1)
    eq(sold[1].args[1], 0); eq(sold[1].args[2], 2, "the cheapest grey item goes first")
    check(not cell(db, "vendor.sell1", KEY_AUTO), "the result waits a second")
    c:advance(10)
    noErrors(c)
    eq(cell(db, "vendor.sell1", KEY_AUTO), "allowed")
    eq(cell(db, "vendor.sellall", KEY_AUTO), "allowed")
    eq(cell(db, "vendor.repair", KEY_AUTO), "allowed")
    eq(c.sellAllCalls, 1)
    eq(#c:callsTo("RepairAllItems"), 1)
    eq(c:callsTo("RepairAllItems")[1].args[1], false, "never the guild's money")
    check(c.world.bags[0][3], "the white item is kept")
    eq(c.world.merchant.repairCost, 0)
    c:closeMerchant()
    -- A second visit in the same situation tries nothing again.
    c.world.bags[0][5] = { itemID = 105, quality = 0, price = 7, count = 1, name = "Wolf Pelt" }
    c:openMerchant(); c:advance(10)
    eq(#c:callsTo("C_Container.UseContainerItem"), 1)
    -- A press with the vendor open does.
    c:click(button(c, "PocketProbeButton")); c:advance(30)
    eq(#c:callsTo("C_Container.UseContainerItem"), 2)
    eq(cell(db, "vendor.sell1", KEY_PRESS), "allowed")
    noErrors(c)
end)

test("a refused sale is 'forbidden' or 'no effect'; nothing to sell tries nothing", function()
    local c, P, db = new({ setup = function(cl)
        cl.world.forbidUse = function() cl:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "UseContainerItem()") end
        cl.world.sellAllJunk = false
    end })
    c:advance(25)
    c:openMerchant(); c:advance(10)
    eq(cell(db, "vendor.sell1", KEY_AUTO), "forbidden")
    eq(detail(db, "vendor.sell1").func, "UseContainerItem()")
    check(not db.results["vendor.sellall"], "sell-all is off on this client: not called")
    eq(c.sellAllCalls, nil)
    check(not db.results["vendor.repair"], "nothing damaged: not called")
    eq(#c:callsTo("RepairAllItems"), 0)

    local c2, _, db2 = new({ setup = function(cl)
        cl.world.forbidUse = function() end            -- the call does nothing
    end })
    c2:advance(25); c2:openMerchant(); c2:advance(10)
    eq(cell(db2, "vendor.sell1", KEY_AUTO), "no effect")

    local c3, _, db3 = new({ setup = function(cl) cl.world.bags[0] = { [3] = cl.world.bags[0][3] } end })
    c3:advance(25); c3:openMerchant(); c3:advance(10)
    eq(#c3:callsTo("C_Container.UseContainerItem"), 0)
    check(not db3.results["vendor.sell1"], "no junk: no result")
    noErrors(c3)
end)

test("a whisper's payload is classed, once per situation, with no text kept", function()
    local c, P, db = new()
    c:advance(25)
    check(not db.results["val.whisper"], "no whisper yet")
    c:whisperIn(WHISPERER .. "-Camelot", "psst hello")
    eq(cell(db, "val.whisper", KEY_AUTO), "readable")
    local text = "psst hello again"
    c.world.secrets[text] = true
    c:whisperIn(WHISPERER .. "-Camelot", text)
    eq(cell(db, "val.whisper", KEY_AUTO), "readable", "one per situation per session")
    c:enterCombat()
    c:whisperIn(WHISPERER .. "-Camelot", text)
    c:advance(1)
    eq(cell(db, "val.whisper", KEY_FIGHT), "secret")
    check(detail(db, "val.whisper").message:find("1=secret 2=readable", 1, true), "classes by position")
    noErrors(c)
end)

test("secret values are classed 'secret' and never compared", function()
    local c, P, db = new({ setup = function(cl)
        cl.world.secrets[PLAYER] = true
        cl.world.money = 123456
        cl.world.secrets[123456] = true
        cl.world.cvars.combinedBags = "1"
        cl.world.secrets["1"] = true
    end })
    c:advance(25)
    noErrors(c)
    eq(cell(db, "val.name.player", KEY_AUTO), "secret")
    eq(detail(db, "val.name.player").message, "name=secret")
    eq(cell(db, "val.money", KEY_AUTO), "secret")
    eq(cell(db, "cvar.write", KEY_AUTO), "no effect")
    eq(#c:callsTo("C_CVar.SetCVar"), 0, "a secret is never passed to SetCVar")
end)

test("nothing from the game world is saved", function()
    local saved = {}
    local c, P, db = new({ saved = saved, setup = function(cl)
        cl.world.merchant.canRepair, cl.world.merchant.repairCost = true, 300
        cl.world.focusFrame = cl.env.WorldMapFrame
        rawset(cl.env.C_Container, "SortBags", function() error("could not sort for " .. "someone") end)
    end })
    c:advance(25)
    c:whisperIn(WHISPERER .. "-Camelot", "psst hello")
    c:click(button(c, "PocketProbeButton")); c:advance(25)
    c:enterCombat(); c:advance(25)
    c:whisperIn(WHISPERER .. "-Camelot", "psst hello")
    c:leaveCombat(); c:advance(5)
    c:openMerchant(); c:advance(10); c:closeMerchant()
    noErrors(c)
    check(#saved.details > 0 and #saved.log > 50, "something was recorded")
    local text = table.concat(dump(saved), "\n")
    for _, word in ipairs(WORLD_TEXT) do
        check(not text:find(word, 1, true), "the saved table contains \"" .. word .. "\"")
    end
    -- Values read (money, position, item ids) are not in it either.
    for _, v in ipairs(dump(saved.results)) do
        check(not tonumber(v), "a number in the results: " .. v)
    end
    for _, d in ipairs(saved.details) do
        for k in pairs(d) do
            check(({ trial = 1, situation = 1, result = 1, func = 1, message = 1, stack = 1, focus = 1, at = 1, inPress = 1 })[k],
                "unknown detail field " .. tostring(k))
        end
    end
end)

test("details stop at 400 and the log at 2000", function()
    local saved = { details = {}, log = {} }
    for i = 1, 400 do saved.details[i] = { trial = "old", situation = "old", result = "blocked", at = "old " .. i } end
    for i = 1, 2000 do saved.log[i] = "00:00:00 old " .. i end
    local c, P, db = new({ saved = saved })
    c:advance(25)
    c:click(button(c, "PocketProbeButton")); c:advance(25)
    noErrors(c)
    eq(#db.details, 400)
    eq(db.details[400].trial, "val.name.target", "newest last")
    check(db.details[1].at ~= "old 1", "oldest dropped")
    check(#db.log <= 2000, "log has " .. #db.log .. " lines")
    check(#db.log >= 1700, "the log drops its oldest lines in blocks, not everything")
    check(db.log[#db.log]:find("pass done", 1, true), "newest log line last")
end)

test("the probe's frames are made at load and nothing ticks", function()
    local c, P, db = new()
    local atLoad = #c:frames()
    for _, name in ipairs({ "PocketProbeButton", "PocketProbeCleanButton", "PocketProbeSaveButton",
        "PocketProbeVendorButton", "PocketProbeStopButton", "PocketProbeNextButton" }) do
        local b = button(c, name)
        local st = c._state(b)
        eq(st.strata, "HIGH", name .. " strata")
        eq(st.parent, c.UIParent, name .. " parent")
        check(b:GetHeight() >= 40, name .. " is big enough for a finger")
        check(not b:IsProtected(), name .. " is a plain frame")
    end
    check(not button(c, "PocketProbeNextButton"):IsShown(), "Next is hidden")
    c:advance(25)
    c:enterCombat(); c:advance(25)
    -- Only the trial buttons were added: three under Blizzard windows and one
    -- under our own window per pass.
    eq(#c:frames() - atLoad, 5)
    eq(c.stats.addonOnUpdate, 0, "no OnUpdate")
    for _, rec in ipairs(c:frames()) do check(not rec.scripts.OnUpdate, "a frame has an OnUpdate script") end
    local _, _, top = c._rect(button(c, "PocketProbeButton"))
    check(top > 700, "Probe sits at the top of the screen")
    c:click(button(c, "PocketProbeSaveButton"))
    eq(c.reloads, 1, "Save reloads from the tap")
    noErrors(c)
end)

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------

local failures = {}
for _, t in ipairs(tests) do
    local ok, err = xpcall(t.fn, debug.traceback)
    for i = #clients, 1, -1 do clients[i]:destroy() clients[i] = nil end
    if not ok then failures[#failures + 1] = t.name .. ": " .. tostring(err) end
end

if #failures > 0 then
    for _, f in ipairs(failures) do print("FAIL: " .. f) end
    os.exit(1)
end
print(string.format("Probe: %d tests", #tests))
