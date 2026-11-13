#!/bin/bash
# Builds dist/MobileAddonBundle.zip with every folder in addons/ at the zip root,
# ready to extract straight into the game's Interface/AddOns folder.
set -euo pipefail

cd "$(dirname "$0")/.."

out="dist/MobileAddonBundle.zip"
mkdir -p dist
rm -f "$out"

# Every addon folder must contain a .toc named after the folder, or the game ignores it.
for dir in addons/*/; do
    name="$(basename "$dir")"
    if [ ! -f "$dir$name.toc" ]; then
        echo "error: $dir has no $name.toc" >&2
        exit 1
    fi
done

(cd addons && zip -qr -X "../$out" . -x '*.DS_Store')

echo "Built $out:"
unzip -l "$out"
