import Foundation

/// One abbreviation as the editor shows it.
public struct MacroEntry: Equatable, Identifiable {
    public let key: String
    public let value: String
    public var id: String { key }
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// One change made in the editor. `expected` is the value the user saw for `key`: when the file
/// says something else by the time it is written (another machine changed it), that is a conflict.
public enum MacroEdit: Equatable {
    case add(key: String, value: String)
    case update(key: String, expected: String, newKey: String, value: String)
    case remove(key: String, expected: String)
}

public enum MacroEditResult: Equatable {
    case applied
    /// The file already says what the edit wants (e.g. the same change came from the other machine).
    case unchanged
    /// The file's value for the key is not the one the user saw (nil: the key is gone).
    case conflict(current: String?)
    case invalid(String)
}

/// A ukmacro.txt kept line by line, so an edit rewrites only the lines it touches: the encoding,
/// BOM, header, comments, order and each line's own line ending stay byte for byte, and UniKey on
/// Windows reads the file as before.
public struct MacroDocument {
    public enum Encoding: Equatable {
        case utf8, utf8BOM, utf16LE, utf16BE
        /// Not UTF-8/UTF-16 (an old single-byte file): readable for the ASCII keys, never written.
        case latin1
    }

    public static let header = ";DO NOT DELETE THIS LINE*** version=1 ***"

    struct Line: Equatable {
        var text: String
        var end: String  // "\r\n", "\n", "\r", or "" for a last line without one
    }

    public private(set) var encoding: Encoding
    var lines: [Line]
    /// Line ending for new lines: the file's first one, CRLF in a file without any.
    let newline: String

    public var isWritable: Bool { encoding != .latin1 }

    /// A new file the way UniKey writes one: UTF-8 with BOM, CRLF, the header line.
    public static func newFile() -> MacroDocument {
        MacroDocument(encoding: .utf8BOM, lines: [Line(text: header, end: "")], newline: "\r\n")
    }

    private init(encoding: Encoding, lines: [Line], newline: String) {
        self.encoding = encoding
        self.lines = lines
        self.newline = newline
    }

