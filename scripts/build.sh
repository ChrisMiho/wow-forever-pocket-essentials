#!/bin/bash
# Builds dist/wow-forever-pocket-essentials.zip with every addon folder at the zip root,
# ready to extract straight into the game's Interface/AddOns folder.
#
# The bundle is the folders in addons/ plus QuestieDB, which is downloaded from
# its official GitHub release (cached in vendor/, not committed).
#
# QuestieDB ships its 18 MB data file twice under two names, because the game
# calls itself "Camelot" internally and it is not confirmed which name the
# client looks for. Both are kept by default. Once in-game testing shows which
# one loads, drop the other:
#     QUESTIEDB_TOC=Forever scripts/build.sh    (or Camelot)
set -euo pipefail

QUESTIEDB_VERSION="1.1.0"
QUESTIEDB_SHA256="283779bc9b9b3e352be63cb665e86ccc1b29bd893186e03062bcff943f20995c"
QUESTIEDB_TOC="${QUESTIEDB_TOC:-both}"

case "$QUESTIEDB_TOC" in
    both|Forever|Camelot) ;;
    *) echo "error: QUESTIEDB_TOC must be both, Forever or Camelot" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."

# --- Fetch QuestieDB (cached) ---------------------------------------------------
qdb_zip="vendor/QuestieDB-$QUESTIEDB_VERSION-Forever.zip"
if [ ! -f "$qdb_zip" ]; then
    mkdir -p vendor
    echo "Downloading QuestieDB $QUESTIEDB_VERSION..."
    curl -fL --progress-bar -o "$qdb_zip.part" \
        "https://github.com/Questie/QuestieDB/releases/download/v$QUESTIEDB_VERSION/QuestieDB-$QUESTIEDB_VERSION-Forever.zip"
    mv "$qdb_zip.part" "$qdb_zip"
fi
if ! echo "$QUESTIEDB_SHA256  $qdb_zip" | shasum -a 256 -c - >/dev/null; then
    echo "error: $qdb_zip does not match the expected checksum; delete it and retry" >&2
    exit 1
fi

# --- Stage everything -----------------------------------------------------------
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -R addons/. "$stage/"
unzip -q "$qdb_zip" -d "$stage"

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
