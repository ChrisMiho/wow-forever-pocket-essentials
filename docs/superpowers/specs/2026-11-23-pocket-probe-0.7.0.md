# Pocket Probe 0.7.0: answers for the face bars, with almost nothing to do in a fight

**Approval.** Draft, 2026-11-23, from `docs/11-23-face-bars/HANDOFF.md` step 1.
Waiting for the owner's go.

## Why

The owner wants "face bars": our own display-only frames that draw the spells
where we like, while the game's real bars stay whole, faded to invisible, and
take the presses (`docs/11-23-face-bars/EVIDENCE.md`). Six questions decide
whether that works ("Open questions" in EVIDENCE). Level 1 fights end in
seconds and long text cannot be read on the handheld, so each question must be
answered by something that records by itself, or by one tap.

## Goals

- Every open question gets a recorded answer from one lunch session of normal
  play.
- In a fight the owner does at most one thing: tap the floating Fight button
  once.
- The recorder can run during the same session (today it refuses every test).
- The recorder's report stops giving wrong "In plain words" lines.

## Not goals

- Building any face bar. Cooldown numbers. Changing Pocket Essentials.

## Anti-goals

- A frame of ours created in a fight. Per-frame code (`OnUpdate`) in any
  watcher.
- A Blizzard frame left moved, faded or changed after a fight, Cancel, Stop, an
  answer, a reload or a logout. `PageUnit`'s own alpha is never written.
- Storing spell names, chat or anything but classes, counts and our own tags.
- The probe in a player zip.

## Approaches

- **A. Extend the probe as built (picked):** the watchers as a new file
  `Watch.lua` (loaded after `Run.lua`, before `Panel.lua`), the two guided
  trials in `Trials.lua`, the Fight button beside the recorder's Stop in
  `Perf.lua`, panel rows in `Panel.lua`. The saved file keeps its shape plus
  one new `watch` table; `read-probe.sh` learns to print it.
- B. Watchers always on whenever the probe is loaded. Fewer taps, but it would
  run code the owner did not ask for, and it would colour the performance
  recording. Turned down.
- C. A separate "lunch mode" window. One more window to drive with touch and a
  pad, for the same result. Turned down.

## 1. Floating "Fight" button

- Our own round button, made at load and hidden, the same size and look as
  the recorder's Stop (`Perf.lua`, `Disc`), label **Fight**, a different
  colour (amber). It sits beside Stop on the side away from the PE button; with
  no Stop showing it takes Stop's spot.
- Shown only while a fight is on (`PLAYER_REGEN_DISABLED` shows it,
  `PLAYER_REGEN_ENABLED` hides it; showing and hiding our own frames in a
  fight is allowed, 11-22 EVIDENCE), and only while the watchers are armed or
  a recording runs. Never shown without one of those, so it never appears in
  normal play.
- One tap runs the existing Fight tests pass (`P.RunFightTests`).
- **Recording pause:** while a recording runs, a Fight tap pauses it (no
  samples, the ticker kept but skipping), runs the pass, and resumes when the
  pass ends or is stopped. The sample after the pause has `dt=0` and a new
  activity letter `p` (probe pass) so the report leaves it out of the plain
  words. Run all safe and other passes keep refusing during a recording, as
  today.
- After the pass, the button shows a tick for 3 seconds (our texture), then
  stays usable; a second tap in the same fight runs the pass again.

## 2. Watchers: one tap out of a fight, then nothing

A row **Watch my next fights** with one button (**Arm** / **Disarm**), on the
"Controller and layout" tab or wherever the panel has room (see "Panel
room"). Out of a fight only. Armed until Disarm or a reload; the row shows
"Watching, 23 min" while armed. The owner (2026-11-23): "watch until reload it
is". Counts only, so the saved data does not grow with time (a few KB a
session). Each watcher is
installed once, the first time Arm is tapped (hooks cannot be taken off), and
does nothing while not armed.

