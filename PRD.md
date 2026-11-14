# WoW Forever Pocket Essentials — Product Requirements

Read this whole file before doing anything in this repo. It is the source of
truth for what is being built and why. If something here turns out to be wrong,
fix this file in the same change.

## How to work in this repo

These rules come from the owner and override your defaults.

1. **Go slowly, one item at a time.** Pick the single next item from
   "Roadmap", agree on it with the owner, and finish it before starting
   another. Do not build ahead.
2. **Nothing counts as working until it has run on the device.** The owner is
   the only one who can test in game. After each change that affects the game,
   stop, hand over a zip, say exactly what to look for, and wait for the result.
3. **Use existing addons first.** Write new addon code only when no existing
   addon fits or loads on this client, and say so before writing it.
4. **Ask before adding scope.** Do not add features, addons, settings or
   scripts the owner did not ask for. Propose them instead.
5. **Explain in plain language.** The owner is a player, not an addon
   developer. Lead with what changes for them in game.
6. **Keep this file current.** Update "Current state" and "Facts" whenever
   something is tested, decided or disproved.

**Rules 1 and 2 were suspended once, for the build session of 2026-11-13/14
only.** The owner asked for version 1 to be built end to end while they were
away, with the plan to test on the device afterwards by switching features on
one at a time and fixing what breaks. That session is over. Rules 1 and 2 are
back in force: from here on, work through the device test plan in "Roadmap"
one step at a time.

## What this is

A small bundle of lightweight addons for playing **WoW Forever** on a handheld,
delivered as one zip the owner downloads on the device and extracts into the
game's AddOns folder.

The owner plays on desktop with a full addon setup and has none of it on the
handheld. The goal is to bring over the few comforts that matter most, sized
and shaped for a small touch screen and a controller, without slowing the game
down.

## The setup

| | |
|---|---|
| Device | Retroid Pocket 6, 12 GB RAM, Android |
| How the game runs | Through Droid Deck (the Windows arm64 client on Android), 720p today, may move to 1080p |
| Game client | WoW Forever 1.60.1 (70938), arm64. Addon interface `16001`. English client |
| Input | Blizzard's built-in gamepad support, working out of the box. Touch screen for everything else. The on-screen keyboard is opened by the owner with a three-finger tap or a bound controller button; an addon cannot open it |
| Owner's faction | Horde |
| Install method | Download the zip on the device, pull it into the AddOns folder through Droid Deck |

WoW Forever runs Classic-era content on the modern (retail-style) addon API.
Addons written for Classic Era 1.x generally do not load; target interface
`16001` and the modern API (`C_QuestLog`, `C_Map`, `C_AddOns` and so on).
The client's internal game name is "Camelot".

## Goals, in priority order

### 1. Questing
- Icons on the world map and minimap showing where each quest objective is
  (kill, loot, interact, turn in). Blizzard's blue "haze" areas are not direct
  enough and should be hidden.
- An arrow that points toward the current objective.

### 2. Bags
- One combined bag window instead of separate bags.
- A way to sort it.
- Not needed: bank view, other characters' bags.

### 3. Vendor chores
- Automatically sell junk (grey items) when visiting a vendor.
- Optional automatic repair.
- Not needed: anything else Leatrix Plus does (camera, misc automation).

### 4. Chat
The owner currently avoids chatting because targets are too small to tap.
- A large icon that sits permanently on screen.
- Tapping it opens a panel of big buttons: one per channel the character can
  currently talk in (Say, Party, Guild, General, Trade and so on), plus
  private messages.
- Private messages show as a short list of big name buttons, most recent
  whisperer first.
- Tapping a channel or name opens the chat box already set to that target.
- The icon indicates when there is an unanswered whisper.

### 5. UI layout
- Some way to arrange the interface that does not depend on fiddly touch
  dragging.

### 6. Settings panel
- One touch-friendly place in game where each feature of the bundle can be
  turned on or off, with big targets and no typed commands.

## Non-goals

- Matching the desktop addon setup feature for feature.
- Combat addons (damage meters, boss timers). The client does not support
  combat-log addons anyway.
- Replacing or fighting Blizzard's gamepad support (no ConsolePort unless the
  owner asks).

## What would make this a failure

