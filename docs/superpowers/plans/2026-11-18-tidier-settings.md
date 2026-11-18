# Tidier settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fewer buttons and heading lines in the settings window and setup guide, same saved values.

**Architecture:** Two new row abilities in the shared list drawer (`Settings.lua` `Drawer:Options`): `toggle = true` on a two-choice row, and `get`/`set` on a choices row that stands for more than one saved key. A label column puts headings beside their buttons, falling back to the old stacked layout when the buttons would wrap (drawn, measured, and rewound with `Drawer:Mark`/`Drawer:Rewind`). Features change only their `options` lists.

**Tech Stack:** Lua 5.1 (LuaJIT for tests), WoW interface 16001, no libraries.

**Spec:** `docs/superpowers/specs/2026-11-18-tidier-settings.md`

## Global Constraints

- Interface 16001, no libraries, handlers through `PE:Safe`/`PE:Wrap`.
- Saved keys unchanged: questIcons `map`, `mini`, `hideHaze`; bags `sortKey`, `showTab`, `dpad`, `iconRow`.
- Exact labels from the spec, sections 1, 2 and 4.
- Version 0.6.0 in the TOC and CHANGELOG together.

## Review Focus

- A saved value that matches neither toggle choice (a damaged file): it reads as the first choice and the tap saves the second, so the label always changes; nothing errors.
- `map = false, mini = false` from `/qd`: "Icons on" marks no button and a tap fixes it.
- Old save with `sortKey = "none", showTab = false`: repaired at load.
- Large button size at 720p: rows that do not fit fall back to heading-above, nothing overlaps.
- The d-pad reading order still walks every button once (toggle runs and inline rows).

---

### Task 1: Drawer: toggles, get/set rows, label column

**Files:** Modify `addons/PocketEssentials/Settings.lua` (`Drawer:Options`, `Drawer:CoreChoices`, `PE:NewListDrawer`); Test `tests/features/ui_test.lua`, `tests/features/setup_test.lua` (helpers `textRegion`, `buttonsAfter`, `choiceButtons`, `checkOption` and the press test learn toggles, get/set and same-line headings).

**Produces:** row fields `toggle = true` (two choices), `get = function(mod) -> value`, `set = function(mod, value)`; `Drawer:Mark() -> mark`, `Drawer:Rewind(mark)`.

- [ ] Tests: a toggle row draws one button `"<label>: <choice label>"`, a tap saves the other value and calls OnChange(mod, value); two adjacent toggles share a line; a get/set row marks `get(mod)` and a tap calls `set`; a heading sits on its buttons' line when they fit and above them when they do not (Large size, many choices).
- [ ] Implement; run `scripts/test.sh`.

### Task 2: Quest icons and Bags options

**Files:** Modify `addons/PocketEssentials/QuestIcons.lua` (options list), `addons/PocketEssentials/Bags.lua` (options list, `OnLoad` repair, `Status` text), `addons/PocketEssentials/Setup.lua` (Bags text if it names "Sort key"/"Sort button"); Test `tests/features/questicons_test.lua`, `tests/features/bags_test.lua`.

- [ ] Tests: "Icons on" choices and their writes to `map`/`mini`; "How to sort" choices, writes, binding and tab follow; the bad pair is repaired at load; `hideHaze`, `dpad`, `iconRow` are toggles.
- [ ] Implement; run `scripts/check.sh` and `scripts/test.sh`.

### Task 3: Version and documents

- [ ] TOC 0.6.0, CHANGELOG 0.6.0, PRD status line, `docs/TESTING.md` section 14 device steps.
- [ ] `scripts/build.sh`.
