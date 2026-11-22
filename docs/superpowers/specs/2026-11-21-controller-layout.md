# Controller layout, first build (unprobed)

Piece 3 of 3 from `docs/ui-review/2026-11-20-action-bars-gameplan.md`
("Controller layout, piece 3"). Planned version: 0.11.0.

**Approval.** The owner was away and wrote on 2026-11-21: "Is it possible to
build without the probe or the screenshots? ... I think the mock is a really
good start, can we start getting things made and then when I return we can
run the probe and adjust from there?" This spec is approved by that
instruction, for an experimental build. Every number of position and size in
it is a first guess, and nothing in it has run on a device.

## Why

The owner, on the RP6 at 720p with the game's Gamepad UI: "minimap in center
middle, we could build out the buttons around the map and then stick the chat
up where the map used to be ... this is for me, what will make playing on the
go feel premium." Arranging the screen in Edit Mode on a handheld is "brutal",
so the addon gives "a new default template to work from".

## Goals

- One switch gives a whole new screen arrangement for controller play.
- It is a starting point: what the player then moves in Edit Mode is kept.
- Switching off brings back exactly the layout that was active before.
- Light: positions are set at login and when an option changes. Nothing runs
  while playing, and nothing at all while the switch is off.

## Not goals

- Touch players, and play without the game's Gamepad UI.
- Bars or buttons of our own. Every button stays Blizzard's.
- Fading bars (Quiet bars, and the "Swap" idea below). Waits for the probe.
- Changing the sub-menu wheels' size or look.
- A flashing border for low health (parked in PRD.md).

## Anti-goals (a failure even if it works)

- Any "Interface action blocked" message, in or out of combat.
- The player's own Edit Mode layouts changed, renamed or deleted.
- A switch that cannot be undone.

## What the source allows (build 1.60.1.70938)

Read on 2026-11-21. File paths are under `Interface/AddOns/`.

1. **A bar cannot be split.** Each of the four gamepad bars holds a d-pad
   group and a face-button group, but the game puts every button back at a
   fixed offset from its bar's centre on every button press, in combat too
   (`Blizzard_GamepadActionBars/ActionBarStyles.lua:119-156`, called from
   `ActionBarButton.lua:421-433`). An addon may not move a spell button in
   combat, so a split would snap back at the first press. Scaling does not
   help: offsets and sizes scale together.
2. **Whole bars can be moved and scaled out of combat.** The game never sets
   the scale of the bars or of their four anchor frames, and never re-anchors
   `BottomCenteredAnchor`. It re-anchors the Top, Left and Right anchors only
   in `PageUnit:RefreshCompactLayout` (`PageUnit.lua:292-315`), which runs
   when the Gamepad UI starts and when Edit Mode's Compact setting changes.
3. **The stance, possess and target bars follow the top anchor**
   (`GamepadOverrideBarMixin.lua:59-65`, `MainActionBarFrame.xml:55-93`), so
   moving the anchor (not the bar) keeps them with the main bar.
4. **The two sub-menu buttons cannot be placed freely.** The game re-anchors
   each to `BottomCenteredAnchor` at x = -138 / +138, y = -50 on every press
   (`ClassActionFlyout.lua:24-25, 50-54`). They can only move together, by
   moving that anchor. The both-triggers bar itself can then be put elsewhere
   with its own `SetPoint`, which the game never undoes.
5. **The wheel must not be scaled.** It places itself in screen units at its
   button's centre each time it opens (`FlyoutRadial.lua:200-224`); a scaled
   wheel would land in the wrong place, and an addon cannot correct that in
   combat.
6. **The game's own layout calls exist for addons**: `C_EditMode.GetLayouts`,
   `SaveLayouts`, `OnLayoutAdded`, `SetActiveLayout`, `IsValidLayoutName`
   (`Blizzard_APIDocumentationGenerated/EditModeManagerDocumentation.lua`).
   Five saved layouts per type at most. `activeLayout` counts the three
   presets first (Modern 1, Classic 2, Gamepad 3).
7. **A layout used with the Gamepad UI must carry
   `interfaceStyle = Enum.InputDeviceInterfaceType.Gamepad`**, or the game
   strips the gamepad bar from it (`EditModeManager.lua:895-911`).
8. **Turning the Gamepad UI off makes the game switch to its Modern preset**
   (`Blizzard_Gamepad/Core.lua:102-106`).
