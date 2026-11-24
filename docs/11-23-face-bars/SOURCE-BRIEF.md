# Face bars: technical brief (Blizzard source, branch forever)

Paths: `G/` = `Blizzard_GamepadActionBars/`, `AB/` = `Blizzard_ActionBar/Shared/`,
`DOC/` = `Blizzard_APIDocumentationGenerated/` (all under `~/.cache/wow-ui-source/forever/Interface/AddOns/`).

## 1. The four bars and their 8 buttons

- PageUnit = `GamepadMainActionBarFrame.PageUnit` (global `GamepadMainActionBarFramePageUnit`), G/MainActionBarFrame.xml:3,12.
- Anchors and bars (G/ActionBarTemplates.xml:600-706):
  | Trigger state | Anchor (parentKey / global) | Bar | `PageUnit.actionBars` key |
  |---|---|---|---|
  | none (main) | `TopCenteredAnchor` / `...PageUnitTopCenteredAnchor` | `.Bar` = `...TopCenteredAnchorTopBar` | `topBar` |
  | LT | `LeftCenteredAnchor` | `.Bar` = `...LeftCenteredAnchorLeftBar` | `leftBar` |
  | RT | `RightCenteredAnchor` | `.Bar` = `...RightCenteredAnchorRightBar` | `rightBar` |
  | LT+RT | `BottomCenteredAnchor` | `.Bar` = `...BottomCenteredAnchorBottomBar` | `bottomBar` |
  Table built at G/PageUnit.lua:111-114; trigger mapping at G/PageUnit.lua:565-594 (RT→right, LT→left and wins over RT, both→bottom, none→top).
- Each bar has `.Left` (d-pad, square) and `.Right` (face, circle) frames, each with parentKeys `ActionButton1..4` (G/ActionBarTemplates.xml:151-320). Order inside each group is **1=left, 2=top, 3=right, 4=bottom** (mappedButtonKey GAMEPAD_DPAD_LEFT/TOP/RIGHT/BOTTOM and GAMEPAD_FACE_LEFT/TOP/RIGHT/BOTTOM, :165,183,201,219,251,269,287,305; also G/ActionBarButton.lua:32-42 and G/ActionBarStyles.lua:7).
  - Face: Right.ActionButton1 = X (left), 2 = Y (top), 3 = B (right), 4 = A (bottom) (xbox atlases, G/ActionBarButton.lua:49-52).
- Stable enumeration: `bar:GetActionButtonByIndex(i)` / `bar.actionButtons[i]`, i=1..8: 1-4 = Left.ActionButton1-4, 5-8 = Right.ActionButton1-4 (G/ActionBar.lua:7-20, 296-298). This is the same index the binding presses: `GAMEPADACTIONBUTTONn` → `PressActionButton(n)` → `GetActiveBar():GetActionButtonByIndex(n)` (G/Bindings.xml:1-31, G/MainActionBarFrame.lua:706-707).
- Global button names: `GamepadMainActionBarFramePageUnit<Dir>CenteredAnchor<Dir>BarActionButton<1-8>`, Dir = Top/Left/Right/Bottom (G/IconIntro.lua:31-37; names 1-4 left group, 5-8 right group, G/ActionBarTemplates.xml:158,244).
- **Main bar face buttons are not spells.** Page-unit slots 5-8 (top bar, Right group) are reserved (G/ActionBindingUtil.lua:23,46-49), action 0 (G/ActionBarButton.lua:871-878). They are scripted: Right.ActionButton1 (X) = Interact/attack, 2 (Y) = Inspect/raid marker, 3 (B) = Back/clear target, 4 (A) = Jump (G/MainActionBarFrame.lua:426-667). Their picture is `button.SpecialActionIcon` (icon alpha 0 on interact, :546-547); they are unregistered from native updates (:658-661).

## 2. Action slot per button

