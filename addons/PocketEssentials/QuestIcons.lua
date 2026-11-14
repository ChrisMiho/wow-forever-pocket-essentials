-- Pocket Essentials: quest icons (module "questIcons").
-- Objective icons on the world map and the minimap for the quests in the log.
-- Where things are comes from PE.QuestData (QuestData.lua); this file only
-- draws. Ported from the old standalone QuestDots addon.
--
-- How it behaves on a touch screen (there is no hover):
--   * Tap an icon: that quest becomes the tracked quest and a short text box
--     says what the icon is. The box goes away by itself after a few seconds,
--     when another icon is tapped, when the same icon is tapped again, or when
--     the map is closed. The box is our own frame in the addon's large font,
--     not GameTooltip: Blizzard's quest-area pin rewrites GameTooltip every
--     frame while the pointer rests inside a quest area, and a tap leaves the
--     pointer exactly there.
--   * Icons are drawn larger than the old addon drew them and the area that
--     accepts a tap is larger still. A tap always goes to the icon whose
--     centre is nearest the finger, so the larger tap areas cannot pick the
--     wrong neighbour.
--
-- Nothing here touches protected frames, so nothing needs to wait for combat
-- to end. Blizzard's own pins are only ever changed with SetAlpha and
-- EnableMouse (no fields are written on them), and every pin we changed is
-- remembered so that switching the feature off puts it back.
local ADDON_NAME, PE = ...

if type(PE) ~= "table" or type(PE.RegisterModule) ~= "function" then return end

local type, pairs, tonumber, tostring, pcall, next = type, pairs, tonumber, tostring, pcall, next
local setmetatable = setmetatable
local max, min, sqrt, sin, cos = math.max, math.min, math.sqrt, math.sin, math.cos

local KEY = "questIcons"

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local DEFAULTS = {
    map = true,            -- icons on the world map
    mini = true,           -- icons on the minimap
    hideHaze = true,       -- hide Blizzard's blue quest areas (map and minimap)
    hideBlizzPins = false, -- also hide Blizzard's own numbered quest pins on the world map
    size = "medium",       -- "small" | "medium" | "large" (or a number typed with /qd size)
    cluster = 2,           -- merge spawns closer than this many % of the map; 0 = off
}

-- Icon sizes in pixels on a 720p screen (a 6 inch 720p screen has about ten
-- pixels to the millimetre, so "medium" is roughly 3 mm on the map).
local MAP_PX = { small = 22, medium = 28, large = 36 }
local MINI_PX = { small = 14, medium = 18, large = 22 }
-- The tap area of an icon is at least this big, whatever the icon size.
local MAP_HIT_PX = 44
local MINI_HIT_PX = 32
-- Icons of the tracked quest are drawn this much larger.
local TRACKED_SCALE = 1.25
-- Most icons drawn at once. The world map keeps one frame per icon, and all
-- of them are moved whenever the map is zoomed; the minimap moves its icons
-- ten times a second while walking. Above these numbers the maps are too
-- crowded to read anyway. On the world map the tracked quest goes first.
local MAP_MAX = 300
local MINI_MAX = 40
local MINI_INTERVAL = 0.1 -- seconds between minimap updates
local LABEL_SECONDS = 5
local DEFAULT_CLUSTER = 2

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
    turnin = { turnin = true },
}
-- The yellow "?" for handing a quest in: an atlas if this client has it,
-- otherwise the gossip window's icon file.
local TURNIN_ATLAS = "QuestTurnin"
local TURNIN_FILE = "Interface\\GossipFrame\\ActiveQuestIcon"

local KIND_LABEL = { slay = "Kill", loot = "Loot", object = "Use", event = "Explore", turnin = "Turn in" }

local BLOB_TEMPLATE = "QuestBlobPinTemplate"   -- Blizzard_SharedMapDataProviders/QuestBlobDataProvider.xml
local QUEST_PIN_TEMPLATE = "QuestPinTemplate"  -- Blizzard_SharedMapDataProviders/QuestDataProvider.xml

-- Minimap diameter in yards for each zoom level. These numbers are not in
-- Blizzard's interface code; they are the ones the HereBeDragons library uses.
local MINIMAP_YARDS = {
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}

