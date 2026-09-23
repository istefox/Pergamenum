import SwiftUI

/// The banner shown when the note on disk moved on while it was being edited.
///
/// Lifted out of `VaultBrowser` when the find bar arrived and the file went past the length
/// the linter allows. It is the natural piece to move: it is one self-contained strip with
/// two buttons and no state, and it is the only part of that view that is about the file
/// rather than about the editor.
extension EditorColumnView {
    var conflictBanner: some View {
        HStack(spacing: theme.spacing(.s)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.color(.taskOverdue))
            Text("La nota è cambiata su disco mentre la stavi modificando.")
                .themedText(.caption)
            Spacer()
            // `focused { }` first, like every other action in this file (`EditorColumnView
            // .focused(_:)`): since ADR-0056 the banner can appear in a column that is not
            // the one with the focus, and `acceptExternalChange`/`keepLocalVersion` both act
            // on the focused tab.
            Button("Ricarica da disco") { focused(vault.acceptExternalChange) }
            Button("Tieni la mia versione") { focused(vault.keepLocalVersion) }
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.accentMuted))
    }
}
