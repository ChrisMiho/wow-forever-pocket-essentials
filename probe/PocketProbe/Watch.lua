local ADDON_NAME, P = ...

-- The watchers (probe 0.7.0), and "Clear saved results".
--
-- One tap on Arm, out of a fight, and every fight after it is counted until
-- Disarm or a reload: how often the action bar events fire, in and out of a
-- fight, and the time spent in each. Only counts and our own short tags are
-- kept: no spell, no slot action, no cooldown value, no chat.
--
-- Nothing ticks. The counts come from events, registered only while armed,
-- on one frame of ours made now, at load.
--
-- The saved data, PocketProbeDB.watch: the last three armings, oldest first.
-- One arming:
--   started, ended   date and time
--   why              how it ended: "disarmed", "reload" (a reload or a
--                    logout), "cleared"
--   events           [event] = { c = in a fight, o = out of one }
--                    _secs = { c = seconds in fights, o = seconds out of them }
--                    missing = "<event>, ..." for events this client lacks
--   bar, press, sweep   (the other watchers)
--
-- Clear saved results: the first tap only arms it ("Tap again to clear" for
-- 5 seconds); a second tap in that time stops a recording, the watchers and
-- anything the probe runs, then empties the saved results, answers, armings
-- and recordings. The switches (Risky, Vendor, Auto) are kept.
--
-- Game names used here and not listed in Core.lua, with their proof in
-- Blizzard's source for build 1.60.1 (paths as in Core.lua). Each event is
-- registered in a pcall: one this client lacks is noted as missing.
--
--   Name                                         Proof
--   ACTIONBAR_SLOT_CHANGED                       Doc/ActionBarFrameDocumentation.lua:1085
--   ACTIONBAR_UPDATE_COOLDOWN                    Doc/ActionBarFrameDocumentation.lua:1095
--   ACTIONBAR_UPDATE_STATE                       Doc/ActionBarFrameDocumentation.lua:1101
--   ACTIONBAR_UPDATE_USABLE                      Doc/ActionBarFrameDocumentation.lua:1107
--   UPDATE_BONUS_ACTIONBAR                       Doc/ActionBarFrameDocumentation.lua:1119
--   SPELL_UPDATE_COOLDOWN                        Doc/SpellBookDocumentation.lua:927
--   PLAYER_LOGOUT                                Doc/SystemDocumentation.lua:159
--   frame :UnregisterAllEvents                   Doc/SimpleFrameAPIDocumentation.lua:1588

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring
local floor, max = math.floor, math.max
local tconcat, tremove = table.concat, table.remove
local Find, IsSecret, Num, Log, Guard = P.Find, P.IsSecret, P.Num, P.Log, P.Guard

local CLEAR_WINDOW = 5      -- seconds the second tap of Clear has

-- The six events a face bar would need (counted in and out of a fight).
local EVENTS = { "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE",
    "ACTIONBAR_SLOT_CHANGED", "SPELL_UPDATE_COOLDOWN", "UPDATE_BONUS_ACTIONBAR" }
P.WATCH_EVENTS = EVENTS

local armed = false
local current               -- the arming being written, while armed
local fighting = false      -- between PLAYER_REGEN_DISABLED and _ENABLED, while armed
local t0, segAt             -- the game's clock at Arm, and at the start of the stretch being timed

local function Clock()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and Num(now) or nil
end
P.WatchClock = Clock

local function InFight()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, locked = pcall(InCombatLockdown)
    return ok and not IsSecret(locked) and locked and true or false
end

local function After(seconds, fn)
    local after = Find("C_Timer.After")
    if type(after) ~= "function" then return false end
    after(seconds, Guard(fn))
    return true
end

local function Changed()
    if P.OnWatchChanged then pcall(P.OnWatchChanged) end
end

local function Status(text)
    if P.SetStatus then P.SetStatus(text) end
end

-- "c" in a fight, "o" out of one.
local function Side()
    return fighting and "c" or "o"
end
P.WatchSide = Side

-- Adds one to count[side], making the pair when it is not there.
local function Bump(list, name, side)
    local pair = list[name]
    if type(pair) ~= "table" then
        pair = { c = 0, o = 0 }
        list[name] = pair
    end
    pair[side] = (pair[side] or 0) + 1
end
P.WatchBump = Bump

-- Adds the time since the stretch began to "in a fight" or "out of one".
local function Flush()
    local cur = current
    local now = Clock()
    if cur and now and segAt then
        local secs = cur.events._secs
        local side = Side()
        secs[side] = floor(((secs[side] or 0) + max(now - segAt, 0)) * 10 + 0.5) / 10
    end
    segAt = now
end

---------------------------------------------------------------------------
-- The event frame (made now; events only while armed)
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", nil, UIParent)

local handlers = {}

for _, event in ipairs(EVENTS) do
    handlers[event] = function()
        local cur = current
        if not cur then return end
        Bump(cur.events, event, Side())
        if P.WatchOnEvent then P.WatchOnEvent(event, cur) end
    end
