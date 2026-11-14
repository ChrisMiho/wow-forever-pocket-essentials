-- Pocket Essentials: core.
-- Namespace, saved variables, module registry, error log, event dispatch,
-- combat queue and the /pe command. Everything a module does goes through an
-- xpcall here, so one broken feature can never stop another or the panel.
local ADDON_NAME, PE = ...

_G.PocketEssentials = PE -- for debugging only; modules use the local

PE.name = ADDON_NAME
PE.modules = {}      -- [key] = module table
PE.moduleList = {}   -- array, sorted by `order`
PE.loggedIn = false
PE.hasQuestieDB = false
PE.questieDBReason = nil
PE.oldQuestDotsLoaded = false
PE.errorSerial = 0   -- goes up by one for every caught error
PE.reloadReasons = {} -- array of { label =, reason = }

local CHAT_TAG = "|cffffd100Pocket Essentials|r: "
local CORE_LABEL = "Pocket Essentials"
local ERROR_CAP = 30
local SIZES = { small = true, medium = true, large = true }

local type, tostring, tonumber, pairs, ipairs, select = type, tostring, tonumber, pairs, ipairs, select
local pcall, xpcall = pcall, xpcall
local tinsert, tremove, tsort = table.insert, table.remove, table.sort

---------------------------------------------------------------------------
-- Chat output
---------------------------------------------------------------------------

function PE:Print(text)
    local msg = CHAT_TAG .. tostring(text)
    local chat = DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage and pcall(chat.AddMessage, chat, msg) then return end
    pcall(print, msg)
end

---------------------------------------------------------------------------
-- Error log (newest first). Kept in memory until the saved variables are
-- loaded, then merged into PE.db.errors.
---------------------------------------------------------------------------

PE.errors = {}
local announced = {} -- [moduleKey] = true: one chat line per feature per session
local inLogError = false

local function ShortPath(text)
    text = text:gsub("Interface[/\\]+AddOns[/\\]+", "")
    return text
end

local function TrimStack(stack)
    if type(stack) ~= "string" then return "" end
    local out, n = {}, 0
    for line in stack:gmatch("[^\r\n]+") do
        line = ShortPath(line:gsub("^%s+", ""))
        if line ~= "" then
            n = n + 1
            out[n] = line:sub(1, 160)
            if n >= 4 then break end
        end
    end
    return table.concat(out, "\n")
end

function PE:ModuleLabel(key)
    local mod = key and self.modules[key]
    if mod and type(mod.label) == "string" then return mod.label end
    return CORE_LABEL
end

local function LogErrorBody(moduleKey, msg, stack)
    if type(moduleKey) ~= "string" or moduleKey == "" then moduleKey = "core" end
    msg = ShortPath(tostring(msg)):sub(1, 300)
    stack = TrimStack(stack)
    PE.errorSerial = PE.errorSerial + 1

    local list, now, isNew = PE.errors, time(), true
    for i = 1, #list do
        local e = list[i]
        if type(e) == "table" and e.module == moduleKey and e.msg == msg then
            e.count = (tonumber(e.count) or 1) + 1
            e.last = now
            if i > 1 then
                tremove(list, i)
                tinsert(list, 1, e)
            end
            isNew = false
            break
        end
    end
    if isNew then
        tinsert(list, 1, { module = moduleKey, msg = msg, stack = stack, count = 1, last = now })
        for i = #list, ERROR_CAP + 1, -1 do list[i] = nil end
    end

    if not announced[moduleKey] then
        announced[moduleKey] = true
        PE:Print(PE:ModuleLabel(moduleKey) .. " hit a problem. See Settings > Errors.")
    end
    -- Only a new entry asks for a redraw (a handler failing many times a
    -- second must not), and RefreshSettings itself only marks the panel as
    -- needing one redraw on the next frame.
    if isNew and PE.RefreshSettings then PE:RefreshSettings() end
end

function PE:LogError(moduleKey, msg, stack)
    if inLogError then return end
    inLogError = true
    pcall(LogErrorBody, moduleKey, msg, stack)
    inLogError = false
end

function PE:ClearErrors()
    local list = self.errors
    for i = #list, 1, -1 do list[i] = nil end
    self:RefreshSettings()
end

