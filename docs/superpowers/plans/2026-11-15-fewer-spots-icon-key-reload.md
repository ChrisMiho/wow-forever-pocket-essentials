# 0.0.6: Fewer Spots, Icon Key, Reload Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show at most N spread-out icons per quest objective (default 5) while the arrow keeps its true nearest target, add an icon key page and a "Reload UI" button to the settings window.

**Architecture:** `QuestData.lua` marks surplus pins `extra = true` when an objective is built (farthest-point sampling per zone) and carries the arrow's current pin between the two quest features. `QuestIcons.lua` skips `extra` pins except the arrow's, and exports the icon list it draws from. `Settings.lua` gains one page and two buttons.

**Tech Stack:** Lua 5.1 (WoW addon, interface 16001), LuaJIT for `scripts/check.sh` and the offline harness `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-11-15-fewer-spots-icon-key-reload.md`

## Global Constraints

- Interface 16001, modern API, no libraries.
- Event handlers, hooks and callbacks go through `PE:Safe` / `PE:Wrap` (`mod:Safe` / `mod:Wrap` inside a feature). Exception already in the code: reload buttons call `PE:ReloadNow()` straight from `OnClick`.
- Nothing ticks while its feature is off. No new per-frame work: trimming happens in `Flush` during a rebuild only.
- Verify every new game API in `github.com/Gethe/wow-ui-source`, branch `forever` (a clone may exist at `~/.cache/wow-ui-source/forever`); log unverified ones in `docs/ARCHITECTURE.md` "Unverified API". This plan should need no new game API beyond `Texture:SetVertexColor`/`SetTexture`, already used.
- Match the surrounding code's comment density and plain-language style. `scripts/check.sh` rejects the phrase "the owner" (and similar) in Lua comments; write "the maintainer" or "the player".
- `scripts/check.sh` and `scripts/test.sh` must pass before every commit.
- Do not edit `curseforge/` or `scripts/make_art.py`. Do not push. Do not upload anywhere.
- No game client here: tests prove logic, not behaviour. Do not claim in-game results.
- Commit on branch `release-prep`, ending messages with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.

## Review Focus

1. Limit switched between All/10/5/3 while quests are cached: every quest must be rebuilt with the new marks (stale `extra` marks would hide or flood icons). Owned by Task 1 (harness check that changing `QD.spotLimit` re-marks).
2. An objective whose spots are all in one place or on one line (zero spread): sampling must still return exactly `limit` distinct pins and never loop or divide by zero. Owned by Task 1 (unit check).
3. The arrow's pin after a rebuild: pins are new tables after every rebuild, so a remembered pin goes stale. The icon must come back once the arrow re-chooses, and a stale pin must never raise an error or keep an icon forever. Owned by Task 2 (read-through; arrow clears and re-sets).
4. Arrow feature off or stopped (dungeon, no focus): `QD:GetArrowPin()` must be nil so no stray extra icon stays. Owned by Task 2.
5. Icon key page opened while "Quest icons" is off or QuestieDB is missing: the page must still draw all five rows. Owned by Task 3 (`PE.QuestIconKey` is built at file load, before `RegisterModule` can refuse anything; the page shows a plain line if the list is missing).

(No UI harness exists; 3 to 5 are checked by reading the code and in the device test.)

---

### Task 1: QuestData — spot limit and arrow pin

**Files:**
- Modify: `addons/PocketEssentials/QuestData.lua` (header comment, `Flush`, `Rebuild`, public section)
- Modify: `tests/questiedb/harness.lua` (new checks), `tests/questiedb/stubs.lua` only if needed
- `tests/questiedb/baseline.txt` must NOT change.

**Interfaces — produces:**
- `QD.spotLimit` — number, default `0` (no limit). Read at the start of `Rebuild` exactly as `QD.cluster` is: floor it, treat non-numbers and values below 1 as 0; when it differs from the value the cache was built with, `wipe(questCache)` and mark dirty.
- Pin field `extra = true` on pins beyond the limit (absent otherwise). Document it in the header's pin description: "users that draw skip `extra` pins; the arrow does not".
- `QD:SetArrowPin(pin)` — `pin` is a pin table or nil. No-op when unchanged; otherwise stores it and fires listeners with reason `"arrow"` (through the existing `Fire`). `QD:GetArrowPin()` returns it. `QD:Release` of the last user clears it without firing.
- `QD._Spread(pins, limit)` — test seam, also what `Flush` uses: given an array of pins (`x`, `y` in 0..1) on one map, with `#pins > limit >= 1`, returns nothing and sets `extra = true` on all but `limit` of them. Algorithm (spec Design 1): first keep the pin nearest the average position; then repeatedly keep the pin whose distance to its nearest kept pin is greatest (ties: lowest index); distance uses `dx * 1.5`. Keep a per-pin "distance to nearest kept" array updated after each pick, so the cost is O(n × limit). Reuse scratch tables; allocate nothing per call beyond first use.
- `Flush(out)`: after the existing `take` loop has decided which buffered pins survive, group this objective's surviving pins by map and call `_Spread` on each group larger than the limit. Do it with the limit captured at the start of the running rebuild (like `clusterCell`). Order of pins in `out` must not change.
- Header interface list gains `QD.spotLimit`, `QD:SetArrowPin`, `QD:GetArrowPin`, and `"arrow"` among the reasons.

