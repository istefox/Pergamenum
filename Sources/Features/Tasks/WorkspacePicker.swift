import SwiftUI

/// Assigns a task to a Workspace (ADR-0021 D9, R-03): the sheet behind «Assegna a un
/// Workspace…», in the Attività toolbar and in the task row's context menu.
///
/// Distinct from «Collega nota o board…» beside it, and deliberately so: that one writes
/// an ordinary wikilink and a task may carry any number of them, while this one writes
/// the single `^[[<board>.canvas]]` marker a task has exactly one of. The write goes
/// through `VaultSession.TaskChange.workspace`, which replaces an existing marker rather
/// than appending a second.
///
/// The list comes from `CanvasStore.allBoards()` rather than from the index: `.canvas`
/// files are not indexed and are not going to be (D10). What is written is the board's
/// **file name**, not its vault-relative path - that is what a wikilink names a board by,
/// and what `IndexSnapshot.tasks(assignedToWorkspace:)` matches on.
struct WorkspacePicker: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let task: TaskItem
    let onClose: () -> Void

    @State private var filter = ""
    @State private var boards: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 380, height: 380)
        .background(theme.color(.surfaceCard))
        .task { boards = vault.root.map { CanvasStore(root: $0).allBoards() } ?? [] }
        .onExitCommand(perform: onClose)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Assegna a un Workspace").themedText(.title)
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.color(.textTertiary))
                TextField("Filtra", text: $filter)
                    .textFieldStyle(.plain)
                    .themedText(.body)
                    .accessibilityIdentifier("workspace-picker-filter")
            }
        }
        .padding(theme.spacing(.m))
    }

    // MARK: Rows

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filtered, id: \.self) { path in
                    row(path)
                }
                if filtered.isEmpty {
                    Text(boards.isEmpty ? "Nessuna board nel vault" : "Nessuna board trovata")
                        .themedText(.body, color: .textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, theme.spacing(.l))
                }
            }
            .padding(.vertical, theme.spacing(.xs))
        }
        .accessibilityIdentifier("workspace-picker-list")
    }

    private var filtered: [String] {
        guard !filter.isEmpty else { return boards }
        return boards.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    private func row(_ path: String) -> some View {
        let name = WorkspaceBoardResolver.fileName(of: path)
        let isAssigned = WorkspaceBoardResolver.matches(path, workspacePath: task.workspacePath)
        return Button {
            assign(name)
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "rectangle.3.group")
                    .foregroundStyle(theme.color(isAssigned ? .accentPrimary : .textTertiary))
                Text(Self.displayName(of: path))
                    .themedText(.body, color: isAssigned ? .accentPrimary : .textPrimary)
                    .lineLimit(1)
                Spacer(minLength: theme.spacing(.xs))
                Text(folder(of: path))
                    .themedText(.caption, color: .textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, theme.spacing(.m))
            .padding(.vertical, theme.spacing(.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workspace \(Self.displayName(of: path))")
        .accessibilityIdentifier("workspace-picker-row-\(path)")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            // Clearing is the other half of "exactly one Workspace" (R-03): without it a
            // marker written by mistake could only be removed by editing the note.
            if task.workspacePath != nil {
                Button("Togli il Workspace") { assign(nil) }
                    .accessibilityIdentifier("workspace-picker-clear")
            }
            Spacer()
            Button("Chiudi", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(theme.spacing(.m))
    }

    // MARK: Writing

    private func assign(_ name: String?) {
        vault.apply(.workspace(name), to: task)
        onClose()
    }

    /// What the row reads: the file name without `.canvas`, which is how the Workspace
    /// pane names the same board.
    private static func displayName(of path: String) -> String {
        (WorkspaceBoardResolver.fileName(of: path) as NSString).deletingPathExtension
    }

    /// The folder the board sits in, so two boards of the same name are told apart.
    private func folder(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }
}
