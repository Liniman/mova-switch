#!/bin/bash
set -euo pipefail

label="com.liniman.MovaSwitch"
uid="$(id -u)"
app="$HOME/Applications/MovaSwitch.app"
agent="$HOME/Library/LaunchAgents/$label.plist"

/bin/launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
/bin/launchctl bootout "gui/$uid/$label.grant-watcher" >/dev/null 2>&1 || true
/bin/rm -f "$HOME/Library/LaunchAgents/$label.grant-watcher.plist"
/bin/rm -f "$agent"
/bin/rm -rf "$app"

if [[ "${1:-}" == "--purge" ]]; then
	/usr/bin/defaults delete "$label" >/dev/null 2>&1 || true
	/usr/bin/tccutil reset Accessibility "$label" >/dev/null 2>&1 || true
	/usr/bin/tccutil reset ListenEvent "$label" >/dev/null 2>&1 || true
	/bin/rm -rf "$HOME/Library/Application Support/MovaSwitch"
fi

printf 'MovaSwitch uninstalled\n'
