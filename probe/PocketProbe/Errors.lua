local ADDON_NAME, P = ...

-- The Errors and Graphics areas (probe 0.3.0).
--
-- Errors: how Lua errors reach the game's error box, and whether an addon can
-- listen without taking the box's place. Only classes, counts and sources
-- (Blizzard, an addon's name, "Macro or script") are kept: never the text of
-- another addon's error, and never the "locals" the game passes along.
--
-- Graphics: why the loot sparkles do not show on the handheld. Reads the
-- outline and sparkle settings, writes one, lists the setting names the
-- client knows, and two guided trials where the player looks and answers.
--
-- Proof in Blizzard's source (forever branch, paths under Interface/AddOns;
-- "Doc/" is Blizzard_APIDocumentationGenerated/):
--   seterrorhandler(HandleLuaError)             Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua:101
--   geterrorhandler                             Blizzard_SharedXMLBase/ErrorUtil.lua:3 (used there; not documented)
--   ScriptErrorsFrame                           Blizzard_ScriptErrorsFrame/Blizzard_ScriptErrorsFrame.xml:4
--     .errorData                                Blizzard_ScriptErrorsFrame/Blizzard_ScriptErrorsFrame.lua:38
--     :DisplayMessageInternal(message, messageType, stack, locals)   same file:88
--     shown only with the "scriptErrors" setting on                  same file:130
--   LUA_WARNING                                 Doc/ScriptWarningsDocumentation.lua:17
--   hooksecurefunc(table, name, fn)             Blizzard_GamepadSmartNavigation/SmartNavigation.lua:260
--   C_AddOns.IsAddOnLoaded                      Doc/AddOnsDocumentation.lua:322
--   C_CVar.GetCVarInfo / GetCVarDefault         Doc/CVarDocumentation.lua:82, 66
--   C_CVar.GetCVar / SetCVar                    Doc/CVarDocumentation.lua:20, 131
--   C_VideoOptions.IsOutlineModeSupported       Doc/VideoDocumentation.lua:78
--   C_VideoOptions.IsSpellVisualDensitySystemSupported   Doc/VideoDocumentation.lua:105
--   ConsoleGetAllCommands (field "command")     Doc/ConsoleDocumentation.lua:59, 256
--   graphicsOutlineMode, raidGraphicsOutlineMode, graphicsSpellDensity,
--   graphicsParticleDensity, graphicsQuality    Blizzard_SettingsDefinitions_Shared/Graphics.lua:108-123
--   SoftTargetLowPriorityIcons                  Blizzard_SettingsDefinitions_Frame/Accessibility.lua:181
--   SoftTargetInteract                          Blizzard_Gamepad/Core.lua:26
--   SoftTargetIconEnemy, SoftTargetIconInteract, SoftTargetIconGameObject
--                                               Blizzard_Gamepad/Core.lua:17, 21, 28
--
-- Not in Blizzard's interface source (engine settings), and guarded: the
-- settings "outlineModeShowLootEffectWhenDisabled" (the sparkle setting) and
-- "OutlineEngineMode". A client without one reads nil, and the trials say so.

local type, tostring, pairs, ipairs, pcall = type, tostring, pairs, ipairs, pcall
local tconcat, tsort = table.concat, table.sort
local Find, IsSecret, Num, Str, Log = P.Find, P.IsSecret, P.Num, P.Str, P.Log
local Add = P.Add

local ERRORS, GRAPHICS = "Errors", "Graphics"
local TEST_TAG = "PocketProbe test error"
local SOURCE_LIMIT = 30              -- different sources counted by name; the rest are "other"

---------------------------------------------------------------------------
-- Listening to the error box
---------------------------------------------------------------------------

-- What this session has seen. Counts and names only.
local seen = {
    others = 0, bySource = {}, sources = 0, ours = 0, hidden = 0, warnings = 0,
    blockedOthers = 0, blockedBy = {}, blockedSources = 0,
}
P.errorSeen = seen

local hook = { installed = false, why = nil }
P.errorHook = hook

local waiting = {}                   -- [number] = what happened to that probe test error
local testCount = 0

