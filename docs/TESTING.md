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
   **Calls into Blizzard's Lua** (`tests/taint/`, part of `test.sh`). A
   function the game's makers wrote in Lua can leave the addon's mark on the
   game's own data when the addon calls it; the game then refuses its own
   controller actions (0.16.0 to 0.16.2). Every such call is listed in
   `tests/taint/calls.txt` with what it writes. The check fails on a call that
   is not listed, and on one listed as `writes`.
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

The line under the switch ("N of 6,000 lines") shows how much is held. When
it is full the middle is dropped: the first 60 lines of each session, every
section mark, every snapshot and the newest 3,000 lines stay, and a line says
how many were dropped. Switching the log off keeps the lines; **Empty the
log** removes them (and starts the section count again).

Two more buttons there, for a long test: **Mark a test section** writes
`==== section N ====` and says "Section N marked" in chat; **Save a
snapshot** writes where every piece of the Controller layout is and which
pieces overlap (out of a fight; in a fight it waits). Both are also at the
bottom of the Controller tab. The log never holds player names or chat
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

### On the device (probe 0.3.0 and later)

**Nothing runs by itself any more.** Logging in does nothing but put a small
**Probe** button at the top centre of the screen, with a line of text under it
saying what the probe is doing. Tap **Probe** (or type `/probe`) to open the
probe's window. It is the same size as Pocket Essentials' settings window and
looks the same.

**The window:**

- **Left: one tab per area.** Errors, Graphics, Our own windows, Blizzard
  windows, Chat box, Bags and vendor, Controller and layout, Values (and
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
  - grey-blue **Can't tell**: nothing refused it, but the probe could not
    see whether it worked (for example the error box was already off).
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
  to the box, how many errors other addons and the game had this session and
  from where, whether turning the box off works (it is turned back on
  straight away), and a risky trial with a handler of our own. Two of them
  raise one harmless test error of the probe's own, so the game's error box
  pops up for a moment; the probe closes it again. Run all safe does those
  two last. It never saves another addon's error text, only where it came
  from.
- **Graphics** (why the loot sparkles do not show on the handheld): reads the
  outline, sparkle and interact-icon settings, writes the sparkle one (and
  puts it back), lists the setting names the game knows, and two **guided**
  trials. A guided trial has **Start** instead of Run. It changes a setting,
  tells you what to do (in the Details line and at the top of the window),
  and then shows two answer buttons. Your answer is saved and the old
  settings are put back.
  - While a guided trial waits, its row has **Cancel** in place of Start, and
    the line at the top says so (for example "Outlines off is waiting: answer
    or Cancel"). **Cancel**, **Stop** and `/probe stop` put the old settings
    back without an answer. If the game refuses to put a setting back, the
    row says "Not put back": tap **Cancel** to try again.
  - **Outlines off, then restart:** after Start, close the game app
    completely and open it again. A reload is not enough, and neither is
    logging out to character select. Then kill something, open the window
    again, go to Graphics and tap **Sparkles seen** or **No sparkles**.
  - **Interact icons on loot:** after Start, look at a lootable corpse, then
    tap **Icon seen** or **No icon**. If the interact or object icon setting
    was off, the probe turns it on for this trial too. Logging out or
    reloading before you answer puts the settings back (start again
    afterwards).

**Steps (one run of 0.3.0):**

Leave Risky off for steps 1 to 5.

1. With Pocket Essentials off and PocketProbe loaded, log in in a town. Check
   that nothing runs by itself. Tap **Probe**.
2. Tap **Run all safe** and wait for "pass done" at the top of the window.
3. Open **Errors**, tap a few rows to read their Details. Open **Graphics**
   and do **Interact icons on loot**, then **Outlines off, then restart**
   (this one needs the game app closed completely and opened again).
4. Pick a fight with something weak and tap **Run all safe** during the
   fight (by touch).
5. Open a vendor with grey items and damaged gear, open the window, switch
   to **Bags and vendor** and tap **Run** on each row.
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
the Graphics settings (numbers like "2"), the names of the addons that had
errors, and (probe 0.4.0) the frame sizes and the names of the game's
controller-button pictures, none of which is personal.

**Probe 0.4.0** adds ten trials for the controller UI round, on existing tabs
(still ten tabs at 720p). The steps for the handheld, and what each answer
decides, are in section 22 of the device test plan. Two of them work
differently from the rest:

- **Park the main bar off screen** (Blizzard windows 2, risky) is a guided
  trial: Start moves the game's main spell bar far above the top of the
  screen, you press a spell button and answer **Spell cast** or **Nothing
  happened**, and the bar comes back. It only starts outside a fight. If a
  fight starts before you answer, the bar stays up there until the fight ends,
  then comes back by itself. **Cancel**, **Stop** and a reload also bring it
  back.
- **Read the main bar's 8 spells** (Controller and layout) and **Set the left
  bar's see-through** (Blizzard windows 2, risky) are meant to be run again
  during a fight: the answer in a fight is the one that matters.

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
| `can't tell` | It ran and nothing refused it, but the probe could not see whether it worked. Never counted as allowed. |
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
(720p, your button size; the mockup page was removed on 2026-11-24, see DECISIONS). Report anything
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

### 20. Version 0.10.0: Catch all errors, Debug log tab

Install the 0.10.0 zip (delete the old `PocketEssentials` folder first, keep
`QuestieDB`) and fully restart the game. Running the probe (Restriction probe
section) in the same session tells us whether the game lets us see its
errors; this build relies on that.

1. Settings: **Errors** and **Debug log** are two tabs. Debug log holds the
   switch and Save the log / Empty the log, as before.
2. Errors tab: turn **Catch all errors** On. Set **Error popup** to Hide.
3. Make the game show an error. The easiest: the map error from before
   (open the map, open Options, press buttons), or run the probe's
   **Hook sees a test error**. The game's popup should not appear; the error
   shows in the Errors tab: who caused it (for example Blizzard), the
   message, the stack.
4. Use **< Previous** / **Next >** and the d-pad Left/Right; try each filter
   (All, Pocket Essentials, Blizzard, Other addons); **Clear all**.
5. Set Error popup to Show, cause an error: the game's popup shows again.
   Turn Catch all errors Off: the filter row goes, and a grey line says only
   Pocket Essentials' own errors are listed.
6. Look at **General → Button size** at Large: all rows still look right, no
   cut-off choices.
7. Tell me anything listed, and whether it was easier to read than the popup.

### 21. Version 0.11.0: Controller layout (experimental)

Do section 23 (Pocket Probe 0.6.0, part 1) first. Both zips are
in the one pre-release **v0.11.0**. This build now has the map's measured
size in it; the spots and gaps between pieces are still my first guesses,
so expect to tell me what overlaps.

Nothing more to install: both zips went in at section 23. The probe may
stay on and recording (section 24) while you do this.

1. to 3. **Done in section 23.** Send the probe file before going on.
4. **Switch it on.** Settings, **Controller** tab, turn **Controller layout**
   On. It should say a reload is needed; tap **Reload now**. Always reload
   before you fight after switching it on or off.
5. After the reload, look at the whole screen and take a screenshot:
   - the map bottom middle, the chat top right, buffs and the quest tracker
     under the chat, a wider XP bar;
   - the LT bar left of the map, the RT bar right of it, the main bar above
     the map;
   - your frame bottom left, the target bottom right.
   Tell me what overlaps, what is off centre and what is too big or small.
6. Open Edit Mode. The layout list should show **Pocket Essentials** as the
   active one, and your old layouts untouched.
7. Hold LT, RT and both. The matching bar should light where it sits.
   Open a pet or class wheel (shoulder + trigger): it should open around its
   small button beside the map.
8. **Fight for a few minutes**, pressing every bar. Watch for "Interface
   action blocked" and for any bar jumping.
9. Set **Map size** to 60% and reload when asked. The bars should close in
   around the smaller map. Take a screenshot. Try 70% the same way. Tell me
   which of 60, 70 and 80% you want as the starting size.
   Then set **Spell button size** to 85%. If any spell on your bars opens its
   own wheel, press it: does the wheel open around its button or beside it?
   Then try the other choices one at a time: Main bar under the map; frames Stacked
   and Side by side; Swing timers above the
   bars and under the LT and RT bars; a timer on Hidden. The ones that ask
   for a reload should say so.
10. Move the map a little in Edit Mode and save. Reload: it should stay
    where you put it.
11. Open Edit Mode, then change **Player and target frames** in the
    settings: it should refuse with "Close Edit Mode first."
12. **Switch it off** and reload. Your old layout and the game's own bar
    spots should be back exactly. Edit Mode should still list Pocket
    Essentials, not active.
13. Switch it on again and reload: it should return to the same Pocket
    Essentials layout, with the map where you moved it in step 10.
14. Send me `SavedVariables/PocketEssentials.lua` (the Errors page and the
    debug log) with the screenshots.

### 22. Pocket Probe 0.4.0 (testing tool): measurements for the controller UI

**What this is for.** The new controller screen (map bottom middle, spell bars
around it, and maybe a flat strip of your main spells under the map) was
designed from Blizzard's code, not on the handheld. This round measures on the
RP6 what the design guessed. Nothing of the new screen is in this release:
only the probe changes. Download: the GitHub pre-release **probe-v0.4.0**,
file `PocketProbe.zip`.

**Before you start**

1. In the game's `AddOns` folder, delete the old `PocketProbe` folder. Extract
   the new `PocketProbe.zip` there, so `PocketProbe` sits next to
   `PocketEssentials` and `QuestieDB`.
2. Turn Pocket Essentials' features off for this session (round button, every
   switch Off), or untick Pocket Essentials on the character-select AddOns
   screen. Keep the game's Gamepad UI on, as you normally play.
3. Close the game app completely and open it again (a new addon is only
   picked up after a full restart). Log in somewhere quiet in a town.

**Plain pass (nothing risky)**

4. Tap **Probe** at the top of the screen. At the bottom, **Risky** should say
   **Off**.
5. Tap **Run all safe** and wait until the top of the window says
   "pass done". The game's red error box may pop up for a moment near the end;
   that is the probe's own test and it closes again.
6. Have a quick look, no need to write anything down (tap a row to read its
   Details line):
   - **Controller and layout**: "Read the main bar's 8 spells" shows a blue
     box (readable or secret).
   - **Our own windows**: "Show the game's controller-button pictures" shows
     something like "8 of 8 copied · Xbox".
   - **Values 1**: "Read the size and scale of the screen's frames" is
     readable.

**In a fight (still nothing risky)**

7. Cast a spell that has a cooldown, then pick a fight with something weak.
   During the fight, open the probe **by touch** (the d-pad goes back to the
   game in a fight), go to **Controller and layout** and tap **Run** on
   "Read the main bar's 8 spells". If you can, do it while that spell is
   still cooling down.

**Risky pass (out of a fight)**

8. Tap **Risky** so it says **On**. Run only the rows below, one at a time,
   with their **Run** button. Leave the chat box and bag rows alone; we
   already know they upset the controller.
   - **Blizzard windows 2**: "Set the left bar to the place it already has",
     "Set the left bar's size to the size it already has", and "Set the left
     bar's see-through to what it has". Each should turn green (Allowed).
     Nothing on screen should change.
   - **Controller and layout**: "Save the layouts exactly as they are".
9. **Park the main bar.** On **Blizzard windows 2**, tap **Start** on "Park
   the main bar off screen, then press a spell button". Your main spell bar
   (the one with no trigger held) disappears off the top of the screen and
   the probe window closes by itself (while it is open it uses the d-pad and
   A). Press a d-pad or face button that holds a spell you can use right now;
   a buff on yourself is easiest. Did the spell go off? Tap **Probe** and, on
   the same row, tap **Spell cast** or **Nothing happened**. The bar
   comes back straight away. If anything looks wrong, **Cancel** brings it
   back, and so does a reload.

**Risky, in a fight**

10. Pick another fight. During it, by touch: **Blizzard windows 2**, **Run** on
    "Set the left bar's see-through to what it has". The two "Set the left bar
    to the place / size" rows will say "not tried, in combat"; that is
    expected, the probe never moves a bar in a fight.
11. Keep fighting for about a minute, using all your bars. Watch the chat for
    "Interface action failed because of an AddOn" and for a "blocked from an
    action" pop-up (tap **Ignore** on the touchscreen). Tell me whether you
    saw either.

**Send it back**

12. Tap **Save (reloads)**. The game writes the file when it reloads. Send me
    this file:
    `World of Warcraft/_forever_/WTF/Account/<account>/SavedVariables/PocketProbe.lua`
13. Afterwards: tap **Risky** back to Off, and switch your Pocket Essentials
    features back on (or delete the `PocketProbe` folder).

**What each answer decides for the new controller screen**

| What the probe measures | If it works | If it does not |
|---|---|---|
| The main bar's spells, read in a fight (step 7) | A flat strip of our own under the map can show your spells live: icon, cooldown and count | If cooldowns or counts come back "secret" in a fight, the strip can only show icons (still useful as a "which button is which" guide); if nothing can be read, the strip is dropped |
| Parked main bar still casts (step 9) | The strip can take the main bar's place on screen while the game's real bar sits out of sight and still takes your presses | The game's main bar has to stay on screen; the strip idea only works if the bar can be faded instead (next row) |
| See-through, out of a fight and in one (steps 8 and 10) | The game's bars can be faded: "Swap" (the both-triggers spells taking the main pads' place while both triggers are held) becomes possible, and the real main bar could be faded under the strip | No fading in a fight: "Swap" is dropped and the both-triggers bar keeps its own spot |
| The controller-button pictures (step 6) | The strip shows the same button pictures as your controller (Xbox, PlayStation and so on) in each spell's corner | We draw simple pictures of our own |
| Sizes of the map, frames, buff rows, quest tracker, XP bar, the two sub-menu buttons, the pet wheel and one spell button (step 5) | They replace my guessed sizes in the layout, so pieces stop overlapping or sitting off centre | (Always measured) |
| Moving, resizing and saving layouts (step 8) and no "Interface action failed" afterwards (step 11) | Controller layout 0.11.0 can place the bars and make its own Edit Mode layout as built | The layout is redesigned around what the game allows; whatever was blamed is left out |

