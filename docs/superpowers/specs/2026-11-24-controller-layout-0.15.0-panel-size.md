# Controller layout 0.15.0: Spell panel size

Status: approved by the owner 2026-11-24 ("I want the scale to go from 80-120 to start, I want whatever you've got it set to right now as the default"); 110% and 120% raise the frames as below. Owner, 2026-11-24: "Is there an option that would
allow me to make the bars bigger or smaller like the rest of the ui components?", and "80-120
sounds like a good start". The row goes on the Controller and layout tab; the page scrolls, so
the old "tab is full" note no longer applies.

## The row

"Spell panel size": 80%, 90%, 100%, 110%, 120% (default 100%: exactly the 0.14.0 numbers). It is saved with the other
Controller layout options. A saved value that is not one of the five reads as 100%.
`Fill()` currently keeps only 0, 1 and 2, so this option is checked on its own.

## What a size s does (s = 0.8 to 1.2; the numbers in UI units from the bottom centre)

- Picture 42s; in a diamond the buttons are 46s left/right and 28s up/down; the diamond is 134s
  by 98s.
- The inner edge stays 103 from the centre (clear of the timers, title strip and map). Inner
  centre x = 103 + 67s, outer centre x = inner + 134s + 12. Centre y stays 66.
  - 80%: inner 156.6, outer 275.8, outer edge 329.4
  - 100%: 170 / 316 / 383 (as 0.14.0)
  - 120%: 183.4 / 356.2 / 436.6
- The real bars scale 0.6s and stay stacked under the inner diamonds (centres y 66 ± 21s).
  The backings follow them.
- The frames:
  - 80% to 100%: they stay at x ±395, 56 up.
  - 110% and 120%: the outer diamonds would reach the frames (409.8 and 436.6 against 395).
    Moving the frames out would push the target's cast bar (frame left + 123 to + 273) past the
    screen edge (682.67), so instead they rise: FRAME_Y = 66 + 49s + 8 (128 at 110%, 133 at
    120%). The cast bar then lands 72 to 82 up at 518 to 668 across, clear of the outer
    diamonds. The pet and the target of target rise with them.

## When it applies

- Pictures, backings and positions are redrawn on the change.
- The real bars' scale and spot, and the frames (an Edit Mode layout rewrite, the same path as
  the timer rows), change out of a fight only. During a fight the change waits, with the
  tab's existing "Updating the layout after this fight." line. No reload.

## Tests

- Plan numbers for every size.
- No overlaps at every size (Plan.Rects takes the size).
- The real bars stay under the inner diamonds at every size.
- A change during a fight waits for the fight to end.
- FaceBars redraws at the new size and keeps its trigger states.

## Device test (TESTING 29)

At 80% and 120%: the panels next to the map, nothing overlapping, triggers open the panels as
before, and at 120% the frames sit just above the panels. Change the size during a fight: it
applies when the fight ends.
