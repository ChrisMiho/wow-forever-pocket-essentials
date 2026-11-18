local ADDON_NAME, PE = ...

-- Menu background: a dark panel behind the game's pop-up menus.
--
-- On this client the game's new pop-up menus (the one on a quest in the quest
-- log is the one that matters) are drawn with no background, so their text
-- sits straight on whatever is behind them. With this feature on, a plain
-- dark panel of ours is shown right behind each menu while it is open.
--
-- How it keeps clear of the game's own menu code:
--   * The panel is our own frame with no name and no parent, like the menu
--     frames themselves. It is never a child of a game frame.
--   * Nothing is written to the menu frame, nothing is created on it and no
--     script on it is set or hooked. We only read its layer, level, size and
--     whether it is shown, and pin our panel to its corners.
--   * No game function is replaced.
--
-- Two ways of hearing that a menu opened:
--   1. The game's own announcements "MenuProxy.OnShow" / "OnHide" / "OnClose"
--      (EventRegistry). Every menu and side menu. Nothing of ours ticks.
--   2. A fallback for the quest log's menu only, in case the announcements do
--      not come on this client: a hook after the function that opens that
--      menu, which asks the menu manager for the open menu. Only this path
--      starts a short repeating check (4 times a second) and only while one
--      of its panels is on screen, because without the announcements nothing
--      else tells us the menu closed.
--
-- The hook cannot be taken off again, so it is put on once and does nothing
-- while the feature is off.

local type, pcall, pairs, ipairs, tostring = type, pcall, pairs, ipairs, tostring
local floor, max = math.floor, math.max

local OUT_X, OUT_Y = 6, 3                 -- how far the panel reaches past the menu
local FILL = { 0.05, 0.05, 0.05, 0.95 }
local EDGE = { 0.52, 0.52, 0.57, 1 }
local MAX_PANELS = 6
local MAX_LINES = 20                      -- "panel shown" lines per switch-on; after that only a count
local WATCH_SECONDS = 0.25
local ART = "common-dropdown-bg"          -- the art the game's own menu background uses
local QUEST_FN = "QuestMapLogTitleButton_CreateContextMenu"
local EV_SHOW, EV_HIDE, EV_CLOSE = "MenuProxy.OnShow", "MenuProxy.OnHide", "MenuProxy.OnClose"

local menuBg

local panels = {}        -- every panel made so far, in use or not
local byMenu = {}        -- [menu frame] = its panel
local listening = false  -- the announcements are registered
local questHooked = false
local triedLate = false  -- the hook was tried a second time (the quest log may load late)
local watching = false
local shownCount = 0
local saidBoth = false
local wrappedShown, wrappedHidden, wrappedClosed, wrappedQuestMenu

local function Say(text)
    if PE.debugOn then PE:Debug("menuBg", text) end
end

-- A size for the log: a whole number, or what PE.Plain makes of it.
local function Whole(v)
    if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then return tostring(floor(v + 0.5)) end
    return PE.Plain(v)
end

local function InUse()
    local n = 0
    for _ in pairs(byMenu) do n = n + 1 end
    return n
end

-- True for a frame of the game's we may read. A forbidden frame is left alone.
local function IsMenuFrame(menu)
    if type(menu) ~= "table" then return false end
    if type(menu.IsForbidden) == "function" then
        local ok, forbidden = pcall(menu.IsForbidden, menu)
        if not ok or forbidden then
            Say("menu skipped: forbidden")
            return false
        end
    end
    return type(menu.GetFrameLevel) == "function" and type(menu.GetFrameStrata) == "function"
        and type(menu.IsShown) == "function"
end

local function NewPanel()
    -- No parent: the game's controller navigation looks at every frame made
    -- with a parent, and the menus have none either.
    local f = CreateFrame("Frame")
    f:Hide()
    f:EnableMouse(false) -- taps go straight through it
    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(f)
    edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
    local fill = f:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(FILL[1], FILL[2], FILL[3], FILL[4])
    f.peEdge, f.peFill = edge, fill
    return f
