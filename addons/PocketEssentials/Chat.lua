-- Pocket Essentials: big chat buttons (module "chat").
-- While this is on, a tap on the round button opens a window of large
-- buttons: one for every place the character can talk right now, and one for
-- each person who whispered recently. A tap on a button closes the window and
-- opens the game's own chat box already pointed at that target. The player
-- then brings up the keyboard (three-finger tap) and types.
--
-- Nothing here hooks, filters or replaces the chat frames. The only game
-- events used are the two character-whisper events, and only while the
-- feature is on. (Battle.net whispers are not tracked in this version.)
local ADDON_NAME, PE = ...

local type, tostring, pcall, select, pairs = type, tostring, pcall, select, pairs
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local tinsert, tremove = table.insert, table.remove
local issecretvalue = issecretvalue -- nil on clients without secret values

local PANEL_NAME = "PocketEssentialsChatPanel"
local PANEL_TITLE = "Chat"
local HINT = "Three-finger tap for the keyboard"
local MAX_WHISPERS = 6 -- whisperers remembered, and name buttons in the window

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

local function Escape(text)
    return (tostring(text):gsub("|", "||"))
end

---------------------------------------------------------------------------
-- The saved whisper list: mod.opts.whispers, newest first, at most
-- MAX_WHISPERS long, so every counted mark has a button in the window.
--   { name = "Thrall", target = "Thrall-Realm", unanswered = true, time = ... }
-- `name` is the short form: the button label, and what an incoming and an
-- outgoing whisper are matched by. `target` is the sender exactly as the game
-- delivered it, and is what the chat box gets addressed to.
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
-- saved data, or Battle.net entries from an earlier version) and keep at
-- most MAX_WHISPERS.
local function CleanList()
    local list = List()
    if not list then return end
    local good = {}
    for i = 1, #list do
        local e = list[i]
        if #good < MAX_WHISPERS and type(e) == "table" and e.bn == nil
            and type(e.name) == "string" and e.name ~= "" then
            if type(e.target) ~= "string" or e.target == "" then e.target = e.name end
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

local function FindEntry(list, name)
    local key = name:lower()
    for i = 1, #list do
        local e = list[i]
        if type(e) == "table" and type(e.name) == "string" and e.name:lower() == key then return i end
    end
    return nil
end

local function UpdateBadge()
    local hub = PE.Hub
    if not (hub and hub.SetBadge) then return end
    local count = CountUnanswered(List())
    hub:SetBadge(count > 0 and tostring(count) or nil)
end

