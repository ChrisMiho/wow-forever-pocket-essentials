# WoW Forever Pocket Essentials — Product Requirements

Read this whole file before doing anything in this repo. It is the product spec
and the source of truth for what is being built and why. Detail lives in
`docs/`. If something here turns out to be wrong, fix this file in the same
change.

## How to work in this repo

These rules come from the owner (the maintainer) and override your defaults.

1. **Go slowly, one item at a time.** Pick the single next item from
   the current "Roadmap" phase, agree on it with the owner, and finish it before starting
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
6. **Keep this file current.** Update "Status" and the "Facts" in
   `docs/ARCHITECTURE.md` whenever something is tested, decided or disproved.
7. **Spec-driven:** new features start as a spec in `docs/superpowers/specs/`,
   approved by the owner, before any plan or code. Then a plan in
   `docs/superpowers/plans/`, a subagent-driven build reviewed against the
   spec, and the owner's device test.

## Vision

Make WoW Forever comfortable to play on any handheld, with touch and a
controller together. Keep it light on performance, and never ask for precise
taps or typed commands. Performance and user experience come before new
features.

## Who it's for

Anyone playing WoW Forever on a handheld, on any device that runs the client.

Dev note: the reference test device is a Retroid Pocket 6 (12 GB, Droid Deck,
720p).

## Reference setup

| | |
|---|---|
| Device | Retroid Pocket 6, 12 GB RAM, Android |
| How the game runs | Through Droid Deck (the Windows arm64 client on Android), 720p today, may move to 1080p |
| Game client | WoW Forever 1.60.1 (70938), arm64. Addon interface `16001`. English client |
| Input | Blizzard's built-in gamepad support, working out of the box. Touch screen for everything else. The on-screen keyboard is opened with a three-finger tap or a bound controller button; an addon cannot open it |
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
Chatting is hard on a handheld because targets are too small to tap.
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
- Replacing or fighting Blizzard's gamepad support (no ConsolePort unless a
  player asks).
- An entry on Forever's radial wheel (dropped 2026-11-15: the game gives
  addons no safe way to add one; see `docs/DECISIONS.md`).
- Icons for quests not yet picked up (dropped 2026-11-15: the addon stays
  focused on quests you have accepted).
- Switching the game's Edit Mode layouts, and a bundled handheld layout
  (dropped 2026-11-17 with the Layout helper, 0.3.0: never tested, the game
  switches to its Gamepad layout by itself, and "Move things" places our own
  pieces).

## What would make this a failure

- A noticeable drop in frame rate or longer load times compared with no addons.
- Anything that needs precise tapping, small targets or typed slash commands
  for everyday use.
- A bundle that needs manual steps beyond "extract the zip into AddOns".

## Deliverable

- One zip, with each addon's folder at the zip root: `PocketEssentials` and
  `QuestieDB`.
- Built by `scripts/build.sh` so it is repeatable.
- Versioning: semantic versioning (MAJOR.MINOR.PATCH), starting at 0.0.1.
  The version lives in `PocketEssentials.toc` and `CHANGELOG.md` and must match.
- CurseForge: PocketEssentials alone, QuestieDB as a required dependency
  (project 1696795). GitHub zip: both folders, QuestieDB pinned at 1.1.1.

## Status

Offline test suite (2026-11-15): the API audit found all 236 game names the addon uses in Blizzard's source for this build (169 documented, 67 seen only in Blizzard's own code, whose restrictions are unknown), and the rule tests and smoke test pass offline; no addon bug has been found by them so far. None of this proves behaviour in the game; see `docs/TESTING.md`.

In progress: device testing. Version 0.0.3 (test build) carries the fixes from
the first device test of 0.0.1 (in 0.0.2) and the maintainer's follow-up on
the arrow and icon defaults (spec `docs/superpowers/specs/2026-11-15-arrow-messages.md`).
Version 0.0.4 (test build) carries fixes 3 and 6 from the second device test
(spec `docs/superpowers/specs/2026-11-15-green-minimap-and-arrow-text.md`).
**Third device test, 2026-11-15 (0.0.4):** no green minimap, no haze, and the
arrow text wraps. Asked for: a wider text line (only one short word wrapped)
and text-only messages shown higher, where the arrow normally is. Both are in
0.0.5.
Version 0.0.6 (test build) carries three items: at most N icons per quest
objective ("Spots per objective", default 5; the arrow's spot always keeps
its icon), an "Icon key" page in the settings, and a "Reload UI" button in
the settings (spec
`docs/superpowers/specs/2026-11-15-fewer-spots-icon-key-reload.md`). It ships
with 0.0.5's two changes. All of it is awaiting device test.

