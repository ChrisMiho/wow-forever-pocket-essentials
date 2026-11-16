# Offline Test Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test the whole addon off the device: an API audit against Blizzard's source, a whole-addon smoke test, and rule tests per feature, run by `scripts/test.sh` and a GitHub Action.

**Architecture:** One stand-in for the game client (`tests/lib/fakeclient.lua`) whose frame methods and `C_` functions are limited to names listed in a committed snapshot of Blizzard's documentation (`tests/api/`). The smoke test and the feature tests load the real addon files into it. Nothing under `addons/` changes.

**Tech Stack:** LuaJIT (Lua 5.1), bash. Blizzard's interface source: `github.com/Gethe/wow-ui-source`, branch `forever`, build 1.60.1.70938; a shallow clone is expected at `~/.cache/wow-ui-source/forever` (`git clone --depth 1 --single-branch --branch forever https://github.com/Gethe/wow-ui-source.git ~/.cache/wow-ui-source/forever`).

**Spec:** `docs/superpowers/specs/2026-11-15-offline-test-suite.md`

## Global Constraints

- **No file under `addons/` is changed by any task.** If a test shows the addon is wrong, do not edit the addon and do not weaken the test: mark the case as a known failure (see "Known failures" below) and report it.
- Nothing from `tests/` or `scripts/` may be packaged: `scripts/build.sh` is not edited.
- `scripts/check.sh` plus `scripts/test.sh` together stay under about 10 seconds on a laptop (a Stop hook runs both every turn). `scripts/test.sh` keeps its current behaviour: skips with a notice (exit 0) when luajit is missing or QuestieDB cannot be downloaded; one summary line per suite on pass; `FAIL:` and exit 1 on failure. The existing QuestieDB harness and `tests/questiedb/baseline.txt` keep working unchanged.
- The network is used only by `scripts/audit-api.sh` and `scripts/fetch-questiedb.sh`; `scripts/test.sh` never needs the wow-ui-source clone.
- Tests are plain Lua run with `luajit`, no libraries beyond what is in `tests/lib/` already. Each test file prints `ok <name>` lines or fails with a message naming the rule and its source (PRD.md, docs/DECISIONS.md, or the file and comment).
- **Known failures:** a table at the top of each test file, `KNOWN_FAILURES = { ["test name"] = "one-line reason" }`. A listed test that fails prints `known failure` and does not fail the run; a listed test that passes fails the run (so the list cannot rot). Every entry goes in the task report.
- Do not edit `curseforge/` or `scripts/make_art.py` (another session is working there; uncommitted changes to those files in the working tree are not yours: never stage them — `git add` only your own paths).
- Do not push. Commit on `release-prep`, messages ending with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.
- No game client exists here: say "passes offline", never "works in game".

## Review Focus

