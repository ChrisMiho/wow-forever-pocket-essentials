local ADDON_NAME, P = ...

-- The performance recorder (probe 0.6.0). While Pocket Essentials is loaded
-- it records, every 15 seconds, what Pocket Essentials costs: the game's own
-- profiler numbers, memory, frame rate, and Pocket Essentials' own counters
-- per feature (its measuring hook, when it has one). scripts/read-probe.sh
-- <file> --perf prints the report.
--
--   * It starts by itself at login and carries on over a reload. Stop (the
--     round button beside the PE button, or the one in the probe window)
--     ends the run; it stays stopped until Start recording or a fresh login.
--   * A small red dot in the bottom-right corner shows while it records. The
--     dot takes no mouse and no touch.
--   * Trials and a recording never run together (Run.lua refuses the one
--     while the other is going), with one exception (probe 0.7.0): the
--     floating Fight button. It shows only in a fight, and only while a
--     recording runs or the watchers are armed (Watch.lua). One tap runs the
--     fight tests; a recording pauses for them (no samples, the ticker kept
--     but skipping) and goes on when the pass is over. The sample after the
--     pause has dt=0 and the letter p, so the report can leave it out. The
--     button is round, amber, as big as Stop, beside it on the side away from
--     the PE button (in Stop's spot when Stop is not showing). After the pass
--     it shows a tick for 3 seconds, then a tap runs the pass again.
--   * One ticker, only while recording. The activity tags come from events
--     and from show / hide hooks, never from a check every frame. Every frame
--     is made now, at load, so nothing is created in a fight.
--   * Without Pocket Essentials nothing here starts or shows.
--   * Only numbers and our own short tags are saved: no names, no chat.
--
-- The saved data (PocketProbeDB.perf):
--   on       a recording is running (it carries on after a reload)
--   stopped  it was stopped by hand, or it filled up; a reload keeps that
--   memAt    the game's clock when the memory was last counted
--   runs     the last three runs, oldest first. One run:
--     started, ended   date and time
--     why              how it ended: "stopped", "full", or a short reason
--     t0               the game's clock when it started
--     interval         seconds between samples
--     addon            Pocket Essentials' version line
--     profiler         "on", "off" or "missing" (the game's profiler)
--     features         true when Pocket Essentials has the measuring hook
--     reloads          how many reloads it carried on over
--     missing          { [game name] = true } for names this client lacks
--     keys             the feature keys, in the order first seen
--     feat             [key] = { ms, calls, max, events = { [event] = { ms, calls } } }
--                      totals for the run; "*" is the whole addon, with
--                      nothing counted twice
--     session          the profiler's numbers since the game started:
--                      { pe = { avg, peak }, all = { ... }, app = { ... } }
--     prev             the profiler's counts at the last sample (while running)
--     samples          one line of text per sample, fields split by ";":
--       t=    seconds since the run started
--       dt=   seconds this sample covers (0 for the first one and after a reload)
--       a=    activity letters seen in that time: c fight, d dungeon or
--             other instance, v vendor, w world map, b bags, m moving, s still;
--             p: the first sample after a pause for the fight tests (dt=0);
--             r: the first sample after a reload the run carried on over (dt=0)
--       fps=  frame rate
--       mem=  memory in KB: Pocket Essentials, QuestieDB, Pocket Probe; a
--             reading the game gave as 0 (right after a reload) is left
--             empty, as for an addon that is not loaded: "mem=,812,96"
--       pe=   the whole addon in that time: ms, runs, slowest run (0 when
--             no run was slower than every one before it)
--       f=    the same per feature: key number:ms:runs:slowest, ...
--       p=    profiler, Pocket Essentials: recent ms per frame, then frames
--             over 1, 5, 10, 50, 100, 500 and 1000 ms in that time
--       all=  profiler, all addons: recent ms per frame, frames over 1, 5, 10 ms
--       app=  profiler, the whole game: recent ms per frame
--
-- Game names used here and not listed in Core.lua, with their proof in
-- Blizzard's source for build 1.60.1 (paths as in Core.lua). Each one is
-- looked up before use: a missing one leaves its number out, and the run's
-- "missing" list says so.
--
--   Name                                         Proof
--   C_AddOnProfiler.IsEnabled                    Doc/AddOnProfilerDocumentation.lua:121
--   C_AddOnProfiler.GetAddOnMetric(name, metric) Doc/AddOnProfilerDocumentation.lua:45
--   C_AddOnProfiler.GetOverallMetric(metric)     Doc/AddOnProfilerDocumentation.lua:78
--   C_AddOnProfiler.GetApplicationMetric(metric) Doc/AddOnProfilerDocumentation.lua:62
--   Enum.AddOnProfilerMetric (the names below)   Doc/AddOnProfilerConstantsDocumentation.lua:19-37
--   UpdateAddOnMemoryUsage                       Doc/PerformanceDocumentation.lua:94 (Blizzard calls it at most
--                                                once in 15 seconds: Blizzard_AddOnList/AddonList.lua:775-785)
--   GetAddOnMemoryUsage(name)                    Doc/PerformanceDocumentation.lua:25
--   GetFramerate                                 Doc/ClientDocumentation.lua:44
--   C_AddOns.IsAddOnLoaded                       Doc/AddOnsDocumentation.lua:322
--   C_Timer.NewTicker (its object has :Cancel)   Doc/UITimerDocumentation.lua:22, Blizzard_Menu/Compositor.lua:350, 357
--   IsPlayerMoving                               Doc/PlayerScriptDocumentation.lua:1453
--   PLAYER_STARTED_MOVING / _STOPPED_MOVING      Doc/UnitDocumentation.lua:3946, 3964
--   PLAYER_ENTERING_WORLD (isInitialLogin, isReloadingUi)   Doc/SystemDocumentation.lua:136-142
--   PLAYER_LOGOUT                                Doc/SystemDocumentation.lua:159
--   ContainerFrame1 .. ContainerFrame7           Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:298-304
--   region :HookScript, :EnableMouse             Doc/SimpleScriptRegionAPIDocumentation.lua:365, 73
--   frame :UnregisterAllEvents                   Doc/SimpleFrameAPIDocumentation.lua:1588
--   frame :GetFrameLevel / :SetFrameLevel        Doc/SimpleFrameAPIDocumentation.lua:421, 1281
--   texture :SetTexture (returns success)        Doc/SimpleTextureBaseAPIDocumentation.lua:604-618
--   region :SetVertexColor                       Doc/SimpleRegionAPIDocumentation.lua:191
--   the atlas "common-icon-checkmark" (the Fight button's tick)
--                                                Blizzard_CharacterCreate/Camelot/Blizzard_CharacterCreate.lua:2986
--                                                (texture :SetAtlas / :GetAtlas: Core.lua)
--
-- Not proven by the source, and guarded:
--   PocketEssentials:StartMeasure / :StopMeasure / :MeasureCounters and the
--     button PocketEssentialsHubButton are Pocket Essentials' own. An older
--     Pocket Essentials has no measuring hook: the run then holds the game's
--     numbers only. Without the button, Stop sits above the red dot.
--   The round picture is Pocket Essentials' own file (Icons\circle). If it
--     does not load, the dot and the Stop button are drawn as squares.
--   Whether the game's profiler is switched on for the device: when
--     IsEnabled() says no, the run is marked "off" and no profiler number is read.
--   Whether the profiler's counts start again at a reload is not in the
--     source: a count that went down is taken as started again from zero.

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring
local floor, max = math.floor, math.max
local tconcat, tremove = table.concat, table.remove
local Find, IsSecret, Num, Str, Log, Guard = P.Find, P.IsSecret, P.Num, P.Str, P.Log, P.Guard

local INTERVAL = 15                     -- seconds between samples
local MAX_SAMPLES = 480                 -- two hours
local MAX_RUNS = P.PERF_RUNS
local PE_NAME = "PocketEssentials"
local ADDONS = { PE_NAME, "QuestieDB", P.name }
local HUB_NAME = "PocketEssentialsHubButton"
local DISC = "Interface\\AddOns\\PocketEssentials\\Icons\\circle"
local DISC_SCALE = 128 / 125            -- the picture is a little larger than its disc
local BAG_FRAMES = { "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6", "ContainerFrame7" }

-- What the player reads.
local NEEDS_PE = "Recording needs Pocket Essentials switched on."
local TRIAL_RUNNING = "A trial is running: let it finish or tap Stop first."
local FULL = "Recording stopped by itself: 2 hours reached"

local run                   -- the run being recorded, or nil
local paused = false        -- a pass of the floating Fight button runs: no samples
local counters              -- the table Pocket Essentials' hook handed over
local ticker
local tickToken = 0         -- changes at every start and stop, so an old ticker does nothing
local lastAt                -- the game's clock at the last sample
local before = {}           -- Pocket Essentials' counters at the last sample
local keyIndex = {}         -- [feature key] = its place in run.keys

local function Clock()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and Num(now) or nil
end

local FORMATS = { [0] = "%.0f", [1] = "%.1f", [3] = "%.3f" }

-- A number as short text: at most `places` decimals, no trailing zeros.
local function Fmt(n, places)
    local text = FORMATS[places]:format(n)
    if places > 0 then text = text:gsub("0+$", ""):gsub("%.$", "") end
    return text
end

local function Round3(n) return floor(n * 1000 + 0.5) / 1000 end

local function Saved()
    local db = P.db
    return db and type(db.perf) == "table" and db.perf or nil
end

local function Missing(r, name)
    if type(r.missing) ~= "table" then r.missing = {} end
    r.missing[name] = true
end

---------------------------------------------------------------------------
-- Pocket Essentials: is it loaded, and its measuring hook
---------------------------------------------------------------------------

local function Loaded(name)
    local fn = Find("C_AddOns.IsAddOnLoaded")
    if type(fn) ~= "function" then return false end
    local ok, loaded = pcall(fn, name)
    return ok and not IsSecret(loaded) and loaded and true or false
end

local function Essentials()
    local pe = _G[PE_NAME]
    return type(pe) == "table" and pe or nil
end

-- Calls one of the hook's three functions. An older Pocket Essentials has
-- none of them: nil then, and no error.
local function Hook(name)
    local pe = Essentials()
    local fn = pe and pe[name]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, pe)
    if ok and type(result) == "table" then return result end
    return nil
end

local function Counters()
    return Hook("MeasureCounters") or counters
end

-- A feature key or an event name of Pocket Essentials', if it is plain text.
local function Plain(text, limit)
    if type(text) ~= "string" or IsSecret(text) or #text == 0 or #text > limit then return nil end
    if text:find("[^%w_%.%-%* ]") then return nil end
    return text
end

---------------------------------------------------------------------------
-- Activity tags. `tags` is what is true now; `seen` is what was true at any
-- moment since the last sample.
---------------------------------------------------------------------------

local LETTERS = { "c", "d", "v", "w", "b", "m", "s" }
local tags, seen = {}, {}

local function Mark(letter, on)
    on = on and true or false
    if letter == "m" then
        -- Standing still is a tag of its own: "s".
        if not on or not tags.m then seen.s = true end
        tags.s = not on
    end
    tags[letter] = on
    if on then seen[letter] = true end
end

local function TagText()
    local out = {}
    for _, letter in ipairs(LETTERS) do
        if seen[letter] or tags[letter] then out[#out + 1] = letter end
        seen[letter] = tags[letter] or nil
    end
    return tconcat(out)
end

local function Truth(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and not IsSecret(v) and v and true or false
end

local function FrameShown(name)
    local f = _G[name]
    return type(f) == "table" and Truth(f.IsShown, f)
end

local function BagsOpen()
    for _, name in ipairs(BAG_FRAMES) do
        if FrameShown(name) then return true end
    end
    return false
end

-- What is true as a recording starts, read once.
local function ReadTags()
    tags.c = Truth(InCombatLockdown)
    tags.d = Truth(IsInInstance)
    tags.v = P.vendorOpen == true
    tags.w = FrameShown("WorldMapFrame")
    tags.b = BagsOpen()
    tags.m = Truth(Find("IsPlayerMoving"))
    tags.s = not tags.m
    for _, letter in ipairs(LETTERS) do seen[letter] = tags[letter] or nil end
end

local tagEvents = {
    PLAYER_REGEN_DISABLED = function() Mark("c", true) end,
    PLAYER_REGEN_ENABLED = function() Mark("c", false) end,
    MERCHANT_SHOW = function() Mark("v", true) end,
    MERCHANT_CLOSED = function() Mark("v", false) end,
    PLAYER_STARTED_MOVING = function() Mark("m", true) end,
    PLAYER_STOPPED_MOVING = function() Mark("m", false) end,
}

-- Listens only while a recording runs.
local tagFrame = CreateFrame("Frame", nil, UIParent)
tagFrame:SetScript("OnEvent", Guard(function(_, event)
    local handler = tagEvents[event]
    if handler and run then handler() end
end))

local function Listen(on)
    pcall(tagFrame.UnregisterAllEvents, tagFrame)
    if not on then return end
    for event in pairs(tagEvents) do
        -- A client without the event raises an error on registering it.
        pcall(tagFrame.RegisterEvent, tagFrame, event)
    end
end

---------------------------------------------------------------------------
-- The red dot and the round Stop button (made now, hidden)
---------------------------------------------------------------------------

-- A round picture in one colour; a square when the picture does not load.
local function Disc(texture, r, g, b)
    local ok, loaded = pcall(texture.SetTexture, texture, DISC)
    if ok and loaded ~= false then
        pcall(texture.SetVertexColor, texture, r, g, b)
    else
        texture:SetColorTexture(r, g, b, 1)
    end
end

local dot = CreateFrame("Frame", "PocketProbeRecDot", UIParent)
dot:SetFrameStrata("HIGH")
dot:EnableMouse(false)
dot:Hide()
local dotArt = dot:CreateTexture(nil, "ARTWORK")
dotArt:SetAllPoints(dot)
Disc(dotArt, 1, 0.1, 0.1)

local stop = CreateFrame("Button", "PocketProbeRecStopButton", UIParent)
stop:SetFrameStrata("HIGH")
stop:Hide()
local stopLevel = stop:GetFrameLevel()
local stopRing = stop:CreateTexture(nil, "BACKGROUND")
Disc(stopRing, 1, 0.25, 0.2)
local stopFill = stop:CreateTexture(nil, "BORDER")
Disc(stopFill, 0.2, 0.04, 0.04)
local stopLabel = P.NewText(stop, "small")
stopLabel:SetJustifyH("CENTER")
stopLabel:SetPoint("CENTER", stop, "CENTER", 0, 0)
stopLabel:SetText("Stop")

local Place                 -- below
local hubHooked             -- the PE button our show / hide hooks are on

local function HubButton()
    local hub = _G[HUB_NAME]
    if type(hub) ~= "table" or type(hub.IsVisible) ~= "function" then return nil end
    return hub
end

local function CenterDisc(texture, size)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", stop, "CENTER", 0, 0)
    texture:SetSize(size, size)
end

-- The floating Fight button (probe 0.7.0): made now, hidden. Amber, as big as Stop.
local fight = CreateFrame("Button", "PocketProbeFloatFight", UIParent)
fight:SetFrameStrata("HIGH")
fight:Hide()
local fightRing = fight:CreateTexture(nil, "BACKGROUND")
Disc(fightRing, 1, 0.7, 0.1)
local fightFill = fight:CreateTexture(nil, "BORDER")
Disc(fightFill, 0.32, 0.19, 0.02)
local fightLabel = P.NewText(fight, "small")
fightLabel:SetJustifyH("CENTER")
fightLabel:SetPoint("CENTER", fight, "CENTER", 0, 0)
fightLabel:SetText("Fight")
local fightTick = fight:CreateTexture(nil, "ARTWORK")
fightTick:SetPoint("CENTER", fight, "CENTER", 0, 0)
local TICK_ATLAS = "common-icon-checkmark"
pcall(fightTick.SetAtlas, fightTick, TICK_ATLAS)
local tickAtlas = fightTick.GetAtlas and select(2, pcall(fightTick.GetAtlas, fightTick)) == TICK_ATLAS
fightTick:Hide()
P.floatFight = { button = fight, label = fightLabel, tick = fightTick }

local function CenterOn(frame, texture, size)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
    texture:SetSize(size, size)
end

local PlaceFight            -- below

-- Puts a round button where Stop goes: beside the PE button, on the side
-- facing the middle of the screen, and as big as it; above the dot when the
-- PE button is not there or not showing. Returns its size, its frame level,
-- and "right" or "left" (of the PE button) or "corner".
local function PlaceRound(f)
    local unit = P.Units
    local gap, dotSize, size = unit(10), unit(20), unit(60)
    f:ClearAllPoints()
    local side, level = nil, stopLevel
    local hub = HubButton()
    if hub then
        if hubHooked ~= hub and type(hub.HookScript) == "function" then
            hubHooked = hub
            local again = Guard(function()
                if run then Place() end
                if fight:IsShown() then PlaceFight() end
            end)
            pcall(hub.HookScript, hub, "OnShow", again)
            pcall(hub.HookScript, hub, "OnHide", again)
        end
        if Truth(hub.IsVisible, hub) then
            local okw, width = pcall(hub.GetWidth, hub)
            width = okw and Num(width)
            if width and width > 8 then size = width end
            local okc, x = pcall(hub.GetCenter, hub)
            local oks, screen = pcall(UIParent.GetWidth, UIParent)
            x, screen = okc and Num(x), oks and Num(screen)
            if x and screen and x < screen / 2 then
                side = pcall(f.SetPoint, f, "LEFT", hub, "RIGHT", gap, 0) and "right" or nil
            else
                side = pcall(f.SetPoint, f, "RIGHT", hub, "LEFT", -gap, 0) and "left" or nil
            end
            -- On the world map the PE button is raised above the map's border.
            local okl, hubLevel = pcall(hub.GetFrameLevel, hub)
            if okl and Num(hubLevel) then level = hubLevel end
        end
    end
    if not side then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -gap, gap + dotSize + gap)
        level, side = stopLevel, "corner"
    end
    pcall(f.SetFrameLevel, f, level)
    f:SetSize(size, size)
    return size, level, side
end

local stopSide = "corner"   -- where Stop was put last

-- The dot in the bottom-right corner, and Stop (PlaceRound).
Place = function()
    local unit = P.Units
    local gap, dotSize = unit(10), unit(20)
    dot:ClearAllPoints()
    dot:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -gap, gap)
    dot:SetSize(dotSize, dotSize)
    local size, level
    size, level, stopSide = PlaceRound(stop)
    CenterDisc(stopRing, size * DISC_SCALE)
    CenterDisc(stopFill, max(size - max(unit(4), 2) * 2, 1) * DISC_SCALE)
end

-- Fight beside Stop, on the side away from the PE button (left of Stop when
-- Stop sits above the dot); in Stop's spot when Stop is not showing.
PlaceFight = function()
    local unit = P.Units
    local gap = unit(10)
    local size
    if stop:IsShown() then
        Place()
        size = stop:GetWidth()
        fight:ClearAllPoints()
        if stopSide == "right" then
            fight:SetPoint("LEFT", stop, "RIGHT", gap, 0)
        else
            fight:SetPoint("RIGHT", stop, "LEFT", -gap, 0)
        end
        pcall(fight.SetFrameLevel, fight, stop:GetFrameLevel())
        fight:SetSize(size, size)
    else
        size = PlaceRound(fight)
    end
    CenterOn(fight, fightRing, size * DISC_SCALE)
    CenterOn(fight, fightFill, max(size - max(unit(4), 2) * 2, 1) * DISC_SCALE)
    CenterOn(fight, fightTick, size * 0.6)
end

---------------------------------------------------------------------------
-- Show / hide hooks for the world map and the bags (a hook cannot be taken
-- off again, so each does nothing while no recording runs)
---------------------------------------------------------------------------

local hooked = {}

local function HookFrame(name, fn)
    if hooked[name] then return end
    local f = _G[name]
    if type(f) ~= "table" or type(f.HookScript) ~= "function" then return end
    hooked[name] = true
    pcall(f.HookScript, f, "OnShow", fn)
    pcall(f.HookScript, f, "OnHide", fn)
end

local onBag = Guard(function()
    if run then Mark("b", BagsOpen()) end
end)

local placeLater = Guard(function() if run then Place() end end)

local onMap = Guard(function()
    if not run then return end
    Mark("w", FrameShown("WorldMapFrame"))
    -- The PE button moves onto the map's book icon and back: Stop follows it.
    local after = Find("C_Timer.After")
    if type(after) == "function" then after(0, placeLater) end
end)

-- Frames that are not there yet (the map loads when first opened) get their
-- hooks at a later sample.
local function EnsureHooks()
    HookFrame("WorldMapFrame", onMap)
    for _, name in ipairs(BAG_FRAMES) do HookFrame(name, onBag) end
end

---------------------------------------------------------------------------
-- One sample
---------------------------------------------------------------------------

-- Memory of the three addons. The game is asked to count again at most once
-- in 15 seconds, as Blizzard's own addon list does; the time of the last
-- count is saved, so a reload or a quick Stop and Start does not add one.
local function MemoryField(r, kind, now)
    local perf = Saved()
    local memAt = perf and Num(perf.memAt)
    if memAt and now and now < memAt then memAt = nil end      -- the game was restarted
    local get = Find("GetAddOnMemoryUsage")
    if type(get) ~= "function" then
        Missing(r, "GetAddOnMemoryUsage")
        return nil
    end
    local update = Find("UpdateAddOnMemoryUsage")
    if type(update) ~= "function" then
        Missing(r, "UpdateAddOnMemoryUsage")
    elseif kind ~= "final" and (not memAt or not now or now - memAt >= INTERVAL - 0.5) then
        pcall(update)
        if perf then perf.memAt = now end
    end
    local out, any = {}, false
    for i, name in ipairs(ADDONS) do
        out[i] = ""
        if Loaded(name) then
            local ok, kb = pcall(get, name)
            kb = ok and Num(kb)
            -- 0 is no reading (the game has not counted since a reload): left empty.
            if kb and kb > 0 then out[i], any = Fmt(kb, 0), true end
        end
    end
    return any and ("mem=" .. tconcat(out, ",")) or nil
end

-- One counter since the last sample. `was` keeps the last reading; a counter
-- that went down started again from zero (a reload, or the hook restarted).
local function Since(was, ms, calls)
    if ms < was.ms or calls < was.calls then was.ms, was.calls, was.max = 0, 0, 0 end
    local dms, dcalls = ms - was.ms, calls - was.calls
    was.ms, was.calls = ms, calls
    return dms, dcalls
end

local function Total(r, key)
    local t = r.feat[key]
    if type(t) ~= "table" then
        t = { ms = 0, calls = 0, max = 0 }
        r.feat[key] = t
    end
    return t
end

-- Pocket Essentials' own counters since the last sample: added to the run's
-- totals and written as the "pe=" and "f=" fields. base: only remember them.
local function FeatureFields(r, base, parts)
    local now = Counters()
    if type(now) ~= "table" then return end
    local list = {}
    for key, c in pairs(now) do
        key = Plain(key, 40)
        if key and type(c) == "table" then
            local ms, calls, slowest = Num(c.ms) or 0, Num(c.calls) or 0, Num(c.max) or 0
            local was = before[key]
            if not was then
                was = { ms = 0, calls = 0, max = 0, events = {} }
                before[key] = was
            end
            local dms, dcalls = Since(was, ms, calls)
            -- The slowest run is only known when it beat every run before it.
            local dmax = slowest > was.max and slowest or 0
            was.max = max(was.max, slowest)
            local total = not base and (dcalls > 0 or dms > 0) and Total(r, key) or nil
            if total then
                total.ms, total.calls = Round3(total.ms + dms), total.calls + dcalls
                total.max = max(total.max, Round3(dmax))
                local text = Fmt(dms, 3) .. ":" .. Fmt(dcalls, 0) .. ":" .. Fmt(dmax, 3)
                if key == "*" then
                    parts[#parts + 1] = "pe=" .. text:gsub(":", ",")
                else
                    if not keyIndex[key] then
                        r.keys[#r.keys + 1] = key
                        keyIndex[key] = #r.keys
                    end
                    list[#list + 1] = keyIndex[key] .. ":" .. text
                end
            end
            for event, e in pairs(type(c.events) == "table" and c.events or {}) do
                event = Plain(event, 60)
                if event and type(e) == "table" then
                    local ewas = was.events[event]
                    if not ewas then
                        ewas = { ms = 0, calls = 0, max = 0 }
                        was.events[event] = ewas
                    end
                    local ems, ecalls = Since(ewas, Num(e.ms) or 0, Num(e.calls) or 0)
                    if total and (ecalls > 0 or ems > 0) then
                        if type(total.events) ~= "table" then total.events = {} end
                        local et = total.events[event]
                        if type(et) ~= "table" then
                            et = { ms = 0, calls = 0 }
                            total.events[event] = et
                        end
                        et.ms, et.calls = Round3(et.ms + ems), et.calls + ecalls
                    end
                end
            end
        end
    end
    if #list > 0 then parts[#parts + 1] = "f=" .. tconcat(list, ",") end
end

local COUNTS = { "RecentAverageTime", "CountTimeOver1Ms", "CountTimeOver5Ms", "CountTimeOver10Ms",
    "CountTimeOver50Ms", "CountTimeOver100Ms", "CountTimeOver500Ms", "CountTimeOver1000Ms" }
-- field: the sample's field and the run's "prev" entry; n: how many of COUNTS it holds.
local SCOPES = {
    { field = "p", session = "pe", n = 8, fn = "C_AddOnProfiler.GetAddOnMetric", addon = true },
    { field = "all", session = "all", n = 4, fn = "C_AddOnProfiler.GetOverallMetric" },
    { field = "app", session = "app", n = 1, fn = "C_AddOnProfiler.GetApplicationMetric" },
}

local function ProfilerState()
    local enabled = Find("C_AddOnProfiler.IsEnabled")
    if type(enabled) ~= "function" then return "missing" end
    return Truth(enabled) and "on" or "off"
end

local function Metric(scope, name)
    local id = Find("Enum.AddOnProfilerMetric." .. name)
    local fn = Find(scope.fn)
    if id == nil or type(fn) ~= "function" then return nil end
    local ok, v
    if scope.addon then ok, v = pcall(fn, PE_NAME, id) else ok, v = pcall(fn, id) end
    return ok and Num(v) or nil
end

-- The game's profiler: the counts since the last sample, and its numbers
-- since the game started (kept once per run, the newest reading).
local function ProfilerFields(r, base, parts)
    if r.profiler ~= "on" then return end
    if type(r.prev) ~= "table" then r.prev = {} end
    if type(r.session) ~= "table" then r.session = {} end
    for _, scope in ipairs(SCOPES) do
        local prev = r.prev[scope.field]
        if type(prev) ~= "table" then
            prev = {}
            r.prev[scope.field] = prev
        end
        local out, any = {}, false
        for i = 1, scope.n do
            local v = Metric(scope, COUNTS[i])
            out[i] = ""
            if v and i == 1 then
                out[i], any = Fmt(v, 3), true
            elseif v then
                local d = v - (Num(prev[i]) or 0)
                if d < 0 then d = v end
                prev[i] = v
                out[i], any = Fmt(d, 0), true
            end
        end
        if any and not base then parts[#parts + 1] = scope.field .. "=" .. tconcat(out, ",") end
        local avg, peak = Metric(scope, "SessionAverageTime"), Metric(scope, "PeakTime")
        if avg or peak then
            r.session[scope.session] = { avg = avg and Round3(avg) or nil, peak = peak and Round3(peak) or nil }
        end
    end
end

-- kind: "base" (the first sample of a run, the first after a reload, and
-- the first after a pause: it only notes where every counter stands),
-- "tick", or "final". mark: letters added to a= ("p" after a pause).
local function Sample(kind, mark)
    local r = run
    if not r then return end
    local now = Clock()
    local base = kind == "base"
    local dt = 0
    if not base and now and lastAt then dt = max(now - lastAt, 0) end
    lastAt = now or lastAt
    local parts = {
        "t=" .. Fmt(max((now or r.t0) - r.t0, 0), 0),
        "dt=" .. Fmt(dt, 1),
        "a=" .. TagText() .. (mark or ""),
    }
    local rate = Find("GetFramerate")
    if type(rate) == "function" then
        local ok, fps = pcall(rate)
        fps = ok and Num(fps)
        if fps then parts[#parts + 1] = "fps=" .. Fmt(fps, 1) end
    else
        Missing(r, "GetFramerate")
    end
    parts[#parts + 1] = MemoryField(r, kind, now)
    FeatureFields(r, base, parts)
    ProfilerFields(r, base, parts)
    r.samples[#r.samples + 1] = tconcat(parts, ";")
end

---------------------------------------------------------------------------
-- Starting and stopping
---------------------------------------------------------------------------

local function StopTicker()
    tickToken = tickToken + 1
    local t = ticker
    ticker = nil
    if t ~= nil then pcall(function() t:Cancel() end) end
end

local function Tick()
    if not run or paused then return end
    Sample("tick")
    if #run.samples >= MAX_SAMPLES then return P.StopRecording("full") end
    EnsureHooks()
    Place()
    if P.RefreshPanel then P.RefreshPanel() end
end

local function StartTicker()
    StopTicker()
    local token = tickToken
    local new = Find("C_Timer.NewTicker")
    if type(new) ~= "function" then
        Missing(run, "C_Timer.NewTicker")
        return
    end
    local ok, t = pcall(new, INTERVAL, Guard(function()
        if token == tickToken then Tick() end
    end))
    if ok then ticker = t end
end

-- Marks the newest run as over when it was left running (a logout, or a
-- reload after which it could not carry on).
local function CloseLast(perf, why)
    perf.on = false
    local r = perf.runs[#perf.runs]
    if type(r) == "table" and r.ended == nil and r.why == nil then
        r.why = why
        r.prev = nil
    end
end

-- Why a recording cannot start now, or nil.
local function StartRefusal()
    if not Saved() then return "loading" end
    if not Loaded(PE_NAME) then return NEEDS_PE end
    if P.Busy and P.Busy() then return TRIAL_RUNNING end
    local waiting = P.GuidedWaiting and P.GuidedWaiting()
    if waiting then return waiting .. " is waiting: answer or Cancel it first" end
    return nil
end

-- carryOn: the newest run goes on (after a reload) when it still can.
local function Begin(carryOn)
    local perf = Saved()
    local now = Clock()
    local r = carryOn and perf.runs[#perf.runs] or nil
    local carried = false
    if type(r) == "table" and type(r.samples) == "table" and #r.samples < MAX_SAMPLES and r.ended == nil
        and now and type(r.t0) == "number" and now >= r.t0 and type(r.keys) == "table" and type(r.feat) == "table" then
        r.reloads = (type(r.reloads) == "number" and r.reloads or 0) + 1
        carried = true
        Log("recording carries on after the reload")
    else
        if perf.on then CloseLast(perf, "ended at a reload or a logout") end
        r = { started = P.Stamp("%Y-%m-%d %H:%M:%S"), t0 = now or 0, interval = INTERVAL, reloads = 0,
            keys = {}, feat = {}, samples = {} }
        perf.runs[#perf.runs + 1] = r
        while #perf.runs > MAX_RUNS do tremove(perf.runs, 1) end
        Log("recording started")
    end
    run = r
    perf.on, perf.stopped = true, false
    local version = Find("C_AddOns.GetAddOnMetadata")
    if type(version) == "function" then
        local ok, v = pcall(version, PE_NAME, "Version")
        r.addon = ok and Str(v) and v:sub(1, 20) or nil
    end
    r.profiler = ProfilerState()
    counters = Hook("StartMeasure")
    r.features = counters ~= nil
    for key in pairs(keyIndex) do keyIndex[key] = nil end
    for i, key in ipairs(r.keys) do keyIndex[key] = i end
    for key in pairs(before) do before[key] = nil end
    lastAt = nil
    ReadTags()
    Listen(true)
    EnsureHooks()
    -- The first sample after a reload says so (r): the report leaves the
    -- next 30 seconds out of its plain words.
    Sample("base", carried and "r" or nil)
    StartTicker()
    Place()
    dot:Show()
    stop:Show()
    -- The PE button may only be made in the next moment: placed once more.
    local after = Find("C_Timer.After")
    if type(after) == "function" then after(1, placeLater) end
    if P.RefreshPanel then P.RefreshPanel() end
    P.UpdateFightButton()
end

function P.Recording()
    return run ~= nil
end

-- The recording line of the probe window shows only with Pocket Essentials loaded.
function P.RecordingOffered()
    return Loaded(PE_NAME)
end

function P.RecordingText()
    if run then
        local now = Clock()
        return "Recording " .. (now and floor(max(now - run.t0, 0) / 60) or 0) .. " min"
    end
    local perf = Saved()
    local last = perf and perf.runs[#perf.runs]
    if type(last) == "table" and last.why == "full" then return "Stopped at 2 hours" end
    return "Not recording"
end

-- Start recording, from the probe window.
function P.StartRecording()
    if run then return true end
    local why = StartRefusal()
    if why then
        P.SetStatus(why)
        return false
    end
    Begin(false)
    P.SetStatus("Recording started")
    return true
end

-- Stop, from either button. why: "full" when the run filled up by itself.
function P.StopRecording(why)
    local r = run
    if not r then return end
    -- During a pause the last stretch is the probe's own pass: left out.
    if why ~= "full" and not paused then pcall(Sample, "final") end
    paused = false
    StopTicker()
    Listen(false)
    Hook("StopMeasure")
    r.ended = P.Stamp("%Y-%m-%d %H:%M:%S")
    r.why = why or "stopped"
    r.prev = nil
    local perf = Saved()
    if perf then perf.on, perf.stopped = false, true end
    run, counters = nil, nil
    dot:Hide()
    stop:Hide()
    Log("recording " .. (why == "full" and "stopped by itself: 2 hours reached" or "stopped") .. ", " .. #r.samples .. " samples")
    P.SetStatus(why == "full" and FULL or "Recording stopped")
    P.UpdateFightButton()
end

stop:SetScript("OnClick", Guard(function() P.StopRecording() end))

---------------------------------------------------------------------------
-- The floating Fight button (probe 0.7.0) and the recording's pause
---------------------------------------------------------------------------

local TICK_SHOW = 3         -- seconds the tick shows after a pass
local fighting = false      -- between PLAYER_REGEN_DISABLED and _ENABLED (Run.lua tells)
local fightBusy = false     -- its pass runs
local ticking = false       -- the tick shows
local tickToken2 = 0

-- No samples while the fight tests run; the ticker goes on, skipping.
function P.PerfPause()
    if not run or paused then return false end
    paused = true
    Log("recording paused for the fight tests")
    return true
end

-- The sample after the pause has dt=0 and the letter p, and only notes
-- where the counters stand, so the pass's own work is not counted.
function P.PerfResume()
    if not paused then return end
    paused = false
    if run then
        Sample("base", "p")
        Log("recording goes on after the fight tests")
    end
end

local function Armed()
    return P.WatchArmed ~= nil and P.WatchArmed() == true
end

local function FightLook()
    local dim = fightBusy
    pcall(fightRing.SetVertexColor, fightRing, dim and 0.55 or 1, dim and 0.4 or 0.7, dim and 0.1 or 0.1)
    if ticking and tickAtlas then
        fightTick:Show()
        fightLabel:Hide()
    else
        fightTick:Hide()
        fightLabel:SetText(ticking and "Done" or "Fight")
        fightLabel:Show()
    end
end

-- Shown only in a fight, and only while armed or recording.
function P.UpdateFightButton()
    if fighting and (run ~= nil or Armed()) then
        PlaceFight()
        FightLook()
        fight:Show()
    else
        fight:Hide()
    end
end

function P.FightButtonCombat(on)
    fighting = on and true or false
    P.UpdateFightButton()
end

local function PassDone()
    fightBusy = false
    P.PerfResume()
    ticking = true
    tickToken2 = tickToken2 + 1
    local token = tickToken2
    local after = Find("C_Timer.After")
    if type(after) == "function" then
        after(TICK_SHOW, Guard(function()
            if token ~= tickToken2 then return end
            ticking = false
            FightLook()
        end))
    else
        ticking = false
    end
    FightLook()
end

fight:SetScript("OnClick", Guard(function()
    -- A tap while its pass runs, while the tick shows, or while another pass
    -- runs does nothing: never a second pass.
    if fightBusy or ticking then return end
    if P.Busy and P.Busy() then
        P.SetStatus("A pass is already running: let it finish.")
        return
    end
    local pausing = P.PerfPause()
    fightBusy = true
    FightLook()
    local started = P.RunFightTests and P.RunFightTests({ duringRecording = true, onDone = PassDone })
    if not started and fightBusy then
        fightBusy = false
        if pausing then P.PerfResume() end
        FightLook()
    end
end))

---------------------------------------------------------------------------
-- Login, reload, logout
---------------------------------------------------------------------------

local entered = false       -- this session's first PLAYER_ENTERING_WORLD has come

local function OnEnteringWorld(isInitialLogin, isReloadingUi)
    local perf = Saved()
    if not perf then return end
    if entered then
        -- A loading screen later on: into or out of a dungeon.
        if run then Mark("d", Truth(IsInInstance)) end
        return
    end
    entered = true
    local reload = not IsSecret(isReloadingUi) and isReloadingUi == true
        and not (not IsSecret(isInitialLogin) and isInitialLogin == true)
    -- A fresh login records again, whatever the last session ended with.
    if not reload then perf.stopped = false end
    local why = perf.stopped and "it was stopped before the reload" or StartRefusal()
    if why then
        if perf.on then CloseLast(perf, "ended at a reload or a logout") end
        if Loaded(PE_NAME) then Log("recording not started: " .. why) end
        return
    end
    Begin(reload and perf.on == true)
end

local loginFrame = CreateFrame("Frame", nil, UIParent)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT" }) do
    pcall(loginFrame.RegisterEvent, loginFrame, event)
end
loginFrame:SetScript("OnEvent", Guard(function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        OnEnteringWorld(...)
    elseif run and not paused then
        -- The game writes the saved file after this: the last stretch goes in.
        Sample("final")
    end
end))
