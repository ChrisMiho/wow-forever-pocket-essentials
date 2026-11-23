# Controller layout 0.11.1: the clear bugs from the main's screenshots

**Approval.** Draft, 2026-11-23, from `docs/11-23-face-bars/HANDOFF.md` step 2.
Waiting for the owner's go. An update to `2026-11-21-controller-layout.md`.

## Why

On the owner's level 40 main (`docs/11-23-ui-debug/FINDINGS.md`) four things
were plainly wrong, whatever the face bars later decide about where the bars
go: the XP bar stayed at the bottom, the layout did not switch on by itself on
a second character, the map's title strip sits on top of the map, and the
buffs cover the chat's last lines.

## Goals

- Those four fixed, nothing else moved.

## Not goals

- Where the bars go, the both-triggers bar's size and spot, the chat's size,
  the controller hints box. All wait for the face bars mockup.

## Anti-goals

- A player's own Edit Mode layout changed. A layout switch in a fight. Any
  ticking while the feature is off.

## Approaches

- **A. Fix them in the template and the switch (picked).** Small changes in
  `ControllerLayout.lua`'s plan and its switch-on; the plan tests cover them.
- B. Leave the template and let the player move things in Edit Mode. Turned
  down: the owner's point is that it is ready-made.

## 1. XP bar top middle

