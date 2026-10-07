#!/bin/zsh
# Genera build/DiskCleaner-<versión>.dmg con la app y un acceso directo a /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
APP=build/DiskCleaner.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="build/DiskCleaner-$VERSION.dmg"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Disk Cleaner $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Listo: $DMG"
