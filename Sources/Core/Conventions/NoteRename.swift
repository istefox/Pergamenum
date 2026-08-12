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
    static func rewritingLinks(in text: String, from oldTitle: String, to newTitle: String) -> String? {
        let needle = fold(oldTitle)
        guard needle != fold(newTitle) else { return nil }

        // Collected first, then applied from the end backwards: replacing a range
        // invalidates every range after it.
        let matches = WikilinkParser.links(in: text).filter { fold($0.target) == needle }
        guard !matches.isEmpty else { return rewritingQuotedRelated(in: text, from: oldTitle, to: newTitle) }

        var result = text
        for link in matches.reversed() {
            var rewritten = link
            rewritten.target = newTitle
            result.replaceSubrange(link.range, with: rewritten.rendered)
        }
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
        var changed = false
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- \""), trimmed.hasSuffix("\"") else { return line }
            let inner = String(trimmed.dropFirst(3).dropLast())
            guard !inner.contains("[["), fold(inner) == fold(oldTitle) else { return line }
            changed = true
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            return "\(indent)- \"\(newTitle)\""
        }
        return changed ? lines.joined(separator: "\n") : nil
    }

    /// Titles are compared case- and whitespace-insensitively so that a link typed
    /// with a stray capital still follows the rename; the new title is always written
    /// exactly as the user gave it.
    private static func fold(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
