-- Rules for the square map of Controller layout 0.19.0 (MapLook.lua).
-- Source: docs/superpowers/specs/2026-11-25-0.19.0-square-map.md ("The edge", "The words inside
-- the map", "The pieces the game hangs on the map's rim", "Off, and failing safely", "Logging",
-- "Tests") and the plan's Review Focus. Fresh client and addon per test; PE.MapLook is called
-- directly (ControllerLayout calls it in the game; the last tests go through the layout).
-- The plan's numbers and the "Map look" row are in layout_test.lua.
--
-- These prove the logic against the stand-in client. Whether the game draws a square map for
-- the square mask, and keeps its pieces where they are put, only the device can show.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local W = 768 * 1280 / 720 -- the stand-in's screen in UI units
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK = "ui-hud-minimap-frame-generic-mask"
local REFUSED = "the square mask was refused"
local TEXT_REFUSED = "The square map is not possible on this game version: the map stays round."
local SQUARE, ROUND = { mapLook = 1 }, { mapLook = 0 }

local function near(a, b, msg)
    check(type(a) == "number" and math.abs(a - b) < 1e-6, (msg or "number") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

-- A client with the map's pieces as the game builds them (c:addMapParts) and the addon loaded,
-- the Debug log on. opts.parts = false: the stand-in's bare map. opts.map: for addMapParts.
-- opts.setup(c, parts) runs before the load. Returns c, PE, Look, parts.
local function new(opts)
    opts = opts or {}
    local parts
    local c, PE = T.new({ setup = function(c)
        if opts.parts ~= false then parts = c:addMapParts(opts.map) end
        if opts.setup then opts.setup(c, parts) end
    end })
    PE:SetDebug(true)
    return c, PE, PE.MapLook, parts
end

-- A client with the square map placed (checked).
local function placed(opts)
    local c, PE, Look, parts = new(opts)
    Look:Place(SQUARE, false)
    check(Look:IsSquare() == true, "the square map was not placed")
    return c, PE, Look, parts
end

local function st(c, region) return c._state(region) end

local function maskCalls(c)
    local out = {}
    for i, call in ipairs(c:callsTo("Minimap:SetMaskTexture")) do out[i] = call.args[1] end
    return out
end

-- Every frame MapLook.lua made.
local function lookFrames(c)
    local out = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == "MapLook.lua" then out[#out + 1] = rec end
    end
    return out
end

-- Its two frames: the edge (on the map's parent) and the words (on the map).
local function edgeAndWords(c)
    local edge, words
    for _, rec in ipairs(lookFrames(c)) do
        if rec.parent == c.env.Minimap then words = rec else edge = rec end
    end
    return edge, words
end

-- A region's rectangle from the screen's bottom centre: { left, bottom, right, top }.
local function rectOf(c, region)
    local l, r, t, b = c._rect(region)
    return { l - W / 2, b, r - W / 2, t }
end

local function sameRect(got, want, what)
    for i = 1, 4 do near(got[i], want[i], what .. " " .. i) end
end

-- The map look's debug lines (after "map look: "), in order.
local function notes(c)
    local out = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        local text = line:match("^%S+ ctrlLayout: map look: (.*)$")
        if text then out[#out + 1] = text end
    end
    return out
end

local function noted(c, text)
    local n = 0
    for _, l in ipairs(notes(c)) do if l == text then n = n + 1 end end
    return n
end

local function notedLike(c, pattern)
    local n = 0
    for _, l in ipairs(notes(c)) do if l:find(pattern) then n = n + 1 end end
    return n
end

-- The font strings of the words' frame: name (top), clock (bottom right), coords (bottom left).
local function wordsOf(c)
    local _, words = edgeAndWords(c)
    check(words ~= nil, "no words frame")
    local out = {}
    for _, r in ipairs(words.regions) do
        local rec = st(c, r)
        if rec.type == "FontString" then
            local point = rec.points[1].point
            out[point == "TOP" and "name" or point == "BOTTOMRIGHT" and "clock" or "coords"] = rec
        end
    end
    return out, words
end

local function strips(c, rec)
    local out = {}
    for _, r in ipairs(rec.regions) do
        if st(c, r).type == "Texture" then out[#out + 1] = st(c, r) end
    end
    return out
end

local function pointOf(c, region)
    local p = st(c, region).points[1]
    return p and { p.point, p.rel, p.relPoint, p.x, p.y } or nil
end

local function eventsHeld(c)
    local n = 0
    for _, rec in ipairs(lookFrames(c)) do for _ in pairs(rec.events) do n = n + 1 end end
    return n
end

local function onUpdates(c)
    local n = 0
    for _, rec in ipairs(lookFrames(c)) do if rec.scripts.OnUpdate then n = n + 1 end end
    return n
end

---------------------------------------------------------------------------
-- Round: nothing at all
---------------------------------------------------------------------------

test("map look: with Round nothing is made, called, registered or written", function()
    local c, _, Look = new()
    local before = #c.calls
    Look:Place(ROUND, false)
    Look:Place({}, true)
    Look:Place(nil, false)
    Look:Restore()
    c:advance(30)
    eq(#c.calls, before, "a game call was made")
    eq(#lookFrames(c), 0, "a frame was made")
    eq(notes(c), {})
    eq(Look:IsSquare(), false)
    eq(Look:Status(), nil)
    eq(Look:SnapshotPieces(), {})
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The mask
---------------------------------------------------------------------------

test("map look: Square gives the white square mask once, and again only after a redraw", function()
    local c, _, Look = new()
    Look:Place(SQUARE, false)
    eq(maskCalls(c), { SQUARE_MASK })
    eq(st(c, c.env.Minimap).mask, SQUARE_MASK)
    eq(Look:IsSquare(), true)
    Look:Place(SQUARE, false)
    Look:Place(SQUARE)
    eq(maskCalls(c), { SQUARE_MASK }, "given again with nothing changed")
    Look:Place(SQUARE, true)
    eq(maskCalls(c), { SQUARE_MASK, SQUARE_MASK }, "after a redraw")
    eq(noted(c, "the square mask given"), 1)
    eq(noted(c, "the square mask given again after a redraw"), 1)
    c:assertClean()
end)

test("map look: a second placement with nothing changed makes no game call and writes no line", function()
    local c, _, Look = placed()
    local calls, lines = #c.calls, #notes(c)
    Look:Place(SQUARE, false)
    Look:Place(SQUARE, false)
    eq(#c.calls, calls, "a game call was made again")
    eq(#notes(c), lines, "a line was written again")
    eq(#lookFrames(c), 2, "frames were made again")
end)

test("map look: Restore gives the game's round mask back", function()
    local c, _, Look = placed()
    Look:Restore()
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK })
    eq(Look:IsSquare(), false)
    eq(noted(c, "the game's round mask given back"), 1)
    -- Once: a second put-back does nothing.
    Look:Restore()
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK })
    c:assertClean()
end)

test("map look: a mask the game refuses is the fallback, said once over three placements", function()
    local c, _, Look, parts = new({ setup = function(c) c.world.maskRefused = true end })
    for _ = 1, 3 do Look:Place(SQUARE, true) end
    eq(Look:IsSquare(), false)
    eq(noted(c, REFUSED), 1)
    eq(#maskCalls(c), 1, "the refused call was tried again")
    eq(Look:Status(), TEXT_REFUSED)
    -- The round look at the square's spot: no edge of ours, the words and the lowered map stay.
    local edge, words = edgeAndWords(c)
    eq(edge.shown, false, "the square edge shows on a round map")
    eq(words.shown, true)
    eq(parts.strip:IsShown(), false)
    -- Round again: the game's mask is not given back (the square one never went on).
    Look:Restore()
    eq(#maskCalls(c), 1)
    eq(Look:Status(), nil)
    c:assertClean()
end)

test("map look: a client without SetMaskTexture is the same fallback", function()
    local c, _, Look = new({ setup = function(c) rawset(c.env.Minimap, "SetMaskTexture", false) end })
    for _ = 1, 3 do Look:Place(SQUARE, false) end
    eq(Look:IsSquare(), false)
    eq(noted(c, REFUSED), 1)
    eq(maskCalls(c), {})
    eq(Look:Status(), TEXT_REFUSED)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The spot, the edge, the faint line
---------------------------------------------------------------------------

test("map look: the map is lowered so its bottom is 5 up, and the edge box is -100..100 by 4..204", function()
    local c, PE, Look, parts = new()
    -- As the game places it: the map's frame 30 up, so the map 57.5 to 255.5 up.
    sameRect(rectOf(c, c.env.Minimap), { -99, 57.5, 99, 255.5 }, "the map before")
    Look:Place(SQUARE, false)
    sameRect(rectOf(c, c.env.Minimap), { -99, 5, 99, 203 }, "the map")
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10, -22.5 })
    local edge, words = edgeAndWords(c)
    eq(edge.parent, parts.box, "the edge is not on the map's parent")
    eq(edge.shown, true)
    sameRect(rectOf(c, edge.frame), { -100, 4, 100, 204 }, "the edge box")
    local box = PE.LayoutPlan.MapBox(SQUARE)
    sameRect(rectOf(c, edge.frame), box, "the edge box against the plan's")
    eq(edge.level, st(c, c.env.Minimap).level - 1)
    eq(edge.mouse, false)
    -- Four black strips, each 1 unit.
    local black = strips(c, edge)
    eq(#black, 4)
    local thin = 0
    for _, s in ipairs(black) do
        eq(s.color, { 0, 0, 0, 1 })
        local r = rectOf(c, s.frame)
        if math.abs((r[3] - r[1]) - 1) < 1e-6 or math.abs((r[4] - r[2]) - 1) < 1e-6 then thin = thin + 1 end
    end
    eq(thin, 4, "a strip of the edge is not 1 unit")
    -- The faint line: white at 12%, on the words' frame, on the map's outermost unit.
    local line = strips(c, words)
    eq(#line, 4)
    for _, s in ipairs(line) do
        eq(s.color, { 1, 1, 1, 0.12 })
        local r = rectOf(c, s.frame)
        check(r[1] >= -99 - 1e-6 and r[3] <= 99 + 1e-6 and r[2] >= 5 - 1e-6 and r[4] <= 203 + 1e-6, "the faint line is outside the map")
    end
    eq(notedLike(c, "^the edge's box l=582%.7 b=4%.0 w=200%.0 h=200%.0$"), 1, table.concat(notes(c), " | "))
    eq(notedLike(c, "^the map's frame lowered inside its piece: its bottom from 30%.0 to %-22%.5"), 1)
    c:assertClean()
end)

test("map look: the words' frame is on the map, over it, and takes no taps", function()
    local c = placed()
    local _, words = edgeAndWords(c)
    eq(words.parent, c.env.Minimap)
    sameRect(rectOf(c, words.frame), { -99, 5, 99, 203 }, "the words' frame")
    eq(words.level, st(c, c.env.Minimap).level + 10)
    eq(words.mouse, false)
    eq(words.shown, true)
end)

test("map look: at another map size the bottom is still 5 up and the edge still 1 unit", function()
    -- Square chosen, the reload not done yet: the map is still at 70%.
    local c, _, Look, parts = new({ map = { scale = 0.7 } })
    Look:Place(SQUARE, false)
    local map = rectOf(c, c.env.Minimap)
    near(map[2], 5, "the map's bottom")
    near(map[3] - map[1], 198 * 0.7, "the map's width")
    local edge = edgeAndWords(c)
    local r = rectOf(c, edge.frame)
    sameRect(r, { map[1] - 1, 4, map[3] + 1, map[4] + 1 }, "the edge box")
    -- Across the game's own number stays (10 right of the piece's middle).
    near((map[1] + map[3]) / 2, 0, "the map's middle")
    eq(pointOf(c, parts.box)[4], 10 / 0.7)
    c:assertClean()
end)

test("map look: Restore puts the map's frame back where the game had it", function()
    local c, _, Look, parts = placed()
    Look:Restore()
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10, 30 })
    sameRect(rectOf(c, c.env.Minimap), { -99, 57.5, 99, 255.5 }, "the map")
    local edge, words = edgeAndWords(c)
    eq(edge.shown, false)
    eq(words.shown, false)
end)

test("map look: after the game anchors the map's frame again it is lowered again; while Round the hook does nothing", function()
    local c, _, Look, parts = placed()
    local function hooks()
        local n = 0
        for _, call in ipairs(c:callsTo("hooksecurefunc")) do if call.args[2] == "SetHeaderUnderneath" then n = n + 1 end end
        return n
    end
    eq(hooks(), 1)
    parts.cluster:SetHeaderUnderneath(true) -- Edit Mode applying the Size or the strip's setting
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10, -22.5 })
    -- In a fight: when it ends, once.
    c:enterCombat()
    parts.cluster:SetHeaderUnderneath(true)
    parts.cluster:SetHeaderUnderneath(true)
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10, 30 }, "moved in a fight")
    c:leaveCombat()
    c:advance(0.1)
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10, -22.5 })
    -- Round: the game's place stays.
    Look:Restore()
    parts.cluster:SetHeaderUnderneath(true)
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10, 30 })
    eq(hooks(), 1, "hooked again")
    c:assertClean()
