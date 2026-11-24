local ADDON_NAME, PE = ...

-- Face bars: our own spell pictures for the game's four controller bars
-- (Controller layout 0.13.0, spec 2026-11-23-controller-layout-0.13.0-face-bars.md;
-- the Blizzard facts are in docs/11-23-face-bars/SOURCE-BRIEF.md).
--
-- The game's real bars stay whole and keep taking every press; they are made
-- invisible by setting their four anchors' see-through to 0, and this file draws
-- one picture per real button where the layout wants it: the d-pad halves left of
-- the map, the face-button halves right of it.
--
--   PE.FaceBars:Start()   out of a fight; builds once, binds to the real buttons,
--                         shows the pictures, then makes the real bars invisible.
--                         Returns true, or false and a plain reason.
--   PE.FaceBars:Stop()    any time, also in a fight: the real bars back to full
--                         strength, the pictures hidden, events dropped.
--   PE.FaceBars:Status()  nil while fine or stopped; else why the game's own bars
--                         are showing.
--
-- It is part of Controller layout (error key "ctrlLayout") and has no switch of its
-- own. Nothing is made, hooked or registered until the first Start. While stopped
-- no event is registered and nothing ticks; the hooks (each installed once, as
-- hooksecurefunc and HookScript cannot be taken off) return at once. While started
-- every hook and event only marks what changed, and one OnUpdate on the next frame
-- does the work and removes itself. No timer of our own.
--
-- Display only: plain frames on UIParent, no secure templates, no click handler.
-- Each picture takes the mouse, so a tap on it (or the game's cursor) never
-- reaches a hidden button. Nothing is ever written into Blizzard's tables or
-- frames except the four anchors' see-through (SetAlpha is not a protected call:
-- device-proven on the bars, docs/11-23-face-bars/EVIDENCE.md) and the hooks.
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
--     both NeverSecret (DOC/SpellSharedDocumentation.lua:26-31).
--   * CooldownFrameTemplate: Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3.
--   * The active bar: PageUnit:RegisterActiveActionBarUpdatedCallback(fn, name)
--     (G/PageUnit.lua:705-707), called as fn(name) from SetActiveActionBar (:527-540)
--     on every trigger check, changed or not; PageUnit:GetActiveBar() (:542-544).
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

local Face = {}
PE.FaceBars = Face

local KEY = "ctrlLayout"
local CALLBACK_NAME = "PocketEssentialsFace"   -- a string: a number is refused (CallbackRegistry.lua:121-122)
local ERROR_LIMIT = 3                          -- errors in a session before the pictures turn off
local QUIET_ALPHA = 0.5                        -- the bars not in use

-- The contract's numbers (plan "The contract between the two halves"), used when
-- PE.LayoutPlan does not carry them: a picture 28 units, a diamond's buttons 30
-- left and right and 19 up and down of its centre (88 by 66).
local FACE_DEFAULT = { button = 28, dx = 30, dy = 19 }
local SPOTS_DEFAULT = {
    main = { dpad = { x = -199, y = 39 },  face = { x = 199, y = 39 } },
    lt   = { dpad = { x = -199, y = 113 }, face = { x = 199, y = 113 } },
    rt   = { dpad = { x = -297, y = 39 },  face = { x = 297, y = 39 } },
    both = { dpad = { x = -297, y = 113 }, face = { x = 297, y = 113 } },
}

-- The four groups, each tied to one of the game's bar anchors.
local GROUPS = {
    { key = "main", anchor = "TopCenteredAnchor" },
    { key = "lt", anchor = "LeftCenteredAnchor", tag = "LT" },
    { key = "rt", anchor = "RightCenteredAnchor", tag = "RT" },
    { key = "both", anchor = "BottomCenteredAnchor", tag = "LT+RT" },
}
-- The bars that can take an anchor's place, in the order they win.
local OVERRIDES = { "friendlyTargetingBar", "hostileTargetingBar", "shortcutsBar", "possessBar", "stanceBar" }
-- A diamond's four spots in press order (left, up, right, down), in steps of dx and dy.
local SPOT_STEPS = { { -1, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 } }
local EVENTS = { "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_STATE",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "UPDATE_POSSESS_BAR" }

