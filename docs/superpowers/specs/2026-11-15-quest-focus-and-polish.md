# Quest focus and visual polish (0.0.2)

Status: approved by the maintainer's instruction of 2026-11-15 ("orchestrate
these fixes and release the next version, don't ask me questions while I'm
gone, I'll follow up on anything I disagree with"). Written from the first
device test report of 0.0.1. Review on return.

## What the first device test showed (0.0.1, Retroid Pocket 6)

1. Quest icons and the arrow run with no errors; the settings menu is easy.
2. The round "PE" button looks pixelated.
3. The arrow has no real point.
4. The arrow could not be made to point at the quest the player wanted.
   Tapping an icon to pick a quest is awkward. The game's quest log already
   has "Focus" for a quest; the arrow should follow that.
5. Far too many icons on the world map: the map cannot be read. The minimap
   is better with "Merge nearby icons" but still too busy.
6. The blue haze is still drawn on the minimap.

## Changes

### A. The focused quest drives the arrow and the icons

- "Focus" in the quest log (right-click/long-press a quest → Focus) is
  Blizzard's super-tracked quest: `C_SuperTrack.GetSuperTrackedQuestID()`,
  changed event `SUPER_TRACKING_CHANGED` (both documented in
  `SuperTrackManagerDocumentation.lua`, forever 1.60.1 (70938); the Focus
  menu entry is `QuestMapFrame.lua:2385`).
- `QuestData`'s "tracked quest" becomes exactly the focused quest. Our own
  saved `questData.tracked` value is no longer used for picking (leave old
  saved data harmlessly unread). `QD:GetTrackedQuest()` returns the focused
  quest ID when it is a positive number and in the log, otherwise nil.
  `SUPER_TRACKING_CHANGED` fires the existing `"tracked"` callback.
  `QD:SetTrackedQuest` stays (sets Blizzard's focus) but nothing in the addon
  calls it any more.
- `QuestData` also watches `QUEST_WATCH_LIST_CHANGED` (as a "quests" reason;
  no rebuild is needed for it, just a callback so icon filters refresh) and
  offers `QD:GetWatchedQuests()` → array of quest IDs in Blizzard's quest
  tracker (`C_QuestLog.GetNumQuestWatches`,
  `C_QuestLog.GetQuestIDForQuestWatchIndex`), guarded.
- Tapping a quest icon no longer changes the focus. It only shows the text
  box (minus the "Tracking this quest" line).

### B. The arrow

- Points at the nearest objective of the focused quest on the current map.
- If the focused quest has no place on this map, the arrow hides and the text
  reads "In <zone name>" (from `C_Map.GetMapInfo(mapID).name` of the map with
  the most pins for it; lowest map ID on a tie, so the choice is stable), falling back to today's "Not in this zone".
- With no focused quest: points at the nearest objective of the quests in
  Blizzard's tracker; with none of those either, the nearest of any quest
  (today's behaviour). The status line in settings says which rule is in use
  only when hidden, as today.
- Module description becomes: "Points to your focused quest. Focus a quest
  from the quest log."
- New look: one texture, `Icons/arrow.tga` (white fill, dark outline baked
  in, a proper pointed head with a notched tail), turned with
  `Texture:SetRotation(rel)` (documented in
  `SimpleTextureBaseAPIDocumentation.lua`), tinted gold / green ("Here")
  with `SetVertexColor`. The rotation sign convention stays as now: `rel` is
  counter-clockwise from up, and `SetRotation` turns counter-clockwise for
  positive radians. Keep the "DEVICE CHECK" flip line. If `SetRotation` is
  missing, fall back to the current three-line drawing.

### C. Fewer icons

- New option on Quest icons, first in the list: "Show icons for":
  - "Focused quest" (default): only the focused quest's icons. With no
    focused quest, the quests in Blizzard's tracker.
  - "Tracked quests": the quests in Blizzard's tracker, plus the focused one.
  - "All quests": today's behaviour.
- Applies to both map and minimap. Turn-in icons follow the same filter.
- Filtering happens at draw time in `QuestIcons.lua` (a reused set table,
  rebuilt only on "quests"/"tracked" callbacks and option changes), not in
  `QuestData`.
- With the filter, the focused quest is no longer drawn larger (all shown
  icons are equal) except in "All quests" mode where the existing 1.25x stays.

### D. Minimap haze

- Blizzard code never sets the minimap blob values, so the engine owns them.
  Likely cause of the failure: our values are applied when the feature turns
  on at login, then reset when the world (re)loads. Fix, all guarded:
  - Re-apply on `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA` and
    `SUPER_TRACKING_CHANGED`/quest-watch changes (cheap: six setter calls).
  - Besides the six alphas, also set the inside/outside/ring textures of the
    quest and task blobs to a fully transparent shipped texture
    (`Icons/blank.tga`) and the ring scalars to 0.
  - Still restored only by reload (prompt unchanged).
- Logged as unverified; a device test step checks it.

### E. Round button and discs

- `UI:CreateDisc` keeps its interface (`SetColor`, `Layout`, `SetShown`) but
  draws one texture of a smooth anti-aliased circle (`Icons/circle.tga`,
  white, tinted with `SetVertexColor`) instead of horizontal strips. Every
  disc (the PE button ring and fill, the whisper badge) becomes smooth.

### F. Art

- `scripts/make_art.py` gains a mode (e.g. `--icons`) that writes
  `addons/PocketEssentials/Icons/arrow.tga`, `circle.tga`, `blank.tga`:
  32-bit uncompressed TGA, power-of-two sizes (arrow 128x128, circle
  128x128, blank 8x8), supersampled for smooth edges. Original art.

## Out of scope

- Arrow across zones (still parked).
- Any change to bags, vendor, chat, layout.
- Default on/off states (all features stay off by default until passed).

## Version

0.0.2: second test build, fixes from the first device test. TOC `## Version`
and CHANGELOG together.

## Device test (for the hand-off)

1. Round button looks smooth.
2. Quest icons on, default "Focused quest": focus a quest in the log; only
   its icons on map and minimap; focus another, icons switch.
3. "Tracked quests" and "All quests" choices behave as described.
4. No blue haze on the minimap after login, after a loading screen, and
   after changing zone.
5. Arrow on: it points at the focused quest; it has a clear point; focusing
   a quest in another zone shows "In <zone>"; walking up turns it green
   "Here".

## Build notes (review of 2026-11-15)

- Zone name: the map with the most pins is used, not "the first" (the order
  of maps is not fixed). Amended above.
- Known difference: in "Focused quest" mode with nothing focused and an empty
  quest tracker, the map shows no icons while the arrow still points at the
  nearest objective of any quest.
- Accepted as is: with nothing focused, the arrow re-reads the tracker list
  at most once a second while moving (small cost).
