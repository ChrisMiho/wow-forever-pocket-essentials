local ADDON_NAME, PE = ...

-- Map look (0.19.0, spec 2026-11-25-0.19.0-square-map.md): the square map of the Controller
-- layout. ControllerLayout.lua holds the numbers and the "Map look" row; this file changes the
-- map itself while that row reads "Square, bigger" and the layout is placed:
--
--   * the map is given a plain white square as its mask, and given it again after each of
--     the game's redraws;
--   * the map's frame is lowered inside its Edit Mode piece, so the map's bottom sits 5 up;
--   * a black edge 1 unit wide round it, and a faint light line just inside;
--   * the place name, the clock and the coordinates drawn inside the map;
--   * the game's strip under the map (the place name button and the clock on it) hidden.
--
-- Round, or the layout off, gives all of it back. Nothing here is made, registered or
-- ticking until the first Square placement, and nothing listens or ticks after a put-back.
--
--   PE.MapLook:Place(opts, redraw)  places for opts.mapLook (1: Square; anything else puts
--                                   everything back). redraw: the game has just redrawn the
--                                   map. Out of a fight only (held until it ends otherwise).
--                                   Calling it again with nothing changed changes nothing.
--   PE.MapLook:Restore()            puts everything back. Out of a fight only.
--   PE.MapLook:IsSquare()           true only while the square mask is on the map
--   PE.MapLook:Status()             a line for the settings card when the game refused the
--                                   square mask, else nil
--   PE.MapLook:SnapshotPieces()     { { name, frame, flags }, ... } for the snapshot; empty
--                                   while Round
--   PE.MapLook:OnChange(fn)         fn() is called whenever IsSquare changes
--
-- Calls into the game (paths under Interface/AddOns/ of Gethe/wow-ui-source, branch forever,
-- 1.60.1 (71091); M/ is Blizzard_Minimap/). Only a frame's own engine methods are called,
-- each through pcall; no function Blizzard wrote in Lua is called, and no field is written on
-- a frame of the game's.
--
--   Minimap:SetMaskTexture(asset): the engine's method on the map widget
--     (Blizzard_APIDocumentationGenerated/MinimapFrameAPIDocumentation.lua:141). The game's
--     only call is in MinimapClusterMixin:UpdateMinimapConfig (M/Camelot/Minimap.lua:42), with
--     "ui-hud-minimap-frame-generic-mask" for the fixed and the rotating map alike (lines 11,
--     16). ControllerLayout.lua hooks that function and places again after it.
--   The map's frame: Minimap's parent, MinimapCluster.MinimapContainer, a plain frame
--     (M/Mainline/Minimap.xml:47-56). With the strip underneath the game anchors it BOTTOM on
--     MinimapCluster's BOTTOM at 10 / scale, 30 / scale (M/Camelot/Minimap.lua:70-73, in
--     MinimapClusterMixin:SetHeaderUnderneath, which Edit Mode calls when the Size or the
--     strip's setting changes: Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:1794-1809).
--     Its own SetPoint is the engine's: it is no Edit Mode system (MinimapCluster is, and is
--     never moved, scaled or hidden here). SetHeaderUnderneath is hooked (hooksecurefunc),
--     never called, so the frame is lowered again after the game anchors it.
--   The strip: MinimapCluster.ZoneTextButton (M/Mainline/Minimap.xml:24, a Button from
--     MinimapZoneTextButtonTemplate, M/Camelot/MinimapZoneTextButton.xml:3-38). Its mixins
--     (M/Mainline/Minimap.lua:83-121, M/Camelot/MinimapZoneTextButton.lua,
--     Blizzard_SharedXMLBase/ButtonStateBehavior.lua) define no Hide, Show or IsShown, and it
--     has no OnHide script. A tap on it opens the world map (M/Mainline/Minimap.lua:110-112).
--   The clock on the strip is a frame of its own: TimeManagerClockButton, a child of
--     MinimapCluster anchored on the strip's right
--     (Blizzard_TimeManager/Mainline/Blizzard_TimeManager.xml:178-203,
--     Blizzard_TimeManager/Camelot/Blizzard_TimeManagerOverrides.lua:5-7), loaded at login
--     (Blizzard_Game/Shared/EventImplementation.lua:176-177). A plain Button with no mixin. A
--     tap on it opens the game's clock window (Blizzard_TimeManager.lua:377-388).
--     Nothing in the game's Lua shows either again once hidden.
--   The time: the game's clock shows GameTime_GetTime(false)
--     (Blizzard_TimeManager.lua:363-365). That function, not called here, reads the setting
--     "timeMgrUseLocalTime" and takes date("%H"), date("%M") or GetGameTime()
--     (Blizzard_FrameXMLUtil/GameTimeUtil.lua:77-93), then formats with "timeMgrUseMilitaryTime"
--     and TIMEMANAGER_TICKER_24HOUR or TIMEMANAGER_TICKER_12HOUR (same file, lines 9-33). The
--     same calls are made here, the settings read with C_CVar.GetCVar: GetGameTime
--     (SystemTimeDocumentation.lua:10).
--   The place name: the game's strip shows GetMinimapZoneText() coloured by
--     C_PvP.GetZonePVPInfo() (Minimap_Update, M/Mainline/Minimap.lua:169-185;
--     ZoneScriptDocumentation.lua:19, PvpInfoDocumentation.lua:847), refreshed on
--     ZONE_CHANGED, ZONE_CHANGED_INDOORS and ZONE_CHANGED_NEW_AREA (lines 373-375, 405-410).
--   The coordinates: the game's own text is MinimapCluster.MinimapContainer.PlayerCoords
--     (M/Mainline/Minimap.xml:287-301), 18 under the map, filled only while the game's
--     setting "minimapShowPlayerCoords" is on (MinimapPlayerCoordsMixin,
--     M/Mainline/Minimap.lua:1420-1456; the mixin has no SetPoint, Hide or SetFrameLevel of
--     its own). It is moved into the map's corner when that setting is on; otherwise, or when
--     the game moves it back, our own text is drawn from C_Map.GetBestMapForUnit and
--     C_Map.GetPlayerMapPosition (MapDocumentation.lua:49, 437), the calls the game's text
--     and QuestData.lua use.

