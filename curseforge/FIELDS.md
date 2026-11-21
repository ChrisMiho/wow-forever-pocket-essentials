# CurseForge project form: values to enter

Upload only after device testing (PRD roadmap phase 3). Nothing here has been uploaded yet.
Everything in this folder follows CurseForge's moderation guidance: an original
avatar (not a blank colour or a game logo), a specific one-line summary about
the addon itself, a description that explains the features without "like
addon X" comparisons, only original art, and credit with links for the
QuestieDB data and the pfQuest icons.

## What's in this folder

| File | Use it for |
|---|---|
| `summary.txt` | The Summary field (one line) |
| `description.md` | The Description field (Markdown) |
| `avatar.png` | The project avatar, 400x400 PNG |
| `banner.png` | The image at the top of the description, 1280x640 |
| `images/overview.png` | The nine features, each with its switch (1280x720) |
| `images/feature-*.png` | One illustrated image each for quests, bags, chat, the four small helpers (`feature-vendor.png`) and setup with the settings (1280x720) |
| `source/` | The web pages the images are drawn from |

Every image is a small web page in `source/`, saved as a picture by Chrome with `curseforge/source/render.sh` (or `python3 scripts/make_art.py`, which runs it). Each one is drawn in the addon's real colours and wording (taken from the approved mockups in `docs/ui-review/`), uses no game art, and says "Illustration, not a screenshot" in the corner, so nobody mistakes it for a real screenshot. Real screenshots go in the gallery (section 4).

Rules checked on 2026-11-20 against CurseForge's "Moderation Policies" and "Project Submission Guide and Tips": the avatar is 400x400, PNG, original, not a single colour and not a game logo; the summary is one sentence about what the addon does; the description says what each feature adds; credits and links sit at the bottom; the name has no game name or version in it.

## 1. Create the project

1. Go to CurseForge, sign in, then **Create Project** and choose **World of Warcraft**, class **Addons**.
2. Name: `Pocket Essentials` (no game name or version in the name; CurseForge asks for that).
3. Summary: paste the single line from `summary.txt`.
4. Avatar: upload `avatar.png`.
5. Main category: `Quests & Leveling`. Additional categories (up to 4): `Map & Minimap`, `Bags & Inventory`, `Chat & Communication`, `Miscellaneous`. Confirm the exact names in the form; pick the closest match if one has changed.
6. License: `GNU General Public License version 3 (GPLv3)`.
7. Source URL: https://github.com/ChrisMiho/wow-forever-pocket-essentials
8. Issues URL: https://github.com/ChrisMiho/wow-forever-pocket-essentials/issues
9. Description: leave it for step 2 (it needs the image links first). If the form insists on text, paste the first paragraph of `description.md` for now.

## 2. Description images

10. Open the project's **Images** tab and upload, one by one: `banner.png`, then every file in `images/`.
11. Click each uploaded image to copy its link, then in `description.md` replace the matching word:

| Word in `description.md` | Image |
|---|---|
| `BANNER_URL` | `banner.png` |
| `OVERVIEW_URL` | `images/overview.png` |
| `QUESTS_URL` | `images/feature-quests.png` |
| `BAGS_URL` | `images/feature-bags.png` |
| `VENDOR_URL` | `images/feature-vendor.png` |
| `CHAT_URL` | `images/feature-chat.png` |
| `SETUP_URL` | `images/feature-setup.png` |

12. Open **Description**, switch the editor to **Markdown**, paste all of `description.md`, and check the preview: every image shows, no `_URL` word is left.

(Ask Claude to fill the links in for you: paste the seven links in chat and it will write a ready-to-paste copy.)

## 3. Upload the file

13. File: `dist/PocketEssentials-<version>.zip` (the version at the top of `CHANGELOG.md`), the addon alone. Rebuild with `scripts/build.sh` if anything changed since (or ask Claude).
14. Game flavor: `Forever`. Game version: `1.60.1`.
15. Release type: `Release`.
16. Changelog: paste the top section of `CHANGELOG.md`.
17. Relations: add **QuestieDB** (project ID `1696795`, slug `questiedb`) as **Required Dependency**. The TOC says OptionalDeps because the addon runs without it, but the quest features, the main reason to install, need it, so CurseForge should install it automatically.
18. Submit. CurseForge reviews every new project by hand, which can take a few days. If a moderator asks for changes, they say which field; ask Claude to rework it.

## 4. Screenshots for the gallery (from the device)

Real screenshots make the page much stronger. Take these in game and upload them in the **Images** tab (they appear in the gallery, below the description). Give each a short title.

- **Quest icons on the world map:** several coloured objective icons, no blue haze. Title: "Quest objectives on the map".
- **Quest arrow:** the arrow on screen with its distance text. Title: "Follow the arrow".
- **Bigger bag:** the bag with the Sort tab on its side. Title: "One bag, one press to sort".
- **Chat picker:** the big channel and whisper buttons. Title: "Chat with big buttons".
- **Settings window:** the tabs and one helper's page. Title: "Every helper has its own switch".
- **Setup guide:** the Welcome screen. Title: "Set up in about a minute".
- **Move on screen:** the panel with the arrow being moved. Title: "Make the screen your own".

## After approval

19. CurseForge shows your project ID on the project page. Ask Claude to put `## X-Curse-Project-ID: <id>` on a new line under `## Version: …` in `addons/PocketEssentials/PocketEssentials.toc`. It takes effect with the next version you upload.