end)

test("map look: a map's frame the game moved meanwhile is not put back over the game's place", function()
    local c, _, Look, parts = placed()
    -- Another layout with the strip on top: the game anchors the frame at its top.
    parts.box:ClearAllPoints()
    parts.box:SetPoint("TOP", parts.cluster, "TOP", 10, -30)
    Look:Restore()
    eq(pointOf(c, parts.box), { "TOP", parts.cluster, "TOP", 10, -30 })
    -- And Square on a frame anchored that way leaves it alone, said once.
    Look:Place(SQUARE, false)
    Look:Place(SQUARE, false)
    eq(pointOf(c, parts.box), { "TOP", parts.cluster, "TOP", 10, -30 })
    eq(noted(c, "the map's frame is not anchored under the map's piece: not lowered"), 1)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The strip and the clock
---------------------------------------------------------------------------

test("map look: the game's strip and its clock are hidden, and shown again by Restore", function()
    local c, _, Look, parts = placed()
    eq(parts.strip:IsShown(), false)
    eq(parts.clock:IsShown(), false)
    eq(#c:callsTo("MinimapCluster.ZoneTextButton:Hide"), 1)
    eq(#c:callsTo("TimeManagerClockButton:Hide"), 1)
    Look:Restore()
    eq(parts.strip:IsShown(), true)
    eq(parts.clock:IsShown(), true)
    c:assertClean()
end)

test("map look: a strip that was hidden before stays hidden after Restore", function()
    local c, _, Look, parts = new({ setup = function(c, parts) c._state(parts.clock).shown = false end })
    Look:Place(SQUARE, false)
    eq(#c:callsTo("TimeManagerClockButton:Hide"), 0)
    Look:Restore()
    eq(parts.strip:IsShown(), true)
    eq(parts.clock:IsShown(), false)
    eq(#c:callsTo("TimeManagerClockButton:Show"), 0)
end)

test("map look: a strip the game showed again is hidden at the next placement", function()
    local c, _, Look, parts = placed()
    parts.strip:Show()
    Look:Place(SQUARE, true)
    eq(parts.strip:IsShown(), false)
    Look:Restore()
    eq(parts.strip:IsShown(), true)
end)

---------------------------------------------------------------------------
-- The words
---------------------------------------------------------------------------

test("map look: the place name is the game's, top middle, in the zone's colour, outlined", function()
    local c = placed({ setup = function(c)
        c.world.zoneText = "Stormwind City"
        c.world.pvpType = "sanctuary"
    end })
    local w = wordsOf(c)
    eq(w.name.text, "Stormwind City")
    eq(w.name.textColor, { 0.41, 0.8, 0.94, 1 })
    eq(w.name.font[3], "OUTLINE")
    eq(w.name.justifyH, "CENTER")
    eq({ w.name.points[1].point, w.name.points[1].x, w.name.points[1].y }, { "TOP", 0, -4 })
    for _, key in ipairs({ "clock", "coords" }) do eq(w[key].font[3], "OUTLINE", key) end
    -- Each kind of zone as the game's strip colours it; none is the game's gold.
    for kind, colour in pairs({ arena = { 1.0, 0.1, 0.1, 1 }, friendly = { 0.1, 1.0, 0.1, 1 }, hostile = { 1.0, 0.1, 0.1, 1 },
        contested = { 1.0, 0.7, 0.0, 1 }, combat = { 1.0, 0.82, 0.0, 1 } }) do
        c.world.pvpType = kind
        c:fire("ZONE_CHANGED")
        eq(w.name.textColor, colour, kind)
    end
    c.world.pvpType = nil
    c:fire("ZONE_CHANGED_NEW_AREA")
    eq(w.name.textColor, { 1.0, 0.82, 0.0, 1 }, "no kind")
end)

test("map look: the place name follows the zone events while Square, and not after Restore", function()
    local c, _, Look = placed()
    local w = wordsOf(c)
    eq(w.name.text, "Elwynn Forest")
    eq(eventsHeld(c), 3)
    c.world.zoneText = "Goldshire"
    c:fire("ZONE_CHANGED")
    eq(w.name.text, "Goldshire")
    c.world.zoneText = "Lion's Pride Inn"
    c:fire("ZONE_CHANGED_INDOORS")
    eq(w.name.text, "Lion's Pride Inn")
    Look:Restore()
    eq(eventsHeld(c), 0)
    c.world.zoneText = "Westfall"
    c:fire("ZONE_CHANGED_NEW_AREA")
    eq(w.name.text, "Lion's Pride Inn", "updated while Round")
end)

-- Review focus: a place name longer than the map.
test("map look: a place name longer than the map is cut with ... and is never wider than 190", function()
    -- The stand-in's letters are 6 wide at this font: 31 fit in 190.
    local c = placed({ setup = function(c) c.world.zoneText = "The Temple of Atal'Hakkar" end })
    local w = wordsOf(c)
    eq(w.name.text, "The Temple of Atal'Hakkar", "a name that fits was cut")
    for _, long in ipairs({ "The Temple of Atal'Hakkar, the Pit of Refuse", "Blackrock Depths: the Grim Guzzler's back room",
        string.rep("W", 80), "Na\195\175ve caf\195\169 of the \195\169lite \195\169migr\195\169s of Atal'Hakkar" }) do
        c.world.zoneText = long
        c:fire("ZONE_CHANGED")
        local text = w.name.text
        check(text:sub(-3) == "...", "not cut with ...: " .. text)
        check(w.name.frame:GetUnboundedStringWidth() <= 190, "wider than 190: " .. text)
        local kept = text:sub(1, -4)
        check(#kept > 0 and long:sub(1, #kept) == kept or long:sub(1, #kept):gsub("%s+$", "") == kept, "not the name's beginning: " .. text)
        -- A character of several bytes is never cut in half.
        local last = kept:byte(#kept)
        local nextByte = long:byte(#kept + 1)
        check(not (nextByte and nextByte >= 128 and nextByte <= 191 and last and last >= 128), "a character was cut in half: " .. text)
    end
    c:assertClean()
end)

test("map look: the clock shows the game's time, the realm's or the local one, 12 or 24 hours", function()
    local c, _, Look = placed({ setup = function(c) c.world.gameTime = { 14, 5 } end })
    local w = wordsOf(c)
    eq(w.clock.text, "2:05")
    eq({ w.clock.points[1].point, w.clock.points[1].x, w.clock.points[1].y }, { "BOTTOMRIGHT", -4, 4 })
    for _, case in ipairs({ { { 0, 7 }, "12:07" }, { { 12, 0 }, "12:00" }, { { 23, 59 }, "11:59" }, { { 9, 30 }, "9:30" } }) do
        c.world.gameTime = case[1]
        c:advance(21)
        eq(w.clock.text, case[2])
    end
    c.world.cvars.timeMgrUseMilitaryTime = "1"
    c.world.gameTime = { 14, 5 }
    c:advance(21)
    eq(w.clock.text, "14:05")
    c.world.gameTime = { 0, 7 }
    c:advance(21)
    eq(w.clock.text, "00:07")
    -- Local time when the game's own clock is set to it.
    c.world.cvars.timeMgrUseLocalTime = "1"
    c:advance(21)
    local now, earlier = os.date("%H:%M"), os.date("%H:%M", os.time() - 60)
    check(w.clock.text == now or w.clock.text == earlier, "local time: " .. tostring(w.clock.text))
    Look:Restore()
    c:assertClean()
end)

test("map look: the clock is read at most once in 20 seconds", function()
    local c = placed({ setup = function(c) c.world.gameTime = { 14, 5 } end })
    local w = wordsOf(c)
    c.world.gameTime = { 14, 6 }
    c:advance(15)
    eq(w.clock.text, "2:05", "read again before 20 seconds")
    c:advance(6)
    eq(w.clock.text, "2:06")
end)

test("map look: with the game's coordinates switched off, our own text is drawn bottom left", function()
    local c, _, Look, parts = placed({ setup = function(c) c.world.player = { map = 1429, x = 0.4521, y = 0.6104, facing = 0 } end })
    local w = wordsOf(c)
    eq(w.coords.text, "45.2, 61.0")
    eq({ w.coords.points[1].point, w.coords.points[1].x, w.coords.points[1].y }, { "BOTTOMLEFT", 4, 4 })
    eq(parts.coords:IsShown(), false, "the game's empty text was left where it was")
    eq(#c:callsTo("PlayerCoords:SetPoint"), 0, "the game's text was moved")
    eq(noted(c, "coordinates: our own text in the map's bottom left corner (the game's own coordinates are switched off)"), 1)
    -- Twice a second, and only written when it reads differently.
    c.world.player.x = 0.5
    c:advance(0.3)
    eq(w.coords.text, "45.2, 61.0")
    c:advance(0.3)
    eq(w.coords.text, "50.0, 61.0")
    -- No position (a loading screen, a dungeon): nothing.
    c.world.player.map = nil
    c:advance(0.6)
    eq(w.coords.text, "")
    Look:Restore()
    eq(parts.coords:IsShown(), true)
    c:assertClean()
end)

test("map look: with the game's coordinates on, the game's own text is moved into the corner and put back", function()
    local c, _, Look, parts = placed({ setup = function(c)
        c.world.cvars.minimapShowPlayerCoords = "1"
        c.world.player = { map = 1429, x = 0.4521, y = 0.6104, facing = 0 }
    end })
    local map = c.env.Minimap
    eq(pointOf(c, parts.coords), { "BOTTOMLEFT", map, "BOTTOMLEFT", 4, 4 })
    eq(st(c, parts.coords).level, st(c, map).level + 10)
    eq(parts.coords:IsShown(), true)
    eq(wordsOf(c).coords.text, "", "our own text shows beside the game's")
    eq(noted(c, "coordinates: the game's own text, moved into the map's bottom left corner"), 1)
    local sets = #c:callsTo("PlayerCoords:SetPoint")
    Look:Place(SQUARE, true)
    eq(#c:callsTo("PlayerCoords:SetPoint"), sets, "moved again though it stayed")
    Look:Restore()
    eq(pointOf(c, parts.coords), { "BOTTOM", map, "BOTTOM", 0, -18 })
    eq(st(c, parts.coords).level, st(c, parts.box).level + 1)
    -- Square again: moved again.
    Look:Place(SQUARE, false)
    eq(pointOf(c, parts.coords), { "BOTTOMLEFT", map, "BOTTOMLEFT", 4, 4 })
    c:assertClean()
end)

test("map look: when the game moves its coordinates back, they are hidden and our own are drawn", function()
    local c, _, Look, parts = placed({ setup = function(c)
        c.world.cvars.minimapShowPlayerCoords = "1"
        c.world.player = { map = 1429, x = 0.4521, y = 0.6104, facing = 0 }
    end })
    local map = c.env.Minimap
    parts.coords:ClearAllPoints()
    parts.coords:SetPoint("BOTTOM", map, "BOTTOM", 0, -18) -- the game put it back
    Look:Place(SQUARE, true)
    eq(parts.coords:IsShown(), false)
    eq(pointOf(c, parts.coords), { "BOTTOM", map, "BOTTOM", 0, -18 }, "moved again")
    eq(wordsOf(c).coords.text, "45.2, 61.0")
    eq(noted(c, "coordinates: our own text in the map's bottom left corner (the game moved its own text back)"), 1)
    -- Kept for the session.
    Look:Place(SQUARE, true)
    eq(pointOf(c, parts.coords), { "BOTTOM", map, "BOTTOM", 0, -18 })
    Look:Restore()
    eq(parts.coords:IsShown(), true)
    c:assertClean()
end)

test("map look: Restore stops everything: no OnUpdate, no event, nothing ticking", function()
    local c, _, Look = placed({ setup = function(c) c.world.gameTime = { 14, 5 } end })
    eq(onUpdates(c), 1)
    eq(eventsHeld(c), 3)
    Look:Restore()
    eq(onUpdates(c), 0)
    eq(eventsHeld(c), 0)
    local before = c.stats.addonOnUpdate
    local w = wordsOf(c)
    c.world.gameTime = { 15, 0 }
    c:advance(60)
    eq(c.stats.addonOnUpdate, before, "an OnUpdate of ours ran while Round")
    eq(w.clock.text, "2:05")
    for _, rec in ipairs(lookFrames(c)) do eq(rec.shown, false, "a frame of ours still shows") end
end)

---------------------------------------------------------------------------
-- Round after Square, fights, missing pieces
---------------------------------------------------------------------------

test("map look: Place for Round after a Square placement is Restore", function()
    local c, _, Look, parts = placed()
    Look:Place(ROUND, false)
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK })
    eq(Look:IsSquare(), false)
    eq(parts.strip:IsShown(), true)
    eq(parts.clock:IsShown(), true)
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10, 30 })
    local edge, words = edgeAndWords(c)
    eq(edge.shown, false)
    eq(words.shown, false)
    eq(onUpdates(c), 0)
    eq(eventsHeld(c), 0)
    eq(Look:SnapshotPieces(), {})
    eq(noted(c, "off: the round map, the game's strip shown again"), 1)
    -- And Square again works as the first time, with the frames already made.
    Look:Place(SQUARE, false)
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK, SQUARE_MASK })
    eq(#lookFrames(c), 2)
    eq(parts.strip:IsShown(), false)
    c:assertClean()
end)

test("map look: in a fight nothing of the game's is changed; it is placed once when the fight ends", function()
    local c, _, Look, parts = new()
    c:enterCombat()
    local before = #c.calls
    Look:Place(SQUARE, false)
    Look:Place(SQUARE, false)
    Look:Place(SQUARE, true)
    eq(#c.calls, before, "a game call was made in a fight")
    eq(maskCalls(c), {})
    eq(parts.strip:IsShown(), true)
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10, 30 })
    eq(Look:IsSquare(), false)
    c:leaveCombat()
    c:advance(0.1)
    eq(maskCalls(c), { SQUARE_MASK }, "not exactly once after the fight")
    eq(Look:IsSquare(), true)
    eq(parts.strip:IsShown(), false)
    c:assertClean()
end)

-- Review focus: the game redraws the map in a fight.
test("map look: a redraw in a fight gives the mask again once the fight ends, and only once", function()
    local c, _, Look = placed()
    c:enterCombat()
    Look:Place(SQUARE, true)
    Look:Place(SQUARE, true)
    Look:Place(SQUARE, false) -- a later placement in the same fight does not lose the redraw
    eq(maskCalls(c), { SQUARE_MASK }, "given in a fight")
    c:leaveCombat()
    c:advance(0.1)
    eq(maskCalls(c), { SQUARE_MASK, SQUARE_MASK })
    Look:Place(SQUARE, false)
    eq(maskCalls(c), { SQUARE_MASK, SQUARE_MASK }, "the redraw was kept for a later placement")
end)

test("map look: Restore in a fight waits for its end, and a Place before that is dropped for it", function()
    local c, _, Look, parts = placed()
    c:enterCombat()
    Look:Place(SQUARE, true)
    Look:Restore()
    eq(parts.strip:IsShown(), false)
    eq(Look:IsSquare(), true)
    c:leaveCombat()
    c:advance(0.1)
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK })
    eq(parts.strip:IsShown(), true)
    eq(Look:IsSquare(), false)
end)

-- Review focus: a frame missing or renamed.
test("map look: no Minimap: one line, no error, nothing made", function()
    local c, _, Look = new({ parts = false, setup = function(c) rawset(c.env, "Minimap", false) end })
    for _ = 1, 3 do Look:Place(SQUARE, true) end
    eq(noted(c, "the map (Minimap) not found on this client"), 1)
    eq(#lookFrames(c), 0)
    eq(Look:IsSquare(), false)
    Look:Restore()
    c:assertClean()
end)

test("map look: no ZoneTextButton: one line, and the mask, the edge and the words are still placed", function()
    local c, _, Look, parts = new({ setup = function(c, parts) rawset(parts.cluster, "ZoneTextButton", nil) end })
    for _ = 1, 3 do Look:Place(SQUARE, true) end
    eq(noted(c, "the game's place name strip (MinimapCluster.ZoneTextButton) not found on this client"), 1)
    eq(Look:IsSquare(), true)
    local edge, words = edgeAndWords(c)
    eq(edge.shown, true)
    eq(words.shown, true)
    eq(parts.clock:IsShown(), false, "the clock was left")
    Look:Restore()
    eq(parts.clock:IsShown(), true)
    c:assertClean()
end)

test("map look: no PlayerCoords: one line, and our own coordinates are drawn", function()
    local c, _, Look = new({ setup = function(c, parts)
        rawset(parts.box, "PlayerCoords", nil)
        c.world.cvars.minimapShowPlayerCoords = "1"
        c.world.player = { map = 1429, x = 0.25, y = 0.75, facing = 0 }
    end })
    for _ = 1, 3 do Look:Place(SQUARE, true) end
    eq(noted(c, "the game's coordinates text (PlayerCoords) not found on this client"), 1)
    eq(Look:IsSquare(), true)
    eq(wordsOf(c).coords.text, "25.0, 75.0")
    Look:Restore()
    c:assertClean()
end)

test("map look: no clock and no map's frame of the expected kind: lines, no error, the mask still given", function()
    -- The stand-in's bare map: the Minimap widget straight on MinimapCluster, no strip, no clock.
    local c, _, Look = new({ parts = false })
    for _ = 1, 2 do Look:Place(SQUARE, false) end
    eq(maskCalls(c), { SQUARE_MASK })
    eq(noted(c, "the game's clock (TimeManagerClockButton) not found on this client"), 1)
    eq(noted(c, "the game's place name strip (MinimapCluster.ZoneTextButton) not found on this client"), 1)
    eq(noted(c, "the map's frame is not anchored under the map's piece: not lowered"), 1)
    Look:Restore()
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK })
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The pieces on the rim, the snapshot, the listener
---------------------------------------------------------------------------

test("map look: each piece the game hangs on the map gets one line with its place, and none is moved", function()
    local c, _, Look, parts = new()
    local diel, mail = rawget(parts.cluster, "DielFrame"), rawget(parts.cluster, "IndicatorFrame")
    local dielPoint, mailPoint = pointOf(c, diel), pointOf(c, mail)
    Look:Place(SQUARE, false)
    Look:Place(SQUARE, true)
    eq(notedLike(c, "^rim: "), 9, table.concat(notes(c), " | "))
    -- The day and night mark: 55 right and 86 up of the map's middle (0, 104), 42 across.
    eq(noted(c, "rim: day and night mark | shown | l=716.7 b=169.0 w=42.0 h=42.0"), 1, table.concat(notes(c), " | "))
    -- The mail mark over the hidden strip's left end.
    eq(noted(c, "rim: mail mark | shown | l=595.7 b=31.0 w=32.0 h=24.0"), 1)
    eq(noted(c, "rim: zoom in button | hidden | l=762.2 b=27.5 w=17.0 h=17.0"), 1)
    eq(noted(c, "rim: group finder button | not found"), 1)
    eq(noted(c, "rim: game's clock | hidden | l=704.7 b=10.5 w=40.0 h=16.0"), 1)
    eq(pointOf(c, diel), dielPoint)
    eq(pointOf(c, mail), mailPoint)
    c:assertClean()
end)

test("map look: the snapshot's pieces are the edge, the words and the rim, only while Square", function()
    local c, _, Look = placed()
    local names = {}
    local list = Look:SnapshotPieces()
    for i, p in ipairs(list) do
        names[i] = p[1]
        eq(p[3], { skip = true }, p[1])
    end
    eq(names, { "map's edge", "map's words", "day and night mark", "mail mark", "zoom in button", "zoom out button", "event button",
        "group finder button", "controller buttons holder", "game's coordinates text", "game's clock" })
    local edge, words = edgeAndWords(c)
    eq(list[1][2], edge.frame)
    eq(list[2][2], words.frame)
    Look:Restore()
    eq(Look:SnapshotPieces(), {})
end)

test("map look: a listener hears each change of the shape, and only a change", function()
    local c, _, Look = new()
    local heard = {}
    Look:OnChange(function() heard[#heard + 1] = Look:IsSquare() end)
    Look:OnChange("not a function")
    Look:Place(SQUARE, false)
    Look:Place(SQUARE, true)
    eq(heard, { true })
    Look:Restore()
    Look:Restore()
    eq(heard, { true, false })
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Through the layout (ControllerLayout.lua: PlaceRing, RestoreRing, the redraw hook, the
-- snapshot, the status line)
---------------------------------------------------------------------------

local USING = "Using the Pocket Essentials layout. Move the map, chat or frames in Edit Mode if you like."

-- The Gamepad UI on, the map's pieces, the layout switched on (ours built and active), the
-- reload request cleared. opts.square: "Map look" is Square before the switch-on.
local function layoutOn(opts)
    opts = opts or {}
    local parts
    local c, PE = T.new({ gamepadUI = true, setup = function(c)
        c.world.layouts = { layouts = {}, activeLayout = 3 }
        parts = c:addMapParts(opts.map or { x = -6, scale = 0.7 })
        if opts.setup then opts.setup(c, parts) end
    end })
    PE:SetDebug(true)
    local m = PE:GetModule("ctrlLayout")
    if opts.square then m.opts.mapLook = 1 end
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    m:CancelReload()
    return c, PE, PE.MapLook, parts, m
end

local function choose(c, PE, key, value)
    local m = PE:GetModule("ctrlLayout")
    for _, o in ipairs(m.options) do
        if o.key == key then
            m.opts[key] = value
            if o.OnChange then PE:Safe("ctrlLayout", o.OnChange, m, value) end
        end
    end
    c:advance(0.1)
end

local function statusText(m)
    local s = m:status()
    if type(s) == "table" then return table.concat(s, "\n") end
    return s
end

-- Our black disc behind the round map (ControllerLayout.lua), or nil.
local function disc(c)
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == "ControllerLayout.lua" then
            for _, r in ipairs(rec.regions) do
                local tex = st(c, r).texture
                if type(tex) == "string" and tex:find("Icons\\circle", 1, true) then return rec end
            end
        end
    end
    return nil
end

test("map look layout: with Round the layout never calls the mask and makes no frame of MapLook's", function()
    local c, PE, Look, parts = layoutOn()
    parts.cluster:UpdateMinimapConfig()
    c:advance(1)
    eq(maskCalls(c), {})
    eq(#lookFrames(c), 0)
    eq(notes(c), {})
    check(disc(c) ~= nil and disc(c).shown == true, "the round map's disc is not drawn")
    eq(parts.strip:IsShown(), true)
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10 / 0.7, 30 / 0.7 })
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    eq(maskCalls(c), {})
    c:assertClean()
end)

test("map look layout: Square places the square map with the layout and the disc is not drawn", function()
    local c, PE, Look, parts, m = layoutOn({ square = true, map = { x = -10, scale = 1 } })
    eq(maskCalls(c), { SQUARE_MASK })
    eq(Look:IsSquare(), true)
    local d = disc(c)
    check(d == nil or d.shown == false, "the round map's disc is drawn behind the square map")
    local edge = edgeAndWords(c)
    sameRect(rectOf(c, edge.frame), { -100, 4, 100, 204 }, "the edge box")
    eq(parts.strip:IsShown(), false)
    eq(statusText(m), USING)
    -- The layout off: everything back.
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK })
    eq(parts.strip:IsShown(), true)
    eq(edge.shown, false)
    eq(onUpdates(c), 0)
    eq(eventsHeld(c), 0)
    c:assertClean()
end)

test("map look layout: the game's redraw gives the mask again; in a fight, once it ends and once", function()
    local c, _, _, parts = layoutOn({ square = true, map = { x = -10, scale = 1 } })
    parts.cluster:UpdateMinimapConfig()
    eq(maskCalls(c), { SQUARE_MASK, SQUARE_MASK })
    c:enterCombat()
    parts.cluster:UpdateMinimapConfig()
    parts.cluster:UpdateMinimapConfig()
    eq(#maskCalls(c), 2, "given in a fight")
    c:leaveCombat()
    c:advance(0.1)
    eq(#maskCalls(c), 3, "not exactly once after the fight")
    c:assertClean()
end)

-- Review focus: Square to Round without a reload in between.
test("map look layout: Round on the row gives the mask, the strip and the disc back at once, before the reload", function()
    local c, PE, Look, parts, m = layoutOn({ square = true, map = { x = -10, scale = 1 } })
    choose(c, PE, "mapLook", 0)
    m:CancelReload() -- the reload prompt dismissed
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK })
    eq(Look:IsSquare(), false)
    eq(parts.strip:IsShown(), true)
    eq(parts.clock:IsShown(), true)
    local edge, words = edgeAndWords(c)
    eq(edge.shown, false)
    eq(words.shown, false)
    eq(onUpdates(c), 0)
    eq(eventsHeld(c), 0)
    check(disc(c) ~= nil and disc(c).shown == true, "the round map's disc is not drawn")
    eq(pointOf(c, parts.box), { "BOTTOM", parts.cluster, "BOTTOM", 10, 30 })
    -- A later placement and a redraw leave no half state.
    parts.cluster:UpdateMinimapConfig()
    c:fire("PLAYER_ENTERING_WORLD")
    c:advance(0.1)
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK })
    eq(parts.strip:IsShown(), true)
    eq(words.shown, false)
    -- And back to Square at once.
    choose(c, PE, "mapLook", 1)
    eq(maskCalls(c), { SQUARE_MASK, ROUND_MASK, SQUARE_MASK })
    eq(parts.strip:IsShown(), false)
    check(disc(c).shown == false, "the disc stays behind the square map")
    c:assertClean()
end)

