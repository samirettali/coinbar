#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
EXPORT_DIR="$BUILD_DIR/export"

rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

cd "$ROOT_DIR"
swift build -c release

EXECUTABLE="$ROOT_DIR/.build/release/Pulse"

if [[ ! -f "$EXECUTABLE" ]]; then
  echo "Executable not found at: $EXECUTABLE" >&2
  exit 1
fi

APP="$EXPORT_DIR/Pulse.app"
mkdir -p "$APP/Contents/MacOS"

cp "$EXECUTABLE" "$APP/Contents/MacOS/Pulse"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Pulse</string>
    <key>CFBundleIdentifier</key>
    <string>com.settali.pulse</string>
    <key>CFBundleName</key>
    <string>Pulse</string>
    <key>CFBundleDisplayName</key>
    <string>Pulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

ditto -c -k --sequesterRsrc --keepParent \
  "$APP" \
  "$BUILD_DIR/Pulse-macOS-unsigned.zip"

echo "Built app: $APP"
echo "Created archive: $BUILD_DIR/Pulse-macOS-unsigned.zip"
