#if TYPING_TEST
import AppKit
import ViKeyCore

/// End-to-end typing test, compiled only into the local test build (`scripts/typing-test.sh`,
/// `-DTYPING_TEST`). It posts real key events at the HID level, so they go through ViKey's own event
/// tap like keys from the keyboard, into a text view of its own (or the focused field of another
/// app with `--app`), then compares the text with the expected result.
///
/// Never in release builds: it would let anything that can launch ViKey type into other apps with
/// ViKey's Accessibility permission.
///
///     --typing-test <cases.tsv> --out <results.tsv> [--app <bundle id>] [--delay <ms>]
///
/// Cases: `method<TAB>keys<TAB>expected`, `#` comments. In keys `{BS}` `{ESC}` `{RET}` `{TAB}`;
/// in both columns `␣` is a space and `⏎` a newline.
final class TypingTest {
    enum Key: Equatable {
        case char(Character), backspace, escape, ret, tab
    }

    struct Case {
        let line: Int
        let method: InputMethod
        let keysText: String
        let keys: [Key]
        let expected: String
    }

    struct Options {
        var casesURL: URL
        var outURL: URL
        var appID: String?
        var delayMs = 8
    }

    /// Main thread: force the test settings for a case and forget the word state.
    var prepare: (InputMethod) -> Void = { _ in }
    /// Main thread: whether ViKey's tap runs, and whether the dictionary (word-end restore) is loaded.
    var status: () -> (tap: Bool, dictionary: Bool) = { (false, false) }

    private let options: Options
    private var window: NSWindow?
    private var textView: NSTextView?
    private let lock = NSLock()
    private var focusLostFlag = false
    private var observers: [NSObjectProtocol] = []
    private let source = CGEventSource(stateID: .privateState)

    init(options: Options) {
        self.options = options
    }

    static func options(from args: [String]) -> Options? {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let cases = value("--typing-test"), let out = value("--out") else { return nil }
        var o = Options(casesURL: URL(fileURLWithPath: cases), outURL: URL(fileURLWithPath: out))
        o.appID = value("--app")
        if let d = value("--delay").flatMap(Int.init) { o.delayMs = max(0, d) }
        return o
    }

    // MARK: - Run

