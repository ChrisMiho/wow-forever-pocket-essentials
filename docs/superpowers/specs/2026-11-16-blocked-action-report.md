# Report what the game blocks

Status: approved by the owner in conversation, 2026-11-16 ("my main concern
was the errors I was seeing popping up, I think we should start there").

## Why

Fourth device test (PRD): with chat, sell junk and repair on, the game showed
"Interface action failed because of an AddOn" in chat and the "PocketEssentials
has been blocked from an action only available to the Blizzard UI" pop-up,
which the owner could not clear. The game knows which function it blocked
but never shows it, so the cause cannot be found from the screenshots.

## What it does

- `Core.lua` listens to `ADDON_ACTION_BLOCKED` and `ADDON_ACTION_FORBIDDEN`
  (both synchronous, payload: addon name, function name;
  `RestrictedActionsDocumentation.lua`). For our addon only:
  - an entry on the Errors page: "The game forbade/blocked <function> (from
    <File.lua:line>). Features on: <list>.", with our lines of the call
    stack; repeats are counted, not duplicated;
  - one chat line per function per session: "The game blocked Pocket
    Essentials from using <function> (<File.lua:line>). Details in Settings >
    Errors."
- Blizzard's own code also prints the chat message by itself, with no event
  (`DisplayInterfaceActionBlockedMessage`, called by the controller
  navigation's secure checks and by panel opening in combat). Once any
  feature is on, that function is hooked (`hooksecurefunc`, once); if any of
  our code is on the stack at that moment, it is recorded the same way as
  "a protected step of Blizzard's own interface". On this client the
  function prints once but is called every time, so the hook runs on every
  call. Blizzard's own `ADDON_ACTION_BLOCKED` handler also calls it; those
  are skipped there (already reported by the event).
- Safety for the test: if the game refuses a sale (`UseContainerItem`
  triggers a block during the call), sell junk stops for that visit and says
  "The game would not let Pocket Essentials sell items here; stopped
  selling." This keeps the pop-up from coming back every 0.2 seconds. It is
  not the fix; the fix waits for the device report.

## Not doing

- No fix to chat, sell junk or repair yet: the report decides what is wrong.
- No change to the chat window's size or layout (owner: refine it later).

## Approaches

1. Listen to the two events plus hook the Blizzard message (chosen): the
   only way to get the function name and our line on the device.
2. Ask the owner to switch on the game's taint log: writes a file on the
   handheld that is hard to reach.
3. Guess and change chat and vendor code: no evidence, rejected.

## Device test

Turn on one feature at a time (chat, then sell junk, then repair), use it,
and send a screenshot of the chat lines and Settings > Errors.
