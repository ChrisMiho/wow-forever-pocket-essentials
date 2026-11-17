-- Pocket Essentials: Move things (PE.Move).
-- A small window of our own that nudges on-screen pieces (the round button,
-- and others that register here) with four arrow buttons. A press moves the
-- chosen piece 2 pixels; holding repeats and speeds up. Works by touch and
-- with the controller (the d-pad picks a button, A presses or holds it, B
-- closes). The game's Edit Mode is not used: every frame here is our own.
--
-- Each move is saved as an offset from the piece's preset spot, in pixels on
-- a 720-pixel-tall screen: PocketEssentialsDB.ui.moved[key] = { x =, y = }
-- (x right, y up). Nothing is built and nothing listens until the window is
-- first opened; nothing ticks unless an arrow button is being held.
--
-- A piece registers once, when its file loads:
--   PE.Move:Register({ key =, label =, order =, available = function() -> bool,
--       apply = function(), outline = function(box) })
--   apply() lays the real piece out again (its own layout adds the offset);
--   outline(box) places and sizes `box` exactly over where the piece sits,
--   whether the piece is showing or not.
-- A piece reads its offset in its own layout code, and works without this
-- file:  local dx, dy = 0, 0; if PE.Move and PE.Move.GetOffset then dx, dy = PE.Move:GetOffset(key) end
local ADDON_NAME, PE = ...

local Move = {}
PE.Move = Move

local type, tostring, ipairs, pairs, pcall, xpcall = type, tostring, ipairs, pairs, pcall, xpcall
local max, min, abs, format = math.max, math.min, math.abs, string.format

local PANEL_NAME = "PocketEssentialsMovePanel"
local OUTLINE_NAME = "PocketEssentialsMoveOutline"
local TITLE = "Move things"

local STEP = 2           -- pixels a press
local BIG_STEP = 6       -- pixels a step once held long enough
local HOLD_DELAY = 0.4   -- seconds held before it repeats
local REPEAT = 0.1       -- seconds between repeats (10 a second)
local BIG_AFTER = 1.5    -- seconds held before the steps grow
local SAFETY_STOP = 8    -- seconds: a hold stops by itself, in case the release never arrives
local LIMIT = 2000       -- saved offsets are read within -2000..2000 pixels
local TINY = 1e-6

local OUTLINE_COLOR = { 1, 0.82, 0 }

local pieces = {}        -- registered pieces, sorted by order
local byKey = {}

local UI, M
local panel, box, boxLabel, driver
local pieceButtons = {}  -- one per listed piece, reused
local arrows = {}        -- [label] = button
local resetButton
local navList = {}
local listed = {}        -- the pieces listed right now, in order
local selected           -- the selected piece (a def)
local corner = "RIGHT"   -- which bottom corner the window sits in
local built, buildFailed = false, false
local closeWhy

-- The hold in progress.
local holding = false
local holdDX, holdDY = 0, 0
local held, nextAt = 0, 0
local pressMoved, edgeLogged = false, false

local function Debug(text)
    if PE.debugOn then PE:Debug("move", text) end
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

local function ByOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.key < b.key
end

