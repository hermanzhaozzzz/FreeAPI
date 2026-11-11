#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

architecture="${1:-universal}"
./scripts/build.sh "$architecture"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
dmg_name="FreeAPI-${version}.dmg"
dmg_path="$project_root/dist/$dmg_name"
rw_dmg="$project_root/build/FreeAPI-rw.dmg"
compressed_dmg="$project_root/build/FreeAPI-compressed-$$.dmg"
staging="$(mktemp -d "$project_root/build/dmg-staging.XXXXXX")"

if [[ ! -f Resources/dmg-background.png ]]; then
    xcrun swift scripts/make-dmg-background.swift >/dev/null
fi

mkdir -p "$staging/.background" "$project_root/dist"
ditto build/FreeAPI.app "$staging/FreeAPI.app"
ln -s /Applications "$staging/Applications"
cp Resources/dmg-background.png "$staging/.background/background.png"
cp Resources/AppIcon.icns "$staging/.VolumeIcon.icns"

hdiutil create -volname "FreeAPI" -srcfolder "$staging" -ov -format UDRW -fs HFS+ "$rw_dmg" >/dev/null

attach_output=$(hdiutil attach "$rw_dmg" -noautoopen)
mountpoint=$(printf '%s\n' "$attach_output" | awk -F '\t' 'NF {print $NF}' | tail -1)
if [[ -z "$mountpoint" || ! -d "$mountpoint" ]]; then
    echo "无法挂载临时 DMG：$attach_output" >&2
    exit 1
fi
volume_name=$(basename "$mountpoint")

SetFile -a V "$mountpoint/.background" 2>/dev/null || true

osascript - "$volume_name" >/dev/null 2>&1 <<'APPLESCRIPT' &
on run argv
    set diskName to item 1 of argv
    tell application "Finder"
        tell disk diskName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {100, 100, 760, 542}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 128
            set background picture of viewOptions to file ".background:background.png"
            set position of item "FreeAPI.app" of container window to {160, 210}
            set position of item "Applications" of container window to {500, 210}
            close
            open
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
APPLESCRIPT

layout_pid=$!
( sleep 12; kill "$layout_pid" 2>/dev/null ) &
watchdog=$!
disown "$watchdog" 2>/dev/null || true
wait "$layout_pid" 2>/dev/null || true
kill "$watchdog" 2>/dev/null || true

# Finder drops .VolumeIcon.icns while applying the view layout, so set it afterwards.
cp Resources/AppIcon.icns "$mountpoint/.VolumeIcon.icns"
SetFile -a C "$mountpoint" 2>/dev/null || true
sync

for _ in 1 2 3; do
    if hdiutil detach "$mountpoint" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
hdiutil detach "$mountpoint" -force >/dev/null 2>&1 || true
if hdiutil info | grep -F "$mountpoint" >/dev/null 2>&1; then
    hdiutil detach "$mountpoint" -force >/dev/null 2>&1 || true
    sleep 2
fi

converted=0
for _ in 1 2 3 4 5; do
    if hdiutil convert "$rw_dmg" -format UDZO -imagekey zlib-level=9 -o "$compressed_dmg" >/dev/null 2>&1; then
        converted=1
        break
    fi
    sleep 2
done
if [[ "$converted" -ne 1 ]]; then
    echo "hdiutil convert failed" >&2
    exit 1
fi
mv -f "$compressed_dmg" "$dmg_path"
(cd "$project_root/dist" && shasum -a 256 "$dmg_name" > SHA256SUMS)

echo "Packaged: $dmg_path"
