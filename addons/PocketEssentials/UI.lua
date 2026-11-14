-- Pocket Essentials: UI kit (PE.UI).
-- Sizes, big touch buttons, panels, a scroll area with big paging buttons and
-- controller (d-pad) navigation. Everything is drawn with solid colours, so it
-- does not depend on any game art.
local ADDON_NAME, PE = ...

local UI = {}
PE.UI = UI

local type, pairs, ipairs, pcall, xpcall, tostring = type, pairs, ipairs, pcall, xpcall, tostring
local max, min, abs, sqrt = math.max, math.min, math.abs, math.sqrt

local function Handler()
    return PE.ErrorHandlerFor and PE.ErrorHandlerFor("core") or function(err) return err end
end

---------------------------------------------------------------------------
-- Sizes. All numbers below are pixels on a 720-pixel-tall screen.
---------------------------------------------------------------------------

local PRESETS = {
    small  = { row = 56, button = 48, gap = 8,  pad = 12, font = 22, small = 18, hub = 56 },
    medium = { row = 66, button = 56, gap = 10, pad = 14, font = 25, small = 20, hub = 60 },
    large  = { row = 80, button = 68, gap = 12, pad = 16, font = 29, small = 23, hub = 72 },
}

local factor -- UI units (for a scale-1 child of UIParent) per 720p pixel

-- The screen is always 768 units tall at effective scale 1 (see
-- Blizzard_SharedXML/PixelUtil.lua), so a 720p pixel is 768/720 units divided
-- by UIParent's effective scale. The result is a fixed fraction of the screen
-- height: the same physical size at 720p and 1080p, whatever the UI scale.
local function ComputeFactor()
    local parent = UIParent
    if parent then
        local ok, scale = pcall(parent.GetEffectiveScale, parent)
        if ok and type(scale) == "number" and scale > 0.05 then
            return 768 / (720 * scale)
        end
        local ok2, height = pcall(parent.GetHeight, parent)
        if ok2 and type(height) == "number" and height > 100 then
            return height / 720
        end
    end
    return 768 / 720
end

function UI:Px(n)
    if not factor then factor = ComputeFactor() end
    return (n or 0) * factor
end

---------------------------------------------------------------------------
-- Fonts: our own Font objects so the text size follows the size preset.
---------------------------------------------------------------------------

local FONT_NAMES = {
    font = "PocketEssentialsFont",
    small = "PocketEssentialsFontSmall",
    title = "PocketEssentialsFontTitle",
}
local FONT_FALLBACK = {
    font = "GameFontHighlightLarge",
    small = "GameFontHighlight",
    title = "GameFontNormalLarge",
}
local FONT_COLOR = {
    font = { 1, 1, 1 },
    small = { 0.84, 0.84, 0.84 },
    title = { 1, 0.82, 0 },
}
local fontObjects = {}
local fontFile, fontFlags

