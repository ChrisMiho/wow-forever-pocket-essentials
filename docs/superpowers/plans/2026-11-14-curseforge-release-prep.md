# CurseForge Release Prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put Pocket Essentials into a clean, public "in progress" state. That covers:
- restated goals, and a check that the PRD is covered by code
- QuestieDB 1.1.1, guarded by an offline test against its real data
- best-practice agent setup: a short CLAUDE.md, a check command, and a Stop hook
- docs for humans
- a GPL-3.0 licence
- a CurseForge-only zip, plus every image and piece of page text the CurseForge form needs
- a reusable `wow-addon-skills` Claude Code plugin in its own repo

**Nothing gets uploaded to CurseForge.**

**Architecture:**
- **Docs and packaging.** PRD.md becomes the product spec: vision, goals, status and roadmap. Its detailed sections move verbatim into `docs/`.
- **Offline test.** A LuaJIT harness under `tests/` loads the pinned QuestieDB through its own loading code, using stand-ins for the WoW API (stubs), then runs every quest through our `QuestData.lua`.
- **Checks.** `scripts/check.sh` (syntax) and `scripts/test.sh` (QuestieDB) are the agents' pass/fail checks, and a Stop hook enforces them.
- **Build.** `scripts/build.sh` also produces a zip holding only PocketEssentials, for CurseForge.
- **Plugin.** The skills that come out of this work go into a separate plugin and marketplace repo.

**Tech Stack:**
- Lua 5.1 (WoW addon, interface 16001); LuaJIT 2.1 from Homebrew for checks and tests
- bash
- Python 3 with Pillow 11 (art)
- LibDeflate (pure Lua, zlib licence), test-only, never shipped
- Claude Code plugin format (`.claude-plugin/marketplace.json`, `plugin.json`, `skills/*/SKILL.md`)

**Spec:** `PRD.md` (current version, commit 10ee856), the owner decisions under Global Constraints (from the 2026-11-14 planning conversation), and <https://code.claude.com/docs/en/best-practices>.

## Global Constraints

**Owner decisions**
- **Licence:** **GPL-3.0** for our code. `Icons/MIT.txt` (pfQuest, Shagu) stays as it is.
- **Prepare only, no upload.** No task creates the CurseForge project, uploads a file, adds `.pkgmeta`, or adds a CurseForge GitHub Action.
- **Framing:** the project exists **to help anyone playing WoW Forever on a handheld**. Dev notes may say the reference test device is a Retroid Pocket 6 running Droid Deck.
  - No faction mentions.
  - No "the owner" wording in README, CurseForge copy or code comments. "The owner" stays only in PRD.md's working rules and in CLAUDE.md, where it means the maintainer.
- **Status everywhere:** **"In progress: version 0.1.0 is written but has not run on a device yet."** No doc may claim a feature works.
- **Pace:** stop at every 🛑 and wait for the owner (PRD rule 1). Gaps the audit finds are reported, not built.
- **Version:** the addon becomes `0.1.0`. TOC, CHANGELOG and CurseForge zip name must agree.

**QuestieDB**
- **Pin 1.1.1:**
  - Forever zip SHA-256 `2527118d861e497fa40bdb6d061883bf09649d5f96e09de6885f578aefbb5e59`
  - contract 4
  - 5,914 quests
  - 37 MB unpacked
  - `src/*.lua` byte-identical to 1.1.0
  - the `_Forever`/`_Camelot` TOC files are still byte-identical copies, so keep both
- **Loading off the device needs these stubs:**
  - `C_AddOns.GetAddOnMetadata` (parsed from the TOC)
  - `C_EncodingUtil.DecodeBase64`, `.DecompressString(s, 1)` (zlib, bytes start `78 9c`), and `.DeserializeCBOR` (byte strings, mixed number and `"p"` keys, floats)
  - `UnitFactionGroup` and `UnitClassBase`
  - optional `GetLocale`
  - files loaded in TOC order with `(ADDON_NAME, ns)` varargs
