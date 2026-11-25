-- Rules for "Arrange it yourself" of Controller layout 0.18.0 (Arrange.lua, and the plan's
-- half in ControllerLayout.lua). Source: docs/superpowers/specs/2026-11-24-0.18.0-arrange.md
-- ("The pieces", "The spell wheel", "How a move is stored", "Inside the plan", "Symmetry",
-- "The Arrange screen", "Apply, Reset, Reset all", "The overlap warning", "The switches",
-- "Logging", "Tests"). Fresh client and addon per test.
--
-- These prove the logic against the stand-in client. Whether the game moves its pieces the
-- same way (the rewritten Edit Mode layout after a reload, the bar anchors placed again and
-- again, the wheels following their buttons) only the device can show.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local NAME = "Pocket Essentials"
local RELOAD = "Reload to finish the layout change."
local NAV_NAME = "PocketEssentialsNavButton"
local W, H = 768 * 1280 / 720, 768 -- the stand-in's screen in UI units
local SIZES = { 80, 90, 100, 110, 120 }
local SYS = { Minimap = 2, UnitFrame = 3, ChatFrame = 8, HudTooltip = 11, SwingTimer = 29 }
-- The frame under the left inner spell panel that takes a tap, at its built-in spot and 100%:
-- the panel (-237 to -103, 17 to 115) and the two real bars under it (-232.4 to -107.6, 24.6
-- to 107.4), 4 wider all round (FaceBars.lua, BackingRects).
local LEFT_GUARD = { -241, 13, -99, 119 }

