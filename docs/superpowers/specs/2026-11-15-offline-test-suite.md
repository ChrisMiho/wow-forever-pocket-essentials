# Offline test suite for the whole addon

Status: approved by the owner 2026-11-15 ("these all sound great, so long as
it's a build either locally or in a GitHub action, and it's not all bundled up
in the addon").

## Why

Five of the seven features (bags, sell junk, repair, chat, layout) have never
run in the game, and the owner is preparing a CurseForge launch. Only the
quest data is tested off the device today. The owner wants more confidence
from our side while the device tests go on.

## Goals

1. Catch, off the device, a call to a game function that does not exist on
   this client.
2. Catch any Lua error when every feature is loaded, switched on, sent its
   game events, shown in the settings window, and switched off.
3. Check each feature's rules (what it sells, when it sorts, who is listed)
   against a stand-in for the game.
4. Run locally with one command and in a GitHub Action on every push.

## Non-goals

- Proving how anything looks, or that the game allows an action (selling,
  repairing, opening chat). Only the device test does that.
- Changing the addon. Tests only. A real bug a test finds is reported to the
  owner and fixed as its own change, because 0.0.6 is on the device now.

## Anti-goals

- Anything from `tests/` or `scripts/` ending up in a release zip.
- A stand-in so forgiving that every test passes whatever the addon does.
- A slow gate: the Stop hook runs `scripts/check.sh` and `scripts/test.sh` on
  every turn, so together they stay under about ten seconds.

## Approaches

- **A. Our own stand-in for the game, strict where Blizzard's source lets it
  be (chosen).** Frame methods and `C_` functions exist in the stand-in only
  if Blizzard's generated documentation for build 1.60.1.70938 lists them (or
  an allow-list entry says where else they were verified), so a made-up
  method fails in the test as it would in the game.
- B. A third-party WoW API emulator. Rejected: none targets this client, and
  the project takes no libraries it cannot verify.
- C. Only hand-written stubs per test. Rejected: each stub repeats what its
  author believed, which is the weakness the current note in
  `docs/ARCHITECTURE.md` already admits.

## Design

Three layers, all under `tests/`, started by `scripts/test.sh`.

1. **API audit** (`tests/api/`). A script lists every global function,
   `C_Namespace.Function` and widget method the addon's Lua files use, and
   checks each against Blizzard's interface source (`wow-ui-source`, branch
   `forever`). The result is a committed snapshot, `tests/api/verified.txt`
   (name, where it was found), plus `tests/api/unverified.txt` for names
   found only by usage or not at all, each with the reason and matching a row
   in `docs/ARCHITECTURE.md` "Unverified API". Two entry points:
   - `scripts/audit-api.sh`: the full audit against a clone of the source
     (slow, needs the network once); rewrites the snapshot. Run on demand and
     in the GitHub Action.
   - A fast check inside `scripts/test.sh`: every name the addon uses today
     is in one of the two lists. A new, unlisted call fails the test.
2. **Whole-addon smoke test** (`tests/smoke/`). Loads all files in TOC order
   into the stand-in (`tests/lib/fakeclient.lua`), then: every feature on;
   every event each feature registered is fired with plausible arguments;
   every `OnUpdate` is ticked for a few simulated seconds; every settings page
   is opened at each button size and every button on it pressed (except
   reload); every feature off. Fails on any Lua error, any `PE:LogError`, and
   any `OnUpdate` or event still registered by a feature that is off.
   Runs for two cases: QuestieDB present and QuestieDB missing.
3. **Rule tests per feature** (`tests/features/`), one file per feature,
   using the same stand-in with a scripted world (bag contents, vendor, chat
   events, combat state):
   - Sell junk: only greys with a price; not locked items; not ignored bags;
     pauses in combat; stops on a trade window or spell cursor; reports money.
   - Repair: repairs when it can afford it; says so once when it cannot;
     nothing at a vendor that cannot repair.
   - Chat: newest whisperer first; six remembered; badge set and cleared;
     Party and Raid only when grouped; nothing listed during chat lockdown.
   - Bags: sort refused in combat and with the bag closed; setting written
     only at logout.
   - Layout: refuses without the Gamepad UI; second tap within 20 seconds to
     overwrite; asks for a reload after a switch.
   - Quest arrow: nearest spot chosen and re-chosen on moving; "Turn around"
     thresholds (150 and 135 degrees); zone and no-focus messages; arrow pin
     published and cleared.
   - Quest icons: the three "Show icons for" modes; the spots limit and the
     arrow's spot; the 150 and 40 caps.
   - Core: saved settings survive an upgrade and gain new defaults; one
     feature's error does not stop another; features default off.
   Each rule comes from PRD.md, `docs/DECISIONS.md` or the feature's own
   comments, and each test names its source.

**GitHub Action** (`.github/workflows/test.yml`): on every push and pull
request, install LuaJIT, run `scripts/check.sh`, `scripts/test.sh` and
`scripts/audit-api.sh`, and fail if the audit changes the snapshot.

**Not in the zip:** `scripts/build.sh` copies only `addons/PocketEssentials`
and QuestieDB. A check in the smoke test confirms the built file list holds
nothing from `tests/`.

## Findings

A test that fails because the addon is wrong is not "fixed" by weakening the
test. It is marked as a known failure with a one-line reason, listed in the
final report to the owner, and fixed in a separate change the owner agrees.

## Left to the builder

- How the stand-in is generated from Blizzard's documentation files.
- The plausible arguments for each event.
- Which rules need a second scenario to be convincing.