9. **The target's target is part of the target frame** and cannot be placed
   by itself (`Blizzard_UnitFrame/Mainline/TargetFrame.lua:732-737`). The pet
   frame can (UnitFrame index 8), once marked as moved.
10. **Managed pieces ignore their saved spot until marked as moved**
    (`isInDefaultPosition = false`): the swing timers, the quest tracker, the
    pet frame (`EditModeSystemTemplates.lua:350-383`).
11. **Each swing timer has the game's own Visibility setting**: Always 0, In
    combat 1, Hidden 2 (`EditModeSettingDisplayInfo.lua:777-858`).
12. **The XP bar's size goes to 130% at most** and changes its width only.

## Approaches considered

- **A. A real Edit Mode layout plus whole-bar placement (picked).** The
  addon writes one new Edit Mode layout through the game's own calls and
  reloads; after the reload the game itself places the map, chat, buffs,
  frames, timers and XP bar. The addon then moves and scales the four bar
  anchors out of combat at each login. The owner chose the Edit Mode layout
  ("A") on 2026-11-21.
- B. No Edit Mode layout, the addon places every piece itself at each login.
  More code touching more of the game's frames, and Edit Mode changes would
  be fought. Turned down by the owner.
- C. The mockup's split main bar. Not possible safely (finding 1). A later
  probe may test a secure-handler route; not in this build.

## What differs from the mockup, and why

The owner approved the mockup's arrangement; findings 1, 4, 5 and 9 rule
parts of it out. This build keeps the idea and changes these points:

| Mockup | This build |
|---|---|
| Main bar split around the map | Main bar whole, **above the map** (default) or **under the map** |
| Both-triggers pads: Above / Corners / Swap | Both-triggers bar whole and smaller, above the main bar (above the map when the main bar is under it). Swap waits for the probe's fade result |
| Sub-menu buttons on the map's rim, placed per setup | Both sit 138 either side of one point; that point is set so they flank the map's upper half |
| Smaller wheel, no dark disc | The game's wheel, unchanged |
| Target's target placed by itself | Rides on the target frame |

The LT bar left of the map and the RT bar right of it stay as designed.

## The feature

- Module key `ctrlLayout` (not `layout`: that was the Layout helper removed
  in 0.3.0, and an old saved file may still hold it switched on), file `ControllerLayout.lua`, label **Controller
  layout**, description "Map bottom middle, spell bars around it, chat top
  right." Marked experimental. Off by default.
- A new settings tab **Controller**, after Chat, holding this feature only
  for now. (Quiet bars and Quick slots join it when they are built.)
- A card in the setup guide, on a new screen "Controller", so every feature
  still has a switch in the guide.

### Blocked

The switch is blocked, with the reason shown, while:

- the game's Gamepad UI is off: "Needs the game's Gamepad UI (Options,
  Controller, Enable Gamepad UI)."
- the Edit Mode calls or the gamepad bar frame are missing: "This game
  version has no layouts an addon can change."

### Switching on

Runs out of combat (queued until combat ends) and refuses while Edit Mode is
open ("Close Edit Mode first.").

1. Read the layouts. Remember the active one in `opts.prev` as
   `{ name, layoutType, preset }` (preset id for a preset, else name and
   type), unless the active one is already ours.
2. If a saved layout named **Pocket Essentials** of type Account exists, use
   it as it is (the player's own changes to it are kept).
3. Otherwise build it (see "The template"), insert it after the last
   Account layout (or first after the presets), `SaveLayouts`, then
   `OnLayoutAdded(index, true, false)`. If five Account layouts exist
   already, stop with: "You already have 5 account-wide layouts. Delete one
   in Edit Mode, then switch this on again." and switch the feature back off.
4. If it existed already, `SetActiveLayout(index)`.
5. Read the layouts again. If ours already reads as active, good. If not,
   stay on anyway: the game may only report the change after the reload.
   Only a game call that raised an error switches the feature back off.
6. Ask for a reload: "Reload to finish changing the screen layout."
7. Place the bars now, best effort (see "Bars").

### Switching off

1. Put the bar anchors, the both-triggers bar and all scales back. Scales
   and the bottom anchor come from what was found before the first change;
   the Top, Left and Right anchors are rebuilt the way the game anchors
   them for its current Compact setting (`PageUnit.lua:292-315`).
2. If our layout is the active one, activate the remembered layout: the
   preset by id, or the saved layout by name and type. If it no longer
   exists, activate the Gamepad preset.
3. Clear `opts.prev`. Ask for a reload.
4. The "Pocket Essentials" layout is left saved, so switching on again
   returns to it. It is never deleted by the addon.

### While on

- At login, and after combat if login was in combat, place the bars, but
  only while our layout is the active one. If another layout is active, the
  bars are left as the game has them and the status line says: "Another
  Edit Mode layout is active. Pick Pocket Essentials in Edit Mode, or switch
  this off and on."
- `EDIT_MODE_LAYOUTS_UPDATED` re-checks which layout is active and places or
  restores the bars to match, out of combat.
- After the game's `RefreshCompactLayout` (a post-hook installed once, which
  does nothing while the feature is off), place the bars again out of
  combat.
