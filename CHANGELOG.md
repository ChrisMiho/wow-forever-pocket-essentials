# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [0.21.0] - 2026-11-25

Forty-first test build: a way to get on your mount without a spell slot.
**Not yet tested on a device, and nothing here can run the game: whether the
game lets an addon's tap call the mount at all is the first thing to find
out.** Spec `docs/superpowers/specs/2026-11-25-0.21.0-mount-slot.md`. It sits
on top of 0.20.0 and 0.19.0.

### Added

- **Quick slots, first slot: the mount.** A new row in the Chat tab,
  **Quick slots** (Off by default). With it On, the window the round PE
  button opens ends with a "Quick slots" line holding one square with your
  mount's picture. Tap PE, tap the square: you get on and the window closes.
  The same two taps get you off (the square has a gold edge and reads "Get
  off" while you are mounted). Nothing is put on your spell bars.
- **Which mount: the row "Mount".** It steps through the mounts this
  character owns with - and +. Until you pick one it reads **First
  favourite**: a mount you starred in the Collections menu if there is one,
  else the first mount you can use; the small line under it names the mount
  that means right now. The choice is saved for each character.
- **In a fight** the square is greyed, and a tap summons nothing:
  the line reads "Not in a fight" and the window stays open.
- **Where you cannot mount** (indoors, swimming) the picture is greyed, and
  a tap still asks the game, which says why in its own red text.
- **With no mount** the square shows "?" and reads "No mount yet".
- The square is one more stop for the d-pad in that window, after the chat
  buttons and before Settings and Close.

### Notes

- Quick slots needs **Chat picker** On: the square lives in its window. With
  Chat picker Off the row reads "Quick slots: Needs Chat picker" and nothing
  is built.
- The two new rows are in the settings only, not in the setup guide.
- Nothing listens or ticks for this, On or Off. The game is asked about your
  mounts only when the window is drawn, when the square is tapped, and when
  the settings show the Mount row with Quick slots On (Off, your mounts are
  never read). So a square drawn before a fight started
  is not greyed until you tap it or open the window again; the tap is still
  stopped.
- The game's "random favourite" call is not used: the game's own button for
  it is switched off on this client.
- For the technically minded: four new game calls, all found in Blizzard's
  source for this build (`C_MountJournal.GetMountIDs`, `GetMountInfoByID`,
  `SummonByID`, `Dismiss`) plus `IsMounted`. Not known until the device:
  whether a tap from an addon may summon. If the game refuses it, the Errors
  page will show a blocked `SummonByID`; switch the row Off and tell me.

## [0.20.0] - 2026-11-25

Fortieth test build: the rest of what you asked for after the first sitting
of 0.18.0. **Made while you were at work: tell me what to change. Not yet
tested on a device.** Spec
`docs/superpowers/specs/2026-11-25-0.20.0-after-first-sitting.md`. It sits on
top of 0.19.0 (the square map), so this one build has both.

### Added

- **Whole names on the slim bars.** "Forgot Shards" now reads "Forgot
  Shards", not "Forgot". A new row on the Controller tab, under Slim bars:
  **Names on the bars**, with **Whole name** (the default) and **First
  name**. It changes the bars at once, no reload. A name too long for its bar
  is cut with "..."; the small pet and target of target bars cut sooner. The
  level and the health number stay where they are.

### Changed

- **Your arrangement is the built-in one.** The pieces now start where you
  put them on 2026-11-25: the four spell panels 16 lower, the LB and RB
  targeting pictures in beside the map, the slim bars a little further out
  and lower, the buffs and debuffs 4 higher. "Reset" and "Reset all" in the
  Arrange window go back to this arrangement, and every piece you had moved
  now reads "At its built-in spot".
- **Nothing on your screen should move.** Your saved moves are counted from
  the new spots, once, at the first login. With **Arrange it yourself On**
  every piece stays exactly where it was and no reload is asked for. Your
  other characters are done the same way at their own first login.
- **With Arrange it yourself Off the screen does take the new spots:** the
  spell panels, targeting pictures and slim bars at once, and the buffs and
  debuffs after one reload (chat says "The controller layout has a new
  built-in arrangement" and the card asks for the reload). If you had moved
  the buffs yourself in Edit Mode, that move is replaced.
- **The spell wheel buttons can be moved without a second switch.** They are
  the two round buttons over "LB + LT" and "RB + RT" (the ones that open your
  pet's and other spells). With Arrange it yourself On, the piece **Spell
  wheels and their buttons** is always in the Arrange window. It moves up and
  down only, both sides together, and the window says so.
- **The square map's warning is gone.** 0.19.0 said "With the square map 3
  pairs of pieces overlap" with Slim bars On and nothing moved. With your
  arrangement built in nothing overlaps there, so the card says nothing.

### Removed

- **The seven "Part: ..." rows.** They were for finding the refused actions
  of 0.16.0 to 0.16.2. Every part of the layout is always on now; an Off you
  had left on one of them is forgotten, so the split spell panels are back
  without you doing anything. The seventh, "Part: follow the triggers with a
  hook", was never tried on a device and is gone with its code.
- **The row "Arrange: spell wheels"** (see above). If you had moved the
  wheels while it was On, they stay moved. A move saved while it was Off was
  never used and is dropped.

### Good to know

- **Names:** the bar joins the second name the way the game's own frames
  do on this client. If the game hides a name in a fight, the bar shows the
  first name, or keeps the whole name it already had.
- **Spell panel size 110% and 120%:** your arrangement was made at 100%. At
  the two larger sizes the panels reach a little under the screen's bottom
  edge and up into the LB and RB pictures, and the card says "2 pairs of
  pieces overlap. Arrange the screen shows which, and moves them." 80%, 90%
  and 100% fit.
- **The map's "2 down"** from your arrangement is not built in: the game
  does not let the map go under the screen's edge, so it did nothing. Your
  saved move is kept as it is.
- **The Debug log knows all of it:** `slim bars: names: whole` or `first`,
  and once `a surname was joined for the player bar`; `arrange: built-in
  arrangement 2`, and one line per piece counted from the new spots
  (`arrange: moved into the built-in spots: player bar -18,-16 -> 0,0`).
- Buff and debuff boxes on the bars are still to come (they wait for the
  probe's "Buffs in a fight" run).

## [0.19.0] - 2026-11-25

Thirty-ninth test build: the square map. **Made while you were at work, from
the look you picked ("C for sure, i like the bigger map"): tell me what to
change. Not yet tested on a device.** Spec
`docs/superpowers/specs/2026-11-25-0.19.0-square-map.md`.

### Added

- **Map look** (Controller tab, a new row under Slim bars): **Round** (the
  map as it is today, and the default) or **Square, bigger**. Square gives a
  square map 200 across (the round one is 139), at the bottom middle between
  the two inner spell panels, with a thin black edge like the slim bars.
  Changing the row asks for one reload, because the game sets the map's size
  itself; the square shape, the edge and the words appear at once.
- **Inside the square map:** the place name at the top middle, in the
  game's own colour for the kind of zone; the clock at the bottom right, the
  same time the game's own clock shows (local or realm, 12 or 24 hours, as
  you have it set); your coordinates at the bottom left. A place name too
  long for the map is cut with "...".
- **No strip under the map** with Square: the place name and the clock are
  in the map now.
- **Quest icons use the corners.** On the square map an icon shows anywhere
  inside the square, and a hand-in spot that is further away sits on the
  square's edge in its direction, as it sits on the round map's rim today.
- **The Debug log knows all of it:** lines starting `map look:` say when the
  square was put on, where its edge is, which coordinates text is used and
  where each small piece on the map sits. **Save a snapshot** lists them too.

### Changed (only with Square)

- The three swing timers sit 14 higher, just over the bigger map.
- The LB and RB targeting pictures start 20 further out. With the moves you
  saved on 2026-11-25 they end up right beside the square map, as on the
  picture you chose; nothing else you moved changes place.

### Good to know

- **Round is exactly 0.18.0.** With the row on Round nothing of this runs
  and every piece is where it was.
- **Two taps are gone with Square.** A tap on the place name used to open
  the world map, and a tap on the clock the game's clock window (stopwatch
  and alarm). With the strip hidden neither is there; the world map still
  opens the usual way.
- **Map buttons** (the magnifier and the calendar) belong to the strip, so
  with Square that row reads "Map buttons: Round map only". Your choice is
  kept for the round map.
- **The small pieces on the map are not moved yet:** the day and night mark,
  the mail mark, the zoom buttons. They were placed for a round map. Look
  where they sit on the square one and say what you want done with them.
- **The coordinates:** if the game's own "coordinates on the minimap" option
  is on, the game's own text is moved into the corner; otherwise the addon
  draws its own. Either way they sit bottom left.
- **If the game will not take the square shape,** the map stays round (at
  the bigger size, with its black border) and the Controller card says "The
  square map is not possible on this game version: the map stays round."
- **Slim bars On, Square, and nothing moved with Arrange it yourself:** the
  LB and RB targeting pictures then reach a little into the inner ends of
  the slim bars, and the card says "With the square map 3 pairs of pieces
  overlap." Arrange it yourself moves them. With your saved arrangement
  nothing overlaps.
- **The map cannot be pushed under the screen's bottom edge with Arrange it
  yourself.** The game holds the map's box on the screen, so a move further
  down than the edge does nothing (your saved "2 down" on the map is such a
  move). The square map's own low spot is done another way and is not
  affected.
- Nothing is changed in a fight: a change of the row waits for its end.

## [0.18.0] - 2026-11-24

Thirty-eighth test build: arrange it yourself. **A first version, made
without you: tell me what to change.** Spec
`docs/superpowers/specs/2026-11-24-0.18.0-arrange.md`. **First device
sitting, 2026-11-25** (a warlock with a Voidwalker, free play, not the
numbered steps): pieces moved and applied, "working great"; the saved file
shows every Apply with 0 overlaps and exact mirrors, and no refused action.
Asked for: a better built-in arrangement (theirs), and the spell wheel
buttons could not be moved (their switch was Off).

### Added

- **Arrange it yourself** (Controller tab, a new row, Off by default). On,
  and after a reload, the row **Arrange the screen** opens a small window
  where you pick a piece of the layout and move it with four arrow buttons.
  Touch and the controller both work (the d-pad walks to a button, A presses
  it, B closes), as in Move on screen.
- **What you can move.** At once, as you press: the spell panels (inner and
  outer, each side), the LB and RB targeting pictures, the slim bars. After
  **Apply** and one reload, because the game places them itself: the map,
  the swing timers, the XP bars, the chat, the quest list, the buffs and
  debuffs, the tooltip, and the game's player and target frames. The window
  says which kind the picked piece is.
- **Symmetry is looked after for you.**
  - A piece with a twin on the other side (a spell panel, a targeting
    picture, a slim bar, a frame) moves its twin with it, as an exact
    mirror. One button, **Twins**, lets a pair move freely if you want
    that; switching it back makes them a mirror again.
  - Steps are whole: **small (2)** or **big (10)**.
  - A piece in the middle (the map, the timers, the XP bars) that comes
    within 6 of the screen's centre line lands exactly on it, and the window
    says "On the centre line".
  - The window tells you when a pair is **not** an exact mirror, and counts
    any other pair that is not.
- **Overlap warning.** A piece that overlaps another is named in the window
  and the other one is outlined in red. It only warns: you may leave it so.
- **Reset** puts the picked piece back; **Reset all** (two taps) puts
  everything back.
- **Arrange: spell wheels** (a second row, Off by default). On, the two
  LB+LT / RB+RT wheels, their round buttons and the prompts under them are
  one more piece you can move **up and down**, so the wheels can open clear
  of the swing timers and the map.
- **The Debug log knows all of it:** every step, every refused step and why,
  every reset, and on **Apply** the place of every piece, every overlap and
  the mirror check, so an arrangement you like can become the built-in one.
  **Save a snapshot** lists your moves too.

### Good to know

- **Off means off.** While the row is Off nothing of this runs and every
  piece is exactly where 0.17.0 puts it, even if you have moves saved. They
  are kept for when you switch it On again.
- **The switch counts from the next reload,** and asks for it.
- **Your moves sit on top of the built-in layout.** A later version that
  moves a built-in spot moves your piece along with it.
- **Where moves are saved.** The pieces that move at once: per character.
  The pieces that need Apply: for all your characters, because the game
  keeps one "Pocket Essentials" Edit Mode layout for the whole account.
- **Nothing is moved in a fight.** A fight closes the window; your moves are
  kept and any piece still waiting for Apply goes on waiting.
- **The yellow outline is the planned spot,** not a measurement: for a piece
  that needs Apply it shows where it will be after the reload, and the quest
  list and the tooltip are drawn at a standard size.
- **The spell wheels only move as a pair, up and down.** The game hangs both
  on one anchor; moving one alone, or the two apart, is not possible
  without a call the addon must not make.
- One tap is one step; holding a button does not repeat (use the big step).
- The PE button is still moved with Move on screen.
- **Apply tells the truth.** If the game does not take the write, the window
  stays open and says "NOT written"; your moves are kept and you can tap
  Apply again.
- **Changing a swing timer's row** (Ranged, Main hand, Off hand) writes all
  three timers with the move you gave them, so they always stay stacked.
- **Switched Off but not yet reloaded,** the Arrange button says so and does
  not open. And if the game was reloaded before an Off could be written
  (tapped in a fight), the next login puts the moved pieces back and asks
  for one more reload.
- With the spell pictures off (their Part row, or after an error) the four
  spell panels are not in the list; the spell wheels still move.

## [0.17.0] - 2026-11-24

Thirty-seventh test build: the slim bars, the second half of the new playing
screen. Spec `docs/superpowers/specs/2026-11-24-0.17.0-slim-bars.md`. **First device
sitting, 2026-11-25** (free play, not the numbered steps): no errors; the
bars followed one fight (14:25, 56 seconds) with no stopped bar and no
refused action; taps where the game's frames were do nothing. Asked for:
the whole name on a bar ("Forgot Shards" shows as "Forgot"). Buff and
debuff boxes still wait for the probe run.

### Added

- **Slim bars** (Controller tab, a new row, Off by default). On, the game's
  player, pet, target and target-of-target frames go invisible and five flat
  bars of the addon's take their place, a little out from the map on each
  side, above the spell panels:
  - **You:** health with your level and name on the left and the health
    number on the right, and a thin power bar under it.
  - **Your target:** the same on the right side. Red for something you can
    attack, grey when someone else's group tagged it, green otherwise.
  - **Your pet:** a small bar with its name, above the left end of yours.
  - **Your target's target:** a small bar above the right end of the
    target's.
  - **Your target's cast:** a thin yellow bar under the target bar while it
    casts or channels, with the spell's name.
- **The tooltip moves to the bottom right corner** while Slim bars is On,
  where the game's target frame used to be.
- **Debug log and Save a snapshot know the bars:** a line when they start and
  stop with where each one is, a line each time a bar appears or goes and
  why, and the snapshot lists them.

### Not in yet

- **The buff and debuff boxes are not built.** They wait for the probe's
  "buffs in a fight" test. Their room is kept free. Until they are in,
  **with Slim bars On you do not see your target's buffs and debuffs
  anywhere**: the game draws them on its target frame, which is invisible.
  Your own buffs along the top are not touched.
- Also not shown while Slim bars is On, because the game draws them on the
  frames that are now invisible: portraits, the target's level badge and
  elite border, raid marks, the resting and fighting marks on your own frame,
  your pet's mood, and whatever your class adds to your frame. **That
  includes combo points:** a rogue or a cat-form druid does not see them
  while Slim bars is On. Drawing them is a later piece.

### Good to know

- **The switch counts from the next reload,** and asks for it: the tooltip's
  spot is part of the Edit Mode layout, which only changes with a reload.
- **The game's frames are still there, only invisible,** and are put back
  exactly as they were when you switch Slim bars or the Controller layout
  off. Nothing of the game's is changed during a fight: if the layout goes
  off in a fight, the bars stay until the fight is over.
- **A tap where the game's frames used to be does nothing.** Without that, a
  tap on what looks like empty ground would target yourself or open a menu.
  The cost: the right-click menus of those frames cannot be reached while
  Slim bars is On.
- The bars are the same size and in the same place at every Spell panel
  size.
- The target-of-target bar's health may be a moment behind when your
  target is attacking someone other than you or your pet: the game sends no
  signal for it. A channelled spell fills up like a normal cast.
- If the bars hit an error three times they turn themselves off for the
  session, bring the game's frames back and say so in chat.
- A bar that turns **grey with a "?"** for its number has stopped getting
  values from the game (it would otherwise stand still and look fine). It
  goes back to normal by itself when values arrive again.

## [0.16.4] - 2026-11-24

Thirty-sixth test build: clean-up after the refused controller actions, and
the tools for one long device test of everything that follows. Spec
`docs/superpowers/specs/2026-11-24-0.16.4-cleanup.md`. **On the device
2026-11-25** as part of 0.18.0: no refused action in any 0.18.0 sitting;
marks and snapshots write to the log. The Part rows kept the Off values of
the day before and hid the split panels until set back to On: they are to be
removed. The hook row was not tried.

### Added

- **Mark a test section** (Debug log tab and Controller tab): writes a
  numbered line to the debug log and says "Section N marked" in chat, so a
  long test can be read back section by section. The number goes on after a
  reload and starts again when the log is emptied.
- **Save a snapshot** (same two places): writes to the debug log where every
  piece of the Controller layout is (the game's frames, the spell panels, the
  PE button), how big, and which ones overlap, with the screen size, the
  active layout and every switch. In a fight it waits for the fight to end.
- **Debug log, spell pictures:** one line each time the panels change, saying
  which bar the game has active and what is drawn where.
- **A check for the mistake behind 0.16.0's refused actions** (for whoever
  builds the addon, not seen in game): every game function the addon calls is
  now listed with whether it leaves the addon's mark on the game's own data,
  and a new one fails the tests until it has been read.

### Changed

- **Debug log holds 6,000 lines (was 3,000) and keeps each session's start.**
  When it is full the middle is dropped, not the beginning: the first lines of
  each session, the section marks, the snapshots and the newest 3,000 lines
  stay, and a line says how many were dropped.
- **The six "Test:" rows on the Controller tab are now "Part:" rows.** They
  are the switches for the parts of the layout. Still On by default, and a
  change still counts from the next reload.
- **A seventh Part row, "Part: follow the triggers with a hook", Off by
  default.** Off, the spell pictures follow LT and RT the way they did up to
  0.16.3, which worked on the device. On tries a second way that writes
  nothing of the addon's into the game's own data; it has never run on a
  device, so it has its own test step. Counts from the next reload.

### Fixed

- **The Inspect button (top of the right pad) drew as a black square.** It
  and the other special buttons now sit on a grey button face with a light
  rim.
- **Targeting bars (LB or RB held): portraits.** The buttons that show a
  face (yourself, your pet, your target's target, a party member) are now
  drawn the way the game draws them, not copied.

### Looked at, not changed

- **Enemy targeting, the empty B square:** the game itself shows nothing
  there while your target has no target of its own (or its target is you).
  The hint list names "Assist Target" all the time.
- **Friendly targeting showing the RT panels:** that is what holding LB and
  RT together gives. The new debug line records which buttons the game saw,
  so the device test can settle it.
- **Game build 71091:** three of the game's files the addon reads changed;
  none of the changes reaches the addon.

## [0.16.3] - 2026-11-24

Thirty-fifth test build: the fix for the refused controller actions. Found
on the device with 0.16.2's testing rows: every part of the Controller layout
was clean except the chat's dark box. Device test, 2026-11-24: no refused
action with the whole layout on; layout off puts everything back; some minor
overlap remains.

### Fixed

- **The game refused its own controller actions while the Controller layout
  was on** (targeting yourself or your pet, the B button, jump, spell presses;
  "Interface action failed because of an AddOn"). The layout removed the
  chat's dark box with a game function that leaves the addon's mark on the
  chat window. It now only hides the box's pictures and shows them again when
  the layout goes off.

### Kept for now

- The six testing rows on the Controller tab stay until this is confirmed on
  the device.

## [0.16.2] - 2026-11-24

Thirty-fourth test build: a finder build, not a fix. With the Controller
layout on, the game still refuses its controller actions. Plan
`docs/superpowers/plans/2026-11-24-blocked-action-0.16.1.md`. Not yet tested
on a device.

### Added

- **Six testing rows** at the bottom of the Controller tab, each On or Off,
  default On: Test: hint box, chat box, map ring and buttons, move the game's
  bars, targeting pictures, spell pictures. Off leaves that part of the layout
  out from the next reload, to find the part that makes the game refuse its
  controller actions. They go away once it is found.

## [0.16.1] - 2026-11-24

Thirty-third test build: a diagnostic build, not a fix. On 0.16.0 with the
Controller layout on, the game refused its own controller actions in Pocket
Essentials' name (127 times in two minutes, among them the B button, jump and
one spell press), and the Errors page did not show where from. Plan
`docs/superpowers/plans/2026-11-24-blocked-action-0.16.1.md`. Not yet tested
on a device. **The refusals are still there while the Controller layout is
on:** this build is for finding them.

### Changed

- **Errors page, a refused action:** shows the game's own steps behind it (up
  to eight), without the addon's own recording lines that filled the list
  before. A repeat shows its newest steps.
