#!/bin/sh
# Build Underrug.app with the Command Line Tools (no Xcode project needed).
set -e
cd "$(dirname "$0")"
APP=build/Underrug.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -Ounchecked -wmo -enforce-exclusivity=unchecked -swift-version 5 -target arm64-apple-macos13.0 \
  -framework AppKit -framework SceneKit -framework ServiceManagement \
  Sources/*.swift -o "$APP/Contents/MacOS/Underrug"
cp Info.plist "$APP/Contents/Info.plist"
"$APP/Contents/MacOS/Underrug" --icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP" >/dev/null
echo "built $APP"
