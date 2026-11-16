# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

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
