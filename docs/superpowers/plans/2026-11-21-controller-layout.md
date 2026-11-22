# Controller layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new, off-by-default feature "Controller layout" that creates a "Pocket Essentials" Edit Mode layout, switches to it, places the game's four gamepad bars around the minimap, and undoes all of it when switched off.

**Architecture:** One new module file, `ControllerLayout.lua`, in two halves: pure functions that turn options into numbers and layout tables (testable with no game), and a thin shell that calls the game (`C_EditMode`, frame `SetPoint` / `SetScale`) out of combat. A new "Controller" settings tab and setup-guide screen list the module. Pocket Probe gains six trials that measure what this build guessed.

**Tech Stack:** Lua 5.1 (LuaJIT offline), WoW Forever client API (Interface 16001), the repo's own test harness (`tests/lib/fakeclient.lua`, `tests/features/run.lua`).

**Spec:** `docs/superpowers/specs/2026-11-21-controller-layout.md`. Read it first; every number below comes from it.

## Global Constraints

- No commits and no pushes. The owner reviews uncommitted changes. Where a task would end with a commit, run `scripts/check.sh` and `scripts/test.sh` instead; both must exit 0.
- No libraries. Interface 16001 only.
- Every event handler, callback and hook body goes through `PE:Safe` / `PE:Wrap` / `mod:Wrap`.
- Nothing ticks while the feature is off: no OnUpdate, no timers, events registered only in `OnEnable`. The one permanent hook returns at once while the module is off.
- Never touch a Blizzard frame in combat. Use `PE:RunOutOfCombat(key, fn)` with keys prefixed `ctrlLayout:`.
- Never write a field into a Blizzard table. Only call `ClearAllPoints`, `SetPoint`, `SetScale`, `GetPoint`, `GetNumPoints`, `GetScale` on frames.
- Never call a method of `EditModeManagerFrame` except `IsShown` / `IsEditModeActive` to see whether Edit Mode is open.
- Every game call is reached through a `type(...) == "function"` check and `pcall`.
- `scripts/check.sh` forbids these words in any `.lua` under `addons/` and `probe/`: "the owner", "owner's", "owner chose", "owner changed", "owner first". Comments are plain present tense.
- Player-facing text is plain language, one line where possible, copied exactly from the spec.
- After adding any game name: add `INDIRECT` rows in `tests/api/extract.lua` where the name is reached through a variable, run `scripts/audit-api.sh`, and explain any unverified name by hand.

## Review Focus

1. The player deletes or renames the "Pocket Essentials" layout in Edit Mode while the feature is on: expected, the status line says another layout is active and the bars return to the game's spots; no error. (Test in Task 3.)
2. Switching on while in combat, then reloading before combat ends: expected, nothing was changed and the feature reads as on with the "another layout" line; switching off and on recovers. (Test in Task 2.)
3. `GetLayouts` returns a table missing a field, or a game call raises: expected, a logged error, the feature switched back off, no half-written layout. (Test in Task 2.)
4. The saved "previous layout" no longer exists at switch-off: expected, the Gamepad preset is activated. (Test in Task 2.)
5. An option is changed while Edit Mode is open: expected, refused with "Close Edit Mode first." and the option's saved value put back. (Test in Task 4.)

---

### Task 1: Pure logic, registration, tab and guide

**Files:**
- Create: `addons/PocketEssentials/ControllerLayout.lua`
- Create: `tests/features/layout_test.lua`
- Modify: `addons/PocketEssentials/PocketEssentials.toc` (add `ControllerLayout.lua` after `LootSparkles.lua`)
- Modify: `addons/PocketEssentials/Settings.lua:28-42` (new tab after Chat: `{ id = "controller", label = "Controller", features = { "ctrlLayout" } }`)
- Modify: `addons/PocketEssentials/Setup.lua:67-101` (new screen after `chat`: `{ id = "controller", title = "Controller", lines = { "Made for playing with a controller. Needs the game's Gamepad UI." }, cards = { { key = "ctrlLayout", only = {} } } }`)
- Modify: `tests/features/run.lua` (load the new test file the way the others are loaded)
- Modify: `tests/features/ui_test.lua:205-230` (ten tabs, the new list, `/10`), `tests/features/setup_test.lua:29-34` (`SCREEN_OF.ctrlLayout = "controller"`, `TAB_OF.ctrlLayout = "controller"`)

