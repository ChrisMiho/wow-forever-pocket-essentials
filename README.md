# WoW Forever Pocket Essentials

A small, lightweight addon bundle for playing WoW Forever on a handheld
(built around a Retroid Pocket 6 running the game through Droid Deck).
Addon interface version: `16001`.

**Nothing here has run in the game yet.** See the device test plan in
[PRD.md](PRD.md).

## Install

1. Run `scripts/build.sh`. It writes `dist/wow-forever-pocket-essentials.zip`.
2. Copy the zip to the device.
3. In the game's `Interface/AddOns` folder, **delete any old `QuestDots`
   folder** from an earlier version of this bundle.
4. Extract the zip into `Interface/AddOns`. You should end up with two
   folders side by side: `PocketEssentials` and `QuestieDB`. Do not rename
   either.
5. Log in. A round "PE" button appears at the left edge of the screen. Tap it
   to open the settings. **Every feature starts switched off**; turn them on
   one at a time.

Other ways to open the settings: the addon list button on the minimap, or
type `/pe`. Holding the round button for half a second also always opens
them.

## What's in it

| Folder | Job |
|--------|-----|
| `PocketEssentials` | Everything below, each with its own on/off switch |
| `QuestieDB` | Quest location data for the two quest features. Downloaded unmodified from the [official release](https://github.com/Questie/QuestieDB/releases) at build time. Everything else works without it |

| Feature | What it does |
|---------|--------------|
| Quest icons | Objective icons on the map and minimap, no blue haze. Tap an icon to pick that quest |
| Quest arrow | An arrow to the nearest objective in your zone, with distance |
| One big bag | Blizzard's combined bag with a big Sort button; L3 sorts while it is open; three sizes |
| Sell junk automatically | Sells grey items at vendors, at most 12 per visit so all stay in buyback |
| Repair automatically | Repairs from your own money |
| Big chat buttons | The round button opens a picker: one big button per channel and per recent whisperer. A badge shows unanswered whispers |
| Layout helper (experimental) | One-tap switch to Blizzard's Gamepad layout and back |

If something goes wrong, the settings window has an **Errors** page that
shows what failed, in large text.

QuestieDB carries its data file under two names (`_Forever` and `_Camelot`)
because it isn't confirmed which one the client loads. The build keeps both
until testing settles it; `QUESTIEDB_TOC=Forever scripts/build.sh` (or
`Camelot`) keeps just one and halves the size.

## Layout

- `addons/PocketEssentials/` — the addon, exactly as it should land in `AddOns`
- `scripts/build.sh` — builds the zip
- `vendor/` — downloaded third-party releases (not committed)
- `dist/` — build output (not committed)
- `PRD.md` — requirements, decisions, known unknowns and the device test plan
