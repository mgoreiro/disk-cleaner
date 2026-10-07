#!/bin/zsh
# Compila y empaqueta Disk Cleaner como app de macOS en build/DiskCleaner.app
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/DiskCleaner.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DiskCleaner "$APP/Contents/MacOS/DiskCleaner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SIGN_ID=<identidad> mantiene estable el permiso de "Acceso total al disco" entre compilaciones.
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Listo: $APP"
