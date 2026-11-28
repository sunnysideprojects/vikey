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

// Resume an earlier word, shared with the Python reference: reference/resume.tsv
// (method, word on screen, keys typed after, expected output).
let resumeText = (try? String(contentsOf: casesFile.deletingLastPathComponent()
    .appendingPathComponent("resume.tsv"), encoding: .utf8)) ?? ""
let resumeCases = resumeText.split(separator: "\n")
    .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    .filter { $0.count == 4 }
if resumeCases.isEmpty {
    failures += 1
    print("RESUME FAIL: cannot read reference/resume.tsv")
}
for f in resumeCases {
    let e = Engine(method: InputMethod(rawValue: f[0])!)
    e.resume(f[1])
    for ch in f[2] { e.process(ch) }
    if e.output != f[3] {
        failures += 1
        print("RESUME FAIL [\(f[0])] \(f[1]) +\(f[2]) -> \(e.output) (expected \(f[3]))")
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

// Backspace into the previous word. Mirrors KeyTap: letters go to the engine, a space or
// punctuation ends the word into RecentText, "<" is a backspace the app has already applied.
// After every key, RecentText + the engine word must equal what a plain editor would show.
func typeLine(_ keys: String, method: InputMethod = .telex, resume: Bool = true) -> String {
    let e = Engine(method: method)
    var recent = RecentText()
    var screen = ""
    for ch in keys {
        if ch == "<" {
            screen = String(screen.dropLast())
            if !e.backspace(), let word = recent.backspace(resume: resume) { e.resume(word) }
        } else if ch.isLetter || (method == .vni && ch.isNumber && !e.output.isEmpty) {
            let before = e.output
            screen = String(screen.dropLast(before.count)) + e.process(ch)
        } else {
            recent.append(e.output + String(ch))
            e.reset()
            screen.append(ch)
        }
        if recent.text + e.output != screen {
            failures += 1
            print("RECENT FAIL \(keys): tracked \(recent.text)|\(e.output), screen \(screen)")
            break
        }
    }
    return screen
}
let lineCases: [(String, InputMethod, Bool, String)] = [
    ("tieeng <s", .telex, true, "tiếng"),
    ("tieeng <s", .telex, false, "tiêngs"),
    ("tieeng <<s", .telex, true, "tiến"),
    ("xin chao <f", .telex, true, "xin chào"),
    ("xin chao <<<<<<f", .telex, true, "xìn"),
    ("toi. <<s", .telex, true, "tói"),
    ("a.b<<s", .telex, true, "á"),
    ("law <s", .telex, true, "lắ"),  // no English restore in this model
    ("tieng <1", .vni, true, "tiéng"),
    ("toi6 <1", .vni, true, "tối"),
    ("<<a", .telex, true, "a"),
]
for (keys, method, resume, expected) in lineCases {
    let got = typeLine(keys, method: method, resume: resume)
    if got != expected {
        failures += 1
        print("RECENT FAIL [\(method)] \(keys) -> \(got) (expected \(expected))")
    }
}
var longText = RecentText()
for _ in 0..<40 { longText.append("abc de ") }
if longText.text.count > 120 || !longText.text.hasPrefix("abc de") {
    failures += 1
    print("RECENT FAIL: trimmed to \(longText.text.count) chars starting \(longText.text.prefix(8))")
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

// Editing: the file comes back byte for byte, an edit touches only its own line, and a value the
// user did not see (changed on another machine) is a conflict unless forced.
func bytes(_ s: String, bom: Bool = false) -> Data { (bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(s.utf8) }
func checkDoc(_ label: String, _ doc: MacroDocument, _ expected: Data) {
    if doc.data() != expected {
        failures += 1
        let got = String(data: doc.data(), encoding: .utf8) ?? doc.data().map { String($0) }.joined(separator: " ")
        print("MACRO EDIT FAIL \(label): \(got.debugDescription)")
    }
}
var utf16BE = Data([0xFE, 0xFF])
utf16BE.append(";h\r\nvs:với\r\n".data(using: .utf16BigEndian)!)
let roundTrips: [(String, Data)] = [
    ("unikey", ukmacro.data(using: .utf8)!),
    ("utf16le", utf16), ("utf16be", utf16BE),
    ("mixed endings, no final newline", bytes(";h\r\na:b\nc:d\re:f")),
    ("empty", Data()),
]
for (label, data) in roundTrips { checkDoc("round trip \(label)", MacroDocument(data: data), data) }

let header = ";DO NOT DELETE THIS LINE*** version=1 ***"
let base = header + "\r\n; comment\r\ndc:được\r\n  k0 :không\r\nvs:với"  // no final CRLF, as UniKey writes
var doc = MacroDocument(data: bytes(base, bom: true))
check("doc entries", doc.entries.map { "\($0.key)=\($0.value)" }.joined(separator: ","), "dc=được,k0=không,vs=với")
check("add", "\(doc.apply(.add(key: "ntn", value: "như thế nào")))", "applied")
checkDoc("add", doc, bytes(base + "\r\nntn:như thế nào", bom: true))
check("add same", "\(doc.apply(.add(key: "ntn", value: "như thế nào")))", "unchanged")
check("add taken", "\(doc.apply(.add(key: "dc", value: "đúng")))", "conflict(current: Optional(\"được\"))")
doc = MacroDocument(data: bytes(base, bom: true))
check("update", "\(doc.apply(.update(key: "k0", expected: "không", newKey: "k0", value: "Không")))", "applied")
checkDoc("update", doc, bytes(header + "\r\n; comment\r\ndc:được\r\nk0:Không\r\nvs:với", bom: true))
check("update stale", "\(doc.apply(.update(key: "k0", expected: "không", newKey: "k0", value: "ko")))",
      "conflict(current: Optional(\"Không\"))")
check("update forced", "\(doc.apply(.update(key: "k0", expected: "không", newKey: "k0", value: "ko"), force: true))",
      "applied")
check("update gone", "\(doc.apply(.update(key: "xx", expected: "a", newKey: "xx", value: "b")))", "conflict(current: nil)")
check("rename taken", "\(doc.apply(.update(key: "dc", expected: "được", newKey: "vs", value: "x")))",
      "invalid(\"Đã có phím tắt vs.\")")
doc = MacroDocument(data: bytes(base, bom: true))
check("remove last", "\(doc.apply(.remove(key: "vs", expected: "với")))", "applied")
checkDoc("remove last", doc, bytes(header + "\r\n; comment\r\ndc:được\r\n  k0 :không", bom: true))
check("remove gone", "\(doc.apply(.remove(key: "vs", expected: "với")))", "unchanged")
check("remove stale", "\(doc.apply(.remove(key: "dc", expected: "đc")))", "conflict(current: Optional(\"được\"))")
// Another machine added a line meanwhile: the edit is applied on top of it, nothing is lost.
doc = MacroDocument(data: bytes(base + "\r\nmoi:mới", bom: true))
_ = doc.apply(.update(key: "dc", expected: "được", newKey: "dc", value: "Được"))
checkDoc("merge", doc, bytes(header + "\r\n; comment\r\ndc:Được\r\n  k0 :không\r\nvs:với\r\nmoi:mới", bom: true))
// Renaming drops a second line for the old key, which would otherwise show up under it.
doc = MacroDocument(data: bytes("a:1\nb:2\na:3\n"))
_ = doc.apply(.update(key: "a", expected: "1", newKey: "c", value: "1"))
checkDoc("rename duplicate", doc, bytes("c:1\nb:2\n"))
doc = MacroDocument(data: utf16)
_ = doc.apply(.add(key: "ko", value: "không"))
var utf16Added = Data([0xFF, 0xFE])
utf16Added.append("x;y\nvs:với\nko:không\n".data(using: .utf16LittleEndian)!)
checkDoc("utf16 add", doc, utf16Added)
doc = MacroDocument(data: Data())
_ = doc.apply(.add(key: "a", value: "b"))
checkDoc("empty add", doc, bytes("a:b\r\n"))
checkDoc("new file", MacroDocument.newFile(), bytes(header, bom: true))
doc = MacroDocument(data: Data([0x61, 0x3A, 0xE9]))  // "a:é" in Latin-1: not UTF-8
check("latin1 readable", doc.value(for: "a"), "é")
check("latin1 read-only", "\(doc.apply(.add(key: "b", value: "c")))",
      "invalid(\"File không phải UTF-8 hay UTF-16, ViKey không sửa được.\")")
check("bad key colon", MacroDocument.problem(key: "a:b", value: "x"), "Phím tắt không được có dấu hai chấm (:).")
check("bad key space", MacroDocument.problem(key: "a b", value: "x"), "Phím tắt không được có dấu cách.")
check("bad newline", MacroDocument.problem(key: "ab", value: "x\ny"), "Không được xuống dòng.")
check("ok key", MacroDocument.problem(key: " ab ", value: "x"), nil)
// NFD typed or pasted in: written as NFC, found again by its NFC form.
doc = MacroDocument(data: Data())
_ = doc.apply(.add(key: "đc", value: "đu\u{031B}o\u{031B}\u{0323}c"))
check("nfc", doc.value(for: "đc").map { String($0.unicodeScalars.count) }, "4")  // đ ư ợ c

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

// MARK: - Clipboard tools

let toolCases: [(TextTool, String, String)] = [
    (.removeAccents, "Tiếng Việt, Đà Nẵng, thuở, ngoằn ngoèo", "Tieng Viet, Da Nang, thuo, ngoan ngoeo"),
    (.removeAccents, "Ti\u{0065}\u{0302}\u{0301}ng", "Tieng"),
    (.upper, "đường phố Hà Nội", "ĐƯỜNG PHỐ HÀ NỘI"),
    (.lower, "ĐƯỜNG PHỐ HÀ NỘI", "đường phố hà nội"),
    (.titleCase, "NGUYỄN văn a, đỗ thị-bình (hà nội)", "Nguyễn Văn A, Đỗ Thị-Bình (Hà Nội)"),
    (.fromTCVN3, "Hµ Néi, §µ N½ng, TiÕng ViÖt, ®­êng, Th¸i B×nh", "Hà Nội, Đà Nẵng, Tiếng Việt, đường, Thái Bình"),
    (.fromTCVN3, "Céng hoµ x· héi chñ nghÜa ViÖt Nam", "Cộng hoà xã hội chủ nghĩa Việt Nam"),
    (.fromVNI, "Coäng hoøa xaõ hoäi chuû nghóa Vieät Nam", "Cộng hòa xã hội chủ nghĩa Việt Nam"),
    (.fromVNI, "Ñaø Naüng, ñöôïc, ngöôøi, THAØNH PHOÁ HOÀ CHÍ MINH", "Đà Nẵng, được, người, THÀNH PHỐ HỒ CHÍ MINH"),
    (.fromVNI, "kyõ thuaät, ñaëc bieät, khuyûu, Ñ", "kỹ thuật, đặc biệt, khuỷu, Đ"),
    (.composeNFC, "Vi\u{0065}\u{0323}\u{0302}t", "Việt"),
]
for (tool, input, expected) in toolCases {
    let got = tool.apply(input)
    if got != expected || got.unicodeScalars.count != expected.unicodeScalars.count {
        failures += 1
        print("TOOL FAIL \(tool) \(input) -> \(got) (expected \(expected))")
    }
}

let caseCounts: [Int] = [cases.count, restoreCases.count, revertCases.count, resumeCases.count, bsCases.count,
                         lineCases.count, toolCases.count]
if failures == 0 {
    print("ViKey self-test: \(caseCounts.reduce(0, +)) cases + fuzz OK, \(candidates.count) syllable candidates")
} else {
    print("ViKey self-test: \(failures) failure(s)")
    exit(1)
}
