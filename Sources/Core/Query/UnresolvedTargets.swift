import Foundation

// ADR-0084 §D2 (PG-386, N3 session A).

/// The one derivation of "which of a note's link targets name no note".
///
/// Three callers each wrote this out by hand before - the query field `unresolved`
/// (`ViewEvaluator`), the connector read `VaultAPI.links(_:at:)` and the inspector - and now
/// share it, with `IndexSnapshot.unresolvedTargets(of:)` as the inspector's door.
enum UnresolvedTargets {
    /// The targets `resolving` answers nothing for, in the order given, duplicates kept: the
    /// targets are `NoteRecord.linkTargets`, already deduplicated by exact text. An ambiguous
    /// target resolves (W-07), so it is not here.
    static func of(_ targets: [String], resolving: (String) -> [String]) -> [String] {
        targets.filter { resolving($0).isEmpty }
    }

    /// The first line holding a note link whose target is `target` as written (`[[X]]`,
    /// `[[X|a]]`, `[[X#s]]`), counting from zero over the whole text, frontmatter included -
    /// the number `NoteJump.lineRange` turns into a caret range. Body links only, code skipped,
    /// exactly the links `linkTargets` was computed from.
    static func firstLine(linking target: String, in text: String) -> Int? {
        let body = NoteDocument.parse(text).body
        guard let link = WikilinkParser.links(in: body).first(where: { $0.isNoteLink && $0.target == target })
        else { return nil }
        // The body is the text's verbatim suffix, so its start is found by UTF-16 length.
        let bodyStart = String.Index(utf16Offset: text.utf16.count - body.utf16.count, in: text)
        let linesBefore = text[..<bodyStart].filter(LineBreak.isTerminator).count
        return linesBefore + body[..<link.range.lowerBound].filter(LineBreak.isTerminator).count
    }
}
