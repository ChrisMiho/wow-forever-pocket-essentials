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
