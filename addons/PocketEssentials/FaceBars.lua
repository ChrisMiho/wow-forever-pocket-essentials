local ADDON_NAME, PE = ...

-- Face bars: our own spell pictures for the game's four controller bars
-- (Controller layout 0.13.0, spec 2026-11-23-controller-layout-0.13.0-face-bars.md;
-- the Blizzard facts are cited line by line below).
--
-- The game's real bars stay whole and keep taking every press; they are made
-- invisible by setting their four anchors' see-through to 0, and this file draws
-- one picture per real button where the layout wants it.
--
-- 0.14.0 (spec 2026-11-23-controller-layout-0.14.0-console.md): each bar's two halves
-- (d-pad, face buttons) are two frames of our own, each holding its four pictures placed
-- on its centre. Which halves show, where and how see-through follows the trigger held
-- (ControllerLayout.lua, Plan.FaceStates): at rest only the main bar, its d-pad diamond
-- inner-left of the map and its face diamond inner-right; holding a trigger opens that
-- trigger's bar into two diamonds on its side and leaves the other side's main diamond
-- quiet. The swap is ClearAllPoints, SetPoint, Show, Hide and SetAlpha on those plain
-- frames only, which a fight allows; no frame of the game's is touched by it.
--
--   PE.FaceBars:Start(whenOff, size, useHook)  out of a fight; builds once, binds to the
--                         real buttons, shows the pictures, then makes the real bars
--                         invisible. Returns true, or false and a plain reason.
--                         whenOff (optional) is called when the safety net below
--                         turns the pictures off later (the real bars show again).
--                         size (optional): the Spell panel size in percent (80, 90,
--                         100, 110 or 120; anything else 100), used by the first
--                         Start, which builds; a change applies after a reload.
--                         useHook (optional, true or not): how the active bar is
--                         followed, see "The active bar" below; also the first Start's.
--   PE.FaceBars:Stop()    any time, also in a fight: the real bars back to full
--                         strength, the pictures hidden, events dropped.
--   PE.FaceBars:Status()  nil while fine or stopped; else why the game's own bars
--                         are showing.
--
-- It is part of Controller layout (error key "ctrlLayout") and has no switch of its
-- own. Nothing is made, hooked or registered until the first Start. While stopped
-- no event is registered and nothing ticks; the hooks (each installed once, as
-- hooksecurefunc and HookScript cannot be taken off) return at once. While started
-- every hook and event only marks what changed (on one picture, only the part that
-- changed: its icon, range dot, count, checked or glow), and one OnUpdate on the next
-- frame does the work and removes itself. No timer of our own. While the game hides
-- its bars nothing is drawn; everything is drawn again when they come back.
--
-- Display only: plain frames on UIParent, no secure templates, no click handler.
-- Each picture takes the mouse, and under the pictures one plain frame per side
-- takes the mouse over that side's inner diamond and both real bars under it, so a
-- tap between two pictures (or the game's cursor) never reaches a hidden button
-- (the outer diamonds have no real bar under them): the real bars take taps at
-- see-through 0 (enableMouse,
-- G/ActionBarTemplates.xml:606-699). Nothing is ever written into Blizzard's tables or
-- frames except the four anchors' see-through (SetAlpha is not a protected call:
-- device-proven on the bars in the Pocket Probe tests of 2026-11-23) and the hooks.
--
-- Where the numbers come from (paths under Interface/AddOns/ of the forever branch;
-- G/ = Blizzard_GamepadActionBars/, AB/ = Blizzard_ActionBar/Shared/,
-- DOC/ = Blizzard_APIDocumentationGenerated/):
--   * PageUnit and its four anchors, each with a .Bar: G/MainActionBarFrame.xml:12,
--     G/ActionBarTemplates.xml:600-706. PageUnit.actionBars (the four bars, the
--     possess and stance bars, the targeting bars): G/PageUnit.lua:108-121. The
--     stance and possess bars re-parent themselves to the anchor of the bar they
--     replace (G/GamepadOverrideBarMixin.lua:59-64) and the targeting bars sit on
--     the top anchor (G/PageUnit.lua:136-149), so the bar shown in an anchor is the
--     one to draw.
--   * A bar's eight buttons in press order, bar:GetActionButtonByIndex(1..8)
--     (G/ActionBar.lua:296, the same list as bar.actionButtons, :7-20): 1-4 the
--     d-pad left, up, right, down; 5-8 the face buttons X left, Y up, B right,
--     A down (G/ActionBarTemplates.xml:165-305, G/ActionBarButton.lua:32-52).
--   * What a button shows: its icon (button.icon, colour and greying written by
--     AB/ActionButton.lua:574, 633-635, 721-734), its Count text (:852-854), its
--     RangeIndicator dot (G/ActionBarButton.lua:533-564, a FontString,
--     G/ActionBarButton.xml:78), checked (GetChecked, AB/ActionButton.lua:715-719),
--     the proc glow (ActionButtonSpellAlertManager ShowAlert / HideAlert / HasAlert,
--     AB/ActionButtonSpellAlerts.lua:117-139). The main bar's four face buttons hold
--     no spell; their picture is button.SpecialActionIcon, set by atlas or texture
--     (G/MainActionBarFrame.lua:423-628).
--   * The button's action slot, button.action (AB/ActionButton.lua:539-545); 0 for
--     the main bar's four face buttons (G/ActionBarButton.lua:871-878).
--   * Cooldowns: C_ActionBar.GetActionCooldownDuration(slot) (DOC/ActionBarFrameDocumentation.lua:181)
--     into our own Cooldown frame with SetCooldownFromDurationObject
--     (DOC/FrameAPICooldownDocumentation.lua:308; allowed in a fight on our frame,
--     device-proven). Never SetCooldown with the game's numbers (refused in a fight).
--     "On cooldown" from C_ActionBar.GetActionCooldown(slot).isActive and .isOnGCD,
--     both NeverSecret (DOC/SpellSharedDocumentation.lua:26-31). isOnGCD is only to be
--     trusted inside a SPELL_UPDATE_COOLDOWN handler (:31), so it is read there, kept
--     on each picture, and the next frame only shows it. That event fires when a
--     cooldown starts; its end comes from our own frame's OnCooldownDone script (the
--     Cooldown script Blizzard_CooldownViewer/CooldownViewer.lua:718 sets too).
--   * CooldownFrameTemplate: Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3. It draws the
--     star flash and the edge by default (:3-10); the game's buttons turn both off
--     (Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml:111), and so do we
--     (SetDrawBling, SetDrawEdge: DOC/FrameAPICooldownDocumentation.lua:390, 401).
--   * The real bars' size, 208 by 68 when they do not grow (G/ActionBarStyles.lua:172),
--     each button inside them at most 32 (G/ActionBarStyles.lua:158-195).
--   * The active bar: PageUnit:RegisterActiveActionBarUpdatedCallback(fn, name)
--     (G/PageUnit.lua:705-707), called as fn(name) from SetActiveActionBar (:527-540)
--     on every trigger check, changed or not; PageUnit:GetActiveBar() (:542-544).
--     That registering function is Lua of the game's and writes our function into the game's
--     own callback table (Blizzard_SharedXMLBase/CallbackRegistry.lua:112), so it is listed
--     "writes-known" in tests/taint/calls.txt. It stays the default: it ran on the device on
--     2026-11-24 (0.16.2, 0.16.3) with the pictures on and no refused action, and the game
--     keeps and runs such callbacks behind its own barrier (SecureInsertEvent,
--     secureexecuterange, securecallfunction, same file). 0.16.4 adds the other way, not yet
--     run on a device, behind the layout's row "Part: follow the triggers with a hook":
--     hooksecurefunc on PageUnit.SetActiveActionBar, which writes nothing of ours into the
--     game's tables. Start is told which (useHook); the first Start of a session decides,
--     and only that one is ever installed.
--   * Page changes: hooksecurefunc on PageUnit.SetCurrentPage (G/PageUnit.lua:420);
--     never PageUnit:AddPageChangeCallback, which would taint the page change (:415-417, 450-452).
--   * The real bars' strata is LOW (G/ActionBarTemplates.xml:147, :375) at frame
--     levels 4 and 5 (G/ActionBar.lua:1-2); the spell wheels are DIALOG, level 10
--     (G/FlyoutRadial.xml:29, G/FlyoutRadial.lua:305). The pictures use MEDIUM, the
--     strata between them: above the invisible bars, under any open wheel.
--   * Events: ACTIONBAR_UPDATE_COOLDOWN, ACTIONBAR_UPDATE_STATE, UPDATE_BONUS_ACTIONBAR
--     (DOC/ActionBarFrameDocumentation.lua:1095, 1101, 1119), SPELL_UPDATE_COOLDOWN and
--     UPDATE_SHAPESHIFT_FORM (DOC/SpellBookDocumentation.lua:927, 992), UPDATE_POSSESS_BAR
--     (DOC/PetInfoDocumentation.lua:250).

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring
local min, max, huge = math.min, math.max, math.huge