local function Count(map, field, name)
    if map[name] == nil then
        if seen[field] >= SOURCE_LIMIT then name = "other" else seen[field] = seen[field] + 1 end
    end
    map[name] = (map[name] or 0) + 1
end

-- Where an error came from: "Blizzard", an addon's folder name, or "Macro or
-- script". Read from the stack first, then the message; secret text is skipped.
local function SourceOf(message, stack)
    local readable = false
    for _, value in ipairs({ stack, message }) do
        local text = Str(value)
        if text then
            readable = true
            local name = text:match("AddOns[/\\]([^/\\%]:]+)[/\\]")
            if name then
                if name:find("^Blizzard_") then return "Blizzard" end
                return name:sub(1, 40)
            end
            if text:find("Interface[/\\]") or text:find("FrameXML", 1, true) then return "Blizzard" end
        end
    end
    return readable and "Macro or script" or "hidden"
end
P.ErrorSource = SourceOf

-- Runs after the game's error box has taken an error or a warning.
local function OnDisplay(_, message, messageType, stack)
    -- Warnings are counted from LUA_WARNING (Run.lua), so they count even
    -- without this listener.
    if Num(messageType) == 1 then return end
    local text = Str(message)
    if text then
        local n = text:match(TEST_TAG .. " #(%d+)")
        local w = n and waiting[tonumber(n)]
        if w then
            w.reached = true
            w.message = P.Class(message)
            w.stack = P.Class(stack)
            seen.ours = seen.ours + 1
            return
        end
    else
        seen.hidden = seen.hidden + 1
    end
    local source = SourceOf(message, stack)
    if source == P.name then
        seen.ours = seen.ours + 1
        return
    end
    seen.others = seen.others + 1
    Count(seen.bySource, "sources", source)
end

-- Puts a listener after the error box's own function. Blizzard's handler is
-- left in place: nothing is replaced. Returns true when the listener is on.
function P.EnsureErrorHook()
    if hook.installed then return true end
    local frame = Find("ScriptErrorsFrame")
    if type(frame) ~= "table" then
        hook.why = "ScriptErrorsFrame is not on this client"
        return false
    end
    if type(frame.DisplayMessageInternal) ~= "function" then
        hook.why = "ScriptErrorsFrame:DisplayMessageInternal is not on this client"
        return false
    end
    if type(hooksecurefunc) ~= "function" then
        hook.why = "hooksecurefunc is not on this client"
        return false
    end
    local ok, err = pcall(hooksecurefunc, frame, "DisplayMessageInternal", function(...)
        pcall(OnDisplay, ...)
    end)
    if not ok then
        hook.why = "the listener could not be put on: " .. P.Plain(err, 200)
        return false
    end
    hook.installed, hook.why = true, nil
    return true
end

-- Called by Run.lua for ADDON_ACTION_BLOCKED / _FORBIDDEN naming another addon.
function P.CountOthersBlock(addon)
    local name = Str(addon)
    seen.blockedOthers = seen.blockedOthers + 1
    Count(seen.blockedBy, "blockedSources", name and name:sub(1, 40) or "hidden")
end

function P.CountWarning()
    seen.warnings = seen.warnings + 1
end

-- Raises one test error of ours on the next frame, outside any protected
-- call, so it travels the same way as any other addon's error.
local function RaiseTestError()
    local after = Find("C_Timer.After")
    if type(after) ~= "function" then return nil end
    testCount = testCount + 1
    local n = testCount
    local w = {}
    waiting[n] = w
    after(0, function() error(TEST_TAG .. " #" .. n, 0) end)
    return w
end

local function ErrorBox()
    local frame = Find("ScriptErrorsFrame")
    return type(frame) == "table" and frame or nil
end

-- true / false, or nil when it cannot be read.
local function BoxShown()
    local box = ErrorBox()
    if not box or type(box.IsShown) ~= "function" then return nil end
    local ok, shown = pcall(box.IsShown, box)
    if not ok or IsSecret(shown) then return nil end
    return shown and true or false
end

