# 0.3.0: Arrow Into Other Zones, Layout Helper Removed: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the never-tested Layout helper, and let the quest arrow point in a straight line at a focused quest's nearest spot in another zone of the same continent, behind a choice that defaults to today's text.

**Architecture:** `QuestData.lua` gains one pure, cached conversion (`QD:MapToMap`) built on `C_Map.GetWorldPosFromMapPos`; it turns a spot on any map into fractions of the player's map. `QuestArrow.lua`'s `Select` uses it when the quest has no spot on the player's map, then the existing `Update` maths runs unchanged on the converted position. Nothing new ticks.

**Tech Stack:** Lua 5.1 (LuaJIT offline), WoW interface 16001, the repo's stand-in client (`tests/lib/fakeclient.lua`) and feature tests (`tests/features/*_test.lua`).

**Spec:** `docs/superpowers/specs/2026-11-17-arrow-other-zones-and-layout-removal.md` (read it; this plan argues from it).

## Global Constraints

- Read `PRD.md` and `CLAUDE.md` first. No libraries. Event handlers and callbacks go through `PE:Safe` / `PE:Wrap` / `mod:Wrap`.
- Nothing ticks while its feature is off; this change adds no OnUpdate, timer or event registration.
- New behaviour defaults off: `otherZones` defaults to `"name"`.
- Every game value read is checked with `IsSecret` and `type` before use, and every new game call is inside `pcall` (the pattern in `QuestData.lua` `ReadPosition`).
- New game names (`C_Map.GetWorldPosFromMapPos`, `CreateVector2D`) must be found by `scripts/audit-api.sh`; anything it cannot find is guarded and logged in `docs/ARCHITECTURE.md` "unverified".
- Comments pass `scripts/check.sh`'s wording check; player-facing text is plain language.
- `scripts/check.sh` and `scripts/test.sh` pass at every commit. Commit on `main`, one commit per task, message prefix `0.3.0:`, ending with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Do not push.
- Exact values from the spec: fit tolerance 5 %; keep rule 80 % and 15 yards (the existing `KEEP_RATIO`, `KEEP_YARDS`); colour (0.55, 0.80, 1.00); option key `otherZones`, values `"name"` / `"point"`, labels "Quest in another zone", "Name the zone", "Point the way"; title `<zone> - <usual title>`.

## Review Focus

1. The spot's zone is on another continent: the text "Outside this zone / Head to <zone>" stays, no arrow (Task 3 test).
2. The game returns nothing, a secret value, or throws from `GetWorldPosFromMapPos`, or the function does not exist: text stays, no error logged (Task 2 and 3 tests).
3. A map whose conversion does not fit its size, or whose size is unreadable: no arrow (Task 2 test).
4. The player walks into the quest's zone while the blue arrow shows: gold arrow, normal title, "Here" works, set-aside list empty (Task 3 test).
5. Saved settings from 0.2.1 with `layout` switched on and its options present: loads with no error and no settings row (Task 1 test).

---

### Task 1: Remove the Layout helper

**Files:**
- Delete: `addons/PocketEssentials/Layout.lua`, `tests/features/layout_test.lua`
- Modify: `addons/PocketEssentials/PocketEssentials.toc` (drop the `Layout.lua` line), `tests/features/core_test.lua:14,55-60`, `tests/smoke/run.lua:79,536-557`, `tests/api/extract.lua:37-39,65-67`, `tests/api/*.txt` (rewritten by the audit)
- Leave alone: `tests/lib/fakeclient.lua` (its `C_EditMode` parts serve the probe tests), everything under `probe/`

- [ ] **Step 1: Write the failing test** in `tests/features/core_test.lua`:

```lua
test("core: a saved Layout helper from 0.2.1 is ignored: no module, no row, no error", function()
    local c, PE = T.new({ saved = saved({ layout = true, sellJunk = true }) })
    eq(PE:GetModule("layout"), nil)
    check(PE:IsModuleEnabled("sellJunk"), "sell junk did not come back on")
    PE:OpenSettings()
    c:advance(0.2)
    c:assertClean("0.2.1 saved layout")
end)
```

Use the file's own `saved(...)` helper; if it cannot also carry options for a module, extend the saved table by hand with the shape 0.2.1 wrote (read `Core.lua`'s saved-variables code for it).

