-- Pocket Essentials: the hub (PE.Hub).
-- One round button that is always on screen. A tap opens the chat panel when
-- the chat feature is on, otherwise the settings. Holding it for a moment
-- always opens the settings. Also the entry in the minimap's addon list.
local ADDON_NAME, PE = ...

-- Called by the game's addon list button on the minimap as
-- func(addonName, mouseButtonName); see Blizzard_Minimap AddonCompartment.lua.
function PocketEssentials_OnAddonCompartmentClick(addonName, buttonName)
    if PE.Safe and PE.ToggleSettings then PE:Safe("core", PE.ToggleSettings, PE) end
end

local Hub = {}
PE.Hub = Hub

local type, tostring, xpcall = type, tostring, xpcall
local max = math.max

local HOLD_SECONDS = 0.6 -- press and hold this long to open the settings

-- point on the screen edge, x direction of the margin, y as a fraction of
-- the screen height from the middle. The corners themselves are left free
-- for the player frame, minimap, chat and bag bar.
local POSITIONS = {
    LEFT        = { point = "LEFT",  x = 1,  y = 0 },
    RIGHT       = { point = "RIGHT", x = -1, y = 0 },
    TOPLEFT     = { point = "LEFT",  x = 1,  y = 0.24 },
    TOP         = { point = "TOP",   x = 0,  y = 0 },
    BOTTOMLEFT  = { point = "LEFT",  x = 1,  y = -0.20 },
    BOTTOMRIGHT = { point = "RIGHT", x = -1, y = -0.20 },
}

-- For the settings panel, in the order shown.
Hub.POSITIONS = {
    { value = "LEFT", label = "Left" },
    { value = "RIGHT", label = "Right" },
    { value = "TOPLEFT", label = "Upper left" },
    { value = "TOP", label = "Top" },
    { value = "BOTTOMLEFT", label = "Lower left" },
    { value = "BOTTOMRIGHT", label = "Lower right" },
}

local COLOR_RING = { 1, 0.82, 0 }
local COLOR_FILL = { 0.07, 0.07, 0.10 }
local COLOR_PRESSED = { 0.45, 0.36, 0.06 }

local button, ring, fill, label, badge
local clickHandler, badgeText
local pressedAt, pressSerial = nil, 0

local function SetPressed(pressed)
    if not fill then return end
    local c = pressed and COLOR_PRESSED or COLOR_FILL
    fill:SetColor(c[1], c[2], c[3], 1)
end

local function UpdateBadge()
    if not button then return end
    if not badgeText then
        if badge then badge:Hide() end
        return
    end
    local UI = PE.UI
    local m = UI:Metrics()
    if not badge then
        badge = CreateFrame("Frame", nil, button)
        badge:SetFrameLevel(button:GetFrameLevel() + 3)
        badge.disc = UI:CreateDisc(badge, "ARTWORK", 0, 14)
        badge.disc:SetColor(0.88, 0.08, 0.08, 1)
        badge.text = badge:CreateFontString(nil, "OVERLAY", m.smallFont)
        if not badge.text:GetFont() and GameFontHighlight then badge.text:SetFontObject(GameFontHighlight) end
        badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
        badge.text:SetTextColor(1, 1, 1, 1)
    end
    local size = max(m.smallFontSize * 1.5, m.hub * 0.45)
    badge:SetSize(size, size)
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", button, "TOPRIGHT", -size * 0.22, -size * 0.22)
    badge.disc:Layout(badge, size)
    badge.text:SetText(badgeText)
    badge:Show()
end

-- Size and place the button from the current settings.
function Hub:Refresh()
    if not button then return end
    local UI = PE.UI
    local m = UI:Metrics()
    local size = m.hub
    button:SetSize(size, size)
    ring:Layout(button, size)
    fill:Layout(button, max(size - max(UI:Px(4), 2) * 2, 1))

    local key = PE.db and PE.db.ui and PE.db.ui.hubPos
    local pos = POSITIONS[key] or POSITIONS.LEFT
    local margin = UI:Px(10)
    local height = UIParent:GetHeight() or 768
    local x = pos.x * margin
    local y = pos.y * height
    if pos.point == "TOP" then y = -margin end
    button:ClearAllPoints()
    button:SetPoint(pos.point, UIParent, pos.point, x, y)
    UpdateBadge()
end

local function OnClick()
    local held = pressedAt and GetTime and (GetTime() - pressedAt) or 0
    pressedAt = nil
    if clickHandler and held < HOLD_SECONDS then
        local before = PE.errorSerial
        local ok = xpcall(clickHandler, PE.ErrorHandlerFor("hub"))
        if ok and PE.errorSerial == before then return end
        -- The handler failed: fall through to the settings so the owner is never stuck.
    end
    if clickHandler then PE:OpenSettings() else PE:ToggleSettings() end
end

local function Create()
    if button then return end
    local UI = PE.UI
    if not UI then return end -- UI.lua failed to load; /pe still works
    local m = UI:Metrics()

    button = CreateFrame("Button", "PocketEssentialsHubButton", UIParent)
    button:SetFrameStrata("HIGH") -- above the game world and normal windows, below our DIALOG panels
    button:SetClampedToScreen(true)

    ring = UI:CreateDisc(button, "BACKGROUND", 0, 24)
    ring:SetColor(COLOR_RING[1], COLOR_RING[2], COLOR_RING[3], 1)
    fill = UI:CreateDisc(button, "BORDER", 0, 24)
    fill:SetColor(COLOR_FILL[1], COLOR_FILL[2], COLOR_FILL[3], 1)

    label = button:CreateFontString(nil, "OVERLAY", m.font)
    if not label:GetFont() and GameFontHighlight then label:SetFontObject(GameFontHighlight) end
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetTextColor(COLOR_RING[1], COLOR_RING[2], COLOR_RING[3], 1)
    label:SetText("PE")

    button:SetScript("OnMouseDown", function()
        pressedAt = GetTime and GetTime() or nil
        pressSerial = pressSerial + 1
        SetPressed(true)
    end)
    button:SetScript("OnMouseUp", function()
        -- Keep the pressed colour a moment so a quick tap is still visible.
        local serial = pressSerial
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, function()
                if serial == pressSerial then SetPressed(false) end
            end)
        else
            SetPressed(false)
        end
    end)
    button:SetScript("OnHide", function() SetPressed(false) end)
    button:SetScript("OnClick", PE:Wrap("hub", OnClick))

    Hub.button = button
    Hub:Refresh()
    button:Show()
    UI:OnMetricsChanged(function() Hub:Refresh() end)
end

-- The chat feature sets its "open the chat panel" function here when it is
-- switched on, and nil when it is switched off.
function Hub:SetClickHandler(fn)
    clickHandler = type(fn) == "function" and fn or nil
end

-- e.g. "2" shows a red badge with that text; nil hides it.
function Hub:SetBadge(text)
    if text == nil or text == "" then
        badgeText = nil
    else
        badgeText = tostring(text)
    end
    if PE.Safe then PE:Safe("hub", UpdateBadge) else UpdateBadge() end
end

if PE.OnCoreLogin then PE:OnCoreLogin(Create) end