-- Minimap blob settings we set to zero to hide the haze. The game has no way
-- to read their normal values back, so only a reload restores them.
local BLOB_SETTERS = {
    "SetQuestBlobInsideAlpha", "SetQuestBlobOutsideAlpha", "SetQuestBlobRingAlpha",
    "SetTaskBlobInsideAlpha", "SetTaskBlobOutsideAlpha", "SetTaskBlobRingAlpha",
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local mod                  -- set by RegisterModule near the end of the file
local QD                   -- PE.QuestData while enabled
local active = false       -- true while the feature is on and allowed to draw
local blocked              -- plain-language reason nothing is drawn, or nil
local trackedID            -- quest whose icons are drawn larger
local turninAtlas, turninChecked
local clusterSet = false   -- we changed PE.QuestData.cluster
local blobsZeroed = false  -- the minimap haze was hidden this session

local EMPTY = {}

local mapPins, mapShown = {}, 0
local mapState = {}        -- what the world map icons were last drawn from
local drawList = {}        -- scratch: the pins chosen for the world map
local mapHooked, providerHooked = false, false

local miniPins, miniShown = {}, 0
local miniList, miniMapID, miniW, miniH = EMPTY, nil, nil, nil
local last = {}            -- last player position/facing/zoom, to skip work when nothing moved
local ticker, tickerOn, tickBusy, acc = nil, false, false, 0
local miniRetries = 0

local label, labelTried, labelSerial = nil, false, 0

-- Blizzard pins we changed: [pin] = the alpha it had before.
local hazeTouched = setmetatable({}, { __mode = "k" })
local questTouched = setmetatable({}, { __mode = "k" })

-- Script handlers and hooks, wrapped once the module is registered.
local pinClick, pinHide, tickHandler, mapChangedHook, mapScaleHook, mapShowHook, providerHook, dataChanged

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
    local choice = Opt("size")
    local px
    if IsNumber(choice) then
        px = (view == "map") and choice or max(10, choice - 6)
    else
        local sizes = (view == "map") and MAP_PX or MINI_PX
        px = sizes[choice] or sizes.medium
    end
    return Px(px)
end

local function ClusterValue()
    local value = tonumber(Opt("cluster")) or DEFAULT_CLUSTER
    if value ~= value or value < 0 then value = 0 end
    if value > 20 then value = 20 end
    return value
end

local function Escape(text)
    return (tostring(text):gsub("|", "||"))
end

local function FindTurninAtlas()
    if turninChecked then return end
    turninChecked = true
    local getInfo = C_Texture and C_Texture.GetAtlasInfo
    if type(getInfo) ~= "function" then return end
    local ok, info = pcall(getInfo, TURNIN_ATLAS)
    if ok and info ~= nil then turninAtlas = TURNIN_ATLAS end
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
    n = n + 1
    lines[n] = "|cff9e9e9eTracking this quest|r"
    return table.concat(lines, "\n"), n
end

-- owner: the icon the box sits above (world map), or nil to sit under the minimap.
local function ShowLabel(owner, d, view)
    local f = EnsureLabel()
    if not f then return end
    local str, lineCount = LabelText(d)
    local pad, border, gap = Px(10), max(Px(2), 1), Px(6)
    local maxWidth, minWidth = Px(440), Px(120)

    local text = f.text
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
    text:SetWidth(maxWidth)
    text:SetText(str)
    local width
    if type(text.GetStringWidth) == "function" then
        local ok, value = pcall(text.GetStringWidth, text)
        if ok and IsNumber(value) and value > 1 then width = value + 2 end
    end
    width = min(maxWidth, max(minWidth, width or maxWidth))
    text:SetWidth(width)
    local height
    local lineHeight = Px(20) * 1.25
    if type(text.GetStringHeight) == "function" then
        local ok, value = pcall(text.GetStringHeight, text)
        if ok and IsNumber(value) and value >= lineHeight * 0.5 then height = value end
    end
    height = height or lineCount * lineHeight

    f:SetSize(width + pad * 2, height + pad * 2)
    f.fill:ClearAllPoints()
    f.fill:SetPoint("TOPLEFT", f, "TOPLEFT", border, -border)
    f.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -border, border)
    f:ClearAllPoints()
    if view == "mini" and Minimap then
        f:SetPoint("TOP", Minimap, "BOTTOM", 0, -gap)
    elseif owner then
        f:SetPoint("BOTTOM", owner, "TOP", 0, gap)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    f.owner, f.data, f.view = (view == "map") and owner or nil, d, view
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
    f:SetScript("OnHide", pinHide)
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
    end
