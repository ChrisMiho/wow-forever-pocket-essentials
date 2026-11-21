# Testing

This file holds the offline tests and the device test plan, steps 0 to 9. Goals live in PRD.md.

## Offline tests

These run on a computer, with no game. Their job is to catch plain mistakes
(a typo, a game function that does not exist, a rule that stopped holding)
before you spend time carrying a build to the handheld. They cannot tell you
how anything looks or feels, and they do not replace the device test below.

Nothing under `tests/`, `scripts/` or `probe/` goes into the addon. `scripts/build.sh`
copies only `addons/PocketEssentials` and QuestieDB into the zips players get, and
stops if it finds a probe file in either.

### How to run them

- `scripts/check.sh`: syntax check of every addon file. About 0.1 s.
- `scripts/test.sh`: everything below except the full audit. A few seconds.
- `scripts/audit-api.sh`: the full audit of game names. About 45 s.

`check.sh` and `test.sh` need `luajit` (`brew install luajit`). Without it they
print a notice and are skipped, so nobody is locked out. `audit-api.sh` needs
luajit too, and on the first run it downloads Blizzard's interface source
(about a minute, once). `test.sh` also downloads the pinned QuestieDB release
into `vendor/` on the first run. If that download fails (for example, you are
offline), the parts that need QuestieDB are skipped and it says so; a checksum
mismatch is a real failure. With `PE_TEST_STRICT=1` set (the GitHub job sets
it) a missing luajit or a failed QuestieDB download is a failure instead of a skip.

The same three scripts run on GitHub for every push to main and release-prep and every pull request
(`.github/workflows/test.yml`). That job only reads the repository: it
publishes nothing and uses no secrets.

### What each layer catches

1. **Fast API check** (`tests/api/`, part of `test.sh`). The game has no
   "does this function exist?" test you can run from a computer, so we asked
   the other way round: every game name the addon uses (functions, events,
   frame methods, settings) was looked up in Blizzard's own interface source
   for this client build (1.60.1, 70938). The results are saved in
   `tests/api/verified.txt` and `tests/api/unverified.txt`. The fast check
   reads the addon, and fails if it now uses a name that is in neither file.
   This catches a typo in a game function name, or a new call nobody has
   looked up yet.
2. **Full audit** (`scripts/audit-api.sh`). Redoes the lookup against
   Blizzard's source and rewrites the two files. Run it after adding or
   changing a game call, then commit the new files. Its limits: methods on
   frames are checked by name, not per kind of frame; template names, font
   names and script-type strings are not checked at all.
3. **QuestieDB harness** (`tests/questiedb/`). Puts every quest in the pinned
   QuestieDB release through our `QuestData.lua` for an Alliance and a Horde
   player, as "in the log" and as "complete", and checks that none raises an
   error and that a handful of known quests get pins in the expected places.
   `tests/questiedb/baseline.txt` records how many quests get pins. Update it
   only on purpose: when pin-building behaviour intentionally changes, or
   when the QuestieDB pin in `scripts/fetch-questiedb.sh` is bumped. Never
   update it just to make a failing run pass.
4. **Rule tests** (`tests/features/`). One file per feature (sell junk,
   repair, chat, core, bags, quest arrow, quest icons, menu background, Move
   things, the setup guide, the shared window code). Each states
   the feature's rules in plain terms ("never sells a non-grey item", "does
   nothing in combat", "off means nothing ticks") and checks them in a
   stand-in game client.
5. **Smoke test** (`tests/smoke/`). Loads every file in the addon's TOC in the
   stand-in client, the way the game would, presses every option on and off,
   checks the arrow, and fails on any error raised along the way.
6. **Debug log reader tests** (`tests/readlog/`). Checks that
   `scripts/read-log.sh` prints a wrapped log oldest line first, one block per
   session, and that the saved file it reads cannot reach files or the system.
7. **Probe reader tests** (`tests/readprobe/`). The same for
   `scripts/read-probe.sh`: the order of the columns, the tables, what differs
   between two files, and that the saved file cannot reach files or the system.
8. **Probe tests** (`tests/probe/`). Runs the restriction probe (see
   "Restriction probe" below) in the stand-in client.

The stand-in client (`tests/lib/fakeclient.lua`) is our own imitation of the
game. It only knows what we believed about the game, and its frame methods and
`C_` functions are limited to names the audit found in Blizzard's source. If
it guesses wrong about how the real game behaves, a test can pass here and
still fail on the device.

### What a known failure is

Each test file has a `KNOWN_FAILURES` table at the top. A test listed there
fails because the addon is wrong; it is kept visible until the addon is fixed. When it fails, the run prints
"known failure" and still passes. When a listed test passes, the run fails,
as a reminder to delete the entry. Known failures, if any, are listed at the
top of each test file.

### Reading the result

On a pass each suite prints one summary line and `test.sh` exits 0. On a
failure it prints `FAIL:` with the first failing item and exits 1.

### What only the device test proves

A pass here means the logic holds offline. It says nothing about:

- how anything looks (sizes, colours, whether text fits, whether a button is
  easy to tap);
- whether the game allows an action: selling, repairing, opening chat, using
  items, switching layouts;
