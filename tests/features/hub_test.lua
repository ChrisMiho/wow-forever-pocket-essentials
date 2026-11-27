-- Rules for the round button over the map's book icon (Hub.lua).
-- Source: docs/superpowers/specs/2026-11-20-round-button-on-map-design.md and
-- its plan's Review Focus. Fresh client and addon per test.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local function centre(f)
    local x, y = f:GetCenter()
    return { x = x, y = y }
end

local function same(a, b, what)
    check(math.abs(a.x - b.x) < 0.5 and math.abs(a.y - b.y) < 0.5,
        (what or "not at the same spot") .. ": " .. a.x .. "," .. a.y .. " vs " .. b.x .. "," .. b.y, 2)
end

local function onBook(c, PE, what) same(centre(PE.Hub.button), centre(c.worldMapPortrait), what or "not on the book icon") end

test("hub: opening the map puts the round button on the book icon", function()
    local c, PE = T.new({})
    c:openWorldMap()
    onBook(c, PE)
    c:assertClean("map open")
end)

test("hub: closing the map puts it back where it was", function()
    local c, PE = T.new({})
    local before = centre(PE.Hub.button)
    c:openWorldMap()
    c:closeWorldMap()
    same(centre(PE.Hub.button), before, "not back at its spot")
end)

test("hub: full screen map leaves it where it was; back to normal size puts it on the book", function()
    local c, PE = T.new({})
    local before = centre(PE.Hub.button)
    c:openWorldMap()
    c:maximizeWorldMap()
    same(centre(PE.Hub.button), before, "full screen: not at its spot")
    c:minimizeWorldMap()
    onBook(c, PE, "normal size again: not on the book icon")
end)

test("hub: closing a full screen map and opening it at normal size puts it on the book", function()
    local c, PE = T.new({})
    c:openWorldMap()
    c:maximizeWorldMap()
    c:closeWorldMap()
    c:minimizeWorldMap()
    c:openWorldMap()
    onBook(c, PE)
end)

test("hub: on the map the button and its badge are above the map's border", function()
    local c, PE = T.new({})
    PE.Hub:SetBadge("2")
    c:openWorldMap()
    local button = PE.Hub.button
    local border = c.worldMapBorder
    for name, f in pairs({ border = border, ring = border.NineSlice, book = border.PortraitContainer, title = border.TitleContainer }) do
        check(button:GetFrameLevel() > f:GetFrameLevel(), "the button is under the map's " .. name)
    end
    check(PE.Hub.badge and PE.Hub.badge:GetFrameLevel() > button:GetFrameLevel(), "the badge is under the button")
end)

test("hub: closing the map puts the button back at its own drawing level", function()
    local c, PE = T.new({})
    local level = PE.Hub.button:GetFrameLevel()
    c:openWorldMap()
    check(PE.Hub.button:GetFrameLevel() > level, "the level was not raised on the map")
    c:closeWorldMap()
    eq(PE.Hub.button:GetFrameLevel(), level, "the level stayed raised after the map closed")
end)

test("hub: a tap on the button while it is on the map still works", function()
    local c, PE = T.new({ on = { "chat" } })
    c:openWorldMap()
    c:click(PE.Hub.button)
    c:advance(0.2)
    local panel = rawget(c.env, "PocketEssentialsChatPanel")
    check(panel and panel:IsShown(), "the chat window did not open")
end)

test("hub: a moved button is back at its moved spot after the map was open", function()
    local saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "LEFT", moved = { hub = { x = 30, y = -20 } } }, errors = {} }
    local c, PE = T.new({ saved = saved })
    local before = centre(PE.Hub.button)
    c:openWorldMap()
    c:closeWorldMap()
    same(centre(PE.Hub.button), before, "not back at its moved spot")
end)

