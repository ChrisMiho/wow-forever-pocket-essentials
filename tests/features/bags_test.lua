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

-- Device log, 0.1.0: "stick click given back to the game" was written at every fight although
-- no stick had been taken. A line is only written when something really changed hands.
local function count(c, text)
    local n = 0
    for _, line in ipairs(debugLines(c, "bags")) do if line == text then n = n + 1 end end
    return n
end

test("debug log: fights with the bag closed write no stick lines", function()
    local c = newBags()
    c.PE:SetDebug(true)
    c:advance(0.5)
    local before = #debugLines(c, "bags")
    for _ = 1, 3 do
        c:enterCombat()
        c:advance(1)
        c:leaveCombat()
        c:advance(1)
    end
    eq(#debugLines(c, "bags") - before, 0, "lines written by three fights with nothing taken")
    eq(count(c, "stick click given back to the game"), 0)
end)

test("debug log: a stick taken and handed back writes one line each, also across a fight", function()
    local c = newBags()
    c.PE:SetDebug(true)
    c:openBag()
    eq(count(c, "left stick click taken for Sort (bag open)"), 1)
    c:enterCombat()                 -- handed back as the fight starts
    c:advance(1)
    eq(count(c, "stick click given back to the game"), 1)
    eq(bindings(c), nil)
    c:leaveCombat()                 -- the bag is still open: taken again
    c:advance(1)
    eq(count(c, "left stick click taken for Sort (bag open)"), 2)
    c:closeBag()
    c:advance(0.5)
    eq(count(c, "stick click given back to the game"), 2)
    c:closeBag()
    c:enterCombat()
    c:advance(1)
    c:leaveCombat()
    c:advance(1)
    eq(count(c, "stick click given back to the game"), 2, "nothing was taken any more")
end)

test("debug log: Button only says so once per bag opening, not after every fight", function()
    local c = newBags()
    c.PE:GetModule("bags").opts.sortKey = "none"
    c.PE:SetDebug(true)
    c:openBag()
    c:enterCombat()
    c:advance(1)
    c:leaveCombat()
    c:advance(1)
    eq(count(c, "no stick taken: button only"), 1)
    eq(count(c, "stick click given back to the game"), 0)
end)

---------------------------------------------------------------------------
-- D-pad to Sort (spec 2026-11-17-0.4.0-handheld-batch, part 3; plan Task 3)
--
-- The stand-in's cursor follows the one rule the design leans on: a jump override that is a
-- visible frame takes the cursor there (c:padMove). Whether the game's own A binding or ours
-- wins on the device cannot be shown here.
---------------------------------------------------------------------------

local LEFT, RIGHT = "smartNavigationOverride-left", "smartNavigationOverride-right"
local NAV_ADD, NAV_CLEAR = "SmartNavigation_AddJumpNavigationOverride", "SmartNavigation_ClearJumpNavigationOverridesInDirection"
local CONFIRM = "PocketEssentialsBagSortConfirm"

-- Gamepad UI on, a bag of 4 columns by 3 rows, "D-pad to Sort" on (o.dpad = false: left as shipped).
local function newPad(o)
    o = o or {}
    local gamepad = o.gamepadUI ~= false
    local c = newBags({ gamepadUI = gamepad, setup = o.setup })
    local grid = not o.noItems and c:fillBag(4, 3) or nil
    if o.dpad ~= false then c.PE:GetModule("bags").opts.dpad = true end
    if o.debug then c.PE:SetDebug(true) end
    return c, grid
end

local function confirmButton(c)
    local b = rawget(c.env, CONFIRM)
    check(b, "no hidden confirm button was made")
    return b
end
local function confirmBindings(c) return c._state(confirmButton(c)).bindings end
local function setterCalls(c) return #c:callsTo(NAV_ADD) + #c:callsTo(NAV_CLEAR) end
local function layoutPass(c) c._protect("UpdateContainerFrameAnchors", c.env.UpdateContainerFrameAnchors) end

-- Frames are compared by identity (eq would walk into them, and a jump there and back is a loop).
local function is(actual, expected, msg)
    if not rawequal(actual, expected) then
        error((msg and (msg .. ": ") or "") .. "expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- Every item button of the grid that has a Left jump, as "col,row" = "tab" (our Sort tab) or
-- the target's name.
local function leftJumps(grid, tab)
    local out = {}
    for col = 1, #grid do
        for row = 1, #grid[col] do
            local v = rawget(grid[col][row], LEFT)
            if v ~= nil then out[col .. "," .. row] = rawequal(v, tab) and "tab" or tostring(v) end
        end
    end
    return out
end

local FIRST_COLUMN = { ["1,1"] = "tab", ["1,2"] = "tab", ["1,3"] = "tab" }

local function hasLine(c, text)
    for _, line in ipairs(debugLines(c, "bags")) do if line == text then return true end end
    return false
end

local function eventRegistered(c, event) return #c:_eventOrder(event) > 0 end

-- Moves the cursor from the first column onto the tab and lets the one-frame timer run.
local function focusTab(c, grid)
    local got = c:padMove(grid[1][1], "left")
    is(got, sortButton(c), "Left from the first column did not reach the Sort tab")
    c:advance(0.1)
    return got
end

-- 1. Spec part 3: "New choice ... Off (default)".
test("d-pad to Sort: off by default, nothing is put on any item button", function()
    local c, grid = newPad({ dpad = false })
    eq(c.PE:GetModule("bags").opts.dpad, false)
    c:openBag()
    c:advance(0.5)
    eq(setterCalls(c), 0)
    eq(leftJumps(grid, sortButton(c)), {})
    is(rawget(sortButton(c), RIGHT), nil)
    c:assertClean("default")
end)

test("d-pad to Sort: it is a choice of Bag sorter with Off first, and a broken saved value reads as Off", function()
    local c = newPad({ dpad = false })
    local mod = c.PE:GetModule("bags")
    local opt
    for _, o in ipairs(mod.options) do if o.key == "dpad" then opt = o end end
    check(opt, "no dpad option")
    eq(opt.label, "D-pad to Sort")
    eq({ opt.choices[1].value, opt.choices[1].label, opt.choices[2].value, opt.choices[2].label }, { false, "Off", true, "On" })
    mod.opts.dpad = "yes"
    mod:OnLoad()
    eq(mod.opts.dpad, false)
end)

-- 2. Spec: "pressing Left ... from any item in the bag's first (leftmost) column".
test("d-pad to Sort: the Left jump is put on the first column only, and points at the Sort tab", function()
    local c, grid = newPad()
    c:openBag()
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN)
    is(c:padMove(grid[1][2], "left"), sortButton(c))
    is(c:padMove(grid[2][2], "left"), nil, "a second-column slot leads to the tab")
    c:assertClean("route")
end)

-- 3. Plan, rejected routes: "Only ever pass a frame." (The stand-in also records an error for a function.)
test("d-pad to Sort: every jump target handed to the game is a frame, never a function", function()
    local c, grid = newPad()
    c:openBag()
    grid[1][1]:Hide()
    layoutPass(c)
    chooseOption(c, "dpad", false)
    local calls = c:callsTo(NAV_ADD)
    check(#calls >= 4, "expected the setter to have been called, got " .. #calls)
    for _, call in ipairs(calls) do
        check(c._isWidget(call.args[1]), "the button is not a frame")
        check(type(call.args[2]) == "table" and type(call.args[2].dirKey) == "string", "the direction is not one of the game's")
        check(c._isWidget(call.args[3]), "the target is not a frame: " .. type(call.args[3]))
    end
    for _, call in ipairs(c:callsTo(NAV_CLEAR)) do
        check(c._isWidget(call.args[1]), "the cleared button is not a frame")
        eq(call.args.n, 2, "arguments to the clear call")
    end
    c:assertClean("targets")
end)

-- 4. Spec: "Right goes back into the bag (to the first-column slot level with the middle of the tab)".
test("d-pad to Sort: Right from the tab goes back to the first-column slot nearest the tab's middle", function()
    local c, grid = newPad()
    c:openBag()
    local tab = sortButton(c)
    local function midY(w) local _, _, t, b = c._rect(w) return (t + b) / 2 end
    local want, gap
    for row = 1, 3 do
        local g = math.abs(midY(grid[1][row]) - midY(tab))
        if not gap or g < gap then want, gap = grid[1][row], g end
    end
    is(rawget(tab, RIGHT), want)
    focusTab(c, grid)
    is(c:padMove(tab, "right"), want)
end)

-- 5. Bags.lua header: "we still never write a field ourselves"; nothing else of the bag is touched.
test("d-pad to Sort: the only thing added to an item button is the Left jump, and the bag is set no differently", function()
    local function bagSets(c)
        local n = 0
        for _, call in ipairs(c.calls) do
            if call.name:find("^ContainerFrameCombinedBags:") then n = n + 1 end
        end
        return n
    end
    local off, offGrid = newPad({ dpad = false })
    off:openBag()
    off:advance(0.5)
    local on, grid = newPad()
    on:openBag()
    on:advance(0.5)
    eq(bagSets(on), bagSets(off), "calls on the bag frame")
    for col = 1, 4 do
        for row = 1, 3 do
            for k in pairs(grid[col][row]) do
                check(col == 1 and k == LEFT, "field " .. tostring(k) .. " written on item button " .. col .. "," .. row)
            end
            eq(next(offGrid[col][row]), nil)
        end
    end
    eq(rawget(on.bagFrame, "Items") ~= nil, true)
    for k in pairs(on.bagFrame) do check(k == "Items", "field " .. tostring(k) .. " written on the bag") end
end)

-- 6. Plan: "We must not give our button a buttonContext field"; header: children of UIParent.
test("d-pad to Sort: the Sort tab carries no field the bag's own code reads, and stays a child of UIParent", function()
    local c, grid = newPad()
    c:openBag()
    focusTab(c, grid)
    local tab = sortButton(c)
    for _, k in ipairs({ "buttonContext", "hasItem", "isBag", "isBackpack", "isCollapsed", "HasBag", "GetBagID", "OpenMenu",
        "customSmartNavOffsetX", "customSmartNavOffsetY" }) do
        is(rawget(tab, k), nil, k)
    end
    for k in pairs(tab) do
        if type(k) == "string" and k:find("^smartNavigation") then eq(k, RIGHT, "navigation field on the tab") end
    end
    is(tab:GetParent(), c.UIParent)
    is(confirmButton(c):GetParent(), c.UIParent)
end)

-- 7. Spec "When it does nothing": the Gamepad UI is off.
test("d-pad to Sort: with the Gamepad UI off nothing is set up and the log says why", function()
    local c, grid = newPad({ gamepadUI = false, debug = true })
    c:openBag()
    c:advance(0.5)
    eq(setterCalls(c), 0)
    eq(leftJumps(grid, sortButton(c)), {})
    check(hasLine(c, "d-pad: not set up: Gamepad UI off"), "no log line for the Gamepad UI being off")
    c:assertClean("gamepad off")
end)

-- 8. Spec "When it does nothing": the game is missing any of the pieces it needs.
test("d-pad to Sort: a client without the navigation helpers gets nothing, no error, and is told so", function()
    local c, grid = newPad({ debug = true, setup = function(cc) cc:removeSmartNav() end })
    c:openBag()
    c:advance(0.5)
    eq(setterCalls(c), 0)
    eq(leftJumps(grid, sortButton(c)), {})
    check(hasLine(c, "d-pad: not set up: no navigation helpers on this client"), "no log line")
    local found = false
    for _, text in ipairs(textsOf(c)) do
        if text == "This client has no way to reach Sort with the d-pad." then found = true end
    end
    check(found, "the settings text does not say the d-pad route is not possible")
    c:click(sortButton(c))
    eq(sorts(c), 1)
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:assertClean("no helpers")
end)

test("d-pad to Sort: with it on and usable the settings text says how to use it", function()
    local c = newPad()
    local found = false
    for _, text in ipairs(textsOf(c)) do
        if text == "D-pad: press Left from the first column to reach Sort, then A." then found = true end
    end
    check(found, "no d-pad line in the settings text")
    local off = newPad({ dpad = false })
    for _, text in ipairs(textsOf(off)) do check(not text:find("D%-pad"), "d-pad text while off: " .. text) end
end)

-- 9. FirstColumn: "bag has no item list".
test("d-pad to Sort: a bag with no item list gets nothing and no error", function()
    local c = newPad({ noItems = true, debug = true })
    c:openBag()
    c:advance(0.5)
    eq(setterCalls(c), 0)
    check(hasLine(c, "d-pad: not set up: bag has no item list"), "no log line")
    c:assertClean("no items")
end)

-- 10. Spec rule 4: "If the bag is first opened in a fight, the d-pad route appears after the fight."
test("d-pad to Sort: a bag opened in a fight gets the route when the fight ends, with nothing refused", function()
    local c, grid = newPad({ debug = true })
    c:enterCombat()
    c:openBag()
    c:advance(0.5)
    eq(setterCalls(c), 0)
    eq(c.blocked, {})
    check(hasLine(c, "d-pad: not set up: waiting for the fight to end"), "no log line")
    c:leaveCombat()
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN)
    eq(c.blocked, {})
    c:assertClean("fight")
end)

-- 11. Core PE:CombatRestricted: Blizzard's setter asks the combat restriction, not lockdown.
test("d-pad to Sort: with the game's restriction on but no lockdown the setter is not called", function()
    local c, grid = newPad()
    c.world.combatRestricted = true
    c:openBag()
    c:advance(0.5)
    eq(setterCalls(c), 0)
    eq(c.blocked, {})
    c.world.combatRestricted = false
    layoutPass(c)
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN)
    c:assertClean("restriction")
end)

