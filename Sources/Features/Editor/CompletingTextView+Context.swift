import AppKit

/// What the caret is sitting in, and what that offers.
///
/// The rule the whole feature turns on, kept apart from the view that acts on it: five
/// triggers, one of them a wikilink and three of them a single punctuation mark under one
/// shared rule. Its own file because `CompletingTextView` is at the length the linter allows.
extension CompletingTextView {
    /// Which of the five triggers the caret is sitting in, if any.
    enum Context {
        case wikilink(prefix: String)
        /// `[[Nota#pre`, where the note is already named and a heading of *that* note is
        /// being typed. Kept apart from `.wikilink` because the candidates come from a
        /// different place and only the part after the `#` is replaced.
        case section(note: String, prefix: String)
        case tag(prefix: String)
        /// The prefix carries the `/` itself, like the tag one carries its `#`, so the
        /// range to replace is simply its length.
        case slash(prefix: String)
        /// `:nome`, the prefix carrying its own `:` like the other two punctuation triggers.
        case emoji(prefix: String)

        /// The icon the candidates are drawn with. A command brings its own, so this is
        /// only ever asked of the three that offer plain strings.
        var symbol: String {
            switch self {
            case .wikilink: "doc.text"
            case .section: "number"
            case .tag: "tag"
            case .slash: "command"
            // Never asked for: an emoji row draws its own glyph.
            case .emoji: "face.smiling"
            }
        }
    }

    /// The headings of `note` that match what has been typed after the `#`.
    ///
    /// The same fuzzy scoring the note titles get, and deliberately not the word-start rule
    /// the slash menu uses: there the candidates are a fixed command catalogue and the
    /// reordering on every keystroke was the defect, here they are the headings of one note.
    ///
    /// **Ties break in document order**, not by length. A note's sections have an order the
    /// person wrote and reads them in - the one the index draws - and sorting the shortest
    /// first offered a `###` from the bottom of the note before the section above it. Seen
    /// on screen on 2026-08-17; the length rule read as arbitrary the moment it was used.
    func sections(of note: String, matching prefix: String) -> [String]? {
        guard let candidates = noteSections?(note), !candidates.isEmpty else { return nil }
        var scored: [(section: String, score: Int, order: Int)] = []
        for (order, section) in candidates.enumerated() {
            if prefix.isEmpty {
                scored.append((section, 0, order))
            } else if let score = FuzzyMatch.score(query: prefix, candidate: section) {
                scored.append((section, score, order))
            }
        }
        scored.sort { left, right in
            left.score == right.score ? left.order < right.order : left.score > right.score
        }
        let matches = scored.prefix(12).map(\.section)
        return matches.isEmpty ? nil : Array(matches)
    }

    /// The rule the three punctuation triggers share, written once.
    ///
    /// **The strictness is the whole design**, and it is the same argument for all three.
    /// `#`, `/` and `:` are ordinary characters in prose, in dates, in URLs and in
    /// frontmatter, so each opens its list only where a person would not otherwise be typing
    /// one: at the start of a line, or after a space. That rules out `24/08/2026` and `14:30`
    /// (a digit before it), `http://x` (a slash, then a letter), `e/o` (a letter) and
    /// `date: 2026-08-18` (a letter) without naming any of them. A space ends the prefix, and
    /// that is also what keeps `# ` a heading rather than a tag.
    ///
    /// Three copies of this lived here before the emoji trigger made it a fourth. One copy
    /// is not tidiness: the day the rule needs a fourth exception, it needs it in one place.
    private static func punctuationTrigger(_ mark: Character, in beforeCursor: String) -> String? {
        guard let found = beforeCursor.range(of: String(mark), options: .backwards) else { return nil }
        let prefix = String(beforeCursor[found.lowerBound...])
        let atLineStart = found.lowerBound == beforeCursor.startIndex
        // `.last`, not `index(before:)`: a line that begins with the mark has nothing before it.
        let afterSpace = beforeCursor.dropLast(prefix.count).last == " "
        guard atLineStart || afterSpace, !prefix.contains(" ") else { return nil }
        return prefix
    }

    /// Looks backwards from the cursor for one of the five triggers on the current line.
    /// Internal rather than private only because it now lives beside the view instead of
    /// inside it; nothing outside this pair of files reads it.
    func completionContext() -> Context? {
        let cursor = selectedRange().location
        guard cursor > 0 else { return nil }

        let text = string as NSString
        guard cursor <= text.length else { return nil }

        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        let beforeCursor = text.substring(with: NSRange(
            location: lineRange.location, length: cursor - lineRange.location
        ))

        if let open = beforeCursor.range(of: "[[", options: .backwards) {
            let prefix = String(beforeCursor[open.upperBound...])
            // A closed link is not a completion context any more.
            if !prefix.contains("]]") {
                // A `#` inside an open wikilink names a section of the note before it. The
                // first `#` wins, as it does in `WikilinkParser`; a `|` means the display
                // text is being typed, and that is not a heading.
                if let hash = prefix.firstIndex(of: "#"), !prefix.contains("|") {
                    return .section(
                        note: String(prefix[prefix.startIndex..<hash]),
                        prefix: String(prefix[prefix.index(after: hash)...])
                    )
                }
                return .wikilink(prefix: prefix)
            }
        }
        if let prefix = Self.punctuationTrigger("#", in: beforeCursor) { return .tag(prefix: prefix) }
        // Order matters and is deliberate: the wikilink was there first, and the three
        // punctuation triggers came in this order. Typing a slash inside an unclosed `[[` is
        // far more likely a title with a slash in it than a command.
        if let prefix = Self.punctuationTrigger("/", in: beforeCursor) { return .slash(prefix: prefix) }
        if let prefix = Self.punctuationTrigger(":", in: beforeCursor) { return .emoji(prefix: prefix) }
        return nil
    }
}