1. A stand-in that passes vacuously: a frame method or game function that returns nil/no-op where the game would return a value the addon branches on, so the tested branch is never the real one. Each feature test must assert on an observable effect (a recorded call such as `C_Container.UseContainerItem(bag, slot)`, a chat line, a saved value), not on "no error". Owned by Tasks 2 and 3.
2. The addon's guards (`type(X) == "function"`) silently skipping a whole feature in the stand-in because a function is missing there: the smoke test must fail if a feature reports a blocked or failed state that the scenario did not intend. Owned by Task 2.
3. Widget methods called on Blizzard frames the addon does not create (`WorldMapFrame`, `Minimap`, `ContainerFrameCombinedBags`, `MerchantFrame`, chat edit boxes, `EditModeManagerFrame`): the audit must classify Lua-defined mixin methods (found in Blizzard's `.lua` source) separately from engine widget methods (found in the generated documentation). Owned by Task 1.
4. Time: C_Timer and OnUpdate driven by a manual clock, never real sleeping; a runaway timer loop must fail, not hang. Owned by Task 2.
5. Test isolation: each scenario gets a fresh client and a fresh addon load; no state leaks through `_G` between scenarios. Owned by Task 2.

---

### Task 1: API audit

**Files:**
- Create: `tests/api/extract.lua` (lists the names the addon uses), `tests/api/audit.lua` (checks them against the source), `tests/api/verified.txt`, `tests/api/unverified.txt`, `scripts/audit-api.sh`
- Modify: `scripts/test.sh` (add the fast check), `docs/ARCHITECTURE.md` only if the audit finds an unverified name with no row in "Unverified API" (add the row; do not remove rows)

**Interfaces — produces:**
- `tests/api/verified.txt`: one line per name, tab-separated: `kind<TAB>name<TAB>evidence`. `kind` is `global`, `namespace` (`C_Foo.Bar`), `method` (a widget method name, e.g. `SetPoint`), `event`, `cvar`, or `frame` (a Blizzard global frame/table such as `WorldMapFrame`). `evidence` is a path under `Interface/AddOns/` (and `documented` or `used` to say whether it is in `Blizzard_APIDocumentationGenerated` or only called/defined by Blizzard code). Sorted, stable, so a re-run with no change produces no diff.
- `tests/api/unverified.txt`: same first two columns, third column the plain-language reason. Every line must correspond to a row in `docs/ARCHITECTURE.md` "Unverified API" or be a Lua standard-library / our-own name wrongly caught (fix the extractor instead).
- `luajit tests/api/extract.lua <repo root>` prints the same `kind<TAB>name` list for the current addon files (used by the fast check and by Task 2's stand-in).
- `scripts/audit-api.sh [path to wow-ui-source clone]`: default `~/.cache/wow-ui-source/forever`; clones it if missing; verifies the clone's last commit message is `1.60.1 (70938)` and fails with a clear message otherwise; rewrites both snapshot files; exits 1 if a name is neither verified nor already in `unverified.txt`.
- Fast check in `scripts/test.sh`: every name from `extract.lua` appears in `verified.txt` or `unverified.txt`; prints `API audit: N names, M unverified, 0 new` or `FAIL:` listing new names and telling the reader to run `scripts/audit-api.sh`.

**Approach notes (decisions):**
- Extract from LuaJIT bytecode listings (`luajit -bl file.lua`: `GGET` for globals, `TGETS`/`MMCALL`-style string constants for fields and methods) rather than regexes over source, so comments and strings do not count. Globals the addon itself defines (`PocketEssentialsDB`, `SLASH_*`, the compartment function) and Lua standard names are excluded by a short explicit list in `extract.lua`.
- Events: string literals passed to `RegisterEvent`; verify against `LiteralName = "..."` in the generated documentation. CVars: literals passed to `GetCVar`/`SetCVar`/`C_CVar.*`; verify by grep of the quoted name in the source.
- Method names are verified as names (a method called `SetPoint` exists on some widget type in the `Simple*APIDocumentation.lua` / `FrameAPI*Documentation.lua` / `MinimapFrameAPIDocumentation.lua` files), or as a Lua-defined method (`function <Something>Mixin:Name` or `function <Frame>:Name` in Blizzard `.lua`), with the evidence saying which. Methods of our own objects (defined in the addon as `function X:Name` or `X.Name = `) are excluded.

- [ ] **Step 1:** Write `extract.lua`; run it; read the list for obvious junk (Lua library names, our own fields) and tighten the exclusions until every line is a real game name.
- [ ] **Step 2:** Write `audit.lua` and `scripts/audit-api.sh`; run against the clone; write the snapshots.
- [ ] **Step 3:** For every line in `unverified.txt`, confirm a matching "Unverified API" row exists in `docs/ARCHITECTURE.md`, or add one in that table's style (what, used by, what the player sees if it is wrong). A name that turns out to be missing from the client entirely with no guard in the addon is a **finding**: report it prominently.
- [ ] **Step 4:** Add the fast check to `scripts/test.sh`; prove it fails by temporarily deleting one line from `verified.txt`, then restore.
- [ ] **Step 5:** `scripts/check.sh && scripts/test.sh` pass. Commit `Tests: API audit against Blizzard's Forever source`.

### Task 2: Stand-in client and whole-addon smoke test

**Files:**
- Create: `tests/lib/fakeclient.lua`, `tests/smoke/run.lua`
- Modify: `scripts/test.sh` (run the smoke test), `tests/questiedb/stubs.lua` only if sharing code is clearly simpler (the QuestieDB harness must keep passing unchanged)

**Interfaces — consumes:** `tests/api/verified.txt`, `tests/api/unverified.txt` (Task 1 format).

**Interfaces — produces** (`local Client = dofile(root .. "/tests/lib/fakeclient.lua")`):
- `Client.new(opts) -> c` — a fresh client. `opts`: `root` (repo root), `questieDB` (`nil` | path to an unpacked QuestieDB release, loaded through the existing `tests/questiedb/stubs.lua` helpers), `saved` (table used as `PocketEssentialsDB`, default nil = first install), `screen = { w, h }` (default 1280×720), `gamepadUI` (bool).
- `c:loadAddon()` — runs every file of `addons/PocketEssentials/PocketEssentials.toc` in order with `("PocketEssentials", PE)`, then fires `ADDON_LOADED` and `PLAYER_LOGIN`/`PLAYER_ENTERING_WORLD` the way the client does. Returns `PE`.
- `c:fire(event, ...)` — delivers an event to every frame registered for it. `c:advance(seconds)` — moves the manual clock, running `C_Timer.After` callbacks and every shown frame's `OnUpdate` in 0.1 s steps; errors if more than 100000 callbacks run in one call.
- `c:click(frame)` / `c:script(frame, "OnClick", ...)` — runs a frame's script. `c:frames()` — every frame created, with `:IsShown()`, `.scripts`, `.events`, children and regions inspectable; `c:find(predicate)`.
- `c.calls` — an ordered log of every call to a game function or method that has a side effect in the real game (`{ name, args }`), with `c:callsTo(name)`; `c.chat` — lines printed to the chat frame.
- `c.world` — the scripted world the stand-in functions read: `bags` (`[bag][slot] = { itemID, quality, price, locked, count }`, `ignoreJunk[bag]`), `money`, `merchant = { open, canRepair, repairCost }`, `inCombat`, `group = "none"|"party"|"raid"`, `channels`, `guild`, `player = { map, x, y, facing }`, `questLog`, `cvars`, `chatLockdown`, `layouts`. Functions such as `C_Container.GetContainerItemInfo`, `GetMoney`, `InCombatLockdown`, `C_Map.GetBestMapForUnit` answer from it.
- `c.errors` — Lua errors caught by the client's own dispatch (they also fail `c:assertClean()`), and `PE.errors`/`PE:LogError` records. `c:assertClean()` fails the test if either is non-empty.
- Strictness: a frame method not listed as `method` in the snapshot files raises `attempt to call method '<name>' (not on this client)`; a `C_Namespace.Function` not listed raises likewise; reading an unknown global returns nil (the addon probes globals with `type(X) == "function"`). Methods on Blizzard frames that the audit classified as Lua-defined get explicit, minimal implementations for the frames the addon touches (`WorldMapFrame`, `Minimap`, `MinimapCluster`, `ContainerFrameCombinedBags`, `MerchantFrame`, the chat edit box, `EditModeManagerFrame`, `AddonCompartmentFrame`, `UIParent`, `GameTooltip`).
- Getters return realistic values (sizes that were set, effective scale 1, text that was set, `GetStringHeight` proportional to text length and width), so layout code takes its real branches.

**Smoke test (`tests/smoke/run.lua <repo root> [QuestieDB dir]`), scenarios each on a fresh client:**
1. First install: load; every feature is off; no `OnUpdate` script is set on any frame our addon made; open settings, press every button on every page at Small, Medium and Large (not "Reload UI"/"Reload now": assert only that pressing them calls `C_UI.Reload` exactly once); close. `c:assertClean()`.
2. Everything on, with QuestieDB: switch each feature on through the same function the settings switch calls; a quest log with three real quests (one with many spots, one complete, one in another zone), one focused; fire every event any frame registered, with plausible arguments, twice; `c:advance(5)` while the player position changes; open and close the world map, a vendor with greys, the bag, a whisper in and out; open every settings page again. `c:assertClean()`, and no feature is in a `failed` or unintended `blocked` state.
3. Everything on, QuestieDB missing: the two quest features report blocked with a reason; the rest behave as in 2.
4. Everything off again after 2: no frame made by the addon still has an `OnUpdate` script or a registered event that belongs to a feature (the core's own are allowed and listed explicitly); `c:advance(5)` runs nothing of ours.
5. Saved settings from an older version (`saved` with 0.0.2-style options, e.g. quest icons `show = "focus"` and no `spots`): loads clean; `spots` is 5; `show` is migrated to `"tracked"`.
6. Zip contents: read `scripts/build.sh`'s staging rule by running `unzip -l` on `dist/PocketEssentials-<version>.zip` if it exists (skip with a note if not): no path contains `tests/` or `scripts/`.

Prints `Smoke: 6 scenarios, 0 errors` on pass.

- [ ] **Step 1:** Read every addon file enough to list the game functions, frames and events each uses (Task 1's `extract.lua` output is the checklist). Build `fakeclient.lua` to the Interfaces block.
- [ ] **Step 2:** Write scenario 1, make it pass honestly (fix the stand-in, never the addon; a real addon problem becomes a known failure and a reported finding).
- [ ] **Step 3:** Scenarios 2 to 6 the same way.
- [ ] **Step 4:** Prove the smoke test can fail: in a scratch copy of the addon (pass an alternate addon directory through an optional `opts.addonDir`), introduce (a) a call to a method that does not exist and (b) a thrown error inside an event handler; confirm each makes the run fail; record the output in the report. Do not commit the broken copies.
- [ ] **Step 5:** Wire into `scripts/test.sh`; total time of check + test under 10 s (report the measured time). `scripts/check.sh && scripts/test.sh` pass. Commit `Tests: stand-in game client and whole-addon smoke test`.

### Task 3: Rule tests for vendor, chat and core

**Files:**
- Create: `tests/features/run.lua` (runs every `*_test.lua` in the folder, prints `Features: N tests, K known failures`), `tests/features/vendor_test.lua`, `tests/features/chat_test.lua`, `tests/features/core_test.lua`
- Modify: `scripts/test.sh`; `tests/lib/fakeclient.lua` only to add world details these tests need

**Interfaces — consumes:** `Client` from Task 2.

Each test: fresh client, feature switched on, a scripted world, an action, an assertion on `c.calls`, `c.chat`, saved values or shown frames. Rules and their sources (read the feature file's comments and `docs/DECISIONS.md` sections "Vendor", "Chat", "General" for exact values):

- **Sell junk** (`Vendor.lua`): sells every grey with a price (assert the exact `(bag, slot)` list); skips an item that is grey in the bag slot but not in the item database, and the reverse; skips locked items and items with no price; skips bags marked ignore-for-junk; sells more than 12 in one visit; pauses while `inCombat` and resumes after; stops when a trade window opens or a spell-target cursor is up; never calls any confirm function; chat line reports the money gained in the "Sold N junk items for Xg Ys Zc." form; nothing happens with the feature off.
- **Repair** (`Vendor.lua`): repairs once when `canRepair` and money ≥ cost, with the "Repairing for ..." line; with money < cost says so once and does not retry that visit; does nothing at a vendor that cannot repair; never uses guild funds; its switch is independent of sell junk.
- **Chat** (`Chat.lua`): targets listed are Say, then Party only when grouped, Raid only in a raid, Guild only in a guild, then the joined channels; no Instance or Officer; whisperers newest first; a seventh pushes out the oldest; a repeat whisperer moves to the front without duplicating; incoming whisper sets the badge, replying to that person clears it, "Clear marks" clears all; a whisper arriving while the picker is open changes the badge but not the listed buttons until it is reopened; during chat lockdown nothing is recorded and nothing errors; tapping a target opens the chat box set to that target (assert on what the feature sets, as the file does it).
- **Core** (`Core.lua`): every feature is off on first install; only a saved `true` enables; new default option keys are added to old saved options without overwriting chosen values; an error thrown in one feature's `OnEnable` marks that feature failed, calls its `OnDisable`, records one error, and other features still enable; an error in an event handler is recorded once per message with a count and does not propagate; at most 30 errors are kept; `/pe reset` restores the round button position and button size; `PE:RunOutOfCombat` defers while in combat and runs once after `PLAYER_REGEN_ENABLED`.

- [ ] **Step 1:** Write `run.lua` and the three files, one rule per named test.
- [ ] **Step 2:** For each failing test decide: stand-in wrong (fix it), test misread the rule (fix the test, citing the source line), or addon wrong (known failure + finding).
- [ ] **Step 3:** For three tests of your choice per file, mutate a scratch copy of the addon to break the rule and confirm the test fails (record which and the output). Do not commit the mutants.
- [ ] **Step 4:** Wire into `scripts/test.sh`. `scripts/check.sh && scripts/test.sh` pass. Commit `Tests: rules for sell junk, repair, chat and the core`.

### Task 4: Rule tests for bags, layout, quest arrow and quest icons

**Files:**
- Create: `tests/features/bags_test.lua`, `tests/features/layout_test.lua`, `tests/features/questarrow_test.lua`, `tests/features/questicons_test.lua`
- Modify: `tests/lib/fakeclient.lua` only for world details these tests need

**Interfaces — consumes:** `Client` (Task 2), `tests/features/run.lua` (Task 3; picks the new files up by name).

Same method and the same mutation step as Task 3. Rules (sources: the feature files' comments; `docs/DECISIONS.md` "Bags", "Layout", "Quest arrow", "Quest icons / data", and the 0.0.6 batch section; `docs/superpowers/specs/2026-11-15-fewer-spots-icon-key-reload.md`):

- **Bags** (`Bags.lua`): the Sort button and L3 call `C_Container.SortBags` only while the bag is open and out of combat; with the Gamepad UI on nothing is written to the `combinedBags` setting; with it off the setting is written only at logout/reload and a reload is requested; the bag scale never goes below the game's own; if the player switched back to separate bags the feature leaves it.
- **Layout** (`Layout.lua`): "Gamepad layout" refuses with a plain message unless the Gamepad UI is on; a switch calls the Edit Mode function once and requests a reload; "back" returns to the layout that was active before; installing over an existing "Handheld" layout needs a second tap within 20 seconds (first tap: no write; second tap at 19 s: write; second tap at 21 s: no write); with no bundled layout it says "No handheld layout saved yet".
- **Quest arrow** (`QuestArrow.lua`), with real QuestieDB data for one multi-spot quest: points at the nearest spot (assert the published `QD:GetArrowPin()` is the nearest by map distance); after the player moves next to a different spot and one second passes, the pin changes; no focused quest → "No quest focused" / "Focus one in your quest log"; focused quest in another zone → "Outside this zone" / "Head to <zone>"; "Turn around" appears above 150 degrees off and goes away below 135; hidden inside an instance; arrow pin is nil after the feature is switched off, after the focus is cleared, and while the position is unknown; nothing ticks when there is nothing to point at.
- **Quest icons** (`QuestIcons.lua`): "Tracked quests" shows the tracker's quests plus the focused one; "Focused quest" shows only the focused one, or the tracker's quests with nothing focused; "All quests" shows all; with "Spots per objective" 5 a many-spot objective draws at most 5 world-map icons per map, plus the arrow's spot when the arrow points at a hidden one; changing to All draws them all (up to the 150 cap); the minimap draws at most 40; hand-in spots outside the minimap radius sit on its rim at 0.6 alpha; the minimap tick is stopped when no shown icon is on the player's map and whenever the feature is off; "Hide blue haze" off after being on requests a reload; tapping an icon shows the text box and a second tap hides it.

- [ ] **Step 1:** Write the four files. **Step 2:** triage failures as in Task 3. **Step 3:** mutation proof, three per file. **Step 4:** `scripts/check.sh && scripts/test.sh` pass, total under 10 s (report the time; if over, move the slowest scenarios behind `scripts/test.sh --full` and say which). Commit `Tests: rules for bags, layout, the quest arrow and quest icons`.

### Task 5: GitHub Action and docs

**Files:**
- Create: `.github/workflows/test.yml`
- Modify: `docs/TESTING.md` ("Offline tests" section), `CLAUDE.md` (Commands), `AGENTS.md` if it mirrors those commands, `README.md` developer section if it lists the test command, `docs/ARCHITECTURE.md` (the paragraph under "Unverified API" that describes the home-made imitation), `PRD.md` (Status: one sentence; Repo layout: the new folders and script)

- Workflow: on `push` and `pull_request`; `ubuntu-latest`; install `luajit` and `unzip` with apt; `actions/checkout@v4`; cache `vendor/` (QuestieDB) and the wow-ui-source clone keyed on the pinned checksum and build string; run `scripts/check.sh`, `scripts/test.sh`, `scripts/audit-api.sh`, then `git diff --exit-code tests/api` so a stale snapshot fails. On Linux the scripts must not rely on macOS-only tools (check `scripts/*.sh` for `stat -f`, `sed -i ''`, `mktemp` forms and BSD-only flags used by the paths the workflow runs; report anything that needs changing in a script outside this task's list rather than changing `scripts/build.sh`).
- Docs: plain language, the owner is a player. Say what each layer catches and what only the device test proves; how to run them; what a known failure is; that nothing here is packaged into the addon.

- [ ] **Step 1:** Write the workflow; validate the YAML parses (`python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/test.yml`) and walk each step for Linux portability. It cannot be run here; say so.
- [ ] **Step 2:** Update the docs. **Step 3:** `scripts/check.sh && scripts/test.sh` pass. Commit `Tests: GitHub Action and docs for the offline suite`.
