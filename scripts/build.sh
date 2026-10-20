#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/CitrusDrop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${1:-}" == "--universal" ]]; then
  # Separate slices work with Command Line Tools alone; no full Xcode required.
  swift build -c release --arch arm64
  swift build -c release --arch x86_64
  ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/CitrusDrop"
  INTEL_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/CitrusDrop"
  /usr/bin/lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP/Contents/MacOS/CitrusDrop"
else
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
  cp "$BIN_DIR/CitrusDrop" "$APP/Contents/MacOS/CitrusDrop"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/CitrusDrop.icns ]]; then cp Resources/CitrusDrop.icns "$APP/Contents/Resources/"; fi
cp -R Resources/ru.lproj Resources/en.lproj "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '\nBuilt: %s/dist/CitrusDrop.app\n' "$PWD"