local type, pcall, tostring, tonumber, ipairs = type, pcall, tostring, tonumber, ipairs
local floor, abs, max = math.floor, math.abs, math.max
local format = string.format

local Look = {}
PE.MapLook = Look

local KEY = "ctrlLayout"            -- the feature the debug lines and errors belong to
local QUEUE = "ctrlLayout:mapLook"  -- one piece of work waits for a fight to end, the newest
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK = "ui-hud-minimap-frame-generic-mask" -- M/Camelot/Minimap.lua:11, 16
local HEADER_HOOK = "SetHeaderUnderneath"
local ZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }
local INSET = 4            -- the words, in from the map's edges (map units)
local WORDS_LEVEL = 10     -- the words' frame over the map (the quest icons are 5 and 6 over it)
local CLOCK_SECONDS = 20   -- the clock is read again this often
local COORD_SECONDS = 0.5  -- and our own coordinates this often
local TEXT_REFUSED = "The square map is not possible on this game version: the map stays round."

local on = false           -- Square is placed
local square = false       -- the square mask is on the map (it was given and not refused)
local maskGiven = false
local refused = false      -- SetMaskTexture is missing or raised: not tried again this session
local want = { mapLook = 0, redraw = false } -- the newest wish: what Place was last asked for
local waiting = false      -- that wish has not run yet (a fight holds it back)
local wordsOn = false      -- the words listen and tick
local said = {}            -- lines written once a session
local noted = {}           -- [key] = the last line written under it (not repeated while the same)
local listeners = {}
local edge, words          -- our two frames, made at the first Square placement
local hiddenFound = {}     -- [the strip or the clock] = shown before it was hidden
local hiddenOrder = {}
local lowered              -- { frame, points = the game's own, set = { point, rel, relPoint, x, y } }
local headerHooked = false
local coords = { mode = nil, applied = false } -- mode "game" or "ours" once decided
local lastName, lastClock, lastCoords
local sinceClock, sinceCoords = 0, 0

local function Debug(text)
    if PE.debugOn then PE:Debug(KEY, "map look: " .. text) end
end

local function Once(text)
    if said[text] then return end
    said[text] = true
    Debug(text)
end

-- A line that is written again only when it reads differently.
local function Note(key, text)
    if noted[key] == text then return end
    noted[key] = text
    Debug(text)
end

local function SayMissing(what)
    Once(what .. " not found on this client")
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function PlainNumber(v)
    return not IsSecret(v) and type(v) == "number" and v == v
end

local function Child(t, key)
    if type(t) ~= "table" then return nil end
    local v = t[key]
    if type(v) == "table" then return v end
    return nil
end

-- One of a region's own methods, called: ok and its answers, or false.
local function Call(region, method, ...)
    local fn = type(region) == "table" and region[method] or nil
    if type(fn) ~= "function" then return false end
    return pcall(fn, region, ...)
end

-- A number read from a region, or nil.
local function Num(region, method)
    local ok, v = Call(region, method)
    if ok and PlainNumber(v) then return v end
    return nil
end

local function Showable(t)
    return type(t) == "table" and type(t.IsShown) == "function" and type(t.Show) == "function"
        and type(t.Hide) == "function"
end

local function IsShownNow(t)
    local ok, shown = Call(t, "IsShown")
    return ok and not IsSecret(shown) and shown and true or false
end

local function UIScale()
    return Num(UIParent, "GetEffectiveScale") or 1
end

-- A region's place in UI units from the screen's bottom left: "l=.. b=.. w=.. h=..", or nil.
local function RectText(region)
    local l, b, w, h = Num(region, "GetLeft"), Num(region, "GetBottom"), Num(region, "GetWidth"), Num(region, "GetHeight")
    local scale, ui = Num(region, "GetEffectiveScale"), UIScale()
    if not (l and b and w and h and scale) or ui <= 0 then return nil end
    local k = scale / ui
    return format("l=%.1f b=%.1f w=%.1f h=%.1f", l * k, b * k, w * k, h * k)
end

local function Plan()
    return PE.LayoutPlan
end

-- The square's numbers (Plan.MAP_SQUARE), with the plan's values when it is not there.
local function SquareNumbers()
    local plan = Plan()
    local q = type(plan) == "table" and plan.MAP_SQUARE or nil
    if type(q) == "table" and PlainNumber(q.edge) and PlainNumber(q.bottom) then return q.edge, q.bottom end
    return 1, 4
end

local function WantsSquare(opts)
    local plan = Plan()
    if type(plan) == "table" and type(plan.MapLook) == "function" then return plan.MapLook(type(opts) == "table" and opts or {}) == 1 end
    return type(opts) == "table" and opts.mapLook == 1
end

local function SetSquare(v)
    v = v and true or false
    if square == v then return end
    square = v
    for _, fn in ipairs(listeners) do PE:Safe(KEY, fn) end
end

---------------------------------------------------------------------------
-- The words: what each one reads
---------------------------------------------------------------------------

-- A game setting that is on or off: "1" is on, as the game's own GetCVarBool has it
-- (Blizzard_SharedXMLBase/CvarUtil.lua:33-35 is Lua on this client, so the engine's
-- C_CVar.GetCVar is asked instead: CVarDocumentation.lua).
local function CVarOn(name)
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function" then return false end
    local ok, v = pcall(C_CVar.GetCVar, name)
    return ok and not IsSecret(v) and v == "1"
end

-- The time the game's clock shows, as its text (Blizzard_FrameXMLUtil/GameTimeUtil.lua:9-33,
-- 77-93, read above), or nil when it cannot be read.
local function ClockText()
    local hour, minute
    if CVarOn("timeMgrUseLocalTime") then
        if type(date) ~= "function" then return nil end
        local ok, h, m = pcall(function() return tonumber(date("%H")), tonumber(date("%M")) end)
        if ok then hour, minute = h, m end
    elseif type(GetGameTime) == "function" then
        local ok, h, m = pcall(GetGameTime)
        if ok then hour, minute = h, m end
    end
    if not PlainNumber(hour) or not PlainNumber(minute) then return nil end
    local pattern
    if CVarOn("timeMgrUseMilitaryTime") then
        pattern = type(TIMEMANAGER_TICKER_24HOUR) == "string" and TIMEMANAGER_TICKER_24HOUR or "%02d:%02d"
    else
        pattern = type(TIMEMANAGER_TICKER_12HOUR) == "string" and TIMEMANAGER_TICKER_12HOUR or "%d:%02d"
        if hour == 0 then hour = 12 elseif hour > 12 then hour = hour - 12 end
    end
    local ok, text = pcall(format, pattern, hour, minute)
    if ok and type(text) == "string" then return text end
    return format("%d:%02d", hour, minute)