-- incoming: they whispered us (marked as waiting for an answer).
-- not incoming: we whispered them (that answers them).
-- Either way that person moves to the top of the list.
-- Only the badge changes here. If the window is open its buttons stay exactly
-- where they are (a button must never change who it whispers under the
-- player's finger); the new order is drawn the next time the window opens.
local function Touch(name, target, incoming)
    local list = List()
    if not list then return end
    local index = FindEntry(list, name)
    local entry = index and tremove(list, index)
    if type(entry) ~= "table" then entry = {} end
    entry.name = name
    entry.target = target
    entry.unanswered = incoming and true or false
    entry.time = time()
    tinsert(list, 1, entry)
    for i = #list, MAX_WHISPERS + 1, -1 do list[i] = nil end
    UpdateBadge()
end

---------------------------------------------------------------------------
-- Whisper events
---------------------------------------------------------------------------

-- "Name-Realm" as the events deliver it -> the short form ("Name" on our own
-- realm), so the incoming and the outgoing event for one person match.
-- Returns the short form and the untouched original, or nil.
local function CleanName(name)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local short = name
    if type(Ambiguate) == "function" then
        local ok, result = pcall(Ambiguate, name, "none")
        if ok and not IsSecret(result) and type(result) == "string" and result ~= "" then short = result end
    end
    return short, name
end

-- Payload (Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua):
-- 1 text, 2 playerName, ...
local function OnWhisper(_, event, ...)
    if InLockdown() then
        if PE.debugOn then PE:Debug("chat", "whisper skipped: chat lockdown") end
        return
    end
    local short, raw = CleanName((select(2, ...)))
    if short then
        if PE.debugOn then
            PE:Debug("chat", event == "CHAT_MSG_WHISPER" and "whisper noted (incoming)" or "whisper noted (outgoing)")
        end
        Touch(short, raw, event == "CHAT_MSG_WHISPER")
    elseif PE.debugOn then
        PE:Debug("chat", "whisper skipped: secret")
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
--
-- With the Gamepad UI on, the box is never opened from here. On the device
-- (Pocket Probe, 2026-11-17, in town, no fight) an addon opening, focusing
-- or closing the chat box was blocked inside Blizzard's controller code
-- (FrameControlsManager:FrameShown > SmartNavigation ActivateBinding), and
-- afterwards the game forbade its own controller actions
-- (SetPreferredGamepadInteractTarget, InteractUnit, ClearTarget,
-- SpellStopCasting) in the addon's name until a reload. Setting the chat type
-- on the closed box was allowed. So in that mode a tap only sets where the
-- chat goes, and the player opens chat with the game's own button; the box
-- keeps the type when it opens (ChatFrameEditBoxMixin:OnShow > ResetChatType
-- only changes a group type the player is no longer in).
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- "Press A to type" (Gamepad UI on).
--
-- An addon may not open the chat box, but the game's own "open chat" key
-- binding may, and an addon may point a controller button at a binding (the
-- probe: override bindings are allowed out of a fight). So after a target is
-- picked, the A button is lent to the game's OPENCHAT binding for a few
-- seconds: the press runs Blizzard's code, not ours. It is given back when
-- chat opens, when the time is up, when a fight starts and on switch-off.
-- Not in a fight: bindings cannot be changed then.
---------------------------------------------------------------------------

local TYPE_KEY = "PAD1"            -- the controller's A button
local TYPE_KEY_SECONDS = 12
local typeKeyOwner = CreateFrame("Frame", "PocketEssentialsChatKeyOwner", UIParent)
local typeKeyArmed, typeKeySerial, openChatHooked = false, 0, false

-- The "Press A to type" prompt: the addon's own display-only frame. It is
-- shown when the A button is lent and hidden when it is given back, and
-- nowhere else.
local prompt
local PromptLayout
local PROMPT_KEY = "chatPrompt"
local PROMPT_SAMPLE = "Chat is set to Say"      -- the second line's size when no prompt is up

-- Creates the prompt hidden. It is shown only by PromptShow.
local function PromptBuild()
    local UI = PE.UI
    if prompt or not UI then return end
    prompt = CreateFrame("Frame", nil, UIParent)
    prompt:Hide()                -- a new frame starts shown; only PromptShow may show it
    prompt:SetFrameStrata("HIGH")
    prompt:EnableMouse(false)
    prompt.back = prompt:CreateTexture(nil, "BACKGROUND")
    prompt.back:SetAllPoints(prompt)
    prompt.back:SetColorTexture(0, 0, 0, 0.75)
    prompt.title = UI:CreateText(prompt, "title")
    prompt.title:SetJustifyH("CENTER")
    prompt.font = UI:CreateText(prompt, "font")
    prompt.font:SetJustifyH("CENTER")
    UI:OnMetricsChanged(mod:Wrap(PromptLayout))
end

-- The prompt's size, text width, padding and anchor offset (the moved offset
-- included). Shared by PromptLayout and the "Move things" outline.
local function PromptGeometry()
    local UI = PE.UI
    local pad = UI:Px(14)
    local titleHeight = prompt.title:GetStringHeight() or UI:Px(24)
    local fontHeight = prompt.font:GetStringHeight() or UI:Px(18)
    local width = max(prompt.title:GetUnboundedStringWidth() or 0, prompt.font:GetUnboundedStringWidth() or 0)
    width = max(width, UI:Px(240))
    local Move, dx, dy = PE.Move, 0, 0
    if Move and Move.GetOffset then dx, dy = Move:GetOffset(PROMPT_KEY) end
    return width, pad, width + pad * 2, titleHeight + fontHeight + pad * 3, dx, UI:Px(110) + dy
