# 0.0.4: green minimap fix and arrow text that fits

Status: approved by the owner 2026-11-15; built as 0.0.4.

## Why

Second device test of 0.0.3 (PRD.md "Status", findings 3 and 6). Two bugs
stop the quest features feeling playable on the Retroid Pocket 6. Fixing just
these lets the owner play with the addon while the next features are designed.

## Findings

1. **Green minimap.** With "Hide blue haze" on, focusing a quest that has a
   quest area turns the minimap green. With the option off and a reload, it
   does not. Cause: `ZeroMinimapBlobs` (`QuestIcons.lua`) swaps the minimap's
   quest and task blob textures for `Icons/blank.tga`. The minimap cannot draw
   that file, and a texture the game cannot draw shows as solid green. This
   was logged as a risk in `docs/ARCHITECTURE.md`.
2. **Cut-off arrow text.** "Focus one in your quest log" ends in "...". The
   line under the distance (`titleText` in `QuestArrow.lua`) is one line of
   fixed width (13 times the font size) with word wrap off.

## Goals

- No green minimap with "Hide blue haze" on.
- The haze stays hidden on the minimap (as in 0.0.3).
- The arrow's small line shows whole messages, for example "Focus one in your
  quest log" and "Head to <long zone name>".

## Non-goals

- Map flooding from quests with many spots (next item, its own spec).
- Icon key, reload button, radial wheel, quest-log colours (parked).

## Approaches

Green minimap:
- **A. Remove the texture swaps and keep the alphas and ring scalars at 0
  (chosen).** The likely real fix in 0.0.2 was setting the haze again after
  loading screens and zone changes, not the textures. No new risk.
- B. Swap to a transparent texture built into the game instead of ours. Kept
  as the fallback if the haze comes back with A, because no built-in file is
  verified as transparent and drawable by the minimap.
- C. Keep our texture but in a different size or format. Rejected: guesswork
  without a client to try it on.

Arrow text:
- **A. Let the small line wrap to at most two lines and make the arrow's frame
  tall enough for it (chosen).** Covers long zone names and quest titles too.
- B. Shorter wording. Rejected on its own: zone names and quest titles can
  still be too long.

## Design

1. `QuestIcons.lua`: drop the six `Set...Texture` entries from
   `BLOB_SETTINGS`. Alphas and ring scalars stay. Update the comments that
   mention the blank texture.
2. Remove `Icons/blank.tga` and its line in `scripts/make_art.py`, and update
   every doc that lists it (ARCHITECTURE.md, the build's file list if it
   names it).
3. `QuestArrow.lua`: the small line (`titleText`) wraps, at most two lines
   (`SetMaxLines(2)`, verify in wow-ui-source), still centred. The display
   frame's height grows by one line so the second line is never clipped.
   The distance line and "Turn around" stay single-line. `Shorten` (used for
   "Head to <zone>" and quest titles) should not cut text that now fits in
   two lines; adjust or drop it as needed.
4. Version 0.0.4 in the TOC and CHANGELOG. Record the finding (the minimap
   cannot draw our blank texture; it turned green) in ARCHITECTURE.md "Facts"
   and the unverified-API table.

## Device test

1. "Hide blue haze" on, reload. Focus several quests in turn: the minimap never
   turns green, and no blue haze shows on it.
2. Go through a loading screen (enter or leave an instance or a city with one)
   and focus a quest again: still no haze, no green.
3. With no quest focused, the arrow shows "No quest focused" and, below it,
   "Focus one in your quest log" in full, on two lines if needed.
4. Focus a quest in another zone: "Head to <zone>" shows in full.

## Left to the builder

- Exact height added to the arrow frame.
- Whether `SetMaxLines` is available; if it is not, wrap without it and size
  the frame for two lines.
