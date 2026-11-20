-- Pocket Essentials: quest icons (module "questIcons").
-- Objective icons on the world map and the minimap for the quests in the log.
-- Where things are comes from PE.QuestData (QuestData.lua); this file only
-- draws. Ported from the old standalone QuestDots addon.
--
-- Which quests get icons is the "Show icons for" option: the quests in
-- Blizzard's quest tracker plus the focused one (the default), only the quest
-- focused in the quest log (Blizzard's "Focus"), or every quest in the log. Tapping an icon does not change the focus.
--
-- Touch (there is no hover): tap an icon and a short text box says what the
-- icon is. The box goes away by itself after a few seconds, when another icon
-- is tapped, when the same icon is tapped again, or when the map is closed.
-- It is our own frame in the addon's large font, not GameTooltip: Blizzard's
-- quest-area pin rewrites GameTooltip every frame while the pointer rests
-- inside a quest area.
--
-- Nothing here touches protected frames, so nothing waits for combat to end.
-- The only Blizzard frame changed is the world map's quest-area pin, and only
-- with SetAlpha; its old alpha is remembered and put back.
local ADDON_NAME, PE = ...

if type(PE) ~= "table" or type(PE.RegisterModule) ~= "function" then return end

local type, pairs, tonumber, tostring, pcall, next = type, pairs, tonumber, tostring, pcall, next
local max, min, sqrt, sin, cos, floor = math.max, math.min, math.sqrt, math.sin, math.cos, math.floor

local KEY = "questIcons"

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local DEFAULTS = {
    show = "tracked", -- "tracked" | "focus" | "all": which quests get icons
    map = true,       -- icons on the world map
    mini = true,      -- icons on the minimap
    hideHaze = true,  -- hide Blizzard's blue quest areas (map and minimap)
    size = "medium",  -- "small" | "medium" | "large"
    cluster = 2,      -- merge spawns closer than this many % of the map; 0 = off
    spots = 5,        -- most spots drawn per objective; 0 = all
}

-- Icon sizes in pixels on a 720p screen (a 6 inch 720p screen has about ten
-- pixels to the millimetre, so "medium" is roughly 3 mm on the map).
local MAP_PX = { xsmall = 18, small = 22, medium = 28, large = 36 }
local MINI_PX = { xsmall = 11, small = 14, medium = 18, large = 22 }
-- On the minimap the tap area of an icon is at least this big. On the world
-- map the tap area is exactly the icon, so the map can still be dragged and
-- Blizzard's own pins underneath can still be tapped.
local MINI_HIT_PX = 32
local TRACKED_SCALE = 1.25 -- with "All quests", icons of the focused quest are drawn this much larger
-- Most icons drawn at once: every world map icon is moved on every frame of a
-- zoom, and the minimap moves its icons ten times a second while walking.
local MAP_MAX = 150
local MINI_MAX = 40
local MINI_INTERVAL = 0.1 -- seconds between minimap updates
local LABEL_SECONDS = 5
local DEFAULT_CLUSTER = 2
local DEFAULT_SPOTS = 5
local MAX_CLUSTER = 10   -- the settings' Merge control goes 0 to 10
local MAX_SPOTS = 20     -- the settings' Spots control goes 1 to 20, then All

local OLD_ADDON_MESSAGE = "Delete the old QuestDots folder from AddOns, then reload."
local TURN_ON_MESSAGE = "Turn on \"Quest icons\" in the Pocket Essentials settings first."
local RELOAD_REASON = "Reload to bring back the blue quest areas on the minimap."

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------

local ICON_PATH = "Interface\\AddOns\\PocketEssentials\\Icons\\"
local STYLE = {
    slay   = { tex = ICON_PATH .. "slay_mono",   color = { 1.00, 0.45, 0.40 } },
    loot   = { tex = ICON_PATH .. "loot_mono",   color = { 1.00, 0.85, 0.30 } },
    object = { tex = ICON_PATH .. "object_mono", color = { 0.50, 0.80, 1.00 } },
    event  = { tex = ICON_PATH .. "object_mono", color = { 0.75, 0.55, 1.00 } },
    turnin = { tex = "Interface\\GossipFrame\\ActiveQuestIcon", color = { 1, 1, 1 } }, -- the yellow "?"
}

local KIND_LABEL = { slay = "Kill", loot = "Loot", object = "Use", event = "Explore", turnin = "Turn in" }

-- The icon list, exported as PE.QuestIconKey for the settings page (tex and
-- color come from STYLE, label from KIND_LABEL).
local KIND_DESC = {
    slay = "A creature to kill.",
    loot = "A creature that drops a quest item.",
    object = "An object in the world to click, use or open. It may hold a quest item.",
    event = "A place to go to, or someone to talk to.",
    turnin = "Where to hand the quest in, once you have done everything it asks.",
}
local KIND_ORDER = { "slay", "loot", "object", "event", "turnin" }
local iconKey = {}
for i = 1, #KIND_ORDER do
    local kind = KIND_ORDER[i]
    iconKey[i] = { kind = kind, label = KIND_LABEL[kind], tex = STYLE[kind].tex,
                   color = STYLE[kind].color, desc = KIND_DESC[kind] }
end
PE.QuestIconKey = iconKey

local BLOB_TEMPLATE = "QuestBlobPinTemplate" -- Blizzard_SharedMapDataProviders/QuestBlobDataProvider.xml

-- Minimap diameter in yards for each zoom level. These numbers are not in
-- Blizzard's interface code; they are the ones the HereBeDragons library uses.
local MINIMAP_YARDS = {
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}

-- Minimap blob settings that hide the haze: every part transparent, and the
-- ring shrunk to nothing. Textures are left alone: our own blank texture
-- turned the minimap solid green on the device (0.0.3), because the minimap
-- cannot draw it. Blizzard's interface code never sets these, so the game
-- engine owns the normal values; it may also put them back when the world
-- loads, which is why they are set again after loading screens, zone changes
-- and quest changes. The game has no way to read the normal values back, so
-- only a reload restores them.
-- (Minimap setters: MinimapFrameAPIDocumentation.lua, forever 1.60.1.)
local BLOB_SETTINGS = {
    { "SetQuestBlobInsideAlpha", 0 }, { "SetQuestBlobOutsideAlpha", 0 }, { "SetQuestBlobRingAlpha", 0 },
    { "SetTaskBlobInsideAlpha", 0 }, { "SetTaskBlobOutsideAlpha", 0 }, { "SetTaskBlobRingAlpha", 0 },
    { "SetQuestBlobRingScalar", 0 }, { "SetTaskBlobRingScalar", 0 },
}
local HAZE_AGAIN_SECONDS = 2 -- after a loading screen, set the haze again this much later too

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local mod                  -- set by RegisterModule near the end of the file
local QD                   -- PE.QuestData while enabled
local active = false       -- true while the feature is on and allowed to draw
local blocked              -- plain-language reason nothing is drawn, or nil
local trackedID            -- the focused quest, or nil
local clusterSet = false   -- we changed PE.QuestData.cluster and .spotLimit
local arrowPin             -- the spot the quest arrow points at; drawn even when it is a surplus one
local blobsZeroed = false  -- the minimap haze was hidden this session

local EMPTY = {}

local dbgMini              -- debug log only: the last minimap line written, so a repeat is not written again

-- Which quests get icons. Rebuilt only when the focus, the quest tracker or
-- the option changes; the draw loops only look questIDs up in it. Two tables
-- take turns so a rebuild allocates nothing.
local showAll = true                -- "All quests": no filter
local showSet, spareSet = {}, {}    -- [questID] = true

local mapPins, mapShown = {}, 0
local mapState = {}        -- what the world map icons were last drawn from
local mapHooked = false

local miniPins, miniShown = {}, 0
local miniList, miniMapID, miniW, miniH = EMPTY, nil, nil, nil
local last = {}            -- last player position/facing/zoom, to skip work when nothing moved
local ticker, tickerOn, tickBusy, acc = nil, false, false, 0

local label, labelTried, labelSerial = nil, false, 0

-- The world map's quest-area pin(s) we made invisible: [pin] = the alpha it had before.
local hazeTouched = setmetatable({}, { __mode = "k" })

-- Script handlers and hooks, wrapped once the module is registered.
local pinClick, tickHandler, mapChangedHook, mapScaleHook, mapShowHook, mapHideHook, dataChanged

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Opt(key)
    local opts = mod and mod.opts
    local value
    if type(opts) == "table" then value = opts[key] end
    if value == nil then value = DEFAULTS[key] end
    return value
end

local function IsNumber(v)
    return type(v) == "number" and v == v
end

-- UI units (for a frame at UIParent's scale) for n pixels on a 720p screen.
local function Px(n)
    local UI = PE.UI
    if type(UI) == "table" and type(UI.Px) == "function" then
        local ok, value = pcall(UI.Px, UI, n)
        if ok and IsNumber(value) and value > 0 then return value end
    end
    return n * 768 / 720
end

local function IconSize(view)
    local sizes = (view == "map") and MAP_PX or MINI_PX
    return Px(sizes[Opt("size")] or sizes.medium)
end

-- What the settings' number control can show is what the map uses: a whole
-- number from 0 to MAX_CLUSTER, anything else is the default (as the
-- control shows it; the saved value is left alone until a press).
local function ClusterValue()
    local value = tonumber(Opt("cluster"))
    if not value or value ~= floor(value) or value < 0 or value > MAX_CLUSTER then return DEFAULT_CLUSTER end
    return value
end

-- 0 = all spots, else a whole number from 1 to MAX_SPOTS; anything else is
-- the default, as the settings show it.
local function SpotsValue()
    local value = tonumber(Opt("spots"))
    if not value or value ~= floor(value) or value < 0 or value > MAX_SPOTS then return DEFAULT_SPOTS end
    return value
end

local function ValidPin(d)
    return type(d) == "table" and IsNumber(d.x) and IsNumber(d.y)
end

local function Escape(text)
    return (tostring(text):gsub("|", "||"))
end

-- Debug log: a minimap line, written only when it differs from the last one.
-- Only called while the log is on.
local function DebugMini(text)
    if text == dbgMini then return end
    dbgMini = text
    PE:Debug(KEY, text)
end

---------------------------------------------------------------------------
-- Which quests get icons ("Show icons for")
---------------------------------------------------------------------------

local function AddWatched(set)
    if type(QD.GetWatchedQuests) ~= "function" then return end
    local list = QD:GetWatchedQuests()
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local id = list[i]
        if id ~= nil then set[id] = true end
    end
end

-- "tracked" (the default): the tracker's quests plus the focused one.
-- "focus": the focused quest; with none focused, the quests in Blizzard's
-- tracker. "all": no filter. Uses trackedID, so set that first. Returns true if the set changed.
local function RebuildFilter()
    local mode = Opt("show")
    local all = (mode == "all") or not QD
    local set = spareSet
    for id in pairs(set) do set[id] = nil end
    if not all then
        if mode == "focus" and trackedID ~= nil then
            set[trackedID] = true
        elseif mode == "focus" then
            AddWatched(set)
        else
            AddWatched(set) -- "tracked" (and any unknown saved value)
            if trackedID ~= nil then set[trackedID] = true end
        end
    end
    local changed = (all ~= showAll)
    if not changed then
        for id in pairs(set) do
            if not showSet[id] then changed = true break end
        end
    end
    if not changed then
        for id in pairs(showSet) do
            if not set[id] then changed = true break end
        end
    end
    spareSet, showSet, showAll = showSet, set, all
    return changed
end

-- Debug log only: how many pins of this list the filter lets through.
local function CountShown(list)
    local n = 0
    for i = 1, #list do
        local d = list[i]
        if ValidPin(d) and (showAll or showSet[d.questID]) and (not d.extra or d == arrowPin) then n = n + 1 end
    end
    return n
end

-- Is there anything in this pin list that the filter lets through?
local function AnyShown(list)
    for i = 1, #list do
        local d = list[i]
        if ValidPin(d) and (showAll or showSet[d.questID]) and (not d.extra or d == arrowPin) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- The text box shown after a tap
---------------------------------------------------------------------------

local function HideLabel()
    labelSerial = labelSerial + 1 -- cancels the pending "hide later" timer
    if label then
        label.owner, label.data = nil, nil
        label:Hide()
    end
end

local function EnsureLabel()
    if label or labelTried then return label end
    labelTried = true
    local UI = PE.UI
    if type(UI) ~= "table" or type(UI.CreateText) ~= "function" or not UIParent then return nil end
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:EnableMouse(false) -- taps go straight through it
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetAllPoints()
    f.border:SetColorTexture(0.52, 0.52, 0.57, 1)
    f.fill = f:CreateTexture(nil, "BORDER")
    f.fill:SetColorTexture(0.06, 0.06, 0.08, 0.96)
    f.text = UI:CreateText(f, "small")
    label = f
    return f
end

local function LabelText(d)
    local lines, n = {}, 1
    lines[1] = "|cffffd100" .. Escape(d.title or ("Quest " .. tostring(d.questID))) .. "|r"
    local kinds = (QD and QD.KIND_LABEL) or KIND_LABEL
    if d.kind == "turnin" then
        n = n + 1
        lines[n] = "|cff4dff4d" .. (d.target and ("Turn in: " .. Escape(d.target)) or "Turn in") .. "|r"
    else
        if d.objText then
            n = n + 1
            lines[n] = Escape(d.objText)
        end
        if d.target and d.target ~= d.objText then
            n = n + 1
            lines[n] = "|cffb3b3b3" .. tostring(kinds[d.kind] or KIND_LABEL[d.kind] or "Go to") .. ": " .. Escape(d.target) .. "|r"
        end
    end
    if d.inside then
        n = n + 1
        lines[n] = "|cff80ccffInside " .. Escape(d.inside) .. "|r"
    end
    return table.concat(lines, "\n"), n
end

-- owner: the icon the box sits above (world map), or nil to sit under the minimap.
local function ShowLabel(owner, d, view)
    local f = EnsureLabel()
    if not f then return end
    local str, lineCount = LabelText(d)
    local pad, border, gap, width = Px(10), max(Px(2), 1), Px(6), Px(380)

    local text = f.text
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
    text:SetWidth(width)
    text:SetText(str)
    local height = text:GetStringHeight()
    if not IsNumber(height) or height < Px(10) then height = lineCount * Px(25) end

    f:SetSize(width + pad * 2, height + pad * 2)
    f.fill:ClearAllPoints()
    f.fill:SetPoint("TOPLEFT", f, "TOPLEFT", border, -border)
    f.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -border, border)
    f:ClearAllPoints()
    if owner then
        f:SetPoint("BOTTOM", owner, "TOP", 0, gap)
    else
        f:SetPoint("TOP", Minimap, "BOTTOM", 0, -gap)
    end
    f.owner, f.data, f.view = owner, d, view
    f:Show()

    labelSerial = labelSerial + 1
    local serial = labelSerial
    mod:After(LABEL_SECONDS, function()
        if labelSerial == serial then HideLabel() end
    end)
end

---------------------------------------------------------------------------
-- Icon frames (pooled: created once, reused for ever)
---------------------------------------------------------------------------

local function CreatePin(parent, view)
    local f = CreateFrame("Button", nil, parent)
    f:Hide()
    f.view = view
    f.shown = false
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f:SetScript("OnClick", pinClick)
    -- Clicks only: there is no hover on a touch screen.
    if type(f.SetMouseMotionEnabled) == "function" then pcall(f.SetMouseMotionEnabled, f, false) end
    return f
end

local function ShowPin(f)
    if not f.shown then
        f.shown = true
        f:Show()
    end
end

local function HidePin(f)
    if f.shown then
        f.shown = false
        f:Hide()
        if label and label.owner == f then HideLabel() end
    end
end

-- size and hit (the tap area) are in the frame's own units.
local function StylePin(f, d, size, hit)
    if f.data ~= d then
        if label and label.owner == f then HideLabel() end
        f.data = d
    end
    local kind = STYLE[d.kind] and d.kind or "event"
    if f.kind ~= kind then
        f.kind = kind
        local style = STYLE[kind]
        f.tex:SetTexture(style.tex)
        f.tex:SetVertexColor(style.color[1], style.color[2], style.color[3])
    end
    if f.size ~= size or f.hit ~= hit then
        f.size, f.hit = size, hit
        f:SetSize(size, size)
        local inset = (hit > size) and -(hit - size) / 2 or 0
        f:SetHitRectInsets(inset, inset, inset, inset)
    end
end

-- Minimap only (its tap areas overlap): the shown icon whose centre is
-- nearest the pointer, or `clicked` if that cannot be told.
local function NearestMiniPin(clicked)
    if type(GetCursorPosition) ~= "function" then return clicked end
    local cx, cy = GetCursorPosition()
    local scale = clicked:GetEffectiveScale()
    if not (IsNumber(cx) and IsNumber(cy) and IsNumber(scale) and scale > 0) then return clicked end
    cx, cy = cx / scale, cy / scale
    local best, bestDist = clicked, nil
    for i = 1, miniShown do
        local p = miniPins[i]
        if p and p.shown and p.data then
            local x, y = p:GetCenter()
            if IsNumber(x) and IsNumber(y) then
                local dx, dy = x - cx, y - cy
                local dist = dx * dx + dy * dy
                if not bestDist or dist < bestDist then best, bestDist = p, dist end
            end
        end
    end
    return best
end

local function OnPinClick(self)
    if not active or not QD then return end
    local onMap = (self.view == "map")
    local target = onMap and self or NearestMiniPin(self)
    local d = target and target.data
    if type(d) ~= "table" then return end
    if PE.debugOn then PE:Debug(KEY, "icon tapped (" .. (onMap and "world map" or "minimap") .. "): quest " .. PE.Plain(d.questID)) end

    if label and label.data == d and label:IsShown() then
        HideLabel() -- a second tap on the same icon puts the text away
        return
    end
    HideLabel()
    if onMap then
        ShowLabel(self, d, "map")
    elseif Minimap then
        ShowLabel(nil, d, "mini")
    end
end

---------------------------------------------------------------------------
-- Blizzard's blue quest areas ("haze")
---------------------------------------------------------------------------

-- World map: the haze is one permanent pin. It is made invisible with
-- SetAlpha(0) and its old alpha is put back when the option or the feature is
-- switched off.
--
-- ALTERNATIVE FOR THE DEVICE TEST (not used): if SetAlpha(0) turns out not to
-- hide it, the blob pin has its own setters, pin:SetFillAlpha(0) and
-- pin:SetBorderAlpha(0); Blizzard's normal values to restore are 128 and 192
-- (QuestBlobDataProvider.lua:68-69).
local function SetWorldMapHaze(map, hide)
    if hide then
        if type(map.EnumeratePinsByTemplate) ~= "function" then return end
        local ok, iter, state, ctrl = pcall(map.EnumeratePinsByTemplate, map, BLOB_TEMPLATE)
        if not ok or type(iter) ~= "function" then return end
        for pin in iter, state, ctrl do
            if type(pin) == "table" and type(pin.SetAlpha) == "function" then
                if hazeTouched[pin] == nil then
                    local alpha = type(pin.GetAlpha) == "function" and pin:GetAlpha()
                    hazeTouched[pin] = IsNumber(alpha) and alpha or 1
                    if PE.debugOn then PE:Debug(KEY, "world map haze hidden") end
                end
                pin:SetAlpha(0)
            end
        end
    elseif next(hazeTouched) ~= nil then
        if PE.debugOn then PE:Debug(KEY, "world map haze restored") end
        for pin, alpha in pairs(hazeTouched) do
            hazeTouched[pin] = nil
            pcall(pin.SetAlpha, pin, alpha)
        end
    end
end

local function RestoreWorldMapHaze()
    SetWorldMapHaze(nil, false)
end

local function ZeroMinimapBlobs()
    local mm = Minimap
    if type(mm) ~= "table" then return end
    for i = 1, #BLOB_SETTINGS do
        local entry = BLOB_SETTINGS[i]
        local setter = mm[entry[1]]
        if type(setter) == "function" and pcall(setter, mm, entry[2]) then
            if PE.debugOn and not blobsZeroed then PE:Debug(KEY, "minimap haze hidden") end
            blobsZeroed = true
        end
    end
end

-- Sets the minimap haze settings again, only while they should be hidden.
local function ReapplyMinimapHaze()
    if active and Opt("hideHaze") then ZeroMinimapBlobs() end
end

-- The "Reload now" prompt is only shown while the minimap haze is hidden but
-- should be visible (option switched off, or the whole feature switched off).
local function UpdateReloadPrompt()
    if not blobsZeroed then return end
    if active and Opt("hideHaze") then
        if type(mod.CancelReload) == "function" then mod:CancelReload() end
    else
        mod:RequestReload(RELOAD_REASON)
    end
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

-- The scale that makes an icon the same size on screen whatever the map zoom.
local function MapScale(canvas)
    local canvasScale = canvas:GetEffectiveScale()
    local uiScale = UIParent and UIParent:GetEffectiveScale()
    if IsNumber(canvasScale) and canvasScale > 0.0001 and IsNumber(uiScale) and uiScale > 0 then
        return uiScale / canvasScale
    end
    return 1
end

-- Just under Blizzard's own quest pins, the player arrow and party members.
-- nil (leave the level alone) if the map cannot say.
local function MapLevel(map)
    if type(map.GetPinFrameLevelsManager) ~= "function" then return nil end
    local ok, manager = pcall(map.GetPinFrameLevelsManager, map)
    if not ok or type(manager) ~= "table" or type(manager.GetValidFrameLevel) ~= "function" then return nil end
    local okLevel, level = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_QUEST_PING")
    if okLevel and IsNumber(level) and level > 0 then return level end
    return nil
end

-- Only "CENTER" is ever set, so SetPoint replaces it; no ClearAllPoints needed.
local function PlaceMapPin(p, d, canvas, scale, width, height)
    p:SetScale(scale)
    p:SetPoint("CENTER", canvas, "TOPLEFT", d.x * width / scale, -d.y * height / scale)
end

local function HideMapPins(from)
    for i = from, mapShown do
        local p = mapPins[i]
        if p then HidePin(p) end
    end
end

-- Zooming only: same icons, new scale.
local function RescaleMapPins(canvas, scale, width, height)
    if mapShown == 0 then return end
    if mapState.scale == scale and mapState.width == width and mapState.height == height then return end
    mapState.scale, mapState.width, mapState.height = scale, width, height
    for i = 1, mapShown do
        local p = mapPins[i]
        local d = p and p.data
        if d then PlaceMapPin(p, d, canvas, scale, width, height) end
    end
end

-- Does nothing unless the world map is open.
local function RefreshWorldMap(force)
    if not active or not QD then return end
    -- Forgetting what was drawn makes the next refresh a full one, even if
    -- the map is closed right now and only opened later.
    if force then mapState.list = nil end
    local map = WorldMapFrame
    if type(map) ~= "table" or type(map.IsShown) ~= "function" or not map:IsShown() then return end
    mod:Safe(SetWorldMapHaze, map, Opt("hideHaze"))
    if type(map.GetCanvas) ~= "function" then return end
    local canvas = map:GetCanvas()
    if type(canvas) ~= "table" then return end

    local mapID, list = nil, EMPTY
    if Opt("map") and type(map.GetMapID) == "function" then
        mapID = map:GetMapID()
        if mapID ~= nil then list = QD:GetPins(mapID) end
        if type(list) ~= "table" then list = EMPTY end
    end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not (IsNumber(width) and IsNumber(height) and width > 0 and height > 0) then
        HideMapPins(1)
        mapShown = 0
        mapState.list = nil
        return
    end
    local scale = MapScale(canvas)
    if mapState.list == list and mapState.mapID == mapID then
        RescaleMapPins(canvas, scale, width, height)
        return
    end
    mapState.list, mapState.mapID = list, mapID
    mapState.scale, mapState.width, mapState.height = scale, width, height

    local size = IconSize("map")
    local big = size * TRACKED_SCALE
    local level = MapLevel(map)
    local all, set = showAll, showSet
    local n = 0
    for i = 1, #list do
        local d = list[i]
        if ValidPin(d) and (all or set[d.questID]) and (not d.extra or d == arrowPin) then
            n = n + 1
            local p = mapPins[n]
            if not p then
                p = CreatePin(canvas, "map")
                mapPins[n] = p
            end
            -- larger only among all quests; a filtered map draws every icon alike
            local isTracked = all and trackedID ~= nil and d.questID == trackedID
            local drawn = isTracked and big or size
            StylePin(p, d, drawn, drawn) -- tap area = the icon itself
            if level then p:SetFrameLevel((isTracked or d.kind == "turnin") and level + 1 or level) end
            PlaceMapPin(p, d, canvas, scale, width, height)
            ShowPin(p)
            if n >= MAP_MAX then break end
        end
    end
    HideMapPins(n + 1)
    mapShown = n
    if PE.debugOn then
        PE:Debug(KEY, "world map shows map " .. PE.Plain(mapID) .. ": " .. n .. " icons"
            .. (n >= MAP_MAX and (", " .. (CountShown(list) - n) .. " cut by the cap of " .. MAP_MAX) or ""))
    end
end

local function OnMapChanged()
    if active then RefreshWorldMap(false) end
end

local function OnMapShow()
    if active and PE.debugOn then PE:Debug(KEY, "world map opened") end
    OnMapChanged()
end

-- Runs every frame while the map is being zoomed or panned with the stick, so it is kept tiny.
local function OnMapScale()
    if not active or mapShown == 0 then return end
    local map = WorldMapFrame
    if type(map) ~= "table" or type(map.GetCanvas) ~= "function" then return end
    local canvas = map:GetCanvas()
    if type(canvas) ~= "table" then return end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not (IsNumber(width) and IsNumber(height) and width > 0 and height > 0) then return end
    RescaleMapPins(canvas, MapScale(canvas), width, height)
end

local function OnMapHide()
    if active and PE.debugOn then PE:Debug(KEY, "world map closed") end
    if label and label.view == "map" then HideLabel() end
end

-- Hooks cannot be removed again, so they are installed once and do nothing while the feature is off.
local function HookWorldMap()
    if mapHooked then return true end
    local map = WorldMapFrame
    if type(map) ~= "table" or type(map.GetCanvas) ~= "function" then return false end
    mapHooked = true
    if type(hooksecurefunc) == "function" then
        if type(map.OnMapChanged) == "function" then
            pcall(hooksecurefunc, map, "OnMapChanged", mapChangedHook)
        end
        if type(map.OnCanvasScaleChanged) == "function" then
            pcall(hooksecurefunc, map, "OnCanvasScaleChanged", mapScaleHook)
        end
    end
    if type(map.HookScript) == "function" then
        pcall(map.HookScript, map, "OnShow", mapShowHook)
        pcall(map.HookScript, map, "OnHide", mapHideHook)
    end
    return true
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

local function HideMiniPins()
    for i = 1, miniShown do
        local p = miniPins[i]
        if p then HidePin(p) end
    end
    miniShown = 0
end

local function StopTicker()
    if ticker and tickerOn then ticker:SetScript("OnUpdate", nil) end
    tickerOn = false
end

local function StartTicker()
    tickBusy = false
    acc = MINI_INTERVAL -- update on the very next frame
    if tickerOn then return end
    local mm = Minimap
    if type(mm) ~= "table" then return end
    -- A child of the minimap: it only ticks while the minimap is on screen.
    if not ticker then ticker = CreateFrame("Frame", nil, mm) end
    ticker:SetScript("OnUpdate", tickHandler)
    tickerOn = true
end

local function MinimapYards(zoom, indoors)
    local sizes = indoors and MINIMAP_YARDS.indoor or MINIMAP_YARDS.outdoor
    if not IsNumber(zoom) or zoom < 0 then zoom = 0 end
    return sizes[zoom] or sizes[#sizes]
end

local function ClearMinimap()
    HideMiniPins()
    StopTicker()
    miniList, miniMapID, miniW, miniH = EMPTY, nil, nil, nil
    last.x = nil
end

local miniRetries, miniRetryWaiting = 0, false
local RetryMinimapData -- set below

-- Chooses the pin list for the map the player is on and starts or stops the
-- update. The update only runs while this map has icons the "Show icons for"
-- filter lets through; the next zone, quest or focus change looks again.
local function RefreshMinimapData()
    if not active or not QD then return end
    last.x = nil -- forces the next update to redraw
    local mm = Minimap
    if not Opt("mini") or type(mm) ~= "table" or type(mm.GetWidth) ~= "function" then
        ClearMinimap()
        if PE.debugOn then DebugMini(Opt("mini") and "minimap icons stopped: no minimap" or "minimap icons stopped: option off") end
        return
    end
    local mapID = QD:GetPlayerPosition()
    if not mapID then
        ClearMinimap() -- not readable (loading screen, inside a dungeon)
        if PE.debugOn then DebugMini("minimap icons stopped: position not readable (loading screen or instance)") end
        -- Just after a loading screen the position can be a moment late and
        -- no zone or quest event may follow: look again, three times at most.
        if miniRetries < 3 and not miniRetryWaiting then
            miniRetries = miniRetries + 1
            miniRetryWaiting = true
            if PE.debugOn then PE:Debug(KEY, "minimap position retry " .. miniRetries .. " of 3") end
            mod:After(1, RetryMinimapData)
        end
        return
    end
    miniRetries = 0
    local list = QD:GetPins(mapID)
    local width, height = QD:GetMapWorldSize(mapID)
    if type(list) ~= "table" or not AnyShown(list) or not (IsNumber(width) and IsNumber(height)) then
        ClearMinimap()
        miniMapID = mapID
        if PE.debugOn then
            DebugMini("minimap icons stopped: " .. ((IsNumber(width) and IsNumber(height)) and "no icons on map "
                or "size not readable of map ") .. mapID)
        end
        return
    end
    miniList, miniMapID, miniW, miniH = list, mapID, width, height
    StartTicker()
    if PE.debugOn then DebugMini("minimap icons started on map " .. mapID) end
end

RetryMinimapData = function()
    miniRetryWaiting = false
    RefreshMinimapData()
end

local function UpdateMinimap()
    if not active or not QD or miniMapID == nil then return end
    local mm = Minimap
    local mapID, px, py = QD:GetPlayerPosition()
    if not mapID then
        if miniShown > 0 then HideMiniPins() end
        last.x = nil
        return
    end
    if mapID ~= miniMapID then
        RefreshMinimapData() -- walked onto another map before the zone event arrived
        return
    end

    local rotate = type(GetCVar) == "function" and GetCVar("rotateMinimap") == "1"
    local facing = 0
    if rotate then
        facing = QD:GetPlayerFacing()
        if not facing then
            if miniShown > 0 then HideMiniPins() end
            last.x = nil
            return
        end
    end
    local zoom = mm:GetZoom()
    local width = mm:GetWidth()
    local indoors = (type(IsIndoors) == "function" and IsIndoors()) and true or false
    if last.x == px and last.y == py and last.f == facing and last.z == zoom
       and last.w == width and last.i == indoors then
        return -- nothing moved
    end
    last.x, last.y, last.f, last.z, last.w, last.i = px, py, facing, zoom, width, indoors
    if not (IsNumber(width) and width > 0) then return end

    local yardsToUnits = width / MinimapYards(zoom, indoors)
    local size = IconSize("mini")
    local big = size * TRACKED_SCALE
    local hit = max(big, Px(MINI_HIT_PX))
    local edge = max(width / 2 - size * 0.4, 1)
    local edgeSq = edge * edge
    local s, c = sin(facing), cos(facing)
    local baseLevel = mm:GetFrameLevel()
    baseLevel = (IsNumber(baseLevel) and baseLevel or 0) + 5
    local list, worldW, worldH = miniList, miniW, miniH
    local all, set = showAll, showSet
    local n = 0

    for i = 1, #list do
        local d = list[i]
        if ValidPin(d) and (all or set[d.questID]) and (not d.extra or d == arrowPin) then
            local dx = (d.x - px) * worldW * yardsToUnits -- east is +x
            local dy = (py - d.y) * worldH * yardsToUnits -- north is +y
            if rotate then dx, dy = dx * c + dy * s, dy * c - dx * s end
            local distSq = dx * dx + dy * dy
            local alpha = 1
            local show = distSq <= edgeSq
            if not show and d.kind == "turnin" then
                -- keep hand-in spots on the rim so the direction is visible
                local k = edge / sqrt(distSq)
                dx, dy, alpha, show = dx * k, dy * k, 0.6, true
            end
            if show then
                n = n + 1
                local p = miniPins[n]
                if not p then
                    p = CreatePin(mm, "mini")
                    miniPins[n] = p
                end
                local isTracked = all and trackedID ~= nil and d.questID == trackedID
                StylePin(p, d, isTracked and big or size, hit)
                local level = (isTracked or d.kind == "turnin") and baseLevel + 1 or baseLevel
                if p.level ~= level then
                    p.level = level
                    p:SetFrameLevel(level)
                end
                if p.alpha ~= alpha then
                    p.alpha = alpha
                    p:SetAlpha(alpha)
                end
                p:SetPoint("CENTER", mm, "CENTER", dx, dy) -- replaces the one point it has
                ShowPin(p)
                if n >= MINI_MAX then break end
            end
        end
    end
    for i = n + 1, miniShown do
        local p = miniPins[i]
        if p then HidePin(p) end
    end
    miniShown = n
end

local function OnTick(_, elapsed)
    acc = acc + (tonumber(elapsed) or 0)
    if acc < MINI_INTERVAL then return end
    acc = 0
    if tickBusy then
        -- The last update stopped with an error (already in the error list).
        -- Stop instead of failing ten times a second; the next zone or quest
        -- change starts it again.
        StopTicker()
        HideMiniPins()
        if PE.debugOn then DebugMini("minimap icons stopped: an update failed") end
        return
    end
    tickBusy = true
    UpdateMinimap()
    tickBusy = false
end

---------------------------------------------------------------------------
-- Reacting to quest data and settings
---------------------------------------------------------------------------

local function OnDataChanged(reason)
    if not active or not QD then return end
    trackedID = QD:GetTrackedQuest()
    if PE.debugOn and reason == "tracked" then PE:Debug(KEY, "focused quest is now " .. (trackedID and PE.Plain(trackedID) or "none")) end
    local oldArrow = arrowPin
    arrowPin = QD:GetArrowPin()
    if reason == "arrow" then
        -- Only a surplus spot being shown or hidden changes what is drawn.
        if (type(oldArrow) == "table" and oldArrow.extra) or (type(arrowPin) == "table" and arrowPin.extra) then
            last.x = nil
            acc = MINI_INTERVAL
            RefreshWorldMap(true)
        end
        return
    end
    if reason ~= "tracked" and reason ~= "quests" then
        RefreshMinimapData() -- "zone": the filter cannot have changed
        RefreshWorldMap(false)
        return
    end
    -- The focus or Blizzard's tracker may have changed (the tracker only
    -- sends "quests"): the filter is rebuilt, and the engine may have put
    -- the minimap haze back.
    local filterChanged = RebuildFilter()
    ReapplyMinimapHaze()
    if reason == "tracked" and showAll and not filterChanged then
        -- All quests: only the larger icons move to another quest
        last.x = nil
        acc = MINI_INTERVAL
        RefreshWorldMap(true)
    else
        RefreshMinimapData() -- also starts or stops the minimap update
        RefreshWorldMap(filterChanged or reason == "tracked")
    end
end

-- Loading screens and new zones: the engine may have reset the minimap haze.
-- After a loading screen it is set once more a little later, in case the
-- engine resets it after the event.
local function OnWorldEvent(_, event)
    ReapplyMinimapHaze()
    if event == "PLAYER_ENTERING_WORLD" then mod:After(HAZE_AGAIN_SECONDS, ReapplyMinimapHaze) end
end

local function RefreshAll()
    if not active then return end
    RefreshMinimapData()
    RefreshWorldMap(true)
end

-- Called after a setting changed, from the panel or from /qd.
local function ApplyOption(key)
    if not active then return end
    if PE.debugOn then PE:Debug(KEY, "option " .. tostring(key) .. " = " .. tostring(Opt(key))) end
    if key == "hideHaze" then
        if Opt("hideHaze") then ZeroMinimapBlobs() end
        UpdateReloadPrompt()
        RefreshWorldMap(true) -- hides or restores the haze on the world map
    elseif key == "cluster" then
        if QD then
            QD.cluster = ClusterValue()
            clusterSet = true
            QD:RequestRebuild()
        end
    elseif key == "spots" then
        if QD then
            QD.spotLimit = SpotsValue()
            clusterSet = true
            QD:RequestRebuild()
        end
    elseif key == "show" then
        RebuildFilter()
        RefreshAll() -- forgets what the minimap and the world map last drew
    elseif key == "mini" then
        RefreshMinimapData()
    elseif key == "map" then
        RefreshWorldMap(true)
    else
        RefreshAll()
    end
end

---------------------------------------------------------------------------
-- On and off
---------------------------------------------------------------------------

local function OnAddonLoaded(_, _, name)
    if name == "Blizzard_WorldMap" and HookWorldMap() then
        mod:UnregisterEvent("ADDON_LOADED")
        RefreshWorldMap(true)
    end
end

local function OnEnable()
    active, blocked, tickBusy = false, nil, false
    mapState.list, mapState.mapID = nil, nil
    if PE.oldQuestDotsLoaded then
        blocked = OLD_ADDON_MESSAGE -- two copies would draw every icon twice
        if PE.debugOn then PE:Debug(KEY, "not drawing: the old QuestDots addon is loaded") end
        return
    end
    QD = PE.QuestData
    if type(QD) ~= "table" or type(QD.Acquire) ~= "function" then
        QD = nil
        blocked = "The quest data part of this addon did not load. See Errors."
        if PE.debugOn then PE:Debug(KEY, "not drawing: quest data did not load") end
        return
    end
    QD.cluster = ClusterValue()
    QD.spotLimit = SpotsValue()
    clusterSet = true
    local ok, reason = QD:Acquire(KEY)
    if not ok then
        blocked = (type(reason) == "string" and reason ~= "") and reason or "The QuestieDB addon could not be used."
        QD.cluster = DEFAULT_CLUSTER
        QD.spotLimit = 0
        clusterSet = false
        if PE.debugOn then PE:Debug(KEY, "not drawing: " .. blocked) end
        return
    end
    active = true
    -- 0.0.2 saved "focus" as the default; move those players to the new
    -- default once. "All quests", and any choice made after this, is kept.
    local opts = mod.opts
    if type(opts) == "table" and opts.showDefault ~= 2 then
        if opts.show == "focus" then opts.show = "tracked" end
        opts.showDefault = 2
    end
    QD:OnChanged(KEY, dataChanged)
    trackedID = QD:GetTrackedQuest()
    arrowPin = QD:GetArrowPin()
    RebuildFilter()
    if not HookWorldMap() then
        mod:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
    end
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", OnWorldEvent)
    mod:RegisterEvent("ZONE_CHANGED_NEW_AREA", OnWorldEvent)
    if Opt("hideHaze") then ZeroMinimapBlobs() end
    UpdateReloadPrompt()
    RefreshMinimapData()
    RefreshWorldMap(true)
end

local function HideEverything()
    HideLabel()
    for i = 1, #mapPins do
        HidePin(mapPins[i])
        mapPins[i].data = nil
    end
    mapShown = 0
    for i = 1, #miniPins do
        HidePin(miniPins[i])
        miniPins[i].data = nil
    end
    miniShown = 0
    miniList, miniMapID, miniW, miniH = EMPTY, nil, nil, nil
    last.x = nil
    mapState.list, mapState.mapID = nil, nil
end

local function ReleaseData()
    local data = QD or PE.QuestData
    QD = nil
    if type(data) ~= "table" then return end
    if type(data.OnChanged) == "function" then data:OnChanged(KEY, nil) end
    if type(data.Release) == "function" then data:Release(KEY) end
    if clusterSet then
        clusterSet = false
        data.cluster = DEFAULT_CLUSTER
        data.spotLimit = 0
        -- another feature may still be using the data: give it the normal merging back
        if type(data.RequestRebuild) == "function" then data:RequestRebuild() end
    end
end

-- Also runs as a rollback after a half-finished OnEnable, so every step stands alone.
local function OnDisable()
    miniRetries, miniRetryWaiting = 0, false -- a waiting retry is dropped with the switch-off
    active, blocked, trackedID, arrowPin = false, nil, nil, nil
    dbgMini = nil
    mod:Safe(StopTicker)
    mod:Safe(HideEverything)
    mod:Safe(RestoreWorldMapHaze)
    mod:Safe(ReleaseData)
    mod:Safe(UpdateReloadPrompt)
end

local function Status()
    if PE.oldQuestDotsLoaded then return OLD_ADDON_MESSAGE end
    return blocked
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local ON_OFF = { { value = true, label = "On" }, { value = false, label = "Off" } }

local function OptionChanged(key)
    return function() ApplyOption(key) end
end

mod = PE:RegisterModule({
    key = KEY,
    label = "Quest icons",
    desc = "Shows where quest objectives are on the map and minimap.",
    order = 10,
    requiresQuestieDB = true,
    defaults = DEFAULTS,
    options = {
        { key = "show", label = "Show icons for",
          choices = { { value = "tracked", label = "Tracked quests" }, { value = "focus", label = "Focused quest" },
                      { value = "all", label = "All quests" } },
          OnChange = OptionChanged("show") },
        -- One choice for the two saved switches `map` and `mini` (0.6.0). Both
        -- off (only from /qd or an old file) marks no button.
        { label = "Icons on",
          choices = { { value = "both", label = "Map and minimap" }, { value = "map", label = "Map only" },
                      { value = "mini", label = "Minimap only" } },
          get = function(m)
              local o = m.opts
              if type(o) ~= "table" then return nil end
              if o.map ~= false and o.mini ~= false then return "both" end
              if o.map ~= false then return "map" end
              if o.mini ~= false then return "mini" end
              return nil
          end,
          set = function(m, value)
              m.opts.map = value ~= "mini"
              m.opts.mini = value ~= "map"
          end,
          OnChange = function()
              ApplyOption("map")
              ApplyOption("mini")
          end },
        { key = "size", label = "Icon size",
          choices = { { value = "xsmall", label = "Extra small" }, { value = "small", label = "Small" },
                      { value = "medium", label = "Medium" }, { value = "large", label = "Large" } },
          OnChange = OptionChanged("size") },
        -- Number controls (0.7.0). The saved values are the same as before:
        -- cluster in % of the map (0 = off), spots 0 = all.
        { key = "cluster", label = "Merge icons closer than",
          number = { min = 0, max = MAX_CLUSTER, default = DEFAULT_CLUSTER, unit = "of map", suffix = "%", offLabel = "Off" },
          OnChange = OptionChanged("cluster") },
        { key = "spots", label = "Spots per objective",
          number = { min = 1, max = MAX_SPOTS, default = DEFAULT_SPOTS, unit = "spots", all = 0, allLabel = "All" },
          OnChange = OptionChanged("spots") },
        { key = "hideHaze", label = "Hide Blue Quest Haze", choices = ON_OFF, toggle = true, OnChange = OptionChanged("hideHaze") },
        -- Opens the Quest Icon Key page of the settings (Back returns to the main list).
        { label = "Quest Icon Key", action = function() PE:OpenSettings("key") end },
    },
    status = Status,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})

if type(mod) ~= "table" or type(mod.Wrap) ~= "function" then return end

pinClick = mod:Wrap(OnPinClick)
tickHandler = mod:Wrap(OnTick)
mapChangedHook = mod:Wrap(OnMapChanged)
mapScaleHook = mod:Wrap(OnMapScale)
mapShowHook = mod:Wrap(OnMapShow)
mapHideHook = mod:Wrap(OnMapHide)
dataChanged = mod:Wrap(OnDataChanged)

-- The icon sizes are fixed screen sizes: redraw when the game's UI scale changes.
if type(PE.UI) == "table" and type(PE.UI.OnMetricsChanged) == "function" then
    PE.UI:OnMetricsChanged(mod:Wrap(RefreshAll))
end

---------------------------------------------------------------------------
-- /qd (backup for when a keyboard is to hand; the panel does the same)
---------------------------------------------------------------------------

local TOGGLES = {
    map = { key = "map", name = "Map icons" },
    mini = { key = "mini", name = "Minimap icons" },
    haze = { key = "hideHaze", name = "Hide Blue Quest Haze" },
}
local CLUSTER_WORDS = { off = 0, normal = 2, more = 5 }
local SPOTS_WORDS = { all = 0 }
local SHOW_WORDS = { focus = "Focused quest", tracked = "Tracked quests", all = "All quests" }
local USAGE = "/qd show tracked (or focus, all), /qd map, /qd mini, /qd haze, /qd size small (or xsmall, medium, large), /qd cluster 2 (0 to 10, 0 is off), /qd spots all (or 1 to 20)"

-- "/qd spots 7": a whole number from 1 to MAX_SPOTS, else nil.
local function SpotsNumber(text)
    local n = tonumber(text)
    if n and n == floor(n) and n >= 1 and n <= MAX_SPOTS then return n end
    return nil
end

local function SlashCommand(msg)
    local opts = mod.opts
    if type(opts) ~= "table" or not mod:IsEnabled() then
        PE:Print(TURN_ON_MESSAGE)
        return
    end
    if not active then
        PE:Print(Status() or TURN_ON_MESSAGE)
        return
    end
    msg = type(msg) == "string" and msg:lower() or ""
    local cmd, value = msg:match("^%s*(%S+)%s*(%S*)")
    local toggle = cmd and TOGGLES[cmd]
    local changed
    if toggle then
        opts[toggle.key] = not Opt(toggle.key)
        changed = toggle.key
        PE:Print(toggle.name .. ": " .. (opts[toggle.key] and "on" or "off") .. ".")
    elseif cmd == "blizz" then
        PE:Print("Hiding Blizzard's quest pins was removed.")
        return
    elseif cmd == "show" and SHOW_WORDS[value] then
        opts.show = value
        changed = "show"
        PE:Print("Show icons for: " .. SHOW_WORDS[value] .. ".")
    elseif cmd == "size" and MAP_PX[value] then
        opts.size = value
        changed = "size"
        PE:Print("Icon size: " .. value .. ".")
    elseif cmd == "cluster" and (CLUSTER_WORDS[value] or tonumber(value)) then
        local number = CLUSTER_WORDS[value] or tonumber(value)
        if number ~= number then number = DEFAULT_CLUSTER end
        opts.cluster = floor(max(0, min(MAX_CLUSTER, number)))
        changed = "cluster"
        PE:Print("Merge icons closer than: " .. (opts.cluster == 0 and "off" or (tostring(opts.cluster) .. "%")) .. ".")
    elseif cmd == "spots" and (SPOTS_WORDS[value] or SpotsNumber(value)) then
        opts.spots = SPOTS_WORDS[value] or SpotsNumber(value)
        changed = "spots"
        PE:Print("Spots per objective: " .. (opts.spots == 0 and "all" or tostring(opts.spots)) .. ".")
    else
        PE:Print(USAGE)
        return
    end
    ApplyOption(changed)
    mod:RefreshPanel()
end

-- Our own key, so an old QuestDots that is still installed keeps its own entry.
if type(SlashCmdList) == "table" then
    SLASH_POCKETESSENTIALSQD1 = "/qd"
    SlashCmdList["POCKETESSENTIALSQD"] = mod:Wrap(SlashCommand)
end
