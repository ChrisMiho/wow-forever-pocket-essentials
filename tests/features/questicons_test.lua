-- Rules for "Quest icons" (QuestIcons.lua, with QuestData.lua), with real quests from QuestieDB.
-- Sources: QuestIcons.lua's header and comments; docs/DECISIONS.md, part "Quest icons / data" of
-- "Decisions made without the maintainer" and the 0.0.6 batch section;
-- docs/superpowers/specs/2026-11-15-fewer-spots-icon-key-reload.md section 1 (spots per objective) and 2.
-- Each test names its source in a comment. Fresh client and addon per test (QuestieDB itself is
-- loaded once per run and only read).
--
-- Skipped, with a notice, when the QuestieDB release is not available (offline).
local T = ...
if not T.questieDB then return { skip = "QuestieDB is not available" } end
local test, eq, check = T.test, T.eq, T.check
local QW = dofile(T.root .. "/tests/lib/questworld.lua")

local KNOWN_FAILURES = {
}

local MINI_YARDS = 466 + 2 / 3          -- minimap diameter at zoom 0 outdoors (QuestIcons.lua MINIMAP_YARDS)

-- Quest log used by most tests: 33 focused (34 spots), 6 in the game's tracker (1 spot), 21 neither (7 spots).
local function basicSpec(over)
    local spec = {
        quests = { { id = QW.MANY }, { id = QW.ONE }, { id = QW.SEVEN } },
        focus = QW.MANY, watched = { QW.ONE },
    }
    for k, v in pairs(over or {}) do spec[k] = v end
    return spec
end

-- A fresh client with the quest log of `spec`, quest icons (and any `on`) switched on.
local function newIcons(spec, on, wait)
    spec = spec or basicSpec()
    local c, PE = T.new({ quest = true, on = on or { "questIcons" }, setup = function(c)
        QW.setup(c, spec)
        if spec.after then spec.after(c) end
    end })
    c:advance(wait or 1.2)
    QW.check(c, PE)
    return c, PE
end

-- What the settings buttons do: store the choice, then run the option's OnChange.
local function setOpt(PE, key, value)
    local mod = PE:GetModule("questIcons")
    mod.opts[key] = value
    for _, opt in ipairs(mod.options) do
        if opt.key == key and opt.OnChange then PE:Safe(mod.key, opt.OnChange, mod, value) end
    end
end

---------------------------------------------------------------------------
-- Reading the screen
---------------------------------------------------------------------------

