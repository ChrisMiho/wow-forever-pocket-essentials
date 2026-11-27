-- Pocket Essentials: chat from round button (module "chat").
-- While this is on, a tap on the round button opens a window of large
-- buttons: one for every place the character can talk right now, and one for
-- each person who whispered recently. A tap on a button closes the window and
-- opens the game's own chat box already pointed at that target. The player
-- then brings up the keyboard (three-finger tap) and types.
--
-- Nothing here hooks, filters or replaces the chat frames. The only game
-- events used are the two character-whisper events, and only while the
-- feature is on. (Battle.net whispers are not tracked in this version.)
--
-- Since 0.21.0 the window can end with a "Quick slots" line holding one
-- square, the mount (row "Quick slots", Off by default). Its rules are in
-- QuickSlots.lua; this file only draws the square and passes on the tap.
local ADDON_NAME, PE = ...

local type, tostring, pcall, select, pairs = type, tostring, pcall, select, pairs
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local tinsert, tremove = table.insert, table.remove
local issecretvalue = issecretvalue -- nil on clients without secret values

local PANEL_NAME = "PocketEssentialsChatPanel"
local PANEL_TITLE = "Chat"
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
-- The saved whisper list: PE.charDB.chatWhispers, in this character's own
-- saved file (PocketEssentialsCharDB), so an alt never sees the names and
-- they stay out of the account-wide file that goes with a debug log. Newest
-- first, at most MAX_WHISPERS long, so every counted mark has a button in
-- the window.
--   { name = "Thrall", target = "Thrall-Realm", unanswered = true, time = ... }
-- `name` is the short form: the button label, and what an incoming and an
-- outgoing whisper are matched by. `target` is the sender exactly as the game
-- delivered it, and is what the chat box gets addressed to. The unanswered
-- mark lives in the entry, so it moves with it.
---------------------------------------------------------------------------

-- PE.charDB is read on every call: Core sets it again when the saved
-- variables load.
local function List()
    local charDB = PE.charDB
    if type(charDB) ~= "table" then return nil end
    local list = charDB.chatWhispers
    if type(list) ~= "table" then
        list = {}
        charDB.chatWhispers = list
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
-- included). Shared by PromptLayout and the "Move on screen" outline.
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
-- As big as its content and centred: a "Talk in" heading and the targets,
-- then a "Whispers" heading and the names, in three columns of chips. Every
-- size in it is the shared size times the "Chat picker size"
-- setting (opts.scale, 70 to 150 per cent), except the border. So the window
-- lays out its own title bar and has its own three fonts, set again only when
-- it opens or redraws and a size has changed.
---------------------------------------------------------------------------

local UI, M, S
local panel, area
local settingsButton, clearButton
local talkText, whispersText, emptyText
local quickText, slotButton, slotText -- the "Quick slots" line; made the first time it is drawn
local targetButtons = {} -- reused on every redraw
local navList = {}       -- tappable buttons in reading order
local built, buildFailed = false, false
local onTargetClick, hubClick
local settingsHooked = false

local COLS = 3
local CHIP_WIDTH = 3.4                  -- in buttons
local SCALE_MIN, SCALE_MAX, SCALE_DEFAULT = 70, 150, 100

local COLOR_HEAD = { 1, 0.82, 0 }
local COLOR_DIM = { 0.62, 0.62, 0.62 }
local COLOR_DOT = { 0.88, 0.08, 0.08 }
local COLOR_PLAIN = { 1, 1, 1 }

local SLOT_SIZE = 1.5                   -- the mount square's side, in buttons
local NOTE_FIGHT = "Not in a fight"
local NOTE_MISSING = "Not available on this version of the game"

local function Scale()
    local n = tonumber(mod and mod.opts and mod.opts.scale)
    if not n then return SCALE_DEFAULT end
    return min(max(n, SCALE_MIN), SCALE_MAX)
end

