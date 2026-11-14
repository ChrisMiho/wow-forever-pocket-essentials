#!/bin/bash
# Offline QuestieDB harness: puts every quest in the pinned QuestieDB release
# through our QuestData.lua under WoW API stand-ins (tests/questiedb/).
#
# Exits 0 and prints one summary line on pass; exits 1 with the first failing
# quest and its error otherwise. Needs luajit (brew install luajit); without it
# the test is skipped (exit 0) so nobody is locked out.
#
#     scripts/test.sh                       # test addons/PocketEssentials/QuestData.lua
#     scripts/test.sh path/to/QuestData.lua # test another copy of it
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit not installed (brew install luajit); skipping" >&2
    exit 0
fi

qdb_zip="$(scripts/fetch-questiedb.sh)"

work="$(mktemp -d "${TMPDIR:-/tmp}/pe-questiedb.XXXXXX")"
trap 'rm -rf "$work"' EXIT
unzip -q "$qdb_zip" -d "$work"

luajit tests/questiedb/harness.lua "$work/QuestieDB" "$PWD" "$@"