- [ ] **Step 2:** Run `scripts/test.sh`. Expected: the new test fails (`GetModule("layout")` is a table).
- [ ] **Step 3:** Delete the two files and the TOC line. In `core_test.lua` and `smoke/run.lua` drop `"layout"` from `FEATURES`; move the "saved as a table is not on" case from `layout = {}` to `questArrow = {}`. In the smoke test remove the two `C_EditMode` / `activeLayout` checks and set the option-press floor to what the run now presses (`SMOKE_VERBOSE=1` prints it; keep the floor a few below the real count, as it is now). Keep the smoke test's Gamepad UI switch: chat and bags depend on it.
- [ ] **Step 4:** In `tests/api/extract.lua` remove the names and rows that exist only for `Layout.lua`, then run `scripts/audit-api.sh`. Expected: it passes and `tests/api/verified.txt` no longer lists any `C_EditMode` or `EditMode` name. `grep -rn "Layout.lua\|C_EditMode" addons tests/api scripts` returns nothing.
- [ ] **Step 5:** `scripts/check.sh && scripts/test.sh`: both pass. Commit `0.3.0: Layout helper removed`.

(Docs for the removal are in Task 4, so the doc edits land once.)

### Task 2: `QD:MapToMap`, with the stand-in client able to convert

**Files:**
- Modify: `tests/lib/fakeclient.lua` (`C_Map` namespace near line 1305; a global `CreateVector2D`), `tests/lib/questworld.lua` (`W.setup` map table), `addons/PocketEssentials/QuestData.lua` (new public section after `GetMapWorldSize`; header list at line 20), `tests/api/extract.lua` only if the audit needs a hint
- Create: `tests/features/mapconvert_test.lua`

**Interfaces:**
- Produces: `QD:MapToMap(fromMapID, x, y, toMapID) -> x2, y2 | nil`. `x, y` are fractions on `fromMapID`; the result is the same place as fractions of `toMapID` (may be below 0 or above 1). `nil` when either map has no usable conversion or the two are on different continents. Same map in and out returns `x, y` without any game call.
- Produces (tests only): stand-in maps take `continent`, `top`, `left` (`world.maps[id] = { name, width, height, continent, top, left }`); `world.mapWorldSwap = true` makes the stand-in return the two world components the other way round; `world.mapWorldSecret = true` makes it return a value marked secret.

- [ ] **Step 1: Stand-in client.** `C_Map.GetWorldPosFromMapPos(mapID, vec)`: for a map with a `continent`, returns `continent, pos` where `pos.x = top - fy * height` (north-south, growing north) and `pos.y = left - fx * width` (east-west, growing west), `pos` having `x`, `y` and `GetXY`; returns nothing for a map without `continent`. `CreateVector2D(x, y)` returns the same kind of table. In `questworld.lua` give the maps: Elwynn Forest `continent = 0, top = -7939, left = 1535`; Duskwood `continent = 0, top = -9716, left = 833`; Dun Morogh `continent = 0, top = -4487, left = 1802`; Mulgore `continent = 1, top = -272, left = 2047`.

- [ ] **Step 2: Write the failing tests** in `tests/features/mapconvert_test.lua` (same skip-without-QuestieDB header and `QW` setup as `questarrow_test.lua`; switch `questArrow` on so quest data is acquired):

```lua
-- Expected values worked out here from the maps' corners, not by the addon.
local function expected(c, from, x, y, to)
    local a, b = c.world.maps[from], c.world.maps[to]
    local north, west = a.top - y * a.height, a.left - x * a.width
    return (b.left - west) / b.width, (b.top - north) / b.height
end

test("map convert: the same map returns the position unchanged", ...)          -- eq 0.3, 0.7; no call to C_Map.GetWorldPosFromMapPos
test("map convert: Duskwood to Elwynn matches the corners' arithmetic", ...)   -- QW.AWAY 0.5,0.5 -> QW.HOME within 1e-6; y2 > 1 (Duskwood is south)
test("map convert: world components the other way round still convert", ...)   -- world.mapWorldSwap = true; same expected values
test("map convert: another continent gives nil", ...)                          -- QW.MULGORE -> QW.HOME
test("map convert: a map the game cannot convert gives nil, and is tried again after a zone change", ...)
    -- remove Duskwood's continent: nil. Put it back: still nil (kept). Fire ZONE_CHANGED_NEW_AREA, advance 1.5: a pair of numbers.
test("map convert: a conversion that does not fit the map's size gives nil", ...) -- Duskwood width = 5000 after setup
test("map convert: a map whose size cannot be read gives nil", ...)            -- Duskwood width, height = 0
test("map convert: a secret value or an error from the game gives nil and logs no error", ...) -- world.mapWorldSecret; then replace the function with one that errors; c:assertClean
test("map convert: each map is asked twice, once", ...)                        -- 3 conversions Duskwood->Elwynn: #c:callsTo("C_Map.GetWorldPosFromMapPos") == 4
```

