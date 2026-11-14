local ADDON_NAME, PE = ...

-- QuestArrow: an arrow on the screen that points, in a straight line, to the
-- nearest objective of the quest you picked, with the distance and the quest
-- name under it.
--
-- Which objective (only pins on the map you are on are ever pointed at):
--   * A quest was picked (QuestData:GetTrackedQuest) and has known places:
--     its nearest pin on this map; if it has none on this map the arrow is
--     hidden and the text reads "Not in this zone" over the quest's name.
--   * No quest picked, or the picked one has no known place anywhere:
--     the nearest pin of any quest on this map.
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
-- The arrow is three thick solid-colour lines (plus a dark outline) whose end
-- points are computed here, so there is no art file that could be missing and
-- no texture rotation direction to get wrong.
--
-- Cost: one OnUpdate on a private driver frame, 10 times a second while an
-- arrow is showing and once a second while your position cannot be read. The
-- driver is stopped completely inside instances, while there is nothing to
-- point at (QuestData's callbacks start it again) and while the feature is off.

local type, pairs, pcall = type, pairs, pcall
local floor, sqrt, sin, cos, max, huge = math.floor, math.sqrt, math.sin, math.cos, math.max, math.huge
local atan2 = math.atan2
local strbyte, strsub = string.byte, string.sub

local KEY = "questArrow"

local ACTIVE_INTERVAL = 1 / 10      -- seconds between updates while the arrow is showing
local IDLE_INTERVAL = 1             -- ... while the position cannot be read
local SELECT_INTERVAL = 1           -- the nearest objective is re-chosen at most this often
local HERE_ENTER, HERE_LEAVE = 10, 14   -- yards: "Here" switches on below the first, off above the second
local MIN_AIM_YARDS = 3             -- closer than this the direction is noise; the arrow keeps its last angle
local ANGLE_STEPS = 180             -- the arrow turns in 2-degree steps
local STEP = 2 * math.pi / ANGLE_STEPS
local TITLE_MAX = 26                -- longer quest names are cut
local MAX_FAILURES = 5              -- the driver stops itself after this many errors in a row

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
local BOX_PX = { normal = 76, large = 112 }
local DEFAULTS = { position = "top", size = "normal" }

local COLOR_ARROW = { 1, 0.82, 0 }
local COLOR_HERE = { 0.35, 1, 0.45 }

-- The arrow pointing up, as fractions of half its length: x1, y1, x2, y2.
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
}
local lines = {}
local gx1, gy1, gx2, gy2 = {}, {}, {}, {}   -- line end points before turning, in UI units

local function IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, v)
    if not ok then return true end
    return secret and true or false
end

local function Opt(key)
    local opts = mod and mod.opts
    local value = type(opts) == "table" and opts[key] or nil
    if value == nil then value = DEFAULTS[key] end
    return value
end

---------------------------------------------------------------------------
-- Choosing the objective
---------------------------------------------------------------------------

local function Nearest(pins, px, py, width, height)
    local best, bestD2 = nil, huge
    for i = 1, #pins do
        local pin = pins[i]
        local x, y = pin.x, pin.y
        if type(x) == "number" and type(y) == "number" then
            local dx, dy = (x - px) * width, (y - py) * height
            local d2 = dx * dx + dy * dy
            if d2 < bestD2 then best, bestD2 = pin, d2 end
        end
    end
    return best
end

local function HasPlaces(byMap)
    for _, pins in pairs(byMap) do
        if type(pins) == "table" and pins[1] ~= nil then return true end
    end
    return false
end

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

local function TitleFor(pin)
    local title = pin.title
    if type(title) ~= "string" or title == "" then title = QD:GetQuestTitle(pin.questID) end
    if type(title) ~= "string" or title == "" then title = "Quest" end
    title = Shorten(title)
    if pin.kind == "turnin" then title = "Turn in: " .. title end
    return title
end

local function SetTitle(title)
    if title ~= S.title then
        S.title = title
        S.titleText:SetText(title)
    end
end

