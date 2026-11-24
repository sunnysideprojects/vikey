import Foundation

enum Mod: Equatable {
    case none, hat, breve, horn, stroke
}

struct Letter {
    var base: Character
    var mod: Mod = .none
    var upper: Bool = false
}

typealias NucleusChar = (base: Character, mod: Mod)

/// Vietnamese orthography tables and syllable rules.
enum Vietnamese {
    static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    static let moddedVowels: [Character: NucleusChar] = [
        "ă": ("a", .breve), "â": ("a", .hat), "ê": ("e", .hat),
        "ô": ("o", .hat), "ơ": ("o", .horn), "ư": ("u", .horn),
    ]

    static func nucleus(_ s: Substring) -> [NucleusChar] {
        s.map { moddedVowels[$0] ?? ($0, .none) }
    }

    /// Every vowel cluster that can form a syllable nucleus.
    static let nuclei: [[NucleusChar]] = (
        "a ă â e ê i o ô ơ u ư y ai ao au ay âu ây eo êu ia iê iu oa oă oe oi ôi ơi oo "
            + "ua uâ uê ui uô uơ ưa ưi ươ ưu uy yê iêu yêu oai oao oay oeo uây uôi uya uyê uyu ươi ươu"
    ).split(separator: " ").map(nucleus)

    /// Nuclei that may be followed by a coda consonant.
    static let finalNuclei: [[NucleusChar]] =
        "a ă â e ê i o ô ơ u ư iê oa oă oe oo uâ uê uô ươ uy uyê yê".split(separator: " ").map(nucleus)

    static let initials: Set<String> = Set(
        "b c ch d g gh h k kh l m n ng ngh nh p ph q r s t th tr v x".split(separator: " ").map(String.init)
    ).union([""])

    static let finals: Set<String> = ["c", "ch", "m", "n", "ng", "nh", "p", "t"]
    static let stopFinals: Set<String> = ["c", "ch", "p", "t"]

    /// Index = tone: 0 none, 1 sắc, 2 huyền, 3 hỏi, 4 ngã, 5 nặng.
    static let toneMarks: [String] = ["", "\u{0301}", "\u{0300}", "\u{0309}", "\u{0303}", "\u{0323}"]

    static func modMark(_ m: Mod) -> String {
        switch m {
        case .hat: return "\u{0302}"
        case .breve: return "\u{0306}"
        case .horn: return "\u{031B}"
        default: return ""
        }
    }

    static func compatible(_ g: [NucleusChar], _ n: [NucleusChar], full: Bool) -> Bool {
        if g.count > n.count || (full && g.count != n.count) { return false }
        for (a, b) in zip(g, n) where a.base != b.base || !(a.mod == b.mod || a.mod == .none) {
            return false
        }
        return true
    }
}

/// Splits letters into initial consonant / vowel group / coda consonant.
struct Syllable {
    var initial: String
    var group: [Int]
    var coda: String
    var codaHasVowel: Bool

    init(_ letters: [Letter]) {
        let v = Vietnamese.vowels
        let n = letters.count
        var i = 0
        while i < n && !v.contains(letters[i].base) { i += 1 }
        var j = i
        while j < n && v.contains(letters[j].base) { j += 1 }
        initial = String(letters[0..<i].map { $0.base })
        group = Array(i..<j)
        coda = String(letters[j..<n].map { $0.base })
        codaHasVowel = letters[j..<n].contains { v.contains($0.base) }
        // In "qu" and "gi" the u / i belongs to the initial consonant.
        if initial == "q", let f = group.first, letters[f].base == "u" {
            group.removeFirst()
            initial = "qu"
        } else if initial == "g", group.count > 1, letters[group[0]].base == "i" {
            group.removeFirst()
            initial = "gi"
        }
    }
}

extension Vietnamese {
    /// True if `letters` is a Vietnamese syllable, or a prefix of one still being typed.
    static func isValid(_ letters: [Letter], tone: Int) -> Bool {
        if letters.isEmpty { return true }
        for (k, l) in letters.enumerated() {
            if l.mod == .stroke && !(k == 0 && l.base == "d") { return false }
            if !vowels.contains(l.base) && l.mod != .none && l.mod != .stroke { return false }
        }
        let s = Syllable(letters)
        if s.codaHasVowel { return false }
        if !initials.contains(s.initial) && s.initial != "qu" && s.initial != "gi" { return false }
        if s.initial == "q" && letters.count > 1 { return false }
        let g: [NucleusChar] = s.group.map { (letters[$0].base, letters[$0].mod) }
        if !s.coda.isEmpty {
            guard finals.contains(s.coda), !g.isEmpty else { return false }
            guard finalNuclei.contains(where: { compatible(g, $0, full: true) }) else { return false }
            if stopFinals.contains(s.coda) && (2...4).contains(tone) { return false }
        } else if !g.isEmpty && !nuclei.contains(where: { compatible(g, $0, full: false) }) {
            return false
        }
        if tone != 0 && g.isEmpty { return false }
        return true
    }

    /// Index of the letter that carries the tone mark.
    static func tonePosition(_ letters: [Letter], modern: Bool) -> Int? {
        let s = Syllable(letters)
        let g = s.group
        guard !g.isEmpty else { return nil }
        if let last = g.last(where: { letters[$0].mod != .none }) { return last }
        if g.count == 1 { return g[0] }
        if g.count >= 3 { return g[1] }
        if !s.coda.isEmpty { return g[1] }
        let pair = String([letters[g[0]].base, letters[g[1]].base])
        if modern && ["oa", "oe", "uy"].contains(pair) { return g[1] }
        return g[0]
    }

    static func render(_ letters: [Letter], tone: Int, modern: Bool) -> String {
        let pos = tone != 0 ? tonePosition(letters, modern: modern) : nil
        let s = Syllable(letters)
        let g = s.group
        // Open syllable ending in "ươ" is written "uơ" (thuở, huơ).
        var plainU = -1
        if s.coda.isEmpty, g.count >= 2, g.last == letters.count - 1 {
            let a = letters[g[g.count - 2]], b = letters[g[g.count - 1]]
            if a.base == "u" && a.mod == .horn && b.base == "o" && b.mod == .horn { plainU = g[g.count - 2] }
        }
        var out = ""
        for (k, l) in letters.enumerated() {
            var piece: String
            if l.mod == .stroke {
                piece = "đ"
            } else {
                piece = String(l.base)
                if k != plainU { piece += modMark(l.mod) }
                if k == pos { piece += toneMarks[tone] }
                piece = piece.precomposedStringWithCanonicalMapping
            }
            out += l.upper ? piece.uppercased() : piece
        }
        return out
    }
}
