-- Pocket Essentials: the settings panel and its Errors page.
-- A standalone window made of large buttons (no Blizzard settings rows).
-- Built the first time it is opened; redrawn only when something changes.
local ADDON_NAME, PE = ...

local type, tostring, tonumber, ipairs, pcall = type, tostring, tonumber, ipairs, pcall
local max, min, ceil, floor = math.max, math.min, math.ceil, math.floor

local PANEL_NAME = "PocketEssentialsSettingsPanel"
local TITLE_MAIN = "Pocket Essentials"
local TITLE_ERRORS = "Pocket Essentials - Errors"

local COLOR = {
    font = { 1, 1, 1 },
    small = { 0.84, 0.84, 0.84 },
    title = { 1, 0.82, 0 },
    option = { 1, 0.82, 0 },
    status = { 0.65, 0.85, 1 },
    warn = { 1, 0.60, 0.20 },
    dim = { 0.62, 0.62, 0.62 },
}

local UI           -- PE.UI, set when the panel is built
local M            -- current metrics
local panel, area
local header = {}  -- fixed widgets above the scrolling list
local pools = {}
local navList = {} -- tappable buttons in reading order, rebuilt on every redraw
local page = "main"
local drawnPage = "main"
local built, buildFailed = false, false
local refreshing, refreshAgain = false, false

---------------------------------------------------------------------------
-- Pools: widgets are reused on every redraw, never thrown away
---------------------------------------------------------------------------

local function NewPool(create)
    return { items = {}, used = 0, shown = 0, create = create }
end

local function Acquire(pool)
    pool.used = pool.used + 1
    local item = pool.items[pool.used]
    if not item then
        item = pool.create()
        pool.items[pool.used] = item
    end
    if pool.used > pool.shown then pool.shown = pool.used end
    item:Show()
    return item
end

local function BeginPools()
    for _, pool in pairs(pools) do pool.used = 0 end
end

local function EndPools()
    for _, pool in pairs(pools) do
        for i = pool.used + 1, pool.shown do pool.items[i]:Hide() end
        pool.shown = pool.used
    end
end

---------------------------------------------------------------------------
-- Placing things in the list (y grows downwards from the top of the list)
---------------------------------------------------------------------------

local function Escape(text)
    return (tostring(text):gsub("|", "||"))
end