- [ ] **Step 1: Failing unit checks in `harness.lua`** (a new numbered section before the baseline comparison, run once per persona load or once overall, using the loaded `QD`):
  - `_Spread` on 10 pins on a line `x = 0.1 .. 1.0, y = 0.5`, limit 3: exactly 3 without `extra`; they include `x = 0.1` and `x = 1.0` and one of the two middle pins (`0.5` or `0.6`).
  - `_Spread` on 8 identical pins, limit 5: exactly 5 without `extra`, no error.
  - `_Spread` with limit 1 on 4 pins at the corners of a square plus one at the centre: the centre pin is the one kept.
- [ ] **Step 2: Failing whole-data check.** In the per-persona pass, run the "in log, not complete" pass a second time with `QD.spotLimit = 5` over every quest (or reuse the pass with a second rebuild) and assert: (a) total pin count equals the count with limit 0; (b) at least one pin has `extra`; (c) for every quest and map, the number of pins without `extra` is at most `5 × (number of distinct objText values among that quest's pins on that map, counting nil as one)`; (d) setting `QD.spotLimit` back to 0 and rebuilding leaves no pin with `extra`. Follow how the harness already drives rebuilds and reads `QD:GetPinsForQuest`.
- [ ] **Step 3: Run `scripts/test.sh`** — expect FAIL on the new checks (`_Spread` is nil).
- [ ] **Step 4: Implement** per the Interfaces block.
- [ ] **Step 5: Run `scripts/check.sh && scripts/test.sh`** — both pass; baseline unchanged.
- [ ] **Step 6: Commit** `QuestData: spots-per-objective limit (marks extra pins) and the arrow pin`.

### Task 2: QuestIcons and QuestArrow — use the limit, show the arrow's spot, export the icon key

**Files:**
- Modify: `addons/PocketEssentials/QuestIcons.lua`
- Modify: `addons/PocketEssentials/QuestArrow.lua`

**Interfaces — consumes:** everything Task 1 produces.

**Interfaces — produces:**
- `PE.QuestIconKey` — array, in this order: slay, loot, object, event, turnin. Each entry `{ kind = "slay", label = "Kill", tex = <path>, color = { r, g, b }, desc = <one plain sentence> }`, with `tex` and `color` taken from the `STYLE` table and `label` from `KIND_LABEL` (not retyped). Assigned right after those tables are defined, before `RegisterModule`.
- `desc` wording: check `QuestData.lua` `ICON_KIND` and `BuildObjectives` for what lands in each kind (QuestieDB "talk" maps to `event`, "interact" to `object`; item objectives show whatever drops or holds the item). Proposed, adjust only if the code says otherwise: Kill "A creature to kill."; Loot "Where a quest item comes from: a creature that drops it or a thing that holds it."; Use "An object in the world to click or use."; Explore "A place to go to, or someone to talk to."; Turn in "Where to hand the quest in. Shown only once the quest is complete."

**QuestIcons.lua changes:**
- `DEFAULTS.spots = 5`. Option row after "Merge nearby icons": `{ key = "spots", label = "Spots per objective", choices = All(0) / 10 / 5 / 3 }`, `OnChange = OptionChanged("spots")`.
- A `SpotsValue()` helper next to `ClusterValue()` (non-number or negative → 5 default; 0 = All). `QD.spotLimit` is set wherever `QD.cluster` is set (`OnEnable`, `ApplyOption("spots")` followed by `QD:RequestRebuild()`), and reset to 0 wherever `QD.cluster` is reset (`OnEnable` failure path, `ReleaseData`).
- A file-local `arrowPin`, read from `QD:GetArrowPin()` in `OnDataChanged`. The three filters (`AnyShown`, the world map loop in `RefreshWorldMap`, the minimap loop in `UpdateMinimap`) additionally require `(not d.extra or d == arrowPin)`.
- `OnDataChanged("arrow")`: remember the old `arrowPin`, read the new one; if either is a table with `extra`, set `last.x = nil; acc = MINI_INTERVAL` and call `RefreshWorldMap(true)`; return without rebuilding the filter or touching the haze. For every other reason also refresh `arrowPin` first. Clear `arrowPin` in `OnDisable`.
- `/qd spots all|10|5|3` in `SlashCommand` and in `USAGE`.

