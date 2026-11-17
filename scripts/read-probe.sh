#!/bin/bash
# Prints the restriction probe's results from its saved file as plain text:
# what the game allowed, in each situation the probe ran in. The file is the
# one the game writes at logout and at a reload:
#     World of Warcraft/_forever_/WTF/Account/<account>/SavedVariables/PocketProbe.lua
#
#     scripts/read-probe.sh path/to/PocketProbe.lua                      # the tables, then everything that was not allowed
#     scripts/read-probe.sh path/to/PocketProbe.lua --markdown           # the tables, ready to paste into docs/ARCHITECTURE.md
#     scripts/read-probe.sh path/to/PocketProbe.lua --details            # only what was not allowed, with function names and stack lines
#     scripts/read-probe.sh path/to/PocketProbe.lua --log                # the probe's activity log
#     scripts/read-probe.sh path/to/PocketProbe.lua --diff other.lua     # only the cells that differ between two files
#
# The file is only read: it is run with no access to files, the system or
# other code (scripts/read-probe.lua). Needs luajit (brew install luajit);
# without it nothing is read (exit 0 with a notice).
set -euo pipefail

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit not installed (brew install luajit); skipping" >&2
    exit 0
fi

exec luajit "$(dirname "$0")/read-probe.lua" "$@"
