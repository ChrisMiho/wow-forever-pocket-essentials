-- Rules for "Big chat buttons" (Chat.lua).
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
    for _, b in ipairs(visibleButtons(c, panelOf(c))) do
        check(T.labelOf(b) ~= "Clear marks", "the Clear marks button is still showing with nothing to clear")
    end
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

-- Opens the settings window and returns a button with that label (any, shown or scrolled away).
local function settingsButton(c, PE, label)
    PE:OpenSettings()
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

-- Spec 3 "Behaviour": each tap moves one step and every chat window gets the same size.
test("chat size: Bigger moves one step and all ten chat windows follow", function()
    local c, PE = newChat()
    c:click(settingsButton(c, PE, "Bigger"))
    c:advance(0.5)
    for i, f in ipairs(c.chatWindows) do eq(select(2, f:GetFont()), 20, "window " .. i) end
    eq(c.chatSizes[1], 20)
    eq(c.chatSizes[10], 20)
    eq(#sizeCalls(c), 10)
    check(hasText(c, "Chat text size: 20"), "the row does not show the new size: " .. table.concat(settingsTexts(c), " | "))
end)

test("chat size: Smaller moves one step down", function()
    local c, PE = newChat()
    c:click(settingsButton(c, PE, "Smaller"))
    eq(mainSize(c), 16)
    eq(c.chatSizes[3], 16)
end)

-- Spec 3: the list goes on from 27 to 30 and 34, and at either end the button does nothing more.
test("chat size: the steps run 12 14 16 18 20 24 27 30 34 and stop at both ends", function()
    local c, PE = newChat()
    local seen = { mainSize(c) }
    for _ = 1, 10 do
        c:click(settingsButton(c, PE, "Bigger"))
        seen[#seen + 1] = mainSize(c)
    end
    eq(seen, { 18, 20, 24, 27, 30, 34, 34, 34, 34, 34, 34 })
    local before = #sizeCalls(c)
    c:click(settingsButton(c, PE, "Bigger"))
    eq(#sizeCalls(c), before, "a tap at the top still called the game")
    seen = {}
    for _ = 1, 10 do
        c:click(settingsButton(c, PE, "Smaller"))
        seen[#seen + 1] = mainSize(c)
    end
    eq(seen, { 30, 27, 24, 20, 18, 16, 14, 12, 12, 12 })
end)

-- Spec 3: a size that is not on the list moves to the next listed size in the tapped direction.
test("chat size: a size between steps moves to the next listed size in the tapped direction", function()
    local cases = {
        { 19, "Bigger", 20 }, { 19, "Smaller", 18 }, { 13, "Smaller", 12 }, { 13, "Bigger", 14 },
        { 11, "Bigger", 12 }, { 40, "Smaller", 34 }, { 28.4, "Bigger", 30 }, { 17.6, "Smaller", 16 },
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
    for _, case in ipairs({ { 35, "Bigger" }, { 11, "Smaller" } }) do
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
    local bigger = settingsButton(c, PE, "Bigger")
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
    local bigger = settingsButton(c, PE, "Bigger")
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
    local bigger = settingsButton(c, PE, "Bigger")
    local smaller = settingsButton(c, PE, "Smaller")
    c:enterCombat()
    c:click(bigger)
    c:click(smaller)
    c:leaveCombat()
    c:advance(0.5)
    eq(mainSize(c), 18)
end)

test("chat size: in a fight the value text shows the size that is waiting; afterwards just the size", function()
    local c, PE = newChat()
    local bigger = settingsButton(c, PE, "Bigger")
    check(hasText(c, "Chat text size: 18"))
    c:enterCombat()
    c:click(bigger)
    c:advance(0.5)
    check(hasText(c, "Chat text size: 20 (after the fight)"), table.concat(settingsTexts(c), " | "))
    c:click(bigger)
    c:advance(0.5)
    check(hasText(c, "Chat text size: 24 (after the fight)"), table.concat(settingsTexts(c), " | "))
    c:leaveCombat()
    c:advance(0.5)
    check(hasText(c, "Chat text size: 24"), table.concat(settingsTexts(c), " | "))
end)

test("chat size: taps in a fight stop at the end of the list", function()
    local c, PE = newChat()
    setAllTo(c, 30)
    local bigger = settingsButton(c, PE, "Bigger")
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
    c:click(settingsButton(c, PE, "Bigger"))
    eq(debugLines(c, "chat"), { "text size 18 -> 20 (10 windows)" })
end)

test("chat size: a tap at the end writes a line and calls nothing", function()
    local c, PE = newChat()
    PE:SetDebug(true)
    setAllTo(c, 34)
    c:click(settingsButton(c, PE, "Bigger"))
    eq(debugLines(c, "chat"), { "text size 34: already the biggest" })
    eq(#sizeCalls(c), 0)
end)

-- Spec 3: "The addon stores nothing" and "With no tap, nothing is changed".
test("chat size: nothing is called or saved until a button is tapped", function()
    local c, PE = newChat()
    settingsButton(c, PE, "Bigger")
    eq(#sizeCalls(c), 0)
    local saved = rawget(c.env, "PocketEssentialsDB").options.chat
    eq(saved.whispers, {})
    local keys = 0
    for _ in pairs(saved) do keys = keys + 1 end
    eq(keys, 1, "the chat feature saved something besides its whisper list")
end)

-- Spec 3 "Rules": the edit box is never touched; the game's own size list is not written to.
test("chat size: the edit box is not touched and the game's own size list stays as it is", function()
    local c, PE = newChat()
    c:click(settingsButton(c, PE, "Bigger"))
    for _, call in ipairs(c.calls) do
        check(not tostring(call.name):find("EditBox", 1, true) and not tostring(call.name):find("OpenChat", 1, true),
            "touched the chat box: " .. tostring(call.name))
    end
    eq(rawget(c.env, "CHAT_FONT_HEIGHTS"), { 12, 14, 16, 18, 20, 24, 27 })
    c:assertClean("chat size")
end)

-- Spec 3: the row shows the current size and the two buttons.
test("chat size: the row in the chat block shows the label, the size and both buttons", function()
    local c, PE = newChat()
    check(settingsButton(c, PE, "Smaller") and settingsButton(c, PE, "Bigger"), "buttons missing")
    check(hasText(c, "Chat text size: 18"), "no size text: " .. table.concat(settingsTexts(c), " | "))
end)

test("chat size: the row is not drawn while the chat feature is off", function()
    local c, PE = T.new({})
    PE:OpenSettings()
    c:advance(0.2)
    check(not hasText(c, "Chat text size: 18"), "drawn with the feature off")
end)

-- Spec 3: "If the function or the main chat window is missing, the row says 'Not available...'".
test("chat size: without the game's function the row says so and has no buttons", function()
    local c, PE = newChat(function(cc) rawset(cc.env, "FCF_SetChatWindowFontSize", nil) end)
    PE:OpenSettings()
    c:advance(0.2)
    check(hasText(c, "Chat text size: Not available on this version of the game"), table.concat(settingsTexts(c), " | "))
    check(not settingsButton(c, PE, "Bigger") and not settingsButton(c, PE, "Smaller"), "buttons drawn")
end)

test("chat size: without a main chat window the row says so and has no buttons", function()
    local c, PE = newChat(function(cc) rawset(cc.env, "DEFAULT_CHAT_FRAME", nil) end)
    PE:OpenSettings()
    c:advance(0.2)
    check(hasText(c, "Chat text size: Not available on this version of the game"), table.concat(settingsTexts(c), " | "))
    check(not settingsButton(c, PE, "Bigger"), "buttons drawn")
end)

-- Guard: a window that fails does not stop the others.
test("chat size: one chat window that raises an error does not stop the rest", function()
    local c, PE = newChat()
    local real = rawget(c.env, "FCF_SetChatWindowFontSize")
    rawset(c.env, "FCF_SetChatWindowFontSize", function(self, f, size)
        if f:GetID() == 2 then error("boom") end
        return real(self, f, size)
    end)
    c:click(settingsButton(c, PE, "Bigger"))
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
    PE:OpenSettings()
    c:advance(0.2)
    check(hasText(c, "Test row: n = 0"), table.concat(settingsTexts(c), " | "))
    local one
    walk(c, settingsOf(c), function(w) if c._state(w).type == "Button" and T.labelOf(w) == "Add one" then one = w end end)
    c:click(one)
    c:advance(0.5)
    check(hasText(c, "Test row: n = 1"), "not redrawn: " .. table.concat(settingsTexts(c), " | "))
end)

---------------------------------------------------------------------------
-- Move things: the chat prompt as a movable piece (docs/superpowers/specs/2026-11-17-move-things.md)
---------------------------------------------------------------------------

local function movePanel(c) return rawget(c.env, "PocketEssentialsMovePanel") end
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
    check(movePanel(c) and movePanel(c):IsShown(), "the Move things panel did not open")
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
    c:click(moveButton(c, "Chat prompt"))
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

test("chat: move: listed while Big chat buttons is on, not when it is off", function()
    local c = T.new({ on = { "chat" }, gamepadUI = true })
    openMove(c, c.PE)
    check(moveButton(c, "Chat prompt"), "not listed while on")
    c.PE.Move:Close("test")
    local c2 = T.new({ on = {}, gamepadUI = true })
    openMove(c2, c2.PE)
    check(moveButton(c2, "Chat prompt") == nil, "listed while off")
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

return { known = KNOWN_FAILURES }
