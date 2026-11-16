#!/bin/bash
# The app sources shared by the app build and the behaviour tests, minus the entry point.
root="$(cd "$(dirname "$0")" && pwd)"
for name in Domain PreferenceStore KeyboardLayoutTranslator AXSelectionConverter BuiltinDecisionCore RustDecisionCore EventTapController TestCommand; do
	printf '%s\n' "$root/Sources/MovaSwitch/$name.swift"
done