- **Debug log:** the steps behind a refused action are written for the first
  three refusals of each action in a session, not for every one, so repeats
  no longer push everything else out of the log.

## [0.16.0] - 2026-11-24

Thirty-second test build: the playing screen's arrangement (the first half;
the slim bars follow in 0.17.0). Spec
`docs/superpowers/specs/2026-11-24-playing-screen-layout-design.md`. Not yet
tested on a device. Pocket Probe goes to 0.8.0 (bundled in the pre-release;
it is for testing only).

### Changed

- **Controller layout, a new arrangement** (at your first login after
  updating, the addon rebuilds the layout by itself and asks for one reload;
  tap Rebuild the layout only if it does not): the chat sits at the left edge with its tabs in a row above the
  text and no dark box behind it; the quest list sits at the right edge from
  the top; your buffs and debuffs run along the top, left of the quest list;
  the map sits at the bottom middle with a plain black border instead of the
  gold ring; the place name and clock sit right under it; the three swing
  timers stack above the map; the green and red targeting pictures (LB and RB)
  moved off the "LB + LT" and "RB + RT" prompts; the tooltip sits at the right
  edge above your target's frame. Nothing overlaps at any Spell panel size:
  checked offline, waiting for the device test.
- **The PE button's first spot** follows the layout: bottom left corner while
  the layout is on, where it was when it is off. A spot you chose with Move on
  screen stays as you set it, and moving it from the bottom left corner starts
  from where it sits.