**First device test, 2026-11-15 (0.0.1, Retroid Pocket 6), quest icons and
arrow:** no errors, the settings menu is easy to use. Found: the round button
looked pixelated; the arrow had no real point; the arrow could not be made to
point at the wanted quest (tapping icons to pick was awkward); far too many
icons on the world map, and the minimap was busy; the blue haze stayed on the
minimap. All five are addressed in 0.0.2 (spec:
`docs/superpowers/specs/2026-11-15-quest-focus-and-polish.md`), not yet
tested in game.

**Second device test, 2026-11-15 (0.0.3), quest icons and arrow:** the new
arrow, the round button art and the settings menu all good; focusing a quest
in the quest log works; untracking quests thins the world map. Found:
1. Blue icons on the minimap only (not the world map); hovering shows text
   about mobs and quests. Probably Blizzard's, not ours (our icons have no
   hover text). Unconfirmed.
2. One quest with many pick-up spots floods the world map, even with the
   clutter settings turned up.
3. The minimap turns green when a quest is focused. Confirmed by the owner:
   it happens only with "Hide blue haze" on; switched off plus a reload, the
   minimap stays normal. The cause was our blank texture swap on the minimap's
   quest areas. Fixed in 0.0.4 (swap removed), confirmed on the device.
4. Inside the quest log, the menu that opens on a quest is hard to read. The
   owner sent a screenshot (2026-11-15): the menu (Track Quest, Focus, Share
   Quest, Share in Chat, Abandon Quest) works but is drawn with no background,
   so its text sits on top of the quest list. It is Blizzard's own pop-up menu
   in its controller style (the "A Select / B Close" bar is Blizzard's).
   Nothing in this addon draws, hooks or changes the quest log or that menu
   (our only world-map hooks redraw our own icons), so it is probably a gap in
   the default UI. To confirm: switch Pocket Essentials off in the addon list,
   reload, open the menu again.
   **Confirmed 2026-11-15:** still broken with every addon switched off, so
   it is the default UI's problem, not ours. 0.4.0 adds "Menu background", a
   switch that puts our own dark panel behind the menu (untested).
5. Untracking quests was found by guessing.
6. The arrow's "Focus one in your quest log" line is cut off with "...": the
   line under the arrow is a single line of fixed width (`QuestArrow.lua`
   `Layout`, 13 times the font size), and the text is longer than that.
   Fixed in 0.0.4 (the line now wraps to two lines), confirmed on the device.
Follow-up: with "Hide blue haze" switched off and a reload, focusing a quest
left the minimap normal; switched back on, focusing a different quest turned
it green again (so the green was ours, finding 3).
Requests: an icon key (built in 0.0.6); opening the settings from Forever's
radial wheel so the round button is not needed (dropped 2026-11-15, findings
in `docs/DECISIONS.md`).

**Fourth device test, 2026-11-15 (0.0.6), bags, chat, sell junk, repair:**
screenshots in `docs/screenshots/`.
1. One big bag: Sort works and the bag looked good. The game's controller
   style already shows one combined bag, so this feature only adds the Sort
   button, the left-stick sort and the size choice. Request: the combined
   bag scatters items and empty slots by the bag they sit in; the owner wants
   one plain box with every item packed at the top. Not built; Blizzard's
   window lays out its own slots, so this would need a bag window of our own
   (a new roadmap item, spec first).
2. Big chat buttons: the window opens and works but is a little too big.
   After tapping buttons in it, the chat showed "Interface action failed
   because of an AddOn" (the game blocked something). Which action is not
   yet known.
3. Sell junk and repair: at the innkeeper the game showed "PocketEssentials
   has been blocked from an action only available to the Blizzard UI"
   (Disable / Ignore), and the owner could not clear it. Likely cause, not
   confirmed: the game forbids addon selling (`C_Container.UseContainerItem`)
   and the sell loop retries every 0.2 seconds, bringing the warning back
   each time. The blocked action's name is passed only to addons
   (`ADDON_ACTION_FORBIDDEN` / `ADDON_ACTION_BLOCKED`), so the next step is
   to print it in chat and retest each feature on its own.

**Apart from the quest tests, nothing in this repo has run in the game.**
Version 0.0.1 was written on a Mac with no game client. Every line was checked against Blizzard's published
interface code for this exact build, syntax-checked, exercised against a
home-made stand-in for the game, and read by a second independent reviewer.
None of that proves it works on the device. Treat every feature as unproven
until its step in the test plan passes.

| Piece | What exists | Status |
|---|---|---|
| Pocket Essentials addon (`addons/PocketEssentials`) | One addon holding everything below. Every feature is **off** on first install | Untested in game |
| Settings window | Own window with one row per feature and a big on/off switch each; big buttons for each feature's choices; an Errors page; a "Reload UI" button at the bottom; the "Icon key" page, opened from the "Quest icons" block since 0.1.0; each feature's options fold away with "Hide options" (0.1.0, remembered); works by touch and (if the game allows it) by d-pad / A / B. Opens from the round button, the game's addon list button on the minimap, or `/pe` | Works on the device; folding and the moved Icon key button (0.1.0) untested |
| Round "PE" button | Always on screen, left edge by default, position set with Move on screen (Move the round button, Reset to the starting spot), colour chosen as Button colour: Gold, Horde or Alliance. Opens settings; opens the chat picker instead when the chat feature is on. Holding it for half a second always opens settings. Smooth round art since 0.0.2 | Works (0.0.1); new art untested |
| Quest icons | Objective icons on map and minimap from QuestieDB data, blue haze hidden. "Show icons for": Tracked quests (default; the quest tracker's quests plus the focused one), Focused quest, All quests. "Spots per objective" (All / 10 / 5 / 3, default 5; 0.0.6) limits icons per objective. Tapping an icon shows its text only | 0.0.1 ran without errors; too many icons and minimap haze fixed in 0.0.2; the spots limit is new in 0.0.6; all untested |
| Quest arrow | On-screen arrow to the focused quest's nearest objective in the current zone, with distance and quest name. "Outside this zone / Head to <zone>" when elsewhere, "No quest focused" with none, "Turn around" when the objective is behind you. Pointed arrow art since 0.0.2. Since 0.0.6 the spot it points at always keeps its icon, even beyond the spots limit. Since 0.1.0 it keeps its spot across quest-log changes, needs a clearly nearer spot before it swaps, and leaves a spot it has reached alone for three minutes | Worked on the device with and without a focused quest (0.0.9); the 0.1.0 changes worked in the 0.1.0 log. |
| Bag window and Bag sorter (two features since 0.8.0; once "One big bag") | Bag window: Blizzard's own combined bag made bigger ("Bag size": three sizes) and "Bag icons" ("In the grid" / "One row at the top": the pictures of the equipped bags in one row above the slots). Bag sorter: a big Sort button on the bag ("Sort button" On / Off) and a stick click that sorts while the bag is open ("Sort stick" Left / Right); with the Sort button showing, Left from the bag's first column reaches it and A sorts (automatic since 0.8.0, changed from the "D-pad to Sort" choice) | Sort tab and left-stick sort worked on the device (0.0.9); D-pad to Sort worked (0.6.0); the 0.8.0 split untested |
| Sell junk automatically | Sells every grey item at vendors | Worked on the device (0.0.9) |
| Repair automatically | Repairs from your own money at vendors that can | Worked on the device (0.0.9) |
| Big chat buttons | Picker with one big button per channel plus the last six whisperers; badge on the round button for unanswered whispers. With the Gamepad UI on (0.0.9) a tap sets where the chat goes and the player opens chat with the game's own button; with it off the tap opens the chat box | Say and Guild through "Press A to type" worked on the device (0.0.9); a whisper is untried. 0.1.0 adds the on-screen "Press A to type" prompt and "Chat text size" (the game's own setting); the size changed on all chat windows in the 0.1.0 log, the prompt is untested. Since 0.4.0 "Chat text size" is one stepper (Smaller, the size, Bigger; 12 to 34) shown whether the feature is on or off: untested |
| Menu background (0.4.0) | Its own switch. A plain dark panel of ours behind the game's pop-up menus while they are open; made for the menu on a quest in the quest log, which the game draws with no background. The menu itself is not touched | Untested |
| Setup guide (0.4.0, options in it since 0.5.0) | A window of nine screens (Welcome, Quest icons, Quest arrow, Menu background, Bags, Vendors, Chat, the round button and Move on screen, All set) that explains each feature and carries its switch and, under the switch, its options, both the same as in the settings and drawn by the same code. Opens by itself once per account, a moment after the first loading screen, until Finish or Skip is pressed; never in a fight. Reopened from the settings' bottom row ("Setup guide") or `/pe setup`. Touch and d-pad / A / B | Untested |
| QuestieDB | Official Questie data addon, Forever build 1.1.1, shipped unmodified. Only the two quest features need it | Untested |
| Move on screen (0.2.0 as "Move things"; renamed 0.8.0) | A small panel, opened from the settings' bottom row, from "Move the arrow" in Quest arrow or from "Move the round button", that nudges the quest arrow, the "Press A to type" text and the round button with Up / Down / Left / Right buttons (press = 2 pixels, hold = repeat and speed up), by touch or d-pad / A / B. Saved as an offset from each piece's starting spot; Reset puts the picked piece back to the starting spot. The old position buttons are gone (0.8.0). Does not use the game's Edit Mode | Untested |
| `scripts/build.sh` | Downloads QuestieDB (pinned checksum), checks the addon's file list, writes `dist/wow-forever-pocket-essentials.zip` (GitHub bundle) and `dist/PocketEssentials-<version>.zip` (CurseForge, addon only) | Runs on the Mac |

### Goal coverage

Each goal bullet above, matched to the code that implements it. "Built" means
the code exists, not that it works: nothing has run in the game yet. Bullets
that say "Not needed" are skipped.

| Goal bullet | Where | Built |
|---|---|---|
| 1. Icons on the world map and minimap for kill, loot, interact and turn-in objectives | `QuestIcons.lua` `RefreshWorldMap`, `UpdateMinimap`, `RebuildFilter`; `QuestData.lua` `KIND_LABEL` | Yes: kill, loot, interact and turn-in each get their own icon on both the map and the minimap; "Explore" objectives get a fifth kind. Shown for the tracked quests by default. Since 0.0.6 each objective shows at most "Spots per objective" icons (5 by default) per zone, spread over its area; the rest are hidden, not deleted (untested) |
| 1. Hide Blizzard's blue "haze" areas | `QuestIcons.lua` `SetWorldMapHaze`, `ZeroMinimapBlobs`, `ReapplyMinimapHaze` | Yes: hidden on the world map and the minimap (minimap re-hidden after loading screens and zone changes since 0.0.2); switching it off restores the map at once, but the minimap needs a reload |
| 1. An arrow that points toward the current objective | `QuestArrow.lua` `Select`, `DrawArrow`, `Update`; `QuestData.lua` `GetTrackedQuest` | Partial: follows the quest you focus in the quest log; points only at objectives in the zone you are standing in; for a quest elsewhere it says "Outside this zone" and names the zone (see `docs/DECISIONS.md`) |
| 2. One combined bag window instead of separate bags | `Bags.lua` `WantCombined`, `Setup` | Yes: uses Blizzard's own combined bag; with the Gamepad UI off, switching it on needs a reload |
| 2. A way to sort it | `Bags.lua` `DoSort`, `CreateButtons` | Yes: a big Sort button, plus a stick click while the bag is open ("Sort stick": left or right). The d-pad reaches the button whenever it shows (since 0.8.0 automatic; tested working in 0.6.0: `RefreshSortJump`, `SyncConfirm`) |
| 3. Automatically sell junk (grey items) at a vendor | `Vendor.lua` `ScanJunk`, `SellStep` | Yes: sells every grey item worth money, except in bags you marked to ignore; no cap per visit |
| 3. Optional automatic repair | `Vendor.lua` `RepairOnShow` | Yes: its own on/off switch, pays from your own money |
| 4. A large icon that sits permanently on screen | `Hub.lua` `Create` | Yes: the round "PE" button, always shown; it is the same button that opens settings when chat is off |
| 4. Tapping it opens a panel of big buttons, one per channel you can talk in | `Chat.lua` `OpenPanel`, `GatherTargets`, `DoRefresh` | Yes, except Instance and Officer chat (left out on purpose, see `docs/DECISIONS.md`). Shows Say, Party (when grouped), Raid (when in a raid), Guild, General, Trade and so on |
| 4. Private messages as a short list of big name buttons, most recent first | `Chat.lua` `Touch`, `GatherTargets`, `DoRefresh` | Yes: the last six whisperers, newest first. Battle.net whispers are not listed |
| 4. Tapping a channel or name opens the chat box set to that target | `Chat.lua` `TargetClicked`, `OpenChatTo` | Yes |
| 4. The icon shows when there is an unanswered whisper | `Chat.lua` `UpdateBadge`, `OnWhisper`; `Hub.lua` `SetBadge` | Yes: a badge on the round button, plus a "Clear marks" button |
| 5. A way to arrange the interface that does not depend on fiddly touch dragging | `Move.lua` `Open`, `Register`, `GetOffset`; each piece's layout | Yes (0.2.0, untested): the "Move on screen" panel moves the quest arrow, the chat prompt and the round button with big buttons or the d-pad, no dragging |
| 6. One touch-friendly place to turn each feature on or off, no typed commands | `Settings.lua` `PE:OpenSettings`, `BuildModuleRow`; `Hub.lua` `OnClick` | Yes: one row and big switch per feature, opened from the round button. Since 0.4.0 (untested) the setup guide (`Setup.lua` `Setup:Open`, `SCREENS`) walks a new player through the same switches with a few lines about each |

Defaults: **every feature is off and stays off by default**, also after it
has passed its device test (owner's ruling, 2026-11-17; it replaces the earlier
plan to flip each default to on once tested). Nothing is switched on for the
player. The setup guide (0.4.0) is how a player learns what exists and turns
on what they want; the settings window has the same switches.

The device test plan is in `docs/TESTING.md`.

## Roadmap

Rules 1 and 2 apply: one phase at a time, one item at a time.

1. **Device testing.** Test 0.0.6 first: the spots limit, the arrow's spot,
   the icon key, the Reload UI button, and 0.0.5's two arrow-text changes
   (`docs/TESTING.md` steps 1 to 3). Then the features that have never run in
   the game, one step at a time: bags (step 4), sell junk (5), repair (6),
   chat (7), and the wrap-up (9). (Step 8, the layout helper, was removed in
   0.3.0.)
2. **Performance and user-experience polish.** Fix what the tests show.
   Features stay off by default; the setup guide is how players turn on what
   they want (see "Defaults" above).
3. **First CurseForge upload.** Use `curseforge/FIELDS.md`.
4. **Left to build.** One at a time, spec first; see "Parked ideas".

0.0.7 (2026-11-17, untested) answers this with a report of what the game
blocked, a debug log that is sent as a file (Settings > Errors, spec
`docs/superpowers/specs/2026-11-17-debug-log.md`), and the fixes from a code
review against Blizzard's source (CHANGELOG 0.0.7, "Fixed"). The review could
not prove the cause of the pop-up; the next device test, with the debug log
on, should name it.

**Fifth device test, 2026-11-17 (0.0.7), first debug log file**
(`docs/errorLogs/PocketEssentials.lua`, read with `scripts/read-log.sh`):
the log file route works on the device. One block recorded: "The game
stopped a protected step of Blizzard's own interface" from `Chat.lua:219`
(the call to `ChatFrameUtil.OpenChat`), Gamepad UI on, no fight by
`InCombatLockdown`; the chat box still opened and the message was sent. The
same tap after a reload was not blocked. The owner confirmed it happened in
town, out of combat. Likely cause, not confirmed: with the Gamepad UI on,
opening the chat box moves the controller's focus through
`Blizzard_GamepadSmartNavigation/SmartNavigation.lua`, where about thirty
functions (`SelectButton`, `SetActiveFrame`, `ActivateBinding`, ...) print
this message whenever addon code is anywhere behind the call, fight or no
fight (`EnsureIsSecure`). 0.0.8 (untested) does not fix it; it writes the
game's own stack lines to the log so the next file names the function, and
also asks the game's combat restriction before opening the chat box. The
fix that cannot be blocked is to stop opening the chat box from the addon:
the tap would only set who the chat goes to, and the player opens chat with
the game's own button (owner's decision, not built). Quest data rebuilt 11
quests into 345 icons in about 0.1 to 0.2 seconds at login. Sell junk and
repair were not exercised in this log.

