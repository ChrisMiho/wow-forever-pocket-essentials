-- Pocket Essentials: UI kit (PE.UI).
-- Sizes, big touch buttons, panels, a scroll area with big paging buttons and
-- controller (d-pad) navigation. Everything is drawn with solid colours or the
-- addon's own Icons, so it does not depend on any game art.
local ADDON_NAME, PE = ...

local UI = {}
PE.UI = UI

local type, pairs, ipairs, pcall, xpcall, tostring = type, pairs, ipairs, pcall, xpcall, tostring
local max, min, abs = math.max, math.min, math.abs

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
    tab      = { fill = { 0.07, 0.06, 0.04 }, border = { 0.80, 0.64, 0.20 }, text = { 1, 0.82, 0 } },
    disabled = { fill = { 0.11, 0.11, 0.12 }, border = { 0.27, 0.27, 0.29 }, text = { 0.50, 0.50, 0.50 } },
    -- The ends of a number control (UI:CreateNumber): gold edge, gold
    -- sign; stepDim when that side has no further step.
    step     = { fill = { 0.15, 0.16, 0.19 }, border = { 0.62, 0.52, 0.22 }, text = { 1, 0.82, 0 } },
    stepDim  = { fill = { 0.11, 0.11, 0.12 }, border = { 0.62, 0.52, 0.22 }, text = { 0.33, 0.32, 0.29 } },
    -- One part of a segmented choice (UI:CreateSegmented): no edge of its own
    -- (the edge is the box around all the parts); segmentOn is the chosen part.
    segment   = { fill = { 0.15, 0.16, 0.19 }, border = { 0.15, 0.16, 0.19 }, text = { 0.82, 0.82, 0.82 } },
    segmentOn = { fill = { 0.56, 0.42, 0.03 }, border = { 0.56, 0.42, 0.03 }, text = { 1, 1, 1 } },
    -- A tab of the settings window: card fill, and the chosen tab in the
    -- selected fill (Settings.lua adds the gold bar on its left edge).
    tabItem   = { fill = { 0.085, 0.085, 0.10 }, border = { 0.085, 0.085, 0.10 }, text = { 0.88, 0.88, 0.88 } },
    tabOn     = { fill = { 0.56, 0.42, 0.03 }, border = { 0.56, 0.42, 0.03 }, text = { 1, 1, 1 } },
}

-- Shared colours of the settings look (spec 2026-11-20-0.9.0-ui-redesign, "Shared rules").
UI.COLORS = {
    card = { 0.085, 0.085, 0.10 },
    divider = { 0.22, 0.22, 0.25 },
    selected = { 0.56, 0.42, 0.03 },
    gold = { 1, 0.82, 0 },
    goldBrown = { 0.62, 0.52, 0.22 },
    window = { 0.05, 0.05, 0.07 },
    name = { 0.92, 0.92, 0.92 },
    help = { 0.62, 0.62, 0.62 },
    dotOn = { 0.35, 0.92, 0.45 },
    dotOff = { 0.40, 0.40, 0.43 },
    badge = { 0.85, 0.08, 0.08 },
}
local SELECTED = { fill = { 0.56, 0.42, 0.03 }, border = { 1, 0.82, 0 }, text = { 1, 1, 1 } }
local FOCUS = { 0.25, 0.92, 1.00 }

