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

local LOG_KEY = "questData"
local REBUILD_DELAY = 0.3      -- quest log events are coalesced into one rebuild per this many seconds
local ZONE_DELAY = 0.1
-- An item that drops from more kinds of creature than this is a "drops
-- everywhere" item (cloth, potions, herbs). Showing it would mean thousands of
-- pins and a long pause, so its sources are left out.
local MAX_ITEM_SOURCES = 60

local type, pairs, ipairs, next, select, tostring, tonumber = type, pairs, ipairs, next, select, tostring, tonumber
local pcall, xpcall = pcall, xpcall
local floor = math.floor

-- State ----------------------------------------------------------------------
local frame                       -- private hidden frame; only has events while acquired
local users, userCount = {}, 0    -- [userKey] = true
local listeners = {}              -- [userKey] = fn(reason)

local ready = false               -- QuestieDB was found and understood
local QuestDB, NpcDB, ItemDB, ObjectDB
local areaToMap = {}              -- QuestieDB zone (area) id -> uiMapID
local dungeons                    -- QuestieDB's dungeon table: [areaId] = { name, altIds, parentZone, { {areaId, x, y}, ... } }

local pinsByMap = {}              -- [uiMapID] = { pin, ... }
local questCache = {}             -- [questID] = { sig = string, byMap = { [uiMapID] = { pin, ... } } }
local order = {}                  -- quest ids in quest-log order, as of the last rebuild
local present = {}                -- scratch: quest ids seen in the current rebuild
local logTitles = {}              -- [questID] = title or false, for every quest in the log
local spawnCache, nameCache = {}, {}
local builtCluster                -- the cluster value the cache was built with
local clusterCell = 0             -- cluster value in use by the rebuild that is running
local dirty = true                -- the last rebuild did not finish; do not trust "nothing changed"

local rebuildPending, zonePending, forceNotify = false, false, false

local tracked                     -- quest the owner last tapped
local trackedLoaded = false
local lastTracked                 -- last value handed out through a "tracked" callback

local EMPTY = {}                  -- shared empty table; only ever read
local NO_PINS = {}                -- what GetPins returns for a map with nothing on it
local NO_MAPS = {}                -- what GetPinsForQuest returns for an unknown quest

-- Small helpers --------------------------------------------------------------
local function LogError(msg, stack)
    if type(PE.LogError) == "function" then
        pcall(PE.LogError, PE, LOG_KEY, tostring(msg), stack or "")
    end
end

local function OnError(err)
    local stack = ""
    if type(debugstack) == "function" then
        local ok, s = pcall(debugstack, 2)
        if ok and type(s) == "string" then stack = s end
    end
    LogError(err, stack)
    return err
end

local function Safe(fn, ...)
    return xpcall(fn, OnError, ...)
end

-- "Secret" values cannot be compared or used in maths by addons. If the test
-- itself fails we assume the value is secret.
local function IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, v)
    if not ok then return true end
    return secret and true or false
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
    local f = entity and entity[field]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, id)
    if ok then return v end
    if not readErrorLogged then
        readErrorLogged = true
        LogError("QuestieDB read failed (" .. tostring(field) .. " " .. tostring(id) .. "): " .. tostring(v))
    end
    return nil
end

-- QuestieDB ships its zone tables as text of the form `return { [12] = 1429, ... }`.
local function DecodeIdMap(v, into)
    local t
    if type(v) == "table" then
        t = v
    elseif type(v) == "string" then
        if type(loadstring) == "function" then
            local okLoad, chunk = pcall(loadstring, v)
            if okLoad and type(chunk) == "function" then
                if type(setfenv) == "function" then pcall(setfenv, chunk, {}) end
                local okRun, res = pcall(chunk)
                if okRun and type(res) == "table" then t = res end
            end
        end
        if not t then
            t = {}
            for k, val in v:gmatch("%[(%d+)%]%s*=%s*(%d+)") do
                t[tonumber(k)] = tonumber(val)
            end
        end
    end
    if not t then return end
    for k, val in pairs(t) do
        if type(k) == "number" and type(val) == "number" then into[k] = val end
    end