**Sixth device test, 2026-11-17, Pocket Probe 0.1.0**
(`docs/errorLogs/PocketProbe.lua`; table in `docs/ARCHITECTURE.md` "What the
device allows"): Gamepad UI on, in town, no fight. Opening, focusing or
closing the chat box, and opening or closing the bags, from addon code is
blocked or forbidden, and afterwards the game forbids its own controller
actions (`InteractUnit`, `SetPreferredGamepadInteractTarget`, `ClearTarget`,
`SpellStopCasting`) in the addon's name until a reload. Everything else tried
was allowed and every value was readable. This is the likely cause of the
pop-up at the innkeeper in the fourth test (chat buttons were on), not yet
confirmed for Pocket Essentials itself. 0.0.9 (untested): chat buttons no
longer open the chat box with the Gamepad UI on. Still not probed: a fight,
the vendor trials, the clean trials.

**Seventh device test, 2026-11-17, Pocket Probe 0.2.0**
(`docs/errorLogs/PocketProbe-1.lua`; table in `docs/ARCHITECTURE.md`): safe
passes in town and in a fight (automatic and from a press), a vendor, and the
thirteen clean trials. Findings: (1) the chat box is the only thing that does
lasting harm: after an addon opens or closes it the game refuses its own
controller actions until a reload; every other clean trial was clean. (2)
Selling a grey item and repairing from addon code, with no button press, were
both allowed, so sell junk and repair were not the cause of the pop-up in the
fourth test. (3) In a fight everything tried was allowed except taking
controller buttons and marking buttons for navigation. (4) Every value was
readable, in and out of a fight. The owner had to type a chat message twice
during the clean trials: after a reload the keyboard was already up (the
probe had opened the chat box and its close was refused), the typed message
was accepted, the box closed and reopened, and it had to be typed again.
Normal chat on the device, with no addons (owner, same day): click the chat
box, the game's small chat line appears empty, the keyboard comes up, type,
send, and the message goes out in one go. The double typing is therefore
put down to the probe's forced-open chat box, not confirmed. Next: device test of Pocket Essentials 0.0.9 (chat "Press A to type",
sell junk, repair) with the debug log on.

