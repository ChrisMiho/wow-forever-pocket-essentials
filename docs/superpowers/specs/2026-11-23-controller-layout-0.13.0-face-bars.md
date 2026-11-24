# Controller layout 0.13.0: face bars, split the way the controller is held

**Approval.** The owner, 2026-11-23 evening, after the 0.12.0 device check
(`docs/weMadeProgress/`): "utilizing the mocks, artifacts, and this latest
feedback, utilize subagents to continue to refine the ui into the vision that
i previously described, a simple and clean ui, thats functional, but gives me
some more screen realestate then what the default gamepad gives, ask no
questions". Approved by that instruction; built and published as a GitHub
pre-release without a review stop (memory: autonomous batches).

## What the 0.12.0 screenshots showed

Screenshots 17:48 to 17:51 (1920 by 1080, 1.406 px per UI unit), saved file
clean (0 errors). 17:48 is before the reload that finished the template
update; 17:50:46 is 0.12.0 as built.

1. **The bars are the game's own.** 0.12.0 moved the real bars; it drew
   nothing of ours. The owner asked whether hiding the real bars and drawing
   our own is possible: it is (proven on the device, `docs/11-23-face-bars/EVIDENCE.md`),
   and 0.13.0 does it.
2. **Dead space.** The bars sit 80 units out from the sub-menu buttons; the
   player frame sits 241 to 305 up and the pet 370 to 400 up, so the bottom
   block reaches half the screen's height at the sides while the middle stays
   empty.
3. **Overlap.** The quest tracker runs into the right-hand bars; before the
   reload (17:48) the frames sat on the bars.
4. **The game's hint box** (top left: LB/RB targeting, ping, auto-run) takes
   a corner for text a practised player does not need.
5. The wheels (17:49) open where expected and cover the map's sides.

## Goals

- **Our own spell pictures ("face")** for all four bars, drawn by Pocket
  Essentials; the game's real bars stay whole and invisible underneath and
  still take every press.
- **The split**: on the screen, as on the controller, the d-pad halves sit
  left of the map and the face-button halves right of it.
- **One low band at the bottom**: frames, spells and map in the bottom fifth
  of the screen; the middle of the screen free.
- **The bar in use stands out**, the others step back (the approved Quiet
  bars idea, simplified): nothing moves when a trigger is held.
- Safe: a press always reaches the real button; if the face cannot work, the
  game's bars come back by themselves.

## Not goals

- Cooldown numbers, stack counts in a fight (secret on this client).
- Proc glows, the pressed flash (open questions; later).
- Option rows: one setup until it plays well (memory: one setup).
- Touch casting from the pictures (the controller casts; see Taps).

## Anti-goals

- Any "Interface action blocked". Anything protected changed in a fight.
- A press that does nothing because of us.
- Per-frame code while nothing changes. Anything running while the switch is off.
- Silent failure: when the face is off for a reason, the status line says so.

## The face

Our own frames, parented to `UIParent`, display only. Facts and citations:
`docs/11-23-face-bars/SOURCE-BRIEF.md` (Blizzard source, forever branch).

- **One picture per real button**, 32 in all (4 groups of 8). Each picture
  group is tied to one of the game's four bar anchors (`TopCenteredAnchor`
  main, `LeftCenteredAnchor` LT, `RightCenteredAnchor` RT,
  `BottomCenteredAnchor` LT+RT) and mirrors **whichever bar sits in that
  anchor now**: the normal bar, or the stance/form bar, the possess bar or
  the LB/RB targeting bars that the game swaps in (brief 2, 4). Buttons by
  `bar:GetActionButtonByIndex(1..8)`: 1-4 the d-pad (left, up, right, down),
  5-8 the face buttons (X left, Y up, B right, A down) (brief 1).
- Each picture: the icon, a thin dark edge, the **position glyph** in the
  top-left corner (four dots with the pressed spot filled for the face
  buttons, a plus with the pressed arm filled for the d-pad; approved on the
  mockup).
- **Button size 28 units**; a diamond puts its buttons 30 left/right and 19
  up/down of its centre: 88 by 66 for a diamond.