- Slot = `button.action` (set in `UpdateAction`, AB/ActionButton.lua:539-545). It equals `button:GetID()`: gamepad buttons force `actionpage`=1 so no MKB page offset is added (G/ActionBarButton.lua:1060-1063; AB formula in Blizzard_FrameXML/SecureTemplates.lua:667-685).
- The ID is a storage index from the gamepad **page** (1-3) and the button's page-unit slot ID 1-32: `GamepadActionBarBindingUtil.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(page, slotID)` (G/ActionBindingUtil.lua:88-111; slot layout diagram :3-21; slot IDs assigned bar-by-bar G/PageUnit.lua:371-380). So yes, it depends on the page: changing page re-IDs every button (G/PageUnit.lua:400-404 → G/ActionBar.lua:242-250 → G/ActionBarButton.lua:1093-1105). Page 4 is the "special" possess page (DOC/GamepadUIDocumentation.lua:146-158).
- Stance/form/bonus bar does **not** change the four bars' slots. Instead a separate bar, `TopCenteredAnchor.StanceBar`, is filled from `C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance()` and **replaces** one bar (`.Bar:Hide()`, StanceBar shown in the same anchor) on `UPDATE_BONUS_ACTIONBAR` (G/StanceBar.lua:24-63; G/GamepadOverrideBarMixin.lua:59-96). Which bar/page it replaces = CVar `GamepadStanceBarOverride` (G/StanceBar.lua:3-14). Possess/pet control does the same with `PossessBar` (pet actions, not action slots; CVar `GamepadPossessBarOverride`, G/PossessBar.lua:1-20,36-50). Targeting bars (Friendly/Hostile/Shortcuts, held LB/RB) replace the top bar (G/TargetActionBars/StaticOverrideActionBar.lua:183-208), reparented to TopCenteredAnchor (G/PageUnit.lua:136-149).
- Change signals: per-button `UpdateAction` (hookable per instance) runs on page change and on `ACTIONBAR_SLOT_CHANGED` (AB/ActionButton.lua:981-984,1109-1112). For bar swaps use the active-bar callback (section 4). Do **not** use `PageUnit:AddPageChangeCallback` (G/PageUnit.lua:450-452): it is called directly from Blizzard code (:415-417), so an addon function there taints the rest of `SetCurrentPage`. `hooksecurefunc(PageUnit, "SetCurrentPage", fn)` is the safe form.

## 3. What a real button shows, where it comes from, and which events drive it

All in `ActionBarActionButtonMixin` (AB/ActionButton.lua) unless noted. Buttons get events through shared frames, not their own registration (AB/ActionButton.lua:213-225, 255-292, 378-450).
| Visual | Source call | Region written | Driven by |
|---|---|---|---|
| Icon | `C_ActionBar.GetActionTexture(action)` | `button.icon:SetTexture` (:574,633-635) | `Update` (slot change, PEW, SPELL_UPDATE_ICON, :985-986,1069-1070); `UPDATE_SHAPESHIFT_FORM` sets the icon **without** `Update` (:987-993); flyouts `UpdateFlyoutActionIcon` (G/ActionBarButton.lua:1027-1035) |
| Usable / no mana | `C_ActionBar.IsUsableAction` | `icon:SetVertexColor` 1,1,1 / .5,.5,1 / .4,.4,.4 (:721-734) | `ACTION_USABLE_CHANGED` (replaces ACTIONBAR_UPDATE_USABLE, :257,416-433), `PLAYER_SOFT_ENEMY_CHANGED` (G/ActionBar.lua:55-60), mount change (:1006-1007) |
| Out of range | `ACTION_RANGE_CHECK_UPDATE(slot,inRange,checksRange)` (only for slots enabled with `C_ActionBar.EnableActionRangeCheck`, :395-404) | gamepad: `button.RangeIndicator` dot red/normal, ButtonIcon disabled (G/ActionBarButton.lua:534-564,1070-1073); icon is **not** tinted | same event |
| Cooldown | `C_ActionBar.GetActionCooldown/GetActionCharges/GetActionLossOfControlCooldownInfo` (or `C_Spell.*` for single-spell flyouts) | `button.cooldown`, `.chargeCooldown`, `.lossOfControlCooldown` via `:SetCooldown` (:867-911) | `ACTIONBAR_UPDATE_COOLDOWN`, `LOSS_OF_CONTROL_*` (:1008-1011); flyouts also `SPELL_UPDATE_COOLDOWN` (G/ActionBarButton.lua:916,988-989). Also `C_ActionBar.RegisterActionUIButton(self, action, self.cooldown)` hands the button to native code (:550; "prevent native events from overriding state", G/TargetActionBars/StaticOverrideActionBar.lua:11-13) |
| Count/charges | `C_ActionBar.GetActionDisplayCount` | `button.Count:SetText` (:852-854) | `SPELL_UPDATE_CHARGES` (:1059-1060), `Update` |
| Equipped border | `C_ActionBar.IsEquippedAction` | `button.Border` green 0.5 (:611-620) | `Update` |
| Checked (current/auto-repeat) | `IsCurrentAction or IsAutoRepeatAction` | `button:SetChecked` (:715-719) | `ACTIONBAR_UPDATE_STATE`, vehicle, companion, trade skill (:1002-1005,1016-1017) |
| Auto-attack / autorepeat flash | `IsAttackAction`, `IsAutoRepeatAction` | `button.Flash` toggled on a timer (:1144-1175,1314-1373) | `PLAYER_ENTER/LEAVE_COMBAT`, `START/STOP_AUTOREPEAT_SPELL` (:1018-1033). Main-bar X (interact) flashes via `RefreshAttackFlash` (G/MainActionBarFrame.lua:404-413) |
| Proc glow | `C_SpellActivationOverlay.IsSpellOverlayed` | `ActionButtonSpellAlertManager:ShowAlert/HideAlert(button)` → child frame `button.SpellActivationAlert` (:921-932,1037-1058; AB/ActionButtonSpellAlerts.lua:11-21,117-133) | `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` |
| Pressed | binding | `SetButtonState("PUSHED"/"NORMAL")` (G/MainActionBarFrame.lua:717-727) and `ApplyPressedStyle(down)` (size -4, y -2) (G/ActionBarButton.lua:421-433,1111-1114; G/ActionBarStyles.lua:11-12,140-144) | press/release |
| Cast fill, interrupt, reticle | spellcast events | `SpellCastAnimFrame`, `InterruptDisplay`, `TargetReticleAnimFrame` (:1074-1103) | UNIT_SPELLCAST_* |

