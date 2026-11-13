-- QuestDots: Questie-style objective icons on the world map + minimap, nothing else.
-- Spawn data (where mobs/items/objects are) comes from the QuestieDB data addon,
-- so Questie itself can be disabled.

local QD = CreateFrame("Frame")

local defaults = {
    worldmap      = true,  -- objective icons on the world map
    minimap       = true,  -- objective icons on the minimap
    hideHaze      = true,  -- remove the blue quest-area blobs (map + minimap)
    hideBlizzPins = false, -- also hide Blizzard's numbered quest pins on the world map
    mapSize       = 18,    -- icon size on the world map
    miniSize      = 14,    -- icon size on the minimap
    cluster       = 2,     -- merge spawns closer than this (% of map) into one icon; 0 = off
}
local db

-- Look ------------------------------------------------------------------------
local ICON_PATH = "Interface\\AddOns\\QuestDots\\Icons\\"
local STYLE = {
    slay   = { tex = ICON_PATH .. "slay_mono",   color = { 1.00, 0.45, 0.40 } },
    loot   = { tex = ICON_PATH .. "loot_mono",   color = { 1.00, 0.85, 0.30 } },
    object = { tex = ICON_PATH .. "object_mono", color = { 0.50, 0.80, 1.00 } },
    event  = { tex = ICON_PATH .. "object_mono", color = { 0.75, 0.55, 1.00 } },
    turnin = { atlas = "QuestTurnin", fallback = "Interface\\GossipFrame\\ActiveQuestIcon" },
}
local KIND_LABEL = { slay = "Kill", loot = "Loot", object = "Use", event = "Explore", turnin = "Turn in" }

-- Data ------------------------------------------------------------------------
local QuestDB, NpcDB, ItemDB, ObjectDB
local areaToMap = {}
local pinsByMap = {}            -- [uiMapID] = { pinData, ... }
local spawnCache, nameCache = {}, {}

local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

local function Decode(v)
    if type(v) == "string" then
        local f = loadstring(v)
        if f then
            local ok, t = pcall(f)
            if ok and type(t) == "table" then return t end
        end
        return nil
    end
    return type(v) == "table" and v or nil
end

local function InitData()
    local L = LibQuestieDB
    if not L or not L.Quest then return false, "QuestieDB not found" end
    if L.RequireContract then
        local ok, msg = L.RequireContract(1)
        if not ok then return false, msg end
    end
    QuestDB, NpcDB, ItemDB, ObjectDB = L.Quest, L.Npc, L.Item, L.Object

    local zone = L.Support and L.Support.Get and L.Support.Get("ZoneDB")
    local p = zone and zone.private
    if not p then return false, "QuestieDB zone data missing" end
    for k, v in pairs(Decode(p.areaIdToUiMapId) or {}) do areaToMap[k] = v end
    for k, v in pairs(Decode(p.areaIdToUiMapIdOverride) or {}) do areaToMap[k] = v end
    return true
end

local function Spawns(kind, id)
    if not id or id == 0 then return nil end
    local key = kind .. id
    local s = spawnCache[key]
    if s == nil then
        local entity = (kind == "npc") and NpcDB or ObjectDB
        s = entity.spawns(id) or false
        spawnCache[key] = s
    end
    return s or nil
end

local function Name(kind, id)
    if not id or id == 0 then return nil end
    local key = kind .. id
    local n = nameCache[key]
    if n == nil then
        local entity = (kind == "npc" and NpcDB) or (kind == "object" and ObjectDB) or ItemDB
        n = entity.name(id) or false
        nameCache[key] = n
    end
    return n or nil
end

-- Is this objective already done according to the game's own quest log?
local function ObjectiveState(blizz, ...)
    for _, o in ipairs(blizz) do
        local t = o.text
        if t then
            for i = 1, select("#", ...) do
                local needle = select(i, ...)
                if needle and needle ~= "" and t:find(needle, 1, true) then
                    return o.finished, t
                end
            end
        end
    end
    return false, nil
end

local function AddSpawns(out, spawns, kind, quest, objText, target, seen)
    if not spawns then return end
    local cell = db.cluster
    for areaId, coords in pairs(spawns) do
        local mapID = areaToMap[areaId]
        if mapID and type(coords) == "table" then
            local list = out[mapID]
            if not list then list = {}; out[mapID] = list end
            for _, c in ipairs(coords) do
                local x, y = c[1], c[2]
                if x and y and x >= 0 and y >= 0 then
                    local key = cell > 0 and (mapID .. ":" .. math.floor(x / cell) .. ":" .. math.floor(y / cell)) or nil
                    if not key or not seen[key] then
                        if key then seen[key] = true end
                        list[#list + 1] = {
                            x = x / 100, y = y / 100, kind = kind,
                            questID = quest.id, title = quest.title,
                            objText = objText, target = target,
                        }
                    end
                end
            end
        end
    end
