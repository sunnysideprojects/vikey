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
codesign --force --sign - "$APP"
echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ViKey 2>/dev/null || true
  rm -rf /Applications/ViKey.app
  cp -R "$APP" /Applications/
  # Ad-hoc signature changes on every build, so an old Accessibility grant no longer matches.
  tccutil reset Accessibility dev.sunnysideprojects.vikey >/dev/null 2>&1 || true
  open /Applications/ViKey.app
  echo "✓ Đã cài vào /Applications và mở ViKey — cấp quyền Accessibility khi được hỏi."
fi
