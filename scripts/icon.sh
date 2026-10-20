#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/citrusdrop-icon.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/CitrusDrop.iconset"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" docs/brand/logo.png --out "$STAGE/CitrusDrop.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size*2))
  /usr/bin/sips -z "$doubled" "$doubled" docs/brand/logo.png --out "$STAGE/CitrusDrop.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$STAGE/CitrusDrop.iconset" -o Resources/CitrusDrop.icns
