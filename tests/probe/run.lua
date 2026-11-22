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

    -- The game's error path (Blizzard_ScriptErrors.lua:71-101, Blizzard_ScriptErrorsFrame.lua:88-141):
    -- the handler set with seterrorhandler gets the message; Blizzard's works out the stack and
    -- passes message, type, stack and locals to the error box, which shows itself when the
    -- "scriptErrors" setting is on. The stand-in's script errors (c.onError) take this path.
    world.cvars.scriptErrors = "1"
    local box = { errorData = {}, shown = false }
    function box:IsShown() return self.shown end
    function box:Hide() if not self.stuck then self.shown = false end end
    function box:DisplayMessageInternal(message, messageType, stack, locals)
        self.errorData[#self.errorData + 1] = { message = message, messageType = messageType, stack = stack, locals = locals }
        if not self.shown and world.cvars.scriptErrors ~= "0" then self.shown = true end
    end
    c.errorBox = box
    rawset(env, "ScriptErrorsFrame", box)
    local function Blizzard(message)
        local text = tostring(message)
        local stack = c.nextStack
        c.nextStack = nil
        if not stack then
            stack = text:find("PocketProbe", 1, true) and "Interface/AddOns/PocketProbe/Errors.lua:150: in function <...>\n"
                or "[string \"/run x()\"]:1: in main chunk\n"
        end
        box:DisplayMessageInternal(message, 0, stack, "secret locals " .. text)
    end
    local handler = Blizzard
    rawset(env, "geterrorhandler", function() return handler end)
    rawset(env, "seterrorhandler", function(fn) handler = fn end)
    c.onError = function(e) handler(e) end
    -- Another addon's error, as the game would pass it on.
    c.otherError = function(_, source, text)
        c.nextStack = "Interface/AddOns/" .. source .. "/Main.lua:12: in function <Interface/AddOns/" .. source .. "/Main.lua:10>\n"
        handler(text)
    end

    -- Settings: CVarDocumentation.lua:66, 82; VideoDocumentation.lua:78, 105; ConsoleDocumentation.lua:59.
    for name, value in pairs({ graphicsOutlineMode = "2", raidGraphicsOutlineMode = "2", graphicsSpellDensity = "1",
        graphicsParticleDensity = "3", SoftTargetLowPriorityIcons = "0", SoftTargetInteract = "1" }) do
        world.cvars[name] = value
    end
    world.secureCVars = { scriptErrors = true }
    rawset(env.C_CVar, "GetCVarDefault", function(name) return world.cvars[name] and "0" or nil end)
    rawset(env.C_CVar, "GetCVarInfo", function(name)
        local v = world.cvars[name]
        if v == nil then return nil end
        return v, "0", false, false, false, world.secureCVars[name] and true or false, false
    end)
    rawset(env, "C_VideoOptions", {
        IsOutlineModeSupported = function() return world.outlineSupported ~= false end,
        IsSpellVisualDensitySystemSupported = function() return false end,
    })
    rawset(env, "ConsoleGetAllCommands", function()
        return { { command = "graphicsOutlineMode", help = "" }, { command = "outlineModeShowLootEffectWhenDisabled", help = "" },
            { command = "lootUnderMouse", help = "" }, { command = "maxFPS", help = "" }, { command = "spellClutter", help = "" } }
    end)

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

local function riskyOn() return { options = { risky = true } } end

-- The panel's buttons and the hidden d-pad button.
local function openPanel(c)
    c:click(rawget(c.env, "PocketProbeButton"))
    assert(rawget(c.env, "PocketProbePanel"):IsShown(), "the panel did not open")
end

-- Opens the panel on the tab that holds this trial and returns its row.
local function showTrial(c, P, id)
    if not rawget(c.env, "PocketProbePanel"):IsShown() then openPanel(c) end
    for _, t in ipairs(P.panelTabs) do
        if t:IsShown() then
            c:click(t)
            for _, r in ipairs(P.panelRows) do
                if r:IsShown() and r.ppEntry and r.ppEntry.id == id then return r end
            end
        end
    end
    error("no row on the panel for " .. id, 2)
end

-- A d-pad key, as the game sends it through the override binding: down, then up.
local function pad(c, key)
    local nav = rawget(c.env, "PocketProbeNavButton")
    c:script(nav, "OnClick", key, true)
    c:script(nav, "OnClick", key, false)
end

-- The place of a log line that starts (after the time) with this text.
local function logAt(db, text)
    for i, line in ipairs(db.log) do
        if line:sub(10, 9 + #text) == text then return i end
    end
end

-- A fresh client with the probe loaded. opts.saved: the saved table (a
-- reload is a new client with the same table). opts.setup(c) runs after the
-- names above are installed and before the probe loads.
-- The automatic passes (probe 0.2.0) start off in 0.3.0; most tests below are
-- about them, so their saved table has the Auto switch on unless it says
-- otherwise or opts.auto is false.
local function new(opts)
    opts = opts or {}
    local gamepad = opts.gamepadUI
    if gamepad == nil then gamepad = true end
    local saved = opts.saved
    if opts.auto ~= false then
        saved = saved or {}
        saved.options = saved.options or {}
        if saved.options.auto == nil then saved.options.auto = true end
    end
    local c = Client.new({ root = root, addonDir = ADDON_DIR, addonName = "PocketProbe", saved = saved, gamepadUI = gamepad })
    clients[#clients + 1] = c
    install(c)
    if opts.setup then opts.setup(c) end
    local P = c:loadAddon()
    return c, P, c.env.PocketProbeDB
end

local function noErrors(c, where)
    for _, e in ipairs(c.errors) do
        -- The probe's own test errors (area Errors) are meant.
        if not e.msg:find("PocketProbe test error", 1, true) then
            error((where or "client") .. ": Lua error in " .. e.where .. ": " .. e.msg, 2)
        end
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
        -- The Errors and Graphics areas only run from the panel.
        if not t.id:find("^vendor%.") and t.id ~= "val.whisper" and t.area ~= "Errors" and t.area ~= "Graphics" then
            out[#out + 1] = t
        end
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
    eq(db.probe, "0.4.0")
    eq(db.options.vendor, true)
    eq(db.options.risky, false)
    eq(type(db.spoiled), "table")
    eq(db.trials[1].id, "chat.open", "the saved list keeps the display order")
    eq(db.clean.index, 0); eq(db.clean.running, false)
    check(#db.trials >= 40, "trial list too short")
    local seen = {}
    for _, t in ipairs(db.trials) do
        check(type(t.id) == "string" and type(t.area) == "string" and type(t.label) == "string", "trial entry fields")
        check(t.kind == "action" or t.kind == "value" or t.kind == "info" or t.kind == "guided", "trial kind " .. tostring(t.kind))
        check(not seen[t.id], "trial id twice: " .. t.id)
        seen[t.id] = true
    end
    for _, id in ipairs({ "err.handler", "err.box", "err.hook", "err.others", "err.hide", "err.chain", "err.blocked",
        "gfx.read", "gfx.write", "gfx.names", "gfx.outlines", "gfx.icons" }) do
        check(seen[id], "new trial missing: " .. id)
    end
    for _, key in ipairs({ "situations", "results", "details", "log", "last", "guided" }) do eq(type(db[key]), "table", key) end
    noErrors(c)
end)

test("nothing runs by itself in 0.3.0: Auto starts off, the listeners still record", function()
    local c, P, db = new({ auto = false, setup = function(cl) cl:openBag(); cl:closeBag() end })
    eq(db.options.auto, false)
    c:advance(60)
    c:enterCombat(); c:advance(30); c:leaveCombat(); c:advance(30)
    c:openMerchant(); c:advance(10); c:closeMerchant()
    noErrors(c)
    eq(next(db.results), nil, "no trial ran")
    eq(countLog(db, "pass started"), 0)
    check(not rawget(c.env, "PocketProbePanel"):IsShown(), "the panel does not open by itself")
    -- The listeners: a whisper and a refusal in the probe's name are still recorded.
    c:whisperIn(WHISPERER .. "-Camelot", "psst hello")
    eq(cell(db, "val.whisper", KEY_AUTO), "readable")
    c:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "InteractUnit()")
    eq(cell(db, "after.InteractUnit", KEY_AUTO), "forbidden")
    -- Auto on: the passes of 0.2.0 run again.
    openPanel(c)
    c:click(button(c, "PocketProbeAutoButton"))
    eq(db.options.auto, true)
    eq(button(c, "PocketProbeAutoButton").ppLabel:GetText(), "Auto: On")
    c:advance(30)
    eq(db.situations[KEY_AUTO].passes, 1)
    eq(cell(db, "own.show", KEY_AUTO), "allowed")
    check(not db.results["err.hook"], "the Errors trials are never in an automatic pass")
    check(not db.results["gfx.write"], "the Graphics trials are never in an automatic pass")
    -- Auto off again stops the next automatic pass.
    c:click(button(c, "PocketProbeAutoButton"))
    c:enterCombat(); c:advance(30)
    check(not db.situations[KEY_FIGHT], "no fight pass with Auto off")
    noErrors(c)
end)

local RISKY = { "chat.open", "chat.openframe", "chat.focus", "chat.close", "bag.toggle", "layout.set",
    "bars.move", "bars.scale", "layout.save" }

test("with the risky switch off (the default) a pass leaves the risky trials out", function()
    local c, P, db = new()
    c:advance(25)
    noErrors(c)
    for _, id in ipairs(RISKY) do check(not db.results[id], id .. " ran with the switch off") end
    eq(#c:callsTo("ChatFrameUtil.OpenChat"), 0)
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 0)
    eq(cell(db, "own.show", KEY_AUTO), "allowed")
    eq(cell(db, "chat.type", KEY_AUTO), "allowed")
    eq(cell(db, "val.money", KEY_AUTO), "readable")
    eq(countLog(db, "risky trials off"), 1)
    eq(db.situations[KEY_AUTO].passes, 1)
    -- Switching them on makes the situation count as not covered yet.
    openPanel(c)
    local switch = button(c, "PocketProbeRiskyButton")
    eq(switch.ppLabel:GetText(), "Risky: Off")
    c:click(switch)
    eq(db.options.risky, true)
    eq(switch.ppLabel:GetText(), "Risky: On")
    c:click(button(c, "PocketProbeCloseButton"))
    c:enterCombat(); c:advance(0.5); c:leaveCombat(); c:advance(30)
    eq(cell(db, "chat.open", KEY_AUTO), "allowed")
    eq(db.situations[KEY_AUTO].passes, 2)
end)

test("risky trials run last: other actions, then values, then the risky ones", function()
    local c, P, db = new({ saved = riskyOn() })
    c:advance(30)
    noErrors(c)
    local lastSafe, firstValue, lastValue, firstRisky = 0, math.huge, 0, math.huge
    for _, t in ipairs(db.trials) do
        local at = logAt(db, t.id .. ": ")
        if at then
            local risky = false
            for _, id in ipairs(RISKY) do if id == t.id then risky = true end end
            if risky then firstRisky = math.min(firstRisky, at)
            elseif t.kind == "value" then firstValue, lastValue = math.min(firstValue, at), math.max(lastValue, at)
            else lastSafe = math.max(lastSafe, at) end
        end
    end
    check(lastSafe > 0 and lastSafe < firstValue, "safe actions come before the values")
    check(lastValue < firstRisky and firstRisky < math.huge, "risky trials come after the values")
    eq(countLog(db, "risky trials off"), 0)
end)

test("an automatic pass after login records every trial under trig=auto", function()
    -- The bag has been opened once before, so it has a position to move.
    local c, P, db = new({ saved = riskyOn(), setup = function(cl) cl:openBag(); cl:closeBag() end })
    c:advance(2.5)
    eq(next(db.results), nil, "nothing runs in the first seconds")
    c:advance(30)
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
        "bag.scale", "pad.bind", "pad.mark", "bags.sort", "cvar.write", "layout.set", "bars.move", "bars.scale",
        "layout.save" }) do
        eq(cell(db, id, KEY_AUTO), "allowed", id)
    end
    for _, id in ipairs({ "layout.read", "layout.sizes", "bars.protected", "bars.settings", "val.position", "val.facing", "val.map", "val.questlog", "val.objectives",
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
    eq(cell(db, "own.show", KEY_FIGHT), "allowed")
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
    check(cell(db, "own.show", KEY_AUTO), "the pass had begun")
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

test("Run all safe starts inside the tap; Run on a row runs that trial inside the tap", function()
    local c, P, db = new({ auto = false, setup = function(cl)
        -- Setting the chat type makes the game print its line (no event).
        rawset(cl.editBox, "SetChatType", function() cl.env.DisplayInterfaceActionBlockedMessage() end)
    end })
    c:advance(5)
    openPanel(c)
    c:click(button(c, "PocketProbeRunAllButton"))
    -- Before any timer: the first safe trial already has its result.
    local first = P.SafeList(false)[1]
    eq(first.id, "chat.type")
    eq(cell(db, "chat.type", KEY_PRESS), "blocked")
    local d = detail(db, "chat.type", KEY_PRESS)
    eq(d.inPress, true)
    eq(d.result, "blocked"); eq(d.func, nil)
    check(d.stack and d.stack:find("Trials.lua", 1, true), "stack")
    check(not d.stack:match("^[^\n]*Run%.lua"), "our own listening lines are left off the top of the stack")
    check(d.at:match("^%d%d%d%d%-"), "at")
    check(not cell(db, "own.show", KEY_PRESS), "the rest waits for the timers")
    c:advance(40)
    noErrors(c)
    for _, t in ipairs(P.SafeList(false)) do
        if not t.id:find("^win%.") or t.id:find("create$") then
            check(cell(db, t.id, KEY_PRESS), "no result for " .. t.id)
        end
    end
    for _, id in ipairs(RISKY) do check(not db.results[id], id .. " ran in Run all safe") end
    check(not db.results["err.chain"], "the risky Errors trial is not safe")
    check(not db.results["gfx.outlines"], "guided trials are not in Run all safe")
    eq(db.situations[KEY_PRESS].trigger, "press")
    eq(detail(db, "err.handler", KEY_PRESS).inPress, false, "later trials of the pass ran on timers")
    -- One row's Run: that trial alone, inside the tap.
    local row = showTrial(c, P, "own.escape")
    local before = countLog(db, "own.escape: allowed (straight from the press)")
    c:click(row.ppRun)
    eq(countLog(db, "own.escape: allowed (straight from the press)"), before + 1)
    eq(row.ppChipText:GetText(), "Allowed")
    check(P.status:find("own.escape done", 1, true), "status: " .. tostring(P.status))
    -- /probe run is Run all safe; /probe opens and closes the panel.
    c.env.SlashCmdList.POCKETPROBE("")
    check(not rawget(c.env, "PocketProbePanel"):IsShown(), "/probe closes the open panel")
    c.env.SlashCmdList.POCKETPROBE("")
    check(rawget(c.env, "PocketProbePanel"):IsShown(), "/probe opens it")
    c.env.SlashCmdList.POCKETPROBE("run")
    check(P.status:find("pass 1/", 1, true), "/probe run starts a pass: " .. tostring(P.status))
    c.env.SlashCmdList.POCKETPROBE("stop")
    check(P.status:find("stopped", 1, true), "status after /probe stop")
    local logged = countLog(db, ": ")
    c:advance(25)
    eq(countLog(db, ": "), logged, "nothing runs after Stop")
    noErrors(c)
end)

test("a risky trial's Run is dimmed and does nothing until Risky is on", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    local row = showTrial(c, P, "chat.open")
    eq(row.ppLabel:GetText(), "Open the chat box (risky)")
    eq(row.ppRun.ppDisabled, true)
    c:click(row.ppRun)
    check(not db.results["chat.open"], "a dimmed Run ran")
    eq(#c:callsTo("ChatFrameUtil.OpenChat"), 0)
    c:click(button(c, "PocketProbeRiskyButton"))
    row = showTrial(c, P, "chat.open")
    eq(row.ppRun.ppDisabled, false)
    c:click(row.ppRun)
    eq(cell(db, "chat.open", KEY_PRESS), "allowed")
    eq(countLog(db, "chat.open: allowed (straight from the press)"), 1)
    c:advance(5)
    check(not cell(db, "own.show", KEY_PRESS), "Run runs that one trial only")
    check(not c.editBox:IsShown(), "the chat box is closed again")
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
    end, saved = riskyOn() })
    c:advance(30)
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
    end, saved = riskyOn() })
    c:advance(30)
    noErrors(c)
    eq(cell(db, "chat.open", KEY_AUTO), "no effect")
    eq(cell(db, "layout.set", KEY_AUTO), "no effect")
    eq(detail(db, "layout.set").message, "Edit Mode open")
    eq(#c:callsTo("C_EditMode.SetActiveLayout"), 0)
end)

test("layout.sizes notes each frame's width, height and scale; a missing frame says missing", function()
    local c, P, db = new({ saved = riskyOn() })
    c:advance(30)
    noErrors(c)
    eq(cell(db, "layout.sizes", KEY_AUTO), "readable")
    local msg = db.last["layout.sizes"].message
    check(msg, "no numbers noted")
    check(msg:find("MinimapCluster w=230 h=230 scale=1", 1, true), "MinimapCluster size: " .. msg)
    check(msg:find("PlayerFrame missing", 1, true), "a missing frame: " .. msg)
    check(msg:find("GamepadMainActionBarFrame w=656", 1, true), "bar frame: " .. msg)
    check(msg:find("LeftCenteredAnchor w=50", 1, true), "anchor: " .. msg)
    check(msg:find("TopCenteredAnchor.Bar w=208", 1, true), "bar: " .. msg)
    check(msg:find("UIParent w=", 1, true), "UIParent: " .. msg)
    check(detail(db, "layout.sizes"), "the numbers are kept in a detail entry")
end)

test("bars.protected and bars.settings are readable and bars.settings counts layouts by type", function()
    local c, P, db = new({ saved = riskyOn(), setup = function(cl)
        cl.world.layouts = { activeLayout = 1, layouts = {
            { layoutName = "A", layoutType = 1 }, { layoutName = "B", layoutType = 2 }, { layoutName = "C", layoutType = 2 } } }
    end })
    c:advance(30)
    noErrors(c)
    eq(cell(db, "bars.protected", KEY_AUTO), "readable")
    eq(cell(db, "bars.settings", KEY_AUTO), "readable")
    local msg = db.last["bars.settings"].message
    check(msg:find("account layouts=1", 1, true), msg)
    check(msg:find("character layouts=2", 1, true), msg)
end)

test("bars.move sets the left anchor to its own point; missing frame, combat", function()
    local c, P, db = new({ saved = riskyOn() })
    c:advance(30)
    noErrors(c)
    eq(cell(db, "bars.move", KEY_AUTO), "allowed")
    eq(cell(db, "bars.scale", KEY_AUTO), "allowed")
    check(#c:callsTo("GamepadBar.LeftCenteredAnchor:SetPoint") >= 1, "SetPoint was called")
    check(#c:callsTo("GamepadBar.LeftCenteredAnchor:SetScale") >= 1, "SetScale was called")
    local c2, P2, db2 = new({ saved = riskyOn(), setup = function(cl) rawset(cl.env, "GamepadMainActionBarFrame", nil) end })
    c2:advance(30)
    noErrors(c2)
    eq(cell(db2, "bars.move", KEY_AUTO), "no effect")
    check(detail(db2, "bars.move").message, "a reason is given")
    local c3, P3, db3 = new({ saved = riskyOn() })
    c3:advance(30)
    c3:enterCombat(); c3:advance(30)
    noErrors(c3)
    -- Refused for combat: not tried and nothing saved (not a result that reads as "no effect").
    for _, id in ipairs({ "bars.move", "bars.scale", "layout.save" }) do
        eq(cell(db3, id, KEY_FIGHT), nil, id .. " saved a result in combat")
    end
    eq(#c3:callsTo("C_EditMode.SaveLayouts"), 1, "layout.save ran only out of combat")
    check(countLog(db3, "bars.move: not tried, in combat") >= 1, "the refusal is logged")
    -- Two anchor points (Compact on): left alone.
    local c4, P4, db4 = new({ saved = riskyOn(), setup = function(cl)
        local anchor = cl.env.GamepadMainActionBarFrame.PageUnit.LeftCenteredAnchor
        anchor:SetPoint("TOP", cl.env.UIParent, "TOP", 0, 0)
    end })
    c4:advance(30)
    noErrors(c4)
    eq(cell(db4, "bars.move", KEY_AUTO), "no effect")
    eq(detail(db4, "bars.move").message, "more than one anchor point")
    eq(#c4:callsTo("GamepadBar.LeftCenteredAnchor:ClearAllPoints"), 0)
end)

test("layout.save sends the presets and the saved layouts once, unchanged", function()
    local c, P, db = new({ saved = riskyOn(), setup = function(cl)
        cl.world.layouts = { activeLayout = 4, layouts = { { layoutName = "Mine", layoutType = 1, layoutIndex = 3, systems = {} } } }
    end })
    c:advance(30)
    noErrors(c)
    eq(cell(db, "layout.save", KEY_AUTO), "allowed")
    local calls = c:callsTo("C_EditMode.SaveLayouts")
    eq(#calls, 1)
    local info = calls[1].args and calls[1].args[1] or calls[1][1]
    eq(info.activeLayout, 4)
    eq(#info.layouts, 4)
    eq(info.layouts[4].layoutName, "Mine")
    eq(c.world.layouts.activeLayout, 4)
    eq(#c.world.layouts.layouts, 1)
end)

test("layout.save refuses with Edit Mode open and says so without a preset list", function()
    local c, P, db = new({ saved = riskyOn(), setup = function(cl) cl.world.editMode = true end })
    c:advance(30)
    eq(cell(db, "layout.save", KEY_AUTO), "no effect")
    eq(detail(db, "layout.save").message, "Edit Mode open")
    eq(#c:callsTo("C_EditMode.SaveLayouts"), 0)
    local c2, P2, db2 = new({ saved = riskyOn(), setup = function(cl) rawset(cl.env, "EditModePresetLayoutManager", nil) end })
    c2:advance(30)
    noErrors(c2)
    eq(cell(db2, "layout.save", KEY_AUTO), "no effect")
    eq(detail(db2, "layout.save").message, "no preset list")
end)

test("a missing function is 'missing'", function()
    local c, P, db = new({ setup = function(cl)
        rawset(cl.env.C_Container, "SortBags", nil)
        rawset(cl.env, "SmartNavigation_MarkFrameIgnored", nil)
        rawset(cl.env, "UnitName", nil)
        cl.typeMethods.EditBox.SetFocus = nil
        rawset(cl.env, "WorldMapFrame", nil)
    end, saved = riskyOn() })
    c:advance(30)
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

test("the clean series runs one trial per reload, watches, and ends", function()
    local saved = {}
    local c, P, db = new({ saved = saved })
    c:advance(25)
    local n = #P.cleanList
    local order = {}
    for i, t in ipairs(P.cleanList) do order[i] = t.id end
    eq(table.concat(order, " "), "chat.type chat.open chat.openframe chat.focus chat.close bag.toggle win.map.create "
        .. "win.bag.create win.chat.create pad.bind pad.mark layout.set layout.save vendor.sell1")
    openPanel(c)
    eq(button(c, "PocketProbeCleanButton").ppLabel:GetText(), "Clean run (reloads)")
    c:click(button(c, "PocketProbeCleanButton"))
    eq(c.reloads, 1, "Clean run reloads from the tap")
    eq(saved.clean.running, true); eq(saved.clean.index, 0)
    eq(saved.options.risky, false, "the series runs the risky trials whatever the switch says")
    local started = countLog(saved, "pass started")

    for i = 1, n do
        c, P = new({ saved = saved })
        local trial = P.cleanList[i]
        local resultsBefore = #dump(saved.results)
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
        local ran = 0
        for _, cells in pairs(saved.results) do
            if cells[KEY_CLEAN] then ran = ran + 1 end
        end
        eq(ran, i, "only that one trial ran")
        -- The watch: Next is not offered yet.
        local nextButton = button(c, "PocketProbeNextButton")
        check(P.status:find("watching for after-effects… ", 1, true) and P.status:match("%d$"),
            "status during the watch: " .. tostring(P.status))
        check(not nextButton:IsShown(), "Next waits for the watch")
        -- A fight in a clean session starts no pass either.
        c:enterCombat(); c:advance(2); c:leaveCombat(); c:advance(8)
        eq(countLog(saved, "pass started"), started, "no pass while the series runs")
        if i < n then
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
    eq(next(saved.spoiled), nil, "nothing was refused afterwards")
    -- The next login is an ordinary one again.
    c = new({ saved = saved })
    c:advance(25)
    eq(countLog(saved, "pass started"), started + 1)
end)

test("a refusal during a clean trial's watch is pinned on that trial", function()
    local saved = { clean = { running = true, index = 1 } }
    local c, P = new({ saved = saved })
    c:advance(4)
    eq(saved.clean.index, 2)
    check(cell(saved, "chat.open", KEY_CLEAN), "the clean trial ran")
    check(not P.warning, "no warning yet")
    c:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "InteractUnit()")
    c:advance(2)
    c:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "InteractUnit()")
    eq(saved.spoiled[KEY_CLEAN], "chat.open")
    eq(cell(saved, "after.InteractUnit", KEY_CLEAN), "forbidden")
    eq(detail(saved, "after.InteractUnit").message, "seen 2 times this session; first seen after: chat.open")
    eq(P.warning, "controls may misbehave until a reload — tap Save")
    c:advance(8)
    eq(P.status, "clean trial 2 of " .. #P.cleanList .. ": tap Next")
    noErrors(c)
end)

test("refusals outside a trial are counted once per situation, with a quiet log", function()
    local saved = {}
    local c, P, db = new({ saved = saved })
    c:advance(25)
    local trialCount = #db.trials
    check(not P.warning, "no warning before anything was refused")
    c:fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "InteractUnit()")
    eq(next(db.spoiled), nil, "another addon's refusal is not ours")
    -- The player presses interact and cancel for a minute.
    for _ = 1, 60 do
        c:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "InteractUnit()")
        c:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "ClearTarget()")
        c:advance(1)
    end
    c.env.DisplayInterfaceActionBlockedMessage()
    noErrors(c)
    eq(db.spoiled[KEY_AUTO], "val.name.target", "the last trial of the pass")
    eq(cell(db, "after.InteractUnit", KEY_AUTO), "forbidden")
    eq(cell(db, "after.ClearTarget", KEY_AUTO), "forbidden")
    eq(cell(db, "after.message", KEY_AUTO), "blocked")
    eq(#db.trials, trialCount + 3)
    local entry = db.trials[trialCount + 1]
    eq(entry.id, "after.InteractUnit"); eq(entry.kind, "action")
    eq(entry.area, "Afterwards (the game's own actions refused in the probe's name)")
    eq(entry.label, "InteractUnit refused afterwards")
    local entries = 0
    for _, d in ipairs(db.details) do if d.trial == "after.InteractUnit" then entries = entries + 1 end end
    eq(entries, 1, "one detail entry per refused function and situation")
    local d = detail(db, "after.InteractUnit")
    eq(d.result, "forbidden"); eq(d.func, "InteractUnit()"); eq(d.situation, KEY_AUTO)
    eq(d.message, "seen 60 times this session; first seen after: val.name.target")
    check(type(d.stack) == "string" and d.stack ~= "", "stack kept")
    eq(countLog(db, "after.InteractUnit: forbidden"), 1, "one log line on first sight")
    local summaries = countLog(db, "more refusal")
    check(summaries >= 3 and summaries <= 7, "about one summary line per ten seconds, got " .. summaries)
    eq(P.warning, "controls may misbehave until a reload — tap Save")
    -- A fight is another situation: counted there too.
    c:enterCombat(); c:advance(30)
    c:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "InteractUnit()")
    eq(cell(db, "after.InteractUnit", KEY_FIGHT), "forbidden")
    eq(db.spoiled[KEY_FIGHT], nil, "only the first refusal of a session names a trial")
    -- The next session: the list keeps its extra entries once, and a second answer is merged.
    local c2, P2 = new({ saved = saved, setup = function(cl) rawset(cl.env, "UnitName", nil) end })
    eq(#saved.trials, trialCount + 3)
    c2:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", "InteractUnit()")
    eq(saved.spoiled[KEY_AUTO], "val.name.target / no trial yet")
    eq(#saved.trials, trialCount + 3)
    eq(detail(saved, "after.InteractUnit").message, "seen 1 time this session; first seen after: no trial yet")
    noErrors(c2)
end)

test("results from another probe version are cleared at load", function()
    local saved = {
        version = 1, probe = "0.1.0", options = { vendor = false },
        results = { ["chat.open"] = { [KEY_AUTO] = "allowed" } }, details = { { trial = "chat.open" } },
        situations = { [KEY_AUTO] = { passes = 3 } }, spoiled = { [KEY_AUTO] = "chat.open" },
        log = { "00:00:00 old line" }, clean = { index = 5, running = true }, pressIndex = 9,
        trials = { { id = "after.InteractUnit", area = "x", label = "y", kind = "action" } },
        last = { ["chat.open"] = { result = "allowed" } },
        guided = { ["gfx.icons"] = { stage = "ask", old = { SoftTargetLowPriorityIcons = "0" } } },
    }
    local c, P, db = new({ saved = saved })
    eq(db, saved)
    eq(db.probe, "0.4.0")
    eq(next(db.last), nil, "the panel's newest results are cleared too")
    eq(db.guided["gfx.icons"].stage, "ask", "a guided trial's old values are kept, to be put back")
    eq(next(db.results), nil); eq(#db.details, 0); eq(next(db.situations), nil); eq(next(db.spoiled), nil)
    eq(db.clean.running, false); eq(db.clean.index, 0); eq(db.pressIndex, 0)
    eq(db.options.vendor, false, "the switches are kept")
    eq(countLog(db, "old line"), 0)
    eq(countLog(db, "results from probe 0.1.0 cleared"), 1)
    for _, t in ipairs(db.trials) do check(not t.id:find("^after%."), "old extra entries are dropped too") end
    c:advance(25)
    eq(db.situations[KEY_AUTO].passes, 1)
    -- The same version again: nothing is cleared.
    local c2 = new({ saved = saved })
    eq(saved.situations[KEY_AUTO].passes, 1)
    eq(countLog(saved, "cleared"), 1)
    noErrors(c2)
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
    openPanel(c)
    local switch = button(c, "PocketProbeVendorButton")
    c:click(switch)
    eq(db.options.vendor, false)
    eq(switch.ppLabel:GetText(), "Vendor: Off")
    eq(showTrial(c, P, "vendor.sell1").ppRun.ppDisabled, true, "vendor Run is dimmed while Vendor is off")
    c:openMerchant(); c:advance(10); c:closeMerchant()
    eq(#c:callsTo("C_Container.UseContainerItem"), 0)
    eq(c.sellAllCalls, nil)
    eq(#c:callsTo("RepairAllItems"), 0)
    check(not db.results["vendor.sell1"], "vendor trial ran with the switch off")
    -- Switch on.
    c:click(switch)
    eq(switch.ppLabel:GetText(), "Vendor: On")
    -- Run with no vendor open says so and tries nothing.
    c:click(showTrial(c, P, "vendor.sell1").ppRun)
    eq(P.status, "open a vendor first")
    c:click(button(c, "PocketProbeCloseButton"))
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
    -- Run all safe with the vendor open does.
    openPanel(c)
    c:click(button(c, "PocketProbeRunAllButton")); c:advance(40)
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
    -- Another addon's error carries world text in its message and its locals.
    c:otherError("SomeAddon", "Broken Fang: attempt to index a nil value")
    openPanel(c)
    c:click(button(c, "PocketProbeRunAllButton")); c:advance(40)
    c:click(button(c, "PocketProbeRiskyButton"))
    c:click(showTrial(c, P, "err.chain").ppRun); c:advance(3)
    c:click(showTrial(c, P, "gfx.icons").ppRun)
    c:click(showTrial(c, P, "gfx.icons").ppAnswer[1])
    c:click(button(c, "PocketProbeCloseButton"))
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
    openPanel(c)
    c:click(button(c, "PocketProbeRunAllButton")); c:advance(40)
    noErrors(c)
    eq(#db.details, 400)
    eq(db.details[400].trial, "gfx.names", "newest last")
    check(db.details[1].at ~= "old 1", "oldest dropped")
    check(#db.log <= 2000, "log has " .. #db.log .. " lines")
    check(#db.log >= 1700, "the log drops its oldest lines in blocks, not everything")
    check(db.log[#db.log]:find("pass done", 1, true), "newest log line last")
end)

test("the probe's frames are made at load and nothing ticks", function()
    local c, P, db = new()
    local atLoad = #c:frames()
    for _, name in ipairs({ "PocketProbeButton", "PocketProbeStopButton", "PocketProbeNextButton" }) do
        local b = button(c, name)
        local st = c._state(b)
        eq(st.strata, "HIGH", name .. " strata")
        eq(st.parent, c.UIParent, name .. " parent")
        check(b:GetHeight() >= 40, name .. " is big enough for a finger")
        check(not b:IsProtected(), name .. " is a plain frame")
    end
    local panel = button(c, "PocketProbePanel")
    eq(c._state(panel).strata, "DIALOG")
    for _, name in ipairs({ "PocketProbeRunAllButton", "PocketProbeCleanButton", "PocketProbeRiskyButton",
        "PocketProbeVendorButton", "PocketProbeAutoButton", "PocketProbeSaveButton", "PocketProbeCloseButton" }) do
        eq(c._state(button(c, name)).parent, panel, name .. " is on the panel")
        check(not button(c, name):IsProtected(), name .. " is a plain frame")
    end
    check(not button(c, "PocketProbeNextButton"):IsShown(), "Next is hidden")
    openPanel(c)
    c:advance(25)
    c:enterCombat(); c:advance(25)
    c:leaveCombat(); c:click(button(c, "PocketProbeCloseButton")); openPanel(c); c:advance(2)
    -- Only the trial buttons were added: three under Blizzard windows and one
    -- under our own window per pass.
    eq(#c:frames() - atLoad, 5)
    eq(c.stats.addonOnUpdate, 0, "no OnUpdate")
    for _, rec in ipairs(c:frames()) do check(not rec.scripts.OnUpdate, "a frame has an OnUpdate script") end
    local _, _, top = c._rect(button(c, "PocketProbeButton"))
    check(top > 700, "Probe sits at the top of the screen")
    eq(button(c, "PocketProbeSaveButton").ppLabel:GetText(), "Save (reloads)")
    c:click(button(c, "PocketProbeSaveButton"))
    eq(c.reloads, 1, "Save reloads from the tap")
    noErrors(c)
end)

---------------------------------------------------------------------------
-- The panel (0.3.0)
---------------------------------------------------------------------------

-- The labels of the tabs on show, in order.
local function tabLabels(P)
    local out = {}
    for _, t in ipairs(P.panelTabs) do
        if t:IsShown() then out[#out + 1] = t.ppName:GetText() end
    end
    return out
end

test("the panel: Settings-sized, area tabs with counts, no scroll bar (big areas split)", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    local panel = button(c, "PocketProbePanel")
    check(not panel:IsShown(), "closed at login")
    openPanel(c)
    -- Settings.lua PanelSize: min(screenW*0.96, Px(1180)) x screenH*0.92 (UIParent is 768 units tall here).
    local uiW, uiH = c.UIParent:GetWidth(), c.UIParent:GetHeight()
    local px = 768 / 720
    check(math.abs(panel:GetWidth() - math.min(uiW * 0.96, 1180 * px)) < 0.01, "width " .. panel:GetWidth())
    check(math.abs(panel:GetHeight() - uiH * 0.92) < 0.01, "height " .. panel:GetHeight())
    local titleText
    for _, rec in ipairs(c:frames()) do
        if rec.frame == panel then
            for _, region in ipairs(rec.regions or {}) do
                if region.GetText and region:GetText() == "Pocket Probe 0.4.0" then titleText = true end
            end
        end
    end
    check(titleText, "titled Pocket Probe 0.4.0")
    local labels = tabLabels(P)
    eq(labels[1], "Errors"); eq(labels[2], "Graphics")
    local joined = table.concat(labels, "|")
    for _, area in ipairs({ "Our own windows", "Chat box", "Bags and vendor", "Controller and layout" }) do
        check(joined:find(area, 1, true), "no tab for " .. area .. ": " .. joined)
    end
    -- More trials than fit: two tabs, never a scroll bar.
    local m = P.panelSizes
    check(m.rowsFit >= 4 and m.rowsFit <= 12, "rows that fit: " .. m.rowsFit)
    check(joined:find("Values 1|Values 2", 1, true), "Values is split in two: " .. joined)
    check(joined:find("Blizzard windows 1|Blizzard windows 2", 1, true), "Blizzard windows is split in two: " .. joined)
    local shown, total = 0, 0
    for _, page in ipairs(P.BuildPages(m.rowsFit)) do
        check(#page.entries <= m.rowsFit, page.label .. " has more rows than fit")
        total = total + #page.entries
    end
    eq(total, #db.trials, "every trial is on a tab")
    for _, rec in ipairs(c:frames()) do
        check(rec.type ~= "ScrollFrame" or not rec.addonFile or not rec.addonFile:find("Panel", 1, true), "the panel made a scroll frame")
    end
    -- Every row and the tabs fit inside the panel.
    local _, _, panelTop, panelBottom = c._rect(panel)
    for _, r in ipairs(P.panelRows) do
        if r:IsShown() then
            local _, _, top, bottom = c._rect(r)
            check(top <= panelTop + 0.01 and bottom >= panelBottom - 0.01, "a row is outside the panel")
        end
    end
    for _, t in ipairs(P.panelTabs) do
        if t:IsShown() then
            local _, _, _, bottom = c._rect(t)
            local _, _, footTop = c._rect(button(c, "PocketProbeRunAllButton"))
            check(bottom > footTop, "a tab reaches into the footer")
        end
    end
    -- Counts: "N / M run", and a row's chip after Run.
    eq(P.panelTabs[1].ppCount:GetText(), "0 / 7 run")
    local row = showTrial(c, P, "err.handler")
    eq(row.ppChipText:GetText(), "Not run")
    c:click(row.ppRun)
    eq(row.ppChipText:GetText(), "function")
    eq(P.panelTabs[1].ppCount:GetText(), "1 / 7 run")
    -- Tapping a row shows its details in one line under the list.
    c:click(row)
    local detailsText
    for _, rec in ipairs(c:frames()) do
        if rec.frame == panel then
            for _, region in ipairs(rec.regions or {}) do
                local t = region.GetText and region:GetText()
                if type(t) == "string" and t:find("Details:", 1, true) then detailsText = t end
            end
        end
    end
    check(detailsText and detailsText:find("geterrorhandler function", 1, true), "details: " .. tostring(detailsText))
    -- Close and /probe.
    c:click(button(c, "PocketProbeCloseButton"))
    check(not panel:IsShown(), "Close closes")
    noErrors(c)
end)

test("at 1280x720 and Medium: at most 10 tabs, each at least 0.85 of a button tall, no page scrolls", function()
    local c, P, db = new({ auto = false })
    openPanel(c)
    local m = P.panelSizes
    local shown = {}
    for _, t in ipairs(P.panelTabs) do
        if t:IsShown() then
            shown[#shown + 1] = t
            check(t:GetHeight() >= 0.85 * m.button - 0.01,
                t.ppName:GetText() .. " is " .. t:GetHeight() .. " tall, button " .. m.button)
            eq((t.ppCount:GetPoint(1)), "TOPLEFT", t.ppName:GetText() .. ": the count sits under the name, not on one line")
        end
    end
    check(#shown <= 10, #shown .. " tabs: " .. table.concat(tabLabels(P), "|"))
    eq(table.concat(tabLabels(P), "|"), "Errors|Graphics|Our own windows|Blizzard windows 1|Blizzard windows 2|Chat box|"
        .. "Bags and vendor|Controller and layout|Values 1|Values 2")
    for _, page in ipairs(P.BuildPages(m.rowsFit)) do
        check(#page.entries <= m.rowsFit, page.label .. " has more rows than fit")
    end
    -- Every row of every page lies inside the list area (above the Details line).
    local _, _, panelTop = c._rect(button(c, "PocketProbePanel"))
    for _, t in ipairs(shown) do
        c:click(t)
        for _, r in ipairs(P.panelRows) do
            if r:IsShown() then
                local _, _, top, bottom = c._rect(r)
                check(top <= panelTop + 0.01, "a row above the panel")
                check(panelTop - bottom <= m.cy + m.listH + 0.01, t.ppName:GetText() .. ": a row reaches below the list")
            end
        end
    end
    noErrors(c)
end)

test("the d-pad drives the panel; its keys are given back on close and in a fight", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    local panel = button(c, "PocketProbePanel")
    local function bound()
        return c._state(panel).bindings
    end
    check(not bound(), "no keys taken while closed")
    openPanel(c)
    local keys = bound()
    check(keys, "keys taken while open")
    for _, key in ipairs({ "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PAD1", "PAD2" }) do
        eq(keys[key], "PocketProbeNavButton", key)
    end
    -- The first press puts the highlight on the tabs; Down moves to Graphics.
    pad(c, "DOWN")
    eq(P.Nav.zone, "tabs")
    pad(c, "DOWN")
    local graphics = P.panelRows[1].ppEntry
    eq(graphics and graphics.id, "gfx.read", "Down selects the next tab")
    -- Right: the first row, then its Run; A runs it.
    pad(c, "RIGHT")
    eq(P.Nav.zone, "rows")
    pad(c, "RIGHT")
    eq(P.Nav.Target(), P.panelRows[1].ppRun)
    pad(c, "A")
    eq(cell(db, "gfx.read", KEY_PRESS), "sparkle 0 · outline 2")
    -- Down along the rows, past the last one to the footer; Left / Right along it.
    for _ = 1, 10 do pad(c, "DOWN") end
    eq(P.Nav.zone, "footer")
    pad(c, "RIGHT"); pad(c, "RIGHT")
    eq(P.Nav.Target(), button(c, "PocketProbeRiskyButton"))
    pad(c, "A")
    eq(db.options.risky, true, "A pressed Risky")
    pad(c, "UP")
    eq(P.Nav.zone, "rows")
    pad(c, "LEFT"); pad(c, "LEFT")
    eq(P.Nav.zone, "tabs")
    -- A release with no press seen is not ours.
    c:script(button(c, "PocketProbeNavButton"), "OnClick", "B", false)
    check(panel:IsShown(), "a lone release closed the panel")
    -- A fight: the keys go back; after it they are taken again.
    c:enterCombat()
    check(not bound(), "keys given back in a fight")
    c:leaveCombat()
    check(bound(), "keys taken again after the fight")
    -- B closes and gives them back.
    pad(c, "B")
    check(not panel:IsShown(), "B closes")
    check(not bound(), "keys given back on close")
    noErrors(c)
end)

---------------------------------------------------------------------------
-- Area Errors
---------------------------------------------------------------------------

test("Errors: handler, box, hook, others' errors by source, blocked actions of others", function()
    local c, P, db = new({ auto = false, setup = function(cl) cl.world.addons = { BugSack = true } end })
    c:advance(5)
    -- Before any trial: other addons' errors and blocks are counted from load.
    c:otherError("SomeAddon", "Kill Ten Rats: attempt to call a nil value")
    c:otherError("SomeAddon", "Kill Ten Rats: attempt to call a nil value")
    c:otherError("Blizzard_QuestLog", "Elwynn: bad argument")
    c:fire("ADDON_ACTION_BLOCKED", "SomeAddon", "CastSpellByName()")
    c:fire("ADDON_ACTION_FORBIDDEN", "OtherAddon", "UseAction()")
    c:fire("LUA_WARNING", "a warning")
    local function run(id)
        local row = showTrial(c, P, id)
        c:click(row.ppRun)
        return row
    end
    run("err.handler")
    eq(cell(db, "err.handler", KEY_PRESS), "function")
    check(db.last["err.handler"].message:find("error addons loaded: BugSack", 1, true), "BugSack noticed")
    run("err.box")
    eq(cell(db, "err.box", KEY_PRESS), "readable")
    check(db.last["err.box"].message:find("entries in the box 3", 1, true), db.last["err.box"].message)
    run("err.hook")
    check(not cell(db, "err.hook", KEY_PRESS), "the hook trial waits a second")
    c:advance(1.5)
    eq(cell(db, "err.hook", KEY_PRESS), "allowed")
    local msg = db.last["err.hook"].message
    check(msg:find("message readable; stack readable; box shown yes", 1, true), msg)
    run("err.others")
    eq(cell(db, "err.others", KEY_PRESS), "3 (SomeAddon 2, Blizzard 1)")
    msg = db.last["err.others"].message
    check(msg:find("warnings (LUA_WARNING) 1", 1, true), msg)
    check(msg:find("the probe's own 1", 1, true), msg)
    run("err.blocked")
    eq(cell(db, "err.blocked", KEY_PRESS), "2 seen")
    check(db.last["err.blocked"].message:find("OtherAddon 1, SomeAddon 1", 1, true), db.last["err.blocked"].message)
    -- Run again: the cell keeps the newest count only.
    c:otherError("SomeAddon", "again")
    run("err.others")
    eq(cell(db, "err.others", KEY_PRESS), "4 (SomeAddon 3, Blizzard 1)")
    -- Others' error text and the locals are never kept.
    local text = table.concat(dump(db), "\n")
    for _, word in ipairs({ "Kill Ten Rats", "Elwynn", "secret locals", "attempt to call" }) do
        check(not text:find(word, 1, true), "the saved table holds \"" .. word .. "\"")
    end
    noErrors(c)
end)

test("Errors: hiding the box, and a chained handler (risky); both put things back", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    local handlerBefore = c.env.geterrorhandler()
    local row = showTrial(c, P, "err.hide")
    c:click(row.ppRun)
    eq(c.world.cvars.scriptErrors, "0", "set to 0 for the test")
    c:advance(1.5)
    eq(cell(db, "err.hide", KEY_PRESS), "allowed")
    local msg = db.last["err.hide"].message
    check(msg:find("value 1, default 0, isSecure yes, isReadOnly no, locked no", 1, true), msg)
    check(msg:find("written back unchanged: ok", 1, true), msg)
    check(msg:find("box shown no", 1, true), msg)
    eq(c.world.cvars.scriptErrors, "1", "the old value is put back")
    eq(c.errorBox.shown, false)
    -- A box left open is closed first, so the test still tells.
    c.errorBox.shown = true
    c:click(showTrial(c, P, "err.hide").ppRun); c:advance(1.5)
    eq(db.last["err.hide"].result, "allowed", "the open box was closed before the test")
    eq(c.errorBox.shown, false)
    -- A box that will not close: "can't tell", never Allowed.
    c.errorBox.shown, c.errorBox.stuck = true, true
    c:click(showTrial(c, P, "err.hide").ppRun); c:advance(1.5)
    eq(db.last["err.hide"].result, "can't tell")
    eq(cell(db, "err.hide", KEY_PRESS), "allowed / can't tell")
    check(db.last["err.hide"].message:find("still open after closing it", 1, true), db.last["err.hide"].message)
    eq(showTrial(c, P, "err.hide").ppChipText:GetText(), "Can't tell")
    eq(c.world.cvars.scriptErrors, "1", "put back")
    c.errorBox.shown, c.errorBox.stuck = false, nil
    -- scriptErrors already 0: "can't tell", and nothing is written.
    c.world.cvars.scriptErrors = "0"
    local writes = #c:callsTo("C_CVar.SetCVar")
    c:click(showTrial(c, P, "err.hide").ppRun)
    eq(db.last["err.hide"].result, "can't tell")
    check(db.last["err.hide"].message:find("already 0", 1, true), db.last["err.hide"].message)
    eq(#c:callsTo("C_CVar.SetCVar"), writes, "nothing written")
    eq(c.world.cvars.scriptErrors, "0")
    c.world.cvars.scriptErrors = "1"
    -- The chained handler is risky: inert until Risky is on.
    row = showTrial(c, P, "err.chain")
    eq(row.ppRun.ppDisabled, true)
    c:click(button(c, "PocketProbeRiskyButton"))
    row = showTrial(c, P, "err.chain")
    c:click(row.ppRun)
    check(c.env.geterrorhandler() ~= handlerBefore, "our handler is on during the trial")
    c:advance(1.5)
    eq(cell(db, "err.chain", KEY_PRESS), "allowed")
    check(db.last["err.chain"].message:find("our handler saw the test error yes; Blizzard's box still got it yes", 1, true),
        db.last["err.chain"].message)
    eq(c.env.geterrorhandler(), handlerBefore, "the old handler is put back")
    noErrors(c)
end)

test("Errors: no error box on this client is 'missing', not a Lua error", function()
    local c, P, db = new({ auto = false, setup = function(cl) rawset(cl.env, "ScriptErrorsFrame", nil) end })
    c:advance(5)
    for _, id in ipairs({ "err.box", "err.hook", "err.others" }) do
        c:click(showTrial(c, P, id).ppRun)
    end
    eq(cell(db, "err.box", KEY_PRESS), "missing")
    eq(cell(db, "err.hook", KEY_PRESS), "missing")
    eq(cell(db, "err.others", KEY_PRESS), "no listener")
    noErrors(c)
end)

---------------------------------------------------------------------------
-- Area Graphics
---------------------------------------------------------------------------

test("Graphics: read, write (put back) and the setting names", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    c:click(showTrial(c, P, "gfx.read").ppRun)
    eq(cell(db, "gfx.read", KEY_PRESS), "sparkle 0 · outline 2")
    local msg = db.last["gfx.read"].message
    check(msg:find("IsOutlineModeSupported true", 1, true), msg)
    check(msg:find("IsSpellVisualDensitySystemSupported false", 1, true), msg)
    check(msg:find("graphicsOutlineMode 2 (default 0)", 1, true), msg)
    check(msg:find("OutlineEngineMode not on this client", 1, true), msg)
    check(msg:find("SoftTargetInteract 1 (default 0)", 1, true), msg)
    c:click(showTrial(c, P, "gfx.write").ppRun)
    eq(cell(db, "gfx.write", KEY_PRESS), "allowed")
    check(db.last["gfx.write"].message:find("set to 1, read back 1", 1, true), db.last["gfx.write"].message)
    eq(c.world.cvars.outlineModeShowLootEffectWhenDisabled, "0", "the old value is put back")
    c:click(showTrial(c, P, "gfx.names").ppRun)
    eq(cell(db, "gfx.names", KEY_PRESS), "4 found")
    eq(db.last["gfx.names"].message, "graphicsOutlineMode, lootUnderMouse, outlineModeShowLootEffectWhenDisabled, spellClutter")
    -- A client without the sparkle setting.
    local c2, P2, db2 = new({ auto = false, setup = function(cl) cl.world.cvars.outlineModeShowLootEffectWhenDisabled = nil end })
    c2:click(showTrial(c2, P2, "gfx.write").ppRun)
    eq(cell(db2, "gfx.write", KEY_PRESS), "missing")
    noErrors(c); noErrors(c2)
end)

test("Graphics, guided: Outlines off waits for a full restart, asks, then puts the old values back", function()
    local saved = { options = { auto = false } }
    local c, P = new({ saved = saved })
    c:advance(5)
    local row = showTrial(c, P, "gfx.outlines")
    eq(row.ppRun.ppLabel:GetText(), "Start")
    eq(row.ppChipText:GetText(), "Not run")
    c:click(row.ppRun)
    eq(c.world.cvars.graphicsOutlineMode, "0"); eq(c.world.cvars.raidGraphicsOutlineMode, "0")
    eq(c.world.cvars.outlineModeShowLootEffectWhenDisabled, "1")
    local g = saved.guided["gfx.outlines"]
    eq(g.stage, "restart")
    eq(g.old.graphicsOutlineMode, "2"); eq(g.old.outlineModeShowLootEffectWhenDisabled, "0")
    row = showTrial(c, P, "gfx.outlines")
    eq(row.ppChipText:GetText(), "Restart the game")
    eq(row.ppRun.ppLabel:GetText(), "Cancel", "Cancel in place of Start while it waits")
    eq(row.ppRun.ppDisabled, false)
    check(not row.ppAnswer[1]:IsShown(), "no answers before the restart")
    check(P.status:find("Close the game app completely and open it again", 1, true), "status: " .. tostring(P.status))
    check(P.status:find("logging out to character select", 1, true), "says logging out is not enough")
    check(P.status:find("Outlines off is waiting for a game restart, or Cancel", 1, true), "status: " .. tostring(P.status))
    -- A reload is not a restart, and logging out keeps a trial that needs one.
    c:fire("PLAYER_LOGOUT")
    c:fire("PLAYER_ENTERING_WORLD", false, true)
    eq(saved.guided["gfx.outlines"].stage, "restart")
    eq(c.world.cvars.graphicsOutlineMode, "0", "kept across the logout")
    -- A full restart: a new session whose login is the first.
    local c2, P2 = new({ saved = saved, setup = function(cl)
        cl.world.cvars.graphicsOutlineMode, cl.world.cvars.raidGraphicsOutlineMode = "0", "0"
        cl.world.cvars.outlineModeShowLootEffectWhenDisabled = "1"
    end })
    eq(saved.guided["gfx.outlines"].stage, "ask")
    check(P2.status:find("Outlines off is waiting: answer or Cancel", 1, true), "status: " .. tostring(P2.status))
    row = showTrial(c2, P2, "gfx.outlines")
    check(row.ppAnswer[1]:IsShown() and row.ppAnswer[2]:IsShown(), "the two answers show")
    check(not row.ppChip:IsShown(), "in place of the chip")
    eq(row.ppRun.ppLabel:GetText(), "Cancel")
    eq(row.ppAnswer[1].ppLabel:GetText(), "Sparkles seen"); eq(row.ppAnswer[2].ppLabel:GetText(), "No sparkles")
    c2:click(row.ppAnswer[2])
    eq(cell(saved, "gfx.outlines", KEY_PRESS), "no sparkles")
    eq(saved.guided["gfx.outlines"], nil)
    eq(c2.world.cvars.graphicsOutlineMode, "2"); eq(c2.world.cvars.raidGraphicsOutlineMode, "2")
    eq(c2.world.cvars.outlineModeShowLootEffectWhenDisabled, "0")
    check(saved.last["gfx.outlines"].message:find("old values put back", 1, true), saved.last["gfx.outlines"].message)
    check(not P2.status:find("waiting", 1, true), "the status no longer says it waits")
    row = showTrial(c2, P2, "gfx.outlines")
    eq(row.ppChipText:GetText(), "no sparkles")
    noErrors(c); noErrors(c2)
end)

test("Graphics, guided: Interact icons asks at once, notes and sets the icon settings, puts them back", function()
    local saved = { options = { auto = false } }
    local c, P = new({ saved = saved, setup = function(cl)
        cl.world.cvars.SoftTargetIconInteract, cl.world.cvars.SoftTargetIconGameObject = "0", "1"
        cl.world.cvars.SoftTargetIconEnemy = "0"
    end })
    c:advance(5)
    c:click(showTrial(c, P, "gfx.read").ppRun)
    local msg = saved.last["gfx.read"].message
    for _, part in ipairs({ "SoftTargetIconInteract 0", "SoftTargetIconGameObject 1", "SoftTargetIconEnemy 0" }) do
        check(msg:find(part, 1, true), "gfx.read notes " .. part .. ": " .. msg)
    end
    c:click(showTrial(c, P, "gfx.icons").ppRun)
    eq(c.world.cvars.SoftTargetLowPriorityIcons, "1")
    eq(c.world.cvars.SoftTargetIconInteract, "1", "0 is set to 1 for the trial")
    eq(c.world.cvars.SoftTargetIconGameObject, "1")
    local g = saved.guided["gfx.icons"]
    eq(g.stage, "ask")
    eq(g.old.SoftTargetIconInteract, "0"); eq(g.old.SoftTargetIconGameObject, nil, "a 1 is left alone")
    check(g.notes:find("SoftTargetIconInteract 0 -> 1", 1, true), g.notes)
    check(g.notes:find("SoftTargetIconGameObject 1", 1, true) and g.notes:find("SoftTargetIconEnemy 0", 1, true), g.notes)
    local row = showTrial(c, P, "gfx.icons")
    eq(row.ppAnswer[1].ppLabel:GetText(), "Icon seen")
    c:click(row.ppAnswer[1])
    eq(cell(saved, "gfx.icons", KEY_PRESS), "icon seen")
    check(saved.last["gfx.icons"].message:find("SoftTargetIconEnemy 0", 1, true), "the answer keeps the notes")
    eq(c.world.cvars.SoftTargetLowPriorityIcons, "0", "put back")
    eq(c.world.cvars.SoftTargetIconInteract, "0", "put back")
    noErrors(c)
end)

test("Guided: Cancel, Stop and logging out put the old values back", function()
    local saved = { options = { auto = false } }
    local c, P = new({ saved = saved })
    c:advance(5)
    -- Cancel while waiting for the restart.
    c:click(showTrial(c, P, "gfx.outlines").ppRun)
    c:click(showTrial(c, P, "gfx.outlines").ppRun)
    eq(saved.guided["gfx.outlines"], nil)
    eq(c.world.cvars.graphicsOutlineMode, "2"); eq(c.world.cvars.outlineModeShowLootEffectWhenDisabled, "0")
    eq(countLog(saved, "gfx.outlines: cancelled"), 1)
    eq(showTrial(c, P, "gfx.outlines").ppRun.ppLabel:GetText(), "Start")
    -- Cancel while asking.
    c:click(showTrial(c, P, "gfx.icons").ppRun)
    c:click(showTrial(c, P, "gfx.icons").ppRun)
    eq(saved.guided["gfx.icons"], nil); eq(c.world.cvars.SoftTargetLowPriorityIcons, "0")
    check(not saved.results["gfx.icons"], "a cancelled trial has no answer")
    -- Stop and /probe stop call off every waiting trial.
    c:click(showTrial(c, P, "gfx.outlines").ppRun)
    c:click(showTrial(c, P, "gfx.icons").ppRun)
    c.env.SlashCmdList.POCKETPROBE("stop")
    eq(next(saved.guided), nil)
    eq(c.world.cvars.graphicsOutlineMode, "2"); eq(c.world.cvars.SoftTargetLowPriorityIcons, "0")
    c:click(showTrial(c, P, "gfx.icons").ppRun)
    P.Stop()
    eq(next(saved.guided), nil)
    -- Logging out (or reloading) puts back a trial that needs no restart.
    c:click(showTrial(c, P, "gfx.icons").ppRun)
    eq(c.world.cvars.SoftTargetLowPriorityIcons, "1")
    c:fire("PLAYER_LOGOUT")
    eq(saved.guided["gfx.icons"], nil)
    eq(c.world.cvars.SoftTargetLowPriorityIcons, "0")
    eq(countLog(saved, "gfx.icons: put back at logout"), 1)
    noErrors(c)
end)

test("Guided: an answer whose put-back fails keeps what failed; Cancel retries", function()
    local saved = { options = { auto = false } }
    local c, P = new({ saved = saved })
    c:advance(5)
    c:click(showTrial(c, P, "gfx.outlines").ppRun)
    saved.guided["gfx.outlines"].stage = "ask"
    -- The game refuses one of the writes back.
    local set = c.env.C_CVar.SetCVar
    rawset(c.env.C_CVar, "SetCVar", function(name, value)
        if name == "raidGraphicsOutlineMode" then return false end
        return set(name, value)
    end)
    c:click(showTrial(c, P, "gfx.outlines").ppAnswer[1])
    eq(cell(saved, "gfx.outlines", KEY_PRESS), "sparkles seen", "the answer is kept")
    local g = saved.guided["gfx.outlines"]
    check(g, "the entry is kept while something is not put back")
    eq(g.stage, "putback")
    eq(g.old.raidGraphicsOutlineMode, "2"); eq(g.old.graphicsOutlineMode, nil, "only what failed is kept")
    eq(c.world.cvars.graphicsOutlineMode, "2")
    check(P.status:find("could not put back raidGraphicsOutlineMode: tap Cancel to retry", 1, true), P.status)
    check(saved.last["gfx.outlines"].message:find("could not put back raidGraphicsOutlineMode", 1, true), "said in the answer")
    local row = showTrial(c, P, "gfx.outlines")
    eq(row.ppChipText:GetText(), "Not put back")
    eq(row.ppRun.ppLabel:GetText(), "Cancel")
    -- Still refused: kept. Then the game takes it.
    c:click(row.ppRun)
    check(saved.guided["gfx.outlines"], "still kept")
    rawset(c.env.C_CVar, "SetCVar", set)
    c:click(showTrial(c, P, "gfx.outlines").ppRun)
    eq(saved.guided["gfx.outlines"], nil)
    eq(c.world.cvars.raidGraphicsOutlineMode, "2")
    noErrors(c)
end)

test("Guided: a trial a later version removed is put back and dropped at load", function()
    local saved = { options = { auto = false }, guided = {
        ["gfx.gone"] = { stage = "ask", old = { graphicsOutlineMode = "3", NoSuchSetting = false } },
        ["gfx.icons"] = { stage = "ask", old = { SoftTargetLowPriorityIcons = "0" } },
    } }
    local c, P = new({ saved = saved, setup = function(cl) cl.world.cvars.graphicsOutlineMode = "0" end })
    eq(saved.guided["gfx.gone"], nil)
    eq(c.world.cvars.graphicsOutlineMode, "3", "its setting is put back")
    check(saved.guided["gfx.icons"], "a trial that still exists is kept")
    eq(countLog(saved, "gfx.gone: no such trial any more; settings put back"), 1)
    noErrors(c)
end)

test("a reload while a trial waits for its check puts it back first", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    c:click(showTrial(c, P, "err.hide").ppRun)
    eq(c.world.cvars.scriptErrors, "0")
    c:click(button(c, "PocketProbeSaveButton"))
    eq(c.reloads, 1)
    eq(c.world.cvars.scriptErrors, "1", "Save put scriptErrors back before reloading")
    eq(countLog(db, "err.hide: put back before the reload"), 1)
    c:advance(1.5)
    eq(c.world.cvars.scriptErrors, "1", "the check does not undo twice")
    -- Clean run reloads too.
    local c2, P2, db2 = new({ auto = false })
    c2:advance(5)
    c2:click(showTrial(c2, P2, "err.hide").ppRun)
    c2:click(button(c2, "PocketProbeCleanButton"))
    eq(c2.world.cvars.scriptErrors, "1")
    -- And a logout.
    local c3, P3 = new({ auto = false })
    c3:advance(5)
    c3:click(showTrial(c3, P3, "err.hide").ppRun)
    c3:fire("PLAYER_LOGOUT")
    eq(c3.world.cvars.scriptErrors, "1")
    noErrors(c); noErrors(c2); noErrors(c3)
end)

test("Run all safe ends with the two error-box trials, and the box is closed after the hook test", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    local list = P.SafeList(false)
    eq(list[#list - 1].id, "err.hook"); eq(list[#list].id, "err.hide")
    openPanel(c)
    c:click(button(c, "PocketProbeRunAllButton")); c:advance(40)
    eq(cell(db, "err.hook", KEY_PRESS), "allowed")
    check(db.last["err.hook"].message:find("box shown yes", 1, true), "the box showed for the hook test")
    eq(cell(db, "err.hide", KEY_PRESS), "allowed", "the box was closed again, so Hide could tell")
    eq(c.errorBox.shown, false)
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
