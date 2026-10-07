#!/usr/bin/env bash
# Usage: shot-url.sh <url> <output.png>
URL="$1"; OUT="$2"
mkdir -p "$(dirname "$OUT")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BRAVE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
EDGE="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
for B in "$CHROME" "$BRAVE" "$EDGE"; do
  if [ -x "$B" ]; then
    "$B" --headless=new --disable-gpu --hide-scrollbars --no-sandbox \
         --virtual-time-budget=4000 --window-size=1280,800 \
         --screenshot="$OUT" "$URL" >/dev/null 2>&1
    [ -s "$OUT" ] && { echo "captured (headless): $OUT"; exit 0; }
  fi
done
# Fallback: open in the default browser and capture the whole screen.
open "$URL"
sleep 4
screencapture -x -o "$OUT" >/dev/null 2>&1
[ -s "$OUT" ] && { echo "captured (screencapture): $OUT"; exit 0; }
echo "SCREENSHOT FAILED for $URL - falling back to text evidence" >&2
exit 1