- `StatusTrackingBar1` and `2` get a spot: `TOP`, `UIParent`, `TOP`, 0, -2
  (the very top edge, centred), Size 10 (100%, was 130%), and `moved = true`.
  The owner (2026-11-23): "i dont read the bar, i really only look to watch
  it fill up, so im cool with the smaller bar that doesnt overlap, but at the
  top like you have it is perfect".
  Bar 2 sits right under bar 1 (`TOP`, 0, -2 - the bar's height; the builder
  finds how the Gamepad preset stacks them in
  `Blizzard_EditMode/Mainline/EditModePresetLayouts.lua` and the status bar
  container's code, and follows that).
- Why the very top: the controller hints box (top left) and the chat (top
  right, whose tabs start about 36 units down) leave a clear strip along the
  top edge. Between them sideways there is only about 580 units.
- **Width.** The probe measured the XP bar at 357.6 units wide (11-22
  EVIDENCE); the 11-23 screenshots look wider (about 770 at 130%, so about
  590 at 100%). 100% keeps it clear of the hints box either way.
- The probe's own button moves down out of its way (probe 0.7.0 spec, 6).

## 2. Switch on per character

The game remembers the active Edit Mode layout per character; our switch is
account-wide. Today `opts.prev` holds one "layout to go back to" for all
characters.

- Not in this build: every setting per character. The owner (2026-11-23):
  "Each character needs its own setup of both pe toggles as well as the ui
  setup ... park it for now, but it comes next as im starting to play more
  characters". 0.11.1 only remembers each character's own old layout.
- `opts.prev` becomes per character: `opts.prevs[<character key>]` with the
  same shape `{ name, layoutType, preset }`. The key is the character's name
  and realm (`UnitName("player")`, `GetRealmName()`; the builder verifies both
  on the forever branch). `opts.prev` is kept for older saved files and read
  once: at the first login on 0.11.1 it becomes the entry of the character
  logging in if ours is active there; otherwise it is dropped (that character
  goes back to the Gamepad preset, as today when nothing is known).
- **Login with the switch On** (out of a fight, through `PE:RunOutOfCombat`):
  - ours active: nothing changes; bars placed, as today;
  - ours not active and this character has **no** entry: remember this
    character's current layout as its entry, make ours active, ask for the
    reload (the same steps as a switch-on);
  - ours not active and this character **has** an entry: the player picked
    another layout in Edit Mode; leave it, status line "Another Edit Mode
    layout is active..." as today.
- **Switch Off** on a character: put back its own entry (or the Gamepad preset
  without one), remove its entry, reload, as today.
- **Login with the switch Off** and this character still has an entry while
  ours is active (it was switched off on another character): put back its own
  layout, remove the entry, ask for the reload. While off the module runs
  only this one login check, then nothing (the builder keeps "nothing ticks
  while off": a one-time check at login, no events kept registered).
- Start over and the option rows are unchanged; they work on the shared
  layout.

## 3. Map title under the map

- The minimap piece gets the setting `HeaderUnderneath = 1`
  (`Enum.EditModeMinimapSetting.HeaderUnderneath`). Proof to confirm:
  `Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua:131`,
  `EditModeSystemTemplates.lua:1794-1795`, and
  `Blizzard_Minimap/Camelot/Minimap.lua:68` (`SetHeaderUnderneath` in the
  Forever client's own map code). Read from the game's Enum like the other
  settings; if missing, the piece is written without it.
- The map's spot is its bottom edge, so a title under it pushes nothing; the
  builder checks the Camelot code for whether the header then sits below the
  map's bottom edge, and if so lifts the map by the header's height so it
  stays clear of the bars or timers under it.

## 4. Buffs clear of the chat

- The chat's last lines reach about 270 units down; the buffs start at 262.
  Move buffs to `TOPRIGHT`, -30, -292, debuffs to -330, the quest tracker to
  -375. Nothing else. The chat box keeps its size. The owner (2026-11-23): "i
  want to try and leave the box as it is, so i can read more than 2/3 chats
  when i increase the font size".

## Tests (offline, `tests/` layout tests)

- Plan: the XP pieces have their spot and size; the minimap has
  `HeaderUnderneath`; the new buff, debuff and tracker spots; a missing
  `HeaderUnderneath` enum leaves it out.
- Switch: two characters in one saved file; login with On on a character
  without an entry switches and remembers; with an entry and another layout
  active it leaves it; Off puts back only that character's own; login with
  Off and a leftover entry puts it back once; an old `opts.prev` is moved
  over or dropped as above; nothing runs in a fight.

## Version

`PocketEssentials.toc` `## Version: 0.11.1`, CHANGELOG entry and a
`docs/TESTING.md` section, together. Features still default off.

## As built (2026-11-23)

What the source showed, and where the build differs from the text above.
File paths are under `Interface/AddOns/` on the forever branch.

### 1. XP bars

- A bar is 17 high (`STATUS_BAR_CONTAINER_HEIGHT`,
  `Blizzard_StatusTrackingBar/Camelot/StatusTrackingBarConstants.lua:2`), so
  bar 2 sits at `TOP`, 0, -19.
- The Gamepad preset stacks bar 2 one bar height **above** bar 1 (offsetY 0
  and 17 on `StatusTrackingBarManager`'s bottom,
  `Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:1441-1461`). At the
  top edge there is no room above, so the build keeps the spec's "right
  under". With a Gamepad layout the game places both bars by their saved spot
  (`Blizzard_EditMode/Camelot/EditModeUtil.lua:5-9` returns no bottom bars).
- Width: with the Gamepad UI a bar at 100% is 596 wide (half of 1192,
  `StatusTrackingBarConstants.lua:1, 12` and
  `Mainline/StatusTrackingManagerOverrides.lua:80-81`). That is close to
  the 11-23 screenshots (about 590) and a little more than the "about 580"
  between the hints box and the chat, so the bar may touch one of them by a
  few units. To check on the device.

### 3. Map title under the map

- `HeaderUnderneath` confirmed (the enum at
  `Blizzard_APIDocumentationGenerated/EditModeManagerConstantsDocumentation.lua:580`,
  the cited display info and system template lines).
- The Forever map code (`Blizzard_Minimap/Camelot/Minimap.lua:68-84`) puts
  the title strip 8 up from the map frame's bottom and the map 30 up from
  that bottom: the mirror of the title on top. The strip stays inside the
  map frame, whose bottom is the spot the template writes, so nothing under
  the map moves and the map is **not** lifted.

### 2. Switch on per character

- `UnitName` (`UnitDocumentation.lua:2489-2503`) and `GetRealmName`
  (`ConnectionDocumentation.lua:69-75`) confirmed. The key is
  `"<name>-<realm>"`. A name that reads as the game's `UNKNOWNOBJECT`
  ("Unknown", early in a login) counts as not readable yet.
- **Added: wait for Edit Mode's layouts.** The game hands Edit Mode its
  layouts through `EDIT_MODE_LAYOUTS_UPDATED`
  (`Blizzard_EditMode/Shared/EditModeManager.lua:193-197`);
  `EditModeManagerFrame:IsInitialized()` (lines 216-218) is true after that.
  A layout list read earlier may be incomplete, and a switch-on saves the
  whole list, which could lose the player's own layouts. So the login check
  runs once both the character's name and Edit Mode's layouts are known;
  until then it waits for the next `PLAYER_ENTERING_WORLD` or
  `EDIT_MODE_LAYOUTS_UPDATED`. If the game has no `IsInitialized`, it goes
  ahead as 0.11.0 did. A tap on the switch goes through the same check (in
  play both are known, so it runs at once).
- **How a module that is off does its one login check.** Core already runs
  every module's `OnLoad` at login, on or off, so no new Core hook was
  needed. While off, `OnLoad` does nothing unless a layout is remembered
  for this character (or the 0.11.0 single entry is still there). If one is,
  it listens on the core's own event list (`PE:RegisterCoreEvent`, as the
  setup guide does for its first `PLAYER_ENTERING_WORLD`), because an off
  module hears none of its own events, and it unregisters as soon as the
  check has run. `Core.lua` changed only in a comment saying modules may do
  this. A player who never used the feature has nothing registered.
- **Login On, ours active, no entry.** Nothing changes in the game, but the
  character gets the entry "Gamepad preset" (as a 0.11.0 switch-on did when
  ours was already active), so switching off there brings back the Gamepad
  preset as the spec says.
- **Login Off with an entry while another layout is active** (spec silent):
  the entry is forgotten, with no reload asked.
- **Reload at a login Off** is asked for only when the layout was changed. A
  tap on the switch still always asks, as before.
- **Old `opts.prev` dropped.** That character then follows the "no entry"
  rule: with the switch on, its current layout is remembered and ours made
  active (the spec's "goes back to the Gamepad preset" read as "the old
  entry is not used for it").
- **No chat line** for a login that switches the layout: the reload request
  shows in the settings window and the setup guide only, as for a tap. The
  owner may not notice it until opening the settings; a chat line would be
  new scope, so it is left as a question.

### Review fixes (2026-11-23)

- **A failed automatic switch-on keeps the switch on.** When the login check's
  switch-on fails or is refused (a game call raises, five account-wide
  layouts, Edit Mode open), the error is logged and the reason shown in the
  status line ("It tries again at the next login."), but the account-wide
  switch stays on and no entry is written for this character, so its next
  login tries again and other characters are left as they are. A failed tap
  still switches the feature back off, as before.
- **Gamepad UI reported late at login.** With the switch on and no entry for
  this character, the feature is blocked when the game does not report its
  Gamepad UI at `PLAYER_LOGIN`, and Core does not try again. The module's
  `OnLoad` then looks once more at the next `PLAYER_ENTERING_WORLD` (one core
  event, unregistered after) and starts the feature if the Gamepad UI reads
  on by then. No Core change.
- **A tap off before the character's name is known** waits for the name and
  keeps the tap's reload request (it used to return as a login check and ask
  none when nothing was changed; it also used to skip the switch-off
  altogether while the name could not be read).

### 0.11.2 (2026-11-23): no character name needed

- On the device the character's name never read: the debug log showed
  "waiting for the character's name" at every login and tap over nine
  sessions, so the check never ran and the layout never switched. Each
  character's layout to go back to now lives in the game's own per-character
  saved file: `## SavedVariablesPerCharacter: PocketEssentialsCharDB` in the
  TOC (as Blizzard's own addons do, e.g.
  `Blizzard_AuctionHouseUI/Blizzard_AuctionHouseUI.toc:4`), at
  `PocketEssentialsCharDB.ctrlLayoutPrev`, same shape. Core loads it with the
  account-wide file (`PE.charDB`). The wait for the name is gone; every other
  rule of section 2 and the review fixes is unchanged.
- Older entries are read once: 0.11.1's `opts.prevs[<name>-<realm>]` for this
  character when its name does read (then removed there), and 0.11.0's
  `opts.prev` as before, now into the per-character file.
- The name is still read for the debug log only: once a session, one line
  says whether it reads, or which part failed ("name secret", "realm secret",
  "name empty", "realm empty", "unknown name", "no function", "error").
