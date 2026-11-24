-- Pocket Essentials: Move on screen (PE.Move).
-- A small window of our own that nudges on-screen pieces (the round button,
-- and others that register here) with four arrow buttons. Every registered
-- piece is listed; one whose helper is off reads "<name> (off)", is dimmed
-- and a tap on it does nothing. A press moves the
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
--       apply = function(), outline = function(box), reset = function() })
--   available() says whether the piece's helper is on (missing: always);
--   apply() lays the real piece out again (its own layout adds the offset);
--   reset() (optional) also puts back the piece's chosen preset spot when the
--   window's Reset is pressed;
--   outline(box) places and sizes `box` exactly over where the piece sits,
--   whether the piece is showing or not.
-- A piece reads its offset in its own layout code, and works without this
-- file:  local dx, dy = 0, 0; if PE.Move and PE.Move.GetOffset then dx, dy = PE.Move:GetOffset(key) end
--
-- Opened while the setup guide is showing, the guide goes away and comes back
-- on the same screen when this window closes (Setup:BackFromMove).
local ADDON_NAME, PE = ...

local Move = {}
PE.Move = Move

local type, tostring, ipairs, pairs, pcall, xpcall = type, tostring, ipairs, pairs, pcall, xpcall
local max, min, abs, floor, format = math.max, math.min, math.abs, math.floor, string.format

local PANEL_NAME = "PocketEssentialsMovePanel"
local OUTLINE_NAME = "PocketEssentialsMoveOutline"
local TITLE = "Move on screen"

local STEP = 2           -- pixels a press
local BIG_STEP = 6       -- pixels a step once held long enough
local HOLD_DELAY = 0.4   -- seconds held before it repeats
local REPEAT = 0.1       -- seconds between repeats (10 a second)
local BIG_AFTER = 1.5    -- seconds held before the steps grow
local SAFETY_STOP = 8    -- seconds: a hold stops by itself, in case the release never arrives
local LIMIT = 2000       -- saved offsets are read within -2000..2000 pixels
local TINY = 1e-6

local OUTLINE_COLOR = { 1, 0.82, 0 }

