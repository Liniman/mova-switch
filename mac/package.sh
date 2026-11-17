#!/bin/bash
# Builds the Apple silicon release zip and its SHA-256 file into the given directory.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
output="${1:-$root/.build/release}"
archive_name="MovaSwitch-arm64.zip"
app="$root/.build/MovaSwitch.app"

[[ "$(/usr/bin/uname -m)" == arm64 ]] || { printf 'Release packaging requires an Apple silicon Mac.\n' >&2; exit 2; }
"$root/build.sh" --skip-tests >/dev/null
/usr/bin/lipo "$app/Contents/MacOS/MovaSwitch" -verify_arch arm64

/bin/rm -rf "$output"
/bin/mkdir -p "$output"
/usr/bin/ditto -c -k --keepParent "$app" "$output/$archive_name"
(cd "$output" && /usr/bin/shasum -a 256 "$archive_name" > "$archive_name.sha256")
printf '%s\n' "$output/$archive_name"
