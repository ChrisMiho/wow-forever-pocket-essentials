# 0.0.4: Green Minimap and Arrow Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the minimap turning green when "Hide blue haze" is on, and let the arrow's small text line show whole messages.

**Architecture:** Two independent edits. `QuestIcons.lua` stops swapping the minimap blob textures (the minimap cannot draw our `blank.tga`; the "outside" blob texture covers the whole minimap, so it turns green) and keeps only alphas and ring scalars. `QuestArrow.lua` lets `titleText` wrap to two lines and sizes the frame for it.

**Tech Stack:** Lua 5.1 (WoW addon, interface 16001), LuaJIT for checks.

**Spec:** `docs/superpowers/specs/2026-11-15-green-minimap-and-arrow-text.md`

## Global Constraints

- Interface 16001, modern API, no libraries.
- Verify every new API in `github.com/Gethe/wow-ui-source`, branch `forever` (e.g. `gh api` or raw.githubusercontent.com); log unverified ones in `docs/ARCHITECTURE.md` "Unverified API".
- Match the surrounding code's comment density and plain-language style; `scripts/check.sh` also checks comment wording.
- Version 0.0.4 in `addons/PocketEssentials/PocketEssentials.toc` `## Version` and a matching `## [0.0.4] - 2026-11-15` CHANGELOG entry, written for a player.
- No game client here: the checks prove syntax and data logic, not behaviour. Do not claim in-game results.
- Do not push and do not upload anywhere.

## Review Focus

1. A quest title or zone name longer than two lines' worth: must end in "..." on line two, never spill out of the frame or overlap anything under it.
2. The distance line and "Turn around" must stay single-line and unchanged.
3. The "Reload to bring back the blue quest areas" prompt and `blobsZeroed` logic must still work with only the alpha and scalar setters left.
4. No remaining reference to `blank` anywhere (code, build file lists, docs, make_art.py) after the file is removed.
5. Short titles must still render on one line, centred, in the same place as in 0.0.3.

(No automated UI harness exists; items 1, 2 and 5 are checked by reading the code and in the owner's device test.)

---

### Task 1: Minimap haze without texture swaps

**Files:**
- Modify: `addons/PocketEssentials/QuestIcons.lua:~85-103` (comment above `BLANK_TEXTURE`, `BLANK_TEXTURE`, `BLOB_SETTINGS`)
- Delete: `addons/PocketEssentials/Icons/blank.tga`
- Modify: `scripts/make_art.py` (line 7 docstring, line 215 `write_tga(... "blank.tga")`)
- Modify: `docs/ARCHITECTURE.md` lines 25, 102, 103, 179, plus a new "Facts" entry

- [ ] **Step 1:** In `BLOB_SETTINGS`, remove the six `Set...Texture` entries and delete `BLANK_TEXTURE`. Keep the six alphas and two ring scalars. Update the comment block above so it no longer mentions textures, and add one line saying why: our blank texture turned the minimap green on the device (0.0.3), so textures are left alone.
- [ ] **Step 2:** `grep -rn -i blank addons scripts docs README.md` and remove or reword every remaining reference (the make_art.py docstring and `write_tga` call; ARCHITECTURE.md lines listed above). Delete `Icons/blank.tga`. If `scripts/build.sh` or any file list names icons explicitly, update it.
- [ ] **Step 3:** In `docs/ARCHITECTURE.md`: unverified-API row at line 102 drops "blank textures"; row 103 drops `blank`; add under "Facts" (the section for things seen on the device, or Verified if that is where device findings live; follow the file's pattern) a line: "0.0.3 on the device: swapping the minimap's quest blob textures for our `Icons/blank.tga` turned the minimap solid green when a focused quest had a quest area. Removed in 0.0.4."
- [ ] **Step 4:** Run `scripts/check.sh` and `scripts/test.sh`. Expected: both exit 0.
- [ ] **Step 5:** Commit: `git add -A addons scripts docs && git commit -m "Quest icons: stop swapping minimap blob textures (green minimap)"`

### Task 2: Arrow text wraps to two lines, then version 0.0.4

**Files:**
- Modify: `addons/PocketEssentials/QuestArrow.lua` (`TITLE_MAX` line 60, `Shorten` ~179, `titleText` creation ~392, `Layout` ~410-430)
- Modify: `addons/PocketEssentials/PocketEssentials.toc`, `CHANGELOG.md`, `PRD.md` "Status" (one line: 0.0.4 carries fixes 3 and 6 from the second device test, spec path)

- [ ] **Step 1:** Verify `FontString:SetMaxLines` exists on the forever branch (search `SetMaxLines` in `Interface/AddOns/Blizzard_APIDocumentationGenerated/` or FrameXML on branch `forever`). Record the file where it was found in the commit message. If absent, log it in ARCHITECTURE.md "Unverified API" and guard the call with `if text.SetMaxLines then`.
- [ ] **Step 2:** `titleText`: `SetWordWrap(true)`, `SetMaxLines(2)`, keep `SetJustifyH("CENTER")`, add `SetJustifyV("TOP")`. Leave `distText` and `turnText` as they are.
- [ ] **Step 3:** `Layout`: give `titleText` an explicit height of two lines (`fontSize * 2.4` or the builder's equivalent) and raise the `S.display` height by one line (`fontSize * 2.6` becomes about `fontSize * 3.8`) so line two is inside the frame. Anchors stay the same so a one-line title sits where it did.
- [ ] **Step 4:** `Shorten` must not cut text that now fits in two lines: raise `TITLE_MAX` to `52` (two lines of the old 26), keep the multi-byte-safe cut. Update its comment.
- [ ] **Step 5:** Bump TOC `## Version: 0.0.4`; add the CHANGELOG `[0.0.4] - 2026-11-15` entry ("Fourth test build. Not yet tested on a device.", Fixed: green minimap with Hide blue haze on; arrow text cut off with "..."). Add the PRD status line.
- [ ] **Step 6:** Run `scripts/check.sh` and `scripts/test.sh`. Expected: both exit 0.
- [ ] **Step 7:** Commit: `git add -A addons CHANGELOG.md PRD.md docs && git commit -m "0.0.4: arrow text wraps to two lines; green minimap fix"`

### After both tasks (controller)

- Run `scripts/build.sh`; confirm `dist/PocketEssentials-0.0.4.zip` exists and has no `blank.tga`.
- Hand the owner the zip and the spec's device-test list.
