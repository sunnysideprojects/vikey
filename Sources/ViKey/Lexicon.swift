import AppKit
import ViKeyCore

/// The Vietnamese syllables that are real words, for restoring English words at word end
/// (`law` -> `lă` -> `law`). Taken from the macOS Vietnamese spelling dictionary: every syllable the
/// rules allow (~32k) is checked once (~6.7k are real), and the result is cached in Application
/// Support per macOS version, so nothing is shipped with the app.
///
/// Until the list is ready, or if the dictionary is missing or looks wrong, every word counts as
/// real: ViKey then never restores, which is the old behavior.
final class VietnameseLexicon {
    private var words: Set<String>?
    var isReady: Bool { words != nil }

    func contains(_ word: String) -> Bool { words?.contains(word) ?? true }

    private static let batch = 50  // ~10 ms of spell checks per main-thread turn, so typing stays smooth
    private static let plausible = 3_000...15_000

    private var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ViKey/syllables.txt")
    }

    func load() {
        let candidates = Vietnamese.syllableCandidates()
        let stamp = "\(ProcessInfo.processInfo.operatingSystemVersionString) | \(candidates.count)"
        if let url = cacheURL, let text = try? String(contentsOf: url, encoding: .utf8) {
            var lines = text.split(separator: "\n").map(String.init)
            if lines.first == stamp {
                lines.removeFirst()
                if Self.plausible.contains(lines.count) {
                    words = Set(lines)
                    return
                }
            }
        }
        let checker = NSSpellChecker.shared
        guard checker.availableLanguages.contains("vi") else { return }
        _ = Self.known("việt", checker)  // the first call can time out while the spell server starts
        // NSSpellChecker is main-thread only: check in small batches between key events.
        var found: [String] = []
        var index = 0
        func step() {
            let end = min(index + Self.batch, candidates.count)
            for w in candidates[index..<end] where Self.known(w, checker) { found.append(w) }
            index = end
            if index < candidates.count {
                DispatchQueue.main.async(execute: step)
                return
            }
            guard Self.plausible.contains(found.count) else { return }
            words = Set(found)
            if let url = cacheURL {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? ([stamp] + found).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
        DispatchQueue.main.async(execute: step)
    }

    private static func known(_ word: String, _ checker: NSSpellChecker) -> Bool {
        checker.checkSpelling(of: word, startingAt: 0, language: "vi", wrap: false,
                              inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }
}