### 23. Pocket Probe 0.6.0 (testing tool), part 1: does a hidden bar still cast?

**What this is for.** Three answers decide how compact the controller screen
can get: does your main bar still cast when it is moved off screen or made
invisible, can a bar really be faded during a fight, and can a button of our
own show a cooldown sweep. About ten minutes. Download: the GitHub
pre-release **v0.11.0**, which holds both zips: `PocketProbe.zip` and
`wow-forever-pocket-essentials.zip`. Install both now; that is the only
install for sections 23, 24 and 21.

**Before you start**

1. In `AddOns`, delete the old `PocketProbe` and `PocketEssentials`
   folders (keep `QuestieDB`). Unzip both new zips there.
2. Close the game completely and open it again. Log in somewhere quiet.
   Turn every Pocket Essentials feature Off for this part, as last time
   (round button, every switch Off).
3. A small red dot shows bottom right and a round **Stop** button sits
   beside the PE button: the probe has started recording by itself. Tap
   **Stop**. (The tests below are refused while it records.)

**Park the main bar (out of a fight)**

4. Without holding a trigger, **count the spell bars** you can see. Remember
   the number.
5. Tap **Probe**. On the bottom row tap **Risky** so it says **On**.
6. Tap the tab **Blizzard windows 2**. On the row "Park the main bar off
   screen, then press a spell button" tap **Start**. The window closes by
   itself.
7. Wait about two seconds for big letters: "Main bar parked. Press a spell,
   then tap Probe."
8. **Count the bars again.** Tell me both numbers.
9. Press a d-pad or face button that holds a spell you can use right now (a
   buff on yourself is easiest). Watch whether it casts.
10. Tap **Probe**. On the same row tap **Spell cast** or **Nothing
    happened**. The bar comes back.

**Fade the main bar (out of a fight)**

11. Same tab, the row "Fade the main bar to nothing, then press a spell
    button": tap **Start**. Wait for the big letters: "Main bar is
    invisible. Press a spell, then tap Probe."
12. Is the main bar gone from view? Press a spell on it as in step 9.
13. Tap **Probe**. On the same row tap **Spell cast** or **Nothing
    happened**.

If anything looks wrong at any point, **Cancel** on the row puts it back,
and so does a reload.

**In a fight**

14. Pick a fight that will last half a minute. If you have a spell with a
    cooldown of a few seconds, cast it first.
15. During the fight, **by touch** (the d-pad belongs to the game in a
    fight): tap **Probe**, then **Fight tests** (bottom row, second button).
16. Look at the top of the screen, just right of the Probe button. Two
    small squares marked **1** and **2** show for 8 seconds. Does a dark
    sweep turn on square 1, square 2, both or neither? Your left bar blinks
    once; that is the fade test.
