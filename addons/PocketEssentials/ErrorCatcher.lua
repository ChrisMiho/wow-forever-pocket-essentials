-- Pocket Essentials: Catch all errors (spec 2026-11-20-error-catcher-and-probe-panel, Part 2).
-- Keeps every Lua error, from the game and from other addons, in one list on
-- the Errors tab. Pocket Essentials' own errors go into its own list
-- (PE.errors, as always); the others go into PocketEssentialsDB.otherErrors,
-- newest first, at most 50.
--
-- How errors reach us: every Lua error and every Lua warning ends at the
-- game's error box, ScriptErrorsFrame:DisplayMessageInternal(message,
-- messageType, stack, locals). We listen after it (hooksecurefunc), so
-- Blizzard's own handler stays in place. Where the box or that function is
-- missing, a handler chained in front of the current one is used instead,
-- and put back when the feature is switched off.
--
-- Never stored: the "locals" the game passes along. A message the game hides
-- from addons (a secret value) is stored as a fixed sentence.
--
-- Standing aside: when BugGrabber, BugSack or Swatter is loaded, or another
-- addon replaced the error handler, those addons take the errors before they
-- reach the game's box, so this feature cannot be switched on and says why.
--
-- Nothing ticks. The listener is put on the first time the feature is
-- switched on (a hook cannot be taken off again) and returns at once while
-- the feature is off; LUA_WARNING is registered only while it is on.
--
-- Proof in Blizzard's source (forever branch, paths under Interface/AddOns;
-- "Doc/" is Blizzard_APIDocumentationGenerated/):
--   ScriptErrorsFrame, .errorData                Blizzard_ScriptErrorsFrame/Blizzard_ScriptErrorsFrame.xml:4, .lua:38
--   :DisplayMessageInternal(message, messageType, stack, locals)   Blizzard_ScriptErrorsFrame.lua:88
--   errorData entries { count, message, messageType, time, stack }  Blizzard_ScriptErrorsFrame.lua:147
--   the box shows only with the "scriptErrors" setting on           Blizzard_ScriptErrorsFrame.lua:130
--   seterrorhandler(HandleLuaError)              Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua:101
--   geterrorhandler                              Blizzard_PrintHandler/Blizzard_PrintHandler.lua (used there)
--   LUA_WARNING                                  Doc/ScriptWarningsDocumentation.lua:17
--   C_AddOns.IsAddOnLoaded                       Doc/AddOnsDocumentation.lua:322
--   C_CVar.GetCVar / SetCVar                     Doc/CVarDocumentation.lua:20, 131
-- Not documented, and logged in docs/ARCHITECTURE.md (Unverified API):
-- seterrorhandler, used only by the fallback.
local ADDON_NAME, PE = ...

local type, tostring, tonumber, ipairs, pcall = type, tostring, tonumber, ipairs, pcall
local tinsert, tremove = table.insert, table.remove

local KEY = "errors"
local CAP = PE.OTHER_ERROR_CAP or 50
local STACK_LINES = 8
local MESSAGE_MAX = 1000
local HIDDEN_TEXT = "(the game hides this message from addons)"
local ERRORS_SETTING = "scriptErrors"
local WARNING_TYPE = 1 -- Blizzard_ScriptErrorsFrame.lua: WarningMessageType

-- The source names used by the viewer's filter.
local BLIZZARD = "Blizzard"
local MACRO = "Macro or script"
local UNKNOWN = "Unknown"
local OURS = "Pocket Essentials"

-- Folder and global names of the error addons we stand aside for.
local OTHER_CATCHERS = {
    { name = "BugSack", folders = { "BugSack" }, global = "BugSack" },
    { name = "BugGrabber", folders = { "!BugGrabber", "BugGrabber" }, global = "BugGrabber" },
    { name = "Swatter", folders = { "!Swatter", "Swatter" }, global = "Swatter" },
}

local mod
local active = false          -- the feature is on: the listener records
local hooked = false          -- the listener is on the error box (stays: hooks cannot be removed)
local chained                 -- our chained handler (fallback), while it is in place
local chainedOld              -- the handler it passes on to
local standAside              -- the name found at login, or nil
local handlerAtLoad           -- the error handler when this file loaded
local filledTo = 0            -- how many of the box's entries this session are already counted
local announced = false       -- the one chat line per session for others' errors
local warnings = 0            -- Lua warnings this session

