#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/citrusdrop-source.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/CitrusDrop"
cp -R Package.swift Sources Resources scripts tests docs .github .gitignore README.md README.en.md README.ru.md install.sh LICENSE CHANGELOG.md SECURITY.md CONTRIBUTING.md PRODUCT.md DESIGN.md "$STAGE/CitrusDrop/"
find "$STAGE/CitrusDrop" -type f \( -name .DS_Store -o -name '._*' -o -name '*.pyc' \) -delete
find "$STAGE/CitrusDrop" -type d -name __pycache__ -empty -delete
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$STAGE/CitrusDrop" dist/CitrusDrop-source.zip
(cd dist && /usr/bin/shasum -a 256 CitrusDrop-macOS.zip CitrusDrop.dmg CitrusDrop-source.zip > SHA256SUMS)
printf 'Source archive: %s/dist/CitrusDrop-source.zip\n' "$PWD"
