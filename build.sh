#!/bin/bash
# Build ViKey.app (Apple Silicon + Intel). Needs Xcode Command Line Tools: xcode-select --install
#   ./build.sh            -> build/ViKey.app
#   ./build.sh --install  -> also copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Self-test engine"
swift run -c release ViKeySelfTest

echo "▸ Build"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release --product ViKey "${ARCHS[@]}"
BIN="$(swift build -c release --product ViKey "${ARCHS[@]}" --show-bin-path)/ViKey"

APP="build/ViKey.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ViKey"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/ssp-app-icon.png Resources/BricolageGrotesque-Variable.ttf Resources/OFL-BricolageGrotesque.txt "$APP/Contents/Resources/"
# Sign with ViKey's own certificate (scripts/make-signing-cert.sh) so the Accessibility grant survives
# rebuilds and updates. Without it (CI, other Macs) fall back to ad-hoc, which changes every build.
# VIKEY_SIGN_IDENTITY overrides the identity (its SHA-1; "-" forces ad-hoc).
IDENTITY="${VIKEY_SIGN_IDENTITY:-$(security find-identity -p codesigning 2>/dev/null | grep -F '"ViKey Code Signing"' | awk '{ print $2; exit }' || true)}"
codesign --force --sign "${IDENTITY:--}" "$APP"
if [[ "${IDENTITY:--}" == "-" ]]; then
  echo "✓ $APP (ad-hoc signature: Accessibility must be granted again after every build)"
else
  echo "✓ $APP (signed with $IDENTITY)"
fi

if [[ "${1:-}" == "--install" ]]; then
  requirement() { codesign -d -r - "$1" 2>/dev/null | sed -n 's/^designated => //p'; }
  OLD_REQ="$(requirement /Applications/ViKey.app || true)"
  NEW_REQ="$(requirement "$APP")"
  pkill -x ViKey 2>/dev/null || true
  rm -rf /Applications/ViKey.app
  cp -R "$APP" /Applications/
  # The Accessibility grant is tied to the designated requirement. Same certificate -> it still
  # matches; ad-hoc (a new cdhash every build) or a different certificate -> stale, so reset it
  # and let macOS ask again.
  if [[ -n "$OLD_REQ" && "$OLD_REQ" == "$NEW_REQ" && "$NEW_REQ" != *cdhash* ]]; then
    open /Applications/ViKey.app
    echo "✓ Đã cài vào /Applications và mở ViKey (cùng chữ ký, giữ quyền Accessibility)."
  else
    tccutil reset Accessibility dev.sunnysideprojects.vikey >/dev/null 2>&1 || true
    open /Applications/ViKey.app
    echo "✓ Đã cài vào /Applications và mở ViKey — chữ ký đã đổi, cấp lại quyền Accessibility khi được hỏi."
  fi
fi