local function IsSecret(v)
    if v == nil or not issecretvalue then return false end
    local ok, secret = pcall(issecretvalue, v)
    return not ok or secret and true or false
end

local function Str(v)
    if v == nil or IsSecret(v) then return nil end
    if type(v) == "string" then return v end
    if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
    return nil
end

local function ShortPath(text)
    return (text:gsub("Interface[/\\]+AddOns[/\\]+", ""))
end

-- Up to 8 lines, paths shortened, each at most 160 characters.
local function TrimStack(stack)
    if type(stack) ~= "string" then return "" end
    local out, n = {}, 0
    for line in stack:gmatch("[^\r\n]+") do
        line = ShortPath(line:gsub("^%s+", ""))
        if line ~= "" then
            n = n + 1
            out[n] = line:sub(1, 160)
            if n >= STACK_LINES then break end
        end
    end
    return table.concat(out, "\n")
end

-- Where an error came from: "Blizzard", Pocket Essentials, another addon's
-- folder name, or "Macro or script". Read from the message first (where it
-- broke), then the stack. Secret text is skipped; with nothing readable the
-- source is "Unknown".
local function SourceOf(message, stack)
    local readable = false
    for _, text in ipairs({ message or false, stack or false }) do
        if text then
            readable = true
            local name = text:match("AddOns[/\\]([^/\\%]:\"]+)[/\\]")
            if name then
                if name:find("^Blizzard_") then return BLIZZARD end
                if name == ADDON_NAME then return OURS end
                return name:sub(1, 40)
            end
            if text:find("Interface[/\\]") or text:find("FrameXML", 1, true) then return BLIZZARD end
            if text:find("^%[?string \"") then return MACRO end
        end
    end
    return readable and MACRO or UNKNOWN
end

local function Store()
    local db = PE.db
    if not db then return nil end
    if type(db.otherErrors) ~= "table" then db.otherErrors = {} end
    return db.otherErrors
end

-- One error (not a warning) the game passed on. message and stack may be
-- secret or missing; count: how many times (a back-filled entry may be more).
local function Record(message, stack, count)
    local text, stackText = Str(message), Str(stack)
    local source = SourceOf(text, stackText)
    local msg = text and ShortPath(text):sub(1, MESSAGE_MAX) or HIDDEN_TEXT
    count = tonumber(count) or 1
    if source == OURS then
        -- One of ours that got past our own guards: into our own list.
        for _ = 1, count do PE:LogError("core", msg, stackText) end
        return
    end
    local list = Store()
    if not list then return end
    local stored = TrimStack(stackText)
    local first = stored:match("^[^\n]*") or ""
    local now = time()
    for i = 1, #list do
        local e = list[i]
        if e.source == source and e.msg == msg and (e.stack:match("^[^\n]*") or "") == first then
            e.count = (tonumber(e.count) or 1) + count
            e.last = now
            if i > 1 then
                tremove(list, i)
                tinsert(list, 1, e)
            end
            return
        end
    end
    tinsert(list, 1, { source = source, msg = msg, stack = stored, count = count, last = now })
    for i = #list, CAP + 1, -1 do list[i] = nil end
    if PE.debugOn then PE:Debug(KEY, "caught an error from " .. source) end
    if not announced and not (mod and mod.opts and mod.opts.popup == "hide") then
        announced = true
        PE:Print("An error from " .. source .. " was caught. See Settings > Errors.")
    end
    PE:RefreshSettings()
end

-- How many entries the error box holds (nil when it cannot be read).
local function BoxCount()
    local box = rawget(_G, "ScriptErrorsFrame")
    if type(box) ~= "table" then return nil end
    local data = box.errorData
    if IsSecret(data) or type(data) ~= "table" then return nil end
    return #data, data
end

-- Runs after the game's error box took an error or a warning.
local function OnDisplay(_, message, messageType, stack)
    if not active then return end
    local n = BoxCount()
    if n then filledTo = n end
    if not IsSecret(messageType) and messageType == WARNING_TYPE then return end -- counted from LUA_WARNING
    Record(message, stack, 1)
end

