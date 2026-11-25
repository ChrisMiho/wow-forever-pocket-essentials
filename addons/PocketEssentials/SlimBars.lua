local ADDON_NAME, PE = ...

-- Slim bars: our own plain bars for the player, the pet, the target, the target's target
-- and the target's cast (Controller layout 0.17.0, spec 2026-11-24-0.17.0-slim-bars.md; the
-- Blizzard facts are cited line by line below).
--
-- The game's four unit frames stay whole and alive; they are made invisible by setting
-- their see-through to 0, out of a fight, and this file draws one flat bar per frame where
-- the layout wants it (ControllerLayout.lua, Plan.SlimRects). The buff and debuff boxes
-- are not built yet; the plan keeps their room.
--
--   PE.SlimBars:Start()   out of a fight; builds once, shows the bars, then makes the
--                         game's frames invisible. Returns true, or false and a plain
--                         reason. Called again while running it only checks that the
--                         game's frames are still invisible and places the tap guards.
--   PE.SlimBars:Stop()    the game's frames get their see-through back, the bars hide,
--                         every event is dropped. In a fight it waits for the fight to end
--                         (nothing of the game's is changed in a fight) and the bars stay
--                         until then.
--   PE.SlimBars:Status()  nil while fine or stopped; else why the bars are off.
--
-- It is part of Controller layout (error key "ctrlLayout") behind that feature's row
-- "Slim bars", Off by default; ControllerLayout.lua calls this file only in a session
-- that began with the row On (Snap.SlimCall). Nothing is made, registered or called until
-- the first Start; there is no hook at all. While stopped no event is registered and
-- nothing ticks. While started everything is driven by the game's events; the one
-- OnUpdate is on the cast bar's own frame and is set only while a cast shows.
--
-- Display only: plain frames on UIParent, no secure templates, no click handler; the bars
-- do not take the mouse. Over each of the game's invisible frames sits one plain frame of
-- ours that takes the mouse and does nothing, so a tap on what looks like empty ground
-- cannot target or open a menu (the frames take taps at see-through 0: each is a
-- SecureUnitButtonTemplate, left click targets and right click opens the menu,
-- Blizzard_FrameXML/SecureTemplates.lua:828-839). Nothing is ever written into Blizzard's
-- tables or frames except the four frames' see-through.
--
-- Values the game hides in a fight ("secret" values) are handed straight to the widget
-- calls that take them from an addon, and never compared, added, joined or tested here:
-- see Widget below.
--
-- Where the facts come from (paths under Interface/AddOns/ of the forever branch, build
-- 1.60.1.71091; U/ = Blizzard_UnitFrame/, E/ = Blizzard_EditMode/Shared/,
-- DOC/ = Blizzard_APIDocumentationGenerated/):
--   * The four frames: PlayerFrame (U/Mainline/PlayerFrame.xml:14), PetFrame
--     (U/Mainline/PetFrame.xml:11), TargetFrame (U/Mainline/TargetFrame.xml:549) and its
--     totFrame (U/Mainline/TargetFrame.lua:732-737, the target frame's child, as is the
--     game's target cast bar, :705-715). The pet frame is made as the player frame's child
--     but Edit Mode moves it to UIParent once it has a spot of its own
--     (E/EditModeSystemTemplates.lua:335-343, 350-365), so each frame gets its own call.
--   * SetAlpha and GetAlpha on them are the engine's own: the unit frames are Edit Mode
--     systems, and Edit Mode replaces only SetScale, SetPoint, ClearAllPoints, SetShown and
--     Hide with Lua (E/EditModeSystemTemplates.lua:11-18, 33-36); none of those five is
--     called here. The engine's SetAlpha is not a protected call in the documentation
--     (DOC/SimpleFrameAPIDocumentation.lua:1134).
--   * The game does not set these frames' see-through itself: Edit Mode's Opacity setting
--     (E/EditModeSystemTemplates.lua:1586-1591) is applied only where a layout has it
--     (:1654, :1691-1692), and only the party, raid and arena frames have it
--     (Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:303, 328, 365). No part of the
--     frames ignores its parent's see-through.
--   * What may come back hidden: UnitHealth (DOC/UnitDocumentation.lua:1526), UnitHealthMax
--     (:1472), UnitPower (:2732), UnitPowerMax (:2801), UnitName (:2489), and from
--     UnitCastingInfo and UnitChannelInfo everything but isTradeskill, the bar id and the
--     delay (:828-852, :870-894). Not marked as hidden, so used to decide: UnitExists
--     (:1192), UnitLevel (:2474), UnitCanAttack (:763), UnitIsTapDenied (:2365),
--     UnitPowerType (:2859).
--   * The widget calls that take a hidden value from an addon (SecretArguments
--     "AllowedWhenTainted"): StatusBar:SetMinMaxValues and SetValue
--     (DOC/SimpleStatusBarAPIDocumentation.lua:229, 355), FontString:SetText
--     (DOC/SimpleFontStringAPIDocumentation.lua:664).
--   * The cast bar: the game's own (Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua)
--     listens to the events below for its unit (:238-250), reads UnitCastingInfo or
--     UnitChannelInfo at a start (:360-369), and works out "now minus start" itself
--     (:396-401). Ours gives the bar the two times as its ends and GetTime() * 1000, our
--     own clock, as its value, so the widget does the sum. StatusBar:SetTimerDuration is
--     not used: it takes hidden values from the game's own code only
--     (DOC/SimpleStatusBarAPIDocumentation.lua:334-336).
--   * The target of target: the game sends no health event for it and reads it every frame
--     (U/Mainline/TargetFrame.lua:887-890, 907). Here it is read again when the target or
--     its target changes and whenever a health event comes for the player, the pet or the
--     target.
--   * Events (DOC/UnitDocumentation.lua): PLAYER_LEVEL_UP 3832, PLAYER_TARGET_CHANGED 3976,
--     UNIT_DISPLAYPOWER 4237, UNIT_FACTION 4259, UNIT_HEALTH 4320, UNIT_LEVEL 4353,
--     UNIT_MAXHEALTH 4398, UNIT_MAXPOWER 4409, UNIT_NAME_UPDATE 4431, UNIT_PET 4451,
--     UNIT_POWER_UPDATE 4554, UNIT_SPELLCAST_CHANNEL_START 4615, _CHANNEL_STOP 4629,
--     _CHANNEL_UPDATE 4644, _DELAYED 4658, _FAILED 4716, _INTERRUPTED 4744, _START 4819,
--     _STOP 4833, UNIT_TARGET 4871; PLAYER_ENTERING_WORLD (DOC/SystemDocumentation.lua:136).
--     Unit events are registered with RegisterUnitEvent (DOC/SimpleFrameAPIDocumentation.lua:1064),
--     as the game's own frames do (U/Mainline/UnitFrame.lua:90-125, 856).
--   * The bar texture, Interface\TargetingFrame\UI-StatusBar, is the one the game's own
--     mana bar uses (U/Mainline/UnitFrame.lua:425); the power colours are the game's
--     (U/Mainline/PowerBarColorUtil.lua:18-21), mana lightened to read on a dark ground.
--   * Layers: the game's unit frames are LOW (PlayerFrame.xml:14, TargetFrame.xml:52,
--     PetFrame.xml:11); the bars and the tap guards are MEDIUM, as the spell pictures are:
--     above the invisible frames, under an open spell wheel (DIALOG).

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring
local format = string.format

local Slim = {}
PE.SlimBars = Slim

local KEY = "ctrlLayout"
local ERROR_LIMIT = 3      -- errors in a session before the bars turn themselves off
local CHECK_EVERY = 0.5    -- while a cast shows: how often the game is asked whether it still goes
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local GROUND_ALPHA = 0.6   -- the dark see-through ground under a bar

local COLOUR = {
    friend = { 0.10, 0.65, 0.20 },
    enemy = { 0.80, 0.15, 0.15 },
    tapped = { 0.50, 0.50, 0.50 },
    stopped = { 0.35, 0.35, 0.35 }, -- a fill whose widget refused the game's value (see Mark)
    cast = { 0.90, 0.70, 0.10 },
}
local POWER = {
    MANA = { 0.20, 0.40, 1.00 },
    RAGE = { 1.00, 0.00, 0.00 },
    FOCUS = { 1.00, 0.50, 0.25 },
    ENERGY = { 1.00, 1.00, 0.00 },
}

local TEXT_NO_PLAN = "the layout's numbers for them are missing"
local TEXT_BUILD = "they could not be made"
local TEXT_ERROR = "they hit an error"
local TEXT_FIGHT = "waiting for the fight to end"
local CHAT_ERROR = "Slim bars turned off after an error; the game's own frames are back. Reload to try again."
local CHAT_ERROR_FIGHT = "Slim bars turned off after an error; the game's own frames come back when this fight ends. Reload to try again."

-- The four bars that stand for a unit. key: the name in `bars`; unit: the game's unit;
-- rect: the name in Plan.SlimRects; main: health, power, level and the health number
-- (else health and name only); hostile: the health colour follows whether it can be attacked.
local BARS = {
    { key = "player", unit = "player", rect = "player bar", label = "player bar", main = true },
    { key = "pet", unit = "pet", rect = "pet bar", label = "pet bar" },
    { key = "target", unit = "target", rect = "target bar", label = "target bar", main = true, hostile = true },
    { key = "tot", unit = "targettarget", rect = "target of target bar", label = "target of target bar", hostile = true },
}
-- The game's four frames, in the order they are made invisible; key: the bar that stands
-- for it (its tap guard shows while that bar does).
local GAME = {
    { key = "player", label = "the game's player frame", get = function() return PlayerFrame end },
    { key = "pet", label = "the game's pet frame", get = function() return PetFrame end },
    { key = "target", label = "the game's target frame", get = function() return TargetFrame end },
    { key = "tot", label = "the game's target of target frame",
      get = function() local t = TargetFrame return type(t) == "table" and t.totFrame or nil end },
}

-- The unit events, and which of our two listening frames gets them.
local OWN_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_PET" }                       -- for "player" and "pet"
local TARGET_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_TARGET",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP" }                                      -- for "target"
local PLAIN_EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_LEVEL_UP" }
-- Why the cast bar hides when one of these arrives and the game says no cast is going.
local CAST_ENDS = {
    UNIT_SPELLCAST_STOP = "the cast ended",
    UNIT_SPELLCAST_CHANNEL_STOP = "the channel ended",
    UNIT_SPELLCAST_FAILED = "the cast failed",
    UNIT_SPELLCAST_INTERRUPTED = "interrupted",
    UNIT_SPELLCAST_START = "the cast ended",
    UNIT_SPELLCAST_DELAYED = "the cast ended",
    UNIT_SPELLCAST_CHANNEL_START = "the channel ended",
    UNIT_SPELLCAST_CHANNEL_UPDATE = "the channel ended",
}

