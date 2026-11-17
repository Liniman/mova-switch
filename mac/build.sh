#!/bin/bash
# Builds an ad-hoc signed MovaSwitch.app. install-app.sh re-signs it with the local identity.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/.build/MovaSwitch.app"
contents="$app/Contents"

case "${1:-}" in
	"") "$root/test.sh" ;;
	--skip-tests) ;;
	*) printf 'Usage: %s [--skip-tests]\n' "$0" >&2; exit 2 ;;
esac
engine="$("$root/build-engine.sh")"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <("$root/swift-sources.sh")

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$root/Resources/Info.plist" "$contents/Info.plist"
cp "$root/install-app.sh" "$root/sign.sh" "$contents/Resources/"
chmod 755 "$contents/Resources/install-app.sh" "$contents/Resources/sign.sh"
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

/usr/bin/codesign --force --sign - --identifier com.liniman.MovaSwitch "$app"
/usr/bin/codesign --verify --strict "$app"
printf '%s\n' "$app"