end

local function AcquirePanel()
    for _, panel in ipairs(panels) do
        if not panel.peMenu then return panel end
    end
    if #panels >= MAX_PANELS then
        Say("no room (" .. MAX_PANELS .. " panels in use)")
        return nil
    end
    local panel = NewPanel()
    panels[#panels + 1] = panel
    return panel
end

local function Release(menu, why)
    local panel = menu ~= nil and byMenu[menu]
    if not panel then return end
    byMenu[menu] = nil
    panel.peMenu = nil
    panel:Hide()
    panel:ClearAllPoints()
    Say("panel hidden (" .. why .. ")")
end

local function ReleaseAll(why)
    for _, panel in ipairs(panels) do
        if panel.peMenu then Release(panel.peMenu, why) end
    end
end

-- Takes the panel off every menu that is no longer shown (a menu that closed
-- without an announcement).
local function Sweep()
    for _, panel in ipairs(panels) do
        local menu = panel.peMenu
        if menu then
            local ok, shown = pcall(menu.IsShown, menu)
            if not ok or not shown then Release(menu, "menu gone") end
        end
    end
end

-- Puts a panel behind `menu`. path: "announcement" or "quest hook".
local function Attach(menu, path)
    Sweep()
    if not IsMenuFrame(menu) then return false end
    -- Read before a panel is taken, so an error here leaves nothing half done.
    local strata = menu:GetFrameStrata()
    local level = max(0, menu:GetFrameLevel() - 1)
    local panel = byMenu[menu]
    if panel then
        -- The game reuses its menu frames: the same one may be shown again at another level.
        panel:SetFrameStrata(strata)
        panel:SetFrameLevel(level)
        return true
    end
    panel = AcquirePanel()
    if not panel then return false end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", menu, "TOPLEFT", -OUT_X, OUT_Y)
    panel:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", OUT_X, -OUT_Y)
    panel:SetFrameStrata(strata)
    panel:SetFrameLevel(level)
    panel.peMenu = menu
    byMenu[menu] = panel
    panel:Show()
    shownCount = shownCount + 1
    if PE.debugOn and shownCount <= MAX_LINES then
        Say("panel shown (" .. path .. "), menu " .. Whole(menu:GetWidth()) .. " x " .. Whole(menu:GetHeight())
            .. ", layer " .. PE.Plain(strata) .. " level " .. PE.Plain(menu:GetFrameLevel())
            .. ", panels in use " .. InUse())
    end
    return true
end

---------------------------------------------------------------------------
-- The fallback: the quest log's menu
---------------------------------------------------------------------------

local function Tick()
    watching = false
    if not menuBg:IsEnabled() then return end
    Sweep()
    if InUse() > 0 then
        watching = true
        menuBg:After(WATCH_SECONDS, Tick)
    end
end

local function StartWatch()
    if watching then return end
    watching = true
    menuBg:After(WATCH_SECONDS, Tick)
end

-- The menu manager's open menu, or nil.
local function OpenMenu()
    if type(Menu) ~= "table" or type(Menu.GetManager) ~= "function" then return nil end
    local ok, manager = pcall(Menu.GetManager)
    if not ok or type(manager) ~= "table" or type(manager.GetOpenMenu) ~= "function" then return nil end
    local ok2, menu = pcall(manager.GetOpenMenu, manager)
    if not ok2 or type(menu) ~= "table" then return nil end
    return menu
end

-- Runs after the game's function that opens the quest log's menu.
local function OnQuestMenu()
    if not menuBg:IsEnabled() then return end
    local menu = OpenMenu()
    if not menu then
        Say("quest hook ran but no open menu was found")
        return
    end
    if byMenu[menu] then
        if not saidBoth then
            saidBoth = true
            Say("quest menu opened, panel already there")
        end
        return
    end
    if Attach(menu, "quest hook") then StartWatch() end
end

local function TryQuestHook()
    if questHooked then return true end
    if type(hooksecurefunc) == "function" and type(_G[QUEST_FN]) == "function" then
        wrappedQuestMenu = wrappedQuestMenu or menuBg:Wrap(OnQuestMenu)
        if pcall(hooksecurefunc, QUEST_FN, wrappedQuestMenu) then questHooked = true end
    end
    return questHooked
end

---------------------------------------------------------------------------
-- The game's announcements (called as func(owner, ...))
---------------------------------------------------------------------------

local function OnMenuShown(_, menu)
    if not triedLate and not questHooked then
        triedLate = true
        if TryQuestHook() then Say("quest hook: put on late") end
    end
    Attach(menu, "announcement")
end

local function OnMenuHidden(_, menu)
    Release(menu, "hidden")
end

local function OnMenuClosed(_, menu)
    Release(menu, "closed")
end

---------------------------------------------------------------------------
-- Switch
---------------------------------------------------------------------------

local function YesNo(v) return v and "yes" or "no" end

local function OnEnable(mod)
    shownCount, saidBoth, watching, triedLate = 0, false, false, false

    -- Settles whether the game's own background art is missing on this client.
    if PE.debugOn then
        local art = "cannot tell"
        if C_Texture and C_Texture.GetAtlasInfo then
            local ok, info = pcall(C_Texture.GetAtlasInfo, ART)
            if ok then art = (type(info) == "table") and "present" or "missing" end
        end
        Say('game background art "' .. ART .. '": ' .. art)
    end

    local shown, hidden, closed = false, false, false
    if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function"
            and type(EventRegistry.UnregisterCallback) == "function" then
        wrappedShown = wrappedShown or mod:Wrap(OnMenuShown)
        wrappedHidden = wrappedHidden or mod:Wrap(OnMenuHidden)
        wrappedClosed = wrappedClosed or mod:Wrap(OnMenuClosed)
        -- Registered under the feature's own table (the game does not allow a number here).
        shown = pcall(EventRegistry.RegisterCallback, EventRegistry, EV_SHOW, wrappedShown, mod)
        hidden = pcall(EventRegistry.RegisterCallback, EventRegistry, EV_HIDE, wrappedHidden, mod)
        closed = pcall(EventRegistry.RegisterCallback, EventRegistry, EV_CLOSE, wrappedClosed, mod)
        listening = shown or hidden or closed
    end
    local hooked = TryQuestHook()
    local manager = type(Menu) == "table" and type(Menu.GetManager) == "function"

    Say("listening: shown " .. YesNo(shown) .. ", hidden " .. YesNo(hidden) .. ", closed " .. YesNo(closed)
        .. ", quest hook " .. YesNo(hooked) .. ", manager " .. YesNo(manager))
    -- Not a problem for the settings page: the feature stays on and does nothing.
    if not shown and not (hooked and manager) then
        Say("cannot listen for menus on this client; doing nothing")
    end
end

local function OnDisable(mod)
    if listening and type(EventRegistry) == "table" and type(EventRegistry.UnregisterCallback) == "function" then
        pcall(EventRegistry.UnregisterCallback, EventRegistry, EV_SHOW, mod)
        pcall(EventRegistry.UnregisterCallback, EventRegistry, EV_HIDE, mod)
        pcall(EventRegistry.UnregisterCallback, EventRegistry, EV_CLOSE, mod)
    end
    listening = false
    ReleaseAll("switched off")
    if shownCount > MAX_LINES then Say(shownCount .. " menus got a panel since switch-on") end
    shownCount, saidBoth, watching, triedLate = 0, false, false, false
end

menuBg = PE:RegisterModule({
    key = "menuBg",
    label = "Menu background",
    desc = "Puts a dark panel behind the game's pop-up menus, such as the menu on a quest in the quest log, so the text is easy to read.",
    order = 70,

    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