test("hub: hooks go on when the map loads after login", function()
    local map
    local c, PE = T.new({ setup = function(c)
        map = rawget(c.env, "WorldMapFrame")
        rawset(c.env, "WorldMapFrame", nil)
    end })
    local function listening()
        local n = 0
        for _, rec in ipairs(c:frames()) do
            if rec.addonFile and rec.events.ADDON_LOADED then n = n + 1 end
        end
        return n
    end
    check(listening() > 0, "nothing waits for the map to load")
    c:fire("ADDON_LOADED", "SomeOtherAddon")
    check(listening() > 0, "stopped waiting before the map loaded")
    rawset(c.env, "WorldMapFrame", map)
    c:fire("ADDON_LOADED", "Blizzard_WorldMap")
    c:openWorldMap()
    onBook(c, PE)
    -- Spec 0.15.0 A9: once the map hook is on, nothing listens for addons loading.
    eq(listening(), 0, "still listening for ADDON_LOADED after the map hook went on")
end)

test("hub: nothing ticks for the map", function()
    local c, PE = T.new({})
    local onUpdate, timers = c.stats.addonOnUpdate, c.stats.addonTimers
    for _ = 1, 2 do
        c:openWorldMap()
        c:advance(1)
        c:closeWorldMap()
        c:advance(1)
    end
    eq(c.stats.addonOnUpdate, onUpdate, "an OnUpdate ran")
    eq(c.stats.addonTimers, timers, "a timer was started")
    c:assertClean("hub map")
end)