local function SetupFonts(preset)
    if not fontFile then
        local source = GameFontHighlightLarge or GameFontNormalLarge or GameFontNormal
        if source and source.GetFont then
            local ok, file, _, flags = pcall(source.GetFont, source)
            if ok and type(file) == "string" and file ~= "" then
                fontFile = file
                fontFlags = type(flags) == "string" and flags or ""
            end
        end
        if not fontFile then
            fontFile = (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
            fontFlags = ""
        end
    end
    local sizes = { font = preset.font, small = preset.small, title = preset.font * 1.12 }
    local names = {}
    for key, name in pairs(FONT_NAMES) do
        local object = fontObjects[key]
        if object == nil and CreateFont then
            local ok, created = pcall(CreateFont, name)
            object = (ok and created) or false
            fontObjects[key] = object
            if object then
                local c = FONT_COLOR[key]
                pcall(object.SetTextColor, object, c[1], c[2], c[3], 1)
                pcall(object.SetShadowColor, object, 0, 0, 0, 1)
                pcall(object.SetShadowOffset, object, 1, -1)
            end
        end
        local good = false
        if object then
            local ok, result = pcall(object.SetFont, object, fontFile, UI:Px(sizes[key]), fontFlags)
            good = ok and result ~= false and object:GetFont() ~= nil
        end
        if good then
            names[key] = name
        else
            fontObjects[key] = false
            names[key] = FONT_FALLBACK[key]
        end
    end
    return names
end

---------------------------------------------------------------------------
-- Metrics
---------------------------------------------------------------------------

local metrics = {}
local metricsBuilt = false
local metricsCallbacks = {}
local panels = setmetatable({}, { __mode = "k" })

local function BuildMetrics()
    local size = PE.db and PE.db.ui and PE.db.ui.size
    local preset = PRESETS[size] or PRESETS.medium
    local names = SetupFonts(preset)
    metrics.size = PRESETS[size] and size or "medium"
    metrics.row = UI:Px(preset.row)
    metrics.button = UI:Px(preset.button)
    metrics.gap = UI:Px(preset.gap)
    metrics.pad = UI:Px(preset.pad)
    metrics.hub = UI:Px(preset.hub)
    metrics.border = max(UI:Px(2), 1)
    metrics.font = names.font
    metrics.smallFont = names.small
    metrics.titleFont = names.title
    metrics.fontSize = UI:Px(preset.font)
    metrics.smallFontSize = UI:Px(preset.small)
    metricsBuilt = true
end

-- The same table is updated in place when the preset or the screen changes.
function UI:Metrics()
    if not metricsBuilt then BuildMetrics() end
    return metrics
end

function UI:OnMetricsChanged(fn)
    if type(fn) == "function" then metricsCallbacks[#metricsCallbacks + 1] = fn end
end

-- Recompute everything and tell the panels. force=true after a preset change.
function UI:Refresh(force)
    local newFactor = ComputeFactor()
    if not force and metricsBuilt and factor and abs(newFactor - factor) < 0.0005 then return end
    factor = newFactor
    BuildMetrics()
    local handler = Handler()
    for panel in pairs(panels) do
        if panel.peLayout then xpcall(panel.peLayout, handler, panel) end
    end
    for i = 1, #metricsCallbacks do xpcall(metricsCallbacks[i], handler) end
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

-- kind: "font" (default), "small" or "title". Left-aligned, wraps.
function UI:CreateText(parent, kind, layer)
    local m = self:Metrics()
    local fontName = (kind == "small" and m.smallFont) or (kind == "title" and m.titleFont) or m.font
    local text = parent:CreateFontString(nil, layer or "OVERLAY", fontName)
    if not text:GetFont() and GameFontHighlight then text:SetFontObject(GameFontHighlight) end
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    return text
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

local STYLES = {
    normal   = { fill = { 0.15, 0.16, 0.19 }, border = { 0.52, 0.52, 0.57 }, text = { 1, 1, 1 } },
    on       = { fill = { 0.07, 0.40, 0.13 }, border = { 0.35, 0.92, 0.45 }, text = { 1, 1, 1 } },
    off      = { fill = { 0.25, 0.25, 0.27 }, border = { 0.52, 0.52, 0.54 }, text = { 0.82, 0.82, 0.82 } },
    warn     = { fill = { 0.52, 0.28, 0.03 }, border = { 1.00, 0.62, 0.15 }, text = { 1, 1, 1 } },
    disabled = { fill = { 0.11, 0.11, 0.12 }, border = { 0.27, 0.27, 0.29 }, text = { 0.50, 0.50, 0.50 } },
}
local SELECTED = { fill = { 0.56, 0.42, 0.03 }, border = { 1, 0.82, 0 }, text = { 1, 1, 1 } }
local FOCUS = { 0.25, 0.92, 1.00 }

local function Paint(btn)
    local c = (btn.peSelected and SELECTED) or STYLES[btn.peStyle] or STYLES.normal
    btn.peBorder:SetColorTexture(c.border[1], c.border[2], c.border[3], 1)
    btn.peFill:SetColorTexture(c.fill[1], c.fill[2], c.fill[3], 1)
    btn.peText:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
    local inset = UI:Metrics().border * (btn.peSelected and 2 or 1)
    btn.peFill:ClearAllPoints()
    btn.peFill:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
    btn.peFill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
end

local function BuildFlash(btn)
    local group = btn.pePush:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.3)
    group:SetToFinalAlpha(true)
    group:SetScript("OnFinished", function() btn.pePush:Hide() end)
    return group
end

local function ButtonDown(btn)
    if btn.peFlash then btn.peFlash:Stop() end
    btn.pePush:SetAlpha(1)
    btn.pePush:Show()
end

local function ButtonUp(btn)
    if btn.peFlash == nil then
        local ok, group = pcall(BuildFlash, btn)
        btn.peFlash = (ok and group) or false
    end
    if btn.peFlash and btn:IsVisible() then
        btn.pePush:SetAlpha(1)
        btn.pePush:Show()
        btn.peFlash:Stop()
        btn.peFlash:Play()
    else
        btn.pePush:Hide()
    end
end

local function ButtonHidden(btn)
    if btn.peFlash then btn.peFlash:Stop() end
    btn.pePush:Hide()
end

local ButtonMethods = {}

function ButtonMethods:SetLabel(text)
    self.peText:SetText(text == nil and "" or tostring(text))
end

function ButtonMethods:GetLabel()
    return self.peText:GetText() or ""
end

-- Marks the current choice: gold fill and a thicker gold border.
function ButtonMethods:SetSelected(selected)
    selected = selected and true or false
    if self.peSelected ~= selected then
        self.peSelected = selected
        Paint(self)
    end
end

-- "normal", "on" (green), "off" (grey), "warn" (amber) or "disabled" (dim; still tappable).
function ButtonMethods:SetStyle(style)
    if not STYLES[style] then style = "normal" end
    if self.peStyle ~= style then
        self.peStyle = style
        Paint(self)
    end
end

-- The controller highlight: a thick bright blue outline.
function ButtonMethods:SetNavFocus(focused)
    local ring = self.peFocus
    if not ring then
        if not focused then return end
        ring = {}
        for i = 1, 4 do
            ring[i] = self:CreateTexture(nil, "OVERLAY", nil, 6)
            ring[i]:SetColorTexture(FOCUS[1], FOCUS[2], FOCUS[3], 1)
        end
        self.peFocus = ring
    end
    if focused then
        local t = max(UI:Px(5), 2)
        ring[1]:ClearAllPoints()
        ring[1]:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        ring[1]:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
        ring[1]:SetHeight(t)
        ring[2]:ClearAllPoints()
        ring[2]:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
        ring[2]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        ring[2]:SetHeight(t)
        ring[3]:ClearAllPoints()
        ring[3]:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        ring[3]:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
        ring[3]:SetWidth(t)
        ring[4]:ClearAllPoints()
        ring[4]:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
        ring[4]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        ring[4]:SetWidth(t)
    end
    for i = 1, 4 do ring[i]:SetShown(focused and true or false) end
end

-- A small red badge with white text at the top-right corner; nil hides it.
function ButtonMethods:SetBadgeText(text)
    local badge = self.peBadge
    if text == nil or text == "" then
        if badge then badge:Hide() end
        return
    end
    local m = UI:Metrics()
    if not badge then
        badge = CreateFrame("Frame", nil, self)
        badge:SetFrameLevel(self:GetFrameLevel() + 2)
        badge.bg = badge:CreateTexture(nil, "BACKGROUND")
        badge.bg:SetAllPoints(badge)
        badge.bg:SetColorTexture(0.85, 0.08, 0.08, 1)
        badge.text = badge:CreateFontString(nil, "OVERLAY", m.smallFont)
        badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
        badge.text:SetTextColor(1, 1, 1, 1)
        self.peBadge = badge
    end
    text = tostring(text)
    badge.text:SetText(text)
    local height = m.smallFontSize * 1.25
    badge:SetSize(max(height, m.smallFontSize * 0.62 * #text + m.smallFontSize * 0.5), height)
    badge:ClearAllPoints()
    badge:SetPoint("TOPRIGHT", self, "TOPRIGHT", m.border, m.border)
    badge:Show()
end

-- Brief "pressed" flash, for clicks that did not come from a tap.
function ButtonMethods:Flash()
    ButtonUp(self)
end

-- Sets the width to fit the label. Returns the new width.
function ButtonMethods:FitWidth(minWidth, maxWidth)
    local m = UI:Metrics()
    local label = self.peText
    local ok, width = pcall(label.GetUnboundedStringWidth, label)
    if not ok or type(width) ~= "number" or width <= 0 then
        width = #(label:GetText() or "") * m.fontSize * 0.55
    end
    width = width + m.pad * 2
    width = max(width, minWidth or m.button * 1.6)
    if maxWidth then width = min(width, maxWidth) end
    self:SetWidth(width)
    return width
end

function UI:CreateButton(parent, text, width, height)
    local m = self:Metrics()
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or m.button * 3, height or m.button)

    btn.peBorder = btn:CreateTexture(nil, "BACKGROUND")
    btn.peBorder:SetAllPoints(btn)
    btn.peFill = btn:CreateTexture(nil, "BORDER")
    btn.pePush = btn:CreateTexture(nil, "ARTWORK")
    btn.pePush:SetAllPoints(btn)
    btn.pePush:SetColorTexture(1, 1, 1, 0.3)
    btn.pePush:Hide()

    local label = btn:CreateFontString(nil, "OVERLAY", m.font)
    if not label:GetFont() and GameFontHighlight then label:SetFontObject(GameFontHighlight) end
    label:SetPoint("LEFT", btn, "LEFT", m.gap * 0.5, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -m.gap * 0.5, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    btn.peText = label

    for name, fn in pairs(ButtonMethods) do btn[name] = fn end
    btn.peStyle = "normal"
    btn.peSelected = false
    Paint(btn)
    btn:SetLabel(text)

    -- Touch has no hover, so the feedback is a bright flash while pressed
    -- that fades out just after the finger lifts.
    btn:SetScript("OnMouseDown", ButtonDown)
    btn:SetScript("OnMouseUp", ButtonUp)
    btn:SetScript("OnHide", ButtonHidden)
    return btn
end

---------------------------------------------------------------------------
-- A disc drawn from thin solid strips (round look without any art file)
---------------------------------------------------------------------------

function UI:CreateDisc(parent, layer, sublevel, stripCount)
    local disc = { strips = {}, count = stripCount or 20 }
    for i = 1, disc.count do
        disc.strips[i] = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    end

    function disc:SetColor(r, g, b, a)
        for i = 1, self.count do self.strips[i]:SetColorTexture(r, g, b, a or 1) end
    end

    -- Centre the disc on `anchor` with the given diameter.
    function disc:Layout(anchor, diameter)
        local n, radius = self.count, diameter / 2
        local stripHeight = diameter / n
        for i = 1, n do
            local y = radius - (i - 0.5) * stripHeight
            local half = sqrt(max(radius * radius - y * y, 0))
            local strip = self.strips[i]
            strip:ClearAllPoints()
            strip:SetSize(max(half * 2, 0.01), stripHeight * 1.12)
            strip:SetPoint("CENTER", anchor, "CENTER", 0, y)
        end
    end

    function disc:SetShown(shown)
        for i = 1, self.count do self.strips[i]:SetShown(shown and true or false) end
    end

    return disc
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

local function PanelLayout(panel)
    local m = UI:Metrics()
    local b = m.border
    local titleHeight = m.button + m.gap
    local top = b + titleHeight + m.gap

    panel.peFill:ClearAllPoints()
    panel.peFill:SetPoint("TOPLEFT", panel, "TOPLEFT", b, -b)
    panel.peFill:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -b, b)

    local close = panel.closeButton
    close:SetSize(m.button * 2, m.button)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(b + m.gap * 0.5), -(b + m.gap * 0.5))

    panel.peTitle:ClearAllPoints()
    panel.peTitle:SetPoint("LEFT", panel, "TOPLEFT", m.pad, -(b + titleHeight * 0.5))
    panel.peTitle:SetPoint("RIGHT", close, "LEFT", -m.gap, 0)

    panel.peLine:ClearAllPoints()
    panel.peLine:SetPoint("TOPLEFT", panel, "TOPLEFT", b, -(b + titleHeight))
    panel.peLine:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -b, -(b + titleHeight))
    panel.peLine:SetHeight(b)

    panel.content:ClearAllPoints()
    panel.content:SetPoint("TOPLEFT", panel, "TOPLEFT", m.pad, -top)
    panel.content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -m.pad, m.pad)

    -- Known without waiting for the game to lay the frame out.
    panel.contentWidth = max((panel.peWidth or 0) - m.pad * 2, 1)
    panel.contentHeight = max((panel.peHeight or 0) - top - m.pad, 1)
