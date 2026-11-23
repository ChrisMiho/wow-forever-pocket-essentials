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
  Move.lua        "Move on screen" (was "Move things" until 0.8.0): saved offsets for our on-screen pieces, the small panel that nudges them
  Hub.lua         the round button and the minimap addon-list entry
  Settings.lua    the settings window, its Errors and Debug log tabs; the list drawer both windows draw options with
  Setup.lua       the setup guide: screens that explain each feature with its switch and options (no switch of its own)
  QuestData.lua   reads QuestieDB + the quest log into objective locations (shared, no switch of its own)
  QuestIcons.lua  feature: quest icons        (also keeps /qd working)
  QuestArrow.lua  feature: quest arrow
  Bags.lua        feature: bag sorter (key `bags`; called "One big bag" before 0.1.0)
  Vendor.lua      features: sell junk, repair (two switches)
  Chat.lua        feature: big chat buttons
  MenuBackground.lua  feature: menu background (key `menuBg`): a dark panel of ours behind the game's pop-up menus
  LootSparkles.lua    feature: loot sparkles (key `sparkles`): keeps the engine setting `outlineModeShowLootEffectWhenDisabled` at 1
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

## Unverified API

Everything the code calls was looked up in Blizzard's interface source for
build 1.60.1.70938 (`github.com/Gethe/wow-ui-source`, branch `forever`).
These are the things that could **not** be confirmed there. Each is guarded
so that being wrong cannot raise an error; the worst case is listed.

| What | Used by | If it is wrong |
|---|---|---|
| An addon may call `C_EditMode.SaveLayouts` and `OnLayoutAdded` out of combat, and Edit Mode stays usable after the reload that is always asked for. The old Layout helper did the same and was never device-tested | Controller layout | "Interface action blocked" until the reload |
| `GetLayouts` shows a saved layout and the new active index straight after the save. Not relied on: if it does not, the feature stays on and asks for the reload | Controller layout | After the reload the status line says another layout is active |
| `SetPoint` and `SetScale` on the four gamepad bar anchors and on the both-triggers bar are allowed out of combat and are not blamed later in combat | Controller layout | A blocked-action message; switching off and reloading removes every trace |
| Sizes still guessed: the map cluster below 100% (taken as the measured 273 by 283 times the Map size percentage; only a part inside it is scaled, so the real one may be a few units larger), a swing timer 170 by 12 at 80%, and every spot and gap. No longer guesses: the map at 100%, a unit frame 232 by 100 and the pet frame 120 by 49 are measured (probe `layout.sizes`); a bar 208 by 68 is Blizzard's size for a bar that does not grow (`Blizzard_GamepadActionBars/ActionBarStyles.lua:172`) | Controller layout | Pieces overlap or sit off centre until the probe measures the map at 60, 70 and 80% and the timers under the template's settings |
| A spell on a scaled bar that opens its own wheel: the wheel is placed in the button's scaled units, so it may open beside the button. Spell button size starts at 100% for this reason | Controller layout | Below 100% such a wheel opens off its button; the spell still works |
| Whether the game picks its own Gamepad preset when the Gamepad UI is turned off and on again | Controller layout | The status line says another layout is active and the bars stay as the game has them |
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
