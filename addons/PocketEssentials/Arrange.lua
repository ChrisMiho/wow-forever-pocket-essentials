local ADDON_NAME, PE = ...

-- Pocket Essentials: Arrange it yourself (PE.Arrange), Controller layout 0.18.0.
-- Spec: docs/superpowers/specs/2026-11-24-0.18.0-arrange.md. A first version.
--
-- A small window, in the manner of Move on screen (Move.lua), that moves the pieces of the
-- Controller layout. Each move is saved as an offset from the piece's built-in spot, in
-- whole UI units. ControllerLayout.lua adds the offsets inside its plan (Plan.Moved), so
-- the overlap check, the snapshot, the spell pictures and the slim bars all see them; this
-- file only changes the saved offsets, asks the layout to place again, and draws the window.
--
-- Two kinds of piece (Plan.ARRANGE, ControllerLayout.lua):
--   live   ours (the spell panels, the slim bars) or placed by the layout with its own
--          calls (the bar anchors, the two targeting pictures): moved at once, out of a
--          fight, by placing the layout again (PE.ControllerLayout:ArrangePlace). Saved per
--          character.
--   apply  the game places it from its Edit Mode layout: the map, chat, quest list, buffs,
--          XP bars, tooltip, swing timers, unit frames. Their frames are never touched: on
--          every Edit Mode system frame the game has replaced SetScale, SetPoint,
--          ClearAllPoints, SetShown and Hide with Lua of its own
--          (Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:9-17, 32-36). The move is
--          collected, written into our Edit Mode layout once on Apply
--          (PE.ControllerLayout:ArrangeApply, the path the option rows use), and one reload
--          shows it. Saved with the layout's options, as the layout is one for the account.
--
-- Symmetry: a piece with a twin moves its twin to the exact mirror about the screen's centre
-- line (per pair: "Twins: free" moves it alone); steps are whole (2 or 10 units); a piece
-- with no twin that steps toward the centre line and ends within 6 units of it, or crosses
-- it, lands exactly on it; MirrorCheck names every pair that is not an exact mirror.
--
-- Nothing here runs unless the session began with "Arrange it yourself" On:
-- ControllerLayout.lua calls this file only then (Snap.ArrangeCall). Loading it makes no
-- frame, registers no event and hooks nothing. The window is built the first time it
-- opens. Nothing ticks. No game frame is called from here: the slim bars' frames placed
-- below are the addon's own (SlimBars.lua), and so is every frame of the window.
--
-- The controller: the window uses the navigation every window of the addon uses
-- (UI:AttachNav: the d-pad moves the highlight, A presses, B closes; the keys are taken only
-- out of a fight). No chat box is opened or focused.
--
-- Public (the names are set with the bracket form: the API check lists widget methods by
-- name, and "Open", "Close" and "Apply" are also names Blizzard uses):
--   Open()  Close(why)  IsOpen()
--   Step(key, dirX, dirY)   one step of that piece; true, or false and why
--   Reset(key)  ResetAll()  ToggleStep()  ToggleTwins(key)  Apply()
--   MirrorCheck()  OverlapsOf(key)  Waiting()
--   Started()  Placed()  Written(ok)     called by ControllerLayout.lua

local Arrange = {}
PE.Arrange = Arrange

local type, tostring, ipairs, pairs = type, tostring, ipairs, pairs
local abs, floor, max, min, format, concat = math.abs, math.floor, math.max, math.min, string.format, table.concat

local KEY = "ctrlLayout"
local PANEL_NAME = "PocketEssentialsArrangePanel"
local SETTINGS_NAME = "PocketEssentialsSettingsPanel"
local STEP_SMALL, STEP_BIG = 2, 10   -- UI units a tap
local SNAP = 6                       -- UI units from the centre line
local TINY = 1e-6
local YELLOW, RED = { 1, 0.82, 0 }, { 1, 0.25, 0.2 }
local BOXES = 20                     -- outlines made, at most shown at once

local TEXT_FIGHT = "Arrange cannot be opened during a fight. Try again afterwards."
local TEXT_CLOSED_FIGHT = "Arrange closed for the fight. Your moves are kept."
local TEXT_SAVED = "Your arrangement is saved. Nothing needs a reload."
local TEXT_NOT_WRITTEN = "Arrange: NOT written. Your moves are kept; tap Apply again. See Settings > Errors."
local TEXT_HELD = "In a fight: the arrangement is written when the fight is over. Then tap Reload now in the settings."
local TEXT_WRITTEN = "Arrangement written. Tap Reload now in the settings to see the moved pieces."

local stepBig = false      -- the step size picked in the window
local selected             -- the picked piece's key
local lastNote             -- why the last tap did nothing, shown until the next one
local confirmAll = false   -- Reset all was tapped once
local snapshotAdded = false

-- The window, made at the first Open.
local UI, panel, built, buildFailed
local buttons = {}         -- by name: prev, next, step, twins, up, down, left, right, reset, apply, resetAll
local lines = {}           -- the text lines
local boxes = {}           -- outline frames
local navList = {}
local backToSettings = false
local closeWhy

local function Note(text)
    if PE.debugOn then PE:Debug(KEY, "arrange: " .. tostring(text)) end
end

local function Fmt(v)
    if type(v) ~= "number" then return "?" end
    if abs(v - floor(v + 0.5)) < TINY then return format("%d", floor(v + 0.5)) end
    return format("%.1f", v)
end

local function Layout()
    local layout = PE.ControllerLayout
    return type(layout) == "table" and layout or nil
end

local function Plan()
    local plan = PE.LayoutPlan
    if type(plan) == "table" and type(plan.Moved) == "function" and type(plan.ARRANGE) == "table" then return plan end
    return nil