end

-- The place name's colour by the zone's kind, as the game's strip has it
-- (Minimap_Update, M/Mainline/Minimap.lua:172-185).
local ZONE_COLOURS = {
    sanctuary = { 0.41, 0.8, 0.94 }, arena = { 1.0, 0.1, 0.1 }, friendly = { 0.1, 1.0, 0.1 },
    hostile = { 1.0, 0.1, 0.1 }, contested = { 1.0, 0.7, 0.0 },
}

local function ZoneColour()
    local kind
    if type(C_PvP) == "table" and type(C_PvP.GetZonePVPInfo) == "function" then
        local ok, v = pcall(C_PvP.GetZonePVPInfo)
        if ok and not IsSecret(v) and type(v) == "string" then kind = v end
    end
    local c = kind and ZONE_COLOURS[kind]
    if c then return c[1], c[2], c[3] end
    local n = NORMAL_FONT_COLOR -- the game's gold (line 184)
    if type(n) == "table" and PlainNumber(n.r) and PlainNumber(n.g) and PlainNumber(n.b) then return n.r, n.g, n.b end
    return 1.0, 0.82, 0.0
end

local function ZoneName()
    if type(GetMinimapZoneText) ~= "function" then return nil end
    local ok, text = pcall(GetMinimapZoneText)
    if not ok or IsSecret(text) or type(text) ~= "string" then return nil end
    return text