local Face = {}
PE.FaceBars = Face

local KEY = "ctrlLayout"
local CALLBACK_NAME = "PocketEssentialsFace"   -- a string: a number is refused (CallbackRegistry.lua:121-122)
local ERROR_LIMIT = 3                          -- errors in a session before the pictures turn off
local QUIET_ALPHA = 0.3                        -- a half drawn quiet (the main diamond across from a held trigger)
local BASE_BUTTON = 28                         -- the picture size the glyph, range dot and count were drawn for

-- The contract's numbers (spec 0.14.0, "The contract between the two files"), used
-- when PE.LayoutPlan does not carry them: a picture 42 units, a diamond's buttons 46
-- left and right and 28 up and down of its centre (134 by 98); the four spots; the
-- states.
local FACE_DEFAULT = { button = 42, dx = 46, dy = 28 }
local SPOTS_DEFAULT = {
    inner = { left = { x = -170, y = 66 }, right = { x = 170, y = 66 } },
    outer = { left = { x = -316, y = 66 }, right = { x = 316, y = 66 } },
}
local STATES_DEFAULT = {
    rest = {
        { group = "main", half = "dpad", spot = "innerLeft" },
        { group = "main", half = "face", spot = "innerRight" },
    },
    lt = {
        { group = "lt", half = "dpad", spot = "outerLeft" },
        { group = "lt", half = "face", spot = "innerLeft" },
        { group = "main", half = "face", spot = "innerRight", quiet = true },
    },
    rt = {
        { group = "main", half = "dpad", spot = "innerLeft", quiet = true },
        { group = "rt", half = "dpad", spot = "innerRight" },
        { group = "rt", half = "face", spot = "outerRight" },
    },
    both = {
        { group = "both", half = "dpad", spot = "innerLeft" },
        { group = "both", half = "face", spot = "innerRight" },
    },
}
-- The game's four real bars, used when PE.LayoutPlan.RealBarRects is missing: 208 by
-- 68 at 60%, the main and LT bars centred at x -170, RT and LT+RT at +170, 87 and 45
-- up ({ left, bottom, right, top } from the screen's bottom centre).
local function BarRect(x, y) return { x - 62.4, y - 20.4, x + 62.4, y + 20.4 } end
local REAL_DEFAULT = { main = BarRect(-170, 87), lt = BarRect(-170, 45), rt = BarRect(170, 87), both = BarRect(170, 45) }
-- The frames under the pictures that take a tap: each side's inner diamond and real
-- bars plus this margin, but never past the player and target frames, whose boxes
-- start 395 either side of the centre (ControllerLayout.lua, FRAME_X). With the
-- 0.14.0 numbers they end at 241, so the cut is only a guard.
local BACKING_MARGIN = 4
local FRAME_EDGE = 395
-- 0.15.0: and never over the LB / RB targeting pictures, whose bottom is 128 up
-- (ControllerLayout.lua, Plan.SHOULDERS). At 120% the inner diamonds reach 124.8, so the
-- margin above them is cut to 3.2 there; below that size the cut is only a guard.
local SHOULDER_BOTTOM = 128

-- The four groups, each tied to one of the game's bar anchors; state is the
-- Plan.FaceStates key used while that group's bar is the active one.
local GROUPS = {
    { key = "main", anchor = "TopCenteredAnchor", state = "rest" },
    { key = "lt", anchor = "LeftCenteredAnchor", tag = "LT", state = "lt" },
    { key = "rt", anchor = "RightCenteredAnchor", tag = "RT", state = "rt" },
    { key = "both", anchor = "BottomCenteredAnchor", tag = "LT+RT", state = "both" },
}
local GROUP_INDEX = { main = 1, lt = 2, rt = 3, both = 4 }
-- A group's two halves: [1] the d-pad (pictures 1-4), [2] the face buttons (5-8).
local HALF_INDEX = { dpad = 1, face = 2 }
-- The four spots by name, as { ring, side } in Plan.FaceSpots.
local SPOT_KEYS = { innerLeft = { "inner", "left" }, outerLeft = { "outer", "left" },
    innerRight = { "inner", "right" }, outerRight = { "outer", "right" } }
local STATE_KEYS = { "rest", "lt", "rt", "both" }
-- The bars that can take an anchor's place, in the order they win.
local OVERRIDES = { "friendlyTargetingBar", "hostileTargetingBar", "shortcutsBar", "possessBar", "stanceBar" }
-- A diamond's four spots in press order (left, up, right, down), in steps of dx and dy.
local SPOT_STEPS = { { -1, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 } }
local EVENTS = { "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_STATE",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "UPDATE_POSSESS_BAR" }

-- 0.16.4 (spec 2026-11-24-0.16.4-cleanup.md, 2): the look of a picture that shows one of the
-- game's special icons (the main bar's four face buttons, a targeting bar's buttons). The
-- game draws those on a round black disc inside the slot's ring (G/MainActionBarFrame.lua:
-- 415-424), and Inspect's icon is a glyph on a see-through ground (crosshair_inspect_32 /
-- crosshair_unableinspect_32, :611), so on our square black backing it was a black square.
-- A grey face with a lighter rim, like the Jump button's own art; art that fills the square
-- (a spell icon, the red Back button, a portrait) covers the face.
local FACE_COLOUR = { 0.30, 0.30, 0.33 }
local RIM_COLOUR = { 0.55, 0.55, 0.60 }

local TEXT_NO_BARS = "the game's spell bars were not found"
local TEXT_NO_BUTTONS = "the game's spell buttons were not found"
local TEXT_NO_COOLDOWN = "this game version cannot draw cooldowns on our pictures"
local TEXT_NO_HOOKS = "this game version does not let addons follow its buttons"
local TEXT_BUILD = "they could not be made"
local TEXT_ERROR = "they hit an error"
local TEXT_FIGHT = "waiting for the fight to end"
local CHAT_ERROR = "Spell pictures turned off after an error; the game's bars are back. Reload to try again."

local running = false     -- started: the pictures show and follow the real buttons
local faded = false       -- the anchors' see-through was set to 0 by us
local broken = false      -- turned off after errors, until a reload
local status              -- why the game's own bars are showing, or nil
local buildFailed         -- the reason the pictures could not be made (kept: not tried again)
local errorCount = 0
local logged = {}         -- [reason] = true: each reason goes to the debug log once

