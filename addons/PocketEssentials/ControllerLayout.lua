local ADDON_NAME, PE = ...

-- Controller layout: a ready-made screen arrangement for playing with a
-- controller (spec 2026-11-21-controller-layout.md; the sizes are from
-- 2026-11-22-controller-layout-measured-sizes.md).
--
-- This file has two halves.
--
--   * PE.LayoutPlan: plain functions that work out the numbers (sizes, bar
--     spots, the list of pieces to place) and write them into an Edit Mode
--     layout table. They make no game calls and read no frame; system and
--     setting names are plain strings, and the caller passes an `enums` table
--     it filled from the game's Enum:
--       enums.system[name]                 -> number
--       enums.setting[system][setting]     -> number
--       enums.index[system][indexName]     -> number
--       enums.layoutType.Account, enums.style.Gamepad
--   * The module: the switch, and the bars. Nothing runs while it is off: its
--     two events are registered only while it is on, it has no timers, and
--     its one hook (installed the first time it is switched on) does nothing
--     while it is off. The one exception is a check at login when a layout to
--     go back to is remembered for this character (see Settle); it listens
--     for two events until that check has run, then for nothing.
--
-- The map's size at 100% was measured on a device and the bar's size is
-- Blizzard's own (see SIZE). Still first guesses: the map's size below 100%
-- (taken as the measured size times the percentage), the swing timer's size,
-- and every spot and gap.
--
-- 0.11.1 (spec 2026-11-23-controller-layout-0.11.1.md): the XP bars top middle,
-- the map's title strip under the map, the buffs clear of the chat, and each
-- character's own layout to go back to.
--
-- The map's title strip under the map: Enum.EditModeMinimapSetting.HeaderUnderneath
-- (Blizzard_APIDocumentationGenerated/EditModeManagerConstantsDocumentation.lua:580; the
-- Minimap system's setting in Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua:131,
-- applied by EditModeSystemTemplates.lua:1794-1795). The Forever client's own map code
-- (Blizzard_Minimap/Camelot/Minimap.lua:68-84) then puts the title strip at the map frame's
-- bottom (8 up) and the map itself 30 up from that bottom, the mirror of the title on top
-- (the title at the top edge, the map 30 down: Mainline/Minimap.xml:50 and
-- Camelot/MinimapZoneTextButton.xml:11). The strip stays inside the map frame, whose bottom
-- edge is the spot written here, so nothing under the map moves and MapY is not raised.

local type, pairs, ipairs = type, pairs, ipairs
local min = math.min
local sort = table.sort

local Plan = {}
PE.LayoutPlan = Plan

Plan.NAME = "Pocket Essentials"

