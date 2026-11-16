# Architecture

This file holds how Pocket Essentials is built, the game functions we could not
verify, and the facts we have checked. Goals live in PRD.md.

## Structure

One addon folder, one Lua file per part, no libraries.

```
addons/PocketEssentials/
  PocketEssentials.toc   interface 16001, one saved table PocketEssentialsDB, QuestieDB as optional dependency
  Core.lua        feature registry, saved settings, error catching and log, combat queue, /pe
  UI.lua          sizes for touch, big buttons, windows, controller navigation
  Hub.lua         the round button and the minimap addon-list entry
  Settings.lua    the settings window and Errors page
  QuestData.lua   reads QuestieDB + the quest log into objective locations (shared, no switch of its own)
  QuestIcons.lua  feature: quest icons        (also keeps /qd working)
  QuestArrow.lua  feature: quest arrow
  Bags.lua        feature: one big bag
  Vendor.lua      features: sell junk, repair (two switches)
  Chat.lua        feature: big chat buttons
  Layout.lua      feature: layout helper (experimental)
  Icons/          three icon images from pfQuest/Shagu with their MIT notice,
                  plus our own arrow and circle (scripts/make_art.py --icons)
```

How the pieces protect each other:
- Each feature registers itself with the core and is switched on and off by
  it. Loading, switching on, and every reaction to a game event run inside a
  safety net, so one feature failing cannot stop another or the settings
  window. Caught failures go to the Errors page (kept between sessions, at
  most 30).
- Nothing runs every frame while its feature is off. Only two things ever
  tick: the minimap icons (10 times a second, only while moving) and the
  arrow (10 times a second, only while it has something to point at).
- Quest spots beyond "Spots per objective" are marked (`extra`) when quest
  data is rebuilt, never per frame. They are not removed: the icon code skips
  them (except the spot the arrow points at), while the arrow reads them all.
  The two ticks are unchanged.
- Sizes are defined as pixels on a 720p screen and converted, so buttons stay
  the same physical size at 1080p. "Button size: Small / Medium / Large" in
  settings re-tunes everything without typing.
- If QuestieDB is missing or did not load, only the two quest features stay
  off and their rows say why.
- The old standalone `QuestDots` addon was folded in and its folder deleted.
  If an old `QuestDots` folder is still in AddOns on the device, the settings
  window says so and quest icons stay off until it is deleted.

## Adding a feature

1. Create `addons/PocketEssentials/MyFeature.lua`. It starts with
   `local ADDON_NAME, PE = ...` and ends by calling `PE:RegisterModule(def)`.
   `Vendor.lua` is a small example.
2. List the file in `PocketEssentials.toc`, after `Core.lua`. `scripts/check.sh`
   fails if a listed file is missing or does not compile.
3. The `def` table supports these fields (all read in `Core.lua` and
   `Settings.lua`):
   - `key` (required, unique text), `label` and `desc` (shown in settings),
     `order` (number that sorts the settings list; default 1000).
   - `requiresQuestieDB = true` keeps the feature off, and the row says why,
     when QuestieDB did not load.
   - `defaults`: a table of saved options, merged into `mod.opts` (stored in
     `PocketEssentialsDB.options[key]`). `options`: a list of rows for the
     settings window, each either `{key, label, choices = {{value, label}}}`
     or `{label, action = function}`, with an optional `OnChange`.
   - Lifecycle: `OnLoad(mod)` once at login, before anything is enabled;
     `OnEnable(mod)` when switched on, and at login if saved on;
     `OnDisable(mod)` when switched off. An error in `OnEnable` marks the
     feature failed, calls `OnDisable`, and shows the error on the Errors page.
4. A feature is off until the player switches it on (only a saved `true`
   enables it). Do not change that until the maintainer has tested it on the device.
5. The feature's switch row appears in the settings window by itself; no UI
   code is needed unless it has `options`.
6. Inside a feature use the module methods: `mod:RegisterEvent(event, fn)`
   (dropped automatically on switch-off), `mod:After(seconds, fn)` (cancelled
   on switch-off), `mod:Safe(fn, ...)`, `mod:Wrap(fn)`, `mod:RequestReload`.
   Use `PE:RunOutOfCombat(key, fn)` for anything the game blocks in combat,
   `PE:OnLogin(fn)` for code that must run after all features are loaded, and
   `PE:LogError(key, msg)` to record a problem on the Errors page. Any other
   callback (hooks, frame scripts) goes through `PE:Wrap(key, fn)` or
   `PE:Safe(key, fn, ...)`.
7. Tick budget: nothing runs every frame or on a timer while the feature is
   off. If it needs a tick (an `OnUpdate`), run it only while it has work, stop
   it in `OnDisable`, and keep it to about 10 per second like the two existing
   ticks.
