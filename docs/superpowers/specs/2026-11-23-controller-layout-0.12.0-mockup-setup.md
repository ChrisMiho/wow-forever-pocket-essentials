# Controller layout 0.12.0: the mockup's one setup, with the game's real bars

**Approval.** The owner, 2026-11-23, after the 0.11.2 device check: "right now,
i do not have the configuration we drew up in the mocks, that is what i want,
can you just do that, no more questions, make the ui in game, look like the
mockups". Approved by that instruction; built and published without a review
stop (memory: autonomous batches).

## Why

The owner wants the game playable. The setup chosen on the mockup
(`docs/ui-review/mockup-0.8.1.html`, view "Face bars (one setup)") draws all
four bars **whole**, so the game's own bars can sit exactly where the mockup
draws them: moving and sizing whole bars out of a fight is proven
(`docs/11-22-playsession/EVIDENCE.md`). No face of our own, no probe needed.

## Goals

- With Controller layout On, the screen matches the mockup's "Face bars (one
  setup)" view.
- An owner already on our layout gets it with no taps beyond one reload.
- One setup: the option rows that made other arrangements go away.

## Not goals

- Our own face frames, the split, faded bars. Per-character settings (next
  item). Moving the controller hints box.

## Anti-goals

- Anything changed in a fight. A player's own Edit Mode layout changed.
  Silent waiting: anything that waits says so in the status line.

## The setup (game units at UI scale 1, 1365 by 768; "up" = from the bottom edge, x from the centre)

| Piece | Where (mockup) | How |
|---|---|---|
| Map | bottom middle, 70%, round map centred 153 up | Edit Mode Minimap, Size for 70%, title strip underneath (0.11.1) |
| Map title strip (zone, clock) | right under the round map (56 to 75 up) | the game's header-underneath setting places it |
| Swing timers (main hand, off hand, ranged) | stacked right under the title strip (12 to 51 up), 180 wide | Edit Mode SwingTimer spots |
| LT bar | centre x -335, 133 up | our bar placement, scale 1 |
| Main bar (no trigger) | centre x -335, 45 up | same |
| RT bar | centre x +335, 133 up | same |
| LT+RT bar | centre x +335, 45 up | same, scale 1 (the 0.7 factor goes) |
| Sub-menu buttons (LB+LT, RB+RT) and LB/RB targeting circles | where the game puts them today: 138 either side of the map's centre, about 188 and 107 up | they ride on `BottomCenteredAnchor`; keep that anchor where it gives these spots. The two wheel circles (175 across) stay clear of the bars and frames |
| Player frame | left, right edge at x -236, 192 to 252 up | Edit Mode UnitFrame Player |
| Pet frame | above the player frame, right-aligned with it, 260 to 294 up | Edit Mode UnitFrame Pet |
| Target frame | mirror of the player frame (left edge at x +236) | Edit Mode UnitFrame Target |
| Target of target | above the target frame, mirror of the pet | only if the game has it as its own Edit Mode frame or a plain frame we may move out of a fight; otherwise it stays on the target frame (As built note) |
| Map icons (mail, the tracking "2" badge, day/night) | on the upper rim of the map, at -30°, top, +30° | only if they are plain frames the Camelot minimap code does not re-anchor; otherwise leave them (As built note) |
| XP bar, chat, buffs, debuffs, quest tracker | as 0.11.1 | unchanged |

The builder turns these into anchors from the Camelot source (frame sizes,
where each Edit Mode system anchors, how the minimap frame holds its title
strip) and checks for overlaps at 1365 by 768. Where the source shows the
mockup's number cannot work (a frame is bigger than drawn, a wheel circle
would be covered), the builder keeps the arrangement and moves the piece the
least, and writes it in "As built".

## One setup

- Rows removed from the Controller card: Main bar (above / under), Map size,
  Player and target frames, Swing timers (where), Spell button size and the
  three fine-tunes. Kept: the switch, the three timer visibility rows, Start
  over.
- Old saved values for the removed rows are ignored (left in the file,
  unused).

## Getting it without taps

