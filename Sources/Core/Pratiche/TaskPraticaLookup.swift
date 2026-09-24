import Foundation

// SPEC (task side of ADR-0049's pratica links), plan
// docs/plans/pratiche-links-task-side-and-inspector-summary.md, Tasks 1-2 - R-01, R-03, R-06, R-07.

/// One pratica that links a given task (SPEC "Data model").
struct TaskPraticaLink: Equatable, Sendable {
    /// `PraticaListItem.id`, what the badge selects.
    let praticaID: String
    /// `PraticaListItem.title`, what the badge reads.
    let praticaTitle: String
}

/// The task -> pratica reverse lookup, built once per `TasksView` render from every
/// pratica's own `PraticaLinks.tasks` and never stored (SPEC Decisions, R-03).
///
/// Not an index: the SPEC rejects a reverse index in `IndexCache`, and ADR-0049 §D4
/// keeps a link readable only off the file that owns it. This value lives for one
/// render and is thrown away with it.
struct TaskPraticaLookup: Sendable {
    /// One pratica as the lookup reads it, in the order the caller wants badges drawn.
    struct Source: Equatable, Sendable {
        var praticaID: String
        var praticaTitle: String
        var links: PraticaLinks
    }

    /// A task, as a pratica's reference names it once resolved: the note it lives in
    /// and its `^id` inside that note (ADR-0049 §D3).
    private struct Key: Hashable {
        var sourcePath: String
        var localID: Int
    }

    private var linksByTask: [Key: [TaskPraticaLink]] = [:]

    static let empty = TaskPraticaLookup(pratiche: [], noteCandidates: { _ in [] }, localIDsInNote: { _ in [] })

    /// `noteCandidates`: `IndexSnapshot.resolve(title:)`'s answer for a title.
    /// `localIDsInNote`: every `^id` the note at a path carries.
    /// Both passed in, never fetched here (ADR-0049 §D5, `PraticaLinkResolver`'s own rule).
    ///
    /// Every reference goes through `PraticaLinkResolver.task`, the same answer the
    /// pratica inspector's own "TASK COLLEGATI" row draws from, so the two sides cannot
    /// disagree on which task a reference means. Only `.unique` is kept: the task side
    /// never draws a broken or ambiguous badge (SPEC R-06).
    init(
        pratiche: [Source],
        noteCandidates: (String) -> [String],
        localIDsInNote: (String) -> [Int]
    ) {
        for source in pratiche {
            let link = TaskPraticaLink(praticaID: source.praticaID, praticaTitle: source.praticaTitle)
            // One badge per pratica (R-01): a pratica listing the same task twice counts once.
            var seen: Set<Key> = []
            for reference in source.links.tasks {
                let candidates = noteCandidates(reference.noteTitle)
                let localIDs = candidates.count == 1 ? localIDsInNote(candidates[0]) : []
                let resolution = PraticaLinkResolver.task(
                    localID: reference.localID, noteCandidates: candidates, localIDsInResolvedNote: localIDs
                )
                guard case let .unique(path) = resolution else { continue }
                let key = Key(sourcePath: path, localID: reference.localID)
                guard seen.insert(key).inserted else { continue }
                // Appended in source order, which is what keeps the caller's order (R-07).
                linksByTask[key, default: []].append(link)
            }
        }
    }

    /// The pratiche linking the task at `taskSourcePath` carrying `^id(taskLocalID)`,
    /// in `pratiche`' input order, one entry per pratica.
    func praticheLinking(taskSourcePath: String, taskLocalID: Int?) -> [TaskPraticaLink] {
        // A task with no `^id` cannot be referenced at all (ADR-0049 §D3).
        guard let taskLocalID else { return [] }
        return linksByTask[Key(sourcePath: taskSourcePath, localID: taskLocalID)] ?? []
    }
}
