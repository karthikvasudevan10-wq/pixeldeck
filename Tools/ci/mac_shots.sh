#!/bin/bash
# Opens the Mac app that the build check just built, photographs its window and describes the
# picture as text in the build log (Tools/ci/describe.py), so the layout can be checked from the log.
# usage: mac_shots.sh /path/to/PixelDeck.app
APP="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
codesign --force --deep --sign - "$APP" > /dev/null 2>&1 || true
mkdir -p shots

window() {   # prints "id x y width height" of the app's biggest window
  swift - "$(pgrep -x PixelDeck | head -1)" <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments.last ?? "") ?? -1
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best = ""
var bestArea = 0.0
for w in list where (w["kCGWindowOwnerPID"] as? Int) == pid {
    guard let b = w["kCGWindowBounds"] as? [String: Any], let n = w["kCGWindowNumber"] as? Int,
          let width = b["Width"] as? Double, let height = b["Height"] as? Double,
          let x = b["X"] as? Double, let y = b["Y"] as? Double else { continue }
    if width * height > bestArea { bestArea = width * height; best = "\(n) \(Int(x)) \(Int(y)) \(Int(width)) \(Int(height))" }
}
print(best)
SWIFT
}

echo "===== MAC WINDOW ====="
# Straight to the Studio: skip the welcome screens and the guided tour.
open -n "$APP" --args -hasSeenOnboarding YES -tourOffered YES -tourCompleted YES
sleep 14
info=($(window))
echo "window: id x y width height = ${info[*]}"
if [ -n "${info[0]}" ]; then
  screencapture -x -o -l"${info[0]}" shots/mac.png || echo "screencapture failed"
  sips -s format bmp shots/mac.png --out shots/mac.bmp > /dev/null 2>&1
  # The picture may have two pixels for each point of the window.
  pixels=$(sips -g pixelWidth shots/mac.png | awk '/pixelWidth/ {print $2}')
  scale=$(( pixels / ${info[3]} )); [ "$scale" -lt 1 ] && scale=1
  echo "picture is $pixels pixels wide: $scale for each point"
  for region in ${REGIONS:-8:0:0:1400:1000}; do
    # region: cell:x:y:w:h, in points of the window
    IFS=: read -r cell x y w h <<< "$region"
    python3 "$HERE/describe.py" shots/mac.bmp $((cell * scale)) $((x * scale)) $((y * scale)) $((w * scale)) $((h * scale))
  done
  rm -f shots/mac.bmp
else
  echo "no window found"
  ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | head -3
fi
pkill -x PixelDeck || echo "app was not running"
