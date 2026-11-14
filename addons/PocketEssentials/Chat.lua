-- Pocket Essentials: big chat buttons (module "chat").
-- While this is on, a tap on the round button opens a window of large
-- buttons: one for every place the character can talk right now, and one for
-- each person who whispered recently. A tap on a button closes the window and
-- opens the game's own chat box already pointed at that target. The owner
-- then brings up the keyboard (three-finger tap) and types.
--
-- Nothing here hooks, filters or replaces the chat frames. The only game
-- events used are the four whisper events, and only while the feature is on.
local ADDON_NAME, PE = ...

local type, tostring, pcall, select, pairs = type, tostring, pcall, select, pairs
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local tinsert, tremove = table.insert, table.remove
local issecretvalue = issecretvalue -- nil on clients without secret values

local PANEL_NAME = "PocketEssentialsChatPanel"
local PANEL_TITLE = "Chat"
local HINT = "Three-finger tap for the keyboard"
local MAX_SAVED = 12 -- whisperers remembered between sessions
local MAX_SHOWN = 6  -- name buttons in the window

local mod -- set at the bottom of the file

---------------------------------------------------------------------------
-- Secret values and the chat lockdown.
-- In dungeons, raids, boss fights and PvP matches this client hides chat
-- details from addons: the whisper events still fire, but the sender arrives
-- as a "secret" value that addon code may not compare, store or join. So
-- while C_ChatInfo.InChatMessagingLockdown() is true nothing is tracked, and
-- a value is never looked at before IsSecret() said it is safe.
---------------------------------------------------------------------------

local function IsSecret(value)
    if not issecretvalue then return false end
    local ok, secret = pcall(issecretvalue, value)
    if not ok then return true end
    return secret and true or false
end

local function InLockdown()
    local info = C_ChatInfo
    local check = info and info.InChatMessagingLockdown
    if type(check) ~= "function" then return false end
    local ok, locked = pcall(check)
    return (ok and locked) and true or false
end

local function Field(tbl, key)
    return tbl[key]
end

local function Escape(text)
    return (tostring(text):gsub("|", "||"))
end

---------------------------------------------------------------------------
-- The saved whisper list: mod.opts.whispers, newest first.
--   { name = "Thrall", unanswered = true, time = 1731500000 }
--   { name = "Jaina", bn = "Jaina#1234", unanswered = false, time = ... }
-- `bn` (a BattleTag) marks a Battle.net friend; it is the only Battle.net
-- detail that still means something in a later session.
---------------------------------------------------------------------------

local function List()
    local opts = mod and mod.opts
    if type(opts) ~= "table" then return nil end
    local list = opts.whispers
    if type(list) ~= "table" then
        list = {}
        opts.whispers = list
    end
    return list
end

