local ADDON_NAME, P = ...

-- The panel that drives the probe: "Pocket Probe 0.6.0".
--
--   top     the title, the status line, and (only with Pocket Essentials
--           loaded) the recording line: "Recording 12 min" and Stop, or
--           "Not recording" and Start recording (Perf.lua, probe 0.6.0).
--           The minutes are as of the last redraw: nothing ticks for them.
--   left    one tab per area, each with "N / M run"
--   right   one row per trial: its label, a result chip and Run (or, for a
--           guided trial, Start and then its two answer buttons)
--   below   Details of the row tapped last, then the footer: Run all safe,
--           Fight tests, Clean run (reloads), Risky, Vendor, Auto, Save (reloads)
--
-- Also here, because it shares the panel's fonts: the big message, a frame
-- of its own that shows a guided trial's question in big letters while the
-- panel is closed (probe 0.5.0).
--
-- It uses no Pocket Essentials code. It copies Pocket Essentials' sizes (the
-- Medium button size, in 720p pixels) and colours so it looks the same, and
-- it is as big as Pocket Essentials' settings window.
--
-- No scroll bar: when an area has more trials than fit at this screen size it
-- becomes two tabs ("Values 1", "Values 2"), or more when needed.
--
-- Touch works everywhere. The d-pad and A / B work while the panel is shown
-- and no fight is on: the six keys are pointed at one hidden button of ours
-- with override bindings owned by the panel, and given back when it hides
-- or a fight starts (the same way Pocket Essentials does it).
--
-- Every frame is made now, at load, so nothing is created in a fight.
--
-- Game names used (proof as in Core.lua; all already used by the probe or
-- by Pocket Essentials): CreateFrame, CreateFont, UIParent, GameFontHighlightLarge,
-- GameFontHighlight, GameFontNormalLarge, SetOverrideBindingClick,
-- ClearOverrideBindings, InCombatLockdown.

local type, ipairs, pairs, pcall, tostring = type, ipairs, pairs, pcall, tostring
local min, max, floor = math.min, math.max, math.floor
local tconcat = table.concat
local Find, Str, Guard = P.Find, P.Str, P.Guard

