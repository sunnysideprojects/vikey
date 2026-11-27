import Foundation

/// Whole-text conversions for the clipboard tools (UniKey's "toolkit"). Swift only, not in the
/// Python reference: they do not touch the typing engine.
public enum TextTool: String, CaseIterable {
    case removeAccents, upper, lower, titleCase, fromTCVN3, fromVNI, composeNFC

    private static let vi = Locale(identifier: "vi_VN")

    public func apply(_ s: String) -> String {
        switch self {
        case .removeAccents: return Self.removeAccents(s)
        case .upper: return s.uppercased(with: Self.vi)
        case .lower: return s.lowercased(with: Self.vi)
        case .titleCase: return Self.titleCase(s)
        case .fromTCVN3: return Self.fromTCVN3(s)
        case .fromVNI: return Self.fromVNI(s)
        case .composeNFC: return s.precomposedStringWithCanonicalMapping
        }
    }

    // MARK: - Accents and case

    /// `Tiếng Việt` -> `Tieng Viet`, `Đà Nẵng` -> `Da Nang`.
    static func removeAccents(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch u.value {
            case 0x0300...0x036F: continue  // combining marks
            case 0x0111: out.append("d")
            case 0x0110: out.append("D")
            default: out.append(u)
            }
        }
        return String(out).precomposedStringWithCanonicalMapping
    }

    /// First letter of every word upper case, the rest lower case: `NGUYỄN văn a` -> `Nguyễn Văn A`.
    static func titleCase(_ s: String) -> String {
        var out = ""
        var startOfWord = true
        for ch in s {
            let piece = String(ch)
            out += startOfWord ? piece.uppercased(with: vi) : piece.lowercased(with: vi)
            startOfWord = !(ch.isLetter || ch.isNumber || ch == "'" || ch == "’")
        }
        return out
    }

    // MARK: - Legacy encodings

    /// TCVN3 (ABC, .VnTime fonts): one byte per letter, read as Windows-1252/Latin-1 when copied.
    /// Toned capitals live in separate "H" fonts with the same codes, so they come out lower case.
    private static let tcvn3: [Character: Character] = {
        let pairs = "¡Ă ¢Â £Ê ¤Ô ¥Ơ ¦Ư §Đ ¨ă ©â ªê «ô ¬ơ \u{AD}ư ®đ "
            + "µà ¶ả ·ã ¸á ¹ạ »ằ ¼ẳ ½ẵ ¾ắ Æặ Çầ Èẩ Éẫ Êấ Ëậ "
            + "Ìè Îẻ Ïẽ Ðé Ñẹ Òề Óể Ôễ Õế Öệ ×ì Øỉ Üĩ Ýí Þị "
            + "ßò áỏ âõ ãó äọ åồ æổ çỗ èố éộ êờ ëở ìỡ íớ îợ "
            + "ïù ñủ òũ óú ôụ õừ öử ÷ữ øứ ùự úỳ ûỷ üỹ ýý þỵ "
            // TCVN 5712 VN1 also puts some toned capitals in this range (as iconv's TCVN does).
            + "¯Ằ ºẲ ¿Ẵ ÀẮ ÁẦ ÂẨ ÃẪ ÄẤ ÅỀ ÍỂ ÙỄ ÚẾ ÛỒ àỔ ðỖ ÿỐ"
        var map: [Character: Character] = [:]
        for p in pairs.split(separator: " ") { map[p.first!] = p.last! }
        return map
    }()

    /// `Hµ Néi` -> `Hà Nội`.
    static func fromTCVN3(_ s: String) -> String {
        String(s.map { tcvn3[$0] ?? $0 })
    }

    /// VNI Windows (VNI-Times fonts): a base letter followed by a mark character (`Vieät` = Việt),
    /// plus a few single characters for ơ, ư, đ and some i/y forms.
    private static let vniSingle: [Character: String] = [
        "ô": "ơ", "Ô": "Ơ", "ö": "ư", "Ö": "Ư", "ñ": "đ", "Ñ": "Đ",
        "í": "í", "Í": "Í", "ì": "ì", "Ì": "Ì", "æ": "ỉ", "Æ": "Ỉ",
        "ó": "ĩ", "Ó": "Ĩ", "ò": "ị", "Ò": "Ị", "î": "ỵ", "Î": "Ỵ",
    ]

    private enum Shape { case tone, hat, breve }

    /// Mark character -> (combining marks, which bases accept it).
    private static let vniMarks: [Character: (String, Shape)] = {
        let acute = "\u{0301}", grave = "\u{0300}", hook = "\u{0309}", tilde = "\u{0303}", dot = "\u{0323}"
        let hat = "\u{0302}", breve = "\u{0306}"
        let lower: [(Character, String, Shape)] = [
            ("ù", acute, .tone), ("ø", grave, .tone), ("û", hook, .tone), ("õ", tilde, .tone), ("ï", dot, .tone),
            ("â", hat, .hat), ("á", hat + acute, .hat), ("à", hat + grave, .hat),
            ("å", hat + hook, .hat), ("ã", hat + tilde, .hat), ("ä", hat + dot, .hat),
            ("ê", breve, .breve), ("é", breve + acute, .breve), ("è", breve + grave, .breve),
            ("ú", breve + hook, .breve), ("ü", breve + tilde, .breve), ("ë", breve + dot, .breve),
        ]
        var map: [Character: (String, Shape)] = [:]
        for (ch, marks, shape) in lower {
            map[ch] = (marks, shape)
            map[Character(String(ch).uppercased())] = (marks, shape)
        }
        return map
    }()

    /// `Coäng hoøa xaõ hoäi chuû nghóa Vieät Nam` -> `Cộng hòa xã hội chủ nghĩa Việt Nam`.
    static func fromVNI(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var i = 0
        while i < chars.count {
            let base = vniSingle[chars[i]] ?? String(chars[i])
            i += 1
            if i < chars.count, let (marks, shape) = vniMarks[chars[i]], accepts(base, shape) {
                out += (base + marks).precomposedStringWithCanonicalMapping
                i += 1
            } else {
                out += base
            }
        }
        return out
    }

    private static func accepts(_ base: String, _ shape: Shape) -> Bool {
        let b = base.lowercased()
        switch shape {
        case .tone: return ["a", "e", "i", "o", "u", "y", "ơ", "ư"].contains(b)
        case .hat: return ["a", "e", "o"].contains(b)
        case .breve: return b == "a"
        }
    }
}