local TEXT_NO_BARS = "the game's spell bars were not found"
local TEXT_NO_BUTTONS = "the game's spell buttons were not found"
local TEXT_NO_COOLDOWN = "this game version cannot draw cooldowns on our pictures"
local TEXT_NO_HOOKS = "this game version does not let addons follow its buttons"
local TEXT_BUILD = "the spell pictures could not be made"
local TEXT_ERROR = "Pocket Essentials' spell pictures hit an error"
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
local groups = {}         -- [1..4] = { def, frame, pics = { [1..8] = picture }, anchor, bar, tags }
local buttonPic = {}      -- [real button] = picture, for the buttons bound now
local hooked = {}         -- [real button or Blizzard frame] = true: its hooks are on
local callbackSet, alertsHooked, pageHooked, mainHooked = false, false, false, false
local settingAlpha = false
local lastActive          -- the bar the game last named active (false: none or unreadable)
local activeGroup         -- index of the group in use, or nil (all at full strength)

local pending = false     -- the OnUpdate is set
local bindDirty, picsDirty, stateDirty, cooldownDirty, alphaDirty = false, false, false, false, false
local Flush, OnUpdate     -- set below

-- Read only, for the offline tests and for looking around in /dump: the groups and
-- their pictures. Never written from outside.
Face.view = groups

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

local function Failed()
    errorCount = errorCount + 1
    if errorCount < ERROR_LIMIT or broken then return end
    broken = true
    pcall(StopNow)
    status = TEXT_ERROR
    Note("turned off after " .. errorCount .. " errors")
    PE:Print(CHAT_ERROR)
    RefreshPanel()
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
    if pending or not driver then return end
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
    return cd
end

-- One picture, centred at (x, y) UI units from the screen's bottom centre. quad is
-- its spot in the diamond (1 left, 2 up, 3 right, 4 down); dpad draws the glyph as
-- a plus, else as four dots.
local function MakePicture(parent, x, y, size, quad, dpad)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(size, size)
    p:SetPoint("CENTER", UIParent, "BOTTOM", x, y)
    p:EnableMouse(true) -- takes a tap and does nothing with it
    local pic = { frame = p }

    pic.glow = p:CreateTexture(nil, "BACKGROUND", nil, -8)
    pic.glow:SetPoint("TOPLEFT", p, "TOPLEFT", -3, 3)
    pic.glow:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 3, -3)
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
    pic.icon:SetPoint("TOPLEFT", p, "TOPLEFT", 1.5, -1.5)
    pic.icon:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1.5, 1.5)
    pic.icon:Hide()
    pic.dim = p:CreateTexture(nil, "OVERLAY")
    pic.dim:SetAllPoints(pic.icon)
    pic.dim:SetColorTexture(0, 0, 0, 0.55)
    pic.dim:Hide()

    pic.cd = NewCooldown(p)
    if not pic.cd then return nil end
    pic.cd:SetAllPoints(pic.icon)

    -- Above the cooldown's sweep: the position glyph, the range dot and the count.
    local over = CreateFrame("Frame", nil, p)
    over:SetAllPoints(p)
    over:SetFrameLevel(p:GetFrameLevel() + 2)
    local glyph = over:CreateTexture(nil, "ARTWORK")
    glyph:SetSize(11, 11)
    glyph:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    glyph:SetColorTexture(0, 0, 0, 0.7)
    if dpad then
        local mid = over:CreateTexture(nil, "OVERLAY")
        mid:SetSize(3, 3)
        mid:SetPoint("CENTER", glyph, "CENTER", 0, 0)
        mid:SetColorTexture(1, 1, 1, 0.35)
    end
    for k, step in ipairs(SPOT_STEPS) do
        local dot = over:CreateTexture(nil, "OVERLAY")
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", glyph, "CENTER", step[1] * 3, step[2] * 3)
        dot:SetColorTexture(1, 1, 1, k == quad and 1 or 0.35)
    end
    pic.range = over:CreateTexture(nil, "OVERLAY")
    pic.range:SetSize(4, 4)
    pic.range:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -2)
    pic.range:SetColorTexture(1, 1, 1, 1)
    pic.range:Hide()
    pic.count = SmallText(over, 9)
    pic.count:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1, 1)
    pic.count:SetJustifyH("RIGHT")
    return pic
