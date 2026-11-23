# Handoff prompt: face bars, probe 0.7.0, layout fixes, the owner's lunch test

Copy everything below the line into a fresh session.

---

You're picking up the controller UI round of WoW Forever Pocket Essentials (repo
root `/Users/chrismiho/Coding/WoWForever/wow-forever-pocket-essentials`, branch
`setup-options`). The owner is a player, not an addon developer: talk in plain
language, one step at a time. They play on a Retroid Pocket 6 at 720p with a
Switch-labelled controller played Xbox-style, and test on their lunch break.

## Read first, in this order
1. `CLAUDE.md` and `PRD.md` (working rules; rule 7 is the spec flow).
2. `docs/11-23-face-bars/EVIDENCE.md`: everything proven so far, the open
   questions, and pointers to the raw files. Don't re-derive it.
3. `docs/11-23-ui-debug/FINDINGS.md` and its screenshots: what the 0.11.0
   layout looks like on the owner's main. Look at the screenshots yourself.
4. `docs/ui-review/2026-11-22-compact-ui-gameplan.md`, section "Decided
   2026-11-23".
5. The probe: `probe/PocketProbe/` (`Trials.lua` trials, `Run.lua` passes and
   guided trials, `Panel.lua` the window, `Perf.lua` the recorder) and its
   specs `docs/superpowers/specs/2026-11-22-pocket-probe-0.5.0.md` and
   `2026-11-21-perf-recorder.md`.
6. The layout: `addons/PocketEssentials/ControllerLayout.lua` and specs
   `2026-11-21-controller-layout.md`, `2026-11-22-controller-layout-measured-sizes.md`.
7. `docs/TESTING.md` sections 21, 23 and 24 (the last device steps).

## Where things stand
- Pre-release `v0.11.0` on GitHub holds both zips: Pocket Essentials 0.11.0
  (Controller layout, experimental, off by default; a sleeping measuring
  hook) and Pocket Probe 0.6.0. The owner always wants **both zips in one
  pre-release**, even when one did not change.
- The owner's direction (2026-11-23): **face bars**. Our own display-only
  frames draw the spells wherever we like, including the owner's original
  **split** (the d-pad half on one side of the map, the face-button half on
  the other). The game's real bars stay whole, faded to invisible, and still
  take the presses. The rule "no bars or buttons of our own" is gone.
- The owner wants **as little as possible to do during a fight**: no menus in
  a fight. One easy button outside the probe window at most.

## The work, in this order

### Step 1. Pocket Probe 0.7.0: answer the open questions with almost no taps in a fight

Short spec at `docs/superpowers/specs/<date>-pocket-probe-0.7.0.md`, the
owner's go, a plan, a subagent build reviewed against the spec. Proposed
contents (the owner decides):

1. **A floating "Fight" button**, outside the probe window: round, the same
   size as the PE button, beside the probe's Stop button. Shown only while a
   fight is on (our own frame; showing and hiding our frames in a fight is
   allowed, 11-22 EVIDENCE). One tap runs Fight tests. If the recorder is
   running it pauses for the pass and carries on afterwards by itself (today
   a recording refuses every test: "Recording: tap Stop first.").
2. **Watchers, armed by one tap out of a fight, then nothing to do.** One
   row "Watch my next fights" in the probe window. While armed (until the
   next reload or 10 minutes) they record by themselves, in and out of fights:
   - the active bar, through `PageUnit:RegisterActiveActionBarUpdatedCallback`
     (`Blizzard_GamepadActionBars/PageUnit.lua:705`, `:527-542`): which bar
     each time a trigger is pressed or let go, and whether
     `GetActiveBar()` is readable in a fight;
   - presses: find in the source how the game shows a pushed button on the
     gamepad bars (button state, `ActionBarButton.lua`) and whether a hook on
     it fires and is readable in a fight; count only;
   - how often the events a face needs fire per minute, in and out of fights
     (list in EVIDENCE, "Open questions" 6);
   - **the cooldown sweep**: the first time a main-bar spell goes on cooldown
     in a fight, run the duration-object sweep on our square for that slot
     and take one guarded `Screenshot()`. Record whether the frame shows by
     itself.
   Watchers must be cheap (no per-frame code), go through the probe's guard,
   never change a Blizzard frame, and store only classes and counts.
