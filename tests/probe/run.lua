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
local KEY_FIGHT_PRESS = "gp=on fight=yes rest=c----- where=world trig=press"

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

    -- Probe 0.5.0. Screenshot: ClientDocumentation.lua:95 (c.shots counts the pictures taken).
    rawset(env, "Screenshot", function()
        if world.shotFails then error("no screenshot now") end
        c.shots = (c.shots or 0) + 1
    end)
    -- C_ActionBar.GetActionCooldownDuration (ActionBarFrameDocumentation.lua:181): a duration object.
    c.durations = {}
    rawset(env.C_ActionBar, "GetActionCooldownDuration", function(slot)
        if type(slot) ~= "number" or slot < 1 then error("C_ActionBar: invalid action slot " .. tostring(slot), 2) end
        if world.durationFails then error("no duration now") end
        c.durations[slot] = c.durations[slot] or { durationObject = true }
        return c.durations[slot]
    end)
    -- Cooldown frames (FrameAPICooldownDocumentation.lua; CooldownFrameTemplate starts hidden,
    -- Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3). world.cooldownModes[method] = "blocked" |
    -- "forbidden" | "error" makes that call be refused; world.noCooldown: no such frame type;
    -- world.cooldownNoObject: no SetCooldownFromDurationObject; world.cooldownStaysHidden: setting
    -- a cooldown does not show the frame.
    world.cooldownModes = {}
    c.cooldowns, c.cooldownCalls = {}, {}
    local create = env.CreateFrame
    local function Refused(method)
        local mode = world.cooldownModes[method]
        if mode == "blocked" then c:fire("ADDON_ACTION_BLOCKED", "PocketProbe", method .. "()") return true end
        if mode == "forbidden" then c:fire("ADDON_ACTION_FORBIDDEN", "PocketProbe", method .. "()") return true end
        if mode == "error" then error(method .. "(): secret values are not allowed here", 3) end
        return false
    end
    rawset(env, "CreateFrame", function(kind, name, parent, template)
        if kind ~= "Cooldown" then return create(kind, name, parent, template) end
        if world.noCooldown or template ~= "CooldownFrameTemplate" then error("CreateFrame(): Unknown frame type 'Cooldown'", 2) end
        local f = create("Frame", name, parent)
        f:Hide()
        local state = { frame = f }
        c.cooldowns[#c.cooldowns + 1] = state
        rawset(f, "SetHideCountdownNumbers", function(_, hide) state.hideNumbers = hide end)
        rawset(f, "GetCooldownDuration", function() return (state.duration or 0) * 1000 end)
        rawset(f, "SetCooldown", function(self, start, duration)
            c.cooldownCalls[#c.cooldownCalls + 1] = { frame = self, method = "SetCooldown", args = { start, duration } }
            if Refused("SetCooldown") then return end
            state.duration = duration
            if not world.cooldownStaysHidden then self:Show() end
        end)
        if not world.cooldownNoObject then
            rawset(f, "SetCooldownFromDurationObject", function(self, object)
                c.cooldownCalls[#c.cooldownCalls + 1] = { frame = self, method = "SetCooldownFromDurationObject", args = { object } }
                if Refused("SetCooldownFromDurationObject") then return end
                state.duration = 8
                if not world.cooldownStaysHidden then self:Show() end
            end)
        end
        return f
    end)
    -- The bars riding on the top anchor (PageUnit.lua:115-121): possess and stance on the anchor,
    -- shortcuts on PageUnit, all hidden. The two targeting bars are left out here (the code says
    -- they may not be there).
    local gamepadBar = rawget(env, "GamepadMainActionBarFrame")
    local pageUnit = gamepadBar and gamepadBar.PageUnit
    if pageUnit then
        local top = pageUnit.TopCenteredAnchor
        for _, spec in ipairs({ { top, "PossessBar" }, { top, "StanceBar" }, { pageUnit, "ShortcutsActionBar" } }) do
            local bar = create("Frame", nil, top)
            bar:SetSize(208, 68)
            bar:SetPoint("CENTER", top, "CENTER", 0, 0)
            bar:Hide()
            c.barParts[spec[1]][spec[2]] = bar
        end
        -- Probe 0.7.0. PageUnit's active bar: SetActiveActionBar keeps it and fires the callback
        -- registered with RegisterActiveActionBarUpdatedCallback, which calls func(owner)
        -- (PageUnit.lua:527-542, 705; CallbackRegistry.lua:112, 184). c:setActiveBar(bar) is a
        -- trigger pressed or let go; world.activeBarError makes GetActiveBar raise.
        local callbacks = {}
        c.barCallbacks = callbacks
        world.activeBar = top.Bar
        rawset(pageUnit, "RegisterActiveActionBarUpdatedCallback", function(_, fn, owner)
            if type(fn) ~= "function" then error("CallbackRegistryMixin::RegisterCallback 'func' requires function type.") end
            if type(owner) == "number" then error("'owner' as number is reserved internally.") end
            callbacks[#callbacks + 1] = { fn = fn, owner = owner }
        end)
        rawset(pageUnit, "GetActiveBar", function()
            if world.activeBarError then error("GetActiveBar failed") end
            return world.activeBar
        end)
        function c:setActiveBar(bar)
            world.activeBar = bar
            for _, cb in ipairs(callbacks) do self._protect("active bar callback", cb.fn, cb.owner) end
        end
        -- Each spell button carries the mixin's ApplyPressedStyle (ActionBarButton.lua:421, mixed in at
        -- creation: ActionBarButton.xml:4); the game calls it on a press and a release (:1111-1114).
        c.pressedStyles = 0
        for _, list in pairs(c.barButtons) do
            for _, b in ipairs(list) do
                rawset(b, "ApplyPressedStyle", function() c.pressedStyles = c.pressedStyles + 1 end)
            end
        end
        function c:pressButton(anchorKey, i, pressed)
            local b = self.barButtons[anchorKey][i]
            self._protect("press", function() b:ApplyPressedStyle(pressed) end)
        end
        -- The wheels. A spell wheel on a bar button calls PageUnit:OnFlyoutOpened(button) with the
        -- button's .popup (PageUnit.lua:719-726, ActionBarButton.lua:737-742); the popup is re-parented
        -- to UIParent and centred on the button (FlyoutRadial.lua:200-224). The two sub-menu wheels
        -- (LB+LT, RB+RT) are the frames GamepadPetActionFlyout and GamepadPetSpellFlyout
        -- (Camelot/PetClassFlyouts.xml:18, 72); their buttons are not on a bar, so they never reach
        -- PageUnit:OnFlyoutOpened (ActionBarButton.lua:738-742, set only at ActionBar.lua:34-35).
        rawset(pageUnit, "OnFlyoutOpened", function() end)
        local spellPopup = create("Frame", nil, env.UIParent)
        spellPopup:SetSize(175, 175)
        spellPopup:SetPoint("CENTER", env.UIParent, "BOTTOMLEFT", 683, 250)
        spellPopup:Hide()
        local flyoutButton = create("Button", nil, env.UIParent)
        rawset(flyoutButton, "popup", spellPopup)
        local petSpell = create("Frame", "GamepadPetSpellFlyout", env.UIParent)
        petSpell:SetSize(175, 175)
        petSpell:SetPoint("CENTER", env.UIParent, "BOTTOMLEFT", 820, 189)
        petSpell:Hide()
        rawset(env, "GamepadPetSpellFlyout", petSpell)
        local petAction = env.GamepadPetActionFlyout
        petAction:ClearAllPoints()
        petAction:SetPoint("CENTER", env.UIParent, "BOTTOMLEFT", 544, 189)
        c.wheels = { spell = spellPopup, pet = petAction, petspell = petSpell }
        function c:openWheel(kind)
            local popup = self.wheels[kind]
            popup:Show()
            if kind == "spell" then
                self._protect("OnFlyoutOpened", function() pageUnit:OnFlyoutOpened(flyoutButton) end)
            end
        end
        function c:closeWheel(kind) self.wheels[kind]:Hide() end
    end
    -- Region:GetEffectiveAlpha (SimpleFrameAPIDocumentation.lua:366): its own alpha times its parents'.
    c.typeMethods.Frame.GetEffectiveAlpha = function(self)
        local a, f = 1, self
        while f do
            a = a * (f:GetAlpha() or 1)
            f = f:GetParent()
        end
        return a
    end
    -- MinimapCluster.MinimapContainer (Minimap.xml:47); Edit Mode's map size is its scale.
    local container = create("Frame", nil, env.MinimapCluster)
    container:SetSize(200, 200)
    container:SetPoint("CENTER", env.MinimapCluster, "CENTER", 0, 0)
    container:SetScale(0.8)
    rawset(env.MinimapCluster, "MinimapContainer", container)

    -- Probe 0.7.0, the watchers: the six action bar events (ActionBarFrameDocumentation.lua:1085-1119,
    -- SpellBookDocumentation.lua:927) and the cast event (UnitDocumentation.lua:4847).
    for _, event in ipairs({ "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE",
        "ACTIONBAR_SLOT_CHANGED", "SPELL_UPDATE_COOLDOWN", "UPDATE_BONUS_ACTIONBAR", "UNIT_SPELLCAST_SUCCEEDED" }) do
        c.snapshot.event[event] = true
    end

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
        -- Guided and "info" trials (bars.park, bars.prompts) only run from the panel too,
        -- and so do the three cooldown trials (probe 0.6.0).
        if not t.id:find("^vendor%.") and t.id ~= "val.whisper" and t.area ~= "Errors" and t.area ~= "Graphics"
            and t.kind ~= "guided" and t.kind ~= "info" and not t.id:find("^cd%.") then
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
    eq(db.probe, "0.7.0")
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
        "gfx.read", "gfx.write", "gfx.names", "gfx.outlines", "gfx.icons",
        "bars.spells", "bars.alpha", "bars.park", "bars.prompts",
        "bars.fade", "bars.fadecast", "cd.duration", "cd.sweep.object", "cd.sweep.numbers" }) do
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
    "bars.move", "bars.scale", "layout.save", "bars.alpha", "bars.park", "bars.fade", "bars.fadecast" }

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
        "layout.save", "bars.alpha", "bars.fade" }) do
        eq(cell(db, id, KEY_AUTO), "allowed", id)
    end
    for _, id in ipairs({ "layout.read", "layout.sizes", "bars.protected", "bars.settings", "bars.spells", "val.position", "val.facing", "val.map", "val.questlog", "val.objectives",
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
    -- Probe 0.5.0: the map's container (its scale is the Edit Mode map size), the map, the other three bars.
    for _, part in ipairs({ "MinimapCluster.MinimapContainer w=200 h=200 scale=0.8", "Minimap w=198 h=198 scale=1",
        "LeftCenteredAnchor.Bar w=208 h=68", "RightCenteredAnchor.Bar w=208 h=68", "BottomCenteredAnchor.Bar w=208 h=68" }) do
        check(msg:find(part, 1, true), part .. ": " .. msg)
    end
    for _, part in ipairs({ "BuffFrame w=260 h=80", "DebuffFrame w=260", "ObjectiveTrackerFrame w=250 h=400",
        "MainStatusTrackingBarContainer w=800", "LeftClassAction w=40", "RightClassAction w=40",
        "GamepadPetActionFlyout w=160", "TopCenteredAnchor.Bar button 1 w=46 h=46" }) do
        check(msg:find(part, 1, true), part .. ": " .. msg)
    end
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
    eq(db.probe, "0.7.0")
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
    for _, name in ipairs({ "PocketProbeRunAllButton", "PocketProbeFightButton", "PocketProbeCleanButton", "PocketProbeRiskyButton",
        "PocketProbeVendorButton", "PocketProbeAutoButton", "PocketProbeSaveButton", "PocketProbeCloseButton" }) do
        eq(c._state(button(c, name)).parent, panel, name .. " is on the panel")
        check(not button(c, name):IsProtected(), name .. " is a plain frame")
    end
    check(not button(c, "PocketProbeNextButton"):IsShown(), "Next is hidden")
    -- Probe 0.5.0: the big message and the sweep squares are made at load too, hidden.
    for _, name in ipairs({ "PocketProbeBigMessage", "PocketProbeSweep" }) do
        local f = button(c, name)
        check(not f:IsShown(), name .. " is hidden at load")
        eq(c._state(f).type, "Frame", name .. " is a plain frame, not a button")
        check(c._state(f).mouse ~= true, name .. " takes no clicks")
        check(not c._state(f).bindings, name .. " takes no keys")
    end
    eq(#c.cooldowns, 2, "the two sweep frames are made at load")
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
                if region.GetText and region:GetText() == "Pocket Probe 0.7.0" then titleText = true end
            end
        end
    end
    check(titleText, "titled Pocket Probe 0.7.0")
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
    pad(c, "RIGHT")
    eq(P.Nav.Target(), button(c, "PocketProbeFightButton"), "Fight tests is the second footer button")
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
-- Probe 0.4.0, second round: main bar spells, fading, parking, pictures
---------------------------------------------------------------------------

-- The main bar's top anchor and its first point.
local function topAnchor(c) return c.env.GamepadMainActionBarFrame.PageUnit.TopCenteredAnchor end
local function topPoint(c)
    local point, rel, relPoint, x, y = topAnchor(c):GetPoint(1)
    return point, rel, relPoint, x, y
end

test("bars.spells counts what can be read of the main bar's 8 spells, in and out of a fight", function()
    local c, P, db = new()
    c:advance(30)
    c:enterCombat(); c:advance(30)
    noErrors(c)
    eq(cell(db, "bars.spells", KEY_AUTO), "readable")
    eq(cell(db, "bars.spells", KEY_FIGHT), "readable", "it runs in a fight too")
    local msg = db.last["bars.spells"].message
    for _, part in ipairs({ "buttons 8, with a spell 3", "slot readable 8", "has readable 8", "icon readable 3",
        "cd start readable 3", "cd duration readable 3", "count readable 3", "usable readable 3",
        "issecretvalue on this client" }) do
        check(msg:find(part, 1, true), part .. ": " .. msg)
    end
    check(not msg:find("135274", 1, true), "a texture id was saved")
    check(detail(db, "bars.spells"), "the counts are kept in a detail entry")
end)

test("bars.spells: a secret cooldown makes the result secret; an error and a missing bar are said", function()
    local c, P, db = new({ setup = function(cl) cl.world.secrets[100] = true end })
    c:advance(30)
    noErrors(c)
    eq(cell(db, "bars.spells", KEY_AUTO), "secret")
    local msg = db.last["bars.spells"].message
    check(msg:find("cd start=secret", 1, true), msg)
    check(msg:find("cd start readable 2 secret 1", 1, true), msg)
    check(msg:find("cd duration readable 3", 1, true), msg)
    local c2, P2, db2 = new({ setup = function(cl)
        rawset(cl.env.C_ActionBar, "GetActionTexture", function() error("no texture") end)
    end })
    c2:advance(30)
    noErrors(c2)
    check(db2.last["bars.spells"].message:find("icon error 3", 1, true), db2.last["bars.spells"].message)
    local c3, P3, db3 = new({ setup = function(cl) rawset(cl.env, "GamepadMainActionBarFrame", nil) end })
    c3:advance(30)
    noErrors(c3)
    eq(cell(db3, "bars.spells", KEY_AUTO), "nil")
    check(db3.last["bars.spells"].message:find("the main bar's buttons are not there", 1, true), "said")
end)

test("bars.alpha sets the left bar's see-through to its own value, out of and in a fight; a block is recorded", function()
    local c, P, db = new({ saved = riskyOn() })
    c:advance(30)
    c:enterCombat(); c:advance(30)
    noErrors(c)
    eq(cell(db, "bars.alpha", KEY_AUTO), "allowed")
    eq(cell(db, "bars.alpha", KEY_FIGHT), "allowed", "tried in a fight too")
    check(#c:callsTo("GamepadBar.LeftCenteredAnchor:SetAlpha") >= 2, "SetAlpha was called")
    -- bars.alpha only ever writes the value the bar had; the one 0 per pass is bars.fade (0.5.0).
    local zeros = 0
    for _, call in ipairs(c:callsTo("GamepadBar.LeftCenteredAnchor:SetAlpha")) do
        if call.args[1] == 0 then zeros = zeros + 1 else eq(call.args[1], 1, "always the value it already had") end
    end
    eq(zeros, 2, "bars.fade set it to nothing once in each pass")
    local c2, P2, db2 = new({ saved = riskyOn(), setup = function(cl) cl.world.barAlphaBlocked = true end })
    c2:advance(30)
    c2:enterCombat(); c2:advance(30)
    noErrors(c2)
    eq(cell(db2, "bars.alpha", KEY_AUTO), "allowed")
    eq(cell(db2, "bars.alpha", KEY_FIGHT), "blocked")
    eq(detail(db2, "bars.alpha", KEY_FIGHT).func, "SetAlpha()")
    eq(topAnchor(c2):GetAlpha(), 1)
    -- Risky off: never tried.
    local c3, P3, db3 = new()
    c3:advance(30)
    check(not db3.results["bars.alpha"], "ran with Risky off")
    eq(#c3:callsTo("GamepadBar.LeftCenteredAnchor:SetAlpha"), 0)
end)

test("bars.park: refused with Risky off or in a fight; parks the main bar, asks, then puts it back exactly", function()
    local saved = { options = { auto = false } }
    local c, P = new({ saved = saved })
    c:advance(5)
    local p1, r1, rp1, x1, y1 = topPoint(c)
    local row = showTrial(c, P, "bars.park")
    eq(row.ppRun.ppLabel:GetText(), "Start")
    check(row.ppRun.ppDisabled, "Start is dimmed while Risky is off")
    P.StartGuided(P.trialById["bars.park"])
    eq(saved.guided["bars.park"], nil, "not started with Risky off")
    check(P.status:find("risky trials are off", 1, true), P.status)
    c:click(button(c, "PocketProbeRiskyButton"))
    c:enterCombat()
    c:click(showTrial(c, P, "bars.park").ppRun)
    eq(saved.guided["bars.park"], nil, "not started in a fight")
    check(P.status:find("not started, in combat", 1, true), P.status)
    c:leaveCombat(); c:advance(2)
    -- Start: parked far above the screen (after the timed steps, see the 0.5.0 tests below).
    c:click(showTrial(c, P, "bars.park").ppRun)
    c:advance(1.7)
    local g = saved.guided["bars.park"]
    check(g and g.stage == "ask", "waiting for the answer")
    check(not rawget(c.env, "PocketProbePanel"):IsShown(), "the panel closed, so a press reaches the game")
    local p2, r2, rp2, x2, y2 = topPoint(c)
    eq(p2, p1); eq(r2, r1); eq(rp2, rp1); eq(x2, x1); eq(y2, y1 + 3000)
    check(g.notes:find("main bar off screen yes", 1, true), g.notes)
    local bar = topAnchor(c).Bar
    check(bar:GetBottom() > c.env.UIParent:GetTop(), "the bar is above the screen")
    for _, v in pairs(g) do check(type(v) ~= "table" or v == g.old, "no frame is kept in the saved table") end
    row = showTrial(c, P, "bars.park")
    eq(row.ppAnswer[1].ppLabel:GetText(), "Spell cast")
    eq(row.ppAnswer[2].ppLabel:GetText(), "Nothing happened")
    c:click(row.ppAnswer[1])
    eq(cell(saved, "bars.park", KEY_PRESS), "spell cast")
    check(saved.last["bars.park"].message:find("main bar off screen yes", 1, true), "the answer keeps the notes")
    eq(saved.guided["bars.park"], nil)
    local p3, r3, rp3, x3, y3 = topPoint(c)
    eq(p3, p1); eq(r3, r1); eq(rp3, rp1); eq(x3, x1); eq(y3, y1)
    eq(topAnchor(c):GetNumPoints(), 1)
    noErrors(c)
end)

test("bars.park: an answer in a fight leaves it parked until the fight ends; a reload calls it off", function()
    local saved = { options = { auto = false, risky = true } }
    local c, P = new({ saved = saved })
    c:advance(5)
    local _, _, _, _, y1 = topPoint(c)
    c:click(showTrial(c, P, "bars.park").ppRun)
    c:advance(1.7)
    c:enterCombat()
    local moves = #c:callsTo("GamepadBar.TopCenteredAnchor:SetPoint")
    c:click(showTrial(c, P, "bars.park").ppAnswer[2])
    eq(cell(saved, "bars.park", KEY_PRESS), nil, "recorded under the fight's situation")
    eq(#c:callsTo("GamepadBar.TopCenteredAnchor:SetPoint"), moves, "nothing moved in the fight")
    local g = saved.guided["bars.park"]
    eq(g.stage, "putback")
    check(g.held:find("the main bar", 1, true) and g.held:find("fight ends", 1, true), g.held)
    local row = showTrial(c, P, "bars.park")
    eq(row.ppChipText:GetText(), "Not put back")
    c:leaveCombat(); c:advance(2)
    eq(saved.guided["bars.park"], nil, "put back after the fight")
    eq(select(5, topPoint(c)), y1)
    eq(countLog(saved, "bars.park: put back after the fight"), 1)
    noErrors(c)
    -- Waiting when the interface reloads: the reload puts the bar back; the trial is called off.
    local c2, P2 = new({ saved = saved })
    c2:advance(5)
    c2:click(showTrial(c2, P2, "bars.park").ppRun)
    c2:advance(1.7)
    check(saved.guided["bars.park"], "waiting")
    c2:enterCombat()
    c2:fire("PLAYER_LOGOUT")
    local c3 = new({ saved = saved })
    eq(saved.guided["bars.park"], nil)
    eq(countLog(saved, "bars.park: called off; the reload put the main bar back"), 1)
    noErrors(c3)
end)

test("bars.park: two anchor points are left alone; a spot the game set meanwhile is kept", function()
    local saved = { options = { auto = false, risky = true } }
    local c, P = new({ saved = saved, setup = function(cl)
        cl.env.GamepadMainActionBarFrame.PageUnit.TopCenteredAnchor:SetPoint("TOP", cl.env.UIParent, "TOP", 0, 0)
    end })
    c:advance(5)
    c:click(showTrial(c, P, "bars.park").ppRun)
    c:advance(1.7)
    eq(saved.guided["bars.park"], nil, "nothing to ask")
    eq(cell(saved, "bars.park", KEY_PRESS), "no effect")
    check(saved.last["bars.park"].message:find("more than one anchor point", 1, true), saved.last["bars.park"].message)
    eq(#c:callsTo("GamepadBar.TopCenteredAnchor:ClearAllPoints"), 0)
    noErrors(c)
    local saved2 = { options = { auto = false, risky = true } }
    local c2, P2 = new({ saved = saved2 })
    c2:advance(5)
    c2:click(showTrial(c2, P2, "bars.park").ppRun)
    c2:advance(1.7)
    local anchor = topAnchor(c2)
    local pageUnit = c2.env.GamepadMainActionBarFrame.PageUnit
    anchor:ClearAllPoints(); anchor:SetPoint("CENTER", pageUnit, "CENTER", 0, 99)
    c2:click(showTrial(c2, P2, "bars.park").ppAnswer[1])
    eq(select(5, topPoint(c2)), 99, "the game's spot is kept")
    eq(saved2.guided["bars.park"], nil)
    check(saved2.last["bars.park"].message:find("left where the game had put it since", 1, true), saved2.last["bars.park"].message)
    noErrors(c2)
    -- Left with no point at all: put back.
    local saved3 = { options = { auto = false, risky = true } }
    local c3, P3 = new({ saved = saved3 })
    c3:advance(5)
    local _, _, _, _, y0 = topPoint(c3)
    c3:click(showTrial(c3, P3, "bars.park").ppRun)
    c3:advance(1.7)
    topAnchor(c3):ClearAllPoints()
    c3:click(showTrial(c3, P3, "bars.park").ppRun)
    eq(saved3.guided["bars.park"], nil)
    eq(select(5, topPoint(c3)), y0)
    noErrors(c3)
end)

test("bars.prompts reads the 8 button pictures and shows them on a texture of ours", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    c:click(showTrial(c, P, "bars.prompts").ppRun)
    noErrors(c)
    eq(cell(db, "bars.prompts", KEY_PRESS), "8 of 8 copied · Xbox")
    local msg = db.last["bars.prompts"].message
    for _, part in ipairs({ "icon set Xbox", "1 PADDLEFT=gamepad-xbox-PADDLEFT", "5 PAD3=gamepad-xbox-PAD3",
        "8 PAD1=gamepad-xbox-PAD1", "same picture for 8 of 8" }) do
        check(msg:find(part, 1, true), part .. ": " .. msg)
    end
    local c2, P2, db2 = new({ auto = false, setup = function(cl)
        rawset(cl.env, "InputDeviceIconSetManager", nil)
        rawset(cl.env, "InputIconTextureSetUtility", nil)
    end })
    c2:advance(5)
    c2:click(showTrial(c2, P2, "bars.prompts").ppRun)
    noErrors(c2)
    eq(cell(db2, "bars.prompts", KEY_PRESS), "8 of 8 copied")
    check(db2.last["bars.prompts"].message:find("icon set unknown", 1, true), "said")
    check(db2.last["bars.prompts"].message:find("same picture for 0 of 8", 1, true), "said")
    local c3, P3, db3 = new({ auto = false, setup = function(cl) rawset(cl.env, "GamepadMainActionBarFrame", nil) end })
    c3:advance(5)
    c3:click(showTrial(c3, P3, "bars.prompts").ppRun)
    noErrors(c3)
    eq(cell(db3, "bars.prompts", KEY_PRESS), "missing")
end)


---------------------------------------------------------------------------
-- Probe 0.5.0: the Fight tests button, the big message, the clearer park
-- test, the fade tests, the cooldown sweep
---------------------------------------------------------------------------

local PARK_BIG = "Main bar parked. Press a spell, then tap Probe."
local FADE_BIG = "Main bar is invisible. Press a spell, then tap Probe."

-- The text on one of our frames while it shows, or nil while it is hidden.
local function shownText(c, name)
    local f = button(c, name)
    if not f:IsShown() then return nil end
    local texts = {}
    for _, rec in ipairs(c:frames()) do
        if rec.frame == f then
            for _, region in ipairs(rec.regions or {}) do
                local t = region.GetText and region:GetText()
                if type(t) == "string" and t ~= "" then texts[#texts + 1] = t end
            end
        end
    end
    return table.concat(texts, "|")
end

local function ids(list)
    local out, at = {}, {}
    for i, t in ipairs(list) do out[i], at[t.id] = t.id, i end
    return out, at
end

local function riskySaved() return { options = { auto = false, risky = true } } end

test("Fight tests: second in the footer; out of a fight it only says to start one", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    openPanel(c)
    local b = button(c, "PocketProbeFightButton")
    eq(b.ppLabel:GetText(), "Fight tests")
    eq(P.panelFooter[1], button(c, "PocketProbeRunAllButton"))
    eq(P.panelFooter[2], b, "placed second, after Run all safe")
    eq(#P.panelFooter, 7)
    local _, _, panelTop, panelBottom = c._rect(button(c, "PocketProbePanel"))
    local left, right = c._rect(button(c, "PocketProbePanel"))
    for _, f in ipairs(P.panelFooter) do
        local l, r, top, bottom = c._rect(f)
        check(l >= left and r <= right and top <= panelTop and bottom >= panelBottom, "a footer button is outside the panel")
    end
    c:click(b)
    eq(P.status, "Fight tests: start a fight first, then tap this.")
    c:advance(10)
    eq(next(db.results), nil, "nothing ran")
    eq(countLog(db, "pass started"), 0)
    noErrors(c)
end)

test("Fight tests: the list has the fight trials first and nothing known to be refused in a fight", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    local list, at = ids(P.FightList())
    eq(table.concat(list, " ", 1, 4), "bars.spells cd.duration cd.sweep.object cd.sweep.numbers", "the fight trials come first, in file order")
    for _, t in ipairs(P.FightList()) do
        check(not t.noFight, t.id .. " is marked noFight")
        check(not t.last, t.id .. " raises a test error")
        check(not t.manual or t.fight, t.id .. " is a manual trial")
        check(not t.vendor, t.id .. " is a vendor trial")
        check(not t.risky, t.id .. " is risky and Risky is off")
        check(t.kind ~= "guided" and not t.event, t.id .. " cannot run in a pass")
    end
    for _, id in ipairs({ "pad.bind", "pad.mark", "err.hook", "err.hide", "err.handler", "gfx.read", "bars.prompts",
        "vendor.sell1", "chat.open", "bag.toggle", "bars.alpha", "bars.fade", "bars.park", "bars.fadecast" }) do
        check(not at[id], id .. " is in the fight list")
    end
    for _, id in ipairs({ "own.show", "chat.type", "cvar.write", "layout.read", "layout.sizes", "val.money" }) do
        check(at[id] and at[id] > 4, id .. " is in the rest of the list")
    end
    local seen = {}
    for _, id in ipairs(list) do
        check(not seen[id], id .. " is in the list twice")
        seen[id] = true
    end
    -- Run all safe is unchanged: it still runs the two controller trials.
    local _, safe = ids(P.SafeList(false))
    check(safe["pad.bind"] and safe["pad.mark"], "Run all safe lost the controller trials")
    -- Risky on: the risky fight trials come last.
    local c2, P2 = new({ saved = riskySaved() })
    c2:advance(5)
    local list2 = ids(P2.FightList())
    eq(list2[#list2 - 1], "bars.alpha"); eq(list2[#list2], "bars.fade")
    eq(#list2, #list + 2, "only the two risky fight trials are added")
    noErrors(c); noErrors(c2)
end)

test("Fight tests in a fight: starts inside the tap, says what ran, and the summary counts right", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    openPanel(c)
    c:enterCombat(); c:advance(2)
    c:click(button(c, "PocketProbeFightButton"))
    eq(cell(db, "bars.spells", KEY_FIGHT_PRESS), "readable", "the first trial ran inside the tap")
    eq(countLog(db, "bars.spells: readable (straight from the press)"), 1)
    check(P.status:find("^pass 1/%d+ bars.spells"), "status while running: " .. tostring(P.status))
    check(not cell(db, "cd.duration", KEY_FIGHT_PRESS), "the rest waits for the timers")
    c:advance(40)
    noErrors(c)
    eq(db.situations[KEY_FIGHT_PRESS].trigger, "press")
    for _, id in ipairs({ "pad.bind", "pad.mark", "bars.alpha", "bars.fade", "err.hook" }) do
        check(not db.results[id], id .. " ran in the fight tests")
    end
    eq(cell(db, "cd.sweep.object", KEY_FIGHT_PRESS), "allowed")
    eq(cell(db, "own.show", KEY_FIGHT_PRESS), "allowed")
    -- One log line with every trial and its result; the status counts them.
    local line
    for _, l in ipairs(db.log) do
        if l:find("fight tests: ", 1, true) and not l:find("pass started", 1, true) then line = l end
    end
    check(line, "no log line with the results")
    local run, good, refused = 0, 0, 0
    for _, t in ipairs(P.FightList()) do
        local result = line:match(" " .. t.id:gsub("%.", "%%.") .. " ([^,]+)")
        check(result, t.id .. " is not in the log line: " .. line)
        if result ~= "not tried" then
            run = run + 1
            eq(result, tostring(db.last[t.id].result), t.id)
            if result == "allowed" or result == "readable" then good = good + 1 end
            if result == "blocked" or result == "forbidden" or result == "error" then refused = refused + 1 end
        end
    end
    check(run > 20 and good > 15, "run " .. run .. ", good " .. good)
    eq(P.status, "Fight tests done: " .. run .. " run, " .. good .. " allowed or readable, " .. refused .. " refused")
    -- A trial the game refuses is counted as refused.
    local c2, P2, db2 = new({ auto = false, setup = function(cl) cl.world.cooldownModes.SetCooldown = "blocked" end })
    c2:advance(5)
    c2:enterCombat(); c2:advance(2)
    P2.RunFightTests(); c2:advance(40)
    noErrors(c2)
    eq(cell(db2, "cd.sweep.numbers", KEY_FIGHT_PRESS), "blocked")
    check(P2.status:find(", 1 refused$"), P2.status)
    -- Risky on: the two fades run too, last.
    local c3, P3, db3 = new({ saved = riskySaved() })
    c3:advance(5)
    c3:enterCombat(); c3:advance(2)
    P3.RunFightTests(); c3:advance(40)
    noErrors(c3)
    eq(cell(db3, "bars.alpha", KEY_FIGHT_PRESS), "allowed")
    eq(cell(db3, "bars.fade", KEY_FIGHT_PRESS), "allowed")
    check(logAt(db3, "bars.fade: ") > logAt(db3, "val.name.target: "), "the risky fight trials run last")
end)

test("Fight tests: the fight ending part-way stops the pass and the status says how many ran", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    c:enterCombat(); c:advance(2)
    P.RunFightTests()
    c:advance(1)
    c:leaveCombat(); c:advance(3)
    noErrors(c)
    local n = tonumber(P.status:match("^Fight tests stopped, the fight ended: (%d+) run, %d+ allowed or readable, %d+ refused$"))
    check(n and n >= 2 and n <= 6, "status: " .. tostring(P.status))
    eq(countLog(db, "fight tests stopped, the fight ended: "), 1)
    local logged = countLog(db, ": ")
    c:advance(20)
    eq(countLog(db, ": "), logged, "nothing runs after the fight")
end)

test("bars.park 0.5.0: closes the panel, takes a picture, parks, takes a picture, then shows the big message", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    local _, _, _, _, y1 = topPoint(c)
    eq(shownText(c, "PocketProbeBigMessage"), nil)
    c:click(showTrial(c, P, "bars.park").ppRun)
    check(not rawget(c.env, "PocketProbePanel"):IsShown(), "the panel closes at Start")
    eq(saved.guided["bars.park"].stage, "prepare")
    eq(c.shots, nil); eq(select(5, topPoint(c)), y1)
    c:advance(0.6)
    eq(c.shots, 1, "the first picture, before parking")
    eq(select(5, topPoint(c)), y1, "not parked yet")
    c:advance(0.5)
    eq(select(5, topPoint(c)), y1 + 3000, "parked")
    eq(c.shots, 1)
    eq(shownText(c, "PocketProbeBigMessage"), nil, "the message waits for the second picture")
    eq(saved.guided["bars.park"].stage, "prepare")
    c:advance(0.5)
    eq(c.shots, 2, "the second picture, parked")
    eq(shownText(c, "PocketProbeBigMessage"), PARK_BIG)
    local g = saved.guided["bars.park"]
    eq(g.stage, "ask")
    eq(P.status, "bars.park: started — Park the main bar is waiting: answer or Cancel")
    -- The bars snapshot, before and after, and the pictures taken.
    local before, after = g.notes:match("before: (.-); after: (.-), screenshots")
    check(before and after, g.notes)
    check(before:find("^top shown %d+,%d+ on screen; left shown %d+,%d+ on screen; right shown %d+,%d+ on screen; bottom shown"), before)
    check(before:find("possess hidden %d+,%d+ on screen; stance hidden", 1) and before:find("shortcuts hidden", 1, true), before)
    check(before:find("friendly missing; hostile missing", 1, true), before)
    check(before:find("bars shown and on screen: 4", 1, true), before)
    check(after:find("^top shown %d+,%d+ off screen; left shown %d+,%d+ on screen"), after)
    check(after:find("possess hidden %d+,%d+ off screen", 1), after)
    check(after:find("bars shown and on screen: 3", 1, true), after)
    check(g.notes:find("screenshots: 2", 1, true), g.notes)
    -- The answer keeps all of it; the message goes away and the bar goes back.
    local row = showTrial(c, P, "bars.park")
    eq(row.ppAnswer[1].ppLabel:GetText(), "Spell cast"); eq(row.ppAnswer[2].ppLabel:GetText(), "Nothing happened")
    c:click(row.ppAnswer[2])
    eq(cell(saved, "bars.park", KEY_PRESS), "nothing happened")
    local msg = saved.last["bars.park"].message
    for _, part in ipairs({ "before: top shown", "after: top shown", "bars shown and on screen: 3", "screenshots: 2", "old values put back" }) do
        check(msg:find(part, 1, true), part .. ": " .. msg)
    end
    eq(shownText(c, "PocketProbeBigMessage"), nil, "hidden on the answer")
    eq(select(5, topPoint(c)), y1)
    noErrors(c)
end)

test("bars.park 0.5.0: a fight before the park moves nothing; Cancel and Stop in the first second call it off", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    local _, _, _, _, y1 = topPoint(c)
    c:click(showTrial(c, P, "bars.park").ppRun)
    c:advance(0.6)
    c:enterCombat()
    c:advance(2)
    noErrors(c)
    eq(#c:callsTo("GamepadBar.TopCenteredAnchor:SetPoint"), 0, "nothing moved")
    eq(saved.guided["bars.park"], nil)
    eq(saved.results["bars.park"], nil, "not tried: nothing saved")
    eq(countLog(saved, "bars.park: not tried, in combat"), 1)
    check(P.status:find("bars.park: not tried, in combat", 1, true), P.status)
    eq(shownText(c, "PocketProbeBigMessage"), nil)
    eq(c.shots, 1, "only the first picture")
    c:leaveCombat(); c:advance(2)
    -- Cancel before the park.
    c:click(showTrial(c, P, "bars.park").ppRun)
    c:advance(0.6)
    local row = showTrial(c, P, "bars.park")
    eq(row.ppRun.ppLabel:GetText(), "Cancel"); eq(row.ppChipText:GetText(), "Waiting")
    check(not row.ppAnswer[1]:IsShown(), "no answers before the question")
    c:click(row.ppRun)
    eq(saved.guided["bars.park"], nil)
    c:advance(3)
    eq(#c:callsTo("GamepadBar.TopCenteredAnchor:SetPoint"), 0, "nothing moved after Cancel")
    eq(shownText(c, "PocketProbeBigMessage"), nil)
    -- Stop before the park.
    P.StartGuided(P.trialById["bars.park"])
    c:advance(0.6)
    P.Stop()
    c:advance(3)
    eq(#c:callsTo("GamepadBar.TopCenteredAnchor:SetPoint"), 0, "nothing moved after Stop")
    eq(select(5, topPoint(c)), y1)
    noErrors(c)
end)

test("bars.park 0.5.0: the message hides on Cancel, Stop and logout; no Screenshot changes nothing else", function()
    for _, way in ipairs({ "cancel", "stop", "logout" }) do
        local saved = riskySaved()
        local c, P = new({ saved = saved })
        c:advance(5)
        local _, _, _, _, y1 = topPoint(c)
        P.StartGuided(P.trialById["bars.park"]); c:advance(1.7)
        eq(shownText(c, "PocketProbeBigMessage"), PARK_BIG, way)
        if way == "cancel" then P.CancelGuided(P.trialById["bars.park"])
        elseif way == "stop" then P.Stop()
        else c:fire("PLAYER_LOGOUT") end
        eq(shownText(c, "PocketProbeBigMessage"), nil, "hidden on " .. way)
        eq(saved.guided["bars.park"], nil, way)
        eq(select(5, topPoint(c)), y1, "put back on " .. way)
        noErrors(c, way)
    end
    -- No Screenshot on this client, or one that raises: the rest is the same.
    for _, how in ipairs({ "missing", "raises" }) do
        local saved = riskySaved()
        local c, P = new({ saved = saved, setup = function(cl)
            if how == "missing" then rawset(cl.env, "Screenshot", nil) else cl.world.shotFails = true end
        end })
        c:advance(5)
        local _, _, _, _, y1 = topPoint(c)
        P.StartGuided(P.trialById["bars.park"]); c:advance(1.7)
        local g = saved.guided["bars.park"]
        eq(g and g.stage, "ask", how)
        eq(select(5, topPoint(c)), y1 + 3000, how)
        eq(shownText(c, "PocketProbeBigMessage"), PARK_BIG, how)
        check(g.notes:find(how == "missing" and "screenshots: none (not on this client)" or "screenshots: none (the call failed)", 1, true), g.notes)
        P.AnswerGuided(P.trialById["bars.park"], 1)
        eq(cell(saved, "bars.park", KEY_PRESS), "spell cast", how)
        eq(select(5, topPoint(c)), y1, how)
        noErrors(c, how)
    end
    -- An answer in a fight: the bar stays parked until the fight ends, but the message goes.
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    P.StartGuided(P.trialById["bars.park"]); c:advance(1.7)
    c:enterCombat()
    P.AnswerGuided(P.trialById["bars.park"], 1)
    eq(saved.guided["bars.park"].stage, "putback")
    eq(shownText(c, "PocketProbeBigMessage"), nil, "hidden once answered, though the bar is still held")
    noErrors(c)
end)

local function mainBar(c) return topAnchor(c).Bar end

test("bars.fadecast: fades the main bar to nothing, asks, notes 'still invisible', and puts the old value back", function()
    local saved = { options = { auto = false } }
    local c, P = new({ saved = saved })
    c:advance(5)
    local row = showTrial(c, P, "bars.fadecast")
    eq(row.ppLabel:GetText(), "Fade the main bar to nothing, then press a spell button (risky)")
    eq(row.ppRun.ppLabel:GetText(), "Start")
    check(row.ppRun.ppDisabled, "Start is dimmed while Risky is off")
    c:click(button(c, "PocketProbeRiskyButton"))
    c:click(showTrial(c, P, "bars.fadecast").ppRun)
    check(not rawget(c.env, "PocketProbePanel"):IsShown(), "the panel closes at Start")
    eq(mainBar(c):GetAlpha(), 1, "not faded yet")
    c:advance(0.6); eq(c.shots, 1)
    c:advance(0.5); eq(mainBar(c):GetAlpha(), 0, "faded")
    eq(shownText(c, "PocketProbeBigMessage"), nil)
    c:advance(0.5); eq(c.shots, 2)
    eq(shownText(c, "PocketProbeBigMessage"), FADE_BIG)
    local g = saved.guided["bars.fadecast"]
    eq(g.stage, "ask")
    check(g.notes:find("main bar see-through 1 -> 0", 1, true) and g.notes:find("screenshots: 2", 1, true), g.notes)
    eq(P.status, "bars.fadecast: started — Fade the main bar is waiting: answer or Cancel")
    for _, v in pairs(g) do check(type(v) ~= "table" or v == g.old, "no frame is kept in the saved table") end
    row = showTrial(c, P, "bars.fadecast")
    eq(row.ppAnswer[1].ppLabel:GetText(), "Spell cast"); eq(row.ppAnswer[2].ppLabel:GetText(), "Nothing happened")
    c:click(row.ppAnswer[1])
    eq(cell(saved, "bars.fadecast", KEY_PRESS), "spell cast")
    local msg = saved.last["bars.fadecast"].message
    check(msg:find("still invisible at the answer: yes", 1, true), msg)
    check(msg:find("old values put back", 1, true), msg)
    eq(mainBar(c):GetAlpha(), 1, "put back")
    eq(saved.guided["bars.fadecast"], nil)
    eq(shownText(c, "PocketProbeBigMessage"), nil)
    -- The game showed the bar again by itself before the answer: noted, and the old value still goes back.
    P.StartGuided(P.trialById["bars.fadecast"]); c:advance(1.7)
    mainBar(c):SetAlpha(0.5)
    P.AnswerGuided(P.trialById["bars.fadecast"], 2)
    eq(saved.last["bars.fadecast"].result, "nothing happened")
    check(saved.last["bars.fadecast"].message:find("still invisible at the answer: no", 1, true), saved.last["bars.fadecast"].message)
    eq(mainBar(c):GetAlpha(), 1)
    noErrors(c)
end)

test("bars.fadecast: Cancel, Stop and logout put the see-through back; a start in a fight is allowed", function()
    for _, way in ipairs({ "cancel", "stop", "logout", "cancel early" }) do
        local saved = riskySaved()
        local c, P = new({ saved = saved })
        c:advance(5)
        P.StartGuided(P.trialById["bars.fadecast"])
        c:advance(way == "cancel early" and 0.6 or 1.7)
        if way ~= "cancel early" then
            eq(mainBar(c):GetAlpha(), 0, way)
            eq(shownText(c, "PocketProbeBigMessage"), FADE_BIG, way)
        end
        if way == "stop" then P.Stop()
        elseif way == "logout" then c:fire("PLAYER_LOGOUT")
        else P.CancelGuided(P.trialById["bars.fadecast"]) end
        c:advance(3)
        eq(mainBar(c):GetAlpha(), 1, "put back on " .. way)
        eq(saved.guided["bars.fadecast"], nil, way)
        eq(saved.results["bars.fadecast"], nil, way .. ": no answer")
        eq(shownText(c, "PocketProbeBigMessage"), nil, way)
        if way == "logout" then eq(countLog(saved, "bars.fadecast: put back at logout"), 1) end
        noErrors(c, way)
    end
    -- In a fight: started, faded, answered and put back, all in the fight.
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    c:enterCombat(); c:advance(2)
    P.StartGuided(P.trialById["bars.fadecast"]); c:advance(1.7)
    eq(mainBar(c):GetAlpha(), 0, "faded in the fight")
    P.AnswerGuided(P.trialById["bars.fadecast"], 1)
    eq(cell(saved, "bars.fadecast", KEY_FIGHT_PRESS), "spell cast")
    eq(mainBar(c):GetAlpha(), 1)
    noErrors(c)
    -- A reload while it waits: the trial is called off (the reload resets the bar).
    local saved2 = riskySaved()
    local c2, P2 = new({ saved = saved2 })
    c2:advance(5)
    P2.StartGuided(P2.trialById["bars.fadecast"]); c2:advance(1.7)
    saved2.guided["bars.fadecast"].applied = true      -- as if the logout could not put it back
    local c3 = new({ saved = saved2 })
    eq(saved2.guided["bars.fadecast"], nil)
    eq(countLog(saved2, "bars.fadecast: called off; the reload put the main bar's see-through back"), 1)
    noErrors(c3)
end)

test("bars.fadecast: a refused fade is the result at once; a refused put-back is held until the fight ends", function()
    -- The game refuses the fade in a fight: stored as the result, nothing asked, nothing left changed.
    local saved = riskySaved()
    local c, P = new({ saved = saved, setup = function(cl) cl.world.barAlphaBlocked = true end })
    c:advance(5)
    c:enterCombat(); c:advance(2)
    P.StartGuided(P.trialById["bars.fadecast"]); c:advance(1.7)
    noErrors(c)
    eq(cell(saved, "bars.fadecast", KEY_FIGHT_PRESS), "blocked")
    eq(detail(saved, "bars.fadecast").func, "SetAlpha()")
    eq(saved.guided["bars.fadecast"], nil, "nothing to ask")
    eq(mainBar(c):GetAlpha(), 1)
    eq(shownText(c, "PocketProbeBigMessage"), nil)
    check(P.status:find("bars.fadecast: blocked", 1, true), P.status)
    -- The write does nothing and says nothing: "no effect".
    local saved2 = riskySaved()
    local c2, P2 = new({ saved = saved2, setup = function(cl)
        rawset(cl.env.GamepadMainActionBarFrame.PageUnit.TopCenteredAnchor.Bar, "SetAlpha", function() end)
    end })
    c2:advance(5)
    P2.StartGuided(P2.trialById["bars.fadecast"]); c2:advance(1.7)
    eq(cell(saved2, "bars.fadecast", KEY_PRESS), "no effect")
    check(saved2.last["bars.fadecast"].message:find("still 1 after setting it to 0", 1, true), saved2.last["bars.fadecast"].message)
    eq(saved2.guided["bars.fadecast"], nil)
    noErrors(c2)
    -- Faded out of a fight; the put-back is refused in the fight and done when it ends.
    local saved3 = riskySaved()
    local c3, P3 = new({ saved = saved3 })
    c3:advance(5)
    P3.StartGuided(P3.trialById["bars.fadecast"]); c3:advance(1.7)
    c3.world.barAlphaBlocked = true
    c3:enterCombat()
    P3.AnswerGuided(P3.trialById["bars.fadecast"], 1)
    eq(cell(saved3, "bars.fadecast", KEY_FIGHT_PRESS), "spell cast", "the answer is kept")
    local g = saved3.guided["bars.fadecast"]
    eq(g and g.stage, "putback")
    check(g.held:find("the main bar's see-through", 1, true), g.held)
    eq(mainBar(c3):GetAlpha(), 0, "still faded in the fight")
    eq(showTrial(c3, P3, "bars.fadecast").ppChipText:GetText(), "Not put back")
    eq(shownText(c3, "PocketProbeBigMessage"), nil)
    c3:leaveCombat(); c3:advance(2)
    eq(saved3.guided["bars.fadecast"], nil, "put back after the fight")
    eq(mainBar(c3):GetAlpha(), 1)
    eq(countLog(saved3, "bars.fadecast: put back after the fight"), 1)
    noErrors(c3)
    -- No main bar on this client.
    local saved4 = riskySaved()
    local c4, P4 = new({ saved = saved4, setup = function(cl) rawset(cl.env, "GamepadMainActionBarFrame", nil) end })
    c4:advance(5)
    P4.StartGuided(P4.trialById["bars.fadecast"]); c4:advance(1.7)
    eq(cell(saved4, "bars.fadecast", KEY_PRESS), "missing")
    noErrors(c4)
end)

test("bars.fade: the left bar to nothing and back; no change is 'no effect'; a block is recorded; always undone", function()
    local c, P, db = new({ saved = riskySaved() })
    c:advance(5)
    local row = showTrial(c, P, "bars.fade")
    eq(row.ppLabel:GetText(), "Fade the left bar to nothing and back (run it in a fight) (risky)")
    c:click(row.ppRun)
    eq(cell(db, "bars.fade", KEY_PRESS), "allowed")
    local calls = c:callsTo("GamepadBar.LeftCenteredAnchor:SetAlpha")
    eq(#calls, 2); eq(calls[1].args[1], 0, "set to nothing"); eq(calls[2].args[1], 1, "and back")
    local left = c.env.GamepadMainActionBarFrame.PageUnit.LeftCenteredAnchor
    eq(left:GetAlpha(), 1)
    -- In a fight too.
    c:enterCombat(); c:advance(2)
    c:click(showTrial(c, P, "bars.fade").ppRun)
    eq(cell(db, "bars.fade", KEY_FIGHT_PRESS), "allowed")
    eq(left:GetAlpha(), 1)
    noErrors(c)
    -- Refused in a fight: blocked, and the bar is as it was.
    local c2, P2, db2 = new({ saved = riskySaved(), setup = function(cl) cl.world.barAlphaBlocked = true end })
    c2:advance(5)
    c2:enterCombat(); c2:advance(2)
    P2.RunOne(P2.trialById["bars.fade"])
    eq(cell(db2, "bars.fade", KEY_FIGHT_PRESS), "blocked")
    eq(detail(db2, "bars.fade").func, "SetAlpha()")
    eq(c2.env.GamepadMainActionBarFrame.PageUnit.LeftCenteredAnchor:GetAlpha(), 1)
    noErrors(c2)
    -- A write that changes nothing.
    local c3, P3, db3 = new({ saved = riskySaved(), setup = function(cl)
        rawset(cl.env.GamepadMainActionBarFrame.PageUnit.LeftCenteredAnchor, "SetAlpha", function() end)
    end })
    c3:advance(5)
    P3.RunOne(P3.trialById["bars.fade"])
    eq(cell(db3, "bars.fade", KEY_PRESS), "no effect")
    noErrors(c3)
    -- A half-faded bar goes back to its own value, not to 1.
    local c4, P4, db4 = new({ saved = riskySaved(), setup = function(cl)
        cl.env.GamepadMainActionBarFrame.PageUnit.LeftCenteredAnchor:SetAlpha(0.5)
    end })
    c4:advance(5)
    P4.RunOne(P4.trialById["bars.fade"])
    eq(cell(db4, "bars.fade", KEY_PRESS), "allowed")
    eq(c4.env.GamepadMainActionBarFrame.PageUnit.LeftCenteredAnchor:GetAlpha(), 0.5)
    noErrors(c4)
end)

test("cd.duration counts what can be read of the main bar's cooldown duration objects", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    P.RunOne(P.trialById["cd.duration"])
    eq(cell(db, "cd.duration", KEY_PRESS), "readable")
    local msg = db.last["cd.duration"].message
    check(msg:find("buttons 8, with a spell 3", 1, true) and msg:find("duration readable 3", 1, true), msg)
    local c2, P2, db2 = new({ auto = false, setup = function(cl) cl.world.durationFails = true end })
    c2:advance(5)
    P2.RunOne(P2.trialById["cd.duration"])
    eq(cell(db2, "cd.duration", KEY_PRESS), "nil")
    check(db2.last["cd.duration"].message:find("duration error 3", 1, true), db2.last["cd.duration"].message)
    local c3, P3, db3 = new({ auto = false, setup = function(cl) rawset(cl.env.C_ActionBar, "GetActionCooldownDuration", nil) end })
    c3:advance(5)
    P3.RunOne(P3.trialById["cd.duration"])
    P3.RunOne(P3.trialById["cd.sweep.object"])
    eq(cell(db3, "cd.duration", KEY_PRESS), "missing")
    eq(cell(db3, "cd.sweep.object", KEY_PRESS), "missing")
    noErrors(c); noErrors(c2); noErrors(c3)
end)

test("the sweep trials: allowed, with the slot on cooldown preferred; the squares show for 8 seconds, one picture", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    local holder = button(c, "PocketProbeSweep")
    eq(c.cooldowns[1].hideNumbers, true, "no countdown numbers on square 1")
    eq(c.cooldowns[2].hideNumbers, true, "no countdown numbers on square 2")
    local row = showTrial(c, P, "cd.sweep.object")
    eq(row.ppLabel:GetText(), "Cooldown sweep on a square of ours, from the game's duration object")
    eq(row.ppRun.ppDisabled, false, "not risky")
    c:click(row.ppRun)
    eq(cell(db, "cd.sweep.object", KEY_PRESS), "allowed")
    local msg = db.last["cd.sweep.object"].message
    for _, part in ipairs({ "slot on cooldown yes", "sweep frame shown by itself yes", "duration afterwards readable" }) do
        check(msg:find(part, 1, true), part .. ": " .. msg)
    end
    eq(#c.cooldownCalls, 1)
    eq(c.cooldownCalls[1].frame, c.cooldowns[1].frame, "square 1")
    eq(c.cooldownCalls[1].args[1], c.durations[2], "the game's duration object of the slot on cooldown, passed straight in")
    check(holder:IsShown(), "the squares show")
    eq(c.shots, nil)
    c:advance(1.1)
    eq(c.shots, 1, "one picture a second later")
    -- The numbers trial on square 2, five seconds on: the 8 seconds start again.
    c:advance(4)
    P.RunOne(P.trialById["cd.sweep.numbers"])
    eq(cell(db, "cd.sweep.numbers", KEY_PRESS), "allowed")
    eq(c.cooldownCalls[2].frame, c.cooldowns[2].frame, "square 2")
    eq(c.cooldownCalls[2].method, "SetCooldown")
    eq(c.cooldownCalls[2].args[1], 100); eq(c.cooldownCalls[2].args[2], 8)
    c:advance(4)
    check(holder:IsShown(), "a second run restarts the 8 seconds")
    c:advance(4.5)
    check(not holder:IsShown(), "hidden 8 seconds after the last run")
    eq(c.shots, 1, "no second picture while it was already showing")
    noErrors(c)
    -- Nothing read from the game is stored: no texture, no start time.
    local text = table.concat(dump(db), "\n")
    for _, value in ipairs({ "135274", "136096", "135952" }) do
        check(not text:find(value, 1, true), "a texture id was saved: " .. value)
    end
    check(not db.last["cd.sweep.numbers"].message:find("100", 1, true), "a start time was saved")
    -- No slot on cooldown: the first with a spell; a frame that does not show itself is shown by us.
    local c2, P2, db2 = new({ auto = false, setup = function(cl)
        cl.world.actions[2].duration = 0
        cl.world.cooldownStaysHidden = true
    end })
    c2:advance(5)
    P2.RunOne(P2.trialById["cd.sweep.object"])
    eq(cell(db2, "cd.sweep.object", KEY_PRESS), "allowed")
    msg = db2.last["cd.sweep.object"].message
    check(msg:find("slot on cooldown no", 1, true) and msg:find("sweep frame shown by itself no", 1, true), msg)
    eq(c2.cooldownCalls[1].args[1], c2.durations[1], "the first slot with a spell")
    check(c2.cooldowns[1].frame:IsShown(), "shown by the probe so a sweep could be seen")
    noErrors(c2)
    -- No spell on the main bar: nothing to try.
    local c3, P3, db3 = new({ auto = false, setup = function(cl) cl.world.actions = {} end })
    c3:advance(5)
    P3.RunOne(P3.trialById["cd.sweep.object"]); P3.RunOne(P3.trialById["cd.sweep.numbers"])
    eq(cell(db3, "cd.sweep.object", KEY_PRESS), "no effect")
    eq(cell(db3, "cd.sweep.numbers", KEY_PRESS), "no effect")
    eq(#c3.cooldownCalls, 0)
    noErrors(c3)
end)

test("the sweep trials: blocked, forbidden and error are told apart; a missing method or frame is 'missing'", function()
    for _, mode in ipairs({ "blocked", "forbidden", "error" }) do
        local c, P, db = new({ auto = false, setup = function(cl)
            cl.world.cooldownModes.SetCooldownFromDurationObject = mode
            cl.world.cooldownModes.SetCooldown = mode
        end })
        c:advance(5)
        c:enterCombat(); c:advance(2)
        P.RunOne(P.trialById["cd.sweep.object"]); P.RunOne(P.trialById["cd.sweep.numbers"])
        noErrors(c, mode)
        eq(cell(db, "cd.sweep.object", KEY_FIGHT_PRESS), mode)
        eq(cell(db, "cd.sweep.numbers", KEY_FIGHT_PRESS), mode)
        local d = detail(db, "cd.sweep.object")
        if mode ~= "error" then
            eq(d.func, "SetCooldownFromDurationObject()", mode)
            eq(detail(db, "cd.sweep.numbers").func, "SetCooldown()", mode)
        else
            check(d.message:find("secret values are not allowed here", 1, true), d.message)
        end
        check(d.message:find("slot on cooldown yes", 1, true), mode .. ": " .. tostring(d.message))
        check(d.message:find("sweep frame shown by itself no", 1, true), mode .. ": " .. tostring(d.message))
        check(button(c, "PocketProbeSweep"):IsShown(), "the squares still show, so the player sees no sweep came")
    end
    local c2, P2, db2 = new({ auto = false, setup = function(cl) cl.world.cooldownNoObject = true end })
    c2:advance(5)
    P2.RunOne(P2.trialById["cd.sweep.object"]); P2.RunOne(P2.trialById["cd.sweep.numbers"])
    eq(cell(db2, "cd.sweep.object", KEY_PRESS), "missing")
    eq(detail(db2, "cd.sweep.object").message, "Cooldown:SetCooldownFromDurationObject is not on this client")
    eq(cell(db2, "cd.sweep.numbers", KEY_PRESS), "allowed")
    noErrors(c2)
    local c3, P3, db3 = new({ auto = false, setup = function(cl) cl.world.noCooldown = true end })
    c3:advance(5)
    P3.RunOne(P3.trialById["cd.sweep.object"]); P3.RunOne(P3.trialById["cd.sweep.numbers"])
    eq(cell(db3, "cd.sweep.object", KEY_PRESS), "missing")
    eq(cell(db3, "cd.sweep.numbers", KEY_PRESS), "missing")
    eq(detail(db3, "cd.sweep.numbers").message, "CooldownFrameTemplate is not on this client")
    check(not button(c3, "PocketProbeSweep"):IsShown(), "nothing to show")
    noErrors(c3)
    -- A secret cooldown table: the numbers trial has nothing it may pass on.
    local c4, P4, db4 = new({ auto = false, setup = function(cl)
        local get = cl.env.C_ActionBar.GetActionCooldown
        rawset(cl.env.C_ActionBar, "GetActionCooldown", function(slot)
            local info = get(slot)
            cl.world.secrets[info] = true
            return info
        end)
    end })
    c4:advance(5)
    P4.RunOne(P4.trialById["cd.sweep.numbers"])
    eq(cell(db4, "cd.sweep.numbers", KEY_PRESS), "no effect")
    eq(#c4.cooldownCalls, 0)
    noErrors(c4)
end)

test("the new rows are on the tabs said, and every area still fits ten tabs", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    local area = {}
    for _, t in ipairs(db.trials) do area[t.id] = t.area end
    eq(area["bars.fadecast"], "Blizzard windows"); eq(area["bars.fade"], "Blizzard windows")
    for _, id in ipairs({ "cd.duration", "cd.sweep.object", "cd.sweep.numbers" }) do eq(area[id], "Our own windows", id) end
    eq(area["bag.toggle"], "Bags and vendor", "moved to make room on the Blizzard windows tabs")
    openPanel(c)
    local shown = 0
    for _, t in ipairs(P.panelTabs) do if t:IsShown() then shown = shown + 1 end end
    eq(shown, 10)
    noErrors(c)
end)

---------------------------------------------------------------------------
-- Probe 0.6.0: three fixes to 0.5.0
---------------------------------------------------------------------------

test("Fight tests: a change of place mid-pass does not stop them; the results stay under the key they started with", function()
    local c, P, db = new({ auto = false })
    c:advance(5)
    c:enterCombat(); c:advance(2)
    P.RunFightTests()
    c:advance(1)
    c.world.instance = true                 -- where=world becomes where=party; the fight goes on
    c:advance(40)
    noErrors(c)
    check(P.status:find("^Fight tests done: %d+ run, "), "status: " .. tostring(P.status))
    eq(countLog(db, "pass stopped"), 0)
    eq(countLog(db, "fight tests stopped"), 0)
    for id, row in pairs(db.results) do
        for key in pairs(row) do eq(key, KEY_FIGHT_PRESS, id .. " is filed under the key the pass started with") end
    end
    eq(cell(db, "val.money", KEY_FIGHT_PRESS), "readable", "the last trials of the list ran")
    -- An ordinary pass still stops when the key changes.
    local c2, P2, db2 = new()
    c2:advance(3.5)
    c2.world.instance = true
    c2:advance(2)
    eq(countLog(db2, "pass stopped: the situation changed"), 1)
    noErrors(c2)
end)

test("the three cooldown trials are not in the automatic passes; Fight tests, Run all safe and Run still run them", function()
    local c, P, db = new()
    c:advance(30)
    c:enterCombat(); c:advance(30)
    noErrors(c)
    eq(db.situations[KEY_AUTO].passes, 1); eq(db.situations[KEY_FIGHT].passes, 1)
    for _, id in ipairs({ "cd.duration", "cd.sweep.object", "cd.sweep.numbers" }) do
        check(not db.results[id], id .. " ran in an automatic pass")
        check(P.trialById[id].manual, id .. " is marked manual")
    end
    eq(c.shots, nil, "no screenshot in an automatic pass")
    check(not button(c, "PocketProbeSweep"):IsShown(), "no squares in an automatic pass")
    eq(#c.cooldownCalls, 0)
    local _, fight = ids(P.FightList())
    local _, safe = ids(P.SafeList(false))
    for _, id in ipairs({ "cd.duration", "cd.sweep.object", "cd.sweep.numbers" }) do
        check(fight[id] and fight[id] <= 4, id .. " is still among the first of the fight tests")
        check(safe[id], id .. " is still in Run all safe")
    end
    c:leaveCombat(); c:advance(30)
    P.RunOne(P.trialById["cd.sweep.object"])
    eq(cell(db, "cd.sweep.object", KEY_PRESS), "allowed", "its Run button still runs it")
    noErrors(c)
end)

test("one big message: a second guided trial that has one is refused while another waits", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    P.StartGuided(P.trialById["bars.park"])
    c:advance(0.6)
    -- Refused while the first is still going through its timed steps ...
    P.StartGuided(P.trialById["bars.fadecast"])
    check(P.status:find("^Park the main bar is waiting: answer or Cancel it first"), "status: " .. tostring(P.status))
    eq(saved.guided["bars.fadecast"], nil)
    c:advance(1.1)
    eq(shownText(c, "PocketProbeBigMessage"), PARK_BIG)
    -- ... and while it shows its question.
    P.StartGuided(P.trialById["bars.fadecast"])
    check(P.status:find("^Park the main bar is waiting: answer or Cancel it first"), "status: " .. tostring(P.status))
    eq(saved.guided["bars.fadecast"], nil, "the second trial did not start")
    c:advance(3)
    eq(mainBar(c):GetAlpha(), 1, "nothing was faded")
    eq(shownText(c, "PocketProbeBigMessage"), PARK_BIG, "the first trial's message stays")
    eq(c.shots, 2, "no pictures for the refused trial")
    -- Once the first is answered the second starts.
    P.AnswerGuided(P.trialById["bars.park"], 1)
    P.StartGuided(P.trialById["bars.fadecast"]); c:advance(1.7)
    eq(shownText(c, "PocketProbeBigMessage"), FADE_BIG)
    -- The other way round too.
    P.StartGuided(P.trialById["bars.park"])
    check(P.status:find("^Fade the main bar is waiting: answer or Cancel it first"), "status: " .. tostring(P.status))
    eq(saved.guided["bars.park"], nil)
    P.CancelGuided(P.trialById["bars.fadecast"])
    -- A waiting trial that has no big message is not in the way.
    P.StartGuided(P.trialById["gfx.icons"])
    check(saved.guided["gfx.icons"], "the trial without a big message waits")
    P.StartGuided(P.trialById["bars.park"]); c:advance(1.7)
    eq(shownText(c, "PocketProbeBigMessage"), PARK_BIG)
    noErrors(c)
end)

---------------------------------------------------------------------------
-- Probe 0.6.0: the performance recorder (Perf.lua)
--
-- Pocket Essentials is a stand-in here: a table with the measuring hook's
-- three functions and counters in the agreed shape
-- (docs/superpowers/specs/2026-11-21-perf-recorder.md, ruling 4), and a
-- button named PocketEssentialsHubButton. This is also the "both addons
-- loaded" check: the real Pocket Essentials is not loaded in this suite.
---------------------------------------------------------------------------

local Reader = dofile(root .. "/scripts/read-probe.lua")

local METRIC = { SessionAverageTime = 0, RecentAverageTime = 1, EncounterAverageTime = 2, LastTime = 3, PeakTime = 4,
    CountTimeOver1Ms = 5, CountTimeOver5Ms = 6, CountTimeOver10Ms = 7, CountTimeOver50Ms = 8, CountTimeOver100Ms = 9,
    CountTimeOver500Ms = 10, CountTimeOver1000Ms = 11 }

-- The game's performance calls, as the source describes them. world.perf holds what they answer.
local function installPerf(c, opts)
    local env, world = c.env, c.world
    opts = opts or {}
    c.snapshot.event.PLAYER_STARTED_MOVING = true           -- UnitDocumentation.lua:3946, 3964
    c.snapshot.event.PLAYER_STOPPED_MOVING = true
    world.perf = {
        enabled = true, fps = 60, moving = false,
        memory = { PocketEssentials = 800, QuestieDB = 10000, PocketProbe = 300 },
        shown = { PocketEssentials = 800, QuestieDB = 10000, PocketProbe = 300 },   -- as of the last update
        pe = { [0] = 0.05, [1] = 0.04, [4] = 3.5, [5] = 0, [6] = 0, [7] = 0, [8] = 0, [9] = 0, [10] = 0, [11] = 0 },
        all = { [0] = 0.5, [1] = 0.4, [4] = 20, [5] = 0, [6] = 0, [7] = 0 },
        app = { [0] = 16.6, [1] = 16.7, [4] = 250 },
    }
    c.memoryUpdates, c.tickers = {}, {}
    if not opts.noProfiler then
        rawset(env.Enum, "AddOnProfilerMetric", METRIC)      -- AddOnProfilerConstantsDocumentation.lua:19
        rawset(env, "C_AddOnProfiler", {                     -- AddOnProfilerDocumentation.lua:45, 62, 78, 121
            IsEnabled = function() return world.perf.enabled end,
            GetAddOnMetric = function(name, metric)
                if type(name) ~= "string" or type(metric) ~= "number" then error("bad argument", 2) end
                return name == "PocketEssentials" and world.perf.pe[metric] or 0
            end,
            GetOverallMetric = function(metric) return world.perf.all[metric] or 0 end,
            GetApplicationMetric = function(metric) return world.perf.app[metric] or 0 end,
        })
    end
    -- PerformanceDocumentation.lua:94, 25: the memory numbers only change when the game is asked to count again.
    rawset(env, "UpdateAddOnMemoryUsage", function()
        c.memoryUpdates[#c.memoryUpdates + 1] = c.now
        for name, kb in pairs(world.perf.memory) do world.perf.shown[name] = kb end
    end)
    rawset(env, "GetAddOnMemoryUsage", function(name) return world.perf.shown[name] or 0 end)
    rawset(env, "GetFramerate", function() return world.perf.fps end)          -- ClientDocumentation.lua:44
    rawset(env, "IsPlayerMoving", function() return world.perf.moving end)     -- PlayerScriptDocumentation.lua:1453
    -- C_Timer.NewTicker (UITimerDocumentation.lua:22): calls back every `seconds` until cancelled.
    rawset(env.C_Timer, "NewTicker", function(seconds, fn)
        local t = { cancelled = false, seconds = seconds }
        function t:Cancel() self.cancelled = true end
        local function tick()
            if t.cancelled then return end
            fn(t)
            if not t.cancelled then env.C_Timer.After(seconds, tick) end
        end
        env.C_Timer.After(seconds, tick)
        c.tickers[#c.tickers + 1] = t
        return t
    end)
    world.addons.PocketProbe = true
    world.addons.QuestieDB = true
end

-- The stand-in Pocket Essentials. opts.old: one without the measuring hook.
-- opts.noButton: no PE button. c.pe:work(key, event, ms, calls) is what its hook would count.
local function installPE(c, opts)
    opts = opts or {}
    c.world.addons.PocketEssentials = true
    local pe = { measuring = false, starts = 0, stops = 0, counters = {} }
    if not opts.old then
        function pe:StartMeasure()
            self.starts = self.starts + 1
            self.measuring = true
            return self.counters
        end
        function pe:StopMeasure()
            self.stops = self.stops + 1
            self.measuring = false
        end
        function pe:MeasureCounters() return self.counters end
    end
    function pe:work(key, event, ms, calls, outer)
        if not self.measuring then return end
        calls = calls or 1
        local function add(k)
            local t = self.counters[k]
            if not t then
                t = { ms = 0, calls = 0, max = 0 }
                self.counters[k] = t
            end
            t.ms, t.calls, t.max = t.ms + ms, t.calls + calls, math.max(t.max, ms / calls)
            return t
        end
        local t = add(key)
        if event then
            t.events = t.events or {}
            local e = t.events[event] or { ms = 0, calls = 0 }
            t.events[event] = e
            e.ms, e.calls = e.ms + ms, e.calls + calls
        end
        if outer ~= false then add("*") end
    end
    rawset(c.env, "PocketEssentials", pe)
    c.pe = pe
    if not opts.noButton then
        local hub = c.env.CreateFrame("Button", "PocketEssentialsHubButton", c.env.UIParent)
        hub:SetFrameStrata("HIGH")
        hub:SetSize(70, 70)
        hub:SetPoint("TOPRIGHT", c.env.UIParent, "TOPRIGHT", -20, -200)
        c.hub = hub
    end
end

-- A client with the probe and the stand-in Pocket Essentials. opts.reload: the
-- game says this load is a reload (PLAYER_ENTERING_WORLD false, true).
-- opts.pe = false: Pocket Essentials is not loaded.
local function newPerf(opts)
    opts = opts or {}
    local inner = opts.setup
    return new({ saved = opts.saved, auto = opts.auto == true, setup = function(c)
        installPerf(c, opts)
        if opts.pe ~= false then installPE(c, opts) end
        if opts.reload then
            local fire = c.fire
            c.fire = function(self, event, ...)
                if event == "PLAYER_ENTERING_WORLD" then return fire(self, event, false, true) end
                return fire(self, event, ...)
            end
        end
        if inner then inner(c) end
    end })
end

-- One sample line as a table of its fields (text).
local function fields(line)
    local out = {}
    for name, value in line:gmatch("(%a+)=([^;]*)") do out[name] = value end
    return out
end

local function lastRun(db) return db.perf.runs[#db.perf.runs] end
local function lastSample(db) local r = lastRun(db) return fields(r.samples[#r.samples]) end

test("recorder: without Pocket Essentials nothing starts, shows or ticks, and the panel has no recording line", function()
    local c, P, db = newPerf({ pe = false })
    c:advance(60)
    noErrors(c)
    eq(P.Recording(), false)
    eq(#db.perf.runs, 0); eq(db.perf.on, false)
    eq(#c.tickers, 0, "no ticker")
    eq(#c.memoryUpdates, 0, "the memory is never counted")
    check(not button(c, "PocketProbeRecDot"):IsShown(), "no dot")
    check(not button(c, "PocketProbeRecStopButton"):IsShown(), "no Stop button")
    eq(countLog(db, "recording"), 0, "nothing about recording in the log")
    openPanel(c)
    check(not button(c, "PocketProbeRecordButton"):IsShown(), "no recording button on the panel")
    check(not P.panelRecordText:IsShown(), "no recording text on the panel")
    -- The panel is as wide for its status line as it was in 0.5.0, and trials run as before.
    P.StartRecording()
    eq(P.status, "Recording needs Pocket Essentials switched on.")
    eq(P.Recording(), false)
    P.RunOne(P.trialById["own.show"])
    eq(cell(db, "own.show", KEY_PRESS), "allowed")
    pad(c, "UP"); pad(c, "UP")
    eq(P.Nav.zone, "tabs", "Up from the first tab wraps as in 0.5.0")
    noErrors(c)
end)

test("recorder: starts by itself at login; the dot takes no touch; Stop sits beside the PE button; the hook is on", function()
    local c, P, db = newPerf()
    eq(P.Recording(), true, "recording from the first moment in the world")
    eq(c.pe.starts, 1); eq(c.pe.measuring, true)
    eq(db.perf.on, true); eq(db.perf.stopped, false)
    eq(#db.perf.runs, 1)
    local r = lastRun(db)
    check(r.started:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"), "started is a date and time")
    eq(r.interval, 15); eq(r.profiler, "on"); eq(r.features, true); eq(r.reloads, 0); eq(r.ended, nil)
    eq(#r.samples, 1, "one sample to start from")
    eq(fields(r.samples[1]).dt, "0")
    eq(#c.tickers, 1); eq(c.tickers[1].seconds, 15)
    -- The dot: bottom-right corner, HIGH, no mouse.
    local dot = button(c, "PocketProbeRecDot")
    check(dot:IsShown(), "the dot shows")
    local st = c._state(dot)
    eq(st.type, "Frame"); eq(st.mouse, false, "the dot takes no mouse or touch"); eq(dot:GetFrameStrata(), "HIGH")
    check(not st.bindings and not st.scripts.OnMouseDown and not st.scripts.OnClick, "the dot has no click script")
    local sl, sr, stop_, sb = c._rect(c.env.UIParent)
    local l, rgt, top, bottom = c._rect(dot)
    check(sr - rgt > 0 and sr - rgt < 20 and bottom - sb > 0 and bottom - sb < 20, "the dot is in the bottom-right corner")
    check(rgt - l > 10 and rgt - l < 30, "the dot is small: " .. (rgt - l))
    -- Stop: round button as big as the PE button, on its side facing the middle of the screen.
    local stopB = button(c, "PocketProbeRecStopButton")
    check(stopB:IsShown(), "Stop shows")
    eq(stopB:GetFrameStrata(), "HIGH")
    eq(stopB:GetWidth(), 70); eq(stopB:GetHeight(), 70)
    local hl, hr, ht, hb = c._rect(c.hub)
    local bl, br, bt, bb = c._rect(stopB)
    check(br < hl and hl - br < 20, "Stop is just left of the PE button (which is on the right of the screen)")
    eq(bt, ht, "level with the PE button")
    eq(shownText(c, "PocketProbeRecStopButton"), "Stop")
    -- It follows the PE button: on the left half of the screen Stop goes to its right.
    c.hub:ClearAllPoints()
    c.hub:SetPoint("TOPLEFT", c.env.UIParent, "TOPLEFT", 30, -100)
    c:advance(16)
    hl, hr, ht = c._rect(c.hub)
    bl, br, bt = c._rect(stopB)
    check(bl > hr and bl - hr < 20, "Stop is just right of the PE button now")
    eq(bt, ht)
    -- Nothing in the way of the game: no keys taken while recording.
    for _, rec in ipairs(c:frames()) do check(not rawget(rec, "bindings"), "a key is taken while recording") end
    check(not rawget(c.env, "PocketProbePanel"):IsShown(), "the probe window stays closed")
    noErrors(c)
end)

test("recorder: a sample every 15 seconds with time, frame rate, memory, the hook's change and the profiler's change", function()
    local c, P, db = newPerf()
    local r = lastRun(db)
    eq(#c.memoryUpdates, 1, "memory counted once for the first sample")
    eq(fields(r.samples[1]).mem, "800,10000,300")
    eq(fields(r.samples[1]).fps, "60")
    eq(fields(r.samples[1]).pe, nil, "the first sample only notes where the counters stand")
    eq(fields(r.samples[1]).p, nil)
    -- 15 seconds of work.
    c.pe:work("questicons", "QUEST_LOG_UPDATE", 6, 3)
    c.pe:work("questicons", "OnUpdate", 1.5, 100)
    c.pe:work("core", "BAG_UPDATE", 0.25, 5)
    c.pe:work("bags", nil, 2, 1, false)                 -- a nested run: not in the total
    c.world.perf.memory.PocketEssentials = 850
    c.world.perf.fps = 50
    c.world.perf.pe[1] = 0.031
    c.world.perf.pe[5], c.world.perf.pe[6] = 12, 2
    c.world.perf.all[5] = 40
    c:advance(15.3)
    eq(#r.samples, 2)
    local s = fields(r.samples[2])
    eq(s.t, "15"); eq(s.dt, "15"); eq(s.fps, "50")
    eq(s.mem, "850,10000,300")
    eq(s.pe, "7.75,108,2", "the whole addon: ms, runs, slowest run")
    eq(s.p, "0.031,12,2,0,0,0,0,0", "profiler: recent ms, then frames over 1, 5, 10, ... ms since the last sample")
    eq(s.all, "0.4,40,0,0"); eq(s.app, "16.7")
    -- Per feature: key number:ms:runs:slowest.
    local byKey = {}
    for part in s.f:gmatch("[^,]+") do
        local k, ms, runs, slowest = part:match("^(%d+):([%d%.]+):(%d+):([%d%.]+)$")
        check(k, "a feature entry reads key:ms:runs:slowest: " .. part)
        byKey[r.keys[tonumber(k)]] = { ms = ms, runs = runs, slowest = slowest }
    end
    eq(byKey.questicons.ms, "7.5"); eq(byKey.questicons.runs, "103"); eq(byKey.questicons.slowest, "2")
    eq(byKey.core.ms, "0.25"); eq(byKey.bags.runs, "1")
    check(not byKey["*"], "the total is not listed as a feature")
    -- The run's totals, with the events.
    eq(r.feat["*"].ms, 7.75); eq(r.feat["*"].calls, 108); eq(r.feat["*"].max, 2)
    eq(r.feat.questicons.events.QUEST_LOG_UPDATE.ms, 6); eq(r.feat.questicons.events.OnUpdate.calls, 100)
    eq(r.feat.bags.events, nil, "no events for a key the dispatcher did not time")
    eq(r.session.pe.avg, 0.05); eq(r.session.pe.peak, 3.5); eq(r.session.app.peak, 250)
    -- A quiet 15 seconds: nothing ran, counts did not move.
    c:advance(15)
    eq(#r.samples, 3)
    s = fields(r.samples[3])
    eq(s.pe, nil); eq(s.f, nil)
    eq(s.p, "0.031,0,0,0,0,0,0,0", "counts are the change, not the total")
    -- More work: only the change is stored, and a slower run shows.
    c.pe:work("questicons", "QUEST_LOG_UPDATE", 9, 1)
    c:advance(15)
    s = fields(r.samples[4])
    eq(s.pe, "9,1,9")
    eq(r.feat["*"].ms, 16.75); eq(r.feat["*"].max, 9); eq(r.feat.questicons.events.QUEST_LOG_UPDATE.calls, 4)
    -- Memory: counted once per sample, never closer than 15 seconds.
    eq(#c.memoryUpdates, 4)
    for i = 2, #c.memoryUpdates do
        check(c.memoryUpdates[i] - c.memoryUpdates[i - 1] >= 14.9, "memory counted twice within 15 seconds")
    end
    -- Stop and Start within the same 15 seconds do not count it again.
    P.StopRecording(); P.StartRecording()
    eq(#c.memoryUpdates, 4, "no extra memory count on Stop or a quick Start")
    eq(#c.tickers, 2); eq(c.tickers[1].cancelled, true, "the first run's ticker is cancelled")
    -- Every sample line is numbers and our own letters only.
    for _, run in ipairs(db.perf.runs) do
        for _, line in ipairs(run.samples) do
            check(line:match("^[%a%d=;:,%.]+$"), "a sample line holds something else: " .. line)
        end
    end
    local text = table.concat(dump(db), "\n")
    for _, word in ipairs(WORLD_TEXT) do
        check(not text:find(word, 1, true), "text from the world was saved: " .. word)
    end
    noErrors(c)
end)

test("recorder: activity tags come from events and show / hide hooks, and cover the whole stretch", function()
    local c, P, db = newPerf()
    local r = lastRun(db)
    local function tagsAfter(seconds)
        c:advance(seconds or 15.3)
        return fields(r.samples[#r.samples]).a
    end
    eq(fields(r.samples[1]).a, "s", "standing still at the start")
    eq(tagsAfter(), "s")
    -- Moving for part of a stretch: both.
    c:fire("PLAYER_STARTED_MOVING")
    eq(tagsAfter(), "ms")
    eq(tagsAfter(15), "m", "moving all the way through")
    c:fire("PLAYER_STOPPED_MOVING")
    eq(tagsAfter(15), "ms")
    eq(tagsAfter(15), "s")
    -- A fight that starts and ends inside one stretch is still seen.
    c:enterCombat(); c:advance(3); c:leaveCombat()
    eq(tagsAfter(12), "cs")
    eq(tagsAfter(15), "s")
    -- Vendor, world map, bags.
    c:openMerchant(); c:advance(2); c:closeMerchant()
    c:openWorldMap(1429); c:advance(2); c:closeWorldMap()
    c:openBag()
    eq(tagsAfter(11), "vwbs")
    eq(tagsAfter(15), "bs", "the bag is still open")
    c:closeBag()
    eq(tagsAfter(15), "bs", "open for the first moment of this stretch")
    eq(tagsAfter(15), "s")
    -- A dungeon, entered through a loading screen.
    c.world.instance = true
    c:fire("PLAYER_ENTERING_WORLD", false, false)
    eq(tagsAfter(15), "ds")
    eq(#db.perf.runs, 1, "a loading screen is not a new run")
    -- Nothing here ran every frame, and stopping takes the listeners off.
    eq(c.stats.addonOnUpdate, 0, "no OnUpdate script of the probe ran")
    P.StopRecording()
    local n = #r.samples
    c:fire("PLAYER_STARTED_MOVING"); c:enterCombat(); c:openBag(); c:advance(40)
    eq(#r.samples, n, "nothing is recorded after Stop")
    noErrors(c)
    -- What is true when a recording starts is read once.
    local c2, P2, db2 = newPerf({ setup = function(cl)
        cl.world.perf.moving = true
        cl.world.instance = true
    end })
    eq(fields(lastRun(db2).samples[1]).a, "dm")
    noErrors(c2)
end)

test("recorder: Stop ends the run and stays stopped over a reload; Start recording and a fresh login record again", function()
    local saved = {}
    local c, P, db = newPerf({ saved = saved })
    c.pe:work("core", "BAG_UPDATE", 1, 2)
    c:advance(20)
    c.pe:work("core", "BAG_UPDATE", 3, 1)
    c:click(button(c, "PocketProbeRecStopButton"))
    eq(P.Recording(), false)
    eq(c.pe.stops, 1); eq(c.pe.measuring, false)
    eq(db.perf.on, false); eq(db.perf.stopped, true)
    local r = lastRun(db)
    eq(r.why, "stopped")
    check(r.ended:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"), "ended is a date and time")
    eq(r.prev, nil, "the working numbers are not kept")
    eq(#r.samples, 3, "the last few seconds are a sample of their own")
    eq(fields(r.samples[3]).dt, "5"); eq(fields(r.samples[3]).pe, "3,1,3")
    eq(r.feat["*"].ms, 4)
    check(not button(c, "PocketProbeRecDot"):IsShown(), "the dot is gone")
    check(not button(c, "PocketProbeRecStopButton"):IsShown(), "Stop is gone")
    eq(c.tickers[1].cancelled, true)
    check(P.status:find("^Recording stopped"), P.status)
    c:advance(60)
    eq(#r.samples, 3)
    noErrors(c)
    -- A reload: still stopped.
    local c2, P2 = newPerf({ saved = saved, reload = true })
    check(math.abs(saved.perf.memAt - 1015) < 0.2, "the time of the last memory count is kept over the reload")
    c2:advance(30)
    eq(P2.Recording(), false); eq(#saved.perf.runs, 1); eq(c2.pe.starts, 0)
    check(not button(c2, "PocketProbeRecDot"):IsShown(), "no dot after the reload")
    eq(countLog(saved, "recording not started: it was stopped before the reload"), 1)
    -- Start recording, in the probe window.
    openPanel(c2)
    local rec = button(c2, "PocketProbeRecordButton")
    eq(rec.ppLabel:GetText(), "Start recording")
    eq(P2.panelRecordText:GetText(), "Not recording")
    c2:click(rec)
    eq(P2.Recording(), true); eq(#saved.perf.runs, 2); eq(c2.pe.starts, 1)
    eq(rec.ppLabel:GetText(), "Stop")
    eq(P2.panelRecordText:GetText(), "Recording 0 min")
    check(P2.status:find("^Recording started"), P2.status)
    check(button(c2, "PocketProbeRecDot"):IsShown(), "the dot is back")
    -- Close leaves it recording; the window's Stop ends it.
    c2:click(button(c2, "PocketProbeCloseButton"))
    eq(P2.Recording(), true, "Close does not stop the recording")
    c2:advance(125)
    openPanel(c2)
    eq(P2.panelRecordText:GetText(), "Recording 2 min")
    c2:click(rec)
    eq(P2.Recording(), false); eq(saved.perf.runs[2].why, "stopped")
    eq(rec.ppLabel:GetText(), "Start recording")
    noErrors(c2)
    -- A fresh login records again, though the last session ended stopped.
    local c3, P3 = newPerf({ saved = saved })
    eq(P3.Recording(), true); eq(#saved.perf.runs, 3); eq(saved.perf.stopped, false)
    noErrors(c3)
end)

test("recorder: a recording carries on over a reload as the same run; counters that start again are not counted twice", function()
    local saved = {}
    local c, P = newPerf({ saved = saved })
    c.pe:work("core", "BAG_UPDATE", 5, 10)
    c.world.perf.pe[5] = 7
    c:advance(15.3)
    c.pe:work("core", "BAG_UPDATE", 2, 1)
    c:advance(4)
    c:fire("PLAYER_LOGOUT")
    local r = saved.perf.runs[1]
    eq(#r.samples, 3, "the stretch before the reload is kept")
    eq(fields(r.samples[3]).pe, "2,1,2")
    eq(saved.perf.on, true, "still recording when the game writes the file")
    eq(r.ended, nil)
    noErrors(c)
    -- The reload: Pocket Essentials' counters start from zero, the profiler's go on.
    local c2, P2 = newPerf({ saved = saved, reload = true, setup = function(cl)
        cl.now = 1100
        cl.world.perf.pe[5] = 9
    end })
    eq(P2.Recording(), true)
    eq(#saved.perf.runs, 1, "the same run")
    eq(r.reloads, 1)
    eq(c2.pe.starts, 1, "the hook is switched on again")
    eq(#r.samples, 4); eq(fields(r.samples[4]).dt, "0")
    eq(#c2.memoryUpdates, 1, "100 seconds on: the memory is counted again")
    eq(countLog(saved, "recording carries on after the reload"), 1)
    c2.pe:work("core", "BAG_UPDATE", 1, 4)      -- 1 ms in all since the reload: less than before it
    c2.world.perf.pe[5] = 12
    c2:advance(15.3)
    local s = fields(r.samples[5])
    eq(s.pe, "1,4,0.25", "counted from zero, not as a negative change")
    eq(s.p:match("^[^,]+,(%d+)"), "3", "the profiler's count goes on from where the reload left it")
    eq(tonumber(s.t) > 100, true, "time runs on from the start of the run")
    eq(r.feat["*"].ms, 8); eq(r.feat["*"].calls, 15)
    eq(r.feat.core.events.BAG_UPDATE.ms, 8)
    -- The hook starting again inside one session is handled the same way.
    c2.pe.counters["*"].ms, c2.pe.counters["*"].calls, c2.pe.counters["*"].max = 0.5, 1, 0.5
    c2.pe.counters.core = nil
    c2:advance(15)
    eq(fields(r.samples[6]).pe, "0.5,1,0.5")
    eq(r.feat["*"].ms, 8.5)
    noErrors(c2)
    -- A fresh login after a logout while recording: the old run is closed, a new one starts.
    c2:fire("PLAYER_LOGOUT")
    local c3, P3 = newPerf({ saved = saved })
    eq(#saved.perf.runs, 2)
    eq(saved.perf.runs[1].why, "ended at a reload or a logout")
    eq(saved.perf.runs[1].prev, nil)
    eq(P3.Recording(), true)
    noErrors(c3)
end)

test("recorder: 480 samples, then it stops by itself and says so; the last three runs are kept", function()
    local samples = {}
    for i = 1, 478 do samples[i] = "t=" .. (i * 15) .. ";dt=15;a=s;fps=60" end
    local saved = { probe = "0.7.0", perf = { on = true, runs = {
        { started = "2026-11-20 10:00:00", why = "stopped", samples = { "t=0;dt=0;a=s" }, keys = {}, feat = {} },
        { started = "2026-11-21 10:00:00", why = "stopped", samples = { "t=0;dt=0;a=s" }, keys = {}, feat = {} },
        { started = "2026-11-21 11:00:00", why = "stopped", samples = { "t=0;dt=0;a=s" }, keys = {}, feat = {} },
        { started = "2026-11-22 10:00:00", t0 = 900, interval = 15, reloads = 0, samples = samples, keys = {}, feat = {} },
    } } }
    local c, P, db = newPerf({ saved = saved, reload = true })
    eq(#db.perf.runs, 3, "the oldest run is removed at load")
    eq(db.perf.runs[1].started, "2026-11-21 10:00:00")
    local r = lastRun(db)
    eq(P.Recording(), true); eq(#r.samples, 479)
    c:advance(15.3)
    eq(#r.samples, 480)
    eq(P.Recording(), false, "it stops at 480 samples")
    eq(r.why, "full")
    eq(P.status:match("^[^—]+"), "Recording stopped by itself: 2 hours reached")
    eq(countLog(db, "recording stopped by itself: 2 hours reached, 480 samples"), 1)
    eq(c.pe.stops, 1)
    check(not button(c, "PocketProbeRecDot"):IsShown(), "the dot is gone")
    openPanel(c)
    eq(P.panelRecordText:GetText(), "Stopped at 2 hours")
    c:advance(60)
    eq(#r.samples, 480)
    noErrors(c)
    -- It does not start again by itself at the next reload; a new run drops the oldest.
    local c2, P2 = newPerf({ saved = saved, reload = true })
    eq(P2.Recording(), false)
    P2.StartRecording()
    eq(#saved.perf.runs, 3)
    eq(saved.perf.runs[1].started, "2026-11-21 11:00:00")
    eq(saved.perf.runs[2], r)
    noErrors(c2)
    -- Recordings of another probe version go with its other results.
    saved.probe = "0.5.9"
    local c3 = newPerf({ saved = saved, pe = false })
    eq(#saved.perf.runs, 0)
    noErrors(c3)
end)

test("recorder: trials are refused while it records, and it is refused while a trial or a guided trial is under way", function()
    local saved = { options = { auto = true, risky = true } }
    local c, P, db = newPerf({ saved = saved, auto = true })
    c:advance(30)
    eq(P.Recording(), true)
    eq(countLog(db, "pass started"), 0, "no automatic pass while recording")
    c:enterCombat(); c:advance(5)
    P.RunFightTests()
    eq(P.status, "Recording: tap Stop first.")
    c:leaveCombat(); c:advance(5)
    c:openMerchant(); c:advance(5); c:closeMerchant()
    P.RunAllSafe(); eq(P.status, "Recording: tap Stop first.")
    P.status = nil
    P.RunOne(P.trialById["own.show"]); eq(P.status, "Recording: tap Stop first.")
    P.status = nil
    P.StartGuided(P.trialById["bars.park"]); eq(P.status, "Recording: tap Stop first.")
    P.status = nil
    P.BeginClean(); eq(P.status, "Recording: tap Stop first.")
    eq(c.reloads, 0, "no clean run, no reload")
    eq(db.clean.running, false)
    c:advance(30)
    eq(next(db.results), nil, "no trial ran")
    eq(next(db.guided), nil)
    eq(countLog(db, "pass started"), 0)
    -- The panel: the buttons that start trials are dim, with the reason.
    local row = showTrial(c, P, "own.show")
    eq(row.ppRun.ppDisabled, true, "Run is dim while recording")
    c:click(row.ppRun)
    eq(next(db.results), nil)
    eq(showTrial(c, P, "bars.park").ppRun.ppDisabled, true, "Start is dim while recording")
    for i, name in ipairs({ "PocketProbeRunAllButton", "PocketProbeFightButton", "PocketProbeCleanButton" }) do
        eq(button(c, name).ppDisabled, true, name .. " is dim while recording")
    end
    for _, name in ipairs({ "PocketProbeRiskyButton", "PocketProbeVendorButton", "PocketProbeAutoButton", "PocketProbeSaveButton",
        "PocketProbeCloseButton", "PocketProbeRecordButton" }) do
        eq(button(c, name).ppDisabled, false, name .. " still works")
    end
    local note
    for _, rec in ipairs(c:frames()) do
        if rec.frame == rawget(c.env, "PocketProbePanel") then
            for _, region in ipairs(rec.regions or {}) do
                local t = region.GetText and region:GetText()
                if type(t) == "string" and t:find("Recording: tap Stop first.", 1, true) then note = t end
            end
        end
    end
    check(note, "the panel says why the trial buttons are dim")
    -- Stop: everything works again.
    c:click(button(c, "PocketProbeRecordButton"))
    eq(P.Recording(), false)
    eq(showTrial(c, P, "own.show").ppRun.ppDisabled, false)
    eq(button(c, "PocketProbeRunAllButton").ppDisabled, false)
    c:click(showTrial(c, P, "own.show").ppRun)
    eq(cell(db, "own.show", KEY_PRESS), "allowed")
    -- The other way round: no recording while a pass runs ...
    P.RunAllSafe()
    P.StartRecording()
    eq(P.status:match("^[^—]+"), "A trial is running: let it finish or tap Stop first.")
    eq(P.Recording(), false); eq(c.pe.starts, 1)
    P.Stop()
    -- ... or while a guided trial waits.
    P.StartGuided(P.trialById["bars.park"]); c:advance(1.7)
    P.StartRecording()
    check(P.status:find("^Park the main bar is waiting: answer or Cancel it first"), P.status)
    eq(P.Recording(), false)
    P.AnswerGuided(P.trialById["bars.park"], 1)
    P.StartRecording()
    eq(P.Recording(), true)
    noErrors(c)
    -- A clean run going at login keeps the recording off; so does a guided trial waiting for its answer.
    local c2, P2, db2 = newPerf({ saved = { clean = { index = 0, running = true } }, reload = true })
    eq(P2.Recording(), false)
    eq(countLog(db2, "recording not started: A trial is running"), 1)
    noErrors(c2)
end)

test("recorder: the probe window reaches Stop with the d-pad", function()
    local c, P, db = newPerf()
    c:advance(5)
    openPanel(c)
    local rec, close, panel = button(c, "PocketProbeRecordButton"), button(c, "PocketProbeCloseButton"), button(c, "PocketProbePanel")
    check(rec:IsShown() and P.panelRecordText:IsShown(), "the recording line shows with Pocket Essentials loaded")
    eq(rec.ppLabel:GetText(), "Stop")
    -- In the title bar, left of Close, inside the panel, not over the text beside it.
    local pl, pr, pt, pb = c._rect(panel)
    local l, r, t, b = c._rect(rec)
    local cl = c._rect(close)
    local _, _, closeTop, closeBottom = c._rect(close)
    check(l > pl and r < cl and t == closeTop and b == closeBottom, "the recording button is in the title bar, left of Close")
    local tl, tr = c._rect(P.panelRecordText)
    check(tr <= l and tl > pl, "the recording text is left of its button")
    -- Ten tabs still: the line takes no room from the list.
    local shown = 0
    for _, tab in ipairs(P.panelTabs) do if tab:IsShown() then shown = shown + 1 end end
    eq(shown, 10)
    -- Up to the tabs, Up again from the first tab to the recording button, A stops.
    pad(c, "UP")
    eq(P.Nav.zone, "tabs")
    pad(c, "UP")
    eq(P.Nav.zone, "top"); eq(P.Nav.Target(), rec)
    pad(c, "DOWN")
    eq(P.Nav.zone, "tabs")
    pad(c, "UP")
    pad(c, "A")
    eq(P.Recording(), false, "A on the recording button stops the recording")
    eq(rec.ppLabel:GetText(), "Start recording")
    check(panel:IsShown(), "the window stays open")
    pad(c, "A")
    eq(P.Recording(), true, "and A again starts one")
    -- No key is taken outside the window.
    c:click(close)
    for _, frameRec in ipairs(c:frames()) do check(not rawget(frameRec, "bindings"), "a key is taken with the window closed") end
    noErrors(c)
end)

test("recorder: profiler off or missing, an older Pocket Essentials, and missing game calls all record what they can", function()
    -- The profiler is switched off: memory, frame rate and the hook's numbers only.
    local c, P, db = newPerf({ setup = function(cl) cl.world.perf.enabled = false end })
    c.pe:work("core", "BAG_UPDATE", 1, 1)
    c:advance(15.3)
    local r = lastRun(db)
    eq(r.profiler, "off")
    local s = fields(r.samples[2])
    eq(s.p, nil); eq(s.all, nil); eq(s.app, nil); eq(r.session, nil)
    eq(s.pe, "1,1,1"); eq(s.mem, "800,10000,300"); eq(s.fps, "60")
    noErrors(c)
    -- No profiler on this client at all.
    local c2, P2, db2 = newPerf({ noProfiler = true })
    c2:advance(15.3)
    eq(lastRun(db2).profiler, "missing")
    eq(fields(lastRun(db2).samples[2]).p, nil)
    noErrors(c2)
    -- An older Pocket Essentials, with no measuring hook: the game's numbers only.
    local c3, P3, db3 = newPerf({ old = true })
    eq(P3.Recording(), true)
    c3:advance(15.3)
    local r3 = lastRun(db3)
    eq(r3.features, false)
    local s3 = fields(r3.samples[2])
    eq(s3.pe, nil); eq(s3.f, nil)
    eq(s3.p, "0.04,0,0,0,0,0,0,0"); eq(s3.mem, "800,10000,300")
    eq(next(r3.feat), nil)
    P3.StopRecording()
    noErrors(c3)
    -- A hook that raises, or hands over something odd, is the same as none.
    local c4, P4, db4 = newPerf({ setup = function(cl)
        cl.pe.StartMeasure = function() error("not today") end
        cl.pe.MeasureCounters = function() return "junk" end
        cl.pe.StopMeasure = function() error("nor now") end
    end })
    c4:advance(15.3)
    eq(lastRun(db4).features, false)
    P4.StopRecording()
    eq(P4.Recording(), false)
    noErrors(c4)
    -- Counters with odd things in them are left out, not saved.
    local c5, P5, db5 = newPerf()
    c5.pe.measuring = true
    c5.pe.counters["core"] = { ms = "a lot", calls = 2, max = 1, events = { ["Zugzug says hi"] = { ms = 1, calls = 1 }, [5] = { ms = 1, calls = 1 }, EVENT = "x" } }
    c5.pe.counters[7] = { ms = 1, calls = 1, max = 1 }
    c5.pe.counters["Zugzug's key!"] = { ms = 1, calls = 1, max = 1 }
    c5.pe.counters["junk"] = "text"
    c5:advance(15.3)
    local r5 = lastRun(db5)
    eq(#r5.keys, 1); eq(r5.keys[1], "core")
    eq(r5.feat.core.calls, 2); eq(r5.feat.core.ms, 0)
    eq(r5.feat.core.events["Zugzug says hi"].calls, 1, "plain words are kept as an event name")
    check(not table.concat(dump(db5), "\n"):find("Zugzug's key", 1, true), "a key that is not plain was saved")
    noErrors(c5)
    -- Game calls this client lacks: their numbers are left out and the run says which.
    local c6, P6, db6 = newPerf({ setup = function(cl)
        rawset(cl.env, "GetFramerate", nil)
        rawset(cl.env, "UpdateAddOnMemoryUsage", nil)
        rawset(cl.env, "IsPlayerMoving", nil)
        rawset(cl.env.C_Timer, "NewTicker", nil)
    end })
    c6:advance(40)
    local r6 = lastRun(db6)
    eq(#r6.samples, 1, "no ticker: only the first sample until Stop")
    check(r6.missing.GetFramerate and r6.missing.UpdateAddOnMemoryUsage and r6.missing["C_Timer.NewTicker"], "the run says what was missing")
    eq(fields(r6.samples[1]).fps, nil)
    P6.StopRecording()
    eq(#r6.samples, 2); eq(fields(r6.samples[2]).dt, "40")
    noErrors(c6)
    local c7, P7, db7 = newPerf({ setup = function(cl) rawset(cl.env, "GetAddOnMemoryUsage", nil) end })
    c7:advance(15.3)
    eq(fields(lastRun(db7).samples[2]).mem, nil)
    check(lastRun(db7).missing.GetAddOnMemoryUsage, "missing memory call noted")
    noErrors(c7)
end)

test("recorder: with the PE button hidden or not there, Stop sits just above the red dot", function()
    local c, P, db = newPerf({ noButton = true })
    local dot, stopB = button(c, "PocketProbeRecDot"), button(c, "PocketProbeRecStopButton")
    check(stopB:IsShown(), "Stop shows without a PE button")
    local dl, dr, dt, db_ = c._rect(dot)
    local l, r, t, b = c._rect(stopB)
    check(b > dt and b - dt < 20, "Stop is just above the dot")
    eq(r, dr, "in the same corner")
    check(r - l > 40, "big enough to tap: " .. (r - l))
    noErrors(c)
    -- The PE button made a moment after login is found.
    local hub = c.env.CreateFrame("Button", "PocketEssentialsHubButton", c.env.UIParent)
    hub:SetSize(64, 64)
    hub:SetPoint("TOPRIGHT", c.env.UIParent, "TOPRIGHT", -20, -200)
    c:advance(1.2)
    local hl = c._rect(hub)
    l, r = c._rect(stopB)
    check(r < hl and hl - r < 20, "Stop moved beside the PE button")
    eq(stopB:GetWidth(), 64)
    -- Hidden: back above the dot at once; shown: beside it again.
    hub:Hide()
    l, r, t, b = c._rect(stopB)
    check(b > dt and b - dt < 20 and r == dr, "Stop is above the dot while the PE button is hidden")
    hub:Show()
    l, r = c._rect(stopB)
    check(r < hl, "and beside it again")
    -- The round picture is Pocket Essentials' own file; the frames are made at load.
    noErrors(c)
    local c2, P2 = newPerf({ pe = false })
    check(rawget(c2.env, "PocketProbeRecDot") and rawget(c2.env, "PocketProbeRecStopButton"), "the frames are made at load, not when a recording starts")
    noErrors(c2)
end)

test("recorder with Pocket Essentials loaded: a play session records and stops cleanly, and the report reads it", function()
    local c, P, db = newPerf()
    c.world.perf.memory.PocketEssentials = 1200
    local minute = 0
    for step = 1, 40 do
        c.pe:work("questicons", "QUEST_LOG_UPDATE", 0.6, 3)
        c.pe:work("core", "BAG_UPDATE", 0.2, 4)
        if step == 5 then c:fire("PLAYER_STARTED_MOVING") end
        if step == 10 then c:enterCombat() end
        if step == 14 then c:leaveCombat() end
        if step == 20 then c:openMerchant() end
        if step == 22 then c:closeMerchant() end
        if step == 30 then c:openWorldMap(1429) end
        if step == 31 then c:closeWorldMap() end
        c.world.perf.pe[5] = c.world.perf.pe[5] + 2
        c:advance(15)
    end
    c:click(button(c, "PocketProbeRecStopButton"))
    noErrors(c)
    eq(P.Recording(), false); eq(c.pe.measuring, false)
    local r = lastRun(db)
    check(#r.samples >= 40 and #r.samples <= 42, "samples: " .. #r.samples)
    -- The reader takes the saved table as the device would write it.
    local out = table.concat(Reader.formatPerf(db), "\n")
    for _, part in ipairs({ "Performance recording", "Run 1 of 1", "10 min", "questicons", "QUEST_LOG_UPDATE", "in a fight", "at a vendor",
        "world map open", "moving", "In plain words" }) do
        check(out:find(part, 1, true), "the report lacks \"" .. part .. "\":\n" .. out)
    end
    check(not out:find("no per-feature numbers", 1, true), "the report has the per-feature numbers")
    -- An older Pocket Essentials: the report says the per-feature numbers are not there.
    local c2, P2, db2 = newPerf({ old = true })
    c2:advance(60)
    P2.StopRecording()
    noErrors(c2)
    check(table.concat(Reader.formatPerf(db2), "\n"):find("no per-feature numbers", 1, true), "the report says there are no per-feature numbers")
end)

---------------------------------------------------------------------------
-- Probe 0.7.0: the watchers (Watch.lua) and Clear saved results
---------------------------------------------------------------------------

local WATCH_EVENTS = { "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE",
    "ACTIONBAR_SLOT_CHANGED", "SPELL_UPDATE_COOLDOWN", "UPDATE_BONUS_ACTIONBAR" }

-- The frame of Watch.lua that listens for the action bar events, or nil.
local function watchFrame(c)
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile and rec.addonFile:find("Watch.lua", 1, true) and rec.scripts.OnEvent then return rec end
    end
end

local function watchSaved() return { options = { auto = false } } end

test("watch: arm refused in a fight", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    c:enterCombat(); c:advance(1)
    local ok = P.WatchArm()
    eq(ok, false)
    eq(P.WatchArmed(), false)
    eq(P.WatchCurrent(), nil)
    eq(#saved.watch, 0, "nothing stored")
    check(P.status:find("out of a fight", 1, true), P.status)
    local rec = watchFrame(c)
    check(rec, "the watch frame is made at load")
    eq(next(rec.events), nil, "no event registered")
    noErrors(c)
end)

test("watch: arm and disarm", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    local rec = watchFrame(c)
    eq(next(rec.events), nil, "nothing is registered before Arm")
    local changed = 0
    P.OnWatchChanged = function() changed = changed + 1 end
    eq(P.WatchArm(), true)
    eq(P.WatchArmed(), true)
    local cur = P.WatchCurrent()
    eq(cur, saved.watch[1])
    eq(#saved.watch, 1)
    check(type(cur.started) == "string" and cur.started ~= "", "started is stored")
    eq(cur.ended, nil)
    for _, key in ipairs({ "bar", "press", "events", "sweep" }) do eq(type(cur[key]), "table", key) end
    for _, event in ipairs(WATCH_EVENTS) do check(rec.events[event], event .. " registered while armed") end
    check(changed >= 1, "the panel is told")
    eq(P.WatchArm(), true, "a second Arm changes nothing")
    eq(#saved.watch, 1)
    c:fire("ACTIONBAR_UPDATE_USABLE")
    P.WatchDisarm()
    eq(P.WatchArmed(), false)
    eq(P.WatchCurrent(), nil)
    eq(cur.why, "disarmed")
    check(type(cur.ended) == "string" and cur.ended ~= "", "ended is stored")
    eq(next(rec.events), nil, "every event unregistered on Disarm")
    eq(cur.events.ACTIONBAR_UPDATE_USABLE.o, 1)
    c:fire("PLAYER_REGEN_DISABLED")
    eq(cur.events.ACTIONBAR_UPDATE_USABLE.o, 1, "nothing counted after Disarm")
    noErrors(c)
end)

test("watch: events counted in and out of a fight", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    P.WatchArm()
    for _, event in ipairs(WATCH_EVENTS) do c:fire(event); c:fire(event) end
    c:advance(10)
    c:enterCombat()
    for _, event in ipairs(WATCH_EVENTS) do c:fire(event); c:fire(event); c:fire(event) end
    c:advance(20)
    c:leaveCombat()
    c:advance(5)
    local cur = P.WatchCurrent()
    P.WatchDisarm()
    for _, event in ipairs(WATCH_EVENTS) do
        eq(cur.events[event].o, 2, event .. " out of a fight")
        eq(cur.events[event].c, 3, event .. " in a fight")
    end
    check(math.abs(cur.events._secs.c - 20) < 0.3, "seconds in a fight: " .. tostring(cur.events._secs.c))
    check(math.abs(cur.events._secs.o - 15) < 0.3, "seconds out of a fight: " .. tostring(cur.events._secs.o))
    noErrors(c)
end)

test("watch: reload ends it", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    P.WatchArm()
    c:advance(3)
    c:fire("PLAYER_LOGOUT")
    eq(saved.watch[1].why, "reload")
    check(saved.watch[1].ended, "ended at the logout")
    local c2, P2 = new({ saved = saved })
    c2:advance(5)
    eq(P2.WatchArmed(), false, "not armed again after the reload")
    eq(next(watchFrame(c2).events), nil)
    eq(#saved.watch, 1)
    -- An arming the logout never closed (the game stopped): closed at the next load.
    saved.watch[2] = { started = "2026-11-23 12:00:00", bar = {}, press = {}, events = {}, sweep = {} }
    local c3 = new({ saved = saved })
    eq(saved.watch[2].why, "reload")
    noErrors(c); noErrors(c2); noErrors(c3)
end)

test("watch: old file and trim to 3", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    eq(type(saved.watch), "table", "an old file gets an empty watch table")
    eq(#saved.watch, 0)
    noErrors(c)
    local list = {}
    for i = 1, 5 do list[i] = { started = "arming " .. i, ended = "x", why = "disarmed", bar = {}, press = {}, events = {}, sweep = {} } end
    local saved2 = { options = { auto = false }, watch = list }
    local c2, P2 = new({ saved = saved2 })
    eq(#saved2.watch, 3, "trimmed to 3")
    eq(saved2.watch[1].started, "arming 3", "the oldest are dropped")
    c2:advance(5)
    P2.WatchArm()
    eq(#saved2.watch, 3, "still 3 after a new arming")
    eq(saved2.watch[1].started, "arming 4")
    eq(saved2.watch[3], P2.WatchCurrent())
    noErrors(c2)
    local saved3 = { options = { auto = false }, watch = "broken" }
    local c3 = new({ saved = saved3 })
    eq(type(saved3.watch), "table")
    noErrors(c3)
end)

test("clear: refused in a fight", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    P.RunOne(P.trialById["own.show"])
    eq(cell(saved, "own.show", KEY_PRESS), "allowed")
    c:enterCombat(); c:advance(1)
    eq(P.ClearSaved(), false)
    eq(P.ClearSaved(), false, "a second tap in a fight is refused too")
    eq(cell(saved, "own.show", KEY_PRESS), "allowed", "nothing cleared")
    check(P.status:find("out of a fight", 1, true), P.status)
    noErrors(c)
end)

test("clear: first tap only arms, second within 5 s clears, after 5 s starts over", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    P.RunOne(P.trialById["own.show"])
    local changed = 0
    P.OnWatchChanged = function() changed = changed + 1 end
    eq(P.ClearSaved(), false, "the first tap only arms")
    eq(P.ClearPending(), true)
    eq(cell(saved, "own.show", KEY_PRESS), "allowed", "nothing cleared yet")
    c:advance(5.5)
    eq(P.ClearPending(), false, "after 5 seconds it starts over")
    check(changed >= 2, "the panel is told when it starts over")
    eq(P.ClearSaved(), false, "a tap after the 5 seconds arms again")
    c:advance(3)
    local ok = P.ClearSaved()
    eq(ok, true, "the second tap within 5 seconds clears")
    eq(P.ClearPending(), false)
    eq(next(saved.results), nil, "results emptied")
    eq(next(saved.last), nil)
    eq(next(saved.details), nil)
    eq(next(saved.situations), nil)
    eq(#saved.watch, 0)
    eq(#saved.perf.runs, 0)
    check(#saved.trials >= 40, "the trial list stays")
    eq(countLog(saved, "saved results cleared"), 1)
    noErrors(c)
end)

test("clear: options kept", function()
    local saved = { options = { auto = false, risky = true, vendor = false } }
    local c, P = new({ saved = saved })
    c:advance(5)
    P.RunOne(P.trialById["own.show"])
    P.ClearSaved(); c:advance(1); P.ClearSaved()
    eq(next(saved.results), nil)
    eq(saved.options.risky, true); eq(saved.options.vendor, false); eq(saved.options.auto, false)
    noErrors(c)
end)

test("clear: stops recording and watchers first", function()
    local c, P, db = newPerf()
    c:advance(20)
    eq(P.Recording(), true)
    P.WatchArm()
    local cur = P.WatchCurrent()
    eq(#db.perf.runs, 1)
    P.ClearSaved(); c:advance(1); P.ClearSaved()
    eq(P.Recording(), false, "the recording stopped first")
    eq(P.WatchArmed(), false, "the watchers stopped first")
    eq(cur.why, "cleared")
    eq(#db.perf.runs, 0)
    eq(#db.watch, 0)
    c:advance(60)
    eq(#db.perf.runs, 0, "no sample writes into the cleared table")
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    eq(#db.watch, 0)
    -- A guided trial waiting: called off and its frame put back before the clear.
    local saved = riskySaved()
    local c2, P2 = new({ saved = saved })
    c2:advance(5)
    P2.StartGuided(P2.trialById["bars.fadecast"]); c2:advance(1.7)
    eq(mainBar(c2):GetAlpha(), 0)
    P2.ClearSaved(); c2:advance(1); P2.ClearSaved()
    eq(mainBar(c2):GetAlpha(), 1, "put back first")
    eq(next(saved.guided), nil)
    noErrors(c); noErrors(c2)
end)

local function anchorBar(c, key) return c.env.GamepadMainActionBarFrame.PageUnit[key].Bar end

test("watch: bar callback names each anchor's bar", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    eq(#c.barCallbacks, 0, "no callback before Arm")
    P.WatchArm()
    eq(#c.barCallbacks, 1, "the callback is set on the first Arm")
    check(type(c.barCallbacks[1].owner) == "table", "the owner is a table of ours")
    local pageUnit = c.env.GamepadMainActionBarFrame.PageUnit
    c:setActiveBar(anchorBar(c, "LeftCenteredAnchor")); c:advance(1)
    c:setActiveBar(anchorBar(c, "RightCenteredAnchor"))
    c:setActiveBar(anchorBar(c, "BottomCenteredAnchor"))
    c:setActiveBar(pageUnit.TopCenteredAnchor.PossessBar)
    c:setActiveBar(anchorBar(c, "TopCenteredAnchor"))
    c:enterCombat()
    c:setActiveBar(anchorBar(c, "LeftCenteredAnchor"))
    c:setActiveBar(anchorBar(c, "TopCenteredAnchor"))
    c:leaveCombat()
    local cur = P.WatchCurrent()
    eq(cur.bar.left.o, 1); eq(cur.bar.left.c, 1)
    eq(cur.bar.right.o, 1); eq(cur.bar.both.o, 1); eq(cur.bar.other.o, 1)
    eq(cur.bar.main.o, 1); eq(cur.bar.main.c, 1)
    eq(#cur.bar.first, 7)
    eq(cur.bar.first[1], "t=0;left;o")
    eq(cur.bar.first[2], "t=1;right;o")
    eq(cur.bar.first[6], "t=1;left;c")
    -- At most 20 kept in order; the counts go on.
    for _ = 1, 30 do c:setActiveBar(anchorBar(c, "RightCenteredAnchor")) end
    eq(#cur.bar.first, 20)
    eq(cur.bar.right.o, 31)
    -- A second arming in the same session: the callback is not set twice, and counts go to the new one.
    P.WatchDisarm()
    c:setActiveBar(anchorBar(c, "LeftCenteredAnchor"))
    eq(cur.bar.left.o, 1, "nothing counted while not armed")
    P.WatchArm()
    eq(#c.barCallbacks, 1)
    c:setActiveBar(anchorBar(c, "LeftCenteredAnchor"))
    eq(P.WatchCurrent().bar.left.o, 1)
    eq(cur.bar.left.o, 1)
    for _, v in ipairs(dump(saved.watch)) do check(not v:find("table: ", 1, true), "no frame stored: " .. v) end
    eq(c:callsTo("GamepadBar.PageUnit:SetAlpha")[1], nil, "PageUnit's alpha is never written")
    noErrors(c)
end)

test("watch: GetActiveBar secret and error told apart", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    P.WatchArm()
    local hidden = {}
    c.world.secrets[hidden] = true
    c:setActiveBar(hidden)
    c.world.activeBarError = true
    c:setActiveBar(anchorBar(c, "LeftCenteredAnchor"))
    c.world.activeBarError = false
    c:setActiveBar(nil)
    local cur = P.WatchCurrent()
    eq(cur.bar.secret.o, 1)
    eq(cur.bar.error.o, 1)
    eq(cur.bar.other.o, 1, "no bar at all is 'other'")
    eq(cur.bar.left, nil)
    noErrors(c)
end)

test("watch: no PageUnit", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved, setup = function(cl) rawset(cl.env, "GamepadMainActionBarFrame", nil) end })
    c:advance(5)
    eq(P.WatchArm(), true, "Arm still works")
    local cur = P.WatchCurrent()
    eq(cur.bar.missing, "PageUnit")
    eq(cur.press.missing, "the bars' buttons")
    eq(cur.sweep.missing, "the main bar")
    c:enterCombat()
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    c:advance(2)
    eq(cur.events.ACTIONBAR_UPDATE_COOLDOWN.c, 1, "the events are still counted")
    eq(cur.sweep.result, nil)
    c:leaveCombat()
    P.WatchDisarm()
    noErrors(c)
    -- PageUnit there, without the callback method.
    local saved2 = watchSaved()
    local c2, P2 = new({ saved = saved2, setup = function(cl)
        rawset(cl.env.GamepadMainActionBarFrame.PageUnit, "RegisterActiveActionBarUpdatedCallback", nil)
    end })
    c2:advance(5)
    P2.WatchArm()
    eq(P2.WatchCurrent().bar.missing, "RegisterActiveActionBarUpdatedCallback")
    eq(P2.WatchCurrent().press.missing, nil)
    noErrors(c2)
end)

test("watch: press hook counts down and up per bar, in and out of a fight", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    c:pressButton("TopCenteredAnchor", 5, true)
    P.WatchArm()
    local cur = P.WatchCurrent()
    eq(cur.press.hooked, 32, "the eight buttons of each of the four bars")
    c:pressButton("TopCenteredAnchor", 5, true); c:pressButton("TopCenteredAnchor", 5, false)
    c:pressButton("BottomCenteredAnchor", 1, true)
    c:enterCombat()
    c:pressButton("LeftCenteredAnchor", 8, true); c:pressButton("LeftCenteredAnchor", 8, false)
    c:pressButton("TopCenteredAnchor", 2, true)
    c:leaveCombat()
    eq(cur.press.main.down.o, 1); eq(cur.press.main.up.o, 1); eq(cur.press.main.down.c, 1)
    eq(cur.press.both.down.o, 1)
    eq(cur.press.left.down.c, 1); eq(cur.press.left.up.c, 1)
    eq(cur.press.right, nil)
    eq(cur.press.kind, "boolean")
    eq(c.pressedStyles, 7, "the game's own style still runs")
    -- A secret or other value is counted apart, never compared.
    local hidden = {}
    c.world.secrets[hidden] = true
    c:pressButton("RightCenteredAnchor", 1, hidden)
    c:pressButton("RightCenteredAnchor", 1, 1)
    eq(cur.press.right.other.o, 2)
    eq(cur.press.kind, "boolean / secret / other")
    noErrors(c)
end)

test("watch: press hooks installed once", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    eq(P.WatchInstallPressHooks(), 32)
    eq(P.WatchInstallPressHooks(), 32, "a second call hooks nothing more")
    P.WatchArm(); P.WatchDisarm(); P.WatchArm()
    c:pressButton("TopCenteredAnchor", 1, true)
    eq(P.WatchCurrent().press.main.down.o, 1, "one press counts once")
    -- A button without the method is left alone.
    local saved2 = watchSaved()
    local c2, P2 = new({ saved = saved2, setup = function(cl)
        rawset(cl.barButtons.TopCenteredAnchor[1], "ApplyPressedStyle", nil)
    end })
    c2:advance(5)
    eq(P2.WatchInstallPressHooks(), 31)
    noErrors(c); noErrors(c2)
end)

test("watch: sweep runs once per arming, only in a fight, at most one check per second, stores no value", function()
    local saved = watchSaved()
    local checks = 0
    local c, P = new({ saved = saved, setup = function(cl)
        local get = cl.env.C_ActionBar.GetActionCooldown
        rawset(cl.env.C_ActionBar, "GetActionCooldown", function(...) checks = checks + 1 return get(...) end)
    end })
    c:advance(5)
    P.WatchArm()
    local cur = P.WatchCurrent()
    -- Out of a fight: nothing.
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    eq(checks, 0, "no check out of a fight")
    eq(#c.cooldownCalls, 0)
    -- In a fight, nothing on cooldown: checked, nothing done.
    c.world.actions[2].duration = 0
    c:enterCombat()
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    check(checks > 0, "checked in a fight")
    eq(#c.cooldownCalls, 0)
    local after = checks
    c.world.actions[2].duration = 8
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    eq(checks, after, "a second event within a second is not checked")
    c:advance(1.1)
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    eq(#c.cooldownCalls, 1, "the sweep ran")
    eq(c.cooldownCalls[1].method, "SetCooldownFromDurationObject")
    eq(c.cooldownCalls[1].frame, c.cooldowns[1].frame, "on square 1")
    check(button(c, "PocketProbeSweep"):IsShown(), "the squares show")
    eq(cur.sweep.result, "allowed")
    eq(cur.sweep.shownByItself, "yes")
    eq(cur.sweep.durClass, "readable")
    eq(cur.sweep.screenshot, "none", "not yet")
    c:advance(1.2)
    eq(c.shots, 1)
    eq(cur.sweep.screenshot, "taken")
    c:advance(8)
    check(not button(c, "PocketProbeSweep"):IsShown(), "hidden after 8 seconds")
    after = checks
    c:fire("ACTIONBAR_UPDATE_COOLDOWN"); c:advance(1.5); c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    eq(#c.cooldownCalls, 1, "once per arming")
    eq(checks, after, "done until the next Arm")
    for k, v in pairs(cur.sweep) do check(type(v) == "string" or k == "t", "only words are stored: " .. k) end
    c:leaveCombat()
    -- The next arming runs it again; a refusal is the result.
    P.WatchDisarm()
    c.world.cooldownModes.SetCooldownFromDurationObject = "blocked"
    P.WatchArm()
    c:enterCombat()
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    eq(#c.cooldownCalls, 2)
    eq(P.WatchCurrent().sweep.result, "blocked")
    eq(cell(saved, "after.SetCooldownFromDurationObject", KEY_FIGHT), nil, "not counted as an afterwards refusal")
    noErrors(c)
end)

test("watch: screenshot missing changes nothing else", function()
    local saved = watchSaved()
    local c, P = new({ saved = saved, setup = function(cl) rawset(cl.env, "Screenshot", nil) end })
    c:advance(5)
    P.WatchArm()
    c:enterCombat()
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    c:advance(2)
    local cur = P.WatchCurrent()
    eq(cur.sweep.result, "allowed")
    eq(cur.sweep.shownByItself, "yes")
    eq(cur.sweep.screenshot, "none")
    eq(c.shots, nil)
    noErrors(c)
end)

---------------------------------------------------------------------------
-- Probe 0.7.0: the two guided bar trials
---------------------------------------------------------------------------

local NEXT_START = "Main bar will vanish in your next fight. Just play."
local NEXT_BIG = "Did your spells cast while the bar was invisible?"
local WHEELS_BIG = "Bars faded. Open the pet wheel (LB+LT), then a spell wheel. Then tap Probe."
local FOUR = { "TopCenteredAnchor", "LeftCenteredAnchor", "RightCenteredAnchor", "BottomCenteredAnchor" }

local function startFadeNext(c, P)
    P.StartGuided(P.trialById["bars.fadenext"])
    c:advance(0.5)
end

test("fadenext: refused in a fight", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    local t = P.trialById["bars.fadenext"]
    eq(t.area, "Blizzard windows"); eq(t.kind, "guided"); check(t.manual and t.risky, "manual and risky")
    eq(t.short, "Fade for next fight")
    c:enterCombat(); c:advance(1)
    P.StartGuided(t)
    eq(saved.guided["bars.fadenext"], nil)
    check(P.status:find("bars.fadenext: not started, in combat", 1, true), P.status)
    eq(mainBar(c):GetAlpha(), 1)
    noErrors(c)
end)

test("fadenext: fades on fight start, reads back, puts back on fight end, then asks", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    c:click(showTrial(c, P, "bars.fadenext").ppRun)
    check(not rawget(c.env, "PocketProbePanel"):IsShown(), "the panel closes at Start")
    local g = saved.guided["bars.fadenext"]
    eq(g.stage, "waitfight")
    eq(shownText(c, "PocketProbeBigMessage"), NEXT_START)
    check(P.status:find("Fade for next fight is waiting for your next fight", 1, true), P.status)
    c:advance(3.5)
    eq(shownText(c, "PocketProbeBigMessage"), NEXT_START, "still up before 4 seconds")
    c:advance(0.6)
    eq(shownText(c, "PocketProbeBigMessage"), nil, "gone after 4 seconds")
    eq(mainBar(c):GetAlpha(), 1, "nothing faded before the fight")
    local row = showTrial(c, P, "bars.fadenext")
    eq(row.ppRun.ppLabel:GetText(), "Cancel")
    check(not row.ppAnswer[1]:IsShown(), "no answers while it waits")
    c:click(button(c, "PocketProbeCloseButton"))
    c:advance(30)
    c:enterCombat()
    eq(mainBar(c):GetAlpha(), 0, "faded as the fight starts")
    eq(g.stage, "infight")
    c:advance(8)
    eq(mainBar(c):GetAlpha(), 0, "still faded in the fight")
    c:leaveCombat()
    eq(mainBar(c):GetAlpha(), 1, "put back as the fight ends")
    eq(g.stage, "ask")
    eq(shownText(c, "PocketProbeBigMessage"), NEXT_BIG)
    row = showTrial(c, P, "bars.fadenext")
    eq(row.ppAnswer[1].ppLabel:GetText(), "Yes, they cast"); eq(row.ppAnswer[2].ppLabel:GetText(), "No")
    c:click(row.ppAnswer[1])
    eq(cell(saved, "bars.fadenext", KEY_PRESS), "yes, they cast")
    local msg = saved.last["bars.fadenext"].message
    for _, part in ipairs({ "main bar see-through 1 -> 0", "still invisible at the end: yes", "main bar presses in the fight: 0",
        "casts in the fight: 0", "old values put back" }) do
        check(msg:find(part, 1, true), "message lacks " .. part .. ": " .. msg)
    end
    eq(saved.guided["bars.fadenext"], nil)
    eq(shownText(c, "PocketProbeBigMessage"), nil)
    -- The game showed the bar again by itself in the fight: noted.
    startFadeNext(c, P)
    c:enterCombat(); mainBar(c):SetAlpha(0.4); c:leaveCombat()
    P.AnswerGuided(P.trialById["bars.fadenext"], 2)
    eq(saved.last["bars.fadenext"].result, "no")
    check(saved.last["bars.fadenext"].message:find("still invisible at the end: no", 1, true), saved.last["bars.fadenext"].message)
    eq(mainBar(c):GetAlpha(), 1)
    noErrors(c)
end)

test("fadenext: refused write stored at once and put back when the fight ends", function()
    -- The game refuses the fade: the result at once, nothing asked, nothing left changed.
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    startFadeNext(c, P)
    local bar = mainBar(c)
    local set = bar.SetAlpha
    rawset(bar, "SetAlpha", function(self, a)
        if a == 0 then c:fire("ADDON_ACTION_BLOCKED", "PocketProbe", "SetAlpha()") return end
        return set(self, a)
    end)
    c:enterCombat()
    eq(saved.last["bars.fadenext"].result, "blocked")
    eq(detail(saved, "bars.fadenext").func, "SetAlpha()")
    eq(saved.guided["bars.fadenext"], nil, "nothing to ask")
    eq(bar:GetAlpha(), 1)
    c:leaveCombat(); c:advance(2)
    eq(shownText(c, "PocketProbeBigMessage"), nil)
    noErrors(c)
    -- The write leaves it at 0.5: "no effect", and it goes back.
    local saved2 = riskySaved()
    local c2, P2 = new({ saved = saved2 })
    c2:advance(5)
    startFadeNext(c2, P2)
    local bar2 = mainBar(c2)
    local set2 = bar2.SetAlpha
    rawset(bar2, "SetAlpha", function(self, a) return set2(self, a == 0 and 0.5 or a) end)
    c2:enterCombat()
    eq(saved2.last["bars.fadenext"].result, "no effect")
    check(saved2.last["bars.fadenext"].message:find("still 0.5 after setting it to 0", 1, true), saved2.last["bars.fadenext"].message)
    eq(bar2:GetAlpha(), 1, "put back")
    eq(saved2.guided["bars.fadenext"], nil)
    noErrors(c2)
    -- Faded; a put-back the game refuses in the fight is held and done when the fight ends.
    local saved3 = riskySaved()
    local c3, P3 = new({ saved = saved3 })
    c3:advance(5)
    startFadeNext(c3, P3)
    c3:enterCombat()
    eq(mainBar(c3):GetAlpha(), 0)
    c3.world.barAlphaBlocked = true
    P3.CancelGuided(P3.trialById["bars.fadenext"])
    eq(saved3.guided["bars.fadenext"].stage, "putback")
    eq(mainBar(c3):GetAlpha(), 0, "held in the fight")
    c3.world.barAlphaBlocked = false
    c3:leaveCombat(); c3:advance(2)
    eq(mainBar(c3):GetAlpha(), 1, "put back when the fight ends")
    eq(saved3.guided["bars.fadenext"], nil)
    noErrors(c3)
end)

test("fadenext: counts presses and casts", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    startFadeNext(c, P)
    c:pressButton("TopCenteredAnchor", 5, true); c:pressButton("TopCenteredAnchor", 5, false)
    c:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
    c:enterCombat()
    c:pressButton("TopCenteredAnchor", 5, true); c:pressButton("TopCenteredAnchor", 5, false)
    c:pressButton("TopCenteredAnchor", 6, true); c:pressButton("TopCenteredAnchor", 6, false)
    c:pressButton("LeftCenteredAnchor", 1, true)
    c:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 133)
    c:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 133)
    c:fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-4", 99)
    local hidden = {}
    c.world.secrets[hidden] = true
    c:fire("UNIT_SPELLCAST_SUCCEEDED", hidden, "Cast-5", 1)
    c:leaveCombat()
    c:pressButton("TopCenteredAnchor", 5, true)
    c:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", 133)
    P.AnswerGuided(P.trialById["bars.fadenext"], 1)
    local msg = saved.last["bars.fadenext"].message
    check(msg:find("main bar presses in the fight: 2", 1, true), msg)
    check(msg:find("casts in the fight: 2", 1, true), msg)
    check(msg:find("casts unreadable: 1", 1, true), msg)
    check(not msg:find("Cast-", 1, true) and not msg:find("133", 1, true), "no cast or spell is stored: " .. msg)
    local rec
    for _, r in ipairs(c:frames()) do if r.events and r.events.UNIT_SPELLCAST_SUCCEEDED then rec = r end end
    eq(rec, nil, "the cast event is only listened to during the fight")
    noErrors(c)
end)

test("fadenext: Cancel, Stop, logout put back", function()
    for _, way in ipairs({ "cancel", "stop", "logout" }) do
        for _, when in ipairs({ "before", "in" }) do
            local saved = riskySaved()
            local c, P = new({ saved = saved })
            c:advance(5)
            startFadeNext(c, P)
            if when == "in" then c:enterCombat(); eq(mainBar(c):GetAlpha(), 0) end
            if way == "stop" then P.Stop()
            elseif way == "logout" then c:fire("PLAYER_LOGOUT")
            else P.CancelGuided(P.trialById["bars.fadenext"]) end
            eq(mainBar(c):GetAlpha(), 1, way .. " " .. when)
            eq(saved.guided["bars.fadenext"], nil, way .. " " .. when)
            eq(saved.results["bars.fadenext"], nil, way .. ": no answer")
            eq(shownText(c, "PocketProbeBigMessage"), nil, way .. " " .. when)
            if when == "in" then c:leaveCombat() end
            c:advance(2)
            eq(mainBar(c):GetAlpha(), 1, way .. " " .. when .. ": nothing faded afterwards")
            eq(shownText(c, "PocketProbeBigMessage"), nil, way .. " " .. when .. ": no question afterwards")
            noErrors(c, way .. " " .. when)
        end
    end
end)

test("fadenext: reload during fight puts back on next login", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    startFadeNext(c, P)
    c:enterCombat()
    eq(mainBar(c):GetAlpha(), 0)
    -- The reload: the logout could not put it back (the game went down); the next load calls it off.
    local c2, P2 = new({ saved = saved })
    eq(saved.guided["bars.fadenext"], nil)
    eq(countLog(saved, "bars.fadenext: called off; the reload put the main bar's see-through back"), 1)
    eq(mainBar(c2):GetAlpha(), 1)
    c2:enterCombat(); c2:leaveCombat(); c2:advance(2)
    eq(mainBar(c2):GetAlpha(), 1, "nothing waits for a fight after the reload")
    eq(shownText(c2, "PocketProbeBigMessage"), nil)
    noErrors(c2)
    -- A reload before any fight: called off too ("until a reload").
    local saved3 = riskySaved()
    local c3, P3 = new({ saved = saved3 })
    c3:advance(5)
    startFadeNext(c3, P3)
    local c4 = new({ saved = saved3 })
    eq(saved3.guided["bars.fadenext"], nil)
    eq(countLog(saved3, "bars.fadenext: called off by the reload"), 1)
    noErrors(c4)
end)

test("fadenext: never touches PageUnit", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    startFadeNext(c, P)
    c:enterCombat(); c:advance(3); c:leaveCombat()
    P.AnswerGuided(P.trialById["bars.fadenext"], 1)
    check(#c:callsTo("GamepadBar.TopCenteredAnchor.Bar:SetAlpha") >= 2, "the main bar was faded and put back")
    eq(#c:callsTo("GamepadBar.PageUnit:SetAlpha"), 0, "PageUnit's alpha is never written")
    eq(#c:callsTo("GamepadBar.TopCenteredAnchor:SetAlpha"), 0, "nor the anchor's")
    noErrors(c)
end)

test("wheels: refused in a fight", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    local t = P.trialById["bars.wheels"]
    eq(t.area, "Blizzard windows"); eq(t.short, "Wheels on a faded bar"); check(t.closePanel and t.risky and t.manual, "flags")
    c:enterCombat(); c:advance(1)
    P.StartGuided(t)
    eq(saved.guided["bars.wheels"], nil)
    for _, key in ipairs(FOUR) do eq(anchorBar(c, key):GetAlpha(), 1) end
    noErrors(c)
end)

test("wheels: fades four and reads back", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    c:click(showTrial(c, P, "bars.wheels").ppRun)
    check(not rawget(c.env, "PocketProbePanel"):IsShown(), "the panel closes at Start")
    for _, key in ipairs(FOUR) do eq(anchorBar(c, key):GetAlpha(), 0, key) end
    local g = saved.guided["bars.wheels"]
    eq(g.stage, "ask")
    check(g.notes:find("four bars' see-through 1, 1, 1, 1 -> 0", 1, true), g.notes)
    eq(shownText(c, "PocketProbeBigMessage"), WHEELS_BIG)
    local row = showTrial(c, P, "bars.wheels")
    eq(row.ppAnswer[1].ppLabel:GetText(), "Wheel visible"); eq(row.ppAnswer[2].ppLabel:GetText(), "Wheel hidden")
    eq(#c:callsTo("GamepadBar.PageUnit:SetAlpha"), 0, "PageUnit's alpha is never written")
    noErrors(c)
    -- One bar does not take the fade: "no effect", the others go back.
    local saved2 = riskySaved()
    local c2, P2 = new({ saved = saved2, setup = function(cl)
        rawset(cl.env.GamepadMainActionBarFrame.PageUnit.RightCenteredAnchor.Bar, "SetAlpha", function() end)
    end })
    c2:advance(5)
    P2.StartGuided(P2.trialById["bars.wheels"])
    eq(saved2.last["bars.wheels"].result, "no effect")
    check(saved2.last["bars.wheels"].message:find("right bar still 1", 1, true), saved2.last["bars.wheels"].message)
    for _, key in ipairs(FOUR) do eq(anchorBar(c2, key):GetAlpha(), 1, key .. " put back") end
    eq(saved2.guided["bars.wheels"], nil)
    noErrors(c2)
end)

test("wheels: records up to two wheels (centre, size, effective alpha, shown) 0.2 s after open", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    c:openWheel("pet"); c:advance(1); c:closeWheel("pet")       -- before Start: not recorded
    P.StartGuided(P.trialById["bars.wheels"])
    c:openWheel("pet")
    c:advance(0.3)
    c:closeWheel("pet")
    c:openWheel("spell")
    c:advance(0.3)
    c:openWheel("petspell")                                      -- a third: not recorded
    c:advance(1)
    P.AnswerGuided(P.trialById["bars.wheels"], 1)
    eq(cell(saved, "bars.wheels", KEY_PRESS), "wheel visible")
    local msg = saved.last["bars.wheels"].message
    for _, part in ipairs({ "wheels seen: 2", "wheel 1 (pet wheel): centre 544,189, size 160 x 160, effective alpha 1, shown yes",
        "wheel 2 (bar wheel): centre 683,250, size 175 x 175, effective alpha 1, shown yes", "screenshot: taken",
        "bars still invisible at the answer: 4 of 4", "old values put back" }) do
        check(msg:find(part, 1, true), "message lacks " .. part .. ": " .. msg)
    end
    check(not msg:find("wheel 3", 1, true), msg)
    for _, key in ipairs(FOUR) do eq(anchorBar(c, key):GetAlpha(), 1, key .. " put back") end
    -- After the answer the hooks do nothing.
    c:openWheel("spell"); c:advance(1)
    noErrors(c)
    -- No wheel opened: said so.
    P.StartGuided(P.trialById["bars.wheels"])
    P.AnswerGuided(P.trialById["bars.wheels"], 2)
    check(saved.last["bars.wheels"].message:find("wheels seen: 0", 1, true), saved.last["bars.wheels"].message)
    noErrors(c)
end)

test("wheels: one screenshot 0.5 s after the first wheel", function()
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    P.StartGuided(P.trialById["bars.wheels"])
    eq(c.shots, nil, "no picture at Start")
    c:openWheel("pet")
    c:advance(0.3)
    eq(c.shots, nil)
    c:advance(0.3)
    eq(c.shots, 1, "one picture half a second after the first wheel")
    c:openWheel("spell"); c:advance(2)
    eq(c.shots, 1, "none for the second wheel")
    noErrors(c)
    -- Without Screenshot nothing else changes.
    local saved2 = riskySaved()
    local c2, P2 = new({ saved = saved2, setup = function(cl) rawset(cl.env, "Screenshot", nil) end })
    c2:advance(5)
    P2.StartGuided(P2.trialById["bars.wheels"])
    c2:openWheel("pet"); c2:advance(1)
    P2.AnswerGuided(P2.trialById["bars.wheels"], 1)
    local msg = saved2.last["bars.wheels"].message
    check(msg:find("wheels seen: 1", 1, true) and msg:find("screenshot: none", 1, true), msg)
    noErrors(c2)
end)

test("wheels: puts four back on answer, Cancel, Stop, logout", function()
    for _, way in ipairs({ "answer", "cancel", "stop", "logout" }) do
        local saved = riskySaved()
        local c, P = new({ saved = saved })
        c:advance(5)
        P.StartGuided(P.trialById["bars.wheels"])
        for _, key in ipairs(FOUR) do eq(anchorBar(c, key):GetAlpha(), 0) end
        if way == "answer" then P.AnswerGuided(P.trialById["bars.wheels"], 2)
        elseif way == "stop" then P.Stop()
        elseif way == "logout" then c:fire("PLAYER_LOGOUT")
        else P.CancelGuided(P.trialById["bars.wheels"]) end
        for _, key in ipairs(FOUR) do eq(anchorBar(c, key):GetAlpha(), 1, way .. ": " .. key) end
        eq(saved.guided["bars.wheels"], nil, way)
        eq(shownText(c, "PocketProbeBigMessage"), nil, way)
        noErrors(c, way)
    end
    -- A reload while it waits: called off (the reload resets the bars).
    local saved = riskySaved()
    local c, P = new({ saved = saved })
    c:advance(5)
    P.StartGuided(P.trialById["bars.wheels"])
    local c2 = new({ saved = saved })
    eq(saved.guided["bars.wheels"], nil)
    eq(countLog(saved, "bars.wheels: called off; the reload put the four bars' see-through back"), 1)
    noErrors(c2)
end)

---------------------------------------------------------------------------
-- Probe 0.7.0: the floating Fight button and the recording's pause
---------------------------------------------------------------------------

local function floatFight(c) return button(c, "PocketProbeFloatFight") end

-- Advances until no pass runs (at most a minute).
local function untilIdle(c, P)
    for _ = 1, 600 do
        if not P.Busy() then return end
        c:advance(0.1)
    end
    error("the pass did not end", 2)
end

test("fight button: hidden out of a fight", function()
    local c, P, db = newPerf()
    c:advance(5)
    eq(P.Recording(), true)
    P.WatchArm()
    local f = floatFight(c)
    check(not f:IsShown(), "hidden out of a fight while recording and armed")
    eq(c._state(f).strata, "HIGH")
    eq(c._state(f).parent, c.UIParent)
    check(not f:IsProtected(), "a plain frame")
    c:enterCombat(); c:advance(1)
    check(f:IsShown(), "shown in the fight")
    c:leaveCombat()
    check(not f:IsShown(), "hidden as the fight ends")
    noErrors(c)
end)

test("fight button: hidden in a fight when not armed and not recording", function()
    local c, P = new({ saved = watchSaved() })
    c:advance(5)
    eq(P.Recording(), false)
    c:enterCombat(); c:advance(1)
    check(not floatFight(c):IsShown(), "never shown in normal play")
    c:leaveCombat()
    -- Armed, then disarmed in the fight: it goes.
    P.WatchArm()
    c:enterCombat()
    check(floatFight(c):IsShown())
    P.WatchDisarm()
    check(not floatFight(c):IsShown(), "hidden once neither armed nor recording")
    noErrors(c)
end)

test("fight button: shown in a fight when armed, and when recording", function()
    local c, P = new({ saved = watchSaved() })
    c:advance(5)
    P.WatchArm()
    c:enterCombat()
    local f = floatFight(c)
    check(f:IsShown(), "shown when armed")
    eq(P.floatFight.label:GetText(), "Fight")
    check(f:GetHeight() >= 40, "big enough for a finger")
    noErrors(c)
    local c2, P2 = newPerf()
    c2:advance(5)
    eq(P2.WatchArmed(), false)
    c2:enterCombat()
    check(floatFight(c2):IsShown(), "shown when recording")
    P2.StopRecording()
    check(not floatFight(c2):IsShown(), "hidden when the recording stops in the fight")
    noErrors(c2)
end)

test("fight button: placed beside Stop away from the PE button, or in Stop's spot", function()
    local c, P = newPerf()
    c:advance(5)
    c:enterCombat()
    local f, stop = floatFight(c), button(c, "PocketProbeRecStopButton")
    local fl, fr, ft, fb = c._rect(f)
    local sl, sr, st, sb = c._rect(stop)
    local hl = c._rect(c.hub)
    check(sl < hl, "Stop is left of the PE button (the PE button is on the right)")
    check(fr <= sl + 0.01, "Fight is left of Stop, away from the PE button")
    check(math.abs((ft + fb) / 2 - (st + sb) / 2) < 0.5, "on the same line")
    check(math.abs((fr - fl) - (sr - sl)) < 0.5 and math.abs((ft - fb) - (st - sb)) < 0.5, "as big as Stop")
    noErrors(c)
    -- No recording (armed only): Fight takes Stop's spot.
    local c2, P2 = newPerf()
    c2:advance(5)
    P2.StopRecording()
    P2.WatchArm()
    c2:enterCombat()
    local f2 = floatFight(c2)
    local l2, r2, t2, b2 = c2._rect(f2)
    eq(math.floor(l2 + 0.5), math.floor(sl + 0.5), "in Stop's spot: left")
    eq(math.floor(t2 + 0.5), math.floor(st + 0.5), "in Stop's spot: top")
    noErrors(c2)
    -- The PE button on the left: Fight right of Stop.
    local c3 = newPerf({ setup = function(cl)
        local hub = rawget(cl.env, "PocketEssentialsHubButton")
        hub:ClearAllPoints(); hub:SetPoint("TOPLEFT", cl.env.UIParent, "TOPLEFT", 20, -200)
    end })
    c3:advance(5)
    c3:enterCombat()
    local a = c3._rect(floatFight(c3))
    local _, sr3 = c3._rect(button(c3, "PocketProbeRecStopButton"))
    check(a >= sr3 - 0.01, "Fight is right of Stop when the PE button is on the left")
    noErrors(c3)
    -- No PE button: Stop above the red dot, Fight left of Stop.
    local c4 = newPerf({ noButton = true })
    c4:advance(5)
    c4:enterCombat()
    local _, r4 = c4._rect(floatFight(c4))
    local l4 = c4._rect(button(c4, "PocketProbeRecStopButton"))
    check(r4 <= l4 + 0.01, "Fight left of Stop above the dot")
    noErrors(c4)
end)

test("fight button: tap during a recording pauses, runs the pass, resumes; next sample has dt=0 and p", function()
    local c, P, db = newPerf({ saved = { options = { auto = false } } })
    c:advance(20)
    local r = lastRun(db)
    c:enterCombat(); c:advance(9)
    -- The ticker's next turn (30 s after the start) falls inside the pass.
    local n0, at = #r.samples, c.now
    c:click(floatFight(c))
    eq(P.Recording(), true, "still recording")
    check(P.Busy(), "the pass runs")
    check(cell(db, "bars.spells", KEY_FIGHT_PRESS), "the first trial ran inside the tap")
    while P.Busy() do
        c:advance(0.1)
        if P.Busy() then eq(#r.samples, n0, "no sample while the pass runs") end
        check(c.now - at < 60, "the pass ends")
    end
    check(c.now - at > 2, "the pass took a while")
    -- No sample while the pass ran; then one that marks the pause.
    eq(#r.samples, n0 + 1, "one sample: the one after the pause")
    local s = fields(r.samples[#r.samples])
    eq(s.dt, "0")
    check(s.a:find("p", 1, true), "the pause's letter: " .. s.a)
    check(s.a:find("c", 1, true), "still in the fight: " .. s.a)
    eq(s.pe, nil, "no work counted for the pause")
    c:advance(16)
    local s2 = fields(r.samples[#r.samples])
    eq(#r.samples, n0 + 2)
    check(tonumber(s2.dt) > 0 and tonumber(s2.dt) <= 15.05, "the next sample covers only the time after the pause: " .. s2.dt)
    check(not s2.a:find("p", 1, true), "only the one sample has p")
    check(countLog(db, "recording paused for the fight tests"), "logged")
    noErrors(c)
end)

test("fight button: Run all safe still refused during a recording", function()
    local c, P, db = newPerf({ saved = { options = { auto = false } } })
    c:advance(5)
    c:enterCombat(); c:advance(1)
    P.RunAllSafe(); eq(P.status, "Recording: tap Stop first.")
    P.RunFightTests(); eq(P.status, "Recording: tap Stop first.", "the panel's Fight tests too")
    eq(next(db.results), nil)
    noErrors(c)
end)

test("fight button: second tap during a pass is ignored", function()
    local c, P, db = newPerf({ saved = { options = { auto = false } } })
    c:advance(5)
    c:enterCombat(); c:advance(1)
    c:click(floatFight(c))
    c:advance(0.5)
    c:click(floatFight(c))
    c:advance(0.5)
    c:click(floatFight(c))
    eq(countLog(db, "pass started"), 1, "one pass")
    untilIdle(c, P)
    noErrors(c)
    -- A pass the panel started (no recording): the tap does not take over.
    local c2, P2, db2 = new({ saved = watchSaved() })
    c2:advance(5)
    P2.WatchArm()
    c2:enterCombat(); c2:advance(1)
    P2.RunFightTests()
    c2:advance(0.5)
    c2:click(floatFight(c2))
    eq(countLog(db2, "pass started"), 1, "the running pass is left alone")
    eq(countLog(db2, "pass stopped"), 0)
    noErrors(c2)
end)

test("fight button: tick shown 3 s then usable again", function()
    local c, P, db = newPerf({ saved = { options = { auto = false } } })
    c:advance(5)
    c:enterCombat(); c:advance(1)
    local f = P.floatFight
    check(not f.tick:IsShown(), "no tick before")
    c:click(floatFight(c))
    untilIdle(c, P)
    check(f.tick:IsShown(), "the tick shows after the pass")
    eq(f.tick:GetAtlas(), "common-icon-checkmark")
    check(not f.label:IsShown(), "the label makes room for it")
    c:click(floatFight(c))
    eq(countLog(db, "pass started"), 1, "a tap while the tick shows does nothing")
    c:advance(3.1)
    check(not f.tick:IsShown(), "gone after 3 seconds")
    check(f.label:IsShown())
    c:click(floatFight(c))
    eq(countLog(db, "pass started"), 2, "a second tap in the same fight runs the pass again")
    untilIdle(c, P)
    noErrors(c)
end)

---------------------------------------------------------------------------
-- Probe 0.7.0: recorder fixes
---------------------------------------------------------------------------

test("perf: memory 0 stored as missing", function()
    local c, P, db = newPerf()
    c.world.perf.memory.PocketEssentials = 0
    c:advance(15.3)
    local r = lastRun(db)
    eq(fields(r.samples[#r.samples]).mem, ",10000,300", "a reading of 0 leaves the field empty")
    c.world.perf.memory.PocketEssentials, c.world.perf.memory.QuestieDB, c.world.perf.memory.PocketProbe = 0, 0, 0
    c:advance(15)
    eq(fields(r.samples[#r.samples]).mem, nil, "no reading at all: no mem field")
    noErrors(c)
end)

test("perf: first sample after a reload has r", function()
    local saved = {}
    local c = newPerf({ saved = saved })
    c:advance(20)
    c:fire("PLAYER_LOGOUT")
    local r = saved.perf.runs[1]
    for _, line in ipairs(r.samples) do check(not fields(line).a:find("r", 1, true), "no r before the reload") end
    local c2 = newPerf({ saved = saved, reload = true, setup = function(cl) cl.now = 1100 end })
    local n = #r.samples
    local s = fields(r.samples[n])
    eq(s.dt, "0")
    check(s.a:find("r", 1, true), "the first sample after the reload has r: " .. s.a)
    c2:advance(15.3)
    check(not fields(r.samples[n + 1]).a:find("r", 1, true), "only that one")
    -- A fresh run (not carried on) has no r.
    local c3, P3, db3 = newPerf()
    check(not fields(lastRun(db3).samples[1]).a:find("r", 1, true), "a new run's first sample has no r")
    noErrors(c); noErrors(c2); noErrors(c3)
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
