import Foundation

public enum InputMethod: String, CaseIterable {
    case telex, vni
}

/// Converts the keystrokes of one word into Vietnamese text.
///
/// The caller feeds every letter key of the current word to `process(_:)`, reads
/// `output`, and diffs it against what is already on screen. Call `reset()` at
/// word boundaries (space, punctuation, arrows, mouse clicks, app switches).
public final class Engine {
    public var method: InputMethod
    public var modernTone: Bool
    public var spellCheck: Bool

    private var keys: [Character] = []
    private var letters: [Letter] = []
    private var tone = 0
    private var dropped: Set<Int> = []
    /// When set, the engine stops transforming and just echoes keys until reset.
    private var inert: String?
    /// The last "o" was turned into "ơ" automatically after "ư"; a following w/7 just confirms it.
    private var autoHorn = false

    private static let telexTones: [Character: Int] = ["s": 1, "f": 2, "r": 3, "x": 4, "j": 5]
    private static let maxKeys = 24

    public init(method: InputMethod = .telex, modernTone: Bool = false, spellCheck: Bool = true) {
        self.method = method
        self.modernTone = modernTone
        self.spellCheck = spellCheck
    }

    public func reset() {
        keys = []
        letters = []
        tone = 0
        dropped = []
        inert = nil
        autoHorn = false
    }

    public var output: String {
        if let inert { return inert }
        if spellCheck && !Vietnamese.isValid(letters, tone: tone) {
            // Not Vietnamese: give back exactly what was typed (minus "undo" keys).
            return String(keys.enumerated().filter { !dropped.contains($0.offset) }.map { $0.element })
        }
        return Vietnamese.render(letters, tone: tone, modern: modernTone)
    }

    @discardableResult
    public func process(_ ch: Character) -> String {
        if inert != nil {
            inert! += String(ch)
            return inert!
        }
        let before = output
        keys.append(ch)
        if keys.count > Self.maxKeys {
            inert = before + String(ch)
            return inert!
        }
        let lo = Self.lower(ch)
        let auto = autoHorn
        autoHorn = false
        if spellCheck && !Vietnamese.isValid(letters, tone: tone) {
            append(ch)  // already not Vietnamese: type literally
            return output
        }
        autoHorn = auto

        var consumed = false
        switch method {
        case .telex:
            if let t = Self.telexTones[lo] {
                consumed = applyTone(t, ch)
            } else if lo == "z" {
                consumed = removeTone()
            } else if lo == "a" || lo == "e" || lo == "o" {
                consumed = applyHat(ch, target: lo)
            } else if lo == "w" {
                consumed = applyHorn(ch, allowBreve: true, allowInsert: true)
            } else if lo == "d" {
                consumed = applyStroke(ch)
            }
        case .vni:
            if let d = lo.wholeNumberValue, lo.isASCII {
                switch d {
                case 1...5: consumed = applyTone(d, ch)
                case 0: consumed = removeTone()
                case 6: consumed = applyHat(ch, target: nil)
                case 7: consumed = applyHorn(ch, allowBreve: false)
                case 8: consumed = applyHorn(ch, allowBreve: true, allowHorn: false)
                case 9: consumed = applyStroke(ch)
                default: break
                }
            }
        }
        autoHorn = false
        if !consumed { append(ch) }
        return output
    }

    /// At the end of a word: the raw keys if the engine made a Vietnamese-looking word that the
    /// dictionary does not know (`law` -> `lă` -> `law`, `yes` -> `ýe` -> `yes`). Telex only: in VNI the
    /// raw keys are digits. `isWord` gets the lowercase old-style spelling (`khỏe`, `thủy`, `hòa`).
    public func restoreIfNotWord(isWord: (String) -> Bool) -> String? {
        guard method == .telex, spellCheck, inert == nil, !letters.isEmpty,
              Vietnamese.isValid(letters, tone: tone) else { return nil }
        let out = output
        let raw = String(keys)
        guard out.unicodeScalars.contains(where: { !$0.isASCII }), raw != out else { return nil }
        let plain = letters.map { Letter(base: $0.base, mod: $0.mod) }
        return isWord(Vietnamese.render(plain, tone: tone, modern: false)) ? nil : raw
    }

    /// The app already deleted one character on screen; rebuild state for the shorter text.
    /// Returns false when no word was in progress.
    @discardableResult
    public func backspace() -> Bool {
        let text = output
        guard !text.isEmpty else { return false }
        let target = String(text.dropLast())
        reset()
        for k in Self.synthKeys(target, method: method) { process(k) }
        if output != target {
            reset()
            inert = target
        }
        return true
    }

    // MARK: - Actions

    private var group: [Int] { Syllable(letters).group }

    private func ok() -> Bool { !spellCheck || Vietnamese.isValid(letters, tone: tone) }

    /// Applies a change and keeps it only if the word stays valid.
    private func attempt(_ mutate: () -> Void) -> Bool {
        let savedLetters = letters, savedTone = tone
        mutate()
        if ok() { return true }
        letters = savedLetters
        tone = savedTone
        return false
    }

    private func append(_ ch: Character) {
        var letter = Letter(base: Self.lower(ch), mod: .none, upper: Self.isUpper(ch))
        if letter.base == "o", let last = letters.last, last.base == "u", last.mod == .horn {
            letter.mod = .horn  // ưo -> ươ
            autoHorn = true
        }
        letters.append(letter)
    }

