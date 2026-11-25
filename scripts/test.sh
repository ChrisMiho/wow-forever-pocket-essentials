#!/bin/bash
# Offline tests: the fast API check (tests/api/), the check for calls into Blizzard's Lua (tests/taint/), the debug log reader's tests (tests/readlog/), the restriction probe
# reader's tests (tests/readprobe/) and the probe's own tests (tests/probe/, skipped when not there), then the QuestieDB harness,
# which puts every quest in the pinned QuestieDB release through our QuestData.lua under WoW API stand-ins (tests/questiedb/),
# then the whole-addon smoke test in the stand-in game client (tests/smoke/, tests/lib/fakeclient.lua),
# and the rule tests for every feature (tests/features/; the quest ones need QuestieDB and are skipped without it).
#
# Exits 0 and prints one summary line per suite on pass; exits 1 with FAIL: and
# the first failure otherwise. Needs luajit (brew install luajit); without it
# the test is skipped (exit 0) so nobody is locked out. The same goes for a failed
# QuestieDB download (for example, when offline), but not for a checksum mismatch.
# With PE_TEST_STRICT=1 (CI sets it) a missing luajit or a failed QuestieDB
# download is a failure (exit 1) instead of a skip, so nothing is skipped silently.
#
#     scripts/test.sh                       # test addons/PocketEssentials/QuestData.lua
#     scripts/test.sh path/to/QuestData.lua # test another copy of it
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v luajit >/dev/null 2>&1; then
    if [ "${PE_TEST_STRICT:-}" = "1" ]; then
        echo "FAIL: luajit not installed and PE_TEST_STRICT=1" >&2
        exit 1
    fi
    echo "luajit not installed (brew install luajit); skipping" >&2
    exit 0
fi

# Fast API check: every game name the addon uses was checked against Blizzard's
# source (tests/api/). Needs no network. A new name fails until scripts/audit-api.sh
# has been run.
luajit tests/api/extract.lua "$PWD" | luajit tests/api/fastcheck.lua "$PWD"

# Calls into Blizzard's Lua (tests/taint/): every function Blizzard wrote in Lua that the
# addon or the probe calls is listed in tests/taint/calls.txt with what it writes; an
# unlisted call, or one listed as "writes", fails. Uses Blizzard's source when it is at
# ~/.cache/wow-ui-source/forever (scripts/audit-api.sh fetches it), else tests/taint/names.txt.
luajit tests/taint/audit.lua "$PWD"

# The debug log reader (scripts/read-log.lua): the order of a wrapped log, the
# output, and that a saved file is loaded with nothing in reach. Needs no network.
luajit tests/readlog/run.lua "$PWD"

# The restriction probe's reader (scripts/read-probe.lua): the order of the
# situations, the tables, what differs between two files, and that a saved file
# is loaded with nothing in reach. Needs no network.
luajit tests/readprobe/run.lua "$PWD"

# The restriction probe itself (probe/PocketProbe, a separate addon for testing
# that players never get) in the stand-in client. Called after the rule tests.
probe_tests() {
    if [ -f tests/probe/run.lua ]; then
        luajit tests/probe/run.lua "$PWD"
    else
        echo "tests/probe/run.lua not found; probe tests skipped" >&2
    fi
}

# Capture the status explicitly: under set -e a failed $(...) assignment would
# abort before the handling below runs. Exit code 2 means the download failed
# (offline): skip. Anything else (such as 3, a checksum mismatch) is a real problem.
fetch_status=0
qdb_zip="$(scripts/fetch-questiedb.sh)" || fetch_status=$?
if [ "$fetch_status" -eq 2 ] && [ "${PE_TEST_STRICT:-}" = "1" ]; then
    echo "FAIL: could not download QuestieDB and PE_TEST_STRICT=1" >&2
    exit 1
elif [ "$fetch_status" -eq 2 ]; then
    # The rule tests and smoke scenarios that need no QuestieDB still run.
    luajit tests/features/run.lua "$PWD"
    probe_tests
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

# Rule tests: each feature's rules against the stand-in client. The quest ones
# get the QuestieDB directory.
luajit tests/features/run.lua "$PWD" "$work/QuestieDB"

probe_tests

luajit tests/questiedb/harness.lua "$work/QuestieDB" "$PWD" "$@"

# Whole-addon smoke test: every file in the TOC, in the stand-in client.
luajit tests/smoke/run.lua "$PWD" "$work/QuestieDB"