end

-- The session's options table for the plan (with the saved offsets), or nil.
local function View()
    local layout = Layout()
    if not layout or type(layout.View) ~= "function" then return nil end
    local view = layout:View()
    if type(view) == "table" and view.arrange == 1 and type(view.offsets) == "table" and type(view.charOffsets) == "table" then
        if type(view.alone) ~= "table" then view.alone = {} end
        return view
    end
    return nil
end

local function Def(key)
    local plan = Plan()
    return plan and plan.ARRANGE_BY[key] or nil
end

-- Whether a piece can be seen, and so is in the list, now.
local function IsListed(view, def)
    if def.when == "slim" then return view.slim == 1 end
    if def.when == "noslim" then return view.slim ~= 1 end
    if def.when == "face" then return not view.faceOff end
    return true
end

local function Listed(view)
    local out = {}
    for _, def in ipairs(Plan().ARRANGE) do
        if IsListed(view, def) then out[#out + 1] = def end
    end
    return out
end

local function Store(view, def)
    return def.kind == "live" and view.charOffsets or view.offsets
end

-- Saves a piece's offset (0, 0 removes the entry). The entry's table is reused.
local function Write(view, def, x, y)
    local store = Store(view, def)
    if abs(x) < TINY and abs(y) < TINY then
        store[def.key] = nil
        return
    end
    local e = store[def.key]
    if type(e) ~= "table" then
        e = {}
        store[def.key] = e
    end
    e.x, e.y = x, y
end

-- The screen the plan's rectangles are worked out for (1365.33 by 768), not UIParent's own
-- size: a piece pinned to an edge of the plan's screen is on its edge, whatever the UI scale.
local function Screen()
    local plan = Plan()
    return plan.SCREEN.w, plan.SCREEN.h
end

-- How far a piece's rectangles stick out of the screen, added up (0: wholly on it).
local function Overflow(rects, def)
    local w, h = Screen()
    local out = 0
    for _, name in ipairs(def.rects) do
        local r = rects[name]
        if r then out = out + max(-w / 2 - r[1], 0) + max(r[3] - w / 2, 0) + max(-r[2], 0) + max(r[4] - h, 0) end
    end
    return out
end

local function OffsetText(x, y)
    if abs(x) < TINY and abs(y) < TINY then return "At its built-in spot." end
    local parts = {}
    if abs(x) >= TINY then parts[#parts + 1] = Fmt(abs(x)) .. (x > 0 and " right" or " left") end
    if abs(y) >= TINY then parts[#parts + 1] = Fmt(abs(y)) .. (y > 0 and " up" or " down") end
    return "Moved " .. concat(parts, ", ") .. "."
end

local function RectText(r)
    return format("l=%s b=%s w=%s h=%s", Fmt(r[1]), Fmt(r[2]), Fmt(r[3] - r[1]), Fmt(r[4] - r[2]))
end

local Refresh -- the window, below

---------------------------------------------------------------------------
-- The checks
---------------------------------------------------------------------------

-- Every pair of twins: { { a =, b = (keys), labelA =, labelB =, ok = bool, ax, ay, bx, by }, ... }.
-- ok: the two offsets are equal and opposite, so the pair is an exact mirror (their built-in
-- spots are).
local function MirrorList(view)
    local out = {}
    for _, def in ipairs(Plan().ARRANGE) do
        if def.twin and def.pair == def.key then
            local twin = Def(def.twin)
            local ax, ay = Plan().Moved(view, def.key)
            local bx, by = Plan().Moved(view, def.twin)
            out[#out + 1] = { a = def.key, b = def.twin, labelA = def.label, labelB = twin and twin.label or def.twin,
                ok = abs(ax + bx) < TINY and abs(ay - by) < TINY, ax = ax, ay = ay, bx = bx, by = by }
        end
    end
    return out
end

local function IsRoom(name)
    return name:sub(-5) == " room" -- kept for the buff boxes; nothing is drawn there yet
end

-- The plan's overlapping pairs for this view, the rooms left out.
local function OverlapList(view)
    local out = {}
    for _, o in ipairs(Plan().Overlaps(Plan().Rects(view))) do
        if not IsRoom(o.a) and not IsRoom(o.b) then out[#out + 1] = o end
    end
    return out
end

-- The piece a rectangle of the plan belongs to (its label), or the rectangle's own name.
local function OwnerLabel(name)
    for _, def in ipairs(Plan().ARRANGE) do
        for _, r in ipairs(def.rects) do
            if r == name then return def.label end
        end
    end
    return name
end

-- What a piece overlaps: { names = { labels of the other pieces }, rects = { their
-- rectangles' names }, total = pairs on the whole screen }.
local function OverlapsOf(view, def)
    local mine = {}
    for _, name in ipairs(def.rects) do mine[name] = true end
    local names, seen, rects = {}, {}, {}
    local all = OverlapList(view)
    for _, o in ipairs(all) do
        local other = (mine[o.a] and not mine[o.b] and o.b) or (mine[o.b] and not mine[o.a] and o.a) or nil
        if other then
            rects[#rects + 1] = other
            local label = OwnerLabel(other)
            if not seen[label] then
                seen[label] = true
                names[#names + 1] = label
            end
        end
    end
    return { names = names, rects = rects, total = #all }
end

-- The labels of the Edit Mode pieces whose offset is not in our layout yet.
local function WaitingLabels()
    local layout, plan = Layout(), Plan()
    local out = {}
    if not layout or not plan or type(layout.opts) ~= "table" then return out end
    for _, key in ipairs(plan.Pending(layout.opts)) do out[#out + 1] = plan.ARRANGE_BY[key].label end
    return out
end

---------------------------------------------------------------------------
-- Our own frames that follow a live move
---------------------------------------------------------------------------

-- The slim bars' frames (SlimBars.lua, PE.SlimBars.view; all the addon's own) to their
-- rectangles of the plan, the way SlimBars.lua places them when it starts.
local slimMissing = {}
local SLIM_FRAMES = { player = "player bar", pet = "pet bar", target = "target bar", tot = "target of target bar" }

local function PlaceSlim()
    local slim, plan = PE.SlimBars, Plan()
    local view = type(slim) == "table" and slim.view or nil
    if type(view) ~= "table" or not plan or type(plan.SlimRects) ~= "function" then return end
    local rects = plan.SlimRects()
    local missing = {}
    local function put(frame, name)
        local r = rects[name]
        if type(frame) ~= "table" or type(frame.SetPoint) ~= "function" or not r then
            missing[#missing + 1] = name
            return
        end
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", r[1], r[2])
    end
    local bars = type(view.bars) == "table" and view.bars or {}
    for key, name in pairs(SLIM_FRAMES) do
        local bar = bars[key]
        put(type(bar) == "table" and bar.frame or nil, name)
    end
    put(type(view.cast) == "table" and view.cast.frame or nil, "cast bar")
    -- Slim bars are on this session and a frame was not where SlimBars.lua keeps it: said, once each.
    local session = View()
    if session and session.slim == 1 then
        table.sort(missing)
        for _, name in ipairs(missing) do
            if not slimMissing[name] then
                slimMissing[name] = true
                Note("slim bars not placed again: no frame found for the " .. name .. " (PE.SlimBars.view)")
            end
        end
    end
end

-- After the layout placed everything (every login, layout event and live step of a session
-- that began with the switch On): the spell panels and the slim bars to the plan's spots.
Arrange["Placed"] = function()
    if PE:InCombat() then return end
    local face = PE.FaceBars
    if type(face) == "table" and type(face.Place) == "function" then PE:Safe(KEY, face.Place, face) end
    PE:Safe(KEY, PlaceSlim)
    if Refresh then Refresh() end
end

---------------------------------------------------------------------------
-- Moving
---------------------------------------------------------------------------

-- The piece, the view, or nil and why not.
local function Ready(key)
    local layout, plan = Layout(), Plan()
    if not layout or not plan or type(layout.ArrangeReady) ~= "function" then return nil, nil, "the Controller layout is missing" end
    local ok, why = layout:ArrangeReady()
    if not ok then return nil, nil, why end
    local view = View()
    if not view then return nil, nil, "the saved offsets are not loaded" end
    local def = plan.ARRANGE_BY[key]
    if not def then return nil, nil, "no such piece" end
    if not IsListed(view, def) then return nil, nil, "that piece is not on the screen now" end
    return def, view
end

local function Refuse(key, why)
    lastNote = why
    Note("not moved: " .. tostring(key) .. ": " .. tostring(why))
    if Refresh then Refresh() end
    return false, why
end

-- A live piece is placed now (out of a fight) or when the fight ends.
local function PlaceLive(def)
    if def.kind ~= "live" then return end
    local how = Layout():ArrangePlace()
    if how == "held" then Note("the placement is held for after the fight: " .. def.key) end
end

-- The twin that moves with a piece, or nil (no twin, or the pair is set free).
local function MirrorTwin(view, def)
    if not def.twin or view.alone[def.pair] then return nil end
    return Def(def.twin)
end

-- One step: dirX, dirY each -1, 0 or 1. Returns true, or false and why.
Arrange["Step"] = function(_, key, dirX, dirY)
    local def, view, why = Ready(key)
    if not def then return Refuse(key, why) end
    dirX, dirY = tonumber(dirX) or 0, tonumber(dirY) or 0
    if dirX == 0 and dirY == 0 then return Refuse(key, "no direction") end
    if def.axis == "y" and dirX ~= 0 then return Refuse(key, "it moves up and down only") end
    local plan = Plan()
    local step = stepBig and STEP_BIG or STEP_SMALL
    local ox, oy = plan.Moved(view, key)
    local nx, ny = ox + dirX * step, oy + dirY * step
    local before = plan.Rects(view)
    local snapped = false
    if dirX ~= 0 and not def.twin then
        -- Toward the centre line and ending within SNAP of it, or across it: onto it.
        local main = before[def.rects[1]]
        if main then
            local c = (main[1] + main[3]) / 2
            local n = c + dirX * step
            if abs(c) > TINY and ((c > 0) ~= (n > 0) or (abs(n) < abs(c) and abs(n) <= SNAP + TINY)) then
                nx, snapped = ox - c, true
            end
        end
    end
    if abs(nx) > plan.ARRANGE_LIMIT or abs(ny) > plan.ARRANGE_LIMIT then return Refuse(key, "it is as far as it goes") end
    local twin = MirrorTwin(view, def)
    local tx, ty = 0, 0
    if twin then tx, ty = plan.Moved(view, twin.key) end
    local outBefore = Overflow(before, def) + (twin and Overflow(before, twin) or 0)
    Write(view, def, nx, ny)
    if twin then Write(view, twin, -nx, ny) end
    local after = plan.Rects(view)
    local outAfter = Overflow(after, def) + (twin and Overflow(after, twin) or 0)
    -- Off the screen: not taken, unless it brings back a piece that was already partly off.
    if outAfter > TINY and outAfter >= outBefore - TINY then
        Write(view, def, ox, oy)
        if twin then Write(view, twin, tx, ty) end
        return Refuse(key, "the edge of the screen")
    end
    lastNote, confirmAll = nil, false
    Note(format("step: %s by %s,%s -> offset %s,%s%s%s", key, Fmt(dirX * step), Fmt(dirY * step), Fmt(nx), Fmt(ny),
        snapped and " (snapped to the centre line)" or "",
        twin and format("; twin %s -> %s,%s (mirror)", twin.key, Fmt(-nx), Fmt(ny)) or ""))
    PlaceLive(def)
    if Refresh then Refresh() end
    return true
end

-- A piece back to its built-in spot (its twin too while the pair is mirrored).
Arrange["Reset"] = function(_, key)
    local def, view, why = Ready(key)
    if not def then return Refuse(key, why) end
    local plan = Plan()
    local ox, oy = plan.Moved(view, key)
    local twin = MirrorTwin(view, def)
    local text = format("reset: %s (was %s,%s)", key, Fmt(ox), Fmt(oy))
    Write(view, def, 0, 0)
    if twin then
        local tx, ty = plan.Moved(view, twin.key)
        Write(view, twin, 0, 0)
        text = text .. format("; twin %s (was %s,%s)", twin.key, Fmt(tx), Fmt(ty))
    end
    lastNote, confirmAll = nil, false
    Note(text)
    PlaceLive(def)
    if Refresh then Refresh() end
    return true
end

-- Every saved offset removed, the ones this version does not know too. Returns how many.
Arrange["ResetAll"] = function()
    local layout = Layout()
    local view = View()
    if not layout or not view then return Refuse("all", "the saved offsets are not loaded") end
    local removed = {}
    for _, store in ipairs({ view.offsets, view.charOffsets }) do
        local keys = {}
        for k in pairs(store) do keys[#keys + 1] = k end
        for _, k in ipairs(keys) do
            local e = store[k]
            removed[#removed + 1] = tostring(k) .. (type(e) == "table" and (" " .. Fmt(e.x) .. "," .. Fmt(e.y)) or "")
            store[k] = nil
        end
    end
    table.sort(removed)
    lastNote, confirmAll = nil, false
    Note("reset all: " .. #removed .. " removed")
    for i = 1, #removed, 4 do
        Note("reset all: " .. concat(removed, "; ", i, min(i + 3, #removed)))
    end
    local ok = layout:ArrangeReady()
    if ok and layout:ArrangePlace() == "held" then Note("the placement is held for after the fight: all") end
    if Refresh then Refresh() end
    return #removed
end

Arrange["ToggleStep"] = function()
    stepBig = not stepBig
    confirmAll = false
    if Refresh then Refresh() end
    return stepBig and STEP_BIG or STEP_SMALL
end

-- "Twins: mirrored" <-> "Twins: free" for the pair of that piece. Back to mirrored, the twin
-- is put on the mirror of that piece at once.
Arrange["ToggleTwins"] = function(_, key)
    local def, view, why = Ready(key)
    if not def then return Refuse(key, why) end
    if not def.twin then return Refuse(key, "it has no twin") end
    lastNote, confirmAll = nil, false
    if view.alone[def.pair] then
        view.alone[def.pair] = nil
        local plan = Plan()
        local x, y = plan.Moved(view, key)
        local twin = Def(def.twin)
        local tx, ty = plan.Moved(view, twin.key)
        Write(view, twin, -x, y)
        Note(format("twins: %s and %s mirrored again; %s set from %s,%s to %s,%s", key, twin.key, twin.key, Fmt(tx), Fmt(ty), Fmt(-x), Fmt(y)))
        PlaceLive(def)
    else
        view.alone[def.pair] = true
        Note(format("twins: %s and %s now move on their own", key, def.twin))
    end
    if Refresh then Refresh() end
    return not view.alone[def.pair]
end

Arrange["MirrorCheck"] = function()
    local view = View()
    return view and MirrorList(view) or {}
end

Arrange["OverlapsOf"] = function(_, key)
    local view, def = View(), Def(key)
    if not view or not def then return { names = {}, rects = {}, total = 0 } end
    return OverlapsOf(view, def)
end

Arrange["Waiting"] = function()
    return WaitingLabels()
end

---------------------------------------------------------------------------
-- The debug log
---------------------------------------------------------------------------

local function LogMirrors(view, prefix, all)
    for _, m in ipairs(MirrorList(view)) do
        if m.ok then
            if all then Note(format("%spair %s / %s: exact mirror (%s,%s)", prefix, m.a, m.b, Fmt(m.ax), Fmt(m.ay))) end
        else
            Note(format("%spair %s / %s: NOT a mirror (%s,%s against %s,%s)", prefix, m.a, m.b, Fmt(m.ax), Fmt(m.ay), Fmt(m.bx), Fmt(m.by)))
        end
    end
end

-- Every piece's offset and where that puts each of its rectangles, every overlap, the
-- mirror check and what waits: what Apply writes, so an arrangement can become the built-in
-- one.
local function LogAll(view, prefix)
    local plan = Plan()
    local rects = plan.Rects(view)
    for _, def in ipairs(plan.ARRANGE) do
        local x, y = plan.Moved(view, def.key)
        for _, name in ipairs(def.rects) do
            local r = rects[name]
            if r then
                Note(format("%s%s | %s | offset %s,%s | %s%s", prefix, def.key, name, Fmt(x), Fmt(y), RectText(r),
                    def.kind == "apply" and " | Edit Mode" or ""))
            end
        end
    end
    local overlaps = OverlapList(view)
    for _, o in ipairs(overlaps) do
        Note(format("%soverlap: %s + %s | %s x %s units", prefix, o.a, o.b, Fmt(o.w), Fmt(o.h)))
    end
    Note(prefix .. #overlaps .. (#overlaps == 1 and " overlap" or " overlaps"))
    LogMirrors(view, prefix, true)
    local waiting = WaitingLabels()
    Note(prefix .. "waiting for a write and a reload: " .. (#waiting > 0 and concat(waiting, ", ") or "nothing"))
end

-- Why a saved value does not count, or nil when it does.
local function BadEntry(plan, kind, key, e)
    local def = type(key) == "string" and plan.ARRANGE_BY[key] or nil
    if not def then return "no piece of that name in this version" end
    if def.kind ~= kind then return "saved in the wrong file for that piece" end
    if type(e) ~= "table" then return "not a pair of numbers" end
    local x, y = e.x, e.y
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return "not a number" end
    if abs(x) > plan.ARRANGE_LIMIT or abs(y) > plan.ARRANGE_LIMIT then return "further than " .. plan.ARRANGE_LIMIT end
    return nil
end

-- The saved offsets as text, sorted: "key x,y" for each that counts and "key (why)" for each
-- that does not; and the keys of the first list, in the same order.
local function OffsetLines(view)
    local plan = Plan()
    local good, bad, keys = {}, {}, {}
    for kind, store in pairs({ apply = view.offsets, live = view.charOffsets }) do
        for key, e in pairs(store) do
            local why = BadEntry(plan, kind, key, e)
            if why then
                bad[#bad + 1] = tostring(key) .. " (" .. why .. ")"
            else
                good[#good + 1] = key .. " " .. Fmt(e.x) .. "," .. Fmt(e.y)
            end
        end
    end
    table.sort(good)
    table.sort(bad)
    for i, l in ipairs(good) do
        for _, def in ipairs(plan.ARRANGE) do
            if l:sub(1, #def.key + 1) == def.key .. " " then keys[i] = def.key end
        end
    end
    return good, bad, keys
end

local function SnapshotSource()
    local view = View()
    if not view or not PE.debugOn then return end
    local good, bad = OffsetLines(view)
    PE:Debug("snapshot", "arrange: on, " .. #good .. " offsets")
    for _, l in ipairs(good) do PE:Debug("snapshot", "arrange: offset " .. l) end
    for _, l in ipairs(bad) do PE:Debug("snapshot", "arrange: ignored " .. l) end
    for _, m in ipairs(MirrorList(view)) do
        if not m.ok then PE:Debug("snapshot", "arrange: pair " .. m.a .. " / " .. m.b .. " is NOT a mirror") end
    end
    local waiting = WaitingLabels()
    PE:Debug("snapshot", "arrange: waiting for Apply: " .. (#waiting > 0 and concat(waiting, ", ") or "nothing"))
end

-- Once, when a session that began with the switch On first needs its offsets.
Arrange["Started"] = function()
    local view, layout = View(), Layout()
    if not view then
        Note("on, but the saved offsets could not be read: nothing is moved")
        return
    end
    Note(format("on (steps %d and %d, centre snap %d)", STEP_SMALL, STEP_BIG, SNAP))
    local good, bad, keys = OffsetLines(view)
    local plan = Plan()
    if type(UIParent) == "table" then
        Note(format("screen: UIParent %s by %s, effective scale %s; the plan is drawn for %s by %s", Fmt(UIParent:GetWidth()),
            Fmt(UIParent:GetHeight()), Fmt(UIParent:GetEffectiveScale()), Fmt(plan.SCREEN.w), Fmt(plan.SCREEN.h)))
    end
    local rects = plan.Rects(view)
    for i, l in ipairs(good) do
        local def = keys[i] and plan.ARRANGE_BY[keys[i]]
        local r = def and rects[def.rects[1]]
        Note("offset: " .. l .. (r and (" -> " .. RectText(r)) or ""))
    end
    for _, l in ipairs(bad) do Note("ignored: " .. l) end
    if #good == 0 and #bad == 0 then Note("no offsets saved: everything at its built-in spot") end
    LogMirrors(view, "", false)
    local waiting = WaitingLabels()
    if #waiting > 0 then Note("waiting for Apply: " .. concat(waiting, ", ")) end
    if not snapshotAdded and layout and type(layout.AddSnapshotSource) == "function" then
        snapshotAdded = true
        layout:AddSnapshotSource(SnapshotSource)
    end
end

-- The layout's write finished (ControllerLayout.lua, RunRewrites).
Arrange["Written"] = function(_, ok, why)
    if ok then
        local waiting = WaitingLabels()
        Note("the layout was written; still waiting: " .. (#waiting > 0 and concat(waiting, ", ") or "nothing") .. "; one reload asked for")
    else
        Note("the layout could not be written (" .. tostring(why or "see the Errors page") .. "); the pieces go on waiting")
    end
    if Refresh then Refresh() end
end

-- Writes the waiting Edit Mode pieces into our layout, once, and asks for one reload.
-- Returns true and how many pieces were sent, or false and why.
Arrange["Apply"] = function()
    local layout, view = Layout(), View()
    if not layout or not view or type(layout.ArrangeApply) ~= "function" then return Refuse("apply", "the Controller layout is missing") end
    local ready, why = layout:ArrangeReady()
    if not ready then return Refuse("apply", why) end
    lastNote, confirmAll = nil, false
    LogAll(view, "apply: ")
    local waiting = #WaitingLabels()
    local ok, n, held = layout:ArrangeApply()
    if not ok and waiting > 0 and #WaitingLabels() > 0 and n ~= "Close Edit Mode first." then
        -- The write itself failed: nothing changed in the game's layout.
        Note("apply: NOT written: " .. tostring(n))
        PE:Print(TEXT_NOT_WRITTEN)
        lastNote = "the layout was not written"
        if Refresh then Refresh() end
        return false, n
    end
    if not ok then
        Note("apply refused: " .. tostring(n))
        PE:Print("Arrange: " .. tostring(n))
        lastNote = n
        if Refresh then Refresh() end
        return false, n
    end
    if n == 0 then
        Note("apply: nothing waits; nothing written, no reload asked for")
        PE:Print(TEXT_SAVED)
        if Refresh then Refresh() end
        return true, 0
    end
    Note("apply: " .. n .. (n == 1 and " piece" or " pieces") .. " sent to the layout in one write"
        .. (held and " (held for after the fight)" or ""))
    PE:Print(held and TEXT_HELD or TEXT_WRITTEN)
    Arrange["Close"](Arrange, "Apply")
    return true, n
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Select(key)
    selected = key
    lastNote, confirmAll = nil, false
    Note("picked: " .. tostring(key))
    if Refresh then Refresh() end
end

-- The next (dir 1) or previous (dir -1) piece of the list, round and round.
local function Walk(dir)
    local view = View()
    if not view then return end
    local list = Listed(view)
    if #list == 0 then return end
    local at = 1
    for i, def in ipairs(list) do if def.key == selected then at = i end end
    at = at + dir
    if at < 1 then at = #list elseif at > #list then at = 1 end
    Select(list[at].key)
end

local function MakeBox()
    local box = CreateFrame("Frame", nil, UIParent)
    box:Hide()
    box:SetFrameStrata("FULLSCREEN") -- above the pieces and our windows; it takes no taps
    box:EnableMouse(false)
    box.fill = box:CreateTexture(nil, "BACKGROUND")
    box.fill:SetAllPoints(box)
    box.edges = {}
    for i = 1, 4 do box.edges[i] = box:CreateTexture(nil, "OVERLAY") end
    local m = UI:Metrics()
    box.label = box:CreateFontString(nil, "OVERLAY", m.smallFont)
    if not box.label:GetFont() and GameFontNormal then box.label:SetFontObject(GameFontNormal) end
    box.label:SetWordWrap(false)
    box.label:SetPoint("BOTTOM", box, "TOP", 0, 2)
    return box
end

-- One outline over a rectangle of the plan: colour, edge thickness, the fill's strength and
-- the name over it (nil: none).
local function ShowBox(i, r, colour, t, fill, name)
    local box = boxes[i]
    if not box then return end
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", r[1], r[2])
    box:SetSize(max(r[3] - r[1], 1), max(r[4] - r[2], 1))
    box.fill:SetColorTexture(colour[1], colour[2], colour[3], fill)
    local e = box.edges
    for k = 1, 4 do
        e[k]:ClearAllPoints()
        e[k]:SetColorTexture(colour[1], colour[2], colour[3], 1)
    end
    e[1]:SetPoint("TOPLEFT", box, "TOPLEFT", -t, t); e[1]:SetPoint("TOPRIGHT", box, "TOPRIGHT", t, t); e[1]:SetHeight(t)
    e[2]:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -t, -t); e[2]:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", t, -t); e[2]:SetHeight(t)
    e[3]:SetPoint("TOPLEFT", box, "TOPLEFT", -t, t); e[3]:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -t, -t); e[3]:SetWidth(t)
    e[4]:SetPoint("TOPRIGHT", box, "TOPRIGHT", t, t); e[4]:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", t, -t); e[4]:SetWidth(t)
    box.label:SetTextColor(colour[1], colour[2], colour[3], 1)
    box.label:SetText(name or "")
    box.peRect, box.peKind = r, (colour == RED and "overlap") or (fill > 0.1 and "picked" or "twin")
    box:Show()
end

-- The window in the first corner (top left, top right, bottom right, bottom left) where it
-- covers least of the picked piece and its twin.
local function PlaceCorner(yellow)
    local w, h = Screen()
    local pw, ph = panel.peWidth or 0, panel.peHeight or 0
    local m = UI:Px(10)
    local corners = {
        { "TOPLEFT", m, -m, -w / 2 + m, h - m - ph },
        { "TOPRIGHT", -m, -m, w / 2 - m - pw, h - m - ph },
        { "BOTTOMRIGHT", -m, m, w / 2 - m - pw, m },
        { "BOTTOMLEFT", m, m, -w / 2 + m, m },
    }
    local best, bestArea
    for _, c in ipairs(corners) do
        local area = 0
        for _, r in ipairs(yellow) do
            local ow = min(r[3], c[4] + pw) - max(r[1], c[4])
            local oh = min(r[4], c[5] + ph) - max(r[2], c[5])
            if ow > 0 and oh > 0 then area = area + ow * oh end
        end
        if not best or area < bestArea - TINY then best, bestArea = c, area end
    end
    panel:ClearAllPoints()
    panel:SetPoint(best[1], UIParent, best[1], best[2], best[3])
    panel.peCorner = best[1]
end

local function SizeAndPlace()
    local M = UI:Metrics()
    local bh, gap, pad, b = M.button, M.gap, M.pad, M.border
    local colW = bh * 4.4
    local cell = bh * 1.8
    local crossW = cell * 3 + gap * 2
    local lineH = UI:LineHeight("small")
    local rowsH = 4 * bh + 3 * gap
    local textH = #lines * lineH
    local width = pad * 2 + colW + gap * 2 + crossW
    local height = b + (bh + gap) + gap + rowsH + gap + textH + pad
    panel:SetPanelSize(width, height)
    local content = panel.content
    local function at(btn, x, row, w)
        btn:ClearAllPoints()
        btn:SetSize(w, bh)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", x, -row * (bh + gap))
    end
    at(buttons.prev, 0, 0, colW)
    at(buttons.next, 0, 1, colW)
    at(buttons.step, 0, 2, colW)
    at(buttons.twins, 0, 3, colW)
    local x0 = colW + gap * 2
    at(buttons.up, x0 + cell + gap, 0, cell)
    at(buttons.left, x0, 1, cell)
    at(buttons.reset, x0 + cell + gap, 1, cell)
    at(buttons.right, x0 + 2 * (cell + gap), 1, cell)
    at(buttons.down, x0 + cell + gap, 2, cell)
    local half = (crossW - gap) / 2
    at(buttons.apply, x0, 3, half)
    at(buttons.resetAll, x0 + half + gap, 3, half)
    for i, line in ipairs(lines) do
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(rowsH + gap + (i - 1) * lineH))
        line:SetWidth(width - pad * 2)
    end
end

Refresh = function()
    if not built or not panel:IsShown() then return end
    local view, plan = View(), Plan()
    if not view or not plan then return end
    local def = selected and plan.ARRANGE_BY[selected] or nil
    if not def or not IsListed(view, def) then
        def = Listed(view)[1]
        selected = def and def.key or nil
    end
    for i = 1, #boxes do boxes[i]:Hide() end
    if not def then return end
    panel:SetTitle("Arrange: " .. def.label)
    buttons.step:SetLabel(stepBig and ("Step: big (" .. STEP_BIG .. ")") or ("Step: small (" .. STEP_SMALL .. ")"))
    if def.twin then
        local free = view.alone[def.pair]
        buttons.twins:SetLabel(free and "Twins: free" or "Twins: mirrored")
        buttons.twins:SetStyle(free and "warn" or "on")
    else
        buttons.twins:SetLabel("No twin")
        buttons.twins:SetStyle("disabled")
    end
    buttons.resetAll:SetLabel(confirmAll and "Tap again" or "Reset all")
    buttons.resetAll:SetStyle(confirmAll and "warn" or "normal")
    local sideways = def.axis ~= "y"
    buttons.left:SetStyle(sideways and "normal" or "disabled")
    buttons.right:SetStyle(sideways and "normal" or "disabled")
    local waiting = WaitingLabels()
    buttons.apply:SetStyle(#waiting > 0 and "on" or "normal")

    local rects = plan.Rects(view)
    local x, y = plan.Moved(view, def.key)
    local main = rects[def.rects[1]]
    local centred = main and not def.twin and abs((main[1] + main[3]) / 2) < TINY
    lines[1]:SetText(OffsetText(x, y) .. (centred and " On the centre line." or ""))
    -- A piece's own note stands in for how it moves (the spell wheels: "Up and down only. Both
    -- sides move together."): the line has no room for both.
    lines[2]:SetText(((type(def.note) == "string" and def.note) or (def.kind == "live" and "Moves as you press.")
            or "Moves after Apply and a reload.")
        .. (lastNote and (" Not moved: " .. tostring(lastNote) .. ".") or "")
        .. (view.faceOff and " Spell panels not listed: the spell pictures are off." or ""))
    local others, mine = 0, nil
    for _, m in ipairs(MirrorList(view)) do
        if m.a == def.pair then mine = m elseif not m.ok then others = others + 1 end
    end
    local mirrorText = mine and (mine.ok and "Twins are an exact mirror." or "NOT a mirror of its twin.") or "No twin."
    if others > 0 then
        mirrorText = mirrorText .. " " .. others .. (others == 1 and " other pair is" or " other pairs are") .. " not mirrored."
    end
    lines[3]:SetText(mirrorText)
    local over = OverlapsOf(view, def)
    lines[4]:SetText((#over.names > 0 and ("Overlaps: " .. concat(over.names, ", ") .. ".") or "No overlap.")
        .. (over.total > #over.rects and (" " .. over.total .. " on the whole screen.") or ""))
    lines[5]:SetText(#waiting > 0 and ("Waiting for Apply: " .. concat(waiting, ", ") .. ".") or "Nothing waits for Apply.")

    -- The outlines: the picked piece, its twin, what it overlaps.
    local n, yellow = 0, {}
    local t = max(UI:Px(3), 2)
    for i, name in ipairs(def.rects) do
        local r = rects[name]
        if r and n < BOXES and not IsRoom(name) then
            n = n + 1
            ShowBox(n, r, YELLOW, t, 0.15, i == 1 and def.label or nil)
            yellow[#yellow + 1] = r
        end
    end
    local twin = def.twin and plan.ARRANGE_BY[def.twin] or nil
    if twin then
        for _, name in ipairs(twin.rects) do
            local r = rects[name]
            if r and n < BOXES and not IsRoom(name) then
                n = n + 1
                ShowBox(n, r, YELLOW, max(t / 2, 1), 0.05, nil)
                yellow[#yellow + 1] = r
            end
        end
    end
    local shown = {}
    for _, name in ipairs(over.rects) do
        local r = rects[name]
        if r and n < BOXES and not shown[name] then
            shown[name] = true
            n = n + 1
            ShowBox(n, r, RED, t, 0.12, OwnerLabel(name))
        end
    end
    PlaceCorner(yellow)
    panel:NavRefresh()
end

local function SettingsShown()
    local settings = rawget(_G, SETTINGS_NAME)
    return type(settings) == "table" and settings.IsShown and settings:IsShown() or false
end

local function SettingsBack()
    if PE:InCombat() then return end
    if type(UISpecialFrames) == "table" then
        for _, name in ipairs(UISpecialFrames) do
            local other = type(name) == "string" and name:find("^PocketEssentials") and _G[name]
            if other and other.IsShown and other:IsShown() then return end
        end
    end
    PE:OpenSettings()
end

local function OnHidden()
    for i = 1, #boxes do boxes[i]:Hide() end
    PE:UnregisterCoreEvent("PLAYER_REGEN_DISABLED", "arrange")
    Note("window closed (" .. (closeWhy or "B, Escape or another window") .. ")")
    local byFight = closeWhy == "a fight started"
    closeWhy = nil
    confirmAll = false
    if backToSettings then
        backToSettings = false
        if not byFight then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, PE:Wrap(KEY, SettingsBack))
            else
                PE:Safe(KEY, SettingsBack)
            end
        end
    end
end

local function OnFight()
    if not (built and panel:IsShown()) then return end
    PE:Print(TEXT_CLOSED_FIGHT)
    Arrange["Close"](Arrange, "a fight started")
end

local function Button(name, label, fn)
    local btn = UI:CreateButton(panel.content, label)
    btn:SetScript("OnClick", PE:Wrap(KEY, fn))
    buttons[name] = btn
    return btn
end

local function Build()
    UI = PE.UI
    panel = UI:CreatePanel(PANEL_NAME, "Arrange", UI:Px(600), UI:Px(400))
    panel.closeButton:SetScript("OnClick", PE:Wrap(KEY, function() Arrange["Close"](Arrange, "Close") end))
    Button("prev", "Previous piece", function() Walk(-1) end)
    Button("next", "Next piece", function() Walk(1) end)
    Button("step", "Step", function() Arrange["ToggleStep"](Arrange) end)
    Button("twins", "Twins", function()
        local def = selected and Def(selected)
        if def and def.twin then Arrange["ToggleTwins"](Arrange, selected) end
    end)
    Button("up", "Up", function() Arrange["Step"](Arrange, selected, 0, 1) end)
    Button("down", "Down", function() Arrange["Step"](Arrange, selected, 0, -1) end)
    Button("left", "Left", function() Arrange["Step"](Arrange, selected, -1, 0) end)
    Button("right", "Right", function() Arrange["Step"](Arrange, selected, 1, 0) end)
    Button("reset", "Reset", function() Arrange["Reset"](Arrange, selected) end)
    Button("apply", "Apply", function() Arrange["Apply"](Arrange) end)
    Button("resetAll", "Reset all", function()
        if not confirmAll then
            confirmAll = true
            Refresh()
            return
        end
        Arrange["ResetAll"](Arrange)
    end)
    for i = 1, 5 do
        local line = UI:CreateText(panel.content, "small")
        line:SetWordWrap(false)
        line:SetTextColor(0.92, 0.92, 0.92, 1)
        lines[i] = line
    end
    for i = 1, BOXES do boxes[i] = MakeBox() end
    for _, name in ipairs({ "prev", "next", "step", "twins", "up", "left", "reset", "right", "down", "apply", "resetAll" }) do
        navList[#navList + 1] = buttons[name]
    end
    navList[#navList + 1] = panel.closeButton
    UI:AttachNav(panel, function() return navList end)
    panel:HookScript("OnHide", PE:Wrap(KEY, OnHidden))
    UI:OnMetricsChanged(PE:Wrap(KEY, function()
        if not built then return end
        SizeAndPlace()
        Refresh()
    end))
    SizeAndPlace()
end

Arrange["Open"] = function()
    if PE:InCombat() then
        Note("not opened: in a fight")
        PE:Print(TEXT_FIGHT)
        return false
    end
    local layout = Layout()
    local ready, why = false, "the Controller layout is missing"
    if layout and Plan() and type(layout.ArrangeReady) == "function" then ready, why = layout:ArrangeReady() end
    if ready and not View() then ready, why = false, "the saved offsets are not loaded" end
    if not ready then
        Note("not opened: " .. tostring(why))
        PE:Print("Arrange cannot be opened: " .. tostring(why) .. ".")
        return false
    end
    if not built and not buildFailed then
        if PE.UI and PE:Safe(KEY, Build) then
            built = true
        else
            buildFailed = true
            if panel then pcall(panel.Hide, panel) end
        end
    end
    if not built then
        PE:Print("Arrange could not be opened. See Settings > Errors.")
        return false
    end
    backToSettings = SettingsShown() or (backToSettings and panel:IsShown())
    PE:CloseSettings()
    if type(UISpecialFrames) == "table" then
        for _, name in ipairs(UISpecialFrames) do
            local other = type(name) == "string" and name:find("^PocketEssentials") and _G[name]
            if other and other ~= panel and other.IsShown and other:IsShown() then pcall(other.Hide, other) end
        end
    end
    PE:RegisterCoreEvent("PLAYER_REGEN_DISABLED", "arrange", OnFight)
    lastNote, confirmAll = nil, false
    if not panel:IsShown() then panel:Show() end
    panel:Raise()
    Note("window opened")
    local view = View()
    if view and view.faceOff then Note("the spell panels are not listed: the spell pictures are off") end
    Refresh()
    return true
end

Arrange["Close"] = function(_, why)
    if built and panel:IsShown() then
        closeWhy = type(why) == "string" and why or nil
        panel:Hide()
    end
end

Arrange["IsOpen"] = function()
    return built and panel:IsShown() or false
end

-- For the window's buttons and the tests: the picked piece's key, and picking one.
Arrange["Picked"] = function()
    return selected
end

Arrange["Pick"] = function(_, key)
    local view, def = View(), Def(key)
    if not view or not def or not IsListed(view, def) then return false end
    Select(key)
    return true
end
