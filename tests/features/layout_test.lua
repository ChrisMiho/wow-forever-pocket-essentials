-- Rules for the "Layout helper" (Layout.lua).
-- Sources: Layout.lua's header and comments; docs/DECISIONS.md, part "Layout" of
-- "Decisions made without the maintainer". Each test names its source in a comment.
-- Fresh client and addon per test.
--
-- The addon bundles no handheld layout yet (Layout.lua BUNDLED_LAYOUT = nil), so the "install"
-- tests load a temporary copy of the addon in which that one line holds a placeholder string, and
-- the stand-in's world.layoutImport says what the game reads out of it. The real addon files
-- are not changed.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local PRESETS = 3   -- Modern, Classic, Gamepad (the stand-in's presets, Enum.EditModePresetLayouts)
local GAMEPAD_INDEX = 3

local function saved(name, layoutType, style)
    return { layoutName = name, layoutType = layoutType or 1, interfaceStyle = style, systems = { {} } }
end

local function newLayout(opts)
    opts = opts or {}
    return T.new({ on = { "layout" }, gamepadUI = opts.gamepadUI, addonDir = opts.addonDir, setup = function(c)
        if opts.layouts then c.world.layouts = opts.layouts end
        if opts.setup then opts.setup(c) end
    end })
end

-- The panel's buttons, by label.
local function action(PE, label)
    for _, o in ipairs(PE:GetModule("layout").options) do
        if o.label == label then return o.action end
    end
    error("no layout button called " .. label)
end
local GAMEPAD, BACK, INSTALL = "Use Blizzard's Gamepad layout", "Go back to my previous layout", "Install the handheld layout"

local function sets(c) return c:callsTo("C_EditMode.SetActiveLayout") end
local function saves(c) return c:callsTo("C_EditMode.SaveLayouts") end
local function lines(c) return T.chatLines(c) end
local function reloadKeys(PE)
    local out = {}
    for _, r in ipairs(PE.reloadReasons) do out[#out + 1] = r.key end
    return out
end

---------------------------------------------------------------------------
-- Gamepad layout
---------------------------------------------------------------------------

-- DECISIONS "Layout": "The Gamepad layout button refuses unless 'Enable Gamepad UI' is on";
-- Layout.lua DoGamepad -> StyleReason ("plain message").
test("layout: the Gamepad layout button refuses with a plain message when the Gamepad UI is off", function()
    local c, PE = newLayout({ gamepadUI = false })
    action(PE, GAMEPAD)()
    eq(#sets(c), 0, "the layout was switched")
    eq(#saves(c), 0)
    eq(c.world.layouts.activeLayout, 1)
    eq(lines(c), { "Turn on \"Enable Gamepad UI\" in the game's options (Gamepad) first, then tap this again." })
    eq(PE.reloadReasons, {}, "asked for a reload after a refusal")
    c:assertClean("refusal")
end)

-- DECISIONS "Layout": "Every layout switch asks for a reload afterwards"; Layout.lua DoGamepad,
-- Activate, Finish. The game numbers presets first: Gamepad = Enum.EditModePresetLayouts.Gamepad + 1.
test("layout: with the Gamepad UI on, the switch calls SetActiveLayout once with the Gamepad preset and asks for a reload", function()
    local c, PE = newLayout({ gamepadUI = true })
    action(PE, GAMEPAD)()
    local calls = sets(c)
    eq(#calls, 1)
    eq(calls[1].args[1], GAMEPAD_INDEX)
    eq(c.world.layouts.activeLayout, GAMEPAD_INDEX)
    eq(lines(c), { "Now using Blizzard's Gamepad layout." })
    eq(reloadKeys(PE), { "layout" })
    eq(PE.reloadReasons[1].reason, "Reload to finish changing the screen layout.")
    c:assertClean("gamepad layout")
end)

-- Layout.lua DoGamepad: "already in use" writes nothing and asks for no reload.
test("layout: the Gamepad layout button does nothing when that layout is already in use", function()
    local c, PE = newLayout({ gamepadUI = true, layouts = { layouts = {}, activeLayout = GAMEPAD_INDEX } })
    action(PE, GAMEPAD)()
    eq(#sets(c), 0)
    eq(lines(c), { "Blizzard's Gamepad layout is already in use." })
    eq(PE.reloadReasons, {})
end)

-- Layout.lua Do: EditModeOpen -> "Close Edit Mode first"; nothing is changed.
test("layout: with Edit Mode open nothing is switched", function()
    local c, PE = newLayout({ gamepadUI = true })
    c.env.EditModeManagerFrame:Show()
    action(PE, GAMEPAD)()
    eq(#sets(c), 0)
    eq(lines(c), { "Close Edit Mode first, then tap this again." })
end)

-- Layout.lua Request: in combat "This will be done when the fight is over." and RunOutOfCombat.
test("layout: a switch asked for in combat waits and is done once when the fight ends", function()
    local c, PE = newLayout({ gamepadUI = true })
    c:enterCombat()
    action(PE, GAMEPAD)()
    c:advance(3)
    eq(#sets(c), 0, "switched during combat")
    eq(lines(c), { "This will be done when the fight is over." })
    c:leaveCombat()
    eq(#sets(c), 1)
    eq(c.world.layouts.activeLayout, GAMEPAD_INDEX)
    eq(reloadKeys(PE), { "layout" })
end)

---------------------------------------------------------------------------
-- Back
---------------------------------------------------------------------------

-- Layout.lua header A ("Go back to my previous layout"), DoGamepad (RememberPrevious), DoBack.
-- The earlier layout is a saved one made for the Gamepad UI (a mouse layout could not be used again
-- while the Gamepad UI is on, so none is remembered; see the next test).
test("layout: back returns to the layout that was active before the switch", function()
    local c, PE = newLayout({ gamepadUI = true, layouts = { layouts = { saved("My handheld", 1, 1) }, activeLayout = PRESETS + 1 } })
    action(PE, GAMEPAD)()
    eq(c.world.layouts.activeLayout, GAMEPAD_INDEX)
    PE:GetModule("layout"):CancelReload()          -- clear the first switch's request, so the next one proves the second
    eq(reloadKeys(PE), {})
    action(PE, BACK)()
    eq(reloadKeys(PE), { "layout" }, "going back asked for no reload")
    local calls = sets(c)
    eq(#calls, 2)
    eq(calls[2].args[1], PRESETS + 1)
    eq(c.world.layouts.activeLayout, PRESETS + 1)
    eq(lines(c), { "Now using Blizzard's Gamepad layout.", "Back to \"My handheld\"." })
    c:assertClean("back")
end)

-- Layout.lua RememberPrevious: "Never offer a way back that could only refuse".
test("layout: back with nothing remembered says so and writes nothing", function()
    local c, PE = newLayout({ gamepadUI = true })
    action(PE, BACK)()
    eq(#sets(c), 0)
    eq(lines(c), { "There is no earlier layout to go back to." })
end)

test("layout: back to a layout that was deleted since says so and writes nothing", function()
    local c, PE = newLayout({ gamepadUI = true, layouts = { layouts = { saved("My handheld", 1, 1) }, activeLayout = PRESETS + 1 } })
    action(PE, GAMEPAD)()
    c.world.layouts = { layouts = {}, activeLayout = GAMEPAD_INDEX }     -- the player deleted it in Edit Mode
    action(PE, BACK)()
    eq(#sets(c), 1, "only the first switch wrote")
    eq(lines(c)[2], "Your earlier layout no longer exists, so there is nothing to go back to.")
end)

---------------------------------------------------------------------------
-- Installing the bundled layout
---------------------------------------------------------------------------

-- The addon with one line changed (a bundled layout string), as a folder of links to the real files.
local function withBundled(fn)
    local dir = os.tmpname()
    os.remove(dir)
    dir = dir .. ".pe-layout"
    assert(os.execute("mkdir -p '" .. dir .. "' && for f in '" .. T.addonDir .. "'/*; do ln -s \"$f\" '" .. dir .. "'/; done"))
    local src = assert(io.open(T.addonDir .. "/Layout.lua", "rb")):read("*a")
    local patched, n = src:gsub("local BUNDLED_LAYOUT = nil", 'local BUNDLED_LAYOUT = "1 2 3 placeholder"', 1)
    assert(n == 1, "Layout.lua no longer has 'local BUNDLED_LAYOUT = nil'; update this test")
    os.remove(dir .. "/Layout.lua")
    local f = assert(io.open(dir .. "/Layout.lua", "wb"))
    f:write(patched)
    f:close()
    local ok, err = pcall(fn, dir)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then error(err, 0) end
end

local IMPORTED = { layoutName = "Imported", layoutType = 0, systems = { { system = 1 } } }

local function newInstall(dir, layouts)
    return newLayout({ addonDir = dir, layouts = layouts, setup = function(c) c.world.layoutImport = IMPORTED end })
end

-- Layout.lua BUNDLED_LAYOUT = nil, Status: "No handheld layout saved yet" and no install button.
test("layout: with no bundled layout the panel says 'No handheld layout saved yet' and offers no install button", function()
    local c, PE = newLayout()
    local mod = PE:GetModule("layout")
    local status = mod.status(mod)
    eq(status[#status], "No handheld layout saved yet")
    eq(#mod.options, 2)
    for _, o in ipairs(mod.options) do check(o.label ~= INSTALL, "install button offered") end
    eq(#saves(c), 0)
end)

test("layout: installing a layout (none called Handheld yet) saves it once as 'Handheld', switches to it, asks for a reload", function()
    withBundled(function(dir)
        local c, PE = newInstall(dir)
        action(PE, INSTALL)()
        eq(#saves(c), 1)
        local layouts = c.world.layouts
        eq(#layouts.layouts, 1)
        eq(layouts.layouts[1].layoutName, "Handheld")
        eq(layouts.layouts[1].layoutType, 1, "an account-wide layout")
        eq(layouts.activeLayout, PRESETS + 1)
        eq(lines(c), { "The handheld layout is installed and in use." })
        eq(reloadKeys(PE), { "layout" })
        c:assertClean("install")
    end)
end)

-- DECISIONS "Layout": "Installing over an existing 'Handheld' layout needs a second tap within 20
-- seconds." Layout.lua CONFIRM_SECONDS, DoInstall.
test("layout: installing over an existing Handheld layout: the first tap writes nothing and asks for a second", function()
    withBundled(function(dir)
        local c, PE = newInstall(dir, { layouts = { saved("Handheld", 1, 0) }, activeLayout = 1 })
        action(PE, INSTALL)()
        eq(#saves(c), 0)
        eq(#lines(c), 1)
        eq(lines(c)[1], "You already have a layout called Handheld. Tap again within 20 seconds to replace it with the built-in one.")
        eq(PE.reloadReasons, {})
    end)
end)

test("layout: a second tap 19 seconds after the first replaces Handheld (one write)", function()
    withBundled(function(dir)
        local c, PE = newInstall(dir, { layouts = { saved("Handheld", 1, 0) }, activeLayout = 1 })
        action(PE, INSTALL)()
        c:advance(19)
        action(PE, INSTALL)()
        eq(#saves(c), 1)
        eq(c.world.layouts.layouts[1].layoutName, "Handheld")
        eq(c.world.layouts.layouts[1].systems, IMPORTED.systems, "the saved layout is the built-in one")
        eq(c.world.layouts.activeLayout, PRESETS + 1)
        eq(lines(c)[2], "The handheld layout is installed and in use.")
    end)
end)

test("layout: a second tap 21 seconds after the first writes nothing and asks again", function()
    withBundled(function(dir)
        local c, PE = newInstall(dir, { layouts = { saved("Handheld", 1, 0) }, activeLayout = 1 })
        action(PE, INSTALL)()
        c:advance(21)
        action(PE, INSTALL)()
        eq(#saves(c), 0)
        eq(#lines(c), 2)
        eq(lines(c)[2]:sub(1, 36), "You already have a layout called Han")
        eq(c.world.layouts.layouts[1].systems, { {} }, "the player's own layout must be untouched")
    end)
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

-- Spec 2026-11-17-debug-log, row "Layout": each button pressed and what the game answered.
test("debug log: the Gamepad layout button writes the press, what was read and the answer", function()
    local c, PE = newLayout({ gamepadUI = true })
    PE:SetDebug(true)
    action(PE, GAMEPAD)()
    eq(debugLines(c, "layout"), {
        "button pressed: gamepad",
        "gamepad: 3 built-in, 0 saved, active 1 (built-in Modern)",
        "asked the game for layout 3, it now reports 3 (changed)",
        "answer: Now using Blizzard's Gamepad layout.",
    })
end)

return { known = KNOWN_FAILURES }