**Eighth device test, 2026-11-17 (0.0.9), probe off, all features:** "very
successful" (owner). Working with no errors or pop-ups: chat buttons in Say
and Guild (tap, press A, type, send), sell junk, repair, the Sort tab and
stick sort, quest icons with the filter, the arrow with and without a focused
quest. The log has no error or block from 0.0.9 across five sessions and
about twenty fights: nine grey items sold for 2s 64c, a repair for 26c, Sort
from the tab and the stick, Say and Guild through "Press A to type". A whisper has not been tried yet. Oddities: (1) after switching more
features on and reloading, the chat box and keyboard were open when the
interface came back. The debug log (`docs/realtest1/`) shows the A button
was not lent at that reload and no chat tap in the minute before it, so the
addon did not open it; the owner also sees the character pane open after
every reload, and both probe files show it focused at login with Pocket
Essentials off. Cause not known; to be checked with no addons loaded. (2)
After sending a message the chat box stays selected until B is pressed.
Requests from this test, all built in 0.1.0 (2026-11-17, one batch at the
owner's request, spec `docs/superpowers/specs/2026-11-17-post-0.0.9-batch.md`),
**none tested on the device yet**:
- Arrow: follow the quest as its parts are completed, and when a quest has
  several areas move on as the player runs around, not stay on the first.
  Looking into it showed the arrow did re-pick the nearest spot and did drop
  finished parts; what it lacked was any memory of spots already reached, so
  in a camp it kept pointing at the spot underfoot. 0.1.0: a reached spot is
  left alone for three minutes, the target is kept across quest-log changes,
  another spot must be clearly nearer to take over, and the debug log names
  the spot so the next log can show what it did.
- Bags: "One big bag" renamed "Bag sorter"; "Sort key": left stick click
  (L3), right stick click (R3), or the on-screen button only.
- Chat: "Chat text size" (Smaller / Bigger) in the settings, using the game's
  own chat font size setting.
- Chat: "Press A to type" shown in big letters on screen while the A button
  is lent.
- Settings: each feature's options fold away ("Hide options" / "Show
  options"), remembered between sessions.
- Settings: the "Icon key" button moved into the "Quest icons" block.

Next: device test of 0.1.0 with the debug log on (all six items, plus a
whisper through the chat buttons).

**Ninth device test, 2026-11-17 (0.1.0), under way.** First impressions from
the owner: so far so good, the folding settings are "great". Requests so far:
- Move the arrow (and the other on-screen text) exactly where the player
  wants, with the d-pad as well as touch; some presets are good but everyone
  will want to tweak. **Built in 0.2.0** at the owner's instruction while the
  test was still running (spec `docs/superpowers/specs/2026-11-17-move-things.md`):
  a "Move things" panel of our own with arrow buttons (press to nudge, hold to
  keep moving), d-pad / A / B, for the quest arrow, the "Press A to type"
  text and the round button. The game's Edit Mode is not used. Untested.
- Chat options should be more configurable than two buttons (a small
  refinement; the owner will say what once they have played more). 0.4.0
  makes "Chat text size" one stepper that shows the size and works with the
  feature off; nothing else has been asked for yet.

Log from that test (`docs/real2/`, 0.1.0 only, two sessions, about an hour,
57 fights): no error and no blocked action. Seen working in the log: folding
four feature blocks; chat text size 18 to 16 and back, on all ten chat
windows; Sort key set to the right stick, taken while the bag was open and
sorting from it; the arrow keeping its spot through quest-log changes,
setting a reached spot aside and leading on to the next one (quests 748 and
761), swapping only to a clearly nearer spot, and going straight to the
turn-in when the last part was finished; time stamps in order. Not exercised
in this log: any tap on a chat button (so the on-screen "Press A to type" and
a whisper are still untested), the Icon key button, and all of 0.2.0. One
piece of log noise found: "stick click given back to the game" is written at
the start of every fight even when no stick was taken (fixed in 0.2.1, which
changes the log only).

**0.3.0 (2026-11-17, untested), built while the owner was away** at their
instruction (spec `docs/superpowers/specs/2026-11-17-arrow-other-zones-and-layout-removal.md`):
- The Layout helper is removed (the owner asked for it to go if it was out of
  scope; it was never tested and "Move things" replaced its purpose).
- The quest arrow can point into another zone: "Quest in another zone" >
  "Point the way", off by default. A light blue arrow, a straight line, same
  continent only. **Taken out again in 0.3.1** (see below).

**0.3.1 (2026-11-17, untested):** the owner chose to postpone the arrow into
other zones and roll it back: a straight line does not lead to where zones
connect, and a list of crossings is more than the addon should carry for now
(`docs/DECISIONS.md`, "Rollback of 2026-11-17"). The Layout helper stays
removed.

**0.6.0 (2026-11-18, untested):** the owner on the settings: "we've got some individual buttons that drive the answer to certain settings, could those be consolidated into a more slique experience that removes visual clutter and streamlines settings?"
Approved four of five proposals: two-sided choices become one-tap toggles
(Hide blue haze, D-pad to Sort, Bag icons); "Map icons" and "Minimap icons"
become one "Icons on" choice; "Sort key" and "Sort button" become one "How
to sort" choice that always leaves a way to sort; headings sit beside their
buttons where they fit. Not taken: merging "Merge nearby icons" and "Spots
per objective". The owner has more Quest icons ideas to bring after testing.
Spec `docs/superpowers/specs/2026-11-18-tidier-settings.md`; device steps
`docs/TESTING.md` 14.

**0.8.0 (2026-11-18, untested):** the owner after testing 0.7.0: "do the
next 3, and call the release 0.8.0" (the three later builds of the 0.7.0
spec), plus Merge nearby icons made clearer, the guide's first page and the
ugly Up and Down buttons. Built: "Move the arrow" and "Move the round button"
replace the position buttons ("Move things" is now "Move on screen"; Reset
means the starting spot); Bags in two (Bag window: Bag size, Bag icons; Bag
sorter: Sort button, Sort stick; D-pad to Sort automatic with the Sort
button, tested working by the owner in 0.6.0); Button colour Gold, Horde,
Alliance; "Merge icons closer than N% of map"; the guide's first page starts
on Start and asks about the touch screen; a slim scroll bar with arrows and a
marker, and a "Touch screen" setting. Spec
`docs/superpowers/specs/2026-11-18-0.8.0-design.md`; device steps
`docs/TESTING.md` section 16.

