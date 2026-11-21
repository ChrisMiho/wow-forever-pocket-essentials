# Quiet bars, the Controller tab and the Quest item button (draft for the owner's approval)

Piece 1 of 3 from `docs/ui-review/2026-11-20-action-bars-gameplan.md`.
Planned version: 0.11.0.

## Why

The owner, on the RP6 at 720p: the game's gamepad action bars are bulky,
"my spell buttons taking up half the screen". They want the bars "really
only during fights", "hide things or make them [see-through]", "possibly
reducing even more when in cities and bring it back into view when buttons
are pushed". "This is for me, what will make playing on the go feel
premium." Later (2026-11-21): the fade should be configurable, "maybe
people want more or less see through, maybe they wanna see them in the
cities", plus "an encouragement note on how to turn on compact".

## Goals

- Spell bars at full strength in a fight, faded or gone outside one, with
  the levels up to the player.
- They come back the moment the player needs them.
- A new settings tab for the controller pieces, each with its own switch.
- Light: no constant ticking, nothing runs while the switch is off.

## Not goals

- Touch players (later, if asked). This piece needs the game's Gamepad UI.
- Moving, resizing or truly hiding the bars (that is piece 3 or not at all).
- Changing Edit Mode settings from the addon, opening Edit Mode for the
  player.
- The pet sub-menus' look (waiting on a screenshot; may join later).

## Anti-goals (a failure even if it works)

- Any "Interface action blocked" message, in or out of a fight.
- A button press that does nothing because a bar is faded.
- A noticeable frame-rate cost.

## Approaches considered

- **A. Change how see-through the bars are (picked by the owner).** The only
  change the game still allows in a fight. The game never sets the bar
  frame's see-through level itself (`GamepadMainActionBarFrame`), so it is
  not fought. Buttons still work while invisible.
- B. Really hide the bars: locked in a fight, gets the addon blamed, and a
  press could not bring them back.
- C. Shrink them outside fights: out-of-fight only, Edit Mode risk, and a
  small bar still takes space.

## The Controller tab

- New tab **Controller**, after Chat. For now it holds Quiet bars only. Quick
  slots and the Controller layout join it, each with its own switch, when
  they are built.
- The tab's dot follows the new three-colour rule (below).

## Quiet bars

Name: **Quiet bars**. Settings line: "Fades your spell buttons when you are
not in combat." Off by default.

**How visible the bars are:**

| When | How visible |
|---|---|
| In a fight | Always full |
| Out of a fight | Option, default 20% |
| In cities and inns (resting) | Option, default 0% (hidden) |
| For a few seconds after a reason to show (below) | Full |

**Reasons to show them in full, out of a fight:**
- A spell button pressed.
- The bar page changed (a shoulder or trigger held).
- An enemy targeted (stays full while the target is an enemy). *My call:
  it brings the bars up before a pull. Easy to drop.*
- The game's override bar replacing the normal one (vehicle, mind
  control): left alone, full.

**Option rows (labels for the owner to check):**
- **Opacity out of combat:** number 0–100, step 10, suffix "%", no unit
  word; 0 reads "Hidden". Help line under the name: "100% is fully shown,
  0% is hidden." Default 20.
- **Opacity in cities and inns:** the same control, no help line. Default 0.
- **Stay visible after a press:** number 2–10, unit "seconds". Default 4.

Player-facing text says "combat", not "fight" (the owner's word,
2026-11-21: "Out of combat opacity").

**Coming back and going away:** full at once on a reason to show; back to
the faded level over about half a second when the time is up.

**Compact tip:** under the options, when the game's Compact setting is off
(read from the bar, never written), one line: "More room: in Edit Mode, tick
Compact on the gamepad bar." When Compact is on, the tip is not shown.

