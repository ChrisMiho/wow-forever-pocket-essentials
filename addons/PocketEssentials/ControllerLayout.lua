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
-- TIMER, UNIT, BAR below); every spot is the mockup's, moved only where a real
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
--
-- 0.13.0 (spec 2026-11-23-controller-layout-0.13.0-face-bars.md): Pocket Essentials draws
-- its own spell pictures (the "face", FaceBars.lua) and the game's four bars sit invisible
-- under them. Split the way the controller is held: the d-pad halves of all four bars left
-- of the map, the face-button halves right of it, in two 2 by 2 grids.
-- The real bars sit under the grids at 90%, two a side; the frames moved down beside the
-- grids, so frames, spells and map share one low band and the middle of the screen is free.
-- The quest tracker moved top left, where the game's controller hint box was; that box is
-- hidden while the layout is placed (the game's own setting, put back when off).
-- This file places everything; FaceBars.lua draws the pictures and fades the real bars.
-- It is started after a placement and stopped before a put-back (see StartFace).
--
-- 0.14.0 (spec 2026-11-23-controller-layout-0.14.0-console.md): one panel a side, the
-- triggers swap it. At rest only the main bar shows: its d-pad diamond inner-left of the
-- map, its face diamond inner-right. Holding a trigger opens that trigger's bar into two
-- diamonds on its own side (LT: outer-left and inner-left; RT: inner-right and
-- outer-right) and the main diamond left on the other side goes quiet; both triggers
-- show the LT+RT bar in the two inner spots (Plan.FaceStates). The pictures grew to 42
-- (Plan.FACE). The real bars sit at 60% under the two inner diamonds, two a side; the
-- frames moved out past the outer diamonds (FRAME_X 395) and the LB / RB targeting
-- pictures in beside the map (Plan.SHOULDERS).
--
-- 0.16.0 (spec 2026-11-24-playing-screen-layout-design.md, "0.16.0: the arrangement"): the
-- playing screen. The map drops to the bottom edge, its place-name strip where the swing
-- timers were, and the timers go above the round map. The chat moves bottom left, above the
-- PE button and the pet frame; the quest tracker top right, the buffs beside it under the XP
-- bars; the tooltip (a new piece) above the target of target. The LB / RB targeting pictures
-- move off the "LB + LT" / "RB + RT" prompts. Plan.Rects also lists the prompts, the tooltip,
-- the game's hint box (while the "Controls reminder" option shows it) and the place-name
-- strip with its two buttons (while "Map buttons" shows them), so the overlap check covers
-- every state.
--
-- 0.17.0 (spec 2026-11-24-0.17.0-slim-bars.md): the slim bars. This file holds their numbers
-- (Plan.SLIM, Plan.SlimRects), their switch (opts.slim, the row "Slim bars", Off by default,
-- counts from the next reload) and the tooltip's corner spot that goes with them; SlimBars.lua
-- (PE.SlimBars) draws them and makes the game's four unit frames invisible. It is started
-- when the layout is placed and stopped when it is put back (Snap.SlimCall), and never
-- called at all in a session that began with the switch Off.
--
-- 0.18.0 (spec 2026-11-24-0.18.0-arrange.md): arrange it yourself. This file holds the list
-- of pieces that can be moved (Plan.ARRANGE), adds each one's saved offset inside the plan
-- (Plan.Moved), and has the switch (opts.arrange, Off by default; until 0.19.0 a second one,
-- opts.arrangeWheel, for the spell wheels) and the "Arrange the screen" row. Arrange.lua (PE.Arrange) is the window and its
-- rules; it is never called in a session that began with the switch Off, and Plan.session
-- is never set then, so every number of the plan is the built-in one.
--
-- 0.20.0 (spec 2026-11-25-0.20.0-after-first-sitting.md, 2): the arrangement of the first
-- device sitting is the built-in one (Plan.BASE_2, added by Plan.Moved wherever a saved
-- offset is), and offsets saved by 0.18.0 and 0.19.0 are carried over once (Plan.MigrateBase,
-- Snap.Carry) so that nobody's screen moves twice.
--
-- 0.19.0 (spec 2026-11-25-0.19.0-square-map.md): the square map. This file holds its numbers
-- (MAP.square, Plan.MAP_SQUARE, Plan.MapBox) and its switch (opts.mapLook, the row "Map look",
-- Round by default: with Round every number, rectangle and written layout is 0.18.0's).
-- MapLook.lua (PE.MapLook) changes the map itself: the square mask, the edge, the words inside
-- it. It is called where the ring is placed and put back (PlaceRing, RestoreRing).

local type, pairs, ipairs = type, pairs, ipairs
local sort = table.sort

local Plan = {}
PE.LayoutPlan = Plan

Plan.NAME = "Pocket Essentials"

-- 0.12.0 (spec 2026-11-23-controller-layout-0.12.0-mockup-setup.md): one setup,
-- the mockup's "Face bars (one setup)" with the game's real bars. The only options left are the three
-- swing timers' visibility. Every spot below is in UI units at UI scale 1
-- (1365 by 768): x from the screen's centre, y ("up") from its bottom edge.
-- How each number follows from the Camelot source is in
-- docs/superpowers/plans/2026-11-23-controller-layout-0.12.0.md.

Plan.DEFAULTS = {
    ranged = 1,         -- timer visibility: 0 Always, 1 In combat, 2 Hidden
    mainHand = 1,
    offHand = 2,
    hints = 0,          -- 0.16.0: the game's hint box ("Controls reminder"): 0 Off, 1 On
    mapButtons = 0,     -- 0.16.0: the magnifier and calendar beside the place name: 0 Hidden, 1 Shown
    -- 0.17.0: the slim bars (SlimBars.lua): 0 Off, 1 On. Off, the game's unit frames and the
    -- tooltip are as 0.16.4 has them and SlimBars.lua is never called.
    slim = 0,
    -- 0.20.0: the names on the slim bars: 1 Whole name (first name and surname), 0 First name.
    slimNames = 1,
    -- 0.18.0: arrange it yourself (Arrange.lua): 0 Off, 1 On. Off, no saved offset is added
    -- anywhere and Arrange.lua is never called. (0.20.0: the second switch, arrangeWheel, is
    -- gone: the spell wheels are a piece like the others. See Snap.Carry for a saved value.)
    arrange = 0,
    -- 0.19.0: the map's look: 0 Round (as 0.18.0 has it), 1 Square, bigger (MapLook.lua).
    mapLook = 0,
}
-- 0.20.0: option keys of rows that are gone; a value an older version saved is removed at
-- load (OnLoad). The seven "Part: ..." rows: 0.16.2's testing rows that left a part of the
-- layout out, to find the part that made the game refuse its controller actions (the chat's
-- box: docs/superpowers/plans/2026-11-24-blocked-action-0.16.1.md), and 0.16.4's row for a
-- hook on the triggers that never ran on a device. Every part is always placed now. If
-- refused actions come back, docs/ARCHITECTURE.md ("A refusal's call stack...") has the method.
Plan.GONE = { "tHints", "tChat", "tMap", "tBars", "tExtras", "tFace", "tHook" }

-- The template's version, saved with our layout whenever it is built
-- (opts.template). A login that finds an older one rebuilds our layout once.
-- 1: 0.11.x (no number saved). 2: 0.12.0, the mockup's one setup. 3: 0.13.0, the
-- face bars (frames and the quest tracker moved). 4: 0.14.0, the console (frames moved
-- out past the outer diamonds). 5: 0.16.0, the playing screen.
Plan.TEMPLATE = 5

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
local SCREEN_W, SCREEN_H = 1365.33, 768

-- The map: Edit Mode Size 2 (70%; the stored Size counts in steps of 10% from 50%),
-- its title strip underneath. With the strip underneath, the Forever map code puts
-- the round map's frame 30 up and 10 right of the map's own bottom
-- (Blizzard_Minimap/Camelot/Minimap.lua:72-73), scaled to 70%: a 253 frame (probe,
-- 2026-11-23) holding the 198 round map at its centre (Mainline/Minimap.xml:60-62).
-- 0.16.0: at the screen's bottom edge (y 0), so the strip sits 8 to 31 up, where the swing
-- timers were, and the round map 49 to 188 up. 6 left of the centre (until 0.15.0: 10, the
-- round map centred): with the map buttons shown the magnifier then ends at x -103, the inner
-- left diamond's edge at every Spell panel size (see STRIP_OUT); the round map is 4 right of
-- the centre.
local MAP = { size = 70, x = -6, y = 0, frame = 253, round = 198, frameUp = 30, frameRight = 10 }
-- The title strip (zone, clock): 152 by 23, 8 up and 1 left of the map's bottom
-- (Camelot/MinimapZoneTextButton.xml:9, Camelot/Minimap.lua:75-76).
local STRIP = { w = 152, h = 23, up = 8, x = -1 }
-- 0.16.0: the two buttons beside it. The magnifier: a 17 wide holder whose right edge is the
-- strip's left (Mainline/Minimap.xml:25-31, the file Camelot loads, Blizzard_Minimap.toc), the
-- 23 by 23 button centred on it (Mainline/Minimap.xml:39-41, Camelot/MinimapTrackingButton.xml:11):
-- 20 out past the strip's left edge. The calendar: 23 by 23, its left edge 4 inside the strip's
-- right (Camelot/GameTimeFrameTemplate.xml:8-10): 19 out past the right edge. Both 23 high, level
-- with the strip.
local STRIP_OUT = { left = 20, right = 19 }
-- The strip's width without and with its two buttons ("Map buttons" Hidden / Shown).
Plan.STRIP_W = { [0] = STRIP.w, [1] = STRIP.w + STRIP_OUT.left + STRIP_OUT.right }

-- 0.19.0, the square map (spec 2026-11-25-0.19.0-square-map.md, "Size and spot"): Edit Mode
-- Size 5 (100%), the map 198 across (Mainline/Minimap.xml:60) with a 1 unit edge of ours all
-- round, so 200; its edge box centred on the screen's middle, its bottom 4 up: x -100 to 100,
-- y 4 to 204. The strip stays underneath (HeaderUnderneath 1) and is hidden by MapLook.lua.
--
-- How the spot written into the layout follows. With the strip underneath the game puts the
-- map's frame (253, the 198 map at its centre) 10 right and 30 up of the spot. Neither number
-- grows with Size: SetHeaderUnderneath divides both by the frame's own scale and the frame
-- multiplies them back (Blizzard_Minimap/Camelot/Minimap.lua:70-73), which is why MAP has them
-- unscaled for 70% too.
--   x: the map's centre is x + 10 (frameRight). Wanted 0, so x = -10.
--   y: at 100% the map's bottom is y + 30 + (253 - 198) / 2 = y + 57.5. Wanted 5 (the edge
--      box's bottom, 4, plus the edge, 1), which asks for y = -52.5. The game does not allow
--      that: every Edit Mode piece is held wholly on the screen (clampedToScreen on
--      EditModeSystemTemplate, Blizzard_EditMode/Shared/EditModeSystemTemplates.xml:4; the
--      room it is given is its selection box, which covers the whole piece: the same file,
--      line 113, and EditModeSystemTemplates.lua:174-185), and the map's piece starts at the
--      spot written here, so a spot under the screen's edge is pushed back up to it. So y
--      stays 0, the lowest spot there is, and MapLook.lua lowers the map's frame inside its
--      piece by the rest (57.5 - 5 = 52.5 at 100%), worked out there from the frame's real
--      size and scale, so the map's bottom lands 5 up whatever they are.
MAP.square = { size = 100, x = -MAP.frameRight, y = 0 }
-- The square's own numbers: its Edit Mode size in percent, the edge's width, the edge box's
-- bottom above the screen's (so the map's bottom is bottom + edge), and what moves with it:
--   timersUp      the three swing timers, 14 up. Round has the lowest one's bottom at 194; the
--                 square's edge box ends at 204 and the timer sits 4 over it: 208 = 194 + 14.
--                 Across they stay where they are (centred on x 4).
--   shouldersOut  the LB and RB targeting pictures, 20 further out each, before a saved offset
--                 is added: a picture moved in beside the round map (94 in and 56 down, the
--                 arrangement of the 2026-11-25 sitting) then ends 4 short of the square
--                 (-140 to -104 against -100) instead of 16 inside it.
Plan.MAP_SQUARE = { size = MAP.square.size, edge = 1, bottom = 4, timersUp = 14, shouldersOut = 20 }
-- Spell panel sizes at which a spell panel reaches the square map: none. The inner panels'
-- inner edge is at 103 at every size (INNER_EDGE below), 3 clear of the edge box.
Plan.SQUARE_TIGHT_SIZES = {}
-- The map look as the module last placed it (1 Square; nil Round), for the callers that
-- pass no options (the targeting pictures' spots). Set by Snap.View.
Plan.look = nil

-- The map look: 1 Square, 0 Round. v: an options table decides for itself (mapLook 1 is
-- Square, anything else Round); any other v (a Spell panel size, nil) means the session's.
function Plan.MapLook(v)
    if type(v) == "table" then return v.mapLook == 1 and 1 or 0 end
    return Plan.look == 1 and 1 or 0
end

-- The map's numbers for that look: { size, x, y } (the Edit Mode size in percent and the
-- spot written into the layout). Every reader of the three goes through here, except the
-- swing timers, which keep the round map's spot and are only lifted (see Timers).
function Plan.MapOf(v)
    return Plan.MapLook(v) == 1 and MAP.square or MAP
end

-- The map's box at its built-in spot, { left, bottom, right, top } in UI units from the
-- screen's bottom centre: for Square the edge box (the map and its 1 unit edge), for Round
-- the round map. A saved offset is not added here (Plan.Rects does that).
function Plan.MapBox(v)
    local m = Plan.MapOf(v)
    local cx = m.x + MAP.frameRight
    if m == MAP.square then
        local q = Plan.MAP_SQUARE
        local half = MAP.round * m.size / 100 / 2 + q.edge
        return { cx - half, m.y + q.bottom, cx + half, m.y + q.bottom + 2 * half }
    end
    local cy = m.y + MAP.frameUp + MAP.frame * m.size / 100 / 2
    local round = MAP.round * m.size / 100
    return { cx - round / 2, cy - round / 2, cx + round / 2, cy + round / 2 }
end

-- Swing timers: Scale 3 (80%), Width 0 (213), Height 0 (15): 170.4 by 12 each
-- (Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:2784-2804, settings at
-- EditModeSettingDisplayInfo.lua:777-830). Edit Mode places a frame's spot in UI
-- units whatever its scale (EditModeSystemTemplates.lua:373-375). 0.16.0: stacked
-- directly above the round map and centred on it, Main Hand lowest, 6 over the round
-- map's top (187.85, rounded up to 194) and 2 between: 194, 208 and 222 up.
local TIMER = { w = 213 * 0.8, h = 15 * 0.8, over = 6, gap = 2, order = { "MainHand", "OffHand", "Ranged" } }

-- The unit frames: player and target 232 by 100
-- (Blizzard_UnitFrame/Mainline/PlayerFrame.xml:14), pet and target of target 120 by
-- 49 (probe; TargetofTargetFrameTemplate, Mainline/TargetFrame.xml:398). Since 0.14.0
-- they sit out past the outer diamonds, their inner edges at x -395 and +395 (the outer
-- diamonds end at -383 and +383).
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
--     left (TargetFrame.lua:830-852, from TargetOfTargetMixin:Update, line 914). With the
--     auras on top it never hangs under the aura rows (TargetFrame.lua:561-568).
local TARGET_AURAS = { picture = { w = 192, h = 67 }, startX = 5, startY = -6, rowWidth = 122, rows = 2, size = 21, spacing = 3 }
local TARGET_CAST = { x = 123, y = -46, w = 150, h = 10 }

-- 0.14.0: player and target 56 up, out past the outer diamonds (x -395 / +395). The
-- target's cast bar, with the target of target shown, then takes 518 to 668 across and 0
-- to 10 up: on screen (the edge is 682.7), in the free corner right of the outer diamond.
-- The player side is the mirror. The
-- pet and the target of target sit above the target's two aura rows (25 over the frames'
-- tops), the pet right-aligned and the target of target left-aligned with the frames'
-- inner edges. 0.15.0: at a Spell panel size whose outer diamonds pass 383 (110% and
-- 120%) the frames rise instead of moving out (see Geometry).
local FRAME_X = 395
local FRAME_Y = 56
local SMALL_GAP = 25 -- the pet and the target of target over the frames' tops

