# Controller layout 0.11.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the four clear layout bugs from the main's screenshots: XP bar top middle, per-character switch-on, map title under the map, buffs clear of the chat.

**Architecture:** Template changes in `PE.LayoutPlan` (`Plan.Pieces`, `ReadEnums`), and the switch's saved "layout to go back to" made per character in the module half of `addons/PocketEssentials/ControllerLayout.lua`.

**Tech Stack:** Lua 5.1 (LuaJIT tests), WoW interface 16001, `tests/features/layout_test.lua` with `tests/lib/fakeclient.lua`.

**Spec:** `docs/superpowers/specs/2026-11-23-controller-layout-0.11.1.md` (approved by the owner 2026-11-23), an update to `2026-11-21-controller-layout.md`. Read both.

## Global Constraints

- Nothing ticks while the feature is off: the only off-state work is one check at login (spec 2), with no events left registered afterwards.
- Layout switches only out of a fight, through `PE:RunOutOfCombat`.
- A player's own Edit Mode layout is never changed.
- Every new game name (`UnitName`, `GetRealmName`, `Enum.EditModeMinimapSetting.HeaderUnderneath`) verified in `~/.cache/wow-ui-source/forever`, cited in the file's header comment, and `scripts/audit-api.sh` run so `tests/api/*.txt` include them.
- Handlers through `PE:Safe` / `PE:Wrap` as the file already does.
- `PocketEssentials.toc` `## Version: 0.11.1`. Do not touch `CHANGELOG.md`, `docs/TESTING.md`, anything under `probe/`, `tests/probe/`, `scripts/read-probe.lua` (another builder and the lead own those).
- `scripts/check.sh` and `scripts/test.sh` pass at the end of every task.

## Review Focus

1. A character key that cannot be read at login (`UnitName` nil early): no switch and no entry written; it waits for the next `PLAYER_ENTERING_WORLD`; test "switch: no character key yet does nothing".
2. Two characters, switch turned off on A, then B logs in with Off and ours still active on B: B gets its own back once, then nothing more on the next login; test "switch: off on A, B puts back once".
3. Player deletes their own saved layout that a character's entry points to: switch-off falls back to the Gamepad preset; test "switch: missing saved layout falls back to Gamepad".
4. Old saved file with `opts.prev` and no `opts.prevs`: migrated once, never twice; test "migrate: old prev moved or dropped once".
5. Login in a fight: nothing switches until the fight ends; test "switch: login in a fight waits".

---

### Task 1: Template: XP bar, map title, buffs

**Files:**
- Modify: `addons/PocketEssentials/ControllerLayout.lua` (`Plan.Pieces` around line 208, `ReadEnums` around line 367)
- Test: `tests/features/layout_test.lua`

**Interfaces:**
- Produces: XP pieces `StatusTrackingBar1` with `Spot("TOP", "TOP", 0, -2)`, `{ Size = 10 }`; `StatusTrackingBar2` placed as the Gamepad preset stacks it (find in `Blizzard_EditMode/Mainline/EditModePresetLayouts.lua` around line 600 and the status bar container code), `{ Size = 10 }`. Minimap settings `{ Size = ..., HeaderUnderneath = 1 }` when the enum exists. Buffs `TOPRIGHT -30, -292`, debuffs `-30, -330`, tracker `-30, -375`.
- `enums.setting.Minimap.HeaderUnderneath` read from `Enum.EditModeMinimapSetting.HeaderUnderneath`; when nil, the setting is left out (the plan's `Apply` must skip a setting whose enum is missing; check how it does today).

- [ ] Tests first: "plan: XP bars top middle at 100%", "plan: minimap header underneath", "plan: no HeaderUnderneath enum leaves it out", "plan: buffs, debuffs, tracker spots".
- [ ] Run `luajit tests/features/run.lua "$PWD"` (or how `scripts/test.sh` runs the feature tests): the new tests fail.
- [ ] Implement. Check `Blizzard_Minimap/Camelot/Minimap.lua` (`SetHeaderUnderneath`, line 68) for whether the header then sits under the map's bottom edge; if so, raise `Plan.MapY` by the header's height (from that code) and update the tests that pin `MapY` and the bar spots under the map. Write what you found in a comment.
- [ ] Update `docs/superpowers/specs/2026-11-21-controller-layout.md`'s table rows for the XP bars, buffs, debuffs, tracker and minimap to the new values (a one-line note pointing at the 0.11.1 spec).
- [ ] `scripts/check.sh && scripts/test.sh`: pass.
- [ ] Commit: `Controller layout 0.11.1: XP bar top middle, map title under the map, buffs clear of the chat`.

### Task 2: Per-character layout to go back to

**Files:**
- Modify: `addons/PocketEssentials/ControllerLayout.lua` (`SwitchOn` ~877, `SwitchOff` ~935, module `OnEnable` / `OnDisable` and `blocked` / `status` ~1157-1222, `defaults`)
- Test: `tests/features/layout_test.lua` (fake client gets `UnitName("player")`, `GetRealmName()` switchable between two characters, and an active-layout index per character)

**Interfaces:**
- Produces: `opts.prevs = { [key] = { name, layoutType, preset } }`, key `"<name>-<realm>"`; local `CharKey() -> string|nil`; `opts.prev` kept only for migration (read once, then set to `false`); `defaults.prevs = {}`. Everything that read `type(opts.prev) == "table"` reads this character's entry instead (`blocked`, `status`, `OnEnable`, `OnDisable`).
- The one off-state login check: when the module is off at login, it is not enabled, so add it where the module system lets a disabled module run once at login (look at how `statusWhenOff` and the Core's module loop work; if there is no hook, add the smallest one in `Core.lua` and test it in `tests/features/core_test.lua`). It registers nothing that stays.

- [ ] Tests first: "switch: On, no entry, own layout active: remembers it, makes ours active, asks reload", "switch: On, ours active: nothing changes", "switch: On, entry present, another layout active: left alone, status says another", "switch: Off puts back this character's own and removes its entry", "switch: off on A, B puts back once", "switch: missing saved layout falls back to Gamepad", "switch: no character key yet does nothing", "switch: login in a fight waits", "migrate: old prev moved or dropped once", "switch: off state registers no events after the login check".
- [ ] Run the feature tests: the new ones fail.
- [ ] Implement as spec section 2.
- [ ] Run `scripts/audit-api.sh` (about 45 s) so `UnitName`, `GetRealmName` and the enum are in `tests/api/*.txt`; cite their proof in the file header.
- [ ] `PocketEssentials.toc` `## Version: 0.11.1`.
- [ ] `scripts/check.sh && scripts/test.sh`: pass. `scripts/build.sh`: the player zip builds.
- [ ] Commit: `Controller layout 0.11.1: each character remembers its own layout`.
