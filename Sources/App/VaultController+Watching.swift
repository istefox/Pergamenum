import Foundation

/// Keeping up with changes made outside the app (SPEC §12, watcher FSEvents).
///
/// The index side is on `VaultSession` (ADR-0007 §D3). What is left here is the
/// editor's answer to a note that changed underneath it, which is the one decision an
/// app has to make and a command-line tool does not.
extension VaultController {
    func startWatching(_ url: URL) {
        let watcher = VaultWatcher(root: url) { [weak self] paths in
            Task { @MainActor [weak self] in
                await self?.reconcile(paths)
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Applies external changes, and puts the editor in front of the ones it is showing.
    ///
    /// ADR-0043 §D3: `session.reconcile` moved its per-path read off the main actor and
    /// into `VaultDisk`, so this is `async` now. The call above is already inside
    /// `Task { @MainActor … }`, so this costs no new asynchrony at that call site.
    ///
    /// Every tab showing the path, in every column - not only the focused one. Reading
    /// `openNote` here dropped an external change to a note open in a background tab or in
    /// the other column: no reload when clean, no conflict banner when dirty, and the next
    /// save overwrote the change (`PG-211`, #415; named by ADR-0055 §D5).
    ///
    /// A file gone from disk (ADR-0061 §D4): a dirty tab gets the prompt like any change, a
    /// clean one answers `.vanished` and is closed afterwards - ids first, then close, since
    /// closing shifts the indices `updateTabs` walks. `closeTabs(_:ofVanishedNote:)` runs for
    /// every deletion, even with no clean tab, so the closed and recent lists never keep a row
    /// that opens nothing. `didChangeExternally` fires for every change, a deletion included,
    /// once the tabs are settled: that call is all the Diario pane needs (R-01).
    func reconcile(_ paths: [String]) async {
        guard let session else { return }

        for change in await session.reconcile(paths) {
            var vanished: [NoteTab.ID] = []
            // Never merge, never discard: ask - the rule `catchUp(to:)` holds (ADR-0058 §D1).
            updateTabs(showing: change.path) { tab in
                if tab.note.catchUp(to: change.content) == .vanished {
                    vanished.append(tab.id)
                }
            }
            if change.content == .deleted {
                closeTabs(vanished, ofVanishedNote: change.path)
            }
            didChangeExternally?(change.path)
        }
    }
}
