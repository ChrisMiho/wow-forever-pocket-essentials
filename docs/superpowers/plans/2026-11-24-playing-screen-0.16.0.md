# The playing screen, 0.16.0 (the arrangement) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With Controller layout on, the playing screen follows the approved arrangement with no overlaps, and Pocket Probe 0.8.0 measures what 0.17.0 needs.

**Architecture:** `ControllerLayout.lua` keeps its two halves. The pure half (`PE.LayoutPlan`) gets the new spots, two options and the rectangles the overlap check uses; the module half places the pieces Edit Mode does not own and puts them back. Everything is placed out of a fight through the paths that exist (`Plan.Pieces` into our Edit Mode layout, `PlaceNow` / `RestoreNow` for the rest).

**Tech Stack:** Lua for Interface 16001, no libraries; LuaJIT tests in `tests/features/` and `tests/probe/` on the stand-in client `tests/lib/fakeclient.lua`.

**Spec:** `docs/superpowers/specs/2026-11-24-playing-screen-layout-design.md` (the 0.16.0 table, the two rows, "Known pinches", "The probe"). The 0.17.0 part is not built here.

## Global Constraints

- Branch `playing-screen-0.16.0` from `main`. No push, no CurseForge upload: the owner does both.
- Nothing of the game's is moved, hidden or changed in a fight: every new step runs inside `PE:RunOutOfCombat` or a caller that already does.
- Nothing ticks: no timer, no `OnUpdate`. Hooks installed once and returning at once while the layout is off.
- Switching the layout off puts back every piece and every game setting this plan touches.
- Handlers and callbacks through `PE:Safe` or `PE:Wrap`. Game calls of the module half through `pcall`, as the file does.
- Every game name new to the addon is checked in `~/.cache/wow-ui-source/forever` and cited by file and line in a comment; what cannot be proven gets a row in `docs/ARCHITECTURE.md` with its worst case. `scripts/audit-api.sh` is run after the last code task.
- Units: UI units at scale 1 (1365.33 by 768), x from the centre, y up from the bottom, as the file's other numbers. A mockup pixel is 768 / 720 units.
- Comments in plain words (`scripts/check.sh` checks their wording). Labels: "Controls reminder" (Off / On), "Map buttons" (Hidden / Shown).
- `scripts/check.sh` and `scripts/test.sh` pass before every commit. No version bump or CHANGELOG before Task 5.

## Review Focus

1. A player who moved the PE button with "Move on screen" before 0.16.0: their button stays where they put it (Task 2 test).
2. Spell panel size changed after 0.16.0 is installed: the chat and the tooltip follow the frames when they rise at 110% and 120% (Task 1 test on `REWRITES`).
3. The layout switched off in the same session it was switched on: chat box see-through, map ring, map buttons and the hint setting are back to the player's (Task 3 test).
4. The game redraws the map's ring (the rotate-minimap setting changes) while the layout is on: the ring stays hidden and the black border stays (Task 3 test).
5. A client where a piece is missing (no `GameTimeFrame`, no `HudTooltip` system): the rest of the layout is still placed and nothing errors (Tasks 1 and 3 tests).

---

### Task 1: The plan's numbers, options and overlap check

**Files:**
- Modify: `addons/PocketEssentials/ControllerLayout.lua` (the pure half, lines 66-660, and `REWRITES` near line 1752)
- Test: `tests/features/layout_test.lua`

**Interfaces:**
- Produces:
  - `Plan.TEMPLATE = 5`
  - `Plan.DEFAULTS.hints = 0` (0 Off, 1 On) and `Plan.DEFAULTS.mapButtons = 0` (0 Hidden, 1 Shown)
  - `Plan.Rects(opts)`: `opts` is the options table (or nil); it reads `panelSize`, `hints`, `mapButtons`. A number is still accepted as the panel size.
  - `Plan.HubSpot(opts) -> point, x, y` on UIParent, in UI units, for the PE button's default spot
  - `Plan.STRIP_W = { [0] = 152, [1] = <measured> }` the place-name strip's width without and with its two buttons
  - `Plan.SHOULDERS` (same shape as today, new numbers)

