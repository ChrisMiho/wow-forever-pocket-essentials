# Pocket Probe 0.7.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer the face-bar open questions from one lunch session: a floating Fight button, watchers armed by one tap, two guided bar trials, a Clear row, and recorder report fixes.

**Architecture:** Extend the probe as built. New `probe/PocketProbe/Watch.lua` (loaded after `Run.lua`, before `Panel.lua`) holds the watchers and the Clear action; the two guided trials go in `Trials.lua`; the Fight button and the recorder pause and fixes in `Perf.lua`; rows in `Panel.lua`; the probe button move in `Run.lua`; the report in `scripts/read-probe.lua`.

**Tech Stack:** Lua 5.1 (LuaJIT for tests), WoW interface 16001 (Forever, "Camelot"), the probe's own fake client in `tests/probe/run.lua`.

**Spec:** `docs/superpowers/specs/2026-11-23-pocket-probe-0.7.0.md` (approved by the owner 2026-11-23). Read it whole first; this plan only fixes names, files and order.

## Global Constraints

- Nothing is created in a fight: every frame, texture and font string is made at load.
- No `OnUpdate` anywhere in the new code. Timers only through `C_Timer.After` / the existing ticker.
- Every handler, hook and callback goes through `P.Guard`.
- Never write `PageUnit`'s alpha. Fade only the four `*CenteredAnchor.Bar` frames.
- Store only classes, counts, rounded positions and our own tags. No spell names, no slot actions, no cooldown values, no chat.
- Every new game name verified in `~/.cache/wow-ui-source/forever` and listed with its file:line in the header of the file that uses it (the probe's existing header style).
- The probe never goes in the player zips. Do not touch `addons/`, `CHANGELOG.md`, `docs/TESTING.md`, `tests/api/`, `tests/features/` (another builder owns those).
- Probe TOC `## Version: 0.7.0` and the panel title together.
- `scripts/check.sh` and `scripts/test.sh` pass at the end of every task.

## Review Focus

1. A fight starting between arming and the first event, or the reload landing mid-fight: watchers and `bars.fadenext` must leave no bar faded after the fight ends; test "fadenext: reload during fight puts back on next login" (the saved hold is read at load, as the fade test's hold is).
2. Fight tap while a guided trial waits or a pass is already running: must not start a second pass; test "fight button: second tap during a pass is ignored".
3. `PageUnit` or the anchors missing (Gamepad UI off): Arm still works, sections say `missing`, nothing raises; test "watch: no PageUnit".
4. Clear tapped while a recording runs or watchers are armed: they stop first and the next sample does not write into a cleared table; test "clear: stops recording and watchers first".
5. Old saved files with no `watch` table, or a `watch` table with more than 3 armings: load and trim without error; test "watch: old file and trim to 3".

---

### Task 1: Watch.lua skeleton, Arm/Disarm, event rates, Clear

**Files:**
- Create: `probe/PocketProbe/Watch.lua`
- Modify: `probe/PocketProbe/PocketProbe.toc` (add `Watch.lua` after `Run.lua`; `## Version: 0.7.0`)
- Test: `tests/probe/run.lua` (load `Watch.lua` where the harness loads the probe files, in TOC order)

**Interfaces:**
- Produces: `P.WatchArm()`, `P.WatchDisarm(why)`, `P.WatchArmed() -> boolean`, `P.WatchCurrent() -> table|nil` (the current arming's table inside `PocketProbeDB.watch`), `P.ClearSaved() -> boolean, string`, `P.OnWatchChanged` (optional callback the panel sets). Arming table shape: `{ started=<date string>, ended=<string|nil>, why=<string|nil>, bar={}, press={}, events={}, sweep={} }`.
- Consumes: `P.Guard`, `P.Find`, `P.IsSecret`, `P.SetStatus`, `P.Recording`, `P.Busy` and the recorder's stop (expose `P.PerfStop` from `Perf.lua` if it is not already exposed).

- [ ] Tests first: "watch: arm refused in a fight", "watch: arm and disarm", "watch: events counted in and out of a fight" (each of the six events in spec 2c counted under `events[name].c` / `.o`, seconds in and out of a fight under `events._secs.c` / `.o`), "watch: reload ends it" (armed state not restored at load; the last arming gets `why = "reload"`), "watch: old file and trim to 3", "clear: refused in a fight", "clear: first tap only arms, second within 5 s clears, after 5 s starts over", "clear: options kept", "clear: stops recording and watchers first".
- [ ] Run `luajit tests/probe/run.lua "$PWD"`: the new tests fail.
- [ ] Implement. One event frame of ours made at load; events registered on Arm and unregistered on Disarm. `PLAYER_REGEN_DISABLED` / `ENABLED` registered while armed for the in-fight split. Clear empties `db.results`, guided answers (`db.guided`), `db.watch`, `db.perf.runs` (use the real field names in `Core.lua`), keeps `db.options`.
- [ ] Run `scripts/check.sh && scripts/test.sh`: pass.
- [ ] Commit: `Pocket Probe 0.7.0: watchers (arm, event rates) and Clear saved results`.

### Task 2: Active bar and press watchers, sweep watcher

**Files:**
- Modify: `probe/PocketProbe/Watch.lua`
- Test: `tests/probe/run.lua` (give the fake `PageUnit` a `RegisterActiveActionBarUpdatedCallback`, `GetActiveBar`, and buttons with `ApplyPressedStyle` on the anchors' `.Bar`)

**Interfaces:**
- Produces: `P.WatchInstallPressHooks() -> number` (buttons hooked; safe to call twice, hooks once per button), `P.WatchBarName(bar) -> "main"|"left"|"right"|"both"|"other"`. Press counts under `press[<bar name>].down.c` etc. and `press.kind` (`"boolean"`, `"secret"`, `"other"`). Bar counts under `bar[<name>].c/.o`, `bar.first` (array of up to 20 strings `t=<s>;<name>;<c|o>`). Sweep under `sweep = { result, shownByItself, durClass, screenshot }`.
- Consumes: the sweep square and holder from `Trials.lua`'s `cd.sweep.object` (factor out a shared `P.SweepOnSlot(slot) -> result table` there if it is not already callable; keep `cd.sweep.object`'s behaviour and tests unchanged).

- [ ] Tests first: "watch: bar callback names each anchor's bar", "watch: GetActiveBar secret and error told apart", "watch: no PageUnit" (every section `missing`, no error), "watch: press hook counts down and up per bar, in and out of a fight", "watch: press hooks installed once", "watch: sweep runs once per arming, only in a fight, at most one check per second, stores no value", "watch: screenshot missing changes nothing else".
- [ ] Run the probe tests: the new ones fail.
- [ ] Implement. Confirm in the source that the button instances carry `ApplyPressedStyle` (mixin applied at creation) and record that line in the header. `hooksecurefunc(button, "ApplyPressedStyle", fn)` per instance through `pcall`. Bar callback registered once, on the first Arm.
- [ ] `scripts/check.sh && scripts/test.sh`: pass.
- [ ] Commit: `Pocket Probe 0.7.0: active bar, press and cooldown sweep watchers`.

### Task 3: Guided trials `bars.fadenext` and `bars.wheels`

**Files:**
- Modify: `probe/PocketProbe/Trials.lua`, `probe/PocketProbe/Run.lua` (only if the guided machinery needs a new stage such as `"waitfight"`)
- Test: `tests/probe/run.lua`

**Interfaces:**
- Consumes: `P.WatchInstallPressHooks()` (Task 2) to count main-bar presses during `bars.fadenext`; the existing guided-trial stages, big message, `shots`, the fade test's hold-and-put-back-after-fight code.
- Produces: trial ids `bars.fadenext`, `bars.wheels`, with the labels, big messages and answers exactly as in spec sections 3 and 4.

- [ ] Tests first: "fadenext: refused in a fight", "fadenext: fades on fight start, reads back, puts back on fight end, then asks", "fadenext: refused write stored at once and put back when the fight ends", "fadenext: counts presses and casts", "fadenext: Cancel, Stop, logout put back", "fadenext: reload during fight puts back on next login", "fadenext: never touches PageUnit", "wheels: refused in a fight", "wheels: fades four and reads back", "wheels: records up to two wheels (centre, size, effective alpha, shown) 0.2 s after open", "wheels: one screenshot 0.5 s after the first wheel", "wheels: puts four back on answer, Cancel, Stop, logout".
- [ ] Run the probe tests: the new ones fail.
- [ ] Implement. `bars.wheels` hooks `PageUnit:OnFlyoutOpened` with `hooksecurefunc` on the instance once; the hook does nothing unless the trial waits.
- [ ] `scripts/check.sh && scripts/test.sh`: pass.
- [ ] Commit: `Pocket Probe 0.7.0: fade for next fight, wheels on faded bars`.

### Task 4: Fight button and recording pause

**Files:**
- Modify: `probe/PocketProbe/Perf.lua`, `probe/PocketProbe/Run.lua` (`RunFightTests` and the `RECORDING` refusal)
- Test: `tests/probe/run.lua`

**Interfaces:**
- Consumes: `P.WatchArmed()` (Task 1), `P.RunFightTests`, `Place()` and `Disc()` in `Perf.lua`.
- Produces: frame `PocketProbeFloatFight` (the panel already has `PocketProbeFightButton`). `P.PerfPause()`, `P.PerfResume()`. Sample activity letter `p`.

- [ ] Tests first: "fight button: hidden out of a fight", "fight button: hidden in a fight when not armed and not recording", "fight button: shown in a fight when armed, and when recording", "fight button: placed beside Stop away from the PE button, or in Stop's spot", "fight button: tap during a recording pauses, runs the pass, resumes; next sample has dt=0 and p", "fight button: Run all safe still refused during a recording", "fight button: second tap during a pass is ignored", "fight button: tick shown 3 s then usable again".
- [ ] Run the probe tests: the new ones fail.
- [ ] Implement as spec section 1 (amber disc, label "Fight").
- [ ] `scripts/check.sh && scripts/test.sh`: pass.
- [ ] Commit: `Pocket Probe 0.7.0: floating Fight button, recording pauses for a pass`.

### Task 5: Recorder fixes and the report

**Files:**
- Modify: `probe/PocketProbe/Perf.lua` (memory 0 as missing, `r` mark), `scripts/read-probe.lua` (`--perf` plain words, `--details` prints `watch`)
- Test: `tests/probe/run.lua`, `tests/readprobe/` (its existing runner and fixtures)

**Interfaces:**
- Consumes: sample format in `Perf.lua`'s header (`a=` letters, `mem=` field order).
- Produces: `mem=` with an empty field for a missing reading (e.g. `mem=,812,96`); `a=` gains `r` on the first sample after a reload and `p` from Task 4.

- [ ] Tests first: "perf: memory 0 stored as missing", "perf: first sample after a reload has r", "read-probe: least/kept growing/heavy skip missing memory", "read-probe: lists reloads at minutes and leaves 30 s after each out of plain words", "read-probe: under 10 minutes left says too short to judge", "read-probe: p samples left out of plain words", "read-probe: --details prints watch armings (bar counts, presses, events per minute, sweep)", "read-probe: old file without watch prints as before".
- [ ] Run both suites: the new ones fail.
- [ ] Implement. Update the sample format block in `Perf.lua`'s header.
- [ ] `scripts/check.sh && scripts/test.sh`: pass.
- [ ] Commit: `Pocket Probe 0.7.0: recorder report fixes, watch table in read-probe`.

### Task 6: Panel rows, probe button move, version

**Files:**
- Modify: `probe/PocketProbe/Panel.lua`, `probe/PocketProbe/Run.lua` (probe button `TOP`, `UIParent`, `TOP`, 0, -28)
- Test: `tests/probe/run.lua` (existing panel-fit tests at 1365 by 768)

**Interfaces:**
- Consumes: `P.WatchArm/Disarm/Armed`, `P.ClearSaved`, `P.OnWatchChanged`, trial ids from Task 3.
- Produces: rows "Watch my next fights" (button **Arm** / **Disarm**, text "Watching, N min" while armed) and "Clear saved results" (button **Clear** / **Tap again to clear**). Panel title shows 0.7.0.

- [ ] Tests first: "panel: watch row arms and shows Watching", "panel: clear row two taps", "panel: still fits ten tabs at 1365 by 768 with the new rows and trials", "probe button at TOP 0,-28; big message and sweep squares follow it".
- [ ] Run the probe tests: the new ones fail.
- [ ] Implement. Put rows and trials where there is room (spec "Panel room"); note where in the spec's "As built" section at the end (create it).
- [ ] `scripts/check.sh && scripts/test.sh`: pass. `scripts/build.sh` builds `dist/PocketProbe.zip` with `Watch.lua` inside.
- [ ] Commit: `Pocket Probe 0.7.0: panel rows, probe button out of the XP bar's way`.
