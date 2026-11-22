# Performance recorder (probe 0.5.0, Pocket Essentials measuring hook)

Status: draft for the owner's approval. Date: 2026-11-21.

## Why

Before 1.0.0, the owner wants proof that Pocket Essentials is still a lightweight addon now that it has grown well past "a few toggles".
A code audit on 2026-11-21 found it light: nothing ticks when idle, frames are built lazily, login work is under 1 ms offline.
The biggest memory cost turned out to be the QuestieDB data addon, not our code.
All of that came from reading code and from LuaJIT on a Mac, never from the handheld.
This feature measures the real cost on the device while the owner plays normally, in total and per feature.
That shows where the weight is, and gives before and after numbers for the planned fixes (see Follow-ups).

## What the owner sees

1. Pocket Probe is installed next to Pocket Essentials, and both are switched on. The owner logs in.
2. Recording starts by itself at login. A small red dot shows in the bottom-right corner of the screen. A round Stop button appears next to the PE button.
3. The owner plays as normal. Nothing else is on screen, and nothing needs typing.
4. Opening the probe window (the existing Probe entry) shows "Recording" with the time so far.
   Its Close button closes the window and recording carries on.
   It also has a Stop button.
   If recording is stopped, the window has a Start recording button instead.
5. Tapping Stop, next to the PE button or in the window, ends the recording. The dot and the Stop button disappear.
6. The recording is written to the probe's saved file at the next `/reload` or logout, the same as every other probe result.
   The owner copies `PocketProbe.lua` off the device as now.
7. `scripts/read-probe.sh <file> --perf` prints the report.
   `--perf --diff <other file>` compares two recordings, for example before and after a fix.

```
                                   ┌─────┐┌─────┐
                                   │STOP ││ PE  │   ← Stop pinned beside the PE button
                                   └─────┘└─────┘


                                               ●   ← red dot, bottom-right corner
```

## Goals

- **Whole-addon numbers from the game itself:**
  - time per frame: average, recent and peak
  - how many frames took over 1, 5 and 10 ms
  - share of all addons' time
  - memory for Pocket Essentials, QuestieDB and Pocket Probe, and frame rate
- **Per-feature numbers:** time, number of runs, and the slowest single run for each feature key (quest icons, bags, core and so on), with the busiest events for each.
- **Activity tags:** every sample says what the owner was doing in that stretch, so the report can split the numbers by activity with nothing to label by hand. The tags are in combat, in a dungeon, at a vendor, world map open, bags open, and moving or standing still.
- **No typing:** start, stop and restart are all done by tapping.

## Non-goals

- Anything a player sees in Pocket Essentials. There is no setting, menu or button for this in the player addon in this round.
- Guidance for players based on how their device performs. See Follow-ups.
- Performance fixes. They are a separate round that uses this tool's numbers.
- The old `scriptProfile`-based CPU functions (`GetAddOnCPUUsage` and the rest). They could not be verified and they slow every addon.

## Anti-goals (a failure even if it works)

- The recorder covers part of the screen or takes taps meant for the game. The red dot must ignore the mouse and touch.
- The measuring makes Pocket Essentials noticeably heavier, so the numbers measure the recorder.
- Any cost for players who don't have the probe. With the probe absent, the hook must stay asleep.
- A Lua error from the recorder in a normal play session.

## Constraints

- **Project rules:** Interface 16001 with the modern API, no libraries, handlers through `PE:Safe`/`PE:Wrap`, and nothing ticks while off.
- **Verify every new game call** in the `forever` branch of Blizzard's source, run `scripts/audit-api.sh`, and log anything unverified in `docs/ARCHITECTURE.md`. Already verified on build 1.60.1 (70938):
  - `C_AddOnProfiler.IsEnabled`, `GetAddOnMetric`, `GetOverallMetric`, `GetApplicationMetric` and `MeasureCall` (Doc/AddOnProfilerDocumentation.lua)
  - `Enum.AddOnProfilerMetric` (Doc/AddOnProfilerConstantsDocumentation.lua:26-37)
  - `UpdateAddOnMemoryUsage` and `GetAddOnMemoryUsage` (Doc/PerformanceDocumentation.lua:94, 25)
  - `debugprofilestop` (Doc/FrameScriptDocumentation.lua:533)
  - `GetFramerate` (Doc/ClientDocumentation.lua:44)
  - `C_AddOns.IsAddOnLoaded` (Doc/AddOnsDocumentation.lua:322)
