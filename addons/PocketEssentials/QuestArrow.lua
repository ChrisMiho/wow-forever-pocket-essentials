local ADDON_NAME, PE = ...

-- QuestArrow: an arrow on the screen that points, in a straight line, to the
-- nearest objective of the quest you focused in the game's quest log, with
-- the distance and the quest name under it.
--
-- Which objective (only pins on the map you are on are ever pointed at):
--   * A quest is focused (QuestData:GetTrackedQuest) and has known places on
--     this map: its nearest pin, chosen again once a second while you move,
--     with these rules:
--       - A spot is known by its position and objective, not by its table, so
--         the target and "Here" survive the quest data being rebuilt (which
--         happens after every kill).
--       - If the target is gone (its objective finished), the nearest spot
--         left is taken at once.
--       - Otherwise another spot only takes over when it is under KEEP_RATIO
--         (80 %) of the target's distance, that is at least 20 % nearer, and
--         also at least KEEP_YARDS (15 yards) nearer, so two spots at
--         a similar distance do not swap back and forth; and never while the
--         arrow reads "Here".
--       - A spot where the arrow read "Here" is set aside for ASIDE_SECONDS
--         once you walk away from it: the arrow leads on to the nearest spot
--         you have not reached yet. When every spot here is set aside the list
--         is cleared and the nearest is taken again (so a quest with one spot
--         keeps pointing at it). The list is cleared when the focused quest or
--         the map changes, and when the feature goes off.
--   * Its places are all on other maps: no arrow; the text reads "Outside
--     this zone" over "Head to <zone>" (the zone with most of its places;
--     the quest's name if the zone name cannot be read).
--   * It has no known place at all: no arrow; "No map data for this quest".
--   * No quest focused: no arrow; the text asks you to focus one. With
--     restHide on (the default) the block is hidden while you rest in a city
--     or inn (IsResting), checked again on PLAYER_UPDATE_RESTING, which is
--     listened for only while the feature is on.
--
-- When the objective is behind you (more than TURN_ENTER from straight
-- ahead) there is no arrow; the top line reads "Turn around".
--
-- Look (spec 2026-11-20-0.9.0-ui-redesign, "Quest arrow on screen"): the
-- block is sized by its own `scale` option only (s = scale / 100), not by
-- Button size: arrow box 76*s, text width 400*s, top line 28*s in the title
-- face, quest line 20*s in the normal face, 4*s under the box and 2*s between
-- the lines (720p units through UI:Px). With no arrow the top line starts at
-- the top of the block. The quest line is one text with colour codes:
-- "Quest: " (or "Turn in: ", "Head to ") in dim gold, then the name in white.
--
-- Which way (the part most likely to be wrong, so it is spelled out):
--   * Map fractions: x grows to the EAST, y grows to the SOUTH.
--       east  = (pin.x - player.x) * mapWidthYards
--       north = (player.y - pin.y) * mapHeightYards
--   * GetPlayerFacing(): radians, 0 = north, growing COUNTER-clockwise
--     (pi/2 = west). The same convention the old QuestDots minimap used.
--   * Bearing to the pin in that same convention (counter-clockwise from
--     north): bearing = atan2(-east, north).  Due west gives +pi/2.
--   * rel = bearing - facing = how far to the LEFT of straight ahead it is.
--   * The arrow is drawn pointing up and turned counter-clockwise by rel on
--     the screen (x right, y up): tip = (-sin(rel), cos(rel)).
--       facing north, pin north: rel = 0      -> up
--       facing north, pin east : rel = -pi/2  -> right
--       facing east,  pin north: rel = +pi/2  -> left
--
-- The arrow is one picture (Icons/arrow, pointing up) turned with
-- Texture:SetRotation, which turns counter-clockwise for positive radians, so
-- it gets `rel` as it is. It is tinted gold, or green for "Here". If this
-- client's textures cannot be turned, the arrow is drawn instead as three
-- thick solid-colour lines (plus a dark outline) whose end points are
-- computed here.
--
-- Cost: one OnUpdate on a private driver frame, 10 times a second while an
-- arrow is showing and once a second while your position cannot be read. The
-- driver is stopped completely inside instances, while there is nothing to
-- point at (QuestData's callbacks start it again) and while the feature is off.

local type, pairs, next, pcall = type, pairs, next, pcall
local floor, sqrt, sin, cos, max, huge = math.floor, math.sqrt, math.sin, math.cos, math.max, math.huge
local atan2 = math.atan2
local strbyte, strsub, format = string.byte, string.sub, string.format

local KEY = "questArrow"

local ACTIVE_INTERVAL = 1 / 10      -- seconds between updates while the arrow is showing
local IDLE_INTERVAL = 1             -- ... while the position cannot be read
local SELECT_INTERVAL = 1           -- the nearest objective is re-chosen at most this often
local KEEP_RATIO = 0.8              -- another spot takes over only under this share of the target's distance...
local KEEP_YARDS = 15               -- ... and at least this many yards nearer
local ASIDE_SECONDS = 180           -- a reached spot is skipped for this long after you leave it
local HERE_ENTER, HERE_LEAVE = 10, 14   -- yards: "Here" switches on below the first, off above the second
local MIN_AIM_YARDS = 3             -- closer than this the direction is noise; the arrow keeps its last angle
local ANGLE_STEPS = 180             -- the arrow turns in 2-degree steps
local STEP = 2 * math.pi / ANGLE_STEPS
local TITLE_MAX = 52                -- longer quest names are cut (two lines of about 32)
local MAX_FAILURES = 5              -- the driver stops itself after this many errors in a row
local TURN_ENTER = math.rad(150)    -- "Turn around" shows when the objective is further round than this...
local TURN_LEAVE = math.rad(135)    -- ... and goes again below this
local PI, TWO_PI = math.pi, 2 * math.pi

-- Presets, in pixels on a 720p screen: point on the arrow block, point on the
-- screen, x, y. Chosen to stay clear of the default layout: unit frames
-- (either side of the bottom middle, or top left), minimap and buffs (top
-- right), quest tracker and side bars (right edge), chat (bottom left) and
-- the action bars (bottom).
local POSITIONS = {
    top   = { "TOP",    "TOP",    0,    -40 },
    upper = { "CENTER", "CENTER", 0,    150 },
    lower = { "CENTER", "CENTER", 0,    -140 },
    left  = { "CENTER", "CENTER", -230, 60 },
    right = { "CENTER", "CENTER", 230,  60 },
}
-- Sizes of the block at scale 100, in pixels on a 720p screen.
local BOX_PX, WIDTH_PX, BIG_PX, SMALL_PX, BOX_GAP_PX, LINE_GAP_PX = 76, 400, 28, 20, 4, 2
local SCALE_MIN, SCALE_MAX, SCALE_STEP, SCALE_DEFAULT = 50, 150, 10, 100
-- The old Small / Normal / Large choice, moved to scale once (then cleared).
local SIZE_TO_SCALE = { small = 70, normal = 100, large = 150 }
local DEFAULTS = { position = "top", scale = SCALE_DEFAULT, restHide = true }

local COLOR_ARROW = { 1, 0.82, 0 }
local COLOR_HERE = { 0.35, 1, 0.45 }
-- Colour codes for the quest line: dim gold (.85, .72, .35), white, grey (.84).
local CODE_PREFIX, CODE_NAME, CODE_GREY = "|cffd9b859", "|cffffffff", "|cffd6d6d6"
local ARROW_TEXTURE = "Interface\\AddOns\\PocketEssentials\\Icons\\arrow"

-- Fallback drawing: the arrow pointing up, as fractions of half its length: x1, y1, x2, y2.
local SHAPE = {
    { 0, -1, 0, 0.85 },         -- shaft
    { 0, 1, -0.62, 0.30 },      -- left barb
    { 0, 1, 0.62, 0.30 },       -- right barb
}
local SHAPE_COUNT = #SHAPE
local LINE_COUNT = SHAPE_COUNT * 2      -- 1..3 outline, 4..6 fill

local mod
local QD                                -- PE.QuestData, set in OnEnable

-- All changing state lives in this one table (no tables are made per update).
local S = {
    ready = false,                      -- enabled, data acquired, frames built
    acquired = false,
    running = false,                    -- the driver's OnUpdate is live
    shown = false,                      -- the arrow block is on screen
    boxShown = true,                    -- the arrow itself (not just the text) is visible
    acc = 0, interval = ACTIVE_INTERVAL,
    sinceSelect = 0, selectDue = true,
    failures = 0,
    here = false,
    turn = false,                       -- "Turn around" is showing instead of the arrow
    noFocus = false,                    -- the text-only state is "No quest focused"
    arrow = nil,                        -- the arrow picture, when it can be turned (else `lines` are used)
    pinMap = nil,                       -- the map the target (S.pin) is on
    aside = {},                         -- spots set aside after being reached: [PosKey] = GetTime() they come back
    asideQuest = nil, asideMap = nil,   -- the quest and map the set-aside spots belong to
    dbgArrow = false,                   -- debug log: the last "driver" line said an arrow is showing
}
local lines = {}
local gx1, gy1, gx2, gy2 = {}, {}, {}, {}   -- line end points before turning, in UI units

local function IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, v)
    if not ok then return true end
    return secret and true or false