All counts go to `PocketProbeDB.watch` (one table per arming: `started`,
`ended`, `why`, the sections below). At most 3 armings kept, oldest dropped.
Every handler goes through `P.Guard`. Each section notes `missing` when a game
name is not there.

### 2a. Active bar
- `PageUnit:RegisterActiveActionBarUpdatedCallback(callback, owner)`
  (`Blizzard_GamepadActionBars/PageUnit.lua:705`), fired from
  `SetActiveActionBar` (`:527-539`) when a trigger is pressed or let go.
  `PageUnit` is found as the probe already finds it.
- On each call: `PageUnit:GetActiveBar()` (`:542`), turned into one of
  `main`, `left`, `right`, `both`, `other` by comparing it with the four
  anchors' `.Bar`; `secret` if `IsSecret`, `error` if the call fails.
- Stored: counts per bar name, split "in a fight" and "out of a fight", and
  the first 20 changes as `t=<seconds>;<bar>;<c or o>`.

### 2b. Presses
- The gamepad buttons show a press through
  `GamepadActionBarButtonMixin:ApplyPressedStyle(pressed)`
  (`ActionBarButton.lua:421`), called from `TriggerSecureClick`
  (`:1111-1114`) and the pet buttons' `OnClick` (`:1182`).
- `hooksecurefunc(button, "ApplyPressedStyle", fn)` on each button instance of
  the four bars (found from each anchor's `.Bar`, the way the bars snapshot
  finds them). The builder confirms in the source that the instances carry
  the method (mixed in at creation, so a hook on the mixin table would not
  reach them).
- Stored: counts of `down` and `up`, in and out of a fight, per bar; whether
  `pressed` read as a boolean, secret or other. No slot numbers, no actions.

### 2c. Event rates
- Counts per event, in and out of a fight, and the seconds spent in each, for
  `ACTIONBAR_UPDATE_COOLDOWN`, `ACTIONBAR_UPDATE_USABLE`,
  `ACTIONBAR_UPDATE_STATE`, `ACTIONBAR_SLOT_CHANGED`, `SPELL_UPDATE_COOLDOWN`,
  `UPDATE_BONUS_ACTIONBAR` (EVIDENCE open question 6). One frame of ours,
  events registered only while armed. `read-probe` prints per minute.

### 2d. Cooldown sweep, once per arming
- On `ACTIONBAR_UPDATE_COOLDOWN` in a fight, at most once per second, check
  the main bar's slots with `C_ActionBar.GetActionCooldown(slot)`'s readable
  `isActive` / `isEnabled` flag (as `cd.sweep.object` does). The first slot
  found on cooldown: run the same steps as `cd.sweep.object` on square 1 (our
  frame, made at load), show the holder for 8 seconds and take one guarded
  `Screenshot()` 1 second in. Then this watcher is done until the next Arm.
- Stored: result (allowed, blocked, forbidden, error), "frame shown by itself"
  yes / no, the class of `GetCooldownDuration()` afterwards, and
  "screenshot: taken / none". No cooldown value.

## 3. "Fade the main bar for the next fight" (guided, nothing to do in it)

- A new guided trial, `bars.fadenext`, area "Blizzard windows", `manual`,
  `risky`, `short = "Fade for next fight"`. Start out of a fight only.
- Start: the big message "Main bar will vanish in your next fight. Just play."
  for 4 seconds; the trial waits (status line note as other guided trials).
- `PLAYER_REGEN_DISABLED`: `TopCenteredAnchor.Bar:SetAlpha(0)`; read back.
  Refused or not 0: stored as the result at once, the old value put back when
  the fight ends.
- During the fight, count main-bar presses (the 2b hook, if installed; Start
  installs it if it is not) and, from `UNIT_SPELLCAST_SUCCEEDED` for
  `player`, the number of casts. Counts only.
