#!/bin/bash
# Builds NeonSwitch.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP=build/NeonSwitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# App icon: render once from Scripts/make_icon.swift, then pack into .icns
if [ ! -f Resources/AppIcon.icns ]; then
  mkdir -p Resources
  [ -f Resources/icon_1024.png ] || swift Scripts/make_icon.swift Resources/icon_1024.png
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
  rm -rf "$ICONSET"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Universal binary: Apple Silicon + Intel
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 \
    -target "$ARCH-apple-macos14.0" \
    -framework AppKit -framework SwiftUI -framework ServiceManagement \
    Sources/*.swift -o "build/NeonSwitch-$ARCH"
done
lipo -create build/NeonSwitch-arm64 build/NeonSwitch-x86_64 -output "$APP/Contents/MacOS/NeonSwitch"
rm build/NeonSwitch-arm64 build/NeonSwitch-x86_64

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NeonSwitch</string>
  <key>CFBundleDisplayName</key><string>NeonSwitch</string>
  <key>CFBundleIdentifier</key><string>dev.mahmoud.neonswitch</string>
  <key>CFBundleExecutable</key><string>NeonSwitch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"

# Package as a drag-to-install DMG
DMG=build/NeonSwitch.dmg
STAGE=build/dmg
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "NeonSwitch" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