-- 12. FirstColumn works from where the buttons are after layout.
test("d-pad to Sort: when the layout changes the route moves to the new first column", function()
    local c, grid = newPad()
    c:openBag()
    local tab = sortButton(c)
    for row = 1, 3 do grid[1][row]:Hide() end
    layoutPass(c)
    eq(leftJumps(grid, sortButton(c)), { ["2,1"] = "tab", ["2,2"] = "tab", ["2,3"] = "tab" })
    check(rawget(tab, RIGHT) == grid[2][1] or rawget(tab, RIGHT) == grid[2][2] or rawget(tab, RIGHT) == grid[2][3],
        "Right from the tab does not point into the new first column")
    -- and by position alone: the fourth column moved to the far left
    for row = 1, 3 do
        grid[4][row]:ClearAllPoints()
        grid[4][row]:SetPoint("TOPLEFT", c.bagFrame, "TOPLEFT", 2, -60 - (row - 1) * 42)
    end
    layoutPass(c)
    eq(leftJumps(grid, sortButton(c)), { ["4,1"] = "tab", ["4,2"] = "tab", ["4,3"] = "tab" })
    c:assertClean("layout change")
end)

-- 13. ApplyRoute: an override that is already there and not ours is left alone.
test("d-pad to Sort: a Left jump that is not ours is left alone, on and off", function()
    local c, grid = newPad()
    local other = c.minimap
    rawset(grid[1][2], LEFT, other)
    c:openBag()
    local tab = sortButton(c)
    eq(leftJumps(grid, sortButton(c)), { ["1,1"] = "tab", ["1,2"] = tostring(other), ["1,3"] = "tab" })
    chooseOption(c, "dpad", false)
    eq(leftJumps(grid, sortButton(c)), { ["1,2"] = tostring(other) })
    is(rawget(grid[1][2], LEFT), other)
    c:assertClean("someone else's jump")
end)