- **Memory reads:** `UpdateAddOnMemoryUsage` is expensive. Blizzard calls it at most once per 15 s (AddonList.lua:775-785). Use the same limit.
- **The game's profiler may be switched off** on the device. When `C_AddOnProfiler.IsEnabled()` is false, record memory, frame rate and our own per-feature timing, and say "profiler off" in the report.
- **The probe is test-only.** It ships only in `dist/PocketProbe.zip`, never in the player zips. Its trials still expect Pocket Essentials off. Recording is the one probe mode meant to run with it on.
- **Versions:** bump the probe to 0.5.0. Pocket Essentials gets a version bump and a CHANGELOG entry together (owner rule). The new section in `docs/TESTING.md` is the device test.

## Approaches considered

1. **All in the probe (whole addon only).** No change to the player addon, but no per-feature split. The probe cannot reach Core's event list, timers or wrappers, which are private (`Core.lua:447`, `:726`). They are also set up at login, before recording could start.
2. **A setting and a performance page in Pocket Essentials.** Every player could see it, but it puts more code and a new screen in front of players right before 1.0.0. Blizzard's addon list already shows profiler numbers when the profiler is on.
3. **Chosen: the probe does the recording and reporting, plus a small sleeping measuring hook in Pocket Essentials' Core.** The owner wanted total and per-feature numbers, and this is the smallest way to get both. The hook is a debug utility: off by default, with no player-facing switch in this round. A switch on the Debug log page could be added later.

## Design

### A. Measuring hook in Pocket Essentials (Core.lua)

- **Turning it on and off:**
  - `PE:StartMeasure()` turns measuring on, idempotently, and returns the counters table.
  - `PE:StopMeasure()` turns it off.
  - `PE:MeasureCounters()` returns the counters.
  - They are reached through the existing `_G.PocketEssentials` (Core.lua:7). Nothing in Pocket Essentials calls them, and the player never sees them.
- **Where it times:** the shared places all feature code passes through:
  - the event dispatcher (Core.lua about 1162-1216), covering both the core list and each module's handlers
  - `Methods:After` timers (:773)
  - `PE:Wrap` (:353), which covers `Methods:Wrap` and every per-frame driver: QuestArrow, QuestIcons and Move
  - `PE:Safe` (:343) and `Methods:Safe` (:767)
- **While measuring:** each run is timed with `debugprofilestop()` before and after. The time goes into `counters[key]` as total ms, call count and slowest run, where `key` is the feature key these paths already know. For the dispatcher it also goes into `counters[key].events[event]` (ms and calls).
- **While not measuring:** one upvalue boolean test per run, then the exact code that runs today. Wrapped functions are made at login, so the test has to be at run time, inside the returned function.
- **Hot path:**
  - no new strings, no new tables except the first time a key or event is seen, and no closures per run
  - no ticker, frame or event of its own
  - it doesn't count its own time, beyond the clock reads themselves
- **Errors:** an error still goes through the same handler as today. The time up to the error is counted.
- **Nested runs** (a wrapped function called from a handler) are counted in both. The report treats "core" and the per-feature rows as overlapping, not as parts adding up to the total. The total comes from the game's profiler.

### B. Recorder in Pocket Probe

- **Starting by itself:**
  - Once the player has logged in, if Pocket Essentials is loaded and the owner hasn't stopped recording this session, the probe starts recording and calls `PE:StartMeasure()`.
  - A recording that is on survives `/reload`: the same run carries on.
  - If Pocket Essentials isn't loaded, nothing starts, and the probe behaves exactly as 0.4.0.
- **Stopping:** Stop (either button) ends the run and calls `PE:StopMeasure()`. The stopped state lasts until Start recording or the next fresh login. Builder: a fresh login starts a new run by default; a reload keeps the stopped state.
- **Sampling:**
  - A `C_Timer.NewTicker` every 15 s, only while recording.
  - Each sample stores the time and the profiler metrics for Pocket Essentials, overall and application. Counters that only ever grow are stored as the change since the last sample.
  - It also stores the memory of the three addons, the frame rate, and the change in Pocket Essentials' per-feature counters.
  - It stores the activity tags seen during the stretch.
- **Activity tags:** come from events and show/hide hooks, never from per-frame checks. Builder: verify each event or frame before use.
- **Limits:** at most 480 samples per run (2 hours). Recording then stops by itself and says so. Keep the last 3 runs; older ones are removed at load. Probe results from another probe version are cleared at load, as now.
- **Red dot:**
  - a small red disc in the bottom-right corner, sized from the same 720p button metrics the panel uses
  - it doesn't take mouse or touch
  - drawn on the HIGH strata, the same as the PE button
  - shown only while recording
