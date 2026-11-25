# Architecture

This file holds how Pocket Essentials is built, the game functions we could not
verify, and the facts we have checked. Goals live in PRD.md.

## Structure

One addon folder, one Lua file per part, no libraries.

```
addons/PocketEssentials/
  PocketEssentials.toc   interface 16001, PocketEssentialsDB (account-wide) and PocketEssentialsCharDB (per character: each one's old layout, the whisper list since 0.15.0), QuestieDB as optional dependency
  Core.lua        feature registry, saved settings, error catching and log, debug log, combat queue, /pe
  UI.lua          sizes for touch, big buttons, windows, controller navigation
  Move.lua        "Move on screen" (was "Move things" until 0.8.0): saved offsets for our on-screen pieces, the small panel that nudges them
  Hub.lua         the round button and the minimap addon-list entry
  Settings.lua    the settings window, its Errors and Debug log tabs; the list drawer both windows draw options with
  Setup.lua       the setup guide: screens that explain each feature with its switch and options (no switch of its own)
  QuestData.lua   reads QuestieDB + the quest log into objective locations (shared, no switch of its own)
  QuestIcons.lua  feature: quest icons        (also keeps /qd working)
  QuestArrow.lua  feature: quest arrow
  Bags.lua        feature: bag sorter (key `bags`; called "One big bag" before 0.1.0)
  Vendor.lua      features: sell junk, repair (two switches)
  Chat.lua        feature: Chat picker (key `chat`; "Big chat buttons" until 0.8.1)
  MenuBackground.lua  feature: menu background (key `menuBg`): a dark panel of ours behind the game's pop-up menus
  LootSparkles.lua    feature: loot sparkles (key `sparkles`): keeps the engine setting `outlineModeShowLootEffectWhenDisabled` at 1
  ControllerLayout.lua  feature: Controller layout (key `ctrlLayout`): the plan's numbers (PE.LayoutPlan), the Edit Mode layout, the game's bars, the option rows, Save a snapshot
  FaceBars.lua        part of Controller layout: our spell pictures over the game's invisible bars (PE.FaceBars; no switch of its own)
  SlimBars.lua        part of Controller layout, row "Slim bars" (Off by default; since 0.20.0 the row "Names on the bars": whole names or first names): flat bars for player, pet, target, target of target and the target's cast over the game's invisible unit frames (PE.SlimBars; never called in a session that began with the row Off)
  Arrange.lua         part of Controller layout, row "Arrange it yourself" (Off by default): the Arrange window and its rules (steps, mirrored twins, the centre snap, the overlap warning, Apply); the offsets are added inside PE.LayoutPlan (Plan.Moved: a piece's built-in amount, Plan.BASE_2, since 0.20.0 the arrangement of the first device sitting, plus its saved offset, Plan.Offset; offsets saved by 0.18.0 and 0.19.0 are carried over once, Plan.MigrateBase) (PE.Arrange; never called in a session that began with the row Off)
  MapLook.lua         part of Controller layout, row "Map look" (Round by default): the square map: the square mask on the Minimap widget, the map's frame lowered inside its Edit Mode piece, the black edge, the place name, clock and coordinates inside the map, the game's strip hidden; the numbers are in PE.LayoutPlan (Plan.MAP_SQUARE, Plan.MapBox) (PE.MapLook; with Round and nothing placed every call returns at once)
  ErrorCatcher.lua    feature: Catch all errors (key `errors`): other addons' and the game's errors in PocketEssentialsDB.otherErrors (at most 50), the Errors tab's viewer reads them; stands aside for BugSack, BugGrabber and Swatter
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
  tick: the minimap icons and the arrow (10 times a second, only while it has
  something to point at). The minimap icons' OnUpdate runs every frame while
  the map the player is on has icons that "Show icons for" lets through; it
  only adds up the time, and every 0.1 s it reads the position, facing, zoom
  and minimap size. The icons are placed again only when one of those
  changed, so standing still costs those reads and nothing more.
- The arrow chooses its spot once a second at most, never per frame. It
  knows a spot by its place on the map, its objective number (`pin.obj`) and, since 0.15.0, its kind,
  not by its table, because every quest-log change rebuilds the tables. A
  spot it has reached ("Here", then left) is set aside for 180 seconds in a
  small table that is only read in that once-a-second choice (0.1.0).
- Quest spots beyond "Spots per objective" are marked (`extra`) when quest
  data is rebuilt, never per frame. They are not removed: the icon code skips
  them (except the spot the arrow points at), while the arrow reads them all.
  The two ticks are unchanged.
- Our own on-screen pieces (quest arrow, chat prompt, round button) can be
  moved with the "Move on screen" panel (0.2.0 as "Move things"; renamed in 0.8.0; the position presets were replaced in 0.8.0 by "Move the arrow" and "Move the round button", which open it). `Move.lua` keeps one offset per
  piece in `PocketEssentialsDB.ui.moved[key] = { x, y }` (720p pixels from the
  piece's preset) and a list of pieces; each piece adds its offset in its own
  layout and registers `{ key, label, order, available, apply, outline }`
  with `PE.Move:Register`. Nothing exists or runs until the panel is opened,
  and the only tick is the hold-to-repeat driver, live only while an arrow
  button is held (it stops itself after 8 seconds). The game's Edit Mode is
  never used.
- The setup guide (`Setup.lua`, 0.4.0) is a window like the settings, built
  from one table of screens (`SCREENS`: id, title, text, and rows of
  `{ key, title, text }`). A row is shown only when its feature is registered,
  and a screen whose rows are all missing is left out. Its switches read
  `PE:GetModuleSwitch(key)` and write through `PE:SetModuleEnabled`, the same
  two calls the settings window uses, so the two cannot disagree; it never
  writes the saved on/off table itself. Since 0.5.0 a feature's options are
  drawn under its switch by the list drawer of `Settings.lua`
  (`PE:NewListDrawer({ child, navList })`: pools of reused widgets, `Card`,
  `Row`, `ChoiceRow`, `ActionRow`, `FeatureCard`, `Options`, `Text`,
  `Button`, `Switch`, `Segmented`, `Number`, `Divider`, `Status`). The
  settings window makes one drawer and the guide makes another, so there is
  one implementation of option rows and both windows save through the same
  closures. The only thing it saves is
  `PocketEssentialsDB.setup`: `"finished"`, `"skipped"`, or nothing (never
  answered; any other value reads as nothing). It opens by itself from one
  1.5-second timer after the first `PLAYER_ENTERING_WORLD` of a login, and
  only when that field is empty and the saved settings really loaded. Nothing
  is built before the first opening and it has no per-frame code. While open
  it listens for `PLAYER_REGEN_DISABLED` (a fight hides it); while closed it
  listens for nothing, except one `PLAYER_REGEN_ENABLED` wait after a fight
  hid it or kept it from opening at login. It redraws with the settings
  window: it wraps `PE:RefreshSettings`, which is why it loads after
  `Settings.lua`.
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
     instead of a button (0.4.0: the number between "Smaller" and "Bigger"; since 0.7.0 the number sits between "-" and "+").
     Any row may carry `always = true`: it is then also drawn while the
     feature is not on, so it must not need the feature (0.4.0, "Chat text
     size").
   - A feature that is on shows all its `options` rows under its switch.
     There are no fold buttons since 0.9.0. A feature that is not on shows
     only rows marked `always` (0.4.0).
   - Lifecycle: `OnLoad(mod)` once at login, before anything is enabled;
     `OnEnable(mod)` when switched on, and at login if saved on;
     `OnDisable(mod)` when switched off. An error in `OnEnable` marks the
     feature failed, calls `OnDisable`, and shows the error on the Errors page.
4. A feature is off until the player switches it on (only a saved `true`
   enables it). That does not change after a device test: every feature stays
   off by default (the maintainer's ruling of 2026-11-17, `docs/DECISIONS.md`).
5. The feature's switch row appears in the settings window by itself; no UI
   code is needed unless it has `options`. For the setup guide, add one row
   `{ key = "myFeature", text = "..." }` to the fitting screen in `SCREENS`
   at the top of `Setup.lua`: a few plain sentences about what the player
   will see. A feature with `options` gets a screen of its own, because the
   options are drawn under its switch by themselves (nothing to add for
   them); a sentence in the text is only for a choice that needs explaining.
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

## Measuring hook

`Core.lua` ("Measuring") has a timing hook for the performance recorder in
Pocket Probe (`docs/superpowers/specs/2026-11-21-perf-recorder.md`). It is
asleep for players: nothing in Pocket Essentials calls it, and there is no
setting, slash command, event, ticker or frame for it. While it is off, each
run through `PE:Safe`, `PE:Wrap`, `mod:Safe`, `mod:After` and the event
dispatcher tests one local boolean and then runs the same code as before.

- `PE:StartMeasure()` switches it on and returns the counters. A second call
  returns the same table and keeps its numbers. It returns nil, and changes
  nothing, on a client without `debugprofilestop`.
- `PE:StopMeasure()` switches it off. The counters are kept.
- `PE:MeasureCounters()` returns the counters, or nil if measuring was never
  started this session.
- `counters[key] = { ms, calls, max, events = { [event] = { ms, calls } } }`
  for each feature key (the same key the error log uses; `events` only for
  keys the event dispatcher has timed), and `counters["*"] = { ms, calls, max }`
  for outermost runs only. A run inside another run is counted under both
  keys, so the per-key rows overlap; `"*"` is the total with nothing counted
  twice.
- Nothing is saved. After a reload measuring is off and the counters start
  from zero.
- An error goes through the same handler as with measuring off, and the time
  up to the error is counted.
- Not timed: a feature's `OnEnable`, `OnDisable` and `OnLoad`, `PE:OnLogin`
  functions and `PE:RunOutOfCombat` functions when they are not inside a timed
  run, and the `/pe` command.

## Calls into Blizzard's Lua

Rule (0.16.4, from the refused controller actions of 0.16.0 to 0.16.2):
**before calling a function Blizzard wrote in Lua, read it. If it writes a
field on a frame or table of the game's, or a global, do the same thing with
the frame's own engine methods instead.** A value written by Lua that the
addon called carries the addon's mark; when the game's own protected code
reads it later, the game refuses its own actions in the addon's name until a
reload. `hooksecurefunc` and `HookScript` are fine (a hook is not a call);
`SetScript` on a game frame and assigning a field on a game frame or table
are not.

- **A refusal's call stack does not name the cause.** The game refuses its
  own action when its protected code reads the marked value, long after the
  call that marked it, so the stack names the game's function and not the
  addon's line. What found the chat's box in 0.16.2 was a row for each part of
  the layout (hint box, chat box, map ring and buttons, the game's bars,
  targeting pictures, spell pictures), each On or Off from the next reload,
  tried on the device one at a time (plan
  `2026-11-24-blocked-action-0.16.1.md`). 0.20.0 removed those rows; if
  refused actions come back, add such rows again for the hunt.
- The check: `tests/taint/audit.lua`, run by `scripts/test.sh`. It lists every
  name the addon and the probe call (or name in a string) that Blizzard
  defines as a Lua function, and each needs a line in `tests/taint/calls.txt`:
  `clean`, `ours`, `engine`, `writes-known` (kept, with the reason) or
  `writes` (fails). A new call fails until it is read and listed.
  `luajit tests/taint/audit.lua . --list` shows the call sites.
- Its limits: it matches by name. It does not see a function reached through
  a variable or a dotted string (`ChatFrameUtil.GetActiveWindow` in `Chat.lua`,
  the probe's `Find("...")`), nor the game's own script handlers that run when
  an engine method shows, hides or focuses a game frame.
- **Edit Mode's frames are a trap.** On every Edit Mode system frame
  (`MinimapCluster`, `GamepadMainActionBarFrame`, `GameTooltipDefaultContainer`,
  the unit frames and others) the game replaces `SetScale`, `SetPoint`,
  `ClearAllPoints`, `SetShown` and `Hide` with Lua of its own
  (`Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:11-36`). No current
  code calls one of those five on such a frame (the frames moved are the bar
  anchors, the bag, `totFrame` and textures). The slim bars (0.17.0) call
  `SetAlpha` and `GetAlpha` on the three unit frames and `totFrame`: those two
  are not among the five and no mixin of the frames defines them, so they are
  the engine's (the stand-in client fails a test that calls one of the five
  on a unit frame). A future `MinimapCluster:SetScale`
  would be a Lua call that the check passes as `engine` unless the line is read
  again.
- **Arrange it yourself (0.18.0) adds no call into Blizzard's Lua.** A piece
  the game places from its Edit Mode layout is moved only by rewriting our
  layout's numbers and a reload (the option rows' path); a live piece by the
  placement calls `PlaceNow` already makes. `Arrange.lua` calls no game
  frame at all. Moving one spell wheel alone would need a field written on
  the game's button (`anchorInfo`), so it is not offered.
- **The square map (0.19.0, `MapLook.lua`) adds no call into Blizzard's Lua.**
  It calls engine methods only, each through `pcall`, out of a fight:
  `Minimap:SetMaskTexture` (the map widget's own; the Lua function of that
  name is the world map canvas's); `ClearAllPoints` and `SetPoint` on
  `MinimapCluster.MinimapContainer` (a plain frame, the one the game itself
  re-anchors in `SetHeaderUnderneath`) and on its `PlayerCoords`;
  `SetFrameLevel` on `PlayerCoords`; `Hide` and `Show` on
  `MinimapCluster.ZoneTextButton`, `TimeManagerClockButton` and
  `PlayerCoords` (no Lua `Hide` or `Show` on them and no `OnShow` / `OnHide`
  script). `MinimapCluster` itself, the Edit Mode system, is only read.
  `MinimapCluster.SetHeaderUnderneath` is hooked (`hooksecurefunc`), never
  called. The time, the place name and its colour come from the calls the
  game's own strip makes (`GetGameTime`, `GetMinimapZoneText`,
  `C_PvP.GetZonePVPInfo`), not from `GameTime_GetTime` or `Minimap_Update`.
  One trap found on the way: **`GetCVarBool` is Lua on this client**
  (`Blizzard_SharedXMLBase/CvarUtil.lua:33`; it only returns
  `C_CVar.GetCVarBool`), so `C_CVar.GetCVar` is asked instead. No field is
  written on a game frame. Each call has its line in `calls.txt`.
- **0.20.0 adds no call into Blizzard's Lua.** Whole names on the slim bars
  come from two engine functions, each through `pcall`: `UnitName` (already
  used, now with its second answer); the separator is read from the
  engine's `Constants` table. The game's own Lua helpers for the same job
  (`GetUnitName`, `NameUtil.FormatUnitNameForDisplay`,
  `NameUtil.GetUnitFirstName`) are read, not called. Only our own font
  strings are written. The built-in arrangement and the carrying over of
  saved offsets are sums on our own saved tables; the pieces are placed by the
  calls `PlaceNow` already made, at other numbers. The spell wheels' piece
  moves `PageUnit.BottomCenteredAnchor` with the same three engine calls as
  since 0.12.0 (`ClearAllPoints`, `SetScale`, `SetPoint`). The one hook that
  went: `hooksecurefunc` on `PageUnit.SetActiveActionBar`.
- Calls that write and are kept (2026-11-24; the reason for each is in
  `calls.txt`). None is part of the Controller layout, and a session with all
  of them and no layout showed no refusal (plan
  `2026-11-24-blocked-action-0.16.1.md`, session 3):
  - `Core.lua`: `DEFAULT_CHAT_FRAME:AddMessage` (every chat line; the chat
    window is Lua on this client and keeps the line in its own list) and
    `print` as its fallback. No engine-only way to put a line in chat.
  - `Chat.lua`: `FCF_SetChatWindowFontSize` (font fields on the chat window)
    and `ChatFrameUtil.OpenChat` (the game's globals for the active chat box;
    already a rule above: never with the Gamepad UI on).
  - `MenuBackground.lua`: `EventRegistry:RegisterCallback` /
    `UnregisterCallback` (our function in the game's callback table, which the
    game calls behind its own barrier).
  - `Bags.lua`: `SmartNavigation_AddJumpNavigationOverride` and
    `SmartNavigation_ClearJumpNavigationOverridesInDirection` (a field on the
    bag's buttons, written by the game's own secure helper, not in the addon's
    name: `Blizzard_GamepadSmartNavigation/SecureHelper.lua:46-74`).
  - The probe (a test tool): its deliberate trials, and its fight watch's
    `RegisterActiveActionBarUpdatedCallback`.
- The one kept call that is part of the Controller layout: `FaceBars.lua`
  registers a callback with `PageUnit:RegisterActiveActionBarUpdatedCallback`
  (our function written into the game's callback table). It stays the default:
  it ran on the device on 2026-11-24 (0.16.2 and 0.16.3, spell pictures on, no
  refused action), and the game keeps and runs such callbacks behind its own
  barrier (`SecureInsertEvent`, `secureexecuterange`, `securecallfunction`,
  `Blizzard_SharedXMLBase/CallbackRegistry.lua`). 0.16.4 had an engine-only
  way behind a row, a `hooksecurefunc` on `PageUnit.SetActiveActionBar`; it
  was never run on a device and 0.20.0 removed it with the seven "Part: ..."
  rows (the six that left a part of the layout out were for the hunt above;
  the method is in "A refusal's call stack..." above).

## Unverified API

Everything the code calls was looked up in Blizzard's interface source for
build 1.60.1.70938 (`github.com/Gethe/wow-ui-source`, branch `forever`), and
checked again against build 1.60.1.71091 (commit `c01a87b`, the build the API
audit is pinned to): of the files the addon relies on, three changed, and none
of the changes reaches the addon (spec `2026-11-24-0.16.4-cleanup.md`, 9).
These are the things that could **not** be confirmed there. Each is guarded
so that being wrong cannot raise an error; the worst case is listed.

**First device sitting of 0.16.4 to 0.18.0, 2026-11-25** (free play on a
warlock with a pet, one 56 second fight; the numbered steps of TESTING 31-33
were not walked through): Slim bars and Arrange it yourself were On, the saved
file holds no refused action and no stopped bar, the bars followed the fight,
the game's four unit frames stayed invisible, the tap guards took the taps,
live moves and Apply with a reload put the pieces (the map and the buffs
among the Edit Mode ones) where the plan said, and the Arrange window was
usable with the controller. The rows below for those points held in that
sitting; they stay listed until a longer test (other classes, a vehicle, a
group, the spell wheels moved) has been done.

| What | Used by | If it is wrong |
|---|---|---|
| `Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8")` from addon code gives a square map, and that file exists on this client. The method is the engine's (`MinimapFrameAPIDocumentation.lua:141`); the game's only call gives `ui-hud-minimap-frame-generic-mask` (`Blizzard_Minimap/Camelot/Minimap.lua:11, 42`). New in 0.19.0, only with "Map look" on Square | Square map (`MapLook.lua`) | The map stays round at 100% with a square edge round it, and the words in the corners sit outside the circle. If the call raises, the fallback draws the round map's disc and the card says so; a call that is silently ignored cannot be told apart from one that worked |
| Nothing but `MinimapClusterMixin:UpdateMinimapConfig` gives the round mask back (the only `SetMaskTexture` call on the map in the source, `Camelot/Minimap.lua:42`; hooked since 0.16.0) | Square map | The map turns round until the next placement; the debug log shows no "given again after a redraw" line at that moment |
| The game's quest areas, the player arrow and the group dots draw into the corners of a square mask | Square map | Corners are empty, or the game's own icons are cut at the old circle (our quest icons are placed by us and are not) |
| An Edit Mode piece is held wholly on the screen (`clampedToScreen` on `EditModeSystemTemplate`, `Blizzard_EditMode/Shared/EditModeSystemTemplates.xml:4`, its room the selection box that covers it, `.lua:174-185`), so `MinimapCluster` cannot be written lower than the screen's bottom edge; and an engine `SetPoint` on `MinimapCluster.MinimapContainer` (BOTTOM on the cluster's BOTTOM, the game's own anchor with the strip underneath, `Camelot/Minimap.lua:72-73`, with a lower y) holds until the game anchors it again in `SetHeaderUnderneath` (hooked: lowered again, out of a fight) | Square map: the map's bottom 5 up instead of 57.5 | The map sits 52.5 higher than planned, over the swing timers, with an empty gap under it; the snapshot's "round map" and "map's edge" lines show it. If the first half is wrong (no holding on the screen), nothing is lost: the lowering still gives the same spot |
| The map's frame at Edit Mode Size 100% is the 253 frame measured at 70% with the 198 map at its centre. `MapLook.lua` reads the frame's height, the map's height and the scale on the spot, so another size only moves the edge by what the reading says | Square map | The edge box is a few units off the plan's -100..100 by 4..204; the debug line "the edge's box" and the snapshot show by how much |
| `Hide` on `MinimapCluster.ZoneTextButton` and `TimeManagerClockButton` (no Lua `Hide`, no `OnHide` script; nothing in the game's Lua shows either again), and what `MinimapCluster`, a resizing layout frame, does when its strip is hidden (it works out its size from its shown children the next time Edit Mode lays it out, `EditModeSystemTemplates.lua:1794-1797`) | Square map: the strip hidden | The strip or the clock shows again under or over the map until the next placement; or the map's Edit Mode box changes size, which could shift the map by a few units. The snapshot's "map" line shows the box |
| An engine `SetPoint` and `SetFrameLevel` on `MinimapCluster.MinimapContainer.PlayerCoords` hold, and its text then draws over the map (it is a sibling of the map widget, moved from 18 under the map into its bottom left corner and raised 10 levels over it). Only tried while the game's own `minimapShowPlayerCoords` setting is on; the next placement reads the point back | Square map: the coordinates | The game's text is under the map or back under it: at the next placement the addon hides it and draws its own (debug line "coordinates: our own text ... (the game moved its own text back)"). A text hidden under the map cannot be noticed by the addon: with the game's option on and no coordinates showing, that is the cause |
| Font strings on a frame of ours that is a child of the map widget draw over the map, at frame level map + 10, and the frame takes no taps from the map (`EnableMouse(false)`). Our quest icons are children of the map widget too (device-proven) | Square map: the words | A word is missing or under the quest icons; or a tap on the map (a ping) is swallowed |
| A live move places the whole layout again at every tap (`mod:ArrangePlace` is `SyncBars`, so `PlaceNow` in `ControllerLayout.lua`), out of a fight. Per tap, on the game's regions: `C_EditMode.GetLayouts` (read); `Put` on `PageUnit.TopCenteredAnchor`, `LeftCenteredAnchor`, `RightCenteredAnchor`, `BottomCenteredAnchor` and `BottomCenteredAnchor.Bar` (`ClearAllPoints`, `SetScale`, `SetPoint`; a second time at full size while the spell pictures are off); `PlaceExtras` on the two shoulder textures and `TargetFrame.totFrame` (`ClearAllPoints`, `SetPoint`); `PlaceChat` (`Hide` on every chat box texture that shows); `PlaceRing` (`Hide` on the compass texture and its underlay if shown, and size reads on `Minimap`); `PlaceButtons` (`Hide` on the map's tracking, calendar and addon-count buttons if shown and the row hides them); `PlaceHints` (the hint box setting, only if its row was tapped since); with Slim bars On, `GetAlpha` on the four unit frames and `SetAlpha(0)` only on one that is not already 0, and position reads on them for the tap guards. Then our own frames: the map's disc, the PE button, the spell panels and their tap guards, the slim bars. Every one of these calls has run on the device at each login and layout event (0.12.0 to 0.16.x; the slim bars' never yet), but never many times in a minute. New in 0.18.0, only with "Arrange it yourself" On and the window in use | Arrange it yourself (`Arrange.lua`, `mod:ArrangePlace`) | "Interface action blocked", or the game refusing its own actions until a reload. Do not use the window; or switch "Arrange it yourself" Off and reload: `Arrange.lua` is then never called and nothing is placed more often than in 0.17.0 |
| The game puts each Edit Mode piece at its built-in spot plus the saved offset after Apply and a reload. The path is the option rows' (`RewritePieces`, `C_EditMode.SaveLayouts`, then a reload), device-proven for the unit frames, the chat and the tooltip by the Spell panel size row; new is that the map, the swing timers, the XP bars, the buffs and the quest list are rewritten after the layout was first built, and that the offsets are the player's (`EditModeSystemTemplates.lua:373-375` places from `anchorInfo.offsetX / offsetY`) | Arrange it yourself: Apply | A piece does not move, or lands somewhere else. "Start over" rebuilds the layout; "Reset all" and Apply puts every piece back; the switch Off and a reload is the built-in arrangement |
| The spell wheels open where the sub-menu buttons are after `PageUnit.BottomCenteredAnchor` is moved up or down (the game pins a wheel on its button's centre each time it opens, `Blizzard_GamepadActionBars/FlyoutRadial.lua:218-220`; the buttons and prompts are anchored to that frame, `MainActionBarFrame.xml:94-135`, and re-anchored to it from the spot read at load, `ClassActionFlyout.lua:24-25, 50-54`). The anchor has been placed at 0, 238 on the device since 0.12.0, never anywhere else | Arrange it yourself, the piece "Spell wheels and their buttons" (0.20.0: always in the Arrange window; until 0.19.0 behind the row "Arrange: spell wheels"). Still unproven on a device | The buttons, prompts or wheels do not follow, or follow apart from each other. Reset that piece in the Arrange window: the anchor is back at 0, 238 at once, where it is placed whenever the piece has no offset (the calls are then 0.19.0's, a test compares them) |
| The Arrange window on the device: its size on the 720p screen, that the d-pad reaches every button (`UI:AttachNav`, as every window of the addon), and that the outlines (frames of ours on the FULLSCREEN strata that take no tap) show over the pieces | Arrange it yourself | A button cannot be reached with the controller (touch still works), or the window covers the piece being moved. Nothing of the game's is involved |
| Our own spell panels and slim bars placed again after a live move (`FaceBars.lua` "Place": `ClearAllPoints`, `SetPoint`, `SetSize` on its own halves and tap guards; `Arrange.lua` on the slim bars' own frames), out of a fight | Arrange it yourself | A panel or bar stays at its old spot until the next reload, where everything is built at the moved spots anyway |
| `SetAlpha(0)` on `PlayerFrame`, `PetFrame`, `TargetFrame` and `TargetFrame.totFrame`, out of a fight, read first with `GetAlpha` and put back when the bars stop. The engine's own method by the source (Edit Mode replaces only `SetScale`, `SetPoint`, `ClearAllPoints`, `SetShown`, `Hide`: `Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:11-18, 33-36`; no Lua `SetAlpha` on these frames), not protected in the documentation (`SimpleFrameAPIDocumentation.lua:1134`). Device-proven only on the gamepad bar anchors, never on unit frames. New in 0.17.0, only with "Slim bars" On | Slim bars (`SlimBars.lua`) | The game refuses its own actions in the addon's name until a reload, as 0.16.0's chat box did; or "Interface action blocked" once. Switch "Slim bars" Off and reload: the file is then never called |
| That the unit frames stay invisible once set: no game code sets their see-through (Edit Mode's Opacity is applied only to the party, raid and arena frames, `EditModeSystemTemplates.lua:1586-1591, 1654`; `Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:303, 328, 365`), but a fight, a vehicle or a zone change has not been watched on a device | Slim bars | A game frame shows again under or beside our bar. It is set to 0 again at the next world load or placement (debug line "made invisible again"); the snapshot shows each frame's see-through |
| `StatusBar:SetMinMaxValues`, `StatusBar:SetValue` and `FontString:SetText` take a hidden ("secret") number or text from addon code in a real fight (documented `SecretArguments = "AllowedWhenTainted"`, `SimpleStatusBarAPIDocumentation.lua:229, 355`, `SimpleFontStringAPIDocumentation.lua:664`; `SetText` with a hidden number rather than text is the least certain) | Slim bars: health, power, the health number, names, the cast's times | That bar or text stops changing, or stays empty, during fights; the debug log names the refused call once. No error reaches the player |
| `UnitExists`, `UnitLevel`, `UnitCanAttack`, `UnitIsTapDenied` and `UnitPowerType` answer plainly in a fight (not marked as hidden in `UnitDocumentation.lua:763, 1192, 2365, 2474, 2859`) | Slim bars: which bars show, the colours, the level | A bar keeps the state or colour it had; the debug log says once which answer was hidden |
| `UnitCastingInfo` / `UnitChannelInfo`: the sixth answer, `isTradeskill`, is there exactly while the unit casts and is never hidden (`UnitDocumentation.lua:845, 887`); the two times count on the same clock as `GetTime() * 1000` (the game's own bar subtracts them, `Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua:396-401`); a status bar whose two ends are hidden numbers still fills from a plain value | Slim bars: the target's cast bar | The cast bar never shows, shows full or empty at once, or (if the info outlives the cast) stays up to half a second too long |
| `RegisterUnitEvent` on an addon's frame delivers `UNIT_HEALTH`, `UNIT_POWER_UPDATE`, `UNIT_TARGET`, the `UNIT_SPELLCAST_*` events and the rest for "player", "pet" and "target", also in a fight (`SimpleFrameAPIDocumentation.lua:1064`; the game's own frames register the same way, `Blizzard_UnitFrame/Mainline/UnitFrame.lua:90-125, 856`) | Slim bars | A bar only catches up at the next target change or world load |
| The target of target's health: the game sends no event for it and reads it every frame (`Blizzard_UnitFrame/Mainline/TargetFrame.lua:887-890, 907`); ours is read with the player's, the pet's and the target's health events | Slim bars: target of target bar | Its health lags when the target attacks someone other than the player or the pet. A slow tick while that bar shows would fix it |
| A plain frame of ours that takes the mouse, layer MEDIUM, over an invisible unit frame (LOW, `toplevel`, `PlayerFrame.xml:14`, `TargetFrame.xml:52`) takes the tap before it. Device-proven over the game's bars, not over unit frames; the guard is placed from `GetLeft`, `GetBottom`, `GetWidth`, `GetHeight`, `GetEffectiveScale` read out of a fight | Slim bars: the four tap guards | A tap where a game frame used to be targets that unit or opens its menu though nothing is seen there; or (place not readable) that guard is left out and the log says so |
| The bar texture `Interface\TargetingFrame\UI-StatusBar` (the game's own mana bar uses it, `UnitFrame.lua:425`) with `SetStatusBarColor`, and a 1-unit black line as the border at 720p | Slim bars | A bar draws white or not at all; a border line is missing or soft |
| `UnitName(unit)` gives a second answer that is the character's surname, for every kind of unit (after the review the bars join any second answer, as the game's own frames do, and no longer ask `RegionalUniqueNamesEnabled()`). By the source: this client's own name helper joins whatever second answer there is with the surname separator (`Blizzard_FrameXMLUtil/Camelot/NameUtil.lua:4-12`, loaded by `Blizzard_FrameXMLUtil.toc:58-59`; the unit frames show it, `Blizzard_UnitFrame/Mainline/UnitFrame.lua:145-163`, `1094-1096`), and the code shared with other clients tells a surname from a realm's name by `RegionalUniqueNamesEnabled()` (`Blizzard_UnitPopup/Mainline/UnitPopupUtils.lua:126-131`; documented, `UnitDocumentation.lua:536`, not marked as hidden). There is no call that returns a surname alone; `UnitName`'s second answer is documented only as "unitServer" (`UnitDocumentation.lua:2489-2503`). What the device gives was seen for the first answer only ("Forgot" for "Forgot Shards") | Slim bars, row "Names on the bars" (0.20.0) | The bars go on showing the first name alone (`RegionalUniqueNamesEnabled` not `true`, or no second answer): the debug log says "a second name was not joined: the game says it is a realm's name here", once. A realm's name is never shown. If the second answer is hidden in a fight nothing is joined: the bar keeps a whole name it already shows for that unit, else shows the first name |
| `Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR` exists and is a space. The constant is the engine's and its value is not in Blizzard's Lua; a comment there says "a surname separator (a space)" (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua:1163`) | Slim bars: joining the two names | The table is read through `pcall`; missing or not a text, one space is used. Another separator than a space would show as the game writes it |
| A name's width is read from our own font string with `GetUnboundedStringWidth` (documented, `SimpleFontStringAPIDocumentation.lua`; used for the square map's place name since 0.19.0, not yet seen on a device) and the text is shortened with "..." until it fits its room (170 on a main bar, 126 on a small one). A hidden name is not measured: it goes into the font string as it came, which is one line wide and cuts it itself | Slim bars: long names | A long name is cut a little early or late, or (the width not readable) left to the font string to cut. Never an error: the call is in a `pcall` |
| That the pieces the game hangs on the invisible frames go with them, as the source says: the combo point frame makes itself a child of the target frame at load (`Blizzard_UnitFrame/Camelot/ComboFrame.lua:16`), the rogue's and druid's point bars and other class bars are children of the player frame (`Camelot/RogueComboPointBar.xml:4`, `Mainline/ClassPowerBar.xml:4`), as are totems (`Mainline/TotemFrame.xml:56`); the player's own cast bar is attached to the player frame when Edit Mode's "Lock to player frame" is on | Slim bars | By the source: combo points, class bars and totems are **not seen** while "Slim bars" is On (the addon draws none yet), and a locked cast bar is not seen either. If the source is read wrong, one of them floats where the game's frame was |
| `SetPortraitTexture(ourTexture, unit)` from addon code, in and out of a fight (documented, `UnitDocumentation.lua:572`; restrictions unknown), and `GetAttribute("type")` / `GetAttribute("unit")` readable on the game's targeting-bar buttons | Spell pictures, the targeting bars' face buttons | The portrait is not drawn; the picture falls back to a copy of the game's icon (see next row) |
| What `GetTexture` returns for a texture a portrait was drawn on, and whether another texture given that value shows the portrait (not in the source) | Spell pictures, only as the fallback of the row above | A blank or wrong picture on the pet, self and assist buttons of a targeting bar |
| `GetLeft`, `GetBottom`, `GetWidth`, `GetHeight`, `GetEffectiveScale` on the game's frames give plain numbers to an addon out of a fight | Save a snapshot | The line for that piece reads `<secret>` or `?` and it is left out of the overlap check |
| An addon may call `C_EditMode.SaveLayouts` and `OnLayoutAdded` out of combat, and Edit Mode stays usable after the reload that is always asked for. The old Layout helper did the same and was never device-tested | Controller layout | "Interface action blocked" until the reload |
| `GetLayouts` shows a saved layout and the new active index straight after the save. Not relied on: if it does not, the feature stays on and asks for the reload | Controller layout | After the reload the status line says another layout is active |
| `SetPoint` and `SetScale` on the four gamepad bar anchors and on the both-triggers bar are allowed out of combat and are not blamed later in combat | Controller layout | A blocked-action message; switching off and reloading removes every trace |
| Sizes still guessed: the map cluster below 100% (taken as the measured 273 by 283 times the Map size percentage; only a part inside it is scaled, so the real one may be a few units larger), a swing timer 170 by 12 at 80%, and every spot and gap. No longer guesses: the map at 100%, a unit frame 232 by 100 and the pet frame 120 by 49 are measured (probe `layout.sizes`); a bar 208 by 68 is Blizzard's size for a bar that does not grow (`Blizzard_GamepadActionBars/ActionBarStyles.lua:172`) | Controller layout | Pieces overlap or sit off centre until the probe measures the map at 60, 70 and 80% and the timers under the template's settings |
| A spell on a scaled bar that opens its own wheel: the wheel is placed in the button's scaled units, so it may open beside the button. Spell button size starts at 100% for this reason | Controller layout | Below 100% such a wheel opens off its button; the spell still works |
| Whether the game picks its own Gamepad preset when the Gamepad UI is turned off and on again | Controller layout | The status line says another layout is active and the bars stay as the game has them |
| Whether the game keeps its controller hint box setting (`GamepadShowPersistentInputLegend`, `Blizzard_Gamepad/UI/PersistentInputLegend/GamepadPersistentInputLegend.lua:273`) for the whole account or per character; the source does not say. The value to put back is kept account-wide (`opts.hintsWas`) and only saved when none is saved yet | Controller layout 0.13.0 | Per character: a second character on the layout keeps its hint box, and a character that first places the layout after another may later get "off" put back; the game's own option (Options, Controller) turns it on again |
| Whether the main bar's spells can be read in a fight. `C_ActionBar.GetActionCooldown` and `GetActionDisplayCount` are documented "SecretWhenCooldownsRestricted", so they may come back secret then | Restriction probe 0.4.0 `bars.spells`; the planned flat strip | The strip could show icons but not cooldowns or counts in a fight |
| `SetAlpha` on a gamepad bar anchor in a fight. Not a protected function in the documentation (`SetPoint` is), but the anchors hold protected spell buttons | Restriction probe 0.4.0 `bars.alpha` (risky); a "Swap" by fading | "Interface action blocked"; fading in a fight would be ruled out |
| A controller press still casts while the main bar's top anchor is far off screen (no screen clamp on the gamepad bars in the source) | Restriction probe 0.4.0 `bars.park` (risky, guided); the planned flat strip | Nothing casts while the bar is off screen; the strip idea would need the bar on screen, faded |
| `InputDeviceIconSetManager:GetActiveInputDeviceIconSet` and `InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture` (found only in Blizzard's own code, `InputDeviceIconSetManager.lua:57`, `InputIconTexture.lua:565`); a spell button's `ButtonIcon.NormalTexture` holds its picture as an atlas (`InputIconTexture.lua:607-613`) | Restriction probe 0.4.0 `bars.prompts` | The trial says "no pictures read" or "missing"; the strip would need pictures of its own |
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
| The `EventRegistry` events `MenuProxy.OnShow`, `MenuProxy.OnHide`, `MenuProxy.OnClose` fire on this client with the menu frame as their argument (seen in `Blizzard_Menu/Menu.lua:1755`, `:1848`, `:1852`; event names are plain strings, so the audit cannot check them) | Menu background | No panel on most menus; the quest menu still gets one through the fallback; the debug log says which |
| `Menu.GetManager():GetOpenMenu()` returns the open menu's frame (`Menu.lua:2667`, `:2712`; found by the audit, behaviour untested) | Menu background, fallback only | The fallback finds nothing; one debug line; no panel |
| `QuestMapLogTitleButton_CreateContextMenu` is the function that opens the quest menu and is called by its global name (`QuestMapFrame.lua:2367`, `:2501`; `Blizzard_WorldMap.lua:921`) | Menu background, fallback only | The fallback never runs; the main path is not affected |
| A frame of ours with no parent, in the menu's layer and one level lower, is drawn directly behind the menu (the menu template flattens its layers and has controller glow frames at fixed levels) | Menu background | The panel is invisible or over the text; the feature is switched off again |
| Whether our parentless frame is in the same window as the menu (menus call `SetWindow`; ours stays in the default one and never calls it) | Menu background | Logged as shown but not visible |
| The engine setting `outlineModeShowLootEffectWhenDisabled` exists on this client and brings the sparkle back on low graphics (engine-only, not in Blizzard's interface source; taken from ForeverLootSparkles, which works on PC). `C_CVar.GetCVar` / `SetCVar` and `CVAR_UPDATE` (with the setting's name first) are documented. Written inside pcall, never in a fight | Loot sparkles | The write does nothing: no sparkle, no error. Switching off may need a full restart to show |
| `WorldMapFrame.BorderFrame:GetPortrait()` returns the book icon (`PortraitFrame.lua:34`; set in `Blizzard_WorldMap.lua:18`), shown at the normal size and hidden in full screen (`Blizzard_WorldMap.lua:40-73`); `WorldMapFrame:Maximize` / `Minimize` are what switch full screen, so a post-hook sees the final state (read, not run; the audit finds the names, not that these are the map's own) | Round button on the map | The button stays at its spot with the map open, or stays on the book's spot after full screen until the map is reopened; tap and hold still work |
| A frame of ours in the HIGH layer, one level above the highest of the map border's pieces (book container +400, ring art +500, title and close button +510: `SharedUIPanelTemplates.xml:381`, `:574`, `PortraitFrame.lua:110-115`), is drawn over the book icon. Not settled by the source: the map has `frameBuffer="true"` (`Blizzard_WorldMap.xml:67`), and how that orders an outside frame is engine behaviour; Forever's `WorldMapFrameStrata` game rule (`Blizzard_WorldMap.lua:376`) could also put the map above HIGH | Round button on the map | The button sits behind the map's border; the book shows over it (taps may still reach it) |
| The atlas `common-dropdown-bg` is missing from this client (the suspected cause of menus with no background) | Explanation only; one debug line reports it | None for the feature |
| `debugstack` argument form; whether `C_UI.Reload` needs a real press (it is only ever called from one; see "Verified" for what the source shows) | Core | Shorter error details |
| Which of two "priority" overrides on the A button wins: ours (held by a hidden button of ours while the controller cursor is on the Sort tab) or the bag footer's own (held by `UIParent`, set again on every footer refresh: `ContainerFrame.lua:2895-2902`, `InputBindingStack/InputFunctionBinding.lua:46-50`). Engine behaviour, not in the Lua source. Ours is set one frame after the cursor arrives and again after each `BAG_UPDATE_DELAYED` | Bag sorter, "D-pad to Sort" | A does nothing on the Sort tab: the tab can be reached with the d-pad but not pressed. Touch and the stick click still sort. The debug log's "A is now: ..." line says who holds A. If so the choice stays Off and the idea is dropped |
| `geterrorhandler` and `seterrorhandler` (Lua built-ins of the game, not in the generated documentation; Blizzard calls `seterrorhandler(HandleLuaError)` once at `Blizzard_ScriptErrors.lua:101` and `geterrorhandler()` in `ErrorUtil.lua:3`). Looked up before use; the chained handler is only set by the risky trial `err.chain` and the old one is put back after a second | Restriction probe 0.3.0, area Errors (testing only, never in the player zips) | The trial says "missing", or the game's error box misses the one test error raised during that second |
| A post-hook on `ScriptErrorsFrame:DisplayMessageInternal` (a mixin method, `Blizzard_ScriptErrorsFrame.lua:88`) sees every error and warning the box takes, without replacing Blizzard's handler; the message and stack may be secret for errors from tainted code | Restriction probe 0.3.0, area Errors; Catch all errors (`ErrorCatcher.lua`, off by default) | The probe's hook trial says "no effect"; Catch all errors lists only Pocket Essentials' own errors, as before. Nothing else changes |
| `seterrorhandler` as Catch all errors' fallback: only when `ScriptErrorsFrame` or its `DisplayMessageInternal` is missing, a handler is chained in front of the current one (it passes every error on) and put back when the feature is switched off, if it is still the one in place | Catch all errors (`ErrorCatcher.lua`, off by default) | Errors are not listed, or the game's error popup stops showing until a reload |
| `geterrorhandler()` read at file load and again at login, compared to tell that another addon replaced the handler (the feature then stands aside as for BugSack) | Catch all errors | The feature stands aside when it need not, or catches nothing beside an unknown error addon |
| Writing the setting `scriptErrors` (read by Blizzard at `Blizzard_ScriptErrorsFrame.lua:130`) from addon code, out of a fight; the old value is kept in `PocketEssentialsDB.options.errors.oldScriptErrors` and put back | Catch all errors, "Error popup: Hide" | The popup keeps showing; or, if the addon is removed while Hide is chosen, the popup stays off until the setting is turned on again |
| The engine settings `OutlineEngineMode` and `outlineModeShowLootEffectWhenDisabled` exist on this client (engine-only, not in Blizzard's interface source) | Restriction probe 0.3.0, area Graphics | The trial says "not on this client" for that setting |
| `C_CVar.GetCVarInfo` returning seven values for an engine-only setting the same way as for a documented one | Restriction probe 0.3.0, area Graphics | The probe falls back to `GetCVar` / `GetCVarDefault` |
| That a value stored on Blizzard's item buttons through `SmartNavigation_AddJumpNavigationOverride` leaves no taint. Taken from Blizzard's own comment (`Blizzard_GamepadSmartNavigation/Utility.lua:14`) and the code path (`SecureHelper.lua:144`); the probe only tried the setter on a button of ours. The addon cannot check its own write (`issecurevariable` is not in this client). Only a frame is ever passed, only out of a fight | Bag sorter, "D-pad to Sort" | Using an item is blocked after the cursor has been in the bag's first column, until a reload. The choice is Off by default; device steps 13c 2, 6, 7, 10, 12, 13 and 16 look for it |
| Whether Blizzard's cursor really jumps to a button of ours that is outside the focused window and calls `OnSmartNavSelect` / `OnSmartNavDeselect` on it (`SmartNavigation.lua:1503-1530`, `:680`, `:710`; read, not run), and where Up, Down and Left take it from there | Bag sorter, "D-pad to Sort" | Left from the first column wraps round as before, or the tab is reached but A is never taken. Nothing else changes |
| Whether the bag ever gives its item buttons to other slots without a layout pass (`UpdateContainerFrameAnchors`) following (the buttons come from a pool: `ContainerFrame.lua:1046-1056`). The Left jumps are put on the first column again at each layout pass and each time the bag opens | Bag sorter, "D-pad to Sort" | Until the bag is next laid out or opened, Left from a slot that is no longer in the first column still goes to the Sort tab, or a new first-column slot does not |
| `GetBindingAction(key, true)` naming the override that holds a key (used in Blizzard's own code, not in the generated documentation). Read only, for one debug-log line | Bag sorter, "D-pad to Sort" | The log line says "unknown" or something unhelpful; nothing else |
| That moving Blizzard's own item buttons and bag buttons with `ClearAllPoints` / `SetPoint` (nothing else) leaves item use untouched, in and out of a fight. By the source the buttons are not protected frames and a button's place is not a Lua value the item code reads (`ContainerFrame.xml`, `ItemButtonTemplate.xml`, Camelot `MainMenuBarBagButtons.xml`: no `protected`); the probe only tried resizing the bag window, never an item button | Bag sorter, "Bag icons" | Using, moving or selling an item is blocked, or the game refuses the move in a fight. If a button says it is protected in a fight the move waits for the fight to end. The choice is "In the grid" by default; device steps 13d 4, 5, 9 and 10 look for it |
| `GamepadBagBar.BagButtonArray` and `ContainerFrameCombinedBags.Items` are readable by an addon, hold the buttons that are in the grid, and each of those has exactly one anchor point on the same frame (`MainMenuBarBagButtons.xml:99-138`, `ContainerFrame.lua:1047-1106`, `:3033-3035`, `AnchorUtil.lua:122-147`; fields are not seen by the audit) | Bag sorter, "Bag icons" | The choice does nothing and writes one debug line ("bag icons: left alone, ...") |
| That a collapsed bag's slot buttons have no anchor point (they come back from the pool cleared, `Pools.lua` `Pool_HideAndClearAnchors`, and the layout skips them: `ContainerFrame.lua:1082-1086`) | Bag sorter, "Bag icons" | A stale button is counted as in the grid; two buttons then share a place, the choice does nothing while a bag is collapsed and the debug line says "two buttons in one place" |
| That Blizzard's controller navigation finds the moved buttons where they now are (its grid is built from the buttons' places on screen, `SmartNavigation.lua` `UpdateGrid`; rebuilt one frame after the bag opens, `ContainerFrame.lua:2866-2873`) and how it treats a bag picture with an empty space under it | Bag sorter, "Bag icons" | The d-pad skips a row or a button near the top of the bag. Touch is not affected. The fallback is the row of pictures at the bottom, where every column is full |
| `SetAlpha(0)` on the four gamepad bar anchors (`Top/Left/Right/BottomCenteredAnchor`), set and put back in a fight too, and the bars still casting while their anchors are invisible. Proven on the device for `.Bar` (fade, cast after a fight); not yet for the anchors, nor a cast answered inside a fight. No game code sets an anchor's alpha (SOURCE-BRIEF 4); a post-hook on each anchor's `SetAlpha` answers any other value with 0 while the pictures are on | Controller layout 0.13.0 face pictures (`FaceBars.lua`) | "Interface action blocked" when the alpha is set in a fight, or a press that does nothing; switching the layout off puts alpha 1 back |
| Post-hooks on Blizzard's button regions (`icon` `SetTexture` / `SetVertexColor` / `SetDesaturated` / `Show` / `Hide`, `Count` `SetText`, `RangeIndicator`, `SpecialActionIcon`) and on `UpdateAction` / `UpdateState` catch every change the game shows. The buttons are also handed to native code (`C_ActionBar.RegisterActionUIButton`, `ActionButton.lua:550`), which may change them with no Lua call; cooldowns and checked are read by event for that reason | Face pictures | A picture shows an old colour, count or range dot until the next change or event; no error |
| `icon:GetVertexColor()`, `button:GetChecked()`, `ActionButtonSpellAlertManager:HasAlert()` readable in a fight (Blizzard writes plain constants; not documented as secret). A secret answer is treated as white / not checked / no glow | Face pictures | Usable and no-mana colours, the gold edge or the glow missing in fights |
| `C_ActionBar.GetActionCooldownDuration` + `SetCooldownFromDurationObject` on our own Cooldown frame actually draws the sweep (both proven allowed in a fight; the sweep was never seen, nothing was on cooldown), and whether the object covers charges and loss of control | Face pictures | No sweep; the icon is still darkened from `GetActionCooldown(slot).isActive` |
| `GetActionCooldown(slot).isOnGCD` (NeverSecret; documented "do not trust this field unless responding to a `SPELL_UPDATE_COOLDOWN` event"): read on the frame after that event, to keep the global cooldown from darkening every icon | Face pictures | Every icon darkens briefly on each cast, or a real cooldown starting with a cast shows undarkened until the next cooldown event |
| The `OnCooldownDone` script on our own Cooldown frame (in Blizzard's source: `Blizzard_SharedXML/UI.xsd`, set by `Blizzard_CooldownViewer/CooldownViewer.lua:718`) fires when a cooldown given with `SetCooldownFromDurationObject` runs out, in a fight too. It only marks the picture; the darkening is then read on the next frame, outside `SPELL_UPDATE_COOLDOWN` | Face pictures (0.15.0) | A spell stays darkened after its cooldown ends until the next cooldown event, as in 0.14.0; no error |
| `CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")` on this client (the template is in `Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3`, loaded through `[Family]`; the probe makes the same frame). Without the template a plain Cooldown frame is used; without either the pictures are not built | Face pictures | The game's bars stay, the status line says "this game version cannot draw cooldowns on our pictures" |
| `PageUnit:RegisterActiveActionBarUpdatedCallback` (an addon function inside Blizzard's callback registry, called through `securecallfunction`, `CallbackRegistry.lua:207-211`), `PageUnit:GetActiveBar`, `GetActionButtonByIndex`, the `SetCurrentPage` post-hook and `HookScript` on the stance, possess and targeting bars and on `GamepadMainActionBarFrame`: found only in Blizzard's own code, so their restrictions are unknown. The probe registered the same callback on the device; whether it follows the trigger in a fight is not yet answered | Face pictures | The bar in use does not stand out (every bar at full strength), a swapped-in stance or targeting bar is drawn late, or a blocked message names the hook; the callback cannot be taken off before a reload but does nothing while the pictures are off |
| The tooltip's size (200 by 100) and the controls reminder's size (200 by 100, its background's size in `GamepadPersistentInputLegend.xml`) in the overlap check. The game sizes the tooltip to its text and the reminder to what it lists, so the real sizes are only known on the device | Controller layout 0.16.0, the overlap check and the tooltip's spot | A tall tooltip reaches the quest list or the target's pieces, or the reminder (when On) reaches a piece it was checked clear of; cosmetic, nothing is clicked there |
| Hiding the chat's box textures named in `CHAT_FRAME_TEXTURES` with each texture's own `Hide` (0.16.3). Until 0.16.2 the addon also called `FCF_SetWindowAlpha(frame, 0, true)`, which writes `ChatFrameN.oldAlpha` from addon code: **on the device (2026-11-24, the testing rows of 0.16.2) that one call made the game refuse its own controller actions in the addon's name from login on** (`SetPreferredGamepadInteractTarget`, `TargetUnit`, `ClearTarget`, `SpellStopCasting`, `UseAction`). Rule: never call a function Blizzard wrote in Lua that writes a field on one of the game's frames; use the frame's own engine methods | Controller layout, "the chat without its box" | Confirmed on the device with 0.16.3 (2026-11-24): no refusal with every part of the layout on, the box stays gone, and switching the layout off brings it back. A pop-up whisper window keeps its box |
| The black disc behind the map: its size (the round map is taken to fill the 198-unit Minimap frame, 4 screen units added) and its frame level (one under `Minimap`, on its parent) | Controller layout 0.16.0, the map's black border | The black rim is uneven, too thick or too thin; or, if the game raises the cluster or changes levels later, the disc draws over the map until the next placement or ring redraw. Cosmetic |
| The gamepad radial's "tracking" action (`GamepadRadial.lua:788`) opening `MinimapCluster.Tracking.Button`'s menu while that button is hidden (Map buttons Hidden) | Controller layout 0.16.0, "Map buttons" | The menu opens anchored to the hidden button, in an odd spot; set Map buttons to Shown to use it |
| Whether hiding the two map buttons (and the addon badge under the calendar button) changes what `MinimapCluster` measures as its own size, and so moves the map | Controller layout 0.16.0, "Map buttons" | The map jumps a few units when Map buttons is switched; the layout is placed again on the next sync and the overlap check was run with both states, so it is cosmetic |
| Reading `MinimapCluster.Tracking` and `ChatFrameN.oldAlpha` (fields of Blizzard's frames, a blind spot of the audit's extractor; cited in the code's comments) | Controller layout 0.16.0 | If either is missing on this client that piece is skipped and said once in the debug log |
| The probe's Buffs in a fight trials: the aura table's field names (`icon`, `applications`, `duration`, `expirationTime`, read from `C_UnitAuras.GetAuraDataByAuraInstanceID`), the target frame's aura container path (`TargetFrame.TargetFrameContent.TargetFrameContentContextual.Auras`, Mainline's; Camelot's source shows none) and `Cooldown:SetCooldownFromExpirationTime`, which Blizzard's documentation marks protected | Pocket Probe 0.8.0 (`aura.count`, `aura.fields`, `aura.show`, `aura.blizzard`), testing only | Each is guarded and read with `pcall`; a wrong name gives "missing", a refused call "refused", no container "no aura container under TargetFrame". Those answers are what 0.17.0 needs; no effect on the player's game |
| The probe's `aura.ignore`: `SetIgnoreParentAlpha(true)` called from addon code on the target frame's aura container (made from the game's own templates, `TargetFrameAuraContainer.xml`, so it may be refused), its earlier value put back at once | Pocket Probe 0.8.0 (`aura.ignore`), testing only; risky, out of a fight, only with Risky and Auto on | The call is refused (recorded as an error), or the container keeps our mark until a reload: the game may refuse some controller actions in our name until then, as the other risky trials can. The device step ends with a reload |
| The probe's `aura.custom`: `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")` and its methods `AddAuraGroup`, `SetUnit`, `GetAuraGroupFrameCount`, `GetAuraGroupFrame` (Blizzard_AuraContainer's Lua, not the documentation folder), and `C_XMLUtil.GetTemplateInfo` to tell a missing template | Pocket Probe 0.8.0 (`aura.custom`), testing only | Each call is guarded: a missing template gives "missing", a refused call "refused". The container and its ten icons are made at load and hidden; in a fight only its methods are called |

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
