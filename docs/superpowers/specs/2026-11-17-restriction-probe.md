# Restriction probe: map what the game allows an addon

Status: approved by the owner in conversation, 2026-11-17 ("yes, this is perfect, build it all out").

## Why

What the Forever client lets an addon do with the Gamepad UI on is known only
from reading Blizzard's source. Two device tests have shown blocks we did not
predict (selling at a vendor, opening the chat box in town). A probe that
tries each action on the device and records the answer replaces guessing
with a table.

The owner plays on a handheld: it must run by itself as far as the game
allows, with as few taps as possible.

## What it is

A separate small addon, `PocketProbe`, kept in `probe/PocketProbe/`. It is not
part of Pocket Essentials, is not in the bundle zip and never goes to
CurseForge. `scripts/build.sh` makes `dist/PocketProbe.zip`, attached to
every GitHub release as its own download, so other addon authors can use it
(owner, 2026-11-17). It needs no other addon and should be run with Pocket
Essentials switched off, so each result belongs to the probe alone.

It saves to its own file,
`WTF/Account/<account>/SavedVariables/PocketProbe.lua`.

## How it runs

One small on-screen button, "Probe", top centre, touch-sized. Nothing else to
set up, no typing, no macro to make.

1. **Automatic passes.** With the probe loaded, a pass runs by itself:
   - a few seconds after login;
   - about one second after a fight starts (the game's lockdown begins after
     the "fight started" event, so not at once);
   - about one second after a fight ends;
   - after each loading screen (so a dungeon gets its own pass);
   - when a vendor window opens (the vendor trials only).
   A pass in the same situation as an earlier one in this session is skipped.
2. **Press passes.** Tapping "Probe" runs the same pass straight from the
   tap. Some game functions only work from a real press, so every result is
   stored under "automatic" or "press". The button can be tapped in a fight.
   This is what a macro would have given; `/probe` does the same for anyone
   who does want it on an action bar.
3. **Clean trials.** A trial can leave the game's interface marked as
   "touched by an addon" until the next reload, which can change the trials
   after it. So the trials most likely to do that are also run one at a time,
   each as the first thing after a reload: the probe runs the next one by
   itself at login, then shows a big "Next (reload)" button. One tap per
   trial; the probe remembers where it is. "Stop" ends the series.
4. A line of text under the button says what it is doing and how many
   situations are covered so far. "Save" reloads so the file is written.

## A situation

Recorded with every result:

- Gamepad UI on or off;
- fight: none, or in a fight (the usual lockdown flag) and, separately, each
  of the game's six addon restrictions (combat, encounter, challenge, PvP,
  map, chat) on or off;
- where: open world, dungeon, raid, battleground;
- which window has the controller's focus, if any;
- how the pass began: automatic, press, or clean.

## A result

For each trial, one of: `allowed` (it ran and the expected thing happened),
`no effect` (it ran with no complaint but nothing happened), `blocked` (the
chat-line kind, with the game's function name and its own stack lines),
`forbidden` (the pop-up kind, with the function name), `error` (with the
message) or `missing` (the function is not on this client).

Found by: the two "blocked" events, a hook on the game's blocked-message
function, the call's own error, and a check afterwards that the thing
happened (chat box showing, item gone, layout changed).

For values: `readable`, `secret`, `nil` or `error`. Only the class is stored,
never the value, so the file holds no names.

## Trials

Safe to run in every pass, and put right again straight after:

| Area | Trials |
|---|---|
| Chat box | open it (`ChatFrameUtil.OpenChat`); open it on a named chat frame; give the edit box focus; set the chat type only, without opening; close it again |
| Our own windows | show and hide a plain window; show one registered for Escape; create a button under our own window |
| Blizzard windows | create a button under the world map, under the bag and under the chat frame; move and resize the bag; open and close the bags |
| Controller | take a button for ourselves (override binding) and give it back; mark one of our buttons for the controller's navigation |
| Bags | sort (`C_Container.SortBags`) |
| Settings | read and write the combined-bags setting back to its own value |
| Layout | read the Edit Mode layouts; set the active layout to the one already active |
| Values | player position and facing, best map, quest log entries and objectives, bag item info, money, repair cost, unit name of the player and of the target, whisper event payload (when one arrives) |

Vendor trials, only with a vendor window open:

| Trial | Cost |
|---|---|
| Sell one grey item with `C_Container.UseContainerItem` (the cheapest one) | one junk item |
| The game's sell-all-junk call (`C_MerchantFrame.SellAllJunkItems`), only if the first did not sell everything | the rest of the junk |
| Repair (`RepairAllItems`), only if something is damaged | the repair bill |

The vendor trials are the only ones that spend anything. They run by
themselves when a vendor opens because that is what the owner asked for; a
"Vendor trials: on / off" switch under the button turns them off.

Clean trials (each alone after a reload): the chat box ones, creating a
button under each Blizzard window, the controller ones, the layout one, and
selling one item.

## What the owner will see

- "Interface action failed because of an AddOn" in chat, at most once a
  session: expected.
- The "blocked from an action" pop-up when a trial is forbidden. It must be
  tapped ("Ignore") on the touchscreen; the controller cannot reach it. The
  probe does not touch it, because doing so would mark more of the interface.
- The chat box opening and closing by itself during a pass.

## Reading it

`scripts/read-probe.sh <file>` prints one table: a row per trial, a column per
situation, the result in each cell, and under it the function names and stack
lines of every block. `--markdown` prints the table ready to paste into
`docs/ARCHITECTURE.md`.

A later step, not in this spec: the offline stand-in game client reads the
table, so the tests block what the device blocks.

## Rules

- Every trial runs inside the probe's own error catcher; one failing trial
  never stops the pass.
- Nothing runs every frame. A pass is a short timed sequence (one trial
  about every 0.3 seconds) and then stops.
- Every game function is looked up in Blizzard's source first, as for the
  main addon.
- The results merge across sessions. If a cell gets two different answers
  both are kept ("allowed / blocked"), so a difference shows.

## Device test (which is the whole point)

1. Switch Pocket Essentials off, load PocketProbe, log in in a town. Wait for
   "pass done".
2. Tap "Probe" once.
3. Pick a fight with something weak. Wait for "pass done", tap "Probe" once
   during the fight, finish the fight and wait for "pass done" again.
4. Open a vendor with a few grey items and damaged gear.
5. Tap "Clean trials" and then "Next (reload)" until it says done (about ten
   taps).
6. If a dungeon is handy, walk in and wait for "pass done".
7. Tap "Save" and send `PocketProbe.lua`.

## Not doing

- No trial that deletes items, spends talent points, trades, mails, or
  targets or casts anything.
- No attempt to get round a block; the probe only reports.