end

-- size and hit are in the frame's own units.
local function StylePin(f, d, size, hit)
    if f.data ~= d then
        if label and label.owner == f then HideLabel() end
        f.data = d
    end
    local kind = STYLE[d.kind] and d.kind or "event"
    if f.kind ~= kind then
        f.kind = kind
        local style, tex = STYLE[kind], f.tex
        if style.turnin then
            tex:SetVertexColor(1, 1, 1)
            if turninAtlas then
                tex:SetAtlas(turninAtlas)
            else
                tex:SetTexture(TURNIN_FILE)
                tex:SetTexCoord(0, 1, 0, 1)
            end
        else
            tex:SetTexture(style.tex)
            tex:SetTexCoord(0, 1, 0, 1) -- an atlas used earlier leaves its own coordinates behind
            tex:SetVertexColor(style.color[1], style.color[2], style.color[3])
        end
    end
    if f.size ~= size or f.hit ~= hit then
        f.size, f.hit = size, hit
        f:SetSize(size, size)
        local inset = (hit > size) and -(hit - size) / 2 or 0
        f:SetHitRectInsets(inset, inset, inset, inset)
    end
end

-- The shown icon whose centre is nearest the pointer; `clicked` if that cannot be told.
local function NearestPin(pins, count, clicked)
    if type(GetCursorPosition) ~= "function" then return clicked end
    local cx, cy = GetCursorPosition()
    local scale = clicked:GetEffectiveScale()
    if not (IsNumber(cx) and IsNumber(cy) and IsNumber(scale) and scale > 0) then return clicked end
    cx, cy = cx / scale, cy / scale
    local best, bestDist = clicked, nil
    for i = 1, count do
        local p = pins[i]
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
    local view = self.view
    local pins, count = mapPins, mapShown
    if view == "mini" then pins, count = miniPins, miniShown end
    local target = NearestPin(pins, count, self)
    local d = target and target.data
    if type(d) ~= "table" then return end

    if label and label.data == d and label:IsShown() then
        HideLabel() -- a second tap on the same icon puts the text away
        return
    end
    HideLabel()
    -- This redraws the icons straight away (the "tracked" callback), so the
    -- tapped icon may now live in a different frame.
    QD:SetTrackedQuest(d.questID)
    if not active then return end
    local owner
    if view == "map" then
        for i = 1, mapShown do
            if mapPins[i].data == d then
                owner = mapPins[i]
                break
            end
        end
        if not owner then return end
    end
    ShowLabel(owner, d, view)
end

local function OnPinHide(self)
    if label and label.owner == self then HideLabel() end
end

---------------------------------------------------------------------------
-- Blizzard's own quest areas and quest pins on the world map
---------------------------------------------------------------------------

local function ForPins(map, template, fn)
    if type(map.EnumeratePinsByTemplate) ~= "function" then return end
    local ok, iter, state, ctrl = pcall(map.EnumeratePinsByTemplate, map, template)
    if not ok or type(iter) ~= "function" then return end
    for pin in iter, state, ctrl do
        if type(pin) == "table" then fn(pin) end
    end
end

local function Remember(touched, pin)
    if touched[pin] == nil then
        local alpha = 1
        if type(pin.GetAlpha) == "function" then
            local ok, value = pcall(pin.GetAlpha, pin)
            if ok and IsNumber(value) then alpha = value end
        end
        touched[pin] = alpha
    end
end

local function HideHazePin(pin)
    if type(pin.SetAlpha) ~= "function" then return end
    Remember(hazeTouched, pin)
    pin:SetAlpha(0)
end

local function HideQuestPin(pin)
    if type(pin.SetAlpha) ~= "function" then return end
    Remember(questTouched, pin)
    pin:SetAlpha(0)
    if type(pin.EnableMouse) == "function" then pin:EnableMouse(false) end
end

-- Puts back every pin in `touched`, including ones Blizzard has put away in
-- its pool for later (those would otherwise come back invisible).
local function Restore(touched, mouse)
    for pin, alpha in pairs(touched) do
        touched[pin] = nil
        if type(pin) == "table" then
            if type(pin.SetAlpha) == "function" then pcall(pin.SetAlpha, pin, alpha) end
            if mouse and type(pin.EnableMouse) == "function" then pcall(pin.EnableMouse, pin, true) end
        end
    end
end