local holder, driver      -- the pictures' parent, and the frame for events and the one OnUpdate
local pageUnit
local rootFrame           -- GamepadMainActionBarFrame, the game's bars' own parent
local barsHidden = false  -- the game hides its bars now: nothing is drawn until they are back
local groups = {}         -- [1..4] = { def, halves = { [1] d-pad, [2] face }, pics = { [1..8] = picture }, anchor, bar, tags }
local centres = {}        -- [spot name] = { x, y }: the four spots, read at Build
local panelScale = 1      -- the Spell panel size as a fraction, read at Build: each half's scale
local builtSize           -- that size in percent, once built
local states              -- Plan.FaceStates (or the default), read at Build
local backings = {}       -- [1] left, [2] right: the plain frames under the pictures that take a tap
local buttonPic = {}      -- [real button] = picture, for the buttons bound now
local hooked = {}         -- [real button or Blizzard frame] = true: its hooks are on
local callbackSet, alertsHooked, pageHooked, mainHooked = false, false, false, false
local settingAlpha = false
local followHook          -- nil until the first Start; then true (the hook) or false (the game's callback)
local lastActive          -- the bar the game last named active (false: none or unreadable)
local activeGroup         -- index of the group in use, or nil (the "nothing held" state)

local pending = false     -- the OnUpdate is set
local bindDirty, picsDirty, stateDirty, cooldownDirty, swapDirty = false, false, false, false, false
local Flush, OnUpdate     -- set below

-- Read only, for the offline tests and for looking around in /dump: the groups, their
-- halves and pictures, and the two frames under them. Never written from outside.
Face.view = groups
Face.backing = backings

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Field(t, key)
    if type(t) ~= "table" then return nil end
    local v = t[key]
    if type(v) ~= "table" then return nil end
    return v
end

-- True only for a readable "shown".
local function Shown(region)
    if type(region) ~= "table" then return false end
    local ok, v = pcall(region.IsShown, region)
    return ok and not IsSecret(v) and v == true
end

-- True only for a readable "visible" (shown, and every parent shown); IsShown when
-- IsVisible cannot be read.
local function Visible(frame)
    if type(frame) ~= "table" then return false end
    if type(frame.IsVisible) == "function" then
        local ok, v = pcall(frame.IsVisible, frame)
        if ok and not IsSecret(v) and type(v) == "boolean" then return v end
    end
    return Shown(frame)
end

-- A region's colour, or white when it cannot be read or is secret.
local function Colour(region)
    local ok, r, g, b = pcall(region.GetVertexColor, region)
    if not ok or IsSecret(r) or IsSecret(g) or IsSecret(b)
        or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return 1, 1, 1
    end
    return r, g, b
end

local function Note(text)
    if PE.debugOn then PE:Debug(KEY, "spell pictures: " .. text) end
end

local function RefreshPanel()
    if PE.RefreshSettings then pcall(PE.RefreshSettings, PE) end
end

---------------------------------------------------------------------------
-- Errors: every handler runs through PE:Wrap; a run that ends in an error is
-- counted, and the third turns the pictures off for the session.
---------------------------------------------------------------------------

local StopNow -- below

local onOff              -- Start's caller's function: told when the pictures turn off by themselves
local starting = false   -- inside Start: its caller reads the answer instead

local function Failed()
    errorCount = errorCount + 1
    if errorCount < ERROR_LIMIT or broken then return end
    broken = true
    pcall(StopNow)
    status = TEXT_ERROR
    Note("turned off after " .. errorCount .. " errors")
    PE:Print(CHAT_ERROR)
    RefreshPanel()
    -- The game's bars show again: ControllerLayout.lua puts them at full size (out of a fight).
    if onOff and not starting then pcall(onOff) end
end

local function Guard(fn)
    local inner = PE:Wrap(KEY, function(...)
        fn(...)
        return true
    end)
    return function(...)
        if inner(...) ~= true then Failed() end
    end
end

local function Schedule()
    if pending or not driver or barsHidden then return end
    pending = true
    driver:SetScript("OnUpdate", OnUpdate)
end

---------------------------------------------------------------------------
-- The real bars
---------------------------------------------------------------------------

-- A bar's button n (1-8), or nil.
local function ButtonOf(bar, n)
    if type(bar) ~= "table" then return nil end
    if type(bar.GetActionButtonByIndex) == "function" then
        local ok, b = pcall(bar.GetActionButtonByIndex, bar, n)
        if ok and type(b) == "table" then return b end
        return nil
    end
    local list = Field(bar, "actionButtons")
    local b = list and list[n]
    return type(b) == "table" and b or nil
end

local function ParentOf(f)
    if type(f) ~= "table" then return nil end
    local ok, p = pcall(f.GetParent, f)
    if ok and type(p) == "table" then return p end
    return nil
end

-- The bar shown in an anchor now: a stance, possess or targeting bar sitting in
-- it and shown, else the anchor's own bar.
local function BarIn(anchor)
    local own = Field(anchor, "Bar")
    local bars = Field(pageUnit, "actionBars")
    if bars then
        for _, key in ipairs(OVERRIDES) do
            local bar = Field(bars, key)
            if bar and bar ~= own and ParentOf(bar) == anchor and Shown(bar) then return bar end
        end
    end
    return own
end

-- Which group's anchor holds a bar (the bar itself or one of its parents), or nil.
local function GroupOfBar(bar)
    local f = bar
    for _ = 1, 4 do
        if type(f) ~= "table" then return nil end
        for i, g in ipairs(groups) do
            if f == g.anchor then return i end
        end
        f = ParentOf(f)
    end
    return nil
end

local function SetAnchorsAlpha(alpha)
    settingAlpha = true
    for _, g in ipairs(groups) do
        local anchor = g.anchor
        if anchor then
            local ok, err = pcall(anchor.SetAlpha, anchor, alpha)
            if not ok then PE:LogError(KEY, "A bar's see-through could not be set: " .. tostring(err)) end
        end
    end
    settingAlpha = false
end

---------------------------------------------------------------------------
-- The pictures
---------------------------------------------------------------------------

local function SmallText(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local file = (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
    pcall(fs.SetFont, fs, file, size, "OUTLINE")
    return fs
end

-- Our own Cooldown frame, or nil when this client cannot make one that takes a
-- duration object.
local function NewCooldown(parent)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, parent, "CooldownFrameTemplate")
    if not ok or type(cd) ~= "table" then ok, cd = pcall(CreateFrame, "Cooldown", nil, parent) end
    if not ok or type(cd) ~= "table" or type(cd.SetCooldownFromDurationObject) ~= "function" then return nil end
    pcall(cd.SetHideCountdownNumbers, cd, true)
    -- No star flash when a cooldown ends and no bright edge on the sweep, as on the
    -- game's own buttons.
    if type(cd.SetDrawBling) == "function" then pcall(cd.SetDrawBling, cd, false) end
    if type(cd.SetDrawEdge) == "function" then pcall(cd.SetDrawEdge, cd, false) end
    return cd
end

-- A size drawn for a 28 unit picture, grown with the picture and rounded to a whole
-- unit (at least 1): 11 becomes 17 at 42.
local function Scaled(n, size)
    return max(1, math.floor(n * size / BASE_BUTTON + 0.5))
end

-- One picture, centred (x, y) UI units from its half's centre (parent is the half's
-- frame). quad is its spot in the diamond (1 left, 2 up, 3 right, 4 down); dpad draws
-- the glyph as a plus, else as four dots. The glow, inset, glyph, range dot and count
-- grow with the picture (drawn for 28).
local function MakePicture(parent, x, y, size, quad, dpad)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(size, size)
    p:SetPoint("CENTER", parent, "CENTER", x, y)
    p:EnableMouse(true) -- takes a tap and does nothing with it
    local pic = { frame = p }
    local glowOut, inset = Scaled(3, size), size * 1.5 / BASE_BUTTON

    pic.glow = p:CreateTexture(nil, "BACKGROUND", nil, -8)
    pic.glow:SetPoint("TOPLEFT", p, "TOPLEFT", -glowOut, glowOut)
    pic.glow:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", glowOut, -glowOut)
    pic.glow:SetColorTexture(1, 0.82, 0.2, 0.6)
    pic.glow:Hide()
    pic.back = p:CreateTexture(nil, "BACKGROUND")
    pic.back:SetAllPoints(p)
    pic.back:SetColorTexture(0, 0, 0, 0.75)
    pic.checked = p:CreateTexture(nil, "BORDER")
    pic.checked:SetAllPoints(p)
    pic.checked:SetColorTexture(1, 0.82, 0, 1)
    pic.checked:Hide()
    pic.icon = p:CreateTexture(nil, "ARTWORK")
    pic.icon:SetPoint("TOPLEFT", p, "TOPLEFT", inset, -inset)
    pic.icon:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -inset, inset)
    pic.icon:Hide()
    -- 0.16.4: a button face under one of the game's special icons (see ShowIcon), at the
    -- icon's place, over the backing, which then shows as a rim around it.
    pic.face = p:CreateTexture(nil, "BORDER", nil, 1)
    pic.face:SetAllPoints(pic.icon)
    pic.face:SetColorTexture(FACE_COLOUR[1], FACE_COLOUR[2], FACE_COLOUR[3], 1)
    pic.face:Hide()
    pic.dim = p:CreateTexture(nil, "OVERLAY")
    pic.dim:SetAllPoints(pic.icon)
    pic.dim:SetColorTexture(0, 0, 0, 0.55)
    pic.dim:Hide()

    pic.cd = NewCooldown(p)
    if not pic.cd then return nil end
    pic.cd:SetAllPoints(pic.icon)
    -- The cooldown ran out: the darkening is read again on the next frame. No game event
    -- says so (SPELL_UPDATE_COOLDOWN fires when a cooldown starts), so without this a
    -- spell stayed dark until the next cast.
    pcall(pic.cd.SetScript, pic.cd, "OnCooldownDone", Guard(function()
        if not running or not pic.button then return end
        pic.dimSlot = nil
        pic.dCooldown = true
        picsDirty = true
        Schedule()
    end))

    -- Above the cooldown's sweep: the position glyph, the range dot and the count.
    local over = CreateFrame("Frame", nil, p)
    over:SetAllPoints(p)
    over:SetFrameLevel(p:GetFrameLevel() + 2)
    local glyphSize, dotSize, dotStep = Scaled(11, size), Scaled(3, size), Scaled(3, size)
    local glyph = over:CreateTexture(nil, "ARTWORK")
    glyph:SetSize(glyphSize, glyphSize)
    glyph:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    glyph:SetColorTexture(0, 0, 0, 0.7)
    if dpad then
        local mid = over:CreateTexture(nil, "OVERLAY")
        mid:SetSize(dotSize, dotSize)
        mid:SetPoint("CENTER", glyph, "CENTER", 0, 0)
        mid:SetColorTexture(1, 1, 1, 0.35)
    end
    for k, step in ipairs(SPOT_STEPS) do
        local dot = over:CreateTexture(nil, "OVERLAY")
        dot:SetSize(dotSize, dotSize)
        dot:SetPoint("CENTER", glyph, "CENTER", step[1] * dotStep, step[2] * dotStep)
        dot:SetColorTexture(1, 1, 1, k == quad and 1 or 0.35)
    end
    local rangeSize, rangeIn = Scaled(4, size), Scaled(2, size)
    pic.range = over:CreateTexture(nil, "OVERLAY")
    pic.range:SetSize(rangeSize, rangeSize)
    pic.range:SetPoint("TOPRIGHT", p, "TOPRIGHT", -rangeIn, -rangeIn)
    pic.range:SetColorTexture(1, 1, 1, 1)
    pic.range:Hide()
    local countIn = Scaled(1, size)
    pic.count = SmallText(over, Scaled(9, size))
    pic.count:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -countIn, countIn)
    pic.count:SetJustifyH("RIGHT")
    return pic
