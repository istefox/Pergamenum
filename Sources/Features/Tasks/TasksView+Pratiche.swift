import SwiftUI

// SPEC (task side of ADR-0049's pratica links), plan
// docs/plans/pratiche-links-task-side-and-inspector-summary.md, Tasks 3-4 - R-01, R-02, R-03, R-06.
//
// Which pratiche link a task, read back from the pratica side: ADR-0049's links are
// one-way (a pratica names a task by its note and `^id`, the task's note carries
// nothing), so the reverse relation is computed here and never written anywhere.

extension TasksView {
    /// Every pratica's task links, resolved once for the whole list (SPEC R-03).
    ///
    /// Not `private`: `TasksView+List.swift`'s `list` builds it, once per render, and hands
    /// it down to every row.
    ///
    /// **Per render, on purpose, not cached** - the same call `PratichePane+Links.swift`
    /// makes for its own sections: tens of small `pratica.md` reads and one index lookup
    /// per referenced note cost less than a cached copy that could go stale, and a copy
    /// kept in `@State` or on `PraticheController` would be a second source of truth for
    /// a relation ADR-0049 §D4 keeps on disk only. If a vault ever holds hundreds of
    /// pratiche, the cache is a SPEC decision to reopen, not a tweak to make here.
    ///
    /// The links are read from each `pratica.md` itself, never from
    /// `NoteRecord.frontmatter.foreignKeys`: a record a scan reused from the cache comes
    /// back with no foreign keys at all (ADR-0049 §D4), so the badges would vanish from
    /// the second launch onward.
    func taskPraticaLookup() -> TaskPraticaLookup {
        guard let root = vault.root else { return .empty }
        // The list column's own default order (`.newestFirst`), flattened: open groups,
        // then «Chiuse». `pratiche.pratiche` itself has no stable order to borrow.
        let grouped = PraticheSidebarGrouping.grouped(pratiche.pratiche)
        let ordered = grouped.open.flatMap(\.pratiche) + grouped.closed
        let sources = ordered.map { item in
            TaskPraticaLookup.Source(
                praticaID: item.id,
                praticaTitle: item.title,
                links: PraticaLinks.parse(praticaFileAt: root.appending(
                    path: PraticaNaming.praticaNotePath(of: item.id), directoryHint: .notDirectory
                ))
            )
        }
        let index = vault.index
        return TaskPraticaLookup(
            pratiche: sources,
            noteCandidates: { index.resolve(title: $0) },
            // One dictionary hit per resolved note, not a scan of every task in the vault.
            localIDsInNote: { index.note(at: $0)?.tasks.compactMap(\.localID) ?? [] }
        )
    }

    /// The pratiche segment of `details`, beside `workspaceSegment(_:)` and in its `.unique`
    /// shape (SPEC R-01): one badge per pratica that links this task, in the list column's
    /// order. Nothing at all when none does - no empty-state text, and no muted badge for
    /// an ambiguous or missing reference, which `TaskPraticaLookup` never returns (R-06).
    ///
    /// Not `private`: `TasksView+Row.swift`'s `details(_:praticaLookup:)` draws it.
    ///
    /// The icon is the Pratiche pane's own (`Navigation.Pane.pratiche.symbol`), read from
    /// the catalogue rather than repeated, so the badge shows where a click leads. The click
    /// goes through `select(_:in:)`, the one door every pratica selector uses, so the pane
    /// shows this pratica's timeline and links rather than the last one's - and it opens
    /// the pane, never `pratica.md` as a note (ADR-0036 §D5: one editor, the inspector).
    @ViewBuilder
    func praticaSegment(_ task: TaskItem, lookup: TaskPraticaLookup) -> some View {
        ForEach(
            lookup.praticheLinking(taskSourcePath: task.sourcePath, taskLocalID: task.localID),
            id: \.praticaID
        ) { link in
            Button {
                pratiche.select(link.praticaID, in: vault)
                navigation.pane = .pratiche
            } label: {
                Text("\(Image(systemName: Navigation.Pane.pratiche.symbol)) \(link.praticaTitle)")
                    .themedText(.caption, color: .accentPrimary)
            }
            .buttonStyle(.plain)
            // Two clients can hold pratiche with the same folder name; the path tells them apart.
            .help(link.praticaID)
        }
    }
}
