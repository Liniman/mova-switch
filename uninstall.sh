#!/bin/sh
# Removes MovaSwitch and its LaunchAgent. --purge also removes settings, the signing identity
# and the Accessibility grant:
#   curl -fsSL https://raw.githubusercontent.com/Liniman/mova-switch/main/uninstall.sh | sh -s -- --purge
set -eu

main() {
	label=com.liniman.MovaSwitch
	domain="gui/$(/usr/bin/id -u)"
	support="$HOME/Library/Application Support/MovaSwitch"

	/bin/launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
	/bin/launchctl bootout "$domain/$label.grant-watcher" >/dev/null 2>&1 || true
	/bin/rm -f "$HOME/Library/LaunchAgents/$label.plist" "$HOME/Library/LaunchAgents/$label.grant-watcher.plist"
	/bin/rm -rf "$HOME/Applications/MovaSwitch.app" "$HOME/Applications/.MovaSwitch.app.installing"

	if [ "${1:-}" = --purge ]; then
		if [ -f "$support/signing/mova-signing.keychain-db" ]; then
			/usr/bin/security delete-keychain "$support/signing/mova-signing.keychain-db" >/dev/null 2>&1 || true
		fi
		/usr/bin/defaults delete "$label" >/dev/null 2>&1 || true
		/usr/bin/tccutil reset Accessibility "$label" >/dev/null 2>&1 || true
		/usr/bin/tccutil reset ListenEvent "$label" >/dev/null 2>&1 || true
		/bin/rm -rf "$support" "$HOME/Library/Logs/MovaSwitch"
	fi

	printf 'MovaSwitch is uninstalled.\n'
}

main "$@"
