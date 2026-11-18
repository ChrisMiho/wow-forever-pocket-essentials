-- Pocket Essentials: the setup guide (PE.Setup).
-- A window of a few screens that explains each feature in plain words and
-- lets the player switch on the ones they want. Every feature starts off;
-- this is how a player finds out what exists.
--
-- It opens by itself a moment after the first loading screen, on an account
-- that never pressed Finish or Skip in it (PocketEssentialsDB.setup is then
-- nil; Finish stores "finished", Skip stores "skipped"). It can be opened
-- again from the settings ("Setup guide") and with /pe setup.
--
-- A switch here is the switch of the settings window: both read
-- PE:GetModuleSwitch and write through PE:SetModuleEnabled. This file never
-- writes the saved on/off table itself.
--
-- Nothing is built until the guide is first opened. It has no per-frame code.
-- While open it listens for one thing (a fight starting, which hides it);
-- while closed it listens for nothing, except the single "fight ended" wait
-- after a fight hid it or kept it from opening at login.
local ADDON_NAME, PE = ...

local Setup = {}
PE.Setup = Setup

local type, tostring, ipairs, pcall = type, tostring, ipairs, pcall
local max, min, ceil, floor = math.max, math.min, math.ceil, math.floor

local PANEL_NAME = "PocketEssentialsSetupPanel" -- the prefix matters: our windows close each other by it
local TITLE = "Pocket Essentials - Setup guide"
local FIRST_LOGIN_DELAY = 1.5 -- seconds after the first loading screen

local TEXT_CLOSED = "Setup guide closed. It will show again next time you log in. Press Skip in it to stop that. "
    .. "You can open it any time from the settings."
local TEXT_FIGHT = "The setup guide cannot be opened during a fight. Try again afterwards."
local TEXT_BROKEN = "The setup guide could not be opened. See Errors in the settings."
local TEXT_NOTHING_ON = "Nothing is switched on yet. That is fine: you can do it later in the settings."

---------------------------------------------------------------------------
-- The screens. A new feature is one row.
--
-- A screen: { id =, title =, text =, rows = { ... } }
--   text: one string; "\n\n" separates paragraphs.
--   rows: optional. A row is { key = <feature key>, title = <optional>, text = <string> }.
--         title defaults to the feature's own label.
--   A row is shown only when its feature is in this build (PE:GetModule(key)).
--   A screen that has a rows table but no row left is skipped.
--   A screen with no rows table (welcome, layout) is always shown.
--   id "finish" is drawn by its own function (the summary).
-- Rows are for features with a switch. A setting that is a choice (sizes,
-- positions) is named in the text and left to the settings window.
---------------------------------------------------------------------------