17. Keep fighting until the top line says "Fight tests done". Tell me the
    numbers it shows.
18. Start one more fight. During it, by touch, do steps 11 to 13 again (the
    fade test, this time in a fight).
19. Keep fighting for a minute with all your bars. Tell me if you saw
    "Interface action failed because of an AddOn" or a "blocked" pop-up.

**Send it back**

20. Tap **Risky** back to Off. Tap **Save (reloads)**.
21. Send me `WTF/Account/<account>/SavedVariables/PocketProbe.lua`. The
    probe also took a few screenshots (before and after parking and fading,
    and of the two squares); send those too if you can find the game's
    `Screenshots` folder.
22. Go on to section 24 and just play. I work through this file meanwhile.

**What each answer decides**

| Question | If yes | If no |
|---|---|---|
| A parked or invisible main bar still casts (steps 9 and 12) | A flat strip of our own can take the main bar's place on screen while the game's real bar does the casting out of sight | The game's main bar stays visible; we only shrink and arrange it |
| A real fade in a fight (step 16, the blink) | Quiet bars can fade the LT, RT and both-triggers bars until their trigger is held, in a fight too | Bars fade only out of a fight |
| A cooldown sweep on our own square (step 16) | The strip can show the game's own cooldown sweep | The strip dims an icon while it is on cooldown instead (already proven readable) |

### 24. Pocket Probe 0.6.0, part 2: play as normal with the recorder on

**What this is for.** Real numbers from the handheld for how heavy Pocket
Essentials is: time per frame, memory, frame rate, and the cost of each
feature, split by what you were doing. Nothing to type and nothing to watch.

1. Switch your Pocket Essentials features back on, the way you normally
   play. Optional, and what I would do: also switch **Controller layout**
   On now (Settings, **Controller** tab) and tap **Reload now**. Then this play
   session is also the layout's test: section 21 from step 5, whenever you
   feel like it.
2. Tap **Probe**. At the top of the window tap **Start recording**. It
   should read "Recording 0 min" in red. Close the window. The red dot and
   the round **Stop** button are back.
3. Play as you normally would for at least 15 minutes: a town, some
   quests, a vendor, a few fights. Longer is better. It stops by itself
   after 2 hours.
4. A reload keeps the same recording going. A full restart of the game
   starts a new one (the last three are kept).
5. When you are done: tap the round **Stop**, then **Probe**, then
   **Save (reloads)**.
6. Send me `SavedVariables/PocketProbe.lua` again (it still holds part 1's
   answers too) and `SavedVariables/PocketEssentials.lua`.
7. If the dot or the Stop button is ever in the way, or anything feels
   slower with the recorder on, tell me. Stopping the recording puts
   everything back; unticking Pocket Probe on the character-select AddOns
   screen removes it altogether.

On a computer: `scripts/read-probe.sh <PocketProbe.lua> --perf` prints the
report, and `--perf --diff <older file>` compares two recordings.

### 25. Version 0.11.2 and Pocket Probe 0.7.0: the lunch test

**What this is for.** Check the four layout fixes, and let the probe answer
the face-bar questions while you play. Out of a fight first (about five
minutes), then just play. The only thing to do in a fight is one tap on the
round **Fight** button, once. Download: the GitHub pre-release **v0.11.2**,
which holds both zips.

**Install**

1. In `AddOns`, delete the old `PocketProbe` and `PocketEssentials` folders
   (keep `QuestieDB`). Unzip both new zips there.
2. Close the game completely and open it again. **Log into your level 40
   main first** (the first character in after the update takes over the
   old "layout to go back to", which was your main's).
3. The red dot and the round **Stop** show: the recorder started by itself.
   Tap **Stop** for now (the two tests below cannot run while it records).

**The layout fixes (on the main)**

4. Open Pocket Essentials' settings, tab **Controller**. If **Controller
   layout** is Off, switch it On and tap **Reload now**.
5. On the row **Template** tap **Start over**, then tap it again to confirm.
   Tap **Reload now**. (This rebuilds our layout from the new template; any
   changes you made to it in Edit Mode are undone.)
6. Look and tell me: is the XP bar at the very top, in the middle, clear of
   the hints box and the chat? Is the zone name and clock under the map? Do
   the buffs sit below the chat's last lines? Take a screenshot.

**Probe set-up (out of a fight)**

7. Tap **Probe**. On the bottom row tap **Risky** so it says **On**.
8. Tab **Blizzard windows 2**, row **Watch my next fights**: tap **Arm**. It
   reads "Watching, 0 min".

**Wheels on a faded bar (out of a fight, on a character with a pet)**

If your main has no pet, skip to step 13 and do steps 9 to 12 on your
warlock later.

9. Same tab, row "Fade the four bars, then open the pet wheel and a spell
   wheel": tap **Start**. The window closes and big letters say what to do.
10. Open the pet wheel (LB + LT). Is it on screen? Close it.
11. Open a spell wheel (a spell button that opens a wheel). Is it on screen?
    Close it.
12. Tap **Probe**. On the same row tap **Wheel visible** or **Wheel hidden**.
    The bars come back.

**Fade for next fight**

13. Same tab, row "Fade the main bar for your next fight, with nothing to do
    in it": tap **Start**. Big letters: "Main bar will vanish in your next
    fight. Just play."
14. Fight one mob with your main bar as normal. The bar vanishes when the
    fight starts and comes back when it ends.
15. Big letters ask "Did your spells cast while the bar was invisible?" Tap
    **Probe**, then on that row **Yes, they cast** or **No**.

**Just play**

16. Tap **Probe**. At the top of the window tap **Start recording**. Close
    the window.
17. Play as you normally would, as long as you like (15 minutes or more is
    best): quests, a vendor, fights with LT and RT spells and a cooldown or
    two. The watchers count by themselves.
18. **Once, in a fight:** by touch, tap the round amber **Fight** button
    beside Stop. A tick shows when the tests are done. That is all.
19. If you see "Interface action failed because of an AddOn" or a "blocked"
    pop-up at any time, note when.

**Another character (last, it reloads)**

20. Log out and into another character that used its own layout. A chat
    line should say "This character now uses the controller layout. Open the
    settings and tap Reload now to finish." Do that. Does the screen then
    look like your main's?

**Send it back**

21. Open Pocket Essentials' settings, tab **Errors**. Take a screenshot of
    it, even if it is empty.
22. Tap **Stop**, then **Probe**, then **Save (reloads)**.
23. Send me `SavedVariables/PocketProbe.lua`, `SavedVariables/PocketEssentials.lua`
    and the screenshots from the game's `Screenshots` folder (the probe takes
    one for the cooldown sweep and one for the wheels).

To start again from empty later: Probe, tab **Controller and layout**, row
**Clear saved results**, tap **Clear** twice.

On a computer: `scripts/read-probe.sh <PocketProbe.lua> --details --perf`.

### 26. Version 0.12.0: the mockup's setup in game

**What this is for.** The Controller layout now matches the mockup's "Face
bars (one setup)" screen, using the game's own bars. Pocket Probe is not
needed (untick it on the AddOns screen if you like). Download: the GitHub
pre-release **v0.12.0**.

1. In `AddOns`, delete the old `PocketEssentials` folder (keep `QuestieDB`)
   and unzip the new zip. Fully restart the game and log into your main.
2. A chat line says the controller layout was updated (or, on a character
   not on our layout yet, that it now uses it). Open the settings and tap
   **Reload now**. If you started clean (old Pocket Essentials saved file
   deleted) and switch the layout On by hand, you will still see the old
   arrangement after that reload: on the Controller tab tap **Start over**,
   tap it again, then **Reload now**.
3. Look at the screen and take a screenshot. You should see: the map bottom
   middle with its name and the swing timers under it; on the left the LT
   bar with the main bar under it; on the right the RT bar with the LT+RT
   bar under it; your frame with the pet above it on the left, the target on
   the right; the XP bar at the top. Tell me what is in the way.
4. Hold LT, then RT, then both: does the right bar light up each time?
5. Open the pet wheel (LB + LT) and the pet spells wheel (RB + RT). Does
   either land on a bar or a frame?
6. Target something with LB and RB. Do the two targeting pictures sit next
   to the main bar's corner, and does targeting work as before?
7. Fight a few mobs with all four bars. Do your spells cast, and does
   anything say "Interface action blocked" or "failed because of an AddOn"?
8. Settings, tab **Errors**: screenshot it. Send me
   `SavedVariables/PocketEssentials.lua` and the screenshots.

To go back to your own layout: Controller tab, switch Off, **Reload now**.