-- 14. Spec "When it does nothing": "Sort button" is set to Hide.
test("d-pad to Sort: hiding the Sort button removes the route and showing it puts it back", function()
    local c, grid = newPad()
    c:openBag()
    chooseOption(c, "showTab", false)
    eq(leftJumps(grid, sortButton(c)), {})
    is(rawget(sortButton(c), RIGHT), nil)
    chooseOption(c, "showTab", true)
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN)
end)

-- 15. Plan: "clears overrides ... on switch-off"; in a fight, after it.
test("d-pad to Sort: the choice Off, the feature off and the bag closed each remove the route", function()
    local c, grid = newPad({ debug = true })
    local tab = sortButton(c)
    c:openBag()
    chooseOption(c, "dpad", false)
    eq(leftJumps(grid, sortButton(c)), {})
    is(rawget(tab, RIGHT), nil)
    check(hasLine(c, "d-pad: route removed"), "no log line for the removal")
    chooseOption(c, "dpad", true)
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN)

    c:closeBag()
    eq(leftJumps(grid, sortButton(c)), {})
    c:openBag()
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN)

    c.PE:SetModuleEnabled("bags", false)
    c:advance(0.5)
    eq(leftJumps(grid, sortButton(c)), {})
    is(rawget(tab, RIGHT), nil)
    c:assertClean("switch-off")