end

function UI:CreatePanel(globalName, title, width, height)
    local m = self:Metrics()
    local panel = CreateFrame("Frame", globalName, UIParent)
    panel:Hide()
    panel:SetFrameStrata("DIALOG") -- not toplevel: a tap on it must not bury a game popup
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true) -- taps must not fall through to the game world
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    panel.peBorderTex = panel:CreateTexture(nil, "BACKGROUND")
    panel.peBorderTex:SetAllPoints(panel)
    panel.peBorderTex:SetColorTexture(0.62, 0.52, 0.22, 1)
    panel.peFill = panel:CreateTexture(nil, "BORDER")
    panel.peFill:SetColorTexture(0.05, 0.05, 0.07, 1)
    panel.peLine = panel:CreateTexture(nil, "ARTWORK")
    panel.peLine:SetColorTexture(0.62, 0.52, 0.22, 1)

    panel.peTitle = panel:CreateFontString(nil, "OVERLAY", m.titleFont)
    if not panel.peTitle:GetFont() and GameFontNormalLarge then panel.peTitle:SetFontObject(GameFontNormalLarge) end
    panel.peTitle:SetJustifyH("LEFT")
    panel.peTitle:SetWordWrap(false)

    panel.closeButton = self:CreateButton(panel, "Close")
    panel.closeButton:SetScript("OnClick", function() panel:Hide() end)

    panel.content = CreateFrame("Frame", nil, panel)

    function panel:SetTitle(text)
        self.peTitle:SetText(text == nil and "" or tostring(text))
    end

    -- Use this instead of SetSize so contentWidth/contentHeight stay right.
    function panel:SetPanelSize(newWidth, newHeight)
        self.peWidth, self.peHeight = newWidth, newHeight
        self:SetSize(newWidth, newHeight)
        PanelLayout(self)
    end

    -- Placeholders so these always exist; AttachNav replaces them.
    function panel:NavRefresh() end
    function panel:NavSetFocus() end

    panel.peLayout = PanelLayout
    panel:SetTitle(title)
    panel:SetPanelSize(width or self:Px(900), height or self:Px(600))
    panels[panel] = true

    -- Escape (and the game's own "close windows" key) hides it.
    if type(globalName) == "string" and type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, globalName)
    end
    return panel
