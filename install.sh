#!/bin/sh
# Installs or updates MovaSwitch from a GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/Liniman/mova-switch/main/install.sh | sh
# MOVA_VERSION=v1.2.3 pins a release. MOVA_LOCAL_ZIP=path/MovaSwitch-arm64.zip installs a local
# build instead; its checksum must sit next to it as path/MovaSwitch-arm64.zip.sha256.
set -eu

archive_name=MovaSwitch-arm64.zip
releases=https://github.com/Liniman/mova-switch/releases

fail() {
	printf 'MovaSwitch: %s\n' "$1" >&2
	exit 1
}

main() {
	[ "$(/usr/bin/uname -s)" = Darwin ] || fail 'needs macOS 13 or later on an Apple silicon Mac.'
	macos_version=$(/usr/bin/sw_vers -productVersion)
	macos_major=${macos_version%%.*}
	case "$macos_major" in
		'' | *[!0-9]*) fail "could not read the macOS version ($macos_version)." ;;
	esac
	[ "$macos_major" -ge 13 ] || fail "needs macOS 13 or later; this Mac runs $macos_version."
	[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ] \
		|| fail 'needs an Apple silicon Mac; Intel Macs are not supported yet.'

	work=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mova-switch.XXXXXX")
	trap '/bin/rm -rf "$work"' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	archive="$work/$archive_name"
	checksum="$archive.sha256"

	if [ -n "${MOVA_LOCAL_ZIP:-}" ]; then
		[ -f "$MOVA_LOCAL_ZIP" ] || fail "local archive not found: $MOVA_LOCAL_ZIP"
		[ -f "$MOVA_LOCAL_ZIP.sha256" ] || fail "local checksum not found: $MOVA_LOCAL_ZIP.sha256"
		/bin/cp "$MOVA_LOCAL_ZIP" "$archive"
		/bin/cp "$MOVA_LOCAL_ZIP.sha256" "$checksum"
	else
		if [ -n "${MOVA_VERSION:-}" ]; then
			case "$MOVA_VERSION" in
				v[0-9]*) ;;
				*) fail 'MOVA_VERSION must be a release tag such as v1.2.3.' ;;
			esac
			case "$MOVA_VERSION" in
				*[!A-Za-z0-9._-]*) fail 'MOVA_VERSION must be a release tag such as v1.2.3.' ;;
			esac
			base_url="$releases/download/$MOVA_VERSION"
		else
			base_url="$releases/latest/download"
		fi
		/usr/bin/curl -fsSL --proto '=https' --retry 3 -o "$archive" "$base_url/$archive_name" \
			|| fail "could not download $base_url/$archive_name"
		/usr/bin/curl -fsSL --proto '=https' --retry 3 -o "$checksum" "$base_url/$archive_name.sha256" \
			|| fail "could not download $base_url/$archive_name.sha256"
	fi

	expected=$(/usr/bin/awk 'NR == 1 { print tolower($1) }' "$checksum")
	actual=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{ print tolower($1) }')
	[ "${#expected}" -eq 64 ] || fail 'the release checksum file is malformed.'
	[ "$actual" = "$expected" ] || fail 'the download does not match its SHA-256 checksum.'

	/usr/bin/ditto -x -k "$archive" "$work/unpacked"
	app="$work/unpacked/MovaSwitch.app"
	[ -f "$app/Contents/Resources/install-app.sh" ] || fail 'the release has no install-app.sh.'
	/bin/sh "$app/Contents/Resources/install-app.sh" "$app" </dev/null
}

main "$@"
