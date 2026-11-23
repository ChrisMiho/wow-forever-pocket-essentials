# Controller layout 0.11.1: the clear bugs from the main's screenshots

**Approval.** Draft, 2026-11-23, from `docs/11-23-face-bars/HANDOFF.md` step 2.
Waiting for the owner's go. An update to `2026-11-21-controller-layout.md`.

## Why

On the owner's level 40 main (`docs/11-23-ui-debug/FINDINGS.md`) four things
were plainly wrong, whatever the face bars later decide about where the bars
go: the XP bar stayed at the bottom, the layout did not switch on by itself on
a second character, the map's title strip sits on top of the map, and the
buffs cover the chat's last lines.

## Goals

- Those four fixed, nothing else moved.

## Not goals

- Where the bars go, the both-triggers bar's size and spot, the chat's size,
  the controller hints box. All wait for the face bars mockup.

## Anti-goals

- A player's own Edit Mode layout changed. A layout switch in a fight. Any
  ticking while the feature is off.

## Approaches

- **A. Fix them in the template and the switch (picked).** Small changes in
  `ControllerLayout.lua`'s plan and its switch-on; the plan tests cover them.
- B. Leave the template and let the player move things in Edit Mode. Turned
  down: the owner's point is that it is ready-made.

## 1. XP bar top middle

- `StatusTrackingBar1` and `2` get a spot: `TOP`, `UIParent`, `TOP`, 0, -2
  (the very top edge, centred), Size 10 (100%, was 130%), and `moved = true`.
  The owner (2026-11-23): "i dont read the bar, i really only look to watch
  it fill up, so im cool with the smaller bar that doesnt overlap, but at the
  top like you have it is perfect".
  Bar 2 sits right under bar 1 (`TOP`, 0, -2 - the bar's height; the builder
  finds how the Gamepad preset stacks them in
  `Blizzard_EditMode/Mainline/EditModePresetLayouts.lua` and the status bar
  container's code, and follows that).
- Why the very top: the controller hints box (top left) and the chat (top
  right, whose tabs start about 36 units down) leave a clear strip along the
  top edge. Between them sideways there is only about 580 units.
- **Width.** The probe measured the XP bar at 357.6 units wide (11-22
  EVIDENCE); the 11-23 screenshots look wider (about 770 at 130%, so about
  590 at 100%). 100% keeps it clear of the hints box either way.
- The probe's own button moves down out of its way (probe 0.7.0 spec, 6).

## 2. Switch on per character

The game remembers the active Edit Mode layout per character; our switch is
account-wide. Today `opts.prev` holds one "layout to go back to" for all
characters.

- Not in this build: every setting per character. The owner (2026-11-23):
  "Each character needs its own setup of both pe toggles as well as the ui
  setup ... park it for now, but it comes next as im starting to play more
  characters". 0.11.1 only remembers each character's own old layout.
- `opts.prev` becomes per character: `opts.prevs[<character key>]` with the
  same shape `{ name, layoutType, preset }`. The key is the character's name
  and realm (`UnitName("player")`, `GetRealmName()`; the builder verifies both
  on the forever branch). `opts.prev` is kept for older saved files and read
  once: at the first login on 0.11.1 it becomes the entry of the character
  logging in if ours is active there; otherwise it is dropped (that character
  goes back to the Gamepad preset, as today when nothing is known).
- **Login with the switch On** (out of a fight, through `PE:RunOutOfCombat`):
  - ours active: nothing changes; bars placed, as today;
  - ours not active and this character has **no** entry: remember this
    character's current layout as its entry, make ours active, ask for the
    reload (the same steps as a switch-on);
  - ours not active and this character **has** an entry: the player picked
    another layout in Edit Mode; leave it, status line "Another Edit Mode
    layout is active..." as today.
- **Switch Off** on a character: put back its own entry (or the Gamepad preset
  without one), remove its entry, reload, as today.
- **Login with the switch Off** and this character still has an entry while
  ours is active (it was switched off on another character): put back its own
  layout, remove the entry, ask for the reload. While off the module runs
  only this one login check, then nothing (the builder keeps "nothing ticks
  while off": a one-time check at login, no events kept registered).
- Start over and the option rows are unchanged; they work on the shared
  layout.

## 3. Map title under the map

- The minimap piece gets the setting `HeaderUnderneath = 1`
  (`Enum.EditModeMinimapSetting.HeaderUnderneath`). Proof to confirm:
  `Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua:131`,
  `EditModeSystemTemplates.lua:1794-1795`, and
  `Blizzard_Minimap/Camelot/Minimap.lua:68` (`SetHeaderUnderneath` in the
  Forever client's own map code). Read from the game's Enum like the other
  settings; if missing, the piece is written without it.
- The map's spot is its bottom edge, so a title under it pushes nothing; the
  builder checks the Camelot code for whether the header then sits below the
  map's bottom edge, and if so lifts the map by the header's height so it
  stays clear of the bars or timers under it.

## 4. Buffs clear of the chat

- The chat's last lines reach about 270 units down; the buffs start at 262.
  Move buffs to `TOPRIGHT`, -30, -292, debuffs to -330, the quest tracker to
  -375. Nothing else. The chat box keeps its size. The owner (2026-11-23): "i
  want to try and leave the box as it is, so i can read more than 2/3 chats
  when i increase the font size".

## Tests (offline, `tests/` layout tests)

- Plan: the XP pieces have their spot and size; the minimap has
  `HeaderUnderneath`; the new buff, debuff and tracker spots; a missing
  `HeaderUnderneath` enum leaves it out.
- Switch: two characters in one saved file; login with On on a character
  without an entry switches and remembers; with an entry and another layout
  active it leaves it; Off puts back only that character's own; login with
  Off and a leftover entry puts it back once; an old `opts.prev` is moved
  over or dropped as above; nothing runs in a fight.

## Version

`PocketEssentials.toc` `## Version: 0.11.1`, CHANGELOG entry and a
`docs/TESTING.md` section, together. Features still default off.
