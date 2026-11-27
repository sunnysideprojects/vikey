# ViKey — context for Claude Code

UniKey-style Vietnamese input method for macOS. Menu bar app (Swift, SwiftPM, macOS 13+), no Xcode project.

## How it works
- `CGEventTap` (session, head insert) catches keyDown. Letters (and VNI digits inside a word) go to `Engine`.
- If the engine output is just `before + key`, the real event passes through. Otherwise the key is swallowed and
  `KeyTap.replace` posts N backspaces + the new suffix as synthetic Unicode key events (`tapPostEvent`), tagged with
  `eventSourceUserData = syntheticMarker` so the tap ignores them.
- No marked text / IMK — that is the point (no underline like the built-in macOS Vietnamese input).
- Word boundary (space, punctuation, arrows, return, mouse click, app switch, ⌘/⌃/⌥ combos) → `engine.reset()`.
- Backspace passes through; `engine.backspace()` rebuilds state for `output.dropLast()` by synthesizing keys.

## Layout
- `Sources/ViKeyCore/` — pure engine, no AppKit. `Vietnamese.swift` (syllable validity, tone placement, render),
  `Engine.swift` (per-word key processing, undo-by-repeat, English restore, backspace resync).
- `Sources/ViKeyCore/Version.swift` — `AppVersion` (dotted numeric compare, `v` prefix, 1.2 == 1.2.0), used by the
  update check; Swift only, covered by the self-test.
- `Sources/ViKeyCore/Macro.swift` — abbreviation table ("gõ tắt") in UniKey `ukmacro.txt` format (UTF-8/BOM/CRLF or
  UTF-16, `;` comment lines, `key:value`). Swift only, not in the Python reference.