end

---------------------------------------------------------------------------
-- Scroll area: a clipped list with two big paging buttons on the right.
--   local area = PE.UI:CreateScrollArea(parent); area:SetPoint(...)
--   area:Layout(width, height)      -- call again when sizes change
--   put content in area.child (its width is area.viewWidth), then
--   area:SetContentHeight(totalHeight)
---------------------------------------------------------------------------

local AreaMethods = {}

function AreaMethods:GetRange()
    return max(self.contentHeight - self.viewHeight, 0)
end

function AreaMethods:ScrollTo(offset)
    local range = self:GetRange()
    offset = min(max(offset or 0, 0), range)
    self.offset = offset
    self.scrollFrame:SetVerticalScroll(offset)
    self.upButton:SetStyle(offset > 0.5 and "normal" or "disabled")
    self.downButton:SetStyle(offset < range - 0.5 and "normal" or "disabled")
end

function AreaMethods:ScrollBy(delta)
    self:ScrollTo(self.offset + (delta or 0))
end

function AreaMethods:PageUp()
    self:ScrollBy(-max(self.viewHeight - UI:Metrics().row, UI:Metrics().row))
end

function AreaMethods:PageDown()
    self:ScrollBy(max(self.viewHeight - UI:Metrics().row, UI:Metrics().row))
