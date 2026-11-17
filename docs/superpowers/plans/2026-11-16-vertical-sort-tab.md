# Vertical Sort Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the wide Sort block beside the bag into a tall, narrow tab flush against the bag's left edge.

**Architecture:** Only `Bags.lua` `CreateButtons` / `LayoutButton` / `ApplyScaleNow` change. The tab is still our own `PE.UI:CreateButton` child of `UIParent`, anchored to the bag. A gold-on-dark look comes from a new `"tab"` style in `UI.lua`.

**Tech Stack:** Lua 5.1 (WoW, Interface 16001), LuaJIT offline tests (`tests/features/`, `tests/lib/fakeclient.lua`).

**Spec:** `docs/superpowers/specs/2026-11-16-vertical-sort-tab.md`

## Global Constraints

- Taint rules in the `Bags.lua` header stay: no field written on a Blizzard frame, no Blizzard Lua function called, the tab is a child of `UIParent`.
- Handlers through `mod:Wrap`. Nothing ticks while the feature is off.
- Every new game call verified in `wow-ui-source` `forever`, then `scripts/audit-api.sh`.
- Atlas name: `bags-button-autosort-up`.

## Review Focus

- Client without the atlas: `SetAtlas` returns false or errors; the tab must still show the letters (pcall, hide the icon).
- Bag at "Extra large" on a small screen: the clamp must leave room for the tab's real (narrow) width, not the old wide one.
- Very short bag (few slots): tab height floor of three button heights must not push it below the screen; it hangs from the top, which is fine.
- Font size preset changes (`OnMetricsChanged`): the tab re-lays out (width, height, letters).
- The test helper finds the button by its label; the label stays "Sort" for code (`GetLabel`), only drawn stacked.

---

### Task 1: The tab

**Files:**
- Modify: `addons/PocketEssentials/UI.lua` (STYLES: add `tab`)
- Modify: `addons/PocketEssentials/Bags.lua` (`CreateButtons`, `LayoutButton`, `ApplyScaleNow` button room)
- Modify: `tests/lib/fakeclient.lua` (Texture `SetAtlas`, returns true)
- Test: `tests/features/bags_test.lua`

**Interfaces:**
- Produces: `TabWidth()` local in `Bags.lua` returning the tab width in UIParent units (`m.button`), used by both `LayoutButton` and the clamp in `ApplyScaleNow`.

- [ ] **Step 1: Tests** in `bags_test.lua`:
  - `bags: the Sort tab is taller than it is wide and flush against the bag's left edge`: open bag; `btn:GetHeight() > btn:GetWidth() * 2`; `GetPoint(1)` is `TOPRIGHT` on `c.bagFrame` `TOPLEFT` with x offset `0`.
  - Existing helper `sortButton` keeps matching `GetLabel() == "Sort"`.
- [ ] **Step 2:** Run `scripts/test.sh`; the new test fails.
- [ ] **Step 3: Implement.**
  - `UI.lua` STYLES `tab = { fill = {0.07,0.06,0.04}, border = {0.80,0.64,0.20}, text = {1,0.82,0} }`.
  - `CreateButtons`: `btn:SetStyle("tab")`; label drawn as `"S\no\nr\nt"` by setting `btn.peText` (our own font string) to word wrap on, justify center, anchored full height; `GetLabel` must still return `"Sort"`, so keep `SetLabel("Sort")` and override display via a separate own font string or by `peText:SetText` after `SetLabel` (builder's choice; `GetLabel` reads `peText`, so prefer a second font string and hide `peText`). Icon: an own texture, `pcall(icon.SetAtlas, icon, "bags-button-autosort-up")`; hide it if that fails or returns false.
  - `LayoutButton`: width `TabWidth()`; height `max(m.button * 3, bagHeightInUIParent * 0.5)` where bag height in UIParent units is `bag:GetHeight() * bag:GetEffectiveScale() / UIParent:GetEffectiveScale()` (Plain-checked; fall back to `m.button * 3`). Anchor `TOPRIGHT` to bag `TOPLEFT`, x `0`, y `-m.button` (clears the round picture).
  - `ApplyScaleNow`: `buttonRoom = TabWidth() * toParent`.
  - `fakeclient.lua`: add `SetAtlas` to `M_TEXTURE` returning true.
- [ ] **Step 4:** `scripts/check.sh && scripts/test.sh` pass. Run `scripts/audit-api.sh` (SetAtlas is new) and confirm it lists `SetAtlas` as verified.
- [ ] **Step 5:** Update the existing "sits beside the bag" test comment and `docs/DECISIONS.md` "Bags" wording if it says "floats beside". Commit.
