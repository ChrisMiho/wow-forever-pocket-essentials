# Move things (version 0.2.0)

Status: **approved by the owner** (2026-11-17, in conversation during the
0.1.0 device test: "you have what you need, go ahead and implement this
please, and then release a new version once it's ready"). The design below is
what was agreed in that conversation; the details it left open are listed
under "Choices made without the owner".

## Why

The quest arrow, the "Press A to type" prompt and the round button can only
sit at a few preset spots. The owner wants to put each one exactly where they
like, with the controller as well as touch, without fiddly dragging.

The game's own Edit Mode is **not** used or touched: it has no supported way
for an addon to add a movable item, and reaching into it is the risk that
made us drop the nudge helper (`docs/DECISIONS.md`). Everything here is the
addon's own frames.

## What the player sees

1. The settings window's bottom row has a new button, **Move things**. Tapping
   it closes the settings and opens a small panel, "Move things".
2. The panel lists the pieces that can be moved, one big button each:
   - **Quest arrow** (only while the Quest arrow feature is on)
   - **Chat prompt** (the "Press A to type" text; only while Big chat buttons
     is on)
   - **Round button** (always)
   The selected piece's button is highlighted. The first one listed is
   selected when the panel opens.
3. A gold outline box with the piece's name shows on screen exactly where the
   selected piece sits (or would sit, if it is not showing right now, such as
   the arrow with no quest focused or the prompt between chats).
4. Four big arrow buttons, **Up, Down, Left, Right**, move the selected piece:
   - One press is a small nudge: 2 pixels (on a 720p screen).
   - Holding the button moves it steadily: after 0.4 seconds it repeats 10
     times a second, and after 1.5 seconds of holding each step grows to 6
     pixels, so a long hold crosses the screen in a few seconds.
   - The piece and the outline box move together, live.
   - A piece cannot be pushed off the screen: a step that would put any part
     of its box outside the screen is not taken.
5. **Reset** puts the selected piece back to its preset spot (offset zero).
   **Close** closes the panel.
6. Controller: the d-pad moves the highlight between the panel's buttons, A
   presses the highlighted one (holding A on an arrow button repeats exactly
   like holding a finger on it), B closes the panel. This is the same
   navigation the settings window uses.
7. Positions are saved as they change, so closing by B, by Close, or by a
   fight starting all keep them. They are remembered between sessions.
8. The panel is small and sits in the bottom right corner. When the selected
   piece's box overlaps the panel, the panel hops to the bottom left corner
   (and back when it no longer overlaps there).
9. The preset choices stay as they are ("Arrow position", "Round button
   position"). The move is an offset from the chosen preset. Choosing a
   preset again puts the piece exactly on that preset (its offset is cleared).

## Rules

- **Default is today's behaviour.** With no saved offset every piece sits
  exactly where 0.1.0 puts it. Saved settings from 0.1.0 load unchanged.
- **Storage.** `PocketEssentialsDB.ui.moved[<piece key>] = { x = <number>, y =
  <number> }` in 720p pixels (x right, y up), converted with `UI:Px` like every
  other size, so a position holds when the screen resolution or "Button size"
  changes. A missing, wrong-typed or non-number entry reads as 0, 0. Offsets
  are limited to the range -2000..2000 when read.
- **One place owns the offsets.** A small core part (new file `Move.lua`)
  keeps the list of movable pieces and the offsets. A piece registers
  `{ key, label, order, available = function() -> bool, apply = function(),
  outline = function(box) }`:
  - `apply()` re-lays the real piece out (its own existing layout function,
    which now adds the offset);
  - `outline(box)` positions and sizes the given outline frame over where the
    piece sits, whether or not the piece is showing.
  Piece keys: `questArrow`, `chatPrompt`, `hub`.
- **Each piece adds the offset in its own layout code** by asking
  `PE.Move:GetOffset(key)` (returns two numbers in UI units, 0, 0 when none).
  Pieces work unchanged if `Move.lua` failed to load (they treat a missing
  `PE.Move` as 0, 0).
- **Nothing ticks unless a button is being held.** The repeat uses one
  `OnUpdate` on the panel's own hidden driver frame, shown only between press
  and release of an arrow button. It stops on release, when the panel hides,
  when a fight starts, when the highlight leaves the button, and by itself
  after 8 seconds (in case a release is never reported). Nothing runs while
  the panel is closed.
- **Fights.** The panel cannot be opened in a fight (controller buttons
  cannot be taken then); the button says so in chat. If a fight starts while
  it is open, it closes; positions are already saved.
- **Frames.** The panel, the outline box and the driver are the addon's own
  frames under `UIParent`. The panel is built with `UI:CreatePanel` and
  `UI:AttachNav` like the others. The outline box is display only (no mouse).
  No Blizzard frame is touched, hooked or parented to. No Edit Mode function
  or event is used.
- **Hold with the controller.** The window navigation in `UI.lua` already
  sees A go down and come up (it acts on release). It gains one optional hook:
  a button with a `peHold` table (`start()`, `stop()`) gets `start` when A
  goes down on it and `stop` when A comes up or the press is lost; such a
  button's click is not fired again on release (the press already nudged).
  Touch uses the button's own mouse-down and mouse-up. Buttons without
  `peHold` behave exactly as before.
- **Handlers** go through `PE:Safe` / `PE:Wrap`. No libraries.
- **Debug log.** "move: panel opened / closed (<why>)", "move: <key> selected",
  "move: <key> now at x,y" (one line when a press or a hold ends, never per
  repeat), "move: <key> reset", "move: stopped at the screen edge", "move:
  hold stopped after 8 s", "move: not opened: in a fight".

## Unverified (to log in `docs/ARCHITECTURE.md`)

- Whether the controller's A release always reaches our navigation button
  while it is held for several seconds (a short press and release already
  works on the device). Worst case: a hold keeps moving until the 8-second
  stop or the screen edge; a single press still nudges.
- Whether the quest arrow's block, moved near a screen edge, is clipped or
  hidden by another Blizzard frame. Worst case: Reset.

## Tests (offline, `tests/features/`)

- With no saved offset, each piece's position equals 0.1.0's (existing
  position tests stay green unchanged).
- A saved offset moves each of the three pieces by that many pixels from its
  preset; a bad saved value reads as 0, 0.
- The panel lists only available pieces (arrow off: not listed; chat off: not
  listed; round button always).
- One press on Right moves the selected piece 2 pixels right and saves it;
  Up, Down, Left likewise.
- Holding: nothing repeats before 0.4 s; then 10 steps a second; steps grow to
  6 pixels after 1.5 s; release stops it; hiding the panel stops it; a fight
  stops it and closes the panel; it stops by itself after 8 s; the driver has
  no `OnUpdate` running when nothing is held and the panel is closed.
- A step that would leave the screen is not taken.
- Reset clears the offset; choosing a preset clears that piece's offset.
- The outline box sits over the selected piece and follows it, including when
  the piece itself is hidden.
- The panel hops to the other corner when the outline overlaps it.
- Controller: d-pad reaches every button; A down then up on an arrow nudges
  once (not twice); A held repeats; B closes; an ordinary button elsewhere
  (settings) still clicks once on release.
- Cannot be opened in a fight.
- Positions survive a reload (saved table).

## Shipping

Version 0.2.0 (a new feature). CHANGELOG, PRD.md, `docs/ARCHITECTURE.md`,
`docs/TESTING.md` steps, audit, check, test, build, push, GitHub pre-release
`v0.2.0` with the bundle zip and `dist/PocketProbe.zip`. Never CurseForge.

## Not in this version

- More chat options (the owner will say what once they have played more).
- Showing our boxes while the game's Edit Mode is open.
- Resizing pieces from the panel (the arrow keeps its "Arrow size" choice).
- Dragging with a finger.

## Choices made without the owner

1. Step sizes and timing: 2 pixels a press; repeat after 0.4 s at 10 a
   second; 6 pixels a step after 1.5 s; an 8-second safety stop.
2. The move is stored as an offset from the preset, and picking a preset
   clears it.
3. The entry point is a "Move things" button in the settings' bottom row.
4. The panel sits bottom right and hops bottom left when in the way.
5. Pieces whose feature is off are not listed.
6. The version is 0.2.0, built while the 0.1.0 device test is still running;
   the 0.1.0 changes stay untested until that report arrives.
