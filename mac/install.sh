#!/bin/bash
# Builds, signs and installs MovaSwitch from this checkout. Rerunnable.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
"$root/build.sh"
"$root/install-app.sh" "$root/.build/MovaSwitch.app"
"$root/check-live.sh"
