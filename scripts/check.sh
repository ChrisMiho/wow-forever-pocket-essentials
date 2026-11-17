#!/bin/bash
# Quick sanity check for the addon's Lua, run before committing (and by the Stop hook).
#
# 1. Every .lua file listed in PocketEssentials.toc must compile under LuaJIT,
#    which is close enough to the game's Lua 5.1 to catch syntax errors.
# 2. No comment may use owner wording (the code is read by players, not by us).
# 3. The same two checks for the restriction probe (probe/PocketProbe, a
#    separate addon for testing that players never get), when it is there.
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

# The restriction probe, when it is there.
probe_toc=probe/PocketProbe/PocketProbe.toc
wording_dirs=(addons/PocketEssentials)
if [ -f "$probe_toc" ]; then
    wording_dirs+=(probe)
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in ''|'#'*) continue ;; esac
        case "$line" in *.lua) ;; *) continue ;; esac
        f="probe/PocketProbe/${line//\\//}"
        if [ ! -f "$f" ]; then
            echo "error: $probe_toc lists $line, which does not exist" >&2
            exit 1
        fi
        if ! luajit -bl "$f" >/dev/null; then
            echo "error: $f does not compile" >&2
            exit 1
        fi
    done < "$probe_toc"
fi

if grep -rn -i -E '\bthe owner\b|owner.s\b|owner chose|owner changed|owner first' "${wording_dirs[@]}" --include='*.lua'; then
    echo "error: owner wording found in the Lua files above" >&2
    exit 1
fi

echo "All Lua files compile."