test("hub: at first install its only game calls are the two hooks after the map's Maximize and Minimize", function()
    local c, PE = T.new({})
    local hooks = {}
    for _, call in ipairs(c.calls) do
        if call.name == "hooksecurefunc" then hooks[#hooks + 1] = call.args[2] end
    end
    table.sort(hooks)
    eq(hooks, { "Maximize", "Minimize" })
    eq(#c.calls, 2, "other game calls at first install")
end)

-- Spec 0.15.0 A9 and CLAUDE.md "Event handlers and callbacks go through PE:Safe or PE:Wrap":
-- a problem in the press colour (mouse down, the timer after mouse up, hide) is caught
-- and logged under the round button, never passed to the game.
test("hub: its press scripts and the timer after a release are caught and logged", function()
    local c, PE = T.new({})
    local button = PE.Hub.button
    PE.Hub.fill.SetColor = function() error("paint broke", 0) end
    c:script(button, "OnMouseDown", "LeftButton")
    c:script(button, "OnMouseUp", "LeftButton")
    c:advance(0.3)
    button:Hide()
    eq(c.errors, {}, "an error reached the game")
    local count = 0
    for _, e in ipairs(PE.errors) do
        if e.module == "hub" and e.msg == "paint broke" then count = count + (tonumber(e.count) or 1) end
    end
    eq(count, 3, "not every script's error was logged under the round button")
end)


-- 0.16.0: the button's default spot is the controller layout's while the layout is placed.
local function point(PE)
    local p, _, _, x, y = PE.Hub.button:GetPoint(1)
    return p, x, y
end

local function stubSpot(PE, ...)
    local spot = { ... }
    rawset(PE.ControllerLayout, "HubSpot", function() return (unpack or table.unpack)(spot) end)
end

test("hub: with the controller layout placed the default spot is the layout's", function()
    local c, PE = T.new({})
    stubSpot(PE, "BOTTOMLEFT", 10, 162)
    PE.Hub:Refresh()
    local p, x, y = point(PE)
    eq(p, "BOTTOMLEFT"); eq(x, 10); eq(y, 162)
    c:assertClean("layout spot")
end)

-- 0.22.0 (spec item 8): the layout is told the button's size, so it can centre the button on its spot.
test("hub: the layout's spot is asked for with the button's size", function()
    local c, PE = T.new({})
    local asked = {}
    rawset(PE.ControllerLayout, "HubSpot", function(_, size) asked[#asked + 1] = size return "BOTTOMLEFT", 61, 117 end)
    PE.Hub:Refresh()
    check(#asked >= 1, "the spot was not asked for")
    eq(asked[#asked], PE.UI:Metrics().hub)
    local p, x, y = point(PE)
    eq({ p, x, y }, { "BOTTOMLEFT", 61, 117 })
    c:assertClean("size asked")
end)

test("hub: a button the player moved keeps its offset from the old default", function()
    local saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "LEFT", moved = { hub = { x = 30, y = -20 } } }, errors = {} }
    local c, PE = T.new({ saved = saved })
    local before = { point(PE) }
    stubSpot(PE, "BOTTOMLEFT", 10, 162)
    PE.Hub:Refresh()
    local p, x, y = point(PE)
    eq(p, "LEFT"); eq(p, before[1]); eq(x, before[2]); eq(y, before[3])
    check(x > 10, "the offset is not in the point")
end)

test("hub: a position the player chose in settings wins", function()
    local c, PE = T.new({})
    PE:SetUISetting("hubPos", "RIGHT")
    stubSpot(PE, "BOTTOMLEFT", 10, 162)
    PE.Hub:Refresh()
    local p = point(PE)
    eq(p, "RIGHT")
end)

test("hub: without the layout the spot is as before", function()
    local c, PE = T.new({})
    local before = { point(PE) }
    local real = PE.ControllerLayout.HubSpot
    stubSpot(PE)
    PE.Hub:Refresh()
    local p, x, y = point(PE)
    eq(p, "LEFT"); eq(x, before[2]); eq(y, before[3])
    eq(real(PE.ControllerLayout), nil, "the layout is off: no spot")
end)

-- Move on screen's arrow buttons (Move.lua), tapped by touch.
local function arrow(c, label)
    local found
    for _, rec in ipairs(c:frames()) do
        local f = rec.frame
        if c._state(f).type == "Button" and f:IsVisible() and T.labelOf(f) == label then found = f end
    end
    check(found, "no shown button " .. label)
    return found
end

local function tap(c, btn)
    c:script(btn, "OnMouseDown", "LeftButton")
    c:script(btn, "OnMouseUp", "LeftButton")
    c:script(btn, "OnClick", "LeftButton", false)
end

local function corner(c, PE)
    local l, _, _, b = c._rect(PE.Hub.button)
    return { x = l, y = b }
end

test("hub: the first nudge from the layout's spot moves the button one step from that spot", function()
    local c, PE = T.new({})
    stubSpot(PE, "BOTTOMLEFT", 10, 162)
    PE.Hub:Refresh()
    local at = corner(c, PE)
    PE.Move:Open()
    c:advance(0.1)
    tap(c, arrow(c, "Up"))
    local now = corner(c, PE)
    same(now, { x = at.x, y = at.y + PE.UI:Px(2) }, "not one step up from the layout's spot")
    tap(c, arrow(c, "Right"))
    same(corner(c, PE), { x = at.x + PE.UI:Px(2), y = at.y + PE.UI:Px(2) }, "the second step")
    -- The saved offset is from the old default spot, so a button moved before 0.16.0 reads the same.
    local p = point(PE)
    eq(p, "LEFT", "the offset is not from the old default")
    -- The layout goes off: the button stays where the player left it.
    local left = corner(c, PE)
    PE.Move:Close("test")
    stubSpot(PE)
    PE.Hub:Refresh()
    same(corner(c, PE), left, "the button moved when the layout went off")
    c:assertClean("nudge from the layout's spot")
end)

test("hub: Reset with the layout on puts the button back on the layout's spot", function()
    local c, PE = T.new({})
    stubSpot(PE, "BOTTOMLEFT", 10, 162)
    PE.Hub:Refresh()
    local at = corner(c, PE)
    PE.Move:Open()
    c:advance(0.1)
    tap(c, arrow(c, "Down"))
    tap(c, arrow(c, "Reset"))
    same(corner(c, PE), at, "not back on the layout's spot")
end)

test("hub: a button moved before 0.16.0 takes one step from where it is, with the layout on", function()
    local saved = { version = 1, enabled = {}, options = {}, ui = { size = "medium", hubPos = "LEFT", moved = { hub = { x = 30, y = -20 } } }, errors = {} }
    local c, PE = T.new({ saved = saved })
    stubSpot(PE, "BOTTOMLEFT", 10, 162)
    PE.Hub:Refresh()
    local at = corner(c, PE)
    PE.Move:Open()
    c:advance(0.1)
    tap(c, arrow(c, "Left"))
    same(corner(c, PE), { x = at.x - PE.UI:Px(2), y = at.y }, "not one step left of its own spot")
    eq(PE.db.ui.moved.hub.x, 28); eq(PE.db.ui.moved.hub.y, -20)
end)

return { known = KNOWN_FAILURES }
