# Plan: Controller layout 0.13.0, face bars

Spec: `docs/superpowers/specs/2026-11-23-controller-layout-0.13.0-face-bars.md`.
Source facts: `docs/11-23-face-bars/SOURCE-BRIEF.md` (cite it; re-check any line
you rely on in `~/.cache/wow-ui-source/forever/Interface/AddOns/`).

Two builders in parallel, in separate worktrees, on files that do not overlap,
then a merge, one review against the spec, the version, and the release.

## The contract between the two halves

`PE.LayoutPlan` (ControllerLayout.lua, pure) gains:

```lua
Plan.FACE = { button = 28, dx = 30, dy = 19 }  -- a diamond: 88 by 66
-- Where each bar's two halves are drawn, centre of each diamond, UI units from
-- the screen's bottom centre. bar = "main" | "lt" | "rt" | "both";
-- half "dpad" is always on the left (x < 0), "face" on the right (x > 0).
function Plan.FaceSpots() return {
    main = { dpad = { x = -199, y = 39 },  face = { x = 199, y = 39 } },
    lt   = { dpad = { x = -199, y = 113 }, face = { x = 199, y = 113 } },
    rt   = { dpad = { x = -297, y = 39 },  face = { x = 297, y = 39 } },
    both = { dpad = { x = -297, y = 113 }, face = { x = 297, y = 113 } },
} end
```

`PE.FaceBars` (FaceBars.lua, new, loaded right after ControllerLayout.lua):

```lua
PE.FaceBars:Start()   -- out of a fight only; builds once, binds to the real
                      -- buttons, shows the face, then sets the four anchors'
                      -- alpha to 0. Returns true, or false and a plain reason.
PE.FaceBars:Stop()    -- any time (also in a fight): hides the face, anchors'
                      -- alpha back to 1, events dropped, hooks go idle.
PE.FaceBars:Status()  -- nil while fine or stopped; else the plain reason the
                      -- game's own bars are showing ("the game's bars were not found", ...)
```

ControllerLayout calls `Start()` at the end of a successful `PlaceNow()` and
`Stop()` at the start of `RestoreNow()` and whenever the feature goes off,
each guarded (`PE.FaceBars` may be nil in old tests) and through `PE:Safe`.
Its status line, while ours is active and `Status()` is non-nil, adds
"Showing the game's own spell bars: <reason>".

## Builder A: the layout (ControllerLayout.lua, tests/features/layout_test.lua, docs)

1. `SPOTS` (real bars, invisible): top (main) -248, 39; left (LT) -248, 113;
   right (RT) 248, 39; both (LT+RT) 248, 113; all scale 0.9; bottom anchor
   unchanged at 0, 238 (sub-menu buttons at ±138, 188).
   Check: `Put` divides by the scale; the 0.9 bars are 187.2 by 61.2.
2. `Plan.FACE`, `Plan.FaceSpots()` as above.
3. Frames: Player `BOTTOMRIGHT` at -345, 56; Pet `BOTTOMRIGHT` -345, 56 + 100 + 25;
   Target `BOTTOMLEFT` 345, 56 (BuffsOnTop kept); target of target above the
   target frame, left-aligned (TOT_SPOT recomputed). Check the target's cast bar
   (with the target of target shown: 123 right, 46 under the frame's bottom
   left, 150 by 10) lands fully on screen (x ≤ 682.6, y ≥ 0) and clear of the
   face; if not, raise the frames the least and write it under "As built".
4. Quest tracker: `TOPLEFT` 5, -5 (where the hint box was), Height setting as
   now. Check the PE round button (Hub "LEFT": `LEFT` of UIParent, x 1; its
   size from Hub.lua) and the quest arrow's "top" spot (`TOP` 0, -40, 400 px
   wide at 720p) do not overlap the tracker; if the round button does, move the
   tracker the least and write it in "As built".
5. The hint box: while our layout is placed, the CVar
   `GamepadShowPersistentInputLegend` is set to "0" (`C_CVar.SetCVar`, out of a
   fight), the player's earlier value saved once in the module's options
   (`opts.hintsWas`), and put back when the layout is switched off or put
   back. A value the player changes while on is left alone at the next login
   (only set it again if it still equals what we set... simplest rule: set it to
   0 only when we have not yet saved `hintsWas`, and restore + clear
   `hintsWas` when off). Verify the CVar name in
   `Blizzard_Gamepad/UI/PersistentInputLegend/GamepadPersistentInputLegend.lua`.
