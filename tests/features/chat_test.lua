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

-- Chat.lua OpenChatTo lines 190-231: choose the box, open it with OpenChat(nil, frame), then set the
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
    check(not panelOf(c):IsShown(), "the picker stays open after a tap")
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
    check(not panelOf(c):IsShown(), "the picker stays open after a tap")
end)

return { known = KNOWN_FAILURES }
