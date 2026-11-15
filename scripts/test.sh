#!/bin/bash
# Offline QuestieDB harness: puts every quest in the pinned QuestieDB release
# through our QuestData.lua under WoW API stand-ins (tests/questiedb/).
#
# Exits 0 and prints one summary line on pass; exits 1 with the first failing
# quest and its error otherwise. Needs luajit (brew install luajit); without it
# the test is skipped (exit 0) so nobody is locked out. The same goes for a failed
# QuestieDB download (for example, when offline).
#
#     scripts/test.sh                       # test addons/PocketEssentials/QuestData.lua
#     scripts/test.sh path/to/QuestData.lua # test another copy of it
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit not installed (brew install luajit); skipping" >&2
    exit 0
fi

# Capture the status explicitly: under set -e a failed $(...) assignment would
# abort before the notice below prints.
fetch_status=0
qdb_zip="$(scripts/fetch-questiedb.sh)" || fetch_status=$?
if [ "$fetch_status" -ne 0 ]; then
    echo "could not download QuestieDB; offline tests skipped" >&2
    exit 0
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/pe-questiedb.XXXXXX")"
trap 'rm -rf "$work"' EXIT
unzip -q "$qdb_zip" -d "$work"

luajit tests/questiedb/harness.lua "$work/QuestieDB" "$PWD" "$@"