-- Chat fallback for when the panel itself cannot open.
function PE:PrintErrors()
    local list = self.errors
    if #list == 0 then
        self:Print("No errors recorded.")
        return
    end
    for i = 1, math.min(#list, 5) do
        local e = list[i]
        if type(e) == "table" then
            self:Print(self:ModuleLabel(e.module) .. " (x" .. tostring(e.count or 1) .. "): " .. tostring(e.msg))
        end
    end
end

---------------------------------------------------------------------------
-- Protected calls
---------------------------------------------------------------------------

local errorHandlers = {}

local function ErrorHandlerFor(key)
    if type(key) ~= "string" or key == "" then key = "core" end
    local handler = errorHandlers[key]
    if not handler then
        handler = function(err)
            local stack
            if debugstack then
                local ok, text = pcall(debugstack, 2)
                if ok then stack = text end
            end
            PE:LogError(key, err, stack)
            return err
        end
        errorHandlers[key] = handler
    end
    return handler
end
PE.ErrorHandlerFor = ErrorHandlerFor

local coreHandler = ErrorHandlerFor("core")

-- PE:Safe(moduleKey, fn, ...) -> ok, results...
function PE:Safe(key, fn, ...)
    if type(fn) ~= "function" then return false end
    return xpcall(fn, ErrorHandlerFor(key), ...)
end

local function PassResults(ok, ...)
    if ok then return ... end
end

-- PE:Wrap(moduleKey, fn) -> function that runs fn inside xpcall
function PE:Wrap(key, fn)
    if type(fn) ~= "function" then return function() end end
    local handler = ErrorHandlerFor(key)
    return function(...)
        return PassResults(xpcall(fn, handler, ...))
    end
end

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------

function PE:InCombat()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

local combatOrder, combatFns = {}, {} -- pending RunOutOfCombat calls

local function KeyOwner(key)
    if type(key) ~= "string" then return "core" end
    if PE.modules[key] then return key end
    local prefix = key:match("^([%w_]+)[:%.]")
    if prefix and PE.modules[prefix] then return prefix end
    return "core"
end

function PE:RunOutOfCombat(key, fn)
    if fn == nil and type(key) == "function" then fn = key end -- PE:RunOutOfCombat(fn)
    if type(fn) ~= "function" then return end
    if key == nil then key = fn end
    if not self:InCombat() then
        combatFns[key] = nil
        xpcall(fn, ErrorHandlerFor(KeyOwner(key)))
        return
    end
    if combatFns[key] == nil then combatOrder[#combatOrder + 1] = key end
    combatFns[key] = fn
end

local function FlushCombatQueue()
    if #combatOrder == 0 then return end
    if PE:InCombat() then
        -- Should not happen at PLAYER_REGEN_ENABLED; try again shortly.
        if C_Timer and C_Timer.After then C_Timer.After(0.5, FlushCombatQueue) end
        return
    end
    local order, fns = combatOrder, combatFns
    combatOrder, combatFns = {}, {}
    for i = 1, #order do
        local key = order[i]
        local fn = fns[key]
        if fn then xpcall(fn, ErrorHandlerFor(KeyOwner(key))) end
    end
end

---------------------------------------------------------------------------
-- Events: one hidden frame for everything
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local coreOwn = {}       -- [event] = true: core itself needs it
local coreHandlers = {}  -- [event] = { { key =, fn = }, ... } for the other core files
local eventUsers = {}    -- [event] = { [mod] = handler }
local S = {}             -- [mod] = private state
setmetatable(S, { __mode = "k" })

-- Returns true, or false plus a reason. An event name this client does not
-- know either raises or is quietly refused, depending on the client; both
-- end up here as "false".
local function FrameRegister(event)
    local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then return false, err end
    if eventFrame.IsEventRegistered then
        local asked, registered = pcall(eventFrame.IsEventRegistered, eventFrame, event)
        if asked and not registered then return false, "the game did not accept it" end
    end
    return true
end

local function EventNeeded(event)
    if coreOwn[event] then return true end
    local list = coreHandlers[event]
    if list then
        for i = 1, #list do
            if list[i].fn then return true end
        end
    end
    local users = eventUsers[event]
    return users ~= nil and next(users) ~= nil
end

local function FrameUnregisterIfUnused(event)
    if not EventNeeded(event) then
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
    end
end

-- For Core/UI/Hub/Settings only (modules use mod:RegisterEvent).
-- fn(event, ...) runs inside xpcall whether or not any module is enabled.
function PE:RegisterCoreEvent(event, key, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return false end
    local list = coreHandlers[event]
    if not list then
        list = {}
        coreHandlers[event] = list
    end
    for i = 1, #list do
        if list[i].key == key then
            list[i].fn = fn
            return FrameRegister(event)
        end
    end
    list[#list + 1] = { key = key, fn = fn }
    local ok, err = FrameRegister(event)
    if not ok then self:LogError("core", "Event " .. event .. " is not available: " .. tostring(err)) end
    return ok
end

function PE:UnregisterCoreEvent(event, key)
    local list = coreHandlers[event]
    if not list then return end
    for i = 1, #list do
        if list[i].key == key then list[i].fn = nil end
    end
    FrameUnregisterIfUnused(event)
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

local function DeepCopy(value, depth)
    if type(value) ~= "table" then return value end
    depth = depth or 0
    local copy = {}
    if depth > 8 then return copy end
    for k, v in pairs(value) do copy[k] = DeepCopy(v, depth + 1) end
    return copy
end

local function AttachOptions(mod)
    local db = PE.db
    if not db then return end
    local opts = db.options[mod.key]
    if type(opts) ~= "table" then
        opts = {}
        db.options[mod.key] = opts
    end
    if type(mod.defaults) == "table" then
        for k, v in pairs(mod.defaults) do
            if opts[k] == nil then opts[k] = DeepCopy(v) end
        end
    end
    mod.opts = opts
end

local function MergeErrors(saved)
    -- Errors caught before the saved variables loaded are newer than the saved ones.
    local merged, index = {}, {}
    local function add(e)
        if type(e) ~= "table" or type(e.msg) ~= "string" then return end
        local moduleKey = type(e.module) == "string" and e.module or "core"
        local id = moduleKey .. "\n" .. e.msg
        local have = index[id]
        if have then
            have.count = (tonumber(have.count) or 1) + (tonumber(e.count) or 1)
        elseif #merged < ERROR_CAP then
            local entry = {
                module = moduleKey,
                msg = e.msg,
                stack = type(e.stack) == "string" and e.stack or "",
                count = tonumber(e.count) or 1,
                last = tonumber(e.last) or 0,
            }
            merged[#merged + 1] = entry
            index[id] = entry
        end
    end
    for _, e in ipairs(PE.errors) do add(e) end
    if type(saved) == "table" then
        for i = 1, #saved do add(saved[i]) end
    end
    return merged
end

local function InitDB()
    if PE.db then return end
    local db = _G.PocketEssentialsDB
    if type(db) ~= "table" then
        db = {}
        _G.PocketEssentialsDB = db
    end
    if type(db.version) ~= "number" then db.version = 1 end
    if type(db.enabled) ~= "table" then db.enabled = {} end
    if type(db.options) ~= "table" then db.options = {} end
    if type(db.ui) ~= "table" then db.ui = {} end
    if not SIZES[db.ui.size] then db.ui.size = "medium" end
    if type(db.ui.hubPos) ~= "string" then db.ui.hubPos = "LEFT" end
    db.errors = MergeErrors(db.errors)
    PE.errors = db.errors
    PE.db = db
    for _, mod in ipairs(PE.moduleList) do AttachOptions(mod) end
end

local function EnsureDB()
    if PE.db then return end
    xpcall(InitDB, coreHandler)
    if PE.db then return end
    -- Last resort: settings work for this session but will not be saved.
    PE.db = {
        version = 1, enabled = {}, options = {},
        ui = { size = "medium", hubPos = "LEFT" },
        errors = PE.errors,
    }
    for _, mod in ipairs(PE.moduleList) do pcall(AttachOptions, mod) end
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------

local function UnregisterAllEvents(mod)
    local st = S[mod]
    if not st then return end
    for event in pairs(st.events) do
        st.events[event] = nil
        local users = eventUsers[event]
        if users then users[mod] = nil end
        FrameUnregisterIfUnused(event)
    end
end

local function Deactivate(mod, callDisable)
    local st = S[mod]
    st.enabled = false
    if callDisable and type(mod.OnDisable) == "function" then
        st.busy = true
        xpcall(mod.OnDisable, st.handler, mod)
        st.busy = false
    end
    st.active = false
    st.offCount = st.offCount + 1 -- cancels this module's pending mod:After timers
    UnregisterAllEvents(mod)
end

local function EnableModule(mod)
    local st = S[mod]
    if not st or st.dead then return false end
    if st.enabled then return true end
    if st.busy then return false end
    if mod.requiresQuestieDB and not PE.hasQuestieDB then return false end
    st.failed = nil
    st.active = true -- events may be registered and delivered from here on
    local ok = true
    if type(mod.OnEnable) == "function" then
        st.busy = true
        ok = xpcall(mod.OnEnable, st.handler, mod)
        st.busy = false
    end
    if ok then
        st.enabled = true
        return true
    end
    -- OnEnable failed part-way: let the module undo what it did, drop its
    -- events, and remember the failure for the panel.
    st.failed = true
    Deactivate(mod, true)
    return false
end

local function DisableModule(mod)
    local st = S[mod]
    if not st or st.dead then return end
    if st.busy then return end
    st.failed = nil
    if st.enabled then Deactivate(mod, true) end
end

local Methods = {}

function Methods:IsEnabled()
    local st = S[self]
    return st ~= nil and st.enabled == true
end

function Methods:RegisterEvent(event, handler)
    local st = S[self]
    if not st or st.dead or type(event) ~= "string" then return false end
    if handler == nil then handler = event end -- method named after the event
    if type(handler) ~= "function" and type(handler) ~= "string" then return false end
    local ok, err = FrameRegister(event)
    if not ok then
        PE:LogError(st.key, "Event " .. event .. " is not available on this client: " .. tostring(err))
        return false
    end
    local users = eventUsers[event]
    if not users then
        users = {}
        eventUsers[event] = users
    end
    users[self] = handler
    st.events[event] = true
    return true
end

function Methods:UnregisterEvent(event)
    local st = S[self]
    if not st or type(event) ~= "string" then return end
    st.events[event] = nil
    local users = eventUsers[event]
    if users then users[self] = nil end
    FrameUnregisterIfUnused(event)
end

function Methods:Wrap(fn)
    local st = S[self]
    return PE:Wrap(st and st.key or "core", fn)
end

function Methods:Safe(fn, ...)
    local st = S[self]
    if type(fn) ~= "function" then return false end
    return xpcall(fn, st and st.handler or coreHandler, ...)
end

function Methods:After(seconds, fn)
    local st = S[self]
    if type(fn) ~= "function" or not (C_Timer and C_Timer.After) then return end
    local handler = st and st.handler or coreHandler
    local offCount = st and st.offCount
    local ok, err = pcall(C_Timer.After, tonumber(seconds) or 0, function()
        -- Skipped if the module was switched off (or off and on again) meanwhile.
        if st and st.offCount ~= offCount then return end
        xpcall(fn, handler)
    end)
    if not ok then PE:LogError(st and st.key or "core", err) end
end

function Methods:Print(text)
    PE:Print(text)
end

function Methods:RequestReload(reason)
    local st = S[self]
    local label = PE:ModuleLabel(st and st.key)
    reason = (type(reason) == "string" and reason ~= "") and reason or "A reload is needed to finish this change."
    for _, r in ipairs(PE.reloadReasons) do
        if r.label == label and r.reason == reason then
            PE:RefreshSettings()
            return
        end
    end
    tinsert(PE.reloadReasons, { label = label, reason = reason })
    PE:RefreshSettings()
end

function Methods:RefreshPanel()
    PE:RefreshSettings()
end

local function SortModules(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.key < b.key
end

local function RegisterBody(self, def)
    for name, fn in pairs(Methods) do def[name] = fn end

    local key = def.key
    local st = { events = {}, offCount = 0, enabled = false, active = false }
    S[def] = st
    if type(key) ~= "string" or key == "" then
        st.dead, st.key = true, "core"
        st.handler = coreHandler
        self:LogError("core", "A feature file registered without a key and was ignored.")
        return def
    end
    st.key = key
    st.handler = ErrorHandlerFor(key)
    if self.modules[key] then
        st.dead = true
        self:LogError("core", "Two features use the key '" .. key .. "'. The second one was ignored.")
        return def
    end

    if type(def.label) ~= "string" or def.label == "" then def.label = key end
    if type(def.desc) ~= "string" then def.desc = "" end
    if type(def.order) ~= "number" then def.order = 1000 end
    self.modules[key] = def
    tinsert(self.moduleList, def)
    tsort(self.moduleList, SortModules)

    if self.db then pcall(AttachOptions, def) end
    if self.loggedIn then
        -- Registered late (not at file load): catch up.
        if type(def.OnLoad) == "function" then xpcall(def.OnLoad, st.handler, def) end
        if self.db and self.db.enabled[key] == true then EnableModule(def) end
        self:RefreshSettings()
    end
    return def
end

-- Never raises: a broken registration must not stop the rest of that file
-- from loading, so the caller always gets a table with the module methods.
function PE:RegisterModule(def)
    if type(def) ~= "table" then def = {} end
    local ok, err = pcall(RegisterBody, self, def)
    if not ok then
        self:LogError(type(def.key) == "string" and def.key or "core", err)
        for name, fn in pairs(Methods) do
            if rawget(def, name) == nil then pcall(rawset, def, name, fn) end
        end
        if not S[def] then
            S[def] = { events = {}, offCount = 0, enabled = false, active = false, dead = true, key = "core", handler = coreHandler }
        end
    end
    return def
end

function PE:GetModule(key)
    return key ~= nil and self.modules[key] or nil
end

function PE:IsModuleEnabled(key)
    local mod = key ~= nil and self.modules[key]
    local st = mod and S[mod]
    return (st and st.enabled == true) or false
end

function PE:IsModuleSavedOn(key)
    return (self.db ~= nil and self.db.enabled[key] == true) or false
end

-- For the panel: "on", "off", "failed" (saved on, OnEnable hit an error) or
-- "blocked" (needs QuestieDB). Second value is a plain-language detail.
function PE:GetModuleState(key)
    local mod = key ~= nil and self.modules[key]
    local st = mod and S[mod]
    if not st then return "off" end
    if mod.requiresQuestieDB and self.loggedIn and not self.hasQuestieDB then
        return "blocked", self.questieDBReason
    end
    if st.enabled then return "on" end
    if st.failed and self:IsModuleSavedOn(key) then return "failed" end
    return "off"
end

function PE:SetModuleEnabled(key, on)
    local mod = key ~= nil and self.modules[key]
    if not mod then return false end
    EnsureDB()
    on = on and true or false
    self.db.enabled[key] = on
    if self.loggedIn then
        if on then EnableModule(mod) else DisableModule(mod) end
    end
    self:RefreshSettings()
    return self:IsModuleEnabled(key)
end

---------------------------------------------------------------------------
-- Login
---------------------------------------------------------------------------

local coreLoginFns, loginFns = {}, {}

-- For UI/Hub/Settings: runs at PLAYER_LOGIN before any module's OnLoad.
function PE:OnCoreLogin(fn)
    if type(fn) ~= "function" then return end
    if self.loggedIn then
        xpcall(fn, coreHandler)
    else
        coreLoginFns[#coreLoginFns + 1] = fn
    end
end

-- Public: runs at PLAYER_LOGIN after modules were loaded and enabled, or now.
function PE:OnLogin(fn)
    if type(fn) ~= "function" then return end
    if self.loggedIn then
        xpcall(fn, coreHandler)
    else
        loginFns[#loginFns + 1] = fn
    end
end

local function IsAddOnLoaded(name)
    -- returns true / false, or nil when it cannot be told
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return nil end
    local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    if not ok then return nil end
    return (loaded or loadedOrLoading) and true or false
end

local function CheckQuestieDB()
    local lib = _G.LibQuestieDB
    local libOK = type(lib) == "table" and lib.Quest ~= nil
    local loaded = IsAddOnLoaded("QuestieDB")
    if libOK and loaded ~= false then
        PE.hasQuestieDB, PE.questieDBReason = true, nil
    elseif loaded == true then
        PE.hasQuestieDB = false
        PE.questieDBReason = "The QuestieDB addon loaded, but its quest data is missing. Try installing it again."
    else
        PE.hasQuestieDB = false
        PE.questieDBReason = "Needs the QuestieDB addon, which is not installed or did not load."
    end
end

local function Login()
    if PE.loggedIn then return end
    EnsureDB()
    xpcall(CheckQuestieDB, coreHandler)
    PE.oldQuestDotsLoaded = IsAddOnLoaded("QuestDots") == true
    PE.loggedIn = true

    for i = 1, #coreLoginFns do xpcall(coreLoginFns[i], coreHandler) end
    coreLoginFns = {}

    local list = {}
    for i, mod in ipairs(PE.moduleList) do list[i] = mod end
    for _, mod in ipairs(list) do
        local st = S[mod]
        if st and type(mod.OnLoad) == "function" then xpcall(mod.OnLoad, st.handler, mod) end
    end
    for _, mod in ipairs(list) do
        if PE.db.enabled[mod.key] == true then EnableModule(mod) end
    end

    local fns = loginFns
    loginFns = {}
    for i = 1, #fns do xpcall(fns[i], coreHandler) end
end

---------------------------------------------------------------------------
-- Event dispatch
---------------------------------------------------------------------------

coreOwn.ADDON_LOADED = true
coreOwn.PLAYER_LOGIN = true
coreOwn.PLAYER_REGEN_ENABLED = true

local function OnEvent(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == ADDON_NAME then
            -- If something needed settings before the saved ones were loaded,
            -- PE.db is a stand-in: drop it and start from the real table.
            if PE.db ~= _G.PocketEssentialsDB then PE.db = nil end
            xpcall(InitDB, coreHandler)
            coreOwn.ADDON_LOADED = nil
            FrameUnregisterIfUnused("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        xpcall(Login, coreHandler)
    elseif event == "PLAYER_REGEN_ENABLED" then
        xpcall(FlushCombatQueue, coreHandler)
    end

    local list = coreHandlers[event]
    if list then
        for i = 1, #list do
            local entry = list[i]
            if entry and entry.fn then xpcall(entry.fn, coreHandler, event, ...) end
        end
    end

    local users = eventUsers[event]
    if users then
        local mods = PE.moduleList
        for i = 1, #mods do
            local mod = mods[i]
            local handler = users[mod]
            if handler then
                local st = S[mod]
                if st and st.active then
                    if type(handler) == "string" then handler = mod[handler] end
                    if type(handler) == "function" then xpcall(handler, st.handler, mod, event, ...) end
                end
            end
        end
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
for event in pairs(coreOwn) do FrameRegister(event) end

---------------------------------------------------------------------------
-- Settings panel entry points. Settings.lua replaces these; if that file
-- failed to load, these keep the hub button and /pe from raising errors.
---------------------------------------------------------------------------

local function SettingsMissing()
    PE:Print("The settings window could not be loaded. The latest problems are listed here instead.")
    PE:PrintErrors()
end

function PE:OpenSettings() SettingsMissing() end
function PE:CloseSettings() end
function PE:ToggleSettings() SettingsMissing() end
function PE:RefreshSettings() end

-- Size preset and hub position, shared by the panel and /pe reset.
function PE:SetUISetting(key, value)
    EnsureDB()
    self.db.ui[key] = value
    local UI, Hub = self.UI, self.Hub
    if key == "size" and UI and UI.Refresh then self:Safe("core", UI.Refresh, UI, true) end
    if Hub and Hub.Refresh then self:Safe("core", Hub.Refresh, Hub) end
    self:RefreshSettings()
end

-- Must be called straight from a button's OnClick (needs a real tap).
function PE:ReloadNow()
    if C_UI and C_UI.Reload then
        C_UI.Reload()
    elseif ReloadUI then
        ReloadUI()
    end
end

---------------------------------------------------------------------------
-- /pe (last-resort backup: the handheld normally has no keyboard)
---------------------------------------------------------------------------

local function SlashCommand(msg)
    msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if msg == "errors" then
        PE:OpenSettings("errors")
    elseif msg == "reset" then
        PE:SetUISetting("size", "medium")
        PE:SetUISetting("hubPos", "LEFT")
        PE:Print("Button size and round button position were reset.")
    else
        PE:ToggleSettings()
    end
end

if type(SlashCmdList) == "table" then
    SLASH_POCKETESSENTIALS1 = "/pe"
    SLASH_POCKETESSENTIALS2 = "/pocket"
    SlashCmdList["POCKETESSENTIALS"] = function(msg)
        xpcall(SlashCommand, coreHandler, msg)
    end
end
