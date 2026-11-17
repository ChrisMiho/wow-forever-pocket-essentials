# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

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
