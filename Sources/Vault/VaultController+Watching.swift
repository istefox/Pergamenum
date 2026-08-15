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
                self?.reconcile(paths)
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Applies external changes, and puts the editor in front of the ones it is showing.
    func reconcile(_ paths: [String]) {
        guard let session else { return }

        for change in session.reconcile(paths) {
            guard var note = openNote, note.relativePath == change.path else { continue }
            if note.hasUnsavedChanges {
                // Never merge, never discard: ask.
                note.externalChangePending = change.text
            } else {
                note.text = change.text
                note.savedText = change.text
            }
            replaceOpenNote(note)
        }
    }
}
