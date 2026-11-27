-- Rules for the slim bars of Controller layout 0.17.0 (SlimBars.lua).
-- Source: docs/superpowers/specs/2026-11-24-0.17.0-slim-bars.md ("Where each bar is", "What
-- each bar shows", "When each bar shows", "In a fight", "The game's four frames", "The
-- switch", "Logging", "Tests"). Fresh client and addon per test; PE.SlimBars is started
-- directly (ControllerLayout calls it in the game; the last tests go through the layout).
-- The plan's numbers and the switch's row are in layout_test.lua.
--
-- These prove the logic against the stand-in client. Whether the game takes the calls the
-- same way (the see-through of its frames, hidden values in a real fight) only the device
-- can show.
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local W = 768 * 1280 / 720 -- the stand-in's screen in UI units

local TEXT_FIGHT = "waiting for the fight to end"
local TEXT_BUILD = "they could not be made"
local TEXT_ERROR = "they hit an error"
local CHAT_ERROR = "Slim bars turned off after an error; the game's own frames are back. Reload to try again."
local CHAT_ERROR_FIGHT = "Slim bars turned off after an error; the game's own frames come back when this fight ends. Reload to try again."

-- The plan's rectangles (layout_test.lua checks Plan.SlimRects against the same numbers):
-- { left, bottom, right, top } from the screen's bottom centre. 0.20.0: each side 18 further
-- out and 16 lower than 0.17.0 to 0.19.0 had it (the built-in arrangement, Plan.BASE_2;
-- before: player -498, 141, -218, 169 and so on).
local RECTS = {
    player = { -516, 125, -236, 153 },
    target = { 236, 125, 516, 153 },
    cast = { 236, 111, 516, 123 },
    pet = { -516, 156, -380, 173 },
    tot = { 380, 156, 516, 173 },
}
local GAME_FRAMES = { "PlayerFrame", "PetFrame", "TargetFrame" }
local GREEN, RED, GREY = { 0.10, 0.65, 0.20, 1 }, { 0.80, 0.15, 0.15, 1 }, { 0.50, 0.50, 0.50, 1 }

local function near(a, b, msg)
    check(type(a) == "number" and math.abs(a - b) < 1e-6, (msg or "number") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

-- A client with the game's unit frames and the addon loaded, the Debug log on. opts.setup(c)
-- runs before the load. Returns c, PE, Slim.
local function new(opts)
    opts = opts or {}
    local c, PE = T.new({ setup = function(c)
        c:addUnitFrames()
        if opts.setup then opts.setup(c) end
    end })
    PE:SetDebug(true)
    return c, PE, PE.SlimBars
end

-- A client with the bars started (checked).
local function started(opts)
    local c, PE, Slim = new(opts)
    local ok, why = Slim:Start()
    check(ok == true, "Start failed: " .. tostring(why))
    return c, PE, Slim
end

local function st(c, region) return c._state(region) end
local function bar(Slim, key) return Slim.view.bars[key] end
local function shown(c, region) return st(c, region).shown == true end
local function alphaOf(c, name) return st(c, c.env[name]).alpha end
local function totFrame(c) return rawget(c.env.TargetFrame, "totFrame") end

-- Every frame SlimBars.lua made.
local function slimFrames(c)
    local out = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == "SlimBars.lua" then out[#out + 1] = rec end
    end
    return out
end

-- The ones that can draw or take a tap (the three listening frames have no parent and no size).
local function drawnFrames(c)
    local out = {}
    for _, rec in ipairs(slimFrames(c)) do
        if rec.parent ~= nil then out[#out + 1] = rec end
    end
    return out
end

local function onUpdates(c)
    local n = 0
    for _, rec in ipairs(slimFrames(c)) do if rec.scripts.OnUpdate then n = n + 1 end end
    return n
end

local function eventsHeld(c)
    local n = 0
    for _, rec in ipairs(slimFrames(c)) do for _ in pairs(rec.events) do n = n + 1 end end
    return n
end

-- A region's rectangle from the screen's bottom centre: { left, bottom, right, top }.
local function rectOf(c, region)
    local l, r, t, b = c._rect(region)
    return { l - W / 2, b, r - W / 2, t }
end

local function sameRect(got, want, what)
    for i = 1, 4 do near(got[i], want[i], what .. " " .. i) end
end

-- The slim bars' debug lines (after "slim bars: "), in order.
local function notes(c)
    local out = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        local text = line:match("^%S+ ctrlLayout: slim bars: (.*)$")
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

-- Calls logged for a game frame's method, for example alphaCalls(c, "PlayerFrame", "SetAlpha").
local function frameCalls(c, name, method) return c:callsTo(name .. ":" .. method) end

-- What a widget was last given: the plain value, or what a secret one stands for (and that it was secret).
local function given(c, v)
    if c.world.secrets[v] then return c.secretValue[v], true end
    return v, false
end

local function setTarget(c, fields)
    c.world.units.target = fields
    c:fire("PLAYER_TARGET_CHANGED")
end

local function kobold(extra)
    local u = { name = "Kobold", level = 7, health = 80, healthMax = 120, power = 30, powerMax = 60, powerToken = "MANA", attackable = true }
    for k, v in pairs(extra or {}) do u[k] = v end
    return u
end

---------------------------------------------------------------------------
-- Off does nothing
---------------------------------------------------------------------------

test("slim: nothing is made, registered or called before Start", function()
    local c, PE, Slim = new()
    eq(#slimFrames(c), 0, "frames made at load")
    eq(#T.gameCalls(c), 0, "game calls at load")
    eq(Slim:Status(), nil)
    eq(Slim.view.cast, nil)
    for _, name in ipairs(GAME_FRAMES) do eq(alphaOf(c, name), 1, name) end
    eq(#c:_eventOrder("UNIT_HEALTH"), 0)
    eq(#c:_eventOrder("PLAYER_TARGET_CHANGED"), 0)
    c.world.units.target = kobold()
    c:fire("PLAYER_TARGET_CHANGED")
    c:advance(1)
    eq(#slimFrames(c), 0)
    eq(#notes(c), 0, "a debug line while off")
    -- Stop while never started: still nothing.
    Slim:Stop()
    eq(#slimFrames(c), 0)
    eq(#frameCalls(c, "PlayerFrame", "SetAlpha"), 0)
    c:assertClean()
end)

test("slim: with the layout on and the switch Off the file makes nothing and the game's frames stay as they are", function()
    local c, PE = T.new({ gamepadUI = true, setup = function(c)
        c:addUnitFrames()
        c.world.layouts = { layouts = {}, activeLayout = 3 }
    end })
    PE:SetDebug(true)
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    eq(PE:GetModule("ctrlLayout").opts.slim, 0)
    c.world.units.target = kobold()
    c:fire("PLAYER_TARGET_CHANGED")
    c:fire("PLAYER_ENTERING_WORLD")
    c:advance(0.5)
    eq(#slimFrames(c), 0)
    eq(#notes(c), 0)
    for _, name in ipairs(GAME_FRAMES) do
        eq(alphaOf(c, name), 1, name)
        eq(#frameCalls(c, name, "SetAlpha"), 0, name .. " SetAlpha")
        eq(#frameCalls(c, name, "GetAlpha"), 0, name .. " GetAlpha")
    end
    eq(#c:callsTo("TargetFrame.totFrame:SetAlpha"), 0)
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    eq(#slimFrames(c), 0)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Start: the bars and the game's frames
---------------------------------------------------------------------------

test("slim: Start places the five bars on the plan's numbers, in the middle layer, and shows the player's", function()
    local c, PE, Slim = started()
    eq(Slim:Status(), nil)
    for _, key in ipairs({ "player", "pet", "target", "tot" }) do
        local b = bar(Slim, key)
        check(b ~= nil, "no " .. key .. " bar")
        sameRect(rectOf(c, b.frame), RECTS[key], key .. " bar")
        eq(b.frame:GetFrameStrata(), "MEDIUM", key)
        near(b.frame:GetEffectiveScale(), 1, key .. " scale")
        eq(st(c, b.frame).mouse, nil, key .. " bar takes the mouse")
        local point, rel, relPoint = b.frame:GetPoint(1)
        eq({ point, rel == c.UIParent, relPoint }, { "BOTTOMLEFT", true, "BOTTOM" }, key .. " anchor")
    end
    sameRect(rectOf(c, Slim.view.cast.frame), RECTS.cast, "cast bar")
    eq(shown(c, bar(Slim, "player").frame), true)
    check(bar(Slim, "player").frame:IsVisible(), "the player bar is not visible")
    -- No pet, no target: the other four hidden.
    for _, key in ipairs({ "pet", "target", "tot" }) do eq(shown(c, bar(Slim, key).frame), false, key) end
    eq(shown(c, Slim.view.cast.frame), false)
    -- Inside a main bar: 1 border, power 6, 1 line, health 19, 1 border; 1 in from each side.
    local p = bar(Slim, "player")
    sameRect(rectOf(c, p.power), { -515, 126, -237, 132 }, "power bar")
    sameRect(rectOf(c, p.health), { -515, 133, -237, 152 }, "health bar")
    local pet = bar(Slim, "pet")
    eq(pet.power, nil)
    eq(pet.level, nil)
    eq(pet.value, nil)
    sameRect(rectOf(c, pet.health), { -515, 157, -381, 172 }, "pet health bar")
    eq(st(c, p.health).barTexture, "Interface\\TargetingFrame\\UI-StatusBar")
    c:assertClean()
end)

test("slim: Start makes the game's four frames invisible with their own SetAlpha, after reading it, and nothing else of theirs is called", function()
    local c, PE, Slim = started()
    for _, name in ipairs(GAME_FRAMES) do
        eq(alphaOf(c, name), 0, name)
        eq(#frameCalls(c, name, "GetAlpha"), 1, name .. " GetAlpha")
        local sets = frameCalls(c, name, "SetAlpha")
        eq(#sets, 1, name .. " SetAlpha")
        eq(sets[1].args[1], 0, name .. " value")
    end
    eq(st(c, totFrame(c)).alpha, 0, "target of target")
    eq(#c:callsTo("TargetFrame.totFrame:SetAlpha"), 1)
    -- The read comes before the write.
    local order = {}
    for _, call in ipairs(c.calls) do
        if call.name == "PlayerFrame:GetAlpha" or call.name == "PlayerFrame:SetAlpha" then order[#order + 1] = call.name end
    end
    eq(order, { "PlayerFrame:GetAlpha", "PlayerFrame:SetAlpha" })
    -- None of the five methods Edit Mode replaces with Lua was called, and no key was written:
    -- the stand-in records either as an error.
    eq(#c.errors, 0)
    -- The frames are left as they are otherwise: shown, where they were.
    eq(c.env.PlayerFrame:IsShown(), true)
    eq({ c.env.PlayerFrame:GetPoint(1) }, { "BOTTOMRIGHT", c.UIParent, "BOTTOM", -395, 56 })
    eq(#c:callsTo("hooksecurefunc") - 2, 0, "a hook was made") -- the round button's two world map hooks only
    c:assertClean()
end)

test("slim: the debug log says what started, where each bar is and what happened to each game frame", function()
    local c, PE, Slim = started()
    local lines = notes(c)
    eq(lines[1], "on (slim=0, Spell panel size 100%)")
    eq(noted(c, "placed the player bar: BOTTOMLEFT on the screen's bottom middle, x -516.0 y 125.0, 280.0 by 28.0, scale 1"), 1)
    eq(noted(c, "placed the target bar: BOTTOMLEFT on the screen's bottom middle, x 236.0 y 125.0, 280.0 by 28.0, scale 1"), 1)
    eq(noted(c, "placed the pet bar: BOTTOMLEFT on the screen's bottom middle, x -516.0 y 156.0, 136.0 by 17.0, scale 1"), 1)
    eq(noted(c, "placed the target of target bar: BOTTOMLEFT on the screen's bottom middle, x 380.0 y 156.0, 136.0 by 17.0, scale 1"), 1)
    eq(noted(c, "placed the cast bar: BOTTOMLEFT on the screen's bottom middle, x 236.0 y 111.0, 280.0 by 12.0, scale 1"), 1)
    for _, what in ipairs({ "player", "pet", "target", "target of target" }) do
        eq(noted(c, "the game's " .. what .. " frame made invisible (its see-through was 1.00)"), 1, what)
        eq(notedLike(c, "^tap guard over the game's " .. what .. " frame: BOTTOMLEFT x "), 1, what .. " guard")
    end
    eq(noted(c, "player bar shown"), 1)
    eq(noted(c, "pet bar hidden: no pet"), 1)
    eq(noted(c, "target bar hidden: no target"), 1)
    eq(noted(c, "target of target bar hidden: no target"), 1)
    for _, l in ipairs(lines) do check(#l <= 150, "a line is too long for the log: " .. l) end
end)

test("slim: bars that cannot be made leave the game's frames showing, and are not tried again", function()
    local c, PE, Slim = new({ setup = function(c) c.world.noStatusBars = true end })
    local ok, why = Slim:Start()
    eq({ ok, why }, { false, TEXT_BUILD })
    eq(Slim:Status(), TEXT_BUILD)
    for _, name in ipairs(GAME_FRAMES) do
        eq(alphaOf(c, name), 1, name)
        eq(#frameCalls(c, name, "SetAlpha"), 0, name)
    end
    for _, rec in ipairs(drawnFrames(c)) do check(not rec.frame:IsVisible(), "a frame of the bars shows") end
    eq(eventsHeld(c), 0)
    check(#PE.errors >= 1, "the failure was not logged")
    local made = #slimFrames(c)
    eq({ Slim:Start() }, { false, TEXT_BUILD })
    eq(#slimFrames(c), made, "built again")
end)

test("slim: a game frame that is missing is said in the log and the rest still starts", function()
    local c, PE, Slim = new({ setup = function(c) rawset(c.env, "PetFrame", nil) end })
    eq(Slim:Start(), true)
    eq(noted(c, "the game's pet frame was not found: it stays as it is"), 1)
    eq(alphaOf(c, "PlayerFrame"), 0)
    eq(alphaOf(c, "TargetFrame"), 0)
    eq(noted(c, "no tap guard over the game's pet frame: its place cannot be read"), 1)
    Slim:Stop()
    eq(alphaOf(c, "PlayerFrame"), 1)
    c:assertClean()
end)

test("slim: Start again while running makes nothing new; a frame the game showed again goes invisible again", function()
    local c, PE, Slim = started()
    local frames, events = #slimFrames(c), eventsHeld(c)
    eq(Slim:Start(), true)
    eq(#slimFrames(c), frames)
    eq(eventsHeld(c), events)
    eq(#frameCalls(c, "PlayerFrame", "SetAlpha"), 1, "set again though still invisible")
    st(c, c.env.TargetFrame).alpha = 1
    eq(Slim:Start(), true)
    eq(alphaOf(c, "TargetFrame"), 0)
    eq(noted(c, "the game's target frame made invisible again (its see-through was 1.00)"), 1)
    -- And when the world loads again.
    st(c, c.env.PlayerFrame).alpha = 0.5
    c:fire("PLAYER_ENTERING_WORLD")
    eq(alphaOf(c, "PlayerFrame"), 0)
    eq(noted(c, "the game's player frame made invisible again (its see-through was 0.50)"), 1)
    -- Stop still puts back what was read at the very first start.
    Slim:Stop()
    eq(alphaOf(c, "PlayerFrame"), 1)
    eq(alphaOf(c, "TargetFrame"), 1)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- What the bars show
---------------------------------------------------------------------------

test("slim: the player bar shows health, the health number, the level, the name and the power", function()
    local c, PE, Slim = started()
    local p = bar(Slim, "player")
    eq({ st(c, p.health).barMin, st(c, p.health).barMax, st(c, p.health).barValue }, { 0, 100, 100 })
    eq(p.value:GetText(), "100")
    eq(p.level:GetText(), "10")
    eq(p.name:GetText(), "Tester")
    eq({ st(c, p.power).barMin, st(c, p.power).barMax, st(c, p.power).barValue }, { 0, 100, 50 })
    eq(st(c, p.health).barColor, GREEN)
    eq(st(c, p.power).barColor, { 0.20, 0.40, 1.00, 1 })
end)

test("slim: the player bar follows the game's events, and a health or power update writes no debug line", function()
    local c, PE, Slim = started()
    local p = bar(Slim, "player")
    local lines = #notes(c)
    local u = c.world.units.player
    u.health = 40
    c:fire("UNIT_HEALTH", "player")
    eq(st(c, p.health).barValue, 40)
    eq(p.value:GetText(), "40")
    u.healthMax = 150
    c:fire("UNIT_MAXHEALTH", "player")
    eq(st(c, p.health).barMax, 150)
    u.power = 10
    c:fire("UNIT_POWER_UPDATE", "player", "MANA")
    eq(st(c, p.power).barValue, 10)
    u.powerMax = 200
    c:fire("UNIT_MAXPOWER", "player", "MANA")
    eq(st(c, p.power).barMax, 200)
    for i = 1, 20 do
        u.health = 40 + i
        c:fire("UNIT_HEALTH", "player")
        c:fire("UNIT_POWER_UPDATE", "player", "MANA")
    end
    eq(#notes(c), lines, "a debug line for a health or power update")
    -- The power's kind changes (a druid shifting): the colour follows, only then.
    u.powerToken = "RAGE"
    c:fire("UNIT_POWER_UPDATE", "player", "RAGE")
    eq(st(c, p.power).barColor, { 0.20, 0.40, 1.00, 1 })
    c:fire("UNIT_DISPLAYPOWER", "player")
    eq(st(c, p.power).barColor, { 1, 0, 0, 1 })
    u.powerToken = "ENERGY"
    c:fire("UNIT_DISPLAYPOWER", "player")
    eq(st(c, p.power).barColor, { 1, 1, 0, 1 })
    u.powerToken = "FOCUS"
    c:fire("UNIT_DISPLAYPOWER", "player")
    eq(st(c, p.power).barColor, { 1, 0.5, 0.25, 1 })
    -- The name and the level.
    c.world.playerName = "Renamed"
    c:fire("UNIT_NAME_UPDATE", "player")
    eq(p.name:GetText(), "Renamed")
    c:fire("PLAYER_LEVEL_UP", 11)
    eq(p.level:GetText(), "11")
    u.level = 12
    c:fire("UNIT_LEVEL", "player")
    eq(p.level:GetText(), "12")
    -- Another unit's event is not ours.
    u.health = 1
    c:fire("UNIT_HEALTH", "party1")
    eq(st(c, p.health).barValue, 60)
    c:assertClean()
end)

test("slim: nothing ticks: no OnUpdate on any of the bars' frames while no cast shows, and no timer", function()
    local c, PE, Slim = started()
    setTarget(c, kobold())
    c.world.units.pet = { name = "Cat", health = 50, healthMax = 50 }
    c:fire("UNIT_PET", "player")
    eq(onUpdates(c), 0)
    local timers = c.stats.addonTimers
    c:advance(5)
    eq(c.stats.addonTimers, timers, "a timer ran")
    eq(onUpdates(c), 0)
end)

---------------------------------------------------------------------------
-- Values the game hides in a fight
---------------------------------------------------------------------------

test("slim: hidden health, power and names go into the widgets as they came", function()
    local c, PE, Slim = started()
    c.world.unitSecret = true
    c.world.units.player.health = 37
    c:fire("UNIT_HEALTH", "player")
    local p = bar(Slim, "player")
    eq({ given(c, st(c, p.health).barValue) }, { 37, true })
    eq({ given(c, st(c, p.health).barMax) }, { 100, true })
    eq(st(c, p.health).barMin, 0)
    eq({ given(c, st(c, p.value).text) }, { 37, true })
    c:fire("UNIT_POWER_UPDATE", "player", "MANA")
    eq({ given(c, st(c, p.power).barValue) }, { 50, true })
    eq({ given(c, st(c, p.power).barMax) }, { 100, true })
    -- A target, its name hidden too.
    setTarget(c, kobold())
    local t = bar(Slim, "target")
    eq(shown(c, t.frame), true)
    eq({ given(c, st(c, t.name).text) }, { "Kobold", true })
    eq({ given(c, st(c, t.health).barValue) }, { 80, true })
    eq({ given(c, st(c, t.health).barMax) }, { 120, true })
    eq({ given(c, st(c, t.value).text) }, { 80, true })
    eq(t.level:GetText(), "7")
    eq(st(c, t.health).barColor, RED)
    -- The pet and the target's target.
    c.world.units.pet = { name = "Cat", health = 9, healthMax = 50 }
    c:fire("UNIT_PET", "player")
    eq({ given(c, st(c, bar(Slim, "pet").health).barValue) }, { 9, true })
    eq({ given(c, st(c, bar(Slim, "pet").name).text) }, { "Cat", true })
    c.world.units.targettarget = { name = "Cat", health = 9, healthMax = 50 }
    c:fire("UNIT_TARGET", "target")
    eq({ given(c, st(c, bar(Slim, "tot").health).barValue) }, { 9, true })
    -- Nothing raised: no value was added, joined, compared or converted on the way.
    eq(#PE.errors, 0)
    eq(Slim:Status(), nil)
    c:assertClean()
end)

test("slim: a hidden cast goes into the cast bar as it came: the two times as its ends, our clock as its value", function()
    local c, PE, Slim = started()
    c.world.unitSecret = true
    local from = c.now * 1000
    setTarget(c, kobold({ cast = { text = "Fireball", startMs = from, endMs = from + 2500 } }))
    local cast = Slim.view.cast
    eq(shown(c, cast.frame), true)
    eq({ given(c, st(c, cast.bar).barMin) }, { from, true })
    eq({ given(c, st(c, cast.bar).barMax) }, { from + 2500, true })
    eq({ given(c, st(c, cast.text).text) }, { "Fireball", true })
    near(st(c, cast.bar).barValue, c.now * 1000, "the bar's value is our clock")
    c:advance(0.3)
    near(st(c, cast.bar).barValue, c.now * 1000, "the bar's value after 0.3 s")
    eq(#PE.errors, 0)
    c:assertClean()
end)

test("slim: a widget that refuses hidden values is said once in the log, by name, and nothing breaks", function()
    local c, PE, Slim = started()
    c.world.unitSecret = true
    c.world.barRefusesSecrets = true
    c.world.textRefusesSecrets = true
    for i = 1, 5 do
        c.world.units.player.health = 30 + i
        c:fire("UNIT_HEALTH", "player")
        c:fire("UNIT_POWER_UPDATE", "player", "MANA")
    end
    eq(notedLike(c, "^StatusBar:SetMinMaxValues %(health%) failed: "), 1)
    eq(notedLike(c, "^StatusBar:SetValue %(health%) failed: "), 1)
    eq(notedLike(c, "^FontString:SetText %(the health number%) failed: "), 1)
    eq(notedLike(c, "^StatusBar:SetValue %(power%) failed: "), 1)
    eq(#PE.errors, 0, "a refusal was counted as an error")
    eq(Slim:Status(), nil)
    -- A cast whose times the bar refuses: no bar, said once.
    local from = c.now * 1000
    setTarget(c, kobold({ cast = { text = "Fireball", startMs = from, endMs = from + 2500 } }))
    eq(shown(c, Slim.view.cast.frame), false)
    eq(notedLike(c, "^StatusBar:SetMinMaxValues %(a cast's times%) failed: "), 1)
    eq(onUpdates(c), 0)
    c:assertClean()
end)

test("slim: a game function that is missing or raises is said once in the log, by name", function()
    local c, PE, Slim = new({ setup = function(c)
        rawset(c.env, "UnitPowerType", nil)
        c.world.unitCallFails.UnitHealth = true
    end })
    eq(Slim:Start(), true)
    for _ = 1, 4 do c:fire("UNIT_HEALTH", "player") end
    c:fire("UNIT_DISPLAYPOWER", "player")
    eq(noted(c, "UnitPowerType is missing on this client"), 1)
    eq(notedLike(c, "^UnitHealth failed: "), 1)
    eq(#PE.errors, 0)
    eq(Slim:Status(), nil)
    -- The rest still works.
    eq(bar(Slim, "player").name:GetText(), "Tester")
    eq(st(c, bar(Slim, "player").power).barValue, 50)
end)

test("slim: an answer that should never be hidden but is: the bar keeps its state and the log says which call", function()
    local c, PE, Slim = started()
    setTarget(c, kobold())
    eq(shown(c, bar(Slim, "target").frame), true)
    c.world.unitAnswerHidden.UnitExists = true
    c.world.units.target = nil
    c:fire("PLAYER_TARGET_CHANGED")
    eq(shown(c, bar(Slim, "target").frame), true, "the bar changed on an answer it could not read")
    eq(noted(c, "UnitExists's answer is hidden: a bar keeps its state"), 1)
    c.world.unitAnswerHidden.UnitExists = nil
    -- (the bar that stayed read "cannot be attacked" for the target that is gone: green)
    eq(st(c, bar(Slim, "target").health).barColor, GREEN)
    c.world.unitAnswerHidden.UnitCanAttack = true
    setTarget(c, kobold())
    eq(st(c, bar(Slim, "target").health).barColor, GREEN, "the colour changed on an answer it could not read")
    eq(noted(c, "UnitCanAttack's answer is hidden: the target bar keeps its colour"), 1)
    -- A hidden level is passed on, not tested.
    c.world.unitAnswerHidden.UnitLevel = true
    c:fire("UNIT_LEVEL", "target")
    eq({ given(c, st(c, bar(Slim, "target").level).text) }, { 7, true })
    eq(#PE.errors, 0)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Pet, target, target of target
---------------------------------------------------------------------------

test("slim: the pet bar shows while there is a pet, and the log says why it changes", function()
    local c, PE, Slim = started()
    local pet = bar(Slim, "pet")
    eq(shown(c, pet.frame), false)
    c.world.units.pet = { name = "Cat", health = 45, healthMax = 50 }
    c:fire("UNIT_PET", "player")
    eq(shown(c, pet.frame), true)
    eq(pet.name:GetText(), "Cat")
    eq({ st(c, pet.health).barMax, st(c, pet.health).barValue }, { 50, 45 })
    eq(st(c, pet.health).barColor, GREEN)
    eq(noted(c, "pet bar shown: a pet is out"), 1)
    c.world.units.pet.health = 20
    c:fire("UNIT_HEALTH", "pet")
    eq(st(c, pet.health).barValue, 20)
    -- The same event again changes nothing and says nothing.
    c:fire("UNIT_PET", "player")
    eq(noted(c, "pet bar shown: a pet is out"), 1)
    c.world.units.pet = nil
    c:fire("UNIT_PET", "player")
    eq(shown(c, pet.frame), false)
    eq(noted(c, "pet bar hidden: no pet"), 2) -- at the start and now
    -- A health event for a pet that is gone is ignored.
    c:fire("UNIT_HEALTH", "pet")
    c:assertClean()
end)

test("slim: the target bar shows while there is a target: red for an enemy, grey when tagged, green for a friend", function()
    local c, PE, Slim = started()
    local t = bar(Slim, "target")
    setTarget(c, kobold())
    eq(shown(c, t.frame), true)
    eq(noted(c, "target bar shown: a target"), 1)
    eq(t.name:GetText(), "Kobold")
    eq(t.level:GetText(), "7")
    eq(t.value:GetText(), "80")
    eq({ st(c, t.health).barMax, st(c, t.health).barValue }, { 120, 80 })
    eq({ st(c, t.power).barMax, st(c, t.power).barValue }, { 60, 30 })
    eq(st(c, t.health).barColor, RED)
    c.world.units.target.health = 10
    c:fire("UNIT_HEALTH", "target")
    eq(st(c, t.health).barValue, 10)
    c.world.units.target.tapped = true
    c:fire("UNIT_FACTION", "target")
    eq(st(c, t.health).barColor, GREY)
    -- Straight to another target: no "shown" line again.
    setTarget(c, { name = "Guard", level = -1, health = 500, healthMax = 500, power = 0, powerMax = 0 })
    eq(st(c, t.health).barColor, GREEN)
    eq(t.level:GetText(), "??")
    eq(t.name:GetText(), "Guard")
    eq(noted(c, "target bar shown: a target"), 1)
    setTarget(c, nil)
    eq(shown(c, t.frame), false)
    eq(noted(c, "target bar hidden: no target"), 2)
    c:assertClean()
end)

test("slim: the target of target bar comes and goes with the target's target, and its health follows the others' events", function()
    local c, PE, Slim = started()
    local tot = bar(Slim, "tot")
    setTarget(c, kobold())
    eq(shown(c, tot.frame), false)
    -- It was hidden already (no target): no line for staying hidden.
    eq(noted(c, "target of target bar hidden: the target has no target"), 0)
    c.world.units.targettarget = { name = "Tester", health = 100, healthMax = 100 }
    c:fire("UNIT_TARGET", "target")
    eq(shown(c, tot.frame), true)
    eq(tot.name:GetText(), "Tester")
    eq(noted(c, "target of target bar shown: the target has a target"), 1)
    eq(st(c, tot.health).barColor, GREEN)
    -- The game sends no health event for it: it is read again with the player's.
    c.world.units.targettarget.health = 61
    c.world.units.player.health = 61
    c:fire("UNIT_HEALTH", "player")
    eq(st(c, tot.health).barValue, 61)
    c.world.units.targettarget.health = 33
    c:fire("UNIT_HEALTH", "target")
    eq(st(c, tot.health).barValue, 33)
    -- An enemy as the target's target is red.
    c.world.units.targettarget = { name = "Wolf", health = 5, healthMax = 9, attackable = true }
    c:fire("UNIT_TARGET", "target")
    eq(st(c, tot.health).barColor, RED)
    c.world.units.targettarget = nil
    c:fire("UNIT_TARGET", "target")
    eq(shown(c, tot.frame), false)
    eq(noted(c, "target of target bar hidden: the target has no target"), 1)
    -- No target at all: hidden, and for that reason.
    c.world.units.targettarget = { name = "Tester", health = 100, healthMax = 100 }
    c:fire("UNIT_TARGET", "target")
    eq(shown(c, tot.frame), true)
    c.world.units.targettarget = nil
    setTarget(c, nil)
    eq(shown(c, tot.frame), false)
    eq(noted(c, "target of target bar hidden: no target"), 2)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The cast bar
---------------------------------------------------------------------------

local function casting(c, text, seconds, extra)
    local from = c.now * 1000
    local k = { text = text, startMs = from, endMs = from + seconds * 1000 }
    for key, v in pairs(extra or {}) do k[key] = v end
    return k
end

test("slim: a cast shows the bar with its name, fills with our clock, and hides when it finishes", function()
    local c, PE, Slim = started()
    local cast = Slim.view.cast
    setTarget(c, kobold())
    eq(shown(c, cast.frame), false)
    eq(onUpdates(c), 0)
    local k = casting(c, "Fireball", 2)
    c.world.units.target.cast = k
    c:fire("UNIT_SPELLCAST_START", "target", "Cast-3-0", 133)
    eq(shown(c, cast.frame), true)
    eq(cast.text:GetText(), "Fireball")
    eq({ st(c, cast.bar).barMin, st(c, cast.bar).barMax }, { k.startMs, k.endMs })
    near(st(c, cast.bar).barValue, c.now * 1000, "value at the start")
    eq(onUpdates(c), 1, "the one OnUpdate, on the cast bar")
    check(st(c, cast.bar).scripts.OnUpdate ~= nil, "the OnUpdate is not on the cast bar's own frame")
    eq(noted(c, "cast bar shown: the target is casting"), 1)
    c:advance(1)
    near(st(c, cast.bar).barValue, c.now * 1000, "value after 1 s")
    eq(shown(c, cast.frame), true)
    -- Pushed back: the new end.
    k.endMs = k.endMs + 500
    c:fire("UNIT_SPELLCAST_DELAYED", "target", "Cast-3-0", 133)
    eq(st(c, cast.bar).barMax, k.endMs)
    eq(noted(c, "cast bar shown: the target is casting"), 1)
    -- Finished.
    c.world.units.target.cast = nil
    c:fire("UNIT_SPELLCAST_STOP", "target", "Cast-3-0", 133)
    eq(shown(c, cast.frame), false)
    eq(onUpdates(c), 0, "the OnUpdate stays after the cast")
    eq(noted(c, "cast bar hidden: the cast ended"), 1)
    c:assertClean()
end)

test("slim: an interrupted cast hides the bar and says so; a failed other spell does not end a cast that still goes", function()
    local c, PE, Slim = started()
    local cast = Slim.view.cast
    setTarget(c, kobold({ cast = casting(c, "Heal", 3) }))
    eq(shown(c, cast.frame), true)
    -- The game says "failed" for something else while the cast still goes: the bar stays.
    c:fire("UNIT_SPELLCAST_FAILED", "target", "Cast-3-9", 99)
    eq(shown(c, cast.frame), true)
    c.world.units.target.cast = nil
    c:fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-3-0", 133)
    eq(shown(c, cast.frame), false)
    eq(noted(c, "cast bar hidden: interrupted"), 1)
    eq(onUpdates(c), 0)
    -- A cast that fails outright.
    c.world.units.target.cast = casting(c, "Heal", 3)
    c:fire("UNIT_SPELLCAST_START", "target")
    c.world.units.target.cast = nil
    c:fire("UNIT_SPELLCAST_FAILED", "target")
    eq(shown(c, cast.frame), false)
    eq(noted(c, "cast bar hidden: the cast failed"), 1)
    c:assertClean()
end)

test("slim: a channel shows and ends; a cast whose end the game never tells is noticed within half a second", function()
    local c, PE, Slim = started()
    local cast = Slim.view.cast
    setTarget(c, kobold())
    local k = casting(c, "Drain Life", 4, { channel = true })
    c.world.units.target.cast = k
    c:fire("UNIT_SPELLCAST_CHANNEL_START", "target")
    eq(shown(c, cast.frame), true)
    eq(cast.text:GetText(), "Drain Life")
    eq(noted(c, "cast bar shown: the target is channelling"), 1)
    k.endMs = k.endMs - 300
    c:fire("UNIT_SPELLCAST_CHANNEL_UPDATE", "target")
    eq(st(c, cast.bar).barMax, k.endMs)
    c.world.units.target.cast = nil
    c:fire("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    eq(shown(c, cast.frame), false)
    eq(noted(c, "cast bar hidden: the channel ended"), 1)
    -- No stop event at all.
    c.world.units.target.cast = casting(c, "Fireball", 2)
    c:fire("UNIT_SPELLCAST_START", "target")
    eq(shown(c, cast.frame), true)
    c.world.units.target.cast = nil
    c:advance(0.7)
    eq(shown(c, cast.frame), false)
    eq(noted(c, "cast bar hidden: the cast ended (no stop event came)"), 1)
    eq(onUpdates(c), 0)
    c:assertClean()
end)

test("slim: the cast bar follows the target: a new target in mid-cast, none, and a cast event with no target", function()
    local c, PE, Slim = started()
    local cast = Slim.view.cast
    setTarget(c, kobold({ cast = casting(c, "Fireball", 3) }))
    eq(shown(c, cast.frame), true)
    -- Another target that casts nothing.
    setTarget(c, kobold({ name = "Wolf" }))
    eq(shown(c, cast.frame), false)
    eq(noted(c, "cast bar hidden: the target changed"), 1)
    -- Another one already in mid-cast.
    setTarget(c, kobold({ name = "Mage", cast = casting(c, "Frostbolt", 3) }))
    eq(shown(c, cast.frame), true)
    eq(cast.text:GetText(), "Frostbolt")
    setTarget(c, nil)
    eq(shown(c, cast.frame), false)
    eq(noted(c, "cast bar hidden: no target"), 1)
    eq(onUpdates(c), 0)
    c:fire("UNIT_SPELLCAST_START", "target")
    eq(shown(c, cast.frame), false)
    -- A cast event for somebody else never reaches the bars.
    c.world.units.player.cast = casting(c, "Hearthstone", 10)
    c:fire("UNIT_SPELLCAST_START", "player")
    eq(shown(c, cast.frame), false)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The tap guards
---------------------------------------------------------------------------

test("slim: a tap guard of ours lies over each invisible frame while its bar shows, and takes the mouse", function()
    local c, PE, Slim = started()
    local guards = Slim.view.guards
    local frames = { player = c.env.PlayerFrame, pet = c.env.PetFrame, target = c.env.TargetFrame, tot = totFrame(c) }
    for key, game in pairs(frames) do
        local g = guards[key]
        check(g ~= nil, "no guard for " .. key)
        eq(st(c, g).mouse, true, key .. " guard does not take the mouse")
        eq(st(c, g).addonFile, "SlimBars.lua", key)
        eq(g:GetFrameStrata(), "MEDIUM", key)
        sameRect(rectOf(c, g), rectOf(c, game), key .. " guard")
        check(g:GetFrameLevel() < bar(Slim, key).frame:GetFrameLevel(), key .. " guard is not under the bars")
        eq(st(c, g).scripts.OnMouseDown, nil, key .. " guard has a click handler")
    end
    eq(shown(c, guards.player), true)
    for _, key in ipairs({ "pet", "target", "tot" }) do eq(shown(c, guards[key]), false, key) end
    setTarget(c, kobold())
    eq(shown(c, guards.target), true)
    eq(shown(c, guards.tot), false)
    c.world.units.targettarget = { name = "Tester", health = 1, healthMax = 1 }
    c:fire("UNIT_TARGET", "target")
    eq(shown(c, guards.tot), true)
    c.world.units.pet = { name = "Cat", health = 1, healthMax = 1 }
    c:fire("UNIT_PET", "player")
    eq(shown(c, guards.pet), true)
    c.world.units.targettarget = nil
    setTarget(c, nil)
    eq(shown(c, guards.target), false)
    eq(shown(c, guards.tot), false)
    Slim:Stop()
    for key in pairs(frames) do eq(shown(c, guards[key]), false, key .. " after Stop") end
    c:assertClean()
end)

test("slim: a game frame whose place cannot be read gets no guard, and the log says so", function()
    local c, PE, Slim = new({ setup = function(c) c._state(c.env.PetFrame).points = {} end })
    eq(Slim:Start(), true)
    eq(noted(c, "no tap guard over the game's pet frame: its place cannot be read"), 1)
    c.world.units.pet = { name = "Cat", health = 1, healthMax = 1 }
    c:fire("UNIT_PET", "player")
    eq(shown(c, bar(Slim, "pet").frame), true)
    eq(shown(c, Slim.view.guards.pet), false)
    eq(alphaOf(c, "PetFrame"), 0)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Stop, and fights
---------------------------------------------------------------------------

test("slim: Stop puts each game frame's see-through back as it was read, hides the bars and drops every event", function()
    local c, PE, Slim = new({ setup = function(c)
        c._state(c.env.TargetFrame).alpha = 0.8
    end })
    eq(Slim:Start(), true)
    setTarget(c, kobold({ cast = casting(c, "Fireball", 3) }))
    eq(alphaOf(c, "TargetFrame"), 0)
    check(eventsHeld(c) > 0, "no events while running")
    Slim:Stop()
    eq(alphaOf(c, "PlayerFrame"), 1)
    eq(alphaOf(c, "PetFrame"), 1)
    eq(alphaOf(c, "TargetFrame"), 0.8)
    eq(st(c, totFrame(c)).alpha, 1)
    eq(eventsHeld(c), 0)
    eq(onUpdates(c), 0)
    for _, rec in ipairs(drawnFrames(c)) do check(not rec.frame:IsVisible(), "a frame of the bars still shows") end
    eq(noted(c, "the game's 4 unit frames have their see-through back"), 1)
    eq(noted(c, "off: stopped"), 1)
    eq(Slim:Status(), nil)
    -- Events after Stop do nothing.
    c.world.units.player.health = 5
    c:fire("UNIT_HEALTH", "player")
    c:fire("PLAYER_TARGET_CHANGED")
    eq(st(c, bar(Slim, "player").health).barValue, 100)
    -- Stop twice is harmless; Start again works and says so again.
    Slim:Stop()
    eq(#frameCalls(c, "PlayerFrame", "SetAlpha"), 2)
    eq(Slim:Start(), true)
    eq(alphaOf(c, "TargetFrame"), 0)
    eq(st(c, bar(Slim, "player").health).barValue, 5)
    eq(shown(c, bar(Slim, "target").frame), true)
    eq(noted(c, "player bar shown"), 2)
    Slim:Stop()
    eq(alphaOf(c, "TargetFrame"), 0.8)
    c:assertClean()
end)

test("slim: in a fight nothing of the game's is called: Start refuses, Stop waits and the bars stay until it ends", function()
    local c, PE, Slim = new()
    c:enterCombat()
    eq({ Slim:Start() }, { false, TEXT_FIGHT })
    eq(Slim:Status(), TEXT_FIGHT)
    eq(#slimFrames(c), 0)
    eq(#frameCalls(c, "PlayerFrame", "SetAlpha"), 0)
    c:leaveCombat()
    eq(Slim:Start(), true)
    eq(Slim:Status(), nil)
    setTarget(c, kobold())
    local sets = #frameCalls(c, "PlayerFrame", "SetAlpha")
    c:enterCombat()
    Slim:Stop()
    eq(#frameCalls(c, "PlayerFrame", "SetAlpha"), sets, "the player frame was touched in a fight")
    eq(#c:callsTo("TargetFrame.totFrame:SetAlpha"), 1, "the target of target was touched in a fight")
    eq(alphaOf(c, "PlayerFrame"), 0)
    eq(shown(c, bar(Slim, "player").frame), true, "the bars went before the game's frames came back")
    eq(noted(c, "asked to stop in a fight: the bars stay until it ends"), 1)
    -- Still following the game meanwhile.
    c.world.units.target.health = 3
    c:fire("UNIT_HEALTH", "target")
    eq(st(c, bar(Slim, "target").health).barValue, 3)
    -- The world loading in a fight (a check of the game's frames) waits too.
    c:fire("PLAYER_ENTERING_WORLD")
    eq(#frameCalls(c, "PlayerFrame", "SetAlpha"), sets)
    Slim:Stop() -- asked twice: one line
    eq(noted(c, "asked to stop in a fight: the bars stay until it ends"), 1)
    c:leaveCombat()
    c:advance(0.1)
    for _, name in ipairs(GAME_FRAMES) do eq(alphaOf(c, name), 1, name) end
    eq(shown(c, bar(Slim, "player").frame), false)
    eq(eventsHeld(c), 0)
    eq(noted(c, "off: stopped (asked in a fight)"), 1)
    eq(#c.blocked, 0)
    c:assertClean()
end)

test("slim: Stop asked in a fight and Start again before it ran: the bars stay on", function()
    local c, PE, Slim = started()
    c:enterCombat()
    Slim:Stop()
    c.world.inCombat = false -- the lockdown is over, the queue has not run yet
    eq(Slim:Start(), true)
    c:fire("PLAYER_REGEN_ENABLED")
    c:advance(0.1)
    eq(alphaOf(c, "PlayerFrame"), 0)
    eq(shown(c, bar(Slim, "player").frame), true)
    check(eventsHeld(c) > 0, "the events were dropped")
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The safety net
---------------------------------------------------------------------------

-- Makes the player's power bar raise when it is coloured, and changes the power's kind n times.
local function breakIt(c, Slim, n)
    rawset(bar(Slim, "player").power, "SetStatusBarColor", function() error("boom") end)
    local kinds = { "RAGE", "ENERGY", "FOCUS", "RAGE" }
    for i = 1, n do
        c.world.units.player.powerToken = kinds[i]
        c:fire("UNIT_DISPLAYPOWER", "player")
    end
end

test("slim: three errors turn the bars off: the game's frames come back, chat and the status say so, Start refuses", function()
    local c, PE, Slim = started()
    breakIt(c, Slim, 2)
    eq(Slim:Status(), nil)
    eq(alphaOf(c, "PlayerFrame"), 0)
    breakIt(c, Slim, 3)
    eq(Slim:Status(), TEXT_ERROR)
    for _, name in ipairs(GAME_FRAMES) do eq(alphaOf(c, name), 1, name) end
    for _, rec in ipairs(drawnFrames(c)) do check(not rec.frame:IsVisible(), "a frame of the bars still shows") end
    eq(eventsHeld(c), 0)
    local lines = T.chatLines(c)
    eq(lines[#lines], CHAT_ERROR)
    eq(noted(c, "turned off after 3 errors"), 1)
    eq({ Slim:Start() }, { false, TEXT_ERROR })
    eq(alphaOf(c, "PlayerFrame"), 1)
    check(#PE.errors >= 1, "the errors were not logged")
end)

test("slim: the safety net in a fight hides our bars at once and brings the game's frames back when the fight ends", function()
    local c, PE, Slim = started()
    c:enterCombat()
    local sets = #frameCalls(c, "PlayerFrame", "SetAlpha")
    breakIt(c, Slim, 3)
    eq(Slim:Status(), TEXT_ERROR)
    eq(#frameCalls(c, "PlayerFrame", "SetAlpha"), sets, "the game's frame was touched in a fight")
    eq(alphaOf(c, "PlayerFrame"), 0)
    -- The bars go; the tap guards stay until the game's frames are back (tested further down).
    for _, key in ipairs({ "player", "pet", "target", "tot" }) do eq(shown(c, bar(Slim, key).frame), false, key .. " bar") end
    eq(shown(c, Slim.view.cast.frame), false)
    local lines = T.chatLines(c)
    eq(lines[#lines], CHAT_ERROR_FIGHT)
    c:leaveCombat()
    c:advance(0.1)
    for _, name in ipairs(GAME_FRAMES) do eq(alphaOf(c, name), 1, name) end
    eq(#c.blocked, 0)
end)

---------------------------------------------------------------------------
-- Older clients
---------------------------------------------------------------------------

test("slim: a client without RegisterUnitEvent still follows its units, and only them", function()
    local c, PE, Slim = new({ setup = function(c) c.typeMethods.Frame.RegisterUnitEvent = nil end })
    eq(Slim:Start(), true)
    local p = bar(Slim, "player")
    c.world.units.player.health = 12
    c:fire("UNIT_HEALTH", "player")
    eq(st(c, p.health).barValue, 12)
    c.world.units.player.health = 1
    c:fire("UNIT_HEALTH", "party1")
    c:fire("UNIT_HEALTH", "nameplate3")
    eq(st(c, p.health).barValue, 12)
    eq(#PE.errors, 0)
end)

---------------------------------------------------------------------------
-- With the layout
---------------------------------------------------------------------------

local function layoutClient(extra)
    local c, PE = T.new({ gamepadUI = true, setup = function(c)
        c:addUnitFrames()
        c.world.layouts = { layouts = {}, activeLayout = 3 }
        if extra then extra(c) end
    end })
    PE:SetDebug(true)
    return c, PE, PE.SlimBars
end

test("slim: with the switch On the layout starts the bars when it is placed and stops them when it goes off", function()
    local c, PE, Slim = layoutClient()
    PE:GetModule("ctrlLayout").opts.slim = 1
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    eq(alphaOf(c, "PlayerFrame"), 0)
    eq(shown(c, bar(Slim, "player").frame), true)
    eq(notes(c)[1], "on (slim=1, Spell panel size 100%)")
    eq(Slim:Status(), nil)
    -- Placed again (the world loads): nothing new.
    local frames = #slimFrames(c)
    c:fire("PLAYER_ENTERING_WORLD")
    c:advance(0.1)
    eq(#slimFrames(c), frames)
    eq(#frameCalls(c, "PlayerFrame", "SetAlpha"), 1)
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    for _, name in ipairs(GAME_FRAMES) do eq(alphaOf(c, name), 1, name) end
    eq(shown(c, bar(Slim, "player").frame), false)
    eq(eventsHeld(c), 0)
    c:assertClean()
end)

test("slim: the layout going off in a fight leaves the game's frames alone until the fight ends", function()
    local c, PE, Slim = layoutClient()
    PE:GetModule("ctrlLayout").opts.slim = 1
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    c:enterCombat()
    PE:SetModuleEnabled("ctrlLayout", false)
    c:advance(0.1)
    eq(#frameCalls(c, "PlayerFrame", "SetAlpha"), 1)
    eq(alphaOf(c, "PlayerFrame"), 0)
    eq(shown(c, bar(Slim, "player").frame), true)
    c:leaveCombat()
    c:advance(0.1)
    eq(alphaOf(c, "PlayerFrame"), 1)
    eq(shown(c, bar(Slim, "player").frame), false)
    eq(#c.blocked, 0)
end)

test("slim: Save a snapshot lists the five bars and the four tap guards, and the game's frames with their see-through", function()
    local c, PE, Slim = layoutClient()
    PE:GetModule("ctrlLayout").opts.slim = 1
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    c.world.units.target = kobold()
    c:fire("PLAYER_TARGET_CHANGED")
    eq(PE.ControllerLayout:Snapshot(), true)
    local lines = {}
    for _, line in ipairs(rawget(c.env, "PocketEssentialsDB").debug.lines) do
        local text = line:match("^%S+ snapshot: (.*)$")
        if text then lines[#lines + 1] = text end
    end
    local function piece(name)
        for _, l in ipairs(lines) do
            if l:sub(1, #name + 9) == "piece: " .. name .. " |" then return l end
        end
        return nil
    end
    eq(piece("player bar"), "piece: player bar | shown | l=166.7 b=125.0 w=280.0 h=28.0 s=1.00")
    eq(piece("target bar"), "piece: target bar | shown | l=918.7 b=125.0 w=280.0 h=28.0 s=1.00")
    check(piece("pet bar"):find("| hidden |", 1, true), "pet bar: " .. piece("pet bar"))
    check(piece("target of target bar") ~= nil, "no target of target bar")
    check(piece("cast bar"):find("| hidden |", 1, true), "cast bar: " .. piece("cast bar"))
    for _, key in ipairs({ "player", "pet", "target", "tot" }) do
        check(piece("tap guard, " .. key .. " frame") ~= nil, "no line for the " .. key .. " guard")
    end
    check(piece("player"):find("a=0.00", 1, true), "the player frame's see-through is not in its line: " .. piece("player"))
    check(piece("target"):find("a=0.00", 1, true), "the target frame's see-through is not in its line: " .. piece("target"))
    -- The switch's value is among the options.
    local found = false
    for _, l in ipairs(lines) do if l:find("^options") and l:find(" slim=1", 1, true) then found = true end end
    check(found, "slim=1 is not among the snapshot's options")
    -- The guards lie over the game's frames by design: never in an overlap line.
    for _, l in ipairs(lines) do
        if l:sub(1, 9) == "overlap: " then check(not l:find("tap guard, ", 1, true), "a guard is in an overlap: " .. l) end
    end
end)

---------------------------------------------------------------------------
-- After the review of 0.17.0
---------------------------------------------------------------------------

test("slim: shut off by errors in a fight, the tap guards stay over the game's still invisible frames until the fight ends", function()
    local c, PE, Slim = started()
    setTarget(c, kobold())
    local guards = Slim.view.guards
    c:enterCombat()
    breakIt(c, Slim, 3)
    eq(Slim:Status(), TEXT_ERROR)
    eq(alphaOf(c, "PlayerFrame"), 0)
    -- Every guard that has a place shows and can take the tap, also the ones whose bar was hidden.
    for _, key in ipairs({ "player", "pet", "target", "tot" }) do
        check(guards[key]:IsVisible(), "the " .. key .. " guard is gone while the game's frame is invisible")
    end
    -- Our bars themselves are gone: no stale numbers.
    for _, key in ipairs({ "player", "pet", "target", "tot" }) do eq(shown(c, bar(Slim, key).frame), false, key .. " bar") end
    eq(shown(c, Slim.view.cast.frame), false)
    c:leaveCombat()
    c:advance(0.1)
    for _, name in ipairs(GAME_FRAMES) do eq(alphaOf(c, name), 1, name) end
    for _, key in ipairs({ "player", "pet", "target", "tot" }) do
        check(not guards[key]:IsVisible(), "the " .. key .. " guard stays after the game's frame is back")
    end
    for _, rec in ipairs(drawnFrames(c)) do check(not rec.frame:IsVisible(), "a frame of the bars still shows") end
    eq(#c.blocked, 0)
end)

test("slim: Stop asked in a fight leaves no gap either: the guards stay as long as the game's frames are invisible", function()
    local c, PE, Slim = started()
    c:enterCombat()
    Slim:Stop()
    eq(alphaOf(c, "PlayerFrame"), 0)
    check(Slim.view.guards.player:IsVisible(), "the player guard went before the game's frame came back")
    c:leaveCombat()
    c:advance(0.1)
    eq(alphaOf(c, "PlayerFrame"), 1)
    check(not Slim.view.guards.player:IsVisible(), "the guard stays")
    -- And a Stop out of a fight after an error shut-off in a fight that has not been tidied yet.
    local c2, PE2, Slim2 = started()
    c2:enterCombat()
    breakIt(c2, Slim2, 3)
    c2.world.inCombat = false
    Slim2:Stop()
    eq(alphaOf(c2, "PlayerFrame"), 1)
    check(not Slim2.view.guards.player:IsVisible(), "the guard stays after Stop")
end)

local STOPPED_GREY = { 0.35, 0.35, 0.35, 1 }

test("slim: a bar whose widget refuses the game's value shows that it stopped: grey fill and a ? for the number, until a call works again", function()
    local c, PE, Slim = started()
    local p = bar(Slim, "player")
    c.world.unitSecret = true
    c.world.barRefusesSecrets = true
    c.world.units.player.health = 31
    c:fire("UNIT_HEALTH", "player")
    eq(st(c, p.health).barColor, STOPPED_GREY, "health fill")
    eq(p.value:GetText(), "?")
    eq(st(c, p.power).barColor, { 0.20, 0.40, 1.00, 1 }, "the power bar was not asked yet")
    c:fire("UNIT_POWER_UPDATE", "player", "MANA")
    eq(st(c, p.power).barColor, STOPPED_GREY, "power fill")
    -- A colour change meanwhile does not paint over the mark.
    c.world.units.player.powerToken = "RAGE"
    c:fire("UNIT_DISPLAYPOWER", "player")
    eq(st(c, p.power).barColor, STOPPED_GREY)
    -- Many more refusals: still one line each in the log.
    local lines = #notes(c)
    for _ = 1, 10 do
        c:fire("UNIT_HEALTH", "player")
        c:fire("UNIT_POWER_UPDATE", "player", "RAGE")
    end
    eq(#notes(c), lines, "a line for a repeated refusal")
    eq(notedLike(c, "^StatusBar:SetValue %(health%) failed: "), 1)
    -- The widgets take the values again: the marks clear.
    c.world.barRefusesSecrets = false
    c:fire("UNIT_HEALTH", "player")
    eq(st(c, p.health).barColor, GREEN)
    eq({ given(c, st(c, p.value).text) }, { 31, true })
    c:fire("UNIT_POWER_UPDATE", "player", "RAGE")
    eq(st(c, p.power).barColor, { 1, 0, 0, 1 })
    -- Only the number refused: the number reads ?, and the bar is marked too.
    c.world.textRefusesSecrets = true
    c:fire("UNIT_HEALTH", "player")
    eq(p.value:GetText(), "?")
    eq(st(c, p.health).barColor, STOPPED_GREY)
    -- A restart clears the mark as well.
    Slim:Stop()
    c.world.unitSecret = false
    eq(Slim:Start(), true)
    eq(st(c, p.health).barColor, GREEN)
    eq(p.value:GetText(), "31")
    eq(#PE.errors, 0)
    c:assertClean()
end)

test("slim: a small bar that stopped is greyed too, and a target bar gets its own colour back", function()
    local c, PE, Slim = started()
    setTarget(c, kobold())
    local t = bar(Slim, "target")
    eq(st(c, t.health).barColor, RED)
    c.world.unitSecret = true
    c.world.barRefusesSecrets = true
    c:fire("UNIT_HEALTH", "target")
    eq(st(c, t.health).barColor, STOPPED_GREY)
    eq(t.value:GetText(), "?")
    -- A new target while stopped keeps the mark.
    setTarget(c, kobold({ name = "Guard", attackable = false }))
    eq(st(c, t.health).barColor, STOPPED_GREY)
    c.world.barRefusesSecrets = false
    c:fire("UNIT_HEALTH", "target")
    eq(st(c, t.health).barColor, GREEN)
    c:assertClean()
end)

test("slim: a Start that raises counts toward the three errors and is then not tried again", function()
    local c, PE, Slim = new()
    local real = PE.LayoutPlan.SlimRects
    PE.LayoutPlan.SlimRects = function() error("boom") end
    eq({ Slim:Start() }, { false, TEXT_ERROR })
    eq({ Slim:Start() }, { false, TEXT_ERROR })
    eq(noted(c, "turned off after 3 errors"), 0)
    eq({ Slim:Start() }, { false, TEXT_ERROR })
    eq(noted(c, "turned off after 3 errors"), 1)
    local lines = T.chatLines(c)
    eq(lines[#lines], CHAT_ERROR)
    check(#PE.errors >= 1, "the failure was not logged")
    -- Not tried again, even once it would work.
    local asked = 0
    PE.LayoutPlan.SlimRects = function() asked = asked + 1 return real() end
    for _ = 1, 5 do eq({ Slim:Start() }, { false, TEXT_ERROR }) end
    eq(asked, 0, "tried again after the limit")
    for _, name in ipairs(GAME_FRAMES) do eq(alphaOf(c, name), 1, name) end
    for _, rec in ipairs(drawnFrames(c)) do check(not rec.frame:IsVisible(), "a frame of the bars shows") end
    eq(eventsHeld(c), 0)
end)

---------------------------------------------------------------------------
-- 0.20.0: whole names (spec 2026-11-25-0.20.0-after-first-sitting.md, 1). The stand-in's
-- surname separator is two spaces, so a test can tell the game's value from our fallback.
---------------------------------------------------------------------------

local SEP = "  "

-- A client whose player is "Forgot Shards", the bars started through the layout (so the
-- row's value is read) unless o.direct. o.names: the saved "Names on the bars" value.
local function named(o)
    o = o or {}
    local c, PE, Slim = layoutClient()
    c.world.playerName, c.world.playerSurname = "Forgot", "Shards"
    if o.setup then o.setup(c) end
    local opts = PE:GetModule("ctrlLayout").opts
    opts.slim = 1
    if o.names ~= nil then opts.slimNames = o.names end
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    return c, PE, Slim
end

local function namesRow(PE)
    for _, o in ipairs(PE:GetModule("ctrlLayout").options) do if o.key == "slimNames" then return o end end
    return nil
end

-- A tap on the row, the way the settings window does it.
local function pickNames(c, PE, value)
    local m = PE:GetModule("ctrlLayout")
    m.opts.slimNames = value
    PE:Safe("ctrlLayout", namesRow(PE).OnChange, m, value)
    c:advance(0.1)
end

test("0.20.0 names: the row is on the Controller tab under Slim bars, Whole name by default", function()
    local c, PE = layoutClient()
    local list = PE:GetModule("ctrlLayout").options
    local at
    for i, o in ipairs(list) do if o.key == "slimNames" then at = i end end
    check(at ~= nil, "no Names on the bars row")
    eq(list[at].label, "Names on the bars")
    eq(list[at - 1].key, "slim", "the row before it")
    local out = {}
    for i, ch in ipairs(list[at].choices) do out[i] = { ch.value, ch.label } end
    eq(out, { { 1, "Whole name" }, { 0, "First name" } })
    eq(PE:GetModule("ctrlLayout").opts.slimNames, 1)
    eq(PE.LayoutPlan.DEFAULTS.slimNames, 1)
    -- A saved value that is neither reads as the default in the plan.
    eq(#PE.LayoutPlan.Pieces({ slimNames = 7 }), #PE.LayoutPlan.Pieces({}))
end)

test("0.20.0 names: a unit with a surname shows first name, the game's separator, surname; the log says so once", function()
    local c, PE, Slim = named()
    eq(bar(Slim, "player").name:GetText(), "Forgot" .. SEP .. "Shards")
    eq(noted(c, "names: whole"), 1)
    eq(noted(c, "a surname was joined for the player bar"), 1)
    setTarget(c, kobold({ name = "Anna", surname = "Lee" }))
    eq(bar(Slim, "target").name:GetText(), "Anna" .. SEP .. "Lee")
    c.world.units.targettarget = { name = "Forgot", surname = "Shards", health = 1, healthMax = 1 }
    c:fire("UNIT_TARGET", "target")
    eq(bar(Slim, "tot").name:GetText(), "Forgot" .. SEP .. "Shards")
    -- Once a session, the first time only.
    c:fire("UNIT_NAME_UPDATE", "player")
    eq(notedLike(c, "^a surname was joined"), 1)
    eq(#PE.errors, 0)
    c:assertClean()
end)

test("0.20.0 names: no surname, or an empty one, shows the first name alone", function()
    local c, PE, Slim = named()
    setTarget(c, kobold())
    eq(bar(Slim, "target").name:GetText(), "Kobold")
    setTarget(c, kobold({ name = "Guard", surname = "" }))
    eq(bar(Slim, "target").name:GetText(), "Guard")
    c.world.units.pet = { name = "Cat", health = 1, healthMax = 1 }
    c:fire("UNIT_PET", "player")
    eq(bar(Slim, "pet").name:GetText(), "Cat")
    -- And back to a unit with one: the old surname does not stay, the new one shows.
    setTarget(c, kobold({ name = "Anna", surname = "Lee" }))
    eq(bar(Slim, "target").name:GetText(), "Anna" .. SEP .. "Lee")
    setTarget(c, kobold())
    eq(bar(Slim, "target").name:GetText(), "Kobold")
    c:assertClean()
end)

test("0.20.0 names: First name shows the first name only, and nothing is joined or asked", function()
    local c, PE, Slim = named({ names = 0 })
    eq(bar(Slim, "player").name:GetText(), "Forgot")
    eq(noted(c, "names: first"), 1)
    eq(notedLike(c, "surname"), 0)
    eq(#c:callsTo("RegionalUniqueNamesEnabled"), 0)
    setTarget(c, kobold({ name = "Anna", surname = "Lee" }))
    eq(bar(Slim, "target").name:GetText(), "Anna")
    c:assertClean()
end)

test("0.20.0 names: the row counts at once, both ways, for every bar that shows, with no reload", function()
    local c, PE, Slim = named()
    setTarget(c, kobold({ name = "Anna", surname = "Lee" }))
    c.world.units.pet = { name = "Cat", surname = "Paws", health = 1, healthMax = 1 }
    c:fire("UNIT_PET", "player")
    local reloads, writes = #PE.reloadReasons, #c:callsTo("C_EditMode.SaveLayouts")
    pickNames(c, PE, 0)
    eq(bar(Slim, "player").name:GetText(), "Forgot")
    eq(bar(Slim, "target").name:GetText(), "Anna")
    eq(bar(Slim, "pet").name:GetText(), "Cat")
    eq(noted(c, "names: first"), 1)
    pickNames(c, PE, 1)
    eq(bar(Slim, "player").name:GetText(), "Forgot" .. SEP .. "Shards")
    eq(bar(Slim, "target").name:GetText(), "Anna" .. SEP .. "Lee")
    eq(bar(Slim, "pet").name:GetText(), "Cat" .. SEP .. "Paws")
    eq(noted(c, "names: whole"), 2) -- at the start and now
    eq(#PE.reloadReasons, reloads, "a reload was asked for")
    eq(#c:callsTo("C_EditMode.SaveLayouts"), writes, "the layout was written again")
    -- Also in a fight: only our own texts are written.
    c:enterCombat()
    pickNames(c, PE, 0)
    eq(bar(Slim, "target").name:GetText(), "Anna")
    eq(#c.blocked, 0)
    c:leaveCombat()
    c:assertClean()
end)

test("0.20.0 names: with Slim bars Off the row is only saved: SlimBars.lua is not called", function()
    local c, PE, Slim = layoutClient()
    PE:SetModuleEnabled("ctrlLayout", true)
    c:advance(0.1)
    pickNames(c, PE, 0)
    eq(PE:GetModule("ctrlLayout").opts.slimNames, 0)
    eq(#slimFrames(c), 0)
    eq(#notes(c), 0)
    c:assertClean()
end)

test("0.20.0 names: a second answer is joined as the game's own frames do, whatever the game says about realms", function()
    for _, how in ipairs({ "false", "missing", "raises", "hidden" }) do
        local c, PE, Slim = named({ setup = function(c)
            if how == "false" then c.world.regionalNames = false end
            if how == "missing" then rawset(c.env, "RegionalUniqueNamesEnabled", nil) end
            if how == "raises" then c.world.unitCallFails.RegionalUniqueNamesEnabled = true end
            if how == "hidden" then c.world.unitAnswerHidden.RegionalUniqueNamesEnabled = true end
        end })
        eq(bar(Slim, "player").name:GetText(), "Forgot  Shards", how) -- the stand-in's separator is two spaces
        eq(#c:callsTo("RegionalUniqueNamesEnabled"), 0, how)
        eq(#PE.errors, 0, how)
    end
end)

test("0.20.0 names: a hidden second answer is never joined: the bar keeps the name it had", function()
    local c, PE, Slim = named({ setup = function(c)
        c.world.units.player.name, c.world.units.player.surname = "Forgot", "Shards"
    end })
    local p = bar(Slim, "player")
    eq(p.name:GetText(), "Forgot" .. SEP .. "Shards")
    c.world.unitSecret = true
    c:fire("UNIT_NAME_UPDATE", "player")
    c:fire("PLAYER_ENTERING_WORLD")
    c:advance(0.1)
    eq(p.name:GetText(), "Forgot" .. SEP .. "Shards")
    eq(noted(c, "a second name is hidden: nothing is joined to it"), 1)
    -- A target picked now: its hidden first name goes into the widget as it came, alone.
    setTarget(c, kobold({ name = "Anna", surname = "Lee" }))
    eq({ given(c, st(c, bar(Slim, "target").name).text) }, { "Anna", true })
    -- A bar that showed another unit's whole name does not keep it for the new unit.
    c.world.unitSecret = false
    setTarget(c, kobold({ name = "Bob", surname = "Ray" }))
    eq(bar(Slim, "target").name:GetText(), "Bob" .. SEP .. "Ray")
    c.world.unitSecret = true
    setTarget(c, kobold({ name = "Anna", surname = "Lee" }))
    eq({ given(c, st(c, bar(Slim, "target").name).text) }, { "Anna", true })
    eq(#PE.errors, 0)
    eq(#c.errors, 0)
end)

test("0.20.0 names: only the second answer hidden, the first plain: still nothing is joined", function()
    local c, PE, Slim = named({ setup = function(c)
        local hidden = c:secret("Lee")
        rawset(c.env, "UnitName", function(unit)
            if unit == "target" then return "Anna", hidden end
            return "Forgot", "Shards"
        end)
    end })
    eq(bar(Slim, "player").name:GetText(), "Forgot" .. SEP .. "Shards")
    setTarget(c, kobold())
    eq(bar(Slim, "target").name:GetText(), "Anna")
    eq(#PE.errors, 0)
    eq(#c.errors, 0)
end)

test("0.20.0 names: a name wider than its room is cut with ... at the room the bar has today", function()
    local c, PE, Slim = named()
    local p, t = bar(Slim, "player"), bar(Slim, "target")
    -- The rooms are 0.19.0's: 280 - 110 on a main bar, 136 - 10 on a small one.
    eq(st(c, p.name).width, 170)
    eq(st(c, t.name).width, 170)
    eq(st(c, bar(Slim, "pet").name).width, 126)
    eq(st(c, bar(Slim, "tot").name).width, 126)
    local long = { name = "Bartholomewington", surname = "Featherstonehaugh" }
    setTarget(c, kobold(long))
    local text = t.name:GetText()
    eq(text:sub(-3), "...")
    check(t.name:GetUnboundedStringWidth() <= 170, "the cut name is wider than its room: " .. text)
    eq(text:sub(1, 17), "Bartholomewington")
    -- One more character would not fit.
    local whole = long.name .. SEP .. long.surname
    local kept = #text - 3
    t.name:SetText(whole:sub(1, kept + 1) .. "...")
    check(t.name:GetUnboundedStringWidth() > 170, "the name was cut shorter than it had to be")
    -- The small bars cut sooner.
    c.world.units.targettarget = { name = long.name, surname = long.surname, health = 1, healthMax = 1 }
    c:fire("UNIT_TARGET", "target")
    local small = bar(Slim, "tot").name:GetText()
    eq(small:sub(-3), "...")
    check(#small < #text, "the small bar's name is not shorter")
    check(bar(Slim, "tot").name:GetUnboundedStringWidth() <= 126, "the small bar's name is wider than its room")
    -- A name that fits is not touched, and the level and the health number keep their places.
    eq(p.name:GetText(), "Forgot" .. SEP .. "Shards")
    eq(p.level:GetText(), "10")
    eq(p.value:GetText(), "100")
    -- Whole characters only: a cut never ends inside a letter of several bytes.
    setTarget(c, kobold({ name = string.rep("\195\169", 20), surname = string.rep("\195\168", 20) }))
    local cut = t.name:GetText()
    eq(cut:sub(-3), "...")
    local body = cut:sub(1, -4)
    check(body == string.rep("\195\169", #body / 2), "a letter was cut in half: " .. #body .. " bytes")
    c:assertClean()
end)

test("0.20.0 names: a client without the game's separator joins with one space", function()
    local c, PE, Slim = named({ setup = function(c) rawset(c.env, "Constants", {}) end })
    eq(bar(Slim, "player").name:GetText(), "Forgot Shards")
    eq(#PE.errors, 0)
end)

test("0.22.0 menu: the tap guards over the target frame and its target of target stand at the lifted spot", function()
    -- The guards read the game's frames, not the plan: with the row b22Menu On the layout puts the
    -- target frame (and so the target of target, which hangs on it) 174 higher after the reload.
    local function lifted(rise)
        return function(c)
            -- The layout's load moves it, not a call of ours: the stand-in's state is set directly.
            c._state(c.env.TargetFrame).points = { { point = "BOTTOMLEFT", rel = c.UIParent, relPoint = "BOTTOM", x = 300, y = 250 + rise } }
        end
    end
    local c0, _, Slim0 = started({ setup = lifted(0) })
    local c, _, Slim = started({ setup = lifted(174) })
    local base = { rectOf(c0, Slim0.view.guards.target), rectOf(c0, Slim0.view.guards.tot) }
    local game = { target = c.env.TargetFrame, tot = totFrame(c) }
    for i, key in ipairs({ "target", "tot" }) do
        local g = rectOf(c, Slim.view.guards[key])
        sameRect(g, rectOf(c, game[key]), key .. " guard over its game frame")
        near(g[2], base[i][2] + 174, key .. " guard bottom, 174 up")
        near(g[4], base[i][4] + 174, key .. " guard top, 174 up")
        near(g[1], base[i][1], key .. " guard left")
        near(g[3], base[i][3], key .. " guard right")
    end
    eq(notedLike(c, "^tap guard over the game's target frame: BOTTOMLEFT x [%d.]+ y 424%.0, 232%.0 by 100%.0$"), 1)
    -- The player and pet guards are where they were.
    for _, key in ipairs({ "player", "pet" }) do
        sameRect(rectOf(c, Slim.view.guards[key]), rectOf(c0, Slim0.view.guards[key]), key .. " guard")
    end
    c:assertClean()
end)

return { known = KNOWN_FAILURES }