end

local function BuildQuest(out, q)
    if C_QuestLog.IsComplete(q.id) then
        local fin = QuestDB.finishedBy(q.id) or {}
        local seen = {}
        for _, id in ipairs(fin[1] or {}) do AddSpawns(out, Spawns("npc", id), "turnin", q, nil, Name("npc", id), seen) end
        for _, id in ipairs(fin[2] or {}) do AddSpawns(out, Spawns("object", id), "turnin", q, nil, Name("object", id), seen) end
        return
    end

    local blizz = C_QuestLog.GetQuestObjectives(q.id) or {}
    local obj = QuestDB.objectives(q.id) or {}

    -- [1] creatures to kill
    for _, o in ipairs(obj[1] or {}) do
        local name = Name("npc", o[1])
        local done, text = ObjectiveState(blizz, name, o[2])
        if not done then AddSpawns(out, Spawns("npc", o[1]), "slay", q, text or o[2] or name, name, {}) end
    end
    -- [2] objects to interact with
    for _, o in ipairs(obj[2] or {}) do
        local name = Name("object", o[1])
        local done, text = ObjectiveState(blizz, o[2], name)
        if not done then AddSpawns(out, Spawns("object", o[1]), "object", q, text or o[2] or name, name, {}) end
    end
    -- [3] items to collect: show whatever drops them
    for _, o in ipairs(obj[3] or {}) do
        local itemID = o[1]
        local iname = Name("item", itemID)
        local done, text = ObjectiveState(blizz, iname, o[2])
        if not done then
            local seen = {}
            for _, nid in ipairs(ItemDB.npcDrops(itemID) or {}) do
                AddSpawns(out, Spawns("npc", nid), "loot", q, text or iname, Name("npc", nid), seen)
            end
            for _, oid in ipairs(ItemDB.objectDrops(itemID) or {}) do
                AddSpawns(out, Spawns("object", oid), "object", q, text or iname, Name("object", oid), seen)
            end
        end
    end
    -- [5] kill credit: { {npcIds}, baseNpcId, text }
    for _, o in ipairs(obj[5] or {}) do
        local baseName = Name("npc", o[2])
        local done, text = ObjectiveState(blizz, baseName, o[3])
        if not done then
            local seen = {}
            for _, nid in ipairs(o[1] or {}) do
                AddSpawns(out, Spawns("npc", nid), "slay", q, text or o[3] or baseName, Name("npc", nid), seen)
            end
        end
    end
    -- exploration / event trigger: { text, {[zone] = {{x, y}}} }
    local te = QuestDB.triggerEnd(q.id)
    if type(te) == "table" and type(te[2]) == "table" then
        local done, text = ObjectiveState(blizz, te[1])
        if not done then AddSpawns(out, te[2], "event", q, text or te[1], nil, {}) end
    end
    -- hidden helper spots Questie adds by hand: { {spawnList, icon, text, objectiveIndex}, ... }
    for _, o in ipairs(QuestDB.extraObjectives(q.id) or {}) do
        if type(o[1]) == "table" then
            local idx = o[4]
            local b = idx and idx ~= 0 and blizz[idx]
            if not (b and b.finished) then AddSpawns(out, o[1], "event", q, o[3], nil, {}) end
        end
    end
end

local function RebuildPins()
    wipe(pinsByMap)
    if not QuestDB then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0
           and QuestDB.Exists(info.questID) then
            local ok, err = pcall(BuildQuest, pinsByMap, { id = info.questID, title = info.title })
            if not ok and db.debug then print("|cffffd100QuestDots|r", info.questID, err) end
        end
    end
end

-- Pin frames ------------------------------------------------------------------
local function ShowTooltip(self)
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(d.title or ("Quest " .. d.questID), 1, 0.82, 0)
    if d.kind == "turnin" then
        GameTooltip:AddLine("Turn in: " .. (d.target or "?"), 0.3, 1, 0.3)
    else
        if d.objText then GameTooltip:AddLine(d.objText, 1, 1, 1, true) end
        if d.target then GameTooltip:AddLine(KIND_LABEL[d.kind] .. ": " .. d.target, 0.7, 0.7, 0.7) end
    end
    GameTooltip:Show()
end

local hasTurninAtlas

local function CreatePin(parent)
    local f = CreateFrame("Button", nil, parent)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f:SetScript("OnEnter", ShowTooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", function(self)
        if self.data and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(self.data.questID)
        end
    end)
    return f