local running = false     -- started: the bars show and follow the game's events
local stopping = false    -- Stop was asked in a fight and waits for its end
local broken = false      -- turned off after errors, until a reload
local built = false
local status              -- why the bars are off, or nil
local buildFailed         -- the reason the bars could not be made (kept: not tried again)
local errorCount = 0
local logged = {}         -- [text] = true: each of these goes to the debug log once
local refused = {}        -- [what] = true: that widget call's refusal is in the debug log

local api = {}            -- the game's functions by name, read at the first Start
local holder              -- the bars' and the tap guards' parent
local plainFrame, ownFrame, targetFrame -- the three frames that listen
local bars = {}           -- [key] = { def, frame, health, power, name, level, value, shown, colour, powerToken }
local cast                -- { frame, bar, text, shown, since, onUpdate }
local guards = {}         -- [key] = the plain frame of ours over that game frame
local guardPlaced = {}    -- [key] = true once that guard has a place (its game frame's place could be read)
local gameAlpha = {}      -- [game frame] = its see-through as read before the first change
local gameOrder = {}      -- the frames in gameAlpha, in order

-- Read only, for the offline tests and for looking around in /dump. Never written from outside.
Slim.view = { bars = bars, guards = guards }

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Note(text)
    if PE.debugOn then PE:Debug(KEY, "slim bars: " .. text) end
end

-- The same line once a session.
local function Once(text)
    if logged[text] then return end
    logged[text] = true
    Note(text)
end

local function RefreshPanel()
    if PE.RefreshSettings then pcall(PE.RefreshSettings, PE) end
end

---------------------------------------------------------------------------
-- The game's functions and the widget calls, each guarded and named in the log
---------------------------------------------------------------------------

local function ReadApi()
    api.UnitExists, api.UnitHealth, api.UnitHealthMax = UnitExists, UnitHealth, UnitHealthMax
    api.UnitPower, api.UnitPowerMax, api.UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
    api.UnitName, api.UnitLevel = UnitName, UnitLevel
    api.UnitCanAttack, api.UnitIsTapDenied = UnitCanAttack, UnitIsTapDenied
    api.UnitCastingInfo, api.UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
    api.GetTime = GetTime
end

local function Answer(name, ok, ...)
    if ok then return true, ... end
    Once(name .. " failed: " .. tostring((...)))
    return false
end

-- One of the game's functions by name: true and its answers, or false (said once in the
-- debug log: missing, or what it raised). The answers may be hidden values.
local function Game(name, ...)
    local fn = api[name]
    if type(fn) ~= "function" then
        Once(name .. " is missing on this client")
        return false
    end
    return Answer(name, pcall(fn, ...))
