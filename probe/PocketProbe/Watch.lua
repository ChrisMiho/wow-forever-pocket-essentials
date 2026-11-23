local ADDON_NAME, P = ...

-- The watchers (probe 0.7.0), and "Clear saved results".
--
-- One tap on Arm, out of a fight, and every fight after it is counted until
-- Disarm or a reload:
--   * which bar the triggers bring up (the game's own callback);
--   * the presses the game shows on its buttons (a hook on each button);
--   * how often the action bar events fire, in and out of a fight, and the
--     time spent in each;
--   * once per arming, the first spell on cooldown in a fight gets the
--     cooldown sweep on square 1 of ours, with one screenshot.
-- Only counts and our own short tags are kept: no spell, no slot action, no
-- cooldown value, no chat.
--
-- Nothing ticks. The counts come from events, registered only while armed,
-- on one frame of ours made now, at load, and from a callback and hooks that
-- are put on once (the first Arm) and do nothing while not armed: neither
-- can be taken off again.
--
-- The saved data, PocketProbeDB.watch: the last three armings, oldest first.
-- One arming:
--   started, ended   date and time
--   why              how it ended: "disarmed", "reload" (a reload or a
--                    logout), "cleared"
--   events           [event] = { c = in a fight, o = out of one }
--                    _secs = { c = seconds in fights, o = seconds out of them }
--                    missing = "<event>, ..." for events this client lacks
--   bar              [main | left | right | both | other | secret | error] = { c, o }:
--                    the bar the game made active ("both" is the both-triggers bar,
--                    "other" any other bar or none; "secret" or "error" when it
--                    could not be read)
--                    first = { "t=<seconds since Arm>;<bar>;<c or o>", ... } (the first 20)
--                    missing = "<game name>" when the callback could not be set
--   press            [main | left | right | both] = { down = { c, o }, up = { c, o },
--                    other = { c, o } } (other: "pressed" was secret or not true / false)
--                    kind = how "pressed" read: "boolean", "secret", "other" (all seen)
--                    hooked = buttons with the hook; missing = "<what>" when none
--   sweep            result ("allowed", "blocked", "forbidden", "error", "missing"),
--                    shownByItself ("yes" / "no"), durClass (the class of
--                    GetCooldownDuration afterwards), screenshot ("taken" / "none"),
--                    t (seconds since Arm); missing = "<game name>"
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
--   PageUnit:RegisterActiveActionBarUpdatedCallback(callback, owner)
--                                                Blizzard_GamepadActionBars/PageUnit.lua:705 (fired with
--                                                no payload from SetActiveActionBar, :527-539, when a
--                                                trigger is pressed or let go: :546-599; the callback is
--                                                called with that table: Blizzard_SharedXMLBase/
--                                                CallbackRegistry.lua:112, 184-208; it may not be a number)
--   PageUnit:GetActiveBar                        Blizzard_GamepadActionBars/PageUnit.lua:542
--   PageUnit.actionBars: topBar, leftBar, rightBar, bottomBar are the four anchors' .Bar
--                                                Blizzard_GamepadActionBars/PageUnit.lua:111-114 (the
--                                                both-triggers bar is bottomBar: :582-584)
--   button :ApplyPressedStyle(pressed)           Blizzard_GamepadActionBars/ActionBarButton.lua:421, called
--                                                on a press and a release from TriggerSecureClick (:1111-1114)
--                                                and the pet buttons' OnClick (:1182). Each button instance
--                                                carries it: the template's mixin (ActionBarButton.xml:4,
--                                                GamepadActionBarStandardButtonMixin, built from
--                                                GamepadActionBarButtonMixin at ActionBarButton.lua:1053) is
--                                                mixed into the frame when it is made, and the game calls the
--                                                mixin's methods on the instances (ActionBar.lua:34-35).
--   hooksecurefunc(table, name, fn)              Blizzard_GamepadSmartNavigation/SmartNavigation.lua:260
--   P.SweepOnSlot (Trials.lua) uses the names of the sweep trials, listed in Core.lua.
--
-- Not proven by the source, and guarded: whether "pressed" reaches an addon's
-- hook as a plain true / false in a fight. Its class is what is recorded.

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring
local floor, max = math.floor, math.max
local tconcat, tremove = table.concat, table.remove
local Find, IsSecret, Num, Log, Guard = P.Find, P.IsSecret, P.Num, P.Log, P.Guard

local CLEAR_WINDOW = 5      -- seconds the second tap of Clear has

-- The six events a face bar would need (counted in and out of a fight).
local EVENTS = { "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE",
    "ACTIONBAR_SLOT_CHANGED", "SPELL_UPDATE_COOLDOWN", "UPDATE_BONUS_ACTIONBAR" }