- A noticeable drop in frame rate or longer load times compared with no addons.
- Anything that needs precise tapping, small targets or typed slash commands
  for everyday use.
- A bundle that needs manual steps beyond "extract the zip into AddOns".

## Deliverable

- One zip, with each addon's folder at the zip root: `PocketEssentials` and
  `QuestieDB`.
- Built by `scripts/build.sh` so it is repeatable.
- **Later, not now:** separate Horde and Alliance builds with the other
  faction's quest data removed. Parked until the bundle works.

## Current state

**Nothing in this repo has run in the game.** Version 1 was written on a Mac
with no game client. Every line was checked against Blizzard's published
interface code for this exact build, syntax-checked, exercised against a
home-made stand-in for the game, and read by a second independent reviewer.
None of that proves it works on the device. Treat every feature as unproven
until its step in the test plan passes.

| Piece | What exists | Status |
|---|---|---|
| Pocket Essentials addon (`addons/PocketEssentials`) | One addon holding everything below. Every feature is **off** on first install | Untested in game |
| Settings window | Own window with one row per feature and a big on/off switch each; big buttons for each feature's choices; an Errors page; works by touch and (if the game allows it) by d-pad / A / B. Opens from the round button, the game's addon list button on the minimap, or `/pe` | Untested |
| Round "PE" button | Always on screen, left edge by default, position chosen from six preset spots. Opens settings; opens the chat picker instead when the chat feature is on. Holding it for half a second always opens settings | Untested |
| Quest icons | Objective icons on map and minimap from QuestieDB data, blue haze hidden, tap an icon to pick that quest | Untested |
| Quest arrow | On-screen arrow to the nearest objective in the current zone, with distance and quest name | Untested |
| One big bag | Blizzard's own combined bag, a big Sort button, L3 sorts while the bag is open, three bag sizes | Untested |
| Sell junk automatically | Sells grey items at vendors, at most 12 per visit | Untested |
| Repair automatically | Repairs from your own money at vendors that can | Untested |
| Big chat buttons | Picker with one big button per channel plus the last six whisperers; badge on the round button for unanswered whispers | Untested |
| Layout helper (experimental) | One-tap switch to Blizzard's Gamepad layout and back; a dormant path to install a ready-made handheld layout. **No nudge arrows** (see below) | Untested |
| QuestieDB | Official Questie data addon, Forever build 1.1.0, shipped unmodified. Only the two quest features need it | Untested |
| `scripts/build.sh` | Downloads QuestieDB (pinned checksum), checks the addon's file list, writes `dist/wow-forever-pocket-essentials.zip` | Runs on the Mac |

Defaults: every feature is off so the owner can switch them on one at a time.
**Once a feature has passed its device test, its default flips to on** (one
line per feature in its Lua file's registration; today all default to off
because nothing is saved as on).

### What was left out, and why

- **Edit Mode nudge helper: not shipped, and why.** We wanted big on-screen
  arrows and plus/minus buttons to move and resize the selected item while
  Edit Mode is open. We did not build it, because it cannot be done safely.
  The only way an addon can move the selected item is to call the game's own
  internal Edit Mode functions. When an addon does that, the game marks the
  positions of the action bars and unit frames as "touched by an addon", and
  later, in combat, it can refuse to update them and show "interface action
  blocked" errors until the interface is reloaded. Addons also cannot press
  keyboard keys for you, so we cannot trigger the game's own arrow-key nudge,
  and this version of the game has no controller nudging inside Edit Mode.
  The alternative of rewriting the saved layout on every tap would throw away
  unsaved Edit Mode changes and has the same risk. So the Layout helper only
  offers one-tap switching between whole layouts, and asks for a quick reload
  after each switch to stay clean. For fine adjustment, use Edit Mode's own
  Grid and Snap tick boxes. If a keyboard with arrow keys is available (or
  the d-pad can be mapped to arrow keys outside the game), the game's own
  nudge works: tap an item, then arrows move it 1 step and Shift+arrows 10.
- **A ready-made handheld layout.** The code to install one exists, but no
  layout is bundled: the owner has to arrange the screen on the device and
  export it first (steps under "Roadmap", step 9). Until then the panel says
  "No handheld layout saved yet".
