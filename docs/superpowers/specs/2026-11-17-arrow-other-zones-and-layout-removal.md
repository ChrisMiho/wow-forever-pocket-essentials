# 0.3.0: the arrow points into other zones; the Layout helper goes

> **Section 2 was rolled back in 0.3.1** at the owner's decision of
> 2026-11-17 (postponed; see `docs/DECISIONS.md`). Section 1 stands.

Date: 2026-11-17. Status: **approved by the owner's instruction of 2026-11-17**
("can we remove that if it's descoped", "happy to keep blasting out features,
keeping them lightweight", said while stepping away). The choice of the arrow
as the next feature was made without the owner: it is the top item of the
PRD's "Parked ideas" and is marked "Wanted by the maintainer".

## 1. Remove the Layout helper

**What the player sees:** the "Layout helper" row (with "Use Blizzard's
Gamepad layout" and "Go back to my previous layout") is gone from the
settings. Nothing else changes.

**Why:** it was written before the first device test, has never been tried
in the game, and its one job (switching to Blizzard's Gamepad layout) is
something the game already does by itself when the Gamepad UI is on. The
part that was wanted, placing things without dragging, is now "Move things"
(0.2.0). It is also the only part of the addon that writes to the game's
Edit Mode, which is the riskiest thing an addon can touch.

**Rules:**
- `Layout.lua` is deleted and taken out of the addon's file list. No other
  addon file calls it.
- A player who had it switched on in 0.2.1 loads 0.3.0 with no error and no
  message; the saved leftovers are ignored, not cleaned.
- The game's Edit Mode layouts are not touched by the removal (whatever
  layout is active stays active).
- The restriction probe (`probe/PocketProbe`) keeps its own layout trials;
  the stand-in game client keeps its Edit Mode parts for them.
- PRD: the bundled handheld layout leaves "Parked ideas" and becomes a
  non-goal. Goal 5 is covered by "Move things".

## 2. The quest arrow points into other zones

**What the player sees:** today, when the focused quest is in another zone,
the arrow is replaced by "Outside this zone / Head to Duskwood". With the
new choice switched on, a **light blue** arrow points straight at the
nearest spot of that quest in the other zone, with the distance, and the
line under it reads "Duskwood - Morbent Fel". On entering the zone the arrow
turns gold and behaves exactly as it does now.

**The setting:** under "Quest arrow", a new choice **"Quest in another
zone"**: "Name the zone" (default, today's behaviour) or "Point the way".
It defaults to today's behaviour because pointing across zones has not been
tried on the device.

**How the direction is worked out:** the game can convert a place on any
zone map into a position on the whole continent
(`C_Map.GetWorldPosFromMapPos`, documented in Blizzard's source for this
build). Two sample points per map give that map's conversion; it is worked
out once per map and kept. With the conversion of the player's map and of
the spot's map, the spot gets a position on the *player's* map (it may lie
outside the map's edges), and from there the existing arrow maths is used
unchanged. No assumption is made about which way the continent's axes run.

**When it does not point** (the text "Outside this zone / Head to <zone>"
stays, as today):
- the choice is on "Name the zone";
- the spot's zone is on another continent;
- the game gives no conversion for either map, or the call fails;
- a map's conversion does not fit its known size (north-south span against
  the map's height, east-west against its width, within 5 %; a map whose
  size cannot be read does not fit). This is the guard against a
  confidently wrong arrow, the reason the first version was removed.

**Rules:**
- Target: the nearest spot, in a straight line, among all the focused
  quest's spots on other maps of the player's continent. Chosen again once a
  second while moving, like today. The current target is kept unless another
  spot is under 80 % of its distance and at least 15 yards nearer (the
  existing rule and numbers).
- A spot on the player's own map always wins: the other-zone arrow only
  shows when the quest has no spot on the map the player is on.
- No "Here" and no setting aside for an other-zone target: it always shows
  yards. "Turn around" works as today.
- Colour: light blue (0.55, 0.80, 1.00) for an other-zone target; gold and
  green are unchanged.
- Text under the arrow: `<zone> - <the usual title>` (so a turn-in reads
  "Duskwood - Turn in: Morbent Fel"), cut to the usual length. If the zone
  name cannot be read, the usual title alone.
- The spot pointed at is published to the quest icons as today, so its icon
  is kept on the world map.
- Changing the setting takes effect at once, no reload.
- Cost: nothing new ticks. The conversion is two game calls per map, once.
  A failed conversion is tried again after the next zone change.
- Debug log: one line per change of state, "pointing across zones at quest
  N ... spot X,Y on map M from map P"; when the choice is on but it cannot
  point, the existing "text only" line ends with the reason ("another
  continent" or "no conversion").

**Not in this version:** routes (roads, boats, zeppelins, flight paths),
other continents, dungeons. The arrow is a straight line and the colour and
the zone name say so.

**What only the device can prove:** that the arrow's direction into a
neighbouring zone matches the world map. If it is wrong, the setting goes
back to "Name the zone" and nothing else is affected.

## Version

0.3.0. The Layout helper's removal is listed under "Removed" in the
changelog.