8. Run `scripts/check.sh` and `scripts/test.sh`, then stop for the maintainer's
   device test. Log any game function you could not verify under "Unverified
   API".

## Unverified API

Everything the code calls was looked up in Blizzard's interface source for
build 1.60.1.70938 (`github.com/Gethe/wow-ui-source`, branch `forever`).
These are the things that could **not** be confirmed there. Each is guarded
so that being wrong cannot raise an error; the worst case is listed.

| What | Used by | If it is wrong |
|---|---|---|
| Which of two "priority" key overrides wins (ours on the panel vs Blizzard's gamepad ones) | Controller navigation in our windows; L3 sort | D-pad / A / B do nothing in our windows, or L3 keeps its normal job. Touch still works |
| Custom click names passed through override bindings | Controller navigation | Same as above |
| `GetPlayerFacing` direction convention (0 = north, counter-clockwise) | Quest arrow, rotating minimap | Arrow turns the wrong way. One marked line in `QuestArrow.lua` flips it |
| Minimap yards-per-zoom table (taken from the HereBeDragons library's values) and six zoom levels | Minimap icons | Icons drift toward or away from the centre as you walk |
| `IsIndoors()` as the indoor/outdoor minimap switch | Minimap icons | Same drift, indoors only |
| Default values of the minimap's quest-area ("haze") transparency (set inside the game engine) | Quest icons | Bringing the minimap haze back needs a reload; the panel asks for one |
| Whether the engine resets the minimap haze values when the world loads, and whether setting them again (alphas 0, ring scalars 0) on login, loading screens and zone changes hides it (0.0.1 did not hide it on the device) | Quest icons | The blue haze still shows on the minimap; no error |
| Whether our own TGA art (`Icons/arrow`, `circle`) loads and faces the right way on this client | Round button, whisper badge, quest arrow | A green square instead of the round button or arrow; text still works |
| Hiding the world-map haze by making its frame transparent | Quest icons | Haze stays visible on the world map. An alternative is noted in the file |
| `C_EncodingUtil` decode functions behave as QuestieDB expects; which of QuestieDB's two identical data files the client loads | QuestieDB itself | QuestieDB fails to load; quest features stay off and say why |
| `CanMerchantRepair`, `GetRepairAllCost`, `RepairAllItems`, `InRepairMode`, `SpellIsTargeting` (used by Blizzard's own vendor code but absent from the generated documentation, so their restrictions are unknown) | Repair, sell junk | Repair row shows "PROBLEM", or the game shows its own "blocked" message once |
| Whether selling (`C_Container.UseContainerItem`) or repairing needs a real button press on this client | Sell junk, repair | The game shows a "blocked by an addon" message at the vendor and nothing is sold/repaired |
| Whether a setting written at logout sticks (`combinedBags`) | Bags, only when the Gamepad UI is off | Bag does not combine; the row says to use the game's own bag menu |
| `GetChannelList`, `IsInGroup`, `IsInRaid` (source use only) | Chat | A channel button missing from the picker |
| Whether values set on the chat box by an addon stay "clean" for the game's secure commands | Chat | A typed `/cast` or `/target` right after using the picker is refused |
| Whether `C_EditMode.SetActiveLayout` / `OnLayoutAdded` called by an addon "taints" Edit Mode | Layout | Possible "action blocked" in combat until reload; the panel asks for a reload after every switch for this reason |
| `Enum.EditModePresetLayoutsMeta.NumValues`; English text of the "Enable Gamepad UI" setting | Layout | A status line reads slightly differently |
| `debugstack` argument form; whether `C_UI.Reload` needs a real press (it is only ever called from one; see "Verified" for what the source shows) | Core | Shorter error details |

Syntax check: all eleven Lua files parse as Lua 5.1 (checked by `scripts/check.sh`, which uses LuaJIT). Each file was also
run against a home-made imitation of the game's API to catch plain coding mistakes. That imitation only knows what its
authors believed about the game.

## Facts

### Verified (from source files or official releases, not in game)
- "Focus" in the quest log is Blizzard's super-tracked quest:
  `C_SuperTrack.GetSuperTrackedQuestID` / `SetSuperTrackedQuestID`, event
  `SUPER_TRACKING_CHANGED` (`QuestMapFrame.lua` quest menu). The quest
  tracker list is `C_QuestLog.GetNumQuestWatches` /
  `GetQuestIDForQuestWatchIndex`, event `QUEST_WATCH_LIST_CHANGED`.
- `Texture:SetRotation(radians)` turns counter-clockwise for positive values:
  Blizzard turns its map vehicle arrows with `SetRotation(facing)`
  (`VehicleDataProvider.lua`), and facing grows counter-clockwise.
- Addon interface number is `16001`. TOC suffixes `_Forever` / `_Camelot`
  exist.
- The client has its own gamepad interface (`Blizzard_Gamepad`,
  `Blizzard_GamepadSmartNavigation`, an "Enable Gamepad UI" setting, a
  radial menu, and a built-in "Gamepad" Edit Mode preset, third after Modern
  and Classic). Its window navigation binds the d-pad and face buttons
  itself whenever a Blizzard window has focus. It has no controller nudging
  inside Edit Mode.
- Gamepad key names: `PADDUP/DOWN/LEFT/RIGHT`, `PAD1` (bottom face button),
  `PAD2` (right face button), `PADLSTICK` (L3, auto-run by default).
- The Addon Compartment (addon list button) exists on this client.
- Bags: `ContainerFrameCombinedBags`, CVar `combinedBags`,
  `C_Container.SortBags` exist. With the Gamepad UI on, the game forces the
  combined bag, hides its sort button and puts "Clean Up Bags" in the
  backpack menu. `UpdateContainerFrameAnchors` resets bag scale on every
  layout pass. Neither the bag frame nor its item buttons are protected.
- Vendor: `MerchantSellAllJunkButton` exists, shown only when
  `C_MerchantFrame.IsSellAllJunkEnabled()` is true. No built-in auto-repair.
  Guild-bank repair exists; we never use it.
- Chat: whisper events are hidden from addons during "chat messaging
  lockdown" (dungeons, raids, PvP matches); `C_ChatInfo.InChatMessagingLockdown()`
  reports it.
- Edit Mode: `C_EditMode.GetLayouts`, `SaveLayouts`, `SetActiveLayout`,
  `OnLayoutAdded`, `ConvertStringToLayoutInfo` exist with no protected flag.
  Layouts carry an `interfaceStyle`; a layout of the other style cannot be
  chosen. Five saved layouts per type at most.
- QuestieDB has an official Forever build:
  <https://github.com/Questie/QuestieDB/releases>. Version 1.1.1 is the
  version we ship (Forever zip SHA-256
  `2527118d861e497fa40bdb6d061883bf09649d5f96e09de6885f578aefbb5e59`), pinned
  in `scripts/fetch-questiedb.sh` with a checksum. It is data only (no icons), includes
  nine translations chosen by client language, and stores its data inside
  its `.toc` files, so its folder must be named exactly `QuestieDB`.
- QuestieDB 1.1.1 is 37 MB unpacked. Most of that is one large data file
  shipped twice under two names, `QuestieDB_Forever.toc` and
  `QuestieDB_Camelot.toc`, still byte-identical in 1.1.1. The game loads only
  one, so we keep both. 1.1.1 is a data-only update: its `src/*.lua` files
  are byte-identical to 1.1.0.
- QuestieDB 1.1.1 provides interface ("contract") version 4; our code asks
  for 4. It holds 5,914 quests. The offline harness (`scripts/test.sh`, not the
  device) runs all of them through our quest-data code without an error;
  5,673 get at least one pin and 241 get none (no location data).
- QuestieDB's licence: the Questie team permits copying under GPL-3.0 terms
  but cannot speak for all past contributors. This repo ships their release
  unmodified with licence files intact. Re-read `LICENSE.md` inside the
  release before distributing a modified (trimmed) copy.
- The three objective icon images come from pfQuest (Shagu), MIT licence;
  the notice is in `addons/PocketEssentials/Icons/MIT.txt`. That notice
  covers only `loot_mono`, `object_mono` and `slay_mono`; `arrow` and
  `circle` are original art drawn by `scripts/make_art.py --icons`.
- `C_UI.Reload` is in the generated documentation
  (`Blizzard_APIDocumentationGenerated/UIManagerDocumentation.lua`) with no
  restriction listed, and Blizzard calls `ReloadUI` from its own button clicks
  (`Blizzard_ScriptErrorsFrame/Blizzard_ScriptErrorsFrame.xml`). We only ever
  call it straight from a tap (the "Reload now" bars and the "Reload UI"
  button).
- 0.0.3 on the device: swapping the minimap's quest blob textures for our
  `Icons/blank.tga` turned the minimap solid green when a focused quest had a
  quest area. Removed in 0.0.4.

### Unverified (do not rely on these without testing)
- Everything under "Unverified API" above.
- Whether any of version 0.0.2 works on the device (0.0.1's first quest test:
  see PRD.md "Status").
- Which of the two QuestieDB data files the client loads.
- Whether quests under a collapsed header in the quest log are still seen
  (if not, their icons vanish while collapsed).
- How long QuestieDB takes to load on the handheld.
