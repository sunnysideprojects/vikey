import Foundation
import ViKeyCore

// Shared with the Python reference engine: reference/cases.tsv (method, modern 0/1, keys, expected).
let casesFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../reference/cases.tsv").standardized
guard let casesText = try? String(contentsOf: casesFile, encoding: .utf8) else {
    print("ViKey self-test: cannot read \(casesFile.path)")
    exit(1)
}
let cases: [(String, Bool, String, String)] = casesText.split(separator: "\n").compactMap { line in
    let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    return f.count == 4 ? (f[0], f[1] == "1", f[2], f[3]) : nil
}

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

// Word-end restore, shared with the Python reference: reference/restore.tsv
// (method, modern 0/1, keys, the one word the dictionary knows or -, expected).
let restoreText = (try? String(contentsOf: casesFile.deletingLastPathComponent()
    .appendingPathComponent("restore.tsv"), encoding: .utf8)) ?? ""
let restoreCases = restoreText.split(separator: "\n").map { $0.split(separator: "\t").map(String.init) }
    .filter { $0.count == 5 }
if restoreCases.isEmpty {
    failures += 1
    print("RESTORE FAIL: cannot read reference/restore.tsv")
}
for f in restoreCases {
    let e = typeWord(f[2], method: InputMethod(rawValue: f[0])!, modern: f[1] == "1")
    let got = e.restoreIfNotWord(isWord: { $0 == f[3] }) ?? e.output
    if got != f[4] {
        failures += 1
        print("RESTORE FAIL [\(f[0])] \(f[2]) -> \(got) (expected \(f[4]))")
    }
}
// Esc revert, shared with the Python reference: reference/revert.tsv
// (method, keys, expected revert result or -, keys typed after, expected output).
let revertText = (try? String(contentsOf: casesFile.deletingLastPathComponent()
    .appendingPathComponent("revert.tsv"), encoding: .utf8)) ?? ""
let revertCases = revertText.split(separator: "\n")
    .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    .filter { $0.count == 5 }
if revertCases.isEmpty {
    failures += 1
    print("REVERT FAIL: cannot read reference/revert.tsv")
}
for f in revertCases {
    let e = typeWord(f[1], method: InputMethod(rawValue: f[0])!)
    let got = e.revert() ?? "-"
    for ch in f[3] { e.process(ch) }
    if got != f[2] || e.output != f[4] {
        failures += 1
        print("REVERT FAIL [\(f[0])] \(f[1]) -> \(got), \(e.output) (expected \(f[2]), \(f[4]))")
    }
}

let candidates = Vietnamese.syllableCandidates()
for w in ["khách", "ngày", "nghiêng", "thuở", "quýt", "gìn", "đồng", "khuỷu", "lă", "hòa", "thủy"]
    where !candidates.contains(w) {
    failures += 1
    print("SYLLABLE FAIL: \(w) not among \(candidates.count) candidates")
}
for w in ["hoà", "thuỷ", "Việt", "zô", "ýe"] where candidates.contains(w) {
    failures += 1
    print("SYLLABLE FAIL: \(w) should not be a candidate")
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

// MARK: - Versions (update check)

func v(_ s: String) -> AppVersion? { AppVersion(s) }
let newer: [(String, String)] = [("1.0.4", "1.0.3"), ("v1.0.10", "1.0.9"), ("2", "1.9.9"), ("1.1", "1.0.99"),
                                 ("1.0.0.1", "1.0")]
for (a, b) in newer {
    if let x = v(a), let y = v(b), x > y, !(y > x) { continue }
    failures += 1
    print("VERSION FAIL: expected \(a) > \(b)")
}
for (a, b) in [("1.0.3", "v1.0.3"), ("1.2", "1.2.0"), ("1.2.3-beta", "1.2.3"), (" v2.0 ", "2")] {
    if v(a) != nil, v(a) == v(b), !(v(a)! < v(b)!), !(v(b)! < v(a)!) { continue }
    failures += 1
    print("VERSION FAIL: expected \(a) == \(b)")
}
for bad in ["", "v", "beta", "1..2", "1.x", "١.٢"] where v(bad) != nil {
    failures += 1
    print("VERSION FAIL: '\(bad)' should not parse")
}
check("version description", v("v1.0.3")?.description, "1.0.3")

if failures == 0 {
    print("ViKey self-test: \(cases.count + restoreCases.count + revertCases.count + bsCases.count) cases + fuzz OK, \(candidates.count) syllable candidates")
} else {
    print("ViKey self-test: \(failures) failure(s)")
    exit(1)
}
