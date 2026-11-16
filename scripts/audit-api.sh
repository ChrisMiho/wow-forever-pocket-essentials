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
cd "$(dirname "$0")/.."

EXPECTED="1.60.1 (70938)"
clone="${1:-$HOME/.cache/wow-ui-source/forever}"

if ! command -v luajit >/dev/null 2>&1; then
    echo "error: luajit not installed (brew install luajit)" >&2
    exit 1
fi
if [ ! -d "$clone/Interface/AddOns" ]; then
    echo "cloning Blizzard's interface source into $clone (one time)..." >&2
    mkdir -p "$(dirname "$clone")"
    git clone --quiet --branch forever --single-branch https://github.com/Gethe/wow-ui-source.git "$clone"
fi
actual="$(git -C "$clone" log -1 --format=%s)"
if [ "$actual" != "$EXPECTED" ]; then
    echo "error: the interface source at $clone is '$actual', but this audit is for '$EXPECTED'." >&2
    echo "Check out the matching commit (or update EXPECTED here once the client is rebuilt) and run again." >&2
    exit 1
fi

luajit tests/api/audit.lua "$PWD" "$clone"
