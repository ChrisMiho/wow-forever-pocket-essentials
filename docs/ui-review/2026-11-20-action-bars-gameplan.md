# Action bars and screen space: game plan (draft, 2026-11-20)

Not a spec. A starting point for the owner to refine. Nothing is built.

## The owner's goal

The game's gamepad action bars (the d-pad and face-button clusters at the
bottom middle) are bulky on a 720p handheld. The owner wants more of the
screen for the game and less for spell buttons, and has their own ideas for
a more phone-like (mobile) layout.

## What the code and the game allow

- **The bag was the easy case.** Our "Bag window" is Blizzard's own bag,
  made bigger and tidied. Bag frames are not protected, so we can move and
  resize them at any time.
- **Action bars are the hard case.** Spell buttons are protected. In a
  fight the game freezes them: an addon cannot move, resize, show or hide
  them until the fight ends. What still works in a fight: changing how see-
  through they are, and rules set up *before* the fight ("show this only in
  combat", "show this while a shoulder button is held").
- **The game already has options for these bars.** In Edit Mode, the
  gamepad main action bar has five checkboxes in this build's source
  (`Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua:1517`): Compact,
  Show empty bars, Button prompts, Highlight, Expand. Not tried on the
  device yet.
- **Known risk:** when an addon changes Edit Mode or the game's own bar
  positions, the game can later blame the addon in a fight ("Interface
  action blocked"). That is why the Layout helper was dropped in 0.3.0.
- **PRD non-goal:** "Replacing or fighting Blizzard's gamepad support (no
  ConsolePort unless a player asks)". Building our own bars needs the owner
  to lift this.

## Three ways to do it

| | What it is | Cost | Risk |
|---|---|---|---|
| A. Game's own options | Try Edit Mode's gamepad bar checkboxes. No code | Minutes | None |
| B. Tidy the game's bars | Fade them out of fights, hide button pictures and empty slots, smaller, a drawer for out-of-fight spells | Medium | Medium: needs a probe run first |
| C. Our own bars | Our own spell buttons laid out for thumbs, any size or shape | Large | High: protected buttons, bindings only out of fights |

Recommendation: A first, then B in small steps. C only if B is not enough.

## Steps

1. Owner tries the Edit Mode checkboxes and sends a screenshot (no code).
2. Pocket Probe round: what we may change on the gamepad bars, in and out
   of a fight (fade, size, hide pictures, a drawer of our own buttons).
3. Mockups at 720p, Today vs Proposed, on the mockup page.
4. Spec, plan, build, device test. One piece at a time.

## Owner's answers (2026-11-20)

1. Size is the problem. Empty buttons will not exist at high level, so show
   less at once. Even less in cities; back into view when buttons are
   pressed; maybe a fade. Chat feels small and the bars clash with it.
   Open to a new layout: minimap bottom centre with the buttons around it,
   chat where the minimap was, buffs and debuffs slid over. The pet
   sub-menus are loved but should look sleeker and smaller. "This is for
   me, what will make playing on the go feel premium."
2. Controller. Fine to call it a controller-optimised theme; touch players
   can come later. RP6 only for now. Asks whether the RP6 back buttons can
   be bound (extra binds for warlock). The game knows four extra
   buttons (`PADPADDLE1` to `PADPADDLE4`); whether the RP6 sends them
   through Droid Deck is a device check.
3. Bars only during fights. Professions sit on the second page; its
   sub-menus are empty. Hiding or fading is a huge win.
4. Tidy first, whatever is lighter.
5. Spell drawer: "10000% yes". Mount, hearth, food, sleeping bag, campfire
   (Forever's new mechanic), sharpening stones, poisons, pet summons.
   Could be long, must stay light.

Proposed order (three pieces, each its own spec and device test):
1. Quiet bars (fade, hide in cities, back on press or in a fight).
2. Kit drawer (the spell drawer).
3. Controller layout (minimap, chat, buffs moved). Mockups first.

Owner agreed the order (2026-11-21) and asked for a new settings tab with
its own switch for each piece, so Quiet bars and the layout can be turned
on separately.

Found in the source: the game's Edit Mode "Compact" checkbox on the
gamepad bar shows only the page you are on and hides the others
(`ActionBar.lua:171`, `PageUnit.lua:292`). The game never sets the bar
frame's see-through level itself (`GamepadMainActionBarFrame`), so a fade
from us would not be fought.

## Five questions (with recommended answers)

1. Your ideas, and what is in your way? Recommended: bars first, then the
   two "Ranged / Main Hand" bars and the controller hint box top left.
2. Do you cast with the controller or by tapping? Recommended: controller;
   the screen only needs cooldowns.
3. When must the bars be on screen? Recommended: full in a fight, faded
   to about 20% out of a fight, back to full while a shoulder button is
   held.
4. Tidy the game's bars or build our own? Recommended: tidy first.
5. A spell drawer, like the bag, for mount, hearthstone, food and
   professions, opened from the round button, closed in a fight?
   Recommended: yes, after the fading.

## Kit drawer, first mockup (2026-11-21)

Quiet bars mockup approved by the owner ("functionally this is perfect for
gameplay"); spec `docs/superpowers/specs/2026-11-21-quiet-bars.md`, waiting
on the owner's go for the plan. The owner then asked for the next mockup
while away. Mockup view "Kit drawer"; its card is on the Controller tab.

My calls in the mockup, for the owner to check:
- Filled by itself from bags and spellbook, four tabs: Travel, Camp, Weapon,
  Pets. Nothing to drag or set up.
- Opens with a binding of our own in the game's Key Bindings (an addon
  `Bindings.xml`), so a back button works if the game sees it. Closes when
  combat starts, cannot open in combat.
- Weapon tab: "Put it on: Main hand / Off hand", then one press applies the
  stone or poison. Source: `Blizzard_FrameXML/SecureTemplates.lua:771`
  (`target-slot` after a spell that targets an item).
- Options: "Open with" (Key Bindings > Pocket Essentials), "After you use
  something: Close / Stay open", "Size of the drawer" 70–150%.
- Cooldowns shown on the icon; a tile on cooldown does nothing.

Open questions: what to do about items the auto-fill gets wrong (hide one?
pin one?), whether the round button should also open it, and the real names
of Forever's camping items.

### Owner's answers on the Kit (2026-11-21)

1. "Can we have the player set it up actually? This avoids incorrect auto
   setup altogether." The kit is player-filled: + opens a picker of bag items
   and spellbook spells; "any item from my bag, not even just the usual
   consumes".
2. No new on-screen piece: "if the bottom of the chat box could double as
   the bin, while still supporting the chat feature". The kit sits under the
   chat buttons in the round button's window; with Chat picker off, PE opens
   the kit alone. No key binding for now ("maybe two clicks is easy enough").
3. Camping names (looked up): Cozy Sleeping Bag (item), camps start from a
   Cooking fire (Basic Campfire). With a player-filled kit the names no
   longer matter to the code.
4. "This new drawer feature is very experimental": built to be tried.

New idea from the owner: "a singular box on the screen if the quest has an
item that needs to be used. I've been clicking the icon in the quest log on
the right, but it's very small." Mocked as "Quest item button": one big
button under the quest arrow for the focused quest's item, a Show / Hide
choice under Quest arrow. `GetQuestLogSpecialItemInfo` and
`GetQuestLogSpecialItemCooldown` exist in the Forever source.

Builder notes: kit slots and the quest item button are secure action
buttons. They can only be created, changed, shown or hidden out of combat,
so the kit is hidden in combat (chat still works). The kit must not be
anchored to the chat window (a protected frame anchored to ours would make
our window protected in combat); place it by position instead.

### Kit and chat in combat (owner, 2026-11-21)

"The kit should be accessible in combat, just like the chat, with the
ability to turn it on and off, as the chat should, to prevent accidental
clicks but to enable people that want those features while in combat."
Mocked: "Kit in combat: Allow / Block" (Controller tab) and "Chat picker in
combat: Allow / Block" (Chat tab), both Allow to start (my call; chat works
in combat today). Both on Block: PE does nothing in combat. In combat the kit
slots work; adding and removing wait until after combat.

The catch (to test with Pocket Probe before building): opening a window of
addon buttons in combat needs a "secure" tap. So the round button would
become a secure button, and then the game freezes it in combat too: it could
not hop onto the map's book icon or be moved during a fight. Chat in combat
is unaffected (it works today).

### Name (owner, 2026-11-21)

"Kit" is now **Quick slots** (owner asked for "quick bar or something";
"Quick bar" was too close to "Quiet bars" on the same tab; owner: "quick
slots works"). Window title "Chat and quick slots", "Edit slots", setting
"Quick slots in combat: Allow / Block".

### Owner's answers on the two open questions (2026-11-21)

1. Quest item button ships with Quiet bars (0.11.0): yes. Added to the
   Quiet bars spec.
2. Round button becomes a secure button, fixed in place during combat, so
   Quick slots work in combat: yes. Pocket Probe test first, then the Quick
   slots spec.

### Fewer slots (owner, 2026-11-21)

"This is too many quick slots, i think we need to simplify it to just 3-4?
with the ability to configure more in the settings." Mocked: four slots to
start, one row; option "Number of slots" (2 to 12) first on the Quick slots
card; up to six per row, so fewer slots get bigger squares (capped). Empty
slots are faint squares, + on the first one. Slots past the number are kept,
just not shown (my call). The Controller tab now scrolls a little with both
cards (owner, earlier: a scroll bar is fine once more is added).
