# 2026-11-23 Controller layout on the owner's main (level 40, Durotar)

Screenshots 09:59 to 10:04 (1920 by 1080, 1.406 px per UI unit) and
`PocketEssentials.lua` (0.11.0). Errors page: 0 entries. The owner's
comments: "parts of the UI are completely gone now, the map in the middle is
ugly with the title above it", "the both trigger buttons are complete gone".

## What the files show

- **Switching works.** On the main, the layout first stayed off because this
  character still had its own Edit Mode layout active (the game remembers the
  active layout per character, Pocket Essentials' switch is account-wide).
  Off, reload, on, reload fixed it; `prev` is now the main's own layout
  ("shardspr6"). To fix in code: a character still on its own layout should
  switch to ours at login and remember its own.
- **Every option row did what it says** (map size, main bar above or under,
  the three frame spots, swing timer spots), each after its reload.

## Problems, from the screenshots

1. **The both-triggers bar is not gone, it is lost.** It sits at 70% size over
   the character's head, in the middle of the screen (09:59:49 and later). Too
   small and in the wrong place to read as a bar.
2. **"Main bar above the map" puts the main bar in the middle of the screen**,
   over the character (centre about 290 units up), with the both-triggers bar
   above that (10:00:56). The opposite of a compact screen.
3. **The map's title strip** (zone name, clock, mail, the "2" badge) sits above
   the map, between the map and the bars above it. The game has a "header
   underneath" setting for the map (`Enum.EditModeMinimapSetting.HeaderUnderneath`).
4. **With the main bar under the map** the three bars make one wide row at the
   very bottom (about 650 units), the map above them reaches the middle of the
   screen, and the both-triggers bar sits above the map. The whole block is
   about half the screen's height. The bars' bottom edges touch the XP bar.
5. **Buffs overlap the chat.** The buff row sits on the chat window's bottom
   edge, over its last lines (10:02:30).
6. **The chat window top right is a large, mostly empty tinted box** over the
   scenery.
7. **The XP bar stayed at the bottom.** The approved mockup put it at the top,
   130% wide, between the controller hints and the chat
   (`docs/ui-review/mockup-0.8.1.html`, `pLayout`; game plan note 15). The
   spec only set its size and left its spot "unchanged", so it kept the spot
   of the layout it was copied from (the warrior's, the game's Gamepad preset:
   bottom). A miss in the spec, not a game limit. Fix: the template places it
   top middle.
8. Unchanged but taking room: the game's controller hint box top left (LB/RB
   targeting, ping, auto-run).
9. Not seen yet: target frame, swing timers (no fight in these shots).

## Compared with the owner's own layout (09:59:49, before)

The owner's own layout keeps the minimap top right and the bars in a tight
cluster under the character. Moving the map to the bottom middle is what
pushes the bars up into the middle of the screen.
