#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
"$(swift build -c release --show-bin-path)/CitrusDrop" --self-test
