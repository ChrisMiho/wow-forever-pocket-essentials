# Handoff prompt: Pocket Probe 0.5.0, then testing layouts

Copy everything below the line into a fresh session.

---

You're picking up the controller UI round of WoW Forever Pocket Essentials (repo root
`/Users/chrismiho/Coding/WoWForever/wow-forever-pocket-essentials`, branch `setup-options`).
The owner is a player, not an addon developer. Talk in plain language, one step at a time,
and stop for their device tests. They play on a Retroid Pocket 6 at 720p with a
Switch-labelled controller, played Xbox-style.

## Read first, in this order
1. `CLAUDE.md` and `PRD.md` (working rules; rule 7 is the spec flow).
2. `docs/11-22-playsession/EVIDENCE.md`: everything the last device session proved. Don't
   re-derive it. The raw files sit next to it (`PocketProbe.lua`, `PocketEssentials.lua`).
3. `docs/TESTING.md` section 22 (the last probe test) and section 21 (0.11.0's test, which
   comes after this round).
4. `docs/superpowers/specs/2026-11-21-controller-layout.md` (0.11.0, built on guessed sizes)
   and `docs/ui-review/2026-11-20-action-bars-gameplan.md` (the "flat strip" idea).
5. The probe: `probe/PocketProbe/` (`Trials.lua` holds the trials, `Run.lua` the passes,
   `Panel.lua` the window). The probe's earlier specs:
   `docs/superpowers/specs/2026-11-17-restriction-probe.md` and
   `2026-11-20-error-catcher-and-probe-panel.md`.

## Where things stand
- Pocket Essentials 0.10.0 is the latest release; 1.5 h of play with 0 errors.
- 0.11.0 (Controller layout, experimental, off) is committed but **not released**. It waits
  for the measured sizes (EVIDENCE.md, finding 6).
- The goal of the round: a tidier screen with smaller bars. The main bar can't be split, so a
  **flat strip** of our own (main spells in one row under or near the map) is the next best
  way to pull the screen together. The owner does **not** want cooldown numbers yet.

## Step 1: Pocket Probe 0.5.0 (this session's work)

The owner already agreed the scope in conversation (2026-11-22). Turn it into a spec at
`docs/superpowers/specs/<date>-pocket-probe-0.5.0.md`. Keep it short; it's a small change.
Get the owner's approval, then write a plan in `docs/superpowers/plans/`, then a
subagent-driven build reviewed against the spec. The three agreed items:

1. **"Run fight tests" button** in the panel footer, made to be tapped once during a fight
   (by touch; the d-pad goes back to the game in a fight). It runs every safe trial worth
   repeating in a fight. With Risky On it also runs the Risky trials meant for fights (today:
   `bars.alpha`, plus any new fight trials below). It **leaves out** trials already known to
   be blocked in a fight (`pad.bind`, `pad.mark`: they print "Interface action failed" every
   time, EVIDENCE finding 7) and the chat box and bag-open trials (they upset the controller).
   Show plainly what ran. Note: Run all safe already works in a fight; this button is the
   clear, fight-only version.

2. **A clearer park test** (`bars.park`). The last run was inconclusive (finding 4):
   - The instruction shown after Start was unreadable on the device. Show a **short, large,
     centred** message instead, something like "Your no-trigger bar is gone. Press a buff,
     then tap Probe."
   - Record **which bars are shown and where**, just before and just after parking: the
     four bars and the bars that ride on `TopCenteredAnchor` (possess, stance, targeting,
     shortcuts).
   - Optionally take a **screenshot** at both moments with `Screenshot()`. It's listed in
     `ClientDocumentation.lua` on the forever branch, but check it isn't protected and
     guard it (`wow-addon-skills:wow-api-verify`).
   - The owner's steps must say to count the bars before and after, and to press a spell
     before answering.
   - Consider a **fade variant** next to it: main bar see-through to 0, press a spell,
     answer, put it back. That answers "does a faded bar still cast?", the other way a
     strip could take the bar's place. Also a **real** see-through change in a fight
     (finding 2 only proved "set to the value it already has"). Propose these in the spec;
     the owner decides.

3. **Cooldown sweep test** (open question 2). On a hidden button of our own (made at load,
   nothing created in a fight), in a fight: feed
   `C_ActionBar.GetActionCooldownDuration(slot)` into
   `Cooldown:SetCooldownFromDurationObject`, and separately try `Cooldown:SetCooldown` with
   the secret start and duration. Record allowed, blocked or Lua error for each, and whether
   the sweep actually shows. Verify every new API on the forever branch first (local clone:
   `~/.cache/wow-ui-source/forever`) and list the names with their proof in the file header,
   as the probe already does. Don't add countdown numbers: the owner said not yet.

Out of scope: cooldown numbers, a stopwatch from casts, the position pictures (they go into
the strip's design later, no probe needed), anything in Pocket Essentials itself.

Rules that apply: the probe is testing-only and never goes in the player zips; nothing runs
by itself; every handler goes through the probe's guard; nothing is created in a fight; add
offline tests (`scripts/test.sh` has the probe's own tests); `scripts/check.sh` and
`scripts/test.sh` must pass (a Stop hook enforces it). Bump the probe version and its
changelog together. Build with `scripts/build.sh` (`dist/PocketProbe.zip`).

## Step 2: hand it to the owner
Use `wow-addon-skills:device-test-handoff`. Add `docs/TESTING.md` section 23 for probe
0.5.0. Keep the steps short and numbered, one action each. The owner got lost when several
steps came at once (see "Lessons" below). Publish a GitHub pre-release only when the owner
says so; never push or upload without them. Then stop and wait for their `PocketProbe.lua`.
Read it with `scripts/read-probe.sh --details` and add the results to a new evidence file
next to the session's files.

## Step 3 (later, separate step): measured sizes into 0.11.0
Replace the guessed sizes in Controller layout with EVIDENCE finding 6 (and anything 0.5.0
adds). That's a change to Pocket Essentials, so it needs its own short spec update and the
owner's go.

## Step 4 (later): testing layouts on the device
Once 0.11.0 has real sizes: release it as a pre-release, then run `docs/TESTING.md`
section 21 together, one layout choice at a time (main bar above or under the map, spell
button size, frames stacked or side by side, swing timers, fading). After that, the flat
strip gets its own brainstorm, mockup (the owner reviews UI on browser mockups first and
plays at 720p), and spec, including the position pictures: a diamond of four dots with the
pressed spot filled, another shape for the d-pad.

## Lessons from the last device session
- Give **one step per message** while the owner is in game, and wait for "done".
- Say which **tab** and which **row** to tap, and whether to tap **Run** on the row or a
  footer button. "Run all safe" got tapped where a single row's Run was meant.
- The owner didn't notice one bar out of four disappearing. Ask for a count or a
  screenshot, not "did it disappear?".
- Long on-screen text from the probe isn't readable on the handheld.
