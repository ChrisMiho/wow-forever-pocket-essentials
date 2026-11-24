# The playing screen: a cleaner layout, then slim bars (0.16.0 and 0.17.0)

Status: approved by the owner 2026-11-24 ("approved with sub agents").

## Why

The split controller bars work (0.15.0, device-tested in town 2026-11-24). The owner:
"now we need to make it look pretty", "a lot of my screen is unfortunately just cluttered
with UI components that are useful but really take away from me enjoying the game", and
"im really only worried about whats on the screen WHILE PLAYING". The windows a player opens
(bags, character, spellbook, quest log, vendor, menus) stay Blizzard's.

What the 2026-11-24 screenshots show: the LB / RB tags sit on the round green and red
buttons beside the map; the place-name strip touches the spell pictures; the tooltip covers
the target frame; the pet frame floats alone; the chat is a dark box a third of the screen
wide; the quest list and the PE button fill the left edge.

The owner chose the look on a mockup (private page,
https://claude.ai/artifact/B6emNUJNYkzyeQPghzaMAH, artboard "Option 1: map stays bottom
middle"): "this looks like the exact modern and nice looking layout i was looking for".
The numbers below are that mockup's.

## Goals

- Nothing on the playing screen overlaps anything else, at every Spell panel size and with
  either or both triggers held.
- The middle and top of the screen are clear; the pieces sit in a band along the bottom and
  in the corners.
- Flat and plain: black one-pixel borders, dark see-through panels, no gold art, on the
  pieces this work touches.
- Nothing gets smaller than it is today: the map, the spell pictures and the text sizes stay.
- The owner can tell on the device what each release cost: a performance reading before and
  after.

## Not goals

- The second arrangement (map in a top corner). The owner wants it one day; one setup at a
  time.
- A square map. The mail, tracking and day / night icons on the map's rim: left as they are.
- Any window the player opens. The names over characters' heads. The XP bar (stays as
  0.11.1 put it).
- The player's own buffs redrawn, or buff boxes for the player or the target of target.
- New option rows for each piece's place. One setup.

## Anti-goals

- Anything of the game's moved, hidden or changed during a fight.
- Anything that ticks: no timers, no per-frame work while nothing changed.
- A piece that cannot be put back: switching Controller layout off returns every piece and
  every game setting this work touched to what the player had.
- The game's real frames deleted or replaced. They stay alive.

## Constraints

- All of this is part of Controller layout (error key `ctrlLayout`) and is on only while
  that switch is on. It reaches existing users the way 0.12.0 did: the template number goes
  up, the layout is rebuilt out of a fight, one reload is asked for.
- Every game call new to the addon is checked in `Gethe/wow-ui-source`, branch `forever`;
  what cannot be proven there is logged in `docs/ARCHITECTURE.md` with its worst case.
- The game hides some values from addons in a fight ("secret" values). Already checked in the
  source for 0.17.0: `UnitHealth` returns secret values, and `StatusBar:SetMinMaxValues`,
  `StatusBar:SetValue` and `FontString:SetText` accept them from addon code. Buff and debuff
  data (`C_UnitAuras`) is restricted in a fight; what remains readable is not known.
- No libraries. Handlers through `PE:Safe` / `PE:Wrap`.

## Approaches

1. **Our own plain display pieces over the game's invisible frames** (chosen). The way the
   spell pictures work since 0.13.0: the game's frame stays alive and takes every press, it
   is made invisible out of a fight, and plain frames of ours draw the look. Proven on the
   device and allowed in a fight.
2. **Reshape Blizzard's own frames** (hide their art, resize them). Rejected: they have a
   fixed size (player and target 232 by 100), are guarded in a fight, and change with game
   updates.
3. **A full reskin of every window**, as ElvUI does. Rejected by the owner for now: only the
   playing screen matters first.

Two releases, the owner's choice ("we can go with the two releases"): the arrangement first,
the slim bars second, so each device test judges one thing and the buff boxes are built on
what the probe measured.

## The layout

