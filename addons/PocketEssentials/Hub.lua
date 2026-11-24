-- Pocket Essentials: the hub (PE.Hub).
-- One round button that is always on screen. A tap opens the chat panel when
-- the chat feature is on, otherwise the settings. Holding it for a moment
-- always opens the settings. Also the entry in the minimap's addon list.
-- Its spot is one of the presets below, moved by the offset saved in "Move
-- on screen" (Move.lua); choosing a preset clears that offset.
-- While the world map is open at its normal size, the button sits on the
-- map's book icon instead (it is only anchored there, never parented), and
-- goes back to its spot when the map closes or goes full screen (the game
-- hides the book then). Hooks on the map's show / hide and after its
-- Maximize / Minimize re-place it; nothing ticks.
local ADDON_NAME, PE = ...

-- Called by the game's addon list button on the minimap as
-- func(addonName, mouseButtonName); see Blizzard_Minimap AddonCompartment.lua.
function PocketEssentials_OnAddonCompartmentClick(addonName, buttonName)
    if PE.Safe and PE.ToggleSettings then PE:Safe("core", PE.ToggleSettings, PE) end
end

local Hub = {}
PE.Hub = Hub

local type, tostring, xpcall, pcall, ipairs = type, tostring, xpcall, pcall, ipairs
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

local MOVE_KEY = "hub" -- its name in "Move on screen" (Move.lua)

-- Colour themes for the round button, picked by the "Button colour" setting
-- (ui.hubColor). Gold is the original look. Pure colour only, no art.
local THEMES = {
    gold = { ring = { 1, 0.82, 0 }, fill = { 0.07, 0.07, 0.10 }, pressed = { 0.45, 0.36, 0.06 } },
    horde = { ring = { 0.85, 0.15, 0.10 }, fill = { 0.18, 0.03, 0.03 }, pressed = { 0.45, 0.07, 0.05 } },
    alliance = { ring = { 0.35, 0.62, 1.00 }, fill = { 0.03, 0.08, 0.24 }, pressed = { 0.10, 0.25, 0.55 } },
}

local function Theme()
    local key = PE.db and PE.db.ui and PE.db.ui.hubColor
    return THEMES[key] or THEMES.gold
end

-- The colours of the chosen theme ({ ring =, fill =, pressed = }), for the
-- setup guide's pictures of the button.
function Hub:Colors()
    return Theme()
end

local button, ring, fill, label, badge
local clickHandler, badgeText
local pressedAt, pressSerial = nil, 0

local function SetPressed(pressed)
    if not fill then return end
    local theme = Theme()
    local c = pressed and theme.pressed or theme.fill
    fill:SetColor(c[1], c[2], c[3], 1)
end

local onMap = false -- the button sits on the map's book icon (for the debug line)
local baseLevel      -- the button's own drawing level, put back when it leaves the map

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
        Hub.badge = badge
        badge.disc = UI:CreateDisc(badge, "ARTWORK", 0, 14)
        badge.disc:SetColor(0.88, 0.08, 0.08, 1)
        badge.text = badge:CreateFontString(nil, "OVERLAY", m.smallFont)
        if not badge.text:GetFont() and GameFontHighlight then badge.text:SetFontObject(GameFontHighlight) end
        badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
        badge.text:SetTextColor(1, 1, 1, 1)
    end
    badge:SetFrameLevel(button:GetFrameLevel() + 3) -- every time: the button's level rises on the map
    local size = max(m.smallFontSize * 1.5, m.hub * 0.45)
    badge:SetSize(size, size)
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", button, "TOPRIGHT", -size * 0.22, -size * 0.22)
    badge.disc:Layout(badge, size)
    badge.text:SetText(badgeText)
    badge:Show()
end

-- Where the button goes: anchor point on UIParent, x, y and size (UI units),
-- from the chosen position plus the offset saved by "Move on screen", or the
-- controller layout's spot (see below).
local function Placement()
    local UI = PE.UI
    local size = UI:Metrics().hub
    local key = PE.db and PE.db.ui and PE.db.ui.hubPos
    local pos = POSITIONS[key] or POSITIONS.LEFT
    local Move, dx, dy = PE.Move, 0, 0
    if Move and Move.GetOffset then dx, dy = Move:GetOffset(MOVE_KEY) end
    -- With the controller layout placed, its spot is the default. A button the
    -- player moved, or put at another spot in the settings, stays as it was.
    local layout = PE.ControllerLayout
    if (key == nil or key == "LEFT") and dx == 0 and dy == 0 and type(layout) == "table"
        and type(layout.HubSpot) == "function" then
        local ok, point, lx, ly = pcall(layout.HubSpot, layout)
        if ok and type(point) == "string" and type(lx) == "number" and type(ly) == "number" then
            return point, lx, ly, size
        end
    end
    local margin = UI:Px(10)
    local height = UIParent:GetHeight() or 768
    local x = pos.x * margin
    local y = pos.y * height
    if pos.point == "TOP" then y = -margin end
    return pos.point, x + dx, y + dy, size
end

-- The map's book icon, while the map is open and the book is shown (not full
-- screen). Blizzard_SharedXML/PortraitFrame.lua:34; Blizzard_WorldMap.lua:18, :49-50, :64-65.
local function MapPortrait()
    local map = WorldMapFrame
    if type(map) ~= "table" or type(map.IsShown) ~= "function" or not map:IsShown() then return nil end
    local border = map.BorderFrame
    if type(border) ~= "table" or type(border.GetPortrait) ~= "function" then return nil end
    local ok, portrait = pcall(border.GetPortrait, border)
    if not ok or type(portrait) ~= "table" or type(portrait.IsShown) ~= "function" or not portrait:IsShown() then
        return nil
    end
    return portrait, border
