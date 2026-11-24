import Foundation
import ViKeyCore

// Generated from proto/cases.tsv — same cases as the Python reference engine.
let cases: [(String, Bool, String, String)] = [
    ("telex", false, "tieengs", "tiếng"),
    ("telex", false, "tiengse", "tiếng"),
    ("telex", false, "vieetj", "việt"),
    ("telex", false, "Vieetj", "Việt"),
    ("telex", false, "VIEETJ", "VIỆT"),
    ("telex", false, "dduowngf", "đường"),
    ("telex", false, "DDUWOWNGF", "ĐƯỜNG"),
    ("telex", false, "truowngf", "trường"),
    ("telex", false, "nguoiwf", "người"),
    ("telex", false, "nguwowif", "người"),
    ("telex", false, "duowcj", "dược"),
    ("telex", false, "dduwowcj", "được"),
    ("telex", false, "hoaf", "hòa"),
    ("telex", true, "hoaf", "hoà"),
    ("telex", false, "hoangf", "hoàng"),
    ("telex", false, "thuyr", "thủy"),
    ("telex", true, "thuyr", "thuỷ"),
    ("telex", false, "cuar", "của"),
    ("telex", false, "quar", "quả"),
    ("telex", false, "quys", "quý"),
    ("telex", false, "gif", "gì"),
    ("telex", false, "giaf", "già"),
    ("telex", false, "giuwx", "giữ"),
    ("telex", false, "muwa", "mưa"),
    ("telex", false, "mwa", "mưa"),
    ("telex", false, "w", "ư"),
    ("telex", false, "nhw", "như"),
    ("telex", false, "tuaans", "tuấn"),
    ("telex", false, "khuyeenx", "khuyễn"),
    ("telex", false, "khuyar", "khuỷa"),
    ("telex", false, "oais", "oái"),
    ("telex", false, "ngoeos", "ngoéo"),
    ("telex", false, "thuowr", "thuở"),
    ("telex", false, "aaa", "aa"),
    ("telex", false, "ass", "as"),
    ("telex", false, "ddd", "dd"),
    ("telex", false, "tesst", "test"),
    ("telex", false, "windows", "windows"),
    ("telex", false, "class", "class"),
    ("telex", false, "google", "google"),
    ("telex", false, "facebook", "facebook"),
    ("telex", false, "teams", "teams"),
    ("telex", false, "data", "dât"),
    ("telex", false, "matf", "matf"),
    ("telex", false, "mats", "mát"),
    ("telex", false, "matj", "mạt"),
    ("telex", false, "tooi", "tôi"),
    ("telex", false, "ddaay", "đây"),
    ("telex", false, "laf", "là"),
    ("telex", false, "vaanx", "vẫn"),
    ("telex", false, "chuyeenj", "chuyện"),
    ("telex", false, "ngheef", "nghề"),
    ("telex", false, "xooong", "xoong"),
    ("telex", false, "asz", "a"),
    ("telex", false, "tafi", "tài"),
    ("telex", false, "tais", "tái"),
    ("telex", false, "hoas", "hóa"),
    ("telex", false, "baws", "bắ"),
    ("telex", false, "awn", "ăn"),
    ("telex", false, "thuwowng", "thương"),
    ("telex", false, "yeeu", "yêu"),
    ("telex", false, "nuwowcs", "nước"),
    ("telex", false, "uw", "ư"),
    ("telex", false, "ww", "w"),
    ("telex", false, "nhaatj", "nhật"),
    ("vni", false, "tie6ng1", "tiếng"),
    ("vni", false, "vie6t5", "việt"),
    ("vni", false, "d9u7o7ng2", "đường"),
    ("vni", false, "duong7", "dương"),
    ("vni", false, "nguoi72", "người"),
    ("vni", false, "hoa2", "hòa"),
    ("vni", true, "hoa2", "hoà"),
    ("vni", false, "a8n", "ăn"),
    ("vni", false, "a66", "a6"),
    ("vni", false, "a11", "a1"),
    ("vni", false, "mu7a", "mưa"),
    ("vni", false, "thuy3", "thủy"),
    ("vni", false, "d99", "d9"),
    ("telex", false, "huow", "huơ"),
    ("telex", false, "uwoww", "uwow"),
    ("telex", false, "hello", "hello"),
    ("telex", false, "you", "you"),
    ("telex", false, "word", "word"),
    ("telex", false, "new", "new"),
    ("telex", false, "the", "the"),
    ("vni", false, "u7o7", "uơ"),
    ("vni", false, "u7o7ng", "ương"),
]

var failures = 0

func typeWord(_ input: String, method: InputMethod, modern: Bool = false) -> Engine {
    let e = Engine(method: method, modernTone: modern)
    for ch in input { e.process(ch) }
    return e
}