- `PLAYER_REGEN_ENABLED`: alpha read once more ("still invisible at the end:
  yes / no"), the old value written back, then the big message "Did your
  spells cast while the bar was invisible?" and the two answers **Yes, they
  cast** / **No**. The stored message adds the press and cast counts.
- Cancel, Stop, reload or logout: the old value put back (in a fight, held and
  put back when it ends, as the fade test does). Waits for the next fight
  until a reload, like the watchers.
- Never `PageUnit` (wheels reset its alpha, EVIDENCE).

## 4. "Wheels under a faded bar" (guided, out of a fight)

- New guided trial `bars.wheels`, area "Blizzard windows", `manual`, `risky`,
  `closePanel`, `short = "Wheels on a faded bar"`. Out of a fight only.
- Start: the four anchors' `.Bar` faded to 0 (each read back), big message
  "Bars faded. Open the pet wheel (LB+LT), then a spell wheel. Then tap
  Probe." Answers **Wheel visible** / **Wheel hidden**.
- While it waits, a hook records the first time a wheel opens:
  `PageUnit:OnFlyoutOpened(button)` (`PageUnit.lua:719`) through
  `hooksecurefunc` on the `PageUnit` instance. Stored: the popup's centre (x,
  y rounded), size, `GetEffectiveAlpha()`, and whether it is shown, read 0.2 s
  after it opens (`C_Timer.After`). Up to two wheels.
- One guarded `Screenshot()` 0.5 s after the first wheel opens.
- Answer, Cancel, Stop, reload, logout: all four alphas put back.

## 4b. "Clear saved results"

A row **Clear saved results** with one button, out of a fight only. First tap:
the button reads **Tap again to clear** for 5 seconds. Second tap in that time:
`PocketProbeDB`'s trial results, guided answers, `watch` and `perf.runs` are
emptied (a running recording or armed watcher is stopped first). The probe's
options (Risky, Auto, Vendor) are kept. Pocket Essentials' saved file is never
touched. The owner asked for "a simple way of clearing it out".

## 5. Recorder fixes (`Perf.lua`, `read-probe`)

- A memory reading of 0 is stored as missing (`mem=` field left empty for that
  addon), never as 0. The report's "least", "kept growing" and "heavy" skip
  missing readings.
- Each reload inside a run is marked in its sample (`a=` gets `r`); the report
  lists "reloads at: 3 min, 5 min" and leaves the 30 seconds after each reload
  out of "In plain words".
- A run under 10 minutes of samples left after that says "too short to judge"
  in "In plain words" instead of a verdict.
- Samples marked `p` (a Fight pass) are left out of "In plain words" too.

## 6. Probe button out of the XP bar's way

Pocket Essentials 0.11.1 puts the XP bar at the very top middle (spec
`2026-11-23-controller-layout-0.11.1.md`). The probe's button and status line
move down by 24 units (`TOP`, `UIParent`, `TOP`, 0, -28) so they do not cover
it. The big message and the sweep squares follow, as they are anchored to it.

## Panel room

The panel is at its ten-tab limit at 720p. Put the watcher row and the two
guided trials where there is room, splitting or merging areas as 0.5.0 did,
and keep the offline panel tests passing at 1365 by 768.

## Game names added, with proof (branch `forever`)

The builder re-checks each in `~/.cache/wow-ui-source/forever` and lists them
in the file headers.

| Name | Proof (to confirm) | Guard |
|---|---|---|
| `PageUnit:RegisterActiveActionBarUpdatedCallback` | `Blizzard_GamepadActionBars/PageUnit.lua:705` | method check, `pcall` |
| `PageUnit:GetActiveBar` | `PageUnit.lua:542` | `pcall`, `IsSecret` |
| `GamepadActionBarButtonMixin:ApplyPressedStyle` | `ActionBarButton.lua:421` | `hooksecurefunc` in `pcall` |
| `PageUnit:OnFlyoutOpened` | `PageUnit.lua:719` | same |
| `UNIT_SPELLCAST_SUCCEEDED` | `Blizzard_APIDocumentationGenerated` (builder finds the line) | event registered in `pcall` |
| the six action bar events in 2c | same (builder finds each line) | same |
| `Region:GetEffectiveAlpha` | `SimpleRegionAPIDocumentation.lua` (builder finds the line) | method check |

