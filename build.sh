#!/bin/bash
# Build Mercury.app  (run on macOS — needs the Swift toolchain / Xcode CLT)
set -e
cd "$(dirname "$0")"

APP="Mercury.app"
EXE="Mercury"
BUNDLE_ID="com.selfhosted.mercury"

echo "› compiling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O Sources/*.swift \
    -o "$APP/Contents/MacOS/$EXE" \
    -framework Cocoa -framework CoreGraphics -framework ServiceManagement

echo "› bundling resources…"
cp Resources/RibbonIcon.png "$APP/Contents/Resources/"
cp Resources/AppIcon.png    "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$EXE</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>Mercury</string>
    <key>CFBundleDisplayName</key><string>Mercury</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "› signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ built $APP"
echo "  open with:  open $APP"
echo "  first run:  enable Mercury under System Settings ▸ Privacy & Security ▸ Input Monitoring, then relaunch."