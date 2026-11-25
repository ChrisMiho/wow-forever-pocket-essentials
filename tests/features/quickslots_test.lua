-- Rules for "Quick slots", first slot: the mount (QuickSlots.lua, and its line in Chat.lua).
-- Source: docs/superpowers/specs/2026-11-25-0.21.0-mount-slot.md ("What the player gets",
-- "Game calls", "Rules that apply") and the plan's Review Focus
-- (docs/superpowers/plans/2026-11-25-0.21.0-mount-slot.md). Fresh client and addon per test.
--
-- The stand-in client has no mount journal of its own, so each test hands in the one it needs:
-- a table for the rule functions, or C_MountJournal and IsMounted put into the client for the
-- ones that read the game. These prove the logic. Whether the game lets an addon's tap call
-- SummonByID, and what it answers for "usable" and "favourite", only the device can show.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

-- One mount as GetMountInfoByID answers it (MountJournalDocumentation.lua:273): name, spellID,
-- icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction,
-- shouldHideOnChar, isCollected, mountID.
local function mount(id, name, o)
    o = o or {}
    return { id = id, name = name, icon = o.icon or (1000 + id), active = o.active or false,
        usable = o.usable ~= false, favourite = o.favourite or false, hide = o.hide or false,
        collected = o.collected ~= false, raw = o.raw }
end