3. **"Fade the main bar for the next fight"** (guided, no taps in the fight):
   start it out of a fight; the main bar fades to 0 when the next fight starts
   and comes back when it ends; the owner just plays. After the fight the
   probe asks "Did your spells cast while the bar was invisible?" (two
   answers). Fade the anchor's `.Bar`, never `PageUnit` (EVIDENCE: wheels
   reset `PageUnit`'s alpha).
4. **"Wheels under a faded bar"** (guided, out of a fight): fade all four
   bars, the owner opens the pet wheel and a spell wheel and answers
   "visible" or "hidden"; record the wheel frame's position and effective
   alpha.
5. **Recorder fixes**: a memory reading of 0 is missing, not 0; mark reloads
   in the report and leave the 30 s after a reload out of "In plain words";
   say "too short to judge" under 10 minutes.

Out of scope: building any face bar; cooldown numbers.

### Step 2. Pocket Essentials 0.11.1: the clear layout bugs

A short spec update (owner's go first). Only what is clearly wrong today;
everything about where the bars go waits for the mockup (step 3).
1. **XP bar top middle**, 130% wide, clear of the controller hints top left,
   the chat top right and the probe's button top centre. The approved
   mockup drew it there (`docs/ui-review/mockup-0.8.1.html`, `pLayout`); the
   spec missed its spot.
2. **Per-character switch-on**: with the switch On, a character whose own
   layout is active switches to ours at login (out of combat) and remembers
   its own layout per character, so switching off on that character brings
   its own back. Today it needs off, reload, on, reload.
3. **Map title under the map** (the game's own Edit Mode setting
   `Enum.EditModeMinimapSetting.HeaderUnderneath`, verify on the forever
   branch).
4. **Buffs clear of the chat** (finding 5).
5. Bump to 0.11.1, CHANGELOG, `docs/TESTING.md`.

### Step 3. The face bars mockup (in parallel with steps 1 and 2)

The owner reviews UI on a browser mockup before any code (memory: "UI review
via mockups"; last one `docs/ui-review/mockup-0.8.1.html`). Draw at 1365 by
768 with the measured sizes. Show: the screen today (from the screenshots),
and two face-bar screens: **A. the split around the map, map bottom middle**
(the owner's idea) and **B. map top right, one flat strip**. On each, mark
where the invisible real bars sit (right under the face, so wheels open near
it), the two sub-menu buttons and targeting circles (the game's own, limited
in where they can go), the XP bar top, and what changes when LT, RT or both
are held. Use the owner's pet-wheel screenshots (they will add them to this
folder). The owner's earlier wish for button pictures: **position glyphs**, a
diamond of four dots with the pressed spot filled, another shape for the
d-pad, not letters.

### Step 4. The face bars spec
After the owner has reacted to the mockup and probe 0.7.0 has answered the
open questions. Not for the lunch test.

### Step 5. Set the owner up for the lunch test
`wow-addon-skills:device-test-handoff`. One pre-release with both zips
(`v0.11.1`), with the owner's OK to push and publish. A new `docs/TESTING.md`
section, numbered, one action per step, saying the tab, row and button. Order:
out of a fight first (arm the watchers, the wheels test, start the
fade-for-next-fight, start recording), then **just play**: the only thing in a
fight is the floating Fight button, once. End with Save and sending
`PocketProbe.lua`, `PocketEssentials.lua` and the screenshots. Then stop and
wait; read the files with `scripts/read-probe.sh --details --perf` and write
the evidence next to them.

## Rules
- Spec, owner's go, plan, subagent build, review against the spec, owner's
  device test. One roadmap item at a time; stop for the device test.
- Verify every new game call in `~/.cache/wow-ui-source/forever` and list it
  with its proof (the probe lists names in its file headers).
- The probe is testing-only and never in the player zips; nothing is created
  in a fight; every handler goes through the guard.
- `scripts/check.sh` and `scripts/test.sh` must pass (a Stop hook enforces
  it). Never push or publish without the owner; never upload to CurseForge.

## Lessons from the device sessions
- One step per message while the owner is in game; wait for "done".
- Say which tab, row and button. Long text on screen is unreadable on the
  handheld; use the probe's big message.
- Level 1 fights end in seconds: anything answered "in a fight" must be
  answered inside it or by a watcher.
- A recording with many reloads is not a play session.
