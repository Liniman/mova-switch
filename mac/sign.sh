#!/bin/bash
# Signs the app with a local self-signed identity so its designated requirement, and with it
# the user's Accessibility grant, stays the same across rebuilds. Creates the identity once.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="${1:-$root/.build/MovaSwitch.app}"
name="MovaSwitch Local Signing"
dir="$HOME/Library/Application Support/MovaSwitch/signing"
keychain="$dir/mova-signing.keychain-db"
password_file="$dir/keychain-password"

[[ -d "$app" ]] || { printf 'App bundle not found: %s\n' "$app" >&2; exit 2; }
mkdir -p "$dir"
chmod 700 "$dir"
if [[ ! -f "$password_file" ]]; then
	(umask 077; /usr/bin/openssl rand -hex 24 > "$password_file")
fi
password="$(cat "$password_file")"

if [[ ! -f "$keychain" ]]; then
	/usr/bin/security create-keychain -p "$password" "$keychain"
	/usr/bin/security set-keychain-settings "$keychain"
fi
/usr/bin/security unlock-keychain -p "$password" "$keychain"

if ! /usr/bin/security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
	work="$(mktemp -d)"
	trap 'rm -rf "$work"' EXIT
	cat > "$work/openssl.cnf" <<CONFIG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG
	/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/openssl.cnf" \
		-keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
	/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
		-out "$work/identity.p12" -passout pass:transfer
	/usr/bin/security import "$work/identity.p12" -k "$keychain" -P transfer -T /usr/bin/codesign
	/usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
fi

search=()
while IFS= read -r entry; do
	entry="${entry#"${entry%%[![:space:]]*}"}"
	entry="${entry#\"}"
	search+=("${entry%\"}")
done < <(/usr/bin/security list-keychains -d user)
if [[ " ${search[*]} " != *"$keychain"* ]]; then
	/usr/bin/security list-keychains -d user -s "${search[@]}" "$keychain"
fi

/usr/bin/codesign --force --sign "$name" --keychain "$keychain" --identifier com.liniman.MovaSwitch "$app"
/usr/bin/codesign --verify --strict "$app"
/usr/bin/codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => /requirement=/p'
