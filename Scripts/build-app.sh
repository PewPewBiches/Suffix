#!/bin/bash
# Build REname.app from the SwiftPM executable.
#
# SwiftPM produces a bare binary; macOS needs a bundle for a menu-bar app to
# have an identity — notifications, preferences, and the per-folder privacy
# prompts are all keyed to the bundle id, so the binary alone is not enough.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="${APP_DEST:-build/REname.app}"
BUNDLE_ID="com.local.REname"
VERSION="0.1.0"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG" --product RenameApp

BIN=$(swift build -c "$CONFIG" --product RenameApp --show-bin-path)/RenameApp

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/REname"
cp Resources/REname.icns "$APP/Contents/Resources/REname.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>REname</string>
  <key>CFBundleDisplayName</key><string>REname</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>REname</string>
  <key>CFBundleIconFile</key><string>REname</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Menu-bar only: no Dock icon. -->
  <key>LSUIElement</key><true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>REname converts files on your Desktop when you change their extension.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>REname converts files in Documents when you change their extension.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>REname converts files in Downloads when you change their extension.</string>
  <key>NSRemovableVolumesUsageDescription</key>
  <string>REname converts files on external drives when you change their extension.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. Enough for notifications and for macOS to remember which
# folders you granted; a Developer ID is only needed to distribute it.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 \
  && echo "Signed (ad-hoc)." \
  || echo "Warning: could not sign; notifications may fall back to on-screen notices."

echo "Built $APP"