-- The errors the box took before we listened (at login: those raised while
-- the game was loading). Each entry once per session.
local function BackFill()
    local n, data = BoxCount()
    if not n then return end
    if filledTo > n then filledTo = 0 end
    for i = filledTo + 1, n do
        local e = data[i]
        if type(e) == "table" and not IsSecret(e) then
            local kind = e.messageType
            if IsSecret(kind) or kind ~= WARNING_TYPE then Record(e.message, e.stack, Str(e.count) or 1) end
        end
    end
    filledTo = n
end

local function Hook()
    if hooked then return true end
    local box = rawget(_G, "ScriptErrorsFrame")
    if type(box) ~= "table" or type(box.DisplayMessageInternal) ~= "function" or type(hooksecurefunc) ~= "function" then
        return false
    end
    local ok = pcall(hooksecurefunc, box, "DisplayMessageInternal", function(...)
        PE:Safe(KEY, OnDisplay, ...)
    end)
    hooked = ok and true or false
    return hooked
end

-- Fallback: a handler in front of the current one. It passes every error on.
local function Chain()
    if chained then return true end
    if type(geterrorhandler) ~= "function" or type(seterrorhandler) ~= "function" then return false end
    local ok, old = pcall(geterrorhandler)
    if not ok or IsSecret(old) or type(old) ~= "function" then return false end
    local handler
    handler = function(message, ...)
        if active then
            local stack
            if debugstack then
                local got, text = pcall(debugstack, 2)
                if got then stack = text end
            end
            PE:Safe(KEY, Record, message, stack, 1)
        end
        return old(message, ...)
    end
    if not pcall(seterrorhandler, handler) then return false end
    chained, chainedOld = handler, old
    return true
end

local function Unchain()
    if not chained then return end
    local ok, current = pcall(geterrorhandler)
    -- Only put the old one back while ours is still the one in place.
    if ok and current == chained then pcall(seterrorhandler, chainedOld) end
    chained, chainedOld = nil, nil
end

---------------------------------------------------------------------------
-- Standing aside
---------------------------------------------------------------------------

local function Loaded(folder)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
    local ok, loading, loaded = pcall(C_AddOns.IsAddOnLoaded, folder)
    if not ok or IsSecret(loading) or IsSecret(loaded) then return false end
    return (loading or loaded) and true or false
end

local function CurrentHandler()
    if type(geterrorhandler) ~= "function" then return nil end
    local ok, h = pcall(geterrorhandler)
    if not ok or IsSecret(h) then return nil end
    return h
end

-- The name of the error addon that takes the errors first, or nil.
local function FindOtherCatcher()
    for _, other in ipairs(OTHER_CATCHERS) do
        for _, folder in ipairs(other.folders) do
            if Loaded(folder) then return other.name end
        end
        if rawget(_G, other.global) ~= nil then return other.name end
    end
    local now = CurrentHandler()
    if handlerAtLoad ~= nil and now ~= nil and now ~= handlerAtLoad then return "another error addon" end
    return nil
end

handlerAtLoad = CurrentHandler()

---------------------------------------------------------------------------
-- The game's error popup (Show / Hide)
---------------------------------------------------------------------------

local function ReadSetting()
    if not (C_CVar and C_CVar.GetCVar) then return nil end
    local ok, v = pcall(C_CVar.GetCVar, ERRORS_SETTING)
    return ok and Str(v) or nil
end

local function WriteSetting(value)
    if not (C_CVar and C_CVar.SetCVar) then return end
    pcall(C_CVar.SetCVar, ERRORS_SETTING, value)
end

-- Hide: remember the setting once, then 0. Show: put the remembered one back.
local function ApplyPopup()
    local opts = mod.opts
    if type(opts) ~= "table" then return end
    if active and opts.popup == "hide" then
        if opts.oldScriptErrors == nil then
            local old = ReadSetting()
            if old == nil then return end
            opts.oldScriptErrors = old
        end
        if ReadSetting() ~= "0" then WriteSetting("0") end
        if PE.debugOn then PE:Debug(KEY, "error popup hidden (was " .. tostring(opts.oldScriptErrors) .. ")") end
    elseif opts.oldScriptErrors ~= nil then
        WriteSetting(opts.oldScriptErrors)
        if PE.debugOn then PE:Debug(KEY, "error popup setting put back to " .. tostring(opts.oldScriptErrors)) end
        opts.oldScriptErrors = nil
    end
end