local SCREENS = {
    { id = "welcome", title = "Welcome to Pocket Essentials",
      text = "Pocket Essentials adds a few helpers for playing on a handheld. Every helper starts switched off. "
          .. "The next screens explain each one in a few lines and let you switch on the ones you want."
          .. "\n\nUse the touch screen, or the d-pad to move the blue highlight, A to press and B to close."
          .. "\n\nNothing here is final. Every switch is also in the settings, and you can open this guide again from there." },

    { id = "quests", title = "Quests",
      text = "Quest icons and Quest arrow show where to go for the quests in your quest log. They get their "
          .. "locations from the QuestieDB addon, which comes with Pocket Essentials. Menu background makes the "
          .. "quest log's menu easier to read.",
      rows = {
          { key = "questIcons",
            text = "Puts an icon on the world map and the minimap at each place where a quest objective is: "
                .. "something to kill, loot, use or hand in. It also hides the game's blue quest areas. To start "
                .. "with it shows your tracked quests and up to five spots for each objective. Tap an icon on the "
                .. "map to read what it is." },
          { key = "questArrow",
            text = "Shows an arrow on screen that points to the nearest objective of the quest you have focused, "
                .. "with the distance and the quest's name. To focus a quest, open the quest log, select the "
                .. "quest and choose Focus in its menu. If the quest is in another zone, it names the zone to "
                .. "head to instead of pointing." },
          { key = "menuBg",
            text = "Puts a plain dark panel behind the game's pop-up menus while they are open, so the text is "
                .. "easy to read. It is meant for the menu on a quest in the quest log (Track, Focus, Share, "
                .. "Abandon), which this game draws with no background. It does not need QuestieDB." },
      } },

    { id = "bags", title = "Bags",
      text = "With the game's controller style on, all your bags already show as one window. This helper gives "
          .. "you an easy way to tidy it.",
      rows = {
          { key = "bags",
            text = "Adds a big Sort button to the bag window. You can also click the left stick while the bag is "
                .. "open to sort. In the settings you can pick the right stick or no stick, and make the bag "
                .. "window larger."
                .. "\n\nTwo more choices are under Bag sorter in the settings, once it is on. Both start off. "
                .. "\"D-pad to Sort\": press Left from the bag's first column to reach the Sort button, then A to "
                .. "sort. \"Bag icons\": \"One row at the top\" puts the pictures of your equipped bags side by "
                .. "side above your items, not in among them."
                .. "\n\nIf you play without the controller style, the game needs a reload to join the bags into "
                .. "one window. The last screen of this guide offers it." },
      } },

    { id = "vendors", title = "Vendors",
      text = "Two chores done for you each time you open a vendor's window. Each has its own switch.",
      rows = {
          { key = "sellJunk",
            text = "Sells every grey item in your bags as soon as a vendor's window opens, and says in chat how "
                .. "many it sold and for how much. Bags you told the game to leave out of junk selling are not "
                .. "touched. Careful: only the last 12 items sold can be bought back." },
          { key = "repair",
            text = "Repairs all your gear when you open a vendor who can repair, paying with your own money, "
                .. "never the guild's. A line in chat says what it cost. If you cannot afford it, it says so and "
                .. "does nothing." },
      } },

    { id = "chat", title = "Chat",
      text = "Chat targets are small on a handheld. This helper gives you big buttons to pick who you talk to.",
      rows = {
          { key = "chat",
            text = "While this is on, a tap on the round PE button opens a window with one big button for each "
                .. "place you can talk (Say, Party, Guild, General, Trade and so on) and for the last six people "
                .. "who whispered you. Tap one, then press A when \"Press A to type\" appears: the game's chat "
                .. "box opens, already set to that channel or person. A red number on the round button counts "
                .. "whispers you have not answered."
                .. "\n\nWith this on, hold the round button for a moment to open the settings, or use the "
                .. "Settings button in the chat window."
                .. "\n\nChat text size is in the settings, under Big chat buttons: Smaller and Bigger change the "
                .. "size of the text in every chat window. It works whether this switch is on or off." },
      } },

    { id = "layout", title = "The round button and moving things",
      text = "The round PE button is always on screen. Tap it to open the settings (or the chat window, when Big "
          .. "chat buttons is on). Hold it for a moment to always open the settings."
          .. "\n\nIn the settings you can choose where the round button sits and how big all Pocket Essentials "
          .. "buttons are: Small, Medium or Large."
          .. "\n\n\"Move things\", in the bottom row of the settings, lets you nudge the quest arrow, the \"Press "
          .. "A to type\" text and the round button to exactly where you want them, with on-screen arrows or "
          .. "the d-pad." },

    { id = "finish", title = "All set",
      text = "You can change all of this at any time. Tap the round PE button to open the settings (hold it if "
          .. "the chat window opens instead), or pick Pocket Essentials in the addon list at the minimap. The "
          .. "\"Setup guide\" button at the bottom of the settings opens this guide again." },
}

local COLOR = {
    font = { 1, 1, 1 },
    small = { 0.84, 0.84, 0.84 },
    title = { 1, 0.82, 0 },
    warn = { 1, 0.60, 0.20 },
}

local UI           -- PE.UI, set when the window is built
local M            -- current metrics
local panel, area
local backButton, skipButton, nextButton, reloadButton
local built, buildFailed = false, false
local drawing, drawQueued = false, false
local texts = {}   -- [kind] = { list = { font strings }, used = n }: reused on every draw
local lines = { list = {}, used = 0 }
local switches = {} -- one switch button per row place on a screen, reused, so the highlight stays on it
local navList = {}  -- tappable buttons in reading order, rebuilt on every draw
local shown = {}    -- the screens of this opening: { { screen =, rows = { ... } }, ... }
local index = 1
local closeWhy      -- why the window is being hidden, for OnHidden
local waiting       -- "login" or "fight": the guide comes (back) when the fight ends
local resumeIndex   -- the screen a fight interrupted
local toldClosed = false -- the "closed, will show again" chat line was printed this session

