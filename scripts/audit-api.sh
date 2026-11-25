#!/bin/bash
# Full API audit: checks every game name the addon uses (tests/api/extract.lua)
# against Blizzard's interface source for this client (Gethe/wow-ui-source,
# branch "forever") and rewrites tests/api/verified.txt and unverified.txt.
# Slow (about a minute) and needs the clone; the fast check in scripts/test.sh
# does not. Exits 1 when a name is neither verified nor explained in
# unverified.txt.
#
#     scripts/audit-api.sh [path to wow-ui-source clone]
#
# The default clone is ~/.cache/wow-ui-source/forever (cloned if missing).
set -euo pipefail
export LC_ALL=C   # sort order must not depend on the locale, or the evidence choice and snapshot would differ
cd "$(dirname "$0")/.."

# The Blizzard source this audit is pinned to: one commit of the "forever"
# branch, and the build string in that commit's subject. After a client patch,
# find the new commit (github.com/Gethe/wow-ui-source, branch forever), put its
# full hash in PIN and its subject in EXPECTED, run this script, and commit the
# changed files in tests/api/. The CI cache is keyed on this file, so a new PIN
# starts a fresh download.
PIN="c01a87b549bbc19e0f284c1616d18654c91297de"
EXPECTED="1.60.1 (71091)"
clone="${1:-$HOME/.cache/wow-ui-source/forever}"

if ! command -v luajit >/dev/null 2>&1; then
    echo "error: luajit not installed (brew install luajit)" >&2
    exit 1
fi
if [ ! -d "$clone/Interface/AddOns" ]; then
    echo "fetching Blizzard's interface source ($PIN) into $clone (one time)..." >&2
    mkdir -p "$clone"
    git -C "$clone" init --quiet
    git -C "$clone" remote add origin https://github.com/Gethe/wow-ui-source.git 2>/dev/null || true
fi
if [ "$(git -C "$clone" rev-parse HEAD 2>/dev/null || true)" != "$PIN" ]; then
    # An existing clone at another commit is moved to the pin, not deleted.
    git -C "$clone" fetch --quiet --depth 1 origin "$PIN"
    git -C "$clone" checkout --quiet --force "$PIN"
fi
actual="$(git -C "$clone" log -1 --format=%s)"
if [ "$actual" != "$EXPECTED" ]; then
    echo "error: the interface source at $clone is '$actual', but this audit is for '$EXPECTED'." >&2
    echo "PIN and EXPECTED at the top of this script do not belong together; fix them and run again." >&2
    exit 1
fi

luajit tests/api/audit.lua "$PWD" "$clone"