test("map look layout: a refused mask keeps the round look with its disc, and the card says so", function()
    local c, _, Look, parts, m = layoutOn({ square = true, map = { x = -10, scale = 1 }, setup = function(c) c.world.maskRefused = true end })
    parts.cluster:UpdateMinimapConfig()
    eq(Look:IsSquare(), false)
    eq(noted(c, REFUSED), 1)
    check(disc(c) ~= nil and disc(c).shown == true, "the fallback has no disc")
    check(statusText(m):find(TEXT_REFUSED, 1, true), "the card: " .. tostring(statusText(m)))
    c:assertClean()
end)

test("map look layout: the snapshot lists the square map's edge, words and rim pieces", function()
    local c, PE, _, _, m = layoutOn({ square = true, map = { x = -10, scale = 1 } })
    check(m:Snapshot() == true, "the snapshot was not written")
    local lines = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        local text = line:match("^%S+ snapshot: (.*)$")
        if text then lines[#lines + 1] = text end
    end
    local all = "\n" .. table.concat(lines, "\n")
    check(all:find("\npiece: map's edge | shown | l=582.7 b=4.0 w=200.0 h=200.0 s=1.00", 1, true), "no edge line:" .. all)
    check(all:find("\npiece: map's words | shown | l=583.7 b=5.0 w=198.0 h=198.0 s=1.00", 1, true), "no words line")
    check(all:find("\npiece: day and night mark | shown", 1, true), "no day and night mark")
    check(all:find("\npiece: group finder button | not found", 1, true), "no group finder line")
    check(all:find("mapLook=1", 1, true), "the option is not listed")
    check(not all:find("overlap: [^\n]*map's edge"), "the edge is checked for overlaps")
    check(not all:find("overlap: [^\n]*map's words"), "the words are checked for overlaps")
    c:assertClean()
end)

test("map look layout: a missing MapLook file changes nothing", function()
    local c, PE = T.new({ gamepadUI = true, setup = function(c)
        c.world.layouts = { layouts = {}, activeLayout = 3 }
        c:addMapParts({ x = -10, scale = 1 })
    end })
    PE.MapLook = nil
    PE:GetModule("ctrlLayout").opts.mapLook = 1
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    check(disc(c) ~= nil and disc(c).shown == true, "the round map's disc is not drawn")
    check(PE:GetModule("ctrlLayout"):Snapshot() ~= nil)
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    c:assertClean()
end)

return { known = KNOWN_FAILURES }
