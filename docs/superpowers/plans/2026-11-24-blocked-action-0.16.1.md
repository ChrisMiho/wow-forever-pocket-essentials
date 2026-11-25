# Blocked Action on 0.16.0: Find It, Fix It (0.16.1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Find which line of Pocket Essentials made the game refuse its own `SetPreferredGamepadInteractTarget()` on 0.16.0, remove it, and add an offline check that catches the same kind of mistake before a build goes out.

**Architecture:** Evidence first: the addon's own Errors page already holds the call stack of the block, so the device's saved file is read before any code changes. In parallel, an offline audit lists every place the addon calls a function that Blizzard wrote in Lua (those can leave a mark on the game's own tables; engine calls cannot). The fix is written for the leading suspect and is rewritten at the gate if the evidence names another line.

**Tech Stack:** Lua 5.1 (LuaJIT offline), `tests/lib/fakeclient.lua`, Blizzard's source at `~/.cache/wow-ui-source/forever`.

**Spec:** none. This is a bug hunt, not a feature. If the gate after Task 1 shows the fix is more than removing or replacing one call, stop and write a short spec first (PRD.md rule 7).

## What is known (2026-11-24, from the screenshot and the source)

- Screenshot `docs/11-24-errorsPostWork/Screenshot_20261124-172059.png`: 0.16.0, layout on, Game Menu open, out of a fight. Chat line: "The game blocked Pocket Essentials from using SetPreferredGamepadInteractTarget()". The line is printed once per session, so the screenshot shows when it was noticed, not when it first happened.
- The addon never calls that function. The game does, in `Blizzard_GamepadActionBars/MainActionBarFrame.lua:373` (`UpdateInteractIcons`), on a target change and whenever a window takes or gives back the controller (`InputBindingManager.lua:38-46` calls `UpdateActionBarFocusedState`, `MainActionBarFrame.lua:672`).
- So the game ran its own code "in our name". That happens when the addon has left a mark (taint) on a value the game later reads. It is the same symptom as the chat finding of 2026-11-17 (`docs/ARCHITECTURE.md:405-414`), which lasted until a reload.
- Leading suspect, new in 0.16.0: `ControllerLayout.lua` `PlaceChat` / `RestoreChat` call `FCF_SetWindowAlpha(frame, alpha, true)`. That is a Blizzard Lua function, and it writes `frame.oldAlpha` on each chat window (`FloatingChatFrame.lua:1062`). Called by an addon, the write marks the field; the game's chat code reads it when the chat fades in, and the chat window is one of the windows that takes the controller (`FloatingChatFrame.lua:137-146`). The file's own rule ("writes no field on a Blizzard frame") is broken through that call. Suspect only: not proven.
- The probe would not have caught this. It tries single game calls from clean code; this is an after-effect of what Pocket Essentials itself does. The Errors page stack is the evidence that names the line.

## Update: the saved file was read (2026-11-24 evening)

`docs/11-24-errorsPostWork/PocketEssentials#1.lua`, read with `scripts/read-log.sh`. This replaces Task 1 Steps 1-2 and changes the order of work: **Task 0 below comes first, and Task 3 is on hold** (its suspect is not confirmed).

- 127 refusals in about two minutes, eight different game actions: `SetPreferredGamepadInteractTarget` 92, `ClearTarget`, `SpellStopCasting`, `SpellStopTargeting` 7 each (the B button), `RunBinding` 4 and `DescendStop` 2 (jump), `TargetNearestFriend` 1, `UseAction` 1 (a spell press, through `SecureTemplates.lua:357`). All inside `Blizzard_GamepadActionBars`. So controller presses themselves were refused, not only a picture update.
- Session 3 of the log: every feature on except the Controller layout, from login for 29 seconds: no refusal. The layout was switched on at 00:30:49 and the session ended 17 seconds later in the settings window: no refusal.
- Session 4 (layout on from login, after a reload): first refusal 0.9 seconds after login, on the game's own login refresh.
- Session 5 (layout on from login): login refresh clean, first refusal 11 seconds in, on a target change.
- So the Controller layout (the layout itself or its spell pictures) is the cause, and it is not only something done at login. The chat's box (`FCF_SetWindowAlpha`) is still a `writes` call that should go, but nothing in the file ties it to these refusals.
- No accidental game-wide names: `luajit -bl` shows the addon writes only its slash commands and the compartment function.
- **The recorder hid the answer.** `Core.lua` `BlockStack` keeps six lines when none of ours (outside Core.lua) is on the stack, and four of the six are the recorder's own. Every entry shows two game lines and stops before the caller that would say where the mark came from. The 127 entries also pushed everything else out of the 1000-line debug log.

### Task 0: Make the recorder show the game's callers (0.16.1, first)

**Files:**
- Modify: `addons/PocketEssentials/Core.lua` (`BlockStack`, `RecordBlock`, about lines 1200-1257)
- Test: `tests/features/core_test.lua`
- Modify: `addons/PocketEssentials/PocketEssentials.toc`, `CHANGELOG.md`

**Interfaces:**
- Produces: `BlockStack()` keeps its five results. The lines of `Core.lua`'s own recorder and bare `[C]: ?` lines are dropped before counting; up to 14 of the remaining lines are kept for the debug log and the first 8 for the Errors page. `RecordBlock` writes the "at ..." lines to the debug log only for the first 3 refusals of each function per session; later ones add one line, "blocked: <function> again (x<count>)", at most once a second.

- [ ] **Step 1: Write the failing tests** in `tests/features/core_test.lua`, with a fake `debugstack` that returns the session-4 stack followed by six made-up game lines (`[Blizzard_Gamepad/X.lua]:1: in function 'A'` to `'F'`):

```lua
test("0.16.1: a blocked stack leaves out the recorder's own lines and keeps the game's callers", function()
    local entry = BlockOnce("SetPreferredGamepadInteractTarget()")
    eq(entry.stack:find("PocketEssentials/Core.lua", 1, true), nil)
    eq(entry.stack:find("[C]: ?", 1, true), nil)
    ok(entry.stack:find("in function 'F'", 1, true))
end)

test("0.16.1: the debug log gets the stack three times per function, then one count line", function()
    for _ = 1, 10 do BlockOnce("UseAction()") end
    eq(CountDebug("blocked:   at "), 3 * 8)
    ok(CountDebug("again %(x") >= 1)
end)
```

`BlockOnce` fires `ADDON_ACTION_FORBIDDEN` with the addon's name through the fake client and returns the newest Errors entry; `CountDebug` counts debug lines matching a pattern. Use the file's existing helpers where they exist.

- [ ] **Step 2:** Run `scripts/test.sh`. Expected: both FAIL (the stack holds Core.lua lines; 60 "at" lines).
- [ ] **Step 3:** Change `BlockStack` and `RecordBlock` as the Interfaces block says.
- [ ] **Step 4:** Run `scripts/check.sh && scripts/test.sh`. Expected: exit 0.
- [ ] **Step 5:** TOC `## Version: 0.16.1`; CHANGELOG `## [0.16.1]`, Changed: "The Errors page shows the game's own steps behind a refused action, and the debug log no longer fills with repeats."
- [ ] **Step 6:** Commit: `git commit -m "0.16.1: a blocked action's stack shows the game's callers; repeats are counted, not logged"`

Then Task 2 (the audit), then a device session with this build (Task 1 Step 3): the Errors page will name the caller, and Task 3 is rewritten for it.

### Meanwhile, on the device with 0.16.0 (two minutes, no new build)

1. Controller layout **off**, reload, play two minutes with fights and target changes: no "blocked" chat line expected.
2. Controller layout **on**, reload, do nothing but change target a few times: note how soon the line appears.

## Update 2: 0.16.1 on the device (2026-11-24, 18:06)

`docs/11-24-errorsPostWork/PocketEssentials#2.lua`. The recorder works: every entry shows the game's callers. What they say:

- The refusals come in through unrelated routes: a button binding (`GAMEPADACTIONBUTTON7` > `PressActionButton` > `Click`), the trigger binding (`GAMEPADLEFTTARGETMODIFIER` > `HoldBindings` > `TargetLogic`), a panel closing (`UIParentPanelManager` > `FrameControlsManager` > `InputBindingManager` > `UpdateActionBarFocusedState`), the spell wheel (`GamepadRadial` > `ActivateBindingGroup`), and the targeting bars (`SecureActionButton_OnClick` > `TargetUnit`, 12 times: targeting yourself or the pet).
- No line of ours is on any stack. So this is result C: a mark on something the game's controller code shares, left earlier. A stack shows where the game noticed, never who left the mark, so more stacks will not name the line.
- Ruled out by reading the source: accidental game-wide names (none written); the active-bar callback (`CallbackRegistry.lua:196-216` runs registered functions behind `secureexecuterange` and `securecallfunction`).
- Not ruled out: moving and scaling the game's bar frames, the see-through on their anchors, the hooks on the buttons, the hint box setting, the chat's box, the map's ring and buttons, the targeting pictures, the saved Edit Mode layout.

**Next: split the layout on the device (0.16.2, needs the owner's yes).** `PlaceNow` in `ControllerLayout.lua` does its work in separable parts: `PlaceScreen` (hint box, chat's box, map), the four `Put` calls (the game's bars), `PlaceExtras` (targeting pictures), `StartFace` (spell pictures). A testing row per part on the Controller tab, each On by default, saved per character, read at login. The owner switches one off, reloads, changes target and presses B; the chat line appears or does not. Four reloads at most name the part; the fix is then written against that part alone. Task 2 (the audit) runs alongside and is checked against the answer.

## Global Constraints

- Interface 16001. No libraries. Handlers and callbacks through `PE:Safe` / `PE:Wrap`.
- Bump the TOC `## Version` to 0.16.1 and add the CHANGELOG entry together.
- Every new game call verified in `~/.cache/wow-ui-source/forever`; run `scripts/audit-api.sh` after adding one.
- `scripts/check.sh` and `scripts/test.sh` pass before every commit.
- Work on branch `playing-screen-0.16.0`. No push, no release, no CurseForge without the owner.
- 0.16.0 is not merged to `main` and not posted publicly until 0.16.1 passes the device test.

## Review Focus

1. A chat window made after the layout switched on (a pop-up whisper window): its box may show (already expected), and nothing errors.
2. A box texture the game had already hidden before the layout switched on: switching the layout off does not show it.
3. The layout switched on and off twice in one session: each box texture ends with the see-through it had before the first switch.
4. A chat window whose saved see-through cannot be read (`GetChatWindowInfo` missing or not a number): the value seen before the first change is put back.
5. A client without `CHAT_FRAME_TEXTURES`: nothing changes, one debug line, no error.

Each is a test in Task 3.

---

### Task 1: Evidence from the device (owner, no code)

**Files:** none changed. Notes go in the reply to the owner, and into `docs/TESTING.md` in Task 4.

- [ ] **Step 1: Copy the saved file from the session that showed the error.** On the device: `WTF/Account/<account>/SavedVariables/PocketEssentials.lua` (and `PocketProbe.lua` if the probe was installed). The Errors page is kept across sessions, so it is still there after the restart.

- [ ] **Step 2: Read it.**

Run: `scripts/read-log.sh <PocketEssentials.lua> --errors`
Expected: at least one entry starting "The game blocked SetPreferredGamepadInteractTarget()" with up to six stack lines and "Features on: ...".

- [ ] **Step 3: Second session with the Debug log on.** Play as normal until the chat line appears again. Write down the last three things done before it (opened the chat, pointed at the chat, opened a menu, changed target, tapped the PE button). Copy the saved file again.

Run: `scripts/read-log.sh <PocketEssentials.lua> --grep blocked`
Expected: the "at ..." lines (up to 14 of the game's own lines) for the first block of the session.

- [ ] **Step 4: Gate. Sort the result into one of three.**

| Result | Meaning | Next |
|---|---|---|
| A. A line of ours is on the stack | That call started it directly | Rewrite Task 3 for that line, then go on |
| B. Only the game's lines, and they pass through the chat window (`FloatingChatFrame`, `FCF_`) | The mark left by `FCF_SetWindowAlpha` | Task 3 as written |
| C. Only the game's lines, nowhere near the chat | Another mark | Use Task 2's list to find which call wrote what those lines read; rewrite Task 3 |

---

### Task 2: Offline audit of calls into Blizzard's Lua (can start now)

**Files:**
- Create: `tests/taint/audit.lua`, `tests/taint/calls.txt`
- Modify: `scripts/test.sh` (add the fast check), `docs/ARCHITECTURE.md` (a "Calls into Blizzard's Lua" rule), `docs/TESTING.md` (one line under the offline tests)

**Interfaces:**
- Produces: `tests/taint/calls.txt`, one line per call: `name<TAB>our file:line<TAB>verdict<TAB>reason`. `verdict` is one of `clean` (writes no table field and no global), `writes` (says which field), `ours` (same name, but our own function). `luajit tests/taint/audit.lua` exits 1 and names the call when the addon or the probe calls a Blizzard Lua function that has no line in `calls.txt`.

- [ ] **Step 1: Write the failing check.** `tests/taint/audit.lua` reads every `.lua` listed in both TOC files, collects each called name (`Name(` and `:Name(` / `.Name(`), and keeps those that Blizzard defines in Lua: a match for `function Name(`, `function X:Name(` or `function X.Name(` under `~/.cache/wow-ui-source/forever/Interface/AddOns`, leaving out `Blizzard_APIDocumentationGenerated`. Follow the shape of `tests/api/fastcheck.lua` (same notice and exit 0 when the source cache or luajit is missing). With an empty `calls.txt` it must fail.

Run: `luajit tests/taint/audit.lua`
Expected: exit 1, a list that includes `FCF_SetWindowAlpha  ControllerLayout.lua`.

- [ ] **Step 2: Fill `calls.txt` by reading each function in Blizzard's source.** For each: does it assign to a field of a frame or table, or to a global? `FCF_SetWindowAlpha` is `writes` (`frame.oldAlpha`, `FloatingChatFrame.lua:1062`). Mixin methods called on the game's frames (`GetActiveBar`, the Edit Mode manager's methods) get the same reading.

- [ ] **Step 3: Run it again.**

Run: `luajit tests/taint/audit.lua`
Expected: exit 0, and a printed summary "N calls: X clean, Y writes, Z ours".

- [ ] **Step 4: Add it to `scripts/test.sh`, write the rule into `docs/ARCHITECTURE.md`:** "Before calling a function Blizzard wrote in Lua, read it. If it writes a field on a frame or table of the game's, do the same thing with the frame's own engine methods instead. Every such call is listed in `tests/taint/calls.txt`."

Run: `scripts/check.sh && scripts/test.sh`
Expected: both exit 0.

- [ ] **Step 5: Report every `writes` line to the owner in plain words, then commit.**

```bash
git add tests/taint scripts/test.sh docs/ARCHITECTURE.md docs/TESTING.md
git commit -m "Offline audit: every call into Blizzard's Lua is listed with what it writes"
```

---

### Task 3: The fix, 0.16.1 (as written for result B; rewrite at the gate for A or C)

**Files:**
- Modify: `addons/PocketEssentials/ControllerLayout.lua` (`PlaceChat`, `RestoreChat`, the comment above them, about lines 1484-1565)
- Modify: `tests/lib/fakeclient.lua` (count calls to `FCF_SetWindowAlpha`; box textures remember alpha and shown)
- Test: `tests/features/layout_test.lua`
- Modify: `tests/taint/calls.txt` (the `FCF_SetWindowAlpha` line goes), `addons/PocketEssentials/PocketEssentials.toc`, `CHANGELOG.md`, `docs/ARCHITECTURE.md`

**Interfaces:**
- Consumes: `tests/taint/audit.lua` from Task 2.
- Produces: `PlaceChat()` and `RestoreChat()` keep their names and callers. Neither calls any `FCF_` function. `chatFound` changes meaning: `[texture] = { alpha = number, shown = boolean }`, read with the texture's own `GetAlpha` and `IsShown` before the first change.

- [ ] **Step 1: Write the failing tests** in `tests/features/layout_test.lua`:

```lua
test("0.16.1: the chat's box is hidden without calling FCF_SetWindowAlpha", function()
    local c = Client({ layoutOn = true })
    eq(c.calls.FCF_SetWindowAlpha or 0, 0)
    eq(rawget(c.G.ChatFrame1, "oldAlpha"), nil)
    eq(c.G.ChatFrame1Background:IsShown(), false)
end)

test("0.16.1: layout off puts each box texture back as it was found", function()
    local c = Client({ layoutOn = false })
    c.G.ChatFrame1Background:SetAlpha(0.4)
    c.G.ChatFrame1TopTexture:Hide()            -- hidden by the game beforehand
    c:SetLayout(true); c:SetLayout(false); c:SetLayout(true); c:SetLayout(false)
    eq(c.calls.FCF_SetWindowAlpha or 0, 0)
    eq(c.G.ChatFrame1Background:IsShown(), true)
    eq(c.G.ChatFrame1Background:GetAlpha(), 0.4)
    eq(c.G.ChatFrame1TopTexture:IsShown(), false)
    eq(rawget(c.G.ChatFrame1, "oldAlpha"), nil)
end)

test("0.16.1: no CHAT_FRAME_TEXTURES on this client: nothing changes, no error", function()
    local c = Client({ layoutOn = true, without = { "CHAT_FRAME_TEXTURES" } })
    eq(#c.errors, 0)
    eq(c.G.ChatFrame1Background:IsShown(), true)
end)

test("0.16.1: a chat window made after the layout is on is left alone without error", function()
    local c = Client({ layoutOn = true })
    c:AddChatWindow(11)
    c:SetLayout(false)
    eq(#c.errors, 0)
end)
```

Use the file's existing helpers under their real names where these differ (`Client`, `SetLayout`, `eq`, `test`); add `AddChatWindow` and the `without` option to the fake client if missing. The existing test that expects a call to `FCF_SetWindowAlpha` is replaced by the first one above.

- [ ] **Step 2: Run them, see them fail.**

Run: `scripts/test.sh`
Expected: FAIL on the four new tests (call count 2 or more, `oldAlpha` is 0).

- [ ] **Step 3: Change `PlaceChat` and `RestoreChat`.** For each window and each name in `CHAT_FRAME_TEXTURES`: on first sight store `{ alpha, shown }`; then `SetAlpha(0)` and `Hide()` on the texture itself, each in a `pcall`. Restore: `SetAlpha(alpha)`, and `Show()` only where `shown` was true; then empty the stores. Drop `GetChatWindowInfo` from this code (the saved value is no longer needed: the game sets it again itself, `FloatingChatFrame_Update`, 488-498). Rewrite the comment block to say why no `FCF_` function is called, with the date and this plan's path.

- [ ] **Step 4: Run everything.**

Run: `scripts/check.sh && scripts/test.sh && scripts/audit-api.sh`
Expected: all exit 0; `tests/taint/audit.lua` passes with the `FCF_SetWindowAlpha` line removed from `calls.txt`; `tests/api/verified.txt` no longer lists `FCF_SetWindowAlpha` or `GetChatWindowInfo` unless another file uses them.

- [ ] **Step 5: Version and documents.** TOC `## Version: 0.16.1`. CHANGELOG `## [0.16.1] - 2026-11-24`, under Fixed: "The game refused its own controller actions in Pocket Essentials' name while the Controller layout was on ('Interface action failed because of an AddOn'). The layout now hides the chat's dark box without the game function that caused it." `docs/ARCHITECTURE.md`: add the finding under the chat rules, dated, marked "not yet confirmed on the device".

- [ ] **Step 6: Commit.**

```bash
git add addons/PocketEssentials tests CHANGELOG.md docs/ARCHITECTURE.md
git commit -m "0.16.1: the chat's box is hidden without FCF_SetWindowAlpha (the game refused its controller actions in our name)"
```

---

### Task 4: Device test of 0.16.1, then the probe run

**Files:**
- Modify: `docs/TESTING.md` (new section "31. Version 0.16.1: the blocked action", after section 30)

- [ ] **Step 1: Build.**

Run: `scripts/build.sh`
Expected: `dist/PocketEssentials-0.16.1.zip` and `dist/PocketProbe.zip`.

- [ ] **Step 2: Write TESTING section 31** (use the `wow-addon-skills:device-test-handoff` skill). Its steps, in order:
  1. Install 0.16.1 only (no probe folder). Debug log on, Catch all errors on, Controller layout on. Reload once.
  2. Twenty minutes of normal play that includes: opening the chat with the controller and typing, pointing at the chat, opening and closing the Game Menu five times, changing target, one fight, looting.
  3. Is "Interface action failed because of an AddOn" or "The game blocked Pocket Essentials" ever shown? Screenshot it at once and say what was done just before.
  4. Section 30's steps 4 and 10 again (the dark box stays gone; layout off puts it back).
  5. Send the saved `PocketEssentials.lua`.
  6. **Separate session, for 0.17.0:** add the `PocketProbe` folder, switch the Controller layout off, reload, then Run all and the Fight button as in section 30. Send `PocketProbe.lua`. Layout off keeps anything the probe is refused apart from anything Pocket Essentials causes.

- [ ] **Step 3: Commit, then stop for the owner.** A GitHub pre-release (both zips) only when the owner says so.

```bash
git add docs/TESTING.md
git commit -m "TESTING 31: 0.16.1, the blocked action, and the probe run with the layout off"
```

- [ ] **Step 4: Read the results.**

Run: `scripts/read-log.sh <PocketEssentials.lua> --errors` and `scripts/read-probe.sh <PocketProbe.lua> --markdown`
Expected: no "blocked" entry from the 0.16.1 session. If there is one, go back to Task 1 Step 4 with the new stack; do not guess a second fix.
