import SwiftUI

/// The inspector's own way into a note's version history, and the sheet it opens
/// (ADR-0011, M9).
///
/// Lifted out of `VaultBrowser` for the same reason `VaultBrowser+Conflict` was: the
/// file went past the length the linter allows the moment this arrived. It is a clean
/// seam anyway - one self-contained section, one sheet, and the only read in the
/// inspector that touches `.pergamenum/` rather than the index.
extension VaultBrowser {
    /// The entry point that makes the feature findable by someone who does not know it
    /// exists. The menu command does the same job faster for someone who does; both
    /// ship, because neither covers the other's case (mockup approved 2026-08-18).
    ///
    /// Reads dates only, never texts: this runs on every pass of the inspector's body,
    /// and `snapshots(for:)` would open every version of the note to print two numbers.
    func history(_ note: VaultController.OpenNote) -> some View {
        let dates = vault.session?.history.snapshotDates(for: note.relativePath) ?? []
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("CRONOLOGIA").themedText(.caption, color: .textTertiary)
            if let latest = dates.first {
                Text(Self.historySummary(count: dates.count, latest: latest))
                    .themedText(.caption, color: .textSecondary)
                Button("Sfoglia…") { vault.isShowingHistory = true }
                    .buttonStyle(.plain)
                    .themedText(.body, color: .accentPrimary)
            } else {
                Text("nessuna").themedText(.caption, color: .textTertiary)
            }
        }
    }

    static func historySummary(count: Int, latest: Date) -> String {
        let noun = count == 1 ? "versione" : "versioni"
        return "\(count) \(noun), l'ultima alle \(HistoryGrouping.time(for: latest))"
    }

}

/// The sheet's presentation, as a modifier rather than a `.sheet` in `VaultBrowser`'s
/// own body: that file sits one line under the length the linter allows, and this is
/// the half of the feature it does not otherwise need to know about.
///
/// The snapshots are read inside the closure, so the call that opens every version of
/// the note happens when the sheet is presented and never on an ordinary pass of the
/// browser's body.
struct HistorySheetPresentation: ViewModifier {
    @Environment(VaultController.self) private var vault

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { vault.isShowingHistory },
            set: { vault.isShowingHistory = $0 }
        )) {
            NoteHistorySheet(
                noteTitle: vault.openNote?.title ?? "",
                snapshots: snapshots,
                onRestore: { text in
                    vault.restoreVersion(text)
                    vault.isShowingHistory = false
                },
                onClose: { vault.isShowingHistory = false }
            )
        }
    }

    private var snapshots: [NoteHistory.Snapshot] {
        guard let session = vault.session, let note = vault.openNote else { return [] }
        return session.history.snapshots(for: note.relativePath)
    }
}
