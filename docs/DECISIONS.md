# Decisions

This file holds the decisions made without the maintainer and what was left out of
version 0.0.1, and why. Goals live in PRD.md.

## Decisions made without the maintainer

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
  problem in the chat picker can never lock the player out.
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
- If the player switches back to separate bags in the game's own menu, the
  feature respects that.

**Vendor**
- No cap on how many greys sell per visit (the maintainer's choice, 2026-11-14; the
  first build stopped at 12). Only the last 12 sold can be bought back.
- The chat line reports the money gained during the visit, e.g. "Sold 7 junk
  items for 1g 20s 5c." and "Repairing for 12s 40c."
- An item must be grey according to both the bag slot and the item database,
  have a price, and not be locked. Bags the player marked "ignore for junk" in
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

## What was left out, and why

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
  layout is bundled: the player has to arrange the screen on the device and
  export it first (steps in `docs/TESTING.md`, step 9). Until then the panel says
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
  heavy and not verifiable for this build. **Revisit later**: the maintainer liked
  its radial wheels and its L3 bag sort (the L3 sort idea is in our bags
  feature already).
- Full Questie, TomTom, Bagnon, BetterBags and ForeverLazy were also
  considered and rejected (too heavy, unverifiable build, or no licence).
  The only third-party addon in the bundle is QuestieDB.
