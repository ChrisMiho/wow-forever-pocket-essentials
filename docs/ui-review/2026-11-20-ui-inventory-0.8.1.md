# UI inventory: what Pocket Essentials draws (0.8.1)

Step 1 of the UI review. This lists only what the addon draws itself. The game's own frames are out of scope; they are only the things ours attach to.
Read from the code at commit 4a59e9e. Nothing was changed.

All sizes are **pixels on a 1080p screen at the Medium button size**. The code writes every size for a 720p screen and scales it to the screen's height. So on the owner's 720p device, divide every number here by 1.5 (a button is 56 tall, not 84). The layout is the same share of the screen at both sizes. The exceptions are the things drawn in raw units, which do not scale: the 1-unit edges on the scroll track and menu background, the menu background's 6/3 outreach, and the text shadow.

## Shared building blocks

| Measurement | Small | **Medium** | Large |
|---|---|---|---|
| button height | 72 | **84** | 102 |
| row height | 84 | **99** | 120 |
| gap | 12 | **15** | 18 |
| pad | 18 | **21** | 24 |
| text | 33 | **37.5** | 43.5 |
| small text | 27 | **30** | 34.5 |
| title text (text × 1.12) | 37 | **42** | 49 |
| round button | 84 | **90** | 108 |
| border | 3 | **3** | 3 |

- **Fonts:** all text uses the game's normal face (Friz Quadrata) with a black shadow. There are three kinds:
  - text: white
  - small: grey (0.84)
  - title: gold (1, .82, 0)
- **Extra text colours in the settings:**
  - status: blue (.65, .85, 1)
  - warning: amber (1, .60, .20)
  - dim: (.62, .62, .62)
- **Button:** a flat fill inside a flat border, with a centred single-line label. Default size is 252×84. Tapping flashes it white (0.3), fading over 0.3 s.
- **Controller highlight:** a cyan frame (.25, .92, 1) drawn inside the button, 7.5 px thick.
- **Button styles** (fill / border / text):

| Style | Fill | Border | Text | Used for |
|---|---|---|---|---|
| normal | .15 .16 .19 | .52 .52 .57 | white | most buttons |
| on | .07 .40 .13 | .35 .92 .45 | white | ON switch, toggles saved as true, Finish |
| off | .25 .25 .27 | .52 .52 .54 | .82 grey | OFF switch, other toggles |
| warn | .52 .28 .03 | 1 .62 .15 | white | Reload now, PROBLEM, unanswered whispers |
| tab | .07 .06 .04 | .80 .64 .20 | gold | bag Sort tab |
| disabled | .11 .11 .12 | .27 .27 .29 | .5 grey | blocked switch |
| step / stepDim | .15 .16 .19 / .11 .11 .12 | .62 .52 .22 | gold / .33 | number control ends, scroll arrows |
| selected | .56 .42 .03 | 1 .82 0, 6 px thick | white | the current choice |

- **Badge:** a red square (.85, .08, .08) with small white text, sticking out of a button's top-right corner. The chat window's "NEW" uses it.
- **Panel (window):**
  - Centred on screen, with a gold-brown border (.62, .52, .22) and a near-black fill (.05, .05, .07).
  - Title bar 99 tall with the gold title on the left and a "Close" button (168×84) on the right.
  - A gold line under the title bar.
  - The content area starts 117 from the top, inset 21 on each side.
  - B, Escape and Close shut it.
- **Scroll area:**
  - A 63-wide column on the right: a "^" button (63×84) at the top, "v" at the bottom, and a dark track with a gold thumb between them.
  - Shown only when Touch screen is Yes.
  - With Touch screen No, the d-pad scrolls the list by itself.

## Screens and pieces

### A. Round button ("PE")
- 90×90 circle, always on screen, on the left edge of the middle of the screen by default.
- Gold ring 6 px wide, dark fill, "PE" in 37.5 text in the ring colour.
- **Colours:**
  - Gold: ring 1, .82, 0 on a dark fill
  - Horde: red .85, .15, .10
  - Alliance: blue .35, .62, 1
- **Pressed:** the fill lights up for 0.15 s.
- **Holding** for 0.6 s opens the settings. Nothing shows the hold while it is happening.
- **Red circle badge**, 45 across, near the top-right: the count of unanswered whispers.
- **On the world map:** it sits on the map's book icon. It goes back when the map closes or is made full screen.
- **Tap:** opens the chat window when Chat is on, otherwise the settings.

### B. Settings window: main page
- 1770×994, title "Pocket Essentials". The list is 1650 wide because the scroll bar always shows when Touch screen is Yes.
- **Header (only when needed):**
  - An amber "old QuestDots folder" line.
  - Amber reload reasons, with a **Reload now** button (378×84, warn style).