end

local function FaceNumbers()
    local plan = PE.LayoutPlan
    local face, spots = FACE_DEFAULT, SPOTS_DEFAULT
    if type(plan) == "table" then
        if type(plan.FACE) == "table" and type(plan.FACE.button) == "number" then face = plan.FACE end
        local faceSpots = plan.FaceSpots -- ControllerLayout.lua's, when it has it
        if type(faceSpots) == "function" then
            local ok, s = pcall(faceSpots)
            if ok and type(s) == "table" and type(s.main) == "table" then spots = s end
        end
    end
    return face, spots
end

local OnEvent -- below

-- Makes every frame, once. Returns true, or false and the reason.
local function Build()
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetAllPoints(UIParent)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", Guard(function(_, event) OnEvent(event) end))
    local face, spots = FaceNumbers()
    for gi, def in ipairs(GROUPS) do
        local gf = CreateFrame("Frame", nil, holder)
        gf:SetAllPoints(holder)
        local g = { def = def, frame = gf, pics = {}, tags = {} }
        local spot = spots[def.key] or SPOTS_DEFAULT[def.key]
        for half = 0, 1 do
            local centre = (half == 0) and spot.dpad or spot.face
            for q, step in ipairs(SPOT_STEPS) do
                local pic = MakePicture(gf, centre.x + step[1] * face.dx, centre.y + step[2] * face.dy, face.button, q, half == 0)
                if not pic then return false, TEXT_NO_COOLDOWN end
                g.pics[half * 4 + q] = pic
            end
            if def.tag then
                local tag = SmallText(gf, 8)
                tag:SetPoint("CENTER", UIParent, "BOTTOM", centre.x, centre.y)
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
    pic.back:SetColorTexture(1, 1, 1, 0.12) -- a faint outline
    pic.empty = true
end

local function ShowIcon(pic, r, g, b, grey)
    pic.icon:SetVertexColor(r, g, b)
    pic.icon:SetDesaturated(grey)
    pic.icon:Show()
    pic.back:SetColorTexture(0, 0, 0, 0.75)
    pic.empty = false
end

-- The real icon's texture, colour (secret: white) and greying.
local function CopyIcon(pic, icon)
    if not icon or not Shown(icon) then return ShowEmpty(pic) end
    local ok, tex = pcall(icon.GetTexture, icon)
    if not ok or (not IsSecret(tex) and (tex == nil or tex == "")) then return ShowEmpty(pic) end
    if not pcall(pic.icon.SetTexture, pic.icon, tex) then return ShowEmpty(pic) end
    pic.icon:SetTexCoord(0, 1, 0, 1)
    local r, g, b = Colour(icon)
    local okGrey, grey = pcall(icon.IsDesaturated, icon)
    ShowIcon(pic, r, g, b, okGrey and not IsSecret(grey) and grey == true)
end

-- The main bar's face buttons: the picture the game draws on them (an atlas, or a
-- texture with its texture coordinates, as for a raid marker).
local function CopySpecial(pic, sp)
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
    ShowIcon(pic, r, g, b, false)
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

-- Everything one picture copies from its real button, except the cooldown.
local function Refresh(pic)
    local b = pic.button
    if not b then
        pic.special = false
        ShowEmpty(pic)
        pic.range:Hide()
        pic.count:SetText("")
        pic.checked:Hide()
        pic.glow:Hide()
        return
    end
    local sp = Field(b, "SpecialActionIcon")
    pic.special = sp ~= nil and Shown(sp)
    if pic.special then CopySpecial(pic, sp) else CopyIcon(pic, Field(b, "icon")) end
    local range = Field(b, "RangeIndicator")
    if range and Shown(range) then
        pic.range:SetVertexColor(Colour(range))
        pic.range:Show()
    else
        pic.range:Hide()
    end
    -- The count goes from the game's text to ours as it is: in a fight it may be
    -- secret, which our SetText takes; it is never compared or changed.
    local count, text = Field(b, "Count"), ""
    if count then
        local ok, v = pcall(count.GetText, count)
        if ok then text = v end
    end
    if not pcall(pic.count.SetText, pic.count, text) then pic.count:SetText("") end
    RefreshChecked(pic)
    RefreshGlow(pic)