**0.7.0 (2026-11-18, untested):** the owner after trying 0.6.0: Spots per
objective and Merge nearby icons should let them pick the exact amount, with
a control that "looks nice too"; a smaller icon size and a smaller arrow;
Chat text size "a little ugly"; Hide blue haze "awkward" in the middle. Built:
a joined "- value +" number control (mockup A, chosen by the owner) for
Spots (1 to 20, then All), Merge (Off, 1 to 10) and Chat text size; Extra
small icons; Small arrow; Hide blue haze at the bottom. The next builds,
agreed in chat and listed in the spec: Move replaces the position buttons,
Bags split in two (D-pad to Sort tested working by the owner), button
colours. Spec `docs/superpowers/specs/2026-11-18-number-control-design.md`;
device steps `docs/TESTING.md` section 15.

**0.5.0 (2026-11-18, untested):** the owner on the setup guide: "the other thing i was expecting is that the setup screens didnt expose the same options i see in the settings menu, can we enhance the flow to expose those, so people are setting things up and configuring, not just turning things on?"
The guide now shows each feature's options under its switch, drawn by the
same code as the settings (one "list drawer", two windows), so labels,
buttons and saved values are the same in both. The screens went from seven
to nine, one per feature that has options. Button size and Round button
position are not in the guide: they belong to no feature and stay on the
list of ideas below until the owner says yes. Device steps:
`docs/TESTING.md` 13e, rewritten.