- **One row per feature, in this order:**
  1. Quest icons
  2. Quest arrow
  3. Bag sorter
  4. Bag window
  5. Sell junk automatically
  6. Repair automatically
  7. Chat from round button
  8. Menu background
- **Each row:**
  - Grey separator line.
  - Name (white), description (small grey), blue status lines, amber problem line.
  - On the right: **ON/OFF switch** (235×84: green ON, grey OFF, dim when blocked, amber PROBLEM).
  - Left of the switch: **Show options / Hide options** (286×84), if the feature has options.
- **Options under a feature** (indented 42):
  - A gold small heading, either to the left of its buttons or above them when they don't fit beside it.
  - **Choice buttons** are whole "slots" wide: 252, 519, 786 or 1053, with 15 between them. The current choice is gold (selected).
  - **Toggle:** one button reading "Label: Choice". Green only if the saved value is true.
  - **Number control:** − [value / unit] +, 347 wide in all.
  - **Action buttons:** at least 2 slots (519) when alone on a line.
- **Options per feature:**
  - Quest icons:
    - Show icons for: Tracked quests / Focused quest / All quests
    - Icons on: Map and minimap / Map only / Minimap only
    - Icon size: Extra small / Small / Medium / Large
    - Merge icons closer than: 0–10 % of map
    - Spots per objective: 1–20 / All
    - Hide Blue Quest Haze: On/Off
    - Quest Icon Key (opens a page)
  - Quest arrow:
    - Move the arrow
    - Arrow size: Small / Normal / Large
  - Bag sorter:
    - Sort button: Off/On
    - Sort stick: Left/Right
  - Bag window:
    - Bag size: Normal / Large / Extra large
    - Bag icons: In the grid / One row at the top
  - Chat: Chat text size (number control). It shows even when Chat is off.
- **Pocket Essentials section** at the bottom (gold title):
  - Button size: Small / Medium / Large
  - Button colour: Gold / Horde / Alliance
  - Move the round button
  - Touch screen: Yes/No
  - Tip: "press and hold the round button to open this window." (dim)
  - Bottom row: **Reload UI · Errors (N) · Move on screen · Setup guide**

### C. Settings window: Errors page
- Title "Pocket Essentials - Errors".
- Header: **Back** and **Clear** (294×84 each).
- **Debug log block:**
  - Gold heading.
  - Grey help text.
  - Blue "N of 10,000 lines".
  - ON/OFF switch.
  - Buttons: **Save log now** and **Clear log**.
- **Error list:** each entry has a gold "Feature xN last: date" line, a white message and a dim stack trace. When empty it reads "No errors recorded."

### D. Settings window: Quest Icon Key page
- Title "Pocket Essentials - Quest Icon Key", with **Back** in the header.
- Five rows, each a coloured 84×84 icon, a name and a description:
  - Kill: red
  - Loot: yellow
  - Use: blue
  - Explore: purple
  - Turn in: yellow "?"
- Two dim footer lines.

### E. Setup guide window
- Same size as the settings window. Title "Pocket Essentials - Setup guide (i of n)".
- **Bottom row:**
  - **Back** and **Skip** on the left.
  - **Start / Next / Finish** on the right (294×84 each). Finish is green.
- **Body:**
  - A gold screen title, then white paragraphs.
  - Each feature block has a line, a **gold** name, grey text, a switch and the same options as in settings, without a fold button.
- **Screens:**
  1. Welcome, including "Do you use the touch screen?" Yes/No
  2. Quest icons
  3. Quest arrow
  4. Menu background
  5. Bags (two features)
  6. Vendors (two features)
  7. Chat
  8. The round button and Move on screen (4 paragraphs, no controls)
  9. All set: lists what is on and what is off, with Reload now if needed

### F. Chat window
- 1180×662 at code scale (about 1770×993 on the device). Title "Chat".
- A **Settings** button next to Close.
- Hint text: "Three-finger tap for the keyboard".
- **Buttons in up to 4 columns** (about 420 wide each, 105 or 84 tall):
  - Say, Yell, Party, Raid, Guild, and one per numbered channel.
  - Gold "Whispers" heading, then up to 6 name buttons. Unanswered ones are amber with a red "NEW" badge.
  - "Clear marks".

### G. "Press A to type" prompt
- Black box (alpha 0.75, no border), centred 165 above the middle of the screen.
- Gold title "Press A to type", then white "Chat is set to <name>".
- Lasts 12 s.

### H. Quest arrow
- Sits in the background layer at the top centre, 60 down.
- The box is 600 wide.
- **Arrow:** 114 at Normal (84 at Small, 168 at Large), gold. It turns green at "Here".
- **Distance line:** gold title text, "120 yd" or "Here".
- **Quest name:** white, up to 2 lines.
- **"Turn around"** replaces the arrow when the target is behind you.
- **Message variants:**
  - "No quest focused" / "Focus one in your quest log"
  - "Outside this zone" / "Head to <zone>"
  - "No known location"