Positions are pixels on a 1280 by 720 screen (the owner's), "up" from the bottom edge, x
from the left edge unless "from the centre". Game units are pixels times 768 / 720. Where a
real size does not fit, the builder keeps the arrangement, moves the piece the least, and
writes it under "As built".

### 0.16.0: the arrangement

| Piece | Where | Notes |
|---|---|---|
| Controls reminder (the game's hint box) | its own spot, tight in the top left corner | hidden by default as since 0.13.0; a new row brings it back (below) |
| PE button | bottom left corner, 16 in and 16 up | only its default spot moves; a spot the player chose with Move stays |
| Chat | left edge, 16 in, 420 wide; the lowest line of text ends 214 up; the tabs in a row above the text | no dark box behind the text; the five tabs stay and work as today, faint until chat is opened; the owner's text size (16) is not changed; room for about six lines |
| Quest list | right edge, from the top | the game's own width |
| The player's buffs | along the top, left of the quest list | the debuffs with them, as today |
| Swing timers | three stacked directly above the map, centred on it | each no wider than the gap between the two sides' pieces |
| Map | bottom middle, today's size (round, about 140 across) | the gold ring hidden, a plain black border drawn in its place; rim icons untouched |
| Place name and clock | directly under the map, no wider than the map | must not reach the spell pictures at any Spell panel size |
| Coordinates | kept, inside the map's lower rim or wherever they sit today if that overlaps nothing | the owner: "i wouldnt mind holding onto those too" |
| The green and red targeting pictures (LB / RB) | moved off the "LB + LT" / "RB + RT" prompts they cover today, to the nearest clear spot beside them | the wheel buttons and their prompts stay where they are (`MainActionBarFrame.xml:94-135`); only the two targeting pictures move. An open wheel may cover a targeting picture while it is open. (Claude's call: the mockup drew this as one row of two pieces; the game has three pieces a side.) |
| Spell pictures (the diamonds) | as 0.15.0 | unchanged, including the Spell panel size rules |
| Player, pet, target, target of target frames | Blizzard's, where 0.15.0 puts them | replaced in 0.17.0 |
| Tooltip | right edge, directly above the target frame's highest piece | moves to the corner in 0.17.0 |

The controls reminder row, on the Controller and layout tab: "Controls reminder", On / Off,
default Off. On shows the game's box (its setting `GamepadShowPersistentInputLegend`) while
the layout is on; Off hides it as today. The value the player had before the layout is still
remembered and written back when the layout goes off. The quest list no longer shares that
corner, so both states are free of overlap.

A second new row on the same tab: "Map buttons", Shown / Hidden, default Hidden. It is the
magnifier and the calendar button beside the place name (the owner: "can we hide them
behind a toggle until i figure out what i wanna do with them? i dont even use them on
desktop, but maybe others do?"). Hidden: the strip is the place name and clock only. Shown:
both buttons as the game draws them, about 10 clear either side of the strip. Both are put
back when the layout goes off. The overlap check passes in both states.

The flat look in 0.16.0 (Claude's call): only the map's border and the chat's box change
their look. The place-name strip, the swing timers, the prompts and the PE button keep the
look they have; the mockup's flat versions of those are not built in this release.

Known pinches while Blizzard's unit frames are still on screen (0.16.0 only; the builder
settles each under "As built" and the overlap check must pass):

- The PE button's corner is inside the player frame's rectangle: the button goes to the
  nearest free spot to the bottom left corner.
- The chat's lowest line meets the pet frame at 100%, and the frames at 110% and 120%: the
  chat rises just enough to clear them.
- The buffs sit under the XP bars. A tall tooltip may reach the quest list; that is accepted.
- The plan's place-name strip was 152 wide, without its magnifier and calendar buttons; with
  them it measures about 185. The check uses the real width.

The coordinates under the map are the game's own (`minimapShowPlayerCoords`,
`Blizzard_Minimap/Mainline/Minimap.lua:1420-1430`) and move with the map. The five chat tabs
are the player's own chat windows; the addon creates none.

The pet ring (the wheel on RB) is not moved in 0.16.0. Its place is looked at after the
device test.

### As built (0.16.0)

In game units (UI units at scale 1, 1365.33 by 768, x from the centre, y up from the bottom),
as `ControllerLayout.lua` has them; each number's source is cited there.

- Map: at the bottom edge (y 0), so the strip is 8 to 31 up and the round map 49 to 188 up.
  Moved 4 right of the centre (map spot x -6, was -10): with the map buttons shown the
  magnifier would otherwise reach 4 into the inner left diamond; it now ends at its edge
  (x -103) at every Spell panel size.
- Place-name strip with its two buttons: 191 wide, not 185 (the magnifier's button reaches 20
  past the strip's left edge, the calendar 19 past its right).
- Swing timers: centred on the round map (x 4), 194, 208 and 222 up.
- LB / RB targeting pictures: 178 to 214 either side, 4 outside the prompts, 155 to 187 up
  (level with the prompts' top half rather than centred on them at 142): lower, they would
  reach into the game's own bars at full size, which show while our pictures are off.
- Tooltip: at 110% and 120% it sits 265 in from the right edge (lined up with the buffs' right
  edge, 10 left of the quest list) instead of 10: over the risen target of target it would
  reach the quest list, which ends 363 up.
- Chat: its bottom 245 up (80% to 100%), 317 (110%), 322 (120%); the PE button at its largest
  size is always higher than the pet frame, so the chat clears the button.
- PE button: bottom left, 10 in, 162 up (80% to 100%), 234 (110%), 239 (120%).
- Hint box: taken at 200 by 100, its background's size in the game's file; the game sizes it
  to what it lists.
- Left as the game has them: each "LB + LT" / "RB + RT" prompt reaches 1 into its own sub-menu
  button (one piece of the game's), and 9 into the top two game bars while they show at full
  size (only while our pictures are off; as in 0.15.0).
- Probe, Stop and Fight buttons: there was no room beside the PE button's new spot (Stop
  overlapped the pet frame by 6 units, Fight more; the other sides hit the screen edge, the
  chat or the player frame). While the controller layout is placed they sit on the left edge
  above the chat (x 10, Stop's bottom 30 over the chat's top: 445 up at 80% to 100%, 517 at
  110%, 522 at 120%), Fight to the right of Stop; checked clear of every rectangle at every
  size. Without the layout they sit beside the PE button as before.
- Probe, the four buff trials have no row of their own in the probe's window (its ten tabs
  were full and an eleventh would break the tap-size rule); they run from the Fight button
  and Run all, and their results are saved and read by `scripts/read-probe.sh` as usual.
- Probe, after the final review: six buff trials, all without a row. `aura.custom` (the game's
  container for addons) runs from the Fight button; `aura.ignore` changes a frame of the
  game's, so it is risky and runs only in the automatic pass out of a fight with Risky and Auto
  on.
- Chat: the dark box is hidden by hiding its textures as well as setting its see-through to
  0, because the game's fade-in would otherwise bring it back to at least 0.25. A pop-up
  whisper window keeps its box for now.
- Map buttons Hidden also hides the addon badge under the calendar button, so it does not
  float alone.
- Not settled: a full row of 11 buffs reaches x -47, into the quest arrow's "top" spot (the
  arrow is not part of the layout); a short row does not.

### 0.17.0: the slim bars

Built on the probe's results from the 0.16.0 test; this part of the document is updated with
them before its plan is written.

| Piece | Where | Look |
|---|---|---|
| Player bar | above the left diamonds, spanning both (264 wide), 132 to 158 up | health 18 tall with the level and name left and the health number right; the power bar 6 tall under it; no portrait |
| Pet bar | above the player bar, left-aligned with it, 128 by 16 | health and name |
| Pet's buff and debuff boxes | a row of 20-pixel boxes directly above the pet bar, from its left edge | so they read as the pet's, not the player's |
| Target bar | the mirror of the player bar, above the right diamonds | hostile red, friendly green |
| Target of target bar | above the target bar, right-aligned with it, 128 by 16 | health and name; no boxes |
| Target's buff and debuff boxes | a row of 20-pixel boxes above the target bar, from its left edge, beside the target of target bar | |
| Target's cast bar | a thin bar directly under the target bar | |
| Tooltip | bottom right corner, which the target frame has left | |

Buff boxes: the owner is "okay with just starting with the blizzard boxes". Which of these
is built depends on the probe: Blizzard's own icons kept showing in that spot while the rest
of the target frame is invisible; or plain boxes of ours showing what a fight leaves
readable (at least the icon; the countdown and stack number only if readable). If neither
works in a fight the boxes are left out of 0.17.0 and the owner is told.

The game's four unit frames stay alive and invisible, as the real bars do. The slim bars are
display only; nothing is clicked on them.

Fallback if the performance reading shows a cost the owner can feel: Blizzard's frames come
back, placed above the diamonds as closely as their size allows.

## The probe (Pocket Probe 0.8.0, shipped with 0.16.0)

- In a real fight, on the target and the pet: which buff and debuff facts an addon can read
  (how many, icon, stack number, time left), and whether a box of ours can show an icon and
  a countdown from them.
- Whether Blizzard's own buff icons on the target frame can stay visible while the frame's
  other art is invisible.
- Added at the final review: the target frame's buff container is told to ignore its parents'
  see-through and put back at once (out of a fight, Risky and Auto on); the game's own buff
  container for addons (`CustomAuraContainerTemplate`, made at load) is pointed at the target in
  a fight; the box of ours also tries the duration object and the stack text; every read and
  call is noted as accepted, refused or missing.
- The performance recording, in town and in a fight, as the "before" reading.

## Left to the builder

- How the chat's dark box is removed and how the chat is placed and sized, and that the
  player's own chat settings come back when the layout goes off.
- How the tooltip's default spot is set.
- How the map's gold ring is hidden and the black border drawn, and what re-applies it when
  the game redraws the ring.
- Exact offsets, and the spots at Spell panel sizes 110% and 120%, where the frames rise.
- The slim bars' file and internals, following `FaceBars.lua`'s pattern.

## Tests

- The layout plan's overlap check covers every piece in the 0.16.0 table, at all five Spell
  panel sizes, at rest and with LT, RT and both held, with the controls reminder on and
  off, and with the map buttons shown and hidden.
- The map buttons row: default Hidden; each state hides or shows both buttons; both come
  back when the layout goes off.
- The reminder row: default Off; On and Off each write the game setting once; the player's
  earlier value comes back when the layout goes off.
- An existing user with the older template gets the new arrangement after one reload, once.
- Device test (the owner): the screenshots' five collisions are gone; chat tabs switch; a
  long message wraps and stays readable; the tooltip no longer covers the target; the probe's
  results and the performance file are sent back.

## Versions

Pocket Essentials 0.16.0 with Pocket Probe 0.8.0, as a GitHub pre-release holding both zips.
Then 0.17.0 after the owner's device test.
