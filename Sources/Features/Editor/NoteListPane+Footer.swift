import SwiftUI

/// What sits under the list of notes in the sidebar: the open note's index, and the
/// strip that says how big the vault is.
///
/// In a file of its own for the reason `VaultBrowser+Editor` exists: `NoteListPane`
/// carries the folder tree, the flat list, renaming and deleting, and adding the index
/// to it took the file past the length SwiftLint warns at.
extension NoteListPane {
    /// The index and the status strip, in that order, each with its own rule.
    ///
    /// The index appears only when a note is open *and on screen* - there is nothing to
    /// index otherwise - and says so when the note has no headings rather than showing an
    /// empty box. The second half of that condition was missing until PG-027: with the
    /// composer covering the editor, the index listed the headings of a note nobody could
    /// see.
    @ViewBuilder
    var footer: some View {
        if let note = vault.openNote, vault.isOpenNoteVisible {
            Divider()
            OutlinePane(
                entries: NoteOutline.entries(in: note.text),
                onSelect: navigation.jumpToOutlineEntry(range:ordinal:),
                text: note.text
            )
            // A share of the pane rather than half of it: the index is for finding your
            // way inside the open note, and the list of notes is how you got there.
            // `maxHeight` and not `height`, so a note with two headings takes two rows.
            .frame(maxHeight: 240)
        }
        Divider()
        statusBar
    }

    // MARK: Status

    var statusBar: some View {
        HStack(spacing: theme.spacing(.xs)) {
            if vault.isScanning {
                ProgressView().controlSize(.small)
                Text("Scansione…").themedText(.caption, color: .textSecondary)
            } else {
                Text("\(vault.index.count) note").themedText(.caption, color: .textSecondary)
                if vault.index.lastScanDuration > .zero {
                    Text("· \(scanDurationText)").themedText(.caption, color: .textTertiary)
                }
            }
            Spacer()
            if !vault.index.failures.isEmpty {
                Label("\(vault.index.failures.count)", systemImage: "exclamationmark.triangle")
                    .themedText(.caption, color: .taskOverdue)
                    .help(vault.index.failures.joined(separator: "\n"))
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
    }

    /// Reported so the in-memory index decision of ADR-0001 can be revisited on a
    /// measurement rather than on a guess.
    var scanDurationText: String {
        let milliseconds = vault.index.lastScanDuration.components.attoseconds / 1_000_000_000_000_000
        let seconds = vault.index.lastScanDuration.components.seconds
        return seconds > 0 ? "\(seconds),\(milliseconds / 100) s" : "\(milliseconds) ms"
    }
}