    func run(completion: @escaping (Int) -> Void) {
        let cases: [Case]
        do {
            cases = try Self.parse(String(contentsOf: options.casesURL, encoding: .utf8))
        } catch {
            finish(["ERROR\tcannot read cases: \(error)"], failures: 1, completion: completion)
            return
        }
        waitUntilReady(deadline: Date().addingTimeInterval(30)) { [self] in
            var header = ["# delay \(options.delayMs) ms, target \(options.appID ?? "own window")"]
            let (tap, dictionary) = status()
            guard tap, CGPreflightPostEventAccess() else {
                finish(header + ["ERROR\tViKey's event tap is not running or may not post keys: check its "
                                 + "Accessibility permission (the test build shares the installed app's grant "
                                 + "only when both are signed with the same certificate)"],
                       failures: 1, completion: completion)
                return
            }
            if !dictionary { header.append("# warning: dictionary not loaded, word-end restore cases will fail") }
            guard focusTarget() else {
                finish(header + ["ERROR\tcannot focus the target (is \(options.appID ?? "?") running?)"],
                       failures: 1, completion: completion)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let (lines, failures) = runCases(cases)
                    DispatchQueue.main.async { [self] in
                        finish(header + lines, failures: failures, completion: completion)
                    }
                }
            }
        }
    }

    private func waitUntilReady(deadline: Date, then: @escaping () -> Void) {
        let s = status()
        if (s.tap && s.dictionary) || Date() > deadline { then(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in waitUntilReady(deadline: deadline, then: then) }
    }

    /// Main thread. Brings up the target and starts watching for the focus moving away.
    private func focusTarget() -> Bool {
        let nc = NotificationCenter.default
        if let id = options.appID {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
                return false
            }
            app.activate(options: [])
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let front = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if front?.bundleIdentifier != id { self?.setFocusLost() }
            })
            return true
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ViKey typing test"
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.autoresizingMask = [.width, .height]
        let text = PlainTextView(frame: scroll.bounds)
        text.autoresizingMask = [.width]
        text.font = .systemFont(ofSize: 15)
        text.isRichText = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextCompletionEnabled = false
        scroll.documentView = text
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        textView = text
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) {
            [weak self] _ in self?.setFocusLost()
        })
        return true
    }

    private func setFocusLost() {
        lock.lock(); focusLostFlag = true; lock.unlock()
    }

    private var focusLost: Bool {
        lock.lock(); defer { lock.unlock() }
        return focusLostFlag
    }

    /// Background thread.
    private func runCases(_ cases: [Case]) -> ([String], Int) {
        var lines: [String] = []
        var failures = 0
        let savedClipboard = options.appID == nil ? nil : DispatchQueue.main.sync { Self.clipboardItems() }
        defer {
            if let savedClipboard { DispatchQueue.main.sync { Self.restoreClipboard(savedClipboard) } }
        }
        for c in cases {
            DispatchQueue.main.sync {
                textView?.string = ""
                prepare(c.method)
            }
            if options.appID != nil {
                postShortcut(0)  // ⌘A
                postKey(.backspace)
                usleep(150_000)
                DispatchQueue.main.sync { prepare(c.method) }
            }
            for key in c.keys where !focusLost {
                postKey(key)
                if options.delayMs > 0 { usleep(useconds_t(options.delayMs * 1000)) }
            }
            if focusLost {
                lines.append("ABORTED\tline \(c.line): the focus moved away from the target")
                failures += 1
                break
            }
            usleep(300_000)  // let the tap and the app catch up
            let got = read()
            let ok = got == c.expected
            if !ok { failures += 1 }
            lines.append([ok ? "PASS" : "FAIL", String(c.line), c.method.rawValue, c.keysText,
                          Self.show(c.expected), got.map(Self.show) ?? "(nothing read)"].joined(separator: "\t"))
        }
        return (lines, failures)
    }

    /// Background thread.
    private func read() -> String? {
        guard options.appID != nil else { return DispatchQueue.main.sync { textView?.string } }
        let before = DispatchQueue.main.sync { NSPasteboard.general.changeCount }
        postShortcut(0)  // ⌘A
        postShortcut(8)  // ⌘C
        for _ in 0..<40 {
            usleep(25_000)
            let text: String? = DispatchQueue.main.sync {
                let pb = NSPasteboard.general
                return pb.changeCount != before ? pb.string(forType: .string) ?? "" : nil
            }
            if let text { return text }
        }
        return nil
    }

    private func finish(_ lines: [String], failures: Int, completion: @escaping (Int) -> Void) {
        for o in observers {
            NotificationCenter.default.removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observers = []
        let summary = "# \(lines.filter { $0.hasPrefix("PASS") || $0.hasPrefix("FAIL") }.count) case(s) run, "
            + "\(failures) failure(s)"
        try? (lines + [summary]).joined(separator: "\n").appending("\n")
            .write(to: options.outURL, atomically: true, encoding: .utf8)
        window?.close()
        completion(failures)
    }

    // MARK: - Key events

    private func postKey(_ key: Key) {
        switch key {
        case .backspace: post(code: 51, char: "\u{8}", flags: [])
        case .escape: post(code: 53, char: "\u{1B}", flags: [])
        case .ret: post(code: 36, char: "\r", flags: [])
        case .tab: post(code: 48, char: "\t", flags: [])
        case .char(let ch):
            guard let (code, shift) = Self.keyCode(ch) else { return }
            post(code: code, char: ch, flags: shift ? .maskShift : [])
        }
    }

    private func postShortcut(_ code: CGKeyCode) {
        post(code: code, char: nil, flags: .maskCommand)
        usleep(30_000)
    }

    private func post(code: CGKeyCode, char: Character?, flags: CGEventFlags) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            if let char {
                let units = Array(String(char).utf16)
                units.withUnsafeBufferPointer { e.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress) }
            }
            e.post(tap: .cghidEventTap)
        }
    }

    /// US (ABC) layout.
    private static let codes: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, " ": 49, "`": 50,
    ]
    private static let shifted: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/",
        "~": "`",
    ]

    static func keyCode(_ ch: Character) -> (CGKeyCode, Bool)? {
        if let c = codes[ch] { return (c, false) }
        if let base = shifted[ch], let c = codes[base] { return (c, true) }
        let lower = Character(ch.lowercased())
        if lower != ch, let c = codes[lower] { return (c, true) }
        return nil
    }

    // MARK: - Cases

    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    static func parse(_ text: String) throws -> [Case] {
        var cases: [Case] = []
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") { continue }
            let f = line.components(separatedBy: "\t")
            guard f.count >= 3, let method = InputMethod(rawValue: f[0]) else {
                throw ParseError(description: "line \(i + 1): want method<TAB>keys<TAB>expected")
            }
            let keys = try parseKeys(f[1], line: i + 1)
            cases.append(Case(line: i + 1, method: method, keysText: f[1], keys: keys, expected: unshow(f[2])))
        }
        return cases
    }

    private static func parseKeys(_ s: String, line: Int) throws -> [Key] {
        var keys: [Key] = []
        var rest = Substring(s)
        let named: [String: Key] = ["{BS}": .backspace, "{ESC}": .escape, "{RET}": .ret, "{TAB}": .tab]
        while let ch = rest.first {
            if ch == "{", let end = rest.firstIndex(of: "}") {
                let name = String(rest[...end])
                guard let key = named[name] else { throw ParseError(description: "line \(line): unknown key \(name)") }
                keys.append(key)
                rest = rest[rest.index(after: end)...]
                continue
            }
            let c: Character = ch == "␣" ? " " : ch
            guard keyCode(c) != nil else { throw ParseError(description: "line \(line): no key for \(c)") }
            keys.append(.char(c))
            rest = rest.dropFirst()
        }
        return keys
    }

    private static func unshow(_ s: String) -> String {
        s.replacingOccurrences(of: "␣", with: " ").replacingOccurrences(of: "⏎", with: "\n")
    }

    private static func show(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "␣").replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\r", with: "⏎").replacingOccurrences(of: "\t", with: "⇥")
    }

    // MARK: - Clipboard (app mode reads the field with ⌘A ⌘C)

    private static func clipboardItems() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { data[type] = item.data(forType: type) }
            return data
        }
    }

    private static func restoreClipboard(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        })
    }
}

/// Esc in a text view opens the completion popup; the test types Esc on purpose.
private final class PlainTextView: NSTextView {
    override func complete(_ sender: Any?) {}
    override func cancelOperation(_ sender: Any?) {}
}
#endif