local function Select(playerMap, px, py)
    S.selectDue = false
    S.sinceSelect = 0
    S.selX, S.selY = px, py
    S.map = playerMap

    local old = S.pin
    local pin, elsewhere = nil, false
    local width, height = QD:GetMapWorldSize(playerMap)
    local tracked = S.tracked
    local byMap = tracked and QD:GetPinsForQuest(tracked) or nil
    if type(byMap) == "table" and HasPlaces(byMap) then
        -- The picked quest: this map only, never silently another quest.
        local pins = byMap[playerMap]
        if type(pins) == "table" and pins[1] ~= nil then
            if width then pin = Nearest(pins, px, py, width, height) end
        else
            elsewhere = true
        end
    elseif width then
        local pins = QD:GetPins(playerMap)
        if type(pins) == "table" then pin = Nearest(pins, px, py, width, height) end
    end

    S.pin, S.elsewhere = pin, elsewhere
    if pin then
        S.tx, S.ty, S.width, S.height = pin.x, pin.y, width, height
        S.force = true
        if pin ~= old then
            S.here = false
            S.distCode = nil
            SetTitle(TitleFor(pin))
        end
    elseif elsewhere then
        local title = QD:GetQuestTitle(tracked)
        if type(title) ~= "string" or title == "" then title = "Quest" end
        SetTitle(Shorten(title))
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Paint(here)
    S.painted = here
    local c = here and COLOR_HERE or COLOR_ARROW
    for i = SHAPE_COUNT + 1, LINE_COUNT do
        lines[i]:SetColorTexture(c[1], c[2], c[3], 1)
    end
end

-- rel: radians counter-clockwise from "straight up".
local function DrawArrow(rel)
    S.rel = rel
    local step = floor(rel / STEP + 0.5) % ANGLE_STEPS
    if step == S.step then return end
    S.step = step
    local angle = step * STEP
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
    S.distText:SetText(here and "Here" or (code .. " yd"))
end

-- Creates the frames once. Returns false if this client cannot draw lines.
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
    if type(S.box.CreateLine) ~= "function" then return false end
    for i = 1, LINE_COUNT do
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
        S.distText = text
    end
    if not S.titleText then
        local text = UI:CreateText(S.display, "font")
        text:SetJustifyH("CENTER")
        text:SetWordWrap(false)
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

-- Sizes and position; also after a preset or the screen size changes.
local function Layout()
    if not S.built then return end
    local UI = PE.UI
    local m = UI:Metrics()
    local box = UI:Px(BOX_PX[Opt("size")] or BOX_PX.normal)
    local gap = UI:Px(4)
    local fontSize = (type(m.fontSize) == "number" and m.fontSize > 0) and m.fontSize or UI:Px(25)
    local textWidth = max(UI:Px(280), fontSize * 13)

    S.box:SetSize(box, box)
    S.distText:ClearAllPoints()
    S.distText:SetPoint("TOP", S.box, "BOTTOM", 0, -gap)
    S.distText:SetWidth(textWidth)
    S.titleText:ClearAllPoints()
    S.titleText:SetPoint("TOP", S.distText, "BOTTOM", 0, -UI:Px(2))
    S.titleText:SetWidth(textWidth)

    local pos = POSITIONS[Opt("position")] or POSITIONS.top
    S.display:SetSize(textWidth, box + gap + fontSize * 2.6)
    S.display:ClearAllPoints()
    S.display:SetPoint(pos[1], UIParent, pos[2], UI:Px(pos[3]), UI:Px(pos[4]))

    -- Line end points for the arrow pointing up. The outline copies are
    -- longer and thicker by `edge` all round.
    local half = box * 0.46
    local thick = max(box * 0.15, 2)
    local edge = max(UI:Px(2.5), 1)
    for i = 1, SHAPE_COUNT do
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
    HideDisplay()
    SetWhy(why)
    return true
end

-- Stops the OnUpdate. keepDisplay leaves the text block on screen.
local function StopDriver(why, keepDisplay)
    S.running = false
    if S.driver then S.driver:Hide() end
    if not keepDisplay then HideDisplay() end
    SetWhy(why)
end

