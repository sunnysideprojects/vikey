#!/bin/bash
# Release ViKey on GitHub.
#
#   scripts/release.sh X.Y.Z changes.md            -> bump, build, commit, push, gh release
#   scripts/release.sh X.Y.Z changes.md --dry-run  -> build the zip and notes only; leaves git untouched
#
# changes.md holds the release-specific part of the notes, in Vietnamese: a one-line summary, then
# "## Thay đổi" with bullets. The script appends the standard install steps, the zip's SHA-256 and
# the Sunny Side Projects endorsement line. The full notes are written to dist/notes-X.Y.Z.md.
#
# Order: everything that can fail (checks, build, zip) runs before anything is committed or pushed.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "✗ $*" >&2; exit 1; }

VERSION="${1:-}"
CHANGES="${2:-}"
DRY_RUN=false
[[ "${3:-}" == "--dry-run" ]] && DRY_RUN=true
[[ $# -eq 2 || ( $# -eq 3 && $DRY_RUN == true ) ]] || die "usage: scripts/release.sh X.Y.Z changes.md [--dry-run]"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3 (got '${VERSION}')"
[[ -s "$CHANGES" ]] || die "changes file '${CHANGES}' is missing or empty"

TAG="v$VERSION"
PLIST=Resources/Info.plist
ZIP="dist/ViKey-$VERSION.zip"
NOTES="dist/notes-$VERSION.md"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }

# MARK: Checks
echo "▸ Checks"
command -v gh >/dev/null || die "gh is not installed"
$DRY_RUN || gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
[[ "$(git branch --show-current)" == main ]] || die "not on main"
[[ -z "$(git status --porcelain)" ]] || die "working tree is not clean"
git fetch -q origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main is not in sync with origin/main (pull or push first)"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
$DRY_RUN || ! gh release view "$TAG" >/dev/null 2>&1 || die "GitHub release $TAG already exists"

CURRENT="$(pb 'Print :CFBundleShortVersionString')"
BUILD="$(pb 'Print :CFBundleVersion')"
[[ "$VERSION" != "$CURRENT" && "$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -V | tail -1)" == "$VERSION" ]] \
  || die "$VERSION is not newer than the current $CURRENT"
NEW_BUILD=$((BUILD + 1))
echo "  $CURRENT (build $BUILD) -> $VERSION (build $NEW_BUILD)"

# MARK: Bump and build
# Until the bump is committed, any exit (failure, die, Ctrl-C, dry run) puts Info.plist back.
BUMPED=true
cleanup() { if $BUMPED; then git checkout -q -- "$PLIST"; fi; }
trap cleanup EXIT
pb "Set :CFBundleShortVersionString $VERSION"
pb "Set :CFBundleVersion $NEW_BUILD"

echo "▸ Build"
bash build.sh
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/ViKey.app/Contents/Info.plist)" == "$VERSION" ]] \
  || die "built app does not report version $VERSION"
lipo build/ViKey.app/Contents/MacOS/ViKey -verify_arch arm64 x86_64
codesign --verify --strict build/ViKey.app

echo "▸ Zip"
mkdir -p dist
rm -f "$ZIP"
ditto -c -k --keepParent build/ViKey.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "  $ZIP  $SHA"

# MARK: Notes
{
  cat "$CHANGES"
  echo
  cat <<EOF
## Cài đặt
1. Tải \`ViKey-$VERSION.zip\`, giải nén, kéo \`ViKey.app\` vào **Applications** (thay bản cũ nếu có).
2. App chỉ được ký ad-hoc (chưa notarize) nên macOS sẽ chặn lần đầu. Mở bằng cách chuột phải → **Open**, hoặc chạy:
   \`\`\`bash
   xattr -dr com.apple.quarantine /Applications/ViKey.app
   \`\`\`
3. Cấp quyền **Accessibility** khi được hỏi (System Settings → Privacy & Security → Accessibility). Nếu nâng cấp từ bản cũ, chữ ký app đã đổi nên cần xoá ViKey khỏi danh sách Accessibility rồi bật lại.
4. Gỡ bộ gõ "Vietnamese" của macOS, chỉ giữ **ABC**.

Universal: Apple Silicon và Intel.

SHA-256 \`ViKey-$VERSION.zip\`: \`$SHA\`

---

<img src="https://cdn.jsdelivr.net/gh/sunnysideprojects/brand@main/logos/svg/ssp-mark.svg" width="20"> ViKey · a [Sunny Side Project](https://github.com/sunnysideprojects)
EOF
} > "$NOTES"
echo "  $NOTES"

if $DRY_RUN; then
  echo "✓ Dry run: $ZIP and $NOTES are ready; Info.plist restored, nothing committed or pushed."
  exit 0
fi

# MARK: Publish
echo "▸ Commit and push"
git add "$PLIST"
git commit -q -m "Bump version to $VERSION"
BUMPED=false  # committed now: keep it
git push -q origin main
COMMIT="$(git rev-parse HEAD)"

echo "▸ GitHub release"
gh release create "$TAG" "$ZIP" --target "$COMMIT" --title "ViKey $VERSION" --notes-file "$NOTES"
git fetch -q origin --tags
[[ "$(git rev-parse "$TAG^{commit}")" == "$COMMIT" ]] || die "tag $TAG does not point at $COMMIT"
LATEST="$(gh api "repos/{owner}/{repo}/releases/latest" -q .tag_name)"
[[ "$LATEST" == "$TAG" ]] || echo "⚠️  GitHub's latest release is $LATEST, not $TAG"
echo "✓ Released $TAG: $(gh release view "$TAG" --json url -q .url)"
