local ADDON_NAME, P = ...

-- Running the trials: noticing when the game blocks one, passes, the clean
-- series (one trial per reload), guided trials, and the small Probe button.
--
-- Nothing runs by itself: a pass starts from the panel (Run, Run all safe,
-- Fight tests), the clean series from Clean run, and the automatic passes of 0.2.0 only
-- with the Auto switch on. Nothing here runs every frame. A pass is a chain
-- of short timers (C_Timer.After), one trial about every 0.3 seconds.

local type, ipairs, pcall, xpcall = type, ipairs, pcall, xpcall
local tconcat = table.concat
local Find, IsSecret, Str, Log, Guard = P.Find, P.IsSecret, P.Str, P.Log, P.Guard

local STEP = 0.3            -- seconds between trials
local LOGIN_DELAY = 3       -- after login or a loading screen
local FIGHT_DELAY = 1       -- after a fight starts or ends (lockdown begins after the event)
local VENDOR_DELAY = 0.3    -- after a vendor window opens
local SHOT_GAP = 0.5        -- between the timed steps of a guided trial with screenshots
local LIST_LOG = 4000       -- the longest log line: every trial of the fight tests and its result

local db                    -- the saved table, once loaded

local function After(seconds, fn)
    local after = Find("C_Timer.After")
    if type(after) ~= "function" then return false end
    after(seconds, Guard(fn))
    return true
end

local FlushQuiet             -- below: writes the count of repeats not yet logged
local current               -- the trial being run: { signals, undoSignals, phase, undo }

-- Puts back what a trial still waiting for its check has changed (a reload
-- or a logout in that second would otherwise keep, say, scriptErrors at 0).
local function UndoCurrent(why)
    local cur = current
    if not cur or not cur.undo or cur.undone then return end
    cur.undone = true
    local ok, err = pcall(cur.undo)
    Log(tostring(cur.id) .. ": put back before " .. why .. (ok and "" or (" (failed: " .. P.Plain(err) .. ")")))
end
P.UndoCurrent = UndoCurrent

local function Reload()
    UndoCurrent("the reload")
    FlushQuiet()
    Log("reloading")
    local reload = Find("C_UI.Reload")
    if type(reload) == "function" then
        reload()
    elseif type(ReloadUI) == "function" then
        ReloadUI()
    end
end

---------------------------------------------------------------------------
-- Noticing a block
--
-- Three signs, all arriving inside the call that caused them:
--   * ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN, naming this addon and
--     the game function;
--   * the game's own "Interface action failed because of an AddOn" line,
--     which Blizzard's code also prints by itself with no event;
--   * a Lua error from the call.
-- Each is pinned on the trial running at that moment.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Afterwards: signs that arrive when no trial is running. On the device the
-- game went on refusing its own controller actions (interact, cancel) in
-- this addon's name after some trials, until a reload. Each such refusal is
-- counted under a made-up trial id, "after.<function>" or "after.message",
-- and the first of a session is pinned on the trial that had just finished.
---------------------------------------------------------------------------

local AFTER_AREA = "Afterwards (the game's own actions refused in the probe's name)"
local QUIET_GAP = 10        -- seconds between log lines about repeats
local WARNING = "controls may misbehave until a reload — tap Save"

local lastTrial, lastTrigger    -- the trial that finished most recently this session
local refusals = 0              -- signs outside a trial, this session
local afterSeen = {}            -- [situation key | id] = { count, first, detail }
local quietCount, quietSince, quietAt = 0, nil, nil
local keyCache, keyTrigger, keyAt
local ShowWarning               -- below, with the buttons

local function Clock()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and P.Num(now) or nil
end

FlushQuiet = function()
    if quietCount > 0 then
        Log(quietCount .. " more refusal" .. (quietCount == 1 and "" or "s") .. " since " .. tostring(quietSince))
        quietCount = 0
    end
end

-- The situation a refusal belongs to: the present one, with the trigger of
-- the trial that came before it. Worked out at most once a second.
local function AfterKey()
    local trigger = lastTrigger or "auto"
    local now = Clock()
    if keyCache and keyTrigger == trigger and now and keyAt and now - keyAt < 1 then return keyCache end
    local key, facts = P.Situation(trigger)
    P.EnsureSituation(key, facts)
    keyCache, keyTrigger, keyAt = key, trigger, now
    return key
end

local function SeenText(seen)
    return "seen " .. seen.count .. (seen.count == 1 and " time" or " times") .. " this session; first seen after: " .. seen.first
end

-- kind: "forbidden" | "blocked" (an event naming a function) | "message".
local function Aftermath(kind, func, rawStack)
    if not P.db then return end
    refusals = refusals + 1
    local id, label = "after.message", "The game's 'interface action failed' line afterwards"
    if kind ~= "message" then
        local name = (func or ""):gsub("%(%)$", "")
        name = name:gsub("[^%w_%.:]", "_")
        if name == "" then name = "unnamed" end
        id, label = "after." .. name, name .. " refused afterwards"
    end
    local key = AfterKey()
    local prior = lastTrial or "no trial yet"
    if refusals == 1 then
        P.db.spoiled[key] = P.Merge(P.db.spoiled[key], prior)
        ShowWarning()
    end
    local now = Clock()
    local slot = key .. "|" .. id
    local seen = afterSeen[slot]
    if seen then
        seen.count = seen.count + 1
        if seen.detail then seen.detail.message = SeenText(seen) end
        if quietCount == 0 then quietSince = P.Stamp("%H:%M:%S") end
        quietCount = quietCount + 1
        if not now or not quietAt or now - quietAt >= QUIET_GAP then
            FlushQuiet()
            quietAt = now
        end
        return
    end
    seen = { count = 1, first = prior }
    afterSeen[slot] = seen
    P.AddTrial(id, AFTER_AREA, label)
    if rawStack == nil then rawStack = P.RawStack() end
    seen.detail = P.Record(id, key, (kind == "forbidden") and "forbidden" or "blocked", {
        func = (kind ~= "message") and func or nil, stack = P.TrimStack(rawStack), message = SeenText(seen),
    })
    quietAt = now
end