end

PromptLayout = function()
    if not prompt then return end
    local width, pad, w, h, x, y = PromptGeometry()
    prompt:SetSize(w, h)
    prompt:ClearAllPoints()
    prompt:SetPoint("CENTER", UIParent, "CENTER", x, y)
    prompt.title:ClearAllPoints()
    prompt.title:SetPoint("TOP", prompt, "TOP", 0, -pad)
    prompt.title:SetWidth(width)
    prompt.font:ClearAllPoints()
    prompt.font:SetPoint("TOP", prompt.title, "BOTTOM", 0, -pad)
    prompt.font:SetWidth(width)
end

local function PromptShow(name)
    local UI = PE.UI
    if not UI then return end
    PromptBuild()
    prompt.title:SetText("Press A to type")
    prompt.font:SetText("Chat is set to " .. name)
    PromptLayout()
    prompt:Show()
    if PE.debugOn then PE:Debug("chat", "prompt shown") end
end

local function PromptHide(why)
    if not (prompt and prompt:IsShown()) then return end
    prompt:Hide()
    if PE.debugOn then PE:Debug("chat", "prompt hidden: " .. tostring(why)) end
end

-- Only out of a fight, or from PLAYER_REGEN_DISABLED (lockdown starts after it).
local function TypeKeyDisarm(why)
    if not typeKeyArmed then return end
    typeKeyArmed = false
    PromptHide(why)
    typeKeySerial = typeKeySerial + 1
    if ClearOverrideBindings then pcall(ClearOverrideBindings, typeKeyOwner) end
    if PE.debugOn then PE:Debug("chat", "A button given back: " .. tostring(why)) end
end

-- Returns true if the A button now opens chat. name says where the chat goes.
local function TypeKeyArm(name)
    if not (SetOverrideBinding and ClearOverrideBindings) or PE:InCombat() then return false end
    if not openChatHooked and type(hooksecurefunc) == "function"
            and type(ChatFrameUtil) == "table" and type(ChatFrameUtil.OpenChat) == "function" then
        -- Runs after the game's own function, and only to give the button back.
        openChatHooked = true
        hooksecurefunc(ChatFrameUtil, "OpenChat", function()
            if typeKeyArmed and not PE:InCombat() then PE:Safe("chat", TypeKeyDisarm, "chat opened") end
        end)
    end
    if not pcall(SetOverrideBinding, typeKeyOwner, true, TYPE_KEY, "OPENCHAT") then return false end
    typeKeyArmed = true
    mod:Safe(PromptShow, name)
    typeKeySerial = typeKeySerial + 1
    local serial = typeKeySerial
    mod:After(TYPE_KEY_SECONDS, function()
        if typeKeyArmed and typeKeySerial == serial then
            PE:RunOutOfCombat("chat:typekey", function() TypeKeyDisarm("time up") end)
        end
    end)
    if PE.debugOn then PE:Debug("chat", "A button opens chat for " .. TYPE_KEY_SECONDS .. " seconds") end
    return true
end

local function CanAddress(box, chatType)
    if type(box) ~= "table" then return false end
    if type(box.SetChatType) ~= "function" or type(box.UpdateHeader) ~= "function" then return false end
    if chatType == "CHANNEL" then return type(box.SetChannelTarget) == "function" end
    if chatType == "WHISPER" then return type(box.SetTellTarget) == "function" end
    return true
end