**Interfaces:**
- Produces, on `PE.LayoutPlan` (a plain table, no game calls):
  - `Plan.NAME = "Pocket Essentials"`
  - `Plan.DEFAULTS = { main = "above", frames = "corner", size = 85, fineMain = 1, fineSide = 1, fineBoth = 1, timers = "under", ranged = 1, mainHand = 1, offHand = 2 }`
  - `Plan.Scales(opts) -> kM, kS, kB` (each `min(1, size/100 * fine)`; `kB` is that times 0.7)
  - `Plan.MapY(opts) -> number` (spec "The template" and the `main = "under"` row of "Bars")
  - `Plan.BarSpots(opts) -> { top = {x, y, s}, left = {...}, right = {...}, bottom = {x, y, s = 1}, both = {x, y, s} }` (spec "Bars" table; x, y are UI units from UIParent BOTTOM, before dividing by s)
  - `Plan.Pieces(opts) -> list of { system = <name string>, index = <number or nil>, anchor = {point, relativeTo, relativePoint, x, y} or nil, settings = { [settingName] = storedValue } or nil, moved = true|nil }` for every row of the spec's template, frames and timers tables. System and setting names are the Enum member names as strings (`"Minimap"`, `"Size"`), resolved to numbers by the shell.
  - `Plan.Build(base, opts, enums) -> layout` : deep copy of `base`, name/type/style set, every piece applied; a system missing from `base` is skipped. `enums` is a table the shell fills from `Enum` (`enums.system.Minimap`, `enums.setting.Minimap.Size`, `enums.index.UnitFrame.Pet`, `enums.layoutType.Account`, `enums.style.Gamepad`).
  - `Plan.Apply(layout, pieces, enums) -> changedCount` : applies a list of pieces to an existing layout in place (used by option changes).
- Produces: module registered with `key = "ctrlLayout"`, `label = "Controller layout"`, `desc = "Map bottom middle, spell bars around it, chat top right."`, `order = 60`, `experimental = true`, `statusWhenOff = true`, `defaults = Plan.DEFAULTS` plus `prev = false`. `OnEnable` / `OnDisable` are empty stubs in this task.

- [ ] **Step 1: Write failing tests** in `tests/features/layout_test.lua` (skeleton as `tests/features/lootsparkles_test.lua`):
  - `Scales`: size 85, fines 1 gives 0.85, 0.85, 0.595; size 100 with `fineSide = 1.15` gives kS 1 (capped); size 70 with `fineMain = 0.85` gives kM 0.595.
  - `MapY`: defaults give 44; `timers = "bars"` gives 6; `main = "under"` with `timers = "under"` gives 126; `main = "under"`, `timers = "above"` gives 90.
  - `BarSpots` for defaults: `left.x == -(82 + 14 + 208*0.85/2)`, `left.y == 8 + 68*0.85/2`, `top.y == 44 + 176 + 12 + 68*0.85/2`, `bottom.s == 1`, `bottom.y == 44 + 176*0.62 + 50`, `right.x == -left.x`; with `timers = "bars"` every side y is 22 higher.
  - `Pieces(defaults)` contains Minimap with anchor `{"BOTTOM","UIParent","BOTTOM",0,44}` and `settings.Size == 3`; ChatFrame with `WidthHundreds 4, WidthTensAndOnes 30, HeightHundreds 2, HeightTensAndOnes 10`; SwingTimer index Ranged with `Visibility == 1` and anchor y 24; index OffHand `Visibility == 2`; UnitFrame Player anchor `{"BOTTOMLEFT","UIParent","BOTTOMLEFT",20,20}`; StatusTrackingBar entries with `settings.Size == 16` and no anchor and no `moved`.
  - `Pieces` with `frames = "flat"`: Pet anchor `{"BOTTOMRIGHT","UIParent","BOTTOM",-401,130}`.
  - `Build`: given a base with Minimap, ChatFrame and an unrelated system, the result has `layoutName == "Pocket Essentials"`, the unrelated system deep-equal to the base's, Minimap `isInDefaultPosition == false`, the base table itself unchanged, and a piece whose system is absent from the base adds nothing.
  - Registration: the module exists, is off, `PE.SETTINGS_TABS[6].id == "controller"`, and `c:assertClean()` after load.