local function SetBoxShown(show)
    if S.boxShown ~= show then
        S.boxShown = show
        S.box:SetShown(show)
    end
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
        if S.elsewhere then
            SetBoxShown(false)
            S.distCode = nil
            S.distText:SetText("Not in this zone")
            if not S.shown then
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
    SetBoxShown(true)
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
    if dist >= MIN_AIM_YARDS then
        -- DEVICE CHECK: if the arrow swings the wrong way when you turn, flip the sign of `facing` here.
        DrawArrow(atan2(-east, north) - facing)
    end
    ShowDistance(dist)
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

local function OnData()
    if not S.ready then return end
    S.tracked = QD:GetTrackedQuest()
    Evaluate()                  -- restarts a stopped driver, or asks a running one to choose again
end

local function OnWorldEvent()
    if S.ready then Evaluate() end
end

local function Relayout()
    if S.ready then Layout() end
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

local STATUS = {
    instance = "Hidden while you are inside a dungeon.",
    nopos = "Hidden: the game cannot tell where you are here.",
    notarget = "Hidden: none of your quests has a known place in this zone.",
}

local SafeOnData, SafeOnUpdate

mod = PE:RegisterModule({
    key = KEY,
    label = "Quest arrow",
    desc = "Points to the nearest quest objective. Tap a quest icon to pick one.",
    order = 20,
    requiresQuestieDB = true,
    defaults = { position = DEFAULTS.position, size = DEFAULTS.size },

    options = {
        { key = "position", label = "Arrow position",
          choices = {
              { value = "top", label = "Top" },
              { value = "upper", label = "Upper middle" },
              { value = "lower", label = "Lower middle" },
              { value = "left", label = "Left" },
              { value = "right", label = "Right" },
          },
          OnChange = function() Relayout() end },
        { key = "size", label = "Arrow size",
          choices = {
              { value = "normal", label = "Normal" },
              { value = "large", label = "Large" },
          },
          OnChange = function() Relayout() end },
    },

    status = function(self)
        if not self:IsEnabled() then return nil end
        if S.failReason then return S.failReason end
        return STATUS[S.why]
    end,

    OnLoad = function(self)
        local UI = PE.UI
        if UI and UI.OnMetricsChanged then UI:OnMetricsChanged(self:Wrap(Relayout)) end
    end,

    OnEnable = function(self)
        S.failReason, S.why = nil, nil
        QD = PE.QuestData
        if type(QD) ~= "table" or type(QD.Acquire) ~= "function" then
            S.failReason = "Quest locations are not available."
            return
        end
        local ok, reason = QD:Acquire(KEY)
        if not ok then
            S.failReason = (type(reason) == "string" and reason ~= "") and reason or "Quest locations are not available."
            return
        end
        S.acquired = true
        if not Build() then
            S.failReason = "The arrow cannot be drawn on this version of the game."
            QD:Release(KEY)     -- nothing will be shown, so do not keep the quest data busy
            S.acquired = false
            return
        end
        if not S.driver:GetScript("OnUpdate") then S.driver:SetScript("OnUpdate", SafeOnUpdate) end
        Layout()
        QD:OnChanged(KEY, SafeOnData)
        self:RegisterEvent("PLAYER_ENTERING_WORLD", OnWorldEvent)
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA", OnWorldEvent)
        S.tracked = QD:GetTrackedQuest()
        S.pin, S.map, S.title, S.elsewhere = nil, nil, nil, false
        S.titleText:SetText("")
        S.distText:SetText("")
        S.distCode, S.here = nil, false
        S.ready = true
        Evaluate()
    end,

    -- Also runs after a half-finished OnEnable, so every step checks first.
    OnDisable = function(self)
        S.ready = false
        S.running = false
        if S.driver then S.driver:Hide() end
        if S.display then S.display:Hide() end
        S.shown = false
        local data = QD or PE.QuestData
        if type(data) == "table" then
            if data.OnChanged then data:OnChanged(KEY, nil) end
            if data.Release then data:Release(KEY) end      -- harmless if it was never acquired
        end
        S.acquired = false
        S.pin, S.map, S.tracked, S.elsewhere = nil, nil, nil, false
        S.why, S.failReason = nil, nil
    end,
})

SafeUpdate = mod:Wrap(Update)
SafeOnUpdate = mod:Wrap(OnUpdate)
SafeOnData = mod:Wrap(OnData)
