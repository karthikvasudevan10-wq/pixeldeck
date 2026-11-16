#!/bin/sh
# Uploads the newest Pixel Deck archive to App Store Connect without the Organizer's
# Distribute button. Run from the repository folder after Product > Archive:
#     sh Tools/upload-archive.sh
set -e
ARCHIVES="$HOME/Library/Developer/Xcode/Archives"
LATEST=$(find "$ARCHIVES" -name "PixelDeck*.xcarchive" -maxdepth 2 -print0 | xargs -0 ls -dt | head -n 1)
if [ -z "$LATEST" ]; then
  echo "No PixelDeck archive found. In Xcode, choose Any iOS Device, then Product > Archive."
  exit 1
fi
echo "Uploading: $LATEST"
OUT="$(mktemp -d)"
xcodebuild -exportArchive \
  -archivePath "$LATEST" \
  -exportOptionsPlist "$(dirname "$0")/ExportOptions.plist" \
  -exportPath "$OUT" \
  -allowProvisioningUpdates
echo "Done. App Store Connect emails you when the build has finished processing (usually 10-30 minutes)."