local function iconsOn(c, parent)
    local out = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == "QuestIcons.lua" and rec.type == "Button" and rec.parent == parent and rec.frame:IsVisible() then
            out[#out + 1] = rec.frame
        end
    end
    return out
end

-- Where an icon on the world map is, as a fraction of the map (x east, y south).
local function mapFraction(c, icon)
    local _, _, _, x, y = icon:GetPoint(1)
    local s = icon:GetScale()
    return x * s / c.worldMapCanvas:GetWidth(), -y * s / c.worldMapCanvas:GetHeight()
end

-- Where an icon on the minimap is, as a fraction of the map, for a player at (px, py), zoom 0 outdoors.
local function miniFraction(c, icon, px, py)
    local _, _, _, dx, dy = icon:GetPoint(1)
    local perYardUnits = c.minimap:GetWidth() / MINI_YARDS
    return px + dx / (QW.WIDTH * perYardUnits), py - dy / (QW.HEIGHT * perYardUnits)
end

-- Which quest owns the pin at this spot of the map (nil if none of `ids` does).
local function questAt(PE, ids, map, fx, fy)
    for _, id in ipairs(ids) do
        for _, p in ipairs(PE.QuestData:GetPinsForQuest(id)[map] or {}) do
            if math.abs(p.x - fx) < 1e-5 and math.abs(p.y - fy) < 1e-5 then return id, p end
        end
    end
    return nil
end

-- { [questID] = number of icons } for the open world map; fails on an icon that belongs to none of `ids`.
local function mapCounts(c, PE, ids, map)
    local counts = {}
    for _, icon in ipairs(iconsOn(c, c.worldMapCanvas)) do
        local fx, fy = mapFraction(c, icon)
        local id = questAt(PE, ids, map, fx, fy)
        check(id, string.format("an icon at %.4f,%.4f belongs to none of the quests %s", fx, fy, T.show(ids)))
        counts[id] = (counts[id] or 0) + 1
    end
    return counts
end

local ALL_IDS = { QW.MANY, QW.SEVEN, QW.ONE, QW.ELSEWHERE, QW.HANDIN }

local function openMap(c, map)
    c:openWorldMap(map or QW.HOME)
    c:advance(0.3)
end

local function ticker(c)
    local rec = c:find(function(r) return r.addonFile == "QuestIcons.lua" and r.type == "Frame" and r.parent == c.minimap end)
    return rec
end
local function tickerRunning(c)
    local rec = ticker(c)
    return rec ~= nil and rec.scripts.OnUpdate ~= nil
end

-- The text box shown after a tap (our own frame on UIParent), or nil before the first tap.
local function labelBox(c)
    local rec = c:find(function(r) return r.addonFile == "QuestIcons.lua" and r.type == "Frame" and r.parent == c.UIParent end)
    return rec and rec.frame
end

local function reloadKeys(PE)
    local out = {}
    for _, r in ipairs(PE.reloadReasons) do out[#out + 1] = r.key end
    return out
end

---------------------------------------------------------------------------
-- Which quests get icons ("Show icons for")
---------------------------------------------------------------------------

-- QuestIcons.lua header + RebuildFilter; DECISIONS: '"Show icons for" defaults to Tracked quests (the
-- quest tracker's quests plus the focused one, since 0.0.3)'.
test("quest icons: Tracked quests shows the tracker's quests plus the focused one", function()
    local c, PE = newIcons()                               -- 33 focused, 6 in the tracker, 21 neither
    eq(PE:GetModule("questIcons").opts.show, "tracked")
    openMap(c)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.MANY] = 5, [QW.ONE] = 1 })
    c:assertClean("tracked")
end)

-- QuestIcons.lua RebuildFilter "focus": the focused quest.
test("quest icons: Focused quest shows only the focused quest", function()
    local c, PE = newIcons()
    setOpt(PE, "show", "focus")
    openMap(c)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.MANY] = 5 })
end)

-- DECISIONS: '"Focused quest" (with nothing focused, the tracker's quests)'.
test("quest icons: Focused quest with nothing focused shows the tracker's quests", function()
    local c, PE = newIcons(basicSpec({ focus = false }))
    c.world.questLog.focus = nil
    setOpt(PE, "show", "focus")
    openMap(c)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.ONE] = 1 })
end)

-- DECISIONS: '"All quests" ... the other choices'.
test("quest icons: All quests shows every quest in the log that has spots on the map", function()
    local c, PE = newIcons()
    setOpt(PE, "show", "all")
    openMap(c)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.MANY] = 5, [QW.ONE] = 1, [QW.SEVEN] = 5 })
end)

-- The map shown is the one the world map shows, not only the player's (QuestIcons.lua RefreshWorldMap).
test("quest icons: the world map shows the icons of the map it is on, not of the player's map", function()
    local c, PE = newIcons(basicSpec({ quests = { { id = QW.MANY }, { id = QW.ELSEWHERE } } }))
    setOpt(PE, "show", "all")
    openMap(c, QW.AWAY)                                    -- Duskwood: only quest 55 has a spot there
    eq(mapCounts(c, PE, ALL_IDS, QW.AWAY), { [QW.ELSEWHERE] = 1 })
    openMap(c, QW.HOME)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.MANY] = 5 })
end)

---------------------------------------------------------------------------
-- Spots per objective
---------------------------------------------------------------------------