## Tests (offline, `tests/probe/run.lua`)

- Fight button: hidden out of a fight and when neither armed nor recording;
  shown in a fight when armed; a tap during a recording pauses and resumes it,
  and the sample after has `dt=0` and `p`.
- Watchers: Arm refused in a fight; arm, events counted in and out of a fight,
  Disarm ends it, a reload ends it; at most 3 armings
  kept; a missing `PageUnit` or method gives `missing`, nothing raises.
- Active bar callback turns each anchor's bar into its name; secret and error
  told apart.
- Sweep watcher runs once per arming, only in a fight, stores no value.
- `bars.fadenext`: fades on the fight's start, puts back on its end, asks,
  stores counts; Cancel, Stop and logout put the alpha back; never touches `PageUnit`.
- `bars.wheels`: fades four, records the wheel, puts four back on every exit.
- Clear: refused in a fight; one tap only arms it, two within 5 s clear;
  options kept; recording and watchers stopped first.
- Recorder: memory 0 stored as missing; reload mark; "too short to judge";
  `p` samples left out.
- `read-probe.sh` prints the `watch` table (`--details`) and the fixed report
  (`--perf`).

## Version

Probe TOC `## Version: 0.7.0`, the panel title and the probe's CHANGELOG
entry together. `dist/PocketProbe.zip` only.

## As built (2026-11-23)

Built as specified, in six commits (plan `2026-11-23-pocket-probe-0.7.0.md`).
New file `probe/PocketProbe/Watch.lua` (after `Run.lua`, before `Panel.lua`);
the CHANGELOG entry is left to the lead.

### Where things sit in the panel (1365 by 768, still ten tabs)

| Tab | Rows |
|---|---|
| Blizzard windows 1 | the map and bag buttons (4), Set the left bar's place, its size, **Read the main bar's 8 spells** (moved from Controller and layout) |
| Blizzard windows 2 | left bar see-through, left bar fade, Park, Fade the main bar, **Fade for next fight** (`bars.fadenext`), **Wheels on a faded bar** (`bars.wheels`), **Watch my next fights** (the row; with the bar trials it watches) |
| Chat box | the five chat trials, and the chat frame's two button trials (moved from Blizzard windows) |
| Bags and vendor | Open and close the bags, Sort, the three vendor trials, **Move the bag** and **Resize the bag** (moved from Blizzard windows) |
| Controller and layout | the six controller and layout trials, **Clear saved results** (the row) |

The two rows are not trials: they are not in the saved trial list, and the
tab counts ("N / M run") leave them out. The "Afterwards" tab, which appears
only after the game refuses its own actions in the probe's name, still makes
an eleventh tab, as before.

### Departures from the spec, and why