Plan.DEFAULTS = {
    main = "above",     -- the main bar: "above" or "under" the map
    map = 80,           -- the map's size in percent: 60, 70 or 80
    frames = "corner",  -- player, pet and target frames: "corner", "stacked" or "flat"
    size = 100,         -- spell button size in percent, 70 to 100 (below 100 a spell's own wheel may open beside its button)
    fineMain = 1,       -- main bar size: 0.85, 1 or 1.15
    fineSide = 1,       -- LT and RT bars
    fineBoth = 1,       -- both-triggers bar
    timers = "under",   -- swing timers: "under" the map, "above" the bars, or under the LT and RT bars ("bars")
    ranged = 1,         -- timer visibility: 0 Always, 1 In combat, 2 Hidden
    mainHand = 1,
    offHand = 2,
}

-- The map at 100%: measured by the probe (273 by 283 at UI scale 1); the
-- Gamepad preset's map size is 100%
-- (Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:397). At another
-- size it is taken as this times the percentage; the real map may be a few
-- units larger, because only a part inside it is scaled
-- (Blizzard_Minimap/Mainline/Minimap.lua:418-419).
-- A bar: Blizzard's size for a bar that does not grow
-- (Blizzard_GamepadActionBars/ActionBarStyles.lua:172); the template switches
-- growing off (ShouldExpand 0).
-- An XP bar: 17 high (STATUS_BAR_CONTAINER_HEIGHT,
-- Blizzard_StatusTrackingBar/Camelot/StatusTrackingBarConstants.lua:2), 596 wide at 100%
-- with the Gamepad UI (STATUS_BAR_CONTAINER_WIDTH_GAMEPAD, same file, line 12, and
-- StatusTrackingManagerOverrides.lua:80-81). The game's Gamepad preset stacks bar 2 one bar
-- height above bar 1 (Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:1441-1461, offsetY 0
-- and 17 on StatusTrackingBarManager's bottom); with a Gamepad layout the game places both
-- by their saved spot (Blizzard_EditMode/Camelot/EditModeUtil.lua:5-9). At the screen's top
-- edge there is no room above, so here bar 2 sits one bar height under bar 1.
local SIZE = { MAP_W = 273, MAP_H = 283, BAR_W = 208, BAR_H = 68, XP_H = 17 }
local XP_TOP_Y = -2 -- the first XP bar's top edge, from the screen's top

-- The map sizes offered. 100% is left out: the two sub-menu buttons sit a
-- fixed 138 either side of the map's centre and a map that wide would cover
-- them.
local MAP_SIZES = { [60] = true, [70] = true, [80] = true }

local MAIN_UNDER_MAP_Y = 8 + SIZE.BAR_H + 14 -- the map's height with the main bar under it, written for size 100%
local TIMERS_UNDER_LIFT = 36         -- what the swing timers under the map add to that
local OFF_HAND_LIFT = 16             -- one more timer row under the map

local UI = "UIParent"

-- The options with every missing or unusable value replaced by its default.
local function Fill(opts)
    local out = {}
    opts = type(opts) == "table" and opts or {}
    for k, default in pairs(Plan.DEFAULTS) do
        local v = opts[k]
        if type(v) == type(default) then out[k] = v else out[k] = default end
    end
    if not MAP_SIZES[out.map] then out.map = Plan.DEFAULTS.map end
    return out
end

-- The map's width and height at the chosen size. `o` is already filled.
local function MapSize(o)
    return SIZE.MAP_W * o.map / 100, SIZE.MAP_H * o.map / 100
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end

-- The three group sizes: main, side and both-triggers bars.
function Plan.Scales(opts)
    local o = Fill(opts)
    local base = o.size / 100
    local kM = min(1, base * o.fineMain)
    local kS = min(1, base * o.fineSide)
    local kB = min(1, base * o.fineBoth) * 0.7
    return kM, kS, kB
end

-- The map's bottom edge, in UI units from the screen's bottom.
function Plan.MapY(opts)
    local o = Fill(opts)
    local offHandShown = o.offHand ~= 2
    if o.main == "under" then
        local y = MAIN_UNDER_MAP_Y
        if o.timers == "under" then
            y = y + TIMERS_UNDER_LIFT
            if offHandShown then y = y + OFF_HAND_LIFT end
        end
        return y
    end
    if o.timers == "under" then
        return 44 + (offHandShown and OFF_HAND_LIFT or 0)
    end
    return 6
end

-- Where each bar group's centre goes, and its scale. x and y are UI units from
-- the screen's bottom centre, before dividing by the scale.
function Plan.BarSpots(opts)
    local o = Fill(opts)
    local kM, kS, kB = Plan.Scales(o)
    local W, H = SIZE.BAR_W, SIZE.BAR_H
    local mapW, mapH = MapSize(o)
    local mapY = Plan.MapY(o)
    local lift = o.timers == "bars" and 22 or 0
    local left, top, both, bottom
    if o.main == "under" then
        left = { x = -(W * kM / 2 + 12 + W * kS / 2), y = 8 + lift + H * kS / 2, s = kS }
        top = { x = 0, y = 8 + lift + H * kM / 2, s = kM }
        both = { x = 0, y = mapY + mapH + 14 + H * kB / 2, s = kB }
        bottom = { x = 0, y = mapY + mapH * 0.5 + 50, s = 1 }
    else
        left = { x = -(mapW / 2 + 14 + W * kS / 2), y = 8 + lift + H * kS / 2, s = kS }
        top = { x = 0, y = mapY + mapH + 12 + H * kM / 2, s = kM }
        both = { x = 0, y = top.y + H * kM / 2 + 22 + H * kB / 2, s = kB }
        bottom = { x = 0, y = mapY + mapH * 0.62 + 50, s = 1 }
    end
    local right = { x = -left.x, y = left.y, s = left.s }
    return { top = top, left = left, right = right, bottom = bottom, both = both }
end

-- The numbers the timers "above" and "bars" placements hang on: the top of the
-- highest bar above the map, and the LT bar's centre, both at size 100% and
-- fine-tunes of 1, for the current main bar choice and map size.
local function TimerAnchors(o)
    local at100 = Fill(o)
    at100.size, at100.fineMain, at100.fineSide, at100.fineBoth = 100, 1, 1, 1
    local spots = Plan.BarSpots(at100)
    local _, _, kB = Plan.Scales(at100)
    return spots.both.y + SIZE.BAR_H * kB / 2, -spots.left.x
end

local FRAME_SPOTS = {
    corner = {
        Player = { "BOTTOMLEFT", UI, "BOTTOMLEFT", 20, 20 },
        Pet = { "BOTTOMLEFT", UI, "BOTTOMLEFT", 40, 124 },
        Target = { "BOTTOMRIGHT", UI, "BOTTOMRIGHT", -20, 20 },
    },
    stacked = {
        Player = { "BOTTOMRIGHT", UI, "BOTTOM", -165, 112 },
        Pet = { "BOTTOMRIGHT", UI, "BOTTOM", -185, 216 },
        Target = { "BOTTOMLEFT", UI, "BOTTOM", 165, 112 },
    },
    flat = {
        Player = { "BOTTOMRIGHT", UI, "BOTTOM", -165, 112 },
        Pet = { "BOTTOMRIGHT", UI, "BOTTOM", -401, 130 },
        Target = { "BOTTOMLEFT", UI, "BOTTOM", 165, 112 },
    },
}

local function Anchor(spot)
    return { point = spot[1], relativeTo = spot[2], relativePoint = spot[3], x = spot[4], y = spot[5] }
end

local function Spot(point, relativePoint, x, y)
    return { point = point, relativeTo = UI, relativePoint = relativePoint, x = x, y = y }
end

-- The swing timers' spots: { Ranged, MainHand, OffHand } as { x, y }.
local function TimerSpots(o)
    if o.timers == "above" then
        local topY = TimerAnchors(o)
        return { { 0, topY + 40 }, { 0, topY + 24 }, { 0, topY + 8 } }
    elseif o.timers == "bars" then
        local _, sideX = TimerAnchors(o)
        return { { -sideX, 6 }, { sideX, 6 }, { sideX, 22 } }
    end
    -- With the main bar under the map, the stack sits between that bar and the map.
    local lift = o.main == "under" and 78 or 0
    if o.offHand ~= 2 then
        return { { 0, 40 + lift }, { 0, 24 + lift }, { 0, 8 + lift } }
    end
    return { { 0, 24 + lift }, { 0, 8 + lift }, { 0, -8 + lift } }
end

-- Every piece of the template that the options decide, in the order of the
-- spec's tables. A piece with no `anchor` keeps its place and only gets
-- settings. `moved` is true where the game must be told the piece is no longer
-- in its default position.
function Plan.Pieces(opts)
    local o = Fill(opts)
    local list = {}
    local function add(system, index, anchor, settings)
        list[#list + 1] = { system = system, index = index, anchor = anchor, settings = settings, moved = anchor and true or nil }
    end
    -- The stored Size counts in steps of 10% from 50%: 80% is 3. HeaderUnderneath 1 puts
    -- the map's title strip (zone name, clock, mail) under the map (0.11.1 spec, 3); left out
    -- by Plan.Apply when the game has no such setting.
    add("Minimap", nil, Spot("BOTTOM", "BOTTOM", 0, Plan.MapY(o)), { Size = (o.map - 50) / 10, HeaderUnderneath = 1 })
    add("ChatFrame", nil, Spot("TOPRIGHT", "TOPRIGHT", -30, -40),
        { WidthHundreds = 4, WidthTensAndOnes = 30, HeightHundreds = 2, HeightTensAndOnes = 10 })
    -- Buffs, debuffs and the quest tracker start under the chat's last lines (0.11.1 spec, 4).
    add("AuraFrame", "BuffFrame", Spot("TOPRIGHT", "TOPRIGHT", -30, -292), nil)
    add("AuraFrame", "DebuffFrame", Spot("TOPRIGHT", "TOPRIGHT", -30, -330), nil)
    add("ObjectiveTracker", nil, Spot("TOPRIGHT", "TOPRIGHT", -30, -375), { Height = 0 })
    -- The XP bars along the top edge, centred, at 100% (0.11.1 spec, 1), the second right
    -- under the first.
    add("StatusTrackingBar", "StatusTrackingBar1", Spot("TOP", "TOP", 0, XP_TOP_Y), { Size = 10 })
    add("StatusTrackingBar", "StatusTrackingBar2", Spot("TOP", "TOP", 0, XP_TOP_Y - SIZE.XP_H), { Size = 10 })
    add("GamepadMainActionBar", nil, nil, { Compact = 0, ShowEmptyBars = 0, ShouldExpand = 0 })
    local frames = FRAME_SPOTS[o.frames] or FRAME_SPOTS.corner
    add("UnitFrame", "Player", Anchor(frames.Player), nil)
    add("UnitFrame", "Pet", Anchor(frames.Pet), nil)
    add("UnitFrame", "Target", Anchor(frames.Target), nil)
    local t = TimerSpots(o)
    local names = { "Ranged", "MainHand", "OffHand" }
    local visibility = { o.ranged, o.mainHand, o.offHand }
    for i, name in ipairs(names) do
        add("SwingTimer", name, Spot("BOTTOM", "BOTTOM", t[i][1], t[i][2]),
            { Scale = 3, Width = 0, Height = 0, Visibility = visibility[i] })
    end
    return list
end

-- The entry of a layout for a system (and index name), or nil.
local function FindEntry(layout, systemNumber, indexNumber)
    for _, entry in ipairs(layout.systems or {}) do
        if entry.system == systemNumber and (indexNumber == nil or entry.systemIndex == indexNumber) then
            return entry
        end
    end
    return nil
end

local function SetSetting(entry, settingNumber, value)
    entry.settings = entry.settings or {}
    for _, s in ipairs(entry.settings) do
        if s.setting == settingNumber then
            s.value = value
            return
        end
    end
    entry.settings[#entry.settings + 1] = { setting = settingNumber, value = value }
end

-- Writes the pieces into a layout, in place. A piece whose system or index is
-- missing from the layout, or from enums, is skipped. Returns how many pieces
-- changed an entry.
function Plan.Apply(layout, pieces, enums)
    if type(layout) ~= "table" or type(pieces) ~= "table" or type(enums) ~= "table" then return 0 end
    local changed = 0
    for _, p in ipairs(pieces) do
        local systemNumber = enums.system and enums.system[p.system]
        local indexNumber
        local known = systemNumber ~= nil
        if known and p.index ~= nil then
            indexNumber = enums.index and enums.index[p.system] and enums.index[p.system][p.index]
            known = indexNumber ~= nil
        end
        local entry = known and FindEntry(layout, systemNumber, indexNumber) or nil
        if entry then
            if p.anchor then
                entry.anchorInfo = {
                    point = p.anchor.point, relativeTo = p.anchor.relativeTo, relativePoint = p.anchor.relativePoint,
                    offsetX = p.anchor.x, offsetY = p.anchor.y,
                }
                entry.anchorInfo2 = nil -- a second anchor would keep the old spot
            end
            if p.moved then entry.isInDefaultPosition = false end
            if p.settings then
                local names = {}
                for name in pairs(p.settings) do names[#names + 1] = name end
                sort(names)
                local numbers = enums.setting and enums.setting[p.system] or {}
                for _, name in ipairs(names) do
                    if numbers[name] ~= nil then SetSetting(entry, numbers[name], p.settings[name]) end
                end
            end
            changed = changed + 1
        end
    end
    return changed
end

-- A new layout: a copy of `base` with our name, the account-wide type and the
-- Gamepad style, and every piece applied.
function Plan.Build(base, opts, enums)
    local layout = DeepCopy(base)
    layout.layoutName = Plan.NAME
    layout.layoutType = enums and enums.layoutType and enums.layoutType.Account
    layout.interfaceStyle = enums and enums.style and enums.style.Gamepad
    Plan.Apply(layout, Plan.Pieces(opts), enums)
    return layout
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

-- How the game's layouts are changed: data only, the way Blizzard's own
-- "new layout" does it (EditModeManagerFrameMixin:MakeNewLayout,
-- Blizzard_EditMode/Shared/EditModeManager.lua:1567-1589), without touching
-- the manager: C_EditMode.SaveLayouts with the whole list (presets first,
-- then the saved layouts), then C_EditMode.OnLayoutAdded, or
-- C_EditMode.SetActiveLayout for a layout that is already saved. The game
-- then places its own frames. Every change ends with a reload request, so the
-- layout is applied once more by Blizzard code alone.
--
-- Index arithmetic: C_EditMode.GetLayouts() returns only the saved layouts,
-- but its activeLayout counts the presets first (Modern 1, Classic 2,
-- Gamepad 3; a preset's index is its Enum.EditModePresetLayouts value + 1).
--
-- The game remembers the active layout per character, so the layout to go back
-- to is kept per character (0.11.1 spec, 2): opts.prevs[<name>-<realm>] =
-- { name, layoutType, preset }, written when a switch-on has really happened
-- on that character. opts.prev is the 0.11.0 file's single entry for the whole
-- account, read once (Migrate) and then false.
--
-- The character's name and realm: UnitName("player")
-- (Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:2489-2503) and
-- GetRealmName() (ConnectionDocumentation.lua:69-75). UnitName may answer
-- UNKNOWNOBJECT ("Unknown", compared the same way in
-- Blizzard_RaidUI/Mainline/Blizzard_RaidUI.lua:706) before the character is
-- loaded; the key is then unknown and the check waits.
--
-- At each login, and at each switch-on, Settle runs once this character's key
-- can be read and the game has handed Edit Mode its layouts
-- (EditModeManagerFrameMixin:IsInitialized,
-- Blizzard_EditMode/Shared/EditModeManager.lua:216-218, true once
-- UpdateLayoutInfo, line 1012, ran on EDIT_MODE_LAYOUTS_UPDATED, line 193): a
-- layout list read before that may be incomplete, and saving it could lose the
-- player's own layouts. Until then it listens for the next
-- PLAYER_ENTERING_WORLD and EDIT_MODE_LAYOUTS_UPDATED through the core's own
-- event list (PE:RegisterCoreEvent), because a module that is off hears none
-- of its own events; both are dropped as soon as Settle has run. While off,
-- this happens only when a layout is remembered for this character (or the old
-- single entry is still there), so a player who never used the feature has
-- nothing registered at all.
--
-- Settle, with the feature on: an entry for this character means it was
-- switched on here before: nothing changes, the bars are placed (or left, with
-- the "another layout" status line, when another layout is active). No entry:
-- the switch-on steps (remember this character's current layout, make ours
-- active, ask for the reload). With the feature off: an entry while ours is
-- active means it was switched off on another character: this character's own
-- layout comes back and the reload is asked for; an entry while another layout
-- is active is only forgotten.

local tostring, pcall = tostring, pcall
local tinsert = table.insert

local TEXT_OFF = "Switching on or off reloads. Your old layout comes back when off."
local TEXT_USING = "Using the Pocket Essentials layout. Move the map, chat or frames in Edit Mode; it is kept."
local TEXT_ANOTHER = "Another Edit Mode layout is active. Pick Pocket Essentials in Edit Mode, or switch this off and on."
local TEXT_NEEDS_GAMEPAD = "Needs the game's Gamepad UI (Options, Controller, Enable Gamepad UI)."
local TEXT_NO_LAYOUTS = "This game version has no layouts an addon can change."
local TEXT_EDIT_MODE = "Close Edit Mode first."
local TEXT_NAME_REFUSED = "The game refused the layout name."
local RELOAD_REASON = "Reload to finish changing the screen layout."
local MAX_LAYOUTS = 5 -- per type (EditModeManagerConstantsDocumentation.lua, EditModeMaxLayoutsPerType)

local mod
local note             -- a refusal, shown in the status line until the next switch-on
local wanted = false   -- the switch is on (the queued work checks it when it runs)
local enumCache, presetCache

local function Say(text)
    note = text
    if PE.debugOn then PE:Debug("ctrlLayout", "answer: " .. tostring(text)) end
    if mod then
        mod:Print(text)
        mod:RefreshPanel()
    end
end

local function Api()
    local api = C_EditMode
    if type(api) == "table" and type(api.GetLayouts) == "function" and type(api.SetActiveLayout) == "function"
        and type(api.SaveLayouts) == "function" and type(api.OnLayoutAdded) == "function" then
        return api
    end
    return nil
end

-- Raises if any table is missing; called through pcall only.
local function ReadEnums()
    local e = {
        system = {
            Minimap = Enum.EditModeSystem.Minimap,
            ChatFrame = Enum.EditModeSystem.ChatFrame,
            AuraFrame = Enum.EditModeSystem.AuraFrame,
            ObjectiveTracker = Enum.EditModeSystem.ObjectiveTracker,
            StatusTrackingBar = Enum.EditModeSystem.StatusTrackingBar,
            GamepadMainActionBar = Enum.EditModeSystem.GamepadMainActionBar,
            UnitFrame = Enum.EditModeSystem.UnitFrame,
            SwingTimer = Enum.EditModeSystem.SwingTimer,
        },
        setting = {
            -- HeaderUnderneath may be nil (an older client): Plan.Apply then leaves it out.
            Minimap = { Size = Enum.EditModeMinimapSetting.Size, HeaderUnderneath = Enum.EditModeMinimapSetting.HeaderUnderneath },
            ChatFrame = {
                WidthHundreds = Enum.EditModeChatFrameSetting.WidthHundreds,
                WidthTensAndOnes = Enum.EditModeChatFrameSetting.WidthTensAndOnes,
                HeightHundreds = Enum.EditModeChatFrameSetting.HeightHundreds,
                HeightTensAndOnes = Enum.EditModeChatFrameSetting.HeightTensAndOnes,
            },
            ObjectiveTracker = { Height = Enum.EditModeObjectiveTrackerSetting.Height },
            StatusTrackingBar = { Size = Enum.EditModeStatusTrackingBarSetting.Size },
            GamepadMainActionBar = {
                Compact = Enum.EditModeGamepadMainActionBarSetting.Compact,
                ShowEmptyBars = Enum.EditModeGamepadMainActionBarSetting.ShowEmptyBars,
                ShouldExpand = Enum.EditModeGamepadMainActionBarSetting.ShouldExpand,
            },
            SwingTimer = {
                Scale = Enum.EditModeSwingTimerSetting.Scale,
                Width = Enum.EditModeSwingTimerSetting.Width,
                Height = Enum.EditModeSwingTimerSetting.Height,
                Visibility = Enum.EditModeSwingTimerSetting.Visibility,
            },
        },
        index = {
            AuraFrame = {
                BuffFrame = Enum.EditModeAuraFrameSystemIndices.BuffFrame,
                DebuffFrame = Enum.EditModeAuraFrameSystemIndices.DebuffFrame,
            },
            UnitFrame = {
                Player = Enum.EditModeUnitFrameSystemIndices.Player,
                Target = Enum.EditModeUnitFrameSystemIndices.Target,
                Pet = Enum.EditModeUnitFrameSystemIndices.Pet,
            },
            SwingTimer = {
                MainHand = Enum.EditModeSwingTimerSystemIndices.MainHand,
                OffHand = Enum.EditModeSwingTimerSystemIndices.OffHand,
                Ranged = Enum.EditModeSwingTimerSystemIndices.Ranged,
            },
            StatusTrackingBar = {
                StatusTrackingBar1 = Enum.EditModeStatusTrackingBarSystemIndices.StatusTrackingBar1,
                StatusTrackingBar2 = Enum.EditModeStatusTrackingBarSystemIndices.StatusTrackingBar2,
            },
        },
        layoutType = {
            Preset = Enum.EditModeLayoutType.Preset,
            Account = Enum.EditModeLayoutType.Account,
        },
        style = { Gamepad = Enum.InputDeviceInterfaceType.Gamepad },
        preset = { Gamepad = Enum.EditModePresetLayouts.Gamepad },
        numPresets = Enum.EditModePresetLayoutsMeta.NumValues,
    }
    return e
end

-- Every value must be a number; one missing means this game version is not
-- the one this file was written for.
local function AllNumbers(t)
    for _, v in pairs(t) do
        if type(v) == "table" then
            if not AllNumbers(v) then return false end
        elseif type(v) ~= "number" then
            return false
        end
    end
    return true
end

-- The enums table PE.LayoutPlan wants (plus layoutType.Preset, preset.Gamepad
-- and numPresets), or nil.
local function Enums()
    if enumCache then return enumCache end
    local ok, e = pcall(ReadEnums)
    if not ok or type(e) ~= "table" or not AllNumbers(e) then return nil end
    enumCache = e
    return e
end

local function GamepadBar()
    local bar = GamepadMainActionBarFrame
    return type(bar) == "table" and bar or nil
end

local function EditModeOpen()
    local manager = EditModeManagerFrame
    if type(manager) ~= "table" then return false end
    if type(manager.IsShown) == "function" then
        local ok, shown = pcall(manager.IsShown, manager)
        if ok and shown then return true end
    end
    if type(manager.IsEditModeActive) == "function" then
        local ok, active = pcall(manager.IsEditModeActive, manager)
        if ok and active then return true end
    end
    return false
end

-- A fresh copy of the game's presets (a copy: it may be changed), or nil.
local function CopyOfPresets()
    local manager = EditModePresetLayoutManager
    if type(manager) ~= "table" or type(manager.GetCopyOfPresetLayouts) ~= "function" then return nil end
    local ok, list = pcall(manager.GetCopyOfPresetLayouts, manager)
    if ok and type(list) == "table" then return list end
    return nil
end

-- A short description of each preset, in the game's order, or nil if the
-- list cannot be trusted.
local function Presets()
    if presetCache then return presetCache end
    local e = Enums()
    local list = e and CopyOfPresets()
    if not list or #list ~= e.numPresets then return nil end
    local out = {}
    for i = 1, #list do
        local preset = list[i]
        if type(preset) ~= "table" or preset.layoutType ~= e.layoutType.Preset or preset.layoutIndex ~= i - 1 then
            return nil
        end
        out[i] = { name = preset.layoutName, id = preset.layoutIndex, style = preset.interfaceStyle }
    end
    presetCache = out
    return out
end

-- state = { api, info (the game's answer, a copy), presets, saved, numPresets,
--           active (index counting the presets), current (summary or nil) }
-- or nil and the reason.
local function ReadState()
    local api = Api()
    if not api then return nil, "C_EditMode is missing a function" end
    local presets = Presets()
    if not presets then return nil, "the game's preset layouts could not be read" end
    local ok, info = pcall(api.GetLayouts)
    if not ok then return nil, "C_EditMode.GetLayouts failed: " .. tostring(info) end
    if type(info) ~= "table" or type(info.layouts) ~= "table" or type(info.activeLayout) ~= "number" then
        return nil, "C_EditMode.GetLayouts gave no layout list"
    end
    local state = {
        api = api, info = info, presets = presets, saved = info.layouts,
        numPresets = #presets, active = info.activeLayout,
    }
    local active = state.active
    if active >= 1 and active <= #presets then
        local preset = presets[active]
        state.current = { name = preset.name, preset = preset.id, style = preset.style, isPreset = true }
    else
        local layout = info.layouts[active - #presets]
        if type(layout) == "table" then
            state.current = { name = layout.layoutName, layoutType = layout.layoutType, style = layout.interfaceStyle }
        end
    end
    return state
end

-- A saved layout by name (and type). Returns its index counting the presets,
-- and the layout.
local function FindSaved(state, name, layoutType)
    if type(name) ~= "string" then return nil end
    for i, layout in ipairs(state.saved) do
        if type(layout) == "table" and layout.layoutName == name
            and (layoutType == nil or layout.layoutType == layoutType) then
            return state.numPresets + i, layout
        end
    end
    return nil
end

local function FindPreset(state, id)
    if type(id) ~= "number" then return nil end
    local preset = state.presets[id + 1]
    if preset and preset.id == id then return id + 1, preset end
    return nil
end

-- The index of our saved layout, or nil.
local function OursIndex(state)
    local e = Enums()
    if not state or not e then return nil end
    return (FindSaved(state, Plan.NAME, e.layoutType.Account))
end

local function IsOursActive()
    local state = ReadState()
    local index = state and OursIndex(state)
    return index ~= nil and state.active == index
end

local function GamepadPresetIndex(state)
    local e = Enums()
    return e and (FindPreset(state, e.preset.Gamepad)) or nil
end

---------------------------------------------------------------------------
-- Each character's own layout to go back to (see the notes above Say)
---------------------------------------------------------------------------

-- "<name>-<realm>" of the character playing, or nil while it cannot be read.
local function CharKey()
    if type(UnitName) ~= "function" or type(GetRealmName) ~= "function" then return nil end
    local okName, name = pcall(UnitName, "player")
    local okRealm, realm = pcall(GetRealmName)
    if not okName or not okRealm then return nil end
    if issecretvalue and (issecretvalue(name) or issecretvalue(realm)) then return nil end
    if type(name) ~= "string" or type(realm) ~= "string" or name == "" or realm == "" then return nil end
    if name == UNKNOWNOBJECT then return nil end
    return name .. "-" .. realm
end

local function Prevs()
    local opts = mod.opts
    if type(opts.prevs) ~= "table" then opts.prevs = {} end
    return opts.prevs
end

-- The entry of a character, or nil.
local function PrevOf(key)
    if not key then return nil end
    local entry = Prevs()[key]
    return type(entry) == "table" and entry or nil
end

local function ThisPrev()
    return PrevOf(CharKey())
end

-- Writes (or, with nil, removes) a character's entry.
local function SetPrev(key, entry)
    Prevs()[key] = entry
end

local function HasLegacy()
    return type(mod.opts) == "table" and type(mod.opts.prev) == "table"
end

-- The 0.11.0 file's single entry, read once: it becomes this character's entry
-- if ours is active here, otherwise it is dropped.
local function Migrate(key)
    if not HasLegacy() then return end
    local legacy = mod.opts.prev
    mod.opts.prev = false
    if PrevOf(key) then return end
    local state = ReadState()
    local index = state and OursIndex(state)
    local kept = index ~= nil and state.active == index
    if kept then SetPrev(key, legacy) end
    if PE.debugOn then PE:Debug("ctrlLayout", "the 0.11.0 layout to go back to was " .. (kept and "kept for " .. key or "dropped")) end
end

-- See the notes above Say.
local function EditModeReady()
    local manager = EditModeManagerFrame
    if type(manager) ~= "table" or type(manager.IsInitialized) ~= "function" then return true end -- cannot tell: go ahead, as 0.11.0
    local ok, ready = pcall(manager.IsInitialized, manager)
    if not ok then return true end
    return ready and true or false
end

local pending = false   -- Settle is still to run (a login check, or a switch-on)
local waiting = false   -- listening for the next PLAYER_ENTERING_WORLD or EDIT_MODE_LAYOUTS_UPDATED
local Settle            -- set below the option rows, which it may run
local onWaitEvent
local WAIT_EVENTS = { "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED" }
local WAIT_KEY = "ctrlLayout:wait"

local function StopWaiting()
    if not waiting then return end
    waiting = false
    for _, event in ipairs(WAIT_EVENTS) do PE:UnregisterCoreEvent(event, WAIT_KEY) end
end

local function StartWaiting()
    if waiting then return end
    waiting = true
    onWaitEvent = onWaitEvent or PE:Wrap("ctrlLayout", function()
        PE:RunOutOfCombat("ctrlLayout:settle", Settle)
    end)
    for _, event in ipairs(WAIT_EVENTS) do PE:RegisterCoreEvent(event, WAIT_KEY, onWaitEvent) end
end

-- Asks for Settle: now if it can, else at the next of those events, out of combat.
local function Begin()
    pending = true
    StartWaiting()
    PE:RunOutOfCombat("ctrlLayout:settle", Settle)
end

-- Switches the feature back off after a refusal, once OnEnable has returned.
local function Refuse(text)
    if text then Say(text) end
    if PE.debugOn then PE:Debug("ctrlLayout", "switch-on refused") end
    mod:After(0, function() PE:SetModuleEnabled("ctrlLayout", false) end)
end

local function Fail(msg)
    PE:LogError("ctrlLayout", msg)
    Refuse(nil)
end

---------------------------------------------------------------------------
-- Bars: the game's four gamepad bar anchors and the both-triggers bar, moved
-- and scaled as whole frames (spec "Bars (placed by the addon)").
--
-- Blizzard_GamepadActionBars (build 1.60.1.70938): ActionBarTemplates.xml
-- makes PageUnit's Top, Left, Right and Bottom CenteredAnchor (50 x 50,
-- CENTER on PageUnit at (0, 58), (-195, 0), (195, 0), (0, -58)), each with a
-- Bar anchored CENTER on it. The game sets no scale on them and re-anchors
-- only the Top, Left and Right anchors, in PageUnit:RefreshCompactLayout
-- (PageUnit.lua:292-315). The both-triggers bar is moved itself, because the
-- sub-menu buttons follow the bottom anchor (ClassActionFlyout.lua:24-25).
--
-- These frames hold protected spell buttons: nothing here runs in combat
-- (everything goes through PE:RunOutOfCombat), and nothing is ever written
-- into the game's tables; the points and scales found are kept here.
---------------------------------------------------------------------------

local REFRESH_METHOD = "RefreshCompactLayout"

-- Each frame by its path from GamepadMainActionBarFrame, and the BarSpots group it takes.
local BAR_FRAMES = {
    { spot = "top", path = { "PageUnit", "TopCenteredAnchor" } },
    { spot = "left", path = { "PageUnit", "LeftCenteredAnchor" } },
    { spot = "right", path = { "PageUnit", "RightCenteredAnchor" } },
    { spot = "bottom", path = { "PageUnit", "BottomCenteredAnchor" } },
    { spot = "both", path = { "PageUnit", "BottomCenteredAnchor", "Bar" } },
}

local found = {}        -- [frame] = { points = { { point, relativeTo, relativePoint, x, y }, ... }, scale }
local foundOrder = {}   -- the frames in `found`, in the order they were first read
local placed = false    -- the bars are where the addon put them
local refreshHooked = false
local missingLogged = false

local function Child(t, key)
    if type(t) ~= "table" then return nil end
    local v = t[key]
    return type(v) == "table" and v or nil
end

-- The five frames as { [spot] = frame }, or nil (logged once) if one is missing.
local function BarFrames()
    local out = {}
    for _, b in ipairs(BAR_FRAMES) do
        local f = GamepadBar()
        for _, key in ipairs(b.path) do f = Child(f, key) end
        if not f then
            if not missingLogged then
                missingLogged = true
                if PE.debugOn then
                    PE:Debug("ctrlLayout", "bars not placed: GamepadMainActionBarFrame." .. table.concat(b.path, ".") .. " is missing")
                end
            end
            return nil
        end
        out[b.spot] = f
    end
    return out
end

-- Reads a frame's points and scale, once a session. True if they are known.
local function Remember(f)
    if found[f] then return true end
    if type(f.GetNumPoints) ~= "function" or type(f.GetPoint) ~= "function" or type(f.GetScale) ~= "function" then
        return false
    end
    local ok, n = pcall(f.GetNumPoints, f)
    if not ok or type(n) ~= "number" then return false end
    local points = {}
    for i = 1, n do
        local okPoint, point, relativeTo, relativePoint, x, y = pcall(f.GetPoint, f, i)
        if not okPoint or type(point) ~= "string" then return false end
        points[i] = { point, relativeTo, relativePoint, x, y }
    end
    local okScale, scale = pcall(f.GetScale, f)
    if not okScale or type(scale) ~= "number" then return false end
    found[f] = { points = points, scale = scale }
    foundOrder[#foundOrder + 1] = f
    return true
end

local function Movable(f)
    return type(f.ClearAllPoints) == "function" and type(f.SetPoint) == "function" and type(f.SetScale) == "function"
end

-- One frame to CENTER on the screen's bottom centre at (x, y) UI units, scale s.
local function Put(f, x, y, s)
    local ok, err = pcall(f.ClearAllPoints, f)
    if ok then ok, err = pcall(f.SetScale, f, s) end
    if ok then ok, err = pcall(f.SetPoint, f, "CENTER", UIParent, "BOTTOM", x / s, y / s) end
    if not ok then PE:LogError("ctrlLayout", "A bar could not be placed: " .. tostring(err)) end
end

-- A frame's points as read before the first change, then its scale.
local function PutBackPoints(f, points)
    local ok, err = pcall(f.ClearAllPoints, f)
    for _, p in ipairs(points) do
        if ok then ok, err = pcall(f.SetPoint, f, p[1], p[2], p[3], p[4], p[5]) end
    end
    return ok, err
end

-- The points the game itself keeps for a re-anchored bar anchor with Compact
-- off (PageUnit.anchorPoints, filled by InitializeCompactLayout,
-- PageUnit.lua:271-290; read only), as { { point, relativeTo, relativePoint,
-- x, y }, ... }, or nil when that table is missing or empty.
local function GamePoints(pageUnit, anchor)
    local all = Child(pageUnit, "anchorPoints")
    local list = all and all[anchor]
    if type(list) ~= "table" or #list == 0 then return nil end
    local out = {}
    for i, p in ipairs(list) do
        if type(p) ~= "table" or type(p.point) ~= "string" then return nil end
        out[i] = { p.point, p.relativeTo, p.relativePoint, p.x or 0, p.y or 0 }
    end
    return out
end

-- Puts the bars back. The bottom anchor and the both-triggers bar, which the
-- game never re-anchors, go back to the points read before the first change.
-- The Top, Left and Right anchors follow the game's current Compact setting
-- (PageUnit:RefreshCompactLayout, PageUnit.lua:292-315), because a layout
-- picked meanwhile may have changed it: Compact on, all points on the bottom
-- anchor; Compact off, the game's own points for each, or ours if the game
-- keeps none. Every scale comes from what was read.
local function RestoreNow()
    if not placed then return end
    placed = false
    local frames = BarFrames()
    local reanchored = {}
    if frames then
        for _, spot in ipairs({ "top", "left", "right" }) do reanchored[frames[spot]] = true end
    end
    local root = GamepadBar()
    local pageUnit = Child(root, "PageUnit")
    local compact = root ~= nil and root.useCompactLayout == true
    local order = {}
    for _, f in ipairs(foundOrder) do if not reanchored[f] then order[#order + 1] = f end end
    for _, f in ipairs(foundOrder) do if reanchored[f] then order[#order + 1] = f end end
    for _, f in ipairs(order) do
        local was = found[f]
        if Movable(f) then
            local ok, err
            if not reanchored[f] then
                ok, err = PutBackPoints(f, was.points)
            elseif compact and type(f.SetAllPoints) == "function" then
                ok, err = pcall(f.ClearAllPoints, f)
                if ok then ok, err = pcall(f.SetAllPoints, f, frames.bottom) end
            else
                ok, err = PutBackPoints(f, GamePoints(pageUnit, f) or was.points)
            end
            if ok then ok, err = pcall(f.SetScale, f, was.scale) end
            if not ok then PE:LogError("ctrlLayout", "A bar could not be put back: " .. tostring(err)) end
        end
    end
    if PE.debugOn then PE:Debug("ctrlLayout", "bars put back" .. (compact and " (compact)" or "")) end
end

local function PlaceNow()
    local frames = BarFrames()
    if not frames then return end
    -- Every frame read before any is changed.
    for _, b in ipairs(BAR_FRAMES) do
        local f = frames[b.spot]
        if not Remember(f) or not Movable(f) then
            if PE.debugOn then PE:Debug("ctrlLayout", "bars not placed: a bar frame cannot be read or moved") end
            return
        end
    end
    local spots = Plan.BarSpots(mod.opts)
    placed = true
    for _, b in ipairs(BAR_FRAMES) do
        local spot = spots[b.spot]
        Put(frames[b.spot], spot.x, spot.y, spot.s)
    end
    if PE.debugOn then PE:Debug("ctrlLayout", "bars placed") end
end

-- Places the bars while the feature is on and our layout is the active one,
-- else puts them back; out of combat. Safe to call in any state.
local function SyncBars()
    PE:RunOutOfCombat("ctrlLayout:bars", function()
        if wanted and IsOursActive() then PlaceNow() else RestoreNow() end
    end)
end

-- Puts the bars back, out of combat, unless the feature is on again by then.
local function RestoreBars()
    PE:RunOutOfCombat("ctrlLayout:restore", function()
        if not wanted then RestoreNow() end
    end)
end

-- After the game re-anchors the bars, place them again. Installed once and
-- never removed; does nothing while the feature is off.
local function HookRefresh()
    if refreshHooked then return end
    local pageUnit = Child(GamepadBar(), "PageUnit")
    if not pageUnit or type(hooksecurefunc) ~= "function" or type(pageUnit[REFRESH_METHOD]) ~= "function" then return end
    local ok = pcall(hooksecurefunc, pageUnit, REFRESH_METHOD, PE:Wrap("ctrlLayout", function()
        if wanted then SyncBars() end
    end))
    refreshHooked = ok and true or false
end

-- The base of a new layout: a copy of the active layout if it is a Gamepad
-- layout, else of the Gamepad preset. A copy, so it may be changed.
local function TemplateBase(state, e)
    local presetsCopy = CopyOfPresets()
    if not presetsCopy then return nil end
    local base
    local current = state.current
    if current and current.style == e.style.Gamepad then
        if current.isPreset then
            base = presetsCopy[state.active]
        else
            base = DeepCopy(state.saved[state.active - state.numPresets])
        end
    end
    if type(base) ~= "table" then
        base = presetsCopy[e.preset.Gamepad + 1]
        if type(base) ~= "table" or base.layoutIndex ~= e.preset.Gamepad then return nil end
    end
    base.layoutIndex = nil -- a preset's own field; a saved layout has none
    return base
end

-- Saves the whole list the way Blizzard does (MakeNewLayout,
-- EditModeManager.lua:1567-1589): a fresh copy of the presets first, then the
-- saved layouts in order; activeLayout is left as the game gave it. Every
-- save goes through here. Returns true, or false and the reason. state.info
-- is changed (its list replaced), so read the layouts again after a save.
local function SaveAll(state, savedLayouts)
    local all = CopyOfPresets()
    if not all or #all ~= state.numPresets then return false, "The game's preset layouts could not be copied" end
    for i, layout in ipairs(savedLayouts) do all[state.numPresets + i] = layout end
    local info = state.info -- the game's answer is a copy, so it may be changed
    info.layouts = all
    local ok, err = pcall(state.api.SaveLayouts, info)
    if not ok then return false, "C_EditMode.SaveLayouts failed: " .. tostring(err) end
    return true
end

-- Saves a new "Pocket Essentials" layout after the last account-wide one and
-- makes it active. Returns ok, wrote: ok is true if the game took it; wrote is
-- true once something was written (even if a later call failed). On failure it
-- says why or logs it, and switches the feature back off.
local function AddOurs(state, e)
    local count, lastAccount = 0, nil
    for i, layout in ipairs(state.saved) do
        if type(layout) ~= "table" then
            Fail("C_EditMode.GetLayouts gave a layout that is not a table")
            return false, false
        end
        if layout.layoutType == e.layoutType.Account then
            count = count + 1
            lastAccount = state.numPresets + i
        end
    end
    if count >= MAX_LAYOUTS then
        Refuse("You already have " .. MAX_LAYOUTS .. " account-wide layouts. Delete one in Edit Mode, then switch this on again.")
        return false, false
    end
    if type(state.api.IsValidLayoutName) == "function" then
        local ok, valid = pcall(state.api.IsValidLayoutName, Plan.NAME)
        if ok and not valid then
            Refuse(TEXT_NAME_REFUSED)
            return false, false
        end
    end
    local base = TemplateBase(state, e)
    if not base then
        Fail("The game's preset layouts could not be copied")
        return false, false
    end
    local layout = Plan.Build(base, mod.opts, e)
    local newIndex = lastAccount and (lastAccount + 1) or (state.numPresets + 1)
    local list = {}
    for i, l in ipairs(state.saved) do list[i] = l end
    tinsert(list, newIndex - state.numPresets, layout)
    local ok, err = SaveAll(state, list)
    if not ok then
        Fail(err)
        return false, false
    end
    -- (index, activate it, imported): as Blizzard's MakeNewLayout.
    ok, err = pcall(state.api.OnLayoutAdded, newIndex, true, false)
    if not ok then
        Fail("C_EditMode.OnLayoutAdded failed: " .. tostring(err))
        return false, true
    end
    if PE.debugOn then PE:Debug("ctrlLayout", "saved the Pocket Essentials layout at index " .. newIndex) end
    return true, true
end

local function SwitchOn()
    if not wanted then return end -- switched off again before this ran
    if EditModeOpen() then
        Refuse(TEXT_EDIT_MODE)
        return
    end
    local key = CharKey()
    if not key then
        Fail("The character's name could not be read")
        return
    end
    local e = Enums()
    local state, why = ReadState()
    if not e or not state then
        Fail("The layout list could not be read: " .. tostring(why or "the game's enums are missing"))
        return
    end
    local oursIndex = OursIndex(state)
    if oursIndex and state.active == oursIndex then
        -- Already in use (picked in Edit Mode, or switched on for this character
        -- elsewhere): nothing to change. Off goes back to the Gamepad preset.
        if not PrevOf(key) then SetPrev(key, { preset = e.preset.Gamepad }) end
        SyncBars()
        mod:RefreshPanel()
        return
    end
    local current = state.current
    local prev = current and { name = current.name, layoutType = current.layoutType, preset = current.preset }
        or { preset = e.preset.Gamepad }
    if oursIndex then
        SetPrev(key, prev)
        local ok, err = pcall(state.api.SetActiveLayout, oursIndex)
        if not ok then
            SetPrev(key, nil)
            Fail("C_EditMode.SetActiveLayout failed: " .. tostring(err))
            return
        end
    else
        SetPrev(key, prev) -- before the write: switching off must undo even a half-done change
        local called, ok, wrote = pcall(AddOurs, state, e)
        if not called then
            -- Every game call in AddOurs is protected, so an error here came
            -- before anything was written.
            SetPrev(key, nil)
            Fail("Building the layout failed: " .. tostring(ok))
            return
        end
        if not ok then
            if not wrote then SetPrev(key, nil) end
            return
        end
    end
    mod:RequestReload(RELOAD_REASON)
    -- The game may report the change only after the reload, so a re-read that
    -- does not show ours as active yet is not a refusal: the feature stays on.
    if PE.debugOn and not IsOursActive() then
        PE:Debug("ctrlLayout", "the Pocket Essentials layout does not read as active yet; the reload finishes it")
    end
    SyncBars() -- best effort: placed only once ours reads as active
    mod:RefreshPanel()
end

-- Puts back this character's own layout, if ours is the active one, and forgets
-- the entry. atLogin: Settle's check with the feature off, which asks for the
-- reload only when it changed the layout (a tap on the switch always asks).
local function SwitchOff(atLogin)
    if wanted then return end -- switched on again before this ran
    local key = CharKey()
    if not key then
        Begin() -- tried again once the name can be read
        return
    end
    Migrate(key)
    local prev = PrevOf(key)
    if not prev then return end
    local state, why = ReadState()
    if not state then
        -- Kept: the next switch-off tries again.
        PE:LogError("ctrlLayout", "The layout list could not be read: " .. tostring(why))
        return
    end
    local oursIndex = OursIndex(state)
    local changed = false
    if oursIndex and state.active == oursIndex then
        local target
        if prev.preset ~= nil then
            target = FindPreset(state, prev.preset)
        else
            target = FindSaved(state, prev.name, prev.layoutType)
        end
        target = target or GamepadPresetIndex(state)
        if target then
            local ok, err = pcall(state.api.SetActiveLayout, target)
            if not ok then
                PE:LogError("ctrlLayout", "C_EditMode.SetActiveLayout failed: " .. tostring(err))
                return -- kept: the next switch-off tries again
            end
            changed = true
        end
    end
    SetPrev(key, nil)
    if PE.debugOn then PE:Debug("ctrlLayout", "switched off for " .. key .. (changed and ", its own layout put back" or "")) end
    if changed or not atLogin then mod:RequestReload(RELOAD_REASON) end
end

---------------------------------------------------------------------------
-- Option rows (spec "Options on the card"). Rows marked (L) there rewrite
-- only their pieces in our layout and ask for a reload; rows marked (B)
-- place the bars again at once. Both run out of combat.
---------------------------------------------------------------------------

local TEXT_START_OVER = "Tap Start over again to replace the Pocket Essentials layout with the template."
local START_OVER_SECONDS = 20

local applied = {}         -- the option values last applied: what a refused change is put back to
local pendingRewrites = {} -- { keep = piece filter, key, old = value before } waiting for RunRewrites
                           -- (several changes in one fight add up; kept over off and on until written)
local rowNote              -- an option row's refusal, shown in the status line while on until the next accepted change
local startOverUntil = 0   -- GetTime() until which a second Start over tap confirms

local function Now() return (GetTime and GetTime()) or 0 end

local function RememberApplied(opts)
    local o = Fill(opts)
    for k in pairs(Plan.DEFAULTS) do applied[k] = o[k] end
end

-- Which pieces of Plan.Pieces each (L) row rewrites.
local function TimersAndMap(p) return p.system == "SwingTimer" or p.system == "Minimap" end
local REWRITES = {
    main = TimersAndMap,                                         -- the map's height and the timer stack under it
    map = TimersAndMap,                                          -- the map's size, and the timers that hang on the bars
    frames = function(p) return p.system == "UnitFrame" end,     -- Player, Pet, Target
    timers = TimersAndMap,
    ranged = function(p) return p.system == "SwingTimer" and p.index == "Ranged" end,
    mainHand = function(p) return p.system == "SwingTimer" and p.index == "MainHand" end,
    offHand = TimersAndMap,                                      -- the stack and the map's height depend on it
}

-- Our layout from a fresh read: state, its position in state.saved, and enums;
-- or nil (logged when the read itself failed).
local function ReadOurs()
    local e = Enums()
    local state, why = ReadState()
    if not e or not state then
        PE:LogError("ctrlLayout", "The layout list could not be read: " .. tostring(why or "the game's enums are missing"))
        return nil
    end
    local index = OursIndex(state)
    if not index then
        -- Deleted or never saved: nothing to rewrite; the status line says another layout is active.
        if PE.debugOn then PE:Debug("ctrlLayout", "the Pocket Essentials layout is not saved; nothing rewritten") end
        mod:RefreshPanel()
        return nil
    end
    return state, index - state.numPresets, e
end

local function RunRewrites()
    if not wanted or #pendingRewrites == 0 then return end -- kept for the next switch-on
    local list = pendingRewrites
    pendingRewrites = {}
    local state, pos, e = ReadOurs()
    if not state then return end
    local pieces = {}
    for _, p in ipairs(Plan.Pieces(mod.opts)) do
        for _, r in ipairs(list) do
            if r.keep(p) then
                pieces[#pieces + 1] = p
                break
            end
        end
    end
    Plan.Apply(state.saved[pos], pieces, e) -- our entry, in place (GetLayouts gave a copy)
    local ok, err = SaveAll(state, state.saved)
    if not ok then
        PE:LogError("ctrlLayout", err)
        -- Nothing was written: the options go back to what the layout has, and the bars with them.
        for i = #list, 1, -1 do
            local r = list[i]
            if r.key then
                mod.opts[r.key] = r.old
                applied[r.key] = r.old
            end
        end
        SyncBars()
        mod:RefreshPanel()
        return
    end
    mod:RequestReload(RELOAD_REASON)
end

-- Rewrites our layout's pieces that `filter` picks, for the option `key`.
-- Refused while Edit Mode is open: the option is put back. Returns true if
-- the change goes ahead.
local function RewritePieces(filter, key)
    if EditModeOpen() then
        if key then mod.opts[key] = applied[key] end
        rowNote = TEXT_EDIT_MODE -- the status line only, no chat line for a tap
        mod:RefreshPanel()
        return false
    end
    rowNote = nil
    local old = key and applied[key]
    if key then applied[key] = mod.opts[key] end
    pendingRewrites[#pendingRewrites + 1] = { keep = filter, key = key, old = old }
    PE:RunOutOfCombat("ctrlLayout:rewrite", RunRewrites)
    return true
end

-- OnChange of a row: (L) rows rewrite their pieces, (B) rows place the bars.
local function LayoutRow(key, bars)
    return function()
        if RewritePieces(REWRITES[key], key) and bars then SyncBars() end
    end
end

local function BarsRow(key)
    return function(m)
        applied[key] = m.opts[key]
        SyncBars()
    end
end

local function RunStartOver()
    if not wanted then return end
    local state, pos, e = ReadOurs()
    if not state then return end
    local presets = CopyOfPresets()
    local base = presets and presets[e.preset.Gamepad + 1]
    if type(base) ~= "table" or base.layoutIndex ~= e.preset.Gamepad then
        PE:LogError("ctrlLayout", "The game's Gamepad preset could not be copied")
        return
    end
    base.layoutIndex = nil
    state.saved[pos] = Plan.Build(base, mod.opts, e)
    local ok, err = SaveAll(state, state.saved)
    if not ok then
        PE:LogError("ctrlLayout", err)
        return
    end
    if PE.debugOn then PE:Debug("ctrlLayout", "the Pocket Essentials layout was rebuilt from the template") end
    mod:RequestReload(RELOAD_REASON)
end

local function StartOver()
    local now = Now()
    if startOverUntil == 0 or now > startOverUntil then
        startOverUntil = now + START_OVER_SECONDS
        rowNote = nil
        mod:RefreshPanel()
        return
    end
    startOverUntil = 0
    if EditModeOpen() then
        rowNote = TEXT_EDIT_MODE
        mod:RefreshPanel()
        return
    end
    rowNote = nil
    PE:RunOutOfCombat("ctrlLayout:startOver", RunStartOver)
end

local SIZES = { { value = 0.85, label = "Smaller" }, { value = 1, label = "Same" }, { value = 1.15, label = "Bigger" } }
local VISIBILITY = { { value = 0, label = "Always" }, { value = 1, label = "In combat" }, { value = 2, label = "Hidden" } }

local OPTIONS = {
    { key = "main", label = "Main bar",
      choices = { { value = "above", label = "Above the map" }, { value = "under", label = "Under the map" } },
      OnChange = LayoutRow("main", true) },
    { key = "map", label = "Map size",
      choices = { { value = 60, label = "60%" }, { value = 70, label = "70%" }, { value = 80, label = "80%" } },
      OnChange = LayoutRow("map", true) },
    { key = "frames", label = "Player and target frames",
      choices = { { value = "corner", label = "Corners" }, { value = "stacked", label = "Stacked" },
                  { value = "flat", label = "Side by side" } },
      OnChange = LayoutRow("frames", false) },
    { key = "size", label = "Spell button size",
      help = "Below 100%, a spell that opens its own wheel may open beside its button.",
      number = { min = 70, max = 100, step = 5, default = 100, suffix = "%" },
      OnChange = BarsRow("size") },
    { key = "fineMain", label = "Main bar size", choices = SIZES, OnChange = BarsRow("fineMain") },
    { key = "fineSide", label = "LT and RT bar size", choices = SIZES, OnChange = BarsRow("fineSide") },
    { key = "fineBoth", label = "Both-triggers bar size", choices = SIZES, OnChange = BarsRow("fineBoth") },
    { key = "timers", label = "Swing timers",
      choices = { { value = "under", label = "Under the map" }, { value = "above", label = "Above the bars" },
                  { value = "bars", label = "Under the LT and RT bars" } },
      OnChange = LayoutRow("timers", true) },
    { key = "ranged", label = "Ranged timer", choices = VISIBILITY, OnChange = LayoutRow("ranged", false) },
    { key = "mainHand", label = "Main Hand timer", choices = VISIBILITY, OnChange = LayoutRow("mainHand", false) },
    { key = "offHand", label = "Off Hand timer", choices = VISIBILITY, OnChange = LayoutRow("offHand", false) },
    { label = "Template", button = "Start over", action = function() StartOver() end },
}

-- This character's check (see the notes above Say). Runs out of combat; waits
-- (and is called again by the next PLAYER_ENTERING_WORLD or
-- EDIT_MODE_LAYOUTS_UPDATED) while the character's name or Edit Mode's layouts
-- are not known yet.
Settle = function()
    if not pending then
        StopWaiting()
        return
    end
    if not EditModeReady() then
        if PE.debugOn then PE:Debug("ctrlLayout", "waiting for Edit Mode's layouts") end
        return
    end
    local key = CharKey()
    if not key then
        if PE.debugOn then PE:Debug("ctrlLayout", "waiting for the character's name") end
        return
    end
    pending = false
    StopWaiting()
    Migrate(key)
    if wanted then
        if PrevOf(key) then
            SyncBars()
            mod:RefreshPanel()
        else
            SwitchOn()
        end
        -- Option changes not yet written when the feature went off (after SwitchOn, so ours exists).
        if #pendingRewrites > 0 then PE:RunOutOfCombat("ctrlLayout:rewrite", RunRewrites) end
    elseif PrevOf(key) then
        SwitchOff(true)
    end
end

local defaults = DeepCopy(Plan.DEFAULTS)
defaults.prev = false -- the 0.11.0 file's single layout to go back to; read once, then false
defaults.prevs = {}   -- each character's layout to go back to, by "<name>-<realm>"

mod = PE:RegisterModule({
    key = "ctrlLayout",
    label = "Controller layout",
    desc = "Map bottom middle, spell bars around it, chat top right.",
    order = 60,
    experimental = true,
    statusWhenOff = true,
    defaults = defaults,
    options = OPTIONS,

    blocked = function()
        -- Once a switch-on has changed this character's layout, never blocked: switching off
        -- must always be possible, and a login where the Gamepad style is not reported yet
        -- must not stop it. The same while the 0.11.0 file's single entry is still unread.
        if mod and type(mod.opts) == "table" and (HasLegacy() or ThisPrev()) then return nil end
        if not PE:GamepadUI() then return TEXT_NEEDS_GAMEPAD end
        if not Api() or not Presets() or not GamepadBar() then return TEXT_NO_LAYOUTS end
        return nil
    end,

    -- Reads only.
    status = function(m)
        if not m:IsEnabled() then
            if note then return { note, TEXT_OFF } end
            return TEXT_OFF
        end
        if note then return note end
        if rowNote then return rowNote end
        if startOverUntil > 0 and Now() <= startOverUntil then return TEXT_START_OVER end
        if type(m.opts) ~= "table" or not ThisPrev() then return nil end -- still to be done
        local state = ReadState()
        if not state then return nil end
        local index = OursIndex(state)
        if index and state.active == index then return TEXT_USING end
        return TEXT_ANOTHER
    end,

    -- At login, on or off. While off this is the module's one piece of work: when a layout is
    -- remembered for this character (it was switched off on another one), Settle puts it back.
    -- With the feature on, OnEnable (right after) does the same check.
    OnLoad = function(self)
        if PE:IsModuleSavedOn("ctrlLayout") or type(self.opts) ~= "table" then return end
        if not HasLegacy() and next(Prevs()) == nil then return end -- nothing remembered for anyone
        local key = CharKey()
        if key and not PrevOf(key) and not HasLegacy() then return end -- nothing for this character
        Begin()
    end,

    OnEnable = function(self)
        note = nil
        wanted = true
        startOverUntil = 0
        rowNote = nil
        RememberApplied(self.opts)
        HookRefresh()
        self:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", SyncBars)
        self:RegisterEvent("PLAYER_ENTERING_WORLD", SyncBars)
        if ThisPrev() then
            -- Switched on before on this character (this is a login, or on again before the
            -- switch-off ran): the layouts are left as they are; only the bars are placed.
            SyncBars()
            -- Option changes not yet written when the feature went off.
            if #pendingRewrites > 0 then PE:RunOutOfCombat("ctrlLayout:rewrite", RunRewrites) end
        else
            -- This character's login check, or a switch-on: Settle, once the character's
            -- name and Edit Mode's layouts are known.
            Begin()
        end
    end,

    OnDisable = function(self)
        wanted = false
        rowNote = nil
        RestoreBars() -- first: bars placed by any path are always put back
        if not HasLegacy() and not ThisPrev() then return end -- no layout was changed for this character
        PE:RunOutOfCombat("ctrlLayout:off", function() SwitchOff(false) end)
    end,
})