end

-- One widget call on a region of ours. Its arguments may be hidden values: they are passed
-- on as they came and nothing here looks at them. True if the widget took them; a refusal
-- is said once in the debug log under `what`.
local function Widget(what, region, method, ...)
    local fn = region[method]
    if type(fn) ~= "function" then
        Once(what .. " is missing on this client")
        return false
    end
    local ok, err = pcall(fn, region, ...)
    -- Said once; a call that keeps failing (every health event of a fight) builds no text.
    if not ok and not refused[what] then
        refused[what] = true
        Note(what .. " failed: " .. tostring(err))
    end
    return ok
end

-- True for a plain nil (a hidden value is never compared, not even with nil).
local function Nothing(v)
    return not IsSecret(v) and v == nil
end

---------------------------------------------------------------------------
-- Errors: every handler runs through PE:Wrap; a run that ends in an error is counted, and
-- the third turns the bars off for the session.
---------------------------------------------------------------------------

local StopNow, ShowGame -- below

local function Failed()
    errorCount = errorCount + 1
    if errorCount < ERROR_LIMIT or broken then return end
    broken = true
    status = TEXT_ERROR
    Note("turned off after " .. errorCount .. " errors")
    local inFight = PE:InCombat()
    -- Our bars hide at once (no stale numbers); the game's frames come back out of a fight.
    -- Until then they are still invisible and still take a tap, so the tap guards stay
    -- over them, and go only after the game's frames are back.
    pcall(StopNow, "an error", inFight)
    if inFight then
        PE:RunOutOfCombat("ctrlLayout:slimBack", function() StopNow("an error") end)
    end
    PE:Print(inFight and CHAT_ERROR_FIGHT or CHAT_ERROR)
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