-- Pieces with a Size row under the cross while they are picked: the piece key
-- (also its feature's key) and the key of that feature's number option.
local SIZE_OPTION = { questArrow = "scale" }

local pieces = {}        -- registered pieces, sorted by order
local byKey = {}

local UI, M
local panel, box, boxLabel, driver
local pieceButtons = {}  -- one per listed piece, reused
local arrows = {}        -- [label] = button
local resetButton
local sizeLabel, sizeNumber -- the Size row (SIZE_OPTION)
local probe              -- a hidden frame that Move:PieceRect places like the outline
local backToGuide = false -- the setup guide was open when this window opened
local backToSettings = false -- the settings window was open when this window opened
local SETTINGS_NAME = "PocketEssentialsSettingsPanel" -- Settings.lua's window
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
local pressMoved, edgeLogged, checkLogged = false, false, false

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
        reset = type(def.reset) == "function" and def.reset or nil,
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
    local moved = MovedTable(false)
    local hadEntry = moved and moved[key] ~= nil
    local before = Overflow() or 0
    WritePixels(key, min(max(ox + holdDX * pixels, -LIMIT), LIMIT), min(max(oy + holdDY * pixels, -LIMIT), LIMIT))
    local placed = PlaceOutline()
    local after = placed and Overflow()
    if not after then
        -- The box could not be placed, so the step cannot be checked
        -- against the screen edge: not taken.
        if hadEntry then WritePixels(key, ox, oy) else MovedTable(true)[key] = nil end
        PlaceOutline()
        if not checkLogged then
            checkLogged = true
            Debug(key .. " could not be checked against the screen edge")
        end
        return false
    end
    -- Off the screen: not taken, unless it brings back a piece that was
    -- already partly off (after a change of screen size).
    if after > TINY and after >= before - TINY then
        if hadEntry then WritePixels(key, ox, oy) else MovedTable(true)[key] = nil end
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

-- byItself: the hold ended here, not by a release (the 8-second stop, the
-- screen edge): the controller navigation forgets its press too.
local function StopHold(why, byItself)
    if not holding then return end
    holding = false
    if driver then driver:Hide() end
    if byItself and UI and UI.NavHoldEnded then UI:NavHoldEnded() end
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
    pressMoved, edgeLogged, checkLogged = false, false, false
    holding = true
    if Step(STEP) then
        driver:Show()
    else
        StopHold(nil, true) -- refused at once: no hold is left behind
    end
end

local function DriverUpdate(_, elapsed)
    if not holding then
        driver:Hide()
        return
    end
    held = held + (type(elapsed) == "number" and elapsed or 0)
    if held + TINY >= SAFETY_STOP then
        StopHold("safety", true)
        return
    end
    -- At most a few steps in one frame, so a long stall does not jump.
    local steps = 0
    while holding and held + TINY >= nextAt and steps < 3 do
        steps = steps + 1
        nextAt = nextAt + REPEAT
        if not Step(held + TINY >= BIG_AFTER and BIG_STEP or STEP) then
            StopHold(nil, true)
            return
        end
    end
    if held + TINY >= nextAt then nextAt = held + REPEAT end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- The Size row of a piece: its feature, the number option and the value
-- shown now. nil when the piece has none.
local function SizeRow(piece)
    local optKey = piece and SIZE_OPTION[piece.key]
    if not optKey then return nil end
    local mod = PE:GetModule(piece.key)
    if not (mod and type(mod.opts) == "table" and type(mod.options) == "table") then return nil end
    for _, opt in ipairs(mod.options) do
        local n = type(opt) == "table" and opt.number
        if opt.key == optKey and type(n) == "table" and type(n.min) == "number" and type(n.max) == "number" then
            local v = mod.opts[optKey]
            if type(v) ~= "number" or v ~= floor(v) or v < n.min or v > n.max then
                v = type(n.default) == "number" and n.default or n.min
            end
            return mod, opt, v
        end
    end
    return nil
end

local QueueNav -- defined below

-- One step of the Size row: saved in the feature's options, applied through
-- the option's own OnChange, then the outline follows.
local function SizeStep(dir)
    local mod, opt, v = SizeRow(selected)
    if not mod then return end
    local n = opt.number
    local step = (type(n.step) == "number" and n.step > 0) and n.step or 1
    local new = min(max(v + dir * step, n.min), n.max)
    if new == v then return end
    local before = box and PlaceOutline() and Overflow()
    mod.opts[opt.key] = new
    if type(opt.OnChange) == "function" then PE:Safe(mod.key, opt.OnChange, mod, new) end
    -- A bigger size that pushes the piece further off the screen is not
    -- taken: the old size is put back.
    local after = before and PlaceOutline() and Overflow()
    if after and after > TINY and after > before + TINY then
        mod.opts[opt.key] = v
        if type(opt.OnChange) == "function" then PE:Safe(mod.key, opt.OnChange, mod, v) end
        PlaceOutline()
        Debug(format("%s size %s not taken: off the screen", mod.key, tostring(new)))
        return
    end
    Debug(format("%s size %s", mod.key, tostring(new)))
    QueueNav()
    if PE.RefreshSettings then PE:RefreshSettings() end
end

-- Sets up the Size row's control for the picked piece. False when it has none.
local function FillSize()
    local mod, opt, v = SizeRow(selected)
    if not mod then return false end
    local n = opt.number
    sizeNumber.peBox = {
        text = tostring(v) .. (n.suffix or ""),
        unit = n.unit,
        down = v > n.min and PE:Wrap("core", function() SizeStep(-1) end) or nil,
        up = v < n.max and PE:Wrap("core", function() SizeStep(1) end) or nil,
        noStep = function() end,
    }
    return true
end

local function Select(piece)
    if not piece or not IsAvailable(piece) then return end
    StopHold()
    selected = piece
    for i = 1, #pieceButtons do
        local btn = pieceButtons[i]
        btn:SetSelected(btn:IsShown() and btn.pePiece == piece)
    end
    Debug(piece.key .. " selected")
    QueueNav()
end

-- Returns true when the Size row shows.
local function Layout()
    M = UI:Metrics()
    local b, gap, pad = M.border, M.gap, M.pad
    local bh = M.button
    local pieceWidth = bh * 4.2
    local cell = bh * 1.8
    local crossWidth = cell * 3 + gap * 2
    local rows = max(#listed, 3)
    local sized = FillSize()
    local contentHeight = rows * bh + (rows - 1) * gap + (sized and (bh + gap) or 0)
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

    -- The Size row: under the cross, its name beside it in the pieces column.
    if sized then
        local y = rows * (bh + gap)
        sizeNumber:ClearAllPoints()
        sizeNumber:SetPoint("TOPLEFT", content, "TOPLEFT", x0, -y)
        sizeNumber:Set(crossWidth, sizeNumber.peBox)
        sizeNumber:Show()
        sizeLabel:SetWidth(pieceWidth)
        sizeLabel:SetText("Size")
        local h = UI:TextHeight(sizeLabel, "font")
        sizeLabel:ClearAllPoints()
        sizeLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + max((bh - h) * 0.5, 0)))
        sizeLabel:Show()
    else
        sizeNumber:Hide()
        sizeLabel:Hide()
    end

    if box then
        local t = max(UI:Px(3), 2)
        local e = box.peEdges
        e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", box, "TOPLEFT", -t, t); e[1]:SetPoint("TOPRIGHT", box, "TOPRIGHT", t, t); e[1]:SetHeight(t)
        e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -t, -t); e[2]:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", t, -t); e[2]:SetHeight(t)
        e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", box, "TOPLEFT", -t, t); e[3]:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -t, -t); e[3]:SetWidth(t)
        e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", box, "TOPRIGHT", t, t); e[4]:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", t, -t); e[4]:SetWidth(t)
    end
    return sized