- [ ] **Step 2: Run** `luajit tests/features/run.lua "$PWD"` (see `scripts/test.sh` for the exact arguments). Expected: the new tests fail, `PE.LayoutPlan` is nil.
- [ ] **Step 3: Implement** the pure half and the registration. Keep the assumed sizes (`MAP_W = 164, MAP_H = 176, BAR_W = 208, BAR_H = 68`) in one table at the top with the comment "First guesses; the probe trial layout.sizes measures the real ones."
- [ ] **Step 4: Update** TOC, Settings tab, Setup screen and the two existing test files.
- [ ] **Step 5: Run** `scripts/check.sh && scripts/test.sh`. Expected: both exit 0.

### Task 2: Switching on and off through Edit Mode

**Files:**
- Modify: `addons/PocketEssentials/ControllerLayout.lua`
- Modify: `tests/features/layout_test.lua`
- Modify: `tests/api/extract.lua` (INDIRECT rows for names reached through `local api = C_EditMode`), then run `scripts/audit-api.sh`
- Reference only: `git show 2797c3c:addons/PocketEssentials/Layout.lua` (the removed Layout helper; reuse its `Api`, `CopyOfPresets`, `Presets`, `ReadState`, `FindSaved`, `Activate`, `EditModeOpen` shapes) and `git show 2797c3c:tests/features/layout_test.lua`.

**Interfaces:**
- Consumes: `Plan.Build`, `Plan.NAME`, `PE:RunOutOfCombat`, `mod:RequestReload`, `PE:SetModuleEnabled`, `PE:GamepadUI`.
- Produces (file-local, used by Tasks 3 and 4): `ReadState() -> state or nil` with `state.api, state.info, state.saved, state.numPresets, state.active, state.current`; `OursIndex(state) -> index or nil`; `IsOursActive() -> boolean`; `Enums() -> enums or nil`; `EditModeOpen() -> boolean`; `Say(text)` setting the module's status note; constant `RELOAD_REASON = "Reload to finish changing the screen layout."`.
- Produces: `blocked` returning the spec's two reasons; `status` returning the spec's lines.

- [ ] **Step 1: Write failing tests** (use `c.world.layouts`, `c:enterCombat()`, `c:callsTo("C_EditMode.SaveLayouts")`, `c.reloads`; start with `gamepadUI = true`):
  - on from the Gamepad preset: one `SaveLayouts` call whose list has a layout named "Pocket Essentials" of type Account with `interfaceStyle` Gamepad at index `numPresets + 1`; `OnLayoutAdded(4, true, false)` called; `opts.prev.preset` is the Gamepad preset id; a reload reason is pending.
  - on with two Account and one Character layout saved: the new one is inserted at saved position 3 (index 6), before the Character layout.
  - on with five Account layouts: no `SaveLayouts` call, status contains "You already have 5 account-wide layouts", the module ends off.
  - on when "Pocket Essentials" exists: no `SaveLayouts`, `SetActiveLayout(its index)`.
  - on while Edit Mode is open: nothing called, status "Close Edit Mode first.", module ends off.
  - on in combat: nothing called until `c:leaveCombat()`.
  - Gamepad UI off: `PE:GetModuleState("ctrlLayout") == "blocked"`.
  - `GetLayouts` raising, or returning `{}`: an error logged, module ends off, no `SaveLayouts`.
  - off: `SetActiveLayout` with the remembered preset index; with a remembered saved layout by name and type; with the remembered layout gone, the Gamepad preset index; `opts.prev` cleared; reload pending; the "Pocket Essentials" layout still in `c.world.layouts`.
  - off when ours is not the active layout: no `SetActiveLayout` call.
  - on, then `c:reload()` style re-login with the saved table: no second `SaveLayouts`.
