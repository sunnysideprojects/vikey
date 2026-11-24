import Foundation

/// A dotted numeric version such as "1.0.3" or a tag such as "v1.2". Missing parts count as 0
/// (1.2 == 1.2.0); a suffix after the numbers ("1.2.3-beta") is ignored. Swift only, not in the
/// Python reference (it is not part of the engine).
public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var t = Substring(text.trimmingCharacters(in: .whitespaces))
        if t.first == "v" || t.first == "V" { t = t.dropFirst() }
        let core = t.prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !core.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.map { $0! }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private static func compare(_ a: AppVersion, _ b: AppVersion) -> Int {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool { compare(a, b) < 0 }
    public static func == (a: AppVersion, b: AppVersion) -> Bool { compare(a, b) == 0 }
}
