# Controller layout 0.14.0: the console (one panel a side, triggers swap it)

Status: approved by the owner's overnight instruction of 2026-11-23 ("operate autonomously,
no questions"). Evidence: docs/progress2/ (three device screenshots of 0.13.0, one
inspiration picture).

## What the device test of 0.13.0 showed

- The split worked: d-pad pictures left of the map, face-button pictures right of it.
- Eight diamonds on screen at once (two 2 by 2 grids) was hard to follow: when a trigger was
  held, the lit diamonds were not where the owner expected.
- The pictures (28 units) were too small to read the spells.

## The new arrangement

The map stays at the bottom centre. Beside it, one big panel a side:

| Held        | Left of the map                                      | Right of the map                                     |
|-------------|------------------------------------------------------|------------------------------------------------------|
| nothing     | inner-left: main bar's d-pad diamond                 | inner-right: main bar's face diamond                 |
| LT          | outer-left: LT d-pad, inner-left: LT face            | inner-right: main face, quiet (dimmed)               |
| RT          | inner-left: main d-pad, quiet (dimmed)               | inner-right: RT d-pad, outer-right: RT face          |
| LT + RT     | inner-left: LT+RT d-pad                              | inner-right: LT+RT face                              |

"The panel of the trigger you hold opens into two: its d-pad half on the left, its face half
on the right." Within every pair the d-pad diamond is left of the face diamond, the way the
controller is held. Both triggers replace the main panels in place. Releasing goes back to the
main bar. Diamonds not in the table are hidden. The quiet side is drawn at 0.3 see-through
(one constant). The tag (LT, RT, LT+RT) stays at the centre of each shown trigger diamond.

Bars that take a top anchor's place (targeting, possess, stance bars) are drawn the way 0.13.0
draws them: the anchor's bar is the group's bar, and the active group decides the state.
With no active bar known, the "nothing held" state.

The move is plain SetPoint / Show / Hide / SetAlpha on our own plain frames, allowed in a
fight. No secure frame is touched by the swap.

## Sizes and spots (UI units from the screen's bottom centre; the screen is 1365.33 by 768)

- Picture 42 (was 28); in a diamond the four buttons 46 left / right and 28 up / down of its
  centre: a diamond is 134 by 98. The glyph, range dot and count grow with the picture.
- Diamond centres: inner (±170, 66), outer (±316, 66). Inner spans 103 to 237 from the centre
  and 17 to 115 up: clear of the swing timers (±85, 3 to 43 up), the title strip (-87 to 65)
  and the round map (±69, 87 to 226).
- The game's four real bars, invisible, at 60% (124.8 by 40.8), under the inner diamonds:
  main (-170, 87), LT (-170, 45), RT (170, 87), LT+RT (170, 45). The frame under the pictures
  that takes a tap covers each side's inner diamond and its two real bars (plus the margin).
  Outer diamonds' pictures take a tap themselves.
- Player and target frames moved out past the outer diamonds: FRAME_X 395 (player -627 to
  -395, target 395 to 627), still 56 up. Pet above the player, target of target above the
  target, as before. The target's cast bar then lands 518 to 668 across, inside the screen.
- LB / RB targeting pictures beside the map, clear of the inner diamonds:
  BOTTOMRIGHT (-76, 128) and BOTTOMLEFT (76, 128).
- Unchanged: map, title strip, swing timers, sub-menu buttons (±138, 188 up) and their
  wheels, chat, buffs, XP bars, quest tracker, round button.
- Plan.TEMPLATE goes to 4, so the saved Pocket Essentials layout is rewritten once at login.

## The contract between the two files

