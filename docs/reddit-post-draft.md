# Reddit post draft (for the owner to edit and post)

Suggested subreddits: r/wowaddons (read its rules on self-promotion first), and a handheld
community where WoW Forever players are (for example r/SBCGaming or a Retroid subreddit).
Add 2 to 4 real screenshots from the device: the settings window, the quest icons on the
map with the arrow, the chat picker, and the Controller layout. Real screenshots go over
better than the CurseForge illustrations.

---

**Title:** I made a one-download QoL addon suite for playing WoW Forever on a handheld (touch + controller, everything off by default)

**Body:**

I play WoW Forever on a Retroid Pocket 6. There's no CurseForge app on a handheld, the screen
is 720p, and half the addons I use on desktop either don't load on Forever or need tiny mouse
clicks. So I built **Pocket Essentials**: the quality-of-life stuff I missed, in one addon,
made for thumbs.

I know the usual advice here is "keep addons focused". I went the other way on purpose: on a
handheld, installing and updating ten addons by hand through a file manager is the hard part,
so one download with a switch per helper is the point. Everything starts **off**, and anything
you leave off does nothing at all (no timers, no events). No libraries.

What's in it:

- **Quest icons** on the map and minimap for your objectives (kill, loot, use, explore, turn
  in), from QuestieDB's data. Blizzard's blue haze hidden. Limits for busy quests.
- **Quest arrow** to the nearest objective of your focused quest, with distance. It moves on as
  you finish parts and heads to the turn-in when you're done.
- **Bigger bag** and **bag sorting**: a big Sort tab, or click a stick to sort.
- **Auto sell junk** and **auto repair**.
- **Chat picker**: tap the round PE button, pick Say / Party / Guild / Trade or a recent
  whisperer from big buttons. A badge when someone's waiting on you.
- **Controller layout** (experimental): the map bottom middle with a spell panel each side,
  d-pad spells left and face-button spells right, the way you hold the pad. Hold LT or RT and
  that side swaps to the trigger's spells. Frees up the middle of the screen.
- Small fixes: a background behind unreadable pop-up menus, loot sparkles on low graphics, and
  one list for every Lua error instead of pop-ups mid-fight.
- A **setup guide** on first login, and a settings window that works with touch or the d-pad.
  No slash commands needed.

It's still in test builds (0.15.0). The quest, bag, vendor and chat parts have been played on
the device for a while; the controller layout is the newest bit and still changing.

Download (GitHub releases, includes QuestieDB):
https://github.com/ChrisMiho/wow-forever-pocket-essentials/releases

Feedback and bug reports are very welcome, especially from other devices and resolutions.
Credit to the Questie team for QuestieDB, Shagu (pfQuest) for three icons, and Ashtar Senior
(ForeverLootSparkles) for the loot sparkle idea.

---

Notes before posting:
- Check the release you link is the one you tested on the device.
- If the subreddit asks for it, add that it's open source (GPL-3.0).