end

-- Debug log: the arrow's state, written only when it differs from the last
-- one written (S.dbgState). Only called while the log is on.
local function DebugState(text)
    if text == S.dbgState then return end
    S.dbgState = text
    PE:Debug(KEY, text)
end

local function Opt(key)
    local opts = mod and mod.opts
    local value = nil
    if type(opts) == "table" then value = opts[key] end     -- may be false: not "and ... or nil"
    if value == nil then value = DEFAULTS[key] end
    return value
end

-- s = scale / 100, from the saved scale kept inside 50..150.
local function ScaleFactor()
    local scale = Opt("scale")
    if type(scale) ~= "number" or scale ~= scale then scale = SCALE_DEFAULT end
    if scale < SCALE_MIN then scale = SCALE_MIN elseif scale > SCALE_MAX then scale = SCALE_MAX end
    return scale / 100
end

-- Moves an old saved size (small / normal / large) to scale, once: size is
-- cleared, so it is never read again.
local function MigrateSize(opts)
    if type(opts) ~= "table" or opts.size == nil then return end
    local scale = SIZE_TO_SCALE[opts.size]
    if scale then opts.scale = scale end
    opts.size = nil
end

local function IsRestingNow()
    if type(IsResting) ~= "function" then return false end
    local ok, resting = pcall(IsResting)
    if not ok or IsSecret(resting) then return false end
    return resting and true or false