end

-- Size and place the button from the current settings.
function Hub:Refresh()
    if not button then return end
    local theme = Theme()
    ring:SetColor(theme.ring[1], theme.ring[2], theme.ring[3], 1)
    label:SetTextColor(theme.ring[1], theme.ring[2], theme.ring[3], 1)
    SetPressed(false)
    local UI = PE.UI
    local point, x, y, size = Placement()
    button:SetSize(size, size)
    ring:Layout(button, size)
    fill:Layout(button, max(size - max(UI:Px(4), 2) * 2, 1))
    button:ClearAllPoints()
    local portrait, border = MapPortrait()
    if portrait then
        button:SetPoint("CENTER", portrait, "CENTER", 0, 0)
        -- The map's border is in the same layer (HIGH), and its pieces sit well
        -- above it: the book's container at +400, the ring art at +500, title and
        -- close button at +510 (PortraitFrame.lua:110-115). Draw above all of them.
        local top = baseLevel or button:GetFrameLevel()
        for _, f in ipairs({ border, portrait.GetParent and portrait:GetParent(), border.NineSlice,
                border.TitleContainer, border.CloseButton }) do
            if type(f) == "table" and type(f.GetFrameLevel) == "function" then
                local ok, level = pcall(f.GetFrameLevel, f)
                if ok and type(level) == "number" and level >= top then top = level + 1 end
            end
        end
        button:SetFrameLevel(top)
    else
        button:SetPoint(point, UIParent, point, x, y)
        if baseLevel then button:SetFrameLevel(baseLevel) end
    end
    if (portrait ~= nil) ~= onMap then
        onMap = portrait ~= nil
        if PE.debugOn then PE:Debug("hub", onMap and "on the map's book icon" or "back to its spot") end
    end
    UpdateBadge()
end

-- Hooks on the world map, put on once (hooks cannot be taken off again).
local mapHooked = false
local function HookMap()
    if mapHooked then return true end
    local map = WorldMapFrame
    if type(map) ~= "table" or type(map.HookScript) ~= "function" then return false end
    mapHooked = true
    local refresh = PE:Wrap("hub", function() Hub:Refresh() end)
    pcall(map.HookScript, map, "OnShow", refresh)
    pcall(map.HookScript, map, "OnHide", refresh)
    -- After full screen on / off (Blizzard_WorldMap.lua:40, :60). Not the game's
    -- "WorldMapMinimized" announcement: it comes before the book is shown again.
    if type(hooksecurefunc) == "function" then
        if type(map.Maximize) == "function" then pcall(hooksecurefunc, map, "Maximize", refresh) end
        if type(map.Minimize) == "function" then pcall(hooksecurefunc, map, "Minimize", refresh) end
    end
    return true
end

local function OnClick()
    local held = pressedAt and GetTime and (GetTime() - pressedAt) or 0
    pressedAt = nil
    if clickHandler and held < HOLD_SECONDS then
        local before = PE.errorSerial
        local ok = xpcall(clickHandler, PE.ErrorHandlerFor("hub"))
        if ok and PE.errorSerial == before then return end
        -- The handler failed: fall through to the settings so the player is never stuck.
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
    baseLevel = button:GetFrameLevel()

    ring = UI:CreateDisc(button, "BACKGROUND", 0, 24)
    fill = UI:CreateDisc(button, "BORDER", 0, 24)

    label = button:CreateFontString(nil, "OVERLAY", m.font)
    if not label:GetFont() and GameFontHighlight then label:SetFontObject(GameFontHighlight) end
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetText("PE")
    Hub.ring, Hub.fill, Hub.label = ring, fill, label

    button:SetScript("OnMouseDown", PE:Wrap("hub", function()
        pressedAt = GetTime and GetTime() or nil
        pressSerial = pressSerial + 1
        SetPressed(true)
    end))
    button:SetScript("OnMouseUp", PE:Wrap("hub", function()
        -- Keep the pressed colour a moment so a quick tap is still visible.
        local serial = pressSerial
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, PE:Wrap("hub", function()
                if serial == pressSerial then SetPressed(false) end
            end))
        else
            SetPressed(false)
        end
    end))
    button:SetScript("OnHide", PE:Wrap("hub", function() SetPressed(false) end))
    button:SetScript("OnClick", PE:Wrap("hub", OnClick))

    Hub.button = button
    if not HookMap() then
        -- The map addon may load later; once its hook is on, nothing more to wait for.
        PE:RegisterCoreEvent("ADDON_LOADED", "hub", function(_, name)
            if name == "Blizzard_WorldMap" and HookMap() then
                PE:UnregisterCoreEvent("ADDON_LOADED", "hub")
                Hub:Refresh()
            end
        end)
    end
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

-- Movable from "Move on screen". Always listed; the box covers the whole button.
if PE.Move and PE.Move.Register then
    PE.Move:Register({
        key = MOVE_KEY,
        label = "Round button",
        order = 30,
        available = function() return true end,
        apply = function() Hub:Refresh() end,
        reset = function() PE:SetUISetting("hubPos", "LEFT") end,
        outline = function(box)
            local point, x, y, size = Placement()
            box:ClearAllPoints()
            box:SetPoint(point, UIParent, point, x, y)
            box:SetSize(size, size)
        end,
    })
end