ControllerLayout.lua (PE.LayoutPlan) gives:
- `Plan.FACE = { button = 42, dx = 46, dy = 28 }`
- `Plan.FaceSpots()`: `{ inner = { left = {x,y}, right = {x,y} }, outer = { left = {x,y}, right = {x,y} } }`
- `Plan.FaceStates()`: for each state key `rest`, `lt`, `rt`, `both`, a list of
  `{ group = "main"|"lt"|"rt"|"both", half = "dpad"|"face", spot = "innerLeft"|"outerLeft"|"innerRight"|"outerRight", quiet = true|nil }`
  as in the table above.
- `Plan.RealBarRects()`: the four real bars' rectangles, as now.
- `Plan.Rects()`: lists every diamond spot once (inner and outer each side) for the
  overlap check, instead of every bar's halves.

FaceBars.lua keeps its own copies of these numbers as defaults (as now) and:
- builds each group's two halves as two frames, each holding its four pictures placed
  relative to that half's centre;
- on a change of the active group (already marked by ReadActive, applied in Flush where
  ApplyGroupAlpha runs now) places, shows, hides and sets the see-through of every half from
  FaceStates; QUIET_ALPHA's old meaning (whole groups quiet) goes away;
- builds the two frames that take a tap from the inner diamonds and the real bars.

## Not in this round

- No animation for the swap (instant).
- No new settings rows. The mockup page is not redrawn tonight.

## Device test (TESTING 28)

1. Reload with Controller layout on: only two diamonds beside the map, bigger than before.
2. Hold LT: the left side opens into two diamonds (LT d-pad, LT face); right side dims.
3. Hold RT: the right side opens into two (RT d-pad, RT face); left side dims.
4. Hold both: the two main diamonds show the LT+RT bar. Release: back to the main bar.
5. Cast from each state; the spell cast must match the picture lit at that spot.
6. In a fight: the same, no errors; frames, cast bar and auras not on top of the pictures.

## As built (2026-11-24)

One builder on `setup-options`, reviewed against this text. Differences, and why:

- **No differences in the numbers or the states.** Plan.FACE 42 / 46 / 28;
  spots inner (±170, 66), outer (±316, 66); real bars at 60% at (-170, 87),
  (-170, 45), (170, 87), (170, 45); FRAME_X 395; SHOULDERS (-76, 128) and
  (76, 128); TEMPLATE 4; quiet 0.3.
- **Plan.Rects names** the four spots "inner left diamond", "outer left
  diamond", "inner right diamond", "outer right diamond". With FRAME_X 395
  the target's cast bar takes 518 to 668 across, 0 to 10 up, and the aura
  rows 420 to 542 across, 156 to 178.5 up: on screen and clear of the outer
  diamond (383).
- **The frames that take a tap** cover each side's inner diamond plus 4:
  left -241, 13 to -99, 119 (the right side the mirror). The two real bars and
  all their buttons fit inside the diamond (the d-pad's left button reaches
  -234.8 of its -237), so the old 0.2 unit gap at the player frame is gone.
  The cut at the frames' edge stays, at 395, as a guard only (nothing reaches
  it). They stay put whatever trigger is held.
- **Grown with the picture** (sizes drawn for 28, times 42 / 28, rounded to
  a whole unit): the button glyph 17 (was 11), its dots 5 (3) and 5 apart (3),
  the range dot 6 (4), the count font 14 (9), the trigger tag font 12 (8),
  the glow 5 outside the picture (3); the icon's inset 2.25 (1.5) is not
  rounded.
- **Each group's halves** are two plain frames, 134 by 98, in the pictures'
  holder; each picture sits CENTER on its half's centre. Every half starts
  hidden, and the first draw after Start places the halves for the state.
  The swap runs where the old strength change ran (on a change of the active
  group, in the next frame's update).
- **Fallbacks:** FaceBars.lua keeps copies of FACE, the spots, the states and
  the real bars. A FaceSpots or FaceStates answer that is missing, raises,
  or names an unknown group, half or spot (or has the 0.13.0 shape) is
  replaced by the copy.
- **No active-bar callback, or an unreadable active bar:** the "nothing
  held" state (0.13.0 showed every bar at full strength).
