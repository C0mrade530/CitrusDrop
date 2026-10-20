#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh "${1:-}"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr -c -k --keepParent dist/CitrusDrop.app dist/CitrusDrop-macOS.zip
(cd dist && /usr/bin/shasum -a 256 CitrusDrop-macOS.zip > SHA256SUMS)
printf 'Packaged: %s/dist/CitrusDrop-macOS.zip\n' "$PWD"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/citrusdrop-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/CitrusDrop.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname CitrusDrop -srcfolder "$STAGE" -ov -format UDZO dist/CitrusDrop.dmg
(cd dist && /usr/bin/shasum -a 256 CitrusDrop-macOS.zip CitrusDrop.dmg > SHA256SUMS)