The spots (the builder turns each into the numbers and checks it against the source; the overlap tests decide):

| Piece | Spot |
|---|---|
| Minimap | `MAP.y` lowered so the strip sits where the swing timers were (start from `MAP.y = 0`: strip 8 to 31 up, round map about 49 to 188 up) |
| Swing timers | stacked directly above the round map, 6 over its top, 2 between, Main Hand lowest; same scale and width settings as today |
| ChatFrame | `BOTTOMLEFT`, x 17; width 450, height 170; its bottom 6 over the higher of the pet frame's top and the PE button's top, so it rises with the frames |
| ObjectiveTracker | `TOPRIGHT` -5, -5, `Height = 0` |
| BuffFrame / DebuffFrame | `TOPRIGHT`, 10 left of the tracker's left edge; the buff row's top 4 under the XP bars' bottom, the debuff row 38 under the buff row (as today's gap) |
| HudTooltip | a new piece: `BOTTOMRIGHT`, x -10, its bottom 6 over the target of target frame's top. Left out by `Plan.Apply` when the game has no such system (the way a missing setting is) |
| LB / RB targeting pictures | off the "LB + LT" / "RB + RT" prompts, at the prompts' height, on their outer side |
| Hint box | `TOPLEFT` 5, -5 (the game's), in the rectangles only when `hints == 1`; its size from `GamepadPersistentInputLegend.xml` |
| PE button | `BOTTOMLEFT`, x 10, its bottom 6 over the player frame's top (left of the pet frame) |

- [ ] **Step 1: Write the failing tests** in `tests/features/layout_test.lua`:
  - `"0.16.0: the template is 5 and the two new options default to 0"`: `eq(Plan.TEMPLATE, 5)`, `eq(Plan.DEFAULTS.hints, 0)`, `eq(Plan.DEFAULTS.mapButtons, 0)`.
  - `"0.16.0: the chat is bottom left, the tracker top right, the tooltip is a piece"`: from `Plan.Pieces({})`, ChatFrame's anchor point is `"BOTTOMLEFT"`, ObjectiveTracker's is `"TOPRIGHT"`, a piece with system `"HudTooltip"` exists with point `"BOTTOMRIGHT"`.
  - `"0.16.0: the timers are above the round map"`: each timer rectangle's bottom is at or above `Plan.Rects({}).map[4]`.
  - `"0.16.0: no piece overlaps another in any state"`: for panel size in `Plan.PANEL_SIZES`, `hints` in {0, 1}, `mapButtons` in {0, 1}: every pair in `Plan.Rects(opts)` has no overlap (reuse `overlapArea`), and every rectangle is on screen. The rectangles include `"LB+LT prompt"`, `"RB+RT prompt"`, `"tooltip"` (taken 200 by 100), `"hint box"` (only when on) and `"round button"` at `Plan.HubSpot(opts)` for the largest button size.
  - `"0.16.0: the strip is wider with the map buttons shown"`: the `"title strip"` rectangle is `Plan.STRIP_W[0]` wide for `mapButtons = 0` and `Plan.STRIP_W[1]` for 1.
  - `"0.16.0: a size change that raises the frames rewrites the chat and the tooltip"`: with the existing rewrite test's harness, a change from 100 to 110 rewrites the pieces of systems UnitFrame, ChatFrame and HudTooltip; 80 to 100 rewrites none.
  - `"0.16.0: a layout without the tooltip system is still built"`: `Plan.Build` with `fakeEnums()` that has no `HudTooltip` returns a layout and no error.
  - Update the existing tests that pin the 0.14.0 / 0.15.0 spots this task moves (the tracker and round-button test near line 360, the timer and strip numbers), keeping what they prove.
- [ ] **Step 2: Run** `scripts/test.sh`; expected: FAIL in `layout_test.lua` on the new tests.
- [ ] **Step 3: Implement.** Bump `Plan.TEMPLATE` (add "5: 0.16.0, the playing screen" to its comment), add the two defaults, the constants for the table above (each with its source citation), change `Plan.Pieces`, `Plan.Rects`, `Plan.SHOULDERS`, add `Plan.HubSpot` and `Plan.STRIP_W`, and extend `REWRITES.panelSize` to ChatFrame and HudTooltip. `Plan.STRIP_W[1]` and the prompt's size come from `Blizzard_Minimap/Camelot/*.xml` and `Blizzard_GamepadActionBars/MainActionBarFrame.xml:119-135`. Where a spot in the table cannot pass the overlap test, keep the arrangement, move the piece the least, and add an "As built" line to the spec.
- [ ] **Step 4: Run** `scripts/check.sh && scripts/test.sh`; expected: both pass.
- [ ] **Step 5: Commit** `git commit -m "0.16.0 T1: the playing screen's spots, two options, the overlap check in every state"`

### Task 2: The PE button's default spot

**Files:**
- Modify: `addons/PocketEssentials/Hub.lua:113-128` (`Placement`), `addons/PocketEssentials/ControllerLayout.lua` (one public reader)
- Test: `tests/features/hub_test.lua`

**Interfaces:**
- Consumes: `Plan.HubSpot(opts) -> point, x, y` (Task 1)
- Produces: `PE.ControllerLayout:HubSpot() -> point, x, y` or nil. Nil unless the layout is on and ours is the active layout (the condition `SyncBars` uses). `Hub:Refresh()` is called when that state changes (from `PlaceNow` and `RestoreNow`).

- [ ] **Step 1: Write the failing tests** in `hub_test.lua`:
  - `"hub: with the controller layout placed the default spot is the layout's"`: with `PE.ControllerLayout.HubSpot` returning `"BOTTOMLEFT", 10, 162`, `Placement` (through the button's point after `Hub:Refresh()`) gives `BOTTOMLEFT`, 10, 162.
  - `"hub: a button the player moved keeps its offset from the old default"`: with a saved Move offset that is not 0, 0 the button's point is the one it had before 0.16.0 (the `POSITIONS` spot plus the offset), whatever `HubSpot` returns.
  - `"hub: a position the player chose in settings wins"`: with `PE.db.ui.hubPos` set to a key other than the default, `HubSpot` is not used.
  - `"hub: without the layout the spot is as before"`: `HubSpot` returning nil gives today's numbers.
  - In `tests/probe/run.lua`, `"probe: Stop and Fight stay clear of the frames at the PE button's new spot"`: with the PE button at `Plan.HubSpot({})`, the probe's Stop and Fight buttons (placed beside the PE button, `probe/PocketProbe/Perf.lua`) are on screen and overlap neither the `player` nor the `pet` rectangle of `Plan.Rects({})`, at every Spell panel size. If they would, the builder flips the side they sit on in the probe and says so in the report.
- [ ] **Step 2: Run** `scripts/test.sh`; expected: FAIL on the new hub tests.
- [ ] **Step 3: Implement** `PE.ControllerLayout:HubSpot()` and the branch in `Placement()`.
- [ ] **Step 4: Run** `scripts/check.sh && scripts/test.sh`; expected: pass.
- [ ] **Step 5: Commit** `git commit -m "0.16.0 T2: the PE button's default spot follows the controller layout"`

### Task 3: The pieces Edit Mode does not own, and the two rows

**Files:**
- Modify: `addons/PocketEssentials/ControllerLayout.lua` (the module half: the hint box block near 1265-1320, `EXTRAS`, `PlaceNow`, `RestoreNow`, `OPTIONS`)
- Modify: `tests/lib/fakeclient.lua` (additive only: the frames and functions the tests need)
- Test: `tests/features/layout_test.lua`

**Interfaces:**
- Consumes: `Plan.DEFAULTS.hints`, `Plan.DEFAULTS.mapButtons`, `Plan.SHOULDERS` (Task 1)
- Produces: two rows in `OPTIONS`, before "Rebuild the layout":
  `{ key = "hints", label = "Controls reminder", choices = { {value=0,label="Off"}, {value=1,label="On"} } }` and
  `{ key = "mapButtons", label = "Map buttons", choices = { {value=0,label="Hidden"}, {value=1,label="Shown"} } }`.
  `mapButtons` also goes through `LayoutRow` only if Task 1 made a Minimap piece depend on it; otherwise both rows call `SyncBars()` and ask for no reload.

What each piece does (all from `PlaceNow`, undone from `RestoreNow`, each remembering what it found before its first change, as `extraFound` does):

| Piece | Placed | Put back |
|---|---|---|
| Hint box | `hints == 0`: as today (`HideHints`). `hints == 1`: the game setting is written `"1"`; the player's earlier value is still saved once in `opts.hintsWas` | `ShowHints()` as today |
| Chat's dark box | `FCF_SetWindowAlpha(frame, 0, true)` on every chat window (`Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua:1053`; the third argument keeps the player's saved value); the builder confirms from that file what else draws the box when the chat fades in, and handles it | each window's own see-through, read before the change |
| Map ring | `MinimapCompassTexture` hidden (and the underlay when shown); a black disc of ours (`Icons/circle.tga`, tinted black, 4 wider than the round map, one frame level under it) shown behind the map. A `hooksecurefunc` on `MinimapCluster.UpdateMinimapConfig` (`Blizzard_Minimap/Camelot/Minimap.lua:31`), installed once, re-applies it while the layout is placed | ring shown, disc hidden |
| Map buttons | `mapButtons == 0`: the tracking (magnifier) button and `GameTimeFrame` hidden, with whatever is anchored to them that would float (the builder reads `Blizzard_Minimap/Camelot/*.xml`; the addon-count badge is anchored to `GameTimeFrame`). `mapButtons == 1`: left as the game draws them | shown again if the addon hid them |
| Targeting pictures | the `EXTRAS` entries, at the new `Plan.SHOULDERS` | as today |

- [ ] **Step 1: Write the failing tests** in `layout_test.lua` (on the stand-in client; add the missing stand-ins to `fakeclient.lua`):
  - `"0.16.0: the two rows exist, Off and Hidden by default"`: the feature's options hold keys `hints` and `mapButtons` with the labels above; fresh options read 0 and 0.
  - `"0.16.0: Controls reminder On writes the game setting once and Off hides it"`: placing with `hints = 1` leaves `GamepadShowPersistentInputLegend` at `"1"`; with 0 at `"0"`; `opts.hintsWas` holds the value from before in both; switching the layout off writes that value back.
  - `"0.16.0: the chat's box is see-through while placed and the player's value comes back"`: a chat window whose see-through was 0.25 reads 0 after placing and 0.25 after the layout is switched off; the saved-value argument was `true` on every call.
  - `"0.16.0: the map's ring is hidden, the black border shown, and both survive the game redrawing the ring"`: after placing, `MinimapCompassTexture:IsShown()` is false and our disc is shown; after calling `MinimapCluster:UpdateMinimapConfig()` (the stand-in shows the ring again) the same holds; after switching off the ring is shown and the disc hidden.
  - `"0.16.0: Map buttons Hidden hides both buttons, Shown leaves them, off puts them back"`.
  - `"0.16.0: a client without the calendar button or the ring still places the rest"`: with `GameTimeFrame` and `MinimapCompassTexture` nil, placing raises no error and the chat and hint steps still ran.
  - `"0.16.0: none of it runs in a fight"`: with the stand-in in combat, a row change makes no game call until the fight ends.
- [ ] **Step 2: Run** `scripts/test.sh`; expected: FAIL on the new tests.
- [ ] **Step 3: Implement** the table above and the two rows.
- [ ] **Step 4: Run** `scripts/check.sh && scripts/test.sh`; expected: pass.
- [ ] **Step 5: Commit** `git commit -m "0.16.0 T3: controls reminder and map buttons rows, the chat without its box, the map's black border"`

### Task 4: Pocket Probe 0.8.0, what a fight leaves readable

Independent of Tasks 1 to 3 (other files); may run beside them.

**Files:**
- Modify: `probe/PocketProbe/Trials.lua`, `probe/PocketProbe/PocketProbe.toc` (`## Version: 0.8.0`), `scripts/read-probe.lua` only if a new result shape needs it
- Test: `tests/probe/run.lua`, `tests/readprobe/run.lua`

**Interfaces:**
- Produces: four trials in a new area `"Buffs in a fight"`, each `kind = "value"`, `fight = true`, not risky, using the file's `Add{}` shape:
  - `aura.count`: how many buffs and debuffs the target and the pet have, by `C_UnitAuras.GetUnitAuraInstanceIDs`; records the count or "secret" / "refused".
  - `aura.fields`: for the first aura of each: whether `icon`, `applications`, `duration`, `expirationTime` are plain, secret or missing (through the probe's own plain-value writer).
  - `aura.show`: a box of the probe's own with a texture and a Cooldown child, fed that aura's icon and time; records whether each call was accepted. The box is hidden again at once.
  - `aura.blizzard`: read-only: whether `TargetFrame`'s aura icons are children of the frame or of a container with its own see-through, and their parent chain's names (what 0.17.0 needs to keep them visible). Makes no change.
- The performance recording needs no code: the device steps ask for one in town and one in a fight (Task 5).

- [ ] **Step 1: Write the failing tests** in `tests/probe/run.lua`: the four ids exist in area "Buffs in a fight", are marked `fight` and not `risky`; on the stand-in each returns a result without an error when the unit has no aura, when a field is a secret stand-in, and when `C_UnitAuras` is missing; `aura.show` leaves its box hidden.
- [ ] **Step 2: Run** `scripts/test.sh`; expected: FAIL in the probe suite.
- [ ] **Step 3: Implement** the four trials; cite `Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua` for each call.
- [ ] **Step 4: Run** `scripts/check.sh && scripts/test.sh`; expected: pass.
- [ ] **Step 5: Commit** `git commit -m "Pocket Probe 0.8.0: what a fight leaves readable of the target's and the pet's buffs"`

### Task 5: Audit, documents, version, build

**Files:**
- Modify: `addons/PocketEssentials/PocketEssentials.toc` (`## Version: 0.16.0`), `CHANGELOG.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `PRD.md` (Status), `tests/api/*.txt` (by the audit), the spec ("As built")

- [ ] **Step 1: Run** `scripts/audit-api.sh`; expected: every new game name verified, or listed in `tests/api/unverified.txt` with a matching row in `docs/ARCHITECTURE.md` and its worst case.
- [ ] **Step 2: Write** the TOC version and the CHANGELOG entry together (what the player sees, in plain words: the new arrangement, the two rows, what waits for 0.17.0), the PRD status line, and the spec's "As built" section listing every spot that differs from its table.
- [ ] **Step 3: Write the device steps** in `docs/TESTING.md` as a new numbered step: one reload after the update; the five collisions from the 2026-11-24 screenshots; chat tabs switch and a long message wraps; Controls reminder On and Off; Map buttons Shown and Hidden; Spell panel size 100% and 120%; the tooltip against the target; layout off puts everything back; then the probe: "Fight tests" in one fight with a pet out and a debuff on the target, a performance recording in town and one in a fight; send back the saved `PocketEssentials.lua` and `PocketProbe.lua`.
- [ ] **Step 4: Run** `scripts/check.sh && scripts/test.sh && scripts/build.sh`; expected: all pass and `dist/` holds the Pocket Essentials zips and `PocketProbe.zip`.
- [ ] **Step 5: Commit** `git commit -m "0.16.0: the playing screen's arrangement; Pocket Probe 0.8.0"`, then stop: the push and the GitHub pre-release (both zips) are the owner's, followed by the device-test handoff.
