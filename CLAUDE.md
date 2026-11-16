# Commands
- `scripts/check.sh`: LuaJIT syntax check of every file in the TOC, plus a wording check on comments. About 0.1 s.
- `scripts/test.sh`: offline tests: API fast check, QuestieDB harness, feature rule tests, whole-addon smoke test (`tests/`, `docs/TESTING.md`).
- `scripts/audit-api.sh`: full API audit against Blizzard's source (clones it once); about 45 s; rewrites `tests/api/*.txt`. Run it after adding a game call.
- `scripts/build.sh`: builds the release zips (GitHub bundle and CurseForge) into `dist/`.
- `python3 scripts/make_art.py`: regenerates the CurseForge art.
- Both check and test exit 0 with a notice when luajit is missing (`brew install luajit`).

# Workflow
- Read PRD.md first, including its working rules.
- Spec-driven (PRD.md rule 7): brainstorm, then a spec at `docs/superpowers/specs/<date>-<feature>.md` that the owner approves,
  then a plan in `docs/superpowers/plans/`, then a subagent-driven build reviewed against the spec, then the owner's device test.
- One roadmap item at a time. Stop after each for the owner's device test.
- Never upload to CurseForge and never push without the owner.
- A Stop hook (`.claude/settings.json`) runs check and test and blocks the turn from ending if either fails.

# Conventions
- Interface 16001 and the modern API. Classic Era 1.x addons do not load.
- No libraries in the addon.
- Event handlers and callbacks go through `PE:Safe` or `PE:Wrap`.
- Nothing ticks while its feature is off.
- Features default off until device-tested.
- Semantic versioning. Bump the TOC `## Version` and add a CHANGELOG entry together.
- Verify every new API in `github.com/Gethe/wow-ui-source`, branch `forever`, and log unverified ones in `docs/ARCHITECTURE.md`.

# Skills
- Reusable procedures (API checks, offline harness, device-test handoff, CurseForge release) come from the `wow-addon-skills` plugin: https://github.com/ChrisMiho/wow-addon-skills

# Gotchas
- The client's internal name is "Camelot".
- The QuestieDB folder name must stay exactly `QuestieDB`.
- There is no game client off the device, so tests prove logic, not behaviour.
- The owner is a player, not an addon developer. Explain in plain language.
