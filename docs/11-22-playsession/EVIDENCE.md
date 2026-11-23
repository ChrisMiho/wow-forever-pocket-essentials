# 2026-11-22 device session: what the files showed

Source files (copied from the RP6 after the session):
- `PocketProbe.lua`: Pocket Probe 0.4.0, read with `scripts/read-probe.sh` (`--details`, `--log`)
- `PocketEssentials.lua`: Pocket Essentials 0.10.0, read with `scripts/read-log.sh` (`--errors`)

Game 1.60.1 (71037), Gamepad UI on, screen 1365x768 (UI scale 1.00), Switch-labelled
controller played Xbox-style. The run followed `docs/TESTING.md` section 22, with some
departures, listed under "How the run went".

## How the run went

| Time (UTC) | What happened |
|---|---|
| 01:30–01:31 | Logged in with every Pocket Essentials feature off (Debug log on, emptied). |
| 01:31:35 | **Run all safe** out of a fight (situation S1). |
| 01:34:37–01:34:54 | Fight 1: owner tapped **Run all safe** in the fight, not the single row (S2). |
| 01:36:22–01:37:45 | Fights 2–4: the single "Read the main bar's 8 spells" row in a fight; then Risky On and Run all safe again, partly in a fight. |
| 01:37:16–01:37:18 | Out of a fight: "Save the layouts" and "Set the active layout" ran (Risky). |
| 01:38:38–01:38:41 | Out of a fight: bag scale, left bar place, left bar size, left bar see-through (Risky). |
| 01:38:42 | **Park the main bar** started. |
| 01:43:06 | Park cancelled; no spell was pressed, no answer given. |
| 01:44:02–01:44:16 | Fight 5: left bar see-through run in the fight. |
| 01:45 | Save (reloads). Probe turned off at character select afterwards. |
| 01:48–03:22 | Play session: Pocket Essentials features on, probe off. |

## Findings, with the evidence

### 1. Main bar spells in a fight: partly readable
- Out of a fight (01:31:41): the main bar had 8 buttons, 4 with a spell. Slot, has, icon,
  cooldown, cooldown start, cooldown duration, count and usable were all readable.
- In a fight (01:34:50, 01:36:59 straight from the press, 01:37:40): slot, has, icon,
  cooldown (whether one is running) and usable were **readable**. Cooldown start, cooldown
  duration and count were **secret** (4 of 4 each). `issecretvalue` exists on this client.
- What this means: a flat strip can show icons and "can't use right now" live in a fight.
  It can't work out a countdown from the numbers itself. Whether the game will draw a
  cooldown sweep for us from the secret values is untested (see the open questions).

### 2. Fading the game's bars: allowed, out of a fight and in one
- `bars.alpha` (left bar see-through set to its own value): allowed at 01:38:41 (no fight)
  and 01:44:07 (in a fight, straight from the press).
- Caveat: this set the value it already had. A real change (for example to 0 and back) in
  a fight is not proven, and neither is whether a faded bar still takes presses.

### 3. Moving and resizing bars, saving layouts: allowed out of a fight
- `bars.move` and `bars.scale` (left bar set to its own place and size): allowed at
  01:38:40–41. In fight 5 both said "not tried, in combat", as designed.
- `layout.save` and `layout.set`: allowed at 01:37:16–17. `layout.read` readable throughout.
- No "Interface action failed" and no "blocked" pop-up during fight 5, by the owner's own
  report, with every bar pressed for about a minute.
- What this means: Controller layout 0.11.0's approach (its own Edit Mode layout, bars
  moved and sized out of a fight) is allowed as built.

### 4. Parking the main bar: inconclusive
- Log: `01:38:42 bars.park: started; top bar anchor moved up 3000; main bar off screen yes`,
  then `01:43:06 bars.park: cancelled; old values put back`.
- The owner reported "I can still see the main bars". They have all four bars showing
  (`showEmptyBars=yes`, `useCompactLayout=no`), so one bar leaving the screen was easy to
  miss among the other three. No spell was pressed, so "does a parked bar still cast" has
  no answer.
- Blizzard's source (`Blizzard_GamepadActionBars/PageUnit.lua:111, 586-588`) confirms
  `TopCenteredAnchor.Bar` is `actionBars.topBar`, the bar the game uses when no trigger is
  held. So the probe parked the right bar. Controller layout 0.11.0 makes the same
  assumption (spec `2026-11-21-controller-layout.md`, "Top anchor (main bar)"), so the
  assumption stands.
- `TopCenteredAnchor` also carries the possess, stance, friendly and hostile targeting,
  and shortcuts bars (`PageUnit.lua:115-147`); those move with the anchor too.
