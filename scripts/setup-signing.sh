#!/bin/bash
# Creates a self-signed code-signing identity in a project-local keychain (.signing/).
# Signing every build with the same identity lets macOS remember Clacky's
# Input Monitoring permission across rebuilds. Nothing is added to your login keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR=.signing
KEYCHAIN="$PWD/$DIR/clacky.keychain-db"
NAME="Clacky Local Signing"
[ -f "$KEYCHAIN" ] && { echo "Signing keychain already exists."; exit 0; }

mkdir -p "$DIR"
PASS=$(openssl rand -hex 16)
echo "$PASS" > "$DIR/password"
chmod 600 "$DIR/password"

TMP=$(mktemp -d)
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -passout pass:"$PASS" -out "$TMP/id.p12" 2>/dev/null

security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN" # no auto-lock timeout
security unlock-keychain -p "$PASS" "$KEYCHAIN"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$KEYCHAIN" >/dev/null
rm -rf "$TMP"
echo "Created signing identity \"$NAME\" in $DIR/"