end

-- text, or its beginning with "..." after it, so that the font string is at most `room`
-- wide. Whole characters only (a UTF-8 character's later bytes are 128 to 191).
local function Fit(fs, text, room)
    fs:SetText(text)
    local width = fs:GetUnboundedStringWidth()
    if not PlainNumber(width) or width <= room then return text end
    local n = #text
    while n > 0 do
        n = n - 1
        while n > 0 do
            local b = text:byte(n + 1)
            if b and b >= 128 and b <= 191 then n = n - 1 else break end
        end
        local cut = text:sub(1, n):gsub("%s+$", "") .. "..."
        fs:SetText(cut)
        width = fs:GetUnboundedStringWidth()
        if not PlainNumber(width) or width <= room then return cut end
    end
    fs:SetText("...")
    return "..."
end

-- Where the player is, as "x, y" in hundredths of the map, or "" where the game gives none.
local function CoordsText()
    if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" or type(C_Map.GetPlayerMapPosition) ~= "function" then
        return ""
    end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or IsSecret(mapID) or type(mapID) ~= "number" then return "" end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or IsSecret(pos) or type(pos) ~= "table" then return "" end
    local x, y = pos.x, pos.y
    if not PlainNumber(x) or not PlainNumber(y) or (x == 0 and y == 0) then return "" end
    return format("%.1f, %.1f", x * 100, y * 100)
end

---------------------------------------------------------------------------
-- Our two frames
---------------------------------------------------------------------------

local function Text(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    local file, size = fs:GetFont()
    if type(file) ~= "string" or not PlainNumber(size) then
        file, size = (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF", 12
    end
    pcall(fs.SetFont, fs, file, size, "OUTLINE")
    fs:SetWordWrap(false)
    return fs
end

-- Four strips along a frame's sides: { top, bottom, left, right }.
local function Strips(frame, layer, r, g, b, a)
    local list = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, layer)
        t:SetColorTexture(r, g, b, a)
        list[i] = t
    end
    return list
end

-- The strips `thick` wide, `inset` in from the frame's sides.
local function LayStrips(list, frame, thick, inset)
    local top, bottom, left, right = list[1], list[2], list[3], list[4]
    for _, t in ipairs(list) do t:ClearAllPoints() end
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    top:SetHeight(thick)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    bottom:SetHeight(thick)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    left:SetWidth(thick)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    right:SetWidth(thick)
end

local RefreshPlaceName, RefreshClock, RefreshCoords -- below

local function Build(map, parent)
    if edge and words then return true end
    if type(CreateFrame) ~= "function" then return false end
    -- The edge: on the map's parent, as the round map's black disc is, so it moves and
    -- scales with the map; one frame level under it.
    local e = CreateFrame("Frame", nil, parent)
    e.strips = Strips(e, "BACKGROUND", 0, 0, 0, 1)
    e:EnableMouse(false)
    e:Hide()
    -- The words and the faint line just inside the edge: on the map, over it, taking no taps.
    local w = CreateFrame("Frame", nil, map)
    w:SetAllPoints(map)
    w:EnableMouse(false)
    w.line = Strips(w, "ARTWORK", 1, 1, 1, 0.12)
    w.name = Text(w, "GameFontNormal")
    w.name:SetJustifyH("CENTER")
    w.name:SetPoint("TOP", w, "TOP", 0, -INSET)
    w.clock = Text(w, "GameFontHighlightSmall")
    w.clock:SetJustifyH("RIGHT")
    w.clock:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -INSET, INSET)
    w.coords = Text(w, "GameFontHighlightSmall")
    w.coords:SetJustifyH("LEFT")
    w.coords:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", INSET, INSET)
    w:Hide()
    w.onEvent = PE:Wrap(KEY, function() if on then RefreshPlaceName() end end)
    w.onUpdate = PE:Wrap(KEY, function(_, elapsed)
        if not on or not PlainNumber(elapsed) then return end
        sinceClock, sinceCoords = sinceClock + elapsed, sinceCoords + elapsed
        if sinceClock >= CLOCK_SECONDS then
            sinceClock = 0
            RefreshClock()
        end
        if sinceCoords >= COORD_SECONDS then
            sinceCoords = 0
            if coords.mode == "ours" then RefreshCoords() end
        end
    end)
    edge, words = e, w
    return true
end

RefreshPlaceName = function()
    local text = ZoneName() or ""
    local room = (Num(words, "GetWidth") or 198) - 2 * INSET
    local r, g, b = ZoneColour()
    words.name:SetTextColor(r, g, b)
    if text == lastName and room == words.nameRoom then return end
    lastName, words.nameRoom = text, room
    Fit(words.name, text, room)
end

RefreshClock = function()
    local text = ClockText() or ""
    if text == lastClock then return end
    lastClock = text
    words.clock:SetText(text)
end

RefreshCoords = function()
    local text = coords.mode == "ours" and CoordsText() or ""
    if text == lastCoords then return end
    lastCoords = text
    words.coords:SetText(text)
end

-- The words listen and tick only while Square is placed.
local function StartWords()
    for _, event in ipairs(ZONE_EVENTS) do pcall(words.RegisterEvent, words, event) end
    words:SetScript("OnEvent", words.onEvent)
    words:SetScript("OnUpdate", words.onUpdate)
    sinceClock, sinceCoords = 0, 0
    lastName, lastClock, lastCoords = nil, nil, nil
    RefreshPlaceName()
    RefreshClock()
    RefreshCoords()
    words:Show()
    wordsOn = true
end

local function StopWords()
    wordsOn = false
    if not words then return end
    words:SetScript("OnUpdate", nil)
    words:SetScript("OnEvent", nil)
    words:UnregisterAllEvents()
    words:Hide()
end

---------------------------------------------------------------------------
-- The game's pieces
---------------------------------------------------------------------------

-- The map, its frame and that frame's parent (Minimap, MinimapCluster.MinimapContainer and
-- MinimapCluster on this client), or nil after saying what is missing.
local function MapParts()
    local map = Minimap
    if type(map) ~= "table" or type(map.GetParent) ~= "function" or type(map.GetWidth) ~= "function"
        or type(map.GetFrameLevel) ~= "function" or type(map.GetEffectiveScale) ~= "function" then
        SayMissing("the map (Minimap)")
        return nil
    end
    local ok, box = pcall(map.GetParent, map)
    if not ok or type(box) ~= "table" then
        SayMissing("the map's frame (the map's parent)")
        return nil
    end
    local _, cluster = Call(box, "GetParent")
    return map, box, type(cluster) == "table" and cluster or nil
