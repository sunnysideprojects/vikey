import Foundation

/// What was typed on screen since the caret last moved, up to the word the engine holds. Lets a
/// backspace step back into the previous word: delete the space after `tiêng` and the word is
/// handed back to the engine, so `s` still makes `tiếng`.
///
/// The caller appends every finished word with the space or punctuation that ended it, and clears
/// it whenever the screen may differ (click, arrows, Return, Tab, app switch...).
public struct RecentText {
    public private(set) var text = ""
    /// Kept short: only the end matters, and a long history is more likely to be stale.
    static let limit = 120
    /// Longer runs of letters are not words the engine could pick up.
    static let maxWord = 24

    public init() {}

    public mutating func clear() { text = "" }

    public mutating func append(_ s: String) {
        text += s
        guard text.count > Self.limit else { return }
        // Cut at a separator, so the oldest word left is never half a word.
        var rest = text.dropFirst(text.count - Self.limit)
        if let cut = rest.firstIndex(where: { !$0.isLetter }) {
            rest = rest[rest.index(after: cut)...]
        } else {
            rest = ""
        }
        text = String(rest)
    }

    /// The app removed these characters from the end (an abbreviation replaced its key).
    public mutating func dropLast(_ n: Int) {
        text = String(text.dropLast(n))
    }

    /// The app deleted the last character before the caret (no word was in progress). If that
    /// was the space or punctuation right after a word, returns the word and removes it from
    /// `text`: it is now the word in progress. `resume` false only keeps `text` in step.
    public mutating func backspace(resume: Bool) -> String? {
        guard let deleted = text.popLast(), resume, !deleted.isLetter else { return nil }
        let word = text.reversed().prefix(while: \.isLetter)
        guard !word.isEmpty, word.count <= Self.maxWord else { return nil }
        text.removeLast(word.count)
        return String(word.reversed())
    }
}
