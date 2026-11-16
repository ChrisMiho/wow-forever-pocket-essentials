-- Offline QuestieDB harness.
--
--   luajit tests/questiedb/harness.lua <QuestieDB dir> <repo root> [QuestData.lua]
--
-- Loads the real QuestieDB addon (its own reading code, from the release zip) and
-- our Core.lua and QuestData.lua under WoW API stand-ins, then puts every quest
-- QuestieDB knows through QuestData twice: once "in the log, not complete" and
-- once "complete", for an Alliance and a Horde player. Any Lua error or
-- PE:LogError call fails the run, and so does a known pin in the wrong place or
-- a change in how many quests get pins (see baseline.txt).
--
-- The optional third argument loads a different QuestData.lua (used to check
-- that the harness notices a broken copy).
--
-- Exit code 0 on pass, 1 on failure (first failing quest and its error).

local qdbDir, root, questDataPath = arg[1], arg[2], arg[3]
if not qdbDir or not root then
    io.stderr:write("usage: luajit harness.lua <QuestieDB dir> <repo root> [QuestData.lua]\n")
    os.exit(2)
end
questDataPath = questDataPath or (root .. "/addons/PocketEssentials/QuestData.lua")

local function fail(msg)
    io.stdout:write("FAIL: ", tostring(msg), "\n")
    os.exit(1)
end

local function need(path, what)
    local chunk, err = loadfile(path)
    if not chunk then fail("missing " .. what .. " (" .. path .. "): " .. tostring(err)) end
    return chunk()
end

local S = need(root .. "/tests/questiedb/stubs.lua", "stubs")

-- Fails on the first PE:LogError call recorded so far (stubs.lua records them).
local function checkErrors(PE, where)
    local e = PE.harnessErrors[1]
    if e then
        fail(where .. ": PE:LogError(" .. tostring(e.module) .. "): " .. tostring(e.msg)
            .. (e.stack ~= "" and ("\n" .. e.stack) or ""))
    end
end

-- Runs fn; a Lua error fails the run with `where`.
local function guarded(where, fn, ...)
    local ok, a, b = xpcall(fn, debug.traceback, ...)
    if not ok then fail(where .. ": " .. tostring(a)) end
    return a, b
end

guarded("loading the decoders and TOC reader from tests/lib", S.init, root)

---------------------------------------------------------------------------
-- 1. Without QuestieDB: Acquire says no, with a reason, and nothing errors.
---------------------------------------------------------------------------
do
    S.install()
    _G.LibQuestieDB = nil
    local PE = guarded("loading Core.lua", S.loadCore, root)
    local QD = guarded("loading QuestData.lua", S.loadAddonFile, questDataPath, PE).QuestData
    local ok, reason = guarded("QD:Acquire without QuestieDB", QD.Acquire, QD, "harness")
    if ok ~= false then fail("QD:Acquire() without QuestieDB returned " .. tostring(ok) .. ", expected false") end
    if type(reason) ~= "string" or reason == "" then
        fail("QD:Acquire() without QuestieDB gave no reason")
    end
    guarded("timers without QuestieDB", S.runTimers)
    checkErrors(PE, "without QuestieDB")
end

---------------------------------------------------------------------------
-- 2. With QuestieDB, once per player persona. QuestieDB applies some of its
--    corrections by faction and class while loading, so each persona gets a
--    fresh load. Shaman has class-specific Horde corrections.
---------------------------------------------------------------------------
local PERSONAS = {
    { label = "Alliance", prefix = "", faction = "Alliance", class = "WARRIOR" },
    { label = "Horde", prefix = "horde_", faction = "Horde", class = "SHAMAN" },
}