local function Paint(btn)
    local c = (btn.peSelected and SELECTED) or STYLES[btn.peStyle] or STYLES.normal
    btn.peBorder:SetColorTexture(c.border[1], c.border[2], c.border[3], 1)
    btn.peFill:SetColorTexture(c.fill[1], c.fill[2], c.fill[3], 1)
    btn.peText:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
    -- A picture in place of the label (the scroll bar's arrow tabs) takes the text's colour.
    if btn.peIcon then btn.peIcon:SetVertexColor(c.text[1], c.text[2], c.text[3], 1) end
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

-- "normal", "on" (green), "off" (grey), "warn" (amber), "tab" (gold on dark, like a bag
-- window), "disabled" (dim; still tappable), "step" / "stepDim" (the ends
-- of a number control), "segment" / "segmentOn" (the parts of a segmented
-- choice) or "tabItem" / "tabOn" (the settings window's tabs).
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
-- A disc: one texture of a smooth white circle, tinted with the vertex colour
---------------------------------------------------------------------------

local DISC_TEXTURE = "Interface\\AddOns\\PocketEssentials\\Icons\\circle"
local ARROW_TEXTURE = "Interface\\AddOns\\PocketEssentials\\Icons\\arrow"
-- The circle art leaves a 1.5-pixel clear margin in its 128-pixel square, so
-- the texture is drawn that much larger to make the visible disc `diameter`.
local DISC_ART_SCALE = 128 / 125

-- stripCount is accepted for older callers and ignored.
function UI:CreateDisc(parent, layer, sublevel, stripCount)
    local disc = { texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0) }
    disc.texture:SetTexture(DISC_TEXTURE)

    function disc:SetColor(r, g, b, a)
        self.texture:SetVertexColor(r, g, b)
        self.texture:SetAlpha(a or 1)
    end

    -- Centre the disc on `anchor` with the given diameter.
    function disc:Layout(anchor, diameter)
        local size = max(diameter * DISC_ART_SCALE, 0.01)
        self.texture:ClearAllPoints()
        self.texture:SetSize(size, size)
        self.texture:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end

    function disc:SetShown(shown)
        self.texture:SetShown(shown and true or false)
    end

    return disc
end

---------------------------------------------------------------------------
-- Settings controls (spec 2026-11-20-0.9.0-ui-redesign, "Widgets"). Each is
-- one button height tall and safe to set again on every redraw, so the list
-- drawer (Settings.lua) keeps them in pools. Every pressable part is one of
-- our buttons: a d-pad stop with the focus ring and the press flash.
--
--   UI:ControlWidth(innerWidth)   the width of the control on the right of a row
--   UI:CreateSwitch(parent)       sw:SetSwitch(state) "on" / "off" / "blocked" / "failed"
--   UI:CreateSegmented(parent)    seg:Set(width, items) -> the parts in use
--   UI:CreateNumber(parent)       num:Set(width, box) -> the "-" and "+" ends
---------------------------------------------------------------------------

-- The control on the right of a settings row: 58% of the row, never wider
-- than nine button heights. need: the width the control's labels need (a
-- choice row, UI:ChoiceWidth); a control that needs more grows past the usual
-- width, up to the row width less the name's width (the name keeps at most
-- 30% of the row, and wraps when longer) less a gap (spec 2026-11-20-error-
-- catcher-and-probe-panel, "Shared rule"). label: the row's name.
function UI:ControlWidth(innerWidth, need, label)
    local m = self:Metrics()
    innerWidth = innerWidth or 0
    local width = min(innerWidth * 0.58, m.button * 9)
    if type(need) == "number" and need > width then
        -- The name keeps a little slack, so it is not cut by a rounding.
        local name = label and (self:TextWidth(label, "font") + self:Px(2)) or 0
        width = max(width, min(need, innerWidth - min(name, innerWidth * 0.3) - m.gap))
    end
    return width
end

-- How wide a text is on one line in the given kind ("font", "small" or
-- "title"), measured with a hidden text of our own.
local measure
function UI:TextWidth(text, kind)
    local m = self:Metrics()
    local size = (kind == "small" and m.smallFontSize) or (kind == "title" and m.fontSize * 1.12) or m.fontSize
    text = text == nil and "" or tostring(text)
    if not measure and CreateFrame and UIParent then
        local ok, frame = pcall(CreateFrame, "Frame", nil, UIParent)
        if ok and frame then
            frame:Hide()
            measure = frame:CreateFontString(nil, "OVERLAY")
            measure:SetWordWrap(false)
        end
    end
    if measure then
        local fontName = (kind == "small" and m.smallFont) or (kind == "title" and m.titleFont) or m.font
        pcall(measure.SetFontObject, measure, fontName)
        measure:SetText(text)
        local ok, width = pcall(measure.GetUnboundedStringWidth, measure)
        if ok and type(width) == "number" and width > 0 then return width end
    end
    return #text * size * 0.55
end

-- The height of one line of text in the given kind, measured.
function UI:LineHeight(kind)
    local m = self:Metrics()
    local size = (kind == "small" and m.smallFontSize) or (kind == "title" and m.fontSize * 1.12) or m.fontSize
    self:TextWidth("Ag", kind) -- makes the measuring text and sets its font
    if measure then
        measure:SetText("Ag")
        local ok, height = pcall(measure.GetStringHeight, measure)
        if ok and type(height) == "number" and height >= size * 0.8 then return height end
    end
    return size * 1.2
end

