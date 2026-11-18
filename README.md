![Pocket Essentials](curseforge/banner.png)

# WoW Forever Pocket Essentials

A small, lightweight addon suite that makes WoW Forever comfortable to play on
a handheld, with touch and a controller together: big buttons, no tiny
targets, no typed commands.

> **Status: In progress: version 0.4.0 is a test build. Quest icons, the quest arrow, the bag sorter, sell junk, repair and the chat buttons have run on a device (0.0.9 and 0.1.0). Everything added since has not: Move things, the setup guide, Menu background, the two new bag choices and the chat text size stepper.**
> Treat every feature as unproven until it has been tested in the game.

## Who it's for

Anyone playing WoW Forever on a handheld, on any device that runs the client.
The developer's test device is a Retroid Pocket 6 running the game through
Droid Deck.

## Features

Every feature has its own on/off switch and starts switched off. The first
time you log in, a short **setup guide** explains each one in a few lines and
lets you switch on the ones you want.

| Feature | What it does |
|---------|--------------|
| Quest icons | Objective icons on the map and minimap for your tracked quests (or only the focused one, or all), no blue haze; a limit on icons per objective, and an icon key page in the settings |
| Quest arrow | An arrow to your focused quest's nearest objective in your zone, with distance. Focus a quest from the quest log. For a quest in another zone it names the zone |
| Bag sorter | A big Sort button on Blizzard's combined bag; a stick click (left, right or none, your choice) sorts while it is open; three sizes. Two choices that start off: "D-pad to Sort" (press Left from the bag's first column to reach the Sort button, A sorts) and "Bag icons: One row at the top" (the pictures of your equipped bags side by side above your items, not in among them) |
| Sell junk automatically | Sells every grey item at vendors. Only the last 12 sold can be bought back |
| Repair automatically | Repairs from your own money |
| Big chat buttons | The round button opens a picker: one big button per channel and per recent whisperer. A badge shows unanswered whispers. "Chat text size" (Smaller / Bigger) is in the settings and works with the feature on or off |
| Menu background | A plain dark panel behind the game's pop-up menus, such as the menu on a quest in the quest log, so the text is easy to read |
| Setup guide | Not a switch: seven short screens that explain the features above, each with its switch. Opens by itself once; open it again from the settings ("Setup guide") |

## Install

Pocket Essentials is one addon, `PocketEssentials`. The two quest features also
need the `QuestieDB` addon; everything else works without it.

### From CurseForge (coming later)

Install Pocket Essentials from CurseForge. QuestieDB installs with it as a
dependency.

### From GitHub

There are no GitHub releases yet, so you build the zip yourself.

1. On a Mac or Linux computer, run `scripts/build.sh`. It writes
   `dist/wow-forever-pocket-essentials.zip`.
2. Copy that zip to your device.
3. In the game's `Interface/AddOns` folder, **delete any old `QuestDots`
   folder** from an earlier version of this bundle.
4. Extract the zip into `Interface/AddOns`. You should end up with two folders
   side by side: `PocketEssentials` and `QuestieDB`. Do not rename either.
5. Log in. A round "PE" button appears at the left edge of the screen, and a
   moment after the loading screen the setup guide opens by itself. Read
   through it and switch on what you want, then press **Finish** (or **Skip**
   to leave everything off). Closing it any other way only hides it until the
   next login. Later, tap the round button to open the settings.

### Without QuestieDB, or with a version this addon doesn't understand

The quest icons and quest arrow stay off and the settings window says why
(for example "Needs the QuestieDB addon, which is not installed or did not
load."). Everything else keeps working.

## Using it

- **Tap the round "PE" button** to open the settings. If Big chat buttons is
  on, it opens the chat picker instead.
- **Hold the round button for half a second** to always open the settings.
- **Type `/pe`**, or use the addon-list button on the minimap, as other ways
  to open them.
- **Setup guide:** the "Setup guide" button in the bottom row of the settings
  (or `/pe setup`) opens the guide again at any time. Its switches are the
  same switches as in the settings. Use the touch screen, or the d-pad to
  move the blue highlight, A to press and B to close.
- **Reload UI button:** at the bottom of the settings, so a reload never
  needs a typed command.
- **Errors page:** if something goes wrong, the settings window has an Errors
  page that shows what failed, in large text. It also has a **Debug log**
  switch: turn it on, play until the problem happens, tap Save log now, and
  send the file `WTF/Account/<account>/SavedVariables/PocketEssentials.lua`.

## For developers

```bash
scripts/check.sh   # LuaJIT syntax check plus a comment-wording check
scripts/test.sh    # offline tests: API check, QuestieDB, feature rules, smoke test
scripts/audit-api.sh  # full check of game names against Blizzard's source (~45 s)
scripts/build.sh   # dist/wow-forever-pocket-essentials.zip (GitHub bundle)
                   # dist/PocketEssentials-<version>.zip (CurseForge, addon only)
                   # dist/PocketProbe.zip (probe/PocketProbe, a test-only addon that records what the game allows; never in the two zips above)
```

The first test run downloads QuestieDB into `vendor/` (cached afterwards). The
tests also run on GitHub for every push. Nothing in `tests/` or `scripts/` goes into
the addon zips; see [docs/TESTING.md](docs/TESTING.md). The
project enables the `wow-addon-skills` Claude Code plugin
(<https://github.com/ChrisMiho/wow-addon-skills>) via `.claude/settings.json`,
so Claude Code may offer to install it.

A Stop hook in `.claude/settings.json` runs the checks and tests and blocks a
Claude Code turn from ending if either fails. New features follow the
spec-driven workflow (rule 7 in [PRD.md](PRD.md)): a spec first, then a plan,
then a reviewed build, then a device test. See [CLAUDE.md](CLAUDE.md) for how
to work in this repo.

## Project docs

| File | What's in it |
|------|--------------|
| [PRD.md](PRD.md) | Vision, goals, status, roadmap, parked ideas |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the addon is built, and what is known about the client |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Why things are the way they are |
| [docs/TESTING.md](docs/TESTING.md) | Offline tests and the device test plan |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each version |
| [CLAUDE.md](CLAUDE.md) | Working rules for AI-assisted development |

## Feedback

Found a bug or have an idea? Open an issue:
[github.com/ChrisMiho/wow-forever-pocket-essentials/issues](https://github.com/ChrisMiho/wow-forever-pocket-essentials/issues).

## Credits and thanks

- Thank you to the [Questie team](https://github.com/Questie/QuestieDB) for
  making the quest database available for other addons to build on.
  QuestieDB (GPL-3.0) is also on
  [CurseForge](https://www.curseforge.com/wow/addons/questiedb).
- Three icons come from [pfQuest](https://github.com/shagu/pfQuest) by Shagu
  (MIT).

## Licence

GPL-3.0. See [LICENSE](LICENSE).
