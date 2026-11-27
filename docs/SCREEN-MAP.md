# Screen map: where every piece sits

One page for where things are on the playing screen, who draws each one, and which areas are
kept free. Read it before moving or adding a piece. **A change that moves, adds or removes a
piece updates this page in the same change** (the note beside `Plan.BASE_2` in
`addons/PocketEssentials/ControllerLayout.lua` says the same).

- Written 2026-11-27 for addon 0.21.0, built-in arrangement 2 (`Plan.ARRANGEMENT`).
- The numbers in "Pieces the plan places" are not typed by hand: they are what
  `PE.LayoutPlan.Rects(options)` returns under the offline harness (`tests/lib/fakeclient.lua`)
  with the owner's switches. If this page and that function disagree, the function is right
  and this page is out of date.
- Rows marked "measured" were read off a device screenshot and are good to a few units only.

## The mockup page

There is one mockup page for the playing screen, and new screens are added to it, never to a
new page: https://claude.ai/artifact/B6emNUJNYkzyeQPghzaMAH (a private Design canvas on the
owner's account; its source files are not in this repo). Each screen is 1280 by 720, so a
number on this page times 0.9375 is a pixel there. The owner decides layout changes on that
page before any spec is written.

| Screen on the page | What it shows | State |
|---|---|---|
| Option 1: map stays bottom middle | The playing screen as first designed (2026-11-24) | Built, 0.16.0 to 0.21.0 |
| Option 2: map in the top corner | The same with the map top right | Wanted later |
| Timers: icons bottom left, bars on the right | The Cooldown Manager placed, bars by the target (`#artboard-Timers`) | Approved 2026-11-27; now the alternative |
| Timers: bars on the left, by your name | The same with the bars above your slim bars and the chat ending higher (`#artboard-TimersLeft`) | Chosen 2026-11-27 to build first and try on the device. Redrawn the same day at the game's real sizes: bars and icons at Icon Size 80%, bar width 100%, the tracked buff icons beside the bars. The owner's target for the icons: what the warlock has plus a few, so one row of six large icons and seven small ones, with room kept above for a second row of large ones |
| Direction marks on the spell pictures | Today's mark and two options, at true size and three times larger (`#artboard-Marks`) | The owner picked Option A on 2026-11-27: a cross in a square for the d-pad, four round buttons in a circle for the face buttons, the pressed part gold, 22 px (about 24 units) |
| Target menu: opens above the tooltip corner | The bottom right quarter of the screen: where the target's menu opens today (over the tooltip) and where it is proposed (the same right edge, one menu height higher) (`#artboard-TargetMenu`) | Drawn 2026-11-27, waiting for the owner |

To add or change a screen: read the page's `project/canvas.json` and the screen's file with the
Artifact tool, edit the copies, and publish back to the same link.

## Units

- UI units on a 1365.3 by 768 screen (the size the handheld reports, UI scale 1).
- **Left** and **top** are counted from the screen's top left corner, so a piece at left 10,
  top 20 starts 10 from the left edge and 20 down.