- [ ] **Step 3:** Run `scripts/test.sh`. Expected: these fail with "attempt to call method 'MapToMap' (a nil value)".
- [ ] **Step 4: Implement in `QuestData.lua`.** Per map, sample fractions (0,0) and (0.5,0.5); the component that changes with map y is north-south. Check which component is which against `QD:GetMapWorldSize` (north-south span against height, east-west against width, each within 5 %; if they fit only the other way round, swap; if neither or the size is nil, the map is unusable). Keep `{ inst, u0, ku, v0, kv }` per map, `false` for unusable. Forget the `false` entries in `OnZoneTimer`. The conversion:

```lua
-- theirs / mine: the kept conversions of fromMapID / toMapID, same inst
x2 = (theirs.v0 + theirs.kv * x - mine.v0) / mine.kv
y2 = (theirs.u0 + theirs.ku * y - mine.u0) / mine.ku
```

Read the vector with `GetXY` when it has one, else `.x` / `.y`. Add the function to the header's public list.
- [ ] **Step 5:** `scripts/test.sh` passes. Run `scripts/audit-api.sh`: `C_Map.GetWorldPosFromMapPos` is listed "documented"; if `CreateVector2D` is not found, keep the plain-table fallback (`{ x =, y = }`) and log it in `docs/ARCHITECTURE.md` under unverified with worst case "other-zone arrow stays as text".
- [ ] **Step 6:** Commit `0.3.0: quest data converts a spot from one map to another`.

### Task 3: The arrow points into other zones

**Files:**
- Modify: `addons/PocketEssentials/QuestArrow.lua` (header comment; `DEFAULTS`; a `COLOR_FAR`; `Select`'s "no spot on this map" branch at 372-383; `Paint`; `ShowDistance`; the module's `options`), `tests/features/questarrow_test.lua`

**Interfaces:**
- Consumes: `QD:MapToMap(fromMapID, x, y, toMapID) -> x2, y2 | nil` (Task 2); the stand-in map fields from Task 2.
- Produces: option `otherZones` (`"name"` default, `"point"`); state `S.far` (true while the target is on another map).

- [ ] **Step 1: Write the failing tests** in `questarrow_test.lua`, under a new heading "Other zones". Helper: `newFar(spec)` = `newArrow` with `focus = QW.ELSEWHERE` then the file's `choose("otherZones", "point")` pattern (lift `choose` out of the positions test to file level) and `c:advance(1.2)`.

```lua
test("quest arrow: other zones: off by default, the text stays", ...)
    -- newArrow({ focus = QW.ELSEWHERE }): distText "Outside this zone", no call to C_Map.GetWorldPosFromMapPos
test("quest arrow: other zones: Point the way shows a light blue arrow, yards and '<zone> - <title>'", ...)
    -- box shown; arrow vertex colour 0.55, 0.80, 1; distText matches "^%d+ yd$" and equals the straight-line
    -- yards worked out in the test from the maps' corners (rounded to 10 above 300); titleText "Duskwood - Morbent Fel";
    -- published(PE) is the Duskwood pin
test("quest arrow: other zones: the arrow turns toward the spot", ...)
    -- Duskwood lies south: facing north shows Turn around; facing south (math.pi) the arrow's rotation is within 30 degrees of 0
test("quest arrow: other zones: no Here and nothing set aside", ...)
    -- move Duskwood's corner so the spot is 5 yards from the player: distText is "5 yd", colour still light blue
test("quest arrow: other zones: another continent keeps the text", ...)          -- Duskwood continent = 1
test("quest arrow: other zones: no conversion keeps the text and logs no error", ...) -- Duskwood continent = nil; assertClean
test("quest arrow: other zones: walking into the zone gives the gold arrow, the plain title and Here", ...)
    -- player.map = QW.AWAY at the pin's x, y + 0.02; fire ZONE_CHANGED_NEW_AREA; advance 1.5: colour gold,
    -- titleText "Morbent Fel"; move onto the pin: "Here"
test("quest arrow: other zones: a spot on this map always wins", ...)            -- focus QW.MANY (Elwynn and Dun Morogh spots): gold, published pin is on QW.HOME
test("quest arrow: other zones: switching back to Name the zone restores the text at once and stops the driver", ...)
test("quest arrow: other zones: nothing of ours ticks once the feature is off", ...)
test("debug log: other zones: one 'pointing across zones' line per change; 'another continent' named when it cannot point", ...)
```