-- Spec section 1: '"Spots per objective" ... default 5'; "each objective shows at most five icons".
test("quest icons: spots per objective 5 (the default) draws at most 5 icons for a many-spot objective", function()
    local c, PE = newIcons(basicSpec(), nil)
    eq(PE:GetModule("questIcons").opts.spots, 5)
    local many = #PE.QuestData:GetPinsForQuest(QW.MANY)[QW.HOME]
    check(many > 20, "test data: " .. many .. " spots")
    setOpt(PE, "show", "focus")
    openMap(c)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.MANY] = 5 })
end)

-- Spec section 1: "for each zone where the objective has more pins than the limit" (per map).
test("quest icons: the limit counts per map: the same quest on its other map also draws 5", function()
    local c, PE = newIcons(basicSpec())
    setOpt(PE, "show", "focus")
    local other = #PE.QuestData:GetPinsForQuest(QW.MANY)[QW.OTHER]
    check(other > 5, "test data: quest 33 has only " .. other .. " spots on map 1426")
    openMap(c, QW.OTHER)
    eq(mapCounts(c, PE, ALL_IDS, QW.OTHER), { [QW.MANY] = 5 })
end)

-- Spec section 1: "An objective with limit spots or fewer is untouched."
test("quest icons: an objective with fewer spots than the limit draws them all", function()
    local c, PE = newIcons()
    openMap(c)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME)[QW.ONE], 1)
    setOpt(PE, "spots", 3)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME)[QW.ONE], 1)
end)

-- Spec section 1: "Design: All / 10 / 5 / 3"; 'Change "Spots per objective" to 3, 10 and All: the map
-- follows at once.' With All, every spot is drawn (up to the 150 cap).
test("quest icons: changing spots per objective redraws at once (3, 10, then All draws every spot)", function()
    local c, PE = newIcons(basicSpec({ watched = {} }))
    setOpt(PE, "show", "focus")
    openMap(c)
    local all = #PE.QuestData:GetPinsForQuest(QW.MANY)[QW.HOME]
    setOpt(PE, "spots", 3)
    c:advance(1)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.MANY] = 3 }, "3")
    setOpt(PE, "spots", 10)
    c:advance(1)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.MANY] = 10 }, "10")
    setOpt(PE, "spots", 0)
    c:advance(1)
    local count = mapCounts(c, PE, ALL_IDS, QW.HOME)[QW.MANY]
    eq(count, math.min(all, 150), "All")
    check(count > 20, "All drew only " .. count)
end)

-- Spec section 2 and goal 2: "that spot always has an icon": the arrow's spot is drawn even when it is
-- one of the surplus ones, so 5 + 1.
test("quest icons: the spot the arrow points at gets its icon even when it is a surplus spot", function()
    local c, PE = newIcons(basicSpec({ watched = {} }), { "questIcons", "questArrow" })
    setOpt(PE, "show", "focus")
    openMap(c)
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.MANY] = 5 }, "before walking")
    local surplus
    for _, p in ipairs(PE.QuestData:GetPinsForQuest(QW.MANY)[QW.HOME]) do
        if p.extra then surplus = p break end
    end
    check(surplus, "test data: no surplus spot")
    c.world.player.x, c.world.player.y = surplus.x + 0.002, surplus.y + 0.002
    c:advance(1.5)
    check(rawequal(PE.QuestData:GetArrowPin(), surplus), "the arrow does not point at the surplus spot")
    eq(mapCounts(c, PE, ALL_IDS, QW.HOME), { [QW.MANY] = 6 }, "at the surplus spot")
    local found = false
    for _, icon in ipairs(iconsOn(c, c.worldMapCanvas)) do
        local fx, fy = mapFraction(c, icon)
        if math.abs(fx - surplus.x) < 1e-5 and math.abs(fy - surplus.y) < 1e-5 then found = true end
    end
    check(found, "no icon at the arrow's spot")
end)