end)

test("d-pad to Sort: switched off in a fight, the route comes off when the fight ends and nothing is refused", function()
    for _, how in ipairs({ "choice", "feature" }) do
        local c, grid = newPad()
        local tab = sortButton(c)
        c:openBag()
        c:enterCombat()
        if how == "choice" then chooseOption(c, "dpad", false) else c.PE:SetModuleEnabled("bags", false) end
        c:advance(0.5)
        eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN, how .. ": changed during the fight")
        eq(c.blocked, {}, how)
        c:leaveCombat()
        eq(leftJumps(grid, sortButton(c)), {}, how)
        is(rawget(tab, RIGHT), nil, how)
        c:assertClean(how)
    end
end)

test("d-pad to Sort: switching to the mouse and keyboard style removes the route", function()
    local c, grid = newPad()
    c:openBag()
    c.world.gamepadUI = false
    c:fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 0)
    c:advance(1.5)
    eq(leftJumps(grid, sortButton(c)), {})
    c:assertClean("style change")
end)

-- 16. Spec rule 3: "A is only taken while the cursor is on the Sort tab".
test("d-pad to Sort: A is taken only once the cursor is on the tab", function()
    local c, grid = newPad()
    c:openBag()
    c:advance(0.5)
    eq(confirmBindings(c), nil, "A taken before the cursor reached the tab")
    -- one frame after arriving, so it lands after the bag's footer has set its own A again
    is(c:padMove(grid[1][1], "left"), sortButton(c))
    eq(confirmBindings(c), nil, "A taken in the same call as the cursor's arrival")
    c:padLeave()
    focusTab(c, grid)
    eq(confirmBindings(c), { PAD1 = CONFIRM })
    c:assertClean("A taken")
end)

