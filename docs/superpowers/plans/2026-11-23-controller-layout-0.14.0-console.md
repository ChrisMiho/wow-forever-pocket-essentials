# Plan: Controller layout 0.14.0, the console

Spec: docs/superpowers/specs/2026-11-23-controller-layout-0.14.0-console.md (approved overnight).

1. ControllerLayout.lua (PE.LayoutPlan): Plan.FACE 42/46/28; FaceSpots() inner/outer; new
   FaceStates(); real bars at 60% under the inner diamonds (SPOTS, REAL_BAR_SCALE); FRAME_X 395;
   SHOULDERS (-76,128)/(76,128); Plan.Rects() lists the four diamond spots; TEMPLATE 4; header
   comment for 0.14.0. Tests: tests/features/layout_test.lua numbers and overlap checks.
2. FaceBars.lua: halves as frames, placed from FaceStates on an active-group change; quiet side
   0.3; glyph/range/count scale with the picture; backings from inner diamonds + real bars;
   defaults mirror the plan. Tests: tests/features/facebars_test.lua for each state (rest, LT,
   RT, both), hidden/quiet halves, swap in a fight allowed (no protected call).
3. Version 0.14.0 (TOC + CHANGELOG), TESTING 28, PRD status line, ARCHITECTURE unverified rows
   only if a new game call is added (none expected).
4. Review against the spec (separate agent), fix, scripts/check.sh + scripts/test.sh + build.
