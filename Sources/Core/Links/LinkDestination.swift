import Foundation

// ADR-0083 §D5, §D6 (PG-386, N3 session A).

/// Where a `[[link]]` goes, decided from the index's and the board resolver's answers.
///
/// Both answers arrive as inputs - the index's `resolve(title:)` for a note title, the board
/// resolver's `unique` path for a `.canvas` name - so there is one resolution rule and no second
/// resolver to drift from the first. Several notes of one title are a choice, never a guess.
enum LinkDestination: Equatable, Sendable {
    case note(path: String)
    case board(path: String)
    case ambiguous(title: String, paths: [String])
    case missing(title: String, creatable: Bool)
    case missingBoard(name: String)

    /// A `.canvas` target asks the board resolver and nothing else; any other target asks the
    /// note index and nothing else. The paths of an ambiguous title keep the order the index
    /// gave: the choice shows what the index said, not a re-sort.
    static func resolve(
        _ target: String,
        notePaths: (String) -> [String],
        board: (String) -> String?
    ) -> LinkDestination {
        if (target as NSString).pathExtension.lowercased() == "canvas" {
            guard let path = board(target) else { return .missingBoard(name: target) }
            return .board(path: path)
        }
        let paths = notePaths(target)
        switch paths.count {
        case 0: return .missing(title: target, creatable: isCreatable(target))
        case 1: return .note(path: paths[0])
        default: return .ambiguous(title: target, paths: paths)
        }
    }

    /// A title the composer could be offered (ADR-0083 §D6): one `NoteName.validate` accepts,
    /// and not ending in `.md` or `.canvas` - `[[TRUST.md]]` names a path, not a title, and keeps
    /// the «nota non trovata» sentence (PG-356).
    static func isCreatable(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return NoteName.validate(title).isEmpty
            && !lowered.hasSuffix(".md")
            && !lowered.hasSuffix(".canvas")
    }
}