-- Closes the game's error box if it is open (so a test starts from a closed
-- box, and the box a test opened does not stay over the screen).
local function CloseBox()
    local box = ErrorBox()
    if box and BoxShown() and type(box.Hide) == "function" then pcall(box.Hide, box) end
end
P.CloseErrorBox = CloseBox

local function YesNo(v)
    if v == nil then return "unknown" end
    return v and "yes" or "no"
end

-- "Blizzard 2, ExampleAddon 1", biggest first.
local function SourceList(map)
    local names = {}
    for name in pairs(map) do names[#names + 1] = name end
    tsort(names, function(a, b)
        if map[a] ~= map[b] then return map[a] > map[b] end
        return a < b
    end)
    for i, name in ipairs(names) do names[i] = name .. " " .. map[name] end
    return tconcat(names, ", ")
end

local function Loaded(name)
    local fn = Find("C_AddOns.IsAddOnLoaded")
    if type(fn) ~= "function" then return false end
    local ok, loading, loaded = pcall(fn, name)
    if not ok then return false end
    if IsSecret(loading) or IsSecret(loaded) then return false end
    return (loading or loaded) and true or false
end

-- At load: the listener goes on now, so the counts cover the whole session.
P.EnsureErrorHook()

---------------------------------------------------------------------------
-- Area Errors
---------------------------------------------------------------------------

Add({
    id = "err.handler", area = ERRORS, label = "Error handler is there", kind = "info", manual = true,
    run = function()
        local get, set = Find("geterrorhandler"), Find("seterrorhandler")
        local parts = { "geterrorhandler " .. type(get), "seterrorhandler " .. type(set) }
        local result = "missing"
        if type(get) == "function" then
            local ok, handler = pcall(get)
            if not ok then
                result = "error"
            elseif IsSecret(handler) then
                result = "secret"
            else
                result = type(handler)
            end
            parts[#parts + 1] = "handler " .. result
        end
        local others = {}
        for _, name in ipairs({ "BugGrabber", "BugSack", "Swatter" }) do
            if Loaded(name) then others[#others + 1] = name end
        end
        if #others == 0 and (Find("BugGrabber") ~= nil or Find("BugSack") ~= nil) then others[1] = "a BugGrabber or BugSack global" end
        parts[#parts + 1] = "error addons loaded: " .. (#others > 0 and tconcat(others, ", ") or "none")
        return result, tconcat(parts, "; ")
    end,
})

Add({
    id = "err.box", area = ERRORS, label = "Error box is there", kind = "info", manual = true,
    run = function()
        local box = ErrorBox()
        if not box then return "missing", "ScriptErrorsFrame is not on this client" end
        local parts = { "DisplayMessageInternal " .. type(box.DisplayMessageInternal) }
        local data = box.errorData
        local class = P.Class(data)
        parts[#parts + 1] = "errorData " .. class
        if class == "readable" and type(data) == "table" then
            local ok, n = pcall(function() return #data end)
            if ok and Num(n) then parts[#parts + 1] = "entries in the box " .. n end
        end
        parts[#parts + 1] = "box shown " .. YesNo(BoxShown())
        parts[#parts + 1] = "listener " .. (hook.installed and "on" or ("off (" .. tostring(hook.why) .. ")"))
        return class, tconcat(parts, "; ")
    end,
})

Add({
    -- last: Run all safe runs the two trials that make the error box pop up at its end.
    id = "err.hook", area = ERRORS, label = "Hook sees a test error", kind = "action", manual = true, last = true, wait = 1,
    run = function(state)
        if not P.EnsureErrorHook() then
            if not ErrorBox() then return "missing", "ScriptErrorsFrame" end
            return false, hook.why
        end
        state.before = BoxShown()
        state.w = RaiseTestError()
        if not state.w then return "missing", "C_Timer.After" end
        return "wait"
    end,
    check = function(state)
        local w = state.w
        local notes = "listener on; test error reached it " .. YesNo(w.reached)
        if w.reached then
            notes = notes .. "; message " .. tostring(w.message) .. "; stack " .. tostring(w.stack)
        end
        notes = notes .. "; box shown " .. YesNo(BoxShown())
            .. (state.before and " (it was already open)" or "")
        -- The box this test opened is closed again once it has been looked at.
        CloseBox()
        return w.reached and true or false, notes
    end,
})

Add({
    id = "err.others", area = ERRORS, label = "Errors from others seen", kind = "info", manual = true,
    run = function()
        if not hook.installed then return "no listener", tostring(hook.why) end
        local result = seen.others == 0 and "0 seen" or (seen.others .. " (" .. SourceList(seen.bySource) .. ")")
        return result, "errors not from the probe this session " .. seen.others
            .. (seen.others > 0 and (" (" .. SourceList(seen.bySource) .. ")") or "")
            .. "; warnings (LUA_WARNING) " .. seen.warnings
            .. "; the probe's own " .. seen.ours
            .. "; messages hidden from addons " .. seen.hidden
    end,
})

local ERRORS_SETTING = "scriptErrors"

Add({
    id = "err.hide", area = ERRORS, label = "Hide the error box", kind = "action", manual = true, last = true, wait = 1,
    needs = { "C_CVar.GetCVarInfo", "C_CVar.GetCVar", "C_CVar.SetCVar" },
    run = function(state)
        local value, default, _, _, locked, secure, readOnly = Find("C_CVar.GetCVarInfo")(ERRORS_SETTING)
        local notes = {}
        state.notes = notes
        value = Str(value)
        if not value then return false, "scriptErrors unreadable or not on this client" end
        notes[#notes + 1] = "value " .. value .. ", default " .. tostring(Str(default))
            .. ", isSecure " .. YesNo(not IsSecret(secure) and secure) .. ", isReadOnly " .. YesNo(not IsSecret(readOnly) and readOnly)
            .. ", locked " .. YesNo(not IsSecret(locked) and locked)
        if value == "0" then
            -- The box is already off: a test error not showing it proves nothing.
            notes[#notes + 1] = "scriptErrors is already 0, so whether setting it hides the box could not be told"
            return P.CANT_TELL, tconcat(notes, "; ")
        end
        CloseBox()
        local set = Find("C_CVar.SetCVar")
        local same = set(ERRORS_SETTING, value)
        same = not IsSecret(same) and same and true or false
        notes[#notes + 1] = "written back unchanged: " .. (same and "ok" or "refused")
        if not same then return false, tconcat(notes, "; ") end
        state.old = value
        set(ERRORS_SETTING, "0")
        if Str(Find("C_CVar.GetCVar")(ERRORS_SETTING)) ~= "0" then
            notes[#notes + 1] = "setting it to 0 did not stick"
            return false, tconcat(notes, "; ")
        end
        state.before = BoxShown()
        state.w = RaiseTestError()
        if not state.w then return "missing", "C_Timer.After" end
        return "wait"
    end,
    check = function(state)
        local notes = state.notes
        local shown = BoxShown()
        CloseBox()
        notes[#notes + 1] = "set to 0, then a test error: box shown " .. YesNo(shown)
            .. "; the listener saw it " .. YesNo(state.w.reached)
        if state.before then
            notes[#notes + 1] = "the box was still open after closing it, so this could not be told"
            return P.CANT_TELL, tconcat(notes, "; ")
        end
        if shown == nil then
            notes[#notes + 1] = "whether the box is shown could not be read"
            return P.CANT_TELL, tconcat(notes, "; ")
        end
        return not shown, tconcat(notes, "; ")
    end,
    undo = function(state)
        if state.old then Find("C_CVar.SetCVar")(ERRORS_SETTING, state.old) end
    end,
})

Add({
    id = "err.chain", area = ERRORS, label = "Own handler", kind = "action", manual = true, risky = true, wait = 1,
    needs = { "geterrorhandler", "seterrorhandler" },
    run = function(state)
        local old = Find("geterrorhandler")()
        if IsSecret(old) or type(old) ~= "function" then return false, "the current handler is not a plain function" end
        local mine = {}
        state.old, state.mine = old, mine
        local box = ErrorBox()
        local data = box and box.errorData
        if not IsSecret(data) and type(data) == "table" then state.count = #data end
        Find("seterrorhandler")(function(message, ...)
            local text = Str(message)
            if text and text:find(TEST_TAG, 1, true) then mine.saw = true end
            return old(message, ...)
        end)
        state.set = true
        state.w = RaiseTestError()
        if not state.w then return "missing", "C_Timer.After" end
        return "wait"
    end,
    check = function(state)
        local box = ErrorBox()
        local data = box and box.errorData
        local grew = nil
        if state.count and not IsSecret(data) and type(data) == "table" then grew = #data > state.count end
        local boxGot = state.w.reached or grew
        return (state.mine.saw and boxGot) and true or false,
            "our handler saw the test error " .. YesNo(state.mine.saw)
            .. "; Blizzard's box still got it " .. YesNo(boxGot)
            .. "; the old handler is put back"
    end,
    undo = function(state)
        if state.set then Find("seterrorhandler")(state.old) end
    end,
})

Add({
    id = "err.blocked", area = ERRORS, label = "Blocked actions of others", kind = "info", manual = true,
    run = function()
        local n = seen.blockedOthers
        return n == 0 and "0 seen" or (n .. " seen"),
            "ADDON_ACTION_BLOCKED or _FORBIDDEN naming another addon this session " .. n
            .. (n > 0 and (" (" .. SourceList(seen.blockedBy) .. ")") or "")
    end,
})

---------------------------------------------------------------------------
-- Area Graphics
---------------------------------------------------------------------------

local SPARKLE = "outlineModeShowLootEffectWhenDisabled"
local GRAPHICS_SETTINGS = {
    SPARKLE, "graphicsOutlineMode", "raidGraphicsOutlineMode", "OutlineEngineMode", "graphicsSpellDensity",
    "graphicsParticleDensity", "graphicsQuality", "SoftTargetLowPriorityIcons", "SoftTargetInteract",
    "SoftTargetIconInteract", "SoftTargetIconGameObject", "SoftTargetIconEnemy",
}
P.SPARKLE = SPARKLE

local function GetSetting(name)
    local get = Find("C_CVar.GetCVar")
    if type(get) ~= "function" then return nil end
    local ok, v = pcall(get, name)
    return ok and Str(v) or nil
end

-- One setting as text: "graphicsOutlineMode 2 (default 3, secure)".
local function SettingText(name)
    local info = Find("C_CVar.GetCVarInfo")
    if type(info) == "function" then
        local ok, value, default, _, _, locked, secure, readOnly = pcall(info, name)
        if ok and value ~= nil then
            local flags = {}
            local function flag(v, word) if not IsSecret(v) and v then flags[#flags + 1] = word end end
            flag(secure, "secure"); flag(readOnly, "read-only"); flag(locked, "locked")
            return name .. " " .. P.Plain(value, 20) .. " (default " .. P.Plain(default, 20)
                .. (#flags > 0 and (", " .. tconcat(flags, ", ")) or "") .. ")"
        end
    end
    local value = GetSetting(name)
    if value == nil then return name .. " not on this client" end
    local default = Find("C_CVar.GetCVarDefault")
    local ok, d = false, nil
    if type(default) == "function" then ok, d = pcall(default, name) end
    return name .. " " .. P.Plain(value, 20) .. (ok and d ~= nil and (" (default " .. P.Plain(d, 20) .. ")") or "")
end

local function Supported(path)
    local fn = Find(path)
    if type(fn) ~= "function" then return "missing" end
    local ok, v = pcall(fn)
    if not ok then return "error" end
    if IsSecret(v) then return "secret" end
    return tostring(v)
end

Add({
    id = "gfx.read", area = GRAPHICS, label = "Read sparkle and outline settings", kind = "info", manual = true,
    run = function()
        local parts = {
            "IsOutlineModeSupported " .. Supported("C_VideoOptions.IsOutlineModeSupported"),
            "IsSpellVisualDensitySystemSupported " .. Supported("C_VideoOptions.IsSpellVisualDensitySystemSupported"),
        }
        for _, name in ipairs(GRAPHICS_SETTINGS) do parts[#parts + 1] = SettingText(name) end
        return "sparkle " .. (GetSetting(SPARKLE) or "none") .. " · outline " .. (GetSetting("graphicsOutlineMode") or "none"),
            tconcat(parts, "; ")
    end,
})

Add({
    id = "gfx.write", area = GRAPHICS, label = "Write the sparkle setting", kind = "action", manual = true,
    needs = { "C_CVar.GetCVar", "C_CVar.SetCVar" },
    run = function(state)
        local old = GetSetting(SPARKLE)
        if old == nil then return "missing", SPARKLE end
        local set = Find("C_CVar.SetCVar")
        local same = set(SPARKLE, old)
        if IsSecret(same) or not same then return false, "writing it back unchanged was refused" end
        state.old = old
        set(SPARKLE, "1")
        local now = GetSetting(SPARKLE)
        return now == "1", "was " .. old .. "; written back unchanged ok; set to 1, read back " .. tostring(now)
            .. "; the old value is put back"
    end,
    undo = function(state)
        if state.old then Find("C_CVar.SetCVar")(SPARKLE, state.old) end
    end,
})

local NAME_WORDS = { "outline", "loot", "sparkle", "particle", "spell" }
local NAMES_MAX = 80

Add({
    id = "gfx.names", area = GRAPHICS, label = "Setting names with outline, loot or spell", kind = "info", manual = true,
    needs = { "ConsoleGetAllCommands" },
    run = function()
        local list = ConsoleGetAllCommands()
        if IsSecret(list) or type(list) ~= "table" then return "nil", "no list" end
        local names = {}
        for _, info in ipairs(list) do
            local name = type(info) == "table" and Str(info.command)
            if name then
                local lower = name:lower()
                for _, word in ipairs(NAME_WORDS) do
                    if lower:find(word, 1, true) then
                        names[#names + 1] = name:sub(1, 60)
                        break
                    end
                end
            end
        end
        tsort(names)
        local shown = {}
        for i = 1, math.min(#names, NAMES_MAX) do shown[i] = names[i] end
        return #names .. " found", (#names > 0 and tconcat(shown, ", ") or "none")
            .. (#names > NAMES_MAX and (" and " .. (#names - NAMES_MAX) .. " more") or "")
    end,
})

-- Guided trials: Run.lua saves the old values, sets these, waits for the
-- player's answer (across a full restart where restart = true), then puts
-- the old values back.
Add({
    id = "gfx.outlines", area = GRAPHICS, label = "Outlines off, then restart", short = "Outlines off", kind = "guided",
    manual = true,
    needs = { "C_CVar.GetCVar", "C_CVar.SetCVar" },
    settings = { { "graphicsOutlineMode", "0" }, { "raidGraphicsOutlineMode", "0" }, { SPARKLE, "1" } },
    restart = true,
    start = "Start",
    steps = "Close the game app completely and open it again (a reload, or logging out to character select, "
        .. "is not enough), kill something, then come back here.",
    ask = "Did the loot sparkles show on the corpse? Answer with the two buttons.",
    answers = { "Sparkles seen", "No sparkles" },
})

Add({
    id = "gfx.icons", area = GRAPHICS, label = "Interact icons on loot", short = "Interact icons", kind = "guided",
    manual = true,
    needs = { "C_CVar.GetCVar", "C_CVar.SetCVar" },
    settings = { { "SoftTargetLowPriorityIcons", "1" } },
    -- With either of these at 0 no icon can show, whatever the answer: set to 1
    -- for the trial (and put back with the rest).
    ifZero = { "SoftTargetIconInteract", "SoftTargetIconGameObject" },
    -- Noted with the answer.
    watch = { "SoftTargetIconInteract", "SoftTargetIconGameObject", "SoftTargetIconEnemy" },
    start = "Start",
    ask = "Look at a lootable corpse, then answer with the two buttons.",
    answers = { "Icon seen", "No icon" },
})
