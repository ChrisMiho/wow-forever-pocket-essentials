#!/bin/bash
# Offline tests: the fast API check (tests/api/), then the QuestieDB harness,
# which puts every quest in the pinned QuestieDB release through our QuestData.lua under WoW API stand-ins (tests/questiedb/),
# then the whole-addon smoke test in the stand-in game client (tests/smoke/, tests/lib/fakeclient.lua),
# and the rule tests for sell junk, repair, chat and the core (tests/features/; no QuestieDB needed).
#
# Exits 0 and prints one summary line per suite on pass; exits 1 with FAIL: and
# the first failure otherwise. Needs luajit (brew install luajit); without it
# the test is skipped (exit 0) so nobody is locked out. The same goes for a failed
# QuestieDB download (for example, when offline), but not for a checksum mismatch.
#
#     scripts/test.sh                       # test addons/PocketEssentials/QuestData.lua
#     scripts/test.sh path/to/QuestData.lua # test another copy of it
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit not installed (brew install luajit); skipping" >&2
    exit 0
fi

# Fast API check: every game name the addon uses was checked against Blizzard's
# source (tests/api/). Needs no network. A new name fails until scripts/audit-api.sh
# has been run.
luajit tests/api/extract.lua "$PWD" | luajit tests/api/fastcheck.lua "$PWD"

# Rule tests: each feature's rules against the stand-in client. Needs no network.
luajit tests/features/run.lua "$PWD"

# Capture the status explicitly: under set -e a failed $(...) assignment would
# abort before the handling below runs. Exit code 2 means the download failed
# (offline): skip. Anything else (such as 3, a checksum mismatch) is a real problem.
fetch_status=0
qdb_zip="$(scripts/fetch-questiedb.sh)" || fetch_status=$?
if [ "$fetch_status" -eq 2 ]; then
    # The smoke test's scenarios that need no QuestieDB still run.
    luajit tests/smoke/run.lua "$PWD"
    echo "could not download QuestieDB; QuestieDB tests skipped" >&2
    exit 0
elif [ "$fetch_status" -ne 0 ]; then
    echo "error: fetching QuestieDB failed (exit $fetch_status); see above" >&2
    exit "$fetch_status"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/pe-questiedb.XXXXXX")"
trap 'rm -rf "$work"' EXIT
unzip -q "$qdb_zip" -d "$work"

luajit tests/questiedb/harness.lua "$work/QuestieDB" "$PWD" "$@"

# Whole-addon smoke test: every file in the TOC, in the stand-in client.
luajit tests/smoke/run.lua "$PWD" "$work/QuestieDB"
