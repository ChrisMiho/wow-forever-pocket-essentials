-- Rules for the face pictures of Controller layout 0.13.0 and 0.14.0 (FaceBars.lua).
-- Source: docs/superpowers/specs/2026-11-23-controller-layout-0.13.0-face-bars.md
-- ("The face", "The real bars", "When the face cannot work", "Layers and taps",
-- "Tests"), the plan's contract (PE.FaceBars:Start / Stop / Status), and
-- docs/superpowers/specs/2026-11-23-controller-layout-0.14.0-console.md (one panel a
-- side, the triggers swap it; picture 42). Fresh client and addon per test;
-- PE.FaceBars is started directly (ControllerLayout calls it in the game).
local T = ...
local test, eq, check = T.test, T.eq, T.check

local KNOWN_FAILURES = {
}

local TEXT_NO_BARS = "the game's spell bars were not found"
local TEXT_NO_BUTTONS = "the game's spell buttons were not found"
local TEXT_NO_COOLDOWN = "this game version cannot draw cooldowns on our pictures"
local TEXT_ERROR = "they hit an error"
local CHAT_ERROR = "Spell pictures turned off after an error; the game's bars are back. Reload to try again."
local ANCHORS = { "TopCenteredAnchor", "LeftCenteredAnchor", "RightCenteredAnchor", "BottomCenteredAnchor" }

