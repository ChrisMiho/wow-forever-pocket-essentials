-- Rules for "Bag sorter" (Bags.lua).
-- Sources: Bags.lua's header and comments; docs/DECISIONS.md, part "Bags" of
-- "Decisions made without the maintainer". Each test names its source in a comment.
-- Fresh client and addon per test.
--
-- Differences from the task brief (the documents win): DECISIONS says only that
-- "L3 sorts only while the bag is open and never during combat"; the brief said the
-- Sort button too, which the documents do not say (see the Sort-in-combat test).
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local function newBags(opts)
    opts = opts or {}
    return T.new({ on = { "bags" }, gamepadUI = opts.gamepadUI, setup = function(c)
        c.world.cvars.combinedBags = opts.cvar or "0"
        if opts.setup then opts.setup(c) end
    end })
end

local function sortButton(c)
    local rec = c:find(function(r) return r.addonFile ~= nil and r.type == "Button" and T.labelOf(r.frame) == "Sort"
        and r.frame:GetParent() == c.UIParent end)
    check(rec, "no Sort button was made")
    return rec.frame
end

local function keyButton(c)
    local k = rawget(c.env, "PocketEssentialsBagSortKey")
    check(k, "no hidden key button was made")
    return k
end

local function bindings(c) return c._state(keyButton(c)).bindings end

local function sorts(c) return #c:callsTo("C_Container.SortBags") end
local function cvarWrites(c) return c:callsTo("C_CVar.SetCVar") end

---------------------------------------------------------------------------
-- Sort button and L3
---------------------------------------------------------------------------

-- Bags.lua DoSort: "if not active or not BagShown() then return end"; SyncButton shows the
-- button only while the bag is visible.
test("bags: the Sort button is shown while the bag is open and hidden when it closes", function()
    local c = newBags()
    local btn = sortButton(c)
    check(not btn:IsVisible(), "button visible with the bag closed")
    c:openBag()
    check(btn:IsVisible(), "button not visible with the bag open")
    c:closeBag()
    check(not btn:IsVisible(), "button still visible after the bag closed")
end)

-- Spec 2026-11-16-vertical-sort-tab: a tab flush against the bag's left edge (TOPRIGHT of the
-- tab on TOPLEFT of the bag, no gap). Not a child of the bag (header: children of UIParent).
test("bags: the Sort tab sits against the bag's left edge and is a child of UIParent, not of the bag", function()
    local c = newBags()
    c:openBag()
    local btn = sortButton(c)
    eq(btn:GetParent(), c.UIParent, "parent")
    local point, rel, relPoint, x = btn:GetPoint(1)
    eq({ point, rel, relPoint, x }, { "TOPRIGHT", c.bagFrame, "TOPLEFT", 0 })
end)

-- Spec 2026-11-16-vertical-sort-tab: tall and narrow, at least three button heights tall.
test("bags: the Sort tab is a tall, narrow tab", function()
    local c = newBags()
    c:openBag()
    local btn = sortButton(c)
    check(btn:GetHeight() > btn:GetWidth() * 2,
        "tab not tall and narrow: " .. btn:GetWidth() .. " x " .. btn:GetHeight())
end)

local function chooseOption(c, key, value)
    local mod = c.PE:GetModule("bags")
    mod.opts[key] = value
    for _, opt in ipairs(mod.options) do
        if opt.key == key then opt.OnChange(mod, value) end
    end
    c:advance(0.5)
end

-- Spec 2026-11-16-vertical-sort-tab, "Sort button" choice: shown by default; hidden, the stick
-- click still sorts; shown again, the tab comes back with the bag open.
test("bags: the Sort button choice hides the tab, the left stick still sorts, and Show brings it back", function()
    local c = newBags()
    c:openBag()
    local btn = sortButton(c)
    check(btn:IsVisible(), "tab not shown by default")
    chooseOption(c, "showTab", false)
    check(not btn:IsVisible(), "tab still visible after Hide")
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:closeBag()
    c:openBag()
    check(not btn:IsVisible(), "tab came back on reopening while hidden")
    chooseOption(c, "showTab", true)
    check(btn:IsVisible(), "tab not shown again after Show")
end)

