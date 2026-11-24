-- Rules for "Bag sorter" and "Bag window" (Bags.lua; split in two in 0.8.0,
-- spec 2026-11-18-0.8.0-design, section 2: size and icons are Bag window's).
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

-- Bag sorter on; opts.window = true switches Bag window on too.
local function newBags(opts)
    opts = opts or {}
    return T.new({ on = opts.window and { "bags", "bagWindow" } or { "bags" }, gamepadUI = opts.gamepadUI, setup = function(c)
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

-- Spec 2026-11-16-vertical-sort-tab: a tab against the bag's left edge (TOPRIGHT of the tab on
-- TOPLEFT of the bag). Spec 0.9.0 "Bag Sort tab": it overlaps the bag's left edge by `border`,
-- so it looks joined. Not a child of the bag (header: children of UIParent).
test("bags: the Sort tab overlaps the bag's left edge by one border and is a child of UIParent, not of the bag", function()
    local c = newBags()
    c:openBag()
    local btn = sortButton(c)
    eq(btn:GetParent(), c.UIParent, "parent")
    local point, rel, relPoint, x = btn:GetPoint(1)
    eq({ point, rel, relPoint, x }, { "TOPRIGHT", c.bagFrame, "TOPLEFT", c.PE.UI:Metrics().border })
end)

-- Spec 2026-11-16-vertical-sort-tab: tall and narrow, at least three button heights tall.
test("bags: the Sort tab is a tall, narrow tab", function()
    local c = newBags()
    c:openBag()
    local btn = sortButton(c)
    check(btn:GetHeight() > btn:GetWidth() * 2,
        "tab not tall and narrow: " .. btn:GetWidth() .. " x " .. btn:GetHeight())
end)

---------------------------------------------------------------------------
-- The Sort tab's look (spec 2026-11-20-0.9.0-ui-redesign, "Bag Sort tab")
---------------------------------------------------------------------------

local TAB_TEXTURE = "Interface\\AddOns\\PocketEssentials\\Icons\\tab_round"

local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.01 end

-- The tab's own regions, grouped by draw layer, in the order they were made.
local function tabRegions(c, btn)
    local out = {}
    for _, r in ipairs(c._state(btn).regions) do
        local layer = c._state(r).layer or "?"
        out[layer] = out[layer] or {}
        table.insert(out[layer], r)
    end
    return out
end

-- Edge and fill: the rounded texture in three slices (top half, a middle band, bottom half),
-- tinted gold-brown (.62, .52, .22) and (.10, .09, .08); the fill is one border inside the edge
-- on the top, left and bottom, and flush on the right (against the bag).
test("bags: the Sort tab is a rounded shape, a gold-brown edge round a dark fill, open against the bag", function()
    local c = newBags()
    c:openBag()
    local btn = sortButton(c)
    local m = c.PE.UI:Metrics()
    local layers = tabRegions(c, btn)
    local function slices(name, layer)
        local out = {}
        for _, t in ipairs(layers[layer] or {}) do
            if c._state(t).texture == TAB_TEXTURE then out[#out + 1] = t
            else check(not t:IsShown(), name .. ": a square texture is drawn") end
        end
        return out
    end
    local function checkShape(name, pieces, color, left, inset)
        eq(#pieces, 3, name .. ": slices")
        local coords = {}
        for i, t in ipairs(pieces) do
            eq(c._state(t).vertexColor, color, name .. " slice " .. i .. " colour")
            check(t:IsShown(), name .. " slice " .. i .. " hidden")
            coords[i] = c._state(t).texCoord
        end
        eq(coords, { { 0, 1, 0, 0.5 }, { 0, 1, 0.4, 0.6 }, { 0, 1, 0.5, 1 } }, name .. " slices")
        local top, mid, bottom = pieces[1], pieces[2], pieces[3]
        local width = btn:GetWidth()
        -- each end cap keeps the texture's proportions: half as tall as it is wide
        check(near(top:GetHeight(), (width - left) * 0.5), name .. ": top cap height " .. tostring(top:GetHeight()))
        check(near(bottom:GetHeight(), (width - left) * 0.5), name .. ": bottom cap height")
        check(near(top:GetLeft(), btn:GetLeft() + left) and near(top:GetRight(), btn:GetRight()), name .. ": top cap sides")
        check(near(top:GetTop(), btn:GetTop() - inset) and near(bottom:GetBottom(), btn:GetBottom() + inset), name .. ": ends")
        check(near(mid:GetTop(), top:GetBottom()) and near(mid:GetBottom(), bottom:GetTop()), name .. ": middle band")
        check(near(mid:GetLeft(), btn:GetLeft() + left) and near(mid:GetRight(), btn:GetRight()), name .. ": middle sides")
    end
    checkShape("edge", slices("edge", "BACKGROUND"), { 0.62, 0.52, 0.22, 1 }, 0, 0)
    checkShape("fill", slices("fill", "BORDER"), { 0.10, 0.09, 0.08, 1 }, m.border, m.border)
    c:assertClean("tab look")
end)

-- Middle: the sort picture button*0.5 square, then "Sort" in the small font, gold, gap*0.6
-- below it, the pair centred both ways. The stacked letters are gone.
test("bags: the middle of the Sort tab is the sort picture with the word Sort under it, centred", function()
    for _, size in ipairs({ "small", "medium", "large" }) do
        local c = T.new({ on = { "bags" }, saved = { version = 1, enabled = {}, options = {}, ui = { size = size }, errors = {} },
            setup = function(cc) cc.world.cvars.combinedBags = "0" end })
        c:openBag()
        local btn = sortButton(c)
        local m = c.PE.UI:Metrics()
        eq(m.size, size, "button size")
        local icon, word
        for _, r in ipairs(tabRegions(c, btn).OVERLAY or {}) do
            local st = c._state(r)
            if st.atlas == "bags-button-autosort-up" then icon = r end
            if st.type == "FontString" and r:IsShown() then
                check(not word, size .. ": more than one word shown")
                word = r
            end
        end
        check(icon and icon:IsShown(), size .. ": no sort picture")
        check(word, size .. ": no word")
        eq(word:GetText(), "Sort", size .. ": the word")
        eq(c._state(word).textColor, { 1, 0.82, 0, 1 }, size .. ": gold")
        local fontObject = c._state(word).fontObject
        check(fontObject ~= nil and rawget(c.env, m.smallFont) == fontObject, size .. ": not the small font")
        check(near(icon:GetWidth(), m.button * 0.5) and near(icon:GetHeight(), m.button * 0.5), size .. ": picture size")
        local cx = (btn:GetLeft() + btn:GetRight()) * 0.5
        check(near((icon:GetLeft() + icon:GetRight()) * 0.5, cx), size .. ": picture not centred across")
        check(near((word:GetLeft() + word:GetRight()) * 0.5, cx), size .. ": word not centred across")
        eq(c._state(word).justifyH, "CENTER", size .. ": word justify")
        check(near(icon:GetBottom() - word:GetTop(), m.gap * 0.6), size .. ": gap between picture and word")
        check(near(word:GetHeight(), m.smallFontSize * 1.15), size .. ": word height")
        -- the pair is centred top to bottom
        local above, below = btn:GetTop() - icon:GetTop(), word:GetBottom() - btn:GetBottom()
        check(near(above, below), size .. ": not centred top to bottom: " .. above .. " above, " .. below .. " below")
        -- no stacked letters anywhere on the tab
        for _, r in ipairs(c._state(btn).regions) do
            local text = c._state(r).type == "FontString" and r:GetText() or ""
            check(not tostring(text):find("\n", 1, true), size .. ": stacked letters: " .. tostring(text))
        end
        c:assertClean("tab middle " .. size)
    end
end)

-- The press flash: shown while pressed and fading after, in the tab's own shape (three slices
-- of the rounded texture), never the shared button's square flash.
test("bags: the Sort tab's press flash has the tab's shape", function()
    local c = newBags()
    c:openBag()
    local btn = sortButton(c)
    local flash = {}
    for _, t in ipairs(tabRegions(c, btn).ARTWORK or {}) do
        if c._state(t).texture == TAB_TEXTURE then flash[#flash + 1] = t end
    end
    eq(#flash, 3, "flash slices")
    local function shown()
        local n = 0
        for _, r in ipairs(c._state(btn).regions) do
            local st = c._state(r)
            if st.type == "Texture" and r:IsShown() and (st.layer == "ARTWORK") then n = n + 1 end
        end
        return n
    end
    for _, t in ipairs(flash) do eq(c._state(t).vertexColor, { 1, 1, 1, 0.3 }) end
    eq(shown(), 0, "flash shown before a press")
    c:script(btn, "OnMouseDown", "LeftButton")
    eq(shown(), 3, "while pressed: the shaped flash only")
    c:script(btn, "OnMouseUp", "LeftButton")
    eq(shown(), 3, "just after the press")
    c:advance(1)
    eq(shown(), 0, "flash still shown after it faded")
    -- a stick click that sorts flashes the tab too
    c:advance(1)
    c:script(keyButton(c), "OnClick", "LeftButton", false)
    eq(sorts(c), 1)
    eq(shown(), 3, "no flash after a stick click")
    c:advance(1)
    eq(shown(), 0, "stick flash still shown")
    c:assertClean("tab flash")
end)

-- The texture: an uncompressed 32-bit TGA with alpha like the other Icons, at most 64x128 and a
-- few KB, in the addon folder the build copies whole (so it needs no TOC entry).
test("bags: the tab texture is a small 32-bit TGA in the addon's Icons folder, which the build ships", function()
    local function slurp(path)
        local f = io.open(T.root .. "/" .. path, "rb")
        check(f, path .. " is missing")
        local data = f:read("*a")
        f:close()
        return data
    end
    local data = slurp("addons/PocketEssentials/Icons/tab_round.tga")
    local b = function(i) return data:byte(i) end
    eq(b(3), 2, "image type (uncompressed true colour)")
    local w, h = b(13) + b(14) * 256, b(15) + b(16) * 256
    check(w >= 1 and w <= 64 and h >= 1 and h <= 128, "size " .. w .. "x" .. h)
    eq(b(17), 32, "bits per pixel")
    eq(b(18) % 16, 8, "alpha bits")
    eq(#data, 18 + w * h * 4, "file length")
    check(#data <= 8 * 1024, "more than a few KB: " .. #data)
    check(slurp("scripts/build.sh"):find('cp -R addons/PocketEssentials "$stage/"', 1, true),
        "build.sh no longer copies the whole addon folder")
    check(slurp("scripts/make_art.py"):find("tab_round.tga", 1, true), "scripts/make_art.py does not make tab_round.tga")
end)

-- Sets one saved value and runs the OnChange of the row that holds it, in
-- whichever of the two features has that row.
local function chooseOption(c, key, value)
    for _, modKey in ipairs({ "bags", "bagWindow" }) do
        local mod = c.PE:GetModule(modKey)
        for _, opt in ipairs(mod.options) do
            if opt.key == key then
                mod.opts[key] = value
                opt.OnChange(mod, value)
            end
        end
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

-- Spec 0.15.0 D4: the tab sits outside the bag's left edge, over the bank's bag slots, so it
-- hides while the bank is open. The stick still sorts there.
test("bags: the Sort tab hides while the bank is open, the stick still sorts, and it comes back after", function()
    local c = newBags()
    c:openBag()
    local btn = sortButton(c)
    check(btn:IsVisible(), "tab not shown")
    c:openBank()
    check(not btn:IsVisible(), "tab shown over the bank")
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:script(keyButton(c), "OnClick", "LeftButton", false)
    eq(sorts(c), 1, "the stick did not sort at the bank")
    c:closeBank()
    check(btn:IsVisible(), "tab not back after the bank closed")
    c:assertClean("bank")
end)

test("bags: the bag opened with the bank already open shows no Sort tab", function()
    local c = newBags()
    c:openBank()
    c:openBag()
    check(not sortButton(c):IsVisible(), "tab shown over the bank")
    c:closeBank()
    check(sortButton(c):IsVisible(), "tab not back after the bank closed")
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
    local c = newBags({ window = true, gamepadUI = true, setup = function(c)
        if bagHeight then c.bagFrame:SetSize(388, bagHeight) end
    end })
    local PE = c.PE
    PE:GetModule("bagWindow").opts.size = size
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
    local mod = c.PE:GetModule("bagWindow")
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

-- Bags.lua ApplyScaleNow (Bag window off: the game's size) and RestoreScaleNow (both off):
-- each puts back exactly what Blizzard's layout pass set.
test("bags: switching Bag window off puts the game's own scale back, with Bag sorter on or off", function()
    for _, sorterToo in ipairs({ false, true }) do
        local c, scale = scaleAfterOpen("large")
        eq(scale, 1.25)
        if sorterToo then c.PE:SetModuleEnabled("bags", false) end
        c.PE:SetModuleEnabled("bagWindow", false)
        c:advance(0.5)
        eq(c.bagFrame:GetScale(), 1)
        local point, _, relPoint, x, y = c.bagFrame:GetPoint(1)
        eq({ point, relPoint, x, y }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 4, 85 })
    end
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

-- The names, descriptions and status lines of both bag features.
local function textsOf(c)
    local out = {}
    for _, key in ipairs({ "bags", "bagWindow" }) do
        local mod = c.PE:GetModule(key)
        out[#out + 1], out[#out + 2] = mod.label, mod.desc
        local status = mod.status(mod)
        if type(status) == "string" then out[#out + 1] = status
        elseif type(status) == "table" then for _, l in ipairs(status) do out[#out + 1] = l end end
    end
    return out
end

-- Spec 0.9.0, "Feature names and lines".
test("bags: the features are called Bag sorting and Bigger bag and no text of them says One big bag", function()
    for _, gamepad in ipairs({ true, false }) do
        local c = newBags({ gamepadUI = gamepad })
        local mod = c.PE:GetModule("bags")
        eq(mod.label, "Bag sorting")
        eq(mod.desc, "Sort your bags with one press.")
        eq(mod.key, "bags")
        local win = c.PE:GetModule("bagWindow")
        eq({ win.label, win.desc }, { "Bigger bag", "A bigger and better organized bag window." })
        for _, text in ipairs(textsOf(c)) do
            check(not text:lower():find("big bag", 1, true), "old name in: " .. text)
        end
    end
    local c = newBags({ cvar = "0" })
    c:advance(1)
    local status = c.PE:GetModule("bags").status(c.PE:GetModule("bags"))
    check(not tostring(status):lower():find("one big bag", 1, true), "old name in status")
end)

test("bags: each Sort stick choice binds the right key on open and clears it on close, tab always there", function()
    for value, want in pairs({ l3 = "PADLSTICK", r3 = "PADRSTICK" }) do
        local c = newBags({ setup = function(cc) end })
        c.PE:GetModule("bags").opts.sortKey = value
        c:openBag()
        eq(bindings(c), { [want] = "PocketEssentialsBagSortKey" }, value)
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

test("debug log: the sort key choice writes which stick was taken and given back", function()
    local c = newBags()
    c.PE:SetDebug(true)
    c:openBag()
    chooseOption(c, "sortKey", "r3")
    c:closeBag()
    local seen = {}
    for _, line in ipairs(debugLines(c, "bags")) do seen[line] = true end
    for _, want in ipairs({ "left stick click taken for Sort (bag open)", "right stick click taken for Sort (bag open)",
        "sort key choice: r3", "stick click given back to the game" }) do
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

---------------------------------------------------------------------------
-- D-pad to Sort (spec 2026-11-17-0.4.0-handheld-batch, part 3; plan Task 3). Since 0.8.0 it is
-- not a choice of its own: the route is there whenever the Sort button shows (spec
-- 2026-11-18-0.8.0-design, section 2), so "off" below means "Sort button" Off.
--
-- The stand-in's cursor follows the one rule the design leans on: a jump override that is a
-- visible frame takes the cursor there (c:padMove). Whether the game's own A binding or ours
-- wins on the device cannot be shown here.
---------------------------------------------------------------------------

local LEFT, RIGHT = "smartNavigationOverride-left", "smartNavigationOverride-right"
local NAV_ADD, NAV_CLEAR = "SmartNavigation_AddJumpNavigationOverride", "SmartNavigation_ClearJumpNavigationOverridesInDirection"
local CONFIRM = "PocketEssentialsBagSortConfirm"

-- Gamepad UI on, a bag of 4 columns by 3 rows, the Sort button on (o.dpad = false: Sort button Off).
-- With o.debug the feature is switched off and on again with the log on, so the log
-- starts from the feature switching on.
local function newPad(o)
    o = o or {}
    local gamepad = o.gamepadUI ~= false
    local c = newBags({ gamepadUI = gamepad, setup = o.setup })
    local grid = not o.noItems and c:fillBag(4, 3) or nil
    if o.dpad == false then c.PE:GetModule("bags").opts.showTab = false end
    if o.debug then
        c.PE:SetDebug(true)
        c.PE:SetModuleEnabled("bags", false)
        c.PE:SetModuleEnabled("bags", true)
        c:advance(0.1)
    end
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
    chooseOption(c, "showTab", false)
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
    -- spec 0.9.0, "Bag sorting": no informational lines in its card
    for _, text in ipairs(textsOf(c)) do check(not text:find("d%-pad"), "d-pad text in the settings: " .. text) end
    c:click(sortButton(c))
    eq(sorts(c), 1)
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:assertClean("no helpers")
end)

-- Spec 0.9.0, "Bag sorting": "The blue informational status lines are not shown in its card.
-- Blocked and failed lines still are."
test("bags: Bag sorting's card has no informational lines, only its problems", function()
    for i, o in ipairs({ {}, { dpad = false }, { setup = function(cc) cc:removeSmartNav() end } }) do
        local c = newPad(o)
        local bags = c.PE:GetModule("bags")
        eq(bags.status(bags), nil, "case " .. i .. ": a line with nothing wrong")
    end
    -- mouse style, already the combined bag, with either stick and the tab shown or hidden
    for _, key in ipairs({ "l3", "r3" }) do
        for _, show in ipairs({ true, false }) do
            local c = newBags({ gamepadUI = false, cvar = "1" })
            local bags = c.PE:GetModule("bags")
            bags.opts.sortKey, bags.opts.showTab = key, show
            eq(bags.status(bags), nil, "mouse style: a line with nothing wrong")
        end
    end
    -- the problems stay
    local c = newBags({ cvar = "0" })
    local bags = c.PE:GetModule("bags")
    eq(bags.status(bags), "Reload to switch to the combined bag.")
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
test("d-pad to Sort: a Left jump that is not ours is left alone, on and off (Sort button Off)", function()
    local c, grid = newPad()
    local other = c.minimap
    rawset(grid[1][2], LEFT, other)
    c:openBag()
    local tab = sortButton(c)
    eq(leftJumps(grid, sortButton(c)), { ["1,1"] = "tab", ["1,2"] = tostring(other), ["1,3"] = "tab" })
    chooseOption(c, "showTab", false)
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

-- Spec 0.15.0 D4: with the bank open the tab is hidden, so the d-pad route treats it as gone.
test("d-pad to Sort: the bank opening removes the route and A, and closing it puts the route back", function()
    local c, grid = newPad()
    c:openBag()
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN)
    focusTab(c, grid)
    eq(confirmBindings(c), { PAD1 = CONFIRM })
    c:openBank()
    eq(leftJumps(grid, sortButton(c)), {})
    is(rawget(sortButton(c), RIGHT), nil)
    eq(next(confirmBindings(c) or {}), nil, "A still taken with the tab hidden")
    c:closeBank()
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN)
    c:assertClean("bank route")
end)

-- 15. Plan: "clears overrides ... on switch-off"; in a fight, after it.
test("d-pad to Sort: Sort button Off, the feature off and the bag closed each remove the route", function()
    local c, grid = newPad({ debug = true })
    local tab = sortButton(c)
    c:openBag()
    chooseOption(c, "showTab", false)
    eq(leftJumps(grid, sortButton(c)), {})
    is(rawget(tab, RIGHT), nil)
    check(hasLine(c, "d-pad: route removed"), "no log line for the removal")
    chooseOption(c, "showTab", true)
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
        if how == "choice" then chooseOption(c, "showTab", false) else c.PE:SetModuleEnabled("bags", false) end
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
test("d-pad to Sort: A is given back when the bag closes, when a fight starts and when Sort button goes Off", function()
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

    chooseOption(c, "showTab", false)
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
test("d-pad to Sort: nothing is pending or listened to while Sort button or the feature is off", function()
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

---------------------------------------------------------------------------
-- "Bag icons": the bag buttons in one row at the top (spec 2026-11-17, part 4)
---------------------------------------------------------------------------

-- Gamepad UI on, the bag built as the game builds it (60 slots unless o.sizes says otherwise),
-- Bag sorting and Bigger bag on: the bag pictures go to the top row (spec 0.9.0: always while
-- Bigger bag is on). o.row = false: Bigger bag off, the game's own layout. The d-pad route is
-- on with the Sort button (o.dpad = false: Sort button Off).
local function newIcons(o)
    o = o or {}
    local c = newBags({ window = o.row ~= false, gamepadUI = o.gamepadUI ~= false, setup = o.setup, cvar = o.cvar })
    c:buildBag(o.sizes)
    if o.dpad == false then c.PE:GetModule("bags").opts.showTab = false end
    if o.debug then c.PE:SetDebug(true) end
    return c
end

-- How many widget calls the addon has made on the bag's own buttons.
local function moves(c)
    local n = 0
    for _, call in ipairs(c.calls) do
        if call.name:find("^GamepadBagButton:") or call.name:find("^ContainerItemButton:") then n = n + 1 end
    end
    return n
end

-- Every button's anchor as text, in the stand-in's fixed button order.
local function places(c)
    local out = {}
    for i, b in ipairs(c.bagButtons) do
        if b:GetNumPoints() == 0 then
            out[i] = "none"
        else
            local point, rel, relPoint, x, y = b:GetPoint(1)
            out[i] = table.concat({ b:GetNumPoints(), point, rawequal(rel, c.bagMoney) and "money" or tostring(rel),
                relPoint, x, y }, " ")
        end
    end
    return out
end

-- What Blizzard's own layout gives for the same bags, from a second client with Bigger bag off.
local function gameLayout(o)
    local g = newIcons({ row = false, sizes = o and o.sizes, gamepadUI = o and o.gamepadUI })
    if o and o.collapsed then for id, v in pairs(o.collapsed) do g.world.collapsed[id] = v end end
    g:openBag()
    return g
end

local function cellsByKind(c)
    local icons, slots = {}, {}
    for _, e in ipairs(c:bagCells()) do
        if e.kind == "icon" then icons[#icons + 1] = e else slots[#slots + 1] = e end
    end
    return icons, slots
end

-- The layout rule of the spec, checked on what is on the screen: icons in the top row from the
-- left in Blizzard's order; slots in Blizzard's order reading left to right, top to bottom; every
-- row below the first slot row full; the first slot row filled from the left, or, when it is the
-- top row, at its right end.
local function checkRowLayout(c, wantIcons, wantSlots)
    local icons, slots = cellsByKind(c)
    eq(#icons, wantIcons, "icons")
    eq(#slots, wantSlots, "slots")
    for i, e in ipairs(icons) do eq({ e.row, e.col }, { 1, i }, "icon " .. i) end
    local seen, perRow, lastRow = {}, {}, 1
    for i, e in ipairs(slots) do
        local key = e.row .. "," .. e.col
        check(not seen[key], "two buttons in cell " .. key)
        seen[key] = true
        check(e.col >= 1 and e.col <= 10 and e.col == math.floor(e.col), "column " .. tostring(e.col))
        perRow[e.row] = (perRow[e.row] or 0) + 1
        if e.row > lastRow then lastRow = e.row end
        if i > 1 then
            local p = slots[i - 1]
            check(e.row > p.row or (e.row == p.row and e.col > p.col),
                "slot " .. i .. " is not after slot " .. (i - 1) .. " in reading order")
        end
    end
    for i, e in ipairs(icons) do check(not seen[e.row .. "," .. e.col], "a slot shares icon " .. i .. "'s cell") end
    return perRow, lastRow, slots, icons
end

-- 1. Spec 0.9.0, "Bigger bag": "The Bag icons choice goes. While Bigger bag is on, the bag
-- pictures always go in the one row at the top ... The iconRow key is no longer read." Review
-- focus 2: a stray iconRow = false must not undo the top-row icons.
test("bags: Bigger bag has no Bag icons choice and puts the icons in the top row whatever iconRow holds", function()
    for _, saved in ipairs({ false, true, "yes", 0 }) do
        local c = newBags({ gamepadUI = true, setup = function(cc) end })
        c:buildBag()
        local mod = c.PE:GetModule("bagWindow")
        for _, opt in ipairs(mod.options) do check(opt.key ~= "iconRow" and opt.label ~= "Bag icons", "a Bag icons row") end
        mod.opts.iconRow = saved
        c.PE:SetModuleEnabled("bagWindow", true)
        c:openBag()
        checkRowLayout(c, 7, 60)
        eq(mod.opts.iconRow, saved, "the saved value was rewritten")
        c:assertClean("iconRow " .. tostring(saved))
    end
    -- a save with iconRow = false loaded with Bigger bag on
    local c, PE = T.new({ gamepadUI = true, saved = { version = 1, enabled = { bags = true, bagWindow = true },
        options = { bagWindow = { size = "normal", iconRow = false } }, errors = {} },
        setup = function(cc) cc.world.cvars.combinedBags = "1" end })
    c:buildBag()
    c:openBag()
    checkRowLayout(c, 7, 60)
    eq(PE.db.options.bagWindow.iconRow, false)
end)

-- 2. The game's way while Bigger bag is off.
test("bags: with Bigger bag off nothing in the bag is moved", function()
    local c = newIcons({ row = false })
    c:openBag()
    c:relayoutBag()
    c:closeBag()
    c:openBag()
    eq(moves(c), 0)
    -- and the stand-in starts from the game's layout: every bag button is in the grid, each
    -- ahead of its own bag's slots, spread over the rows
    local icons = cellsByKind(c)
    eq(#icons, 7)
    local rows, n = {}, 0
    for _, e in ipairs(icons) do
        if not rows[e.row] then rows[e.row], n = true, n + 1 end
    end
    eq(n, 6, "rows with a bag button")
    local cells = c:bagCells()
    eq({ cells[1].kind, cells[1].bag, cells[2].kind, cells[2].slot, cells[18].kind, cells[18].bag }, { "icon", 0, "slot", 1, "icon", 1 })
    c:assertClean("in the grid")
end)

-- 3. Layout rule: "Icons: top row, columns 1..h, in Blizzard's order."
test("bags: One row at the top puts the seven icons in the top row from the left", function()
    local c = newIcons()
    c:openBag()
    local icons = cellsByKind(c)
    eq(#icons, 7)
    local order = {}
    for i, e in ipairs(icons) do
        eq({ e.row, e.col }, { 1, i }, "icon " .. i)
        order[i] = e.bag
    end
    eq(order, { 0, 1, 2, 3, 4, 5, -2 })
    c:assertClean("icon row")
end)

-- 4. Layout rule: "Slots keep Blizzard's order (backpack slot 1 first)", nothing in between.
test("bags: the slots follow below in Blizzard's order with no icon between them", function()
    local c = newIcons()
    c:openBag()
    local perRow, lastRow, slots = checkRowLayout(c, 7, 60)
    eq(lastRow, 7)
    eq(perRow[1], nil, "slots in the icon row")
    for row = 2, 7 do eq(perRow[row], 10, "row " .. row) end
    eq({ slots[1].bag, slots[1].slot, slots[1].row, slots[1].col }, { 0, 1, 2, 1 })
    eq({ slots[60].bag, slots[60].slot, slots[60].row, slots[60].col }, { 4, 10, 7, 10 })
end)

-- 5. Layout rule: "the first row under the icons holds the odd slots, from the left".
test("bags: odd slots sit in the first row under the icons, from the left", function()
    local c = newIcons({ sizes = { 16, 16, 16, 16, 0 } })
    c:openBag()
    local perRow, lastRow, slots = checkRowLayout(c, 7, 64)
    eq(lastRow, 8)
    eq(perRow[1], nil)
    eq(perRow[2], 4)
    for i = 1, 4 do eq({ slots[i].row, slots[i].col }, { 2, i }) end
    for row = 3, 8 do eq(perRow[row], 10, "row " .. row) end
end)

-- 6. Layout rule: "Otherwise ... those first slots finish the top row at its right end".
test("bags: when the slots do not fit below, the first ones finish the top row at the right", function()
    local c = newIcons({ sizes = { 16, 16, 16, 15, 0 } })
    c:openBag()
    local perRow, lastRow, slots = checkRowLayout(c, 7, 63)
    eq(lastRow, 7)
    eq(perRow[1], 3)
    for i = 1, 3 do eq({ slots[i].row, slots[i].col }, { 1, 7 + i }) end
    for row = 2, 7 do eq(perRow[row], 10, "row " .. row) end
end)

-- 7. Rules: "Offsets are copied exactly from what Blizzard set, never calculated"; the window
-- keeps Blizzard's size; the anchor is the one Blizzard's grid uses.
test("bags: every button keeps one of Blizzard's own columns and rows", function()
    for _, sizes in ipairs({ { 16, 12, 12, 10, 10 }, { 16, 16, 16, 16, 0 }, { 16, 16, 16, 15, 0 }, { 16, 0, 0, 0, 0 } }) do
        local g = gameLayout({ sizes = sizes })
        local xs, ys = {}, {}
        for _, e in ipairs(g:bagCells()) do xs[e.x], ys[e.y] = true, true end
        local c = newIcons({ sizes = sizes })
        c:openBag()
        local cells = c:bagCells()
        eq(#cells, #g:bagCells())
        for _, e in ipairs(cells) do
            check(xs[e.x], "x " .. tostring(e.x) .. " is not one of the game's columns")
            check(ys[e.y], "y " .. tostring(e.y) .. " is not one of the game's rows")
            eq({ e.point, e.relPoint }, { "BOTTOMRIGHT", "TOPRIGHT" })
            check(rawequal(e.rel, c.bagMoney), "anchored to something else")
            eq(e.button:GetNumPoints(), 1)
        end
        eq({ c.bagFrame:GetWidth(), c.bagFrame:GetHeight() }, { g.bagFrame:GetWidth(), g.bagFrame:GetHeight() })
        c:assertClean("cells")
    end
end)

-- 8. ApplyIconRow: only buttons whose place differs are touched.
test("bags: a second layout pass without changes moves nothing", function()
    local c = newIcons()
    c:openBag()
    local first, before = moves(c), places(c)
    check(first > 0, "nothing was moved at all")
    layoutPass(c)
    layoutPass(c)
    eq(moves(c), first, "moved again though the game had moved nothing")
    eq(places(c), before)
    -- the game lays the items out again (same bags): the same result once more
    c:relayoutBag()
    eq(places(c), before)
    eq(moves(c), first * 2)
end)

-- 9. Spec: "X on an icon still collapses and expands that bag and the layout stays tidy".
test("bags: collapsing a bag re-flows the remaining slots", function()
    local c = newIcons()
    c:openBag()
    c:collapseBag(1, true)
    local perRow, lastRow, slots = checkRowLayout(c, 7, 48)
    eq(lastRow, 6)
    eq(perRow[2], 8)
    for row = 3, 6 do eq(perRow[row], 10, "row " .. row) end
    for _, e in ipairs(slots) do check(e.bag ~= 1, "a slot of the collapsed bag is in the grid") end
    for slot = 1, 12 do eq(c.bagSlots[1][slot]:GetNumPoints(), 0, "collapsed slot was given a place") end
    -- the key ring expanded as well, then everything back
    c:collapseBag(-2, false)
    checkRowLayout(c, 7, 52)
    c:collapseBag(1, false)
    c:collapseBag(-2, true)
    local again = newIcons()
    again:openBag()
    eq(places(c), places(again))
    c:assertClean("collapse")
end)

-- 10. Rules, switch-off: "each button gets back the exact anchor Blizzard gave it".
test("bags: switching back to In the grid puts every button back exactly", function()
    local g = gameLayout()
    local c = newIcons()
    c:openBag()
    check(table.concat(places(c), "|") ~= table.concat(places(g), "|"), "the row layout is the game's layout")
    c.PE:SetModuleEnabled("bagWindow", false)
    eq(places(c), places(g))
    local after = moves(c)
    layoutPass(c)
    c:relayoutBag()
    eq(moves(c), after, "still moving buttons with the choice back on In the grid")
    eq(places(c), places(g))
    -- and on again with the bag open
    c.PE:SetModuleEnabled("bagWindow", true)
    checkRowLayout(c, 7, 60)
    c:assertClean("back to the grid")
end)

-- 10b. The same after the bag changed while the row was on (a collapsed bag).
test("bags: switching back after a bag was collapsed gives the game's layout for those bags", function()
    local g = gameLayout({ collapsed = { [2] = true } })
    local c = newIcons()
    c:openBag()
    c:collapseBag(2, true)
    c.PE:SetModuleEnabled("bagWindow", false)
    eq(places(c), places(g))
end)

-- 11. Rules: "Switching ... off puts every button back where the game had it" (Bag window since 0.8.0).
test("bags: switching Bag window off puts every button back exactly", function()
    local g = gameLayout()
    local c = newIcons()
    c:openBag()
    c.PE:SetModuleEnabled("bagWindow", false)
    eq(places(c), places(g))
    local after = moves(c)
    layoutPass(c)
    c:relayoutBag()
    eq(moves(c), after, "buttons moved with the feature off")
    c:assertClean("feature off")
end)

-- 11b. Switch-off: "but only if it still has the anchor we set".
test("bags: a button that is no longer where it was put is not touched at switch-off", function()
    local c = newIcons()
    c:openBag()
    local stray = c.bagSlots[0][1]
    c._state(stray).points[1].x = -999
    local before = places(c)
    c.PE:SetModuleEnabled("bagWindow", false)
    eq(places(c), before, "buttons were moved though the layout was no longer ours")
    c:assertClean("stray")
end)

-- 12. Spec: "It only acts in the controller style"; debug line.
test("bags: with the Gamepad UI off the choice does nothing and says why in the debug log", function()
    local c = newIcons({ gamepadUI = false, debug = true, cvar = "1" })
    c:openBag()
    layoutPass(c)
    eq(moves(c), 0)
    eq(count(c, "bag icons: left alone, no bag icons in the grid (not the controller style)"), 1)
    c:assertClean("mouse style")
end)

-- 13. Rules: "If anything is not as expected (no GamepadBagBar ...): do nothing, one debug line."
test("bags: without GamepadBagBar the choice does nothing and writes one debug line", function()
    local c = newIcons({ debug = true })
    c:removeBagBar()
    c:openBag()
    layoutPass(c)
    c:relayoutBag()
    eq(moves(c), 0)
    eq(count(c, "bag icons: left alone, the grid is not as expected (no GamepadBagBar)"), 1)
    c:assertClean("no bar")
end)

-- 13b. The other "not as expected" cases: a second point on a button, a different anchor,
-- fewer than ten columns in use.
test("bags: a grid that is not Blizzard's is left alone", function()
    local a = newIcons({ debug = true })
    a:openBag()
    a:layoutBagItems()   -- the game lays the items out again, and one comes out differently
    local st = a._state(a.bagSlots[0][5])
    st.points[1].rel, st.points[1].relPoint = a.bagFrame, "BOTTOMRIGHT"
    local before, n = places(a), moves(a)
    layoutPass(a)
    layoutPass(a)
    eq(places(a), before)
    eq(moves(a), n)
    eq(count(a, "bag icons: left alone, the grid is not as expected (mixed anchors)"), 1)
    a:assertClean("mixed anchors")

    -- two slots and seven bag buttons: one row of nine
    local b = newIcons({ debug = true, sizes = { 2, 0, 0, 0, 0 } })
    b:openBag()
    eq(moves(b), 0)
    eq(count(b, "bag icons: left alone, the grid is not as expected (fewer than ten columns)"), 1)
    b:assertClean("short grid")
end)

-- 14. Rules: "No field written on any Blizzard frame or table."
test("bags: nothing is written onto Blizzard's buttons or tables", function()
    local c = newIcons()
    local function keys(t)
        local out = {}
        for k in pairs(t) do out[#out + 1] = tostring(k) end
        table.sort(out)
        return out
    end
    local bar = rawget(c.env, "GamepadBagBar")
    local bagKeys, barKeys = keys(c.bagFrame), keys(bar)
    local items, array = rawget(c.bagFrame, "Items"), rawget(bar, "BagButtonArray")
    local nItems, nArray = #items, #array
    c:openBag()
    c:collapseBag(3, true)
    c:closeBag()
    c:openBag()
    c.PE:SetModuleEnabled("bagWindow", false)
    c.PE:SetModuleEnabled("bagWindow", true)
    c.PE:SetModuleEnabled("bags", false)
    for i, b in ipairs(c.bagButtons) do eq(next(b), nil, "a field on bag button " .. i) end
    eq(keys(c.bagFrame), bagKeys)
    eq(keys(bar), barKeys)
    check(rawequal(rawget(c.bagFrame, "Items"), items) and rawequal(rawget(bar, "BagButtonArray"), array), "a list was replaced")
    eq({ #items, #array }, { nItems, nArray })
    eq(next(c.bagMoney), nil)
    c:assertClean("no fields")
end)

-- 15. Rules, combat: "allowed, the buttons are not protected. If a button says it is protected
-- during a fight: leave Blizzard's layout, one debug line, redo after the fight".
test("bags: the bag opened in a fight is re-flowed at once; with protected buttons it waits for the fight to end", function()
    local c = newIcons()
    c:enterCombat()
    c:openBag()
    checkRowLayout(c, 7, 60)
    eq(c.blocked, {})
    c:assertClean("fight, not protected")

    local g = gameLayout()
    local p = newIcons({ debug = true })
    p._state(p.bagSlots[2][3]).protected = true
    p:enterCombat()
    p:openBag()
    layoutPass(p)
    eq(moves(p), 0)
    eq(places(p), places(g))
    eq(count(p, "bag icons: held for after the fight"), 1)
    p:leaveCombat()
    checkRowLayout(p, 7, 60)
    eq(p.blocked, {})
    -- switched off in a fight: put back when the fight ends
    p:enterCombat()
    p.PE:SetModuleEnabled("bagWindow", false)
    checkRowLayout(p, 7, 60)
    p:leaveCombat()
    eq(places(p), places(g))
    p:assertClean("fight, protected")
end)

-- 16. Rules: "Bag size and the Sort tab are unaffected (the window's size does not change)."
-- Since 0.9.0 the row comes with Bigger bag: at Normal size the bag and the tab are as without it.
test("bags: the icon row leaves the bag's size and the Sort tab as they are", function()
    local function snapshot(row)
        local c = newIcons({ row = row })
        c:openBag()
        local bag, tab = c.bagFrame, sortButton(c)
        local point, _, relPoint, x, y = bag:GetPoint(1)
        local tp, trel, trp, tx, ty = tab:GetPoint(1)
        check(rawequal(trel, bag), "tab not on the bag")
        check(tab:IsVisible(), "tab not shown")
        return { bag:GetScale(), bag:GetNumPoints(), point, relPoint, x, y, bag:GetWidth(), bag:GetHeight(),
            tp, trp, tx, ty, tab:GetWidth(), tab:GetHeight() }
    end
    local grid, row = snapshot(false), snapshot(true)
    eq(row, grid)
end)

-- Rulings: "the Left jump to the Sort tab is put on whatever item buttons end up in the first
-- column after the bag icons have been moved". The bag buttons themselves get no jump (they are
-- not item buttons and keep the game's own navigation).
test("bags: with Bag icons and D-pad to Sort both on, the Left jump is on the first column of the re-flowed bag", function()
    local c = newIcons({ dpad = true })
    c:openBag()
    c:advance(0.5)
    local tab = sortButton(c)
    local function checkJumps(what, wantCount)
        local n = 0
        for _, e in ipairs(c:bagCells()) do
            local jump = rawget(e.button, LEFT)
            if e.kind == "slot" and e.col == 1 then
                check(rawequal(jump, tab), what .. ": no Left jump on the slot in row " .. e.row .. " of the first column")
                n = n + 1
            else
                eq(jump, nil, what .. ": Left jump on " .. e.kind .. " at row " .. e.row .. ", column " .. e.col)
            end
        end
        eq(n, wantCount, what .. ": first-column slots")
        for _, b in ipairs(c.bagButtons) do
            if b:GetNumPoints() == 0 then eq(rawget(b, LEFT), nil, what .. ": jump on a button that is not laid out") end
        end
        local right = rawget(tab, RIGHT)
        check(right ~= nil and c.bagInfo[right].kind == "slot" and rawequal(rawget(right, LEFT), tab),
            what .. ": Right from the tab does not go to a first-column slot")
    end
    checkJumps("row", 6)                 -- rows 2 to 7 of column 1; the backpack button above them has none
    is(c:padMove(c.bagSlots[0][1], "left"), tab)
    eq(c:padMove(c.bagIcons[0], "left"), nil)
    -- a bag collapsed: the first column is other buttons now
    c:collapseBag(1, true)
    checkJumps("collapsed", 5)
    c:collapseBag(1, false)
    checkJumps("expanded", 6)
    -- back to the game's layout: its first column holds five slots and a bag button
    c.PE:SetModuleEnabled("bagWindow", false)
    checkJumps("grid", 5)
    c.PE:SetModuleEnabled("bagWindow", true)
    checkJumps("row again", 6)
    eq(c.blocked, {})
    c:assertClean("both choices")
end)

-- Review of 0.4.0, point 1: Blizzard hands its pooled item buttons back to the slots in no fixed
-- order whenever the bag is generated. Out of a fight the route follows at once. In a fight
-- Blizzard's setter is refused, so the old jumps stay on whatever slots their buttons serve now
-- until the fight ends (spec part 3, rule 4); then they are put right.
local function checkShuffledJumps(c, what, wantCount)
    local tab = sortButton(c)
    local n = 0
    for _, e in ipairs(c:bagCells()) do
        local jump = rawget(e.button, LEFT)
        if e.kind == "slot" and e.col == 1 then
            check(rawequal(jump, tab), what .. ": no Left jump on the slot in row " .. e.row .. " of the first column")
            n = n + 1
        else
            eq(jump, nil, what .. ": Left jump on " .. e.kind .. " at row " .. e.row .. ", column " .. e.col)
        end
    end
    -- wantCount nil: however many slots the layout put in the first column, but some
    if wantCount then eq(n, wantCount, what .. ": first-column slots") end
    check(n > 0, what .. ": no slot in the first column")
    -- no button anywhere else keeps one (folded bags' buttons, hidden ones)
    local total = 0
    for _, b in ipairs(c.bagButtons) do
        if rawget(b, LEFT) ~= nil then total = total + 1 end
    end
    eq(total, n, what .. ": buttons with a Left jump in all")
    local right = rawget(tab, RIGHT)
    check(right ~= nil and c.bagInfo[right].kind == "slot" and rawequal(rawget(right, LEFT), tab),
        what .. ": Right from the tab does not go to a first-column slot")
end

-- How many laid-out slots off the first column carry a Left jump to the tab (the stale ones).
local function strayJumps(c)
    local tab, n = sortButton(c), 0
    for _, e in ipairs(c:bagCells()) do
        if not (e.kind == "slot" and e.col == 1) and rawequal(rawget(e.button, LEFT), tab) then n = n + 1 end
    end
    return n
end

test("d-pad to Sort: out of a fight, buttons handed to other slots get the route put right at once", function()
    for _, row in ipairs({ true, false }) do
        local what = row and "icon row" or "grid"
        local c = newIcons({ dpad = true, row = row })
        local want = row and 6 or 5
        c:openBag()
        c:advance(0.5)
        checkShuffledJumps(c, what .. ", opened", want)
        -- the game lays the bag out again with its buttons on other slots
        c:shuffleBagButtons()
        c:relayoutBag()
        checkShuffledJumps(c, what .. ", shuffled", want)
        -- closed and opened again
        c:closeBag()
        c:shuffleBagButtons(13)
        c:openBag()
        checkShuffledJumps(c, what .. ", reopened", want)
        -- a bag folded
        c:shuffleBagButtons(29)
        c:collapseBag(1, true)
        checkShuffledJumps(c, what .. ", folded", row and 5 or nil)
        eq(c.blocked, {})
        c:assertClean(what)
    end
end)

test("d-pad to Sort: in a fight, buttons handed to other slots keep the old jumps until the fight ends, then all are put right", function()
    local changes = {
        reopened = function(c) c:closeBag(); c:shuffleBagButtons(); c:openBag() end,
        folded = function(c) c:shuffleBagButtons(); c:collapseBag(1, true) end,
    }
    for name, change in pairs(changes) do
        for _, row in ipairs({ true, false }) do
            local what = name .. (row and ", icon row" or ", grid")
            local c = newIcons({ dpad = true, row = row })
            c:openBag()
            c:advance(0.5)
            local want = row and 6 or 5
            checkShuffledJumps(c, what .. ", before the fight", want)
            c:enterCombat()
            local calls = setterCalls(c)
            change(c)
            c:advance(0.5)
            -- the limit: nothing can be set in a fight, so the old jumps sit on other slots
            eq(setterCalls(c), calls, what .. ": the setter was called in a fight")
            eq(c.blocked, {}, what)
            check(strayJumps(c) > 0, what .. ": the shuffle moved no jump off the first column (the test's premise)")
            -- item buttons are still Blizzard's own: nothing of ours but the Left jump is on them
            for _, b in ipairs(c.bagButtons) do
                for k in pairs(b) do
                    if type(k) == "string" and k:find("^smartNavigation") then eq(k, LEFT, what .. ": field on an item button") end
                end
            end
            c:leaveCombat()
            if name == "folded" then want = row and 5 or nil end
            checkShuffledJumps(c, what .. ", after the fight", want)
            eq(strayJumps(c), 0, what)
            eq(c.blocked, {}, what)
            c:assertClean(what)
        end
    end
end)

-- FirstColumn: a slot is only in the first column if no bag button is further left.
test("bags: slots that finish the icon row get no Left jump when bag buttons are to their left", function()
    local c = newIcons({ dpad = true, sizes = { 3, 0, 0, 0, 0 } })
    c:openBag()
    c:advance(0.5)
    local icons, slots = cellsByKind(c)
    eq({ #icons, #slots }, { 7, 3 })
    for i, e in ipairs(slots) do
        eq({ e.row, e.col }, { 1, 7 + i })
        eq(rawget(e.button, LEFT), nil, "Left jump on a slot with bag buttons to its left")
    end
    c:assertClean("one row")
end)

-- "Nothing ticks. No new event."
test("bags: the icon row registers nothing and leaves nothing ticking", function()
    local off = newIcons({ row = false })
    off:openBag()
    off:advance(1)
    local on = newIcons()
    on:openBag()
    on:advance(1)
    eq(#on._timers, #off._timers, "timers")
    eq(on.stats.addonOnUpdate, off.stats.addonOnUpdate)
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE", "PLAYER_REGEN_ENABLED" }) do
        eq(eventRegistered(on, event), eventRegistered(off, event), event)
    end
end)

-- Spec 0.9.0: the Bag icons choice is gone, and so are its notes in the settings text.
test("bags: the settings text has no notes about the bag icons", function()
    for _, gamepad in ipairs({ true, false }) do
        local c = newIcons({ gamepadUI = gamepad, cvar = "1" })
        c:openBag()
        for _, text in ipairs(textsOf(c)) do check(not text:find("Bag icons"), "row note: " .. text) end
        local win = c.PE:GetModule("bagWindow")
        eq(win.status(win), nil, "a line with nothing wrong")
    end
end)

-- 17. Spec part 4, "Debug-log lines".
test("debug log: the bag icons lines", function()
    local c = newIcons({ debug = true, row = false })
    c:openBag()
    eq(count(c, "bag icons: 7 icons in the top row, 60 slots below"), 0)
    c.PE:SetModuleEnabled("bagWindow", true)
    eq(count(c, "bag icons: 7 icons in the top row, 60 slots below"), 1)
    layoutPass(c)
    c:relayoutBag()
    c:closeBag()
    c:openBag()
    eq(count(c, "bag icons: 7 icons in the top row, 60 slots below"), 1)
    c:collapseBag(1, true)
    eq(count(c, "bag icons: 7 icons in the top row, 48 slots below"), 1)
    c.PE:SetModuleEnabled("bagWindow", false)
    eq(count(c, "bag icons: the game's own places put back"), 1)
    c.PE:SetModuleEnabled("bagWindow", true)
    c:closeBag()
    c.PE:SetModuleEnabled("bagWindow", false)
    eq(count(c, "bag icons: nothing of ours to put back"), 1)
    -- Bag sorting alone, switched off, says nothing about bag icons
    local d = newIcons({ debug = true, row = false })
    d:openBag()
    d.PE:SetModuleEnabled("bags", false)
    for _, line in ipairs(debugLines(d, "bags")) do check(not line:find("bag icons"), "line without Bigger bag: " .. line) end
end)

---------------------------------------------------------------------------
-- 0.8.0: "Bag window" and "Bag sorter" (spec 2026-11-18-0.8.0-design, section 2)
---------------------------------------------------------------------------

-- A client with the saved table given and the features listed switched on
-- afterwards. The bag is already combined unless o.cvar says otherwise.
local function newSplit(o)
    o = o or {}
    return T.new({ on = o.on or {}, gamepadUI = o.gamepadUI, saved = o.saved, setup = function(c)
        c.world.cvars.combinedBags = o.cvar or "1"
        if o.setup then o.setup(c) end
    end })
end

local function optionOf(mod, key)
    for _, o in ipairs(mod.options) do if o.key == key then return o end end
end

-- Sets one saved value of one feature and runs that row's OnChange.
local function choose(c, modKey, key, value)
    local mod = c.PE:GetModule(modKey)
    mod.opts[key] = value
    local opt = optionOf(mod, key)
    check(opt, "no row for " .. key .. " in " .. modKey)
    opt.OnChange(mod, value)
    c:advance(0.5)
end

-- Spec: "Bag window is switched on exactly when Bag sorter was on; size and iconRow are copied."
-- Since 0.9.0 iconRow is no longer read, so it is not copied either (spec 0.9.0, "Bigger bag").
test("split: the first 0.8.0 load switches Bag window on when Bag sorter was on and copies the size", function()
    local _, PE = newSplit({ saved = { version = 1, enabled = { bags = true },
        options = { bags = { size = "large", iconRow = true, dpad = true, sortKey = "r3", showTab = true } } } })
    check(PE:IsModuleEnabled("bagWindow"), "Bag window is not on")
    eq(PE.db.enabled.bagWindow, true)
    local w = PE.db.options.bagWindow
    eq({ w.size, w.iconRow }, { "large", nil })
    -- Spec: "Bag sorter's old size, iconRow and dpad keys are left in the file and no longer read."
    local b = PE.db.options.bags
    eq({ b.size, b.iconRow, b.dpad, b.sortKey, b.showTab }, { "large", true, true, "r3", true })
end)

-- Plan, device check "Bags migration": reloading again changes nothing.
test("split: after the first 0.8.0 load a reload keeps Bag window as the player left it", function()
    local c, PE = newSplit({ saved = { version = 1, enabled = { bags = true },
        options = { bags = { size = "xlarge", iconRow = true } } } })
    eq({ PE.db.enabled.bagWindow, PE.db.options.bagWindow.size }, { true, "xlarge" })
    PE:SetModuleEnabled("bagWindow", false)
    PE.db.options.bagWindow.size = "large"
    local _, PE2 = newSplit({ saved = rawget(c.env, "PocketEssentialsDB") })
    check(not PE2:IsModuleEnabled("bagWindow"), "Bag window came back on after the reload")
    eq(PE2.db.options.bagWindow.size, "large")
    check(PE2:IsModuleEnabled("bags"), "Bag sorter did not stay on")
end)

test("split: the first 0.8.0 load leaves Bag window off when Bag sorter was off, and still copies its size", function()
    local _, PE = newSplit({ saved = { version = 1, enabled = { bags = false },
        options = { bags = { size = "xlarge", iconRow = false } } } })
    check(not PE:IsModuleEnabled("bagWindow"), "Bag window is on")
    eq(PE.db.enabled.bagWindow, false)
    eq(PE.db.options.bagWindow.size, "xlarge")
end)

test("split: a fresh install has both off, Bag window at Normal and no iconRow saved", function()
    local _, PE = newSplit()
    check(not PE:IsModuleEnabled("bagWindow") and not PE:IsModuleEnabled("bags"), "a bag feature is on")
    check(PE.db.enabled.bagWindow ~= true and PE.db.enabled.bags ~= true, "saved on")
    eq({ PE.db.options.bagWindow.size, PE.db.options.bagWindow.iconRow }, { "normal", nil })
    eq({ PE.db.options.bags.showTab, PE.db.options.bags.sortKey }, { true, "l3" })
end)

test("split: once Bag window has been saved it is not copied again", function()
    local _, PE = newSplit({ saved = { version = 1, enabled = { bags = true, bagWindow = false },
        options = { bags = { size = "large", iconRow = true }, bagWindow = { size = "normal", iconRow = false } } } })
    check(not PE:IsModuleEnabled("bagWindow"), "Bag window was switched on again")
    eq({ PE.db.options.bagWindow.size, PE.db.options.bagWindow.iconRow }, { "normal", false }, "left as saved")
end)

test("split: a broken copied size reads as Normal", function()
    local _, PE = newSplit({ saved = { version = 1, enabled = { bags = true },
        options = { bags = { size = "huge", iconRow = "yes" } } } })
    eq({ PE.db.options.bagWindow.size, PE.db.options.bagWindow.iconRow }, { "normal", nil })
end)

-- Spec: "A saved sortKey = "none" becomes l3 at load." The old repair (button back on) is gone.
test("split: a saved Button only becomes the left stick, and a hidden Sort button stays hidden", function()
    local _, PE = newSplit({ saved = { version = 1, enabled = { bags = true },
        options = { bags = { sortKey = "none", showTab = false } } } })
    eq({ PE.db.options.bags.sortKey, PE.db.options.bags.showTab }, { "l3", false })
    local _, PE2 = newSplit({ saved = { version = 1, enabled = {}, options = { bags = { sortKey = "bogus" } } } })
    eq(PE2.db.options.bags.sortKey, "l3")
end)

-- Spec 0.9.0, "Option rows per feature": Bigger bag has only "Bag size".
test("split: Bigger bag is its own feature with only Bag size", function()
    local c = newSplit()
    local win = c.PE:GetModule("bagWindow")
    check(win, "no bagWindow feature")
    eq({ win.label, win.desc, win.order }, { "Bigger bag", "A bigger and better organized bag window.", 31 })
    eq(#win.options, 1)
    local size = win.options[1]
    eq(size.key, "size")
    eq(size.label, "Bag size")
    local got = {}
    for _, ch in ipairs(size.choices) do got[#got + 1] = ch.value .. "=" .. ch.label end
    eq(got, { "normal=Normal", "large=Large", "xlarge=Extra large" })
end)

-- Spec 0.9.0, "Bag sorting": "Sort button on the bag: Show / Hide (showTab)"; "Click a stick in to
-- sort: Left stick / Right stick (sortKey l3 / r3)". The keys stay.
test("split: Bag sorting has Sort button on the bag and Click a stick in to sort, and no How to sort or D-pad to Sort", function()
    local c = newSplit()
    local mod = c.PE:GetModule("bags")
    eq(mod.label, "Bag sorting")
    eq(#mod.options, 2)
    local tab, stick = mod.options[1], mod.options[2]
    eq({ tab.key, tab.label }, { "showTab", "Sort button on the bag" })
    eq({ tab.choices[1].value, tab.choices[1].label, tab.choices[2].value, tab.choices[2].label }, { true, "Show", false, "Hide" })
    eq(#tab.choices, 2)
    eq({ stick.key, stick.label }, { "sortKey", "Click a stick in to sort" })
    eq({ stick.choices[1].value, stick.choices[1].label, stick.choices[2].value, stick.choices[2].label },
        { "l3", "Left stick", "r3", "Right stick" })
    eq(#stick.choices, 2)
    for _, key in ipairs({ "bags", "bagWindow" }) do
        for _, o in ipairs(c.PE:GetModule(key).options) do
            check(o.label ~= "How to sort" and o.label ~= "D-pad to Sort" and o.key ~= "dpad", key .. " still has " .. tostring(o.label))
        end
    end
end)

-- Spec: "Bag window alone: size and icons, with no Sort tab and no stick."
test("split: Bag window alone sizes the bag and moves the icons, with no Sort tab and no stick taken", function()
    local c, PE = newSplit({ on = { "bagWindow" }, gamepadUI = true })
    c:buildBag()
    local win = PE:GetModule("bagWindow")
    win.opts.size = "large"
    c:openBag()
    c:advance(0.5)
    eq(c.bagFrame:GetScale(), 1.25)
    checkRowLayout(c, 7, 60)
    check(not sortButton(c):IsVisible(), "the Sort tab shows without Bag sorter")
    eq(bindings(c), nil, "a stick is taken without Bag sorter")
    c:script(sortButton(c), "OnClick", "LeftButton", false) -- a stale tap: the tab is hidden
    eq(sorts(c), 0, "a stale tap sorted")
    c:assertClean("window alone")
end)

-- Spec: "Bag sorter alone: the Sort tab and stick, at Blizzard's size, icons in the grid."
test("split: Bag sorter alone has the tab and the stick at the game's size, icons in the grid", function()
    local c, PE = newSplit({ on = { "bags" }, gamepadUI = true })
    c:buildBag()
    local win = PE:GetModule("bagWindow")
    win.opts.size = "xlarge" -- saved, but the feature is off
    c:openBag()
    c:advance(0.5)
    eq(c.bagFrame:GetScale(), 1)
    eq(moves(c), 0, "bag buttons were moved without Bag window")
    check(sortButton(c):IsVisible(), "no Sort tab")
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:click(sortButton(c))
    eq(sorts(c), 1)
    c:assertClean("sorter alone")
end)

test("split: Sort stick Right takes the right stick", function()
    local c = newSplit({ on = { "bags" } })
    c:openBag()
    choose(c, "bags", "sortKey", "r3")
    eq(bindings(c), { PADRSTICK = "PocketEssentialsBagSortKey" })
    choose(c, "bags", "sortKey", "l3")
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
end)

-- Spec: "D-pad to Sort is now on whenever the Sort button shows, and off when it does not."
test("split: the d-pad route is there exactly when the Sort tab shows", function()
    local c, PE = newSplit({ on = { "bags" }, gamepadUI = true })
    local grid = c:fillBag(4, 3)
    c:openBag()
    c:advance(0.5)
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN, "Sort button on")
    choose(c, "bags", "showTab", false)
    check(not sortButton(c):IsVisible(), "tab still shows")
    eq(leftJumps(grid, sortButton(c)), {}, "Sort button off")
    is(rawget(sortButton(c), RIGHT), nil)
    choose(c, "bags", "showTab", true)
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN, "Sort button on again")
    -- Bag window alone: no tab, no route
    PE:SetModuleEnabled("bags", false)
    PE:SetModuleEnabled("bagWindow", true)
    c:advance(0.5)
    eq(leftJumps(grid, sortButton(c)), {}, "route with Bag window alone")
    c:assertClean("route follows tab")
end)

-- Controller's brief: switching one off while the other stays on takes down only its own parts.
test("split: Bag window off with Bag sorter on puts the scale and the icons back and keeps the tab", function()
    local c, PE = newSplit({ on = { "bags", "bagWindow" }, gamepadUI = true })
    c:buildBag()
    local win = PE:GetModule("bagWindow")
    win.opts.size = "large"
    c:openBag()
    c:advance(0.5)
    eq(c.bagFrame:GetScale(), 1.25)
    checkRowLayout(c, 7, 60)
    PE:SetModuleEnabled("bagWindow", false)
    c:advance(0.5)
    eq(c.bagFrame:GetScale(), 1)
    eq(places(c), places(gameLayout()), "the icons are not back in the grid")
    check(sortButton(c):IsVisible(), "the tab went with Bag window")
    eq(bindings(c), { PADLSTICK = "PocketEssentialsBagSortKey" })
    c:assertClean("window off")
end)

test("split: Bag sorter off with Bag window on hides the tab, gives the stick back and keeps the size", function()
    local c, PE = newSplit({ on = { "bags", "bagWindow" }, gamepadUI = true })
    local grid = c:fillBag(4, 3)
    PE:GetModule("bagWindow").opts.size = "large"
    c:openBag()
    c:advance(0.5)
    eq(leftJumps(grid, sortButton(c)), FIRST_COLUMN)
    PE:SetModuleEnabled("bags", false)
    c:advance(0.5)
    check(not sortButton(c):IsVisible(), "the tab still shows")
    eq(bindings(c), nil, "the stick is still taken")
    eq(leftJumps(grid, sortButton(c)), {}, "the route is still there")
    eq(c.bagFrame:GetScale(), 1.25)
    eq(cvarWrites(c), {})
    c:assertClean("sorter off")
end)

-- The combined bag setting belongs to the pair: it goes back only when both are off.
test("split: the bag setting goes back only once both features are off", function()
    local c, PE = newSplit({ on = { "bags", "bagWindow" }, cvar = "0" })
    eq(#PE.reloadReasons, 1, "one reload asked for")
    PE:SetModuleEnabled("bags", false)
    eq(#PE.reloadReasons, 1, "the reload went with one feature still on")
    PE:SetModuleEnabled("bagWindow", false)
    eq(#PE.reloadReasons, 0, "a reload is still asked for with both off")
    c:assertClean("cvar")
end)

return { known = KNOWN_FAILURES }