end

local function InitData()
    local L = LibQuestieDB
    if type(L) ~= "table" then
        return false, Str(PE.questieDBReason) or "The QuestieDB addon is not installed or not switched on."
    end
    if type(L.Quest) ~= "table" or (type(L.Npc) ~= "table" and type(L.Object) ~= "table") then
        return false, "The QuestieDB addon loaded, but its quest data is missing."
    end
    if type(L.RequireContract) == "function" then
        local okCall, ok = pcall(L.RequireContract, 1)
        if okCall and ok == false then
            return false, "The QuestieDB addon is a version this addon cannot read. Update both addons."
        end
    end

    local zone
    local support = L.Support
    if type(support) == "table" and type(support.Get) == "function" then
        local okCall, z = pcall(support.Get, "ZoneDB")
        if okCall then zone = z end
    end
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

    dungeons = type(p.dungeons) == "table" and p.dungeons or nil
    QuestDB = L.Quest
    NpcDB = type(L.Npc) == "table" and L.Npc or nil
    ObjectDB = type(L.Object) == "table" and L.Object or nil
    ItemDB = type(L.Item) == "table" and L.Item or nil
    return true
end

local function QuestExists(id)
    local f = QuestDB and QuestDB.Exists
    if type(f) ~= "function" then return true end
    local ok, v = pcall(f, id)
    return ok and v == true
end

-- kind is "npc" or "object". Returns { [areaId] = { {x, y}, ... } } with x, y in 0..100, or nil.
local function Spawns(kind, id)
    if type(id) ~= "number" or id == 0 then return nil end
    local key = kind .. id
    local s = spawnCache[key]
    if s == nil then
        s = Read(kind == "npc" and NpcDB or ObjectDB, "spawns", id)
        if type(s) ~= "table" then s = false end
        spawnCache[key] = s
    end
    return s or nil
end

-- kind is "npc", "object" or "item".
local function Name(kind, id)
    if type(id) ~= "number" or id == 0 then return nil end
    local key = kind .. id
    local n = nameCache[key]
    if n == nil then
        local entity = (kind == "npc" and NpcDB) or (kind == "object" and ObjectDB) or ItemDB
        n = Str(Read(entity, "name", id)) or false
        nameCache[key] = n
    end
    return n or nil
end

-- Building pins ----------------------------------------------------------------
local function AddPin(out, mapID, x, y, kind, quest, objText, target, inside)
    local list = out[mapID]
    if not list then
        list = {}
        out[mapID] = list
    end
    list[#list + 1] = {
        x = x / 100, y = y / 100, kind = kind,
        questID = quest.id, title = quest.title,
        objText = objText, target = target, inside = inside,
    }
end

-- The target is inside a dungeon: point at the dungeon's entrance(s) instead.
local function AddEntrances(out, areaId, kind, quest, objText, target, seen)
    local d = dungeons and dungeons[areaId]
    if type(d) ~= "table" then return end
    local key = "in:" .. tostring(areaId)
    if seen[key] then return end
    seen[key] = true
    local inside = Str(d[1])
    for _, loc in ipairs(List(d[4])) do
        if type(loc) == "table" then
            local zoneId, x, y = loc[1], loc[2], loc[3]
            local mapID = zoneId ~= nil and areaToMap[zoneId] or nil
            if mapID and mapID ~= 0 and type(x) == "number" and type(y) == "number"
               and x >= 0 and y >= 0 and x <= 100 and y <= 100 then
                AddPin(out, mapID, x, y, kind, quest, objText, target, inside)
            end
        end
    end
end