end

local function IsPoint(c)
    return type(c) == "table" and type(c.x) == "number" and type(c.y) == "number"
end

-- Plan.FaceSpots' answer when it has all four spots.
local function GoodSpots(s)
    if type(s) ~= "table" then return false end
    for _, key in pairs(SPOT_KEYS) do
        local ring = s[key[1]]
        if type(ring) ~= "table" or not IsPoint(ring[key[2]]) then return false end
    end
    return true
end

-- Plan.FaceStates' answer when every state is a list of known groups, halves and spots.
local function GoodStates(t)
    if type(t) ~= "table" then return false end
    for _, key in ipairs(STATE_KEYS) do
        local list = t[key]
        if type(list) ~= "table" then return false end
        for _, e in ipairs(list) do
            if type(e) ~= "table" or not GROUP_INDEX[e.group] or not HALF_INDEX[e.half] or not SPOT_KEYS[e.spot] then
                return false
            end
        end
    end
    return true
end

-- One of ControllerLayout.lua's functions called (with arg), its answer when good() takes it.
local function FromPlan(name, good, arg)
    local plan = PE.LayoutPlan
    local fn = type(plan) == "table" and plan[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, arg)
    if ok and good(v) then return v end
    return nil
end

-- The Spell panel size in percent: one of the five, else 100.
local function PanelSize(v)
    if v == 80 or v == 90 or v == 110 or v == 120 then return v end
    return 100
end

-- The picture sizes at 100%, the four spots and the states, and the size the spots were
-- worked out for: ControllerLayout.lua's, when it has them, else the copies above (at
-- 100%: without its spots the pictures are drawn at 100%).
local function FaceNumbers(size)
    local plan = PE.LayoutPlan
    local face = FACE_DEFAULT
    if type(plan) == "table" and type(plan.FACE) == "table" and type(plan.FACE.button) == "number"
        and type(plan.FACE.dx) == "number" and type(plan.FACE.dy) == "number" then
        face = plan.FACE
    end
    local spots = FromPlan("FaceSpots", GoodSpots, size)
    if not spots then spots, size = SPOTS_DEFAULT, 100 end
    return face, spots, FromPlan("FaceStates", GoodStates) or STATES_DEFAULT, size
end

local function IsRect(r)
    return type(r) == "table" and type(r[1]) == "number" and type(r[2]) == "number"
        and type(r[3]) == "number" and type(r[4]) == "number"
end

-- The four real bars' rectangles at that size: ControllerLayout.lua's, when it has them
-- (the copy is at 100%).
local function RealBars(size)
    return FromPlan("RealBarRects", function(r)
        return type(r) == "table" and IsRect(r.main) and IsRect(r.lt) and IsRect(r.rt) and IsRect(r.both)
    end, size) or REAL_DEFAULT
end

local function Grow(box, l, b, r, t)
    box[1], box[2], box[3], box[4] = min(box[1], l), min(box[2], b), max(box[3], r), max(box[4], t)
end

-- The two frames under the pictures, { left, bottom, right, top } each from the
-- screen's bottom centre: [1] the inner-left diamond and the real bars left of the
-- centre, [2] the inner-right diamond and the real bars right of it, each grown by
-- the margin and cut at the player and target frames and under the targeting pictures.
-- face is at 100%, s the Spell panel size as a fraction; spots are at that size.
local function BackingRects(face, spots, s, size)
    local boxes = { { huge, huge, -huge, -huge }, { huge, huge, -huge, -huge } }
    local hw, hh = (face.dx + face.button / 2) * s, (face.dy + face.button / 2) * s
    for side, c in ipairs({ spots.inner.left, spots.inner.right }) do
        Grow(boxes[side], c.x - hw, c.y - hh, c.x + hw, c.y + hh)
    end
    for _, r in pairs(RealBars(size)) do
        Grow(boxes[(r[1] + r[3]) < 0 and 1 or 2], r[1], r[2], r[3], r[4])
    end
    -- 0.18.0 (Arrange it yourself): an inner panel the player moved takes its two cuts with
    -- it, so the frame under it keeps its shape and still lies under every picture and real
    -- button of that side. No offset (the switch Off, or the panel not moved): 0, 0.
    local plan = PE.LayoutPlan
    local moved = type(plan) == "table" and plan.Moved
    for side, box in ipairs(boxes) do
        local dx, dy = 0, 0
        if type(moved) == "function" then
            local ok, x, y = pcall(moved, nil, side == 1 and "inner left diamond" or "inner right diamond")
            if ok and type(x) == "number" and type(y) == "number" then dx, dy = x, y end
        end
        box[1], box[2], box[3], box[4] = box[1] - BACKING_MARGIN, box[2] - BACKING_MARGIN, box[3] + BACKING_MARGIN, box[4] + BACKING_MARGIN
        if side == 1 then box[1] = max(box[1], -FRAME_EDGE + dx) else box[3] = min(box[3], FRAME_EDGE + dx) end
        box[4] = min(box[4], SHOULDER_BOTTOM + dy)
    end
    return boxes
