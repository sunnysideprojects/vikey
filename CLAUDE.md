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
- `Sources/ViKeyCore/RecentText.swift` — text typed since the caret last moved, before the engine's word (finished
  words + the space/punctuation after each, ≤ 120 chars, trimmed at a word start); KeyTap uses it to step back into
  the previous word on backspace. Swift only; `typeLine` cases in the self-test check it stays equal to the screen.
- `Sources/ViKeyCore/Macro.swift` — abbreviation table ("gõ tắt") in UniKey `ukmacro.txt` format (UTF-8/BOM/CRLF or
  UTF-16, `;` comment lines, `key:value`). Swift only, not in the Python reference.
- `Sources/ViKeyCore/TextTools.swift` — `TextTool` conversions for the menu "Chuyển văn bản trong clipboard"
  (AppDelegate `runTool` rewrites the clipboard as plain text, beeps if no text / no change): bỏ dấu, HOA, thường,
  Hoa Đầu Từ, TCVN3 (ABC) → Unicode (table checked against `iconv -f TCVN`, incl. the VN1 capitals; toned
  capitals from .VnTimeH fonts come out lower case), VNI Windows → Unicode (base + mark char; no external
  converter to check against, only the canonical examples), NFD → NFC. Swift only; cases in the self-test.
- `Sources/ViKey/` — `KeyTap.swift` (event tap + output), `Lexicon.swift` (real Vietnamese syllables for the
  word-end English restore: checks all ~32k `Vietnamese.syllableCandidates()` once with `NSSpellChecker` "vi" in
  50-word main-thread batches, ~9 s, keeps ~6.7k, caches `~/Library/Application Support/ViKey/syllables.txt` keyed
  by macOS version; until ready or if the count looks wrong every word counts as real = no restore), `AppDelegate.swift` (short menu, Accessibility, per-app state;
  `applySettings()` pushes UserDefaults into the engine/tap at launch and on every `UserDefaults.didChangeNotification`),
  `SettingsWindow.swift` ("Cài đặt…" ⌘,: NSTabViewController toolbar tabs Gõ phím / Gõ tắt / Tương thích / Chung,
  each a SwiftUI grouped Form with fixed size; plain prefs are `@AppStorage` on the same keys as `Settings`, which
  registers the defaults; `SettingsState` carries macro status, login item, the fast-typing app list and actions;
  remembers the last tab in `settingsTab`; `--settings` launch arg opens it),
  `Settings.swift` (UserDefaults), `MacroFile.swift` (polls the chosen ukmacro.txt every 3 s off the main thread,
  read-only, so it can sit in Google Drive and be shared with UniKey on Windows), `SecureInput.swift` (polls
  `IsSecureEventInputEnabled` every 1 s; holder app from the session's `kCGSSessionSecureInputPID`, which names
  the responsible GUI app; menu bar shows a lock + greyed letter and a menu line), `Updater.swift` (Sparkle 2,
  see Repo and releases; `SPUStandardUpdaterController`, daily automatic checks unless "Tự kiểm tra cập nhật" is
  off; "gentle reminders": an update found in the background adds a top menu line instead of a window, choosing it
  or "Kiểm tra cập nhật…" opens Sparkle's window; only started from an .app bundle and never in the typing test;
  `--check-update` launch arg runs the manual check), `AboutWindow.swift` ("Giới thiệu
  ViKey", Sunny Side Projects brand: tokens, Bricolage Grotesque, endorsement line; `--about` launch arg opens it),
  `ViKeyApp.swift` (@main), `TypingTest.swift` (end-to-end typing test, only compiled with `-DTYPING_TEST`, see
  Commands).
- `Resources/` — Info.plist, `AppIcon.icns`, the SSP logo and Bricolage font (OFL), copied into Contents/Resources by
  build.sh. Brand source: ~/Documents/Workplace/SSP/brand (BRAND-BOOK.md, tokens/tokens.json).
- `scripts/` — `build-icon.sh` + `make-icon.swift` (app icon), `frame-screenshots.swift` (README screenshot),
  `make-signing-cert.sh` (one-time signing certificate, see Repo and releases), `release.sh` + `appcast.py` (GitHub release and Sparkle feed, see below),
  `typing-test.sh` + `typing-cases.tsv` (end-to-end typing test).
- `docs/` — README images only: `vikey-icon.png` (logo), `screenshot.png` (menu + About window).
- `Sources/ViKeySelfTest/` — engine tests as an executable (no XCTest, works with Command Line Tools only); reads
  the engine cases from `reference/cases.tsv` at run time.
- `reference/` — Python port of the engine (`engine.py`) + shared `cases.tsv`, `restore.tsv` (word-end restore,
  column 4 = the one word the fake dictionary knows), `revert.tsv` (Esc revert), `resume.tsv` (resume an earlier word) + `test_engine.py` (incl. 20k-word
  backspace fuzz). The Swift engine mirrors it 1:1; keep them in sync when changing rules.

## Commands
- `swift run -c release ViKeySelfTest` — engine tests
- `python3 reference/test_engine.py` — reference tests
- `bash build.sh` / `bash build.sh --install` — universal build, sign (the "ViKey Code Signing" certificate if the
  keychain has it, else ad-hoc; `VIKEY_SIGN_IDENTITY=<sha1|->` overrides), copy to /Applications. `--install` keeps
  the Accessibility grant when the designated requirement is unchanged, else `tccutil reset` + re-prompt.
- `bash scripts/typing-test.sh [--delay MS] [--app BUNDLE_ID] [cases.tsv]` — end-to-end typing test (~30 s, needs
  the signing certificate and an unlocked screen; hands off the keyboard and mouse). Builds ViKey with
  `-DTYPING_TEST` into `.build/typing-test`, bundles `build/ViKeyTest.app` with the same bundle ID and certificate
  (so it shares the installed app's Accessibility grant), quits the installed ViKey, runs it via `open -W`, then
  deletes it and reopens the installed app. The test build posts real key events at the HID level (they pass the
  tap like keyboard keys) into a window of its own, or with `--app` into the focused field of that app (read back
  with ⌘A ⌘C, clipboard restored; Return sends in chat apps!). Settings are forced in memory only (defaults,
  macros off; `testing` blocks applySettings and smart switch). Aborts if the focus moves. Claude can run it: it
  needs no permission for Claude's shell. The test code must never be in release builds (it would let anything
  that can launch ViKey type into other apps with its Accessibility grant); `strings` on the release binary shows
  no `--typing-test`. The very first run after adding it typed nothing (new bundle not trusted yet?); it now
  fails early with an error when the tap is not running or posting is not allowed.
- `open /Applications/ViKey.app --args --about` (after `pkill -x ViKey`) — launch with the About window open
  (`--settings` for the settings window).

## Icon and README images
- App icon: cream "Vi" keycap sticker (ink border + hard ink shadow) on a yolk squircle, Bricolage ExtraBold.
  `bash scripts/build-icon.sh [label]` regenerates `Resources/AppIcon.icns` and `docs/vikey-icon.png` (256 px); the
  output is deterministic, both files are checked in. Info.plist has `CFBundleIconFile = AppIcon`.
- Screenshot: capture windows with `screencapture -x -l <windowID>` (keeps the shadow; find the ID with
  `CGWindowListCopyWindowInfo`, owner "ViKey": About is layer 0, the open menu is a non-zero layer). Claude has Screen
  Recording permission (granted 2026-11-24). The computer-use tools cannot target ViKey (LSUIElement, not in the app
  index), so for the menu run a small poller that captures the first ViKey window with layer != 0 and ask the user to
  click the menu bar item. Menus come out grey (no vibrancy backdrop); that is expected. The status menu follows the
  system appearance even when ViKey runs with `-NSRequiresAquaSystemAppearance YES`, so capture About in the same mode
  (the 2026-11-27 screenshot is dark: short menu + About). A locked screen makes every
  capture black (check `CGSSessionScreenIsLocked`); then a temporary in-app hook that `cacheDisplay`s the window's
  frame view to PNG still works. The unbundled `swift build` binary uses the `ViKey` defaults domain, not
  `dev.sunnysideprojects.vikey`, so sample settings for it do not touch the installed app.
  Then `swift scripts/frame-screenshots.swift docs/screenshot.png menu.png about.png` (yolk-soft backdrop, radius-lg,
  2 pt ink border, per the brand book's screenshot rule). README shows it at half size (`width="925"`).

## Repo and releases
- Public repo: https://github.com/sunnysideprojects/vikey (org `sunnysideprojects` = Sunny Side Projects), branch
  `main`, MIT (font OFL, SSP logo all rights reserved; see LICENSE). `origin` uses the SSH host alias
  `github.com-personal` (personal key, account nhatnx); `gh` is logged in as nhatnx.
- Never commit `ukmacro.txt` (the user's personal abbreviations, gitignored), `build/`, `dist/`.
- Releases (latest v1.0.11, 2026-11-28): `scripts/release.sh X.Y.Z changes.md [--dry-run]`. changes.md is the
  release-specific part of the notes in Vietnamese (one-line summary + `## Thay đổi` bullets); write it in the
  scratchpad, not the repo. The script checks (on main, clean, in sync with origin, tag free, version newer), bumps
  `CFBundleShortVersionString` and `CFBundleVersion` (+1), runs build.sh, zips to `dist/ViKey-X.Y.Z.zip`, writes
  `dist/notes-X.Y.Z.md` (changes + install steps incl. the Gatekeeper workaround + SHA-256 + SSP endorsement line),
  then commits "Bump version to X.Y.Z", pushes, runs `gh release create` on that commit and checks the tag and
  `releases/latest`. Info.plist is restored on any failure before the commit. Do a `--dry-run` first (no git or
  GitHub changes) and show the notes. The script refuses to build unless the keychain has the pinned certificate
  (`SIGNING_CERT_SHA1`) and checks the built app's requirement names it.
- In-app updates (Sparkle 2.10.1, SwiftPM, pinned exact; Package.resolved committed): build.sh copies
  `Sparkle.framework` into Contents/Frameworks (rpath `@executable_path/../Frameworks` from Package.swift linker
  flags), drops its XPC services (ViKey is not sandboxed) and signs Autoupdate, Updater.app, the framework and the app
  with the same identity (Sparkle rejects an update whose code signature does not match the running app). Feed:
  `SUFeedURL` = `/releases/latest/download/appcast.xml`, an asset of each release, holding only that release
  (`scripts/appcast.py` writes it from changes.md; notes as HTML). Update key: EdDSA, keychain account `vikey`
  (`generate_keys --account vikey`, created 2026-11-28), public key in `SUPublicEDKey`; release.sh checks the keychain
  key matches it, signs the zip with `sign_update --account vikey`, verifies, uploads appcast.xml with the zip, then
  checks the live feed offers the new build. Losing the key means installed copies cannot be updated in-app (users
  reinstall by hand once with a new key). Info.plist declares `vi` only (`CFBundleDevelopmentRegion`,
  `CFBundleLocalizations`), so Sparkle's window and system panels use Vietnamese. Tested 2026-11-28 with a local feed
  (`defaults write dev.sunnysideprojects.vikey SUFeedURL http://127.0.0.1:8765/appcast.xml` + `python3 -m
  http.server`; remove the default afterwards): 1.0.11 → 1.0.99 installed and relaunched, signature kept, no
  quarantine, event tap running without re-granting. The first try failed with "error extracting the archive":
  the disk was full. Releases ≤ v1.0.11 have no Sparkle and no appcast; the first release after it starts the feed.
- CI: `.github/workflows/ci.yml` on push to main / PRs (macos-latest): Python reference tests, build.sh, bundle checks.
- Signing (since v1.0.10, 2026-11-27): self-signed "ViKey Code Signing" certificate in the user's
  login keychain (RSA 3072, 20 years, SHA-1 19FE4391…F8D4), created by `scripts/make-signing-cert.sh`. Designated
  requirement `identifier "dev.sunnysideprojects.vikey" and certificate root = H"19fe…"`, so TCC keeps the
  Accessibility grant across builds and updates (users coming from ≤ v1.0.9 re-grant once). Not trusted by the system
  (`CSSMERR_TP_NOT_TRUSTED`): codesign only finds it by SHA-1, not by name. codesign's key access was allowed once
  ("Always Allow", by the user). Only this Mac has the key; if it is lost, make a new one, change the pin in
  release.sh, and every user re-grants once. CI has no certificate and builds ad-hoc.
- Not notarized: first launch is blocked by Gatekeeper (right-click → Open, or
  `xattr -dr com.apple.quarantine /Applications/ViKey.app`). Fixing that needs a paid Developer ID + notarization.
- README links to `/releases/latest`, so it needs no edit per release.

## Engine rules worth knowing
- Spell check on: a transform is applied only if the result stays a valid Vietnamese syllable prefix; if the word is
  invalid, output = raw keys minus "undo" keys (`tesst` → `test`, `windows` stays `windows`).
- Word-end restore (Telex only, setting "Trả lại từ không có trong từ điển", default on, needs spell check): on
  space/Return/Tab/punctuation, if the output has diacritics and its lowercase old-style spelling is not a real
  syllable, KeyTap retypes the raw keys (`law`→`lă`→`law`, `yes`, `more`, `door`). Real words stay (`car`→`cả`,
  `sex`→`sẽ`). Doubled-letter words still need a third letter (`bosss`→`boss`): `ass`→`as` and `tesst`→`test` win.
  `Engine.restoreIfNotWord(isWord:)` / `restore_if_not_word`.
- Repeat a mark key to undo it and type it literally (`ass` → `as`, `aaa` → `aa`).
- Esc revert (setting "Esc trả lại các phím đã gõ", default on, both methods): Esc while a converted word is in
  progress swallows the Esc and retypes the raw keys under the Space keycode (`car` → `cả` → Esc → `car`); the
  engine then stays inert (literal) until the word ends. Nothing to undo → Esc passes through, so a second Esc
  always reaches the app. Conflicts with vim's Esc in insert mode (tooltip says to turn it off).
  `Engine.revert()` / `revert`.
- Backspace into the previous word (setting "Xoá lùi để sửa từ vừa gõ", key `backspaceResume`, default on, both
  methods): with no word in progress, a backspace that deletes the space or punctuation right after a word hands
  that word back to the engine (`RecentText.backspace` → `Engine.resume(word)`, state rebuilt from `synthKeys`;
  words the keys cannot reproduce stay literal), so `tiêng␣` ⌫ `s` → `tiếng`. Several words back works too.
  Space and punctuation keep the history; Return/Tab/Esc, clicks, arrows, ⌘⌃⌥ combos and app switches clear it.
  Risk: an app that changes a word on space (autocorrect, text replacement) leaves the history stale.
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
- Shipped 2026-11-27 (v1.0.5): word-end English restore from the macOS Vietnamese dictionary; (v1.0.6) Esc
  revert; (v1.0.7) clipboard tools; (v1.0.8) fast-typing fallbacks (all off by default); (v1.0.9) Settings
  window + short menu. None of these confirmed by the user in real apps yet. (v1.0.10) stable self-signed
  signing; checked 2026-11-27 that a rebuild keeps the Accessibility grant (event tap enabled, no re-grant).
- Shipped 2026-11-28 (v1.0.11): backspace into the previous word (not tried by the user in real apps yet).
- Built 2026-11-28, not released: Sparkle in-app updates (the user clicked Install in the local-feed test).
- Built 2026-11-28: end-to-end typing test; 39 cases pass in its own window (8 ms and 0 ms between keys) and in
  TextEdit. Not run against Chrome/Electron apps yet (the fast-typing bugs were there).
- Fixed (user confirmed 2026-11-16): fast typing dropped text ("làm" → "lm"; after deleting and retyping → "a2a2" /
  "la2m"). User types VNI. Cause: synthetic text events used keycode 0 (= the A key, often still held when typing
  fast, so the app dropped them); now they reuse the keycode of the swallowed key. Also `engine.reset()` when the
  tap gets disabled by timeout. The "la2m" symptom was only a consequence: the screen lost a char the engine still
  had, so the retyped word looked invalid and mark keys passed through. If it ever comes back: find out which app,
  compare with TextEdit, then try the fallbacks (Settings → Tương thích, all off by default):
  per app (`slowApps` / `realKeyApps` bundle IDs; list with "Gõ chậm" / "Phím thật" checkboxes, add from running apps)
  (a) "Gửi chữ cuối bằng chính phím vừa bấm": the last char of a change is written into the real key event, which
  is then passed through (events posted from the tap enter the system before the returned one), (b) "Gõ chậm":
  4 ms `usleep` after each synthetic key inside the tap callback (keeps the order, blocks typing briefly); global
  (c) "Chỉ dùng ở thanh địa chỉ…" under the browser fix: asks AX whether the focused element has an AXWebArea
  ancestor (30 ms budget, cached until click/Return/Tab/Esc/arrow/⌘⌃⌥ combo/app switch; no answer = keep the
  U+202F trick). Not checked against Chrome's AX tree yet (Claude's shell has no Accessibility permission).
- Abbreviations (gõ tắt) with the user's ukmacro.txt on Google Drive: user confirmed working 2026-11-24.
- Known limits: no typing under Secure Input (password fields; shown with a lock in the menu bar), no restoring an old word after the caret moved, Unicode only.

## Conventions
- Code and comments in English; user-facing menu and settings strings in Vietnamese.
