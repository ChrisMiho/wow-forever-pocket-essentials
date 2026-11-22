# Action bars and screen space: game plan (draft, 2026-11-20)

Not a spec. A starting point for the owner to refine. Nothing is built.

## The owner's goal

The game's gamepad action bars (the d-pad and face-button clusters at the
bottom middle) are bulky on a 720p handheld. The owner wants more of the
screen for the game and less for spell buttons, and has their own ideas for
a more phone-like (mobile) layout.

## What the code and the game allow

- **The bag was the easy case.** Our "Bag window" is Blizzard's own bag,
  made bigger and tidied. Bag frames are not protected, so we can move and
  resize them at any time.
- **Action bars are the hard case.** Spell buttons are protected. In a
  fight the game freezes them: an addon cannot move, resize, show or hide
  them until the fight ends. What still works in a fight: changing how see-
  through they are, and rules set up *before* the fight ("show this only in
  combat", "show this while a shoulder button is held").
- **The game already has options for these bars.** In Edit Mode, the
  gamepad main action bar has five checkboxes in this build's source
  (`Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua:1517`): Compact,
  Show empty bars, Button prompts, Highlight, Expand. Not tried on the
  device yet.
- **Known risk:** when an addon changes Edit Mode or the game's own bar
  positions, the game can later blame the addon in a fight ("Interface
  action blocked"). That is why the Layout helper was dropped in 0.3.0.
- **PRD non-goal:** "Replacing or fighting Blizzard's gamepad support (no
  ConsolePort unless a player asks)". Building our own bars needs the owner
  to lift this.

## Three ways to do it

| | What it is | Cost | Risk |
|---|---|---|---|
| A. Game's own options | Try Edit Mode's gamepad bar checkboxes. No code | Minutes | None |
| B. Tidy the game's bars | Fade them out of fights, hide button pictures and empty slots, smaller, a drawer for out-of-fight spells | Medium | Medium: needs a probe run first |
| C. Our own bars | Our own spell buttons laid out for thumbs, any size or shape | Large | High: protected buttons, bindings only out of fights |

Recommendation: A first, then B in small steps. C only if B is not enough.

## Steps

1. Owner tries the Edit Mode checkboxes and sends a screenshot (no code).
2. Pocket Probe round: what we may change on the gamepad bars, in and out
   of a fight (fade, size, hide pictures, a drawer of our own buttons).
3. Mockups at 720p, Today vs Proposed, on the mockup page.
4. Spec, plan, build, device test. One piece at a time.

## Owner's answers (2026-11-20)

1. Size is the problem. Empty buttons will not exist at high level, so show
   less at once. Even less in cities; back into view when buttons are
   pressed; maybe a fade. Chat feels small and the bars clash with it.
   Open to a new layout: minimap bottom centre with the buttons around it,
   chat where the minimap was, buffs and debuffs slid over. The pet
   sub-menus are loved but should look sleeker and smaller. "This is for
   me, what will make playing on the go feel premium."
2. Controller. Fine to call it a controller-optimised theme; touch players
   can come later. RP6 only for now. Asks whether the RP6 back buttons can
   be bound (extra binds for warlock). The game knows four extra
   buttons (`PADPADDLE1` to `PADPADDLE4`); whether the RP6 sends them
   through Droid Deck is a device check.
3. Bars only during fights. Professions sit on the second page; its
   sub-menus are empty. Hiding or fading is a huge win.
4. Tidy first, whatever is lighter.
5. Spell drawer: "10000% yes". Mount, hearth, food, sleeping bag, campfire
   (Forever's new mechanic), sharpening stones, poisons, pet summons.
   Could be long, must stay light.

Proposed order (three pieces, each its own spec and device test):
1. Quiet bars (fade, hide in cities, back on press or in a fight).
2. Kit drawer (the spell drawer).
3. Controller layout (minimap, chat, buffs moved). Mockups first.

Owner agreed the order (2026-11-21) and asked for a new settings tab with
its own switch for each piece, so Quiet bars and the layout can be turned
on separately.

Found in the source: the game's Edit Mode "Compact" checkbox on the
gamepad bar shows only the page you are on and hides the others
(`ActionBar.lua:171`, `PageUnit.lua:292`). The game never sets the bar
frame's see-through level itself (`GamepadMainActionBarFrame`), so a fade
from us would not be fought.

## Five questions (with recommended answers)

1. Your ideas, and what is in your way? Recommended: bars first, then the
   two "Ranged / Main Hand" bars and the controller hint box top left.
2. Do you cast with the controller or by tapping? Recommended: controller;
   the screen only needs cooldowns.
3. When must the bars be on screen? Recommended: full in a fight, faded
   to about 20% out of a fight, back to full while a shoulder button is
   held.
4. Tidy the game's bars or build our own? Recommended: tidy first.
5. A spell drawer, like the bag, for mount, hearthstone, food and
   professions, opened from the round button, closed in a fight?
   Recommended: yes, after the fading.

## Kit drawer, first mockup (2026-11-21)

Quiet bars mockup approved by the owner ("functionally this is perfect for
gameplay"); spec `docs/superpowers/specs/2026-11-21-quiet-bars.md`, waiting
on the owner's go for the plan. The owner then asked for the next mockup
while away. Mockup view "Kit drawer"; its card is on the Controller tab.

My calls in the mockup, for the owner to check:
- Filled by itself from bags and spellbook, four tabs: Travel, Camp, Weapon,
  Pets. Nothing to drag or set up.
- Opens with a binding of our own in the game's Key Bindings (an addon
  `Bindings.xml`), so a back button works if the game sees it. Closes when
  combat starts, cannot open in combat.
- Weapon tab: "Put it on: Main hand / Off hand", then one press applies the
  stone or poison. Source: `Blizzard_FrameXML/SecureTemplates.lua:771`
  (`target-slot` after a spell that targets an item).
- Options: "Open with" (Key Bindings > Pocket Essentials), "After you use
  something: Close / Stay open", "Size of the drawer" 70–150%.
- Cooldowns shown on the icon; a tile on cooldown does nothing.

Open questions: what to do about items the auto-fill gets wrong (hide one?
pin one?), whether the round button should also open it, and the real names
of Forever's camping items.

### Owner's answers on the Kit (2026-11-21)

1. "Can we have the player set it up actually? This avoids incorrect auto
   setup altogether." The kit is player-filled: + opens a picker of bag items
   and spellbook spells; "any item from my bag, not even just the usual
   consumes".
2. No new on-screen piece: "if the bottom of the chat box could double as
   the bin, while still supporting the chat feature". The kit sits under the
   chat buttons in the round button's window; with Chat picker off, PE opens
   the kit alone. No key binding for now ("maybe two clicks is easy enough").
3. Camping names (looked up): Cozy Sleeping Bag (item), camps start from a
   Cooking fire (Basic Campfire). With a player-filled kit the names no
   longer matter to the code.
4. "This new drawer feature is very experimental": built to be tried.

New idea from the owner: "a singular box on the screen if the quest has an
item that needs to be used. I've been clicking the icon in the quest log on
the right, but it's very small." Mocked as "Quest item button": one big
button under the quest arrow for the focused quest's item, a Show / Hide
choice under Quest arrow. `GetQuestLogSpecialItemInfo` and
`GetQuestLogSpecialItemCooldown` exist in the Forever source.

Builder notes: kit slots and the quest item button are secure action
buttons. They can only be created, changed, shown or hidden out of combat,
so the kit is hidden in combat (chat still works). The kit must not be
anchored to the chat window (a protected frame anchored to ours would make
our window protected in combat); place it by position instead.

### Kit and chat in combat (owner, 2026-11-21)

"The kit should be accessible in combat, just like the chat, with the
ability to turn it on and off, as the chat should, to prevent accidental
clicks but to enable people that want those features while in combat."
Mocked: "Kit in combat: Allow / Block" (Controller tab) and "Chat picker in
combat: Allow / Block" (Chat tab), both Allow to start (my call; chat works
in combat today). Both on Block: PE does nothing in combat. In combat the kit
slots work; adding and removing wait until after combat.

The catch (to test with Pocket Probe before building): opening a window of
addon buttons in combat needs a "secure" tap. So the round button would
become a secure button, and then the game freezes it in combat too: it could
not hop onto the map's book icon or be moved during a fight. Chat in combat
is unaffected (it works today).

### Name (owner, 2026-11-21)

"Kit" is now **Quick slots** (owner asked for "quick bar or something";
"Quick bar" was too close to "Quiet bars" on the same tab; owner: "quick
slots works"). Window title "Chat and quick slots", "Edit slots", setting
"Quick slots in combat: Allow / Block".

### Owner's answers on the two open questions (2026-11-21)

1. Quest item button ships with Quiet bars (0.11.0): yes. Added to the
   Quiet bars spec.
2. Round button becomes a secure button, fixed in place during combat, so
   Quick slots work in combat: yes. Pocket Probe test first, then the Quick
   slots spec.

### Fewer slots (owner, 2026-11-21)

"This is too many quick slots, i think we need to simplify it to just 3-4?
with the ability to configure more in the settings." Mocked: four slots to
start, one row; option "Number of slots" (2 to 12) first on the Quick slots
card; up to six per row, so fewer slots get bigger squares (capped). Empty
slots are faint squares, + on the first one. Slots past the number are kept,
just not shown (my call). The Controller tab now scrolls a little with both
cards (owner, earlier: a scroll bar is fine once more is added).

## Controller layout, piece 3 (2026-11-21)

Mockup view "Controller layout" (Today / Proposed). Nothing is built.

Found in the source (build 1.60.1.70938):
- The minimap, chat, buffs, debuffs and the gamepad bars are all Edit Mode
  pieces, so a player can drag them by hand. Only the gamepad bars are locked
  in combat (their buttons are spell buttons).
- The game has four gamepad bars, not pages: no trigger (top), left trigger,
  right trigger, both triggers (bottom). `PageUnit.lua:108`, `:546`.
- Each bar is built as two blocks, `Left` (d-pad) and `Right` (face buttons)
  (`ActionBarTemplates.xml:151`, `:237`), so a bar can be split by moving two
  frames, not eight buttons.
- The game calls back when the active bar changes
  (`RegisterActiveActionBarUpdatedCallback`, `PageUnit.lua:705`).
- The game shows or hides bars itself only in its Compact setting; an addon
  cannot show or hide them in combat, so a "swap" has to be a fade.

Owner's answers:
1. One switch sets the whole layout by itself (not a hand recipe in Edit
   Mode).
2. Map bottom middle. The main bar is split around it: d-pad half left, face
   half right. The LT bar sits whole outside on the left, the RT bar whole
   outside on the right. (A split with the other bars stacked was confusing:
   "both sides would light up".)
3. Both-triggers bar: the owner likes all three ideas, so it is a choice:
   small above the pads (close to the map, not "like horns"), small in the
   bottom corners (the row must not move up; keeps "a clean line above"), or
   swapping with the main pads while both triggers are held.
4. "The goal is to reduce buttons taking up space." One "Spell button size"
   option, with three fine-tune sizes under it (main pads, LT and RT bars,
   both-triggers pads). Starts at 85% (my call).
5. Switching off puts everything back exactly as it was before switching on.
   The "before" positions are saved with the settings.
6. The PRD non-goal "Replacing or fighting Blizzard's gamepad support" is
   removed (owner's choice; removed from PRD.md the same day).
7. The switch makes a new starting point, not a lock. "Before turning this
   on, we need to save that configuration, when it turns on, we'd ideally
   make a new one ... if edit mode is used again ... we accept the edit mode
   suggestions and bake them into this new format ... we're giving them a new
   default template to work from." So: the addon creates a real Edit Mode
   layout and switches to it, with a reload. Its name in Edit Mode is
   "Pocket Essentials" (owner: "after the addon").
   The old layout is never touched; switching off switches back to it.
   Edit Mode changes save into the new layout by themselves. The non-goal
   "Switching the game's Edit Mode layouts, and a bundled handheld layout"
   is lifted on purpose (removed from PRD.md the same day). The old Layout
   helper's code is in git history (`9e8a7d6`).
   What Edit Mode cannot hold (the split main bar, the both-triggers
   placement, the button sizes) the addon applies at each login, out of
   combat, from the Controller tab's options.

My calls in the mockup: chat 440 by 200 in the map's old corner, buffs left
of it, quest tracker under it, the Ranged and Main Hand timers under the
pads (under the LT and RT bars with "bottom corners"), Compact must be off.

8. Second pass (owner): include the quest arrow and its text; LT and RT bars
   lower, toward the timers' outer corner; main pads scooted out a little;
   the "above" pads lower; everything hugging the bottom more. Then the
   player frame, pet frame, target and target's target, and the pet
   sub-menu "and any other sub menus". First stab mocked: frames in the
   bottom corners (player and pet left, target and its target right), the
   arrow kept top middle, buffs under the chat, the two class-action buttons
   on the top of the map's rim with a smaller wheel and no dark disc.

9. Frames: the owner likes the corners but also pictured them "above the
   left and right trigger buttons, snug up against the main pads", and
   cannot tell which is better "until im trying them". So it is a choice on
   the Controller tab: "Player and target frames: Corners / Above bars".
   To check in the Probe round: whether changing this choice needs a reload,
   since the frames' spots live in the Edit Mode layout.

10. Swing timers (owner): under the main pads they crowd; under the LT and
    RT bars "they actually look really nice"; curious about stacked under or
    above the map. "My biggest gripe ... is they're always visible, even when
    im a caster, i dont really need the mainhand swing, only the ranged one"
    and did not know how to turn one off. Found: each timer (Main Hand, Off
    Hand, Ranged) is its own Edit Mode piece with the game's own Visibility
    setting, Always / In combat / Hidden, plus width, height, title and time
    (`EditModeSettingDisplayInfo.lua:777`). Mocked: a "Swing timers" fold on
    the card with Where (Under bars / Above map / Under map) and one
    Always / In combat / Hidden row per timer.
11. Owner: "i like under the minimap to start"; the timers start stacked
    under the map (the map lifts a little). The "above" both-triggers pads
    slide down to rest on top of each main pad, against the map's side.
    The timers start with Ranged and Main Hand on "In combat" and Off Hand
    hidden (owner's choice). The corner pads move just outside the timer
    stack when it is under the map. Before the spec: every combination of
    pads, frames and timer spot is checked at 70%, 85% and 100% and written
    as a table of spots.

12. Sub-menu wheel (owner): the two buttons on the map's rim, slid "to the
    outer edges of the minimap a tad more", placed per setup so an open wheel
    never covers a pad. Mocked: out toward the map's upper corners; nearer
    the top with the "above" pads. Smaller wheel, no dark disc; a thin dark
    ring is kept as a fallback if it reads badly on bright ground (my call).

13. "Above map" stays as a timer spot; an open wheel may briefly touch the
    timers there (owner accepts).

### Combination check (2026-11-21)

Every pairing was drawn from the mockup's own numbers and tested for
overlaps and for pieces leaving the screen: 3 pad placements x 2 frame
placements x 3 timer spots x 3 sizes (70, 85, 100%) x sub-menus closed, pet
commands open, pet spells open = 162 checks; then the same pairings with all
27 fine-tune settings = 1,404 more. Compared: every spell button, the map,
the four unit frames, the timers, the two sub-menu buttons and the open
wheel's spells. Not compared: highlight boxes, text labels, the buffs and the
quest arrow (they sit at the top, away from the band).

Result after two fixes: no overlaps, except the accepted one (an open wheel
over timers stacked above the map).
- Fix 1: a group's size is the overall size times its fine-tune, capped at
  100%. Before the cap, 100% with "Bigger" pushed the LT and RT bars into the
  corner frames, the "above" pads into the map and the corner pads off the
  bottom of the screen.
- Fix 2: with the "above" pads at more than 90% and the timers not under the
  map, the sub-menu buttons sit nearer the top of the map with a smaller
  wheel, or the open wheel touched the left both-triggers pad.

The stand-in sizes are approximate, so the real spots still need the device.

14. Frames, third spot (owner): "instead of stacked, the main one would
    still be in the middle, but the pet and target would be next to it on the
    outside, to be a little more flat ... i need the bars in the middle so i
    keep track of my health". Mocked as "Side by side"; the frames choice is
    now Corners / Stacked / Side by side. The combination check was re-run
    with it: 243 checks plus 2,106 fine-tune checks, no overlaps beyond the
    accepted one.
    The owner also floated a flashing border for low health and low mana,
    and asked whether that is too much for a lightweight addon. Not designed.
    The game's files include its own low-health screen flash
    (`Blizzard_FrameXML/Shared/LowHealthFrame.lua`); whether it is active on
    Forever is not confirmed.

15. The flashing border is parked (owner; added to PRD.md "Parked ideas").
    XP bar: "make the xp bar bigger to fill in that gap up there better".
    The game's Edit Mode size for it goes from 50% to 130% and changes the
    width only (`EditModeSystemTemplates.lua:2641`), so the template sets
    130% and centres it between the controller hints and the chat.

Sub-menus found in the source: a wheel of up to 8 places around the button
that opened it (`FlyoutRadial.lua:280`, radius 60). Pet commands open from
`LeftClassAction` (`Camelot/PetActionFlyout.lua:175`), pet spells from
`RightClassAction` (`Camelot/PetSpellFlyout.lua:314`); druid and paladin
class wheels use the left button, warrior the right
(`Camelot/ClassSpellFlyout.lua:2`). The wheel centres itself on its button
each time it opens, so moving the button moves the wheel.

Still open: the pet sub-menus (waiting on the owner's screenshot), and a
Pocket Probe round before any spec: save a new Edit Mode layout and switch
to it (`C_EditMode.GetLayouts`, `SaveLayouts`, `SetActiveLayout`), reload,
and switch back; what happens when the saved layouts are full; move and
resize the bars' `Left` and `Right` halves out of combat; fade a bar in
combat; then a long fight to look for "Interface action blocked".


## Controller layout, first build (2026-11-21, 0.11.0, untested)

The owner, away: "can we start getting things made and then when I return we
can run the probe and adjust from there". Built without the probe round.
Spec `docs/superpowers/specs/2026-11-21-controller-layout.md` (its "Rulings"
lists the calls made without the owner), plan
`docs/superpowers/plans/2026-11-21-controller-layout.md`, device steps
`docs/TESTING.md` 21. Nothing committed.

Found while writing the spec, and it changes the design: **a bar cannot be
split.** The game puts every spell button back at a fixed offset from its
bar's centre at each button press, in combat too
(`ActionBarStyles.lua:119-156`), and an addon may not move a spell button in
combat. So the build keeps each bar whole: main bar above the map (or under
it), LT left, RT right, both-triggers smaller above. Also found: the two
sub-menu buttons can only move together, 138 either side of one point; a
scaled wheel would open in the wrong place; the target's target cannot be
placed by itself. The mockup's "Bars" control shows the build as it is next
to the first design.

To decide with the owner after the device session: the whole-bar
arrangement (it is taller in the middle than the split design); whether
85% becomes the starting size; "Swap" once the fade is probed; whether a
secure-handler route could split a bar after all.

## Flat strip for the main bar (idea, 2026-11-22, mocked, not built)

The owner, on hearing a bar cannot be split: "Is it possible to have the
main bar flat and the others in the controller shape, and then just stick
the bar under the mini map ... if we can't split, then we need a solution to
that, cause that also means the both triggers bar also needs to be adjusted".

The game's own bar cannot be reshaped either (same finding). What is
possible since the "no bars of our own" non-goal was removed: a flat strip of
our own, under the map, that shows the main bar's eight spells (icons,
cooldowns, counts) while the game's real main bar sits off screen and still
takes the controller presses. Owner's answer: display-only, not tappable.

Mocked ("Bars: Flat strip for the main bar"): four d-pad squares, a gap, four
face-button circles, on the bottom edge under the map; the LT and RT bars
stay the game's own either side. Both-triggers spells: share the strip while
both are held, or a small strip of their own above it (the owner has not
picked).

Not designed yet, for its spec: how the strip follows the game when the main
bar changes (stances, target bars, taking control of a creature, paging),
the pressed look and the highlight, and which events it listens to in
combat. It builds on 0.11.0's Edit Mode layout and bar moves, so the probe
and the 0.11.0 device test still come first.

Owner (2026-11-22): "having the overlay of that button over the spell icon
to help indicate which button even though its in a straight line". Mocked: a
small picture of the controller button in each spell's top right corner,
in the order d-pad left, up, right, down, then X, Y, B, A. For the spec: the
game has its own button pictures per controller type ("Button prompts" on
the gamepad bar, `ActionBar.lua` ShowButtonIcons); check whether a strip of
our own can show the same pictures, so they match the player's controller.

Owner (2026-11-22) on the both-triggers spells: "I like A and B honestly,
both work, i could see both being popular". So it is a choice: share the
strip while both triggers are held, or a small strip of its own.
