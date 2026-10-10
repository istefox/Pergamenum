import Foundation

// ADR-0083 §D3 (PG-386, N3 session B).

/// Which followable link the caret is on (ADR-0083 §D3), as one pure rule over what the editor
/// already knows: the `.editorLink` runs of the caret's paragraph and the wikilinks' source ranges.
enum LinkAtCaret {
    /// One `.editorLink` run: its range in the text and the URL the styler wrote on it.
    struct Run: Equatable, Sendable {
        var range: NSRange
        var url: URL
    }

    /// A run containing the caret, or touching it at either edge, wins; otherwise a wikilink
    /// whose source range holds the caret (inside `[[`, in the alias, on `]]`) hands over the run
    /// inside it. Among several candidates the shortest range wins, which is what "innermost"
    /// means: a wikilink in a markdown link's label beats the label.
    static func pick(caret: Int, runs: [LinkAtCaret.Run], wikilinks: [NSRange]) -> URL? {
        if let run = innermost(runs.filter { touches($0.range, caret) }) {
            return run.url
        }
        let enclosing = wikilinks.filter { touches($0, caret) }.sorted { $0.length < $1.length }
        guard let wikilink = enclosing.first else { return nil }
        return innermost(runs.filter { NSIntersectionRange($0.range, wikilink) == $0.range })?.url
    }

    private static func touches(_ range: NSRange, _ caret: Int) -> Bool {
        range.location <= caret && caret <= NSMaxRange(range)
    }

    private static func innermost(_ runs: [Run]) -> Run? {
        runs.min { $0.range.length < $1.range.length }
    }
}