### Added

- **Controls reminder** (Controller tab): On or Off, default Off. On shows
  the game's own box of button hints while the layout is on.
- **Map buttons** (Controller tab): Shown or Hidden, default Hidden. They are
  the magnifier and the calendar beside the place name. Switching the layout
  off puts everything back: the chat box, the map's ring, both buttons, the
  reminder.
- **Pocket Probe 0.8.0:** "Buffs in a fight" trials (what a fight leaves
  readable of the target's and your pet's buffs, and whether the game's own
  buff box for addons fills for your target), run from the Fight button and
  Run all. One more, out of a fight with Risky and Auto on: whether the
  target frame's buff icons can stay visible while the rest of the frame
  fades (it puts the frame back at once). While the layout is on, Stop and
  Fight sit on the left edge above the chat.

### Not yet

- The player, pet, target and target of target frames are still the game's;
  the slim bars replace them in 0.17.0, built on the probe's results.
- A pop-up whisper window may still show its dark box.

## [0.15.0] - 2026-11-24

Thirty-first test build: polish before the first public post. Every file was
read by a reviewer, and the confirmed bugs and rough edges are fixed. Spec
`docs/superpowers/specs/2026-11-24-0.15.0-polish.md`. Not yet tested on a
device. Your saved choices carry over (see the whisper list below). Pocket
Probe is unchanged (0.7.0).

### Added

- **Spell panel size** (Controller tab): 80% to 120%. The pictures and the
  game's hidden bars follow; at 110% and 120% your frame and your target's
  rise above the panels (between 80% and 100% the frames stay where they
  are, including where you moved them in Edit Mode). A change needs a reload (the card
  shows Reload now); in a fight it waits for the fight to end.

### Changed

- **Your whisper list belongs to each character.** It no longer sits in the
  shared file you send with a bug report, and an alt no longer shows your
  main's whisperers. Each character starts with an empty list once.
- **The sell line counts what was sold:** "Sold 20 junk items for 1s 4c"
  counts items (not stacks) and their price, so buying food or a buyback in
  the same visit no longer changes the figure, and closing the vendor at once
  no longer reports too little.
- **Quest icons keep the spots in every zone.** A quest with hundreds of
  spots across several zones could lose every icon in a small zone (often
  the one where the drop actually is). Each zone now keeps its own share.
  Heavy quests also make far less garbage when they update.
- **Clearer words** in the settings, the guide and the chat lines: one name,
  "Move on screen", for the move panel; the same labels in the guide and the
  settings ("Size of all buttons", "Round button colour", "I play with");
  shorter labels that no longer wrap at 720p; "Go to: <name>" for explore
  spots; the Controller card describes the panels; the "Template" row is
  "Rebuild the layout"; "Main hand timer", "Off hand timer"; the guide is
  titled "Setup guide".
- **Tidier windows:** the scroll tabs show arrows instead of "^" and "v";
  the Quest icon key page has its title; the Debug log switch lines up with
  the other switches; the Errors page has the same spacing as the other tabs;
  on the guide's first screen Skip sits at the left edge; "Your screen" says
  where each piece is now; "All set" lists the features in the guide's order.
- **Move on screen** opened from the settings brings the settings back when
  you close it.
- **The Sort tab hides while the bank is open** (it sat over the bank's bag
  slots). The stick sort still works there.
- **Debug log** holds 3,000 lines (was 10,000), so it loads and saves faster.
  A longer saved log keeps its newest lines. Its rebuild line now shows the
  real work time, not the waiting between steps.
- **Quest arrow:** "Hidden inside dungeons, raids and battlegrounds."

### Fixed

- **Controller layout:** switching it on needed two reloads when your old
  saved layout was from an earlier version; now one. A spell stayed dark
  after its cooldown ended until you cast something; it now brightens when
  the cooldown ends, and also after a slot gets a different spell. If the
  spell pictures cannot be made, the game's own bars come back at full size
  (they stayed small). The status line no longer contradicts itself.
- **Minimap quest icons** come back after leaving a dungeon (they could stay
  off until the next zone change).
- **Quest arrow** switches to the turn-in when a quest completes at the same
  NPC as its objective.
- **Chat picker:** a channel that went away while the picker was open (you
  left a city or a group) now says "That channel is gone." instead of
  sending to the wrong channel.
- **Loot sparkles:** switched off in a fight and reloaded before the fight
  ended, the sparkles stayed on for good; they are now put back at the next
  login. The "restart the game" line shows only when a restart is needed.
- **Errors page with the d-pad:** Right from Previous moves to Next, and
  Clear all can be reached from any error.
- **Catch all errors:** clear wording when another, unnamed addon takes the
  errors, and for errors from a macro or an unknown source.
- A job held for the end of a fight could run twice.

### Known

- A wheel or the "new spell" picture opened from a spell button shows where
  the game's hidden button is, not always at that spell's picture.
- The game's page number sits just above the left panel while you hold the
  page button.
- Pet and possess bar pictures show no cooldown.

## [0.14.0] - 2026-11-24

Thirtieth test build. Controller layout shows one bigger panel each side of
the map, and holding a trigger swaps what it shows. Spec
`docs/superpowers/specs/2026-11-23-controller-layout-0.14.0-console.md`.
Not yet tested on a device. Your saved choices carry over. Pocket Probe is
unchanged (0.7.0).

### Changed

- **Only two diamonds at rest:** your main bar's d-pad spells left of the
  map, its face-button spells right of it. The other bars are hidden until
  you hold their trigger.
- **The triggers swap the panel:** hold LT and the left side opens into two
  diamonds (LT d-pad on the outside, LT face buttons next to the map); the
  main face buttons on the right stay, dimmed. Hold RT and the right side
  does the same (RT d-pad next to the map, RT face buttons outside); the
  main d-pad on the left stays, dimmed. Hold both and the two diamonds next
  to the map show the LT+RT bar. Let go and the main bar is back. The d-pad
  diamond is always left of its face diamond, the way you hold the
  controller. The swap is instant and works in a fight.