**0.4.1 (2026-11-18):** the owner's first look at 0.4.0 on the device: "initial
testing went well, ui and everything had no issues, the setup screen was
nice". One fix asked for: the guide's Up and Down buttons on the right are
now shown only on a screen too long to fit. The numbered steps of
`docs/TESTING.md` section 13 are still to be reported.

**0.4.0 (2026-11-17, untested), built while the owner was away** at their
instruction (spec `docs/superpowers/specs/2026-11-17-0.4.0-handheld-batch.md`,
rulings in `docs/DECISIONS.md`, "Batch of 2026-11-17 (0.4.0)"). Five things,
every one off or on the game's own behaviour until the player changes it:
- Setup guide: seven screens that explain each feature and carry its switch.
  It opens by itself once per account until Finish or Skip is pressed, and
  again from the settings or `/pe setup`. The owner's words: "all settings
  remain off by default, i want to introduce a tutorial/setup flow with a few
  screens that educate and enable users to turn on what they want, that way
  they understand whats turned on and how it works."
- Menu background: its own switch; a dark panel behind the game's pop-up
  menus (second device test, finding 4).
- Bags, "D-pad to Sort": a choice in Bag sorter; Left from the bag's first
  column goes to the Sort tab and A sorts. Whether A can be won from the
  bag's own footer can only be seen on the device; if not, the idea is
  dropped.