---------------------------------------------------------------------------
-- Sizes and colours (copied from Pocket Essentials' UI.lua, Medium preset)
---------------------------------------------------------------------------

local SIZE = { button = 56, gap = 10, pad = 14, font = 25, small = 20 }
local TAB_WIDTH = 4.4                    -- in buttons
local POOL_TABS, POOL_ROWS = 24, 16

local factor = 768 / 720                 -- UI units per 720p pixel, worked out at each layout

local function Factor()
    local ok, scale = pcall(UIParent.GetEffectiveScale, UIParent)
    if ok and type(scale) == "number" and scale > 0.05 then return 768 / (720 * scale) end
    local ok2, height = pcall(UIParent.GetHeight, UIParent)
    if ok2 and type(height) == "number" and height > 100 then return height / 720 end
    return 768 / 720
end

local function Px(n) return n * factor end

-- For the recorder's dot and Stop button (Perf.lua): n 720p pixels in UI
-- units, at the screen's size right now.
function P.Units(n)
    factor = Factor()
    return n * factor
end

local STYLE = {
    normal   = { fill = { 0.15, 0.16, 0.19 }, border = { 0.52, 0.52, 0.57 }, text = { 1, 1, 1 } },
    on       = { fill = { 0.07, 0.40, 0.13 }, border = { 0.35, 0.92, 0.45 }, text = { 1, 1, 1 } },
    off      = { fill = { 0.25, 0.25, 0.27 }, border = { 0.52, 0.52, 0.54 }, text = { 0.82, 0.82, 0.82 } },
    disabled = { fill = { 0.11, 0.11, 0.12 }, border = { 0.27, 0.27, 0.29 }, text = { 0.50, 0.50, 0.50 } },
}
local CHIP = {
    allowed = { fill = { 0.07, 0.40, 0.13 }, border = { 0.35, 0.92, 0.45 } },
    blocked = { fill = { 0.52, 0.28, 0.03 }, border = { 1.00, 0.62, 0.15 } },
    notrun  = { fill = { 0.16, 0.16, 0.18 }, border = { 0.40, 0.40, 0.43 } },
    value   = { fill = { 0.10, 0.12, 0.18 }, border = { 0.45, 0.60, 0.85 } },
    -- grey-blue: ran, nothing refused it, but it could not see the outcome
    info    = { fill = { 0.13, 0.14, 0.17 }, border = { 0.47, 0.52, 0.62 } },
}
local GOLDBROWN, PANELFILL = { 0.62, 0.52, 0.22 }, { 0.05, 0.05, 0.07 }
local CARD, CARD_SELECTED, TAB_SELECTED = { 0.085, 0.085, 0.10 }, { 0.13, 0.12, 0.09 }, { 0.56, 0.42, 0.03 }
local GOLD, STATUS_BLUE, DIM = { 1, 0.82, 0 }, { 0.65, 0.85, 1 }, { 0.62, 0.62, 0.62 }
local LABEL, LABEL_DIM, COUNT = { 0.92, 0.92, 0.92 }, { 0.5, 0.5, 0.5 }, { 0.7, 0.7, 0.72 }

-- The areas in the order of the tabs. Any other area (the "Afterwards"
-- entries the probe adds when the game refuses its own actions) comes last.
-- Small areas share a tab (ten tabs at most at 16:9, each tall enough to tap).
local AREA_ORDER = { "Errors", "Graphics", "Our own windows", "Blizzard windows", "Chat box", "Bags and vendor",
    "Controller and layout", "Values" }

local function AreaName(area)
    if type(area) ~= "string" then return "Other" end
    if area:find("^Afterwards") then return "Afterwards" end
    return area
end

---------------------------------------------------------------------------
-- Fonts: our own, so the text has Pocket Essentials' sizes
---------------------------------------------------------------------------

local FONTS = {
    font  = { name = "PocketProbeFont",      size = SIZE.font,         color = { 1, 1, 1 },          fallback = "GameFontHighlightLarge" },
    small = { name = "PocketProbeFontSmall", size = SIZE.small,        color = { 0.84, 0.84, 0.84 }, fallback = "GameFontHighlight" },
    title = { name = "PocketProbeFontTitle", size = SIZE.font * 1.12,  color = GOLD,                  fallback = "GameFontNormalLarge" },
    tab   = { name = "PocketProbeFontTab",   size = SIZE.font * 0.92,  color = { 1, 1, 1 },          fallback = "GameFontHighlight" },
    tiny  = { name = "PocketProbeFontTiny",  size = SIZE.small * 0.85, color = COUNT,                 fallback = "GameFontHighlight" },
    big   = { name = "PocketProbeFontBig",   size = SIZE.font * 2,     color = { 1, 1, 1 },          fallback = "GameFontNormalLarge" },
}
local fontObjects = {}
local fontFile, fontFlags

local function FontFile()
    if fontFile then return end
    local source = GameFontHighlightLarge or GameFontNormalLarge or GameFontNormal
    if source and source.GetFont then
        local ok, file, _, flags = pcall(source.GetFont, source)
        if ok and type(file) == "string" and file ~= "" then
            fontFile, fontFlags = file, type(flags) == "string" and flags or ""
        end
    end
    if not fontFile then
        fontFile = (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
        fontFlags = ""
    end
end

-- Sets (or resets, after the screen changed) the sizes of our fonts.
local function SetupFonts()
    FontFile()
    for key, spec in pairs(FONTS) do
        local object = fontObjects[key]
        if object == nil and CreateFont then
            local ok, made = pcall(CreateFont, spec.name)
            object = ok and made or false
            fontObjects[key] = object
            if object then
                pcall(object.SetTextColor, object, spec.color[1], spec.color[2], spec.color[3], 1)
                pcall(object.SetShadowColor, object, 0, 0, 0, 1)
                pcall(object.SetShadowOffset, object, 1, -1)
            end
        end
        if object then
            local ok = pcall(object.SetFont, object, fontFile, Px(spec.size), fontFlags)
            if not ok then fontObjects[key] = false end
        end
    end
end

local function UseFont(text, key)
    local object = fontObjects[key]
    if object then
        pcall(text.SetFontObject, text, object)
    else
        local fallback = _G[FONTS[key].fallback]
        if fallback then pcall(text.SetFontObject, text, fallback) end
    end
end

local function NewText(parent, key, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    UseFont(text, key)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    text.ppFont = key
    return text
end

P.NewText = NewText

local function Color(text, c) text:SetTextColor(c[1], c[2], c[3], 1) end

---------------------------------------------------------------------------
-- Boxes and buttons: an edge texture with a fill inset by the border
---------------------------------------------------------------------------

local border = 2

local function Box(kind, parent, name)
    local f = CreateFrame(kind, name, parent)
    f.ppEdge = f:CreateTexture(nil, "BACKGROUND")
    f.ppEdge:SetAllPoints(f)
    f.ppFill = f:CreateTexture(nil, "BORDER")
    return f
end

local function Paint(f, fill, edge, width)
    width = width or border
    f.ppEdge:SetColorTexture(edge[1], edge[2], edge[3], 1)
    f.ppFill:ClearAllPoints()
    f.ppFill:SetPoint("TOPLEFT", f, "TOPLEFT", width, -width)
    f.ppFill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -width, width)
    f.ppFill:SetColorTexture(fill[1], fill[2], fill[3], 1)
end

local function Place(f, parent, x, y, w, h)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    f:SetSize(max(w, 1), max(h, 1))
end

-- A button with Pocket Essentials' look. b.ppDisabled makes it dim and inert.
local function NewButton(parent, name, onClick)
    local b = Box("Button", parent, name)
    b.ppLabel = NewText(b, "font")
    b.ppLabel:SetJustifyH("CENTER")
    b.ppLabel:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:SetScript("OnClick", Guard(function(self)
        if self.ppDisabled then return end
        onClick(self)
    end))
    return b
end

local function SetButton(b, label, style, disabled)
    b.ppDisabled = disabled and true or false
    local s = STYLE[disabled and "disabled" or (style or "normal")]
    Paint(b, s.fill, s.border)
    b.ppLabel:SetText(label)
    Color(b.ppLabel, s.text)
end

-- Fits a button's label: the normal font, else the small one on up to two lines.
local function FitLabel(b, width)
    local label = b.ppLabel
    UseFont(label, "font")
    label:SetWordWrap(false)
    label:SetWidth(width)
    local ok, need = pcall(label.GetUnboundedStringWidth, label)
    if ok and type(need) == "number" and need > width then
        UseFont(label, "small")
        label:SetWordWrap(true)
        label:SetMaxLines(2)
    end
end

---------------------------------------------------------------------------
-- The frames, made now
---------------------------------------------------------------------------

SetupFonts()

local panel = Box("Frame", UIParent, "PocketProbePanel")
panel:SetFrameStrata("DIALOG")
panel:EnableMouse(true)
panel:Hide()
P.panel = panel

local titleRule = panel:CreateTexture(nil, "ARTWORK")
local title = NewText(panel, "title")
local statusLine = NewText(panel, "small")
Color(statusLine, STATUS_BLUE)

local closeButton = NewButton(panel, "PocketProbeCloseButton", function() panel:Hide() end)

-- The recording line (probe 0.6.0), in the title bar left of Close. Hidden
-- when Pocket Essentials is not loaded: the panel is then as it was in 0.5.0.
local function Recording() return P.Recording ~= nil and P.Recording() == true end
local function RecordingOffered() return P.RecordingOffered ~= nil and P.RecordingOffered() == true end
local RECORDING_NOTE = "Recording: tap Stop first."
local recordText = NewText(panel, "small")
recordText:SetJustifyH("RIGHT")
recordText:Hide()
local recordButton = NewButton(panel, "PocketProbeRecordButton", function()
    if Recording() then P.StopRecording() else P.StartRecording() end
end)
recordButton:Hide()

local tabs = {}
local selectedPage, selectedRow = 1, 1
local pages = {}                         -- { label, entries = { { id, label, def }, ... } }
local Refresh                            -- below

for i = 1, POOL_TABS do
    local t = Box("Button", panel)
    t.ppBar = t:CreateTexture(nil, "ARTWORK")
    t.ppName = NewText(t, "tab")
    t.ppCount = NewText(t, "tiny")
    t.ppIndex = i
    t:SetScript("OnClick", Guard(function()
        selectedPage, selectedRow = i, 1
        Refresh()
    end))
    t:Hide()
    tabs[i] = t
end

local rows = {}
for i = 1, POOL_ROWS do
    local r = Box("Button", panel)
    r.ppIndex = i
    r.ppLabel = NewText(r, "font")
    r.ppChip = Box("Frame", r)
    r.ppChipText = NewText(r.ppChip, "small")
    r.ppChipText:SetJustifyH("CENTER")
    r.ppChipText:SetPoint("CENTER", r.ppChip, "CENTER", 0, 0)
    r.ppRun = NewButton(r, nil, function()
        local e = r.ppEntry
        if not e or not e.def then return end
        if e.def.kind == "guided" then
            -- Start, or Cancel while the trial waits (it puts the old values back).
            if P.db and P.db.guided[e.id] then P.CancelGuided(e.def) else P.StartGuided(e.def) end
        else
            P.RunOne(e.def)
        end
    end)
    r.ppAnswer = {}
    for k = 1, 2 do
        r.ppAnswer[k] = NewButton(r, nil, function()
            local e = r.ppEntry
            if e and e.def then P.AnswerGuided(e.def, k) end
        end)
    end
    r:SetScript("OnClick", Guard(function()
        selectedRow = i
        Refresh()
    end))
    r:Hide()
    rows[i] = r
end

local details = NewText(panel, "small")
details:SetJustifyV("TOP")
details:SetWordWrap(true)
details:SetMaxLines(2)

local FOOTER = {
    { key = "runall", name = "PocketProbeRunAllButton", click = function() P.RunAllSafe() end },
    { key = "fight",  name = "PocketProbeFightButton",  click = function() P.RunFightTests() end },
    { key = "clean",  name = "PocketProbeCleanButton",  click = function() P.BeginClean() end },
    { key = "risky",  name = "PocketProbeRiskyButton",  click = function() P.ToggleOption("risky") end },
    { key = "vendor", name = "PocketProbeVendorButton", click = function() P.ToggleOption("vendor") end },
    { key = "auto",   name = "PocketProbeAutoButton",   click = function() P.ToggleOption("auto") end },
    { key = "save",   name = "PocketProbeSaveButton",   click = function() P.Reload() end },
}
local footer = {}
for i, spec in ipairs(FOOTER) do
    footer[i] = NewButton(panel, spec.name, function()
        spec.click()
        if panel:IsShown() then Refresh() end
    end)
end

-- The d-pad highlight: four gold edges around the button in focus.
local ring = CreateFrame("Frame", nil, panel)
ring:SetFrameLevel(panel:GetFrameLevel() + 40)
ring.edges = {}
for i = 1, 4 do
    local e = ring:CreateTexture(nil, "OVERLAY")
    e:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    ring.edges[i] = e
end
ring:Hide()

---------------------------------------------------------------------------
-- The big message (probe 0.5.0): a guided trial's question in letters twice
-- the panel's size, on a dark backing in the upper third of the screen,
-- under the Probe button. At most two lines, wrapped inside 60% of the
-- screen's width. A plain frame: it takes no clicks and no controller keys.
-- Run.lua shows it when the question starts and hides it when it is over.
---------------------------------------------------------------------------

local big = CreateFrame("Frame", "PocketProbeBigMessage", UIParent)
big:SetFrameStrata("HIGH")
big:EnableMouse(false)
big:Hide()
local bigBack = big:CreateTexture(nil, "BACKGROUND")
bigBack:SetAllPoints(big)
bigBack:SetColorTexture(0, 0, 0, 0.8)
local bigText = NewText(big, "big")
bigText:SetJustifyH("CENTER")
bigText:SetWordWrap(true)
bigText:SetMaxLines(2)
bigText:SetPoint("CENTER", big, "CENTER", 0, 0)

function P.ShowBig(text)
    factor = Factor()
    SetupFonts()
    UseFont(bigText, "big")
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if type(sw) ~= "number" or sw < 100 then sw = 1024 end
    if type(sh) ~= "number" or sh < 100 then sh = 768 end
    local width, pad = sw * 0.6, Px(SIZE.pad)
    bigText:SetWidth(width)
    bigText:SetText(tostring(text))
    big:ClearAllPoints()
    big:SetPoint("TOP", UIParent, "TOP", 0, -sh * 0.19)
    big:SetSize(width + pad * 2, Px(FONTS.big.size) * 2.5 + pad * 2)
    big:Show()
end

function P.HideBig()
    big:Hide()
end

---------------------------------------------------------------------------
-- What the panel shows
---------------------------------------------------------------------------

local CHIP_WORDS = { allowed = "Allowed", blocked = "Blocked", forbidden = "Forbidden", error = "Error" }

-- The chip for one trial: its text and colours.
local function ChipFor(entry)
    local db = P.db
    local g = db and db.guided[entry.id]
    if type(g) == "table" then
        if g.stage == "restart" then return "Restart the game", CHIP.value end
        if g.stage == "putback" then return "Not put back", CHIP.blocked end
        return "Waiting", CHIP.value
    end
    local last = db and db.last[entry.id]
    if type(last) ~= "table" or last.result == nil then return "Not run", CHIP.notrun end
    local result = tostring(last.result)
    if result == P.CANT_TELL then return "Can't tell", CHIP.info end
    local word = CHIP_WORDS[result]
    if result == "allowed" then return word, CHIP.allowed end
    if word then return word, CHIP.blocked end
    return result, CHIP.value
end

local function Short(text, limit)
    text = tostring(text):gsub("[\r\n]+", " ")
    if #text > limit then text = text:sub(1, limit) .. "..." end
    return text
end

-- One line of details for the row tapped last.
local function DetailsFor(entry)
    if not entry then return "" end
    local def = entry.def
    local db = P.db
    local g = db and db.guided[entry.id]
    if def and def.kind == "guided" then
        if type(g) == "table" then
            if g.stage == "putback" then
                local names = {}
                for name in pairs(type(g.old) == "table" and g.old or {}) do names[#names + 1] = tostring(name) end
                table.sort(names)
                if type(g.held) == "string" then names[#names + 1] = g.held end
                return "Could not put back " .. tconcat(names, ", ") .. ": tap Cancel to retry."
            end
            local step = (g.stage == "restart") and (def.steps or "Fully restart the game.") or (def.ask or "Answer with the two buttons.")
            return step .. " Cancel puts the old values back. Set: " .. tostring(g.notes or "") .. "."
        end
    end
    local last = db and db.last[entry.id]
    if type(last) ~= "table" then
        if def and def.kind == "guided" then return "Tap Start, follow the steps, then answer with the two buttons." end
        if not def then return "Recorded by itself when the game refuses one of its own actions in the probe's name." end
        if def.event then return "Recorded by itself when the event arrives." end
        return entry.id .. ": not run yet."
    end
    local parts = { entry.id .. " " .. tostring(last.result) .. (last.at and (" at " .. last.at) or "") }
    if last.func then parts[#parts + 1] = "function " .. tostring(last.func) end
    if last.message then parts[#parts + 1] = Short(last.message, 260) end
    if type(last.stack) == "string" and last.stack ~= "" then
        local lines = {}
        for line in last.stack:gmatch("[^\n]+") do
            lines[#lines + 1] = line
            if #lines == 2 then break end
        end
        parts[#parts + 1] = "stack " .. tconcat(lines, " < ")
    end
    return tconcat(parts, " · ")
end

local function RunDisabled(def)
    local db = P.db
    if not def or def.event then return true end
    if Recording() then return true end
    if def.risky and not (db and db.options.risky) then return true end
    if def.vendor and not (db and db.options.vendor) then return true end
    return false
end

-- The trials grouped into pages: one per area, split when it has more rows
-- than fit (rowsFit).
local function BuildPages(rowsFit)
    local db = P.db
    local byArea, order = {}, {}
    local list = (db and type(db.trials) == "table") and db.trials or P.trials
    for _, t in ipairs(list) do
        if type(t) == "table" and type(t.id) == "string" then
            local area = AreaName(t.area)
            if not byArea[area] then byArea[area] = {} end
            local def = P.trialById[t.id]
            local entries = byArea[area]
            entries[#entries + 1] = { id = t.id, label = (def and def.label) or Str(t.label) or t.id, def = def }
        end
    end
    for _, area in ipairs(AREA_ORDER) do
        if byArea[area] then order[#order + 1] = area end
    end
    for _, t in ipairs(list) do
        local area = type(t) == "table" and AreaName(t.area)
        if area and byArea[area] then
            local known = false
            for _, a in ipairs(order) do if a == area then known = true break end end
            if not known then order[#order + 1] = area end
        end
    end
    local out = {}
    rowsFit = max(rowsFit, 1)
    for _, area in ipairs(order) do
        local entries = byArea[area]
        local parts = floor((#entries + rowsFit - 1) / rowsFit)
        for p = 1, parts do
            local chunk = {}
            for k = (p - 1) * rowsFit + 1, min(p * rowsFit, #entries) do chunk[#chunk + 1] = entries[k] end
            out[#out + 1] = { label = parts > 1 and (area .. " " .. p) or area, area = area, entries = chunk }
        end
    end
    while #out > POOL_TABS do out[#out] = nil end
    return out
end
P.BuildPages = BuildPages

---------------------------------------------------------------------------
-- Layout and drawing (only while shown; nothing ticks)
---------------------------------------------------------------------------

local m = {}                             -- the sizes worked out by the last layout
local Nav                                -- below

local function Layout()
    factor = Factor()
    SetupFonts()
    m.button, m.gap, m.pad = Px(SIZE.button), Px(SIZE.gap), Px(SIZE.pad)
    m.small = Px(SIZE.small)
    border = max(Px(2), 1)
    m.border = border
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if type(sw) ~= "number" or sw < 100 then sw = 1024 end
    if type(sh) ~= "number" or sh < 100 then sh = 768 end
    m.w, m.h = min(sw * 0.96, Px(1180)), sh * 0.92
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetSize(m.w, m.h)
    Paint(panel, PANELFILL, GOLDBROWN)
    local bar = m.button + m.gap
    titleRule:ClearAllPoints()
    titleRule:SetPoint("TOPLEFT", panel, "TOPLEFT", border, -(border + bar))
    titleRule:SetSize(m.w - 2 * border, border)
    titleRule:SetColorTexture(GOLDBROWN[1], GOLDBROWN[2], GOLDBROWN[3], 1)
    local closeW = m.button * 2
    local closeX = m.w - (border + m.gap * 0.5) - closeW
    Place(closeButton, panel, closeX, border + m.gap * 0.5, closeW, m.button)
    SetButton(closeButton, "Close", "normal")
    UseFont(title, "title")
    title:ClearAllPoints()
    title:SetPoint("LEFT", panel, "TOPLEFT", m.pad, -(border + bar / 2))
    title:SetWidth(m.w * 0.32)
    statusLine:ClearAllPoints()
    statusLine:SetPoint("LEFT", panel, "TOPLEFT", m.pad + m.w * 0.32 + m.gap, -(border + bar / 2))
    local statusEnd = closeX
    if RecordingOffered() then
        local recordW, textW = m.button * 3.6, m.button * 3.4
        Place(recordButton, panel, closeX - m.gap - recordW, border + m.gap * 0.5, recordW, m.button)
        recordText:ClearAllPoints()
        recordText:SetPoint("RIGHT", recordButton, "LEFT", -m.gap, 0)
        recordText:SetWidth(textW)
        statusEnd = closeX - m.gap - recordW - m.gap - textW
        m.recordW = recordW
        recordButton:Show()
        recordText:Show()
    else
        recordButton:Hide()
        recordText:Hide()
    end
    statusLine:SetWidth(max(statusEnd - m.gap - (m.pad + m.w * 0.32 + m.gap), 10))
    -- The content area under the title bar.
    m.cx, m.cy = m.pad, border + bar + m.gap
    m.cw, m.ch = m.w - 2 * m.pad, m.h - m.cy - m.pad
    m.foot = m.cy + m.ch - m.button
    m.tw = m.button * TAB_WIDTH
    m.px, m.pw = m.cx + m.tw + m.gap, m.cw - m.tw - m.gap
    m.listH = m.foot - m.gap - m.cy - (m.small * 2.6 + m.gap)
    m.rh = m.button + m.gap * 0.3
    m.rowsFit = max(floor((m.listH + border) / (m.rh + border)), 1)
    m.rowsFit = min(m.rowsFit, POOL_ROWS)
    m.tabsH = m.foot - m.gap - m.cy
    -- Footer.
    local bw = (m.cw - (#footer - 1) * m.gap) / #footer
    for i, b in ipairs(footer) do
        Place(b, panel, m.cx + (i - 1) * (bw + m.gap), m.foot, bw, m.button)
    end
    m.footerW = bw
    -- Details.
    details:ClearAllPoints()
    details:SetPoint("TOPLEFT", panel, "TOPLEFT", m.px, -(m.cy + m.listH + m.gap * 0.5))
    details:SetWidth(m.pw)
    -- Rows: fixed places.
    for i, r in ipairs(rows) do
        local y = m.cy + (i - 1) * (m.rh + border)
        Place(r, panel, m.px, y, m.pw, m.rh)
        local runW, chipW = m.button * 2.2, m.button * 3.6
        local inner = m.gap * 0.15
        r.ppRun:ClearAllPoints()
        r.ppRun:SetPoint("TOPRIGHT", r, "TOPRIGHT", -m.pad, -inner)
        r.ppRun:SetSize(runW, m.button)
        r.ppChip:ClearAllPoints()
        r.ppChip:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(m.pad + runW + m.gap), -inner)
        r.ppChip:SetSize(chipW, m.button)
        r.ppChipText:SetWidth(chipW - m.gap * 0.8)
        local both = runW + chipW + m.gap
        -- The two answers share the chip's place; Cancel stays in Run's place.
        local answerW = (chipW - m.gap) / 2
        for k, b in ipairs(r.ppAnswer) do
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(m.pad + runW + m.gap + (2 - k) * (answerW + m.gap)), -inner)
            b:SetSize(answerW, m.button)
        end
        m.answerW = answerW
        r.ppLabel:ClearAllPoints()
        r.ppLabel:SetPoint("LEFT", r, "LEFT", m.pad, 0)
        m.labelW = max(m.pw - both - m.pad * 3, 10)
        r.ppLabel:SetWidth(m.labelW)
    end
end

local function ShowTabs()
    local n = #pages
    local gapTotal = (n - 1) * border
    local th = n > 0 and min(m.button, (m.tabsH - gapTotal) / n) or m.button
    local compact = th < m.button * 0.85
    for i, t in ipairs(tabs) do
        local page = pages[i]
        if page then
            Place(t, panel, m.cx, m.cy + (i - 1) * (th + border), m.tw, th)
            local selected = i == selectedPage
            local fill = selected and TAB_SELECTED or CARD
            Paint(t, fill, fill, 0)
            t.ppBar:ClearAllPoints()
            t.ppBar:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
            t.ppBar:SetSize(max(4, border * 2), th)
            t.ppBar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
            if selected then t.ppBar:Show() else t.ppBar:Hide() end
            local run = 0
            local last = P.db and P.db.last or {}
            for _, e in ipairs(page.entries) do
                if last[e.id] ~= nil then run = run + 1 end
            end
            t.ppName:SetText(page.label)
            t.ppCount:SetText(run .. " / " .. #page.entries .. " run")
            t.ppName:ClearAllPoints()
            t.ppCount:ClearAllPoints()
            if compact then
                -- One line: the name on the left, the count on the right.
                UseFont(t.ppName, "small")
                t.ppCount:SetJustifyH("RIGHT")
                t.ppCount:SetPoint("RIGHT", t, "RIGHT", -m.pad * 0.6, 0)
                t.ppCount:SetWidth(m.tw * 0.36)
                t.ppName:SetPoint("LEFT", t, "LEFT", m.pad, 0)
                t.ppName:SetWidth(m.tw * 0.64 - m.pad * 1.2)
            else
                UseFont(t.ppName, "tab")
                t.ppCount:SetJustifyH("LEFT")
                t.ppName:SetPoint("TOPLEFT", t, "TOPLEFT", m.pad, -th * 0.08)
                t.ppName:SetSize(m.tw - m.pad * 2, th * 0.55)
                t.ppCount:SetPoint("TOPLEFT", t, "TOPLEFT", m.pad, -th * 0.55)
                t.ppCount:SetSize(m.tw - m.pad * 2, th * 0.4)
            end
            t:Show()
        else
            t:Hide()
        end
    end
end

local function ShowRows()
    local page = pages[selectedPage]
    local entries = page and page.entries or {}
    local db = P.db
    local risky = db and db.options.risky
    for i, r in ipairs(rows) do
        local e = entries[i]
        r.ppEntry = e
        if e and i <= m.rowsFit then
            local selected = i == selectedRow
            local fill = selected and CARD_SELECTED or CARD
            Paint(r, fill, fill, 0)
            local def = e.def
            local dim = def and def.risky and not risky
            r.ppLabel:SetText(e.label .. ((def and def.risky) and " (risky)" or ""))
            -- A long name goes to the small font on two lines rather than being cut.
            FitLabel({ ppLabel = r.ppLabel }, m.labelW)
            Color(r.ppLabel, dim and LABEL_DIM or LABEL)
            local g = db and db.guided[e.id]
            if def and def.kind == "guided" and type(g) == "table" and g.stage == "ask" then
                r.ppChip:Hide()
                for k, b in ipairs(r.ppAnswer) do
                    SetButton(b, def.answers[k], "normal")
                    FitLabel(b, m.answerW - m.gap * 0.5)
                    b:Show()
                end
                SetButton(r.ppRun, "Cancel", "normal")
                r.ppRun:Show()
            else
                for _, b in ipairs(r.ppAnswer) do b:Hide() end
                local word, colours = ChipFor(e)
                Paint(r.ppChip, colours.fill, colours.border)
                r.ppChipText:SetText(word)
                Color(r.ppChipText, { 1, 1, 1 })
                r.ppChip:Show()
                if def and def.kind == "guided" then
                    if type(g) == "table" then
                        SetButton(r.ppRun, "Cancel", "normal")
                    else
                        SetButton(r.ppRun, def.start or "Start", "normal", (def.risky and not risky) or Recording())
                    end
                else
                    SetButton(r.ppRun, "Run", "normal", RunDisabled(def))
                end
                r.ppRun:Show()
            end
            r:Show()
        else
            r:Hide()
        end
    end
    local sel = entries[selectedRow]
    -- While a recording runs the trial buttons are dim: the reason comes first.
    details:SetText((Recording() and ("|cffffd100" .. RECORDING_NOTE .. "|r ") or "")
        .. "|cffffd100Details:|r " .. DetailsFor(sel))
end

local function ShowRecording()
    if not recordButton:IsShown() then return end
    local on = Recording()
    SetButton(recordButton, on and "Stop" or "Start recording", "normal")
    FitLabel(recordButton, m.recordW - m.gap * 0.5)
    recordText:SetText(P.RecordingText and P.RecordingText() or "")
    Color(recordText, on and { 1, 0.35, 0.3 } or DIM)
end

local function ShowFooter()
    local db = P.db
    local o = db and db.options or {}
    local function onOff(word, on) return word .. ": " .. (on and "On" or "Off"), on and "on" or "off" end
    local labels = {
        { "Run all safe", "normal" },
        { "Fight tests", "normal" },
        { "Clean run (reloads)", "normal" },
        { onOff("Risky", o.risky) },
        { onOff("Vendor", o.vendor) },
        { onOff("Auto", o.auto) },
        { "Save (reloads)", "normal" },
    }
    -- The three that start trials are dim while a recording runs.
    local recording = Recording()
    for i, b in ipairs(footer) do
        SetButton(b, labels[i][1], labels[i][2], recording and i <= 3)
        FitLabel(b, m.footerW - m.gap * 0.5)
    end
end

Refresh = function()
    if not panel:IsShown() or not m.button then return end
    local keep = pages[selectedPage] and pages[selectedPage].label
    pages = BuildPages(m.rowsFit)
    -- The same tab stays selected when the pages are worked out again.
    if keep then
        for i, page in ipairs(pages) do
            if page.label == keep then selectedPage = i break end
        end
    end
    if selectedPage > #pages then selectedPage = max(#pages, 1) end
    local count = pages[selectedPage] and #pages[selectedPage].entries or 0
    if selectedRow > count then selectedRow = max(count, 1) end
    title:SetText("Pocket Probe " .. tostring((P.db and P.db.probe) or P.VERSION))
    statusLine:SetText(tostring(P.status or "") .. (P.warning and (" — " .. P.warning) or ""))
    ShowTabs()
    ShowRows()
    ShowFooter()
    ShowRecording()
    if Nav then Nav.Draw() end
end
P.RefreshPanel = Refresh

P.OnRecord = function() if panel:IsShown() then Refresh() end end
P.OnStatus = function()
    if not panel:IsShown() then return end
    statusLine:SetText(tostring(P.status or "") .. (P.warning and (" — " .. P.warning) or ""))
    Refresh()
end

---------------------------------------------------------------------------
-- D-pad: Up / Down move along the tabs or the rows, Left / Right go between
-- the tabs, a row and its buttons, and along the footer; A presses, B closes.
-- Up from the first tab goes to the recording line's button when it shows
-- (that is how a recording is stopped with a controller); Down comes back.
---------------------------------------------------------------------------

local NAV_NAME = "PocketProbeNavButton"
local NAV_KEYS = { PADDUP = "UP", PADDDOWN = "DOWN", PADDLEFT = "LEFT", PADDRIGHT = "RIGHT", PAD1 = "A", PAD2 = "B" }

Nav = { zone = nil, sub = 1, foot = 1, down = {}, armed = false }

local navButton = CreateFrame("Button", NAV_NAME, UIParent)
navButton:SetSize(1, 1)
navButton:RegisterForClicks("AnyDown", "AnyUp")

-- The buttons of one row a d-pad stop can land on: the row, then its buttons.
local function RowStops(i)
    local r = rows[i]
    if not r or not r:IsShown() then return {} end
    local stops = { r }
    if r.ppAnswer[1]:IsShown() then
        stops[#stops + 1], stops[#stops + 2] = r.ppAnswer[1], r.ppAnswer[2]
    end
    if r.ppRun:IsShown() then stops[#stops + 1] = r.ppRun end
    return stops
end

local function VisibleRows()
    local n = 0
    for _, r in ipairs(rows) do if r:IsShown() then n = n + 1 end end
    return n
end

-- The frame in focus, or nil.
function Nav.Target()
    if Nav.zone == "top" then return recordButton end
    if Nav.zone == "tabs" then return tabs[selectedPage] end
    if Nav.zone == "rows" then
        local stops = RowStops(selectedRow)
        return stops[min(Nav.sub, #stops)]
    end
    if Nav.zone == "footer" then return footer[Nav.foot] end
    return nil
end

function Nav.Draw()
    local target = Nav.Target()
    if not target or not target:IsShown() then
        ring:Hide()
        return
    end
    local b = max(border * 2, 2)
    local e = ring.edges
    e[1]:ClearAllPoints(); e[1]:SetPoint("BOTTOMLEFT", target, "TOPLEFT", -b, 0); e[1]:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", b, 0); e[1]:SetHeight(b)
    e[2]:ClearAllPoints(); e[2]:SetPoint("TOPLEFT", target, "BOTTOMLEFT", -b, 0); e[2]:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", b, 0); e[2]:SetHeight(b)
    e[3]:ClearAllPoints(); e[3]:SetPoint("TOPRIGHT", target, "TOPLEFT", 0, 0); e[3]:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", 0, 0); e[3]:SetWidth(b)
    e[4]:ClearAllPoints(); e[4]:SetPoint("TOPLEFT", target, "TOPRIGHT", 0, 0); e[4]:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", 0, 0); e[4]:SetWidth(b)
    ring:Show()
end

local function Move(key)
    local zone = Nav.zone
    if not zone then
        Nav.zone = "tabs"
        return
    end
    local nRows = VisibleRows()
    if zone == "tabs" then
        if key == "UP" or key == "DOWN" then
            local n = #pages
            if n == 0 then return end
            if key == "DOWN" and selectedPage == n then
                Nav.zone = "footer"
                return
            end
            if key == "UP" and selectedPage == 1 and recordButton:IsShown() then
                Nav.zone = "top"
                return
            end
            selectedPage = (selectedPage - 1 + (key == "UP" and -1 or 1)) % n + 1
            selectedRow = 1
        elseif key == "RIGHT" and nRows > 0 then
            Nav.zone, Nav.sub = "rows", 1
        end
    elseif zone == "top" then
        if key == "DOWN" or not recordButton:IsShown() then Nav.zone = "tabs" end
    elseif zone == "rows" then
        if key == "UP" then
            if selectedRow > 1 then selectedRow = selectedRow - 1 end
        elseif key == "DOWN" then
            if selectedRow < nRows then selectedRow = selectedRow + 1 else Nav.zone = "footer" end
        elseif key == "LEFT" then
            if Nav.sub > 1 then Nav.sub = Nav.sub - 1 else Nav.zone = "tabs" end
        elseif key == "RIGHT" then
            if Nav.sub < #RowStops(selectedRow) then Nav.sub = Nav.sub + 1 end
        end
        local stops = #RowStops(selectedRow)
        if Nav.sub > stops then Nav.sub = max(stops, 1) end
    elseif zone == "footer" then
        if key == "LEFT" and Nav.foot > 1 then
            Nav.foot = Nav.foot - 1
        elseif key == "RIGHT" and Nav.foot < #footer then
            Nav.foot = Nav.foot + 1
        elseif key == "UP" then
            if nRows > 0 then
                Nav.zone, selectedRow, Nav.sub = "rows", nRows, 1
            else
                Nav.zone = "tabs"
            end
        end
    end
end

local function Press()
    local target = Nav.Target()
    if not target then
        Nav.zone = "tabs"
        return
    end
    if target.ppDisabled then return end
    local onClick = target:GetScript("OnClick")
    if onClick then onClick(target, "LeftButton", false) end
end

function Nav.Key(key, down)
    if not panel:IsShown() then return end
    if down ~= false then
        Nav.down[key] = true
        if key ~= "A" and key ~= "B" then
            Move(key)
            Refresh()
        end
        return
    end
    -- A and B act on release, and only after a press we saw.
    local saw = Nav.down[key]
    Nav.down[key] = nil
    if not saw then return end
    if key == "A" then
        Press()
        if panel:IsShown() then Refresh() end
    elseif key == "B" then
        panel:Hide()
    end
end

navButton:SetScript("OnClick", Guard(function(_, key, down) Nav.Key(key, down) end))

local function InFight()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, locked = pcall(InCombatLockdown)
    return ok and not P.IsSecret(locked) and locked and true or false
end

function Nav.Arm()
    if Nav.armed or not panel:IsShown() or InFight() then return end
    if type(SetOverrideBindingClick) ~= "function" or type(ClearOverrideBindings) ~= "function" then return end
    pcall(ClearOverrideBindings, panel)
    for key, name in pairs(NAV_KEYS) do
        pcall(SetOverrideBindingClick, panel, true, key, NAV_NAME, name)
    end
    Nav.armed = true
end

function Nav.Disarm()
    for key in pairs(Nav.down) do Nav.down[key] = nil end
    if not Nav.armed then return end
    if type(ClearOverrideBindings) == "function" then pcall(ClearOverrideBindings, panel) end
    Nav.armed = false
end
P.Nav = Nav

-- PLAYER_REGEN_DISABLED (lockdown starts after it) and _ENABLED, from Run.lua.
P.OnCombat = function(fight)
    if fight then
        Nav.Disarm()
        ring:Hide()
    elseif panel:IsShown() then
        Nav.Arm()
    end
end

---------------------------------------------------------------------------
-- Showing and hiding
---------------------------------------------------------------------------

panel:SetScript("OnShow", Guard(function()
    Layout()
    Nav.zone, Nav.sub, Nav.foot = nil, 1, 1
    Refresh()
    Nav.Arm()
end))

panel:SetScript("OnHide", Guard(function()
    Nav.Disarm()
    ring:Hide()
end))

-- For the offline tests.
P.panelTabs, P.panelRows, P.panelFooter, P.panelSizes = tabs, rows, footer, m
P.panelRecordText = recordText

function P.TogglePanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

function P.HidePanel()
    if panel:IsShown() then panel:Hide() end
end
