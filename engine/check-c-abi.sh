#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
build_dir="$repo_root/target/release"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

cargo_command=${CARGO:-cargo}
if ! command -v "$cargo_command" >/dev/null 2>&1; then
	cargo_command=${HOME}/.cargo/bin/cargo
fi

"$cargo_command" build --release -p engine --lib
cc -std=c11 -Wall -Wextra -Werror \
	-I"$script_dir/include" \
	"$script_dir/tests/ffi_smoke.c" \
	-L"$build_dir" \
	-Wl,-rpath,"$build_dir" \
	-lengine \
	-o "$temp_dir/ffi-smoke"
"$temp_dir/ffi-smoke"
