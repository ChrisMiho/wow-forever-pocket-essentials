# Move Things (0.2.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. One task per agent, in order, never two at once.

**Goal:** A small "Move things" panel that nudges the quest arrow, the "Press A to type" prompt and the round button to any spot, by touch or controller, with press-and-hold repeat.

**Architecture:** A new core file `Move.lua` owns the saved offsets, the registry of movable pieces, the panel, the outline box and the hold-repeat driver. Each piece adds its offset in its own existing layout function and registers itself. `UI.lua`'s window navigation gains an optional press-and-hold hook.

**Tech Stack:** Lua 5.1 (WoW "Forever", Interface 16001, modern API), LuaJIT offline tests.

**Spec:** `docs/superpowers/specs/2026-11-17-move-things.md` (the binding authority).

## Global Constraints

- Read first: `CLAUDE.md`, the spec in full, `docs/ARCHITECTURE.md` sections "Adding a feature" and "What the device allows (from the probe)", and the header comment of every file you change.
- The game's Edit Mode is never used: no `EditMode*` function, frame or event. No Blizzard frame is touched, hooked or parented to. All new frames are the addon's own, under `UIParent`.
- Controller buttons (override bindings) are only taken or given back out of a fight, or from `PLAYER_REGEN_DISABLED`; reuse `UI:AttachNav`, do not write new binding code.
- With the Gamepad UI on, addon code never opens, focuses or closes the chat box and never touches the chat edit box.
- No libraries. Every event handler, timer, hook and frame script goes through `PE:Safe` / `PE:Wrap` or a module's `Wrap` / `Safe` / `RegisterEvent` / `After`.
- Nothing ticks unless an arrow button is being held. The only new `OnUpdate` is the hold driver's, live only between press and release. Do not change `ACTIVE_INTERVAL` or `SELECT_INTERVAL` in `QuestArrow.lua`.
- Default is 0.1.0's behaviour: with no saved offset every piece sits exactly where it did. Existing position tests must stay green unchanged.
- Exact values (use verbatim): storage `PocketEssentialsDB.ui.moved[key] = { x =, y = }` in 720p pixels, x right, y up, read range -2000..2000; piece keys `questArrow`, `chatPrompt`, `hub`; labels "Quest arrow", "Chat prompt", "Round button"; nudge 2 pixels; hold delay 0.4 s; repeat 10 a second; 6 pixels a step after 1.5 s held; safety stop 8 s; panel title "Move things"; buttons "Up", "Down", "Left", "Right", "Reset", "Close".
- Every new game function, global, key name or frame method: find it in `~/.cache/wow-ui-source/forever`, quote file and line in your report, then run `scripts/audit-api.sh` (about 45 s; commit the rewritten `tests/api/*.txt`). Anything not found is guarded and reported. Do not edit `docs/ARCHITECTURE.md`, `PRD.md`, `CHANGELOG.md` or the TOC `## Version`; the release task does that. (Adding `Move.lua` to the TOC file list is yours.)
- Debug log: the lines in the spec's "Debug log" bullet, as `if PE.debugOn then PE:Debug("move", text) end`. Never per repeat step.
- Tests first (watch them fail), in `tests/features/`; extend `tests/lib/fakeclient.lua` only with what the source shows the game does. Never weaken an existing test; if one encodes behaviour the spec changes, change it and say so.
- `scripts/check.sh` and `scripts/test.sh` must pass before you commit. Comments are written for a player reading the code (no "the owner", no "device test").
- One commit per task, by naming paths (`git commit <paths> -m ...`; `git add <path>` only for new files). Never `git add -A` / `.`. Never commit `docs/errorLogs/`, `docs/realtest1/`, `docs/screenshots/`. Never push.
- Every text shown in game is plain language.

---

### Task 1: Move.lua, the panel, hold-to-repeat, and the round button

Spec: all of it except the quest arrow and chat prompt pieces.

**Files:**
- Create: `addons/PocketEssentials/Move.lua` (list it in `PocketEssentials.toc` after `UI.lua` and before `Hub.lua`)
- Modify: `addons/PocketEssentials/UI.lua` (`NavPress` / `NavActivate`: the optional `peHold` hook)
- Modify: `addons/PocketEssentials/Hub.lua` (its placement function adds the offset; registers piece `hub`; choosing a "Round button position" clears the offset)
- Modify: `addons/PocketEssentials/Settings.lua` (`BuildCoreSection`: "Move things" button in the bottom row; where the round button preset is chosen)
- Modify: `addons/PocketEssentials/Core.lua` (`InitDB`: `db.ui.moved` is a table)
- Test: new `tests/features/move_test.lua`; `tests/features/ui_test.lua` for the navigation hook

