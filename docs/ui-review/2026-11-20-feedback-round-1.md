# UI review, round 1: owner feedback and proposals

These are the owner's notes on the "today" mockups (`mockup-0.8.1.html`) and what the "Proposed" version of that page shows in answer. Nothing here is built yet. Each item waits for the owner's yes before it goes into a spec.

## What the owner likes
- The default play screen is good: the round button, the quest arrow and the quest icons.
- Every arrow message except "No known location" reads well.
- The settings work well and are well organised. The complaint is how they look, not what they do.

## Feedback → proposal

| # | Owner feedback | Proposed (see the "Proposed" switch on the mockup page) |
|---|---|---|
| 1 | The arrow and its text are too big by default. Let each player pick any size, not just a few presets. | One size control, 50%–150% in steps of 10, scales the arrow and its text together. It no longer follows Button size, and Small/Normal/Large goes. It can be set in Move on screen while watching the arrow (a new Size row) or under Quest arrow in the settings. The default size is still to be decided. |
| 2 | "No known location" was unclear. | The top line reads "No map data for this quest", with "Quest: <name>" under it. |
| 3 | Turn around leaves a gap, and it is unclear that the line under it is the quest name. | The arrow stays and points back. The top line reads "Turn around · 120 yd". |
| 4 | Distance and Here show the same lines; make the quest name smaller and mark it. | The quest line is smaller (the small font) and starts with "Quest:", the same way turn-ins start with "Turn in:". "Here" is green in both the arrow and the text. |
| 5 | Hide "No quest focused" in cities and inns, as a choice. | A new Quest arrow choice, "No quest focused" in cities and inns: Hide / Show (default Hide). The API check is below. |
| 6 | The chat window's "Three-finger tap for the keyboard" is misleading. | Removed. Tapping a target already sets up "Press A to type". |
| 7 | The chat window is a big empty box with few channels. | The window is only as big as its buttons, centred, in 3 columns, with "Talk in" and "Whispers" headings. Unanswered whispers get a round red dot, like the round button's badge. |
| 8 | The settings need to look uniform: same sizes, same shapes, sleek and professional, easy to navigate. | Tabs down the left (Quest icons, Quest arrow, Bags, Vendors, Chat, Menu background, General, Errors) with one page at a time on the right. Every row is a name on the left and one control of one width on the right: a switch, a segmented choice, a number, or an action button. Selected always means a gold fill. A green dot on a tab shows that a helper there is on. Only one tab is drawn at a time, which is lighter. |

## The API check for item 5
Checked on the Forever branch of Blizzard's code, at the audit's pinned commit.
- `IsResting()` returns true or false (`PlayerScriptDocumentation.lua:1471`). It is the same flag as the "Zzz" resting icon, so it covers inns and cities. It is also true at some small rest spots, and it can lag a moment after you cross the edge.
- `PLAYER_UPDATE_RESTING` fires when that changes and carries no data (`UnitDocumentation.lua:3990`).
- The sanctuary checks (`GetZonePVPInfo` returning "sanctuary", `UnitIsPVPSanctuary`) miss faction capitals, so they are not used.

## Round 2 (same day)
- **Turn around:** no arrow at all. It reads "Turn around" with the quest line under it. *Done in the mockup.*
- **The new settings look is approved** ("beautiful").
- **Bigger bag:** when it is on, the bag pictures always go in one row at the top. It is meant to replace Blizzard's bag; with it off, the game shows its own. The "Bag pictures" choice is removed. *Done.*
- **Bag sorting:** it must say why someone would hide the Sort button: it is only for touch, because a controller player sorts with the stick click. A row can now have one short grey line under its name. *Done for Sort button, Sort stick and Chat text size.*
- **"Touch screen" under General feels out of place.** It was meant for setup. *Proposed:* rename it "I play with: Touch too / Controller only", with a line saying what Controller only hides. The other choice is to remove it from General and leave it to the setup guide. **The owner is undecided.**
- **Setup guide:** too much text. It needs a simpler way to say what each helper does and how it is used ("click the stick in to sort"). *Proposed:* 6 screens, the same cards as the settings, one line on what each helper does plus a "How:" line, only the main choices, and dots for progress.

## Round 3 (same day)
**Settings**
- "Blue quest haze" becomes "Blizzard blue quest haze".
- Quest arrow: "Place on screen" + "Move" was confusing across the wide gap. It is now "Position on screen" with the button "Move the arrow".
- Bigger bag's line is now "A bigger and better organized bag window."
- Bag sorting had too much explaining. The section line is now "Sort your bags with one press." The explaining moved into the choices: "Show, to tap" / "Hide", and "Left stick" / "Right stick". The blue status lines are gone from this card.
- General: "I play with" is now **Touch controls / Controller**.

**Setup guide**
- Welcome uses the same Touch controls / Controller choice. The navigation help was unclear; it now has a heading, "Getting around these windows", with D-pad, A and B pictures and what each does.
- Bags and Vendors: less text, with no "How:" lines. The helpers are renamed **Auto sell junk** and **Auto repair**.
- The tips on the last screen are now three tiles, each with a picture (the PE button, the PE button with a hold ring, the move outline).
- **New:** a "Round button" screen (colour and button size, with a live preview).
- **New:** a "Your screen" screen (a small picture of the starting spots, and "Move things now").

## Round 4 (same day)
- Bags: the Sort button choices are just "Show" / "Hide".
- The Menu background tab gets a heading card: "Fixes for the game's own interface", saying these fix parts of the default Blizzard UI that are hard to use on a handheld.
- **Setup pages are rebalanced.** The Quests page was crammed and did not show every choice, while other pages were near empty. Now there are 9 screens:
  1. Welcome
  2. Quest icons (switch, Show icons for, Icons on, Icon size)
  3. Quest icon details (Merge, Spots, Blizzard haze, and what each icon means; skipped while Quest icons is off)
  4. Quest arrow (every choice)
  5. Bags
  6. Vendors and menus (Auto sell junk, Auto repair, Menu background)
  7. Round button and chat (colour, button size, Chat picker and its choices)
  8. Your screen
  9. All set

  Every choice now appears in the guide.
- The All set tip tiles are all the same height, with the picture box, title and text on shared lines.
- **The chat window gets its own size, 70%–150%** (under Chat), the same kind of control as the quest arrow's.
- **Move on screen:** the third piece was hidden because Chat picker was off; that is how it works today, since the prompt is listed only while Chat is on. *Proposed:* always list all three, dim any whose helper is off with "(off)", and rename "Chat prompt" to "Press A to type".
- **Sort tab:** the same size, but cleaner. It is rounded on the outer side and joined to the bag, with one gold edge and the sort picture plus "Sort" in the middle instead of the stacked letters. The rounded corners need one small texture file; square corners need none.

## Open questions for the owner
1. The arrow's default size. It is 100% today. The owner likes it smaller, but other players may not.
2. Should the round button and "Press A to type" also get their own size control? Today the round button follows Button size.
3. The suggested feature names: Bigger bag, Bag sorting, Sell junk, Repair gear, Chat picker. Keep them or change them?
4. The setup guide is not redrawn yet. It should take the same row style once the settings style is agreed.
