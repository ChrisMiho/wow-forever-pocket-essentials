-- Rules for the shared quest data (QuestData.lua), with real quests from QuestieDB.
-- Sources: QuestData.lua's header and comments; docs/superpowers/specs/2026-11-24-0.15.0-polish.md
-- part C (C1 debug line, C3 thinning per map). Fresh client and addon per test.
--
-- Skipped, with a notice, when the QuestieDB release is not available (offline).
local T = ...
if not T.questieDB then return { skip = "QuestieDB is not available" } end
local test, eq, check = T.test, T.eq, T.check
local QW = dofile(T.root .. "/tests/lib/questworld.lua")

local KNOWN_FAILURES = {
}

-- QuestieDB 1.1.1 (Alliance), at the default merge of 2 %:
--   889  "Spirit of the Wind": one loot objective, 1152 spots on 17 maps, one each on 1416 and 1420.
--   5150 "Dadanga is Hungry!": one loot objective, 565 spots, all on map 1449 (Un'Goro Crater).
local SPREAD, SPREAD_SMALL = 889, { 1416, 1420 }
local BUSY, BUSY_MAP = 5150, 1449
local MAX_PINS, MIN_PER_MAP = 300, 30

-- A fresh client with these quests in the log and the quest icons on (so the data is in use).
local function newData(ids)
    local quests = {}
    for i, id in ipairs(ids) do quests[i] = { id = id } end
    local c, PE = T.new({ quest = true, on = { "questIcons" }, setup = function(c)
        QW.setup(c, { quests = quests })
    end })
    c:advance(1.2)
    return c, PE
end

local function count(byMap, map) return type(byMap[map]) == "table" and #byMap[map] or 0 end

---------------------------------------------------------------------------
-- Thinning (C3): at most MAX_PINS spots per objective on each map
---------------------------------------------------------------------------

-- Spec C3: "Thinning to MAX_PINS works per map, not across all maps, so a zone with few spots keeps them."
test("quest data: a map with few spots keeps them when the objective has many on other maps", function()
    local _, PE = newData({ SPREAD })
    local byMap = PE.QuestData:GetPinsForQuest(SPREAD)
    local maps = 0
    for _, list in pairs(byMap) do
        maps = maps + 1
        check(#list <= MAX_PINS, "a map has " .. #list .. " spots of one objective, more than " .. MAX_PINS)
    end
    check(maps >= 10, "QuestieDB changed under the test: quest 889 should have spots on 10 or more maps")
    for _, map in ipairs(SPREAD_SMALL) do
        check(count(byMap, map) >= 1, "map " .. map .. " lost its spot of quest 889 to the busy maps")
    end
end)

-- QuestData.lua MAX_PINS and MIN_PER_MAP: keeping every map's spots must not let one objective keep
-- thousands; it keeps about MAX_PINS in all, plus at most MIN_PER_MAP for each map.
test("quest data: an objective spread over many maps keeps about 300 spots in all", function()
    local _, PE = newData({ SPREAD })
    local total, maps = 0, 0
    for _, list in pairs(PE.QuestData:GetPinsForQuest(SPREAD)) do
        total, maps = total + #list, maps + 1
    end
    check(total <= MAX_PINS + MIN_PER_MAP * maps,
        "quest 889 kept " .. total .. " spots on " .. maps .. " maps, more than its budget")
    check(total >= MAX_PINS * 0.8, "quest 889 kept only " .. total .. " spots")
end)

-- 0.15.0 review: a quest that fails half way (here an error inside Flush, after its pins were
-- made) must leave nothing behind for the next quest: no spots of its own in the next one's pins.
test("quest data: a quest that fails half way leaves none of its spots to the next quest", function()
    local c, PE = T.new({ quest = true, on = { "questIcons" }, setup = function(c)
        QW.setup(c, { quests = { { id = SPREAD }, { id = BUSY } } })
    end })
    local QD = PE.QuestData
    local failed = false
    QD._groupHook = function(questID)
        if questID == SPREAD and not failed then
            failed = true
            error("test: a quest that fails half way")
        end
    end
    c:advance(1.2)
    QD._groupHook = nil
    check(failed, "the failing quest was never built")
    for mapID, list in pairs(QD:GetPinsForQuest(BUSY)) do
        for _, pin in ipairs(list) do
            check(pin.questID == BUSY, "quest " .. BUSY .. " has a spot of quest " .. tostring(pin.questID) .. " on map " .. mapID)
        end
    end
end)

-- Spec C3 (the limit still holds on a busy map) and QuestData.lua MAX_PINS.
test("quest data: a map with more than 300 spots of one objective keeps 300", function()
    local _, PE = newData({ BUSY })
    eq(count(PE.QuestData:GetPinsForQuest(BUSY), BUSY_MAP), MAX_PINS, "spots of quest 5150 kept on map 1449")
end)

---------------------------------------------------------------------------
-- Debug line and the house rule for handlers (C1)
---------------------------------------------------------------------------

local function logLines(c, text)
    local out = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        if line:find(text, 1, true) then out[#out + 1] = line end
    end
    return out
end

-- Spec C1: "The debug line reports the work time (summed per step) and the number of steps, so the
-- log stops showing waiting time as work." Each step reads the quest log count once; here that read
-- costs 7 ms on the profiling clock, and the 0.05 s waits between steps cost nothing.
test("quest data: the rebuild line counts the steps and only the time spent working", function()
    local c, PE = newData({ QW.MANY, QW.SEVEN, QW.ONE, QW.ELSEWHERE, 889 })
    PE:SetDebug(true)
    c.profileMs = 0
    local QL = rawget(c.env, "C_QuestLog")
    local count = QL.GetNumQuestLogEntries
    QL.GetNumQuestLogEntries = function(...)
        c.profileMs = c.profileMs + 7
        return count(...)
    end
    PE.QuestData.cluster = 5                               -- every quest is built again: 5 quests, 2 steps
    PE.QuestData:RequestRebuild()
    c:advance(1.5)
    local lines = logLines(c, "questData: rebuild:")
    eq(#lines, 1, "rebuild lines")
    check(lines[1]:find("5 quests in log, 5 rebuilt in 2 steps, %d+ icons on %d+ maps, 14 ms work$"), lines[1])
    QL.GetNumQuestLogEntries = count
    c:assertClean("rebuild line")
end)

-- CLAUDE.md: "Event handlers and callbacks go through PE:Safe or PE:Wrap"; spec C1: "the performance
-- recorder can then see them".
test("quest data: its event handler and rebuild timer run through PE:Wrap (the recorder sees them)", function()
    local c, PE = newData({ QW.MANY })
    local counters = PE:StartMeasure()
    c:fire("QUEST_LOG_UPDATE")
    c:advance(1)
    local entry = counters.questData
    check(entry and entry.calls >= 2, "questData runs counted: " .. T.show(entry))
    PE:StopMeasure()
end)

return { known = KNOWN_FAILURES }