- **What our code uses:**
  - `LibQuestieDB` and `RequireContract`
  - `Quest`, `Npc`, `Object`, `Item` with `Exists`
  - Quest `finishedBy`, `triggerEnd`, `objectives`, `extraObjectives`
  - Npc `spawns`, `name`; Object `spawns`; Item `npcDrops`, `objectDrops`
  - `Support.Get("ZoneDB").private` → `areaIdToUiMapId`, `areaIdToUiMapIdOverride`, `dungeons`

**CurseForge** (research, 2026-11-14)
- flavor **"Forever"**, game version **1.60.1**
- QuestieDB project `questiedb`, ID **1696795**
- avatar **400×400 PNG**: not a single solid colour, no Blizzard art, not WebP
- description in Markdown
- one main category plus up to 4 others
- zip must not contain `__MACOSX`, `.DS_Store`, nested zips or non-English filenames

**Agent practice** (best-practices page)
- CLAUDE.md holds only what agents can't learn from the repo: commands, gotchas, decisions, workflow. No architecture tour. Under 80 lines.
- Procedures go in skills.
- Zero-exception rules go in hooks.
- Workflow is spec-driven: PRD = product spec. A new feature goes brainstorm → `docs/superpowers/specs/<date>-<feature>.md` → plan in `docs/superpowers/plans/` → subagent-driven build with a review against the spec → device test.

**Git**
- No history rewrite needed: all commits use a noreply address, and a scan found no personal details.
- Branch `release-prep` from `build-v1`.
- The plugin lives in a new sibling repo `/Users/chrismiho/Coding/wow-addon-skills`. 🛑 before `gh repo create` or any push.

