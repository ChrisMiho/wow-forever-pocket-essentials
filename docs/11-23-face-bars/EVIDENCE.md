# Face bars: what we know (2026-11-23)

Everything proven so far that the "face bars" work stands on. The raw files
and the longer write-ups stay where they are:

- `docs/11-22-playsession/EVIDENCE.md`: probe 0.4.0 and 1.5 h of play on 0.10.0.
- `docs/11-23-playsession/EVIDENCE.md`: probe 0.6.0, part 1 (park, fade, fight
  tests) on a level 1 warrior, and three screenshots of the layout on it.
- `docs/11-23-ui-debug/FINDINGS.md`: Controller layout 0.11.0 on the owner's
  level 40 main, 16 screenshots, with the owner's comments.
- `docs/11-23-ui-debug/PocketProbe (1).lua`: three recordings (read with
  `scripts/read-probe.sh <file> --perf`).

Device: Retroid Pocket 6, game 1.60.1 (71037), screen 1365.3 by 768 UI units
at UI scale 1 (screenshots are 1920 by 1080: 1.406 pixels per unit). Gamepad
UI on. A Switch-labelled controller played Xbox-style.

## The idea, in the owner's words

"there are so many UI addons for WoW, that re-do the UI, can we not just
explore doing that as well? ... the only nuance, is figuring out where to
stick/hide buttons, since we cant split it, but im hoping the flat bars
solution can give us the visual organization we need, even if in reality, the
buttons are mapped in a different way thats hidden from the user."

"if we're making our own face bars, doesnt that mean we can still do the split
idea? we are drawing our own ui piece, the actual bars remain the same"

The rule "no bars or buttons of our own" was removed by the owner on
2026-11-23: "completely remove the rule if its blocking this work".

## Proven on the device

| Question | Answer | Where |
|---|---|---|
| Split the game's bar | **No**: the game puts every button back on each press | Blizzard source, `ActionBarStyles.lua:119-156` |
| Move and size whole bars, save our own Edit Mode layout | **Yes**, out of a fight | 11-22 EVIDENCE 3 |
| Main bar moved off screen still casts | **Yes** (out of a fight; moving it in a fight is not allowed) | 11-23 EVIDENCE 1 |
| Main bar faded to 0 still casts | **Yes**, three times; the game did not put the alpha back | 11-23 EVIDENCE 2 |
| Real fade (to 0 and back) in a fight | **Yes** | 11-23 EVIDENCE 3 |
| Invisible bar casts **during** a fight | Very likely, not proven: the answers were all given just after the fight ended | 11-23 EVIDENCE 2 |
| Read a spell's icon, "usable", "on cooldown" in a fight | **Yes** | 11-22 EVIDENCE 1 |
| Read cooldown start, duration, stack count in a fight | **No**, secret | 11-22 EVIDENCE 1 |
| `C_ActionBar.GetActionCooldownDuration` in a fight | **Readable** | 11-23 EVIDENCE 4 |
| `Cooldown:SetCooldownFromDurationObject` on our own frame in a fight | **Allowed** | 11-23 EVIDENCE 4 |
| `Cooldown:SetCooldown` with the secret numbers | **Refused** ("Secret values are only allowed during untainted execution") | 11-23 EVIDENCE 4 |
| Whether that sweep is actually drawn | **Unknown**: nothing was on cooldown | 11-23 EVIDENCE 4 |
| Take a controller button for our own frame in a fight | **No** | 11-22 EVIDENCE 7 |
| Game's profiler on the device | **On** | 11-23 EVIDENCE 6 |

## Found in Blizzard's source today (not yet tried on the device)

Paths under `~/.cache/wow-ui-source/forever/Interface/AddOns/Blizzard_GamepadActionBars/`.

- **Which bar is active:** `PageUnit:GetActiveBar()` (`PageUnit.lua:542`) and
  `PageUnit:RegisterActiveActionBarUpdatedCallback(callback, owner)` (`:705`),
  fired from `SetActiveActionBar` (`:527-539`) when a trigger is pressed or
  let go. A face can follow the trigger without checking every frame.
- **Wheels and fading:** when a wheel opens, the game sets the whole
  `PageUnit` to a low alpha and the wheel's popup to ignore its parent's
  alpha, then puts `PageUnit` back to alpha 1 when it closes
  (`PageUnit.lua:719-737`). The wheel re-parents itself to `UIParent` while
  open (`FlyoutRadial.lua:211-216`). Two consequences:
  - fade the four `*CenteredAnchor` frames or their `.Bar`, **never
    `PageUnit`**, or the first wheel undoes the fade;
  - a wheel opened from a faded bar is probably still visible, at the hidden
    button's spot. To be proven.