-- 17. Spec: "A sorts the bags (same sound, same sort, same half-second guard as a tap)".
test("d-pad to Sort: A on the tab sorts once, and again only after half a second", function()
    local c, grid = newPad({ debug = true })
    c:openBag()
    focusTab(c, grid)
    local a = confirmButton(c)
    c:script(a, "OnClick", "LeftButton", true)      -- down
    eq(sorts(c), 0, "sorted on key down")
    c:script(a, "OnClick", "LeftButton", false)     -- up
    eq(sorts(c), 1)
    c:script(a, "OnClick", "LeftButton", false)
    eq(sorts(c), 1, "sorted twice within half a second")
    c:advance(1)
    c:script(a, "OnClick", "LeftButton", false)
    eq(sorts(c), 2)
    check(hasLine(c, "Sort pressed: A on the tab"), "no log line for A")
    c:assertClean("A sorts")
end)

-- 18. Spec rule 3: "handed back the moment the cursor leaves it".
test("d-pad to Sort: A is given back when the cursor leaves the tab, and a late press does not sort", function()
    local c, grid = newPad()
    c:openBag()
    local tab = focusTab(c, grid)
    check(c:padMove(tab, "right"), "Right from the tab went nowhere")
    eq(confirmBindings(c), nil)
    c:script(confirmButton(c), "OnClick", "LeftButton", false)
    eq(sorts(c), 0)
    -- leaving in a direction with no jump (the game's own grid takes over) gives it back too
    focusTab(c, grid)
    eq(confirmBindings(c), { PAD1 = CONFIRM })
    c:padLeave()
    eq(confirmBindings(c), nil)
    c:assertClean("A given back")
end)

-- 19. Spec rule 3: "...the bag closes, a fight starts, or the feature is switched off".
test("d-pad to Sort: A is given back when the bag closes, when a fight starts and when the choice goes Off", function()
    local c, grid = newPad()
    c:openBag()
    focusTab(c, grid)
    c:closeBag()
    eq(confirmBindings(c), nil, "kept after the bag closed")
    c:script(confirmButton(c), "OnClick", "LeftButton", false)
    eq(sorts(c), 0, "sorted with the bag closed")

    c:openBag()
    c:advance(0.1)
    eq(confirmBindings(c), nil, "taken on reopening without the cursor on the tab")
    focusTab(c, grid)
    eq(confirmBindings(c), { PAD1 = CONFIRM })
    c:enterCombat()
    eq(confirmBindings(c), nil, "kept in a fight")
    eq(c.blocked, {})
    c:advance(1)
    c:leaveCombat()
    eq(confirmBindings(c), { PAD1 = CONFIRM }, "not taken again after the fight with the cursor still on the tab")

    chooseOption(c, "dpad", false)
    eq(confirmBindings(c), nil, "kept after the choice went Off")
    c:assertClean("hand-backs")

    local d, dgrid = newPad()
    d:openBag()
    focusTab(d, dgrid)
    d.PE:SetModuleEnabled("bags", false)
    d:advance(0.5)
    eq(confirmBindings(d), nil, "kept after the feature went off")
    d:assertClean("feature off")
end)

-- 20. Spec rule 4: "Left still reaches the tab but A does nothing there".
test("d-pad to Sort: A is never taken in a fight; it is taken when the fight ends with the cursor still on the tab", function()
    local c, grid = newPad({ debug = true })
    c:openBag()
    c:enterCombat()
    focusTab(c, grid)
    c:advance(0.5)
    eq(confirmBindings(c), nil)
    eq(c.blocked, {})
    check(hasLine(c, "d-pad: A not taken: in a fight"), "no log line")
    eq(bindings(c), nil, "the stick is held in a fight")
    c:leaveCombat()
    eq(confirmBindings(c), { PAD1 = CONFIRM })
    c:assertClean("fight focus")
end)

test("d-pad to Sort: with the game's restriction on A is not taken, and is taken at the next bag update after it lifts", function()
    local c, grid = newPad({ debug = true })
    c:openBag()
    c.world.combatRestricted = true
    focusTab(c, grid)
    eq(confirmBindings(c), nil)
    check(hasLine(c, "d-pad: A not taken: game restrictions on"), "no log line")
    c.world.combatRestricted = false
    c:fire("BAG_UPDATE_DELAYED")
    eq(confirmBindings(c), { PAD1 = CONFIRM })
    c:assertClean("restriction focus")
end)

-- 21. Plan OnTabFocused: the bag's footer sets its own A again on every bag update.
test("d-pad to Sort: A is taken again after a bag update while on the tab, and the update is not listened to otherwise", function()
    local c, grid = newPad()
    c:openBag()
    check(not eventRegistered(c, "BAG_UPDATE_DELAYED"), "listening for bag updates before the cursor is on the tab")
    local tab = focusTab(c, grid)
    check(eventRegistered(c, "BAG_UPDATE_DELAYED"), "not listening for bag updates on the tab")
    c._state(confirmButton(c)).bindings = nil      -- as if the game had taken A back
    c:fire("BAG_UPDATE_DELAYED")
    eq(confirmBindings(c), { PAD1 = CONFIRM })
    c:padMove(tab, "right")
    check(not eventRegistered(c, "BAG_UPDATE_DELAYED"), "still listening after leaving the tab")
    c:fire("BAG_UPDATE_DELAYED")
    eq(confirmBindings(c), nil)
    c:assertClean("bag update")
end)

-- 22. The stick click (ApplyBinding) and A (ApplyConfirm) are held by two different hidden buttons.
test("d-pad to Sort: the stick click and A do not disturb each other", function()
    local c, grid = newPad()
    c:openBag()
    focusTab(c, grid)
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    eq(confirmBindings(c), { PAD1 = CONFIRM })
    chooseOption(c, "sortKey", "r3")
    eq(bindings(c), { PADRSTICK = "PocketEssentialsBagSortKey" })
    eq(confirmBindings(c), { PAD1 = CONFIRM }, "changing the Sort key dropped A")
    c:fire("BAG_UPDATE_DELAYED")
    eq(bindings(c), { PADRSTICK = "PocketEssentialsBagSortKey" }, "taking A again dropped the stick")
    c:advance(1)
    c:script(keyButton(c), "OnClick", "LeftButton", false)
    eq(sorts(c), 1, "the stick click no longer sorts")
    c:padLeave()
    eq(confirmBindings(c), nil)
    eq(bindings(c), { PADRSTICK = "PocketEssentialsBagSortKey" }, "giving A back dropped the stick")
    c:assertClean("stick and A")
end)

-- 23. CLAUDE.md: "Nothing ticks while its feature is off."
test("d-pad to Sort: nothing is pending or listened to while the choice or the feature is off", function()
    local c, grid = newPad({ dpad = false })
    c:openBag()
    c:advance(1)
    eq(#c._timers, 0, "timers pending with the choice off")
    check(not eventRegistered(c, "BAG_UPDATE_DELAYED"), "bag updates listened to with the choice off")
    -- a cursor that lands on the tab anyway (a jump left over from a fight) takes nothing
    rawset(grid[1][1], LEFT, sortButton(c))
    c:padMove(grid[1][1], "left")
    c:advance(0.5)
    eq(confirmBindings(c), nil)
    eq(#c._timers, 0)
    check(not eventRegistered(c, "BAG_UPDATE_DELAYED"), "bag updates listened to with the choice off")

    local d, dgrid = newPad()
    d:openBag()
    focusTab(d, dgrid)
    d.PE:SetModuleEnabled("bags", false)
    d:advance(1)
    eq(#d._timers, 0, "timers pending with the feature off")
    check(not eventRegistered(d, "BAG_UPDATE_DELAYED"), "bag updates listened to with the feature off")
    eq(d.stats.addonOnUpdate, 0)
end)

-- Spec part 3, "Debug-log lines".
test("debug log: the d-pad route and the A button each write one line when they change", function()
    local c, grid = newPad({ debug = true })
    c:openBag()
    layoutPass(c)
    local tab = focusTab(c, grid)
    c:fire("BAG_UPDATE_DELAYED")
    c:padMove(tab, "right")
    c:closeBag()
    eq(count(c, "d-pad: route set on 3 first-column slots"), 1)
    eq(count(c, "d-pad: on the Sort tab"), 1)
    eq(count(c, "d-pad: A taken for Sort (A is now: CLICK PocketEssentialsBagSortConfirm:LeftButton)"), 1)
    eq(count(c, "d-pad: left the Sort tab"), 1)
    eq(count(c, "d-pad: A given back"), 1)
    eq(count(c, "d-pad: route removed"), 1)
end)

return { known = KNOWN_FAILURES }
