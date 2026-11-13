# Mobile Addon Bundle

A small, lightweight set of addons for playing WoW Forever on a handheld
(built around a Retroid Pocket 6 running the game through Droid Deck).
Addon interface version: `16001`.

## Install

1. Run `scripts/build.sh`. It writes `dist/MobileAddonBundle.zip`.
2. Copy the zip to the device.
3. Extract it into the game's `Interface/AddOns` folder. Each addon's folder
   sits at the root of the zip.

## What's in it

| Addon | Job | Status |
|-------|-----|--------|
| QuestDots | Quest objective icons on the map and minimap, no blue haze | Untested in game. Needs the QuestieDB data addon, not bundled yet |

## Planned

- QuestieDB data, trimmed per faction (separate Horde and Alliance bundles)
- Direction arrow to the tracked quest objective
- One big bag with sorting
- Auto-sell junk, optional auto-repair
- Touch-friendly chat button: pick a channel or whisper target, then type
- Easier UI layout on a touch screen

## Layout

- `addons/` — one folder per addon, exactly as it should land in `AddOns`
- `scripts/build.sh` — builds the zip
- `dist/` — build output (not committed)
