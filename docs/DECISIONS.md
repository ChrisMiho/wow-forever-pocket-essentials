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
- 0.0.1 drew the round button from plain coloured strips, and it looked
  pixelated on the device. From 0.0.2 it uses our own smooth circle image.

**Quest icons / data**
- Icon sizes: Small / Medium / Large = 22 / 28 / 36 px on the map, 14 / 18 /
  22 on the minimap. They are deliberately below the 48 px touch rule,
  because 48 px icons would bury the map; on the world map the tap area is
  exactly the icon.
- Tapping an icon shows a short text box (hover tooltips do not exist on a
  touch screen). It hides after 5 seconds. Since 0.0.2 a tap no longer picks
  the quest: picking by tap was awkward on the device.
- At most 150 icons on the world map and 40 on the minimap at once; at most
  300 places per objective (thinned evenly). Items that drop from more than
  60 kinds of creature (cloth, potions) show no icons.
- Dungeon objectives show an icon on the dungeon entrance.
- "Talk to" objectives are labelled "Explore" (there is no separate label).
- Since 0.0.2 the quest that matters is the one you **focus** in the quest
  log (Blizzard's own focus). "Show icons for" defaults to Tracked quests
  (the quest tracker's quests plus the focused one, since 0.0.3). "Focused
  quest" (with nothing focused, the tracker's quests) and "All quests" are
  the other choices. Added because the map was unreadable with every quest shown.
- The minimap haze is hidden again after every loading screen and zone
  change, and two seconds after each loading screen, because hiding it once
  at login did not work on the device.
- "Hide Blizzard's quest pins" was removed (see "left out").
- `/qd` still works for map, mini, haze, size, cluster and show.

**Quest arrow**
- Points at the focused quest only. With none focused it says "No quest
  focused / Focus one in your quest log" (since 0.0.3; 0.0.2 fell back to
  other quests). Current zone only; for a focused quest elsewhere it says
  "Outside this zone / Head to <zone>".
- With the objective more than 150 degrees off straight ahead it shows "Turn
  around" instead of an arrow pointing down (back below 135 degrees).
- Since 0.0.2 drawn from our own arrow picture (the line drawing had no
  real point). The old line drawing remains as a fallback.
- Five preset positions (Top, Upper middle, Lower middle, Left, Right), two
  sizes. It sits behind all windows and never takes taps.
- The arrow is relative to the way the character faces, not the camera.

**Bags**
- The combined-bag setting is never changed mid-session. With the Gamepad UI
  on, the game already forces the combined bag, so nothing is changed at all.
  With it off, the change is written at logout/reload and the panel shows
  "Reload now". Changing it live would make the game re-open bags inside our
  code, which risks "action blocked" when using items.
- The Sort button is a tall tab against the bag's left edge (since
  2026-11-16, spec `2026-11-16-vertical-sort-tab.md`), outside the window
  rather than inside it, so Blizzard's controller cursor does not treat it as
  an item slot. Reaching it with the d-pad is a later roadmap item.
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

**Layout** (the Layout helper was removed in 0.3.0; kept for the record)
- No nudge helper (see "left out").
- The Gamepad layout button refuses unless "Enable Gamepad UI" is on,
  because that layout hides the normal action bars otherwise.
- Every layout switch asks for a reload afterwards.
- Installing over an existing "Handheld" layout needs a second tap within
  20 seconds.

## Batch of 2026-11-15 (0.0.6)

Chosen by the owner: "Spots per objective" starts at 5, and the spot the arrow
points at always keeps its icon.

Made without the owner:
- The limit counts per objective per zone and applies to every icon kind,
  turn-in included.
- The first spot kept is the one nearest the middle of the spots, then the
  farthest-apart ones, so the icons cover the area.
- Trimming happens when quest data is rebuilt, never per frame.
- Spots are hidden from the icons only (marked, not deleted), so the arrow
  sees them all and still points at the truly nearest one.
- "Reload UI" has no confirmation, because a reload loses nothing.
- The icon key includes Explore.
- "Icon key" and "Reload UI" sit in the bottom section next to "Errors".

## Batch of 2026-11-17 (0.3.0)

