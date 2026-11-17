#!/bin/sh
set -eu

exec /bin/sh "$(cd "$(dirname "$0")/.." && pwd)/uninstall.sh" "$@"
