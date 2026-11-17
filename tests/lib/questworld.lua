-- A quest log with real quests from the pinned QuestieDB release, for the quest feature tests
-- (tests/features/questarrow_test.lua, questicons_test.lua). Quests (QuestieDB 1.1.1, Alliance):
--   33  "Wolves Across the Border": 34 loot spots on Elwynn Forest (and 21 on map 1426)
--   21  "Skirmish at Echo Ridge":    7 kill spots on Elwynn Forest
--   6   "Bounty on Garrick Padfoot": 1 loot spot on Elwynn Forest
--   35  "Further Concerns":          a turn-in spot only (give it complete = true)
--   55  "Morbent Fel":               one kill spot, in Duskwood only
--   745 "Sharing the Land" (Horde):  three kill objectives, 26 spots in three camps on Mulgore
-- W.check(c, PE) fails with a clear message when an update of QuestieDB changed one of these.
local W = {}

W.HOME, W.AWAY, W.OTHER = 1429, 1431, 1426          -- Elwynn Forest, Duskwood, (33's other map)
W.MULGORE = 1412
W.MANY, W.SEVEN, W.ONE, W.HANDIN, W.ELSEWHERE = 33, 21, 6, 35, 55
W.CAMPS = 745
W.WIDTH, W.HEIGHT = 3470, 2314                      -- Elwynn Forest in yards, as in the smoke test
W.MULGORE_WIDTH, W.MULGORE_HEIGHT = 5137, 3425

local function name(entity, id)
    local ok, n = pcall(entity.name, id)
    return ok and type(n) == "string" and n or nil
end

-- The log entry the game would give for a quest: its objectives from QuestieDB's own list.
function W.entry(L, spec)
    local id = spec.id
    local out = {}
    local function add(text, kind) out[#out + 1] = { text = text, type = kind, finished = spec.complete and true or false } end
    local obj = L.Quest.objectives(id) or {}
    for _, o in ipairs(obj[1] or {}) do add((name(L.Npc, o[1]) or "Creature") .. " slain: 0/1", "monster") end
    for _, o in ipairs(obj[2] or {}) do add((o[2] or name(L.Object, o[1]) or "Object") .. ": 0/1", "object") end
    for _, o in ipairs(obj[3] or {}) do add((name(L.Item, o[1]) or "Item") .. ": 0/1", "item") end
    for _, o in ipairs(obj[5] or {}) do add((o[3] or name(L.Npc, o[2]) or "Creature") .. ": 0/1", "monster") end
    return { id = id, title = L.Quest.name(id) or ("Quest " .. id), complete = spec.complete, objectives = out }
end

-- spec.quests: { { id =, complete = }, ... }; spec.focus: quest id or nil; spec.watched: ids in the
-- game's tracker; spec.pos = { x, y, facing, map }. Call before c:loadAddon() (T.new's setup).
function W.setup(c, spec)
    local w = c.world
    -- continent, top, left: the continent and each map's north-west corner in continent yards
    -- (C_Map.GetWorldPosFromMapPos in tests/lib/fakeclient.lua).
    w.maps[W.HOME] = { name = "Elwynn Forest", width = W.WIDTH, height = W.HEIGHT, continent = 0, top = -7939, left = 1535 }
    w.maps[W.AWAY] = { name = "Duskwood", width = 2700, height = 1800, continent = 0, top = -9716, left = 833 }
    w.maps[W.OTHER] = { name = "Dun Morogh", width = 3000, height = 2000, continent = 0, top = -4487, left = 1802 }
    w.maps[W.MULGORE] = { name = "Mulgore", width = W.MULGORE_WIDTH, height = W.MULGORE_HEIGHT,
        continent = 1, top = -272, left = 2047 }
    local pos = spec.pos or {}
    w.player.map, w.player.x, w.player.y, w.player.facing = pos.map or W.HOME, pos.x or 0.45, pos.y or 0.62, pos.facing or 0
    local L = rawget(c.env, "LibQuestieDB")
    assert(L, "questworld: QuestieDB is not loaded in this client")
    w.questLog.quests = {}
    for _, q in ipairs(spec.quests or {}) do w.questLog.quests[#w.questLog.quests + 1] = W.entry(L, q) end
    w.questLog.focus = spec.focus
    w.questLog.watched = spec.watched or {}
end

-- Every quest id QuestieDB knows in 1 .. last, as log entries (a crowded log).
function W.crowd(c, last)
    local L = rawget(c.env, "LibQuestieDB")
    local list = {}
    for id = 1, last do
        if name(L.Quest, id) then list[#list + 1] = { id = id } end
    end
    return list
end

local function count(by, map) return type(by[map]) == "table" and #by[map] or 0 end

function W.check(c, PE)
    local QD = PE.QuestData
    local function fail(msg) error("QuestieDB changed under the quest tests: " .. msg, 3) end
    local function inLog(id) return QD:IsQuestInLog(id) end
    if inLog(W.MANY) and count(QD:GetPinsForQuest(W.MANY), W.HOME) < 20 then fail("quest 33 no longer has 20 or more spots on map 1429") end
    if inLog(W.SEVEN) and count(QD:GetPinsForQuest(W.SEVEN), W.HOME) < 6 then fail("quest 21 no longer has 6 or more spots on map 1429") end
    if inLog(W.ONE) and count(QD:GetPinsForQuest(W.ONE), W.HOME) ~= 1 then fail("quest 6 no longer has exactly one spot on map 1429") end
    if inLog(W.CAMPS) and count(QD:GetPinsForQuest(W.CAMPS), W.MULGORE) < 20 then fail("quest 745 no longer has 20 or more spots on map 1412") end
    if inLog(W.ELSEWHERE) and (count(QD:GetPinsForQuest(W.ELSEWHERE), W.AWAY) < 1
        or count(QD:GetPinsForQuest(W.ELSEWHERE), W.HOME) ~= 0) then
        fail("quest 55 is no longer only in Duskwood")
    end
end

return W
