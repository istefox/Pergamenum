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
        // `navigation.revealFolder(_:)` rather than a local method: the Note tree's
        // `expanded`/`selectedRows` are `NoteListPane`'s own private `@State`, so this bar
        // has no reference to open a row through - the same reason `jumpToOutlineEntry`
        // exists for the outline instead of a direct call into the editor.
        //
        // An explicit identifier on every segment, distinct from the visible label
        // (2026-08-28, recovery checkpoint): the bare root crumb reads "Note", byte-identical
        // to the pane switcher's own `staticTexts["Note"]` row
        // (`WorkspaceIntegrationUITests.openPane`), and with no identifier of its own a
        // `Text` answers a lookup by its label - that ambiguity is what broke
        // `testSendingANoteFromAFolderWithNoBoardsToTheWorkspace…` the first time the full UI
        // suite ran after this bar shipped.
        BreadcrumbBar(
            segments: vault.breadcrumb,
            isUnsaved: vault.openNote?.hasUnsavedChanges == true,
            identifierPrefix: "breadcrumb-crumb",
            onSelectAncestor: { navigation.revealFolder($0) }
        ) {
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
    }
}
