import AppKit
import ViKeyCore

/// Global keyboard hook. Like UniKey: it watches keystrokes, and when a word changes
/// shape (tieen -> tiên) it swallows the key, sends backspaces and types the new text.
/// No marked text, so no underline and no half-committed words.
final class KeyTap {
    static let syntheticMarker: Int64 = 0x5649_4B45  // "VIKE"

    private static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "org.mozilla.firefox", "com.apple.Safari", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "com.coccoc.Coccoc", "org.chromium.Chromium",
    ]

    private static let backspaceKey: CGKeyCode = 51
    private static let spaceKey: CGKeyCode = 49

    let engine: Engine
    var enabled = true
    var hotkey: Hotkey = .ctrlShift
    var browserFix = true
    var frontBundleID: String?
    var onToggle: (() -> Void)?
    var macros = MacroTable()
    var macroEnabled = true

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
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            resetWord()  // caret probably moved
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
            return pass
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if keyCode == Self.backspaceKey {
            // Let the app delete; just resync the engine (or the part of the token before it).
            if !engine.backspace(), !tokenPrefix.isEmpty { tokenPrefix.removeLast() }
            tokenKeysValid = false
            return pass
        }

        guard let ch = typedCharacter(event) else {
            resetWord()  // arrows, function keys...
            return pass
        }
        if !isEngineKey(ch) {
            if expandMacro(trigger: ch, event: event, keyCode: keyCode, proxy: proxy) { return nil }
            if Self.isTokenChar(ch) {
                // Punctuation or a digit ends the engine word but not the token (`k0`, `9h`).
                tokenPrefix += engine.output + String(ch)
                tokenKeys.append(ch)
                engine.reset()
            } else {
                resetWord()  // space, return, tab, escape: end of word
            }
            return pass
        }

        tokenKeys.append(ch)
        let before = engine.output
        let after = engine.process(ch)
        if after == before + String(ch) { return pass }  // plain typing: let the real key through
        replace(old: before, new: after, keyCode: keyCode, proxy: proxy)
        return nil
    }

    /// Forget the word being typed (caret moved, app switched, settings changed...).
    func resetWord() {
        engine.reset()
        tokenPrefix = ""
        tokenKeys = ""
        tokenKeysValid = true
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
        resetWord()
        // Return/Tab keycodes carry meaning (send, next field) in many apps: type text as Space.
        replace(old: screen, new: expansion, keyCode: isText || ch == " " ? keyCode : Self.spaceKey, proxy: proxy)
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
    private func replace(old: String, new: String, keyCode: CGKeyCode, proxy: CGEventTapProxy) {
        let o = Array(old), n = Array(new)
        var common = 0
        while common < o.count && common < n.count && o[common] == n[common] { common += 1 }
        var deletes = o.count - common
        let insert = String(n[common...])

        if browserFix && deletes > 0, let id = frontBundleID, Self.browsers.contains(id) {
            // Address bars keep an autocomplete suggestion selected after the caret; a backspace
            // would delete the suggestion instead of our character. Typing a throwaway char first
            // replaces the suggestion, then we delete it along with the rest.
            postText("\u{202F}", keyCode: keyCode, proxy: proxy)
            deletes += 1
        }
        for _ in 0..<deletes { postKey(Self.backspaceKey, proxy: proxy) }
        postText(insert, keyCode: keyCode, proxy: proxy)
    }

    private func mark(_ e: CGEvent) {
        e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        e.flags = []
    }

    private func postKey(_ code: CGKeyCode, proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            mark(e)
            e.tapPostEvent(proxy)
        }
    }

    private func postText(_ text: String, keyCode: CGKeyCode, proxy: CGEventTapProxy) {
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
        }
    }
}