Hook points (all are per-instance fields, so `hooksecurefunc(button, name, fn)` works): `Update`, `UpdateAction`, `UpdateUsable`, `UpdateState`, `UpdateCount`, `UpdateFlash`, `ApplyPressedStyle`, `SetButtonState` (replaced by a Lua field at AB/ActionButton.lua:455-456). Globals: `hooksecurefunc("ActionButton_UpdateCooldown", fn)` (called as a global, :587,1009,1011), `hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert"/"HideAlert", fn)`. Region-level hooks also work and catch every Lua path: `button.icon` `SetTexture`/`SetVertexColor`/`SetDesaturated`, `button.Count` `SetText`, `button.Flash` `Show`/`Hide`.

Is copying from the real regions sound? Mostly yes, with these limits:
- `icon:GetTexture()` / `GetTextureFileID()` carry no secret aspect (DOC/SimpleTextureBaseAPIDocumentation.lua:219-243). `GetVertexColor` is secret only if a secret value was written (DOC/SimpleRegionAPIDocumentation.lua:66-69); Blizzard writes constants (AB/ActionButton.lua:728-734).
- `Count:GetText()` will be secret in a fight (count is `SecretWhenCooldownsRestricted`, DOC/ActionBarFrameDocumentation.lua:199-203; SetText adds the Text aspect, DOC/SimpleFontStringAPIDocumentation.lua:353-355,664-667). Passing it to **our** FontString's `SetText` is allowed (`AllowedWhenTainted`), but never compare or format it.
- Do not copy the cooldown frame: `GetCooldownTimes` returns secrets (DOC/FrameAPICooldownDocumentation.lua:49-51) and `SetCooldown` refuses them from addon code (:281-285; device-proven). Use `C_ActionBar.GetActionCooldownDuration(action)` + `SetCooldownFromDurationObject` (:308-311; device-proven allowed).
- Native code can change cooldown/checked on registered buttons without Lua (`RegisterActionUIButton`), which Lua hooks will not see. So for cooldown and checked, listen to the events yourself and query by slot.
- In compact layout inactive bars are hidden, and hidden buttons drop range/usable watching (AB/ActionButton.lua:1191-1196); their regions go stale until shown (:1180-1185).

## 4. Active bar

