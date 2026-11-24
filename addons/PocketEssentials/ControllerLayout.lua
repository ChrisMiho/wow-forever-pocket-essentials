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
-- Sizes come from Blizzard's source and the probe's measurements (see MAP,
-- TIMER, FRAMES, BAR below); every spot is the mockup's, moved only where a real
-- size does not fit (0.12.0 spec, "As built").
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
local sort = table.sort

local Plan = {}
PE.LayoutPlan = Plan

Plan.NAME = "Pocket Essentials"

-- 0.12.0 (spec 2026-11-23-controller-layout-0.12.0-mockup-setup.md): one setup,
-- the mockup's "Face bars (one setup)" (docs/ui-review/mockup-0.8.1.html,
-- drawFace) with the game's real bars. The only options left are the three
-- swing timers' visibility. Every spot below is in UI units at UI scale 1
-- (1365 by 768): x from the screen's centre, y ("up") from its bottom edge.
-- How each number follows from the Camelot source is in
-- docs/superpowers/plans/2026-11-23-controller-layout-0.12.0.md.

Plan.DEFAULTS = {
    ranged = 1,         -- timer visibility: 0 Always, 1 In combat, 2 Hidden
    mainHand = 1,
    offHand = 2,
}

-- The template's version, saved with our layout whenever it is built
-- (opts.template). A login that finds an older one rebuilds our layout once.
-- 1: 0.11.x (no number saved). 2: 0.12.0, the mockup's one setup.
Plan.TEMPLATE = 2