end

-- The controller's reading order: the pieces that can be picked, the cross,
-- the Size row's two ends while it shows, Close.
local function NavFill(sized)
    for i = #navList, 1, -1 do navList[i] = nil end
    for i = 1, #listed do
        local btn = pieceButtons[i]
        if not btn.peOff then navList[#navList + 1] = btn end
    end
    navList[#navList + 1] = arrows.Up
    navList[#navList + 1] = arrows.Left
    navList[#navList + 1] = resetButton
    navList[#navList + 1] = arrows.Right
    navList[#navList + 1] = arrows.Down
    if sized then
        navList[#navList + 1] = sizeNumber.peMinus
        navList[#navList + 1] = sizeNumber.pePlus
    end
    navList[#navList + 1] = panel.closeButton
end

-- After a pick or a size step: the panel's size, the outline, the d-pad list.
QueueNav = function()
    if not built then return end
    local sized = Layout()
    NavFill(sized)
    if panel:IsShown() then
        ShowOutline()
        panel:NavRefresh()
    end
end

-- Every registered piece, in order, and its button. A piece whose helper is
-- off reads "<name> (off)", is dimmed, and a tap on it does nothing.
local function Fill()
    for i = #listed, 1, -1 do listed[i] = nil end
    for i = 1, #pieces do listed[#listed + 1] = pieces[i] end
    for i = 1, #listed do
        local btn = pieceButtons[i]
        if not btn then
            btn = UI:CreateButton(panel.content, "")
            btn:SetScript("OnClick", PE:Wrap("core", function(self)
                if self.peOff then return end
                Select(self.pePiece)
            end))
            pieceButtons[i] = btn
        end
        local on = IsAvailable(listed[i])
        btn.pePiece = listed[i]
        btn.peOff = not on
        btn:SetLabel(on and listed[i].label or (listed[i].label .. " (off)"))
        btn:SetStyle(on and "normal" or "disabled")
        btn:SetSelected(false)
        btn:Show()
    end
    for i = #listed + 1, #pieceButtons do
        pieceButtons[i].pePiece = nil
        pieceButtons[i]:Hide()
    end
    NavFill(Layout())
end

local function Reset()
    if not selected then return end
    StopHold()
    local piece = selected
    Move:ClearOffset(piece.key)
    if piece.reset then
        PE:Safe("core", piece.reset)
        Apply(piece)
        if built and panel:IsShown() and selected == piece then ShowOutline() end
    end
    Debug(selected.key .. " reset")
end

-- The setup guide comes back one frame later, so a window that closed this
-- one by opening is on the screen by then and the guide stays away.
local function GuideBack()
    local Setup = PE.Setup
    if Setup and Setup.BackFromMove then Setup:BackFromMove() end
end

local function SettingsShown()
    local settings = rawget(_G, SETTINGS_NAME)
    return type(settings) == "table" and settings.IsShown and settings:IsShown() or false
end

-- Another of our windows (one that closed this one by opening) is on the
-- screen by then: the settings stay away. Not in a fight.
local function SettingsBack()
    if PE:InCombat() then return end
    if type(UISpecialFrames) == "table" then
        for _, name in ipairs(UISpecialFrames) do
            local other = type(name) == "string" and name:find("^PocketEssentials") and _G[name]
            if other and other.IsShown and other:IsShown() then return end
        end
    end
    PE:OpenSettings()
end

local function OnHidden()
    StopHold()
    if box then box:Hide() end
    PE:UnregisterCoreEvent("PLAYER_REGEN_DISABLED", "move")
    Debug("panel closed (" .. (closeWhy or "B, Escape or another window") .. ")")
    local byFight = closeWhy == "fight started"
    closeWhy = nil
    if backToSettings then
        backToSettings = false
        if not byFight then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, PE:Wrap("core", SettingsBack))
            else
                PE:Safe("core", SettingsBack)
            end
        end
    end
    if backToGuide then
        backToGuide = false
        if C_Timer and C_Timer.After then
            C_Timer.After(0, PE:Wrap("core", GuideBack))
        else
            PE:Safe("core", GuideBack)
        end
    end
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
    sizeLabel = UI:CreateText(panel.content, "font")
    sizeLabel:SetTextColor(0.92, 0.92, 0.92, 1)
    sizeLabel:Hide()
    sizeNumber = UI:CreateNumber(panel.content)
    sizeNumber:Hide()

    UI:AttachNav(panel, function() return navList end)
    panel:HookScript("OnHide", PE:Wrap("core", OnHidden))

    UI:OnMetricsChanged(PE:Wrap("core", function()
        if not built then return end
        QueueNav()
    end))
end

local function OnFight()
    StopHold()
    Move:Close("fight started")
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- key (optional): the piece to select when the window opens, if it is
-- registered and its helper is on; otherwise the round button.
function Move:Open(key)
    if PE:InCombat() then
        Debug("not opened: in a fight")
        PE:Print("Move on screen cannot be opened during a fight. Try again afterwards.")
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
        PE:Print("Move on screen could not be opened. See Settings > Errors.")
        return false
    end
    -- From the setup guide: it goes away now and comes back when this closes.
    local Setup = PE.Setup
    local fromGuide = Setup and Setup.IsOpen and Setup:IsOpen() or false
    if fromGuide then PE:Safe("core", Setup.Close, Setup, "move") end
    backToGuide = fromGuide or (backToGuide and panel:IsShown())
    -- From the settings: the same, on the tab it was showing.
    backToSettings = not backToGuide and (SettingsShown() or (backToSettings and panel:IsShown()))
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
    local want = type(key) == "string" and byKey[key] or nil
    if want and not IsAvailable(want) then want = byKey.hub end
    if not (want and IsAvailable(want)) then
        want = nil
        for i = 1, #listed do
            if not want and IsAvailable(listed[i]) then want = listed[i] end
        end
    end
    if want then
        Select(want)
    else
        QueueNav()
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

-- The registered pieces, in order: { { key =, label =, on = bool }, ... }.
function Move:Pieces()
    local out = {}
    for i = 1, #pieces do
        out[i] = { key = pieces[i].key, label = pieces[i].label, on = IsAvailable(pieces[i]) }
    end
    return out
end

-- Where a piece sits now, whether it is showing or not: left, bottom, width,
-- height in UIParent's units. nil when it cannot be worked out.
function Move:PieceRect(key)
    local piece = byKey[key]
    if not piece then return nil end
    if not probe then
        probe = CreateFrame("Frame", nil, UIParent)
        probe:EnableMouse(false)
        probe:SetAlpha(0)
    end
    probe:Hide()
    if not PE:Safe("core", piece.outline, probe) then return nil end
    -- Shown for the reading only (fully see-through), so the game works out its place.
    probe:Show()
    local l, r, t, b = probe:GetLeft(), probe:GetRight(), probe:GetTop(), probe:GetBottom()
    probe:Hide()
    if not (l and r and t and b) then return nil end
    return l, b, r - l, t - b
end