- [ ] **Step 2: Run** the feature tests. Expected: the new ones fail.
- [ ] **Step 3: Implement** `OnEnable` / `OnDisable` per spec "Switching on" and "Switching off". Switching the feature back off after a refusal uses `PE:SetModuleEnabled("ctrlLayout", false)` from a `mod:After(0, ...)` so it does not run inside `OnEnable`.
- [ ] **Step 4: Add INDIRECT rows, run** `scripts/audit-api.sh`, explain any unverified row.
- [ ] **Step 5: Run** `scripts/check.sh && scripts/test.sh`. Expected: both exit 0.

### Task 3: Placing and restoring the bars

**Files:**
- Modify: `addons/PocketEssentials/ControllerLayout.lua`
- Modify: `tests/lib/fakeclient.lua` (a stand-in `GamepadMainActionBarFrame` with `PageUnit`, the four `*CenteredAnchor` frames each with a `.Bar`, real `GetPoint` / `GetNumPoints` / `SetPoint` / `ClearAllPoints` / `SetScale` / `GetScale` that record calls and raise while `c` is in combat, and a `PageUnit.RefreshCompactLayout` method that restores the Top, Left and Right anchors' first points)
- Modify: `tests/features/layout_test.lua`, `tests/smoke/run.lua` only if its allow-lists need the new event

**Interfaces:**
- Consumes: `Plan.BarSpots`, `IsOursActive`, `PE:RunOutOfCombat`.
- Produces (file-local): `PlaceBars()` (queues `"ctrlLayout:bars"`), `RestoreBars()` (queues `"ctrlLayout:restore"`), both safe to call in any state.

- [ ] **Step 1: Write failing tests:**
  - on with ours active: the left anchor's point is `("CENTER", UIParent, "BOTTOM", x/s, y/s)` with the numbers from `Plan.BarSpots(defaults)` and scale 0.85; the bottom anchor scale 1; the both-triggers bar (`BottomCenteredAnchor.Bar`) scale 0.595.
  - in combat: no `SetPoint` / `SetScale` until `c:leaveCombat()`.
  - another layout active (set `c.world.layouts.activeLayout` to a preset and fire `EDIT_MODE_LAYOUTS_UPDATED`): anchors back at their first points and scale 1; status contains "Another Edit Mode layout is active".
  - the "Pocket Essentials" layout deleted from `c.world.layouts` then the event fired: same as above, no error logged.
  - `PageUnit:RefreshCompactLayout()` called while on: the anchors are placed again; called while off: no call recorded on any anchor.
  - off: every anchor and the both-triggers bar deep-equal to their state before the first change (points and scale).
  - no key is ever assigned on the stand-in Blizzard tables (wrap them in a `__newindex` that fails the test).
  - `c:assertClean()` after off.
- [ ] **Step 2: Run.** Expected: fail.
- [ ] **Step 3: Implement.** Snapshot each frame's points and scale once before the first change (module-local table, not saved). Register `EDIT_MODE_LAYOUTS_UPDATED` and `PLAYER_ENTERING_WORLD` in `OnEnable`. Install `hooksecurefunc(pageUnit, "RefreshCompactLayout", ...)` once; the hook body is `if on then PlaceBars() end` inside `PE:Safe`.
- [ ] **Step 4: Run** `scripts/check.sh && scripts/test.sh`. Expected: both exit 0.

### Task 4: Option rows

**Files:**
- Modify: `addons/PocketEssentials/ControllerLayout.lua`
- Modify: `tests/features/layout_test.lua`

**Interfaces:**
- Consumes: `Plan.Pieces`, `Plan.Apply`, `ReadState`, `OursIndex`, `PlaceBars`, `EditModeOpen`, `RELOAD_REASON`.
- Produces: the module's `options` list, in the spec's order and wording, using the existing row shapes (`choices` with `get` / `set` or `key`, `number`, `action` with `button`): see `Settings.lua:405-442`.

- [ ] **Step 1: Write failing tests:**
  - `frames` set to "flat" while on: one `SaveLayouts`; in the saved "Pocket Essentials" layout the Pet anchor is `-401, 130`, Minimap and ChatFrame entries unchanged from before; reload pending.
  - `size` 70: no `SaveLayouts`; left anchor scale 0.7.
  - `timers` "bars": `SaveLayouts` once (timer and map entries changed) and the side anchors 22 higher.
  - `ranged` 2: only the SwingTimer Ranged entry's Visibility changes.
  - `main` "under": map entry y is 126, top anchor y is `8 + 68*0.85/2`.
  - an option changed while Edit Mode is open: no `SaveLayouts`, status "Close Edit Mode first.", `mod.opts` value back to what it was.
  - "Start over": first tap changes nothing and the status asks to tap again; second tap within 20 s replaces the "Pocket Essentials" layout with `Plan.Build` output and asks for a reload; a tap after 20 s counts as a first tap.
  - the options list has eleven rows with the spec's labels.
- [ ] **Step 2: Run.** Expected: fail.
- [ ] **Step 3: Implement.** One helper `RewritePieces(filter)` that reads the layouts, applies the matching `Plan.Pieces(opts)` to ours in place, saves, and asks for a reload.
- [ ] **Step 4: Run** `scripts/check.sh && scripts/test.sh`. Expected: both exit 0.

### Task 5: Pocket Probe trials

**Files:**
- Modify: `probe/PocketProbe/Trials.lua`, `probe/PocketProbe/Core.lua` (`P.VERSION = "0.4.0"` and the header's source-proof list), `probe/PocketProbe/PocketProbe.toc` (Version 0.4.0)
- Modify: `tests/probe/run.lua` (the `RISKY` list, the allowed and readable id lists, the clean-series order string, the panel title "Pocket Probe 0.4.0", stubs for the new frames in `install(c)`)
- Modify: `tests/api/extract.lua` (INDIRECT rows pointing at `../../probe/PocketProbe/Trials.lua`), then `scripts/audit-api.sh`

**Interfaces:**
- Produces trials in area "Controller and layout", ids and kinds exactly as the spec's "Pocket Probe additions": `layout.sizes` (value), `bars.protected` (value), `bars.settings` (value), `bars.move` (action, risky), `bars.scale` (action, risky), `layout.save` (action, risky, clean).

- [ ] **Step 1: Write failing tests** in `tests/probe/run.lua`: each new id is listed; the three action trials are in `RISKY`; `layout.sizes` records a `MinimapCluster w` value from the stub; `bars.move` returns true when the stub's point reads back and `false, reason` when the frame is missing; `layout.save` calls `SaveLayouts` once with a list equal to the one read.
- [ ] **Step 2: Run** `luajit tests/probe/run.lua "$PWD"`. Expected: fail.
- [ ] **Step 3: Implement** with `Find(...)` for every game function and plain `_G` lookups guarded by `type(...) == "table"` for frames.
- [ ] **Step 4: Run** `scripts/audit-api.sh`, then `scripts/check.sh && scripts/test.sh`. Expected: both exit 0.

### Task 6: Version, notes and the build

**Files:**
- Modify: `addons/PocketEssentials/PocketEssentials.toc` (Version 0.11.0, Notes line mentions the controller layout), `CHANGELOG.md` (entry `## [0.11.0] - 2026-11-21`), `docs/TESTING.md` (section 21, numbered plain-language device steps, probe first), `docs/ARCHITECTURE.md` (the spec's four "Unverified" rows; correct the stale "Adding a feature" lines about folds), `PRD.md` (Status note `**0.11.0 (2026-11-21, untested):**`)

- [ ] **Step 1: Write** the entries.
- [ ] **Step 2: Run** `scripts/check.sh && scripts/test.sh && scripts/build.sh`. Expected: all exit 0 and `dist/` holds the 0.11.0 zips and `PocketProbe.zip`.
