import AppKit
import SwiftUI

// PG-387 (N4), ADR-0085 §D1/§D2, plan docs/plans/pg-387-n4-birth-of-note.md, Task 5 - R-01.

/// «Da classificare»: the notes that still carry `status-inbox`, a Contenitore scheda included.
///
/// The rows are derived from `vault.index` on every body pass and never cached (principle 3): a
/// note classified anywhere - this pane, the editor, the connector - leaves the list at the index
/// generation that saw it.
struct UnfiledPane: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    /// The folder filter, nil for every folder.
    @State private var folder: String?

    var body: some View {
        let records = vault.index.allNotes
        let folders = UnfiledListModel.folders(from: records)
        let rows = UnfiledListModel.rows(from: records, folder: folder)
        VStack(spacing: 0) {
            header(count: rows.count, folders: folders)
            Divider()
            if rows.isEmpty {
                empty
            } else {
                UnfiledList(rows: rows)
            }
        }
        .background(theme.color(.backgroundPrimary))
        // After a filing, the selection moves to the row that followed, else the one before
        // (ADR-0085 §D2), so the next Return classifies the next capture.
        .onChange(of: rows) { old, new in
            guard let selected = navigation.unfiledSelection, !new.contains(where: { $0.id == selected }) else {
                return
            }
            let next = UnfiledListModel.selection(after: selected, in: old)
            navigation.unfiledSelection = next.flatMap { id in new.contains { $0.id == id } ? id : nil }
        }
        .onChange(of: folders.map(\.folder)) { _, names in
            if let folder, !names.contains(folder) { self.folder = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unfiled-pane")
    }

    private func header(count: Int, folders: [(folder: String, count: Int)]) -> some View {
        HStack(spacing: theme.spacing(.m)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Da classificare").themedText(.title)
                Text(count == 1 ? "1 nota" : "\(count) note")
                    .themedText(.caption, color: .textSecondary)
            }
            Spacer()
            // Hidden with nothing to classify (R-01): a filter over no folders filters nothing.
            if !folders.isEmpty {
                Picker("Cartella", selection: $folder) {
                    Text("Tutte le cartelle").tag(String?.none)
                    ForEach(folders, id: \.folder) { entry in
                        Text("\(entry.folder.isEmpty ? "(radice)" : entry.folder) · \(entry.count)")
                            .tag(Optional(entry.folder))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("unfiled-folder-filter")
            }
        }
        .padding(.horizontal, theme.spacing(.l))
        .padding(.vertical, theme.spacing(.m))
    }

    private var empty: some View {
        VStack(spacing: theme.spacing(.m)) {
            Image(systemName: "tray")
                .font(theme.font(.iconDisplay))
                .foregroundStyle(theme.color(.textTertiary))
            Text("Niente da classificare").themedText(.title)
            Text("Le note nate senza argomento arrivano qui con status-inbox. Classificale per farle uscire.")
                .themedText(.body, color: .textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("unfiled-empty")
    }
}

/// The rows as one flat `List` (ADR-0024), with the keyboard, the row menu and the two gestures.
private struct UnfiledList: View {
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    @Environment(CommandActions.self) private var actions
    @Environment(ContenitoreController.self) private var contenitore
    let rows: [UnfiledListModel.Row]

    /// ADR-0070: a row click does not give the list the keyboard, so the selection change does;
    /// a setter, never a guard. Also set on appear, so Ctrl+Cmd+I then Down moves in the list -
    /// one turn later (measured: set synchronously in `onAppear`, the `List`'s table is not yet
    /// something focus can land on and the window stays first responder, `Tests/UnfiledPaneHostedTests`).
    @FocusState private var isListFocused: Bool

    var body: some View {
        @Bindable var navigation = navigation
        List(selection: $navigation.unfiledSelection) {
            ForEach(rows) { row in
                UnfiledRow(row: row).tag(row.id)
            }
        }
        .scrollContentBackground(.hidden)
        // One row-level menu (no nested one, ADR-0069). `primaryAction` is the list's own and
        // receives both Return and a double click: Return classifies, a double click opens the
        // note, told apart by the event that delivered it.
        .contextMenu(forSelectionType: String.self) { selection in
            if let path = selection.first, let row = rows.first(where: { $0.id == path }) {
                menu(for: row)
            }
        } primaryAction: { selection in
            guard let path = selection.first else { return }
            if NSApp.currentEvent?.type == .keyDown {
                classify(path)
            } else {
                open(path)
            }
        }
        .focused($isListFocused)
        .onAppear { Task { @MainActor in isListFocused = true } }
        .onChange(of: navigation.unfiledSelection) { _, selected in
            if selected != nil { isListFocused = true }
        }
        .accessibilityIdentifier("unfiled-list")
    }

    @ViewBuilder
    private func menu(for row: UnfiledListModel.Row) -> some View {
        Button(ShortcutCommand.classifyNote.title) { classify(row.id) }
        Button("Apri") { open(row.id) }
        Button("Apri in una nuova tab") {
            navigation.pane = .notes
            vault.openNoteInNewTab(at: row.id)
        }
        Divider()
        Button("Mostra nel Finder") {
            // Through the boundary (PG-360): a path outside the vault reveals nothing.
            guard let root = vault.root, let url = try? VaultBoundary(root: root).url(for: row.id) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        if row.isScheda {
            Button("Mostra nel Contenitore") {
                navigation.pane = .contenitore
                contenitore.selection = row.id
            }
        }
    }

    private func classify(_ path: String) {
        navigation.unfiledSelection = path
        navigation.classifying = actions.classifySubject(for: path)
    }

    private func open(_ path: String) {
        navigation.pane = .notes
        vault.openNote(at: path)
    }
}
