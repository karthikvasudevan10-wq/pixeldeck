#!/bin/bash
# Opens the Mac app that the build check just built, photographs its window and describes the
# picture as text in the build log (Tools/ci/describe.py), so the layout can be checked from the log.
# usage: mac_shots.sh /path/to/PixelDeck.app
APP="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
codesign --force --deep --sign - "$APP" > /dev/null 2>&1 || true
mkdir -p shots

window() {   # prints "id x y width height" of the app's biggest window
  swift - <<'SWIFT'
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best = ""
var bestArea = 0.0
for w in list where (w["kCGWindowOwnerName"] as? String) == "PixelDeck" {
    guard let b = w["kCGWindowBounds"] as? [String: Any], let n = w["kCGWindowNumber"] as? Int,
          let width = b["Width"] as? Double, let height = b["Height"] as? Double,
          let x = b["X"] as? Double, let y = b["Y"] as? Double else { continue }
    if width * height > bestArea { bestArea = width * height; best = "\(n) \(Int(x)) \(Int(y)) \(Int(width)) \(Int(height))" }
}
print(best)
SWIFT
}

for mode in ${MODES:-0}; do
  echo "===== MAC WINDOW, titlebar experiment $mode ====="
  open -n --stderr "$PWD/shots/diag-$mode.txt" "$APP" --args -hasSeenOnboarding YES -tourOffered YES -tourCompleted YES -pdTitlebar "$mode"
  sleep 14
  info=($(window))
  echo "window: id x y width height = ${info[*]}"
  if [ -n "${info[0]}" ]; then
    screencapture -x -o -l"${info[0]}" "shots/mac-$mode.png" || echo "screencapture failed"
    sips -s format bmp "shots/mac-$mode.png" --out "shots/mac-$mode.bmp" > /dev/null 2>&1
    grep -h "PD-DIAG\|scene \|uiwindow\|nswindow" "shots/diag-$mode.txt" || true
    for region in $REGIONS; do
      # region: cell:x:y:w:h (pixels of the picture)
      IFS=: read -r cell x y w h <<< "$region"
      python3 "$HERE/describe.py" "shots/mac-$mode.bmp" "$cell" "$x" "$y" "$w" "$h"
    done
    rm -f "shots/mac-$mode.bmp"
  else
    echo "no window found"; tail -5 "shots/diag-$mode.txt" 2>/dev/null
    ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | head -3
  fi
  pkill -x PixelDeck || echo "app was not running"
  sleep 2
done
