# CurseForge project form: values to enter

Upload only after device testing (PRD roadmap phase 3, after device testing and polish). Nothing here has been uploaded yet.

## Create the project

1. Name: `Pocket Essentials`
2. Summary: paste the single line from `curseforge/summary.txt`.
3. Avatar: upload `curseforge/avatar.png` (400x400 PNG).
4. Main category: `Map & Minimap`. Additional categories (up to 4): `Quests & Leveling`, `Bags & Inventory`, `Chat & Communication`, plus the closest fourth match you can find. Confirm the exact names in the form.
5. License: `GPL-3.0`.
6. Source URL: https://github.com/ChrisMiho/wow-forever-pocket-essentials
7. Issues URL: https://github.com/ChrisMiho/wow-forever-pocket-essentials/issues
8. Description: switch the editor to Markdown mode and paste all of `curseforge/description.md`.

## Banner in the description

9. Open the project's Images tab and upload `curseforge/banner.png`.
10. Copy that image's URL and replace `BANNER_URL` on the first line of the description with it. (Linking the raw file on GitHub also works, but the Images tab is recommended.) Don't publish the description until `BANNER_URL` is replaced.

## Upload the file

11. File: `dist/PocketEssentials-<version>.zip` (the version in `CHANGELOG.md`'s top section) (addon only). It may already be in `dist/`; if anything has changed since, rebuild it with `scripts/build.sh` from a Mac or Linux terminal (or ask Claude).
12. Game flavor: `Forever`. Game version: `1.60.1`.
13. Release type: `Release` (the 0.0.x version number shows it is early).
14. Changelog: paste the top section of `CHANGELOG.md` (replace 'Unreleased' with the release date if it says that).
15. Relations: add QuestieDB (project ID `1696795`, slug `questiedb`) as **Required**. (The TOC says OptionalDeps because the addon runs without QuestieDB, but the quest features, the main reason to install, need it, so CurseForge should install it automatically.)

## Optional, for later

16. Optional, for later: CurseForge shows your project ID on the project page. Ask Claude (or add it yourself) to put `## X-Curse-Project-ID: <id>` on a new line directly under `## Version: …` in `addons/PocketEssentials/PocketEssentials.toc`. It takes effect with the next version you upload; you don't need to re-upload the current version.

## Screenshots to take on the device

Upload these in the Images tab.

- Settings window: the feature list with switches visible.
- World map with quest icons: several objective icons, no blue haze.
- Quest arrow: the arrow on screen with its distance text.
- Combined bag with the Sort button: the big Sort button clearly visible.
- Chat picker: the big channel and whisper buttons.
