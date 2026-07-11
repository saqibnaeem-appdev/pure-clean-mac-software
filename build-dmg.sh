#!/bin/bash
# Builds PureClean in Release and packages a branded drag-to-install .dmg:
# Retina background artwork, positioned icons, volume icon, UDZO compressed.
# Usage: ./build-dmg.sh
set -euo pipefail

APP_NAME="PureClean"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
STAGING="$DIST/staging"
ASSETS="$DIST/dmg-assets"
DMG_RW="$DIST/${APP_NAME}-rw.dmg"
DMG_PATH="$DIST/${APP_NAME}.dmg"
VOLUME_NAME="$APP_NAME"

echo "▸ Building Release…"
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath "$DIST/DerivedData" build \
  CODE_SIGN_IDENTITY="-" -quiet

APP_PATH="$DIST/DerivedData/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP_PATH" ] || { echo "✗ Build product not found"; exit 1; }

echo "▸ Rendering installer artwork…"
swift "$ROOT/make-dmg-background.swift" "$ASSETS"
# Multi-resolution TIFF so Finder picks the Retina layer automatically.
tiffutil -cathidpicheck "$ASSETS/background.png" "$ASSETS/background@2x.png" \
  -out "$ASSETS/background.tiff" 2>/dev/null

echo "▸ Building volume icon…"
ICONSET="$DIST/volume.iconset"
rm -rf "$ICONSET"
cp -R "$ROOT/PureClean/Resources/Assets.xcassets/AppIcon.appiconset" "$ICONSET"
rm -f "$ICONSET/Contents.json"
iconutil -c icns "$ICONSET" -o "$ASSETS/volume.icns" 2>/dev/null || true
rm -rf "$ICONSET"

echo "▸ Staging disk image…"
rm -rf "$STAGING" "$DMG_RW" "$DMG_PATH"
mkdir -p "$STAGING/.background"
cp -R "$APP_PATH" "$STAGING/"
cp "$ASSETS/background.tiff" "$STAGING/.background/background.tiff"
ln -s /Applications "$STAGING/Applications"
if [ -f "$ASSETS/volume.icns" ]; then
  cp "$ASSETS/volume.icns" "$STAGING/.VolumeIcon.icns"
fi

echo "▸ Creating writable image…"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" \
  -ov -format UDRW -fs HFS+ "$DMG_RW" > /dev/null

echo "▸ Laying out the Finder window…"
MOUNT_DIR="/Volumes/$VOLUME_NAME"
hdiutil attach "$DMG_RW" -noautoopen > /dev/null
sleep 1

# Enable the custom volume icon flag.
if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
  SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# Finder scripting sets the icon view, background and icon positions.
# Best effort: if Automation permission is denied the DMG still works.
osascript <<EOF || echo "  (Finder layout skipped — grant Automation permission for the full look)"
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 560}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {165, 205}
    set position of item "Applications" of container window to {495, 205}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sync
hdiutil detach "$MOUNT_DIR" > /dev/null

echo "▸ Compressing…"
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" > /dev/null
rm -f "$DMG_RW"
rm -rf "$STAGING"

echo "✓ Done: $DMG_PATH"
echo "  Open it and drag ${APP_NAME} into Applications."