end

local OnEvent -- below

-- Makes every frame, once, at the Spell panel size given (in percent). Returns true, or
-- false and the reason. Every half starts hidden; the first Flush places the ones the
-- state shows (ApplyState). The pictures are made at 100% and each half is scaled, so
-- everything in it (pictures, glyphs, counts, tags) grows with it; a scaled frame's
-- offsets count in its own scale, so its spot is divided by the scale.
local function Build(size)
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetAllPoints(UIParent)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", Guard(function(_, event) OnEvent(event) end))
    local face, spots
    face, spots, states, size = FaceNumbers(PanelSize(size))
    panelScale = size / 100
    builtSize = size
    for name, key in pairs(SPOT_KEYS) do
        local c = spots[key[1]][key[2]]
        centres[name] = { x = c.x, y = c.y }
    end
    -- Under the pictures (the same strata, a lower level): takes a tap, draws nothing,
    -- has no script.
    for side, r in ipairs(BackingRects(face, spots, panelScale, size)) do
        local f = CreateFrame("Frame", nil, holder)
        f:SetFrameStrata("MEDIUM")
        f:SetFrameLevel(holder:GetFrameLevel() + 1)
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", r[1], r[2])
        f:SetSize(r[3] - r[1], r[4] - r[2])
        f:EnableMouse(true)
        backings[side] = f
    end
    local w, h = 2 * face.dx + face.button, 2 * face.dy + face.button
    for gi, def in ipairs(GROUPS) do
        local g = { def = def, halves = {}, pics = {}, tags = {} }
        for half = 1, 2 do
            local hf = CreateFrame("Frame", nil, holder)
            hf:SetSize(w, h)
            hf:SetScale(panelScale)
            hf:SetPoint("CENTER", UIParent, "BOTTOM", centres.innerLeft.x / panelScale, centres.innerLeft.y / panelScale)
            hf:SetFrameLevel(holder:GetFrameLevel() + 2) -- the pictures above the frames that take a tap
            hf:Hide()
            g.halves[half] = hf
            for q, step in ipairs(SPOT_STEPS) do
                local pic = MakePicture(hf, step[1] * face.dx, step[2] * face.dy, face.button, q, half == 1)
                if not pic then return false, TEXT_NO_COOLDOWN end
                g.pics[(half - 1) * 4 + q] = pic
            end
            if def.tag then
                local tag = SmallText(hf, Scaled(8, face.button))
                tag:SetPoint("CENTER", hf, "CENTER", 0, 0)
                tag:SetText(def.tag)
                g.tags[#g.tags + 1] = tag
            end
        end
        groups[gi] = g
    end
    return true
end

local function ShowEmpty(pic)
    pic.icon:Hide()
    pic.face:Hide()
    pic.back:SetColorTexture(1, 1, 1, 0.12) -- a faint outline
    pic.empty = true
end

-- special: one of the game's special icons, drawn on a button face (see FACE_COLOUR).
local function ShowIcon(pic, r, g, b, grey, special)
    pic.icon:SetVertexColor(r, g, b)
    pic.icon:SetDesaturated(grey)
    pic.icon:Show()
    if special then
        pic.back:SetColorTexture(RIM_COLOUR[1], RIM_COLOUR[2], RIM_COLOUR[3], 1)
        pic.face:Show()
    else
        pic.back:SetColorTexture(0, 0, 0, 0.75)
        pic.face:Hide()
    end
    pic.empty = false
end

-- The real icon's texture, colour (secret: white) and greying. Our texture is set
-- only when it changed; a secret one is always set (it cannot be compared).
local function CopyIcon(pic, icon)
    if not icon or not Shown(icon) then return ShowEmpty(pic) end
    local ok, tex = pcall(icon.GetTexture, icon)
    if not ok then return ShowEmpty(pic) end
    if IsSecret(tex) then
        if not pcall(pic.icon.SetTexture, pic.icon, tex) then pic.tex = nil return ShowEmpty(pic) end
        pic.tex = nil
    else
        if tex == nil or tex == "" then return ShowEmpty(pic) end
        if tex ~= pic.tex then
            if not pcall(pic.icon.SetTexture, pic.icon, tex) then pic.tex = nil return ShowEmpty(pic) end
            pic.tex = tex
            -- Another spell in the slot, maybe: its cooldown and darkening are read again.
            pic.dCooldown = true
            pic.dimSlot = nil
        end
    end
    if not pic.plainCoords then
        pic.icon:SetTexCoord(0, 1, 0, 1)
        pic.plainCoords = true
    end
    local r, g, b = Colour(icon)
    local okGrey, grey = pcall(icon.IsDesaturated, icon)
    ShowIcon(pic, r, g, b, okGrey and not IsSecret(grey) and grey == true)
end

-- The main bar's face buttons: the picture the game draws on them (an atlas, or a
-- texture with its texture coordinates, as for a raid marker).
local function CopySpecial(pic, sp)
    pic.tex, pic.plainCoords = nil, false -- set here outside CopyIcon's record
    local done = false
    local okAtlas, atlas = pcall(sp.GetAtlas, sp)
    if okAtlas and not IsSecret(atlas) and type(atlas) == "string" and atlas ~= "" then
        done = pcall(pic.icon.SetAtlas, pic.icon, atlas)
    end
    if not done then
        local ok, tex = pcall(sp.GetTexture, sp)
        if ok and (IsSecret(tex) or tex ~= nil) then done = pcall(pic.icon.SetTexture, pic.icon, tex) end
        if done then
            local okC, ulx, uly, _, _, _, _, lrx, lry = pcall(sp.GetTexCoord, sp)
            if okC and type(ulx) == "number" and type(uly) == "number" and type(lrx) == "number" and type(lry) == "number"
                and not IsSecret(ulx) and not IsSecret(uly) and not IsSecret(lrx) and not IsSecret(lry) then
                pcall(pic.icon.SetTexCoord, pic.icon, ulx, lrx, uly, lry)
            else
                pic.icon:SetTexCoord(0, 1, 0, 1)
            end
        end
    end
    if not done then return ShowEmpty(pic) end
    local r, g, b = Colour(sp)
    ShowIcon(pic, r, g, b, false, true)
end

-- 0.16.4 (spec 2026-11-24-0.16.4-cleanup.md, 3): the unit whose portrait the game draws on a
-- button, or nil. The targeting bars' buttons that target a unit (the pet, the player, the
-- target's target, a party member, the focus) are set up with the attributes type "target"
-- and unit (G/TargetActionBars/Shared.lua:112-119), and their picture is that unit's portrait,
-- drawn by SetPortraitTexture(icon, unit) (Shared.lua:98, FriendlyTargetingActionBar.lua:156,
-- 180, 185). GetAttribute is the frame's own method
-- (DOC/SimpleFrameAPIDocumentation.lua:290); it only reads.
local function PortraitUnit(b)
    if type(b.GetAttribute) ~= "function" then return nil end
    local ok, kind = pcall(b.GetAttribute, b, "type")
    if not ok or IsSecret(kind) or kind ~= "target" then return nil end
    local okUnit, unit = pcall(b.GetAttribute, b, "unit")
    if okUnit and not IsSecret(unit) and type(unit) == "string" and unit ~= "" then return unit end
    return nil
end