- Bags, "Bag icons": a choice in Bag sorter; the pictures of the equipped
  bags in one row at the top of the game's bag window ("like Bagnon"). No
  bag window of our own. This is the first time the addon moves the bag's
  own buttons, so the device test of item use (press, drag, sell, split, in
  and out of a fight) decides whether it stays.
- Chat text size: one stepper (- number +, since 0.7.0; first Smaller, the size, Bigger), shown whether or
  not Big chat buttons is on. This is the "more configurable chat options"
  asked for in the ninth test, as far as the owner has said so far.

Next: device test of 0.2.0 (Move things), 0.3.1 and 0.4.0 (`docs/TESTING.md`
steps 11, 12 and 13a to 13e) with the debug log on.

Upcoming from the fourth device test (2026-11-16), one at a time:
- Bags: reach the Sort tab with the d-pad: built in 0.4.0 ("D-pad to Sort"),
  untested.
- Bags: clearer settings wording and a choice of sort key: built in 0.1.0
  ("Bag sorter", "Sort key"); the Sort key choice worked in the 0.1.0 log.
- Bags: "one plain box with items packed at the top" became, after the
  owner's ruling of 2026-11-17, the bag icons row: built in 0.4.0 ("Bag
  icons"), untested. The game's one big bag box stays; packing the items
  with no gaps is parked (see "Parked ideas").

