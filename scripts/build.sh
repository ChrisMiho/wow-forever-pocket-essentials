#!/bin/bash
# Builds dist/wow-forever-pocket-essentials.zip with every addon folder at the zip root,
# ready to extract straight into the game's Interface/AddOns folder. It also builds
# dist/PocketEssentials-<version>.zip (the addon alone) for CurseForge.
#
# The zip holds exactly two folders:
#   PocketEssentials  (from addons/, our own addon)
#   QuestieDB         (downloaded unmodified from its official GitHub release,
#                      cached in vendor/, not committed)
#
# QuestieDB ships its 18 MB data file twice under two names, because the game
# calls itself "Camelot" internally and it is not confirmed which name the
# client looks for. Both are kept by default. Once in-game testing shows which
# one loads, drop the other:
#     QUESTIEDB_TOC=Forever scripts/build.sh    (or Camelot)
set -euo pipefail

QUESTIEDB_TOC="${QUESTIEDB_TOC:-both}"

case "$QUESTIEDB_TOC" in
    both|Forever|Camelot) ;;
    *) echo "error: QUESTIEDB_TOC must be both, Forever or Camelot" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."

# --- Check the addon's Lua before packaging anything ---------------------------
scripts/check.sh

# --- Fetch QuestieDB (cached, checksum-verified; pin lives in fetch-questiedb.sh) ---
qdb_zip="$(scripts/fetch-questiedb.sh)"

# --- Stage everything -----------------------------------------------------------
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

if [ ! -f addons/PocketEssentials/PocketEssentials.toc ]; then
    echo "error: addons/PocketEssentials/PocketEssentials.toc is missing" >&2
    exit 1
fi
# Every file the TOC lists must exist, or the game reports an error at login.
while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    if [ ! -f "addons/PocketEssentials/$line" ]; then
        echo "error: PocketEssentials.toc lists $line, which does not exist" >&2
        exit 1
    fi
done < addons/PocketEssentials/PocketEssentials.toc

# The version names the CurseForge zip. Strip CRs and surrounding spaces.
version="$(sed -n 's/^## Version: //p' addons/PocketEssentials/PocketEssentials.toc \
    | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [ -z "$version" ]; then
    echo "error: PocketEssentials.toc has no '## Version:' line" >&2
    exit 1
fi

# CHANGELOG.md must have a heading for this version, or the two have drifted apart.
if ! grep -q -F "## [$version]" CHANGELOG.md; then
    echo "error: CHANGELOG.md has no '## [$version]' heading (the TOC version); add one" >&2
    exit 1
fi

cp -R addons/PocketEssentials "$stage/"
unzip -q "$qdb_zip" -d "$stage"

# The old standalone QuestDots addon was folded into PocketEssentials. It must
# never ship alongside it, or the two copies would both draw icons.
if [ -e "$stage/QuestDots" ]; then
    echo "error: a QuestDots folder ended up in the bundle" >&2
    exit 1
fi

case "$QUESTIEDB_TOC" in
    Forever) rm "$stage/QuestieDB/QuestieDB_Camelot.toc" ;;
    Camelot) rm "$stage/QuestieDB/QuestieDB_Forever.toc" ;;
esac

# Every addon folder needs a .toc named after the folder (optionally with a
# _Flavor suffix), or the game ignores it.
for dir in "$stage"/*/; do
    name="$(basename "$dir")"
    if [ -z "$(find "$dir" -maxdepth 1 \( -name "$name.toc" -o -name "${name}_*.toc" \) -print -quit)" ]; then
        echo "error: $name has no $name.toc" >&2
        exit 1
    fi
done

# --- Zip ------------------------------------------------------------------------
out="$PWD/dist/wow-forever-pocket-essentials.zip"
mkdir -p dist
rm -f "$out"
(cd "$stage" && zip -qr -X "$out" . -x '*.DS_Store')

echo "Built dist/wow-forever-pocket-essentials.zip ($(du -h "$out" | cut -f1)) with:"
for dir in "$stage"/*/; do
    echo "  $(basename "$dir")  $(du -sh "$dir" | cut -f1)"
done

# CurseForge takes PocketEssentials alone: QuestieDB is linked there as its own
# project, so it must not be bundled into this zip.
cf_out="$PWD/dist/PocketEssentials-$version.zip"
rm -f "$cf_out"
(cd "$stage" && zip -qr -X "$cf_out" PocketEssentials -x '*.DS_Store' '__MACOSX/*')

echo "Built dist/PocketEssentials-$version.zip ($(du -h "$cf_out" | cut -f1)) for CurseForge"