- **What each picture shows: a copy of what the real button shows**, so the
  game's own secret-safe work is reused (brief 3, 8):
  - icon texture, its colour (usable, no mana: the game writes 1/1/1, .5/.5/1,
    .4/.4/.4) and greying, copied from the real button's `icon` through
    post-hooks on its `SetTexture`, `SetVertexColor`, `SetDesaturated` (and a
    first read when bound); an empty slot is a faint outline;
  - the main bar's four face buttons hold no spells (Interact, Inspect, Back,
    Jump): their picture is copied from the button's `SpecialActionIcon`;
  - **cooldown**: on `ACTIONBAR_UPDATE_COOLDOWN` and `SPELL_UPDATE_COOLDOWN`,
    for a real slot (`button.action` a number above 0):
    `C_ActionBar.GetActionCooldownDuration(slot)` into our own Cooldown frame
    with `SetCooldownFromDurationObject` (allowed in a fight), and the icon
    darkened while the game says "on cooldown" (readable), so it reads as on
    cooldown even if the sweep does not draw. Never `SetCooldown` with the
    game's numbers (refused);
  - **out of range**: our small dot copies the real button's `RangeIndicator`
    (shown, colour);
  - **in use** (current, auto-repeat): a gold edge when `GetChecked()` is
    readable and true, read on `ACTIONBAR_UPDATE_STATE`;
  - **proc glow**: a gold glow while the game shows its alert on that button
    (post-hooks on `ActionButtonSpellAlertManager` `ShowAlert` / `HideAlert`,
    filtered to our buttons);
  - stack counts: the real button's `Count` text passed straight to our own
    text (allowed even when secret), never compared or formatted;
  - the trigger tag in each diamond's centre: "LT", "RT", "LT+RT"; none on
    the main bar.
- Any value that comes back secret where we would need to compare it is
  treated as "unknown" and shows the plain picture.
- **The bar in use**: its two diamonds at full strength; the other three bars'
  at 50%. Follows the game's own active-bar callback
  (`PageUnit:RegisterActiveActionBarUpdatedCallback(fn, owner)`, called as
  `fn(owner)`; read `PageUnit:GetActiveBar()` inside and find which anchor
  holds it). It fires on every trigger check, so only a change does work.
  Without the callback, every bar stays at full strength.
- **Updates on hooks and events only**, collected into one update on the
  next frame (an `OnUpdate` set only while something is waiting, then
  removed). No timer of our own.
