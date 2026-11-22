# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [0.11.0] - 2026-11-21

Twenty-fifth test build. From the owner, for the controller UI round:
"minimap in center middle, we could build out the buttons around the map and
then stick the chat up where the map used to be". Built while the owner was
away ("can we start getting things made and then when I return we can run
the probe and adjust from there"), before the probe round that was meant to
come first. Spec `docs/superpowers/specs/2026-11-21-controller-layout.md`.
Not yet tested on a device: every position and size in it is a first guess.
Your saved choices carry over.

### Added

- **Controller layout** (new switch on a new **Controller** tab, off to
  start with, marked experimental): one switch gives a new screen
  arrangement for controller play. It needs the game's Gamepad UI.
  - It creates a new Edit Mode layout named "Pocket Essentials", switches
    to it and asks for a reload. Your own layouts are never changed.
    Switching off goes back to the layout you had, with a reload.
  - The map sits bottom middle; the chat is bigger, top right, with the
    buffs and the quest tracker under it; the XP bar is wider.
  - The left-trigger bar sits left of the map and the right-trigger bar
    right of it. The main bar is above the map, or under it. The
    both-triggers bar is smaller, above them.
  - Choices: where the main bar goes; where the player, pet and target
    frames go (corners, stacked, or side by side); one size for all spell
    buttons (starts at 100%) with three fine-tunes; where the swing timers go; and for each
    swing timer Always, In combat or Hidden.
  - It is a starting point: what you then move in Edit Mode is kept.
    "Start over" rebuilds the layout from the template.
- **Setup guide:** a Controller screen with the same switch.
- **Pocket Probe 0.4.0** (testing tool, released on its own as the GitHub
  pre-release `probe-v0.4.0` before this build): ten new trials. They
  measure the real sizes of the map, frames, buff rows, quest tracker, XP
  bar, sub-menu buttons, pet wheel, bars and one spell button; test the moves
  this build relies on; and answer what a flat strip of spells under the map
  would need: whether the main bar's spells can be read in a fight, whether a
  bar can be faded in a fight, whether a controller press still casts with
  the main bar parked off screen (a guided trial), and which pictures the
  game uses for the controller buttons. Device steps: `docs/TESTING.md`
  section 22.

### Known gaps

- Spell button size starts at 100%. Below that, a spell that opens its own
  wheel from a bar may open the wheel beside its button (unconfirmed).
- Switching off during a fight and reloading before the fight ends leaves
  the Pocket Essentials layout active. Switch on and off again to fix it.
- Turning the game's Gamepad UI off makes the game pick its own Modern
  layout. Switch the feature off first.

### Not as drawn in the mockup

- The main bar is whole, not split around the map. The game puts every
  spell button back beside its bar's centre at each button press, in combat
  too, and an addon may not move a spell button in combat.
- The both-triggers bar has one spot. "Swap" waits for the probe's fade
  result.
- The two sub-menu buttons sit either side of the map at a fixed distance,
  and their wheels are the game's own. The game does not let them be
  placed freely or resized safely.
- The target's target stays attached to the target frame.

## [0.10.0] - 2026-11-20

Twenty-fourth test build. From the owner, after a Blizzard error popped up on
the handheld: "we need another feature to make managing bugs easier ...
almost working like how bugsack works". Built while the owner was away ("keep
working and release when done"). Spec
`docs/superpowers/specs/2026-11-20-error-catcher-and-probe-panel.md` (Part 2).
Not yet tested on a device. Your saved choices carry over.

### Added

- **Catch all errors** (new switch on the Errors tab, off to start with):
  every Lua error, from the game and from other addons, goes into one list,
  not only Pocket Essentials' own.
  - **One error per page**, BugSack-style: who caused it, how often and when,
    the message, then the stack. **< Previous** and **Next >** (or d-pad
    Left/Right), "3 of 12", and **Clear all**. A filter row picks All, Pocket
    Essentials, Blizzard or Other addons.
  - **Error popup: Show / Hide.** Hide keeps the game's small error box from
    popping up and taking the controller; hidden errors still show in this
    list. Switching the feature off puts the popup back as it was.
  - **Stands aside for BugSack** (or BugGrabber, Swatter): the switch is
    dimmed and the card says why and how to choose this one instead (turn
    BugSack off in the AddOns list). It never switches another addon off.
  - Pocket Essentials still lists its own errors with the switch off.

### Changed

- **Debug log has its own tab**, under Errors.
- **Choices that do not fit grow wider** into the empty space beside their
  name, so no choice is cut off.

## [0.9.1] - 2026-11-20

Twenty-third test build. From the owner, after installing 0.9.0: "this latest
build looks great, but i have some minor tweaks". Specs
`docs/superpowers/specs/2026-11-20-0.9.0-ui-redesign.md` (0.9.1 changes) and
`docs/superpowers/specs/2026-11-20-loot-sparkles.md`. Not yet tested on a
device. Your saved choices carry over.

### Added

- **Loot sparkles** (new switch, off to start with): brings back the sparkle
  on things you can loot or use, even on the lowest graphics. It turns the
  game's own sparkle setting back on and keeps it on after graphics changes.
  Switching it off puts the old setting back; the sparkles go after a full
  game restart. Based on
  [ForeverLootSparkles](https://github.com/svengabr/ForeverLootSparkles) by
  Ashtar Senior (GPL-3.0-or-later).

### Changed

- **Game fixes** is the new name of the Menu background tab; it holds Menu
  background and Loot sparkles. In the setup guide the screen is "Vendors and
  game fixes".
- **Setup guide, Welcome:** the controller pictures show which face button
  (bottom, right) does what, so they fit any controller.
- **Setup guide, d-pad:** the highlight starts on the screen's first control
  (usually the switch), not on Close. Down from the last control goes to
  Next; Left from Next goes to Skip, then Back.
- **Setup guide, less text:** one sentence for Menu background, and the round
  button and chat screen says once what a tap does.

## [0.9.0] - 2026-11-20

Twenty-second test build. A new look for every window, built from the mockups
the owner reviewed in four rounds ("i am so happy with this setup, this looks
incredible"). Spec `docs/superpowers/specs/2026-11-20-0.9.0-ui-redesign.md`;
mockups `docs/ui-review/mockup-0.8.1.html`. Not yet tested on a device. Your
saved choices carry over (the old arrow size becomes a percentage once).

### Changed

- **Settings have tabs.** Down the left: Quest icons, Quest arrow, Bags,
  Vendors, Chat, Menu background, General, Errors. One page at a time on the
  right. A green dot on a tab means a helper there is on.
- **Every row looks the same:** the name on the left, one control of one width
  on the right. There are four controls: an On/Off switch, a row of joined
  choices (the chosen one is gold), a − number + box, and a single button.
  The fold buttons, the bottom row of buttons and the "press and hold" tip are
  gone. The scroll bar shows only when a page is too long.
- **New names:** Bigger bag (was Bag window), Bag sorting (was Bag sorter),
  Auto sell junk, Auto repair, Chat picker (was Chat from round button). Each
  has one short line under its name.
- **Quest arrow:** one size control, 50% to 150% in steps of 10, for the
  arrow and its text together. It no longer follows Button size, and it can
  also be set in Move on screen while you watch the arrow. The quest line is
  smaller and starts with "Quest:" (or "Turn in:"). "Here" is green. "Turn
  around" shows no arrow. "No known location" now reads "No map data for this
  quest". New: "No quest focused" can hide itself in cities and inns (on by
  default).
- **Chat picker window:** only as big as its buttons, in 3 columns under
  "Talk in" and "Whispers", with its own size control (70% to 150%). The
  "Three-finger tap" hint is gone. Unanswered whispers get a round red dot.
- **Bigger bag** always puts the bag pictures in one row at the top (the
  "Bag icons" choice is gone). Off, the game shows its own bag.
- **Sort tab:** the same size, but rounded on the outside and joined to the
  bag, with the sort picture and "Sort" in the middle.
- **General tab:** Button size, Round button colour, "I play with: Touch
  controls / Controller", Move things on screen, Setup guide, Reload.
- **Move on screen** always lists all three pieces; one whose helper is off
  says "(off)". The chat prompt is now listed as "Press A to type".
- **Setup guide:** 9 shorter screens with dots for progress, the same cards
  as the settings, every choice included, controller-button pictures on the
  first screen, a Round button screen, a "Your screen" picture of where each
  piece starts with a "Move things now" button, and tip tiles at the end.

## [0.8.1] - 2026-11-19

Twenty-first test build. From the owner, after installing 0.8.0: "im really
happy so far", with four points about the settings. Spec
`docs/superpowers/specs/2026-11-19-0.8.1-clearer-labels.md`. Not yet tested
on a device. Your saved choices carry over as they are.

### Changed

- **Hide Blue Quest Haze** (was "Hide blue haze") and **Quest Icon Key**
  (was "Icon key") sit side by side on one line in the Quest icons options,
  in the settings and in the setup guide. The key page is now called
  "Pocket Essentials - Quest Icon Key". With the d-pad, press Right from
  the toggle to reach Quest Icon Key (Down now goes to the next line).
- **Chat from round button** is the new name of "Big chat buttons". The
  line under it says what it does: "Tap the round button to choose who to
  talk to: Say, Party, Guild or someone who whispered you." Chat text size
  stays under it.
- **The round button moves off the map.** While the map is open at its
  normal size, the round PE button sits on the map's book icon in the
  top-left corner; it goes back to its spot when the map closes or goes full
  screen. Tap and hold work as before. Always on, no setting.
- **Buttons are one size.** In the settings and the setup guide, every
  button in a row is the same width (3 button heights), so they line up in
  columns; a longer label takes two or more widths. A toggle such as
  **Touch screen: Yes/No** is wide enough for both sides, so it no longer
  changes size when you tap it.

### Not changed yet

- **Menu background** did not put a panel behind the quest log's quest menu
  on the device. This build does not change it: a debug log from the device
  (steps in `docs/TESTING.md` section 17) will show where it goes wrong.

## [0.8.0] - 2026-11-18

Twentieth test build. From the owner, after trying 0.7.0: "do the next 3, and
call the release 0.8.0", plus fixes for Merge nearby icons, the setup guide's
first page and the ugly Up and Down buttons. Spec
`docs/superpowers/specs/2026-11-18-0.8.0-design.md`. Not yet tested on a
device. Your saved choices carry over as they are.

### Changed

- **Move the arrow** (in Quest arrow) and **Move the round button** (in the
  main settings) replace the position buttons. Each opens **Move on screen**
  with that piece picked. **Reset** puts the piece back to the starting
  spot. Nothing you already placed moves.
- **"Move things" is now "Move on screen".**
- **Bags is now two features.**
  - **Bag window:** **Bag size** and **Bag icons**.
  - **Bag sorter:** **Sort button** (On / Off) and **Sort stick** (Left /
    Right).
  - **D-pad to Sort** is now automatic whenever the Sort button shows.
  - **Button only** is gone: a saved one now sorts with the left stick too.
  - The first time 0.8.0 loads, **Bag window** is switched on if you used
    **Bag sorter**, with your size and icons as they were.
- **Button colour:** Gold, Horde or Alliance for the round button.
- **Merge icons closer than N%** (for example 2%, of the map) replaces the old number, with
  "of map" under it.
- **Setup guide, first page:** the highlight starts on **Start**. A new
  question asks whether you use the touch screen. **No** turns off the Sort
  button and the scroll bar.
- **A slim scroll bar** replaces the big Up and Down buttons: an arrow at
  each end and a marker showing where you are in the list. Tap the track to
  page. A new **Touch screen: Yes / No** setting turns it on or off.

## [0.7.0] - 2026-11-18

Nineteenth test build. From the owner, after trying 0.6.0: fine-tune the
Quest icons rows, a smaller arrow, a nicer chat text size row. Spec
`docs/superpowers/specs/2026-11-18-number-control-design.md`. Not yet tested
on a device. Your saved choices carry over as they are.

### Changed

- **A new number control: - value +.** One joined, gold-edged box with the
  number large in the middle and a small word under it. An end that can go
  no further is dimmed. The d-pad stops on - and +.
  - **Spots per objective:** any number from 1 to 20, then **All**.
  - **Merge nearby icons:** **Off**, then 1 to 10 (higher merges icons that
    are further apart). The old "Normal" is 2 and "More" is 5.
  - **Chat text size:** the same box replaces Smaller and Bigger.
- **Icon size: Extra small**, a little smaller than Small.
- **Arrow size: Small**, about three quarters of Normal.
- **Hide blue haze** moved to the bottom of Quest icons, just before Icon key.
- `/qd spots` takes any number from 1 to 20; `/qd cluster` goes up to 10;
  `/qd size xsmall`.

## [0.6.0] - 2026-11-18

Eighteenth test build. From the owner: fewer buttons and less clutter in the
settings. Spec `docs/superpowers/specs/2026-11-18-tidier-settings.md`. Not yet
tested on a device. Your saved choices carry over as they are.

### Changed

- **One-tap toggles.** A choice with only two sides is now one button that
  says what it is set to, and a tap flips it: **Hide blue haze: On**,
  **D-pad to Sort: Off**, **Bag icons: In the grid**. Green means on.
  Toggles next to each other share a line, with no heading above them.
- **Quest icons: "Icons on"** replaces the separate "Map icons" and "Minimap
  icons" rows: **Map and minimap** / **Map only** / **Minimap only**.
  (`/qd map` and `/qd mini` still work.)
- **Bag sorter: "How to sort"** replaces "Sort key" and "Sort button":
  **Button + left stick** / **Button + right stick** / **Button only** /
  **Left stick only** / **Right stick only**. You can no longer end up with
  no way to sort (before, "Button only" with the button hidden did that; such
  a saved setting gets the button back).
- **Headings beside their buttons.** A row's name now sits on the same line
  as its buttons, to their left, when they fit, so each row takes about half
  the height. A row with too many buttons for one line keeps its name above,
  as before. The same goes for "Button size" and "Round button position".
- The setup guide shows all of this the same way (it draws options with the
  same code).

### Fixed

- Nothing shipped was affected, but the offline tests found and fixed two
  slips in the new code before release: a saved `false` read as "nothing
  chosen", and a toggle whose other side is `false` would not flip.

## [0.5.0] - 2026-11-18

Seventeenth test build. From the owner's first look at the setup guide: it
only had the ON / OFF switches, and the choices of each feature were left to
the settings. Now you set each feature up in the guide itself. Not yet tested
on a device.

### Changed

- **Setup guide: each feature's options are in the guide**, under its switch,
  exactly as the settings window shows them: the same labels, the same
  buttons, the same saved values. Switch a feature on and its choices appear
  under it at once (for example Quest icons: which quests, map and minimap
  icons, icon size; Bag sorter: bag size, sort key, "D-pad to Sort", "Bag
  icons"). **Chat text size** (Smaller, the number, Bigger) is on the Chat
  screen whether "Big chat buttons" is on or off. A choice made in the guide
  shows in the settings, and the other way round. There are no "Hide
  options" buttons in the guide: the options are simply there.
- **Setup guide: one screen per feature**, nine screens where there were
  seven: Welcome, Quest icons, Quest arrow, Menu background, Bags, Vendors
  (Sell junk and Repair, which have no options, share one), Chat, "The round
  button and moving things", and All set. The texts are shorter where the
  buttons now speak for themselves.
- A screen that becomes too long when a feature is switched on gets the
  **Up** and **Down** buttons on the right, as in 0.4.1; a screen that fits
  still has none. The d-pad reaches every button and scrolls to it.
- If a choice needs a reload, the last screen offers it, as it already did
  for a switch.
- **Icon key** (under Quest icons) opens the settings' Icon key page from the
  guide too, which closes the guide. Open the guide again from the settings.

### Internal

- The settings window and the setup guide draw options with one piece of
  code (the "list drawer" in `Settings.lua`), not two copies. The settings
  window looks and behaves as before.

## [0.4.1] - 2026-11-18

Sixteenth test build. From the owner's first look at 0.4.0 on the device: the
setup guide and the rest showed no problems, but the guide had Up and Down
buttons down its right side that did nothing.

### Changed

- Setup guide: the **Up** and **Down** buttons are gone from every screen
  that fits in the window, and the text uses the whole width. They only
  appear on a screen that is too long to show at once (which can happen at
  the larger button sizes), because there they are the only way to read the
  rest by touch.

## [0.4.0] - 2026-11-17

Fifteenth test build: a setup guide that explains each feature and lets you
switch on what you want, a background for the game's pop-up menus, two new
choices for the bag (the d-pad can reach the Sort tab; the bag pictures in one
row at the top), and chat text size as one small stepper. Every feature and
every new choice starts off. Not yet tested on a device.

### Added

- **Setup guide**, a window of seven screens that explains each feature in a
  few lines and has the feature's ON / OFF switch right there: Welcome,
  Quests (Quest icons, Quest arrow, Menu background), Bags, Vendors, Chat,
  "The round button and moving things", and "All set", which lists what is
  switched on and what is still off. Every feature still starts off; the
  guide is how you find out what there is and turn on what you want.
  - It opens by itself a moment after the first loading screen, once, on an
    account that has never pressed **Finish** or **Skip** in it. If you
    already use the addon you will see it once after this update, with your
    switches exactly as you left them.
  - A switch in the guide is the same switch as in the settings: it acts at
    once and is saved at once. Nothing waits for Finish.
  - **Back**, **Skip** and **Next** sit in the bottom row. With the
    controller, the d-pad moves the blue highlight, A presses and B closes;
    the highlight stays on Next, so pressing A again and again walks through
    the guide.
  - Only Finish and Skip are remembered (for every character on the
    account). Close, B, Escape, or the game closing its windows only hide
    the guide; it comes back at the next login, and a chat line says so the
    first time.
  - It never opens during a fight. If a fight starts while it is open it
    hides at once and comes back at the same screen when the fight ends.
  - When the game hides its whole interface (a cinematic, a full-screen
    view) the guide goes and comes back with it. That is not a closing: no
    chat line, nothing remembered.
  - **Reload now** on the last screen counts as Finish, so the reload does
    not bring the guide back.
  - Open it again at any time with the new **Setup guide** button in the
    bottom row of the settings (after "Move things"), or with `/pe setup`.
  - Nothing of it exists until it is first opened, and nothing of it runs
    while it is closed.
- **Menu background**, a new switch, off by default. With it on, a plain
  dark panel with a thin grey edge sits behind the game's pop-up menus while
  they are open, so the text is easy to read. The menu it is meant for is
  the one on a quest in the quest log (Track / Focus / Share / Abandon),
  which on this client is drawn with no background. The panel is only a
  picture behind the menu: the menu's entries are not touched, it never
  takes a tap, and it goes away when the menu closes. No reload is needed
  to turn it on or off. With the debug log on, the log also says whether
  the game's own menu background picture is missing on this client.
- **D-pad to Sort**, a new choice inside "Bag sorter", Off by default. With
  it On, the Gamepad UI on and the bag open, pressing **Left** from any slot
  in the bag's first (leftmost) column moves the controller cursor onto the
  Sort tab. On the tab **A** sorts the bags, **Right** goes back into the
  bag and **B** closes the bag as usual. Left from the first column used to
  wrap round to the last column; with this On it goes to the tab first.
  A is only taken while the cursor is on the tab and is handed back when
  the cursor leaves, the bag closes, a fight starts or the choice is
  switched Off. In a fight the game does not let an addon set this up: a bag
  first opened in a fight gets the route when the fight ends, and on a tab
  reached during a fight A does nothing (the stick click still sorts).
  One limit: if you close and reopen the bag, or fold one of your bags,
  during a fight, the game may deal its item buttons out to other slots and
  the addon cannot follow until the fight ends. Until then Left may jump to
  Sort from an odd slot, or not from the first column at all. Using items is
  not affected, and it is put right the moment the fight ends.
  Touch and the stick click work exactly as before. Using, equipping,
  selling and picking up items is not changed. Not yet tested on a device:
  whether A on the tab really sorts can only be seen there.
- **Bag icons**, a new choice inside "Bag sorter": "In the grid" (as the
  game draws it, and the default) or "One row at the top". With the Gamepad
  UI on, the game draws a picture of each equipped bag inside the bag
  window, in among the item slots, where they look like loose bags lying in
  your inventory. With "One row at the top" those pictures sit side by side
  in the top row, starting at the left, and every slot follows below in the
  same order as before with nothing in between. The window keeps its size.
  Items are not moved or packed, and the bag pictures still do their jobs
  (X folds a bag away, Y opens its menu, LB and RB jump between them). When
  the slots do not fill whole rows, the short row is the first one under the
  pictures. Switching back to "In the grid", or switching "Bag sorter" off,
  puts every button back where the game had it, at once. It does nothing
  in the mouse and keyboard style, where the game does not draw those
  pictures in the bag. With "D-pad to Sort" also On, Left goes to the Sort
  tab from the slots of the leftmost column, not from the backpack picture
  above them. Not yet tested on a device: that using, moving and selling
  items still works with it on, in and out of a fight, can only be seen
  there.

### Changed

- **Chat text size** is now one small stepper: **Smaller**, the size as a
  number, **Bigger**. One press moves one step through the game's own sizes
  (12, 14, 16, 18, 20, 24, 27) and then on to 30 and 34. The number is the
  size the game is using right now, so it also follows a change made from
  the game's own chat tab menu. The buttons stop at the ends: at the
  smallest size Smaller is drawn dim, at the biggest size Bigger is, and a
  press on a dim button does nothing.
- The **Chat text size** row is now shown whether "Big chat buttons" is ON
  or OFF; it never needed that feature. Because of this the "Big chat
  buttons" block has a "Hide options" button even while it is off.
- As before, every chat window gets the same size, and a press during a
  fight is held and applied when the fight ends (the row then says, for
  example, "Chat text size: 20 (after the fight)").
- **All features stay off by default**, also after they have passed a device
  test. The earlier plan was to turn each one on for everybody once it was
  proven; the setup guide replaces that: it shows what there is and you
  switch on what you want.
- Opening the chat window now also closes the setup guide, so only one
  Pocket Essentials window is ever open.

## [0.3.1] - 2026-11-17

Fourteenth test build: the arrow's "Quest in another zone" choice from 0.3.0
is taken out again. Not yet tested on a device.

### Removed

- Quest arrow: the **"Quest in another zone"** choice ("Point the way", the
  light blue arrow). A straight line across zones does not know where the
  zones connect, so it can point at a mountain wall; doing it properly needs
  a list of crossings, which is more than this addon should carry for now.
  The owner chose to postpone it. For a quest in another zone the arrow says
  "Outside this zone / Head to <zone>", as it did before 0.3.0. If you had
  chosen "Point the way", nothing happens: the choice is simply gone.

The Layout helper stays removed.

## [0.3.0] - 2026-11-17

Thirteenth test build: the arrow can now point at a quest in another zone,
and the Layout helper is gone. Not yet tested on a device.

### Added

- Quest arrow: a new choice, **"Quest in another zone"**.
  - **Name the zone** (the default) is what you have today: "Outside this
    zone / Head to Duskwood".
  - **Point the way** shows a **light blue** arrow pointing straight at the
    quest's nearest spot in the other zone, with the distance, and
    "Duskwood - Morbent Fel" under it. When you enter the zone the arrow
    turns gold and works as before.
  - It is a straight line, not a route: it knows nothing about roads, boats
    or mountains. The colour and the zone name are there to say so.
  - It only points within the same continent. For another continent, or a
    zone the game cannot place, the text stays as it is today.
  - Changing the choice takes effect at once.

### Removed

- **Layout helper.** It was written before the first device test and never
  tried in the game, and the game already switches to its Gamepad layout by
  itself. Placing things without dragging is what "Move things" does. If you
  had it switched on, nothing happens: the row is simply gone, and your
  game's layout is left as it is.

## [0.2.1] - 2026-11-17

Twelfth test build, from the debug log of the 0.1.0 play test (two sessions,
57 fights, no error and nothing blocked). Nothing changes in how the game
plays. Not yet tested on a device.

### Debug log

- Bag sorter no longer writes "stick click given back to the game" at every
  fight when no stick was taken. A line is written only when a stick is
  really taken or handed back, and "no stick taken: button only" once per
  bag opening.

## [0.2.0] - 2026-11-17

Eleventh test build, asked for during the play test of 0.1.0: a way to put
the arrow and the other on-screen pieces exactly where you want them. Not
yet tested on a device. (0.1.0's changes are still being tested too.)

### Added

- **Move things.** A new button at the bottom of the settings opens a small
  panel that moves the addon's on-screen pieces: the quest arrow, the "Press
  A to type" text, and the round button.
  - Pick a piece from the list; a gold outline shows where it sits, even if
    the piece itself is not showing at the moment.
  - Up, Down, Left and Right move it. One press is a small nudge. Hold the
    button and it keeps moving, faster after a moment.
  - With the controller: d-pad to a button, A to press or hold it, B to
    close. Touch works on the same buttons.
  - Reset puts the piece back on its preset spot. A piece cannot be pushed
    off the screen.
  - Positions are saved as you go and remembered between sessions.
  - The panel moves to the other bottom corner if it is in the way.
  - It cannot be opened during a fight, and closes if one starts.
- The preset choices ("Arrow position", "Round button position") are still
  there as starting points. Choosing a preset puts the piece exactly on it
  again.
- This does not use the game's Edit Mode and does not touch any of the
  game's own frames.

## [0.1.0] - 2026-11-17

Tenth test build, from the first long play test of 0.0.9 (five sessions and
about twenty fights with no error and nothing blocked). Six requests from
that test, built together. Not yet tested on a device.

### Added

- Big chat buttons: after you tap a chat button, "Press A to type" now shows
  in big letters in the middle of the screen, with where the chat is going
  under it ("Chat is set to Guild"). It goes when the chat box opens, after 12
  seconds, or when a fight starts. The chat line is still printed too.
- Chat text size: under "Big chat buttons" in the settings there is a "Chat
  text size" row with Smaller and Bigger buttons. Each tap changes the game's
  chat window text one step (12 up to 34), in every chat tab, using the game's
  own setting, so it is remembered. If you tap during a fight it is applied
  when the fight ends.
- Bag sorter: a "Sort key" choice: Left stick click (as before), Right stick
  click, or Button only (no stick is taken). The stick is still only used
  while the bag is open.
- Settings: a feature that is on and has options gets a "Hide options"
  button next to its switch. Tap it to fold the options away so the list is
  shorter; "Show options" brings them back. The feature stays on either way,
  and what you folded is remembered. It works with the d-pad and A as well.

### Changed

- "One big bag" is now called "Bag sorter" (the game's controller mode
  already shows one combined bag; what this feature adds is the sorting).
  If you had it switched on, it is still on.
- Quest arrow:
  - It keeps pointing at the same spot when the quest's progress changes
    (before, every kill made it start again).
  - It only swaps to another spot when that one is clearly nearer (at least
    a fifth nearer and 15 yards nearer), so it no longer flips between two
    spots at a similar distance.
  - After it has said "Here" and you walk away, that spot is left alone for
    three minutes and the arrow leads you to the nearest spot you have not
    been to, instead of pointing back at the place you just left. When you
    have been to them all it starts again.
  - When one part of a quest is finished, the arrow moves straight to a spot
    for a part that is not.
- The "Icon key" button has moved from the bottom of the settings into the
  "Quest icons" block, next to the other quest settings.

### Debug log

- The time on each line now comes from one clock, so lines within the same
  second are in order.
- The arrow's line says which spot it points at (the objective's number and
  the place on the map) and a new line is written each time the spot changes,
  with the reason.
- The "driver started / stopped" pair is no longer written on every quest-log
  change while no quest is focused.
- The long legend on the fight lines is written once per session.

## [0.0.9] - 2026-11-17

Ninth test build, from the first Pocket Probe file sent from the device.
Not yet tested on a device.

The probe showed that, with the Gamepad UI on, an addon opening the chat box
is blocked inside the game's controller code, and that afterwards the game
refuses its own controller actions (interact, cancel, clear target) in the
addon's name until a reload. This is the likely cause of the "blocked from
an action only available to the Blizzard UI" pop-up from the fourth device
test.

### Changed

- Big chat buttons, Gamepad UI on: a tap no longer opens the chat box. It
  sets where your chat goes (Say, Party, a channel, a whisper) and a chat line
  says "Chat is set to Say. Press A to type." For the next 12 seconds the
  controller's A button opens the chat box through the game's own key
  binding, which the game allows; the button is given back when chat opens,
  when the time is up or when a fight starts. During a fight the tap still
  sets the chat, but the button cannot be lent, so the line says to open chat
  yourself. With the Gamepad UI off, a tap opens the chat box as before.
- Pocket Probe 0.2.0: the trials that upset the controller run last and only
  when "Risky trials" is switched on; what the game refuses afterwards is
  counted in the table; the one-per-reload trials watch for after-effects.

## [0.0.8] - 2026-11-17

Eighth test build, from the first debug log sent from the device (0.0.7).
Not yet tested on a device.

The log showed one block: "The game stopped a protected step of Blizzard's
own interface", from the line where Big chat buttons opens the chat box, with
the Gamepad UI on, in town and out of combat (confirmed by the owner). The
message was still sent. This build does not fix that block; it makes the next
log name the exact step.

### Added

- Pocket Probe, a separate test addon (`probe/PocketProbe/`, its own
  `PocketProbe.zip` on each GitHub release, never in the player zips and never
  on CurseForge). It tries a list of addon actions by itself in each
  situation (Gamepad UI, in and out of a fight, dungeons, vendors, straight
  from a press) and saves whether the game allowed, blocked or forbade each
  one, and which values it hides. `scripts/read-probe.sh` prints the saved
  file as a table. Not for play.

### Changed

- Big chat buttons: the "not during a fight" rule now also asks the game's
  own combat restriction, which is what Blizzard's controller code checks and
  which can be on when the usual combat flag is not. This covers blocks during
  a fight only; the block in the log happened out of combat.
- Blocked-action report: with the debug log on, the game's own lines of the
  call stack are written to the log, so the next file names the exact step
  that refused. The report also says when the combat restriction was active.
- Debug log: records each change of the game's addon restrictions.

## [0.0.7] - 2026-11-17

Seventh test build, from the fourth device test. Not yet tested on a device.

### Added

- When the game blocks something Pocket Essentials tried to do, it now says
  what: one chat line per blocked action ("The game blocked Pocket Essentials
  from using …", with the file and line), and an entry on Settings > Errors
  listing which features were on. This is to find the cause of the
  "Interface action failed" message and the "blocked from an action" pop-up.
- A debug log that can be sent as a file. Settings > Errors has a "Debug log"
  switch (off by default; `/pe debug on` and `/pe debug off` do the same).
  While it is on, the addon keeps a timestamped line for each thing it does
  or decides, up to 10,000 lines, with no player names and no chat text.
  "Save log now" reloads the interface so the game writes the file
  (`WTF/Account/<account>/SavedVariables/PocketEssentials.lua`); "Clear log"
  empties it. `scripts/read-log.sh` prints the file as plain text.
- One big bag: a "Sort button" choice (Show / Hide). Hidden, the left stick
  click still sorts.

### Changed

- One big bag: the Sort button is now a tall gold tab against the bag's left
  edge, below the round bag picture, with the game's sort icon and "Sort"
  written down it. It follows the bag size.
- Sell junk: if the game refuses a sale, selling stops for that visit with a
  chat line, instead of trying every item (which brought the pop-up back
  again and again).
- Sell junk: the first sale of a visit is checked a second later; if the item
  is still in the bag, selling stops for that visit. This covers the game
  refusing without telling the addon.
- Sell junk: nothing is sold while the vendor's Buyback tab is showing.
- Big chat buttons: a tap during a fight no longer opens the chat box; a chat
  line says to try again afterwards. With the Gamepad UI on, the game refuses
  that step to addons in combat and printed "Interface action failed".

### Fixed

Found by a code review against Blizzard's interface source, not on a device.

- Repair: "Repairing for …" is now said only after the game accepted the
  repair; a refused repair gets its own line and is not counted as money spent.
- Big chat buttons: when the chat box cannot be opened the expected way, the
  addon no longer falls back to having the game read a typed command, which
  could make a later typed `/cast` or `/target` fail.
- The blocked-action report now recognises the game's call-stack format
  ("[File.lua]:123") and no longer drops a report when it cannot read the line.
- An error repeating many times a second (for example in the arrow's update)
  now only counts up, instead of reading the call stack every time.
- Quest icons on the minimap come back after a loading screen even when the
  game is a moment late with the player's position.
- Quest icons: helper spots that QuestieDB ties to an item now get icons.

## [0.0.6] - 2026-11-15

Sixth test build. Not yet tested on a device. It also carries 0.0.5, which has
not been tested yet either.

### Added

- Quest icons: a new choice, "Spots per objective" (All, 10, 5 or 3, set to 5
  at first). Each objective now shows at most that many icons in a zone,
  spread across the area its spots cover, instead of one icon on every spot.
  An objective with fewer spots than the limit looks the same as before.
  "Merge nearby icons" works as before. It applies to the world map and the
  minimap. `/qd spots all`, `10`, `5` or `3` does the same by typing.
- The quest arrow still points at the nearest spot, and that spot always keeps
  its icon, even when it is beyond the limit.
- Settings: an "Icon key" button at the bottom opens a page that shows each
  quest icon in its real colour and what it means (Kill, Loot, Use, Explore,
  Turn in).
- Settings: a "Reload UI" button at the bottom, so you never need to type a
  reload.

## [0.0.5] - 2026-11-15

Fifth test build. Not yet tested on a device.

### Changed

- The text under the quest arrow is wider, so short messages fit on one line.
- Messages shown without an arrow ("No quest focused", "Outside this zone")
  now sit where the arrow normally is, instead of lower down.

## [0.0.4] - 2026-11-15

Fourth test build. Tested on the device: both fixes work.

### Fixed

- Green minimap with "Hide blue haze" on: we no longer swap the minimap's
  quest area textures (the blank texture is gone).
- Arrow text cut off with "...": the quest name under the arrow now wraps to
  two lines, and only names longer than two lines are cut.

## [0.0.3] - 2026-11-15

Third test build. Not yet tested on a device.

### Changed

- Quest arrow with no focused quest: instead of pointing somewhere, it says
  "No quest focused" and "Focus one in your quest log".
- Focused quest in another zone: the arrow says "Outside this zone" and
  "Head to <zone>".
- When the objective is behind you, the arrow is replaced by "Turn around".
- Quest icons: "Show icons for" now defaults to Tracked quests (your tracked
  quests plus the focused one). If 0.0.2 had you on Focused quest, you are
  moved to Tracked quests once; All quests is kept.

## [0.0.2] - 2026-11-15

Second test build, with fixes from the first device test of the quest
features. Not yet tested on a device.

### Changed

- Quest arrow follows the quest you **focus** in the quest log, instead of a
  quest picked by tapping an icon. With no quest focused, it points at your
  tracked quests. For a focused quest in another zone it names that zone.
- Quest icons: new "Show icons for" choice. Focused quest (default; with none
  focused, your tracked quests), Tracked quests, or All quests. The map is
  readable again.
- Tapping a quest icon only shows its text; it no longer changes the quest.
- Quest arrow is now a proper pointed arrow.
- The round "PE" button and the whisper badge are smooth instead of stepped.

### Fixed

- The blue haze stayed on the minimap. It is now hidden again after every
  loading screen and zone change (untested on device).

## [0.0.1] - 2026-11-15

Nothing in this version has run on a device yet.

### Added (untested on device)

- Settings window with one big on/off switch per feature, an Errors page, and
  the round "PE" button (also `/pe` and the minimap addon-list button).
- Quest icons on the map and minimap, with Blizzard's blue haze hidden.
- Quest arrow to the nearest objective in your zone, with distance.
- One big bag: Blizzard's combined bag with a big Sort button (L3 sorts while
  it is open) and three sizes.
- Sell junk automatically at vendors.
- Repair automatically from your own money.
- Big chat buttons: one per channel and per recent whisperer, with a badge for
  unanswered whispers.
- Layout helper (experimental): one-tap switch to Blizzard's Gamepad layout
  and back.

### Dependencies

- QuestieDB (the GitHub bundle pins 1.1.1; CurseForge installs the latest), for the two quest features.