-- The unit's portrait on our own texture, the way the game draws it on its own
-- (SetPortraitTexture, DOC/UnitDocumentation.lua:572). What GetTexture returns for a
-- portrait, and whether another texture can show it, is not in the source, so the copy
-- (CopySpecial) is only the fallback. False when the game has no such function or refuses.
local function DrawPortrait(pic, unit)
    local draw = SetPortraitTexture
    if type(draw) ~= "function" or not pcall(draw, pic.icon, unit) then return false end
    pic.tex, pic.plainCoords = nil, false
    pic.icon:SetTexCoord(0, 1, 0, 1)
    ShowIcon(pic, 1, 1, 1, false, true)
    return true
end

-- The picture: the real icon, or the game's own picture on the main bar's face
-- buttons. When it turns empty or special (or back), or shows another texture, the
-- cooldown is looked at again.
local function RefreshIcon(pic)
    local b = pic.button
    local wasEmpty, wasSpecial = pic.empty, pic.special
    if not b then
        pic.special = false
        ShowEmpty(pic)
    else
        local sp = Field(b, "SpecialActionIcon")
        pic.special = sp ~= nil and Shown(sp)
        if pic.special then
            local unit = PortraitUnit(b)
            pic.unit = unit
            if not (unit and DrawPortrait(pic, unit)) then CopySpecial(pic, sp) end
        else
            pic.unit = nil
            CopyIcon(pic, Field(b, "icon"))
        end
    end
    if pic.empty ~= wasEmpty or pic.special ~= wasSpecial then pic.dCooldown = true end
end

local function RefreshRange(pic)
    local range = pic.button and Field(pic.button, "RangeIndicator")
    if range and Shown(range) then
        pic.range:SetVertexColor(Colour(range))
        pic.range:Show()
    else
        pic.range:Hide()
    end
end

-- The count goes from the game's text to ours as it is: in a fight it may be
-- secret, which our SetText takes; it is never compared or changed.
local function RefreshCount(pic)
    local count, text = pic.button and Field(pic.button, "Count"), ""
    if count then
        local ok, v = pcall(count.GetText, count)
        if ok then text = v end
    end
    if not pcall(pic.count.SetText, pic.count, text) then pic.count:SetText("") end
end

local function RefreshChecked(pic)
    local b, on = pic.button, false
    if b and not pic.special then
        local ok, v = pcall(b.GetChecked, b)
        on = ok and not IsSecret(v) and v == true
    end
    pic.checked:SetShown(on)
end

local function RefreshGlow(pic)
    local b, on = pic.button, false
    local manager = ActionButtonSpellAlertManager
    if b and type(manager) == "table" then
        local ok, has = pcall(manager.HasAlert, manager, b)
        on = ok and not IsSecret(has) and has == true
    end
    pic.glow:SetShown(on)
end

-- The parts of one picture that were marked, each copied from its real button. The
-- icon goes first: checked and the cooldown depend on what it found.
local function RefreshMarked(pic)
    if pic.dIcon then
        pic.dIcon = false
        RefreshIcon(pic)
    end
    if pic.dRange then
        pic.dRange = false
        RefreshRange(pic)
    end
    if pic.dCount then
        pic.dCount = false
        RefreshCount(pic)
    end
    if pic.dChecked then
        pic.dChecked = false
        RefreshChecked(pic)
    end
    if pic.dGlow then
        pic.dGlow = false
        RefreshGlow(pic)
    end
end

local function MarkWhole(pic)
    pic.dIcon, pic.dRange, pic.dCount, pic.dChecked, pic.dGlow, pic.dCooldown = true, true, true, true, true, true
end

local function ClearCooldown(pic)
    if pic.cdOn then
        pcall(pic.cd.Clear, pic.cd)
        pic.cdOn = false
    end
    pic.dim:Hide()
end

-- The action slot a picture's cooldown comes from, or nil (no button, an empty or
-- special picture, a pet button, a secret or unusable slot).
local function SlotOf(pic)
    local b = pic.button
    local slot = b and b.action
    if pic.empty or pic.special or IsSecret(slot) or type(slot) ~= "number" or slot < 1 then return nil end
    return slot
end

-- Whether the game says the slot is on cooldown, the global cooldown alone not
-- counting; kept on the picture with the slot it was read for. A secret, missing or
-- unreadable answer is "not on cooldown".
local function ReadDim(pic, slot)
    local dim = false
    local api = C_ActionBar
    if type(api) == "table" and type(api.GetActionCooldown) == "function" then
        local ok, info = pcall(api.GetActionCooldown, slot)
        if ok and not IsSecret(info) and type(info) == "table" then
            local active, gcd = info.isActive, info.isOnGCD
            dim = not IsSecret(active) and active == true and not (not IsSecret(gcd) and gcd == true)
        end
    end
    pic.dimOn, pic.dimSlot = dim, slot
end

-- The cooldown sweep from the game's duration object, and the darkening kept by
-- ReadDim. The darkening is read here only for a slot it was never read for (a
-- new button or page, another texture in it) or whose cooldown just ended (our
-- frame's OnCooldownDone): there is no event to read it in then, and the next
-- SPELL_UPDATE_COOLDOWN puts it right.
local function RefreshCooldown(pic)
    local slot = SlotOf(pic)
    local api = C_ActionBar
    if not slot or type(api) ~= "table" then return ClearCooldown(pic) end
    local ok, object = pcall(api.GetActionCooldownDuration, slot)
    if ok and (IsSecret(object) or object ~= nil) then ok = pcall(pic.cd.SetCooldownFromDurationObject, pic.cd, object) else ok = false end
    if ok then
        pic.cdOn = true
    elseif pic.cdOn then
        pcall(pic.cd.Clear, pic.cd)
        pic.cdOn = false
    end
    if pic.dimSlot ~= slot then ReadDim(pic, slot) end
    pic.dim:SetShown(pic.dimOn == true)
end

-- Places the halves for the trigger held now (Plan.FaceStates; no active bar known is
-- the "nothing held" state): each listed half to its spot, at full strength or quiet,
-- shown; every other half hidden. Plain calls on our own frames, fine in a fight.
local function ApplyState()
    local list = states and states[activeGroup and GROUPS[activeGroup].state or "rest"] or {}
    local want = {}
    for _, e in ipairs(list) do want[(GROUP_INDEX[e.group] - 1) * 2 + HALF_INDEX[e.half]] = e end
    for gi, g in ipairs(groups) do
        for half, f in ipairs(g.halves) do
            local e = want[(gi - 1) * 2 + half]
            local c = e and centres[e.spot]
            if c then
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "BOTTOM", c.x / panelScale, c.y / panelScale)
                f:SetAlpha(e.quiet and QUIET_ALPHA or 1)
                f:Show()
            else
                f:Hide()
            end
        end
    end
end

---------------------------------------------------------------------------
-- Following the real buttons
---------------------------------------------------------------------------

-- One part of the picture bound to a real button needs copying again ("dIcon",
-- "dRange", "dCount", "dChecked", "dGlow").
local function MarkPart(b, part)
    if not running then return end
    local pic = buttonPic[b]
    if not pic then return end
    pic[part] = true
    picsDirty = true
    Schedule()
end

local function MarkAll()
    for _, g in ipairs(groups) do
        for _, pic in ipairs(g.pics) do MarkWhole(pic) end
    end
    picsDirty, cooldownDirty = true, true
end

-- Every picture's darkening is read again when next drawn.
local function ForgetDim()
    for _, g in ipairs(groups) do
        for _, pic in ipairs(g.pics) do pic.dimSlot = nil end
    end
end

local function Hook(t, name, fn)
    if type(t) == "table" and type(t[name]) == "function" then
        return pcall(hooksecurefunc, t, name, fn) and true or false
    end
    return false
end

local ICON_CALLS = { "SetTexture", "SetVertexColor", "SetDesaturated", "Show", "Hide" }
local SPECIAL_CALLS = { "SetTexture", "SetAtlas", "SetTexCoord", "SetColorTexture", "SetVertexColor", "Show", "Hide" }
local RANGE_CALLS = { "SetVertexColor", "Show", "Hide" }

