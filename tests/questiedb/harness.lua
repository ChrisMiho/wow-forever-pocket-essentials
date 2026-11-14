-- Offline QuestieDB harness.
--
--   luajit tests/questiedb/harness.lua <QuestieDB dir> <repo root> [QuestData.lua]
--
-- Loads the real QuestieDB addon (its own reading code, from the release zip) and
-- our Core.lua and QuestData.lua under WoW API stand-ins, then puts every quest
-- QuestieDB knows through QuestData twice: once "in the log, not complete" and
-- once "complete". Any Lua error or PE:LogError call fails the run, and so does
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
-- 2. With QuestieDB.
---------------------------------------------------------------------------
S.install()
local L, version = guarded("loading QuestieDB", S.loadQuestieDB, qdbDir)
if L ~= _G.LibQuestieDB or type(L) ~= "table" then fail("QuestieDB loaded but LibQuestieDB is not set") end
if L.RequireContract(4) ~= true then fail("LibQuestieDB.RequireContract(4) is not true") end

local PE = guarded("loading Core.lua", S.loadCore, root)
local QD = guarded("loading QuestData.lua", S.loadAddonFile, questDataPath, PE).QuestData
S.questLog.set(nil)
local ok, reason = guarded("QD:Acquire", QD.Acquire, QD, "harness")
if ok ~= true then fail("QD:Acquire() with QuestieDB returned false: " .. tostring(reason)) end
guarded("first rebuild", S.runTimers)
checkErrors(PE, "after QD:Acquire")

-- Quest-log objectives the game would show for this quest, built from QuestieDB.
local function name(entity, id)
    local f = type(id) == "number" and entity.name
    local v = f and f(id)
    return type(v) == "string" and v or nil
end

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

local function countPins(byMap)
    local n = 0
    for _, list in pairs(byMap) do n = n + #list end
    return n
end

local ids = guarded("LibQuestieDB.Quest.GetAllIds", L.Quest.GetAllIds)
local sorted = {}
for i = 1, #ids do sorted[i] = ids[i] end
table.sort(sorted)

local counts = { quests = #sorted, with_pins = 0, inlog_with_pins = 0, complete_with_pins = 0,
    inlog_pins = 0, complete_pins = 0 }

for _, id in ipairs(sorted) do
    local title = L.Quest.name(id)
    local got = 0
    for pass = 1, 2 do
        local complete = pass == 2
        local where = "quest " .. id .. (complete and " (complete)" or " (in log, not complete)")
        local objectives = guarded(where .. ": building quest-log objectives", logObjectives, id, complete)
        S.questLog.set({ id = id, title = title, complete = complete, objectives = objectives })
        guarded(where, QD.RequestRebuild, QD)
        guarded(where, S.runTimers)
        checkErrors(PE, where)
        local n = countPins(guarded(where, QD.GetPinsForQuest, QD, id))
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
S.questLog.set(nil)
guarded("emptying the quest log", QD.RequestRebuild, QD)
guarded("emptying the quest log", S.runTimers)
checkErrors(PE, "emptying the quest log")
QD:Release("harness")

---------------------------------------------------------------------------
-- 3. Compare with the baseline.
---------------------------------------------------------------------------
local KEYS = { "quests", "with_pins", "inlog_with_pins", "complete_with_pins", "inlog_pins", "complete_pins" }
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
for _, k in ipairs(KEYS) do
    if baseline[k] ~= counts[k] then
        local diff = baseline[k] and string.format(" (%+d)", counts[k] - baseline[k]) or ""
        mismatch[#mismatch + 1] = string.format("  %s: baseline %s, now %d%s", k, tostring(baseline[k]), counts[k], diff)
    end
end
if #mismatch > 0 then
    io.stdout:write("FAIL: counts differ from tests/questiedb/baseline.txt\n", table.concat(mismatch, "\n"), "\n")
    io.stdout:write("Observed:\n")
    for _, k in ipairs(KEYS) do io.stdout:write(string.format("%s=%d\n", k, counts[k])) end
    os.exit(1)
end

io.stdout:write(string.format("QuestieDB %s: %d quests, %d with pins, 0 errors\n", version, counts.quests, counts.with_pins))
os.exit(0)
