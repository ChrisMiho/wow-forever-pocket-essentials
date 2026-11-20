-- Rules for "Chat picker" (Chat.lua), called "Chat from round button" before 0.9.0.
-- Sources: Chat.lua's header and comments; docs/DECISIONS.md, part "Chat" of
-- "Decisions made without the maintainer"; PRD.md goals 3 and 4.
-- Each test names its source in a comment. Fresh client and addon per test.
--
-- Differences from the task brief (the documents win): the picker also lists
-- "Yell" after "Say" (Chat.lua GatherTargets lines 261-262), which the brief
-- left out.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local function newChat(setup)
    return T.new({ on = { "chat" }, setup = setup })
end

local function panelOf(c) return rawget(c.env, "PocketEssentialsChatPanel") end

local function walk(c, w, fn, seen)
    seen = seen or {}
    if seen[w] then return end
    seen[w] = true
    fn(w)
    local st = c._state(w)
    for _, ch in ipairs(st.children) do walk(c, ch, fn, seen) end
    if st.scrollChild then walk(c, st.scrollChild, fn, seen) end
end

-- Visible buttons under a frame, in reading order (top to bottom, left to right).
local function visibleButtons(c, top)
    local out, pos = {}, {}
    walk(c, top, function(w)
        if c._state(w).type == "Button" and w:IsVisible() then
            out[#out + 1] = w
            local l, _, t = c._rect(w)
            pos[w] = { l or 0, t or 0 }
        end
    end)
    table.sort(out, function(a, b)
        if math.abs(pos[a][2] - pos[b][2]) > 0.5 then return pos[a][2] > pos[b][2] end
        return pos[a][1] < pos[b][1]
    end)
    return out
end

-- A tap on the round button.
local function tapHub(c, PE)
    c:click(PE.Hub.button)
    c:advance(0.2)
end

-- Opens the picker and returns { targets = {labels}, whispers = {labels}, buttons = {...} }.
local function readPicker(c)
    local panel = panelOf(c)
    check(panel and panel:IsShown(), "the chat window is not open")
    local out = { targets = {}, whispers = {}, kinds = {}, buttons = {} }
    for _, b in ipairs(visibleButtons(c, panel)) do
        out.buttons[#out.buttons + 1] = b
        if b.peChatTarget then
            out.targets[#out.targets + 1] = T.labelOf(b)
            out.kinds[#out.kinds + 1] = b.peChatTarget.chatType
        elseif b.peChatEntry then
            out.whispers[#out.whispers + 1] = T.labelOf(b)
        end
    end
    return out
end

local function openPicker(c, PE)
    tapHub(c, PE)
    return readPicker(c)
end

local function buttonLabelled(c, label)
    for _, b in ipairs(visibleButtons(c, panelOf(c))) do
        if T.labelOf(b) == label then return b end
    end
    error("no visible button labelled " .. label, 2)
end

-- The red number on the round button, or nil.
local function badge(c, PE)
    local hub = PE.Hub.button
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == "Hub.lua" and rec.parent == hub and rec.frame:IsVisible() then
            for _, r in ipairs(rec.regions) do
                local st = c._state(r)
                if st.type == "FontString" and st.text and st.text ~= "" then return st.text end
            end
        end
    end
    return nil
end

local function savedList(PE)
    local out = {}
    for i, e in ipairs(PE:GetModule("chat").opts.whispers) do
        out[i] = { name = e.name, unanswered = e.unanswered }
    end
    return out
end

---------------------------------------------------------------------------
-- Who can be talked to
---------------------------------------------------------------------------

-- Chat.lua GatherTargets lines 261-262: Say and Yell are always there.
test("chat: alone, not grouped, no guild, no channels: only Say and Yell are listed", function()
    local c, PE = newChat()
    local p = openPicker(c, PE)
    eq(p.targets, { "Say", "Yell" })
end)

-- DECISIONS "Chat": "Party shows when grouped"; Chat.lua line 263.
test("chat: Party is listed only when grouped", function()
    local c, PE = newChat(function(c) c.world.group = "party" end)
    eq(openPicker(c, PE).targets, { "Say", "Yell", "Party" })
end)

-- DECISIONS "Chat": "Raid when in a raid"; Chat.lua line 264 (a raid is also a group).
test("chat: Raid is listed only in a raid", function()
    local c, PE = newChat(function(c) c.world.group = "raid" end)
    eq(openPicker(c, PE).targets, { "Say", "Yell", "Party", "Raid" })
    local c2, PE2 = newChat(function(c) c.world.group = "party" end)
    local labels = openPicker(c2, PE2).targets
    for _, l in ipairs(labels) do check(l ~= "Raid", "Raid listed in a party") end
end)

-- Chat.lua line 265.
test("chat: Guild is listed only in a guild", function()
    local c, PE = newChat(function(c) c.world.guild = "Pocket Guild" end)
    eq(openPicker(c, PE).targets, { "Say", "Yell", "Guild" })
end)

-- Chat.lua GatherTargets lines 266-277: joined channels last, with their number; disabled ones left out.
test("chat: joined channels come after the others, numbered, and disabled ones are left out", function()
    local c, PE = newChat(function(c)
        c.world.group, c.world.guild = "raid", "Pocket Guild"
        c.world.channels = {
            { id = 1, name = "General - Elwynn Forest" },
            { id = 2, name = "Trade - City", disabled = true },
            { id = 4, name = "LookingForGroup" },
        }
    end)
    eq(openPicker(c, PE).targets,
        { "Say", "Yell", "Party", "Raid", "Guild", "1. General - Elwynn Forest", "4. LookingForGroup" })
end)

-- DECISIONS "Chat": "Instance and Officer chat are not in the picker."
test("chat: no Instance or Officer chat, even in an instance, a raid and a guild", function()
    local c, PE = newChat(function(c)
        c.world.group, c.world.guild, c.world.instance = "raid", "Pocket Guild", true
    end)
    local p = openPicker(c, PE)
    local allowed = { SAY = true, YELL = true, PARTY = true, RAID = true, GUILD = true, CHANNEL = true }
    for i, kind in ipairs(p.kinds) do
        check(allowed[kind], "unexpected chat type in the picker: " .. tostring(kind))
        check(not p.targets[i]:find("Instance") and not p.targets[i]:find("Officer"), "listed: " .. p.targets[i])
    end
    eq(p.targets, { "Say", "Yell", "Party", "Raid", "Guild" })
end)

---------------------------------------------------------------------------
-- Whisperers
---------------------------------------------------------------------------

-- DECISIONS "Chat" and Chat.lua line 54: newest first.
test("chat: whisperers are listed newest first", function()
    local c, PE = newChat()
    c:whisperIn("Ann", "hi")
    c:whisperIn("Bob", "hi")
    c:whisperIn("Cy", "hi")
    eq(openPicker(c, PE).whispers, { "Cy", "Bob", "Ann" })
    eq(savedList(PE), { { name = "Cy", unanswered = true }, { name = "Bob", unanswered = true },
        { name = "Ann", unanswered = true } })
end)

-- DECISIONS "Chat": "Six whisperers are remembered; a seventh pushes out the oldest."
test("chat: a seventh whisperer pushes out the oldest", function()
    local c, PE = newChat()
    for i = 1, 7 do c:whisperIn("W" .. i, "hi") end
    eq(openPicker(c, PE).whispers, { "W7", "W6", "W5", "W4", "W3", "W2" })
    eq(#PE:GetModule("chat").opts.whispers, 6)
    eq(badge(c, PE), "6", "the badge counts only the six that have buttons")
end)

-- Chat.lua Touch lines 127-140: "that person moves to the top of the list".
test("chat: a repeat whisperer moves to the front without being listed twice", function()
    local c, PE = newChat()
    c:whisperIn("W1", "hi")
    c:whisperIn("W2", "hi")
    c:whisperIn("W3", "hi")
    c:whisperIn("W1", "again")
    eq(openPicker(c, PE).whispers, { "W1", "W3", "W2" })
    eq(#PE:GetModule("chat").opts.whispers, 3)
    eq(badge(c, PE), "3")
end)

-- Chat.lua CleanName lines 146-157: the short form on our own realm; the full address is kept.
test("chat: a whisperer on our realm shows by short name, another realm by full name", function()
    local c, PE = newChat()
    c:whisperIn("Thrall-Camelot", "hi")
    c:whisperIn("Jaina-Otherrealm", "hi")
    eq(openPicker(c, PE).whispers, { "Jaina-Otherrealm", "Thrall" })
    c:whisperOut("Thrall-Camelot", "hello")  -- our reply is matched to the same person
    eq(#PE:GetModule("chat").opts.whispers, 2)
end)

---------------------------------------------------------------------------
-- The badge and "Clear marks"
---------------------------------------------------------------------------

-- Chat.lua UpdateBadge; Hub:SetBadge: "1" on an incoming whisper.
test("chat: an incoming whisper puts its count on the round button", function()
    local c, PE = newChat()
    eq(badge(c, PE), nil, "no badge before any whisper")
    c:whisperIn("Ann", "hi")
    eq(badge(c, PE), "1")
    c:whisperIn("Bob", "hi")
    eq(badge(c, PE), "2")
end)

-- Chat.lua Touch: "not incoming: we whispered them (that answers them)".
test("chat: replying to a person clears that person's mark and the badge", function()
    local c, PE = newChat()
    c:whisperIn("Ann", "hi")
    c:whisperIn("Bob", "hi")
    c:whisperOut("Ann", "on my way")
    eq(badge(c, PE), "1")
    eq(savedList(PE), { { name = "Ann", unanswered = false }, { name = "Bob", unanswered = true } })
    c:whisperOut("Bob", "hello")
    eq(badge(c, PE), nil)
end)

-- DECISIONS "Chat": 'A "Clear marks" button was added so the unanswered badge cannot get stuck.'
test("chat: Clear marks clears every mark and the badge, and keeps the whisperers", function()
    local c, PE = newChat()
    c:whisperIn("Ann", "hi")
    c:whisperIn("Bob", "hi")
    local p = openPicker(c, PE)
    eq(p.whispers, { "Bob", "Ann" })
    eq(badge(c, PE), "2")
    c:click(buttonLabelled(c, "Clear marks"))
    c:advance(0.2)
    eq(badge(c, PE), nil)
    eq(savedList(PE), { { name = "Bob", unanswered = false }, { name = "Ann", unanswered = false } })
    eq(readPicker(c).whispers, { "Bob", "Ann" })
    -- Spec 0.9.0 "Chat window": Clear marks is always the last chip while names are listed.
    check(buttonLabelled(c, "Clear marks"), "Clear marks went away while names are listed")
end)

-- DECISIONS "Chat": "A whisper arriving while the picker is open updates the badge only".
test("chat: a whisper arriving while the picker is open changes the badge but not the buttons until reopened", function()
    local c, PE = newChat()
    c:whisperIn("Ann", "hi")
    local p = openPicker(c, PE)
    eq(p.whispers, { "Ann" })
    eq(badge(c, PE), "1")
    c:whisperIn("Bob", "hi")
    c:advance(0.5)
    eq(badge(c, PE), "2", "the badge changed")
    eq(readPicker(c).whispers, { "Ann" }, "the buttons did not")
    tapHub(c, PE)   -- closes it
    check(not panelOf(c):IsShown(), "the second tap should close the window")
    tapHub(c, PE)   -- reopens it
    eq(readPicker(c).whispers, { "Bob", "Ann" })
end)

---------------------------------------------------------------------------
-- Chat lockdown and the feature switch
---------------------------------------------------------------------------

-- Chat.lua lines 25-32 and OnWhisper line 162: "while ... InChatMessagingLockdown() is true nothing is tracked".
test("chat: during chat lockdown nothing is recorded and nothing errors", function()
    local c, PE = newChat()
    c.world.chatLockdown = true
    c:whisperIn("Ann", "hi")
    c:whisperOut("Bob", "hello")
    c:advance(0.5)
    eq(PE:GetModule("chat").opts.whispers, {})
    eq(badge(c, PE), nil)
    c:assertClean("lockdown")
    -- and it records again once the lockdown ends
    c.world.chatLockdown = false
    c:whisperIn("Cy", "hi")
    eq(savedList(PE), { { name = "Cy", unanswered = true } })
end)

-- Chat.lua header: "only while the feature is on"; PRD goal 3 (nothing runs while a feature is off).
test("chat: with the feature off, whispers are not recorded and no whisper event is registered", function()
    local c, PE = T.new({})
    c:whisperIn("Ann", "hi")
    eq(PE:GetModule("chat").opts.whispers, {})
    eq(badge(c, PE), nil)
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile then
            check(not rec.events.CHAT_MSG_WHISPER and not rec.events.CHAT_MSG_WHISPER_INFORM,
                rec.addonFile .. " listens for whispers with chat off")
        end
    end
end)

---------------------------------------------------------------------------
-- A tap on a target
---------------------------------------------------------------------------

-- The chat calls, in order, as (name, arguments).
local function chatCalls(c)
    local out = {}
    for _, call in ipairs(c.calls) do
        if call.name:find("^ChatFrame") then out[#out + 1] = call end
    end
    return out
end

-- Chat.lua TargetClicked: with the Gamepad UI on, the game refuses the chat box's controller focus
-- to addons during a fight (Blizzard_GamepadSharedUtility/FrameControlsManager.lua FrameShown), so
-- a tap in combat opens nothing and says why.
test("chat: a tap during a fight does not open the chat box, and says so", function()
    local c, PE = newChat()
    openPicker(c, PE)
    c:enterCombat()
    c:click(buttonLabelled(c, "Say"))
    c:advance(0.2)
    eq(#chatCalls(c), 0, "the chat box was touched in combat")
    local said = false
    for _, line in ipairs(T.chatLines(c)) do
        if line:find("Not during a fight", 1, true) then said = true end
    end
    check(said, "no chat line explains why nothing opened")
    c:leaveCombat()
end)

-- Chat.lua TargetClicked, Core.lua PE:CombatRestricted. 0.0.7 on the device: the block came with
-- no fight going by InCombatLockdown. Blizzard's check is the "Combat" addon restriction
-- (Blizzard_GamepadSmartNavigation/SecureHelper.lua IsSecureOrOutOfCombatRestriction).
test("chat: a tap while the game's combat restriction is active opens nothing, even with no lockdown", function()
    local c, PE = newChat()
    openPicker(c, PE)
    c.world.combatRestricted = true
    c:click(buttonLabelled(c, "Say"))
    c:advance(0.2)
    eq(#chatCalls(c), 0, "the chat box was touched under the combat restriction")
    c.world.combatRestricted = false
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Say"))
    c:advance(0.2)
    check(#chatCalls(c) > 0, "the chat box did not open once the restriction was over")
end)

-- Chat.lua OpenChatTo, Gamepad UI on. Pocket Probe on the device (docs/errorLogs/PocketProbe.lua,
-- 2026-11-17): an addon opening the chat box is blocked in Blizzard's controller code and the game
-- then forbids its own controller actions until a reload; setting the chat type on the closed box
-- is allowed. So the tap sets the type and never calls OpenChat.
test("chat: with the Gamepad UI on, a tap sets the chat type and never opens the chat box", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Say"))
    c:advance(0.2)
    local names = {}
    for _, call in ipairs(chatCalls(c)) do names[#names + 1] = call.name end
    eq(names, { "ChatFrame1EditBox:SetChatType" })
    eq(chatCalls(c)[1].args[1], "SAY")
    local said = false
    for _, line in ipairs(T.chatLines(c)) do
        if line:find("Chat is set to Say. Press A to type.", 1, true) then said = true end
    end
    check(said, "no chat line tells the player how to open chat: " .. table.concat(T.chatLines(c), " / "))
end)

-- Chat.lua TypeKeyArm / TypeKeyDisarm: the A button is lent to the game's own OPENCHAT binding
-- (an addon may not open the chat box; the game's binding may), and given back when chat opens.
test("chat: with the Gamepad UI on, the A button is lent to the game's open-chat binding and given back", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    local owner = rawget(c.env, "PocketEssentialsChatKeyOwner")
    local function bound() local b = c._state(owner).bindings return b and b.PAD1 or nil end
    eq(bound(), nil, "before any tap")
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Say"))
    eq(bound(), "command:OPENCHAT")
    c.env.ChatFrameUtil.OpenChat(nil) -- the player's press runs the game's binding
    eq(bound(), nil, "after chat opened")
    c.closeChat()
    -- and by itself when the time is up
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Say"))
    eq(bound(), "command:OPENCHAT")
    c:advance(13)
    eq(bound(), nil, "after 12 seconds")
    -- and when a fight starts
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Say"))
    c:enterCombat()
    eq(bound(), nil, "when a fight starts")
    c:leaveCombat()
    eq(#c:problems(), 0, table.concat(c:problems(), " / "))
end)

-- Chat.lua TypeKeyArm / TypeKeyDisarm: the on-screen "Press A to type" prompt is tied to the lending.
local function promptLines(c)
    local lines, frame = {}, nil
    for _, ch in ipairs(c._state(c.env.UIParent).children) do
        local shown = false
        for _, r in ipairs(c._state(ch).regions) do
            local t = c._state(r).type == "FontString" and r:GetText()
            if t == "Press A to type" then shown = true end
        end
        if shown then
            frame = ch
            for _, r in ipairs(c._state(ch).regions) do
                if c._state(r).type == "FontString" then lines[#lines + 1] = r:GetText() end
            end
        end
    end
    return frame, lines
end
local function promptShown(c)
    local f = promptLines(c)
    return f ~= nil and f:IsShown()
end
local function tapLabel(c, PE, label)
    openPicker(c, PE)
    c:click(buttonLabelled(c, label))
end

test("chat: prompt: with the Gamepad UI on, a tap shows 'Press A to type' naming the target", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    check(not promptShown(c), "shown before any tap")
    tapLabel(c, PE, "Say")
    check(promptShown(c), "not shown after a tap")
    local f, lines = promptLines(c)
    eq(lines, { "Press A to type", "Chat is set to Say" })
    eq(c._state(f).mouse, false)
    eq(c._state(f).strata, "HIGH")
    eq(#c:problems(), 0, table.concat(c:problems(), " / "))
end)

test("chat: prompt: a whisper prompt says 'your whisper', never the name", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    c:fire("CHAT_MSG_WHISPER", "hello", "Bobby-Realm", "", "", "Bobby-Realm", "", 0, 0, "", 0, 1, "guid")
    openPicker(c, PE)
    local btn
    for _, b in ipairs(visibleButtons(c, panelOf(c))) do
        if b.peChatEntry then btn = b break end
    end
    check(btn, "no whisper button")
    c:click(btn)
    local _, lines = promptLines(c)
    eq(lines[2], "Chat is set to your whisper")
end)

test("chat: prompt: no prompt when the A button could not be lent (in a fight)", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    openPicker(c, PE)
    c:enterCombat()
    c:click(buttonLabelled(c, "Say"))
    check(not promptShown(c), "shown although the button was not lent")
    c:leaveCombat()
end)

test("chat: prompt: hidden when chat opens, after 12 seconds, when a fight starts, and on switch-off", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    tapLabel(c, PE, "Say")
    check(promptShown(c))
    c.env.ChatFrameUtil.OpenChat(nil)
    check(not promptShown(c), "still shown after chat opened")
    c.closeChat()
    tapLabel(c, PE, "Say")
    check(promptShown(c))
    c:advance(13)
    check(not promptShown(c), "still shown after 12 seconds")
    tapLabel(c, PE, "Say")
    check(promptShown(c))
    c:enterCombat()
    check(not promptShown(c), "still shown when a fight started")
    c:leaveCombat()
    tapLabel(c, PE, "Say")
    check(promptShown(c))
    PE:SetModuleEnabled("chat", false)
    check(not promptShown(c), "still shown after switch-off")
    eq(#c:problems(), 0, table.concat(c:problems(), " / "))
end)

test("chat: prompt: a second tap replaces the text and restarts the 12 seconds", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    tapLabel(c, PE, "Say")
    c:advance(8)
    tapLabel(c, PE, "Yell")
    local _, lines = promptLines(c)
    eq(lines[2], "Chat is set to Yell")
    c:advance(8) -- 16 s after the first tap, 8 after the second
    check(promptShown(c), "hidden by the first tap's timer")
    c:advance(5)
    check(not promptShown(c), "still shown 13 s after the second tap")
end)

test("chat: prompt: with the Gamepad UI off, a tap shows no prompt", function()
    local c = T.new({ on = { "chat" }, gamepadUI = false })
    local PE = c.PE
    tapLabel(c, PE, "Say")
    check(not promptShown(c), "prompt shown with the Gamepad UI off")
    eq(#c:problems(), 0, table.concat(c:problems(), " / "))
end)

test("chat: prompt: its parent is UIParent", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    tapLabel(c, PE, "Say")
    local f = promptLines(c)
    check(f ~= nil, "no prompt frame")
    check(f:GetParent() == c.env.UIParent, "parent is not UIParent")
end)

test("chat: prompt: no frame made by Chat.lua has an OnUpdate script", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    local owner = rawget(c.env, "PocketEssentialsChatKeyOwner")
    tapLabel(c, PE, "Say")
    local f = promptLines(c)
    check(f ~= nil, "no prompt frame")
    check(f:GetScript("OnUpdate") == nil, "prompt has OnUpdate while up")
    check(owner:GetScript("OnUpdate") == nil, "key owner has OnUpdate while up")
    c:advance(13)
    check(not promptShown(c), "prompt still up")
    check(f:GetScript("OnUpdate") == nil, "prompt has OnUpdate after hiding")
    check(owner:GetScript("OnUpdate") == nil, "key owner has OnUpdate after hiding")
end)

-- Bindings cannot be changed in a fight: the type is set, the button is not lent.
test("chat: with the Gamepad UI on, a tap during a fight lends no button and says to open chat", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    local owner = rawget(c.env, "PocketEssentialsChatKeyOwner")
    openPicker(c, PE)
    c:enterCombat()
    c:click(buttonLabelled(c, "Say"))
    eq(c._state(owner).bindings, nil)
    local said = false
    for _, line in ipairs(T.chatLines(c)) do
        if line:find("Open chat to type your message.", 1, true) then said = true end
    end
    check(said, "no chat line: " .. table.concat(T.chatLines(c), " / "))
    eq(#c:problems(), 0, table.concat(c:problems(), " / "))
    c:leaveCombat()
end)

-- Same rule: nothing is opened, so a tap is fine during a fight too.
test("chat: with the Gamepad UI on, a tap during a fight still sets the chat type", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    openPicker(c, PE)
    c:enterCombat()
    c:click(buttonLabelled(c, "Say"))
    c:advance(0.2)
    eq(#chatCalls(c), 1)
    eq(chatCalls(c)[1].name, "ChatFrame1EditBox:SetChatType")
    c:leaveCombat()
end)

-- Chat.lua OpenChatTo: choose the box, open it with OpenChat(nil, frame), then set the
-- type and call UpdateHeader; nothing typed into the box.
test("chat: tapping Say opens the chat box set to Say", function()
    local c, PE = newChat()
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Say"))
    c:advance(0.2)
    local calls = chatCalls(c)
    eq({ calls[1].name, calls[2].name, calls[3].name },
        { "ChatFrameUtil.OpenChat", "ChatFrame1EditBox:SetChatType", "ChatFrame1EditBox:UpdateHeader" })
    eq(#calls, 3)
    eq(calls[1].args[1], nil, "no text is pushed into the box")
    check(calls[1].args[2] == c.chatFrame, "the box is opened on the main chat frame")
    eq(calls[2].args[1], "SAY")
    eq(c.chatBox.chatType, "SAY")
    check(c.editBox:IsShown(), "the chat box is not open")
    check(not panelOf(c):IsShown(), "the picker did not close after a tap")
end)

test("chat: tapping Party opens the chat box set to Party", function()
    local c, PE = newChat(function(c) c.world.group = "party" end)
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Party"))
    eq(c.chatBox.chatType, "PARTY")
    eq(#c:callsTo("ChatFrame1EditBox:SetChatType"), 1)
    eq(c:callsTo("ChatFrame1EditBox:SetChatType")[1].args[1], "PARTY")
end)

test("chat: tapping a channel opens the chat box set to that channel number", function()
    local c, PE = newChat(function(c) c.world.channels = { { id = 1, name = "General - Elwynn Forest" } } end)
    openPicker(c, PE)
    c:click(buttonLabelled(c, "1. General - Elwynn Forest"))
    local target = c:callsTo("ChatFrame1EditBox:SetChannelTarget")
    eq(#target, 1)
    eq(target[1].args[1], 1)
    eq(c:callsTo("ChatFrame1EditBox:SetChatType")[1].args[1], "CHANNEL")
    eq(c.chatBox.channelTarget, 1)
end)

-- Chat.lua TargetClicked: a whisper button addresses the sender exactly as the game delivered it.
test("chat: tapping a whisperer opens the chat box set to a whisper to that person's full name", function()
    local c, PE = newChat()
    c:whisperIn("Thrall-Camelot", "hello")
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Thrall"))
    local tell = c:callsTo("ChatFrame1EditBox:SetTellTarget")
    eq(#tell, 1)
    eq(tell[1].args[1], "Thrall-Camelot")
    eq(c:callsTo("ChatFrame1EditBox:SetChatType")[1].args[1], "WHISPER")
    eq(c.chatBox.tellTarget, "Thrall-Camelot")
    eq(c.chatBox.chatType, "WHISPER")
    check(not panelOf(c):IsShown(), "the picker did not close after a tap")
end)


---------------------------------------------------------------------------
-- After a reload, Battle.net, self
---------------------------------------------------------------------------

-- Chat.lua OnEnable line 594 (UpdateBadge) and CleanList lines 76-92.
test("chat: saved unanswered whispers show the badge when chat is enabled at login", function()
    local saved = { version = 1, enabled = { chat = true }, ui = { size = "medium", hubPos = "LEFT" }, errors = {},
        options = { chat = { whispers = {
            { name = "Ann", target = "Ann", unanswered = true, time = 1 },
            { name = "Bob", target = "Bob", unanswered = false, time = 2 },
            { name = "Cy", target = "Cy-Realm", unanswered = true, time = 3 },
        } } } }
    local c, PE = T.new({ saved = saved })
    eq(badge(c, PE), "2")
    eq(openPicker(c, PE).whispers, { "Ann", "Bob", "Cy" })
end)

test("chat: a saved list longer than six, with Battle.net or damaged entries, is cleaned at login", function()
    local list = { { name = "A1", target = "A1", unanswered = true, time = 1 }, { bn = true, name = "BN", unanswered = true },
        { name = "", unanswered = true }, "junk" }
    for i = 2, 8 do list[#list + 1] = { name = "A" .. i, target = "A" .. i, unanswered = true, time = i } end
    local saved = { version = 1, enabled = { chat = true }, ui = { size = "medium", hubPos = "LEFT" }, errors = {},
        options = { chat = { whispers = list } } }
    local c, PE = T.new({ saved = saved })
    eq(openPicker(c, PE).whispers, { "A1", "A2", "A3", "A4", "A5", "A6" })
    eq(badge(c, PE), "6")
end)

-- DECISIONS "What was left out": "Battle.net whispers ... Only ordinary character whispers are listed";
-- Chat.lua header: only the two character-whisper events are used. (The stand-in has no
-- CHAT_MSG_BN_WHISPER event to fire, so what is checked is that nothing listens for one.)
test("chat: only the two character-whisper events are listened for (no Battle.net whisper events)", function()
    local c, PE = newChat()
    local listened = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile then
            for e in pairs(rec.events) do
                if e:find("WHISPER") or e:find("BN_") then listened[e] = true end
            end
        end
    end
    eq(listened, { CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true })
end)

-- The debug log's lines for one feature, without the time and the feature's name.
local function debugLines(c, key)
    local out = {}
    local prefix = " " .. key .. ": "
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        local at = line:find(prefix, 1, true)
        if at and at <= 14 then out[#out + 1] = line:sub(at + #prefix) end
    end
    return out
end

-- Spec 2026-11-17-debug-log, "Rules for every line": no names of players and no chat text; a
-- whisper target is written as "whisper".
test("debug log: a whisper and a tap on its button are written without the name or the text", function()
    local c, PE = newChat()
    PE:SetDebug(true)
    c:whisperIn("Zugzug-Camelot", "meet me at the bank")
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Zugzug"))
    c:advance(0.2)
    local lines = debugLines(c, "chat")
    local noted, tapped = false, false
    for _, line in ipairs(lines) do
        if line == "whisper noted (incoming)" then noted = true end
        if line == "tapped: whisper" then tapped = true end
    end
    check(noted and tapped, "missing whisper lines: " .. table.concat(lines, " / "))
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        check(not line:lower():find("zugzug", 1, true), "a player's name is in the log: " .. line)
        check(not line:find("bank", 1, true), "chat text is in the log: " .. line)
    end
end)

-- Spec 2026-11-17-debug-log, row "Chat buttons": picker opened, the kind of target tapped, chat
-- box opened or not.
test("debug log: opening the picker and tapping Say writes the counts, the kind and the result", function()
    local c, PE = newChat()
    PE:SetDebug(true)
    openPicker(c, PE)
    c:click(buttonLabelled(c, "Say"))
    c:advance(0.2)
    eq(debugLines(c, "chat"), {
        "picker opened",
        "picker drawn: 2 targets, 0 whisper entries, 0 marked",
        "tapped: SAY",
        "chat box opened",
    })
end)


---------------------------------------------------------------------------
-- Spec 2026-11-17-post-0.0.9-batch, section 3: "Chat text size" (Chat.lua, Settings.lua).
---------------------------------------------------------------------------

local function settingsOf(c) return rawget(c.env, "PocketEssentialsSettingsPanel") end

-- Opens the settings window on its Chat tab and returns a button with that label (any, shown or scrolled away).
local function settingsButton(c, PE, label)
    PE:OpenSettings("chat")
    c:advance(0.2)
    local found
    walk(c, settingsOf(c), function(w)
        if not found and c._state(w).type == "Button" and T.labelOf(w) == label then found = w end
    end)
    return found
end

-- Every text drawn in the settings window.
local function settingsTexts(c)
    local out = {}
    walk(c, settingsOf(c), function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and st.text and st.text ~= "" then out[#out + 1] = st.text end
        end
    end)
    return out
end

local function hasText(c, text)
    for _, t in ipairs(settingsTexts(c)) do if t == text then return true end end
    return false
end

local function sizeCalls(c)
    local out = {}
    for _, call in ipairs(c.calls) do
        if call.name == "SetChatWindowSize" then out[#out + 1] = call.args[1] .. "=" .. call.args[2] end
    end
    return out
end

local function setAllTo(c, size)
    for _, f in ipairs(c.chatWindows) do f:SetFont("Fonts\\ARIALN.TTF", size, "") end
end

local function mainSize(c) return (select(2, c.chatFrame:GetFont())) end

-- A shown settings button with that label, without opening or redrawing anything.
local function shownButton(c, label)
    local found
    walk(c, settingsOf(c), function(w)
        local st = c._state(w)
        if not found and st.type == "Button" and st.shown and T.labelOf(w) == label then found = w end
    end)
    return found
end

-- The stepper's number: the one shown text that sits between "-" and
-- "+" on their line (spec 2026-11-17-0.4.0, Rulings). nil when there is none.
local function stepperText(c)
    local smaller, bigger = shownButton(c, "-"), shownButton(c, "+")
    if not (smaller and bigger) then return nil end
    local _, sr, st, sb = c._rect(smaller)
    local bl = c._rect(bigger)
    local found, count = nil, 0
    walk(c, settingsOf(c), function(w)
        for _, r in ipairs(c._state(w).regions) do
            local rs = c._state(r)
            if rs.type == "FontString" and rs.shown and rs.text and rs.text ~= "" and rs.text ~= "text size" then
                local l, rr, t = c._rect(r)
                if l and rr and t and l >= sr - 0.01 and rr <= bl + 0.01 and t <= st + 0.01 and t >= sb - 0.01 then
                    found, count = rs.text, count + 1
                end
            end
        end
    end)
    if count ~= 1 then return nil end
    return found
end

-- Spec 3 "Behaviour": each tap moves one step and every chat window gets the same size.
test("chat size: Bigger moves one step and all ten chat windows follow", function()
    local c, PE = newChat()
    c:click(settingsButton(c, PE, "+"))
    c:advance(0.5)
    for i, f in ipairs(c.chatWindows) do eq(select(2, f:GetFont()), 20, "window " .. i) end
    eq(c.chatSizes[1], 20)
    eq(c.chatSizes[10], 20)
    eq(#sizeCalls(c), 10)
    eq(stepperText(c), "20", "the row does not show the new size: " .. table.concat(settingsTexts(c), " | "))
end)

test("chat size: Smaller moves one step down", function()
    local c, PE = newChat()
    c:click(settingsButton(c, PE, "-"))
    eq(mainSize(c), 16)
    eq(c.chatSizes[3], 16)
end)

-- Spec 3: the list goes on from 27 to 30 and 34, and at either end the button does nothing more.
test("chat size: the steps run 12 14 16 18 20 24 27 30 34 and stop at both ends", function()
    local c, PE = newChat()
    local seen = { mainSize(c) }
    for _ = 1, 10 do
        c:click(settingsButton(c, PE, "+"))
        seen[#seen + 1] = mainSize(c)
    end
    eq(seen, { 18, 20, 24, 27, 30, 34, 34, 34, 34, 34, 34 })
    local before = #sizeCalls(c)
    c:click(settingsButton(c, PE, "+"))
    eq(#sizeCalls(c), before, "a tap at the top still called the game")
    seen = {}
    for _ = 1, 10 do
        c:click(settingsButton(c, PE, "-"))
        seen[#seen + 1] = mainSize(c)
    end
    eq(seen, { 30, 27, 24, 20, 18, 16, 14, 12, 12, 12 })
end)

-- Spec 3: a size that is not on the list moves to the next listed size in the tapped direction.
test("chat size: a size between steps moves to the next listed size in the tapped direction", function()
    local cases = {
        { 19, "+", 20 }, { 19, "-", 18 }, { 13, "-", 12 }, { 13, "+", 14 },
        { 11, "+", 12 }, { 40, "-", 34 }, { 28.4, "+", 30 }, { 17.6, "-", 16 },
    }
    for _, case in ipairs(cases) do
        local c, PE = newChat()
        setAllTo(c, case[1])
        c:click(settingsButton(c, PE, case[2]))
        eq(mainSize(c), case[3], case[1] .. " " .. case[2])
    end
end)

-- Spec 3: below the first and above the last step nothing is done.
test("chat size: a size beyond the list in the tapped direction does nothing", function()
    for _, case in ipairs({ { 35, "+" }, { 11, "-" } }) do
        local c, PE = newChat()
        setAllTo(c, case[1])
        c:click(settingsButton(c, PE, case[2]))
        eq(#sizeCalls(c), 0, case[1] .. " " .. case[2])
        eq(mainSize(c), case[1])
    end
end)

-- Spec 3 "How": applied only out of a fight.
test("chat size: a tap in a fight is held until the fight ends", function()
    local c, PE = newChat()
    PE:SetDebug(true)
    local bigger = settingsButton(c, PE, "+")
    c:enterCombat()
    c:click(bigger)
    eq(#sizeCalls(c), 0, "the game was called during the fight")
    eq(mainSize(c), 18)
    c:leaveCombat()
    c:advance(0.5)
    eq(mainSize(c), 20)
    eq(#sizeCalls(c), 10)
    local lines = debugLines(c, "chat")
    local held = false
    for _, l in ipairs(lines) do if l == "text size change held for after the fight" then held = true end end
    check(held, "no held line: " .. table.concat(lines, " / "))
end)

test("chat size: two taps in one fight are two steps once it ends", function()
    local c, PE = newChat()
    local bigger = settingsButton(c, PE, "+")
    c:enterCombat()
    c:click(bigger)
    c:click(bigger)
    eq(mainSize(c), 18, "changed during the fight")
    c:leaveCombat()
    c:advance(0.5)
    eq(mainSize(c), 24)
end)

test("chat size: a bigger and a smaller tap in one fight cancel out", function()
    local c, PE = newChat()
    local bigger = settingsButton(c, PE, "+")
    local smaller = settingsButton(c, PE, "-")
    c:enterCombat()
    c:click(bigger)
    c:click(smaller)
    c:leaveCombat()
    c:advance(0.5)
    eq(mainSize(c), 18)
end)

test("chat size: in a fight the value text shows the size that is waiting; afterwards just the size", function()
    local c, PE = newChat()
    local bigger = settingsButton(c, PE, "+")
    check(hasText(c, "Chat text size"))
    eq(stepperText(c), "18")
    c:enterCombat()
    c:click(bigger)
    c:advance(0.5)
    check(hasText(c, "Chat text size: 20 (after the fight)"), table.concat(settingsTexts(c), " | "))
    c:click(bigger)
    c:advance(0.5)
    check(hasText(c, "Chat text size: 24 (after the fight)"), table.concat(settingsTexts(c), " | "))
    c:leaveCombat()
    c:advance(0.5)
    check(hasText(c, "Chat text size"), table.concat(settingsTexts(c), " | "))
    check(not hasText(c, "Chat text size: 24 (after the fight)"), "the waiting note stayed")
    eq(stepperText(c), "24")
end)

test("chat size: taps in a fight stop at the end of the list", function()
    local c, PE = newChat()
    setAllTo(c, 30)
    local bigger = settingsButton(c, PE, "+")
    c:enterCombat()
    c:click(bigger)
    c:click(bigger)
    c:click(bigger)
    c:leaveCombat()
    c:advance(0.5)
    eq(mainSize(c), 34)
end)

-- Spec 3 "Debug log".
test("chat size: the debug log has one line for the change, without a player's name", function()
    local c, PE = newChat()
    PE:SetDebug(true)
    c:click(settingsButton(c, PE, "+"))
    eq(debugLines(c, "chat"), { "text size 18 -> 20 (10 windows)" })
end)

test("chat size: a tap at the end writes a line and calls nothing", function()
    local c, PE = newChat()
    PE:SetDebug(true)
    setAllTo(c, 34)
    c:click(settingsButton(c, PE, "+"))
    eq(debugLines(c, "chat"), { "text size 34: already the biggest" })
    eq(#sizeCalls(c), 0)
end)

-- Spec 3: "The addon stores nothing" and "With no tap, nothing is changed".
test("chat size: nothing is called or saved until a button is tapped", function()
    local c, PE = newChat()
    settingsButton(c, PE, "+")
    eq(#sizeCalls(c), 0)
    local saved = rawget(c.env, "PocketEssentialsDB").options.chat
    eq(saved.whispers, {})
    -- The window size (spec 0.9.0, key scale) is the picker's own setting, not the text size.
    local keys = 0
    for key in pairs(saved) do if key ~= "scale" then keys = keys + 1 end end
    eq(keys, 1, "the chat feature saved something besides its whisper list")
end)

-- Spec 3 "Rules": the edit box is never touched; the game's own size list is not written to.
test("chat size: the edit box is not touched and the game's own size list stays as it is", function()
    local c, PE = newChat()
    c:click(settingsButton(c, PE, "+"))
    for _, call in ipairs(c.calls) do
        check(not tostring(call.name):find("EditBox", 1, true) and not tostring(call.name):find("OpenChat", 1, true),
            "touched the chat box: " .. tostring(call.name))
    end
    eq(rawget(c.env, "CHAT_FONT_HEIGHTS"), { 12, 14, 16, 18, 20, 24, 27 })
    c:assertClean("chat size")
end)

-- Review of 0.4.0, point 5: at either end the button that can go no further is dimmed (the
-- kit's "disabled" look, which can still be pressed and does nothing).
test("chat size: at the smallest and the biggest size the end button is dimmed and a press does nothing", function()
    local function styles(c, PE)
        return { settingsButton(c, PE, "-").peStyle, shownButton(c, "+").peStyle }
    end
    local c, PE = newChat()
    eq(styles(c, PE), { "step", "step" }, "in the middle")
    setAllTo(c, 34)
    PE:RefreshSettings()
    c:advance(0.1)
    eq(styles(c, PE), { "step", "stepDim" }, "at the biggest")
    c:click(shownButton(c, "+"))
    c:advance(0.1)
    eq(#sizeCalls(c), 0, "a press on the dimmed Bigger called the game")
    eq(mainSize(c), 34)
    eq(styles(c, PE), { "step", "stepDim" }, "after the press")
    -- one step down and Bigger is a plain button again
    c:click(shownButton(c, "-"))
    c:advance(0.1)
    eq(mainSize(c), 30)
    eq(styles(c, PE), { "step", "step" }, "one step below the biggest")
    setAllTo(c, 12)
    PE:RefreshSettings()
    c:advance(0.1)
    eq(styles(c, PE), { "stepDim", "step" }, "at the smallest")
    local before = #sizeCalls(c)
    c:click(shownButton(c, "-"))
    c:advance(0.1)
    eq(#sizeCalls(c), before, "a press on the dimmed Smaller called the game")
    eq(mainSize(c), 12)
    -- beyond the list the same holds
    setAllTo(c, 40)
    PE:RefreshSettings()
    c:advance(0.1)
    eq(styles(c, PE), { "step", "stepDim" }, "above the biggest")
    c:assertClean("dimmed ends")
end)

-- The step waiting for the end of a fight counts: the last step taken in a fight dims the button.
test("chat size: in a fight the end button dims as soon as the waiting size is the last one", function()
    local c, PE = newChat()
    setAllTo(c, 30)
    local bigger = settingsButton(c, PE, "+")
    eq(bigger.peStyle, "step")
    c:enterCombat()
    c:click(bigger)
    c:advance(0.1)
    eq(shownButton(c, "+").peStyle, "stepDim", "34 is waiting, Bigger is not dimmed")
    eq(shownButton(c, "-").peStyle, "step")
    c:leaveCombat()
    c:advance(0.1)
    eq(mainSize(c), 34)
    eq(shownButton(c, "+").peStyle, "stepDim")
end)

-- Spec 0.4.0 Rulings: one stepper, "Chat text size", then Smaller, the size, Bigger.
test("chat size: the row in the chat block shows the label, Smaller, the size and Bigger, in that order", function()
    local c, PE = newChat()
    check(settingsButton(c, PE, "-") and settingsButton(c, PE, "+"), "buttons missing")
    check(hasText(c, "Chat text size"), "no label: " .. table.concat(settingsTexts(c), " | "))
    eq(stepperText(c), "18", "no number between the buttons: " .. table.concat(settingsTexts(c), " | "))
    local sl, sr, st = c._rect(shownButton(c, "-"))
    local bl, _, bt = c._rect(shownButton(c, "+"))
    check(sl < sr and sr < bl, "Smaller is not left of Bigger")
    check(math.abs(st - bt) < 0.01, "the two buttons are not on one line")
end)

-- Rulings: "not a button per size".
test("chat size: there is no button per size, only Smaller and Bigger", function()
    local c, PE = newChat()
    for _, n in ipairs({ 12, 14, 16, 18, 20, 24, 27, 30, 34 }) do
        check(not settingsButton(c, PE, tostring(n)), "a button labelled " .. n)
    end
end)

-- Rulings: one press moves one step through the whole list, both ways, and the number follows.
test("chat size: the number steps through the full list both ways and stops at the ends", function()
    local c, PE = newChat()
    setAllTo(c, 12)
    PE:OpenSettings("chat")
    c:advance(0.2)
    local seen = { stepperText(c) }
    for _ = 1, 10 do
        c:click(shownButton(c, "+"))
        c:advance(0.2)
        seen[#seen + 1] = stepperText(c)
    end
    eq(seen, { "12", "14", "16", "18", "20", "24", "27", "30", "34", "34", "34" })
    eq(#sizeCalls(c), 80, "a tap at the top still called the game")
    seen = {}
    for _ = 1, 10 do
        c:click(shownButton(c, "-"))
        c:advance(0.2)
        seen[#seen + 1] = stepperText(c)
    end
    eq(seen, { "30", "27", "24", "20", "18", "16", "14", "12", "12", "12" })
    eq(#sizeCalls(c), 160, "a tap at the bottom still called the game")
    c:assertClean("chat size stepper")
end)

-- Rulings: "The number shown is the size the game is using, read from the game."
test("chat size: the number is read from the game, not from anything the addon keeps", function()
    local c, PE = newChat()
    c:click(settingsButton(c, PE, "+"))
    c:advance(0.2)
    eq(stepperText(c), "20")
    local before = #sizeCalls(c)
    setAllTo(c, 14) -- the game's own tab menu, behind the addon's back
    PE:CloseSettings()
    PE:OpenSettings("chat")
    c:advance(0.2)
    eq(stepperText(c), "14")
    eq(#sizeCalls(c), before, "drawing the row called the game")
end)

-- Rulings: a size that is not in the list is shown as it is and steps to its neighbour.
test("chat size: a size that is not in the list is shown, and one press goes to the neighbour that way", function()
    for _, case in ipairs({ { 19, "+", "20" }, { 19, "-", "18" }, { 22, "+", "24" }, { 40, "-", "34" } }) do
        local c, PE = newChat()
        setAllTo(c, case[1])
        PE:OpenSettings("chat")
        c:advance(0.2)
        eq(stepperText(c), tostring(case[1]))
        c:click(shownButton(c, case[2]))
        c:advance(0.2)
        eq(stepperText(c), case[3], case[1] .. " " .. case[2])
        eq(mainSize(c), tonumber(case[3]))
    end
end)

-- Spec 1 rule 6 and the Rulings: in a fight the number stays the game's size; the label has the waiting size.
test("chat size: in a fight the number stays the game's size until the change is applied", function()
    local c, PE = newChat()
    local bigger = settingsButton(c, PE, "+")
    c:enterCombat()
    c:click(bigger)
    c:advance(0.2)
    eq(stepperText(c), "18")
    check(hasText(c, "Chat text size: 20 (after the fight)"), table.concat(settingsTexts(c), " | "))
    c:leaveCombat()
    c:advance(0.5)
    eq(stepperText(c), "20")
end)

-- Spec 1 rule 1: the steps come from the game's list when it is there; the list is never written to.
test("chat size: the steps follow the game's list when it differs, then 30 and 34", function()
    local c, PE = newChat(function(cc) rawset(cc.env, "CHAT_FONT_HEIGHTS", { 22, 10, 15.2, 15, "x", -3 }) end)
    setAllTo(c, 10)
    local seen = {}
    for _ = 1, 5 do
        c:click(settingsButton(c, PE, "+"))
        seen[#seen + 1] = mainSize(c)
    end
    eq(seen, { 15, 22, 30, 34, 34 })
    eq(rawget(c.env, "CHAT_FONT_HEIGHTS"), { 22, 10, 15.2, 15, "x", -3 })
end)

test("chat size: a game list that already goes past 30 gets only the larger extra size", function()
    local c, PE = newChat(function(cc) rawset(cc.env, "CHAT_FONT_HEIGHTS", { 12, 32 }) end)
    setAllTo(c, 12)
    local seen = {}
    for _ = 1, 3 do
        c:click(settingsButton(c, PE, "+"))
        seen[#seen + 1] = mainSize(c)
    end
    eq(seen, { 32, 34, 34 })
end)

-- Spec 1 rule 1 and "Debug log lines": a missing or damaged list falls back to the seven known sizes.
test("chat size: without the game's list the known sizes are used, and the log says so", function()
    local empty = {}
    for name, value in pairs({ missing = false, text = "12,14", empty = empty, junk = { "a", 0 } }) do
        local c, PE = newChat(function(cc) rawset(cc.env, "CHAT_FONT_HEIGHTS", value or nil) end)
        setAllTo(c, 12)
        local seen = {}
        for _ = 1, 9 do
            c:click(settingsButton(c, PE, "+"))
            seen[#seen + 1] = mainSize(c)
        end
        eq(seen, { 14, 16, 18, 20, 24, 27, 30, 34, 34 }, name)
        PE:SetDebug(true)
        c:click(settingsButton(c, PE, "-"))
        eq(debugLines(c, "chat"), { "text size: the game's size list is missing, using our own",
            "text size 34 -> 30 (10 windows)" }, name)
    end
end)

-- Spec 1 "What the player sees": the row is shown whether "Chat from round button" is on or off
-- (this reverses the 0.1.0 rule that hid it while the feature was off).
test("chat size: the row is drawn and works while the chat feature is off", function()
    local c, PE = T.new({})
    PE:OpenSettings("chat")
    c:advance(0.2)
    check(hasText(c, "Chat text size"), "not drawn with the feature off: " .. table.concat(settingsTexts(c), " | "))
    eq(stepperText(c), "18")
    c:click(shownButton(c, "-"))
    c:advance(0.2)
    eq(stepperText(c), "16")
    eq(#sizeCalls(c), 10)
    for i, f in ipairs(c.chatWindows) do eq(select(2, f:GetFont()), 16, "window " .. i) end
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile then
            check(not rec.events.CHAT_MSG_WHISPER and not rec.events.CHAT_MSG_WHISPER_INFORM,
                rec.addonFile .. " listens for whispers with chat off")
        end
    end
    eq(PE:GetModuleState("chat") == "on", false, "the tap switched the feature on")
    c:assertClean("chat size with the feature off")
end)

-- Spec 1 rule 7: nothing on login, nothing saved, with the feature off.
test("chat size: with the feature off nothing is saved and nothing is called until a tap", function()
    local c, PE = T.new({})
    PE:OpenSettings("chat")
    c:advance(0.2)
    eq(#sizeCalls(c), 0)
    c:click(shownButton(c, "+"))
    local saved = rawget(c.env, "PocketEssentialsDB").options.chat
    for key in pairs(type(saved) == "table" and saved or {}) do
        -- scale: the picker window's size (spec 0.9.0), not the text size.
        if key ~= "scale" then eq(key, "whispers", "the chat feature saved something besides its whisper list") end
    end
end)

test("chat size: a tap in a fight with the feature off is held and applied when the fight ends", function()
    local c, PE = T.new({})
    PE:OpenSettings("chat")
    c:advance(0.2)
    local bigger = shownButton(c, "+")
    c:enterCombat()
    c:click(bigger)
    eq(#sizeCalls(c), 0, "the game was called during the fight")
    c:leaveCombat()
    c:advance(0.5)
    eq(mainSize(c), 20)
    eq(#sizeCalls(c), 10)
end)

-- Spec 3: "If the function or the main chat window is missing, the row says 'Not available...'".
-- With Chat picker off, so the only - and + would be the text size row's (the
-- picker's window size row has its own; spec 0.9.0).
test("chat size: without the game's function the row says so and has no buttons", function()
    local c, PE = T.new({ setup = function(cc) rawset(cc.env, "FCF_SetChatWindowFontSize", nil) end })
    PE:OpenSettings("chat")
    c:advance(0.2)
    check(hasText(c, "Chat text size: Not available on this version of the game"), table.concat(settingsTexts(c), " | "))
    check(not settingsButton(c, PE, "+") and not settingsButton(c, PE, "-"), "buttons drawn")
end)

test("chat size: without a main chat window the row says so and has no buttons", function()
    local c, PE = T.new({ setup = function(cc) rawset(cc.env, "DEFAULT_CHAT_FRAME", nil) end })
    PE:OpenSettings("chat")
    c:advance(0.2)
    check(hasText(c, "Chat text size: Not available on this version of the game"), table.concat(settingsTexts(c), " | "))
    check(not settingsButton(c, PE, "+"), "buttons drawn")
end)

-- Guard: a window that fails does not stop the others.
test("chat size: one chat window that raises an error does not stop the rest", function()
    local c, PE = newChat()
    local real = rawget(c.env, "FCF_SetChatWindowFontSize")
    rawset(c.env, "FCF_SetChatWindowFontSize", function(self, f, size)
        if f:GetID() == 2 then error("boom") end
        return real(self, f, size)
    end)
    c:click(settingsButton(c, PE, "+"))
    eq(c.chatSizes[1], 20)
    eq(c.chatSizes[3], 20)
    eq(c.chatSizes[2], nil)
end)

-- Settings.lua: the new row kind works for any feature (no chat code involved in the drawing).
test("settings: an option row with a value and buttons draws the text and runs each action then redraws", function()
    local c, PE = T.new({ on = { "bags" } })
    local mod = PE:GetModule("bags")
    local n = 0
    mod.options[#mod.options + 1] = { label = "Test row", value = function() return "n = " .. n end,
        buttons = { { label = "Add one", action = function() n = n + 1 end }, { label = "Add ten", action = function() n = n + 10 end } } }
    PE:OpenSettings("bags")
    c:advance(0.2)
    check(hasText(c, "Test row: n = 0"), table.concat(settingsTexts(c), " | "))
    local one
    walk(c, settingsOf(c), function(w) if c._state(w).type == "Button" and T.labelOf(w) == "Add one" then one = w end end)
    c:click(one)
    c:advance(0.5)
    check(hasText(c, "Test row: n = 1"), "not redrawn: " .. table.concat(settingsTexts(c), " | "))
end)

-- Settings.lua: an entry { text = } in a buttons row is a text at that place, not a button.
test("settings: a text entry in a buttons row is drawn between the buttons and read again after a press", function()
    local c, PE = T.new({ on = { "bags" } })
    local mod = PE:GetModule("bags")
    local n = 7
    mod.options[#mod.options + 1] = { label = "Test row", buttons = function()
        return { { label = "-", action = function() n = n - 1 end }, { text = "n" .. n },
            { label = "+", action = function() n = n + 1 end } }
    end }
    PE:OpenSettings("bags")
    c:advance(0.2)
    check(hasText(c, "Test row"), table.concat(settingsTexts(c), " | "))
    eq(stepperText(c), "n7")
    check(not shownButton(c, "n7"), "the text was drawn as a button")
    c:click(shownButton(c, "+"))
    c:advance(0.2)
    eq(stepperText(c), "n8")
    c:assertClean("settings text entry")
end)

-- Settings.lua: `always = true` on an option row.
test("settings: an option row marked always is drawn with its feature off, others are not", function()
    local c, PE = T.new({})
    local mod = PE:GetModule("bags")
    local taps = 0
    mod.options[#mod.options + 1] = { label = "Plain row", value = function() return "x" end,
        buttons = { { label = "Plain tap", action = function() end } } }
    mod.options[#mod.options + 1] = { label = "Always row", value = function() return "y" end, always = true,
        buttons = { { label = "Always tap", action = function() taps = taps + 1 end } } }
    PE:OpenSettings("bags")
    c:advance(0.2)
    check(hasText(c, "Always row: y"), table.concat(settingsTexts(c), " | "))
    check(not hasText(c, "Plain row: x"), "a row without the mark was drawn with the feature off")
    check(not shownButton(c, "Plain tap"), "a button without the mark was drawn with the feature off")
    c:click(shownButton(c, "Always tap"))
    eq(taps, 1)
    -- With the feature on, both are drawn.
    PE:SetModuleEnabled("bags", true)
    c:advance(0.2)
    check(hasText(c, "Always row: y") and hasText(c, "Plain row: x"), table.concat(settingsTexts(c), " | "))
end)

-- Spec 2026-11-20-0.9.0-ui-redesign: no fold buttons; an always row shows on the Chat tab with the feature off.
test("settings: the Chat tab shows Chat text size with the chat feature off, and has no fold button", function()
    local c, PE = T.new({})
    PE:OpenSettings("chat")
    c:advance(0.2)
    check(hasText(c, "Chat text size") and stepperText(c) == "18", "the row is not drawn with the feature off")
    check(not shownButton(c, "Hide options") and not shownButton(c, "Show options"), "a fold button")
end)

test("settings: a feature that is off with no always row draws no option rows", function()
    local c, PE = T.new({})
    local chat = PE:GetModule("chat")
    for i = #chat.options, 1, -1 do chat.options[i] = nil end
    PE:OpenSettings("chat")
    c:advance(0.2)
    check(not hasText(c, "Chat text size"), "a row drawn")
    check(not shownButton(c, "-"), "a control drawn")
end)

---------------------------------------------------------------------------
-- Move on screen: the chat prompt as a movable piece (docs/superpowers/specs/2026-11-17-move-things.md)
---------------------------------------------------------------------------

local function movePanel(c) return rawget(c.env, "PocketEssentialsMovePanel") end
local PROMPT_LABEL = "\"Press A to type\""
local function moveButton(c, label)
    local found
    local function walk(w, seen)
        if seen[w] then return end
        seen[w] = true
        local st = c._state(w)
        if st.type == "Button" and w:IsVisible() and T.labelOf(w) == label then found = w end
        for _, ch in ipairs(st.children) do walk(ch, seen) end
    end
    walk(movePanel(c), {})
    return found
end
local function moveOutline(c)
    for _, rec in ipairs(c:frames()) do
        if rec.name == "PocketEssentialsMoveOutline" then return rec.frame end
    end
end
local function openMove(c, PE)
    PE.Move:Open()
    c:advance(0.1)
    check(movePanel(c) and movePanel(c):IsShown(), "the Move on screen panel did not open")
end
local function nudge(c, label)
    local b = moveButton(c, label)
    check(b, "no '" .. label .. "' button")
    c:script(b, "OnMouseDown", "LeftButton")
    c:script(b, "OnMouseUp", "LeftButton")
    c:script(b, "OnClick", "LeftButton", false)
end
local function rect(c, w)
    local l, r, t, b = c._rect(w)
    return { l = l, r = r, t = t, b = b }
end
local function sameRect(a, b)
    return math.abs(a.l - b.l) < 1e-3 and math.abs(a.r - b.r) < 1e-3
        and math.abs(a.t - b.t) < 1e-3 and math.abs(a.b - b.b) < 1e-3
end

local function promptSelected(c, PE)
    openMove(c, PE)
    c:click(moveButton(c, PROMPT_LABEL))
end

test("chat: move: no saved offset leaves the prompt where it was", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    tapLabel(c, PE, "Say")
    local f = promptLines(c)
    local point, rel, relPoint, x, y = f:GetPoint(1)
    eq({ point, rel, relPoint }, { "CENTER", c.UIParent, "CENTER" })
    check(math.abs(x) < 0.01 and math.abs(y - PE.UI:Px(110)) < 0.01, "at " .. x .. "," .. y)
end)

test("chat: move: a saved offset is added when the prompt is laid out", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    PE.db.ui.moved.chatPrompt = { x = -20, y = 8 }
    local dx, dy = PE.Move:GetOffset("chatPrompt")
    tapLabel(c, PE, "Say")
    local _, _, _, x, y = promptLines(c):GetPoint(1)
    check(dx ~= 0 and math.abs(x - dx) < 0.01 and math.abs(y - (PE.UI:Px(110) + dy)) < 0.01, "at " .. x .. "," .. y)
end)

-- Spec 2026-11-20-0.9.0-ui-redesign, "Move on screen": always listed, as "Press A to type";
-- with Chat picker off it reads "(off)", is dimmed and a tap does nothing.
test("chat: move: listed as Press A to type while Chat picker is on, and dimmed with (off) while it is off", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    openMove(c, c.PE)
    local on = moveButton(c, PROMPT_LABEL)
    check(on, "not listed while on")
    eq(on.peStyle, "normal")
    c.PE.Move:Close("test")
    local c2 = T.new({ on = {}, gamepadUI = true })
    openMove(c2, c2.PE)
    local off = moveButton(c2, PROMPT_LABEL .. " (off)")
    check(off, "not listed as off while off")
    eq(off.peStyle, "disabled")
    check(moveButton(c2, PROMPT_LABEL) == nil, "listed as on while off")
    c2:click(off)
    check(not off.peSelected, "a tap picked the prompt while Chat picker is off")
end)

test("chat: move: the outline shows over the prompt's place before any prompt, and shows no prompt", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    check(not promptShown(c), "setup")
    promptSelected(c, PE)
    local outline = moveOutline(c)
    check(outline and outline:IsVisible(), "no outline")
    local r = rect(c, outline)
    check(r.r - r.l > 50 and r.t - r.b > 20, "empty outline")
    check(not promptShown(c), "the prompt was shown by the outline")
    nudge(c, "Up")
    check(not promptShown(c), "the prompt was shown by a move")
    -- the prompt then appears where the outline was, 2 pixels higher (one Up press after r was read)
    PE.Move:Close("test")
    tapLabel(c, PE, "Say")
    local shown = rect(c, promptLines(c))
    check(math.abs((shown.l + shown.r) / 2 - (r.l + r.r) / 2) < 0.01, "centre differs from the outline")
    check(math.abs(shown.t - (r.t + PE.UI:Px(2))) < 0.01, "the prompt is not where the outline showed, moved up 2 pixels")
end)

test("chat: move: a press while the prompt shows moves it 2 pixels, and it stays shown and unhidden by the panel", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    tapLabel(c, PE, "Say")
    local f = promptLines(c)
    local _, _, _, x0, y0 = f:GetPoint(1)
    promptSelected(c, PE)
    nudge(c, "Right")
    local _, _, _, x1, y1 = f:GetPoint(1)
    check(math.abs(x1 - x0 - PE.UI:Px(2)) < 0.01 and math.abs(y1 - y0) < 0.01, "moved " .. (x1 - x0))
    check(f:IsShown(), "prompt hidden by a move")
    check(sameRect(rect(c, moveOutline(c)), rect(c, f)), "outline differs from the shown prompt")
end)

test("chat: move: moving with no prompt showing never shows or hides it", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    local PE = c.PE
    promptSelected(c, PE)
    nudge(c, "Left"); nudge(c, "Down")
    check(not promptShown(c), "shown")
    eq(PE.db.ui.moved.chatPrompt, { x = -2, y = -2 })
    PE.Move:Close("test")
    c:advance(0.5)
    check(not promptShown(c), "shown after the panel closed")
    eq(#c:problems(), 0, table.concat(c:problems(), " / "))
end)

-- Spec 2026-11-20-0.9.0-ui-redesign, "Feature names and lines".
test("chat: the switch is called Chat picker, with its line under it", function()
    local c, PE = T.new({})
    local mod = PE:GetModule("chat")
    eq(mod.label, "Chat picker")
    eq(mod.desc, "Tap the round button to pick who to talk to.")
end)

---------------------------------------------------------------------------
-- Spec 2026-11-20-0.9.0-ui-redesign: "Chat window" and the Chat picker rows.
---------------------------------------------------------------------------

-- The window's size rules at a scale (s = scale/100), straight from the spec.
local function expectedWidth(PE, s)
    local M = PE.UI:Metrics()
    return 2 * M.pad * s + 3 * (3.4 * M.button * s) + 2 * M.gap * s
end
-- Rows of targets, and of names plus Clear marks (0: the "No whispers yet." line).
local function expectedHeight(PE, s, targetRows, nameRows)
    local M = PE.UI:Metrics()
    local button, gap, pad, small = M.button * s, M.gap * s, M.pad * s, M.smallFontSize * s
    local head = small * 1.15 + gap * 0.4
    local function grid(rows) return rows * button + (rows - 1) * gap end
    local content = head + grid(targetRows) + gap * 1.5 + head
        + (nameRows > 0 and grid(nameRows) or small * 1.15)
    return M.border + (button + gap) + gap + content + pad
end

local function panelSize(c)
    local l, r, t, b = c._rect(panelOf(c))
    return r - l, t - b
end

local function near(a, b, what)
    check(type(a) == "number" and math.abs(a - b) < 0.01, what .. ": " .. tostring(a) .. ", wanted " .. tostring(b))
end

-- Every shown text in the chat window.
local function windowTexts(c)
    local out = {}
    walk(c, panelOf(c), function(w)
        if not w:IsVisible() then return end
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and st.shown and st.text and st.text ~= "" then out[#out + 1] = st.text end
        end
    end)
    return out
end

-- The chips: the buttons in the window's list (not Settings and Close in the title bar).
local function chips(c)
    local out = {}
    for _, b in ipairs(visibleButtons(c, panelOf(c))) do
        local l = T.labelOf(b)
        if l ~= "Settings" and l ~= "Close" then out[#out + 1] = b end
    end
    return out
end

-- A shown red dot on a button: a texture tinted (.88, .08, .08).
local function redDot(c, btn)
    for _, r in ipairs(c._state(btn).regions) do
        local st = c._state(r)
        local v = st.vertexColor
        if st.type == "Texture" and st.shown and v and math.abs(v[1] - 0.88) < 0.001
            and math.abs(v[2] - 0.08) < 0.001 and math.abs(v[3] - 0.08) < 0.001 then return r end
    end
    return nil
end

test("chat window: the width is 3 chips of 3.4 buttons plus the gaps and padding, at the normal size", function()
    local c, PE = newChat()
    openPicker(c, PE)
    local w = panelSize(c)
    near(w, expectedWidth(PE, 1), "width")
    local M = PE.UI:Metrics()
    local l, r, t, b = c._rect(buttonLabelled(c, "Say"))
    near(r - l, 3.4 * M.button, "chip width")
    near(t - b, M.button, "chip height")
end)

test("chat window: the size follows the Size of the chat picker window setting", function()
    local c, PE = newChat()
    eq(PE:GetModule("chat").opts.scale, 100, "the default")
    c:whisperIn("Ann", "hi")
    c:whisperIn("Bob", "hi")
    PE:GetModule("chat").opts.scale = 150
    openPicker(c, PE)
    local w, h = panelSize(c)
    near(w, expectedWidth(PE, 1.5), "width at 150%")
    near(h, expectedHeight(PE, 1.5, 1, 1), "height at 150%")
    local M = PE.UI:Metrics()
    local l, r, t, b = c._rect(buttonLabelled(c, "Say"))
    near(r - l, 3.4 * M.button * 1.5, "chip width at 150%")
    near(t - b, M.button * 1.5, "chip height at 150%")
    tapHub(c, PE)
    PE:GetModule("chat").opts.scale = 70
    openPicker(c, PE)
    w, h = panelSize(c)
    near(w, expectedWidth(PE, 0.7), "width at 70%")
    near(h, expectedHeight(PE, 0.7, 1, 1), "height at 70%")
end)

test("chat window: the text follows the window's size too", function()
    local c, PE = newChat()
    PE:GetModule("chat").opts.scale = 150
    openPicker(c, PE)
    local M = PE.UI:Metrics()
    local _, size = buttonLabelled(c, "Say").peText:GetFont()
    near(size, M.fontSize * 1.5, "chip text size at 150%")
    tapHub(c, PE)
    PE:GetModule("chat").opts.scale = 100
    openPicker(c, PE)
    _, size = buttonLabelled(c, "Say").peText:GetFont()
    near(size, M.fontSize, "chip text size back at 100%")
end)

test("chat window: the height follows the content", function()
    local c, PE = newChat()
    openPicker(c, PE)
    local _, h = panelSize(c)
    near(h, expectedHeight(PE, 1, 1, 0), "Say and Yell, no whispers")
    tapHub(c, PE)
    c:whisperIn("Ann", "hi")
    c:whisperIn("Bob", "hi")
    openPicker(c, PE)
    _, h = panelSize(c)
    near(h, expectedHeight(PE, 1, 1, 1), "two names and Clear marks: one row")
    tapHub(c, PE)
    c:whisperIn("Cat", "hi")
    openPicker(c, PE)
    _, h = panelSize(c)
    near(h, expectedHeight(PE, 1, 1, 2), "three names and Clear marks: two rows")
    local w = panelSize(c)
    near(w, expectedWidth(PE, 1), "the width does not change with the content")
end)

test("chat window: content taller than the screen scrolls inside a window that fits", function()
    local c, PE = newChat(function(c)
        c.world.group, c.world.guild = "raid", "Pocket Guild"
        local list = {}
        for i = 1, 10 do list[i] = { id = i, name = "Channel " .. i } end
        c.world.channels = list
    end)
    for _, n in ipairs({ "Ann", "Bob", "Cat", "Dan", "Eve", "Fay" }) do c:whisperIn(n, "hi") end
    PE:GetModule("chat").opts.scale = 150
    local p = openPicker(c, PE)
    eq(#p.whispers, 6)
    local _, h = panelSize(c)
    local screenHeight = rawget(c.env, "UIParent"):GetHeight()
    check(h <= screenHeight * 0.92 + 0.01, "the window is taller than the screen: " .. h)
    local w = panelSize(c)
    check(w <= rawget(c.env, "UIParent"):GetWidth(), "the window is wider than the screen: " .. w)
    c:assertClean("a long chat picker")
end)

-- Review fix: the scroll bar follows the window's own scale, like its chips
-- (Chat.lua DoRefresh, UI.lua area:Layout metrics).
test("chat window: the scroll bar's width follows the window's size", function()
    for _, scale in ipairs({ 100, 150 }) do
        local c, PE = newChat(function(c)
            c.world.group, c.world.guild = "raid", "Pocket Guild"
            local list = {}
            for i = 1, 10 do list[i] = { id = i, name = "Channel " .. i } end
            c.world.channels = list
        end)
        PE:SetUISetting("touch", true)
        for _, n in ipairs({ "Ann", "Bob", "Cat", "Dan", "Eve", "Fay", "Hal", "Ivy", "Kim", "Lou" }) do
            c:whisperIn(n, "hi")
        end
        PE:GetModule("chat").opts.scale = scale
        openPicker(c, PE)
        local area = rawget(c.env, "PocketEssentialsChatPanel").peNavArea
        check(area.upButton:IsShown(), scale .. ": the list does not scroll")
        local M = PE.UI:Metrics()
        local s = scale / 100
        local l, r, t, b = c._rect(area.upButton)
        near(r - l, M.button * 0.75 * s, "the bar's width at " .. scale .. "%")
        near(t - b, M.button * s, "the bar's tab height at " .. scale .. "%")
        c:assertClean("chat bar at " .. scale)
    end
end)

test("chat window: the chips are in 3 columns", function()
    local c, PE = newChat(function(c)
        c.world.group, c.world.guild = "party", "Pocket Guild"
        c.world.channels = { { id = 1, name = "General" }, { id = 2, name = "Trade" } }
    end)
    local p = openPicker(c, PE)
    eq(#p.targets, 6, "targets: " .. table.concat(p.targets, ", "))
    local xs, ys = {}, {}
    for i, label in ipairs(p.targets) do
        local l, _, t = c._rect(buttonLabelled(c, label))
        xs[i], ys[i] = l, t
    end
    check(xs[1] < xs[2] and xs[2] < xs[3], "the first row is not three across")
    near(ys[1], ys[3], "first row")
    near(xs[4], xs[1], "the fourth chip starts the second row")
    check(ys[4] < ys[1], "the fourth chip is not below the first")
end)

test("chat window: the keyboard hint is gone, the headings are Talk in and Whispers", function()
    local c, PE = newChat()
    openPicker(c, PE)
    local texts = table.concat(windowTexts(c), " | ")
    check(not texts:find("Three-finger", 1, true), "the hint is still there: " .. texts)
    check(texts:find("Talk in", 1, true), "no Talk in heading: " .. texts)
    check(texts:find("Whispers", 1, true), "no Whispers heading: " .. texts)
    check(texts:find("No whispers yet.", 1, true), "no empty line: " .. texts)
    check(not texts:find("Clear marks", 1, true), "Clear marks with no names: " .. texts)
end)

test("chat window: Clear marks is the last chip, in the off style, even with nothing marked", function()
    local c, PE = newChat()
    c:whisperIn("Ann", "hi")
    c:whisperIn("Bob", "hi")
    c:whisperOut("Bob", "hello")
    openPicker(c, PE)
    local list = chips(c)
    local last = list[#list]
    eq(T.labelOf(last), "Clear marks")
    eq(last.peStyle, "off")
    local texts = table.concat(windowTexts(c), " | ")
    check(not texts:find("No whispers yet.", 1, true), "the empty line shows with names listed")
    c:whisperOut("Ann", "hello")
    tapHub(c, PE)
    openPicker(c, PE)
    list = chips(c)
    eq(T.labelOf(list[#list]), "Clear marks", "with no marks at all")
end)

test("chat window: an unanswered name has the warn style and a red dot at its top-right, no NEW", function()
    local c, PE = newChat()
    c:whisperIn("Ann", "hi")
    c:whisperIn("Bob", "hi")
    c:whisperOut("Bob", "hello")
    openPicker(c, PE)
    local ann, bob = buttonLabelled(c, "Ann"), buttonLabelled(c, "Bob")
    eq(ann.peStyle, "warn")
    eq(bob.peStyle, "normal")
    check(redDot(c, bob) == nil, "a dot on an answered name")
    local dot = redDot(c, ann)
    check(dot, "no red dot on the unanswered name")
    local M = PE.UI:Metrics()
    local d, inset = M.smallFontSize * 0.7, M.gap * 0.6
    local _, br, bt = c._rect(ann)
    local dl, dr, dt, db = c._rect(dot)
    near((dl + dr) / 2, br - inset - d / 2, "dot centre x")
    near((dt + db) / 2, bt - inset - d / 2, "dot centre y")
    check(dr - dl >= d - 0.01 and dr - dl <= d * 1.05, "dot size " .. (dr - dl))
    local texts = table.concat(windowTexts(c), " | ")
    check(not texts:find("NEW", 1, true), "NEW is still shown: " .. texts)
end)

test("chat window: Settings and Close stay in the title bar", function()
    local c, PE = newChat()
    openPicker(c, PE)
    local M = PE.UI:Metrics()
    local _, pr, pt = c._rect(panelOf(c))
    local close, settings = buttonLabelled(c, "Close"), buttonLabelled(c, "Settings")
    local _, cr, ct = c._rect(close)
    local _, sr, st = c._rect(settings)
    check(pt - ct < M.button, "Close is not in the title bar")
    near(st, ct, "Settings is not beside Close")
    check(sr < cr and cr < pr, "Settings is not left of Close")
end)

test("chat options: Chat text size keeps always and gains help; the window size is a number from 70 to 150", function()
    local c, PE = T.new({})
    local opts = PE:GetModule("chat").options
    eq(opts[1].label, "Chat text size")
    eq(opts[1].always, true)
    eq(opts[1].help, "For every chat window, even with Chat picker off.")
    local n = opts[2]
    eq(n.key, "scale")
    eq(n.label, "Size of the chat picker window")
    eq(n.number, { min = 70, max = 150, step = 10, default = 100, suffix = "%", unit = "of normal" })
    eq(PE:GetModule("chat").opts.scale, 100)
end)

return { known = KNOWN_FAILURES }
