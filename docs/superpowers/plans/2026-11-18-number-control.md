# Number control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spots, Merge and Chat text size become one joined – number + control. Quest icons gain Extra small, the arrow gains Small, and Hide blue haze moves down. Every saved value is unchanged.

**Architecture:**
- **New item in `Drawer:Flow`:** an item `{ box = { text, unit, down, up } }` draws the joined control. It has the same width rules as any other item, so `LabeledRow` places its heading beside it unchanged.
- **Two row kinds use it:**
  - `number = { min, max, default, unit, all, allLabel, offLabel }` steps a saved key.
  - `stepper = function(mod) -> box` lets a feature step its own value (Chat).

**Tech Stack:** Lua 5.1 (LuaJIT tests), interface 16001, no libraries.

**Spec:** `docs/superpowers/specs/2026-11-18-number-control-design.md`

## Global Constraints

- Handlers through `PE:Wrap`/`PE:Safe`; widgets pooled through the drawer (`AddPool`/`Acquire`), so `Mark`/`Rewind` still work.
- Saved keys unchanged: questIcons `spots` (0 = All), `cluster`, `size`; questArrow `size`.
- **Exact values:** Spots 1–20 then All; Merge 0–10, with "Off" at 0; Extra small 18 px on the map and 11 px on the minimap; Small arrow 56 px.
- **Unit words:** "spots", "merge" and "text size".
- **Version:** 0.7.0, in the TOC and CHANGELOG together.

## Review Focus

- **Saved spots of 3, 5, 10 or 0:** each shows as itself; – from All goes to 20.
- **Saved cluster of 15 (from an older `/qd`) or a string:** shows the default (2). A press steps from 2, and nothing errors.
- **A dimmed end pressed:** it saves nothing and does not run OnChange, but still redraws.
- **The d-pad:** it visits – then + once each per control. The middle is never a stop.
- **Large button size, narrow window:** the box falls back to heading-above, and the joined pieces never split across lines.

---

### Task 1: Drawer number control

**Files:**
- Modify: `addons/PocketEssentials/UI.lua` (STYLES: `step`, `stepDim`).
- Modify: `addons/PocketEssentials/Settings.lua`:
  - a new "well" pool in `PE:NewListDrawer`;
  - the `box` item in `Flow`;
  - the `number` and `stepper` rows in `Options`;
  - the doc comment.
- Test: `tests/features/ui_test.lua` and `tests/features/setup_test.lua` (helpers learn number rows).

**Produces:**
- Row `{ key, label, number = { min, max, default, unit, all = <value after max>, allLabel = "All", offLabel = "Off" (shown at 0) }, OnChange }`.
- Row `{ label, value = fn, stepper = function(mod) -> { text, unit, down = fn|nil, up = fn|nil } or nil, always }`.
- **Box layout:**
  - **Ends:** two buttons, each `M.button` wide, labelled "-" and "+". Style `step`, or `stepDim` when that side has no further step; a dimmed end saves nothing.
  - **Middle:** a well, `M.button * 2.2` wide, gold border, dark fill. The value is gold ("font"). The unit word is grey ("small") under it, and is dropped when the two lines do not fit in `M.button`.

- [ ] **Tests (ui_test):**
  - a number row draws "-", a well text equal to the saved value, and "+" on one line, with "-" then "+" in navList;
  - "+" saves value+1 and calls OnChange(mod, value+1);
  - at max with `all`, "+" saves `all` and the text reads "All";
  - "-" from `all` saves max;
  - at min, "-" has style `stepDim`, and pressing it leaves the value and skips OnChange;
  - a value of 0 with offLabel reads "Off";
  - a saved value out of range (15, or "x") reads the default and "+" saves default+1;
  - a stepper row with `up = nil` dims "+";
  - Large size, narrow width: the heading goes above and all three pieces share a line.
- [ ] Implement; `scripts/test.sh`.

### Task 2: Features use it

**Files:**
- Modify: `QuestIcons.lua`:
  - options order: show, Icons on, size, cluster, spots, hideHaze, Icon key;
  - `MAP_PX.xsmall = 18`, `MINI_PX.xsmall = 11`, with choice "Extra small" first;
  - cluster `number = { min=0, max=10, default=2, unit="merge", offLabel="Off" }`;
  - spots `number = { min=1, max=20, default=5, unit="spots", all=0, allLabel="All" }`;
  - `/qd spots` takes 1–20 too; `/qd cluster` is clamped to 0–10; update USAGE.
- Modify: `QuestArrow.lua`: `BOX_PX.small = 56`, with choice "Small" first.
- Modify: `Chat.lua`: replace `buttons = TextSizeButtons` with `stepper`, giving text = the current size, unit "text size", and down/up nil when `NextTextSize` has no step.
- Tests: `questicons_test.lua`, `questarrow` tests, `chat` tests (whichever exist):
  - the new choices and order;
  - 1–20/All and 0–10 wiring;
  - xsmall pixel sizes;
  - the arrow's small box;
  - the chat stepper's dimmed ends and the "(after the fight)" text;
  - smoke threshold updated if the press count changes, with a comment.
- [ ] Implement; `scripts/check.sh`, `scripts/test.sh`.

### Task 3: Version, documents, build

- [ ] **Version and documents:**
  - TOC 0.7.0 and CHANGELOG 0.7.0 ("Nineteenth test build").
  - The PRD status paragraph.
  - `docs/TESTING.md` section 15, with the spec's device-test steps.
- [ ] Run `scripts/build.sh`, commit, push the branch, tag v0.7.0, and create a GitHub pre-release (the owner asked for it on 2026-11-18).