6. `Plan.TEMPLATE = 3` (CHAT_UPDATED line unchanged).
7. `Plan.Rects()`: replace the bar boxes with the face diamonds (88 by 66 each,
   named "main dpad", "main face", ...) plus the invisible real bars (reported
   separately as `Plan.RealBarRects()`, not part of the overlap check against
   the face, since they sit under it by design); the new frames, auras, cast
   bar, ToT; the tracker at its new spot (260 by 400 at most); keep the map,
   strip, timers, sub-menu buttons; add the two targeting pictures (36 by 32 at
   ±108 to ±144, 84 to 116 up).
   Tests: no overlaps among `Plan.Rects()`; every rect on screen
   (−682.6 ≤ x ≤ 682.6, 0 ≤ y ≤ 768); real bars do not overlap the frames, the
   map or the targeting pictures; each real bar lies under its own side's face
   grid; the wheels may cover face diamonds (no test), but not the frames.
8. The integration calls to `PE.FaceBars` (contract above), guarded, and the
   status line. Tests with a stub `PE.FaceBars` that records calls: Start after
   a placement; Stop before a put-back and at switch-off; the status line text.
9. Update comments at the top of the file (0.13.0), keep the wording rule
   (`scripts/check.sh` checks comment wording).
10. Do NOT touch: FaceBars.lua, tests/lib/fakeclient.lua beyond what the CVar
    needs, the TOC, CHANGELOG, TESTING, PRD.

## Builder B: the face (FaceBars.lua, tests/lib/fakeclient.lua, tests/features/facebars_test.lua, the TOC line)

1. `addons/PocketEssentials/FaceBars.lua`, added to the TOC right after
   `ControllerLayout.lua`. Not a module with its own switch: it belongs to
   Controller layout (PE error key `"ctrlLayout"`); nothing runs until
   `Start()`.