-- Drop anything that is not a well-formed entry (hand-edited or damaged
-- saved data) and keep at most MAX_SAVED.
local function CleanList()
    local list = List()
    if not list then return end
    local good = {}
    for i = 1, #list do
        local e = list[i]
        if #good < MAX_SAVED and type(e) == "table" and type(e.name) == "string" and e.name ~= ""
            and (e.bn == nil or (type(e.bn) == "string" and e.bn ~= "")) then
            e.unanswered = e.unanswered and true or false
            if type(e.time) ~= "number" then e.time = 0 end
            good[#good + 1] = e
        end
    end
    for key in pairs(list) do list[key] = nil end
    for i = 1, #good do list[i] = good[i] end
end

local function CountUnanswered(list)
    local count = 0
    if list then
        for i = 1, #list do
            local e = list[i]
            if type(e) == "table" and e.unanswered then count = count + 1 end
        end
    end
    return count
end

local function FindEntry(list, name, bn)
    local key = name:lower()
    for i = 1, #list do
        local e = list[i]
        if type(e) == "table" then
            if bn then
                if e.bn == bn then return i end
            elseif e.bn == nil and type(e.name) == "string" and e.name:lower() == key then
                return i
            end
        end
    end
    return nil
end

-- The (at most MAX_SHOWN) entries for the window, newest first. People still
-- waiting for an answer are never pushed out of sight by answered ones.
local function VisibleWhispers(list)
    local out = {}
    if not list then return out end
    local answeredRoom = max(MAX_SHOWN - CountUnanswered(list), 0)
    for i = 1, #list do
        if #out >= MAX_SHOWN then break end
        local e = list[i]
        if type(e) == "table" and type(e.name) == "string" then
            if e.unanswered then
                out[#out + 1] = e
            elseif answeredRoom > 0 then
                out[#out + 1] = e
                answeredRoom = answeredRoom - 1
            end
        end
    end
    return out
end

local Refresh -- defined with the window, below

local function UpdateBadge()
    local hub = PE.Hub
    if not (hub and hub.SetBadge) then return end
    local count = CountUnanswered(List())
    hub:SetBadge(count > 0 and tostring(count) or nil)
end

local function WhispersChanged()
    UpdateBadge()
    Refresh()
end

-- incoming: they whispered us (marked as waiting for an answer).
-- not incoming: we whispered them (that answers them).
-- Either way that person moves to the top of the list.
local function Touch(name, bn, incoming)
    local list = List()
    if not list then return end
    local index = FindEntry(list, name, bn)
    local entry = index and tremove(list, index)
    if type(entry) ~= "table" then entry = {} end
    entry.name = name
    entry.bn = bn
    entry.unanswered = incoming and true or false
    entry.time = time()
    tinsert(list, 1, entry)
    for i = #list, MAX_SAVED + 1, -1 do list[i] = nil end
    WhispersChanged()
end

---------------------------------------------------------------------------
-- Whisper events
---------------------------------------------------------------------------

-- "Name-Realm" as the events deliver it -> the shortest form that can still
-- be whispered ("Name" on our own realm), so the incoming and the outgoing
-- event for one person always give the same text.
local function CleanName(name)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    if type(Ambiguate) == "function" then
        local ok, short = pcall(Ambiguate, name, "none")
        if ok and not IsSecret(short) and type(short) == "string" and short ~= "" then name = short end
    end
    return name
end

-- The Battle.net id in the events only lasts for this session; the BattleTag
-- behind it is what gets saved.
local function BattleTagFor(id)
    if IsSecret(id) or type(id) ~= "number" or id <= 0 then return nil end
    local api = C_BattleNet
    local lookup = api and api.GetAccountInfoByID
    if type(lookup) ~= "function" then return nil end
    local ok, info = pcall(lookup, id)
    if not ok or IsSecret(info) or type(info) ~= "table" then return nil end
    local ok2, tag = pcall(Field, info, "battleTag")
    if not ok2 or IsSecret(tag) or type(tag) ~= "string" or tag == "" then return nil end
    return tag
end

-- Payload (Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua):
-- 1 text, 2 playerName, ... 12 guid, 13 bnSenderID.
local function OnWhisper(_, event, ...)
    if InLockdown() then return end
    local incoming = (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER")
    if event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
        local tag = BattleTagFor((select(13, ...)))
        if tag then Touch(tag:match("^([^#]+)") or tag, tag, incoming) end
    else
        local name = CleanName((select(2, ...)))
        if name then Touch(name, nil, incoming) end
    end
end

---------------------------------------------------------------------------
-- Opening the game's chat box pointed at a target.
--
-- Done the way Blizzard's own chat menu and Reply key do it
-- (ChatFrameMenuButtonMixin.SetChatTypeAttribute, ChatFrameUtil.ReplyTell):
-- pick the edit box with ChooseBoxForSend, open it with OpenChat(nil) (what
-- the Enter key binding runs), then set its chat type / target, which are
-- frame attributes, through the edit box's own methods. This file writes no
-- field on a Blizzard frame and pushes no text into the box. (OpenChat
-- itself notes which box is active in two globals, as it does for every
-- addon that opens chat; the path that sends a typed line or runs a typed
-- /cast never reads those.)
---------------------------------------------------------------------------

local function CanAddress(box, chatType)
    if type(box) ~= "table" then return false end
    if type(box.SetChatType) ~= "function" or type(box.UpdateHeader) ~= "function" then return false end
    if chatType == "CHANNEL" then return type(box.SetChannelTarget) == "function" end
    if chatType == "WHISPER" then return type(box.SetTellTarget) == "function" end
    return true
end

-- Returns true if the chat box was asked to open.
local function OpenChatTo(chatType, target, slash)
    local util = ChatFrameUtil
    if type(util) ~= "table" then return false end
    local choose, open, active = util.ChooseBoxForSend, util.OpenChat, util.GetActiveWindow
    if type(open) ~= "function" then return false end

    if type(choose) == "function" and type(active) == "function" then
        local box = choose()
        if CanAddress(box, chatType) then
            if box ~= active() then
                -- Naming the chat frame keeps this out of any other window's
                -- chat line (the guild window has one).
                local opened = open(nil, box.chatFrame)
                if opened ~= box and CanAddress(opened, chatType) then box = opened end
            end
            if chatType == "CHANNEL" then
                box:SetChannelTarget(target)
            elseif chatType == "WHISPER" then
                box:SetTellTarget(target)
            end
            box:SetChatType(chatType)
            box:UpdateHeader()
            return true
        end
    end

    -- The edit box does not look the way this file expects: fall back to
    -- letting the game read a typed command.
    if chatType == "WHISPER" then
        if type(util.SendTell) ~= "function" then return false end
        util.SendTell(target)
        return true
    end
    if type(slash) ~= "string" then return false end
    open(slash .. " ")
    return true
end

-- The name the game wants for a Battle.net whisper to this BattleTag, or nil
-- if that friend cannot be found right now.
local function FriendToken(battleTag)
    local api = C_BattleNet
    local getFriend = api and api.GetFriendAccountInfo
    if type(getFriend) ~= "function" or type(BNGetNumFriends) ~= "function" then return nil end
    local total = BNGetNumFriends()
    if IsSecret(total) or type(total) ~= "number" then return nil end
    for i = 1, min(total, 500) do
        local info = getFriend(i)
        if not IsSecret(info) and type(info) == "table" then
            local tag, token = info.battleTag, info.accountName
            if not IsSecret(tag) and not IsSecret(token) and tag == battleTag
                and type(token) == "string" and token ~= "" then
                return token
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- What the character can talk in right now
---------------------------------------------------------------------------

local function AddTarget(list, label, chatType, target, slash)
    list[#list + 1] = { label = label, chatType = chatType, target = target, slash = slash }
end

local function Pack(...)
    return select("#", ...), { ... }
end

local function ChannelList()
    return Pack(GetChannelList())
end

local function ChannelLabel(name)
    -- Community channels arrive as "Community:1:2"; the game has the real name.
    local resolve = ChatFrameUtil and ChatFrameUtil.ResolveChannelName
    if type(resolve) == "function" then
        local ok, nice = pcall(resolve, name)
        if ok and type(nice) == "string" and nice ~= "" then name = nice end
    end
    return name
end

local function GatherTargets()
    local list = {}
    AddTarget(list, "Say", "SAY", nil, "/s")
    AddTarget(list, "Yell", "YELL", nil, "/y")
    if type(IsInGroup) == "function" and IsInGroup() then AddTarget(list, "Party", "PARTY", nil, "/p") end
    if type(IsInRaid) == "function" and IsInRaid() then AddTarget(list, "Raid", "RAID", nil, "/raid") end
    if type(IsInGuild) == "function" and IsInGuild() then AddTarget(list, "Guild", "GUILD", nil, "/g") end
    if type(GetChannelList) == "function" then
        -- id, name, disabled, id, name, disabled, ...
        local ok, count, channels = pcall(ChannelList)
        if ok and type(count) == "number" and type(channels) == "table" then
            for i = 1, count, 3 do
                local id, name, disabled = channels[i], channels[i + 1], channels[i + 2]
                if type(id) == "number" and id > 0 and type(name) == "string" and name ~= "" and not disabled then
                    AddTarget(list, id .. ". " .. Escape(ChannelLabel(name)), "CHANNEL", id, "/" .. id)
                end
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local UI, M
local panel, area
local settingsButton, clearButton
local hintText, sectionText, noteText, emptyText
local targetButtons = {} -- reused on every redraw
local navList = {}       -- tappable buttons in reading order
local built, buildFailed = false, false
local note               -- one short line under "Whispers", e.g. a friend who cannot be reached
local onTargetClick, hubClick

local function PanelSize()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if type(screenWidth) ~= "number" or screenWidth < 100 then screenWidth = 1024 end
    if type(screenHeight) ~= "number" or screenHeight < 100 then screenHeight = 768 end
    return min(screenWidth * 0.96, UI:Px(1180)), screenHeight * 0.92
end

local function LineHeight(kind)
    if kind == "small" then return M.smallFontSize * 1.3 end
    if kind == "title" then return M.fontSize * 1.12 * 1.3 end
    return M.fontSize * 1.3
end

local COLOR_HINT = { 0.84, 0.84, 0.84 }
local COLOR_SECTION = { 1, 0.82, 0 }
local COLOR_PLAIN = { 1, 1, 1 }
local COLOR_NOTE = { 1, 0.60, 0.20 }

local function PlaceText(fontString, text, y, width, color)
    fontString:ClearAllPoints()
    fontString:SetPoint("TOPLEFT", area.child, "TOPLEFT", 0, -y)
    fontString:SetWidth(max(width, 10))
    fontString:SetText(text)
    fontString:SetTextColor(color[1], color[2], color[3], 1)
    fontString:Show()
end

local function PlaceButton(btn, label, x, y, width, height)
    btn:SetSelected(false)
    btn:SetStyle("normal")
    btn:SetBadgeText(nil)
    btn:ClearAllPoints()
    btn:SetLabel(label)
    btn:SetSize(width, height)
    btn:SetPoint("TOPLEFT", area.child, "TOPLEFT", x, -y)
    btn.peScrollTop, btn.peScrollBottom = y, y + height
    btn:Show()
    navList[#navList + 1] = btn
end

local function TargetButton(index)
    local btn = targetButtons[index]
    if not btn then
        btn = UI:CreateButton(area.child, "")
        btn:SetScript("OnClick", onTargetClick)
        targetButtons[index] = btn
    end
    return btn
end

local function DoRefresh()
    M = UI:Metrics()
    for i = #navList, 1, -1 do navList[i] = nil end

    local targets = GatherTargets()
    local list = List()
    local shown = VisibleWhispers(list)
    local marked = CountUnanswered(list)

    local gap = M.gap
    local width, height = panel.contentWidth, panel.contentHeight
    local hintHeight, sectionHeight = LineHeight("small"), LineHeight("title")
    local noteHeight, emptyHeight = LineHeight("small"), LineHeight("font")

    local function Columns(forWidth)
        return max(1, min(4, floor((forWidth + gap) / (M.button * 4.4 + gap))))
    end
    local function TotalHeight(cols, buttonHeight)
        local total = hintHeight + gap + ceil(#targets / cols) * (buttonHeight + gap) + sectionHeight + gap * 0.5
        if note then total = total + noteHeight + gap * 0.5 end
        if #shown == 0 then
            total = total + emptyHeight + gap
        else
            total = total + ceil(#shown / cols) * (buttonHeight + gap)
        end
        if marked > 0 then total = total + buttonHeight + gap end
        return total - gap
    end

    -- Tall buttons if everything fits, plain ones if that is what it takes,
    -- and only then a list that scrolls.
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, 0)
    area:Layout(width, height)
    local narrowWidth = area.viewWidth -- what is left beside the paging buttons
    local cols, buttonHeight, scroll = Columns(width), M.button * 1.25, false
    if TotalHeight(cols, buttonHeight) > height then
        buttonHeight = M.button
        if TotalHeight(cols, buttonHeight) > height then
            scroll = true
            cols = Columns(narrowWidth)
        end
    end
    if not scroll then
        -- No scrolling needed: widen the area so the list gets the whole
        -- window and the (hidden) paging buttons sit outside it.
        area:Layout(width + (width - narrowWidth), height)
    end
    area.upButton:SetShown(scroll)
    area.downButton:SetShown(scroll)
    local viewWidth = scroll and narrowWidth or min(area.viewWidth, width)
    local colWidth = max((viewWidth - (cols - 1) * gap) / cols, 1)

    local y = 0
    PlaceText(hintText, HINT, y, viewWidth, COLOR_HINT)
    y = y + hintHeight + gap

    for i = 1, #targets do
        local btn = TargetButton(i)
        PlaceButton(btn, targets[i].label, ((i - 1) % cols) * (colWidth + gap),
            y + floor((i - 1) / cols) * (buttonHeight + gap), colWidth, buttonHeight)
        btn.peChatTarget, btn.peChatEntry = targets[i], nil
    end
    y = y + ceil(#targets / cols) * (buttonHeight + gap)
    local used = #targets

    PlaceText(sectionText, "Whispers", y, viewWidth, COLOR_SECTION)
    y = y + sectionHeight + gap * 0.5
    if note then
        PlaceText(noteText, note, y, viewWidth, COLOR_NOTE)
        y = y + noteHeight + gap * 0.5
    else
        noteText:Hide()
    end

    if #shown == 0 then
        PlaceText(emptyText, "No whispers yet.", y, viewWidth, COLOR_PLAIN)
        y = y + emptyHeight + gap
    else
        emptyText:Hide()
        for i = 1, #shown do
            local entry = shown[i]
            local btn = TargetButton(used + i)
            PlaceButton(btn, Escape(entry.name), ((i - 1) % cols) * (colWidth + gap),
                y + floor((i - 1) / cols) * (buttonHeight + gap), colWidth, buttonHeight)
            btn.peChatTarget, btn.peChatEntry = nil, entry
            if entry.unanswered then
                btn:SetStyle("warn")
                btn:SetBadgeText("NEW")
            end
        end
        y = y + ceil(#shown / cols) * (buttonHeight + gap)
        used = used + #shown
    end

    if marked > 0 then
        PlaceButton(clearButton, "Clear marks", 0, y, colWidth, buttonHeight)
        y = y + buttonHeight + gap
    else
        clearButton:Hide()
    end

    for i = used + 1, #targetButtons do targetButtons[i]:Hide() end
    area:SetContentHeight(max(y - gap, 1))

    if scroll then
        navList[#navList + 1] = area.upButton
        navList[#navList + 1] = area.downButton
    end

    -- In the title bar, left of Close.
    settingsButton:SetSize(M.button * 2.6, M.button)
    settingsButton:ClearAllPoints()
    settingsButton:SetPoint("RIGHT", panel.closeButton, "LEFT", -gap, 0)
    navList[#navList + 1] = settingsButton
    navList[#navList + 1] = panel.closeButton
    panel:NavRefresh()
end

-- Does nothing unless the window is open.
Refresh = function()
    if built and panel:IsShown() then mod:Safe(DoRefresh) end
end

local function WhisperTo(entry)
    if entry.bn then
        local send = ChatFrameUtil and ChatFrameUtil.SendBNetTell
        local ok, token = pcall(FriendToken, entry.bn)
        if not ok or not token or type(send) ~= "function" then
            note = "Can't reach " .. Escape(entry.name) .. " right now."
            Refresh()
            return
        end
        panel:Hide()
        send(token) -- Blizzard's own "whisper this Battle.net friend"
        return
    end
    panel:Hide()
    if not OpenChatTo("WHISPER", entry.name) then
        mod:Print("The chat box could not be opened.")
    end
end

local function TargetClicked(btn)
    local entry, target = btn.peChatEntry, btn.peChatTarget
    if entry then
        WhisperTo(entry)
    elseif target then
        panel:Hide()
        if not OpenChatTo(target.chatType, target.target, target.slash) then
            mod:Print("The chat box could not be opened.")
        end
    end
end

local function ClearMarks()
    local list = List()
    if list then
        for i = 1, #list do
            if type(list[i]) == "table" then list[i].unanswered = false end
        end
    end
    WhispersChanged()
end

local function Build()
    UI = PE.UI
    M = UI:Metrics()
    onTargetClick = mod:Wrap(TargetClicked)

    local width, height = PanelSize()
    panel = UI:CreatePanel(PANEL_NAME, PANEL_TITLE, width, height)
    area = UI:CreateScrollArea(panel.content)

    hintText = UI:CreateText(area.child, "small")
    sectionText = UI:CreateText(area.child, "title")
    noteText = UI:CreateText(area.child, "small")
    emptyText = UI:CreateText(area.child, "font")
    hintText:SetWordWrap(false)
    sectionText:SetWordWrap(false)
    noteText:SetWordWrap(false)
    emptyText:SetWordWrap(false)

    clearButton = UI:CreateButton(area.child, "Clear marks")
    clearButton:SetScript("OnClick", mod:Wrap(ClearMarks))

    settingsButton = UI:CreateButton(panel, "Settings")
    settingsButton:SetScript("OnClick", mod:Wrap(function()
        panel:Hide()
        PE:OpenSettings()
    end))

    UI:AttachNav(panel, function() return navList end)
    panel.navOnFocus = function(btn)
        if btn.peScrollTop then area:ScrollIntoView(btn) end
    end

    UI:OnMetricsChanged(mod:Wrap(function()
        if not built then return end
        local newWidth, newHeight = PanelSize()
        panel:SetPanelSize(newWidth, newHeight)
        Refresh()
    end))
end

local function OpenPanel()
    if not built and not buildFailed then
        if PE.UI and mod:Safe(Build) then
            built = true
        else
            buildFailed = true
            if panel then pcall(panel.Hide, panel) end
        end
    end
    if not built then
        -- Never leave the round button dead.
        PE:OpenSettings()
        return
    end
    PE:CloseSettings()
    note = nil
    area.offset = 0
    if not panel:IsShown() then panel:Show() end
    panel:Raise()
    Refresh()
end

-- What a tap on the round button does while this feature is on.
local function TogglePanel()
    if built and panel:IsShown() then
        panel:Hide()
    else
        OpenPanel()
    end
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

mod = PE:RegisterModule({
    key = "chat",
    label = "Big chat buttons",
    desc = "Tap the round button to pick who to talk to.",
    order = 60,
    defaults = { whispers = {} },

    OnEnable = function(self)
        CleanList()
        self:RegisterEvent("CHAT_MSG_WHISPER", OnWhisper)
        self:RegisterEvent("CHAT_MSG_WHISPER_INFORM", OnWhisper)
        self:RegisterEvent("CHAT_MSG_BN_WHISPER", OnWhisper)
        self:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM", OnWhisper)
        hubClick = hubClick or self:Wrap(TogglePanel)
        local hub = PE.Hub
        if hub and hub.SetClickHandler then hub:SetClickHandler(hubClick) end
        UpdateBadge()
    end,

    -- Also runs after a half-finished OnEnable.
    OnDisable = function(self)
        local hub = PE.Hub
        if hub then
            if hub.SetClickHandler then hub:SetClickHandler(nil) end
            if hub.SetBadge then hub:SetBadge(nil) end
        end
        if built and panel then panel:Hide() end
    end,
})
