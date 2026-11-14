local ADDON_NAME, PE = ...

-- QuestData: where the things your quests ask for are.
--
-- Reads the QuestieDB data addon (global `LibQuestieDB`) and the quest log and
-- turns them into map positions ("pins"). It is shared by the quest icons and
-- the quest arrow, has no switch of its own, and does nothing at all until a
-- module acquires it.
--
-- Interface (see CONTRACT.md):
--   ok, reason = QD:Acquire(userKey)      QD:Release(userKey)
--   QD:GetPins(uiMapID) -> array          QD:GetAllPins() -> { [uiMapID] = array }
--   QD:GetPinsForQuest(questID) -> { [uiMapID] = array }
--   QD:OnChanged(userKey, fn)             fn("quests" | "zone" | "tracked")
--   QD:RequestRebuild()                   QD.cluster (number, % of the map)
--   QD:GetPlayerPosition() -> uiMapID, x, y | nil
--   QD:GetPlayerFacing() -> radians | nil
--   QD:GetMapWorldSize(uiMapID) -> width, height | nil
--   QD:SetTrackedQuest(questID|nil)       QD:GetTrackedQuest() -> questID | nil
--   QD:IsQuestInLog(questID) -> bool      QD:GetQuestTitle(questID) -> string | nil
--   QD.KIND_LABEL
--
-- A pin is { x=, y= (0..1), kind=, questID=, title=, objText=, target=, inside= }.
-- `inside` is only set for a target that lives in a dungeon: the pin then sits
-- on the dungeon's entrance and `inside` is the dungeon's name.
--
-- Everything returned is read only. Never change a pin or a pin list.

local QD = {}
PE.QuestData = QD

QD.KIND_LABEL = { slay = "Kill", loot = "Loot", object = "Use", event = "Explore", turnin = "Turn in" }

-- Spawns closer together than this many percent of the map become one pin.
-- 0 switches merging off. Change it, then call QD:RequestRebuild().
QD.cluster = 2

local REBUILD_DELAY = 0.3      -- quest log events are coalesced into one rebuild per this many seconds
local STEP_DELAY = 0.05        -- a big rebuild is spread over several short steps this far apart
local QUESTS_PER_STEP = 4      -- quests rebuilt in one step
local ZONE_DELAY = 0.1
local MAX_ITEM_SOURCES = 60    -- an item dropped by more kinds of creature than this "drops everywhere": not shown
local MAX_SOURCE_POINTS = 1500 -- one creature or object with more spawn points than this is "everywhere": not shown
local MAX_PINS = 300           -- most pins one objective may have; above it they are thinned evenly

local type, pairs, ipairs, select, tostring, tonumber, pcall, xpcall = type, pairs, ipairs, select, tostring, tonumber, pcall, xpcall
local floor = math.floor

-- State ----------------------------------------------------------------------
local frame                       -- private hidden frame; only has events while acquired
local users, userCount = {}, 0    -- [userKey] = true
local listeners = {}              -- [userKey] = fn(reason)

local ready = false               -- QuestieDB was found and understood
local QuestDB, NpcDB, ItemDB, ObjectDB
local areaToMap = {}              -- QuestieDB zone (area) id -> uiMapID
local dungeons = {}               -- QuestieDB: [areaId] = { name, altIds, parentZone, { {areaId, x, y}, ... } }
local dungeonAlias = {}           -- alternative dungeon area id -> the id `dungeons` knows

local pinsByMap = {}              -- [uiMapID] = { pin, ... }
local questCache = {}             -- [questID] = { sig = string, byMap = { [uiMapID] = { pin, ... } } }
local order = {}                  -- quest ids in quest-log order, as of the last rebuild
local present = {}                -- scratch: quest ids seen in the running rebuild
local spawnCache, nameCache = {}, {}
local builtCluster                -- the cluster value the cache was built with
local clusterCell = 0             -- cluster value in use by the running rebuild
local dirty = true                -- pinsByMap is out of date

local rebuildPending, zonePending, forceNotify, questRemoved = false, false, false, false
local tracked                     -- quest the owner last tapped
local trackedLoaded = false
local lastTracked                 -- last value handed out through a "tracked" callback