**Credits:** **QuestieDB and the Questie team** (GPL-3.0, <https://github.com/Questie/QuestieDB>, <https://www.curseforge.com/wow/addons/questiedb>); **pfQuest by Shagu** (icons, MIT); LibDeflate credited in `tests/lib/` only.

## Review Focus

1. **QuestieDB updates and changes shape.** The CurseForge app installs the newest QuestieDB, not our pin. Users expect the quest rows to say why they're off rather than throw errors.
   - Task 5 runs every quest through our code and fails on any `LogError`.
   - Task 5 also includes a mutation check: a broken field name must make the harness fail.
   - Task 9's README states the "turns off and says why" behaviour.
2. **A CurseForge user installs without QuestieDB.** Task 5's harness adds a "no LibQuestieDB" case: `QD:Acquire()` returns false with a reason string, and nothing errors.
3. **CurseForge rejects the zip.** Task 7 asserts no `.DS_Store`, `__MACOSX` or nested zip.
4. **Version drift** between TOC, CHANGELOG and zip name. Task 7's test compares all three.
5. **A doc claims something works, or drops the old-QuestDots step.** Task 9 greps for the status line and for `QuestDots`.

---

### Task 1: Licence, addon metadata, neutral wording in code

**Files:**
- Create: `LICENSE`
- Modify: `addons/PocketEssentials/PocketEssentials.toc`
- Modify: comments at `Bags.lua:208`, `Chat.lua:5,126`, `Hub.lua:113`, `Layout.lua:51,301,438,579`, `QuestData.lua:70,720`, `Vendor.lua:7`

**Interfaces:**
- Produces: TOC `## Version: 0.1.0` (read by Tasks 7 and 9).

- [ ] **Step 1: Write the failing check.** Run:
```bash
head -1 LICENSE 2>/dev/null | grep -q "GNU GENERAL PUBLIC LICENSE" \
 && grep -q '^## Version: 0.1.0$' addons/PocketEssentials/PocketEssentials.toc \
 && grep -q '^## X-License: GPL-3.0$' addons/PocketEssentials/PocketEssentials.toc \
 && ! grep -rn -i -E '\bthe owner\b|owner.s\b|owner chose|owner changed|owner first' addons/PocketEssentials/*.lua \
 && echo PASS
```
Expected: no output.
- [ ] **Step 2: Fetch the licence.** Run `curl -fsSL https://www.gnu.org/licenses/gpl-3.0.txt -o LICENSE`.
- [ ] **Step 3: Edit the TOC.**
  - `## Version: 0.1.0`
  - Add `## Author: ChrisMiho`, `## X-License: GPL-3.0` and `## X-Website: https://github.com/ChrisMiho/wow-forever-pocket-essentials`.
  - `## Notes: Handheld-friendly helpers for WoW Forever: quest icons, a quest arrow, one big bag, auto sell junk and repair, and big chat buttons. Each feature has its own on/off switch.`
- [ ] **Step 4: Reword the comments.** Replace "the owner" with "the player" in the listed comments only. `KeyOwner`, `navOwner` and `label.owner` are code; leave them alone.
- [ ] **Step 5: Run the check from Step 1.** Expected: `PASS`.
- [ ] **Step 6: Commit.** Message: `Add GPL-3.0 licence, 0.1.0 metadata, neutral comment wording`.

### Task 2: Restate the goals and split PRD.md 🛑

**Files:**
- Modify: `PRD.md`
- Create: `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, `docs/TESTING.md`

**Interfaces:**
- Produces the doc map that later tasks link to:
  - `PRD.md`: rules, vision, goals, status, roadmap, parked ideas
  - `docs/ARCHITECTURE.md`: structure, safety net, unverified API, verified facts
  - `docs/DECISIONS.md`: decisions made without the owner, and what was left out
  - `docs/TESTING.md`: device test plan, steps 0–9

- [ ] **Step 1: Move sections verbatim.**
  - PRD "Structure", "Unverified API" and "Facts" go to `docs/ARCHITECTURE.md`.
  - "Decisions made without the owner" and "What was left out, and why" go to `docs/DECISIONS.md`.
  - "Roadmap — device test plan" goes to `docs/TESTING.md`.
  - Each new file opens with one line saying what it holds and "Goals live in PRD.md".
  - In `docs/ARCHITECTURE.md` Facts, update the QuestieDB lines to the 1.1.1 values from Global Constraints.
- [ ] **Step 2: Rewrite `PRD.md` with this order and these headings:**
  1. "How to work in this repo": rules 1–6, plus rule 7: "Spec-driven: new features start as a spec in `docs/superpowers/specs/`, approved by the owner, before any plan or code." Delete the "suspended once" paragraph.
  2. "Vision", two or three sentences: comfortable WoW Forever on any handheld (touch plus controller), light on performance, no precise taps or typed commands. Performance and user experience come before new features.
  3. "Who it's for": handheld players on any device that runs the client. Dev note: the reference test device is a Retroid Pocket 6, 12 GB, Droid Deck, 720p.
  4. "Reference setup": the current table, minus the "Owner's faction" row.
  5. Goals 1–6, Non-goals, "What would make this a failure": unchanged apart from owner-to-player wording.
  6. "Deliverable": add "CurseForge: PocketEssentials alone, QuestieDB as a required dependency (project 1696795). GitHub zip: both folders, QuestieDB pinned at 1.1.1."
  7. "Status": the Global Constraints status line, plus the Current-state table (with the QuestieDB row updated to 1.1.1) and a pointer to `docs/TESTING.md`.
  8. "Roadmap", in four phases: (a) device testing; (b) performance and user-experience polish from the results; (c) first CurseForge upload as an Alpha, using `curseforge/FIELDS.md`; (d) new features, parked until (b) is done.
  9. "Parked ideas": faction builds, Improved Forever radial wheels, a bundled handheld layout, the arrow across zones, plus "Owner has more ideas; add them here as one line each, then spec before building."
  10. "Repo layout": updated for all files this plan adds.
- [ ] **Step 3: Verify.**
  - `grep -n -i faction PRD.md` should show only the parked item and the Deliverable "later" line.
  - `grep -c '^## ' docs/*.md` should show more than 0 for each file.
- [ ] **Step 4: Commit.** Message: `Restate goals for all handheld players; split PRD into docs/`.
- [ ] **Step 5: 🛑 Owner checkpoint.** Show Vision, Who it's for, Roadmap, Parked ideas and rule 7. Wait for approval or edits.

### Task 3: PRD coverage audit 🛑

**Files:**
- Modify: `PRD.md` (Status table)

- [ ] **Step 1: Map Goals 1–6 to code.** For each bullet, add a "Where" column (`File.lua` plus function) and a "Built" column (Yes, Partial or No, with a one-line reason). One row per bullet.
- [ ] **Step 2: Verify each cited function exists.** For every row, run `grep -n "<function>" addons/PocketEssentials/<File>.lua` and expect a hit.
- [ ] **Step 3: Commit.** Message: `PRD: map each goal to the code that implements it`.
- [ ] **Step 4: 🛑 Owner checkpoint.** List every Partial or No row in plain language. Build nothing. The owner decides parked versus roadmap.

### Task 4: Tooling, LuaJIT check, QuestieDB 1.1.1 pin

**Files:**
- Create: `scripts/check.sh`, `scripts/fetch-questiedb.sh`
- Modify: `scripts/build.sh`

**Interfaces:**
- Produces:
  - `scripts/fetch-questiedb.sh`: downloads (cached in `vendor/`), verifies the SHA-256, and prints the zip path. It holds the only copy of `QUESTIEDB_VERSION` and `QUESTIEDB_SHA256`.
  - `scripts/check.sh`: exits 0 when every TOC-listed Lua file compiles under LuaJIT and no comment uses owner wording.

- [ ] **Step 1: Install LuaJIT.** Run `brew install luajit && luajit -v`. Expected: `LuaJIT 2.1.…`.
- [ ] **Step 2: Write `scripts/check.sh`.**
  - Same TOC parsing as `build.sh`.
  - For each file, run `luajit -e 'assert(loadfile(arg[1]))' "$f"`.
  - Then the owner-wording grep from Task 1.
  - Exit non-zero naming the first failure; print `All Lua files compile.` on success.
  - If `luajit` is missing, print `luajit not installed (brew install luajit); skipping` to stderr and exit 0, so a contributor without it isn't locked out by the Stop hook.
- [ ] **Step 3: Show it fails, then passes.** Run `printf 'local x = \n' > "$TMPDIR/bad.lua" && luajit -e 'assert(loadfile(arg[1]))' "$TMPDIR/bad.lua"`. Expected: non-zero, with an `unexpected symbol` error. Then run `scripts/check.sh`. Expected: `All Lua files compile.`
- [ ] **Step 4: Move the pin into `scripts/fetch-questiedb.sh` at 1.1.1** (SHA from Global Constraints). `build.sh` calls it instead of its inline fetch. Comments still explain the Forever/Camelot TOC choice.
- [ ] **Step 5: Verify.** Run `scripts/build.sh`. Expected: the output lists `QuestieDB` and `unzip -p dist/wow-forever-pocket-essentials.zip QuestieDB/QuestieDB_Forever.toc | grep -m1 '^## Version'` shows `1.1.1`.
- [ ] **Step 6: Commit.** Message: `Pin QuestieDB 1.1.1; add LuaJIT check script and shared fetch`.

### Task 5: Offline QuestieDB test harness 🛑

**Files:**
- Create: `scripts/test.sh`, `tests/questiedb/stubs.lua`, `tests/questiedb/decode.lua`, `tests/questiedb/harness.lua`, `tests/questiedb/baseline.txt`, `tests/lib/LibDeflate.lua`, `tests/lib/README.md` (source URL, version, licence)

**Interfaces:**
- Consumes: `scripts/fetch-questiedb.sh` (Task 4); the QuestieDB surface listed in Global Constraints; `QuestData.lua`'s `QD:Acquire()` and `QD:GetPinsForQuest(id)` (confirm the exact names in `QuestData.lua` before writing the harness, and use what is there).
- Produces: `scripts/test.sh`, which exits 0 on pass, prints a one-line summary (`QuestieDB 1.1.1: 5914 quests, N with pins, 0 errors`), and exits 1 with the first failing quest ID and error.

- [ ] **Step 1: Check upstream first.** Look for `emulator/metadata.lua` and `emulator/client.lua` in the QuestieDB GitHub repo, referenced at `baked.lua:19`. If they provide TOC metadata and `C_EncodingUtil` stand-ins under a licence compatible with GPL-3.0, vendor them under `tests/lib/` instead of writing `decode.lua`. Note the choice in `tests/lib/README.md`.
- [ ] **Step 2: Write the harness assertions first, in `harness.lua`:**
  - `LibQuestieDB.RequireContract(4) == true`
  - every ID from `LibQuestieDB.Quest.GetAllIds()` passes through our code in two passes, "in log, not complete" and "complete", with zero Lua errors and zero `PE:LogError` calls
  - quest count and with-pins count equal `baseline.txt` (print the difference on mismatch)
  - a run with `LibQuestieDB = nil` makes `QD:Acquire()` return false with a non-empty reason, with no error
- [ ] **Step 3: Run `scripts/test.sh` before the stubs exist.** Expected: FAIL, pointing at a missing stub or decoder.
- [ ] **Step 4: Implement the stubs and decoders.**
  - `stubs.lua`: the WoW API stand-ins from Global Constraints, plus a stub `C_QuestLog` that holds exactly the quest under test, and the `PE` core loaded from `Core.lua`.
  - `decode.lua`: base64 and CBOR (IEEE754 floats by hand); zlib via `LibDeflate:DecompressZlib`.
  - `test.sh` unzips the pinned zip into `$TMPDIR` and runs `luajit tests/questiedb/harness.lua <qdb dir> <repo root>`.
- [ ] **Step 5: First full run.** Write the observed counts into `baseline.txt`, then rerun. Expected: PASS. Record the runtime in seconds.
- [ ] **Step 6: Mutation check.**
  - In a scratch copy of `QuestData.lua`, rename the `objectives` field read to `objectivez`.
  - Point the harness at the copy. Expected: FAIL.
  - Delete the copy. Do not commit it.
- [ ] **Step 7: Commit.** Message: `Add offline QuestieDB harness: every quest through QuestData under stubs`.
- [ ] **Step 8: 🛑 Owner checkpoint.** Report the summary line, the runtime, how many quests have no pins, and the mutation result.

### Task 6: Agent setup: CLAUDE.md, Stop hook, architecture how-to

**Files:**
- Create: `CLAUDE.md`, `AGENTS.md`, `.claude/settings.json`
- Modify: `docs/ARCHITECTURE.md`, `.gitignore` (add `CLAUDE.local.md`)

**Interfaces:**
- Consumes: `scripts/check.sh` and `scripts/test.sh` (Tasks 4 and 5); the `PE` API in `Core.lua`: `RegisterModule(def)` (read `Core.lua:553-660` for the def fields), `Safe`, `Wrap`, `RunOutOfCombat`, `RegisterCoreEvent`, `LogError`, `OnLogin`.

- [ ] **Step 1: Write `CLAUDE.md`, under 80 lines, with sections `# Commands`, `# Workflow`, `# Conventions`, `# Gotchas`.**
  - **Commands:** `scripts/check.sh`, `scripts/test.sh`, `scripts/build.sh`, `python3 scripts/make_art.py`.
  - **Workflow:**
    - Read PRD.md and its rules first.
    - Spec-driven flow from Global Constraints.
    - One roadmap item at a time; stop for the owner's device test.
    - Never upload to CurseForge or push without the owner.
  - **Conventions:**
    - Interface 16001 and the modern API; Classic Era 1.x addons don't load.
    - No libraries in the addon.
    - Handlers go through `PE:Safe` or `PE:Wrap`.
    - Nothing ticks while its feature is off.
    - Features default off until device-tested.
    - Verify every new API in `github.com/Gethe/wow-ui-source`, branch `forever`, and log unverified ones in `docs/ARCHITECTURE.md`.
  - **Gotchas:**
    - The client's internal name is "Camelot".
    - The QuestieDB folder name must stay exactly `QuestieDB`.
    - There is no game client off the device, so tests prove logic, not behaviour.
    - The owner is a player, not an addon developer; explain in plain language.
  - **Point to the plugin:** "Reusable procedures: the `wow-addon-skills` plugin." Add this line only after Task 11 lands.
- [ ] **Step 2: Write `AGENTS.md`** as one line: `See CLAUDE.md.`
- [ ] **Step 3: Write `.claude/settings.json` with a Stop hook.**
  - If the Task 5 runtime is 20 seconds or less, run `scripts/check.sh 1>&2 && scripts/test.sh 1>&2 || exit 2`.
  - Otherwise run only `scripts/check.sh 1>&2 || exit 2`, and have `build.sh` run `test.sh`.
- [ ] **Step 4: Verify the hook.**
  - Break a Lua file temporarily (append `local x =`), start `claude -p "say hi"` in the repo, and confirm the turn is blocked with the compile error.
  - Revert the file and confirm the next run ends normally.
- [ ] **Step 5: Add "Adding a feature" to `docs/ARCHITECTURE.md`.** Cover the `RegisterModule` fields and lifecycle, default off, the TOC entry, the Settings row appearing automatically, the tick budget, and running check and test.
- [ ] **Step 6: Commit.** Message: `Add CLAUDE.md, Stop hook enforcing check/test, feature how-to`.

### Task 7: CurseForge zip from the build

**Files:**
- Modify: `scripts/build.sh`

**Interfaces:**
- Produces: `dist/PocketEssentials-<version>.zip` alongside `dist/wow-forever-pocket-essentials.zip`.

- [ ] **Step 1: Write the failing check:**
```bash
scripts/build.sh && v=$(sed -n 's/^## Version: //p' addons/PocketEssentials/PocketEssentials.toc | tr -d '\r') \
 && z=dist/PocketEssentials-$v.zip && test -f "$z" \
 && [ "$(unzip -Z1 "$z" | cut -d/ -f1 | sort -u)" = "PocketEssentials" ] \
 && ! unzip -Z1 "$z" | grep -E '__MACOSX|\.DS_Store|\.zip$' \
 && grep -q "## \[$v\]" CHANGELOG.md && echo PASS
```
Expected: FAIL.
- [ ] **Step 2: Extend `build.sh`.**
  - Run `scripts/check.sh` before staging (and `scripts/test.sh` if Task 6 moved it here).
  - Zip `$stage/PocketEssentials` alone into `dist/PocketEssentials-$version.zip` with `-x '*.DS_Store' '__MACOSX/*'`.
  - Print both zips with sizes.
- [ ] **Step 3: Run the check without its `CHANGELOG` clause.** Expected: `PASS`. The full check runs again at the end of Task 9.
- [ ] **Step 4: Commit.** Message: `Build a PocketEssentials-only zip for CurseForge`.

### Task 8: Artwork 🛑

**Files:**
- Create: `scripts/make_art.py`, `curseforge/avatar.png` (400×400), `curseforge/banner.png` (1280×640: README header and GitHub social preview)

- [ ] **Step 1: Write the failing check.** Run:
```bash
python3 -c "from PIL import Image; a=Image.open('curseforge/avatar.png'); b=Image.open('curseforge/banner.png'); assert a.size==(400,400) and a.format=='PNG'; assert b.size==(1280,640) and b.format=='PNG'; assert len(a.convert('RGB').getcolors(1<<20) or [0,0])>1; print('PASS')"
```
Expected: FileNotFoundError.
- [ ] **Step 2: Write `make_art.py`.** Pillow only, original art only.
  - Echo the in-game hub button: a dark disc with a gold ring and "PE", on a deep blue-to-teal gradient, with simple handheld line art behind it.
  - Banner: the mark on the left; "Pocket Essentials" plus "Handheld helpers for WoW Forever" on the right.
  - Font: `/System/Library/Fonts/Supplemental/Arial Bold.ttf`, falling back to `ImageFont.load_default(size=…)`.
- [ ] **Step 3: Run the script, then the check from Step 1.** Run `python3 scripts/make_art.py`. Expected: `PASS`.
- [ ] **Step 4: Commit.** Message: `Add generated CurseForge avatar and banner`.
- [ ] **Step 5: 🛑 Owner checkpoint.** Show both images and iterate until approved.

### Task 9: Human docs on GitHub

**Files:**
- Modify: `README.md`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write `CHANGELOG.md`** in Keep-a-Changelog format: `## [0.1.0] - Unreleased`, with the seven features under "Added (untested on device)" and "QuestieDB 1.1.1" under Dependencies.
- [ ] **Step 2: Rewrite `README.md` in this order:**
  1. Banner.
  2. Pitch.
  3. Status callout with the exact line.
  4. Who it's for.
  5. Features table.
  6. Install: (a) CurseForge, "coming later", where QuestieDB installs as a dependency; (b) from GitHub, with the bundle steps, keeping "delete any old QuestDots folder".
  7. "Without QuestieDB, or with a version this addon doesn't understand": the quest rows stay off and say why.
  8. Using it: the round button, long-press, `/pe`, Errors page.
  9. For developers: `scripts/check.sh`, `scripts/test.sh`, `scripts/build.sh`, and the spec-driven workflow.
  10. Project docs table.
  11. Feedback: GitHub issues.
  12. Credits & thanks: the Questie team, thanked for making the quest database available for other addons to build on, with both links; Shagu for the icons.
  13. Licence: GPL-3.0.
- [ ] **Step 3: Verify.** Run:
```bash
grep -q 'In progress: version 0.1.0 is written but has not run on a device yet' README.md \
 && grep -q QuestDots README.md && grep -q Questie README.md && grep -q Shagu README.md \
 && ! grep -n -i -E '\bthe owner\b|horde' README.md && echo PASS
```
Then rerun the full Task 7 check. Expected: `PASS` both times.
- [ ] **Step 4: Commit.** Message: `Rewrite README for handheld players; add CHANGELOG`.

### Task 10: CurseForge page material

**Files:**
- Create: `curseforge/summary.txt`, `curseforge/description.md`, `curseforge/FIELDS.md`

- [ ] **Step 1: Write `summary.txt`.** At most 120 characters (the CurseForge limit is unconfirmed). Draft: `Big, touch- and controller-friendly helpers for playing WoW Forever on a handheld.`
- [ ] **Step 2: Write `description.md`.**
  - Banner first, with a note in FIELDS.md to upload it to the Images tab and re-link it.
  - Early-alpha status; testers wanted.
  - Who it's for.
  - Features.
  - "Requires QuestieDB for quest features", with the link.
  - Opening settings; reporting problems (GitHub issues, Errors page).
  - Credits & thanks.
  - Licence.
- [ ] **Step 3: Write `FIELDS.md`**, with every value for the project form:
  - Name `Pocket Essentials`, the summary, the avatar path.
  - Main category "Map & Minimap"; additional "Quests & Leveling", "Bags & Inventory", "Chat & Communication", and the closest fourth. Mark these "confirm names in the form".
  - Licence GPL-3.0; source and issues URLs; description in Markdown mode.
  - File: `dist/PocketEssentials-0.1.0.zip`, flavor Forever, 1.60.1, **Alpha**, changelog from CHANGELOG.
  - Relation: QuestieDB 1696795, **Required**.
  - After creation, add `## X-Curse-Project-ID: <id>` to the TOC.
  - A screenshot to-do list for the device: settings window, map icons, arrow, bag plus Sort, chat picker.
  - "Upload only after device testing (PRD roadmap phase c)."
- [ ] **Step 4: Verify.** Run:
```bash
[ $(wc -m < curseforge/summary.txt) -le 121 ] && grep -q questiedb curseforge/description.md \
 && grep -q 1696795 curseforge/FIELDS.md && grep -q avatar.png curseforge/FIELDS.md \
 && ! grep -rn -i -E '\bthe owner\b|horde' curseforge/description.md curseforge/summary.txt && echo PASS
```
Expected: `PASS`.
- [ ] **Step 5: Commit.** Message: `Add CurseForge summary, description and form checklist`.

### Task 11: `wow-addon-skills` plugin repo 🛑

**Files** (new repo `/Users/chrismiho/Coding/wow-addon-skills`):
- `.claude-plugin/marketplace.json` (name `chrismiho-wow-addons`, owner `ChrisMiho`, one entry `wow-addon-skills` with source `./plugins/wow-addon-skills`)
- `plugins/wow-addon-skills/.claude-plugin/plugin.json` (name `wow-addon-skills`, version `0.1.0`, licence GPL-3.0)
- `plugins/wow-addon-skills/skills/<name>/SKILL.md` for the four skills below
- `README.md`, `LICENSE`
- In this repo: modify `.claude/settings.json` (`extraKnownMarketplaces` pointing to `ChrisMiho/wow-addon-skills`, and `enabledPlugins` `wow-addon-skills@chrismiho-wow-addons: true`) and add the CLAUDE.md pointer line.

**Skills.** Each holds only what an agent can't learn from a repo, stays under 150 lines, and puts long reference material in supporting files:

| Skill | Invocation | Content |
|---|---|---|
| `wow-api-verify` | model | How to confirm an API for a client flavor in Gethe/wow-ui-source (branch per flavor: `forever`, `classic_era`, `live`…); guard patterns (`type(x)=="function"`, `pcall`); record unverified APIs with their worst case. Generic; mentions no project names |
| `addon-offline-harness` | model | How to run addon Lua under LuaJIT with WoW API stubs and load another addon from its TOC. Ships `stubs.lua`, `decode.lua` and the LibDeflate notice as supporting files (copied from this repo's Task 5, generalised: addon name and paths become arguments). `questiedb.md` covers the QuestieDB-specific surface |
| `device-test-handoff` | model | After a game-affecting change: build the zip, write numbered "do this, look for that" steps in plain language, ask for the in-game error log, then stop and wait. No claim of "works" before the report |
| `curseforge-release` | `disable-model-invocation: true` | Release checklist: flavor and game-version IDs, avatar spec, zip hygiene, relations, `X-Curse-Project-ID`, changelog, and Alpha/Beta/Release meaning. Never uploads; the final step is a hand-off to the human |

- [ ] **Step 1: Scaffold the repo and manifests.** Run `git init`. Write the two JSON files.
- [ ] **Step 2: Write the four skills.** Descriptions put the use case first and include phrases a user would say (e.g. "is this API available on Forever", "test against QuestieDB offline", "ready to test on my device", "release to CurseForge").
- [ ] **Step 3: Validate.** Run `claude plugin validate .` and `claude plugin validate ./plugins/wow-addon-skills`. Expected: `✔ Validation passed` for both.
- [ ] **Step 4: Install locally and smoke-test.**
  - Run `claude plugin marketplace add /Users/chrismiho/Coding/wow-addon-skills`, then `claude plugin install wow-addon-skills@chrismiho-wow-addons`, then `claude plugin details wow-addon-skills`. Expected: `Skills (4)`.
  - In this repo, run `claude -p "Is C_QuestLog.GetInfo available on WoW Forever? Use the relevant skill."`. Expected: the answer cites the `forever` branch of wow-ui-source.
- [ ] **Step 5: Commit** in the plugin repo. Message: `wow-addon-skills 0.1.0: four addon-development skills`.
- [ ] **Step 6: 🛑 Owner checkpoint.** Ask before `gh repo create ChrisMiho/wow-addon-skills --public` and the push. Only after both, add the `.claude/settings.json` marketplace entries and the CLAUDE.md pointer here, then commit `Enable wow-addon-skills plugin for this project`.