-- A journal over a list of mounts. `calls` counts every call by name.
local function journal(mounts)
    local calls = { GetMountIDs = 0, GetMountInfoByID = 0, SummonByID = 0, Dismiss = 0 }
    local byId = {}
    for _, m in ipairs(mounts) do byId[m.id] = m end
    local j = { calls = calls, summoned = {} }
    function j.GetMountIDs()
        calls.GetMountIDs = calls.GetMountIDs + 1
        local ids = {}
        for i, m in ipairs(mounts) do ids[i] = m.id end
        return ids
    end
    function j.GetMountInfoByID(id)
        calls.GetMountInfoByID = calls.GetMountInfoByID + 1
        local m = byId[id]
        if not m then return end
        if m.raw then return m.raw() end
        return m.name, 5000 + id, m.icon, m.active, m.usable, 1, m.favourite, false, nil, m.hide, m.collected, id
    end
    function j.SummonByID(id)
        calls.SummonByID = calls.SummonByID + 1
        j.summoned[#j.summoned + 1] = id
    end
    function j.Dismiss()
        calls.Dismiss = calls.Dismiss + 1
    end
    return j
end

local HORSE = function(o) return mount(11, "Brown Horse", o) end
local RAM = function(o) return mount(22, "Gray Ram", o) end
local WOLF = function(o) return mount(33, "Dire Wolf", o) end

-- A client with the addon loaded and a mount journal in it. o.mounted: what IsMounted answers.
-- o.on lists the features to switch on; o.quick = true switches the Quick slots row On.
local function new(mounts, o)
    o = o or {}
    local j = mounts and journal(mounts) or nil
    local world = { mounted = o.mounted or false }
    local c, PE = T.new({ on = o.on, savedChar = o.savedChar, setup = function(c)
        if j then rawset(c.env, "C_MountJournal", j) end
        rawset(c.env, "IsMounted", function() return world.mounted end)
    end })
    if o.quick then PE:GetModule("chat").opts.quickSlots = 1 end
    return c, PE, PE.QuickSlots, j, world
end

local function ids(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.id end
    return out
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

-- The visible buttons of the chat window.
local function buttons(c)
    local out = {}
    walk(c, panelOf(c), function(w)
        if c._state(w).type == "Button" and w:IsVisible() then out[#out + 1] = w end
    end)
    return out
end

-- The visible texts of the chat window (font strings anywhere under it).
local function texts(c)
    local out = {}
    walk(c, panelOf(c), function(w)
        for _, r in ipairs(c._state(w).regions) do
            local st = c._state(r)
            if st.type == "FontString" and r:IsVisible() and st.text and st.text ~= "" then out[st.text] = true end
        end
    end)
    return out
end

local function tapHub(c, PE)
    c:click(PE.Hub.button)
    c:advance(0.2)
end

-- The mount square: the one visible button of the window that carries the slot's picture.
local function square(c)
    for _, b in ipairs(buttons(c)) do
        if b.peSlotIcon then return b end
    end
    return nil
end

local function height(c, w)
    local _, _, t, b = c._rect(w)
    return t - b
end

local function stops(c)
    return #panelOf(c).peNavGet()
end

---------------------------------------------------------------------------
-- The list of owned mounts
---------------------------------------------------------------------------

test("quick slots: only owned mounts are listed, in the game's order", function()
    local _, _, QS = new()
    local j = journal({ WOLF(), HORSE({ collected = false }), RAM({ favourite = true }) })
    local list = QS.Mounts(j)
    eq(ids(list), { 33, 22 })
    eq(list[1].name, "Dire Wolf")
    eq(list[1].icon, 1033)
    eq(list[1].favourite, false)
    eq(list[2].favourite, true)
    eq(list[1].usable, true)
    eq(list[1].active, false)
end)

test("quick slots: a mount the game hides on this character is left out", function()
    local _, _, QS = new()
    eq(ids(QS.Mounts(journal({ HORSE({ hide = true }), RAM() }))), { 22 })
end)

-- Review Focus: a client where C_MountJournal or one of its functions is missing.
test("quick slots: no journal, or one without its two read functions, gives an empty list", function()
    local _, _, QS = new()
    eq(QS.Mounts(nil), {})
    eq(QS.Mounts({}), {})
    local j = journal({ HORSE() })
    eq(QS.Mounts({ GetMountIDs = j.GetMountIDs }), {})
    eq(QS.Mounts({ GetMountInfoByID = j.GetMountInfoByID }), {})
    eq(QS.Mounts({ GetMountIDs = function() error("refused") end, GetMountInfoByID = j.GetMountInfoByID }), {})
    eq(QS.Mounts({ GetMountIDs = function() return nil end, GetMountInfoByID = j.GetMountInfoByID }), {})
end)

-- Review Focus: GetMountInfoByID answering nil or a secret value for a field.
test("quick slots: a mount whose answer is nothing, or raises, is left out", function()
    local _, _, QS = new()
    local list = QS.Mounts(journal({
        mount(1, "Nothing", { raw = function() return end }),
        mount(2, "Raises", { raw = function() error("refused") end }),
        RAM(),
    }))
    eq(ids(list), { 22 })
end)

test("quick slots: nil fields mean not usable, not a favourite, not active; a nil name gets a plain one", function()
    local _, _, QS = new()
    local list = QS.Mounts(journal({
        mount(7, "x", { raw = function() return nil, 5007, nil, nil, nil, 1, nil, false, nil, nil, true, 7 end }),
    }))
    eq(#list, 1)
    eq(list[1].name, "Mount")
    eq(list[1].icon, nil)
    eq(list[1].usable, false)
    eq(list[1].favourite, false)
    eq(list[1].active, false)
end)

test("quick slots: secret fields mean not usable, not a favourite, not active, and are never joined", function()
    local c, _, QS = new()
    local list = QS.Mounts(journal({
        mount(7, "x", { raw = function()
            return c:secret("Hidden Horse"), 5007, c:secret(1234), c:secret(true), c:secret(true), 1, c:secret(true),
                false, nil, c:secret(false), true, 7
        end }),
        -- Owned or not is hidden too: not listed.
        mount(8, "y", { raw = function() return "Ghost", 5008, 1, false, true, 1, false, false, nil, false, c:secret(true), 8 end }),
    }))
    eq(#list, 1)
    eq(list[1].id, 7)
    eq(list[1].name, "Mount")
    eq(list[1].icon, nil)
    eq(list[1].usable, false)
    eq(list[1].favourite, false)
    eq(list[1].active, false)
    local state = QS.State(list[1], false, false)
    eq(state.label, "Mount")
    eq(state.greyed, true)
    c:assertClean("secret fields")
end)

test("quick slots: a hidden list of ids, or a hidden id in it, is skipped", function()
    local c, _, QS = new()
    local j = journal({ HORSE() })
    eq(QS.Mounts({ GetMountIDs = function() return c:secret({ 11 }) end, GetMountInfoByID = j.GetMountInfoByID }), {})
    eq(ids(QS.Mounts({ GetMountIDs = function() return { c:secret(11), 11, 0, "11" } end,
        GetMountInfoByID = j.GetMountInfoByID })), { 11 })
end)

---------------------------------------------------------------------------
-- Which mount
---------------------------------------------------------------------------

test("quick slots: Pick takes the saved mount when it is owned", function()
    local _, _, QS = new()
    local list = QS.Mounts(journal({ HORSE({ favourite = true }), RAM(), WOLF() }))
    local entry, isDefault = QS.Pick(list, 33)
    eq(entry.id, 33)
    eq(isDefault, false)
end)

test("quick slots: Pick's four fallbacks, in order", function()
    local _, _, QS = new()
    local function pick(mounts)
        local entry, isDefault = QS.Pick(QS.Mounts(journal(mounts)), nil)
        eq(isDefault, true)
        return entry and entry.id
    end
    -- 1. the first usable favourite, even after an unusable favourite and a usable plain one
    eq(pick({ HORSE(), RAM({ favourite = true, usable = false }), WOLF({ favourite = true }) }), 33)
    -- 2. else the first favourite
    eq(pick({ HORSE(), RAM({ favourite = true, usable = false }), WOLF({ favourite = true, usable = false }) }), 22)
    -- 3. else the first usable
    eq(pick({ HORSE({ usable = false }), RAM(), WOLF() }), 22)
    -- 4. else the first
    eq(pick({ HORSE({ usable = false }), RAM({ usable = false }) }), 11)
    -- none
    local entry, isDefault = QS.Pick({}, nil)
    eq(entry, nil)
    eq(isDefault, true)
end)

-- Review Focus: a saved mount id the character no longer owns.
test("quick slots: a saved mount that is not owned falls back to the first favourite and stays saved", function()
    local _, PE, QS, j = new({ HORSE(), RAM({ favourite = true }) }, { savedChar = { quickSlots = { mount = 999 } } })
    local entry, isDefault = QS.Pick(QS.Mounts(j), 999)
    eq(entry.id, 22)
    eq(isDefault, true)
    local state, picked = QS:Line()
    eq(picked.id, 22)
    eq(state.label, "Gray Ram")
    eq(QS:MountLabel(), "First favourite")
    eq(QS:Tap(), "summon")
    eq(j.summoned, { 22 })
    eq(PE.charDB.quickSlots.mount, 999, "the saved id was changed")
end)

test("quick slots: Next goes First favourite, each owned mount, and back, both ways", function()
    local _, _, QS = new()
    local list = QS.Mounts(journal({ HORSE(), RAM(), WOLF() }))
    eq(QS.Next(list, nil, 1), 11)
    eq(QS.Next(list, 11, 1), 22)
    eq(QS.Next(list, 22, 1), 33)
    eq(QS.Next(list, 33, 1), nil)
    eq(QS.Next(list, nil, -1), 33)
    eq(QS.Next(list, 33, -1), 22)
    eq(QS.Next(list, 22, -1), 11)
    eq(QS.Next(list, 11, -1), nil)
    -- A saved mount that is not owned counts as First favourite.
    eq(QS.Next(list, 999, 1), 11)
    eq(QS.Next(list, 999, -1), 33)
    eq(QS.Next({}, nil, 1), nil)
    eq(QS.Next({}, 11, -1), nil)
end)

---------------------------------------------------------------------------
-- What the square says
---------------------------------------------------------------------------

test("quick slots: State for a mount that can be used", function()
    local _, _, QS = new()
    local entry = QS.Mounts(journal({ HORSE() }))[1]
    eq(QS.State(entry, false, false), { icon = 1011, label = "Brown Horse", greyed = false, bright = false, action = "summon" })
end)

test("quick slots: State while mounted is bright, reads Get off and gets off", function()
    local _, _, QS = new()
    local entry = QS.Mounts(journal({ HORSE() }))[1]
    eq(QS.State(entry, true, false), { icon = 1011, label = "Get off", greyed = false, bright = true, action = "dismiss" })
end)

test("quick slots: State in a fight is greyed and its tap is the fight answer, mounted or not", function()
    local _, _, QS = new()
    local entry = QS.Mounts(journal({ HORSE() }))[1]
    local state = QS.State(entry, false, true)
    eq(state.greyed, true)
    eq(state.action, "combat")
    eq(state.label, "Brown Horse")
    state = QS.State(entry, true, true)
    eq(state.greyed, true)
    eq(state.action, "combat")
end)

test("quick slots: State for a mount that cannot be used here is greyed, and a tap still asks the game", function()
    local _, _, QS = new()
    local entry = QS.Mounts(journal({ HORSE({ usable = false }) }))[1]
    local state = QS.State(entry, false, false)
    eq(state.greyed, true)
    eq(state.bright, false)
    eq(state.action, "summon")
    eq(state.label, "Brown Horse")
end)

test("quick slots: State with no mount reads No mount yet and does nothing", function()
    local _, _, QS = new()
    for _, fight in ipairs({ false, true }) do
        eq(QS.State(nil, false, fight), { icon = nil, label = "No mount yet", greyed = true, bright = false, action = "none" })
    end
    eq(QS.State(nil, true, false).action, "none")
end)

---------------------------------------------------------------------------
-- The game: Line and Tap
---------------------------------------------------------------------------

-- Review Focus: a character with no mounts, or a client without the journal.
test("quick slots: with no journal in the game the line reads No mount yet and a tap does nothing", function()
    local c, PE, QS = new(nil)
    local state, entry = QS:Line()
    eq(entry, nil)
    eq(state.label, "No mount yet")
    eq(QS:Tap(), "none")
    eq(QS:MountLabel(), "No mount yet")
    QS:StepMount(1)
    eq(PE.charDB.quickSlots, nil, "a step with no mounts saved something")
    c:assertClean("no journal")
end)

test("quick slots: with no mount owned the line reads No mount yet and a tap calls nothing", function()
    local c, _, QS, j = new({ HORSE({ collected = false }) })
    local state = QS:Line()
    eq(state.label, "No mount yet")
    eq(QS:Tap(), "none")
    eq(j.calls.SummonByID + j.calls.Dismiss, 0)
    c:assertClean("no mounts")
end)

test("quick slots: a journal that can list but not summon answers 'missing' and raises nothing", function()
    local c, _, QS, j = new({ HORSE() })
    j.SummonByID, j.Dismiss = nil, nil
    eq(QS:Tap(), "missing")
    c:assertClean("no summon function")
end)

test("quick slots: a tap summons the picked mount by its id, never id 0", function()
    local c, _, QS, j = new({ HORSE(), RAM({ favourite = true }) })
    eq(QS:Tap(), "summon")
    eq(j.summoned, { 22 })
    eq(j.calls.Dismiss, 0)
    c:assertClean("summon")
end)

test("quick slots: a tap while mounted gets off, by IsMounted or by the mount's own answer", function()
    local c, _, QS, j = new({ HORSE() }, { mounted = true })
    eq(QS:Line().label, "Get off")
    eq(QS:Tap(), "dismiss")
    eq(j.calls.Dismiss, 1)
    eq(j.calls.SummonByID, 0)
    local c2, _, QS2, j2 = new({ HORSE({ active = true }) })
    eq(QS2:Tap(), "dismiss")
    eq(j2.calls.Dismiss, 1)
    c:assertClean("dismiss")
    c2:assertClean("dismiss by the mount's answer")
end)

test("quick slots: a hidden IsMounted answer counts as not mounted", function()
    local c, _, QS, j = new({ HORSE() })
    rawset(c.env, "IsMounted", function() return c:secret(true) end)
    eq(QS:Tap(), "summon")
    eq(j.summoned, { 11 })
    c:assertClean("hidden IsMounted")
end)

-- Review Focus: a tap in a fight makes no game call at all.
test("quick slots: a tap in a fight calls neither SummonByID nor Dismiss", function()
    for _, mounted in ipairs({ false, true }) do
        local c, _, QS, j = new({ HORSE() }, { mounted = mounted })
        c:enterCombat()
        eq(QS:Tap(), "combat")
        eq(j.calls.SummonByID, 0)
        eq(j.calls.Dismiss, 0)
        eq(j.calls.GetMountIDs, 0, "the journal was read by a tap in a fight")
        eq(j.calls.GetMountInfoByID, 0)
        c:assertClean("tap in a fight")
    end
end)

test("quick slots: an error inside the game's summon is caught and logged, not raised", function()
    local c, PE, QS, j = new({ HORSE() })
    j.SummonByID = function() error("the game said no") end
    eq(QS:Tap(), "summon")
    eq(#PE.errors, 1)
end)

---------------------------------------------------------------------------
-- The Mount row's value and steps (saved per character)
---------------------------------------------------------------------------

test("quick slots: the Mount row starts at First favourite and saves nothing until stepped", function()
    local _, PE, QS = new({ HORSE(), RAM() })
    eq(QS:MountLabel(), "First favourite")
    eq(PE.charDB.quickSlots, nil)
end)

test("quick slots: stepping the Mount row goes through the owned mounts and back, saved per character", function()
    local _, PE, QS, j = new({ HORSE(), RAM() })
    QS:StepMount(1)
    eq(PE.charDB.quickSlots.mount, 11)
    eq(QS:MountLabel(), "Brown Horse")
    QS:StepMount(1)
    eq(PE.charDB.quickSlots.mount, 22)
    eq(QS:MountLabel(), "Gray Ram")
    eq(QS:Tap(), "summon")
    eq(j.summoned, { 22 })
    QS:StepMount(1)
    eq(PE.charDB.quickSlots.mount, nil)
    eq(QS:MountLabel(), "First favourite")
    QS:StepMount(-1)
    eq(PE.charDB.quickSlots.mount, 22)
    -- Nothing of it is in the account-wide file.
    eq(PE:GetModule("chat").opts.mount, nil)
    eq(PE:GetModule("chat").opts.quickSlots, nil)
end)

test("quick slots: a damaged saved value reads as First favourite", function()
    for _, bad in ipairs({ "text", { mount = "22" }, { mount = -1 }, { mount = 0 } }) do
        local c, _, QS, j = new({ HORSE(), RAM() }, { savedChar = { quickSlots = bad } })
        eq(QS:MountLabel(), "First favourite")
        eq(QS:Tap(), "summon")
        eq(j.summoned, { 11 })
        c:assertClean("damaged saved value")
    end
end)

---------------------------------------------------------------------------
-- The line in the chat window
---------------------------------------------------------------------------

-- Plan, Task 2: with the row Off the window is exactly as before.
test("quick slots window: Off, the window has the same stops and height as with no journal at all", function()
    local c0, PE0 = new(nil, { on = { "chat" } })
    tapHub(c0, PE0)
    local c, PE, _, j = new({ HORSE() }, { on = { "chat" } })
    tapHub(c, PE)
    eq(stops(c), stops(c0))
    eq(height(c, panelOf(c)), height(c0, panelOf(c0)))
    eq(square(c), nil)
    eq(texts(c)["Quick slots"], nil)
    eq(j.calls.GetMountIDs, 0, "the journal was asked with the row Off")
    c:assertClean("row off")
end)

test("quick slots window: On, one more d-pad stop and the window is taller by the line", function()
    local c0, PE0 = new({ HORSE() }, { on = { "chat" } })
    tapHub(c0, PE0)
    local c, PE = new({ HORSE() }, { on = { "chat" }, quick = true })
    tapHub(c, PE)
    eq(stops(c), stops(c0) + 1)
    local M = PE.UI:Metrics()
    local head = M.smallFontSize * 1.15 + M.gap * 0.4
    local grew = height(c, panelOf(c)) - height(c0, panelOf(c0))
    check(math.abs(grew - (M.gap * 1.5 + head + M.button * 1.5)) < 1e-6, "the window grew by " .. tostring(grew))
    check(texts(c)["Quick slots"], "no Quick slots heading")
    check(texts(c)["Brown Horse"], "the mount's name is not shown")
    local b = square(c)
    check(b ~= nil, "no square")
    local l, r, t, bottom = c._rect(b)
    check(math.abs((r - l) - (t - bottom)) < 1e-6, "the square is not square")
    eq(c._state(b.peSlotIcon).texture, 1011)
    eq(b.peSelected, false)
    c:assertClean("row on")
end)

test("quick slots window: the square is the stop after the chat buttons and before Settings and Close", function()
    local c, PE = new({ HORSE() }, { on = { "chat" }, quick = true })
    tapHub(c, PE)
    local list = panelOf(c).peNavGet()
    local at
    for i, b in ipairs(list) do if b == square(c) then at = i end end
    check(at ~= nil, "the square is not a d-pad stop")
    eq(T.labelOf(list[at + 1]), "Settings")
    eq(T.labelOf(list[at + 2]), "Close")
    eq(#list, at + 2)
    check(list[at - 1].peChatTarget ~= nil or T.labelOf(list[at - 1]) == "Clear marks", "the stop before the square is not a chat button")
    -- It sits under every chat button.
    local _, _, top = c._rect(square(c))
    for i = 1, at - 1 do
        local _, _, _, bottom = c._rect(list[i])
        check(bottom >= top, "a chat button is not above the square")
    end
end)

test("quick slots window: a tap gets on the mount and closes the window", function()
    local c, PE, _, j = new({ HORSE(), RAM({ favourite = true }) }, { on = { "chat" }, quick = true })
    tapHub(c, PE)
    c:click(square(c))
    eq(j.summoned, { 22 })
    eq(j.calls.Dismiss, 0)
    eq(panelOf(c):IsShown(), false)
    c:assertClean("tap to mount")
end)

test("quick slots window: mounted, the square has the bright edge, reads Get off, and a tap gets off and closes", function()
    local c, PE, _, j = new({ HORSE() }, { on = { "chat" }, quick = true, mounted = true })
    tapHub(c, PE)
    eq(square(c).peSelected, true)
    check(texts(c)["Get off"], "the label does not read Get off")
    c:click(square(c))
    eq(j.calls.Dismiss, 1)
    eq(j.calls.SummonByID, 0)
    eq(panelOf(c):IsShown(), false)
    c:assertClean("tap to get off")
end)

-- Spec: "In a fight the square is greyed and a tap does nothing but say Not in a fight".
test("quick slots window: in a fight the square is greyed, a tap calls nothing, says so and leaves the window open", function()
    local c, PE, _, j = new({ HORSE() }, { on = { "chat" }, quick = true })
    c:enterCombat()
    tapHub(c, PE)
    local b = square(c)
    eq(b.peStyle, "disabled")
    eq(c._state(b.peSlotIcon).desaturated, true)
    c:click(b)
    eq(j.calls.SummonByID + j.calls.Dismiss, 0)
    eq(panelOf(c):IsShown(), true)
    check(texts(c)["Not in a fight"], "the window does not say Not in a fight")
    eq(#c.blocked, 0)
    c:assertClean("tap in a fight")
end)

test("quick slots window: a fight that starts while the window is open still stops the tap", function()
    local c, PE, _, j = new({ HORSE() }, { on = { "chat" }, quick = true })
    tapHub(c, PE)
    eq(square(c).peStyle, "normal")
    c:enterCombat()
    c:click(square(c))
    eq(j.calls.SummonByID + j.calls.Dismiss, 0)
    eq(panelOf(c):IsShown(), true)
    check(texts(c)["Not in a fight"], "the window does not say Not in a fight")
    eq(square(c).peStyle, "disabled")
    c:assertClean("fight started with the window open")
end)

test("quick slots window: a mount that cannot be used here is greyed and a tap still asks the game", function()
    local c, PE, _, j = new({ HORSE({ usable = false }) }, { on = { "chat" }, quick = true })
    tapHub(c, PE)
    eq(square(c).peStyle, "disabled")
    c:click(square(c))
    eq(j.summoned, { 11 })
    c:assertClean("unusable mount")
end)

-- Review Focus: no mounts, or no journal: "No mount yet", a tap does nothing, no error.
test("quick slots window: with no mount the square shows ? and No mount yet, and a tap does nothing", function()
    for _, mounts in ipairs({ false, {} }) do
        local c, PE, _, j = new(mounts or nil, { on = { "chat" }, quick = true })
        tapHub(c, PE)
        local b = square(c)
        check(b ~= nil, "no square")
        eq(T.labelOf(b), "?")
        eq(b.peSlotIcon:IsShown(), false)
        check(texts(c)["No mount yet"], "the label does not read No mount yet")
        c:click(b)
        eq(panelOf(c):IsShown(), true)
        if j then eq(j.calls.SummonByID + j.calls.Dismiss, 0) end
        c:assertClean("no mount")
    end
end)

test("quick slots window: opened again after getting on, the square is drawn anew", function()
    local c, PE, _, _, world = new({ HORSE() }, { on = { "chat" }, quick = true })
    tapHub(c, PE)
    c:click(square(c))
    world.mounted = true
    tapHub(c, PE)
    eq(square(c).peSelected, true)
    check(texts(c)["Get off"], "the label does not read Get off")
end)

-- Review Focus: Quick slots On with Chat picker Off: nothing is built.
test("quick slots window: On with Chat picker off, nothing is built and the journal is not asked by a tap on the round button", function()
    local c, PE, _, j = new({ HORSE() }, { quick = true })
    tapHub(c, PE)
    eq(panelOf(c), nil)
    c:advance(5)
    for _, rec in ipairs(c:frames()) do
        check(rec.addonFile ~= "QuickSlots.lua", "QuickSlots.lua made a frame")
    end
    eq(j.calls.SummonByID + j.calls.Dismiss, 0)
    eq(j.calls.GetMountIDs, 0)
    c:assertClean("chat picker off")
end)

-- The stand-in client's own journal (tests/lib/fakeclient.lua, world.mounts), end to end:
-- the calls are the logged ones, and a summon there really mounts.
test("quick slots window: with the stand-in's journal, two taps get on and two more get off", function()
    local c, PE = T.new({ on = { "chat" }, setup = function(c)
        c.world.mounts = { { id = 11, name = "Brown Horse" }, { id = 22, name = "Gray Ram", favourite = true } }
    end })
    PE:GetModule("chat").opts.quickSlots = 1
    tapHub(c, PE)
    check(texts(c)["Gray Ram"], "the favourite is not the one shown")
    c:click(square(c))
    eq(#c:callsTo("C_MountJournal.SummonByID"), 1)
    eq(c:callsTo("C_MountJournal.SummonByID")[1].args[1], 22)
    eq(c.world.mounted, 22)
    eq(panelOf(c):IsShown(), false)
    tapHub(c, PE)
    check(texts(c)["Get off"], "the label does not read Get off")
    c:click(square(c))
    eq(#c:callsTo("C_MountJournal.Dismiss"), 1)
    eq(#c:callsTo("C_MountJournal.SummonByID"), 1)
    eq(c.world.mounted, nil)
    eq(panelOf(c):IsShown(), false)
    c:assertClean("stand-in journal")
end)

---------------------------------------------------------------------------
-- The two settings rows
---------------------------------------------------------------------------

local function row(PE, label)
    for _, opt in ipairs(PE:GetModule("chat").options) do
        if opt.label == label then return opt end
    end
    error("no row " .. label, 2)
end

test("quick slots rows: Quick slots is Off / On, Off by default, and saves nothing until tapped", function()
    local _, PE = new({ HORSE() }, { on = { "chat" } })
    local mod, opt = PE:GetModule("chat"), row(PE, "Quick slots")
    eq(opt.choices, { { value = 0, label = "Off" }, { value = 1, label = "On" } })
    eq(opt.get(mod), 0)
    eq(mod.opts.quickSlots, nil)
    eq(opt.value(mod), nil)
    opt.set(mod, 1)
    eq(mod.opts.quickSlots, 1)
    eq(opt.get(mod), 1)
    opt.set(mod, 0)
    eq(opt.get(mod), 0)
end)

test("quick slots rows: with Chat picker off the Quick slots row is still drawn and says what it needs", function()
    local c, PE = new({ HORSE() })
    local mod, opt = PE:GetModule("chat"), row(PE, "Quick slots")
    eq(opt.always, true)
    eq(opt.value(mod), "Needs Chat picker")
    eq(row(PE, "Mount").always, nil)
    PE:OpenSettings("chat")
    c:advance(0.2)
    local found = false
    for _, rec in ipairs(c:frames()) do
        for _, r in ipairs(rec.regions) do
            local st = c._state(r)
            if st.type == "FontString" and r:IsVisible() and st.text == "Quick slots: Needs Chat picker" then found = true end
        end
    end
    check(found, "the settings do not show 'Quick slots: Needs Chat picker'")
    c:assertClean("row with chat picker off")
end)

test("quick slots rows: switching the row On redraws an open window with the square, Off takes it away", function()
    local c, PE = new({ HORSE() }, { on = { "chat" } })
    tapHub(c, PE)
    local before = stops(c)
    local mod, opt = PE:GetModule("chat"), row(PE, "Quick slots")
    opt.set(mod, 1)
    eq(stops(c), before + 1)
    check(square(c) ~= nil, "no square after On")
    opt.set(mod, 0)
    eq(stops(c), before)
    eq(square(c), nil)
    eq(texts(c)["Quick slots"], nil)
    c:assertClean("row toggled")
end)

test("quick slots rows: Mount shows the choice between - and +, and each end steps it", function()
    local _, PE = new({ HORSE(), RAM({ favourite = true }) }, { on = { "chat" }, quick = true })
    local mod, opt = PE:GetModule("chat"), row(PE, "Mount")
    eq(opt.value(mod), nil)
    local box = opt.stepper(mod)
    eq(box.text, "First favourite")
    eq(box.unit, "Gray Ram")
    box.up()
    box = opt.stepper(mod)
    eq(box.text, "Brown Horse")
    eq(box.unit, "1 of 2")
    eq(PE.charDB.quickSlots.mount, 11)
    box.down()
    eq(opt.stepper(mod).text, "First favourite")
    box.down()
    eq(opt.stepper(mod).text, "Gray Ram")
    eq(opt.stepper(mod).unit, "2 of 2")
end)

-- After the review: with Quick slots Off the settings do not read the journal.
test("quick slots rows: with Quick slots Off the Mount row says to turn it on and the journal is not read", function()
    local c, PE, _, j = new({ HORSE() }, { on = { "chat" } })
    local mod, opt = PE:GetModule("chat"), row(PE, "Mount")
    eq(opt.stepper(mod), { text = "Turn Quick slots on", downDim = true, upDim = true })
    PE:OpenSettings("chat")
    c:advance(0.2)
    eq(j.calls.GetMountIDs, 0)
    eq(j.calls.GetMountInfoByID, 0)
    c:assertClean("mount row with quick slots off")
end)

test("quick slots rows: with no mount the Mount row reads No mount yet between two dim ends", function()
    for _, mounts in ipairs({ false, {} }) do
        local c, PE = new(mounts or nil, { on = { "chat" }, quick = true })
        local mod, opt = PE:GetModule("chat"), row(PE, "Mount")
        eq(opt.value(mod), nil)
        eq(opt.stepper(mod), { text = "No mount yet", downDim = true, upDim = true })
        PE:OpenSettings("chat")
        c:advance(0.2)
        c:assertClean("mount row with no mount")
    end
end)

test("quick slots rows: both rows are left out of the setup guide", function()
    local c, PE = new({ HORSE() }, { on = { "chat" }, quick = true })
    eq(row(PE, "Quick slots").guide, false)
    eq(row(PE, "Mount").guide, false)
    PE.Setup:Open()
    c:advance(0.2)
    local guide = rawget(c.env, "PocketEssentialsSetupPanel")
    check(guide and guide:IsShown(), "the setup guide is not open")
    for _ = 1, 12 do
        walk(c, guide, function(w)
            for _, r in ipairs(c._state(w).regions) do
                local st = c._state(r)
                if st.type == "FontString" and r:IsVisible() and st.text then
                    check(st.text:sub(1, 11) ~= "Quick slots" and st.text:sub(1, 5) ~= "Mount", "the guide shows " .. st.text)
                end
            end
        end)
        local nextButton
        walk(c, guide, function(w)
            if c._state(w).type == "Button" and w:IsVisible() and T.labelOf(w) == "Next" then nextButton = w end
        end)
        if not nextButton then break end
        c:click(nextButton)
        c:advance(0.1)
    end
    c:assertClean("guide without the rows")
end)

test("quick slots rows: the settings draw both rows with Chat picker on and a mount owned, without error", function()
    local c, PE = new({ HORSE() }, { on = { "chat" }, quick = true })
    PE:OpenSettings("chat")
    c:advance(0.2)
    c:assertClean("settings with both rows")
end)

---------------------------------------------------------------------------
-- No event, no tick
---------------------------------------------------------------------------

test("quick slots: the file makes no frame and registers no event, On or Off", function()
    local c, PE = new({ HORSE() }, { on = { "chat" }, quick = true })
    tapHub(c, PE)
    for _, rec in ipairs(c:frames()) do
        check(rec.addonFile ~= "QuickSlots.lua", "QuickSlots.lua made a frame")
    end
    c:assertClean("no frames")
end)

test("quick slots: nothing is asked of the journal while the window is closed", function()
    local c, _, _, j = new({ HORSE() }, { on = { "chat" }, quick = true })
    c:advance(30)
    c:enterCombat()
    c:leaveCombat()
    c:advance(30)
    eq(j.calls.GetMountIDs, 0)
    eq(j.calls.GetMountInfoByID, 0)
end)

return { known = KNOWN_FAILURES }