**Interfaces (produced, used by Task 2):**
- `PE.Move:Register(def)` with `def = { key, label, order, available = function() -> bool, apply = function(), outline = function(box) }`. `outline(box)` must `ClearAllPoints`, `SetPoint` and `SetSize` the given frame over the piece.
- `PE.Move:GetOffset(key) -> dx, dy` in UI units (already through `UI:Px`), `0, 0` when none or invalid.
- `PE.Move:ClearOffset(key)` (used when a preset is chosen), `PE.Move:Open()`, `PE.Move:Close(why)`.
- Pieces call these guarded: `local M = PE.Move; local dx, dy = 0, 0; if M and M.GetOffset then dx, dy = M:GetOffset(key) end`.

**Notes:**
- `Move.lua` is core, not a feature module: it has no on/off switch and does nothing until `PE.Move:Open()` is called (no frames built at load, no events registered while closed).
- Screen-edge rule: after computing a candidate offset, ask the piece's `outline(box)` to place the box, read the box's rectangle (`GetLeft/GetRight/GetTop/GetBottom`) against `UIParent`'s; if any part is outside, restore the old offset and place again. Keep it allocation-free per step.
- Hold driver: a hidden frame; `Show()` on press, `Hide()` on stop; its `OnUpdate` accumulates elapsed time. The first nudge happens on press itself (touch: mouse-down; controller: A down), the repeats from the driver.
- Touch: the arrow buttons use mouse-down / mouse-up (see how `UI:CreateButton` already wires `ButtonDown` / `ButtonUp`; keep its pressed look). Make sure a touch press does not nudge twice (mouse-down nudge plus an `OnClick`).
- Controller: `NavPress` currently acts on A's release only. Add: on A down, if the focused button has `peHold`, call `peHold.start()` and remember that button; on A up (or when the press is lost: panel hidden, `NavDisarm`, focus moved), call `peHold.stop()` and do not fire its `OnClick`. Buttons without `peHold` are untouched; prove it with a test on the settings window.
- Fight: register `PLAYER_REGEN_DISABLED` only while the panel is open (unregister on close). In its handler stop the hold and hide the panel. Check how the other panels and `NavCombatEvent` already behave and stay consistent.
- Panel corner hop: bottom right by default, bottom left when the outline box overlaps the panel's rectangle; re-check after each move and each selection.
- The settings' round-button preset buttons call `PE:SetUISetting("hubPos", value)`; clearing the `hub` offset belongs with that choice.

### Task 2: The quest arrow and the chat prompt become movable

Spec: pieces `questArrow` and `chatPrompt`.

**Files:**
- Modify: `addons/PocketEssentials/QuestArrow.lua` (`Layout`: the display's `SetPoint` adds the offset; registers piece `questArrow`; the "Arrow position" option's `OnChange` clears the offset)
- Modify: `addons/PocketEssentials/Chat.lua` (the prompt's layout adds the offset; registers piece `chatPrompt`)
- Test: `tests/features/questarrow_test.lua`, `tests/features/chat_test.lua`, `tests/features/move_test.lua`

**Notes:**
- Use the Task 1 interfaces exactly as its report describes them.
- `available`: the arrow piece while the Quest arrow feature is enabled; the prompt piece while Big chat buttons is enabled. Register once at load; `available` decides listing.
- `outline(box)` must work while the piece is hidden or not yet built: compute the same anchor, offset and size the piece's own layout uses (the arrow's whole block: box, distance line, title lines; the prompt's backdrop rectangle with sample text sizes). Share the maths with the real layout rather than copying numbers.
- `apply()` calls the piece's existing layout function; when the piece's frames are not built yet it does nothing (the offset is read when they are built).
- The arrow's layout is also called on metrics changes; nothing new may run per update tick.
- The prompt must still be shown only from `TypeKeyArm` and hidden only from `TypeKeyDisarm`.

### Task 3: Release 0.2.0 (controller, not a subagent)

TOC version, CHANGELOG, PRD.md, `docs/ARCHITECTURE.md`, `docs/TESTING.md` steps, audit, check, test, build, commit, push, GitHub pre-release `v0.2.0`, device-test handoff.