for (m, modern, input, expected) in cases {
    let got = typeWord(input, method: InputMethod(rawValue: m)!, modern: modern).output
    if got != expected {
        failures += 1
        print("FAIL [\(m)] \(input) -> \(got) (expected \(expected))")
    }
}

// Backspace: delete n chars, keep typing, compare.
let bsCases: [(String, Int, String, String)] = [
    ("tieengs", 1, "h", "tiếnh"),
    ("tieengs", 2, "t", "tiết"),
    ("dduwowcj", 1, "", "đượ"),
    ("tesst", 1, "t", "test"),
    ("vieetj", 3, "ieetj", "việt"),
]
for (word, n, more, expected) in bsCases {
    let e = typeWord(word, method: .telex)
    for _ in 0..<n { e.backspace() }
    for ch in more { e.process(ch) }
    if e.output != expected {
        failures += 1
        print("BACKSPACE FAIL \(word) -\(n) +\(more) -> \(e.output) (expected \(expected))")
    }
}

// Fuzz: after any word, backspace must remove exactly one character from the output.
var seed: UInt64 = 42
func rand(_ n: Int) -> Int {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Int((seed >> 33) % UInt64(n))
}
let alphabet = Array("aeiouywdsfrxjzngthcmqAEW")
for _ in 0..<20000 {
    let method: InputMethod = rand(2) == 0 ? .telex : .vni
    let al = alphabet + (method == .vni ? Array("0123456789") : [])
    let word = String((0..<(1 + rand(10))).map { _ in al[rand(al.count)] })
    let e = typeWord(word, method: method, modern: rand(2) == 0)
    let before = e.output
    e.backspace()
    if e.output != String(before.dropLast()) {
        failures += 1
        print("FUZZ FAIL [\(method)] \(word): \(before) -> \(e.output)")
        break
    }
}

// MARK: - Abbreviations (gõ tắt)

func check(_ label: String, _ got: String?, _ expected: String?) {
    if got != expected {
        failures += 1
        print("MACRO FAIL \(label): \(got ?? "nil") (expected \(expected ?? "nil"))")
    }
}

// UniKey file: UTF-8 BOM, CRLF, header line, a ':' inside the value.
let ukmacro = "\u{FEFF};DO NOT DELETE THIS LINE*** version=1 ***\r\n~:những\r\ndc:được\r\nk0:không\r\n"
    + "k0g:Không\r\nntn:như thế nào\r\nurl:http://x.vn\r\nbad line\r\n:novalue\r\n"
let table = MacroTable(data: ukmacro.data(using: .utf8)!)
check("count", String(table.count), "6")
check("dc", table.lookup("dc"), "được")
check("Dc", table.lookup("Dc"), "Được")
check("DC", table.lookup("DC"), "ĐƯỢC")
check("k0g exact", table.lookup("k0g"), "Không")
check("K0", table.lookup("K0"), "Không")
check("ntn", table.lookup("ntn"), "như thế nào")
check("url", table.lookup("url"), "http://x.vn")
check("~", table.lookup("~"), "những")
check("miss", table.lookup("d"), nil)
check("prefix ~", String(table.isPrefix("~")), "true")
check("prefix k0", String(table.isPrefix("K0")), "true")
check("prefix dc.", String(table.isPrefix("dc.")), "false")
var utf16 = Data([0xFF, 0xFE])
utf16.append("x;y\nvs:với\n".data(using: .utf16LittleEndian)!)
check("utf16", MacroTable(data: utf16).lookup("vs"), "với")

// Every key in a real UniKey file must show up on screen unchanged when typed, in both methods,
// or the key could never match. Mirrors KeyTap: letters (and VNI digits inside a word) go to the
// engine; any other character closes the engine word but stays in the token.
func screenText(_ keys: String, method: InputMethod) -> String {
    let e = Engine(method: method)
    var prefix = ""
    for ch in keys {
        let engineKey = ch.isASCII && (ch.isLetter || (method == .vni && ch.isNumber && !e.output.isEmpty))
        if engineKey { e.process(ch) } else { prefix += e.output + String(ch); e.reset() }
    }
    return prefix + e.output
}
let realFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../ukmacro.txt").standardized
if let data = try? Data(contentsOf: realFile) {
    let entries = MacroTable.parse(MacroTable.decode(data))
    for (key, _) in entries {
        for m in InputMethod.allCases {
            let shown = screenText(key, method: m)
            if MacroTable(data: data).lookup(shown) == nil {
                failures += 1
                print("MACRO FAIL [\(m)] key \(key) shows as \(shown)")
            }
        }
    }
    print("ukmacro.txt: \(entries.count) entries checked")
}

if failures == 0 {
    print("ViKey self-test: \(cases.count + bsCases.count) cases + fuzz OK")
} else {
    print("ViKey self-test: \(failures) failure(s)")
    exit(1)
}