- **Bigger pictures:** each spell picture is half as big again (42 instead
  of 28), and the button picture, range dot and stack count grew with it.
- **Frames further out:** your frame and your target's moved out past the
  outer diamonds; the target's cast bar and buffs moved with it and stay on
  screen. The LB / RB targeting pictures sit beside the map.
- The game's bars, still invisible and still doing the casting, sit smaller
  (60%) under the two diamonds next to the map.
- Your next login rebuilds the layout once (as 0.13.0 did); tap Reload now.

### Known

- A wheel or the "new spell" picture opened from a spell button shows where
  the game's hidden button is (under a diamond next to the map), which is
  not always where that spell's picture is drawn.
- The game's page number can show near the left pictures while you hold the
  page button.

## [0.13.0] - 2026-11-23

Twenty-ninth test build. Controller layout draws its own spell pictures,
split the way you hold the controller, in one low band at the bottom of the
screen. Spec
`docs/superpowers/specs/2026-11-23-controller-layout-0.13.0-face-bars.md`.
Not yet tested on a device. Your saved choices carry over. Pocket Probe is
unchanged (0.7.0).

### Added

- **Spell pictures of our own ("face bars"):** with Controller layout on,
  Pocket Essentials draws all four of your bars itself. Left of the map are
  the d-pad halves, right of it the face-button halves, like the controller
  in your hands. Each side is a small grid: the main bar nearest the map at
  the bottom, LT above it, RT on the outside, LT + RT outside and up ("up is
  LT, out is RT"). Each picture shows the spell, a small picture of which
  button presses it, greying when it can't be used, blue when you lack mana,
  darkening and the game's sweep while on cooldown, a range dot, stack
  counts, a gold edge while active and a glow when the game highlights it.
- **The bar in use stands out:** holding LT, RT or both brings that bar to
  full strength and the others drop to half. Nothing moves.
- **The game's own bars still do the casting.** They stay whole, invisible,
  under our pictures; you press the same buttons as before. Stance, form,
  possess and LB / RB targeting bars show in our pictures too.
- **A safety net:** if the pictures cannot be built, or hit three errors, the
  game's own bars come back by themselves and the Controller card says why.

### Changed

- **Everything moved down and in:** your frame sits beside the left
  pictures with your pet above it, the target beside the right pictures with
  the target of target above it; the target's cast bar sits in the bottom
  right corner. The middle of the screen is free.
- **The game's hint box (top left) is hidden** while the layout is on (the
  game's own "show input legend" setting, put back when you switch the
  layout off). The quest tracker moved into that corner.
- Your next login rebuilds the layout once (as 0.12.0 did); tap Reload now.

### Known

- Tapping a spell picture does nothing; cast with the controller.
- The cooldown sweep may not draw on this client; the darkening still shows.
- Numbers for cooldowns are not shown (the game keeps them secret in a fight).
- A wheel or the "new spell" picture opened from a spell button shows where
  the game's hidden button is, not at its picture.
- The game's page number can show over the left pictures while you hold the
  page button.

## [0.12.0] - 2026-11-23

Twenty-eighth test build. Controller layout now arranges the screen the way
the "Face bars (one setup)" mockup draws it. Spec
`docs/superpowers/specs/2026-11-23-controller-layout-0.12.0-mockup-setup.md`.
Not yet tested on a device. Your saved choices carry over.

### Changed

- **Controller layout, the mockup's setup:** the map sits at the bottom
  middle at 70%, with its zone and clock strip under it and the swing timers
  under that. The game's four spell bars stay whole and sit in the bottom
  corners: the LT bar over the main bar on the left, the RT bar over the LT +
  RT bar on the right, all at full size. Your frame sits above the left
  bars with your pet above it; the target frame sits above the right bars
  with the target of target above it, and the target's buffs show above the
  target frame so they and its cast bar stay clear of the spell bars. The two sub-menu buttons and the LB / RB
  targeting pictures stay beside the map where you know them. XP bar, chat,
  buffs and debuffs as in 0.11.1; the quest tracker moved to the screen's
  right edge.
- **One setup:** the rows for the main bar, the map size, the frames, the
  swing timers' spot, the spell button size and the three bar sizes are gone.
  The three timer rows (Always / In combat / Hidden) and Start over stay.
- **No taps needed:** if you are already on the Pocket Essentials layout, your
  next login rebuilds it in the new arrangement once and says so in chat;
  open the settings and tap Reload now to finish. While it waits for a fight
  to end or for the game's layouts, the Controller card says so.

### Known

- The game's quest tracker is wider than the mockup drew it: when it holds a
  long list, its lower left corner reaches over the right end of the target
  frame, the target's cast bar and the corner of the RT bar.
- The rebuild replaces any changes you made to the Pocket Essentials layout in
  Edit Mode; the chat line says so.

## [0.11.2] - 2026-11-23

Twenty-seventh test build. A fix for 0.11.1 from the owner's debug log. Not
yet tested on a device. Your saved choices carry over.

### Fixed

- **Controller layout, each character:** the layout never switched on,
  because the character's name could not be read on the device (the debug
  log said "waiting for the character's name" at every login). Each
  character's old layout is now kept in the game's own per-character saved
  file instead, so no name is needed. With the debug log on, one line says
  which part of the name could not be read, to find the cause.

## [0.11.1] - 2026-11-23

Twenty-sixth test build. The clear bugs from the owner's level 40 main
(`docs/11-23-ui-debug/FINDINGS.md`). Spec
`docs/superpowers/specs/2026-11-23-controller-layout-0.11.1.md`. Released
together with Pocket Probe 0.7.0 in one GitHub pre-release. Not yet tested on
a device. Your saved choices carry over.

### Fixed

- **Controller layout, XP bar at the top:** the XP bar now sits at the very
  top of the screen, centred, at 100% width, clear of the controller hints
  and the chat. It stayed at the bottom in 0.11.0 (a miss in the spec).
- **Controller layout, each character:** with the switch On, a character
  that is still on its own layout switches to ours at login (out of a
  fight, once the game has loaded its layouts) and remembers its own.
  Switching off on that character brings its own back; another character
  gets its own back at its next login. Before, it needed off, reload, on,
  reload. A chat line says when a login changed the layout and a reload
  finishes it. If the switch at login fails, the switch stays on and the
  next login tries again.
- **Controller layout, map title under the map:** the zone name and clock
  strip now sits under the map instead of on top of it (the game's own
  "header underneath" setting).
- **Controller layout, buffs clear of the chat:** the buffs, debuffs and the
  quest tracker sit 30 lower, so they no longer cover the chat's last lines.
  The chat keeps its size.
- These template changes reach a layout that already exists only through
  **Start over** on the Controller tab (which also undoes your own Edit
  Mode changes to it).

### Added

