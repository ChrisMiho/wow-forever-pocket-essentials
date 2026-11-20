# Round button over the map's book icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While the world map is open at its normal size, the round PE button sits centred on the map's book icon; otherwise it is where it always is.

**Architecture:** `Hub:Refresh()` picks the anchor: the map's portrait texture when the map is shown and the portrait is shown, else today's `Placement()`. Hooks installed once (map OnShow / OnHide, `EventRegistry` `WorldMapMaximized` / `WorldMapMinimized`) just call `Hub:Refresh()`. The test stand-in gets the map's BorderFrame, its portrait, and maximize / minimize.

**Tech Stack:** Lua 5.1 (WoW Forever, Interface 16001), LuaJIT offline tests, fake client `tests/lib/fakeclient.lua`.

**Spec:** `docs/superpowers/specs/2026-11-20-round-button-on-map-design.md`

## Global Constraints

- Always on, no setting (owner's decision, recorded in the spec).
- Our button is never parented to a game frame; only anchored to the portrait. Nothing written to the map.
- Nothing ticks: re-placing happens only on map show / hide / maximize / minimize.
- Handlers through `PE:Wrap("hub", ...)`; every game call guarded (`type(...) == "function"`, `pcall` for registry calls), as `QuestIcons.lua:695-712` does.
- New game calls (`BorderFrame:GetPortrait`, events `WorldMapMaximized` / `WorldMapMinimized`) verified in wow-ui-source `forever` and `scripts/audit-api.sh` run; event names go in `docs/ARCHITECTURE.md`'s unverified table (the audit cannot check registry strings).
- Ruling: shipped inside 0.8.1 (not yet installed by the owner), so one device test covers both: CHANGELOG 0.8.1 entry and `docs/TESTING.md` section 17 grow, no new version.

## Review Focus

1. Map opened before the hub exists, or `Blizzard_WorldMap` loads late: the hooks still go on (retry on `ADDON_LOADED` "Blizzard_WorldMap") → Task 1 test "hooks go on when the map loads after login".
2. Button and red badge drawn under the map's border (same HIGH strata, lower level) → Task 1 sets the level; test checks button level > BorderFrame level and badge level > button level.
3. Map closed while full screen, then reopened at normal size → test sequence below.
4. "Move on screen" Reset / nudge while the map is closed still moves the button → existing move_test passes unchanged; one new test nudges after a map open/close.
5. Settings opened from the button while on the map (hold) → still opens; covered by the existing hold test plus a new tap-on-map test.

---

### Task 1: The button follows the book icon

**Files:**
- Modify: `tests/lib/fakeclient.lua:988-1010` (world map stand-in), `:1933-1946` (client actions)
- Modify: `addons/PocketEssentials/Hub.lua` (`Refresh`, `UpdateBadge`, new `MapPortrait`, `HookMap`, `Create`)
- Create: `tests/features/hub_test.lua` (auto-discovered by `tests/features/run.lua`)
- Modify: `tests/api/*.txt` (rewritten by `scripts/audit-api.sh`), `docs/ARCHITECTURE.md` (unverified table)

**Interfaces:**
- Produces in the fake client: `WorldMapFrame.BorderFrame` (Blizzard frame, strata HIGH, level above the map, TOPLEFT of the map) with method `GetPortrait()` returning a Texture (60 x 60, TOPLEFT of BorderFrame at -5, 7), shown by default; `Client:maximizeWorldMap()` hides the portrait and triggers registry `WorldMapMaximized`; `Client:minimizeWorldMap()` shows it and triggers `WorldMapMinimized`. Add the methods to the fake client the way `GetCanvas` is (`BlizzMethod`); if the snapshot gate rejects `GetPortrait` before the audit is run, run `scripts/audit-api.sh` after Step 3 and re-run.
- Produces in Hub.lua: `local function MapPortrait() -> Texture|nil` (the portrait when `WorldMapFrame:IsShown()` and the portrait `IsShown()`, else nil); `local function HookMap() -> boolean` (installs once).

- [ ] **Step 1: Write the failing tests** in `tests/features/hub_test.lua` (header comment citing the spec; `local T = ...`; end with `return { known = KNOWN_FAILURES }`). Use `T.new({})`, `c:advance`, and `PE.Hub.button`:
  - `test("hub: opening the map puts the round button on the book icon")`: `c:openWorldMap()`; `local p = WorldMapFrame.BorderFrame:GetPortrait()` (read from `c.env`); button centre equals the portrait's centre (`GetCenter`, within 0.5).
  - `test("hub: closing the map puts it back where it was")`: note the centre before, open, close; centre equals the noted one.
  - `test("hub: full screen map leaves it where it was; back to normal size puts it on the book")`: open, `c:maximizeWorldMap()` → centre = noted; `c:minimizeWorldMap()` → centre = portrait's.
  - `test("hub: closing a full screen map and opening it at normal size puts it on the book")`: open, maximize, close, minimize, open → on the portrait.
  - `test("hub: on the map the button and its badge are above the map's border")`: `PE.Hub:SetBadge("2")`, open; `button:GetFrameLevel() > BorderFrame:GetFrameLevel()`; the badge frame's level (`button`'s child that is not the label; or expose `PE.Hub.badge`) `> button:GetFrameLevel()`.
  - `test("hub: a tap on the button while it is on the map still works")`: chat feature on (`T.new({ on = { "chat" } })`), open map, `c:click(button)` → chat panel `PocketEssentialsChatPanel` shown.
  - `test("hub: Move on screen still moves the button after the map was open")`: open, close, nudge via `PE.Move` the way `move_test.lua` does; centre moved by the nudge.
  - `test("hub: hooks go on when the map loads after login")`: a client where `WorldMapFrame` is absent at login (use the fake client's option for late addons if it has one; otherwise `rawset(c.env, "WorldMapFrame", nil)` before login, restore it and `c:fire("ADDON_LOADED", "Blizzard_WorldMap")`); then open → on the portrait.
  - `test("hub: nothing ticks for the map")`: open and close the map twice; `c.stats.addonOnUpdate` and `c.stats.addonTimers` do not grow; `c:assertClean("hub map")`.
- [ ] **Step 2: Run** `scripts/test.sh` → the hub tests FAIL (button not on the portrait / no BorderFrame).
- [ ] **Step 3: Implement in `Hub.lua`:**
  - `Refresh()`: `local portrait = MapPortrait()`; with one, `button:SetPoint("CENTER", portrait, "CENTER", 0, 0)` and `button:SetFrameLevel(max(button:GetFrameLevel(), WorldMapFrame.BorderFrame:GetFrameLevel() + 10))`; without, today's `SetPoint`. Debug line once per change: `"on the map's book icon"` / `"back to its spot"` (key `"hub"`, only when `PE.debugOn`).
  - `UpdateBadge()`: set the badge level to `button:GetFrameLevel() + 3` every time, not only at creation.
  - `HookMap()`: needs `WorldMapFrame` with `HookScript` and `BorderFrame.GetPortrait`; `HookScript("OnShow"/"OnHide", wrapped Refresh)`; `pcall(EventRegistry.RegisterCallback, EventRegistry, "WorldMapMaximized" / "WorldMapMinimized", wrapped, Hub)`. Called from `Create()`; if it returns false, `PE:RegisterCoreEvent("ADDON_LOADED", "hub", fn)` that calls it for `"Blizzard_WorldMap"` and `Hub:Refresh()`.
  - Header comment: say the button moves onto the map's book icon while the map is open at normal size.
- [ ] **Step 4: Run** `scripts/audit-api.sh`, then `scripts/check.sh && scripts/test.sh` → all PASS; `tests/api/verified.txt` lists `GetPortrait`. Add the two registry event names to the unverified table in `docs/ARCHITECTURE.md` with their worst case ("the button stays on the book icon's spot when the map goes full screen, until the map is closed") and the source lines `Blizzard_WorldMap.lua:42, :62`.
- [ ] **Step 5: Commit** `git commit -m "0.8.1: the round button sits on the map's book icon while the map is open"`

### Task 2: Docs and device steps

**Files:**
- Modify: `CHANGELOG.md` (0.8.1 "Changed": one bullet), `PRD.md` (0.8.1 entry: one sentence with the owner's words; round button row), `README.md` ("Using it": one line), `docs/TESTING.md` section 17 (new steps before the Menu background step), `addons/PocketEssentials/Setup.lua` round button screen: add "While the map is open, it sits on the map's book icon."

- [ ] **Step 1: Write the device steps** in section 17: open the map: the button sits on the book icon, tap opens chat, hold opens settings, the red number (if any) is on top; drag/move the map window if possible: the button follows; full screen map: the button is back at its spot; close the map: back at its spot; in a fight, open the map: same.
- [ ] **Step 2: Update** the other files above. `scripts/check.sh && scripts/test.sh && scripts/build.sh` → pass; zips rebuilt.
- [ ] **Step 3: Commit** `git commit -m "0.8.1: round button on the map: changelog, PRD, README, guide text, device steps"`

Then stop for the owner's device test. No push, no upload.
