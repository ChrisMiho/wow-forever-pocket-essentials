# Pocket Probe 0.5.0: fight button, clearer park test, fade and sweep tests

**Approval.** Scope agreed by the owner in conversation on 2026-11-22
(`docs/11-22-playsession/HANDOFF.md`, step 1). On the same day, before
stepping away, the owner chose "Fade tests + screenshots" for the optional
extras and said to build and publish without a review stop. This spec is
approved by that instruction.

## Why

The last device session (`docs/11-22-playsession/EVIDENCE.md`) left three
questions open that decide how compact the controller screen can get:

1. Does a parked or faded main bar still cast? (finding 4: no answer)
2. Can a real see-through change be made in a fight? (finding 2: only "set
   to the value it already has" was tried)
3. Can a button of ours show a cooldown sweep in a fight?

It also showed the probe is hard to drive in a fight: the wrong button got
tapped, and the on-screen instruction could not be read.

## Goals

- One tap in a fight runs everything worth running there, and nothing known
  to be refused.
- A park test and a fade test the owner can follow on the handheld and
  answer with confidence.
- A recorded answer, allowed or refused, for each open question.

## Not goals

- Cooldown numbers, a stopwatch from casts, position pictures.
- Any change to Pocket Essentials.

## Anti-goals

- A frame of ours created in a fight.
- Anything that runs by itself.
- A Blizzard frame left moved or faded after Cancel, Stop, an answer, a
  reload or a logout.
- The probe in a player zip.

## Approaches

- **A. Extend the probe as it is built (picked):** new trials in
  `Trials.lua` with flags `Run.lua` reads, one more footer button, one
  message frame. Smallest change; the saved file and `read-probe` stay the
  same shape.
- B. A separate "fight mode" window with its own big buttons. Clearer, but a
  second window to keep working with touch and the controller, for one tap.
- C. Run the fight tests by themselves when a fight starts. Turned down:
  nothing in the probe runs by itself unless Auto is on, and the owner
  should know what ran.

## 1. "Fight tests" footer button

- A seventh footer button, label **Fight tests**, placed second (after Run
  all safe). The footer already fits its labels to the button width.
- Tapped out of a fight it does nothing but set the status: "Fight tests:
  start a fight first, then tap this." (Run all safe covers the rest.)
- Tapped in a fight it starts a pass from the press (`trigger = "press"`,
  first trial inside the tap, as Run all safe does). The list, in order:
  1. trials marked `fight = true` that are not risky, in file order;
  2. the rest of what Run all safe would run, **minus** trials marked
     `noFight = true`, trials marked `last` (they raise a test error and
     pop the game's error box), `manual` trials and vendor trials;
  3. with Risky On: risky trials marked `fight = true`.
- `noFight = true` on `pad.bind` and `pad.mark` (EVIDENCE finding 7). The
  chat box and bag-open trials are risky and not marked `fight`, so they
  never run here.
- Run all safe is unchanged (it still runs `pad.*`; that is its job out of
  a fight).
- What ran is shown plainly: while running, the usual "pass n/m id"; at the
  end the status reads "Fight tests done: N run, A allowed or readable, B
  refused" and the log gets one line with every trial id and its result.
- The pass stops, as passes do, if the fight ends part-way; the status then
  says how many ran.

## 2. Big message

A frame of ours made at load: centred on the screen's upper third, a dark
backing, text about twice the panel's font size, at most two short lines,
word-wrapped inside 60% of the screen's width. It takes no clicks and no
controller keys. A guided trial with a `big` text shows it when its question
stage starts and hides it on answer, cancel, stop and logout. It replaces
the long status-line text for that trial (the status line keeps a short
"<trial> is waiting: answer or Cancel").

## 3. Park test (`bars.park`), clearer

Same trial id, same idea (move `TopCenteredAnchor` up 3000, out of a fight
only), with these changes:

- **Bars snapshot**, stored in the result's message, just before parking
  and just after: for each of the four bars (`Top/Left/Right/Bottom
  CenteredAnchor.Bar`) and the bars riding on the top anchor
  (`TopCenteredAnchor.PossessBar`, `.StanceBar`,
  `PageUnit.FriendlyTargetingActionBar`, `.HostileTargetingActionBar`,
  `.ShortcutsActionBar`): shown yes/no, centre x and y rounded to whole
  units, on screen yes/no. Plus one count each time: "bars shown and on
  screen: N". A missing frame is written as "missing".
- **Screenshots**, optional and guarded: `Screenshot()` through `pcall`,
  only if it is a function. Sequence after Start: the panel closes; 0.5 s
  later screenshot 1; 0.5 s later the bar is parked (the trial's `ready`
  is checked again; if a fight has started, nothing is moved and the result
  is "not tried, in combat"); 0.5 s later screenshot 2; then the big
  message shows. The result's message says "screenshots: 2", "1" or "none
  (not on this client)". A trial opts in with `shots = true`.
- **Big message:** "Main bar parked. Press a spell, then tap Probe."
- Answers unchanged: **Spell cast** / **Nothing happened**.
- The owner's steps (TESTING section 23) say: count the bars before Start,
  count again after, press a spell, then answer.

## 4. Fade test (`bars.fadecast`), new, guided

- Area "Blizzard windows", `short = "Fade the main bar"`, `kind =
  "guided"`, `manual`, `risky`, `shots = true`, `closePanel`.
- Start (allowed in a fight too; that is part of the question): reads the
  main bar's see-through (`TopCenteredAnchor.Bar:GetAlpha()`), sets it to
  0, reads it back. Not 0 afterwards, a block or an error: stored at once
  as the result, and the old value put back.
- **Big message:** "Main bar is invisible. Press a spell, then tap Probe."
- Answers: **Spell cast** / **Nothing happened**.
- On answer the see-through is read once more before it is put back, and
  the message records "still invisible at the answer: yes/no" (the game may
  set it itself). The old value is then written back. If that is refused in
  a fight it is held and retried when the fight ends, as the park test
  does. A reload puts it back in any case.

## 5. Real fade in a fight (`bars.fade`), new, action

- Area "Blizzard windows", `risky`, `fight = true`. Label "Fade the left
  bar to nothing and back (run it in a fight)".
- Run: left anchor's see-through read, set to 0, read back, pass if it
  reads 0 (within 0.001). Undo: the old value written back, always.
- `bars.alpha` (same value) also gets `fight = true`.

## 6. Cooldown sweep (`cd.duration`, `cd.sweep.object`, `cd.sweep.numbers`)

Area "Controller and layout" (or a new tab if that one is full; the panel
splits a full area by itself, see "Panel room"). All three `fight = true`,
not risky (they touch only frames of ours).

Made at load, hidden: a holder with two 48 by 48 squares side by side at
the top centre of the screen, each a texture (the spell's icon) with a
`Cooldown` child (`CooldownFrameTemplate`, countdown numbers hidden), and a
small "1" and "2" under them.

- **`cd.duration`** (value): `C_ActionBar.GetActionCooldownDuration(slot)`
  for each main bar button that holds a spell. Recorded as the other spell
  fields are: how many readable, secret, nil, error. Never a value.
- **`cd.sweep.object`** (action): picks a main bar slot, preferring one
  whose cooldown the game says is running (the `isActive` or `isEnabled`
  flag of `C_ActionBar.GetActionCooldown`, when readable), else the first
  with a spell. Sets square 1's icon, then
  `cooldown1:SetCooldownFromDurationObject(durationObject)`. Result: allowed
  (no error, no block), blocked, forbidden or error, as the probe already
  tells them apart. The message adds: slot on cooldown yes / no / unknown;
  `cooldown1:IsShown()` afterwards; the class of
  `cooldown1:GetCooldownDuration()` afterwards.
- **`cd.sweep.numbers`** (action): the same slot; `startTime` and
  `duration` from `C_ActionBar.GetActionCooldown(slot)` passed straight to
  `cooldown2:SetCooldown(start, duration)`. Same recording.
- When either sweep trial runs, the holder shows for 8 seconds and then
  hides (one timer; a second run restarts it). One guarded `Screenshot()`
  1 second after it shows. So the owner can see, and the picture can show,
  whether a dark sweep turns on square 1, square 2, both or neither.
- No trial stores a cooldown value. No countdown numbers.

## 7. Sizes (`layout.sizes`), more rows

Added to the list: `MinimapCluster.MinimapContainer`, `Minimap`, and the
`Left/Right/BottomCenteredAnchor.Bar` frames. The map's Edit Mode size
scales the container inside the cluster
(`Blizzard_Minimap/Mainline/Minimap.lua:418-419`), so the container's scale
tells which size setting a measurement was taken at.

## Panel room

The panel is at its ten-tab limit at 720p and "Controller and layout" is
full. New trials must not push the panel past what fits: put them where
there is room, or merge two small areas into one tab, and keep the existing
offline panel tests passing at 1365 by 768.

## Game names added, with proof (branch `forever`, build 1.60.1.70938)

| Name | Proof | Guard |
|---|---|---|
| `Screenshot` | `Blizzard_APIDocumentationGenerated/ClientDocumentation.lua:95`, a plain function, no protected flag; Blizzard calls it from Lua at `Blizzard_CharacterCreate/Camelot/Blizzard_CharacterCreate.lua:457` | `type(...) == "function"` and `pcall` |
| `C_ActionBar.GetActionCooldownDuration` | `ActionBarFrameDocumentation.lua:181`, returns a `LuaDurationObject` | `needs`, `pcall` |
| `Cooldown:SetCooldownFromDurationObject` | `FrameAPICooldownDocumentation.lua:308`, **marked protected**: being refused is a possible, useful answer | method check, the probe's catcher |
| `Cooldown:SetCooldown` | `FrameAPICooldownDocumentation.lua:281`, **marked protected**, secret arguments "AllowedWhenUntainted" | same |
| `Cooldown:GetCooldownDuration`, `SetHideCountdownNumbers` | same file, lines 34 and 461 | method check, `pcall` |
| `CooldownFrameTemplate` | used across Blizzard's XML, e.g. `Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerShared.xml:35` | `pcall` around `CreateFrame`; without it the sweep trials answer "missing" |

The builder re-checks each line in `~/.cache/wow-ui-source/forever` and
lists them in the file header, as the probe already does.

## Tests (offline)

In `tests/probe/run.lua`, with the probe's existing fake client:

- Fight tests: refuses out of a fight; in a fight the list has the `fight`
  trials first, no `noFight`, `last`, `manual`, vendor or (Risky Off) risky
  trial; with Risky On it ends with `bars.alpha` and `bars.fade`; the
  summary line counts right.
- Park: the snapshot is in the stored message before and after; the
  timed sequence runs in order; a fight starting before the park moves
  nothing; `Screenshot` missing or raising changes nothing else.
- Fade test: sets 0, asks, records "still invisible", puts the old value
  back on answer, cancel, stop and logout; a refused write is stored as
  the result.
- `bars.fade`: pass, fail and undo.
- Sweep trials: allowed, blocked and error are told apart; a missing
  method answers "missing"; the holder shows and hides; no value is stored.
- Big message: shows and hides at the right stages.
- `scripts/read-probe.sh` still prints a saved file holding the new ids.

## Version

Probe TOC `## Version: 0.5.0`, the panel title, and the CHANGELOG entry
together. `dist/PocketProbe.zip` only; never in the player zips.

## As built (departures, 2026-11-22)

- The three sweep trials are on the **Our own windows** tab ("Controller
  and layout" was full). "Open and close the bags" moved to **Bags and
  vendor** so the panel stays at ten tabs.
- The big message's top edge is 19% down the screen, under the Probe button
  and the status line. The two sweep squares sit just right of the Probe
  button, which already has the top centre.
- The fade test fades about a second after Start, not inside the tap,
  because it shares the timed screenshot steps with the park test.
- If the cooldown frame does not show itself after a sweep call, the probe
  shows it, and the result says "sweep frame shown by itself: no".
- A result's message may be 1500 characters (was 900), for the two bar
  snapshots.
- Fight tests include the existing "create a button" trials, because Run
  all safe does; the new trials create nothing in a fight.
- `CooldownFrameTemplate` is defined at
  `Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3`.
