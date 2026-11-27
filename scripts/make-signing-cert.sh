#!/bin/bash
# One-time setup: create ViKey's self-signed code signing certificate in the login keychain.
#
#   bash scripts/make-signing-cert.sh
#
# Why: an ad-hoc signature changes on every build, so macOS treats each build as a new app and the
# Accessibility (TCC) grant stops matching. Signed with the same certificate every time, the app's
# designated requirement stays `identifier "dev.sunnysideprojects.vikey" and certificate root = H"…"`,
# and the grant survives rebuilds and updates. This does not help with Gatekeeper (that needs a paid
# Developer ID + notarization).
#
# The certificate is not trusted by the system (find-identity shows CSSMERR_TP_NOT_TRUSTED); codesign
# still signs with it when given its SHA-1, which is what build.sh does. Nothing here changes trust
# settings or the keychain search list.
#
# Keep a backup: Keychain Access → login → My Certificates → "ViKey Code Signing" → Export (.p12).
# If the private key is lost, a new certificate means every user re-grants Accessibility once, and the
# pinned hash in scripts/release.sh has to change.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="ViKey Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl  # LibreSSL: its PKCS#12 output is readable by `security import`

die() { echo "✗ $*" >&2; exit 1; }

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
  security find-identity -p codesigning "$KEYCHAIN" | grep "\"$NAME\""
  die "\"$NAME\" already exists in the login keychain; nothing to do"
fi

umask 077
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
O = Sunny Side Projects
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "▸ Create key and certificate (RSA 3072, 20 years)"
"$OPENSSL" req -x509 -newkey rsa:3072 -nodes -sha256 -days 7300 \
  -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout "pass:$PASS"

echo "▸ Import into the login keychain (codesign allowed to use the key)"
security import "$TMP/id.p12" -k "$KEYCHAIN" -f pkcs12 -P "$PASS" -T /usr/bin/codesign >/dev/null

SHA1="$(security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\"" | awk '{ print $2; exit }')"
[[ -n "$SHA1" ]] || die "imported, but codesign cannot see the identity"
echo "✓ \"$NAME\"  SHA-1 $SHA1"
echo "  Pin it in scripts/release.sh (SIGNING_CERT_SHA1) and export a .p12 backup from Keychain Access."
echo "  The first build may ask to let codesign use the key: enter your login password, Always Allow."