- **Pocket Probe 0.7.0** (testing tool, in the same GitHub pre-release as
  its own `PocketProbe.zip`; never in the player zips). Spec
  `docs/superpowers/specs/2026-11-23-pocket-probe-0.7.0.md`. It answers the
  questions for the "face bars" (our own pictures of the spells, over the
  game's invisible real bars) with almost nothing to do in a fight.
  - **Fight button:** a round amber button beside Stop, shown only in a
    fight and only while the watchers are armed or a recording runs. One tap
    runs Fight tests. A recording pauses for the pass and carries on by
    itself.
  - **Watch my next fights:** one tap out of a fight, then nothing to do
    until a reload. It counts which bar is active as you hold the triggers,
    your presses, and how often the bar events fire, in and out of fights;
    the first time a main-bar spell goes on cooldown in a fight it tries the
    cooldown sweep on a square of ours and takes a screenshot. Counts only.
  - **Fade for next fight:** start it before a fight; the main bar vanishes
    when the fight starts and comes back when it ends, then one question:
    did your spells cast?
  - **Wheels on a faded bar:** out of a fight, all four bars fade; open the
    pet wheel and a spell wheel, then say whether they showed.
  - **Clear saved results:** two taps empty the probe's results, watcher
    counts and recordings. Its switches and Pocket Essentials are untouched.
  - **Recorder report:** a memory reading of 0 counts as missing, reloads
    are marked and the 30 seconds after each are left out of "In plain
    words", and a run under 10 minutes says "too short to judge".
  - The Probe button sits a little lower, out of the XP bar's way.

## [0.11.0] - 2026-11-22

Twenty-fifth test build. From the owner, for the controller UI round:
"minimap in center middle, we could build out the buttons around the map and
then stick the chat up where the map used to be". First built while the owner
was away, before the probe round; the probe has since run on the device
(`docs/11-22-playsession/EVIDENCE.md`) and its measurements are now in.
Specs `docs/superpowers/specs/2026-11-21-controller-layout.md` and
`2026-11-22-controller-layout-measured-sizes.md`. Released together with
Pocket Probe 0.6.0 in one GitHub pre-release. Not yet tested on a device:
the map's size is measured and the bar's size is Blizzard's own, but every
spot and gap is still a first guess. Your saved choices carry over.

### Added

- **Controller layout** (new switch on a new **Controller** tab, off to
  start with, marked experimental): one switch gives a new screen
  arrangement for controller play. It needs the game's Gamepad UI.
  - It creates a new Edit Mode layout named "Pocket Essentials", switches
    to it and asks for a reload. Your own layouts are never changed.
    Switching off goes back to the layout you had, with a reload.
  - The map sits bottom middle; the chat is bigger, top right, with the
    buffs and the quest tracker under it; the XP bar is wider.
  - The left-trigger bar sits left of the map and the right-trigger bar
    right of it. The main bar is above the map, or under it. The
    both-triggers bar is smaller, above them.
  - **Map size**: 60%, 70% or 80% (starts at 80%). The probe measured the
    map at 273 by 283, a third bigger than the mockup assumed, so the bars
    now sit around the real map and the map can be made smaller.
  - Choices: where the main bar goes; where the player, pet and target
    frames go (corners, stacked, or side by side); one size for all spell
    buttons (starts at 100%) with three fine-tunes; where the swing timers go; and for each
    swing timer Always, In combat or Hidden.
  - It is a starting point: what you then move in Edit Mode is kept.
    "Start over" rebuilds the layout from the template.
- **Setup guide:** a Controller screen with the same switch.
- **A sleeping measuring hook** in the addon's core, for testing only.
  Nothing in Pocket Essentials switches it on and there is no setting for
  it; only Pocket Probe's recorder does. Asleep, it costs one yes-or-no
  check each time a feature's code runs. Awake, it times each run and adds
  it up per feature. Nothing is saved; a reload puts it back to sleep.
  Spec `docs/superpowers/specs/2026-11-21-perf-recorder.md`.
- **Pocket Probe 0.6.0** (testing tool, in the same GitHub pre-release as
  this build, as its own `PocketProbe.zip`; never in the player zips). Specs
  `docs/superpowers/specs/2026-11-22-pocket-probe-0.5.0.md` (0.5.0 was not
  released by itself) and `2026-11-21-perf-recorder.md`.
  - **Performance recorder**: with Pocket Essentials loaded it records
    while you play. A red dot shows bottom right and a round Stop button
    sits beside the PE button; the Probe window's title bar has Stop and
    Start recording. Every 15 seconds it notes time per frame, memory for
    Pocket Essentials, QuestieDB and the probe, the frame rate, the cost of
    each feature, and what you were doing (fighting, in a dungeon, at a
    vendor, map open, bags open, moving). Two hours at most; the last three
    recordings are kept. `scripts/read-probe.sh <file> --perf` prints the
    report, `--perf --diff <other file>` compares two. Tests and recording
    never run together: "Recording: tap Stop first."
  - **Fight tests** button: one tap in a fight runs what is worth running
    there and leaves out what is known to be refused. It ends with "Fight
    tests done: N run, A allowed or readable, B refused".
  - **Park the main bar** is clearer: big letters on screen say what to do,
    the probe records which bars were shown and where just before and just
    after, and takes a screenshot at both moments.
  - **Fade the main bar to nothing, then press a spell** (new, guided, also
    in a fight): does an invisible bar still cast?
  - **Fade the left bar to nothing and back** (new): a real see-through
    change in a fight, not only "the value it already has".
  - **Cooldown sweep** (three new trials): whether a square of our own can
    show the game's cooldown sweep in a fight, from the game's duration
    object or from the start and duration numbers. Two small squares show
    for 8 seconds so the answer can be seen.
  - Sizes: the map's inner container and the three other bars are measured
    too.
  - "Open and close the bags" moved to the Bags and vendor tab to make room.
  - Device steps: `docs/TESTING.md` sections 23 and 24.
- **Pocket Probe 0.4.0** (testing tool, released on its own as the GitHub
  pre-release `probe-v0.4.0` before this build): ten new trials. They
  measure the real sizes of the map, frames, buff rows, quest tracker, XP
  bar, sub-menu buttons, pet wheel, bars and one spell button; test the moves
  this build relies on; and answer what a flat strip of spells under the map
  would need: whether the main bar's spells can be read in a fight, whether a
  bar can be faded in a fight, whether a controller press still casts with
  the main bar parked off screen (a guided trial), and which pictures the
  game uses for the controller buttons. Device steps: `docs/TESTING.md`
  section 22.

### Known gaps

- Spell button size starts at 100%. Below that, a spell that opens its own
  wheel from a bar may open the wheel beside its button (unconfirmed).
- Switching off during a fight and reloading before the fight ends leaves
  the Pocket Essentials layout active. Switch on and off again to fix it.
- Turning the game's Gamepad UI off makes the game pick its own Modern
  layout. Switch the feature off first.

### Not as drawn in the mockup

- The main bar is whole, not split around the map. The game puts every
  spell button back beside its bar's centre at each button press, in combat
  too, and an addon may not move a spell button in combat.
- The both-triggers bar has one spot. "Swap" waits for the probe's fade
  result.
- The two sub-menu buttons sit either side of the map at a fixed distance,
  and their wheels are the game's own. The game does not let them be
  placed freely or resized safely.
- The target's target stays attached to the target frame.

## [0.10.0] - 2026-11-20

Twenty-fourth test build. From the owner, after a Blizzard error popped up on
the handheld: "we need another feature to make managing bugs easier ...
almost working like how bugsack works". Built while the owner was away ("keep
working and release when done"). Spec
`docs/superpowers/specs/2026-11-20-error-catcher-and-probe-panel.md` (Part 2).
Not yet tested on a device. Your saved choices carry over.

### Added

- **Catch all errors** (new switch on the Errors tab, off to start with):
  every Lua error, from the game and from other addons, goes into one list,
  not only Pocket Essentials' own.
  - **One error per page**, BugSack-style: who caused it, how often and when,
    the message, then the stack. **< Previous** and **Next >** (or d-pad
    Left/Right), "3 of 12", and **Clear all**. A filter row picks All, Pocket
    Essentials, Blizzard or Other addons.
  - **Error popup: Show / Hide.** Hide keeps the game's small error box from
    popping up and taking the controller; hidden errors still show in this
    list. Switching the feature off puts the popup back as it was.
  - **Stands aside for BugSack** (or BugGrabber, Swatter): the switch is
    dimmed and the card says why and how to choose this one instead (turn
    BugSack off in the AddOns list). It never switches another addon off.
  - Pocket Essentials still lists its own errors with the switch off.

### Changed

- **Debug log has its own tab**, under Errors.
- **Choices that do not fit grow wider** into the empty space beside their
  name, so no choice is cut off.

## [0.9.1] - 2026-11-20

Twenty-third test build. From the owner, after installing 0.9.0: "this latest
build looks great, but i have some minor tweaks". Specs
`docs/superpowers/specs/2026-11-20-0.9.0-ui-redesign.md` (0.9.1 changes) and
`docs/superpowers/specs/2026-11-20-loot-sparkles.md`. Not yet tested on a
device. Your saved choices carry over.

### Added

- **Loot sparkles** (new switch, off to start with): brings back the sparkle
  on things you can loot or use, even on the lowest graphics. It turns the
  game's own sparkle setting back on and keeps it on after graphics changes.
  Switching it off puts the old setting back; the sparkles go after a full
  game restart. Based on
  [ForeverLootSparkles](https://github.com/svengabr/ForeverLootSparkles) by
  Ashtar Senior (GPL-3.0-or-later).

### Changed

- **Game fixes** is the new name of the Menu background tab; it holds Menu
  background and Loot sparkles. In the setup guide the screen is "Vendors and
  game fixes".
- **Setup guide, Welcome:** the controller pictures show which face button
  (bottom, right) does what, so they fit any controller.
- **Setup guide, d-pad:** the highlight starts on the screen's first control
  (usually the switch), not on Close. Down from the last control goes to
  Next; Left from Next goes to Skip, then Back.
- **Setup guide, less text:** one sentence for Menu background, and the round
  button and chat screen says once what a tap does.

## [0.9.0] - 2026-11-20

Twenty-second test build. A new look for every window, built from the mockups
the owner reviewed in four rounds ("i am so happy with this setup, this looks
incredible"). Spec `docs/superpowers/specs/2026-11-20-0.9.0-ui-redesign.md`;
mockups `docs/ui-review/mockup-0.8.1.html`. Not yet tested on a device. Your
saved choices carry over (the old arrow size becomes a percentage once).

### Changed

- **Settings have tabs.** Down the left: Quest icons, Quest arrow, Bags,
  Vendors, Chat, Menu background, General, Errors. One page at a time on the
  right. A green dot on a tab means a helper there is on.
- **Every row looks the same:** the name on the left, one control of one width
  on the right. There are four controls: an On/Off switch, a row of joined
  choices (the chosen one is gold), a − number + box, and a single button.
  The fold buttons, the bottom row of buttons and the "press and hold" tip are
  gone. The scroll bar shows only when a page is too long.
- **New names:** Bigger bag (was Bag window), Bag sorting (was Bag sorter),
  Auto sell junk, Auto repair, Chat picker (was Chat from round button). Each
  has one short line under its name.
- **Quest arrow:** one size control, 50% to 150% in steps of 10, for the
  arrow and its text together. It no longer follows Button size, and it can
  also be set in Move on screen while you watch the arrow. The quest line is
  smaller and starts with "Quest:" (or "Turn in:"). "Here" is green. "Turn
  around" shows no arrow. "No known location" now reads "No map data for this
  quest". New: "No quest focused" can hide itself in cities and inns (on by
  default).
- **Chat picker window:** only as big as its buttons, in 3 columns under
  "Talk in" and "Whispers", with its own size control (70% to 150%). The
  "Three-finger tap" hint is gone. Unanswered whispers get a round red dot.
- **Bigger bag** always puts the bag pictures in one row at the top (the
  "Bag icons" choice is gone). Off, the game shows its own bag.
- **Sort tab:** the same size, but rounded on the outside and joined to the
  bag, with the sort picture and "Sort" in the middle.
- **General tab:** Button size, Round button colour, "I play with: Touch
  controls / Controller", Move things on screen, Setup guide, Reload.
- **Move on screen** always lists all three pieces; one whose helper is off
  says "(off)". The chat prompt is now listed as "Press A to type".
- **Setup guide:** 9 shorter screens with dots for progress, the same cards
  as the settings, every choice included, controller-button pictures on the
  first screen, a Round button screen, a "Your screen" picture of where each
  piece starts with a "Move things now" button, and tip tiles at the end.

## [0.8.1] - 2026-11-19

Twenty-first test build. From the owner, after installing 0.8.0: "im really
happy so far", with four points about the settings. Spec
`docs/superpowers/specs/2026-11-19-0.8.1-clearer-labels.md`. Not yet tested
on a device. Your saved choices carry over as they are.

### Changed

- **Hide Blue Quest Haze** (was "Hide blue haze") and **Quest Icon Key**
  (was "Icon key") sit side by side on one line in the Quest icons options,
  in the settings and in the setup guide. The key page is now called
  "Pocket Essentials - Quest Icon Key". With the d-pad, press Right from
  the toggle to reach Quest Icon Key (Down now goes to the next line).
- **Chat from round button** is the new name of "Big chat buttons". The
  line under it says what it does: "Tap the round button to choose who to
  talk to: Say, Party, Guild or someone who whispered you." Chat text size
  stays under it.
- **The round button moves off the map.** While the map is open at its
  normal size, the round PE button sits on the map's book icon in the
  top-left corner; it goes back to its spot when the map closes or goes full
  screen. Tap and hold work as before. Always on, no setting.
- **Buttons are one size.** In the settings and the setup guide, every
  button in a row is the same width (3 button heights), so they line up in
  columns; a longer label takes two or more widths. A toggle such as
  **Touch screen: Yes/No** is wide enough for both sides, so it no longer
  changes size when you tap it.

### Not changed yet

- **Menu background** did not put a panel behind the quest log's quest menu
  on the device. This build does not change it: a debug log from the device
  (steps in `docs/TESTING.md` section 17) will show where it goes wrong.

## [0.8.0] - 2026-11-18

Twentieth test build. From the owner, after trying 0.7.0: "do the next 3, and
call the release 0.8.0", plus fixes for Merge nearby icons, the setup guide's
first page and the ugly Up and Down buttons. Spec
`docs/superpowers/specs/2026-11-18-0.8.0-design.md`. Not yet tested on a
device. Your saved choices carry over as they are.

### Changed

- **Move the arrow** (in Quest arrow) and **Move the round button** (in the
  main settings) replace the position buttons. Each opens **Move on screen**
  with that piece picked. **Reset** puts the piece back to the starting
  spot. Nothing you already placed moves.
- **"Move things" is now "Move on screen".**
- **Bags is now two features.**
  - **Bag window:** **Bag size** and **Bag icons**.
  - **Bag sorter:** **Sort button** (On / Off) and **Sort stick** (Left /
    Right).
  - **D-pad to Sort** is now automatic whenever the Sort button shows.
  - **Button only** is gone: a saved one now sorts with the left stick too.
  - The first time 0.8.0 loads, **Bag window** is switched on if you used
    **Bag sorter**, with your size and icons as they were.
- **Button colour:** Gold, Horde or Alliance for the round button.
- **Merge icons closer than N%** (for example 2%, of the map) replaces the old number, with
  "of map" under it.
- **Setup guide, first page:** the highlight starts on **Start**. A new
  question asks whether you use the touch screen. **No** turns off the Sort
  button and the scroll bar.
- **A slim scroll bar** replaces the big Up and Down buttons: an arrow at
  each end and a marker showing where you are in the list. Tap the track to
  page. A new **Touch screen: Yes / No** setting turns it on or off.

## [0.7.0] - 2026-11-18

Nineteenth test build. From the owner, after trying 0.6.0: fine-tune the
Quest icons rows, a smaller arrow, a nicer chat text size row. Spec
`docs/superpowers/specs/2026-11-18-number-control-design.md`. Not yet tested
on a device. Your saved choices carry over as they are.

### Changed

- **A new number control: - value +.** One joined, gold-edged box with the
  number large in the middle and a small word under it. An end that can go
  no further is dimmed. The d-pad stops on - and +.
  - **Spots per objective:** any number from 1 to 20, then **All**.
  - **Merge nearby icons:** **Off**, then 1 to 10 (higher merges icons that
    are further apart). The old "Normal" is 2 and "More" is 5.
  - **Chat text size:** the same box replaces Smaller and Bigger.
- **Icon size: Extra small**, a little smaller than Small.
- **Arrow size: Small**, about three quarters of Normal.
- **Hide blue haze** moved to the bottom of Quest icons, just before Icon key.
- `/qd spots` takes any number from 1 to 20; `/qd cluster` goes up to 10;
  `/qd size xsmall`.

## [0.6.0] - 2026-11-18

Eighteenth test build. From the owner: fewer buttons and less clutter in the
settings. Spec `docs/superpowers/specs/2026-11-18-tidier-settings.md`. Not yet
tested on a device. Your saved choices carry over as they are.

### Changed

- **One-tap toggles.** A choice with only two sides is now one button that
  says what it is set to, and a tap flips it: **Hide blue haze: On**,
  **D-pad to Sort: Off**, **Bag icons: In the grid**. Green means on.
  Toggles next to each other share a line, with no heading above them.
- **Quest icons: "Icons on"** replaces the separate "Map icons" and "Minimap
  icons" rows: **Map and minimap** / **Map only** / **Minimap only**.
  (`/qd map` and `/qd mini` still work.)
- **Bag sorter: "How to sort"** replaces "Sort key" and "Sort button":
  **Button + left stick** / **Button + right stick** / **Button only** /
  **Left stick only** / **Right stick only**. You can no longer end up with
  no way to sort (before, "Button only" with the button hidden did that; such
  a saved setting gets the button back).
- **Headings beside their buttons.** A row's name now sits on the same line
  as its buttons, to their left, when they fit, so each row takes about half
  the height. A row with too many buttons for one line keeps its name above,
  as before. The same goes for "Button size" and "Round button position".
- The setup guide shows all of this the same way (it draws options with the
  same code).

### Fixed

- Nothing shipped was affected, but the offline tests found and fixed two
  slips in the new code before release: a saved `false` read as "nothing
  chosen", and a toggle whose other side is `false` would not flip.

## [0.5.0] - 2026-11-18

Seventeenth test build. From the owner's first look at the setup guide: it
only had the ON / OFF switches, and the choices of each feature were left to
the settings. Now you set each feature up in the guide itself. Not yet tested
on a device.

### Changed

- **Setup guide: each feature's options are in the guide**, under its switch,
  exactly as the settings window shows them: the same labels, the same
  buttons, the same saved values. Switch a feature on and its choices appear
  under it at once (for example Quest icons: which quests, map and minimap
  icons, icon size; Bag sorter: bag size, sort key, "D-pad to Sort", "Bag
  icons"). **Chat text size** (Smaller, the number, Bigger) is on the Chat
  screen whether "Big chat buttons" is on or off. A choice made in the guide
  shows in the settings, and the other way round. There are no "Hide
  options" buttons in the guide: the options are simply there.
- **Setup guide: one screen per feature**, nine screens where there were
  seven: Welcome, Quest icons, Quest arrow, Menu background, Bags, Vendors
  (Sell junk and Repair, which have no options, share one), Chat, "The round
  button and moving things", and All set. The texts are shorter where the
  buttons now speak for themselves.
- A screen that becomes too long when a feature is switched on gets the
  **Up** and **Down** buttons on the right, as in 0.4.1; a screen that fits
  still has none. The d-pad reaches every button and scrolls to it.
- If a choice needs a reload, the last screen offers it, as it already did
  for a switch.
- **Icon key** (under Quest icons) opens the settings' Icon key page from the
  guide too, which closes the guide. Open the guide again from the settings.

### Internal

- The settings window and the setup guide draw options with one piece of
  code (the "list drawer" in `Settings.lua`), not two copies. The settings
  window looks and behaves as before.

## [0.4.1] - 2026-11-18

Sixteenth test build. From the owner's first look at 0.4.0 on the device: the
setup guide and the rest showed no problems, but the guide had Up and Down
buttons down its right side that did nothing.

### Changed

- Setup guide: the **Up** and **Down** buttons are gone from every screen
  that fits in the window, and the text uses the whole width. They only
  appear on a screen that is too long to show at once (which can happen at
  the larger button sizes), because there they are the only way to read the
  rest by touch.

## [0.4.0] - 2026-11-17

Fifteenth test build: a setup guide that explains each feature and lets you
switch on what you want, a background for the game's pop-up menus, two new
choices for the bag (the d-pad can reach the Sort tab; the bag pictures in one
row at the top), and chat text size as one small stepper. Every feature and
every new choice starts off. Not yet tested on a device.

### Added

- **Setup guide**, a window of seven screens that explains each feature in a
  few lines and has the feature's ON / OFF switch right there: Welcome,
  Quests (Quest icons, Quest arrow, Menu background), Bags, Vendors, Chat,
  "The round button and moving things", and "All set", which lists what is
  switched on and what is still off. Every feature still starts off; the
  guide is how you find out what there is and turn on what you want.
  - It opens by itself a moment after the first loading screen, once, on an
    account that has never pressed **Finish** or **Skip** in it. If you
    already use the addon you will see it once after this update, with your
    switches exactly as you left them.
  - A switch in the guide is the same switch as in the settings: it acts at
    once and is saved at once. Nothing waits for Finish.
  - **Back**, **Skip** and **Next** sit in the bottom row. With the
    controller, the d-pad moves the blue highlight, A presses and B closes;
    the highlight stays on Next, so pressing A again and again walks through
    the guide.
  - Only Finish and Skip are remembered (for every character on the
    account). Close, B, Escape, or the game closing its windows only hide
    the guide; it comes back at the next login, and a chat line says so the
    first time.
  - It never opens during a fight. If a fight starts while it is open it
    hides at once and comes back at the same screen when the fight ends.
  - When the game hides its whole interface (a cinematic, a full-screen
    view) the guide goes and comes back with it. That is not a closing: no
    chat line, nothing remembered.
  - **Reload now** on the last screen counts as Finish, so the reload does
    not bring the guide back.
  - Open it again at any time with the new **Setup guide** button in the
    bottom row of the settings (after "Move things"), or with `/pe setup`.
  - Nothing of it exists until it is first opened, and nothing of it runs
    while it is closed.
- **Menu background**, a new switch, off by default. With it on, a plain
  dark panel with a thin grey edge sits behind the game's pop-up menus while
  they are open, so the text is easy to read. The menu it is meant for is
  the one on a quest in the quest log (Track / Focus / Share / Abandon),
  which on this client is drawn with no background. The panel is only a
  picture behind the menu: the menu's entries are not touched, it never
  takes a tap, and it goes away when the menu closes. No reload is needed
  to turn it on or off. With the debug log on, the log also says whether
  the game's own menu background picture is missing on this client.
- **D-pad to Sort**, a new choice inside "Bag sorter", Off by default. With
  it On, the Gamepad UI on and the bag open, pressing **Left** from any slot
  in the bag's first (leftmost) column moves the controller cursor onto the
  Sort tab. On the tab **A** sorts the bags, **Right** goes back into the
  bag and **B** closes the bag as usual. Left from the first column used to
  wrap round to the last column; with this On it goes to the tab first.
  A is only taken while the cursor is on the tab and is handed back when
  the cursor leaves, the bag closes, a fight starts or the choice is
  switched Off. In a fight the game does not let an addon set this up: a bag
  first opened in a fight gets the route when the fight ends, and on a tab
  reached during a fight A does nothing (the stick click still sorts).
  One limit: if you close and reopen the bag, or fold one of your bags,
  during a fight, the game may deal its item buttons out to other slots and
  the addon cannot follow until the fight ends. Until then Left may jump to
  Sort from an odd slot, or not from the first column at all. Using items is
  not affected, and it is put right the moment the fight ends.
  Touch and the stick click work exactly as before. Using, equipping,
  selling and picking up items is not changed. Not yet tested on a device:
  whether A on the tab really sorts can only be seen there.
- **Bag icons**, a new choice inside "Bag sorter": "In the grid" (as the
  game draws it, and the default) or "One row at the top". With the Gamepad
  UI on, the game draws a picture of each equipped bag inside the bag
  window, in among the item slots, where they look like loose bags lying in
  your inventory. With "One row at the top" those pictures sit side by side
  in the top row, starting at the left, and every slot follows below in the
  same order as before with nothing in between. The window keeps its size.
  Items are not moved or packed, and the bag pictures still do their jobs
  (X folds a bag away, Y opens its menu, LB and RB jump between them). When
  the slots do not fill whole rows, the short row is the first one under the
  pictures. Switching back to "In the grid", or switching "Bag sorter" off,
  puts every button back where the game had it, at once. It does nothing
  in the mouse and keyboard style, where the game does not draw those
  pictures in the bag. With "D-pad to Sort" also On, Left goes to the Sort
  tab from the slots of the leftmost column, not from the backpack picture
  above them. Not yet tested on a device: that using, moving and selling
  items still works with it on, in and out of a fight, can only be seen
  there.

### Changed

- **Chat text size** is now one small stepper: **Smaller**, the size as a
  number, **Bigger**. One press moves one step through the game's own sizes
  (12, 14, 16, 18, 20, 24, 27) and then on to 30 and 34. The number is the
  size the game is using right now, so it also follows a change made from
  the game's own chat tab menu. The buttons stop at the ends: at the
  smallest size Smaller is drawn dim, at the biggest size Bigger is, and a
  press on a dim button does nothing.
- The **Chat text size** row is now shown whether "Big chat buttons" is ON
  or OFF; it never needed that feature. Because of this the "Big chat
  buttons" block has a "Hide options" button even while it is off.
- As before, every chat window gets the same size, and a press during a
  fight is held and applied when the fight ends (the row then says, for
  example, "Chat text size: 20 (after the fight)").
- **All features stay off by default**, also after they have passed a device
  test. The earlier plan was to turn each one on for everybody once it was
  proven; the setup guide replaces that: it shows what there is and you
  switch on what you want.
- Opening the chat window now also closes the setup guide, so only one
  Pocket Essentials window is ever open.

## [0.3.1] - 2026-11-17

Fourteenth test build: the arrow's "Quest in another zone" choice from 0.3.0
is taken out again. Not yet tested on a device.

### Removed

- Quest arrow: the **"Quest in another zone"** choice ("Point the way", the
  light blue arrow). A straight line across zones does not know where the
  zones connect, so it can point at a mountain wall; doing it properly needs
  a list of crossings, which is more than this addon should carry for now.
  The owner chose to postpone it. For a quest in another zone the arrow says
  "Outside this zone / Head to <zone>", as it did before 0.3.0. If you had
  chosen "Point the way", nothing happens: the choice is simply gone.

The Layout helper stays removed.

## [0.3.0] - 2026-11-17

Thirteenth test build: the arrow can now point at a quest in another zone,
and the Layout helper is gone. Not yet tested on a device.

### Added

- Quest arrow: a new choice, **"Quest in another zone"**.
  - **Name the zone** (the default) is what you have today: "Outside this
    zone / Head to Duskwood".
  - **Point the way** shows a **light blue** arrow pointing straight at the
    quest's nearest spot in the other zone, with the distance, and
    "Duskwood - Morbent Fel" under it. When you enter the zone the arrow
    turns gold and works as before.
  - It is a straight line, not a route: it knows nothing about roads, boats
    or mountains. The colour and the zone name are there to say so.
  - It only points within the same continent. For another continent, or a
    zone the game cannot place, the text stays as it is today.
  - Changing the choice takes effect at once.

### Removed

- **Layout helper.** It was written before the first device test and never
  tried in the game, and the game already switches to its Gamepad layout by
  itself. Placing things without dragging is what "Move things" does. If you
  had it switched on, nothing happens: the row is simply gone, and your
  game's layout is left as it is.

## [0.2.1] - 2026-11-17

Twelfth test build, from the debug log of the 0.1.0 play test (two sessions,
57 fights, no error and nothing blocked). Nothing changes in how the game
plays. Not yet tested on a device.

### Debug log

- Bag sorter no longer writes "stick click given back to the game" at every
  fight when no stick was taken. A line is written only when a stick is
  really taken or handed back, and "no stick taken: button only" once per
  bag opening.

## [0.2.0] - 2026-11-17

Eleventh test build, asked for during the play test of 0.1.0: a way to put
the arrow and the other on-screen pieces exactly where you want them. Not
yet tested on a device. (0.1.0's changes are still being tested too.)

### Added

- **Move things.** A new button at the bottom of the settings opens a small
  panel that moves the addon's on-screen pieces: the quest arrow, the "Press
  A to type" text, and the round button.
  - Pick a piece from the list; a gold outline shows where it sits, even if
    the piece itself is not showing at the moment.
  - Up, Down, Left and Right move it. One press is a small nudge. Hold the
    button and it keeps moving, faster after a moment.
  - With the controller: d-pad to a button, A to press or hold it, B to
    close. Touch works on the same buttons.
  - Reset puts the piece back on its preset spot. A piece cannot be pushed
    off the screen.
  - Positions are saved as you go and remembered between sessions.
  - The panel moves to the other bottom corner if it is in the way.
  - It cannot be opened during a fight, and closes if one starts.
- The preset choices ("Arrow position", "Round button position") are still
  there as starting points. Choosing a preset puts the piece exactly on it
  again.
- This does not use the game's Edit Mode and does not touch any of the
  game's own frames.

## [0.1.0] - 2026-11-17

Tenth test build, from the first long play test of 0.0.9 (five sessions and
about twenty fights with no error and nothing blocked). Six requests from
that test, built together. Not yet tested on a device.

### Added

- Big chat buttons: after you tap a chat button, "Press A to type" now shows
  in big letters in the middle of the screen, with where the chat is going
  under it ("Chat is set to Guild"). It goes when the chat box opens, after 12
  seconds, or when a fight starts. The chat line is still printed too.
- Chat text size: under "Big chat buttons" in the settings there is a "Chat
  text size" row with Smaller and Bigger buttons. Each tap changes the game's
  chat window text one step (12 up to 34), in every chat tab, using the game's
  own setting, so it is remembered. If you tap during a fight it is applied
  when the fight ends.
- Bag sorter: a "Sort key" choice: Left stick click (as before), Right stick
  click, or Button only (no stick is taken). The stick is still only used
  while the bag is open.
- Settings: a feature that is on and has options gets a "Hide options"
  button next to its switch. Tap it to fold the options away so the list is
  shorter; "Show options" brings them back. The feature stays on either way,
  and what you folded is remembered. It works with the d-pad and A as well.

### Changed

- "One big bag" is now called "Bag sorter" (the game's controller mode
  already shows one combined bag; what this feature adds is the sorting).
  If you had it switched on, it is still on.
- Quest arrow:
  - It keeps pointing at the same spot when the quest's progress changes
    (before, every kill made it start again).
  - It only swaps to another spot when that one is clearly nearer (at least
    a fifth nearer and 15 yards nearer), so it no longer flips between two
    spots at a similar distance.
  - After it has said "Here" and you walk away, that spot is left alone for
    three minutes and the arrow leads you to the nearest spot you have not
    been to, instead of pointing back at the place you just left. When you
    have been to them all it starts again.
  - When one part of a quest is finished, the arrow moves straight to a spot
    for a part that is not.
- The "Icon key" button has moved from the bottom of the settings into the
  "Quest icons" block, next to the other quest settings.

### Debug log

- The time on each line now comes from one clock, so lines within the same
  second are in order.
- The arrow's line says which spot it points at (the objective's number and
  the place on the map) and a new line is written each time the spot changes,
  with the reason.
- The "driver started / stopped" pair is no longer written on every quest-log
  change while no quest is focused.
- The long legend on the fight lines is written once per session.

## [0.0.9] - 2026-11-17

Ninth test build, from the first Pocket Probe file sent from the device.
Not yet tested on a device.

The probe showed that, with the Gamepad UI on, an addon opening the chat box
is blocked inside the game's controller code, and that afterwards the game
refuses its own controller actions (interact, cancel, clear target) in the
addon's name until a reload. This is the likely cause of the "blocked from
an action only available to the Blizzard UI" pop-up from the fourth device
test.

### Changed

- Big chat buttons, Gamepad UI on: a tap no longer opens the chat box. It
  sets where your chat goes (Say, Party, a channel, a whisper) and a chat line
  says "Chat is set to Say. Press A to type." For the next 12 seconds the
  controller's A button opens the chat box through the game's own key
  binding, which the game allows; the button is given back when chat opens,
  when the time is up or when a fight starts. During a fight the tap still
  sets the chat, but the button cannot be lent, so the line says to open chat
  yourself. With the Gamepad UI off, a tap opens the chat box as before.
- Pocket Probe 0.2.0: the trials that upset the controller run last and only
  when "Risky trials" is switched on; what the game refuses afterwards is
  counted in the table; the one-per-reload trials watch for after-effects.

## [0.0.8] - 2026-11-17

Eighth test build, from the first debug log sent from the device (0.0.7).
Not yet tested on a device.

The log showed one block: "The game stopped a protected step of Blizzard's
own interface", from the line where Big chat buttons opens the chat box, with
the Gamepad UI on, in town and out of combat (confirmed by the owner). The
message was still sent. This build does not fix that block; it makes the next
log name the exact step.

### Added

- Pocket Probe, a separate test addon (`probe/PocketProbe/`, its own
  `PocketProbe.zip` on each GitHub release, never in the player zips and never
  on CurseForge). It tries a list of addon actions by itself in each
  situation (Gamepad UI, in and out of a fight, dungeons, vendors, straight
  from a press) and saves whether the game allowed, blocked or forbade each
  one, and which values it hides. `scripts/read-probe.sh` prints the saved
  file as a table. Not for play.

### Changed

- Big chat buttons: the "not during a fight" rule now also asks the game's
  own combat restriction, which is what Blizzard's controller code checks and
  which can be on when the usual combat flag is not. This covers blocks during
  a fight only; the block in the log happened out of combat.
- Blocked-action report: with the debug log on, the game's own lines of the
  call stack are written to the log, so the next file names the exact step
  that refused. The report also says when the combat restriction was active.
- Debug log: records each change of the game's addon restrictions.

## [0.0.7] - 2026-11-17

Seventh test build, from the fourth device test. Not yet tested on a device.

### Added

- When the game blocks something Pocket Essentials tried to do, it now says
  what: one chat line per blocked action ("The game blocked Pocket Essentials
  from using …", with the file and line), and an entry on Settings > Errors
  listing which features were on. This is to find the cause of the
  "Interface action failed" message and the "blocked from an action" pop-up.
- A debug log that can be sent as a file. Settings > Errors has a "Debug log"
  switch (off by default; `/pe debug on` and `/pe debug off` do the same).
  While it is on, the addon keeps a timestamped line for each thing it does
  or decides, up to 10,000 lines, with no player names and no chat text.
  "Save log now" reloads the interface so the game writes the file
  (`WTF/Account/<account>/SavedVariables/PocketEssentials.lua`); "Clear log"
  empties it. `scripts/read-log.sh` prints the file as plain text.
- One big bag: a "Sort button" choice (Show / Hide). Hidden, the left stick
  click still sorts.

### Changed

- One big bag: the Sort button is now a tall gold tab against the bag's left
  edge, below the round bag picture, with the game's sort icon and "Sort"
  written down it. It follows the bag size.
- Sell junk: if the game refuses a sale, selling stops for that visit with a
  chat line, instead of trying every item (which brought the pop-up back
  again and again).
- Sell junk: the first sale of a visit is checked a second later; if the item
  is still in the bag, selling stops for that visit. This covers the game
  refusing without telling the addon.
- Sell junk: nothing is sold while the vendor's Buyback tab is showing.
- Big chat buttons: a tap during a fight no longer opens the chat box; a chat
  line says to try again afterwards. With the Gamepad UI on, the game refuses
  that step to addons in combat and printed "Interface action failed".

### Fixed

Found by a code review against Blizzard's interface source, not on a device.

- Repair: "Repairing for …" is now said only after the game accepted the
  repair; a refused repair gets its own line and is not counted as money spent.
- Big chat buttons: when the chat box cannot be opened the expected way, the
  addon no longer falls back to having the game read a typed command, which
  could make a later typed `/cast` or `/target` fail.
- The blocked-action report now recognises the game's call-stack format
  ("[File.lua]:123") and no longer drops a report when it cannot read the line.
- An error repeating many times a second (for example in the arrow's update)
  now only counts up, instead of reading the call stack every time.
- Quest icons on the minimap come back after a loading screen even when the
  game is a moment late with the player's position.
- Quest icons: helper spots that QuestieDB ties to an item now get icons.

## [0.0.6] - 2026-11-15

Sixth test build. Not yet tested on a device. It also carries 0.0.5, which has
not been tested yet either.

### Added

- Quest icons: a new choice, "Spots per objective" (All, 10, 5 or 3, set to 5
  at first). Each objective now shows at most that many icons in a zone,
  spread across the area its spots cover, instead of one icon on every spot.
  An objective with fewer spots than the limit looks the same as before.
  "Merge nearby icons" works as before. It applies to the world map and the
  minimap. `/qd spots all`, `10`, `5` or `3` does the same by typing.
- The quest arrow still points at the nearest spot, and that spot always keeps
  its icon, even when it is beyond the limit.
- Settings: an "Icon key" button at the bottom opens a page that shows each
  quest icon in its real colour and what it means (Kill, Loot, Use, Explore,
  Turn in).
- Settings: a "Reload UI" button at the bottom, so you never need to type a
  reload.

## [0.0.5] - 2026-11-15

Fifth test build. Not yet tested on a device.

### Changed

- The text under the quest arrow is wider, so short messages fit on one line.
- Messages shown without an arrow ("No quest focused", "Outside this zone")
  now sit where the arrow normally is, instead of lower down.

## [0.0.4] - 2026-11-15

Fourth test build. Tested on the device: both fixes work.

### Fixed

- Green minimap with "Hide blue haze" on: we no longer swap the minimap's
  quest area textures (the blank texture is gone).
- Arrow text cut off with "...": the quest name under the arrow now wraps to
  two lines, and only names longer than two lines are cut.

## [0.0.3] - 2026-11-15

Third test build. Not yet tested on a device.

### Changed

- Quest arrow with no focused quest: instead of pointing somewhere, it says
  "No quest focused" and "Focus one in your quest log".
- Focused quest in another zone: the arrow says "Outside this zone" and
  "Head to <zone>".
- When the objective is behind you, the arrow is replaced by "Turn around".
- Quest icons: "Show icons for" now defaults to Tracked quests (your tracked
  quests plus the focused one). If 0.0.2 had you on Focused quest, you are
  moved to Tracked quests once; All quests is kept.

## [0.0.2] - 2026-11-15

Second test build, with fixes from the first device test of the quest
features. Not yet tested on a device.

### Changed

- Quest arrow follows the quest you **focus** in the quest log, instead of a
  quest picked by tapping an icon. With no quest focused, it points at your
  tracked quests. For a focused quest in another zone it names that zone.
- Quest icons: new "Show icons for" choice. Focused quest (default; with none
  focused, your tracked quests), Tracked quests, or All quests. The map is
  readable again.
- Tapping a quest icon only shows its text; it no longer changes the quest.
- Quest arrow is now a proper pointed arrow.
- The round "PE" button and the whisper badge are smooth instead of stepped.

### Fixed

- The blue haze stayed on the minimap. It is now hidden again after every
  loading screen and zone change (untested on device).

## [0.0.1] - 2026-11-15

Nothing in this version has run on a device yet.

### Added (untested on device)

- Settings window with one big on/off switch per feature, an Errors page, and
  the round "PE" button (also `/pe` and the minimap addon-list button).
- Quest icons on the map and minimap, with Blizzard's blue haze hidden.
- Quest arrow to the nearest objective in your zone, with distance.
- One big bag: Blizzard's combined bag with a big Sort button (L3 sorts while
  it is open) and three sizes.
- Sell junk automatically at vendors.
- Repair automatically from your own money.
- Big chat buttons: one per channel and per recent whisperer, with a badge for
  unanswered whispers.
- Layout helper (experimental): one-tap switch to Blizzard's Gamepad layout
  and back.

### Dependencies

- QuestieDB (the GitHub bundle pins 1.1.1; CurseForge installs the latest), for the two quest features.
