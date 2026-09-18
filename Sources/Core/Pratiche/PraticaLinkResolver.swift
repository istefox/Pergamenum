import Foundation

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 1 - R-08, §D5.

/// What a pratica link's target resolves to. `missing` is what "broken" means in the
/// UI - nothing is ever removed on a miss (SPEC's own decision): the reference stays
/// on disk exactly as written, and the surface that draws it says so.
enum PraticaLinkResolution: Equatable, Sendable {
    /// Exactly one candidate answers to the reference.
    case unique(String)
    /// More than one candidate answers to it; which one was meant cannot be inferred.
    case ambiguous
    /// No candidate answers to it - the reference is broken, not removed.
    case missing
}

/// Answers `unique` / `ambiguous` / `missing` for all four relations (general note,
/// general task, general board, per-message note), assembled from the two resolvers
/// that already exist rather than a third index (ADR §D5).
///
/// Candidates are **passed in**, never fetched here - `WorkspaceBoardResolver`'s own
/// stated rule, because `CanvasStore.allBoards()` is an uncached full filesystem walk
/// and a resolver called per row must not repeat it.
enum PraticaLinkResolver {
    /// A note reference: folds `IndexSnapshot.resolve(title:)`'s `[String]` into the
    /// three cases - zero is `missing`, one is `unique`, more than one is
    /// `ambiguous`.
    static func note(candidates: [String]) -> PraticaLinkResolution {
        fold(candidates)
    }

    /// A board reference: `WorkspaceBoardResolver.resolve(_:in:)` literally, its three
    /// cases mapped one-to-one - the ambiguity behaviour a person sees for a pratica
    /// link is the one they already know from a task's board marker.
    static func board(_ fileName: String, boards: [String]) -> PraticaLinkResolution {
        switch WorkspaceBoardResolver.resolve(fileName, in: boards) {
        case let .unique(path): .unique(path.value)
        case .ambiguous: .ambiguous
        case .notFound: .missing
        }
    }

    /// A task reference: the note half resolved exactly like `note(candidates:)`,
    /// then the `^id` looked up among the `localID`s the caller already parsed out of
    /// that one note (`TaskParser.tasks(in:sourcePath:)`) - this resolver never reads
    /// a file itself.
    static func task(
        localID: Int, noteCandidates: [String], localIDsInResolvedNote: [Int]
    ) -> PraticaLinkResolution {
        switch fold(noteCandidates) {
        case let .unique(path):
            localIDsInResolvedNote.contains(localID) ? .unique(path) : .missing
        case .ambiguous:
            .ambiguous
        case .missing:
            .missing
        }
    }

    private static func fold(_ candidates: [String]) -> PraticaLinkResolution {
        switch candidates.count {
        case 0: .missing
        case 1: .unique(candidates[0])
        default: .ambiguous
        }
    }
}
