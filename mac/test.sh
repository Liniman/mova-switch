#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
build="$root/.build"
mkdir -p "$build"
engine="$("$root/build-engine.sh")"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <("$root/swift-sources.sh")

/usr/bin/xcrun swiftc \
	-swift-version 5 \
	-O \
	-import-objc-header "$root/../engine/include/mova_engine.h" \
	-framework ApplicationServices \
	-framework Carbon \
	"${sources[@]}" \
	"$root/Tests/ShellBehaviourTests.swift" \
	"$engine" \
	-o "$build/ShellBehaviourTests"

# The tests read the U.S. and Ukrainian – PC input sources, which a CI runner does not have.
[[ "${1:-}" == "--compile-only" ]] || "$build/ShellBehaviourTests"