local function TextHeight(fontString, kind, text, width)
    local size = (kind == "small" and M.smallFontSize) or (kind == "title" and M.fontSize * 1.12) or M.fontSize
    local ok, height = pcall(fontString.GetStringHeight, fontString)
    if ok and type(height) == "number" and height >= size * 0.8 then return height end
    -- The game could not measure it yet: estimate from the text length.
    local perLine = max(floor(width / (size * 0.5)), 1)
    local lines = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + max(ceil(#line / perLine), 1)
    end
    return max(lines, 1) * size * 1.2
end

local function SetText(fontString, kind, text, width, color)
    text = text == nil and "" or tostring(text)
    fontString:SetWidth(max(width, 10))
    fontString:SetText(text)
    local c = color or COLOR[kind] or COLOR.font
    fontString:SetTextColor(c[1], c[2], c[3], 1)
    return TextHeight(fontString, kind, text, width)
end

local function PlaceText(kind, text, x, y, width, color)
    local fontString = Acquire(pools[kind])
    fontString:ClearAllPoints()
    fontString:SetPoint("TOPLEFT", area.child, "TOPLEFT", x, -y)
    return SetText(fontString, kind, text, width, color)
end

local function PlaceLine(y, width)
    local line = Acquire(pools.line)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", area.child, "TOPLEFT", 0, -y)
    line:SetSize(max(width, 1), M.border)
    return M.border
end

local function ResetButton(btn)
    btn:SetSelected(false)
    btn:SetStyle("normal")
    btn:SetBadgeText(nil)
    btn:ClearAllPoints()
end

-- One button at a fixed place and size.
local function PlaceButton(text, x, y, width, height, style, onClick)
    local btn = Acquire(pools.button)
    ResetButton(btn)
    btn:SetLabel(text)
    btn:SetSize(width, height)
    btn:SetPoint("TOPLEFT", area.child, "TOPLEFT", x, -y)
    if style then btn:SetStyle(style) end
    btn:SetScript("OnClick", onClick)
    btn.peScrollTop, btn.peScrollBottom = y, y + height
    navList[#navList + 1] = btn
    return btn
end

-- A run of buttons sized to their labels, wrapping onto new lines.
-- items: { { label =, selected =, style =, onClick = }, ... }. Returns the new y.
local function FlowButtons(items, x0, y, maxWidth, minWidth)
    local x, height = x0, M.button
    for i = 1, #items do
        local item = items[i]
        local btn = Acquire(pools.button)
        ResetButton(btn)
        btn:SetLabel(item.label)
        btn:SetHeight(height)
        local width = btn:FitWidth(minWidth or M.button * 2.2, maxWidth)
        if x > x0 and x + width > x0 + maxWidth then
            x = x0
            y = y + height + M.gap
        end
        btn:SetPoint("TOPLEFT", area.child, "TOPLEFT", x, -y)
        if item.style then btn:SetStyle(item.style) end
        btn:SetSelected(item.selected)
        btn:SetScript("OnClick", item.onClick)
        btn.peScrollTop, btn.peScrollBottom = y, y + height
        navList[#navList + 1] = btn
        x = x + width + M.gap
    end
    return y + height
end

---------------------------------------------------------------------------
-- Main page
---------------------------------------------------------------------------

local function ChooseOption(mod, opt, value)
    if type(mod.opts) ~= "table" then return end
    mod.opts[opt.key] = value
    if type(opt.OnChange) == "function" then PE:Safe(mod.key, opt.OnChange, mod, value) end
    PE:RefreshSettings()
end

local function BuildOptions(mod, y, width)
    local x = M.pad * 2
    local innerWidth = width - x - M.gap
    for _, opt in ipairs(mod.options) do
        if type(opt) == "table" then
            if type(opt.choices) == "table" and opt.key ~= nil then
                if type(opt.label) == "string" and opt.label ~= "" then
                    y = y + PlaceText("small", opt.label, x, y, innerWidth, COLOR.option) + M.gap * 0.4
                end
                local current = type(mod.opts) == "table" and mod.opts[opt.key]
                local items = {}
                for _, choice in ipairs(opt.choices) do
                    if type(choice) == "table" then
                        local value = choice.value
                        items[#items + 1] = {
                            label = tostring(choice.label ~= nil and choice.label or value),
                            selected = (current == value),
                            onClick = PE:Wrap("core", function() ChooseOption(mod, opt, value) end),
                        }
                    end
                end
                y = FlowButtons(items, x, y, innerWidth) + M.gap
            elseif type(opt.action) == "function" then
                local items = { {
                    label = (type(opt.label) == "string" and opt.label ~= "") and opt.label or "Do it",
                    onClick = PE:Wrap("core", function()
                        PE:Safe(mod.key, opt.action, mod)
                        PE:RefreshSettings()
                    end),
                } }
                y = FlowButtons(items, x, y, innerWidth, M.button * 4) + M.gap
            end
        end
    end
    return y
end

local function BuildModuleRow(mod, y, width, separator)
    if separator then
        y = y + PlaceLine(y, width) + M.gap
    else
        y = y + M.gap * 0.5
    end
    local key = mod.key
    local state, detail = PE:GetModuleState(key)
    local savedOn = PE:IsModuleSavedOn(key)
    local toggleWidth = M.button * 2.8
    local textX = M.gap
    local textWidth = width - toggleWidth - textX - M.pad

    local title = Escape(mod.label)
    if mod.experimental then title = title .. "   |cffff9a33Experimental|r" end
    local ty = y + M.gap * 0.3
    ty = ty + PlaceText("font", title, textX, ty, textWidth) + M.gap * 0.3
    if type(mod.desc) == "string" and mod.desc ~= "" then
        ty = ty + PlaceText("small", mod.desc, textX, ty, textWidth) + M.gap * 0.3
    end
    if type(mod.status) == "function" then
        local ok, status = PE:Safe(key, mod.status, mod)
        if ok then
            if type(status) == "table" then
                local lines = {}
                for i = 1, #status do lines[i] = tostring(status[i]) end
                status = table.concat(lines, "\n")
            end
            if type(status) == "string" and status ~= "" then
                ty = ty + PlaceText("small", status, textX, ty, textWidth, COLOR.status) + M.gap * 0.3
            end
        end
    end
    if state == "blocked" then
        ty = ty + PlaceText("small", detail or "This cannot be switched on right now.", textX, ty, textWidth, COLOR.warn) + M.gap * 0.3
    elseif state == "failed" then
        ty = ty + PlaceText("small", "Switched on, but it hit a problem. See Errors at the bottom of this list.", textX, ty, textWidth, COLOR.warn) + M.gap * 0.3
    end
    local rowHeight = max(M.row, ty - y)

    local label, style
    if state == "blocked" then
        label, style = "OFF", "disabled"
    elseif state == "on" then
        label, style = "ON", "on"
    elseif state == "failed" then
        label, style = "ON, problem", "warn"
    else
        label, style = "OFF", "off"
    end
    local toggle = PlaceButton(label, width - toggleWidth, y + (M.row - M.button) * 0.5, toggleWidth, M.button, style,
        PE:Wrap("core", function()
            if state == "blocked" then return end
            PE:SetModuleEnabled(key, not savedOn)
        end))
    -- When the controller lands on the switch, bring the whole row into view.
    toggle.peScrollTop, toggle.peScrollBottom = y, y + rowHeight

    y = y + rowHeight + M.gap * 0.5
    if state == "on" and type(mod.options) == "table" then
        y = BuildOptions(mod, y, width)
    end
    return y
end

local SIZE_CHOICES = {
    { value = "small", label = "Small" },
    { value = "medium", label = "Medium" },
    { value = "large", label = "Large" },
}

local function BuildCoreSection(y, width)
    local x = M.pad * 2
    local innerWidth = width - x - M.gap
    local ui = PE.db and PE.db.ui or {}

    y = y + PlaceLine(y, width) + M.gap
    y = y + PlaceText("title", TITLE_MAIN, M.gap, y, width - M.gap * 2) + M.gap

    y = y + PlaceText("small", "Button size", x, y, innerWidth, COLOR.option) + M.gap * 0.4
    local items = {}
    for i, choice in ipairs(SIZE_CHOICES) do
        local value = choice.value
        items[i] = {
            label = choice.label,
            selected = (ui.size == value),
            onClick = PE:Wrap("core", function() PE:SetUISetting("size", value) end),
        }
    end
    y = FlowButtons(items, x, y, innerWidth) + M.gap

    local positions = PE.Hub and PE.Hub.POSITIONS
    if type(positions) == "table" then
        y = y + PlaceText("small", "Round button position", x, y, innerWidth, COLOR.option) + M.gap * 0.4
        items = {}
        for i, choice in ipairs(positions) do
            local value = choice.value
            items[i] = {
                label = choice.label,
                selected = (ui.hubPos == value),
                onClick = PE:Wrap("core", function() PE:SetUISetting("hubPos", value) end),
            }
        end
        y = FlowButtons(items, x, y, innerWidth) + M.gap
        y = y + PlaceText("small", "Tip: press and hold the round button to open this window.", x, y, innerWidth, COLOR.dim) + M.gap
    end

    local count = #PE.errors
    items = { {
        label = "Errors (" .. count .. ")",
        style = count > 0 and "warn" or nil,
        onClick = PE:Wrap("core", function() PE:OpenSettings("errors") end),
    } }
    y = FlowButtons(items, x, y, innerWidth, M.button * 4)
    return y + M.pad
end

local function BuildMain(width)
    local y = 0
    local mods = PE.moduleList
    for i = 1, #mods do
        y = BuildModuleRow(mods[i], y, width, i > 1)
    end
    if #mods == 0 then
        y = y + M.gap
        y = y + PlaceText("font", "No features were loaded.", M.gap, y, width - M.gap * 2) + M.gap
    end
    return BuildCoreSection(y, width)
end

---------------------------------------------------------------------------
-- Errors page
---------------------------------------------------------------------------

local function BuildErrors(width)
    local x = M.gap
    local innerWidth = width - x * 2
    local y = M.gap * 0.5
    local list = PE.errors
    if #list == 0 then
        return y + PlaceText("font", "No errors recorded.", x, y, innerWidth) + M.gap
    end
    local first = true
    for i = 1, #list do
        local e = list[i]
        if type(e) == "table" then
            if not first then y = y + PlaceLine(y, width) + M.gap end
            first = false
            local head = Escape(PE:ModuleLabel(e.module)) .. "   x" .. tostring(tonumber(e.count) or 1)
            if type(e.last) == "number" and e.last > 0 then
                local ok, when = pcall(date, "%b %d %H:%M", e.last)
                if ok and type(when) == "string" then head = head .. "   last: " .. when end
            end
            y = y + PlaceText("font", head, x, y, innerWidth, COLOR.title) + M.gap * 0.3
            y = y + PlaceText("small", Escape(e.msg), x, y, innerWidth, COLOR.font) + M.gap * 0.3
            if type(e.stack) == "string" and e.stack ~= "" then
                y = y + PlaceText("small", Escape(e.stack), x, y, innerWidth, COLOR.dim)
            end
            y = y + M.gap
        end
    end
    return y
end

---------------------------------------------------------------------------
-- Fixed header above the list
---------------------------------------------------------------------------

local function LayoutHeader(width)
    local y = 0
    local content = panel.content

    if PE.oldQuestDotsLoaded then
        header.warn:ClearAllPoints()
        header.warn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + SetText(header.warn, "small", "The old QuestDots folder is still installed. Delete it from AddOns.", width, COLOR.warn) + M.gap
        header.warn:Show()
    else
        header.warn:Hide()
    end

    local reasons = PE.reloadReasons
    if page == "main" and type(reasons) == "table" and #reasons > 0 then
        local buttonWidth = M.button * 4.5
        local lines = {}
        for i = 1, min(#reasons, 2) do
            lines[i] = Escape(reasons[i].label) .. ": " .. Escape(reasons[i].reason)
        end
        header.reloadButton:ClearAllPoints()
        header.reloadButton:SetSize(buttonWidth, M.button)
        header.reloadButton:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        header.reloadButton:Show()
        header.reloadText:ClearAllPoints()
        header.reloadText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        local textHeight = SetText(header.reloadText, "small", table.concat(lines, "\n"), width - buttonWidth - M.gap, COLOR.warn)
        header.reloadText:Show()
        y = y + max(M.button, textHeight) + M.gap
        navList[#navList + 1] = header.reloadButton
    else
        header.reloadButton:Hide()
        header.reloadText:Hide()
    end

    if page == "errors" then
        local buttonWidth = M.button * 3.5
        header.back:ClearAllPoints()
        header.back:SetSize(buttonWidth, M.button)
        header.back:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        header.back:Show()
        header.clear:ClearAllPoints()
        header.clear:SetSize(buttonWidth, M.button)
        header.clear:SetPoint("TOPLEFT", content, "TOPLEFT", buttonWidth + M.gap, -y)
        header.clear:Show()
        y = y + M.button + M.gap
        navList[#navList + 1] = header.back
        navList[#navList + 1] = header.clear
    else
        header.back:Hide()
        header.clear:Hide()
    end
    return y
end

---------------------------------------------------------------------------
-- Redraw
---------------------------------------------------------------------------

local function DoRefresh()
    M = UI:Metrics()
    for i = #navList, 1, -1 do navList[i] = nil end
    BeginPools()

    panel:SetTitle(page == "errors" and TITLE_ERRORS or TITLE_MAIN)
    local contentWidth, contentHeight = panel.contentWidth, panel.contentHeight
    local headerHeight = LayoutHeader(contentWidth)
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -headerHeight)
    area:Layout(contentWidth, max(contentHeight - headerHeight, M.button * 2 + M.gap))

    local width = area.viewWidth
    local total
    if page == "errors" then
        total = BuildErrors(width)
    else
        total = BuildMain(width)
    end
    EndPools()
    area:SetContentHeight(total)

    if page == "errors" then
        -- Nothing in the error list can take the controller highlight, so
        -- the paging buttons do.
        navList[#navList + 1] = area.upButton
        navList[#navList + 1] = area.downButton
    end
    navList[#navList + 1] = panel.closeButton
    if page ~= drawnPage then
        -- A different page: if the controller highlight is in use, restart it at the top.
        drawnPage = page
        if panel.peNavFocus then panel:NavSetFocus(navList[1]) end
    end
    panel:NavRefresh()
end

local function Refresh()
    if not built or not panel:IsShown() then return end
    if refreshing then
        refreshAgain = true
        return
    end
    refreshing = true
    local passes = 0
    repeat
        refreshAgain = false
        PE:Safe("core", DoRefresh)
        passes = passes + 1
    until not refreshAgain or passes >= 3
    refreshing = false
end

---------------------------------------------------------------------------
-- Building the window (first open only)
---------------------------------------------------------------------------

local function PanelSize()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if type(screenWidth) ~= "number" or screenWidth < 100 then screenWidth = 1024 end
    if type(screenHeight) ~= "number" or screenHeight < 100 then screenHeight = 768 end
    return min(screenWidth * 0.96, UI:Px(1180)), screenHeight * 0.92
end

local function Build()
    UI = PE.UI
    M = UI:Metrics()
    local width, height = PanelSize()
    panel = UI:CreatePanel(PANEL_NAME, TITLE_MAIN, width, height)
    area = UI:CreateScrollArea(panel.content)

    pools.button = NewPool(function() return UI:CreateButton(area.child, "") end)
    pools.font = NewPool(function() return UI:CreateText(area.child, "font") end)
    pools.small = NewPool(function() return UI:CreateText(area.child, "small") end)
    pools.title = NewPool(function() return UI:CreateText(area.child, "title") end)
    pools.line = NewPool(function()
        local line = area.child:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.30, 0.30, 0.34, 1)
        return line
    end)

    header.warn = UI:CreateText(panel.content, "small")
    header.reloadText = UI:CreateText(panel.content, "small")
    header.reloadButton = UI:CreateButton(panel.content, "Reload now")
    header.reloadButton:SetStyle("warn")
    -- Called straight from the tap: reloading needs a real button press.
    header.reloadButton:SetScript("OnClick", function() PE:ReloadNow() end)
    header.back = UI:CreateButton(panel.content, "Back")
    header.back:SetScript("OnClick", PE:Wrap("core", function() PE:OpenSettings() end))
    header.clear = UI:CreateButton(panel.content, "Clear")
    header.clear:SetScript("OnClick", PE:Wrap("core", function() PE:ClearErrors() end))

    UI:AttachNav(panel, function() return navList end)
    panel.navOnFocus = function(btn)
        if btn.peScrollTop then area:ScrollIntoView(btn) end
    end

    UI:OnMetricsChanged(function()
        if not built then return end
        local newWidth, newHeight = PanelSize()
        panel:SetPanelSize(newWidth, newHeight)
        Refresh()
    end)
end

---------------------------------------------------------------------------
-- Public entry points (replace the placeholders in Core.lua)
---------------------------------------------------------------------------

function PE:OpenSettings(which)
    if not built and not buildFailed then
        if PE.UI and PE:Safe("core", Build) then
            built = true
        else
            buildFailed = true
            if panel then pcall(panel.Hide, panel) end
        end
    end
    if not built then
        self:Print("The settings window could not be opened. The latest problems are listed here instead.")
        self:PrintErrors()
        return
    end
    local newPage = (which == "errors") and "errors" or "main"
    if newPage ~= page then
        page = newPage
        area.offset = 0
    end
    if not panel:IsShown() then panel:Show() end
    panel:Raise()
    Refresh()
end

function PE:CloseSettings()
    if built and panel:IsShown() then panel:Hide() end
end

function PE:ToggleSettings()
    if built and panel:IsShown() then
        panel:Hide()
    else
        self:OpenSettings()
    end
end

-- Does nothing unless the window is open.
function PE:RefreshSettings()
    Refresh()
end
