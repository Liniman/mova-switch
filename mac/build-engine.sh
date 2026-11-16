#!/bin/bash
# Builds the Rust engine as a static library and prints its path.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cargo="$(command -v cargo || true)"
[[ -n "$cargo" ]] || cargo="$HOME/.cargo/bin/cargo"
[[ -x "$cargo" ]] || { printf 'cargo not found; install rustup for this user\n' >&2; exit 2; }

(cd "$repo" && "$cargo" build --quiet --release -p engine --lib) >&2
printf '%s\n' "$repo/target/release/libengine.a"