-- Blizzard takes its quest pins down and puts them up again on every quest
-- log update. Hooking that one refresh lets us hide them again in the same
-- frame, so they never flash.
local function HookQuestProvider(map)
    if providerHooked then return end
    local providers = map.dataProviders
    if type(providers) ~= "table" or type(hooksecurefunc) ~= "function" then return end
    for provider in pairs(providers) do
        if type(provider) == "table" and type(provider.GetPinTemplate) == "function"
           and type(provider.RefreshAllData) == "function" then
            local ok, template = pcall(provider.GetPinTemplate, provider)
            if ok and template == QUEST_PIN_TEMPLATE then
                providerHooked = true
                pcall(hooksecurefunc, provider, "RefreshAllData", providerHook)
                return
            end
        end
    end
end

local function SuppressBlizzard(map)
    if active and Opt("hideHaze") then
        ForPins(map, BLOB_TEMPLATE, HideHazePin)
    elseif next(hazeTouched) ~= nil then
        Restore(hazeTouched, false)
    end
    if active and Opt("hideBlizzPins") then
        HookQuestProvider(map)
        ForPins(map, QUEST_PIN_TEMPLATE, HideQuestPin)
    elseif next(questTouched) ~= nil then
        Restore(questTouched, true)
    end
end

local function RestoreBlizzard()
    Restore(hazeTouched, false)
    Restore(questTouched, true)
end

local function ZeroMinimapBlobs()
    local mm = Minimap
    if type(mm) ~= "table" then return end
    for i = 1, #BLOB_SETTERS do
        local setter = mm[BLOB_SETTERS[i]]
        if type(setter) == "function" and pcall(setter, mm, 0) then blobsZeroed = true end
    end
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

-- The scale that makes an icon the same size on screen whatever the map zoom.
local function MapScale(map, canvas)
    local canvasScale = canvas:GetEffectiveScale()
    local uiScale = UIParent and UIParent:GetEffectiveScale()
    local scale
    if IsNumber(canvasScale) and canvasScale > 0.0001 and IsNumber(uiScale) and uiScale > 0 then
        scale = uiScale / canvasScale
    elseif type(map.GetCanvasScale) == "function" then
        local zoom = map:GetCanvasScale()
        if IsNumber(zoom) and zoom > 0.0001 then scale = 1 / zoom end
    end
    if not scale or scale <= 0 then scale = 1 end
    return scale
end

-- Just under Blizzard's own quest pins, the player arrow and party members;
-- above everything else on the map.
local function MapLevel(map, canvas)
    if type(map.GetPinFrameLevelsManager) == "function" then
        local ok, manager = pcall(map.GetPinFrameLevelsManager, map)
        if ok and type(manager) == "table" and type(manager.GetValidFrameLevel) == "function" then
            local okPing, ping = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_QUEST_PING")
            local okBase, base = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_DEFAULT")
            if okPing and okBase and IsNumber(ping) and IsNumber(base) and ping > base then return ping end
            local okTop, top = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_TOPMOST")
            if okTop and IsNumber(top) and top > 0 then return top end
        end
    end
    local level = canvas:GetFrameLevel()
    return (IsNumber(level) and level or 0) + 3000
end

local function PlaceMapPin(p, d, canvas, scale, width, height)
    p:SetScale(scale)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", d.x * width / scale, -d.y * height / scale)
end

local function ValidPin(d)
    return type(d) == "table" and IsNumber(d.x) and IsNumber(d.y)
end

-- Fills drawList with at most `cap` pins. When there are too many, the tracked quest goes first.
local function BuildDrawList(list, cap)
    local n, total = 0, #list
    local first = (total > cap) and trackedID or nil
    if first then
        for i = 1, total do
            local d = list[i]
            if ValidPin(d) and d.questID == first then
                n = n + 1
                drawList[n] = d
                if n >= cap then break end
            end
        end
    end
    if n < cap then
        for i = 1, total do
            local d = list[i]
            if ValidPin(d) and (first == nil or d.questID ~= first) then
                n = n + 1
                drawList[n] = d
                if n >= cap then break end
            end
        end
    end
    for i = #drawList, n + 1, -1 do drawList[i] = nil end
    return n
end