end

local function ClearCooldown(pic)
    if pic.cdOn then
        pcall(pic.cd.Clear, pic.cd)
        pic.cdOn = false
    end
    pic.dim:Hide()
end

-- The cooldown sweep from the game's duration object, and the icon darkened while
-- the game says the spell is on cooldown (not for the global cooldown).
local function RefreshCooldown(pic)
    local b = pic.button
    local slot = b and b.action
    if pic.empty or pic.special or IsSecret(slot) or type(slot) ~= "number" or slot < 1 then return ClearCooldown(pic) end
    local api = C_ActionBar
    if type(api) ~= "table" then return ClearCooldown(pic) end
    local ok, object = pcall(api.GetActionCooldownDuration, slot)
    if ok and (IsSecret(object) or object ~= nil) then ok = pcall(pic.cd.SetCooldownFromDurationObject, pic.cd, object) else ok = false end
    if ok then
        pic.cdOn = true
    elseif pic.cdOn then
        pcall(pic.cd.Clear, pic.cd)
        pic.cdOn = false
    end
    local dim = false
    local okInfo, info = pcall(api.GetActionCooldown, slot)
    if okInfo and not IsSecret(info) and type(info) == "table" then
        local active, gcd = info.isActive, info.isOnGCD
        dim = not IsSecret(active) and active == true and not (not IsSecret(gcd) and gcd == true)
    end
    pic.dim:SetShown(dim)
end

local function ApplyGroupAlpha()
    for i, g in ipairs(groups) do
        g.frame:SetAlpha((activeGroup == nil or activeGroup == i) and 1 or QUIET_ALPHA)
    end
end

---------------------------------------------------------------------------
-- Following the real buttons
---------------------------------------------------------------------------

local function MarkButton(b, slotChanged)
    if not running then return end
    local pic = buttonPic[b]
    if not pic then return end
    pic.dirty = true
    picsDirty = true
    if slotChanged then cooldownDirty = true end
    Schedule()
end

local function MarkAll()
    for _, g in ipairs(groups) do
        for _, pic in ipairs(g.pics) do pic.dirty = true end
    end
    picsDirty, cooldownDirty = true, true
end

local function Hook(t, name, fn)
    if type(t) == "table" and type(t[name]) == "function" then
        return pcall(hooksecurefunc, t, name, fn) and true or false
    end
    return false
end

-- The hooks on one real button and its pictures' regions, once; they only mark
-- the picture bound to that button, and do nothing while stopped or unbound.
local function HookButton(b)
    if hooked[b] then return end
    hooked[b] = true
    local mark = Guard(function() MarkButton(b) end)
    local icon = Field(b, "icon")
    for _, name in ipairs({ "SetTexture", "SetVertexColor", "SetDesaturated", "Show", "Hide" }) do Hook(icon, name, mark) end
    local sp = Field(b, "SpecialActionIcon")
    for _, name in ipairs({ "SetTexture", "SetAtlas", "SetTexCoord", "SetColorTexture", "SetVertexColor", "Show", "Hide" }) do
        Hook(sp, name, mark)
    end
    local range = Field(b, "RangeIndicator")
    for _, name in ipairs({ "SetVertexColor", "Show", "Hide" }) do Hook(range, name, mark) end
    Hook(Field(b, "Count"), "SetText", mark)
    if type(b.UpdateState) == "function" then Hook(b, "UpdateState", mark) end
    if type(b.UpdateAction) == "function" then Hook(b, "UpdateAction", Guard(function() MarkButton(b, true) end)) end
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
                pic.dirty = true
                picsDirty, cooldownDirty = true, true
            end
        end
    end
    HookOverrides()
end

-- Which group the game's active bar belongs to; a change re-binds and sets the
-- groups' strength. Called on every trigger check, so nothing happens without a change.
local function ReadActive()
    local bar = false
    if pageUnit and type(pageUnit.GetActiveBar) == "function" then
        local ok, b = pcall(pageUnit.GetActiveBar, pageUnit)
        if ok and not IsSecret(b) and type(b) == "table" then bar = b end
    end
    if bar == lastActive then return false end
    lastActive = bar
    local group = callbackSet and bar and GroupOfBar(bar) or nil
    if group ~= activeGroup then
        activeGroup = group
        alphaDirty = true
    end
    bindDirty = true
    return true