local function near(a, b, msg)
    check(type(a) == "number" and math.abs(a - b) < 1e-6, (msg or "number") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

local function plan()
    local c, PE = T.new({})
    return PE.LayoutPlan, c, PE
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- An options table for the plan with the switch On and one piece moved (in both stores:
-- the plan reads the one that fits the piece).
local function moved(key, x, y, more)
    local v = { arrange = 1, arrangeWheel = 1, offsets = { [key] = { x = x, y = y } }, charOffsets = { [key] = { x = x, y = y } } }
    for k, val in pairs(more or {}) do v[k] = val end
    return v
end

local function shifted(r, dx, dy)
    return { r[1] + dx, r[2] + dy, r[3] + dx, r[4] + dy }
end

local function sameRect(got, want, what)
    check(type(got) == "table", what .. ": no rectangle")
    for i = 1, 4 do near(got[i], want[i], what .. " " .. i) end
end

-- A client with the Controller layout on from the Gamepad preset (ours built and active)
-- and the saved values given: o.arrange (default 1), o.wheel, o.slim, o.offsets (the Edit
-- Mode pieces'), o.char (this character's saved table), o.setup(c). The Debug log is on and
-- the first reload request is cleared. Returns c, PE, PE.Arrange.
local function client(o)
    o = o or {}
    local saved = { options = { ctrlLayout = { arrange = o.arrange == nil and 1 or o.arrange, arrangeWheel = o.wheel,
        slim = o.slim, panelSize = o.panelSize, offsets = o.offsets, offsetsWritten = o.written } } }
    for k, v in pairs(o.more or {}) do saved.options.ctrlLayout[k] = v end
    local c, PE = T.new({ gamepadUI = true, saved = saved, savedChar = o.char, screen = o.screen, setup = function(c)
        c.world.layouts = { layouts = {}, activeLayout = 3 }
        if o.slim == 1 then c:addUnitFrames() end
        if o.setup then o.setup(c) end
    end })
    PE:SetDebug(true)
    if o.off then return c, PE, PE.Arrange end
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    PE:GetModule("ctrlLayout"):CancelReload()
    return c, PE, PE.Arrange
end

local function opts(PE) return PE:GetModule("ctrlLayout").opts end
local function charStore(PE) return PE.charDB.ctrlArrange end
-- The offsets our Edit Mode layout holds, as the options note them (none noted yet: empty).
local function written(PE) return opts(PE).offsetsWritten or {} end

local function ours(c)
    for _, l in ipairs(c.world.layouts.layouts) do if l.layoutName == NAME then return l end end
    return nil
end

local function entry(c, system, index)
    for _, e in ipairs(ours(c).systems) do
        if e.system == system and (index == nil or e.systemIndex == index) then return e end
    end
    return nil
end

local function saves(c) return #c:callsTo("C_EditMode.SaveLayouts") end

local function reloadReason(PE)
    for _, r in ipairs(PE.reloadReasons) do
        if r.key == "ctrlLayout" then return r.reason end
    end
    return nil
end

local function optRow(PE, keyOrLabel)
    for _, o in ipairs(PE:GetModule("ctrlLayout").options or {}) do
        if o.key == keyOrLabel or o.label == keyOrLabel then return o end
    end
    return nil
end

local function choose(c, PE, key, value)
    local m = PE:GetModule("ctrlLayout")
    local o = optRow(PE, key)
    check(o ~= nil, "no option row " .. key)
    m.opts[key] = value
    if o.OnChange then PE:Safe("ctrlLayout", o.OnChange, m, value) end
    c:advance(0.1)
end

local function tapArrangeRow(c, PE)
    local o = optRow(PE, "Arrange the screen")
    check(o ~= nil and type(o.action) == "function", "no Arrange the screen row")
    PE:Safe("ctrlLayout", o.action, PE:GetModule("ctrlLayout"))
    c:advance(0.1)
end

-- The "arrange:" lines of the debug log, in order.
local function notes(c)
    local out = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        local text = line:match("^%S+ ctrlLayout: arrange: (.*)$")
        if text then out[#out + 1] = text end
    end
    return out
end

local function noted(c, text)
    for _, l in ipairs(notes(c)) do if l == text then return true end end
    return false
end

local function notedLike(c, pattern)
    for _, l in ipairs(notes(c)) do if l:find(pattern) then return l end end
    return nil
end

local function chatHas(c, text)
    for _, l in ipairs(T.chatLines(c)) do if l == text then return true end end
    return false
end

local function barFrames(c)
    local pu = c.env.GamepadMainActionBarFrame.PageUnit
    return { top = pu.TopCenteredAnchor, left = pu.LeftCenteredAnchor, right = pu.RightCenteredAnchor,
        bottom = pu.BottomCenteredAnchor, both = pu.BottomCenteredAnchor.Bar }, pu
end

-- A bar frame's spot in UI units from the screen's bottom centre (its one point times its scale).
local function barAt(c, f)
    local st = c._state(f)
    eq(#st.points, 1, "a bar frame's points")
    local p = st.points[1]
    return p.x * st.scale, p.y * st.scale
end

local function barCalls(c)
    local n = 0
    for _, call in ipairs(c.calls) do
        if call.name:match("^GamepadBar%.") then n = n + 1 end
    end
    return n
end

local function panel(c) return rawget(c.env, "PocketEssentialsArrangePanel") end
local function settingsPanel(c) return rawget(c.env, "PocketEssentialsSettingsPanel") end
local function nav(c) return rawget(c.env, NAV_NAME) end

local function walk(c, w, fn, seen)
    seen = seen or {}
    if seen[w] then return end
    seen[w] = true
    fn(w)
    for _, ch in ipairs(c._state(w).children) do walk(c, ch, fn, seen) end
end

-- The window's button with that label (exactly one shown).
local function button(c, label)
    local found = {}
    walk(c, panel(c), function(w)
        if c._state(w).type == "Button" and w:IsVisible() and T.labelOf(w) == label then found[#found + 1] = w end
    end)
    check(#found == 1, "expected one shown button '" .. label .. "' in the Arrange window, found " .. #found)
    return found[1]
end

-- Every text of the window that is showing, joined by newlines.
local function windowText(c)
    local out = {}
    walk(c, panel(c), function(w)
        for _, r in ipairs(c._state(w).regions or {}) do
            local st = c._state(r)
            if st.type == "FontString" and st.text and st.text ~= "" and st.shown ~= false then out[#out + 1] = st.text end
        end
    end)
    return table.concat(out, "\n")
end

-- The outlines showing: { { kind = "picked" | "twin" | "overlap", rect = { l, b, r, t } }, ... }.
local function outlines(c)
    local out = {}
    for _, rec in ipairs(c:frames()) do
        local f = rec.frame
        if rec.addonFile == "Arrange.lua" and rawget(f, "peKind") and c._state(f).shown then
            local l, r, t, b = c._rect(f)
            out[#out + 1] = { kind = f.peKind, rect = { l - W / 2, b, r - W / 2, t } }
        end
    end
    return out
end

local function open(c, PE, key)
    check(PE.Arrange:Open() == true, "the Arrange window did not open")
    c:advance(0.1)
    check(panel(c) and panel(c):IsShown(), "the Arrange window is not showing")
    if key then check(PE.Arrange:Pick(key) == true, "could not pick " .. key) end
end

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------

test("arrange plan: both switches are Off by default, and Off ignores saved offsets everywhere", function()
    local Plan = plan()
    eq(Plan.DEFAULTS.arrange, 0)
    eq(Plan.DEFAULTS.arrangeWheel, 0)
    eq(Plan.session, nil, "a session's offsets are set with the switch Off")
    for _, def in ipairs(Plan.ARRANGE) do
        for _, size in ipairs(SIZES) do
            for slim = 0, 1 do
                local base = { panelSize = size, slim = slim }
                for _, value in ipairs({ 0, 2, "yes", false }) do
                    local v = moved(def.key, 30, -20, { panelSize = size, slim = slim, arrange = value })
                    local what = def.key .. " " .. size .. "% slim " .. slim .. " arrange " .. tostring(value)
                    eq(Plan.Rects(v), Plan.Rects(base), what .. ": Rects")
                    eq(Plan.Pieces(v), Plan.Pieces(base), what .. ": Pieces")
                    eq(Plan.BarSpots(v), Plan.BarSpots(base), what .. ": BarSpots")
                    eq(Plan.FaceSpots(v), Plan.FaceSpots(base), what .. ": FaceSpots")
                    eq(Plan.RealBarRects(v), Plan.RealBarRects(base), what .. ": RealBarRects")
                    eq(Plan.SlimRects(v), Plan.SlimRects(), what .. ": SlimRects")
                    eq(Plan.Wheels(v), Plan.Wheels(), what .. ": Wheels")
                    eq({ Plan.Moved(v, def.key) }, { 0, 0 }, what .. ": Moved")
                end
            end
        end
    end
    local s = Plan.Shoulders({ arrange = 0, charOffsets = { ["LB targeting picture"] = { x = 9, y = 9 } } })
    eq(s, { left = { "BOTTOMRIGHT", -178, 155 }, right = { "BOTTOMLEFT", 178, 155 } })
    eq(Plan.TEMPLATE, 5, "the template number must not change: nobody's layout is rebuilt for this")
end)

test("arrange plan: the list of pieces, their kinds and their twins", function()
    local Plan = plan()
    local kinds, twins = {}, {}
    for _, def in ipairs(Plan.ARRANGE) do
        kinds[def.key] = def.kind
        check(Plan.ARRANGE_BY[def.key] == def, def.key .. " is not in ARRANGE_BY")
        check(type(def.label) == "string" and def.label ~= "", def.key .. " has no label")
        check(type(def.rects) == "table" and #def.rects >= 1, def.key .. " has no rectangle")
        if def.twin then
            twins[def.key] = def.twin
            local other = Plan.ARRANGE_BY[def.twin]
            check(other and other.twin == def.key, def.key .. "'s twin does not name it back")
            eq(other.kind, def.kind, def.key .. " and its twin are of two kinds")
            eq(other.pair, def.pair, def.key .. " and its twin name two pairs")
            check(def.pair == def.key or def.pair == def.twin, def.key .. ": the pair is not named after one of the two")
        end
    end
    eq(kinds, {
        map = "apply", ["swing timers"] = "apply", ["XP bars"] = "apply", chat = "apply", ["quest tracker"] = "apply",
        ["buffs and debuffs"] = "apply", tooltip = "apply", player = "apply", target = "apply",
        ["inner left diamond"] = "live", ["inner right diamond"] = "live", ["outer left diamond"] = "live",
        ["outer right diamond"] = "live", ["LB targeting picture"] = "live", ["RB targeting picture"] = "live",
        ["player bar"] = "live", ["target bar"] = "live", ["spell wheels"] = "live",
    })
    eq(twins, {
        player = "target", target = "player",
        ["inner left diamond"] = "inner right diamond", ["inner right diamond"] = "inner left diamond",
        ["outer left diamond"] = "outer right diamond", ["outer right diamond"] = "outer left diamond",
        ["LB targeting picture"] = "RB targeting picture", ["RB targeting picture"] = "LB targeting picture",
        ["player bar"] = "target bar", ["target bar"] = "player bar",
    })
    eq(Plan.ARRANGE_BY["spell wheels"].axis, "y")
    eq(Plan.ARRANGE_BY["spell wheels"].gate, "arrangeWheel")
end)

test("arrange plan: the built-in spots of every pair of twins are exact mirrors, at every size", function()
    local Plan = plan()
    for _, size in ipairs(SIZES) do
        for slim = 0, 1 do
            local r = Plan.Rects({ panelSize = size, slim = slim })
            for _, def in ipairs(Plan.ARRANGE) do
                local a, b = r[def.rects[1]], def.twin and r[Plan.ARRANGE_BY[def.twin].rects[1]]
                if a and b then
                    sameRect(a, { -b[3], b[2], -b[1], b[4] }, size .. "% slim " .. slim .. ": " .. def.key .. " against its twin")
                end
            end
            -- The small frames and bars of each side too.
            for _, pair in ipairs({ { "pet", "target of target" }, { "pet bar", "target of target bar" } }) do
                local a, b = r[pair[1]], r[pair[2]]
                if a and b then sameRect(a, { -b[3], b[2], -b[1], b[4] }, size .. "%: " .. pair[1]) end
            end
        end
    end
end)

test("arrange plan: an offset moves exactly its own piece's rectangles, at every Spell panel size, Slim bars on and off", function()
    local Plan = plan()
    for _, size in ipairs(SIZES) do
        for slim = 0, 1 do
            local base = Plan.Rects({ panelSize = size, slim = slim, hints = 1, mapButtons = 1 })
            for _, def in ipairs(Plan.ARRANGE) do
                local got = Plan.Rects(moved(def.key, 14, -6, { panelSize = size, slim = slim, hints = 1, mapButtons = 1 }))
                local dx = def.axis == "y" and 0 or 14
                local mine = {}
                for _, name in ipairs(def.rects) do mine[name] = true end
                local n = 0
                for name, r in pairs(base) do
                    local what = size .. "% slim " .. slim .. ", " .. def.key .. " moved: " .. name
                    if mine[name] then
                        n = n + 1
                        sameRect(got[name], shifted(r, dx, -6), what)
                    else
                        sameRect(got[name], r, what)
                    end
                end
                for name in pairs(got) do check(base[name], "a rectangle appeared: " .. name) end
                -- A piece whose rectangles are not drawn in this state (the game's frames under the slim bars) moves nothing.
                local drawn = 0
                for _, name in ipairs(def.rects) do if base[name] then drawn = drawn + 1 end end
                eq(n, drawn)
            end
        end
    end
end)

test("arrange plan: the spell panels move in every trigger state, the real bars follow their inner panel, the wheels their anchor", function()
    local Plan = plan()
    local SPOT = { innerLeft = "inner left diamond", innerRight = "inner right diamond", outerLeft = "outer left diamond",
        outerRight = "outer right diamond" }
    local RING = { innerLeft = { "inner", "left" }, innerRight = { "inner", "right" }, outerLeft = { "outer", "left" },
        outerRight = { "outer", "right" } }
    for _, size in ipairs(SIZES) do
        local base = Plan.FaceSpots(size)
        for spot, key in pairs(SPOT) do
            local v = moved(key, -8, 12, { panelSize = size })
            local got = Plan.FaceSpots(v)
            for state, list in pairs(Plan.FaceStates()) do
                for _, h in ipairs(list) do
                    local ring = RING[h.spot]
                    local b, g = base[ring[1]][ring[2]], got[ring[1]][ring[2]]
                    local what = size .. "%, " .. key .. " moved, state " .. state .. ", " .. h.spot
                    near(g.x, b.x + (h.spot == spot and -8 or 0), what .. " x")
                    near(g.y, b.y + (h.spot == spot and 12 or 0), what .. " y")
                end
            end
        end
        -- The real bars: two under each inner panel, and they go with it.
        local bars, rects = Plan.BarSpots(size), Plan.RealBarRects(size)
        local left = moved("inner left diamond", -8, 12, { panelSize = size })
        local gotBars, gotRects = Plan.BarSpots(left), Plan.RealBarRects(left)
        for _, spot in ipairs({ "top", "left" }) do
            near(gotBars[spot].x, bars[spot].x - 8, size .. "% " .. spot .. " x")
            near(gotBars[spot].y, bars[spot].y + 12, size .. "% " .. spot .. " y")
            eq(gotBars[spot].s, bars[spot].s)
        end
        for _, spot in ipairs({ "right", "both", "bottom" }) do eq(gotBars[spot], bars[spot], size .. "% " .. spot .. " moved") end
        sameRect(gotRects.main, shifted(rects.main, -8, 12), size .. "% main real bar")
        sameRect(gotRects.lt, shifted(rects.lt, -8, 12), size .. "% lt real bar")
        sameRect(gotRects.rt, rects.rt, size .. "% rt real bar")
        local right = moved("inner right diamond", 4, -2, { panelSize = size })
        sameRect(Plan.RealBarRects(right).rt, shifted(rects.rt, 4, -2), size .. "% rt real bar")
        sameRect(Plan.RealBarRects(right).both, shifted(rects.both, 4, -2), size .. "% both real bar")
        eq(Plan.BarSpots(moved("outer left diamond", 30, 30, { panelSize = size })), bars, size .. "%: an outer panel moved a bar")
    end
    -- The wheels: up and down with the bottom anchor, never sideways, and only with their switch.
    local v = moved("spell wheels", 40, 30)
    eq(Plan.BarSpots(v).bottom, { x = 0, y = 268, s = 1 })
    eq(Plan.Wheels(v), { { x = -138, y = 218, r = 87.5 }, { x = 138, y = 218, r = 87.5 } })
    eq({ Plan.Moved(v, "spell wheels") }, { 40, 30 })
    v.arrangeWheel = 0
    eq(Plan.BarSpots(v).bottom, { x = 0, y = 238, s = 1 }, "moved with its own switch off")
    eq(Plan.Wheels(v), Plan.Wheels())
    eq(Plan.Rects(v), Plan.Rects({}))
    -- The targeting pictures.
    eq(Plan.Shoulders(moved("LB targeting picture", -5, 7)), { left = { "BOTTOMRIGHT", -183, 162 }, right = { "BOTTOMLEFT", 178, 155 } })
    eq(Plan.SHOULDERS, { left = { "BOTTOMRIGHT", -178, 155 }, right = { "BOTTOMLEFT", 178, 155 } }, "the built-in numbers changed")
    -- The slim bars: a side moves whole.
    local slim, was = Plan.SlimRects(moved("target bar", 6, 8)), Plan.SlimRects()
    for _, name in ipairs({ "target bar", "cast bar", "target of target bar", "target boxes room" }) do
        sameRect(slim[name], shifted(was[name], 6, 8), name)
    end
    for _, name in ipairs({ "player bar", "pet bar", "pet boxes room" }) do sameRect(slim[name], was[name], name) end
end)

test("arrange plan: the Edit Mode pieces carry their offset in their anchor, and say which piece and offset they were built with", function()
    local Plan = plan()
    local SYSTEMS = { map = { "Minimap" }, chat = { "ChatFrame" }, ["quest tracker"] = { "ObjectiveTracker" },
        ["buffs and debuffs"] = { "AuraFrame" }, ["XP bars"] = { "StatusTrackingBar" }, tooltip = { "HudTooltip" },
        ["swing timers"] = { "SwingTimer" } }
    for _, size in ipairs(SIZES) do
        for slim = 0, 1 do
            local base = Plan.Pieces({ panelSize = size, slim = slim })
            for _, def in ipairs(Plan.ARRANGE) do
                local list = Plan.Pieces(moved(def.key, 14, -6, { panelSize = size, slim = slim }))
                eq(#list, #base)
                local n = 0
                for i, p in ipairs(list) do
                    local b = base[i]
                    local what = size .. "% slim " .. slim .. ", " .. def.key .. " moved: " .. p.system .. " " .. tostring(p.index)
                    if p.arrange == def.key then
                        n = n + 1
                        eq(def.kind, "apply", what .. ": a live piece is in the Edit Mode layout")
                        eq({ p.dx, p.dy }, { 14, -6 }, what)
                        eq({ p.anchor.x, p.anchor.y }, { b.anchor.x + 14, b.anchor.y - 6 }, what)
                        eq({ p.anchor.point, p.anchor.relativeTo, p.anchor.relativePoint },
                            { b.anchor.point, b.anchor.relativeTo, b.anchor.relativePoint }, what)
                        eq(p.settings, b.settings, what)
                        if SYSTEMS[def.key] then eq(p.system, SYSTEMS[def.key][1], what) end
                    else
                        eq(p, b, what)
                    end
                end
                if def.kind == "live" then eq(n, 0) end
            end
            local counts = {}
            for _, p in ipairs(base) do
                if p.arrange then
                    counts[p.arrange] = (counts[p.arrange] or 0) + 1
                    eq({ p.dx, p.dy }, { 0, 0 })
                end
            end
            eq(counts, { map = 1, chat = 1, ["quest tracker"] = 1, ["buffs and debuffs"] = 2, ["XP bars"] = 2, tooltip = 1,
                ["swing timers"] = 3, player = 2, target = 1 }, size .. "%: which pieces belong to which")
        end
    end
end)

test("arrange plan: bad and old saved offsets are ignored without an error", function()
    local Plan = plan()
    local base = Plan.Rects({})
    local huge = math.huge
    local bad = {
        map = "left", chat = 5, ["quest tracker"] = { x = "3", y = 4 }, ["XP bars"] = { x = 0 / 0, y = 1 },
        tooltip = { x = 1, y = huge }, ["swing timers"] = { x = 1501, y = 0 }, ["buffs and debuffs"] = { y = 3 },
        player = true, target = { x = 0, y = -1500.5 },
        ["a piece that is gone"] = { x = 50, y = 50 }, [7] = { x = 1, y = 1 },
        -- A live piece's key in the file of the Edit Mode pieces: not that piece's place.
        ["inner left diamond"] = { x = 20, y = 20 },
    }
    local v = { arrange = 1, arrangeWheel = 1, offsets = bad, charOffsets = { chat = { x = 9, y = 9 }, ["outer left diamond"] = { x = {}, y = 2 },
        ["spell wheels"] = "up" } }
    eq(Plan.Rects(v), base)
    eq(Plan.Pieces(v), Plan.Pieces({}))
    eq(Plan.FaceSpots(v), Plan.FaceSpots(100))
    eq(Plan.BarSpots(v), Plan.BarSpots(100))
    for key in pairs(bad) do eq({ Plan.Moved(v, key) }, { 0, 0 }, tostring(key)) end
    eq({ Plan.Moved(v, nil) }, { 0, 0 })
    -- Stores that are not tables at all.
    eq(Plan.Rects({ arrange = 1, offsets = "none", charOffsets = 4 }), base)
    eq(Plan.Rects({ arrange = 1 }), base)
    -- The limit itself is taken.
    eq({ Plan.Moved({ arrange = 1, offsets = { map = { x = 1500, y = -1500 } } }, "map") }, { 1500, -1500 })
    -- A good one beside the bad ones still counts.
    bad.chat = { x = 4, y = 6 }
    sameRect(Plan.Rects(v).chat, shifted(base.chat, 4, 6), "chat")
end)

test("arrange plan: the overlap check finds nothing in the built-in arrangement and names a pair that overlaps", function()
    local Plan = plan()
    for _, size in ipairs(SIZES) do
        for slim = 0, 1 do
            for hints = 0, 1 do
                eq(Plan.Overlaps(Plan.Rects({ panelSize = size, slim = slim, hints = hints, mapButtons = hints })), {},
                    size .. "% slim " .. slim .. " hints " .. hints)
            end
        end
    end
    eq(Plan.Overlaps({ a = { 0, 0, 10, 10 }, b = { 10, 0, 20, 10 } }), {}, "touching edges are not an overlap")
    eq(Plan.Overlaps({ b = { 0, 0, 10, 10 }, a = { 6, 7, 20, 30 }, c = { 100, 100, 110, 110 } }), { { a = "a", b = "b", w = 4, h = 3 } })
    eq(Plan.Overlaps({ ["LB+LT button"] = { 0, 0, 10, 10 }, ["LB+LT prompt"] = { 0, 9, 10, 20 } }), {}, "the game's button and its prompt")
    eq(Plan.Overlaps(nil), {})
    -- The chat moved down onto the round button and the player frame.
    local hits = {}
    for _, o in ipairs(Plan.Overlaps(Plan.Rects(moved("chat", 0, -40)))) do hits[#hits + 1] = o.a .. " + " .. o.b end
    eq(hits, { "chat + pet", "chat + round button" })
end)

test("arrange plan: what waits for a write is what the options ask for against what the layout holds", function()
    local Plan = plan()
    eq(Plan.Pending({ arrange = 1 }), {})
    eq(Plan.Pending(nil), {})
    local o = { arrange = 1, offsets = { chat = { x = 4, y = 6 }, map = { x = -4, y = 0 }, ["inner left diamond"] = { x = 9, y = 9 } } }
    eq(Plan.Pending(o), { "map", "chat" }, "in the list's order; a live piece never waits")
    Plan.MarkWritten(o, Plan.Pieces(o))
    eq(o.offsetsWritten, { chat = { x = 4, y = 6 }, map = { x = -4, y = 0 } })
    eq(Plan.Pending(o), {})
    -- Switched Off: the layout still holds the offsets, so the two wait to be written back.
    o.arrange = 0
    eq(Plan.Pending(o), { "map", "chat" })
    Plan.MarkWritten(o, Plan.Pieces(o))
    eq(o.offsetsWritten, {})
    eq(Plan.Pending(o), {})
    eq(o.offsets.chat, { x = 4, y = 6 }, "the saved offset was touched")
    -- Only the pieces that were written are noted.
    o.arrange = 1
    local only = {}
    for _, p in ipairs(Plan.Pieces(o)) do if p.system == "ChatFrame" then only[#only + 1] = p end end
    Plan.MarkWritten(o, only)
    eq(Plan.Pending(o), { "map" })
end)

---------------------------------------------------------------------------
-- Off
---------------------------------------------------------------------------

-- A stand-in for PE.Arrange that records every call.
local function arrangeStub(PE)
    local s = { calls = {} }
    setmetatable(s, { __index = function(_, name)
        return function(_, ...) s.calls[#s.calls + 1] = name end
    end })
    PE.Arrange = s
    return s
end

test("arrange off: saved offsets move nothing, the plan has no session, and Arrange.lua is never called", function()
    local char = { ctrlArrange = { offsets = { ["inner left diamond"] = { x = 20, y = 10 }, ["LB targeting picture"] = { x = 6, y = 6 },
        ["spell wheels"] = { x = 0, y = 30 } }, alone = {} } }
    local c, PE = client({ arrange = 0, wheel = 1, off = true, offsets = { chat = { x = 30, y = 30 }, map = { x = -4, y = 0 } }, char = char })
    local stub = arrangeStub(PE)
    local frames = 0
    for _, rec in ipairs(c:frames()) do if rec.addonFile == "Arrange.lua" then frames = frames + 1 end end
    eq(frames, 0, "Arrange.lua made a frame at load")
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    c:fire("PLAYER_ENTERING_WORLD")
    c:advance(0.1)
    local Plan = PE.LayoutPlan
    eq(Plan.session, nil)
    local spots = Plan.BarSpots(100)
    local f = barFrames(c)
    for _, spot in ipairs({ "top", "left", "right", "both", "bottom" }) do
        local x, y = barAt(c, f[spot])
        near(x, spots[spot].x, spot .. " x")
        near(y, spots[spot].y, spot .. " y")
    end
    near(spots.top.x, -170, "the built-in spot")
    eq(spots.bottom.y, 238)
    local _, pu = barFrames(c)
    local p = c._state(pu.LeftShoulderBackground).points[1]
    eq({ p.point, p.x, p.y }, { "BOTTOMRIGHT", -178, 155 })
    eq({ entry(c, SYS.ChatFrame).anchorInfo.offsetX, entry(c, SYS.ChatFrame).anchorInfo.offsetY }, { 17, 245 })
    eq(entry(c, SYS.Minimap).anchorInfo.offsetX, -6)
    eq(written(PE), {}, "an offset was noted as written")
    -- The spell pictures are at their built-in spots too.
    local half = PE.FaceBars.view[1].halves[1]
    local hp = c._state(half).points[1]
    near(hp.x, -170, "main d-pad panel x")
    near(hp.y, 66, "main d-pad panel y")
    -- The saved offsets are kept.
    eq(opts(PE).offsets, { chat = { x = 30, y = 30 }, map = { x = -4, y = 0 } })
    eq(PE.charDB.ctrlArrange.offsets["inner left diamond"], { x = 20, y = 10 })
    -- The button says what to do, and still calls nothing.
    tapArrangeRow(c, PE)
    check(chatHas(c, "Switch on Arrange it yourself first, then reload."), "the button did not say what to do")
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    eq(stub.calls, {})
    eq(#notes(c), 0, "an arrange line in the log while off")
    c:assertClean()
end)

test("arrange off: the real file loads without a frame, an event or a hook, and its window does not open", function()
    local c, PE = client({ arrange = 0 })
    for _, rec in ipairs(c:frames()) do check(rec.addonFile ~= "Arrange.lua", "Arrange.lua made a frame") end
    eq(PE.Arrange:Open(), false)
    eq(panel(c), nil)
    eq(PE.Arrange:Step("map", 1, 0), false)
    eq(opts(PE).offsets, nil)
    eq(PE.Arrange:Apply(), false)
    eq(saves(c), 1)
    eq(PE.LayoutPlan.session, nil)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The switches
---------------------------------------------------------------------------

test("arrange switch: Off by default; On rewrites the pieces that have a saved offset, asks for one reload, and counts from then", function()
    local c, PE = client({ arrange = 0, offsets = { chat = { x = 30, y = 20 }, map = { x = -4, y = 0 } } })
    local row = optRow(PE, "arrange")
    check(row ~= nil, "no Arrange it yourself row")
    eq(row.label, "Arrange it yourself")
    eq({ row.choices[1].value, row.choices[1].label, row.choices[2].value, row.choices[2].label }, { 0, "Off", 1, "On" })
    eq(optRow(PE, "arrangeWheel").label, "Arrange: spell wheels")
    local fresh = select(2, T.new({}))
    eq(fresh:GetModule("ctrlLayout").opts.arrange, 0)
    eq(fresh:GetModule("ctrlLayout").opts.arrangeWheel, 0)
    -- Every piece marked, to see which are rewritten.
    for _, e in ipairs(ours(c).systems) do if e.anchorInfo then e.anchorInfo.offsetX = 222 end end
    choose(c, PE, "arrange", 1)
    eq(saves(c), 2, "one write")
    local rewritten = {}
    for _, e in ipairs(ours(c).systems) do
        if e.anchorInfo and e.anchorInfo.offsetX ~= 222 then rewritten[e.system] = true end
    end
    eq(rewritten, { [SYS.ChatFrame] = true, [SYS.Minimap] = true })
    eq({ entry(c, SYS.ChatFrame).anchorInfo.offsetX, entry(c, SYS.ChatFrame).anchorInfo.offsetY }, { 47, 265 })
    eq(entry(c, SYS.Minimap).anchorInfo.offsetX, -10)
    eq(written(PE), { chat = { x = 30, y = 20 }, map = { x = -4, y = 0 } })
    eq(reloadReason(PE), RELOAD)
    check(chatHas(c, "Arrange it yourself counts from the next reload."), "not said")
    check(noted(c, "the switch is now 1; it counts from the next reload"), "not in the log")
    -- This session began Off: nothing live moves and the window stays shut.
    eq(PE.LayoutPlan.session, nil)
    tapArrangeRow(c, PE)
    check(chatHas(c, "Arrange it yourself starts with the next reload. Tap Reload now first."), "the button did not say to reload")
    eq(panel(c), nil)
    -- Off again: the two go back to their built-in spots; the offsets are kept.
    choose(c, PE, "arrange", 0)
    eq(saves(c), 3)
    eq({ entry(c, SYS.ChatFrame).anchorInfo.offsetX, entry(c, SYS.ChatFrame).anchorInfo.offsetY }, { 17, 245 })
    eq(entry(c, SYS.Minimap).anchorInfo.offsetX, -6)
    eq(written(PE), {})
    eq(opts(PE).offsets, { chat = { x = 30, y = 20 }, map = { x = -4, y = 0 } })
    local said = 0
    for _, l in ipairs(T.chatLines(c)) do if l == "Arrange it yourself counts from the next reload." then said = said + 1 end end
    eq(said, 1)
    c:assertClean()
end)

test("arrange switch: a change in a fight waits; with Edit Mode open it is put back", function()
    local c, PE = client({ arrange = 0, offsets = { chat = { x = 30, y = 20 } } })
    c:enterCombat()
    choose(c, PE, "arrange", 1)
    eq(saves(c), 1, "the layout was written in a fight")
    c:leaveCombat()
    c:advance(0.1)
    eq(saves(c), 2)
    eq(entry(c, SYS.ChatFrame).anchorInfo.offsetX, 47)
    local c2, PE2 = client({ arrange = 0, offsets = { chat = { x = 30, y = 20 } } })
    c2.world.editMode = true
    choose(c2, PE2, "arrange", 1)
    eq(opts(PE2).arrange, 0)
    eq(saves(c2), 1)
    eq(reloadReason(PE2), nil)
end)

test("arrange on: a session that begins On places every piece at its saved offset, builds the layout with them and asks for no reload", function()
    local char = { ctrlArrange = { offsets = { ["inner left diamond"] = { x = -20, y = 10 }, ["inner right diamond"] = { x = 20, y = 10 },
        ["RB targeting picture"] = { x = 6, y = -4 }, ["spell wheels"] = { x = 0, y = 30 } } } }
    local c, PE = client({ offsets = { chat = { x = 30, y = 20 } }, char = char })
    local Plan = PE.LayoutPlan
    check(Plan.session ~= nil, "the session's offsets are not set")
    local f, pu = barFrames(c)
    local x, y = barAt(c, f.top)
    near(x, -190, "main bar x")
    near(y, 66 + 21 * 1 + 10, "main bar y")
    x, y = barAt(c, f.both)
    near(x, 190, "LT+RT bar x")
    near(y, 66 - 21 + 10, "LT+RT bar y")
    -- The wheels' switch is Off: their saved offset is not applied.
    x, y = barAt(c, f.bottom)
    eq({ x, y }, { 0, 238 })
    local p = c._state(pu.RightShoulderBackground).points[1]
    eq({ p.point, p.x, p.y }, { "BOTTOMLEFT", 184, 151 })
    p = c._state(pu.LeftShoulderBackground).points[1]
    eq({ p.point, p.x, p.y }, { "BOTTOMRIGHT", -178, 155 })
    -- Our own spell pictures and the frames under them that take a tap.
    local hp = c._state(PE.FaceBars.view[1].halves[1]).points[1]
    near(hp.x, -190, "main d-pad panel x")
    near(hp.y, 76, "main d-pad panel y")
    local l, r, t, b = c._rect(PE.FaceBars.backing[1])
    sameRect({ l - W / 2, b, r - W / 2, t }, shifted(LEFT_GUARD, -20, 10), "the left tap guard")
    -- The layout was built with the chat's offset, so nothing waits and no reload is asked for.
    eq({ entry(c, SYS.ChatFrame).anchorInfo.offsetX, entry(c, SYS.ChatFrame).anchorInfo.offsetY }, { 47, 265 })
    eq(written(PE), { chat = { x = 30, y = 20 } })
    eq(PE.Arrange:Waiting(), {})
    eq(saves(c), 1)
    eq(reloadReason(PE), nil)
    -- The log says so.
    check(noted(c, "on (spell wheels=0, steps 2 and 10, centre snap 6)"), "no start line: " .. T.show(notes(c)))
    check(notedLike(c, "^offset: chat 30,20 %-> l="), "the chat's offset is not in the log")
    check(noted(c, "offset: spell wheels 0,30 (its switch is off: not applied) -> l=-157 b=169 w=38 h=38"), "the wheels' line: " .. T.show(notes(c)))
    check(notedLike(c, "^pair LB targeting picture / RB targeting picture: NOT a mirror"), "the pair that is not a mirror is not named")
    c:assertClean()
end)

test("arrange on: at another Spell panel size the offsets sit on that size's spots", function()
    local char = { ctrlArrange = { offsets = { ["inner left diamond"] = { x = -20, y = 10 }, ["outer right diamond"] = { x = 6, y = 0 } } } }
    for _, size in ipairs({ 80, 120 }) do
        local c, PE = client({ panelSize = size, char = char })
        local base = PE.LayoutPlan.BarSpots({ panelSize = size, arrange = 0 })
        local f = barFrames(c)
        local x, y = barAt(c, f.top)
        near(x, base.top.x - 20, size .. "% main bar x")
        near(y, base.top.y + 10, size .. "% main bar y")
        near(c._state(f.top).scale, 0.6 * size / 100, size .. "% main bar scale")
        x, y = barAt(c, f.right)
        near(x, base.right.x, size .. "% RT bar x")
        -- The panels: a half's spot counts in its own scale.
        local spots = PE.LayoutPlan.FaceSpots({ panelSize = size, arrange = 0 })
        local hp = c._state(PE.FaceBars.view[1].halves[1]).points[1]
        near(hp.x * size / 100, spots.inner.left.x - 20, size .. "% main d-pad panel x")
        near(hp.y * size / 100, spots.inner.left.y + 10, size .. "% main d-pad panel y")
        eq(reloadReason(PE), nil)
    end
end)

test("arrange on: the spell wheels move with their own switch, at once, and go back when it is switched off", function()
    local char = { ctrlArrange = { offsets = { ["spell wheels"] = { x = 0, y = 30 } } } }
    local c, PE = client({ wheel = 1, char = char })
    local f = barFrames(c)
    eq({ barAt(c, f.bottom) }, { 0, 268 })
    choose(c, PE, "arrangeWheel", 0)
    eq({ barAt(c, f.bottom) }, { 0, 238 })
    choose(c, PE, "arrangeWheel", 1)
    eq({ barAt(c, f.bottom) }, { 0, 268 })
    eq(saves(c), 1, "the layout was written")
    eq(reloadReason(PE), nil)
    -- Sideways is refused; up and down moves the one anchor both wheels hang on.
    eq({ PE.Arrange:Step("spell wheels", 1, 0) }, { false, "it moves up and down only" })
    eq(PE.Arrange:Step("spell wheels", 0, 1), true)
    eq({ barAt(c, f.bottom) }, { 0, 270 })
    -- Its switch off: not in the list.
    choose(c, PE, "arrangeWheel", 0)
    eq({ PE.Arrange:Step("spell wheels", 0, 1) }, { false, "that piece is not on the screen now" })
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Steps, twins, the centre line
---------------------------------------------------------------------------

test("arrange steps: small is 2 and big is 10, whole numbers, saved per character for a live piece and with the options for an Edit Mode piece", function()
    local c, PE, A = client()
    eq(A:Step("LB targeting picture", 0, 1), true)
    eq(charStore(PE).offsets["LB targeting picture"], { x = 0, y = 2 })
    eq(A:ToggleStep(), 10)
    eq(A:Step("LB targeting picture", -1, 0), true)
    eq(charStore(PE).offsets["LB targeting picture"], { x = -10, y = 2 })
    eq(A:ToggleStep(), 2)
    eq(A:Step("LB targeting picture", 1, 0), true)
    eq(charStore(PE).offsets["LB targeting picture"], { x = -8, y = 2 })
    eq(opts(PE).offsets, {}, "a live piece was saved with the options")
    eq(A:Step("chat", 1, 0), true)
    eq(A:Step("chat", 0, -1), true)
    eq(opts(PE).offsets, { chat = { x = 2, y = -2 } })
    eq(charStore(PE).offsets.chat, nil, "an Edit Mode piece was saved per character")
    -- Back to nothing removes the entry.
    eq(A:Step("chat", -1, 0), true)
    eq(A:Step("chat", 0, 1), true)
    eq(opts(PE).offsets, {})
    eq({ A:Step("chat", 0, 0) }, { false, "no direction" })
    eq({ A:Step("nothing", 1, 0) }, { false, "no such piece" })
    check(noted(c, "step: chat by 2,0 -> offset 2,0"), "no step line: " .. T.show(notes(c)))
    check(noted(c, "not moved: nothing: no such piece"), "no refusal line")
    c:assertClean()
end)

test("arrange live: a step moves the piece at once, with no layout write and no reload", function()
    local c, PE, A = client()
    local f, pu = barFrames(c)
    local writes = saves(c)
    eq(A:ToggleTwins("inner left diamond"), false)
    eq(A:Step("inner left diamond", -1, 0), true)
    eq(A:Step("inner left diamond", 0, 1), true)
    local x, y = barAt(c, f.top)
    near(x, -172, "main bar x")
    near(y, 89, "main bar y")
    x, y = barAt(c, f.left)
    near(x, -172, "LT bar x")
    near(y, 47, "LT bar y")
    near((barAt(c, f.right)), 170, "the right side moved")
    local hp = c._state(PE.FaceBars.view[1].halves[1]).points[1]
    near(hp.x, -172, "main d-pad panel x")
    near(hp.y, 68, "main d-pad panel y")
    local l, r, t, b = c._rect(PE.FaceBars.backing[1])
    sameRect({ l - W / 2, b, r - W / 2, t }, shifted(LEFT_GUARD, -2, 2), "the left tap guard")
    eq(A:Step("RB targeting picture", 1, 0), true)
    local p = c._state(pu.RightShoulderBackground).points[1]
    eq({ p.point, p.x, p.y }, { "BOTTOMLEFT", 180, 155 })
    p = c._state(pu.LeftShoulderBackground).points[1]
    eq({ p.point, p.x, p.y }, { "BOTTOMRIGHT", -180, 155 }, "the mirrored twin")
    eq(saves(c), writes, "the Edit Mode layout was written for a live piece")
    eq(reloadReason(PE), nil)
    eq(A:Waiting(), {})
    c:assertClean()
end)

test("arrange live: the slim bars move at once, a side as a whole, the twin mirrored", function()
    local c, PE, A = client({ slim = 1 })
    local bars, cast = PE.SlimBars.view.bars, PE.SlimBars.view.cast
    check(bars.player and bars.player.frame, "the slim bars did not start")
    local function at(frame)
        local l, r, t, b = c._rect(frame)
        return { l - W / 2, b, r - W / 2, t }
    end
    sameRect(at(bars.player.frame), { -498, 141, -218, 169 }, "player bar before")
    eq(A:ToggleStep(), 10)
    eq(A:Step("player bar", -1, 0), true)
    eq(A:Step("player bar", 0, 1), true)
    sameRect(at(bars.player.frame), { -508, 151, -228, 179 }, "player bar")
    sameRect(at(bars.pet.frame), { -508, 182, -372, 199 }, "pet bar")
    sameRect(at(bars.target.frame), { 228, 151, 508, 179 }, "target bar (the mirror)")
    sameRect(at(bars.tot.frame), { 372, 182, 508, 199 }, "target of target bar")
    sameRect(at(cast.frame), { 228, 137, 508, 149 }, "cast bar")
    eq(charStore(PE).offsets["player bar"], { x = -10, y = 10 })
    eq(charStore(PE).offsets["target bar"], { x = 10, y = 10 })
    eq(saves(c), 1)
    -- The game's frames are not in the list while they are invisible.
    eq({ A:Step("player", 1, 0) }, { false, "that piece is not on the screen now" })
    c:assertClean()
end)

test("arrange twins: a step moves the twin to the exact mirror; a pair set free moves alone; back to mirrored puts the twin on the mirror", function()
    local c, PE, A = client()
    local function off(key) return { PE.LayoutPlan.Moved(nil, key) } end
    eq(A:Step("outer left diamond", -1, 0), true)
    eq(A:Step("outer left diamond", 0, 1), true)
    eq(off("outer left diamond"), { -2, 2 })
    eq(off("outer right diamond"), { 2, 2 })
    -- From the right one: the left follows.
    eq(A:Step("outer right diamond", 1, 0), true)
    eq(off("outer left diamond"), { -4, 2 })
    for _, m in ipairs(A:MirrorCheck()) do check(m.ok, m.a .. " / " .. m.b .. " is not a mirror") end
    -- Free.
    eq(A:ToggleTwins("outer right diamond"), false)
    eq(charStore(PE).alone, { ["outer left diamond"] = true })
    eq(A:Step("outer right diamond", 0, -1), true)
    eq(off("outer right diamond"), { 4, 0 })
    eq(off("outer left diamond"), { -4, 2 })
    local bad = {}
    for _, m in ipairs(A:MirrorCheck()) do if not m.ok then bad[#bad + 1] = m.a .. " / " .. m.b end end
    eq(bad, { "outer left diamond / outer right diamond" })
    -- The other pairs are still mirrored by default.
    eq(A:Step("inner left diamond", 1, 0), true)
    eq(off("inner right diamond"), { -2, 0 })
    -- Mirrored again, from the right one: the left one is put on its mirror.
    eq(A:ToggleTwins("outer right diamond"), true)
    eq(charStore(PE).alone, {})
    eq(off("outer left diamond"), { -4, 0 })
    for _, m in ipairs(A:MirrorCheck()) do check(m.ok, m.a .. " / " .. m.b .. " is not a mirror") end
    check(noted(c, "twins: outer right diamond and outer left diamond now move on their own"), "free is not in the log")
    check(noted(c, "twins: outer right diamond and outer left diamond mirrored again; outer left diamond set from -4,2 to -4,0"),
        "mirrored again is not in the log: " .. T.show(notes(c)))
    check(noted(c, "step: outer left diamond by -2,0 -> offset -2,0; twin outer right diamond -> 2,0 (mirror)"), "the twin's move is not in the log")
    eq({ A:ToggleTwins("map") }, { false, "it has no twin" })
    -- The Edit Mode twins too.
    eq(A:Step("player", -1, 0), true)
    eq(opts(PE).offsets, { player = { x = -2, y = 0 }, target = { x = 2, y = 0 } })
    c:assertClean()
end)

test("arrange centre: a step toward the centre line that ends within 6 of it, or crosses it, lands on it; a step away is never caught", function()
    local c, PE, A = client()
    local Plan = PE.LayoutPlan
    local function centre(name)
        local r = Plan.Rects(PE.ControllerLayout:View())[name]
        return (r[1] + r[3]) / 2
    end
    near(centre("map"), 4, "the round map's built-in middle")
    -- Away from the line: plain steps.
    eq(A:Step("map", 1, 0), true)
    near(centre("map"), 6, "one step right")
    eq(A:Step("map", 1, 0), true)
    near(centre("map"), 8, "two steps right")
    -- Back toward it: 8 to 6 ends within 6 of the line, so it lands on it.
    eq(A:Step("map", -1, 0), true)
    near(centre("map"), 0, "caught")
    eq(opts(PE).offsets.map, { x = -4, y = 0 })
    check(noted(c, "step: map by -2,0 -> offset -4,0 (snapped to the centre line)"), "the snap is not in the log: " .. T.show(notes(c)))
    -- Away from the line again, either side, small steps: not caught.
    eq(A:Step("map", -1, 0), true)
    near(centre("map"), -2, "a step away, left")
    eq(A:Step("map", 1, 0), true)
    near(centre("map"), 0, "and back: caught")
    eq(A:Step("map", 1, 0), true)
    near(centre("map"), 2, "a step away, right")
    -- Up and down never snaps.
    eq(A:Step("map", 0, 1), true)
    near(centre("map"), 2, "after a step up")
    -- A big step across the line lands on it.
    eq(A:ToggleStep(), 10)
    eq(A:Step("map", -1, 0), true)
    near(centre("map"), 0, "across the line")
    -- From far away: plain steps until one ends within 6.
    eq(A:Step("map", 1, 0), true)
    eq(A:Step("map", 1, 0), true)
    eq(A:Step("map", 1, 0), true)
    near(centre("map"), 30, "three big steps right")
    eq(A:Step("map", -1, 0), true)
    near(centre("map"), 20, "a big step back")
    eq(A:Step("map", -1, 0), true)
    near(centre("map"), 10, "another")
    eq(A:Step("map", -1, 0), true)
    near(centre("map"), 0, "the last one lands on the line")
    -- A piece with a twin is never caught: the pair is mirrored instead.
    eq(A:ToggleStep(), 2)
    for _ = 1, 3 do eq(A:Step("LB targeting picture", 1, 0), true) end
    eq({ Plan.Moved(nil, "LB targeting picture") }, { 6, 0 })
    c:assertClean()
end)

test("arrange reset: Reset puts one piece (and its mirrored twin) back; Reset all removes every saved offset, the unknown ones too", function()
    local char = { ctrlArrange = { offsets = { ["inner left diamond"] = { x = -20, y = 10 }, ["inner right diamond"] = { x = 20, y = 10 },
        ["LB targeting picture"] = { x = 4, y = 0 }, ["a piece of a later version"] = { x = 1, y = 1 } }, alone = { ["LB targeting picture"] = true } } }
    local c, PE, A = client({ offsets = { chat = { x = 30, y = 20 }, map = "bad" }, char = char })
    local f = barFrames(c)
    near((barAt(c, f.top)), -190, "before")
    eq(A:Reset("inner left diamond"), true)
    eq(charStore(PE).offsets["inner left diamond"], nil)
    eq(charStore(PE).offsets["inner right diamond"], nil, "the mirrored twin stayed")
    near((barAt(c, f.top)), -170, "the left bars are back at once")
    near((barAt(c, f.right)), 170, "the right bars are back at once")
    check(noted(c, "reset: inner left diamond (was -20,10); twin inner right diamond (was 20,10)"), "not in the log: " .. T.show(notes(c)))
    -- A pair set free: only the one.
    eq(A:Step("RB targeting picture", 1, 0), true)
    eq(A:Reset("RB targeting picture"), true)
    eq(charStore(PE).offsets["LB targeting picture"], { x = 4, y = 0 })
    -- An Edit Mode piece: its offset goes; the game's piece waits for Apply.
    eq(A:Reset("chat"), true)
    eq(opts(PE).offsets.chat, nil)
    eq(A:Waiting(), { "Chat" })
    eq(saves(c), 1)
    -- Reset all.
    eq(A:Step("quest tracker", 0, -1), true)
    eq(A:ResetAll(), 4)
    eq(opts(PE).offsets, {})
    eq(charStore(PE).offsets, {})
    check(PE.LayoutPlan.session.offsets == opts(PE).offsets, "the session lost the saved table")
    check(PE.LayoutPlan.session.charOffsets == charStore(PE).offsets, "the session lost this character's table")
    check(noted(c, "reset all: 4 removed"), "not in the log")
    check(notedLike(c, "^reset all: LB targeting picture 4,0; a piece of a later version 1,1; map; quest tracker 0,%-2$"),
        "what was removed is not in the log: " .. T.show(notes(c)))
    eq(saves(c), 1, "a reset wrote the layout")
    c:assertClean()
end)

test("arrange refused: a step that would leave the screen is not taken, and the log says why", function()
    local c, PE, A = client()
    eq(A:ToggleStep(), 10)
    -- The chat's left edge is 17 from the screen's.
    eq(A:Step("chat", -1, 0), true)
    eq({ A:Step("chat", -1, 0) }, { false, "the edge of the screen" })
    eq(opts(PE).offsets.chat, { x = -10, y = 0 })
    check(noted(c, "not moved: chat: the edge of the screen"), "not in the log")
    -- A mirrored twin leaving the screen stops both.
    eq(A:ToggleStep(), 2)
    local before = copy(charStore(PE).offsets)
    for _ = 1, 400 do
        if not A:Step("outer left diamond", -1, 0) then break end
    end
    local x = PE.LayoutPlan.Moved(nil, "outer left diamond")
    local r = PE.LayoutPlan.Rects(PE.ControllerLayout:View())
    check(r["outer left diamond"][1] >= -W / 2 and r["outer left diamond"][1] < -W / 2 + 2, "the panel did not stop at the edge")
    eq({ PE.LayoutPlan.Moved(nil, "outer right diamond") }, { -x, 0 })
    check(before ~= nil)
    -- The layout switched off: nothing moves.
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    eq({ A:Step("map", 1, 0) }, { false, "the Controller layout is off" })
    eq(opts(PE).offsets.map, nil)
end)

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

test("arrange apply: the waiting Edit Mode pieces are written in one write and one reload is asked for; nothing waiting writes nothing", function()
    local c, PE, A = client()
    eq(A:ToggleStep(), 10)
    eq(A:Step("chat", 1, 0), true)
    eq(A:Step("chat", 0, 1), true)
    eq(A:Step("quest tracker", 0, -1), true)
    eq(A:Step("swing timers", 0, 1), true)
    eq(A:Step("player", -1, 0), true)
    eq(A:Step("inner left diamond", 0, 1), true)
    eq(A:Waiting(), { "Swing timers", "Chat", "Quest list", "Player and pet frames", "Target frames" })
    -- Nothing of the game's layout has changed yet.
    eq(saves(c), 1)
    eq(entry(c, SYS.ChatFrame).anchorInfo.offsetX, 17)
    eq(reloadReason(PE), nil)
    for _, e in ipairs(ours(c).systems) do if e.anchorInfo then e.anchorInfo.relativePoint = "MARK" end end
    eq({ A:Apply() }, { true, 5 })
    c:advance(0.1)
    eq(saves(c), 2, "one write")
    local rewritten = {}
    for _, e in ipairs(ours(c).systems) do
        if e.anchorInfo and e.anchorInfo.relativePoint ~= "MARK" then rewritten[e.system] = (rewritten[e.system] or 0) + 1 end
    end
    eq(rewritten, { [SYS.ChatFrame] = 1, [12] = rewritten[12], [SYS.SwingTimer] = 3, [SYS.UnitFrame] = 3 })
    eq({ entry(c, SYS.ChatFrame).anchorInfo.offsetX, entry(c, SYS.ChatFrame).anchorInfo.offsetY }, { 27, 255 })
    eq(entry(c, SYS.SwingTimer, 1).anchorInfo.offsetY, 204)
    eq(entry(c, SYS.UnitFrame, 1).anchorInfo.offsetX, -405)
    eq(entry(c, SYS.UnitFrame, 2).anchorInfo.offsetX, 405)
    eq(entry(c, SYS.Minimap).anchorInfo.relativePoint, "MARK", "a piece that was not moved was rewritten")
    eq(reloadReason(PE), RELOAD)
    eq(#PE.reloadReasons, 1, "one reload request")
    eq(A:Waiting(), {})
    eq(written(PE), { chat = { x = 10, y = 10 }, ["quest tracker"] = { x = 0, y = -10 }, ["swing timers"] = { x = 0, y = 10 },
        player = { x = -10, y = 0 }, target = { x = 10, y = 0 } })
    check(chatHas(c, "Arrangement written. Tap Reload now in the settings to see the moved pieces."), "not said")
    -- Again with nothing waiting: nothing is written.
    eq({ A:Apply() }, { true, 0 })
    c:advance(0.1)
    eq(saves(c), 2)
    check(chatHas(c, "Your arrangement is saved. Nothing needs a reload."), "not said")
    c:assertClean()
end)

test("arrange apply: the log gets every piece's offset and rectangle, every overlap and the mirror check", function()
    local c, PE, A = client()
    eq(A:ToggleStep(), 10)
    for _ = 1, 4 do eq(A:Step("chat", 0, -1), true) end
    eq(A:ToggleTwins("LB targeting picture"), false)
    eq(A:Step("LB targeting picture", 0, 1), true)
    eq({ A:Apply() }, { true, 1 })
    c:advance(0.1)
    local r = PE.LayoutPlan.Rects(PE.ControllerLayout:View())
    check(noted(c, string.format("apply: chat | chat | offset 0,-40 | l=%.1f b=205 w=450 h=170 | Edit Mode", r.chat[1])), "the chat's line: " .. T.show(notes(c)))
    check(notedLike(c, "^apply: map | map | offset 0,0 | l=%-65.3 b=49.%d w=138.6 h=138.6 | Edit Mode$"), "a piece that was not moved is not listed")
    check(noted(c, "apply: map | title strip | offset 0,0 | l=-83 b=8 w=152 h=23 | Edit Mode"), "the second rectangle of a piece is not listed")
    check(noted(c, "apply: LB targeting picture | LB targeting picture | offset 0,10 | l=-214 b=165 w=36 h=32"), "a live piece is not listed")
    check(noted(c, "apply: inner left diamond | inner left diamond | offset 0,0 | l=-237 b=17 w=134 h=98"), "the spell panel is not listed")
    check(notedLike(c, "^apply: overlap: chat %+ pet | [%d%.]+ x 25 units$"), "the overlap with the pet frame: " .. T.show(notes(c)))
    check(notedLike(c, "^apply: overlap: chat %+ round button | "), "the overlap with the round button")
    check(noted(c, "apply: 2 overlaps"), "the count")
    check(noted(c, "apply: pair LB targeting picture / RB targeting picture: NOT a mirror (0,10 against 0,0)"), "the pair that is not a mirror")
    check(noted(c, "apply: pair inner left diamond / inner right diamond: exact mirror (0,0)"), "a pair that is a mirror")
    check(noted(c, "apply: waiting for a write and a reload: Chat"), "what waits")
    check(noted(c, "apply: 1 piece sent to the layout in one write"), "what was sent")
    check(noted(c, "written into the layout with their offsets: chat 0,-40"), "the layout's line")
    check(noted(c, "the layout was written; still waiting: nothing; one reload asked for"), "the answer")
    for _, l in ipairs(notes(c)) do check(#l < 170, "a line the log would cut: " .. l) end
    c:assertClean()
end)

test("arrange apply: refused while Edit Mode is open; a write the game refuses leaves the pieces waiting", function()
    local c, PE, A = client()
    eq(A:Step("chat", 1, 0), true)
    c.world.editMode = true
    eq({ A:Apply() }, { false, "Close Edit Mode first." })
    eq(saves(c), 1)
    eq(A:Waiting(), { "Chat" })
    eq(reloadReason(PE), nil)
    check(chatHas(c, "Arrange: Close Edit Mode first."), "not said")
    c.world.editMode = false
    c.world.layoutCallFails.SaveLayouts = true
    open(c, PE, "chat")
    local ok, why = A:Apply()
    c:advance(0.1)
    eq(ok, false)
    check(type(why) == "string" and why:find("SaveLayouts", 1, true), "the reason: " .. tostring(why))
    check(#PE.errors >= 1, "the failure is not on the Errors page")
    eq(A:Waiting(), { "Chat" })
    eq(written(PE), {})
    eq(reloadReason(PE), nil)
    check(panel(c):IsShown(), "the window closed though nothing was written")
    check(not chatHas(c, "Arrangement written. Tap Reload now in the settings to see the moved pieces."), "it said written")
    check(chatHas(c, "Arrange: NOT written. Your moves are kept; tap Apply again. See Settings > Errors."), "not said: " .. T.show(T.chatLines(c)))
    check(windowText(c):find("Not moved: the layout was not written", 1, true), "the window: " .. windowText(c))
    check(notedLike(c, "^the layout could not be written %(C_EditMode.SaveLayouts failed"), "not in the log: " .. T.show(notes(c)))
    A:Close("test")
    c:advance(0.1)
    c.world.layoutCallFails.SaveLayouts = nil
    eq({ A:Apply() }, { true, 1 })
    c:advance(0.1)
    eq(A:Waiting(), {})
    eq(entry(c, SYS.ChatFrame).anchorInfo.offsetX, 19)
end)

test("arrange apply: another row that rewrites a moved piece writes it with its offset, and Start over builds with them", function()
    local c, PE, A = client()
    eq(A:Step("tooltip", -1, 0), true)
    eq(A:Step("chat", 1, 0), true)
    -- Spell panel size 120% rewrites the frames, the chat and the tooltip (they rise).
    choose(c, PE, "panelSize", 120)
    local chat = PE.LayoutPlan.Pieces({ panelSize = 120, arrange = 0 })[2].anchor -- the built-in spot at that size
    eq({ entry(c, SYS.ChatFrame).anchorInfo.offsetX, entry(c, SYS.ChatFrame).anchorInfo.offsetY }, { chat.x + 2, chat.y })
    eq(A:Waiting(), {})
    eq(written(PE), { chat = { x = 2, y = 0 }, tooltip = { x = -2, y = 0 } })
    -- Start over (two taps) rebuilds the whole layout: with the offsets.
    eq(A:Step("map", 0, 1), true)
    local row = optRow(PE, "Rebuild the layout")
    PE:Safe("ctrlLayout", row.action, PE:GetModule("ctrlLayout"))
    PE:Safe("ctrlLayout", row.action, PE:GetModule("ctrlLayout"))
    c:advance(0.1)
    eq(entry(c, SYS.Minimap).anchorInfo.offsetY, 2)
    eq(A:Waiting(), {})
end)

---------------------------------------------------------------------------
-- A fight
---------------------------------------------------------------------------

test("arrange fight: the window does not open in a fight, closes when one starts, and nothing of the game's is called until it ends", function()
    local c, PE, A = client()
    c:enterCombat()
    eq(A:Open(), false)
    check(chatHas(c, "Arrange cannot be opened during a fight. Try again afterwards."), "not said")
    eq(panel(c), nil)
    c:leaveCombat()
    c:advance(0.1)
    open(c, PE, "inner left diamond")
    eq(A:Step("inner left diamond", 0, 1), true)
    local calls, writes = barCalls(c), saves(c)
    c:enterCombat()
    check(not panel(c):IsShown(), "the window stayed open in a fight")
    eq(A:IsOpen(), false)
    check(chatHas(c, "Arrange closed for the fight. Your moves are kept."), "not said")
    check(noted(c, "window closed (a fight started)"), "not in the log")
    eq(charStore(PE).offsets["inner left diamond"], { x = 0, y = 2 }, "the move was lost")
    -- A step made in a fight (only the tests can: the window is shut) is saved, and placed after it.
    eq(A:Step("inner left diamond", 0, 1), true)
    eq(A:Step("chat", 1, 0), true)
    eq({ A:Apply() }, { true, 1 })
    eq(barCalls(c), calls, "a bar frame was touched in a fight")
    eq(saves(c), writes, "the layout was written in a fight")
    check(noted(c, "the placement is held for after the fight: inner left diamond"), "the held placement is not in the log")
    local f = barFrames(c)
    near(select(2, barAt(c, f.top)), 89, "the bar moved in a fight")
    c:leaveCombat()
    c:advance(0.1)
    near(select(2, barAt(c, f.top)), 91, "the bar was not placed after the fight")
    eq(saves(c), writes + 1)
    eq(reloadReason(PE), RELOAD)
    -- The settings window does not come back in the middle of a fight.
    check(not (settingsPanel(c) and settingsPanel(c):IsShown()), "the settings came back")
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

test("arrange window: opened from the Controller tab's row; it names the piece, says how it moves, and outlines it and its twin", function()
    local c, PE, A = client()
    PE:OpenSettings()
    c:advance(0.1)
    tapArrangeRow(c, PE)
    check(panel(c) and panel(c):IsShown(), "the window did not open")
    check(not settingsPanel(c):IsShown(), "the settings stayed open under it")
    eq(A:Picked(), "map")
    eq(c._state(panel(c).peTitle).text, "Arrange: Map")
    local text = windowText(c)
    check(text:find("At its built-in spot.", 1, true), "no offset line: " .. text)
    check(text:find("Moves after Apply and a reload.", 1, true), "it does not say how the map moves")
    check(text:find("No twin.", 1, true), "no mirror line")
    check(text:find("No overlap.", 1, true), "no overlap line")
    check(text:find("Nothing waits for Apply.", 1, true), "no waiting line")
    eq(T.labelOf(button(c, "Step: small (2)")), "Step: small (2)")
    eq(c._state(button(c, "No twin")).type, "Button")
    -- The map's two rectangles are outlined, at the plan's numbers.
    local o = outlines(c)
    eq(#o, 2)
    local r = PE.LayoutPlan.Rects(PE.ControllerLayout:View())
    sameRect(o[1].rect, r.map, "the round map's outline")
    sameRect(o[2].rect, r["title strip"], "the strip's outline")
    eq({ o[1].kind, o[2].kind }, { "picked", "picked" })
    -- Next piece, by touch: the swing timers. Then to a live pair.
    c:click(button(c, "Next piece"))
    eq(A:Picked(), "swing timers")
    c:click(button(c, "Previous piece"))
    c:click(button(c, "Previous piece"))
    eq(A:Picked(), "RB targeting picture", "Previous from the first is the last (the wheels are not listed)")
    eq(c._state(panel(c).peTitle).text, "Arrange: RB targeting picture")
    text = windowText(c)
    check(text:find("Moves as you press.", 1, true), "it does not say how a live piece moves")
    check(text:find("Twins are an exact mirror.", 1, true), "no mirror line: " .. text)
    eq(T.labelOf(button(c, "Twins: mirrored")), "Twins: mirrored")
    o = outlines(c)
    eq({ o[1].kind, o[2].kind }, { "picked", "twin" })
    sameRect(o[2].rect, r["LB targeting picture"], "the twin's outline")
    -- The game's frames are listed while the slim bars are off; the slim bars are not.
    local seen = {}
    for _ = 1, 30 do
        seen[A:Picked()] = true
        c:click(button(c, "Next piece"))
    end
    check(seen.player and seen.target, "the game's frames are not in the list")
    check(not seen["player bar"] and not seen["spell wheels"], "a piece that cannot be seen is in the list")
    -- Close: the settings come back.
    c:click(button(c, "Close"))
    c:advance(0.1)
    check(not panel(c):IsShown(), "the window did not close")
    check(settingsPanel(c):IsShown(), "the settings did not come back")
    check(noted(c, "window opened") and noted(c, "window closed (Close)"), "open and close are not in the log")
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == "Arrange.lua" then check(not rec.scripts.OnUpdate, "something of the window ticks") end
    end
    c:assertClean()
end)

test("arrange window: the arrows, Reset, the step and the twins button work by touch and with the controller", function()
    local c, PE, A = client()
    open(c, PE, "inner left diamond")
    local f = barFrames(c)
    c:click(button(c, "Up"))
    c:click(button(c, "Left"))
    eq(charStore(PE).offsets["inner left diamond"], { x = -2, y = 2 })
    eq(charStore(PE).offsets["inner right diamond"], { x = 2, y = 2 })
    near((barAt(c, f.top)), -172, "the bars followed the tap")
    check(windowText(c):find("Moved 2 left, 2 up.", 1, true), "the offset line: " .. windowText(c))
    c:click(button(c, "Step: small (2)"))
    c:click(button(c, "Right"))
    eq(charStore(PE).offsets["inner left diamond"], { x = 8, y = 2 })
    eq(T.labelOf(button(c, "Step: big (10)")), "Step: big (10)")
    c:click(button(c, "Twins: mirrored"))
    c:click(button(c, "Down"))
    eq(charStore(PE).offsets["inner left diamond"], { x = 8, y = -8 })
    eq(charStore(PE).offsets["inner right diamond"], { x = -8, y = 2 })
    check(windowText(c):find("NOT a mirror of its twin.", 1, true), "the mirror warning: " .. windowText(c))
    eq(T.labelOf(button(c, "Twins: free")), "Twins: free")
    c:click(button(c, "Reset"))
    eq(charStore(PE).offsets["inner left diamond"], nil)
    eq(charStore(PE).offsets["inner right diamond"], { x = -8, y = 2 })
    -- Another pair that is not mirrored is counted while a different piece is picked.
    A:Pick("map")
    check(windowText(c):find("1 other pair is not mirrored.", 1, true), "the other pair: " .. windowText(c))
    -- The controller: the d-pad walks to a button and A presses it.
    local p = panel(c)
    local function press(key)
        c:script(nav(c), "OnClick", key, true)
        c:script(nav(c), "OnClick", key, false)
    end
    local function dpadTo(target)
        local n = 0
        while p.peNavFocus ~= target and n < 40 do
            press("RIGHT")
            n = n + 1
        end
        check(p.peNavFocus == target, "the d-pad never reached " .. T.labelOf(target))
    end
    dpadTo(button(c, "Up"))
    press("A")
    eq(opts(PE).offsets.map, { x = 0, y = 10 })
    dpadTo(button(c, "Next piece"))
    press("A")
    eq(A:Picked(), "swing timers")
    press("B")
    c:advance(0.1)
    check(not p:IsShown(), "B did not close the window")
    c:assertClean()
end)

test("arrange window: a piece that overlaps another is named and the other outlined in red; it warns and does not forbid", function()
    local c, PE, A = client()
    open(c, PE, "chat")
    c:click(button(c, "Step: small (2)"))
    for _ = 1, 4 do c:click(button(c, "Down")) end
    eq(opts(PE).offsets.chat, { x = 0, y = -40 }, "the step into another piece was refused")
    local text = windowText(c)
    check(text:find("Overlaps: Player and pet frames, round button.", 1, true), "the warning: " .. text)
    check(text:find("Waiting for Apply: Chat.", 1, true), "what waits: " .. text)
    local red, r = {}, PE.LayoutPlan.Rects(PE.ControllerLayout:View())
    for _, o in ipairs(outlines(c)) do if o.kind == "overlap" then red[#red + 1] = o.rect end end
    eq(#red, 2)
    sameRect(red[1], r.pet, "the pet frame's red outline")
    sameRect(red[2], r["round button"], "the round button's red outline")
    eq(A:OverlapsOf("chat").total, 2)
    eq(A:OverlapsOf("map"), { names = {}, rects = {}, total = 2 })
    -- With another piece picked the window still says the screen has overlaps.
    A:Pick("map")
    check(windowText(c):find("No overlap. 2 on the whole screen.", 1, true), "the total: " .. windowText(c))
    -- Back up: the warning goes.
    A:Pick("chat")
    for _ = 1, 4 do c:click(button(c, "Up")) end
    check(windowText(c):find("No overlap.", 1, true), "the warning stayed")
    for _, o in ipairs(outlines(c)) do check(o.kind ~= "overlap", "a red outline stayed") end
    -- A refused step is said in the window.
    A:Pick("chat")
    c:click(button(c, "Left"))
    c:click(button(c, "Left"))
    check(windowText(c):find("Not moved: the edge of the screen.", 1, true), "the refusal: " .. windowText(c))
    c:assertClean()
end)

test("arrange window: Apply closes it with the reload request in the settings; Reset all asks for a second tap", function()
    local c, PE, A = client()
    PE:OpenSettings()
    c:advance(0.1)
    tapArrangeRow(c, PE)
    A:Pick("chat")
    c:click(button(c, "Up"))
    A:Pick("LB targeting picture")
    c:click(button(c, "Up"))
    c:click(button(c, "Reset all"))
    eq(opts(PE).offsets.chat, { x = 0, y = 2 }, "the first tap reset everything")
    eq(T.labelOf(button(c, "Tap again")), "Tap again")
    -- Any other button takes the question back.
    c:click(button(c, "Up"))
    eq(T.labelOf(button(c, "Reset all")), "Reset all")
    c:click(button(c, "Reset all"))
    c:click(button(c, "Tap again"))
    eq(opts(PE).offsets, {})
    eq(charStore(PE).offsets, {})
    c:click(button(c, "Right"))
    A:Pick("chat")
    c:click(button(c, "Right"))
    c:click(button(c, "Apply"))
    c:advance(0.1)
    check(not panel(c):IsShown(), "the window stayed open after Apply")
    check(settingsPanel(c):IsShown(), "the settings did not come back")
    eq(reloadReason(PE), RELOAD)
    eq(saves(c), 2)
    c:assertClean()
end)

test("arrange window: it sits where it does not cover the picked piece", function()
    local c, PE, A = client()
    open(c, PE, "map")
    eq(panel(c).peCorner, "TOPLEFT")
    A:Pick("chat")
    eq(panel(c).peCorner, "TOPRIGHT", "it covers the chat")
    A:Pick("quest tracker")
    eq(panel(c).peCorner, "TOPLEFT")
    local l, r, t, b = c._rect(panel(c))
    check(l >= 0 and r <= W + 1e-6 and b >= 0 and t <= H + 1e-6, "the window is off the screen")
    check(r - l < W * 0.6 and t - b < H * 0.8, "the window is too large for the screen: " .. (r - l) .. " by " .. (t - b))
end)

test("arrange window: the layout going off closes it", function()
    local c, PE, A = client()
    open(c, PE, "map")
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    check(not panel(c):IsShown(), "the window stayed open")
    eq(A:Open(), false)
    check(chatHas(c, "Arrange cannot be opened: the Controller layout is off."), "not said: " .. T.show(T.chatLines(c)))
end)

---------------------------------------------------------------------------
-- The snapshot
---------------------------------------------------------------------------

test("arrange snapshot: Save a snapshot lists the offsets, what waits and a pair that is not a mirror; nothing while Off", function()
    local char = { ctrlArrange = { offsets = { ["LB targeting picture"] = { x = 4, y = 0 }, ["outer left diamond"] = "bad" } } }
    local c, PE, A = client({ offsets = { chat = { x = 30, y = 20 } }, char = char })
    eq(A:Step("map", 0, 1), true)
    eq(PE.ControllerLayout:Snapshot(), true)
    local lines = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        local text = line:match("^%S+ snapshot: arrange: (.*)$")
        if text then lines[#lines + 1] = text end
    end
    eq(lines, {
        "on, spell wheels 0, 3 offsets",
        "offset LB targeting picture 4,0",
        "offset chat 30,20",
        "offset map 0,2",
        "ignored outer left diamond (not a pair of numbers)",
        "pair LB targeting picture / RB targeting picture is NOT a mirror",
        "waiting for Apply: Map",
    })
    local c2, PE2 = client({ arrange = 0, offsets = { chat = { x = 30, y = 20 } } })
    eq(PE2.ControllerLayout:Snapshot(), true)
    for _, line in ipairs(rawget(c2.env, "PocketEssentialsDB").debug.lines) do
        check(not line:find("arrange: ", 1, true), "an arrange line while Off: " .. line)
    end
    c:assertClean()
end)

---------------------------------------------------------------------------
-- After the review of 0.18.0
---------------------------------------------------------------------------

test("arrange review M1: a row that rewrites one swing timer writes all three with the piece's offset, and a part of a piece is never noted as written", function()
    local c, PE, A = client()
    eq(A:ToggleStep(), 10)
    eq(A:Step("swing timers", 0, 1), true)
    eq(A:Waiting(), { "Swing timers" })
    local before = {}
    for i = 1, 3 do before[i] = entry(c, SYS.SwingTimer, i).anchorInfo.offsetY end
    choose(c, PE, "ranged", 0)
    for i = 1, 3 do eq(entry(c, SYS.SwingTimer, i).anchorInfo.offsetY, before[i] + 10, "timer " .. i) end
    eq(written(PE), { ["swing timers"] = { x = 0, y = 10 } })
    eq(A:Waiting(), {})
    -- The plan's half: only a whole piece is noted.
    local Plan = PE.LayoutPlan
    local o = { arrange = 1, offsets = { ["swing timers"] = { x = 0, y = 4 }, chat = { x = 2, y = 0 } } }
    local all, part = Plan.Pieces(o), {}
    for _, p in ipairs(all) do
        if (p.system == "SwingTimer" and p.index == "Ranged") or p.system == "ChatFrame" then part[#part + 1] = p end
    end
    Plan.MarkWritten(o, part, all)
    eq(o.offsetsWritten, { chat = { x = 2, y = 0 } })
    eq(Plan.Pending(o), { "swing timers" })
    c:assertClean()
end)

test("arrange review W1: Apply with our layout gone says it was not written, keeps the window open and logs why", function()
    local c, PE, A = client()
    eq(A:Step("chat", 1, 0), true)
    open(c, PE, "chat")
    c.world.layouts.layouts = {}
    c.world.layouts.activeLayout = 3
    local ok, why = A:Apply()
    c:advance(0.1)
    eq(ok, false)
    eq(why, "the Pocket Essentials layout could not be read or is not saved")
    check(panel(c):IsShown(), "the window closed")
    check(not chatHas(c, "Arrangement written. Tap Reload now in the settings to see the moved pieces."), "it said written")
    eq(reloadReason(PE), nil)
    eq(A:Waiting(), { "Chat" })
    check(noted(c, "the layout could not be written (the Pocket Essentials layout could not be read or is not saved); the pieces go on waiting"),
        "not in the log: " .. T.show(notes(c)))
end)

test("arrange review W2: with the spell pictures off the wheels' offset still applies and the spell panels are not listed", function()
    local char = { ctrlArrange = { offsets = { ["spell wheels"] = { x = 0, y = 30 } } } }
    local c, PE, A = client({ wheel = 1, char = char, setup = function(c) c.world.noCooldownFrames = true end })
    local f = barFrames(c)
    eq({ barAt(c, f.bottom) }, { 0, 268 })
    eq(c._state(f.top).scale, 1, "the bars are not at full size")
    eq(A:Step("spell wheels", 0, 1), true)
    eq({ barAt(c, f.bottom) }, { 0, 270 })
    eq({ A:Step("inner left diamond", 0, 1) }, { false, "that piece is not on the screen now" })
    open(c, PE)
    local seen = {}
    for _ = 1, 30 do
        seen[A:Picked()] = true
        c:click(button(c, "Next piece"))
    end
    check(not seen["inner left diamond"] and not seen["outer right diamond"], "a spell panel is listed while the pictures are off")
    check(seen["LB targeting picture"] and seen["spell wheels"], "the other live pieces are gone")
    check(windowText(c):find("Spell panels not listed: the spell pictures are off.", 1, true), "the window: " .. windowText(c))
    check(noted(c, "the spell panels are not listed: the spell pictures are off"), "not in the log: " .. T.show(notes(c)))
    c:assertClean()
end)

test("arrange review W3: a login that finds the switch Off and moved pieces still in the layout puts them back once; unapplied moves of an On session are never written by themselves", function()
    local c, PE, A = client({ offsets = { chat = { x = 30, y = 20 } } })
    eq(entry(c, SYS.ChatFrame).anchorInfo.offsetX, 47)
    -- An On session with a move not applied: a new world load writes nothing.
    eq(A:Step("map", 0, 1), true)
    c:fire("PLAYER_ENTERING_WORLD")
    c:advance(0.1)
    eq(saves(c), 1, "an unapplied move was written by itself")
    eq(A:Reset("map"), true)
    -- The switch saved Off though the layout still holds the offset (tapped in a fight, then a reload).
    opts(PE).arrange = 0
    c:fire("PLAYER_ENTERING_WORLD")
    c:advance(0.1)
    eq(saves(c), 2)
    eq({ entry(c, SYS.ChatFrame).anchorInfo.offsetX, entry(c, SYS.ChatFrame).anchorInfo.offsetY }, { 17, 245 })
    eq(written(PE), {})
    eq(reloadReason(PE), RELOAD)
    eq(opts(PE).offsets, { chat = { x = 30, y = 20 } }, "the saved offset was lost")
    check(chatHas(c, "Arrange it yourself is Off: the pieces you had moved go back. Open the settings and tap Reload now to finish."), "not said")
    c:fire("PLAYER_ENTERING_WORLD")
    c:advance(0.1)
    eq(saves(c), 2, "it wrote again")
    -- In a fight it waits; a write that fails is not tried again and again.
    local c2, PE2 = client({ offsets = { chat = { x = 30, y = 20 } } })
    opts(PE2).arrange = 0
    c2.world.layoutCallFails.SaveLayouts = true
    c2:enterCombat()
    c2:fire("PLAYER_ENTERING_WORLD")
    c2:advance(0.1)
    eq(saves(c2), 1)
    c2:leaveCombat()
    c2:advance(0.1)
    local tries = saves(c2)
    c2:fire("PLAYER_ENTERING_WORLD")
    c2:advance(0.1)
    c2:fire("PLAYER_ENTERING_WORLD")
    c2:advance(0.1)
    eq(saves(c2), tries, "it tried again in the same session")
end)

test("arrange review W4: the screen's edge is the plan's screen whatever size UIParent has, and the session's first lines give UIParent's size", function()
    local c, PE, A = client({ screen = { 1024, 768 } })
    check(c.env.UIParent:GetWidth() < 1300, "the stand-in's screen is not smaller: " .. tostring(c.env.UIParent:GetWidth()))
    eq(A:Step("chat", 0, 1), true)
    eq(A:Step("quest tracker", 0, -1), true)
    eq(A:Step("tooltip", 0, 1), true)
    eq(A:Step("XP bars", -1, 0), true)
    eq(A:ToggleStep(), 10)
    eq(A:Step("chat", -1, 0), true)
    eq({ A:Step("chat", -1, 0) }, { false, "the edge of the screen" })
    check(notedLike(c, "^screen: UIParent [%d%.]+ by [%d%.]+, effective scale [%d%.]+; the plan is drawn for 1365.3 by 768$"),
        "no screen line: " .. T.show(notes(c)))
end)

test("arrange review: the slim bars' frames are found by the names SlimBars.lua gives them, and a missing one is logged", function()
    local c, PE, A = client({ slim = 1 })
    local view = PE.SlimBars.view
    for _, key in ipairs({ "player", "pet", "target", "tot" }) do
        check(type(view.bars[key]) == "table" and type(view.bars[key].frame) == "table", "PE.SlimBars.view.bars." .. key .. ".frame is gone")
    end
    check(type(view.cast) == "table" and type(view.cast.frame) == "table", "PE.SlimBars.view.cast.frame is gone")
    eq(A:Step("player bar", 0, 1), true)
    check(not notedLike(c, "^slim bars not placed again"), "a frame was not found: " .. T.show(notes(c)))
    view.bars.pet.frame = nil
    eq(A:Step("player bar", 0, 1), true)
    check(noted(c, "slim bars not placed again: no frame found for the pet bar (PE.SlimBars.view)"), "not in the log: " .. T.show(notes(c)))
end)

test("arrange review: switched Off but not reloaded yet, the window does not open and nothing is moved", function()
    local c, PE, A = client()
    open(c, PE, "map")
    choose(c, PE, "arrange", 0)
    check(not panel(c):IsShown(), "the window stayed open")
    tapArrangeRow(c, PE)
    check(chatHas(c, "Arrange it yourself is Off from the next reload."), "not said: " .. T.show(T.chatLines(c)))
    check(not panel(c):IsShown(), "the window opened")
    eq({ A:Step("chat", 1, 0) }, { false, "Arrange it yourself is Off from the next reload" })
    eq(opts(PE).offsets, {})
    eq(A:Open(), false)
end)

return { known = KNOWN_FAILURES }
