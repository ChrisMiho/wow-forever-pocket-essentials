# The away batch: 0.16.4, 0.17.0, 0.18.0 built behind switches, one device test at the end

Approved by the owner's instruction of 2026-11-24 (evening): "implement the rest of the
work, feature flag it all... when it's all built I can take a break from playing and do a
test through each section, and report back one big log and screenshots. Ensure our logging
is able to capture everything you would need to fix any issues. Make double sure we are
referencing github.com/Gethe/wow-ui-source." Logging in on the device logs the owner out
of the game, so there are no device rounds until everything is built.

Each part below gets its own spec file written by its builder before any code, then tests,
then code. This file is the shared charter: every part's spec inherits it.

## Rules for every part

1. **Blizzard's source is the spec for the game.** `~/.cache/wow-ui-source/forever`, commit
   `c01a87b` = build 1.60.1 (71091), the build the device runs. Every game function, frame,
   field, event and setting used is read there first and cited (file and line) in a comment
   or the part's spec. What cannot be proven there goes in `docs/ARCHITECTURE.md`
   (Unverified API) with its worst case. `scripts/audit-api.sh` after adding any game call.
2. **Never call a function Blizzard wrote in Lua that writes a field or a global.** That is
   what broke the controller on 2026-11-24 (`FCF_SetWindowAlpha` wrote `oldAlpha` on the chat
   windows; the game then refused its own controller actions). Use a frame's own engine
   methods (Hide, Show, SetAlpha, SetPoint, SetScale...). Never assign a field on a game
   frame or table. `hooksecurefunc` and `HookScript` are allowed; `SetScript` on a game
   frame is not. Part 1 builds the offline check for this; parts 2 and 3 must pass it.
3. **Everything new is behind a switch that starts Off**, saved per character with the
   Controller layout's options, read at login. Off must mean the code for that part does
   nothing at all: no hook, no frame made, no event. A switch that changes what already ran
   this session says "counts from the next reload". The settings list may grow long; it
   scrolls. Tidying the options is a later job.
4. **Nothing of the game's is moved, hidden or changed in a fight** (`PE:RunOutOfCombat`).
   Nothing ticks while nothing changed. Switching a part Off, or the Controller layout Off,
   puts back everything that part touched.
5. **Handlers and callbacks through `PE:Safe` / `PE:Wrap`.** No libraries. Interface 16001.
6. **Logging good enough to fix it from one file.** With the Debug log on, each part writes:
   a line when it switches on and off, with its option values; every decision that changes
   what the player sees (and the reason when it decides to do nothing); every game call that
   fails or is missing, with the name; the numbers behind every placement (piece, anchor, x,
   y, scale). Never per frame, never in a loop that runs every event: once per change.
   Part 1 adds a snapshot and a section marker for the device test.
7. **Tests first** (`tests/features/`, the fake client in `tests/lib/fakeclient.lua`).
   `scripts/check.sh` and `scripts/test.sh` pass before every commit. Tests prove logic, not
   behaviour: say so, and write the device steps for what only the device can show.
8. **Plain language** in option labels, chat lines, CHANGELOG and TESTING: the owner is a
   player. Comments follow the repo's wording check.
9. One commit per finished piece on branch `playing-screen-0.17.0`. No push, no release:
   the orchestrator does those. TOC `## Version` and CHANGELOG change together.

## Part 1: 0.16.4, clean-up and what the device test needs

- **Offline check for calls into Blizzard's Lua** (`tests/taint/`), as Task 2 of
  `docs/superpowers/plans/2026-11-24-blocked-action-0.16.1.md`: every such call in the addon
  and the probe listed with what it writes; the check fails on an unlisted call. Wired into
  `scripts/test.sh`. Report every call that writes.
- **The Inspect button's picture** (right pad, top, at rest) draws as a black square
  (`docs/11-24-errorsPostWork/followup/Screenshot_20261124-184415.png`). The game draws the
  icon on a round black backing (`MainActionBarFrame.lua`, `SetupNonBindableSlotBackdrop`).
  Ours should look like the other three special buttons.
- **Enemy targeting (RB held): the B square is empty** though the game lists "B: Assist
  Target" (`...184436.png`). Find why from the source and fix it.