end

-- Resting rule: "No quest focused" is hidden in cities and inns with restHide on.
local function HiddenForRest()
    return S.noFocus and Opt("restHide") == true and IsRestingNow()
end

---------------------------------------------------------------------------
-- Choosing the objective
---------------------------------------------------------------------------

-- A spot's position as one number (map fractions to 5 decimals), for the set-aside list.
local function PosKey(x, y)
    return floor(x * 1e5 + 0.5) * 1e6 + floor(y * 1e5 + 0.5)
end

-- Nearest pin of `pins` not in `skip` (a set-aside list, or nil). Returns
-- pin, d2, how many pins were skipped, how many were looked at.
local function Nearest(pins, px, py, width, height, skip)
    local best, bestD2, skipped, count = nil, huge, 0, 0
    for i = 1, #pins do
        local pin = pins[i]
        local x, y = pin.x, pin.y
        if type(x) == "number" and type(y) == "number" then
            count = count + 1
            if skip and skip[PosKey(x, y)] then
                skipped = skipped + 1
            else
                local dx, dy = (x - px) * width, (y - py) * height
                local d2 = dx * dx + dy * dy
                if d2 < bestD2 then best, bestD2 = pin, d2 end
            end
        end
    end
    return best, bestD2, skipped, count
end

-- The pin of `pins` that is the same spot as `old` (position, objective and kind), or nil.
-- The kind counts: a turn-in at the objective's own spot is a new target.
local function SameSpot(pins, old)
    local x, y, obj, kind = old.x, old.y, old.obj, old.kind
    for i = 1, #pins do
        local pin = pins[i]
        if pin.x == x and pin.y == y and pin.obj == obj and pin.kind == kind then return pin end
    end
    return nil
end

local function Yards(pin, px, py, width, height)
    local dx, dy = (pin.x - px) * width, (pin.y - py) * height
    return sqrt(dx * dx + dy * dy)
end

local function HasPlaces(byMap)
    for _, pins in pairs(byMap) do
        if type(pins) == "table" and pins[1] ~= nil then return true end
    end
    return false
end

-- The map with most of the quest's places (lowest map id on a tie).
local function BusiestMap(byMap)
    local best, bestN = nil, 0
    for mapID, pins in pairs(byMap) do
        local n = type(pins) == "table" and #pins or 0
        if type(mapID) == "number" and (n > bestN or (n == bestN and n > 0 and mapID < best)) then
            best, bestN = mapID, n
        end
    end
    return best
end

-- The zone name of a map, or nil.
local function ZoneName(mapID)
    local name
    if mapID and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and not IsSecret(info) and type(info) == "table" then
            name = info.name
            if IsSecret(name) or type(name) ~= "string" or name == "" then name = nil end
        end
    end
    return name
end

-- Names that fit on two lines are kept whole; longer ones end in "...".
local function Shorten(text)
    if #text <= TITLE_MAX then return text end
    local n = TITLE_MAX - 3
    -- do not cut a multi-byte letter in half
    while n > 1 do
        local b = strbyte(text, n + 1)
        if not b or b < 128 or b > 191 then break end
        n = n - 1
    end
    while n > 1 and strbyte(text, n) == 32 do n = n - 1 end    -- no space before the dots
    return strsub(text, 1, n) .. "..."
end

-- The quest line: the prefix in dim gold, then the name (shortened) in white.
local function Line(prefix, name)
    return CODE_PREFIX .. prefix .. "|r" .. CODE_NAME .. Shorten(name) .. "|r"
end

local function QuestTitle(questID)
    local title = QD:GetQuestTitle(questID)
    if type(title) ~= "string" or title == "" then title = "Quest" end
    return title
end

local function TitleFor(pin)
    local title = pin.title
    if type(title) ~= "string" or title == "" then title = QuestTitle(pin.questID) end
    return Line(pin.kind == "turnin" and "Turn in: " or "Quest: ", title)
end

local function SetTitle(title)
    if title ~= S.title then
        S.title = title
        S.titleText:SetText(title)
    end
end

-- Text-only states: the big line and the small line under it.
local function SetMessage(big, small)
    S.msgBig = big
    SetTitle(small or "")
end

-- Tells QuestData which spot the arrow points at (nil: none), so the icons
-- can draw it even when the spots-per-objective limit would hide it.
local function PublishPin(pin)
    local data = QD or PE.QuestData
    if type(data) == "table" and type(data.SetArrowPin) == "function" then data:SetArrowPin(pin) end
end