-- An XP bar: 17 high (STATUS_BAR_CONTAINER_HEIGHT,
-- Blizzard_StatusTrackingBar/Camelot/StatusTrackingBarConstants.lua:2), 596 wide at 100%
-- with the Gamepad UI (STATUS_BAR_CONTAINER_WIDTH_GAMEPAD, same file, line 12, and
-- StatusTrackingManagerOverrides.lua:80-81). The game's Gamepad preset stacks bar 2 one bar
-- height above bar 1 (Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:1441-1461, offsetY 0
-- and 17 on StatusTrackingBarManager's bottom); with a Gamepad layout the game places both
-- by their saved spot (Blizzard_EditMode/Camelot/EditModeUtil.lua:5-9). At the screen's top
-- edge there is no room above, so here bar 2 sits one bar height under bar 1.
local XP_H = 17
local XP_TOP_Y = -2 -- the first XP bar's top edge, from the screen's top

local UI = "UIParent"

-- The map: Edit Mode Size 2 (70%; the stored Size counts in steps of 10% from 50%),
-- its title strip underneath. With the strip underneath, the Forever map code puts
-- the round map's frame 30 up and 10 right of the map's own bottom
-- (Blizzard_Minimap/Camelot/Minimap.lua:72-73), scaled to 70%: a 253 frame (probe,
-- 2026-11-23) holding the 198 round map at its centre (Mainline/Minimap.xml:60-62).
-- Its spot is 10 left of the centre so the round map itself is centred.
local MAP = { size = 70, x = -10, y = 38, frame = 253, round = 198, frameUp = 30, frameRight = 10 }
-- The title strip (zone, clock): 152 by 23, 8 up and 1 left of the map's bottom
-- (Camelot/MinimapZoneTextButton.xml:9, Camelot/Minimap.lua:75-76).
local STRIP = { w = 152, h = 23, up = 8, x = -1 }

-- Swing timers: Scale 3 (80%), Width 0 (213), Height 0 (15): 170.4 by 12 each
-- (Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:2784-2804, settings at
-- EditModeSettingDisplayInfo.lua:777-830). Edit Mode places a frame's spot in UI
-- units whatever its scale (EditModeSystemTemplates.lua:373-375). Stacked under the
-- title strip, Main Hand on top as the mockup draws them.
local TIMER = { w = 213 * 0.8, h = 15 * 0.8, y = { MainHand = 31, OffHand = 17, Ranged = 3 } }

-- The unit frames: player and target 232 by 100
-- (Blizzard_UnitFrame/Mainline/PlayerFrame.xml:14), pet and target of target 120 by
-- 49 (probe; TargetofTargetFrameTemplate, Mainline/TargetFrame.xml:398). The mockup
-- drew them smaller (192 by 60, 112 by 34); the frames keep its inner edges (x -236
-- and +236).
local UNIT = { w = 232, h = 100 }
local SMALL = { w = 120, h = 49 }

-- What the target frame puts around itself in a fight:
--   * Its auras: with Edit Mode's BuffsOnTop (EditModeSettingDisplayInfo.lua:215-219, set on
--     the target by the game's own Gamepad preset, Mainline/EditModePresetLayouts.lua:1312-1316)
--     they grow up from the frame picture's top, 6 into it
--     (TargetFrame.lua:538-555, AURA_START_X 5, AURA_MIRRORED_START_Y -6, lines 5-7), in rows
--     of at most 122 (101 for the first two while the target of target shows) with 21
--     icons, 3 apart (Shared/TargetFrameAuraShared.lua:6-19). Two rows reach 22.5 above
--     the frame's top. The frame picture is centred in the frame
--     (Mainline/TargetFrame.xml:78-81); its size, 192 by 67, is the retail atlas (not in
--     this source).
--   * Its cast bar, 150 by 10 (Mainline/TargetFrame.xml:536-537): with the target of
--     target shown and the Gamepad UI on, 123 right of and 46 under the frame's bottom
--     left (TargetFrame.lua:830-852, from TargetOfTargetMixin:Update, line 914). The
--     frame sits high enough that this spot clears the RT bar.
local TARGET_AURAS = { picture = { w = 192, h = 67 }, startX = 5, startY = -6, rowWidth = 122, rows = 2, size = 21, spacing = 3 }
local TARGET_CAST = { x = 123, y = -46, w = 150, h = 10 }

-- Player and target 226 up: the target's cast bar (226 - 46 - 10 = 170) then clears the
-- RT bar's top (167). The player side is the mirror. The pet and the target of target
-- sit above the two aura rows (25 over the frames' tops), the pet right-aligned and
-- the target of target left-aligned with the frames' inner edges.
local FRAME_Y = 226
local SMALL_Y = FRAME_Y + UNIT.h + 25
local FRAMES = {
    Player = { "BOTTOMRIGHT", UI, "BOTTOM", -236, FRAME_Y },
    Pet = { "BOTTOMRIGHT", UI, "BOTTOM", -236, SMALL_Y },
    Target = { "BOTTOMLEFT", UI, "BOTTOM", 236, FRAME_Y },
}

-- The target of target, placed by the module on the target frame (see EXTRAS).
Plan.TOT_SPOT = { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", x = 0, y = SMALL_Y - FRAME_Y - UNIT.h }
-- The two LB / RB targeting pictures, placed by the module on UIParent's bottom (see EXTRAS).
Plan.SHOULDERS = { left = { "BOTTOMRIGHT", -108, 84 }, right = { "BOTTOMLEFT", 108, 84 } }

-- A bar that does not grow: 208 by 68 (Blizzard_GamepadActionBars/ActionBarStyles.lua:172;
-- the template switches growing off, ShouldExpand 0).
local BAR = { w = 208, h = 68 }

-- The four bars, whole, at scale 1, and the bottom anchor that carries the two
-- sub-menu buttons (at -138 / +138, -50 from it:
-- Blizzard_GamepadActionBars/MainActionBarFrame.xml:94-112), so they sit 138 either
-- side of the centre, 188 up.
local SPOTS = {
    left = { x = -335, y = 133, s = 1 },  -- LT bar
    top = { x = -335, y = 45, s = 1 },    -- main bar (no trigger)
    right = { x = 335, y = 133, s = 1 },  -- RT bar
    both = { x = 335, y = 45, s = 1 },    -- LT + RT bar
    bottom = { x = 0, y = 238, s = 1 },   -- sub-menu buttons at (±138, 188)
}

-- The options with every missing or unusable value replaced by its default.
-- Values saved by older versions for rows that are gone are ignored.
local function Fill(opts)
    local out = {}
    opts = type(opts) == "table" and opts or {}
    for k, default in pairs(Plan.DEFAULTS) do
        local v = opts[k]
        if v == 0 or v == 1 or v == 2 then out[k] = v else out[k] = default end
    end
    return out
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end

-- Where each bar group's centre goes, and its scale (always 1). x and y are UI
-- units from the screen's bottom centre.
function Plan.BarSpots()
    return DeepCopy(SPOTS)
end

-- A frame's rectangle from its anchor point (on UIParent's bottom) and its size.
local function RectAt(point, x, y, w, h)
    local left = (point:find("LEFT") and x) or (point:find("RIGHT") and x - w) or x - w / 2
    local bottom = (point:find("BOTTOM") and y) or (point:find("TOP") and y - h) or y - h / 2
    return { left, bottom, left + w, bottom + h }
end

-- The rectangles the template puts on screen, for the overlap check:
-- { name = { left, bottom, right, top } } in UI units from the bottom centre,
-- worked out from the spots and sizes above. The quest tracker is taken at the
-- height the probe measured (264). The target's two aura rows are the part above
-- the frame; its cast bar is the spot it takes with the target of target shown.
function Plan.Rects()
    local r = {}
    local function box(name, cx, cy, w, h) r[name] = { cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2 } end
    for name, s in pairs(SPOTS) do
        if name ~= "bottom" then box(name .. " bar", s.x, s.y, BAR.w, BAR.h) end
    end
    local roundCentre = MAP.y + MAP.frameUp + MAP.frame * MAP.size / 100 / 2
    local round = MAP.round * MAP.size / 100
    box("map", MAP.x + MAP.frameRight, roundCentre, round, round)
    r["title strip"] = { MAP.x + STRIP.x - STRIP.w / 2, MAP.y + STRIP.up, MAP.x + STRIP.x + STRIP.w / 2, MAP.y + STRIP.up + STRIP.h }
    for name, y in pairs(TIMER.y) do r[name .. " timer"] = { -TIMER.w / 2, y, TIMER.w / 2, y + TIMER.h } end
    local function frame(spot, size) return RectAt(spot[1], spot[4], spot[5], size.w, size.h) end
    r.player = frame(FRAMES.Player, UNIT)
    r.pet = frame(FRAMES.Pet, SMALL)
    local target = frame(FRAMES.Target, UNIT)
    r.target = target
    local tot = Plan.TOT_SPOT -- on the target frame's corner named by relativePoint
    local cornerX = tot.relativePoint:find("LEFT") and target[1] or target[3]
    local cornerY = tot.relativePoint:find("TOP") and target[4] or target[2]
    r["target of target"] = RectAt(tot.point, cornerX + tot.x, cornerY + tot.y, SMALL.w, SMALL.h)
    local a = TARGET_AURAS
    local pictureLeft = (target[1] + target[3]) / 2 - a.picture.w / 2
    local pictureTop = (target[2] + target[4]) / 2 + a.picture.h / 2
    local aurasTop = pictureTop + a.startY + a.rows * a.size + (a.rows - 1) * a.spacing
    r["target auras"] = { pictureLeft + a.startX, target[4], pictureLeft + a.startX + a.rowWidth, aurasTop }
    local castTop = target[2] + TARGET_CAST.y
    r["target cast bar"] = { target[1] + TARGET_CAST.x, castTop - TARGET_CAST.h, target[1] + TARGET_CAST.x + TARGET_CAST.w, castTop }
    for _, side in ipairs({ -1, 1 }) do
        box(side < 0 and "LB+LT button" or "RB+RT button", side * 138, SPOTS.bottom.y - 50, 38, 38)
    end
    local W, H = 1365.33, 768
    r["quest tracker"] = { W / 2 - 260, H - 375 - 264, W / 2, H - 375 }
    return r
end

-- The two sub-menu wheels: centred on the sub-menu buttons, 175 across (the
-- mockup's ring; the game puts its eight buttons 60 out, FlyoutRadial.lua:28).
function Plan.Wheels()
    local y = SPOTS.bottom.y - 50
    return { { x = -138, y = y, r = 87.5 }, { x = 138, y = y, r = 87.5 } }
end

local function Anchor(spot)
    return { point = spot[1], relativeTo = spot[2], relativePoint = spot[3], x = spot[4], y = spot[5] }
end

local function Spot(point, relativePoint, x, y)
    return { point = point, relativeTo = UI, relativePoint = relativePoint, x = x, y = y }
end

-- Every piece of the template, in the order of the spec's table. A piece with no
-- `anchor` keeps its place and only gets settings. `moved` is true where the game
-- must be told the piece is no longer in its default position.
function Plan.Pieces(opts)
    local o = Fill(opts)
    local list = {}
    local function add(system, index, anchor, settings)
        list[#list + 1] = { system = system, index = index, anchor = anchor, settings = settings, moved = anchor and true or nil }
    end
    -- HeaderUnderneath 1 puts the map's title strip under the map (0.11.1 spec, 3); left
    -- out by Plan.Apply when the game has no such setting.
    add("Minimap", nil, Spot("BOTTOM", "BOTTOM", MAP.x, MAP.y), { Size = (MAP.size - 50) / 10, HeaderUnderneath = 1 })
    add("ChatFrame", nil, Spot("TOPRIGHT", "TOPRIGHT", -30, -40),
        { WidthHundreds = 4, WidthTensAndOnes = 30, HeightHundreds = 2, HeightTensAndOnes = 10 })
    -- Buffs and debuffs under the chat's last lines (0.11.1 spec, 4). The quest tracker
    -- flush with the right edge: it is 260 wide (probe), not the mockup's 218, and this
    -- keeps it clear of the RT bar until it holds a long list.
    add("AuraFrame", "BuffFrame", Spot("TOPRIGHT", "TOPRIGHT", -30, -292), nil)
    add("AuraFrame", "DebuffFrame", Spot("TOPRIGHT", "TOPRIGHT", -30, -330), nil)
    add("ObjectiveTracker", nil, Spot("TOPRIGHT", "TOPRIGHT", 0, -375), { Height = 0 })
    -- The XP bars along the top edge, centred, at 100% (0.11.1 spec, 1).
    add("StatusTrackingBar", "StatusTrackingBar1", Spot("TOP", "TOP", 0, XP_TOP_Y), { Size = 10 })
    add("StatusTrackingBar", "StatusTrackingBar2", Spot("TOP", "TOP", 0, XP_TOP_Y - XP_H), { Size = 10 })
    add("GamepadMainActionBar", nil, nil, { Compact = 0, ShowEmptyBars = 0, ShouldExpand = 0 })
    add("UnitFrame", "Player", Anchor(FRAMES.Player), nil)
    add("UnitFrame", "Pet", Anchor(FRAMES.Pet), nil)
    -- BuffsOnTop 1 (as the game's Gamepad preset has it): the target's auras grow up, away
    -- from the RT bar. Left out by Plan.Apply when the game has no such setting.
    add("UnitFrame", "Target", Anchor(FRAMES.Target), { BuffsOnTop = 1 })
    local visibility = { Ranged = o.ranged, MainHand = o.mainHand, OffHand = o.offHand }
    for _, name in ipairs({ "MainHand", "OffHand", "Ranged" }) do
        add("SwingTimer", name, Spot("BOTTOM", "BOTTOM", 0, TIMER.y[name]),
            { Scale = 3, Width = 0, Height = 0, Visibility = visibility[name] })
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
-- to is kept per character (0.11.1 spec, 2; 0.11.2): in the game's own
-- per-character saved file (PocketEssentialsCharDB, the TOC's
-- SavedVariablesPerCharacter line, as Blizzard's own addons do, e.g.
-- Blizzard_AuctionHouseUI/Blizzard_AuctionHouseUI.toc:4), at
-- PE.charDB.ctrlLayoutPrev = { name, layoutType, preset }, written when a
-- switch-on has really happened on that character. Core loads that table with
-- the account-wide one. No character name is needed: 0.11.1 keyed the entry by
-- UnitName("player") and GetRealmName(), and on the device the name never read
-- (the check waited for it forever). Two older entries are read once (Migrate):
-- opts.prev, the 0.11.0 file's single entry for the whole account, and
-- opts.prevs[<name>-<realm>], 0.11.1's, when this character's name can be read.
--
-- The name and realm are still read, for the debug log only (CharKey): which
-- part fails is logged once a session, so the cause can be found. Nothing waits
-- on them. UnitName (Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:
-- 2489-2503, secret when the unit's identity is restricted), GetRealmName
-- (ConnectionDocumentation.lua:69-75), UNKNOWNOBJECT ("Unknown", compared the
-- same way in Blizzard_RaidUI/Mainline/Blizzard_RaidUI.lua:706).
--
-- At each login, and at each switch-on, Settle runs once the game has handed
-- Edit Mode its layouts (EditModeManagerFrameMixin:IsInitialized,
-- Blizzard_EditMode/Shared/EditModeManager.lua:216-218, true once
-- UpdateLayoutInfo, line 1012, ran on EDIT_MODE_LAYOUTS_UPDATED, line 193): a
-- layout list read before that may be incomplete, and saving it could lose the
-- player's own layouts. Until then it listens for the next
-- PLAYER_ENTERING_WORLD and EDIT_MODE_LAYOUTS_UPDATED through the core's own
-- event list (PE:RegisterCoreEvent), because a module that is off hears none
-- of its own events; both are dropped as soon as Settle has run. While off,
-- this happens only when a layout is remembered for this character (or an
-- older entry is still to be read), so a player who never used the feature has
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
-- Said in chat when a login, not a tap, changed this character's layout: the reload
-- request itself only shows in the settings window, which is closed at login.
local CHAT_SWITCHED_ON = "This character now uses the controller layout. Open the settings and tap Reload now to finish."
local CHAT_SWITCHED_OFF = "This character's own screen layout is back. Open the settings and tap Reload now to finish."
local CHAT_UPDATED = "The controller layout was updated to the new arrangement (changes you made to it in Edit Mode are replaced). Open the settings and tap Reload now to finish."
-- Status lines while the login check waits (0.12.0 spec, "Getting it without taps"): no silent waiting.
local TEXT_WAIT_FIGHT = "Updating the layout after this fight."
local TEXT_WAIT_LAYOUTS = "Waiting for the game's layouts."
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

-- The value fn reads, or nil if it raises (a group this client does not have).
local function Optional(fn)
    local ok, v = pcall(fn)
    if ok then return v end
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
            -- BuffsOnTop (EditModeManagerConstantsDocumentation.lua:792) may be missing, its
            -- whole group too: Plan.Apply then leaves it out.
            UnitFrame = {
                BuffsOnTop = Optional(function() return Enum.EditModeUnitFrameSetting.BuffsOnTop end),
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

-- "<name>-<realm>" of the character playing, or nil and which part failed. For
-- the debug log and the one-time read of 0.11.1's entries only: nothing waits on it.
local function CharKey()
    if type(UnitName) ~= "function" or type(GetRealmName) ~= "function" then return nil, "no function" end
    local okName, name = pcall(UnitName, "player")
    local okRealm, realm = pcall(GetRealmName)
    if not okName or not okRealm then return nil, "error" end
    if issecretvalue and issecretvalue(name) then return nil, "name secret" end
    if issecretvalue and issecretvalue(realm) then return nil, "realm secret" end
    if type(name) ~= "string" or name == "" then return nil, "name empty" end
    if type(realm) ~= "string" or realm == "" then return nil, "realm empty" end
    if name == UNKNOWNOBJECT then return nil, "unknown name" end
    return name .. "-" .. realm
end

local nameLogged = false

-- Once a session, with the debug log on: whether the character's name can be
-- read, and if not, which part failed (0.11.1 never found it on the device).
local function LogNameOnce()
    if nameLogged or not PE.debugOn then return end
    nameLogged = true
    local key, why = CharKey()
    PE:Debug("ctrlLayout", key and "the character's name reads" or ("the character's name does not read: " .. tostring(why)))
end

-- This character's own saved table (Core: PE.charDB), or nil before it is loaded.
local function CharDB()
    local t = PE.charDB
    return type(t) == "table" and t or nil
end

-- This character's layout to go back to, or nil.
local function ThisPrev()
    local t = CharDB()
    local entry = t and t.ctrlLayoutPrev
    return type(entry) == "table" and entry or nil
end

-- Writes (or, with nil, removes) this character's entry.
local function SetThisPrev(entry)
    local t = CharDB()
    if t then t.ctrlLayoutPrev = entry end
end

local function HasLegacy()
    return type(mod.opts) == "table" and type(mod.opts.prev) == "table"
end

-- 0.11.1's entry for this character in the account-wide file (opts.prevs, by
-- name and realm) and its key, or nil (none, or the name cannot be read).
local function OldNamedPrev()
    local opts = mod.opts
    local prevs = type(opts) == "table" and opts.prevs
    if type(prevs) ~= "table" or next(prevs) == nil then return nil end
    local key = CharKey()
    local entry = key and prevs[key]
    if type(entry) == "table" then return entry, key end
    return nil
end

-- An older entry is still to be read for this character.
local function HasOldEntry()
    return HasLegacy() or OldNamedPrev() ~= nil
end

-- Reads the older entries once. 0.11.1's entry for this character becomes its
-- entry (and leaves the account-wide file). 0.11.0's single entry becomes it if
-- ours is active here; otherwise it is dropped.
local function Migrate()
    local named, key = OldNamedPrev()
    if named then
        mod.opts.prevs[key] = nil
        if not ThisPrev() then SetThisPrev(named) end
        if PE.debugOn then PE:Debug("ctrlLayout", "the 0.11.1 layout to go back to moved to this character's own file") end
    end
    if not HasLegacy() then return end
    local legacy = mod.opts.prev
    mod.opts.prev = false
    if ThisPrev() then return end
    local state = ReadState()
    local index = state and OursIndex(state)
    local kept = index ~= nil and state.active == index
    if kept then SetThisPrev(legacy) end
    if PE.debugOn then PE:Debug("ctrlLayout", "the 0.11.0 layout to go back to was " .. (kept and "kept for this character" or "dropped")) end
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

local pendingTap = false -- the Settle still to run was asked for by a tap on the switch
local atLogin = true     -- the module is being switched on by the login, not by a tap
local autoSwitch = false -- SwitchOn is running from a login check, not from a tap

-- Asks for Settle: now if it can, else at the next of those events, out of combat.
-- byTap: a tap on the switch asked for it (a refusal then switches the feature
-- back off, and a switch-off always asks for the reload).
local function Begin(byTap)
    pending = true
    if byTap then pendingTap = true end
    StartWaiting()
    PE:RunOutOfCombat("ctrlLayout:settle", Settle)
end

local TEXT_AUTO_FAILED = "This character could not be switched to the Pocket Essentials layout. It tries again at the next login."

-- After a tap: switches the feature back off after a refusal, once OnEnable has
-- returned. From a login check (autoSwitch) the switch is account-wide and other
-- characters may use the layout, so it stays on: the reason goes to the status
-- line and the next login tries again.
local function Refuse(text)
    if autoSwitch then
        Say(text or TEXT_AUTO_FAILED)
        if PE.debugOn then PE:Debug("ctrlLayout", "automatic switch-on refused; the switch stays on") end
        return
    end
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

---------------------------------------------------------------------------
-- Pieces placed with the bars (0.12.0): the two LB / RB targeting pictures and
-- the target of target. Out of a fight only, like the bars; their points are
-- read before the first change and put back when the bars are.
--
-- The targeting pictures are PageUnit's LeftShoulderBackground and
-- RightShoulderBackground textures (the friendly and hostile icons sit on them),
-- anchored to the main bar's anchor at -108 / +108, 42
-- (Blizzard_GamepadActionBars/MainActionBarFrame.xml:18-26). Moving the main bar to
-- its corner would take them along, so they are anchored where that anchor held them
-- (the main bar centred, 42 up): Plan.SHOULDERS, BOTTOMRIGHT at -108, 84 and BOTTOMLEFT
-- at 108, 84.
-- No game code re-anchors them (MainActionBarFrame.lua:631-649 only sets their
-- pictures and the pressed highlight, which is anchored on them).
--
-- The target of target is TargetFrame.totFrame, a secure button made by
-- TargetFrameMixin:CreateTargetofTarget (Blizzard_UnitFrame/Mainline/TargetFrame.lua:732-737)
-- from TargetofTargetFrameTemplate (Mainline/TargetFrame.xml:397-405: 120 by 49,
-- under the target frame's bottom right). It is no Edit Mode system and the game
-- does not re-anchor it for the target frame (only the focus frame's, lines
-- 1175-1215), so it is placed here: above the target frame, its left edges lined up,
-- the mirror of the pet above the player.
---------------------------------------------------------------------------

local EXTRAS = {
    { name = "LB targeting picture", get = function() return Child(Child(GamepadBar(), "PageUnit"), "LeftShoulderBackground") end,
      point = function() local s = Plan.SHOULDERS.left return s[1], UIParent, "BOTTOM", s[2], s[3] end },
    { name = "RB targeting picture", get = function() return Child(Child(GamepadBar(), "PageUnit"), "RightShoulderBackground") end,
      point = function() local s = Plan.SHOULDERS.right return s[1], UIParent, "BOTTOM", s[2], s[3] end },
    { name = "target of target", get = function() return Child(type(TargetFrame) == "table" and TargetFrame or nil, "totFrame") end,
      point = function() local t = Plan.TOT_SPOT return t.point, TargetFrame, t.relativePoint, t.x, t.y end },
}

local extraFound = {}   -- [region] = { { point, relativeTo, relativePoint, x, y }, ... } read before the first change
local extraPlaced = {}  -- regions placed by the addon, in order

-- A region's points, or nil when they cannot be read.
local function ReadPoints(f)
    if type(f.GetNumPoints) ~= "function" or type(f.GetPoint) ~= "function" then return nil end
    local ok, n = pcall(f.GetNumPoints, f)
    if not ok or type(n) ~= "number" then return nil end
    local points = {}
    for i = 1, n do
        local okPoint, point, relativeTo, relativePoint, x, y = pcall(f.GetPoint, f, i)
        if not okPoint or type(point) ~= "string" then return nil end
        points[i] = { point, relativeTo, relativePoint, x, y }
    end
    return points
end

local function PlaceExtras()
    for _, x in ipairs(EXTRAS) do
        local ok, f = pcall(x.get)
        if not ok or type(f) ~= "table" or type(f.ClearAllPoints) ~= "function" or type(f.SetPoint) ~= "function" then
            if PE.debugOn then PE:Debug("ctrlLayout", x.name .. " not placed: not found") end
        else
            local points = extraFound[f] or ReadPoints(f)
            if not points then
                if PE.debugOn then PE:Debug("ctrlLayout", x.name .. " not placed: its points cannot be read") end
            else
                if not extraFound[f] then
                    extraFound[f] = points
                    extraPlaced[#extraPlaced + 1] = f
                end
                local okMove, err = pcall(f.ClearAllPoints, f)
                if okMove then okMove, err = pcall(f.SetPoint, f, x.point()) end
                if not okMove then PE:LogError("ctrlLayout", "The " .. x.name .. " could not be placed: " .. tostring(err)) end
            end
        end
    end
end

local function RestoreExtras()
    for _, f in ipairs(extraPlaced) do
        local ok, err = PutBackPoints(f, extraFound[f])
        if not ok then PE:LogError("ctrlLayout", "A targeting picture or the target of target could not be put back: " .. tostring(err)) end
    end
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
    RestoreExtras()
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
    local spots = Plan.BarSpots()
    placed = true
    for _, b in ipairs(BAR_FRAMES) do
        local spot = spots[b.spot]
        Put(frames[b.spot], spot.x, spot.y, spot.s)
    end
    PlaceExtras()
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
    mod.opts.template = Plan.TEMPLATE
    if PE.debugOn then PE:Debug("ctrlLayout", "saved the Pocket Essentials layout at index " .. newIndex) end
    return true, true
end

local function SwitchOn()
    if not wanted then return end -- switched off again before this ran
    if EditModeOpen() then
        Refuse(TEXT_EDIT_MODE)
        return
    end
    if not CharDB() then
        Fail("This character's saved settings are not loaded")
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
        if not ThisPrev() then SetThisPrev({ preset = e.preset.Gamepad }) end
        SyncBars()
        mod:RefreshPanel()
        return
    end
    local current = state.current
    local prev = current and { name = current.name, layoutType = current.layoutType, preset = current.preset }
        or { preset = e.preset.Gamepad }
    if oursIndex then
        SetThisPrev(prev)
        local ok, err = pcall(state.api.SetActiveLayout, oursIndex)
        if not ok then
            SetThisPrev(nil)
            Fail("C_EditMode.SetActiveLayout failed: " .. tostring(err))
            return
        end
    else
        SetThisPrev(prev) -- before the write: switching off must undo even a half-done change
        local called, ok, wrote = pcall(AddOurs, state, e)
        if not called then
            -- Every game call in AddOurs is protected, so an error here came
            -- before anything was written.
            SetThisPrev(nil)
            Fail("Building the layout failed: " .. tostring(ok))
            return
        end
        if not ok then
            -- After a tap the switch-off that follows the refusal undoes a half-done
            -- change. From a login check the switch stays on: no entry, so the next
            -- login tries again.
            if not wrote or autoSwitch then SetThisPrev(nil) end
            return
        end
    end
    mod:RequestReload(RELOAD_REASON)
    if autoSwitch then PE:Print(CHAT_SWITCHED_ON) end
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
    Migrate()
    local prev = ThisPrev()
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
    SetThisPrev(nil)
    if PE.debugOn then PE:Debug("ctrlLayout", "switched off for this character" .. (changed and ", its own layout put back" or "")) end
    if changed or not atLogin then mod:RequestReload(RELOAD_REASON) end
    if changed and atLogin then PE:Print(CHAT_SWITCHED_OFF) end
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

-- Which pieces of Plan.Pieces each row rewrites: its own swing timer only (one
-- setup since 0.12.0: the stack's spots no longer depend on what is shown).
local function Timer(index) return function(p) return p.system == "SwingTimer" and p.index == index end end
local REWRITES = {
    ranged = Timer("Ranged"),
    mainHand = Timer("MainHand"),
    offHand = Timer("OffHand"),
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

-- OnChange of a row: rewrites its pieces in our layout.
local function LayoutRow(key)
    return function()
        RewritePieces(REWRITES[key], key)
    end
end

-- Rebuilds our layout from the template, in place (only ours: every other layout
-- is saved back as it was read). True if the game took it; a failure is logged.
local function Rebuild()
    local state, pos, e = ReadOurs()
    if not state then return false end
    local presets = CopyOfPresets()
    local base = presets and presets[e.preset.Gamepad + 1]
    if type(base) ~= "table" or base.layoutIndex ~= e.preset.Gamepad then
        PE:LogError("ctrlLayout", "The game's Gamepad preset could not be copied")
        return false
    end
    base.layoutIndex = nil
    state.saved[pos] = Plan.Build(base, mod.opts, e)
    local ok, err = SaveAll(state, state.saved)
    if not ok then
        PE:LogError("ctrlLayout", err)
        return false
    end
    mod.opts.template = Plan.TEMPLATE
    if PE.debugOn then PE:Debug("ctrlLayout", "the Pocket Essentials layout was rebuilt from the template") end
    return true
end

local function RunStartOver()
    if not wanted then return end
    if Rebuild() then mod:RequestReload(RELOAD_REASON) end
end

-- The saved template version (none saved: 0.11.x, version 1).
local function SavedTemplate()
    local v = mod.opts.template
    return type(v) == "number" and v or 1
end

-- At a login with ours active and built from an older template: rebuilt once from
-- the template (Start over's steps), the reload asked for, and said in chat. A tap on
-- the switch keeps an existing layout as it is (until the next login). A failure
-- keeps the old version saved, so the next login tries again.
local function UpdateTemplate(byTap)
    if byTap or SavedTemplate() >= Plan.TEMPLATE or not IsOursActive() then return end
    if not Rebuild() then return end
    mod:RequestReload(RELOAD_REASON)
    PE:Print(CHAT_UPDATED)
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

local VISIBILITY = { { value = 0, label = "Always" }, { value = 1, label = "In combat" }, { value = 2, label = "Hidden" } }

-- One setup (0.12.0 spec, "One setup"): the rows that made other arrangements are
-- gone; values older versions saved for them stay in the file, unused.
local OPTIONS = {
    { key = "ranged", label = "Ranged timer", choices = VISIBILITY, OnChange = LayoutRow("ranged") },
    { key = "mainHand", label = "Main Hand timer", choices = VISIBILITY, OnChange = LayoutRow("mainHand") },
    { key = "offHand", label = "Off Hand timer", choices = VISIBILITY, OnChange = LayoutRow("offHand") },
    { label = "Template", button = "Start over", action = function() StartOver() end },
}

-- This character's check (see the notes above Say). Runs out of combat; waits
-- (and is called again by the next PLAYER_ENTERING_WORLD or
-- EDIT_MODE_LAYOUTS_UPDATED) while Edit Mode's layouts are not known yet.
Settle = function()
    if not pending then
        StopWaiting()
        return
    end
    if not EditModeReady() then
        if PE.debugOn then PE:Debug("ctrlLayout", "waiting for Edit Mode's layouts") end
        return
    end
    if not CharDB() then
        if PE.debugOn then PE:Debug("ctrlLayout", "waiting for this character's saved settings") end
        return
    end
    LogNameOnce()
    local byTap = pendingTap
    pending, pendingTap = false, false
    StopWaiting()
    Migrate()
    if wanted then
        if ThisPrev() then
            SyncBars()
            mod:RefreshPanel()
        else
            autoSwitch = not byTap
            local ok, err = pcall(SwitchOn)
            autoSwitch = false
            if not ok then error(err, 0) end
        end
        if wanted then UpdateTemplate(byTap) end -- a refused switch-on may have switched it off
        -- Option changes not yet written when the feature went off (after SwitchOn, so ours exists).
        if #pendingRewrites > 0 then PE:RunOutOfCombat("ctrlLayout:rewrite", RunRewrites) end
    elseif ThisPrev() then
        SwitchOff(not byTap)
    end
end

-- The switch is on, but at PLAYER_LOGIN the game did not report its Gamepad UI yet,
-- so Core found the feature blocked and did not start it (a character with no
-- layout remembered is blocked without the Gamepad UI). One more look at the next
-- PLAYER_ENTERING_WORLD, through the core's event list (an off module hears none
-- of its own), then never again this session.
local LATE_KEY = "ctrlLayout:gamepadUI"

local function WatchLateGamepadUI()
    PE:RegisterCoreEvent("PLAYER_ENTERING_WORLD", LATE_KEY, PE:Wrap("ctrlLayout", function()
        PE:UnregisterCoreEvent("PLAYER_ENTERING_WORLD", LATE_KEY)
        if mod:IsEnabled() or not PE:IsModuleSavedOn("ctrlLayout") then return end
        if not PE:GamepadUI() then
            if PE.debugOn then PE:Debug("ctrlLayout", "the Gamepad UI still reads off; not started") end
            return
        end
        if PE.debugOn then PE:Debug("ctrlLayout", "the Gamepad UI reads on now; starting") end
        atLogin = true -- a login, not a tap: a refused switch-on leaves the switch on
        PE:SetModuleEnabled("ctrlLayout", true)
        atLogin = false
    end))
end

local defaults = DeepCopy(Plan.DEFAULTS)
defaults.prev = false -- the 0.11.0 file's single layout to go back to; read once, then false
-- (opts.prevs, 0.11.1's entries by character name, is only read: Migrate. Each
-- character's entry now lives in its own saved file, PE.charDB.ctrlLayoutPrev.)

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
        -- must not stop it. The same while an older entry for this character is still unread.
        if mod and type(mod.opts) == "table" and (ThisPrev() or HasOldEntry()) then return nil end
        if not PE:GamepadUI() then return TEXT_NEEDS_GAMEPAD end
        if not Api() or not Presets() or not GamepadBar() then return TEXT_NO_LAYOUTS end
        return nil
    end,

    -- Reads only.
    status = function(m)
        local waitText
        if pending then
            if PE:InCombat() then waitText = TEXT_WAIT_FIGHT elseif not EditModeReady() then waitText = TEXT_WAIT_LAYOUTS end
        end
        if not m:IsEnabled() then
            local lines = {}
            if note then lines[#lines + 1] = note end
            if waitText then lines[#lines + 1] = waitText end
            lines[#lines + 1] = TEXT_OFF
            return #lines == 1 and TEXT_OFF or lines
        end
        if note then return note end
        if waitText then return waitText end
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
        if type(self.opts) ~= "table" then return end
        if PE:IsModuleSavedOn("ctrlLayout") then
            -- Blocked at this login only because the game does not report its Gamepad UI
            -- yet: one more try at the next PLAYER_ENTERING_WORLD.
            if not ThisPrev() and not HasOldEntry() and not PE:GamepadUI() then WatchLateGamepadUI() end
            return
        end
        if not ThisPrev() and not HasOldEntry() then return end -- nothing remembered for this character
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
            -- A login whose layout was built from an older template: Settle rebuilds it.
            if atLogin and SavedTemplate() < Plan.TEMPLATE then Begin(false) end
        else
            -- This character's login check, or a switch-on: Settle, once the character's
            -- name and Edit Mode's layouts are known.
            Begin(not atLogin)
        end
    end,

    OnDisable = function(self)
        wanted = false
        rowNote = nil
        RestoreBars() -- first: bars placed by any path are always put back
        if not ThisPrev() and not HasOldEntry() then return end -- nothing was changed for this character
        PE:RunOutOfCombat("ctrlLayout:off", function() SwitchOff(false) end)
    end,
})

-- From here on a switch-on is a tap, except the late one below.
PE:OnLogin(function() atLogin = false end)