- **Bar sizes:** a bar that does not grow is 208 by 68; grown 266 by 86
  (`ActionBarStyles.lua:172-173`). One button 40 by 40 grown.

## The 0.11.0 layout on the main (from the screenshots)

See `docs/11-23-ui-debug/FINDINGS.md` for the full list. In short:

1. The both-triggers bar sits at 70% over the character's head: the owner
   read it as gone.
2. "Main bar above the map" puts the spells in the middle of the screen.
3. The map's title strip sits between the map and the bars above it. The
   game has a "header underneath" setting for the map.
4. "Main bar under the map": one wide row at the very bottom touching the XP
   bar, and the block (bars, map, both-triggers bar) is half the screen tall.
5. Buffs overlap the chat's last lines; the chat is a large tinted box.
6. **The XP bar stays at the bottom.** The approved mockup put it top middle,
   130% wide; the spec only set its width. A spec miss.
7. **The layout did not switch on by itself on the main**: the game remembers
   the active Edit Mode layout per character, Pocket Essentials' switch is
   account-wide. Off, reload, on, reload fixed it.
8. Every option row did what it says. Errors page: 0.

## Performance (three recordings, `PocketProbe (1).lua`)

Not a clean play session: run 3 had 10 reloads in 6 minutes while the owner
tried every option. Read with care.

- Frame rate 40 throughout (the device's cap at these settings).
- Pocket Essentials' own time: 0.003 ms per frame with features off; 0.02 to
  0.04 ms per frame with them on (light is under 0.1).
- Slow single runs: up to 44 ms, at reloads (core login work, Controller
  layout's placement 13 ms).
- `questIcons` ran about 38 times a second in run 2 (10,794 runs in 4 min 46 s,
  0.05 ms each): a per-frame driver while the map or minimap shows icons.
  Worth a look.
- Memory 1.2 MB with features off; up to 7.7 MB with them on, falling back
  after collection. The audit's shortlist item (quest pins built before
  thinning) is the likely cause.
- **Recorder bugs seen:** a memory reading of 0 right after a reload is
  stored as 0 ("least 0" in the report) and makes "kept growing" and
  "heavy" wrong; reloads inside a run are not marked in the report's plain
  words. Fix before trusting the "In plain words" lines.

## Open questions for the face bars

1. Can the face follow the trigger (LT, RT, both) through the game's callback,
   in and out of a fight?
2. Can the face show a press (the pushed flash)? The game animates its own,
   invisible button.
3. Is a wheel opened from a faded bar visible, and where?
4. Is the cooldown sweep drawn on our frame (needs a spell on cooldown)?
5. Does an invisible bar cast during a fight (answer given inside the fight)?
6. How often do the events a face needs fire in a fight
   (`ACTIONBAR_UPDATE_COOLDOWN`, `ACTIONBAR_UPDATE_USABLE`,
   `ACTIONBAR_UPDATE_STATE`, `ACTIONBAR_SLOT_CHANGED`, `SPELL_UPDATE_COOLDOWN`,
   `UPDATE_BONUS_ACTIONBAR`)? That is the face's CPU cost.

## The two sub-menu wheels (screenshots `docs/11-23-ui-debug/petUI/`, 11:19)

Owner's level 52 warlock, Controller layout on (map 70%, main bar under the
map). The owner: stance, totems and the other sub-menus "all look the same,
where the icons fall on the radial menu may change".

- **LB + LT (pet commands, 11:19:14):** a round wheel about 245 px across
  (about 175 UI units), centred on the left sub-menu button (centre about
  765, 815 px; 544, 189 units from the bottom left). Eight places on a ring
  plus the button in the middle. It covers the right half of the player frame
  and the left edge of the map.
- **RB + RT (pet spells, 11:19:26):** the same size, centred on the right
  sub-menu button (about 1152, 815 px). It covers the right part of the map.
- Both wheels open in place around their button, as the source says
  (`FlyoutRadial.lua:200-224`, radius 60 in its own units).
- For the face mockup: each sub-menu button needs a clear circle of about 175
  units around it, or the wheel lands on top of something. With the face,
  the game's real buttons can stay where they are (they ride on
  `BottomCenteredAnchor`), so the face should leave those two circles free.