**QuestArrow.lua changes:**
- In `Select`, after `S.pin = pin`: `QD:SetArrowPin(pin)` (nil when there is no pin).
- Wherever the arrow stops pointing — `StopDriver`, the module's `OnDisable`/release path, and any path that sets `S.pin = nil` — call `QD:SetArrowPin(nil)` (guard `QD` and the method's existence, as the file does elsewhere).
- `OnData(reason)`: return at once when `reason == "arrow"`.

- [ ] **Step 1: Implement** the above. Read both files fully first; keep the existing guard style (`type(x) == "function"` checks, `mod:Wrap`).
- [ ] **Step 2: `scripts/check.sh && scripts/test.sh`** pass.
- [ ] **Step 3: Self-check Review Focus 3 and 4** by reading: after a `"quests"` rebuild the arrow re-selects (`Evaluate` sets `selectDue`) and sets the new pin; with the arrow off `GetArrowPin()` is nil.
- [ ] **Step 4: Commit** `Quest icons: at most N spread-out spots per objective; the arrow's spot always shows`.

### Task 3: Settings — icon key page and Reload UI button

**Files:**
- Modify: `addons/PocketEssentials/Settings.lua`

**Interfaces — consumes:** `PE.QuestIconKey` (Task 2), `PE:ReloadNow()` (`Core.lua`).

- `page` gains the value `"key"`; `PE:OpenSettings("key")` selects it (unknown values still mean `"main"`). Title constant `TITLE_KEY = "Pocket Essentials - Icon key"`.
- `LayoutHeader`: Back shows on every page except main; Clear only on errors.
- `BuildKey(width)`: one row per `PE.QuestIconKey` entry — a texture from a new `pools.icon` pool (child of `area.child`, `SetTexture(entry.tex)`, `SetVertexColor(color)`, square, side `M.button`), the label with `PlaceText("font", ...)` and the desc with `PlaceText("small", ...)` to its right, a `PlaceLine` between rows. Row height at least `M.row`. After the rows, in `COLOR.dim` small text: "Tap an icon on the map to see what it is for." and "\"Spots per objective\" in Quest icons sets how many spots each objective shows." If `PE.QuestIconKey` is not a non-empty table: one line "The quest icons part of this addon did not load. See Errors." The pool must hide unused textures on other pages the way the existing pools do (`BeginPools`/`EndPools`).
- `DoRefresh`: picks title and builder by page; on `"key"`, as on errors, the paging buttons join `navList`.
- `BuildCoreSection`: the bottom button row becomes three buttons in one `FlowButtons` call: "Icon key" (`PE:OpenSettings("key")`, wrapped), "Reload UI" (calls `PE:ReloadNow()` directly from the click, not wrapped, with the same comment as the header's reload button), "Errors (n)" (unchanged). Check how `PlaceButton`/`FlowButtons` attach `onClick` to be sure the reload call stays in the click's own call stack.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: `scripts/check.sh && scripts/test.sh`** pass.
- [ ] **Step 3: Commit** `Settings: icon key page and a Reload UI button`.

### Task 4: Version and docs

**Files:**
- Modify: `addons/PocketEssentials/PocketEssentials.toc` (`## Version: 0.0.6`)
- Modify: `CHANGELOG.md` (new `## [0.0.6] - 2026-11-15` above 0.0.5, written for a player; 0.0.5 untouched)
- Modify: `PRD.md` (Status paragraph; status-table rows for Settings window, Quest icons, Quest arrow; goal-coverage row for icons; Parked ideas: remove the icon key and reload button lines, keep the radial wheel line with "see docs/DECISIONS.md, 'Radial wheel entry'"; second-device-test finding 4 reworded: the quest log's sub-menu that turns tracking on and off is hidden or broken; nothing in this addon touches the quest log window, so probably Blizzard's; needs a screenshot, and a check with "Quest icons" off after a reload)
- Modify: `docs/ARCHITECTURE.md` (tick list unchanged; add to Facts/Verified: `C_UI.Reload` documented in `UIManagerDocumentation.lua` with no restriction, `ReloadUI` called from Blizzard button clicks; mention the pin's `extra` mark under Structure's notes)
- Modify: `docs/DECISIONS.md` (new dated section "Batch of 2026-11-15 (0.0.6)": limit counts per objective per zone and applies to turn-ins too; the first spot kept is the one nearest the middle; no confirmation on Reload UI; icon key includes Explore; icon key and reload sit in the bottom section. New "left out" entry "Radial wheel entry" — text supplied by the coordinator in the task brief)
- Modify: `docs/TESTING.md` (steps 1, 2, 3 gain the spec's device-test items)
- Modify: `README.md` only if it lists settings or features that changed.

- [ ] **Step 1: Edit** the files. Plain language; lead with what changes in game.
- [ ] **Step 2: `scripts/check.sh && scripts/test.sh`** pass.
- [ ] **Step 3: Commit** `0.0.6: spots per objective, icon key, Reload UI button`.
