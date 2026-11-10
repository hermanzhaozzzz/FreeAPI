#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
./scripts/build.sh "${1:-universal}"
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent build/FreeAPI.app dist/FreeAPI-macOS.zip
shasum -a 256 dist/FreeAPI-macOS.zip > dist/SHA256SUMS
echo "Packaged: $project_root/dist/FreeAPI-macOS.zip"