local armed = false
local current               -- the arming being written, while armed
local fighting = false      -- between PLAYER_REGEN_DISABLED and _ENABLED, while armed
local t0, segAt             -- the game's clock at Arm, and at the start of the stretch being timed

local function Clock()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and Num(now) or nil
end

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
    -- The floating Fight button (Perf.lua) shows in a fight only while armed or recording.
    if P.UpdateFightButton then pcall(P.UpdateFightButton) end
end

local function Status(text)
    if P.SetStatus then P.SetStatus(text) end
end

-- "c" in a fight, "o" out of one.
local function Side()
    return fighting and "c" or "o"
end

-- Adds one to count[side], making the pair when it is not there.
local function Bump(list, name, side)
    local pair = list[name]
    if type(pair) ~= "table" then
        pair = { c = 0, o = 0 }
        list[name] = pair
    end
    pair[side] = (pair[side] or 0) + 1
end

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
-- The active bar: the game's callback, set once
---------------------------------------------------------------------------

local PAGE_UNIT = "GamepadMainActionBarFrame.PageUnit"
local BARS = { { "TopCenteredAnchor", "main" }, { "LeftCenteredAnchor", "left" },
    { "RightCenteredAnchor", "right" }, { "BottomCenteredAnchor", "both" } }
local FIRST_MAX = 20        -- bar changes kept in order, per arming

local function PageUnit()
    local pu = Find(PAGE_UNIT)
    if type(pu) == "table" and not IsSecret(pu) then return pu end
    return nil
end

-- One anchor's bar, or nil.
local function AnchorBar(key)
    local pu = PageUnit()
    local anchor = pu and pu[key]
    if type(anchor) ~= "table" or IsSecret(anchor) then return nil end
    local bar = anchor.Bar
    if type(bar) ~= "table" or IsSecret(bar) then return nil end
    return bar
end

-- PageUnit and the four bars, looked up once at each Arm (no lookups on
-- every trigger press): cache.pu, cache[1..4] (in the order of BARS).
local cache = {}

local function FillCache()
    cache.pu = PageUnit()
    for i, entry in ipairs(BARS) do cache[i] = AnchorBar(entry[1]) or false end
end

-- "main", "left", "right", "both" or "other" for a bar the game names.
function P.WatchBarName(bar)
    if type(bar) ~= "table" or IsSecret(bar) then return "other" end
    if cache[1] == nil then FillCache() end
    for i, entry in ipairs(BARS) do
        if rawequal(cache[i], bar) then return entry[2] end
    end
    return "other"
end

local barKey = {}           -- the table our callback is registered under
local barHooked = false