local function QueuePopup()
    PE:RunOutOfCombat("errors:popup", ApplyPopup)
end

---------------------------------------------------------------------------
-- The list for the viewer (Settings.lua)
---------------------------------------------------------------------------

-- "pe", "blizz" or "other": the viewer's filter group of a source.
local function GroupOf(source)
    if source == OURS then return "pe" end
    if source == BLIZZARD then return "blizz" end
    return "other"
end

local function OurSource(e)
    if e.module == nil or e.module == "core" or e.module == "blocked" or not PE.modules[e.module] then return OURS end
    return OURS .. ": " .. PE:ModuleLabel(e.module)
end

---------------------------------------------------------------------------
-- The feature
---------------------------------------------------------------------------

local function OnEnable(m)
    active = true
    if not Hook() then Chain() end
    m:RegisterEvent("LUA_WARNING", function()
        warnings = warnings + 1
        if PE.db then PE.db.luaWarnings = (tonumber(PE.db.luaWarnings) or 0) + 1 end
    end)
    BackFill()
    QueuePopup()
    if PE.debugOn then PE:Debug(KEY, "listening " .. (hooked and "after the error box" or (chained and "with a chained handler" or "nowhere: neither way is on this client"))) end
end

local function OnDisable()
    active = false
    Unchain()
    QueuePopup()
end

mod = PE:RegisterModule({
    key = KEY,
    label = "Catch all errors",
    desc = "Keeps every Lua error, from the game and other addons, in one list here.",
    order = 90,
    defaults = { popup = "show" },

    OnLoad = function()
        standAside = FindOtherCatcher()
        if standAside and PE.debugOn then PE:Debug(KEY, "standing aside: " .. standAside .. " is loaded") end
    end,

    blocked = function()
        if not standAside then return nil end
        return "Off while " .. standAside .. " is loaded: " .. standAside
            .. " takes the errors before they reach this list.\n|cff9e9e9e"
            .. "To use this instead, turn " .. standAside .. " off in the AddOns list and restart.|r"
    end,

    options = {
        { key = "popup", label = "Error popup", help = "Hidden errors still show in this list.",
          choices = { { value = "show", label = "Show" }, { value = "hide", label = "Hide" } },
          OnChange = function() QueuePopup() end },
    },

    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
PE.ErrorCatcher = mod

-- Whether others' errors are listed (the feature is on).
function mod:Listing()
    return PE:IsModuleEnabled(KEY)
end

-- The name of the error addon this feature stands aside for, or nil.
function mod:StandingAsideFor()
    return standAside
end

function mod:WarningCount()
    return warnings
end

-- The entries the viewer shows, newest first: { source, group, msg, stack,
-- count, last }. filter: "all", "pe", "blizz" or "other". While the feature is
-- off only Pocket Essentials' own errors are listed (filter ignored).
function mod:Entries(filter)
    local listing = self:Listing()
    if not listing then filter = "pe" end
    local out = {}
    if filter == "all" or filter == "pe" then
        for _, e in ipairs(PE.errors) do
            if type(e) == "table" then
                out[#out + 1] = { source = OurSource(e), group = "pe", msg = tostring(e.msg), stack = e.stack,
                    count = tonumber(e.count) or 1, last = tonumber(e.last) or 0 }
            end
        end
    end
    if listing then
        for _, e in ipairs(Store() or {}) do
            local group = GroupOf(e.source)
            if filter == "all" or filter == group then
                out[#out + 1] = { source = e.source, group = group, msg = e.msg, stack = e.stack,
                    count = tonumber(e.count) or 1, last = tonumber(e.last) or 0 }
            end
        end
    end
    -- Newest first; ties keep the list order (ours first).
    for i = 1, #out do out[i].order = i end
    table.sort(out, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.order < b.order
    end)
    return out
end

-- How many errors the Errors tab's badge counts.
function mod:Count()
    local n = #PE.errors
    if self:Listing() then n = n + #(Store() or {}) end
    return n
end

-- Clear all: everything that is listed.
function mod:ClearAll()
    if self:Listing() then
        local list = Store()
        if list then
            for i = #list, 1, -1 do list[i] = nil end
        end
        if PE.db then PE.db.luaWarnings = 0 end
    end
    PE:ClearErrors()
end

-- For tests.
mod._SourceOf = SourceOf
