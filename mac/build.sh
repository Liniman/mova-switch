#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/.build/MovaSwitch.app"
contents="$app/Contents"

"$root/test.sh"
engine="$("$root/build-engine.sh")"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <("$root/swift-sources.sh")

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$root/Resources/Info.plist" "$contents/Info.plist"
/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null

/usr/bin/xcrun swiftc \
	-swift-version 5 \
	-O \
	-import-objc-header "$root/../engine/include/mova_engine.h" \
	-framework AppKit \
	-framework ApplicationServices \
	-framework Carbon \
	"${sources[@]}" \
	"$root/Sources/MovaSwitch/AppDelegate.swift" \
	"$root/Sources/MovaSwitch/main.swift" \
	"$engine" \
	-o "$contents/MacOS/MovaSwitch"

"$root/sign.sh" "$app"
printf '%s\n' "$app"