end

local onActiveBar = Guard(function()
    if running and ReadActive() then Schedule() end
end)

Flush = function()
    if driver then driver:SetScript("OnUpdate", nil) end
    pending = false
    if not running then return end
    if bindDirty then
        bindDirty = false
        Rebind()
    end
    if picsDirty then
        picsDirty = false
        for _, g in ipairs(groups) do
            for _, pic in ipairs(g.pics) do
                if pic.dirty then
                    pic.dirty = false
                    Refresh(pic)
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
    if cooldownDirty then
        cooldownDirty = false
        for _, g in ipairs(groups) do
            for _, pic in ipairs(g.pics) do RefreshCooldown(pic) end
        end
    end
    if alphaDirty then
        alphaDirty = false
        ApplyGroupAlpha()
    end
end
OnUpdate = Guard(function() Flush() end)

OnEvent = function(event)
    if not running then return end
    if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        cooldownDirty = true
    elseif event == "ACTIONBAR_UPDATE_STATE" then
        stateDirty = true
    else
        bindDirty = true
        MarkAll()
    end
    Schedule()
end

-- The hooks that are not per button, once each.
local function HookOnce(root)
    if not mainHooked and type(root.HookScript) == "function" then
        mainHooked = true
        -- The pictures hide while the game hides its bars (binding editor, Gamepad UI off).
        pcall(root.HookScript, root, "OnShow", Guard(function() if running and holder then holder:Show() end end))
        pcall(root.HookScript, root, "OnHide", Guard(function() if running and holder then holder:Hide() end end))
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
        local glow = Guard(function(_, button) MarkButton(button) end)
        if type(manager.ShowAlert) == "function" then Hook(manager, "ShowAlert", glow) end
        if type(manager.HideAlert) == "function" then Hook(manager, "HideAlert", glow) end
    end
    if not callbackSet and type(pageUnit.RegisterActiveActionBarUpdatedCallback) == "function" then
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
    bindDirty, picsDirty, stateDirty, cooldownDirty, alphaDirty = false, false, false, false, false
    if holder then holder:Hide() end
    for b in pairs(buttonPic) do buttonPic[b] = nil end
    for _, g in ipairs(groups) do
        g.bar = nil
        for _, pic in ipairs(g.pics) do
            pic.button = nil
            ClearCooldown(pic)
        end
    end
    lastActive, activeGroup = nil, nil
end

-- Raises only on a bug; Start counts it.
local function StartNow()
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
        local ok, made, why = pcall(Build)
        if not ok or not made then
            buildFailed = (ok and why) or TEXT_BUILD
            if not ok then PE:LogError(KEY, "The spell pictures could not be made: " .. tostring(made)) end
            if holder then holder:Hide() end
            return Fail(buildFailed)
        end
    end
    for i, g in ipairs(groups) do g.anchor = anchors[i] end
    HookOnce(root)

    running = true
    status = nil
    for _, event in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, event) end
    lastActive, activeGroup = nil, nil
    ReadActive()
    bindDirty, alphaDirty = true, true
    MarkAll()
    Flush() -- the pictures are right before the real bars go invisible
    holder:SetShown(Shown(root))
    faded = true
    SetAnchorsAlpha(0)
    Note("on" .. (callbackSet and "" or " (no active-bar callback: every bar at full strength)"))
    return true
end

-- The three are set with the bracket form on purpose: tests/api/extract.lua treats a
-- name this addon defines as its own, and "Stop" is also the game's animation call.
local Public = {}

function Public.Start()
    if broken then return false, status end
    if PE:InCombat() then return false, TEXT_FIGHT end
    local ok, started, reason = PE:Safe(KEY, StartNow)
    if ok then return started, reason end
    pcall(StopNow)
    Failed()
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

Face["Start"] = function() return Public.Start() end
Face["Stop"] = function() Public.Halt() end
Face["Status"] = function() return Public.Reason() end