end

function handlers.PLAYER_REGEN_DISABLED()
    Flush()
    fighting = true
end

function handlers.PLAYER_REGEN_ENABLED()
    Flush()
    fighting = false
end

-- The game writes the saved file after this: the arming ends here.
function handlers.PLAYER_LOGOUT()
    if armed then P.WatchDisarm("reload") end
end

frame:SetScript("OnEvent", Guard(function(_, event, ...)
    local handler = handlers[event]
    if handler and armed then handler(...) end
end))

local function Listen(on)
    pcall(frame.UnregisterAllEvents, frame)
    if not on then return nil end
    local missing = {}
    for event in pairs(handlers) do
        -- A client without the event raises an error on registering it.
        if not pcall(frame.RegisterEvent, frame, event) then missing[#missing + 1] = event end
    end
    table.sort(missing)
    return #missing > 0 and tconcat(missing, ", ") or nil
end

---------------------------------------------------------------------------
-- Arm and Disarm
---------------------------------------------------------------------------

function P.WatchArmed()
    return armed
end

function P.WatchCurrent()
    return armed and current or nil
end

-- Seconds since Arm, whole, or nil.
function P.WatchSeconds()
    local now = Clock()
    if not armed or not now or not t0 then return nil end
    return max(floor(now - t0), 0)
end

-- What the panel's row says.
function P.WatchText()
    if not armed then return "Not watching" end
    local secs = P.WatchSeconds()
    return "Watching, " .. floor((secs or 0) / 60) .. " min"
end

-- Out of a fight only. True when armed (or already armed).
function P.WatchArm()
    local db = P.db
    if not db then return false end
    if armed then return true end
    if InFight() then
        Status("Watch my next fights: out of a fight only.")
        return false
    end
    if type(db.watch) ~= "table" then db.watch = {} end
    local cur = { started = P.Stamp("%Y-%m-%d %H:%M:%S"), bar = {}, press = {}, events = { _secs = { c = 0, o = 0 } }, sweep = {} }
    db.watch[#db.watch + 1] = cur
    while #db.watch > P.WATCH_KEEP do tremove(db.watch, 1) end
    armed, current, fighting = true, cur, false
    t0 = Clock()
    segAt = t0
    cur.events.missing = Listen(true)
    if P.WatchOnArm then P.WatchOnArm(cur) end
    Log("watch: armed")
    Status("Watching your next fights until Disarm or a reload")
    Changed()
    return true
end

-- why: "disarmed" unless given ("reload", "cleared").
function P.WatchDisarm(why)
    if not armed then return end
    Flush()
    local cur = current
    cur.ended = P.Stamp("%Y-%m-%d %H:%M:%S")
    cur.why = why or "disarmed"
    Listen(false)
    armed, current, fighting = false, nil, false
    segAt, t0 = nil, nil
    Log("watch: ended (" .. cur.why .. ")")
    if cur.why == "disarmed" then Status("Watching stopped") end
    Changed()
end

---------------------------------------------------------------------------
-- Clear saved results
---------------------------------------------------------------------------

local clearAt               -- the game's clock at the first tap, while the second one may come
local clearToken = 0        -- changes with every first tap, so only the newest timer starts over

function P.ClearPending()
    return clearAt ~= nil
end

local function Empty()
    local db = P.db
    if P.Recording and P.Recording() and P.StopRecording then P.StopRecording() end
    if armed then P.WatchDisarm("cleared") end
    -- A pass, the clean run or a guided trial: stopped, and frames put back.
    local busy = P.Busy and P.Busy()
    local waiting = P.GuidedWaiting and P.GuidedWaiting()
    if (busy or waiting) and P.Stop then P.Stop() end
    for _, key in ipairs({ "results", "last", "details", "situations", "spoiled" }) do db[key] = {} end
    db.watch = {}
    if type(db.perf) == "table" then
        db.perf.runs = {}
        db.perf.on = false
    end
    Log("saved results cleared (the switches are kept)")
end

-- The first tap only arms it; a second one within 5 seconds clears.
-- Returns true when the results were cleared.
function P.ClearSaved()
    if not P.db then return false end
    if InFight() then
        clearAt = nil
        Status("Clear saved results: out of a fight only.")
        Changed()
        return false
    end
    local now = Clock()
    if not clearAt or not now or now - clearAt > CLEAR_WINDOW then
        clearAt = now or 0
        clearToken = clearToken + 1
        local token = clearToken
        After(CLEAR_WINDOW, function()
            if token ~= clearToken or not clearAt then return end
            clearAt = nil
            Changed()
        end)
        Status("Tap Clear again within " .. CLEAR_WINDOW .. " seconds to clear the saved results.")
        Changed()
        return false
    end
    clearAt = nil
    clearToken = clearToken + 1
    Empty()
    Status("Saved results cleared")
    Changed()
    if P.RefreshPanel then pcall(P.RefreshPanel) end
    return true
end