-- The window's sizes (S): the shared ones times the scale, the border as it
-- is. A window that would be wider than the screen is made smaller to fit.
local function ScaledMetrics()
    M = UI:Metrics()
    local s = Scale() / 100
    local screenWidth = UIParent:GetWidth()
    if type(screenWidth) ~= "number" or screenWidth < 100 then screenWidth = 1024 end
    local width = (2 * M.pad + COLS * CHIP_WIDTH * M.button + (COLS - 1) * M.gap) * s
    if width > screenWidth * 0.96 then s = s * screenWidth * 0.96 / width end
    S = S or {}
    S.scale = s
    S.button, S.gap, S.pad, S.row = M.button * s, M.gap * s, M.pad * s, M.row * s
    S.fontSize, S.smallFontSize = M.fontSize * s, M.smallFontSize * s
    S.border = M.border
    return S
end

-- The window's own fonts. Each copies the face of the shared font of its
-- kind at the window's size. false when one could not be made: that kind
-- then keeps the shared font (the right face, at the normal size).
local FONT_NAMES = {
    font = "PocketEssentialsChatFont",
    small = "PocketEssentialsChatFontSmall",
    title = "PocketEssentialsChatFontTitle",
}
local FONT_SHARED = { font = "font", small = "smallFont", title = "titleFont" } -- fields of UI:Metrics()
local FONT_COLOR = { font = { 1, 1, 1 }, small = { 0.84, 0.84, 0.84 }, title = { 1, 0.82, 0 } }
local fonts, fontSizes = {}, {}

local function SharedFont(kind)
    local object = _G[M[FONT_SHARED[kind]]]
    if type(object) == "table" and type(object.GetFont) == "function" then return object end
    return nil
end

local function UpdateFonts()
    local sizes = { font = S.fontSize, small = S.smallFontSize, title = S.fontSize * 1.12 }
    for kind, name in pairs(FONT_NAMES) do
        local object = fonts[kind]
        if object == nil then
            local ok, made = false, nil
            if type(CreateFont) == "function" then ok, made = pcall(CreateFont, name) end
            object = (ok and made) or false
            if object then
                local c = FONT_COLOR[kind]
                pcall(object.SetTextColor, object, c[1], c[2], c[3], 1)
                pcall(object.SetShadowColor, object, 0, 0, 0, 1)
                pcall(object.SetShadowOffset, object, 1, -1)
            end
            fonts[kind] = object
        end
        if object and (not fontSizes[kind] or abs(fontSizes[kind] - sizes[kind]) > 0.001) then
            local shared = SharedFont(kind)
            local ok, file, _, flags = false, nil, nil, nil
            if shared then ok, file, _, flags = pcall(shared.GetFont, shared) end
            if ok and type(file) == "string" and file ~= "" then
                local set = pcall(object.SetFont, object, file, sizes[kind], type(flags) == "string" and flags or "")
                if set and object:GetFont() then
                    fontSizes[kind] = sizes[kind]
                else
                    fonts[kind] = false
                end
            else
                fonts[kind] = false
            end
        end
    end
end

-- The font object for a kind: the window's own, or the shared one.
local function FontFor(kind)
    return fonts[kind] or SharedFont(kind)
end

-- Set once, when the text is made: the object stays the same and its size
-- follows the window. (Setting a font object again could reset the colour a
-- button's style gave its label.)
local function UseFont(fontString, kind)
    local object = FontFor(kind)
    if object then fontString:SetFontObject(object) end
end

-- A button's label inset at the window's size.
local function FitLabel(btn)
    btn.peText:ClearAllPoints()
    btn.peText:SetPoint("LEFT", btn, "LEFT", S.gap * 0.5, 0)
    btn.peText:SetPoint("RIGHT", btn, "RIGHT", -S.gap * 0.5, 0)
end

-- The title bar at the window's size: what UI.lua's panel layout does with
-- the shared sizes, with Settings left of Close.
local function LayoutChrome(width, height)
    panel:SetPanelSize(width, height)
    local b, bar = S.border, S.button + S.gap
    local close = panel.closeButton
    close:SetSize(S.button * 2, S.button)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(b + S.gap * 0.5), -(b + S.gap * 0.5))
    FitLabel(close)

    settingsButton:SetSize(S.button * 2.6, S.button)
    settingsButton:ClearAllPoints()
    settingsButton:SetPoint("RIGHT", close, "LEFT", -S.gap, 0)
    FitLabel(settingsButton)

    panel.peTitle:ClearAllPoints()
    panel.peTitle:SetPoint("LEFT", panel, "TOPLEFT", S.pad, -(b + bar * 0.5))
    panel.peTitle:SetPoint("RIGHT", settingsButton, "LEFT", -S.gap, 0)

    panel.peLine:ClearAllPoints()
    panel.peLine:SetPoint("TOPLEFT", panel, "TOPLEFT", b, -(b + bar))
    panel.peLine:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -b, -(b + bar))

    panel.content:ClearAllPoints()
    panel.content:SetPoint("TOPLEFT", panel, "TOPLEFT", S.pad, -(b + bar + S.gap))
    panel.content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -S.pad, S.pad)