end

-- top/bottom are distances from the top of area.child (positive, downwards).
function AreaMethods:EnsureVisible(top, bottom)
    if type(top) ~= "number" or type(bottom) ~= "number" then return end
    local margin = UI:Metrics().gap
    if bottom - top > self.viewHeight - margin * 2 then bottom = top + self.viewHeight - margin * 2 end
    if top - margin < self.offset then
        self:ScrollTo(top - margin)
    elseif bottom + margin > self.offset + self.viewHeight then
        self:ScrollTo(bottom + margin - self.viewHeight)
    end
end

-- For any shown frame placed somewhere inside area.child.
function AreaMethods:ScrollIntoView(frame)
    if not frame then return end
    if frame.peScrollTop and frame.peScrollBottom then
        self:EnsureVisible(frame.peScrollTop, frame.peScrollBottom)
        return
    end
    local childTop = self.child:GetTop()
    local top, bottom = frame:GetTop(), frame:GetBottom()
    if childTop and top and bottom then self:EnsureVisible(childTop - top, childTop - bottom) end
end

function AreaMethods:SetContentHeight(height)
    self.contentHeight = max(height or 0, 1)
    self.child:SetHeight(self.contentHeight)
    self:ScrollTo(self.offset)
end

function AreaMethods:Layout(width, height)
    local m = UI:Metrics()
    local column = m.button * 1.4
    width, height = max(width or 0, column + m.gap + 10), max(height or 0, 10)
    self.viewWidth = width - column - m.gap
    self.viewHeight = height
    self:SetSize(width, height)
    self.scrollFrame:ClearAllPoints()
    self.scrollFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.scrollFrame:SetSize(self.viewWidth, self.viewHeight)
    self.child:SetWidth(self.viewWidth)
    local buttonHeight = max((height - m.gap) / 2, 1)
    self.upButton:ClearAllPoints()
    self.upButton:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
    self.upButton:SetSize(column, buttonHeight)
    self.downButton:ClearAllPoints()
    self.downButton:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    self.downButton:SetSize(column, buttonHeight)
    self:ScrollTo(self.offset)