-- Forgets the set-aside spots when the focused quest or the map changed, and
-- drops the ones whose time is up.
local function RefreshAside(tracked, playerMap)
    local aside = S.aside
    if tracked ~= S.asideQuest or playerMap ~= S.asideMap then
        if PE.debugOn and next(aside) ~= nil then
            PE:Debug(KEY, "set-aside spots forgotten: " .. (tracked ~= S.asideQuest and "quest changed" or "map changed"))
        end
        S.asideQuest, S.asideMap = tracked, playerMap
        wipe(aside)
        return
    end
    if next(aside) == nil then return end
    local now = GetTime()
    for key, back in pairs(aside) do
        if back <= now then aside[key] = nil end
    end
end

-- The spot to point at among `pins` (this map's spots of the focused quest).
local function Pick(pins, px, py, width, height, old)
    local aside = S.aside
    local nearest, nearestD2, skipped, count = Nearest(pins, px, py, width, height, aside)
    local restart = false
    if not nearest and skipped > 0 then
        wipe(aside)
        restart = true
        if PE.debugOn then PE:Debug(KEY, "all spots reached: starting again") end
        nearest, nearestD2, skipped, count = Nearest(pins, px, py, width, height, nil)
    end
    local pin, why = nearest, nil
    if old then
        local same = SameSpot(pins, old)
        if not same then
            why = "spot changed: objective finished or spot gone"
        elseif S.here or nearest == same then
            pin = same
        elseif restart or aside[PosKey(same.x, same.y)] then
            pin = nearest                   -- just set aside (its own line was written then): no margin
        elseif not nearest then
            pin = same
        else
            local near, far = sqrt(nearestD2), Yards(same, px, py, width, height)
            if near <= far * KEEP_RATIO and far - near >= KEEP_YARDS then
                why = "spot changed: another is nearer (" .. floor(near + 0.5) .. " yd against " .. floor(far + 0.5) .. " yd)"
            else
                pin = same
            end
        end
    end
    if why and PE.debugOn then PE:Debug(KEY, why) end
    return pin, count - skipped, skipped
end

local function PointingText(tracked, pin, playerMap, choices, skipped)
    local what = pin.obj and (" objective " .. pin.obj) or (pin.kind == "turnin" and " turn-in" or "")
    return "pointing at quest " .. tracked .. what .. " spot " .. format("%.1f,%.1f", pin.x * 100, pin.y * 100)
        .. " on map " .. playerMap .. " (nearest of " .. choices .. ", " .. skipped .. " set aside)"
end

local function Select(playerMap, px, py)
    S.selectDue = false
    S.sinceSelect = 0
    S.selX, S.selY = px, py
    S.map = playerMap

    -- The target before this pick, if it is a spot of this quest on this map.
    local old = S.pin
    local tracked = S.tracked
    if old and (old.questID ~= tracked or S.pinMap ~= playerMap) then old = nil end
    RefreshAside(tracked, playerMap)

    local pin = nil
    S.noFocus = not tracked
    if not tracked then
        SetMessage("No quest focused", CODE_GREY .. "Focus one in your quest log|r")
        -- While it is hidden for resting the "hidden" line says so; this one would alternate with it.
        if PE.debugOn and not HiddenForRest() then DebugState("text only: no quest focused") end
    else
        local byMap = QD:GetPinsForQuest(tracked)
        local pins = type(byMap) == "table" and byMap[playerMap]
        if type(pins) == "table" and pins[1] ~= nil then
            -- Here; if the map's size cannot be read there is no arrow and no message.
            S.msgBig = nil
            local width, height = QD:GetMapWorldSize(playerMap)
            local choices, skipped
            if width then
                pin, choices, skipped = Pick(pins, px, py, width, height, old)
                S.width, S.height = width, height
            end
            if PE.debugOn then
                DebugState(pin and PointingText(tracked, pin, playerMap, choices, skipped)
                    or ("hidden: quest " .. tracked .. ", size not readable of map " .. playerMap))
            end
        else
            local title = QuestTitle(tracked)
            if type(byMap) == "table" and HasPlaces(byMap) then
                local zone = ZoneName(BusiestMap(byMap))
                SetMessage("Outside this zone", zone and Line("Head to ", zone) or Line("Quest: ", title))
                if PE.debugOn then DebugState("text only: quest " .. tracked .. " has no spot on map " .. playerMap) end
            else
                SetMessage("No map data for this quest", Line("Quest: ", title))
                if PE.debugOn then DebugState("text only: quest " .. tracked .. " has no known location") end
            end
        end
    end

    S.pin = pin
    S.pinMap = pin and playerMap or nil
    PublishPin(pin)
    if pin then
        S.tx, S.ty = pin.x, pin.y
        S.force = true
        -- The same spot rebuilt as a new table keeps "Here" and the distance shown.
        if not (old and pin.x == old.x and pin.y == old.y and pin.obj == old.obj and pin.kind == old.kind) then
            S.here = false
            S.distCode = nil
            SetTitle(TitleFor(pin))
        end
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Paint(here)
    S.painted = here
    local c = here and COLOR_HERE or COLOR_ARROW
    if S.arrow then
        S.arrow:SetVertexColor(c[1], c[2], c[3], 1)
        return
    end
    for i = SHAPE_COUNT + 1, LINE_COUNT do
        lines[i]:SetColorTexture(c[1], c[2], c[3], 1)
    end
end

-- The top line: its text, in green for "Here" and gold otherwise. Only a
-- change is passed on to the game.
local function SetTop(text, green)
    if text ~= S.topText then
        S.topText = text
        S.distText:SetText(text)
    end
    green = green and true or false
    if green ~= S.topGreen then
        S.topGreen = green
        local c = green and COLOR_HERE or COLOR_ARROW
        S.distText:SetTextColor(c[1], c[2], c[3], 1)
    end
end

-- rel: radians counter-clockwise from "straight up".
local function DrawArrow(rel)
    S.rel = rel
    local step = floor(rel / STEP + 0.5) % ANGLE_STEPS
    if step == S.step then return end
    S.step = step
    local angle = step * STEP
    if S.arrow then
        S.arrow:SetRotation(angle)      -- counter-clockwise for positive radians, like `rel`
        return
    end
    local c, s = cos(angle), sin(angle)
    local box = S.box
    for i = 1, LINE_COUNT do
        local line = lines[i]
        local x1, y1, x2, y2 = gx1[i], gy1[i], gx2[i], gy2[i]
        line:SetStartPoint("CENTER", box, x1 * c - y1 * s, x1 * s + y1 * c)
        line:SetEndPoint("CENTER", box, x2 * c - y2 * s, x2 * s + y2 * c)
    end
end

local function ShowDistance(dist)
    local here = S.here
    if here then
        if dist > HERE_LEAVE then here = false end
    elseif dist < HERE_ENTER then
        here = true
    end
    if PE.debugOn and here ~= S.here then PE:Debug(KEY, here and "arrived at the spot" or "left the spot") end
    if S.here and not here then
        -- Reached and left: lead on to a spot not reached yet (the next pick skips this one).
        S.aside[PosKey(S.tx, S.ty)] = GetTime() + ASIDE_SECONDS
        S.selectDue = true
        if PE.debugOn then PE:Debug(KEY, "spot set aside for " .. ASIDE_SECONDS .. " s after being reached") end
    end
    S.here = here
    local code
    if here then
        code = -1
    elseif dist < 300 then
        code = floor(dist / 5 + 0.5) * 5
    else
        code = floor(dist / 10 + 0.5) * 10
    end
    if here ~= S.painted then Paint(here) end
    if code == S.distCode then return end
    S.distCode = code
    S.distLabel = here and "Here" or (code .. " yd")
end

-- Creates the frames once. Returns false if this client can neither turn a
-- texture nor draw lines.
local function Build()
    if S.built then return true end
    local UI = PE.UI
    if not S.display then
        local display = CreateFrame("Frame", nil, UIParent)
        display:Hide()
        -- The lowest layer: under every window, bar and unit frame, and under
        -- the dark backdrop of the full-screen world map, so the arrow never
        -- covers anything and needs no "is the map open" check.
        display:SetFrameStrata("BACKGROUND")
        display:EnableMouse(false)          -- display only: taps go straight through
        S.display = display
    end
    if not S.box then
        local box = CreateFrame("Frame", nil, S.display)
        box:EnableMouse(false)
        box:SetPoint("TOP", S.display, "TOP", 0, 0)
        S.box = box
    end
    if not S.arrow and not lines[1] and type(S.box.CreateTexture) == "function" then
        local tex = S.box:CreateTexture(nil, "ARTWORK")
        if tex and type(tex.SetRotation) == "function" then
            tex:SetTexture(ARROW_TEXTURE)
            tex:SetAllPoints(S.box)
            tex:SetVertexColor(COLOR_ARROW[1], COLOR_ARROW[2], COLOR_ARROW[3], 1)
            S.arrow = tex
        elseif tex then
            tex:Hide()
        end
    end
    if not S.arrow and type(S.box.CreateLine) ~= "function" then return false end
    for i = 1, S.arrow and 0 or LINE_COUNT do
        if not lines[i] then
            local outline = i <= SHAPE_COUNT
            local line = S.box:CreateLine(nil, "ARTWORK", nil, outline and 0 or 1)
            if not line then return false end
            if outline then
                line:SetColorTexture(0, 0, 0, 0.9)
            else
                line:SetColorTexture(COLOR_ARROW[1], COLOR_ARROW[2], COLOR_ARROW[3], 1)
            end
            lines[i] = line
        end
    end
    if not S.distText then
        local text = UI:CreateText(S.display, "title")
        text:SetJustifyH("CENTER")
        text:SetWordWrap(false)
        text:SetTextColor(COLOR_ARROW[1], COLOR_ARROW[2], COLOR_ARROW[3], 1)
        -- The face of the title font; its size is set by Layout from scale.
        local face, _, flags = text:GetFont()
        S.bigFace, S.bigFlags = face, flags
        S.distText = text
    end
    if not S.titleText then
        local text = UI:CreateText(S.display, "font")
        text:SetJustifyH("CENTER")
        text:SetJustifyV("TOP")
        text:SetWordWrap(true)       -- a long name continues on a second line
        if text.SetMaxLines then text:SetMaxLines(2) end
        text:SetTextColor(1, 1, 1, 1)
        local face, _, flags = text:GetFont()
        S.smallFace, S.smallFlags = face, flags
        S.titleText = text
    end
    if not S.driver then
        local driver = CreateFrame("Frame", nil, UIParent)
        driver:Hide()
        S.driver = driver
    end
    S.built = true
    return true
end

-- The text sits under the arrow box, or in its place while the box is
-- hidden (text-only messages), so messages show where the arrow would be.
local function PlaceDistText()
    S.distText:ClearAllPoints()
    if S.boxShown == false then
        S.distText:SetPoint("TOP", S.box, "TOP", 0, 0)
    else
        S.distText:SetPoint("TOP", S.box, "BOTTOM", 0, -(S.gap or 0))
    end
end

-- The sizes of the whole block (arrow box, top line and quest line) and
-- where it sits, offset included. Shared by Layout and by the "Move on screen"
-- outline, so the outline is right even before anything has been built.
-- Sized by scale only, not by Button size.
-- Returns box, width, height, point, relPoint, x, y, big, small, boxGap, lineGap.
local function Geometry()
    local UI = PE.UI
    local s = ScaleFactor()
    local box, width = UI:Px(BOX_PX * s), UI:Px(WIDTH_PX * s)
    local big, small = UI:Px(BIG_PX * s), UI:Px(SMALL_PX * s)
    local boxGap, lineGap = UI:Px(BOX_GAP_PX * s), UI:Px(LINE_GAP_PX * s)
    local pos = POSITIONS[Opt("position")] or POSITIONS.top
    local Move, dx, dy = PE.Move, 0, 0
    if Move and Move.GetOffset then dx, dy = Move:GetOffset(KEY) end
    -- The arrow, the top line, and room for two lines of quest name.
    local height = box + boxGap + big * 1.15 + lineGap + small * 2.3
    return box, width, height, pos[1], pos[2], UI:Px(pos[3]) + dx, UI:Px(pos[4]) + dy,
        big, small, boxGap, lineGap
end

-- Sets a text's size in its own face (from the font it was made with).
local function SetSize(text, face, flags, size)
    if type(face) ~= "string" or face == "" then return end
    pcall(text.SetFont, text, face, size, flags or "")
end

-- Sizes and position; also after a scale change, a move or the screen size changes.
local function Layout()
    if not S.built then return end
    local UI = PE.UI
    local box, width, height, point, relPoint, x, y, big, small, boxGap, lineGap = Geometry()

    S.box:SetSize(box, box)
    S.gap = boxGap
    SetSize(S.distText, S.bigFace, S.bigFlags, big)
    SetSize(S.titleText, S.smallFace, S.smallFlags, small)
    PlaceDistText()
    S.distText:SetWidth(width)
    S.titleText:ClearAllPoints()
    S.titleText:SetPoint("TOP", S.distText, "BOTTOM", 0, -lineGap)
    S.titleText:SetWidth(width)
    S.titleText:SetHeight(small * 2.4)    -- room for two lines

    S.display:SetSize(width, height)
    S.display:ClearAllPoints()
    S.display:SetPoint(point, UIParent, relPoint, x, y)

    -- Fallback only: line end points for the arrow pointing up. The outline
    -- copies are longer and thicker by `edge` all round.
    local half = box * 0.46
    local thick = max(box * 0.15, 2)
    local edge = max(UI:Px(2.5), 1)
    for i = 1, S.arrow and 0 or SHAPE_COUNT do
        local seg = SHAPE[i]
        local x1, y1, x2, y2 = seg[1] * half, seg[2] * half, seg[3] * half, seg[4] * half
        local dx, dy = x2 - x1, y2 - y1
        local len = sqrt(dx * dx + dy * dy)
        local ux, uy = dx / len * edge, dy / len * edge
        gx1[i], gy1[i], gx2[i], gy2[i] = x1 - ux, y1 - uy, x2 + ux, y2 + uy
        lines[i]:SetThickness(thick + edge * 2)
        local j = i + SHAPE_COUNT
        gx1[j], gy1[j], gx2[j], gy2[j] = x1, y1, x2, y2
        lines[j]:SetThickness(thick)
    end
    S.step = nil
    DrawArrow(S.rel or 0)
    S.force = true
end

---------------------------------------------------------------------------
-- The update
---------------------------------------------------------------------------

local function SetWhy(why)
    if S.why == why then return end
    S.why = why
    if mod then mod:RefreshPanel() end     -- does nothing unless the settings window is open
end

local function HideDisplay()
    if S.shown then
        S.shown = false
        S.display:Hide()
    end
end

local function Idle(why)
    S.interval = IDLE_INTERVAL
    PublishPin(nil)     -- not pointing while the position is unknown
    S.selectDue = true  -- choose (and publish) again when the position is back
    HideDisplay()
    SetWhy(why)
    if PE.debugOn then DebugState("hidden: position not readable") end
    return true
end

-- Stops the OnUpdate. keepDisplay leaves the text block on screen.
local function StopDriver(why, keepDisplay)
    if PE.debugOn then
        -- Only a real change is written: from showing an arrow to not showing one.
        if S.dbgArrow then PE:Debug(KEY, "driver stopped") end
        if why == "instance" then DebugState("stopped inside an instance") end
        if why == "failed" then DebugState("stopped after " .. MAX_FAILURES .. " errors in a row") end
    end
    S.running = false
    S.dbgArrow = false
    PublishPin(nil)     -- the arrow no longer points anywhere
    if S.driver then S.driver:Hide() end
    if not keepDisplay then HideDisplay() end
    SetWhy(why)
end

local function SetBoxShown(show)
    if S.boxShown ~= show then
        S.boxShown = show
        S.box:SetShown(show)
        PlaceDistText()
    end
end

-- "Turn around" takes the arrow away; the top line moves up into its place.
local function SetTurn(turn)
    S.turn = turn
    SetBoxShown(not turn)
end

-- Returns true when it ran to the end (the driver counts failures).
local function Update()
    local playerMap, px, py = QD:GetPlayerPosition()
    if not playerMap then return Idle("nopos") end
    local facing = QD:GetPlayerFacing()
    if not facing then return Idle("nopos") end

    if S.selectDue or playerMap ~= S.map
       or (S.sinceSelect >= SELECT_INTERVAL and (px ~= S.selX or py ~= S.selY)) then
        Select(playerMap, px, py)
    end

    if not S.pin then
        -- Nothing to point at for now. Stop completely; QuestData's
        -- "quests" / "zone" / "tracked" callbacks start the driver again.
        if S.msgBig then
            S.turn = false
            SetBoxShown(false)
            S.distCode = nil
            SetTop(S.msgBig, false)
            if HiddenForRest() then
                HideDisplay()
                if PE.debugOn then DebugState("hidden: no quest focused while resting") end
            elseif not S.shown then
                S.shown = true
                S.display:Show()
            end
            StopDriver(nil, true)
        else
            StopDriver("notarget")
        end
        return true
    end

    S.interval = ACTIVE_INTERVAL
    if not S.dbgArrow and PE.debugOn then
        S.dbgArrow = true
        PE:Debug(KEY, "driver started")     -- written when an arrow starts showing, not on every start
    end
    SetBoxShown(not S.turn)
    if not S.shown then
        S.shown = true
        S.force = true
        S.display:Show()
    end
    SetWhy(nil)
    if not S.force and px == S.px and py == S.py and facing == S.facing then return true end
    S.force = false
    S.px, S.py, S.facing = px, py, facing

    local east = (S.tx - px) * S.width
    local north = (py - S.ty) * S.height
    local dist = sqrt(east * east + north * north)
    ShowDistance(dist)
    if S.here then
        SetTurn(false)
    elseif dist >= MIN_AIM_YARDS then
        -- DEVICE CHECK: if the arrow swings the wrong way when you turn, flip the sign of `facing` here.
        local rel = (atan2(-east, north) - facing + PI) % TWO_PI - PI     -- -pi .. pi
        local behind = rel < 0 and -rel or rel
        if S.turn then
            SetTurn(behind > TURN_LEAVE)
        else
            SetTurn(behind > TURN_ENTER)
        end
        DrawArrow(rel)
    end
    if S.turn then
        SetTop("Turn around", false)
    else
        SetTop(S.distLabel or "", S.here)
    end
    return true
end

local SafeUpdate    -- Update inside the module's error catcher; set below

local function OnUpdate(_, elapsed)
    S.sinceSelect = S.sinceSelect + elapsed
    local acc = S.acc + elapsed
    if acc < S.interval then
        S.acc = acc
        return
    end
    S.acc = 0
    if SafeUpdate() == true then
        S.failures = 0
    else
        -- Something is wrong on this client. Do not keep failing 10 times a second.
        S.failures = S.failures + 1
        S.interval = IDLE_INTERVAL
        if S.failures >= MAX_FAILURES then
            S.failReason = "The arrow stopped after an error. Turn it off and on to try again."
            StopDriver("failed")
        end
    end
end

local function StartDriver()
    S.acc = IDLE_INTERVAL       -- update on the very next frame
    S.interval = ACTIVE_INTERVAL
    S.selectDue = true
    S.failures = 0
    S.running = true
    S.driver:Show()
end

local function InInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(IsInInstance)
    if not ok or IsSecret(inside) then return false end
    return inside and true or false
end

-- Decides whether the driver should be running at all.
local function Evaluate()
    if not S.ready or S.why == "failed" then return end
    if InInstance() then
        StopDriver("instance")
    elseif not S.running then
        if S.why == "instance" then S.why = nil end
        StartDriver()
    else
        S.selectDue = true
        S.acc = S.interval
    end
end

local function OnData(reason)
    if reason == "arrow" then return end    -- our own pin, nothing to choose again
    if not S.ready then return end
    S.tracked = QD:GetTrackedQuest()
    Evaluate()                  -- restarts a stopped driver, or asks a running one to choose again
end

local function OnWorldEvent()
    if S.ready then Evaluate() end
end

-- PLAYER_UPDATE_RESTING (registered only while the feature is on), and the
-- restHide choice: look again, so the message is hidden or shown at once.
local function OnResting()
    if S.ready then Evaluate() end
end

local function Relayout()
    if S.ready then Layout() end
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

local STATUS = {
    instance = "Hidden inside dungeons, raids and battlegrounds.",
    nopos = "Hidden: the game cannot tell where you are here.",
    notarget = "Hidden: the game cannot tell this zone's size.",
}

local SafeOnData, SafeOnUpdate, SafeOnResting

mod = PE:RegisterModule({
    key = KEY,
    label = "Quest arrow",
    desc = "Points to the nearest objective of your focused quest.",
    order = 20,
    requiresQuestieDB = true,
    defaults = { position = DEFAULTS.position, scale = DEFAULTS.scale, restHide = DEFAULTS.restHide },

    options = {
        { key = "scale", label = "Arrow and text size",
          number = { min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP, default = SCALE_DEFAULT,
                     suffix = "%", unit = "of normal" },
          OnChange = function() Relayout() end },
        { key = "restHide", label = "In cities and inns", help = "The \"No quest focused\" line.",
          choices = {
              { value = true, label = "Hide" },
              { value = false, label = "Show" },
          },
          OnChange = function() OnResting() end },
        { label = "Position on screen", button = "Move the arrow",
          action = function()
              if PE.Move and PE.Move.Open then PE.Move:Open(KEY) end
          end },
    },

    status = function(self)
        if not self:IsEnabled() then return nil end
        if S.failReason then return S.failReason end
        return STATUS[S.why]
    end,

    OnLoad = function(self)
        MigrateSize(self.opts)
        local UI = PE.UI
        if UI and UI.OnMetricsChanged then UI:OnMetricsChanged(self:Wrap(Relayout)) end
    end,

    OnEnable = function(self)
        S.failReason, S.why = nil, nil
        QD = PE.QuestData
        if type(QD) ~= "table" or type(QD.Acquire) ~= "function" then
            S.failReason = "Quest locations are not available."
            if PE.debugOn then PE:Debug(KEY, "not started: quest data did not load") end
            return
        end
        local ok, reason = QD:Acquire(KEY)
        if not ok then
            S.failReason = (type(reason) == "string" and reason ~= "") and reason or "Quest locations are not available."
            if PE.debugOn then PE:Debug(KEY, "not started: " .. S.failReason) end
            return
        end
        S.acquired = true
        if not Build() then
            S.failReason = "The arrow cannot be drawn on this version of the game."
            QD:Release(KEY)     -- nothing will be shown, so do not keep the quest data busy
            S.acquired = false
            if PE.debugOn then PE:Debug(KEY, "not started: the arrow cannot be drawn") end
            return
        end
        if not S.driver:GetScript("OnUpdate") then S.driver:SetScript("OnUpdate", SafeOnUpdate) end
        Layout()
        QD:OnChanged(KEY, SafeOnData)
        self:RegisterEvent("PLAYER_ENTERING_WORLD", OnWorldEvent)
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA", OnWorldEvent)
        -- Only while on; the core drops every event of the feature when it goes off.
        self:RegisterEvent("PLAYER_UPDATE_RESTING", SafeOnResting)
        S.tracked = QD:GetTrackedQuest()
        S.pin, S.pinMap, S.map, S.title, S.msgBig = nil, nil, nil, nil, nil
        S.titleText:SetText("")
        SetTop("", false)
        S.distCode, S.distLabel, S.here, S.turn, S.noFocus = nil, nil, false, false, false
        SetBoxShown(true)
        S.ready = true
        Evaluate()
    end,

    -- Also runs after a half-finished OnEnable, so every step checks first.
    OnDisable = function(self)
        S.ready = false
        if PE.debugOn and S.dbgArrow then PE:Debug(KEY, "driver stopped: feature off") end     -- pairs with "driver started"
        S.running = false
        S.dbgState, S.dbgArrow = nil, false
        if S.driver then S.driver:Hide() end
        if S.display then S.display:Hide() end
        S.shown = false
        local data = QD or PE.QuestData
        if type(data) == "table" then
            if data.SetArrowPin then data:SetArrowPin(nil) end      -- before the data is released
            if data.OnChanged then data:OnChanged(KEY, nil) end
            if data.Release then data:Release(KEY) end      -- harmless if it was never acquired
        end
        S.acquired = false
        S.pin, S.pinMap, S.map, S.tracked, S.msgBig = nil, nil, nil, nil, nil
        S.turn, S.noFocus = false, false
        S.why, S.failReason = nil, nil
        wipe(S.aside)
        S.asideQuest, S.asideMap = nil, nil
    end,
})

SafeUpdate = mod:Wrap(Update)
SafeOnUpdate = mod:Wrap(OnUpdate)
SafeOnData = mod:Wrap(OnData)
SafeOnResting = mod:Wrap(OnResting)

-- "Move on screen": the whole block can be nudged from the preset spot.
if PE.Move and PE.Move.Register then
    PE.Move:Register({
        key = KEY, label = "Quest arrow", order = 10,
        available = function() return mod ~= nil and mod:IsEnabled() end,
        apply = function() Layout() end,       -- does nothing until the frames are built
        reset = function()
            local o = mod and mod.opts
            if o then o.position = "top" end
        end,
        outline = function(box)
            local _, width, height, point, relPoint, x, y = Geometry()
            box:ClearAllPoints()
            box:SetPoint(point, UIParent, relPoint, x, y)
            box:SetSize(width, height)
        end,
    })
end
