# Error catcher and probe panel

**Status:** draft. It waits for the owner's OK on the mockups (the "Probe panel" and "Error catcher" views in `docs/ui-review/mockup-0.8.1.html`, Proposed).

**Owner (2026-11-20):** "we need another feature to make managing bugs easier ... since the blizzard ui clearly has bugs"; "is it possible to add a check to see if the other addon is enabled"; "can this bug grabber also help navigate the popups ... almost working like how bugsack works"; "can any of this be automated through the probe ... it doesnt just automatically fire when i login, maybe we build a tad nicer ui for me to drive our tests with".

Research is in this session's notes. The sources are `Blizzard_ScriptErrors.lua:71-101` and `Blizzard_ScriptErrorsFrame.lua:43-141` on the forever branch. The research is summarised in the "Facts" below.

**Order of work:** Part 1 (the probe) ships first, as a test build. The owner runs it once. Part 2 (the error catcher) is then built on the ways the probe shows to work.

## Facts this relies on (from the forever source; the device confirms them through Part 1)
- **Blizzard's handler:** Blizzard installs the error handler with `seterrorhandler(HandleLuaError)`. Addons cannot register with `AddLuaErrorHandler` (it requires secure code).
- **Where errors land:** every Lua error and every `LUA_WARNING` ends at `ScriptErrorsFrame:DisplayMessageInternal(message, messageType, stack, locals)`. An addon can post-hook it with `hooksecurefunc` without replacing Blizzard's handler.
- **The error box:** it shows only when the CVar `scriptErrors` is on. In the Gamepad UI it takes the controller focus. After 1000 errors the game shows its own "too many errors" popup whatever that CVar says.
- **Secret text:** error text from tainted code can be secret, so check `issecretvalue` before any use.
- **Other error addons:** they can be spotted with `C_AddOns.IsAddOnLoaded` and the globals `BugGrabber` / `BugSack`.

## Shared rule (all settings rows)
**Choices that do not fit grow wider.** A choice row's control grows past the usual width (`min(inner*0.58, button*9)`) when its labels need it. It can grow up to the row width minus the row name's width (never less than 30% of the row) minus a gap. A long name then wraps rather than a choice being cut off. Owner, 2026-11-20: "the text is cutoff on the second button, we have deadspace on the left side".

## Part 1: Pocket Probe 0.3.0 (testing only, ships as PocketProbe.zip)

**No more automatic runs.**
- Nothing runs by itself at login. The old passes sit behind an **Auto** switch that starts Off.
- The listeners that only record blocks stay.
- `/probe` and the small "Probe" button open the panel.

**The panel** stays standalone: no Pocket Essentials code. It copies only PE's sizes and colours, so it looks the same.
- **No scroll bar** (owner, 2026-11-20: "id really like to avoid having a scroll bar on the screen if possible, the side pannel really helps avoid that"). An area with more trials than fit becomes two tabs; it never scrolls.
- **Window:** the same size as the Settings window (`min(screenW*0.96, Px(1180))` × `screenH*0.92`), centred, titled "Pocket Probe 0.3.0", with Close.
- **Rows:** `button + gap*0.3` tall, with one border between them.
- **Left:** area tabs.
  - The existing areas: Our own windows, Blizzard windows, Chat box, Bags, Vendor, Controller, Layout, Settings, Values.
  - New: **Errors** and **Graphics**.
  - Each tab shows a count, for example "5 / 7 run".
- **Right:** one row per trial:
  - its label;
  - a result chip: **Allowed** (green), **Blocked** (amber), **Not run** (grey), or the value read;
  - a **Run** button, which runs the trial straight from the tap;
  - risky trials are marked "risky" and are dimmed while Risky is Off.
  - Tapping a row shows its details (function, message, short stack) in a line at the bottom.
- **Footer:** Run all safe · Clean run (reloads) · Risky: On/Off · Vendor: On/Off · Auto: On/Off · Save (reloads).
- **Guided trials** show their own two buttons in place of Run (for example "Sparkles seen" / "No sparkles"), and the owner answers after looking.
- **Controller:** the d-pad and touch work as in Pocket Essentials.

**New trials, area Errors.** These record only classes, counts and sources, never error text from other addons and never `locals`.
1. **Handler:** `geterrorhandler` and `seterrorhandler` exist; the handler is a function.
2. **Error box:** `ScriptErrorsFrame` and `DisplayMessageInternal` exist; `errorData` is readable or secret.
3. **Hook:** the hook installs; a probe test error (`C_Timer.After(0, error)`) reaches it; whether the message and stack are readable; whether the box showed.
4. **Others' errors seen:** the number of errors this session not from the probe, by source (Blizzard / addon name), plus the `LUA_WARNING` count.
5. **Hide the box:** reads `GetCVarInfo("scriptErrors")` (value, isSecure, isReadOnly, locked). Writing it back unchanged must succeed. Then, set to 0: a test error does not show the box. The old value is put back.
6. **Own handler (risky):** a chained `seterrorhandler` sees a test error and Blizzard's box still works. The old handler is put back.
7. **Blocked actions of others:** a count of `ADDON_ACTION_BLOCKED/FORBIDDEN` naming other addons.