- `PageUnit:GetActiveBar()` returns the bar **frame** (G/PageUnit.lua:542-544). Compare it to `PageUnit.actionBars.topBar/leftBar/rightBar/bottomBar`; it can also be `stanceBar`, `possessBar`, `friendlyTargetingBar`, `hostileTargetingBar`, `shortcutsBar` (G/PageUnit.lua:553-597).
- `PageUnit:RegisterActiveActionBarUpdatedCallback(callback, owner)` (G/PageUnit.lua:705-707) → `RegisterCallback`; fired from `SetActiveActionBar` with **no arguments** (:527-540). Called as `callback(owner)` inside `securecallfunction` (Blizzard_SharedXMLBase/CallbackRegistry.lua:112-141,207-211); owner must not be a number (:121-122). Call `GetActiveBar()` inside. It fires on every modifier check, also when nothing changed (G/PageUnit.lua:546-599,601-603).
- "Grow": `ShowHighlight` on the active bar, `HideHighlight` on the others (G/PageUnit.lua:530-536; G/ActionBar.lua:79-125). Grow changes **size and frame level only** (bar 266x86 vs 208x68, buttons 40/38 vs 32/30, frame level 5 vs 4, `BackgroundFocus` texture). No SetScale, no SetAlpha. Edit Mode "ShouldExpand" turns it off (G/MainActionBarFrame.lua:135-139).
- Every SetAlpha/Show/Hide on these frames:
  - `PageUnit:SetAlpha(0.35)` on wheel open, `SetAlpha(1)` on close (G/PageUnit.lua:719-737).
  - **Targeting bars reset bar alpha.** Holding LB/RB (Friendly/Hostile/Shortcuts bar) calls `FadeOutInactiveBars`: after the CVar delay `GamepadTargetingModifierVisualDelay`, every shown bar not parented to TopCenteredAnchor gets `UIFrameFade` OUT, which first does `SetAlpha(1.0)` then fades to 0.3 (G/TargetActionBars/Shared.lua:136-169; Blizzard_SharedXMLBase/FrameUtil.lua:337-361). On release `RestoreInactiveBars` does `SetAlpha(1)` on **every** bar in `actionBars`, top bar included (Shared.lua:171-195; callers StaticOverrideActionBar.lua:203,219). **A `.Bar` alpha of 0 will come back after any LB/RB hold longer than the delay.** Nothing in the source ever sets an anchor's alpha.
  - Bar Show/Hide: `RefreshActionBarVisibility` (G/ActionBar.lua:155-183; compact: only active shown, G/PageUnit.lua:656-666), override bars hide `.Bar` and show themselves (G/GamepadOverrideBarMixin.lua:82-114, StaticOverrideActionBar.lua:183-240), on `ACTIONBAR_SLOT_CHANGED` (G/PageUnit.lua:247-252), PEW (G/MainActionBarFrame.lua:378-380). Button alpha: targeting-bar buttons 1/0.3 (StaticOverrideActionBar.lua:139-142).
  - Edit Mode enter/exit only re-runs the active-bar check (Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:1264-1276). The gamepad binding editor hides and re-shows `GamepadMainActionBarFrame` (G/ActionBarEditFrame.lua:282-309). Show/Hide does not touch alpha.
  - Combat and `UPDATE_BONUS_ACTIONBAR`: no alpha calls (G/MainActionBarFrame.lua:385-389, G/StanceBar.lua:33-63 only Show/Hide).

## 5. Glyph pictures and empty bars

- Each button has `ButtonIcon` (InputIconTextureFrameTemplate, the small controller glyph), a child frame of the button (G/ActionBarTemplates.xml:163-171). Shown only on the active bar when Edit Mode "ShowButtonPrompts" is on (G/ActionBar.lua:79-95,110-111; default off, G/MainActionBarFrame.lua:153). `HotKey` is hidden for good (G/ActionBar.lua:28-32). Empty slots show the glyph as `SlotArt` (G/ActionBarButton.lua:483-492). All are children of the button, so they inherit its alpha. Nothing needs hiding on its own.
- Empty bars: `showEmptyBars` defaults true (G/MainActionBarFrame.lua:152; Edit Mode setting :117-121). When off, an empty bar is hidden (G/ActionBar.lua:175-177). The top bar never counts as empty (reserved slots, :195-197).

