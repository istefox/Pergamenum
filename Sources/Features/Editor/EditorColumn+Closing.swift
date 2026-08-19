import SwiftUI

/// Closing a tab that has unsaved edits (ADR-0012 D3).
///
/// In a file of its own for the reason `EditorColumn+Text` exists: the tab bar took the view
/// past the length SwiftLint warns at. The question itself is small and the reason for it is
/// not - with one note open, explicit saving was safe because the buffer was in front of you;
/// with six tabs the third one closes with work in it nobody has looked at since.
extension EditorColumnView {
    /// What a column with no tabs shows. Here rather than in `VaultBrowser` because it is
    /// now the empty *tab set*, not the pane's own empty state.
    var emptyState: some View {
        VStack(spacing: theme.spacing(.s)) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(theme.color(.textTertiary))
            Text("Nessuna nota aperta").themedText(.body, color: .textSecondary)
            Text("Cmd+O per il quick switcher").themedText(.caption, color: .textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color(.backgroundPrimary))
    }

    /// Asks only when there is something to lose; a clean tab closes on the click.
    func requestClose(_ tab: NoteTab) {
        if tab.note.hasUnsavedChanges {
            closing = tab
        } else {
            focused { vault.closeTab(tab.id) }
        }
    }

    /// Saves the tab being closed, which means focusing it first: the save writes the focused
    /// buffer, and the tab under the pointer is not necessarily the one in front.
    func closeAfterSaving() {
        guard let tab = closing else { return }
        closing = nil
        focused {
            vault.focusTab(tab.id)
            vault.saveOpenNote()
            vault.closeTab(tab.id)
        }
    }

    func closeDiscarding() {
        guard let tab = closing else { return }
        closing = nil
        focused { vault.closeTab(tab.id) }
    }
}

/// The dialog, as a modifier so the pane's `body` stays about the pane.
struct UnsavedTabDialog: ViewModifier {
    @Binding var closing: NoteTab?
    let column: EditorColumnView

    func body(content: Content) -> some View {
        content.confirmationDialog(
            closing.map { "Salvare le modifiche a «\($0.note.title)»?" } ?? "",
            isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
            titleVisibility: .visible
        ) {
            // Three buttons and a title, the way macOS asks a document this question. Annulla
            // is the safe one in the literal sense: it changes nothing, so the tab stays and
            // so does the work.
            Button("Salva") { column.closeAfterSaving() }
            Button("Non salvare", role: .destructive) { column.closeDiscarding() }
            Button("Annulla", role: .cancel) { closing = nil }
        } message: {
            Text("Chiudendo la tab senza salvare, le modifiche vanno perse.")
        }
    }
}