**New trials, area Graphics** (answering why the sparkles do not show on the handheld):
1. **Read:**
   - `C_VideoOptions.IsOutlineModeSupported()` and `IsSpellVisualDensitySystemSupported()`;
   - the values, defaults and info of `outlineModeShowLootEffectWhenDisabled`, `graphicsOutlineMode`, `raidGraphicsOutlineMode`, `OutlineEngineMode`, `graphicsSpellDensity`, `graphicsParticleDensity`, `graphicsQuality`, `SoftTargetLowPriorityIcons`, `SoftTargetInteract`.
2. **Write:** the sparkle CVar is written back unchanged, then set to 1 and read back.
3. **Names:** the names from `ConsoleGetAllCommands()` that match outline / loot / sparkle / particle / spell (names only).
4. **Guided, Outlines off:** saves the old values, sets `graphicsOutlineMode` and `raidGraphicsOutlineMode` to 0 and the sparkle CVar to 1, then says "Fully restart the game, kill something, then come back here." After the restart it asks "Sparkles seen" / "No sparkles", and puts the old values back once answered.
5. **Guided, Interact icons:** saves the old value and sets `SoftTargetLowPriorityIcons` to 1, then "Look at a lootable corpse:" "Icon seen" / "No icon". Puts it back.

**Stays the same:** the probe's saved file, `read-probe.sh` (extended for the new ids and the guided answers), its tests, and the build keeping the probe out of the player zips. The version moves to 0.3.0, which clears old results.

## Part 2: Error catcher (Pocket Essentials feature, built after Part 1's device run)

**The feature:** key `errors`, name **Catch all errors**, line "Keeps every Lua error, from the game and other addons, in one list here." It is the Errors tab's first card, and is off by default.

**Debug log is a separate feature** with its own tab, **Debug log**, after Errors (owner, 2026-11-20). It holds today's debug log card unchanged: the switch, the help line, the line count, and Save the log / Empty the log. The Errors tab holds only the catcher and the viewer. The settings now have 9 tabs; tab height is `min(button, (contentHeight − 8*border) / 9)`.

**Standing aside:**
- At login, if BugGrabber, BugSack or Swatter is loaded (or someone replaced the error handler), the feature does nothing. Its switch is drawn disabled and reads Off.
- The card says why, in amber: "Off while BugSack is loaded: BugSack takes the errors before they reach this list." It uses the name actually found.
- And how to choose ours, in dim text: "To use this instead, turn BugSack off in the AddOns list and restart."
- **No override switch** (owner asked, 2026-11-20). BugGrabber takes errors before they reach the game's error popup, which is where we listen, so an override would catch nothing. Pocket Essentials never switches another addon off.

**Catching:**
- The hook from Part 1, trial 3. If the device shows the hook does not work, use the chained handler from trial 6.
- Back-fill from the error box's list at login.
- Each error is named by its source: Blizzard (`Blizzard_*`), Pocket Essentials (goes into our own list), an addon name, or "Macro or script".
- Others' errors are kept apart from ours in their own list, capped at 50. Dedupe on source + message + first stack line. A stack keeps up to 8 lines. `locals` are never stored.
- A secret message shows as "(the game hides this message from addons)".

**Hiding the game's popup:** the row **Error popup: Show / Hide**, with the grey help line "Hidden errors still show in this list." (owner's pick, 2026-11-20). Hide sets `scriptErrors` to 0 and saves the old value; switching the feature off puts it back.

**The viewer** (the Errors tab's second card, BugSack style, one error per page):
- A filter row: **All / Pocket Essentials / Blizzard / Other addons**.
- The page: the source in gold, "x3 · 23:11" on the right, the message (white, wraps), and the stack (dim, small).
- The bottom row: **◀ Previous**, "3 of 12", **Next ▶**, and **Clear all**. With the d-pad, Left and Right move between errors.
- **Switch off, or another error addon present:** Pocket Essentials still lists its own errors, as it always has. The filter row is hidden, and a dim line says "Only Pocket Essentials' own errors are listed while this is off."
- When empty: "No errors recorded."
- **No scroll bar:** the message shows at most 3 lines and the stack at most 6 lines. Longer text is cut at the edge, and the full text stays in the saved file. The Errors page must fit at every button size without the scroll bar.

**Reading:**
- `read-log.sh` prints the others' list grouped by source.
- The chat line for others' errors is at most once per session, and off while the box is hidden.

**API:** `hooksecurefunc` on the frame, `ScriptErrorsFrame`, `C_CVar.GetCVarInfo`, `LUA_WARNING`, `C_AddOns.IsAddOnLoaded`, `geterrorhandler`. Run the audit; the last one is undocumented, so it is logged as unverified.

**Tests:**
- standing aside
- sources
- dedupe and the cap
- secret text
- the box hidden and put back
- the viewer: filter, previous and next, the count, clear, and the d-pad
- the reader