- taint, shown as "interface action blocked" or "blocked by an addon";
- real-game quirks the stand-in does not copy (event order, timing, the
  quest log's real contents, frame rate, login time).

So far the audit found all 236 game names the addon uses in Blizzard's
source for this build (169 are in Blizzard's generated documentation; 67 are
seen only in Blizzard's own code, so their restrictions are unknown), and the
offline tests pass. That is still not evidence that anything works in the game.
The audit does not cover fields of tables the game returns, template names,
font names or script-type names, and it checks methods by name, not per
widget type.

For other addon authors: the trials are general (chat box, vendor, bags,
layout, hidden values), so the table describes the device and game build, not
Pocket Essentials. The probe only counts blocks that name `PocketProbe`; to
test another addon's own actions, add trials to `probe/PocketProbe/Trials.lua`.

## Debug log

A device test can come back as one file instead of screenshots. The addon
keeps a timestamped line for each thing it does or decides, and the game
writes those lines to disk with the saved settings.

On the device:

1. Round button → Errors. Turn **Debug log** on (it is off by default, and
   stays as you left it across logins). `/pe debug on` and `/pe debug off` do
   the same if the settings window is the thing that is broken.
2. Play until the problem happens.
3. Back on the Errors page, tap **Save log now**. This reloads the interface,
   which is when the game writes the file. Logging out writes it too.
4. Send this file:
   `World of Warcraft/_forever_/WTF/Account/<account>/SavedVariables/PocketEssentials.lua`

The line under the switch ("N of 10,000 lines") shows how much is held. When
it is full the oldest lines are replaced. Switching the log off keeps the
lines; **Clear log** removes them. The log never holds player names or chat
text.

Reading the file on a computer:

```bash
scripts/read-log.sh path/to/PocketEssentials.lua                  # the log, one block per session, then the Errors page
scripts/read-log.sh path/to/PocketEssentials.lua --grep sellJunk  # only lines matching a Lua pattern
scripts/read-log.sh path/to/PocketEssentials.lua --errors         # the Errors page only
```

Each line is `HH:MM:SS.mmm feature: what happened`. A session starts with a
header line giving the addon version, game build, features on, Gamepad UI and
screen size. The reader needs `luajit`; it only reads the file, with no access
to files or the system from inside it.

## Restriction probe

**What it is.** The game refuses some actions when an addon asks for them, and
which ones it refuses changes with the situation: Gamepad UI on or off, in a
fight or not, in the open world or in a dungeon, and whether the action came
straight from a tap. Until now we only knew this from reading Blizzard's
source, and two device tests found blocks we had not predicted. The probe
replaces guessing with a table: it tries each action on the device and writes
down whether the game allowed it.

**It is a separate addon, `PocketProbe`, and players never get it.** It lives
in `probe/PocketProbe/`, not in Pocket Essentials. It is not in the bundle zip
and never goes to CurseForge; the build stops if a probe file turns up in
either of those zips. It only reports what the game does. It never tries to
get round a block.

**What it costs.** Almost nothing. The only trials that spend anything are
the vendor ones: it sells your grey junk and repairs your gear. The
**Vendor: On / Off** switch at the bottom of its window turns those off.

### Installing it

1. On the computer, run `scripts/build.sh`. Next to the usual zips it writes
   `dist/PocketProbe.zip`.
2. Extract it into the game's AddOns folder, so `PocketProbe` sits next to
   `PocketEssentials` and `QuestieDB`.
3. **Switch Pocket Essentials' features off while probing** (round button,
   every row OFF), or untick Pocket Essentials on the character-select AddOns
   screen. That way each result belongs to the probe alone.
4. Leave "Enable Gamepad UI" on in the game's settings, as you normally play.

When you are done probing, delete the `PocketProbe` folder or untick it, and
switch your features back on.

### On the device (probe 0.3.0)

**Nothing runs by itself any more.** Logging in does nothing but put a small
**Probe** button at the top centre of the screen, with a line of text under it
saying what the probe is doing. Tap **Probe** (or type `/probe`) to open the
probe's window. It is the same size as Pocket Essentials' settings window and
looks the same.

**The window:**

- **Left: one tab per area.** Errors, Graphics, Our own windows, Blizzard
  windows, Chat box, Bags, Vendor, Controller, Layout, Settings, Values (and
  "Afterwards" once the game has refused one of its own actions in the probe's
  name). Each tab says how many of its trials have run, for example
  "5 / 7 run". There is no scroll bar: an area with more trials than fit on
  the screen is split into two tabs, such as "Values 1" and "Values 2".
- **Right: one row per trial.** Its name, then a coloured box with the
  result, then **Run**:
  - green **Allowed**: it worked;
  - amber **Blocked** (or Forbidden, Error): the game refused it;
  - grey **Not run**: not tried yet;
  - blue: what it read, for example "function" or "sparkle 0 · outline 2".
  - **Run** tries that one trial at once, straight from your tap.
  - Trials marked "(risky)" are dimmed, and their Run does nothing, while
    **Risky** is Off.
- **Details:** tap a row (not its Run) and the line under the list shows
  what happened: the game function, its message and the first lines of the
  game's stack.
- **Bottom:** **Run all safe** (every trial that is not risky, one after the
  other) · **Clean run (reloads)** · **Risky: On / Off** · **Vendor: On / Off**
  · **Auto: On / Off** · **Save (reloads)**.
- **Auto** brings back the automatic runs of probe 0.2.0 (at login, at the
  start and end of each fight, at a vendor). It starts Off.
- **Controller:** the d-pad moves (Up / Down along the tabs or the rows, Right
  from a tab to its rows and on to Run, Down past the last row to the bottom
  buttons), **A** presses, **B** closes. In a fight the d-pad is given back to
  the game; touch still works.

**Risky trials** (opening the chat box and the bags, switching the layout,
setting our own error handler) can leave the controller's interact and cancel
buttons refusing to work until a reload. If the line under the Probe button,
or the top of the window, says "controls may misbehave until a reload", tap
**Save**.

**The two new areas:**

- **Errors** (for the coming error catcher in Pocket Essentials): whether the
  game's error handler and error box are there, whether the probe can listen
  to the box (it raises one harmless test error of its own, so the game's
  error box will pop up: close it), how many errors other addons and the game
  had this session and from where, whether turning the box off works (it is
  turned back on straight away), and a risky trial with a handler of our own.
  It never saves another addon's error text, only where it came from.
- **Graphics** (why the loot sparkles do not show on the handheld): reads the
  outline and sparkle settings, writes the sparkle one (and puts it back),
  lists the setting names the game knows, and two **guided** trials. A guided
  trial has **Start** instead of Run. It changes a setting, tells you what to
  do (in the Details line and at the top of the window), and then shows two
  answer buttons. Your answer is saved and the old setting is put back.
  - **Outlines off, then restart:** after Start, fully close and restart the
    game (a reload is not enough), kill something, open the window again, go
    to Graphics and tap **Sparkles seen** or **No sparkles**.
  - **Interact icons on loot:** after Start, look at a lootable corpse, then
    tap **Icon seen** or **No icon**.

**Steps (one run of 0.3.0):**

Leave Risky off for steps 1 to 5.

1. With Pocket Essentials off and PocketProbe loaded, log in in a town. Check
   that nothing runs by itself. Tap **Probe**.
2. Tap **Run all safe** and wait for "pass done" at the top of the window.
3. Open **Errors**, tap a few rows to read their Details. Open **Graphics**
   and do **Interact icons on loot**, then **Outlines off, then restart**
   (this one needs a full restart of the game).
4. Pick a fight with something weak and tap **Run all safe** during the
   fight (by touch).
5. Open a vendor with grey items and damaged gear, open the window, switch
   to **Vendor** and tap **Run** on each row.
6. Tap **Clean run (reloads)**, then **Next (reload)** under the Probe button
   each time it appears, until it says done (13 trials). Each tap reloads the
   interface and runs one trial as the first thing after the reload, then
   watches for a few seconds for after-effects.
7. Optional, last: switch **Risky** on and tap **Run** on the risky rows (in
   town, then in a fight). Expect the controls to misbehave afterwards.
8. Tap **Save (reloads)** (the game writes the file when it reloads) and send
   this file:
   `World of Warcraft/_forever_/WTF/Account/<account>/SavedVariables/PocketProbe.lua`

What you will see while it runs, all expected:

- The chat box opening and closing by itself (risky trials only).
- The game's red error box, after the Errors trials' test error.
- "Interface action failed because of an AddOn" in chat, at most once a
  session.
- A "blocked from an action" pop-up when a trial is forbidden. Tap **Ignore**
  on the touchscreen; the controller cannot reach it.

For the values it reads, the file holds only the kind of answer ("readable",
"secret"), never the value itself, so it holds no names. The exceptions are
the Graphics settings (numbers like "2") and the names of the addons that had
errors, which are not personal.

### Reading the file on a computer

```bash
scripts/read-probe.sh path/to/PocketProbe.lua                   # the tables, then everything that was not allowed
scripts/read-probe.sh path/to/PocketProbe.lua --markdown        # the tables, ready to paste into docs/ARCHITECTURE.md
scripts/read-probe.sh path/to/PocketProbe.lua --details         # only what was not allowed, with function names and stack lines
scripts/read-probe.sh path/to/PocketProbe.lua --log             # the probe's own activity log
scripts/read-probe.sh path/to/PocketProbe.lua --diff newer.lua  # only what changed between two files (for example, after a game patch)
```

The output starts with a list of the situations the probe ran in, each given
a short name (S1, S2, ...) and spelled out, for example "Gamepad UI on, no
fight, open world, automatic". Then comes one table per area (chat box, bags,
controller and so on): a row per trial, a column per situation.

What a cell means:

| Cell | Meaning |
|---|---|
| `allowed` | It ran and the expected thing happened. |
| `no effect` | The game did not complain, but nothing happened. |
| `blocked` | The game refused it with the "Interface action failed because of an AddOn" chat line. |
| `forbidden` | The game refused it with the "blocked from an action" pop-up. |
| `error` | It failed with an error message. |
| `missing` | This game version does not have the function. |
| `readable`, `secret`, `nil` | For values the probe only reads: the addon can see it, the game hides it, or there was nothing to read. |
| `allowed / blocked` | Two passes in the same situation got different answers. Both are kept, so the difference shows. |
| `-` | Not tried in that situation. |