- `Sources/ViKey/` — `KeyTap.swift` (event tap + output), `Lexicon.swift` (real Vietnamese syllables for the
  word-end English restore: checks all ~32k `Vietnamese.syllableCandidates()` once with `NSSpellChecker` "vi" in
  50-word main-thread batches, ~9 s, keeps ~6.7k, caches `~/Library/Application Support/ViKey/syllables.txt` keyed
  by macOS version; until ready or if the count looks wrong every word counts as real = no restore), `AppDelegate.swift` (menu, Accessibility, per-app state),
  `Settings.swift` (UserDefaults), `MacroFile.swift` (polls the chosen ukmacro.txt every 3 s off the main thread,
  read-only, so it can sit in Google Drive and be shared with UniKey on Windows), `SecureInput.swift` (polls
  `IsSecureEventInputEnabled` every 1 s; holder app from the session's `kCGSSessionSecureInputPID`, which names
  the responsible GUI app; menu bar shows a lock + greyed letter and a menu line), `UpdateChecker.swift` (GET
  `api.github.com/repos/sunnysideprojects/vikey/releases/latest`, compares `tag_name` with CFBundleShortVersionString;
  menu "Kiểm tra cập nhật…" shows an alert, auto check 20 s after launch then daily unless "Tự kiểm tra cập nhật"
  is off, a newer release adds a top menu line that opens the release page; never downloads or installs; `--check-update`
  launch arg runs the manual check), `AboutWindow.swift` ("Giới thiệu
  ViKey", Sunny Side Projects brand: tokens, Bricolage Grotesque, endorsement line; `--about` launch arg opens it),
  `ViKeyApp.swift` (@main).
- `Resources/` — Info.plist, `AppIcon.icns`, the SSP logo and Bricolage font (OFL), copied into Contents/Resources by
  build.sh. Brand source: ~/Documents/Workplace/SSP/brand (BRAND-BOOK.md, tokens/tokens.json).
- `scripts/` — `build-icon.sh` + `make-icon.swift` (app icon), `frame-screenshots.swift` (README screenshot),
  `release.sh` (GitHub release, see below).
- `docs/` — README images only: `vikey-icon.png` (logo), `screenshot.png` (menu + About window).
- `Sources/ViKeySelfTest/` — engine tests as an executable (no XCTest, works with Command Line Tools only); reads
  the engine cases from `reference/cases.tsv` at run time.
- `reference/` — Python port of the engine (`engine.py`) + shared `cases.tsv`, `restore.tsv` (word-end restore,
  column 4 = the one word the fake dictionary knows) + `test_engine.py` (incl. 20k-word
  backspace fuzz). The Swift engine mirrors it 1:1; keep them in sync when changing rules.

## Commands
- `swift run -c release ViKeySelfTest` — engine tests
- `python3 reference/test_engine.py` — reference tests
- `bash build.sh` / `bash build.sh --install` — universal build, ad-hoc sign, copy to /Applications, reset + re-prompt
  Accessibility (ad-hoc signature changes every build, so the TCC grant must be re-enabled).
- `open /Applications/ViKey.app --args --about` (after `pkill -x ViKey`) — launch with the About window open.

## Icon and README images
- App icon: cream "Vi" keycap sticker (ink border + hard ink shadow) on a yolk squircle, Bricolage ExtraBold.
  `bash scripts/build-icon.sh [label]` regenerates `Resources/AppIcon.icns` and `docs/vikey-icon.png` (256 px); the
  output is deterministic, both files are checked in. Info.plist has `CFBundleIconFile = AppIcon`.
- Screenshot: capture windows with `screencapture -x -l <windowID>` (keeps the shadow; find the ID with
  `CGWindowListCopyWindowInfo`, owner "ViKey": About is layer 0, the open menu is a non-zero layer). Claude has Screen
  Recording permission (granted 2026-11-24). The computer-use tools cannot target ViKey (LSUIElement, not in the app
  index), so for the menu run a small poller that captures the first ViKey window with layer != 0 and ask the user to
  click the menu bar item. Menus come out grey (no vibrancy backdrop); that is expected.
  Then `swift scripts/frame-screenshots.swift docs/screenshot.png menu.png about.png` (yolk-soft backdrop, radius-lg,
  2 pt ink border, per the brand book's screenshot rule). README shows it at half size (`width="925"`).

## Repo and releases
- Public repo: https://github.com/sunnysideprojects/vikey (org `sunnysideprojects` = Sunny Side Projects), branch
  `main`, MIT (font OFL, SSP logo all rights reserved; see LICENSE). `origin` uses the SSH host alias
  `github.com-personal` (personal key, account nhatnx); `gh` is logged in as nhatnx.
- Never commit `ukmacro.txt` (the user's personal abbreviations, gitignored), `build/`, `dist/`.
- Releases (latest v1.0.3, 2026-11-24): `scripts/release.sh X.Y.Z changes.md [--dry-run]`. changes.md is the
  release-specific part of the notes in Vietnamese (one-line summary + `## Thay đổi` bullets); write it in the
  scratchpad, not the repo. The script checks (on main, clean, in sync with origin, tag free, version newer), bumps
  `CFBundleShortVersionString` and `CFBundleVersion` (+1), runs build.sh, zips to `dist/ViKey-X.Y.Z.zip`, writes
  `dist/notes-X.Y.Z.md` (changes + install steps incl. the Gatekeeper workaround + SHA-256 + SSP endorsement line),
  then commits "Bump version to X.Y.Z", pushes, runs `gh release create` on that commit and checks the tag and
  `releases/latest`. Info.plist is restored on any failure before the commit. Do a `--dry-run` first (no git or
  GitHub changes) and show the notes.
- CI: `.github/workflows/ci.yml` on push to main / PRs (macos-latest): Python reference tests, build.sh, bundle checks.
- The app is ad-hoc signed, not notarized: first launch is blocked by Gatekeeper (right-click → Open, or
  `xattr -dr com.apple.quarantine /Applications/ViKey.app`). Fixing that needs a paid Developer ID + notarization.
- README links to `/releases/latest`, so it needs no edit per release.

## Engine rules worth knowing
- Spell check on: a transform is applied only if the result stays a valid Vietnamese syllable prefix; if the word is
  invalid, output = raw keys minus "undo" keys (`tesst` → `test`, `windows` stays `windows`).
- Word-end restore (Telex only, menu "Trả lại từ không có trong từ điển", default on, needs spell check): on
  space/Return/Tab/punctuation, if the output has diacritics and its lowercase old-style spelling is not a real
  syllable, KeyTap retypes the raw keys (`law`→`lă`→`law`, `yes`, `more`, `door`). Real words stay (`car`→`cả`,
  `sex`→`sẽ`). Doubled-letter words still need a third letter (`bosss`→`boss`): `ass`→`as` and `tesst`→`test` win.
  `Engine.restoreIfNotWord(isWord:)` / `restore_if_not_word`.
- Repeat a mark key to undo it and type it literally (`ass` → `as`, `aaa` → `aa`).
- `ư` + `o` auto-becomes `ươ`; a following `w`/`7` just confirms it (`uwow` → `ươ`). Open syllable `ươ` renders `uơ` (thuở).
- Abbreviations: KeyTap tracks a token since the last whitespace/caret move (`tokenPrefix + engine.output`, plus the
  raw keys as a fallback match). Space/Return/Tab, or punctuation that does not extend any key, expands it; the
  trigger key is then re-posted as a copy. Return/Tab expansions type the text under the Space keycode.
  Case-insensitive lookup, `Dc` -> `Được`, `DC` -> `ĐƯỢC`; an exact-case key wins (`k0g:Không`).
- Tone position: last modded vowel; else 1 vowel → it; 3 vowels → middle; 2 vowels → 2nd if coda, else 1st
  (modern style puts oa/oe/uy on the 2nd).

## Status / open issues
- Claude can build, install and launch on the user's Mac (Xcode + gh available); the user tests typing by hand.
- On this macOS the status item has no window owned by ViKey in `CGWindowListCopyWindowInfo`; to check the menu bar
  icon, capture the screen strip instead (`screencapture -x -R<x>,0,900,30`).
- Shipped 2026-11-24: app icon, About window, gõ tắt, public repo, release v1.0.0, README logo + screenshot.
- Fixed (user confirmed 2026-11-16): fast typing dropped text ("làm" → "lm"; after deleting and retyping → "a2a2" /
  "la2m"). User types VNI. Cause: synthetic text events used keycode 0 (= the A key, often still held when typing
  fast, so the app dropped them); now they reuse the keycode of the swallowed key. Also `engine.reset()` when the
  tap gets disabled by timeout. The "la2m" symptom was only a consequence: the screen lost a char the engine still
  had, so the retyped word looked invalid and mark keys passed through. If it ever comes back: find out which app,
  compare with TextEdit, then consider
  (a) returning the modified original event for the last char instead of swallowing it, (b) a per-app slow mode with
  small delays between synthetic events, (c) skipping the browser-fix U+202F trick outside address bars.
- Abbreviations (gõ tắt) with the user's ukmacro.txt on Google Drive: user confirmed working 2026-11-24.
- Known limits: no typing under Secure Input (password fields; shown with a lock in the menu bar), no restoring an old word after the caret moved, Unicode only.

## Conventions
- Code and comments in English; user-facing menu strings in Vietnamese.
