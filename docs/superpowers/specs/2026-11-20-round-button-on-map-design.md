# Round button over the map's book icon (design)

From the owner on 2026-11-20, after looking at their Riverglades screenshots:
the round PE button hovers over the map. "a better plan would be to move it
over the little book icon of the map in the top lefthand corner, so its
still available, even if people arent going to be clicking on it." Asked
about a setting: "for now, lets just auto move it for the players, if we
get feedback they want to tweak it, we can adjust then."

## What the player gets

- Map open (the normal window size, with the book icon): the round button
  sits centred on the book icon in the map's top-left corner, and follows it
  if the map window moves or changes size. Tap and hold work as always; the
  red whisper number moves with it.
- Map closed: the button is back where it was (its "Move on screen" spot).
- Map full screen: the game hides the book icon there, so the button stays
  where it was (my call: nothing to sit on, and the full-screen map has no
  free corner we know is safe).

## Rules

- Always on, no setting (the owner's decision; this overrides the project's
  "off until device-tested" rule for this one change). A setting can come
  later if players ask.
- Our button is never parented to a game frame; it is only anchored to the
  book icon. Nothing is written to the map. The map's show / hide and
  full-screen / normal changes are heard with hooks that do nothing but
  re-place our button.
- Nothing ticks: the button is re-placed only when the map shows, hides, or
  changes size mode.
- "Move on screen" keeps working on the normal spot. Moving the button while
  the map is open is not expected; if it happens, the saved spot changes and
  is used after the map closes.
- Works in combat: the round button is our own plain (not protected) button.

## Approaches considered

1. Move it over the book icon (picked by the owner).
2. Hide it while the map is open: the owner considered it and preferred
   keeping the button reachable.
3. A setting to choose between them: not now, by the owner's decision.

## Game pieces it relies on (verify in wow-ui-source, branch forever)

- `WorldMapFrame.BorderFrame` is a portrait frame; `GetPortrait()` returns
  `PortraitContainer.portrait` (`Blizzard_SharedXML/PortraitFrame.lua:34`),
  the book icon set in `Blizzard_WorldMap.lua:18`.
- Full screen hides it: `WorldMapMixin:Maximize` calls
  `SetPortraitShown(false)`, `Minimize` calls `SetPortraitShown(true)`
  (`Blizzard_WorldMap.lua:40-73`); `EventRegistry` events
  `WorldMapMaximized` / `WorldMapMinimized` fire there.

## Left to the builder

Where the hooks live (Hub.lua owns the button; QuestIcons already hooks the
map's OnShow / OnHide only while its feature is on, so the hub needs its
own), the debug-log lines, and the tests.