-- Pins whose exact place is known. A wrong float decode or a change of
-- coordinate scale moves them. Values were read from QuestieDB 1.1.1's decoded
-- data (Npc spawns are in 0..100 per zone; pins are 0..1) and the zone ids map
-- to uiMap ids in its support/Forever/Zones/areaIdToUiMapId.lua.
local KNOWN_PINS = {
    -- Quest 2 "Sharptalon's Claw", turn in: finishedBy {{12696}}; Npc 12696
    -- "Senani Thunderheart" spawns {[331] = {{73.78, 61.46}}}; area 331 Ashenvale = uiMap 1440.
    { quest = 2, complete = true, map = 1440, x = 0.7378, y = 0.6146, kind = "turnin", target = "Senani Thunderheart" },
    -- Quest 55 "Morbent Fel", kill: objectives {{{1200, ...}}}; Npc 1200
    -- "Morbent Fel" spawns {[10] = {{16.9, 33.4}}}; area 10 Duskwood = uiMap 1431.
    { quest = 55, complete = false, map = 1431, x = 0.169, y = 0.334, kind = "slay", target = "Morbent Fel" },
}

local function describePins(byMap)
    local out = {}
    for mapID, list in pairs(byMap) do
        for _, p in ipairs(list) do
            out[#out + 1] = string.format("  map %s x=%s y=%s kind=%s target=%s",
                tostring(mapID), tostring(p.x), tostring(p.y), tostring(p.kind), tostring(p.target))
        end
    end
    return #out > 0 and table.concat(out, "\n") or "  (no pins)"
end

local function checkKnownPin(want, byMap, where)
    for _, p in ipairs(byMap[want.map] or {}) do
        if type(p.x) == "number" and type(p.y) == "number" and math.abs(p.x - want.x) < 1e-4
            and math.abs(p.y - want.y) < 1e-4 and p.kind == want.kind and p.target == want.target then
            return
        end
    end
    fail(string.format("%s: expected a %s pin for %s on map %d at %.4f, %.4f; got:\n%s",
        where, want.kind, want.target, want.map, want.x, want.y, describePins(byMap)))
end

local function countPins(byMap)
    local n = 0
    for _, list in pairs(byMap) do n = n + #list end
    return n
end

local function name(entity, id)
    local f = type(id) == "number" and entity.name
    local v = f and f(id)
    return type(v) == "string" and v or nil
end

local version

