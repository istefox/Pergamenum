import SwiftUI

/// The banner shown when the note on disk moved on, or went away, while it was being edited.
///
/// Lifted out of `VaultBrowser` when the find bar arrived and the file went past the length
/// the linter allows. It is the natural piece to move: it is one self-contained strip with
/// two buttons and no state, and it is the only part of that view that is about the file
/// rather than about the editor.
///
/// **What it says is decided elsewhere (ADR-0061 §D5).** The message and both labels come from
/// `ConflictBannerCopy`, built from the pending change of *this column's* tab - a text change
/// offers «Ricarica da disco», a deletion «Scarta ed elimina», and the view only renders that.
/// The strings go through `LocalizedStringKey` so they stay localizable like the literals they
/// replaced.
extension EditorColumnView {
    func conflictBanner(_ pending: VaultSession.ExternalChange.Content) -> some View {
        let copy = ConflictBannerCopy(pending: pending)
        return HStack(spacing: theme.spacing(.s)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.color(.taskOverdue))
            Text(LocalizedStringKey(copy.message))
                .themedText(.caption)
            Spacer()
            // `focused { }` first, like every other action in this file (`EditorColumnView
            // .focused(_:)`): since ADR-0056 the banner can appear in a column that is not
            // the one with the focus, and `acceptExternalChange`/`keepLocalVersion` both act
            // on the focused tab.
            Button(LocalizedStringKey(copy.acceptLabel)) { focused(vault.acceptExternalChange) }
            Button(LocalizedStringKey(copy.keepLabel)) { focused(vault.keepLocalVersion) }
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.accentMuted))
    }
}
