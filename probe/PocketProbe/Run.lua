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

local function Reload()
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

local function Signal(kind, func, message, rawStack)
    local s = { kind = kind, func = func, message = message, stack = P.TrimStack(rawStack) }
    local cur = current
    if not cur then
        Log("outside a trial: " .. kind .. (func and (" " .. func) or ""))
        return
    end
    local list = (cur.phase == "undo") and cur.undoSignals or cur.signals
    list[#list + 1] = s
end

local function OnActionEvent(event, addon, func)
    if Str(addon) ~= P.name then return end
    func = Str(func)
    if func == "" then func = nil end
    Signal(event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", func and func:sub(1, 120), nil, P.RawStack())
end

local BLOCKED_FN = "DisplayInterfaceActionBlockedMessage"
local hookedFn              -- the global as it was right after our hook went on
local idleNotes = 0

local function OnBlockedMessage()
    if not current then
        if idleNotes < 20 then
            idleNotes = idleNotes + 1
            Log("the game printed its 'interface action failed' line outside a trial")
        end
        return
    end
    local raw = P.RawStack()
    -- Blizzard's handler for the "blocked" event prints the line too; the
    -- event has already told us about that one.
    if raw:find("HandleActionBlocked", 1, true) or raw:find("HandleMacroActionBlocked", 1, true) then return end
    Signal("blocked", nil, "the game's 'interface action failed' line, with no event", raw)
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
    Signal("error", nil, P.Plain(err), P.RawStack())
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
statusText:SetPoint("CENTER", statusFrame, "CENTER", 0, 0)
statusText:SetText("loading")

local cleanButton = MakeButton("PocketProbeCleanButton", "Clean trials", 112, 40)
cleanButton:SetPoint("TOPLEFT", statusFrame, "BOTTOMLEFT", 0, -2)
local saveButton = MakeButton("PocketProbeSaveButton", "Save", 70, 40)
saveButton:SetPoint("LEFT", cleanButton, "RIGHT", GAP, 0)
local vendorButton = MakeButton("PocketProbeVendorButton", "Vendor trials: on", 160, 40)
vendorButton:SetPoint("LEFT", saveButton, "RIGHT", GAP, 0)
local stopButton = MakeButton("PocketProbeStopButton", "Stop", 70, 40)
stopButton:SetPoint("LEFT", vendorButton, "RIGHT", GAP, 0)

local nextButton = MakeButton("PocketProbeNextButton", "Next (reload)", 280, 72)
nextButton:SetPoint("TOP", cleanButton, "BOTTOM", 150, -8)
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
end

---------------------------------------------------------------------------
-- Passes
---------------------------------------------------------------------------

local pass                  -- the pass under way, or nil
local completed = {}        -- [situation key] = true: a whole pass ran this session
local pendingFull, pendingVendor = false, false
local cleanHold = false     -- the clean series has this session: no passes

local TryFull, TryVendor    -- below

local function VendorOn()
    return P.vendorOpen == true and db.options.vendor == true
end

-- Every trial that runs in an ordinary pass, in display order.
local function StandardList()
    local list = {}
    for _, t in ipairs(P.trials) do
        if not t.vendor and not t.event then list[#list + 1] = t end
    end
    return list
end

local function VendorList(into)
    local list = into or {}
    for _, t in ipairs(P.trials) do
        if t.vendor then list[#list + 1] = t end
    end
    return list
end

local function FinishPass(p)
    pass = nil
    if p.full then
        completed[p.key] = true
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
local function StartPass(trigger, list, full, firstInPress)
    local key, facts = P.Situation(trigger)
    P.EnsureSituation(key, facts)
    local p = { trigger = trigger, key = key, list = list, pos = 0, full = full }
    pass = p
    Log("pass started: " .. key .. (full and "" or " (vendor trials only)"))
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
    if completed[(P.Situation("auto"))] then return end
    StartPass("auto", StandardList(), true)
end

-- The vendor trials by themselves, when a vendor window opens.
TryVendor = function()
    if not db or cleanHold then return end
    if pass then
        pendingVendor = true
        return
    end
    if not VendorOn() then return end
    StartPass("auto", VendorList(), false)
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
        if t.kind == "action" then actions[#actions + 1] = t end
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
    local list = {}
    if first then list[1] = first end
    local rest = StandardList()
    if VendorOn() then VendorList(rest) end
    for _, t in ipairs(rest) do
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
    P.cleanWaiting = nil
    nextButton:Hide()
    Log("stopped")
    SetStatus("stopped — " .. Covered())
end

---------------------------------------------------------------------------
-- Clean trials: one per reload, each the first thing the probe does
---------------------------------------------------------------------------

local cleanRan = false      -- this session's clean trial has been started

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
    local key, facts = P.Situation("clean")
    local s = P.EnsureSituation(key, facts)
    SetStatus("clean trial " .. i .. " of " .. n .. ": " .. trial.id)
    Log("clean trial " .. i .. " of " .. n .. ": " .. trial.id .. " in " .. key)
    RunTrial(trial, { trigger = "clean", key = key }, nil, function()
        s.passes = (type(s.passes) == "number" and s.passes or 0) + 1
        CleanDone(i, n)
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
