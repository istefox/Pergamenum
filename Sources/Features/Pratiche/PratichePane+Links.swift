import SwiftUI

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 5 - R-04, R-06, R-08, R-09.
//
// The three sections `inspector` (`PratichePane+Inspector.swift`) appends under
// `pratica.md`'s body. `BoardTray.traySection`'s shape is reproduced rather than
// shared - that helper is `private` to a different `View` type - as `linksSection`
// below.
//
// Resolution happens here, per draw, rather than once and cached in `@State` the way
// `BoardTray` holds its own dashboard: that tray redraws on every observable change a
// whole workspace document sees, a card dragged across it included, while this section
// redraws only when the pratica's selection or its own links change. An index lookup
// and one `CanvasStore.allBoards()` walk - the second done once per section, never per
// row, `PraticaLinkResolver`'s own stated rule - cost less than a cached copy that could
// go stale.

extension PratichePane {
    /// R-04, R-09: appended under `pratica.md`'s body inside `inspector`. R-09 stays
    /// satisfied because nothing here reacts to the timeline's row selection - only to
    /// `pratiche.selection` and `pratiche.links`, exactly like the body above it.
    var praticaLinksSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            linkedNotesSection
            linkedTasksSection
            linkedBoardsSection
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-links")
    }

    // MARK: Shared shape

    private func linksSection<Rows: View>(
        title: String, count: Int, identifier: String, emptyText: String, @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Text(title).themedText(.caption, color: .textTertiary)
                if count > 0 {
                    Text("\(count)").themedText(.caption, color: .textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(count)")
            .accessibilityIdentifier("\(identifier)-header")

            if count == 0 {
                Text(emptyText).themedText(.caption, color: .textTertiary)
            } else {
                rows()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// `linkRow`'s static fields, bundled so the function itself stays under
    /// SwiftLint's parameter-count ceiling - `onOpen`/`trailing` stay discrete
    /// because they are the two things a call site actually varies in shape, not
    /// just in value.
    private struct LinkRowContent {
        let reference: String
        let displayName: String
        let resolution: PraticaLinkResolution
        let resolvedIcon: String
        let missingHelp: String
    }

    /// One row of any of the three sections: an icon and color that mark a broken
    /// state rather than hiding it (R-08), and an action that opens the resolved
    /// target - disabled when there is nothing unique to open.
    private func linkRow<Trailing: View>(
        _ content: LinkRowContent,
        onOpen: @escaping (String) -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let path: String? = if case let .unique(value) = content.resolution { value } else { nil }
        return Button {
            if let path { onOpen(path) }
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: path == nil ? "questionmark.square.dashed" : content.resolvedIcon)
                    .foregroundStyle(theme.color(path == nil ? .textTertiary : .textSecondary))
                Text(content.displayName)
                    .themedText(.caption, color: path == nil ? .textTertiary : .textPrimary)
                    .lineLimit(1)
                trailing()
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(path == nil)
        .help(help(for: content.resolution, missingText: content.missingHelp))
        .accessibilityLabel(content.displayName)
        .accessibilityIdentifier("pratiche-link-row-\(content.reference)")
    }

    private func help(for resolution: PraticaLinkResolution, missingText: String) -> String {
        switch resolution {
        case .unique(let path): path
        case .ambiguous: "collegamento ambiguo: più elementi hanno lo stesso nome"
        case .missing: missingText
        }
    }

    // MARK: Notes (R-04, R-06)

    private var linkedNotesSection: some View {
        let rows = pratiche.aggregatedNoteLinks
        return linksSection(
            title: "NOTE COLLEGATE", count: rows.count,
            identifier: "pratiche-links-notes", emptyText: "nessuna nota collegata"
        ) {
            ForEach(rows) { row in linkedNoteRow(row) }
        }
    }

    private func linkedNoteRow(_ row: PraticaAggregatedNoteLink) -> some View {
        let resolution = PraticaLinkResolver.note(candidates: vault.index.resolve(title: row.title))
        let content = LinkRowContent(
            reference: PraticaLinkReference.wikilink(row.title).rendered,
            displayName: row.title,
            resolution: resolution,
            resolvedIcon: "doc.text",
            missingHelp: "nota non trovata nel vault"
        )
        return linkRow(content) { path in
            vault.openNote(at: path)
            navigation.pane = .notes
        } trailing: {
            // R-06: a note reached through one or more messages, not only the
            // pratica's own general link, is marked rather than shown as if it were
            // the same as any other row.
            if row.messagePaths.isEmpty {
                EmptyView()
            } else {
                Image(systemName: "envelope")
                    .foregroundStyle(theme.color(.textTertiary))
                    .help(
                        row.messagePaths.count == 1
                            ? "collegata anche da un messaggio"
                            : "collegata anche da \(row.messagePaths.count) messaggi"
                    )
            }
        }
    }

    // MARK: Tasks (R-04)

    private var linkedTasksSection: some View {
        let refs = pratiche.links.tasks
        return linksSection(
            title: "TASK COLLEGATI", count: refs.count,
            identifier: "pratiche-links-tasks", emptyText: "nessun task collegato"
        ) {
            ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in linkedTaskRow(ref) }
        }
    }

    /// The note half resolves like a note link; the `^id` half is then looked up
    /// among that one note's own tasks, `vault.index.allTasks` filtered rather than a
    /// file read - the index already holds every task's `localID`.
    private func linkedTaskRow(_ ref: PraticaLinks.TaskReference) -> some View {
        let candidates = vault.index.resolve(title: ref.noteTitle)
        var localIDs: [Int] = []
        var matched: TaskItem?
        if candidates.count == 1 {
            let inNote = vault.index.allTasks.filter { $0.sourcePath == candidates[0] }
            localIDs = inNote.compactMap(\.localID)
            matched = inNote.first { $0.localID == ref.localID }
        }
        let resolution = PraticaLinkResolver.task(
            localID: ref.localID, noteCandidates: candidates, localIDsInResolvedNote: localIDs
        )
        let content = LinkRowContent(
            reference: PraticaLinkReference.task(noteTitle: ref.noteTitle, localID: ref.localID).rendered,
            displayName: matched?.text ?? ref.noteTitle,
            resolution: resolution,
            resolvedIcon: "checklist",
            missingHelp: "task non trovato nel vault"
        )
        return linkRow(content) { path in
            vault.openNote(at: path)
            navigation.pane = .notes
        } trailing: {
            EmptyView()
        }
    }

    // MARK: Boards (R-04)

    private var linkedBoardsSection: some View {
        let names = pratiche.links.boards
        // Once per section, never per row (`PraticaLinkResolver`'s own stated rule):
        // `CanvasStore.allBoards()` is an uncached full filesystem walk.
        let boards = vault.root.map { CanvasStore(root: $0).allBoards() } ?? []
        return linksSection(
            title: "BOARD COLLEGATE", count: names.count,
            identifier: "pratiche-links-boards", emptyText: "nessuna board collegata"
        ) {
            ForEach(names, id: \.self) { fileName in linkedBoardRow(fileName, boards: boards) }
        }
    }

    private func linkedBoardRow(_ fileName: String, boards: [String]) -> some View {
        let resolution = PraticaLinkResolver.board(fileName, boards: boards)
        let content = LinkRowContent(
            reference: PraticaLinkReference.wikilink(fileName).rendered,
            displayName: (fileName as NSString).deletingPathExtension,
            resolution: resolution,
            resolvedIcon: "square.grid.2x2",
            missingHelp: "board non trovata nel vault"
        )
        return linkRow(content) { path in
            vault.routeState.pendingCanvas = (path, nil)
        } trailing: {
            EmptyView()
        }
    }
}