-- def = { key, label, order, available, apply, outline }; see the top of this file.
function Move:Register(def)
    if type(def) ~= "table" or type(def.key) ~= "string" or def.key == ""
            or type(def.outline) ~= "function" then
        return false
    end
    local entry = {
        key = def.key,
        label = type(def.label) == "string" and def.label or def.key,
        order = type(def.order) == "number" and def.order or 100,
        available = type(def.available) == "function" and def.available or nil,
        apply = type(def.apply) == "function" and def.apply or nil,
        outline = def.outline,
    }
    local old = byKey[entry.key]
    if old then
        for i = #pieces, 1, -1 do
            if pieces[i] == old then table.remove(pieces, i) end
        end
    end
    byKey[entry.key] = entry
    pieces[#pieces + 1] = entry
    table.sort(pieces, ByOrder)
    return true
end

local function IsAvailable(piece)
    if not piece.available then return true end
    local ok, yes = PE:Safe("core", piece.available)
    return ok and yes and true or false
end

local function Apply(piece)
    if piece and piece.apply then PE:Safe("core", piece.apply) end
end

---------------------------------------------------------------------------
-- Saved offsets (pixels on a 720-pixel-tall screen)
---------------------------------------------------------------------------

local function MovedTable(create)
    local ui = PE.db and PE.db.ui
    if type(ui) ~= "table" then return nil end
    if type(ui.moved) ~= "table" then
        if not create then return nil end
        ui.moved = {}
    end
    return ui.moved
end

local function GoodNumber(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- x, y in pixels; 0, 0 when missing or damaged.
local function ReadPixels(key)
    local moved = MovedTable(false)
    local entry = moved and moved[key]
    if type(entry) ~= "table" or not GoodNumber(entry.x) or not GoodNumber(entry.y) then return 0, 0 end
    return min(max(entry.x, -LIMIT), LIMIT), min(max(entry.y, -LIMIT), LIMIT)
end

-- Reuses the saved entry, so a step makes no new table.
local function WritePixels(key, x, y)
    local moved = MovedTable(true)
    if not moved then return end
    local entry = moved[key]
    if type(entry) ~= "table" then
        entry = {}
        moved[key] = entry
    end
    entry.x, entry.y = x, y
end

-- dx, dy in UI units, ready for SetPoint.
function Move:GetOffset(key)
    local x, y = ReadPixels(key)
    if x == 0 and y == 0 then return 0, 0 end
    local ui = PE.UI
    if not (ui and ui.Px) then return 0, 0 end
    return ui:Px(x), ui:Px(y)
end

---------------------------------------------------------------------------
-- The outline box and the window's corner
---------------------------------------------------------------------------

local function ScreenRect()
    local l, r, t, b = UIParent:GetLeft(), UIParent:GetRight(), UIParent:GetTop(), UIParent:GetBottom()
    if not (l and r and t and b) then
        l, b = 0, 0
        r, t = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
    end
    return l, r, t, b
end

-- How far the box sticks out of the screen (0 when wholly on it), or nil
-- when the game has no position for it yet.
local function Overflow()
    local l, r, t, b = box:GetLeft(), box:GetRight(), box:GetTop(), box:GetBottom()
    if not (l and r and t and b) then return nil end
    local sl, sr, st, sb = ScreenRect()
    return max(sl - l, 0) + max(r - sr, 0) + max(t - st, 0) + max(sb - b, 0)
end

-- The name above the box, or below it when there is no room above.
local function PlaceLabel()
    local gap = M.gap * 0.3
    local top = box:GetTop()
    local _, _, screenTop = ScreenRect()
    boxLabel:ClearAllPoints()
    if top and top + gap + M.fontSize * 1.3 > screenTop then
        boxLabel:SetPoint("TOP", box, "BOTTOM", 0, -gap)
    else
        boxLabel:SetPoint("BOTTOM", box, "TOP", 0, gap)
    end
end

local function PlaceOutline()
    if not (box and selected) then return false end
    local ok = PE:Safe("core", selected.outline, box)
    return ok
end

local function Overlaps(l, r, t, b)
    local bl, br, bt, bb = box:GetLeft(), box:GetRight(), box:GetTop(), box:GetBottom()
    if not (bl and br and bt and bb) or not box:IsShown() then return false end
    return bl < r - TINY and l < br - TINY and bb < t - TINY and b < bt - TINY
end

-- Bottom right unless the box is in the way there; then bottom left (if that is free).
local function PlaceCorner()
    if not panel then return end
    local margin = UI:Px(10)
    local w, h = panel.peWidth or 0, panel.peHeight or 0
    local sl, sr, _, sb = ScreenRect()
    local rightBusy = Overlaps(sr - margin - w, sr - margin, sb + margin + h, sb + margin)
    local leftBusy = Overlaps(sl + margin, sl + margin + w, sb + margin + h, sb + margin)
    if not rightBusy then
        corner = "RIGHT"
    elseif not leftBusy then
        corner = "LEFT"
    end
    panel:ClearAllPoints()
    if corner == "LEFT" then
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", margin, margin)
    else
        panel:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -margin, margin)
    end
end

local function ShowOutline()
    if not box then return end
    if selected and PlaceOutline() then
        boxLabel:SetText(selected.label)
        box:Show()
        PlaceLabel()
    else
        box:Hide()
    end
    PlaceCorner()
end

---------------------------------------------------------------------------
-- Moving
---------------------------------------------------------------------------

-- One step of the selected piece. Returns false when it was not taken.
local function Step(pixels)
    local piece = selected
    if not piece then return false end
    local key = piece.key
    local ox, oy = ReadPixels(key)
    local before = Overflow() or 0
    WritePixels(key, min(max(ox + holdDX * pixels, -LIMIT), LIMIT), min(max(oy + holdDY * pixels, -LIMIT), LIMIT))
    PlaceOutline()
    local after = Overflow()
    -- Off the screen: not taken, unless it brings back a piece that was
    -- already partly off (after a change of screen size).
    if after and after > TINY and after >= before - TINY then
        WritePixels(key, ox, oy)
        PlaceOutline()
        if not edgeLogged then
            edgeLogged = true
            Debug("stopped at the screen edge")
        end
        return false
    end
    pressMoved = true
    Apply(piece)
    PlaceLabel()
    PlaceCorner()
    return true
end

local function StopHold(why)
    if not holding then return end
    holding = false
    if driver then driver:Hide() end
    if why == "safety" then Debug("hold stopped after 8 s") end
    if pressMoved and selected then
        local x, y = ReadPixels(selected.key)
        Debug(format("%s now at %s,%s", selected.key, tostring(x), tostring(y)))
    end
end

local function StartHold(dx, dy)
    StopHold()
    if not (panel and panel:IsShown() and selected) then return end
    holdDX, holdDY = dx, dy
    held, nextAt = 0, HOLD_DELAY
    pressMoved, edgeLogged = false, false
    holding = true
    if Step(STEP) then
        driver:Show()
    end
end

local function DriverUpdate(_, elapsed)
    if not holding then
        driver:Hide()
        return
    end
    held = held + (type(elapsed) == "number" and elapsed or 0)
    if held + TINY >= SAFETY_STOP then
        StopHold("safety")
        return
    end
    -- At most a few steps in one frame, so a long stall does not jump.
    local steps = 0
    while holding and held + TINY >= nextAt and steps < 3 do
        steps = steps + 1
        nextAt = nextAt + REPEAT
        if not Step(held + TINY >= BIG_AFTER and BIG_STEP or STEP) then
            StopHold()
            return
        end
    end
    if held + TINY >= nextAt then nextAt = held + REPEAT end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Select(piece)
    if not piece then return end
    StopHold()
    selected = piece
    for i = 1, #pieceButtons do
        local btn = pieceButtons[i]
        btn:SetSelected(btn:IsShown() and btn.pePiece == piece)
    end
    Debug(piece.key .. " selected")
    ShowOutline()
end

local function Layout()
    M = UI:Metrics()
    local b, gap, pad = M.border, M.gap, M.pad
    local bh = M.button
    local pieceWidth = bh * 3.4
    local cell = bh * 1.8
    local crossWidth = cell * 3 + gap * 2
    local rows = max(#listed, 3)
    local contentHeight = max(rows * bh + (rows - 1) * gap, 3 * bh + 2 * gap)
    local width = pad * 2 + pieceWidth + gap * 2 + crossWidth
    local titleHeight = bh + gap
    local height = b + titleHeight + gap + contentHeight + pad
    panel:SetPanelSize(width, height)

    local content = panel.content
    for i = 1, #pieceButtons do
        local btn = pieceButtons[i]
        btn:ClearAllPoints()
        if i <= #listed then
            btn:SetSize(pieceWidth, bh)
            btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * (bh + gap))
        end
    end
    local x0 = pieceWidth + gap * 2
    local function Cell(btn, col, row)
        btn:ClearAllPoints()
        btn:SetSize(cell, bh)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", x0 + col * (cell + gap), -row * (bh + gap))
    end
    Cell(arrows.Up, 1, 0)
    Cell(arrows.Left, 0, 1)
    Cell(resetButton, 1, 1)
    Cell(arrows.Right, 2, 1)
    Cell(arrows.Down, 1, 2)

    if box then
        local t = max(UI:Px(3), 2)
        local e = box.peEdges
        e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", box, "TOPLEFT", -t, t); e[1]:SetPoint("TOPRIGHT", box, "TOPRIGHT", t, t); e[1]:SetHeight(t)
        e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -t, -t); e[2]:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", t, -t); e[2]:SetHeight(t)
        e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", box, "TOPLEFT", -t, t); e[3]:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -t, -t); e[3]:SetWidth(t)
        e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", box, "TOPRIGHT", t, t); e[4]:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", t, -t); e[4]:SetWidth(t)
    end
