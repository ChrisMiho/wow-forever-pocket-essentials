#!/bin/bash
# Prints the debug log and the Errors page from a saved-settings file as plain
# text, one block per play session, then other addons' and the game's errors
# (Catch all errors) grouped by source. The file is the one the game writes at
# logout and at a reload:
#     World of Warcraft/_forever_/WTF/Account/<account>/SavedVariables/PocketEssentials.lua
#
#     scripts/read-log.sh path/to/PocketEssentials.lua
#     scripts/read-log.sh path/to/PocketEssentials.lua --grep sellJunk   # only lines matching a Lua pattern
#     scripts/read-log.sh path/to/PocketEssentials.lua --errors          # the Errors page only
#
# The file is only read: it is run with no access to files, the system or
# other code (scripts/read-log.lua). Needs luajit (brew install luajit);
# without it nothing is read (exit 0 with a notice).
set -euo pipefail

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit not installed (brew install luajit); skipping" >&2
    exit 0
fi

exec luajit "$(dirname "$0")/read-log.lua" "$@"