local function near(a, b, msg)
    check(type(a) == "number" and math.abs(a - b) < 1e-6, (msg or "number") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

-- A client with the addon loaded; opts.setup(c) runs before the load. Returns c, PE, Face.
local function new(opts)
    opts = opts or {}
    local c, PE = T.new({ setup = opts.setup })
    return c, PE, PE.FaceBars
end

-- A client with the face started (checked).
local function started(opts)
    local c, PE, Face = new(opts)
    local ok, why = Face:Start()
    check(ok == true, "Start failed: " .. tostring(why))
    return c, PE, Face
end

local function pu(c) return c.env.GamepadMainActionBarFrame.PageUnit end
local function anchor(c, key) return pu(c)[key] end
local function alphaOf(c, f) return c._state(f).alpha end
local function pic(Face, g, n) return Face.view[g].pics[n] end
local function half(Face, g, h) return Face.view[g].halves[h] end
-- The frame every half, and the frames that take a tap, sit in.
local function holderOf(c, Face) return c._state(half(Face, 1, 1)).parent end
local function st(c, region) return c._state(region) end
local function shown(c, region) return st(c, region).shown == true end

-- Every frame FaceBars.lua made.
local function faceFrames(c)
    local out = {}
    for _, rec in ipairs(c:frames()) do
        if rec.addonFile == "FaceBars.lua" then out[#out + 1] = rec end
    end
    return out
end

local function onUpdates(c)
    local n = 0
    for _, rec in ipairs(faceFrames(c)) do if rec.scripts.OnUpdate then n = n + 1 end end
    return n
end

local function cdCalls(c, method)
    local n = 0
    for _, call in ipairs(c.cdCalls) do if call.method == method then n = n + 1 end end
    return n
end

local function hookCount(c)
    return #c:callsTo("hooksecurefunc")
end

-- The spec's four spots and states (0.14.0, "The new arrangement").
local SPOT_XY = { innerLeft = { -170, 66 }, outerLeft = { -316, 66 }, innerRight = { 170, 66 }, outerRight = { 316, 66 } }
local GROUP_N = { main = 1, lt = 2, rt = 3, both = 4 }
local HALF_N = { dpad = 1, face = 2 }
local REST = { { "main", "dpad", "innerLeft" }, { "main", "face", "innerRight" } }
local LT = { { "lt", "dpad", "outerLeft" }, { "lt", "face", "innerLeft" }, { "main", "face", "innerRight", true } }
local RT = { { "main", "dpad", "innerLeft", true }, { "rt", "dpad", "innerRight" }, { "rt", "face", "outerRight" } }
local BOTH = { { "both", "dpad", "innerLeft" }, { "both", "face", "innerRight" } }

-- Every half against a state: the listed ones shown, CENTER on the screen's bottom at
-- their spot, quiet (true) at 0.3 or else 1; every other half hidden.
local function checkState(c, Face, want, what)
    local wanted = {}
    for _, w in ipairs(want) do wanted[GROUP_N[w[1]] * 10 + HALF_N[w[2]]] = w end
    for g = 1, 4 do
        for h = 1, 2 do
            local f = half(Face, g, h)
            local w = wanted[g * 10 + h]
            local label = what .. ": group " .. g .. " half " .. h
            if w then
                eq(f:IsShown(), true, label .. " shown")
                eq(f:GetNumPoints(), 1, label .. " points")
                local point, rel, relPoint, x, y = f:GetPoint(1)
                eq({ point, rel == c.UIParent, relPoint }, { "CENTER", true, "BOTTOM" }, label .. " anchor")
                near(x, SPOT_XY[w[3]][1], label .. " x")
                near(y, SPOT_XY[w[3]][2], label .. " y")
                near(alphaOf(c, f), w[4] and 0.3 or 1, label .. " see-through")
            else
                eq(f:IsShown(), false, label .. " hidden")
            end
        end
    end
end

---------------------------------------------------------------------------
-- Off until started
---------------------------------------------------------------------------

test("face: nothing is made, hooked or registered before Start", function()
    local c, PE, Face = new()
    eq(#faceFrames(c), 0, "frames made at load")
    eq(#T.gameCalls(c), 0, "game calls at load")
    eq(Face:Status(), nil)
    eq(alphaOf(c, anchor(c, "TopCenteredAnchor")), 1)
    c:advance(1)
    eq(#faceFrames(c), 0)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- The pictures
---------------------------------------------------------------------------

test("face: Start builds 32 pictures, four per half, placed on their half's centre, then makes the four anchors invisible", function()
    local c, PE, Face = started()
    eq(Face:Status(), nil)
    eq(#Face.view, 4)
    -- Picture 42; a diamond's buttons 46 left / right and 28 up / down of its centre.
    local steps = { { -46, 0 }, { 0, 28 }, { 46, 0 }, { 0, -28 } }
    for g = 1, 4 do
        eq(#Face.view[g].pics, 8, "group " .. g)
        eq(#Face.view[g].halves, 2, "group " .. g .. " halves")
        for h = 1, 2 do
            near(half(Face, g, h):GetWidth(), 134, "half width")
            near(half(Face, g, h):GetHeight(), 98, "half height")
        end
        for n = 1, 8 do
            local p = pic(Face, g, n)
            local h = n <= 4 and 1 or 2
            local q = (n - 1) % 4 + 1
            eq(st(c, p.frame).parent, half(Face, g, h), "group " .. g .. " picture " .. n .. " in its half")
            local point, rel, relPoint, x, y = p.frame:GetPoint(1)
            eq({ point, rel == half(Face, g, h), relPoint }, { "CENTER", true, "CENTER" }, "group " .. g .. " picture " .. n)
            near(x, steps[q][1], "x of " .. g .. "/" .. n)
            near(y, steps[q][2], "y of " .. g .. "/" .. n)
            near(p.frame:GetWidth(), 42)
        end
    end
    -- At rest: only the main bar, d-pad inner-left and face inner-right.
    checkState(c, Face, REST, "rest")
    for _, key in ipairs(ANCHORS) do eq(alphaOf(c, anchor(c, key)), 0, key .. " see-through") end
    eq(onUpdates(c), 0, "no OnUpdate left after Start")
    c:assertClean()
end)

test("face: the trigger tags sit in each diamond's centre, none on the main bar", function()
    local c, PE, Face = started()
    eq(#Face.view[1].tags, 0)
    local want = { nil, "LT", "RT", "LT+RT" }
    for g = 2, 4 do
        eq(#Face.view[g].tags, 2, "group " .. g)
        for _, tag in ipairs(Face.view[g].tags) do eq(tag:GetText(), want[g]) end
    end
    local point, rel, relPoint, x, y = Face.view[4].tags[2]:GetPoint(1)
    eq({ point, rel == half(Face, 4, 2), relPoint, x, y }, { "CENTER", true, "CENTER", 0, 0 })
end)

test("face: the glyph, range dot and count grow with the picture (drawn for 28, now 42)", function()
    local c, PE, Face = started()
    local p = pic(Face, 2, 1)
    near(p.range:GetWidth(), 6, "range dot")
    local _, size = p.count:GetFont()
    eq(size, 14, "count font")
    local _, tagSize = Face.view[2].tags[1]:GetFont()
    eq(tagSize, 12, "tag font")
end)

test("face: strata MEDIUM, between the bars (LOW) and the wheels (DIALOG)", function()
    local c, PE, Face = started()
    eq(holderOf(c, Face):GetFrameStrata(), "MEDIUM")
end)

test("face: taps are taken and do nothing (mouse on, no click handler)", function()
    local c, PE, Face = started()
    for g = 1, 4 do
        for n = 1, 8 do
            local rec = st(c, pic(Face, g, n).frame)
            eq(rec.mouse, true, "mouse on " .. g .. "/" .. n)
            for name in pairs(rec.scripts) do error("picture " .. g .. "/" .. n .. " has a " .. name .. " script") end
        end
    end
end)

test("face: icon, usable colour and empty slots are copied from the real buttons", function()
    local c, PE, Face = started()
    local p1, p2, p3 = pic(Face, 1, 1), pic(Face, 1, 2), pic(Face, 1, 3)
    eq(st(c, p1.icon).texture, 135274)
    eq(shown(c, p1.icon), true)
    eq(st(c, p1.icon).vertexColor, { 1, 1, 1, 1 })
    eq(st(c, p2.icon).texture, 136096)
    eq(st(c, p2.icon).vertexColor, { 0.4, 0.4, 0.4, 1 }, "not usable: the game's grey")
    eq(p3.empty, true, "slot 3 holds nothing")
    eq(shown(c, p3.icon), false)
    eq(st(c, p3.back).color, { 1, 1, 1, 0.12 }, "a faint outline")
    -- The game greys a button and changes its colour: the hooks bring both across.
    local real = c.barButtons.TopCenteredAnchor[1]
    real.icon:SetDesaturated(true)
    real.icon:SetVertexColor(0.5, 0.5, 1)
    eq(st(c, p1.icon).desaturated, false, "not before the next frame")
    c:advance(0.1)
    eq(st(c, p1.icon).desaturated, true)
    eq(st(c, p1.icon).vertexColor, { 0.5, 0.5, 1, 1 })
    -- A slot that gets a spell.
    c:setAction(3, { texture = 777, duration = 0, count = "" })
    c:advance(0.1)
    eq(p3.empty, false)
    eq(st(c, p3.icon).texture, 777)
    eq(onUpdates(c), 0)
    c:assertClean()
end)

test("face: the main bar's face buttons show the game's own pictures, no cooldown, never checked", function()
    local c, PE, Face = started()
    local x, y, b, a = pic(Face, 1, 5), pic(Face, 1, 6), pic(Face, 1, 7), pic(Face, 1, 8)
    eq(x.special, true)
    eq(st(c, x.icon).texture, "Interface\\Cursor\\Interact")
    eq(st(c, y.icon).atlas, "crosshair_unableinspect_32")
    eq(st(c, b.icon).atlas, "128-redbutton-exit")
    eq(st(c, a.icon).atlas, "gamepad-ability-icon-jump")
    -- Slot 5 has a spell in the stand-in's world, but the button is reserved: no sweep.
    for _, call in ipairs(c.cdCalls) do check(call.frame ~= x.cd, "a cooldown was set on X") end
    c.world.actions[5].checked = true
    c:fire("ACTIONBAR_UPDATE_STATE")
    c:advance(0.1)
    eq(shown(c, x.checked), false)
    -- The game changes Y's picture (a target to inspect).
    c.barButtons.TopCenteredAnchor[6].SpecialActionIcon:SetAtlas("crosshair_inspect_32")
    c:advance(0.1)
    eq(st(c, y.icon).atlas, "crosshair_inspect_32")
    c:assertClean()
end)

test("face: cooldown from the duration object, the icon darkened while on cooldown, never SetCooldown", function()
    local c, PE, Face = started()
    local p1, p2 = pic(Face, 1, 1), pic(Face, 1, 2)
    eq(shown(c, p2.cd), true, "slot 2 is on cooldown (8 s)")
    eq(st(c, p2.cd).cooldown.duration, 8)
    eq(shown(c, p2.dim), true)
    eq(shown(c, p1.cd), false)
    eq(shown(c, p1.dim), false)
    -- A cast puts slot 1 on cooldown; the events are collected into one update.
    c.world.actions[1].duration = 5
    local before = cdCalls(c, "SetCooldownFromDurationObject")
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    c:fire("SPELL_UPDATE_COOLDOWN")
    c:fire("SPELL_UPDATE_COOLDOWN")
    eq(cdCalls(c, "SetCooldownFromDurationObject"), before, "nothing before the next frame")
    eq(onUpdates(c), 1, "one OnUpdate waiting")
    c:advance(0.1)
    local after = cdCalls(c, "SetCooldownFromDurationObject")
    check(after > before and after - before <= 32, "one pass over the pictures, got " .. (after - before) .. " calls")
    eq(st(c, p1.cd).cooldown.duration, 5)
    eq(shown(c, p1.dim), true)
    eq(onUpdates(c), 0, "the OnUpdate removed itself")
    -- The global cooldown: the sweep runs, the icon is not darkened.
    c.world.actions[1].duration, c.world.actions[1].gcd = 1.5, true
    c:fire("SPELL_UPDATE_COOLDOWN")
    c:advance(0.1)
    eq(shown(c, p1.cd), true)
    eq(shown(c, p1.dim), false)
    eq(cdCalls(c, "SetCooldown"), 0, "SetCooldown is never used")
    c:assertClean()
end)

test("face: range dot copies the real RangeIndicator (shown, colour)", function()
    local c, PE, Face = started()
    local real, p = c.barButtons.LeftCenteredAnchor[2], pic(Face, 2, 2)
    eq(shown(c, p.range), false)
    c:setRange(real, true, false)
    c:advance(0.1)
    eq(shown(c, p.range), true)
    eq(st(c, p.range).vertexColor, { 1, 0.1, 0.1, 1 })
    c:setRange(real, true, true)
    c:advance(0.1)
    eq(st(c, p.range).vertexColor, { 0.6, 0.6, 0.6, 1 })
    c:setRange(real, false)
    c:advance(0.1)
    eq(shown(c, p.range), false)
end)

test("face: the count text is passed on as it is, a secret one too", function()
    local c, PE, Face = started()
    c:setAction(9, { texture = 5, duration = 0, count = "5" })
    c:advance(0.1)
    eq(pic(Face, 2, 1).count:GetText(), "5")
    local secret = "12"
    c.world.secrets[secret] = true
    c.barButtons.LeftCenteredAnchor[1].Count:SetText(secret)
    c:advance(0.1)
    eq(pic(Face, 2, 1).count:GetText(), "12")
    c:assertClean()
end)

test("face: checked is read on ACTIONBAR_UPDATE_STATE and after UpdateState", function()
    local c, PE, Face = started()
    local p = pic(Face, 1, 1)
    eq(shown(c, p.checked), false)
    c.world.actions[1].checked = true
    c:fire("ACTIONBAR_UPDATE_STATE")
    c:advance(0.1)
    eq(shown(c, p.checked), true)
    c.world.actions[1].checked = false
    c.barButtons.TopCenteredAnchor[1]:UpdateState()
    c:advance(0.1)
    eq(shown(c, p.checked), false)
end)

test("face: the proc glow follows the game's alert on that button only", function()
    local c, PE, Face = started()
    local p = pic(Face, 3, 4)
    c:spellAlert(c.barButtons.RightCenteredAnchor[4], true)
    c:advance(0.1)
    eq(shown(c, p.glow), true)
    eq(shown(c, pic(Face, 3, 3).glow), false)
    c:spellAlert(c.barButtons.RightCenteredAnchor[4], false)
    c:advance(0.1)
    eq(shown(c, p.glow), false)
    -- A button that is not on our bars: nothing happens.
    c:spellAlert({}, true)
    c:advance(0.1)
    c:assertClean()
end)

test("face: a stance bar swapped into an anchor is mirrored, and the normal bar again when it leaves", function()
    local c, PE, Face = started()
    c:setAction(201, { texture = 4444, duration = 0, count = "" })
    local stance = c.actionBars.stanceBar
    c:showOverrideBar("stanceBar", "TopCenteredAnchor")
    c:advance(0.1)
    eq(pic(Face, 1, 1).button, stance:GetActionButtonByIndex(1))
    eq(st(c, pic(Face, 1, 1).icon).texture, 4444)
    eq(pic(Face, 1, 5).special, false, "the stance bar's face buttons are spells")
    c:hideOverrideBar("stanceBar")
    c:advance(0.1)
    eq(pic(Face, 1, 1).button, c.barButtons.TopCenteredAnchor[1])
    eq(st(c, pic(Face, 1, 1).icon).texture, 135274)
    -- The stance bar in the LT anchor (GamepadStanceBarOverride Page1LeftBar).
    c:showOverrideBar("stanceBar", "LeftCenteredAnchor")
    c:advance(0.1)
    eq(pic(Face, 2, 1).button, stance:GetActionButtonByIndex(1))
    eq(pic(Face, 1, 1).button, c.barButtons.TopCenteredAnchor[1], "the main group keeps its own bar")
    c:assertClean()
end)

test("face: a targeting bar held in the top anchor is mirrored by the main group, which stays the active one", function()
    local c, PE, Face = started({ setup = function(cl) cl:addTargetingBars() end })
    local friendly = c.actionBars.friendlyTargetingBar
    c:showOverrideBar("friendlyTargetingBar", "TopCenteredAnchor")
    c:advance(0.1)
    eq(pic(Face, 1, 2).button, friendly:GetActionButtonByIndex(2))
    checkState(c, Face, REST, "targeting bar")
    c:hideOverrideBar("friendlyTargetingBar")
    c:advance(0.1)
    eq(pic(Face, 1, 2).button, c.barButtons.TopCenteredAnchor[2])
end)

test("face: the triggers swap the halves: rest, LT, RT, both, rest", function()
    local c, PE, Face = started()
    checkState(c, Face, REST, "rest")
    c:pressTriggers(true, false)
    checkState(c, Face, REST, "LT, before the next frame")
    c:advance(0.1)
    checkState(c, Face, LT, "LT")
    c:pressTriggers(false, true)
    c:advance(0.1)
    checkState(c, Face, RT, "RT")
    c:pressTriggers(true, true)
    c:advance(0.1)
    checkState(c, Face, BOTH, "LT+RT")
    -- The game calls back on every trigger check: no change, no work.
    c:pressTriggers(true, true)
    eq(onUpdates(c), 0, "an unchanged bar asks for nothing")
    c:pressTriggers(false, false)
    c:advance(0.1)
    checkState(c, Face, REST, "released")
    -- The pictures follow their own bar wherever its half is drawn.
    c:pressTriggers(true, false)
    c:advance(0.1)
    eq(pic(Face, 2, 1).button, c.barButtons.LeftCenteredAnchor[1])
    eq(pic(Face, 2, 5).button, c.barButtons.LeftCenteredAnchor[5])
    c:assertClean()
end)

test("face: the swap works in a fight and changes no frame of the game's", function()
    local c, PE, Face = started()
    c:enterCombat()
    eq(c.env.InCombatLockdown(), true)
    local from = #c.calls
    for _, step in ipairs({ { true, false, LT, "LT" }, { false, true, RT, "RT" }, { true, true, BOTH, "LT+RT" }, { false, false, REST, "rest" } }) do
        c:pressTriggers(step[1], step[2])
        c:advance(0.1)
        checkState(c, Face, step[3], "in a fight, " .. step[4])
    end
    for i = from + 1, #c.calls do
        local name = c.calls[i].name
        check(not (name:match("^GamepadBar%.") and (name:match(":Set") or name:match(":Clear"))), "a game bar frame was changed in a fight: " .. name)
    end
    eq(#c.blocked, 0, "a blocked action")
    c:assertClean()
end)

test("face: without the active-bar callback the main bar shows (the nothing-held state)", function()
    local c, PE, Face = started({ setup = function(cl)
        rawset(cl.env.GamepadMainActionBarFrame.PageUnit, "RegisterActiveActionBarUpdatedCallback", nil)
    end })
    checkState(c, Face, REST, "no callback")
    c:assertClean()
end)

test("face: GetActiveBar raising or missing: the main bar shows, no error", function()
    local c, PE, Face = started({ setup = function(cl) cl.world.activeBarError = true end })
    checkState(c, Face, REST, "raising")
    c:pressTriggers(true, false)
    c:advance(0.1)
    checkState(c, Face, REST, "raising, LT held")
    c:assertClean()
    local c2, PE2, Face2 = started({ setup = function(cl) rawset(cl.env.GamepadMainActionBarFrame.PageUnit, "GetActiveBar", nil) end })
    checkState(c2, Face2, REST, "missing")
    c2:assertClean()
end)

test("face: a page change re-reads every picture", function()
    local c, PE, Face = started()
    c.world.actions[101] = { texture = 9001, duration = 0, count = "" }
    c:setPage(2)
    eq(st(c, pic(Face, 1, 1).icon).texture, 135274, "not before the next frame")
    c:advance(0.1)
    eq(st(c, pic(Face, 1, 1).icon).texture, 9001)
    eq(pic(Face, 1, 2).empty, true, "slot 102 holds nothing")
    eq(onUpdates(c), 0)
end)

test("face: hidden while the game hides its bars (binding editor, Gamepad UI off)", function()
    local c, PE, Face = started()
    local holder = holderOf(c, Face)
    eq(holder:IsShown(), true)
    c.env.GamepadMainActionBarFrame:Hide()
    eq(holder:IsShown(), false)
    c.env.GamepadMainActionBarFrame:Show()
    eq(holder:IsShown(), true)
    c:assertClean()
end)

test("face: started while the game's bars are hidden, the pictures wait for them", function()
    local c, PE, Face = new({ setup = function(cl) cl.env.GamepadMainActionBarFrame:Hide() end })
    eq(Face:Start(), true)
    local holder = holderOf(c, Face)
    eq(holder:IsShown(), false)
    c.env.GamepadMainActionBarFrame:Show()
    eq(holder:IsShown(), true)
end)

test("face: something else setting an anchor's see-through while on gets 0 back; after Stop it stays", function()
    local c, PE, Face = started()
    local top = anchor(c, "TopCenteredAnchor")
    top:SetAlpha(1)
    eq(alphaOf(c, top), 0)
    Face:Stop()
    eq(alphaOf(c, top), 1)
    top:SetAlpha(0.7)
    eq(alphaOf(c, top), 0.7)
    c:assertClean()
end)

test("face: Stop puts the bars back, hides the pictures, drops the events, and the hooks go idle", function()
    local c, PE, Face = started()
    local hooks = hookCount(c)
    c:fire("SPELL_UPDATE_COOLDOWN") -- an update waiting
    Face:Stop()
    for _, key in ipairs(ANCHORS) do eq(alphaOf(c, anchor(c, key)), 1, key) end
    local holder = holderOf(c, Face)
    eq(holder:IsShown(), false)
    eq(onUpdates(c), 0, "the waiting update was dropped")
    for _, rec in ipairs(faceFrames(c)) do eq(next(rec.events), nil, "events left on a frame") end
    eq(Face:Status(), nil)
    -- Everything the hooks watch changes: nothing runs.
    local calls = #c.cdCalls
    c:setAction(1, { texture = 1, duration = 3, count = "2" })
    c.barButtons.TopCenteredAnchor[1].icon:SetVertexColor(0.4, 0.4, 0.4)
    c:spellAlert(c.barButtons.TopCenteredAnchor[1], true)
    c:pressTriggers(true, false)
    c:setPage(2)
    eq(onUpdates(c), 0)
    c:advance(1)
    eq(#c.cdCalls, calls)
    -- Started again: the same hooks (none added), the bars invisible again.
    eq(Face:Start(), true)
    eq(hookCount(c), hooks, "hooks are installed once")
    eq(alphaOf(c, anchor(c, "TopCenteredAnchor")), 0)
    eq(holder:IsShown(), true)
    c:assertClean()
end)

test("face: Stop in a fight puts the bars back at once", function()
    local c, PE, Face = started()
    c:enterCombat()
    Face:Stop()
    for _, key in ipairs(ANCHORS) do eq(alphaOf(c, anchor(c, key)), 1, key) end
    c:assertClean()
end)

test("face: Start twice keeps one set of pictures", function()
    local c, PE, Face = started()
    local frames, hooks = #faceFrames(c), hookCount(c)
    eq(Face:Start(), true)
    c:advance(0.1)
    eq(#faceFrames(c), frames)
    eq(hookCount(c), hooks)
end)

test("face: Start in a fight waits (the game's bars stay, no reason is kept)", function()
    local c, PE, Face = new()
    c:enterCombat()
    local ok, why = Face:Start()
    eq(ok, false)
    eq(why, "waiting for the fight to end")
    eq(Face:Status(), nil)
    eq(#faceFrames(c), 0)
    eq(alphaOf(c, anchor(c, "TopCenteredAnchor")), 1)
end)

---------------------------------------------------------------------------
-- When the face cannot work
---------------------------------------------------------------------------

local function refused(opts, reason, what)
    local c, PE, Face = new(opts)
    local ok, why = Face:Start()
    eq(ok, false, what)
    eq(why, reason, what)
    eq(Face:Status(), reason, what)
    for _, key in ipairs(ANCHORS) do
        local a = c.barParts[c.barParts[c.env.GamepadMainActionBarFrame].PageUnit or {}]
        if a and a[key] then eq(alphaOf(c, a[key]), 1, what .. ": " .. key .. " stays visible") end
    end
    c:assertClean(what)
    return c, PE, Face
end

test("face: not built when the bars, the buttons or the cooldown call are missing; the bars stay", function()
    refused({ setup = function(cl) cl.barParts[cl.env.GamepadMainActionBarFrame].PageUnit = nil end }, TEXT_NO_BARS, "no PageUnit")
    refused({ setup = function(cl)
        local bar = cl.env.GamepadMainActionBarFrame.PageUnit.RightCenteredAnchor.Bar
        rawset(bar, "GetActionButtonByIndex", function() return nil end)
    end }, TEXT_NO_BUTTONS, "no buttons")
    refused({ setup = function(cl) rawset(cl.env.C_ActionBar, "GetActionCooldownDuration", nil) end }, TEXT_NO_COOLDOWN, "no duration call")
    local c = refused({ setup = function(cl) cl.world.noCooldownFrames = true end }, TEXT_NO_COOLDOWN, "no Cooldown frames")
    -- Not tried again: the same reason, still no pictures showing.
    local Face = c.PE.FaceBars
    eq(select(2, Face:Start()), TEXT_NO_COOLDOWN)
    for _, rec in ipairs(faceFrames(c)) do
        -- (the one frame with no parent is the event frame, which draws nothing)
        check(rec.parent == nil or not rec.frame:IsVisible(), "a picture frame is showing")
    end
end)

test("face: the bars' own button list is used when GetActionButtonByIndex is missing", function()
    local c, PE, Face = started({ setup = function(cl)
        for _, key in ipairs(ANCHORS) do rawset(cl.env.GamepadMainActionBarFrame.PageUnit[key].Bar, "GetActionButtonByIndex", nil) end
    end })
    eq(pic(Face, 1, 1).button, c.barButtons.TopCenteredAnchor[1])
    c:assertClean()
end)

test("face: without CooldownFrameTemplate a plain Cooldown frame is used", function()
    local c, PE, Face = started({ setup = function(cl) cl.world.noCooldownTemplate = true end })
    eq(st(c, pic(Face, 1, 2).cd).cooldown.duration, 8)
    c:assertClean()
end)

test("face: Stop clears a not-built reason", function()
    local c, PE, Face = refused({ setup = function(cl) rawset(cl.env.C_ActionBar, "GetActionCooldownDuration", nil) end }, TEXT_NO_COOLDOWN, "no duration call")
    Face:Stop()
    eq(Face:Status(), nil)
end)

test("face: after 3 errors the pictures turn off, the bars come back, one chat line, Start refused", function()
    local c, PE, Face = started()
    rawset(pic(Face, 1, 1).icon, "SetVertexColor", function() error("broken picture") end)
    local real = c.barButtons.TopCenteredAnchor[1]
    for i = 1, 2 do
        real.icon:SetVertexColor(0.5, 0.5, 0.5)
        c:advance(0.1)
        eq(Face:Status(), nil, "still on after error " .. i)
        eq(alphaOf(c, anchor(c, "TopCenteredAnchor")), 0)
    end
    real.icon:SetVertexColor(0.5, 0.5, 0.5)
    c:advance(0.1)
    eq(Face:Status(), TEXT_ERROR)
    for _, key in ipairs(ANCHORS) do eq(alphaOf(c, anchor(c, key)), 1, key) end
    eq(holderOf(c, Face):IsShown(), false)
    local lines = 0
    for _, line in ipairs(T.chatLines(c)) do if line == CHAT_ERROR then lines = lines + 1 end end
    eq(lines, 1)
    local ok, why = Face:Start()
    eq({ ok, why }, { false, TEXT_ERROR })
    Face:Stop()
    eq(Face:Status(), TEXT_ERROR, "the reason stays until a reload")
    check(#PE.errors > 0 and PE.errors[1].module == "ctrlLayout", "the errors are in the log under Controller layout")
end)

---------------------------------------------------------------------------
-- A difficult game: each call missing, nil, raising, secret
---------------------------------------------------------------------------

test("face: cooldown calls that raise, return nil or are refused clear the sweep without an error", function()
    for _, case in ipairs({
        { what = "duration raises", set = function(w) w.durationFails = true end },
        { what = "duration nil", set = function(w) w.durationNil = true end },
        { what = "duration object refused", set = function(w) w.durationObjectRefused = true end },
    }) do
        local c, PE, Face = started()
        eq(shown(c, pic(Face, 1, 2).cd), true, case.what .. ": on cooldown first")
        case.set(c.world)
        c:fire("ACTIONBAR_UPDATE_COOLDOWN")
        c:advance(0.1)
        eq(shown(c, pic(Face, 1, 2).cd), false, case.what)
        eq(cdCalls(c, "SetCooldown"), 0, case.what)
        c:assertClean(case.what)
    end
end)

test("face: a secret or missing GetActionCooldown answer leaves the icon undarkened", function()
    local c, PE, Face = started({ setup = function(cl) cl.world.cooldownInfoSecret = true end })
    eq(shown(c, pic(Face, 1, 2).dim), false)
    eq(shown(c, pic(Face, 1, 2).cd), true, "the sweep still comes from the duration object")
    c:assertClean()
    local c2, PE2, Face2 = started({ setup = function(cl) rawset(cl.env.C_ActionBar, "GetActionCooldown", nil) end })
    eq(shown(c2, pic(Face2, 1, 2).dim), false)
    c2:assertClean()
end)

test("face: a secret colour shows white; a texture that cannot be read shows the empty picture", function()
    local c, PE, Face = started()
    local real = c.barButtons.TopCenteredAnchor[1]
    c.world.secrets[0.25] = true
    real.icon:SetVertexColor(0.25, 0.25, 0.25)
    c:advance(0.1)
    eq(st(c, pic(Face, 1, 1).icon).vertexColor, { 1, 1, 1, 1 })
    rawset(real.icon, "GetTexture", function() error("no texture now") end)
    real.icon:SetTexture(1234)
    c:advance(0.1)
    eq(pic(Face, 1, 1).empty, true)
    c:assertClean()
end)

test("face: a secret texture is passed on as it is", function()
    local c, PE, Face = started()
    local secret = 424242
    c.world.secrets[secret] = true
    c.barButtons.TopCenteredAnchor[1].icon:SetTexture(secret)
    c:advance(0.1)
    eq(st(c, pic(Face, 1, 1).icon).texture, secret)
    eq(pic(Face, 1, 1).empty, false)
    c:assertClean()
end)

test("face: GetChecked secret, raising or missing: not checked", function()
    local c, PE, Face = started()
    local real = c.barButtons.TopCenteredAnchor[1]
    local secret = {}
    c.world.secrets[secret] = true
    for _, fn in ipairs({ function() return secret end, function() error("no") end }) do
        rawset(real, "GetChecked", fn)
        c:fire("ACTIONBAR_UPDATE_STATE")
        c:advance(0.1)
        eq(shown(c, pic(Face, 1, 1).checked), false)
    end
    c:assertClean()
end)

test("face: the alert manager missing or raising: no glow, no error", function()
    local c, PE, Face = started({ setup = function(cl) rawset(cl.env, "ActionButtonSpellAlertManager", nil) end })
    eq(shown(c, pic(Face, 1, 1).glow), false)
    c:assertClean()
    local c2, PE2, Face2 = started()
    rawset(c2.env.ActionButtonSpellAlertManager, "HasAlert", function() error("no") end)
    c2:spellAlert(c2.barButtons.TopCenteredAnchor[1], true)
    c2:advance(0.1)
    eq(shown(c2, pic(Face2, 1, 1).glow), false)
    c2:assertClean()
end)

test("face: SetCurrentPage missing: it still starts", function()
    local c, PE, Face = started({ setup = function(cl) rawset(cl.env.GamepadMainActionBarFrame.PageUnit, "SetCurrentPage", nil) end })
    eq(Face:Status(), nil)
    c:assertClean()
end)

test("face: the possess bar's pet buttons (no action slot, no UpdateAction) show without a cooldown", function()
    local c, PE, Face = started()
    c:showOverrideBar("possessBar", "TopCenteredAnchor")
    c:advance(0.1)
    local possess = c.actionBars.possessBar
    eq(pic(Face, 1, 1).button, possess:GetActionButtonByIndex(1))
    eq(pic(Face, 1, 1).empty, true)
    eq(shown(c, pic(Face, 1, 1).cd), false)
    c:assertClean()
end)

test("face: the contract's numbers come from PE.LayoutPlan when it has them", function()
    local c, PE, Face = new()
    local plan = PE.LayoutPlan
    rawset(plan, "FACE", { button = 20, dx = 25, dy = 15 })
    rawset(plan, "FaceSpots", function() return {
        inner = { left = { x = -100, y = 50 }, right = { x = 100, y = 50 } },
        outer = { left = { x = -200, y = 50 }, right = { x = 200, y = 50 } },
    } end)
    rawset(plan, "FaceStates", function() return {
        rest = { { group = "rt", half = "face", spot = "outerLeft", quiet = true } },
        lt = {}, rt = {}, both = {},
    } end)
    eq(Face:Start(), true)
    local _, _, _, x, y = pic(Face, 1, 1).frame:GetPoint(1)
    eq({ x, y }, { -25, 0 })
    near(pic(Face, 1, 1).frame:GetWidth(), 20)
    local f = half(Face, 3, 2)
    eq(f:IsShown(), true)
    local _, _, _, hx, hy = f:GetPoint(1)
    eq({ hx, hy }, { -200, 50 })
    near(alphaOf(c, f), 0.3)
    eq(half(Face, 1, 1):IsShown(), false)
    c:assertClean()
end)

test("face: an unusable FaceStates or FaceSpots answer falls back to the built-in copies", function()
    for _, case in ipairs({
        { what = "states missing", set = function(plan) rawset(plan, "FaceStates", nil) end },
        { what = "states with an unknown spot", set = function(plan) rawset(plan, "FaceStates", function()
            return { rest = { { group = "main", half = "dpad", spot = "middle" } }, lt = {}, rt = {}, both = {} } end) end },
        { what = "states raising", set = function(plan) rawset(plan, "FaceStates", function() error("no") end) end },
        { what = "spots with the old 0.13.0 shape", set = function(plan) rawset(plan, "FaceSpots", function()
            return { main = { dpad = { x = -199, y = 39 }, face = { x = 199, y = 39 } } } end) end },
    }) do
        local c, PE, Face = new()
        case.set(PE.LayoutPlan)
        eq(Face:Start(), true, case.what)
        checkState(c, Face, REST, case.what)
        c:pressTriggers(false, true)
        c:advance(0.1)
        checkState(c, Face, RT, case.what .. ", RT")
        c:assertClean(case.what)
    end
end)

---------------------------------------------------------------------------
-- Taps between the pictures (the frames under them)
---------------------------------------------------------------------------

-- A frame's rectangle { left, bottom, right, top } from the screen's bottom centre;
-- the frames under the pictures are set by their BOTTOMLEFT on UIParent's BOTTOM.
local function rectOf(f)
    local point, rel, relPoint, x, y = f:GetPoint(1)
    check(point == "BOTTOMLEFT" and relPoint == "BOTTOM", "placed by BOTTOMLEFT on BOTTOM, got " .. tostring(point) .. " " .. tostring(relPoint))
    return { x, y, x + f:GetWidth(), y + f:GetHeight() }
end

local function inside(inner, outer)
    local e = 1e-6
    return inner[1] >= outer[1] - e and inner[2] >= outer[2] - e and inner[3] <= outer[3] + e and inner[4] <= outer[4] + e
end

local function overlaps(a, b)
    return math.min(a[3], b[3]) - math.max(a[1], b[1]) > 1e-6 and math.min(a[4], b[4]) - math.max(a[2], b[2]) > 1e-6
end

-- Every rectangle of the game's that takes a tap under the face, worked out from
-- Blizzard's numbers rather than ours: each real bar (208 by 68, enableMouse,
-- Blizzard_GamepadActionBars/ActionBarTemplates.xml:606-699; ActionBarStyles.lua:172)
-- at 60%, centred at x -170 (main, LT) and +170 (RT, LT+RT), 87 (main, RT) and 45 (LT,
-- LT+RT) up, and its eight buttons where the collapsed style puts them
-- (ActionBarStyles.lua:158-195: the d-pad group square, 32; the face group round, 30).
local function realTapRects()
    local out = {}
    local s = 0.6
    local buttons = {
        { -92, 0, 32 }, { -58, 17, 32 }, { -24, 0, 32 }, { -58, -17, 32 },
        { 25, 0, 30 }, { 55, 18, 30 }, { 85, 0, 30 }, { 55, -18, 30 },
    }
    for _, bar in ipairs({ { "main", -170, 87 }, { "LT", -170, 45 }, { "RT", 170, 87 }, { "LT+RT", 170, 45 } }) do
        local cx, cy = bar[2], bar[3]
        out[#out + 1] = { name = bar[1] .. " bar", r = { cx - 104 * s, cy - 34 * s, cx + 104 * s, cy + 34 * s } }
        for i, b in ipairs(buttons) do
            local x, y, h = cx + b[1] * s, cy + b[2] * s, b[3] / 2 * s
            out[#out + 1] = { name = bar[1] .. " button " .. i, r = { x - h, y - h, x + h, y + h } }
        end
    end
    return out
end

-- The pieces the frames under the pictures must leave alone: the map, the two
-- sub-menu buttons (138 either side, 188 up, about 19 round), the LB / RB targeting
-- pictures (76 to 112 either side, 128 to 160 up), the outer diamonds (249 to 383
-- either side, 17 to 115 up: their pictures take a tap themselves) and the player
-- and target frames (from 395 either side outwards).
local KEEP_CLEAR = {
    { name = "LB+LT button", r = { -138 - 19, 188 - 19, -138 + 19, 188 + 19 } },
    { name = "RB+RT button", r = { 138 - 19, 188 - 19, 138 + 19, 188 + 19 } },
    { name = "LB targeting picture", r = { -112, 128, -76, 160 } },
    { name = "RB targeting picture", r = { 76, 128, 112, 160 } },
    { name = "outer left diamond", r = { -383, 17, -249, 115 } },
    { name = "outer right diamond", r = { 249, 17, 383, 115 } },
    { name = "player frame", r = { -395 - 232, 56, -395, 156 } },
    { name = "target frame", r = { 395, 56, 395 + 232, 156 } },
}

local function checkBacking(c, PE, Face, what)
    eq(#Face.backing, 2, what .. ": two frames, one per side")
    local holder = holderOf(c, Face)
    local lowestPicture = math.huge
    for g = 1, 4 do
        for h = 1, 2 do lowestPicture = math.min(lowestPicture, half(Face, g, h):GetFrameLevel()) end
        for n = 1, 8 do lowestPicture = math.min(lowestPicture, pic(Face, g, n).frame:GetFrameLevel()) end
    end
    local rects = {}
    for side, f in ipairs(Face.backing) do
        local rec = st(c, f)
        eq(rec.parent, holder, what .. ": in the holder")
        eq(rec.mouse, true, what .. ": takes a tap")
        eq(f:GetFrameStrata(), "MEDIUM", what .. ": the pictures' strata")
        check(f:GetFrameLevel() < lowestPicture, what .. ": under the pictures")
        eq(#rec.regions, 0, what .. ": draws nothing")
        for name in pairs(rec.scripts) do error(what .. ": the frame under the pictures has a " .. name .. " script") end
        check(f:IsVisible(), what .. ": shown with the pictures")
        rects[side] = rectOf(f)
    end
    -- Every real bar and button, whole (the d-pad's left button pokes 4.8 past its bar,
    -- -170 - 108 * 0.6 = -234.8, still inside the inner diamond's -237).
    for _, t in ipairs(realTapRects()) do
        check(inside(t.r, rects[1]) or inside(t.r, rects[2]), what .. ": " .. t.name .. " is not under a frame of ours that takes a tap")
    end
    local clear = {}
    for _, k in ipairs(KEEP_CLEAR) do clear[#clear + 1] = k end
    for name, r in pairs(PE.LayoutPlan.Rects()) do
        if name ~= "inner left diamond" and name ~= "inner right diamond" then clear[#clear + 1] = { name = name, r = r } end
    end
    for side, r in ipairs(rects) do
        for _, k in ipairs(clear) do
            check(not overlaps(r, k.r), what .. ": the frame on side " .. side .. " covers the " .. k.name)
        end
    end
    return rects
end

test("face: a tap between the pictures never reaches a hidden button; the frames under them clear the map, sub-menus, targeting pictures, outer diamonds and unit frames", function()
    local c, PE, Face = started()
    local rects = checkBacking(c, PE, Face, "with the layout's numbers")
    -- The inner diamond (with the main and LT bars under it), 4 more each way; the right side its mirror.
    for i, want in ipairs({ -241, 13, -99, 119 }) do near(rects[1][i], want, "left " .. i) end
    for i, want in ipairs({ 99, 13, 241, 119 }) do near(rects[2][i], want, "right " .. i) end
    -- The frames under the pictures stay put whatever trigger is held.
    for _, held in ipairs({ { true, false }, { false, true }, { true, true } }) do
        c:pressTriggers(held[1], held[2])
        c:advance(0.1)
        for side = 1, 2 do for i = 1, 4 do near(rectOf(Face.backing[side])[i], rects[side][i], "held " .. side .. "/" .. i) end end
    end
    c:assertClean()
    -- Without ControllerLayout's numbers the fallback gives the same frames and states.
    local c2, PE2, Face2 = new()
    rawset(PE2.LayoutPlan, "RealBarRects", nil)
    rawset(PE2.LayoutPlan, "FaceSpots", nil)
    rawset(PE2.LayoutPlan, "FaceStates", nil)
    rawset(PE2.LayoutPlan, "FACE", nil)
    eq(Face2:Start(), true)
    local rects2 = checkBacking(c2, PE2, Face2, "with the fallback numbers")
    for side = 1, 2 do for i = 1, 4 do near(rects2[side][i], rects[side][i], "fallback " .. side .. "/" .. i) end end
    checkState(c2, Face2, REST, "fallback rest")
    c2:pressTriggers(true, false)
    c2:advance(0.1)
    checkState(c2, Face2, LT, "fallback LT")
    for _, n in ipairs({ 1, 8 }) do near(pic(Face2, 1, n).frame:GetWidth(), 42, "fallback picture size") end
    c2:assertClean()
end)

test("face: the frames under the pictures hide with them", function()
    local c, PE, Face = started()
    c.env.GamepadMainActionBarFrame:Hide()
    for _, f in ipairs(Face.backing) do eq(f:IsVisible(), false) end
    c.env.GamepadMainActionBarFrame:Show()
    for _, f in ipairs(Face.backing) do eq(f:IsVisible(), true) end
    Face:Stop()
    for _, f in ipairs(Face.backing) do eq(f:IsVisible(), false) end
end)

---------------------------------------------------------------------------
-- Cooldown looks
---------------------------------------------------------------------------

test("face: our cooldowns draw no star flash and no edge, as the game's buttons", function()
    for _, opts in ipairs({ {}, { setup = function(cl) cl.world.noCooldownTemplate = true end } }) do
        local c, PE, Face = started(opts)
        for g = 1, 4 do
            for n = 1, 8 do
                local rec = st(c, pic(Face, g, n).cd)
                eq(rec.drawBling, false, "star flash on " .. g .. "/" .. n)
                eq(rec.drawEdge, false, "edge on " .. g .. "/" .. n)
            end
        end
        c:assertClean()
    end
end)

-- Counts C_ActionBar.GetActionCooldown calls; returns a function giving the count so far.
local function countCooldownReads(c)
    local api = c.env.C_ActionBar
    local orig = rawget(api, "GetActionCooldown")
    local n = 0
    rawset(api, "GetActionCooldown", function(...) n = n + 1 return orig(...) end)
    return function() return n end
end

test("face: the darkening is read inside SPELL_UPDATE_COOLDOWN; the next frame only shows it", function()
    local c, PE, Face = started()
    local p1 = pic(Face, 1, 1)
    local reads = countCooldownReads(c)
    eq(shown(c, p1.dim), false)
    -- ACTIONBAR_UPDATE_COOLDOWN: the sweep again, the darkening not read.
    c.world.actions[1].duration = 5
    c:fire("ACTIONBAR_UPDATE_COOLDOWN")
    c:advance(0.1)
    eq(st(c, p1.cd).cooldown.duration, 5, "the sweep follows")
    eq(shown(c, p1.dim), false, "not read outside SPELL_UPDATE_COOLDOWN")
    eq(reads(), 0, "no GetActionCooldown on a flush outside the event")
    -- SPELL_UPDATE_COOLDOWN: read at once, in the handler.
    c:fire("SPELL_UPDATE_COOLDOWN")
    local inEvent = reads()
    check(inEvent > 0, "GetActionCooldown not read in the event")
    -- What the game says after the event does not count: the frame shows what was read.
    c.world.actions[1].duration = 0
    c:advance(0.1)
    eq(reads(), inEvent, "the flush only shows what was read")
    eq(shown(c, p1.dim), true)
    -- The global cooldown alone: the sweep runs, no darkening.
    c.world.actions[1].duration, c.world.actions[1].gcd = 1.5, true
    c:fire("SPELL_UPDATE_COOLDOWN")
    c:advance(0.1)
    eq(shown(c, p1.cd), true)
    eq(shown(c, p1.dim), false, "the global cooldown alone does not darken")
    c:assertClean()
end)

test("face: the darkening ends when our cooldown frame says the cooldown is done, not at the next cast", function()
    local c, PE, Face = started()
    local p2 = pic(Face, 1, 2)
    eq(shown(c, p2.dim), true, "slot 2 is on cooldown (8 s)")
    -- The cooldown runs out: no SPELL_UPDATE_COOLDOWN comes (that fires when one starts).
    c.world.actions[2].duration = 0
    c._runScript(p2.cd, "OnCooldownDone")
    eq(shown(c, p2.dim), true, "not before the next frame")
    eq(onUpdates(c), 1, "one OnUpdate waiting")
    c:advance(0.1)
    eq(shown(c, p2.dim), false, "still dark after its cooldown ended")
    eq(onUpdates(c), 0)
    -- While stopped it does nothing.
    Face:Stop()
    c._runScript(p2.cd, "OnCooldownDone")
    eq(onUpdates(c), 0, "an OnUpdate while stopped")
    c:assertClean()
end)

test("face: a slot whose icon turns into another spell reads that spell's cooldown again", function()
    local c, PE, Face = started()
    local p1 = pic(Face, 1, 1)
    eq(shown(c, p1.dim), false)
    local before = cdCalls(c, "SetCooldownFromDurationObject")
    -- The game puts another spell in slot 1 (on cooldown) and only changes the icon.
    c.world.actions[1].duration, c.world.actions[1].texture = 6, 999
    c.barButtons.TopCenteredAnchor[1].icon:SetTexture(999)
    c:advance(0.1)
    eq(st(c, p1.icon).texture, 999)
    check(cdCalls(c, "SetCooldownFromDurationObject") > before, "the sweep was not read again")
    eq(st(c, p1.cd).cooldown.duration, 6)
    eq(shown(c, p1.dim), true, "the new spell's cooldown not read")
    -- The same icon again (a colour change): nothing read.
    local calls = cdCalls(c, "SetCooldownFromDurationObject")
    c.barButtons.TopCenteredAnchor[1].icon:SetVertexColor(0.5, 0.5, 0.5)
    c:advance(0.1)
    eq(cdCalls(c, "SetCooldownFromDurationObject"), calls, "a colour change read the cooldown")
    c:assertClean()
end)

test("face: a secret or missing isActive / isOnGCD reads as not darkened", function()
    local c, PE, Face = started()
    local secret = {}
    c.world.secrets[secret] = true
    local api = c.env.C_ActionBar
    for _, case in ipairs({
        { what = "isActive secret", info = { isActive = secret, isOnGCD = false } },
        { what = "isActive missing", info = { isOnGCD = false } },
        { what = "raises", raise = true },
    }) do
        rawset(api, "GetActionCooldown", function()
            if case.raise then error("no") end
            return case.info
        end)
        c:fire("SPELL_UPDATE_COOLDOWN")
        c:advance(0.1)
        eq(shown(c, pic(Face, 1, 2).dim), false, case.what)
    end
    -- isOnGCD secret: only isActive counts.
    rawset(api, "GetActionCooldown", function() return { isActive = true, isOnGCD = secret } end)
    c:fire("SPELL_UPDATE_COOLDOWN")
    c:advance(0.1)
    eq(shown(c, pic(Face, 1, 2).dim), true, "isOnGCD secret")
    c:assertClean()
end)

---------------------------------------------------------------------------
-- Only the part that changed is copied
---------------------------------------------------------------------------

-- Counts calls to a method of a Blizzard region or frame (wrapped in place).
local function counter(obj, name)
    local orig = obj[name]
    local n = 0
    rawset(obj, name, function(...) n = n + 1 return orig(...) end)
    return function() return n end
end

local function watchButton(b)
    return {
        checked = counter(b, "GetChecked"),
        icon = counter(b.icon, "GetTexture"),
        count = counter(b.Count, "GetText"),
        range = counter(b.RangeIndicator, "IsShown"),
    }
end

local function counts(w)
    return { checked = w.checked(), icon = w.icon(), count = w.count(), range = w.range() }
end

test("face: UpdateState on a button reads only its checked state", function()
    local c, PE, Face = started()
    local b1, b2 = c.barButtons.TopCenteredAnchor[1], c.barButtons.TopCenteredAnchor[2]
    local w1, w2 = watchButton(b1), watchButton(b2)
    local cd = #c.cdCalls
    b1:UpdateState()
    c:advance(0.1)
    eq(counts(w1), { checked = 1, icon = 0, count = 0, range = 0 })
    eq(counts(w2), { checked = 0, icon = 0, count = 0, range = 0 })
    eq(#c.cdCalls, cd, "no cooldown work")
    c:assertClean()
end)

test("face: a real icon's colour re-copies only that icon; the count and range dot alone likewise", function()
    local c, PE, Face = started()
    local b1, b2 = c.barButtons.TopCenteredAnchor[1], c.barButtons.TopCenteredAnchor[2]
    local w1, w2 = watchButton(b1), watchButton(b2)
    local p1 = pic(Face, 1, 1)
    local setTexture = counter(p1.icon, "SetTexture")
    local cd = #c.cdCalls
    b1.icon:SetVertexColor(0.5, 0.5, 1)
    c:advance(0.1)
    eq(counts(w1), { checked = 0, icon = 1, count = 0, range = 0 })
    eq(counts(w2), { checked = 0, icon = 0, count = 0, range = 0 })
    eq(st(c, p1.icon).vertexColor, { 0.5, 0.5, 1, 1 })
    eq(setTexture(), 0, "the texture is the same: not set again")
    eq(#c.cdCalls, cd, "no cooldown work")
    -- A new texture is set once.
    b1.icon:SetTexture(31337)
    c:advance(0.1)
    eq(setTexture(), 1)
    eq(st(c, p1.icon).texture, 31337)
    -- The count text alone.
    b1.Count:SetText("3")
    c:advance(0.1)
    eq(counts(w1), { checked = 0, icon = 2, count = 1, range = 0 })
    eq(p1.count:GetText(), "3")
    -- The range dot alone.
    c:setRange(b1, true, false)
    c:advance(0.1)
    local after = counts(w1)
    eq({ after.checked, after.icon, after.count }, { 0, 2, 1 })
    check(after.range > 0, "the range dot was not read")
    eq(shown(c, p1.range), true)
    c:assertClean()
end)

---------------------------------------------------------------------------
-- While the game hides its bars
---------------------------------------------------------------------------

test("face: while the game hides its bars nothing is drawn; all is drawn again when they come back", function()
    local c, PE, Face = started()
    local root = c.env.GamepadMainActionBarFrame
    local p1, p2 = pic(Face, 1, 1), pic(Face, 1, 2)
    root:Hide()
    local reads = countCooldownReads(c)
    local cd = #c.cdCalls
    c:setAction(1, { texture = 5555, duration = 4, count = "" })
    c.world.actions[2].duration = 0
    c:fire("SPELL_UPDATE_COOLDOWN")
    c:fire("ACTIONBAR_UPDATE_STATE")
    c:pressTriggers(true, false)
    eq(onUpdates(c), 0, "nothing waits for a frame while hidden")
    c:advance(0.5)
    eq(st(c, p1.icon).texture, 135274, "not drawn while hidden")
    eq(#c.cdCalls, cd, "no cooldown work while hidden")
    eq(reads(), 0, "the darkening is not read while hidden")
    root:Show()
    eq(st(c, p1.icon).texture, 5555, "drawn at once when the bars come back")
    eq(st(c, p1.cd).cooldown.duration, 4)
    eq(shown(c, p1.dim), true)
    eq(shown(c, p2.dim), false)
    checkState(c, Face, LT, "LT active")
    eq(onUpdates(c), 0)
    c:assertClean()
end)

test("face: started while the whole interface is hidden, the pictures wait for it (IsVisible)", function()
    local c, PE, Face = new()
    c.UIParent:Hide()
    eq(Face:Start(), true)
    local holder = holderOf(c, Face)
    eq(holder:IsShown(), false)
    c.UIParent:Show()
    eq(holder:IsShown(), true)
    eq(st(c, pic(Face, 1, 1).icon).texture, 135274)
    c:assertClean()
end)

return { known = KNOWN_FAILURES }