---------------------------------------------------------------------------
-- What a bar shows
---------------------------------------------------------------------------

-- A bar whose widget refused the game's value would stand still and look healthy. So a
-- health or power fill that could not be fed goes grey and the health number reads "?"
-- (a plain text of ours), until a later feed works or the bars start again.
-- part: "health" or "power"; ok: whether every widget call of this feed was taken.
local function Mark(bar, part, ok)
    local fill = bar[part]
    if ok then
        if bar.stopped[part] then
            bar.stopped[part] = nil
            local c = (part == "health") and bar.colour or bar.powerColour
            fill:SetStatusBarColor(c[1], c[2], c[3])
        end
        return
    end
    if not bar.stopped[part] then
        bar.stopped[part] = true
        local c = COLOUR.stopped
        fill:SetStatusBarColor(c[1], c[2], c[3])
    end
    if part == "health" and bar.value then bar.value:SetText("?") end
end

local function UpdateHealth(bar)
    local unit = bar.def.unit
    local okMax, most = Game("UnitHealthMax", unit)
    local okNow, now = Game("UnitHealth", unit)
    if not (okMax and okNow) or Nothing(most) or Nothing(now) then return end
    local ok = Widget("StatusBar:SetMinMaxValues (health)", bar.health, "SetMinMaxValues", 0, most)
    ok = Widget("StatusBar:SetValue (health)", bar.health, "SetValue", now) and ok
    if bar.value then ok = Widget("FontString:SetText (the health number)", bar.value, "SetText", now) and ok end
    Mark(bar, "health", ok)
end

-- colour: also read the power's kind and colour the bar (at a start, and when the kind changes).
local function UpdatePower(bar, colour)
    if not bar.power then return end
    local unit = bar.def.unit
    if colour then
        local ok, _, token = Game("UnitPowerType", unit)
        local c = POWER.MANA
        if ok and not IsSecret(token) and type(token) == "string" and POWER[token] then c = POWER[token] end
        if bar.powerColour ~= c then
            bar.powerColour = c
            if not bar.stopped.power then bar.power:SetStatusBarColor(c[1], c[2], c[3]) end
        end
    end
    local okMax, most = Game("UnitPowerMax", unit)
    local okNow, now = Game("UnitPower", unit)
    if not (okMax and okNow) or Nothing(most) or Nothing(now) then return end
    local ok = Widget("StatusBar:SetMinMaxValues (power)", bar.power, "SetMinMaxValues", 0, most)
    ok = Widget("StatusBar:SetValue (power)", bar.power, "SetValue", now) and ok
    Mark(bar, "power", ok)
end

local function UpdateName(bar)
    local ok, name = Game("UnitName", bar.def.unit)
    if not ok or Nothing(name) then return end
    Widget("FontString:SetText (a name)", bar.name, "SetText", name)
end

-- level: the new level when the game just said it (PLAYER_LEVEL_UP), else read.
local function UpdateLevel(bar, level)
    if not bar.level then return end
    if level == nil then
        local ok, read = Game("UnitLevel", bar.def.unit)
        if not ok or Nothing(read) then return end
        level = read
    end
    if not IsSecret(level) then
        -- A level the game does not tell (a skull) reads as -1.
        level = (type(level) == "number" and level > 0) and tostring(level) or "??"
    end
    Widget("FontString:SetText (a level)", bar.level, "SetText", level)
end

local function UpdateColour(bar)
    local c = COLOUR.friend
    if bar.def.hostile then
        local ok, attack = Game("UnitCanAttack", "player", bar.def.unit)
        if not ok then return end
        if IsSecret(attack) then
            Once("UnitCanAttack's answer is hidden: the " .. bar.def.label .. " keeps its colour")
            return
        end
        if attack == true then
            c = COLOUR.enemy
            local okTap, tapped = Game("UnitIsTapDenied", bar.def.unit)
            if okTap and not IsSecret(tapped) and tapped == true then c = COLOUR.tapped end
        end
    end
    if bar.colour ~= c then
        bar.colour = c
        if not bar.stopped.health then bar.health:SetStatusBarColor(c[1], c[2], c[3]) end
    end
end

-- true or false; nil when the game's answer cannot be used (the bar then stays as it is).
local function Exists(unit)
    local ok, there = Game("UnitExists", unit)
    if not ok then return nil end
    if IsSecret(there) then
        Once("UnitExists's answer is hidden: a bar keeps its state")
        return nil
    end
    return there == true
end

