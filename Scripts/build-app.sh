#!/bin/bash
# Build Suffix.app from the SwiftPM executable.
#
# SwiftPM produces a bare binary; macOS needs a bundle for a menu-bar app to
# have an identity — notifications, preferences, and the per-folder privacy
# prompts are all keyed to the bundle id, so the binary alone is not enough.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="${APP_DEST:-build/Suffix.app}"
BUNDLE_ID="io.github.pewpewbiches.Suffix"
VERSION="0.1.0"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG" --product SuffixApp

BIN=$(swift build -c "$CONFIG" --product SuffixApp --show-bin-path)/SuffixApp

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Suffix"
cp Resources/Suffix.icns "$APP/Contents/Resources/Suffix.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Suffix</string>
  <key>CFBundleDisplayName</key><string>Suffix</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>Suffix</string>
  <key>CFBundleIconFile</key><string>Suffix</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Menu-bar only: no Dock icon. -->
  <key>LSUIElement</key><true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Suffix converts files on your Desktop when you change their extension.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Suffix converts files in Documents when you change their extension.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Suffix converts files in Downloads when you change their extension.</string>
  <key>NSRemovableVolumesUsageDescription</key>
  <string>Suffix converts files on external drives when you change their extension.</string>
  <!-- Finder right-click entries. NSSendFileTypes decides which selections
       they appear for, so they stay out of the menu for everything else. -->
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Merge into one PDF</string></dict>
      <key>NSMessage</key><string>mergeIntoPDF</string>
      <key>NSPortName</key><string>Suffix</string>
      <key>NSRequiredContext</key><dict><key>NSTextContent</key><string>FilePath</string></dict>
      <key>NSSendFileTypes</key>
      <array>
        <string>com.adobe.pdf</string>
        <string>public.image</string>
      </array>
    </dict>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Compress…</string></dict>
      <key>NSMessage</key><string>compressFiles</string>
      <key>NSPortName</key><string>Suffix</string>
      <key>NSRequiredContext</key><dict><key>NSTextContent</key><string>FilePath</string></dict>
      <key>NSSendFileTypes</key>
      <array>
        <string>com.adobe.pdf</string>
        <string>public.image</string>
      </array>
    </dict>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Create ZIP archive</string></dict>
      <key>NSMessage</key><string>createZIP</string>
      <key>NSPortName</key><string>Suffix</string>
      <key>NSRequiredContext</key><dict><key>NSTextContent</key><string>FilePath</string></dict>
      <key>NSSendFileTypes</key><array><string>public.item</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Ad-hoc signature. Enough for notifications and for macOS to remember which
# folders you granted; a Developer ID is only needed to distribute it.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 \
  && echo "Signed (ad-hoc)." \
  || echo "Warning: could not sign; notifications may fall back to on-screen notices."

echo "Built $APP"
