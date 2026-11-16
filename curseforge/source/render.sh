#!/usr/bin/env bash
# Renders the CurseForge description images from the HTML pages in this folder
# with headless Chrome. Run from anywhere: curseforge/source/render.sh
# Output: curseforge/images/<page>.png at 1280x720 (pillars: 1280x520).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../images"
mkdir -p "$out"

browser=""
for candidate in \
	"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
	"$(command -v google-chrome || true)" \
	"$(command -v chromium || true)"; do
	if [ -n "$candidate" ] && [ -x "$candidate" ]; then browser="$candidate"; break; fi
done
if [ -z "$browser" ]; then echo "No Chrome found" >&2; exit 1; fi

pages=("$@")
if [ ${#pages[@]} -eq 0 ]; then
	pages=(pillars feature-quests feature-bags feature-vendor feature-chat feature-settings)
fi

for page in "${pages[@]}"; do
	height=720
	[ "$page" = pillars ] && height=520
	"$browser" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
		--default-background-color=00000000 --window-size=1280,$height \
		--screenshot="$out/$page.png" "file://$here/$page.html" >/dev/null 2>&1
	echo "wrote images/$page.png"
done