### 27. Version 0.13.0: our own spell pictures, split like the controller

**What this is for.** The Controller layout now draws your spells itself:
d-pad spells left of the map, face-button spells right of it, in one low
band at the bottom. The game's bars are still there, invisible, and do the
casting. Picture of the plan: the mockup page's "Face bars
(one setup)", Show "0.13.0: split face" (removed on 2026-11-24, see DECISIONS). Download: the GitHub pre-release
**v0.13.0** (both zips; Pocket Probe is unchanged, you don't need it).

1. In `AddOns`, delete the old `PocketEssentials` folder (keep `QuestieDB`)
   and unzip the new one. Fully restart the game and log into your main.
2. A chat line says the controller layout was updated. Open the settings,
   tap **Reload now**.
3. Take a screenshot. You should see: no hint box top left (the quest
   tracker is there now); at the bottom, left of the map, four small
   diamonds of spell pictures with a plus in their corners (your d-pad);
   right of the map, four with four dots (your face buttons); your frame
   beside the left pictures, your target's beside the right ones. Tell me
   what is in the way and what is too small to read.
4. Hold LT, then RT, then both. Does the matching pair of diamonds (one each
   side, tagged LT, RT, LT+RT) go bright while the rest dims?
5. Out of a fight, press a few spells from each bar. Do the right spells
   cast? (Same buttons as before.)
6. Fight a few mobs using all four bars. Do spells cast? Do the pictures
   darken while on cooldown, and grey out when you can't use them? Does
   anything say "Interface action blocked" or "failed because of an AddOn"?
7. Open the pet wheel (LB + LT) and the pet spells wheel (RB + RT). Is the
   wheel drawn on top of the pictures?
8. Tap a spell picture with your finger. Nothing should happen.
9. If the pictures ever vanish and the game's bars come back, the Controller
   card says why: screenshot it.
10. Settings, tab **Errors**: screenshot it. Send me
   `SavedVariables/PocketEssentials.lua` and the screenshots.

Things to watch for (found in review, not fixed yet):
- A wheel or the "new spell" picture opened from a spell button appears
  where the game's hidden button is, which may be on the other grid cell.
- The game's page number shows above the left pictures while you hold the
  page button.
- A warrior's or druid's stance bar set to replace the LT+RT bar sits
  invisible over the top of the map (the pictures still show it right).

To go back to your own layout: Controller tab, switch Off, **Reload now**
(the hint box comes back too).

### 28. Version 0.14.0: one panel a side, the triggers swap it

**What this is for.** In 0.13.0 eight small diamonds were on screen at once
and it was hard to see which ones a trigger lit. Now only two bigger
diamonds sit beside the map, and holding a trigger swaps what they show.
Spec `docs/superpowers/specs/2026-11-23-controller-layout-0.14.0-console.md`.
Download: the GitHub pre-release **v0.14.0** (both zips; Pocket Probe is
unchanged, you don't need it).

1. In `AddOns`, delete the old `PocketEssentials` folder (keep `QuestieDB`)
   and unzip the new one. Fully restart the game and log into your main.
   A chat line says the controller layout was updated: open the settings and
   tap **Reload now**.
2. With Controller layout on, take a screenshot. You should see only two
   diamonds beside the map, bigger than before: your main bar's d-pad
   spells on the left, its face-button spells on the right. Your frame and
   your target's sit further out, past where the outer diamonds will open.
3. Hold LT: the left side opens into two diamonds (LT d-pad on the outside,
   LT face buttons next to the map); the right side dims. Screenshot.
4. Hold RT: the right side opens into two (RT d-pad next to the map, RT face
   buttons on the outside); the left side dims. Screenshot.
5. Hold both: the two diamonds next to the map show the LT+RT bar. Let go:
   back to the main bar.
6. Out of a fight, cast from each state (nothing, LT, RT, both). Does the
   spell that casts match the picture lit at that spot?
7. Fight a few mobs and do the same. Any "Interface action blocked" or
   "failed because of an AddOn"? Do your frame, your target's frame, its
   cast bar or its buffs ever sit on top of the pictures?
8. Settings, tab **Errors**: screenshot it. Send me
   `SavedVariables/PocketEssentials.lua` and the screenshots.

Things to watch for (known, not fixed yet):
- A wheel or the "new spell" picture opened from a spell button appears
  where the game's hidden button is: under the diamond next to the map,
  which is not always where that spell's picture is drawn (LT's d-pad and
  RT's face buttons are drawn on the outside).
- The game's page number shows near the left pictures while you hold the
  page button.

To go back to your own layout: Controller tab, switch Off, **Reload now**.

### 29. Version 0.15.0: polish before the first public post

**What this is for.** A reviewer read every file and the confirmed bugs and
rough edges are fixed, and the Controller tab gets "Spell panel size". Spec
`docs/superpowers/specs/2026-11-24-0.15.0-polish.md`. Download: the GitHub
pre-release **v0.15.0** (both zips; Pocket Probe is unchanged, you don't
need it). Turn the **Debug log** on before you start.

1. In `AddOns`, delete the old `PocketEssentials` folder (keep `QuestieDB`)
   and unzip the new one. Fully restart the game and log in.
2. **Settings, look around:** the scroll tabs show arrows, not "^" and "v";
   General says "Size of all buttons", "Round button colour", "I play with",
   "Move on screen". Open Move on screen and close it: the settings come
   back. Quest icons > Icon key: the page has its title. Screenshot anything
   that wraps onto two lines or looks out of line.
3. **Setup guide** (General > Setup guide > Open): the window says "Setup
   guide"; on the first screen Skip sits at the bottom left; the controls row
   reads "Press it"; the last screen lists the features in the guide's order.
4. **Controller tab:** set **Spell panel size** to 80%, tap Reload now,
   screenshot. Then 120%, Reload now, screenshot: your frame and your
   target's sit just above the panels. Is anything overlapping? Do LT, RT and
   both still swap the panels? Put it back to the size you like.
5. **Cooldowns on the pictures:** use a spell with a long cooldown, walk
   around without casting until it is ready: its picture brightens by itself.
6. **Vendor:** with greys in your bags, buy one food item and let the greys
   sell. The line counts items (a stack of 5 is 5) and only their price.
7. **Chat picker:** check the whisper list on an alt does not show your
   main's names. Whisper yourself from another character if you can.
8. **Bank:** open the bank with Bag sorting on: the Sort tab is gone while it
   is open and comes back after.
9. **Quests:** a quest whose items drop in more than one zone: the icons show
   in the zone you are in. Leave a dungeon: the minimap icons come back.
10. Settings, tab **Errors**: screenshot it. Send me
    `SavedVariables/PocketEssentials.lua` and the screenshots.

Things to watch for (known, not fixed):
- A wheel or the "new spell" picture opened from a spell button appears
  where the game's hidden button is.
- The game's page number sits just above the left panel.
- Pet and possess bar pictures show no cooldown.

### 30. Version 0.16.0: the playing screen's arrangement; Pocket Probe 0.8.0

**What this is for.** The first half of the new playing screen: with the
Controller layout on, the chat, quest list, buffs, map, timers, targeting
pictures, tooltip and PE button move to new spots and nothing should overlap.
The slim bars come in 0.17.0, built on what the probe finds here. Spec
`docs/superpowers/specs/2026-11-24-playing-screen-layout-design.md`. Download:
the GitHub pre-release **v0.16.0** (both zips: Pocket Essentials and
PocketProbe). Turn the **Debug log** on before you start.

1. In `AddOns`, delete the old `PocketEssentials` folder (keep `QuestieDB`)
   and unzip the new one; put the new `PocketProbe` folder in as well. Fully
   restart the game and log in. At this first login the addon should update
   the layout by itself: a chat line says so and it asks for one reload. Tell
   me whether it asked by itself, then reload. Only if it did not ask:
   Controller tab, **Rebuild the layout**, then reload once when it asks.
2. **The arrangement, screenshot it.** Chat at the left edge, tabs in a row
   above the text, no dark box; quest list at the top right; buffs along the
   top; map at the bottom middle with a plain black ring; place name and clock
   under it; three swing timers above it; the PE button in the bottom left
   corner. Screenshot at rest and while holding LT, RT (the left and right
   triggers) and both.
3. **The five collisions** from your 2026-11-24 screenshots: is any piece
   still on top of another? Name each one that is.
4. **Chat:** open the chat and type. Does the dark box stay gone? Do all five
   tabs still switch? Does a long message wrap inside the chat? A pop-up
   whisper window may still show its dark box: that is expected for now.
5. **Controls reminder:** On, then Off. On shows the game's hint box in the
   top left; Off hides it. Does it overlap anything?
6. **Map buttons:** Hidden (the default) shows only the place name and clock;
   Shown adds the magnifier and the calendar. Switch Hidden then Shown: does
   the map jump? Do the buttons work when Shown?
7. **Spell panel size** 100%, then 120% (Reload now each time): do the chat,
   the PE button, the tooltip and your frames stay clear of the panels?
8. **Tooltip:** point at a target and at an item. Is the tooltip above your
   target's frame, and does a tall one reach the quest list?
9. **PE button:** move it with "Move on screen": the first press of an
   arrow should move it one small step from the bottom left corner, not jump.
   Then switch the layout off and on again. Tell me where the button ends up.
10. **Layout off puts everything back.** Switch the layout off. Before you
    reload, look at the chat box, the map's gold ring, the two map buttons and
    the controls reminder: are they back as before? Then reload and look again.
11. **The probe, Fight tests.** Have your pet out and a debuff on your target.
    The Fight button is on the left edge above the chat (not beside the PE
    button) while the layout is on. Tap it once and wait until the word Fight
    on it turns into a tick mark (or the word Done). This also tries the
    game's own buff box for addons on your target; nothing to switch on for
    it, and you see nothing of it. It waits half a second for the game, so the
    tick comes about half a second later than before. Then open the probe's
    window and take a **performance recording** in town, and another in a
    fight.
12. **The probe, the target frame's buffs (last, out of a fight).** Target
    something with a buff, and stay out of a fight until Risky and Auto are
    both off again. In the probe's window tap the Risky button so it reads
    **Risky: On**, then the Auto button so it reads **Auto: On**. Wait until
    the status line says "pass done" (about a minute). This pass also opens
    and closes the chat and the bags and moves or fades the bars for a moment:
    that is expected. It tries once whether the target frame's buff icons can
    stay visible while the rest of the frame fades, and puts it back at once.
    Then tap them back to **Risky: Off** and **Auto: Off**, and tap
    **Save (reloads)**: the risky trials can leave the controller refusing
    some actions until that reload.
13. Settings, tab **Errors**: screenshot it. Send me
    `SavedVariables/PocketEssentials.lua`, `SavedVariables/PocketProbe.lua`
    and the screenshots.

Things to watch for (known, not fixed):
- A pop-up whisper window may still show its dark box.
- A wheel or the "new spell" picture opened from a spell button appears where
  the game's hidden button is.
- With Map buttons Shown, the magnifier's left edge may not take a tap.
- A full row of eleven buffs may reach the quest arrow's top spot.

### 31. Version 0.16.4: clean-up, and the tools for the long test

**First device sitting, 2026-11-25 (0.18.0, a warlock with a Voidwalker):**
free play rather than these numbered steps (one mark, one snapshot). No refused action in any 0.18.0 sitting; Mark and Snapshot wrote to
the log (snapshot 1: 53 pieces, 11 not found, 6 overlaps, before any
arranging). The Part rows still held Off values from 2026-11-24 and hid the
split panels until set to On; the rows are to be removed.
The steps below have not been walked through one by one.

This section is the first part of
one long sitting; later sections (0.17.0, 0.18.0) carry on in the same log.
Wherever a step says **Mark**, tap "Mark a test section" (Settings, Debug log
tab, or the bottom of the Controller tab) and check that chat says the number
given. Wherever it says **Snapshot**, tap "Save a snapshot" in the same place
and wait for "Snapshot N saved to the debug log." Stand still, out of a
fight, with no window open except the settings.

Before you start:

1. Install 0.16.4 only (no probe folder). Settings, Debug log tab: tap
   **Empty**, then switch the Debug log **On**. The line should read
   "1 of 6,000 lines". Switch Catch all errors on. Controller layout on.
   Tap **Save** (it reloads).

Section 1, at rest:

2. **Mark** (chat: "Section 1 marked"). Close the settings and look at the
   right pad's top button (Inspect), with no target: is it a grey button with
   a magnifier, like the other three buttons, and no longer a black square?
   Screenshot. Target something: does the magnifier change?
3. **Snapshot** (chat: "Snapshot 1 saved").

Section 2, the triggers:

4. **Mark** (2). Hold LT alone, let go; hold RT alone, let go; hold both, let
   go. Do the panels swap as before (LT opens two on the left, RT two on the
   right, both show one each side)? They are followed the same way as in
   0.16.3 here.

Section 3, friendly targeting (LB):

5. **Mark** (3). Make sure neither trigger is held. Hold **LB only** and
   screenshot. Expected: the left panel shows the d-pad (four empty squares
   when you are not in a group), the right panel shows X your pet's face (if
   you have a pet out), Y a raid mark, B your target's target (empty if there
   is none), A your own face. Let go.