    /// Pressing a mark key twice removes the mark and types the key itself (ss, aaa, ww, dd...).
    private func undoLiteral(_ ch: Character) {
        dropped.insert(keys.count - 1)
        letters.append(Letter(base: Self.lower(ch), mod: .none, upper: Self.isUpper(ch)))
    }

    private func applyTone(_ t: Int, _ ch: Character) -> Bool {
        if group.isEmpty { return false }
        if tone == t {
            tone = 0
            undoLiteral(ch)
            return true
        }
        return attempt { tone = t }
    }

    private func removeTone() -> Bool {
        if tone == 0 { return false }
        tone = 0
        return true
    }

    private func applyHat(_ ch: Character, target: Character?) -> Bool {
        let allowed: Set<Character> = target.map { Set([$0]) } ?? ["a", "e", "o"]
        let cands = group.filter { allowed.contains(letters[$0].base) }
        if cands.isEmpty { return false }
        if cands.contains(where: { letters[$0].mod == .hat }) {
            for k in cands where letters[k].mod == .hat { letters[k].mod = .none }
            undoLiteral(ch)
            return true
        }
        for k in cands.reversed() where attempt({ letters[k].mod = .hat }) {
            return true
        }
        return false
    }

    private func applyHorn(_ ch: Character, allowBreve: Bool, allowHorn: Bool = true, allowInsert: Bool = false) -> Bool {
        let g = group
        if allowHorn && autoHorn {
            autoHorn = false
            return true  // "uwow": the w just confirms the automatic ơ
        }
        var relevant: [Mod] = []
        if allowHorn { relevant.append(.horn) }
        if allowBreve { relevant.append(.breve) }
        if g.contains(where: { relevant.contains(letters[$0].mod) }) {
            for k in g where relevant.contains(letters[k].mod) { letters[k].mod = .none }
            undoLiteral(ch)
            return true
        }
        if g.isEmpty {
            if allowInsert && !letters.contains(where: { Vietnamese.vowels.contains($0.base) }) {
                let up = Self.isUpper(ch)
                return attempt { letters.append(Letter(base: "u", mod: .horn, upper: up)) }  // w -> ư
            }
            return false
        }
        // "giw" -> "giư": the i of "gi" belongs to the initial, so w still inserts ư (giữ, giờ).
        if allowInsert, letters.count == 2, letters[0].base == "g", letters[1].base == "i", letters[1].mod == .none {
            let up = Self.isUpper(ch)
            if attempt({ letters.append(Letter(base: "u", mod: .horn, upper: up)) }) { return true }
        }
        let bases = g.map { letters[$0].base }
        var targets: [[Int]] = []
        if allowHorn {
            for a in 0..<(g.count - 1) where bases[a] == "u" && bases[a + 1] == "o" {
                targets.append([g[a], g[a + 1]])
            }
            if let i = bases.lastIndex(of: "o") { targets.append([g[i]]) }
            if let i = bases.firstIndex(of: "u") { targets.append([g[i]]) }
        }
        if allowBreve, let i = bases.firstIndex(of: "a") { targets.append([g[i]]) }
        for t in targets {
            let applied = attempt {
                for k in t { letters[k].mod = letters[k].base == "a" ? .breve : .horn }
            }
            if applied { return true }
        }
        return false
    }

    private func applyStroke(_ ch: Character) -> Bool {
        guard let first = letters.first, first.base == "d" else { return false }
        if first.mod == .stroke {
            letters[0].mod = .none
            undoLiteral(ch)
            return true
        }
        return attempt { letters[0].mod = .stroke }
    }

    // MARK: - Helpers

    static func lower(_ ch: Character) -> Character {
        Character(String(ch).lowercased())
    }

    static func isUpper(_ ch: Character) -> Bool {
        String(ch) != String(ch).lowercased()
    }

    /// Keystrokes that reproduce `text` (used to resume a word after backspace).
    static func synthKeys(_ text: String, method: InputMethod) -> [Character] {
        var keys: [Character] = []
        var tone = 0, horn = false, breve = false
        let telex = method == .telex
        for ch in text {
            let upper = isUpper(ch)
            let lowered = String(ch).lowercased()
            if lowered == "đ" {
                keys.append(upper ? "D" : "d")
                keys.append(telex ? "d" : "9")
                continue
            }
            let scalars = Array(lowered.decomposedStringWithCanonicalMapping.unicodeScalars)
            guard let first = scalars.first else { continue }
            let base = Character(first)
            keys.append(upper ? Character(String(base).uppercased()) : base)
            for s in scalars.dropFirst() {
                switch s.value {
                case 0x0301: tone = 1
                case 0x0300: tone = 2
                case 0x0309: tone = 3
                case 0x0303: tone = 4
                case 0x0323: tone = 5
                case 0x0302: keys.append(telex ? base : "6")
                case 0x031B: horn = true
                case 0x0306: breve = true
                default: break
                }
            }
        }
        if telex {
            if horn || breve { keys.append("w") }
            if tone > 0 { keys.append(Array("sfrxj")[tone - 1]) }
        } else {
            if horn { keys.append("7") }
            if breve { keys.append("8") }
            if tone > 0 { keys.append(Character(String(tone))) }
        }
        return keys
    }
}