- A 1920 by 1080 screenshot has 1.406 pixels per unit. The 1280 by 720 mockups have 0.9375.
- The code counts differently (x from the screen's centre, y up from the bottom edge). To
  convert: x = left - 682.7, up = 768 - top - height.

## The setup this describes

The owner's, from the saved file of 2026-11-27: Controller layout on, Slim bars on, Map look
Square, Map buttons Shown, Controls reminder On, Spell panel size 100%, Arrange it yourself on,
all three swing timers "In combat". Other switch settings move things (the round map, the
game's unit frames instead of slim bars, larger spell panels); `Plan.Rects` gives those.

## Pieces the plan places

"Layout" means the game places it from our Edit Mode layout "Pocket Essentials" (moved by
rewriting the layout, then a reload). "Addon" means the addon draws or places it itself.

| Piece | Left | Top | Width | Height | Placed by | In Arrange |
|---|---|---|---|---|---|---|
| XP bars | 384.7 | 2 | 596 | 34 | Layout | Yes |
| Controls reminder (the game's input hints box) | 5 | 5 | 200 | 100 | The game; not moved | No |
| Buffs and debuffs (the area; it fills from the right) | 635.3 | 36 | 455 | 88 | Layout | Yes |
| Quest list (taken at its least height) | 1100.3 | 5 | 260 | 400 | Layout | Yes |
| Chat | 17 | 353 | 450 | 170 | Layout | Yes |
| Swing timer, Ranged | 601.5 | 520 | 170.4 | 12 | Layout | Yes, as one piece |
| Swing timer, Off Hand | 601.5 | 534 | 170.4 | 12 | Layout | with the above |
| Swing timer, Main Hand | 601.5 | 548 | 170.4 | 12 | Layout | with the above |
| Map (square, with its edge) | 582.7 | 564 | 200 | 200 | Layout, MapLook.lua | Yes |
| LB+LT and RB+RT buttons | 525.7 and 801.7 | 561 | 38 | 38 | Layout (the game's bars) | Yes, "Spell wheels", up and down only |
| LB+LT and RB+RT prompts | 508.7 and 784.7 | 598 | 72 | 24 | with the buttons | with the buttons |
| LB and RB targeting pictures | 542.7 and 786.7 | 637 | 36 | 32 | Addon | Yes, mirrored pair |
| Slim bar, you | 166.7 | 615 | 280 | 28 | Addon (SlimBars.lua) | Yes, with the pet bar |
| Slim bar, pet | 166.7 | 595 | 136 | 17 | Addon | with the above |
| Slim bar, target | 918.7 | 615 | 280 | 28 | Addon | Yes, with the three below |
| Slim bar, target of target | 1062.7 | 595 | 136 | 17 | Addon | with the above |
| Cast bar (the target's) | 918.7 | 645 | 280 | 12 | Addon | with the above |
| Spell panel, outer left | 299.7 | 669 | 134 | 98 | Addon (FaceBars.lua) | Yes, mirrored pair |
| Spell panel, inner left | 445.7 | 669 | 134 | 98 | Addon | Yes, mirrored pair |
| Spell panel, inner right | 785.7 | 669 | 134 | 98 | Addon | with inner left |
| Spell panel, outer right | 931.7 | 669 | 134 | 98 | Addon | with outer left |
| Tooltip (taken at 200 by 100; it grows up and left from its bottom right corner) | 1155.3 | 658 | 200 | 100 | Layout | Yes |
| PE button (round), default spot | 10 | 529.2 | 76.8 | 76.8 | Addon (Hub.lua) | No; it is in the "Move" window |

The game's four real action bars sit invisible under the inner spell panels (`Plan.RealBarRects`).

## The addon's pieces outside the plan

| Piece | Where | Moved with |
|---|---|---|
| PE button on the owner's handheld | measured: about left 178, top 683, 60 across (they moved it in session 30 of the 11-27 file) | "Move" window |
| Quest arrow | default "top": centred, 43 down, up to 427 wide; four other presets (`QuestArrow.lua:101-107`) | "Move" window, and its own Position row |
| "Press A to type" prompt | centred, 117 above the screen's middle, at least 256 wide; shown for 12 seconds | "Move" window |
| PE windows (settings, chat picker, Arrange, Move) | open in the middle on demand | not placed |

## Areas kept on purpose

| Area | Left | Top | Width | Height | Why |
|---|---|---|---|---|---|
| Target boxes room | 918.7 | 591 | 140 | 21 | One row for the target's buff and debuff boxes, not built yet (`Plan.SLIM.boxes`). It is left of the target of target bar, above the target bar. |
| Pet boxes room | 166.7 | 571 | 280 | 21 | The same for your side, above the pet bar. |
| Bottom right corner | about 1155 | about 560 | to the edge | to the edge | The tooltip grows up from here, and the game's target menu (Interact With Target, Target Marker Icon, Set Focus, Edit Mode) appears here. Put nothing new in it. Which frame the target menu is, is not yet known (handoff 2026-11-27, item 6). |

## Free space today

| Area | Left | Top | Width | Height | Note |
|---|---|---|---|---|---|
| Bottom left corner | 0 | 643 | 300 | 125 | Under your slim bar, left of the outer left spell panel. The owner's PE button sits in it today. |
| Left edge, under the chat | 0 | 523 | 167 | 245 | Left of the pet and your slim bars; joins the corner above. |
| Right side, between the quest list and the target bars | about 919 | about 405 | to the edge | about 185 | Only while the quest list is short: the list is 400 tall at least and grows down with more quests. |
| Left side, between the hints box and the chat | 0 | 105 | about 470 | 248 | Nothing of ours is there. |

## The game's pieces we do not place yet

These show on the handheld and our layout holds no spot for them, so the game puts them at its
own default spots. All positions here are measured from the screenshots of 2026-11-27.

| Piece | Where it lands | Trouble |
|---|---|---|
| Cooldown Manager, two icon rows (`EssentialCooldownViewer`, `UtilityCooldownViewer`) | about left 587 to 779, top 601 to 686 | Straight on top of the map |
| Cooldown Manager, tracked buff bars (`BuffBarCooldownViewer`) | about left 871 to 1202, top 316 to 338 per bar; held by its bottom edge 430 up, 420 right of centre (`Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:850-870`) | Across the quest list |
| Cooldown Manager, tracked buff icons (`BuffIconCooldownViewer`) | a box just above the map | Near the swing timers |
| The game's own cast bar (yours) | about left 576 to 786, top 425 to 448 | None seen |
| A unit frame box in Edit Mode (probably the focus frame) | about left 1084 to 1223, top 388 to 455 | Over the lower quest list when it shows |
| The game's target menu | bottom right | See "Areas kept on purpose" |

Arrange does not offer any of these. Handoff item 7 asks that Arrange cover every piece we
place; when one of these gets a spot in the layout it moves up into the first table.

## Decided, not built yet

From the owner, 2026-11-27 (handoff item 8). These need a mockup, then a spec.

- **PE button** moves to the left of your slim bars (about left 61, top 588, 60 across: level
  with the pet bar and your bar, about 46 clear of them and 61 in from the screen's edge).
  The owner's rule: a buffer from the bars, but never hugging the screen's edge, where the
  edge of a hand holding the device can touch it, which empties the bottom left corner. The
  owner's first idea, beside the Controls reminder box, was dropped the same day.
- **Cooldown Manager icon rows** go into the bottom left corner.
- **Cooldown Manager buff bars:** a column at half width, growing upward, the game's own piece
  with the game's own settings (no upright bars, no drawing of our own for now). Two spots,
  chosen by a row; the piece is also offered in Arrange:
  - **Left, by your name (the owner's preference, later the same day):** its bottom edge above
    the pet boxes room, lined up with your slim bar. They are your own buffs, so they read
    correctly there. Planned for three bars at once, which needs the chat to end a little
    higher; a fourth and more grow up over the chat's lowest lines, and the player moves
    things from there.
  - **Right, by the target (the first mockup, approved):** its bottom edge above the target
    boxes room, lined up with the target bar's left end. Nothing is in its way, but beside the
    target it can be read as the target's buffs.
  - The game has no limit on how many bars can be tracked in the source read so far; how many
    a class can keep running is not known from the source.
- **Open:** whether the target's buff and debuff boxes need more than the one 21-tall row the
  plan keeps today. If they get two rows, the buff bar column starts that much higher.