-- Shows or hides one bar and its tap guard; one line in the debug log per change.
local function ShowBar(key, show, why)
    local bar = bars[key]
    if show == nil or bar.shown == show then return end
    bar.shown = show
    local guard = guardPlaced[key] and guards[key] or nil
    if show then
        bar.frame:Show()
        if guard then guard:Show() end
    else
        bar.frame:Hide()
        if guards[key] then guards[key]:Hide() end
    end
    Note(bar.def.label .. (show and " shown" or " hidden") .. (why and (": " .. why) or ""))
end

---------------------------------------------------------------------------
-- The cast bar
---------------------------------------------------------------------------

-- What the target casts now: "cast" or "channel", the name to show and the two times as
-- the game gave them (any of the three may be hidden); nil when it casts nothing. Decided
-- by the sixth answer, isTradeskill, which the game never hides and which is there exactly
-- while a cast is (DOC/UnitDocumentation.lua:845, 887).
local function CastInfo()
    local ok, _, text, _, from, to, trade = Game("UnitCastingInfo", "target")
    if ok and (IsSecret(trade) or trade ~= nil) then return "cast", text, from, to end
    ok, _, text, _, from, to, trade = Game("UnitChannelInfo", "target")
    if ok and (IsSecret(trade) or trade ~= nil) then return "channel", text, from, to end
    return nil
end

local function CastTick()
    local ok, now = Game("GetTime")
    if ok and type(now) == "number" then Widget("StatusBar:SetValue (the time)", cast.bar, "SetValue", now * 1000) end
end

local function HideCast(why)
    if not cast.shown then return end
    cast.shown = false
    cast.bar:SetScript("OnUpdate", nil)
    cast.frame:Hide()
    Note("cast bar hidden: " .. tostring(why))
end

-- Reads the target's cast again and shows, refills or hides the bar. why: the reason to
-- give if nothing is being cast.
local function RefreshCast(why)
    if not bars.target.shown then return HideCast("no target") end
    local kind, text, from, to = CastInfo()
    if not kind then return HideCast(why) end
    -- The two times as the bar's ends, straight from the game; our own clock as its value.
    if Nothing(from) or Nothing(to)
        or not Widget("StatusBar:SetMinMaxValues (a cast's times)", cast.bar, "SetMinMaxValues", from, to) then
        return HideCast("the bar could not take the cast's times")
    end
    CastTick()
    Widget("FontString:SetText (a spell's name)", cast.text, "SetText", text)
    if not cast.shown then
        cast.shown = true
        cast.since = 0
        cast.frame:Show()
        cast.bar:SetScript("OnUpdate", cast.onUpdate)
        Note("cast bar shown: the target is " .. (kind == "channel" and "channelling" or "casting"))
    end
end

---------------------------------------------------------------------------
-- Reading everything again
---------------------------------------------------------------------------

local function RefreshPlayer()
    local bar = bars.player
    ShowBar("player", true)
    UpdateHealth(bar)
    UpdatePower(bar, true)
    UpdateName(bar)
    UpdateLevel(bar)
end

local function RefreshPet()
    local there = Exists("pet")
    ShowBar("pet", there, there and "a pet is out" or "no pet")
    local bar = bars.pet
    if bar.shown then
        UpdateColour(bar)
        UpdateHealth(bar)
        UpdateName(bar)
    end
end

local function RefreshTot()
    local bar = bars.tot
    if not bars.target.shown then
        ShowBar("tot", false, "no target")
        return
    end
    local there = Exists("targettarget")
    ShowBar("tot", there, there and "the target has a target" or "the target has no target")
    if bar.shown then
        UpdateColour(bar)
        UpdateHealth(bar)
        UpdateName(bar)
    end
end

local function RefreshTarget()
    local there = Exists("target")
    ShowBar("target", there, there and "a target" or "no target")
    local bar = bars.target
    if bar.shown then
        UpdateColour(bar)
        UpdateHealth(bar)
        UpdatePower(bar, true)
        UpdateName(bar)
        UpdateLevel(bar)
    end
    RefreshTot()
    RefreshCast("the target changed")
end

local function RefreshAll()
    RefreshPlayer()
    RefreshPet()
    RefreshTarget()
end

---------------------------------------------------------------------------
-- The game's four frames: invisible, and back
---------------------------------------------------------------------------

local function PlainNumber(v)
    return not IsSecret(v) and type(v) == "number"
end

