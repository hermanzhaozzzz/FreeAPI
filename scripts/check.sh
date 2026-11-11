#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

echo "== shellcheck =="
shellcheck scripts/*.sh Resources/guardian.sh

echo "== plist / json =="
plutil -lint Resources/Info.plist
python3 -m json.tool config.example.json >/dev/null

echo "== swift typecheck =="
xcrun swiftc -swift-version 5 -typecheck Sources/*.swift

echo "All checks passed."
