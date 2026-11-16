# 0.0.6: fewer icons per objective, an icon key, a reload button

Status: approved by the owner 2026-11-15 as an autonomous batch (the owner
answered the opening questions: default 5; the arrow's target always gets its
icon). Built as 0.0.6. No device test between the items; one test build.

## Why

Second and third device tests (PRD.md "Status"): one quest with many pick-up
spots floods the world map even with "Merge nearby icons" on "More". The owner
mostly needs the general area, and exact spots only matter when the spot is
special. Two small requests ride along: a page that explains the icons, and a
reload button so a reload never needs a typed command.

## Goals

1. A quest objective with many spots shows only a few icons, spread over the
   area the spots cover.
2. The arrow still points at the truly nearest spot, and that spot always has
   an icon.
3. A page in the settings menu shows every quest icon and what it means.
4. A "Reload UI" button in the settings menu.

## Non-goals

- The radial wheel entry: cut from this batch by the owner. Findings are in
  `docs/DECISIONS.md`.
- The quest log's hidden sub-menu (second device test, finding 4): nothing of
  ours touches it; noted in PRD.md as probably Blizzard's.
- Quests not yet picked up, the cross-zone arrow, anything CurseForge.

## Anti-goals

- Any work per frame for the trimming. It happens when quest data is rebuilt.
- An arrow that points at a "shown" spot instead of the nearest one.
- An icon key that can drift from the icons actually drawn.

## Approaches

Fewer spots:
- **A. Mark, do not remove (chosen).** When an objective's spots are built,
  `QuestData.lua` picks up to N per zone by farthest-point sampling and marks
  the rest `extra = true`. The icon code skips `extra` pins; the arrow reads
  the same list and ignores the mark, so it needs no second list.
- B. Remove the spots in `QuestData.lua` and keep a second, full list for the
  arrow. Rejected: two lists to keep in step.
- C. Trim in `QuestIcons.lua` when drawing. Rejected: that code runs ten times
  a second on the minimap.

The arrow's target icon:
- **A. The arrow tells the quest data which pin it points at; the icon code
  draws that pin even when it is `extra` (chosen by the owner).** At most one
  more icon; changes at most once a second (the arrow's own re-choose rate).
- B. Leave it hidden. Rejected by the owner.

Icon key and reload: one sensible way each. The settings window already has a
second page (Errors) and a bottom section with buttons; both items reuse them.

## Design

### 1. Spots per objective

- New quest-icon option **"Spots per objective"**: All / 10 / 5 / 3, default
  **5**. Saved as `spots` (0 = All). It sits after "Merge nearby icons", which
  stays as it is and still runs first.
- `QuestData.lua`: `QD.spotLimit` (number, 0 = no limit, default 0), used like
  `QD.cluster`: set it, then `QD:RequestRebuild()`; a changed value rebuilds
  every quest. In `Flush`, after the existing thinning, for each zone where
  the objective has more pins than the limit: choose `limit` pins by
  farthest-point sampling and set `extra = true` on the others. Start from the
  pin nearest the middle (the average position) so one icon always marks the
  general area; then keep adding the pin farthest from those already chosen.
  Distances are in map fractions with x stretched by 1.5 (maps are 3:2).
- The limit counts per objective per zone, for every kind including turn-in.
  An objective with `limit` spots or fewer is untouched.
- No pin is removed: pin counts in `tests/questiedb/baseline.txt` do not change.
- `QuestIcons.lua` sets `QD.spotLimit` from the option (as it does `cluster`)
  and puts the default back when it releases the data. The world map loop, the
  minimap loop and `AnyShown` skip a pin with `extra` unless it is the arrow's
  pin. Applies to the map and the minimap alike.
- `/qd spots all|10|5|3` as the typed backup.

### 2. The arrow's target

- `QuestData.lua`: `QD:SetArrowPin(pin|nil)` and `QD:GetArrowPin()`. A change
  fires the listeners with the new reason `"arrow"`.
- `QuestArrow.lua`: unchanged choice (nearest of all pins, `extra` or not).
  After choosing it calls `QD:SetArrowPin(pin)`; it clears it (nil) whenever
  it stops pointing (no pin, driver stopped, feature off). It ignores the
  `"arrow"` reason itself.
- `QuestIcons.lua` on `"arrow"`: if the old or the new arrow pin is `extra`,
  redraw the minimap on its next tick and refresh the world map if open.
  Otherwise nothing.

### 3. Icon key

- `QuestIcons.lua` exposes `PE.QuestIconKey`: an ordered list of
  `{ kind, label, tex, color, desc }` built from its own `STYLE` and
  `KIND_LABEL` tables (the ones the pins are drawn from). Built when the file
  loads, so the page works with the feature off.
- Order and wording (plain, checked against what `QuestData.lua` puts in each
  kind): Kill, Loot, Use, Explore, Turn in. Turn in says it shows only once
  the quest is complete.
- `Settings.lua`: a third page, `PE:OpenSettings("key")`, titled "Pocket
  Essentials - Icon key", with Back in the header like Errors. One row per
  icon: the real texture in its colour, drawn large (button height), the name
  in the big font, the meaning in the small font. Below the rows, two lines on
  using the icons: tap an icon for its text; "Spots per objective" limits how
  many show. Nothing to hover.
- Opened from a new **"Icon key"** button in the bottom section of the main
  page.

### 4. Reload button

- A **"Reload UI"** button in the same bottom section. It calls
  `PE:ReloadNow()` straight from the tap, as the existing "Reload now" button
  does. No confirmation: a reload loses nothing.
- `C_UI.Reload` is in the generated documentation for forever 1.60.1.70938
  (`UIManagerDocumentation.lua`) with no restriction listed; `ReloadUI` is
  called from Blizzard button clicks (`Blizzard_ScriptErrorsFrame.xml`).

### 5. Housekeeping

- Version 0.0.6 in the TOC and CHANGELOG (0.0.5's entry stays).
- PRD.md: Status, the status table, goal coverage, Parked ideas (icon key and
  reload button done; radial wheel stays parked with a pointer to the
  findings; quest log sub-menu noted as probably Blizzard's).
- `docs/ARCHITECTURE.md`: the pin's `extra` field, the reload fact.
- `docs/DECISIONS.md`: decisions made in this batch and the radial findings.
- `docs/TESTING.md`: steps for the three items.

## Device test

1. Quest icons on, a quest with many spots tracked. World map: each objective
   shows at most five icons, spread over the area. Change "Spots per
   objective" to 3, 10 and All: the map follows at once.
2. Focus that quest with the arrow on. Walk toward the arrow: the spot it
   points at has an icon on the minimap, even when it is not one of the five.
3. A quest with one or two spots looks as before.
4. Settings, bottom: "Icon key" opens a page with five rows; the icons look
   like the ones on the map. Back returns.
5. Settings, bottom: "Reload UI" reloads the interface.
6. Play ten minutes with the map opening and closing: no stutter, no errors
   on the Errors page.

## Left to the builder

- Exact wording of each icon's meaning, within the plain-language rule.
- Row sizes on the icon key page.
- How the offline harness proves the limit (for example: with the limit on,
  no quest has more unmarked pins per objective and zone than the limit, and
  the totals are unchanged).