local function OnActiveBar()
    local cur = current
    if not cur then return end
    local pu = cache.pu
    local name
    if not pu or type(pu.GetActiveBar) ~= "function" then
        name = "error"
    else
        local ok, bar = pcall(pu.GetActiveBar, pu)
        if not ok then name = "error"
        elseif IsSecret(bar) then name = "secret"
        else name = P.WatchBarName(bar) end
    end
    local side = Side()
    Bump(cur.bar, name, side)
    if type(cur.bar.first) ~= "table" then cur.bar.first = {} end
    local first = cur.bar.first
    if #first < FIRST_MAX then
        first[#first + 1] = "t=" .. (P.WatchSeconds() or 0) .. ";" .. name .. ";" .. side
    end
end

local function SetBarCallback(cur)
    if barHooked then return end
    local pu = PageUnit()
    if not pu then
        cur.bar.missing = "PageUnit"
        return
    end
    if type(pu.RegisterActiveActionBarUpdatedCallback) ~= "function" then
        cur.bar.missing = "RegisterActiveActionBarUpdatedCallback"
        return
    end
    if type(pu.GetActiveBar) ~= "function" then cur.bar.missing = "GetActiveBar" end
    if pcall(pu.RegisterActiveActionBarUpdatedCallback, pu, Guard(OnActiveBar), barKey) then
        barHooked = true
    else
        cur.bar.missing = "RegisterActiveActionBarUpdatedCallback (it raised an error)"
    end
end

---------------------------------------------------------------------------
-- Presses: a hook on each spell button of the four bars, put on once
---------------------------------------------------------------------------

local pressHooked = {}      -- [button] = true
local pressCount = 0
local kindsSeen = {}        -- [kind] = true this arming, so the text is only built for a new one

local function OnPress(name, pressed)
    local kind = IsSecret(pressed) and "secret" or (type(pressed) == "boolean" and "boolean" or "other")
    local dir = (kind == "boolean") and (pressed and "down" or "up") or "other"
    -- The fade-for-next-fight trial counts main bar presses too (Trials.lua).
    if P.WatchOnPress then pcall(P.WatchOnPress, name, dir) end
    local cur = current
    if not cur then return end
    if not kindsSeen[kind] then
        kindsSeen[kind] = true
        cur.press.kind = P.Merge(cur.press.kind, kind)
    end
    local per = cur.press[name]
    if type(per) ~= "table" then
        per = {}
        cur.press[name] = per
    end
    Bump(per, dir, Side())
end

-- Puts the hook on every button that does not have it yet. Returns how many
-- buttons have it.
function P.WatchInstallPressHooks()
    if type(hooksecurefunc) ~= "function" then return pressCount end
    for _, entry in ipairs(BARS) do
        local bar, name = AnchorBar(entry[1]), entry[2]
        local list = bar and bar.actionButtons
        if type(list) == "table" and not IsSecret(list) then
            for i = 1, 8 do
                local b = list[i]
                if type(b) == "table" and not IsSecret(b) and not pressHooked[b] and type(b.ApplyPressedStyle) == "function" then
                    local hook = Guard(function(_, pressed) OnPress(name, pressed) end)
                    if pcall(hooksecurefunc, b, "ApplyPressedStyle", hook) then
                        pressHooked[b] = true
                        pressCount = pressCount + 1
                    end
                end
            end
        end
    end
    return pressCount
end

---------------------------------------------------------------------------
-- The cooldown sweep, once per arming
---------------------------------------------------------------------------

local SWEEP_NEEDS = { "C_ActionBar.HasAction", "C_ActionBar.GetActionCooldown", "C_ActionBar.GetActionCooldownDuration" }
local sweepDone = false     -- this arming's sweep ran (or cannot run)
local sweepCheckAt          -- the game's clock at the last look for a spell on cooldown

local function SweepNow(cur, slot)
    local sw = cur.sweep
    sw.t = P.WatchSeconds() or 0
    sw.screenshot = "none"
    if not P.SweepOnSlot or not P.Watched then
        sw.result = "missing"
        return
    end
    local function onShot(taken)
        if taken then sw.screenshot = "taken" end
    end
    local out, missing, sig = P.Watched("watch.sweep", function() return P.SweepOnSlot(slot, onShot) end)
    if sig then
        sw.result = (sig.kind == "forbidden" or sig.kind == "blocked") and sig.kind or "error"
    elseif out == "missing" then
        sw.result, sw.missing = "missing", tostring(missing)
    elseif type(out) == "table" then
        sw.result = out.ok and "allowed" or "error"
    else
        sw.result = "error"
    end
    if type(out) == "table" then
        sw.shownByItself = out.shown and "yes" or "no"
        sw.durClass = type(out.durClass) == "string" and out.durClass or nil
    end
    Log("watch: cooldown sweep " .. sw.result)
end

local function OnCooldownEvent(cur)
    if sweepDone or not fighting then return end
    local now = Clock()
    if sweepCheckAt and now and now - sweepCheckAt < 1 then return end
    sweepCheckAt = now
    local slot, state
    if P.SweepSlot then slot, state = P.SweepSlot() end
    if not slot or state ~= "yes" then return end
    sweepDone = true
    SweepNow(cur, slot)
end

P.WatchOnEvent = function(event, cur)
    if event == "ACTIONBAR_UPDATE_COOLDOWN" then OnCooldownEvent(cur) end
end

local function SetSweep(cur)
    sweepDone, sweepCheckAt = false, nil
    for _, name in ipairs(SWEEP_NEEDS) do
        if Find(name) == nil then
            cur.sweep.missing, sweepDone = name, true
            return
        end
    end
    if not AnchorBar("TopCenteredAnchor") then cur.sweep.missing, sweepDone = "the main bar", true end
end

-- At every Arm: the callback and the hooks (once each), the sweep made ready.
P.WatchOnArm = function(cur)
    FillCache()
    for kind in pairs(kindsSeen) do kindsSeen[kind] = nil end
    SetBarCallback(cur)
    cur.press.hooked = P.WatchInstallPressHooks()
    if cur.press.hooked == 0 then
        cur.press.missing = (type(hooksecurefunc) ~= "function") and "hooksecurefunc" or "the bars' buttons"
    end
    SetSweep(cur)
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
    -- The automatic passes' "already covered this session" goes too (Run.lua).
    if P.ResetCovered then P.ResetCovered() end
    db.watch = {}
    if type(db.perf) == "table" then
        db.perf.runs = {}
        db.perf.on = false
    end
    Log("saved results cleared (the switches are kept)")
end

-- The first tap only arms it; a second one within 5 seconds clears.
-- Returns true when the results were cleared, and a short word on what happened.
function P.ClearSaved()
    if not P.db then return false, "loading" end
    if InFight() then
        clearAt = nil
        Status("Clear saved results: out of a fight only.")
        Changed()
        return false, "in a fight"
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
        return false, "tap again"
    end
    clearAt = nil
    clearToken = clearToken + 1
    Empty()
    Status("Saved results cleared")
    Changed()
    if P.RefreshPanel then pcall(P.RefreshPanel) end
    return true, "cleared"
end