-- The target of target, placed by the module on the target frame (see EXTRAS).
Plan.TOT_SPOT = { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", x = 0, y = SMALL_GAP }
-- The game's "LB + LT" / "RB + RT" prompts under the two sub-menu buttons: 72 by 24, centred
-- 138 either side of the centre and 80 under the bottom anchor (238 up), so 158 up
-- (Blizzard_GamepadActionBars/MainActionBarFrame.xml:119-135): 102 to 174 either side, 146 to
-- 170 up. Not moved by the addon.
local PROMPT = { x = 138, y = 238 - 80, w = 72, h = 24 }
-- The two LB / RB targeting pictures, placed by the module on UIParent's bottom (see EXTRAS).
-- 0.16.0: off the prompts they covered in 0.14.0 and 0.15.0 (76 to 112, 128 to 160 up), on the
-- prompts' outer sides, 4 clear of them: 178 to 214 either side. 155 to 187 up, level with the
-- prompts' top half: centred on the prompts (142 up) they would reach 13 into the game's own
-- bars at full size (FULL_SPOTS, up to 155), which show while our pictures are off.
Plan.SHOULDERS = { left = { "BOTTOMRIGHT", -178, 155 }, right = { "BOTTOMLEFT", 178, 155 } }
-- Their size: 36 by 32, as measured on the device photos (the pictures use their atlas
-- size, gamepad-targeting-left/right-shoulder-bg, MainActionBarFrame.xml:18-26; the atlas
-- itself is not in this source).
local SHOULDER = { w = 36, h = 32 }

-- A bar that does not grow: 208 by 68 (Blizzard_GamepadActionBars/ActionBarStyles.lua:172;
-- the template switches growing off, ShouldExpand 0).
local BAR = { w = 208, h = 68 }

-- 0.14.0: our own spell pictures. A picture is 42 across (0.13.0: 28, too small to read
-- on the device); a diamond puts its four 46 left / right and 28 up / down of its
-- centre, so a diamond is 134 by 98. These are the 100% numbers; Plan.Face(size) gives
-- them at a Spell panel size.
local FACE = { button = 42, dx = 46, dy = 28 }
Plan.FACE = { button = FACE.button, dx = FACE.dx, dy = FACE.dy }

-- The four spots a diamond can be drawn at (Plan.FaceSpots): their centres, in UI units
-- from the screen's bottom centre. At 100% the inner ones span 103 to 237 either side of
-- the centre and 17 to 115 up: clear of the title strip (0.16.0: -83 to 69, 8 to 31 up;
-- -103 to 88 with the map buttons) and the round map (-65 to 73, 49 to 188 up). The outer
-- ones 249 to 383, 12 apart from the inner ones and 12 short of the frames (FRAME_X).
local INNER_EDGE = 103 -- the inner diamonds' inner edge, at every size
local RING_GAP = 12    -- between an inner and an outer diamond, and an outer one and the frames
local FACE_Y = 66      -- every diamond's centre, at every size
Plan.FACE_Y = FACE_Y

-- Which bar half is drawn at which spot for each state of the triggers (spec, "The new
-- arrangement"). The d-pad half always left of its own face half, the way the controller
-- is held; quiet halves are drawn see-through (FaceBars.lua). Halves not listed hide.
local FACE_STATES = {
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

-- The game's four bars, whole and invisible under the two inner diamonds, at 60% (124.8
-- by 40.8 each) at 100%: the main and LT bars under the left one, RT and LT+RT under the
-- right one, centred on it (x -170 / +170), one above the other (87 and 45 up; the
-- diamond spans 17 to 115). At another Spell panel size s they are at 60% times s, 21s
-- above and under the diamond's centre (Plan.BarSpots). Put divides the spot by the
-- scale, since a frame's offsets count in its own scale. The bottom anchor carries the
-- two sub-menu buttons (at -138 / +138, -50 from it:
-- Blizzard_GamepadActionBars/MainActionBarFrame.xml:94-112), so they sit 138 either side
-- of the centre, 188 up.
local REAL_BAR_SCALE = 0.6
local REAL_BAR_STEP = 21 -- each bar's centre above or under the diamond's, at 100%
local SPOTS = {
    bottom = { x = 0, y = 238, s = 1 },                -- sub-menu buttons at (±138, 188)
}
-- Which face group each real bar spot is.
local SPOT_FACE = { top = "main", left = "lt", right = "rt", both = "both" }

-- 0.15.0: the four bars when our pictures are off (FaceBars.lua could not make them, or
-- its safety net turned them off): the game's bars show again, so at full size (208 by
-- 68), two a side, 8 apart: 116 to 324 either side of the centre, 11 to 79 and 87 to 155
-- up. Clear of the LB / RB targeting pictures (0.16.0: 155 up and higher), the timers, the
-- map, the sub-menu buttons (169 up) and the frames (395); only the diamonds, hidden then,
-- share the place, and the game's own "LB + LT" / "RB + RT" prompts (146 to 170 up, see
-- PROMPT) reach 9 into the top two.
local FULL_SPOTS = {
    top = { x = -220, y = 121, s = 1 },
    left = { x = -220, y = 45, s = 1 },
    right = { x = 220, y = 121, s = 1 },
    both = { x = 220, y = 45, s = 1 },
    bottom = SPOTS.bottom,
}

-- Pocket Essentials' own round button. 0.16.0: its default spot while the layout is placed
-- (Plan.HubSpot): BOTTOMLEFT, 10 in, its bottom 6 over the player frame's top, left of the
-- pet frame (the corner itself is inside the player frame's rectangle). The size presets of
-- UI.lua:22-24 are 56, 60 and 72 px on a 720 px screen, 768 / 720 UI units each; the
-- largest one is used.
local HUB = { x = 10, over = 6, size = 72 * 768 / 720 }

-- The quest tracker. 0.16.0: top right, TOPRIGHT -5, -5 (until 0.15.0 top left, where the
-- game's controller hint box is). With Height 0 the tracker is 400 tall (the Edit Mode
-- setting's least, EditModeSettingDisplayInfo.lua:609-618, and
-- Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerContainer.lua:206-217): 363 to 763 up.
-- 260 wide (probe).
local TRACKER = { x = -5, y = -5, w = 260, h = 400 }

-- The game's controller hint box ("Controls reminder", shown only while opts.hints is 1):
-- TOPLEFT 5, -5 (Blizzard_Gamepad/UI/PersistentInputLegend/GamepadPersistentInputLegend.xml:40-42),
-- taken at its background's size, 200 by 100 (same file, line 5; the game sizes it to what it
-- lists, GamepadPersistentInputLegend.lua:119-123).
local HINTS = { x = 5, y = -5, w = 200, h = 100 }

-- The options with every missing or unusable value replaced by its default.
-- Values saved by older versions for rows that are gone are ignored.
local function Fill(opts)
    local out = {}
    opts = type(opts) == "table" and opts or {}
    for k, default in pairs(Plan.DEFAULTS) do
        local v = opts[k]
        local onOff = k == "hints" or k == "mapButtons" or k:sub(1, 4) == "slim" or k:sub(1, 7) == "arrange"
            or k == "mapLook"
        if v == 0 or v == 1 or (v == 2 and not onOff) then out[k] = v else out[k] = default end
    end
    return out
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end