-- The hooks on one real button and its regions, once; each marks only its part of
-- the picture bound to that button, and does nothing while stopped or unbound.
local function HookButton(b)
    if hooked[b] then return end
    hooked[b] = true
    local markIcon = Guard(function() MarkPart(b, "dIcon") end)
    local icon = Field(b, "icon")
    for _, name in ipairs(ICON_CALLS) do Hook(icon, name, markIcon) end
    local sp = Field(b, "SpecialActionIcon")
    for _, name in ipairs(SPECIAL_CALLS) do Hook(sp, name, markIcon) end
    local markRange = Guard(function() MarkPart(b, "dRange") end)
    local range = Field(b, "RangeIndicator")
    for _, name in ipairs(RANGE_CALLS) do Hook(range, name, markRange) end
    Hook(Field(b, "Count"), "SetText", Guard(function() MarkPart(b, "dCount") end))
    if type(b.UpdateState) == "function" then Hook(b, "UpdateState", Guard(function() MarkPart(b, "dChecked") end)) end
    if type(b.UpdateAction) == "function" then
        -- The button may hold another action now: everything, the darkening read again.
        Hook(b, "UpdateAction", Guard(function()
            if not running then return end
            local pic = buttonPic[b]
            if not pic then return end
            MarkWhole(pic)
            pic.dimSlot = nil
            picsDirty = true
            Schedule()
        end))
    end
end

local markBind = Guard(function()
    if not running then return end
    bindDirty = true
    Schedule()
end)

-- Show and Hide of the bars that can take an anchor's place, once per bar.
local function HookOverrides()
    local bars = Field(pageUnit, "actionBars")
    if not bars then return end
    for _, key in ipairs(OVERRIDES) do
        local bar = Field(bars, key)
        if bar and not hooked[bar] and type(bar.HookScript) == "function" then
            hooked[bar] = true
            pcall(bar.HookScript, bar, "OnShow", markBind)
            pcall(bar.HookScript, bar, "OnHide", markBind)
        end
    end
end

-- Ties each group's eight pictures to the buttons of the bar shown in its anchor.
local function Rebind()
    for _, g in ipairs(groups) do
        local bar = BarIn(g.anchor)
        if bar ~= g.bar then
            g.bar = bar
            if PE.debugOn then Note(g.def.key .. " group follows " .. ((bar and bar == Field(g.anchor, "Bar")) and "its own bar" or "another bar")) end
        end
        for n, pic in ipairs(g.pics) do
            local b = ButtonOf(bar, n)
            if pic.button ~= b then
                if pic.button and buttonPic[pic.button] == pic then buttonPic[pic.button] = nil end
                pic.button = b
                if b then
                    buttonPic[b] = pic
                    HookButton(b)
                end
                MarkWhole(pic)
                pic.dimSlot = nil
                picsDirty = true
            end
        end
    end
    HookOverrides()
end

-- Which group the game's active bar belongs to; a change re-binds and swaps the
-- halves shown. Called on every trigger check, so nothing happens without a change.
local function ReadActive()
    local bar = false
    if pageUnit and type(pageUnit.GetActiveBar) == "function" then
        local ok, b = pcall(pageUnit.GetActiveBar, pageUnit)
        if ok and not IsSecret(b) and type(b) == "table" then bar = b end
    end
    -- The group is read again even for the same bar: a possess or stance bar moved to
    -- another anchor by a settings change stays the same frame (GamepadOverrideBarMixin.lua:59-64).
    local group = callbackSet and bar and GroupOfBar(bar) or nil
    if bar == lastActive and group == activeGroup then return false end
    lastActive = bar
    if group ~= activeGroup then
        activeGroup = group
        swapDirty = true
    end
    bindDirty = true
    return true
end

local onActiveBar = Guard(function()
    if running and ReadActive() then Schedule() end
end)

-- 0.16.4 (spec 2026-11-24-0.16.4-cleanup.md, 4): what is drawn, for the debug log. One line
-- when the state, the game's active bar or the pictures shown change: the state, the
-- active bar by its key in PageUnit.actionBars (G/PageUnit.lua:108-121; rightBar means the
-- right trigger is held, :565-567), and each half shown with its spot, "quiet" and how many
-- of its four pictures show an icon. A second line when a group follows another bar. Called
-- only from a Flush that swapped or re-bound, never per frame, and only with the log on.
local lastDrawn, lastFollows

local function BarName(bar)
    if type(bar) ~= "table" then return "none" end
    local bars = Field(pageUnit, "actionBars")
    if bars then
        for key, value in pairs(bars) do
            if value == bar and type(key) == "string" then return key end
        end
    end
    return "unknown"
end