end

-- Gives the map the square mask: at the first placement and after each redraw. A missing
-- method or a call that raises is the fallback: said once, the round look stays.
local function GiveMask(map, redraw)
    if refused then return end
    if maskGiven and not redraw then return end
    local ok = type(map.SetMaskTexture) == "function" and pcall(map.SetMaskTexture, map, SQUARE_MASK)
    if not ok then
        refused = true
        maskGiven = false
        Once("the square mask was refused")
        SetSquare(false)
        return
    end
    Debug(maskGiven and "the square mask given again after a redraw" or "the square mask given")
    maskGiven = true
    SetSquare(true)
end

local function SamePoint(a, b)
    return a ~= nil and b ~= nil and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
        and PlainNumber(a[4]) and PlainNumber(a[5]) and abs(a[4] - b[4]) < 0.01 and abs(a[5] - b[5]) < 0.01
end

-- A frame's points as { { point, relativeTo, relativePoint, x, y }, ... }, or nil.
local function ReadPoints(f)
    local n = Num(f, "GetNumPoints")
    if not n then return nil end
    local out = {}
    for i = 1, n do
        local ok, point, rel, relPoint, x, y = Call(f, "GetPoint", i)
        if not ok or type(point) ~= "string" then return nil end
        out[i] = { point, rel, relPoint, x, y }
    end
    return out
end

local function WritePoints(f, points)
    local ok = Call(f, "ClearAllPoints")
    for _, p in ipairs(points) do
        if ok then ok = Call(f, "SetPoint", p[1], p[2], p[3], p[4], p[5]) end
    end
    return ok
end

