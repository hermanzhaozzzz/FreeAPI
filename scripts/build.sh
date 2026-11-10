#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
architecture="${1:-universal}"
case "$architecture" in
  universal) architectures=(x86_64 arm64) ;;
  x86_64|arm64) architectures=("$architecture") ;;
  *) echo "Usage: $0 [universal|x86_64|arm64]" >&2; exit 2 ;;
esac
app="build/FreeAPI.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/bin
for arch in "${architectures[@]}"; do
  xcrun swiftc -swift-version 5 -O -target "${arch}-apple-macos15.0" \
    Sources/Configuration.swift Sources/main.swift -o "build/bin/FreeAPI-$arch"
done
if [[ "$architecture" == universal ]]; then
  xcrun lipo -create build/bin/FreeAPI-x86_64 build/bin/FreeAPI-arm64 -output "$app/Contents/MacOS/FreeAPI"
else
  cp "build/bin/FreeAPI-$architecture" "$app/Contents/MacOS/FreeAPI"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/guardian.sh Resources/AppIcon.icns "$app/Contents/Resources/"
chmod +x "$app/Contents/MacOS/FreeAPI" "$app/Contents/Resources/guardian.sh"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "Built: $project_root/$app ($architecture; ad-hoc signed)"