- **Arrow across zones.** The arrow only points at objectives in the zone you
  are in. If the quest you picked is elsewhere it says "Not in this zone"
  rather than guessing a direction. Pointing across zone borders was written,
  then removed after review because it could show a confidently wrong arrow.
- **Battle.net whispers** in the chat picker. Only ordinary character
  whispers are listed. Battle.net could not be checked on this client.
- **"Hide Blizzard's numbered quest pins"** (an option in the old QuestDots).
  Removed: the game's controller map cursor would still react to the hidden
  pins.
- **Improved Forever** (another addon bundle). Considered and dropped: too
  heavy and not verifiable for this build. **Revisit later**: the owner liked
  its radial wheels and its L3 bag sort (the L3 sort idea is in our bags
  feature already).
- Full Questie, TomTom, Bagnon, BetterBags and ForeverLazy were also
  considered and rejected (too heavy, unverifiable build, or no licence).
  The only third-party addon in the bundle is QuestieDB.

## Structure

One addon folder, one Lua file per part, no libraries.

```
addons/PocketEssentials/
  PocketEssentials.toc   interface 16001, one saved table PocketEssentialsDB, QuestieDB as optional dependency
  Core.lua        feature registry, saved settings, error catching and log, combat queue, /pe
  UI.lua          sizes for touch, big buttons, windows, controller navigation
  Hub.lua         the round button and the minimap addon-list entry
  Settings.lua    the settings window and Errors page
  QuestData.lua   reads QuestieDB + the quest log into objective locations (shared, no switch of its own)
  QuestIcons.lua  feature: quest icons        (also keeps /qd working)
  QuestArrow.lua  feature: quest arrow
  Bags.lua        feature: one big bag
  Vendor.lua      features: sell junk, repair (two switches)
  Chat.lua        feature: big chat buttons
  Layout.lua      feature: layout helper (experimental)
  Icons/          three icon images from pfQuest/Shagu with their MIT notice
```

How the pieces protect each other:
- Each feature registers itself with the core and is switched on and off by
  it. Loading, switching on, and every reaction to a game event run inside a
  safety net, so one feature failing cannot stop another or the settings
  window. Caught failures go to the Errors page (kept between sessions, at
  most 30).
- Nothing runs every frame while its feature is off. Only two things ever
  tick: the minimap icons (10 times a second, only while moving) and the
  arrow (10 times a second, only while it has something to point at).
- Sizes are defined as pixels on a 720p screen and converted, so buttons stay
  the same physical size at 1080p. "Button size: Small / Medium / Large" in
  settings re-tunes everything without typing.
- If QuestieDB is missing or did not load, only the two quest features stay
  off and their rows say why.
- The old standalone `QuestDots` addon was folded in and its folder deleted.
  If an old `QuestDots` folder is still in AddOns on the device, the settings
  window says so and quest icons stay off until it is deleted.

## Unverified API

Everything the code calls was looked up in Blizzard's interface source for
build 1.60.1.70938 (`github.com/Gethe/wow-ui-source`, branch `forever`).
These are the things that could **not** be confirmed there. Each is guarded
so that being wrong cannot raise an error; the worst case is listed.