- Slot and page changes: post-hook on each real button's `UpdateAction`
  re-reads that button; `hooksecurefunc(PageUnit, "SetCurrentPage")` re-reads
  all. Never `PageUnit:AddPageChangeCallback` (it taints the game's page change).
- The face hides while `GamepadMainActionBarFrame` is hidden (binding editor,
  Gamepad UI off), through `HookScript("OnShow"/"OnHide")`.
- Hooks are installed once and do nothing while the feature is off; nothing
  is ever written into Blizzard's tables or frames except the anchors' alpha
  and spots.

## Where everything goes (UI units at UI scale 1, 1365 by 768; x from the centre, "up" from the bottom)

Kept from 0.12.0: map bottom middle at 70% (round map centred 156.6 up), its
title strip under it, the swing timers under that, the sub-menu buttons at
±138, 188 up, the LB/RB targeting pictures at ±108 to ±144, 84 to 116 up,
chat top right, buffs and debuffs under the chat, XP bar top middle.

| Piece | Where |
|---|---|
| Left face (d-pad halves) | a 2 by 2 grid of diamonds, inner edge x -155, 186 wide, 6 to 146 up |
| Right face (face-button halves) | the mirror, inner edge x +155 |
| Grid cells, both sides | inner bottom: main bar; inner top: LT; outer bottom: RT; outer top: LT+RT ("up is LT, out is RT"); cell centres x ±199 / ±297, y 39 / 113 |
| Real bars, invisible | two per side under the face grids, scale 0.9 (187 by 61): left main (39 up) and LT (113 up) centred x -248; right RT (39) and LT+RT (113) centred x +248 |
| Player frame | left, beside the face: frame box right edge x -345, 56 to 156 up (the picture inside it, 192 by 67, sits 20 in) |
| Pet frame | above the player frame, right-aligned with it |
| Target frame | the mirror, left edge x +345, 56 to 156 up, auras on top as 0.12.0 |
| Target of target | above the target frame, left-aligned with it |
| Target cast bar | with the target of target shown, the game puts it 123 right of and 46 under the frame's bottom left: x 468 to 618, 0 to 10 up, in the free corner |
| Quest tracker | top left, where the hint box was (TOPLEFT 5, -5), height as 0.12.0 |
| Game's hint box | hidden while the layout is on: the game's own setting `GamepadShowPersistentInputLegend` set off, the player's value put back when the layout is switched off |

The builder checks every number against the Camelot source and the probe's
sizes, and records the differences under "As built". Overlap test at 1365 by
768: no two pieces overlap; the face grids may sit under an open sub-menu
wheel (the wheel is drawn above them; see Layers).

## Layers and taps

- The face sits above the invisible real bars and below the sub-menu wheels
  and spell flyouts (strata and levels from the source).
- **Taps**: the face takes a tap and does nothing with it, so a tap or the
  game's cursor never presses a hidden button or shows its tooltip. Spells
  are cast with the controller, as today.

## The real bars

- Placed and scaled out of a fight, as 0.12.0 does (same code, new spots).
- Made invisible by setting the four **anchors** (`Top/Left/Right/BottomCenteredAnchor`)
  to alpha 0. Not `.Bar`: holding LB/RB makes the game fade the other bars
  with `UIFrameFade`, which sets `.Bar` alpha back to 1 first, and on release
  sets alpha 1 on every bar (brief 4). No game code sets an anchor's alpha.
  Never `PageUnit` (the wheels set it). The anchors' alpha may be set in a
  fight (it is not protected); a post-hook on each anchor's `SetAlpha` puts
  0 back should anything else change it.
- The stance, possess and targeting bars and the game's trigger tags sit in
  the anchors, so they fade with them.
- The sub-menu buttons, the LB/RB targeting pictures and the new-spell fly-in
  are not in the anchors and stay visible. A wheel opened from a hidden bar
  button shows itself and that button at full strength (brief 6).

## When the face cannot work

- The real bars are only made invisible once the face is built and showing.
- The face is not built (bars or buttons not found, a needed call missing):
  the game's bars stay as 0.12.0 shows them, the status line says "Showing
  the game's own spell bars: <reason>", logged once.
- Errors while running: after 3 errors in a session the face hides and the
  real bars come back at once (alpha is allowed in a fight), with the same
  status line and a chat line.
- Switching the layout off puts everything back: face hidden and its events
  dropped, bars' alpha 1, the hint box setting, frames and bars as before.

## Template

`TEMPLATE = 3`. A login with an older template rebuilds our layout once and
asks for the reload, as 0.12.0 does (chat line, status lines while waiting).

## Tests

- Plan: every spot above; no overlaps at 1365 by 768 (face grids, real bars,
  frames, auras, cast bar, map, strip, timers, sub-menu buttons, targeting
  pictures, tracker, chat, buffs); the target cast bar on screen.
- Face (fake client): 32 pictures built from the real buttons; icon, colour,
  greying, cooldown (duration object, never `SetCooldown`), range dot,
  checked, glow, count, the main bar's special pictures, empty slot; a stance
  or targeting bar swapped into an anchor is mirrored, and the normal bar
  again when it leaves; the active bar at full and others at 50% from the
  callback; no callback, all full; a page change re-reads; updates collected
  into one; no `OnUpdate` left when idle; nothing registered and no hook
  doing work while off.
- "Difficult game" for every new call: missing, returns nil, raises, returns a
  secret value: the face shows the safe fallback and never errors.
- Fallback: face not built, bars stay visible; 3 errors, bars come back; off
  puts back the anchors' alpha and the hint setting; something else setting
  an anchor's alpha while on gets 0 back.
- Taps: the face's frames take the mouse and have no click handler.

## Version

`## Version: 0.13.0`, CHANGELOG, `docs/TESTING.md` section 27, the mockup
page gets the new screen (the same page, one setup), pre-release `v0.13.0`
with both zips (Pocket Probe unchanged at 0.7.0).