- Nothing else. No timers, no OnUpdate.

## The template

Start from a copy of the active layout if its `interfaceStyle` is Gamepad,
otherwise from a copy of the game's Gamepad preset
(`EditModePresetLayoutManager:GetCopyOfPresetLayouts()`, the entry whose
`layoutIndex` is `Enum.EditModePresetLayouts.Gamepad`). Then set
`layoutName = "Pocket Essentials"`, `layoutType = Account`,
`interfaceStyle = Gamepad`, and change only the systems below. A system
missing from the base is skipped, never added. For every system changed,
`isInDefaultPosition = false`.

All numbers are UI units and first guesses. "Stored" is the raw setting
value the game saves.

| Piece (system, index) | Anchor: point, relativeTo, relativePoint, x, y | Settings (stored) |
|---|---|---|
| Minimap (Minimap) | BOTTOM, UIParent, BOTTOM, 0, mapY | Size 3 (80%) |
| Chat (ChatFrame) | TOPRIGHT, UIParent, TOPRIGHT, -30, -40 | Width 430 (4, 30), height 210 (2, 10) |
| Buffs (AuraFrame 1) | TOPRIGHT, UIParent, TOPRIGHT, -30, -262 | unchanged |
| Debuffs (AuraFrame 2) | TOPRIGHT, UIParent, TOPRIGHT, -30, -300 | unchanged |
| Quest tracker (ObjectiveTracker) | TOPRIGHT, UIParent, TOPRIGHT, -30, -345 | Height 0 (400) |
| XP bars (StatusTrackingBar 1, 2) | unchanged, `isInDefaultPosition` unchanged | Size 16 (130%) |
| Gamepad bar (GamepadMainActionBar) | unchanged | Compact 0, ShowEmptyBars 0, ShouldExpand 0 |
| Player, Pet, Target (UnitFrame 1, 8, 2) | see "Frames" | unchanged |
| Swing timers (SwingTimer 1, 2, 3) | see "Swing timers" | Scale 3 (80%), Width 0 (213), Height 0 (15), Visibility per option |

`mapY` is 44 when the timers are under the map (60 with Off Hand shown),
else 6.

Assumed sizes, to be replaced by the probe's measurements: map cluster at
80% is 164 wide and 176 tall; a bar is 208 by 68; a unit frame is 232 by
100; the pet frame 120 by 49; a timer at 80% is 170 by 12.

ShouldExpand 0 keeps every bar the same size whichever trigger is held, so
the arrangement does not shift. ShowEmptyBars 0 hides a bar with no spells
(the owner: empty buttons "will not exist at high level").

### Frames (option `frames`)

x and y in UI units. "L" means the anchor is on the left half; the target
mirrors the player.

| Option | Player | Pet | Target |
|---|---|---|---|
| `corner` (default) | BOTTOMLEFT, UIParent, BOTTOMLEFT, 20, 20 | BOTTOMLEFT, UIParent, BOTTOMLEFT, 40, 124 | BOTTOMRIGHT, UIParent, BOTTOMRIGHT, -20, 20 |
| `stacked` | BOTTOMRIGHT, UIParent, BOTTOM, -165, 112 | BOTTOMRIGHT, UIParent, BOTTOM, -185, 216 | BOTTOMLEFT, UIParent, BOTTOM, 165, 112 |
| `flat` | BOTTOMRIGHT, UIParent, BOTTOM, -165, 112 | BOTTOMRIGHT, UIParent, BOTTOM, -401, 130 | BOTTOMLEFT, UIParent, BOTTOM, 165, 112 |