For the Errors and Graphics trials a cell can also hold what was read (such
as `function`, `3 (Blizzard 2, SomeAddon 1)` or `sparkle 0 · outline 2`), and
a guided trial's cell holds the answer (`sparkles seen`, `no icon`).

Under the tables come, when there are any: "Guided trials not answered yet"
(with the settings each will put back once answered), "Readings and answers"
(everything the Errors and Graphics trials read, and each guided answer), and
"Not allowed", which lists every refusal with the game function's name, the
game's message, whether it ran straight from a tap, and the game's own stack
lines. Like the debug log reader, this needs `luajit` and only reads the file,
with no access to files or the system from inside it.

## Device test plan

Rules 1 and 2 in PRD.md apply: **one step at a time, report back, then the next
step.** For every step, "report back" means: did it do what is described,
anything odd, and what the Errors page shows (round button → Errors).

Install first: delete any old `QuestDots` folder from AddOns, then extract
`dist/wow-forever-pocket-essentials.zip` into AddOns so `PocketEssentials`
and `QuestieDB` sit side by side.

### 0. Baseline — every feature off (do nothing in the settings yet)
- Log in. **Does any error box appear?**
- From 0.4.0 on, the setup guide opens by itself a moment after the loading
  screen, until you have pressed Finish or Skip in it once. For a baseline
  with every feature off, press **Close** (it comes back at the next login)
  or **Skip** (it stays away) without touching a switch. Its own steps are
  in 13e.
- **Is login noticeably slower than with no addons?** (QuestieDB carries
  18 MB of data; this is the main thing that could slow login.) If it feels
  slower, try once with the `QuestieDB` folder removed and compare.
- **Is there a round gold-ringed "PE" button at the left edge, mid-height?
  Is it big enough to tap comfortably?**
- Play for a few minutes. Does the frame rate feel the same as before?
- Report: errors yes/no, login slower yes/no, button visible and tappable
  yes/no, whether both addons are listed on the character-select AddOns
  screen.

### 1. Settings window — touch, then controller
- Tap the round button. A large window titled Pocket Essentials should open
  with one row per feature, all showing OFF.
- By touch: page the list with the big Up/Down buttons; change "Button size"
  to Large and back; move the round button with "Hub button position"; open
  the Errors page and come back; close with the big Close button.
- Also try: the addon list button on the minimap (if this client shows one)
  → "Pocket Essentials"; and typing `/pe` once.
- By controller, with the window open: d-pad up/down should move a bright
  blue outline; the bottom face button (A) presses the outlined button; the
  right face button (B) closes the window. After closing, check the d-pad
  and A/B do their normal jobs again.
- 0.0.6: in the **Quest icons** options (switch it on first), tap **Icon key**: a page opens with
  five rows (Kill, Loot, Use, Explore, Turn in), each with its icon in its
  real colour and what it means. The icons should look like the ones on the
  map. Tap Back to return.
- 0.0.6: tap **Reload UI**: the interface reloads and you land back in the
  game.
- Report: which of the three ways to open worked; is everything big enough;
  does text fit; does the d-pad move the outline at all (if not, touch-only
  is the fallback and we note it); do the buttons return to normal after
  closing.

### 2. Quest icons
- Switch on **Quest icons** only. Have a few quests in the log.
- **Round button:** it should now look smooth, not stepped.
- Open the world map: icons (red kill, yellow loot, blue use, purple
  explore, "?" turn in) sit where objectives are, and the blue haze is gone.
- By default ("Show icons for: Tracked quests") the map shows the quests in
  Blizzard's quest tracker plus the focused one. Track or untrack a quest:
  its icons appear or go.
