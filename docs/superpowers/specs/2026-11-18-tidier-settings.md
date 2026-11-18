# Tidier settings (0.6.0)

Approved by the owner on 2026-11-18 in chat: items 1 to 4 below. Item 4's
form ("one How to sort choice") is the recommendation the owner did not
overrule ("start with just implementing what I've approved").

Goal: fewer buttons and fewer heading lines in the settings window, with
the same saved values underneath. The setup guide draws options with the
same code, so it changes the same way.

## 1. One-tap toggles

A two-way choice is drawn as one button that reads `<label>: <current
choice>` and flips to the other choice on a tap. Rows of this kind that
follow each other sit side by side on one line (wrapping when narrow).
There is no heading line above them. A toggle whose current value is
`true` is green ("on" style), otherwise grey ("off" style).

- Quest icons: "Hide blue haze: On / Off".
- Bag sorter: "D-pad to Sort: Off / On", "Bag icons: In the grid / One row
  at the top".

Saved keys and values do not change; OnChange runs as before, with the
new value.

## 2. Map and minimap icons in one choice

Quest icons' "Map icons" and "Minimap icons" rows become one row
"Icons on": "Map and minimap" / "Map only" / "Minimap only". It writes the
existing saved keys `map` and `mini`. A saved pair with both off (only
possible from older versions or `/qd`) marks no button. `/qd map` and
`/qd mini` keep working.

## 3. Heading beside its buttons

A choices row and a buttons row (Chat text size) put their heading to the
left of their buttons, on the same line, when all the buttons fit on one
line beside it. Headings of one feature share one column width (the
widest heading, at most 40% of the row). When the buttons would not fit
on one line, the row is drawn as before: heading above, buttons below.
The same applies to "Button size" and "Round button position".

## 4. Bags: "How to sort"

"Sort key" and "Sort button" become one row "How to sort":
"Button + left stick" / "Button + right stick" / "Button only" /
"Left stick only" / "Right stick only". It writes the existing keys
`sortKey` and `showTab`. There is no longer any way to pick no way to sort.
A saved file with `sortKey = "none"` and `showTab = false` is repaired at
load to `showTab = true`.

## Not changing

Feature switches, fold buttons, Icon key, the Errors and Icon key pages,
the saved file's layout, and the `/qd` commands.

## Device test

Settings and setup guide at Small, Medium and Large button sizes: the
toggles flip and stay after a reload; "Icons on" shows and hides map and
minimap icons; "How to sort" changes the stick and the Sort tab;
headings sit beside their buttons where they fit.
