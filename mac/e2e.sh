#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$HOME/Applications/MovaSwitch.app"
binary="$app/Contents/MacOS/MovaSwitch"
host_app="$HOME/Applications/MovaSwitchE2EHost.app"
host_contents="$host_app/Contents"
session="mova-e2e-$$-$(date +%s)"
pid=""

cleanup() {
	if [[ -n "$pid" ]] && /bin/kill -0 "$pid" 2>/dev/null; then
		/bin/kill "$pid" 2>/dev/null || true
	fi
	cua-driver call end_session "{\"session\":\"$session\"}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

[[ -x "$binary" ]] || { printf 'MovaSwitch is not installed\n' >&2; exit 2; }
[[ -f "$HOME/Library/Application Support/MovaSwitch/accessibility-granted" ]] || { printf 'MovaSwitch has no Accessibility permission yet\n' >&2; exit 2; }
/usr/sbin/ioreg -n Root -d1 -k IOConsoleUsers > "${TMPDIR:-/tmp}/mova-e2e-ioreg"
! grep -q '"CGSSessionScreenIsLocked"=Yes' "${TMPDIR:-/tmp}/mova-e2e-ioreg" || { printf 'the screen is locked\n' >&2; exit 2; }

# Posts real keyboard events from a LaunchServices-launched copy of the app, so they carry
# the same Accessibility grant and enter the session like hardware keys.
inject() {
	/usr/bin/open -W -n -a "$app" --args "$@"
}
/usr/bin/pgrep -x MovaSwitch >/dev/null || { printf 'MovaSwitch is not running\n' >&2; exit 2; }

rm -rf "$host_app"
mkdir -p "$host_contents/MacOS"
cp "$root/Resources/E2EHost-Info.plist" "$host_contents/Info.plist"
/usr/bin/xcrun swiftc -swift-version 5 -framework AppKit "$root/Tests/E2EHost.swift" -o "$host_contents/MacOS/MovaSwitchE2EHost"
/usr/bin/codesign --force --deep --sign - "$host_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$host_app"

call() {
	cua-driver call "$1" "$2"
}

json_value() {
	/usr/bin/python3 -c 'import json,sys; value=json.load(sys.stdin); print(eval(sys.argv[1], {}, {"x": value}))' "$1"
}

token_for() {
	/usr/bin/python3 -c 'import json,sys
data=json.load(sys.stdin)
wanted=sys.argv[1]
def walk(value):
    if isinstance(value, dict):
        if value.get("label") == wanted and value.get("element_token"):
            return value["element_token"]
        for child in value.values():
            found=walk(child)
            if found: return found
    elif isinstance(value, list):
        for child in value:
            found=walk(child)
            if found: return found
    return None
token=walk(data)
if not token: raise SystemExit("missing element: " + wanted)
print(token)' "$1"
}

assert_contains() {
	/usr/bin/python3 -c 'import json,sys
data=json.load(sys.stdin)
text=json.dumps(data, ensure_ascii=False)
needle=sys.argv[1]
if needle not in text: raise SystemExit("missing state: " + needle)' "$1"
}

snapshot() {
	call get_window_state "{\"pid\":$pid,\"window_id\":$window_id,\"include_screenshot\":false,\"session\":\"$session\",\"timeout_ms\":5000}"
}

click_label() {
	local label="$1"
	local before token after
	before="$(snapshot)"
	token="$(printf '%s' "$before" | token_for "$label")"
	call click "{\"pid\":$pid,\"element_token\":\"$token\",\"session\":\"$session\"}" >/dev/null
	after="$(snapshot)"
	printf '%s' "$after" >/dev/null
}

launch="$(call launch_app "{\"bundle_id\":\"com.liniman.MovaSwitchE2EHost\",\"creates_new_application_instance\":true,\"session\":\"$session\"}")"
pid="$(printf '%s' "$launch" | json_value 'x["pid"]')"
window_id="$(printf '%s' "$launch" | json_value 'x["windows"][0]["window_id"]')"

before_front="$(snapshot)"
printf '%s' "$before_front" >/dev/null
call bring_to_front "{\"pid\":$pid,\"window_id\":$window_id,\"session\":\"$session\"}" >/dev/null || /usr/bin/open "$host_app"
sleep 0.5
after_front="$(snapshot)"
printf '%s' "$after_front" | assert_contains "MovaSwitch E2E"

click_label "Clear normal"
"$binary" --test-layout us >/dev/null
inject --test-inject ghbdsn space
sleep 0.25
wrong_layout="$(snapshot)"
printf '%s' "$wrong_layout" | assert_contains "normal-value=привіт "
[[ "$("$binary" --test-current-layout)" == "layout=com.apple.keylayout.Ukrainian-PC" ]]

inject --test-option-tap
sleep 0.25
undone="$(snapshot)"
printf '%s' "$undone" | assert_contains "normal-value=ghbdsn "
[[ "$("$binary" --test-current-layout)" == "layout=com.apple.keylayout.US" ]]

click_label "Clear normal"
"$binary" --test-layout us >/dev/null
inject --test-inject hello space
sleep 0.2
correct_word="$(snapshot)"
printf '%s' "$correct_word" | assert_contains "normal-value=hello "
[[ "$("$binary" --test-current-layout)" == "layout=com.apple.keylayout.US" ]]

click_label "Clear normal"
"$binary" --test-layout us >/dev/null
inject --test-inject ghbdsn none
call hotkey "{\"pid\":$pid,\"window_id\":$window_id,\"keys\":[\"cmd\",\"a\"],\"delivery_mode\":\"foreground\",\"session\":\"$session\"}" >/dev/null
inject --test-option-tap
sleep 0.25
selection="$(snapshot)"
printf '%s' "$selection" | assert_contains "normal-value=привіт"
[[ "$("$binary" --test-current-layout)" == "layout=com.apple.keylayout.Ukrainian-PC" ]]

click_label "Clear secure"
secure_focused="$(snapshot)"
printf '%s' "$secure_focused" | assert_contains "Secure test field"
"$binary" --test-layout us >/dev/null
inject --test-inject ghbdsn space
sleep 0.2
secure_result="$(snapshot)"
printf '%s' "$secure_result" | assert_contains "secure-result=untouched"
[[ "$("$binary" --test-current-layout)" == "layout=com.apple.keylayout.US" ]]

before_quit="$(snapshot)"
printf '%s' "$before_quit" >/dev/null
call hotkey "{\"pid\":$pid,\"window_id\":$window_id,\"keys\":[\"cmd\",\"q\"],\"delivery_mode\":\"foreground\",\"session\":\"$session\"}" >/dev/null
for _ in 1 2 3 4 5; do
	if ! /bin/kill -0 "$pid" 2>/dev/null; then break; fi
	sleep 0.1
done
! /bin/kill -0 "$pid" 2>/dev/null
call end_session "{\"session\":\"$session\"}" >/dev/null
trap - EXIT

printf 'rewrite=passed\nlayout_switch=passed\nundo=passed\ncorrect_word=passed\nselection=passed\nsecure_input=passed\n'