- [ ] **Step 2:** `scripts/test.sh`: the new tests fail (no option, text shown).
- [ ] **Step 3: Implement.** In `Select`, when the quest has no spot on `playerMap`, `HasPlaces(byMap)`, the option is `"point"` and the player's map size is readable: go through every pin of every other map, convert with `QD:MapToMap(mapID, pin.x, pin.y, playerMap)`, take the nearest in yards; apply the keep rule against the old target when it is the same spot (same map, x, y, obj) and still present. Set `S.pin` to the real pin, `S.pinMap` to its map, `S.tx, S.ty` to the converted position, `S.width, S.height` to the player's map, `S.far = true`, `S.msgBig = nil`; title per the spec. `S.far` is false on every other path and in `OnDisable`. The check at the top of `Select` that drops `old` when `S.pinMap ~= playerMap` must keep a far target of the same quest. `Paint` takes the far colour when `S.far` and not here; `ShowDistance` never enters "Here" and never sets aside while `S.far`. The option's `OnChange` asks for a new choice (`Evaluate()` when ready). Debug lines per the spec. Update the header comment's "Which objective" list.
- [ ] **Step 4:** `scripts/check.sh && scripts/test.sh` pass, including the existing "another zone" tests unchanged (they run with the default).
- [ ] **Step 5:** Commit `0.3.0: quest arrow can point into another zone ("Quest in another zone")`.

### Task 4: Version, changelog and docs

**Files:**
- Modify: `addons/PocketEssentials/PocketEssentials.toc` (`## Version: 0.3.0`), `CHANGELOG.md`, `PRD.md`, `README.md`, `docs/DECISIONS.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `curseforge/description.md` (only if it names the Layout helper or the arrow's zone text)

- [ ] **Step 1:** TOC version 0.3.0. CHANGELOG `## [0.3.0] - 2026-11-17`, "Thirteenth test build", "Not yet tested on a device", sections **Added** (the "Quest in another zone" choice, in the player's words from the spec: what it shows, that it is a straight line, that it is off until chosen, when it falls back to the text) and **Removed** (Layout helper, with the spec's reason in two sentences and "Move things does the placing").
- [ ] **Step 2:** PRD: Status table (drop the Layout helper row; extend the Quest arrow row; untested), Goal coverage (goal 1 arrow row: other zones behind the choice; goal 5: drop the Layout row, keep Move things), Non-goals (a bundled handheld layout and switching Edit Mode layouts, dropped 2026-11-17), Parked ideas (remove the arrow-across-zones and handheld-layout items; add "routes across zones, other continents" as not planned), a short "0.3.0" paragraph after the ninth device test notes, Repo layout unchanged.
- [ ] **Step 3:** DECISIONS: a "Batch of 2026-11-17 (0.3.0)" section listing what was decided without the owner (the arrow as the next feature; off by default; light blue; no "Here" across zones; title format; the 5 % fit guard; saved Layout leftovers ignored). Mark the old "Layout" decisions and the two "left out" entries (nudge helper's last sentences, ready-made handheld layout, arrow across zones) as superseded by 0.3.0. ARCHITECTURE: file list, remove the three Layout rows from the unverified table and the Edit Mode facts that only Layout used, add a row for `GetWorldPosFromMapPos` ("whether the conversion is a straight line on every zone map of this client", worst case "the blue arrow points the wrong way; the choice is off by default"). README: drop the Layout row, add one line on the choice.
- [ ] **Step 4:** TESTING: replace step 8's body with one line saying the Layout helper was removed in 0.3.0 (keep the numbering so "step 9" references stay right; fix step 9's export instructions, which no longer apply). Add "### 12. Version 0.3.0" with numbered plain-language steps: (1) the Layout helper row is gone and nothing complains at login; (2) with a focused quest in a neighbouring zone, the text still reads "Outside this zone" until "Point the way" is chosen; (3) choose it: a light blue arrow, a distance, "<zone> - <quest>"; (4) open the world map and compare: the arrow should point at the quest's zone when you face the same way as the map's north; turn in a circle and it should keep pointing at the same place; (5) walk in: it turns gold on arrival in the zone; (6) focus a quest on the other continent: text only; (7) send the debug log.
- [ ] **Step 5:** `scripts/check.sh && scripts/test.sh && scripts/build.sh`: all pass; `dist/` holds `PocketEssentials-0.3.0.zip` and the bundle, and neither contains `Layout.lua` (`unzip -l`). Commit `0.3.0: version, changelog, status and test steps`.