-- Lowers the map's frame inside its Edit Mode piece so the map's bottom is `bottom + edge`
-- (5) over the piece's own bottom, which the layout puts on the screen's bottom edge. In the
-- frame's own units: its bottom at yb gives the map's bottom at (yb + (H - h) / 2) * scale,
-- H the frame's height and h the map's, so yb = 5 / scale - (H - h) / 2. At 100% with the
-- 253 frame: 5 - 27.5 = -22.5, where the game has 30. Across the game's own number stays.
-- Only while the frame is anchored the way the game does it with the strip underneath
-- (one point, BOTTOM on its parent's BOTTOM); anything else is left alone and said once.
local function LowerMapFrame(map, box, cluster)
    if not cluster then return SayMissing("the map's piece (the map's frame's parent)") end
    local points = ReadPoints(box)
    if not points then return SayMissing("the map's frame's place") end
    if lowered and lowered.frame == box and #points == 1 and SamePoint(points[1], lowered.set) then return end -- still ours
    local p = points[1]
    if #points ~= 1 or p[1] ~= "BOTTOM" or p[3] ~= "BOTTOM" or (p[2] ~= cluster and p[2] ~= nil) or not PlainNumber(p[4]) then
        return Once("the map's frame is not anchored under the map's piece: not lowered")
    end
    local scale, height, mapHeight = Num(box, "GetScale"), Num(box, "GetHeight"), Num(map, "GetHeight")
    local clusterScale, ui = Num(cluster, "GetEffectiveScale"), UIScale()
    if not (scale and height and mapHeight and clusterScale) or scale <= 0 or clusterScale <= 0 then
        return SayMissing("the map's frame's size")
    end
    local edgeWidth, boxBottom = SquareNumbers()
    local up = (boxBottom + edgeWidth) * ui / clusterScale -- in the piece's units
    local y = up / scale - (height - mapHeight) / 2
    local set = { "BOTTOM", cluster, "BOTTOM", p[4], y }
    if not WritePoints(box, { set }) then
        WritePoints(box, points)
        return Once("the map's frame could not be lowered")
    end
    lowered = { frame = box, points = points, set = set }
    Note("lowered", format("the map's frame lowered inside its piece: its bottom from %.1f to %.1f (scale %.2f, frame %.1f, map %.1f)",
        PlainNumber(p[5]) and p[5] or 0, y, scale, height, mapHeight))
end

local function Unlower()
    if not lowered then return end
    local now = ReadPoints(lowered.frame)
    -- Put back only while it is still where this file put it: after the game anchored it
    -- again it is already the game's.
    if now and #now == 1 and SamePoint(now[1], lowered.set) then WritePoints(lowered.frame, lowered.points) end
    lowered = nil
    noted.lowered = nil
end

local Replace -- below

-- After the game anchors the map's frame again (Edit Mode, when the Size or the strip's
-- setting changes), lower it again. Installed once, at the first Square placement; does
-- nothing while Round.
local function HookHeader(cluster)
    if headerHooked then return end
    if type(cluster) ~= "table" or type(cluster[HEADER_HOOK]) ~= "function" or type(hooksecurefunc) ~= "function" then
        return SayMissing("the hook on the map's frame being anchored (MinimapCluster.SetHeaderUnderneath)")
    end
    local ok = pcall(hooksecurefunc, cluster, HEADER_HOOK, PE:Wrap(KEY, function()
        if on then Replace() end
    end))
    headerHooked = ok and true or false
end

-- The game's strip and the clock on it, hidden while Square is placed.
local STRIP = {
    { name = "the game's place name strip (MinimapCluster.ZoneTextButton)",
      get = function(cluster) return Child(cluster, "ZoneTextButton") end },
    { name = "the game's clock (TimeManagerClockButton)", get = function() return TimeManagerClockButton end },
}

