import Foundation

/// Pure `[[` trigger detection and fuzzy candidate ranking for Workspace `.text` cards
/// (ADR-0027 §D1) - a narrow sibling of `CompletingTextView+Context.swift`'s own `.wikilink`
/// case, never a fork of it: a card offers no section/tag/slash/emoji trigger, and offers
/// boards too, which the note editor's own `[[` completion never does.
enum WikilinkTrigger {
    /// An unclosed `[[` on the caret's current line, and what has been typed after it.
    struct Context: Equatable {
        let prefix: String
        /// What a chosen candidate replaces - `prefix`'s own range, ending at the caret,
        /// mirroring `CompletingTextView.rangeForUserCompletion`'s `.wikilink` case.
        let range: NSRange
    }

    /// Looks backwards from `caret` on its own line for an unclosed `[[`, the same rule
    /// `CompletingTextView.completionContext()` applies for its `.wikilink` case, minus the
    /// `#`-section branch a card has no heading completion for.
    static func context(in text: String, caret: Int) -> Context? {
        let nsText = text as NSString
        guard caret >= 0, caret <= nsText.length else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: caret, length: 0))
        let beforeCursor = nsText.substring(with: NSRange(
            location: lineRange.location, length: caret - lineRange.location
        ))
        guard let open = beforeCursor.range(of: "[[", options: .backwards) else { return nil }
        let prefix = String(beforeCursor[open.upperBound...])
        // A closed link is not a completion context any more.
        guard !prefix.contains("]]") else { return nil }
        return Context(
            prefix: prefix,
            range: NSRange(location: caret - prefix.count, length: prefix.count)
        )
    }
}

/// One row the popup can offer: a note by title, or a board by file.
struct WikilinkCandidate: Identifiable, Equatable {
    enum Kind: Equatable { case note, board }

    var id: String { "\(kind)-\(insertText)" }
    /// What the row shows - a note's title, or a board's full vault-relative path, so two
    /// boards named alike in different folders stay distinguishable.
    let displayTitle: String
    /// What gets spliced into `[[...]]` - a note's plain title, or **a board's bare
    /// filename**, never its full path: `CommandActions.open(link:)` →
    /// `WorkspaceBoardResolver.resolve(_:in:)` matches a bare name against the full path
    /// list, exactly how `^[[board.canvas]]` task markers already write it.
    let insertText: String
    let kind: Kind
}

/// The popup's live state: the trigger it answers, its ranked candidates, and which one the
/// keyboard has highlighted.
struct WikilinkCompletion: Equatable {
    let context: WikilinkTrigger.Context
    let candidates: [WikilinkCandidate]
    var selectedIndex = 0

    var selected: WikilinkCandidate? {
        candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : nil
    }
}

enum CardWikilinkCompletion {
    /// Notes and boards matching `prefix`, fuzzy-ranked together (`FuzzyMatch`,
    /// `Sources/Core/FuzzyMatch.swift`) and capped at `limit` - the card's own popup offers
    /// both kinds, unlike the note editor's, which only ever offers notes.
    static func candidates(
        matching prefix: String, notes: [String], boards: [String], limit: Int = 8
    ) -> [WikilinkCandidate] {
        var scored: [(candidate: WikilinkCandidate, score: Int)] = []
        for title in notes {
            guard let score = FuzzyMatch.score(query: prefix, candidate: title) else { continue }
            scored.append((WikilinkCandidate(displayTitle: title, insertText: title, kind: .note), score))
        }
        for path in boards {
            let name = (path as NSString).lastPathComponent
            guard let score = FuzzyMatch.score(query: prefix, candidate: path) else { continue }
            scored.append((WikilinkCandidate(displayTitle: path, insertText: name, kind: .board), score))
        }
        scored.sort { left, right in
            left.score == right.score
                ? left.candidate.displayTitle.count < right.candidate.displayTitle.count
                : left.score > right.score
        }
        return Array(scored.prefix(limit).map(\.candidate))
    }
}