local function AddSpawns(out, spawns, kind, quest, objText, target, seen)
    if type(spawns) ~= "table" then return end
    local cell = clusterCell
    for areaId, coords in pairs(spawns) do
        if type(coords) == "table" then
            local mapID = areaToMap[areaId]
            if mapID == 0 then mapID = nil end   -- QuestieDB uses 0 for "never show this zone"
            local inInstance = false
            for _, c in ipairs(coords) do
                if type(c) == "table" then
                    local x, y = c[1], c[2]
                    if type(x) == "number" and type(y) == "number" then
                        if x >= 0 and y >= 0 and x <= 100 and y <= 100 then
                            if mapID then
                                local key = cell > 0 and (mapID .. ":" .. floor(x / cell) .. ":" .. floor(y / cell)) or nil
                                if not key or not seen[key] then
                                    if key then seen[key] = true end
                                    AddPin(out, mapID, x, y, kind, quest, objText, target, nil)
                                end
                            end
                        elseif x == -1 and y == -1 then
                            inInstance = true   -- QuestieDB's marker for "somewhere inside an instance"
                        end
                    end
                end
            end
            if inInstance then AddEntrances(out, areaId, kind, quest, objText, target, seen) end
        end
    end
end

-- Whatever drops or holds an item.
local function AddItemSources(out, itemID, quest, objText, seen)
    if type(itemID) ~= "number" or itemID == 0 then return end
    local npcs = List(Read(ItemDB, "npcDrops", itemID))
    if #npcs <= MAX_ITEM_SOURCES then
        for _, nid in ipairs(npcs) do
            AddSpawns(out, Spawns("npc", nid), "loot", quest, objText, Name("npc", nid), seen)
        end
    end
    local objects = List(Read(ItemDB, "objectDrops", itemID))
    if #objects <= MAX_ITEM_SOURCES then
        for _, oid in ipairs(objects) do
            AddSpawns(out, Spawns("object", oid), "object", quest, objText, Name("object", oid), seen)
        end
    end
end

-- Is this objective already done according to the game's own quest log?
-- First by finding one of the given names in the objective text; failing that,
-- when both sides have exactly one objective of that type, they are the same one.
-- Returns done, text.
local function ObjectiveState(blizz, wantType, sole, ...)
    local count = select("#", ...)
    for _, o in ipairs(blizz) do
        if type(o) == "table" then
            local t = o.text
            if not IsSecret(t) and type(t) == "string" then
                for i = 1, count do
                    local needle = select(i, ...)
                    if type(needle) == "string" and needle ~= "" and t:find(needle, 1, true) then
                        return o.finished and true or false, t
                    end
                end
            end
        end
    end
    if sole and wantType then
        local found, matches = nil, 0
        for _, o in ipairs(blizz) do
            if type(o) == "table" and o.type == wantType then
                found = o
                matches = matches + 1
            end
        end
        if matches == 1 then
            local t = found.text
            if IsSecret(t) or type(t) ~= "string" then t = nil end
            return found.finished and true or false, t
        end
    end
    return false, nil
end

-- QuestieDB's icon numbers for its hand-written helper spots.
local EXTRA_KIND = { [1] = "slay", [2] = "loot", [4] = "object", [17] = "object" }

