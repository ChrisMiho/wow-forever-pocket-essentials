# 2026-11-23 device session, part 1: what the files showed

Source files (copied from the RP6 after part 1 of `docs/TESTING.md` section 23):
- `PocketProbe.lua`: Pocket Probe 0.6.0, read with `scripts/read-probe.sh` (`--details`, `--log`, `--perf`)
- `PocketEssentials.lua`: Pocket Essentials 0.11.0, fresh start (`setup = "skipped"`, every feature off)

Game 1.60.1 (71037), Gamepad UI on, screen 1365.3 by 768 (UI scale 1). A new
level 1 warrior, so no spell had a cooldown. Times are the device's clock.

## How the run went

| Time | What happened |
|---|---|
| 15:40:12 | Recording started by itself at login; stopped by the owner at 15:41:06 (55 s, 5 samples) |
| 15:42:14 | Park the main bar, out of a fight. Answered "spell cast" at 15:45:21 (auto attack) |
| 15:47:25 | Fade the main bar, out of a fight. Answered "spell cast" at 15:47:51 |
| 15:50:45 | Fight tests, in a fight (tapped twice; the second pass took over and ran to the end at 15:50:56) |
| 15:51:21, 15:52:43 | Fade the main bar twice more, meant to be in a fight; both answered out of one (see finding 2) |
| 15:56:16 | Save (reloads) |

## Findings

### 1. A parked main bar still casts (open question 1: answered)
- `bars.park` "spell cast" in S1. Snapshot before: 4 bars shown on screen (top,
  left, bottom, stance); after: 3, the top bar at y 3269, off screen. The
  possess, targeting and shortcuts bars moved with it, as the source said.
- Parking is only done out of a fight, by design; in a fight the probe does not
  move it (the owner saw "nothing happened", as expected).

### 2. An invisible main bar still casts (open question 1: answered)
- `bars.fadecast` "spell cast" three times, see-through 1 -> 0, "still
  invisible at the answer: yes" each time: the game does not put the alpha
  back by itself.
- All three answers were recorded out of a fight. The fight with the level 1
  warrior was over before the answer, so "an invisible bar casts during a
  fight" is not proven directly. Changing a bar's see-through in a fight is
  (finding 3), and see-through does not take part in how a press reaches a
  button, so it is very likely the same. Worth one more try in a longer fight.

### 3. A real fade in a fight is allowed (open question 3: answered)
- `bars.fade` (left bar to 0 and back) allowed in S2 at 15:50:56. `bars.alpha`
  allowed in S2 too. No "Interface action failed" from either.

### 4. Cooldown sweep on our own button (open question 2: half answered)
- `cd.duration`: `C_ActionBar.GetActionCooldownDuration` readable in a fight
  (3 of 3 spells).
- `cd.sweep.object`: `SetCooldownFromDurationObject` with that object is
  **allowed** in a fight from addon code.
- `cd.sweep.numbers`: `SetCooldown` with the secret start and duration is
  **refused**: "Secret values are only allowed during untainted execution for
  this argument."
- No spell was on cooldown ("slot on cooldown no"), so whether the sweep is
  actually drawn is still open. Retest with a spell that has a cooldown
  (Charge, at level 4).

### 5. Other fight readings
- `win.chat.create` blocked in a fight (the controller's navigation code
  refuses a new button under the chat frame). `win.map.create` and
  `win.bag.create` allowed. Nothing new for the layout.
- `bars.spells` as on 2026-11-22: icon, usable and "on cooldown" readable;
  times and counts secret.
- Sizes unchanged. New: `MinimapCluster.MinimapContainer` 253 by 253 and
  `Minimap` 198 by 198 at 100%; the three other bars 208 by 68 (not grown).
  The quest tracker read 264 tall here (400 before; it holds fewer quests).

### 6. Performance recorder: works on the device
- The game's profiler is **on** on the RP6 (numbers came back; "share of all
  addons" 0 %).
- 55 s with every feature off: Pocket Essentials 0.0031 ms per frame on
  average, one run of 6.6 ms (login work), memory 1.2 MB, QuestieDB 7.3 MB,
  frame rate 40. A baseline, too short to judge by.
- Report wording to look at later: one slow frame in a 55 s run is called
  "Hitches: some", "Overall: in between". The marks need a longer run.

### 7. Pocket Essentials: clean
- Errors page: 0 entries. The fresh start took (setup "skipped").

## What this means for the compact screen

- The flat strip is possible: the game's main bar can be **faded** to nothing
  (changeable in a fight too) or **parked** off screen (out of a fight only)
  and it still takes the presses. Fading is the more flexible of the two.
- Quiet bars (fading the LT, RT and both-triggers bars until held) is allowed.
- A strip can show icons and "can't use now" live, and the game's own cooldown
  sweep through the duration object, if the sweep turns out to be drawn.

## Still open
1. Whether the sweep is drawn (Fight tests with Charge on cooldown).
2. Optional: the fade-and-press test answered inside a longer fight.
3. Part 2: the play recording (section 24) and the layout (section 21).

## Part 2, first look (three screenshots, no saved file yet)

Screenshots 09:21:38, 09:22:12 and 09:22:37, at 1920 by 1080 (1.406 pixels per
UI unit). Controller layout on, Pocket Essentials features on, recorder on
(red dot bottom right, round Stop beside the PE button on the left).

- **Applied as designed:** map bottom middle at about 80%; chat top right,
  larger; quest tracker under it on the right; RT bar right of the map at about
  +220 units, y about 43 (the plan says +227, 42); the RB+RT sub-menu button
  beside the map's right edge.
- **Main bar above the map (09:21:38):** sits just above the map's zone-text
  line, with little room between them. The two targeting circles sit above it.
- **Main bar under the map (09:22:12, 09:22:37):** main bar at the bottom
  middle, RT bar beside it about 35 units away, map lifted. Both bars' bottom
  edges touch the XP bar; the RT bar's "RT" tag sits on it.
- **LT bar not shown:** expected on a level 1 warrior. ShowEmptyBars is off in
  the layout, and the LT bar has no spells yet.
- **Player frame not in the corner:** it sits at about x 305, y 128 units from
  the bottom left, not at the "Corners" spot (20, 20). Either the game places
  the player frame itself under the Gamepad UI, or the layout's entry for it
  was not written. Check in the saved file once it comes (debug log, the
  layout entries) before changing anything.