-- Bags.lua OnSortTapped -> DoSort: one C_Container.SortBags per tap while the bag is open.
test("bags: tapping Sort with the bag open calls SortBags once", function()
    local c = newBags()
    c:openBag()
    c:click(sortButton(c))
    eq(sorts(c), 1)
    c:assertClean("sort tap")
end)

-- DECISIONS "Bags": "L3 sorts only while the bag is open"; Bags.lua DoSort first line.
test("bags: a tap that reaches the Sort button with the bag closed does nothing", function()
    local c = newBags()
    local btn = sortButton(c)
    c:script(btn, "OnClick", "LeftButton", false)   -- a stale tap: the button is hidden
    eq(sorts(c), 0)
    c:openBag()
    c:closeBag()
    c:script(btn, "OnClick", "LeftButton", false)
    eq(sorts(c), 0)
end)

-- Bags.lua header + ApplyBinding: PADLSTICK is pointed at the hidden key button only while
-- the bag is open (and out of combat).
test("bags: the left stick click is bound to the key button only while the bag is open", function()
    local c = newBags()
    eq(bindings(c), nil, "bound before the bag opened")
    c:openBag()
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:closeBag()
    eq(bindings(c), nil, "still bound after the bag closed")
end)

-- DECISIONS "Bags": "L3 sorts only while the bag is open"; Bags.lua OnSortKey (key up sorts).
test("bags: L3 (key up) sorts once with the bag open; key down does nothing", function()
    local c = newBags()
    c:openBag()
    local key = keyButton(c)
    c:script(key, "OnClick", "LeftButton", true)    -- down
    eq(sorts(c), 0, "sorted on key down")
    c:script(key, "OnClick", "LeftButton", false)   -- up
    eq(sorts(c), 1)
    c:assertClean("L3")
end)