Asked for by the owner: remove the Layout helper ("the controller schema
thing") if it is out of scope, and keep building lightweight features while
they are away.

Made without the owner:
- The Layout helper counts as out of scope: never tested, the game switches
  to its Gamepad layout by itself, and "Move things" covers placing our own
  pieces. The bundled handheld layout goes with it (now a non-goal).
- Saved leftovers of the Layout helper are ignored, not cleaned.
- The next feature is the arrow into other zones (top of "Parked ideas",
  marked wanted by the owner).
- It is a choice, "Quest in another zone", and starts on "Name the zone"
  (today's text), because the direction has not been checked on the device.
- Straight line only, same continent only. No routes, boats or flight paths.
- A light blue arrow, and the zone's name in front of the quest's, so it
  cannot be mistaken for the ordinary gold arrow.
- No "Here" and no setting aside for a spot in another zone.
- A map is only used when the game's conversion fits the map's known size
  within 5 %; otherwise the text stays. This is the guard against the
  confidently wrong arrow that got the first version removed.
- The test stand-in keeps four Edit Mode names for the restriction probe's
  tests; they are checked against the probe's file in the API audit.

## Rollback of 2026-11-17 (0.3.1)

Decided by the owner on seeing 0.3.0's report: take the arrow's "Quest in
another zone" choice out again and postpone it, to keep the addon light.
- Why: a straight line does not lead to the place where two zones connect.
  The game gives addons no list of crossings and the quest database has none.
- What a later version would need (not planned): a list of crossings, either
  written by hand (60 to 80 places, unchecked until walked) or learned by
  remembering where the player changes zone. The map conversion written for
  0.3.0 (`C_Map.GetWorldPosFromMapPos` sampled at two points per map, checked
  against the map's size) is in git at commit `608d3ff`, and the spec is
  `docs/superpowers/specs/2026-11-17-arrow-other-zones-and-layout-removal.md`.
- The Layout helper stays removed.

## Batch of 2026-11-17 (0.4.0)

Spec: `docs/superpowers/specs/2026-11-17-0.4.0-handheld-batch.md` (its
"Rulings" section). Built while the owner was away, at their instruction.

Said by the owner on 2026-11-17:
- **All features stay off by default.** "all settings remain off by default,
  i want to introduce a tutorial/setup flow with a few screens that educate
  and enable users to turn on what they want, that way they understand whats
  turned on and how it works." Nothing is switched on for the player; the
  setup guide is how a player learns what exists. This replaces the PRD's
  earlier "flip each default to on after its device test".
- **Chat text size is one small stepper, not a button per size** ("that's a
  lot of buttons"): Smaller, the size, Bigger. One press is one step through
  the game's own sizes (12, 14, 16, 18, 20, 24, 27) and then 30 and 34. The
  number is the size the game is using. The row shows whether or not "Big
  chat buttons" is on, and every chat window gets the size.
- **Bags: the game's one big bag box stays.** The complaint was that the
  pictures of the equipped bags are drawn inside the item grid, in a
  diagonal, and look like loose bags. They go to one row at the top, "like
  Bagnon". No bag window of our own.

Made without the owner:
- "D-pad to Sort" and "Bag icons" are choices inside "Bag sorter", and both
  start on the game's own behaviour (Off, "In the grid").
- "Menu background" is its own switch, off by default. In the setup guide it
  sits on the Quests screen, because the quest log's menu is where it is
  needed.
- If the device shows that the A button cannot be won from the bag's footer,
  "D-pad to Sort" stays off and the idea is dropped; the game's own bag menu
  already has "Clean Up Bags".
- "D-pad to Sort" and "Bag icons" both touch the bag's first column: the Left
  jump to the Sort tab is put on whatever item buttons end up in the first
  column after the bag pictures have been moved.
- Setup guide: B closes it, like every other window of ours (it does not go
  back a screen).
- Setup guide: only **Finish** and **Skip** are remembered, for the whole
  account. Close, B, Escape, another of our windows and the game closing its
  windows only hide it, and it comes back at the next login. Reason: the game
  closes every addon window of this kind on each loading screen, on death and
  on loss of control; if any closing counted as "skipped", the game could
  dismiss the guide before the player had read it.
- Setup guide: players who already use the addon see it once after updating,
  with their switches as they are. Nothing they switched on is touched.
- Setup guide: it opens about a second and a half after the first loading
  screen, not at login (the game closes such windows when the character
  enters the world), never in a fight, and at most once per login by itself.
  A fight that starts while it is open hides it; it comes back at the same
  screen afterwards unless another of our windows was opened meanwhile.
- Setup guide: a switch in it acts and saves at once, exactly as in the
  settings (one source of truth: `PE:GetModuleSwitch` and
  `PE:SetModuleEnabled`). Nothing waits for Finish.
- Setup guide: the two new bag choices and the chat text size are explained
  in the text and left to the settings; the guide has switches only. The
  settings window's option rows are drawn by code that belongs to that window
  (its own pools and layout), so showing them in the guide would have meant a
  second copy of that code.
- Setup guide: when the answer is already saved, no timer is started at
  login at all (the plan read the saved answer only when the timer fired).
  The answer is still read a second time when the timer fires.
- Opening the chat window closes the setup guide, so that only one Pocket
  Essentials window is open at a time (one line in `Chat.lua`).
- Offline tests: the test helper marks setup as skipped in the saved settings
  it hands to the addon, unless a test asks for a first run, so that the
  roughly 400 other tests do not get a window opening by itself.

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
- **A ready-made handheld layout.** (Dropped with the Layout helper in 0.3.0;
  now a non-goal.) The code to install one existed, but no
  layout is bundled: the player has to arrange the screen on the device and
  export it first (steps in `docs/TESTING.md`, step 9). Until then the panel says
  "No handheld layout saved yet".
- **Radial wheel entry.** Asked for: an entry on WoW Forever's controller
  radial wheel that opens the Pocket Essentials settings. The owner cut it
  from the 0.0.6 batch on 2026-11-15, then dropped it the same day while
  preparing the CurseForge launch. It is now a non-goal in PRD.md. What was
  found in Blizzard's interface source (`github.com/Gethe/wow-ui-source`,
  branch `forever`, build 1.60.1.70938, `Blizzard_Gamepad/UI/Radials/GamepadRadial.lua`
  and `.xml`): the wheel is the frame `GamepadRadial`. Its entries live in two
  plain tables on that frame, `segmentOptions` (one handler per entry) and
  `mainMenuPages` (three pages of eight slots; the right-hand page has five
  empty slots). There is no function for addons to register an entry, and the
  helper that builds entries (`BasicSegmentHandler`) is private to that file.
  The wheel is opened by a hidden Blizzard key binding (`OPENRADIAL`,
  `GamepadMode.OpenRadial`). So the only route is to write our own entry
  straight into Blizzard's tables. Not checked in game. The risk is the same
  kind that ruled out the Edit Mode nudge helper: values an addon writes into
  Blizzard's own tables are marked "touched by an addon", and the wheel reads
  those tables when it fills its slots and runs its entries (bags, spellbook,
  PvP and so on), so the game may later refuse some of those actions in combat
  with "interface action blocked". A client update could also rename the
  tables and break the entry. Options when it is picked up again: (a) a spike
  build for the device that adds one entry to an empty slot on the right-hand
  page, tested hard in combat for "action blocked" messages before deciding;
  (b) a key binding of our own ("Open Pocket Essentials settings") that a
  controller button can be mapped to in the game's key bindings, which needs
  no Blizzard table at all; (c) keep the round button, whose hold-to-open
  already works. Recommendation: (b) first, because it is the safe one.
- **Icons for quests not yet picked up** (like Questie's "!"). Dropped by the
  owner on 2026-11-15 to keep the addon focused on accepted quests. The hard
  part would have been correctness (quest chains, reputation and profession
  quests), not speed.
- **Arrow across zones.** (Built in 0.3.0 as a choice that was off by default, taken out
  again in 0.3.1; see "Rollback of 2026-11-17 (0.3.1)".) The arrow only points at objectives in the zone you
  are in. If the focused quest is elsewhere it says "Outside this zone"
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