**Fits without a scroll bar** (owner, 2026-11-21: no scroll bars, no extra
tabs, no options removed, shorter text). The tab has no heading card, every
help line and tip is one line long, and the opacity help line ("100% is fully
shown, 0% is hidden.") runs under its row across the card's full width.
Mockup: `docs/ui-review/mockup-0.8.1.html`, "Controller tab" and "Quiet bars
in play".

**Gamepad UI off:** the switch can still be set, but nothing fades; the
card says "Needs the game's Gamepad UI."

**Switching off:** the bars go back to full at once.

## Settings tabs, same release

The owner, 2026-11-21: the left column is full, so "combining the debug and
error log tabs into one, as that's a junk drawer for debug that most people
probably won't go into"; and "we have a green indicator when things are
turned on, what about when things are off? ... a red dot opposite of the
green".

- **Errors and log:** the Errors and Debug log tabs become one tab, named
  "Errors and log" *(my call on the name)*. Catch all errors and the error
  list first, the Debug log card under them. The error count badge stays on
  this tab. A scroll bar here is fine.
- **Tab dots, three colours** (owner, 2026-11-21: "some tabs can have things
  partially on and off ... we need an in between color ... blue, cause yellow
  or orange might communicate a problem when there isn't one"; no grey ring):
  green (.35, .92, .45) when every feature on the tab is on, blue
  (.40, .65, 1) when some are, red (.90, .22, .20) when all are off. A tab
  with one feature is green or red. Tabs with no features (General, Errors
  and log) have no dot.
- The scroll bar is fine where a tab later grows; keep text short anyway.

## Quest item button, same release

The owner, 2026-11-21: "a singular box on the screen if the quest has an
item that needs to be used. I've been clicking the icon in the quest log on
the right, but it's very small." Owner said yes to shipping it with this
release.

- One big button under the quest arrow, for the item of the quest the arrow
  is pointing at (the focused quest). Tap it to use the item.
- Shows the item's picture, its count in the corner and its cooldown on the
  picture, like the game's small tracker icon.
- **Which item** (owner, 2026-11-21: "when nothing is focused or the quest
  focused doesnt have one, it shouldnt show, and when there are more than 2,
  i guess give a small message saying focus the quest you want the item to
  populate for"):
  - Only the focused quest's item gets a button, and only when that item is
    in your bags (the same check the game's tracker icon uses; a finished
    quest's item is left out unless the game marks it as still useful).
  - Nothing focused, or the focused quest has no item: no button.
  - No button, and items for 2 or more other quests in your bags: one short
    line where the button would be, "Focus a quest to get a button for its
    item". *My call:* "more than 2" read as "2 or more"; with only one such
    item, nothing shows. The line follows the arrow's "hide in cities and
    inns" choice.
- Moves with the quest arrow (Move on screen) and follows the arrow's size.
- A choice on the Quest arrow card and in its setup screen: **"Button for
  the quest's item: Show / Hide"**, Show to start. *My call:* it is part of
  the Quest arrow, so with the arrow off there is no button and no new switch
  or dot.
- **In combat** the button keeps working. Which item it holds, and whether it
  is shown, can only change out of combat (the game's rule for addon buttons
  that use items). If the focused quest changes in a fight, the button
  catches up when the fight ends.
- Mockup: "Quest item button".

Builder notes: the game's own tracker icon calls `UseQuestLogSpecialItem`,
which addons may not call; use a secure action button (type "item") set from
`GetQuestLogSpecialItemInfo`, with `GetQuestLogSpecialItemCooldown` for the
cooldown (both in `Blizzard_ObjectiveTrackerShared.lua`). Do not anchor it to
the arrow's insecure frame; place it by position so the arrow stays movable in
combat. Updates come from quest and bag events, no constant ticking.

## Setup guide

*My call, to confirm:* one new screen, "Controller", with the Quiet bars
switch and its options, the same as the settings (shared drawer). Shown to
everyone, like the other screens.

## Constraints for the builder

- Only `SetAlpha` on the bar frame. Never `Show`, `Hide`, `SetPoint`,
  `SetScale` on it, and no `UIFrameFadeIn` / `UIFrameFadeOut` (they call
  `Show`).
- The fade's frame-by-frame update runs only during the half-second fade,
  then stops. Everything else is events.
- Verify every new game name in the Forever source and run the API audit.
- Which frames to fade (main bar only, or also stance, possess and pet
  bars) is for the builder to work out from the source and log.

## Device test (summary)

Fade levels out of a fight, in a city, in a fight; a press brings the bars
back and they fade after the chosen seconds; a page change and an enemy
target bring them back; Compact tip shown and gone; no blocked-action
message in the debug log across a session with fights. Quest item button:
appears for a quest with an item, uses it on tap in and out of a fight, shows
count and cooldown, gone for a quest without one, Hide removes it; with
nothing focused and items for two quests in the bags, the hint line shows.