## 6. Sub-menu buttons and wheels

- `LeftClassAction` / `RightClassAction` (LB+LT, RB+RT) are children of **PageUnit**, anchored to BottomCenteredAnchor at (∓138, -50) (G/MainActionBarFrame.xml:94-113), with prompts at y -80 (:119-138). Fading an anchor or `.Bar` does **not** hide them. They have no `parentActionBar`, so opening their wheel does not dim PageUnit (G/ActionBarButton.lua:737-744; G/ActionBar.lua:34-35 only sets it for bar buttons).
- Wheel (`GamepadSpellFlyout`, pet flyouts): on open it **reparents itself to UIParent and reparents the real button into the wheel** (G/FlyoutRadial.lua:200-224), restored on close (:227-235). So a wheel opened from a faded bar button shows **both the wheel and the real button at full alpha** at that button's screen spot. `SetIgnoreParentAlpha(true)` on the popup (G/PageUnit.lua:726) is moot once it is a UIParent child.

## 7. Other visible leftovers

- No GameTooltip on presses; tooltips only on mouse-over (AB/ActionButton.lua:1114-1130,1447) and inside a wheel (G/FlyoutRadial.lua:387-405).
- `ActionBarFocusFX` animates only regions inside the bar and its modifier icon (G/ActionBarFocusFX.lua:65-97,164-169,347-372). These inherit the alpha.
- Modifier icons (LT, RT, LT+RT prompts) are reparented to their bars (G/PageUnit.lua:123-128) and move to override bars (G/GamepadOverrideBarMixin.lua:73-80), so they fade too.
- **New-spell fly-in** (`IconIntroTemplate`) is a UIParent child drawn at the hidden button (G/IconIntro.lua:62-91,141). It stays visible.
- PageUnit's own shoulder textures (`LeftShoulderBackground` etc.) sit around TopCenteredAnchor but are PageUnit regions (G/MainActionBarFrame.xml:16-52). They stay visible.

## 8. Taint and secrets

- `hooksecurefunc` post-hooks on these instances, globals and regions do not taint Blizzard's path. Reading `button.action`, `GetID()`, regions is safe. Avoid writing fields on Blizzard frames and avoid `AddPageChangeCallback` (section 2).
- Our own Texture under UIParent: `SetTexture` is `AllowedWhenTainted` (DOC/SimpleTextureBaseAPIDocumentation.lua:604-610), and so are `SetVertexColor` and `SetText`. No Blizzard code reads our frames, so nothing can error from it.
- Secret-aware APIs: `GetActionCooldown`, `GetActionCharges`, `GetActionDisplayCount` are `SecretWhenCooldownsRestricted`. `GetActionTexture`, `IsUsableAction`, `HasAction`, `IsCurrentAction`, `IsEquippedAction` are not (DOC/ActionBarFrameDocumentation.lua:147-151,164-210,268-284,467-470,720-754,917-934). Several need a valid slot (`RequiresValidActionSlot`). Guard slot 0 (reserved buttons).
- `issecretvalue`/`canaccessvalue` are not used anywhere in G/ or AB/ (grep). Blizzard relies on secret aspects instead (DOC/SecretAspectConstantsDocumentation.lua:13-40).
- Changing alpha on the anchors/bars in a fight: SetAlpha is not a protected call (device-proven on `.Bar`).

## 9. Sizes

- Bar: 208x68 collapsed, 266x86 grown (G/ActionBarStyles.lua:172-173). Template frame 300x200 (G/ActionBarTemplates.xml:149). PageUnit and main frame 656x202 (MainActionBarFrame.xml:4).
- Buttons: d-pad square 32 → 40, face circle 30 → 38; pressed -4 (G/ActionBarStyles.lua:19-24,158-168). Class buttons always 38 (G/ClassActionFlyout.lua:13-16).
- Button centres relative to the bar centre. Collapsed d-pad L/T/R/B (-92,0) (-58,17) (-24,0) (-58,-17); face (25,0) (55,18) (85,0) (55,-18). Grown d-pad (-119,0) (-75,23) (-31,0) (-75,-23); face (32,0) (70,23) (108,0) (70,-23) (G/ActionBarStyles.lua:180-195).
- Anchors 50x50 at Top (0,58), Bottom (0,-58), Left (-195,0), Right (195,0) of PageUnit (ActionBarTemplates.xml:600-704). Compact layout stacks all anchors on Bottom (G/PageUnit.lua:301-304). The game never scales the bars; size comes from SetSize, plus whatever Edit Mode or our layout does to `GamepadMainActionBarFrame`.

