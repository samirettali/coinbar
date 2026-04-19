#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
EXPORT_DIR="$BUILD_DIR/export"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"

rm -rf "$EXPORT_DIR" "$DERIVED_DATA_DIR"
mkdir -p "$EXPORT_DIR"

xcodebuild \
  -project "$ROOT_DIR/Coinbar.xcodeproj" \
  -scheme Pulse \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

app_path="$DERIVED_DATA_DIR/Build/Products/Release/Pulse.app"

if [[ ! -d "$app_path" ]]; then
  echo "Expected app bundle not found at: $app_path" >&2
  exit 1
fi

cp -R "$app_path" "$EXPORT_DIR/Pulse.app"

ditto -c -k --sequesterRsrc --keepParent \
  "$EXPORT_DIR/Pulse.app" \
  "$BUILD_DIR/Pulse-macOS-unsigned.zip"

echo "Built app: $EXPORT_DIR/Pulse.app"
echo "Created archive: $BUILD_DIR/Pulse-macOS-unsigned.zip"