end

function UI:CreateScrollArea(parent)
    local area = CreateFrame("Frame", nil, parent)
    area.scrollFrame = CreateFrame("ScrollFrame", nil, area)
    area.child = CreateFrame("Frame", nil, area.scrollFrame)
    area.child:SetSize(10, 10)
    area.scrollFrame:SetScrollChild(area.child)
    area.offset, area.contentHeight, area.viewWidth, area.viewHeight = 0, 1, 10, 10

    area.upButton = self:CreateButton(area, "Up")
    area.downButton = self:CreateButton(area, "Down")
    for name, fn in pairs(AreaMethods) do area[name] = fn end
    area.upButton:SetScript("OnClick", function() area:PageUp() end)
    area.downButton:SetScript("OnClick", function() area:PageDown() end)

    -- No wheel on the handheld; this is for testing on a desktop.
    area.scrollFrame:EnableMouseWheel(true)
    area.scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        area:ScrollBy(-(delta or 0) * UI:Metrics().row)
    end)
    return area
end

---------------------------------------------------------------------------
-- Controller navigation.
-- While a panel is shown and the player is out of combat, the d-pad and the
-- A / B buttons are pointed (temporary override bindings owned by the panel)
-- at one hidden button of ours. Cleared when the panel hides and when combat
-- starts. Blizzard's own gamepad navigation is never touched.
---------------------------------------------------------------------------

local NAV_NAME = "PocketEssentialsNavButton"
local NAV_KEYS = { PADDUP = "UP", PADDDOWN = "DOWN", PADDLEFT = "LEFT", PADDRIGHT = "RIGHT", PAD1 = "A", PAD2 = "B" }

local navShown = {}  -- nav panels that are shown, most recently shown last
local navOwner       -- the panel whose bindings are armed (at most one)
local navDown = {}   -- [key] = true while we have seen that key go down
local navButton, navEventsReady

local function NavList(panel)
    local ok, list = xpcall(panel.peNavGet, Handler())
    return (ok and type(list) == "table") and list or {}
end

