#!/bin/sh
# Build Underrug.app with the Command Line Tools (no Xcode project needed).
set -e
cd "$(dirname "$0")"
APP=build/Underrug.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# one universal binary: Apple silicon and Intel
for arch in arm64 x86_64; do
  swiftc -Ounchecked -wmo -enforce-exclusivity=unchecked -swift-version 5 -target $arch-apple-macos13.0 \
    -framework AppKit -framework ServiceManagement \
    Sources/*.swift -o build/Underrug-$arch
done
lipo -create build/Underrug-arm64 build/Underrug-x86_64 -output "$APP/Contents/MacOS/Underrug"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Rugs "$APP/Contents/Resources/Rugs"
"$APP/Contents/MacOS/Underrug" --icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP" >/dev/null
echo "built $APP"