- The template gets a version number (`TEMPLATE = 2`), saved with our layout
  when it is built (in the module's saved options).
- At a login with the switch On and ours active, when the saved template
  version is lower: rebuild our layout from the template (as Start over does,
  out of a fight, after Edit Mode's layouts are ready), ask for the reload,
  and say in chat: "The controller layout was updated to the new
  arrangement. Open the settings and tap Reload now to finish." Once per
  character's layout, never again for the same version.
- While it waits (fight, Edit Mode not ready), the status line says
  "Updating the layout after this fight" or "Waiting for the game's
  layouts".

## Tests

- Plan: every piece's spot and setting above; no piece overlaps another at
  1365 by 768 (rectangles from the plan's own sizes); the bars clear the two
  wheel circles.
- Rows: the removed rows are gone; old saved values do not change the plan.
- Template version: a login with an older version rebuilds once, asks the
  reload, says it in chat; the next login does nothing; in a fight it waits
  and the status line says so; a layout of the player's own is never touched.
- A "difficult game" check for every new game call: missing, nil, error.

## Version

`## Version: 0.12.0`, CHANGELOG, `docs/TESTING.md` section 26 (the lead).

## As built (2026-11-23)

The anchors and their sources are in
`docs/superpowers/plans/2026-11-23-controller-layout-0.12.0.md`. Where the
build differs from the mockup's numbers, and why:

- **Map 3.6 higher (round map centred 156.6 up, not 153), title strip 46 to 69
  up (not 56 to 75), swing timers 3 to 43 up (not 12 to 51).** The Forever map
  code fixes the strip 8 up from the map frame's bottom and the round map 30 up
  from it (`Blizzard_Minimap/Camelot/Minimap.lua:72-76`), so the strip sits
  18 under the round map, not 9; the timers are at least 12 tall at 80%
  (Height 15 is the game's smallest). The map frame's spot is 10 left of the
  centre so the round map itself is centred (the game puts it 10 right).
- **Swing timers 170 wide, 12 tall, 2 apart** (mockup 180, 11, 3): Width 213 is
  the game's smallest, at 80% (`EditModeSettingDisplayInfo.lua:777-830`).
- **Player and target frames 232 by 100, pet and target of target 120 by 49**
  (the mockup drew 192 by 60 and 112 by 34). The frames keep the mockup's
  inner edges (x -236 / +236); the player and target sit 172 to 272 up
  (centred on the mockup's middle, clear of the LT and RT bars' tops at 167),
  the pet and target of target 274 to 323 up, about 21 higher than drawn.
- **Target of target placed by the addon**: it is not an Edit Mode system on
  Camelot but a plain secure button the game anchors once under the target
  frame (`Blizzard_UnitFrame/Mainline/TargetFrame.lua:732-737`,
  `TargetFrame.xml:397-405`); the addon moves it above the target frame out of
  a fight, and puts it back when off.
- **LB / RB targeting pictures re-anchored by the addon.** They hang on the
  main bar's anchor (`Blizzard_GamepadActionBars/MainActionBarFrame.xml:18-26`),
  not on the sub-menu anchor, so moving the main bar to its corner would take
  them along. They are anchored where the main bar's anchor held them (the
  spots the 11:19 photo measured); no game code moves them.
- **Sub-menu buttons**: the bottom anchor at 0, 238 puts them at ±138, 188 as
  drawn; the two wheels (175 across) stay clear of every bar and frame (test).
- **Map icons left as the game places them**: the mail icon sits in
  `MinimapCluster.IndicatorFrame`, which the Camelot map code re-anchors with
  the title strip (`Camelot/Minimap.lua:78-79`); the tracking badge hangs on
  the strip (`Mainline/Minimap.xml:25-31`).
- **Quest tracker flush with the right edge** (TOPRIGHT 0, -375; was -30). It
  is 260 wide (probe), not the mockup's 218, and has no width setting. Even
  flush right, once it holds a long list (more than about 120 tall) its lower
  left part reaches over the target frame's right end (by 45) and the RT bar's
  top-right corner (by 16). Nothing else can move without reaching a sub-menu
  wheel; a later item could move the tracker or cap its list.
- **Template rebuild only at a login**, as the spec says: a tap on the switch
  that finds an existing older layout keeps it as it is until the next login
  (the 0.11 rule that a player's changes to an existing layout are kept on a
  tap).
- The XP bar at 100% with the Gamepad UI is 596 wide (0.11.1 "As built").