end

local function PlaceText(fontString, text, y, width, color)
    fontString:ClearAllPoints()
    fontString:SetPoint("TOPLEFT", area.child, "TOPLEFT", 0, -y)
    fontString:SetWidth(max(width, 10))
    fontString:SetText(text)
    fontString:SetTextColor(color[1], color[2], color[3], 1)
    fontString:Show()
end

-- The round red dot at a chip's top-right, for a name waiting for an answer.
local function SetDot(btn, shown)
    local dot = btn.peChatDot
    if not shown then
        if dot then dot:SetShown(false) end
        return
    end
    if not dot then
        dot = UI:CreateDisc(btn, "OVERLAY", 5)
        dot:SetColor(COLOR_DOT[1], COLOR_DOT[2], COLOR_DOT[3], 1)
        btn.peChatDot = dot
    end
    local size, inset = S.smallFontSize * 0.7, S.gap * 0.6
    dot:Layout(btn, size)
    dot.texture:ClearAllPoints()
    dot.texture:SetPoint("CENTER", btn, "TOPRIGHT", -(inset + size * 0.5), -(inset + size * 0.5))
    dot:SetShown(true)
end

-- index counts from 1 in a grid whose top is at y.
local function PlaceChip(btn, label, index, y, style)
    local chip = S.button * CHIP_WIDTH
    local col, row = (index - 1) % COLS, floor((index - 1) / COLS)
    local top = y + row * (S.button + S.gap)
    btn:SetSelected(false)
    btn:SetStyle(style or "normal")
    btn:SetBadgeText(nil)
    SetDot(btn, false)
    btn:ClearAllPoints()
    btn:SetLabel(label)
    btn:SetSize(chip, S.button)
    btn:SetPoint("TOPLEFT", area.child, "TOPLEFT", col * (chip + S.gap), -top)
    FitLabel(btn)
    btn.peScrollTop, btn.peScrollBottom = top, top + S.button
    btn:Show()
    navList[#navList + 1] = btn
end

local function TargetButton(index)
    local btn = targetButtons[index]
    if not btn then
        btn = UI:CreateButton(area.child, "")
        UseFont(btn.peText, "font")
        btn:SetScript("OnClick", onTargetClick)
        targetButtons[index] = btn
    end
    return btn
end

---------------------------------------------------------------------------
-- The "Quick slots" line: a heading and one square, the mount, under the
-- whisper names. Drawn only while the row "Quick slots" is On. The square is
-- a button of our own from the window's button maker with a picture of our
-- own on it; QuickSlots.lua says what it shows (QS:Line) and does the tap
-- (QS:Tap). The game is asked when the window is drawn and on a tap, never
-- in between, except with the row "Mount square, live" On (see Live below).
---------------------------------------------------------------------------

local function QuickOn()
    return PE.QuickSlots ~= nil and type(mod.opts) == "table" and mod.opts.quickSlots == 1
end

-- What the square should show right now, or nil when the line is not drawn.
-- fight: true or false when the caller knows better than InCombatLockdown (see Live below).
local function QuickState(fight)
    if not QuickOn() then return nil end
    local ok, state = mod:Safe(PE.QuickSlots.Line, PE.QuickSlots, fight)
    if ok and type(state) == "table" then return state end
    return nil
end

local Refresh

-- The row "Mount square, live" (b22Mount): while it is On, the Quick slots line
-- is On and the window is open, the square is drawn again when a fight starts
-- or ends, when the player mounts or gets off, and when the game says whether
-- a mount can be used here has changed (going indoors or outdoors). The events
-- are registered only for that time. No timer. registered: whether they are;
-- fight: what to draw as "in a fight" while the answer of InCombatLockdown is
-- not yet right; last: the state of the latest drawing, for the log line.
local Live = { registered = false, fight = nil, last = nil }

-- A tap on the square. Getting on or off closes the window. In a fight
-- nothing is asked of the game and the line says so; the window stays open.
local function SlotClicked()
    local QS = PE.QuickSlots
    if not QS then return end
    local action = QS:Tap()
    if action == "summon" or action == "dismiss" then
        panel:Hide()
        return
    end
    -- Drawn again first: a fight may have started since the window opened.
    Refresh()
    if not (slotText and slotText:IsShown()) then return end
    if action == "combat" then
        slotText:SetText(NOTE_FIGHT)
    elseif action == "missing" then
        slotText:SetText(NOTE_MISSING)
    end
    slotText:SetTextColor(COLOR_HEAD[1], COLOR_HEAD[2], COLOR_HEAD[3], 1)
end

local function QuickBuild()
    if slotButton then return end
    quickText = UI:CreateText(area.child, "small")
    UseFont(quickText, "small")
    quickText:SetWordWrap(false)
    slotText = UI:CreateText(area.child, "font")
    UseFont(slotText, "font")
    slotText:SetWordWrap(false)
    slotText:SetJustifyH("LEFT")
    local btn = UI:CreateButton(area.child, "")
    UseFont(btn.peText, "font")
    -- Above the button's fill, under its pressed flash.
    btn.peSlotIcon = btn:CreateTexture(nil, "BORDER", nil, 1)
    btn:SetScript("OnClick", mod:Wrap(SlotClicked))
    slotButton = btn
end

local function QuickHide()
    if not slotButton then return end
    quickText:Hide()
    slotText:Hide()
    slotButton:Hide()
end

-- The height the line adds to the window's content.
local function QuickHeight(head)
    return S.gap * 1.5 + head + S.button * SLOT_SIZE
end

-- Draws the line with its heading's top at y. Returns the y under the square.
local function PlaceQuick(state, y, head, contentWidth)
    QuickBuild()
    PlaceText(quickText, "Quick slots", y, contentWidth, COLOR_HEAD)
    local top = y + head
    local side = S.button * SLOT_SIZE
    local btn = slotButton
    btn:SetStyle(state.greyed and "disabled" or "normal")
    btn:SetSelected(state.bright and true or false)   -- the bright edge while mounted
    btn:ClearAllPoints()
    btn:SetSize(side, side)
    btn:SetPoint("TOPLEFT", area.child, "TOPLEFT", 0, -top)
    FitLabel(btn)
    local icon = btn.peSlotIcon
    if state.icon ~= nil then
        -- Inside the button's edge, so the edge (gold while mounted) shows round it.
        local inset = S.border * 3
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
        icon:SetTexture(state.icon)
        icon:SetDesaturated(state.greyed and true or false)
        local shade = state.greyed and 0.45 or 1
        icon:SetVertexColor(shade, shade, shade, 1)
        icon:Show()
        btn:SetLabel("")
    else
        icon:Hide()
        btn:SetLabel("?")
    end
    -- The heading counts as part of the stop, so the d-pad brings it into view too.
    btn.peScrollTop, btn.peScrollBottom = y, top + side
    btn:Show()
    navList[#navList + 1] = btn

    local color = state.greyed and COLOR_DIM or COLOR_PLAIN
    slotText:ClearAllPoints()
    slotText:SetPoint("LEFT", btn, "RIGHT", S.gap, 0)
    slotText:SetWidth(max(contentWidth - side - S.gap, 10))
    slotText:SetText(state.label)
    slotText:SetTextColor(color[1], color[2], color[3], 1)
    slotText:Show()
    return top + side
end

-- The height of n chips in rows of three.
local function GridHeight(n)
    local rows = ceil(n / COLS)
    if rows < 1 then return 0 end
    return rows * S.button + (rows - 1) * S.gap
end

local function DoRefresh()
    ScaledMetrics()
    UpdateFonts()
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

    local gap, b = S.gap, S.border
    local contentWidth = COLS * S.button * CHIP_WIDTH + (COLS - 1) * gap
    local lineHeight = S.smallFontSize * 1.15
    local head = lineHeight + gap * 0.4
    local contentHeight = head + GridHeight(#targets) + gap * 1.5 + head
        + (#shown > 0 and GridHeight(#shown + 1) or lineHeight)
    local quick = QuickState(Live.fight)
    Live.last = quick
    if quick then contentHeight = contentHeight + QuickHeight(head) end

    -- As tall as the content. Only if that is taller than the screen allows
    -- does the list scroll, with its bar beside the chips.
    local chrome = b + S.button + gap + gap + S.pad
    local screenHeight = UIParent:GetHeight()
    if type(screenHeight) ~= "number" or screenHeight < 100 then screenHeight = 768 end
    local maxHeight = screenHeight * 0.92
    local scroll = chrome + contentHeight > maxHeight
    -- The scroll bar follows the window's own scale, like its chips.
    local barWidth = (scroll and PE:UsesTouch()) and (S.button * 0.75 + S.gap) or 0
    local viewHeight = scroll and max(maxHeight - chrome, S.button) or contentHeight

    LayoutChrome(2 * S.pad + contentWidth + barWidth, chrome + viewHeight)
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, 0)
    area:Layout(contentWidth + barWidth, viewHeight, not scroll, S)

    local y = 0
    PlaceText(talkText, "Talk in", y, contentWidth, COLOR_HEAD)
    y = y + head
    for i = 1, #targets do
        local btn = TargetButton(i)
        PlaceChip(btn, targets[i].label, i, y)
        btn.peChatTarget, btn.peChatEntry = targets[i], nil
    end
    y = y + GridHeight(#targets) + gap * 1.5
    local used = #targets

    PlaceText(whispersText, "Whispers", y, contentWidth, COLOR_HEAD)
    y = y + head

    if #shown == 0 then
        PlaceText(emptyText, "No whispers yet.", y, contentWidth, COLOR_DIM)
        clearButton:Hide()
        y = y + lineHeight
    else
        emptyText:Hide()
        for i = 1, #shown do
            local entry = shown[i]
            local btn = TargetButton(used + i)
            PlaceChip(btn, Escape(entry.name), i, y, entry.unanswered and "warn" or "normal")
            btn.peChatTarget, btn.peChatEntry = nil, entry
            if entry.unanswered then SetDot(btn, true) end
        end
        -- Always the last chip, so it is always in the same place. Dimmed
        -- (still tappable) while nothing is marked.
        PlaceChip(clearButton, "Clear marks", #shown + 1, y, marked > 0 and "off" or "disabled")
        y = y + GridHeight(#shown + 1)
        used = used + #shown
    end

    for i = used + 1, #targetButtons do targetButtons[i]:Hide() end

    if quick then
        y = PlaceQuick(quick, y + gap * 1.5, head, contentWidth)
    else
        QuickHide()
    end
    area:SetContentHeight(max(y, 1))

    if scroll and area.upButton:IsShown() then
        navList[#navList + 1] = area.upButton
        navList[#navList + 1] = area.downButton
    end
    navList[#navList + 1] = settingsButton
    navList[#navList + 1] = panel.closeButton
    panel:NavRefresh()
end

-- Does nothing unless the window is open.
Refresh = function()
    if built and panel:IsShown() then mod:Safe(DoRefresh) end
end

-- True if a target drawn earlier is still there now: the same kind, number
-- and name. Channel numbers shift when a city channel is left, and Party goes
-- when the group does.
local function StillThere(target)
    local now = GatherTargets()
    for i = 1, #now do
        local t = now[i]
        if t.chatType == target.chatType and t.target == target.target and t.label == target.label then return true end
    end
    return false
end

local function TargetClicked(btn)
    local entry, target = btn.peChatEntry, btn.peChatTarget
    if not (entry or target) then return end
    if PE.debugOn then
        -- The kind only: never who a whisper is for.
        PE:Debug("chat", "tapped: " .. (entry and "whisper"
            or (PE.Plain(target.chatType) .. (target.target ~= nil and (" " .. PE.Plain(target.target)) or ""))))
    end
    if not entry and not StillThere(target) then
        if PE.debugOn then PE:Debug("chat", "tapped target is gone: window redrawn") end
        Refresh()
        mod:Print("That channel is gone.")
        return
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
        local name = entry and ("a whisper to " .. Escape(entry.name))
            or (type(target.label) == "string" and target.label or "that")
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

---------------------------------------------------------------------------
-- The row "Mount square, live"
-- Events, from the pinned source (Blizzard_APIDocumentationGenerated):
--   PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED: UnitDocumentation.lua:3887, :3893
--   PLAYER_MOUNT_DISPLAY_CHANGED: UnitDocumentation.lua:3861
--   MOUNT_JOURNAL_USABILITY_CHANGED: MountJournalDocumentation.lua:650; the
--   game's own Mount list redraws on it (Blizzard_Collections/Classic/
--   Blizzard_MountCollection.lua:22 and :222). It also covers going indoors
--   and outdoors, which is when a mount stops or starts being usable.
-- PLAYER_REGEN_DISABLED is already listened to for the whole session by the
-- "press A to type" prompt (OnEnable below); its handler calls LiveRedraw too,
-- which does nothing unless Live.registered. It arrives before the game's
-- combat lock is on, so that call says "in a fight" itself.
---------------------------------------------------------------------------

local LIVE_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_MOUNT_DISPLAY_CHANGED", "MOUNT_JOURNAL_USABILITY_CHANGED" }

-- The word for the log: what the square says now.
local function LiveWord(state)
    if state.bright then return "mounted" end
    if state.action == "combat" then return "in a fight" end
    if state.greyed then return "cannot mount here" end
    return "ready"
end

local function LiveRedraw(fight)
    if not Live.registered then return end
    Live.fight, Live.last = fight, nil
    Refresh()
    Live.fight = nil
    local state = Live.last
    if state and PE.debugOn then
        PE:Debug("chat", "quick slots: mount square redrawn: " .. LiveWord(state))
    end
end

local function LiveWanted()
    local batch = PE.Batch
    return built and panel:IsShown() and QuickOn() and type(batch) == "table" and batch.On("b22Mount")
end

-- Registers or drops the events to match: called when the window opens or
-- closes, and when either row changes.
local function LiveSync()
    local want = LiveWanted() and true or false
    if want == Live.registered then return end
    Live.registered = want
    if want then
        Live.handler = Live.handler or mod:Wrap(function() LiveRedraw(nil) end)
        for _, event in ipairs(LIVE_EVENTS) do mod:RegisterEvent(event, Live.handler) end
    else
        for _, event in ipairs(LIVE_EVENTS) do mod:UnregisterEvent(event) end
    end
end

local batchRows = PE.Batch
if type(batchRows) == "table" and type(batchRows.Listen) == "function" then
    batchRows.Listen("b22Mount", function() LiveSync() end)
end

local function Build()
    UI = PE.UI
    onTargetClick = mod:Wrap(TargetClicked)
    ScaledMetrics()
    UpdateFonts()

    -- The size is set each time the window is drawn (DoRefresh).
    panel = UI:CreatePanel(PANEL_NAME, PANEL_TITLE, UI:Px(600), UI:Px(400))
    area = UI:CreateScrollArea(panel.content)
    UseFont(panel.peTitle, "title")
    UseFont(panel.closeButton.peText, "font")

    talkText = UI:CreateText(area.child, "small")
    whispersText = UI:CreateText(area.child, "small")
    emptyText = UI:CreateText(area.child, "small")
    for _, text in ipairs({ talkText, whispersText, emptyText }) do
        UseFont(text, "small")
        text:SetWordWrap(false)
    end

    clearButton = UI:CreateButton(area.child, "Clear marks")
    UseFont(clearButton.peText, "font")
    clearButton:SetScript("OnClick", mod:Wrap(ClearMarks))

    settingsButton = UI:CreateButton(panel, "Settings")
    UseFont(settingsButton.peText, "font")
    settingsButton:SetScript("OnClick", mod:Wrap(function()
        panel:Hide()
        PE:OpenSettings()
        HookSettings()
    end))

    panel:HookScript("OnShow", mod:Wrap(LiveSync))
    panel:HookScript("OnHide", mod:Wrap(LiveSync))

    UI:AttachNav(panel, function() return navList end)
    panel.peNavArea = area   -- lets the d-pad page the list when touch is off (UI.lua NavMove)
    panel.navOnFocus = function(btn)
        if btn.peScrollTop then area:ScrollIntoView(btn) end
    end

    -- A new button size or screen: drawn again if open, else when it next opens.
    UI:OnMetricsChanged(mod:Wrap(function()
        if built then Refresh() end
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
-- drawn whether Chat picker is on or off.
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
-- The two "Quick slots" rows.
-- "Quick slots" Off / On is saved as opts.quickSlots (1 for On; nothing is
-- saved until the row is tapped, and nothing saved means Off). It is drawn
-- with Chat picker off too, where it says what it needs: the square lives in
-- the Chat picker's window, so with Chat picker off there is no window to
-- hold it and nothing is built. "Mount" steps through the mounts this
-- character owns (QuickSlots.lua keeps the choice in the character's own
-- saved file).
---------------------------------------------------------------------------

local OFF_ON = { { value = 0, label = "Off" }, { value = 1, label = "On" } }

local function QuickGet(self)
    return (type(self.opts) == "table" and self.opts.quickSlots == 1) and 1 or 0
end

local function QuickSet(self, value)
    self.opts.quickSlots = (value == 1) and 1 or 0
    if PE.debugOn then PE:Debug("chat", "quick slots: " .. (value == 1 and "on" or "off")) end
    LiveSync()
    Refresh()
end

local function QuickValue(self)
    if not self:IsEnabled() then return "Needs Chat picker" end
    return nil
end

-- The text after "Mount": nothing, the control shows the choice.
local function MountValue()
    local QS = PE.QuickSlots
    if QS == nil then return "Not available" end
    return nil
end

-- The number control with the chosen mount between - and +, and under it
-- which mount "First favourite" stands for, or the mount's place in the
-- list. With no mount owned it reads "No mount yet" and both ends are dim:
-- there is nothing to step through.
local function MountStepper()
    local QS = PE.QuickSlots
    if not QS then return nil end
    -- With Quick slots Off the journal is not read: the row only says how to start.
    if QuickGet(mod) ~= 1 then return { text = "Turn Quick slots on", downDim = true, upDim = true } end
    local label, note = QS:MountLabel()
    if note == nil then return { text = label, downDim = true, upDim = true } end
    return {
        text = Escape(label),
        unit = Escape(note),
        down = function() QS:StepMount(-1) Refresh() end,
        up = function() QS:StepMount(1) Refresh() end,
    }
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

mod = PE:RegisterModule({
    key = "chat",
    label = "Chat picker",
    desc = "Tap the round button to pick who to talk to.",
    order = 60,
    defaults = { scale = SCALE_DEFAULT },

    options = {
        { label = "Chat text size", value = TextSizeValue, stepper = TextSizeStepper, always = true,
          help = "All chat windows, even with Chat picker off." },
        { key = "scale", label = "Chat picker size",
          number = { min = SCALE_MIN, max = SCALE_MAX, step = 10, default = SCALE_DEFAULT, suffix = "%", unit = "of normal" } },
        -- guide = false: the setup guide leaves these two out (its Chat screen is full, and
        -- this part is new and untried); they are in the settings only.
        { label = "Quick slots", value = QuickValue, choices = OFF_ON, get = QuickGet, set = QuickSet, always = true,
          guide = false, help = "A mount square in the Chat picker's window." },
        { label = "Mount", value = MountValue, stepper = MountStepper, guide = false,
          help = "The mount the square uses." },
    },

    -- Before 0.15.0 the whisper list was in the account-wide file
    -- (opts.whispers). It is dropped there, on or off, so names leave that
    -- file; each character starts with an empty list once.
    OnLoad = function(self)
        if type(self.opts) == "table" then self.opts.whispers = nil end
    end,

    OnEnable = function(self)
        CleanList()
        self:RegisterEvent("CHAT_MSG_WHISPER", OnWhisper)
        self:RegisterEvent("CHAT_MSG_WHISPER_INFORM", OnWhisper)
        self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
            TypeKeyDisarm("fight started")
            LiveRedraw(true)
        end)
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

-- "Move on screen": the prompt's backdrop can be nudged from its usual spot.
if PE.Move and PE.Move.Register then
    PE.Move:Register({
        key = PROMPT_KEY, label = "\"Press A to type\"", order = 20,
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
