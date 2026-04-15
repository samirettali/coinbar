#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
EXPORT_DIR="$BUILD_DIR/export"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
SCHEMES=(Coinbar Zonebar)

rm -rf "$EXPORT_DIR" "$DERIVED_DATA_DIR"
mkdir -p "$EXPORT_DIR"

for scheme in "$SCHEMES[@]"; do
  app_name="$scheme.app"
  zip_name="$scheme-macOS-unsigned.zip"

  xcodebuild \
    -project "$ROOT_DIR/Coinbar.xcodeproj" \
    -scheme "$scheme" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

  app_path="$DERIVED_DATA_DIR/Build/Products/Release/$app_name"

  if [[ ! -d "$app_path" ]]; then
    echo "Expected app bundle not found at: $app_path" >&2
    exit 1
  fi

  cp -R "$app_path" "$EXPORT_DIR/$app_name"

  ditto -c -k --sequesterRsrc --keepParent \
    "$EXPORT_DIR/$app_name" \
    "$BUILD_DIR/$zip_name"

  echo "Built app: $EXPORT_DIR/$app_name"
  echo "Created archive: $BUILD_DIR/$zip_name"
done
