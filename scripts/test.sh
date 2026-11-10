#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p build/tests
xcrun swiftc -swift-version 5 Sources/Models.swift Tests/main.swift -o build/tests/models
build/tests/models
python3 Tests/guardian_test.py
plutil -lint Resources/Info.plist
sh -n Resources/guardian.sh
bash -n scripts/build.sh scripts/package.sh scripts/test.sh