-- The focused quest and Blizzard's tracker list reach QuestData's users.
-- Needs QD acquired as "harness" and its event frame among S.frames.
local function checkFocus(PE, QD, tag)
    local where = tag .. ": focus and tracker"
    local frame
    for _, f in ipairs(S.frames) do
        if f.events.SUPER_TRACKING_CHANGED then frame = f end
    end
    if not frame then fail(where .. ": SUPER_TRACKING_CHANGED is not registered while acquired") end
    if not frame.events.QUEST_WATCH_LIST_CHANGED then
        fail(where .. ": QUEST_WATCH_LIST_CHANGED is not registered while acquired")
    end
    local got = {}
    QD:OnChanged("harness", function(reason) got[#got + 1] = reason end)
    local function count(reason)
        local n = 0
        for _, r in ipairs(got) do if r == reason then n = n + 1 end end
        return n
    end
    local function event(name) guarded(where .. ": " .. name, frame.scripts.OnEvent, frame, name) end

    S.questLog.set({ id = 2, title = "Sharptalon's Claw", complete = false, objectives = {} })
    S.questLog.focus(2)
    event("SUPER_TRACKING_CHANGED")
    if QD:GetTrackedQuest() ~= 2 then fail(where .. ": GetTrackedQuest() is not the focused quest 2") end
    if count("tracked") ~= 1 then fail(where .. ": focusing a quest gave " .. count("tracked") .. " \"tracked\" callbacks, expected 1") end
    event("SUPER_TRACKING_CHANGED")
    if count("tracked") ~= 1 then fail(where .. ": an unchanged focus fired \"tracked\" again") end
    S.questLog.focus(55)    -- not in the log
    if QD:GetTrackedQuest() ~= nil then fail(where .. ": GetTrackedQuest() returned a quest that is not in the log") end
    S.questLog.focus(nil)

    S.questLog.watch({ 2, 55, 2 })
    local w = QD:GetWatchedQuests()
    if type(w) ~= "table" or #w ~= 2 or w[1] ~= 2 or w[2] ~= 55 then
        fail(where .. ": GetWatchedQuests() is not { 2, 55 }")
    end
    S.questLog.watch({})
    if #QD:GetWatchedQuests() ~= 0 then fail(where .. ": GetWatchedQuests() is not empty for an empty tracker") end

    wipe(got)
    event("QUEST_WATCH_LIST_CHANGED")
    event("QUEST_WATCH_LIST_CHANGED")
    guarded(where, S.runTimers)
    if count("quests") ~= 1 then
        fail(where .. ": two tracker changes gave " .. count("quests") .. " \"quests\" callbacks, expected 1")
    end
    QD:OnChanged("harness", nil)
    S.questLog.set(nil)
    checkErrors(PE, where)
end

---------------------------------------------------------------------------
-- 2b. The spot limit's picker (QD._Spread) on small made-up cases.
---------------------------------------------------------------------------
local function spreadUnit(QD)
    local function unmarked(pins)
        local keep = {}
        for _, p in ipairs(pins) do if not p.extra then keep[#keep + 1] = p end end
        return keep
    end
    if type(QD._Spread) ~= "function" then fail("spread: QD._Spread is missing") end

    local line = {}
    for i = 1, 10 do line[i] = { x = i / 10, y = 0.5 } end
    guarded("spread: line", QD._Spread, line, 3)
    local keep = unmarked(line)
    if #keep ~= 3 then fail("spread: 10 pins on a line, limit 3 kept " .. #keep .. ", expected 3") end
    local has = {}
    for _, p in ipairs(keep) do has[math.floor(p.x * 10 + 0.5)] = true end
    if not (has[1] and has[10] and (has[5] or has[6])) then
        fail("spread: the line case should keep both ends and one middle pin")
    end

    local same = {}
    for i = 1, 8 do same[i] = { x = 0.3, y = 0.3 } end
    guarded("spread: identical", QD._Spread, same, 5)
    if #unmarked(same) ~= 5 then fail("spread: 8 identical pins, limit 5 kept " .. #unmarked(same) .. ", expected 5") end

    local sq = { { x = 0.1, y = 0.1 }, { x = 0.9, y = 0.1 }, { x = 0.1, y = 0.9 }, { x = 0.9, y = 0.9 }, { x = 0.5, y = 0.5 } }
    guarded("spread: limit 1", QD._Spread, sq, 1)
    keep = unmarked(sq)
    if #keep ~= 1 or keep[1] ~= sq[5] then fail("spread: limit 1 should keep the centre pin") end
end

local function runPersona(persona)
    local tag = persona.label .. " " .. persona.class
    S.install(persona)
    local L, v = guarded(tag .. ": loading QuestieDB", S.loadQuestieDB, qdbDir)
    version = v
    if L ~= _G.LibQuestieDB or type(L) ~= "table" then fail(tag .. ": QuestieDB loaded but LibQuestieDB is not set") end
    if L.RequireContract(4) ~= true then fail(tag .. ": LibQuestieDB.RequireContract(4) is not true") end

    local PE = guarded("loading Core.lua", S.loadCore, root)
    local QD = guarded("loading QuestData.lua", S.loadAddonFile, questDataPath, PE).QuestData
    S.questLog.set(nil)
    local ok, reason = guarded(tag .. ": QD:Acquire", QD.Acquire, QD, "harness")
    if ok ~= true then fail(tag .. ": QD:Acquire() with QuestieDB returned false: " .. tostring(reason)) end
    guarded(tag .. ": first rebuild", S.runTimers)
    checkErrors(PE, tag .. ": after QD:Acquire")

    -- Quest-log objectives the game would show for this quest, built from QuestieDB.
    local function logObjectives(id, finished)
        local out = {}
        local function add(text, kind)
            out[#out + 1] = { text = text, type = kind, finished = finished }
        end
        local obj = L.Quest.objectives(id) or {}
        for _, o in ipairs(obj[1] or {}) do
            add((name(L.Npc, o[1]) or o[2] or "Creature") .. " slain: 0/1", "monster")
        end
        for _, o in ipairs(obj[2] or {}) do
            add((o[2] or name(L.Object, o[1]) or "Object") .. ": 0/1", "object")
        end
        for _, o in ipairs(obj[3] or {}) do
            add((name(L.Item, o[1]) or o[2] or "Item") .. ": 0/1", "item")
        end
        for _, o in ipairs(obj[5] or {}) do
            add((o[3] or name(L.Npc, o[2]) or "Creature") .. ": 0/1", "monster")
        end
        local te = L.Quest.triggerEnd(id)
        if type(te) == "table" and type(te[1]) == "string" then add(te[1], "event") end
        return out
    end

    local ids = guarded(tag .. ": LibQuestieDB.Quest.GetAllIds", L.Quest.GetAllIds)
    local sorted = {}
    for i = 1, #ids do sorted[i] = ids[i] end
    table.sort(sorted)

    local known = {}
    for _, k in ipairs(KNOWN_PINS) do known[k.quest .. (k.complete and "c" or "l")] = k end
    local knownSeen = 0

    local counts = { quests = #sorted, with_pins = 0, inlog_with_pins = 0, complete_with_pins = 0,
        inlog_pins = 0, complete_pins = 0 }

    for _, id in ipairs(sorted) do
        local title = L.Quest.name(id)
        local got = 0
        for pass = 1, 2 do
            local complete = pass == 2
            local where = tag .. ": quest " .. id .. (complete and " (complete)" or " (in log, not complete)")
            local objectives = guarded(where .. ": building quest-log objectives", logObjectives, id, complete)
            S.questLog.set({ id = id, title = title, complete = complete, objectives = objectives })
            guarded(where, QD.RequestRebuild, QD)
            guarded(where, S.runTimers)
            checkErrors(PE, where)
            local byMap = guarded(where, QD.GetPinsForQuest, QD, id)
            local want = known[id .. (complete and "c" or "l")]
            if want then
                checkKnownPin(want, byMap, where)
                knownSeen = knownSeen + 1
            end
            local n = countPins(byMap)
            if complete then
                counts.complete_pins = counts.complete_pins + n
                if n > 0 then counts.complete_with_pins = counts.complete_with_pins + 1 end
            else
                counts.inlog_pins = counts.inlog_pins + n
                if n > 0 then counts.inlog_with_pins = counts.inlog_with_pins + 1 end
            end
            got = got + n
        end
        if got > 0 then counts.with_pins = counts.with_pins + 1 end
    end
    if knownSeen ~= #KNOWN_PINS then fail(tag .. ": a quest with a known pin is missing from QuestieDB") end
    -- Spot limit: every quest again with QD.spotLimit = 5. Same pins, some marked extra.
    do
        local LIMIT = 5
        local groups = {}   -- ["quest:map"] = number of objective groups seen
        QD._groupHook = function(questID, mapID)
            local key = questID .. ":" .. mapID
            groups[key] = (groups[key] or 0) + 1
        end
        local sawExtra = false
        for _, id in ipairs(sorted) do
            for pass = 1, 2 do
                local complete = pass == 2
                local where = tag .. ": quest " .. id .. " with spot limit" .. (complete and " (complete)" or "")
                S.questLog.set({ id = id, title = L.Quest.name(id), complete = complete,
                    objectives = logObjectives(id, complete) })
                QD.spotLimit = 0
                guarded(where, QD.RequestRebuild, QD)
                guarded(where, S.runTimers)
                local plain = countPins(guarded(where, QD.GetPinsForQuest, QD, id))
                QD.spotLimit = LIMIT
                wipe(groups)
                guarded(where, QD.RequestRebuild, QD)
                guarded(where, S.runTimers)
                checkErrors(PE, where)
                local byMap = guarded(where, QD.GetPinsForQuest, QD, id)
                if countPins(byMap) ~= plain then
                    fail(where .. ": " .. countPins(byMap) .. " pins with the limit, " .. plain .. " without")
                end
                for mapID, list in pairs(byMap) do
                    local kept = 0
                    for _, p in ipairs(list) do
                        if p.extra then sawExtra = true else kept = kept + 1 end
                    end
                    -- At most LIMIT unmarked pins per objective (each objective is one group).
                    local g = groups[id .. ":" .. mapID] or 0
                    if kept > LIMIT * g then
                        fail(where .. ": map " .. mapID .. " has " .. kept .. " unmarked pins from " .. g .. " objectives")
                    end
                end
            end
        end
        if not sawExtra then fail(tag .. ": the spot limit of " .. LIMIT .. " never marked a pin extra") end
        QD._groupHook = nil
        QD.spotLimit = 0
        S.questLog.set({ id = 55, title = L.Quest.name(55), complete = false, objectives = logObjectives(55, false) })
        guarded(tag, QD.RequestRebuild, QD)
        guarded(tag, S.runTimers)
        for _, id in ipairs(sorted) do
            for _, list in pairs(QD:GetPinsForQuest(id)) do
                for _, p in ipairs(list) do if p.extra then fail(tag .. ": limit 0 left a pin marked extra") end end
            end
        end
        -- The arrow pin
        local pin = { x = 0.5, y = 0.5 }
        local fired = {}
        QD:OnChanged("harness", function(reason) fired[#fired + 1] = reason end)
        QD:SetArrowPin(pin)
        QD:SetArrowPin(pin)
        if QD:GetArrowPin() ~= pin or #fired ~= 1 or fired[1] ~= "arrow" then
            fail(tag .. ": SetArrowPin should store the pin and fire \"arrow\" once")
        end
        QD:OnChanged("harness", nil)
    end
    checkFocus(PE, QD, tag)
    S.questLog.set(nil)
    guarded(tag .. ": emptying the quest log", QD.RequestRebuild, QD)
    guarded(tag .. ": emptying the quest log", S.runTimers)
    checkErrors(PE, tag .. ": emptying the quest log")
    QD:Release("harness")
    if QD:GetArrowPin() ~= nil then fail(tag .. ": Release left the arrow pin set") end
    spreadUnit(QD)
    return counts
end

local KEYS = { "quests", "with_pins", "inlog_with_pins", "complete_with_pins", "inlog_pins", "complete_pins" }
local results, observed = {}, {}
for _, persona in ipairs(PERSONAS) do
    local counts = runPersona(persona)
    results[#results + 1] = counts
    for _, k in ipairs(KEYS) do observed[#observed + 1] = { persona.prefix .. k, counts[k] } end
end

---------------------------------------------------------------------------
-- 3. Compare with the baseline.
---------------------------------------------------------------------------
local baselinePath = root .. "/tests/questiedb/baseline.txt"
local baseline = {}
local f = io.open(baselinePath, "r")
if f then
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(%d+)%s*$")
        if k then baseline[k] = tonumber(v) end
    end
    f:close()
end

local mismatch = {}
for _, o in ipairs(observed) do
    local k, n = o[1], o[2]
    if baseline[k] ~= n then
        local diff = baseline[k] and string.format(" (%+d)", n - baseline[k]) or ""
        mismatch[#mismatch + 1] = string.format("  %s: baseline %s, now %d%s", k, tostring(baseline[k]), n, diff)
    end
end
if #mismatch > 0 then
    io.stdout:write("FAIL: counts differ from tests/questiedb/baseline.txt\n", table.concat(mismatch, "\n"), "\n")
    io.stdout:write("Observed:\n")
    for _, o in ipairs(observed) do io.stdout:write(string.format("%s=%d\n", o[1], o[2])) end
    os.exit(1)
end

local parts = {}
for i, persona in ipairs(PERSONAS) do
    parts[i] = string.format("%d with pins (%s)", results[i].with_pins, persona.label)
end
io.stdout:write(string.format("QuestieDB %s: %d quests, %s, 0 errors\n", version, results[1].quests, table.concat(parts, ", ")))
os.exit(0)
