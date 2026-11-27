#!/bin/bash
# End-to-end typing test: types real key events through a test build of ViKey and checks the text.
#
#   bash scripts/typing-test.sh [--delay MS] [--app BUNDLE_ID] [cases.tsv]
#
# Builds ViKey with -DTYPING_TEST (the test code is never in release builds), signs it with the
# "ViKey Code Signing" certificate so it shares the installed app's Accessibility grant, quits the
# installed ViKey, runs the cases, deletes the test build and starts the installed ViKey again.
#
# Default target: a window of its own. --app types into the focused text field of a running app
# instead (put the caret in an empty field first, e.g. a <textarea> in Chrome; Return in a chat app
# sends!). The field is read back with ⌘A ⌘C; the clipboard is restored afterwards.
# --delay is the pause between keys (default 8 ms); 0 is as fast as the system takes them.
# Don't touch the keyboard or mouse while it runs: a focus change aborts the run.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "✗ $*" >&2; exit 2; }

CASES=scripts/typing-cases.tsv
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --delay) ARGS+=(--delay "${2:?}"); shift 2 ;;
    --app) ARGS+=(--app "${2:?}"); shift 2 ;;
    -*) die "unknown option $1" ;;
    *) CASES="$1"; shift ;;
  esac
done
[[ -s "$CASES" ]] || die "no cases file $CASES"
CASES="$(cd "$(dirname "$CASES")" && pwd)/$(basename "$CASES")"

IDENTITY="$(security find-identity -p codesigning 2>/dev/null | grep -F '"ViKey Code Signing"' | awk '{ print $2; exit }' || true)"
[[ -n "$IDENTITY" ]] || die "needs the ViKey Code Signing certificate (scripts/make-signing-cert.sh): without it the test build would need its own Accessibility grant"

echo "▸ Build test variant"
SCRATCH=.build/typing-test
swift build -c release --product ViKey --scratch-path "$SCRATCH" -Xswiftc -DTYPING_TEST >/dev/null
BIN="$(swift build -c release --product ViKey --scratch-path "$SCRATCH" -Xswiftc -DTYPING_TEST --show-bin-path)/ViKey"

APP=build/ViKeyTest.app
OUT="$(mktemp -t vikey-typing)"
WAS_RUNNING=false
pgrep -x ViKey >/dev/null && WAS_RUNNING=true
cleanup() {
  pkill -f "$APP/Contents/MacOS/ViKey" 2>/dev/null || true
  rm -rf "$APP"
  if $WAS_RUNNING && ! pgrep -x ViKey >/dev/null; then open /Applications/ViKey.app; fi
}
trap cleanup EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ViKey"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# The binary links Sparkle (the updater itself never starts in the test build).
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework" 2>/dev/null
codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null

echo "▸ Run $CASES (hands off the keyboard and mouse)"
pkill -x ViKey 2>/dev/null || true
sleep 0.5
open -W -n "$APP" --args --typing-test "$CASES" --out "$OUT" "${ARGS[@]+"${ARGS[@]}"}"

[[ -s "$OUT" ]] || die "the test build wrote no results"
grep -v "^PASS" "$OUT" || true
SUMMARY="$(tail -1 "$OUT")"
rm -f "$OUT"
[[ "$SUMMARY" == *", 0 failure(s)" ]] && { echo "✓ ${SUMMARY#\# }"; exit 0; }
echo "✗ ${SUMMARY#\# }"
exit 1