end

-- The list of available pieces, the buttons and the controller's reading order.
local function Fill()
    for i = #listed, 1, -1 do listed[i] = nil end
    for i = 1, #pieces do
        if IsAvailable(pieces[i]) then listed[#listed + 1] = pieces[i] end
    end
    for i = 1, #listed do
        local btn = pieceButtons[i]
        if not btn then
            btn = UI:CreateButton(panel.content, "")
            btn:SetScript("OnClick", PE:Wrap("core", function(self) Select(self.pePiece) end))
            pieceButtons[i] = btn
        end
        btn.pePiece = listed[i]
        btn:SetLabel(listed[i].label)
        btn:Show()
    end
    for i = #listed + 1, #pieceButtons do
        pieceButtons[i].pePiece = nil
        pieceButtons[i]:Hide()
    end
    for i = #navList, 1, -1 do navList[i] = nil end
    for i = 1, #listed do navList[#navList + 1] = pieceButtons[i] end
    navList[#navList + 1] = arrows.Up
    navList[#navList + 1] = arrows.Left
    navList[#navList + 1] = resetButton
    navList[#navList + 1] = arrows.Right
    navList[#navList + 1] = arrows.Down
    navList[#navList + 1] = panel.closeButton
    Layout()
end

local function Reset()
    if not selected then return end
    StopHold()
    Move:ClearOffset(selected.key)
    Debug(selected.key .. " reset")
end

local function OnHidden()
    StopHold()
    if box then box:Hide() end
    PE:UnregisterCoreEvent("PLAYER_REGEN_DISABLED", "move")
    Debug("panel closed (" .. (closeWhy or "B, Escape or another window") .. ")")
    closeWhy = nil
end

-- An arrow button: touch uses its own mouse down and up, the controller its
-- peHold hook (UI.lua navigation). A click with no press before it (not from
-- a finger) still nudges once.
local function MakeArrow(label, dx, dy)
    local btn = UI:CreateButton(panel.content, label)
    btn.peHold = {
        start = function() StartHold(dx, dy) end,
        stop = function() StopHold() end,
    }
    btn:HookScript("OnMouseDown", PE:Wrap("core", function(self)
        self.peTouched = true
        StartHold(dx, dy)
    end))
    btn:HookScript("OnMouseUp", PE:Wrap("core", function() StopHold() end))
    btn:HookScript("OnHide", PE:Wrap("core", function(self)
        self.peTouched = nil
        StopHold()
    end))
    btn:SetScript("OnClick", PE:Wrap("core", function(self)
        if self.peTouched then
            self.peTouched = nil
            return
        end
        StartHold(dx, dy)
        StopHold()
    end))
    arrows[label] = btn
    return btn
end

local function Build()
    UI = PE.UI
    M = UI:Metrics()

    driver = CreateFrame("Frame", nil, UIParent)
    driver:Hide()
    driver:SetScript("OnUpdate", PE:Wrap("core", DriverUpdate))

    box = CreateFrame("Frame", OUTLINE_NAME, UIParent)
    box:Hide()
    box:SetFrameStrata("FULLSCREEN") -- above the pieces and our windows; it takes no taps
    box:EnableMouse(false)
    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(box)
    fill:SetColorTexture(OUTLINE_COLOR[1], OUTLINE_COLOR[2], OUTLINE_COLOR[3], 0.15)
    box.peEdges = {}
    for i = 1, 4 do
        local edge = box:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(OUTLINE_COLOR[1], OUTLINE_COLOR[2], OUTLINE_COLOR[3], 1)
        box.peEdges[i] = edge
    end
    boxLabel = box:CreateFontString(nil, "OVERLAY", M.titleFont)
    if not boxLabel:GetFont() and GameFontNormalLarge then boxLabel:SetFontObject(GameFontNormalLarge) end
    boxLabel:SetTextColor(OUTLINE_COLOR[1], OUTLINE_COLOR[2], OUTLINE_COLOR[3], 1)
    boxLabel:SetWordWrap(false)

    panel = UI:CreatePanel(PANEL_NAME, TITLE, UI:Px(600), UI:Px(300))
    panel.closeButton:SetScript("OnClick", PE:Wrap("core", function() Move:Close("Close") end))
    MakeArrow("Up", 0, 1)
    MakeArrow("Down", 0, -1)
    MakeArrow("Left", -1, 0)
    MakeArrow("Right", 1, 0)
    resetButton = UI:CreateButton(panel.content, "Reset")
    resetButton:SetScript("OnClick", PE:Wrap("core", Reset))

    UI:AttachNav(panel, function() return navList end)
    panel:HookScript("OnHide", PE:Wrap("core", OnHidden))

    UI:OnMetricsChanged(PE:Wrap("core", function()
        if not built then return end
        Layout()
        if panel:IsShown() then ShowOutline() end
    end))
end

local function OnFight()
    StopHold()
    Move:Close("fight started")
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function Move:Open()
    if PE:InCombat() then
        Debug("not opened: in a fight")
        PE:Print("Move things cannot be opened during a fight. Try again afterwards.")
        return false
    end
    if not built and not buildFailed then
        if PE.UI and PE:Safe("core", Build) then
            built = true
        else
            buildFailed = true
            if panel then pcall(panel.Hide, panel) end
            if box then pcall(box.Hide, box) end
        end
    end
    if not built then
        PE:Print("Move things could not be opened. See Errors in the settings.")
        return false
    end
    -- Never on top of another Pocket Essentials window.
    PE:CloseSettings()
    if type(UISpecialFrames) == "table" then
        for _, name in ipairs(UISpecialFrames) do
            local other = type(name) == "string" and name:find("^PocketEssentials") and _G[name]
            if other and other ~= panel and other.IsShown and other:IsShown() then pcall(other.Hide, other) end
        end
    end
    Fill()
    selected = nil
    corner = "RIGHT"
    PE:RegisterCoreEvent("PLAYER_REGEN_DISABLED", "move", OnFight)
    if not panel:IsShown() then panel:Show() end
    panel:Raise()
    Debug("panel opened")
    if listed[1] then
        Select(listed[1])
    else
        ShowOutline()
    end
    panel:NavRefresh()
    return true
end

function Move:Close(why)
    StopHold()
    if built and panel:IsShown() then
        closeWhy = type(why) == "string" and why or nil
        panel:Hide()
    end
end

function Move:IsOpen()
    return built and panel:IsShown() or false
end

-- Back to the preset spot. Used by Reset and when a preset is chosen.
function Move:ClearOffset(key)
    local moved = MovedTable(false)
    if not (moved and moved[key] ~= nil) then return end
    if holding and selected and selected.key == key then StopHold() end
    moved[key] = nil
    local piece = byKey[key]
    Apply(piece)
    if built and panel:IsShown() and selected == piece then ShowOutline() end
end
