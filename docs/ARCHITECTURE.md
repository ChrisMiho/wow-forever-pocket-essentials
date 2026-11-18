# Architecture

This file holds how Pocket Essentials is built, the game functions we could not
verify, and the facts we have checked. Goals live in PRD.md.

## Structure

One addon folder, one Lua file per part, no libraries.

```
addons/PocketEssentials/
  PocketEssentials.toc   interface 16001, one saved table PocketEssentialsDB, QuestieDB as optional dependency
  Core.lua        feature registry, saved settings, error catching and log, debug log, combat queue, /pe
  UI.lua          sizes for touch, big buttons, windows, controller navigation
  Move.lua        "Move things": saved offsets for our on-screen pieces, the small panel that nudges them
  Hub.lua         the round button and the minimap addon-list entry
  Settings.lua    the settings window and Errors page
  QuestData.lua   reads QuestieDB + the quest log into objective locations (shared, no switch of its own)
  QuestIcons.lua  feature: quest icons        (also keeps /qd working)
  QuestArrow.lua  feature: quest arrow
  Bags.lua        feature: bag sorter (key `bags`; called "One big bag" before 0.1.0)
  Vendor.lua      features: sell junk, repair (two switches)
  Chat.lua        feature: big chat buttons
  Icons/          three icon images from pfQuest/Shagu with their MIT notice,
                  plus our own arrow and circle (scripts/make_art.py --icons)

probe/PocketProbe/       the restriction probe: a separate addon for testing only. It tries each action
                         on the device and records whether the game allowed it. Built into
                         dist/PocketProbe.zip; never in the zips players get (docs/TESTING.md)
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
- The arrow chooses its spot once a second at most, never per frame. It
  knows a spot by its place on the map and its objective number (`pin.obj`),
  not by its table, because every quest-log change rebuilds the tables. A
  spot it has reached ("Here", then left) is set aside for 180 seconds in a
  small table that is only read in that once-a-second choice (0.1.0).
- Quest spots beyond "Spots per objective" are marked (`extra`) when quest
  data is rebuilt, never per frame. They are not removed: the icon code skips
  them (except the spot the arrow points at), while the arrow reads them all.
  The two ticks are unchanged.
- Our own on-screen pieces (quest arrow, chat prompt, round button) can be
  moved with the "Move things" panel (0.2.0). `Move.lua` keeps one offset per
  piece in `PocketEssentialsDB.ui.moved[key] = { x, y }` (720p pixels from the
  piece's preset) and a list of pieces; each piece adds its offset in its own
  layout and registers `{ key, label, order, available, apply, outline }`
  with `PE.Move:Register`. Nothing exists or runs until the panel is opened,
  and the only tick is the hold-to-repeat driver, live only while an arrow
  button is held (it stops itself after 8 seconds). The game's Edit Mode is
  never used.
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
     or `{label, action = function}`, with an optional `OnChange`; or a row
     of buttons with a value text, `{label, value = function(mod) -> text,
     buttons = {{label, action = function(mod)}, ...}}` (0.1.0, used by "Chat
     text size"; `buttons` may also be a function returning the list). An
     entry `{text = ...}` in that list is drawn as a short text at that place
     instead of a button (0.4.0: the number between "Smaller" and "Bigger").
     Any row may carry `always = true`: it is then also drawn while the
     feature is not on, so it must not need the feature (0.4.0, "Chat text
     size").
   - A feature that is on and has `options` gets a "Hide options" / "Show
     options" button in its row; the choice is saved in
     `PocketEssentialsDB.ui.folded[key]` (0.1.0). A feature that is not on
     gets one only when it has a row marked `always` (0.4.0).
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
   Debug log: one line per decision, never per frame, written as
   `if PE.debugOn then PE:Debug(key, text) end` so the text is not built while
   the log is off. Never a player's name or chat text; a value from the game
   goes through `PE.Plain(v)`, which writes a hidden one as `<secret>`.
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
| `debugstack(start, count1, count2)` taking line counts (only `debugstack()` / `debugstack(level)` appear in Blizzard's source) | Blocked-action report | The report names the blocked function but not our file and line |
| Whether `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` reach addon frames and carry the addon's name first (documented, untested here) | Blocked-action report | Nothing is reported; the game's own message and pop-up still appear |
| `C_Texture.GetAtlasInfo` and the `bags-button-autosort-up` atlas on this client | Bag Sort tab | The tab shows the letters without the icon |
| Whether a setting written at logout sticks (`combinedBags`) | Bags, only when the Gamepad UI is off | Bag does not combine; the row says to use the game's own bag menu |
| `GetChannelList`, `IsInGroup`, `IsInRaid` (source use only) | Chat | A channel button missing from the picker |
| Whether values set on the chat box by an addon stay "clean" for the game's secure commands. By the source, attributes (`SetChatType`, `SetTellTarget`, `SetChannelTarget`) carry no taint, but `ChatFrameUtil.OpenChat` called by an addon writes `ACTIVE_CHAT_EDIT_BOX` / `LAST_ACTIVE_CHAT_EDIT_BOX` tainted, and with the Gamepad UI on the chat frame's controller prompts are then set up by tainted code (`FloatingChatFrame.lua` `FocusGamepad`) | Chat | A typed `/cast` or `/target` right after using the picker is refused, or a controller focus change in combat is blocked and blamed on us, until a reload. If the device shows this: stop calling `OpenChat`, only set the box's target and let the player open chat |
| Blizzard's controller navigation hooks `CreateFrame` (`Blizzard_GamepadSmartNavigation/SmartNavigation.lua:260`); a frame of ours created in combat under a Blizzard panel that has controller focus makes it print "Interface action failed" | Quest icons (map icons are created as needed under the world map) | The chat message once, in combat with the map open; the blocked-action report names our line |
| `SetChatWindowSize` (called inside the game's `FCF_SetChatWindowFontSize`, no source to read): whether sizes above the game's own list (30, 34) are kept across a reload, and whether a chat window that is not in use accepts a size | Chat text size | The size falls back after a reload, or one window keeps its old size (each window's call is guarded on its own) |
| Whether calling `FCF_SetChatWindowFontSize` from addon code with the Gamepad UI on has an after-effect. By the source it only sets fonts and saves the size: no protected call, no edit box. Applied only out of a fight | Chat text size | A block report in the next debug log names it |
| `NUM_CHAT_WINDOWS` (defined in `Blizzard_DeprecatedChatInfo`, which this client may not load) | Chat text size | None: falls back to 10 windows |
| `CHAT_FONT_HEIGHTS` (FloatingChatFrame.lua:33, found by the audit; read only, copied each time the row is drawn or tapped): whether this client fills it | Chat text size | None: falls back to our own copy 12, 14, 16, 18, 20, 24, 27, and the debug log says so on a tap |
| `PADRSTICK` taken as an override binding while the bag is open (the key name is in `GamepadConstants.lua`; only `PADLSTICK` has run on the device) | Bag sorter, "Right stick click" | The right stick keeps its normal job; the Sort tab still works |
| `date("%H:%M:%S", time)` with a time argument (Blizzard's source only shows `date("*t", time)`; it is standard Lua) | Debug log time stamps | The stamp falls back to the old form (seconds and milliseconds from two clocks); guarded so a log line can never raise an error |
| Whether the controller's A release always reaches our navigation button during a long hold, whether A repeats while held, and whether a finger sliding off a button still sends its release | Move things, hold to repeat | A hold keeps moving until the 8-second stop or the screen edge (if the game also repeats A while it is held, until the button is let go or the edge); a single press still nudges |
| `GetLeft` / `GetRight` / `GetTop` / `GetBottom` read straight after `SetPoint` giving the new rectangle | Move things, the screen-edge rule and the panel's corner hop | A piece can be nudged partly off the screen, or the panel does not hop; Reset recovers |
| Whether a moved piece near a screen edge is covered by one of the game's own frames | Move things | The piece is hard to see there; move it or Reset |
| `debugstack` argument form; whether `C_UI.Reload` needs a real press (it is only ever called from one; see "Verified" for what the source shows) | Core | Shorter error details |

Checks that run offline (see `docs/TESTING.md`): `scripts/check.sh` compiles
every Lua file in the TOC under LuaJIT, which parses Lua 5.1 like the game.
`scripts/audit-api.sh` looks up every game name the addon uses in Blizzard's
interface source for this build and saves the result in `tests/api/`; the fast
check in `scripts/test.sh` fails on any name not in those files. The audit
checks methods by name, not per kind of frame, and does not check template
names, font names or script-type strings. The addon also runs against our own
stand-in game client (`tests/lib/fakeclient.lua`) in the rule tests and the
smoke test; the stand-in only knows what its authors believed about the game,
so a pass there is no proof of behaviour in the game. Nothing in this section
removes a row from the table above: those are still unconfirmed.

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
  The addon has not used Edit Mode since 0.3.0 (the Layout helper was
  removed); only the restriction probe still tries a layout switch.
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

### What the device allows (from the probe)

From the restriction probe (`probe/PocketProbe/`, `docs/TESTING.md`
"Restriction probe"). Produce the full table from a saved file with
`scripts/read-probe.sh <file> --markdown`.

Second file, 2026-11-17: probe 0.2.0, game 1.60.1 (70959), Gamepad UI on,
open world. Covered: no fight (automatic and from a press), in a fight
(automatic and from a press), a vendor, and the thirteen clean trials (each
the first thing after a reload). Not covered: a dungeon, the Gamepad UI off,
the game's sell-all-junk call (nothing was left to sell), a whisper arriving.

| Action by an addon | No fight | In a fight |
|---|---|---|
| Set the chat type on the closed chat box | allowed, no after-effects | allowed |
| Open the chat box (`ChatFrameUtil.OpenChat`, with or without a chat frame); give the edit box focus | goes through, but see below | not tried |
| Close the chat box (`ChatFrameUtil.DeactivateChat`) | blocked | not tried |
| Open and close the bags, alone after a reload | allowed, no after-effects | not tried |
| Set the active Edit Mode layout to the one already active, alone after a reload | allowed, no after-effects | not tried |
| Show, hide and create our own windows; a window registered for Escape | allowed | allowed |
| Create a button under the world map, the bag, the chat frame; re-attach it | allowed | allowed (re-attach) |
| Resize the bag | allowed | allowed |
| Take a controller button (override binding); mark a button for controller navigation | allowed | blocked |
| Sort the bags | allowed | allowed |
| Write the combined-bags setting | allowed | allowed |
| Sell a grey item with `C_Container.UseContainerItem`, no press | allowed | not tried |
| Repair with `RepairAllItems(false)`, no press | allowed | not tried |
| Read position, facing, map, quest log and objectives, bag items, money, repair cost, Edit Mode layouts, unit names | readable | readable |

The chat box is the one thing that does lasting harm. In the clean trials,
opening it from addon code looked allowed, but in the seconds after
`chat.open`, `chat.openframe` and `chat.close` the game began refusing its
own controller actions in the probe's name (`SetPreferredGamepadInteractTarget`,
`ClearTarget`, `SpellStopCasting`, `SpellStopTargeting`, and its "Interface
action failed" line), and kept doing so until the next reload. No other
clean trial had any after-effect. In the first file (probe 0.1.0) the bag and
focus trials were refused only because the chat trials had already run in the
same session.

Rules for the addon, from this:

- With the Gamepad UI on, never open, focus or close the chat box from addon
  code. Set the chat type and let the player open it (0.0.9 lends the A
  button to the game's own OPENCHAT binding).
- Controller buttons can only be taken or given back out of a fight.
- Selling and repairing from addon code need no button press.

Eighth device test, 2026-11-17 (Pocket Essentials 0.0.9, probe off, five
sessions, about twenty fights): no error and no blocked action. Lending the A
button to the game's OPENCHAT binding works for Say and Guild (a whisper is
untried). After a message is sent the chat box stays selected until B is
pressed; that is the game's behaviour and addon code must not try to change
it. 0.1.0 keeps all of this: its prompt is the addon's own frame under
`UIParent`, and "Chat text size" never touches an edit box.
