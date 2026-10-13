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
            // The rows, the caret's entry and the folds are read here, so the pane holds none of
            // them as observed state, and `.equatable()` skips its body when they are what they
            // were (ADR-0096 §D7). The store answers for the revision the note is at, and parses
            // the note's own text only when it does not describe it yet. A column with no
            // registered store gets an empty one, which describes no revision and so answers from
            // the text: a registry miss costs a parse, never the index, and the body registers
            // nothing.
            let store = focusedOutlineStore ?? OutlineStore()
            let answer = store.rows(describing: note.revision, text: note.text)
            OutlinePane(
                inputs: OutlinePaneInputs(
                    rows: answer.rows,
                    source: answer.source,
                    notePath: note.relativePath,
                    currentEntry: vault.currentOutlineEntry,
                    foldedOrdinals: store.foldedOrdinals(
                        ofOffsets: vault.foldedEntries, describing: note.revision, text: note.text
                    )
                ),
                onSelect: { ordinal in selectOutlineEntry(ordinal, from: store) },
                onToggleFold: { ordinal in toggleOutlineFold(ordinal, from: store) },
                moveReplacements: { moving, target in outlineMoveReplacements(moving: moving, to: target) },
                onMove: navigation.moveOutlineSection
            )
            .equatable()
            // A share of the pane rather than half of it: the index is for finding your
            // way inside the open note, and the list of notes is how you got there.
            // `maxHeight` and not `height`, so a note with two headings takes two rows.
            .frame(maxHeight: 240)
        }
        Divider()
        statusBar
    }

    /// The focused column's outline store, the one its editor feeds.
    private var focusedOutlineStore: OutlineStore? {
        guard vault.columns.indices.contains(vault.focusedColumnIndex) else { return nil }
        return vault.registeredOutlineStore(forColumn: vault.columns[vault.focusedColumnIndex].id)
    }

    /// `store` when it describes `note`, otherwise one read from the note's text: what a click
    /// resolves against. Static, so it reads no view state: the note is the one the caller read when
    /// the click happened, and the parse it may cost is paid there, never per body.
    private static func store(_ store: OutlineStore, describing note: VaultController.OpenNote?) -> OutlineStore? {
        guard let note else { return nil }
        return store.describes == note.revision ? store : OutlineStore(text: note.text)
    }

    /// A click on a row: the editor scrolls to the entry's line.
    private func selectOutlineEntry(_ ordinal: Int, from store: OutlineStore) {
        let resolved = Self.store(store, describing: vault.openNote)
        guard let range = resolved?.lineRange(ofEntry: ordinal) else { return }
        navigation.jumpToOutlineEntry(range: range, ordinal: ordinal)
    }

    /// The chevron or a double-click: folds the section by its heading's offset, the key
    /// `NoteTab.foldedEntries` keeps.
    private func toggleOutlineFold(_ ordinal: Int, from store: OutlineStore) {
        let resolved = Self.store(store, describing: vault.openNote)
        guard let offset = resolved?.foldableOffset(ofEntry: ordinal) else { return }
        vault.toggleFold(offset)
    }

    /// A drag's validity and its drop, over the note's text as it is when asked.
    private func outlineMoveReplacements(
        moving entry: Int, to target: OutlinePane.MoveTarget
    ) -> [(range: NSRange, text: String)]? {
        guard let text = vault.openNote?.text else { return nil }
        switch target {
        case .nestingUnder(let heading):
            return OutlineMove.replacements(in: text, moving: entry, nestingUnder: heading)
        case .toPrecede(let destination):
            return OutlineMove.replacements(in: text, moving: entry, toPrecede: destination)
        }
    }

    // MARK: Status

    var statusBar: some View {
        HStack(spacing: theme.spacing(.xs)) {
            if vault.isScanning {
                ProgressView().controlSize(.small)
                Text("Scansione…").themedText(.caption, color: .textSecondary)
            } else {
                Text("\(vault.index.count) note").themedText(.caption, color: .textSecondary)
                    // Drawn only once no scan is running: what a UI test waits on before it
                    // searches a large vault (`GlobalSearchUITests`).
                    .accessibilityIdentifier("vault-note-count")
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