end

local function StylePin(f, d, size)
    f.data = d
    f:SetSize(size, size)
    local s = STYLE[d.kind]
    if d.kind == "turnin" then
        f.tex:SetVertexColor(1, 1, 1)
        if hasTurninAtlas then f.tex:SetAtlas(s.atlas) else f.tex:SetTexture(s.fallback) end
    else
        f.tex:SetTexture(s.tex)
        f.tex:SetVertexColor(s.color[1], s.color[2], s.color[3])
    end
end

-- World map -------------------------------------------------------------------
local mapPins = {}

local function ForPins(template, fn)
    local ok, iter, state, ctrl = pcall(WorldMapFrame.EnumeratePinsByTemplate, WorldMapFrame, template)
    if not ok or type(iter) ~= "function" then return end
    for pin in iter, state, ctrl do fn(pin) end
end

local function SuppressBlizzard()
    if not WorldMapFrame then return end
    local hazeAlpha = db.hideHaze and 0 or 1
    ForPins("QuestBlobPinTemplate", function(pin) pin:SetAlpha(hazeAlpha) end)
    local hide = db.hideBlizzPins
    ForPins("QuestPinTemplate", function(pin)
        pin:SetAlpha(hide and 0 or 1)
        pin:EnableMouse(not hide)
    end)
end

local function RefreshWorldMap()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local canvas = WorldMapFrame:GetCanvas()
    local list = db.worldmap and pinsByMap[WorldMapFrame:GetMapID()] or {}
    local w, h = canvas:GetSize()
    local scale = 1 / (WorldMapFrame:GetCanvasScale() or 1)  -- fixed icon size while zooming
    local level = canvas:GetFrameLevel() + 3000

    for i, d in ipairs(list) do
        local p = mapPins[i]
        if not p then
            p = CreatePin(canvas)
            mapPins[i] = p
        end
        StylePin(p, d, db.mapSize)
        p:SetFrameStrata(WorldMapFrame:GetFrameStrata())
        p:SetFrameLevel(d.kind == "turnin" and level + 1 or level)
        p:SetScale(scale)
        p:ClearAllPoints()
        p:SetPoint("CENTER", canvas, "TOPLEFT", d.x * w / scale, -d.y * h / scale)
        p:Show()
    end
    for i = #list + 1, #mapPins do mapPins[i]:Hide() end
    SuppressBlizzard()
end

local mapHooked
local function HookWorldMap()
    if mapHooked or not WorldMapFrame then return end
    mapHooked = true
    local function soon() C_Timer.After(0, RefreshWorldMap) end
    hooksecurefunc(WorldMapFrame, "OnMapChanged", soon)
    if WorldMapFrame.OnCanvasScaleChanged then
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", RefreshWorldMap)
    end
    WorldMapFrame:HookScript("OnShow", soon)
end

-- Minimap ---------------------------------------------------------------------
-- Minimap diameter in yards per zoom level (same values HereBeDragons uses).
local MINIMAP_DIAMETER = {
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2/3, 400, 333 + 1/3, 266 + 1/3, 200, 133 + 1/3 },
}

local BLOB_SETTERS = {
    "SetQuestBlobInsideAlpha", "SetQuestBlobOutsideAlpha", "SetQuestBlobRingAlpha",
    "SetTaskBlobInsideAlpha",  "SetTaskBlobOutsideAlpha",  "SetTaskBlobRingAlpha",
}

local function ApplyMinimapHaze()
    if not db.hideHaze then return end   -- turning haze back on needs a /reload
    for _, m in ipairs(BLOB_SETTERS) do
        if Minimap[m] then pcall(Minimap[m], Minimap, 0) end
    end
end

local miniPins, miniList, miniMapID = {}, {}, nil
local last = {}   -- last player x/y/facing/zoom, to skip work when nothing moved

local function HideMiniPins(from)
    for i = from or 1, #miniPins do miniPins[i]:Hide() end
end

