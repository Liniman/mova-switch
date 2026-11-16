#!/bin/bash
# Reports the installed app, its signature, the LaunchAgent and the permission state.
set -euo pipefail

app="$HOME/Applications/MovaSwitch.app"
label="com.liniman.MovaSwitch"
domain="gui/$(id -u)"

if [[ -d "$app" ]]; then
	/usr/bin/codesign --verify --strict "$app"
	printf 'app=installed signature=valid\n'
	/usr/bin/codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => /requirement=/p'
else
	printf 'app=absent\n'
fi

if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
	printf 'launch_agent=loaded arguments=%s\n' "$(/bin/launchctl print "$domain/$label" | awk '/arguments = \{/{f=1;next} /\}/{f=0} f' | wc -l | tr -d ' ')"
else
	printf 'launch_agent=absent\n'
fi

pid="$(/usr/bin/pgrep -x MovaSwitch || true)"
printf 'process=%s\n' "${pid:-absent}"

if [[ -f "$HOME/Library/Application Support/MovaSwitch/accessibility-granted" ]]; then
	printf 'accessibility=granted event_tap=running\n'
else
	printf 'accessibility=missing event_tap=not-running\n'
fi