local function HideStrip(cluster)
    for _, s in ipairs(STRIP) do
        local ok, f = pcall(s.get, cluster)
        if not ok or not Showable(f) then
            SayMissing(s.name)
        else
            local shown = IsShownNow(f)
            if hiddenFound[f] == nil then
                hiddenFound[f] = shown
                hiddenOrder[#hiddenOrder + 1] = f
            end
            if shown then pcall(f.Hide, f) end
        end
    end
end

local function ShowStrip()
    for _, f in ipairs(hiddenOrder) do
        if hiddenFound[f] then pcall(f.Show, f) end
    end
    hiddenFound, hiddenOrder = {}, {}
end

-- The coordinates. The game's own text is used when its setting is on and it stays where
-- it is put; decided once a session, then kept.
local function OursBecause(why)
    coords.mode = "ours"
    Note("coords", "coordinates: our own text in the map's bottom left corner (" .. why .. ")")
end

local function CoordsPoint(map)
    return { "BOTTOMLEFT", map, "BOTTOMLEFT", INSET, INSET }
end

local function HideGameCoords(f)
    if not Showable(f) then return end
    if coords.shown == nil then coords.shown = IsShownNow(f) end
    if IsShownNow(f) then pcall(f.Hide, f) end
    coords.hidden = f
end

local function PlaceCoords(map, box)
    local f = Child(box, "PlayerCoords")
    if not f or type(f.SetPoint) ~= "function" or type(f.ClearAllPoints) ~= "function" then
        SayMissing("the game's coordinates text (PlayerCoords)")
        if coords.mode ~= "ours" then OursBecause("the game's own text was not found") end
        return
    end
    local wanted = CoordsPoint(map)
    if coords.mode == "ours" then return HideGameCoords(f) end
    if coords.mode == "game" and coords.applied then
        local now = ReadPoints(f)
        if now and #now == 1 and SamePoint(now[1], wanted) then return end
        OursBecause("the game moved its own text back")
        return HideGameCoords(f)
    end
    if coords.mode == nil and not CVarOn("minimapShowPlayerCoords") then
        OursBecause("the game's own coordinates are switched off")
        return HideGameCoords(f)
    end
    local points, level = ReadPoints(f), Num(f, "GetFrameLevel")
    local mapLevel = Num(map, "GetFrameLevel")
    if not points or not level or not mapLevel then
        OursBecause("the game's own text could not be read")
        return HideGameCoords(f)
    end
    coords.frame, coords.points, coords.level = f, points, level
    local ok = WritePoints(f, { wanted })
    if ok then ok = Call(f, "SetFrameLevel", mapLevel + WORDS_LEVEL) end
    if not ok then
        WritePoints(f, points)
        Call(f, "SetFrameLevel", level)
        OursBecause("the game's own text could not be moved")
        return HideGameCoords(f)
    end
    coords.mode, coords.applied = "game", true
    Note("coords", "coordinates: the game's own text, moved into the map's bottom left corner")
end

local function RestoreCoords()
    if coords.applied and coords.frame then
        local now = ReadPoints(coords.frame)
        if now and #now == 1 and coords.points and SamePoint(now[1], CoordsPoint(Minimap)) then
            WritePoints(coords.frame, coords.points)
        end
        if coords.level then Call(coords.frame, "SetFrameLevel", coords.level) end
    end
    coords.applied = false
    if coords.hidden then
        if coords.shown then pcall(coords.hidden.Show, coords.hidden) end
        coords.hidden, coords.shown = nil, nil
    end
    noted.coords = nil
end

-- What the game hangs on the map that this version leaves where it is, for the log and the
-- snapshot: the day and night mark (M/Camelot/Diel.lua:18-28, MinimapCluster.DielFrame), the
-- mail mark (MinimapCluster.IndicatorFrame, M/Mainline/Minimap.xml:46; over the strip's
-- left end, M/Camelot/Minimap.lua:78-79), the two zoom buttons (Minimap.ZoomIn and ZoomOut,
-- M/Mainline/Minimap.xml:71-100, hidden until the map is pointed at), the event button
-- (MinimapBackdrop.ExternalEventURLButton, line 274), the group finder's button
-- (QueueStatusButton, Blizzard_QueueStatusFrame/Mainline/QueueStatusFrame.xml:136, an Edit
-- Mode piece of its own: only read), and the holder for the controller's buttons under the
-- strip (MinimapCluster.GamepadButtons, M/Mainline/Minimap.xml:304-309). The instance flag
-- does not exist on this client (M/Camelot/MinimapInstanceDifficulty.lua:1-3). The tracking
-- and calendar buttons and the addon badge are hidden by ControllerLayout.lua.
local RIM = {
    { "day and night mark", function(_, _, cluster) return Child(cluster, "DielFrame") end },
    { "mail mark", function(_, _, cluster) return Child(cluster, "IndicatorFrame") end },
    { "zoom in button", function(map) return Child(map, "ZoomIn") end },
    { "zoom out button", function(map) return Child(map, "ZoomOut") end },
    { "event button", function() return Child(type(MinimapBackdrop) == "table" and MinimapBackdrop or nil, "ExternalEventURLButton") end },
    { "group finder button", function() return type(QueueStatusButton) == "table" and QueueStatusButton or nil end },
    { "controller buttons holder", function(_, _, cluster) return Child(cluster, "GamepadButtons") end },
    { "game's coordinates text", function(_, box) return Child(box, "PlayerCoords") end },
    { "game's clock", function() return type(TimeManagerClockButton) == "table" and TimeManagerClockButton or nil end },
}

local function RimPieces()
    local out = {}
    local map = type(Minimap) == "table" and Minimap or nil
    local _, box = Call(map, "GetParent")
    box = type(box) == "table" and box or nil
    local _, cluster = Call(box, "GetParent")
    cluster = type(cluster) == "table" and cluster or nil
    for i, r in ipairs(RIM) do
        local ok, f = pcall(r[2], map, box, cluster)
        out[i] = { r[1], ok and f or nil }
    end
    return out
end

local function LogRim()
    if not PE.debugOn then return end
    for _, p in ipairs(RimPieces()) do
        local name, f = p[1], p[2]
        local text = f and RectText(f) or nil
        Note("rim " .. name, "rim: " .. name .. " | " .. (f == nil and "not found"
            or ((IsShownNow(f) and "shown" or "hidden") .. " | " .. (text or "no place"))))
    end
end

---------------------------------------------------------------------------
-- Place and put back
---------------------------------------------------------------------------

-- The edge round the map and the faint line inside it, sized from the map as the round
-- map's disc is: the map's own width, plus 1 screen unit on each side.
local function PlaceEdge(map, box)
    local w, h, level = Num(map, "GetWidth"), Num(map, "GetHeight"), Num(map, "GetFrameLevel")
    local mapScale, boxScale, ui = Num(map, "GetEffectiveScale"), Num(box, "GetEffectiveScale"), UIScale()
    if not (w and h and level and mapScale and boxScale) or boxScale <= 0 or mapScale <= 0 then
        edge:Hide()
        return SayMissing("the map's size, for its edge")
    end
    local edgeWidth = SquareNumbers()
    local t = edgeWidth * ui / boxScale -- 1 screen unit, in the units of the map's parent
    edge:SetFrameLevel(max(0, level - 1))
    edge:SetSize(w * mapScale / boxScale + 2 * t, h * mapScale / boxScale + 2 * t)
    edge:ClearAllPoints()
    edge:SetPoint("CENTER", map, "CENTER", 0, 0)
    LayStrips(edge.strips, edge, t, 0)
    edge:Show()
    LayStrips(words.line, words, edgeWidth * ui / mapScale, 0)
    for _, s in ipairs(words.line) do s:Show() end
    Note("edge", "the edge's box " .. (RectText(edge) or "has no place yet"))
end

local function RestoreNow()
    if not on and not maskGiven then return end -- never placed: nothing was changed
    local wasOn = on
    on = false
    StopWords()
    if edge then edge:Hide() end
    if maskGiven then
        local map = Minimap
        if type(map) == "table" and type(map.SetMaskTexture) == "function" and pcall(map.SetMaskTexture, map, ROUND_MASK) then
            Debug("the game's round mask given back")
        else
            Debug("the game's round mask could not be given back")
        end
        maskGiven = false
    end
    SetSquare(false)
    Unlower()
    ShowStrip()
    RestoreCoords()
    noted = {}
    if wasOn then Debug("off: the round map, the game's strip shown again") end
end

local function PlaceNow(opts, redraw)
    if not WantsSquare(opts) then return RestoreNow() end
    local map, box, cluster = MapParts()
    if not map then return end
    if not Build(map, box) then return SayMissing("the frames for the map's edge and words (CreateFrame)") end
    if not on then
        on = true
        Debug(format("on: the square map, the map %.1f across at scale %.2f", Num(map, "GetWidth") or 0, Num(box, "GetScale") or 0))
    end
    GiveMask(map, redraw)
    HookHeader(cluster)
    LowerMapFrame(map, box, cluster)
    HideStrip(cluster)
    local level = Num(map, "GetFrameLevel") or 0
    words:SetFrameLevel(level + WORDS_LEVEL)
    if square then
        PlaceEdge(map, box)
    else
        -- The fallback: the round map with its disc (ControllerLayout.lua draws it).
        edge:Hide()
        for _, s in ipairs(words.line) do s:Hide() end
    end
    PlaceCoords(map, box)
    if not wordsOn then
        StartWords()
    else
        RefreshPlaceName()
        RefreshCoords()
    end
    Note("words", "the words' frame " .. (RectText(words) or "has no place yet"))
    LogRim()
end

local function RunWish()
    waiting = false
    local redraw = want.redraw
    want.redraw = false
    PlaceNow(want, redraw)
end

-- The newest wish, run now or, once, when the fight ends.
Replace = function()
    waiting = true
    PE:RunOutOfCombat(QUEUE, RunWish)
end

-- Nothing of this file is on the screen or waiting: Round then has nothing to do at all.
local function Idle()
    return not on and not maskGiven and not waiting
end

function Look:Place(opts, redraw)
    local look = WantsSquare(opts) and 1 or 0
    if look == 0 and Idle() then
        want = { mapLook = 0, redraw = false }
        return
    end
    -- A redraw that a fight is still holding back counts when the held call runs.
    local held = waiting and want.mapLook == look and want.redraw
    want = { mapLook = look, redraw = (redraw or held) and true or false }
    Replace()
end

function Look:Restore()
    want = { mapLook = 0, redraw = false }
    if Idle() then return end
    Replace()
end

function Look:IsSquare()
    return square
end

function Look:Status()
    if refused and want.mapLook == 1 then return TEXT_REFUSED end
    return nil
end

function Look:OnChange(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

function Look:SnapshotPieces()
    if not on then return {} end
    local SKIP = { skip = true } -- they sit on the map by design: listed, not checked for overlaps
    local out = { { "map's edge", edge, SKIP }, { "map's words", words, SKIP } }
    for _, p in ipairs(RimPieces()) do out[#out + 1] = { p[1], p[2], SKIP } end
    return out
end
