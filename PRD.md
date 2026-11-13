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
| Device | Retroid Pocket 6, 12 GB RAM |
| How the game runs | Through Droid Deck (the Windows arm64 client on Android) |
| Game client | WoW Forever 1.60.1 (70938), arm64. Addon interface `16001` |
| Input | Blizzard's built-in gamepad support, working out of the box. Touch screen for everything else |
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
- Tapping a channel or name opens the chat box already set to that target,
  bringing up the keyboard to type.
- The icon indicates when there is an unanswered whisper.

### 5. UI layout
- Some way to arrange the interface that does not depend on fiddly touch
  dragging. Not yet explored; needs a conversation with the owner first.

### 6. Settings panel
Added 2026-11-13; not yet scoped or designed.
- One touch-friendly place in game where each feature of the bundle can be
  turned on or off, with big targets and no typed commands.
- Mockups of this and the other screens should be agreed with the owner
  before anything is built.

## Non-goals

- Matching the desktop addon setup feature for feature.
- Combat addons (damage meters, boss timers). The client does not support
  combat-log addons anyway.
- Replacing Blizzard's gamepad support (no ConsolePort unless the owner asks).

## What would make this a failure

- A noticeable drop in frame rate or longer load times compared with no addons.
- Anything that needs precise tapping, small targets or typed slash commands
  for everyday use.
- A bundle that needs manual steps beyond "extract the zip into AddOns".

## Deliverable

- One zip, with each addon's folder at the zip root.
- Built by a script in this repo so it is repeatable.
- **Later, not now:** separate Horde and Alliance builds with the other
  faction's quest data removed, so the owner can share an Alliance build with
  friends. Parked until the bundle works.

## Current state

**Nothing in this repo has been tested in game.** Treat everything below as
unproven.

| Piece | What exists | Status |
|---|---|---|
| QuestDots (`addons/QuestDots`) | Custom addon written by a previous agent, unprompted. Draws objective icons on map and minimap, hides the haze, tapping an icon tracks that quest. Settings only via typed `/qd` commands. No arrow. Only shows quests already in the log | Untested |
| QuestieDB | Official Questie data addon, Forever build 1.1.0. Downloaded at build time, not stored in the repo. QuestDots depends on it | Untested |
| `scripts/build.sh` | Downloads QuestieDB, combines it with `addons/`, writes `dist/wow-forever-pocket-essentials.zip` | Runs on the Mac; output untested on device |
| Arrow, bags, vendor, chat, UI layout | Nothing | Not started, not researched |

## Roadmap

Work top to bottom. Each step ends with the owner testing on the device.

1. **First device test.** Install the current zip. Does the game list both
   addons? Do icons appear on the map and minimap for quests in the log? Is
   the haze gone? Any errors?
2. **Fix whatever step 1 finds** until questing icons work.
3. **Direction arrow.** Check existing options first (TomTom has a Forever
   build; Blizzard's own quest tracking may already give an arrow).
4. **Bags.** Research which combined-bag addons have a Forever build and how
   heavy they are. Recommend one.
5. **Vendor chores.** Research existing small auto-sell/repair addons with a
   Forever build. If none, this is a very small custom addon.
6. **Chat button.** Likely custom. Confirm first whether opening the chat box
   from an addon brings up the on-screen keyboard under Droid Deck.
7. **UI layout.** Talk to the owner about what is hard today before proposing
   anything.
8. **Trim and split.** Cut QuestieDB's duplicate data file if testing allows,
   then faction-specific builds.

## Facts

### Verified (from source files or official releases)
- Addon interface number is `16001` (from the QuestDots manifest and multiple
  addon listings).
- QuestieDB has an official Forever build:
  <https://github.com/Questie/QuestieDB/releases>. Version 1.1.0 is pinned in
  `scripts/build.sh` with a checksum.
- QuestieDB 1.1.0 is 36 MB unpacked. 34 MB of that is one 18 MB data file
  shipped twice under two names, `QuestieDB_Forever.toc` and
  `QuestieDB_Camelot.toc`, byte-identical. The game loads only one.
- Inside that data file: translations 5.4 MB, creatures 5.5 MB, items 3.2 MB,
  quests 2.1 MB, objects 1.9 MB. Entries are read on demand, so size mainly
  costs storage and load time.
- Each quest records which races can take it, so faction filtering is possible
  in principle.
- QuestDots requests version 1 of QuestieDB's interface; QuestieDB 1.1.0
  (version 4) still accepts version 1.
- QuestieDB's licence: the Questie team permits copying under GPL-3.0 terms
  but cannot speak for all past contributors. This repo ships their release
  unmodified with licence files intact. Re-read `LICENSE.md` inside the release
  before distributing a modified (trimmed) copy.

### Unverified (do not rely on these without testing)
- Whether QuestDots works at all on this client.
- Which of the two QuestieDB data files the client loads. QuestieDB's own
  authors list this as unconfirmed, which is why both ship. Removing the wrong
  one would silently break the database. `QUESTIEDB_TOC=Forever
  scripts/build.sh` (or `Camelot`) builds with only one, for testing this.
- Whether the owner's client uses English text. The launcher reports "Chinese
  Release". This decides whether translations can be dropped.
- Whether opening the chat box from an addon triggers the on-screen keyboard
  under Droid Deck.
- Community guides report bag, map, vendor and tooltip addons working on
  Forever, and TomTom having a Forever build. Not checked first-hand.
- How much faction trimming would save. Not measured.

## Repo layout

- `PRD.md` — this file
- `README.md` — short install notes
- `addons/` — one folder per addon, exactly as it should land in AddOns
- `scripts/build.sh` — builds the zip
- `vendor/` — downloaded third-party releases (not committed)
- `dist/` — build output (not committed)