- The instruction text the probe shows after Start was **unreadable on the device** ("a big
  string at the top of my screen that I can't read"). That is a usability bug for the retest.

### 5. Controller-button pictures: copyable, but not what the owner wants
- `bars.prompts`: "8 of 8 copied · Letters" in S1 and S2. Each pad button maps to an
  Xbox atlas (for example `PAD1=Gamepad-Xbox1-ButtonA-Normal`). "The game's own lookup gives
  the same picture for 0 of 8": the pictures copied don't match what the game's own lookup
  returns. Worth a look if the pictures are ever used.
- Owner's decision (2026-11-22): the controller is Switch-labelled but played Xbox-style,
  so letters mislead. The strip should show **position pictures**: a diamond of four dots
  with the pressed spot filled, and a different shape for the d-pad. The owner loved the
  idea and the different shapes. This needs no probe; it goes into the strip's design.

### 6. Measured sizes (UI scale 1, screen 1365.3 x 768 in UI units)

| Frame | Width | Height |
|---|---|---|
| MinimapCluster | 273 | 283 |
| PlayerFrame / TargetFrame | 232 | 100 |
| PetFrame | 120 | 49 |
| ChatFrame1 | 430 | 120 |
| SwingTimerMainHandFrame | 333 | 21 |
| GamepadMainActionBarFrame | 656 | 202 |
| Top/Left/Right/BottomCenteredAnchor | 50 | 50 |
| TopCenteredAnchor.Bar (main bar) | 266 | 86 |
| One main bar button | 40 | 40 |
| BuffFrame | 400 | 135 |
| DebuffFrame | 280 | 90 |
| ObjectiveTrackerFrame | 260 | 400 |
| MainStatusTrackingBarContainer (XP) | 357.6 | 17 |
| LeftClassAction / RightClassAction | 38 | 38 |
| GamepadPetActionFlyout | 200 | 200 |

The same values in and out of a fight. Every gamepad bar frame and anchor reports
`protected=yes` (`explicit=no`). Bar settings: `useCompactLayout=no`, `showEmptyBars=yes`,
`shouldExpand=yes`, 3 account layouts, 0 character layouts.

### 7. Taking controller buttons in a fight: blocked (already known)
- `pad.bind` and `pad.mark` were blocked in every fight run (01:34:48, 01:37:04-05,
  01:37:37). `pad.mark` makes the game print "Interface action failed" (stack through
  `Blizzard_GamepadSmartNavigation/SecureHelper.lua:19`). These ran only because Run all
  safe was used in a fight.
- `err.others` at 01:37:44 counted 1 Blizzard error. The stored stacks point to
  `DisplayInterfaceActionBlockedMessage` from those same pad trials, so it is very likely
  the probe's own blocked call, attributed to Blizzard. Not a separate problem.
- Lesson for a fight button: leave out trials already known to be blocked in a fight, or
  they print "Interface action failed" on every run.

### 8. Other readings
- Bag: move "no effect, the bag has no position yet"; scale allowed.
- Errors: error handler hookable; test error seen with message and stack; the error box
  can be hidden through `scriptErrors`. No blocked actions of other addons.
- Target unit name is readable in a fight (nil out of one, when no target).
- Graphics: sparkle 1, outline 0, `IsOutlineModeSupported` false.

### 9. Play session (Pocket Essentials 0.10.0): clean
- 01:49–03:22 (about 1.5 h). Features on: questIcons, questArrow, bags, bagWindow,
  sellJunk, repair, chat, menuBg, spark. Catch all errors on.
- **Errors page: 0 entries.** 84 fights. Repair at a vendor worked (31 copper). Bag
  sort by stick click worked. Chat picker used 23 times (A button handoff each time).
  Quest rebuilds were 0 ms when nothing changed, at most 221 ms.
- The owner reported nothing broken.

## Open questions (for the next probe round)

1. **Does a parked or faded main bar still cast?** This decides whether a flat strip can
   take the main bar's place. Needs a retest the owner can follow.
2. **Can our own button show a cooldown sweep in a fight?** Blizzard's docs on this client:
   `C_ActionBar.GetActionCooldownDuration(slot)` returns a duration object (not marked
   secret), and `Cooldown:SetCooldownFromDurationObject` takes one. `Cooldown:SetCooldown`
   accepts secret values only "AllowedWhenUntainted", so addon code probably can't pass the
   secret numbers straight in. Untested on the device.
3. **A real alpha change in a fight** (to 0 and back), not only "the value it already has".
4. *(Owner-only, no addon, optional)* Does the game's own Options, Action Bars, "Show
   Numbers for Cooldowns" (`countdownForCooldowns`) exist on Forever and show numbers on
   the controller bars? The owner said cooldown numbers are **not wanted yet**, so this is
   low priority.

## Decisions taken in the conversation
- The aim is a tidier screen, not cooldown numbers. The bar can't be split, so a **flat
  strip** is the best way to pull the screen together. The next probe measures only what
  that needs.
- Cooldown numbers and a "stopwatch from casts" (the way the DoesItDie addon tracks DoTs)
  are **out for now**. DoesItDie (github.com/swirllyman/DoesItDie) confirms two
  techniques on Forever: its own casts (`UNIT_SPELLCAST_SUCCEEDED`) stay readable in a
  fight, and game widgets (StatusBar) accept secret values and draw them.
- Next probe (0.5.0): a **Run fight tests** button, a **clearer park test**, a
  **cooldown sweep test**. After that: the measured sizes go into 0.11.0, then testing
  layouts on the device.