Open questions from the device tests (not yet known to be ours):
- Blue icons on the minimap only (second device test, finding 1).


## Parked ideas

Everything still to be built, in rough order of how much it is wanted.

- The quest arrow pointing into another zone. Postponed by the owner on
  2026-11-17: built in 0.3.0 as a straight line, taken out in 0.3.1 because
  it does not lead to where zones connect. Needs a list of crossings (written
  by hand or learned from where the player changes zone). Routes by boat or
  flight path and other continents are not planned at all.
- Bags: items packed together with no gaps between the bags' slots. The
  game's bag window lays out its own slots by the bag they sit in; 0.4.0 only
  moves the bag pictures out of the grid ("Bag icons"). Packing needs either
  a bag window of our own, which the owner ruled out on 2026-11-17, or moving
  every slot button; wait for the device test of "Bag icons" first.
- The setup guide could also offer the button size and the round button's
  position, a picture per feature, and come back when a later version adds a
  feature. Proposed in the 0.4.0 spec, not asked for. (Since 0.5.0 the first
  is a few lines: the settings' two rows are drawn by the shared list
  drawer, `CoreChoices`.)
- Owner has more ideas; add them here as one line each, then spec before
  building.

Built since they were parked here: a background for the quest log's pop-up
menu ("Menu background", 0.4.0), the d-pad reaching the Sort tab ("D-pad to
Sort", 0.4.0) and the chat text size stepper (0.4.0). All untested.

Dropped on 2026-11-15 (see "Non-goals"): the radial wheel entry, and icons for
quests not yet picked up.

## Repo layout

- `PRD.md` — this file: rules, goals, status, roadmap
- `README.md` — player and developer overview
- `CLAUDE.md`, `AGENTS.md` — instructions for AI coding agents
- `.claude/settings.json` — shared agent settings
- `CHANGELOG.md` — release history
- `LICENSE` — GPL-3.0
- `addons/PocketEssentials/` — the addon, exactly as it should land in AddOns
- `probe/PocketProbe/` — the restriction probe: a separate test-only addon that records what the game allows; built into `dist/PocketProbe.zip`, never in the player zips; read its saved file with `scripts/read-probe.sh` (`docs/TESTING.md`)
- `scripts/build.sh` — builds the zip
- `scripts/check.sh` — LuaJIT syntax check plus a comment-wording check
- `scripts/test.sh` — runs the offline tests in `tests/`
- `scripts/audit-api.sh` — full check of the game names the addon uses against Blizzard's source; rewrites `tests/api/*.txt`
- `scripts/fetch-questiedb.sh` — downloads the pinned QuestieDB release
- `scripts/make_art.py` — generates the artwork
- `tests/` — off-device tests; none of it is packaged into the addon zips
  - `tests/api/` — game-name audit and its saved results
  - `tests/questiedb/` — QuestieDB harness
  - `tests/features/` — rule tests, one file per feature
  - `tests/smoke/` — whole-addon smoke test
  - `tests/lib/` — stand-in game client and helpers
- `.github/workflows/test.yml` — runs check, tests and audit on GitHub for every push
- `curseforge/` — CurseForge upload text and fields (`FIELDS.md`)
- `docs/ARCHITECTURE.md` — structure, safety net, unverified API, facts
- `docs/DECISIONS.md` — decisions made without the maintainer, and what was left out
- `docs/TESTING.md` — device test plan
- `docs/superpowers/specs/` — approved feature specs, `<date>-<feature>.md`
- `docs/superpowers/plans/` — build plans made from the specs
- `vendor/` — downloaded third-party releases (not committed)
- `dist/` — build output (not committed)

New features: brainstorm, write a spec in `docs/superpowers/specs/`, make a
plan in `docs/superpowers/plans/`, build it subagent-driven with review
against the spec, then test on a device.
