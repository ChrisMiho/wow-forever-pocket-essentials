#!/usr/bin/env bash
# Renders every CurseForge image from the HTML pages in this folder with
# headless Chrome. Run from anywhere: curseforge/source/render.sh [page ...]
# Output:
#   curseforge/avatar.png             400x400
#   curseforge/banner.png             1280x640
#   curseforge/images/<page>.png      1280x720 (overview and feature-*)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$here/.."
mkdir -p "$out/images"

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
	pages=(avatar banner overview feature-quests feature-bags feature-vendor feature-chat
		feature-setup)
fi

for page in "${pages[@]}"; do
	size=1280,720
	target="images/$page.png"
	case "$page" in
		avatar) size=400,400; target="avatar.png" ;;
		banner) size=1280,640; target="banner.png" ;;
	esac
	"$browser" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
		--window-size="$size" --screenshot="$out/$target" "file://$here/$page.html" >/dev/null 2>&1
	echo "wrote $target"
done
