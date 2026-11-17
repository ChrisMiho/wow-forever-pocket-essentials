# Vertical Sort tab beside the bag

Status: approved by the owner in conversation, 2026-11-16 ("for right now,
can we just adjust the button to be vertical like you're showing").

## Why

Fourth device test (PRD "Fourth device test"): Sort works, but the button
looked "a little awkward on the spot", "a block hanging off the edge". The
owner wants it to look like part of the bag window.

## What changes

Only the look and place of the Sort button in `Bags.lua`. What it does (play
the sort sound, `C_Container.SortBags()`), when it shows (bag open, feature
on) and the left-stick click are unchanged.

- A tall, narrow tab flush against the bag window's left edge, not a wide
  block with a gap.
- Width: about one button height (`m.button`). Height: about half the bag's
  height on screen, never shorter than three button heights. Its top sits
  just below the round bag picture that sticks out of the top-left corner,
  so the picture is not covered.
- Look: dark fill with a gold border, to match the bag window rather than our
  settings buttons.
- Content, top to bottom: Blizzard's own sort icon (atlas
  `bags-button-autosort-up`, used by Blizzard's `BagItemAutoSortButton`) if
  the client has it, then the word "Sort" written one letter per line.
  Without the atlas, the letters alone.
- The press flash and the left-stick flash keep working.
- "Bag size" fitting (`ApplyScaleNow` `buttonRoom`) uses the tab's real
  width, so a large bag still leaves room for the tab.

## Addendum: "Sort button" choice (owner, 2026-11-16)

"For those that have physical controls ... a toggle to hide the sort button
... on by default ... to help reduce screen clutter."

- New choice in the bag row: "Sort button": Show (default) / Hide.
- Hidden: the tab never shows; the stick click still sorts; Bag size no
  longer keeps room for the tab. The row's note says it is hidden and can be
  shown again there.

## Not changing (taint rules in `Bags.lua` stay)

- The tab stays a child of `UIParent`, anchored to the bag. Nothing is
  written onto Blizzard's frames; no Blizzard Lua function is called.
- No d-pad navigation yet (upcoming item, needs Blizzard's navigation
  helpers and a device test).
- Settings wording and the left/right-stick choice: upcoming item.

## Approaches

1. Restyle our own button (chosen): smallest change, keeps every taint rule.
2. Re-parent Blizzard's own `BagItemAutoSortButton`: would write to a
   Blizzard frame in our name; rejected.
3. Put the tab inside the bag window: Blizzard's controller navigation would
   find it and could taint item use; rejected until the d-pad item.

## Device test

Open the bag at each bag size: the tab sits against the left edge below the
round picture, reads "Sort" top to bottom, tapping it sorts, left-stick click
still sorts and flashes the tab, and using an item from the bag is never
blocked.