- Under the row, try **Focused quest** (only the focused quest; with none
  focused, the tracker's quests) and **All quests** (every quest, like 0.0.1).
- Zoom the map in and out: icons stay on their spots and the same size.
- Minimap: **no blue haze** right after login, after a loading screen, and
  after walking into another zone. Icons move toward the centre as you
  approach. "Spots per objective" applies to the minimap too, so the minimap
  is often empty until you are near one of the shown spots (or the arrow is on
  and pointing at a spot); this is expected.
- Tap an icon on the map: a text box names the quest and objective. The tap
  does not change the focus.
- Finish an objective: its icons disappear within a second or two.
- 0.0.6, **Spots per objective:** track a quest with many spots. On the
  world map each objective should show at most five icons, spread over the
  area. Change the choice to 3, 10 and All: the map follows at once. A quest
  with only one or two spots should look as before.
- 0.0.6: play about ten minutes, opening and closing the map. Any stutter, or
  anything on the Errors page?
- Report: is the map readable now; does the minimap haze stay gone in all
  three cases; do icons follow the focus; any "action blocked" message;
  frame rate with the map open.

### 3. Quest arrow
- Leave Quest icons on and switch on **Quest arrow**.
- Focus a quest with an objective in your zone. An arrow (gold, with a
  clear point) with a distance and quest name appears at the top.
- **Direction check:** face north (use the minimap) with the objective to
  your north: the arrow should point up. Turn right: the arrow should swing
  left. If it swings the same way you turn, tell us; it is a one-line fix.
- Walk to the objective: the distance counts down and the arrow turns green
  with "Here".
- Turn your back to the objective: the arrow is replaced by "Turn around";
  turn back and the arrow returns.
- Focus a different quest: the arrow switches to it. Focus a quest in
  another zone: the text says "Outside this zone" and "Head to <zone>".
- Remove the focus: the text says "No quest focused" and "Focus one in your
  quest log".
- Enter a dungeon: the arrow hides while you are inside.
- Then switch Quest icons off and confirm the arrow still works alone.
- 0.0.6: focus a quest with many spots and walk toward the arrow. The spot
  it points at should have an icon on the minimap, even when it is not one of
  the five on the map.
- Report: direction right/mirrored; does it follow the focus; distance
  sensible; any stutter while moving.

### 4. Bags
- Switch on **Bag sorter**. If a "Reload now" bar appears, tap it.
- Open your bags: one combined window, with a tall gold **Sort** tab
  against its left edge, below the round bag picture (the sort icon at the
  top, "Sort" written down the tab). Tap it: items should tidy up. Check it at
  each Bag size.
- Set **Sort button** to Hide: the tab disappears, L3 still sorts. Set it back
  to Show.
- With the bag open, press L3 (click the left stick): it should sort. Close
  the bag: L3 should do its normal job again (auto-run).
- Set **Sort key** to Right stick click: with the bag open R3 sorts and L3 does
  not. Set it to Button only: neither stick sorts, the tab still does.
- Try Bag size Large and Extra large.
- **Use, move and equip a few items, in and out of combat.** Watch for any
  "interface action blocked" message; this is the main risk here.
- Switch the feature off: the bag should return to how it was (after a
  reload if asked).
- Report: combined yes/no; Sort button position and size; L3 works and is
  released; any blocked message; whether bag size changes anything.

### 5. Sell junk
- Carry a few grey items (and one grey you would not mind losing as a test).
  Switch on **Sell junk automatically** and open a vendor.
- Greys should sell one at a time over a second or two, then one chat line:
  "Sold N junk items for …". Check the buyback tab holds them (it only
  holds the last 12).
- With more than 12 greys: all of them sell in one visit, and the count in
  the chat line matches.
- Report: sold yes/no; anything non-grey sold (should be impossible; tell us
  immediately); any "blocked by an addon" popup; the chat line's numbers.
- 0.0.7: test this with only Sell junk on. If the game refuses, selling
  stops with "The game would not let Pocket Essentials sell items here",
  plus a line "The game blocked Pocket Essentials from using …". Screenshot
  both, and Settings > Errors.

### 6. Repair
- With damaged gear, switch on **Repair automatically** and open a vendor
  that repairs. Expect "Repairing for …" and yellow/red gear fixed.
- Report: repaired yes/no; cost line matches money spent; any popup.
- 0.0.7: test with only Repair on; screenshot any "The game blocked Pocket
  Essentials from using …" line and Settings > Errors.

### 7. Chat
- Switch on **Big chat buttons**. Tap the round button: a picker opens with
  Say, Yell, Guild/Party if they apply, each numbered channel, a Whispers
  section, a Settings button and Close.
- Tap Say: the picker closes and the chat box opens showing "Say:". Do a
  three-finger tap for the keyboard, type, send.
- Try a numbered channel, and Party when grouped.
- Have someone whisper you: a red badge appears on the round button; their
  name is in the picker marked NEW. Tap it, reply; the badge clears.
- After using the picker, type one `/target` or `/cast` command by hand and
  check it is not refused.
- Hold the round button for half a second: settings should open instead.
- Report: header shows the right target each time; keyboard appears with the
  three-finger tap; badge behaves; any refused command; d-pad in the picker.
- 0.0.7: test with only Big chat buttons on. After each tap, look for "The
  game blocked Pocket Essentials from using …" in chat and note what you had
  just tapped. Screenshot it and Settings > Errors.

### 8. Layout (removed)
The Layout helper was removed in 0.3.0 (never tested, and "Move things" does
the placing). Nothing to test; the number is kept so later steps keep theirs.

### 9. After all of the above
- Flip the default to on for each feature that passed.
- Decide which of QuestieDB's two identical data files the client loads and
  drop the other (`QUESTIEDB_TOC=Forever scripts/build.sh` or `Camelot`
  builds with one), halving the zip.

### 10. Version 0.1.0 (six changes from the 0.0.9 play test)

Before starting: Settings > Errors, switch the **debug log** on. When
finished: Settings > Errors > **Save log now** (it reloads), then send
`WTF/Account/<account>/SavedVariables/PocketEssentials.lua`.

1. Log in. Nothing should look different until you open the settings; no
   error pop-up.
2. Settings: every feature that is on and has options has a **Hide options**
   button beside its ON switch. Tap one: its options fold away, the switch
   still says ON, and the feature still works. Do the same with the d-pad and
   A. Also press A on an ON / OFF switch twice: the highlight should stay on
   that switch and the same feature should go off and back on. Reload: what you folded is still folded. **Show options** brings them
   back.
3. Settings, **Quest icons** block: **Icon key** is the last button there (it
   is gone from the bottom row). Tap it, then Back.
4. Settings, **Big chat buttons** block: **Chat text size** shows a number
   with **Smaller** and **Bigger**. Tap Bigger a few times and look at the
   chat window; tap Smaller. Leave it at a size you can read, reload, and
   check the size stayed (especially if you chose 30 or 34).
5. Chat: tap the round button, tap **Say**. "Press A to type" should appear
   in big letters in the middle of the screen with "Chat is set to Say" under
   it. Press A: the chat box opens and the big text goes. Do it again and
   wait: the text goes by itself after 12 seconds. Do it again and pull a
   creature: the text goes when the fight starts.
6. Chat, whisper: have someone whisper you (or whisper yourself from another
   character), tap their name in the picker: the big text should read "Chat
   is set to your whisper" (no name). Press A, type, send. Watch for any
   "blocked" message.
7. Bags: the feature is now called **Bag sorter**. With **Sort key** on Left
   stick click, open the bag and click the left stick: it sorts. Choose Right
   stick click: the right stick sorts and the left stick does its normal job.
   Choose Button only: neither stick sorts, the Sort tab still does. Close the
   bag each time and check both sticks do their normal jobs.
8. Quest arrow: focus a quest with several places to go (a "kill 10 of
   these" quest with more than one camp is ideal). Walk to where the arrow
   points until it says "Here", fight there, then walk away. The arrow should
   now lead you on to another spot, not back to the one you just left. Stand
   between two spots: it should not flip back and forth. Finish one part of
   the quest: the arrow should move to a place for a part that is not
   finished.
9. Report each step yes / no with notes, anything odd, and the saved file.

### 11. Version 0.2.0: Move things

Debug log on first; save and send the file afterwards, as in step 10.

1. Log in. Everything should sit exactly where it did in 0.1.0.
2. Settings, bottom row: tap **Move things**. The settings close and a small
   "Move things" panel opens in the bottom right corner, listing Quest arrow
   and Chat prompt (if those features are on), then Round button. The first
   one is selected, and a gold outline shows where it is.
3. Pick **Quest arrow**. Tap **Left** once: the arrow and its outline move a
   tiny step. Hold **Left**: after a moment it keeps moving, then faster. Let
   go: it stops at once.
4. The same with the controller: d-pad to **Up**, tap A (one small step),
   then hold A (keeps moving), let go (stops). If it does not stop when you
   let go, tell me; it should stop by itself after 8 seconds at most.
5. Hold a direction until the piece reaches the screen edge: it should stop
   there, not leave the screen.
6. Move a piece down toward the panel: the panel should hop to the bottom
   left corner.
7. Pick **Chat prompt** and move it; then close with B, tap a chat button and
   check "Press A to type" appears where you put it.
8. Pick **Round button**, move it, tap **Reset**: it returns to its preset
   spot.
9. Close with B. Reload: the pieces are still where you put them.
10. Settings: choose a different **Arrow position**: the arrow goes exactly
    to that preset (your nudge is cleared).
11. Start a fight with the panel open: it closes. During a fight, **Move
    things** says it cannot open.
12. Report each step yes / no with notes, anything odd, and the saved file.

### 12. Version 0.3.1: Layout helper gone; the arrow as before

The arrow's "Quest in another zone" choice of 0.3.0 was taken out in 0.3.1,
so there is nothing new to try on the arrow.

1. Log in. The settings no longer have a **Layout helper** row, and nothing
   complains in chat about it.
2. Settings > Quest arrow: there is no **Quest in another zone** choice.
3. Focus a quest whose places are all in another zone: the arrow's place
   reads "Outside this zone / Head to <zone>", as before.
4. Report each step yes / no with notes, and send the saved file.

### 13. Version 0.4.0

Five parts, in the order they are best tried. Each can be done on its own
day; report after each one.

- **13e. Setup guide** comes first in practice, because it opens by itself
  at the first login on a fresh install. Its steps were rewritten for 0.5.0
  (the guide now carries each feature's choices).
- **13a. Chat text size**: the stepper in the settings.
- **13b. Menu background**: the dark panel behind the quest log's menu.
- **13c. D-pad to Sort**: reaching the Sort tab with the d-pad.
- **13d. Bag icons**: the bag pictures in one row at the top.

In 13c and 13d the answer that matters most is that using, moving and
selling items still works.

#### 13a. Chat text size

Install the 0.4.0 zip, turn the debug log on (settings, Errors page), and
note the chat size before starting.

1. Open the settings (hold the round "PE" button). With **Big chat buttons**
   OFF, find its block. Under it you should see **Chat text size** and, on
   the next line, **Smaller**, a number, **Bigger**. The number is the chat's
   size right now (18 unless you changed it).
2. Tap **Bigger** once. The chat text on screen should grow at once and the
   number should go up one step (18 becomes 20).
3. Tap **Smaller** twice. The number should go 18, then 16, and the chat
   should shrink each time.
4. Move to **Bigger** with the d-pad and press A. Same result as a tap. The
   highlight should stay on the button after the press.
5. Tap **Bigger** until it stops. The numbers should run 20, 24, 27, 30, 34
   and then stay at 34. Tap **Smaller** until it stops: it should end at 12.
6. Set it to 20 and close the settings. Open the game's own menu on the chat
   tab, go to Font Size: the ticked entry should be 20.
7. In that game menu pick 14. Open our settings again: the number should
   say 14.
8. If you have a second chat tab (Combat Log counts): look at it after a
   press; it should be the same size as the main chat.
9. Set it to 16, then use **Reload UI**. The chat should still be 16 and the
   number should say 16. Log out fully and back in: still 16. Do the same
   once with 30 (this one may not survive; tell me either way).
10. Start a fight, open the settings and tap **Bigger**. The line should say
    "Chat text size: <the next size> (after the fight)" and the chat should
    not change yet (the number between the buttons stays as it was). When
    the fight ends the chat should change by itself and the note should go.
11. Tap **Hide options** in the "Big chat buttons" block: the stepper should
    fold away; **Show options** brings it back. Switch **Big chat buttons**
    ON: the row should still be there and work, and fold the same way.
12. Check the other blocks still look right with the d-pad: each ON / OFF
    switch can be reached, and features that are off (other than Big chat
    buttons) have no "Hide options" button.
13. Set the size you actually want. Say whether the three pieces fit on one
    line and are easy to hit at the Small, Medium and Large button sizes.
    Send the saved `PocketEssentials.lua` file, and say whether any
    "Interface action failed" or "action blocked" message appeared.

#### 13b. Menu background

Install the 0.4.0 zip, log in, open the Pocket Essentials settings and turn
the debug log on (Errors page).

1. Open the quest log and open the menu on a quest (the Y button). Confirm
   it still looks broken (text with no background). This shows the switch
   really starts off.
2. In the settings, switch on **Menu background**. No reload should be
   asked for.
3. Open the quest log and open the menu on a quest again. Is there now a
   dark panel behind Track / Focus / Share / Abandon? Is all the text on the
   panel, with nothing sticking out? Is the "A Select / B Close" bar still
   there? Take a screenshot here.
4. Move up and down the menu. Does the highlight still follow?
5. Choose **Track Quest** (or Untrack). Did it work, and did the panel
   vanish together with the menu?
6. Open the menu again and choose **Focus**. Does the quest arrow pick up
   the quest? Panel gone?
7. Open the menu again and choose **Share in Chat**. Does the quest link
   land in the chat box as before?
8. Open the menu again and press **B**. Menu and panel both gone?
9. Open the menu and, while it is open, close the whole map. Is any dark box
   left on the screen? (If one is, say whether it goes away the next time
   you open any menu.)
10. On a quest you do not need: open the menu, choose **Abandon Quest**, and
    confirm. Did the usual "abandon?" question appear and work?
11. Open the menu on a zone heading in the quest log (the "track all" menu).
    Does it have the panel too?
12. Open a menu that has a side menu (an entry with an arrow) and open the
    side menu. Where the two menus meet, is the first menu's text still
    readable, or does the side menu's dark panel cover part of it?
13. If you can, with touch or a mouse: right click your own portrait or a
    chat tab. Does that menu have a panel? Does any menu look worse than
    before (a dark box around a menu that already had a background)?
14. Start a fight with something easy, and during the fight open the quest
    log and the quest menu. Panel there? Does the chat say "Interface action
    failed because of an AddOn" at any point in this whole test?
15. Switch **Menu background** off. Open the quest menu once more. It should
    look as it did in step 1.
16. Log out, and send the saved `PocketEssentials.lua` file plus the
    screenshot from step 3.

Report for each step: yes / no / what you saw. The saved file's `menuBg`
lines say which way the addon heard about the menu and whether the game's
own background picture is missing on this client.

#### 13c. D-pad to Sort

What this is: a new choice in "Bag sorter" that lets you reach the Sort tab
with the d-pad (Left from the bag's first column) and press it with A.

Two answers matter more than all the others:

- **Using items must still work** (steps 2, 6, 7, 10, 12, 13 and 16). This is the
  first time the addon asks the game to store something on the bag's own item
  buttons. If any item will not use, equip, sell, pick up or split, or the
  chat says "Interface action failed", stop there.
- **A must really press Sort** (step 4). Reaching the tab is the easy half.
  The game also holds A while the bag is open, and only the device can show
  whether our hold or the game's wins.

Before starting: install the 0.4.0 zip, turn the debug log on (settings,
Errors page), Gamepad UI on, out of a fight, in a safe place. Have in your
bags: something you can use (food or a potion), something you can equip,
and a stack of 2 or more.

A known limit, so it does not surprise you: in a fight the game does not let
the addon change where Left goes. Each time the bag is opened, or one of your
bags is folded, the game may deal its item buttons out to other slots. Out of
a fight the addon follows at once. In a fight it cannot, so until the fight
ends Left may jump to Sort from a slot that is not in the first column, or
not jump from the first column at all. It is put right the moment the fight
ends. Using items must work the whole time (step 16).

1. Settings, "Bag sorter": set **D-pad to Sort** to **On**. Make sure
   **Sort button** is on Show. The text under the feature should now say
   "D-pad: press Left from the first column to reach Sort, then A."
2. **(Matters most.)** Open the bag. Use an item with the usual button. It
   must work as always.
3. Move the cursor to any slot in the leftmost column. Press **Left**. The
   cursor should jump onto the Sort tab. Say where the cursor's pointer is
   drawn (beside the tab, on it, off the screen).
4. **(Matters most.)** Press **A**. The bags should sort (you hear the sort
   sound and the tab flashes). Wait a second and press **A** again: they
   should sort again.
5. Press **Right**. The cursor should go back into the bag's first column.
6. **(Matters most.)** Press **A** on an item: it should pick the item up as
   usual. Press B to put it down.
7. **(Matters most.)** Use an item, equip an item, and split a stack (the
   "more actions" button). All must work, with no red error and no
   "Interface action failed" line in chat.
8. Go to the tab again (Left), then press **B**. The bag should close. Open
   it again: the cursor should be in the bag as usual, and A should behave
   normally on items.
9. Go to the tab, then press **Up**, **Down** and **Left** in turn (going
   back to the tab between them). Say where the cursor goes each time. It
   must never get stuck.
10. **(Matters most.)** Start a fight with the bag closed. Open the bag in
    the fight. Use a potion or food from it: it must work. Left from the
    first column may do the old thing (wrap round to the last column); that
    is expected.
11. After the fight, with the bag still open, press Left from the first
    column: it should reach the tab again and A should sort.
12. **(Matters most.)** Open the bag out of a fight, move onto the tab, then
    get into a fight without closing it. Press A on the tab (nothing should
    happen), click the stick (should sort), then move Right and use an item
    (must work).
13. **(Matters most.)** Go to a vendor with the bag open and sell one item
    from the bag with the usual button. It must work.
14. Tap the Sort tab with a finger and click the stick once more: both
    should still sort, as before this version.
15. Settings: set **D-pad to Sort** to **Off**. Open the bag: Left from the
    first column wraps round to the last column, as it did before.
16. **(Matters most.)** Set **D-pad to Sort** back to **On**. Open the bag
    out of a fight, start a fight, then close the bag and open it again
    during the fight. Move around the bag with the d-pad and press Left in a
    few places. Left may land on Sort from an odd slot, or not at all from
    the first column, until the fight ends: that is the known limit above,
    say what you saw. Use a potion or food from the bag during the fight: it
    **must** work. After the fight, Left from the first column (and only from
    there) should reach the tab again.
17. Send the saved `PocketEssentials.lua` file and say for each step:
    worked / did not / what you saw. If at any point the game says
    "Interface action failed" or an item will not use, stop, note the step,
    use Reload UI, and send the file.

What the answers decide:

- Step 3 fails: the route cannot be used, and the choice is dropped.
- Step 3 works but step 4 fails: the game's hold on A beats ours. The log
  line "A taken for Sort (A is now: ...)" says who holds it. The choice then
  stays Off and the idea is dropped (the stick click and the game's own
  "Clean Up Bags" entry in the bag menu already sort).
- Any failure in steps 2, 6, 7, 10, 12, 13 or 16 (an item that will not
  use; Left landing oddly in step 16 is not a failure): switch the choice Off. It
  stays off, and the log names the cause.

#### 13d. Bag icons

What this is: a new choice in "Bag sorter". In the controller style the game
draws a picture of each of your equipped bags inside the bag window, in
among the item slots, so they look like loose bags lying in your inventory.
With "Bag icons" on "One row at the top", those pictures sit side by side in
the top row and the slots follow below with nothing in between.

One answer matters more than all the others:

- **Using, dragging and selling items must still work, in and out of a
  fight** (steps 4, 5, 9 and 10). This is the first time the addon moves the
  bag's own item buttons. Reading the game's code says that moving a button
  cannot block what the button does, but only the device can show it. If any
  item will not use, equip, move, split or sell, or the chat says "Interface
  action failed", stop there, use Reload UI, and send the file.

Before starting: install the 0.4.0 zip, turn the debug log on (settings,
Errors page), Gamepad UI on, out of a fight, in a safe place. Have in your
bags: something you can use (food or a potion), something you can equip, a
stack of 2 or more, and something a vendor will buy.

1. Settings, "Bag sorter" on. Leave **Bag icons** on **In the grid**. Open
   the bag: it should look exactly as before (the bag pictures in a diagonal
   among the slots).
2. Set **Bag icons** to **One row at the top**. The text under the feature
   should now say "Bag icons are in one row at the top of the bag." Open the
   bag. The bag pictures (backpack first, the key last) should be side by
   side in the top row, starting at the left. Below them there should be
   only item slots. Take a screenshot.
3. Move with the d-pad: along the row of bag pictures, down into the slots,
   across a row, and back up. Say if the cursor ever jumps somewhere odd,
   and from where to where. (Up from the first slot under the backpack
   picture may go to the round picture in the window's corner; that is the
   game's own rule.)
4. **(Matters most.)** Use a food or potion from the bag. Equip an item.
   Nothing may show "Interface action failed because of an AddOn".
5. **(Matters most.)** Pick an item up and put it in another slot (drag it
   with a finger, and also with A on the controller). Split a stack. Both
   must work as always.
6. Put the cursor on a bag picture. Press **X**: that bag's slots should
   fold away and the rest should close up tidily under the row. Press **X**
   again: they come back. Press **Y**: the bag's menu should open. Press
   **LB** and **RB**: the cursor should jump from one bag picture to the
   next.
7. Do the same X on the key picture (last in the row): the key slots should
   appear among the slots and go away again.
8. Click the stick (or tap the Sort tab). Items should sort as before.
9. **(Matters most.)** At a vendor, sell one item from the bag with the
   usual button, and drag another onto the vendor window.
10. **(Matters most.)** Start a fight with the bag closed. Open the bag in
    the fight: the bag pictures should be in the top row at once. Use a
    potion or food from it, and move one item to another slot. Both must
    work.
11. Try each **Bag size** (Normal, Large, Extra large) with the bag open.
    The row should stay tidy and the Sort tab should stay in its place.
12. If you use **D-pad to Sort** (13c): set it On. Left from any slot in the
    leftmost column should go to the Sort tab. Left from the backpack
    picture (top left) is left to the game and should not go to the tab.
13. Equip or take off a bag, if you can spare one. Open the bag: the row and
    the slots should still be tidy.
14. Set **Bag icons** back to **In the grid** with the bag open: it should
    return to the old look at once. Then switch "Bag sorter" off and on
    again and open the bag: still the old look.
15. Send the saved `PocketEssentials.lua` file and the screenshot, and say
    for each step: worked / did not / what you saw.
    (`scripts/read-log.sh <file> --grep "bag icons"` shows this choice's
    lines.)

What the answers decide:

- Any failure in steps 4, 5, 9 or 10: set the choice back to "In the grid".
  It stays off and is withdrawn.
- Step 3 feels wrong (the cursor slips a row beside a bag picture that has
  an empty space under it): the row of pictures can be put at the bottom,
  next to the money, where the d-pad lines up exactly. Say so.
- Step 2 shows nothing changed: the log line "bag icons: left alone, ..."
  says why.

#### 13e. Setup guide

Rewritten for 0.5.0. The guide now has nine screens, one per feature that has
choices, and each feature's choices are in the guide under its switch: the
same ones as in the settings. It has no **Up** / **Down** buttons on a screen
that fits; when a screen gets too long (a feature with many choices switched
on, or the Large button size) they appear on the right.

It opens by itself once after a fresh install. If you already pressed Finish
or Skip in 0.4.x it will not: open it from the settings (hold the round
button, scroll to the bottom, **Setup guide**) and start at step 2.

Install the 0.5.0 zip and log in. Keep the debug log on (settings, Errors
page).

1. Fresh install only: wait a couple of seconds after the loading screen. A
   window "Pocket Essentials - Setup guide (1 of 9)" should open by itself.
2. Read the Welcome screen. Without touching the screen, press the d-pad
   down: a blue outline should appear on a button. Move to **Start** and
   press A.
3. Screen 2, "Quest icons". With the switch OFF there should be nothing under
   it but the text. Tap the switch: it should read ON and, at once, the
   choices should appear under it: "Show icons for", "Map icons", "Minimap
   icons", "Hide blue haze", "Icon size", "Merge nearby icons", "Spots per
   objective" and an **Icon key** button. The screen is now too long, so
   **Up** and **Down** should appear on the right.
4. Still on that screen, use only the d-pad: move down through the choices.
   The list should scroll by itself so the blue outline is always in view.
   Press A on **Focused quest**: it should turn gold, and the outline should
   stay on it.
5. Tap **Down** and **Up** with your finger: the list should page.
6. Press **Next**. Screen 3, "Quest arrow": switch it on. "Arrow position"
   (five buttons) and "Arrow size" should appear. Pick **Left**; if you have
   a focused quest, the arrow on screen should move at once.
7. Screen 4, "Menu background": one switch, nothing under it.
8. Screen 5, "Bags": switch **Bag sorter** on. Five rows should appear: "Bag
   size", "Sort key", "Sort button", "D-pad to Sort", "Bag icons". Pick
   **Extra large** and **One row at the top**, then open your bag behind the
   guide (or after it): it should already be that way.
9. Screen 6, "Vendors": two switches (Sell junk, Repair), nothing under
   them.
10. Screen 7, "Chat": with **Big chat buttons** OFF you should still see
    **Chat text size** with **Smaller**, a number and **Bigger**. Tap
    **Bigger**: the chat text should grow and the number go up one step.
11. Screen 8, "The round button and moving things": text only, no switches
    and no choices (button size and the round button's position are still
    only in the settings).
12. Screen 9, "All set": the "Switched on:" and "Still off:" lines should
    match what you did. Press **Finish** (green). The window closes.
13. **Same value in the settings.** Open the settings (hold the round
    button). Under **Quest icons**, "Show icons for" should have **Focused
    quest** in gold; under **Bag sorter**, **Extra large** and **One row at
    the top**; the chat text size number should be the one you left.
14. **Same value in the guide.** In the settings, change two of them: under
    **Bag sorter** pick **Normal**, and under **Quest arrow** pick **Top**.
    Then tap **Setup guide** at the bottom of the settings and walk to the
    Bags and Quest arrow screens: **Normal** and **Top** should be the gold
    ones there.
15. In the settings, tap **Hide options** on Bag sorter, then open the guide
    again: the Bags screen should still show all five rows (the guide has no
    hiding).
16. On the Bags screen switch **Bag sorter** off: the five rows should go at
    once and, if **Up** / **Down** were showing, they should go too. Switch
    it on again with the d-pad and A: the rows come back and the blue outline
    stays on the switch.
17. On the Quest icons screen tap **Icon key**. The guide should close and
    the settings' Icon key page open. Tap **Back** there, then **Setup
    guide** to return.
18. Press **Back** and **Next** a few times with A: the outline should stay
    on the same bottom button. Back should not be on the first screen; Skip
    should not be on the last.
19. Open the guide, go to screen 5, and pull a monster. The guide should
    disappear at once and come back at screen 5 when the fight ends, with the
    choices as you left them.
20. Try each button size once (Settings > Button size) and walk the guide
    with every feature on. Tell us on which screens, at which size, **Up** / **Down**
    show, and whether any text or button is cut off or overlapping.
21. Optional, on a second account or after deleting
    `WTF/Account/<account>/SavedVariables/PocketEssentials.lua` with the
    game closed: log in. Everything should be off, the guide should open by
    itself, and pressing B should close it with a chat line saying it will
    show again next time. Press Skip: next login it stays away.
22. Tell us: were the choices where you expected them, was any screen too
    long to be comfortable, did the d-pad ever stop moving the blue outline,
    and did the guide ever close by itself. Send the saved
    `PocketEssentials.lua` file. (`scripts/read-log.sh <file> --grep "setup"`
    shows the guide's lines.)

Without QuestieDB the two quest screens show a dimmed OFF switch with the
amber reason and no choices, as the settings do.

What the answers decide:

- The d-pad does nothing in the guide right after login, but works when the
  guide is opened from the settings: the game took the controller keys back
  after the guide opened. The wait before it opens gets longer, or the guide
  takes the keys a second time.
- A screen is too long to read comfortably: its text gets shorter.
- A value differs between the guide and the settings: that is a bug in the
  shared drawing code; say which choice and in which order you pressed.
- The guide closed by itself outside a fight: say what you were doing (a
  loading screen, dying and losing control of the character all close every
  window of this kind; that is the game's rule, and the guide comes back at
  the next login).

### 14. Version 0.6.0: tidier settings

Fewer buttons in the settings and the setup guide. Install the 0.6.0 zip and
log in; your choices from before should all still be as you left them. Keep
the debug log on (settings, Errors page).

1. Open the settings (hold the round button) with **Quest icons** and **Bag
   sorter** on. Each row's name should now be on the same line as its
   buttons, to their left (for example "Icon size  Small  Medium  Large").
   A row with many buttons ("Arrow position", "How to sort", "Round button
   position") may keep its name above, as before. Nothing should overlap or
   be cut off.
2. Under **Quest icons**: "Map icons" and "Minimap icons" are gone; there is
   one row **Icons on** with **Map and minimap**, **Map only** and
   **Minimap only**. The one you had before should be gold.
3. Tap **Map only**: the quest icons should leave the minimap and stay on the
   world map. Tap **Minimap only**: the other way round. Tap **Map and
   minimap** to finish.
4. **Hide blue haze** is now one button that reads **Hide blue haze: On**
   (green). Tap it: it should read **Off** (grey), and the settings should
   ask for a reload, as before. Tap it again: **On**, and the reload request
   goes away.
5. Under **Bag sorter**: "Sort key" and "Sort button" are gone; there is one
   row **How to sort**. The one matching your old setting should be gold
   (out of the box: **Button + left stick**).
6. Open your bag. Tap **Right stick only**: the Sort tab beside the bag
   should go, and clicking the right stick should sort. Tap **Button only**:
   the tab comes back and no stick sorts. Tap **Button + left stick** to
   finish.
7. **D-pad to Sort** and **Bag icons** are now one button each, side by
   side: **D-pad to Sort: Off** and **Bag icons: In the grid**. Tap each:
   they should change to **On** (green) and **One row at the top** (green),
   and the bag should change as it did before. Tap again to go back.
8. Reload (the **Reload UI** button). Everything you changed should still
   be the way you left it.
9. Use only the d-pad in the settings: the blue outline should reach every
   button, including the toggles, in reading order (left to right, then
   down).
10. Try each button size (**Button size**) and tell us whether any row
    looks crowded or wrong at Small, Medium or Large.
11. Open the **Setup guide** (bottom of the settings) and walk to the Quest
    icons and Bags screens: they should look the same as the settings.
12. Tell us: is it easier to read than 0.5.0, and is any toggle unclear
    about what it does? Send the saved `PocketEssentials.lua` file.

### 15. Version 0.7.0: number control, finer Quest icons, smaller arrow

Install the 0.7.0 zip (only the `PocketEssentials` folder; the probe is not
needed) and log in. Your choices from before should all still be as you left
them. Keep the debug log on (settings, Errors page).

1. Open the settings with **Quest icons**, **Quest arrow** and **Big chat
   buttons** on. **Merge nearby icons**, **Spots per objective** and **Chat
   text size** each show one gold-edged box: **-**, a gold number with a
   small word under it, **+**. Say whether it looks right and nothing is cut
   off.
2. **Spots per objective** shows the number you had (out of the box 5).
   Tap **+** until it reads **20**, then once more: it should read **All**,
   and **+** goes dim. Tap **-**: back to 20. Open the map after a few taps:
   the number of icons per objective should follow.
3. Tap **-** down to **1**: **-** goes dim, and another tap does nothing.
4. **Merge nearby icons** shows **5** if you had "More" (or 2 for "Normal").
   Step it to **Off** and to **10** and look at a crowded spot on the map
   (a camp of mobs): more merging means fewer icons.
5. **Chat text size**: **-** and **+** change the chat text as Smaller and
   Bigger did. At the biggest size **+** is dim.
6. **Icon size** has **Extra small** first. Pick it: the icons on the map and
   minimap get a little smaller than Small.
7. **Arrow size** has **Small** first. Pick it: the arrow gets smaller than
   Normal.
8. **Hide blue haze** is now near the bottom of Quest icons, just above
   **Icon key**.
9. Use only the d-pad: the blue outline stops on **-** and **+** of each box
   (never on the number), and A presses them.
10. Try **Button size** Small and Large: the boxes should stay whole on one
    line.
11. Open the **Setup guide** and walk to the Quest icons and Chat screens:
    the same boxes, and a change in one window shows in the other.
12. Reload. Everything you changed should still be the way you left it.
    Send the saved `PocketEssentials.lua` file.

### 16. Version 0.8.0: Move on screen, Bags in two, button colours, touch question

Older sections describe older builds: where they mention "How to sort",
"D-pad to Sort", "Move things" or the position buttons, follow the steps
below instead.

Install the 0.8.0 zip (only the `PocketEssentials` folder) and log in. Keep
the debug log on (settings, Errors page).

1. Open the settings. If you used **Bag sorter** before, **Bag window** is on
   now, with the size and icons you had.
2. In **Quest arrow**, tap **Move the arrow**. **Move on screen** opens with
   the arrow picked. Nudge it, close, reload: it stays where you put it.
   Tap **Reset**: the arrow goes to the top-centre starting spot.
3. In the main settings, tap **Move the round button**. Same checks: it
   opens with the round button picked, a moved button stays after a reload,
   and **Reset** sends it to the left starting spot.
4. Say whether the name **Move on screen** reads right in the window title,
   the settings' bottom row and the setup guide.
5. Open your bag. With **Bag window** on, try **Bag size** and **Bag icons**.
   Turn **Bag sorter** off: the bag keeps its size and icons. Turn
   **Bag window** off and **Bag sorter** on: the Sort button still works.
6. In **Bag sorter**, **Sort button** On shows the big Sort button, Off
   hides it. **Sort stick** Left or Right sorts with that stick's click
   while the bag is open.
7. With the Sort button showing, press Left on the d-pad from the bag's
   first column: the highlight reaches the Sort button, and A sorts. With
   the Sort button Off, it should not.
8. **Button colour** (in the main settings): tap Gold, Horde and Alliance.
   The round button changes colour at once each time.
9. **Merge icons closer than N%** (for example 2%) shows "of map" under the number. Step it
   and look at a crowded spot on the map: a bigger number means fewer
   icons.
10. Open the **Setup guide** (settings bottom row). The d-pad highlight
    starts on **Start**, not Close or Skip.
11. The first page asks whether you use the touch screen. Answer **No**: the
    scroll bar and the Sort button go away. Open the bag (no Sort button)
    and a long settings page (no scroll bar). Go back in the same guide and
    answer **Yes**: the scroll bar and the Sort button come back.
12. Open a long settings page. The slim scroll bar shows an arrow at each
    end and a marker. Tap the arrows to move, tap the track to page, and say
    whether the marker follows where you are. **Touch screen: Yes / No** in
    the settings does the same as the guide's question.
13. With **Touch screen: No**, open the **Errors** page from the settings
    (or any long page) and press d-pad Down repeatedly: the page should
    scroll all the way to the bottom, and Up should bring it back.
14. Reload. Everything you changed should still be as you left it. Send the
    saved `PocketEssentials.lua` file.

### 17. Version 0.8.1: clearer labels, the round button on the map, and a log for Menu background

Install the 0.8.1 zip (only the `PocketEssentials` folder) and log in.

1. Open the settings with **Quest icons** on. **Hide Blue Quest Haze: On**
   and **Quest Icon Key** are on one line, side by side. Tap the toggle: it
   flips to Off and back. Tap **Quest Icon Key**: the key page opens and its
   title says "Quest Icon Key". **Back** returns.
2. With the d-pad, move to the toggle, then press Right: the highlight
   goes to **Quest Icon Key** next. Down goes to the next line, and Left
   comes back from the key to the toggle.
3. Open the **Setup guide** and go to the Quest icons screen: the same two
   buttons are side by side there too.
4. Find the chat switch: it reads **Chat from round button**, with the line
   "Tap the round button to choose who to talk to: Say, Party, Guild or
   someone who whispered you." under it. Say whether the name reads clearly
   now. With the switch off, **Chat text size** is still there.
5. Open the map (normal size, with the quest log beside it). The round PE
   button sits on the map's book icon in the top-left corner, not over the
   map. Tap it: the chat window opens (with Chat from round button on). Hold
   it: the settings open. If you have an unanswered whisper, the red number
   shows on top of the button.
6. If the map can be made full screen, do it: the button goes back to its
   usual spot. Back to normal size: it is on the book again.
7. Close the map: the button is back at its usual spot (or where you moved
   it with Move on screen). Open the map once in a fight too: same.
8. Menu background: settings, **Errors** page, turn **Debug log** on. Turn
   **Menu background** on. Open the quest log, tap a quest so its menu
   (Track, Focus, Share, Abandon) opens, look at it, then close it. Back on
   the **Errors** page, tap **Save log now**. Send the saved
   `PocketEssentials.lua` file (in `WTF/Account/<your account>/SavedVariables/`).
9. Look through the settings pages: buttons in a row (Small, Medium,
   Large; Gold, Horde, Alliance) are all the same width and line up.
   Longer ones like **Move the round button** are two widths. Tap
   **Touch screen: Yes**: it reads No and stays the same size. Hide Blue
   Quest Haze and Quest Icon Key are still on one line.

### 18. Version 0.9.0: the new look from the mockups

Install the 0.9.0 zip (delete the old `PocketEssentials` folder first, keep
`QuestieDB`) and log in. Compare each window with the "Proposed" mockups
(`docs/ui-review/mockup-0.8.1.html`, 720p, your button size). Report anything
that looks different from the mockup, cut-off text, or controls that do not
respond, plus the Errors tab.

1. **Settings tabs.** Tap the round button (hold it if Chat picker is on).
   Tabs down the left; tap each. Each page has the same row shape: name
   left, control right. Green dots show which tabs have a helper on.
2. **Controls.** Flip a switch On and Off. Tap each part of a row of joined
   choices: the chosen one turns gold. Use − and + on "Spots per objective".
   With the d-pad: Up/Down move in a column, Right goes from a tab into its
   page, Left from the first control goes back to the tab, A presses.
   With General → I play with: Controller, do the same; Up/Down on the tabs
   must move between tabs, not scroll the page.
3. **Quest arrow.** Quest arrow tab → "Size of the arrow and its text":
   step it down (for example to 70%) and up. The arrow and its text change
   together; Button size no longer changes them. Check the messages: walk
   past an objective (Here is green), turn away (Turn around, no arrow),
   unfocus your quest in the open world (No quest focused) and then in a city
   or inn (it disappears; set the row to Show and it comes back).
4. **Move on screen** (General → Move things on screen). All three pieces are
   listed; turn Chat picker off and "Press A to type (off)" is dimmed. Pick
   the quest arrow: a Size row sits under the arrows.
5. **Chat picker window.** With Chat picker on, tap PE: a small window with
   "Talk in" and "Whispers" in 3 columns, no keyboard hint. Chat tab → "Size
   of the chat picker window": change it and reopen the window.
6. **Bags.** Bigger bag on: bag pictures in one row at the top. Bag sorting
   on: the rounded Sort tab beside the bag, with the picture and "Sort". Tap
   it, and click your chosen stick in: both sort. Set the Sort button to Hide.
7. **Setup guide** (General → Setup guide). Walk all screens with Next: dots
   at the bottom, nothing overlapping Skip. On "Your screen", tap "Move things
   now": the guide hides, Move on screen opens; close it and the guide is back
   on the same screen. Finish.
8. **Button size Large** (General): reopen settings and the guide. Look for
   any cut-off words.
9. **Menu background** (still open from 0.8.1): Errors tab → Debug log On,
   Menu background on, open a quest's menu in the quest log, close it, then
   Errors tab → Save the log, and send the saved `PocketEssentials.lua`.

### 19. Version 0.9.1: setup guide tweaks and Loot sparkles

Install the 0.9.1 zip (delete the old `PocketEssentials` folder first, keep
`QuestieDB`) and fully restart the game.

1. **Setup guide** (General → Setup guide → Open). On Welcome, the button
   pictures show the bottom and right face buttons lit, no letters.
2. With the d-pad: the first press lands on the screen's first control (the
   "How do you play?" choice, or a switch), not Close. Down from the last
   control goes to Next; Left goes to Skip, then Back. Press A on Next a few
   times: each new screen starts on its first control.
3. "Vendors and game fixes" has four cards, one sentence each. "Round button
   and chat" says once what a tap does.
4. **Loot sparkles.** Set the game's graphics to the lowest. Settings → Game
   fixes → Loot sparkles On. Kill a mob and look at the corpse, items on the
   ground, quest givers and objects: they sparkle. Change the graphics preset
   and back: the sparkles stay. Does the frame rate feel the same?
5. Turn Loot sparkles Off: its card says to fully restart the game. Restart:
   the sparkles are gone.
6. Errors tab: anything listed?