-- Out of a fight only. again: a later check (the debug log then says "again").
local function HideGame(again)
    for _, g in ipairs(GAME) do
        local ok, f = pcall(g.get)
        if not ok or type(f) ~= "table" or type(f.SetAlpha) ~= "function" or type(f.GetAlpha) ~= "function" then
            Once(g.label .. " was not found: it stays as it is")
        else
            local okRead, alpha = pcall(f.GetAlpha, f)
            local known = okRead and PlainNumber(alpha)
            if gameAlpha[f] == nil then
                gameAlpha[f] = known and alpha or 1
                gameOrder[#gameOrder + 1] = f
            end
            if not (known and alpha == 0) then
                local okSet, err = pcall(f.SetAlpha, f, 0)
                if okSet then
                    Note(g.label .. " made invisible" .. (again and " again" or "")
                        .. " (its see-through was " .. (known and format("%.2f", alpha) or "not readable") .. ")")
                else
                    PE:LogError(KEY, "SetAlpha on " .. g.label .. " failed: " .. tostring(err))
                    Once("SetAlpha on " .. g.label .. " failed: it stays visible")
                end
            end
        end
    end
end

-- Out of a fight only: each frame's see-through as it was read.
ShowGame = function()
    for _, f in ipairs(gameOrder) do
        local alpha = gameAlpha[f]
        local ok, err = pcall(f.SetAlpha, f, alpha)
        if not ok then PE:LogError(KEY, "A unit frame of the game's could not be shown again: " .. tostring(err)) end
    end
    if #gameOrder > 0 then Note("the game's " .. #gameOrder .. " unit frames have their see-through back") end
    gameAlpha, gameOrder = {}, {}
end

-- The tap guards: each on the rectangle read from its game frame, in UIParent's units.
-- Out of a fight only (the game may hide a frame's place in a fight).
local function PlaceGuards()
    local ui = UIParent:GetEffectiveScale()
    for _, g in ipairs(GAME) do
        local guard = guards[g.key]
        local ok, f = pcall(g.get)
        local l, b, w, h, scale
        if ok and type(f) == "table" and type(f.GetLeft) == "function" and type(f.GetBottom) == "function"
            and type(f.GetWidth) == "function" and type(f.GetHeight) == "function"
            and type(f.GetEffectiveScale) == "function" then
            local o1, o2, o3, o4, o5
            o1, l = pcall(f.GetLeft, f)
            o2, b = pcall(f.GetBottom, f)
            o3, w = pcall(f.GetWidth, f)
            o4, h = pcall(f.GetHeight, f)
            o5, scale = pcall(f.GetEffectiveScale, f)
            ok = o1 and o2 and o3 and o4 and o5
        else
            ok = false
        end
        if ok and PlainNumber(l) and PlainNumber(b) and PlainNumber(w) and PlainNumber(h) and PlainNumber(scale)
            and PlainNumber(ui) and ui > 0 and w > 0 and h > 0 then
            local k = scale / ui
            guard:ClearAllPoints()
            guard:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, b * k)
            guard:SetSize(w * k, h * k)
            if not guardPlaced[g.key] then
                Note(format("tap guard over %s: BOTTOMLEFT x %.1f y %.1f, %.1f by %.1f", g.label, l * k, b * k, w * k, h * k))
            end
            guardPlaced[g.key] = true
            if bars[g.key].shown then guard:Show() else guard:Hide() end
        else
            guardPlaced[g.key] = false
            guard:Hide()
            Once("no tap guard over " .. g.label .. ": its place cannot be read")
        end
    end
end

---------------------------------------------------------------------------
-- Building (once)
---------------------------------------------------------------------------

local function Text(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local file = (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
    pcall(fs.SetFont, fs, file, size, "OUTLINE")
    fs:SetWordWrap(false)
    return fs
end

-- A flat panel: a dark see-through ground and a black line 1 unit wide around it.
local function Panel(w, h)
    local f = CreateFrame("Frame", nil, holder)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(holder:GetFrameLevel() + 2) -- above the tap guards
    f:SetSize(w, h)
    local ground = f:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(f)
    ground:SetColorTexture(0, 0, 0, GROUND_ALPHA)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", w, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", w, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, h }, { "TOPRIGHT", "BOTTOMRIGHT", 1, h } }) do
        local line = f:CreateTexture(nil, "BORDER")
        line:SetColorTexture(0, 0, 0, 1)
        line:SetPoint(edge[1], f, edge[1], 0, 0)
        line:SetPoint(edge[2], f, edge[2], 0, 0)
        if edge[3] == 1 then line:SetWidth(1) else line:SetHeight(1) end
    end
    f:Hide()
    return f
end

-- A status bar inside a panel, `up` over its bottom line, `h` tall, 1 in from each side.
local function Fill(panel, w, up, h, colour)
    local sb = CreateFrame("StatusBar", nil, panel)
    sb:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 1, up)
    sb:SetSize(w - 2, h)
    sb:SetStatusBarTexture(BAR_TEXTURE)
    sb:SetStatusBarColor(colour[1], colour[2], colour[3])
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    return sb
end