6. Now hold **LB and RT together** and screenshot. Expected: the two RT
   panels on the right, and four dim squares on the left. This is what the
   earlier screenshot showed.

Section 4, enemy targeting (RB):

7. **Mark** (4). Send your pet at an enemy and target that enemy while it
   fights the pet (its target must be someone other than you; a training
   dummy will not do). Hold **RB only** and screenshot: is your pet's face on
   the B square now?
8. Target your own pet, hold RB: the B square should be empty (the game shows
   nothing there either). Screenshot.

Section 5, the parts:

9. **Mark** (5). Settings, Controller tab: the six rows at the bottom should
   read "Part: ...", all On, and a seventh, "Part: follow the triggers with a
   hook", Off (leave that one for step 12). Switch **Part: map ring and
   buttons** Off; chat
   should say "Part switches count from the next reload." Tap Save (reload).
   Is the map's gold ring back while everything else is as before?
   **Snapshot**. Switch it On again and reload.

Section 6, layout off:

10. **Mark** (6). Switch the Controller layout off (do not reload yet).
    **Snapshot**. Then reload, and **Snapshot** again. Is everything back
    where the game has it?
11. Switch the layout on again and reload.

Section 7, the hook (a second way to follow the triggers, never tried on
the device):

12. **Mark** (7). Settings, Controller tab: switch **Part: follow the
    triggers with a hook** On. Tap Save (reload). Hold LT alone, RT alone,
    then both, a few times each. Do the panels swap exactly as in step 4? Does
    "Interface action failed because of an AddOn" or "The game blocked Pocket
    Essentials" appear? Change target and press B once or twice as well.
    **Snapshot**.
13. Switch the row **Off** again and tap Save (reload), whatever the result,
    so the rest of the test runs the proven way. Say which it was: swapped
    and clean, swapped with a blocked line, or did not swap.

Section 8, a fight:

14. **Mark** (8). Fight two or three enemies, using LT and RT spells and the
    targeting bars. In the fight, tap **Snapshot** once: chat should say it
    is saved when the fight is over, and then say "Snapshot N saved" after
    the fight.
15. Any "Interface action failed because of an AddOn" or "The game blocked
    Pocket Essentials"? Screenshot it at once and say what you did just
    before.

To finish this part:

16. Settings, Debug log tab: note the line count. Tab Errors: screenshot it.
    Tap **Save** (reload). If you are going on to the next section's steps,
    keep playing; the file is sent once, at the very end:
    `SavedVariables/PocketEssentials.lua`, with the screenshots.

Things to watch for (known, not fixed):
- The grey button face is a first guess at the look; say if it reads badly.
- If the log line says the count went down by itself, that is the log making
  room: the start of each session, the marks and the snapshots are kept.

### 32. Version 0.17.0: the slim bars