-- DECISIONS "Bags": L3 "never during combat"; Bags.lua OnCombatStart: the binding is handed back
-- to the game when combat starts (the game's own left-stick action, auto-run, gets it).
test("bags: starting combat releases the left stick click; leaving combat takes it back (bag still open)", function()
    local c = newBags()
    c:openBag()
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:enterCombat()
    eq(bindings(c), nil, "binding kept in combat")
    c:advance(1)
    c:leaveCombat()
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:assertClean("combat")
end)

test("bags: the bag opened during combat gets no left stick binding until the fight ends", function()
    local c = newBags()
    c:enterCombat()
    c:openBag()
    eq(bindings(c), nil, "bound in combat")
    c:leaveCombat()
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:assertClean("combat open")
end)

-- Bags.lua DoSort comment "same as Blizzard's own Clean Up button: a sound, then SortBags"; DECISIONS
-- "Bags" limits only L3 in combat. Blizzard's Clean Up button calls C_Container.SortBags() with no combat
-- check (ContainerFrame.lua:740, ContainerFrame.xml:373 in wow-ui-source `forever`), so a tap on the Sort
-- button with the bag open sorts, in or out of combat.
test("bags: tapping Sort with the bag open sorts in combat too, like Blizzard's Clean Up button", function()
    local c = newBags()
    c:openBag()
    c:enterCombat()
    c:click(sortButton(c))
    eq(sorts(c), 1)
end)

---------------------------------------------------------------------------
-- The "combinedBags" setting
---------------------------------------------------------------------------

-- DECISIONS "Bags": "With the Gamepad UI on, the game already forces the combined bag, so nothing
-- is changed at all." Bags.lua WantCombined / OnLogout.
test("bags: with the Gamepad UI on nothing is written to combinedBags and no reload is asked for", function()
    local c, PE = newBags({ gamepadUI = true })
    c:openBag()
    c:advance(2)
    c:fire("PLAYER_LOGOUT")
    eq(#cvarWrites(c), 0)
    eq(c.world.cvars.combinedBags, "0")
    eq(PE.reloadReasons, {})
    c:assertClean("gamepad on")
end)

-- DECISIONS "Bags": "With it off, the change is written at logout/reload and the panel shows
-- 'Reload now'"; "never changed mid-session". Bags.lua header, WantCombined, OnLogout.
test("bags: with the Gamepad UI off combinedBags is not written during the session, a reload is asked for", function()
    local c, PE = newBags()
    c:openBag()
    c:advance(2)
    eq(#cvarWrites(c), 0, "written mid-session")
    eq(c.world.cvars.combinedBags, "0")
    eq(#PE.reloadReasons, 1)
    eq(PE.reloadReasons[1].key, "bags")
    eq(PE.reloadReasons[1].reason, "Reload to finish changing the bags.")
end)

test("bags: with the Gamepad UI off combinedBags is written once, to 1, at logout", function()
    local c = newBags()
    c:advance(1)
    c:fire("PLAYER_LOGOUT")
    local writes = cvarWrites(c)
    eq(#writes, 1)
    eq({ writes[1].args[1], writes[1].args[2] }, { "combinedBags", "1" })
    eq(c.world.cvars.combinedBags, "1")
end)

test("bags: when the bag is already combined nothing is written and no reload is asked for", function()
    local c, PE = newBags({ cvar = "1" })
    c:advance(1)
    c:fire("PLAYER_LOGOUT")
    eq(#cvarWrites(c), 0)
    eq(PE.reloadReasons, {})
end)

-- DECISIONS "Bags": "If the player switches back to separate bags in the game's own menu, the
-- feature respects that." Bags.lua WantCombined (sawCombined / userSeparate) and Status.
test("bags: if the player switches back to separate bags the feature leaves it", function()
    local c, PE = newBags({ cvar = "1" })
    c:advance(1)
    eq(PE.reloadReasons, {})
    c.world.cvars.combinedBags = "0"                       -- the player's choice in the bag menu
    c:fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 0)      -- the next time the feature looks (1 s later)
    c:advance(1.5)
    c:fire("PLAYER_LOGOUT")
    eq(#cvarWrites(c), 0, "wrote the setting back")
    eq(c.world.cvars.combinedBags, "0")
    eq(PE.reloadReasons, {}, "asked for a reload")
    eq(PE:GetModule("bags"):IsEnabled(), true)
    local status = PE:GetModule("bags").status(PE:GetModule("bags"))
    eq(status, "You switched back to separate bags in the game's bag menu.")
end)

---------------------------------------------------------------------------
-- Bag size
---------------------------------------------------------------------------

local function scaleAfterOpen(size, bagHeight)
    local c = newBags({ gamepadUI = true, setup = function(c)
        if bagHeight then c.bagFrame:SetSize(388, bagHeight) end
    end })
    local PE = c.PE
    PE:GetModule("bags").opts.size = size
    c:openBag()
    c:advance(0.5)
    return c, c.bagFrame:GetScale()
end

-- Bags.lua SIZE_FACTOR: normal 1, large 1.25, xlarge 1.5 (times the game's own scale).
test("bags: the bag size choices scale the bag by 1, 1.25 and 1.5 times the game's own", function()
    local _, normal = scaleAfterOpen("normal")
    local _, large = scaleAfterOpen("large")
    local _, xlarge = scaleAfterOpen("xlarge")
    eq({ normal, large, xlarge }, { 1, 1.25, 1.5 })
end)

-- DECISIONS "Bags": "Bag size never goes below the game's own size; 'Extra large' may equal 'Large'
-- when the bag is already as tall as the screen." Bags.lua ApplyScaleNow ("target < base.scale").
test("bags: the bag scale never goes below the game's own, even when the bag is too tall for the screen", function()
    local c, scale = scaleAfterOpen("xlarge", 900)    -- 900 tall in a 768-tall screen
    check(scale >= 1 - 1e-9, "scale went below the game's own: " .. scale)
    eq(scale, 1)
end)

-- DECISIONS "Bags": "'Extra large' may equal 'Large' when the bag is already as tall as the screen."
test("bags: a tall bag is made as big as the screen allows and no bigger", function()
    local c, scale = scaleAfterOpen("xlarge", 600)    -- fits 1.5x? 600*1.5 = 900 > room: clamped between 1 and 1.5
    check(scale > 1 and scale < 1.5, "expected a scale between 1 and 1.5, got " .. scale)
    local top = c.bagFrame:GetTop()
    check(top <= 768 + 0.5, "the bag's top is off the screen: " .. tostring(top))
end)

-- Spec 2026-11-16-vertical-sort-tab: about half the bag's height on screen. Changing Bag size with
-- the bag open (option OnChange -> SyncScale) must resize the tab too, not only the bag.
test("bags: the Sort tab grows with the bag when Bag size changes while it is open", function()
    local c = scaleAfterOpen("normal", 500)
    local mod = c.PE:GetModule("bags")
    local btn = sortButton(c)
    local before = btn:GetHeight()
    mod.opts.size = "large"
    for _, opt in ipairs(mod.options) do
        if opt.key == "size" then opt.OnChange(mod, "large") end
    end
    c:advance(0.5)
    eq(c.bagFrame:GetScale(), 1.25)
    local after = btn:GetHeight()
    check(math.abs(after - before * 1.25) < 0.5,
        "tab height did not follow the bag: " .. before .. " -> " .. after)
end)

-- Bags.lua OnDisable -> RestoreScaleNow: puts back exactly what Blizzard's layout pass set.
test("bags: switching the feature off puts the game's own scale back", function()
    local c, scale = scaleAfterOpen("large")
    eq(scale, 1.25)
    c.PE:SetModuleEnabled("bags", false)
    c:advance(0.5)
    eq(c.bagFrame:GetScale(), 1)
    local point, _, relPoint, x, y = c.bagFrame:GetPoint(1)
    eq({ point, relPoint, x, y }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 4, 85 })
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

-- Spec 2026-11-17-debug-log, row "Bag sorter": combined or not and why; Sort pressed.
test("debug log: switching the bags on and tapping Sort writes why and what was pressed", function()
    local c = newBags({ cvar = "1" })
    c.PE:SetDebug(true)
    c.PE:SetModuleEnabled("bags", false)
    c.PE:SetModuleEnabled("bags", true)
    c:openBag()
    c:click(sortButton(c))
    local lines = debugLines(c, "bags")
    local seen = {}
    for _, line in ipairs(lines) do seen[line] = true end
    for _, want in ipairs({ "combined: the setting is already on", "Sort pressed: the tab", "sorting" }) do
        check(seen[want], "no line \"" .. want .. "\" in: " .. table.concat(lines, " / "))
    end
    eq(sorts(c), 1)
end)

---------------------------------------------------------------------------
-- Bag sorter: name and sort key choice (spec 2026-11-17-post-0.0.9-batch, item 2)
---------------------------------------------------------------------------

local function textsOf(c)
    local mod = c.PE:GetModule("bags")
    local out = { mod.label, mod.desc }
    local status = mod.status(mod)
    if type(status) == "string" then out[#out + 1] = status
    elseif type(status) == "table" then for _, l in ipairs(status) do out[#out + 1] = l end end
    return out
end

test("bags: the feature is called Bag sorter and no text of it says One big bag", function()
    for _, gamepad in ipairs({ true, false }) do
        local c = newBags({ gamepadUI = gamepad })
        local mod = c.PE:GetModule("bags")
        eq(mod.label, "Bag sorter")
        eq(mod.desc, "Sort your bags with a big button or a stick click.")
        eq(mod.key, "bags")
        for _, text in ipairs(textsOf(c)) do
            check(not text:lower():find("big bag", 1, true), "old name in: " .. text)
        end
    end
    local c = newBags({ cvar = "0" })
    c:advance(1)
    local status = c.PE:GetModule("bags").status(c.PE:GetModule("bags"))
    check(not tostring(status):lower():find("one big bag", 1, true), "old name in status")
end)

test("bags: Sort key is an option with three choices, left stick click first", function()
    local c = newBags()
    local mod = c.PE:GetModule("bags")
    local opt
    for _, o in ipairs(mod.options) do if o.key == "sortKey" then opt = o end end
    check(opt, "no sortKey option")
    eq(opt.label, "Sort key")
    local got = {}
    for _, ch in ipairs(opt.choices) do got[#got + 1] = ch.value .. "=" .. ch.label end
    eq(got, { "l3=Left stick click", "r3=Right stick click", "none=Button only" })
    eq(mod.opts.sortKey, "l3")
end)

test("bags: each Sort key choice binds the right key on open and clears it on close, tab always there", function()
    for value, want in pairs({ l3 = "PADLSTICK", r3 = "PADRSTICK", none = false }) do
        local c = newBags({ setup = function(cc) end })
        c.PE:GetModule("bags").opts.sortKey = value
        c:openBag()
        if want then
            eq(bindings(c), { [want] = "PocketEssentialsBagSortKey" }, value)
        else
            eq(bindings(c), nil, value)
        end
        check(sortButton(c):IsVisible(), "tab missing for " .. value)
        c:closeBag()
        eq(bindings(c), nil, "still bound after close: " .. value)
    end
end)

test("bags: changing Sort key with the bag open hands back the old stick and takes the new one", function()
    local c = newBags()
    c:openBag()
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    chooseOption(c, "sortKey", "r3")
    eq(bindings(c), { PADRSTICK = "PocketEssentialsBagSortKey" })
    chooseOption(c, "sortKey", "none")
    eq(bindings(c), nil)
    chooseOption(c, "sortKey", "l3")
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
end)

test("bags: changing Sort key in a fight waits for the fight to end", function()
    local c = newBags()
    c:openBag()
    c:enterCombat()
    chooseOption(c, "sortKey", "r3")
    eq(bindings(c), nil, "bound in combat")
    c:leaveCombat()
    eq(bindings(c), { PADRSTICK = "PocketEssentialsBagSortKey" })
end)

test("bags: a 0.0.9 saved table has no sortKey and binds the left stick; an unknown value reads as left", function()
    local c = newBags()
    local mod = c.PE:GetModule("bags")
    mod.opts.sortKey = nil
    c:openBag()
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:closeBag()
    mod.opts.sortKey = "bogus"
    c:openBag()
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    -- OnLoad also repairs it.
    mod.opts.sortKey = "bogus"
    mod:OnLoad()
    eq(mod.opts.sortKey, "l3")
end)

test("bags: switching the feature off hands the chosen stick back", function()
    local c = newBags()
    c.PE:GetModule("bags").opts.sortKey = "r3"
    c:openBag()
    eq(bindings(c), { PADRSTICK = "PocketEssentialsBagSortKey" })
    c.PE:SetModuleEnabled("bags", false)
    c:advance(0.5)
    eq(bindings(c), nil)
end)

test("debug log: the sort key choice writes which stick was taken, given back, or none taken", function()
    local c = newBags()
    c.PE:SetDebug(true)
    c:openBag()
    chooseOption(c, "sortKey", "r3")
    chooseOption(c, "sortKey", "none")
    c:closeBag()
    local seen = {}
    for _, line in ipairs(debugLines(c, "bags")) do seen[line] = true end
    for _, want in ipairs({ "left stick click taken for Sort (bag open)", "right stick click taken for Sort (bag open)",
        "no stick taken: button only", "stick click given back to the game" }) do
        check(seen[want], "no line \"" .. want .. "\"")
    end
end)

return { known = KNOWN_FAILURES }