local function RefreshMinimapData()
    miniMapID = C_Map.GetBestMapForUnit("player")
    miniList = (db.minimap and miniMapID and pinsByMap[miniMapID]) or {}
    for i, d in ipairs(miniList) do
        local p = miniPins[i]
        if not p then
            p = CreatePin(Minimap)
            miniPins[i] = p
        end
        p:SetFrameLevel(Minimap:GetFrameLevel() + (d.kind == "turnin" and 6 or 5))
        StylePin(p, d, db.miniSize)
    end
    HideMiniPins(#miniList + 1)
    wipe(last)
end

local function UpdateMinimap()
    if #miniList == 0 then return end

    local pos = C_Map.GetPlayerMapPosition(miniMapID, "player")
    if not pos then return HideMiniPins() end
    local px, py = pos:GetXY()
    if not px or IsSecret(px) then return HideMiniPins() end

    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing() or 0
    if not facing or IsSecret(facing) then facing = 0 end
    local zoom = Minimap:GetZoom()
    if last.x == px and last.y == py and last.f == facing and last.z == zoom then return end
    last.x, last.y, last.f, last.z = px, py, facing, zoom

    local mw, mh = C_Map.GetMapWorldSize(miniMapID)
    if not mw or mw == 0 then return HideMiniPins() end

    local sizes     = IsIndoors() and MINIMAP_DIAMETER.indoor or MINIMAP_DIAMETER.outdoor
    local width     = Minimap:GetWidth()
    local yardsToPx = width / (sizes[zoom] or 400)
    local edge      = width / 2 - db.miniSize * 0.4
    local s, c      = math.sin(facing), math.cos(facing)

    for i, d in ipairs(miniList) do
        local p  = miniPins[i]
        local dx =  (d.x - px) * mw * yardsToPx   -- east  = +x
        local dy = -(d.y - py) * mh * yardsToPx   -- north = +y
        if rotate then dx, dy = dx * c + dy * s, -dx * s + dy * c end

        local dist = math.sqrt(dx * dx + dy * dy)
        if dist <= edge then
            p:SetAlpha(1)
            p:ClearAllPoints()
            p:SetPoint("CENTER", Minimap, "CENTER", dx, dy)
            p:Show()
        elseif d.kind == "turnin" then
            -- keep turn-ins on the rim so you can see which way to go
            p:SetAlpha(0.6)
            p:ClearAllPoints()
            p:SetPoint("CENTER", Minimap, "CENTER", dx * edge / dist, dy * edge / dist)
            p:Show()
        else
            p:Hide()
        end
    end
end

-- Refresh plumbing ------------------------------------------------------------
local pending
local function RequestRefresh(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 0.3, function()
        pending = false
        RebuildPins()
        RefreshMinimapData()
        RefreshWorldMap()
    end)
end

local function RequestViewRefresh()
    C_Timer.After(0.1, function()
        RefreshMinimapData()
        RefreshWorldMap()
    end)
end

local acc = 0
local function OnUpdate(_, elapsed)
    acc = acc + elapsed
    if acc < 0.05 then return end
    acc = 0
    UpdateMinimap()
end

QD:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        QuestDotsDB = QuestDotsDB or {}
        for k, v in pairs(defaults) do
            if QuestDotsDB[k] == nil then QuestDotsDB[k] = v end
        end
        db = QuestDotsDB
        hasTurninAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(STYLE.turnin.atlas) ~= nil

        local ok, err = InitData()
        if not ok then
            print("|cffffd100QuestDots|r disabled: " .. tostring(err))
            return
        end
        ApplyMinimapHaze()
        HookWorldMap()
        QD:SetScript("OnUpdate", OnUpdate)
        RequestRefresh(1)
    elseif not db or not QuestDB then
        return
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_WorldMap" then HookWorldMap() end
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        RequestRefresh()
    else
        RequestViewRefresh()   -- zone changes: data is the same, just a different map
    end
end)

for _, e in ipairs({
    "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
}) do
    QD:RegisterEvent(e)
end

-- Slash commands --------------------------------------------------------------
local TOGGLES = { map = "worldmap", mini = "minimap", haze = "hideHaze", blizz = "hideBlizzPins", debug = "debug" }

SLASH_QUESTDOTS1 = "/qd"
SlashCmdList.QUESTDOTS = function(msg)
    if not db then return end
    local cmd, val = strsplit(" ", (msg or ""):lower(), 2)
    local n = tonumber(val)
    if TOGGLES[cmd] then
        local key = TOGGLES[cmd]
        db[key] = not db[key]
        print("|cffffd100QuestDots|r " .. key .. ": " .. (db[key] and "on" or "off"))
        if key == "hideHaze" then
            ApplyMinimapHaze()
            if not db.hideHaze then print("|cffffd100QuestDots|r /reload to bring the minimap haze back") end
        end
    elseif cmd == "size" and n then
        db.mapSize, db.miniSize = n, math.max(10, n - 4)
        print("|cffffd100QuestDots|r icon size: " .. n)
    elseif cmd == "cluster" and n then
        db.cluster = math.max(0, n)
        print("|cffffd100QuestDots|r cluster: " .. db.cluster)
    else
        print("|cffffd100QuestDots|r /qd map | mini | haze | blizz | size <n> | cluster <n>")
        return
    end
    RequestRefresh(0)
end
