#!/bin/sh
# Installs a built MovaSwitch.app into ~/Applications under a KeepAlive LaunchAgent. Rerunnable.
# The one install path for install.sh, mac/install.sh and Homebrew; it ships inside the app bundle.
set -eu

source_app=${1:?usage: install-app.sh path/to/MovaSwitch.app}
here=$(cd "$(dirname "$0")" && pwd)
label=com.liniman.MovaSwitch
domain="gui/$(/usr/bin/id -u)"
app="$HOME/Applications/MovaSwitch.app"
incoming="$HOME/Applications/.MovaSwitch.app.installing"
agent="$HOME/Library/LaunchAgents/$label.plist"
log_dir="$HOME/Library/Logs/MovaSwitch"
marker="$HOME/Library/Application Support/MovaSwitch/accessibility-granted"

[ -d "$source_app/Contents" ] || { printf 'App bundle not found: %s\n' "$source_app" >&2; exit 2; }
/bin/mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$log_dir"
/bin/rm -rf "$incoming"
/usr/bin/ditto "$source_app" "$incoming"
/bin/bash "$here/sign.sh" "$incoming" >/dev/null
/usr/bin/codesign --verify --strict "$incoming"

/bin/launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
tries=0
while /bin/launchctl print "$domain/$label" >/dev/null 2>&1 && [ "$tries" -lt 50 ]; do
	tries=$((tries + 1))
	/bin/sleep 0.1
done
/bin/rm -rf "$app"
/bin/mv "$incoming" "$app"

/bin/cat > "$agent.installing" <<PLIST
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
if ! /bin/launchctl bootstrap "$domain" "$agent" 2>/dev/null; then
	/bin/sleep 1
	/bin/launchctl bootstrap "$domain" "$agent"
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
printf 'MovaSwitch %s is installed in ~/Applications and starts at login.\n' "$version"
if [ ! -f "$marker" ]; then
	(/usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' >/dev/null 2>&1 </dev/null &)
	printf 'Turn on MovaSwitch in System Settings > Privacy & Security > Accessibility.\n'
fi