-- The width a segmented choice needs so that no label is cut: every part as
-- wide as the widest label with its inner margin, plus the borders.
function UI:ChoiceWidth(labels)
    local m = self:Metrics()
    local widest = 0
    for _, label in ipairs(labels) do widest = max(widest, self:TextWidth(label, "font")) end
    local n = max(#labels, 1)
    return n * (widest + m.gap * 1.6 + m.border) + m.border
end

-- The switch: two button heights wide, a square knob and the word On / Off.
local SwitchMethods = {}

local SWITCH_LOOK = {
    on = { style = "on", label = "On" },
    off = { style = "off", label = "Off" },
    blocked = { style = "disabled", label = "Off" },
    failed = { style = "warn", label = "Problem" },
}

-- state: "on", "off", "blocked" (cannot be switched on; a tap must do
-- nothing, which the caller's OnClick checks) or "failed".
function SwitchMethods:SetSwitch(state)
    if not SWITCH_LOOK[state] then state = "off" end
    self.peSwitchState = state
    local look = SWITCH_LOOK[state]
    self:SetStyle(look.style)
    self:SetLabel(look.label)
    self:LayoutSwitch()
end

function SwitchMethods:LayoutSwitch()
    local m = UI:Metrics()
    local b = m.border
    local width, height = m.button * 2, m.button
    self:SetSize(width, height)
    local knob = max(height - 4 * b - m.gap * 0.4, 1)
    local inset = 2 * b + m.gap * 0.2
    local on = self.peSwitchState == "on"
    self.peKnob:ClearAllPoints()
    self.peKnob:SetSize(knob, knob)
    self.peKnob:SetPoint("LEFT", self, "LEFT", on and (width - inset - knob) or inset, 0)
    if on then
        self.peKnob:SetColorTexture(0.9, 1, 0.92, 1)
    else
        self.peKnob:SetColorTexture(0.62, 0.62, 0.64, 1)
    end
    local label = self.peText
    label:ClearAllPoints()
    -- Failed: no knob, and the longer word "Problem" uses the whole width.
    if self.peSwitchState == "failed" then
        self.peKnob:Hide()
        label:SetPoint("CENTER", self, "CENTER", 0, 0)
        label:SetWidth(max(width - m.gap * 0.4, 1))
        return
    end
    self.peKnob:Show()
    label:SetPoint("LEFT", self, "LEFT", on and m.gap * 0.4 or (knob + m.gap * 0.6), 0)
    label:SetWidth(max(width - knob - m.gap, 1))
end

function UI:CreateSwitch(parent)
    local m = self:Metrics()
    local sw = self:CreateButton(parent, "", m.button * 2, m.button)
    sw.peKnob = sw:CreateTexture(nil, "BORDER", nil, 1)
    pcall(sw.peText.SetFontObject, sw.peText, m.smallFont)
    sw.peText:SetJustifyH("CENTER")
    for name, fn in pairs(SwitchMethods) do sw[name] = fn end
    sw:SetSwitch("off")
    return sw
end

-- The segmented choice: one box with an edge, cut into equal parts separated
-- by one border. The chosen part has the selected fill, white text and a gold
-- bar along its bottom. Left and Right on the d-pad move between the parts.
local SegmentedMethods = {}

-- items: { { label =, selected =, onClick = }, ... }. Returns the list of
-- part buttons in use, in order. fitLabels: for a full-width choice with no
-- row name (the Errors tab's filter): parts may be unequal so that no label
-- is cut. Without it the parts are always equal.
function SegmentedMethods:Set(width, items, fitLabels)
    local m = UI:Metrics()
    local b = m.border
    local n = max(#items, 1)
    local height = m.button
    self:SetSize(width, height)
    local inside = max(width - b * (n + 1), n)
    local partWidth = max(inside / n, 1)
    -- Equal parts. With fitLabels, when a label does not fit its part even in
    -- the small font and all the labels fit side by side, each part is as wide
    -- as its label needs, plus an even share of what is left ("Pocket
    -- Essentials" beside "All").
    local widths = {}
    for i = 1, #items do widths[i] = partWidth end
    if fitLabels then
        local needs, total, cut = {}, 0, false
        for i = 1, #items do
            local smallWidth = UI:TextWidth(items[i].label, "small") + m.gap * 0.8
            needs[i] = smallWidth
            total = total + smallWidth
            if smallWidth > partWidth then cut = true end
        end
        if cut and total <= inside then
            local share = (inside - total) / n
            for i = 1, #items do widths[i] = needs[i] + share end
        end
    end
    local barHeight = max(UI:Px(3), b * 1.5)
    local used = {}
    local x = b
    for i = 1, #items do
        local item = items[i]
        local part = self.peParts[i]
        if not part then
            part = UI:CreateButton(self, "")
            part.peBar = part:CreateTexture(nil, "ARTWORK", nil, 2)
            part.peBar:SetColorTexture(1, 0.82, 0, 1)
            self.peParts[i] = part
        end
        local w = widths[i]
        part:ClearAllPoints()
        part:SetSize(w, height - 2 * b)
        part:SetPoint("TOPLEFT", self, "TOPLEFT", x, -b)
        x = x + w + b
        part.peText:ClearAllPoints()
        part.peText:SetPoint("LEFT", part, "LEFT", m.gap * 0.4, 0)
        part.peText:SetPoint("RIGHT", part, "RIGHT", -m.gap * 0.4, 0)
        part:SetLabel(item.label)
        -- A label that does not fit its part (at Large: "Extra large", or
        -- "Medium" in a part of four) uses the small font instead.
        local label = part.peText
        pcall(label.SetFontObject, label, m.font)
        local ok, textWidth = pcall(label.GetUnboundedStringWidth, label)
        if not ok or type(textWidth) ~= "number" or textWidth <= 0 then
            textWidth = #(label:GetText() or "") * m.fontSize * 0.55
        end
        part.peSmallLabel = textWidth > w - m.gap * 0.8
        if part.peSmallLabel then pcall(label.SetFontObject, label, m.smallFont) end
        part:SetStyle(item.selected and "segmentOn" or "segment")
        part.peBar:ClearAllPoints()
        part.peBar:SetPoint("BOTTOMLEFT", part, "BOTTOMLEFT", 0, 0)
        part.peBar:SetPoint("BOTTOMRIGHT", part, "BOTTOMRIGHT", 0, 0)
        part.peBar:SetHeight(barHeight)
        part.peBar:SetShown(item.selected and true or false)
        part.peChosen = item.selected and true or false
        part:SetScript("OnClick", item.onClick)
        part:Show()
        used[i] = part
    end
    for i = #items + 1, #self.peParts do self.peParts[i]:Hide() end
    return used
end

function UI:CreateSegmented(parent)
    local seg = CreateFrame("Frame", nil, parent)
    seg.peEdge = seg:CreateTexture(nil, "BACKGROUND")
    seg.peEdge:SetAllPoints(seg)
    local c = STYLES.normal.border
    seg.peEdge:SetColorTexture(c[1], c[2], c[3], 1)
    seg.peParts = {}
    for name, fn in pairs(SegmentedMethods) do seg[name] = fn end
    return seg
end

-- The number control: "-", a dark well with the value in gold and a small
-- grey unit word under it (when both lines fit), "+", as one joined box. The
-- well is not a d-pad stop.
local NumberMethods = {}

-- box: { text, unit, down = onClick or nil, up = onClick or nil, downDim,
-- upDim, noStep = onClick for an end with no step }. An end with no step (or
-- marked dim) is drawn dim. Returns the "-" and "+" buttons.
function NumberMethods:Set(width, box)
    local m = UI:Metrics()
    local b, e = m.border, m.button
    width = max(width, e * 2 + e * 0.5)
    self:SetSize(width, e)
    local minus, plus = self.peMinus, self.pePlus
    minus:ClearAllPoints()
    minus:SetSize(e, e)
    minus:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    minus:SetStyle((box.down and not box.downDim) and "step" or "stepDim")
    minus:SetScript("OnClick", box.down or box.noStep)
    plus:ClearAllPoints()
    plus:SetSize(e, e)
    plus:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
    plus:SetStyle((box.up and not box.upDim) and "step" or "stepDim")
    plus:SetScript("OnClick", box.up or box.noStep)

    local wellWidth = width - 2 * e + 2 * b
    local well = self.peWell
    well:ClearAllPoints()
    well:SetSize(wellWidth, e)
    well:SetPoint("TOPLEFT", self, "TOPLEFT", e - b, 0)
    well.fill:ClearAllPoints()
    well.fill:SetPoint("TOPLEFT", well, "TOPLEFT", b, -b)
    well.fill:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -b, b)
    local inner = max(wellWidth - 2 * b, 1)
    local unit = box.unit ~= nil and tostring(box.unit) or ""
    local showUnit = unit ~= "" and m.fontSize + m.smallFontSize <= e - 2 * b
    local value = well.value
    value:SetWidth(inner)
    value:SetText(box.text == nil and "" or tostring(box.text))
    value:SetTextColor(1, 0.82, 0, 1)
    local valueHeight = UI:TextHeight(value, "font")
    value:ClearAllPoints()
    if showUnit then
        well.unit:SetWidth(inner)
        well.unit:SetText(unit)
        well.unit:SetTextColor(0.62, 0.62, 0.62, 1)
        local unitHeight = UI:TextHeight(well.unit, "small")
        local top = max((e - valueHeight - unitHeight) * 0.5, b)
        value:SetPoint("TOP", well, "TOP", 0, -top)
        well.unit:ClearAllPoints()
        well.unit:SetPoint("TOP", well, "TOP", 0, -(top + valueHeight))
        well.unit:Show()
    else
        value:SetPoint("TOP", well, "TOP", 0, -max((e - valueHeight) * 0.5, 0))
        well.unit:Hide()
    end
    -- The ends above the well, so their edges draw over its joints.
    minus:SetFrameLevel(well:GetFrameLevel() + 1)
    plus:SetFrameLevel(well:GetFrameLevel() + 1)
    return minus, plus
end

function UI:CreateNumber(parent)
    local num = CreateFrame("Frame", nil, parent)
    local well = CreateFrame("Frame", nil, num)
    well.border = well:CreateTexture(nil, "BACKGROUND")
    well.border:SetAllPoints(well)
    well.border:SetColorTexture(0.62, 0.52, 0.22, 1)
    well.fill = well:CreateTexture(nil, "BORDER")
    well.fill:SetColorTexture(0.03, 0.03, 0.04, 1)
    well.value = self:CreateText(well, "font")
    well.value:SetJustifyH("CENTER")
    well.value:SetWordWrap(false)
    well.unit = self:CreateText(well, "small")
    well.unit:SetJustifyH("CENTER")
    well.unit:SetWordWrap(false)
    num.peWell = well
    num.peMinus = self:CreateButton(num, "-")
    num.pePlus = self:CreateButton(num, "+")
    for name, fn in pairs(NumberMethods) do num[name] = fn end
    return num
end

-- The height of a text that was just set; an estimate from its length while
-- the game cannot measure it yet. kind: "font", "small" or "title".
function UI:TextHeight(fontString, kind)
    local m = self:Metrics()
    local size = (kind == "small" and m.smallFontSize) or (kind == "title" and m.fontSize * 1.12) or m.fontSize
    local ok, height = pcall(fontString.GetStringHeight, fontString)
    if ok and type(height) == "number" and height >= size * 0.8 then return height end
    local text = fontString:GetText() or ""
    local okW, width = pcall(fontString.GetWidth, fontString)
    width = (okW and type(width) == "number" and width > 0) and width or size * 20
    local perLine = max(math.floor(width / (size * 0.5)), 1)
    local lines = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + max(math.ceil(#line / perLine), 1)
    end
    return max(lines, 1) * size * 1.2
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
    panel.closeButton:SetScript("OnClick", PE:Wrap("core", function() panel:Hide() end))

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
-- Scroll area: a clipped list with a slim scroll bar on the right (an up tab,
-- a track with a marker, a down tab).
--   local area = PE.UI:CreateScrollArea(parent); area:SetPoint(...)
--   area:Layout(width, height)      -- call again when sizes change
--   put content in area.child (its width is area.viewWidth), then
--   area:SetContentHeight(totalHeight)
---------------------------------------------------------------------------

local AreaMethods = {}

-- The sizes the area is laid out with: its own (Layout's metrics) or the
-- shared ones.
local function AreaMetrics(area)
    return area.peMetrics or UI:Metrics()
end

function AreaMethods:GetRange()
    return max(self.contentHeight - self.viewHeight, 0)
end

function AreaMethods:ScrollTo(offset)
    local range = self:GetRange()
    offset = min(max(offset or 0, 0), range)
    self.offset = offset
    self.scrollFrame:SetVerticalScroll(offset)
    self.upButton:SetStyle(offset > 0.5 and "step" or "stepDim")
    self.downButton:SetStyle(offset < range - 0.5 and "step" or "stepDim")
    self:PlaceThumb()
end

-- The marker: as tall as the share of the list in view (never thinner than
-- half a button), and as far down the track as the list is scrolled.
function AreaMethods:PlaceThumb()
    local trackHeight = self.trackHeight or 1
    local ratio = min(self.viewHeight / max(self.contentHeight, 1), 1)
    local thumbHeight = min(max(trackHeight * ratio, AreaMetrics(self).button * 0.5), trackHeight)
    local range = self:GetRange()
    local fraction = range > 0 and (self.offset / range) or 0
    self.thumb:SetHeight(thumbHeight)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPLEFT", self.track, "TOPLEFT", 0, -(trackHeight - thumbHeight) * fraction)
    self.thumb:SetPoint("TOPRIGHT", self.track, "TOPRIGHT", 0, -(trackHeight - thumbHeight) * fraction)
end

-- Shows or hides the whole bar. It stays hidden while the player does not use
-- the touch screen, unless the row "Menu arrows, always" is On (0.22.0).
function AreaMethods:SetBarShown(shown)
    shown = shown and (PE:UsesTouch() or UI.ArrowsAlways()) or false
    self.barShown = shown
    self.upButton:SetShown(shown)
    self.downButton:SetShown(shown)
    self.track:SetShown(shown)
end

function AreaMethods:ScrollBy(delta)
    self:ScrollTo(self.offset + (delta or 0))
end

function AreaMethods:PageUp()
    local row = AreaMetrics(self).row
    self:ScrollBy(-max(self.viewHeight - row, row))
end

function AreaMethods:PageDown()
    local row = AreaMetrics(self).row
    self:ScrollBy(max(self.viewHeight - row, row))
end

-- top/bottom are distances from the top of area.child (positive, downwards).
function AreaMethods:EnsureVisible(top, bottom)
    if type(top) ~= "number" or type(bottom) ~= "number" then return end
    local margin = AreaMetrics(self).gap
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
    if self.barShown and PE.debugOn and UI.ArrowsAlways() and not PE:UsesTouch() then
        local m = AreaMetrics(self)
        PE:Debug("ui", ("menu arrows: shown (list %d rows, window fits %d)"):format(
            math.ceil(self.contentHeight / m.row), math.floor(self.viewHeight / m.row)))
    end
    self:ScrollTo(self.offset)
end

-- noPaging: for a list known to fit. The scroll bar is hidden and the list
-- takes the whole width. It is hidden too while the player does not use the
-- touch screen (PE:UsesTouch), which is read on every call. metrics: the
-- sizes for the bar (button, gap, row) of a window with its own scale (the
-- chat window); nil uses the shared ones.
function AreaMethods:Layout(width, height, noPaging, metrics)
    self.peMetrics = type(metrics) == "table" and metrics or nil
    local m = AreaMetrics(self)
    local column = m.button * 0.75
    local bar = not noPaging and (PE:UsesTouch() or UI.ArrowsAlways())
    width, height = max(width or 0, column + m.gap + 10), max(height or 0, 10)
    self.viewWidth = bar and (width - column - m.gap) or width
    self:SetBarShown(bar)
    self.viewHeight = height
    self:SetSize(width, height)
    self.scrollFrame:ClearAllPoints()
    self.scrollFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.scrollFrame:SetSize(self.viewWidth, self.viewHeight)
    self.child:SetWidth(self.viewWidth)
    self.upButton:ClearAllPoints()
    self.upButton:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
    self.upButton:SetSize(column, m.button)
    self.downButton:ClearAllPoints()
    self.downButton:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    self.downButton:SetSize(column, m.button)
    local side = min(column, m.button) * 0.8
    if self.upButton.peIcon then self.upButton.peIcon:SetSize(side, side) end
    if self.downButton.peIcon then self.downButton.peIcon:SetSize(side, side) end
    self.trackHeight = max(height - 2 * (m.button + m.gap), 1)
    self.track:ClearAllPoints()
    self.track:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(m.button + m.gap))
    self.track:SetSize(column, self.trackHeight)
    self:ScrollTo(self.offset)
end

function UI:CreateScrollArea(parent)
    local area = CreateFrame("Frame", nil, parent)
    area.scrollFrame = CreateFrame("ScrollFrame", nil, area)
    area.child = CreateFrame("Frame", nil, area.scrollFrame)
    area.child:SetSize(10, 10)
    area.scrollFrame:SetScrollChild(area.child)
    area.offset, area.contentHeight, area.viewWidth, area.viewHeight = 0, 1, 10, 10

    -- Our arrow picture (Icons/arrow, pointing up), turned over for down by
    -- its texture corners. The letters stay as the tabs' names, hidden while
    -- the picture shows; they show only if the picture cannot be set.
    area.upButton = self:CreateButton(area, "^")
    area.downButton = self:CreateButton(area, "v")
    for btn, coords in pairs({ [area.upButton] = { 0, 1, 0, 1 }, [area.downButton] = { 0, 1, 1, 0 } }) do
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        local ok, set = pcall(icon.SetTexture, icon, ARROW_TEXTURE)
        if ok and set ~= false then
            pcall(icon.SetTexCoord, icon, coords[1], coords[2], coords[3], coords[4])
            icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.peIcon = icon
            btn.peText:Hide()
            Paint(btn)
        else
            icon:Hide()
        end
    end
    for name, fn in pairs(AreaMethods) do area[name] = fn end
    area.upButton:SetScript("OnClick", PE:Wrap("core", function() area:PageUp() end))
    area.downButton:SetScript("OnClick", PE:Wrap("core", function() area:PageDown() end))
    area.upButton:SetStyle("stepDim")
    area.downButton:SetStyle("stepDim")

    -- The track is a plain frame, not a button: it is no d-pad stop.
    area.track = CreateFrame("Frame", nil, area)
    area.track:EnableMouse(true)
    area.trackBorder = area.track:CreateTexture(nil, "BACKGROUND")
    area.trackBorder:SetAllPoints(area.track)
    area.trackBorder:SetColorTexture(0.62, 0.52, 0.22, 1)
    area.trackFill = area.track:CreateTexture(nil, "BORDER")
    area.trackFill:SetPoint("TOPLEFT", area.track, "TOPLEFT", 1, -1)
    area.trackFill:SetPoint("BOTTOMRIGHT", area.track, "BOTTOMRIGHT", -1, 1)
    area.trackFill:SetColorTexture(0.03, 0.03, 0.04, 1)
    area.thumb = CreateFrame("Frame", nil, area.track)
    area.thumbFill = area.thumb:CreateTexture(nil, "ARTWORK")
    area.thumbFill:SetAllPoints(area.thumb)
    area.thumbFill:SetColorTexture(1, 0.82, 0, 1)
    area.track:SetScript("OnMouseDown", PE:Wrap("core", function()
        local ok, cx, cy = pcall(GetCursorPosition)
        local scale = area.track:GetEffectiveScale()
        if not (ok and type(cy) == "number" and type(scale) == "number" and scale > 0) then return end
        local y = cy / scale
        local top, bottom = area.thumb:GetTop(), area.thumb:GetBottom()
        if type(top) ~= "number" or type(bottom) ~= "number" then return end
        if y > top then area:PageUp() elseif y < bottom then area:PageDown() end
    end))
    area.track:Hide()
    area.upButton:Hide()
    area.downButton:Hide()

    -- No wheel on the handheld; this is for testing on a desktop.
    area.scrollFrame:EnableMouseWheel(true)
    area.scrollFrame:SetScript("OnMouseWheel", PE:Wrap("core", function(_, delta)
        area:ScrollBy(-(delta or 0) * AreaMetrics(area).row)
    end))
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
local navHoldBtn     -- the button whose peHold A started, until A comes up or the press is lost

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

-- A held button: one with a peHold table { start = fn, stop = fn } acts on A
-- going down (start) and coming up (stop), and is not clicked on release.
-- The press is also lost (stop) when the highlight leaves it, when the window
-- hides and when the keys are given back. Other buttons are not affected.
local function NavHoldStop()
    local btn = navHoldBtn
    if not btn then return end
    navHoldBtn = nil
    navDown.A = nil -- the release that follows belongs to this press: it clicks nothing
    local hold = btn.peHold
    if type(hold) == "table" and type(hold.stop) == "function" then xpcall(hold.stop, Handler(), btn) end
    if btn.pePush then pcall(ButtonUp, btn) end
end

-- For a held button's owner that stopped the hold by itself (a safety stop,
-- the screen edge): forget the press, so the next A press is a fresh one and
-- a late release of this one clicks nothing. stop is not called again.
function UI:NavHoldEnded()
    local btn = navHoldBtn
    if not btn then return end
    navHoldBtn = nil
    navDown.A = nil
    if btn.pePush then pcall(ButtonUp, btn) end
end

local function NavFocus(panel, btn, index)
    if navHoldBtn and navHoldBtn ~= btn then NavHoldStop() end
    local old = panel.peNavFocus
    if old and old ~= btn and old.SetNavFocus then old:SetNavFocus(false) end
    panel.peNavFocus, panel.peNavIndex = btn, index
    if btn then
        if btn.SetNavFocus then btn:SetNavFocus(true) end
        if type(panel.navOnFocus) == "function" then xpcall(panel.navOnFocus, Handler(), btn) end
    end
end

function UI:NavSameRow(a, b)
    return (a and b and SameRow(a, b)) or false
end

-- 0.22.0 row "Menu arrows, always": read at call time (Batch.lua loads first,
-- but the row can change while the game runs).
function UI.ArrowsAlways()
    local batch = PE.Batch
    return batch ~= nil and batch.On("b22Arrows") or false
end

function UI.DpadByDirection()
    local batch = PE.Batch
    return batch ~= nil and batch.On("b22Dpad") or false
end

-- 0.22.0 row "D-pad moves by direction". The rectangle of a button as
-- { left, bottom, right, top }, from its own frame (reads only); nil when the
-- frame has no place on screen yet.
local function FrameRect(btn)
    local ok, l, b, r, t = pcall(function() return btn:GetLeft(), btn:GetBottom(), btn:GetRight(), btn:GetTop() end)
    if ok and l and b and r and t then return { l, b, r, t } end
end

-- The button the D-pad should reach from focus when dx, dy (-1, 0 or 1, y up)
-- is pressed: among shown, enabled buttons whose centre is strictly further in
-- that direction, the least along + 2 * across between centres. nil when none.
-- rectOf(button) -> { left, bottom, right, top } may be passed for a test.
function UI.NearestInDirection(buttons, focus, dx, dy, rectOf)
    rectOf = rectOf or FrameRect
    local from = focus and rectOf(focus)
    if not from then return nil end
    local fx, fy = (from[1] + from[3]) / 2, (from[2] + from[4]) / 2
    local best, bestScore
    for _, btn in ipairs(buttons) do
        if btn ~= focus and not (btn.IsShown and not btn:IsShown())
            and not (btn.IsEnabled and not btn:IsEnabled()) then
            local rect = rectOf(btn)
            if rect then
                local ox, oy = (rect[1] + rect[3]) / 2 - fx, (rect[2] + rect[4]) / 2 - fy
                local along, across
                if dx ~= 0 then along, across = ox * dx, abs(oy) else along, across = oy * dy, abs(ox) end
                if along > 0 then
                    local score = along + 2 * across
                    if not bestScore or score < bestScore then best, bestScore = btn, score end
                end
            end
        end
    end
    return best
end

-- step = -1 / +1. byRow (up/down) skips the other buttons on the same line.
-- A panel may split its buttons into columns:
--   panel.navCross(focus, step, byRow) -> a button to jump to, or nil for the
--     usual move (focus is nil before anything is highlighted);
--   panel.navColumn(focus) -> the part of the list that holds focus; the
--     usual move then stays inside it.
local function NavMove(panel, step, byRow)
    local all = NavList(panel)
    local list = all
    if #all == 0 then return NavFocus(panel, nil) end
    local focus = panel.peNavFocus
    if not IndexOf(all, focus) then focus = nil end
    -- A panel with its own rule (navCross) keeps it whole, as in 0.21.0.
    local byDirection = type(panel.navCross) ~= "function" and UI.DpadByDirection()
    if type(panel.navCross) == "function" then
        local ok, target = xpcall(panel.navCross, Handler(), focus, step, byRow)
        -- navCross may have redrawn the window: read its list again.
        all = NavList(panel)
        local at = ok and IndexOf(all, target)
        if at then return NavFocus(panel, target, at) end
    end
    -- 0.22.0: by direction. With nothing highlighted yet the usual first stop
    -- is chosen below; with nothing that way the highlight stays.
    if byDirection and focus then
        local dx, dy = 0, 0
        if byRow then dy = -step else dx = step end
        local target = UI.NearestInDirection(all, focus, dx, dy)
        if PE.debugOn then
            local name = dx < 0 and "left" or dx > 0 and "right" or dy > 0 and "up" or "down"
            if target then
                PE:Debug("ui", ('dpad: %s from "%s" to "%s"'):format(name, focus.GetLabel and focus:GetLabel() or "", target.GetLabel and target:GetLabel() or ""))
            else
                PE:Debug("ui", "dpad: " .. name .. ": nothing that way")
            end
        end
        if target then return NavFocus(panel, target, IndexOf(all, target)) end
        return
    end
    if focus and type(panel.navColumn) == "function" then
        local ok, column = xpcall(panel.navColumn, Handler(), focus)
        if ok and type(column) == "table" and IndexOf(column, focus) then list = column end
    end
    local n = #list
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
    -- Touch off: the scroll bar's tabs are hidden, so a list with no stops
    -- below the top (plain text) could not be scrolled. When the next stop is
    -- outside the list (or the move wraps), the d-pad pages the list instead.
    -- A column with no stop inside the list (the settings tabs) never pages:
    -- Up and Down there move between its own stops.
    local area = panel.peNavArea
    local pages = list == all or list[current or 0] and list[current].peScrollTop
    if not pages and current then
        for i = 1, n do
            if list[i].peScrollTop then pages = true break end
        end
    end
    if byRow and current and pages and area and area.GetRange and not PE:UsesTouch() then
        local target = list[index]
        local outside = not (target and target.peScrollTop)
        if outside then
            if step > 0 and index > current and area:GetRange() > area.offset + 0.5 then
                return area:PageDown()
            elseif step < 0 and area.offset > 0.5 then
                return area:PageUp()
            end
        end
    end
    NavFocus(panel, list[index], IndexOf(all, list[index]))
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

-- A went down on the highlighted button: start it if it is a held button.
local function NavHoldStart(panel)
    local btn = panel.peNavFocus
    local hold = btn and btn.peHold
    if type(hold) ~= "table" or type(hold.start) ~= "function" then return end
    if not IndexOf(NavList(panel), btn) or (btn.IsEnabled and not btn:IsEnabled()) then return end
    navHoldBtn = btn
    if btn.pePush then pcall(ButtonDown, btn) end
    xpcall(hold.start, Handler(), btn)
end

local function NavPress(_, key, down)
    local panel = navOwner
    if not panel or not panel:IsShown() then return end
    if down ~= false then
        -- A again while a held button is down (a repeated press): nothing new.
        if key == "A" and navHoldBtn then return end
        navDown[key] = true
        if key == "A" then NavHoldStart(panel)
        elseif key == "UP" then NavMove(panel, -1, true)
        elseif key == "DOWN" then NavMove(panel, 1, true)
        elseif key == "LEFT" then NavMove(panel, -1, false)
        elseif key == "RIGHT" then NavMove(panel, 1, false)
        end
        return
    end
    -- A and B act on release, and only if we also saw the press: a release
    -- whose press went to the game (or to a Blizzard window) is not ours.
    if key == "A" and navHoldBtn then
        NavHoldStop()
        return
    end
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
    NavHoldStop()
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
    NavHoldStop()
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
