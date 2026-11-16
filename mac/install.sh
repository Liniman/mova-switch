#!/bin/bash
# Builds, signs and installs MovaSwitch under a KeepAlive LaunchAgent. Rerunnable.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
label="com.liniman.MovaSwitch"
domain="gui/$(id -u)"
app="$HOME/Applications/MovaSwitch.app"
incoming="$HOME/Applications/.MovaSwitch.app.installing"
agent="$HOME/Library/LaunchAgents/$label.plist"
log_dir="$HOME/Library/Logs/MovaSwitch"

"$root/build.sh"

/bin/launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$log_dir"
/bin/rm -rf "$incoming"
/usr/bin/ditto "$root/.build/MovaSwitch.app" "$incoming"
/bin/rm -rf "$app"
/bin/mv "$incoming" "$app"

cat > "$agent.installing" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>
		<string>$app/Contents/MacOS/MovaSwitch</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ThrottleInterval</key>
	<integer>5</integer>
	<key>StandardOutPath</key>
	<string>$log_dir/stdout.log</string>
	<key>StandardErrorPath</key>
	<string>$log_dir/stderr.log</string>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$agent.installing" >/dev/null
/bin/mv "$agent.installing" "$agent"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
/bin/launchctl bootstrap "$domain" "$agent"
/bin/launchctl kickstart -k "$domain/$label"
sleep 1

if [[ ! -f "$HOME/Library/Application Support/MovaSwitch/accessibility-granted" ]]; then
	/usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
	printf 'Turn on MovaSwitch in Privacy & Security > Accessibility.\n'
fi
"$root/check-live.sh"
