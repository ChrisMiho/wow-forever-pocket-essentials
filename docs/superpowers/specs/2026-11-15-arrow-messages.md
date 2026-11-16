# Arrow messages, "Turn around", tracked-quests default (0.0.3)

Status: approved by the maintainer on 2026-11-15 ("implement this and release
again"), after reading the 0.0.2 report. Builds on
`2026-11-15-quest-focus-and-polish.md`.

## Changes

1. **No focused quest:** the arrow does not fall back to other quests any
   more. No arrow; the text reads "No quest focused" over "Focus one in your
   quest log".
2. **Focused quest in another zone:** "Outside this zone" over "Head to
   <zone>" (the zone with most of its places; the quest name if the zone name
   cannot be read). A focused quest with no known place anywhere: "No known
   location" over its name.
3. **Turn around:** when the objective is more than 150 degrees from straight
   ahead, the arrow is replaced by the words "Turn around" (back to the arrow
   below 135 degrees, so it does not flicker at the edge). Distance and quest
   name stay. Never while "Here".
4. **Show icons for:** default is now "Tracked quests" (the quest tracker's
   quests plus the focused one), listed first. Players who have "Focused quest" saved
   from 0.0.2 (where it was the default) are moved to "Tracked quests" once;
   "All quests" and any choice made after that are kept.

## Not now

- Arrow across zones: wanted by the maintainer, still parked (PRD "Parked
  ideas"). "Outside this zone" is the stop-gap.
