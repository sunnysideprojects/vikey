import AppKit
import ViKeyCore

/// Global keyboard hook. Like UniKey: it watches keystrokes, and when a word changes
/// shape (tieen -> tiên) it swallows the key, sends backspaces and types the new text.
/// No marked text, so no underline and no half-committed words.
final class KeyTap {
    static let syntheticMarker: Int64 = 0x5649_4B45  // "VIKE"

    private static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "app.zen-browser.zen",
        "com.brave.Browser", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX", "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS", "com.duckduckgo.macos.browser", "ai.perplexity.comet",
        "com.coccoc.Coccoc",
    ]

    private static let backspaceKey: CGKeyCode = 51
    private static let spaceKey: CGKeyCode = 49

    let engine: Engine
    var enabled = true
    var hotkey: Hotkey = .ctrlShift
    var browserFix = true
    /// Use the address-bar trick only when the focus is outside the web page (asks Accessibility).
    var addressBarOnly = false
    var frontBundleID: String? {
        didSet { webFocus = nil }
    }
    /// Fast-typing fallbacks, per app (bundle IDs). Slow: a short pause after every key ViKey sends.
    var slowApps: Set<String> = []
    /// Real key: the last character of a change goes out in the user's own (edited) key event.
    var realKeyApps: Set<String> = []
    var onToggle: (() -> Void)?
    var macros = MacroTable()
    var macroEnabled = true
    /// Word-end restore of English words that came out as non-words (`law` -> `lă` -> `law`).
    var englishRestore = true
    var isWord: ((String) -> Bool)?
    /// Esc right after a converted word puts back the raw keys (`car` -> `cả` -> Esc -> `car`).
    var escRevert = true
    /// Backspace over the space after a word picks the word up again (`tiêng ` ⌫ `s` -> `tiếng`).
    var backspaceResume = true

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeyArmed = false
    private let source = CGEventSource(stateID: .privateState)

    // Abbreviation tracking. A "token" runs from the last whitespace/caret move to the caret and can
    // span several engine words (`k0`, `9h`, `a.b`). On screen it is `tokenPrefix + engine.output`.
    private var tokenPrefix = ""
    /// Physical keys typed in the token (`ddc`), a fallback match when the screen text differs (`đc`).
    private var tokenKeys = ""
    private var tokenKeysValid = true
    /// Finished words since the caret last moved, with the spaces and punctuation between them.
    private var recent = RecentText()

    /// Whether the focused text field sits inside a web page (nil: not asked yet since the focus
    /// may have moved). Only used with `addressBarOnly`.
    private var webFocus: Bool?
    private static let slowPause: useconds_t = 4000  // 4 ms after each key ViKey sends

    init(engine: Engine) {
        self.engine = engine
    }

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - Event handling

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Keys typed while the tap was off reached the app unseen: our word state is stale.
            resetWord()
            webFocus = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            resetWord()  // caret probably moved
            webFocus = nil
            return pass
        case .flagsChanged:
            handleModifiers(event.flags)
            return pass
        case .keyDown:
            break
        default:
            return pass
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return pass }
        hotkeyArmed = false
        guard enabled else { return pass }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            resetWord()
            webFocus = nil  // ⌘L, ⌘F, ⌃Tab... move the focus
            return pass
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if keyCode == Self.backspaceKey {
            // Let the app delete; just resync the engine. With no word in progress the deleted
            // character comes off the text before it, and deleting the space or punctuation right
            // after a word makes that word the one in progress again.
            if !engine.backspace() {
                if !tokenPrefix.isEmpty { tokenPrefix.removeLast() }
                if let word = recent.backspace(resume: backspaceResume) {
                    engine.resume(word)
                    tokenPrefix = tokenPrefix.hasSuffix(word) ? String(tokenPrefix.dropLast(word.count)) : ""
                }
            }
            tokenKeysValid = false
            return pass
        }

        guard let ch = typedCharacter(event) else {
            resetWord()  // arrows, function keys...
            webFocus = nil
            return pass
        }
        if !isEngineKey(ch) {
            // Return, Tab and Esc may move the focus (once the key is through).
            if ch == "\r" || ch == "\t" || ch == "\u{1B}" || ch == "\u{3}" { webFocus = nil }
            if ch == "\u{1B}", escRevert, revertWord(proxy: proxy) { return nil }
            if expandMacro(trigger: ch, event: event, keyCode: keyCode, proxy: proxy) { return nil }
            if restoreWord(trigger: ch, event: event, keyCode: keyCode, proxy: proxy) { return nil }
            endWord(engine.output, with: ch)
            return pass
        }

        tokenKeys.append(ch)
        let before = engine.output
        let after = engine.process(ch)
        if after == before + String(ch) { return pass }  // plain typing: let the real key through
        let realKey = frontBundleID.map(realKeyApps.contains) ?? false
        return replace(old: before, new: after, keyCode: keyCode, proxy: proxy, into: realKey ? event : nil)
            ? pass : nil
    }

    /// Forget the word being typed and the text before it (caret moved, app switched, settings
    /// changed...).
    func resetWord() {
        engine.reset()
        tokenPrefix = ""
        tokenKeys = ""
        tokenKeysValid = true
        recent.clear()
    }

    /// `word` is on screen and `ch` (not an engine key) is being typed after it.
    private func endWord(_ word: String, with ch: Character) {
        if Self.isTokenChar(ch) {
            // Punctuation or a digit ends the engine word but not the token (`k0`, `9h`).
            engine.reset()
            tokenPrefix += word + String(ch)
            tokenKeys.append(ch)
            recent.append(word + String(ch))
        } else if ch == " " {
            // Ends the token; the word stays reachable with backspace.
            engine.reset()
            tokenPrefix = ""
            tokenKeys = ""
            tokenKeysValid = true
            recent.append(word + " ")
        } else {
            resetWord()  // Return, Tab, Esc: the caret may be somewhere else now
        }
    }

    /// Visible, non-whitespace character that stays part of an abbreviation token.
    private static func isTokenChar(_ ch: Character) -> Bool {
        guard let s = ch.unicodeScalars.first else { return false }
        if s.properties.generalCategory == .privateUse { return false }  // arrows, F-keys
        return !ch.isWhitespace && !ch.isNewline && s.value >= 0x20 && s.value != 0x7F
    }

    /// `ch` ends the token (whitespace, or punctuation that is not part of any key): if the token
    /// is an abbreviation, replace it on screen, then retype the trigger key itself.
    private func expandMacro(trigger ch: Character, event: CGEvent, keyCode: CGKeyCode, proxy: CGEventTapProxy) -> Bool {
        guard macroEnabled, !macros.isEmpty else { return false }
        let screen = tokenPrefix + engine.output
        guard !screen.isEmpty else { return false }
        let isText = Self.isTokenChar(ch)
        if isText {
            // `~` or `a.` may be the start of a longer key: keep typing.
            if ch.isLetter || ch.isNumber || macros.isPrefix(screen + String(ch)) { return false }
        } else if !(ch == " " || ch == "\r" || ch == "\t" || ch == "\u{3}") {
            return false  // escape etc.
        }
        guard let expansion = macros.lookup(screen) ?? (tokenKeysValid ? macros.lookup(tokenKeys) : nil),
              expansion != screen else { return false }
        // The expansion starts a fresh token, but stays in the recent text like any word.
        recent.dropLast(tokenPrefix.count)
        let history = recent
        resetWord()
        if isText || ch == " " {
            recent = history
            recent.append(expansion + String(ch))
        }
        // Return/Tab keycodes carry meaning (send, next field) in many apps: type text as Space.
        replace(old: screen, new: expansion, keyCode: isText || ch == " " ? keyCode : Self.spaceKey, proxy: proxy)
        if let copy = event.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            copy.tapPostEvent(proxy)
        }
        return true
    }

    /// Esc: if the word being typed was converted, swallow the Esc and put back the raw keys. The
    /// word then stays literal until it ends. Nothing to undo: Esc passes through as usual (a second
    /// Esc always does).
    private func revertWord(proxy: CGEventTapProxy) -> Bool {
        let old = engine.output
        guard let raw = engine.revert() else { return false }
        // The Escape keycode could still close a dialog or leave insert mode: type under Space.
        replace(old: old, new: raw, keyCode: Self.spaceKey, proxy: proxy)
        return true
    }

    /// `ch` ends the word (whitespace or punctuation): if the engine turned it into something the
    /// dictionary does not know, put the raw keys back, then retype the trigger key itself.
    private func restoreWord(trigger ch: Character, event: CGEvent, keyCode: CGKeyCode, proxy: CGEventTapProxy) -> Bool {
        guard englishRestore, let isWord else { return false }
        let isText = Self.isTokenChar(ch)
        guard isText || ch == " " || ch == "\r" || ch == "\t" || ch == "\u{3}" else { return false }
        let old = engine.output
        guard let raw = engine.restoreIfNotWord(isWord: isWord) else { return false }
        endWord(raw, with: ch)
        // Same as abbreviations: Return/Tab keycodes carry meaning, so the text goes under Space.
        replace(old: old, new: raw, keyCode: isText || ch == " " ? keyCode : Self.spaceKey, proxy: proxy)
        if let copy = event.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            copy.tapPostEvent(proxy)
        }
        return true
    }

    private func isEngineKey(_ ch: Character) -> Bool {
        guard ch.isASCII else { return false }
        if ch.isLetter { return true }
        // VNI mark keys only act inside a word; a leading digit is just a digit.
        return engine.method == .vni && ch.isNumber && !engine.output.isEmpty
    }

    private func typedCharacter(_ event: CGEvent) -> Character? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length == 1, let scalar = Unicode.Scalar(buffer[0]) else { return nil }
        return Character(scalar)
    }

    /// Modifier-only hotkey: press the combo and release it without typing anything else.
    private func handleModifiers(_ flags: CGEventFlags) {
        let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let mods = flags.intersection(relevant)
        let target = hotkey.flags
        if !target.isSuperset(of: mods) {
            hotkeyArmed = false
        } else if mods == target {
            hotkeyArmed = true
        } else if mods.isEmpty {
            if hotkeyArmed {
                hotkeyArmed = false
                resetWord()
                onToggle?()
            }
        }
    }

    // MARK: - Output

    /// `keyCode` is the physical key the user just pressed (and we swallowed). Synthetic text is
    /// sent under that keycode, never keycode 0: keycode 0 is the real A key, and when typing fast
    /// the A in "la" + "f/2" is often still held down. Chromium/Electron then treat our fake A press
    /// as a duplicate and drop it, so the backspace lands but "à" never appears ("làm" -> "lm").
    ///
    /// With `into`, the last character is written into that (real) event instead of a synthetic
    /// one; the caller then lets the event through. Events posted from the tap enter the system
    /// before the event the callback returns, so the order holds. Returns whether `into` was used.
    @discardableResult
    private func replace(old: String, new: String, keyCode: CGKeyCode, proxy: CGEventTapProxy,
                         into event: CGEvent? = nil) -> Bool {
        let o = Array(old), n = Array(new)
        var common = 0
        while common < o.count && common < n.count && o[common] == n[common] { common += 1 }
        var deletes = o.count - common
        var insert = String(n[common...])
        let slow = frontBundleID.map(slowApps.contains) ?? false

        if browserFix && deletes > 0, let id = frontBundleID, Self.browsers.contains(id), !focusInWebPage() {
            // Address bars keep an autocomplete suggestion selected after the caret; a backspace
            // would delete the suggestion instead of our character. Typing a throwaway char first
            // replaces the suggestion, then we delete it along with the rest.
            postText("\u{202F}", keyCode: keyCode, slow: slow, proxy: proxy)
            deletes += 1
        }
        for _ in 0..<deletes { postKey(Self.backspaceKey, slow: slow, proxy: proxy) }
        guard let event, let last = insert.popLast() else {
            postText(insert, keyCode: keyCode, slow: slow, proxy: proxy)
            return false
        }
        postText(insert, keyCode: keyCode, slow: slow, proxy: proxy)
        let units = Array(String(last).utf16)
        units.withUnsafeBufferPointer { buf in
            event.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        return true
    }

    // MARK: - Focus (address-bar trick only where it is needed)

    /// True when `addressBarOnly` is on and the focused element is inside a web page (an
    /// AXWebArea), where there is no inline autocomplete. Any doubt (no answer, slow app) = false,
    /// so the trick stays. Asked once per focus: kept until a click, Return/Tab/Esc, a ⌘/⌃/⌥
    /// combo, an arrow key or an app switch.
    private func focusInWebPage() -> Bool {
        guard addressBarOnly else { return false }
        if let webFocus { return webFocus }
        let answer = Self.askFocusInWebPage()
        if let answer { webFocus = answer }
        return answer ?? false
    }

    /// nil: no answer in time (asked again next change).
    private static func askFocusInWebPage() -> Bool? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let deadline = CFAbsoluteTimeGetCurrent() + 0.03  // the tap blocks all typing meanwhile
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.02)
        guard var element = axElement(app, kAXFocusedUIElementAttribute) else { return nil }
        for _ in 0..<40 {
            if CFAbsoluteTimeGetCurrent() > deadline { return nil }
            AXUIElementSetMessagingTimeout(element, 0.02)
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
               role as? String == "AXWebArea" { return true }
            guard let parent = axElement(element, kAXParentAttribute) else { return false }
            element = parent
        }
        return false
    }

    private static func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func mark(_ e: CGEvent) {
        e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        e.flags = []
    }

    private func postKey(_ code: CGKeyCode, slow: Bool = false, proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            mark(e)
            e.tapPostEvent(proxy)
        }
        if slow { usleep(Self.slowPause) }
    }

    private func postText(_ text: String, keyCode: CGKeyCode, slow: Bool = false, proxy: CGEventTapProxy) {
        for ch in text {
            let units = Array(String(ch).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
                units.withUnsafeBufferPointer { buf in
                    e.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                mark(e)
                e.tapPostEvent(proxy)
            }
            if slow { usleep(Self.slowPause) }
        }
    }
}
