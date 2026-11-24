import Foundation

/// Abbreviation table ("gõ tắt") in UniKey's `ukmacro.txt` format:
///
///     ;DO NOT DELETE THIS LINE*** version=1 ***
///     dc:được
///     k0g:Không
///
/// UTF-8 (with or without BOM) or UTF-16 with BOM, LF or CRLF. Lines starting with `;` are
/// comments; the key ends at the first `:`, the rest of the line is the expansion.
public struct MacroTable {
    /// Keys exactly as written in the file.
    private var exact: [String: String] = [:]
    /// Lowercased keys, for case-insensitive lookup (first entry wins).
    private var folded: [String: String] = [:]
    /// Every lowercased prefix of every key, so a trailing punctuation char that is still
    /// part of some key (`~`, `a.b`) does not trigger an expansion.
    private var prefixes: Set<String> = []

    public private(set) var count = 0

    public init() {}

    public init(entries: [(String, String)]) {
        for (k, v) in entries { add(k, v) }
    }

    public init(data: Data) {
        self.init(entries: Self.parse(Self.decode(data)))
    }

    public var isEmpty: Bool { count == 0 }

    private mutating func add(_ key: String, _ value: String) {
        let k = key.precomposedStringWithCanonicalMapping
        guard !k.isEmpty, exact[k] == nil else { return }
        let v = value.precomposedStringWithCanonicalMapping
        exact[k] = v
        let lo = k.lowercased()
        if folded[lo] == nil { folded[lo] = v }
        var p = ""
        for ch in lo { p.append(ch); prefixes.insert(p) }
        count += 1
    }

    public static func decode(_ data: Data) -> String {
        let b = [UInt8](data.prefix(3))
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) ?? ""
        }
        if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian) ?? ""
        }
        let body = b == [0xEF, 0xBB, 0xBF] ? data.dropFirst(3) : data
        // Not valid UTF-8: probably an old single-byte file; Latin-1 at least keeps the ASCII keys.
        return String(data: body, encoding: .utf8) ?? String(data: body, encoding: .isoLatin1) ?? ""
    }

    public static func parse(_ text: String) -> [(String, String)] {
        var out: [(String, String)] = []
        // "\r\n" is a single Character in Swift, so split on both forms.
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let line = String(raw)
            if line.hasPrefix(";") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...])
            if key.isEmpty || value.isEmpty { continue }
            out.append((key, value))
        }
        return out
    }

    /// True if `text` (case-insensitive) is a key or the start of a key.
    public func isPrefix(_ text: String) -> Bool {
        prefixes.contains(text.precomposedStringWithCanonicalMapping.lowercased())
    }

    /// Expansion for `typed`, or nil. Exact key first; otherwise case-insensitive with UniKey-style
    /// capitalization: `Dc` -> `Được`, `DC` -> `ĐƯỢC`.
    public func lookup(_ typed: String) -> String? {
        let t = typed.precomposedStringWithCanonicalMapping
        if t.isEmpty { return nil }
        if let v = exact[t] { return v }
        guard let v = folded[t.lowercased()] else { return nil }
        let letters = t.filter { $0.isLetter }
        guard let first = letters.first, first.isUppercase else { return v }
        if letters.count > 1 && letters.allSatisfy({ $0.isUppercase }) { return v.uppercased() }
        return v.prefix(1).uppercased() + v.dropFirst()
    }
}