- **Friendly targeting (LB held)** (`...184427.png`): the left side shows four empty d-pad
  squares and no face buttons, and the right side shows the RT panels. It is not known
  whether RT was also held. Work out from the source and `FaceBars.lua` what should be
  drawn for the friendly targeting bar; fix what is wrong; and make the log say which bar,
  group and state were drawn so the device test settles it.
- **The six testing rows stay**, renamed from "Test: ..." to "Part: ..." (they are the
  switches for the existing parts). Default On.
- **Snapshot.** A button "Save a snapshot" (Debug log tab, and usable from the Controller
  tab): writes to the debug log, once, every piece the layout knows (the game's frames it
  placed, our pictures, panels and bars, the PE button): name, shown or hidden, left,
  bottom, width, height, scale, and for each pair that overlaps, both names and the overlap
  in pixels. Also the active Edit Mode layout's name, every switch's value, the screen size
  and UI scale. Out of a fight only; values the game hides are written as `<secret>`.
- **Section marker.** A button "Mark a test section" that writes
  `==== section N ====` to the debug log and says "Section N marked" in chat, N counting up
  per session; the device test script tells the owner when to tap it.
- **The debug log must hold a whole test sitting.** Check its cap and what happens when it
  is reached; a 60-minute test of every section with fights must not lose its start. If the
  cap has to change, weigh memory (the 2026-11-21 audit wanted it lower): keep the first
  lines of each session and the newest, drop the middle, and say so in the log.
- **Changes in build 71091** against 70938 that touch what the addon relies on:
  `ContainerFrame.lua` (the game removed `ApplySmartNavOverrideForLeftmostButton`),
  `SmartNavigation.lua`, `Camelot/TargetFrame.lua`. Check the addon and the comments' line
  numbers that cite these three files; fix what moved.

## Part 2: 0.17.0, the slim bars

Spec: `docs/superpowers/specs/2026-11-24-playing-screen-layout-design.md`, "0.17.0: the slim
bars". The probe's buff trials have not been run, so:

- Built now: the player bar, pet bar, target bar, target of target bar and the target's cast
  bar, as that table describes, in a new file following `FaceBars.lua`'s pattern; the game's
  four unit frames stay alive and are made invisible; the tooltip moves to the bottom right
  corner. Display only.
- **Not built: the buff and debuff boxes.** The spec makes them depend on the probe. The
  device test includes the probe's "Buffs in a fight" run so they can follow.
- Values the game hides in a fight are passed straight to the widgets that accept them
  (the spec's Constraints); never compared, added or formatted.
- Switch: "Slim bars", Off by default. Off leaves the game's frames exactly as 0.16.x has
  them.
- The overlap check in `tests/features/layout_test.lua` covers the new pieces at all five
  Spell panel sizes and trigger states.

## Part 3: 0.18.0, arrange it yourself

The owner: "I love the idea of me tweaking things where I want it, my only concern is it
not being perfectly symmetrical." No brainstorm was possible; this is a first version to
react to, and its spec says so.

- A switch "Arrange it yourself", Off by default. On adds an "Arrange" screen where the
  owner picks a piece of the layout and moves it with the d-pad or on-screen arrows, in the
  manner of the existing "Move on screen" (`Move.lua`). Touch and controller both work.
- Moves are saved per character as an offset from the piece's built-in spot, so a later
  change to the built-in layout still applies underneath.
- **Symmetry:** pieces that have a left / right twin move together, mirrored about the
  screen's centre line (on by default, can be switched off per pair); a piece within a few
  pixels of the centre line snaps to it; moves are in whole steps (a coarse and a fine
  step); "Reset this piece" and "Reset all".
- **Overlap warning:** while arranging, a piece that overlaps another is outlined and named.
  It warns; it does not forbid.
- Pieces the game places through its Edit Mode layout cannot move live: the screen says so,
  collects the moves, writes the layout once on "Apply" and asks for one reload. Our own
  pieces move live.
- Every Apply writes all offsets and the resulting spots to the debug log, so the owner's
  arrangement can become the built-in one.
- The game's spell wheel (LB+LT, RB+RT) opens over the swing timers and the map's edge
  (`...184442.png`, `...184451.png`). It is the game's; report whether it can be moved
  safely, and do not move it if that needs a call rule 2 forbids.

## Not in this batch

- Buff boxes (need the probe's results). Performance fixes (need the device recording).
  Per-character feature switches. The second arrangement. Merging to `main`, CurseForge.
