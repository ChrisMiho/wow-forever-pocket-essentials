# Loot sparkles

**Status:** approved by the owner on 2026-11-20 ("i agree, just build it behind a toggle, that way, when someone turns down their settings all the way, i can turn the sparkles back on").

## Why
On low graphics, the game hides the sparkle on things you can interact with. The owner uses the addon ForeverLootSparkles (https://github.com/svengabr/ForeverLootSparkles, GPL-3.0-or-later, by Ashtar Senior / svengabr) on their PC. On their PC "everything sparkles that i can interact with, from quest givers to corpses, to items on the ground".

That addon keeps one engine setting switched on: the CVar `outlineModeShowLootEffectWhenDisabled = 1`. That is too little code to bundle as a second addon, so Pocket Essentials gets the same thing as one switch, credited to the original.

## What it does
- **New feature:** file `LootSparkles.lua`, key `sparkles`, name **Loot sparkles**, line "Brings back the sparkle on things you can loot or use, even on the lowest graphics." Off by default, like every feature until it is device-tested.
- **On:**
  - Save the CVar's current value once, in the feature's options as `previous`, if not already saved.
  - Then set it to "1". Set it again at login and on `CVAR_UPDATE` for `graphicsQuality`, `raidGraphicsQuality` or this CVar itself, when it is not "1".
  - Writes are put off while in combat (`InCombatLockdown()`) until `PLAYER_REGEN_ENABLED`.
  - All handlers go through `PE:Safe` / `PE:Wrap`. No timers and no OnUpdate. Events are registered only while the feature is on.
- **Off:**
  - Put the saved `previous` value back (or "0"), then clear `previous`.
  - No reload reason: the reload bar's "Reload now" would not remove the sparkles (changed at review, 2026-11-20).
  - The status line while it is off after having been on this session: "Fully restart the game to remove the sparkles."
- **A blue status line while it is on:** "Quest items show the sparkle instead of the outline."
- **API:** `C_CVar.GetCVar` and `C_CVar.SetCVar` inside pcall, as Bags.lua does today; and `CVAR_UPDATE`. Confirm `CVAR_UPDATE` and `C_CVar` on the forever branch (`scripts/audit-api.sh`). The CVar name is engine-only (not in Blizzard's UI source). Log it in `docs/ARCHITECTURE.md` as unverified; the worst case is that it does nothing.
- **Credit** in the file header, CHANGELOG and README: "Based on ForeverLootSparkles by Ashtar Senior (GPL-3.0-or-later)".

## Where it shows
- **Settings:** the "Menu background" tab is renamed **Game fixes**. It keeps its heading card ("Fixes for the game's own interface"; its line becomes "Parts of the default Blizzard UI that are hard to use on a handheld, or that low graphics hide.") and holds the Menu background card, then the Loot sparkles card. Its dot is green when either is on.
- **Setup guide:** the "Vendors and menus" screen becomes **Vendors and game fixes**, with the cards Auto sell junk, Auto repair, Menu background and Loot sparkles. Each card has one line, with no "How:" line.

## Tests
- Turning it on saves `previous` and sets the CVar to 1.
- A graphics change that resets it is undone, outside combat at once, and in combat after combat ends.
- Turning it off puts `previous` back and shows the restart reason.
- No events are registered while off.
- The tab and the setup screen hold the new card.