## Recommended approach

1. **Fade the four `*CenteredAnchor` frames, not `.Bar`.** No game code ever sets anchor alpha, while `.Bar` alpha is reset by any long LB/RB hold (Shared.lua:153-188). Anchor alpha also covers StanceBar, PossessBar, targeting bars and the modifier icons, which are anchor children or reparent into anchors. Never touch PageUnit. If `.Bar` must be used, add `hooksecurefunc(bar, "SetAlpha", ...)` with a guard that sets it back to 0, for all 9 `actionBars`.
2. **Which bar to draw:** `RegisterActiveActionBarUpdatedCallback(fn, "PocketFace")`; in `fn` read `GetActiveBar()` and map it to main/LT/RT/both. For a stance or possess bar, mirror that bar's buttons in the slot of the bar it replaces (`GetActionBarLinkedWithOverrideBar()`, GamepadOverrideBarMixin.lua:67-70). For targeting bars, show nothing or a dim state.
3. **Per face button** (32 buttons + stance bar's 8), mirror the real button with as little logic of our own as possible:
   - Icon: `hooksecurefunc(btn.icon, "SetTexture", ...)`, `"SetVertexColor"`, `"SetDesaturated"`, copying the arguments as given. This also covers the shapeshift and flyout paths. Seed once with `btn.icon:GetTexture()`/`GetVertexColor()`/`IsShown()`. For the 4 main-bar face buttons copy `btn.SpecialActionIcon` instead.
   - Count: hook `btn.Count:SetText`, pass the value straight to our FontString.
   - Cooldown: own events `ACTIONBAR_UPDATE_COOLDOWN` (+`SPELL_UPDATE_COOLDOWN`), then `C_ActionBar.GetActionCooldownDuration(btn.action)` → our `Cooldown:SetCooldownFromDurationObject`.
   - Range: hook `btn.RangeIndicator` `Show`/`Hide`/`SetVertexColor`, or tint our icon from `ACTION_RANGE_CHECK_UPDATE`.
   - Checked/flash/proc: `hooksecurefunc(btn, "UpdateState")` then read `btn:GetChecked()`; hook `btn.Flash` `Show`/`Hide`; hook `ActionButtonSpellAlertManager` `ShowAlert`/`HideAlert` and filter on our button set.
   - Pressed: `hooksecurefunc(btn, "ApplyPressedStyle", fn(self, down))` (the probe already does this).
   - Slot/page changes: `hooksecurefunc(btn, "UpdateAction")` then re-seed everything.
4. Hide the whole face while `GamepadMainActionBarFrame` is hidden (binding editor, gamepad off): `HookScript("OnHide"/"OnShow")`.
5. Leave clear space for the two sub-menu buttons (PageUnit children, still visible) and their wheels, which also pull the real button out visibly.

## Unknowns only a device test can answer

1. Does `C_ActionBar.RegisterActionUIButton` make native code set cooldown/checked/usable on the real button without any Lua call (so region hooks miss them)? How often do our hooks fire in a fight?
2. Is `btn.icon:GetVertexColor()` ever secret in a fight? (Constants are written, but branching on a secret `isUsable` might mark it.) Is `GetChecked()` readable?
3. Does `GetActionCooldownDuration` + `SetCooldownFromDurationObject` actually draw a sweep (needs a spell on cooldown)? Does it include charges and loss of control?
4. Do anchor-alpha 0 bars still cast in and out of a fight? (Same as `.Bar`, but not yet proven.)
5. Default value of CVars `GamepadStanceBarOverride` / `GamepadPossessBarOverride` and `GamepadTargetingModifierVisualDelay` on the owner's characters.
6. Does a wheel from a faded bar show the real button where it sat, as the source says?
7. Do C_ActionBar calls with slot 0 error (`RequiresValidActionSlot`) on the reserved main-bar face buttons?
8. Does compact layout (hidden inactive bars) leave stale usable/range state that our face then shows?
