# Testing

This file holds the offline tests and the device test plan, steps 0 to 9. Goals live in PRD.md.

## Offline tests

These run on a computer, with no game. Their job is to catch plain mistakes
(a typo, a game function that does not exist, a rule that stopped holding)
before you spend time carrying a build to the handheld. They cannot tell you
how anything looks or feels, and they do not replace the device test below.

Nothing under `tests/` or `scripts/` goes into the addon. `scripts/build.sh`
copies only `addons/PocketEssentials` and QuestieDB into the zips.

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
   repair, chat, core, bags, layout, quest arrow, quest icons). Each states
   the feature's rules in plain terms ("never sells a non-grey item", "does
   nothing in combat", "off means nothing ticks") and checks them in a
   stand-in game client.
5. **Smoke test** (`tests/smoke/`). Loads every file in the addon's TOC in the
   stand-in client, the way the game would, presses every option on and off,
   checks the arrow, and fails on any error raised along the way.

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

## Device test plan

Rules 1 and 2 in PRD.md apply: **one step at a time, report back, then the next
step.** For every step, "report back" means: did it do what is described,
anything odd, and what the Errors page shows (round button → Errors).

Install first: delete any old `QuestDots` folder from AddOns, then extract
`dist/wow-forever-pocket-essentials.zip` into AddOns so `PocketEssentials`
and `QuestieDB` sit side by side.

### 0. Baseline — every feature off (do nothing in the settings yet)
- Log in. **Does any error box appear?**
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
- 0.0.6: at the bottom of the main page, tap **Icon key**: a page opens with
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
- Switch on **One big bag**. If a "Reload now" bar appears, tap it.
- Open your bags: one combined window, with a big **Sort** button just
  outside it. Tap Sort: items should tidy up.
- With the bag open, press L3 (click the left stick): it should sort. Close
  the bag: L3 should do its normal job again (auto-run).
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

### 6. Repair
- With damaged gear, switch on **Repair automatically** and open a vendor
  that repairs. Expect "Repairing for …" and yellow/red gear fixed.
- Report: repaired yes/no; cost line matches money spent; any popup.

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

### 8. Layout (experimental)
- Switch on **Layout helper**. Read the status under the row: it names the
  layout in use and says "No handheld layout saved yet".
- With "Enable Gamepad UI" on in the game's settings, tap "Use Blizzard's
  Gamepad layout", then "Reload now". The screen should rearrange to
  Blizzard's gamepad arrangement. "Go back to my previous layout" (then
  reload) should undo it.
- Report: did it switch; did Go back work; any blocked message afterwards in
  combat; whether the game had already switched layouts by itself when the
  Gamepad UI was turned on (in which case this button adds little).

### 9. After all of the above
- Flip the default to on for each feature that passed.
- **Export a handheld layout** so it can be bundled: open Edit Mode in the
  control style you play in, arrange and Save under a name, open the Layout
  drop-down, choose Share → Copy To Clipboard, paste the long line into a
  note outside the game and send it. (Button names are from the retail game
  and may differ slightly; whether Android receives the game's clipboard is
  untested.) It goes into `Layout.lua` at `BUNDLED_LAYOUT`.
- Decide which of QuestieDB's two identical data files the client loads and
  drop the other (`QUESTIEDB_TOC=Forever scripts/build.sh` or `Camelot`
  builds with one), halving the zip.