local function HideMapPins(from)
    for i = from, mapShown do
        local p = mapPins[i]
        if p then HidePin(p) end
    end
    if from <= mapShown then mapShown = from - 1 end
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
    mod:Safe(SuppressBlizzard, map)
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
        mapState.list = nil
        return
    end
    local scale = MapScale(map, canvas)
    if mapState.list == list and mapState.mapID == mapID then
        RescaleMapPins(canvas, scale, width, height)
        return
    end
    mapState.list, mapState.mapID = list, mapID
    mapState.scale, mapState.width, mapState.height = scale, width, height

    local n = BuildDrawList(list, MAP_MAX)
    if n > 0 then
        local size = IconSize("map")
        local big = size * TRACKED_SCALE
        local hit = max(big, Px(MAP_HIT_PX))
        local level = MapLevel(map, canvas)
        for i = 1, n do
            local d = drawList[i]
            local p = mapPins[i]
            if not p then
                p = CreatePin(canvas, "map")
                mapPins[i] = p
            end
            local isTracked = trackedID ~= nil and d.questID == trackedID
            StylePin(p, d, isTracked and big or size, hit)
            p:SetFrameLevel((isTracked or d.kind == "turnin") and level + 1 or level)
            PlaceMapPin(p, d, canvas, scale, width, height)
            ShowPin(p)
        end
    end
    HideMapPins(n + 1)
    mapShown = n
end

local function OnMapChanged()
    if active then RefreshWorldMap(false) end
end

local function OnMapShow()
    if active then RefreshWorldMap(false) end
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
    RescaleMapPins(canvas, MapScale(map, canvas), width, height)
end

local function OnProviderRefresh()
    if not active or not Opt("hideBlizzPins") then return end
    local map = WorldMapFrame
    if type(map) == "table" then ForPins(map, QUEST_PIN_TEMPLATE, HideQuestPin) end
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

local RefreshMinimapData

local function RetryMinimap()
    if active and miniMapID == nil then RefreshMinimapData() end
end

-- Chooses the pin list for the map the player is on and starts or stops the
-- update. The update only runs while there is something to draw.
RefreshMinimapData = function()
    if not active or not QD then return end
    last.x = nil -- forces the next update to redraw
    local mm = Minimap
    if not Opt("mini") or type(mm) ~= "table" or type(mm.GetWidth) ~= "function" then
        ClearMinimap()
        return
    end
    local mapID = QD:GetPlayerPosition()
    if not mapID then
        -- Not readable right now (loading screen, inside a dungeon). Look
        -- again a few times, then wait for the next zone or quest change.
        ClearMinimap()
        if miniRetries < 5 then
            miniRetries = miniRetries + 1
            mod:After(2, RetryMinimap)
        end
        return
    end
    miniRetries = 0
    local list = QD:GetPins(mapID)
    local width, height = QD:GetMapWorldSize(mapID)
    if type(list) ~= "table" or #list == 0 or not (IsNumber(width) and IsNumber(height)) then
        ClearMinimap()
        miniMapID = mapID
        return
    end
    miniList, miniMapID, miniW, miniH = list, mapID, width, height
    StartTicker()
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
    local n = 0

    for i = 1, #list do
        local d = list[i]
        if ValidPin(d) then
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
                local isTracked = trackedID ~= nil and d.questID == trackedID
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
                p:ClearAllPoints()
                p:SetPoint("CENTER", mm, "CENTER", dx, dy)
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
    if reason == "tracked" then
        last.x = nil
        acc = MINI_INTERVAL
        RefreshWorldMap(true)
    else
        miniRetries = 0
        RefreshMinimapData()
        RefreshWorldMap(false)
    end
end

local function RefreshAll()
    if not active then return end
    miniRetries = 0
    RefreshMinimapData()
    RefreshWorldMap(true)
end

local function ApplyHaze()
    if not active then return end
    if Opt("hideHaze") then
        ZeroMinimapBlobs()
    elseif blobsZeroed then
        mod:RequestReload(RELOAD_REASON)
    end
    RefreshWorldMap(true) -- hides or restores the haze on the world map
end

local function ApplyCluster()
    if not active or not QD then return end
    QD.cluster = ClusterValue()
    clusterSet = true
    QD:RequestRebuild()
end

