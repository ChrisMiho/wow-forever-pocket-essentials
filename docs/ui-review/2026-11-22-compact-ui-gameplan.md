# Compact controller screen: game plan to 1.0.0

Written 2026-11-22 from `docs/11-22-playsession/EVIDENCE.md`, while the owner
was away. The owner's aim: "more screen to enjoy without having to look at my
spell buttons taking up half the screen".

## What we know

| Question | Answer | Proof |
|---|---|---|
| Split a bar around the map | **No.** The game puts every button back on each press, in a fight too | Blizzard source, `ActionBarStyles.lua:119-156` |
| Move and resize whole bars | **Yes**, out of a fight | Device, EVIDENCE 3 |
| Save our own Edit Mode layout | **Yes**, out of a fight | Device, EVIDENCE 3 |
| Fade a bar | **Yes** as far as tested: setting the see-through value is allowed in a fight. A real change (to 0 and back) is not proven | Device, EVIDENCE 2 |
| Read the main bar's spells in a fight | **Partly.** Icon, "on cooldown", "usable": yes. Cooldown times and stack counts: secret | Device, EVIDENCE 1 |
| Take controller buttons in a fight | **No** | Device, EVIDENCE 7 |
| A parked or faded bar still casts | **Unknown.** Last test gave no answer | EVIDENCE 4 |
| Our own button can show a cooldown sweep in a fight | **Unknown.** Blizzard's docs mark the calls as protected, so "no" is likely | `FrameAPICooldownDocumentation.lua:281-318` |

One thing the evaluation turned up: the bar size in 0.11.0 (208 by 68) was
not a guess after all. It is Blizzard's own size for a bar that does not grow
when its trigger is held (`ActionBarStyles.lua:172`), and Controller layout
switches that growing off. The 266 by 86 the probe measured is the grown bar.
The map was the wrong guess: it is 273 by 283 at full size, so about 218 by
226 at 80%, not 164 by 176.

## Three ways to get screen back, cheapest first

1. **Arrange and shrink (Controller layout, 0.11.0).** Built. Everything it
   does is proven allowed. Gets the map and bars into one block at the
   bottom and lets every bar shrink to 70%. This build adds a **Map size**
   choice (60, 70 or 80%), because the real map is a third bigger than the
   mockup assumed.
2. **Fade what you are not using (Quiet bars).** Spec drafted
   (`docs/superpowers/specs/2026-11-21-quiet-bars.md`), not built. The
   LT, RT and both-triggers bars fade until their trigger is held; all bars
   can fade out of a fight. Needs one probe answer: a real fade in a fight.
3. **Flat strip in place of the main bar.** Our own single row of eight
   small icons near the map, with the game's main bar faded to nothing
   behind it. It shows icons and "can't use now"; it never takes a press
   (the game's own bar still does the casting). Needs two probe answers:
   does a faded bar still cast, and can we draw a cooldown sweep. If the
   sweep is refused the strip can still dim an icon while it is on
   cooldown, which the probe already proved readable.

## Order to 1.0.0

1. **Now (this build):** Pocket Probe 0.6.0 and Pocket Essentials 0.11.0
   with the measured map size, in one pre-release. Device test: the probe's
   short UI tests first (section 23), then normal play with the probe's
   performance recorder on (section 24) and the layout (section 21).
2. **Then:** fix what the layout test shows (spots, gaps, default sizes).
3. **Then:** Quiet bars, if the real fade in a fight is allowed.
4. **Then:** the flat strip gets its own brainstorm, mockup and spec, with
   the position pictures (a diamond of four dots, another shape for the
   d-pad). Whether it is in 1.0.0 or after is the owner's call once the
   probe answers are in.
5. **1.0.0:** Controller layout out of "experimental", the perf shortlist
   from the 2026-11 audit, first CurseForge upload.

## Decisions the owner still has

- The map's default size in the layout: 80% (as in the 0.11.0 spec) or
  60% (what the approved mockup actually drew). This build keeps 80% and
  adds the choice.
- Whether the flat strip is in 1.0.0.

## Decided 2026-11-23 (after the device session)

- **The rule "no bars or buttons of our own" is gone.** The owner: "completely
  remove the rule if its blocking this work".
- **Direction: a "face" of our own over the game's bars.** Our frames draw the
  spells wherever we like; the game's real bars stay whole, faded to
  invisible, and still take the presses (proven 2026-11-23,
  `docs/11-23-playsession/EVIDENCE.md`). The owner: "the buttons are mapped
  in a different way thats hidden from the user".
- **The split idea is back** as a picture, not a real split: our face can put
  the d-pad half of a bar on one side of the map and the face-button half on
  the other, while the real bar stays whole underneath.
- Real bars of our own (secure buttons bound to the pad, the Bartender way)
  stay a later option, probe first.
