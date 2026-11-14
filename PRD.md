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
   approved by the owner, before any plan or code.

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

In progress: version 0.0.1 is written but has not run on a device yet.

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
| Sell junk automatically | Sells every grey item at vendors | Untested |
| Repair automatically | Repairs from your own money at vendors that can | Untested |
| Big chat buttons | Picker with one big button per channel plus the last six whisperers; badge on the round button for unanswered whispers | Untested |
| Layout helper (experimental) | One-tap switch to Blizzard's Gamepad layout and back; a dormant path to install a ready-made handheld layout. **No nudge arrows** (see `docs/DECISIONS.md`) | Untested |
| QuestieDB | Official Questie data addon, Forever build 1.1.1, shipped unmodified. Only the two quest features need it | Untested |
| `scripts/build.sh` | Downloads QuestieDB (pinned checksum), checks the addon's file list, writes `dist/wow-forever-pocket-essentials.zip` | Runs on the Mac |

### Goal coverage

Each goal bullet above, matched to the code that implements it. "Built" means
the code exists, not that it works: nothing has run in the game yet. Bullets
that say "Not needed" are skipped.

| Goal bullet | Where | Built |
|---|---|---|
| 1. Icons on the world map and minimap for kill, loot, interact and turn-in objectives | `QuestIcons.lua` `RefreshWorldMap`, `UpdateMinimap`; `QuestData.lua` `KIND_LABEL` | Yes: all four kinds get their own icon on both the map and the minimap |
| 1. Hide Blizzard's blue "haze" areas | `QuestIcons.lua` `SetWorldMapHaze`, `ZeroMinimapBlobs` | Yes: hidden on the world map and the minimap, and put back when the feature is off |
| 1. An arrow that points toward the current objective | `QuestArrow.lua` `Select`, `DrawArrow`, `Update` | Partial: works only for objectives in the zone you are standing in; for a quest elsewhere it says "Not in this zone" (see `docs/DECISIONS.md`) |
| 2. One combined bag window instead of separate bags | `Bags.lua` `WantCombined`, `Setup` | Yes: uses Blizzard's own combined bag; with the Gamepad UI off, switching it on needs a reload |
| 2. A way to sort it | `Bags.lua` `DoSort`, `CreateButtons` | Yes: a big Sort button, plus L3 while the bag is open |
| 3. Automatically sell junk (grey items) at a vendor | `Vendor.lua` `ScanJunk`, `SellStep` | Yes: sells every grey item, no cap per visit |
| 3. Optional automatic repair | `Vendor.lua` `RepairOnShow` | Yes: its own on/off switch, pays from your own money |
| 4. A large icon that sits permanently on screen | `Hub.lua` `Create` | Yes: the round "PE" button, always shown; it is the same button that opens settings when chat is off |
| 4. Tapping it opens a panel of big buttons, one per channel you can talk in | `Chat.lua` `OpenPanel`, `GatherTargets`, `DoRefresh` | Yes: Say, Party (when grouped), Raid (when in a raid), Guild, General, Trade and so on. Instance and Officer chat are left out (see `docs/DECISIONS.md`) |
| 4. Private messages as a short list of big name buttons, most recent first | `Chat.lua` `Touch`, `GatherTargets`, `DoRefresh` | Yes: the last six whisperers, newest first. Battle.net whispers are not listed |
| 4. Tapping a channel or name opens the chat box set to that target | `Chat.lua` `TargetClicked`, `OpenChatTo` | Yes |
| 4. The icon shows when there is an unanswered whisper | `Chat.lua` `UpdateBadge`, `OnWhisper`; `Hub.lua` `SetBadge` | Yes: a badge on the round button, plus a "Clear marks" button |
| 5. A way to arrange the interface that does not depend on fiddly touch dragging | `Layout.lua` `DoGamepad`, `DoBack`, `DoInstall` | Partial: one-tap switch to Blizzard's Gamepad layout and back. No nudge arrows (not safe, see `docs/DECISIONS.md`) and no ready-made handheld layout is bundled yet |
| 6. One touch-friendly place to turn each feature on or off, no typed commands | `Settings.lua` `PE:OpenSettings`, `BuildModuleRow`; `Hub.lua` `OnClick` | Yes: one row and big switch per feature, opened from the round button |

Defaults: every feature is off so players can switch them on one at a time.
**Once a feature has passed its device test, its default flips to on** (one
line per feature in its Lua file's registration; today all default to off
because nothing is saved as on).

The device test plan is in `docs/TESTING.md`.

## Roadmap

Rules 1 and 2 apply: one phase at a time, one item at a time.

1. **Device testing.** Work through `docs/TESTING.md` one step at a time on
   the reference device.
2. **Performance and user-experience polish.** Fix what the test results
   show, and flip defaults to on for features that pass.
3. **First CurseForge upload (0.0.1).** Use `curseforge/FIELDS.md`.
4. **New features.** Parked until phase 2 is done; see "Parked ideas".

## Parked ideas

- Improved Forever's radial wheels.
- A bundled handheld layout (needs one exported from the device first; see
  `docs/TESTING.md` step 9).
- The quest arrow across zones (removed after review because it could show a
  confidently wrong direction).
- Owner has more ideas; add them here as one line each, then spec before
  building.

## Repo layout

- `PRD.md` — this file: rules, goals, status, roadmap
- `README.md` — short install notes
- `CLAUDE.md`, `AGENTS.md` — instructions for AI coding agents
- `.claude/settings.json` — shared agent settings
- `CHANGELOG.md` — release history
- `LICENSE` — GPL-3.0
- `addons/PocketEssentials/` — the addon, exactly as it should land in AddOns
- `scripts/build.sh` — builds the zip
- `scripts/check.sh` — syntax and consistency checks
- `scripts/test.sh` — runs the tests in `tests/`
- `scripts/fetch-questiedb.sh` — downloads the pinned QuestieDB release
- `scripts/make_art.py` — generates the artwork
- `tests/` — off-device tests
- `curseforge/` — CurseForge upload text and fields (`FIELDS.md`)
- `docs/ARCHITECTURE.md` — structure, safety net, unverified API, facts
- `docs/DECISIONS.md` — decisions made without the owner, and what was left out
- `docs/TESTING.md` — device test plan
- `docs/superpowers/specs/` — approved feature specs, `<date>-<feature>.md`
- `docs/superpowers/plans/` — build plans made from the specs
- `vendor/` — downloaded third-party releases (not committed)
- `dist/` — build output (not committed)

New features: brainstorm, write a spec in `docs/superpowers/specs/`, make a
plan in `docs/superpowers/plans/`, build it subagent-driven with review
against the spec, then test on a device.
