-- The few WoW client functions QuestieDB, Core.lua and QuestData.lua touch while
-- loading and while QuestData builds pins, plus helpers for the harness.
--
--   S.init(root)                 load the decoders and the TOC reader from tests/lib
--   S.install()                  (re)install the client globals below
--   S.loadQuestieDB(dir)         load QuestieDB from an unpacked release -> LibQuestieDB, version
--   S.loadCore(root)             load Core.lua into a fresh namespace -> PE
--   S.loadAddonFile(path, PE)    load one PocketEssentials file into PE -> PE
--   S.runTimers()                run C_Timer.After callbacks until none are left
--   S.questLog.set(q | nil)      the quest log holds exactly q = { id, title, complete, objectives }
--
-- PE.harnessErrors lists every PE:LogError call ({ module, msg, stack }).

local S = {}
local root, metadata, encoding

local noop = function() end

function S.init(repoRoot)
    root = repoRoot
    local LibDeflate = dofile(root .. "/tests/lib/LibDeflate.lua")
    encoding = dofile(root .. "/tests/questiedb/decode.lua")(LibDeflate)
    metadata = dofile(root .. "/tests/lib/metadata.lua")
end

-- Frames: only what the loaded files call.
local Frame = {}
Frame.__index = Frame
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:Hide() self.shown = false end
function Frame:Show() self.shown = true end

local function CreateFrame()
    return setmetatable({ events = {}, scripts = {}, shown = true }, Frame)
end

-- C_Timer.After only queues; S.runTimers() runs the queue.
local timers = {}

function S.runTimers()
    local guard = 0
    while #timers > 0 do
        guard = guard + 1
        if guard > 10000 then error("C_Timer callbacks keep scheduling more callbacks") end
        local fn = table.remove(timers, 1)
        fn()
    end
end

-- The quest log: empty, or exactly one quest.
local current
S.questLog = {}
function S.questLog.set(q) current = q end

local function quest(id)
    return current and current.id == id and current or nil
end

local C_QuestLog = {
    GetNumQuestLogEntries = function() return current and 1 or 0 end,
    GetInfo = function(i)
        if i ~= 1 or not current then return nil end
        return { questID = current.id, title = current.title, isHeader = false, isHidden = false }
    end,
    IsComplete = function(id) local q = quest(id); return q and q.complete or false end,
    GetQuestObjectives = function(id) local q = quest(id); return q and q.objectives or {} end,
    IsOnQuest = function(id) return quest(id) ~= nil end,
    GetTitleForQuestID = function(id) local q = quest(id); return q and q.title or nil end,
}

function S.install()
    timers = {}
    current = nil
    _G.CreateFrame = CreateFrame
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_QuestLog = C_QuestLog
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.time = os.time
    _G.debugstack = function(level) return debug.traceback("", (level or 1) + 1) end
    _G.DEFAULT_CHAT_FRAME = { AddMessage = noop }
    -- QuestieDB: the correction files ask for the player's faction and class.
    _G.UnitFactionGroup = function() return "Alliance", "Alliance" end
    _G.UnitClassBase = function() return "WARRIOR", 1 end
    _G.GetLocale = function() return "enUS" end
    _G.C_EncodingUtil = {
        DecodeBase64 = encoding.DecodeBase64,
        DecompressString = encoding.DecompressString,
        DeserializeCBOR = encoding.DeserializeCBOR,
    }
end

function S.loadQuestieDB(dir)
    local toc = dir .. "/QuestieDB_Forever.toc"
    local _, header = metadata.load(toc, "QuestieDB")   -- installs C_AddOns.GetAddOnMetadata
    metadata.loadAddon(toc, "QuestieDB", dir, "forever")
    return _G.LibQuestieDB, header.Version
end

function S.loadAddonFile(path, PE)
    local chunk, err = loadfile(path)
    if not chunk then error("cannot load " .. path .. ": " .. tostring(err), 0) end
    chunk("PocketEssentials", PE)
    return PE
end

function S.loadCore(repoRoot)
    local PE = S.loadAddonFile(repoRoot .. "/addons/PocketEssentials/Core.lua", {})
    PE.harnessErrors = {}
    local logError = PE.LogError
    PE.LogError = function(self, module, msg, stack)
        PE.harnessErrors[#PE.harnessErrors + 1] = { module = module, msg = msg, stack = stack or "" }
        return logError(self, module, msg, stack)
    end
    return PE
end

return S