-- 0.18.0 (spec 2026-11-24-0.18.0-arrange.md): the pieces that can be arranged, in the order
-- the Arrange screen lists them. On tables, not locals (this file is at Lua's limit of 200).
--   key    the name its offset is saved under
--   label  the name on screen
--   kind   "apply": a piece of the Edit Mode layout, moved by rewriting the layout and a
--          reload (its offset is saved with the options, opts.offsets); "live": placed by the
--          addon, moved at once (its offset is saved per character)
--   twin   the key of its mirror on the other side of the screen; pair: the pair's name (the
--          left one's key)
--   rects  the rectangles of Plan.Rects that move with it, the first one its main one
--   when   listed only then: "slim" (Slim bars On), "noslim" (Off),
--          "face" (our spell pictures show: with them off nothing is drawn at the panels' spots)
--   axis   "y": moves up and down only
--   note   a line the Arrange window shows while the piece is picked
Plan.ARRANGE = {
    { key = "map", label = "Map", kind = "apply", rects = { "map", "title strip" } },
    { key = "swing timers", label = "Swing timers", kind = "apply", rects = { "MainHand timer", "OffHand timer", "Ranged timer" } },
    { key = "XP bars", label = "XP bars", kind = "apply", rects = { "XP bars" } },
    { key = "chat", label = "Chat", kind = "apply", rects = { "chat" } },
    { key = "quest tracker", label = "Quest list", kind = "apply", rects = { "quest tracker" } },
    { key = "buffs and debuffs", label = "Buffs and debuffs", kind = "apply", rects = { "buffs and debuffs" } },
    { key = "tooltip", label = "Tooltip", kind = "apply", rects = { "tooltip" } },
    { key = "player", label = "Player and pet frames", kind = "apply", twin = "target", pair = "player", when = "noslim",
      rects = { "player", "pet" } },
    { key = "target", label = "Target frames", kind = "apply", twin = "player", pair = "player", when = "noslim",
      rects = { "target", "target of target", "target auras", "target cast bar" } },
    { key = "inner left diamond", when = "face", label = "Inner spell panel, left", kind = "live", twin = "inner right diamond",
      pair = "inner left diamond", rects = { "inner left diamond" } },
    { key = "inner right diamond", when = "face", label = "Inner spell panel, right", kind = "live", twin = "inner left diamond",
      pair = "inner left diamond", rects = { "inner right diamond" } },
    { key = "outer left diamond", when = "face", label = "Outer spell panel, left", kind = "live", twin = "outer right diamond",
      pair = "outer left diamond", rects = { "outer left diamond" } },
    { key = "outer right diamond", when = "face", label = "Outer spell panel, right", kind = "live", twin = "outer left diamond",
      pair = "outer left diamond", rects = { "outer right diamond" } },
    { key = "LB targeting picture", label = "LB targeting picture", kind = "live", twin = "RB targeting picture",
      pair = "LB targeting picture", rects = { "LB targeting picture" } },
    { key = "RB targeting picture", label = "RB targeting picture", kind = "live", twin = "LB targeting picture",
      pair = "LB targeting picture", rects = { "RB targeting picture" } },
    { key = "player bar", label = "Slim bars, you and pet", kind = "live", twin = "target bar", pair = "player bar", when = "slim",
      rects = { "player bar", "pet bar", "pet boxes room" } },
    { key = "target bar", label = "Slim bars, target", kind = "live", twin = "player bar", pair = "player bar", when = "slim",
      rects = { "target bar", "cast bar", "target of target bar", "target boxes room" } },
    -- Both sub-menu buttons, their prompts and where both wheels open hang on one frame of
    -- the game's (PageUnit.BottomCenteredAnchor: Blizzard_GamepadActionBars/MainActionBarFrame.xml:94-135,
    -- FlyoutRadial.lua:218-220), which the layout already places: so one piece, and up and
    -- down only (a sideways move would push both sides the same way). 0.20.0: always listed
    -- (until 0.19.0 behind a switch of its own, "Arrange: spell wheels"). With no offset saved
    -- the bottom anchor is placed exactly as the layout always placed it (BarSpots).
    { key = "spell wheels", label = "Spell wheels and their buttons", kind = "live", axis = "y",
      note = "Up and down only. Both sides move together.",
      rects = { "LB+LT button", "LB+LT prompt", "RB+RT button", "RB+RT prompt" } },
}
Plan.ARRANGE_BY = {}
for i = 1, #Plan.ARRANGE do Plan.ARRANGE_BY[Plan.ARRANGE[i].key] = Plan.ARRANGE[i] end
-- A saved offset further than this either way is not believed.
Plan.ARRANGE_LIMIT = 1500
-- The offsets of the session: set by the module, once, when the session began with
-- "Arrange it yourself" On ({ arrange = 1, offsets, charOffsets }); nil
-- otherwise, and then only the built-in amounts (Plan.BASE_2) are added.
Plan.session = nil

-- 0.20.0: the built-in arrangement, number 2 (spec 2026-11-25-0.20.0-after-first-sitting.md,
-- 2): what was arranged at the first device sitting of 0.18.0 (the saved file of
-- 2026-11-25, its "arrange: apply:" and "arrange: offset:" lines), as amounts { x, y } added
-- to the spots worked out in this file (arrangement 1, up to 0.19.0). They are added in one
-- place, Plan.Moved, where a saved offset is added too, so every reader of the plan sees
-- them and the twins stay exact mirrors (equal up, opposite across). The map is not here:
-- its saved "0, -2" would put it under the screen's edge, where the game does not let an
-- Edit Mode piece go (see MAP.square above).
--
-- Where every piece ends up on screen, who places it, and the areas kept free are written
-- down in docs/SCREEN-MAP.md (its numbers are what Plan.Rects returns). A change to a spot,
-- a size or the list of pieces in this file changes that page in the same commit.
Plan.BASE_2 = {
    ["inner left diamond"] = { 0, -16 }, ["inner right diamond"] = { 0, -16 },
    ["outer left diamond"] = { 0, -16 }, ["outer right diamond"] = { 0, -16 },
    ["LB targeting picture"] = { 94, -56 }, ["RB targeting picture"] = { -94, -56 },
    ["player bar"] = { -18, -16 }, ["target bar"] = { 18, -16 },
    ["buffs and debuffs"] = { 0, 4 },
}
-- The number saved offsets are counted from: saved as opts.arrangeBase (the Edit Mode
-- pieces') and ctrlArrange.base (each character's live pieces'); none saved means 1.
Plan.ARRANGEMENT = 2

-- A piece's built-in amount: x, y (0, 0 for a piece that has none).
function Plan.Base(key)
    local b = Plan.BASE_2[key]
    if b and Plan.ARRANGE_BY[key] then return b[1], b[2] end
    return 0, 0
end

-- A saved offset's two numbers, or nil when it is not a table of two finite numbers within
-- ARRANGE_LIMIT (such a value counts as no offset: never an error).
function Plan.Usable(e)
    if type(e) ~= "table" then return nil end
    local x, y = e.x, e.y
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y
        or math.abs(x) > Plan.ARRANGE_LIMIT or math.abs(y) > Plan.ARRANGE_LIMIT then
        return nil
    end
    return x, y
end

-- A piece's saved offset from its built-in spot: dx, dy in UI units (x right, y up); 0, 0
-- when there is none. v: an options table that has an `arrange` value decides for itself
-- (1: its offsets, v.offsets for the Edit Mode pieces and v.charOffsets for the live ones;
-- anything else: none); any other v (a Spell panel size, nil) means the session's
-- (Plan.session). A value that is not usable, or whose key names no piece, counts as none.
function Plan.Offset(v, key)
    local src = v
    if type(src) ~= "table" or src.arrange == nil then src = Plan.session end
    if type(src) ~= "table" or src.arrange ~= 1 then return 0, 0 end
    local def = Plan.ARRANGE_BY[key]
    if not def then return 0, 0 end
    local store = def.kind == "live" and src.charOffsets or src.offsets
    local x, y = Plan.Usable(type(store) == "table" and store[key] or nil)
    if not x then return 0, 0 end
    return x, y
end

-- Whether the row b22Panels (Batch.lua) is On.
function Plan.PanelsOn()
    local batch = PE.Batch
    return type(batch) == "table" and type(batch.On) == "function" and batch.On("b22Panels") == true
end

-- How far a piece is from the spot worked out in this file: its built-in amount (always)
-- plus its saved offset (v as Plan.Offset takes it). What the plan adds to a piece's spot.
--
-- 0.22.0 (spec item 10, row b22Panels, Off by default): with the row On, a diamond whose bottom
-- would fall under 1 (the screen's bottom edge; the game keeps nothing lower) is raised by
-- exactly the shortfall, before the saved offset is added. Why it showed "with Arrange Off":
-- the built-in -16 (Plan.BASE_2) is added in every state, Arrange or not, so a diamond's
-- centre is 66 - 16 = 50 up at every size and its bottom is 50 minus half its height: 1 at
-- 100%, about -3.9 at 110% and -8.8 at 120%. Arrange On with nothing moved is the same.
-- Both rings and both twins have the same height and base, so they are raised alike.
Plan.Moved = function(v, key)
    local bx, by = Plan.Base(key)
    local x, y = Plan.Offset(v, key)
    if type(key) == "string" and key:find(" diamond$") and Plan.PanelsOn() then
        local face = Plan.Face(v)
        local bottom = Plan.FACE_Y + by - (face.dy + face.button / 2)
        if bottom < 1 then by = by + (1 - bottom) end
    end
    return bx + x, by + y
end

-- 0.20.0: saved offsets carried over to the built-in arrangement they are counted from now.
-- store: a table of saved offsets, changed in place; mark: the arrangement they were saved
-- for (nil: 1). Below Plan.ARRANGEMENT, each piece's amount is subtracted from its offset, so
-- built-in plus offset is exactly what it was (an offset that ends at 0, 0 is removed).
-- kind: only the pieces of that kind ("apply", "live"; nil: all). everyPiece: also a piece
-- with no usable offset saved, which stood at the old built-in spot and so gets minus its
-- amount (for a store whose offsets were in use: the screen must not move). Returns what
-- changed: { { key =, fromX =, fromY =, x =, y = }, ... } in Plan.ARRANGE's order. Pure.
function Plan.MigrateBase(store, mark, kind, everyPiece)
    local changed = {}
    if type(store) ~= "table" or (type(mark) == "number" and mark >= Plan.ARRANGEMENT) then return changed end
    for _, def in ipairs(Plan.ARRANGE) do
        local bx, by = Plan.Base(def.key)
        if (bx ~= 0 or by ~= 0) and (kind == nil or def.kind == kind) then
            local e = store[def.key]
            local ox, oy = Plan.Usable(e)
            if ox or everyPiece then
                ox, oy = ox or 0, oy or 0
                local nx, ny = ox - bx, oy - by
                if nx == 0 and ny == 0 then
                    store[def.key] = nil
                else
                    if type(e) ~= "table" then
                        e = {}
                        store[def.key] = e
                    end
                    e.x, e.y = nx, ny
                end
                changed[#changed + 1] = { key = def.key, fromX = ox, fromY = oy, x = nx, y = ny }
            end
        end
    end
    return changed
end

-- 0.15.0 (spec 2026-11-24-controller-layout-0.15.0-panel-size.md): the Spell panel
-- size, saved as opts.panelSize (not opts.size: 0.11.x left an unused `size` in saved
-- files). Fill keeps only 0, 1 and 2, so this one is checked on its own.
Plan.PANEL_SIZES = { 80, 90, 100, 110, 120 }
Plan.PANEL_SIZE_DEFAULT = 100

-- The Spell panel size in percent: one of the five, else 100. `v` is the options table,
-- a size, or nil.
function Plan.PanelSize(v)
    if type(v) == "table" then v = v.panelSize end
    for _, size in ipairs(Plan.PANEL_SIZES) do
        if v == size then return size end
    end
    return Plan.PANEL_SIZE_DEFAULT
end

-- Every number the Spell panel size changes, for size v (as Plan.PanelSize takes it), s
-- the size as a fraction:
--   face        the picture 42s and its steps 46s / 28s; w, h the diamond (134s by 98s)
--   inner, outer  the diamonds' centres' distance from the screen's centre: the inner
--               edge stays at 103, inner = 103 + 67s, outer = inner + 134s + 12
--   frameY      the player and target frames' bottom: 56 while the outer diamonds end
--               12 short of the frames (up to 100%); else just above the diamonds,
--               66 + 49s + 8 rounded up (128 at 110%, 133 at 120%), so the frames stay
--               at 395 across and the target's cast bar (123 to 273 right of the
--               frame) stays on the screen
--   barScale, barStep  the real bars at 60% times s, 21s above and under the diamonds'
--               centre
local function Geometry(v)
    local s = Plan.PanelSize(v) / 100
    local face = { button = FACE.button * s, dx = FACE.dx * s, dy = FACE.dy * s }
    local w, h = 2 * face.dx + face.button, 2 * face.dy + face.button
    local inner = INNER_EDGE + w / 2
    local outer = inner + w + RING_GAP
    local frameY = FRAME_Y
    if outer + w / 2 > FRAME_X - RING_GAP + 1e-9 then frameY = math.ceil(FACE_Y + h / 2 + 8 - 1e-9) end
    return { s = s, face = face, w = w, h = h, inner = inner, outer = outer, frameY = frameY,
        barScale = REAL_BAR_SCALE * s, barStep = REAL_BAR_STEP * s }
end

-- The player, pet and target frames' spots for size v.
local function Frames(v)
    local y = Geometry(v).frameY
    return {
        Player = { "BOTTOMRIGHT", UI, "BOTTOM", -FRAME_X, y },
        Pet = { "BOTTOMRIGHT", UI, "BOTTOM", -FRAME_X, y + UNIT.h + SMALL_GAP },
        Target = { "BOTTOMLEFT", UI, "BOTTOM", FRAME_X, y },
    }
end

-- The picture sizes for size v: { button, dx, dy }, a fresh table.
function Plan.Face(v)
    return Geometry(v).face
end

-- Where each real bar group's centre goes, and its scale, for size v (nil: 100%). x and
-- y are UI units from the screen's bottom centre.
-- 0.18.0: the two bars of a side follow that side's inner spell panel when it is moved, and
-- the bottom anchor (the sub-menu buttons and the wheels) follows "spell wheels", up and down.
local function BarSpots(v)
    local g = Geometry(v)
    local up, down = FACE_Y + g.barStep, FACE_Y - g.barStep
    local lx, ly = Plan.Moved(v, "inner left diamond")
    local rx, ry = Plan.Moved(v, "inner right diamond")
    local _, wy = Plan.Moved(v, "spell wheels")
    local bottom = DeepCopy(SPOTS.bottom)
    bottom.y = bottom.y + wy
    return {
        top = { x = -g.inner + lx, y = up + ly, s = g.barScale },     -- main bar (no trigger)
        left = { x = -g.inner + lx, y = down + ly, s = g.barScale },  -- LT bar
        right = { x = g.inner + rx, y = up + ry, s = g.barScale },    -- RT bar
        both = { x = g.inner + rx, y = down + ry, s = g.barScale },   -- LT + RT bar
        bottom = bottom,
    }
end
Plan.BarSpots = BarSpots

-- The same for when our pictures are off (see FULL_SPOTS).
function Plan.FullBarSpots()
    return DeepCopy(FULL_SPOTS)
end

-- The four spots a diamond can be drawn at, for size v (nil: 100%; see Geometry):
-- { inner = { left, right }, outer = { left, right } }, each { x, y }, a fresh table.
local function FaceSpots(v)
    local g = Geometry(v)
    local spots = {
        inner = { left = { x = -g.inner, y = FACE_Y }, right = { x = g.inner, y = FACE_Y } },
        outer = { left = { x = -g.outer, y = FACE_Y }, right = { x = g.outer, y = FACE_Y } },
    }
    for ring, sides in pairs(spots) do -- 0.18.0: each where the player moved it
        for side, c in pairs(sides) do
            local dx, dy = Plan.Moved(v, ring .. " " .. side .. " diamond")
            c.x, c.y = c.x + dx, c.y + dy
        end
    end
    return spots
end
Plan.FaceSpots = FaceSpots

-- Which half of which bar is drawn where, per state (see FACE_STATES): { rest, lt, rt,
-- both }, each a list of { group = "main"|"lt"|"rt"|"both", half = "dpad"|"face",
-- spot = "innerLeft"|"outerLeft"|"innerRight"|"outerRight", quiet = true|nil }, a fresh copy.
function Plan.FaceStates()
    return DeepCopy(FACE_STATES)
end

-- A frame's rectangle from its anchor point (on UIParent's bottom) and its size.
local function RectAt(point, x, y, w, h)
    local left = (point:find("LEFT") and x) or (point:find("RIGHT") and x - w) or x - w / 2
    local bottom = (point:find("BOTTOM") and y) or (point:find("TOP") and y - h) or y - h / 2
    return { left, bottom, left + w, bottom + h }
end

-- 0.16.0: the chat box bottom left, BOTTOMLEFT 17 in, 450 by 170 (its Edit Mode width and
-- height, 250 to 800 and 120 to 800: Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua:
-- 564-584, stored as hundreds and the rest: EditModeSystemTemplates.lua:2237-2290). Its bottom
-- 6 over the higher of the pet frame's top and the round button's top, rounded up, so it rises
-- with the frames (see Rising).
local CHAT = { x = 17, w = 450, h = 170, over = 6 }
-- The buffs and debuffs, as one area: the game's default rows of 11 buffs and 8
-- debuffs, each icon 30 by 40 (Blizzard_BuffFrame/BuffFrameTemplates.xml:5) with 10
-- between (IconPadding 5, EditModeSettingDisplayInfo.lua:496-503;
-- Mainline/EditModePresetLayouts.lua:434-458), the frame (icon + 10) a slot
-- (BuffFrame.lua:289-302), plus the 15 wide fold-out button (BuffFrame.xml:15), 455 wide.
-- 0.16.0: TOPRIGHT, 10 left of the quest tracker's left edge (x -275); the buff row's top 4
-- under the XP bars' bottom (36 down, so 40 down), the debuff row 38 under it (78 down) as
-- before; the area reaches the debuff row's bottom, 78 + 50 down.
local AURA_X = TRACKER.x - TRACKER.w - 10
local AURA_TOP = XP_TOP_Y - 2 * XP_H - 4
local AURA_DEBUFF_GAP = 38
local AURAS = { right = AURA_X, top = AURA_TOP, w = 11 * 40 + 15, bottom = AURA_TOP - AURA_DEBUFF_GAP - 50 }

-- 0.16.0: the tooltip, the Edit Mode system HudTooltip
-- (Blizzard_APIDocumentationGenerated/EditModeManagerConstantsDocumentation.lua:749), whose
-- frame is GameTooltipDefaultContainer (Blizzard_GameTooltip/Mainline/GameTooltip.xml:242-247,
-- 250 by 150, the game's spot BOTTOMRIGHT -9, 85). The tooltip is pinned by the container's
-- own corner (GameTooltip_SetDefaultAnchor, Blizzard_SharedXML/SharedTooltipTemplates.lua:87-113),
-- so BOTTOMRIGHT puts the tooltip's bottom right corner on the spot and it grows up and left.
-- The spot: 10 in from the right edge, 6 over the target of target's top. Taken at 200 by 100
-- for the overlap check. Where that would reach the quest tracker (at 110% and 120%, where the
-- frames rise), it moves left and lines up with the buffs' right edge, 10 clear of the tracker.
local TOOLTIP = { x = -10, over = 6, w = 200, h = 100 }

-- 0.17.0: the slim bars (spec 2026-11-24-0.17.0-slim-bars.md, "Where each bar is"). On a
-- table, not locals: this file is at Lua's limit of 200 locals. UI units; a pixel of the
-- design's 1280 by 720 screen is 768 / 720 units.
--   x, y, w, h  a main bar (player left, target right, mirrored): its inner edge 218 from the
--               centre, 4 outside the LB / RB targeting pictures (Plan.SHOULDERS, 178 to 214);
--               its bottom 141 up (the design's 132 px); 280 by 28 (264 by 26 px)
--   health, power  inside a main bar: 1 border, the power bar 6, 1 line, the health bar 19,
--               1 border
--   cast        the target's cast bar: 12 tall, 2 under the target bar (127 to 139 up; the
--               diamonds end 124.8 up at the largest Spell panel size)
--   small       the pet bar and the target of target bar: 136 by 17 (128 by 16 px), 3 over
--               the main bars, lined up with their outer ends
--   boxes       the room kept for the buff and debuff boxes, which are not built yet: a row
--               21 tall (20 px); the pet's 3 over the pet bar, the target's over the target
--               bar and 4 short of the target of target bar
--   tooltip     the tooltip's corner while the slim bars are on: BOTTOMRIGHT -10, 10, where
--               the game's target frame was
-- The same at every Spell panel size: nothing here scales or moves.
Plan.SLIM = { x = 218, y = 141, w = 280, h = 28, health = 19, power = 6,
    cast = { h = 12, gap = 2 }, small = { w = 136, h = 17, gap = 3 },
    boxes = { h = 21, gap = 3, short = 4 }, tooltip = { x = -10, y = 10 } }

-- The slim bars' rectangles, { name = { left, bottom, right, top } } in UI units from the
-- screen's bottom centre, a fresh table: the five bars and the two rows kept for the boxes.
-- SlimBars.lua places from these, and Plan.Rects lists them while the switch is on.
-- 0.18.0: v as Plan.Moved takes it; each side's rectangles carry that side's offset (the
-- pieces "player bar" and "target bar" of Plan.ARRANGE).
function Plan.SlimRects(v)
    local S = Plan.SLIM
    local l, r, b, t = S.x, S.x + S.w, S.y, S.y + S.h
    local row = t + S.small.gap
    local petBoxes = row + S.small.h + S.boxes.gap
    local out = {
        ["player bar"] = { -r, b, -l, t },
        ["target bar"] = { l, b, r, t },
        ["cast bar"] = { l, b - S.cast.gap - S.cast.h, r, b - S.cast.gap },
        ["pet bar"] = { -r, row, -r + S.small.w, row + S.small.h },
        ["target of target bar"] = { r - S.small.w, row, r, row + S.small.h },
        ["pet boxes room"] = { -r, petBoxes, -l, petBoxes + S.boxes.h },
        ["target boxes room"] = { l, row, r - S.small.w - S.boxes.short, row + S.boxes.h },
    }
    for _, key in ipairs({ "player bar", "target bar" }) do
        local dx, dy = Plan.Moved(v, key)
        if dx ~= 0 or dy ~= 0 then
            for _, name in ipairs(Plan.ARRANGE_BY[key].rects) do
                local q = out[name]
                q[1], q[2], q[3], q[4] = q[1] + dx, q[2] + dy, q[3] + dx, q[4] + dy
            end
        end
    end
    return out
end

-- 0.18.0: the two targeting pictures' spots with their offsets: { left = { point, x, y },
-- right = { point, x, y } } on UIParent's bottom, a fresh table. Plan.SHOULDERS stays the
-- built-in numbers. 0.19.0: with the square map each is 20 further out before its offset is
-- added (Plan.MAP_SQUARE.shouldersOut).
function Plan.Shoulders(v)
    local out = {}
    local further = Plan.MapLook(v) == 1 and Plan.MAP_SQUARE.shouldersOut or 0
    for side, key in pairs({ left = "LB targeting picture", right = "RB targeting picture" }) do
        local s = Plan.SHOULDERS[side]
        local dx, dy = Plan.Moved(v, key)
        out[side] = { s[1], s[2] + (side == "left" and -further or further) + dx, s[3] + dy }
    end
    return out
end

-- 0.18.0: the overlap check (until 0.17.0 only the tests had it). rects: { name = { left,
-- bottom, right, top } }, as Plan.Rects gives them. Returns every pair that overlaps,
-- { { a =, b =, w =, h = }, ... }, a before b by name, the list in that order. Each sub-menu
-- button and the prompt under it are one piece of the game's (the prompt 1 unit into the
-- button, Blizzard_GamepadActionBars/MainActionBarFrame.xml:94-135) and are not a pair.
function Plan.Overlaps(rects)
    local names, out = {}, {}
    for name in pairs(type(rects) == "table" and rects or {}) do names[#names + 1] = name end
    sort(names)
    for i = 1, #names do
        local a = rects[names[i]]
        for j = i + 1, #names do
            local b = rects[names[j]]
            local one = (names[i] == "LB+LT button" and names[j] == "LB+LT prompt")
                or (names[i] == "RB+RT button" and names[j] == "RB+RT prompt")
            if not one then
                local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
                local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
                if w > 1e-9 and h > 1e-9 then out[#out + 1] = { a = names[i], b = names[j], w = w, h = h } end
            end
        end
    end
    return out
end

-- 0.18.0: the screen the plan is drawn for, in UI units.
Plan.SCREEN = { w = SCREEN_W, h = SCREEN_H }

-- 0.18.0: the Edit Mode pieces whose distance from this file's spot (Plan.Moved, as opts
-- asks for it now: the built-in amount alone while opts.arrange is not 1) differs from the
-- one our Edit Mode layout holds (opts.offsetsWritten, kept by Plan.MarkWritten): their
-- keys, in Plan.ARRANGE's order. 0.20.0: the record holds the whole distance, built-in
-- amount and saved offset together, which is what was written into the layout. So carrying
-- the offsets over (Plan.MigrateBase) leaves the record as it is, and a layout written
-- before the built-in amounts existed shows up here as waiting for them.
function Plan.Pending(opts)
    local out = {}
    local written = type(opts) == "table" and type(opts.offsetsWritten) == "table" and opts.offsetsWritten or {}
    for _, def in ipairs(Plan.ARRANGE) do
        if def.kind == "apply" then
            local dx, dy = Plan.Moved(type(opts) == "table" and opts or { arrange = 0 }, def.key)
            local w = written[def.key]
            local wx = type(w) == "table" and type(w.x) == "number" and w.x or 0
            local wy = type(w) == "table" and type(w.y) == "number" and w.y or 0
            if dx ~= wx or dy ~= wy then out[#out + 1] = def.key end
        end
    end
    return out
end

-- 0.18.0: after a successful write of `pieces` (from Plan.Pieces) into our layout: notes in
-- opts.offsetsWritten how far from this file's spot each arranged piece was written (p.dx,
-- p.dy: Plan.Moved). all (optional): the
-- whole list the pieces were picked from; a piece of Plan.ARRANGE that is several Edit Mode
-- pieces (the three swing timers) is then only noted when every one of them was written.
function Plan.MarkWritten(opts, pieces, all)
    if type(opts) ~= "table" or type(pieces) ~= "table" then return end
    local have, need = {}, {}
    for _, p in ipairs(pieces) do if p.arrange then have[p.arrange] = (have[p.arrange] or 0) + 1 end end
    for _, p in ipairs(type(all) == "table" and all or {}) do if p.arrange then need[p.arrange] = (need[p.arrange] or 0) + 1 end end
    for _, p in ipairs(pieces) do
        if p.arrange and have[p.arrange] >= (need[p.arrange] or 0) then
            if p.dx == 0 and p.dy == 0 then
                if type(opts.offsetsWritten) == "table" then opts.offsetsWritten[p.arrange] = nil end
            else
                -- The table is only made once there is something to note: a player who never
                -- arranged anything keeps the saved options 0.17.0 wrote.
                if type(opts.offsetsWritten) ~= "table" then opts.offsetsWritten = {} end
                opts.offsetsWritten[p.arrange] = { x = p.dx, y = p.dy }
            end
        end
    end
end

-- 0.16.0: the spots that follow the frames' height at Spell panel size v (as Plan.PanelSize
-- takes it): the round button's bottom (hubY), the chat's bottom (chatY) and the tooltip's
-- corner (tipX, tipY).
local function Rising(v)
    local frameY = Geometry(v).frameY
    local hubY = frameY + UNIT.h + HUB.over
    local petTop = frameY + UNIT.h + SMALL_GAP + SMALL.h
    local chatY = math.ceil(math.max(petTop, hubY + HUB.size) + CHAT.over - 1e-9)
    local tipY = frameY + UNIT.h + Plan.TOT_SPOT.y + SMALL.h + TOOLTIP.over
    local tipX = TOOLTIP.x
    if tipY + TOOLTIP.h > SCREEN_H + TRACKER.y - TRACKER.h then tipX = AURA_X end
    return { hubY = hubY, chatY = chatY, tipX = tipX, tipY = tipY }
end

-- The PE button's default spot while the layout is placed: point, x, y on UIParent, in UI
-- units, for the options (or a Spell panel size, or nil).
function Plan.HubSpot(opts)
    return "BOTTOMLEFT", HUB.x, Rising(opts).hubY
end

-- The swing timers' spots: { x, y = { MainHand, OffHand, Ranged } }, each timer's bottom.
-- 0.19.0: worked out from the round map for both looks; with the square map (v as
-- Plan.MapLook takes it) each is then 14 higher (Plan.MAP_SQUARE.timersUp).
local function Timers(v)
    local s = MAP.size / 100
    local mapTop = MAP.y + MAP.frameUp + MAP.frame * s / 2 + MAP.round * s / 2
    local y, step = {}, math.floor(TIMER.h + 0.5) + TIMER.gap -- 12 + 2
    local bottom = math.ceil(mapTop + TIMER.over - 1e-9)
    if Plan.MapLook(v) == 1 then bottom = bottom + Plan.MAP_SQUARE.timersUp end
    for i, name in ipairs(TIMER.order) do y[name] = bottom + (i - 1) * step end
    return { x = MAP.x + MAP.frameRight, y = y }
end

-- The rectangles the template puts on screen, for the overlap check:
-- { name = { left, bottom, right, top } } in UI units from the bottom centre,
-- worked out from the spots and sizes above. Each of the four diamond spots is
-- listed once (whichever bar is drawn there); the real bars under the inner ones
-- are not (Plan.RealBarRects). The quest tracker is taken at
-- its least height (400). The target's two aura rows are the part above the
-- frame; its cast bar is the spot it takes with the target of target shown.
-- v: the options (panelSize, hints, mapButtons), or a Spell panel size (as
-- Plan.PanelSize takes it); nil is the defaults. The hint box is listed only while
-- hints is 1; the title strip includes its two buttons while mapButtons is 1. While slim is 1
-- (0.17.0) the game's four unit frames are invisible, so their six rectangles are left out,
-- the slim bars' seven are listed and the tooltip is in its corner. While mapLook is 1
-- (0.19.0) "map" is the square's edge box and there is no title strip (MapLook.lua hides it).
function Plan.Rects(v)
    local o = Fill(type(v) == "table" and v or nil)
    local rise = Rising(v)
    local r = {}
    local function box(name, cx, cy, w, h) r[name] = { cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2 } end
    local g = Geometry(v)
    for ring, sides in pairs(FaceSpots(v)) do
        for side, c in pairs(sides) do box(ring .. " " .. side .. " diamond", c.x, c.y, g.w, g.h) end
    end
    local FRAMES = Frames(v)
    if Plan.MapLook(v) == 1 then
        r.map = Plan.MapBox(v)
    else
        local roundCentre = MAP.y + MAP.frameUp + MAP.frame * MAP.size / 100 / 2
        local round = MAP.round * MAP.size / 100
        box("map", MAP.x + MAP.frameRight, roundCentre, round, round)
        local out = o.mapButtons == 1 and STRIP_OUT or { left = 0, right = 0 }
        r["title strip"] = { MAP.x + STRIP.x - STRIP.w / 2 - out.left, MAP.y + STRIP.up,
            MAP.x + STRIP.x + STRIP.w / 2 + out.right, MAP.y + STRIP.up + STRIP.h }
    end
    local timers = Timers(v)
    for name, y in pairs(timers.y) do r[name .. " timer"] = { timers.x - TIMER.w / 2, y, timers.x + TIMER.w / 2, y + TIMER.h } end
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
    -- The sub-menu buttons, 38 across (CIRCULAR_BUTTON_EXPANDED_SIZE,
    -- Blizzard_GamepadActionBars/ActionBarStyles.lua:20), and their prompts under them.
    local _, wheelY = Plan.Moved(v, "spell wheels") -- 0.18.0: both hang on the bottom anchor
    for _, side in ipairs({ -1, 1 }) do
        box(side < 0 and "LB+LT button" or "RB+RT button", side * 138, SPOTS.bottom.y - 50 + wheelY, 38, 38)
        box(side < 0 and "LB+LT prompt" or "RB+RT prompt", side * PROMPT.x, PROMPT.y + wheelY, PROMPT.w, PROMPT.h)
    end
    local shoulders = Plan.Shoulders(v)
    local sl, sr = shoulders.left, shoulders.right
    r["LB targeting picture"] = RectAt(sl[1], sl[2], sl[3], SHOULDER.w, SHOULDER.h)
    r["RB targeting picture"] = RectAt(sr[1], sr[2], sr[3], SHOULDER.w, SHOULDER.h)
    local W, H = SCREEN_W, SCREEN_H
    local tr = W / 2 + TRACKER.x
    r["quest tracker"] = { tr - TRACKER.w, H + TRACKER.y - TRACKER.h, tr, H + TRACKER.y }
    local cl = -W / 2 + CHAT.x
    r.chat = { cl, rise.chatY, cl + CHAT.w, rise.chatY + CHAT.h }
    r["buffs and debuffs"] = { W / 2 + AURAS.right - AURAS.w, H + AURAS.bottom, W / 2 + AURAS.right, H + AURAS.top }
    r["XP bars"] = { -596 / 2, H + XP_TOP_Y - 2 * XP_H, 596 / 2, H + XP_TOP_Y }
    local tipRight = W / 2 + rise.tipX
    r.tooltip = { tipRight - TOOLTIP.w, rise.tipY, tipRight, rise.tipY + TOOLTIP.h }
    local _, hubX, hubY = Plan.HubSpot(v)
    r["round button"] = { -W / 2 + hubX, hubY, -W / 2 + hubX + HUB.size, hubY + HUB.size }
    if o.hints == 1 then
        local hl = -W / 2 + HINTS.x
        r["hint box"] = { hl, H + HINTS.y - HINTS.h, hl + HINTS.w, H + HINTS.y }
    end
    if o.slim == 1 then
        for _, name in ipairs({ "player", "pet", "target", "target of target", "target auras", "target cast bar" }) do r[name] = nil end
        for name, rect in pairs(Plan.SlimRects(v)) do r[name] = rect end
        local tip = Plan.SLIM.tooltip
        r.tooltip = { W / 2 + tip.x - TOOLTIP.w, tip.y, W / 2 + tip.x, tip.y + TOOLTIP.h }
    end
    -- 0.18.0: the Edit Mode pieces where the player moved them (the live ones were worked
    -- out moved above: FaceSpots, Shoulders, SlimRects, the bottom anchor).
    for _, def in ipairs(Plan.ARRANGE) do
        if def.kind == "apply" then
            local dx, dy = Plan.Moved(v, def.key)
            if dx ~= 0 or dy ~= 0 then
                for _, name in ipairs(def.rects) do
                    local q = r[name]
                    if q then q[1], q[2], q[3], q[4] = q[1] + dx, q[2] + dy, q[3] + dx, q[4] + dy end
                end
            end
        end
    end
    return r
end

-- The game's four real bars, invisible under the inner diamonds: { main, lt, rt,
-- both } each { left, bottom, right, top }, at Spell panel size v. Not part of
-- Plan.Rects: they sit under the face by design.
function Plan.RealBarRects(v)
    local r = {}
    local spots = BarSpots(v)
    for spot, bar in pairs(SPOT_FACE) do
        local s = spots[spot]
        local w, h = BAR.w * s.s, BAR.h * s.s
        r[bar] = { s.x - w / 2, s.y - h / 2, s.x + w / 2, s.y + h / 2 }
    end
    return r