### Swing timers (options `timers`, `ranged`, `mainHand`, `offHand`)

Anchor BOTTOM, UIParent, BOTTOM for all. Order from the top: Ranged, Main
Hand, Off Hand, 16 apart.

| `timers` | Ranged x, y | Main Hand | Off Hand |
|---|---|---|---|
| `under` (default) | 0, 24 | 0, 8 | 0, -8 (off screen is fine: starts hidden) |
| `above` | 0, topY + 40 | 0, topY + 24 | 0, topY + 8 |
| `bars` | -sideX, 6 | sideX, 6 | sideX, 22 |

`topY` is the top edge of the highest bar above the map at size 100%;
`sideX` is the LT bar's centre at size 100% (see "Bars"). With `under`, if
Off Hand is not Hidden the stack is Ranged 0, 40; Main Hand 0, 24; Off Hand
0, 8, and `mapY` is 16 higher. With `main = "under"` the `under` stack sits
between the main bar and the map: every y in that row is 78 higher.

Visibility starts Ranged In combat, Main Hand In combat, Off Hand Hidden
(the owner's choice).

## Bars (placed by the addon)

Frames, by Lua path from `GamepadMainActionBarFrame.PageUnit`:
`TopCenteredAnchor`, `LeftCenteredAnchor`, `RightCenteredAnchor`,
`BottomCenteredAnchor`, and the both-triggers bar
`BottomCenteredAnchor.Bar`.

For each: `ClearAllPoints()`, then
`SetPoint("CENTER", UIParent, "BOTTOM", x / s, y / s)` and `SetScale(s)`,
where s is the group's size. Only frames are moved and scaled; nothing is
written into a Blizzard table. Before the first change, each frame's points
and scale are read and kept for "Switching off".

Sizes: `size` (70 to 100%, step 5, default 100; see ruling 11) times the group's fine-tune
(`fineMain`, `fineSide`, `fineBoth`: 0.85, 1 or 1.15, default 1), capped at
100%. The both-triggers bar is a further 0.7 of its group size.
kM, kS, kB below are those three results.

With H = 68 (bar height), W = 208 (bar width), mapW = 164, mapH = 176 and
`lift` = 22 when `timers` is `bars`, else 0:

| Frame | `main = "above"` (default) | `main = "under"` |
|---|---|---|
| Left anchor (LT bar) | -(mapW/2 + 14 + W*kS/2), 8 + lift + H*kS/2 | -(W*kM/2 + 12 + W*kS/2), 8 + lift + H*kS/2 |
| Right anchor (RT bar) | mirrored | mirrored |
| Top anchor (main bar) | 0, mapY + mapH + 12 + H*kM/2 | 0, 8 + lift + H*kM/2 |
| Map `mapY` | as in the template | not moved by options: the template is written with `mapY = 8 + H + 14` (+ 36 with timers under) when `main` is `under` |
| Both-triggers bar | 0, top of the main bar + 22 + H*kB/2 | 0, mapY + mapH + 14 + H*kB/2 |
| Bottom anchor (sub-menu buttons at x -138 / +138, y -50 from it) | 0, mapY + mapH*0.62 + 50 | 0, mapY + mapH*0.5 + 50 |

The bottom anchor keeps scale 1, so the sub-menu buttons keep their size and
their wheels open in the right place.

## Options on the card

Shown while the feature is on. Rows marked (L) change the Edit Mode layout:
the addon rewrites only that piece's entries in the "Pocket Essentials"
layout, saves, and asks for a reload. A hand-moved spot for that piece is
replaced; other pieces are untouched. Rows marked (B) re-place the bars at
once, out of combat.

| Row | Choices | Default | |
|---|---|---|---|
| Main bar | Above the map / Under the map | Above | (B)(L: the map's height) |
| Player and target frames | Corners / Stacked / Side by side | Corners | (L) |
| Spell button size | 70 to 100%, step 5. Help line: "Below 100%, a spell that opens its own wheel may open beside its button." | 100% | (B) |
| Main bar size | Smaller / Same / Bigger | Same | (B) |
| LT and RT bar size | Smaller / Same / Bigger | Same | (B) |
| Both-triggers bar size | Smaller / Same / Bigger | Same | (B) |
| Swing timers | Under the map / Above the bars / Under the LT and RT bars | Under the map | (L)(B) |
| Ranged timer | Always / In combat / Hidden | In combat | (L) |
| Main Hand timer | Always / In combat / Hidden | In combat | (L) |
| Off Hand timer | Always / In combat / Hidden | Hidden | (L) |
| Template | button "Start over": rebuilds the "Pocket Essentials" layout from the template (second tap within 20 s to confirm) | | (L) |

The settings panel has no fold rows since 0.9.0, so the mockup's two "Show"
folds become plain rows; the tab scrolls.

Status lines (blue, under the description): the reload note while off
("Switching on or off reloads. Your old layout comes back when off."), and
while on either "Using the Pocket Essentials layout. Move the map, chat or
frames in Edit Mode; it is kept." or the "another layout" line above.

## Rulings (made without the owner; check these first)

1. The main bar stays whole (finding 1). Default spot: above the map.
2. One both-triggers placement. "Corners" has no whole-bar meaning; "Swap"
   needs the fade.
3. Sub-menu buttons flank the map at a fixed 276 apart; wheels unchanged.
4. ShouldExpand and ShowEmptyBars are switched off in the new layout.
5. The new layout is account-wide.
6. Timers "under the map" lifts the map by 38.
7. The quest tracker moves under the chat and buffs on the right.
8. Version 0.11.0; the Quiet bars spec, which planned that number, is not
   touched.
9. No fold rows; ten option rows on one card.
11. Spell button size starts at 100%, not the mockup's 85%. A spell on a
    bar that opens its own wheel places that wheel at the button's centre in
    the button's own scaled units (`FlyoutRadial.lua:220`), so on a scaled
    bar the wheel would open beside the button. Unconfirmed on the device;
    85% can become the default once it is.
10. Mid-play option changes that touch the layout ask for a reload instead
    of applying live.

## Pocket Probe additions

So the first device session can measure what this build guessed. Probe
version 0.4.0, area "Controller and layout".

- `layout.sizes` (value): width, height and scale of `MinimapCluster`,
  `PlayerFrame`, `PetFrame`, `TargetFrame`, `ChatFrame1`,
  `SwingTimerMainHandFrame`, `GamepadMainActionBarFrame`, each bar anchor and
  one bar; and UIParent's size.
- `bars.protected` (value): `IsProtected()` for the main frame, PageUnit,
  the four anchors, the four bars.
- `bars.settings` (value): `useCompactLayout`, `showEmptyBars`,
  `shouldExpand`, and the number of saved layouts by type.
- `bars.move` (action, risky): set the left anchor to the point it already
  has; pass if no error and the point reads back.
- `bars.scale` (action, risky): set the left anchor's scale to the scale it
  already has.
- `layout.save` (action, risky, clean): `SaveLayouts` with the list just
  read, unchanged; pass if the active layout and the count read back equal.

## Tests (offline, logic only)

- Template: every changed system gets the table's anchor, settings and
  `isInDefaultPosition = false`; untouched systems are byte-for-byte the
  base; a missing system is skipped.
- Each option value produces the table's numbers.
- Switching on: new layout inserted at Blizzard's index; five layouts
  refuses; an existing "Pocket Essentials" is reused untouched; previous
  layout remembered; reload asked; refused in Edit Mode; queued in combat.
- Switching off: preset and saved previous layouts restored; a deleted one
  falls back to the Gamepad preset; bar points and scales restored exactly.
- Bars: placed only while our layout is active; never touched in combat;
  re-placed after `RefreshCompactLayout`; nothing written to Blizzard tables.
- Nothing registered and no hook work while off (smoke test).

## Unverified, with the worst case

Logged in `docs/ARCHITECTURE.md`, "Unverified API".

- An addon's `SaveLayouts` / `OnLayoutAdded` leaves Edit Mode usable after
  the reload. Worst case: "Interface action blocked" until the reload; the
  reload is always asked for.
- `SetPoint` and `SetScale` on the bar anchors out of combat are allowed and
  are not blamed later in combat. Worst case: a blocked-action message; the
  feature is experimental and off by default; switching off and reloading
  removes every trace.
- Every size in "Assumed sizes". Worst case: pieces overlap or sit off
  centre until the numbers are corrected.
- Whether the game picks its Gamepad preset by itself when the Gamepad UI
  turns back on, leaving ours inactive. Worst case: the "another layout"
  status line shows and the bars stay as the game has them.
