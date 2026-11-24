# Controller layout 0.12.0 Implementation Plan

**Spec:** `docs/superpowers/specs/2026-11-23-controller-layout-0.12.0-mockup-setup.md`
(approved by the owner 2026-11-23). Mockup: `docs/ui-review/mockup-0.8.1.html`,
`pFaceBars` / `drawFace`.

**Goal:** the screen matches the mockup's "Face bars (one setup)" with the
game's real bars, one setup, and an owner already on our layout gets it with
one reload.

**Files:** `addons/PocketEssentials/ControllerLayout.lua`, `tests/features/layout_test.lua`,
`tests/lib/fakeclient.lua`, TOC, CHANGELOG, the spec's "As built".

## Anchors derived from the Camelot source (UI units, x from the centre, "up" from the bottom)

Source paths under `Interface/AddOns/` (branch forever).

| Piece | Anchor | Why |
|---|---|---|
| Map (MinimapCluster) | `BOTTOM`, UIParent, `BOTTOM`, -10, 38; Size 2 (70%); HeaderUnderneath 1 | Header underneath: the round map's container sits 30 up and 10 right of the cluster's bottom (`Blizzard_Minimap/Camelot/Minimap.lua:72-73`), scaled 0.7; container 253 (probe), map 198 centred in it (`Mainline/Minimap.xml:60-62`). Round map centre = 38 + 30 + 253 × 0.7 / 2 = 156.6 up, x 0 (mockup 153) |
| Title strip | follows the map: 46 to 69 up, x -11 | `Camelot/Minimap.lua:75-76` (`BOTTOM`, -1, 8), 152 × 23 (`Camelot/MinimapZoneTextButton.xml:9`) |
| Swing timers | `BOTTOM`, UIParent, `BOTTOM`, 0, y: Main Hand 31, Off Hand 17, Ranged 3; Scale 3 (80%), Width 0 (213), Height 0 (15) | 170.4 × 12 each (`EditModeSystemTemplates.lua:2784-2804`, `EditModeSettingDisplayInfo.lua:777-830`); offsets are UI units (`EditModeSystemTemplates.lua:373-375`) |
| Player (UnitFrame 1) | `BOTTOMRIGHT`, UIParent, `BOTTOM`, -236, 172 | frame 232 × 100 (`Blizzard_UnitFrame/Mainline/PlayerFrame.xml:14`), centred on the mockup's 222; bottom clear of the LT bar's top (167) |
| Pet (UnitFrame 8) | `BOTTOMRIGHT`, UIParent, `BOTTOM`, -236, 274 | 120 × 49 (probe), right above the player frame |
| Target (UnitFrame 2) | `BOTTOMLEFT`, UIParent, `BOTTOM`, 236, 172 | mirror of the player |
| Target of target | `BOTTOMLEFT` on `TargetFrame` `TOPLEFT`, 0, 2 (placed by the addon, out of a fight) | not an Edit Mode system: a secure button made by `TargetFrameMixin:CreateTargetofTarget` (`Mainline/TargetFrame.lua:732-737`, template `Mainline/TargetFrame.xml:397-405`), never re-anchored for the target frame |
| LT bar (Left anchor) | CENTER at -335, 133, scale 1 | mockup |
| Main bar (Top anchor) | CENTER at -335, 45, scale 1 | mockup |
| RT bar (Right anchor) | CENTER at 335, 133, scale 1 | mockup |
| LT+RT bar (`BottomCenteredAnchor.Bar`) | CENTER at 335, 45, scale 1 | mockup; the 0.7 factor goes |
| Sub-menu buttons (Bottom anchor) | anchor CENTER at 0, 238 → buttons at ±138, 188 | buttons sit at -138/+138, -50 from it (`Blizzard_GamepadActionBars/MainActionBarFrame.xml:94-112`) |
| LB/RB targeting pictures | `LeftShoulderBackground` `BOTTOMRIGHT` at -108, 84; `RightShoulderBackground` `BOTTOMLEFT` at 108, 84 (on UIParent `BOTTOM`) | they hang on the **main bar's** anchor (`MainActionBarFrame.xml:18-26`, -108 / +108, 42), not the sub-menu's; moving the main bar would take them along, so the addon re-anchors the two textures where the main bar used to hold them (the spots the 11:19 photo measured). No game code re-anchors them (only `SetAtlas`, `MainActionBarFrame.lua:642-649`) |
| Map icons (mail, tracking, day/night) | left as the game places them | mail sits in `MinimapCluster.IndicatorFrame`, which the Camelot map code re-anchors with the title strip (`Camelot/Minimap.lua:78-79`); tracking hangs on the strip (`Mainline/Minimap.xml:25-31`) |
| Quest tracker | `TOPRIGHT`, UIParent, `TOPRIGHT`, 0, -375 (was -30) | real width 260 (probe), not the mockup's 218: flush right keeps it clear of the RT bar except a 16-unit corner when it is long (As built) |

## Task 1: one setup in the plan (test first)

- Tests: "plan: map bottom middle at 70% with its title under it", "plan: swing
  timers stacked under the title strip", "plan: player, pet and target
  frames", "plan: four whole bars at the mockup's spots", "plan: sub-menu
  buttons 138 either side at 188 up", "plan: no piece overlaps another",
  "plan: the bars and frames clear the two wheel circles", "plan: old saved
  option values do not change the plan", "rows: only the switch's three timer
  rows and Start over".
- `Plan.Pieces`, `Plan.BarSpots` give fixed spots; `Plan.DEFAULTS` keeps the
  three timer visibilities; the removed rows go from `OPTIONS`; each timer
  row rewrites only its own timer.
- Commit: `Controller layout 0.12.0: the mockup's one setup`.

## Task 2: pieces the addon places itself (test first)

- The two targeting pictures and the target of target, placed and put back with
  the bars, out of a fight only.
- Tests: "bars: the targeting pictures go where the main bar used to hold
  them", "bars: the target of target sits above the target frame", "bars: off
  puts the targeting pictures and the target of target back", and the
  difficult game: "bars: a missing, nil or failing targeting picture or target
  of target places the rest", "bars: never in a fight".
- Commit: `Controller layout 0.12.0: targeting pictures and target of target`.

## Task 3: getting it without taps (test first)

- `Plan.TEMPLATE = 2`, saved as `opts.template` whenever our layout is built.
  In `Settle`, with the switch on and ours active and `opts.template` lower:
  rebuild ours from the template (Start over's steps), ask for the reload,
  chat line (logins only), save the version.
- Status lines while waiting: "Updating the layout after this fight" (in a
  fight), "Waiting for the game's layouts" (Edit Mode not ready).
- Tests: "template: an older layout is rebuilt once at login, asks the reload
  and says so", "template: the next login does nothing", "template: in a
  fight it waits and the status line says so", "template: waiting for the
  game's layouts says so", "template: a layout of the player's own is never
  touched", "template: a new layout saves the version", difficult game:
  "template: the rebuild failing logs it and tries again next login".
- Version 0.12.0 and CHANGELOG. Commit: `Controller layout 0.12.0: the new
  arrangement without taps`.