**First device sitting, 2026-11-25 (0.18.0, a warlock with a Voidwalker):**
free play rather than these numbered steps (one mark, one snapshot). Slim bars On: no errors, the bars followed a 56 second fight (target and
target of target came and went), no stopped bar, no refused action, and
taps where the game's frames were do nothing. Only the first word of a name
shows. Step 18 (the probe's Buffs in a fight) was not done.
The steps below have not been walked through one by one.

This carries on from section 31 in
the same sitting and the same log: Debug log On, Catch all errors on,
Controller layout on, no probe folder (it is only needed for the very last
step). **Mark** and **Snapshot** mean the same two buttons as in section 31.
The marks go on counting; straight after section 31 the first one here is 9.
If your numbers differ, just say which numbers you saw.

**What this is.** A new row at the bottom of the Controller tab, **Slim
bars**, Off until you switch it on. On, the game's own player, pet, target and
target-of-target frames go invisible and five flat bars take their place: you
on the left, your target on the right, your pet and your target's target as
small bars above them, and your target's cast as a thin bar under the target.

**What is not in yet.** The buff and debuff boxes. With Slim bars On you will
not see your target's buffs and debuffs anywhere. Portraits, raid marks and
the elite border are gone too, and so are **combo points** and anything else
your class shows on the game's player or target frame. That is expected.

Section 9, before:

1. **Mark** (9). Controller tab: the row **Slim bars** should be there and
   read Off. Target something and screenshot the screen as it is now (the
   game's own frames). **Snapshot**.

Section 10, switching on:

2. **Mark** (10). Switch **Slim bars** On. Chat should say "Slim bars count
   from the next reload." and the card should ask for a reload. Nothing else
   should change yet. Tap Save (it reloads).
3. After the reload, with no target and no pet: screenshot. Expected: the
   game's player frame at the bottom left is gone. A flat dark bar sits on
   the left, above where the outer spell panel opens: your level and name on
   its left, your health as a number on its right, a thin power bar under the
   health. Nothing on the right side. **Snapshot**.
4. Tap the spot where the game's player frame used to be (bottom left,
   below and left of the new bar). Expected: nothing happens. Tell me if it
   targets you or opens a menu.
5. Point at a character and at an item in your bag. Is the tooltip in the
   bottom right corner now? Does it cover any part of a bar?

Section 11, the pet:

6. **Mark** (11). Call your pet. A small bar with its name should appear
   above the left end of your bar. Screenshot. Dismiss the pet: the small bar
   should go. Call it again.

Section 12, the target and its target:

7. **Mark** (12). Target a friendly character: a bar on the right, the mirror
   of yours, green, with its level, name and health number. Screenshot.
   Target an enemy: red. Screenshot. Clear your target: the bar goes.
8. Send your pet at an enemy and target that enemy. A small bar above the
   right end of the target bar should show who the enemy is attacking (your
   pet's name). With all four bars showing: screenshot at rest, then holding
   LT, RT and both, and **Snapshot**. Does a spell panel or anything else
   touch a bar?

Section 13, a cast:

9. **Mark** (13). The easy way first: target **yourself** and use your
   hearthstone (or any spell with a cast time). A thin yellow bar should
   appear under the target bar, fill from left to right with the spell's name
   on it, and go when the cast is done. Screenshot it half way. Start again
   and step forward to cancel: the bar should go at once.
10. Then find an enemy that casts spells, target it and fight it. Does the
    bar show its casts? If you can interrupt one, does the bar go at that
    moment? Screenshot one cast.

Section 14, a fight:

11. **Mark** (14). Fight two or three enemies with your pet. While fighting,
    look at each bar: does your health move, and its number? Your power? The
    target's health and name? The pet's bar? Does the small bar on the right
    switch between you and your pet as the enemy changes its mind? Screenshot
    in the middle of a fight. Tap **Snapshot** once in a fight (it is saved
    when the fight ends).
12. Tell me about any bar that was empty, stuck or blank **during** the fight
    but right again afterwards: that is the thing only your device can show.
13. Did one of the game's own frames come back into view at any time, in or
    after a fight? Screenshot it.
14. Any "Interface action failed because of an AddOn" or "The game blocked
    Pocket Essentials", or a button or targeting that stopped answering?
    Screenshot it at once and say what you did just before.

Section 15, the panel size:

15. **Mark** (15). Spell panel size 120%, Save (reload). Screenshot at rest
    and holding LT and RT. The bars should be exactly where they were, and
    the bigger panels should stop just under them. **Snapshot**. Put the size
    back to yours and reload.

Section 16, layout off:

16. **Mark** (16). Out of a fight, switch the Controller layout off (do not
    reload yet). The game's four frames should be back at once and the five
    bars gone. **Snapshot**. Reload, **Snapshot** again. Switch the layout on
    again and reload: are the bars back?

Section 17, switching off again:

17. **Mark** (17). Switch **Slim bars** Off and Save (reload). Expected:
    everything as it was in step 1: the game's frames, and the tooltip above
    the target of target again. Tap the game's player frame: it should target
    you again. **Snapshot**.

Last, for the boxes that are still to come:

18. With Slim bars still Off, do steps 11 and 12 of section 30 (the probe's
    Fight tests with your pet out and a debuff on your target, then the Risky
    pass). That needs the `PocketProbe` folder and a full restart of the
    game, so keep it for the very end of the sitting.
19. Settings, Debug log tab: note the line count. Tab Errors: screenshot it.
    Tap **Save** (reload). Send `SavedVariables/PocketEssentials.lua` (and
    `PocketProbe.lua` after step 18) with the screenshots.

Things to watch for (known, not fixed):
- No buff or debuff boxes yet, so nothing shows your target's debuffs while
  Slim bars is On.
- The small bar on the right may be a moment behind when the enemy attacks
  someone who is neither you nor your pet.
- A channelled spell fills the cast bar up; the game's own empties it.
- An open spell wheel covers the inner end of a bar while it is open, and a
  very tall tooltip reaches the right end of the target bar.
- The right-click menus of the game's player, pet and target frames cannot be
  reached while Slim bars is On.
- In Edit Mode the game's four frames are invisible too while Slim bars is
  On.
- The bars' black outline is a very thin line; say if it looks uneven.

Things to look at and tell me about (nobody could check these off the
device):
- **A grey bar with a "?"** where the health number should be means that bar
  stopped getting values from the game. Say which bar and when (in a fight?).
- **Your own cast bar.** Cast something yourself with Slim bars On. If your
  cast bar does not appear at all, the game has it attached to your player
  frame (Edit Mode, cast bar, "Lock to player frame"), which is invisible
  now. Say whether you saw it.
- **A tap just above the target bar** (with a target that has buffs or
  debuffs): does a tooltip pop up from nowhere? The game's invisible buff
  icons sit there, outside the patch that swallows taps.
- **Do your health and power bars move as smoothly as the game's own did,**
  or in visible jumps?
- **Does the cast bar fill smoothly** or in steps?
- **The tap guards:** in the snapshots from steps 3 and 8, the lines "tap
  guard, player frame" and the other three give their place. Tap around the
  edges of where the game's frames used to be: is there a spot that still
  targets you or opens a menu?

### 33. Version 0.18.0: arrange it yourself

**First device sitting, 2026-11-25 (0.18.0, a warlock with a Voidwalker):**
free play rather than these numbered steps (one mark, one snapshot). Arrange it yourself On: "working great". Live pieces and Edit Mode pieces
(map, buffs) moved; every Apply logged 0 overlaps and exact mirrors, and the
offsets were back after each reload. Arrange: spell wheels stayed Off, so
the two wheel buttons could not be moved.
The steps below have not been walked through one by one.

This is a first version made
without you: say what you would change. It carries on from section 32 in the
same sitting and the same log: Debug log On, Catch all errors on, Controller
layout on. **Mark** and **Snapshot** are the same two buttons as before. The
marks go on counting; straight after section 32 the first one here is 18. If
your numbers differ, just say which numbers you saw.

**What this is.** Three new rows at the bottom of the Controller tab:
**Arrange it yourself** (Off), **Arrange: spell wheels** (Off) and **Arrange
the screen** with a button **Arrange**. The button opens a small window: pick
a piece with **Previous piece** / **Next piece**, move it with **Up, Down,
Left, Right**. Some pieces move as you press. Others (the game places them
itself) only move after **Apply** and a reload; the window says which.

Do sections 18 to 21 with **Slim bars Off**, so the game's own frames show.

Section 18, before, and switching on:

1. **Mark** (18). **Snapshot**. Tap **Arrange** while the row above it still
   reads Off: chat should say "Switch on Arrange it yourself first, then
   reload." and no window opens.
2. Switch **Arrange it yourself** On. Chat should say "Arrange it yourself
   counts from the next reload." and the card should ask for a reload.
   Nothing on the screen should move. Tap Save (it reloads).
3. After the reload: is everything exactly where it was? **Snapshot**.

Section 19, a piece that moves at once, and a mirrored pair:

4. **Mark** (19). Out of a fight, tap **Arrange**. The settings go away and a
   small window appears, top left, titled "Arrange: Map", with a yellow
   outline around the map. Screenshot. Can you read it? Is it too big?
5. Tap **Next piece** until the title reads "Arrange: Inner spell panel,
   left". The window should say "Moves as you press." and "Twins are an exact
   mirror.", with a yellow outline on the left panel and a thinner one on the
   right panel.
6. Tap **Up** three times, then **Left** three times. Expected: the left
   panel moves up and out a little each tap, and the **right panel moves up
   and out the same amount, as its mirror**. The window reads "Moved 6 left,
   6 up." Screenshot. Does the pair look perfectly even to you?
7. Tap **Step: small (2)** (it becomes "Step: big (10)") and **Up** once: a
   bigger jump. Hold LT, then RT: do the panels that open sit right against
   the moved ones? Screenshot each.
8. Tap **Twins: mirrored** (it becomes "Twins: free") and **Down** twice: now
   only the left panel moves, and the window says "NOT a mirror of its
   twin." Screenshot. Tap **Twins: free** again: the right panel should jump
   to the mirror of the left one, and the warning goes.
9. Now with the controller: d-pad to **Right** and press A a few times, then
   d-pad to **Reset** and press A. Both panels should be back where they
   started. Did the d-pad reach every button? Press B: the window closes and
   the settings come back. **Snapshot**.
10. Cast a spell from a moved panel before and after step 9, and tap a
    picture: does it still behave as before (a tap does nothing)?

Section 20, the centre line and an Edit Mode piece:

11. **Mark** (20). **Arrange**, pick **Map** (step small). Tap **Left**
    once. Expected: the window says "Moved 4 left. On the centre line." (the
    map sits a little right of the middle by default, and the first step
    toward the middle lands it exactly there), and "Waiting for Apply: Map."
    The yellow outline moved; **the map itself did not**. That is right: the
    game places the map.
12. Pick **Chat**, step big, tap **Down** four times. Expected: the window
    names what the chat would now cover ("Overlaps: ...") and those pieces
    get a red outline. Screenshot. It only warns.
13. Tap **Up** twice, so the chat is 20 lower than it was. Tap **Apply**.
    Expected: the window closes, chat says "Arrangement written...", and the
    settings ask for a reload once. Tap Save (it reloads).
14. After the reload: is the map in the exact middle now, and the chat a
    little lower? Screenshot and **Snapshot**. Did the map's black border and
    its place-name strip come along?

Section 21, the game's frames as a pair:

15. **Mark** (21). **Arrange**, pick **Player and pet frames**. Tap **Up**
    twice (step big). The outlines of both sides should rise together. Tap
    **Apply**, Save. After the reload: did your frame and the target's frame
    both move up by the same amount? Target something. Screenshot,
    **Snapshot**.

Section 22, the spell wheels:

16. **Mark** (22). First open both wheels (LB+LT, RB+RT) and screenshot where
    they open now. Then switch **Arrange: spell wheels** On (no reload).
    **Arrange**, pick **Spell wheels and their buttons** (the last piece).
    Tap **Left**: the window should say it only moves up and down. Step big,
    tap **Up** three times: the two round buttons and the prompts under them
    should rise at once.
17. Close the window. Open both wheels again: do they open higher, on their
    buttons, clear of the swing timers and the map? Screenshot each.
    **Snapshot**. Any "Interface action failed" or a wheel that will not
    open? Screenshot at once and say what you did just before.

Section 23, with the slim bars:

18. **Mark** (23). Switch **Slim bars** On, Save. **Arrange**: the list should
    now have "Slim bars, you and pet" and "Slim bars, target", and no longer
    the game's frames. Pick one, tap **Up** and **Left** a few times: both
    sides should move as mirrors, the pet bar and cast bar with them.
    Screenshot with a target and your pet out. **Snapshot**.

Section 24, a fight:

19. **Mark** (24). Open **Arrange**, pick any spell panel, tap **Up** once,
    and pull an enemy with the window open. Expected: the window closes at
    once, chat says "Arrange closed for the fight. Your moves are kept." In
    the fight, try **Arrange**: it should refuse. After the fight open it
    again: the piece is where you left it. Any blocked action? Screenshot.

Section 25, the resets and Off:

20. **Mark** (25). **Arrange**, pick a spell panel, tap **Reset**: it and
    its twin go back at once. Then tap **Reset all**: the button should read
    "Tap again"; tap it. Every piece that moves at once is back; the window
    says which pieces wait for Apply. Tap **Apply**, Save. After the reload:
    is everything back where 0.17.0 had it? **Snapshot**.
21. Move one spell panel up again and Apply the map 10 to the left (so there
    is something saved), reload. Then switch **Arrange it yourself** Off and
    Save. After the reload: everything should be exactly at its built-in
    spot again, the map too. **Snapshot**. Switch it On and Save again: your
    two moves should be back. **Snapshot**. Leave it however you like.
22. Settings, Debug log tab: note the line count. Tab Errors: screenshot it.
    Tap **Save** (reload). Send `SavedVariables/PocketEssentials.lua` and
    `SavedVariables/<your character>/PocketEssentials.lua` with the
    screenshots.

What I most want to hear:
- Are the pieces the right ones, or do you want them split (the pet bar on
  its own) or more of them?
- Are steps of 2 and 10 right? Is the pull to the centre line (6) helpful or
  in the way?
- Is moving the outline first and the piece after a reload bearable for the
  map and chat?
- Is the window in the way?

Things to look at while you are there:
- **The map and the swing timers start 4 to the right of the centre line**
  (that is the built-in layout). So the very first tap **Left** on either
  jumps 4, not 2, and lands on the centre. That is the pull to the centre,
  not a fault. With **Map buttons** set to Shown, the centred map's
  place-name strip then reaches about 4 into the inner left spell panel and
  the overlap warning shows: say whether you would rather have the map
  centred or the strip clear.
- **The stance bar and the possess bar** (a warrior's or druid's stances, a
  mind-controlled creature) sit on the same anchor as the main bar, so they
  move with **Inner spell panel, left**, not with the spell wheels. If you
  have a character with stances, look where its stance pictures are after
  moving that panel.
- **A wheel that is open while you move the spell wheels piece stays where
  it opened** until you close it and open it again.
- If **Apply** ever says "NOT written", the window stays open and nothing
  changed in the game: screenshot it and the Errors tab.
- With **Part: spell pictures** Off the four spell panels are not in the
  list (nothing is drawn there); the window says so.

Things to watch for (known, not fixed):
- The yellow outline is the planned spot, not a measurement: the quest list
  and tooltip are drawn at a standard size.
- One tap is one step; holding does not repeat.
- The pieces that need Apply are shared by all your characters; the ones
  that move at once are per character.
- The spell wheels move only as a pair, and only up and down.

### 34. Version 0.19.0: the square map

Not yet tested on a device. Made while you were away, from the look you
picked on the mockup (the square, bigger map): say what you would change.
Same setup as before: Debug log On, Catch all errors on, Controller layout
on, and your own arrangement and Slim bars as you left them. **Mark** and
**Snapshot** are the same two buttons at the bottom of the Controller tab.
The marks go on counting from wherever you are; the numbers below assume the
first one here is 26. If yours differ, just say which numbers you saw.

**What this is.** One new row on the Controller tab, under Slim bars: **Map
look**, with **Round** (today's map) and **Square, bigger**. Square makes the
map square and bigger, with the place name, the clock and your coordinates
inside it, and no strip underneath.

Section 26, Round: nothing changed.

1. Install the build and log in. **Mark** (26). **Snapshot**. The row **Map
   look** should read **Round**. Is the screen exactly as 0.18.0 left it: the
   round map, the strip with the place name and clock under it, your pieces
   where you put them? Screenshot.

Section 27, Square.

2. **Mark** (27). Tap **Square, bigger**. Expected at once: the map turns
   square (still small), the strip under it goes, and the card asks for a
   reload. Screenshot this in-between look. Tap Save (it reloads).
3. After the reload: the map should be a square about as wide as two spell
   panels are tall, sitting at the bottom middle between the two inner spell
   panels, with a thin black edge and a small gap to the screen's bottom.
   **Snapshot**, and a screenshot standing outdoors. Look for:
   - Is the map really square, or round with a square edge around it?
   - Are the corners filled with ground, or empty?
   - Place name at the top middle, clock bottom right, coordinates bottom
     left: can you read all three? Is any of them cut off or missing?
   - Do the two inner spell panels, the LB and RB pictures and the "LB + LT"
     / "RB + RT" prompts sit clear of the map? Does anything touch it?
   - The swing timers (make one show, or set a timer row to Always): are
     they just over the map?
4. Look at the small pieces on the map: the sun or moon mark, the mail mark
   if you have mail, anything else. Where do they sit now? Screenshot. They
   were not moved in this version; say what you want done with each.
5. Track a quest with spots nearby (Quest icons on). Screenshot. Do icons
   show in the map's corners? Does a far hand-in spot sit on the square's
   edge, not on a circle inside it?
6. Walk into an inn or a building. Screenshot. Does the place name change
   to the building's? Is the map still square indoors?
7. Walk across a zone border and wait a minute. Do the place name, its
   colour and the clock keep up? Do the coordinates change as you walk?
8. A fight: pull something. Does the map stay square through the fight and
   after it? Any "Interface action failed" or a controller button that does
   nothing? Screenshot at once and say what you did just before.
9. Open both spell wheels (LB+LT, RB+RT) with the square map. Screenshot
   each. Do they open over the map or the timers? (They did over the round
   map too; say whether it is worse.)
10. Open the world map and close it again; open and close Edit Mode once
    (Escape, Edit Mode, then leave it without changing anything). Is the map
    still square, at the same low spot, the strip still gone? If the map
    jumps up for a moment and comes back, say so. **Snapshot**.
11. The row **Map buttons** should read "Map buttons: Round map only". Tap
    it: nothing should appear on the screen.

Section 28, back to Round.

12. **Mark** (28). Tap **Round**. Expected at once: the map is round again
    (still big, and sitting higher, until the reload), the strip is back, the
    words inside the map are gone. Screenshot. Tap Save (it reloads).
13. After the reload: is everything exactly as in step 1? **Snapshot**.
    Leave the row however you like.
14. Settings, Errors tab: screenshot it. Tap **Save** (reload). Send
    `SavedVariables/PocketEssentials.lua` and
    `SavedVariables/<your character>/PocketEssentials.lua` with the
    screenshots.

What I most want to hear:
- Is the size right, and the spot?
- Are the three texts the right ones, in the right corners, big enough?
- Which of the small pieces on the map should stay, move or go?
- Do you miss tapping the place name to open the world map?

Things to look at while you are there:
- **If the map stays round** after step 3 (bigger, with a black round
  border), the game did not take the square shape. The card then says "The
  square map is not possible on this game version". Screenshot it; that is
  the answer I need.
- **If the map sits about 50 higher than the bottom edge,** with an empty
  gap under it, the game did not let the addon lower it. Screenshot and
  **Snapshot**: the snapshot's lines "map's edge" and "round map" say by how
  much.
- **The coordinates:** with the game's own "coordinates on the minimap"
  option on, the text bottom left is the game's (plain, no outline); with it
  off, the addon's (outlined). If you see none at all, say which way your
  option is set.
- **The card says "With the square map ... pairs of pieces overlap"** only
  when pieces really overlap in the plan. With your saved arrangement it
  should not say it.

Things to watch for (known, not fixed):
- The day and night mark and the mail mark sit where the game puts them for
  a round map; the day and night mark may poke a little over the square's
  top right corner.
- The zoom buttons, if they show when you touch the map, sit inside the
  bottom right corner, near the clock.
- A tap on the place name (world map) and on the clock (the game's clock
  window) is not there with the square map.
- The spell wheels still open over the map and the timers.

### 35. Version 0.20.0: whole names, your arrangement built in, fewer rows

Not yet tested on a device. Made while you were away, from what you asked
for after the first sitting of 0.18.0. This build also has 0.19.0's square
map, so section 34 can be done in the same sitting, before or after this
one. Same setup as before: Debug log On, Catch all errors on, Controller
layout on. **Before you install it, do not change any row:** the first login
is the test. The marks go on counting; the numbers below assume the first
one here is 29.

**What should happen at the first login, by how your switches are set.**
Yours are Slim bars On and Arrange it yourself On, so the first line is the
one for you.

- **Arrange it yourself On (you):** nothing moves. Every piece is exactly
  where it was in 0.18.0 and 0.19.0. No reload is asked for and chat says
  nothing about the layout. In the Arrange window every piece you had moved
  reads "At its built-in spot", except the map ("Moved 2 down", as you left
  it).
- **Arrange it yourself Off:** the pieces go to your arrangement of
  2026-11-25. The spell panels, the LB and RB pictures and the slim bars at
  once; the buffs and debuffs 4 higher after one reload, which the card asks
  for (chat: "The controller layout has a new built-in arrangement").
- **Another character of yours, Arrange it yourself On:** its pieces stay
  where that character had them. If it was played with 0.18.0 or 0.19.0 and
  never moved anything, they stay at the old spots (not your arrangement);
  **Reset all** in the Arrange window then gives it your arrangement. A
  character not played since before 0.18.0 gets your arrangement at once.
- **Either way:** the split spell panels are there even if a "Part" row was
  left Off, and the spell wheels are where they were.

Section 29, the first login: does anything move?

1. Before installing, take a screenshot of the screen as it is now, standing
   still with a target picked.
2. Install the build and log in on the same character. **Mark** (29).
   **Snapshot**. Take the same screenshot. Did anything move, even a little?
   The spell panels, the LB and RB pictures, the two slim bars, the buffs
   top right? Did the card ask for a reload, or chat say anything about the
   layout? (It should not.)
3. Settings, Controller tab. Screenshot the rows. Gone: the seven "Part:
   ..." rows and "Arrange: spell wheels". New: **Names on the bars** under
   Slim bars.

Section 30, names.

4. **Mark** (30). Look at your own bar: does it read your whole name
   ("Forgot Shards")? Screenshot.
5. Target another player, then a creature, then a player with a long name if
   you can find one. Screenshot each. Whole names for players? Plain names
   for creatures? Is a long name cut with "..." before it reaches the health
   number? With a pet out, look at the pet bar and, with a target that
   targets you, the small bar over the target bar.
6. Tap **First name** on the row. The bars should change at once, no reload.
   Tap **Whole name** again. Screenshot both.
7. A fight: pull something. Do the names stay as they were through it? Any
   "Interface action failed" or a controller button that does nothing?
   Screenshot at once and say what you did just before.

Section 31, the Arrange window.

8. **Mark** (31). Open **Arrange the screen**. Step through the pieces with
   Next piece. Does each piece you had moved read "At its built-in spot"?
   (The map: "Moved 2 down".) Do all pairs read "Twins are an exact mirror"?
9. Find **Spell wheels and their buttons** in the list (the last piece). It
   should read "Up and down only. Both sides move together." Tap Up a few
   times: do both round buttons and both "LB + LT" / "RB + RT" prompts rise
   together, at once? Left and Right should do nothing.
10. Close the window. Open the left wheel (LB+LT) and the right one (RB+RT).
    Screenshot each. Do the wheels open around the buttons where they are
    now, or where the buttons were before? This is the part that has never
    been tried on a device.
11. Back in the Arrange window, pick the wheels and tap **Reset**. They
    should go back at once. Then pick the LB targeting picture, tap Up once,
    then **Reset**: it should return to where you had it, not to the old spot
    out by the prompts.
12. **Snapshot**.

Section 32, the square map with your arrangement (if you use it).

13. **Mark** (32). Set **Map look** to **Square, bigger** and reload when
    asked (or leave it if it already is). The card should **not** say "With
    the square map ... pairs of pieces overlap" any more. Do the LB and RB
    pictures sit just beside the square map, not on it? Screenshot.

Section 33, optional: the other way round.

14. Only if you are curious, and you can skip it. **Mark** (33). Switch
    **Arrange it yourself** Off and reload. The screen should look the same
    as with it On (your arrangement is the built-in one now), except the
    map, which goes back up by the 2 you had moved it, if that ever showed.
    Switch it On again and reload.
15. Settings, Errors tab: screenshot it. Tap **Save** (reload). Send
    `SavedVariables/PocketEssentials.lua` and
    `SavedVariables/<your character>/PocketEssentials.lua` with the
    screenshots.

What I most want to hear:
- Did anything move at the first login? If so, which piece and about how
  far.
- Are the names right: whole for you and other players, cut cleanly when
  long?
- Do the spell wheels open where their buttons are after you move them?

Things to look at while you are there:
- **If your bar still reads only "Forgot",** the game told the addon that
  second names are not surnames here. The debug log then has the line "a
  second name was not joined"; send the file and say so.
- **If a name shows a realm** (a server's name after a player's name), that
  is wrong: screenshot it.
- **A second character:** log in on one. Nothing of the layout should move
  there either, and no reload should be asked for.

Things to watch for (known, not fixed):
- At Spell panel size 110% and 120% your arrangement does not fit: the
  panels reach a little under the bottom edge and into the LB and RB
  pictures, and the card says "2 pairs of pieces overlap". 100% and smaller
  fit.
- If the spell pictures are ever off (the card says why), the game's own
  bars show at full size and the upper one on each side touches the LB or RB
  picture.
- Buffs and debuffs on the target are still not shown with Slim bars On.