local function Debug(text)
    if PE.debugOn then PE:Debug("setup", text) end
end

---------------------------------------------------------------------------
-- What was answered before
---------------------------------------------------------------------------

-- False when the saved settings did not load: the addon then runs on a
-- stand-in table that the game never writes, so an answer could not be kept.
local function SavedLoaded()
    return PE.db ~= nil and PE.db == _G.PocketEssentialsDB
end

-- "finished", "skipped" or nil. Any other saved value reads as never seen.
function Setup:Seen()
    local value = PE.db and PE.db.setup
    if value == "finished" or value == "skipped" then return value end
    return nil
end

-- Finish is never turned back into Skip.
local function Remember(value)
    if not SavedLoaded() then return end
    if value == "skipped" and PE.db.setup == "finished" then return end
    PE.db.setup = value
end

---------------------------------------------------------------------------
-- Which screens this build has
---------------------------------------------------------------------------

local function ShownScreens()
    local out = {}
    for _, screen in ipairs(SCREENS) do
        if type(screen.rows) == "table" then
            local rows = {}
            for _, row in ipairs(screen.rows) do
                if PE:GetModule(row.key) then rows[#rows + 1] = row end
            end
            if #rows > 0 then out[#out + 1] = { screen = screen, rows = rows } end
        else
            out[#out + 1] = { screen = screen }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Placing things (y grows downwards from the top of the list)
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
    local count = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        count = count + max(ceil(#line / perLine), 1)
    end
    return max(count, 1) * size * 1.2
end

local function PlaceText(kind, text, x, y, width, color)
    local pool = texts[kind]
    pool.used = pool.used + 1
    local fontString = pool.list[pool.used]
    if not fontString then
        fontString = UI:CreateText(area.child, kind)
        pool.list[pool.used] = fontString
    end
    text = text == nil and "" or tostring(text)
    fontString:ClearAllPoints()
    fontString:SetPoint("TOPLEFT", area.child, "TOPLEFT", x, -y)
    fontString:SetWidth(max(width, 10))
    fontString:SetText(text)
    local c = color or COLOR[kind] or COLOR.font
    fontString:SetTextColor(c[1], c[2], c[3], 1)
    fontString:Show()
    return TextHeight(fontString, kind, text, width)
end

-- Paragraphs ("\n\n" between them), one under the other. Returns the new y.
local function PlaceParagraphs(kind, text, x, y, width, color)
    for paragraph in (text .. "\n\n"):gmatch("(.-)\n\n") do
        if paragraph ~= "" then
            y = y + PlaceText(kind, paragraph, x, y, width, color) + M.gap
        end
    end
    return y
end

local function PlaceLine(y, width)
    lines.used = lines.used + 1
    local line = lines.list[lines.used]
    if not line then
        line = area.child:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.30, 0.30, 0.34, 1)
        lines.list[lines.used] = line
    end
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", area.child, "TOPLEFT", 0, -y)
    line:SetSize(max(width, 1), M.border)
    line:Show()
    return M.border
end

---------------------------------------------------------------------------
-- Switches
---------------------------------------------------------------------------

local QueueDraw -- defined below

-- The same call the settings switch makes.
local function OnSwitch(key)
    if key == nil then return end
    local _, _, state = PE:GetModuleSwitch(key)
    if state == "blocked" then
        Debug("switch tapped: " .. tostring(key) .. " cannot be switched on")
        return
    end
    local on = not PE:IsModuleSavedOn(key)
    Debug("switch tapped: " .. tostring(key) .. " -> " .. (on and "on" or "off"))
    PE:SetModuleEnabled(key, on)
    QueueDraw()
end

local function SwitchButton(place)
    local btn = switches[place]
    if not btn then
        btn = UI:CreateButton(area.child, "")
        btn:SetScript("OnClick", PE:Wrap("core", function(self) OnSwitch(self.peKey) end))
        switches[place] = btn
    end
    return btn
end

---------------------------------------------------------------------------
-- Drawing one screen
---------------------------------------------------------------------------

-- Heading, lead text, then one block per feature: name left, switch right,
-- the explanation under the name. Returns the total height.
local function DrawScreen(entry, width)
    local screen = entry.screen
    local x = M.gap
    local y = M.gap * 0.5
    y = y + PlaceText("title", screen.title, x, y, width - x * 2) + M.gap
    y = PlaceParagraphs("font", screen.text, x, y, width - x * 2)

    local toggleWidth = M.button * 2.8
    local textWidth = width - toggleWidth - x - M.pad
    for place, row in ipairs(entry.rows or {}) do
        local mod = PE:GetModule(row.key)
        if mod then
            y = y + PlaceLine(y, width) + M.gap
            local label, style, state, detail = PE:GetModuleSwitch(row.key)
            local ty = y + M.gap * 0.3
            ty = ty + PlaceText("font", row.title or Escape(mod.label), x, ty, textWidth, COLOR.title) + M.gap * 0.3
            ty = PlaceParagraphs("small", row.text, x, ty, textWidth)
            if state == "blocked" then
                ty = ty + PlaceText("small", detail or "This cannot be switched on right now.", x, ty, textWidth, COLOR.warn) + M.gap * 0.3
            elseif state == "failed" then
                ty = ty + PlaceText("small", "Switched on, but it hit a problem. See Errors in the settings.", x, ty, textWidth, COLOR.warn) + M.gap * 0.3
            end
            local rowHeight = max(M.row, ty - y)

            local btn = SwitchButton(place)
            btn.peKey = row.key
            btn:SetLabel(label)
            btn:SetStyle(style)
            btn:ClearAllPoints()
            btn:SetSize(toggleWidth, M.button)
            btn:SetPoint("TOPLEFT", area.child, "TOPLEFT", width - toggleWidth, -(y + (M.row - M.button) * 0.5))
            -- When the controller lands on the switch, bring the whole block into view.
            btn.peScrollTop, btn.peScrollBottom = y, y + rowHeight
            btn:Show()
            navList[#navList + 1] = btn
            y = y + rowHeight + M.gap * 0.5
        end
    end
    return y + M.pad
end

-- The last screen: what is on, what is still off, where to change it later,
-- and the reload button if a feature asked for a reload.
local function DrawFinish(entry, width)
    local screen = entry.screen
    local x = M.gap
    local inner = width - x * 2
    local y = M.gap * 0.5
    y = y + PlaceText("title", screen.title, x, y, inner) + M.gap

    local on, off = {}, {}
    for _, mod in ipairs(PE.moduleList) do
        local list = PE:IsModuleEnabled(mod.key) and on or off
        list[#list + 1] = Escape(mod.label)
    end
    if #on > 0 then
        y = y + PlaceText("font", "Switched on: " .. table.concat(on, ", ") .. ".", x, y, inner) + M.gap
    else
        y = y + PlaceText("font", TEXT_NOTHING_ON, x, y, inner) + M.gap
    end
    if #off > 0 then
        y = y + PlaceText("font", "Still off: " .. table.concat(off, ", ") .. ".", x, y, inner) + M.gap
    end
    y = PlaceParagraphs("font", screen.text, x, y, inner)

    local reasons = PE.reloadReasons
    if type(reasons) == "table" and #reasons > 0 then
        local buttonWidth = M.button * 4.5
        local list = {}
        for i = 1, min(#reasons, 2) do
            list[i] = Escape(reasons[i].label) .. ": " .. Escape(reasons[i].reason)
        end
        y = y + PlaceLine(y, width) + M.gap
        local textHeight = PlaceText("small", table.concat(list, "\n"), x, y, inner - buttonWidth - M.gap, COLOR.warn)
        local rowHeight = max(M.button, textHeight)
        reloadButton:ClearAllPoints()
        reloadButton:SetSize(buttonWidth, M.button)
        reloadButton:SetPoint("TOPLEFT", area.child, "TOPLEFT", width - buttonWidth, -y)
        reloadButton.peScrollTop, reloadButton.peScrollBottom = y, y + rowHeight
        reloadButton:Show()
        navList[#navList + 1] = reloadButton
        y = y + rowHeight + M.gap
    end
    return y + M.pad
end

local function PanelSize()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if type(screenWidth) ~= "number" or screenWidth < 100 then screenWidth = 1024 end
    if type(screenHeight) ~= "number" or screenHeight < 100 then screenHeight = 768 end
    return min(screenWidth * 0.96, UI:Px(1180)), screenHeight * 0.92
end

-- Back and Skip at the bottom left, Next at the bottom right: always in the
-- same place, so pressing A again and again walks through the guide.
local function LayoutBottomRow()
    local width = M.button * 3.5
    local content = panel.content
    backButton:ClearAllPoints()
    backButton:SetSize(width, M.button)
    backButton:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    skipButton:ClearAllPoints()
    skipButton:SetSize(width, M.button)
    skipButton:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", width + M.gap, 0)
    nextButton:ClearAllPoints()
    nextButton:SetSize(width, M.button)
    nextButton:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
end

local function DoDraw()
    M = UI:Metrics()
    for i = #navList, 1, -1 do navList[i] = nil end
    for _, pool in pairs(texts) do pool.used = 0 end
    lines.used = 0

    local count = #shown
    if index > count then index = count end
    if index < 1 then index = 1 end
    local entry = shown[index]
    if not entry then return end
    local isFirst, isLast = index == 1, index == count
    panel:SetTitle(TITLE .. " (" .. index .. " of " .. count .. ")")

    LayoutBottomRow()
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, 0)
    area:Layout(panel.contentWidth, max(panel.contentHeight - M.button - M.gap, M.button * 2 + M.gap))

    reloadButton:Hide()
    local rowCount = (entry.screen.id ~= "finish" and entry.rows) and #entry.rows or 0
    for i = rowCount + 1, #switches do
        switches[i].peKey = nil
        switches[i]:Hide()
    end
    local ok, total = PE:Safe("core", entry.screen.id == "finish" and DrawFinish or DrawScreen, entry, area.viewWidth)
    if not ok or type(total) ~= "number" then total = area.viewHeight end
    for _, pool in pairs(texts) do
        for i = pool.used + 1, #pool.list do pool.list[i]:Hide() end
    end
    for i = lines.used + 1, #lines.list do lines.list[i]:Hide() end
    area:SetContentHeight(total)

    -- Reading order for the d-pad: what is in the list, the paging buttons
    -- when there is something to page, the bottom row, Close.
    if area:GetRange() > 0 then
        navList[#navList + 1] = area.upButton
        navList[#navList + 1] = area.downButton
    end
    backButton:SetShown(not isFirst)
    skipButton:SetShown(not isLast)
    nextButton:SetLabel(isLast and "Finish" or isFirst and "Start" or "Next")
    nextButton:SetStyle(isLast and "on" or "normal")
    if not isFirst then navList[#navList + 1] = backButton end
    if not isLast then navList[#navList + 1] = skipButton end
    navList[#navList + 1] = nextButton
    navList[#navList + 1] = panel.closeButton

    -- The highlighted button went away with the screen (Back on the first
    -- screen): the highlight goes to Next.
    local focus = panel.peNavFocus
    if focus then
        local still = false
        for i = 1, #navList do
            if navList[i] == focus then still = true end
        end
        if not still then panel:NavSetFocus(nextButton) end
    end
    panel:NavRefresh()
end

local function Draw()
    if drawing or not built or not panel:IsShown() then return end
    drawing = true
    PE:Safe("core", DoDraw)
    drawing = false
end

local function QueuedDraw()
    drawQueued = false
    Draw()
end

-- Redraw once on the next frame, however many times this is asked for.
-- Returns at its first line while the guide is closed.
QueueDraw = function()
    if drawQueued or not built or not panel:IsShown() then return end
    if C_Timer and C_Timer.After then
        drawQueued = true
        C_Timer.After(0, PE:Wrap("core", QueuedDraw))
    else
        Draw()
    end
end

-- Back (-1) and Next / Start / Finish (+1).
local function Go(step)
    if step > 0 and index >= #shown then
        Setup:Close("finished")
        return
    end
    index = max(min(index + step, #shown), 1)
    area.offset = 0
    Debug("screen " .. index .. " of " .. #shown .. ": " .. tostring(shown[index] and shown[index].screen.id))
    Draw()
end

---------------------------------------------------------------------------
-- Fights
---------------------------------------------------------------------------

local function OtherWindowShown()
    if type(UISpecialFrames) ~= "table" then return false end
    for _, name in ipairs(UISpecialFrames) do
        local other = type(name) == "string" and name:find("^PocketEssentials") and _G[name]
        if other and other ~= panel and other.IsShown and other:IsShown() then return true end
    end
    return false
end

-- Runs once, at the end of the fight that hid the guide or kept it from
-- opening at login. The game's lockdown starts after the "fight started"
-- event, so this wait cannot be a PE:RunOutOfCombat call made from there:
-- it would run at once.
local function OnFightOver()
    PE:UnregisterCoreEvent("PLAYER_REGEN_ENABLED", "setup")
    local why = waiting
    waiting = nil
    if not why then return end
    if OtherWindowShown() then
        Debug("not reopened: another window is open")
        return
    end
    if why == "login" then
        if Setup:Seen() then return end
        Setup:Open("first login")
    else
        Setup:Open("after the fight")
    end
end

local function WaitForFightEnd(why)
    waiting = why
    PE:RegisterCoreEvent("PLAYER_REGEN_ENABLED", "setup", OnFightOver)
end

local function OnFight()
    Setup:Close("fight")
end

-- Every way the window goes away ends here: our buttons, B, Escape, another
-- of our windows, and the game closing its windows by itself (loading screen,
-- death, loss of control). Only Finish and Skip are remembered.
local function OnHidden()
    PE:UnregisterCoreEvent("PLAYER_REGEN_DISABLED", "setup")
    local why = closeWhy
    closeWhy = nil
    if why == "finished" then
        Remember("finished")
        Debug("closed: finished")
    elseif why == "skipped" then
        Remember("skipped")
        Debug("closed: skipped")
    elseif why == "fight" then
        resumeIndex = index
        WaitForFightEnd("fight")
        Debug("closed: fight started, will come back")
    else
        Debug("closed: not remembered (" .. (why == "Close" and "Close" or "B, Escape or another window") .. ")")
        if Setup:Seen() == nil and not toldClosed then
            toldClosed = true
            PE:Print(TEXT_CLOSED)
        end
    end
end

---------------------------------------------------------------------------
-- Building the window (first opening only)
---------------------------------------------------------------------------

local function Build()
    UI = PE.UI
    M = UI:Metrics()
    local width, height = PanelSize()
    panel = UI:CreatePanel(PANEL_NAME, TITLE, width, height)
    panel.closeButton:SetScript("OnClick", PE:Wrap("core", function() Setup:Close("Close") end))
    area = UI:CreateScrollArea(panel.content)
    texts.title = { list = {}, used = 0 }
    texts.font = { list = {}, used = 0 }
    texts.small = { list = {}, used = 0 }

    backButton = UI:CreateButton(panel.content, "Back")
    backButton:SetScript("OnClick", PE:Wrap("core", function() Go(-1) end))
    skipButton = UI:CreateButton(panel.content, "Skip")
    skipButton:SetScript("OnClick", PE:Wrap("core", function() Setup:Close("skipped") end))
    nextButton = UI:CreateButton(panel.content, "Next")
    nextButton:SetScript("OnClick", PE:Wrap("core", function() Go(1) end))

    reloadButton = UI:CreateButton(area.child, "Reload now")
    reloadButton:SetStyle("warn")
    reloadButton:Hide()
    -- Called straight from the tap, in case reloading needs a real button
    -- press. The reload ends the session, so Finish is stored first.
    reloadButton:SetScript("OnClick", function()
        pcall(Remember, "finished")
        PE:ReloadNow()
    end)

    UI:AttachNav(panel, function() return navList end)
    panel.navOnFocus = function(btn)
        if btn.peScrollTop then area:ScrollIntoView(btn) end
    end
    panel:HookScript("OnHide", PE:Wrap("core", OnHidden))

    UI:OnMetricsChanged(PE:Wrap("core", function()
        if not built then return end
        M = UI:Metrics()
        panel:SetPanelSize(PanelSize())
        QueueDraw()
    end))
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- how: "first login", "settings", "slash" or "after the fight".
function Setup:Open(how)
    how = type(how) == "string" and how or "settings"
    local byHand = how ~= "first login" and how ~= "after the fight"
    if PE:InCombat() then
        if byHand then
            Debug("not opened: in a fight")
            PE:Print(TEXT_FIGHT)
        else
            WaitForFightEnd(how == "first login" and "login" or "fight")
            Debug("waiting for the fight to end")
        end
        return false
    end
    if not built and not buildFailed then
        if PE.UI and PE:Safe("core", Build) then
            built = true
        else
            buildFailed = true
            if panel then pcall(panel.Hide, panel) end
        end
    end
    if not built then
        PE:Print(TEXT_BROKEN)
        return false
    end
    -- Opened: any wait for the end of a fight is over.
    if waiting then
        waiting = nil
        PE:UnregisterCoreEvent("PLAYER_REGEN_ENABLED", "setup")
    end
    -- Never on top of another Pocket Essentials window.
    PE:CloseSettings()
    if type(UISpecialFrames) == "table" then
        for _, name in ipairs(UISpecialFrames) do
            local other = type(name) == "string" and name:find("^PocketEssentials") and _G[name]
            if other and other ~= panel and other.IsShown and other:IsShown() then pcall(other.Hide, other) end
        end
    end
    shown = ShownScreens()
    if how == "after the fight" then
        index = max(min(resumeIndex or 1, #shown), 1)
    else
        index = 1
    end
    resumeIndex = nil
    closeWhy = nil
    area.offset = 0
    PE:RegisterCoreEvent("PLAYER_REGEN_DISABLED", "setup", OnFight)
    if not panel:IsShown() then panel:Show() end
    panel:Raise()
    if PE.debugOn then
        Debug("opened (" .. how .. ")")
        local ids = {}
        for i, entry in ipairs(shown) do ids[i] = entry.screen.id end
        Debug("screens: " .. table.concat(ids, ", "))
        Debug("screen " .. index .. " of " .. #shown .. ": " .. tostring(ids[index]))
    end
    Draw()
    return true
end

-- why: "finished", "skipped", "Close" or "fight"; anything else is a plain
-- hide. The bookkeeping is in OnHidden, so B and Escape take the same path.
function Setup:Close(why)
    if built and panel:IsShown() then
        closeWhy = type(why) == "string" and why or nil
        panel:Hide()
    end
end

function Setup:IsOpen()
    return built and panel:IsShown() or false
end

---------------------------------------------------------------------------
-- At file load: two hooks, nothing else
---------------------------------------------------------------------------

-- Anything that changes a feature's state asks the settings window to redraw
-- (PE:RefreshSettings); the guide redraws with it when it is open.
local innerRefresh = PE.RefreshSettings
function PE:RefreshSettings()
    if innerRefresh then innerRefresh(self) end
    QueueDraw()
end

-- True when the guide should open by itself. Asked twice: when the character
-- enters the world (no timer is started when the answer is already no), and
-- again when the timer fires. The offline tests rely on the second reading
-- (tests/features/run.lua, T.new): do not drop it.
local function WantedAtLogin()
    if not SavedLoaded() then
        Debug("first login check: saved settings not loaded, guide not shown")
        return false
    end
    local seen = Setup:Seen()
    if seen then
        Debug("first login check: not needed (" .. seen .. ")")
        return false
    end
    return true
end

local function FirstLoginCheck()
    if Setup:IsOpen() or waiting then return end
    if not WantedAtLogin() then return end
    if #PE.moduleList == 0 or not PE.UI then return end
    Setup:Open("first login") -- in a fight this waits for the fight to end
end

-- After the first loading screen, not at login: the game closes every window
-- of this kind when the character enters the world, ours included.
if PE.RegisterCoreEvent then
    PE:RegisterCoreEvent("PLAYER_ENTERING_WORLD", "setup", function()
        PE:UnregisterCoreEvent("PLAYER_ENTERING_WORLD", "setup") -- the first one only
        if not WantedAtLogin() then return end
        if C_Timer and C_Timer.After then
            C_Timer.After(FIRST_LOGIN_DELAY, PE:Wrap("core", FirstLoginCheck))
        end
    end)
end
