#!/bin/bash
# Builds PureClean in Release and packages a drag-to-Applications .dmg.
# Usage: ./build-dmg.sh
set -euo pipefail

APP_NAME="PureClean"
DIST="$(cd "$(dirname "$0")" && pwd)/dist"
STAGING="$DIST/staging"
DMG_PATH="$DIST/${APP_NAME}.dmg"

echo "▸ Building Release…"
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath "$DIST/DerivedData" build \
  CODE_SIGN_IDENTITY="-" > /dev/null

APP_PATH="$DIST/DerivedData/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP_PATH" ] || { echo "✗ Build product not found"; exit 1; }

echo "▸ Staging disk image…"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target

echo "▸ Creating .dmg…"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG_PATH" > /dev/null
rm -rf "$STAGING"

echo "✓ Done: $DMG_PATH"
echo "  Open it and drag ${APP_NAME} into Applications."