local EMPTY = {}                  -- shared empty table; only ever read

-- Small helpers --------------------------------------------------------------
local function LogError(msg, stack)
    if type(PE.LogError) == "function" then
        pcall(PE.LogError, PE, "questData", tostring(msg), stack or "")
    end
end

local function OnError(err)
    LogError(err, type(debugstack) == "function" and debugstack(2) or "")
    return err
end

local function Safe(fn, ...)
    return xpcall(fn, OnError, ...)
end

local function Str(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function List(v)
    if type(v) == "table" then return v end
    return EMPTY
end

-- QuestieDB ------------------------------------------------------------------
local readErrorLogged = false

-- One guarded read, e.g. Read(NpcDB, "spawns", 123). A missing reader or a
-- failing read gives nil, never an error.
local function Read(entity, field, id)
    local f = entity[field]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, id)
    if ok then return v end
    if not readErrorLogged then
        readErrorLogged = true
        LogError("QuestieDB read failed (" .. field .. " " .. tostring(id) .. "): " .. tostring(v))
    end
    return nil
end

-- QuestieDB ships its zone tables as text of the form `return { [12] = 1429, ... }`.
local function DecodeIdMap(v, into)
    if type(v) == "table" then
        for k, val in pairs(v) do into[k] = val end
    elseif type(v) == "string" then
        for k, val in v:gmatch("%[(%d+)%]%s*=%s*(%d+)") do
            into[tonumber(k)] = tonumber(val)
        end
    end
end

local NEEDED = {
    Quest = { "Exists", "objectives", "finishedBy" }, Npc = { "spawns" }, Object = { "spawns" }, Item = {},
}

local function InitData()
    local L = LibQuestieDB
    if type(L) ~= "table" then
        return false, Str(PE.questieDBReason) or "The QuestieDB addon is not installed or not switched on."
    end
    for name, fields in pairs(NEEDED) do
        if type(L[name]) ~= "table" then
            return false, "The QuestieDB addon loaded, but its quest data is missing."
        end
        for _, field in ipairs(fields) do
            if type(L[name][field]) ~= "function" then
                return false, "QuestieDB is a version this addon does not understand."
            end
        end
    end
    -- 4 is the QuestieDB data format this file was written against (release 1.1.0).
    if type(L.RequireContract) == "function" and not L.RequireContract(4) then
        return false, "QuestieDB is a version this addon does not understand."
    end

    local support = L.Support
    local zone = type(support) == "table" and type(support.Get) == "function" and support.Get("ZoneDB")
    local p = type(zone) == "table" and zone.private
    if type(p) ~= "table" then
        return false, "The QuestieDB addon loaded, but its list of zones is missing."
    end
    wipe(areaToMap)
    DecodeIdMap(p.areaIdToUiMapId, areaToMap)
    DecodeIdMap(p.areaIdToUiMapIdOverride, areaToMap)   -- applied second, so it wins
    if next(areaToMap) == nil then
        return false, "The QuestieDB addon loaded, but its list of zones could not be read."
    end

    dungeons = List(p.dungeons)
    wipe(dungeonAlias)
    for id, d in pairs(dungeons) do
        for _, alt in ipairs(List(type(d) == "table" and d[2])) do
            if dungeons[alt] == nil then dungeonAlias[alt] = id end
        end
    end
    QuestDB, NpcDB, ObjectDB, ItemDB = L.Quest, L.Npc, L.Object, L.Item
    return true
end

-- Returns { [areaId] = { {x, y}, ... } } with x, y in 0..100, or nil.
local function Spawns(entity, id)
    if type(id) ~= "number" or id == 0 then return nil end
    local key = (entity == NpcDB and "n" or "o") .. id
    local s = spawnCache[key]
    if s == nil then
        s = Read(entity, "spawns", id)
        local points = 0
        for _, coords in pairs(List(s)) do points = points + #List(coords) end
        if type(s) ~= "table" or points > MAX_SOURCE_POINTS then s = false end
        spawnCache[key] = s
    end
    return s or nil
end

local function Name(entity, id)
    if type(id) ~= "number" or id == 0 then return nil end
    local key = (entity == NpcDB and "n" or entity == ObjectDB and "o" or "i") .. id
    local n = nameCache[key]
    if n == nil then
        n = Str(Read(entity, "name", id)) or false
        nameCache[key] = n
    end
    return n or nil
