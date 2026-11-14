#!/bin/bash
# Quick sanity check for the addon's Lua, run before committing (and by the Stop hook).
#
# 1. Every .lua file listed in PocketEssentials.toc must compile under LuaJIT,
#    which is close enough to the game's Lua 5.1 to catch syntax errors.
# 2. No comment may use owner wording (the code is read by players, not by us).
#
# If luajit is not installed the check is skipped (exit 0) so nobody is locked out:
#     brew install luajit
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v luajit >/dev/null 2>&1; then
    echo "luajit not installed (brew install luajit); skipping" >&2
    exit 0
fi

toc=addons/PocketEssentials/PocketEssentials.toc
while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *.lua) ;; *) continue ;; esac
    f="addons/PocketEssentials/$line"
    if [ ! -f "$f" ]; then
        echo "error: $toc lists $line, which does not exist" >&2
        exit 1
    fi
    if ! luajit -bl "$f" >/dev/null; then
        echo "error: $f does not compile" >&2
        exit 1
    fi
done < "$toc"

if grep -rn -i -E '\bthe owner\b|owner.s\b|owner chose|owner changed|owner first' addons/PocketEssentials --include='*.lua'; then
    echo "error: owner wording found in the Lua files above" >&2
    exit 1
fi

echo "All Lua files compile."
