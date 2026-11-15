#!/bin/bash
# Downloads QuestieDB from its official GitHub release into vendor/ (not committed),
# checks its SHA-256, and prints the zip's path on stdout. Everything else goes to
# stderr, so callers can do:  zip=$(scripts/fetch-questiedb.sh)
#
# Exit codes: 0 ok; 2 the download failed (offline); 3 checksum mismatch (the bad
# file is removed).
#
# This file holds the only copy of the pinned version and checksum.
#
# We use the "-Forever" zip. QuestieDB ships its data file under two names (the
# _Forever and _Camelot TOCs, byte-identical), because the game calls itself
# "Camelot" internally; build.sh decides which TOC(s) to keep.
set -euo pipefail

QUESTIEDB_VERSION="1.1.1"
QUESTIEDB_SHA256="2527118d861e497fa40bdb6d061883bf09649d5f96e09de6885f578aefbb5e59"

cd "$(dirname "$0")/.."

qdb_zip="vendor/QuestieDB-$QUESTIEDB_VERSION-Forever.zip"
if [ ! -f "$qdb_zip" ]; then
    mkdir -p vendor
    echo "Downloading QuestieDB $QUESTIEDB_VERSION..." >&2
    curl -fL --progress-bar -o "$qdb_zip.part" \
        "https://github.com/Questie/QuestieDB/releases/download/v$QUESTIEDB_VERSION/QuestieDB-$QUESTIEDB_VERSION-Forever.zip" >&2 \
        || { rm -f "$qdb_zip.part"; echo "error: could not download QuestieDB" >&2; exit 2; }
    mv "$qdb_zip.part" "$qdb_zip"
fi
if ! echo "$QUESTIEDB_SHA256  $qdb_zip" | shasum -a 256 -c - >/dev/null; then
    rm -f "$qdb_zip"
    echo "error: $qdb_zip does not match the expected checksum; it was removed, so the next run downloads it again" >&2
    exit 3
fi

echo "$PWD/$qdb_zip"