end

-- Building pins ----------------------------------------------------------------
-- Pins of the objective being built wait here until Flush() moves them out.
local buf, bufMap, seen = {}, {}, {}

local function AddPin(mapID, x, y, kind, quest, objText, target, inside)
    local n = #buf + 1
    bufMap[n] = mapID
    buf[n] = {
        x = x / 100, y = y / 100, kind = kind,
        questID = quest.id, title = quest.title,
        objText = objText, target = target, inside = inside,
    }
end

-- End of one objective: hand its pins over (thinned evenly if there are too many).
local function Flush(out)
    local n = #buf
    local take = n > MAX_PINS and MAX_PINS or n
    for i = 1, take do
        local j = floor((i - 1) * n / take) + 1
        local list = out[bufMap[j]]
        if not list then
            list = {}
            out[bufMap[j]] = list
        end
        list[#list + 1] = buf[j]
    end
    wipe(buf)
    wipe(bufMap)
    wipe(seen)
end

-- The target is inside a dungeon: point at the dungeon's entrance(s) instead.
local function AddEntrances(areaId, kind, quest, objText, target)
    areaId = dungeonAlias[areaId] or areaId
    local d = dungeons[areaId]
    if type(d) ~= "table" or seen[-areaId] then return end
    seen[-areaId] = true
    for _, loc in ipairs(List(d[4])) do
        local mapID, x, y = areaToMap[loc[1] or 0], loc[2], loc[3]
        if mapID and mapID ~= 0 and type(x) == "number" and type(y) == "number" then
            AddPin(mapID, x, y, kind, quest, objText, target, Str(d[1]))
        end
    end
end

local function AddSpawns(spawns, kind, quest, objText, target)
    local cell = clusterCell
    for areaId, coords in pairs(List(spawns)) do
        local mapID = areaToMap[areaId]
        if mapID == 0 then mapID = nil end   -- QuestieDB uses 0 for "never show this zone"
        local inInstance = false
        for _, c in ipairs(List(coords)) do
            local x, y = c[1], c[2]
            if type(x) ~= "number" or type(y) ~= "number" then
                -- not a position
            elseif x == -1 and y == -1 then
                inInstance = true   -- QuestieDB's marker for "somewhere inside an instance"
            elseif mapID and x >= 0 and y >= 0 and x <= 100 and y <= 100 then
                local key = cell > 0 and (mapID * 1e8 + floor(x / cell) * 1e4 + floor(y / cell))
                if not key then
                    AddPin(mapID, x, y, kind, quest, objText, target)
                elseif not seen[key] then
                    seen[key] = true
                    AddPin(mapID, x, y, kind, quest, objText, target)
                end
            end
        end
        if inInstance and type(areaId) == "number" then AddEntrances(areaId, kind, quest, objText, target) end
    end
end

-- Whatever drops or holds an item.
local function AddItemSources(itemID, quest, objText)
    if type(itemID) ~= "number" then return end
    local npcs = List(Read(ItemDB, "npcDrops", itemID))
    if #npcs <= MAX_ITEM_SOURCES then
        for _, id in ipairs(npcs) do
            AddSpawns(Spawns(NpcDB, id), "loot", quest, objText, Name(NpcDB, id))
        end
    end
    local objects = List(Read(ItemDB, "objectDrops", itemID))
    if #objects <= MAX_ITEM_SOURCES then
        for _, id in ipairs(objects) do
            AddSpawns(Spawns(ObjectDB, id), "object", quest, objText, Name(ObjectDB, id))
        end
    end
end

-- Finds the quest-log objective that goes with a QuestieDB one, and says
-- whether it is finished. Of all log objectives whose text contains one of the
-- given names the tightest fit wins ("Night Web Spider" must not pick "Young
-- Night Web Spider slain"); the right type and not yet used by an earlier
-- objective count for more. With no name hit, a lone objective of that type is it.
-- Returns done, text.
local function ObjectiveState(blizz, claimed, wantType, sole, ...)
    local best, bestScore, typed, typedCount = nil, nil, nil, 0
    for index, o in ipairs(blizz) do
        local t = o.text
        if o.type == wantType then
            typed, typedCount = index, typedCount + 1
        end
        if type(t) == "string" then
            for i = 1, select("#", ...) do
                local needle = select(i, ...)
                if needle and t:find(needle, 1, true) then
                    local score = #(t:gsub("%d", ""))
                    if o.type ~= wantType then score = score + 1000 end
                    if claimed[index] then score = score + 10000 end
                    if not bestScore or score < bestScore then best, bestScore = index, score end
                    break
                end
            end
        end
    end
    if not best and sole and typedCount == 1 then best = typed end
    if not best then return false, nil end
    claimed[best] = true
    return blizz[best].finished and true or false, Str(blizz[best].text)
end

-- QuestieDB's icon numbers (src/corrections/enum/icons.lua): slay, loot, event, object, talk, interact.
local ICON_KIND = { [1] = "slay", [2] = "loot", [3] = "event", [4] = "object", [5] = "event", [17] = "object" }

-- Adds pins for everything still to do. Returns how many objectives QuestieDB
-- knows for the quest (0 = it is a plain "go and talk to someone" quest).
local function BuildObjectives(out, q, blizz)
    local obj = List(Read(QuestDB, "objectives", q.id))
    local kills, objects, items, credits = List(obj[1]), List(obj[2]), List(obj[3]), List(obj[5])
    local known = #kills + #objects + #items + #credits + #List(obj[6]) + (obj[4] and 1 or 0)
    local soleMonster = (#kills + #credits) == 1
    local claimed = {}

    -- [1] creatures: { npcId, text?, icon } (the icon says kill, talk to, use...)
    for _, o in ipairs(kills) do
        local name, dbText = Name(NpcDB, o[1]), Str(o[2])
        local done, text = ObjectiveState(blizz, claimed, "monster", soleMonster, name, dbText)
        if not done then
            AddSpawns(Spawns(NpcDB, o[1]), ICON_KIND[o[3]] or "slay", q, text or dbText or name, name)
            Flush(out)
        end
    end
    -- [2] objects to use: { objectId, text?, icon }
    for _, o in ipairs(objects) do
        local name, dbText = Name(ObjectDB, o[1]), Str(o[2])
        local done, text = ObjectiveState(blizz, claimed, "object", #objects == 1, dbText, name)
        if not done then
            AddSpawns(Spawns(ObjectDB, o[1]), "object", q, text or dbText or name, name)
            Flush(out)
        end
    end
    -- [3] items to collect: { itemId, text?, icon }; show whatever drops them
    for _, o in ipairs(items) do
        local name, dbText = Name(ItemDB, o[1]), Str(o[2])
        local done, text = ObjectiveState(blizz, claimed, "item", #items == 1, name, dbText)
        if not done then
            AddItemSources(o[1], q, text or dbText or name)
            Flush(out)
        end
    end
    -- [5] kill credit: { {npcIds}, baseNpcId, text?, icon }
    for _, o in ipairs(credits) do
        local baseName, dbText = Name(NpcDB, o[2]), Str(o[3])
        local done, text = ObjectiveState(blizz, claimed, "monster", soleMonster, baseName, dbText)
        if not done then
            for _, id in ipairs(List(o[1])) do
                AddSpawns(Spawns(NpcDB, id), ICON_KIND[o[4]] or "slay", q, text or dbText or baseName, Name(NpcDB, id))
            end
            Flush(out)
        end
    end
    -- exploration / event trigger: { text, { [areaId] = { {x, y} } } }
    local te = List(Read(QuestDB, "triggerEnd", q.id))
    if type(te[2]) == "table" then
        known = known + 1
        local dbText = Str(te[1])
        local done, text = ObjectiveState(blizz, claimed, "event", true, dbText)
        if not done then
            AddSpawns(te[2], "event", q, text or dbText, nil)
            Flush(out)
        end
    end
    -- helper spots QuestieDB adds by hand:
    -- { spawnList?, icon, text?, objectiveIndex, { {"monster"|"object", id}, ... }? }
    for _, o in ipairs(List(Read(QuestDB, "extraObjectives", q.id))) do
        local b = blizz[o[4] or 0]
        if not (b and b.finished) then
            local kind, text = ICON_KIND[o[2] or 0] or "event", Str(o[3])
            AddSpawns(o[1], kind, q, text, nil)
            for _, ref in ipairs(List(o[5])) do
                local entity = (ref[1] == "monster" and NpcDB) or (ref[1] == "object" and ObjectDB)
                if entity then
                    AddSpawns(Spawns(entity, ref[2]), kind, q, text, Name(entity, ref[2]))
                end
            end
            Flush(out)
        end
    end
    return known
end

-- Returns { [uiMapID] = { pin, ... } } for one quest.
local function BuildQuest(q, blizz, complete)
    local out = {}
    Flush(out)   -- start clean, even if the quest before this one failed half way
    if not complete then
        local known = BuildObjectives(out, q, blizz)
        -- Nothing to do but hand it in (a "deliver this" quest).
        complete = known == 0 and #blizz == 0 and next(out) == nil
    end
    if complete then
        -- finishedBy = { {npcIds}?, {objectIds}? }
        local fin = List(Read(QuestDB, "finishedBy", q.id))
        for _, id in ipairs(List(fin[1])) do
            AddSpawns(Spawns(NpcDB, id), "turnin", q, nil, Name(NpcDB, id))
        end
        for _, id in ipairs(List(fin[2])) do
            AddSpawns(Spawns(ObjectDB, id), "turnin", q, nil, Name(ObjectDB, id))
        end
        Flush(out)
    end
    return out
end

local questErrorLogged = {}
local function LogQuestError(id, err)
    if questErrorLogged[id] then return end
    questErrorLogged[id] = true
    LogError("Quest " .. tostring(id) .. " could not be read: " .. tostring(err))
end

-- Returns "same", "rebuilt", or "later" (it needs rebuilding but `allowed` is false).
local function UpdateQuest(id, title, allowed)
    local QL = C_QuestLog
    local complete = QL.IsComplete and QL.IsComplete(id) and true or false
    local blizz = List(QL.GetQuestObjectives and QL.GetQuestObjectives(id))

    -- A quest is only rebuilt when this text changes.
    local parts = { complete and "C" or "c", title or "" }
    for _, o in ipairs(blizz) do
        parts[#parts + 1] = (o.finished and "1" or "0") .. tostring(o.text)
    end
    local sig = table.concat(parts, "\n")
    local entry = questCache[id]
    if entry and entry.sig == sig then return "same" end
    if not allowed then return "later" end

    local ok, byMap = pcall(BuildQuest, { id = id, title = title }, blizz, complete)
    if not ok then
        LogQuestError(id, byMap)
        byMap = {}
    end
    questCache[id] = { sig = sig, byMap = byMap }
    return "rebuilt"
end

-- One step of a rebuild. Returns changed, more: `more` means it stopped early
-- (QUESTS_PER_STEP quests rebuilt) and must be called again; `changed` is only
-- meaningful on the last step.
local function Rebuild()
    local QL = C_QuestLog
    if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return false, false end

    local cell = tonumber(QD.cluster) or 0
    if cell < 0.02 then cell = 0 end
    if cell ~= builtCluster then
        builtCluster = cell
        wipe(questCache)
        dirty = true
    end
    clusterCell = cell

    wipe(present)
    local n, budget = 0, QUESTS_PER_STEP
    for i = 1, QL.GetNumQuestLogEntries() or 0 do
        local info = QL.GetInfo(i)
        local id = type(info) == "table" and not info.isHeader and not info.isHidden and info.questID
        if type(id) == "number" and id > 0 and not present[id] and Read(QuestDB, "Exists", id) == true then
            local ok, state = pcall(UpdateQuest, id, Str(info.title), budget > 0)
            if not ok then
                LogQuestError(id, state)
            elseif state == "later" then
                dirty = true
                return false, true
            else
                if state == "rebuilt" then
                    budget = budget - 1
                    dirty = true
                end
                present[id] = true
                n = n + 1
                if order[n] ~= id then
                    order[n] = id
                    dirty = true
                end
            end
        end
    end
    for i = #order, n + 1, -1 do
        order[i] = nil
        dirty = true
    end
    local shrunk = false
    for id in pairs(questCache) do
        if not present[id] then
            questCache[id] = nil
            shrunk = true
        end
    end
    if shrunk then
        -- A quest left the log: drop what was remembered for it (the rest is re-read on demand).
        wipe(spawnCache)
        wipe(nameCache)
        dirty = true
    end
    if not dirty then return false, false end

    wipe(pinsByMap)
    for i = 1, n do
        for mapID, list in pairs(questCache[order[i]].byMap) do
            local dst = pinsByMap[mapID]
            if not dst then
                dst = {}
                pinsByMap[mapID] = dst
            end
            local at = #dst
            for j = 1, #list do dst[at + j] = list[j] end
        end
    end
    dirty = false
    return true, false
end

-- Tracked quest ----------------------------------------------------------------
local function SaveTracked()
    local db = PE.db
    if type(db) ~= "table" then return end
    if type(db.questData) ~= "table" then db.questData = {} end
    db.questData.tracked = tracked
end

local function LoadTracked()
    local db = PE.db
    if trackedLoaded or type(db) ~= "table" then return end
    trackedLoaded = true
    local saved = type(db.questData) == "table" and db.questData.tracked
    if tracked == nil and type(saved) == "number" then tracked = saved end
end

-- Callbacks and timers -------------------------------------------------------
local function Fire(reason)
    local keys, n = {}, 0
    for key in pairs(listeners) do
        if users[key] then
            n = n + 1
            keys[n] = key
        end
    end
    for i = 1, n do
        local fn = listeners[keys[i]]
        if fn and users[keys[i]] then Safe(fn, reason) end
    end
end

local function NotifyTracked()
    local now = QD:GetTrackedQuest()
    if now ~= lastTracked then
        lastTracked = now
        if userCount > 0 then Fire("tracked") end
    end
end

local function After(delay, fn)
    return C_Timer and C_Timer.After and pcall(C_Timer.After, delay, fn) or false
end

-- Returns true when the rebuild is not finished and wants another step.
local function RebuildStep()
    if userCount <= 0 then return false end
    local changed, more = Rebuild()
    if more then return true end
    if questRemoved then
        questRemoved = false
        -- The tapped quest was handed in or abandoned: forget it for good.
        if tracked and not QD:IsQuestInLog(tracked) then
            tracked = nil
            SaveTracked()
        end
    end
    local force = forceNotify
    forceNotify = false
    if changed or force then Fire("quests") end
    NotifyTracked()
    return false
end

local function OnRebuildTimer()
    local ok, more = Safe(RebuildStep)
    if ok and more and After(STEP_DELAY, OnRebuildTimer) then return end
    rebuildPending = false
end

-- At most one rebuild per REBUILD_DELAY, and never a second one while one is waiting or running.
local function ScheduleRebuild()
    if rebuildPending then return end
    rebuildPending = After(REBUILD_DELAY, OnRebuildTimer)
end

local function OnZoneTimer()
    zonePending = false
    if userCount > 0 then Fire("zone") end
end

local EVENTS = {
    QUEST_LOG_UPDATE = "quests", QUEST_ACCEPTED = "quests", QUEST_REMOVED = "quests",
    ZONE_CHANGED = "zone", ZONE_CHANGED_INDOORS = "zone", ZONE_CHANGED_NEW_AREA = "zone",
    PLAYER_ENTERING_WORLD = "zone",
}

local function OnEvent(event)
    if userCount <= 0 then return end
    if EVENTS[event] == "quests" then
        if event == "QUEST_REMOVED" then questRemoved = true end
        ScheduleRebuild()
    elseif EVENTS[event] == "zone" and not zonePending then
        zonePending = After(ZONE_DELAY, OnZoneTimer)
    end
end

-- Public: lifetime -----------------------------------------------------------
function QD:Acquire(userKey)
    if userKey == nil then return false, "No name was given for who is using the quest data." end
    if users[userKey] then return true end
    if not ready then
        local okCall, ok, reason = pcall(InitData)
        if not okCall then
            LogError("QuestieDB could not be read: " .. tostring(ok))
            return false, "The QuestieDB addon loaded, but its data could not be read."
        end
        if not ok then return false, reason end
        ready = true
    end
    users[userKey] = true
    userCount = userCount + 1
    if userCount == 1 then
        if not frame then
            frame = CreateFrame("Frame")
            frame:Hide()
            frame:SetScript("OnEvent", function(_, event) xpcall(OnEvent, OnError, event) end)
        end
        for event in pairs(EVENTS) do
            pcall(frame.RegisterEvent, frame, event)
        end
    end
    forceNotify = true      -- the new user gets a "quests" callback even if nothing changed
    ScheduleRebuild()
    return true
end

function QD:Release(userKey)
    if userKey == nil or not users[userKey] then return end
    users[userKey] = nil
    userCount = userCount - 1
    if userCount > 0 then return end
    frame:UnregisterAllEvents()
    -- Nobody is using the data: forget it all so it costs nothing.
    wipe(pinsByMap)
    wipe(questCache)
    wipe(order)
    wipe(spawnCache)
    wipe(nameCache)
    dirty = true
    forceNotify, questRemoved = false, false
    lastTracked = nil
end

function QD:OnChanged(userKey, fn)
    if userKey == nil then return end
    listeners[userKey] = type(fn) == "function" and fn or nil
end

function QD:RequestRebuild()
    if userCount <= 0 then return end
    forceNotify = true
    ScheduleRebuild()
end

-- Public: pins -----------------------------------------------------------------
function QD:GetPins(uiMapID)
    return uiMapID ~= nil and pinsByMap[uiMapID] or EMPTY
end

function QD:GetAllPins()
    return pinsByMap
end

function QD:GetPinsForQuest(questID)
    local entry = questID ~= nil and questCache[questID]
    return entry and entry.byMap or EMPTY
end

-- Public: quest log ------------------------------------------------------------
function QD:IsQuestInLog(questID)
    local QL = C_QuestLog
    if type(questID) ~= "number" or not (QL and QL.IsOnQuest) then return false end
    local ok, on = pcall(QL.IsOnQuest, questID)
    return ok and on and true or false
end

function QD:GetQuestTitle(questID)
    local QL = C_QuestLog
    if type(questID) ~= "number" or not (QL and QL.GetTitleForQuestID) then return nil end
    local ok, title = pcall(QL.GetTitleForQuestID, questID)
    return ok and Str(title) or nil
end

-- The quest the owner last tapped, for as long as it is in the quest log.
function QD:SetTrackedQuest(questID)
    if type(questID) ~= "number" or questID <= 0 then questID = nil end
    LoadTracked()
    tracked = questID
    SaveTracked()
    local ST = C_SuperTrack
    if ST and ST.SetSuperTrackedQuestID then
        pcall(ST.SetSuperTrackedQuestID, questID or 0)   -- Blizzard's own tracker follows; 0 clears it
    end
    Safe(NotifyTracked)
end

function QD:GetTrackedQuest()
    LoadTracked()
    if tracked and self:IsQuestInLog(tracked) then return tracked end
    return nil
end

-- Public: where the player is --------------------------------------------------
-- "Secret" values cannot be compared or used in maths by addons. If the test
-- itself fails we assume the value is secret.
local function IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, v)
    return not ok or (secret and true or false)
end

local function ReadPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if IsSecret(mapID) or type(mapID) ~= "number" then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if IsSecret(pos) or type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if IsSecret(x) or IsSecret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
    if x == 0 and y == 0 then return nil end   -- "no position here" (instances)
    return mapID, x, y
end

function QD:GetPlayerPosition()
    local ok, mapID, x, y = pcall(ReadPosition)
    if ok and mapID then return mapID, x, y end
    return nil
end

function QD:GetPlayerFacing()
    local ok, facing = pcall(GetPlayerFacing)
    if ok and not IsSecret(facing) and type(facing) == "number" then return facing end
    return nil
end

local sizeCache = {}   -- [uiMapID] = { width, height }; map sizes never change

function QD:GetMapWorldSize(uiMapID)
    local size = sizeCache[uiMapID or 0]
    if not size then
        local ok, w, h = pcall(C_Map and C_Map.GetMapWorldSize, uiMapID)
        if not ok or type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
        size = { w, h }
        sizeCache[uiMapID] = size
    end
    return size[1], size[2]
end
