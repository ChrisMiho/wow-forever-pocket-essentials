# Controller layout 0.11.0: measured sizes and a Map size choice

An update to `2026-11-21-controller-layout.md`, which stays the main spec.
0.11.0 was committed but never released, so the version stays 0.11.0.

**Approval.** `docs/11-22-playsession/HANDOFF.md` step 3 asked for the
measured sizes to replace the guesses, with "its own short spec update and
the owner's go". On 2026-11-22 the owner chose "both builds" and
"publish pre-release" before stepping away. This spec is approved by that
instruction. The Map size row is a ruling made without the owner (see
"Rulings").

## What the measurements and the source say

From `docs/11-22-playsession/EVIDENCE.md` finding 6 (UI scale 1, screen
1365.3 by 768) and Blizzard's source, build 1.60.1.70938:

| Piece | 0.11.0 assumed | Now known | Change |
|---|---|---|---|
| Map cluster | 164 by 176 at 80% | 273 by 283 measured, scale 1. The Gamepad preset's map size is 100% (`Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:397`), so this is taken as the 100% size | **Yes** |
| A bar | 208 by 68 | 208 by 68 is Blizzard's size for a bar that does not grow (`Blizzard_GamepadActionBars/ActionBarStyles.lua:172`); 266 by 86 (line 173, and what the probe measured with "grow" on) is the grown size. The template switches growing off (ShouldExpand 0) | No |
| Player, target frame | 232 by 100 | 232 by 100 | No |
| Pet frame | 120 by 49 | 120 by 49 | No |
| Swing timer | 170 by 12 at 80% | 333 by 21 measured under the owner's own settings, not the template's. Not comparable | No |

The map's Edit Mode size scales a container inside the cluster
(`Blizzard_Minimap/Mainline/Minimap.lua:418-419`), and the cluster resizes
around it with some fixed padding. The size at a setting other than 100% is
therefore worked out as measured size times the percentage; the true value
may be a few units larger. Probe 0.5.0 measures the container so this can
be checked.

## Approaches

- **A. Constants from the measurement, scaled by a Map size option
  (picked).** No game call, the same numbers in the Edit Mode template and
  in the bar spots, fully testable offline.
- B. Read the map's size from the game each time the bars are placed.
  Exact, but the template is written before the reload that applies the map
  size, so the two halves would disagree for one session, and
  `PE.LayoutPlan` would stop being plain arithmetic.
- C. Keep the guesses and tune by eye on the device. Costs a device round
  for numbers we already have.

## Changes

1. **Map size.** `SIZE.MAP_W = 273`, `SIZE.MAP_H = 283` are the 100% size.
   A new option `map` (percent; 60, 70 or 80; default 80). The map's width
   and height everywhere in `PE.LayoutPlan` are those times `map / 100`.
   The template's Minimap `Size` setting is stored as `(map - 50) / 10`
   (80% is 3, as before; 70% is 2; 60% is 1).
2. **A new row on the card,** after "Main bar": **Map size**, choices
   60% / 70% / 80%, default 80%. It changes the Edit Mode layout and the
   bar spots, like "Main bar": the addon rewrites the map's entry, saves,
   asks for a reload, and re-places the bars.
   100% is not offered: the two sub-menu buttons sit a fixed 138 either
   side of the map's centre (main spec, finding 4) and a 273-wide map would
   cover them.
3. **Bar size stays 208 by 68.** The comments and the main spec say why it
   is no longer a guess.
4. **Wording.** "Every size and spot is a first guess" becomes true only of
   the spots and gaps: the file header, the main spec's "Assumed sizes"
   paragraph and `docs/ARCHITECTURE.md` "Unverified API" are updated to say
   which sizes are measured, which come from Blizzard's source, and which
   are still guesses (the timer size at 80%, the map at less than 100%,
   every spot and gap).
5. An unusable saved `map` value (not 60, 70 or 80) falls back to 80.

Nothing else in the feature changes: the same switch, the same frames
touched, the same events.

## What moves, at the defaults (80%, main bar above, timers under)

Map 218 by 226 instead of 164 by 176, so: the LT and RT bars sit 27 further
out (centres at 227 from the middle instead of 200); the main bar sits 50
higher (centre 316 above the screen's bottom); the both-triggers bar and the
sub-menu buttons follow. The frames' and timers' own spots do not change.

## Rulings (made without the owner; check these first)

1. The default stays 80%, as the main spec said. The approved mockup drew
   the map about 164 wide, which is really 60%. The row lets the owner pick
   on the device.
2. Version stays 0.11.0; the CHANGELOG entry is updated, not added to.

## Tests (offline)

`tests/features/layout_test.lua`: the bar spots, the map's y, the timer
spots and the template's Minimap entry for `map` 60, 70 and 80 against
numbers worked out by hand from this spec; an unusable `map` falls back;
the row saves, asks for a reload and re-places the bars; the existing tests
updated to the new sizes. Smoke test unchanged in meaning: nothing
registered while off.