1. **The two sub-menu wheels never reach `PageUnit:OnFlyoutOpened`.** The
   source calls it only from a bar button's flyout
   (`ActionBarButton.lua:737-742`, through the button's bar, which is set
   only at `ActionBar.lua:34-35`); the LB+LT and RB+RT wheels belong to
   `LeftClassAction` / `RightClassAction`, which are on no bar. So
   `bars.wheels` also hooks `OnShow` of the wheels' own frames,
   `GamepadPetActionFlyout` (`Camelot/PetClassFlyouts.xml:18`) and
   `GamepadPetSpellFlyout` (`:72`), besides `OnFlyoutOpened` for a spell wheel
   on a bar. Each wheel is named in the answer ("pet wheel", "pet spell
   wheel", "bar wheel"); one opening seen by two hooks counts once.
2. **`GetEffectiveAlpha` is a Frame method** (`SimpleFrameAPIDocumentation.lua:366`),
   not a Region one. The wheels are frames, so nothing changes.
3. **The big message and the sweep squares were not anchored to the Probe
   button** (both sat on `UIParent`'s top). They are moved by the same 24
   units through one shared offset (`P.TOP_Y = -28`, `Core.lua`): the Probe
   button at `TOP, UIParent, TOP, 0, -28`, the squares at
   `TOPLEFT, UIParent, TOP, 230, -28`, the big message 24 lower than before.
4. **Panel room.** The new trials made Blizzard windows three pages, so four
   older rows moved (table above) to keep ten tabs.
5. **Clear saved results.** Guided answers are stored with the other results
   (`results`, `last`, `details`); `db.guided` holds only trials still
   waiting, with values to put back. So Clear empties `results`, `last`,
   `details`, `situations`, `spoiled`, `watch` and `perf.runs`, and before
   that stops a recording, disarms the watchers and, when a pass, the clean
   run or a guided trial is under way, calls Stop (which puts every frame and
   setting back). The switches and the activity log are kept.
6. **`bars.fadenext`, a refused fade.** It is stored at once, as specified;
   anything that changed goes back at once when the game takes it, and is
   held until the fight ends only when the game refuses the put-back (the way
   the fade test does). Its situation key reads `fight=no`: the fade is made
   in the `PLAYER_REGEN_DISABLED` handler, and lockdown starts after it.
7. **`bars.fadenext` closes the panel at Start**, so the 4-second message can
   be seen. Like every trial with a big message, while it waits (until its
   answer, Cancel or a reload) another big-message trial (Park, Fade the main
   bar, Wheels) cannot start: there is one big message.
8. **Casts.** `UNIT_SPELLCAST_SUCCEEDED` is registered for the player only
   (`RegisterUnitEvent`, `SimpleFrameAPIDocumentation.lua:1064`) when the
   client has it; otherwise for everyone, counting a unit that reads
   "player". Its unit can be secret in a fight
   (`SecretWhenUnitSpellCastRestricted`): such a cast is counted apart as
   "casts unreadable".
9. **The Fight button** ignores a tap while its own pass runs, while its tick
   shows (3 seconds), while another pass runs (it never takes one over), and
   during a guided trial's timed screenshot steps. A guided trial waiting for
   its answer does not stop it. The tick is the atlas
   `common-icon-checkmark` (`Blizzard_CharacterCreate/Camelot/Blizzard_CharacterCreate.lua:2986`)
   on a texture of ours; if the client lacks it, the label reads "Done".
10. **Disarm works in a fight**; only Arm is out of a fight only.
11. **The report.** The plain words of `--perf --diff` follow the same rules
    (pauses and the 30 s after each reload left out, "too short to judge"
    under 10 minutes). For files from probe 0.6.0, a sample after the first
    with `dt=0` counts as a reload, and a memory reading of 0 counts as
    missing. The tables still show every sample. The watch table prints with
    `--details` and in the full report.
12. **Names.** The plan's `P.PerfStop` is the existing `P.StopRecording`.
    `P.ClearSaved()` does the two taps itself (`P.ClearPending()` tells the
    panel). `P.Watched` (Run.lua) is exposed so the sweep watcher's call is
    noticed like a trial's. The sweep steps are shared through
    `P.SweepOnSlot` / `P.SweepSlot` (Trials.lua); `cd.sweep.object` behaves
    as before.

### Not proven off the device

- Whether `pressed` reaches the press hook as a plain true / false in a fight
  (its class is what is recorded).
- Whether the game's callback, the button hooks and the `PageUnit` hook leave
  the game's own controller actions working (the source's taint barrier and
  `hooksecurefunc` say they should).
- Whether a fade made in the `PLAYER_REGEN_DISABLED` handler stays for the
  whole fight on the device (it did in 0.6.0's in-fight fade).
- Whether the wheel frames' `OnShow` comes before they are placed: they are
  read 0.2 seconds later in any case.
- Whether the tick atlas exists in the game (not only at character creation).
