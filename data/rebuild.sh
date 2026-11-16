#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
raw_dir="$script_dir/raw"
frequency_dir="$raw_dir/FrequencyWords"
dictionaries_dir="$raw_dir/libreoffice-dictionaries"
frequency_revision=525f9b560de45753a5ea01069454e72e9aa541c6
dictionaries_revision=c0865a85eb67dc377f2cf8e8fe2c4fa9e53f0dcb

mkdir -p "$raw_dir"

fetch_sparse() {
	local url=$1
	local revision=$2
	local destination=$3
	shift 3

	if [[ ! -d "$destination/.git" ]]; then
		git clone --filter=blob:none --no-checkout "$url" "$destination"
	fi

	if [[ $(git -C "$destination" remote get-url origin) != "$url" ]]; then
		printf 'unexpected origin for %s\n' "$destination" >&2
		exit 1
	fi

	git -C "$destination" sparse-checkout init --cone
	git -C "$destination" sparse-checkout set "$@"
	git -C "$destination" fetch --depth 1 origin "$revision"
	git -C "$destination" checkout --detach FETCH_HEAD
}

fetch_sparse \
	https://github.com/hermitdave/FrequencyWords.git \
	"$frequency_revision" \
	"$frequency_dir" \
	content/2018/en content/2018/uk

fetch_sparse \
	https://github.com/LibreOffice/dictionaries.git \
	"$dictionaries_revision" \
	"$dictionaries_dir" \
	en uk_UA

cargo_command=${CARGO:-cargo}
if ! command -v "$cargo_command" >/dev/null 2>&1; then
	cargo_command=${HOME}/.cargo/bin/cargo
fi

"$cargo_command" run --release -p engine --bin build-data -- \
	"$frequency_dir" \
	"$dictionaries_dir" \
	"$repo_root/data/model.tsv" \
	"$repo_root/data/model-shipped.tsv" \
	"$repo_root/data/eval/heldout.tsv"

sha256sum "$repo_root/data/model.tsv" "$repo_root/data/model-shipped.tsv" "$repo_root/data/eval/heldout.tsv"