    public init(data: Data) {
        let (text, encoding) = Self.decode(data)
        var lines: [Line] = []
        var current = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            if s == "\r" || s == "\n" {
                var end = String(s)
                if s == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" {
                    end = "\r\n"
                    i += 1
                }
                lines.append(Line(text: String(current), end: end))
                current = String.UnicodeScalarView()
            } else {
                current.append(s)
            }
            i += 1
        }
        if !current.isEmpty { lines.append(Line(text: String(current), end: "")) }
        self.init(encoding: encoding, lines: lines, newline: lines.first { !$0.end.isEmpty }?.end ?? "\r\n")
    }

    public static func decode(_ data: Data) -> (String, Encoding) {
        let b = [UInt8](data.prefix(3))
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE,
           let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return (s, .utf16LE) }
        if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF,
           let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return (s, .utf16BE) }
        if b == [0xEF, 0xBB, 0xBF], let s = String(data: data.dropFirst(3), encoding: .utf8) { return (s, .utf8BOM) }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8) }
        // Latin-1 decodes any bytes and at least keeps the ASCII keys.
        return (String(data: data, encoding: .isoLatin1) ?? "", .latin1)
    }

    public func data() -> Data {
        let text = lines.map { $0.text + $0.end }.joined()
        switch encoding {
        case .utf8: return Data(text.utf8)
        case .utf8BOM: return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        case .utf16LE: return Data([0xFF, 0xFE]) + (text.data(using: .utf16LittleEndian) ?? Data())
        case .utf16BE: return Data([0xFE, 0xFF]) + (text.data(using: .utf16BigEndian) ?? Data())
        case .latin1: return text.data(using: .isoLatin1) ?? Data()
        }
    }

    /// The entry on a line, read the way `MacroTable.parse` reads it.
    private static func entry(_ line: String) -> (key: String, value: String)? {
        if line.hasPrefix(";") { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colon)...])
        if key.isEmpty || value.isEmpty { return nil }
        return (key.precomposedStringWithCanonicalMapping, value.precomposedStringWithCanonicalMapping)
    }

    /// Entries in file order; for a key written twice the first one counts, as in `MacroTable`.
    public var entries: [MacroEntry] {
        var seen = Set<String>()
        var out: [MacroEntry] = []
        for line in lines {
            guard let e = Self.entry(line.text), seen.insert(e.key).inserted else { continue }
            out.append(MacroEntry(key: e.key, value: e.value))
        }
        return out
    }

    public var table: MacroTable { MacroTable(entries: entries.map { ($0.key, $0.value) }) }

    public func value(for key: String) -> String? {
        let k = key.precomposedStringWithCanonicalMapping
        for line in lines { if let e = Self.entry(line.text), e.key == k { return e.value } }
        return nil
    }

    private func lineIndices(of key: String) -> [Int] {
        let k = key.precomposedStringWithCanonicalMapping
        return lines.indices.filter { Self.entry(lines[$0].text)?.key == k }
    }

    /// Why `key`/`value` cannot be written as a line UniKey reads back the same, or nil.
    public static func problem(key: String, value: String) -> String? {
        let k = key.trimmingCharacters(in: .whitespaces)
        if k.isEmpty { return "Chưa có phím tắt." }
        if value.isEmpty { return "Chưa có nội dung." }
        if k.contains(":") { return "Phím tắt không được có dấu hai chấm (:)." }
        if k.hasPrefix(";") { return "Phím tắt không được bắt đầu bằng dấu chấm phẩy (;)." }
        if k.contains(where: \.isWhitespace) { return "Phím tắt không được có dấu cách." }
        if (k + value).unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }) {
            return "Không được xuống dòng."
        }
        return nil
    }

    private func line(_ key: String, _ value: String) -> String {
        key.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping + ":"
            + value.precomposedStringWithCanonicalMapping
    }

    /// Applies `edit` to the lines. With `force`, a conflict is resolved in favour of the edit.
    public mutating func apply(_ edit: MacroEdit, force: Bool = false) -> MacroEditResult {
        guard isWritable else { return .invalid("File không phải UTF-8 hay UTF-16, ViKey không sửa được.") }
        switch edit {
        case let .add(key, value):
            if let p = Self.problem(key: key, value: value) { return .invalid(p) }
            let v = value.precomposedStringWithCanonicalMapping
            if let current = self.value(for: key) {
                if current == v { return .unchanged }
                if !force { return .conflict(current: current) }
                lines[lineIndices(of: key)[0]].text = line(key, value)
                return .applied
            }
            append(line(key, value))
            return .applied

        case let .update(key, expected, newKey, value):
            if let p = Self.problem(key: newKey, value: value) { return .invalid(p) }
            let newK = newKey.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping
            let renamed = newK != key.precomposedStringWithCanonicalMapping
            if renamed, self.value(for: newK) != nil { return .invalid("Đã có phím tắt \(newK).") }
            let current = self.value(for: key)
            if current != expected.precomposedStringWithCanonicalMapping, !force {
                return .conflict(current: current)
            }
            let indices = lineIndices(of: key)
            guard let first = indices.first else {
                append(line(newK, value))  // forced: the key is gone, write it again
                return .applied
            }
            if !renamed, current == value.precomposedStringWithCanonicalMapping { return .unchanged }
            lines[first].text = line(newK, value)
            // A second line for the old key would show up under it once the first one is renamed.
            if renamed { remove(Array(indices.dropFirst())) }
            return .applied

        case let .remove(key, expected):
            guard let current = self.value(for: key) else { return .unchanged }
            if current != expected.precomposedStringWithCanonicalMapping, !force {
                return .conflict(current: current)
            }
            remove(lineIndices(of: key))
            return .applied
        }
    }

    /// Adds a line at the end, keeping whether the file ends with a line ending.
    private mutating func append(_ text: String) {
        guard let last = lines.last else {
            lines.append(Line(text: text, end: newline))
            return
        }
        if last.end.isEmpty {
            lines[lines.count - 1].end = newline
            lines.append(Line(text: text, end: ""))
        } else {
            lines.append(Line(text: text, end: newline))
        }
    }

    private mutating func remove(_ indices: [Int]) {
        for i in indices.sorted(by: >) {
            let wasLast = i == lines.count - 1
            let end = lines[i].end
            lines.remove(at: i)
            // The file did not end with a line ending: neither does it now.
            if wasLast, end.isEmpty, !lines.isEmpty { lines[lines.count - 1].end = "" }
        }
    }
}
