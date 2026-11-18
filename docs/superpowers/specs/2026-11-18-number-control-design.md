# Number control, finer Quest icons, smaller arrow (0.7.0)

The owner described these in chat on 2026-11-18, after testing 0.6.0. They
picked mockup A for the number control ("option A for sure") and approved
the Merge range ("that sounds perfect").

## Why

- Spots per objective and Merge nearby icons give a few preset buttons.
  The owner wants to pick the exact amount.
- The owner uses Small icons and sometimes wants smaller, and finds the
  Normal arrow sometimes too big.
- Chat text size's "Smaller 14 Bigger" row looks plain ("a little ugly").
- Hide blue haze sits awkwardly among the size and count rows.

Success: these rows look tidy and let the owner fine-tune, and every saved
setting stays as it was.

## Approaches

1. **A new "number" row kind in the shared list drawer** (chosen). It
   follows the toggles from 0.6.0: a feature declares `number = { min, max,
   ... }` and `Settings.lua` draws the joined control. The settings window
   and the setup guide both get it.
2. Each feature draws its own – and + buttons. Rejected: the same code
   three times, and the setup guide would need a copy too.

## 1. The number control (mockup A)

One joined box, drawn on the row's line, beside its heading (the 0.6.0
label column):

```
Spots per objective    [ – |  5   | + ]
                             spots
```

- **Ends:** – on the left and + on the right are the box's two ends, dark
  fill with a gold sign.
- **Middle:** a darker well holding the value in large gold, with a small
  grey word under it (the row's unit).
- **Border:** gold all round, with gold lines between the ends and the
  middle.
- **End of the range:** an end with no further step is greyed out (sign
  dimmed). Pressing it does nothing.
- **Pressing:** works by touch and with the controller. The d-pad reaches
  – and + as two separate stops in reading order; the middle is not a
  stop.
- **Holding** – or + is not required.

**Rows that use it:**

| Row | Values | Shown as | Unit word | Saved value |
|---|---|---|---|---|
| Spots per objective | 1, 2, …, 20, then All | number, "All" | spots | `spots`: 1–20, 0 = All (unchanged) |
| Merge nearby icons | 0, 1, …, 10 | "Off" at 0, else number | merge | `cluster`: % of the map, 0 = off (unchanged) |
| Chat text size | the game's chat sizes (as today) | the size the game uses | text size | not ours (the game's chat font size) |

- **Spots:** + from 20 goes to All, and – from All goes to 20. Old saved
  values (3, 5, 10, 0) show as they are.
- **Merge:** old saved values 2 ("Normal") and 5 ("More") show as 2 and 5.
- **Chat text size:** the "(after the fight)" note and the "Not available
  on this version of the game" text stay as today.
- **Unusable saved values:** a saved value outside the range, or not a
  number, shows the feature's default and is not rewritten until a press.

## 2. Quest icons

- **Icon size:** **Extra small** comes first: Extra small, Small, Medium,
  Large. Extra small is 18 px on the map and 11 px on the minimap (on a
  720p screen; Small is 22 and 14).
- **Hide blue haze:** moves to the end of the Quest icons options, on the
  line before Icon key.
- **Order:** Show icons for, Icons on, Icon size, Merge nearby icons,
  Spots per objective, Hide blue haze, Icon key.

## 3. Quest arrow

- **Arrow size:** **Small** comes first: Small, Normal, Large. Small is
  56 px (Normal 76, Large 112).
- **Arrow position:** unchanged in this build.

## Not changing

- **Saved file:** its layout and every existing saved value.
- **Commands:** `/qd` keeps working. `/qd spots` and `/qd cluster` keep
  their words and also take a number.
- **The rest:** the other rows and features.

## Later builds (agreed in chat, each with its own spec)

1. **Move replaces the position buttons:**
   - Quest arrow and the round button lose their preset position buttons.
   - Each feature gets its own Move button, which opens Move things with
     that piece picked.
   - Reset returns the piece to the starting spot everyone gets.
   - A saved preset becomes that piece's starting point, so nothing jumps.
   - "Move things" gets a clearer label.
2. **Bags split in two:**
   - **Bag size** becomes its own feature with its own switch.
   - **Bag sorter** gets two toggles: "Sort button: On / Off" and "Sort
     stick: Left / Right".
   - D-pad to Sort goes away as a separate setting and is on whenever the
     Sort button shows. The owner device-tested it on 2026-11-18 and it
     works.
3. **Round button colour choices.**

## Device test

Settings and setup guide at Small and Large button sizes:

- Each number control steps through its whole range, and its ends grey out
  at the limits.
- Spots and Merge change the map at once, and they stay after a reload.
- Chat text size changes the chat.
- Extra small icons and the Small arrow show at their new sizes.
- The d-pad reaches – and + on every number control.

## Left to the builder

- Exact pixel sizes of the control's ends and middle, from the current
  button height.
- The dimmed sign colour.
- How the number row tells the drawer its range, display text and unit.
