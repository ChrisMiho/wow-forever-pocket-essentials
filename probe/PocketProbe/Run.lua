local ADDON_NAME, P = ...

-- Running the trials: noticing when the game blocks one, the timed passes,
-- the clean series (one trial per reload) and the few buttons on screen.
--
-- Nothing here runs every frame. A pass is a chain of short timers
-- (C_Timer.After), one trial about every 0.3 seconds, and then it stops.

local type, ipairs, pcall, xpcall = type, ipairs, pcall, xpcall
local tconcat = table.concat
local Find, IsSecret, Str, Log, Guard = P.Find, P.IsSecret, P.Str, P.Log, P.Guard

local STEP = 0.3            -- seconds between trials
local LOGIN_DELAY = 3       -- after login or a loading screen
local FIGHT_DELAY = 1       -- after a fight starts or ends (lockdown begins after the event)
local VENDOR_DELAY = 0.3    -- after a vendor window opens

local db                    -- the saved table, once loaded

local function After(seconds, fn)
    local after = Find("C_Timer.After")
    if type(after) ~= "function" then return false end
    after(seconds, Guard(fn))
    return true
end

local FlushQuiet             -- below: writes the count of repeats not yet logged

local function Reload()
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

local current               -- the trial being run: { signals, undoSignals, phase }

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
    if Str(addon) ~= P.name then return end
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
    if trial.kind == "value" then
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
        func = sig and sig.func, stack = sig and sig.stack, inPress = inPress,
        message = (#notes > 0) and P.Plain(tconcat(notes, " | "), 400) or nil,
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
            return done()
        end
    end

    EnsureHook()
    local state = {}
    local cur = { signals = {}, undoSignals = {}, phase = "run" }
    current = cur

    local function Finish(expected, message)
        cur.phase = "undo"
        if trial.undo then
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
-- The buttons (made now, at load, so nothing is created in a fight)
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
end

local cleanButton = MakeButton("PocketProbeCleanButton", "Clean trials", 112, 40)
cleanButton:SetPoint("TOPLEFT", statusFrame, "BOTTOMLEFT", 0, -2)
local saveButton = MakeButton("PocketProbeSaveButton", "Save", 70, 40)
saveButton:SetPoint("LEFT", cleanButton, "RIGHT", GAP, 0)
local vendorButton = MakeButton("PocketProbeVendorButton", "Vendor trials: on", 160, 40)
vendorButton:SetPoint("LEFT", saveButton, "RIGHT", GAP, 0)
local stopButton = MakeButton("PocketProbeStopButton", "Stop", 70, 40)
stopButton:SetPoint("LEFT", vendorButton, "RIGHT", GAP, 0)

local riskyButton = MakeButton("PocketProbeRiskyButton", "Risky trials: off", 160, 40)
riskyButton:SetPoint("TOPLEFT", cleanButton, "BOTTOMLEFT", 0, -GAP)

local nextButton = MakeButton("PocketProbeNextButton", "Next (reload)", 280, 72)
nextButton:SetPoint("TOPLEFT", riskyButton, "TOPRIGHT", GAP, 0)
nextButton:Hide()

local function SetStatus(text)
    P.status = text
    statusText:SetText(text)
end

local function Covered()
    local n = P.SituationCount()
    return n .. (n == 1 and " situation covered" or " situations covered")
end

local function UpdateVendorLabel()
    vendorButton.label:SetText("Vendor trials: " .. ((db and db.options.vendor) and "on" or "off"))
    riskyButton.label:SetText("Risky trials: " .. ((db and db.options.risky) and "on" or "off"))
end

---------------------------------------------------------------------------
-- Passes
---------------------------------------------------------------------------

local pass                  -- the pass under way, or nil
local completed = {}        -- [situation key] = true: a whole pass ran this session
local pendingFull, pendingVendor = false, false
local cleanHold = false     -- the clean series has this session: no passes
local watchToken = 0        -- changes when a clean trial's watch for after-effects is called off

local TryFull, TryVendor    -- below

local function VendorOn()
    return P.vendorOpen == true and db.options.vendor == true
end

local function RiskyOn()
    return db.options.risky == true
end

local function VendorList(into)
    local list = into or {}
    for _, t in ipairs(P.trials) do
        if t.vendor then list[#list + 1] = t end
    end
    return list
end

-- The run order of an ordinary pass: the actions that are not risky, then
-- (withVendor) the vendor trials, then the values, and the risky actions
-- last so that whatever they leave behind cannot colour the rest. With the
-- "Risky trials" switch off they are left out altogether.
local function StandardList(withVendor)
    local list, risky = {}, {}
    for _, t in ipairs(P.trials) do
        if t.kind == "action" and not t.vendor then
            if t.risky then risky[#risky + 1] = t else list[#list + 1] = t end
        end
    end
    if withVendor then VendorList(list) end
    for _, t in ipairs(P.trials) do
        if t.kind == "value" and not t.event then list[#list + 1] = t end
    end
    if RiskyOn() then
        for _, t in ipairs(risky) do list[#list + 1] = t end
    end
    return list
end

-- A situation counts as covered separately with and without the risky trials.
local function DoneKey(key)
    return key .. (RiskyOn() and " +risky" or "")
end

local function FinishPass(p)
    pass = nil
    if p.full then
        completed[p.doneKey] = true
        local s = db.situations[p.key]
        if type(s) == "table" then s.passes = (type(s.passes) == "number" and s.passes or 0) + 1 end
    end
    Log("pass done: " .. p.key)
    SetStatus("pass done — " .. Covered())
    if pendingFull then
        pendingFull = false
        TryFull()
    elseif pendingVendor then
        pendingVendor = false
        TryVendor()
    end
end

local function NextStep(p)
    if pass ~= p then return end
    -- A fight starting or ending mid-pass: the trial just run is kept, the
    -- pass stops and the new situation gets its own pass.
    if P.Situation(p.trigger) ~= p.key then
        pass = nil
        Log("pass stopped: the situation changed")
        SetStatus("situation changed")
        After(FIGHT_DELAY, TryFull)
        return
    end
    p.pos = p.pos + 1
    local trial = p.list[p.pos]
    if not trial then return FinishPass(p) end
    SetStatus("pass " .. p.pos .. "/" .. #p.list .. " " .. trial.id)
    local inPress = nil
    if p.trigger == "press" then inPress = false end
    RunTrial(trial, p, inPress, function()
        After(STEP, function() NextStep(p) end)
    end)
end

-- firstInPress: list[1] runs right now, in the caller's own call stack.
-- note: what a pass that is not a whole one is ("vendor trials only").
local function StartPass(trigger, list, full, firstInPress, note)
    local key, facts = P.Situation(trigger)
    P.EnsureSituation(key, facts)
    local p = { trigger = trigger, key = key, list = list, pos = 0, full = full, doneKey = DoneKey(key) }
    pass = p
    FlushQuiet()
    Log("pass started: " .. key .. (note and (" (" .. note .. ")") or ""))
    if full and not RiskyOn() then Log("risky trials off") end
    if firstInPress then
        p.pos = 1
        SetStatus("pass 1/" .. #list .. " " .. list[1].id)
        RunTrial(list[1], p, true, function()
            After(STEP, function() NextStep(p) end)
        end)
    else
        NextStep(p)
    end
end

-- An automatic pass, unless this situation already had one this session.
TryFull = function()
    if not db or cleanHold then return end
    if pass then
        pendingFull = true
        return
    end
    if completed[DoneKey((P.Situation("auto")))] then return end
    StartPass("auto", StandardList(false), true)
end

-- The vendor trials by themselves, when a vendor window opens.
TryVendor = function()
    if not db or cleanHold then return end
    if pass then
        pendingVendor = true
        return
    end
    if not VendorOn() then return end
    StartPass("auto", VendorList(), false, false, "vendor trials only")
end

-- A pass straight from a tap (or /probe). Its first trial runs inside this
-- call, because whether the game treats an action as coming from a real
-- press is one of the things being measured. Each press starts with the
-- next action trial in turn, so repeated taps cover them all.
local function PressPass()
    if not db then return end
    if cleanHold then
        SetStatus("clean trials are running: tap Next, or Stop")
        return
    end
    if pass then
        Log("pass stopped: a press pass takes over")
        if pass.full and pass.trigger == "auto" then pendingFull = true end
        pass = nil
    end
    local actions = {}
    for _, t in ipairs(P.trials) do
        if t.kind == "action" and (RiskyOn() or not t.risky) then actions[#actions + 1] = t end
    end
    local first
    local n = #actions
    local start = (type(db.pressIndex) == "number") and db.pressIndex or 0
    for step = 1, n do
        local index = (start + step - 1) % n + 1
        if CanRunNow(actions[index]) then
            first = actions[index]
            db.pressIndex = index
            break
        end
    end
    -- A risky trial straight from the press is a pass of its own: nothing
    -- else is run after it in the same pass.
    if first and first.risky then
        Log("this press tries one risky trial only: " .. first.id)
        StartPass("press", { first }, false, true, "one risky trial only")
        return
    end
    local list = {}
    if first then list[1] = first end
    for _, t in ipairs(StandardList(VendorOn())) do
        if t ~= first then list[#list + 1] = t end
    end
    StartPass("press", list, true, first ~= nil)
end

local function Stop()
    pass = nil
    pendingFull, pendingVendor = false, false
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
-- Button scripts and the slash command
---------------------------------------------------------------------------

probeButton:SetScript("OnClick", Guard(PressPass))
cleanButton:SetScript("OnClick", Guard(BeginClean))
saveButton:SetScript("OnClick", Guard(Reload))
stopButton:SetScript("OnClick", Guard(Stop))
vendorButton:SetScript("OnClick", Guard(function()
    if not db then return end
    db.options.vendor = not db.options.vendor
    Log("vendor trials switched " .. (db.options.vendor and "on" or "off"))
    UpdateVendorLabel()
end))
riskyButton:SetScript("OnClick", Guard(function()
    if not db then return end
    db.options.risky = not db.options.risky
    Log("risky trials switched " .. (db.options.risky and "on" or "off"))
    UpdateVendorLabel()
end))
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
        else
            PressPass()
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
    UpdateVendorLabel()
    if cleanHold then
        SetStatus("clean trials: the next one runs in a moment")
    else
        SetStatus("idle — " .. Covered())
    end
end

function handlers.PLAYER_ENTERING_WORLD()
    if cleanHold then
        if not cleanRan then After(LOGIN_DELAY, StartClean) end
    else
        After(LOGIN_DELAY, TryFull)
    end
end

function handlers.PLAYER_REGEN_DISABLED() After(FIGHT_DELAY, TryFull) end
function handlers.PLAYER_REGEN_ENABLED() After(FIGHT_DELAY, TryFull) end
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
end

function handlers.MERCHANT_CLOSED()
    P.vendorOpen = false
end

function handlers.ADDON_ACTION_BLOCKED(addon, func) OnActionEvent("ADDON_ACTION_BLOCKED", addon, func) end
function handlers.ADDON_ACTION_FORBIDDEN(addon, func) OnActionEvent("ADDON_ACTION_FORBIDDEN", addon, func) end
handlers.CHAT_MSG_WHISPER = OnWhisper

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

-- For the offline tests.
P.PressPass, P.Stop, P.BeginClean = PressPass, Stop, BeginClean