end

-- The two sub-menu wheels: centred on the sub-menu buttons, 175 across (the
-- mockup's ring; the game puts its eight buttons 60 out, FlyoutRadial.lua:28).
function Plan.Wheels(v)
    local _, wheelY = Plan.Moved(v, "spell wheels") -- 0.18.0
    local y = SPOTS.bottom.y - 50 + wheelY
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
    local FRAMES = Frames(opts) -- they rise at the larger Spell panel sizes
    local rise = Rising(opts)   -- and the chat and the tooltip with them (0.16.0)
    local list = {}
    -- key (0.18.0): the piece of Plan.ARRANGE this one belongs to; its offset is added to the
    -- spot, and the piece carries the key and the offset (arrange, dx, dy) for Plan.MarkWritten.
    local function add(system, index, anchor, settings, key)
        local p = { system = system, index = index, anchor = anchor, settings = settings, moved = anchor and true or nil }
        if key and anchor then
            local dx, dy = Plan.Moved(opts, key)
            anchor.x, anchor.y = anchor.x + dx, anchor.y + dy
            p.arrange, p.dx, p.dy = key, dx, dy
        end
        list[#list + 1] = p
    end
    -- HeaderUnderneath 1 puts the map's title strip under the map (0.11.1 spec, 3); left
    -- out by Plan.Apply when the game has no such setting.
    -- 0.19.0: the size and the spot of the map look (Round: Size 2 at -6, 0; Square: Size 5 at -10, 0).
    local m = Plan.MapOf(o)
    add("Minimap", nil, Spot("BOTTOM", "BOTTOM", m.x, m.y), { Size = (m.size - 50) / 10, HeaderUnderneath = 1 }, "map")
    -- 0.16.0: the chat bottom left, over the PE button and the pet frame (see CHAT).
    add("ChatFrame", nil, Spot("BOTTOMLEFT", "BOTTOMLEFT", CHAT.x, rise.chatY),
        { WidthHundreds = math.floor(CHAT.w / 100), WidthTensAndOnes = CHAT.w % 100,
          HeightHundreds = math.floor(CHAT.h / 100), HeightTensAndOnes = CHAT.h % 100 }, "chat")
    -- 0.16.0: the buffs and debuffs under the XP bars, left of the quest tracker, which is
    -- top right (see AURAS and TRACKER).
    add("AuraFrame", "BuffFrame", Spot("TOPRIGHT", "TOPRIGHT", AURAS.right, AURAS.top), nil, "buffs and debuffs")
    add("AuraFrame", "DebuffFrame", Spot("TOPRIGHT", "TOPRIGHT", AURAS.right, AURAS.top - AURA_DEBUFF_GAP), nil, "buffs and debuffs")
    add("ObjectiveTracker", nil, Spot("TOPRIGHT", "TOPRIGHT", TRACKER.x, TRACKER.y), { Height = 0 }, "quest tracker")
    -- The XP bars along the top edge, centred, at 100% (0.11.1 spec, 1).
    add("StatusTrackingBar", "StatusTrackingBar1", Spot("TOP", "TOP", 0, XP_TOP_Y), { Size = 10 }, "XP bars")
    add("StatusTrackingBar", "StatusTrackingBar2", Spot("TOP", "TOP", 0, XP_TOP_Y - XP_H), { Size = 10 }, "XP bars")
    add("GamepadMainActionBar", nil, nil, { Compact = 0, ShowEmptyBars = 0, ShouldExpand = 0 })
    add("UnitFrame", "Player", Anchor(FRAMES.Player), nil, "player")
    add("UnitFrame", "Pet", Anchor(FRAMES.Pet), nil, "player")
    -- BuffsOnTop 1 (as the game's Gamepad preset has it): the target's auras grow up, so
    -- the cast bar keeps its spot under the frame. Left out by Plan.Apply when the game has
    -- no such setting.
    add("UnitFrame", "Target", Anchor(FRAMES.Target), { BuffsOnTop = 1 }, "target")
    -- 0.16.0: the tooltip above the target of target (see TOOLTIP). Left out by Plan.Apply
    -- when the game has no such system. 0.17.0: in the bottom right corner while the slim
    -- bars are on (Plan.SLIM.tooltip).
    if o.slim == 1 then
        add("HudTooltip", nil, Spot("BOTTOMRIGHT", "BOTTOMRIGHT", Plan.SLIM.tooltip.x, Plan.SLIM.tooltip.y), nil, "tooltip")
    else
        add("HudTooltip", nil, Spot("BOTTOMRIGHT", "BOTTOMRIGHT", rise.tipX, rise.tipY), nil, "tooltip")
    end
    local visibility = { Ranged = o.ranged, MainHand = o.mainHand, OffHand = o.offHand }
    local timers = Timers(o)
    for _, name in ipairs(TIMER.order) do
        add("SwingTimer", name, Spot("BOTTOM", "BOTTOM", timers.x, timers.y[name]),
            { Scale = 3, Width = 0, Height = 0, Visibility = visibility[name] }, "swing timers")
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

local TEXT_OFF = "Needs a reload to switch on or off. Off brings back your own layout."
local TEXT_USING = "Using the Pocket Essentials layout. Move the map, chat or frames in Edit Mode if you like."
local TEXT_ANOTHER = "Another Edit Mode layout is active. Pick Pocket Essentials in Edit Mode, or switch this off and on."
local TEXT_NEEDS_GAMEPAD = "Needs the game's Gamepad UI (Options, Controller, Enable Gamepad UI)."
local TEXT_NO_LAYOUTS = "This game version has no layouts an addon can change."
local TEXT_EDIT_MODE = "Close Edit Mode first."
local TEXT_NAME_REFUSED = "The game refused the layout name."
local RELOAD_REASON = "Reload to finish the layout change."
-- Said in chat when a login, not a tap, changed this character's layout: the reload
-- request itself only shows in the settings window, which is closed at login.
local CHAT_SWITCHED_ON = "This character now uses the controller layout. Open the settings and tap Reload now to finish."
local CHAT_SWITCHED_OFF = "This character's own screen layout is back. Open the settings and tap Reload now to finish."
local CHAT_UPDATED = "The controller layout was updated to the new arrangement (changes you made to it in Edit Mode are replaced). Open the settings and tap Reload now to finish."
-- Status lines while the login check waits (0.12.0 spec, "Getting it without taps"): no silent waiting.
local TEXT_WAIT_FIGHT = "Updating the layout after this fight."
local TEXT_WAIT_LAYOUTS = "Waiting for the game's layouts."
-- Under the "Using" line while our spell pictures are off for a reason (PE.FaceBars:Status()).
local TEXT_FACE_OFF = "Pocket Essentials' spell pictures are off: "
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
            -- 0.16.0 (EditModeManagerConstantsDocumentation.lua:749): may be missing on another
            -- client: Plan.Apply then leaves the tooltip out.
            HudTooltip = Optional(function() return Enum.EditModeSystem.HudTooltip end),
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
-- Blizzard_GamepadActionBars (build 1.60.1.70938, unchanged in 71091): ActionBarTemplates.xml
-- makes PageUnit's Top, Left, Right and Bottom CenteredAnchor (50 x 50,
-- CENTER on PageUnit at (0, 58), (-195, 0), (195, 0), (0, -58)), each with a
-- Bar anchored CENTER on it. The game sets no scale on them and re-anchors
-- only the Top, Left and Right anchors, in PageUnit:RefreshCompactLayout
-- (PageUnit.lua:292-315). The both-triggers bar is moved itself, because the
-- sub-menu buttons follow the bottom anchor (ClassActionFlyout.lua:24-25).
-- Since 0.14.0 the four bars are placed at 60% under the inner diamonds; FaceBars.lua
-- makes them invisible (their anchors' alpha) once its pictures show.
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
-- its corner would take them along, so they are anchored on the screen's bottom instead:
-- until 0.13.0 where that anchor held them (the main bar centred, 42 up: -108, 84 and
-- 108, 84), in 0.14.0 and 0.15.0 beside the map (BOTTOMRIGHT at -76, 128 and BOTTOMLEFT
-- at 76, 128), since 0.16.0 beside the "LB + LT" / "RB + RT" prompts (Plan.SHOULDERS,
-- BOTTOMRIGHT at -178, 155 and BOTTOMLEFT at 178, 155).
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
      point = function() local s = Plan.Shoulders().left return s[1], UIParent, "BOTTOM", s[2], s[3] end },
    { name = "RB targeting picture", get = function() return Child(Child(GamepadBar(), "PageUnit"), "RightShoulderBackground") end,
      point = function() local s = Plan.Shoulders().right return s[1], UIParent, "BOTTOM", s[2], s[3] end },
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

---------------------------------------------------------------------------
-- The game's controller hint box (0.13.0): the box top left that lists LB / RB
-- targeting, ping and auto-run. It is the game's own setting "Show persistent
-- controls information" (Blizzard_SettingsDefinitions_Shared/Gamepad.lua:140), the
-- console setting GamepadShowPersistentInputLegend; the box hides itself as soon as
-- it changes (Blizzard_Gamepad/UI/PersistentInputLegend/GamepadPersistentInputLegend.lua:
-- 201-203, 273, 297). Since 0.16.0 the "Controls reminder" row (opts.hints) picks it:
-- Off (0) writes "0" when the layout is placed, as since 0.13.0; On (1) writes "1". Either
-- way the player's value is saved once (opts.hintsWas) and written back when the layout is
-- put back or switched off. While a value is saved it is not set again unless the row was
-- tapped since (hintsTapped), so a player who changes the game's own option while the
-- layout is on keeps it. Out of a fight only (both callers run there).
---------------------------------------------------------------------------

local HINTS_SETTING = "GamepadShowPersistentInputLegend"

-- The setting's value as a string, or nil when it cannot be read.
local function ReadHints()
    if not (C_CVar and type(C_CVar.GetCVar) == "function") then return nil end
    local ok, v = pcall(C_CVar.GetCVar, HINTS_SETTING)
    if not ok or v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return tostring(v)
end

-- True if the game took the value.
local function WriteHints(value)
    if not (C_CVar and type(C_CVar.SetCVar) == "function") then return false end
    local ok, took = pcall(C_CVar.SetCVar, HINTS_SETTING, value)
    return ok and took ~= false
end

local hintsTapped = false -- the Controls reminder row was tapped since the value was last written

local function PlaceHints()
    local opts = mod and mod.opts
    if type(opts) ~= "table" then return end
    local value = opts.hints == 1 and "1" or "0"
    if opts.hintsWas ~= nil then
        if not hintsTapped then return end
        if WriteHints(value) then
            hintsTapped = false
            if PE.debugOn then PE:Debug("ctrlLayout", "the game's hint box set to " .. value .. " (the row)") end
        elseif PE.debugOn then
            PE:Debug("ctrlLayout", "the game's hint box setting could not be changed")
        end
        return
    end
    local was = ReadHints()
    if was == nil then return end
    if not WriteHints(value) then
        if PE.debugOn then PE:Debug("ctrlLayout", "the game's hint box setting could not be changed") end
        return
    end
    opts.hintsWas = was
    hintsTapped = false
    if PE.debugOn then PE:Debug("ctrlLayout", "the game's hint box set to " .. value .. " (it was " .. was .. ")") end
end

local function ShowHints()
    local opts = mod and mod.opts
    hintsTapped = false -- nothing saved after this: the next placement writes the row's value anyway
    if type(opts) ~= "table" or type(opts.hintsWas) ~= "string" then return end
    if not WriteHints(opts.hintsWas) then
        -- Kept: the next put-back tries again.
        if PE.debugOn then PE:Debug("ctrlLayout", "the game's hint box setting could not be put back") end
        return
    end
    opts.hintsWas = nil
    if PE.debugOn then PE:Debug("ctrlLayout", "the game's hint box setting put back") end
end

---------------------------------------------------------------------------
-- 0.16.0: the pieces of the playing screen Edit Mode does not own (spec 2026-11-24
-- "0.16.0: the arrangement", "Left to the builder"): the chat without its dark box, the
-- map's black border in place of its gold ring, and the two map buttons (the "Map buttons"
-- row, opts.mapButtons). Placed with the layout, bars or not, and put back with it; each
-- piece keeps what it found before its first change. Out of a fight only: PlaceNow and
-- RestoreNow run through PE:RunOutOfCombat, and so do the two hooks below. A missing frame
-- or function skips that one piece (said once in the debug log); the rest still runs.
---------------------------------------------------------------------------

local PlaceScreen, RestoreScreen -- the block below; in a do block, as the file is near Lua's 200 locals
-- 0.16.4: everything of the snapshot (the block at the end of the file) hangs on this one
-- table, for the same reason (the file is AT the limit: a new top-level local does not
-- compile; put new ones in a do block or on a table). sources: functions other parts added
-- (mod:AddSnapshotSource).
local Snap = { sources = {} }

-- 0.17.0: the slim bars (SlimBars.lua, PE.SlimBars), reached the way the spell pictures are
-- (FaceCall below) and hung on the same table for want of a local.
--   Snap.slimOn    the "Slim bars" switch as this session found it at the first placement
--                  (nil before that). A change counts from the next reload, so this never
--                  changes afterwards.
--   Snap.SlimCall  calls PE.SlimBars[name] and returns its first two answers. Does nothing,
--                  and so SlimBars.lua does nothing, unless slimOn is true. Guarded: a
--                  missing or older SlimBars, or a call that raises, changes nothing here.
Snap.SlimCall = function(name, ...)
    if Snap.slimOn ~= true then return nil end
    local slim = PE.SlimBars
    local fn = type(slim) == "table" and slim[name] or nil
    if type(fn) ~= "function" then return nil end
    local ok, a, b = PE:Safe("ctrlLayout", fn, slim, ...)
    if ok then return a, b end
    return nil
end

-- 0.18.0: arrange it yourself (Arrange.lua, PE.Arrange), hung on the same table.
--   Snap.arrangeLogin  the "Arrange it yourself" switch as the login found it (OnLoad)
--   Snap.arrangeOn     that value once the session has asked for it (Snap.View, below
--                      PlaceNow); a change of the switch counts from the next reload
--   Snap.ArrangeCall   calls PE.Arrange[name], as SlimCall does; nothing unless arrangeOn
--   Snap.ArrangeFilter the Edit Mode pieces whose offset in our layout is not the one the
--                      options ask for now (for RewritePieces)
Snap.ArrangeCall = function(name, ...)
    if Snap.arrangeOn ~= true then return nil end
    local arrange = PE.Arrange
    local fn = type(arrange) == "table" and arrange[name] or nil
    if type(fn) ~= "function" then return nil end
    local ok, a, b = PE:Safe("ctrlLayout", fn, arrange, ...)
    if ok then return a, b end
    return nil
end
Snap.ArrangeFilter = function(p)
    if not p.arrange then return false end
    for _, key in ipairs(Plan.Pending(mod.opts)) do
        if key == p.arrange then return true end
    end
    return false
end

do
    local screenPlaced = false -- these pieces are placed (the hooks below do nothing otherwise)
    local missingSaid = {}

    local function SayMissing(what)
        if missingSaid[what] then return end
        missingSaid[what] = true
        if PE.debugOn then PE:Debug("ctrlLayout", what .. " not changed: not found on this client") end
    end

    -- A texture or frame that can be read, shown and hidden.
    local function Showable(t)
        return type(t) == "table" and type(t.IsShown) == "function" and type(t.Show) == "function"
            and type(t.Hide) == "function"
    end

    local function IsShownNow(t)
        local ok, shown = pcall(t.IsShown, t)
        return ok and shown and true or false
    end

    -- The chat's dark box. Each chat window's box is the textures listed in CHAT_FRAME_TEXTURES
    -- (Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua:43-63, named after the window).
    -- Each one that shows is hidden with its own Hide, and shown again at the end: nothing
    -- else. The game draws the box when the chat fades in, opened or pointed at
    -- (FCF_FadeInChatFrame, 1237-1246) and fades it out again (1276), but both skip a hidden
    -- texture and no chat code shows one again. A texture's see-through is never touched, so
    -- the player's own value is still on it when it is shown again.
    --
    -- 0.16.3: no FCF_ function is called. Until 0.16.2 this called FCF_SetWindowAlpha (1053-1063),
    -- which writes frame.oldAlpha on the chat window. Written from addon code, that field carries
    -- the addon's mark; the game's chat code reads it, the chat window is one of the windows that
    -- takes the controller (137-146), and from login on the game refused its own controller
    -- actions in the addon's name (SetPreferredGamepadInteractTarget, TargetUnit, ClearTarget,
    -- UseAction...). Found on the device on 2026-11-24 with 0.16.2's testing rows: every other
    -- part of the layout on, no refusal; this part on, refusals at once
    -- (docs/superpowers/plans/2026-11-24-blocked-action-0.16.1.md).
    local chatHidden = {}  -- box textures hidden by the addon, in order
    local chatHiddenSet = {}

    local function ChatWindows()
        local out = {}
        local n = tonumber(NUM_CHAT_WINDOWS) or 0
        for i = 1, n do
            local f = _G["ChatFrame" .. i]
            if type(f) == "table" then out[#out + 1] = { frame = f, name = "ChatFrame" .. i } end
        end
        return out
    end

    local function PlaceChat()
        if type(CHAT_FRAME_TEXTURES) ~= "table" then return SayMissing("the chat's box (CHAT_FRAME_TEXTURES)") end
        for _, w in ipairs(ChatWindows()) do
            for _, value in ipairs(CHAT_FRAME_TEXTURES) do
                local t = _G[w.name .. tostring(value)]
                if Showable(t) and IsShownNow(t) then
                    pcall(t.Hide, t)
                    if not chatHiddenSet[t] then
                        chatHiddenSet[t] = true
                        chatHidden[#chatHidden + 1] = t
                    end
                end
            end
        end
    end

    local function RestoreChat()
        for _, t in ipairs(chatHidden) do pcall(t.Show, t) end
        chatHidden, chatHiddenSet = {}, {}
    end

    -- The map's gold ring: MinimapCompassTexture, and MinimapCompassTextureUnderlay under it
    -- (Blizzard_Minimap/Mainline/Minimap.xml:111-125, the file this client loads). The game
    -- redraws them in MinimapCluster:UpdateMinimapConfig (Camelot/Minimap.lua:31-58: a new
    -- picture for the compass, and the underlay shown only while the map rotates), so a hook
    -- on it, installed once, hides them again while placed. The underlay's wish is read again
    -- after each redraw, so the end shows it only if the game last wanted it.
    -- In its place a black disc of ours (the addon's circle picture, UI.lua's CreateDisc), 4
    -- wider than the round map (the Minimap frame, Mainline/Minimap.xml:56-62) and one frame
    -- level under it, on the map's parent so it moves and scales with the map.
    local RING_HOOK = "UpdateMinimapConfig"
    local RING = {
        { name = "MinimapCompassTexture", get = function() return MinimapCompassTexture end },
        { name = "MinimapCompassTextureUnderlay", get = function() return MinimapCompassTextureUnderlay end, redrawn = true },
    }
    local ringFound = {}  -- [texture] = shown before the addon hid it (the underlay: as the game last drew it)
    local ringOrder = {}
    local ringHooked = false
    local disc            -- { frame, art } made at the first placement
    local PlaceRing       -- below

    local function PlaceDisc()
        local map = Minimap
        if type(map) ~= "table" or type(map.GetParent) ~= "function" or type(map.GetWidth) ~= "function"
            or type(map.GetFrameLevel) ~= "function" or type(map.GetEffectiveScale) ~= "function" then
            return SayMissing("the map's black border (Minimap)")
        end
        local ok, parent = pcall(map.GetParent, map)
        if not ok or type(parent) ~= "table" then return SayMissing("the map's black border (the map's parent)") end
        if not disc then
            local UI = PE.UI
            if type(UI) ~= "table" or type(UI.CreateDisc) ~= "function" or type(CreateFrame) ~= "function" then
                return SayMissing("the map's black border (the disc)")
            end
            local frame = CreateFrame("Frame", nil, parent)
            local art = UI:CreateDisc(frame, "BACKGROUND")
            art:SetColor(0, 0, 0, 1)
            disc = { frame = frame, art = art }
        end
        local _, w = pcall(map.GetWidth, map)
        local _, level = pcall(map.GetFrameLevel, map)
        local _, mapScale = pcall(map.GetEffectiveScale, map)
        local okP, parentScale = pcall(parent.GetEffectiveScale, parent)
        local uiScale = UIParent and UIParent:GetEffectiveScale() or 1
        if type(w) ~= "number" or type(level) ~= "number" or type(mapScale) ~= "number" or not okP
            or type(parentScale) ~= "number" or parentScale <= 0 then
            return SayMissing("the map's black border (the map's size)")
        end
        -- In the parent's units: the map's own width, plus 4 screen units.
        local size = w * mapScale / parentScale + 4 * uiScale / parentScale
        local f = disc.frame
        f:SetFrameLevel(math.max(0, level - 1))
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint("CENTER", map, "CENTER", 0, 0)
        disc.art:Layout(f, size)
        f:Show()
    end

    local function HookRing()
        if ringHooked then return end
        local cluster = MinimapCluster
        if type(cluster) ~= "table" or type(cluster[RING_HOOK]) ~= "function" or type(hooksecurefunc) ~= "function" then
            return SayMissing("the hook on the map's redraw (MinimapCluster.UpdateMinimapConfig)")
        end
        local ok = pcall(hooksecurefunc, cluster, RING_HOOK, PE:Wrap("ctrlLayout", function()
            if not screenPlaced then return end
            PE:RunOutOfCombat("ctrlLayout:ring", function() if screenPlaced then PlaceRing(true) end end)
        end))
        ringHooked = ok and true or false
    end

    -- redraw: the game has just drawn the ring again (the hook).
    PlaceRing = function(redraw)
        for _, r in ipairs(RING) do
            local ok, t = pcall(r.get)
            if not ok or not Showable(t) then
                SayMissing(r.name)
            else
                local shown = IsShownNow(t)
                if ringFound[t] == nil then
                    ringFound[t] = shown
                    ringOrder[#ringOrder + 1] = t
                elseif redraw and r.redrawn then
                    ringFound[t] = shown
                end
                if shown then pcall(t.Hide, t) end
            end
        end
        -- 0.19.0: the map look (MapLook.lua). With Round it does nothing at all, unless a square
        -- map was placed earlier this session, which it then puts back. The black disc is the
        -- round map's border: it is drawn unless the square mask is on the map.
        local look, isSquare = PE.MapLook, false
        if type(look) == "table" and type(look.Place) == "function" and type(look.IsSquare) == "function" then
            PE:Safe("ctrlLayout", look.Place, look, mod and mod.opts, redraw)
            local ok, answer = pcall(look.IsSquare, look)
            isSquare = ok and answer == true
        end
        if isSquare then
            if disc then disc.frame:Hide() end
        else
            PlaceDisc()
        end
        HookRing()
    end

    -- The disc's frame for the snapshot, or nil before the first placement.
    Snap.disc = function() return disc and disc.frame or nil end

    local function RestoreRing()
        for _, t in ipairs(ringOrder) do
            if ringFound[t] then pcall(t.Show, t) end
        end
        ringFound, ringOrder = {}, {}
        if disc then disc.frame:Hide() end
        -- 0.19.0: and the square map, if one was placed (MapLook.lua): the game's mask, the strip.
        local look = PE.MapLook
        if type(look) == "table" and type(look.Restore) == "function" then PE:Safe("ctrlLayout", look.Restore, look) end
    end

    -- The two map buttons beside the place name: the tracking (magnifier) frame,
    -- MinimapCluster.Tracking (Mainline/Minimap.xml:25-44), and the calendar button,
    -- GameTimeFrame (Mainline/GameTime.xml:3, Camelot/GameTimeFrameTemplate.xml:3-11). The
    -- addon-count badge, AddonCompartmentFrame, is anchored under the calendar button
    -- (Camelot/AddonCompartment.xml:3-12, and Camelot/Minimap.lua:80-90), so it would float
    -- without it: hidden with them. The mail and other rim icons are anchored to the place name
    -- on this client (Camelot/MinimapIndicatorFrameTemplate.xml:8-10, Camelot/Minimap.lua:75-76)
    -- and stay. The game shows these again on its own (the tracking frame, Mainline/Minimap.lua:398,
    -- 852, 917; the badge, Mainline/AddonCompartment.lua:166-172), so each gets an OnShow hook,
    -- installed once, that hides it again while placed; a button the game shows meanwhile is
    -- shown at the end.
    local BUTTONS = {
        { name = "the tracking button (MinimapCluster.Tracking)",
          get = function() return Child(type(MinimapCluster) == "table" and MinimapCluster or nil, "Tracking") end },
        { name = "the calendar button (GameTimeFrame)", get = function() return GameTimeFrame end },
        { name = "the addon-count badge (AddonCompartmentFrame)", get = function() return AddonCompartmentFrame end },
    }
    local buttonsFound = {}  -- [frame] = shown before the addon hid it, or shown by the game since
    local buttonOrder = {}
    local buttonHooked = {}
    local PlaceButtons       -- below

    local function ButtonsWanted()
        local opts = mod and mod.opts
        -- 0.19.0: never with the square map, whose strip is hidden (the row says "Round map only").
        return type(opts) == "table" and opts.mapButtons == 1 and Plan.MapLook(opts) ~= 1
    end

    local function HookButton(f)
        if buttonHooked[f] or type(f.HookScript) ~= "function" then return end
        local ok = pcall(f.HookScript, f, "OnShow", PE:Wrap("ctrlLayout", function()
            if not screenPlaced or ButtonsWanted() then return end
            buttonsFound[f] = true -- the game wants it shown: it is, once the layout goes
            PE:RunOutOfCombat("ctrlLayout:mapButtons", function() if screenPlaced then PlaceButtons() end end)
        end))
        buttonHooked[f] = ok and true or false
    end

    local function RestoreButtons()
        for _, f in ipairs(buttonOrder) do
            if buttonsFound[f] then pcall(f.Show, f) end
        end
        buttonsFound, buttonOrder = {}, {}
    end

    PlaceButtons = function()
        if ButtonsWanted() then return RestoreButtons() end -- Shown: as the game draws them
        for _, b in ipairs(BUTTONS) do
            local ok, f = pcall(b.get)
            if not ok or not Showable(f) then
                SayMissing(b.name)
            else
                local shown = IsShownNow(f)
                if buttonsFound[f] == nil then buttonOrder[#buttonOrder + 1] = f end
                if shown or buttonsFound[f] == nil then buttonsFound[f] = shown end
                if shown then pcall(f.Hide, f) end
                HookButton(f)
            end
        end
    end

    -- Every piece of this block, each on its own: one that raises does not stop the others.
    PlaceScreen = function()
        screenPlaced = true
        PE:Safe("ctrlLayout", PlaceHints)
        PE:Safe("ctrlLayout", PlaceChat)
        PE:Safe("ctrlLayout", PlaceRing, false)
        PE:Safe("ctrlLayout", PlaceButtons)
    end

    RestoreScreen = function()
        screenPlaced = false
        PE:Safe("ctrlLayout", ShowHints)
        PE:Safe("ctrlLayout", RestoreChat)
        PE:Safe("ctrlLayout", RestoreRing)
        PE:Safe("ctrlLayout", RestoreButtons)
    end
end

---------------------------------------------------------------------------
-- Our own spell pictures (FaceBars.lua, PE.FaceBars): started after the bars are
-- placed, stopped before they are put back and whenever the feature goes off.
-- PE.FaceBars:Start() builds the pictures and only then fades the real bars, so a
-- face that cannot work leaves the game's bars showing; Stop() works at any time,
-- also in a fight; Status() is the reason the game's own bars show, or nil.
-- Every call is guarded: an older or missing FaceBars changes nothing here.
---------------------------------------------------------------------------

-- PE.FaceBars and one of its functions by name, or nil.
local function FaceCall(name)
    local face = PE.FaceBars
    if type(face) ~= "table" then return nil end
    local fn = face[name]
    if type(fn) ~= "function" then return nil end
    return face, fn
end

local SyncBars   -- below
local onFaceOff  -- made once: FaceBars.lua's safety net turned the pictures off

-- The Spell panel size the bars and the pictures use this session: read at the first
-- placement, then kept (the pictures are built once). A change rewrites the frames and
-- asks for a reload, after which all of them are at the new size together.
local sessionSize
local function SessionSize()
    if not sessionSize then sessionSize = Plan.PanelSize(mod and mod.opts) end
    return sessionSize
end

local function StartFace()
    local face, start = FaceCall("Start")
    if not face then return end
    -- The bars go to full size once our pictures are off (PlaceNow), out of a fight.
    onFaceOff = onFaceOff or PE:Wrap("ctrlLayout", function() if wanted then SyncBars() end end)
    local ok, started, why = PE:Safe("ctrlLayout", start, face, onFaceOff, SessionSize())
    if ok and not started and PE.debugOn then
        PE:Debug("ctrlLayout", "spell pictures not shown: " .. tostring(why))
    end
end

local function StopFace()
    local face, stop = FaceCall("Stop")
    if face then PE:Safe("ctrlLayout", stop, face) end
end

-- The reason the game's own bars are showing, or nil. Reads only.
local function FaceStatus()
    local face, status = FaceCall("Status")
    if not face then return nil end
    local ok, why = pcall(status, face)
    if ok and type(why) == "string" and why ~= "" then return why end
    return nil
end

-- The round button works out its own spot again (Hub.lua asks HubSpot, below).
local function RefreshHub()
    local hub = PE.Hub
    if type(hub) == "table" and type(hub.Refresh) == "function" then PE:Safe("ctrlLayout", hub.Refresh, hub) end
end

-- Puts the bars back. The bottom anchor and the both-triggers bar, which the
-- game never re-anchors, go back to the points read before the first change.
-- The Top, Left and Right anchors follow the game's current Compact setting
-- (PageUnit:RefreshCompactLayout, PageUnit.lua:292-315), because a layout
-- picked meanwhile may have changed it: Compact on, all points on the bottom
-- anchor; Compact off, the game's own points for each, or ours if the game
-- keeps none. Every scale comes from what was read. The spell pictures stop first
-- (the real bars show again) and the pieces Edit Mode does not own come back, placed or
-- not: a hint box value saved at an earlier session is put back too.
local function RestoreNow()
    StopFace()
    Snap.SlimCall("Stop") -- the game's unit frames show again (0.17.0)
    Snap.ArrangeCall("Close", "the layout was put back") -- 0.18.0: the Arrange screen, if open
    RestoreScreen()
    if not placed then return end
    placed = false
    RefreshHub() -- the round button goes back to its own default spot
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

-- 0.20.0: saved data of an older version carried over, once. Called at login (OnLoad) and
-- again before the session's offsets are first used; what was done is marked in the saved
-- files, so a second call, and every later login, changes nothing. Two things: the old
-- switch for the spell wheels (here) and the built-in arrangement (in the function).
--
-- The row "Arrange: spell wheels" (opts.arrangeWheel) is gone: the piece is always listed.
-- An offset saved for it counted only while that switch was On, so one saved with the switch
-- Off (or never set) was never applied and must not suddenly apply: it is removed. The
-- switch was the account's and the offset is each character's, so the account's file keeps
-- what the switch was (opts.wheelWas: 1 On, 0 Off) for the characters that log in later, and
-- each character's file is marked once it is done (ctrlArrange.wheel = 1).
Snap.Carry = function()
    local opts = type(mod and mod.opts) == "table" and mod.opts or nil
    if not opts then return end
    if opts.arrangeWheel ~= nil then
        opts.wheelWas = opts.arrangeWheel == 1 and 1 or 0
        opts.arrangeWheel = nil
    end
    -- The built-in arrangement (Plan.BASE_2): saved offsets are counted from it from now on,
    -- so each piece's amount is taken off its saved offset, once, and the piece stays where
    -- it was. With "Arrange it yourself" On and at least one piece moved, the offsets were in
    -- use, so a piece with none saved (it stood at the old built-in spot) gets minus its
    -- amount too; with On and nothing moved the screen was never arranged and takes the new
    -- spots. With it Off they
    -- were not in use: the screen takes the new spots, and only an offset that is saved is
    -- changed, for the day the switch goes On again. The Edit Mode pieces' offsets are the
    -- account's (opts.offsets, marked opts.arrangeBase); the live pieces' are each
    -- character's (ctrlArrange.offsets, marked ctrlArrange.base) and are carried over at
    -- that character's own first login. What our Edit Mode layout holds is not touched and
    -- neither is its record (see Plan.Pending).
    local inUse = opts.arrange == 1
    local function said(list)
        if not PE.debugOn then return end
        for _, m in ipairs(list) do
            PE:Debug("ctrlLayout", "arrange: moved into the built-in spots: " .. m.key .. " " .. PE.Plain(m.fromX) .. ","
                .. PE.Plain(m.fromY) .. " -> " .. PE.Plain(m.x) .. "," .. PE.Plain(m.y))
        end
    end
    if not (type(opts.arrangeBase) == "number" and opts.arrangeBase >= Plan.ARRANGEMENT) then
        -- The Edit Mode pieces stay where the layout holds them while the switch is On,
        -- moved or not: a new spot for them would wait for an Apply nobody asked for.
        if inUse and type(opts.offsets) ~= "table" then opts.offsets = {} end
        local list = Plan.MigrateBase(opts.offsets, opts.arrangeBase, "apply", inUse)
        opts.arrangeBase = Plan.ARRANGEMENT -- marked before anything else can go wrong
        said(list)
    end
    local char = CharDB()
    local store = char and char.ctrlArrange
    if type(store) ~= "table" then return end -- nothing saved for this character
    if not (type(store.base) == "number" and store.base >= Plan.ARRANGEMENT) then
        -- The live pieces: a character with the switch On and nothing moved was never
        -- arranged, and takes the new spots.
        local arranged = inUse and type(store.offsets) == "table" and next(store.offsets) ~= nil
        local list = Plan.MigrateBase(store.offsets, store.base, "live", arranged)
        store.base = Plan.ARRANGEMENT
        said(list)
    end
    if store.wheel ~= 1 then
        store.wheel = 1
        local e = type(store.offsets) == "table" and store.offsets["spell wheels"] or nil
        if e ~= nil and opts.wheelWas ~= 1 then
            store.offsets["spell wheels"] = nil
            if PE.debugOn then
                PE:Debug("ctrlLayout", "arrange: spell wheels: an offset saved while their old switch was Off ("
                    .. (type(e) == "table" and (PE.Plain(e.x) .. "," .. PE.Plain(e.y)) or "not readable")
                    .. ") is removed: it was never applied")
            end
        end
    end
end

-- 0.18.0: what this session is drawn with, as one options table for the plan: the Spell panel
-- size and Slim bars of the session, the rows that count at once, and, when the session
-- began with "Arrange it yourself" On, the saved offsets themselves (by reference: a step in
-- the Arrange screen is seen at once). The first call decides the session: On sets
-- Plan.session, so every function of the plan adds the offsets, and tells Arrange.lua once;
-- Off sets nothing. nil before the options are loaded.
Snap.View = function()
    local opts = type(mod and mod.opts) == "table" and mod.opts or nil
    if not opts then return nil end
    if Snap.arrangeOn == nil then
        Snap.Carry() -- 0.20.0: saved data of an older version, before it is used
        if PE.debugOn then PE:Debug("ctrlLayout", "arrange: built-in arrangement " .. Plan.ARRANGEMENT) end
        if Snap.arrangeLogin == nil then Snap.arrangeLogin = opts.arrange == 1 end
        Snap.arrangeOn = Snap.arrangeLogin
        if Snap.arrangeOn then
            if type(opts.offsets) ~= "table" then opts.offsets = {} end
            local char = CharDB() or {} -- not loaded (never seen): the moves last for the session
            -- A table made now holds nothing an older version saved: marked as carried over.
            if type(char.ctrlArrange) ~= "table" then char.ctrlArrange = { wheel = 1, base = Plan.ARRANGEMENT } end
            if type(char.ctrlArrange.offsets) ~= "table" then char.ctrlArrange.offsets = {} end
            if type(char.ctrlArrange.alone) ~= "table" then char.ctrlArrange.alone = {} end
            Snap.view = { arrange = 1, offsets = opts.offsets, charOffsets = char.ctrlArrange.offsets,
                alone = char.ctrlArrange.alone }
            Plan.session = Snap.view
        else
            Snap.view = { arrange = 0 }
        end
    end
    local view = Snap.view
    view.panelSize = SessionSize()
    view.hints, view.mapButtons = opts.hints, opts.mapButtons
    -- 0.19.0: the map look counts at once (the size it asks of Edit Mode follows the reload).
    view.mapLook = Plan.MapLook(opts)
    Plan.look = view.mapLook == 1 and 1 or nil
    view.slim = (Snap.slimOn == true or (Snap.slimOn == nil and opts.slim == 1)) and 1 or 0
    -- Our spell pictures are off (FaceBars.lua says why): no panel is drawn.
    view.faceOff = FaceStatus() ~= nil and true or nil
    if Snap.arrangeOn and not Snap.arrangeStarted then
        Snap.arrangeStarted = true
        Snap.ArrangeCall("Started")
    end
    return view
end

-- 0.18.0: "Arrange it yourself" is Off, yet our Edit Mode layout still holds moved pieces: the
-- row was tapped in a fight and the game reloaded before it ended, or the write failed. Once
-- a session, when the layout is placed (out of a fight): the pieces are written back to their
-- built-in spots and the reload is asked for. 0.20.0: the same when the layout was written
-- before a built-in spot changed (buffs and debuffs, Plan.BASE_2): the piece is written at
-- its new built-in spot, once, and the chat line says that instead. Only while Off: a move not yet applied in an
-- On session is never written by itself. After the write nothing waits, so it cannot loop;
-- a write that fails is not tried again until the next login.
Snap.ArrangeBack = function()
    local o = mod and mod.opts
    if type(o) ~= "table" or o.arrange == 1 or Snap.arrangeBack or not Snap.RewritePieces or Snap.RewritesWaiting() > 0 then return end
    if #Plan.Pending(o) == 0 or EditModeOpen() then return end
    -- A layout built from an older template is rebuilt whole at the next login (UpdateTemplate),
    -- built-in spots and all: nothing is written into it before that.
    if (type(o.template) == "number" and o.template or 1) < Plan.TEMPLATE then return end
    Snap.arrangeBack = true
    -- Nothing noted as written for any of them: the layout holds the spots of an older version.
    local older = true
    for _, key in ipairs(Plan.Pending(o)) do
        if type(o.offsetsWritten) == "table" and o.offsetsWritten[key] ~= nil then older = false end
    end
    if PE.debugOn then
        PE:Debug("ctrlLayout", (older and "arrange: the layout holds the built-in spots of an older version ("
            or "arrange: the switch is Off but the layout still holds moved pieces (")
            .. table.concat(Plan.Pending(o), ", ") .. "): written " .. (older and "at" or "back to") .. " their built-in spots")
    end
    if Snap.RewritePieces(Snap.ArrangeFilter, nil) and Snap.lastWrite and Snap.lastWrite.ok then
        PE:Print(older and "The controller layout has a new built-in arrangement. Open the settings and tap Reload now to finish."
            or "Arrange it yourself is Off: the pieces you had moved go back. Open the settings and tap Reload now to finish.")
    end
end

local function PlaceNow()
    Snap.View() -- 0.18.0: the session's offsets are known before anything is placed
    PlaceScreen() -- the hint box, the chat's box, the map's border and buttons go with our layout, bars or not
    -- 0.17.0: and so do the slim bars, when the session began with their switch on.
    if Snap.slimOn == nil then Snap.slimOn = type(mod and mod.opts) == "table" and mod.opts.slim == 1 end
    if Snap.slimOn then
        local started, why = Snap.SlimCall("Start")
        if started == false and PE.debugOn then PE:Debug("ctrlLayout", "slim bars not shown: " .. tostring(why)) end
    end
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
    local spots = Plan.BarSpots(SessionSize())
    placed = true
    RefreshHub() -- the round button takes the layout's spot
    for _, b in ipairs(BAR_FRAMES) do
        local spot = spots[b.spot]
        Put(frames[b.spot], spot.x, spot.y, spot.s)
    end
    PlaceExtras()
    if PE.debugOn then PE:Debug("ctrlLayout", "bars placed") end
    StartFace()
    -- Our pictures are off (FaceStatus says why): the game's bars show, at full size.
    if FaceStatus() then
        local full = Plan.FullBarSpots()
        full.bottom = spots.bottom -- 0.18.0: the same anchor either way, so with the spell wheels' offset
        for _, b in ipairs(BAR_FRAMES) do
            local spot = full[b.spot]
            Put(frames[b.spot], spot.x, spot.y, spot.s)
        end
        if PE.debugOn then PE:Debug("ctrlLayout", "bars at full size: the spell pictures are off") end
    end
    Snap.ArrangeCall("Placed") -- 0.18.0: our own panels and bars follow a move made this session
    Snap.ArrangeBack()
end

-- Places the bars while the feature is on and our layout is the active one,
-- else puts them back; out of combat. Safe to call in any state.
SyncBars = function()
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
    table.insert(list, newIndex - state.numPresets, layout) -- no local for it: the file is at Lua's 200 locals
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
    Plan.MarkWritten(mod.opts, Plan.Pieces(mod.opts)) -- 0.18.0: the offsets it was built with
    if PE.debugOn then PE:Debug("ctrlLayout", "saved the Pocket Essentials layout at index " .. newIndex) end
    return true, true
end

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
    Plan.MarkWritten(mod.opts, Plan.Pieces(mod.opts)) -- 0.18.0
    if PE.debugOn then PE:Debug("ctrlLayout", "the Pocket Essentials layout was rebuilt from the template") end
    return true
end

-- The saved template version (none saved: 0.11.x, version 1).
local function SavedTemplate()
    local v = mod.opts.template
    return type(v) == "number" and v or 1
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
        -- Built from an older template: rebuilt first, so this one reload brings the new
        -- arrangement (the next login would otherwise rebuild it and ask for a second
        -- reload). A failure is logged; the next login tries again.
        if SavedTemplate() < Plan.TEMPLATE then Rebuild() end
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

local TEXT_START_OVER = "Tap Start over again to put every piece back. Changes you made in Edit Mode are lost."
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
    applied.panelSize = Plan.PanelSize(opts)
end

-- Which pieces of Plan.Pieces each row rewrites: its own swing timer only (one
-- setup since 0.12.0: the stack's spots no longer depend on what is shown); the Spell
-- panel size the three unit frames, and since 0.16.0 the chat and the tooltip, which
-- rise with them.
local function Timer(index) return function(p) return p.system == "SwingTimer" and p.index == index end end
local REWRITES = {
    ranged = Timer("Ranged"),
    mainHand = Timer("MainHand"),
    offHand = Timer("OffHand"),
    -- The Spell panel size: the player, pet and target frames (they rise at 110% and 120%),
    -- the chat over them and the tooltip over the target of target. The pictures and the
    -- real bars take the new size after the reload asked for.
    panelSize = function(p) return p.system == "UnitFrame" or p.system == "ChatFrame" or p.system == "HudTooltip" end,
    -- 0.17.0, Slim bars: the tooltip's spot (the corner while they are on).
    slim = function(p) return p.system == "HudTooltip" end,
    -- 0.19.0, Map look: the map (its size and spot) and the three swing timers (14 up with Square).
    mapLook = function(p) return p.system == "Minimap" or p.system == "SwingTimer" end,
}

local function RunRewrites()
    if not wanted or #pendingRewrites == 0 then return end -- kept for the next switch-on
    local list = pendingRewrites
    pendingRewrites = {}
    local state, pos, e = ReadOurs()
    if not state then
        -- 0.18.0: every way out says how it went (Snap.lastWrite, and Arrange.lua when its session is on).
        Snap.lastWrite = { ok = false, why = "the Pocket Essentials layout could not be read or is not saved" }
        Snap.ArrangeCall("Written", false, Snap.lastWrite.why)
        return
    end
    local all = Plan.Pieces(mod.opts)
    local picked, keys = {}, {}
    for i, p in ipairs(all) do
        for _, r in ipairs(list) do
            if r.keep(p) then
                picked[i] = true
                if p.arrange then keys[p.arrange] = true end
                break
            end
        end
    end
    -- 0.18.0: a piece of Plan.ARRANGE that is several Edit Mode pieces (the three swing timers)
    -- is written whole, so its parts can never hold different offsets.
    local pieces = {}
    for i, p in ipairs(all) do
        if picked[i] or (p.arrange and keys[p.arrange]) then pieces[#pieces + 1] = p end
    end
    Plan.Apply(state.saved[pos], pieces, e) -- our entry, in place (GetLayouts gave a copy)
    local ok, err = SaveAll(state, state.saved)
    if not ok then
        PE:LogError("ctrlLayout", err)
        Snap.lastWrite = { ok = false, why = tostring(err) }
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
        Snap.ArrangeCall("Written", false, Snap.lastWrite.why)
        return
    end
    Snap.lastWrite = { ok = true }
    Plan.MarkWritten(mod.opts, pieces, all) -- 0.18.0: which offsets our layout holds now
    if PE.debugOn then
        local keys, seen = {}, {}
        for _, p in ipairs(pieces) do
            if p.arrange and not seen[p.arrange] and (p.dx ~= 0 or p.dy ~= 0) then
                seen[p.arrange] = true
                keys[#keys + 1] = p.arrange .. " " .. p.dx .. "," .. p.dy
            end
        end
        for i = 1, #keys, 4 do -- four to a line: the log cuts a line at 200 characters
            PE:Debug("ctrlLayout", "arrange: written into the layout with their offsets: "
                .. table.concat(keys, "; ", i, math.min(i + 3, #keys)))
        end
    end
    mod:RequestReload(RELOAD_REASON)
    Snap.ArrangeCall("Written", true)
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

-- 0.18.0: for Snap.ArrangeBack, which is defined above it.
Snap.RewritePieces = function(filter, key) return RewritePieces(filter, key) end
Snap.RewritesWaiting = function() return #pendingRewrites end

-- OnChange of a row: rewrites its pieces in our layout.
local function NONE() return false end

local function LayoutRow(key)
    return function()
        local filter = REWRITES[key]
        -- A size change that leaves the frames at the same height (for example 80%
        -- to 100%) rewrites no frame, so moves made in Edit Mode stay; the reload
        -- is still asked for (the pictures and the real bars take the new size).
        if key == "panelSize"
            and Geometry({ panelSize = applied.panelSize }).frameY
                == Geometry({ panelSize = mod.opts.panelSize }).frameY then
            filter = NONE
        end
        RewritePieces(filter, key)
    end
end

local function RunStartOver()
    if not wanted then return end
    if Rebuild() then mod:RequestReload(RELOAD_REASON) end
end

-- At a login with ours active and built from an older template: rebuilt once from
-- the template (Start over's steps), the reload asked for, and said in chat. A tap on
-- the switch that makes an older layout of ours active rebuilds it there (SwitchOn);
-- one that finds it active already keeps it as it is (until the next login). A failure
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
    { key = "panelSize", label = "Spell panel size", OnChange = LayoutRow("panelSize"),
      number = { min = 80, max = 120, step = 10, default = Plan.PANEL_SIZE_DEFAULT, suffix = "%", unit = "of normal" } },
    { key = "ranged", label = "Ranged timer", choices = VISIBILITY, OnChange = LayoutRow("ranged") },
    { key = "mainHand", label = "Main hand timer", choices = VISIBILITY, OnChange = LayoutRow("mainHand") },
    { key = "offHand", label = "Off hand timer", choices = VISIBILITY, OnChange = LayoutRow("offHand") },
    -- 0.16.0: these two change no Edit Mode piece, so no rewrite and no reload: the
    -- screen is placed again (out of a fight) while the layout is on.
    { key = "hints", label = "Controls reminder", choices = { { value = 0, label = "Off" }, { value = 1, label = "On" } },
      OnChange = function()
          hintsTapped = true
          if wanted then SyncBars() end
      end },
    -- With the square map the strip these buttons sit beside is hidden: the row's name then
    -- reads "Map buttons: Round map only" and a tap is only remembered for the round map.
    { key = "mapButtons", label = "Map buttons", choices = { { value = 0, label = "Hidden" }, { value = 1, label = "Shown" } },
      value = function(m) if Plan.MapLook(m.opts) == 1 then return "Round map only" end end,
      OnChange = function() if wanted and Plan.MapLook(mod.opts) ~= 1 then SyncBars() end end },
    { label = "Rebuild the layout", button = "Start over", action = function() StartOver() end },
}
-- The rows for the newer parts, each Off (or as before) until tried on the device. (0.20.0:
-- the seven "Part: ..." rows that stood here are gone, see Plan.GONE.)
do
    local ON_OFF = { { value = 0, label = "Off" }, { value = 1, label = "On" } }
    -- 0.17.0: the slim bars (SlimBars.lua), Off by default. The tooltip's spot is a piece of
    -- our Edit Mode layout, so a change rewrites that piece (out of a fight) and asks for the
    -- reload; the bars themselves start or stop with that reload (Snap.slimOn).
    OPTIONS[#OPTIONS + 1] = { key = "slim", label = "Slim bars", choices = ON_OFF, OnChange = function()
        if RewritePieces(REWRITES.slim, "slim") and not Snap.slimTold then
            Snap.slimTold = true
            PE:Print("Slim bars count from the next reload.")
        end
    end }
    -- 0.20.0: the names on the slim bars (SlimBars.lua). It changes no Edit Mode piece: the
    -- bars read their names again at once, in a session that began with Slim bars On.
    OPTIONS[#OPTIONS + 1] = { key = "slimNames", label = "Names on the bars",
        choices = { { value = 1, label = "Whole name" }, { value = 0, label = "First name" } },
        OnChange = function() Snap.SlimCall("SetNames", mod.opts.slimNames) end }
    -- 0.19.0: the map's look, Round by default. Square asks Edit Mode for another size and spot,
    -- so a change goes the way the Spell panel size does: the map and the timers are rewritten
    -- in our layout (out of a fight) and the reload is asked for. What MapLook.lua draws (the
    -- mask, the edge, the words) follows the row at once.
    OPTIONS[#OPTIONS + 1] = { key = "mapLook", label = "Map look",
        choices = { { value = 0, label = "Round" }, { value = 1, label = "Square, bigger" } }, OnChange = function()
            if not RewritePieces(REWRITES.mapLook, "mapLook") then return end
            if PE.debugOn then
                PE:Debug("ctrlLayout", "map look: the row is now " .. (Plan.MapLook(mod.opts) == 1 and "the square map" or "the round map")
                    .. "; the map's size follows the next reload")
            end
            if wanted then SyncBars() end
        end }
    -- 0.18.0: arrange it yourself (Arrange.lua), Off by default. A change counts from the
    -- next reload: the Edit Mode pieces whose offset in our layout is not what the new value
    -- asks for (On: the saved offsets; Off: none) are rewritten, out of a fight, and the
    -- reload is asked for. What the session started with decides the rest (Snap.View).
    OPTIONS[#OPTIONS + 1] = { key = "arrange", label = "Arrange it yourself", choices = ON_OFF, OnChange = function()
        if not RewritePieces(Snap.ArrangeFilter, "arrange") then return end
        if mod.opts.arrange ~= 1 then Snap.ArrangeCall("Close", "the switch was set to Off") end
        if PE.debugOn then
            PE:Debug("ctrlLayout", "arrange: the switch is now " .. tostring(mod.opts.arrange) .. "; it counts from the next reload")
        end
        if not Snap.arrangeTold then
            Snap.arrangeTold = true
            PE:Print("Arrange it yourself counts from the next reload.")
        end
    end }
    -- (0.20.0: the row "Arrange: spell wheels" that stood here is gone; the piece is always
    -- in the Arrange window. See Snap.Carry.)
    OPTIONS[#OPTIONS + 1] = { label = "Arrange the screen", button = "Arrange", action = function()
        Snap.View()
        if Snap.arrangeOn ~= true then
            PE:Print(mod.opts.arrange == 1 and "Arrange it yourself starts with the next reload. Tap Reload now first."
                or "Switch on Arrange it yourself first, then reload.")
            return
        end
        if mod.opts.arrange ~= 1 then
            PE:Print("Arrange it yourself is Off from the next reload.")
            return
        end
        Snap.ArrangeCall("Open")
    end }
    -- 0.22.0 (Batch.lua): one switch for each part of the batch, all Off until tried on the
    -- device, under their own heading. `always`: they also show while the layout is Off, since
    -- some of them do not need it. Turn all on and Turn all off only flip the rows.
    OPTIONS[#OPTIONS + 1] = { heading = PE.Batch.VERSION, always = true }
    OPTIONS[#OPTIONS + 1] = { label = "Everything in " .. PE.Batch.VERSION, always = true, buttons = {
        { label = "Turn all on", action = function() PE.Batch.SetAll(true) mod:RefreshPanel() end },
        { label = "Turn all off", action = function() PE.Batch.SetAll(false) mod:RefreshPanel() end },
    } }
    for _, row in ipairs(PE.Batch.ROWS) do
        local key = row.key
        OPTIONS[#OPTIONS + 1] = { key = key, label = row.label .. (row.reload and " (reload)" or ""), choices = ON_OFF, always = true,
            OnChange = function() PE.Batch.Changed(key) end }
    end
    -- Where the buff timer bars sit (used by a later part of the batch).
    OPTIONS[#OPTIONS + 1] = { key = "b22BarsSide", label = "Buff timer bars", always = true,
        choices = { { value = 0, label = "Left, by your name" }, { value = 1, label = "Right, by the target" } } }
end
-- 0.16.4, for the device test (spec 2026-11-24-0.16.4-cleanup.md, 6 and 7): a numbered mark
-- in the debug log, and the snapshot (the block at the end of the file). `always`: the two
-- rows also show while the layout is off, to record what "everything put back" looks like.
OPTIONS[#OPTIONS + 1] = { label = "Mark a test section", button = "Mark", always = true,
    action = function() PE:MarkSection() end }
OPTIONS[#OPTIONS + 1] = { label = "Save a snapshot", button = "Snapshot", always = true,
    action = function() Snap.Take() end }

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
defaults.panelSize = Plan.PANEL_SIZE_DEFAULT
defaults.prev = false -- the 0.11.0 file's single layout to go back to; read once, then false
-- 0.22.0: every batch row starts Off (Batch.lua); the buff timer bars start on the left.
for _, row in ipairs(PE.Batch.ROWS) do defaults[row.key] = 0 end
defaults.b22BarsSide = 0
-- (opts.prevs, 0.11.1's entries by character name, is only read: Migrate. Each
-- character's entry now lives in its own saved file, PE.charDB.ctrlLayoutPrev.)

mod = PE:RegisterModule({
    key = "ctrlLayout",
    label = "Controller layout",
    desc = "Map bottom middle, a spell panel each side (hold LT or RT to swap), chat on the left above the PE button.",
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
        elseif wanted and #pendingRewrites > 0 and PE:InCombat() then
            waitText = TEXT_WAIT_FIGHT -- an option change waiting for the fight to end
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
        if index and state.active == index then
            local lines = { TEXT_USING }
            local why = FaceStatus()
            if why then lines[2] = TEXT_FACE_OFF .. why .. (why:find("[.!]$") and "" or ".") end
            -- 0.17.0: and why the slim bars are off, when their switch is on and they are not.
            why = Snap.SlimCall("Status")
            if type(why) == "string" and why ~= "" then
                lines[#lines + 1] = "Pocket Essentials' slim bars are off: " .. why .. (why:find("[.!]$") and "" or ".")
            end
            -- 0.19.0: the game refused the square mask (MapLook.lua says so in plain words).
            local look = PE.MapLook
            if type(look) == "table" and type(look.Status) == "function" then
                local ok, text = pcall(look.Status, look)
                if ok and type(text) == "string" and text ~= "" then lines[#lines + 1] = text end
            end
            -- 0.19.0: pieces of this session's screen that overlap, with the square map. 0.20.0: with
            -- the round one too (the built-in arrangement does not fit the two largest Spell
            -- panel sizes); only said when the check really finds a pair.
            if type(Snap.view) == "table" then
                local n = 0
                for _, o in ipairs(Plan.Overlaps(Plan.Rects(Snap.view))) do
                    -- As the Arrange window counts them: the rooms kept for the buff boxes are not
                    -- pieces yet (nothing is drawn there).
                    if o.a:sub(-5) ~= " room" and o.b:sub(-5) ~= " room" then n = n + 1 end
                end
                if n > 0 then
                    local count = n .. (n == 1 and " pair of pieces overlaps" or " pairs of pieces overlap")
                    lines[#lines + 1] = (Snap.view.mapLook == 1 and "With the square map " or "") .. count
                        .. ". Arrange the screen shows which, and moves them."
                end
            end
            return #lines == 1 and TEXT_USING or lines
        end
        return TEXT_ANOTHER
    end,

    -- At login, on or off. While off this is the module's one piece of work: when a layout is
    -- remembered for this character (it was switched off on another one), Settle puts it back.
    -- With the feature on, OnEnable (right after) does the same check.
    OnLoad = function(self)
        if type(self.opts) ~= "table" then return end
        -- 0.20.0: values saved for rows that are gone (the "Part: ..." rows) are removed.
        for _, key in ipairs(Plan.GONE) do self.opts[key] = nil end
        Snap.Carry() -- offsets saved for the older built-in arrangement, and the old wheels switch
        -- A Spell panel size that is not one of the five shows and reads as 100%.
        self.opts.panelSize = Plan.PanelSize(self.opts)
        Snap.arrangeLogin = self.opts.arrange == 1 -- 0.18.0: the session's value (Snap.View)
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
        StopFace() -- at once, also in a fight: the game's bars show again
        RestoreBars() -- bars placed by any path are always put back
        if not ThisPrev() and not HasOldEntry() then return end -- nothing was changed for this character
        PE:RunOutOfCombat("ctrlLayout:off", function() SwitchOff(false) end)
    end,
})

-- The PE button's default spot (Hub.lua): point, x, y on UIParent while the bars are
-- placed by us, else nil. "Placed" is what SyncBars decides: the switch is on and our layout
-- is the active one. Reads only.
function mod:HubSpot()
    if not (wanted and placed) then return nil end
    return Plan.HubSpot(SessionSize())
end
PE.ControllerLayout = mod

---------------------------------------------------------------------------
-- 0.16.4: the snapshot (spec 2026-11-24-0.16.4-cleanup.md, 7). One tap writes to the debug
-- log, once, where every piece of the layout is: the game's frames it places or moves, our
-- own panels, and the PE button; then each pair of visible pieces that overlap. For a
-- device test: one file then says what a screenshot shows.
--
--   mod:Snapshot()             true when written. With the Debug log off, or in a fight, it
--                              says so in chat and returns false; in a fight it is written
--                              when the fight is over (PE:RunOutOfCombat), since the game
--                              may hide a frame's place in a fight.
--   mod:AddSnapshotSource(fn)  another part's pieces: fn(add) calls add(name, region) for
--                              each (region nil: written as "not found"), or
--                              add(name, region, { skip = true }) for one that is listed but
--                              not checked for overlaps.
--
-- It only reads: each region's own IsVisible, GetLeft, GetBottom, GetWidth, GetHeight,
-- GetEffectiveScale, GetAlpha and GetParent (engine methods:
-- Blizzard_APIDocumentationGenerated/SimpleScriptRegionAPIDocumentation.lua:178, 582,
-- SimpleRegionAPIDocumentation.lua:38). No frame is made, nothing is hooked, nothing ticks.
-- Numbers are UI units from the screen's bottom left (a region's own numbers times its
-- scale over UIParent's), the unit of Edit Mode and of Plan.Rects. A value the game hides
-- is written "<secret>" and that piece is left out of the overlap check.
--
-- The game's frames, by the names their XML gives them (paths under Interface/AddOns/):
-- MinimapCluster and its ZoneTextButton, Minimap (Blizzard_Minimap/Mainline/Minimap.xml:24, 56),
-- ChatFrame1, BuffFrame and DebuffFrame (Blizzard_BuffFrame/BuffFrame.xml:6, 87),
-- ObjectiveTrackerFrame (Blizzard_ObjectiveTracker/Blizzard_ObjectiveTracker.xml:3),
-- MainStatusTrackingBarContainer and SecondaryStatusTrackingBarContainer
-- (Blizzard_StatusTrackingBar/Mainline/StatusTrackingBar.xml:41, 49), PlayerFrame, PetFrame
-- (Blizzard_UnitFrame/Mainline/PetFrame.xml:11), TargetFrame and its totFrame,
-- GameTooltipDefaultContainer (Blizzard_GameTooltip/Mainline/GameTooltip.xml:242),
-- SwingTimerMainHandFrame, SwingTimerOffHandFrame, SwingTimerRangedFrame
-- (Blizzard_SwingTimer/Blizzard_SwingTimer.xml:56, 69, 82), GamepadPersistentInputLegend
-- (Blizzard_Gamepad/UI/PersistentInputLegend/GamepadPersistentInputLegend.xml:38), and on
-- GamepadMainActionBarFrame.PageUnit the four anchors with their bars, LeftClassAction,
-- RightClassAction, LeftInputPrompt, RightInputPrompt and the two shoulder pictures
-- (Blizzard_GamepadActionBars/MainActionBarFrame.xml:18-26, 94-135).
---------------------------------------------------------------------------

-- In a function of its own, not a do block: this far down the file every one of its (nearly
-- 200) top-level locals is in scope, and a block's locals count on top of them.
Snap.Build = function()
    local floor, format = math.floor, string.format
    local SECRET = "<secret>"
    local LINE_ROOM = 150 -- a snapshot line's own text; the log cuts a whole line at 200
    local taken = 0

    -- One of a region's own methods, called: its first answer, SECRET for a hidden one,
    -- nil when the method is missing or raises.
    local function Read(region, method)
        local fn = region[method]
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, region)
        if not ok then return nil end
        if issecretvalue ~= nil and issecretvalue(v) == true then return SECRET end
        return v
    end

    local function Num(v)
        if v == SECRET then return SECRET end
        if type(v) ~= "number" then return "?" end
        return format("%.1f", v)
    end

    -- The pieces this file knows, in the order written.
    local function BuiltIn(add)
        local SKIP = { skip = true }
        local cluster = type(MinimapCluster) == "table" and MinimapCluster or nil
        add("map", cluster, SKIP) -- the map's whole box: the round map and the strip are listed themselves
        add("round map", Minimap, { with = "map's black disc" })
        add("map title strip", Child(cluster, "ZoneTextButton"))
        add("map's black disc", Snap.disc(), { with = "round map" })
        -- 0.19.0: with the square map, its edge, its words and what the game hangs on the map
        -- (MapLook.lua; nothing while Round).
        local look = Child(PE, "MapLook")
        if look and type(look.SnapshotPieces) == "function" then
            local ok, list = pcall(look.SnapshotPieces, look)
            for _, p in ipairs((ok and type(list) == "table") and list or {}) do add(p[1], p[2], p[3]) end
        end
        add("chat", ChatFrame1)
        add("buffs", BuffFrame)
        add("debuffs", DebuffFrame)
        add("quest tracker", ObjectiveTrackerFrame)
        add("XP bar 1", MainStatusTrackingBarContainer)
        add("XP bar 2", SecondaryStatusTrackingBarContainer)
        add("player", PlayerFrame)
        add("pet", PetFrame)
        local target = type(TargetFrame) == "table" and TargetFrame or nil
        add("target", target)
        add("target of target", Child(target, "totFrame"))
        add("tooltip spot", GameTooltipDefaultContainer, SKIP) -- the box the tooltip is pinned in, not the tooltip
        add("main hand timer", SwingTimerMainHandFrame)
        add("off hand timer", SwingTimerOffHandFrame)
        add("ranged timer", SwingTimerRangedFrame)
        add("hint box", GamepadPersistentInputLegend)
        local pageUnit = Child(GamepadBar(), "PageUnit")
        for _, b in ipairs({ { "main", "TopCenteredAnchor" }, { "LT", "LeftCenteredAnchor" }, { "RT", "RightCenteredAnchor" },
            { "LT+RT", "BottomCenteredAnchor" } }) do
            local anchor = Child(pageUnit, b[2])
            add("bar anchor " .. (b[1] == "LT+RT" and "bottom" or b[1]), anchor, SKIP)
            add("game bar " .. b[1], Child(anchor, "Bar"))
        end
        -- The prompt sits 1 unit into its button by the game's own design (MainActionBarFrame.xml:94-135).
        add("LB+LT button", Child(pageUnit, "LeftClassAction"), { with = "LB+LT prompt" })
        add("LB+LT prompt", Child(pageUnit, "LeftInputPrompt"), { with = "LB+LT button" })
        add("RB+RT button", Child(pageUnit, "RightClassAction"), { with = "RB+RT prompt" })
        add("RB+RT prompt", Child(pageUnit, "RightInputPrompt"), { with = "RB+RT button" })
        add("LB targeting picture", Child(pageUnit, "LeftShoulderBackground"))
        add("RB targeting picture", Child(pageUnit, "RightShoulderBackground"))
        -- Ours: FaceBars.lua's eight panel halves and the two frames under them that take a tap.
        local face = Child(PE, "FaceBars")
        local view, backing = Child(face, "view"), Child(face, "backing")
        for gi, key in ipairs({ "main", "lt", "rt", "both" }) do
            local halves = Child(Child(view, gi), "halves")
            add(key .. " d-pad panel", Child(halves, 1))
            add(key .. " face panel", Child(halves, 2))
        end
        add("tap guard left", Child(backing, 1), SKIP)
        add("tap guard right", Child(backing, 2), SKIP)
        add("PE button", Child(Child(PE, "Hub"), "button"))
    end

    -- Where a region is: { line = text after the name, rect = { l, b, r, t } or nil when it
    -- is hidden, fully see-through, hidden by the game or has no place yet }.
    local function Measure(region, ui)
        local visible = Read(region, "IsVisible")
        local eff = Read(region, "GetEffectiveScale")
        local l, b = Read(region, "GetLeft"), Read(region, "GetBottom")
        local w, h = Read(region, "GetWidth"), Read(region, "GetHeight")
        local alpha, f = 1, region
        for _ = 1, 12 do
            if type(f) ~= "table" then break end
            local a = Read(f, "GetAlpha")
            if a == SECRET then alpha = SECRET break end
            if type(a) == "number" then alpha = alpha * a end
            f = Read(f, "GetParent")
        end
        local k = (type(eff) == "number" and ui > 0) and eff / ui or nil
        local function U(v) return (type(v) == "number" and k) and v * k or v end
        l, b, w, h = U(l), U(b), U(w), U(h)
        local state = (visible == SECRET and SECRET) or (visible == true and "shown") or "hidden"
        local text = state .. " | l=" .. Num(l) .. " b=" .. Num(b) .. " w=" .. Num(w) .. " h=" .. Num(h)
            .. " s=" .. (k and format("%.2f", k) or Num(eff))
        if alpha == SECRET then
            text = text .. " a=" .. SECRET
        elseif alpha < 0.995 then
            text = text .. format(" a=%.2f", alpha)
        end
        local rect
        if visible == true and k and type(l) == "number" and type(b) == "number" and type(w) == "number" and type(h) == "number"
            and w > 0 and h > 0 and type(alpha) == "number" and alpha > 0.005 then
            rect = { l, b, l + w, b + h }
        end
        return text, rect
    end

    -- "label: a b c" in as many lines as LINE_ROOM needs; the later ones say "(more)".
    local function WriteList(label, items)
        local line, first = "", true
        local function Out()
            PE:Debug("snapshot", label .. (first and ": " or " (more): ") .. line)
            line, first = "", false
        end
        for _, item in ipairs(items) do
            if line ~= "" and #line + #item + 1 > LINE_ROOM then Out() end
            line = line == "" and item or (line .. " " .. item)
        end
        if line ~= "" or first then Out() end
    end

    local function Write()
        taken = taken + 1
        local n = taken
        PE:Debug("snapshot", "==== snapshot " .. n .. " ==== section " .. PE:Section())
        local ui = UIParent:GetEffectiveScale()
        PE:Debug("snapshot", format("screen %dx%d, UI scale %.2f", floor(UIParent:GetWidth() + 0.5),
            floor(UIParent:GetHeight() + 0.5), ui))
        local state, why = ReadState()
        if state and state.current then
            local index = OursIndex(state)
            PE:Debug("snapshot", 'Edit Mode layout "' .. PE.Plain(state.current.name) .. '" (ours: '
                .. ((index ~= nil and state.active == index) and "yes" or "no") .. ")")
        else
            PE:Debug("snapshot", "Edit Mode layout: not readable (" .. tostring(why or "no active layout") .. ")")
        end
        local items = {}
        for _, m in ipairs(PE.moduleList) do items[#items + 1] = m.key .. "=" .. tostring(PE:GetModuleState(m.key)) end
        WriteList("features", items)
        items = {}
        local opts = type(mod.opts) == "table" and mod.opts or {}
        local keys = {}
        for k, v in pairs(opts) do
            if type(k) == "string" and (type(v) == "number" or type(v) == "string" or type(v) == "boolean") then keys[#keys + 1] = k end
        end
        sort(keys)
        for _, k in ipairs(keys) do items[#items + 1] = k .. "=" .. PE.Plain(opts[k]) end
        WriteList("options", items)

        local pieces, missing = {}, 0
        local function add(name, region, flags)
            name = tostring(name)
            if type(region) ~= "table" then
                missing = missing + 1
                PE:Debug("snapshot", "piece: " .. name .. " | not found")
                return
            end
            local ok, text, rect = pcall(Measure, region, ui)
            if not ok then
                PE:Debug("snapshot", "piece: " .. name .. " | not readable")
                return
            end
            PE:Debug("snapshot", "piece: " .. name .. " | " .. text)
            flags = type(flags) == "table" and flags or nil
            pieces[#pieces + 1] = { name = name, rect = (not (flags and flags.skip)) and rect or nil, with = flags and flags.with }
        end
        BuiltIn(add)
        for i, source in ipairs(Snap.sources) do
            local ok, err = pcall(source, add)
            if not ok then PE:Debug("snapshot", "source " .. i .. " failed: " .. tostring(err)) end
        end

        local overlaps = 0
        for i = 1, #pieces do
            local a = pieces[i]
            for j = i + 1, #pieces do
                local b = pieces[j]
                if a.rect and b.rect and a.with ~= b.name and b.with ~= a.name then
                    local w = math.min(a.rect[3], b.rect[3]) - math.max(a.rect[1], b.rect[1])
                    local h = math.min(a.rect[4], b.rect[4]) - math.max(a.rect[2], b.rect[2])
                    if w > 0.05 and h > 0.05 then
                        overlaps = overlaps + 1
                        local first, second = a.name, b.name
                        if second < first then first, second = second, first end
                        PE:Debug("snapshot", format("overlap: %s + %s | %.1f x %.1f units (%d x %d px)", first, second, w, h,
                            floor(w * ui + 0.5), floor(h * ui + 0.5)))
                    end
                end
            end
        end
        PE:Debug("snapshot", "==== snapshot " .. n .. " end ==== " .. (#pieces + missing) .. " pieces, " .. missing
            .. " not found, " .. overlaps .. (overlaps == 1 and " overlap" or " overlaps"))
        PE:Print("Snapshot " .. n .. " saved to the debug log.")
    end

    Snap.Take = function()
        if not PE.debugOn then
            PE:Print(PE.TEXT_DEBUG_FIRST)
            return false
        end
        if PE:InCombat() then
            PE:Print("In a fight: the snapshot is saved when the fight is over.")
            PE:RunOutOfCombat("ctrlLayout:snapshot", function()
                if PE.debugOn then PE:Safe("ctrlLayout", Write) end
            end)
            return false
        end
        return (PE:Safe("ctrlLayout", Write)) == true
    end

    function mod:Snapshot()
        return Snap.Take()
    end

    function mod:AddSnapshotSource(fn)
        if type(fn) == "function" then Snap.sources[#Snap.sources + 1] = fn end
    end
end
Snap.Build()

---------------------------------------------------------------------------
-- 0.18.0: what Arrange.lua asks of this file (spec 2026-11-24-0.18.0-arrange.md). In a
-- function, for the same reason as the snapshot.
--   mod:View()           the session's options table for the plan (Snap.View)
--   mod:ArrangeReady()   true while the session began with the switch On, the layout is on
--                        and its bars are placed; else false and why
--   mod:ArrangePlace()   the live pieces placed again from the plan, with the calls every
--                        placement makes (PlaceNow); "placed", or "held" in a fight (they
--                        are placed when it ends)
--   mod:ArrangeApply()   the Edit Mode pieces whose offset is not in our layout yet, written
--                        once (RewritePieces, the option rows' path), then one reload asked
--                        for. Returns true and how many pieces were written (a third answer
--                        "held": in a fight, they are written when it ends), or false and
--                        why (Edit Mode is open, or the write itself failed).
---------------------------------------------------------------------------
Snap.ArrangeBuild = function()
    function mod:View()
        return Snap.View()
    end

    function mod:ArrangeReady()
        Snap.View()
        if Snap.arrangeOn ~= true then return false, "Arrange it yourself was off when this session began" end
        if mod.opts.arrange ~= 1 then return false, "Arrange it yourself is Off from the next reload" end
        if not wanted then return false, "the Controller layout is off" end
        if not placed then return false, "the Controller layout is not placed (another Edit Mode layout is active?)" end
        return true
    end

    function mod:ArrangePlace()
        local held = PE:InCombat()
        SyncBars()
        return held and "held" or "placed"
    end

    function mod:ArrangeApply()
        local waiting = #Plan.Pending(mod.opts)
        if waiting == 0 then return true, 0 end
        Snap.lastWrite = nil
        if not RewritePieces(Snap.ArrangeFilter, nil) then return false, TEXT_EDIT_MODE end
        local result = Snap.lastWrite
        if result == nil then return true, waiting, "held" end -- in a fight: written when it ends
        if not result.ok then return false, result.why end
        return true, waiting
    end
end
Snap.ArrangeBuild()

-- From here on a switch-on is a tap, except the late one below.
PE:OnLogin(function() atLogin = false end)