local function Signal(kind, func, message, rawStack)
    local cur = current
    if not cur then
        if kind ~= "error" then Aftermath(kind, func, rawStack) end
        return
    end
    if rawStack == nil then rawStack = P.RawStack() end
    local list = (cur.phase == "undo") and cur.undoSignals or cur.signals
    list[#list + 1] = { kind = kind, func = func, message = message, stack = P.TrimStack(rawStack) }
end

local function OnActionEvent(event, addon, func)
    if Str(addon) ~= P.name then
        -- Another addon's refusal: only counted (area Errors).
        if P.CountOthersBlock then P.CountOthersBlock(addon) end
        return
    end
    func = Str(func)
    if func == "" then func = nil end
    Signal(event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", func and func:sub(1, 120), nil, nil)
end

local BLOCKED_FN = "DisplayInterfaceActionBlockedMessage"
local hookedFn              -- the global as it was right after our hook went on
local idleReads, idleReadAt = 0, nil

local function OnBlockedMessage()
    local raw
    if current then
        raw = P.RawStack()
    else
        -- Outside a trial this can repeat with every button the player
        -- presses: after the first twenty the stack is read once a second.
        local now = Clock()
        if idleReads < 20 or not now or not idleReadAt or now - idleReadAt >= 1 then
            idleReads, idleReadAt = idleReads + 1, now
            raw = P.RawStack()
        else
            raw = ""
        end
    end
    -- Blizzard's handler for the "blocked" event prints the line too; the
    -- event has already told us about that one.
    if raw:find("HandleActionBlocked", 1, true) or raw:find("HandleMacroActionBlocked", 1, true) then return end
    if current then
        Signal("blocked", nil, "the game's 'interface action failed' line, with no event", raw)
    else
        Aftermath("message", nil, raw)
    end
end

-- Puts our hook on the game's message function. One build of that function
-- swaps itself for an empty one after its first call, which would drop the
-- hook, so this is checked again before every trial.
local function EnsureHook()
    if type(hooksecurefunc) ~= "function" then return end
    local fn = _G[BLOCKED_FN]
    if type(fn) ~= "function" or fn == hookedFn then return end
    hooksecurefunc(BLOCKED_FN, function() pcall(OnBlockedMessage) end)
    hookedFn = _G[BLOCKED_FN]
end

local function OnError(err)
    Signal("error", nil, P.Plain(err), nil)
    return err
end

---------------------------------------------------------------------------
-- One trial
---------------------------------------------------------------------------

local vendorDone = {}       -- [trial id | situation key] = true: tried this session

local function MissingNeed(trial)
    for _, path in ipairs(trial.needs or {}) do
        if Find(path) == nil then return path end
    end
    return nil
end

local function GateOpen(trial)
    if trial.event then return false end
    if not trial.gate then return true end
    local ok, open = pcall(trial.gate)
    return ok and open and true or false
end

-- True if the trial could really be tried right now (used to pick the trial
-- that runs straight from a press).
local function CanRunNow(trial)
    if not GateOpen(trial) or MissingNeed(trial) then return false end
    if trial.ready then
        local ok, ready = pcall(trial.ready)
        if not ok or not ready then return false end
    end
    return true
end

local function Describe(s)
    return s.kind .. (s.func and (" " .. s.func) or "") .. ((s.kind == "error" and s.message) and (": " .. s.message) or "")
end

-- Works out the result from what was noticed and what the trial reported.
local function Conclude(trial, key, inPress, cur, expected, message)
    local forbidden, blocked, err
    for _, s in ipairs(cur.signals) do
        if s.kind == "forbidden" then
            forbidden = forbidden or s
        elseif s.kind == "blocked" then
            if not blocked or (not blocked.func and s.func) then blocked = s end
        else
            err = err or s
        end
    end
    local sig = forbidden or blocked or err
    local result
    local notes = {}
    local replace = nil
    if trial.kind == "info" then
        -- An "info" trial's answer is the short text it returned.
        replace = true
        if sig then
            result = (sig.kind == "error") and "error" or sig.kind
            notes[#notes + 1] = (sig.kind == "error") and sig.message or Describe(sig)
        elseif expected == "missing" then
            result = "missing"
            message = (message or "a function") .. " is not on this client"
        else
            result = (type(expected) == "string" and expected ~= "") and expected or "nil"
        end
    elseif trial.kind == "value" then
        if sig then
            result = "error"
            notes[#notes + 1] = (sig.kind == "error") and sig.message or Describe(sig)
        else
            result = expected
        end
    elseif sig then
        result = sig.kind
        if sig.message then notes[#notes + 1] = sig.message end
    elseif expected == "missing" then
        result = "missing"
        message = (message or "a method") .. " is not on this client"
    elseif expected == P.CANT_TELL then
        -- Nothing refused it, but the trial could not see whether it worked.
        result = P.CANT_TELL
    elseif expected == false then
        result = "no effect"
    else
        result = "allowed"
    end
    if message then notes[#notes + 1] = message end
    if #cur.signals > 1 then
        local all = {}
        for i, s in ipairs(cur.signals) do all[i] = Describe(s) end
        notes[#notes + 1] = #cur.signals .. " signs: " .. tconcat(all, "; ")
    end
    for _, s in ipairs(cur.undoSignals) do
        local note = "while putting it back: " .. Describe(s)
        notes[#notes + 1] = note
        Log(trial.id .. " " .. note)
    end
    P.Record(trial.id, key, result, {
        func = sig and sig.func, stack = sig and sig.stack, inPress = inPress, replace = replace,
        message = (#notes > 0) and P.Plain(tconcat(notes, " | "), P.MESSAGE_MAX) or nil,
        keep = (trial.kind == "value" and #notes > 0) or nil,   -- numbers a value trial noted get a detail entry
    })
end

-- Runs one trial and calls done() when its result is stored (at once, or
-- about a second later for the vendor trials). inPress: true when this call
-- is in the tap's own call stack, false when a press pass reached it on a
-- timer, nil in other passes.
local function RunTrial(trial, pass, inPress, done)
    local key = pass.key
    if not GateOpen(trial) then return done() end
    local missing = MissingNeed(trial)
    if missing then
        P.Record(trial.id, key, "missing", { message = missing .. " is not on this client", inPress = inPress })
        return done()
    end
    if trial.vendor and pass.trigger == "auto" and vendorDone[trial.id .. "|" .. key] then return done() end
    if trial.ready then
        local ok, ready, reason = pcall(trial.ready)
        if not ok then
            P.Record(trial.id, key, "error", { message = P.Plain(ready), inPress = inPress })
            return done()
        end
        if not ready then
            if reason then Log(trial.id .. ": not tried, " .. reason) end
            return done(reason or "nothing to try right now")
        end
    end

    EnsureHook()
    local state = {}
    local cur = { signals = {}, undoSignals = {}, phase = "run", id = trial.id }
    if trial.undo then cur.undo = function() trial.undo(state) end end
    current = cur

    local function Finish(expected, message)
        cur.phase = "undo"
        if trial.undo and not cur.undone then
            cur.undone = true
            local ok, err = pcall(trial.undo, state)
            if not ok then cur.undoSignals[#cur.undoSignals + 1] = { kind = "error", message = P.Plain(err) } end
        end
        if current == cur then current = nil end
        lastTrial, lastTrigger = trial.id, pass.trigger
        if trial.vendor then vendorDone[trial.id .. "|" .. key] = true end
        Conclude(trial, key, inPress, cur, expected, message)
        done()
    end

    if trial.kind == "value" then
        local classes = P.Classes()
        xpcall(trial.read, OnError, classes)
        return Finish(classes:result())
    end

    local ok, expected, message = xpcall(trial.run, OnError, state)
    if not ok then expected, message = nil, nil end
    if expected == "wait" then
        local started = After(trial.wait or 1, function()
            local ok2, later, laterMessage = xpcall(trial.check, OnError, state)
            if not ok2 then later, laterMessage = nil, nil end
            Finish(later, laterMessage)
        end)
        if started then return end
        expected, message = nil, "no timer on this client, so the outcome was not checked"
    end
    Finish(expected, message)
end

---------------------------------------------------------------------------
-- The small Probe button and its status line (made now, at load, so nothing
-- is created in a fight). Probe opens the panel (Panel.lua). Stop shows while
-- something runs; Next shows while the clean series waits for its reload.
---------------------------------------------------------------------------

local function MakeButton(name, text, width, height)
    local b = CreateFrame("Button", name, UIParent)
    b:SetSize(width, height)
    b:SetFrameStrata("HIGH")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0, 0, 0, 0.65)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", b, "CENTER", 0, 0)
    label:SetText(text)
    b.label = label
    return b
end

local GAP = 6
local probeButton = MakeButton("PocketProbeButton", "Probe", 120, 48)
probeButton:SetPoint("TOP", UIParent, "TOP", 0, -4)

local statusFrame = CreateFrame("Frame", "PocketProbeStatus", UIParent)
statusFrame:SetSize(430, 20)
statusFrame:SetFrameStrata("HIGH")
statusFrame:SetPoint("TOP", probeButton, "BOTTOM", 0, -2)
local statusBg = statusFrame:CreateTexture(nil, "BACKGROUND")
statusBg:SetAllPoints(statusFrame)
statusBg:SetColorTexture(0, 0, 0, 0.5)
local statusText = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("TOP", statusFrame, "TOP", 0, -3)
statusText:SetText("loading")
local warningText = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
warningText:SetPoint("BOTTOM", statusFrame, "BOTTOM", 0, 3)
warningText:SetText("")
warningText:Hide()

-- Shown from the first refusal outside a trial until the reload, so the
-- player knows why interact or cancel may have stopped working.
ShowWarning = function()
    if P.warning then return end
    P.warning = WARNING
    statusFrame:SetHeight(38)
    warningText:SetText(WARNING)
    warningText:Show()
    if P.OnStatus then pcall(P.OnStatus) end
end

local stopButton = MakeButton("PocketProbeStopButton", "Stop", 112, 40)
stopButton:SetPoint("TOPLEFT", statusFrame, "BOTTOMLEFT", 0, -2)
stopButton:Hide()

local nextButton = MakeButton("PocketProbeNextButton", "Next (reload)", 280, 72)
nextButton:SetPoint("TOPLEFT", stopButton, "TOPRIGHT", GAP, 0)
nextButton:Hide()

local pass                  -- the pass under way, or nil
local cleanHold = false     -- the clean series has this session: no passes

local function Busy()
    return pass ~= nil or current ~= nil or cleanHold
end
P.Busy = Busy

-- While a guided trial waits, the status line says so, whatever else it says.
local function GuidedNote()
    if not db or type(db.guided) ~= "table" then return nil end
    local ids = {}
    for id in pairs(db.guided) do ids[#ids + 1] = tostring(id) end
    if #ids == 0 then return nil end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        local g, t = db.guided[id], P.trialById[id]
        local name = (t and (t.short or t.label)) or id
        local stage = type(g) == "table" and g.stage or nil
        if stage == "restart" then
            parts[#parts + 1] = name .. " is waiting for a game restart, or Cancel"
        elseif stage == "putback" then
            parts[#parts + 1] = name .. " could not put back: tap Cancel to retry"
        elseif stage == "prepare" then
            parts[#parts + 1] = name .. " is starting: wait for the big message, or Cancel"
        else
            parts[#parts + 1] = name .. " is waiting: answer or Cancel"
        end
    end
    return tconcat(parts, "; ")
end

local function SetStatus(text)
    local note = GuidedNote()
    if note then text = text .. " — " .. note end
    P.status = text
    statusText:SetText(text)
    if Busy() then stopButton:Show() else stopButton:Hide() end
    if P.OnStatus then pcall(P.OnStatus) end
end
P.SetStatus = SetStatus

local function Covered()
    local n = P.SituationCount()
    return n .. (n == 1 and " situation covered" or " situations covered")
end

---------------------------------------------------------------------------
-- Passes
---------------------------------------------------------------------------

local completed = {}        -- [situation key] = true: a whole automatic pass ran this session
local pendingFull, pendingVendor = false, false
local watchToken = 0        -- changes when a clean trial's watch for after-effects is called off

local TryFull, TryVendor    -- below

local function VendorOn()
    return P.vendorOpen == true and db.options.vendor == true
end

local function RiskyOn()
    return db.options.risky == true
end

local function AutoOn()
    return db.options.auto == true
end

local function VendorList(into)
    local list = into or {}
    for _, t in ipairs(P.trials) do
        if t.vendor then list[#list + 1] = t end
    end
    return list
end

-- The run order of an automatic pass (the passes of 0.2.0): the actions that
-- are not risky, then (withVendor) the vendor trials, then the values, and the
-- risky actions last so that whatever they leave behind cannot colour the
-- rest. With the "Risky" switch off they are left out altogether. Trials
-- marked manual (the Errors and Graphics areas) are never in these passes.
local function StandardList(withVendor)
    local list, risky = {}, {}
    for _, t in ipairs(P.trials) do
        if t.kind == "action" and not t.vendor and not t.manual then
            if t.risky then risky[#risky + 1] = t else list[#list + 1] = t end
        end
    end
    if withVendor then VendorList(list) end
    for _, t in ipairs(P.trials) do
        if t.kind == "value" and not t.event and not t.manual then list[#list + 1] = t end
    end
    if RiskyOn() then
        for _, t in ipairs(risky) do list[#list + 1] = t end
    end
    return list
end

-- "Run all safe": every trial that is not risky, guided or waiting for an
-- event: actions, then (withVendor) the vendor trials, then values and
-- the "info" trials, and last the trials marked last (the two that raise a
-- test error and make the game's error box pop up).
local function SafeList(withVendor)
    local list, last = {}, {}
    for _, t in ipairs(P.trials) do
        if t.kind == "action" and not t.vendor and not t.risky then
            if t.last then last[#last + 1] = t else list[#list + 1] = t end
        end
    end
    if withVendor then VendorList(list) end
    for _, t in ipairs(P.trials) do
        if (t.kind == "value" or t.kind == "info") and not t.event and not t.risky then list[#list + 1] = t end
    end
    for _, t in ipairs(last) do list[#list + 1] = t end
    return list
end
P.SafeList = SafeList

-- A situation counts as covered separately with and without the risky trials.
local function DoneKey(key)
    return key .. (RiskyOn() and " +risky" or "")
end

-- "Fight tests": the trials marked fight that are not risky, in file order;
-- then the rest of what Run all safe runs, without the trials marked noFight
-- (known to be refused in a fight), last (they pop the game's error box) or
-- manual, and without the vendor trials; with Risky on, the risky trials
-- marked fight come last.
local function FightList()
    local list, listed = {}, {}
    local function add(t)
        if not listed[t.id] then
            listed[t.id] = true
            list[#list + 1] = t
        end
    end
    local function passable(t) return t.kind ~= "guided" and not t.event and not t.vendor end
    for _, t in ipairs(P.trials) do
        if t.fight and not t.risky and passable(t) then add(t) end
    end
    for _, t in ipairs(SafeList(false)) do
        if not t.fight and not t.noFight and not t.last and not t.manual then add(t) end
    end
    if RiskyOn() then
        for _, t in ipairs(P.trials) do
            if t.fight and t.risky and passable(t) then add(t) end
        end
    end
    return list
end
P.FightList = FightList

-- The fight tests' last words: how many ran, were allowed, were refused.
local function FightSummary(p, words)
    return words .. ": " .. p.run .. " run, " .. p.good .. " allowed or readable, " .. p.refused .. " refused"
end

local function FinishPass(p)
    pass = nil
    if p.full then
        completed[p.doneKey] = true
        local s = db.situations[p.key]
        if type(s) == "table" then s.passes = (type(s.passes) == "number" and s.passes or 0) + 1 end
    end
    Log("pass done: " .. p.key)
    if p.ran then
        Log("fight tests: " .. tconcat(p.ran, ", "), LIST_LOG)
        SetStatus(FightSummary(p, "Fight tests done"))
    else
        SetStatus("pass done — " .. Covered())
    end
    if pendingFull then
        pendingFull = false
        TryFull()
    elseif pendingVendor then
        pendingVendor = false
        TryVendor()
    end
end

local NextStep              -- below

local REFUSED = { blocked = true, forbidden = true, error = true }

-- One trial of a pass, then the next after a short wait. A pass that keeps
-- count (the fight tests: p.ran) notes each trial's result as it is stored.
local function Step(p, trial, inPress)
    local before = db.last[trial.id]
    RunTrial(trial, p, inPress, function()
        if p.ran then
            -- A trial that stored a result has a new "last" entry; one not tried has not.
            local now = db.last[trial.id]
            local result = (now ~= before and type(now) == "table") and tostring(now.result) or nil
            p.ran[#p.ran + 1] = trial.id .. " " .. (result or "not tried")
            if result then
                p.run = p.run + 1
                if result == "allowed" or result == "readable" then p.good = p.good + 1 end
                if REFUSED[result] then p.refused = p.refused + 1 end
            end
        end
        After(STEP, function() NextStep(p) end)
    end)
end

NextStep = function(p)
    if pass ~= p then return end
    -- A fight starting or ending mid-pass: the trial just run is kept, the
    -- pass stops and (with Auto on) the new situation gets its own pass.
    if P.Situation(p.trigger) ~= p.key then
        pass = nil
        Log("pass stopped: the situation changed")
        if p.ran then
            Log("fight tests stopped, the fight ended: " .. tconcat(p.ran, ", "), LIST_LOG)
            SetStatus(FightSummary(p, "Fight tests stopped, the fight ended"))
        else
            SetStatus("situation changed")
        end
        After(FIGHT_DELAY, TryFull)
        return
    end
    p.pos = p.pos + 1
    local trial = p.list[p.pos]
    if not trial then return FinishPass(p) end
    SetStatus("pass " .. p.pos .. "/" .. #p.list .. " " .. trial.id)
    local inPress = nil
    if p.trigger == "press" then inPress = false end
    Step(p, trial, inPress)
end

-- firstInPress: list[1] runs right now, in the caller's own call stack.
-- note: what a pass that is not a whole one is ("vendor trials only").
-- count: the pass keeps each trial's result for its last line (the fight tests).
local function StartPass(trigger, list, full, firstInPress, note, count)
    local key, facts = P.Situation(trigger)
    P.EnsureSituation(key, facts)
    local p = { trigger = trigger, key = key, list = list, pos = 0, full = full, doneKey = DoneKey(key) }
    if count then p.ran, p.run, p.good, p.refused = {}, 0, 0, 0 end
    pass = p
    FlushQuiet()
    Log("pass started: " .. key .. (note and (" (" .. note .. ")") or ""))
    if full and trigger == "auto" and not RiskyOn() then Log("risky trials off") end
    if firstInPress and list[1] then
        p.pos = 1
        SetStatus("pass 1/" .. #list .. " " .. list[1].id)
        Step(p, list[1], true)
    else
        NextStep(p)
    end
end

-- An automatic pass (Auto on only), unless this situation already had one
-- this session.
TryFull = function()
    if not db or cleanHold or not AutoOn() then return end
    if pass then
        pendingFull = true
        return
    end
    if completed[DoneKey((P.Situation("auto")))] then return end
    StartPass("auto", StandardList(false), true)
end

-- The vendor trials by themselves, when a vendor window opens (Auto on only).
TryVendor = function()
    if not db or cleanHold or not AutoOn() then return end
    if pass then
        pendingVendor = true
        return
    end
    if not VendorOn() then return end
    StartPass("auto", VendorList(), false, false, "vendor trials only")
end

-- Says why nothing can start now, or returns nil.
local function Refusal()
    if not db then return "loading" end
    if cleanHold then return "the clean run is going: tap Next, or Stop" end
    if current then return "wait: " .. tostring(current.id) .. " is still running" end
    return nil
end

local function TakeOver(why)
    if not pass then return end
    Log("pass stopped: " .. why)
    if pass.full and pass.trigger == "auto" then pendingFull = true end
    pass = nil
end

-- "Run all safe": a pass straight from the tap. Its first trial runs inside
-- the tap, because whether the game treats an action as coming from a real
-- press is one of the things being measured; the rest follow on timers.
local function RunAllSafe()
    local why = Refusal()
    if why then return SetStatus(why) end
    TakeOver("Run all safe takes over")
    local list = SafeList(VendorOn())
    StartPass("press", list, true, true, "run all safe")
end

-- "Fight tests": one tap in a fight runs what is worth running there (see
-- FightList), the first trial inside the tap as Run all safe does. Out of a
-- fight it only says so: Run all safe covers the rest.
local function RunFightTests()
    local why = Refusal()
    if why then return SetStatus(why) end
    local _, facts = P.Situation("press")
    if not facts.lockdown then return SetStatus("Fight tests: start a fight first, then tap this.") end
    TakeOver("Fight tests take over")
    StartPass("press", FightList(), false, true, "fight tests", true)
end

-- One trial, straight from its Run button.
local function RunOne(trial)
    if type(trial) ~= "table" then return end
    local why = Refusal()
    if why then return SetStatus(why) end
    if trial.kind == "guided" then return SetStatus("a guided trial: use Start, then its two answers") end
    if trial.event then return SetStatus(trial.id .. " is recorded when its event arrives") end
    if trial.risky and not RiskyOn() then return SetStatus("risky trials are off: switch Risky on first") end
    if trial.vendor then
        if not db.options.vendor then return SetStatus("vendor trials are off: switch Vendor on first") end
        if not P.vendorOpen then return SetStatus("open a vendor first") end
    end
    TakeOver("a single trial takes over")
    local key, facts = P.Situation("press")
    P.EnsureSituation(key, facts)
    FlushQuiet()
    SetStatus("running " .. trial.id)
    RunTrial(trial, { trigger = "press", key = key }, true, function(reason)
        if reason then
            SetStatus(trial.id .. ": not tried, " .. reason)
        else
            SetStatus(trial.id .. " done")
        end
    end)
end

local CancelAllGuided       -- below, with the guided trials
local PutBack               -- below, with the guided trials

local function Stop()
    pass = nil
    pendingFull, pendingVendor = false, false
    CancelAllGuided("stopped")
    if db and db.clean.running then
        db.clean.running = false
        Log("clean trials stopped")
    end
    cleanHold = false
    watchToken = watchToken + 1
    P.cleanWaiting = nil
    nextButton:Hide()
    Log("stopped")
    SetStatus("stopped — " .. Covered())
end

---------------------------------------------------------------------------
-- Clean trials: one per reload, each the first thing the probe does
---------------------------------------------------------------------------

local cleanRan = false      -- this session's clean trial has been started
local WATCH = 8             -- seconds after a clean trial in which after-effects are watched for

local function CleanDone(i, n)
    db.clean.index = i
    P.cleanWaiting = nil
    if i >= n then
        db.clean.running = false
        cleanHold = false
        nextButton:Hide()
        Log("clean trials done")
        SetStatus("clean trials done")
    else
        SetStatus("clean trial " .. i .. " of " .. n .. ": tap Next")
        nextButton:Show()
    end
end

local function RunCleanTrial(trial, i, n)
    P.cleanWaiting = nil
    nextButton:Hide()
    local key, facts = P.Situation("clean")
    local s = P.EnsureSituation(key, facts)
    SetStatus("clean trial " .. i .. " of " .. n .. ": " .. trial.id)
    Log("clean trial " .. i .. " of " .. n .. ": " .. trial.id .. " in " .. key)
    RunTrial(trial, { trigger = "clean", key = key }, nil, function()
        s.passes = (type(s.passes) == "number" and s.passes or 0) + 1
        db.clean.index = i
        -- Nothing else runs now: a refusal in the next seconds can only come
        -- from this one trial. Next is offered when the watch is over.
        watchToken = watchToken + 1
        local token = watchToken
        local function Watch(left)
            if token ~= watchToken or not cleanHold then return end
            if left <= 0 then return CleanDone(i, n) end
            SetStatus("clean trial " .. i .. " of " .. n .. ": watching for after-effects… " .. left)
            if not After(1, function() Watch(left - 1) end) then CleanDone(i, n) end
        end
        Watch(WATCH)
    end)
end

local function StartClean()
    if cleanRan or not db or not db.clean.running then return end
    cleanRan = true
    local n = #P.cleanList
    local i = db.clean.index + 1
    local trial = P.cleanList[i]
    if not trial then return CleanDone(n, n) end
    if trial.vendor then
        if not db.options.vendor then
            Log(trial.id .. ": not tried, vendor trials are switched off")
            return CleanDone(i, n)
        end
        if not P.vendorOpen then
            P.cleanWaiting = { trial = trial, i = i, n = n }
            SetStatus("clean trial " .. i .. " of " .. n .. ": open a vendor (Next skips it)")
            nextButton:Show()
            return
        end
    end
    RunCleanTrial(trial, i, n)
end

local function BeginClean()
    if not db then return end
    pass = nil
    pendingFull, pendingVendor = false, false
    db.clean.index = 0
    db.clean.running = true
    cleanHold = true
    Log("clean trials started")
    SetStatus("clean trials: reloading")
    Reload()
end

---------------------------------------------------------------------------
-- Guided trials. Start saves the old values of the trial's settings in the
-- saved table, sets the new ones and shows the steps. The answer is stored
-- like any result, and only then are the old values put back. The saved
-- table keeps all of it, so a full restart (or a reload) loses nothing.
--
--   db.guided[id] = { stage = "prepare" | "restart" | "ask" | "putback",
--                     old = { [name] = value | false }, started = "<date time>",
--                     notes = "<what was set>" }
-- stage "prepare": a trial with screenshots is going through its timed steps
-- (below); nothing is asked yet. "restart": waiting for a full restart (PLAYER_ENTERING_WORLD with
-- isInitialLogin true); a reload is not enough. "ask": the two answer
-- buttons show. "putback": answered, but some old values could not be
-- written back; old then holds only those, and Cancel tries again.
-- old[name] = false: the setting is not on this client.
--
-- Nothing is left changed for good: Cancel, Stop and /probe stop put the old
-- values back, and so does logging out for a trial that needs no restart.
--
-- A trial with shots = true (probe 0.5.0) starts in timed steps, so the two
-- screenshots show the screen before and after its change: the panel closes;
-- half a second later screenshot 1; half a second later the change (the
-- trial's ready() is asked again first: a fight that has started since means
-- nothing is changed); half a second later screenshot 2; then the question.
-- A trial with a big text has its question shown in big letters (Panel.lua)
-- from then until it is answered or called off.
---------------------------------------------------------------------------

local bigFor                -- the id of the trial whose big message is showing

local function ShowBig(id, text)
    bigFor = id
    if P.ShowBig then P.ShowBig(text) end
end

local function HideBig(id)
    if bigFor ~= id then return end
    bigFor = nil
    if P.HideBig then P.HideBig() end
end

-- One screenshot, if this client has the function. Counted on the trial's entry.
local function Shot(g)
    local shot = Find("Screenshot")
    if type(shot) ~= "function" then return end
    g.shotsTried = true
    if pcall(shot) then g.shots = (g.shots or 0) + 1 end
end

local function ShotsNote(g)
    local note
    if (g.shots or 0) > 0 then
        note = "screenshots: " .. g.shots
    elseif g.shotsTried then
        note = "screenshots: none (the call failed)"
    else
        note = "screenshots: none (not on this client)"
    end
    g.shots, g.shotsTried = nil, nil
    return note
end

local function SettingNow(name)
    local get = Find("C_CVar.GetCVar")
    if type(get) ~= "function" then return nil end
    local ok, v = pcall(get, name)
    return ok and Str(v) or nil
end

local function WriteSetting(name, value)
    local set = Find("C_CVar.SetCVar")
    if type(set) ~= "function" then return false end
    local ok, done = pcall(set, name, value)
    return ok and not IsSecret(done) and done and true or false
end

-- Runs fn() (a guided trial's apply or restore) the way a trial runs, so a
-- block or an error in it is pinned on that trial and not counted as an
-- after-effect. Returns its two answers, the strongest sign seen, and all signs.
local function Watched(id, fn)
    EnsureHook()
    local cur = { signals = {}, undoSignals = {}, phase = "run", id = id }
    local before = current
    current = cur
    local ok, a, b = xpcall(fn, OnError)
    current = before
    local sig
    for _, s in ipairs(cur.signals) do
        if s.kind == "forbidden" then sig = s break end
        if s.kind == "blocked" and (not sig or sig.kind == "error") then sig = s
        elseif not sig then sig = s end
    end
    if not ok then a, b = nil, nil end
    return a, b, sig, cur.signals
end

-- A trial that changes a frame (apply / restore in Trials.lua) does it here.
-- True when it went through. Otherwise there is nothing to ask about: the
-- result is stored now, anything changed goes back, and false is returned.
local function ApplyGuided(trial, g, notes, inPress)
    if not trial.apply then return true end
    g.applied = true
    local done, note, sig, all = Watched(trial.id, trial.apply)
    if note then notes[#notes + 1] = P.Plain(note, 1000) end
    if not sig and done == true then return true end
    if trial.shots then notes[#notes + 1] = ShotsNote(g) end
    g.notes = tconcat(notes, ", ")
    local failed = PutBack(trial.id, g)
    local result = sig and ((sig.kind == "error") and "error" or sig.kind)
        or ((done == "missing") and "missing" or "no effect")
    if sig and sig.message then notes[#notes + 1] = sig.message end
    if #all > 1 then notes[#notes + 1] = #all .. " signs" end
    if #failed > 0 then notes[#notes + 1] = "could not put back " .. tconcat(failed, ", ") end
    local key, facts = P.Situation("press")
    P.EnsureSituation(key, facts)
    P.Record(trial.id, key, result, {
        func = sig and sig.func, stack = sig and sig.stack, inPress = inPress,
        message = P.Plain(tconcat(notes, "; "), P.MESSAGE_MAX),
    })
    SetStatus(trial.id .. ": " .. result .. (#failed > 0 and ("; could not put back " .. tconcat(failed, ", ")) or ""))
    return false
end

-- The question: from here the trial waits for its answer (or for a restart).
local function AskGuided(trial, g, notes)
    g.notes = tconcat(notes, ", ")
    g.stage = trial.restart and "restart" or "ask"
    Log(trial.id .. ": started; " .. g.notes, P.MESSAGE_MAX)
    -- The panel holds the d-pad and A while open: closed so a press reaches the game.
    if trial.closePanel and P.HidePanel then P.HidePanel() end
    if g.stage == "ask" and trial.big then
        -- The big message says what to do; the status line stays short.
        ShowBig(trial.id, trial.big)
        return SetStatus(trial.id .. ": started")
    end
    SetStatus(trial.id .. ": " .. (g.stage == "restart" and (trial.steps or "restart the game") or (trial.ask or "answer")))
end

-- The timed steps of a trial with screenshots (see the top of this section).
-- Cancel, Stop or a logout in between take the entry away, and the steps stop.
local function StartInSteps(trial, g, notes)
    local id = trial.id
    local function alive() return db.guided[id] == g and g.stage == "prepare" end
    if trial.closePanel and P.HidePanel then P.HidePanel() end
    SetStatus(id .. ": starting")
    local function ask()
        if not alive() then return end
        notes[#notes + 1] = ShotsNote(g)
        AskGuided(trial, g, notes)
    end
    local function change()
        if not alive() then return end
        if trial.ready then
            local ok, ready, reason = pcall(trial.ready)
            if not ok or not ready then
                local why = tostring(ok and (reason or "not now") or P.Plain(ready))
                PutBack(id, g)
                Log(id .. ": not tried, " .. why)
                return SetStatus(id .. ": not tried, " .. why)
            end
        end
        if not ApplyGuided(trial, g, notes, false) then return end
        local function second()
            if not alive() then return end
            Shot(g)
            ask()
        end
        if not After(SHOT_GAP, second) then ask() end
    end
    local function first()
        if not alive() then return end
        Shot(g)
        if not After(SHOT_GAP, change) then change() end
    end
    if not After(SHOT_GAP, first) then change() end
end

local function StartGuided(trial)
    if type(trial) ~= "table" or trial.kind ~= "guided" then return end
    local why = Refusal()
    if why then return SetStatus(why) end
    if db.guided[trial.id] then return SetStatus(trial.id .. " is already waiting for an answer") end
    if trial.risky and not RiskyOn() then return SetStatus("risky trials are off: switch Risky on first") end
    local missing = MissingNeed(trial)
    if missing then
        P.Record(trial.id, (P.Situation("press")), "missing", { message = missing .. " is not on this client" })
        return SetStatus(trial.id .. ": " .. missing .. " is not on this client")
    end
    if trial.ready then
        local ok, ready, reason = pcall(trial.ready)
        if not ok or not ready then
            return SetStatus(trial.id .. ": not started, " .. tostring(ok and (reason or "not now") or P.Plain(ready)))
        end
    end
    -- What to set: the trial's own settings, plus each "ifZero" setting that is 0 now.
    local settings = {}
    for _, pair in ipairs(trial.settings or {}) do settings[#settings + 1] = pair end
    for _, name in ipairs(trial.ifZero or {}) do
        if SettingNow(name) == "0" then settings[#settings + 1] = { name, "1" } end
    end
    local old, notes = {}, {}
    for _, pair in ipairs(settings) do
        local value = SettingNow(pair[1])
        old[pair[1]] = value == nil and false or value
    end
    -- Saved before anything is changed, so a crash still leaves the old values to put back.
    local g = { stage = trial.shots and "prepare" or (trial.restart and "restart" or "ask"), old = old,
        started = P.Stamp("%Y-%m-%d %H:%M:%S") }
    db.guided[trial.id] = g
    for _, pair in ipairs(settings) do
        local name, value = pair[1], pair[2]
        if old[name] == false then
            notes[#notes + 1] = name .. " not on this client"
        else
            local written = WriteSetting(name, value)
            notes[#notes + 1] = name .. " " .. tostring(old[name]) .. " -> " .. value .. (written and "" or " (refused)")
        end
    end
    -- Settings only noted, so the answer can be read against them.
    for _, name in ipairs(trial.watch or {}) do
        if old[name] == nil then notes[#notes + 1] = name .. " " .. tostring(SettingNow(name) or "not on this client") end
    end
    if trial.shots then return StartInSteps(trial, g, notes) end
    if not ApplyGuided(trial, g, notes, true) then return end
    AskGuided(trial, g, notes)
end

-- Writes the old values back. Keeps the entry, holding only the settings that
-- failed, when any did; returns their names.
PutBack = function(id, g)
    -- The question is over, however this ends.
    HideBig(id)
    local failed = P.PutBackSettings(g.old)
    local keep = {}
    for _, name in ipairs(failed) do keep[name] = g.old[name] end
    local t = P.trialById[id]
    if g.applied and t and t.restore then
        local done, why, sig = Watched(id, t.restore)
        if done == true and not sig then
            g.applied, g.held = nil, nil
            if why then
                g.restoreNote = P.Plain(why, 120)
                Log(tostring(id) .. ": " .. g.restoreNote)
            end
        else
            why = sig and Describe(sig) or why
            g.held = tostring(t.hold or "a frame") .. (why and (" (" .. P.Plain(why, 120) .. ")") or "")
            failed[#failed + 1] = g.held
        end
    end
    if #failed == 0 then
        db.guided[id] = nil
    else
        g.old, g.stage = keep, "putback"
        Log(tostring(id) .. ": could not put back " .. tconcat(failed, ", "))
    end
    return failed
end

-- After a fight: a guided trial whose frame could not go back in it tries again.
local function RetryHeld()
    if not db then return end
    local ids = {}
    for id, g in pairs(db.guided) do
        if type(g) == "table" and g.stage == "putback" and g.applied then ids[#ids + 1] = id end
    end
    for _, id in ipairs(ids) do
        local failed = PutBack(id, db.guided[id])
        if #failed == 0 then
            Log(tostring(id) .. ": put back after the fight")
            SetStatus(tostring(id) .. ": put back after the fight")
        end
    end
end

local function CancelGuided(trial)
    if type(trial) ~= "table" then return end
    local g = db and db.guided[trial.id]
    if type(g) ~= "table" then return end
    local failed = PutBack(trial.id, g)
    if #failed == 0 then
        Log(trial.id .. ": cancelled; old values put back")
        SetStatus(trial.id .. ": cancelled, old values put back")
    else
        SetStatus(trial.id .. ": could not put back " .. tconcat(failed, ", ") .. ": tap Cancel to retry")
    end
end

-- Stop, /probe stop: every waiting guided trial is called off.
CancelAllGuided = function(why)
    if not db then return end
    local ids = {}
    for id in pairs(db.guided) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local g = db.guided[id]
        if type(g) == "table" then
            local failed = PutBack(id, g)
            Log(tostring(id) .. ": cancelled (" .. why .. ")" .. (#failed > 0 and "; some settings could not be put back" or ""))
        else
            db.guided[id] = nil
        end
    end
end

local function AnswerGuided(trial, index)
    if type(trial) ~= "table" or trial.kind ~= "guided" then return end
    local g = db and db.guided[trial.id]
    if type(g) ~= "table" or g.stage ~= "ask" then return end
    local answer = trial.answers and trial.answers[index]
    if type(answer) ~= "string" then return end
    local notes, started = g.notes, g.started
    -- What the trial reads at the answer, before anything is put back.
    if trial.atAnswer then
        local ok, note = pcall(trial.atAnswer)
        if ok and type(note) == "string" then notes = tostring(notes) .. ", " .. note end
    end
    local failed = PutBack(trial.id, g)
    if g.restoreNote then notes = tostring(notes) .. ", " .. g.restoreNote end
    local key, facts = P.Situation("press")
    P.EnsureSituation(key, facts)
    P.Record(trial.id, key, answer:lower(), {
        message = P.Plain("set: " .. tostring(notes) .. "; started " .. tostring(started) .. "; "
            .. (#failed > 0 and ("could not put back " .. tconcat(failed, ", ")) or "old values put back"), P.MESSAGE_MAX),
    })
    if #failed > 0 then
        SetStatus(trial.id .. ": answered; could not put back " .. tconcat(failed, ", ") .. ": tap Cancel to retry")
    else
        SetStatus(trial.id .. ": answered, old values put back")
    end
end

-- After a full restart, guided trials waiting for one ask their question.
local function GuidedAfterLogin(isInitialLogin)
    if IsSecret(isInitialLogin) or isInitialLogin ~= true then return end
    local asked = false
    for id, g in pairs(db.guided) do
        if type(g) == "table" and g.stage == "restart" then
            g.stage = "ask"
            asked = true
            Log(tostring(id) .. ": the game was restarted; waiting for the answer")
        end
    end
    if asked then SetStatus("the game was restarted: tap Probe and answer") end
end

-- Logging out (or a reload): a guided trial that needs no restart puts its
-- settings back, so none stays changed if the player never answers.
local function GuidedAtLogout()
    if not db then return end
    local ids = {}
    for id in pairs(db.guided) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local g, t = db.guided[id], P.trialById[id]
        if type(g) == "table" and not (t and t.restart) then
            if #PutBack(id, g) == 0 then Log(tostring(id) .. ": put back at logout") end
        end
    end
end

---------------------------------------------------------------------------
-- Switches
---------------------------------------------------------------------------

local OPTION_WORDS = { risky = "risky trials", vendor = "vendor trials", auto = "automatic passes" }

local function ToggleOption(name)
    if not db or not OPTION_WORDS[name] then return end
    db.options[name] = not db.options[name]
    Log(OPTION_WORDS[name] .. " switched " .. (db.options[name] and "on" or "off"))
    if name == "auto" then
        if db.options.auto then
            After(FIGHT_DELAY, TryFull)
        else
            pendingFull, pendingVendor = false, false
            if pass and pass.trigger == "auto" then
                pass = nil
                Log("pass stopped: automatic passes switched off")
            end
        end
    end
    SetStatus("idle — " .. Covered())
end

---------------------------------------------------------------------------
-- Button scripts and the slash command
---------------------------------------------------------------------------

local function TogglePanel()
    if P.TogglePanel then P.TogglePanel() end
end

probeButton:SetScript("OnClick", Guard(TogglePanel))
stopButton:SetScript("OnClick", Guard(Stop))
nextButton:SetScript("OnClick", Guard(function()
    -- A trial still waiting for a vendor window is skipped.
    local waiting = P.cleanWaiting
    if db and waiting then db.clean.index = waiting.i end
    Reload()
end))

SLASH_POCKETPROBE1 = "/probe"
if type(SlashCmdList) == "table" then
    SlashCmdList["POCKETPROBE"] = Guard(function(msg)
        local word = (Str(msg) or ""):lower():match("^%s*(%S*)")
        if word == "save" then
            Reload()
        elseif word == "clean" then
            BeginClean()
        elseif word == "stop" then
            Stop()
        elseif word == "run" then
            RunAllSafe()
        else
            TogglePanel()
        end
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local whisperSeen = {}      -- [situation key] = true: one whisper per situation per session

local function OnWhisper(...)
    if not db then return end
    local key, facts = P.Situation("auto")
    if whisperSeen[key] then return end
    whisperSeen[key] = true
    P.EnsureSituation(key, facts)
    local class, message = P.ClassesOf(...)
    P.Record("val.whisper", key, class, { message = message })
end

local handlers = {}

function handlers.ADDON_LOADED(name)
    if db or Str(name) ~= P.name then return end
    db = P.InitDB()
    cleanHold = db.clean.running
    if cleanHold then
        SetStatus("clean trials: the next one runs in a moment")
    else
        SetStatus("idle — " .. Covered() .. (AutoOn() and "" or " (tap Probe)"))
    end
end

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin)
    if not db then return end
    GuidedAfterLogin(isInitialLogin)
    if cleanHold then
        if not cleanRan then After(LOGIN_DELAY, StartClean) end
    else
        After(LOGIN_DELAY, TryFull)
    end
    if P.OnStatus then pcall(P.OnStatus) end
end

function handlers.PLAYER_REGEN_DISABLED()
    After(FIGHT_DELAY, TryFull)
    if P.OnCombat then P.OnCombat(true) end
end
function handlers.PLAYER_REGEN_ENABLED()
    After(FIGHT_DELAY, TryFull)
    After(FIGHT_DELAY, RetryHeld)
    if P.OnCombat then P.OnCombat(false) end
end
function handlers.ADDON_RESTRICTION_STATE_CHANGED() After(FIGHT_DELAY, TryFull) end

function handlers.MERCHANT_SHOW()
    P.vendorOpen = true
    if P.cleanWaiting then
        After(VENDOR_DELAY, function()
            local waiting = P.cleanWaiting
            if waiting and P.vendorOpen then RunCleanTrial(waiting.trial, waiting.i, waiting.n) end
        end)
    else
        After(VENDOR_DELAY, TryVendor)
    end
    if P.OnStatus then pcall(P.OnStatus) end
end

function handlers.MERCHANT_CLOSED()
    P.vendorOpen = false
    if P.OnStatus then pcall(P.OnStatus) end
end

function handlers.ADDON_ACTION_BLOCKED(addon, func) OnActionEvent("ADDON_ACTION_BLOCKED", addon, func) end
function handlers.ADDON_ACTION_FORBIDDEN(addon, func) OnActionEvent("ADDON_ACTION_FORBIDDEN", addon, func) end
function handlers.LUA_WARNING() if P.CountWarning then P.CountWarning() end end
handlers.CHAT_MSG_WHISPER = OnWhisper

-- The game writes the saved file after this: nothing may stay changed.
function handlers.PLAYER_LOGOUT()
    UndoCurrent("logging out")
    GuidedAtLogout()
end

local eventFrame = CreateFrame("Frame", nil, UIParent)
for event in pairs(handlers) do
    -- A client without the event raises an error on registering it.
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
        Log("event not on this client: " .. event)
    end
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if not handler then return end
    local ok, err = pcall(handler, ...)
    if not ok then pcall(Log, "error in the probe (" .. tostring(event) .. "): " .. P.Plain(err)) end
end)

EnsureHook()

-- For the panel and the offline tests.
P.RunAllSafe, P.RunOne, P.Stop, P.BeginClean, P.Reload = RunAllSafe, RunOne, Stop, BeginClean, Reload
P.ToggleOption, P.StartGuided, P.AnswerGuided = ToggleOption, StartGuided, AnswerGuided
P.CancelGuided = CancelGuided
P.RunFightTests = RunFightTests