-- Returns true if the chat box was opened and pointed at the target, "set"
-- if it was only pointed (Gamepad UI on, box closed), false if neither.
local function OpenChatTo(chatType, target, slash)
    local util = ChatFrameUtil
    if type(util) ~= "table" then
        if PE.debugOn then PE:Debug("chat", "chat box not opened: no ChatFrameUtil") end
        return false
    end
    local choose, open, active = util.ChooseBoxForSend, util.OpenChat, util.GetActiveWindow
    if type(open) ~= "function" then
        if PE.debugOn then PE:Debug("chat", "chat box not opened: no ChatFrameUtil.OpenChat") end
        return false
    end

    if type(choose) == "function" and type(active) == "function" then
        local box = choose()
        if CanAddress(box, chatType) then
            local ready = (box == active())
            if not ready and PE:GamepadUI() then
                -- Closed box, controller style: point it, do not open it.
                -- No UpdateHeader either: the box redraws its header itself
                -- when the player opens it.
                if chatType == "CHANNEL" then
                    box:SetChannelTarget(target)
                elseif chatType == "WHISPER" then
                    box:SetTellTarget(target)
                end
                box:SetChatType(chatType)
                if PE.debugOn then PE:Debug("chat", "chat type set, box left closed (Gamepad UI)") end
                return "set"
            end
            if not ready and box.chatFrame ~= nil then
                -- Naming the chat frame keeps this out of any other window's
                -- chat line (the guild window has one).
                local opened = open(nil, box.chatFrame)
                if CanAddress(opened, chatType) and type(opened.IsShown) == "function" and opened:IsShown() then
                    box, ready = opened, true
                end
            end
            if ready then
                if chatType == "CHANNEL" then
                    box:SetChannelTarget(target)
                elseif chatType == "WHISPER" then
                    box:SetTellTarget(target)
                end
                box:SetChatType(chatType)
                box:UpdateHeader()
                if PE.debugOn then PE:Debug("chat", "chat box opened") end
                return true
            end
            if PE.debugOn then PE:Debug("chat", "chat box not opened: it did not open") end
        elseif PE.debugOn then
            PE:Debug("chat", "chat box not opened: box shape unexpected")
        end
    elseif PE.debugOn then
        PE:Debug("chat", "chat box not opened: ChatFrameUtil has no ChooseBoxForSend or GetActiveWindow")
    end

    -- The edit box does not look the way this file expects, or it did not
    -- open. Nothing else is tried: having the game read a typed command for
    -- us (SendTell, OpenChat with text) leaves our mark on the box's own
    -- fields, which a later typed /cast or /target then runs into.
    return false
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
local hintText, sectionText, emptyText
local targetButtons = {} -- reused on every redraw
local navList = {}       -- tappable buttons in reading order
local built, buildFailed = false, false
local onTargetClick, hubClick
local settingsHooked = false

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
    local shown = {}
    if list then
        for i = 1, #list do
            local e = list[i]
            if #shown < MAX_WHISPERS and type(e) == "table" and type(e.name) == "string" then shown[#shown + 1] = e end
        end
    end
    local marked = CountUnanswered(list)
    if PE.debugOn then
        PE:Debug("chat", "picker drawn: " .. #targets .. " targets, " .. #shown .. " whisper entries, " .. marked .. " marked")
    end

    local gap = M.gap
    local width, height = panel.contentWidth, panel.contentHeight
    local hintHeight, sectionHeight, emptyHeight = LineHeight("small"), LineHeight("title"), LineHeight("font")

    local function Columns(forWidth)
        return max(1, min(4, floor((forWidth + gap) / (M.button * 4.4 + gap))))
    end
    local function TotalHeight(cols, buttonHeight)
        local total = hintHeight + gap + ceil(#targets / cols) * (buttonHeight + gap) + sectionHeight + gap * 0.5
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
local function Refresh()
    if built and panel:IsShown() then mod:Safe(DoRefresh) end
end

local function TargetClicked(btn)
    local entry, target = btn.peChatEntry, btn.peChatTarget
    if not (entry or target) then return end
    if PE.debugOn then
        -- The kind only: never who a whisper is for.
        PE:Debug("chat", "tapped: " .. (entry and "whisper"
            or (PE.Plain(target.chatType) .. (target.target ~= nil and (" " .. PE.Plain(target.target)) or ""))))
    end
    if PE:CombatRestricted() and not PE:GamepadUI() then
        -- Opening the chat box from an addon during a fight is refused by the
        -- game. (With the Gamepad UI on the box is never opened from here,
        -- so a tap is fine in a fight too.)
        panel:Hide()
        if PE.debugOn then PE:Debug("chat", "refused: in a fight") end
        mod:Print("Not during a fight. Open chat the usual way, or try again afterwards.")
        return
    end
    local opened
    if entry then
        panel:Hide()
        opened = OpenChatTo("WHISPER", entry.target or entry.name)
    elseif target then
        panel:Hide()
        opened = OpenChatTo(target.chatType, target.target, target.slash)
    else
        return
    end
    if opened == "set" then
        local name = entry and "your whisper" or (type(target.label) == "string" and target.label or "that")
        if TypeKeyArm(name) then
            mod:Print("Chat is set to " .. name .. ". Press A to type.")
        else
            mod:Print("Chat is set to " .. name .. ". Open chat to type your message.")
        end
    elseif not opened then
        mod:Print("The chat box could not be opened.")
    end
end

local function ClearMarks()
    local list = List()
    if list then
        for i = 1, #list do
            if type(list[i]) == "table" then list[i].unanswered = false end
        end
    end
    if PE.debugOn then PE:Debug("chat", "marks cleared") end
    UpdateBadge()
    Refresh()
end

-- Only one of our two windows at a time: when the settings window shows
-- (holding the round button opens it), this one closes. The settings window
-- is our own frame and only exists after its first opening, so this is tried
-- again until it can be hooked.
local function HookSettings()
    if settingsHooked then return end
    local settings = _G["PocketEssentialsSettingsPanel"]
    if type(settings) ~= "table" or type(settings.HookScript) ~= "function" then return end
    settingsHooked = true
    settings:HookScript("OnShow", mod:Wrap(function()
        if built and panel:IsShown() then panel:Hide() end
    end))
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
    emptyText = UI:CreateText(area.child, "font")
    hintText:SetWordWrap(false)
    sectionText:SetWordWrap(false)
    emptyText:SetWordWrap(false)

    clearButton = UI:CreateButton(area.child, "Clear marks")
    clearButton:SetScript("OnClick", mod:Wrap(ClearMarks))

    settingsButton = UI:CreateButton(panel, "Settings")
    settingsButton:SetScript("OnClick", mod:Wrap(function()
        panel:Hide()
        PE:OpenSettings()
        HookSettings()
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
        if PE.debugOn then PE:Debug("chat", "picker could not be built: opening the settings instead") end
        PE:OpenSettings()
        return
    end
    PE:CloseSettings()
    -- Only one Pocket Essentials window at a time: the setup guide goes too.
    if PE.Setup and PE.Setup.Close then PE.Setup:Close() end
    HookSettings()
    area.offset = 0
    if PE.debugOn then PE:Debug("chat", "picker opened") end
    if not panel:IsShown() then panel:Show() end
    panel:Raise()
    Refresh()
end

-- What a tap on the round button does while this feature is on.
local function TogglePanel()
    if built and panel:IsShown() then
        if PE.debugOn then PE:Debug("chat", "picker closed by the round button") end
        panel:Hide()
    else
        OpenPanel()
    end
end

---------------------------------------------------------------------------
-- Chat text size.
-- The game's own function FCF_SetChatWindowFontSize(nil, chatFrame, size)
-- (Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua) sets the font of
-- one chat window and tells the game to remember the size. By Blizzard's
-- source it makes no protected call and never touches the chat box. The
-- game's chat tab menu (Font Size) does one window; here it is called for
-- every chat window so all tabs match, and only out of a fight.
-- The settings row is a number control: -, the size the game is using, +.
-- The steps are the game's own list, read when the row is drawn or tapped,
-- then two larger sizes. Nothing is saved here: the game keeps the size, and
-- nothing is changed until one of the two buttons is tapped. The row is
-- drawn whether "Big chat buttons" is on or off.
---------------------------------------------------------------------------

-- Our copy of the game's list (CHAT_FONT_HEIGHTS, FloatingChatFrame.lua:33),
-- used when the game's list is missing, and two larger sizes of our own.
local FALLBACK_SIZES = { 12, 14, 16, 18, 20, 24, 27 }
local EXTRA_SIZES = { 30, 34 }

-- The game's sizes as a new sorted list of whole numbers, and whether they
-- came from the game. The game's table is only read, never kept or written.
local function GameSizes()
    local out = {}
    local source = CHAT_FONT_HEIGHTS
    if type(source) == "table" then
        local seen = {}
        for i = 1, #source do
            local n = source[i]
            if type(n) == "number" and n > 0 then
                n = floor(n + 0.5)
                if n > 0 and not seen[n] then
                    seen[n] = true
                    out[#out + 1] = n
                end
            end
        end
        table.sort(out)
    end
    if #out > 0 then return out, true end
    for i = 1, #FALLBACK_SIZES do out[i] = FALLBACK_SIZES[i] end
    return out, false
end

-- Every step of the stepper: the game's sizes, then ours that are larger.
local function StepSizes()
    local list, fromGame = GameSizes()
    local last = list[#list]
    for i = 1, #EXTRA_SIZES do
        if EXTRA_SIZES[i] > last then list[#list + 1] = EXTRA_SIZES[i] end
    end
    return list, fromGame
end

local FALLBACK_WINDOWS = 10 -- Constants.ChatFrameConstants.MaxChatWindows

local function WindowCount()
    local n = tonumber(NUM_CHAT_WINDOWS)
    if n and n >= 1 then return floor(n) end
    return FALLBACK_WINDOWS
end

-- The main chat window, or nil when this version of the game has none.
local function MainChatWindow()
    local frame = DEFAULT_CHAT_FRAME
    if type(frame) == "table" and type(frame.GetFont) == "function" then return frame end
    return nil
end

local function TextSizeAvailable()
    return type(FCF_SetChatWindowFontSize) == "function" and MainChatWindow() ~= nil
end

-- The main window's font height as a whole number, or nil.
local function CurrentTextSize()
    local frame = MainChatWindow()
    if not frame then return nil end
    local ok, _, size = pcall(frame.GetFont, frame)
    if ok and type(size) == "number" and size > 0 then return floor(size + 0.5) end
    return nil
end

-- The next size of a list in a direction (1 bigger, -1 smaller), or nil at the end.
local function NextTextSize(sizes, current, direction)
    if direction > 0 then
        for i = 1, #sizes do
            if sizes[i] > current then return sizes[i] end
        end
    else
        for i = #sizes, 1, -1 do
            if sizes[i] < current then return sizes[i] end
        end
    end
    return nil
end

-- Sizes picked during a fight, waiting for it to end: the size the last tap
-- will set. Taps in a fight step from here, so two taps are two steps.
local pendingSize

-- Sets one size on every chat window. Runs out of a fight only.
local function ApplyTextSize(size)
    local waited = pendingSize ~= nil
    pendingSize = nil
    if waited then PE:RefreshSettings() end -- the "(after the fight)" note goes away
    if not TextSizeAvailable() then
        if PE.debugOn then PE:Debug("chat", "text size: not available") end
        return
    end
    local current = CurrentTextSize() or size
    local done = 0
    for i = 1, WindowCount() do
        local frame = _G["ChatFrame" .. i]
        if type(frame) == "table" then
            local ok = pcall(FCF_SetChatWindowFontSize, nil, frame, size)
            if ok then done = done + 1 end
        end
    end
    if PE.debugOn then
        PE:Debug("chat", "text size " .. current .. " -> " .. size .. " (" .. done .. " windows)")
    end
end

-- The one way in: sets a size now, or holds it until the fight ends.
local function SetTextSize(size)
    if not TextSizeAvailable() then
        if PE.debugOn then PE:Debug("chat", "text size: not available") end
        return
    end
    if PE:InCombat() then
        pendingSize = size
        if PE.debugOn then PE:Debug("chat", "text size change held for after the fight") end
    end
    PE:RunOutOfCombat("chat:fontsize", function() ApplyTextSize(size) end)
end

local function ChangeTextSize(direction)
    local current = TextSizeAvailable() and CurrentTextSize()
    if not current then
        if PE.debugOn then PE:Debug("chat", "text size: not available") end
        return
    end
    local sizes, fromGame = StepSizes()
    if not fromGame and PE.debugOn then
        PE:Debug("chat", "text size: the game's size list is missing, using our own")
    end
    local base = pendingSize or current
    local size = NextTextSize(sizes, base, direction)
    if not size then
        if PE.debugOn then
            PE:Debug("chat", "text size " .. base .. ": already the " .. (direction > 0 and "biggest" or "smallest"))
        end
        return
    end
    SetTextSize(size)
end

-- The text after the row's label: nothing while the stepper shows the size,
-- the waiting size during a fight, or why there is no stepper.
local function TextSizeValue()
    local size = TextSizeAvailable() and CurrentTextSize()
    if size then
        if pendingSize and pendingSize ~= size then return pendingSize .. " (after the fight)" end
        return nil
    end
    return "Not available on this version of the game"
end

-- The number control (Settings.lua, stepper row): the size the game is
-- using right now between - and +. A side with no further step (counting a
-- step that waits for the end of a fight) is a dimmed end; a press on it
-- changes nothing. nil when there is no size to show.
local function TextSizeStepper()
    local size = TextSizeAvailable() and CurrentTextSize()
    if not size then return nil end
    local sizes = StepSizes()
    local base = pendingSize or size
    return {
        text = tostring(size),
        unit = "text size",
        -- A dimmed end still calls ChangeTextSize, which only writes the
        -- debug line saying there is no further step.
        down = function() ChangeTextSize(-1) end,
        up = function() ChangeTextSize(1) end,
        downDim = not NextTextSize(sizes, base, -1),
        upDim = not NextTextSize(sizes, base, 1),
    }
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

    options = {
        { label = "Chat text size", value = TextSizeValue, stepper = TextSizeStepper, always = true },
    },

    OnEnable = function(self)
        CleanList()
        self:RegisterEvent("CHAT_MSG_WHISPER", OnWhisper)
        self:RegisterEvent("CHAT_MSG_WHISPER_INFORM", OnWhisper)
        self:RegisterEvent("PLAYER_REGEN_DISABLED", function() TypeKeyDisarm("fight started") end)
        hubClick = hubClick or self:Wrap(TogglePanel)
        local hub = PE.Hub
        if hub and hub.SetClickHandler then hub:SetClickHandler(hubClick) end
        UpdateBadge()
        HookSettings()
    end,

    -- Also runs after a half-finished OnEnable.
    OnDisable = function(self)
        local hub = PE.Hub
        if hub then
            if hub.SetClickHandler then hub:SetClickHandler(nil) end
            if hub.SetBadge then hub:SetBadge(nil) end
        end
        if built and panel then panel:Hide() end
        if typeKeyArmed then
            PE:RunOutOfCombat("chat:typekey", function() TypeKeyDisarm("switched off") end)
        end
    end,
})

-- "Move things": the prompt's backdrop can be nudged from its usual spot.
if PE.Move and PE.Move.Register then
    PE.Move:Register({
        key = PROMPT_KEY, label = "Chat prompt", order = 20,
        available = function() return mod ~= nil and mod:IsEnabled() end,
        apply = function() PromptLayout() end,      -- does nothing until the prompt is built
        outline = function(box)
            -- Works before the prompt was ever shown: it is built hidden and, while
            -- it is not up, holds sample text so the size is the real one.
            PromptBuild()
            if not prompt then return end
            if not prompt:IsShown() then
                prompt.title:SetText("Press A to type")
                prompt.font:SetText(PROMPT_SAMPLE)
            end
            local _, _, w, h, x, y = PromptGeometry()
            box:ClearAllPoints()
            box:SetPoint("CENTER", UIParent, "CENTER", x, y)
            box:SetSize(w, h)
        end,
    })
end