-- Adds pins for everything still to do. Returns how many objectives QuestieDB
-- knows for the quest (0 = it is a plain "go and talk to someone" quest).
local function BuildObjectives(out, q, blizz)
    local obj = Read(QuestDB, "objectives", q.id)
    if type(obj) ~= "table" then obj = EMPTY end
    local kills, objects, items, credits = List(obj[1]), List(obj[2]), List(obj[3]), List(obj[5])
    local known = #kills + #objects + #items + #credits + #List(obj[6])
    if obj[4] ~= nil then known = known + 1 end
    local soleMonster = (#kills + #credits) == 1

    -- [1] creatures to kill: { npcId, text?, icon }
    for _, o in ipairs(kills) do
        if type(o) == "table" then
            local name, dbText = Name("npc", o[1]), Str(o[2])
            local done, text = ObjectiveState(blizz, "monster", soleMonster, name, dbText)
            if not done then
                AddSpawns(out, Spawns("npc", o[1]), "slay", q, text or dbText or name, name, {})
            end
        end
    end
    -- [2] objects to use: { objectId, text?, icon }
    for _, o in ipairs(objects) do
        if type(o) == "table" then
            local name, dbText = Name("object", o[1]), Str(o[2])
            local done, text = ObjectiveState(blizz, "object", #objects == 1, dbText, name)
            if not done then
                AddSpawns(out, Spawns("object", o[1]), "object", q, text or dbText or name, name, {})
            end
        end
    end
    -- [3] items to collect: { itemId, text?, icon }; show whatever drops them
    for _, o in ipairs(items) do
        if type(o) == "table" then
            local name, dbText = Name("item", o[1]), Str(o[2])
            local done, text = ObjectiveState(blizz, "item", #items == 1, name, dbText)
            if not done then
                AddItemSources(out, o[1], q, text or dbText or name, {})
            end
        end
    end
    -- [5] kill credit: { {npcIds}, baseNpcId, text?, icon }
    for _, o in ipairs(credits) do
        if type(o) == "table" then
            local baseName, dbText = Name("npc", o[2]), Str(o[3])
            local done, text = ObjectiveState(blizz, "monster", soleMonster, baseName, dbText)
            if not done then
                local seen = {}
                for _, nid in ipairs(List(o[1])) do
                    AddSpawns(out, Spawns("npc", nid), "slay", q, text or dbText or baseName, Name("npc", nid), seen)
                end
            end
        end
    end
    -- exploration / event trigger: { text, { [areaId] = { {x, y} } } }
    local te = Read(QuestDB, "triggerEnd", q.id)
    if type(te) == "table" and type(te[2]) == "table" then
        known = known + 1
        local dbText = Str(te[1])
        local done, text = ObjectiveState(blizz, "event", true, dbText)
        if not done then
            AddSpawns(out, te[2], "event", q, text or dbText, nil, {})
        end
    end
    -- helper spots QuestieDB adds by hand:
    -- { spawnList?, icon, text?, objectiveIndex, { {"monster"|"object"|"item", id}, ... }? }
    for _, o in ipairs(List(Read(QuestDB, "extraObjectives", q.id))) do
        if type(o) == "table" then
            local idx = o[4]
            local b = type(idx) == "number" and idx > 0 and blizz[idx] or nil
            if not (type(b) == "table" and b.finished) then
                local kind = EXTRA_KIND[o[2]] or "event"
                local text = Str(o[3])
                local seen = {}
                if type(o[1]) == "table" then
                    AddSpawns(out, o[1], kind, q, text, nil, seen)
                end
                for _, ref in ipairs(List(o[5])) do
                    if type(ref) == "table" then
                        local refType, refId = ref[1], ref[2]
                        if refType == "monster" then
                            AddSpawns(out, Spawns("npc", refId), kind, q, text, Name("npc", refId), seen)
                        elseif refType == "object" then
                            AddSpawns(out, Spawns("object", refId), kind, q, text, Name("object", refId), seen)
                        elseif refType == "item" then
                            AddItemSources(out, refId, q, text or Name("item", refId), seen)
                        end
                    end
                end
            end
        end
    end
    return known
end

-- Where to hand the quest in: finishedBy = { {npcIds}?, {objectIds}? }
local function AddTurnIn(out, q)
    local fin = Read(QuestDB, "finishedBy", q.id)
    if type(fin) ~= "table" then return end
    local seen = {}
    for _, id in ipairs(List(fin[1])) do
        AddSpawns(out, Spawns("npc", id), "turnin", q, nil, Name("npc", id), seen)
    end
    for _, id in ipairs(List(fin[2])) do
        AddSpawns(out, Spawns("object", id), "turnin", q, nil, Name("object", id), seen)
    end
end

-- Returns { [uiMapID] = { pin, ... } } for one quest.
local function BuildQuest(q, blizz, complete)
    local out = {}
    if not complete then
        local known = BuildObjectives(out, q, blizz)
        -- Nothing to do but hand it in (a "deliver this" quest).
        if known == 0 and #blizz == 0 and next(out) == nil then complete = true end
    end
    if complete then AddTurnIn(out, q) end
    return out
end

local questErrorLogged = {}
local function LogQuestError(id, err)
    if questErrorLogged[id] then return end
    questErrorLogged[id] = true
    LogError("Quest " .. tostring(id) .. " could not be read: " .. tostring(err))
end

-- A quest is only rebuilt when this text changes.
local function Signature(complete, blizz, title)
    local parts = { complete and "C" or "c", title or "" }
    for _, o in ipairs(blizz) do
        if type(o) == "table" then
            local t = o.text
            if IsSecret(t) or type(t) ~= "string" then t = "?" end
            parts[#parts + 1] = (o.finished and "1" or "0") .. t
        end
    end
    return table.concat(parts, "\n")
end

-- Returns true when the quest's pins were rebuilt.
local function UpdateQuest(id, title)
    local QL = C_QuestLog
    local complete = false
    if QL.IsComplete then complete = QL.IsComplete(id) and true or false end
    local blizz = QL.GetQuestObjectives and QL.GetQuestObjectives(id)
    if type(blizz) ~= "table" then blizz = EMPTY end

    local sig = Signature(complete, blizz, title)
    local entry = questCache[id]
    if entry and entry.sig == sig then return false end

    local q = { id = id, title = title or Str(Read(QuestDB, "name", id)) }
    local ok, byMap = pcall(BuildQuest, q, blizz, complete)
    if not ok then
        LogQuestError(id, byMap)
        byMap = {}
    end
    questCache[id] = { sig = sig, byMap = byMap }
    return true
end

-- Returns true when the pin data changed.
local function Rebuild()
    local QL = C_QuestLog
    if not ready or not (QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return false end

    local changed = dirty
    dirty = true   -- cleared again at the end; stays set if anything below fails

    local cell = tonumber(QD.cluster) or 0
    if cell < 0 then cell = 0 end
    if cell ~= builtCluster then
        builtCluster = cell
        wipe(questCache)
        changed = true
    end
    clusterCell = cell

    wipe(present)
    wipe(logTitles)
    local n = 0
    local num = QL.GetNumQuestLogEntries()
    if type(num) ~= "number" then num = 0 end
    for i = 1, num do
        local info = QL.GetInfo(i)
        if type(info) == "table" and not info.isHeader then
            local id = info.questID
            if type(id) == "number" and id > 0 then
                local title = info.title
                if IsSecret(title) then title = nil end
                title = Str(title)
                logTitles[id] = title or false
                if not info.isHidden and not present[id] and QuestExists(id) then
                    local ok, rebuilt = pcall(UpdateQuest, id, title)
                    if ok then
                        present[id] = true
                        n = n + 1
                        if order[n] ~= id then
                            order[n] = id
                            changed = true
                        end
                        if rebuilt then changed = true end
                    else
                        LogQuestError(id, rebuilt)
                    end
                end
            end
        end
    end
    for i = #order, n + 1, -1 do
        order[i] = nil
        changed = true
    end
    for id in pairs(questCache) do
        if not present[id] then
            questCache[id] = nil
            changed = true
        end
    end

    if changed then
        wipe(pinsByMap)
        for i = 1, n do
            local entry = questCache[order[i]]
            if entry then
                for mapID, list in pairs(entry.byMap) do
                    local dst = pinsByMap[mapID]
                    if not dst then
                        dst = {}
                        pinsByMap[mapID] = dst
                    end
                    local at = #dst
                    for j = 1, #list do dst[at + j] = list[j] end
                end
            end
        end
    end
    dirty = false
    return changed
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
        local key = keys[i]
        local fn = listeners[key]
        if fn and users[key] then Safe(fn, reason) end
    end
end

local function NotifyTracked()
    local now = QD:GetTrackedQuest()
    if now ~= lastTracked then
        lastTracked = now
        if userCount > 0 then Fire("tracked") end
    end
end

local function DoRebuild()
    rebuildPending = false
    if userCount <= 0 then return end
    local force = forceNotify
    forceNotify = false
    local changed = Rebuild()
    if changed or force then Fire("quests") end
    NotifyTracked()
end

local function DoRebuildSafe() Safe(DoRebuild) end

-- At most one rebuild per REBUILD_DELAY, and never a second one while one is waiting.
local function ScheduleRebuild()
    if rebuildPending then return end
    rebuildPending = true
    local ok = false
    if C_Timer and C_Timer.After then
        ok = pcall(C_Timer.After, REBUILD_DELAY, DoRebuildSafe)
    end
    if not ok then DoRebuildSafe() end
end

local function DoZone()
    zonePending = false
    if userCount > 0 then Fire("zone") end
end

local function DoZoneSafe() Safe(DoZone) end

local function ScheduleZone()
    if zonePending then return end
    zonePending = true
    local ok = false
    if C_Timer and C_Timer.After then
        ok = pcall(C_Timer.After, ZONE_DELAY, DoZoneSafe)
    end
    if not ok then DoZoneSafe() end
end

local EVENTS = {
    QUEST_LOG_UPDATE = "quests", QUEST_ACCEPTED = "quests", QUEST_REMOVED = "quests",
    ZONE_CHANGED = "zone", ZONE_CHANGED_INDOORS = "zone", ZONE_CHANGED_NEW_AREA = "zone",
    PLAYER_ENTERING_WORLD = "zone",
    SUPER_TRACKING_CHANGED = "tracked",
}

local function OnEvent(event)
    if userCount <= 0 then return end
    local what = EVENTS[event]
    if what == "quests" then
        ScheduleRebuild()
    elseif what == "zone" then
        ScheduleZone()
    elseif what == "tracked" then
        NotifyTracked()
    end
end

local function StartListening()
    if not frame then
        frame = CreateFrame("Frame")
        frame:Hide()
        frame:SetScript("OnEvent", function(_, event) xpcall(OnEvent, OnError, event) end)
    end
    for event in pairs(EVENTS) do
        pcall(frame.RegisterEvent, frame, event)
    end
end

local function StopListening()
    if frame then pcall(frame.UnregisterAllEvents, frame) end
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
        if not ok then return false, reason or "The QuestieDB addon could not be used." end
        ready = true
    end
    users[userKey] = true
    userCount = userCount + 1
    if userCount == 1 then StartListening() end
    forceNotify = true      -- the new user gets a "quests" callback even if nothing changed
    ScheduleRebuild()
    return true
end

function QD:Release(userKey)
    if userKey == nil or not users[userKey] then return end
    users[userKey] = nil
    userCount = userCount - 1
    if userCount > 0 then return end
    userCount = 0
    StopListening()
    -- Nobody is using the data: forget it all so it costs nothing.
    wipe(pinsByMap)
    wipe(questCache)
    wipe(order)
    wipe(present)
    wipe(logTitles)
    wipe(spawnCache)
    wipe(nameCache)
    builtCluster = nil
    dirty = true
    forceNotify = false
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
    if uiMapID == nil then return NO_PINS end
    return pinsByMap[uiMapID] or NO_PINS
end

function QD:GetAllPins()
    return pinsByMap
end

function QD:GetPinsForQuest(questID)
    local entry = questID ~= nil and questCache[questID] or nil
    return entry and entry.byMap or NO_MAPS
end

-- Public: quest log ------------------------------------------------------------
function QD:IsQuestInLog(questID)
    if type(questID) ~= "number" or questID <= 0 then return false end
    local QL = C_QuestLog
    if QL and QL.IsOnQuest then
        local ok, v = pcall(QL.IsOnQuest, questID)
        if ok and not IsSecret(v) then return v and true or false end
    end
    if QL and QL.GetLogIndexForQuestID then
        local ok, v = pcall(QL.GetLogIndexForQuestID, questID)
        if ok and not IsSecret(v) then return type(v) == "number" and v > 0 end
    end
    return logTitles[questID] ~= nil
end

function QD:GetQuestTitle(questID)
    if type(questID) ~= "number" or questID <= 0 then return nil end
    local title = logTitles[questID]
    if title then return title end
    local QL = C_QuestLog
    if QL and QL.GetTitleForQuestID then
        local ok, t = pcall(QL.GetTitleForQuestID, questID)
        if ok and not IsSecret(t) and Str(t) then return t end
    end
    if ready then return Str(Read(QuestDB, "name", questID)) end
    return nil
end

-- Public: tracked quest ----------------------------------------------------------
local function SaveTracked()
    local db = PE.db
    if type(db) ~= "table" then return end
    if type(db.questData) ~= "table" then db.questData = {} end
    db.questData.tracked = tracked
end

local function LoadTracked()
    if trackedLoaded then return end
    local db = PE.db
    if type(db) ~= "table" then return end   -- saved settings are not there yet; try again next time
    trackedLoaded = true
    if tracked ~= nil then
        SaveTracked()   -- something was tapped before the settings loaded: keep it
        return
    end
    local saved = type(db.questData) == "table" and db.questData.tracked or nil
    if type(saved) == "number" and saved > 0 then tracked = saved end
end

local function SuperTracked()
    local ST = C_SuperTrack
    if not (ST and ST.GetSuperTrackedQuestID) then return nil end
    local ok, id = pcall(ST.GetSuperTrackedQuestID)
    if ok and not IsSecret(id) and type(id) == "number" and id > 0 then return id end
    return nil
end

function QD:SetTrackedQuest(questID)
    if type(questID) ~= "number" or questID <= 0 then questID = nil end
    LoadTracked()
    tracked = questID
    SaveTracked()
    local ST = C_SuperTrack
    if ST and ST.SetSuperTrackedQuestID then
        pcall(ST.SetSuperTrackedQuestID, questID or 0)   -- 0 clears Blizzard's own focus
    end
    Safe(NotifyTracked)
end

function QD:GetTrackedQuest()
    LoadTracked()
    if tracked and self:IsQuestInLog(tracked) then return tracked end
    local id = SuperTracked()
    if id and self:IsQuestInLog(id) then return id end
    return nil
end

-- Public: where the player is --------------------------------------------------
local function ReadPosition()
    local Map = C_Map
    if not (Map and Map.GetBestMapForUnit and Map.GetPlayerMapPosition) then return nil end
    local mapID = Map.GetBestMapForUnit("player")
    if IsSecret(mapID) or type(mapID) ~= "number" then return nil end
    local pos = Map.GetPlayerMapPosition(mapID, "player")
    if IsSecret(pos) or type(pos) ~= "table" then return nil end
    local x, y
    if type(pos.GetXY) == "function" then
        x, y = pos:GetXY()
    else
        x, y = pos.x, pos.y
    end
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
    if type(GetPlayerFacing) ~= "function" then return nil end
    local ok, facing = pcall(GetPlayerFacing)
    if ok and not IsSecret(facing) and type(facing) == "number" then return facing end
    return nil
end

local sizeCache = {}   -- [uiMapID] = { width, height }; map sizes never change

function QD:GetMapWorldSize(uiMapID)
    if type(uiMapID) ~= "number" then return nil end
    local size = sizeCache[uiMapID]
    if not size then
        local Map = C_Map
        if not (Map and Map.GetMapWorldSize) then return nil end
        local ok, w, h = pcall(Map.GetMapWorldSize, uiMapID)
        if not ok or IsSecret(w) or IsSecret(h) or type(w) ~= "number" or type(h) ~= "number"
           or w <= 0 or h <= 0 then
            return nil
        end
        size = { w, h }
        sizeCache[uiMapID] = size
    end
    return size[1], size[2]
end