local function IndexOf(list, item)
    if item == nil then return nil end
    for i = 1, #list do
        if list[i] == item then return i end
    end
end

local function RowY(btn)
    local ok, _, y = pcall(btn.GetCenter, btn)
    return ok and y or nil
end

-- Same line = same parent frame and (nearly) the same height on screen.
local function SameRow(a, b)
    if a == b then return true end
    if a.GetParent and b.GetParent and a:GetParent() ~= b:GetParent() then return false end
    local ya, yb = RowY(a), RowY(b)
    return ya ~= nil and yb ~= nil and abs(ya - yb) < UI:Metrics().button * 0.4
end

local function NavFocus(panel, btn, index)
    local old = panel.peNavFocus
    if old and old ~= btn and old.SetNavFocus then old:SetNavFocus(false) end
    panel.peNavFocus, panel.peNavIndex = btn, index
    if btn then
        if btn.SetNavFocus then btn:SetNavFocus(true) end
        if type(panel.navOnFocus) == "function" then xpcall(panel.navOnFocus, Handler(), btn) end
    end
end

-- step = -1 / +1. byRow (up/down) skips the other buttons on the same line.
local function NavMove(panel, step, byRow)
    local list = NavList(panel)
    local n = #list
    if n == 0 then return NavFocus(panel, nil) end
    local current = IndexOf(list, panel.peNavFocus)
    local index = current
    if not current then
        index = step > 0 and 1 or n
    else
        for _ = 1, n do
            index = index + step
            if index < 1 then index = n elseif index > n then index = 1 end
            if not byRow or index == current or not SameRow(list[index], list[current]) then break end
        end
        if byRow and step < 0 then -- land on the first button of that line
            while index > 1 and SameRow(list[index - 1], list[index]) do index = index - 1 end
        end
    end
    NavFocus(panel, list[index], index)
end

local function NavActivate(panel)
    local btn = panel.peNavFocus
    if not btn or not IndexOf(NavList(panel), btn) then return NavMove(panel, 1) end
    if btn.IsEnabled and not btn:IsEnabled() then return end
    local onClick = btn:GetScript("OnClick")
    if onClick then
        if btn.Flash then btn:Flash() end
        xpcall(onClick, Handler(), btn, "LeftButton", false)
    end
    if panel:IsShown() and panel.NavRefresh then panel:NavRefresh() end
end

local function NavPress(_, key, down)
    local panel = navOwner
    if not panel or not panel:IsShown() then return end
    if down ~= false then
        navDown[key] = true
        if key == "UP" then NavMove(panel, -1, true)
        elseif key == "DOWN" then NavMove(panel, 1, true)
        elseif key == "LEFT" then NavMove(panel, -1, false)
        elseif key == "RIGHT" then NavMove(panel, 1, false)
        end
        return
    end
    -- A and B act on release, and only if we also saw the press: a release
    -- whose press went to the game (or to a Blizzard window) is not ours.
    local sawPress = navDown[key]
    navDown[key] = nil
    if not sawPress then return end
    if key == "A" then
        NavActivate(panel)
    elseif key == "B" then
        panel:Hide()
    end
end

-- Only call out of combat, or from PLAYER_REGEN_DISABLED (lockdown starts after it).
local function NavDisarm(panel)
    for key in pairs(navDown) do navDown[key] = nil end
    if panel.peNavArmed then
        if ClearOverrideBindings then pcall(ClearOverrideBindings, panel) end
        panel.peNavArmed = false
    end
    if navOwner == panel then navOwner = nil end
end

-- Sets the six keys once. If a Blizzard window takes them back afterwards
-- (its own navigation binds the same keys, and the latest one wins), we leave
-- it alone: touch keeps working and the keys are ours again the next time
-- this panel is shown.
local function NavArm(panel)
    if not (SetOverrideBindingClick and ClearOverrideBindings) then return false end
    if PE:InCombat() or not panel:IsShown() then return false end
    if navOwner and navOwner ~= panel then NavDisarm(navOwner) end
    if not navButton then
        navButton = CreateFrame("Button", NAV_NAME, UIParent)
        navButton:SetSize(1, 1)
        navButton:RegisterForClicks("AnyDown", "AnyUp")
        navButton:SetScript("OnClick", function(self, key, down)
            xpcall(NavPress, Handler(), self, key, down)
        end)
    end
    for key in pairs(navDown) do navDown[key] = nil end
    pcall(ClearOverrideBindings, panel)
    for key, name in pairs(NAV_KEYS) do
        pcall(SetOverrideBindingClick, panel, true, key, NAV_NAME, name)
    end
    panel.peNavArmed = true
    navOwner = panel
    return true
