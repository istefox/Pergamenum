import Foundation

/// Renaming a note and carrying its incoming links with it (wikilink.md W-08).
///
/// A wikilink names a note by its exact title, so renaming a note breaks every link
/// pointing at it unless they are rewritten in the same operation. That rewrite is
/// the whole point of renaming from inside the app rather than in the Finder.
enum NoteRename {
    /// Rewrites the links in one note's text so that `oldTitle` becomes `newTitle`.
    ///
    /// Returns nil when nothing in this note points at the old title, so the caller
    /// can skip writing a file it would not change.
    ///
    /// The section and the display text are preserved: `[[Vecchio#Metodo|come qui]]`
    /// becomes `[[Nuovo#Metodo|come qui]]`, because the fragment and the label are the
    /// reader's, not the target's.
    /// `includeQuotedRelated` gates the frontmatter-only pass below. A Workspace board's
    /// `.text` card has no `related:` field to preserve, so calling this for a card body
    /// with the default `true` would rewrite an unrelated quoted bullet line
    /// (`- "Capture"`) that only coincidentally folds to the old title - a silent
    /// corruption this type was never meant to cause outside a note's own frontmatter.
    static func rewritingLinks(
        in text: String, from oldTitle: String, to newTitle: String, includeQuotedRelated: Bool = true
    ) -> String? {
        let needle = fold(oldTitle)
        guard needle != fold(newTitle) else { return nil }

        // Collected first, then applied from the end backwards: replacing a range
        // invalidates every range after it.
        // Matched by `Wikilink.names(_:)`, the one predicate the index keys a backlink by and every
        // row counts with: `[[**Forno tunnel**]]` names `Forno tunnel`, and matching on the literal
        // interior left it pointing at a note that no longer exists (ADR-0065 §D9.4, R-19;
        // ADR-0097 §D1).
        let matches = WikilinkParser.links(in: text).filter { $0.names(oldTitle) }
        guard !matches.isEmpty else {
            guard includeQuotedRelated else { return nil }
            return rewritingQuotedRelated(in: text, from: oldTitle, to: newTitle)
        }

        var result = text
        for link in matches.reversed() {
            result.replaceSubrange(link.range, with: link.retitled(newTitle).rendered)
        }
        guard includeQuotedRelated else { return result }
        return rewritingQuotedRelated(in: result, from: oldTitle, to: newTitle) ?? result
    }

    /// Handles the `related:` form that carries no brackets: `- "Vecchio titolo"`.
    ///
    /// F-06 allows either spelling, and a rename that fixed only the bracketed one
    /// would leave the frontmatter pointing at a note that no longer exists while the
    /// body was correct - the hardest kind of inconsistency to notice.
    private static func rewritingQuotedRelated(
        in text: String,
        from oldTitle: String,
        to newTitle: String
    ) -> String? {
        // A line split on "\n" carries a trailing "\r" on a CRLF note (ADR-0065 §D3); comparing
        // through the raw split left that "\r" attached, so `hasSuffix("\"")` never matched and a
        // CRLF note's quoted `related:` entry was silently left unrewritten.
        let suffix = LineBreak.detected(in: text).lineSuffix
        var lines = text.components(separatedBy: "\n")
        // Only the `related:` entry's own lines (R-10): the walk ran over the whole note and
        // rewrote a body bullet, or a fenced line, that happened to read `- "Old title"`.
        var changed = false
        for index in relatedLineIndices(in: lines) {
            let interpreted = FrontmatterSource.interpreted(lines[index])
            let trimmed = interpreted.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- \""), trimmed.hasSuffix("\"") else { continue }
            let inner = String(trimmed.dropFirst(3).dropLast())
            guard !inner.contains("[["), fold(inner) == fold(oldTitle) else { continue }
            changed = true
            let indent = interpreted.prefix { $0 == " " || $0 == "\t" }
            lines[index] = "\(indent)- \"\(newTitle)\"\(suffix)"
        }
        return changed ? lines.joined(separator: "\n") : nil
    }

    /// The continuation lines of the frontmatter's `related:` key, grouped the way the parser
    /// groups a key's lines (`FrontmatterParser.keyName(of:)`, `isContinuation`); none when the
    /// note has no block.
    private static func relatedLineIndices(in lines: [String]) -> [Int] {
        guard let closing = FrontmatterSource.closingDelimiterIndex(in: lines) else { return [] }
        var indices: [Int] = []
        var insideRelated = false
        for index in 1..<closing {
            let line = FrontmatterSource.interpreted(lines[index])
            if let key = FrontmatterParser.keyName(of: line) {
                insideRelated = key == "related"
            } else if insideRelated, FrontmatterParser.isContinuation(line) {
                indices.append(index)
            } else {
                insideRelated = false
            }
        }
        return indices
    }

    /// Titles are compared case- and whitespace-insensitively so that a link typed
    /// with a stray capital still follows the rename; the new title is always written
    /// exactly as the user gave it.
    private static func fold(_ title: String) -> String {
        Wikilink.fold(title)
    }
}
