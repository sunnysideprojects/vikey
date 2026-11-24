#!/bin/bash
# Regenerate Resources/AppIcon.icns (and docs/vikey-icon.png for the README) from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swift scripts/make-icon.swift "$TMP/icon-1024.png" "${1:-Vi}"
SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
mkdir -p docs
sips -z 256 256 "$TMP/icon-1024.png" --out docs/vikey-icon.png >/dev/null
echo "✓ Resources/AppIcon.icns, docs/vikey-icon.png"