-- Called after a setting changed, from the panel or from /qd.
local function ApplyOption(key)
    if not active then return end
    if key == "hideHaze" then
        ApplyHaze()
    elseif key == "cluster" then
        ApplyCluster()
    elseif key == "mini" then
        miniRetries = 0
        RefreshMinimapData()
    elseif key == "map" or key == "hideBlizzPins" then
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
    active, blocked = false, nil
    miniRetries, tickBusy = 0, false
    mapState.list, mapState.mapID = nil, nil
    if PE.oldQuestDotsLoaded then
        blocked = OLD_ADDON_MESSAGE -- two copies would draw every icon twice
        return
    end
    QD = PE.QuestData
    if type(QD) ~= "table" or type(QD.Acquire) ~= "function" then
        QD = nil
        blocked = "The quest data part of this addon did not load. See Errors."
        return
    end
    QD.cluster = ClusterValue()
    clusterSet = true
    local ok, reason = QD:Acquire(KEY)
    if not ok then
        blocked = (type(reason) == "string" and reason ~= "") and reason or "The QuestieDB addon could not be used."
        QD.cluster = DEFAULT_CLUSTER
        clusterSet = false
        return
    end
    active = true
    QD:OnChanged(KEY, dataChanged)
    trackedID = QD:GetTrackedQuest()
    FindTurninAtlas()
    if not HookWorldMap() then
        mod:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
    end
    if Opt("hideHaze") then ZeroMinimapBlobs() end
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
    for i = #drawList, 1, -1 do drawList[i] = nil end
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
        -- another feature may still be using the data: give it the normal merging back
        if type(data.RequestRebuild) == "function" then data:RequestRebuild() end
    end
end

-- Also runs as a rollback after a half-finished OnEnable, so every step stands alone.
local function OnDisable()
    active, blocked, trackedID = false, nil, nil
    mod:Safe(StopTicker)
    mod:Safe(HideEverything)
    mod:Safe(RestoreBlizzard)
    mod:Safe(ReleaseData)
    if blobsZeroed then mod:RequestReload(RELOAD_REASON) end
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
        { key = "map", label = "Map icons", choices = ON_OFF, OnChange = OptionChanged("map") },
        { key = "mini", label = "Minimap icons", choices = ON_OFF, OnChange = OptionChanged("mini") },
        { key = "hideHaze", label = "Hide blue haze", choices = ON_OFF, OnChange = OptionChanged("hideHaze") },
        { key = "hideBlizzPins", label = "Hide Blizzard's quest pins", choices = ON_OFF, OnChange = OptionChanged("hideBlizzPins") },
        { key = "size", label = "Icon size",
          choices = { { value = "small", label = "Small" }, { value = "medium", label = "Medium" }, { value = "large", label = "Large" } },
          OnChange = OptionChanged("size") },
        { key = "cluster", label = "Merge nearby icons",
          choices = { { value = 0, label = "Off" }, { value = 2, label = "Normal" }, { value = 5, label = "More" } },
          OnChange = OptionChanged("cluster") },
    },
    status = Status,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})

if type(mod) ~= "table" or type(mod.Wrap) ~= "function" then return end

pinClick = mod:Wrap(OnPinClick)
pinHide = mod:Wrap(OnPinHide)
tickHandler = mod:Wrap(OnTick)
mapChangedHook = mod:Wrap(OnMapChanged)
mapScaleHook = mod:Wrap(OnMapScale)
mapShowHook = mod:Wrap(OnMapShow)
providerHook = mod:Wrap(OnProviderRefresh)
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
    haze = { key = "hideHaze", name = "Hide blue haze" },
    blizz = { key = "hideBlizzPins", name = "Hide Blizzard's quest pins" },
}
local CLUSTER_WORDS = { off = 0, normal = 2, more = 5 }
local USAGE = "/qd map, /qd mini, /qd haze, /qd blizz, /qd size small (or medium, large, or a number), /qd cluster 2 (0 is off)"

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
    elseif cmd == "size" and value ~= "" then
        local number = tonumber(value)
        if MAP_PX[value] then
            opts.size = value
        elseif number and number == number then
            opts.size = max(12, min(64, number))
        else
            PE:Print(USAGE)
            return
        end
        changed = "size"
        PE:Print("Icon size: " .. tostring(opts.size) .. ".")
    elseif cmd == "cluster" and value ~= "" then
        local number = CLUSTER_WORDS[value] or tonumber(value)
        if not number or number ~= number then
            PE:Print(USAGE)
            return
        end
        opts.cluster = max(0, min(20, number))
        changed = "cluster"
        PE:Print("Merge nearby icons: " .. (opts.cluster == 0 and "off" or tostring(opts.cluster)) .. ".")
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
