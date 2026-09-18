import Foundation

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 1 - R-07, §D2, §D3.

/// The text of one link reference, written once so a future surface cannot spell a
/// reference a second way (ADR §D2, §D3).
///
/// Both cases render as a wikilink because that is the shape both rename passes
/// (`NoteFileOperations.renamePlan`, `BoardFileOperations.renamePlan`) already rewrite:
/// a note and a board reference cost no new code for R-07, and a task reference keeps
/// its `^id` because the marker sits outside the rewritten range
/// (`WikilinkParser.links(in:)`'s `range` stops at the closing `]]`).
enum PraticaLinkReference: Equatable, Sendable {
    /// `[[Titolo]]` (a note, by title) or `[[Nome.canvas]]` (a board, by file name) -
    /// the two are told apart by which of `PraticaLinks`' three keys the entry sits
    /// under, not by this case.
    case wikilink(String)
    /// `[[Nota]] ^id(3)` - the task carrying `^id(3)` inside the note titled `Nota`
    /// (ADR §D3): never the task's own text, which is the most ordinary thing to edit.
    case task(noteTitle: String, localID: Int)

    /// The exact text written to a `- "…"` block item or the `pergamenum-mail-note`
    /// scalar.
    var rendered: String {
        switch self {
        case let .wikilink(target):
            return "[[\(target)]]"
        case let .task(noteTitle, localID):
            return "[[\(noteTitle)]] ^id(\(localID))"
        }
    }

    /// Parses a reference's text back. `nil` when it is neither shape.
    init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), let close = trimmed.range(of: "]]") else { return nil }
        let target = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
        guard !target.isEmpty else { return nil }

        let remainder = trimmed[close.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else {
            self = .wikilink(target)
            return
        }
        guard remainder.hasPrefix("^id("), remainder.hasSuffix(")"),
              let localID = Int(remainder.dropFirst("^id(".count).dropLast())
        else { return nil }
        self = .task(noteTitle: target, localID: localID)
    }
}
