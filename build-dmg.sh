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
# Vector PDF: Finder rasterizes it at the display scale, so it stays
# Retina-sharp (Tahoe draws raster backgrounds at raw pixel size).
cp "$ASSETS/background.pdf" "$STAGING/.background/background.pdf"
if [ -f "$ASSETS/volume.icns" ]; then
  cp "$ASSETS/volume.icns" "$STAGING/.VolumeIcon.icns"
fi

echo "▸ Ejecting stale PureClean volumes…"
for VOL in /Volumes/${VOLUME_NAME}*; do
  [ -d "$VOL" ] && hdiutil detach "$VOL" -force > /dev/null 2>&1 || true
done

echo "▸ Creating writable image…"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" \
  -ov -format UDRW -fs HFS+ "$DMG_RW" > /dev/null

echo "▸ Laying out the Finder window…"
MOUNT_DIR="/Volumes/$VOLUME_NAME"
hdiutil attach "$DMG_RW" -noautoopen > /dev/null
sleep 1

# macOS Tahoe draws plain /Applications symlinks as a dashed placeholder
# (create-dmg issue #202). Work around it: a Finder-made alias file with
# the real Applications-folder icon stamped on, falling back to a symlink.
echo "▸ Creating Applications shortcut…"
osascript > /dev/null <<EOF || true
tell application "Finder"
  make new alias file at (POSIX file "$MOUNT_DIR" as alias) to (POSIX file "/Applications" as alias)
  set name of result to "Applications"
end tell
EOF
if [ -e "$MOUNT_DIR/Applications" ]; then
  swift -e '
import AppKit
let icon = NSImage(contentsOfFile:
  "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns")
if let icon {
  NSWorkspace.shared.setIcon(icon, forFile: "'"$MOUNT_DIR"'/Applications", options: [])
}
' 2>/dev/null || true
else
  ln -s /Applications "$MOUNT_DIR/Applications"
fi

# Enable the custom volume icon flag (SetFile when available, otherwise
# write the kHasCustomIcon bit into FinderInfo directly).
if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
  if command -v SetFile > /dev/null 2>&1; then
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
  else
    xattr -wx com.apple.FinderInfo \
      "0000000000000000040000000000000000000000000000000000000000000000" \
      "$MOUNT_DIR" 2>/dev/null || true
  fi
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
    set pathbar visible of container window to false
    -- 660×440 content + 28 pt title bar, matching the artwork exactly.
    set the bounds of container window to {200, 120, 860, 588}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.pdf"
    set position of item "$APP_NAME.app" of container window to {165, 195}
    set position of item "Applications" of container window to {495, 195}
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