local function LogDrawn()
    local stateKey = activeGroup and GROUPS[activeGroup].state or "rest"
    local parts = {}
    for _, e in ipairs(states and states[stateKey] or {}) do
        local g = groups[GROUP_INDEX[e.group]]
        local first, icons = (HALF_INDEX[e.half] - 1) * 4, 0
        for q = 1, 4 do
            local pic = g and g.pics[first + q]
            if pic and pic.empty == false then icons = icons + 1 end
        end
        parts[#parts + 1] = e.group .. " " .. e.half .. "@" .. e.spot .. (e.quiet and " quiet " or " ") .. icons .. "/4"
    end
    local drawn = "drawn: state=" .. stateKey .. " active=" .. BarName(lastActive or nil) .. "; " .. table.concat(parts, ", ")
    if drawn ~= lastDrawn then
        lastDrawn = drawn
        Note(drawn)
    end
    local names = {}
    for _, g in ipairs(groups) do names[#names + 1] = g.def.key .. "=" .. BarName(g.bar) end
    local follows = "follows: " .. table.concat(names, " ")
    if follows ~= lastFollows then
        lastFollows = follows
        Note(follows)
    end
end

-- The work the hooks and events marked. Does nothing while the game hides its bars:
-- the marks wait, and everything is drawn again when the bars come back.
Flush = function()
    if driver then driver:SetScript("OnUpdate", nil) end
    pending = false
    if not running or barsHidden then return end
    -- The swap first: it needs no binding, so an error further down never holds it back.
    local changed = swapDirty or bindDirty
    if swapDirty then
        swapDirty = false
        ApplyState()
    end
    if bindDirty then
        bindDirty = false
        Rebind()
    end
    local allCooldowns = cooldownDirty
    cooldownDirty = false
    if picsDirty or allCooldowns then
        picsDirty = false
        for _, g in ipairs(groups) do
            for _, pic in ipairs(g.pics) do
                RefreshMarked(pic)
                if allCooldowns or pic.dCooldown then
                    pic.dCooldown = false
                    RefreshCooldown(pic)
                end
            end
        end
    end
    if stateDirty then
        stateDirty = false
        for _, g in ipairs(groups) do
            for _, pic in ipairs(g.pics) do RefreshChecked(pic) end
        end
    end
    if changed and PE.debugOn then LogDrawn() end
end
OnUpdate = Guard(function() Flush() end)

-- SPELL_UPDATE_COOLDOWN: the one moment isOnGCD can be trusted, so every bound
-- slot's darkening is read now; the next frame only shows it.
local function ReadAllDim()
    for _, g in ipairs(groups) do
        for _, pic in ipairs(g.pics) do
            local slot = SlotOf(pic)
            if slot then ReadDim(pic, slot) end
        end
    end
end

OnEvent = function(event)
    if not running then return end
    if event == "SPELL_UPDATE_COOLDOWN" then
        if not barsHidden then ReadAllDim() end
        cooldownDirty = true
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
        cooldownDirty = true
    elseif event == "ACTIONBAR_UPDATE_STATE" then
        stateDirty = true
    else
        bindDirty = true
        MarkAll()
    end
    Schedule()
end

-- The game's bars came back: everything is drawn again at once, before they show.
local function BarsShown()
    if not running or not holder or not Visible(rootFrame) then return end
    barsHidden = false
    bindDirty = true
    MarkAll()
    ForgetDim()
    Flush()
    holder:Show()
end

local function BarsHidden()
    if not running or not holder then return end
    barsHidden = true
    holder:Hide()
    if driver then driver:SetScript("OnUpdate", nil) end
    pending = false
end

-- The hooks that are not per button, once each.
local function HookOnce(root, useHook)
    if followHook == nil then followHook = useHook == true end
    if not mainHooked and type(root.HookScript) == "function" then
        mainHooked = true
        -- The pictures hide while the game hides its bars (binding editor, Gamepad UI off).
        pcall(root.HookScript, root, "OnShow", Guard(BarsShown))
        pcall(root.HookScript, root, "OnHide", Guard(BarsHidden))
    end
    if not pageHooked and type(pageUnit.SetCurrentPage) == "function" then
        pageHooked = Hook(pageUnit, "SetCurrentPage", Guard(function()
            if not running then return end
            bindDirty = true
            MarkAll()
            Schedule()
        end))
    end
    local manager = ActionButtonSpellAlertManager
    if not alertsHooked and type(manager) == "table" then
        alertsHooked = true
        local glow = Guard(function(_, button) MarkPart(button, "dGlow") end)
        if type(manager.ShowAlert) == "function" then Hook(manager, "ShowAlert", glow) end
        if type(manager.HideAlert) == "function" then Hook(manager, "HideAlert", glow) end
    end
    -- One of the two, as the first Start chose (followHook); never both in a session.
    if not callbackSet and followHook then
        if type(pageUnit.SetActiveActionBar) == "function" then
            callbackSet = Hook(pageUnit, "SetActiveActionBar", onActiveBar)
        end
    elseif not callbackSet and type(pageUnit.RegisterActiveActionBarUpdatedCallback) == "function" then
        callbackSet = pcall(pageUnit.RegisterActiveActionBarUpdatedCallback, pageUnit, onActiveBar, CALLBACK_NAME) and true or false
    end
    for _, g in ipairs(groups) do
        local anchor = g.anchor
        if not hooked[anchor] then
            hooked[anchor] = true
            -- Anything else that changes an anchor's see-through while we are on gets 0 back.
            Hook(anchor, "SetAlpha", Guard(function(self, alpha)
                if not running or not faded or settingAlpha then return end
                if type(alpha) == "number" and alpha == 0 then return end
                settingAlpha = true
                local ok = pcall(self.SetAlpha, self, 0)
                settingAlpha = false
                if not ok then error("a bar's see-through could not be put back to 0", 0) end
            end))
        end
    end
end

---------------------------------------------------------------------------
-- Start, Stop, Status
---------------------------------------------------------------------------

local function Fail(reason)
    status = reason
    if not logged[reason] then
        logged[reason] = true
        Note("the game's own bars stay: " .. reason)
    end
    return false, reason
end

StopNow = function()
    local wasFaded = faded
    running, faded = false, false
    if wasFaded then SetAnchorsAlpha(1) end
    if driver then
        driver:SetScript("OnUpdate", nil)
        driver:UnregisterAllEvents()
    end
    pending = false
    bindDirty, picsDirty, stateDirty, cooldownDirty, swapDirty = false, false, false, false, false
    if holder then holder:Hide() end
    for b in pairs(buttonPic) do buttonPic[b] = nil end
    for _, g in ipairs(groups) do
        g.bar = nil
        for _, pic in ipairs(g.pics) do
            pic.button = nil
            pic.dimSlot = nil
            ClearCooldown(pic)
        end
    end
    lastActive, activeGroup = nil, nil
    lastDrawn, lastFollows = nil, nil
    barsHidden = false
end

-- Raises only on a bug; Start counts it.
local function StartNow(size, useHook)
    if running then
        bindDirty = true
        Schedule()
        return true
    end
    if buildFailed then return Fail(buildFailed) end
    if type(hooksecurefunc) ~= "function" or type(CreateFrame) ~= "function" then return Fail(TEXT_NO_HOOKS) end
    local root = GamepadMainActionBarFrame
    local pu = Field(root, "PageUnit")
    if not pu then return Fail(TEXT_NO_BARS) end
    local anchors = {}
    for i, def in ipairs(GROUPS) do
        local anchor = Field(pu, def.anchor)
        local bar = Field(anchor, "Bar")
        if not bar or type(anchor.SetAlpha) ~= "function" then return Fail(TEXT_NO_BARS) end
        for n = 1, 8 do
            if not ButtonOf(bar, n) then return Fail(TEXT_NO_BUTTONS) end
        end
        anchors[i] = anchor
    end
    local api = C_ActionBar
    if type(api) ~= "table" or type(api.GetActionCooldownDuration) ~= "function" then return Fail(TEXT_NO_COOLDOWN) end
    pageUnit = pu
    if not holder then
        local ok, made, why = pcall(Build, size)
        if not ok or not made then
            buildFailed = (ok and why) or TEXT_BUILD
            if not ok then PE:LogError(KEY, "The spell pictures could not be made: " .. tostring(made)) end
            if holder then holder:Hide() end
            return Fail(buildFailed)
        end
    end
    for i, g in ipairs(groups) do g.anchor = anchors[i] end
    rootFrame = root
    HookOnce(root, useHook)

    running = true
    status = nil
    for _, event in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, event) end
    lastActive, activeGroup = nil, nil
    ReadActive()
    bindDirty, swapDirty = true, true
    MarkAll()
    -- The pictures are right before the real bars go invisible; while the game hides
    -- its bars they wait (drawn when the bars come back).
    barsHidden = not Visible(root)
    Flush()
    holder:SetShown(not barsHidden)
    faded = true
    SetAnchorsAlpha(0)
    if not callbackSet then
        Note(followHook and "on (no active-bar hook: the main bar only)" or "on (no active-bar callback: the main bar only)")
    else
        Note("on (triggers followed with " .. (followHook and "a hook on SetActiveActionBar" or "the game's callback") .. ")")
    end
    return true
end

-- The three are set with the bracket form on purpose: tests/api/extract.lua treats a
-- name this addon defines as its own, and "Stop" is also the game's animation call.
local Public = {}

function Public.Start(whenOff, size, useHook)
    if type(whenOff) == "function" then onOff = whenOff end
    if broken then return false, status end
    if PE:InCombat() then return false, TEXT_FIGHT end
    local ok, started, reason = PE:Safe(KEY, StartNow, size, useHook)
    if ok then return started, reason end
    pcall(StopNow)
    starting = true
    Failed()
    starting = false
    if broken then return false, status end
    status = TEXT_BUILD
    return false, status
end

function Public.Halt()
    PE:Safe(KEY, StopNow)
    if not broken then status = nil end
end

function Public.Reason()
    return status
end

-- 0.18.0 (Arrange it yourself): the spots read again from the plan, and the panels and the
-- two frames under them placed there. For a move made while the pictures show; a session
-- that starts with the pieces moved is built there by Build. Our own frames only. Out of a
-- fight (its one caller, ControllerLayout.lua's placement, runs there). True when placed.
function Public.Place()
    if not holder or not builtSize or PE:InCombat() then return false end
    local face, spots = FaceNumbers(builtSize)
    for name, key in pairs(SPOT_KEYS) do
        local c = spots[key[1]][key[2]]
        centres[name] = { x = c.x, y = c.y }
    end
    for side, r in ipairs(BackingRects(face, spots, panelScale, builtSize)) do
        local f = backings[side]
        if f then
            f:ClearAllPoints()
            f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", r[1], r[2])
            f:SetSize(r[3] - r[1], r[4] - r[2])
        end
    end
    ApplyState()
    return true
end

Face["Start"] = function(_, whenOff, size, useHook) return Public.Start(whenOff, size, useHook) end
Face["Place"] = function() local ok, placed = PE:Safe(KEY, Public.Place) return ok and placed or false end
Face["Stop"] = function() Public.Halt() end
Face["Status"] = function() return Public.Reason() end
