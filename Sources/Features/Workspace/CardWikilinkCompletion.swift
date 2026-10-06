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

    /// What a chosen `[[` candidate writes over the typed prefix, and where the caret lands
    /// relative to the start of that write, in UTF-16 units (n1-seams R-07): the title and the
    /// closing `]]`, caret after it. A `]]` already right after the caret (`[[Tras]]` with the
    /// caret before the brackets) is reused rather than doubled, and the caret moves past it.
    /// Anything else ahead - a single `]`, a space before the brackets - is nothing ahead.
    static func closingInsertion(of title: String, ahead: Substring) -> (text: String, caretOffset: Int) {
        let closing = "]]"
        let caretOffset = (title + closing).utf16.count
        return ahead.hasPrefix(closing) ? (title, caretOffset) : (title + closing, caretOffset)
    }
}

/// A note as the `[[` popup sees it: its title and the aliases it answers to (n1-seams R-08).
struct WikilinkNote: Equatable, Sendable {
    let title: String
    let aliases: [String]
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
    /// The alias that matched, when the note was found through one (n1-seams R-08). `insertText`
    /// is the title either way.
    var matchedAlias: String?

    /// What the row reads: «Titolo · alias: X» when the note was found through an alias, so
    /// the person sees which name matched, and the bare `displayTitle` otherwise.
    var label: String {
        guard let matchedAlias else { return displayTitle }
        return "\(displayTitle) · alias: \(matchedAlias)"
    }
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
    /// `Sources/Core/FuzzyMatch.swift`) and capped at `limit`. A note is matched on its title
    /// first; only when the title does not match is it offered through its best-scoring alias
    /// (n1-seams R-08), with `matchedAlias` set and the title still the insertion. The note
    /// editor passes aliases; the card's popup passes titles only.
    ///
    /// `@_disfavoredOverload` keeps an empty `notes: []` literal resolving to the `[String]`
    /// overload below, as callers wrote it before this one existed.
    @_disfavoredOverload
    static func candidates(
        matching prefix: String, notes: [WikilinkNote], boards: [String], limit: Int = 8
    ) -> [WikilinkCandidate] {
        var scored: [(candidate: WikilinkCandidate, score: Int)] = []
        for note in notes {
            if let score = FuzzyMatch.score(query: prefix, candidate: note.title) {
                scored.append((WikilinkCandidate(displayTitle: note.title, insertText: note.title, kind: .note), score))
                continue
            }
            let aliasScores = note.aliases.compactMap { alias in
                FuzzyMatch.score(query: prefix, candidate: alias).map { (alias: alias, score: $0) }
            }
            guard let best = aliasScores.max(by: { $0.score < $1.score }) else { continue }
            let candidate = WikilinkCandidate(
                displayTitle: note.title, insertText: note.title, kind: .note, matchedAlias: best.alias
            )
            scored.append((candidate, best.score))
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

    /// The same ranking over bare titles - the card's popup, which offers no alias.
    static func candidates(
        matching prefix: String, notes: [String], boards: [String], limit: Int = 8
    ) -> [WikilinkCandidate] {
        candidates(
            matching: prefix,
            notes: notes.map { WikilinkNote(title: $0, aliases: []) },
            boards: boards,
            limit: limit
        )
    }
}