- **Stop button:**
  - round, the same size and look as the PE button
  - anchored to `PocketEssentialsHubButton` (Hub.lua:220) on the side facing the middle of the screen, so it follows the PE button, including onto the world map's book icon
  - if the PE button is missing or hidden, it sits just above the red dot
  - shown only while recording
  - touch only; see "Reaching Stop with the d-pad"
- **Probe window:** see "Probe window and trials while recording" above.

### Where the per-stretch numbers come from (author's call after review)

The game's profiler numbers don't cover "this run" or "this 15 s stretch":

- `SessionAverageTime` and `PeakTime` run from game start.
- `RecentAverageTime` covers only the last 60 frames.

So the numbers are split like this:

- **Exact, per stretch, from our own hook:**
  - total time spent in Pocket Essentials code. Only the outermost runs are counted, with a depth counter, so nested runs aren't counted twice.
  - the slowest single run
  - the per-feature rows

  These drive the run average, the activity split, the diff and the light/heavy marks.
  Average ms per frame is the stretch's total ms divided by the frames in it. The frame count is estimated from the average frame rate and the elapsed time, and the report says so.
- **Exact, per stretch, from the game:** the change in the `CountTimeOver1Ms` to `CountTimeOver1000Ms` counters.
- **From the game, as a cross-check:** `RecentAverageTime` (a snapshot) and the session average and peak, labelled "since the game started".

Pocket Essentials' counters start from zero again after a reload. The recorder notices a counter going down and treats it as a restart.

### Probe window and trials while recording (author's call after review)

- **Recording line:** a line across the top of the window shows the recording state, elapsed time, Stop and Start recording. The window's existing Close button closes it while recording carries on.
- **Trial buttons:** they stay where they are. While Pocket Essentials is loaded they are dimmed, with a note that trials need Pocket Essentials off.
- **No overlap:** trials and recording never run together, so a Clean run's reloads don't have to keep a recording going.

### Reaching Stop with the d-pad (author's call after review)

- **The floating Stop button is touch-only,** like the PE button.
- **On a controller,** you stop from the probe window, whose d-pad control already works while it is open.
- **No d-pad bindings during play:** the probe takes none while recording.

### C. Report (scripts/read-probe.lua)

- **`--perf`:** for each run, with "profiler off" when it was off:
  - profiler numbers: average and peak ms per frame, frames over 1, 5 and 10 ms (count and per minute), share of all addon time
  - memory for each addon: start, minimum, maximum, end, and growth in KB per minute
  - frame rate: average and lowest
  - a per-feature table: total ms, runs, ms per run, slowest run and the top 3 events, sorted by total ms
  - the same headline numbers split by activity tag
- **`--perf --diff <other file>`:** puts the headline numbers and the per-feature table of the newest run in each file side by side.
- **Plain-language summary:** every report ends with a few lines a player can read, comparing against rough marks:
  - light: under 0.1 ms per frame on average, under 2 MB of our own memory, few frames over 5 ms
  - heavy: anything at or over 1 ms per frame, or memory that keeps growing

### Tests

- **Offline:** tests for the hook, the recorder and the report, in the existing suites (`tests/features`, `tests/probe/run.lua`, read-probe checks). They need stand-ins for the profiler and memory calls.
- **Hook tests:**
  - off: the counters don't change and the wrapped function's results pass through unchanged
  - on: time and calls are counted per key and event
  - an error in a handler is still reported once
- **Smoke test:** the whole addon with the probe loaded starts the recorder and stops cleanly.
- **Device test:** a new section in `docs/TESTING.md`, in plain steps:
  1. Log in with both addons on and check that the dot and the Stop button appear.
  2. Play about 15 minutes covering town, questing, a vendor and some combat.
  3. Tap Stop, `/reload`, and send the file.
  4. Repeat with all Pocket Essentials features off for a baseline.

## Left to the builder

- exact sizes and spacing of the dot and the Stop button within the 720p metrics
- how the activity tags are detected, within "events and hooks, never per frame"
- the layout of the saved data, as long as `read-probe.lua` can read it and old probe files still load
- report wording and formatting

## Follow-ups (not in this round)

- **Fixes from the 2026-11-21 audit, measured with this tool before and after:**
  - lower the debug log cap from 10,000 lines
  - build quest pins only after thinning (QuestData.lua:249, :302)
  - clear QuestieDB's caches on Release (QuestData.lua:790)
  - stop the controller layout re-reading every layout on each bar refresh
- **A "Measure performance" switch** on Pocket Essentials' Debug log page, so this works without the probe.
- **The owner's idea: guide players by how their device is doing,** for example suggesting which features to turn off on a struggling device. Decide after real recordings show whether it's worth building.
