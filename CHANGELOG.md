# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

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
