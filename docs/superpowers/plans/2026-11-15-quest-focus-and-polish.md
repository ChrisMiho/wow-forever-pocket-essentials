# Plan: quest focus and visual polish (0.0.2)

Spec: `docs/superpowers/specs/2026-11-15-quest-focus-and-polish.md`.

Three build tasks touch separate files, so they run in parallel subagents in
the same working tree. Nobody commits until the review passes.

| Task | Spec parts | Files |
|---|---|---|
| 1. Art and discs | E, F | `scripts/make_art.py`, `addons/PocketEssentials/Icons/{arrow,circle,blank}.tga`, `UI.lua` (`CreateDisc`) |
| 2. Focus data and arrow | A (QuestData side), B | `QuestData.lua`, `QuestArrow.lua`, `tests/questiedb/stubs.lua` if the harness needs new stand-ins |
| 3. Icon filter and haze | A (tap behaviour), C, D | `QuestIcons.lua` |

Shared interface fixed up front (task 2 provides, task 3 uses):

- `QD:GetTrackedQuest()` → focused quest ID or nil.
- `QD:GetWatchedQuests()` → array of quest IDs (may be empty, never nil;
  read only; may be a reused table).
- `"tracked"` callback on focus change; `"quests"` callback on
  `QUEST_WATCH_LIST_CHANGED`.
- Texture paths: `Interface\AddOns\PocketEssentials\Icons\arrow`, `circle`,
  `blank`.

Then:

4. Review against the spec (fresh subagent), fix findings.
5. Docs: PRD status and goal coverage, `docs/TESTING.md` step 2/3 updates,
   `docs/ARCHITECTURE.md` unverified rows, `docs/DECISIONS.md`, CHANGELOG,
   TOC version 0.0.2, README if it describes tap-to-pick.
6. `scripts/check.sh`, `scripts/test.sh`, `scripts/build.sh`; commit; push
   `release-prep`; GitHub pre-release `v0.0.2` with the bundle zip (as for
   v0.0.1). No CurseForge upload.