2. Build (once, out of a fight): one holder frame on UIParent, strata and
   level chosen from the source so it is above the real bars and below the
   wheels / flyouts (`FlyoutRadial`, `GamepadSpellFlyout`, class action
   flyouts): find their strata; if the wheel shares the bars' strata, use the
   bars' strata with a frame level above the bars' highest and below the
   wheel's, and write the numbers in a comment. 4 groups × 8 pictures:
   - a Frame (mouse enabled, no scripts: it swallows taps), size 28;
   - textures: dark edge, icon, the position glyph (drawn from plain textures:
     four small dots in a diamond for face buttons, a plus for the d-pad, the
     button's own spot filled white; the others outlined), a small range dot
     (bottom right), a gold edge (checked), a gold glow (proc), dim overlay;
   - a FontString for the count (bottom right, small) and, in each diamond's
     centre, the tag "LT" / "RT" / "LT+RT" (none for main);
   - a Cooldown frame (`CreateFrame("Cooldown", nil, picture, "CooldownFrameTemplate")`
     if the template exists on forever; check; else a plain Cooldown frame).
   Spots from `PE.LayoutPlan.FaceSpots()` and `Plan.FACE`; index order 1-4
   d-pad left, up, right, down; 5-8 face X left, Y up, B right, A down.
3. Bind: for each group, the anchor (`GamepadMainActionBarFrame.PageUnit.<Top|Left|Right|Bottom>CenteredAnchor`)
   and the bar shown in it now: among `PageUnit.actionBars` (all of them:
   topBar, leftBar, rightBar, bottomBar, stanceBar, possessBar, the targeting
   bars) the one whose parent is that anchor and that is shown; else the
   anchor's `.Bar`. Re-bind on the active-bar callback, on
   `UPDATE_BONUS_ACTIONBAR`, `UPDATE_SHAPESHIFT_FORM`, `UPDATE_POSSESS_BAR`
   (whichever exist), and on Show/Hide hooks of the override bars (install
   `HookScript("OnShow"/"OnHide")` once on each of them).
4. Mirror (per picture, from its bound real button), all post-hooks installed
   once per real button and doing nothing while stopped or while that button is
   not bound; every hook only marks the picture dirty; one `OnUpdate` on the
   holder runs while anything is dirty, then removes itself:
   - icon: `button.icon` `SetTexture` / `SetVertexColor` / `SetDesaturated` /
     `Show` / `Hide`; seed with `GetTexture`, `GetVertexColor`, `IsDesaturated`,
     `IsShown` (each pcall'd; a secret colour is replaced by 1,1,1);
   - main bar's face buttons (`button.action` 0 or nil, `SpecialActionIcon`
     present): copy `SpecialActionIcon` (texture or atlas, whichever it uses)
     instead of `icon`;
   - range: `button.RangeIndicator` `Show` / `Hide` / `SetVertexColor`;
   - count: `button.Count` `SetText` → our FontString `SetText` with the same
     value (no comparison, no formatting; empty when the button has no Count);
   - checked: `button:GetChecked()` read on `ACTIONBAR_UPDATE_STATE` and after
     `UpdateState` (hook if present); secret → not checked;
   - glow: `ActionButtonSpellAlertManager` `ShowAlert(self, button)` /
     `HideAlert(self, button)` hooked once; the button looked up in our
     real-button → picture map;
   - slot changes: hook `UpdateAction` per button (re-seed); hook
     `PageUnit` `SetCurrentPage` (re-seed all). Never `AddPageChangeCallback`;
   - cooldown: events `ACTIONBAR_UPDATE_COOLDOWN`, `SPELL_UPDATE_COOLDOWN`;
     for each bound button with `type(action) == "number" and action > 0`:
     `C_ActionBar.GetActionCooldownDuration(action)` → `cd:SetCooldownFromDurationObject(obj)`
     (pcall; nil or error → `cd:Clear()` if present); "on cooldown" from the
     readable answer the probe proved (see `probe/PocketProbe/Trials.lua`,
     the `bars.spells` trial: which call it uses for "on cooldown") → dim the
     icon. Never `SetCooldown`.
   An empty slot (no texture): the picture shows only a faint outline and the glyph.
5. Active bar: `PageUnit:RegisterActiveActionBarUpdatedCallback(fn, "PocketEssentialsFace")`
   once (owner a string). `fn` reads `PageUnit:GetActiveBar()`, finds which
   anchor is its parent (or ancestor), and if that changed, sets the four
   groups' alpha: the active group 1, the others 0.5. A targeting bar in the top
   anchor makes "main" the active group. Missing callback: all groups 1.
6. Fade: after the face is built, bound and shown, set the four anchors'
   `SetAlpha(0)`; hook each anchor's `SetAlpha` once so that while started, any
   other value is answered with 0 (guard against our own call recursing).
   `Stop()` sets 1. Hide the face while `GamepadMainActionBarFrame` is hidden
   (`HookScript` once).
7. Failure: anything missing at Start (frames, buttons, Cooldown support,
   `GetActionButtonByIndex`) → no fade, Status() says why, logged once (debug).
   Errors: our own error counter; at the 3rd error in a session `Stop()` runs
   and Status() = "Pocket Essentials' spell pictures hit an error" and a chat line
   once ("Spell pictures turned off after an error; the game's bars are back.
   Reload to try again."). All handlers through `PE:Wrap("ctrlLayout", ...)`;
   count errors with a small wrapper around it.
8. Fake client: extend the existing gamepad bar model (`tests/lib/fakeclient.lua`
   near line 1116) with `PageUnit.actionBars`, each bar's `Left` / `Right`
   groups with `ActionButton1..4`, `GetActionButtonByIndex`, the buttons'
   regions (`icon`, `Count`, `RangeIndicator`, `SpecialActionIcon` on the top
   bar's face buttons), `action`, `GetChecked`, `UpdateAction`, `UpdateState`;
   a stance bar that can be swapped into the top anchor;
   `RegisterActiveActionBarUpdatedCallback` / `GetActiveBar` / `SetCurrentPage`
   and test helpers to press triggers; `ActionButtonSpellAlertManager`;
   `CreateFrame("Cooldown")` with `SetCooldownFromDurationObject` (and
   `SetCooldown` that records a call so a test can assert it is never used);
   `C_ActionBar.GetActionCooldownDuration`. Keep every existing test green.
   Mark secret values with the existing `world.secrets` mechanism.
9. Tests `tests/features/facebars_test.lua` (register it where the others are,
   `tests/features/run.lua`), covering the spec's "Tests" list for the face
   and the fallback, plus the "difficult game" cases: each new call missing,
   nil, raising, secret.
10. `scripts/audit-api.sh` after adding game calls (it rewrites
    `tests/api/*.txt`); unverified ones go in `docs/ARCHITECTURE.md` with their
    worst case.
11. Do NOT touch ControllerLayout.lua, layout_test.lua, CHANGELOG, TESTING, PRD.

## Both builders

- `scripts/check.sh` and `scripts/test.sh` green before every commit; small
  commits with clear messages ending with the session's attribution lines.
- Plain-language comments, existing style (see the top of ControllerLayout.lua).
- Report: what was built, what differs from the spec and why ("As built"
  notes), every unverified API, anything you were unsure about.

## After both

Merge both branches into `setup-options` (re-run `scripts/audit-api.sh` if the
`tests/api/*.txt` files conflict), check + test, one review subagent against
the spec, fixes, then version 0.13.0 (TOC, CHANGELOG), `docs/TESTING.md`
section 27, PRD status, the spec's "As built", build, pre-release `v0.13.0`
with both zips.
