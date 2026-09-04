#!/bin/bash
# Build Suffix.app and wrap it in a DMG for a GitHub release.
#
# The DMG contains the app and a shortcut to /Applications, so installing is
# the drag people already know.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
STAGE="build/dmg"
DMG="build/Suffix-$VERSION.dmg"

./Scripts/build-app.sh

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Suffix.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# A note in the disk image itself, since this is the moment someone meets
# Gatekeeper and decides the app is broken.
cat > "$STAGE/If macOS blocks it — read me.txt" <<'NOTE'
macOS will refuse to open Suffix the first time, saying it cannot be verified.

That is Gatekeeper reacting to a missing Apple Developer signature (which costs
$99/year), not to anything the app does.

To open it:

  1. Drag Suffix to Applications, then try to open it. Let macOS block it.
  2. Open System Settings > Privacy & Security.
  3. Scroll down to the line about Suffix and click "Open Anyway".

You only do this once.

Suffix has no network access. It converts files using only what ships with
macOS, and never sends anything anywhere.
NOTE

hdiutil create -volname "Suffix" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