### I. Quest icons on the map and minimap
- **Coloured markers:**
  - Kill: red
  - Loot: yellow
  - Use: blue
  - Explore: purple
  - Turn-in: yellow "?"
- **Map icon size:** 42 at Medium (27, 33, 42, 54), and ×1.25 for the focused quest under All quests.
- **Minimap icon size:** 27 at Medium. Turn-ins beyond the edge sit faded on the rim.
- **Tap label:**
  - A 600-wide box with a grey border.
  - Lines: gold quest name, the objective, "Kill: X" in grey, and "Inside <place>" in light blue.
  - Sits above the map icon, or under the minimap. Gone after 5 s.

### J. Bag Sort tab
- A tall gold-edged tab outside the bag window's left edge: 84 wide and at least 294 tall (half the bag's height).
- Blizzard's sort icon at the top, then the letters S-o-r-t stacked in gold.

### K. Move on screen
- A small window (about 840×420) in the bottom-right, or bottom-left if it would cover the piece.
- **Left:** piece buttons: Quest arrow, Chat prompt, Round button. The chosen one is gold.
- **Right:** a cross of Up / Left / Reset / Right / Down.
- **The piece being moved** gets a gold outline, a faint gold fill and its name in gold.

### L. Menu background
- A dark panel (.05, alpha .95) with a grey 1-unit edge behind the game's pop-up menus, slightly bigger than the menu.

## Things that already don't match (cleanup candidates)

**Colours and look**
1. Four different "dark box" looks for the same job:
   - window: gold-brown edge
   - tap label: grey edge
   - "Press A" prompt: black, no edge
   - Sort tab: a third gold edge
2. Three golds for edges (.62/.52/.22, .80/.64/.20, 1/.82/0) and three greens for "on / here / turn in".
3. Two red badges: a square one on chat buttons and a round one on the PE button, each sized by its own rule.
4. Line thickness varies: 3, 6, 7.5, 6, and 1 unscaled unit (which won't grow with the screen).
5. Toggles: green means "the saved value is true", not "on". So "Sort stick: Left/Right" is always grey, and "Bag icons: One row at the top" turns green.
6. Feature names are white in settings but gold in the setup guide. "Debug log" is gold.
7. The arrow turns green at "Here", but the "Here" text stays gold.

**Words**

8. Mixed case: "Hide Blue Quest Haze" and "Quest Icon Key" use Title Case; everything else is sentence case.
9. Yes/no words differ: switches say ON/OFF, toggles say On/Off, Touch screen says Yes/No. On/Off order flips between toggles (Haze On first, Sort button Off first).
10. Feature names follow no pattern:
    - "Sell junk automatically" and "Repair automatically" are phrases.
    - "Chat from round button" is long.
    - The setup guide uses different names: Bags, Vendors, Chat.
11. The scroll bar uses "^" and "v" while Move uses "Up/Down".
12. Status lines are written in mixed styles ("Hidden while…" vs "Hidden: the game…"), with and without full stops.
13. Two "problem" messages say different things: "See Errors at the bottom of this list" vs "See Errors in the settings".

**Clutter and duplicates**

14. Three ways into Move on screen: Move the round button, Move on screen, Move the arrow.
15. Two reload buttons can show at once (Reload now, Reload UI). "Save log now" also just reloads.
16. The Errors page has Clear (errors) and Clear log (debug log) side by side, which are easy to mix up.
17. The "press and hold" tip always shows, and the setup guide says it again.
18. Chat text size makes the Chat row show options even while Chat is off.
19. Setup screen 8 is four paragraphs explaining settings without showing them.
20. Answering "No" to touch screen quietly turns off the bag Sort button.

**Size and spacing**

21. Button widths follow no common rule. As multiples of the button height:
    - switch 2.8
    - fold 3.4
    - Back/Next 3.5
    - Reload now 4.5
    - slots 3, 6.2, 9.4
    - a lone action is at least 6.2, so "Move the arrow" looks oversized
22. Spacing uses 0.3, 0.4, 0.5, 1 and 1.5 × gap. The indent differs between features (42) and the Errors/Key pages (15).
23. The settings window always keeps the scroll bar when Touch screen is Yes, even on a short page, losing 78 px. Setup only adds it when needed.
24. Headings sit beside their buttons on some rows and above them on others within the same feature.

**Left-over code (not visible, but weight)**

25. Saved values that nothing on screen sets any more:
    - the round button's six preset positions (`ui.hubPos`)
    - the arrow's five positions (`position`)
    - old bag keys (`size`, `iconRow`, `dpad` in Bag sorter)
26. The minimap tap label is 600 wide and hangs under the minimap, over the quest tracker and buffs.