local function Build(S)
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetAllPoints(UIParent)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()
    for _, def in ipairs(BARS) do
        local w, h = def.main and S.w or S.small.w, def.main and S.h or S.small.h
        local bar = { def = def, frame = Panel(w, h), stopped = {} }
        if def.main then
            bar.power = Fill(bar.frame, w, 1, S.power, POWER.MANA)
            bar.powerColour = POWER.MANA
            bar.health = Fill(bar.frame, w, 1 + S.power + 1, S.health, COLOUR.friend)
            bar.level = Text(bar.health, 12)
            bar.level:SetPoint("LEFT", bar.health, "LEFT", 4, 0)
            bar.value = Text(bar.health, 12)
            bar.value:SetPoint("RIGHT", bar.health, "RIGHT", -4, 0)
            bar.value:SetJustifyH("RIGHT")
            bar.name = Text(bar.health, 12)
            bar.name:SetPoint("LEFT", bar.level, "RIGHT", 4, 0)
            bar.name:SetWidth(w - 110) -- room for the level before it and the number after
        else
            bar.health = Fill(bar.frame, w, 1, h - 2, COLOUR.friend)
            bar.name = Text(bar.health, 11)
            bar.name:SetPoint("LEFT", bar.health, "LEFT", 4, 0)
            bar.name:SetWidth(w - 10)
        end
        bar.name:SetJustifyH("LEFT")
        bar.colour = COLOUR.friend
        bars[def.key] = bar
    end
    local frame = Panel(S.w, S.cast.h)
    cast = { frame = frame, shown = false, since = 0 }
    cast.bar = Fill(frame, S.w, 1, S.cast.h - 2, COLOUR.cast)
    cast.text = Text(cast.bar, 10)
    cast.text:SetPoint("LEFT", cast.bar, "LEFT", 4, 0)
    cast.text:SetWidth(S.w - 10)
    cast.text:SetJustifyH("LEFT")
    Slim.view.cast = cast
    for _, g in ipairs(GAME) do
        local guard = CreateFrame("Frame", nil, holder)
        guard:SetFrameStrata("MEDIUM")
        guard:SetFrameLevel(holder:GetFrameLevel() + 1)
        guard:EnableMouse(true) -- takes a tap and does nothing with it
        guard:Hide()
        guards[g.key] = guard
    end
    plainFrame, ownFrame, targetFrame = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
end

-- Each bar to its rectangle of the plan; one line per bar in the debug log.
local function Place(rects)
    local function put(frame, name)
        local r = rects[name]
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", r[1], r[2])
        Note(format("placed the %s: BOTTOMLEFT on the screen's bottom middle, x %.1f y %.1f, %.1f by %.1f, scale 1",
            name, r[1], r[2], r[3] - r[1], r[4] - r[2]))
    end
    for _, def in ipairs(BARS) do put(bars[def.key].frame, def.rect) end
    put(cast.frame, "cast bar")
end

-- The pieces for "Save a snapshot" (ControllerLayout.lua, mod:AddSnapshotSource). The tap
-- guards lie over the game's invisible frames by design and are listed, not checked.
local function SnapshotSource(add)
    for _, def in ipairs(BARS) do add(def.label, bars[def.key] and bars[def.key].frame) end
    add("cast bar", cast and cast.frame)
    for _, g in ipairs(GAME) do add("tap guard, " .. g.key .. " frame", guards[g.key], { skip = true }) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function OnUnitEvent(event, unit, ...)
    if not running then return end
    if IsSecret(unit) or type(unit) ~= "string" then return end
    local ends = CAST_ENDS[event]
    if ends then
        if unit == "target" then RefreshCast(ends) end
        return
    end
    if event == "UNIT_PET" then
        if unit == "player" then RefreshPet() end
        return
    end
    if event == "UNIT_TARGET" then
        if unit == "target" then RefreshTot() end
        return
    end
    local bar = bars[unit]
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if bar and bar.shown then UpdateHealth(bar) end
        -- The game sends no health event for the target's target: read it along.
        if bars.tot.shown then UpdateHealth(bars.tot) end
        return
    end
    if not (bar and bar.shown) then return end
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        UpdatePower(bar, false)
    elseif event == "UNIT_DISPLAYPOWER" then
        UpdatePower(bar, true)
    elseif event == "UNIT_NAME_UPDATE" then
        UpdateName(bar)
    elseif event == "UNIT_LEVEL" then
        UpdateLevel(bar)
    elseif event == "UNIT_FACTION" then
        UpdateColour(bar)
        if bars.tot.shown then UpdateColour(bars.tot) end
    end
end

local function OnPlainEvent(event, a1)
    if not running then return end
    if event == "PLAYER_TARGET_CHANGED" then
        RefreshTarget()
    elseif event == "PLAYER_LEVEL_UP" then
        UpdateLevel(bars.player, a1)
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshAll()
        -- The world loaded again: the game's frames are checked, out of a fight.
        PE:RunOutOfCombat("ctrlLayout:slimCheck", function()
            if running and not stopping then
                HideGame(true)
                PlaceGuards()
            end
        end)
    end
end

local function Register()
    local function each(frame, events, ...)
        for _, event in ipairs(events) do
            local ok, err
            if select("#", ...) > 0 and type(frame.RegisterUnitEvent) == "function" then
                ok, err = pcall(frame.RegisterUnitEvent, frame, event, ...)
            else
                ok, err = pcall(frame.RegisterEvent, frame, event)
            end
            if not ok then Once("the event " .. event .. " could not be registered: " .. tostring(err)) end
        end
    end
    each(plainFrame, PLAIN_EVENTS)
    each(ownFrame, OWN_EVENTS, "player", "pet")
    each(targetFrame, TARGET_EVENTS, "target")
