import SwiftUI

/// The Note pane's chrome above everything else: breadcrumb and save state, the same row
/// `BoardTopBar` draws for the Workspace (`Sources/Features/Workspace/BoardChrome.swift:15-80`,
/// SPEC §6.1), mirrored here for the Note side (2026-08-28, toolbar/breadcrumb parity chain).
///
/// Sits above `NoteListPane` and the editor both, not inside either - the same reason
/// `BoardTopBar` sits above `WorkspaceBrowser` and the canvas: it is one strip for the whole
/// pane, not furniture belonging to one column of it.
struct VaultTopBar: View {
    @Environment(\.theme) private var theme
    let vault: VaultController
    let navigation: Navigation

    var body: some View {
        let crumbs = vault.breadcrumb
        return HStack(spacing: theme.spacing(.xs)) {
            Circle()
                .fill(theme.color(
                    vault.openNote?.hasUnsavedChanges == true ? .taskScheduled : .accentPrimary
                ))
                .frame(width: 8, height: 8)

            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("›").themedText(.body, color: .textTertiary)
                }
                if index == crumbs.count - 1 {
                    // The last segment is the note itself (or the bare root with nothing
                    // open) - not a link, the same reason `BoardTopBar`'s own last segment
                    // is not one (ADR-0024 §D8.2): it is where you already are.
                    Text(crumb.title).themedText(.body, color: .textPrimary)
                } else {
                    // `navigation.revealFolder(_:)` rather than a local method: the Note
                    // tree's `expanded`/`selectedRows` are `NoteListPane`'s own private
                    // `@State`, so this bar has no reference to open a row through - the
                    // same reason `jumpToOutlineEntry` exists for the outline instead of a
                    // direct call into the editor.
                    Button(crumb.title) { navigation.revealFolder(crumb.folder) }
                        .buttonStyle(.plain)
                        .themedText(.body, color: .textSecondary)
                }
            }

            Spacer()

            // Only with a note open: unlike `WorkspaceController`, which carries a stored
            // `hasUnsavedChanges` that reads `false` at rest even with nothing loaded,
            // there is no save state to report here until a note exists to have one -
            // showing "Salvato" over an empty pane would claim to have saved nothing.
            if vault.openNote != nil {
                Label(
                    vault.openNote?.hasUnsavedChanges == true ? "Salvataggio…" : "Salvato",
                    systemImage: vault.openNote?.hasUnsavedChanges == true
                        ? "arrow.triangle.2.circlepath" : "checkmark.circle"
                )
                .themedText(.caption, color: .textSecondary)
            }
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
    }
}