-- Spec: 'DECISIONS "Quest icons": At most 150 icons on the world map'; QuestIcons.lua MAP_MAX.
test("quest icons: the world map draws at most 150 icons", function()
    local spec = basicSpec({ focus = QW.MANY, watched = {} })
    local c, PE = T.new({ quest = true, on = {}, setup = function(c)
        spec.quests = QW.crowd(c, 300)
        QW.setup(c, spec)
    end })
    PE:SetModuleEnabled("questIcons", true)
    setOpt(PE, "show", "all")
    setOpt(PE, "spots", 0)
    c:advance(12)
    local pins = 0
    for _, p in ipairs(PE.QuestData:GetPins(QW.HOME)) do if not p.extra then pins = pins + 1 end end
    check(pins > 200, "test data: only " .. pins .. " spots on the map")
    openMap(c)
    eq(#iconsOn(c, c.worldMapCanvas), 150)
    c:assertClean("150")
end)

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

-- DECISIONS: "40 on the minimap at once"; QuestIcons.lua MINI_MAX. The player stands where the quests
-- crowd together (the test checks that more than 40 spots are within the minimap's circle).
test("quest icons: the minimap draws at most 40 icons", function()
    local px, py = 0.4883, 0.3833
    local c, PE = T.new({ quest = true, on = {}, setup = function(c)
        local spec = { quests = QW.crowd(c, 300), focus = QW.MANY, watched = {}, pos = { x = px, y = py } }
        QW.setup(c, spec)
    end })
    PE:SetModuleEnabled("questIcons", true)
    setOpt(PE, "show", "all")
    setOpt(PE, "spots", 0)
    c:advance(12)
    local inside = 0
    for _, p in ipairs(PE.QuestData:GetPins(QW.HOME)) do
        local dx, dy = (p.x - px) * QW.WIDTH, (p.y - py) * QW.HEIGHT
        if dx * dx + dy * dy < 200 * 200 then inside = inside + 1 end
    end
    check(inside > 60, "test data: only " .. inside .. " spots within 200 yards")
    c:advance(0.5)
    eq(#iconsOn(c, c.minimap), 40)
    c:assertClean("40")
end)

local function handInWorld(px, py)
    return basicSpec({ quests = { { id = QW.HANDIN, complete = true } }, focus = QW.HANDIN, watched = {},
        pos = { x = px, y = py } })
end

-- DECISIONS-adjacent: QuestIcons.lua UpdateMinimap "keep hand-in spots on the rim so the direction is
-- visible": alpha 0.6, at distance edge = width/2 - size*0.4 from the centre.
test("quest icons: a hand-in spot outside the minimap radius sits on the rim at 0.6 alpha", function()
    local c, PE = newIcons(handInWorld(0.45, 0.62))      -- the spot is 1600 yards away
    local icons = iconsOn(c, c.minimap)
    eq(#icons, 1)
    eq(icons[1]:GetAlpha(), 0.6)
    local _, _, _, dx, dy = icons[1]:GetPoint(1)
    local edge = c.minimap:GetWidth() / 2 - PE.UI:Px(18) * 0.4
    check(math.abs(math.sqrt(dx * dx + dy * dy) - edge) < 0.01, "not on the rim: " .. dx .. "," .. dy .. " (edge " .. edge .. ")")
    local spot = PE.QuestData:GetPinsForQuest(QW.HANDIN)[QW.HOME][1]
    check(dx > 0 and dy < 0, "the rim icon points the wrong way (spot is east and south)")
    check(spot.x > 0.45 and spot.y > 0.62)
end)

test("quest icons: a hand-in spot inside the minimap radius is drawn in place at full alpha", function()
    local c, PE = newIcons(handInWorld(0.7397 - 0.01, 0.7218 - 0.01))
    local icons = iconsOn(c, c.minimap)
    eq(#icons, 1)
    eq(icons[1]:GetAlpha(), 1)
    local fx, fy = miniFraction(c, icons[1], 0.7397 - 0.01, 0.7218 - 0.01)
    check(math.abs(fx - 0.7397) < 1e-4 and math.abs(fy - 0.7218) < 1e-4, "icon not at the hand-in spot: " .. fx .. "," .. fy)
end)

-- QuestIcons.lua UpdateMinimap: only a hand-in spot is kept on the rim; other spots beyond the circle are not drawn.
test("quest icons: an ordinary spot outside the minimap radius is not drawn", function()
    local c, PE = newIcons(basicSpec({ quests = { { id = QW.ONE } }, focus = QW.ONE, watched = {} }))
    eq(#iconsOn(c, c.minimap), 0)
    check(tickerRunning(c), "the minimap should still be watching: the quest has spots on this map")
end)

-- QuestIcons.lua header of RefreshMinimapData: "The update only runs while this map has icons the
-- 'Show icons for' filter lets through".
test("quest icons: the minimap tick runs while a shown icon is on the player's map", function()
    local c, PE = newIcons()
    check(tickerRunning(c), "no OnUpdate on the minimap ticker")
end)

test("quest icons: the minimap tick stops when no shown icon is on the player's map, and starts again on return", function()
    local c, PE = newIcons()
    check(tickerRunning(c))
    c.world.player.map, c.world.player.x, c.world.player.y = QW.AWAY, 0.5, 0.5   -- Duskwood: nothing of ours shown there
    c:fire("ZONE_CHANGED_NEW_AREA")
    c:advance(1.5)
    check(not tickerRunning(c), "the ticker still has an OnUpdate in a zone with nothing to show")
    eq(#iconsOn(c, c.minimap), 0)
    local ticks = c.stats.addonOnUpdate
    c:advance(2)
    eq(c.stats.addonOnUpdate, ticks, "an OnUpdate of ours ran")
    c.world.player.map, c.world.player.x, c.world.player.y = QW.HOME, 0.45, 0.62
    c:fire("ZONE_CHANGED_NEW_AREA")
    c:advance(1.5)
    check(tickerRunning(c), "the ticker did not start again on the map with icons")
end)

-- QuestIcons.lua RefreshMinimapData/AnyShown: the update runs only while this map has icons the "Show icons
-- for" filter lets through. Quest 6 has a spot on the player's map but is not focused; "Focused quest" is
-- on and the focus is on quest 55 (Duskwood only).
test("quest icons: the minimap tick is stopped while the filter leaves nothing on the player's map, and starts when it shows something", function()
    local c, PE = newIcons(basicSpec({ quests = { { id = QW.ONE }, { id = QW.ELSEWHERE } }, focus = QW.ELSEWHERE,
        watched = { QW.ONE }, pos = { x = 0.5752 - 0.01, y = 0.4825 - 0.01 } }))
    setOpt(PE, "show", "focus")
    c:advance(1)
    check(#PE.QuestData:GetPins(QW.HOME) > 0, "test data: no spot on the player's map")
    eq(#iconsOn(c, c.minimap), 0)
    check(not tickerRunning(c), "the ticker runs although the filter shows nothing here")
    local ticks = c.stats.addonOnUpdate
    c:advance(2)
    eq(c.stats.addonOnUpdate, ticks, "an OnUpdate of ours ran")
    setOpt(PE, "show", "tracked")                         -- the tracker's quest 6 is next to the player
    c:advance(1)
    check(tickerRunning(c), "the ticker did not start when the filter let a spot through")
    eq(#iconsOn(c, c.minimap), 1)
end)

-- CLAUDE.md "Nothing ticks while its feature is off"; QuestIcons.lua OnDisable -> StopTicker.
test("quest icons: the minimap tick is stopped, and no icon left, after the feature is switched off", function()
    local c, PE = newIcons()
    check(tickerRunning(c))
    PE:SetModuleEnabled("questIcons", false)
    c:advance(0.5)
    check(not tickerRunning(c), "the ticker still has an OnUpdate")
    eq(#iconsOn(c, c.minimap), 0)
    openMap(c)
    eq(#iconsOn(c, c.worldMapCanvas), 0)
    local ticks = c.stats.addonOnUpdate
    c:advance(2)
    eq(c.stats.addonOnUpdate, ticks)
    c:assertClean("off")
end)

---------------------------------------------------------------------------
-- The blue haze
---------------------------------------------------------------------------

-- QuestIcons.lua UpdateReloadPrompt: the prompt shows only while the haze is hidden but should be
-- visible again (the setting only comes back with a reload).
test("quest icons: Hide blue haze switched off after being on asks for a reload; back on withdraws it", function()
    local c, PE = newIcons()
    eq(reloadKeys(PE), {}, "asked for a reload while the haze is hidden")
    setOpt(PE, "hideHaze", false)
    eq(reloadKeys(PE), { "questIcons" })
    eq(PE.reloadReasons[1].reason, "Reload to bring back the blue quest areas on the minimap.")
    setOpt(PE, "hideHaze", true)
    eq(reloadKeys(PE), {})
end)

test("quest icons: the world map's blue area is hidden while on and put back when Hide blue haze is off", function()
    local c, PE = newIcons()
    openMap(c)
    eq(c.blobPin:GetAlpha(), 0)
    setOpt(PE, "hideHaze", false)
    c:advance(0.3)
    eq(c.blobPin:GetAlpha(), 1)
end)

---------------------------------------------------------------------------
-- Tapping an icon
---------------------------------------------------------------------------

local function firstIcon(c)
    local icons = iconsOn(c, c.worldMapCanvas)
    check(#icons > 0, "no icon on the world map to tap")
    return icons[1]
end

-- DECISIONS: "Tapping an icon shows a short text box"; QuestIcons.lua header: "...or when the same icon
-- is tapped again". OnPinClick.
test("quest icons: tapping an icon shows the text box with the quest's name; a second tap hides it", function()
    local c, PE = newIcons(basicSpec({ quests = { { id = QW.ONE } }, focus = QW.ONE, watched = {} }))
    openMap(c)
    check(labelBox(c) == nil or not labelBox(c):IsShown(), "text box shown before any tap")
    local icon = firstIcon(c)
    c:click(icon)
    local box = labelBox(c)
    check(box and box:IsShown(), "no text box after a tap")
    check(box.text:GetText():find("Bounty on Garrick Padfoot", 1, true), "the text box does not name the quest: " .. tostring(box.text:GetText()))
    c:click(icon)
    check(not box:IsShown(), "a second tap did not hide the text box")
    c:click(icon)
    check(box:IsShown(), "a third tap did not show it again")
    c:assertClean("tap")
end)

-- DECISIONS: "It hides after 5 seconds."
test("quest icons: the text box hides by itself after 5 seconds", function()
    local c, PE = newIcons(basicSpec({ quests = { { id = QW.ONE } }, focus = QW.ONE, watched = {} }))
    openMap(c)
    c:click(firstIcon(c))
    local box = labelBox(c)
    check(box:IsShown())
    c:advance(4.5)
    check(box:IsShown(), "hidden too early")
    c:advance(1)
    check(not box:IsShown(), "still shown after 5 seconds")
end)

-- DECISIONS "Quest icons / data": "Dungeon objectives show an icon on the dungeon entrance"; QuestData.lua
-- pin.inside is the dungeon's name and LabelText adds "Inside <dungeon>". Quest 90's loot is in Shadowfang Keep.
test("quest icons: a dungeon objective has an icon on the entrance and its text box says Inside <dungeon>", function()
    local c, PE = newIcons({ quests = { { id = 90 } }, focus = 90, watched = {} })
    local pins = PE.QuestData:GetPinsForQuest(90)
    local map, inside
    for m, list in pairs(pins) do
        for _, p in ipairs(list) do if p.inside then map, inside = m, p end end
    end
    check(inside, "test data: quest 90 has no spot inside a dungeon")
    c:openWorldMap(map)
    c:advance(0.3)
    local tapped
    for _, icon in ipairs(iconsOn(c, c.worldMapCanvas)) do
        local fx, fy = mapFraction(c, icon)
        local _, p = questAt(PE, { 90 }, map, fx, fy)
        if p and p.inside then tapped = icon break end
    end
    check(tapped, "no icon on the dungeon entrance")
    c:click(tapped)
    check(labelBox(c):IsShown())
    check(labelBox(c).text:GetText():find("Inside " .. inside.inside, 1, true), "the text box does not say Inside: " .. tostring(labelBox(c).text:GetText()))
end)

-- QuestIcons.lua header: "...when another icon is tapped" the box moves to that icon.
test("quest icons: tapping another icon moves the text box to it", function()
    local c, PE = newIcons(basicSpec({ watched = { QW.ONE } }))
    openMap(c)
    local icons = iconsOn(c, c.worldMapCanvas)
    check(#icons >= 2)
    c:click(icons[1])
    local box = labelBox(c)
    local first = box.text:GetText()
    local other
    for _, icon in ipairs(icons) do
        local fx, fy = mapFraction(c, icon)
        if questAt(PE, { QW.ONE }, QW.HOME, fx, fy) then other = icon end
    end
    check(other, "test data: no icon of quest 6")
    c:click(other)
    check(box:IsShown())
    check(box.text:GetText() ~= first, "the text box still shows the first icon's text")
    check(box.text:GetText():find("Bounty on Garrick Padfoot", 1, true))
end)

-- QuestIcons.lua OnMapHide: the box goes away when the map is closed.
test("quest icons: closing the world map hides the text box", function()
    local c, PE = newIcons(basicSpec({ quests = { { id = QW.ONE } }, focus = QW.ONE, watched = {} }))
    openMap(c)
    c:click(firstIcon(c))
    local box = labelBox(c)
    check(box:IsShown())
    c:closeWorldMap()
    c:advance(0.2)
    check(not box:IsShown())
end)

---------------------------------------------------------------------------
-- Debug log (docs/superpowers/specs/2026-11-17-debug-log.md)
---------------------------------------------------------------------------

-- The debug log's lines that contain `text` (plain match).
local function logLines(c, text)
    local out = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        if line:find(text, 1, true) then out[#out + 1] = line end
    end
    return out
end

local FIVE = { { id = QW.MANY }, { id = QW.SEVEN }, { id = QW.ONE }, { id = QW.HANDIN, complete = true }, { id = QW.ELSEWHERE } }

-- Spec "What is written", Quest data: "each rebuild as one line (quests in the log, quests rebuilt, icons
-- made, time taken)". Five quests are rebuilt in two steps (QuestData.lua QUESTS_PER_STEP = 4): still one line.
test("debug log: a rebuild of five quests writes one rebuild line, not one per quest or step", function()
    local c, PE = newIcons(basicSpec({ quests = FIVE }))
    PE:SetDebug(true)
    setOpt(PE, "cluster", 5)                               -- every quest is built again
    c:advance(1.5)
    local lines = logLines(c, "questData: rebuild:")
    eq(#lines, 1, "rebuild lines")
    check(lines[1]:find("5 quests in log, 5 rebuilt, %d+ icons on %d+ maps, %d+ ms"), lines[1])
    PE.QuestData:RequestRebuild()                          -- nothing to build again: one more line
    c:advance(1)
    lines = logLines(c, "questData: rebuild:")
    eq(#lines, 2, "rebuild lines after a second rebuild")
    check(lines[2]:find("5 quests in log, 0 rebuilt", 1, true), lines[2])
    c:assertClean("rebuild line")
end)

-- Spec "Cost while off": "No text is built, nothing is stored."
test("debug log: with the log off the quest features write nothing", function()
    local c, PE = newIcons(basicSpec({ quests = FIVE }))
    setOpt(PE, "cluster", 5)
    openMap(c)
    c:click(iconsOn(c, c.worldMapCanvas)[1])
    c:closeWorldMap()
    c:advance(1.5)
    eq(#rawget(c.env, "PocketEssentialsDB").debug.lines, 0)
end)

-- Spec "What is written": "One line per decision, never per frame"; "Not doing: No log of every frame or
-- every update of the arrow or minimap."
test("debug log: the minimap tick writes nothing while nothing changes", function()
    local c, PE = newIcons()
    PE:SetDebug(true)
    c:advance(0.5)
    check(tickerRunning(c), "test setup: the minimap ticker is not running")
    local count, ticks = #logLines(c, ""), c.stats.addonOnUpdate
    c:advance(10)
    check(c.stats.addonOnUpdate >= ticks + 90, "test setup: the minimap ticker did not tick")
    eq(#logLines(c, ""), count, "lines written by ticks")
end)

-- Spec "What is written", Quest icons: "world map opened / closed with the number of icons drawn; minimap
-- icons started / stopped and why".
test("debug log: the world map and the minimap write their lines, by map number", function()
    local c, PE = newIcons()                               -- 5 icons of quest 33 and 1 of quest 6 are shown
    PE:SetDebug(true)
    openMap(c)
    eq(#logLines(c, "questIcons: world map opened"), 1)
    eq(#logLines(c, "questIcons: world map shows map " .. QW.HOME .. ": 6 icons"), 1)
    c:click(iconsOn(c, c.worldMapCanvas)[1])
    eq(#logLines(c, "questIcons: icon tapped (world map): quest "), 1)
    c:closeWorldMap()
    eq(#logLines(c, "questIcons: world map closed"), 1)
    c.world.player.map, c.world.player.x, c.world.player.y = QW.AWAY, 0.5, 0.5
    c:fire("ZONE_CHANGED_NEW_AREA")
    c:advance(1.5)
    eq(#logLines(c, "questData: zone change noticed, map " .. QW.AWAY), 1)
    eq(#logLines(c, "questIcons: minimap icons stopped: no icons on map " .. QW.AWAY), 1)
    c:assertClean("icon lines")
end)

---------------------------------------------------------------------------
-- "Icons on" (spec 2026-11-18-tidier-settings, part 2)
---------------------------------------------------------------------------

local function iconsOnRow(PE)
    for _, o in ipairs(PE:GetModule("questIcons").options) do if o.label == "Icons on" then return o end end
end

test("quest icons: Icons on is one row for map and minimap, with no Map icons or Minimap icons rows", function()
    local c, PE = newIcons()
    local mod, opt = PE:GetModule("questIcons"), iconsOnRow(PE)
    check(opt, "no Icons on row")
    local got = {}
    for _, ch in ipairs(opt.choices) do got[#got + 1] = ch.value .. "=" .. ch.label end
    eq(got, { "both=Map and minimap", "map=Map only", "mini=Minimap only" })
    for _, o in ipairs(mod.options) do
        check(o.key ~= "map" and o.key ~= "mini", "a row of its own for " .. tostring(o.key))
        if o.key == "hideHaze" then eq(o.toggle, true, "Hide blue haze is not a toggle") end
    end
    eq(opt.get(mod), "both", "the default")
end)

test("quest icons: each Icons on choice saves map and mini, and both off marks none", function()
    local c, PE = newIcons()
    local mod, opt = PE:GetModule("questIcons"), iconsOnRow(PE)
    for value, want in pairs({ both = { true, true }, map = { true, false }, mini = { false, true } }) do
        opt.set(mod, value)
        eq({ mod.opts.map, mod.opts.mini }, want, value)
        eq(opt.get(mod), value, value .. " read back")
    end
    mod.opts.map, mod.opts.mini = false, false
    eq(opt.get(mod), nil, "both off")
end)

test("quest icons: Map only takes the icons off the minimap, and Map and minimap puts them back", function()
    local c, PE = newIcons()
    local mod, opt = PE:GetModule("questIcons"), iconsOnRow(PE)
    local before = #iconsOn(c, c.minimap)
    check(before > 0, "no minimap icons to start with (the test's premise)")
    opt.set(mod, "map")
    opt.OnChange(mod, "map")
    c:advance(0.5)
    eq(#iconsOn(c, c.minimap), 0)
    opt.set(mod, "both")
    opt.OnChange(mod, "both")
    c:advance(0.5)
    eq(#iconsOn(c, c.minimap), before)
    c:assertClean("icons on")
end)

return { known = KNOWN_FAILURES }