| What | Used by | If it is wrong |
|---|---|---|
| Which of two "priority" key overrides wins (ours on the panel vs Blizzard's gamepad ones) | Controller navigation in our windows; L3 sort | D-pad / A / B do nothing in our windows, or L3 keeps its normal job. Touch still works |
| Custom click names passed through override bindings | Controller navigation | Same as above |
| `GetPlayerFacing` direction convention (0 = north, counter-clockwise) | Quest arrow, rotating minimap | Arrow turns the wrong way. One marked line in `QuestArrow.lua` flips it |
| Minimap yards-per-zoom table (taken from the HereBeDragons library's values) and six zoom levels | Minimap icons | Icons drift toward or away from the centre as you walk |
| `IsIndoors()` as the indoor/outdoor minimap switch | Minimap icons | Same drift, indoors only |
| Default values of the minimap's quest-area ("haze") transparency (set inside the game engine) | Quest icons | Bringing the minimap haze back needs a reload; the panel asks for one |
| Hiding the world-map haze by making its frame transparent | Quest icons | Haze stays visible on the world map. An alternative is noted in the file |
| `C_EncodingUtil` decode functions behave as QuestieDB expects; which of QuestieDB's two identical data files the client loads | QuestieDB itself | QuestieDB fails to load; quest features stay off and say why |
| `CanMerchantRepair`, `GetRepairAllCost`, `RepairAllItems`, `InRepairMode`, `SpellIsTargeting` (used by Blizzard's own vendor code but absent from the generated documentation, so their restrictions are unknown) | Repair, sell junk | Repair row shows "PROBLEM", or the game shows its own "blocked" message once |
| Whether selling (`C_Container.UseContainerItem`) or repairing needs a real button press on this client | Sell junk, repair | The game shows a "blocked by an addon" message at the vendor and nothing is sold/repaired |
| Whether a setting written at logout sticks (`combinedBags`) | Bags, only when the Gamepad UI is off | Bag does not combine; the row says to use the game's own bag menu |
| `GetChannelList`, `IsInGroup`, `IsInRaid` (source use only) | Chat | A channel button missing from the picker |
| Whether values set on the chat box by an addon stay "clean" for the game's secure commands | Chat | A typed `/cast` or `/target` right after using the picker is refused |
| Whether `C_EditMode.SetActiveLayout` / `OnLayoutAdded` called by an addon "taints" Edit Mode | Layout | Possible "action blocked" in combat until reload; the panel asks for a reload after every switch for this reason |
| `Enum.EditModePresetLayoutsMeta.NumValues`; English text of the "Enable Gamepad UI" setting | Layout | A status line reads slightly differently |
| `debugstack` argument form; whether `C_UI.Reload` needs a real press (it is only ever called from one) | Core | Shorter error details |

Syntax check: all eleven Lua files parse as Lua 5.1 (checked with the
`luaparse` JavaScript parser, because no `luac` or `luacheck` is installed on
the build Mac). Each file was also run against a home-made imitation of the
game's API to catch plain coding mistakes. That imitation only knows what its
authors believed about the game.

## Decisions made without the owner

Made during the unattended build of 2026-11-13/14. Each took the lighter or
safer option. Any of them can be reversed.

**General**
- Sizes are tied to a 720p-tall screen and converted, rather than fixed, so
  1080p needs no retuning. Presets: Small = 56 px rows / 48 px buttons (the
  stated minimum), Medium (default) = 66 / 56, Large = 80 / 68.
- A feature's extra choices only show while that feature is on, to keep the
  list short.
- Settings rows live in a list paged with two big Up/Down buttons (there is
  no mouse wheel on the device); the d-pad also scrolls it.
- Holding the round button for half a second always opens settings, so a
  problem in the chat picker can never lock the owner out.
- Controller navigation arms once when a window opens and never fights
  Blizzard's gamepad UI. If a Blizzard popup takes the d-pad while our window
  is open, close and reopen ours to get it back.
- Errors are logged quietly with one chat line per feature per session,
  instead of the game's error popup.
- `/pe reset` puts the round button and button size back to default.
- No round artwork could be verified, so the round button is drawn from
  plain coloured strips with the letters "PE". It may look slightly stepped.

**Quest icons / data**
- Icon sizes: Small / Medium / Large = 22 / 28 / 36 px on the map, 14 / 18 /
  22 on the minimap. They are deliberately below the 48 px touch rule,
  because 48 px icons would bury the map; on the world map the tap area is
  exactly the icon.
- Tapping an icon picks that quest and shows a short text box (hover tooltips
  do not exist on a touch screen). It hides after 5 seconds.
- At most 150 icons on the world map and 40 on the minimap at once; at most
  300 places per objective (thinned evenly). Items that drop from more than
  60 kinds of creature (cloth, potions) show no icons.
- Dungeon objectives show an icon on the dungeon entrance.
- "Talk to" objectives are labelled "Explore" (there is no separate label).
- "The quest you picked" means only a quest tapped on one of our icons. It
  does not follow Blizzard's own quest tracker.
- "Hide Blizzard's quest pins" was removed (see "left out").
- `/qd` still works for map, mini, haze, size and cluster.

**Quest arrow**
- Current zone only; "Not in this zone" for a picked quest elsewhere.
- Drawn from thick lines rather than a picture, so no artwork can be missing.
- Five preset positions (Top, Upper middle, Lower middle, Left, Right), two
  sizes. It sits behind all windows and never takes taps.
- The arrow is relative to the way the character faces, not the camera.

**Bags**
- The combined-bag setting is never changed mid-session. With the Gamepad UI
  on, the game already forces the combined bag, so nothing is changed at all.
  With it off, the change is written at logout/reload and the panel shows
  "Reload now". Changing it live would make the game re-open bags inside our
  code, which risks "action blocked" when using items.
- The Sort button floats beside the bag rather than inside it, so Blizzard's
  controller cursor does not treat it as an item slot.
- L3 sorts only while the bag is open and never during combat.
- Bag size never goes below the game's own size; "Extra large" may equal
  "Large" when the bag is already as tall as the screen.
- If the owner switches back to separate bags in the game's own menu, the
  feature respects that.

**Vendor**
- The 12-item cap is per visit and counts attempts.
- The chat line reports the money gained during the visit, e.g. "Sold 7 junk
  items for 1g 20s 5c." and "Repairing for 12s 40c."
- An item must be grey according to both the bag slot and the item database,
  have a price, and not be locked. Bags the owner marked "ignore for junk" in
  Blizzard's bag menu are skipped.
- Selling pauses in combat and stops if a trade window or spell-target
  cursor is up. Nothing is ever auto-confirmed.
- If the character cannot afford the repair it says so once and does not
  retry that visit.

**Chat**
- A "Clear marks" button was added so the unanswered badge cannot get stuck
  on spam or on whispers answered inside a dungeon (where the game hides
  whisper details from addons).
- Instance and Officer chat are not in the picker. Party shows when grouped,
  Raid when in a raid.
- Six whisperers are remembered; a seventh pushes out the oldest.
- A whisper arriving while the picker is open updates the badge only; the
  list redraws next time it opens, so a button never changes under a finger.
- The chat box is opened by setting its target directly rather than by
  typing a slash command into it, which writes less into the game's chat
  code.

**Layout**
- No nudge helper (see "left out").
- The Gamepad layout button refuses unless "Enable Gamepad UI" is on,
  because that layout hides the normal action bars otherwise.
- Every layout switch asks for a reload afterwards.
- Installing over an existing "Handheld" layout needs a second tap within
  20 seconds.

## Roadmap — device test plan

Rules 1 and 2 apply again: **one step at a time, report back, then the next
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
- Report: which of the three ways to open worked; is everything big enough;
  does text fit; does the d-pad move the outline at all (if not, touch-only
  is the fallback and we note it); do the buttons return to normal after
  closing.

### 2. Quest icons
- Switch on **Quest icons** only. Have a few quests in the log.
- Open the world map in a zone with quest objectives: coloured icons (red
  kill, yellow loot, blue use, purple explore, "?" turn in) should sit where
  the objectives are, and the blue haze should be gone. Zoom the map in and
  out: icons should stay on their spots and stay the same size.
- Look at the minimap while walking toward an objective: the icon should
  move toward the centre steadily as you approach.
- Tap an icon on the map: a text box names the quest and objective.
- Finish an objective: its icons should disappear within a second or two.
- Try the choices under the row (icon size, minimap on/off, haze on/off).
- Report: do icons appear at all; are they in believable places; does the
  haze vanish on map and minimap; do minimap icons drift oddly; can you
  still drag the map by touch; any "action blocked" message; frame rate with
  the map open.

### 3. Quest arrow
- Leave Quest icons on and switch on **Quest arrow**.
- Stand in a zone with an objective. An arrow with a distance and quest name
  should appear at the top of the screen.
- **Direction check:** face north (use the minimap) with an objective to
  your north: the arrow should point up. Turn right: the arrow should swing
  left. If it swings the same way you turn, tell us; it is a one-line fix.
- Walk to the objective: distance should count down to "Here".
- Tap a different quest's icon on the map: the arrow should switch to it.
  Pick a quest in another zone: it should say "Not in this zone".
- Enter a dungeon: the arrow should hide while you are inside.
- Then switch Quest icons off and confirm the arrow still works alone.
- Report: direction right/mirrored; distance sensible; position choices that
  collide with something on your screen; any stutter while moving.

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
  "Sold N junk items for …". Check the buyback tab holds them.
- With more than 12 greys: exactly 12 sell and the line ends with "(more
  left - reopen the vendor)".
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
- Revisit Improved Forever's radial wheels if still wanted.
- Faction-specific builds (parked).

## Facts

### Verified (from source files or official releases, not in game)
- Addon interface number is `16001`. TOC suffixes `_Forever` / `_Camelot`
  exist.
- The client has its own gamepad interface (`Blizzard_Gamepad`,
  `Blizzard_GamepadSmartNavigation`, an "Enable Gamepad UI" setting, a
  radial menu, and a built-in "Gamepad" Edit Mode preset, third after Modern
  and Classic). Its window navigation binds the d-pad and face buttons
  itself whenever a Blizzard window has focus. It has no controller nudging
  inside Edit Mode.
- Gamepad key names: `PADDUP/DOWN/LEFT/RIGHT`, `PAD1` (bottom face button),
  `PAD2` (right face button), `PADLSTICK` (L3, auto-run by default).
- The Addon Compartment (addon list button) exists on this client.
- Bags: `ContainerFrameCombinedBags`, CVar `combinedBags`,
  `C_Container.SortBags` exist. With the Gamepad UI on, the game forces the
  combined bag, hides its sort button and puts "Clean Up Bags" in the
  backpack menu. `UpdateContainerFrameAnchors` resets bag scale on every
  layout pass. Neither the bag frame nor its item buttons are protected.
- Vendor: `MerchantSellAllJunkButton` exists, shown only when
  `C_MerchantFrame.IsSellAllJunkEnabled()` is true. No built-in auto-repair.
  Guild-bank repair exists; we never use it.
- Chat: whisper events are hidden from addons during "chat messaging
  lockdown" (dungeons, raids, PvP matches); `C_ChatInfo.InChatMessagingLockdown()`
  reports it.
- Edit Mode: `C_EditMode.GetLayouts`, `SaveLayouts`, `SetActiveLayout`,
  `OnLayoutAdded`, `ConvertStringToLayoutInfo` exist with no protected flag.
  Layouts carry an `interfaceStyle`; a layout of the other style cannot be
  chosen. Five saved layouts per type at most.
- QuestieDB has an official Forever build:
  <https://github.com/Questie/QuestieDB/releases>. Version 1.1.0 is pinned in
  `scripts/build.sh` with a checksum. It is data only (no icons), includes
  nine translations chosen by client language, and stores its data inside
  its `.toc` files, so its folder must be named exactly `QuestieDB`.
- QuestieDB 1.1.0 is 36 MB unpacked. 34 MB of that is one 18 MB data file
  shipped twice under two names, `QuestieDB_Forever.toc` and
  `QuestieDB_Camelot.toc`, byte-identical. The game loads only one.
- QuestieDB 1.1.0 provides interface ("contract") version 4; our code asks
  for 4. All 5,893 quests in it were run through our quest-data code off the
  device without an error. About 980 of them have no location data and will
  show no icons.
- QuestieDB's licence: the Questie team permits copying under GPL-3.0 terms
  but cannot speak for all past contributors. This repo ships their release
  unmodified with licence files intact. Re-read `LICENSE.md` inside the
  release before distributing a modified (trimmed) copy.
- The three objective icon images come from pfQuest (Shagu), MIT licence;
  the notice is in `addons/PocketEssentials/Icons/MIT.txt`.

### Unverified (do not rely on these without testing)
- Everything under "Unverified API" above.
- Whether any of version 1 works on the device.
- Which of the two QuestieDB data files the client loads.
- Whether quests under a collapsed header in the quest log are still seen
  (if not, their icons vanish while collapsed).
- How long QuestieDB takes to load on the handheld.
- How much faction trimming would save. Not measured.

## Repo layout

- `PRD.md` — this file
- `README.md` — short install notes
- `addons/PocketEssentials/` — the addon, exactly as it should land in AddOns
- `scripts/build.sh` — builds the zip
- `vendor/` — downloaded third-party releases (not committed)
- `dist/` — build output (not committed)