end

local function Unregister()
    for _, frame in ipairs({ plainFrame, ownFrame, targetFrame }) do
        if frame then frame:UnregisterAllEvents() end
    end
end

---------------------------------------------------------------------------
-- Start, Stop, Status
---------------------------------------------------------------------------

-- why: for the debug log. keepGame: leave the game's frames invisible for now (the safety
-- net in a fight; they are shown when the fight ends).
StopNow = function(why, keepGame)
    stopping = false
    if not keepGame then
        ShowGame() -- the game's frames back before ours go
        for _, guard in pairs(guards) do guard:Hide() end
    end
    if running then
        running = false
        Unregister()
        if cast then
            cast.shown = false
            cast.bar:SetScript("OnUpdate", nil)
            cast.frame:Hide()
        end
        for _, bar in pairs(bars) do
            bar.shown = nil
            bar.frame:Hide()
            Mark(bar, "health", true)
            if bar.power then Mark(bar, "power", true) end
        end
        Note("off: " .. tostring(why))
    end
    if keepGame then
        -- The game's four frames are still invisible: every guard that has a place shows
        -- (whatever its bar did), in the holder, which stays up for them.
        for key, guard in pairs(guards) do
            if guardPlaced[key] then guard:Show() end
        end
    elseif holder then
        holder:Hide()
    end
end

local function StartNow(plan)
    if not built then
        if buildFailed then return false, buildFailed end
        ReadApi()
        local ok, err = pcall(Build, plan.SLIM)
        if not ok then
            buildFailed = TEXT_BUILD
            PE:LogError(KEY, "The slim bars could not be made: " .. tostring(err))
            if holder then pcall(holder.Hide, holder) end
            return false, buildFailed
        end
        built = true
        local layout = PE.ControllerLayout
        if type(layout) == "table" and type(layout.AddSnapshotSource) == "function" then
            pcall(layout.AddSnapshotSource, layout, SnapshotSource)
        end
        plainFrame:SetScript("OnEvent", Guard(function(_, event, a1) OnPlainEvent(event, a1) end))
        local onUnit = Guard(function(_, event, unit, ...) OnUnitEvent(event, unit, ...) end)
        ownFrame:SetScript("OnEvent", onUnit)
        targetFrame:SetScript("OnEvent", onUnit)
        cast.onUpdate = Guard(function(_, elapsed)
            CastTick()
            cast.since = cast.since + ((type(elapsed) == "number") and elapsed or 0)
            if cast.since >= CHECK_EVERY then
                cast.since = 0
                RefreshCast("the cast ended (no stop event came)")
            end
        end)
    end
    local layout = PE.ControllerLayout
    local opts = type(layout) == "table" and layout.opts or nil
    Note("on (slim=" .. PE.Plain(type(opts) == "table" and opts.slim or nil) .. ", Spell panel size "
        .. PE.Plain(type(opts) == "table" and opts.panelSize or nil) .. "%)")
    Place(plan.SlimRects())
    Register()
    running = true
    holder:Show()
    RefreshAll()
    -- Only now, with our bars showing, do the game's frames go.
    HideGame(false)
    PlaceGuards()
    return true
end

-- The three public functions are set by string key (as in FaceBars.lua): the API check
-- lists widget methods by name, and "Stop" is also an animation's method the addon calls.
Slim["Start"] = function()
    if broken then return false, status end
    if PE:InCombat() then
        if not running then status = TEXT_FIGHT end
        return false, TEXT_FIGHT
    end
    stopping = false
    if running then
        -- Placed again by the layout: only the game's frames and the guards are checked.
        HideGame(true)
        PlaceGuards()
        return true
    end
    local plan = PE.LayoutPlan
    if type(plan) ~= "table" or type(plan.SLIM) ~= "table" or type(plan.SlimRects) ~= "function" then
        status = TEXT_NO_PLAN
        return false, status
    end
    local ok, started, why = PE:Safe(KEY, StartNow, plan)
    if not ok then
        -- Raised part-way: everything of ours off again, the game's frames as they were.
        pcall(StopNow, "the start failed")
        running = false
        Unregister()
        if holder then pcall(holder.Hide, holder) end
        -- A start that raises counts like any other error: after the third it is not tried
        -- again this session (the layout asks at every placement).
        Failed()
        status = TEXT_ERROR
        return false, status
    end
    if not started then
        status = why
        return false, why
    end
    status = nil
    return true
end

Slim["Stop"] = function()
    if not running and #gameOrder == 0 then
        if status == TEXT_FIGHT then status = nil end
        return
    end
    if PE:InCombat() then
        if not stopping then
            stopping = true
            Note("asked to stop in a fight: the bars stay until it ends")
            PE:RunOutOfCombat("ctrlLayout:slimStop", function()
                if stopping then StopNow("stopped (asked in a fight)") end
            end)
        end
        return
    end
    StopNow("stopped")
    if not broken then status = nil end
end

Slim["Status"] = function()
    return status
end