end

local function NavRemoveShown(panel)
    for i = #navShown, 1, -1 do
        if navShown[i] == panel then table.remove(navShown, i) end
    end
end

local function NavOnShow(panel)
    NavRemoveShown(panel)
    navShown[#navShown + 1] = panel
    NavList(panel) -- lets the caller build its list; nothing is highlighted until the d-pad is used
    NavArm(panel) -- does nothing in combat; touch still works
end

local function NavOnHide(panel)
    NavRemoveShown(panel)
    -- Release the keys first, whatever else goes wrong afterwards.
    if panel.peNavArmed then
        if PE:InCombat() then
            -- Cannot happen normally (combat start already cleared them).
            PE:RunOutOfCombat(panel, function()
                if not panel:IsShown() then NavDisarm(panel) end
            end)
        else
            NavDisarm(panel)
        end
    end
    pcall(NavFocus, panel, nil)
    local top = navShown[#navShown]
    if top and not navOwner then NavArm(top) end
end

local function NavCombatEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        local panel = navOwner
        if panel then
            NavDisarm(panel)
            pcall(NavFocus, panel, nil) -- no highlight while the controller cannot drive it
        end
    else -- PLAYER_REGEN_ENABLED
        local top = navShown[#navShown]
        if top and top:IsShown() then NavArm(top) end
    end
end

function UI:AttachNav(panel, getButtons)
    if type(panel) ~= "table" or type(getButtons) ~= "function" then return panel end
    panel.peNavGet = getButtons

    -- Re-read getButtons() after the caller changed the layout.
    function panel:NavRefresh()
        local list = NavList(self)
        if self.peNavFocus and not IndexOf(list, self.peNavFocus) then
            -- The highlighted button went away: move to whatever took its place.
            local index = min(self.peNavIndex or 1, #list)
            NavFocus(self, list[index], index)
        end
    end

    -- Move the highlight to one of the buttons getButtons() returns (nil clears it).
    function panel:NavSetFocus(btn)
        local index = IndexOf(NavList(self), btn)
        NavFocus(self, index and btn or nil, index)
    end

    if not navEventsReady then
        navEventsReady = true
        PE:RegisterCoreEvent("PLAYER_REGEN_DISABLED", "nav", NavCombatEvent)
        PE:RegisterCoreEvent("PLAYER_REGEN_ENABLED", "nav", NavCombatEvent)
    end
    panel:HookScript("OnShow", function(self) xpcall(NavOnShow, Handler(), self) end)
    panel:HookScript("OnHide", function(self) xpcall(NavOnHide, Handler(), self) end)
    if panel:IsShown() then xpcall(NavOnShow, Handler(), panel) end
    return panel
end

---------------------------------------------------------------------------
-- Keep sizes right when the screen or the UI scale changes
---------------------------------------------------------------------------

if PE.OnCoreLogin then
    PE:OnCoreLogin(function() UI:Refresh(true) end)
end
if PE.RegisterCoreEvent then
    local pending = false
    local function Apply()
        pending = false
        UI:Refresh(true)
    end
    -- Wait a moment so UIParent already has its new size, and fold a burst
    -- of these events into one pass.
    local function ScreenChanged()
        if pending or not PE.loggedIn then return end
        if C_Timer and C_Timer.After then
            pending = true
            C_Timer.After(0.2, function() xpcall(Apply, Handler()) end)
        else
            Apply()
        end
    end
    PE:RegisterCoreEvent("UI_SCALE_CHANGED", "ui", ScreenChanged)
    PE:RegisterCoreEvent("DISPLAY_SIZE_CHANGED", "ui", ScreenChanged)
end
