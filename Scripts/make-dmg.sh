#!/bin/bash
# Build Suffix.app and wrap it in a disk image for a GitHub release.
#
# The window is the first thing anyone sees, before the app has drawn a pixel
# of its own, so it is laid out rather than left to Finder: a System 7
# background, two icons, and the Gatekeeper warning said *before* it happens
# instead of in a text file nobody opens.
#
# Doing that means building read-write, letting Finder write a .DS_Store with
# the view settings in it, then compressing. A read-only image cannot be
# decorated.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-$(cat VERSION)}"
VOL="Suffix"
STAGE="build/dmg"
RW="build/rw.dmg"
DMG="build/Suffix-$VERSION.dmg"

./Scripts/build-app.sh

rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
cp -R build/Suffix.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# A Retina background is one TIFF holding both scales; Finder picks per display.
swift Scripts/make-dmg-background.swift "$STAGE/.background/bg.png"    1 >/dev/null
swift Scripts/make-dmg-background.swift "$STAGE/.background/bg@2x.png" 2 >/dev/null
tiffutil -cathidpicheck "$STAGE/.background/bg.png" "$STAGE/.background/bg@2x.png" \
         -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
rm -f "$STAGE/.background/bg.png" "$STAGE/.background/bg@2x.png"

# Room to breathe: the image has to be bigger than its contents or the copy
# fails on the last file with no useful message.
SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov \
        -fs HFS+ -format UDRW -size "${SIZE}m" "$RW" >/dev/null

# A left-over mount makes the new one "Suffix 1", and the AppleScript below
# would then decorate the stale volume and silently succeed.
for stale in /Volumes/"$VOL"*; do
  [ -d "$stale" ] && hdiutil detach "$stale" -force >/dev/null 2>&1 || true
done

MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | \
        grep -o '/Volumes/.*' | head -1)
trap 'hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true' EXIT
MOUNTED_VOL=$(basename "$MOUNT")
[ "$MOUNTED_VOL" = "$VOL" ] || { echo "mounted as '$MOUNTED_VOL', expected '$VOL'"; exit 1; }

# Finder holds the view settings, so Finder has to be the one to set them.
# Coordinates are the icon centres, and they match the artwork in
# Scripts/make-dmg-background.swift — change one and change the other.
# The background is set from a POSIX path. The `file ".background:x.tiff"`
# colon form that every DMG recipe on the internet uses fails here with
# -10006 — Finder resolves it against the wrong container.
osascript >/dev/null <<APPLESCRIPT || echo "  note: could not style the window (grant Terminal automation access for Finder)"
tell application "Finder"
  tell disk "$MOUNTED_VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 568}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 12
    set background picture of opts to POSIX file "$MOUNT/.background/background.tiff"
    set position of item "Suffix.app" of container window to {170, 214}
    set position of item "Applications" of container window to {470, 214}
    delay 1
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

[ -f "$MOUNT/.DS_Store" ] || { echo "the window layout did not save — refusing to ship a plain disk image"; exit 1; }

hdiutil detach "$MOUNT" >/dev/null
trap - EXIT

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
