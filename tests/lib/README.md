# Third-party code used by the offline tests

Nothing in `tests/` ships in the addon zip (`scripts/build.sh` copies only
`addons/PocketEssentials` and QuestieDB). Both files below are unmodified copies.

| File | Source | Version | Licence |
|---|---|---|---|
| `LibDeflate.lua` | <https://github.com/SafeteeWoW/LibDeflate/blob/6831edcaa915154e7769d622e0de72ee5d25a882/LibDeflate.lua> | 1.0.2-release (commit `6831edc`) | zlib (notice kept at the top of the file) |
| `metadata.lua` | <https://github.com/Questie/QuestieDB/blob/4dbb82440a27856f8dccf57094a5d792cdc7cc9b/emulator/metadata.lua> | commit `4dbb824` (the build commit of QuestieDB 1.1.1) | GPL-3.0 (see below) |

SHA-256: `LibDeflate.lua` `76f2114e527c2be1ac5cf768a68084946a3e19f63592834640020b7c9b5a450f`,
`metadata.lua` `6b18286acc05352dfb5f512cd7efcceb14905aa2b46dd6e0a2501908fcabfc0d`.

## Why these, and what was written here instead

QuestieDB's `src/read/baked.lua` points at its own offline emulator
(`emulator/metadata.lua` and `emulator/client.lua`). We checked it first:

- **`metadata.lua` is used as is.** It parses the QuestieDB TOC into a
  `C_AddOns.GetAddOnMetadata` stand-in and loads the addon's files in TOC order
  with `("QuestieDB", ns)`, the way the game does. Every commit to it is by
  Logonz, who is listed in QuestieDB's `LICENSE.md` as having put their
  contributions under GPL-3.0, so it is compatible with this project's GPL-3.0.
- **`client.lua` is not used.** It loads its helpers with repo-relative
  `dofile` paths, its `C_Timer.After` runs callbacks at once (QuestData needs
  them queued), and its CBOR decoder (`generator/vendor/BlizzardCBOR.lua`) was
  copied from a Questie code-review checkout whose authorship and licence we
  could not trace. `tests/questiedb/stubs.lua` installs the client globals
  instead, and `tests/questiedb/decode.lua` (our own code) provides base64 and
  CBOR decoding; zlib goes through `LibDeflate:DecompressZlib`.
- **LibDeflate** comes from its own upstream release rather than QuestieDB's
  copy, so its origin and licence are unambiguous.
