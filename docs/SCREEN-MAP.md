# Screen map: where every piece sits

One page for where things are on the playing screen, who draws each one, and which areas are
kept free. Read it before moving or adding a piece. **A change that moves, adds or removes a
piece updates this page in the same change** (the note beside `Plan.BASE_2` in
`addons/PocketEssentials/ControllerLayout.lua` says the same).

- Written 2026-11-27 for addon 0.22.0, built-in arrangement 2 (`Plan.ARRANGEMENT`). With every
  0.22.0 row Off the tables are 0.21.0's. A piece or spot marked "while its 0.22.0 row is On"
  exists only then; every 0.22.0 row is Off until the player turns it on (Controller tab, the
  "0.22.0" heading) and none is device-tested yet.
- The numbers in "Pieces the plan places" are not typed by hand: they are what
  `PE.LayoutPlan.Rects(options)` returns under the offline harness (`tests/lib/fakeclient.lua`)
  with the owner's switches (Slim bars, Map look Square, Map buttons, hints, Spell panel size 100%,
  Arrange it yourself On), once with the 0.22.0 rows Off and once with them On. If this page and that function disagree, the function is right
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
| Option 1: map stays bottom middle | The playing screen as first designed (2026-11-24) | Built, 0.16.0 to 0.21.0 (0.19.0 to 0.21.0 reported working) |
| Option 2: map in the top corner | The same with the map top right | Wanted later |
| Timers: icons bottom left, bars on the right | The Cooldown Manager placed, bars by the target (`#artboard-Timers`) | Approved 2026-11-27; built in 0.22.0 as the row "Buff timer bars: Right, by the target", not yet tested |
| Timers: bars on the left, by your name | The same with the bars above your slim bars and the chat ending higher (`#artboard-TimersLeft`) | Built in 0.22.0 (row "Place the game's timers", the default side), not yet tested. Drawn at the game's real sizes: icons and bars at Icon Size 80%, bar width 100%, one row of six large icons and seven small ones, the tracked buff icons beside the bars, room kept above for a second row of large ones |
| Direction marks on the spell pictures | Today's mark and two options, at true size and three times larger (`#artboard-Marks`) | Option A picked 2026-11-27; built in 0.22.0 (row "Bigger direction marks"), not yet tested. Built with squares: five touching squares in a cross for the D-pad, four separate square dots for the face buttons, the pressed part gold, both on a square dark backing, 24 units. No round art could be verified for this client |
| Target menu: opens above the tooltip corner | The bottom right quarter of the screen: where the target's menu opens today (over the tooltip) and where it is proposed (the same right edge, one menu height higher) (`#artboard-TargetMenu`) | Approved 2026-11-27; built in 0.22.0 (row "Target menu above the tooltip", needs Slim bars On), not yet tested. The lift of 174 comes from this mockup |

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
| Your cast bar (the game's own; row "Arrange: cast bar and focus frame" On) | 578.7 | 425 | 208 | 11 | Layout, at the Gamepad preset's spot | Yes, while the row is On |
| Focus frame (the game's own, small size; the same row) | 1068.7 | 377 | 174 | 75 | Layout, at the Gamepad preset's spot | Yes, while the row is On; it overlaps the lower quest list as before |
| PE button (round), default spot | 10 | 529.2 | 76.8 | 76.8 | Addon (Hub.lua) | No; it is in the "Move" window |

Pieces and spots that exist or change only **while their 0.22.0 row is On** (the same numbers,
from `Plan.Rects` with the owner's switches and that row On; none tested on a device):

| Piece | Left | Top | Width | Height | Placed by | In Arrange |
|---|---|---|---|---|---|---|
| Timer icons, large (the game's Cooldown Manager, "Place the game's timers", needs Slim bars) | 41 | 693 | 250 | 40 | Layout; icons 80%, six to a row | Yes, while the row is On |
| Room kept above the large icons (a seventh and more start a second row there) | 41 | 653 | 250 | 40 | Kept free | No |
| Timer icons, small | 111 | 736 | 180 | 24 | Layout | Yes, while the row is On |
| Timer bars, bars on the left (the default side) | 166.7 | 485 | 176 | 82 | Layout; width 100% (stored as 50), growing up | Yes, while the row is On |
| Tracked buff icons, bars on the left | 351 | 535 | 107 | 32 | Layout; beside the bars | Yes, while the row is On |
| Timer bars, bars on the right ("Buff timer bars: Right, by the target"); the large and small icons stay where they are | 918.7 | 505 | 176 | 82 | Layout | Yes, while the row is On |
| Tracked buff icons, bars on the right | 1103 | 555 | 107 | 32 | Layout | Yes, while the row is On |
| Chat, with the bars on the left (it ends higher; 43 above its spot in the main table) | 17 | 310 | 450 | 170 | Layout | Yes |
| PE button, with the timers placed (once moved there; the owner's own moved spot is cleared once) | 61 | 576.2 | 76.8 | 76.8 | Addon (Hub.lua) | No |
| The game's target frame, invisible with Slim bars On, 174 higher so its menu opens above the tooltip ("Target menu above the tooltip") | not in `Plan.Rects` | | | | Layout (piece written from BOTTOMLEFT y 56 to 230); its tap guard moves with it | No |

With "Large spell panels, whole" On, Spell panel size 110% and 120% change as follows (still at
100%: nothing moves). The four diamonds rise by what they were short of the screen's bottom edge
(4.9 at 110%, 9.8 at 120%), so the lowest button ends 1 above the edge; the LB and RB pictures rise
by the same amount; at 120% the slim bars, the cast bar and the boxes rooms rise 9.6 so the cast
bar stays at least 2 above the diamonds' tops. The timer icon rows end further left at 110% and
120% so they stay clear of the outer spell panels (right edge 264 and 238, not 291).

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
| Pet boxes room | 166.7 | 571 | 280 | 21 | The same for your side, above the pet bar. The timer bars (bars on the left) stand on it, 4 above its top, while "Place the game's timers" is On. |
| Bottom right corner | about 1155 | about 560 | to the edge | to the edge | The tooltip grows up from here, and the game's target menu (Interact With Target, Target Marker Icon, Set Focus, Edit Mode) appears here. Put nothing new in it. The menu is the target's ordinary unit menu, pinned to the game's target frame (`TargetFrame.lua:674-676`); while "Target menu above the tooltip" is On it opens one menu height higher, about 191 up and above the tooltip, and the invisible frame's tap guard sits there too. |

## Free space today

| Area | Left | Top | Width | Height | Note |
|---|---|---|---|---|---|
| Bottom left corner | 0 | 643 | 300 | 125 | Under your slim bar, left of the outer left spell panel. The owner's PE button sits in it today. While "Place the game's timers" is On the large and small timer icons fill it (left 41 to 291, down to 760). |
| Left edge, under the chat | 0 | 523 | 167 | 245 | Left of the pet and your slim bars; joins the corner above. |
| Right side, between the quest list and the target bars | about 919 | about 405 | to the edge | about 185 | Only while the quest list is short: the list is 400 tall at least and grows down with more quests. |
| Left side, between the hints box and the chat | 0 | 105 | about 470 | 248 | Nothing of ours is there. |

## The game's pieces, placed only while their 0.22.0 row is On

These show on the handheld whether or not our layout holds a spot for them. With every 0.22.0
row Off the game puts them at its own default spots, as below (measured from the screenshots of
2026-11-27). With the row named in the last column On, they get a spot in our layout and move
up into the second pieces table.

| Piece | Where it lands with its row Off | Trouble | Row that places it |
|---|---|---|---|
| Cooldown Manager, two icon rows (`EssentialCooldownViewer`, `UtilityCooldownViewer`) | about left 587 to 779, top 601 to 686 | Straight on top of the map | "Place the game's timers" (needs Slim bars On) |
| Cooldown Manager, tracked buff bars (`BuffBarCooldownViewer`) | about left 871 to 1202, top 316 to 338 per bar; held by its bottom edge 430 up, 420 right of centre (`Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:850-870`) | Across the quest list | the same row; side chosen by "Buff timer bars" |
| Cooldown Manager, tracked buff icons (`BuffIconCooldownViewer`) | a box just above the map | Near the swing timers | the same row |
| The game's own cast bar (yours) | about left 576 to 786, top 425 to 448 (Edit Mode's box, 12 taller than the bar under it) | None seen | "Arrange: cast bar and focus frame" |
| A unit frame box in Edit Mode (the focus frame; the preset puts it at left 1068.7, top 377, 174 by 75) | about left 1084 to 1223, top 388 to 455 (the box Edit Mode draws is smaller than the 174 by 75 the source gives) | Over the lower quest list when it shows | the same row |
| The game's target menu | bottom right, over the tooltip | See "Areas kept on purpose" | "Target menu above the tooltip" |

With the rows Off, Arrange offers none of these. With "Arrange: cast bar and focus frame" On it
lists the cast bar and the focus frame, and with the timers row On it lists the four timer
pieces.

Two things in the map are still not placed or identified: a small "?" on the square map's left
edge (probably the game's controller button holder, which the source shows as an empty frame; it
is left alone and the log says so), and the target's and the pet's buff and debuff boxes (their
rooms stay reserved).

## Decided, not built yet

What is left of the owner's decisions of 2026-11-27 (handoff item 7 and the open question):

- **Starting arrangements:** rows that choose the default positions before the player adjusts in
  Arrange (for example the map in a top corner, "Option 2" on the mockup page). Not in 0.22.0.
- **Open:** whether the target's buff and debuff boxes need more than the one 21-tall row the
  plan keeps today. If they get two rows, the buff bar column starts that much higher.
- **Open:** the game has no limit on how many bars can be tracked in the source read so far; how
  many a class can keep running is not known, and a fourth timer bar grows up over the chat's
  lowest lines.
- **Open:** a handheld-only profile (handoff item 9) and anything that asks which device this is.

Built in 0.22.0 (see the second pieces table, not yet tested): the PE button's move to the left
of the slim bars (61 in from the screen's edge, the owner's rule of never hugging it), the
Cooldown Manager icon rows in the bottom left corner, the buff bars on the left by your name
(or on the right by the target, chosen by a row), the chat ending higher, and the cast bar and
the focus frame as Arrange pieces.
